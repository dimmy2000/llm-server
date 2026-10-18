#!/usr/bin/env bash
# Тикет 07: проверка того, как КАЖДЫЙ движок трактует client-side поля reasoning.
# Прямые curl-пробы через :8080 (ответы стриминговые, reasoning берём из
# reasoning_content). Запускать при уже загруженном движке, чтобы не мешала
# loading-плашка llama-swap.
#
#   ./probe-reasoning.sh <tag>
set -u
TAG=${1:?usage: probe-reasoning.sh <tag>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/$TAG"
mkdir -p "$OUT"
URL=http://127.0.0.1:8080/v1/chat/completions
PROMPT='Compute 419 multiplied by 137 step by step, then reply with only the number.'

probe() {
  local id=$1 body=$2
  echo "  - $id"
  curl -s -N -X POST "$URL" -H 'Content-Type: application/json' -d "$body" \
    > "$OUT/$id.sse" 2> "$OUT/$id.err"
  python3 - "$OUT/$id.sse" "$id" <<'PY'
import json,sys
raw=open(sys.argv[1]).read()
if raw.lstrip().startswith("{") and '"error"' in raw:
    print("      ERROR:", raw.strip()[:220]); raise SystemExit
r="".join(d.get("reasoning_content") or d.get("reasoning") or ""
          for line in raw.splitlines() if line.startswith("data: ") and line[6:].strip() not in ("","[DONE]")
          for c in (json.loads(line[6:]).get("choices") or []) for d in [(c.get("delta") or {})])
txt="".join(d.get("content") or ""
          for line in raw.splitlines() if line.startswith("data: ") and line[6:].strip() not in ("","[DONE]")
          for c in (json.loads(line[6:]).get("choices") or []) for d in [(c.get("delta") or {})])
print(f"      reasoning: {len(r):>5} chars | content: {txt[:60]!r}")
PY
}

MA='[{"role":"user","content":"'$PROMPT'"}]'
probe 01-bare                 "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true}"
probe 02-effort-none          "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"reasoning_effort\":\"none\"}"
probe 03-effort-low           "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"reasoning_effort\":\"low\"}"
probe 04-effort-xhigh         "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"reasoning_effort\":\"xhigh\"}"
probe 05-kwargs-enable-false  "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"chat_template_kwargs\":{\"enable_thinking\":false}}"
probe 06-kwargs-effort-none   "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"chat_template_kwargs\":{\"reasoning_effort\":\"none\"}}"
probe 07-effort-invalid       "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"reasoning_effort\":\"banana\"}"
probe 08-kwargs-effort-low    "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"chat_template_kwargs\":{\"reasoning_effort\":\"low\"}}"
probe 09-kwargs-effort-xhigh  "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"chat_template_kwargs\":{\"reasoning_effort\":\"xhigh\"}}"
probe 10-kwargs-both          "{\"model\":\"qwen3.8-27b\",\"messages\":$MA,\"max_tokens\":300,\"stream\":true,\"reasoning_effort\":\"low\",\"chat_template_kwargs\":{\"enable_thinking\":true}}"
