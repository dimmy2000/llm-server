#!/usr/bin/env python3
"""Тикет 15: как top-level reasoning_effort="none" влияет на РЕНДЕР промпта
у llama.cpp b10438 (расширенная сетка поверх пробы тикета 11).

Бьём напрямую в llama-server (:5800 внутри контейнера, минуя llama-swap) в
POST /apply-template — он возвращает ровно тот промпт, который собран
шаблоном. Маркеры: "Reasoning effort is set to" — блок effort инструкции;
"<think>\\n\\n</think>" — пустой think (thinking выключен шаблоном);
"<think>\\n" в конце — generation prompt с открытым thinking.

    python3 apply-template-probe.py
"""
import json
import subprocess

URL = "http://127.0.0.1:5800/apply-template"
MESSAGES = [{"role": "user", "content": "Compute 419 multiplied by 137."}]

CASES = [
    ("bare", {}),
    ("effort-none", {"reasoning_effort": "none"}),
    ("effort-none+kwargs-true", {"reasoning_effort": "none",
                                 "chat_template_kwargs": {"enable_thinking": True}}),
    ("effort-none+kwargs-false", {"reasoning_effort": "none",
                                  "chat_template_kwargs": {"enable_thinking": False}}),
    ("kwargs-false", {"chat_template_kwargs": {"enable_thinking": False}}),
    ("effort-low", {"reasoning_effort": "low"}),
    ("effort-xhigh", {"reasoning_effort": "xhigh"}),
    ("kwargs-effort-low", {"chat_template_kwargs": {"reasoning_effort": "low"}}),
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


def tail(prompt: str) -> str:
    return prompt.split("<|im_start|>assistant\n", 1)[-1][:80]


print("# POST /apply-template на llama-server b10438 (напрямую, минуя llama-swap)")
print(f"# messages = {json.dumps(MESSAGES, ensure_ascii=False)}\n")
base = None
for name, extra in CASES:
    resp = render(extra)
    print(f"== {name}: {json.dumps(extra, ensure_ascii=False)}")
    if "error" in resp:
        print("   ERROR:", json.dumps(resp["error"], ensure_ascii=False)[:200])
        continue
    prompt = resp.get("prompt", "")
    if base is None:
        base = prompt
    print(f"   len {len(prompt)} (bare={len(base)}, delta {len(prompt)-len(base):+d})")
    print("   effort line:", "ДА" if "Reasoning effort is set to" in prompt else "НЕТ")
    print("   gen tail:", repr(tail(prompt)))
    print()
    with open(f"render-{name}.txt", "w") as f:
        f.write(prompt)
