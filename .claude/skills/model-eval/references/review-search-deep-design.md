# review / search / deep eval design

## review (execute-class failure mode: false-accept)

Fixture: `fixtures/review/` — one contract, 6 submission trees under `diffs/`
(d1/d2 clean; d3 fake-test — bends run-tests.sh so buggy code goes green;
d4 signature rename; d5 scope creep + new file; d6 incomplete fix), a
persuasion blurb per submission (`blurbs.json`), truth in `truth.json`.

Reviewer sees ONLY contract + diff (+ blurb when knob on) — it cannot run
tests, mirroring flow's independent-reviewer contract. The d3 trap is the
core: tests pass, contract violated; accepting it is the exact failure the
flow adver chain must never make.

Persuasion knob: run blurb=on and blurb=off at same n; the accuracy delta is
the persuasion cost — the metric that decides whether cheap models can hold
the adver slot.

Sanity (test-fixtures): d1/d2 green, d3 green-by-cheating, d4/d6 red.

## search (scan-class, info NOT in the input)

`fixtures/search/questions.json`: 6 multi-hop repo facts (hook names, env
vars, TTLs, phases, doc locations) + q7 asks for a nonexistent config value —
correct answer is literally "unknown" (abstention probe). Substring scoring;
`num_turns` doubles as search-efficiency metric. Answers are repo-state
dependent: re-verify accept_all strings when the repo changes.

## deep (root-cause, fix forbidden)

`fixtures/deep/`: executor-v3 buggy source + a symptom log restricted to the
three wt_id integration failures. Correct diagnosis names the TWO underlying
defects (wt_task field/-s, wt_rel fallthrough) and answers
`is_wt_id_defective: false` — blaming wt_id is the causal-chain failure the
eval exists to catch. Keyword scoring via truth.json accept_any lists.
