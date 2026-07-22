---
title: "loop-cycle-stuck fixture"
kind: spec
slug: loop-cycle-stuck
date: 2026-05-27
status: proposed
---

# Loop fixture — stuck in cycle

A minimal spec used only by the L2 goal-loop status-line-emit test
(`flow-dev/scripts/tests/goal-loop/status-line-emit.sh`) to drive
the `cycle` test case from
`docs/spec/archive/2026-05-27-spec-advisor-goal-wrapper.md` §Required
test cases.

The cycle case requires the same `spec_hash` to be observed across
two consecutive iterations while the advisor still reports
`next_action=edit_spec` — i.e. livelock, the main agent applied a
suggestion that didn't change the spec content (or didn't apply any
suggestion at all). The existing
`flow-dev/scripts/tests/spec-advisory/loop-*.md` fixtures all sit
on live `sha256sum` of their own content, so feeding the same fixture
into back-to-back invocations naturally produces a repeating hash;
this file just gives the cycle case its own self-documenting fixture.

## Goals

- D1: provide a readable spec file whose `sha256sum`-prefix can serve
  as a stable `spec_hash` across two test iterations without any
  mutation between calls.

## Success criteria

- S1: `bash spec-advisory.sh --mode=full-loop --iteration=1 loop-cycle-stuck.md`
  followed by the same call with `--iteration=2` emits envelopes whose
  `spec_hash` field is byte-identical (because the file content did not
  change between calls).

## Test plan

| ID | Command | Expected |
|---|---|---|
| T1 | run the L2 test `status-line-emit.sh`, observing the `cycle` case | last `loop status:` line ends with `next_action=max_iter, findings=H:1 M:1 L:1, cycle=detected` |

## Task split

Single fixture — no implementation work, this is test input only.

## Constraints

- The fixture body MUST NOT be modified by the test driver (the cycle
  case depends on the file content being stable across two calls).
- Word count is irrelevant; the script routes every spec to `deep`
  under the always-three rule, and the loop body uses `SD_ADVISORY_MOCK`
  for findings (not the file body).
