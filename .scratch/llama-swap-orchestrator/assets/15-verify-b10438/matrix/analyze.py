#!/usr/bin/env python3
"""Сводка по логам tap-proxy: что ушло в теле запроса и что вернул сервер.

Читает каталог с парами `NNN-post-v1_chat_completions.{req,resp,meta}.txt` и
печатает по каждому запросу:
  - model, reasoning_effort, chat_template_kwargs, есть ли поле tools
    (и сколько), tools/tool_choice, sampling-поля тела;
  - ответ: непустой ли `reasoning_content`, имена вызванных инструментов,
    финальный текст;
  - длительность.
"""

import json
import os
import re
import sys


def summarize_request(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    body = raw.split("\n\n", 1)[1] if "\n\n" in raw else ""
    try:
        data = json.loads(body)
    except Exception:
        return None
    out["model"] = data.get("model")
    out["stream"] = data.get("stream")
    out["reasoning_effort"] = data.get("reasoning_effort", "<отсутствует>")
    out["chat_template_kwargs"] = data.get("chat_template_kwargs", "<отсутствует>")
    tools = data.get("tools")
    out["tools_count"] = "нет поля tools" if tools is None else len(tools)
    out["tool_names"] = [t.get("function", {}).get("name") for t in (tools or [])]
    out["tool_choice"] = data.get("tool_choice", "<отсутствует>")
    out["sampling"] = {
        k: data[k]
        for k in (
            "temperature",
            "top_p",
            "top_k",
            "min_p",
            "presence_penalty",
            "frequency_penalty",
            "repetition_penalty",
            "max_tokens",
        )
        if k in data
    }
    out["messages_count"] = len(data.get("messages", []))
    return out


def summarize_response(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.read()
    reasoning_chunks = 0
    reasoning_chars = 0
    tool_calls = []
    text = []
    error = None
    for line in raw.splitlines():
        if not line.startswith("data: "):
            if line.startswith("{"):  # не-стриминговый JSON-ответ
                try:
                    error = error or json.loads(line).get("error")
                except Exception:
                    pass
            continue
        payload = line[6:]
        if payload.strip() == "[DONE]":
            continue
        try:
            evt = json.loads(payload)
        except Exception:
            continue
        for choice in evt.get("choices", []):
            delta = choice.get("delta") or choice.get("message") or {}
            for key in ("reasoning_content", "reasoning"):
                if delta.get(key):
                    reasoning_chunks += 1
                    reasoning_chars += len(delta[key])
            if delta.get("reasoning_details"):
                reasoning_chunks += 1
                for d in delta["reasoning_details"]:
                    reasoning_chars += len(d.get("text", ""))
            for tc in delta.get("tool_calls") or []:
                name = (tc.get("function") or {}).get("name") or tc.get("name")
                if name and (not tool_calls or tool_calls[-1] != name):
                    tool_calls.append(name)
            if delta.get("content"):
                text.append(delta["content"])
    return {
        "reasoning_nonempty": reasoning_chars > 0,
        "reasoning_chars": reasoning_chars,
        "reasoning_chunks": reasoning_chunks,
        "tool_calls": tool_calls,
        "text": "".join(text)[:200],
        "error": error,
    }


def main():
    d = sys.argv[1]
    rows = []
    for name in sorted(os.listdir(d)):
        if not name.endswith(".req.txt"):
            continue
        base = name[: -len(".req.txt")]
        req_path = os.path.join(d, name)
        resp_path = os.path.join(d, base + ".resp.txt")
        meta_path = os.path.join(d, base + ".meta.txt")
        row = {"id": base}
        req = summarize_request(req_path)
        if req is None:
            row["request"] = "не JSON (не chat/completions)"
        else:
            row["request"] = req
        if os.path.exists(resp_path):
            row["response"] = summarize_response(resp_path)
        if os.path.exists(meta_path):
            with open(meta_path, encoding="utf-8") as f:
                row["meta"] = f.read().strip()
        rows.append(row)
    print(json.dumps(rows, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
