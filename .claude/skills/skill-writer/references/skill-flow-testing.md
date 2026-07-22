# TEST · Skill Flow Execution (optional)

Run a modified skill's full flow on real hardware or locally to verify
end-to-end correctness. Complements verify-skill (LLM judgment) and resident
dogfood (live task) with target-environment execution.

**Optional** — all modes. SKIP when infra unavailable (not FAIL).

## 1. Detect modified skills

```bash
git diff --name-only origin/main...HEAD -- '*/SKILL.md'
```

No `*/SKILL.md` in diff → skip entirely.

## 2. Extract device types from frontmatter

```bash
grep "^test-devices:" <skill>/SKILL.md | sed 's/test-devices: *//' | tr -d '"'
```

Returns `local` or comma-separated device types (e.g., `UNAS, ENAS`).

## 3. Launch test agents

**Device-bound skills** (test-devices ≠ `local`) — one agent per skill × device type, parallel:

```
Launch 1 agent (per skill x device type, parallel):
  You are a skill flow execution test agent.

  Skill: <skill-name>
  SKILL.md: <path-to-SKILL.md>
  Device type: <device-type> (e.g., UNAS, ENAS, UNVR)

  Run this skill's full flow on a real device to verify it works end-to-end.

  Step 1 — Reserve a device:
  Use the ubiquiti-device-reserve skill to find and lock a <device-type> device.

  Step 2 — Run the skill flow:
  Read <path-to-SKILL.md> and execute the skill as if a user invoked it.
  Follow the instructions step by step on the reserved device.
  Run all pre/post checks documented in the skill.

  Step 3 — Report:
  PASS: all steps completed successfully, all checks passed
  FAIL: which step failed, error output, root cause if identifiable

  Step 4 — Cleanup:
  Unlock the device (lock-test.sh unlock) even if the test failed.

  IMPORTANT: This is a READ-ONLY validation test. Do NOT make destructive
  changes (nuke storage, flash firmware) unless the skill flow requires it
  AND the device is a dedicated test device. When in doubt, run only
  pre/post check commands and skip destructive operations.
```

**Local-only skills** (test-devices = `local`) — one agent per skill:

```
Launch 1 agent:
  You are a skill flow execution test agent.

  Skill: <skill-name>
  SKILL.md: <path-to-SKILL.md>

  Run this skill's flow locally as if a user invoked it.
  Verify the instructions are accurate and commands work.
  Report PASS/FAIL with evidence.
```

## 4. Skip conditions

- Changes to SKILL.md are formatting/typos only (no flow changes) → skip
- No devices of required type reachable → SKIP (not FAIL)
- User declines → skip (optional leg)

## 5. Result handling

Advisory — FAIL warns user, does not hard-block skill-writer. All results
reported alongside verify-skill and dogfood outcomes in the flow-complete
summary.
