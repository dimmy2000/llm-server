#!/usr/bin/env bash
# Тикет 13: подтвердить, что после `sendLoadingState: false` баннер загрузки
# llama-swap больше не появляется в `reasoning_content` (и нигде ещё) на
# запросе, который платит за загрузку движка.
#
#   1. PUT active=llama — выгрузить ninfer, llama.cpp не загружен.
#   2. Сразу стриминговый запрос на qwen3.8-27b (платит загрузку 40–60 c):
#      ожидаем ЧИСТЫЙ SSE без reasoning_content вовсе.
#   3. Контроль: второй запрос с thinking on (дефолт шаблона) — ожидаем
#      непустой reasoning_content от модели, т.е. поле не мёртвое.
#
#   ./probe-banner-off.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
API=http://127.0.0.1:8080

curl -s -m10 -X PUT "$API/api/profiles/active" -H 'Content-Type: application/json' -d '{"name":"llama"}' >/dev/null

# Шаг 2: первый запрос платит загрузку llama.cpp
curl -s -N -m900 -X POST "$API/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"Reply with only: ok"}],"max_tokens":8,"stream":true,"chat_template_kwargs":{"enable_thinking":false}}' \
  > "$HERE/stream-cold.sse"

# Шаг 3: контроль — движок уже горячий, thinking on
curl -s -N -m900 -X POST "$API/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"What is 2+2? Answer briefly."}],"max_tokens":3000,"stream":true}' \
  > "$HERE/stream-thinking.sse"

python3 - "$HERE" <<'PY'
import json, sys, os

def parse(path):
    reasoning, content = "", ""
    for line in open(path):
        if not line.startswith("data: "):
            continue
        payload = line[6:].strip()
        if payload in ("", "[DONE]"):
            continue
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if "error" in obj:
            return reasoning, content, obj["error"]
        for c in obj.get("choices") or []:
            d = c.get("delta") or {}
            reasoning += d.get("reasoning_content") or ""
            content += d.get("content") or ""
    return reasoning, content, None

here = sys.argv[1]
for name in ("stream-cold.sse", "stream-thinking.sse"):
    r, c, err = parse(os.path.join(here, name))
    print(f"=== {name}")
    if err:
        print(f"ERROR: {err}")
        continue
    print(f"reasoning_content ({len(r)} chars): {r[:120]!r}")
    print(f"content          ({len(c)} chars): {c[:120]!r}")
PY
