#!/usr/bin/env bash
# Тикет 07, проход 2: ОДНА И ТА ЖЕ клиентская конфигурация (opencode-test.json,
# вариант = `body.chat_template_kwargs`) гоняет матрицу reasoning x tools на
# активном профиле. Профиль переключается снаружи (PUT /api/profiles/active);
# скрипт только снимает доказательства и не трогает активный backend.
#
#   ./run-pass2.sh <backend>     # напр. ninfer | llama
#
# Пишет в assets/07-verify/pass2-kwargs/<backend>/:
#   tap/               — тело запроса и сырой SSE-ответ (через tap-proxy :8090)
#   opencode/          — события opencode `run --format json`
#   tap-summary.json   — разбор всех пар req/resp
#   vram.csv / vram-min.txt — минимум свободной VRAM по GPU
#   ps.txt             — какие движки были живы (доказательство непараллельности)
#   container.log      — логи llama-swap за прогон
set -u

BACKEND=${1:?usage: run-pass2.sh <backend>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/pass2-kwargs/$BACKEND"
# Рабочий каталог вне репозитория: иначе opencode подхватит AGENTS.md проекта.
WORK=/tmp/opencode/oc-work
mkdir -p "$OUT/tap" "$OUT/opencode" "$WORK"
echo 419 > "$WORK/notes.txt"

# opencode v2.0.32: конфиг — $OPENCODE_CONFIG (сливается с ~/.config/opencode),
# поэтому HOME уводим в песочницу и отключаем подкачку каталога моделей.
export HOME=/tmp/opencode/oc-home
export XDG_DATA_HOME=/tmp/opencode/oc-data
export XDG_CACHE_HOME=/tmp/opencode/oc-cache
export OPENCODE_CONFIG="$HERE/opencode-test.json"
export OPENCODE_DISABLE_MODELS_FETCH=1
mkdir -p "$HOME"

# tap: весь HTTP-трафик opencode -> llama-swap пишется на диск (порт 8090).
TAP_LOG_DIR="$OUT/tap" TAP_PORT=8090 nohup python3 "$HERE/tap-proxy.py" > "$OUT/tap.log" 2>&1 &
TAP_PID=$!
sleep 1

# Сэмплер свободной VRAM: красная линия — >= 512 MiB на дисплейной GPU1.
(
  while true; do
    nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | paste -sd';'
    sleep 2
  done
) > "$OUT/vram.csv" &
VRAM_PID=$!

PROMPT='Read the file ./notes.txt using the read tool. Reply with only the number stored in it, multiplied by 137.'

# id|agent|variant  (variant "" = голый ID, без варианта)
CASES=(
  "01-none-notools|tools-off|off"
  "02-low-notools|tools-off|low"
  "03-none-tools|tools-on|off"
  "04-medium-tools|tools-on|medium"
  "05-bare-default|tools-off|"
  "06-xhigh-notools|tools-off|xhigh"
)

for c in "${CASES[@]}"; do
  IFS='|' read -r id agent variant <<<"$c"
  if [ -n "$variant" ]; then model="self-hosted/qwen3.8-27b#$variant"; else model="self-hosted/qwen3.8-27b"; fi
  echo "== $BACKEND / $id (agent=$agent model=$model) $(date -Iseconds)"
  (cd "$WORK" && timeout 1500 opencode run --standalone --auto --format json \
      --thinking --agent "$agent" --model "$model" "$PROMPT" \
      > "$OUT/opencode/$id.json" 2> "$OUT/opencode/$id.err")
  echo "   exit=$? bytes=$(wc -c < "$OUT/opencode/$id.json")"
done

kill "$TAP_PID" "$VRAM_PID" 2>/dev/null
wait 2>/dev/null

# Какие движки живы прямо сейчас (единственный активный backend).
ps -eo pid,comm,args | grep -E 'ninfer-serve|llama-server' | grep -v grep > "$OUT/ps.txt" || true
docker logs llama-swap > "$OUT/container.log" 2>&1 || true

python3 "$HERE/analyze.py" "$OUT/tap" > "$OUT/tap-summary.json"
python3 - "$OUT/vram.csv" > "$OUT/vram-min.txt" <<'PY'
import sys
mins = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    for part in line.split(";"):
        idx, free = part.split(",")
        idx, free = int(idx), int(free)
        mins[idx] = min(mins.get(idx, 10**9), free)
for k in sorted(mins):
    print(f"GPU{k} min free MiB: {mins[k]}")
PY
cat "$OUT/vram-min.txt"
echo "== ps =="
cat "$OUT/ps.txt"
echo "== summary -> $OUT/tap-summary.json"
