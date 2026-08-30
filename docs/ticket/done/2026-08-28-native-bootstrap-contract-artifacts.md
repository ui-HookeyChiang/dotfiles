# Native bootstrap contract artifacts

Status: done
Labels: flow:task
Spec: ../../specs/active/2026-08-27-native-windows-setup-check.md
Stack: 1/3
Blocked by: none

## Description

Create the static safe-v1 manifest, report schema, and pure contract module.
This layer defines data and policy only. It must not resolve tools, inspect a
real checkout, spawn a process, read credentials, access the network, or mutate
the host.

## Scope

Create only:

- `windows/native-bootstrap.manifest.psd1`
- `windows/native-bootstrap-report.schema.json`
- `windows/NativeBootstrap.Contract.psm1`
- `tests/windows/Test-NativeBootstrap.Contract.ps1`
- `tests/windows/fixtures/native-bootstrap-report/valid/*.json`
- `tests/windows/fixtures/native-bootstrap-report/invalid/*.json`

The manifest must be static PowerShell data. Importing the module or manifest
must have no observable side effect.

## Acceptance

- The manifest contains the five ordered project identities, complete tool
  descriptors, action IDs, executor profiles, policy fields, prerequisite
  edges, recovery objects, and required deferred shell/service records.
- Validation rejects missing or unknown fields, duplicate IDs or destinations,
  unsafe executor descriptors, contradictory policies, and incomplete
  recovery. Invalid contract data maps to exit 30 without invoking a child.
- Pure functions implement URL normalization, state-transition validation,
  result precedence, exit selection, canonical ordering, environment-profile
  hashing, redaction policy, and full/error/fatal serialization.
- PowerShell 7.4+ `Test-Json -SchemaFile` is the single JSON Schema validator
  contract. It uses PowerShell's JsonSchema.NET-backed implementation; no
  Python, jq, npm, or second schema validator may define acceptance.
- The contract test sends every canonical full, invocation-error, and fatal
  fixture through `Test-Json -SchemaFile` and requires true. It sends every
  malformed, mistyped, extra-field, and invalid fallback/recovery fixture
  through the same command and requires false or the documented validation
  exception.
- Exit 0 remains unreachable while any required action is deferred.
- Future clone and checkout authority stays descriptor-bound and unavailable
  in v1. There is no force, approve-all, inherited-environment, credential, or
  mutation activation surface.

## Spec traceability

| Spec tests | Success criteria |
| --- | --- |
| T02, T06, T12, T15, T17, T19, T25, T26, T27, T28 | SC04, SC07, SC09, SC10, SC12, SC16, SC17 |

This ticket owns the contract-level portions of those tests. Real process,
filesystem, and host behavior remains in tickets 2 and 3.

## Test seam

Use dependency-free PowerShell 7.4+ fixtures. Inject manifest values directly
into pure exported functions. Call native `Test-Json -SchemaFile` directly for
all schema assertions. Tests must work without administrator rights, network,
WSL, GitHub login, project checkouts, services, or credential/profile access.

## Commands

```powershell
pwsh -NoProfile -File tests/windows/Test-NativeBootstrap.Contract.ps1
```

The command must first assert PowerShell 7.4+, then exit 0 only when all valid
and invalid fixtures receive the expected result from `Test-Json -SchemaFile`.

## Dirty-worktree overlap

All scoped paths are new. Do not edit the pre-existing dirty `README.md`,
`install.sh`, or `windows/bootstrap.ps1`. Do not import their working-tree
content into this task.

## Safety boundary

This task cannot install, clone, authenticate, change configuration, create a
checkout root, execute checkout content, or activate a deferred action.
