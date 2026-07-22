#!/usr/bin/env python3
"""jira-cli.py — Jira ticket automation (subcommands).

Subcommands:
    fill <KEY>   Auto-fill an empty Jira description from PR body + commits
                 + qa-verify-template.md schema. Implements spec
                 docs/specs/active/2026-05-12-jira-fill-from-pr.md.
    link <KEY>   Out of scope for this PR — stub raises NotImplementedError.

External dependencies are isolated behind a small set of seam functions
(``subprocess_run``, ``http_get``, ``http_put``, ``call_llm``) so the
``fill`` flow stays mockable in unit tests.
"""
from __future__ import annotations

import argparse
import datetime
import difflib
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS_DIR = HERE
SKILL_ROOT = HERE.parent.parent
TEMPLATE_PATH = SKILL_ROOT / "_shared" / "references" / "qa-verify-template.md"
ALLOWLIST_PATH = HERE / "confab-allowlist.txt"
MD2ADF_PATH = HERE / "md2adf.py"

DEFAULT_TELEMETRY = pathlib.Path.home() / ".config" / "ubiquiti" / "jira-fill-telemetry.jsonl"
DEFAULT_CREDENTIALS = pathlib.Path.home() / ".config" / "ubiquiti" / "jira-credentials"

LLM_MODEL = "claude-opus-4-8"

PLACEHOLDER_VERIFY = """### Prerequisites

<!-- needs human: list ticket attachments and host requirements -->

### Step 0 — Download and stage the test bundle

<!-- needs human: how does QA fetch the test bundle from this ticket -->

### Step-by-step verification

<!-- needs human: exact commands + bit-exact Expected: lines -->

### Failure handling

<!-- needs human: failure mode → component owner mapping -->

### Cleanup

<!-- needs human: explicit teardown, isolated config removal -->
"""

EXIT_OK = 0
EXIT_REFUSED = 1
EXIT_API_ERROR = 2
EXIT_MD2ADF_ERROR = 3
EXIT_CREDS_MISSING = 4


# ---------------------------------------------------------------------
# Seam functions (mocked by tests)
# ---------------------------------------------------------------------

def subprocess_run(cmd, **kwargs):
    """Wrapper around subprocess.run that the tests patch."""
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    return subprocess.run(cmd, **kwargs)


def http_get(url, **kwargs):  # pragma: no cover — patched in tests
    import urllib.request
    req = urllib.request.Request(url, headers=kwargs.get("headers", {}))
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8")
            return _FakeResp(r.status, body)
    except Exception as e:  # network errors surface to caller
        return _FakeResp(0, str(e))


def http_put(url, **kwargs):  # pragma: no cover — patched in tests
    import urllib.request
    data = kwargs.get("data") or b""
    if isinstance(data, str):
        data = data.encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="PUT", headers=kwargs.get("headers", {})
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return _FakeResp(r.status, r.read().decode("utf-8"))
    except Exception as e:
        return _FakeResp(0, str(e))


class _FakeResp:
    """Minimal response shape; tests use MagicMock with the same fields."""

    def __init__(self, status_code, text):
        self.status_code = status_code
        self.text = text

    def json(self):
        return json.loads(self.text)


def call_llm(prompt: str, system: str = "") -> str:  # pragma: no cover
    """Anthropic call; tests patch this entirely."""
    try:
        import anthropic
    except ImportError:
        raise RuntimeError("anthropic SDK not installed")
    client = anthropic.Anthropic()
    msg = client.messages.create(
        model=LLM_MODEL,
        max_tokens=4096,
        system=system,
        messages=[{"role": "user", "content": prompt}],
    )
    parts = []
    for block in msg.content:
        if getattr(block, "type", None) == "text":
            parts.append(block.text)
    return "".join(parts)


# ---------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------

def _creds_path() -> pathlib.Path:
    override = os.environ.get("JIRA_FILL_CREDENTIALS")
    if override:
        return pathlib.Path(override)
    return DEFAULT_CREDENTIALS


def load_credentials() -> dict[str, str] | None:
    """Parse ~/.config/ubiquiti/jira-credentials.

    File format is shell-export-compatible:
        export JIRA_EMAIL=...
        export JIRA_TOKEN=...
        export JIRA_BASE_URL=https://...
    Returns dict or None if file is missing / unparseable.
    """
    p = _creds_path()
    if not p.exists():
        return None
    creds: dict[str, str] = {}
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        line = line.removeprefix("export ").strip()
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        creds[k.strip()] = v.strip().strip('"').strip("'")
    required = ("JIRA_EMAIL", "JIRA_TOKEN", "JIRA_BASE_URL")
    if not all(creds.get(k) for k in required):
        return None
    return creds


# ---------------------------------------------------------------------
# Telemetry
# ---------------------------------------------------------------------

def _telemetry_path() -> pathlib.Path:
    override = os.environ.get("JIRA_FILL_TELEMETRY")
    if override:
        return pathlib.Path(override)
    return DEFAULT_TELEMETRY


def write_telemetry(record: dict[str, Any]) -> None:
    p = _telemetry_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------
# PR + git context
# ---------------------------------------------------------------------

_PR_URL_RE = re.compile(
    r"^https?://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/pull/(?P<num>\d+)"
)


def parse_pr_url(url: str) -> tuple[str, str] | None:
    """Parse a github.com PR URL into (owner/repo, pull-number).

    Returns None on malformed input; caller surfaces that as an error.
    """
    m = _PR_URL_RE.match(url.strip())
    if not m:
        return None
    return f"{m['owner']}/{m['repo']}", m["num"]


def fetch_pr_context(pr_url: str | None = None) -> dict[str, Any] | None:
    """Fetch PR context via `gh pr view --json ...`.

    Default (pr_url=None): the PR associated with the current branch in
    the current working directory — the common case where the operator
    fills a ticket from the branch that already has its own PR.

    Cross-repo (pr_url given): the PR named by the github.com URL.
    Useful when the ticket's PR lives in a different repo than the
    operator's worktree (e.g., a UOF ticket whose code PR is in
    unifi-drive-config, or a multi-repo feature where one ticket points
    at two/three PRs). See spec § Cross-repo support.
    """
    fields = "body,number,title,baseRefName,headRefName,headRefOid"
    if pr_url:
        parsed = parse_pr_url(pr_url)
        if not parsed:
            return None
        repo, num = parsed
        cp = subprocess_run(
            ["gh", "pr", "view", num, "--repo", repo, "--json", fields]
        )
    else:
        cp = subprocess_run(
            ["gh", "pr", "view", "--json", fields]
        )
    if cp.returncode != 0:
        return None
    try:
        return json.loads(cp.stdout)
    except json.JSONDecodeError:
        return None


def fetch_commits(base_ref: str, pr_url: str | None = None) -> str:
    """Collect commit messages on the PR for the LLM prompt.

    Default (pr_url=None): `git log base_ref..HEAD` in the current
    worktree.

    Cross-repo (pr_url given): `gh api repos/<owner>/<repo>/pulls/<num>/commits`
    — operator does not need a local clone of the other repo.
    """
    if pr_url:
        parsed = parse_pr_url(pr_url)
        if not parsed:
            return ""
        repo, num = parsed
        cp = subprocess_run(
            [
                "gh", "api", f"repos/{repo}/pulls/{num}/commits",
                "--jq", '.[] | "- " + .commit.message',
            ]
        )
        if cp.returncode != 0:
            return ""
        return cp.stdout
    cp = subprocess_run(
        ["git", "log", f"{base_ref}..HEAD", "--pretty=format:- %s%n%n%b"]
    )
    if cp.returncode != 0:
        return ""
    return cp.stdout


def pr_body_is_empty(body: str | None) -> bool:
    """Spec lines 96-97: empty PR body OR boilerplate-only counts as empty."""
    if not body or not body.strip():
        return True
    # Strip boilerplate markers and check for substantive content
    text = body
    # Remove top-level "## Summary" / "## Test plan" headers + <TBD> tokens
    stripped = re.sub(r"^##\s+\w[\w ]*$", "", text, flags=re.MULTILINE)
    stripped = stripped.replace("<TBD>", "")
    stripped = re.sub(r"\s+", "", stripped)
    return len(stripped) < 10


# ---------------------------------------------------------------------
# Confabulation defense
# ---------------------------------------------------------------------

def load_command_allowlist() -> set[str]:
    if not ALLOWLIST_PATH.exists():
        raise RuntimeError(f"missing allowlist: {ALLOWLIST_PATH}")
    out: set[str] = set()
    for line in ALLOWLIST_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.add(line)
    return out


def extract_schema_allowlist(template_text: str) -> set[str]:
    """Extract device names + protocol tokens from qa-verify-template.md.

    We scan the template body for `[A-Z][A-Z0-9_-]{2,}` tokens (e.g.
    UOF-4485, UNAS, NFS, SMB) and use those as the L2 schema allowlist.
    """
    return set(re.findall(r"[A-Z][A-Z0-9_-]{2,}", template_text))


def _iter_fenced_blocks(md: str):
    """Yield (lang, [lines]) tuples for every ```...``` fenced block."""
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("```"):
            lang = s[3:].strip() or None
            i += 1
            buf = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            if i < len(lines):
                i += 1  # consume closing fence
            yield lang, buf
        else:
            i += 1


def check_l1_commands(verify_md: str, allowlist: set[str]) -> list[str]:
    """Return list of disallowed binaries found in fenced blocks.
    Empty list = pass."""
    bad = []
    for _lang, block in _iter_fenced_blocks(verify_md):
        for raw_line in block:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            # Allow <placeholder> lines and Expected: prose.
            if line.startswith("<") and line.endswith(">"):
                continue
            if line.startswith("Expected:") or line.startswith("**Expected"):
                continue
            try:
                tokens = shlex.split(line, comments=True, posix=True)
            except ValueError:
                tokens = line.split()
            if not tokens:
                continue
            # Strip env-var assignments (FOO=bar before the binary).
            idx = 0
            while idx < len(tokens) and "=" in tokens[idx] and not tokens[idx].startswith("/"):
                idx += 1
            if idx >= len(tokens):
                continue
            binary = tokens[idx]
            # Allow placeholder tokens.
            if binary.startswith("<") and binary.endswith(">"):
                continue
            # Strip path prefix; allowlist matches basename.
            binary_base = pathlib.PurePath(binary).name
            # Allow shell control words.
            if binary_base in {
                "if", "fi", "then", "else", "elif", "for", "do", "done",
                "while", "case", "esac", "set", "true", "false", "exit",
                "echo", "printf", "test", "[",
            }:
                continue
            if binary_base not in allowlist:
                bad.append(binary_base)
    return bad


def check_l2_identifiers(
    verify_md: str,
    pr_body: str,
    commits: str,
    schema_allowlist: set[str],
) -> list[str]:
    """Return list of identifiers (UPPER_TOKENs) in the verify section
    that don't appear in commit_messages ∪ pr_body ∪ schema_allowlist."""
    tokens = set(re.findall(r"[A-Z][A-Z0-9_-]{2,}", verify_md))
    haystack = (pr_body or "") + "\n" + (commits or "")
    haystack_tokens = set(re.findall(r"[A-Z][A-Z0-9_-]{2,}", haystack))
    # Common protocol/format tokens — HTTP verbs, oracle-output keywords,
    # data-format names. Hardcoded for Sprint 1 because these are
    # protocol-level universals unlikely to need expansion in the first
    # 30 runs; deferring the file-extraction discipline (mirroring L1's
    # confab-allowlist.txt) to a Sprint 2 follow-up after kill-criterion B′
    # spot-check data accumulates. See spec line 47 ("schema_allowlist =
    # device names + protocols from qa-verify-template.md") — that part is
    # extracted at runtime; this `generic` set is the L2 false-positive
    # defense layered on top.
    # Note: tokens shorter than 3 chars (would not match the
    # [A-Z][A-Z0-9_-]{2,} extraction regex above) omitted.
    generic = {
        "PASS", "FAIL", "MISSING", "BASELINE", "SUMMARY", "TBD",
        "GET", "PUT", "POST", "DELETE", "PATCH",
        "URL", "API", "JSON", "ADF", "YAML", "XML",
        "MD5", "SHA",
    }
    allowed = haystack_tokens | schema_allowlist | generic
    bad = [t for t in tokens if t not in allowed]
    return bad


# ---------------------------------------------------------------------
# Provenance markers
# ---------------------------------------------------------------------

def _short_sha(sha: str) -> str:
    return (sha or "0000000")[:7]


def _section_sha(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:8]


def annotate_provenance(markdown: str, branch: str, head_sha: str) -> str:
    """Append per-H3 trailing HTML comment with provenance handshake."""
    iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    short = _short_sha(head_sha)
    lines = markdown.splitlines()
    out: list[str] = []
    section_buf: list[str] = []
    section_header: str | None = None

    def flush():
        if section_header is None:
            out.extend(section_buf)
            return
        out.append(section_header)
        body = "\n".join(section_buf).rstrip()
        out.append(body)
        sha = _section_sha(body)
        out.append(
            f"<!-- generated by /jira fill from {branch}@{short} "
            f"on {iso} sha={sha} — please correct in place -->"
        )

    for line in lines:
        if line.startswith("### "):
            flush()
            section_header = line
            section_buf = []
        else:
            section_buf.append(line)
    # Final flush
    if section_header is None:
        return "\n".join(out + section_buf)
    out.append(section_header)
    body = "\n".join(section_buf).rstrip()
    out.append(body)
    sha = _section_sha(body)
    out.append(
        f"<!-- generated by /jira fill from {branch}@{short} "
        f"on {iso} sha={sha} — please correct in place -->"
    )
    return "\n".join(out)


# ---------------------------------------------------------------------
# Prompt assembly + LLM
# ---------------------------------------------------------------------

SYSTEM_PROMPT = (
    "You draft Jira ticket descriptions from PR context. NEVER reference "
    "files, commands, or identifiers not present in the inputs. If the Why "
    "section is missing in the PR body, emit "
    "`<!-- needs human: why this change -->` verbatim. Use markdown only — "
    "no markdown links (URLs must be bare). Use single-level 3-backtick "
    "code fences (no nested ``````). Emit exactly three top-level H2 "
    "sections: `## Why`, `## What`, `## How to verify`. The verify section "
    "must follow the 5-H3 schema: Prerequisites / Step 0 / Step-by-step / "
    "Failure handling / Cleanup."
)


def build_prompt(
    pr: dict[str, Any], commits: str, template: str
) -> str:
    return (
        "Draft a 3-section Jira description (Why / What / How to verify) "
        "from the following PR context.\n\n"
        "## PR title\n"
        f"{pr.get('title', '')}\n\n"
        "## PR body\n"
        f"{pr.get('body') or '<empty>'}\n\n"
        "## Commits on this branch\n"
        f"{commits or '<none>'}\n\n"
        "## Verify-section schema (5 H3s, derived from qa-verify-template.md)\n"
        f"{template}\n\n"
        "Emit the markdown directly. No preamble, no postscript."
    )


# ---------------------------------------------------------------------
# md2adf invocation
# ---------------------------------------------------------------------

def md_to_adf(markdown: str) -> tuple[int, str, str]:
    """Run md2adf.py as subprocess; return (rc, stdout, stderr)."""
    cp = subprocess_run(
        ["python3", str(MD2ADF_PATH)],
        input=markdown,
    )
    return cp.returncode, cp.stdout or "", cp.stderr or ""


# ---------------------------------------------------------------------
# Jira REST
# ---------------------------------------------------------------------

def _auth_header(creds: dict[str, str]) -> dict[str, str]:
    import base64
    raw = f"{creds['JIRA_EMAIL']}:{creds['JIRA_TOKEN']}".encode("utf-8")
    return {
        "Authorization": "Basic " + base64.b64encode(raw).decode("ascii"),
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def fetch_issue(key: str, creds: dict[str, str]) -> tuple[int, dict[str, Any] | str]:
    url = f"{creds['JIRA_BASE_URL']}/rest/api/3/issue/{key}?fields=summary,description,issuetype"
    resp = http_get(url, headers=_auth_header(creds))
    if resp.status_code != 200:
        return resp.status_code, getattr(resp, "text", "")
    return 200, resp.json()


def put_description(
    key: str, adf: dict[str, Any], creds: dict[str, str]
) -> tuple[int, str]:
    url = f"{creds['JIRA_BASE_URL']}/rest/api/3/issue/{key}"
    payload = json.dumps({"fields": {"description": adf}})
    resp = http_put(url, headers=_auth_header(creds), data=payload)
    return resp.status_code, getattr(resp, "text", "")


# ---------------------------------------------------------------------
# Description-empty detection
# ---------------------------------------------------------------------

def _adf_node_is_empty_filler(node: dict) -> bool:
    """A node counts as empty-filler if it's a heading (template scaffold)
    or a paragraph with no rendered text. Observed in UOF Task type's
    create-form template (e.g. UOF-4569): the form pre-fills 3 H3
    headings + 1 empty paragraph and users perceive this as 'empty'."""
    t = node.get("type")
    if t == "heading":
        return True
    if t == "paragraph":
        for child in node.get("content") or []:
            text = (child.get("text") or "").strip()
            if text:
                return False
            if child.get("type") not in ("text", "hardBreak"):
                return False
        return True
    return False


def description_is_empty(desc: Any) -> bool:
    """Spec line 98: refuse when `fields.description != null`.

    Treat as empty when:
      - description is None / missing entirely, or
      - description is an explicit empty string, or
      - description is an ADF doc with no content nodes, or
      - description is an ADF doc whose every content node is
        empty-filler — i.e. headings or empty paragraphs (Jira create
        form templates land here; see _adf_node_is_empty_filler).

    Any node with real text content makes the doc non-empty — the
    operator wrote *something* and we refuse without --regenerate.
    """
    if desc is None:
        return True
    if isinstance(desc, str):
        return not desc.strip()
    if isinstance(desc, dict):
        content = desc.get("content") or []
        if len(content) == 0:
            return True
        return all(_adf_node_is_empty_filler(n) for n in content)
    return False


# ---------------------------------------------------------------------
# Verify-section downgrade helpers
# ---------------------------------------------------------------------

_VERIFY_HEADER_RE = re.compile(r"^##\s+How to verify\s*$", re.MULTILINE)


def isolate_verify_section(markdown: str) -> tuple[str, str, str]:
    """Split markdown into (before_verify, verify_body, after_verify)."""
    m = _VERIFY_HEADER_RE.search(markdown)
    if not m:
        return markdown, "", ""
    before = markdown[: m.end()]
    rest = markdown[m.end():]
    # Find the next H2 (or end of file).
    next_h2 = re.search(r"^##\s+\w", rest, flags=re.MULTILINE)
    if next_h2:
        verify_body = rest[: next_h2.start()]
        after = rest[next_h2.start():]
    else:
        verify_body = rest
        after = ""
    return before, verify_body, after


def downgrade_verify(markdown: str) -> str:
    before, _body, after = isolate_verify_section(markdown)
    if not before:
        return markdown  # no verify section; nothing to do
    return before + "\n\n" + PLACEHOLDER_VERIFY + ("\n" + after if after else "\n")


# ---------------------------------------------------------------------
# Edit ratio (Levenshtein-flavored, but use difflib for portability)
# ---------------------------------------------------------------------

def edit_ratio(a: str, b: str) -> float:
    if not a:
        return 0.0
    sm = difflib.SequenceMatcher(None, a, b)
    return round(1.0 - sm.ratio(), 4)


# ---------------------------------------------------------------------
# fill subcommand
# ---------------------------------------------------------------------

def cmd_fill(args: argparse.Namespace) -> int:
    """Run /jira fill <KEY>.

    Telemetry contract (spec lines 124-138): one JSONL line per run,
    regardless of exit path. State accumulators below default to neutral
    values so the finally-block can always emit a record, even on early
    refuse/abort paths where pr/generated are not yet populated.
    """
    key = args.key
    pr: dict[str, Any] = {
        "title": "", "body": "", "baseRefName": "main",
        "headRefName": "", "headRefOid": "", "number": 0,
    }
    generated = ""
    annotated = ""
    l1_bad: list[str] = []
    l2_bad: list[str] = []
    downgraded = False
    exit_path = "unknown"
    rc = EXIT_OK
    try:
        creds = load_credentials()
        if not creds:
            print(
                "credentials missing — populate "
                f"{_creds_path()} (JIRA_EMAIL / JIRA_TOKEN / JIRA_BASE_URL)",
                file=sys.stderr,
            )
            exit_path = "creds_missing"
            rc = EXIT_CREDS_MISSING
            return rc

        # --auto + --force is incompatible (interactive y/N required for Bug).
        if args.auto and args.force:
            print(
                "refusing: --force requires interactive y/N confirmation and is "
                "incompatible with --auto",
                file=sys.stderr,
            )
            exit_path = "refused_auto_force"
            rc = EXIT_REFUSED
            return rc

        # GET issue
        status, body = fetch_issue(key, creds)
        if status != 200:
            print(f"jira GET {key}: HTTP {status}: {body}", file=sys.stderr)
            exit_path = "api_error"
            rc = EXIT_API_ERROR
            return rc
        fields = body.get("fields", {})
        issuetype = (fields.get("issuetype") or {}).get("name") or ""
        existing_desc = fields.get("description")

        # Guard: empty/whitespace description
        if not description_is_empty(existing_desc) and not args.regenerate:
            print(
                f"refusing: {key} description is non-empty (has real content "
                "beyond template scaffolding). Pass --regenerate to override.",
                file=sys.stderr,
            )
            exit_path = "refused_empty"
            rc = EXIT_REFUSED
            return rc

        # Guard: issuetype != Bug
        if issuetype == "Bug":
            if not args.force:
                print(
                    f"refusing: {key} issuetype=Bug. Pass --force to override "
                    "(requires interactive y/N).",
                    file=sys.stderr,
                )
                exit_path = "refused_bug"
                rc = EXIT_REFUSED
                return rc
            # --force path: must prompt interactively (--auto already filtered)
            try:
                answer = input(
                    f"{key} is a Bug ticket. Overwrite description? [y/N] "
                ).strip().lower()
            except EOFError:
                answer = ""
            if answer != "y":
                print("aborted by user", file=sys.stderr)
                exit_path = "refused_bug"
                rc = EXIT_REFUSED
                return rc

        # Collect PR context (cross-repo: --pr-url overrides current branch)
        pr_url = getattr(args, "pr_url", None)
        if pr_url and parse_pr_url(pr_url) is None:
            print(
                f"refusing: --pr-url {pr_url!r} is not a github.com/<owner>/<repo>/pull/<num> URL",
                file=sys.stderr,
            )
            exit_path = "refused_bad_pr_url"
            rc = EXIT_REFUSED
            return rc
        pr = fetch_pr_context(pr_url=pr_url) or pr
        pr_body = pr.get("body") or ""
        commits = fetch_commits(
            pr.get("baseRefName") or "main", pr_url=pr_url
        )
        template = ""
        if TEMPLATE_PATH.exists():
            template = TEMPLATE_PATH.read_text()

        # Note empty-body → emits placeholder via system-prompt instruction.
        # No special-case; the LLM is told to emit `<!-- needs human: ... -->`.
        _pr_empty = pr_body_is_empty(pr_body)

        # LLM call
        try:
            prompt = build_prompt(pr, commits, template)
            generated = call_llm(prompt, system=SYSTEM_PROMPT)
        except Exception as e:
            print(f"LLM call failed: {e}", file=sys.stderr)
            exit_path = "api_error"
            rc = EXIT_API_ERROR
            return rc

        # Confabulation defense L1 + L2 — scope to verify section only.
        _before, verify_body, _after = isolate_verify_section(generated)
        allowlist = load_command_allowlist()
        schema_allow = extract_schema_allowlist(template) if template else set()

        l1_bad = check_l1_commands(verify_body, allowlist) if verify_body else []
        l2_bad = (
            check_l2_identifiers(verify_body, pr_body, commits, schema_allow)
            if verify_body else []
        )
        if l1_bad or l2_bad:
            generated = downgrade_verify(generated)
            downgraded = True

        # Provenance annotation
        annotated = annotate_provenance(
            generated,
            branch=pr.get("headRefName") or "unknown",
            head_sha=pr.get("headRefOid") or "0000000",
        )

        # Preview / edit
        if args.edit:
            tmp = pathlib.Path(f"/tmp/jira-fill-{key}.md")
            tmp.write_text(annotated)
            editor = os.environ.get("EDITOR", "vi")
            subprocess.run([editor, str(tmp)])
            annotated = tmp.read_text()
        elif not args.auto:
            print(annotated)
            try:
                confirm = input("Post to Jira? [y/N] ").strip().lower()
            except EOFError:
                confirm = ""
            if confirm != "y" and not args.yes:
                print("cancelled", file=sys.stderr)
                exit_path = "cancelled"
                rc = EXIT_REFUSED
                return rc

        # md2adf conversion
        md_rc, adf_stdout, adf_stderr = md_to_adf(annotated)
        if md_rc != 0 or not adf_stdout.strip():
            debug = pathlib.Path(f"/tmp/jira-fill-{key}.md")
            debug.write_text(annotated)
            print(f"md2adf failed: {adf_stderr}", file=sys.stderr)
            exit_path = "md2adf_error"
            rc = EXIT_MD2ADF_ERROR
            return rc

        try:
            adf = json.loads(adf_stdout)
        except json.JSONDecodeError as e:
            debug = pathlib.Path(f"/tmp/jira-fill-{key}.md")
            debug.write_text(annotated)
            print(f"md2adf returned non-JSON: {e}", file=sys.stderr)
            exit_path = "md2adf_error"
            rc = EXIT_MD2ADF_ERROR
            return rc

        # PUT
        put_status, put_text = put_description(key, adf, creds)
        if put_status >= 400 or put_status == 0:
            adf_debug = pathlib.Path(f"/tmp/jira-fill-{key}.adf.json")
            adf_debug.write_text(json.dumps(adf, indent=2))
            print(
                f"jira PUT {key}: HTTP {put_status}: {put_text}",
                file=sys.stderr,
            )
            exit_path = "api_error"
            rc = EXIT_API_ERROR
            return rc

        # Success
        exit_path = "posted"
        print(f"posted {key}")
        rc = EXIT_OK
        return rc
    finally:
        # Spec lines 124-138: telemetry written once per run, regardless
        # of exit path. Skip only if cmd_fill exits before key/exit_path
        # are even known (cannot happen given the default values above).
        try:
            write_telemetry(_telemetry_record(
                key, pr, generated, annotated,
                l1_bad, l2_bad, downgraded, exit_path,
            ))
        except Exception as _telemetry_exc:  # pragma: no cover
            # Telemetry must never break the main flow.
            print(
                f"warning: telemetry write failed: {_telemetry_exc}",
                file=sys.stderr,
            )


def _telemetry_record(
    key: str,
    pr: dict[str, Any],
    generated: str,
    posted: str,
    l1_bad: list[str],
    l2_bad: list[str],
    downgraded: bool,
    exit_path: str,
) -> dict[str, Any]:
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    branch_label = (
        f"{pr.get('headRefName') or 'unknown'}@"
        f"{_short_sha(pr.get('headRefOid') or '')}"
    )
    return {
        "ts": ts,
        "key": key,
        "pr": pr.get("number") or 0,
        "branch": branch_label,
        "exit": exit_path,
        "gen_chars": len(generated or ""),
        "posted_chars": len(posted or ""),
        "edit_ratio": edit_ratio(generated or "", posted or ""),
        "confab_l1_fail": bool(l1_bad),
        "confab_l2_fail": bool(l2_bad),
        "downgraded_verify": bool(downgraded),
        "rework_events_7d": None,
    }


# ---------------------------------------------------------------------
# link subcommand (stub)
# ---------------------------------------------------------------------

def cmd_link(args: argparse.Namespace) -> int:
    raise NotImplementedError(
        "link subcommand out of scope for this PR — see spec "
        "docs/specs/active/2026-05-12-jira-fill-from-pr.md § Out of scope"
    )


# ---------------------------------------------------------------------
# argparse
# ---------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="jira-cli.py",
        description="Jira ticket automation (fill / link subcommands).",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    fp = sub.add_parser(
        "fill",
        help="Auto-fill an empty Jira description from PR context.",
    )
    fp.add_argument("key", help="Jira issue key, e.g. UOF-1234")
    fp.add_argument(
        "--auto", action="store_true",
        help="Programmatic mode: skip preview prompt. Requires --yes.",
    )
    fp.add_argument(
        "--yes", action="store_true",
        help="Non-interactive approval (required for --auto).",
    )
    fp.add_argument(
        "--edit", action="store_true",
        help="Open $EDITOR on the draft before POST.",
    )
    fp.add_argument(
        "--regenerate", action="store_true",
        help="Override the empty-description guard.",
    )
    fp.add_argument(
        "--force", action="store_true",
        help="Override the Bug-issuetype guard (interactive y/N required; "
             "incompatible with --auto).",
    )
    fp.add_argument(
        "--pr-url", default=None,
        help="Cross-repo: use this github.com/<owner>/<repo>/pull/<num> URL "
             "as the PR source instead of the current branch's PR. Useful "
             "when the ticket's code PR lives in a different repo than the "
             "operator's worktree (e.g., multi-repo features).",
    )

    lp = sub.add_parser(
        "link",
        help="(out of scope for this PR — stub raises NotImplementedError)",
    )
    lp.add_argument("key", help="Jira issue key or 'reuse'")

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.cmd == "fill":
        return cmd_fill(args)
    if args.cmd == "link":
        return cmd_link(args)
    parser.error(f"unknown subcommand: {args.cmd}")
    return EXIT_REFUSED  # unreachable


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
