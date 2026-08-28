---
title: Native Windows project setup and readiness contract
kind: spec
date: 2026-08-27
status: active
related_concepts:
  - Native project runtime
  - Native bootstrap
  - Checkout root
  - Credential owner
  - Execution provenance
sources:
  - ../../../.scratch/windows-wsl-first-project-runtime/PRD.md
  - ../../../.scratch/windows-wsl-first-project-runtime/issues/07-task-native-setup-check-contract.md
  - ../../../.scratch/windows-wsl-first-project-runtime/native-only-runtime-research.md
implementation_tickets:
  - ../../ticket/2026-08-28-native-bootstrap-contract-artifacts.md
  - ../../ticket/2026-08-28-native-bootstrap-zero-mutation-core.md
  - ../../ticket/2026-08-28-native-bootstrap-real-sentinel-gate.md
execution_gates:
  - ../../ticket/2026-08-28-native-bootstrap-baseline-reconciliation.md
---

# Native Windows project setup and readiness contract

## Problem

`windows/bootstrap.ps1` is a mutating installer. It installs tools, starts
GitHub authentication, clones repositories, edits global Git and PowerShell
configuration, installs dependencies, and seeds an environment file. It has no
read-only readiness command, trust boundary for checkout code, stable
per-project result, remote identity check, or failure taxonomy.

Native Windows is the authoritative local runtime. Safe-v1 needs zero-mutation
`Setup` planning and `Check` inspection operations that truthfully report
the five-project set without WSL. Root creation, clone, host integration,
dependency setup, shell/test execution, and service activation belong to
successor activation specs and tickets.

## Scope

This spec defines:

- the PowerShell host, command interface, native-executor predicate, and output;
- the normative project/action manifest and checkout containment rules;
- setup, check, dirty-checkout, credential, offline, and no-WSL behavior;
- deferred-action planning, successor mutation schema compatibility, errors,
  recovery metadata, and exit selection;
- the test seam, test plan, and success-to-test traceability.

Issue 08 defines required shell and test actions. Issue 09 defines required
Task Scheduler and Docker Desktop readiness. Issue 11 owns model-evaluation
artifacts. This spec provides the bootstrap result seam those issues extend.

## Non-goals

- Installing, launching, probing, or recommending WSL.
- Updating existing repositories with fetch, pull, checkout, reset, rebase, or
  submodule update.
- Starting, stopping, replacing, or deleting long-running services.
- Reading, copying, migrating, printing, or brokering credential contents.
- Treating Git Bash output as Linux evidence.
- Rewriting project installers, business logic, or model-evaluation schemas.
- Providing a general repository updater or uninstall manager.

## PowerShell host and native-executor predicate

The supported host is 64-bit PowerShell Core `pwsh.exe` 7.4 or newer on
Windows 10/11 or Windows Server 2022 or newer. Windows PowerShell 5.1 is
unsupported. Before loading the manifest, the bootstrap requires all of:

- `$PSVersionTable.PSEdition -eq 'Core'` and version at least 7.4;
- `[Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(Windows)`;
- a 64-bit process whose executable resolves to a local `pwsh.exe`;
- no `WSL_DISTRO_NAME`, `WSL_INTEROP`, or Linux `/proc/version` marker;
- a local, non-UNC, non-device, non-network, non-reparse script/root path.

Only then may a report claim `execution_provenance: windows-native`. A child
executor is native when its resolved executable is a local Windows PE binary,
or the approved Git-for-Windows `bash.exe` assigned by issue 08. An executable
under `\\wsl$\share`, `\\?\C:\path`, `\\.\PhysicalDrive0`, a
network drive, a reparse-rooted
path, or a wrapper that resolves to `wsl.exe` fails
`NPR-HOST-NONNATIVE-EXECUTOR`. Provenance is never inferred from a filename
alone.

The entry point sets console input, console output, `$OutputEncoding`, and
child-process text decoding to UTF-8 without BOM. JSON stdout is UTF-8 without
BOM and contains no ANSI sequences. File writes performed by Setup specify
`utf8NoBOM` and the owning file's existing newline convention; Check writes
no file.

## Interface

The command is mandatory so automation cannot mutate a host by omission:

```powershell
& .\windows\bootstrap.ps1 -Command Setup [-ProjectsDir D:\projects] [-NonInteractive] [-Offline] [-WhatIf] [-OutputFormat Text|Json] [-Diagnostics]
& .\windows\bootstrap.ps1 -Command Check [-ProjectsDir D:\projects] [-Offline] [-OutputFormat Text|Json] [-Diagnostics]
```

Normative parameters:

| Parameter | Contract |
| --- | --- |
| `-Command Setup|Check` | Required operation. |
| `-ProjectsDir` | Absolute local Windows checkout root; default `D:\projects`. |
| `-NonInteractive` | Forbids prompts. No credential behavior changes. |
| `-Offline` | Forbids all network actions. Check is offline even without this switch. |
| `-WhatIf` | Setup-only; emits plans but performs no mutation. |
| `-OutputFormat Text|Json` | Default Text; JSON is the automation contract. |
| `-Diagnostics` | Enables bounded, sanitized diagnostics on stderr. It never changes stdout or child authorization. |

`Setup` and `Check` are both zero-mutation in safe-v1. `Check` rejects
planning-only switches. Neither command installs,
clone, fetch, edit profiles or Git config, authenticate, start services, create
directories, seed files, or install dependencies.

Existing skip and `-ApplyClaudePermissions` switches are outside the stable
contract. Temporary compatibility aliases are Setup-only and must report any
skipped required work as `action_required`, never `ready`.

## Trust and containment boundary

A checkout is untrusted input even when its origin matches. Version 1 may
inspect repository metadata but may not:

- execute a script, package hook, task, binary, or configuration from it;
- invoke npm, uv, Git Bash, or another tool with that checkout as input or cwd;
- copy checkout content into a user profile or executable path;
- load PowerShell data/code, Git includes, package manifests, or hooks from it;
- mutate the checkout or host based on checkout content.

Fresh clones and existing checkouts use the same rule. Version 1 exposes no
checkout-execution approval or force switch. Checkout-owned installers,
package managers, scripts, submodule operations, global Git includes, profile
copies, and generated-file steps are deferred and non-executable.

Any future approval must bind to an immutable execution descriptor containing
the handle-resolved repository/top-level path, normalized remote, HEAD object
ID, HEAD tree ID, every declared input-file SHA-256, executor absolute path and
SHA-256, cwd, argv-array SHA-256, environment-profile ID and SHA-256, and
manifest/action schema versions. The bootstrap must recompute and compare the
descriptor immediately before process creation. Mismatch invalidates approval.
Approval remains one-action and one-invocation, cannot imply credential
authorization, and has no approve-all form.

The checkout root must resolve to a fixed local drive directory below, but not
equal to, a filesystem root or user-profile root. Version 1 rejects:

- UNC, device, extended-device, and network-mapped paths;
- drive letters backed by `SUBST` or a DOS-device mapping;
- a root or destination with any existing reparse point/junction in its
  ancestor chain from the volume root;
- destinations that escape the canonical root after normalization;
- alternate data streams, trailing-dot/space aliases, reserved device names,
  and case-folded duplicate destinations.

Containment uses handle-resolved canonical paths, not string prefix tests.
Drive type comes from the native volume API; `Get-PSDrive.DisplayRoot` detects
mapped drives and `QueryDosDevice` detects `SUBST`/DOS-device aliases.
Missing descendants are validated component by component before creation. A
path-policy failure exits 2 without mutation.

## Normative manifest and action schema

The checked-in manifest is static PowerShell data; it never loads executable
content. It has `schema_version: 1` and exactly five project records in this
order:

| Name / canonical identity | Clone URL / action ID | Required tool IDs | Required deferred record |
| --- | --- | --- | --- |
| `dotfiles` / `github.com/ui-HookeyChiang/dotfiles` | `https://github.com/ui-HookeyChiang/dotfiles.git` / `repo.dotfiles.clone.deferred` | `pwsh,scoop,git,fzf,fd,jq,yq` | `dotfiles.host-integration.deferred` |
| `skill-dev` / `github.com/ui-HookeyChiang/skill-dev` | `https://github.com/ui-HookeyChiang/skill-dev.git` / `repo.skill-dev.clone.deferred` | `pwsh,scoop,git,ast-grep,jq,yq` | `skill-dev.dependencies.deferred` |
| `Awesome-CV` / `github.com/ui-HookeyChiang/Awesome-CV` | `https://github.com/ui-HookeyChiang/Awesome-CV.git` / `repo.awesome-cv.clone.deferred` | `pwsh,scoop,git,node,npm,pdfinfo,xelatex` | `awesome-cv.dependencies.deferred` |
| `telegram-claude-bridge` / `github.com/ui-HookeyChiang/telegram-claude-bridge` | `https://github.com/ui-HookeyChiang/telegram-claude-bridge.git` / `repo.telegram-bridge.clone.deferred` | `pwsh,scoop,git,node,npm` | `telegram-bridge.dependencies.deferred` |
| `stock-target-finder` / `github.com/ui-HookeyChiang/stock-target-finder` | `https://github.com/ui-HookeyChiang/stock-target-finder.git` / `repo.stock-finder.clone.deferred` | `pwsh,scoop,git,python,uv` | `stock-finder.dependencies.deferred` |

Each project record requires:

```text
name, destination_segment, canonical_identity, clone_url,
required_tools[], readiness_probes[], actions[]
```

Each action requires:

```text
id, phase, kind, executor_id, argv_template[], working_directory,
checkout_effect, credential_policy, network_policy, dirty_policy,
required, v1_state, prerequisites[], success_probe, recovery
```

Rules:

- `id` is globally unique and stable. `argv_template` is an argument array,
  never a shell command string.
- `checkout_effect` is `inspect|execute|install|copy|configure`. In version
  1 every value except `inspect` has `v1_state: deferred` and cannot start.
- `credential_policy` is `deny|required|optional`; required/optional use
  still needs exact action authorization.
- `network_policy` is `deny|required|optional`; Offline blocks required
  network actions as `action_required`.
- `dirty_policy` is `inspect|require-clean`. Every mutating action uses
  `require-clean`.
- `recovery` contains `kind: exact|manual|deferred`, instructions, affected
  paths/settings, and verification. A required action with deferred recovery
  cannot execute in version 1 and yields `action_required`.
- Manifest validation runs before mutation. Missing/unknown fields, duplicate
  IDs/destinations, unsafe executors, or contradictory policies exit 30.

PowerShell 7.4+, Scoop, and all tools are external prerequisites. Setup and
Check only resolve and version-probe them. Neither command bootstraps Scoop,
installs/upgrades tools, changes execution policy or PATH, installs rtk, adds
`safe.directory`, runs `gh auth setup-git`, or includes checkout-owned Git
configuration.

The complete version 1 tool descriptors are:

| ID | Executable / minimum | Required by | Secret-free remediation |
| --- | --- | --- | --- |
| `pwsh` | host `pwsh.exe` / 7.4 | bootstrap | Install PowerShell 7.4+ separately, then reopen the terminal. |
| `scoop` | `scoop.cmd` / supported current | host policy | Install Scoop from reviewed official instructions; do not pipe remote text into this bootstrap. |
| `git` | `git.exe` / 2.45 | all repositories | `scoop install git` |
| `gh` | `gh.exe` / 2.50 | clone auth status | `scoop install gh`; run `gh auth login` separately. |
| `node`, `npm` | `node.exe` 20, `npm.cmd` 10 | Awesome-CV, bridge | `scoop install nodejs-lts` |
| `python`, `uv` | `python.exe` 3.12, `uv.exe` 0.8 | stock finder | `scoop install python uv` |
| `jq`, `yq` | `jq.exe` 1.7, `yq.exe` 4.44 | shared tooling | `scoop install jq yq` |
| `fzf`, `fd` | `fzf.exe` 0.53, `fd.exe` 10 | dotfiles | `scoop install fzf fd` |
| `ast-grep` | `ast-grep.exe` 0.27 | skill-dev | `scoop install ast-grep` |
| `pdfinfo`, `xelatex` | Poppler 24, MiKTeX 24 | Awesome-CV | `scoop install poppler miktex`; finish MiKTeX setup separately. |

Each descriptor fixes executable basename, trusted local resolver roots,
version argv/parser/constraint, required projects, environment profile, timeout,
network prohibition, and remediation string. A missing descriptor is a
manifest invariant failure. `rtk` is explicitly deferred and non-gating
until a separate package/probe contract exists.

The complete version 1 action inventory is:

| Action ID | Owner | Effect | Recovery requirement |
| --- | --- | --- | --- |
| `checkout-root.create.deferred` | dotfiles native bootstrap | Future checkout-root creation | Deferred/non-executable |
| The five exact `repo.*.clone.deferred` IDs above | dotfiles native bootstrap | Future HTTPS clone | Deferred/non-executable |
| `dotfiles.host-integration.deferred` | dotfiles | Git include, agent CLI/profile, PATH | Deferred/non-executable |
| `skill-dev.dependencies.deferred` | skill-dev | Checkout installer | Deferred/non-executable |
| `awesome-cv.dependencies.deferred` | Awesome-CV | Checkout installer/package manager | Deferred/non-executable |
| `telegram-bridge.dependencies.deferred` | telegram-claude-bridge | Checkout `npm ci` | Deferred/non-executable |
| `stock-finder.dependencies.deferred` | stock-target-finder | Checkout `uv sync` | Deferred/non-executable |
| `shell-tests.deferred` | issue 08 | Required shell/test work | Deferred/non-executable |
| `services.deferred` | issue 09 | Required service/readiness work | Deferred/non-executable |

Until issues 08 and 09 supply their required manifest records and probes, both
Setup and Check emit `action_required` with exit 10. Deferred required work
never appears as `ready` or successful `skipped`.

## Checkout identity and sanitized Git inspection

For destination `<ProjectsDir>\<name>`:

1. Missing path: both commands report `NPR-REPO-MISSING` and the deferred
   HTTPS clone record; neither creates or clones.
2. Existing non-Git path: both report `NPR-REPO-NONGIT-COLLISION`.
3. Existing Git path: its handle-resolved top level must equal the destination.
4. `remote.origin.url` must normalize to the canonical identity.

Normalization accepts scp SSH, `ssh://`, and `https://` GitHub URLs. It
removes one trailing `.git` and compares host, owner, and repository
case-insensitively. It rejects URL credentials, non-GitHub hosts, extra path
components, query strings, fragments, and local/file URLs. Equivalent URLs
match identity but are never rewritten.

All inspection uses an argument-array invocation of the trusted native
`git.exe` with:

- `--no-optional-locks`;
- `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=NUL`,
  `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`, and
  `GCM_INTERACTIVE=Never`;
- `GIT_ASKPASS`, `SSH_ASKPASS`, `GIT_SSH`, `GIT_SSH_COMMAND`, and
  credential environment variables removed;
- overrides `core.fsmonitor=false`, `core.hooksPath=NUL`,
  `credential.helper=`, and `protocol.ext.allow=never`;
- only `rev-parse --show-toplevel`, `config --local --get remote.origin.url`,
  and `status --porcelain=v1 -z --untracked-files=all`.

Inspection never uses an alias, transport, fetch, submodule, hook, filter,
pager, editor, or shell. Dubious ownership is `action_required`; Check never
adds `safe.directory` or bypasses the ownership guard. Clone omits
`--recurse-submodules`. Fresh and existing checkouts never run a submodule
operation.

## Dirty checkout safety

The NUL-delimited porcelain result is parsed as data; filenames are never
executed or copied into commands. Check reports dirty state as a warning when
all required probes otherwise pass.

Setup blocks every checkout-derived or repository-local mutating action when
porcelain is non-empty. It reports `NPR-REPO-DIRTY-BLOCKED`, continues with
independent projects, and exits 10. Version 1 has no force or allow-dirty path.

For a clean checkout, Setup snapshots porcelain before and after an approved
action. New tracked or untracked state reports
`NPR-REPO-INSTALL-DIRTIED` and exit 20. The report carries sanitized relative
paths, capped at 100 entries with a truncated count; control characters are
escaped. The bootstrap never restores, deletes, stashes, or resets changes.

## Credentials and child-process environment

Native tools own local credentials. Bootstrap may invoke a vendor status
command with output suppressed, but it never reads profile files or includes
status output in a report. It never initiates login. Missing authentication is
`NPR-AUTH-ACTION-REQUIRED` and exit 10.

Every child starts from a constructed environment, not inherited
`$env:`. The default allowlist contains only non-secret OS execution values
needed by the approved executor. It excludes `HOME`, `USERPROFILE`,
`APPDATA`, `LOCALAPPDATA`, SSH agents/askpass, GitHub/vendor tokens, cloud
variables, and all variables whose names match credential/secret/token/key
patterns.

Version 1 exposes no credential authorization because it performs no clone.
Future clone authorization must be exact and invocation-scoped, permit only
the reviewed Git Credential Manager profile, and never accept or report a
secret value.

The bootstrap does not copy `.env`, auth profiles, token files, or CLI
settings. It never reads existing `.env` contents. Existing secret-bearing or
potentially secret-bearing files are never overwritten. Version 1 has no
backup, merge, or restore scheme; configuration seeding is deferred.

### Executor environment profiles

| Profile | Allowed inputs | Constraints |
| --- | --- | --- |
| `tool-probe-v1` | `SystemRoot`, `ComSpec`, `TEMP`, `TMP`, fixed UTF-8 values | Absolute executable/argv; no profile, credential, network, pager, or shell variables |
| `git-inspect-v1` | tool-probe values plus fixed Git denial/override values | Local read-only subcommands only |
| `git-clone-anonymous-future` | tool-probe values plus noninteractive Git denial values | Deferred activation precondition; HTTPS only |
| `git-clone-gcm-future` | anonymous profile plus reviewed Git Credential Manager inputs | Deferred activation precondition; explicit authorization and full output suppression |

Each profile has a schema version and canonical SHA-256. Children use absolute
executables, argv arrays, and constructed environments. Version 1 has no
generic inherited, shell, npm, uv, or checkout executor profile.

Native `.cmd` wrappers are allowed only for fixed, read-only version probes
whose tool descriptor pins the wrapper's local non-reparse path, SHA-256,
reviewed contents, absolute `cmd.exe`, fixed argv, environment profile, and
expected parser. No operator-controlled argument reaches `cmd.exe`. A digest
or template mismatch is action-required; the wrapper is not run.

Future HTTPS clone activation must separately prove TOCTOU containment:
revalidate destination nonexistence, root handles, git/GCM executable digests,
system/global configuration denial, explicit absolute GCM helper selection,
environment profile, transport URL, and immutable execution descriptor
immediately before spawn. It must also prove that no remote, protocol helper,
askpass, hook, template, or system configuration outside that descriptor can
execute. These are future activation gates, not version 1 behavior.

## Offline and prerequisite rules

Check is offline by contract. Setup `-Offline` evaluates local state and
blocks network-required actions without attempting DNS, HTTP, Git transport, or
package-manager refresh.

Prerequisites have deterministic classes:

| Condition | Result |
| --- | --- |
| Required tool missing | `action_required`, exit 10 |
| Required tool version unsupported | `action_required`, exit 10 |
| Trusted tool resolves outside the native-executor/path policy | `action_required`, exit 10 |
| Tool probe starts but fails or returns malformed data | `failed`, exit 20 |
| Required auth absent | `action_required`, exit 10 |
| Required network action while Offline | `action_required`, exit 10 |
| Network action attempted and fails | `failed`, exit 20 |
| Optional prerequisite absent | `warning` or `skipped`, as fixed by manifest |
| Required shell/service definition deferred | `action_required`, exit 10 |

Probe versions use machine-readable flags where available, fixed timeouts, no
network, sanitized environments, and bounded output.

## Action plan and mutation state machine

Setup validates the complete manifest and emits a plan before mutation.
`Setup -WhatIf` stops there. Check emits no mutation plan.

Each plan has `action_id`, target, prerequisites, approval/credential/network
decisions, and one state:

`planned -> blocked | authorized -> started -> applied | failed | partial | unknown`

- `blocked`: policy or prerequisite prevents start; result is
  `action_required`.
- `applied`: the success probe proves the intended state.
- `failed`: the action started, no intended mutation is observed, and failure
  is known.
- `partial`: some intended mutation is observed but the success probe fails.
- `unknown`: timeout, termination, or unreadable state prevents determining
  what changed.

A mutation record is created before starting a mutating child. It contains the
plan ID, state, affected targets, recovery object, child exit/timeout facts, and
success-probe result. `partial` and `unknown` always exit at least 20 and
require manual inspection. No automatic rollback runs.

Independent action failures do not block unrelated projects. An invariant,
containment, or serialization failure stops new mutations, marks any in-flight
record `unknown`, and still attempts a minimal deterministic report.

## Deterministic result, exit, and serialization

Per-result status precedence is:

`failed > action_required > warning > ready > skipped`

Overall status is the highest-precedence required result. An absent optional
prerequisite is `warning` or `skipped` exactly as its descriptor states; an
optional probe that starts and fails is `warning` unless it exposes an
invariant or safety failure. Optional results never mask required results.
Required skipped results normalize to `action_required`.

Exit selection is deterministic:

| Exit | Condition |
| --- | --- |
| 0 | Reserved for a successor schema after every required deferred record is replaced; unreachable in safe v1. |
| 2 | Invocation or path-policy error before action planning. |
| 10 | At least one required action/result is blocked or action-required, with no higher condition. |
| 20 | Any operation failed, partial, or unknown, with no internal invariant failure. |
| 30 | Manifest, containment-after-start, report, or internal invariant failure. |

JSON has fixed field order:
`schema_version, report_kind, command, execution_provenance, projects_dir,
offline, overall, exit_code, authorizations, plans, results, mutations,
diagnostics, errors, fallback`. The full report also carries
`check_contract_ready`: true means inspection/reporting completed, not that
the project set is ready. While any required deferred record exists, overall
is `action_required`, exit is 10, and `check_contract_ready` may still be
true.
Projects follow manifest order; actions follow manifest order; host results
precede project results; same-scope results sort by stable code. Sets are sorted
ordinally. No timestamp, locale-formatted value, random ID, absolute temporary
path, or hash-table enumeration enters canonical output.

`OutputFormat Json` writes exactly one JSON object to stdout. Text mode writes
the human summary to stdout. Child output and diagnostics never reach stdout.

### Version 1 JSON Schema

This complete Draft 2020-12 schema governs full and fatal fallback reports:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ui-hookeychiang.invalid/dotfiles/native-bootstrap-report-v1.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "report_kind", "command", "execution_provenance", "check_contract_ready", "overall", "exit_code", "errors"],
  "properties": {
    "schema_version": {"const": 1},
    "report_kind": {"enum": ["full", "fatal"]},
    "command": {"enum": ["setup", "check", "unknown"]},
    "execution_provenance": {"enum": ["windows-native", "unverified"]},
    "check_contract_ready": {"type": "boolean"},
    "projects_dir": {"type": ["string", "null"]},
    "offline": {"type": ["boolean", "null"]},
    "overall": {"enum": ["ready", "warning", "action_required", "failed"]},
    "exit_code": {"enum": [0, 2, 10, 20, 30]},
    "authorizations": {"type": "array", "maxItems": 0},
    "plans": {"type": "array", "items": {"$ref": "#/$defs/plan"}},
    "results": {"type": "array", "items": {"$ref": "#/$defs/result"}},
    "mutations": {"type": "array", "items": {"$ref": "#/$defs/mutation"}},
    "diagnostics": {"type": "array", "items": {"$ref": "#/$defs/diagnostic"}},
    "errors": {"type": "array", "items": {"$ref": "#/$defs/error"}},
    "fallback": {"oneOf": [{"type": "null"}, {"$ref": "#/$defs/fallback"}]}
  },
  "$defs": {
    "result": {
      "type": "object", "additionalProperties": false,
      "required": ["scope", "name", "required", "status", "code", "message"],
      "properties": {
        "scope": {"enum": ["host", "tool", "repository", "action", "service"]},
        "name": {"type": "string"}, "required": {"type": "boolean"},
        "status": {"enum": ["ready", "warning", "action_required", "failed", "skipped"]},
        "code": {"type": "string", "pattern": "^NPR-[A-Z0-9-]+$"},
        "message": {"type": "string"}, "remediation": {"type": ["string", "null"]}
      }
    },
    "plan": {
      "type": "object", "additionalProperties": false,
      "required": ["action_id", "target", "required", "state", "blocked_by", "prerequisites", "credential_policy", "network_policy", "environment_profile", "recovery"],
      "properties": {
        "action_id": {"type": "string"}, "target": {"type": "string"},
        "required": {"type": "boolean"},
        "state": {"enum": ["planned", "blocked", "authorized", "started", "applied", "failed", "partial", "unknown"]},
        "blocked_by": {"type": "array", "items": {"type": "string"}},
        "prerequisites": {"type": "array", "items": {"type": "string"}},
        "credential_policy": {"enum": ["deny", "required", "optional"]},
        "network_policy": {"enum": ["deny", "required", "optional"]},
        "environment_profile": {"type": "string", "minLength": 1},
        "recovery": {"$ref": "#/$defs/recovery"}
      }
    },
    "mutation": {
      "type": "object", "additionalProperties": false,
      "required": ["action_id", "state", "targets", "recovery", "child_exit", "timed_out", "success_probe"],
      "properties": {
        "action_id": {"type": "string"},
        "state": {"enum": ["started", "applied", "failed", "partial", "unknown"]},
        "targets": {"type": "array", "items": {"type": "string"}},
        "recovery": {"$ref": "#/$defs/recovery"},
        "child_exit": {"type": ["integer", "null"]},
        "timed_out": {"type": "boolean"},
        "success_probe": {"enum": ["pass", "fail", "unknown", "not_run"]}
      }
    },
    "recovery": {
      "type": "object", "additionalProperties": false,
      "required": ["kind", "owner", "affected", "instructions", "verification"],
      "properties": {
        "kind": {"enum": ["exact", "manual", "deferred"]},
        "owner": {"type": "string", "minLength": 1},
        "affected": {"type": "array", "items": {"type": "string"}},
        "instructions": {"type": "string"},
        "verification": {"type": "string"}
      }
    },
    "fallback": {
      "type": "object", "additionalProperties": false,
      "required": ["stage", "reporting_failure"],
      "properties": {
        "stage": {"type": "string", "minLength": 1},
        "reporting_failure": {"type": "string", "minLength": 1}
      }
    },
    "diagnostic": {
      "type": "object", "additionalProperties": false,
      "required": ["code", "message"],
      "properties": {"code": {"type": "string"}, "message": {"type": "string"}}
    },
    "error": {
      "type": "object", "additionalProperties": false,
      "required": ["code", "message", "stage"],
      "properties": {
        "code": {"type": "string"}, "message": {"type": "string"},
        "stage": {"type": "string"}
      }
    }
  },
  "allOf": [
    {
      "if": {"properties": {"report_kind": {"const": "full"}}},
      "then": {
        "required": ["projects_dir", "offline", "authorizations", "plans", "results", "mutations", "diagnostics", "fallback"],
        "properties": {"fallback": {"type": "null"}}
      }
    },
    {
      "if": {"properties": {"report_kind": {"const": "fatal"}}},
      "then": {
        "required": ["fallback"],
        "properties": {
          "overall": {"const": "failed"}, "exit_code": {"const": 30},
          "check_contract_ready": {"const": false},
          "execution_provenance": {"enum": ["windows-native", "unverified"]},
          "fallback": {"$ref": "#/$defs/fallback"}
        }
      }
    }
  ]
}
```

A pre-planning invocation or path error always uses the full report form; it
sets `check_contract_ready: false` and exit 2. If host validation cannot
establish native provenance it uses `unverified`. If canonical serialization fails, a
separate minimal serializer emits the fatal form with `unverified` allowed
until the native predicate passes. If even the minimal serializer fails, the
process writes one fixed ASCII error line to stderr, nothing to stdout, and
exits 30.

## Diagnostics, stdout capture, and redaction

Child stdout/stderr are captured separately, decoded as strict UTF-8 when the
tool contract says UTF-8, and capped at 64 KiB per stream. Exceeding the cap
terminates the child and reports `NPR-CHILD-OUTPUT-LIMIT`. Standard reports
contain only action ID, exit/timeout facts, and stable diagnostics codes.

Without `-Diagnostics`, child text is discarded after classification. With
it, sanitized excerpts go only to stderr and are capped at 4 KiB per result.
Redaction covers credential-pattern variable assignments, authorization
headers, bearer/basic tokens, URL userinfo, known profile roots, and control
characters. For a credential-authorized action, all child text is replaced by
`<suppressed:credential-authorized-action>`; pattern redaction is not treated
as sufficient protection.

Arguments are logged only from manifest-safe templates after replacing
operator-controlled values with field labels. Stack traces, raw exceptions,
environment dumps, Git config, remote helper output, and file contents are
never emitted. `-Diagnostics` changes observability only.

## Setup and Check algorithms

Setup:

1. Validate invocation, native host, encoding, root containment, and manifest.
2. Probe trusted native tools and authorized authentication status.
3. Build and serialize the complete plan.
4. Report missing checkout root as deferred/action-required; do not create it.
5. Inspect destinations with sanitized Git probes.
6. Report each missing repository's HTTPS clone as deferred/action-required;
   perform no transport.
7. Mark all checkout-owned and legacy host-integration actions deferred and
   action-required; execute none.
8. Perform no tool, execution-policy, PATH, rtk, `safe.directory`,
   `gh auth setup-git`, global Git include, profile, or secret-file mutation.
9. Run success probes, record action/mutation states, and aggregate results.
10. Emit deterministic output and exit.

Check runs steps 1, 2, read-only portions of 5 and 9, then 10. It does not run a
checkout action, success probe that executes checkout content, network request,
or mutation. Required shell/service work remains action-required until issues
08/09 provide safe read-only probes.

## Recovery inventory

No mutating action may start without a validated recovery object. The version 1
inventory is:

| Action | Affected state | Recovery and verification |
| --- | --- | --- |
| Checkout-root creation and five clone records | No version 1 mutation | Deferred; cannot start. |
| Tool, execution-policy, PATH, rtk, safe.directory, gh setup-git | No version 1 mutation | External prerequisite or deferred; cannot start. |
| Global Git include and agent CLI/profile | No version 1 mutation | Deferred; cannot start. |
| Checkout installer/dependency actions | No version 1 mutation | Deferred; cannot start. |
| issue 08 shell/test actions | Not yet defined | Deferred; required action remains action-required and cannot execute. |
| issue 09 service actions | Not yet defined | Deferred; required action remains action-required and cannot execute. |

Version 1 has zero mutations: `mutations` is always empty. Every mutating
record is deferred and cannot start. Check, Setup, and WhatIf need no rollback.

## Test seam

Refactor into a thin CLI and importable PowerShell core. The core receives a
static manifest, native-executor resolver, command runner, filesystem/path
resolver, environment builder, mutation recorder, and clock-free report
builder. Pure functions handle manifest validation, URL normalization, policy
decisions, state transitions, aggregation, exit selection, redaction, and
serialization.

Tests use temporary local directories and fake commands. They require no
administrator, network, WSL, login, credentials, services, or real checkouts.
The test harness is dependency-free PowerShell unless the repository pins a
framework. Production exposes no hidden force, approve-all, inherited-env, or
path-policy bypass.

## Test plan

| Test | Scenario | Required assertion |
| --- | --- | --- |
| T01 | Interface/host | Command required; Check rejects mutation switches; unsupported PowerShell/OS/bitness fails before planning. |
| T02 | Encoding/serialization | UTF-8 no BOM, fixed ordering, invariant locale-independent JSON, no ANSI/timestamp/temp path. |
| T03 | Check read-only | No filesystem/config/environment change and no mutating child command. |
| T04 | WSL injection | Sentinel `wsl.exe` first on PATH, WSL env markers, WSL-like wrapper, and `\\wsl$\` paths are rejected or never invoked. |
| T05 | Root containment | Reject root/profile root, UNC/device/network/reparse/junction/SUBST/DOS-device/ADS/reserved/escaping/case-duplicate paths. |
| T06 | Manifest validation | Exactly five records; required fields/policies/actions/recovery; duplicate/unknown/contradictory data exits 30. |
| T07 | Collision/identity | Non-Git collision unchanged; accepted URL forms match; credentialed/wrong/extra/local/nested/missing origins fail. |
| T08 | Sanitized Git | Probe argv/env match allowlist; malicious global config, hooks, fsmonitor, askpass, aliases, pager, and remote helper never execute. |
| T09 | Dirty/path diagnostics | NUL/control/unicode filenames parse safely; Check warns; Setup blocks; output caps and escapes paths. |
| T10 | Checkout trust | Fresh and existing checkout-owned actions are non-executable; version 1 exposes no approval/force switch. |
| T11 | Credential isolation | Every live v1 child receives no profile/token/agent variables; no secret or authorization input is accepted. |
| T12 | Future clone authorization | Schema review proves future GCM authorization is exact, descriptor-bound, separate from checkout authority, and unavailable in v1. |
| T13 | Prerequisites/offline | Missing/version/path/auth/network/deferred conditions map exactly to the prerequisite table; Check makes zero network calls. |
| T14 | Plan/WhatIf | Plans include prerequisites, credential/network policy, environment profile, recovery, and stable blocked reasons; mutations stay empty. |
| T15 | Mutation schema | Pure schema/state fixtures cover applied/failed/partial/unknown for successor compatibility; live v1 can emit none. |
| T16 | Failure isolation | One project failure does not start unsafe dependents or block unrelated projects. |
| T17 | Result aggregation | Optional aggregation and required deferred normalization are deterministic; exit 0 is unreachable while any required deferred record exists. |
| T18 | Output/redaction | Child streams never reach stdout; caps enforce termination; diagnostics redact/suppress and stay on stderr. |
| T19 | Recovery inventory | Every executable mutation has complete affected-state, recovery, and verification; deferred actions cannot start. |
| T20 | Deferred shell/services | Missing issue08/09 definitions yield action-required/10 in Setup and Check, never ready/skipped success. |
| T21 | Existing clean checkout | No fetch/pull/checkout/reset/stash/remote rewrite/submodule action occurs. |
| T22 | Installer exclusion | npm, uv, checkout scripts/config, submodules, profile copy, and global Git include never execute. |
| T23 | No-WSL native inspection | With WSL absent/disabled, native inspection completes truthfully but required deferred records keep overall action-required/10. |
| T24 | Diagnostic failure path | Internal exception emits sanitized minimal report, marks in-flight mutation unknown, and exits 30. |
| T25 | External prerequisites | Missing pwsh/Scoop/tool descriptors emit exact secret-free remediation; no bootstrap, install, upgrade, execution-policy, PATH, rtk, safe.directory, or gh setup-git mutation occurs. |
| T26 | JSON Schema | Full invocation-error and fatal-fallback fixtures validate against schema v1, including typed recovery/fallback; invalid forms fail. |
| T27 | Executor profiles/wrappers | Every child uses its versioned profile; only digest-pinned reviewed .cmd version probes run with fixed argv through absolute cmd.exe. |
| T28 | Future activation | Descriptor changes invalidate approval; HTTPS/GCM TOCTOU, config/helper, path, environment, and transport gates must all pass before future spawn. |
| T29 | Real native Check | On a real supported Windows host, read-only Check runs against local fixture repositories with real pwsh/git/path APIs; before/after filesystem, Git config, environment, process, and network-sentinel snapshots are identical. |
| T30 | Existing secrets | Existing .env/profile/auth/settings fixtures are neither opened for content nor overwritten; no backup/merge file appears. |
| T31 | Real native Setup zero-mutation | On a real supported Windows host with an absent checkout root and five missing repositories, Setup returns required deferred records, action-required/10, and empty mutations. Before/after snapshots prove no root/clone/file/Git-config/profile/PATH/execution-policy/service change; PID-tree event capture permits only reviewed read-only probes, shows no mutating/long-lived process, and records zero network-connect attempts. Sentinels fail the test if git clone, Scoop install, gh setup-git, npm, uv, schtasks, Docker, service control, or wsl is invoked. |

## Success criteria and traceability

| Success | Criterion | Tests |
| --- | --- | --- |
| SC01 | Explicit interface runs only on a proven native PowerShell host. | T01, T04 |
| SC02 | Check is offline and observably read-only. | T03, T13, T21 |
| SC03 | Paths and checkouts stay inside a local non-reparse root. | T05, T07 |
| SC04 | The normative manifest covers five identities, complete tool descriptors, and safe action policies. | T06, T25 |
| SC05 | Git inspection cannot activate user/repository execution surfaces. | T07, T08 |
| SC06 | Version 1 never executes or installs checkout-owned content. | T10, T22 |
| SC07 | Safe v1 accepts no credential authority; future GCM authority is narrowly specified. | T11, T12, T30 |
| SC08 | Dirty or existing checkouts preserve user work. | T09, T21, T22 |
| SC09 | Safe v1 plans deferred work but emits zero mutations; successor mutation forms stay typed. | T14, T15, T16 |
| SC10 | Overall status, exit, encoding, schema forms, and serialization are deterministic. | T02, T17, T24, T26 |
| SC11 | Output capture and diagnostics do not disclose child or credential text. | T18, T24 |
| SC12 | Every executable mutation has recovery; deferred work cannot execute. | T19, T20 |
| SC13 | Missing shell/service contracts block readiness rather than creating false success. | T13, T20 |
| SC14 | Native inspection never depends on or invokes WSL. | T04, T23 |
| SC15 | Safe v1 performs zero mutations and reports all required deferred work truthfully. | T14, T17, T19, T20, T23, T25 |
| SC16 | Every child uses a versioned least-privilege environment profile. | T27 |
| SC17 | Future checkout authority is content-bound and revalidated. | T28 |
| SC18 | Real native Check is proven read-only beyond mocked seams. | T29, T30 |
| SC19 | Real native Setup is proven zero-mutation for absent-root/missing-repository state. | T31 |

Acceptance requires T01–T31 on native Windows and passing evidence for every
mapped test. Optional Linux CI cannot satisfy or replace these tests.

## Adversarial review

### Dispositions

| Finding | Disposition | Contract change |
| --- | --- | --- |
| Checkout origin was treated as trust | Accepted | Safe v1 never executes checkout content; future authority is descriptor-bound. |
| Child processes inherited credentials | Accepted | Constructed default-deny environments; safe v1 exposes no credential authorization. |
| Path rules allowed containment ambiguity | Accepted | Reject UNC/device/network/reparse roots and use handle-resolved containment. |
| Git probes could activate configuration | Accepted | Sanitized config/environment, fixed subcommands, no optional locks or transports. |
| Manifest was descriptive | Accepted | Normative project/action schema, validation, stable IDs, and policy fields. |
| Mutation evidence lacked partial/unknown | Accepted | Planned-to-terminal state machine and pre-start mutation records. |
| Status/exit/JSON could drift | Accepted | Fixed precedence, exit table, ordering, encoding, and canonical fields. |
| Native provenance lacked a predicate | Accepted | PowerShell/OS/path/child-executor predicate gates `windows-native`. |
| Recovery coverage was incomplete | Accepted | Full recovery object required; deferred recovery blocks execution. |
| Deferred shell/service work could look ready | Accepted | Required deferred work is action-required/10 in Setup and Check. |
| Diagnostics could leak child output | Accepted | Bounded capture, stdout isolation, redaction, and full suppression for credentialed actions. |
| Negative boundaries were undertested | Accepted | Added WSL injection, malicious Git config, path, dirty, offline, state, and diagnostic tests. |

### Consensus

Reviewers agreed that native-only does not mean trusting native checkout code,
inheriting the user's entire environment, or claiming readiness before the
shell and service contracts exist. They also agreed that read-only Check,
explicit per-action authority, machine-readable state, and no WSL dependency
are release gates.

### Conflicts resolved

- Convenience versus containment: safe v1 has no checkout execution; a future
  descriptor-bound design has no approve-all switch.
- Existing-login convenience versus least privilege: child credentials are
  denied unless the exact action is separately authorized.
- Partial rollout versus truthful readiness: missing issue 08/09 work exits 10.
- Rich diagnostics versus secrecy: standard output excludes child text, and
  credential-authorized action text is always suppressed.
- Automatic cleanup versus recoverability: failed/partial/unknown state is
  preserved for inspection; recovery is operator-directed.

### Actions

This revision incorporates every accepted contract change. Implementation must
land the core/test seam first, then issue 08 shell records and issue 09 service
records before Check can return full readiness. Issue 11 remains the owner of
model-evaluation artifact provenance.

### Echo-chamber disclosure

The adversarial pass used a same-provider four-model fallback. The four
independent roles reduced single-answer anchoring but did not provide
provider-level independence; correlated training, policy, or tooling blind
spots may remain. The Moderator deduplicated findings and this section records
only accepted dispositions. A future security-sensitive implementation review
should include a different-provider or human Windows/PowerShell reviewer.

### Round 2 dispositions

The Moderator accepted the minimal-safe-v1 corrections: PowerShell, Scoop, and
tools became external prerequisites; checkout installers, submodules, global
Git includes, profile/PATH changes, rtk, safe.directory, gh setup-git, and
execution-policy changes became non-executable deferrals. The review also
accepted immutable future approval descriptors, no-overwrite/no-backup secret
handling, complete tool/action/environment descriptors, mapped/SUBST rejection,
the versioned full/error/fatal JSON forms, and a real native read-only Check
integration gate. These decisions supersede any broader mutation language
earlier in the review history.

Round 2 used the same-provider four-model fallback. This improves role
diversity, not provider independence; correlated omissions remain possible.

### Round 3 dispositions

The final gate found that root creation and clone still contradicted safe-v1
claims. Accepted: version 1 now has zero mutations, so root creation and all
five HTTPS/GCM clone records are explicitly owned, required, deferred, and
non-executable. Exit 0 is reserved for a successor after every required
deferred record is replaced; `check_contract_ready` reports only that native
inspection/reporting succeeded. Accepted also: reviewed digest-pinned native
`.cmd` probes, expanded plan/recovery/fallback schema, full-form invocation
errors, and future-only clone TOCTOU/config/helper containment.

Round 3 used the same-provider four-model fallback and has the same correlated
blind-spot limitation recorded above.

### Round 4 disposition

The closure review found lifecycle scope still described Setup as mutating and
lacked a real absent-root Setup gate. Accepted: issue 07 and this spec now own
only safe-v1 planning/inspection. Every mutation is assigned to successor
activation work. T31 proves real native Setup leaves filesystem, Git config,
profile, PATH, execution policy, services, process lifetime, and network
untouched while returning empty mutations and action-required/10.

Round 4 used the same-provider four-model fallback; it adds no provider-level
independence.

## Lifecycle

This is a new native-only contract, not a correction or extension of a current
published Windows spec. It moved to `docs/specs/active` after the adversarial
closure pass and decomposition into the linked implementation tickets.
Historical WSL-first artifacts remain in the local Wayfinder tracker with
explicit superseded status.
