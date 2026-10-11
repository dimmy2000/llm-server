#!/usr/bin/env bash
# NInfer p2p-615.71.09 bench (тикет 05), методика тикетов 01/03.
# Промпты те же, что в 03 (decode-промпты реконструированы там); авто-nonce —
# каждый прогон холодный (device-state cache реплеит префикс).
set -euo pipefail
cd "$(dirname "$0")"
PY=bench.py

echo "=== ninfer p2p prefill 30k ==="
python3 $PY --model qwen3.8-27b --prompt-file prompt-30k.txt --max-tokens 4 \
  --out results-p2p-prefill-30k.json --label ninfer-p2p-prefill-30k

echo "=== ninfer p2p prefill 90k (с vram-sampler) ==="
./vram-sampler.sh vram-sampler-p2p-90k.csv &
SAMPLER=$!
sleep 3
python3 $PY --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4 \
  --out results-p2p-prefill-90k.json --label ninfer-p2p-prefill-90k
sleep 3
kill $SAMPLER 2>/dev/null || true

echo "=== ninfer p2p prefill 90k repeat ==="
python3 $PY --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4 \
  --out results-p2p-prefill-90k-repeat.json --label ninfer-p2p-prefill-90k-repeat

echo "=== decode 600 essay (chat-medium) ==="
python3 $PY --model qwen3.8-27b-chat-medium \
  --prompt "Write a long essay about the history of alpine railways: engineering, tourism, and politics." \
  --max-tokens 600 --out results-p2p-decode-600-essay.json --label ninfer-p2p-decode-600-essay

echo "=== decode 600 story (chat-medium) ==="
python3 $PY --model qwen3.8-27b-chat-medium \
  --prompt "Write a long story about a mountain railway climbing to a high alpine pass." \
  --max-tokens 600 --out results-p2p-decode-600-story.json --label ninfer-p2p-decode-600-story

echo "=== decode 600 instruct ==="
python3 $PY --model qwen3.8-27b \
  --prompt "Write a detailed history of alpine railways, covering engineering, tourism, and politics." \
  --max-tokens 600 --out results-p2p-decode-600-instruct.json --label ninfer-p2p-decode-600-instruct

echo "=== decode 8192 на prompt-90k (instruct, finish=length) ==="
./vram-sampler.sh vram-sampler-p2p-decode8k.csv &
SAMPLER=$!
sleep 3
python3 $PY --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 8192 \
  --out results-p2p-decode-8k.json --label ninfer-p2p-decode-8k
sleep 3
kill $SAMPLER 2>/dev/null || true

echo "=== suite done ==="
