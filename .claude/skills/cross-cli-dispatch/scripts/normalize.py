#!/usr/bin/env python3
"""Normalize one backend run into a ledger JSON line on stdout.

Env in: BACKEND MODEL EFFORT TIER RUN_DIR RC LAT.
Reads $RUN_DIR/raw.out + stderr.log. Exit: 0 ok, 75 quota, 1 no result.
Stamps `ts` (ISO-8601 UTC, second precision) at completion.

JSON extraction uses raw_decode (model-eval harness-pitfalls erratum #7):
it stops at the first complete JSON object, so trailing prose cannot break
the parse the way a greedy first-to-last-brace regex would.
"""
import json
import os
import re
import sys
from datetime import datetime, timezone

QUOTA_RE = re.compile(
    r"rate.?limit|quota|usage limit|too many requests|\b429\b"
    r"|limit (?:has been )?reached|insufficient[_ ]credits|out of credits",
    re.I,
)


def decode_first_json(text):
    i = text.find("{")
    if i < 0:
        return None
    try:
        return json.JSONDecoder().raw_decode(text[i:])[0]
    except Exception:
        return None


def parse_claude(raw):
    d = decode_first_json(raw) or {}
    u = d.get("usage") or {}
    return {
        "result": d.get("result") or "",
        "num_turns": d.get("num_turns"),
        "cost_usd": d.get("total_cost_usd"),
        "in_tok": u.get("input_tokens"),
        "out_tok": u.get("output_tokens"),
        "cache_create": u.get("cache_creation_input_tokens"),
        "cache_read": u.get("cache_read_input_tokens"),
        "api_ms": d.get("duration_api_ms"),
    }


def parse_cursor(raw):
    """cursor-agent spells usage keys in camelCase; accept both spellings."""
    d = decode_first_json(raw) or {}
    u = d.get("usage") or {}
    result = d.get("result") or d.get("text") or d.get("response") or ""

    def first(src, *names):
        """First key present with a non-None value; 0 and 0.0 count as present."""
        for n in names:
            if src.get(n) is not None:
                return src[n]
        return None

    return {
        "result": result,
        "num_turns": d.get("num_turns"),
        "cost_usd": first(d, "total_cost_usd", "cost_usd"),
        "in_tok": first(u, "input_tokens", "inputTokens"),
        "out_tok": first(u, "output_tokens", "outputTokens"),
        "cache_create": first(u, "cache_creation_input_tokens", "cacheWriteTokens"),
        "cache_read": first(u, "cache_read_input_tokens", "cacheReadTokens"),
        "api_ms": d.get("duration_api_ms"),
    }


def parse_codex(raw):
    """JSONL event stream: last agent message wins; usage from token_count."""
    result, usage, turns = "", {}, 0
    for line in raw.splitlines():
        ev = decode_first_json(line)
        if not ev:
            continue
        item = ev.get("item") or ev.get("msg") or ev
        typ = item.get("type") or ev.get("type") or ""
        if "agent_message" in str(typ):
            result = item.get("text") or item.get("message") or result
            turns += 1
        for key in ("usage", "token_usage", "info"):
            u = item.get(key) or ev.get(key)
            if isinstance(u, dict) and (
                "input_tokens" in u or "total_token_usage" in u
            ):
                usage = u.get("total_token_usage", u)
    return {
        "result": result,
        "num_turns": turns or None,
        "cost_usd": None,
        "in_tok": usage.get("input_tokens"),
        "out_tok": usage.get("output_tokens"),
        "cache_create": None,
        "cache_read": usage.get("cached_input_tokens"),
        "api_ms": None,
    }


def parse_opencode(raw):
    """`--format json` is a JSONL event stream: text parts + step_finish."""
    texts, tokens, cost, cache, turns = [], {}, None, {}, 0
    for line in raw.splitlines():
        ev = decode_first_json(line)
        if not ev:
            continue
        part = ev.get("part") or {}
        typ = ev.get("type") or part.get("type") or ""
        if typ == "text":
            texts.append(part.get("text") or ev.get("text") or "")
        elif typ in ("step_finish", "step-finish"):
            turns += 1
            tokens = part.get("tokens") or tokens
            cache = tokens.get("cache") or {}
            cost = part.get("cost", cost)
    return {
        "result": "\n".join(t for t in texts if t).strip(),
        "num_turns": turns or None,
        "cost_usd": cost,
        "in_tok": tokens.get("input"),
        "out_tok": tokens.get("output"),
        "cache_create": cache.get("write"),
        "cache_read": cache.get("read"),
        "api_ms": None,
    }


PARSERS = {
    "claude": parse_claude,
    "cursor": parse_cursor,
    "codex": parse_codex,
    "opencode": parse_opencode,
}


def main():
    backend = os.environ["BACKEND"]
    run_dir = os.environ["RUN_DIR"]
    rc = int(os.environ["RC"])

    def read(name):
        try:
            with open(os.path.join(run_dir, name)) as f:
                return f.read()
        except OSError:
            return ""

    raw, err = read("raw.out"), read("stderr.log")
    fields = PARSERS[backend](raw)

    # Quota is error-driven only: pattern match AND the run yielded nothing.
    quota = bool(QUOTA_RE.search(err) or (rc != 0 and QUOTA_RE.search(raw)))
    quota = quota and (rc != 0 or not fields["result"])

    rec = {
        # Run completion time, UTC. quota-estimator.py buckets days on this;
        # without it every record collapses into one day.
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "q": os.environ.get("TIER", "adapter"),
        "run": os.environ.get("RUN_IDX", "1"),  # numeric-safe (pitfall #4)
        "backend": backend,
        "model": os.environ["MODEL"],
        "effort": os.environ.get("EFFORT"),
        "latency_ms": int(os.environ["LAT"]),
        "exit_code": rc,
        "quota_exhausted": quota,
        "cost_estimated": fields["out_tok"] is None,
        "run_dir": run_dir,
    }
    rec.update(fields)
    print(json.dumps(rec))
    if quota:
        sys.exit(75)
    if rc != 0 or not fields["result"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
