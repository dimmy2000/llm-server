#!/usr/bin/env bash
# Тикет 07: доказать, что `sendLoadingState: true` отдаёт баннер загрузки
# llama-swap как `reasoning_content` на запросе, который платит за загрузку.
#
# Уводит профиль на другой движок (чтобы текущий выгрузился), возвращает
# профиль обратно и сразу шлёт стриминговый запрос через tap. В ответе видно
# `reasoning_content` = текст баннера до `content` с настоящим ответом.
#
#   ./probe-loading-banner.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/banner-probe"
mkdir -p "$OUT/tap"
API=http://127.0.0.1:8080

curl -s -m10 -X PUT "$API/api/profiles/active" -H 'Content-Type: application/json' -d '{"name":"ninfer"}' >/dev/null
curl -s -m600 -X POST "$API/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}],"max_tokens":4,"stream":false,"chat_template_kwargs":{"enable_thinking":false}}' >/dev/null

TAP_LOG_DIR="$OUT/tap" TAP_PORT=8090 nohup python3 "$HERE/tap-proxy.py" > "$OUT/tap.log" 2>&1 &
TP=$!
sleep 1

curl -s -m10 -X PUT "$API/api/profiles/active" -H 'Content-Type: application/json' -d '{"name":"llama"}' >/dev/null
curl -s -N -m900 -X POST http://127.0.0.1:8090/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"Reply with only: ok"}],"max_tokens":8,"stream":true,"chat_template_kwargs":{"enable_thinking":false}}' > "$OUT/stream.sse" 2> "$OUT/stream.err"

kill "$TP" 2>/dev/null

python3 - "$OUT/stream.sse" <<'PY'
import json, sys
reasoning = "".join(
    (c.get("delta") or {}).get("reasoning_content") or ""
    for line in open(sys.argv[1])
    if line.startswith("data: ") and line[6:].strip() not in ("", "[DONE]")
    for c in (json.loads(line[6:]).get("choices") or [])
)
print(f"reasoning_content ({len(reasoning)} chars):")
print(reasoning)
PY
