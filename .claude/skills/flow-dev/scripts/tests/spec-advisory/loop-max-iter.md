---
title: "loop-max-iter fixture"
kind: spec
slug: loop-max-iter
date: 2026-05-25
status: proposed
---

# Loop fixture — max iterations reached

A realistic spec used by the `--mode=full-loop` test suite to assert
that when the caller invokes the script with `--iteration=N` equal to
the max cap AND the advisor still surfaces HIGH/MED findings, the
envelope reports `next_action=max_iter` and `terminated=max_iterations`.

In a live run this would model a pathological spec where each fix
introduces a new defect (livelock). The script does not detect cycles
itself — the caller (main agent) compares `spec_hash` across iterations
and may terminate early with its own `cycle_detected` flag. This
fixture only tests the cap-reached branch.

## Background

The fixture's content is irrelevant to the test logic — the script does
not read findings from the file. Findings come from `SD_ADVISORY_MOCK`,
which the test sets to a non-empty HIGH+MED array. What matters is that
the file exists and is readable so `wc -w` and `sha256sum` succeed.

## Goals

- D1: when `--iteration=N >= max_iter` AND findings include HIGH or MED,
  the envelope returns `next_action=max_iter` and
  `terminated=max_iterations`.

## Success criteria

- S1: iteration=5 with HIGH mock → `next_action=max_iter`,
  `terminated=max_iterations`.
- S2: `SD_ADVISORY_MAX_ITER=2` + iteration=2 + HIGH mock → same.

## Test plan

| ID | Command | Expected |
|---|---|---|
| T1 | `SD_ADVISORY_MOCK=<dirty> bash spec-advisory.sh --mode=full-loop --iteration=5 loop-max-iter.md` | `next_action=max_iter`, `terminated=max_iterations` |
| T2 | `SD_ADVISORY_MAX_ITER=2 SD_ADVISORY_MOCK=<dirty> bash spec-advisory.sh --mode=full-loop --iteration=2 loop-max-iter.md` | same |

## Task split

Single fixture — no implementation work.

## Constraints

- Fixture content is opaque to the test (findings come from mock); no
  intentional structural defects are needed in the markdown body.
