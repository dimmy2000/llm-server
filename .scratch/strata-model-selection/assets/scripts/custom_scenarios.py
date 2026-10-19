#!/opt/strata/.venv/bin/python
"""Кастомные сценарии протокола матрицы (issues/06): потолочный пробой и многотуровый чат.

Общее: streaming-запрос к /v1/chat/completions, разбор usage+timings как в strata_bench
(prompt tokens, reused=cache_n, read=prompt_n, prompt/decode tok/s от движка),
число prompt-токенов строится точно через пак-токенизатор (Tokenzier.from_gguf),
watch-замер минимумов VRAM обеих карт в потоке (2 с), thinking off, temperature 0.

Usage:
  custom_scenarios.py ceiling --url http://127.0.0.1:8081 --gguf <native.gguf> \
      --max-context 131072 --repeats 3 --out ceiling.json
  custom_scenarios.py multiturn --url http://127.0.0.1:8081 --gguf <native.gguf> \
      --max-context 131072 --turns 15 --out multiturn.json [--turn-tokens 6000]
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, "/opt/strata/tools")
import strata_tokenizer as ST  # noqa: E402

VOCAB = ("river stone market lantern copper winter garden signal harbor needle orbit velvet canyon ember "
         "ledger quartz meadow anchor violet thunder guerra моста освещение зимнего сада приборный "
         "чертёж фасад синхрофазотрон обновление сборка тестирование окружение развертка").split()


def encode_text(tok: ST.Tokenizer, text: str) -> int:
    return len(tok.encode(text))


def build_prompt(tok: ST.Tokenizer, target_tokens: int, corner: str) -> str:
    """Filler-текст, доподлинно означающий target_tokens (подгон повторным измерением кодировки)."""
    rng = random.Random(11)
    base = 512
    words: list[str] = [rng.choice(VOCAB) for _ in range(base)]
    text = " ".join(words)
    n = encode_text(tok, text + corner)
    # умножаем грубым равномерным додаванием, затем подрезаем
    factor = max(1, target_tokens // max(1, n))
    words = words * factor + [rng.choice(VOCAB) for _ in range(base)]
    lo, hi = 0, len(words)                      # бинарный поиск границей по токенам
    text_best = None
    while lo <= hi:
        mid = (lo + hi) // 2
        t = " ".join(words[:mid])
        if encode_text(tok, t + corner) <= target_tokens:
            text_best, lo = t, mid + 1
        else:
            hi = mid - 1
    if text_best is None:
        raise SystemExit("не удалось построить промпт заданной длины")
    return text_best + corner


def watch_gpu(interval: float, stop: threading.Event, out: dict) -> None:
    mins = {0: None, 1: None}
    while not stop.is_set():
        try:
            r = subprocess.run(["nvidia-smi", "--query-gpu=index,memory.free",
                                "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10)
            for line in r.stdout.strip().splitlines():
                idx, free = [x.strip() for x in line.split(",")]
                f = int(free)
                mins[int(idx)] = f if mins[int(idx)] is None else min(mins[int(idx)], f)
        except Exception:
            pass
        stop.wait(interval)
    out["vram_min_mib"] = mins


class Watcher:
    def __init__(self) -> None:
        self.stop = threading.Event()
        self.result = {}

    def __enter__(self) -> "Watcher":
        threading.Thread(target=watch_gpu, args=(2.0, self.stop, self.result), daemon=True).start()
        return self

    def __exit__(self, *a) -> None:
        self.stop.set()
        time.sleep(0.3)


def stream_chat(url: str, messages: list[dict], max_tokens: int) -> dict:
    body = json.dumps({"messages": messages, "max_tokens": max_tokens, "temperature": 0,
                       "stream": True, "stream_options": {"include_usage": True},
                       "chat_template_kwargs": {"enable_thinking": False}}).encode()
    req = urllib.request.Request(f"{url}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    first = usage = timings = None
    gen = 0
    try:
        with urllib.request.urlopen(req, timeout=3600) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                j = json.loads(payload)
                choice = (j.get("choices") or [{}])[0].get("delta") or {}
                if choice.get("content"):
                    if first is None:
                        first = time.perf_counter() - t0
                    gen += 1
                if j.get("usage"):
                    usage = j["usage"]
                if j.get("timings"):
                    timings = j["timings"]
    except urllib.error.HTTPError as e:
        return {"ok": False, "err": f"HTTP {e.code}: {e.read()[:300]!r}"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "err": repr(e)[:300]}
    total = time.perf_counter() - t0
    u, t = usage or {}, timings or {}
    cached = (u.get("prompt_tokens_details") or {}).get("cached_tokens")
    if cached is None:
        cached = t.get("cache_n")
    return {"ok": True, "ttft_s": None if first is None else round(first, 3),
            "total_s": round(total, 3), "prompt_tokens": u.get("prompt_tokens") or t.get("prompt_n"),
            "reused_tokens": cached, "read_tokens": t.get("prompt_n"),
            "generated_tokens": u.get("completion_tokens") or gen,
            "decode_tps": round((gen - 1) / (total - first), 1) if first and gen > 1 and total > first else None,
            "engine_decode_tps": t.get("predicted_per_second"), "engine_prompt_tps": t.get("prompt_per_second"),
            "prompt_ms": t.get("prompt_ms"), "drafts_offered": t.get("draft_n"),
            "drafts_accepted": t.get("draft_n_accepted")}


def digest_median(rows: list[dict]) -> dict:
    def med(k: str):
        v = [r[k] for r in rows if isinstance(r.get(k), (int, float))]
        return {"median": round(statistics.median(v), 3), "min": round(min(v), 2), "max": round(max(v), 2)} if v else None
    return {"ttft_s": med("ttft_s"), "decode_tps": med("decode_tps"), "engine_prompt_tps": med("engine_prompt_tps"),
            "engine_decode_tps": med("engine_decode_tps"), "total_s": med("total_s"),
            "prompt_tokens": med("prompt_tokens"), "generated_tokens": med("generated_tokens")}


def tok_for(gguf: str) -> ST.Tokenizer:
    return ST.Tokenizer.from_gguf(gguf)


# ----------------------------------------------------------------------------- потолочный пробой
def cmd_ceiling(a: argparse.Namespace) -> None:
    tok = tok_for(a.gguf)
    target = int(a.max_context * a.ratio)
    prompt = build_prompt(tok, target, "\n\nКакие слова встречались в списке? Перечисли десять подряд.")
    n_tok = encode_text(tok, prompt)
    print(f"prompt ходит {n_tok} токенов ({100.0 * n_tok / a.max_context:.1f}% потолка), генерация до {a.gen}")
    rows, fails = [], []
    for i in range(a.repeats):
        print(f"--- повтор {i + 1}/{a.repeats}")
        with Watcher() as w:
            r = stream_chat(a.url, [{"role": "user", "content": prompt}], a.gen)
        w_res = w.result.get("vram_min_mib")
        r["vram_min_mib"] = w_res
        if not r["ok"]:
            fails.append(r["err"])
            print(f"FAIL: {r['err']}")
        else:
            print(f"ttft {r['ttft_s']} s, decode {r['decode_tps']} tok/s (engine {r['engine_decode_tps']}), "
                  f"prompt {r['prompt_tokens']} tok, gen {r['generated_tokens']}, "
                  f"prefill {r['engine_prompt_tps']} tok/s, VRAM min {w_res}")
        rows.append(r)
        time.sleep(2)
    good = [r for r in rows if r["ok"]]
    out = {"scenario": "ceiling", "max_context": a.max_context, "target_ratio": a.ratio,
           "prompt_tokens_built": n_tok, "gen_cap": a.gen, "repeats": rows,
           "median": digest_median(good) if good else None,
           "failures": fails,
           "pass": len(good) >= a.repeats - (1 if a.repeats >= 2 else 0) and
                    any((r.get("decode_tps") or 0) > 20 for r in good)}
    Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"pass={out['pass']} -> {a.out}")
    return 0


# ----------------------------------------------------------------------------- многотуровый чат
def cmd_multiturn(a: argparse.Namespace) -> None:
    tok = tok_for(a.gguf)
    sys = ("Ты ассистент в длинном рабочем чате. Отвечай кратко (2-4 предложения), "
           "сохраняя историю: о чём договорились ранее.")
    history = [{"role": "system", "content": sys}]
    turns = []
    rng = random.Random(int(time.time()) & 0xFFFF)
    total_stop = None
    for i in range(a.turns):
        growth = a.turn_tokens
        topic = build_prompt(tok, growth, f"\n\n(тур {i + 1}) Продолжаем: кратко подтверди, что история учтена и ответь, что делаем дальше.")
        n = encode_text(tok, topic)
        history.append({"role": "user", "content": topic})
        with Watcher() as w:
            r = stream_chat(a.url, history, 600)
        r["turn"] = i + 1
        r["turn_fill_tokens"] = n
        r["vram_min_mib"] = w.result.get("vram_min_mib")
        if not r["ok"]:
            print(f"туp {i + 1}: FAIL {r['err']}")
            turns.append(r)
            total_stop = "fail"
            break
        answer_len = int(r.get("generated_tokens") or 0)
        hist_tokens = r["prompt_tokens"] + answer_len
        print(f"туp {i + 1}: prompt {r['prompt_tokens']} (reused {r['reused_tokens']}, read {r['read_tokens']}), "
              f"ttft {r['ttft_s']} s, decode {r['decode_tps']} tok/s, VRAM min {r['vram_min_mib']}")
        turns.append(r)
        hist = {"role": "assistant", "content": "." * max(8, answer_len)}
        history.append(hist)
        if r["prompt_tokens"] and r["prompt_tokens"] >= int(a.max_context * 0.97):
            total_stop = "context_ceiling"
            break
    out = {"scenario": "multiturn", "turns_target": a.turns, "turn_fill_tokens": a.turn_tokens,
           "turns": turns, "stop_reason": total_stop or "turns_exhausted",
           "vram_min_all": min((r["vram_min_mib"][1] or 1 << 30) for r in turns if isinstance(r.get("vram_min_mib"), dict)),
           "pass": all(r.get("ok") for r in turns) and len(turns) >= a.turns - 2}
    Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"pass={out['pass']} stop={out['stop_reason']} -> {a.out}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", default="http://127.0.0.1:8081")
    p.add_argument("--gguf", default=None)
    p.add_argument("--out", default=None)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("ceiling")
    c.add_argument("--url", default="http://127.0.0.1:8081")
    c.add_argument("--gguf", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--max-context", type=int, required=True)
    c.add_argument("--ratio", type=float, default=0.90)
    c.add_argument("--gen", type=int, default=4096)
    c.add_argument("--repeats", type=int, default=3)
    m = sub.add_parser("multiturn")
    m.add_argument("--url", default="http://127.0.0.1:8081")
    m.add_argument("--gguf", required=True)
    m.add_argument("--out", required=True)
    m.add_argument("--max-context", type=int, required=True)
    m.add_argument("--turns", type=int, default=15)
    m.add_argument("--turn-tokens", type=int, default=6000)
    a = p.parse_args()
    return {"ceiling": cmd_ceiling, "multiturn": cmd_multiturn}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
