#!/usr/bin/env bash
# Offline-проверка router-топологии (тикет 06, п.4): без GPU, настоящие движки
# заменены заглушками `sleep` + фиктивными HTTP-backend'ами.
#
#   LS_BIN=/tmp/opencode/t265/llama-swap bash run-smoke.sh
#
# Проверяет: единый ID в /v1/models, unlisted backend-записи, переключение
# профиля, пин ~ (404), useModelName для ninfer, stripParams repetition_penalty,
# непараллельность (ровно один cmd-процесс).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LS_BIN="${LS_BIN:-/tmp/opencode/t265/llama-swap}"
CONF="$HERE/smoke/config.yaml"
CONFDIR="$HERE/smoke/config.d"
LISTEN="127.0.0.1:8128"
BASE="http://$LISTEN"

PY=python3
PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

models() {
  curl -s "$BASE/v1/models" | $PY -c 'import sys,json;print([m["id"] for m in json.load(sys.stdin)["data"]])'
}
active() {
  curl -s "$BASE/api/profiles" | $PY -c 'import sys,json;print(json.load(sys.stdin)["active"])'
}
switch() {
  curl -s -X PUT "$BASE/api/profiles/active" -d "{\"name\":\"$1\"}" >/dev/null
}
chat() {
  curl -s -X POST "$BASE/v1/chat/completions" -H 'Content-Type: application/json' \
    -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}],"temperature":0.3,"repetition_penalty":1.4,"reasoning_effort":"medium"}'
}
cmds_running() { pgrep -c -x sleep 2>/dev/null || true; }

echo "=== llama-swap: $("$LS_BIN" --version)"
"$LS_BIN" -config "$CONF" -config-dir "$CONFDIR" -validate || { echo "VALIDATE FAILED"; exit 1; }

$PY "$HERE/router-smoke-backend.py" llama.cpp 19011 >/dev/null 2>&1 & PIDS+=($!)
$PY "$HERE/router-smoke-backend.py" ninfer    19012 >/dev/null 2>&1 & PIDS+=($!)
sleep 0.5
"$LS_BIN" -config "$CONF" -config-dir "$CONFDIR" -listen "$LISTEN" >"$HERE/smoke/llama-swap.log" 2>&1 & PIDS+=($!)
sleep 2

echo
echo "--- стартовый профиль (hooks.on_startup.profile):" "$(active)"
echo "--- /v1/models при активном ninfer (ожидаем ровно qwen3.8-27b):"; models
echo "--- backend-записи скрыты (unlisted): регекс не должен найти backend-*"
curl -s "$BASE/v1/models" | $PY -c 'import sys,json;ids=[m["id"] for m in json.load(sys.stdin)["data"]];print("backend-* в списке:", [i for i in ids if i.startswith("backend-")])'

echo
echo "--- прямой запрос к backend-ninfer при активном ninfer (unlisted, но достижим по имени):"
curl -s -o /dev/null -w '  POST backend-ninfer -> HTTP %{http_code}\n' -X POST "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d '{"model":"backend-ninfer","messages":[]}'

echo
echo "=== профиль llama ==="
switch llama
echo "active: $(active)"
echo "--- неактивный backend-ninfer закрыт пином ~ (ожидаем 404 и на /v1, и на /upstream):"
curl -s -o /dev/null -w '  POST /v1 model=backend-ninfer       -> HTTP %{http_code}\n' -X POST "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d '{"model":"backend-ninfer","messages":[]}'
curl -s -o /dev/null -w '  POST /upstream/backend-ninfer/...    -> HTTP %{http_code}\n' -X POST "$BASE/upstream/backend-ninfer/v1/chat/completions" -H 'Content-Type: application/json' -d '{"model":"backend-ninfer","messages":[]}'
echo "--- запрос model=qwen3.8-27b -> куда пришёл, с каким телом:"
chat; echo
echo "--- cmd-процессов sleep в момент запроса: $(cmds_running)"

echo
echo "=== профиль ninfer ==="
switch ninfer
echo "active: $(active)"
echo "--- запрос model=qwen3.8-27b (useModelName перепишет имя; repetition_penalty стрипается):"
chat; echo
echo "--- cmd-процессов sleep: $(cmds_running)"

echo
echo "=== профиль none (публичный ID выключен пином ~) ==="
switch none
echo "active: $(active)"
echo "--- /v1/models:"; models

echo
echo "=== done ==="
