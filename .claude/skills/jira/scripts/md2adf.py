#!/usr/bin/env python3
"""md2adf.py — Markdown → Atlassian Document Format (ADF v3) converter.

Handles the markdown subset we actually use in Jira tickets:
- ## / ###   → heading (level 2/3)
- ```...```  → codeBlock
- |a|b|...   → table / tableHeader / tableRow / tableCell
- - item     → bulletList / listItem
- 1. item    → orderedList / listItem
- `code`     → inline code mark
- **bold**   → strong mark
- plain      → paragraph

Reads markdown from stdin, writes ADF JSON to stdout.
"""
import json
import re
import sys


# Inline marks: `code` and **bold**. We tokenize left-to-right rather than
# `re.split` on alternation so `**bold \`code\`**` keeps its inner backticks
# as a code mark inside the strong span (not as literal characters).
_TOKEN_RE = re.compile(r'\*\*(.+?)\*\*|`([^`]+)`')


def _emit(nodes, text, marks):
    if not text:
        return
    node = {'type': 'text', 'text': text}
    if marks:
        node['marks'] = list(marks)
    nodes.append(node)


def parse_inline(text, marks=()):
    """Return a list of ADF text nodes with marks for inline code/bold.

    Recursive: when we match `**...**`, we re-parse the inside with the
    `strong` mark stacked, so nested ``code`` inside bold lights up too.
    """
    if not text:
        return []
    nodes = []
    pos = 0
    for m in _TOKEN_RE.finditer(text):
        # Plain text before this match.
        _emit(nodes, text[pos:m.start()], marks)
        if m.group(1) is not None:
            # **bold** — recurse so nested `code` / future marks compose.
            nested = parse_inline(m.group(1), marks=tuple(marks) + ({'type': 'strong'},))
            nodes.extend(nested)
        else:
            # `code` — code mark does not nest, so emit directly.
            _emit(nodes, m.group(2), tuple(marks) + ({'type': 'code'},))
        pos = m.end()
    _emit(nodes, text[pos:], marks)
    return nodes


def make_paragraph(text):
    return {'type': 'paragraph', 'content': parse_inline(text)}


def make_heading(level, text):
    return {
        'type': 'heading',
        'attrs': {'level': level},
        'content': parse_inline(text),
    }


def make_code_block(lines, lang=None):
    block = {
        'type': 'codeBlock',
        'content': [{'type': 'text', 'text': '\n'.join(lines)}],
    }
    if lang:
        block['attrs'] = {'language': lang}
    return block


def make_list_item(text_or_blocks):
    if isinstance(text_or_blocks, str):
        return {
            'type': 'listItem',
            'content': [make_paragraph(text_or_blocks)],
        }
    return {'type': 'listItem', 'content': text_or_blocks}


def parse_table(rows):
    """rows is a list of '|a|b|c|' strings (raw lines); skip the alignment row.

    Returns a single ADF table node with header + body rows.
    """
    parsed = []
    for r in rows:
        cells = [c.strip() for c in r.strip().strip('|').split('|')]
        parsed.append(cells)

    # Drop alignment row (---|---|---).
    body = [r for r in parsed if not all(re.fullmatch(r':?-+:?', c or '') for c in r)]

    if not body:
        return None

    table_rows = []
    for i, cells in enumerate(body):
        cell_type = 'tableHeader' if i == 0 else 'tableCell'
        row = {
            'type': 'tableRow',
            'content': [
                {'type': cell_type, 'content': [make_paragraph(c)]}
                for c in cells
            ],
        }
        table_rows.append(row)

    return {'type': 'table', 'content': table_rows}


def parse_markdown(md):
    """Parse markdown text into a list of top-level ADF block nodes."""
    lines = md.splitlines()
    nodes = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        stripped = line.strip()

        # Empty line — skip (paragraph separators).
        if not stripped:
            i += 1
            continue

        # Code block.
        if stripped.startswith('```'):
            lang = stripped[3:].strip() or None
            fence_start_line = i + 1  # 1-indexed for human-readable warnings
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith('```'):
                buf.append(lines[i])
                i += 1
            if i >= n:
                # Walked off the end without seeing a closing fence — emit
                # what we have but warn loudly so the dev can fix the source.
                print(
                    f'md2adf: WARNING: unclosed code fence opened at line '
                    f'{fence_start_line}; absorbed {len(buf)} lines to EOF',
                    file=sys.stderr,
                )
            else:
                i += 1  # consume closing ```
            nodes.append(make_code_block(buf, lang))
            continue

        # Heading.
        m = re.match(r'^(#{1,6})\s+(.*)$', stripped)
        if m:
            level = len(m.group(1))
            nodes.append(make_heading(min(level, 6), m.group(2)))
            i += 1
            continue

        # Table — line starts with `|` and next line is alignment.
        if stripped.startswith('|') and i + 1 < n and re.match(
            r'^\s*\|[\s:|-]+\|\s*$', lines[i + 1]
        ):
            tbl_rows = []
            while i < n and lines[i].strip().startswith('|'):
                tbl_rows.append(lines[i])
                i += 1
            tbl = parse_table(tbl_rows)
            if tbl:
                nodes.append(tbl)
            continue

        # Table-shaped without alignment row — most likely a hand-typed
        # table missing `|---|---|`. Fall through to paragraph but warn:
        # silently rendering as raw text was the original UOF-4536 failure.
        if stripped.startswith('|') and stripped.endswith('|') and stripped.count('|') >= 2:
            next_stripped = lines[i + 1].strip() if i + 1 < n else ''
            if not re.match(r'^\|[\s:|-]+\|$', next_stripped):
                print(
                    f'md2adf: WARNING: line {i + 1} looks like a table row '
                    f'but is missing the |---|---| alignment row on the next '
                    f'line; rendering as raw paragraph',
                    file=sys.stderr,
                )

        # Unordered list — `-` or `*` at any indent.
        list_match = re.match(r'^(\s*)([-*])\s+(.*)$', line)
        if list_match:
            list_items = []
            while i < n:
                m2 = re.match(r'^(\s*)([-*])\s+(.*)$', lines[i])
                if not m2:
                    break
                indent = len(m2.group(1))
                if indent > 0 and list_items:
                    # Nested item: append to previous listItem's content.
                    nested_text = m2.group(3)
                    prev_item = list_items[-1]
                    # Find or create a nested bulletList.
                    nested_list = None
                    for c in prev_item['content']:
                        if c.get('type') == 'bulletList':
                            nested_list = c
                            break
                    if nested_list is None:
                        nested_list = {'type': 'bulletList', 'content': []}
                        prev_item['content'].append(nested_list)
                    nested_list['content'].append(make_list_item(nested_text))
                else:
                    list_items.append(make_list_item(m2.group(3)))
                i += 1
            nodes.append({'type': 'bulletList', 'content': list_items})
            continue

        # Ordered list — `1.`, `2.`, etc.
        ord_match = re.match(r'^(\s*)\d+\.\s+(.*)$', line)
        if ord_match:
            list_items = []
            while i < n:
                m2 = re.match(r'^(\s*)\d+\.\s+(.*)$', lines[i])
                if not m2:
                    break
                list_items.append(make_list_item(m2.group(2)))
                i += 1
            nodes.append({'type': 'orderedList', 'content': list_items})
            continue

        # Paragraph — collapse consecutive non-empty, non-special lines.
        buf = [stripped]
        i += 1
        while i < n:
            nxt = lines[i].strip()
            if not nxt:
                break
            if nxt.startswith(('#', '```', '|', '-', '*')) or re.match(r'^\d+\.\s', nxt):
                break
            buf.append(nxt)
            i += 1
        nodes.append(make_paragraph(' '.join(buf)))

    return nodes


def main():
    md = sys.stdin.read()
    doc = {'type': 'doc', 'version': 1, 'content': parse_markdown(md)}
    json.dump(doc, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
