# Repository exploration

Native tools first: Read (offset/limit), Grep, Glob — not shell readers.
A global hook denies bare cat/head/tail/grep/rg/find-search/sed -n.
Pipelines, find -exec, real sed/awk programs pass; shell stays for
build/test/git. Native tool unavailable → retry with ALLOW_BARE_READ=1
(gitignored paths: ALLOW_BARE_READ=1 rg --no-ignore).
