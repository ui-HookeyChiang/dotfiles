// guard-stale-base.js — OpenCode plugin wrapping the bash hook.
// Single source of truth: ~/.claude/hooks/guard-stale-base.sh

import { execSync } from "child_process"

const HOOK = (process.env.HOME || "") + "/.claude/hooks/guard-stale-base.sh"

export const GuardStaleBase = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return

      const cmd = (output.args.command || "").trim()
      if (!cmd) return

      const hookInput = JSON.stringify({
        tool_input: { command: cmd },
        cwd: output.args.cwd || process.cwd(),
      })

      let result
      try {
        result = execSync(`bash "${HOOK}"`, {
          input: hookInput,
          encoding: "utf8",
          timeout: 15000,
          stdio: ["pipe", "pipe", "pipe"],
        })
      } catch {
        return // hook not found or errored — allow
      }

      if (!result || !result.trim()) return // no output = allow

      try {
        const parsed = JSON.parse(result)
        const decision = parsed?.hookSpecificOutput?.permissionDecision
        if (decision === "deny") {
          throw new Error(parsed.hookSpecificOutput.permissionDecisionReason)
        }
      } catch (e) {
        if (e instanceof SyntaxError) return // not JSON — allow
        throw e // re-throw Error from deny
      }
    },
  }
}
