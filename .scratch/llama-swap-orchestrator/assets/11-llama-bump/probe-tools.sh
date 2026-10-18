#!/usr/bin/env bash
# Тикет 11: smoke уровня движка после бампа — разбор tool-calls (llama.cpp
# b10438 принёс специализированный парсер qwen3) и управление им через
# reasoning. Нужен уже ЗАГРУЖЕННЫЙ движок.
#
#   ./probe-tools.sh <tag>
set -u
TAG=${1:?usage: probe-tools.sh <tag>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/$TAG"
mkdir -p "$OUT"
URL=http://127.0.0.1:8080/v1/chat/completions

TOOLS='[{"type":"function","function":{"name":"get_weather","description":"Get the current weather for a city","parameters":{"type":"object","properties":{"city":{"type":"string","description":"City name"}},"required":["city"]}}}]'
MSG='[{"role":"user","content":"What is the current weather in Paris? Use the get_weather tool."}]'

probe() {
  local id=$1 body=$2
  echo "  - $id"
  curl -s -X POST "$URL" -H 'Content-Type: application/json' -d "$body" \
    > "$OUT/$id.json" 2> "$OUT/$id.err"
  python3 - "$OUT/$id.json" "$id" <<'PY'
import json,sys
raw=open(sys.argv[1]).read()
try:
    d=json.loads(raw)
except Exception:
    print("      RAW:", raw.strip()[:200]); raise SystemExit
if "error" in d:
    print("      ERROR:", json.dumps(d["error"])[:200]); raise SystemExit
ch=(d.get("choices") or [{}])[0]
m=ch.get("message") or {}
tc=m.get("tool_calls") or []
names=[ (t.get("function") or {}).get("name") for t in tc ]
args=[ (t.get("function") or {}).get("arguments") for t in tc ]
print(f"      finish={ch.get('finish_reason')!r} tool_calls={names} args={args} reasoning_chars={len(m.get('reasoning_content') or '')}")
PY
}

probe 01-tools-bare    "{\"model\":\"qwen3.8-27b\",\"messages\":$MSG,\"tools\":$TOOLS,\"max_tokens\":300}"
probe 02-tools-none    "{\"model\":\"qwen3.8-27b\",\"messages\":$MSG,\"tools\":$TOOLS,\"max_tokens\":300,\"reasoning_effort\":\"none\"}"
probe 03-notools-bare  "{\"model\":\"qwen3.8-27b\",\"messages\":$MSG,\"max_tokens\":300}"
probe 04-notools-none  "{\"model\":\"qwen3.8-27b\",\"messages\":$MSG,\"max_tokens\":300,\"reasoning_effort\":\"none\"}"
