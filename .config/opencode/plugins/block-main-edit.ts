// block-main-edit.ts — OpenCode plugin (tool.execute.before)
//
// Equivalent of Claude Code PreToolUse hook: block-main-edit.sh
// Rule: edits are forbidden in the MAIN working tree. Develop in a linked
// worktree instead, so the main checkout always reflects a clean merged state.
//
// Detection: resolve the edit target's git directory — if it does NOT contain
// `/worktrees/` it's the main checkout → deny.
//
// Escape hatch: ALLOW_MAIN_EDIT=1 env var bypasses the check.

export const BlockMainEdit = async ({ $ }) => {
  return {
    "tool.execute.before": async (input, output) => {
      // Only intercept file-editing tools.
      const tool = input.tool
      if (!["edit", "write", "multi_edit", "notebook_edit"].includes(tool)) {
        return
      }

      // Escape hatch.
      if (process.env.ALLOW_MAIN_EDIT === "1") {
        return
      }

      // Resolve file path from tool args.
      const filePath = output.args.filePath || output.args.file_path || output.args.notebook_path
      if (!filePath) return

      const path = await import("path")
      const dir = path.dirname(path.resolve(filePath))

      // Resolve git-dir for the target path.
      let gitdir
      try {
        const result = await $`git -C ${dir} rev-parse --absolute-git-dir`.quiet()
        gitdir = result.stdout.toString().trim()
      } catch {
        // Not a git repo — allow.
        return
      }

      if (!gitdir) return

      // Linked worktree: git-dir contains /worktrees/ → allow.
      if (gitdir.includes("/worktrees/")) {
        return
      }

      // Main checkout → deny.
      throw new Error(
        `Blocked: editing the main working tree is forbidden.\n\n` +
        `  target: ${dir}\n\n` +
        `Create a linked worktree and develop there instead:\n\n` +
        `  git worktree add .worktree/<branch> -b <branch>\n` +
        `  cd .worktree/<branch>\n\n` +
        `Escape hatch: set ALLOW_MAIN_EDIT=1 env var.`
      )
    },
  }
}
