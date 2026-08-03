#!/bin/sh
# usage: run-tokenizer.sh <model> <lang:zh|en> <run_idx>
# out_tok on a verbatim-repeat of identical text = pure tokenizer size.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"; L="$2"; IDX="$3"
OUT="${MODEL_EVAL_OUT:-$HOME/model-eval-out}"
mkdir -p "$OUT"
TXT=$(/bin/cat "$SKILL/fixtures/tokenizer/tok-$L.txt")
TMP_JSON=$(mktemp)
printf '一字不差地重複以下文字，不要加任何其他內容：\n\n%s' "$TXT" \
  | sh "$SKILL/scripts/cli-run.sh" "$MODEL" "low" 1 "$TMP_JSON" 2>/dev/null
MODEL="$MODEL" L="$L" IDX="$IDX" OUT="$OUT" python3 -c "
import json, os
tmp = '$(printf '%s' "$TMP_JSON")'
try: d = json.load(open(tmp))
except Exception: d = {}
u = d.get('usage', {})
res = d.get('result') or ''
rec = {'q': 'tokenizer', 'model': os.environ['MODEL'], 'lang': os.environ['L'],
       'run': os.environ['IDX'], 'out_tok': u.get('output_tokens'),
       'chars_out': len(res), 'cost_usd': d.get('total_cost_usd')}
open(os.environ['OUT'] + '/ledger.jsonl', 'a').write(json.dumps(rec) + '\n')
print('tokenizer', rec['model'], rec['lang'], rec['out_tok'], 'tok /', rec['chars_out'], 'chars')
"
rm -f "$TMP_JSON"
