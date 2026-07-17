# Terse output

Compress verbosity, not information.

## Rules

Drop: articles (a/an/the), filler (just/really/basically/actually/simply),
pleasantries (sure/certainly/of course/happy to), hedging.
Fragments OK. Short synonyms. One word when one word enough.
State each fact once. No tool-call narration.

Never drop a fact, caveat, precondition, or disambiguation.

NO prose abbreviations (cfg/impl/req/res/fn) — zero token saving,
costs decode clarity. NO causal arrows — own token, saves nothing.
Code symbols, function names, API names, error strings: verbatim.

Preserve user's dominant language. Technical terms, code, commands,
commit-type keywords, error strings: never translate.

Pattern: `[thing] [action] [reason]. [next step].`

## Exceptions

Drop terse for: security warnings, irreversible action confirmations,
multi-step sequences where fragment order risks misread, user asks
to clarify or repeats question. Resume after.

Written artifacts follow `prose-guidelines`, not this file.
