#!/usr/bin/env bash
# Две полосы: пара равных промптов параллельно (методика тикетов 11/12/13).
# Пул под P2P auto 381 376 токенов: 2×196k = 392 754 не влезает, полоса
# обрезана до ~187k на запрос (2×187k + 2×600 < пул). VRAM под пиковой нагрузкой.
set -euo pipefail
cd "$(dirname "$0")"
PY=bench.py
PROMPT_FILE="${1:-prompt-187k.txt}"
MAXTOK="${2:-600}"

./vram-sampler.sh vram-sampler-p2p-twolanes.csv &
SAMPLER=$!
sleep 3

python3 $PY --model qwen3.8-27b --prompt-file "$PROMPT_FILE" --max-tokens "$MAXTOK" \
  --out results-p2p-twolanes-a.json --label ninfer-p2p-twolanes-a &
PA=$!
python3 $PY --model qwen3.8-27b --prompt-file "$PROMPT_FILE" --max-tokens "$MAXTOK" \
  --out results-p2p-twolanes-b.json --label ninfer-p2p-twolanes-b &
PB=$!
wait $PA; wait $PB

sleep 3
kill $SAMPLER 2>/dev/null || true
echo "=== two lanes done ==="
