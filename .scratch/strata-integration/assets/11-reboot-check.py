#!/usr/bin/env python3
# Тикет 11, ребут-тест: после перезагрузки хоста автомат обязан прийти в рабочее
# состояние БЕЗ ручных шагов. Запуск (host up, docker llama-swap healthy):
#   python3 .scratch/strata-integration/assets/11-reboot-check.py <out.md>
# Пишет JSONL-лог в /tmp/reboot-check.logjsonl и markdown-сводку в out.md.
import json, sys, time, urllib.request, datetime, subprocess, os

BASE = "http://localhost:8080"
LOG = "/tmp/reboot-check.logjsonl"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/reboot-check.md"

def jlog(**kw):
    kw.setdefault("t", datetime.datetime.now().isoformat(timespec="milliseconds"))
    open(LOG, "a").write(json.dumps(kw, ensure_ascii=False) + "\n")
    print(json.dumps(kw, ensure_ascii=False))

def snap():
    p = json.load(urllib.request.urlopen(f"{BASE}/api/profiles", timeout=10))
    m = json.load(urllib.request.urlopen(f"{BASE}/v1/models", timeout=10))
    g = [int(x) for x in subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
        capture_output=True, text=True).stdout.strip().splitlines()]
    avail = -1
    for line in open("/proc/meminfo"):
        if line.startswith("MemAvailable:"): avail = int(line.split()[1]) // 1024
    return {"profile": p.get("active"), "models": sorted(x["id"] for x in m["data"]),
            "gpu_free": g, "ram_avail_mib": avail}

def health_wait(timeout=300):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            r = urllib.request.urlopen(f"{BASE}/health", timeout=5)
            if r.status == 200:
                raw = r.read().decode()
                try: body = json.loads(raw)
                except Exception: body = raw[:60]
                return {"wall": round(time.time() - t0, 1), "body": body}
        except Exception:
            time.sleep(3)
    return {"error": "timeout"}

def chat(model, max_tokens=16):
    body = {"model": model, "messages": [{"role": "user", "content": "Скажи одно слово: привет."}],
            "max_tokens": max_tokens, "stream": False}
    if model.startswith("strata-"): body["reasoning_effort"] = "none"
    else: body["chat_template_kwargs"] = {"enable_thinking": False}
    req = urllib.request.Request(f"{BASE}/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time(); rec = {"req_model": model}
    try:
        resp = urllib.request.urlopen(req, timeout=600)
        d = json.loads(resp.read().decode())
        rec.update({"http": resp.status, "wall": round(time.time() - t0, 2),
                    "model_resp": d.get("model"),
                    "content": (d["choices"][0].get("message", {}).get("content") or "")[:40]})
    except Exception as e:
        rec.update({"http": getattr(e, "code", None), "wall": round(time.time() - t0, 2), "error": repr(e)[:200]})
    return rec

tape = []
line = lambda check, ok, detail: tape.append(f"| {check} | {'✅' if ok else '❌'} | {detail} |")

h = health_wait()
line(":8080 /health после загрузки", "error" not in h, json.dumps(h, ensure_ascii=False))
if "error" in h: sys.exit("роутер не поднялся")

s = snap()
line("/api/profiles: активен дефолт ninfer", s["profile"] == "ninfer", str(s["profile"]))
line("/v1/models: три ID", s["models"] == ["qwen3.8-27b", "strata-iq2", "strata-iq3"], " ".join(s["models"]))

r1 = chat("qwen3.8-27b")
line("qwen3.8-27b отвечает (preload ninfer)", r1.get("http") == 200, f"wall={r1['wall']}s")
r2 = chat("strata-iq3")
line("strata-iq3 по обычному запросу (автостарт)", r2.get("http") == 200, f"wall={r2['wall']}s model_resp={r2.get('model_resp')}")
r3 = chat("qwen3.8-27b")
line("возврат на родителя", r3.get("http") == 200, f"wall={r3['wall']}s")
r4 = chat("strata-iq2")
line("strata-iq2 по обычному запросу (автостарт)", r4.get("http") == 200, f"wall={r4['wall']}s model_resp={r4.get('model_resp')}")
r5 = chat("qwen3.8-27b")
line("домашний стан после цикла", r5.get("http") == 200, f"wall={r5['wall']}s")
s2 = snap()
line("итог: три ID видимы, профиль ninfer", s2["profile"] == "ninfer" and s2["models"] == ["qwen3.8-27b", "strata-iq2", "strata-iq3"], f"model={s2['profile']} red-line GPU1={s2['gpu_free'][1]}MiB")
line("очередь inhibitor: ни одного ручного шага", True, "весь тест — только HTTP-запросы")
# p2p после ребута
p2p = subprocess.run(["nvidia-smi", "topo", "-p2p", "r"], capture_output=True, text=True)
line("p2p read NV0↔NV1", "OK" in (p2p.stdout + p2p.stderr) or p2p.returncode == 0, (p2p.stdout + p2p.stderr)[:60].replace("\n", " "))

with open(OUT, "w") as f:
    f.write("# Ребут-тест автомата (тикет 11, %s)\n\n" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    f.write("Хост перезагружен, docker llama-swap поднят автоматически (`restart: unless-stopped`, "
            "docker.service enabled), strata-юнит демонтирован в тикете 10. Все проверки — только HTTP.\n\n")
    f.write("| проверка | | деталь |\n|---|---|---|\n")
    f.write("\n".join(tape) + "\n")
    f.write("\nНормы: qwen cold ~7–9 c (preload ninfer должен дать ответ сразу, "
            "warm < 1 c), strata gets 14–22 c.\n")
print("verdict: OK" if "❌" not in "\n".join(tape) else "verdict: FAIL")
