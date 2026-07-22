"""Minimal YAML parser for advisory LLM dispatch responses.

Supports only the subset emitted by references/llm-audit-prompt.md:
  - top-level mapping with string keys
  - values: scalar (string, int), list of scalars in brackets, list of mappings
  - mappings inside list items use 2-space indentation
  - no anchors, no aliases, no multi-document, no flow-style mappings

Anything outside this subset raises YamlParseError. The intent is to be
strict and predictable rather than permissive.
"""
from __future__ import annotations

import re
from typing import Any


class YamlParseError(ValueError):
    pass


SCALAR_INT = re.compile(r"^-?\d+$")
BRACKET_LIST = re.compile(r"^\[(.*)\]$")
KV_LINE = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
LIST_ITEM = re.compile(r"^(\s*)-\s*(.*)$")


def _parse_scalar(raw: str, coerce_int: bool = True) -> Any:
    """Parse a raw scalar string into a Python value.

    coerce_int=False is passed by bracket-list items so bare integers in
    location strings (e.g. ``[62-64, 568]``) are kept as strings.
    """
    raw = raw.strip()
    if not raw:
        return None
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    if raw.startswith("'") and raw.endswith("'"):
        return raw[1:-1]
    m = BRACKET_LIST.match(raw)
    if m:
        inner = m.group(1).strip()
        if not inner:
            return []
        # bracket list items are location strings — never coerce to int
        return [_parse_scalar(item, coerce_int=False) for item in _split_bracket(inner)]
    if coerce_int and SCALAR_INT.match(raw):
        return int(raw)
    return raw


def _split_bracket(inner: str) -> list[str]:
    out, buf, in_str, str_ch = [], [], False, ""
    for ch in inner:
        if in_str:
            buf.append(ch)
            if ch == str_ch:
                in_str = False
        elif ch in ('"', "'"):
            in_str = True
            str_ch = ch
            buf.append(ch)
        elif ch == ",":
            out.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    if buf:
        out.append("".join(buf).strip())
    return out


def parse_yaml(text: str) -> dict:
    """Parse the YAML subset our LLM prompt emits."""
    if not text.strip():
        return {}
    pairs = [
        (orig_i + 1, ln.rstrip())
        for orig_i, ln in enumerate(text.splitlines())
        if ln.strip() and not ln.strip().startswith("#")
    ]
    source_linenos = [p[0] for p in pairs]
    lines = [p[1] for p in pairs]
    result: dict = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        m = KV_LINE.match(line)
        if not m:
            raise YamlParseError(f"line {source_linenos[i]}: expected key:value, got {line!r}")
        indent = len(m.group(1))
        if indent != 0:
            raise YamlParseError(f"line {source_linenos[i]}: top-level key must not be indented")
        key, rest = m.group(2), m.group(3)
        if rest == "" or rest is None:
            peek = lines[i + 1] if i + 1 < len(lines) else ""
            if LIST_ITEM.match(peek):
                block_lines, i_next = _take_block(lines, i + 1, base_indent=0)
                result[key] = _parse_list_of_mappings(block_lines, key)
                i = i_next
            else:
                result[key] = None
                i += 1
        else:
            result[key] = _parse_scalar(rest)
            i += 1
    return result


def _take_block(lines: list[str], start: int, base_indent: int) -> tuple[list[str], int]:
    block = []
    i = start
    while i < len(lines):
        m = KV_LINE.match(lines[i])
        if m and len(m.group(1)) == base_indent:
            break
        block.append(lines[i])
        i += 1
    return block, i


def _parse_list_of_mappings(block: list[str], parent_key: str) -> list[dict]:
    if not block:
        return []
    items: list[dict] = []
    current: dict | None = None
    for ln_idx, raw in enumerate(block):
        m_item = LIST_ITEM.match(raw)
        if m_item and len(m_item.group(1)) == 2:
            if current is not None:
                items.append(current)
            current = {}
            rest = m_item.group(2)
            if rest:
                sub = KV_LINE.match(rest)
                if not sub:
                    raise YamlParseError(
                        f"under {parent_key!r}: list item without key:value: {raw!r}"
                    )
                current[sub.group(2)] = _parse_scalar(sub.group(3))
            continue
        m_kv = KV_LINE.match(raw)
        if m_kv and len(m_kv.group(1)) == 4:
            if current is None:
                raise YamlParseError(
                    f"under {parent_key!r}: dangling key:value before any list item: {raw!r}"
                )
            current[m_kv.group(2)] = _parse_scalar(m_kv.group(3))
            continue
        raise YamlParseError(
            f"under {parent_key!r}: malformed line (bad indent or syntax): {raw!r}"
        )
    if current is not None:
        items.append(current)
    return items
