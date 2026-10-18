#!/usr/bin/env python3
"""Сводка tap-логов тикета 14: какое тело ушло, что вернулось.

Для каждой пары *.req.txt / *.resp.txt печатает: chat_template_kwargs,
наличие tools, суммарную длину reasoning_content и content из SSE-ответа.
Запросы title-generator (системный промпт не начинается с 'You are an AI
agent') помечены, чтобы не путать с шагом агента.
"""
import glob
import json
import os
import sys

log_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "tap")

for req_path in sorted(glob.glob(os.path.join(log_dir, "*.req.txt"))):
    base = req_path[: -len(".req.txt")]
    resp_path = base + ".resp.txt"
    if not os.path.exists(resp_path):
        continue
    raw = open(req_path, encoding="utf-8").read()
    header, _, body = raw.partition("\n\n")
    try:
        b = json.loads(body)
    except Exception:
        print(f"{os.path.basename(base)}: not JSON body")
        continue
    is_agent = False
    for m in b.get("messages", []):
        if m.get("role") == "system" and (m.get("content") or "").startswith("You are an AI agent"):
            is_agent = True
            break
    meta = {}
    if os.path.exists(base + ".meta.txt"):
        for kv in open(base + ".meta.txt").read().split():
            if "=" in kv:
                k, v = kv.split("=", 1)
                meta[k] = v
    reas = content = 0
    status = meta.get("status", "?")
    for line in open(resp_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if payload == "[DONE]":
            break
        try:
            d = json.loads(payload)
        except Exception:
            continue
        for ch in d.get("choices", []):
            delta = ch.get("delta") or {}
            reas += len(delta.get("reasoning_content") or "")
            content += len(delta.get("content") or "")
    kind = "AGENT" if is_agent else "title/other"
    print(
        f"{os.path.basename(base)} [{kind}] status={status} "
        f"kwargs={json.dumps(b.get('chat_template_kwargs'), ensure_ascii=False)} "
        f"top_level_reasoning_effort={b.get('reasoning_effort')!r} "
        f"tools={'yes' if b.get('tools') else 'no'} "
        f"reasoning_chars={reas} content_chars={content}"
    )
