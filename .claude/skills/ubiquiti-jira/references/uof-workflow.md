# UOF Workflow State Machine

Complete state machine for the UOF Jira project, derived from live API
queries (2026-06-29).

## States (11)

| Status | ID | Category | Terminal? |
|---|---|---|---|
| Backlog | 15196 | 待辦事項 | no |
| 待辦事項 | 15191 | 待辦事項 | no |
| RD In Progress | 15192 | 進行中 | no |
| Block | 15211 | 進行中 | no |
| Ready to QA | 15194 | 進行中 | no |
| Test build for QA | 15212 | 進行中 | no |
| Ready to Merge | 15213 | 進行中 | no |
| Need more info | 15197 | 進行中 | no |
| monitoring | 15737 | 進行中 | no |
| Stable Version Verified | 15256 | 完成 | yes |
| No need to fix | 15193 | 完成 | yes |

## Global Transitions (available from ANY status)

| ID | Name | Target |
|----|------|--------|
| 2 | monitoring | monitoring |
| 3 | RD In Progress | RD In Progress |
| 21 | Need more info | Need more info |

## Status-Specific Transitions

| ID | From | Transition Name | To |
|----|------|-----------------|-----|
| 91 | Backlog | Ready to Develop | 待辦事項 |
| 101 | Backlog | Close issue | No need to fix |
| 31 | 待辦事項 | Start to Develop | RD In Progress |
| 41 | 待辦事項 | Close issue | No need to fix |
| 111 | RD In Progress | Dev Completed | Ready to QA |
| 121 | RD In Progress | RD Completed & Close | No need to fix |
| 131 | RD In Progress | Block by something | Block |
| 141 | RD In Progress | PR release | Test build for QA |
| 201 | Block | In progress | RD In Progress |
| 211 | Block | Ready to QA | Ready to QA |
| 61 | Ready to QA | Failed to verify | 待辦事項 |
| 81 | Ready to QA | Verified stable branch | Stable Version Verified |
| 221 | Test build for QA | QA Verified | Ready to Merge |
| 231 | Ready to Merge | completed | No need to fix |
| 251 | Stable Version Verified | Failed to verify | 待辦事項 |

Need more info has 4 exits (IDs 151/161/171/181) back to
待辦事項 / RD In Progress / Ready to QA / No need to fix.

## Typical Paths

### Happy path (PR merge → QA)

```
Backlog --(91)--> 待辦事項 --(31)--> RD In Progress --(111)--> Ready to QA
```

Or use global transition (3) to jump to RD In Progress from any state,
then (111) to Ready to QA.

### PR release path (test build needed)

```
RD In Progress --(141)--> Test build for QA --(221)--> Ready to Merge --(231)--> No need to fix
```

### Block → resume

```
RD In Progress --(131)--> Block --(201)--> RD In Progress --(111)--> Ready to QA
```

### QA failure → rework

```
Ready to QA --(61)--> 待辦事項 --(31)--> RD In Progress --(111)--> Ready to QA
```

### Stable verified

```
Ready to QA --(81)--> Stable Version Verified
```

## customfield_12889 (Secondary "Status" Field)

A manually-set select field tracking dev stage, independent of workflow status.
13 values: Not Started / Ready to development / In progress / Development Done /
Need Build / In Review / Block by other team / Verified test build / Verified /
Redo / Duplicate / No longer need / Can't reproduce.

## fixVersion Convention

| Merge branch | fixVersion | Example |
|---|---|---|
| `master` | current `PRODUCT_VERSION` from `conf/arch/version` | `6.0.0` |
| `stable/5.1` | same | `5.1.21` |
| `stable/5.0` | same | `5.0.18` |

A ticket may have **multiple** fixVersions (backport to multiple branches).
