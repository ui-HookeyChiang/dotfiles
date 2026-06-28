// warn-stale-main.ts — OpenCode plugin (event: session.created + tool.execute.before)
//
// Equivalent of Claude Code UserPromptSubmit hook: warn-stale-main.sh
// Warns when HEAD is behind its upstream or has moved since the last warning.
// Advisory only: injects a re-read nudge, never blocks.

import { existsSync, readFileSync, writeFileSync } from "fs"
import { join } from "path"
import { execSync } from "child_process"

function checkStaleMain(cwd) {
  try {
    execSync("git rev-parse --git-dir", { cwd, stdio: "pipe" })
  } catch {
    return null // not a repo
  }

  const gitdir = execSync("git rev-parse --git-dir", { cwd, stdio: "pipe" }).toString().trim()
  const stamp = join(gitdir, ".opencode-session-head")
  let now
  try {
    now = execSync("git rev-parse HEAD", { cwd, stdio: "pipe" }).toString().trim()
  } catch {
    return null
  }

  // (a) behind upstream
  let behind = 0
  try {
    execSync("git rev-parse --abbrev-ref @{upstream}", { cwd, stdio: "pipe" })
    behind = parseInt(
      execSync("git rev-list --count HEAD..@{upstream}", { cwd, stdio: "pipe" }).toString().trim(),
      10
    ) || 0
  } catch {
    // no upstream configured
  }

  // (b) HEAD moved since last warning
  let moved = ""
  let prev = ""
  if (existsSync(stamp)) {
    prev = readFileSync(stamp, "utf-8").trim()
  }
  if (prev && prev !== now) {
    moved = `HEAD moved ${prev.slice(0, 8)}\u2192${now.slice(0, 8)}`
  }

  let msg = ""
  if (behind > 0) msg += `main ${behind} commit(s) ahead of HEAD (as of last fetch). `
  if (moved) msg += `${moved}. `

  if (msg) {
    // Advance stamp: warn once per move.
    try { writeFileSync(stamp, now + "\n") } catch {}
    return msg
  }

  // Seed the stamp on first prompt if missing.
  if (!existsSync(stamp)) {
    try { writeFileSync(stamp, now + "\n") } catch {}
  }

  return null
}

export const WarnStaleMain = async ({ directory }) => {
  return {
    // Check on every tool execution (lightweight git queries).
    "tool.execute.before": async (input, _output) => {
      // Only check on user-facing tool calls, not every sub-call.
      // We piggyback on any tool call as our "prompt submit" equivalent.
      if (input.tool !== "bash" && input.tool !== "edit" && input.tool !== "write") {
        return
      }

      const msg = checkStaleMain(directory)
      if (msg) {
        // Inject warning via console — OpenCode surfaces plugin logs.
        console.warn(`\u26A0 Stale-code guard: ${msg}Re-read any file from disk before editing or quoting line numbers.`)
      }
    },
  }
}
