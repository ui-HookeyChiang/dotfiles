// block-main-edit.js — OpenCode plugin wrapping the bash hook.
// Single source of truth: ~/.claude/hooks/block-main-edit.sh

import { execSync } from "child_process"
import { resolve, dirname } from "path"

const HOOK = (process.env.HOME || "") + "/.claude/hooks/block-main-edit.sh"

export const BlockMainEdit = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (!["edit", "write", "multi_edit", "notebook_edit"].includes(input.tool)) {
        return
      }

      if (process.env.ALLOW_MAIN_EDIT === "1") return

      const filePath = output.args.filePath || output.args.file_path || output.args.notebook_path
      if (!filePath) return

      const hookInput = JSON.stringify({
        tool_input: { file_path: resolve(filePath) },
      })

      let result
      try {
        result = execSync(`bash "${HOOK}"`, {
          input: hookInput,
          encoding: "utf8",
          timeout: 10000,
          env: { ...process.env },
          stdio: ["pipe", "pipe", "pipe"],
        })
      } catch {
        return
      }

      if (!result || !result.trim()) return

      try {
        const parsed = JSON.parse(result)
        const decision = parsed?.hookSpecificOutput?.permissionDecision
        if (decision === "deny") {
          throw new Error(parsed.hookSpecificOutput.permissionDecisionReason)
        }
      } catch (e) {
        if (e instanceof SyntaxError) return
        throw e
      }
    },
  }
}
