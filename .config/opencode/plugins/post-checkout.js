// post-checkout.ts — OpenCode plugin (tool.execute.after)
//
// Equivalent of Claude Code PostToolUse hook: post-checkout.sh
// Seeds CRG (code-review-graph) DB into a fresh worktree on `git worktree add`.
//
// DB layout: ~/.cache/crg/<repo>/<branch-slug>/
// On worktree add: copy base branch DB → incremental update.

import { existsSync, cpSync, mkdirSync } from "fs"
import { basename, dirname, resolve } from "path"
import { execSync } from "child_process"

function which(cmd) {
  try {
    execSync(`command -v ${cmd}`, { stdio: "pipe" })
    return true
  } catch {
    return false
  }
}

export const PostCheckoutCRG = async ({ directory }) => {
  return {
    "tool.execute.after": async (input, _output) => {
      if (input.tool !== "bash") return

      const cmd = input.args?.command || ""
      if (!cmd.includes("git worktree add")) return

      // code-review-graph must be installed.
      if (!which("code-review-graph")) return

      // Resolve git-common-dir.
      let gitCommonAbs
      try {
        const gitCommon = execSync("git rev-parse --git-common-dir", {
          cwd: directory, stdio: "pipe"
        }).toString().trim()
        gitCommonAbs = execSync(`cd "${gitCommon}" && pwd -P`, {
          cwd: directory, stdio: "pipe"
        }).toString().trim()
      } catch {
        return
      }

      const repoRoot = dirname(gitCommonAbs)
      const repoName = basename(repoRoot)

      // Parse the git worktree add command for positional args.
      const afterAdd = cmd.split("git worktree add")[1] || ""
      const tokens = afterAdd.trim().split(/\s+/).filter(Boolean)

      // Strip flags: -b <name>, --track, --detach, etc.
      const positionals = []
      for (let i = 0; i < tokens.length; i++) {
        if (tokens[i] === "-b" || tokens[i] === "--track") {
          i++ // skip next arg
          continue
        }
        if (tokens[i].startsWith("-")) continue
        positionals.push(tokens[i])
      }

      let worktreePath = positionals[0]
      const commitIsh = positionals[1] || ""
      if (!worktreePath) return

      // Expand relative path.
      if (!worktreePath.startsWith("/")) {
        worktreePath = resolve(directory, worktreePath)
      }

      if (!existsSync(worktreePath)) return

      // Derive base branch.
      let baseBranch
      if (commitIsh) {
        baseBranch = commitIsh.replace(/^origin\//, "")
      } else {
        try {
          baseBranch = execSync("git symbolic-ref refs/remotes/origin/HEAD", {
            cwd: directory, stdio: "pipe"
          }).toString().trim().replace("refs/remotes/origin/", "")
        } catch {
          baseBranch = "main"
        }
      }

      // New branch name (from -b flag or worktree basename).
      let newBranch = ""
      const bIdx = tokens.indexOf("-b")
      if (bIdx >= 0 && bIdx + 1 < tokens.length) {
        newBranch = tokens[bIdx + 1]
      }
      if (!newBranch) newBranch = basename(worktreePath)

      // DB paths.
      const crgCache = resolve(process.env.HOME || "~", ".cache/crg", repoName)
      const baseDb = resolve(crgCache, baseBranch.replace(/\//g, "-"))
      const newDb = resolve(crgCache, newBranch.replace(/\//g, "-"))

      // Already seeded — skip.
      if (existsSync(newDb)) return

      // Base DB must exist to copy from.
      if (!existsSync(baseDb)) return

      // Copy base DB → new branch slot, then incremental update.
      try {
        mkdirSync(crgCache, { recursive: true })
        cpSync(baseDb, newDb, { recursive: true })
        execSync(
          `code-review-graph update --repo "${worktreePath}" --data-dir "${newDb}" --base "${baseBranch}"`,
          { stdio: "pipe", timeout: 30000 }
        )
      } catch {
        // Best-effort: don't block on CRG failures.
      }
    },
  }
}
