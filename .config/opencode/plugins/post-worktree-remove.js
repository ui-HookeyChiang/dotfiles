// post-worktree-remove.ts — OpenCode plugin (tool.execute.after)
//
// Equivalent of Claude Code PostToolUse hook: post-worktree-remove.sh
// Cleans CRG DB when a worktree is removed via `git worktree remove`.
//
// Long-lived branches (stable/*, main, master, release/*) are preserved.

import { existsSync, rmSync } from "fs"
import { basename, dirname, resolve } from "path"
import { execSync } from "child_process"

export const PostWorktreeRemoveCRG = async ({ directory }) => {
  return {
    "tool.execute.after": async (input, _output) => {
      if (input.tool !== "bash") return

      const cmd = input.args?.command || ""
      if (!cmd.includes("git worktree remove")) return

      // Resolve repo name from git-common-dir.
      let repoName
      try {
        const gitCommon = execSync("git rev-parse --git-common-dir", {
          cwd: directory, stdio: "pipe"
        }).toString().trim()
        const gitCommonAbs = execSync(`cd "${gitCommon}" && pwd -P`, {
          cwd: directory, stdio: "pipe"
        }).toString().trim()
        repoName = basename(dirname(gitCommonAbs))
      } catch {
        return
      }

      const crgCache = resolve(process.env.HOME || "~", ".cache/crg", repoName)
      if (!existsSync(crgCache)) return

      // Extract worktree path from the remove command.
      const afterRemove = cmd.split("git worktree remove")[1] || ""
      const tokens = afterRemove.trim().split(/\s+/).filter(Boolean)

      // First non-flag arg is the worktree path.
      let worktreePath = ""
      for (const t of tokens) {
        if (t.startsWith("-")) continue
        worktreePath = t
        break
      }
      if (!worktreePath) return

      // Expand relative path.
      if (!worktreePath.startsWith("/")) {
        worktreePath = resolve(directory, worktreePath)
      }

      // Derive branch name from the worktree's HEAD before it's removed.
      let branch
      try {
        branch = execSync(`git -C "${worktreePath}" rev-parse --abbrev-ref HEAD`, {
          stdio: "pipe"
        }).toString().trim()
      } catch {
        return
      }
      if (!branch) return

      // Preserve long-lived branches.
      if (/^(stable\/|main$|master$|release\/)/.test(branch)) return

      // Delete the DB slot.
      const dbSlot = resolve(crgCache, branch.replace(/\//g, "-"))
      if (existsSync(dbSlot)) {
        try {
          rmSync(dbSlot, { recursive: true, force: true })
        } catch {
          // Best-effort.
        }
      }
    },
  }
}
