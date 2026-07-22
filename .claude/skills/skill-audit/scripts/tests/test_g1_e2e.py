"""G1 end-to-end test (Task 22 / #22).

End-to-end here means: drive ``audit.py main()`` through the same call
path the shell wrapper uses, against real fixture files in
``testdata/g1-fixtures/``, with a mocked ``llm_dispatch`` so no API key
is required. Real-LLM integration is validated in Task 6 dogfood.

Scope (test plan items 4-7, 11-12 of CONTEXT.md):
  * audit.py G1 wire calls detect() with ``corpus_dir=`` (not legacy
    ``cross=``) — verified via spy + by direct invocation through main().
  * fixture corpus produces >= 1 MED finding for the a/b paraphrase pair
    under a mock dispatch that returns is_paraphrased=True only for the
    a/b cross-file pair.
  * c-unrelated stays out of the a/b finding's locations.
  * Single-path G1 invocation (no --cross) hits ValueError -> friendly
    stderr hint -> exit 1.
  * expected.yaml structure matches the produced finding shape on the
    fields the schema documents.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Put scripts/ on sys.path so we can import ``audit`` and ``detectors``.
_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import semantic_audit as audit  # noqa: E402
from detectors import g1_cross_skill_dup as g1  # noqa: E402
from detectors import g8_progressive_disclosure as g8  # noqa: E402

_FIXTURES = (_SCRIPTS.parent / "testdata" / "g1-fixtures").resolve()
_SKILL_A = _FIXTURES / "skill-a-debfactory.md"
_SKILL_B = _FIXTURES / "skill-b-debfactory.md"
_SKILL_C = _FIXTURES / "skill-c-unrelated.md"
_EXPECTED = _FIXTURES / "expected.yaml"


def _mk_pair_dispatch(*basenames: str):
    """Return a dispatch callable that flags only the named file pair.

    ``basenames`` are matched as file-basename pairs (order-insensitive).
    Every other pair returns is_paraphrased=False.
    """
    targets = frozenset(basenames)

    def _dispatch(record: dict) -> dict:
        pa, pb = record["paragraph_a"], record["paragraph_b"]
        names = frozenset({os.path.basename(pa["file"]),
                           os.path.basename(pb["file"])})
        is_para = names == targets
        return {
            "is_paraphrased": is_para,
            "confidence": "medium" if is_para else "low",
            "evidence_a": pa["lines"],
            "evidence_b": pb["lines"],
            "reasoning": "mock-e2e",
        }
    return _dispatch


# ---- fixture presence -------------------------------------------------------

def test_fixtures_exist():
    for p in (_SKILL_A, _SKILL_B, _SKILL_C, _EXPECTED):
        assert p.exists(), p


def test_fixtures_have_candidate_paragraphs():
    """a/b each have one >=30-word candidate; c has at least one too."""
    for path, expected_min in ((_SKILL_A, 1), (_SKILL_B, 1), (_SKILL_C, 1)):
        cands = [p for p in g1._parse_paragraphs(str(path)) if p.is_candidate]
        assert len(cands) >= expected_min, (path, cands)


# ---- detector against fixture corpus ---------------------------------------

def test_ab_pair_emits_med_finding():
    """skill-a + skill-b paraphrase pair fires MED (2 skills + >= 10 lines)."""
    findings = g1.detect(
        [str(_SKILL_A), str(_SKILL_B)],
        llm_dispatch=_mk_pair_dispatch("skill-a-debfactory.md",
                                       "skill-b-debfactory.md"),
    )
    assert len(findings) == 1
    f = findings[0]
    assert f["axis"] == "G1"
    assert f["severity"] == "MED"
    assert f["confidence"] == "medium"
    files = {os.path.basename(loc["file"]) for loc in f["locations"]}
    assert files == {"skill-a-debfactory.md", "skill-b-debfactory.md"}
    assert f["requires_human"] is True
    assert f["numeric_basis"] is None


def test_unrelated_skill_c_excluded_from_finding():
    """When dispatch only flags a/b, skill-c stays out of locations even when
    in the corpus."""
    findings = g1.detect(
        [str(_SKILL_A)],
        corpus_dir=str(_FIXTURES),
        llm_dispatch=_mk_pair_dispatch("skill-a-debfactory.md",
                                       "skill-b-debfactory.md"),
    )
    assert len(findings) == 1
    files = {os.path.basename(loc["file"]) for loc in findings[0]["locations"]}
    assert "skill-c-unrelated.md" not in files


def test_finding_has_all_required_schema_fields():
    """finding-schema.md L7-19 required-field set, against a fixture finding."""
    findings = g1.detect(
        [str(_SKILL_A), str(_SKILL_B)],
        llm_dispatch=_mk_pair_dispatch("skill-a-debfactory.md",
                                       "skill-b-debfactory.md"),
    )
    required = {"id", "axis", "severity", "confidence", "title", "summary",
                "locations", "evidence_quote", "suggested_action",
                "requires_human", "numeric_basis"}
    assert required.issubset(findings[0].keys())


def test_expected_yaml_aligns_with_produced_finding():
    """expected.yaml documents the contract; verify produced finding matches."""
    yaml = pytest.importorskip("yaml")
    spec = yaml.safe_load(_EXPECTED.read_text(encoding="utf-8"))
    expected_finding = spec["findings"][0]

    findings = g1.detect(
        [str(_SKILL_A), str(_SKILL_B)],
        llm_dispatch=_mk_pair_dispatch("skill-a-debfactory.md",
                                       "skill-b-debfactory.md"),
    )
    f = findings[0]
    assert f["axis"] == expected_finding["axis"]
    assert f["severity"] == expected_finding["severity"]
    assert f["confidence"] == expected_finding["confidence"]
    assert f["requires_human"] is expected_finding["requires_human"]
    assert f["numeric_basis"] == expected_finding["numeric_basis"]
    produced_files = {os.path.basename(loc["file"]) for loc in f["locations"]}
    assert produced_files == set(expected_finding["locations_files"])


# ---- audit.py CLI route (via main, no subprocess) --------------------------

def test_audit_main_g1_single_path_friendly_hint(capsys):
    """audit.py with --axis G1 and only one path (< 2 candidate paras) -> hint + exit 2 (clean).

    "Not enough qualifying content to analyze" is an advisory N/A condition, not a
    tool failure: it must exit 2 (clean) so run.sh does not falsely propagate
    any_error on a skill whose reference files are short. The friendly hint still
    prints to stderr. (Previously exited 1 — that was a bug; run.sh treats rc=1 as
    an engine error.) Genuine errors (bad --cross dir, unreadable file, exception)
    still exit 1.
    """
    rc = audit.main([str(_SKILL_A), "--axis", "G1"])
    assert rc == 2
    err = capsys.readouterr().err
    assert "fewer than 2 candidate paragraphs" in err


def test_g1_insufficient_content_raises_typed_exception(tmp_path):
    """The < 2-candidate-paragraph case raises G1InsufficientContentError (a typed
    ValueError subclass), NOT a bare ValueError — so semantic_audit.py can
    discriminate the N/A case from a genuine corpus_dir error without string
    matching the message."""
    a = tmp_path / "a.md"
    a.write_text("# tiny\n\nshort.\n", encoding="utf-8")
    with pytest.raises(g1.G1InsufficientContentError):
        g1.detect([str(a)])


def test_g1_insufficient_content_is_value_error_subclass():
    """G1InsufficientContentError must subclass ValueError so existing
    `except ValueError` callers keep working (back-compat)."""
    assert issubclass(g1.G1InsufficientContentError, ValueError)


def test_corpus_dir_invalid_stays_plain_value_error(tmp_path):
    """An invalid --cross dir is a genuine bad-arg error: it must raise a plain
    ValueError (NOT the typed N/A subclass) so main() keeps exiting 1 for it."""
    a = tmp_path / "a.md"
    a.write_text("# h\n\n" + ("word " * 40) + "\n", encoding="utf-8")
    with pytest.raises(ValueError) as ei:
        g1.detect([str(a)], corpus_dir=str(tmp_path / "does-not-exist"))
    assert not isinstance(ei.value, g1.G1InsufficientContentError)


def test_audit_main_corpus_dir_invalid_exits_one(capsys, tmp_path):
    """audit.py with an invalid --cross dir exits 1 (genuine error, not N/A)."""
    rc = audit.main([str(_SKILL_A), "--cross",
                     str(tmp_path / "nope"), "--axis", "G1"])
    assert rc == 1


def test_audit_main_g1_na_continues_to_g8(capsys):
    """REGRESSION (code-review Finding 1, HIGH): when G1 hits the N/A
    insufficient-content condition under --axis all, the axis loop must
    `continue` to G8 — NOT `return` — so G8 still runs.

    Proof (real path, not a call-count mock): patch G8 to return a genuine
    finding, run --axis all on a skill where G1 is N/A, and assert the G8
    finding reaches stdout. That can only happen if the loop reached G8 after
    G1's N/A AND aggregated + rendered its findings — the exact path the bug
    short-circuited.
    """
    g8_finding = {
        "id": "G8-test-1", "axis": "G8", "severity": "MED",
        "confidence": "high", "title": "g8-sentinel",
        "summary": "g8 ran after g1 na", "locations": [],
        "evidence_quote": "", "suggested_action": "",
        "requires_human": False, "numeric_basis": {},
    }
    with patch.object(g8, "detect", return_value=[g8_finding]):
        rc = audit.main([str(_SKILL_A), "--axis", "all", "--no-llm"])
    out = capsys.readouterr().out
    assert rc == 0, "G8 returned a real finding -> exit 0 (flagged)"
    assert "g8-sentinel" in out, (
        f"G8 was silently skipped after G1 N/A — coverage hole.\n{out!r}"
    )


def test_audit_main_default_axis_g1_na_g8_clean_exits_2(capsys, tmp_path):
    """The exact assembled path the integration test exercises: DEFAULT axis
    (no --axis flag -> G1+G8), G1 N/A (insufficient content) AND G8 clean ->
    exit 2 (clean). No patching — both detectors run for real.

    Existing coverage either uses --axis G1 alone or patches G8 to return a
    finding; neither locks the all-clean default-axis exit. A short SKILL.md
    (< 2 candidate paragraphs >= 30 words, no inline changelog) drives G1 to the
    N/A condition while G8 finds nothing -> the only correct exit is 2. If G1's
    N/A wrongly propagated as an error (exit 1) or G8 short-circuited, run.sh
    would mis-flag any_error; this test pins exit 2 at the unit level.
    """
    skill = tmp_path / "SKILL.md"
    skill.write_text(
        "---\nname: tiny-skill\ndescription: A tiny skill for testing.\n---\n\n"
        "# tiny-skill\n\nShort body. Nothing here.\n",
        encoding="utf-8",
    )
    rc = audit.main([str(skill), "--no-llm"])
    assert rc == 2, "G1 N/A + G8 clean on default axis must exit 2 (clean)"
    err = capsys.readouterr().err
    assert "fewer than 2 candidate paragraphs" in err


def test_audit_main_g1_dispatches_with_corpus_dir(capsys):
    """audit.py routes --cross to detect()'s corpus_dir= kwarg (not cross=)."""
    seen = {}

    def _spy(paths, **kwargs):
        seen["paths"] = list(paths)
        seen["kwargs"] = dict(kwargs)
        # Return [] so main() proceeds to the unreachable stub return.
        return []

    with patch.object(g1, "detect", side_effect=_spy):
        audit.main([str(_SKILL_A), "--cross", str(_FIXTURES), "--axis", "G1"])

    assert seen["paths"] == [str(_SKILL_A)]
    # The audit.py wire MUST use corpus_dir= (not legacy cross=).
    assert "corpus_dir" in seen["kwargs"]
    assert seen["kwargs"]["corpus_dir"] == str(_FIXTURES)
    assert "cross" not in seen["kwargs"]


def test_audit_main_g1_missing_file_exit_1(capsys):
    """Non-existent SKILL.md path -> exit 1 + stderr."""
    rc = audit.main(["/no/such/file.md", "--axis", "G1"])
    assert rc == 1
    assert "input not found" in capsys.readouterr().err
