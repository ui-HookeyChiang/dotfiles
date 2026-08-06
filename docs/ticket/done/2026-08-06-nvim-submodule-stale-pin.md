# .config/nvim submodule pinned to commit missing on remote

Status: needs-triage
Created: 2026-08-06

## Problem

Fresh-clone `install.sh` aborts in `init_submodules`:

```
fatal: Fetched in submodule path '.config/nvim', but it did not contain
6dd97f67ece74ca0d25d0478856ba56b13efb50c. Direct fetching of that commit failed.
```

The gitlink points at a commit no longer reachable on
`ui-HookeyChiang/nvim` (force-pushed or unpushed local commit). Any new
machine bootstrap fails before the skills fanout. Found while testing the
skill-dev submodule migration (#137).

## Fix

Push the missing commit to the nvim remote, or re-pin the submodule to the
remote's current head. Consider making `init_submodules` warn-and-continue
per submodule instead of aborting the whole install.

## Blocked by

None.
