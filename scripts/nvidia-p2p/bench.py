#!/usr/bin/env python3
"""Single-request streaming bench for the OpenAI-compatible endpoint (:8080).

Measures TTFT (first content chunk), wall total, and passes through the
backend's final-chunk `usage` and `timings` objects (llama.cpp and NInfer
both report prefill/decode tok/s there; NInfer also draft_n / draft_n_accepted).

Usage:
  bench.py --model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4 \
           --out results-ninfer-prefill-90k.json [--nonce auto] [--label name]
  bench.py --model qwen3.8-27b --prompt "Write a long story..." \
           --max-tokens 600 --out results-ninfer-decode.json

A random nonce is prepended to the user message by default so every run is a
cold prefill (device-state/KV prefix cache would otherwise replay the prompt).
"""
import argparse
import http.client
import json
import secrets
import sys
import time


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt", default=None, help="inline prompt text")
    ap.add_argument("--prompt-file", default=None, help="read prompt from file")
    ap.add_argument("--system", default=None)
    ap.add_argument("--max-tokens", type=int, default=4)
    ap.add_argument("--nonce", default="auto",
                    help="'auto' = random nonce, 'none' = no nonce, or a literal")
    ap.add_argument("--label", default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    content = args.prompt if args.prompt else (
        open(args.prompt_file, encoding="utf-8").read() if args.prompt_file else "")
    if not content:
        ap.error("need --prompt or --prompt-file")
    if args.nonce == "auto":
        content = f"Bench session nonce {secrets.token_hex(8)}.\n\n{content}"
    elif args.nonce != "none":
        content = f"Bench session nonce {args.nonce}.\n\n{content}"

    messages = []
    if args.system:
        messages.append({"role": "system", "content": args.system})
    messages.append({"role": "user", "content": content})

    body = json.dumps({
        "model": args.model,
        "messages": messages,
        "max_tokens": args.max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
    })

    conn = http.client.HTTPConnection(args.host, args.port, timeout=7200)
    t0 = time.perf_counter()
    conn.request("POST", "/v1/chat/completions", body=body,
                 headers={"Content-Type": "application/json"})
    resp = conn.getresponse()
    if resp.status != 200:
        err = resp.read().decode(errors="replace")
        json.dump({"error": {"status": resp.status, "body": err},
                   "label": args.label}, open(args.out, "w"), indent=2)
        print(f"HTTP {resp.status}: {err[:300]}", file=sys.stderr)
        return 1

    ttft = None
    t_last = None
    content_chars = 0
    content_chunks = 0
    usage = None
    timings = None
    finish_reason = None
    text_parts = []

    while True:
        line = resp.readline()
        if not line:
            break
        line = line.strip()
        if not line.startswith(b"data:"):
            continue
        payload = line[5:].strip()
        if payload == b"[DONE]":
            break
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        now = time.perf_counter()
        if obj.get("usage"):
            usage = obj["usage"]
        if obj.get("timings"):
            timings = obj["timings"]
        for ch in obj.get("choices", []):
            if ch.get("finish_reason"):
                finish_reason = ch["finish_reason"]
            delta = (ch.get("delta") or {}).get("content") or ""
            if delta:
                if ttft is None:
                    ttft = now - t0
                content_chars += len(delta)
                content_chunks += 1
                t_last = now
                text_parts.append(delta)
    conn.close()
    total = time.perf_counter() - t0

    completion_tokens = usage.get("completion_tokens") if usage else None
    decode_span = (t_last - ttft) if (ttft and t_last) else None
    result = {
        "label": args.label,
        "model": args.model,
        "max_tokens": args.max_tokens,
        "ttft_s": ttft,
        "total_s": total,
        "decode_span_s": decode_span,
        "content_chars": content_chars,
        "content_chunks": content_chunks,
        "completion_tokens": completion_tokens,
        "decode_tok_s_chunks": (content_chunks / decode_span
                                if decode_span and content_chunks else None),
        "decode_tok_s_usage": (completion_tokens / decode_span
                               if decode_span and completion_tokens else None),
        "usage": usage,
        "timings": timings,
        "finish_reason": finish_reason,
        "text": "".join(text_parts),
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    usage_s = ""
    if usage:
        usage_s = (f" prompt={usage.get('prompt_tokens')}"
                   f" completion={completion_tokens}")
    print(f"{args.label or args.model}: ttft={ttft and round(ttft, 2)}s"
          f" total={round(total, 2)}s{usage_s}"
          f" finish={finish_reason}")
    if timings:
        t = timings
        print(f"  engine: prompt_n={t.get('prompt_n')}"
              f" prefill={t.get('prompt_per_second')} tok/s"
              f" decode={t.get('predicted_per_second')} tok/s"
              f" draft={t.get('draft_n')}/{t.get('draft_n_accepted')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
