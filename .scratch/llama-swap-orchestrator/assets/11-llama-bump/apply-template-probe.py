#!/usr/bin/env python3
"""Тикет 11: как поля клиента влияют на РЕНДЕР промпта у llama.cpp b10438.

Бьём напрямую в llama-server (:5800 внутри контейнера, минуя llama-swap) в
POST /apply-template — он возвращает ровно тот промпт, который собран шаблоном.
Так видно, доходит ли поле клиента до шаблона, не гадая по ответу модели.

    python3 apply-template-probe.py
"""
import json
import subprocess

URL = "http://127.0.0.1:5800/apply-template"
MESSAGES = [{"role": "user", "content": "Compute 419 multiplied by 137."}]

CASES = [
    ("bare", {}),
    ("effort-none", {"reasoning_effort": "none"}),
    ("effort-low", {"reasoning_effort": "low"}),
    ("effort-medium", {"reasoning_effort": "medium"}),
    ("effort-xhigh", {"reasoning_effort": "xhigh"}),
    ("effort-banana", {"reasoning_effort": "banana"}),
    ("kwargs-enable-false", {"chat_template_kwargs": {"enable_thinking": False}}),
    ("kwargs-effort-low", {"chat_template_kwargs": {"reasoning_effort": "low"}}),
    ("none+kwargs-false", {"reasoning_effort": "none",
                           "chat_template_kwargs": {"enable_thinking": False}}),
]


def render(body: dict) -> dict:
    payload = json.dumps(dict(messages=MESSAGES, **body))
    out = subprocess.run(
        ["docker", "exec", "-i", "llama-swap", "curl", "-s", URL,
         "-H", "Content-Type: application/json", "--data-binary", "@-"],
        input=payload, capture_output=True, text=True, check=False).stdout
    try:
        return json.loads(out)
    except Exception:
        return {"error": {"message": out[:200]}}


print("# POST /apply-template на llama-server b10438 (напрямую, минуя llama-swap)")
print(f"# messages = {json.dumps(MESSAGES, ensure_ascii=False)}\n")
base_len = None
for name, extra in CASES:
    resp = render(extra)
    print(f"== {name}: {json.dumps(extra, ensure_ascii=False)}")
    if "error" in resp:
        print("   ERROR:", json.dumps(resp["error"], ensure_ascii=False)[:200])
        continue
    prompt = resp.get("prompt", "")
    if base_len is None:
        base_len = len(prompt)
    print(f"   prompt len {len(prompt)} (bare={base_len}, delta {len(prompt)-base_len:+d})")
    print("   first block:", repr(prompt.split("<|im_end|>")[0][:230]))
    print()
