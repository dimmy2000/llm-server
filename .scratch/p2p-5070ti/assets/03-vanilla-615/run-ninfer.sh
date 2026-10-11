#!/usr/bin/env bash
# NInfer vanilla-615.71.09 baseline (H2), методика тикета 01.
# Decode-промпты реконструированы (оригиналы 01 не сохранялись) — приём драфта
# сравнивать направленно; префиллы — на тех же файлах промптов, точное сравнение.
set -euo pipefail
cd "$(dirname "$0")"
PY=bench.py

echo "=== ninfer 615.71.09 prefill 30k ==="
python3 $PY --model qwen3.8-27b --prompt-file prompt-30k.txt --max-tokens 4 \
  --out results-ninfer-615-prefill-30k.json --label ninfer-615-prefill-30k

echo "=== ninfer 615.71.09 prefill 90k (с vram-sampler) ==="
./vram-sampler.sh vram-sampler-ninfer-615.csv &
SAMPLER=$!
sleep 3
python3 $PY --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4 \
  --out results-ninfer-615-prefill-90k.json --label ninfer-615-prefill-90k
sleep 3
kill $SAMPLER 2>/dev/null || true

echo "=== ninfer 615.71.09 prefill 90k repeat ==="
python3 $PY --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4 \
  --out results-ninfer-615-prefill-90k-repeat.json --label ninfer-615-prefill-90k-repeat

echo "=== decode 600 essay (chat-medium) ==="
python3 $PY --model qwen3.8-27b-chat-medium \
  --prompt "Write a long essay about the history of alpine railways: engineering, tourism, and politics." \
  --max-tokens 600 --out results-ninfer-615-decode-600-essay.json --label ninfer-615-decode-600-essay

echo "=== decode 600 story (chat-medium) ==="
python3 $PY --model qwen3.8-27b-chat-medium \
  --prompt "Write a long story about a mountain railway climbing to a high alpine pass." \
  --max-tokens 600 --out results-ninfer-615-decode-600-story.json --label ninfer-615-decode-600-story

echo "=== decode 600 instruct ==="
python3 $PY --model qwen3.8-27b \
  --prompt "Write a detailed history of alpine railways, covering engineering, tourism, and politics." \
  --max-tokens 600 --out results-ninfer-615-decode-600-instruct.json --label ninfer-615-decode-600-instruct

echo "=== suite done ==="
