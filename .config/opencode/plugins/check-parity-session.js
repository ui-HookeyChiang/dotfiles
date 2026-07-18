// check-parity-session.js — OpenCode plugin (session.created)
// Lightweight parity check at session start. Reports drift.

import { execSync } from "child_process"
import { existsSync, realpathSync } from "fs"
import { join, dirname } from "path"

export const CheckParitySession = async () => {
  return {
    "session.created": async () => {
      const home = process.env.HOME || ""
      let hookRepo = ""
      try {
        hookRepo = dirname(dirname(realpathSync(join(home, ".claude", "hooks", "check-parity-session.sh"))))
      } catch {}
      const candidates = [
        join(home, ".claude", "skills", "agent-parity", "scripts", "check-parity.sh"),
        ...(hookRepo ? [join(hookRepo, "agent-parity", "scripts", "check-parity.sh")] : []),
      ]

      let script = null
      for (const c of candidates) {
        if (existsSync(c)) { script = c; break }
      }
      if (!script) return

      try {
        const output = execSync(`bash "${script}"`, { encoding: "utf8", timeout: 10000 })
        const gapMatch = output.match(/(\d+) gap/)
        const warnMatch = output.match(/(\d+) warning/)
        const gaps = parseInt(gapMatch?.[1] || "0")
        const warnings = parseInt(warnMatch?.[1] || "0")

        if (gaps > 0 || warnings > 0) {
          const lines = output.split("\n").filter(l => /MISSING|DRIFTED|UNDECLARED|DIVERGED/.test(l))
          console.warn(`Agent parity drift: ${gaps} gap(s), ${warnings} warning(s)`)
          lines.forEach(l => console.warn("  " + l.trim()))
        }
      } catch {
        // Silent fail — don't block session start
      }
    },
  }
}
