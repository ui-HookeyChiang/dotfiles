# Harness pitfalls (each one cost a real batch)

1. **max-turns routing burn.** Headless `claude -p` loads the user's global
   CLAUDE.md. With `--max-turns 1` a generation task can return EMPTY: the
   model spends turn 1 on routing/skill/tool attempts. Symptom: out_tok
   ~200-1500 but `result` empty. Fix: `--max-turns 8+` for planner-class
   prompts; recover past runs by post-processing each run's `claude.json`.
2. **sed without /g.** Deriving a variant runner via `sed 's|a|b|'` replaces
   only the FIRST occurrence per line — a `cp` line with two fixture paths
   copied the old test suite; the batch ran the wrong suite and looked valid.
   Fix: always `/g`, AND assert the fixture marker (`test_last` must show the
   new suite's total, e.g. `pass=14`).
3. **cache pollution.** First run in a session pays ~29k cache_creation
   tokens (~2x cost); later runs read cache. Never compare cost across
   batches — use out_tok/latency; keep cost comparisons within one batch.
4. **non-numeric run index.** Ledger writers that `int()` the index crash on
   ids like `1L`; data survives in claude.json but the ledger line is lost.
   Keep indexes numeric-safe; the shipped runners store them as strings.
5. **verbatim-compliance blips.** Even frontier models occasionally ignore
   "repeat exactly" (added content, +60% chars). Record chars_out with
   out_tok so these runs can be excluded from tokenizer ratios.
6. **planner false-done.** A model may claim "Written plan.yaml" with no file
   written (headless, no write perms). Deterministic artifact-exists check
   before accepting any plan; count it as false_done, not as a low score.
7. **greedy JSON extraction.** `re.search(r'\{.*\}', s, re.S)` grabs first
   brace to LAST brace — any prose after the JSON makes json.loads raise
   "Extra data" and the run silently scores 0 (acc=0 with FA=FR=0 is the
   tell). Use `json.JSONDecoder().raw_decode(s[s.find('{'):])`. Rescore
   affected runs OFFLINE from claude.json — never rerun for a scoring bug.
