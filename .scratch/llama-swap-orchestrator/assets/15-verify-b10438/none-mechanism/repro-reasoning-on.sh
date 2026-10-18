#!/usr/bin/env bash
# Тикет 15: минимальный репро инертности top-level reasoning_effort="none".
#
# Гипотеза: виноват CLI-флаг --reasoning on — он инжектит дефолтный template
# kwarg enable_thinking:"true" (arg.cpp), который переживает ветку none
# (server-common.cpp стирает только reasoning_effort) и на рендере
# перебивает inputs.enable_thinking=false (extra_context применяется после).
# Без --reasoning on (auto) none должен выключать thinking.
#
# Репро: два CPU-only llama-server (b10438) на крошечной Qwen3-0.6B,
# отличающиеся только флагом --reasoning on. /apply-template показывает рендер.
set -u
IMG=llm-server/router:v265   # b10438: оба инстанса на одном бинарнике, отличие только во флаге --reasoning
MODEL=/tmp/opencode/models/Qwen3-0.6B-Q8_0.gguf
OUT=$(cd "$(dirname "$0")" && pwd)

run_probe() {  # container port body
  docker exec "$1" curl -s "http://127.0.0.1:$2/apply-template" \
    -H 'Content-Type: application/json' --data-binary "$3"
}

start() {  # name port extra-flags
  docker rm -f "$1" >/dev/null 2>&1
  docker run --rm -d --name "$1" \
    -v /tmp/opencode/models:/models:ro \
    -e LD_LIBRARY_PATH=/app:/usr/local/cuda-13.3/lib64 \
    --entrypoint /app/llama-server \
    "$IMG" -m /models/Qwen3-0.6B-Q8_0.gguf --host 0.0.0.0 --port "$2" \
    -ngl 0 --jinja -c 4096 $3 >/dev/null
  # /health отдаёт 200 и во время загрузки — ждём /props (503, пока модель грузится)
  for i in $(seq 1 120); do
    code=$(docker exec "$1" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:"$2"/props || true)
    [ "$code" = "200" ] && break
    sleep 1
  done
  echo "  ($1 ready after ${i}s, props=$code)"
}

probe_all() {  # name port
  local name=$1 port=$2
  echo "## $name"
  for case in bare none kwargs-false; do
    case $case in
      bare)        body='{"messages":[{"role":"user","content":"hi"}]}' ;;
      none)        body='{"messages":[{"role":"user","content":"hi"}],"reasoning_effort":"none"}' ;;
      kwargs-false) body='{"messages":[{"role":"user","content":"hi"}],"chat_template_kwargs":{"enable_thinking":false}}' ;;
    esac
    prompt=$(run_probe "$name" "$port" "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("prompt",""))')
    tail="${prompt##*assistant}"
    echo "  $case -> gen tail: $(printf '%s' "$tail" | tail -c 40 | tr '\n' '~')"
    printf '%s' "$prompt" > "$OUT/repro-$name-$case.txt"
  done
  # и живой ответ: reasoning_content непуст/пуст
  resp=$(docker exec "$name" curl -s "http://127.0.0.1:$port/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    --data-binary '{"messages":[{"role":"user","content":"What is 2+2? One word."}],"reasoning_effort":"none","max_tokens":200}')
  echo "$resp" > "$OUT/repro-$name-response.json"
  python3 - "$OUT/repro-$name-response.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d["choices"][0]["message"]
print(f"  live none -> reasoning_content: {len(m.get('reasoning_content') or '')} chars; content: {(m.get('content') or '')[:60]!r}")
PY
}

echo "# минимальный репро: llama.cpp $(docker exec repro-on /app/llama-server --version 2>/dev/null | head -1)"
start repro-on 5811 "--reasoning on"
start repro-auto 5812 ""
probe_all repro-on 5811
probe_all repro-auto 5812
docker rm -f repro-on repro-auto >/dev/null 2>&1
echo DONE
