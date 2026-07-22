"""Regression tests for function-level qualified/self/dunder edges (design 2026-06-21).

reachability.py flagged 14 live functions (c) because `function_called`'s negative
lookbehind excludes every dot-qualified position, missing module-alias calls
(`M.compute_size(...)`) and attribute/property access (`self.is_candidate`). These
tests pin the fix to TWO exact qualifiers only (in-skill module alias + `self`)
plus a dunder->ADVISORY demotion, and lock the collision guard that keeps an
unresolved qualifier from marking a dead in-skill same-named function live.
"""
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1] / "reachability.py"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "py-edge-fn-skill"
REPO = Path(__file__).resolve().parents[3]


def _run(skill_dir):
    r = subprocess.run([sys.executable, str(ENGINE), str(skill_dir)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _flagged(out, cls):
    names = set()
    marker = f"({cls})"
    for line in out.splitlines():
        if marker in line and "|" in line:
            cells = [c.strip().strip("`") for c in line.split("|")]
            if len(cells) >= 6 and cells[1].startswith(marker):
                names.add(cells[4])
    return names


def _flagged_c(out):
    return _flagged(out, "c")


def _flagged_adv(out):
    return _flagged(out, "adv")


# ---------------------------------------------------------------------------
# Case 1: module-alias-qualified call edge
# ---------------------------------------------------------------------------

def test_module_alias_call_is_live():
    """`from advisory import metrics as M` + `M.compute_size(...)` -> compute_size
    NOT (c)."""
    _, out, _ = _run(FIXTURE)
    assert "compute_size" not in _flagged_c(out)


def test_unaliased_dead_fn_stays_c():
    """metrics.dead_fn is defined but never called via any alias -> still (c)
    (no over-suppression)."""
    _, out, _ = _run(FIXTURE)
    assert "dead_fn" in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 2: self method + property
# ---------------------------------------------------------------------------

def test_self_method_and_property_are_live():
    """`@property is_candidate` accessed `self.is_candidate` and method `bump`
    called `self.bump(...)` in another method of the same class -> both NOT (c)."""
    _, out, _ = _run(FIXTURE)
    c = _flagged_c(out)
    assert "is_candidate" not in c
    assert "bump" not in c


def test_unused_property_stays_c():
    """`@property never_used` never accessed -> still (c) (no over-suppression)."""
    _, out, _ = _run(FIXTURE)
    assert "never_used" in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 3: dunder -> ADVISORY demotion
# ---------------------------------------------------------------------------

def test_dunder_invoked_implicitly_is_advisory_not_c():
    """`__contains__` invoked only via `x in obj` (no explicit `.__contains__(`)
    -> NOT (c) HIGH, IS ADVISORY (adv)."""
    _, out, _ = _run(FIXTURE)
    assert "__contains__" not in _flagged_c(out)
    assert "__contains__" in _flagged_adv(out)


def test_non_dunder_dead_method_stays_c():
    """A non-dunder method with no caller stays (c)."""
    _, out, _ = _run(FIXTURE)
    assert "dead_method" in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 4: collision guard — unresolved qualifier does NOT count
# ---------------------------------------------------------------------------

def test_unresolved_qualifier_does_not_mark_inskill_dead_live():
    """`x = open(...)` then `x.read()` where `x` is NOT an in-skill module alias,
    AND advisory/reader.py defines a dead module-level `def read` -> in-skill
    `read` STILL (c) (the unresolved qualifier must not count as an edge)."""
    _, out, _ = _run(FIXTURE)
    assert "read" in _flagged_c(out)


# ---------------------------------------------------------------------------
# Case 5: regression on the real audit-family skills
# ---------------------------------------------------------------------------

def _skip_if_absent(name):
    import pytest
    d = REPO / name
    if not (d / "SKILL.md").is_file():
        pytest.skip(f"{name} not present")
    return d


def test_syntax_audit_module_alias_fns_not_c():
    """All 9 module-alias-called functions (`M.`/`R.`/`RP.`/`L.` qualifiers, from
    `from advisory import metrics as M` etc) clear (c). bench-m2.sh shell fns stay
    (c) (out of scope, shell)."""
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    for fn in ("compute_size", "compute_imbalance", "compute_staleness",
               "compute_cross_section_hints", "composite_score", "rank_skills",
               "render_markdown", "render_json", "dispatch_llm_audit"):
        assert fn not in c, f"{fn} still falsely (c)"


def test_semantic_audit_self_call_and_dunders():
    """`find` clears via its `self.find(a)` site (case 2). The dunders `__init__`
    and `__contains__` demote to ADVISORY, not (c). `is_candidate`, `line_count`,
    `lines_field` are @property accessors accessed via local vars — cleared by the
    @property fix (design 2026-06-23). `bump` is a plain method (not @property)
    but IS now cleared by instance-method dispatch (design 2026-06-25): the class
    `_OutOfBoundsCounter` that owns `bump` is instantiated, and `counter.bump(`
    occurs in code — accepted over-count."""
    d = _skip_if_absent("skill-audit")
    _, out, _ = _run(d)
    c = _flagged_c(out)
    adv = _flagged_adv(out)
    assert "find" not in c, "find should clear via self.find(a)"
    assert "__init__" not in c and "__init__" in adv
    assert "__contains__" not in c
    # @property members cleared by the property fix (accessed via para./p. local vars)
    for fn in ("is_candidate", "line_count", "lines_field"):
        assert fn not in c, (
            f"{fn} (@property) still (c) — @property fix not applied.")
    # bump is now live via instance-method dispatch (counter.bump(...) in code)
    assert "bump" not in c, (
        "bump should clear via instance-method dispatch (counter.bump(...))")


def test_self_dogfood_still_exits_2():
    """reachability.py on skill-audit still exits 2 (the function-edge
    logic must not make the engine flag its own code)."""
    rc, out, _ = _run(REPO / "skill-audit")
    assert rc == 2, f"self-dogfood not clean (exit {rc}):\n{out}"


# ---------------------------------------------------------------------------
# Case 6: a name inside a single-line quoted string is NOT a call edge
# (string-literal / docstring over-count — issue 2026-06-23 item #2)
# ---------------------------------------------------------------------------

import reachability  # noqa: E402


def test_name_only_in_string_is_not_a_call():
    """A function name mentioned only inside a single-line quoted string (a sibling
    docstring or string literal) is NOT a call edge."""
    assert reachability.function_called("parse", 'x = "see parse() for details"') is False


def test_bare_call_still_counts():
    """A real call on a code line still counts."""
    assert reachability.function_called("parse", "parse()") is True


def test_call_in_expression_still_counts():
    """A real call embedded in an assignment expression still counts."""
    assert reachability.function_called("parse", "result = parse(x)") is True


def test_name_in_comment_still_skipped():
    """A name inside a `#` comment is still skipped (no regression)."""
    assert reachability.function_called("parse", "# call parse() here") is False


def test_call_after_string_on_same_line_still_counts():
    """A genuine call AFTER a closed string on the same line still counts (the
    string-span skip must not swallow the rest of the line)."""
    assert reachability.function_called("parse", 'msg = "hi"; parse(msg)') is True


def test_call_in_fstring_interpolation_still_counts():
    """A call inside an f-string `{...}` interpolation is real code, NOT a string
    mention — it still counts (guards the _yaml_scalar f-string call sites)."""
    assert reachability.function_called("parse", 'out = f"id: {parse(x)}"') is True
