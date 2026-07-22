---
title: "loop-clean-first-pass fixture"
kind: spec
slug: loop-clean-first-pass
date: 2026-05-25
status: proposed
---

# Loop fixture — clean first pass

A realistic small spec that has no structural defects. Used by the
`--mode=full-loop` test suite to assert that a clean spec terminates the
loop immediately (no findings, no edit_spec, no max_iter).

## Background

We need a fixture whose content satisfies all four review-checklist
items — measurable success criteria, runnable test plan, clear task
contract, no scope creep — so the advisor mock (or the real advisor on
this fixture in a live run) has nothing legitimate to flag.

## Goals

- D1: emit a passing JSON envelope on `--mode=full-loop --iteration=1`
  when no `SD_ADVISORY_MOCK` is provided (default = empty findings array).

## Success criteria

- S1: `bash spec-advisory.sh --mode=full-loop --iteration=1 <this-file>`
  exits 0 with stdout JSON containing `"next_action":"done"` and
  `"terminated":"all_clean"`.

## Test plan

| ID | Command | Expected |
|---|---|---|
| T1 | `bash spec-advisory.sh --mode=full-loop --iteration=1 loop-clean-first-pass.md` | JSON with `next_action=done`, `terminated=all_clean`, exit 0 |

## Task split

Single fixture file — no implementation work, this is test input only.

## Constraints

- No mutation of the fixture by the test suite; the file is read-only input.
