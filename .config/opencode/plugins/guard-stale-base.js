// guard-stale-base.js — OpenCode plugin (tool.execute.before)
//
// Unified stale-base guard:
// 1. BLOCK branching from bare main/master (forces origin/main)
// 2. WARN if shared base branch drifted from origin (config-driven)
//
// Config: .guard-stale-base.json at repo root, or ~/.claude/guard-stale-base.json.

import { existsSync, readFileSync } from "fs"
import { join } from "path"
import { execSync } from "child_process"

function loadConfig(cwd) {
  const candidates = [
    join(cwd, ".guard-stale-base.json"),
    join(process.env.HOME || "", ".claude", "guard-stale-base.json"),
  ]
  for (const p of candidates) {
    if (existsSync(p)) {
      try { return JSON.parse(readFileSync(p, "utf8")) } catch { /* skip */ }
    }
  }
  return null
}

function gitExec(cmd, cwd) {
  try {
    return execSync(cmd, { cwd, stdio: "pipe", timeout: 10000 }).toString().trim()
  } catch { return null }
}

export const GuardStaleBase = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return

      const cmd = (output.args.command || "").trim()
      if (!cmd) return

      const cwd = output.args.cwd || process.cwd()
      if (!gitExec("git rev-parse --git-dir", cwd)) return

      // Part 1: Block branching from bare main/master
      const branchPatterns = [
        /git\s+(?:checkout\s+-b|switch\s+-c|branch\s+(?!-[dD]))\S+\s+(main|master)\s*(?:$|[;&|])/,
        /git\s+worktree\s+add\s+\S+\s+(?:-b\s+\S+\s+)?(main|master)\s*(?:$|[;&|])/,
      ]

      for (const pat of branchPatterns) {
        const m = pat.exec(cmd)
        if (m) {
          const base = m[1]
          throw new Error(
            `Blocked: branching from local \`${base}\` is forbidden.\n\n` +
            `  command: ${cmd}\n\n` +
            `Local ${base} may carry stale or unpushed commits.\n` +
            `Use \`origin/${base}\` instead.\n`
          )
        }
      }

      // Part 2: Warn on stale shared base branches
      const config = loadConfig(cwd)
      if (!config || !config.shared_bases || !config.triggers) return

      const matchesTrigger = config.triggers.some(t => cmd.includes(t))
      if (!matchesTrigger) return

      const targetBase = config.shared_bases.find(b => {
        const re = new RegExp(`(^|[\\s/])${b.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&")}($|[\\s/])`)
        return re.test(cmd)
      })
      if (!targetBase) return

      gitExec(`git fetch origin ${targetBase} --quiet`, cwd)
      const behind = parseInt(gitExec(`git rev-list --count ${targetBase}..origin/${targetBase}`, cwd) || "0")
      const ahead = parseInt(gitExec(`git rev-list --count origin/${targetBase}..${targetBase}`, cwd) || "0")

      if (behind > 0 || ahead > 0) {
        let msg = `\u26a0 Shared base '${targetBase}' drifted from origin: `
        if (behind > 0) msg += `${behind} commit(s) BEHIND. `
        if (ahead > 0) msg += `${ahead} local-only commit(s). `
        msg += `Confirm before proceeding.`
        throw new Error(msg)
      }
    },
  }
}
