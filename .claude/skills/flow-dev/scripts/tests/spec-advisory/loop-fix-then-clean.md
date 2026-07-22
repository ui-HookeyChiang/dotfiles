---
title: "loop-fix-then-clean fixture"
kind: spec
slug: loop-fix-then-clean
date: 2026-05-25
status: proposed
---

# Loop fixture — fix then clean

A realistic spec with one structural defect (deliberate omission) that
the advisor mock can flag as a HIGH finding. Used by the
`--mode=full-loop` test suite to assert that iteration=1 returns
`edit_spec` with structured findings.

In a live run, the main agent would apply the suggested rewrite, then
call iteration=2 which (with a cleaner mock) returns `done`. The test
file only needs to drive iteration=1 — the iteration=2 transition is
covered by a separate AC using a different mock.

## Background

The advisor is expected to surface the missing test-plan row in iteration
1. The intentional defect: success criterion S1 below has no matching
row in the §Test plan table (T1 covers a different criterion).

## Goals

- D1: when the test injects a HIGH-severity finding via
  `SD_ADVISORY_MOCK`, the loop returns `next_action=edit_spec`.

## Success criteria

- S1: iteration=1 with a HIGH-severity mock returns
  `next_action=edit_spec` and the findings array is non-empty.
- S2: the spec_hash field is a 12-char hex string (sha256 prefix of the
  on-disk content).

## Test plan

| ID | Command | Expected |
|---|---|---|
| T1 | `SD_ADVISORY_MOCK=<dirty.json> bash spec-advisory.sh --mode=full-loop --iteration=1 loop-fix-then-clean.md` | JSON with `next_action=edit_spec`, `findings_summary.H>=1` |

(Intentional gap: S1 is exercised by T1, but S2 lacks an explicit T-row.
This is the defect the advisor mock flags.)

## Task split

Single fixture — no implementation work.

## Constraints

- The intentional defect (missing T-row for S2) must remain in the file;
  removing it would invalidate the AC.
