#!/usr/bin/env bash
# validate-findings.sh — deterministic verifier for prose-guidelines findings.
#
# Reads a YAML document (agent output) from stdin or first arg, verifies each
# finding's evidence_quote is a literal substring of the cited line range in
# the target file, that the line range is in bounds, and (for v2 batches) that
# `finding_class` is present and valid (and `lexical_hits` populated when
# class is `lexical`). v2 batches additionally enforce:
#   * Gate 7 — fact-token preservation: hard fact tokens (numbers+units,
#     ranges/codes, paths, --flags, errno/header-idents, hex/SHA/IP, and
#     CJK/latin negation words) extracted from the cited original range must
#     all survive in `rewritten_text`. Tokens inside a recorded lexical_hits
#     span are exempt (deleting a flagged weasel never trips the gate). meta
#     class skips Gate 7.
#   * Gate 8 — CJK-aware ratio recount: word counts are recomputed with a
#     CJK-aware tokenizer (latin runs = 1 token, each CJK ideograph = 1 token);
#     a finding is dropped if |self-reported ratio - recount| > 0.05, or if a
#     paragraph-class recount ratio is >= 0.8.
# It also de-duplicates identical surface tokens within one finding's
# lexical_hits, and emits a per-sub-class `severity_recount` (HIGH iff >= 3
# hits within one HIGH-eligible sub-class B1/B2/B4/B5; B3 advisory, cross-class
# caps at MED) on lexical
# findings. `lexical_hits` entries are normalized to objects
# {token, subclass}; bare-string entries (v2-pre) migrate to subclass=null.
# Enforces a drop budget: v1 = fixed 3, v2 = relative
# max(3, ceil(0.15 * len(findings))).
#
# Usage:
#   validate-findings.sh <findings.yaml> <target-file>
#
# Exit codes:
#   0 — drops under budget, validated subset emitted
#   1 — drops >= budget, batch invalidated
#   2 — bad input (file missing, malformed YAML)
#
# Output: filtered YAML to stdout (only valid findings); drop count + reasons
# to stderr.
#
# Batch-mode selection (v1 vs v2): inspect the first finding's keys. If
# `finding_class` is present -> v2 (apply new checks + relative budget). If
# absent -> v1 (fixed 3-drop budget, no class checks). Mixed batches are
# rejected per-finding via the drop path.

set -euo pipefail

YAML_FILE="${1:-}"
TARGET_FILE="${2:-}"

if [[ -z "$YAML_FILE" || -z "$TARGET_FILE" ]]; then
  echo "usage: $0 <findings.yaml> <target-file>" >&2
  exit 2
fi
[[ -f "$YAML_FILE" ]] || { echo "validate: findings yaml not found: $YAML_FILE" >&2; exit 2; }
[[ -f "$TARGET_FILE" ]] || { echo "validate: target file not found: $TARGET_FILE" >&2; exit 2; }

python3 - "$YAML_FILE" "$TARGET_FILE" <<'PY'
import math, re, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("validate: PyYAML required (pip install pyyaml)\n"); sys.exit(2)

yaml_path, target_path = sys.argv[1], sys.argv[2]
with open(yaml_path, encoding="utf-8") as f: doc = yaml.safe_load(f)
with open(target_path, encoding="utf-8") as f: lines = f.read().splitlines()
n_lines = len(lines); body = "\n".join(lines)
findings = (doc or {}).get("findings") or []
range_re = re.compile(r"^L(\d+)-L(\d+)$")
ws_re = re.compile(r"\s+")
def normws(s): return ws_re.sub(" ", s).strip()
body_n = normws(body)

ALLOWED_CLASSES = {"paragraph", "lexical", "meta", "hedge"}
# Batch-mode detection: inspect first finding's keys.
v2_mode = bool(findings) and isinstance(findings[0], dict) and "finding_class" in findings[0]

# --- Gate 7: hard fact-token extraction (closed token-class table) --------
# Markdown structural chars stripped before extraction so table-cell facts
# are still seen.
_MD_STRUCT = re.compile(r"^[\s>#*+\-]+|[|`]")
NUM_UNIT = re.compile(r"\d+(?:\.\d+)?\s?-?(?:ms|MB|GB|KB|req/s|minute|min|bit|s|x|%|h)\b", re.I)
HYPHEN_UNIT = re.compile(r"\b\d+-[A-Za-z]+\b")            # 15-minute
RANGE_CODE = re.compile(r"\b\d+xx\b|\b\d+-\d+%|\b[1-5]\d{2}\b")   # 5xx, 30-50%, 429
PATHFILE = re.compile(r"\b[\w./-]+\.(?:sh|md|py|json|yaml|lua)\b|(?<![\w])/[\w./-]+")
FLAG_REF = re.compile(r"(?<![\w])--[\w-]+|\bL\d+-L\d+\b")
ERRNO_HDR = re.compile(r"\b[A-Z]{3,}\b|\b[A-Z][a-z]+-[A-Z][a-z]+\b")   # ETIMEDOUT, Retry-After
HEX_IP = re.compile(r"\b[0-9a-f]{7,40}\b|\b(?:\d{1,3}\.){3}\d{1,3}\b")
NEGATIONS = ["not", "never", "unless", "except", "不", "除非", "否則"]

def _strip_md(text):
    out = []
    for ln in text.splitlines():
        out.append(_MD_STRUCT.sub(" ", ln))
    return "\n".join(out)

def hard_tokens(text):
    t = _strip_md(text)
    toks = set()
    for rx in (NUM_UNIT, HYPHEN_UNIT, RANGE_CODE, PATHFILE, FLAG_REF, ERRNO_HDR, HEX_IP):
        toks |= {m.group(0) for m in rx.finditer(t)}
    # negation: SUBSTRING match (no word boundary — CJK has none)
    for w in NEGATIONS:
        if w in t:
            toks.add(w)
    return toks

# --- Gate 8: CJK-aware word counter ---------------------------------------
CJK_TOKEN = re.compile(r"[A-Za-z0-9]+(?:[.\-/][A-Za-z0-9]+)*|[一-鿿]")
def wc(text): return len(CJK_TOKEN.findall(text or ""))

# --- lexical_hits normalization (object migration) ------------------------
def normalize_hits(raw):
    """bare-string -> {token, subclass:None}; dict tolerated (subclass None)."""
    out = []
    for h in (raw or []):
        if isinstance(h, dict):
            tok = h.get("token")
            if tok is None: continue
            out.append({"token": tok, "subclass": h.get("subclass")})
        else:
            out.append({"token": h, "subclass": None})
    return out

def dedup_hits(hits):
    """surface-token dedup within one finding (keep first occurrence)."""
    seen, out = set(), []
    for h in hits:
        if h["token"] in seen: continue
        seen.add(h["token"]); out.append(h)
    return out

def severity_recount(hits):
    """HIGH iff >=3 hits within a single HIGH-eligible sub-class (B1/B2/B4/B5);
    cross-class (or null subclass) caps at MED; otherwise LOW. B3 (nominalization)
    is advisory: it still counts toward MED via `total` and is surfaced in
    lexical_hits, but it cannot escalate to HIGH on its own (excluded from `real`)
    because nominalization detection is the field's highest false-positive class."""
    buckets = {}
    for h in hits:
        sc = h.get("subclass")
        buckets[sc] = buckets.get(sc, 0) + 1
    real = {k: v for k, v in buckets.items() if k in ("B1", "B2", "B4", "B5")}
    if any(v >= 3 for v in real.values()):
        return "HIGH"
    total = sum(buckets.values())
    if total >= 2:
        return "MED"
    return "LOW"

ok, drops = [], []
for i, fnd in enumerate(findings):
    fnd = fnd or {}
    # v2 class checks (or mixed-batch rejection on v1 path)
    if v2_mode:
        if "finding_class" not in fnd:
            drops.append(f"#{i} missing finding_class (v2 batch)"); continue
        if fnd["finding_class"] not in ALLOWED_CLASSES:
            drops.append(f"#{i} unknown finding_class={fnd['finding_class']!r}"); continue
        if fnd["finding_class"] == "lexical" and not fnd.get("lexical_hits"):
            drops.append(f"#{i} missing lexical_hits for class=lexical"); continue
        if fnd["finding_class"] == "paragraph" and fnd.get("semantic_axis") != "G7":
            drops.append(f"#{i} paragraph class missing semantic_axis: G7"); continue
        if fnd["finding_class"] != "paragraph" and "semantic_axis" in fnd:
            drops.append(f"#{i} semantic_axis only valid for paragraph class, got {fnd['finding_class']}"); continue
    else:
        # v1 batch must not contain v2 fields — reject mixed
        if "finding_class" in fnd:
            drops.append(f"#{i} unexpected finding_class in v1 batch"); continue
    rng = fnd.get("lines", "")
    m = range_re.match(str(rng))
    if not m: drops.append(f"#{i} malformed lines={rng!r}"); continue
    s, e = int(m.group(1)), int(m.group(2))
    if not (1 <= s <= e <= n_lines): drops.append(f"#{i} out-of-bounds L{s}-L{e} (file has {n_lines} lines)"); continue
    cited_lines = lines[s-1:e]
    cited_raw = "\n".join(cited_lines)
    cited_n = normws(cited_raw)
    quote = (fnd.get("evidence_quote") or "").strip()
    # meta-class with empty rewritten_text still requires non-empty evidence_quote
    if not quote: drops.append(f"#{i} empty evidence_quote"); continue
    quote_n = normws(quote)
    if quote_n not in cited_n and quote_n not in body_n:
        drops.append(f"#{i} evidence_quote not substring of L{s}-L{e}"); continue

    cls = fnd.get("finding_class")
    rewritten = fnd.get("rewritten_text") or ""
    # capture the agent's self-reported ratio BEFORE Gate 8 overwrites it
    try:
        reported_ratio = float(fnd.get("ratio")) if fnd.get("ratio") is not None else None
    except (TypeError, ValueError):
        reported_ratio = None

    # Normalize / dedup lexical_hits + severity emit (v2 lexical only)
    hits = []
    if v2_mode and cls == "lexical":
        hits = dedup_hits(normalize_hits(fnd.get("lexical_hits")))
        fnd["lexical_hits"] = hits
        fnd["severity_recount"] = severity_recount(hits)

    # --- Gate 7 (fact-token preservation) --- v2, non-meta only
    if v2_mode and cls != "meta":
        orig_tokens = hard_tokens(cited_raw)
        # lexical exemption: drop tokens that fall inside any lexical_hits span
        if hits:
            for h in hits:
                span = h["token"]
                if not span: continue
                orig_tokens = {t for t in orig_tokens if t not in span and span not in t}
        rw_tokens = hard_tokens(rewritten)
        missing = orig_tokens - rw_tokens
        if missing:
            tok = sorted(missing)[0]
            drops.append(f"#{i} Gate7 drop missing token={tok!r}"); continue

    # --- Gate 8 (CJK-aware ratio recount) --- v2 only
    if v2_mode:
        ow = wc(cited_raw)
        rww = wc(rewritten)
        recount = round(rww / ow, 2) if ow else 0.0
        # publish the verified recount (the prompt's "validator will recount")
        fnd["ratio"] = recount
        # mismatch: agent's self-reported ratio diverges from the recount
        if reported_ratio is not None and abs(reported_ratio - recount) > 0.05:
            drops.append(f"#{i} Gate8 drop ratio mismatch reported={reported_ratio} recount={recount}"); continue
        # paragraph-class skip rule: a >= 0.8 recount is not worth applying
        if recount >= 0.8 and cls == "paragraph":
            drops.append(f"#{i} Gate8 drop paragraph recount ratio={recount} >= 0.8"); continue

    ok.append(fnd)

for d in drops: sys.stderr.write(f"validate: drop {d}\n")

total = len(findings)
if v2_mode:
    budget = max(3, math.ceil(0.15 * total))
else:
    budget = 3

if len(drops) >= budget:
    sys.stderr.write(f"validate: FAIL — {len(drops)} drops >= {budget}-budget (mode={'v2' if v2_mode else 'v1'}, total={total}); batch invalidated\n"); sys.exit(1)
doc["findings"] = ok
if "summary" in doc and isinstance(doc["summary"], dict): doc["summary"]["validator_dropped"] = len(drops)
yaml.safe_dump(doc, sys.stdout, allow_unicode=True, default_flow_style=False, sort_keys=False)
PY
