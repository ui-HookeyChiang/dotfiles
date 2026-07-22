#!/usr/bin/env python3
"""reachability.py — consumer-reachability / dead-output detector for one skill.

Read-only. No LLM. Classifies each script / function / JSON-emitted field in a
skill directory into one of six reachability classes, plus a KEEP suppression
for external-contract fields. See SKILL.md + references/engine-internals.md for
the full contract; this module is the deterministic core.

Design source: docs/superpowers/specs/2026-06-13-skill-audit-design.md

Classes:
  a live-consumed      reached from a root via a live invoke/call/read edge
  b test-only          reachable only from tests/ or evals/
  c zero-reader        no live edge anywhere (removal-CANDIDATE, not -safe)
  d doc-orphan         named only in SKILL.md-linked references prose
  e starved-artifact   file-contract with live readers, no resolvable writer (advisory)
  f dangling-target    literal in-skill invoke target missing on disk

Exit codes (mirror the syntax leg):
  0  findings present
  1  tool error (bad path, parse failure)
  2  clean (no findings)
"""

from __future__ import annotations

import ast
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

# ---------------------------------------------------------------------------
# Path resolution — inherit the install-prefix normalization so a SKILL.md that
# invokes `bash ~/.claude/skills/<skill>/scripts/X.sh` resolves to the dev tree.
# ---------------------------------------------------------------------------

INSTALL_PREFIX_RE = re.compile(r"(?:~|\$HOME|\$\{HOME\})/\.claude/skills/([^/\s]+)/")


def normalize_install_path(text: str, skill_dir: Path) -> str:
    """Rewrite an install-prefix path to the audited skill dir, so `stat` and
    edge matching see the on-disk file. `~/.claude/skills/<skill>/scripts/X.sh`
    -> `<skill_dir>/scripts/X.sh` — but ONLY when `<skill>` is the audited skill.
    A `$HOME/.claude/skills/<OTHER-skill>/...` path is a cross-skill reference
    (e.g. flow-dev exec'ing `jira/scripts/jira-cli.py`); rewriting it to the
    audited dir would invent a missing file and fire a false (f). Such paths are
    left untouched so the cross-skill guard skips them."""
    name = skill_dir.name

    def _sub(m: "re.Match[str]") -> str:
        return str(skill_dir) + "/" if m.group(1) == name else m.group(0)

    return INSTALL_PREFIX_RE.sub(_sub, text)


# ---------------------------------------------------------------------------
# Candidate enumeration
# ---------------------------------------------------------------------------

SCRIPT_EXTS = {".sh", ".py", ".lua"}

# function-definition patterns, per language
FUNC_DEF_PATTERNS = [
    re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{"),  # sh
    re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_:.]*)\s*\("),            # lua
    re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("),                   # py
]

_PROPERTY_DECORATOR_RE = re.compile(
    r"^\s*@(?:property|cached_property|functools\.cached_property|abstractproperty)"
    r"\s*(?:#.*)?$"
)


@dataclass
class Candidate:
    kind: str           # "script" | "function" | "field"
    name: str           # basename for script, func name, or field key
    path: str           # defining file (rel to skill_dir)
    line: int
    cls: str = ""       # filled in: a/b/c/d/e/f
    note: str = ""
    is_property: bool = False  # True when decorated @property/@cached_property


@dataclass
class SkillModel:
    skill_dir: Path
    skill_name: str
    scripts: list[Path] = field(default_factory=list)
    candidates: list[Candidate] = field(default_factory=list)


def enumerate_scripts(skill_dir: Path) -> list[Path]:
    out = []
    scripts_dir = skill_dir / "scripts"
    if not scripts_dir.is_dir():
        return out
    for p in sorted(scripts_dir.rglob("*")):
        if p.is_file() and p.suffix in SCRIPT_EXTS:
            out.append(p)
    return out


def enumerate_functions(scripts: list[Path], skill_dir: Path) -> list[Candidate]:
    out = []
    for p in scripts:
        # test infrastructure is not an audited candidate: test-helper functions
        # are called by their own test runner, not the skill's live surface.
        if "tests" in p.relative_to(skill_dir).parts:
            continue
        try:
            lines = p.read_text(errors="replace").splitlines()
        except OSError:
            continue
        is_py = p.suffix == ".py"
        for i, line in enumerate(lines, 1):
            for pat in FUNC_DEF_PATTERNS:
                m = pat.match(line)
                if m:
                    is_prop = False
                    if is_py:
                        # Walk the WHOLE preceding decorator stack (skipping
                        # blanks), so a @property buried under another decorator
                        # (e.g. `@abstractmethod` over `@property`) is still seen.
                        j = i - 2  # 0-based index of the line before `def`
                        while j >= 0:
                            stripped = lines[j].strip()
                            if stripped == "":
                                j -= 1
                                continue
                            if not stripped.startswith("@"):
                                break  # past the decorator stack
                            if _PROPERTY_DECORATOR_RE.match(lines[j]):
                                is_prop = True
                                break
                            j -= 1
                    out.append(Candidate("function", m.group(1),
                                         str(p.relative_to(skill_dir)), i,
                                         is_property=is_prop))
                    break
    return out


# JSON-emitted fields: jq -n built object keys + python json.dump dict keys.
JQ_OBJ_KEY_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\$")
PY_JSON_DUMP_RE = re.compile(r"json\.dump\(")


def enumerate_fields(scripts: list[Path], skill_dir: Path) -> list[Candidate]:
    out = []
    seen = set()
    for p in scripts:
        # test fixtures / infra are not audited candidates — mirror
        # enumerate_functions so a fixture skill's own JSON fields do not leak
        # into the parent skill's audit surface.
        if "tests" in p.relative_to(skill_dir).parts:
            continue
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        rel = str(p.relative_to(skill_dir))
        # jq -n '{ key: $key, ... }' — scan only inside a jq -n block
        if p.suffix == ".sh" and "jq -n" in text:
            for m in JQ_OBJ_KEY_RE.finditer(text):
                key = m.group(1)
                if (rel, key) not in seen:
                    seen.add((rel, key))
                    ln = text[:m.start()].count("\n") + 1
                    out.append(Candidate("field", key, rel, ln))
        # python json.dump({...}) — parse dict keys via ast
        if p.suffix == ".py" and PY_JSON_DUMP_RE.search(text):
            out.extend(_py_json_dump_keys(text, rel, seen))
    return out


def _py_json_dump_keys(text: str, rel: str, seen: set) -> list[Candidate]:
    out = []
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "dump"
                and node.args
                and isinstance(node.args[0], ast.Dict)):
            for k in node.args[0].keys:
                if isinstance(k, ast.Constant) and isinstance(k.value, str):
                    if (rel, k.value) not in seen:
                        seen.add((rel, k.value))
                        out.append(Candidate("field", k.value, rel,
                                             getattr(k, "lineno", 0)))
    return out


# ---------------------------------------------------------------------------
# Corpus — text the engine searches for edges. Wider than the roots.
#   SKILL.md + ALL references/*.md + ALL scripts/ + evals/ + .github run: blocks
#   docs/specs/archive/ is OUT.
# ---------------------------------------------------------------------------

@dataclass
class CorpusFile:
    path: Path
    rel: str
    text: str
    is_test: bool       # under scripts/tests/ or evals/
    is_reference: bool   # under references/
    is_skillmd: bool
    is_ci: bool          # .github/workflows


def build_corpus(skill_dir: Path, repo_root: Path) -> list[CorpusFile]:
    files: list[CorpusFile] = []

    def add(p: Path, **flags):
        try:
            txt = p.read_text(errors="replace")
        except OSError:
            return
        try:
            rel = str(p.relative_to(skill_dir))
        except ValueError:
            rel = str(p)
        files.append(CorpusFile(p, rel, txt, **{
            "is_test": flags.get("is_test", False),
            "is_reference": flags.get("is_reference", False),
            "is_skillmd": flags.get("is_skillmd", False),
            "is_ci": flags.get("is_ci", False),
        }))

    skillmd = skill_dir / "SKILL.md"
    if skillmd.is_file():
        add(skillmd, is_skillmd=True)
    refs = skill_dir / "references"
    if refs.is_dir():
        for p in sorted(refs.rglob("*.md")):
            add(p, is_reference=True)
    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir():
        for p in sorted(scripts_dir.rglob("*")):
            if p.is_file():
                is_test = "tests" in p.relative_to(scripts_dir).parts
                add(p, is_test=is_test)
    evals = skill_dir / "evals"
    if evals.is_dir():
        for p in sorted(evals.rglob("*")):
            if p.is_file():
                add(p, is_test=True)
    # repo CI run: blocks
    gh = repo_root / ".github" / "workflows"
    if gh.is_dir():
        for p in sorted(gh.glob("*.yml")):
            add(p, is_ci=True)
    return files


# ---------------------------------------------------------------------------
# Edge extraction
# ---------------------------------------------------------------------------

# A script basename in any of these positions counts as an invoked edge. The
# spec's edge-type model: an invocation verb / `./` / a `$DIR/basename` path,
# quoted or not. Regex is best-effort and biased to OVER-count (false-alive ≪
# false-dead). The discriminator is "appears in an invocation/path position",
# NOT a bare prose mention of the filename.
_PATH_TOK = r"[A-Za-z0-9._${}\[\]%*/-]*?([A-Za-z0-9._-]+\.(?:sh|py|lua))"
INVOKE_PATTERNS = [
    # verb + (optional path prefix incl $DIR/) + basename: bash $THIS/x.sh, source ./lib/x.sh,
    # python3 scripts/x.py, lua x.lua. The interpreter verb is the entry edge for a
    # non-shell script (a python skill's SKILL.md invokes `python3 .../reachability.py`).
    re.compile(r"""(?:bash|sh|source|exec|python3?|lua|node|ruby|perl|\.)\s+["']?""" + _PATH_TOK),
    # direct quoted dir-var invocation at command position: "$HERE/x.sh" args
    re.compile(r"""["']\$\{?[A-Za-z_]\w*\}?/""" + r"([A-Za-z0-9._-]+\.(?:sh|py|lua))"),
    # ./x.sh or $DIR/x.sh bare at command position
    re.compile(r"""(?:^|[\s|&;(])\.?/?\$?\{?[A-Za-z_]?\w*\}?/?""" + r"([A-Za-z0-9._-]+\.(?:sh|py|lua))\s*(?:\||&|;|\)|$|\s)", re.MULTILINE),
    # command-substitution dir prefix: $(dirname "$0")/x.sh, $(readlink -f ...)/x.sh
    re.compile(r"""\$\((?:dirname|readlink)[^)]*\)/["']?""" + r"([A-Za-z0-9._-]+\.(?:sh|py|lua))"),
]
# dir-var ASSIGNMENT (VAR="$DIR/foo.sh") — the assigned basename is a candidate
# edge when the var is later invoked; we over-count and just take the basename.
DIRVAR_ASSIGN_RE = re.compile(
    r'=\s*["\']?\$\{?[A-Za-z_]\w*\}?/([A-Za-z0-9._-]+\.(?:sh|py|lua))')
# bare-literal assign then invoke: VAR=foo.sh ; bash $VAR  (single-hop)
BARELIT_ASSIGN_RE = re.compile(
    r'([A-Za-z_]\w*)=["\']?([A-Za-z0-9._-]+\.(?:sh|py|lua))["\']?\s*$', re.MULTILINE)


# basename of a script that appears anywhere inside a string token
_BASENAME_IN_STR_RE = re.compile(r"([A-Za-z0-9._-]+\.(?:sh|py|lua))")


@lru_cache(maxsize=1)
def _have_ast_grep() -> bool:
    return shutil.which("ast-grep") is not None


# ast-grep rule: every string-literal node (double + single quoted) in a file.
# A path inside a SHELL STRING is an invocation/path context; a bare prose
# mention is NOT a string node, so this excludes comments/prose by construction.
_AST_GREP_STRING_RULE = (
    "id: str\nlanguage: {lang}\nrule:\n  any:\n"
    "    - kind: string\n    - kind: raw_string\n"
)


def _ast_grep_string_paths(path: Path) -> set[str]:
    """Script basenames found inside string-literal AST nodes of a .sh/.lua
    file (via ast-grep). This is THE edge form regex misses: dynamic
    `source "${BASH_SOURCE[0]%/*}/lib/x.sh"`, `"$HERE/x.sh"`, assign-then-invoke
    `DETECT="$THIS/x.sh"`. ast-grep's `kind: string` excludes comments/prose, so
    a path inside a shell string counts as an invocation/path context but a bare
    prose filename does not. Graceful no-op if ast-grep is absent."""
    if not _have_ast_grep():
        return set()
    lang = {".sh": "bash", ".lua": "lua"}.get(path.suffix)
    if lang is None:
        return set()
    rule = _AST_GREP_STRING_RULE.format(lang=lang)
    try:
        proc = subprocess.run(
            ["ast-grep", "scan", "--inline-rules", rule, "--json", str(path)],
            capture_output=True, text=True, timeout=30)
        nodes = json.loads(proc.stdout or "[]")
    except (OSError, ValueError, subprocess.SubprocessError):
        return set()
    out: set[str] = set()
    for n in nodes:
        for m in _BASENAME_IN_STR_RE.finditer(n.get("text", "")):
            out.add(os.path.basename(m.group(1)))
    return out


def _py_string_paths(text: str) -> set[str]:
    """Script basenames inside python string-literal nodes (stdlib `ast`)."""
    out: set[str] = set()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            for m in _BASENAME_IN_STR_RE.finditer(node.value):
                out.add(os.path.basename(m.group(1)))
    return out


def _py_imported_names(text: str) -> set[str]:
    """Module/symbol names a python source reaches via `import` (stdlib `ast`).

    A python import names a MODULE, not a path token, so the string-literal scan
    misses it entirely. This recovers the import graph, covering every form the
    audit family uses:
      * `import x` / `import a.b.c [as d]`     -> last component (`x`, `c`)
      * `from pkg import n1, n2 [as a]`        -> the imported names + `pkg`'s
                                                  last component (so
                                                  `from advisory.yaml_lite import
                                                  parse_yaml` reaches `yaml_lite`)
      * `from . import n` / `from .sub import n` -> the imported names (`n`);
                                                  relative, so module path empty
    Returns bare names (no `.py`); `_py_import_basenames` maps them to files."""
    out: set[str] = set()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                out.add(alias.name.split(".")[-1])
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                out.add(node.module.split(".")[-1])
            for alias in node.names:
                if alias.name != "*":
                    out.add(alias.name)
    return out


def _py_import_basenames(text: str, scripts_dir: Path | None) -> set[str]:
    """Imported python module names that resolve to a `<name>.py` anywhere under
    the skill's `scripts/` tree (incl. `detectors/`, `advisory/` subdirs). Keeps
    the over-count bias: if `<name>.py` exists under scripts/, record the edge
    even if the same name appears in two packages. A package name maps to its
    `__init__.py` (the package's `__init__` is the imported module)."""
    if scripts_dir is None or not scripts_dir.is_dir():
        return set()
    py_stems: dict[str, set[str]] = {}
    pkg_dirs: set[str] = set()
    for p in scripts_dir.rglob("*.py"):
        py_stems.setdefault(p.stem, set()).add(p.name)
    for p in scripts_dir.rglob("*"):
        if p.is_dir() and (p / "__init__.py").is_file():
            pkg_dirs.add(p.name)
    out: set[str] = set()
    for name in _py_imported_names(text):
        if name in py_stems:
            out |= py_stems[name]
        if name in pkg_dirs:
            out.add("__init__.py")
    return out


def _py_inskill_module_aliases(text: str, scripts_dir: Path | None) -> set[str]:
    """Local binding names in `text` whose import resolves to a python module
    under the skill's `scripts/` tree. Captures the alias the #844 basename
    extractor drops (it records module basenames, never the bound name):
      * `import x as Q` / `import a.b as Q` -> `Q`  (in-skill iff `x.py`/`b.py`)
      * `from pkg import mod as Q`          -> `Q`  (in-skill iff `mod.py`)
      * `from pkg import mod`               -> `mod`
    A binding is recorded ONLY when its module is in-skill, so `import os as O`
    is not a known alias and an `O.fn(` call stays unresolved (no false edge)."""
    if scripts_dir is None or not scripts_dir.is_dir():
        return set()
    py_stems = {p.stem for p in scripts_dir.rglob("*.py")}
    pkg_dirs = {p.name for p in scripts_dir.rglob("*")
                if p.is_dir() and (p / "__init__.py").is_file()}

    def _in_skill(module: str) -> bool:
        last = module.split(".")[-1]
        return last in py_stems or last in pkg_dirs

    out: set[str] = set()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if _in_skill(alias.name):
                    out.add(alias.asname or alias.name.split(".")[-1])
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name != "*" and _in_skill(alias.name):
                    out.add(alias.asname or alias.name)
    return out


# attribute access / qualified call `Q.name`; group(1)=qualifier, group(2)=name.
_ATTR_ACCESS_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)")


def property_accessed(name: str, text: str) -> bool:
    """True if `.name` appears in real attribute-access position `Q.name` with
    ANY qualifier. Used ONLY for @property candidates — a property is structurally
    never bare-called, so any `Q.name` in the live corpus is its only possible
    edge. Skips matches inside a comment or a single-line quoted string (mirrors
    function_called) so a docstring/comment/prose mention `"item.name"` is NOT a
    false edge (review-H3)."""
    for m in _ATTR_ACCESS_RE.finditer(text):
        if m.group(2) != name:
            continue
        ln_start = text.rfind("\n", 0, m.start()) + 1
        ln_end = text.find("\n", m.start())
        line = text[ln_start:ln_end if ln_end != -1 else len(text)]
        col = m.start() - ln_start
        hashpos = _comment_start_col(line)
        if hashpos is not None and col >= hashpos:
            continue
        if _in_string_span(line, col):
            continue
        return True
    return False


def function_qualified_called(name: str, corpus: list["CorpusFile"],
                              scripts_dir: Path | None) -> bool:
    """A qualified attribute/call edge `Q.name` (or `Q.name(`) to `name`, counted
    ONLY when the qualifier `Q` is one of TWO exact forms:
      1. an in-skill module alias — `Q` is bound in the SAME file to a python
         module under the skill's `scripts/` tree (per-file alias map), OR
      2. `self`.
    `@property` access without call parens (`self.is_candidate`, `M.PROP`) counts
    under the same two rules. An unresolved qualifier (`x.read()` where `x` is a
    stdlib file object, not a known alias) does NOT count — staying conservative
    against false-alive on a dead in-skill same-named function."""
    for cf in corpus:
        aliases = (_py_inskill_module_aliases(cf.text, scripts_dir)
                   if cf.path.suffix == ".py" else set())
        for m in _ATTR_ACCESS_RE.finditer(cf.text):
            if m.group(2) != name:
                continue
            qual = m.group(1)
            if qual == "self" or qual in aliases:
                return True
    return False


def invoked_basenames(text: str, path: Path | None = None,
                      scripts_dir: Path | None = None) -> set[str]:
    """All script basenames in an invocation/path position. Hybrid UNION of
    (1) regex invoke-verb forms, (2) AST string-literal nodes (ast-grep for
    .sh/.lua, stdlib `ast` for .py), and (3) python import/call edges (stdlib
    `ast`, mapped to `<name>.py` under `scripts_dir`). Biased to OVER-count
    (false-alive ≪ false-dead). The discriminator is "invocation/path/import
    context", NOT a bare prose mention. `path` enables the string-AST pass on the
    source file; `scripts_dir` enables the import-name -> file mapping. Import
    edges live HERE (not a liveness-only side-channel) so the shared a/b/c
    classification stays consistent — a test-only importer yields a (b)
    test_edge, not a fall-through to (c)."""
    out: set[str] = set()
    for pat in INVOKE_PATTERNS:
        for m in pat.finditer(text):
            out.add(os.path.basename(m.group(1)))
    for m in DIRVAR_ASSIGN_RE.finditer(text):
        out.add(m.group(1))
    for m in BARELIT_ASSIGN_RE.finditer(text):
        var, base = m.group(1), m.group(2)
        if re.search(r"(?:bash|sh|source|exec|\.)\s+\$\{?" + re.escape(var) + r"\}?\b", text):
            out.add(base)
    if path is not None and path.is_file():
        if path.suffix in {".sh", ".lua"}:
            out |= _ast_grep_string_paths(path)
        elif path.suffix == ".py":
            out |= _py_string_paths(text)
            out |= _py_import_basenames(text, scripts_dir)
    return out


# function-call detection: a bare `name` token at command position, or $(name ...)
def function_called(name: str, text: str) -> bool:
    # word-boundary call (command position or substitution), excluding the def
    call = re.compile(r"(?<![\w.-])" + re.escape(name) + r"(?![\w.-])\s*(?:\(|\b)")
    for m in call.finditer(text):
        # skip the definition line `name() {` / `def name(` / `function name`
        ln_start = text.rfind("\n", 0, m.start()) + 1
        ln_end = text.find("\n", m.start())
        line = text[ln_start:ln_end if ln_end != -1 else len(text)]
        # skip a name that sits inside a comment — a header-comment mention of
        # the function (`# pms_check_oracle_history <histfile>`) is NOT a call.
        col = m.start() - ln_start
        hashpos = _comment_start_col(line)
        if hashpos is not None and col >= hashpos:
            continue
        # skip a name that sits inside a single-line quoted string — a sibling
        # docstring/string-literal mention (`"see parse() for details"`) is NOT a
        # call. NOTE: line-by-line model, so a MULTI-LINE triple-quoted docstring
        # spanning lines is NOT tracked here (remaining limitation, issue #2).
        if _in_string_span(line, col):
            continue
        if re.match(r"\s*(?:function\s+)?" + re.escape(name) + r"\s*\(\)\s*\{", line):
            continue
        if re.match(r"\s*def\s+" + re.escape(name) + r"\s*\(", line):
            continue
        return True
    return False


def _inskill_class_methods(scripts: list[Path], skill_dir: Path) -> dict[str, set[str]]:
    """{class_name: {method/attr names}} for python classes defined in-skill
    (excluding tests/). Used to resolve `obj.method()` dispatch edges."""
    out: dict[str, set[str]] = {}
    for p in scripts:
        if p.suffix != ".py":
            continue
        if "tests" in p.relative_to(skill_dir).parts:
            continue
        try:
            tree = ast.parse(p.read_text(errors="replace"))
        except (OSError, SyntaxError):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                members: set[str] = set()
                for item in node.body:
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        members.add(item.name)
                    elif isinstance(item, ast.Assign):
                        for t in item.targets:
                            if isinstance(t, ast.Name):
                                members.add(t.id)
                out[node.name] = members
    return out


def instance_method_called(name: str, text: str,
                           class_methods: dict[str, set[str]]) -> bool:
    """A live edge to method/attr `name` when (1) `name` is a member of some
    in-skill class C, AND (2) C is instantiated in-skill (`C(` appears in text),
    AND (3) an attribute access `.name(` or `.name` occurs in text (outside
    comments and string spans).

    Known bound (documented): does NOT resolve which object bears the `.name`
    access -- an in-skill class owning `name` being instantiated anywhere + any
    `.name` access marks it live. Accepted over-count (false-alive << false-dead).
    Collision-guard: a stdlib `x.read()` does NOT clear in-skill dead `read`
    UNLESS an in-skill class owning `read` is also instantiated."""
    # Check: is `name` a member of ANY in-skill class that is instantiated?
    owning_class_instantiated = False
    for cls_name, members in class_methods.items():
        if name in members:
            # Check if this class is instantiated: `ClassName(` in text
            if re.search(r"\b" + re.escape(cls_name) + r"\s*\(", text):
                owning_class_instantiated = True
                break
    if not owning_class_instantiated:
        return False
    # Check: `.name(` or `.name` access occurs in text, outside comments/strings
    access_re = re.compile(r"\." + re.escape(name) + r"(?!\w)")
    for m in access_re.finditer(text):
        ln_start = text.rfind("\n", 0, m.start()) + 1
        ln_end = text.find("\n", m.start())
        line = text[ln_start:ln_end if ln_end != -1 else len(text)]
        col = m.start() - ln_start
        # skip if inside a comment
        hashpos = _comment_start_col(line)
        if hashpos is not None and col >= hashpos:
            continue
        # skip if inside a string span
        if _in_string_span(line, col):
            continue
        return True
    return False


def _comment_start_col(line: str) -> int | None:
    """Column of the `#` that starts a comment on this line, ignoring `#` inside
    quotes. Returns None if the line has no comment. Shell + python both use #."""
    in_s = in_d = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == "#" and not in_s and not in_d:
            return i
    return None


def _in_string_span(line: str, col: int) -> bool:
    """Whether column `col` of `line` falls inside a single-line quoted span,
    EXCLUDING f-string `{...}` interpolations (those carry real code, e.g.
    `f"id: {parse(x)}"` is a genuine call). Walks the line tracking single/double
    quote state (same machinery as _comment_start_col) plus brace depth while in a
    string. Single-line only — a triple-quoted span crossing lines is invisible to
    this per-line model."""
    in_s = in_d = False
    brace = 0
    for i, ch in enumerate(line):
        if i == col:
            return (in_s or in_d) and brace == 0
        if (in_s or in_d) and ch == "{":
            brace += 1
        elif (in_s or in_d) and ch == "}" and brace > 0:
            brace -= 1
        elif ch == "'" and not in_d and brace == 0:
            in_s = not in_s
        elif ch == '"' and not in_s and brace == 0:
            in_d = not in_d
    return False


def function_dynamic_dispatch(name: str, text: str) -> bool:
    """declare -F name / ${name} indirect / eval near name → reflective use."""
    if re.search(r"declare\s+-F\s+" + re.escape(name) + r"\b", text):
        return True
    if re.search(r"\$\{?" + re.escape(name) + r"\}?\b", text) and "eval" in text:
        return True
    return False


def field_read(key: str, text: str) -> bool:
    pats = [
        # any `.key` path reference — jq read, yq read, OR a test absence-assert
        # (`.key == null`). Per the FP#2 discipline the engine counts ANY
        # reference as an edge and never judges read-vs-assert.
        r"\.\b" + re.escape(key) + r"\b",
        r"^\s*" + re.escape(key) + r"\s*:",          # grep '^key:' style yaml read
        r'\[\s*["\']' + re.escape(key) + r'["\']\s*\]',  # py ["key"]
        r"\.get\(['\"]" + re.escape(key) + r"['\"]",
        # quoted-key JSON-shape declaration: `"key":` in a SKILL.md-linked
        # reference's schema block or a consumer's parse map. A documented schema
        # key is a cross-process producer/consumer contract (FP#2 field pairing).
        r'["\']' + re.escape(key) + r'["\']\s*:',
    ]
    return any(re.search(p, text, re.MULTILINE) for p in pats)


# artifact read/write detection for class (e)
def artifact_paths_read(text: str) -> set[str]:
    out = set()
    for m in re.finditer(r"(?:-f|yq|jq[^|]*|cat|read|<)\s+['\"]?(\.?[\w./-]*\.(?:locked|json|yaml|yml|jsonl))\b", text):
        out.add(os.path.basename(m.group(1)))
    return out


def artifact_paths_written(text: str) -> set[str]:
    out = set()
    for m in re.finditer(r"(?:>|>>|mv\b[^>]*|cp\b[^>]*|tee)\s+['\"]?(\.?[\w./-]*\.(?:locked|json|yaml|yml|jsonl))\b", text):
        out.add(os.path.basename(m.group(1)))
    for m in re.finditer(r"write_text\(['\"]?(\.?[\w./-]*\.(?:locked|json|yaml|yml|jsonl))", text):
        out.add(os.path.basename(m.group(1)))
    return out


# ---------------------------------------------------------------------------
# Roots — SKILL.md, SKILL.md-linked references, CI run: blocks
# ---------------------------------------------------------------------------

# markdown link `](path.md)` or `](path.md#anchor)`, plus backtick `references/x.md`
MD_LINK_RE = re.compile(r"\]\(([^)#]+\.md)(?:#[^)]*)?\)|`(references/[^`]+\.md)`")


def linked_reference_set(corpus: list[CorpusFile]) -> set[str]:
    """references/*.md transitively reachable from SKILL.md via md links."""
    by_rel = {c.rel: c for c in corpus}
    linked: set[str] = set()
    skillmd = next((c for c in corpus if c.is_skillmd), None)
    if not skillmd:
        return linked
    frontier = [skillmd]
    while frontier:
        cur = frontier.pop()
        for m in MD_LINK_RE.finditer(cur.text):
            target = (m.group(1) or m.group(2) or "").lstrip("./")
            # normalize to references/<name>
            base = os.path.basename(target)
            for rel, c in by_rel.items():
                if c.is_reference and os.path.basename(rel) == base and rel not in linked:
                    linked.add(rel)
                    frontier.append(c)
    return linked


def root_texts(corpus: list[CorpusFile], linked_refs: set[str]) -> list[CorpusFile]:
    return [c for c in corpus
            if c.is_skillmd or c.is_ci or (c.is_reference and c.rel in linked_refs)]


# ---------------------------------------------------------------------------
# Liveness fixpoint
# ---------------------------------------------------------------------------

# a basename inside a markdown code span: `write-lock.sh`. A code span in a
# root text is the documented-command idiom (the agent invokes the named script
# in a phase). Bare prose without backticks does NOT match — a script merely
# discussed (e.g. "the old foo.sh") stays dead.
_MD_CODE_SPAN_SCRIPT_RE = re.compile(r"`[^`]*?([A-Za-z0-9._-]+\.(?:sh|py|lua))[^`]*?`")


def _prose_root_basenames(roots: list[CorpusFile]) -> set[str]:
    out: set[str] = set()
    for r in roots:
        if not (r.is_skillmd or r.is_reference):
            continue
        for m in _MD_CODE_SPAN_SCRIPT_RE.finditer(r.text):
            out.add(os.path.basename(m.group(1)))
    return out


# a path-string invoke "$VAR/name.sh" — the harness-target form. Matched on the
# RAW script body (not via invoked_basenames, which over-counts bare basenames);
# this is deliberately the explicit `$DIR/name.sh` quoted/bare path position.
_HARNESS_PATH_INVOKE_RE = re.compile(
    r'\$\{?[A-Za-z_]\w*\}?/([A-Za-z0-9._-]+\.(?:sh|py|lua))')


def _harness_target_basenames(model: SkillModel) -> set[str]:
    """Basenames a script reaches via a "$VAR/name.sh" path invoke, scanning
    EVERY in-skill script (incl. test/lint harnesses). A deprecation shim wired
    into a lint target-list, or a script a test exercises, is a maintained
    consumer — not dead — so its edge confers reachability."""
    by_basename = {p.name: p for p in model.scripts}
    out: set[str] = set()
    for p in model.scripts:
        try:
            txt = p.read_text(errors="replace")
        except OSError:
            continue
        for m in _HARNESS_PATH_INVOKE_RE.finditer(txt):
            base = os.path.basename(m.group(1))
            if base in by_basename and base != p.name:
                out.add(base)
    return out


def compute_liveness(model: SkillModel,
                     roots: list[CorpusFile]) -> dict[str, bool]:
    """Returns {script_basename: is_live}. Monotone BFS from roots over
    invoke/source edges; a dead script's invokes do not confer liveness.
    Two WEAK-edge seed sources widen the root set (FP-refine 2026-06-16):
    prose code-span roots and harness/path-invoke targets — see helpers above."""
    by_basename = {p.name: p for p in model.scripts}
    text_of = {p.name: p.read_text(errors="replace") for p in model.scripts
               if p.is_file()}

    scripts_dir = model.skill_dir / "scripts"
    live: set[str] = set()
    # seed: basenames invoked from any root (roots are .md/.yml → regex path),
    # plus WEAK roots: code-span script names in root prose + harness path-invokes.
    frontier: list[str] = []
    seed = set()
    for r in roots:
        seed |= invoked_basenames(
            normalize_install_path(r.text, model.skill_dir), r.path, scripts_dir)
    seed |= _prose_root_basenames(roots)
    seed |= _harness_target_basenames(model)
    for base in seed:
        if base in by_basename and base not in live:
            live.add(base)
            frontier.append(base)
    # propagate: a live script's invokes are live edges (AST + regex + python
    # imports on the source file — this is what makes a sourced lib OR an
    # imported submodule live once its sourcer/importer is).
    while frontier:
        cur = frontier.pop()
        txt = text_of.get(cur, "")
        for base in invoked_basenames(
                normalize_install_path(txt, model.skill_dir),
                by_basename[cur], scripts_dir):
            if base in by_basename and base not in live:
                live.add(base)
                frontier.append(base)
    return {b: (b in live) for b in by_basename}


def script_test_only(basename: str, corpus: list[CorpusFile], skill_dir: Path) -> bool:
    """Invoked only from test/eval files (no non-test, non-root edge)."""
    scripts_dir = skill_dir / "scripts"
    non_test_edge = False
    test_edge = False
    for c in corpus:
        if basename in invoked_basenames(
                normalize_install_path(c.text, skill_dir), c.path, scripts_dir):
            if c.is_test:
                test_edge = True
            else:
                non_test_edge = True
    return test_edge and not non_test_edge


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

def classify(model: SkillModel, corpus: list[CorpusFile],
             linked_refs: set[str], repo_root: Path) -> list[Candidate]:
    roots = root_texts(corpus, linked_refs)
    liveness = compute_liveness(model, roots)
    all_text = "\n".join(c.text for c in corpus)
    live_corpus = [c for c in corpus
                   if not (c.path.suffix in SCRIPT_EXTS
                           and liveness.get(c.path.name) is False)]
    live_text = "\n".join(c.text for c in live_corpus)
    # Python-only live text for @property edge detection: a property can only be
    # truly accessed in .py source — an `obj.flag` mention in SKILL.md/reference
    # prose is not a real edge. Restricting to .py avoids a prose false-alive.
    live_py_text = "\n".join(c.text for c in live_corpus if c.path.suffix == ".py")
    # Script-only live text for instance-method dispatch: like @property, an
    # `obj.method` in SKILL.md prose is not a real code access. Restricting to
    # script extensions avoids a prose false-alive.
    live_script_text = "\n".join(c.text for c in live_corpus
                                if c.path.suffix in SCRIPT_EXTS)
    text_by_rel = {c.rel: c.text for c in corpus}
    sibling_text = _sibling_corpus_text(model.skill_dir)
    scripts_dir = model.skill_dir / "scripts"

    findings: list[Candidate] = []

    # scripts
    for p in model.scripts:
        base = p.name
        if p.relative_to(model.skill_dir).parts[:2] == ("scripts", "tests"):
            continue  # test scripts are infra, not audited candidates
        if liveness.get(base):
            continue  # (a) live
        if script_test_only(base, corpus, model.skill_dir):
            findings.append(Candidate("script", base,
                                      str(p.relative_to(model.skill_dir)), 0,
                                      cls="b", note="test/eval-only"))
            continue
        # doc-orphan: named only in an UNLINKED reference
        if _named_only_in_unlinked_ref(base, corpus, linked_refs):
            findings.append(Candidate("script", base,
                                      str(p.relative_to(model.skill_dir)), 0,
                                      cls="d", note="named only in unlinked reference"))
            continue
        findings.append(Candidate("script", base,
                                  str(p.relative_to(model.skill_dir)), 0,
                                  cls="c", note="no live invoker (removal-candidate) — also delete co-located tests that exclusively test this symbol"))

    # functions
    class_methods = _inskill_class_methods(model.scripts, model.skill_dir)
    for c in model.candidates:
        if c.kind != "function":
            continue
        if function_called(c.name, live_text):
            continue
        if function_qualified_called(c.name, live_corpus, scripts_dir):
            continue
        # intra-file caller: a call site in the function's OWN defining file is a
        # real edge even when that file is non-live (excluded from live_text). A
        # private helper called only by a sibling function in the same module is
        # not zero-reader — deleting it breaks that sibling. function_called skips
        # the definition line, so a lone def with no call still falls through to (c).
        if function_called(c.name, text_by_rel.get(c.path, "")):
            continue
        # Bounded in-skill instance-method dispatch: if `name` is a member of
        # an in-skill class that is instantiated, and `.name` access occurs,
        # treat as live. Does NOT resolve which object bears the access —
        # accepted over-count (false-alive << false-dead). Scoped to script
        # text (not live_text) so a prose `.name` mention in SKILL.md/reference
        # docs cannot form a false edge (same rationale as @property).
        if instance_method_called(c.name, live_script_text, class_methods):
            continue
        if function_dynamic_dispatch(c.name, all_text):
            c.cls, c.note = "c", "reflective dispatch found — ADVISORY, verify before removal"
            findings.append(c)
            continue
        # @property accept-path: a property is structurally never bare-called —
        # attribute access is its only possible call edge. If Q.name appears in
        # the live PYTHON corpus with ANY qualifier, it is live. Scoped to .py
        # (not live_text) so a prose `obj.name` mention in SKILL.md/reference
        # docs cannot form a false edge. Residual accepted risk: two classes
        # with a same-named @property where only one is accessed — same genus as
        # the self/alias collision the qualified-call rule already tolerates.
        if c.is_property and property_accessed(c.name, live_py_text):
            continue
        if c.name.startswith("__") and c.name.endswith("__"):
            c.cls = "adv"
            c.note = "dunder — implicit-invocation, verify before removal"
            findings.append(c)
            continue
        c.cls, c.note = "c", "no static caller (removal-candidate)"
        findings.append(c)

    # fields (JSON-mediated) — Tier-1 cross-script pairing: a field WRITTEN here
    # is live if READ anywhere in the corpus (jq `.key`, `["key"]`, `.get("key")`,
    # or a documented `"key":` schema in a SKILL.md-linked reference). The read
    # may live in a sibling script that the liveness BFS wrongly excluded, so the
    # pairing scan uses the FULL corpus minus the field's OWN defining file (a
    # write site must not self-satisfy as a read). A real read is real liveness;
    # false-negative risk is low.
    for c in model.candidates:
        if c.kind != "field":
            continue
        pairing_text = "\n".join(cf.text for cf in corpus if cf.rel != c.path)
        if field_read(c.name, pairing_text):
            continue
        # KEEP: external contract
        if _external_contract(c.name, model, sibling_text):
            c.cls, c.note = "KEEP", "external-contract (sibling/CI reads it)"
            findings.append(c)
            continue
        c.cls, c.note = "c", "JSON field written, never read (removal-candidate)"
        findings.append(c)

    # (e) starved artifacts + (f) dangling targets
    findings.extend(_artifact_findings(corpus, sibling_text))
    findings.extend(_dangling_findings(model, corpus, repo_root))

    # (g) stale-doc: prose paragraphs whose subject is a dead symbol
    dead_names = {f.name for f in findings if f.cls == "c"}
    # live_names = NARROW identifier set from LIVE SCRIPT files (non-test, non-dead).
    # Only def/class names, module-level assignment targets, and string-literal
    # identifiers — NOT every word in the live corpus. A blanket token scan would
    # pull in comment/prose words and make (g) never fire on a real skill.
    dead_script_basenames = {p.name for p in model.scripts if p.name in dead_names}
    _live_script_text = "\n".join(
        c.text for c in corpus
        if c.path.suffix in SCRIPT_EXTS
        and not c.is_test
        and c.path.name not in dead_script_basenames
    )
    def_names = set(re.findall(r"^(?:def|class)\s+([A-Za-z_][A-Za-z0-9_]*)",
                               _live_script_text, re.MULTILINE))
    assigned = set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=",
                              _live_script_text, re.MULTILINE))
    str_lits = set(re.findall(r"""["']([A-Za-z_][A-Za-z0-9_]*)["']""",
                              _live_script_text))
    live_names = ((def_names | assigned | str_lits)
                  | {c.name for c in model.candidates if c.cls in ("", "a")}
                  | {p.name for p in model.scripts}) - dead_names
    findings.extend(_stale_doc_findings(dead_names, live_names, corpus, model))

    return findings


def _paragraphs(text: str) -> list[str]:
    """Split text by blank lines, return non-empty blocks."""
    return [b for b in re.split(r"\n\s*\n", text) if b.strip()]


def _stale_doc_findings(dead_names: set[str], live_names: set[str],
                        corpus: list[CorpusFile], model: SkillModel) -> list[Candidate]:
    """(g) stale-doc: a prose paragraph (SKILL.md / reference markdown) whose
    SUBJECT is a dead symbol. Subject test (no LLM): the paragraph names a dead
    symbol AND names NO live symbol -- a mixed paragraph describes live surface too
    and is NOT flagged."""
    out: list[Candidate] = []
    flagged: set[str] = set()
    for c in corpus:
        if not (c.is_skillmd or c.is_reference):
            continue
        for para in _paragraphs(c.text):
            # which dead names appear in this paragraph?
            dead_in_para = {n for n in dead_names if re.search(r"\b" + re.escape(n) + r"\b", para)}
            if not dead_in_para:
                continue
            # does any live name also appear?
            live_in_para = any(re.search(r"\b" + re.escape(n) + r"\b", para) for n in live_names)
            if live_in_para:
                continue
            # flag each dead name in this paragraph
            for n in dead_in_para:
                if n not in flagged:
                    flagged.add(n)
                    out.append(Candidate("function", n, c.rel, 0,
                                         cls="g", note="stale-doc: prose paragraph subject is dead symbol"))
    return out


def _named_only_in_unlinked_ref(base: str, corpus, linked_refs) -> bool:
    in_unlinked = False
    in_anything_live = False
    for c in corpus:
        if base in c.text:
            if c.is_reference and c.rel not in linked_refs:
                in_unlinked = True
            elif c.is_skillmd or c.is_ci or (c.is_reference and c.rel in linked_refs):
                in_anything_live = True
    return in_unlinked and not in_anything_live


def _sibling_corpus_text(skill_dir: Path) -> str:
    """Resolved sibling-skill corpus: sibling dirs of the skill-under-audit."""
    parts = []
    parent = skill_dir.parent
    for d in sorted(parent.iterdir()) if parent.is_dir() else []:
        if d.is_dir() and d != skill_dir and (d / "SKILL.md").is_file():
            for p in d.rglob("*"):
                if p.is_file() and (p.suffix in SCRIPT_EXTS or p.suffix == ".md"):
                    try:
                        parts.append(p.read_text(errors="replace"))
                    except OSError:
                        pass
    return "\n".join(parts)


def _external_contract(name: str, model: SkillModel, sibling_text: str) -> bool:
    # author marker on emit site or sibling reads it
    for p in model.scripts:
        try:
            t = p.read_text(errors="replace")
        except OSError:
            continue
        if re.search(r"#\s*(?:contract|schema-out|external-writer)\b.*" + re.escape(name), t):
            return True
    return field_read(name, sibling_text) or (name in sibling_text)


def _artifact_findings(corpus, sibling_text) -> list[Candidate]:
    read_in: dict[str, str] = {}
    written: set[str] = set()
    for c in corpus:
        if c.is_test:
            continue
        for a in artifact_paths_read(c.text):
            read_in.setdefault(a, c.rel)
        written |= artifact_paths_written(c.text)
    sibling_written = artifact_paths_written(sibling_text)
    ci_text = "\n".join(c.text for c in corpus if c.is_ci)
    ci_written = artifact_paths_written(ci_text)
    out = []
    for art, rel in sorted(read_in.items()):
        if art in written or art in sibling_written or art in ci_written:
            continue
        out.append(Candidate("artifact", art, rel, 0, cls="e",
                             note="live readers, no resolvable writer — ADVISORY, verify external producer"))
    return out


def _fenced_code_only(text: str) -> str:
    """Return only the ``` fenced code-block content of a markdown file — a
    skill is entered by the command shown in a fence, while prose around it may
    merely *name* a script (not invoke it)."""
    out, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            out.append(line)
    return "\n".join(out)


# An example/proposal marker: prose that frames a fenced command as illustrative,
# not a real invoke site (a "Proposed refactor:" sample, an `e.g.` snippet). The
# net-new FP-3 surface beyond the existing $/<>/single-char guards.
#
# STRONG vs WEAK split (false-negative guard): STRONG markers
# (`proposed refactor`, `example`, `e.g.`) unambiguously frame illustration, so
# they may match EITHER the introducing prose line OR the fence body. WEAK markers
# (bare `proposed`, bare `would`) are common English words that can appear in the
# intro sentence of a REAL invoke ("Running this would clean up:") — they may
# match ONLY inside the fence body, never the intro line, so a real dangling
# invoke is not falsely suppressed (false-alive << false-dead).
_EXAMPLE_MARKER_STRONG_RE = re.compile(
    r"\b(?:proposed\s+refactor|example|e\.g\.)\b", re.IGNORECASE)
_EXAMPLE_MARKER_RE = re.compile(
    r"\b(?:proposed\s+refactor|proposed|example|e\.g\.|would)\b", re.IGNORECASE)

# a script basename inside an invoke token (`bash scripts/x.sh`) — used to scope
# example suppression to the exact basename in a marked fence.
_INVOKE_BASENAME_RE = re.compile(
    r"(?:bash|sh|source|exec|python3?|lua|node|\.)\s+[\"']?"
    r"(?:\$\{?[A-Za-z_]\w*\}?/)?[\w./<>-]*?([A-Za-z0-9._-]+\.(?:sh|py|lua))")


def _example_marked_basenames(text: str) -> set[str]:
    """Script basenames whose invoke token sits in an example/proposal-marked
    context within a markdown file: either the SAME fenced block carries a marker,
    or the prose line introducing that fence does. Anchored to the fence/marker
    line — NOT whole-file keyword proximity — so a real unmarked invoke fence near
    an incidental marker word elsewhere still fires (f)."""
    lines = text.splitlines()
    out: set[str] = set()
    i = 0
    n = len(lines)
    while i < n:
        if lines[i].lstrip().startswith("```"):
            # the introducing prose line = nearest non-blank line above the fence
            intro = ""
            j = i - 1
            while j >= 0:
                if lines[j].strip():
                    intro = lines[j]
                    break
                j -= 1
            # collect the fence body
            body: list[str] = []
            i += 1
            while i < n and not lines[i].lstrip().startswith("```"):
                body.append(lines[i])
                i += 1
            block = "\n".join(body)
            # intro: STRONG markers only (weak words like "would"/"proposed" can
            # appear in a real invoke's intro sentence). body: full marker set.
            marked = bool(_EXAMPLE_MARKER_STRONG_RE.search(intro)
                          or _EXAMPLE_MARKER_RE.search(block))
            if marked:
                for m in _INVOKE_BASENAME_RE.finditer(block):
                    out.add(os.path.basename(m.group(1)))
            i += 1  # skip the closing fence
        else:
            i += 1
    return out


def _strip_line_comments(text: str) -> str:
    """Drop the comment tail of each line (`#` for sh/py, `--` for lua), so a
    `# foo.sh writes …` comment is not read as an invocation. Quote-aware via
    the existing comment-column finder."""
    out = []
    for line in text.splitlines():
        col = _comment_start_col(line)
        if col is not None:
            line = line[:col]
        # lua line comments
        dd = line.find("--")
        if dd != -1:
            line = line[:dd]
        out.append(line)
    return "\n".join(out)


def _dangling_findings(model, corpus, repo_root) -> list[Candidate]:
    """Literal in-skill invoke target whose file does not exist on disk.

    A dangling target is a broken *in-skill* invocation site — it lives in this
    skill's script source or a SKILL.md / reference fenced command, and points at
    a path that should be in THIS skill. The scan EXCLUDES:
      - eval/corpus data (`*.json`, test files): test data names other skills'
        scripts in prose, not as invocations;
      - `.github/workflows/*.yml` `run:` blocks: CI invokes SIBLING skills via
        repo-root-relative paths (`flow-dev/scripts/...`, `_shared/eval/...`)
        — those are other skills' concern, never this skill's dangling target.
    A token that resolves anywhere (skill dir OR repo root) exists → not (f); a
    token whose path is clearly under another skill / `_shared/` is skipped."""
    out = []
    seen = set()
    for c in corpus:
        # skip eval/corpus data + CI (both name other skills' scripts, not in-skill invokes)
        if c.is_test or c.is_ci or c.rel.endswith(".json"):
            continue
        # an invoke target is a real command, not a comment / prose mention.
        # For markdown (SKILL.md / references) scan only fenced code blocks;
        # for scripts strip the comment portion of each line. This keeps a
        # `# foo.sh writes …` comment or a `lua script.lua` prose example from
        # firing a false (f) (the FP-safe definition: invoke SITES only).
        example_marked: set[str] = set()
        if c.is_skillmd or c.is_reference:
            scan_src = _fenced_code_only(c.text)
            # suppress invoke tokens framed as illustrative (Proposed refactor:,
            # e.g.) — a hypothetical sample fence is not a real dangling target.
            example_marked = _example_marked_basenames(c.text)
        else:
            scan_src = _strip_line_comments(c.text)
        norm = normalize_install_path(scan_src, model.skill_dir)
        for m in re.finditer(
                r"(?:bash|sh|source|exec|python3?|lua|node|\.)\s+([\"']?)"
                r"((?:\$\{?[A-Za-z_]\w*\}?/)?[\w./<>-]+\.(?:sh|py|lua))\1", norm):
            tok = m.group(2)
            if "$" in tok or "<" in tok or ">" in tok:
                continue  # variable/computed/placeholder → unresolved, never (f)
            base = os.path.basename(tok)
            stem = base.rsplit(".", 1)[0]
            # skip doc-example placeholders: single-char stems (X.sh / x.sh).
            if len(stem) <= 1:
                continue
            # skip an invoke literal framed as an example/proposal in a marked fence.
            if base in example_marked:
                continue
            # a path pointing into another skill / shared commons is NOT this
            # skill's dangling target (cross-skill reference).
            first = tok.lstrip("./").split("/", 1)[0]
            if "/" in tok and first not in ("scripts", "references", "evals", str(model.skill_dir.name)) and not tok.startswith(str(model.skill_dir)):
                continue
            # resolve relative to skill_dir, its scripts/, OR repo root.
            cand_paths = [model.skill_dir / tok,
                          model.skill_dir / "scripts" / base,
                          repo_root / tok,
                          Path(tok)]
            if any(cp.exists() for cp in cand_paths):
                continue
            # must be an in-skill-shaped path (not a system binary)
            if "/" not in tok and "." not in base:
                continue
            if base in {p.name for p in model.scripts}:
                continue
            if base in seen:
                continue
            seen.add(base)
            out.append(Candidate("invoke-target", base, c.rel, 0, cls="f",
                                 note="literal invoke target missing on disk"))
    return out


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

CLASS_LABEL = {
    "a": "live-consumed", "b": "test-only", "c": "zero-reader (removal-candidate)",
    "d": "doc-orphan", "e": "starved-artifact (advisory)",
    "f": "dangling-target", "g": "stale-doc (advisory)",
    "KEEP": "external-contract (KEEP)",
    "adv": "implicit-invocation (advisory)",
}
CLASS_SEVERITY = {"c": "HIGH", "f": "HIGH", "d": "MED", "b": "LOW",
                  "e": "ADVISORY", "g": "ADVISORY", "adv": "ADVISORY", "KEEP": "—"}


def render(skill_name: str, findings: list[Candidate]) -> str:
    actionable = [f for f in findings if f.cls in {"c", "d", "e", "f"}]
    lines = [f"## Reachability findings", "",
             f"Skill: `{skill_name}`  ·  findings: {len(actionable)} "
             f"(b/adv/KEEP suppressed below)", ""]
    if not findings:
        lines.append("No findings — every script / function / field is reachable.")
        return "\n".join(lines)
    lines.append("| Class | Severity | Kind | Name | Where | Note |")
    lines.append("|---|---|---|---|---|---|")
    order = {"c": 0, "f": 1, "e": 2, "d": 3, "g": 4, "adv": 5, "b": 6, "KEEP": 7}
    for f in sorted(findings, key=lambda x: (order.get(x.cls, 9), x.name)):
        loc = f.path + (f":{f.line}" if f.line else "")
        lines.append(f"| ({f.cls}) {CLASS_LABEL.get(f.cls, f.cls)} | "
                     f"{CLASS_SEVERITY.get(f.cls, '—')} | {f.kind} | "
                     f"`{f.name}` | `{loc}` | {f.note} |")
    if any(f.cls == "c" for f in findings):
        lines.append("")
        lines.append("> **Removal rule**: for every `(c) zero-reader` finding, also delete "
                     "the tests that exclusively test that symbol — otherwise the test suite "
                     "becomes a false-positive reachability signal for future audits.")
    return "\n".join(lines)


def find_repo_root(start: Path) -> Path:
    cur = start.resolve()
    while cur != cur.parent:
        if (cur / ".git").exists():
            return cur
        cur = cur.parent
    return start.resolve().parent


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in {"-h", "--help"}:
        print(__doc__)
        return 1
    skill_dir = Path(argv[1]).resolve()
    if not skill_dir.is_dir():
        print(f"reachability: not a directory: {skill_dir}", file=sys.stderr)
        return 1
    if not (skill_dir / "SKILL.md").is_file():
        print(f"reachability: no SKILL.md in {skill_dir}", file=sys.stderr)
        return 1

    repo_root = find_repo_root(skill_dir)
    model = SkillModel(skill_dir, skill_dir.name)
    model.scripts = enumerate_scripts(skill_dir)
    model.candidates = (enumerate_functions(model.scripts, skill_dir)
                        + enumerate_fields(model.scripts, skill_dir))

    corpus = build_corpus(skill_dir, repo_root)
    linked_refs = linked_reference_set(corpus)
    findings = classify(model, corpus, linked_refs, repo_root)

    print(render(model.skill_name, findings))
    actionable = [f for f in findings if f.cls in {"c", "d", "e", "f"}]
    return 0 if actionable else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
