# Recording discipline

`MEMORY.md` loads every session and is never pruned — record passive history
elsewhere. Ask in order; stop at the first match:

```
1. 能成護欄?            → skill / CONTEXT.md / agent instructions
2. 能機制硬擋?          → deny / hook / lint (update-config)
3. 架構決定?           → ADR (docs/adr/)
4. 已做完?             → git / PR
5. bug / 待辦 / 延後?   → triage 建單 → docs/issue/
6. n=1 觀察待評估?      → triage 建單 → docs/issue/ Status: needs-triage
                         (再犯加進同單 → triage 見 n≥2 → 升護欄)
7. 不可機制化跨-session 環境事實? → MEMORY (一行 ≤200 字)  ← 唯一進 MEMORY
```

Paths (`docs/issue/`, `docs/adr/`) are the skill-dev backend; other repos resolve
their own — the gate's *ordering* is what travels.
