## Снапшот-0 (before cycle) 2026-10-19 15:44:16
ninfer
0, 1225 MiB
1, 749 MiB
Mem used 8675 MiB, avail 52182 MiB
страта-процессов нет
inactive
linked
(not enabled — disabled/linked)

## 1) strata-use.sh llama  15:44:24
[strata-use] 15:44:24 переход на родительский 'llama'
[strata-use] 15:44:27 VRAM Strata освобождена: GPU1, free 749 MiBGPU0, free 1225 MiB
[strata-use] 15:44:27 профиль llama-swap: активен 'llama'
[strata-use] 15:44:27 GPU1, free 749 MiBGPU0, free 1225 MiB; RAM available 52167 MiB
[strata-use] 15:44:27 ГОТОВО: 'llama' — движок загрузится на первом запросе к qwen3.8-27b

real	0m2.173s
user	0m0.024s
sys	0m0.118s
rc=0

## 1b) прогрев llama.cpp запросом через :8080  15:44:49
HTTP 200 за 12 с; ответ: Да
VRAM после прогрева: GPU0=993 MiB, GPU1=1541 MiB
RAM: used 6549 MiB, avail 54308 MiB

## 2) strata-use.sh strata-iq3 (с резидентным llama.cpp)  15:45:11
[strata-use] 15:45:11 переход на strata-iq3 (конфиг strata-iq3_xxs.json)
[strata-use] 15:45:13 VRAM Strata освобождена: GPU0 free  MiB (!! НИЖЕ КРАСНОЙ ЛИНИИ 512 MiB) | GPU1 free  MiB (!! НИЖЕ КРАСНОЙ ЛИНИИ 512 MiB)
[strata-use] 15:45:13 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 15:45:13 RAM available 55980 MiB ≥ порог 46000 MiB — родительский стек не держит idle-cache
[strata-use] 15:45:13 симлинк /etc/strata/active.json → /opt/strata/strata-iq3_xxs.json
[strata-use] 15:45:13 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 15:45:33 /health :8081 → model=qwen3.8-flash-next-iq3_xxs loaded=true (за 20 с)
[strata-use] 15:45:33 профиль llama-swap: активен 'strata-iq3'
[strata-use] 15:45:33 GPU0 free  MiB (!! НИЖЕ КРАСНОЙ ЛИНИИ 512 MiB) | GPU1 free  MiB (!! НИЖЕ КРАСНОЙ ЛИНИИ 512 MiB); RAM available 13560 MiB
[strata-use] 15:45:33 ГОТОВО: strata-iq3 — доступен через llama-swap :8080 (публичный ID 'strata-iq3')

real	0m22.676s
user	0m0.066s
sys	0m0.113s
rc=0
## 2b) снапшот после перехода на strata-iq3 15:46:00
[strata-use] 15:46:00 уже активен strata-iq3 (юнит жив, /health совпадает, профиль выставлен) — no-op
[strata-use] 15:46:00 GPU0 free 811 MiB | GPU1 free 1675 MiB; RAM available 13259 MiB
{
  "status": "ok",
  "model": "qwen3.8-flash-next-iq3_xxs",
  "loaded": true,
  "max_context": 131072
}
активный профиль: strata-iq3
438496, /opt/strata/engine/strata, 15018 MiB
7000, /usr/bin/ptyxis, 67 MiB
438496, /opt/strata/engine/strata, 13552 MiB
ready: http://172.17.0.1:8081/v1  (OpenAI: /v1/chat/completions, Anthropic: /v1/messages, context 131072 tokens, images on)
       open http://172.17.0.1:8081/ in a browser to chat; close this window to stop the model
       from other devices: http://192.168.17.99:8081/   (API: http://192.168.17.99:8081/v1)
       WARNING: no API key - anyone on your network can use this model. Add "api_key": "..." to the config (clients send it as their API key; the web page asks for it)
## 2c) Санити-decode через :8080 ID strata-iq3  15:46:12
HTTP 200 за 1 с
model(ответа): qwen3.8-flash-next-iq3_xxs  content: Париж

## 3) strata-use.sh strata-iq2 (рестарт с чужого размера iq3)  15:46:20
[strata-use] 15:46:20 переход на strata-iq2 (конфиг strata-iq2_xs.json)
[strata-use] 15:46:20 останов юнита strata…
[strata-use] 15:46:25 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15315 MiB
[strata-use] 15:46:25 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 15:46:25 RAM available 57421 MiB ≥ порог 36000 MiB — родительский стек не держит idle-cache
[strata-use] 15:46:25 симлинк /etc/strata/active.json → /opt/strata/strata-iq2_xs.json
[strata-use] 15:46:25 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 15:46:39 /health :8081 → model=qwen3.8-flash-next-iq2_xs loaded=true (за 14 с)
[strata-use] 15:46:39 профиль llama-swap: активен 'strata-iq2'
[strata-use] 15:46:39 GPU0 free 2173 MiB | GPU1 free 1705 MiB; RAM available 19036 MiB
[strata-use] 15:46:39 ГОТОВО: strata-iq2 — доступен через llama-swap :8080 (публичный ID 'strata-iq2')

real	0m18.804s
user	0m0.060s
sys	0m0.100s
rc=0
ExecStop/добивание: 0 строк helper'а
## 3b) Санити-decode через :8080 ID strata-iq2  15:46:59
HTTP 200
model(ответа): qwen3.8-flash-next-iq2_xs  content: Мадрид

## 4) strata-use.sh ninfer (из strata-iq2)  15:47:05
[strata-use] 15:47:05 переход на родительский 'ninfer'
[strata-use] 15:47:05 останов юнита strata…
[strata-use] 15:47:08 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15319 MiB
[strata-use] 15:47:08 профиль llama-swap: активен 'ninfer'
[strata-use] 15:47:08 GPU0 free 15919 MiB | GPU1 free 15319 MiB; RAM available 57398 MiB
[strata-use] 15:47:08 ГОТОВО: 'ninfer' — движок загрузится на первом запросе к qwen3.8-27b

real	0m3.166s
user	0m0.024s
sys	0m0.061s
rc=0
## 4b) прогрев ninfer запросом через :8080  15:47:18
HTTP 200 за 8 с; content: Миф
0, 1199 MiB
1, 709 MiB
RAM: used 7260 MiB, avail 53597 MiB

## 5) strata-use.sh off (из ninfer — ожидаем no-op)  15:47:33
[strata-use] 15:47:33 уже off (юнит не запущен, профиль дефолтного 'ninfer') — no-op

real	0m0.031s
user	0m0.011s
sys	0m0.018s
rc=0

## 5b) не-тривиальный off: strata-iq3 → off  15:47:37
[strata-use] 15:47:37 переход на strata-iq3 (конфиг strata-iq3_xxs.json)
[strata-use] 15:47:39 VRAM Strata освобождена: GPU0 free 1199 MiB | GPU1 free 709 MiB
[strata-use] 15:47:40 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 15:47:40 RAM available 57379 MiB ≥ порог 46000 MiB — родительский стек не держит idle-cache
[strata-use] 15:47:40 симлинк /etc/strata/active.json → /opt/strata/strata-iq3_xxs.json
[strata-use] 15:47:40 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 15:47:56 /health :8081 → model=qwen3.8-flash-next-iq3_xxs loaded=true (за 16 с)
[strata-use] 15:47:56 профиль llama-swap: активен 'strata-iq3'
[strata-use] 15:47:56 GPU0 free 811 MiB | GPU1 free 1673 MiB; RAM available 11740 MiB
[strata-use] 15:47:56 ГОТОВО: strata-iq3 — доступен через llama-swap :8080 (публичный ID 'strata-iq3')

real	0m18.549s
user	0m0.053s
sys	0m0.099s

[strata-use] 15:47:56 off: останов юнита, дефолт-профиль 'ninfer' (hooks on_startup), движок не стартую
[strata-use] 15:47:56 останов юнита strata…
[strata-use] 15:47:59 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15317 MiB
[strata-use] 15:47:59 профиль llama-swap: активен 'ninfer'
[strata-use] 15:47:59 GPU0 free 15919 MiB | GPU1 free 15317 MiB
[strata-use] 15:47:59 ГОТОВО: off — доступность родителя через профиль 'ninfer' по первому запросу

real	0m3.170s
user	0m0.026s
sys	0m0.056s
rc=0

## 6) Cold-старт-проверка (имитация после ребута) 15:48:24
is-enabled: linked (rc=1 → linked = автостарт выключен)
is-active:  inactive
страта-процессов нет — VRAM не захвачена
GPU 0, 15919 MiB
GPU 1, 15317 MiB
RAM: used 3508 MiB, avail 57349 MiB
--- journald -u strata (последние строки последнего запуска) ---
    self.close()
BrokenPipeError: [Errno 32] Broken pipe
[strata] stopped
strata.service: Deactivated successfully.
Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
strata.service: Consumed 28.283s CPU time over 17.175s wall clock time, 51.8G memory peak.
--- читаемость юнита их репо ---
# /etc/systemd/system/strata.service -> /home/dimmy/projects/00 infra/llm-server/scripts/strata/strata.service
# strata.service — нативный движок Strata (Qwen3.8-Flash-Next) на хосте.
#

## 7) Коды выхода ошибок  15:48:32
usage: strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}
bogus → rc=1
usage: strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}
no-arg → rc=1
readlink активного конфига: /opt/strata/strata-iq3_xxs.json
