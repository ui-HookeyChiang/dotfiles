"""Unit tests for jira-cli.py fill subcommand.

Covers spec § "Failure mode handling" table (lines 90-97), confab L1/L2
defenses (lines 36-46), telemetry JSONL schema (lines 124-132), and the
flag matrix (--auto, --yes, --edit, --regenerate, --force).

All external dependencies (gh, git, md2adf.py subprocess, Jira REST,
Anthropic LLM) are mocked. Tests run offline.
"""
import importlib.util
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import types
from contextlib import contextmanager
from unittest import mock

import pytest


HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS = HERE.parent
TEMPLATE = SCRIPTS.parent.parent / "_shared" / "references" / "qa-verify-template.md"
ALLOWLIST = SCRIPTS / "confab-allowlist.txt"
JIRA_CLI = SCRIPTS / "jira-cli.py"


def _load_module():
    """Import jira-cli.py as a module under name `jira_cli`."""
    if "jira_cli" in sys.modules:
        del sys.modules["jira_cli"]
    spec = importlib.util.spec_from_file_location("jira_cli", JIRA_CLI)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["jira_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------

@pytest.fixture
def jira_cli():
    """The imported jira-cli.py module."""
    return _load_module()


@pytest.fixture
def tmp_telemetry(tmp_path, monkeypatch):
    """Redirect telemetry + credentials to a tmp dir."""
    cfg = tmp_path / "config" / "ubiquiti"
    cfg.mkdir(parents=True)
    creds = cfg / "jira-credentials"
    creds.write_text(
        "export JIRA_EMAIL=test@example.com\n"
        "export JIRA_TOKEN=tok123\n"
        "export JIRA_BASE_URL=https://example.atlassian.net\n"
    )
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("JIRA_FILL_TELEMETRY", str(cfg / "jira-fill-telemetry.jsonl"))
    monkeypatch.setenv("JIRA_FILL_CREDENTIALS", str(creds))
    return tmp_path


@pytest.fixture
def good_pr_context():
    """A PR with body + commits + branch info, typical happy path inputs."""
    return {
        "pr": {
            "number": 4321,
            "title": "feat(filer): cap statfs by qgroup limit",
            "body": (
                "## Summary\n\nFix btrfs qgroup statfs reporting under NFS/SMB.\n\n"
                "## Why\nQgroup limit was ignored, leading to wrong free space.\n\n"
                "## Test plan\n- run.sh on UNAS Pro\n"
            ),
            "baseRefName": "main",
            "headRefName": "feat/qgroup-cap-statfs",
            "headRefOid": "abc1234deadbeef",
        },
        "commits": (
            "- fix(filer): cap statfs by qgroup\n\n"
            "Patches btrfs_qgroup_cap_statfs to clamp free space.\n"
        ),
    }


@pytest.fixture
def good_jira_issue():
    """A typical empty UOF-1234 task ticket, ready to be filled."""
    return {
        "key": "UOF-1234",
        "fields": {
            "summary": "btrfs qgroup statfs cap",
            "description": None,
            "issuetype": {"name": "Task"},
        },
    }


@pytest.fixture
def mock_llm_response():
    """A clean, allowlist-clean LLM response that should pass L1+L2."""
    return (
        "## Why\n\nFix btrfs qgroup statfs reporting under NFS/SMB.\n\n"
        "## What\n\nClamp statfs free-space by qgroup limit.\n\n"
        "## How to verify\n\n"
        "### Prerequisites\n\n- Bundle: qgst-test-bundle.tgz\n\n"
        "### Step 0 — Download and stage the test bundle\n\n"
        "```\nscp qgst-test-bundle.tgz root@unas-pro:/tmp/\n"
        "ssh root@unas-pro 'cd /tmp && tar -xzf qgst-test-bundle.tgz'\n```\n\n"
        "### Step-by-step verification\n\n"
        "```\nssh root@unas-pro 'cd /tmp/qgst && ./run.sh'\n```\n\n"
        "**Expected:** SUMMARY line printed.\n\n"
        "### Failure handling\n\n"
        "| Failure | Owner |\n|---|---|\n| run.sh fails | filer dev |\n\n"
        "### Cleanup\n\n```\nssh root@unas-pro 'rm -rf /tmp/qgst'\n```\n"
    )


@pytest.fixture(autouse=True)
def _ensure_allowlist_exists():
    """Tests need the allowlist file; if implementation hasn't created it,
    tests fail clearly rather than silently no-op."""
    # We don't create it here — implementation must.
    yield


# ---------------------------------------------------------------------
# Mocking helpers
# ---------------------------------------------------------------------

@contextmanager
def patched_external(
    jira_cli,
    *,
    pr_context,
    issue,
    llm_text,
    put_status=204,
    md2adf_raises=False,
):
    """Patch all external boundaries: subprocess (gh/git/md2adf), HTTP,
    LLM, input()/getpass.
    """
    def fake_run(cmd, *args, **kwargs):
        # Identify call by argv[0..N]
        argv = cmd if isinstance(cmd, list) else cmd.split()
        joined = " ".join(argv)
        cp = types.SimpleNamespace()
        cp.returncode = 0
        cp.stderr = ""
        if argv[0] == "gh" and "pr" in argv and "view" in argv:
            cp.stdout = json.dumps(pr_context["pr"])
        elif argv[0] == "git" and "log" in argv:
            cp.stdout = pr_context["commits"]
        elif argv[0] == "python3" and "md2adf.py" in joined:
            if md2adf_raises:
                cp.returncode = 1
                cp.stderr = "md2adf: WARNING: synthetic error\n"
                cp.stdout = ""
            else:
                cp.stdout = json.dumps({"type": "doc", "version": 1, "content": []})
        else:
            cp.stdout = ""
        return cp

    def fake_http_get(url, **kw):
        resp = mock.MagicMock()
        resp.status_code = 200
        resp.json.return_value = issue
        resp.text = json.dumps(issue)
        return resp

    def fake_http_put(url, **kw):
        resp = mock.MagicMock()
        resp.status_code = put_status
        resp.text = "" if put_status < 400 else '{"errorMessages":["bad"]}'
        return resp

    def fake_llm_call(*args, **kwargs):
        return llm_text

    with mock.patch.object(jira_cli, "subprocess_run", side_effect=fake_run), \
         mock.patch.object(jira_cli, "http_get", side_effect=fake_http_get), \
         mock.patch.object(jira_cli, "http_put", side_effect=fake_http_put), \
         mock.patch.object(jira_cli, "call_llm", side_effect=fake_llm_call):
        yield


# ---------------------------------------------------------------------
# Sanity: implementation files exist
# ---------------------------------------------------------------------

def test_jira_cli_exists():
    assert JIRA_CLI.exists(), f"missing: {JIRA_CLI}"


def test_allowlist_exists():
    assert ALLOWLIST.exists(), f"missing: {ALLOWLIST}"
    binaries = [
        ln.strip() for ln in ALLOWLIST.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]
    for need in ("ssh", "scp", "tar", "ls", "md5sum"):
        assert need in binaries, f"allowlist missing seed: {need}"


def test_template_readable():
    assert TEMPLATE.exists()


# ---------------------------------------------------------------------
# CLI surface
# ---------------------------------------------------------------------

def test_fill_help_exits_zero(jira_cli, capsys):
    with pytest.raises(SystemExit) as exc:
        jira_cli.main(["fill", "--help"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    for flag in ("--auto", "--yes", "--edit", "--regenerate", "--force"):
        assert flag in out


def test_link_stub_raises_not_implemented(jira_cli):
    with pytest.raises(NotImplementedError):
        jira_cli.main(["link", "UOF-1234"])


# ---------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------

def test_happy_path_posts(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 0
    telem = pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
    assert telem.exists()
    line = json.loads(telem.read_text().strip().splitlines()[-1])
    assert line["exit"] == "posted"
    assert line["key"] == "UOF-1234"
    assert line["confab_l1_fail"] is False
    assert line["confab_l2_fail"] is False
    assert line["downgraded_verify"] is False


# ---------------------------------------------------------------------
# Failure modes from spec lines 90-97
# ---------------------------------------------------------------------

def test_refuse_non_empty_description(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    """Real content (non-empty text in a paragraph) refuses without --regenerate."""
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": {
                "type": "doc",
                "content": [
                    {"type": "paragraph", "content": [
                        {"type": "text", "text": "operator wrote something"}
                    ]}
                ],
            },
            "issuetype": {"name": "Task"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 1


def test_description_is_empty_unit(jira_cli):
    """Direct unit coverage of description_is_empty for the canonical shapes,
    including template-only (UOF Task create form fingerprint observed in
    UOF-4569 on 2026-05-15)."""
    assert jira_cli.description_is_empty(None) is True
    assert jira_cli.description_is_empty("") is True
    assert jira_cli.description_is_empty("   ") is True
    # ADF doc with no content
    assert jira_cli.description_is_empty({"type": "doc", "content": []}) is True
    # ADF doc with only template scaffolding (3 headings + empty paragraph,
    # matching UOF-4569's actual shape)
    template = {
        "type": "doc",
        "content": [
            {"type": "heading", "attrs": {"level": 4},
             "content": [{"type": "text", "text": "Why do (Optional)"}]},
            {"type": "heading", "attrs": {"level": 4},
             "content": [{"type": "text", "text": "What to do (Optional)"}]},
            {"type": "heading", "attrs": {"level": 4},
             "content": [{"type": "text", "text": "How to verify (Must if you need QA help)"}]},
            {"type": "paragraph", "content": []},
        ],
    }
    assert jira_cli.description_is_empty(template) is True
    # ADF doc with real text content under a heading
    real = {
        "type": "doc",
        "content": [
            {"type": "heading", "content": [{"type": "text", "text": "Why"}]},
            {"type": "paragraph", "content": [{"type": "text", "text": "real content"}]},
        ],
    }
    assert jira_cli.description_is_empty(real) is False
    # Whitespace-only paragraph counts as empty-filler
    ws = {
        "type": "doc",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "   "}]},
        ],
    }
    assert jira_cli.description_is_empty(ws) is True


def test_regenerate_overrides_non_empty(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": {"type": "doc", "content": [{"type": "paragraph"}]},
            "issuetype": {"name": "Task"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes", "--regenerate"])
    assert rc == 0


def test_refuse_bug_without_force(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 1


def test_bug_under_auto_refuses_even_with_force(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    """`--force` requires interactive y/N — incompatible with --auto."""
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(
            ["fill", "UOF-1234", "--auto", "--yes", "--force"]
        )
    assert rc == 1


def test_bug_with_force_interactive_yes(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response, monkeypatch
):
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    monkeypatch.setattr("builtins.input", lambda *a, **k: "y")
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--yes", "--force"])
    assert rc == 0


def test_bug_with_force_interactive_no(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response, monkeypatch
):
    issue = {
        "key": "UOF-1234",
        "fields": {
            "summary": "x",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    monkeypatch.setattr("builtins.input", lambda *a, **k: "N")
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--yes", "--force"])
    assert rc == 1


def test_pr_no_body_emits_placeholder(
    jira_cli, tmp_telemetry, good_jira_issue, mock_llm_response
):
    pr_context = {
        "pr": {
            "number": 4321,
            "title": "feat: x",
            "body": "",
            "baseRefName": "main",
            "headRefName": "feat/x",
            "headRefOid": "abc1234",
        },
        "commits": "- feat: x\n",
    }
    with patched_external(
        jira_cli,
        pr_context=pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    # Empty PR body still produces a draft (Why → placeholder per spec
    # line 96) and posts successfully.
    assert rc == 0


def test_pr_body_boilerplate_treated_as_empty(
    jira_cli, tmp_telemetry, good_jira_issue, mock_llm_response
):
    pr_context = {
        "pr": {
            "number": 4321,
            "title": "feat: x",
            "body": "## Summary\n\n<TBD>\n\n## Test plan\n",
            "baseRefName": "main",
            "headRefName": "feat/x",
            "headRefOid": "abc1234",
        },
        "commits": "- feat: x\n",
    }
    with patched_external(
        jira_cli,
        pr_context=pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    # Boilerplate-only body behaves same as no body (spec line 97).
    assert rc == 0


def test_jira_4xx_on_put(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response,
    tmp_path,
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
        put_status=400,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 2
    # ADF saved for debug
    saved = pathlib.Path("/tmp/jira-fill-UOF-1234.adf.json")
    assert saved.exists(), "ADF debug dump missing"


def test_md2adf_raises_exit_3(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
        md2adf_raises=True,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 3
    saved = pathlib.Path("/tmp/jira-fill-UOF-1234.md")
    assert saved.exists()


def test_credentials_missing_exit_4(
    jira_cli, tmp_path, monkeypatch
):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv(
        "JIRA_FILL_CREDENTIALS", str(tmp_path / "does-not-exist")
    )
    monkeypatch.setenv(
        "JIRA_FILL_TELEMETRY", str(tmp_path / "telemetry.jsonl")
    )
    rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 4


# ---------------------------------------------------------------------
# Confabulation defense L1: command allowlist
# ---------------------------------------------------------------------

def test_l1_planted_bad_command_downgrades(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue
):
    """Planting `dd if=/dev/zero of=/dev/sda` in the verify section
    must cause the entire verify to downgrade to placeholders."""
    bad_response = (
        "## Why\n\nReason.\n\n"
        "## What\n\nDo a thing.\n\n"
        "## How to verify\n\n"
        "### Prerequisites\n\n- Bundle\n\n"
        "### Step 0 — Download and stage the test bundle\n\n"
        "```\nscp x root@host:/tmp/\n```\n\n"
        "### Step-by-step verification\n\n"
        "```\ndd if=/dev/zero of=/dev/sda\n```\n\n"
        "### Failure handling\n\n| f | o |\n|---|---|\n| x | y |\n\n"
        "### Cleanup\n\n```\nrm -rf /tmp/x\n```\n"
    )
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=bad_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 0
    telem_line = json.loads(
        pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
        .read_text()
        .strip()
        .splitlines()[-1]
    )
    assert telem_line["confab_l1_fail"] is True
    assert telem_line["downgraded_verify"] is True


def test_l1_clean_passes(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 0
    telem_line = json.loads(
        pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
        .read_text()
        .strip()
        .splitlines()[-1]
    )
    assert telem_line["confab_l1_fail"] is False
    assert telem_line["downgraded_verify"] is False


# ---------------------------------------------------------------------
# Confabulation defense L2: identifier allowlist
# ---------------------------------------------------------------------

def test_l2_unknown_upper_token_downgrades(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue
):
    """A bare `UNDEFINED_DEVICE` token not in PR body / commits / schema
    must trigger L2 downgrade."""
    bad_response = (
        "## Why\n\nReason.\n\n"
        "## What\n\nDo a thing.\n\n"
        "## How to verify\n\n"
        "### Prerequisites\n\n- UNDEFINED_DEVICE attached.\n\n"
        "### Step 0 — Download and stage the test bundle\n\n"
        "```\nscp bundle.tgz root@host:/tmp/\n```\n\n"
        "### Step-by-step verification\n\n"
        "```\nssh root@host ls /tmp\n```\n\n"
        "### Failure handling\n\n| f | o |\n|---|---|\n| x | y |\n\n"
        "### Cleanup\n\n```\nrm -rf /tmp/x\n```\n"
    )
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=bad_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    assert rc == 0
    telem_line = json.loads(
        pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
        .read_text()
        .strip()
        .splitlines()[-1]
    )
    assert telem_line["confab_l2_fail"] is True
    assert telem_line["downgraded_verify"] is True


# ---------------------------------------------------------------------
# Telemetry schema
# ---------------------------------------------------------------------

def test_telemetry_schema_fields(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
    telem = pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
    lines = telem.read_text().strip().splitlines()
    assert len(lines) == 1, f"expected exactly 1 telemetry line, got {len(lines)}"
    obj = json.loads(lines[0])
    required = {
        "ts", "key", "pr", "branch", "exit",
        "gen_chars", "posted_chars", "edit_ratio",
        "confab_l1_fail", "confab_l2_fail", "downgraded_verify",
        "rework_events_7d",
    }
    missing = required - set(obj.keys())
    assert not missing, f"telemetry missing fields: {missing}"


def test_telemetry_appended_not_overwritten(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response
):
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        jira_cli.main(["fill", "UOF-1234", "--auto", "--yes"])
        jira_cli.main(["fill", "UOF-1234", "--auto", "--yes", "--regenerate"])
    telem = pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
    assert len(telem.read_text().strip().splitlines()) == 2


# ---------------------------------------------------------------------
# Credentials contract — guard against mock-induced false negatives
# ---------------------------------------------------------------------
#
# Background: a dry-run demo once caught a `TypeError: tuple indices must
# be integers or slices, not str` in cmd_fill → fetch_issue. Root cause was
# `load_credentials()` returning a tuple `(email, token)` while every
# consumer subscripted it as a dict (`creds['JIRA_BASE_URL']` etc.). The
# 22 unit tests above did NOT catch it because the in-test mocks
# replicated the wrong shape — producer + mock agreed on a contract the
# consumers rejected. The tests below lock the contract from two angles
# so any future regression to a tuple (or to missing keys) fails fast.

def test_load_credentials_returns_dict_with_required_keys(
    jira_cli, tmp_path, monkeypatch
):
    """Contract test: load_credentials() must return a dict carrying
    JIRA_EMAIL / JIRA_TOKEN / JIRA_BASE_URL. If anyone changes the return
    shape (e.g. back to tuple), this test fails before consumers blow up
    at runtime with `TypeError: tuple indices must be integers`."""
    creds_path = tmp_path / "jira-credentials"
    creds_path.write_text(
        "export JIRA_EMAIL=alice@example.com\n"
        "export JIRA_TOKEN=tok-xyz\n"
        "export JIRA_BASE_URL=https://example.atlassian.net\n"
    )
    monkeypatch.setenv("JIRA_FILL_CREDENTIALS", str(creds_path))
    creds = jira_cli.load_credentials()
    assert creds is not None, "load_credentials returned None on valid file"
    assert isinstance(creds, dict), (
        f"load_credentials must return dict, got {type(creds).__name__}. "
        "Tuple/list shapes break consumers like fetch_issue that do "
        "creds['JIRA_BASE_URL']."
    )
    for key in ("JIRA_EMAIL", "JIRA_TOKEN", "JIRA_BASE_URL"):
        assert key in creds, f"missing credential key: {key}"
        assert isinstance(creds[key], str) and creds[key], (
            f"credential {key} must be a non-empty str"
        )


def test_load_credentials_missing_base_url_returns_none(
    jira_cli, tmp_path, monkeypatch
):
    """If JIRA_BASE_URL is absent we must reject the file rather than
    return a partial dict; consumers would otherwise KeyError at the
    first URL build. Cheaper to fail at load time."""
    creds_path = tmp_path / "jira-credentials"
    # Missing JIRA_BASE_URL on purpose.
    creds_path.write_text(
        "export JIRA_EMAIL=alice@example.com\n"
        "export JIRA_TOKEN=tok-xyz\n"
    )
    monkeypatch.setenv("JIRA_FILL_CREDENTIALS", str(creds_path))
    assert jira_cli.load_credentials() is None


def test_load_credentials_return_type_hint_is_dict(jira_cli):
    """Lock the published type signature so a future refactor can't
    silently revert to a positional tuple. Mypy isn't a dep here, but
    inspecting __annotations__ is free and binds the contract."""
    ann = jira_cli.load_credentials.__annotations__.get("return")
    assert ann is not None, "load_credentials must declare a return type"
    # Accept either `dict[str, str] | None` or PEP-604 union variants.
    s = str(ann)
    assert "dict" in s, f"return annotation must mention dict, got {s!r}"


def test_real_flow_bug_refuse_no_typeerror(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response, capsys
):
    """End-to-end real-flow test that mocks ONLY the outermost seams
    (subprocess_run, http_get, http_put, call_llm). load_credentials,
    _auth_header, fetch_issue, description_is_empty, and the issuetype
    guard all run real code.

    This is the test that would have caught the original demo bug: if
    load_credentials returned a tuple, _auth_header(creds) would raise
    `TypeError: tuple indices must be integers or slices, not str`
    BEFORE reaching the Bug-refuse exit path. Reaching the refuse path
    cleanly (rc=1, no TypeError) proves the dict contract holds across
    every internal boundary in cmd_fill's pre-LLM phase.
    """
    bug_issue = {
        "key": "UOF-4242",
        "fields": {
            "summary": "kernel oops on btrfs send",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    # No --force → must exit 1 via the Bug-refuse path.
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=bug_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-4242", "--auto", "--yes"])
    assert rc == 1, f"expected Bug-refuse exit 1, got {rc}"
    err = capsys.readouterr().err
    assert "issuetype=Bug" in err, (
        f"Bug-refuse stderr message missing — flow may have crashed "
        f"before the guard. stderr was: {err!r}"
    )
    # And critically: no TypeError leaked. capsys + the explicit rc=1
    # assertion above prove the flow reached the guard cleanly.


# ---------------------------------------------------------------------
# Telemetry-on-every-exit contract (spec lines 124-138)
# ---------------------------------------------------------------------
#
# Background: dry-run demo on 2026-05-15 against UOF-4485 produced an
# empty telemetry file because the cancelled path returned early before
# write_telemetry(). Spec says one JSONL line per run regardless of
# exit. Kill criterion C (low adoption) divides posted_runs by
# eligible_PRs; if cancelled/refused paths don't write telemetry,
# the denominator is missing those runs entirely.

def _read_telemetry_lines():
    path = pathlib.Path(os.environ["JIRA_FILL_TELEMETRY"])
    if not path.exists():
        return []
    return [
        json.loads(line) for line in path.read_text().splitlines()
        if line.strip()
    ]


def test_telemetry_written_on_cancelled_path(
    jira_cli, tmp_telemetry, good_pr_context, good_jira_issue, mock_llm_response,
    monkeypatch
):
    """User presses N (or stdin EOF) at preview → exit_path=cancelled, rc=1,
    telemetry MUST still record this run."""
    monkeypatch.setattr("builtins.input", lambda _prompt="": "N")
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-1234"])
    assert rc == 1
    rows = _read_telemetry_lines()
    assert len(rows) == 1, f"expected 1 telemetry row, got {len(rows)}"
    assert rows[0]["exit"] == "cancelled"
    assert rows[0]["key"] == "UOF-1234"


def test_telemetry_written_on_refused_empty(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    """description non-empty + no --regenerate → exit_path=refused_empty."""
    issue = {
        "key": "UOF-9999",
        "fields": {
            "summary": "x",
            "description": {
                "type": "doc",
                "content": [
                    {"type": "paragraph", "content": [
                        {"type": "text", "text": "real content"}
                    ]}
                ],
            },
            "issuetype": {"name": "Task"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-9999", "--auto", "--yes"])
    assert rc == 1
    rows = _read_telemetry_lines()
    assert len(rows) == 1
    assert rows[0]["exit"] == "refused_empty"


def test_telemetry_written_on_refused_bug(
    jira_cli, tmp_telemetry, good_pr_context, mock_llm_response
):
    """Bug issuetype without --force → exit_path=refused_bug."""
    bug_issue = {
        "key": "UOF-BUG-1",
        "fields": {
            "summary": "race condition",
            "description": None,
            "issuetype": {"name": "Bug"},
        },
    }
    with patched_external(
        jira_cli,
        pr_context=good_pr_context,
        issue=bug_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main(["fill", "UOF-BUG-1", "--auto", "--yes"])
    assert rc == 1
    rows = _read_telemetry_lines()
    assert len(rows) == 1
    assert rows[0]["exit"] == "refused_bug"


def test_telemetry_written_on_auto_force_conflict(
    jira_cli, tmp_telemetry
):
    """--auto + --force is rejected pre-GET — telemetry MUST still record."""
    rc = jira_cli.main([
        "fill", "UOF-1234", "--auto", "--yes", "--force"
    ])
    assert rc == 1
    rows = _read_telemetry_lines()
    assert len(rows) == 1
    assert rows[0]["exit"] == "refused_auto_force"


def test_telemetry_written_on_creds_missing(
    jira_cli, tmp_telemetry, monkeypatch
):
    """Missing credentials → exit_path=creds_missing, telemetry still records."""
    monkeypatch.setenv("JIRA_FILL_CREDENTIALS", "/nonexistent/path/creds")
    rc = jira_cli.main(["fill", "UOF-1234"])
    assert rc == 4
    rows = _read_telemetry_lines()
    assert len(rows) == 1
    assert rows[0]["exit"] == "creds_missing"


# ---------------------------------------------------------------------
# Cross-repo (--pr-url) flag
# ---------------------------------------------------------------------

def test_parse_pr_url_happy(jira_cli):
    assert jira_cli.parse_pr_url(
        "https://github.com/ubiquiti/unifi-drive-config/pull/290"
    ) == ("ubiquiti/unifi-drive-config", "290")
    # http also accepted
    assert jira_cli.parse_pr_url(
        "http://github.com/foo/bar/pull/1"
    ) == ("foo/bar", "1")
    # trailing path components after pull/<num> are ignored (e.g. /files, /commits)
    assert jira_cli.parse_pr_url(
        "https://github.com/foo/bar/pull/42/files"
    ) == ("foo/bar", "42")


def test_parse_pr_url_rejects_bad_input(jira_cli):
    assert jira_cli.parse_pr_url("not a url") is None
    assert jira_cli.parse_pr_url(
        "https://github.com/foo/bar/issues/1"  # issue, not PR
    ) is None
    assert jira_cli.parse_pr_url(
        "https://gitlab.com/foo/bar/pull/1"  # wrong host
    ) is None
    assert jira_cli.parse_pr_url("") is None


def test_bad_pr_url_refuses_with_telemetry(
    jira_cli, tmp_telemetry, good_jira_issue, mock_llm_response
):
    """Malformed --pr-url is caught after creds + guards (so telemetry records)."""
    with patched_external(
        jira_cli,
        pr_context={},  # would be unused
        issue=good_jira_issue,
        llm_text=mock_llm_response,
    ):
        rc = jira_cli.main([
            "fill", "UOF-1234", "--auto", "--yes",
            "--pr-url", "not-a-url",
        ])
    assert rc == 1
    rows = _read_telemetry_lines()
    assert len(rows) == 1
    assert rows[0]["exit"] == "refused_bad_pr_url"


def test_pr_url_routes_fetch_pr_context_cross_repo(jira_cli, monkeypatch):
    """With pr_url, fetch_pr_context calls `gh pr view <num> --repo <slug> --json ...`,
    NOT bare `gh pr view --json ...` (which would target current branch)."""

    class _Cp:
        def __init__(self, rc, stdout):
            self.returncode = rc
            self.stdout = stdout
            self.stderr = ""

    seen = []
    def fake_run(cmd, **kw):
        seen.append(list(cmd))
        return _Cp(0, json.dumps({
            "title": "[UOF-1234] cross-repo PR",
            "body": "## Why\n\nDoing the thing.",
            "baseRefName": "main",
            "headRefName": "feat/x",
            "headRefOid": "abcdef1234567890",
            "number": 290,
        }))
    monkeypatch.setattr(jira_cli, "subprocess_run", fake_run)
    result = jira_cli.fetch_pr_context(
        pr_url="https://github.com/ubiquiti/unifi-drive-config/pull/290"
    )
    assert result is not None
    assert result["number"] == 290
    assert len(seen) == 1
    cmd = seen[0]
    assert cmd[:3] == ["gh", "pr", "view"]
    assert "290" in cmd
    assert "--repo" in cmd
    repo_idx = cmd.index("--repo")
    assert cmd[repo_idx + 1] == "ubiquiti/unifi-drive-config"


def test_pr_url_routes_fetch_commits_via_gh_api(jira_cli, monkeypatch):
    """With pr_url, fetch_commits calls `gh api repos/<slug>/pulls/<num>/commits`,
    NOT `git log` (which would scan a local repo the operator may not have)."""

    class _Cp:
        def __init__(self, rc, stdout):
            self.returncode = rc
            self.stdout = stdout
            self.stderr = ""

    seen = []
    def fake_run(cmd, **kw):
        seen.append(list(cmd))
        return _Cp(0, "- first commit\n- second commit\n")
    monkeypatch.setattr(jira_cli, "subprocess_run", fake_run)
    out = jira_cli.fetch_commits(
        base_ref="main",
        pr_url="https://github.com/ubiquiti/unifi-drive-config/pull/290",
    )
    assert "first commit" in out
    assert "second commit" in out
    assert len(seen) == 1
    cmd = seen[0]
    assert cmd[:2] == ["gh", "api"]
    assert "pulls/290/commits" in cmd[2]
    # And NOT git log
    assert all(c[:2] != ["git", "log"] for c in seen)


def test_no_pr_url_uses_current_branch_fetch(jira_cli, monkeypatch):
    """Default behavior preserved: no pr_url → bare `gh pr view --json ...`,
    no --repo, no num (gh defaults to current branch's PR)."""

    class _Cp:
        def __init__(self, rc, stdout):
            self.returncode = rc
            self.stdout = stdout
            self.stderr = ""

    seen = []
    def fake_run(cmd, **kw):
        seen.append(list(cmd))
        return _Cp(0, json.dumps({"number": 0, "body": "", "title": "",
                                  "baseRefName": "main", "headRefName": "",
                                  "headRefOid": ""}))
    monkeypatch.setattr(jira_cli, "subprocess_run", fake_run)
    jira_cli.fetch_pr_context()  # no pr_url
    assert len(seen) == 1
    cmd = seen[0]
    assert cmd[:3] == ["gh", "pr", "view"]
    assert "--repo" not in cmd
