---
name: brief
description: >-
  Compose a review brief for a human reviewer — a short Slack/Teams mrkdwn
  message plus, for a design doc or postmortem, a self-contained HTML
  attachment with TL;DR and Origin sections. Covers code PRs, design-doc
  reviews, and incident postmortems. Use when PRs or a doc are ready and the
  user says "review brief", "幫我寫 review brief", "組 slack review 訊息",
  "design doc review brief", "postmortem brief", "brief 輸出 html", or needs a
  message to request human review before merge/sign-off. NOT for AI code
  review (use code-review), NOT for responding to feedback (use
  receiving-code-review).
argument-hint: "<PR-number|PR-URL|doc-link|feature-prefix>"
landing-group: workflow
---

# Review Brief

A **brief** is the minimum context a reviewer needs to start cold — what
changed, where to look, what passed. Optimise for the reviewer who opens this
with zero prior context and must decide in 30 seconds whether to dive in.

Two sections carry every brief:

- **TL;DR** — the 30-second skim. What broke or changed, and whether it's
  verified. A reviewer reads this alone and can decide.
- **Origin** — the story behind it. How the failure happened, how it was
  fixed, what was checked, what's still uncertain. Read only when TL;DR
  raises a question.

The brief writes both in plain, spoken language, the way you'd explain it to a
peer at the desk — never as a spec.

## Output shapes

Two artifacts, by target:

| Target | Slack message | HTML attachment |
|---|---|---|
| Code PR | ✅ mrkdwn | ❌ — reviewer opens the live PR via GitHub link unfurl |
| Design doc | ✅ mrkdwn | ✅ TL;DR + Origin |
| Postmortem | ✅ mrkdwn | ✅ TL;DR + Origin |

The **Slack message** is always mrkdwn text pasted into the input box. HTML
does NOT render there — never paste HTML into a message. The **HTML file** is
a self-contained attachment: reviewer opens it in a browser anywhere, no
Confluence login, no source file. It carries the full TL;DR + Origin; the
message just points at it.

## Steps

### 1. Gather

Pull these before writing. Missing any → ask the user.

| Field | Source |
|-------|--------|
| SCOPE | Product/component — ENVR, UNAS Pro, debfactory… |
| TOPIC | ≤5-word label naming the **problem**, not the change area |
| TL;DR | 1-3 sentences: what broke/changed + verified or not |
| Links | `gh pr list` filtered by prefix, or user-supplied URLs |
| Verification | evidence — see verification guard below |
| Origin | the story: how it happened, fix, checks, caveats (skip for trivial PR) |

**TOPIC names the problem.** For a bugfix the label states the failure being
removed, not the fix applied — "兩個記憶體壓力 OOM 修復" beats "記憶體壓力
修復"; "SFP link flap fix" beats "SFP driver change". A reviewer reads the
topic to judge relevance, and the symptom is what they recognise. A feature or
refactor has no prior failure to name, so it keeps a plain change label.

### 2. Write TL;DR

The reviewer grasps this in ~30 seconds with no subsystem context.

- **Lead with the pain, not the fix.** For a bugfix, open on the observed
  symptom or field evidence — "現場 NAS 在 585MB free 時仍被 OOM-killer 殺
  （3512 事件）" before "修法按 zone 縮放 boost 單位". For a feature/doc, open
  on what it enables.
- **Plain-language first.** If the lead needs ≥3 domain acronyms a peer
  outside the subsystem couldn't parse cold, prepend one plain sentence before
  any jargon.
- **End on the verdict.** State whether it's verified and how, in one clause.

### 3. Write Origin (skip for trivial PR)

The full story, for the reviewer who read TL;DR and wants to know how. Use
plain, spoken section labels — never wooden translations. Suggested headings
(pick what the story needs, adapt the wording):

- **為什麼會這樣 / What happened** — lay the causal chain, don't jump to the
  punchline. When the cause is a chain (A → B → C → failure) and a step needs
  subsystem knowledge, spell it out, one line per link, ≤4 links, stating the
  mechanism: "64K page → pageblock = 8192 pages = 512 MB → 一次 migratetype
  fallback 把 min watermark 抬高 512 MB → 實際還有 585 MB 卻跌破 watermark →
  假 OOM". A bare "one fallback boosts 512 MB" is a punchline the reader can't
  reconstruct. When every step is common ground, one sentence is enough.
- **怎麼修的 / The fix** — what changed, one or two sentences.
- **驗證了什麼 / What was checked** — numbered, each line one check: method
  (what ran, on what, how many) + verdict. Never a comma-spliced paragraph,
  never process narrative ("register decode 確認 UAF" ✓ / "3 個 reviewer 辯論
  兩個假設後確認" ✗), never a value judgment ("64k throughput −8%" ✓ / "用 8%
  換 panic 划算" ✗).
- **還沒把握的地方 / Caveats** — honest gaps (no clean repro, limited hardware,
  untested edge), each one sentence, never buried. Only for the gaps the
  reviewer needs to assess risk.

Not every heading applies to every brief. A design doc's Origin is "who
aligned + which tradeoffs resolved and how"; a postmortem's is "root cause
confirmed + fix verified". Keep the ones the story needs.

### 4. Verification guard (blocks output)

Every verification value states a **method** (what ran, on what, how many) AND
a **verdict**. Reject vague filler — "測試都過了", "CI 綠", "看起來沒問題".
Missing method or verdict → ask the user before formatting.

### 5. Format and output

**Slack message** — output verbatim in a fenced block:

```
幫看 <SCOPE> <TOPIC>

<TL;DR>

PRs：
 <URL>
 …

驗證結果：<verification>
<HTML attachment or deep-link, if any>
```

Relabel links for context: `文件：` (design doc) / `Postmortem：` (incident).

- Title: `幫看` + scope + topic. No punctuation, no emoji.
- Links: one URL per line, single leading space.
- Tone: conversational, plain verbs over formal ones — "砍了 / 卡住 / 壓掉 /
  少 9.7 倍" over "終止 / 阻塞 / 消除 / 降低 9.7 倍"; "killed / stuck / capped"
  over "terminated / blocked / eliminated". Never soften technical terms,
  symbols, numbers, error strings, or the guard for tone.
- Prose: `prose-guidelines` five principles apply.

**HTML attachment** (design doc + postmortem) — one self-contained `.html`
file, inline `<style>`, no external assets. Two `<section>`: TL;DR then
Origin, same content as above. Write it, then tell the user to upload it as a
Slack attachment (drag into the channel), NOT paste into the message. Trivial
code PR: no HTML — the GitHub link unfurl is the reviewer's entry point.

**Completion criterion:** verification guard passed; Slack message printed in a
fenced block; for a design doc / postmortem, the HTML file written and the
user told to attach it; user confirms sent.

## Examples

See [`references/examples.md`](references/examples.md) — worked Slack messages
(simple flat, multi-PR, layered bugfix with negative/positive contrast) and an
HTML attachment.
