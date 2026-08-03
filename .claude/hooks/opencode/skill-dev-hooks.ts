import type { Plugin } from "@opencode-ai/plugin"
import { execSync } from "child_process"
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs"
import { resolve, join } from "path"

const HOME = process.env.HOME || ""
const HOOKS_DIR = join(HOME, ".claude", "hooks")
const WORKTREE_PATH_RE = /\.worktrees\/[^\s"'`]+/

function runBashHook(
  script: string,
  input: string,
  timeout: number,
  extraEnv?: Record<string, string>,
): string | null {
  try {
    return execSync(`bash "${script}"`, {
      input,
      encoding: "utf8",
      timeout,
      stdio: ["pipe", "pipe", "pipe"],
      env: extraEnv ? { ...process.env, ...extraEnv } : undefined,
    })
  } catch {
    return null
  }
}

function parseHookDecision(output: string | null): void {
  if (!output || !output.trim()) return
  try {
    const parsed = JSON.parse(output)
    const decision = parsed?.hookSpecificOutput?.permissionDecision
    if (decision === "deny") {
      throw new Error(parsed.hookSpecificOutput.permissionDecisionReason)
    }
  } catch (e) {
    if (e instanceof SyntaxError) return
    throw e
  }
}

function getAgentMap(sessionID: string, dir: string): string | null {
  const mapFile = join(dir, ".worktrees", ".agent-map", sessionID)
  try {
    return readFileSync(mapFile, "utf8").trim() || null
  } catch {
    return null
  }
}

function runWorktreeGuard(
  agentId: string,
  toolName: string,
  toolInput: Record<string, unknown>,
  cwd: string,
  dir: string,
): void {
  const hook = join(HOOKS_DIR, "guard-agent-worktree.sh")
  if (!existsSync(hook)) return
  const hookInput = JSON.stringify({
    agent_id: agentId,
    tool_name: toolName,
    tool_input: toolInput,
    cwd,
  })
  parseHookDecision(
    runBashHook(hook, hookInput, 10000, { CLAUDE_PROJECT_DIR: dir }),
  )
}

export const SkillDevHooks: Plugin = async ({ client, directory }) => {
  const checkedSessions = new Map<string, boolean>()
  return {
    // agent-map writer: when a child session receives its first message,
    // check if it's a subagent (has parentID) and extract the worktree path
    "chat.message": async (input, output) => {
      const { sessionID } = input
      if (checkedSessions.has(sessionID)) return
      checkedSessions.set(sessionID, true)

      try {
        const resp = await client.session.get({
          path: { id: sessionID },
        })
        const session = resp.data
        if (!session?.parentID) return

        const text = output.parts
          .map((p) => ("content" in p ? String(p.content) : "prompt" in p ? String(p.prompt) : ""))
          .join(" ")
        const match = text.match(WORKTREE_PATH_RE)
        if (!match) return

        const candidate = match[0]
        const abs = candidate.startsWith("/")
          ? candidate
          : join(directory, candidate)
        const mapDir = join(directory, ".worktrees", ".agent-map")
        mkdirSync(mapDir, { recursive: true })
        writeFileSync(join(mapDir, sessionID), abs)
      } catch {
        // non-fatal: guard will treat unmapped sessions as allowed
      }
    },

    "tool.execute.before": async (input, output) => {
      const tool = input.tool

      // block-main-edit: deny Edit/Write on main worktree
      if (["edit", "write", "multi_edit", "notebook_edit"].includes(tool)) {
        if (process.env.ALLOW_MAIN_EDIT === "1") return
        const filePath =
          output.args.filePath || output.args.file_path || output.args.notebook_path
        if (!filePath) return

        const hook = join(HOOKS_DIR, "block-main-edit.sh")
        if (!existsSync(hook)) return
        const hookInput = JSON.stringify({
          tool_input: { file_path: resolve(filePath) },
        })
        parseHookDecision(runBashHook(hook, hookInput, 10000))

        // guard-agent-worktree: file tools
        const mapped = getAgentMap(input.sessionID, directory)
        if (mapped) {
          const toolNameMap: Record<string, string> = {
            edit: "Edit",
            write: "Write",
            multi_edit: "MultiEdit",
            notebook_edit: "NotebookEdit",
          }
          runWorktreeGuard(
            input.sessionID,
            toolNameMap[tool] || tool,
            { file_path: resolve(filePath) },
            directory,
            directory,
          )
        }
        return
      }

      // guard-stale-base + guard-agent-worktree: Bash
      if (tool === "bash") {
        const cmd = (output.args.command || "").trim()
        if (!cmd) return

        const bareReadHook = join(HOOKS_DIR, "block-bare-read.sh")
        if (existsSync(bareReadHook)) {
          const hookInput = JSON.stringify({
            tool_input: { command: cmd },
          })
          parseHookDecision(runBashHook(bareReadHook, hookInput, 10000))
        }

        const staleHook = join(HOOKS_DIR, "guard-stale-base.sh")
        if (existsSync(staleHook)) {
          const hookInput = JSON.stringify({
            tool_input: { command: cmd },
            cwd: output.args.cwd || process.cwd(),
          })
          parseHookDecision(runBashHook(staleHook, hookInput, 15000))
        }

        // guard-agent-worktree: Bash — cwd not in hook input, use project dir
        const mapped = getAgentMap(input.sessionID, directory)
        if (mapped) {
          runWorktreeGuard(
            input.sessionID,
            "Bash",
            { command: cmd },
            directory,
            directory,
          )
        }
      }
    },
  }
}
