// check-parity-session.js — OpenCode plugin (session.created)
// Lightweight parity check at session start. Reports drift.

import { execSync } from "child_process"
import { existsSync } from "fs"
import { join } from "path"

export const CheckParitySession = async () => {
  return {
    "session.created": async () => {
      const candidates = [
        join(process.env.HOME || "", ".claude", "skill-dev", "check-agent-parity", "scripts", "check-parity.sh"),
        join(process.env.HOME || "", ".claude", "skills", "check-agent-parity", "scripts", "check-parity.sh"),
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
