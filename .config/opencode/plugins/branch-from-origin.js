// branch-from-origin.js — OpenCode plugin (tool.execute.before)
//
// Guard: when creating a new branch, the base MUST be origin/main (or
// origin/<default>), never bare `main`. Local main may carry uncommitted
// or unpushed commits from a parallel subagent sharing the same checkout.
//
// Catches: git checkout -b <branch> main
//          git switch -c <branch> main
//          git branch <name> main
//
// Allows:  git checkout -b <branch> origin/main
//          git checkout -b <branch>  (no explicit base — git uses HEAD)
//          git checkout main  (switching to main, not creating a branch)

export const BranchFromOrigin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return

      const cmd = (output.args.command || "").trim()
      if (!cmd) return

      // Patterns that create a branch with an explicit base ref
      const patterns = [
        // git checkout -b <branch> <base>
        /git\s+checkout\s+-b\s+\S+\s+(main|master)\s*$/,
        /git\s+checkout\s+-b\s+\S+\s+(main|master)\s*[;&|]/,
        // git switch -c <branch> <base>
        /git\s+switch\s+-c\s+\S+\s+(main|master)\s*$/,
        /git\s+switch\s+-c\s+\S+\s+(main|master)\s*[;&|]/,
        // git branch <name> <base>  (create, not switch)
        /git\s+branch\s+(?!-[dD])\S+\s+(main|master)\s*$/,
        /git\s+branch\s+(?!-[dD])\S+\s+(main|master)\s*[;&|]/,
      ]

      for (const pat of patterns) {
        if (pat.test(cmd)) {
          throw new Error(
            `Blocked: branching from local \`main\` is forbidden.\n\n` +
            `  command: ${cmd}\n\n` +
            `Local main may carry stale commits from parallel subagents.\n` +
            `Use \`origin/main\` instead:\n\n` +
            `  git fetch origin && git checkout -b <branch> origin/main\n\n` +
            `This is a hard rule (AGENTS.md § Branch isolation).`
          )
        }
      }
    },
  }
}
