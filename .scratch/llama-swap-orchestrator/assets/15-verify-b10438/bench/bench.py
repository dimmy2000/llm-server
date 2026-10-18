#!/usr/bin/env python3
"""A/B prefill/decode/spul-accept: llama.cpp b10068 vs b10438 на одинаковых флагах.

Методика — docs/research/0005 (тот же протокол OAI-запроса и метрики
print_timing/timings), адаптирована под текущий конфиг router (единый
endpoint, --spec-type draft-mtp,ngram-mod):

- POST /v1/chat/completions, model qwen3.8-27b, stream false;
- sampling клиента как в 0005: temperature 0.7, top_p 0.8, top_k 20, min_p 0,
  presence_penalty 1.5, repeat_penalty 1.05; reasoning off
  (chat_template_kwargs.enable_thinking=false);
- промпт — уникальный связный текст на каждый замер (без переиспользования
  KV-префикса), фактические токены — из ответа timings.prompt_n;
- метрики — timings из ответа (prompt_per_second, predicted_per_second,
  draft_n/draft_n_accepted) + print_timing из docker-логов как перекрёстная
  проверка.

  ./bench.py --label b10438 --out /path/out [--cases p16k,p60k,...]
"""

import argparse
import json
import os
import random
import time
import urllib.request

URL = "http://127.0.0.1:8080/v1/chat/completions"

WORDS = (
    "harbor lantern meadow compass ember thistle quarry mirage beacon cinder "
    "orchard tide voxel glimmer fathom parchment zephyr cobble index mosaic "
    "spectrum kestrel foundry lattice trellis amber silt monsoon cartograph "
    "fresco basalt pollen cipher anvil drizzle hollow prism mariner mosaic"
).split()

TOPICS = (
    "the maintenance log of a coastal railway",
    "a field guide to uncommon cloud shapes",
    "the minutes of a guild of clockmakers",
    "an inventory of a seed library",
    "letters between two lighthouse keepers",
    "a catalogue of borrowed instruments",
    "the diary of a night-shift baker",
    "notes from a cartography expedition",
)


def make_text(n_words: int, rng: random.Random) -> str:
    """Связный, но каждый раз новый текст; ~1.3 токена на слово."""
    parts = []
    while sum(len(p.split()) for p in parts) < n_words:
        topic = rng.choice(TOPICS)
        sent = [f"Entry {rng.randint(1000, 9999)} of {topic}"]
        for _ in range(rng.randint(4, 9)):
            sent.append(
                " ".join(rng.choice(WORDS) for _ in range(rng.randint(3, 9)))
                + f" ({rng.randint(10, 9999)})."
            )
        parts.append(" ".join(sent))
    return "\n\n".join(parts)


def request(prompt: str, max_tokens: int, temperature: float) -> dict:
    body = {
        "model": "qwen3.8-27b",
        "stream": False,
        "messages": [{"role": "user", "content": prompt}],
        "chat_template_kwargs": {"enable_thinking": False},
        "temperature": temperature,
        "top_p": 0.8,
        "top_k": 20,
        "min_p": 0.0,
        "presence_penalty": 1.5,
        "repeat_penalty": 1.05,
        "max_tokens": max_tokens,
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as resp:
        data = json.loads(resp.read())
    return {"wall_s": round(time.time() - t0, 2), "response": data}


# target_prompt_tokens -> (n_words, max_tokens, temperature, task)
CASES = {
    "tiny-temp0": (60, 128, 0.0, "repeat"),
    "p16k-gen1024": (12500, 1024, 0.7, "story"),
    "p16k-gen1024-rep": (12500, 1024, 0.7, "story"),
    "p60k-gen1024": (46500, 1024, 0.7, "story"),
    "p100k-gen256": (77000, 256, 0.7, "story"),
}

TASK_PROMPTS = {
    "story": (
        "Write a long, detailed and varied story inspired by the text above. "
        "Keep writing for the whole response."
    ),
    "repeat": "Count from 1 to 50, one number per line, then stop.",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cases", default=",".join(CASES))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(f"{args.label}-{time.time()}")

    summary_path = os.path.join(args.out, f"summary-{args.label}.jsonl")
    for case in args.cases.split(","):
        n_words, max_tokens, temp, task = CASES[case]
        prompt = make_text(n_words, rng) + "\n\n" + TASK_PROMPTS[task]
        print(f"== {args.label}/{case}: ~{len(prompt)} chars, max_tokens {max_tokens}, temp {temp}", flush=True)
        try:
            res = request(prompt, max_tokens, temp)
        except Exception as exc:  # noqa: BLE001
            print(f"   ERROR: {exc!r}", flush=True)
            with open(summary_path, "a") as f:
                f.write(json.dumps({"label": args.label, "case": case, "error": repr(exc)}) + "\n")
            continue

        resp = res["response"]
        timings = resp.get("timings") or {}
        row = {
            "label": args.label,
            "case": case,
            "wall_s": res["wall_s"],
            "system_fingerprint": resp.get("system_fingerprint"),
            "prompt_n": timings.get("prompt_n"),
            "prompt_per_second": timings.get("prompt_per_second"),
            "predicted_n": timings.get("predicted_n"),
            "predicted_per_second": timings.get("predicted_per_second"),
            "draft_n": timings.get("draft_n"),
            "draft_n_accepted": timings.get("draft_n_accepted"),
            "accept_rate": (
                round(timings["draft_n_accepted"] / timings["draft_n"], 4)
                if timings.get("draft_n")
                else None
            ),
            "stop_reason": (resp.get("choices") or [{}])[0].get("finish_reason"),
        }
        with open(summary_path, "a") as f:
            f.write(json.dumps(row) + "\n")
        print("   " + json.dumps(row, ensure_ascii=False), flush=True)
        with open(os.path.join(args.out, f"{args.label}-{case}.resp.json"), "w") as f:
            json.dump(resp, f, ensure_ascii=False, indent=2)
        with open(os.path.join(args.out, f"{args.label}-{case}.prompt.tail.txt"), "w") as f:
            f.write(prompt[-800:])
        time.sleep(3)  # дать --cache-idle-slots сериализовать KV до следующего замера


if __name__ == "__main__":
    main()
