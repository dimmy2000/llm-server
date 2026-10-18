#!/usr/bin/env bash
# Тикет 11: снять доказательства с активного профиля (llama | ninfer) на
# собранном образе router:v265 с бампом llama.cpp b10068 -> b10438.
# Профиль переключается снаружи (PUT /api/profiles/active); скрипт его не
# трогает, только прогоняет curl-пробы и снимает VRAM/ps/logs.
#
#   ./run-pass.sh <backend>
#
# Пишет в assets/11-llama-bump/<backend>/:
#   *.sse / *.json      — сырые ответы проб
#   vram.csv / vram-min.txt — свободная VRAM по GPU и её минимум
#   ps.txt              — какой движок был жив (непараллельность)
#   container.log       — docker logs llama-swap за прогон
set -u
BACKEND=${1:?usage: run-pass.sh <backend>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/$BACKEND"
mkdir -p "$OUT"

# Сэмплер свободной VRAM: красная линия — >= 512 MiB на дисплейной GPU1.
(
  while true; do
    nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | paste -sd';'
    sleep 2
  done
) > "$OUT/vram.csv" &
VRAM_PID=$!

"$HERE/probe-reasoning.sh" "$BACKEND" | tee "$OUT/probe-reasoning.txt"
"$HERE/probe-tools.sh" "$BACKEND" | tee "$OUT/probe-tools.txt"

kill "$VRAM_PID" 2>/dev/null
wait 2>/dev/null

ps -eo pid,comm,args | grep -E 'ninfer-serve|llama-server' | grep -v grep > "$OUT/ps.txt" || true
docker logs llama-swap > "$OUT/container.log" 2>&1 || true

python3 - "$OUT/vram.csv" > "$OUT/vram-min.txt" <<'PY'
import sys
mins={}
with open(sys.argv[1]) as f:
    for line in f:
        for part in line.strip().split(';'):
            if not part: continue
            gpu,free = part.split(',')
            gpu, free = gpu.strip(), int(free.strip())
            mins[gpu]=min(mins.get(gpu, 1<<30), free)
for gpu in sorted(mins):
    print(f"GPU{gpu} min free MiB: {mins[gpu]}")
PY
cat "$OUT/vram-min.txt"
