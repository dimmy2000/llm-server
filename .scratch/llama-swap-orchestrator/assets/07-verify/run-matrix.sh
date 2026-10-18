#!/usr/bin/env bash
# Тикет 07: матрица reasoning x tools через opencode на едином endpoint'е.
#
#   ./run-matrix.sh <backend>
#
# Client-side управление (opencode v2.0.32):
#   reasoning → вариант модели `--model self-hosted/qwen3.8-27b#<none|low|medium|xhigh>`;
#   tools     → агент (`tools-on` / `tools-off`, permission deny) — в теле либо
#               12 инструментов, либо поля `tools` нет.
# Весь HTTP-трафик идёт через tap-proxy (127.0.0.1:8090): тело запроса и сырой
# ответ ложатся в assets/07-verify/<backend>/tap/.
set -u

BACKEND=${1:?usage: run-matrix.sh <backend>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/$BACKEND"
# Рабочий каталог вне репозитория: opencode иначе подхватит проектные AGENTS.md
# и дерево файлов, что исказило бы промпт и тест инструментов.
WORK=/tmp/opencode/oc-work
mkdir -p "$OUT/tap" "$OUT/opencode" "$WORK"
echo 419 > "$WORK/notes.txt"

PROMPT='Read the file ./notes.txt using the read tool. Reply with only the number stored in it, multiplied by 137.'

# Изоляция от пользовательского ~/.config/opencode: иначе его model-options
# (reasoning_effort medium + chat_template_kwargs) подмешиваются в тело.
export HOME=/tmp/opencode/oc-home
export XDG_DATA_HOME=/tmp/opencode/oc-data
export XDG_CACHE_HOME=/tmp/opencode/oc-cache
export OPENCODE_CONFIG="$HERE/opencode-test.json"
export OPENCODE_DISABLE_MODELS_FETCH=1
mkdir -p "$HOME"

# id|agent|variant
CASES=(
  "01-none-notools|tools-off|none"
  "02-low-notools|tools-off|low"
  "03-none-tools|tools-on|none"
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
  echo "   exit=$? events=$(grep -c . "$OUT/opencode/$id.json")"
done

echo "== анализ: python3 $HERE/analyze.py $OUT/tap"
python3 "$HERE/analyze.py" "$OUT/tap" > "$OUT/tap-summary.json"
echo "   -> $OUT/tap-summary.json"
