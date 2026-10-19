# Цикл ×2: llama → strata-iq3 → strata-iq2 → ninfer → off (тикет 04, 2026-10-19)

Сокращённый верификационный проход: 2 полных цикла strata-use.sh подряд.
Все переключения только через `scripts/strata/strata-use.sh`; после каждого шага —
`GET /api/profiles` (active), `GET /v1/models`, VRAM/RAM-снапшот, хвост journald -u strata.
Снапшоты mid-N — 4-секундный поллинг вокруг тяжёлых переходов (старт/останов юнита).

## Сводная таблица переходов

| цикл | шаг | время | exit | elapsed | active после |
|---|---|---|---|---|---|
| 1 | llama (+прогрев) | 16:33:31 | 0 | 4 c (прогрев 8.7 c) | llama |
| 1 | strata-iq3 | 16:33:51 | 0 | 29 c (/health 24 c) | strata-iq3 |
| 1 | strata-iq2 | 16:35:14 | 0 | 20 c (/health 14 c) | strata-iq2 |
| 1 | ninfer (+прогрев) | 16:35:56 | 0 | 4 c (прогрев 7.6 c) | ninfer |
| 1 | off | 16:36:16 | 0 | 4 c (no-op) | ninfer |
| 2 | llama (+прогрев) | 16:36:26 | 0 | 4 c (прогрев 9.0 c) | llama |
| 2 | strata-iq3 | 16:36:47 | 0 | 26 c (/health 23 c) | strata-iq3 |
| 2 | strata-iq2 | 16:37:29 | 0 | 20 c (/health 14 c) | strata-iq2 |
| 2 | ninfer (+прогрев) | 16:38:08 | 0 | 4 c (прогрев 7.6 c) | ninfer |
| 2 | off | 16:38:28 | 0 | 4 c (no-op) | ninfer |

RAM-гейты скрипта: iq3 — available 57.2/57.3 ГиБ ≥ 46 ГиБ; iq2 — 57.5/56.9 ГиБ ≥ 36 ГиБ.
Идемпотентность: off из ninfer — no-op в обоих циклах; повторный strata-use не потребовался.

**Наблюдение 1 (семантика листинга).** Под страта-профилем `/v1/models` отдаёт ДВЕ записи
(`strata-iq2`, `strata-iq3`) — родитель `qwen3.8-27b` (мета-тип profile) исчезает из листинга,
пин `~` в конфиге; под родительскими профилями — три записи (страта-ID с пином видны как
unloaded, прямой запрос → 404). Это семантика пинов llama-swap v265 (см. тикет 01),
не регресс; формулировка задания «три ID» выполняется в родительских состояниях.

**Наблюдение 2 (транзиентный своп на старте iq3).** Во время загрузки экспертов iq3 (~40 ГиБ,
10–15 с) vmstat показывает кратковременные si/so-всплески (до ~190/80 МиБ/с, 2 окна 
vmstat-c{1,2}-iq3.log) — page cache вытесняется, анонимные страницы на секунды уходят в swap;
available при этом не падает ниже ~13.5 ГиБ, в покое so=0. Не постоянный своп, красная линия RAM не тронута.

**Наблюдение 3 (косметика).** В journald при каждом останове юнита — BrokenPipeError в
server.py shutdown (глотнутый SIGTERM, добивание деревом работает — «Deactivated successfully»).
Совпадает с логом тикета 02, не аномалия.

## Полный сырой лог шагов
```
===== STEP c1-llama (llama) start 16:33:31
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:33:31 переход на родительский 'llama'
[strata-use] 16:33:33 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15321 MiB
[strata-use] 16:33:33 профиль llama-swap: активен 'llama'
[strata-use] 16:33:33 GPU0 free 15919 MiB | GPU1 free 15321 MiB; RAM available 57215 MiB
[strata-use] 16:33:33 ГОТОВО: 'llama' — движок загрузится на первом запросе к qwen3.8-27b
--- warmup qwen3.8-27b (родитель резидентен, max_tokens 8):
  HTTP 200, wall 8.749152s
  warmup ok
--- snapshot [post] 16:33:44
  VRAM GPU0, 983 MiB free
  VRAM GPU1, 1522 MiB free
  RAM: avail 55352 MiB / used 5504 MiB
--- /api/profiles active: llama
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:25:14 dimmy-server python[482858]: Traceback (most recent call last):
  Oct 19 16:25:14 dimmy-server python[482858]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:25:14 dimmy-server python[482858]:     self.close()
  Oct 19 16:25:14 dimmy-server python[482858]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:25:14 dimmy-server python[482858]: [strata] stopped
  Oct 19 16:25:15 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:25:15 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:25:15 dimmy-server systemd[1]: strata.service: Consumed 59.420s CPU time over 23.382s wall clock time, 52.5G memory peak.
===== STEP c1-llama end 16:33:44
===== STEP c1-iq3 (strata-iq3) start 16:33:51
--- snapshot [mid-1] 16:33:55
  VRAM GPU0, 15919 MiB free
  VRAM GPU1, 15321 MiB free
  RAM: avail 56147 MiB / used 4709 MiB
--- snapshot [mid-2] 16:33:59
  VRAM GPU0, 11033 MiB free
  VRAM GPU1, 9377 MiB free
  RAM: avail 34012 MiB / used 26844 MiB
--- snapshot [mid-3] 16:34:03
  VRAM GPU0, 11033 MiB free
  VRAM GPU1, 9377 MiB free
  RAM: avail 16995 MiB / used 43862 MiB
--- snapshot [mid-4] 16:34:08
  VRAM GPU0, 11033 MiB free
  VRAM GPU1, 9377 MiB free
  RAM: avail 16439 MiB / used 44417 MiB
--- snapshot [mid-5] 16:34:12
  VRAM GPU0, 10953 MiB free
  VRAM GPU1, 9293 MiB free
  RAM: avail 15737 MiB / used 45120 MiB
--- snapshot [mid-6] 16:34:16
  VRAM GPU0, 1177 MiB free
  VRAM GPU1, 2145 MiB free
  RAM: avail 15663 MiB / used 45194 MiB
--- SCRIPT_EXIT=0 elapsed=29s
--- лог strata-use.sh:
[strata-use] 16:33:51 переход на strata-iq3 (конфиг strata-iq3_xxs.json)
[strata-use] 16:33:53 VRAM Strata освобождена: GPU0 free 983 MiB | GPU1 free 1523 MiB
[strata-use] 16:33:54 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 16:33:54 RAM available 57160 MiB ≥ порог 46000 MiB — родительский стек не держит idle-cache
[strata-use] 16:33:54 симлинк /etc/strata/active.json → /opt/strata/strata-iq3_xxs.json
[strata-use] 16:33:54 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 16:34:18 /health :8081 → model=qwen3.8-flash-next-iq3_xxs loaded=true (за 24 с)
[strata-use] 16:34:18 профиль llama-swap: активен 'strata-iq3'
[strata-use] 16:34:18 GPU0 free 811 MiB | GPU1 free 1673 MiB; RAM available 13558 MiB
[strata-use] 16:34:18 ГОТОВО: strata-iq3 — доступен через llama-swap :8080 (публичный ID 'strata-iq3')
--- snapshot [post] 16:34:20
  VRAM GPU0, 811 MiB free
  VRAM GPU1, 1673 MiB free
  RAM: avail 13550 MiB / used 47307 MiB
--- /api/profiles active: strata-iq3
--- /v1/models: ["strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:33:57 dimmy-server python[487156]:          Please wait and don't close this window; the browser opens when it is ready.
  Oct 19 16:34:16 dimmy-server python[487156]: [strata] experts loaded: 39.97 GiB at 6.06 GiB/s (20 s so far)
  Oct 19 16:34:16 dimmy-server python[487156]: [strata] filling the GPU's expert cache (6606 experts, 9.55 GiB of VRAM) ...
  Oct 19 16:34:16 dimmy-server python[487156]: [strata] almost ready ...
  Oct 19 16:34:17 dimmy-server python[487156]: ready: http://172.17.0.1:8081/v1  (OpenAI: /v1/chat/completions, Anthropic: /v1/messages, context 131072 tokens, images on)
  Oct 19 16:34:17 dimmy-server python[487156]:        open http://172.17.0.1:8081/ in a browser to chat; close this window to stop the model
  Oct 19 16:34:17 dimmy-server python[487156]:        from other devices: http://192.168.17.99:8081/   (API: http://192.168.17.99:8081/v1)
  Oct 19 16:34:17 dimmy-server python[487156]:        WARNING: no API key - anyone on your network can use this model. Add "api_key": "..." to the config (clients send it as their API key; the web page asks for it)
===== STEP c1-iq3 end 16:34:20
===== STEP c1-iq2 (strata-iq2) start 16:35:14
--- snapshot [mid-1] 16:35:18
  VRAM GPU0, 15919 MiB free
  VRAM GPU1, 15317 MiB free
  RAM: avail 57515 MiB / used 3342 MiB
--- snapshot [mid-2] 16:35:22
  VRAM GPU0, 12585 MiB free
  VRAM GPU1, 11983 MiB free
  RAM: avail 55369 MiB / used 5488 MiB
--- snapshot [mid-3] 16:35:26
  VRAM GPU0, 10601 MiB free
  VRAM GPU1, 8589 MiB free
  RAM: avail 21268 MiB / used 39588 MiB
--- snapshot [mid-4] 16:35:30
  VRAM GPU0, 10601 MiB free
  VRAM GPU1, 8589 MiB free
  RAM: avail 21243 MiB / used 39614 MiB
--- SCRIPT_EXIT=0 elapsed=20s
--- лог strata-use.sh:
[strata-use] 16:35:14 переход на strata-iq2 (конфиг strata-iq2_xs.json)
[strata-use] 16:35:14 останов юнита strata…
[strata-use] 16:35:19 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15317 MiB
[strata-use] 16:35:19 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 16:35:19 RAM available 57519 MiB ≥ порог 36000 MiB — родительский стек не держит idle-cache
[strata-use] 16:35:19 симлинк /etc/strata/active.json → /opt/strata/strata-iq2_xs.json
[strata-use] 16:35:19 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 16:35:33 /health :8081 → model=qwen3.8-flash-next-iq2_xs loaded=true (за 14 с)
[strata-use] 16:35:33 профиль llama-swap: активен 'strata-iq2'
[strata-use] 16:35:33 GPU0 free 2469 MiB | GPU1 free 1707 MiB; RAM available 19181 MiB
[strata-use] 16:35:33 ГОТОВО: strata-iq2 — доступен через llama-swap :8080 (публичный ID 'strata-iq2')
--- snapshot [post] 16:35:34
  VRAM GPU0, 2469 MiB free
  VRAM GPU1, 1707 MiB free
  RAM: avail 19150 MiB / used 41706 MiB
--- /api/profiles active: strata-iq2
--- /v1/models: ["strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:35:22 dimmy-server python[488257]:          Please wait and don't close this window; the browser opens when it is ready.
  Oct 19 16:35:30 dimmy-server python[488257]: [strata] experts loaded: 33.02 GiB at 6.53 GiB/s (11 s so far)
  Oct 19 16:35:30 dimmy-server python[488257]: [strata] filling the GPU's expert cache (5733 experts, 7.60 GiB of VRAM) ...
  Oct 19 16:35:31 dimmy-server python[488257]: [strata] almost ready ...
  Oct 19 16:35:32 dimmy-server python[488257]: ready: http://172.17.0.1:8081/v1  (OpenAI: /v1/chat/completions, Anthropic: /v1/messages, context 262144 tokens, images on)
  Oct 19 16:35:32 dimmy-server python[488257]:        open http://172.17.0.1:8081/ in a browser to chat; close this window to stop the model
  Oct 19 16:35:32 dimmy-server python[488257]:        from other devices: http://192.168.17.99:8081/   (API: http://192.168.17.99:8081/v1)
  Oct 19 16:35:32 dimmy-server python[488257]:        WARNING: no API key - anyone on your network can use this model. Add "api_key": "..." to the config (clients send it as their API key; the web page asks for it)
===== STEP c1-iq2 end 16:35:34
===== STEP c1-ninfer (ninfer) start 16:35:56
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:35:56 переход на родительский 'ninfer'
[strata-use] 16:35:56 останов юнита strata…
[strata-use] 16:35:59 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15319 MiB
[strata-use] 16:35:59 профиль llama-swap: активен 'ninfer'
[strata-use] 16:35:59 GPU0 free 15919 MiB | GPU1 free 15319 MiB; RAM available 57506 MiB
[strata-use] 16:35:59 ГОТОВО: 'ninfer' — движок загрузится на первом запросе к qwen3.8-27b
--- warmup qwen3.8-27b (родитель резидентен, max_tokens 8):
  HTTP 200, wall 7.597901s
  warmup ok
--- snapshot [post] 16:36:08
  VRAM GPU0, 1199 MiB free
  VRAM GPU1, 709 MiB free
  RAM: avail 53676 MiB / used 7181 MiB
--- /api/profiles active: ninfer
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:35:57 dimmy-server python[488257]: Traceback (most recent call last):
  Oct 19 16:35:57 dimmy-server python[488257]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:35:57 dimmy-server python[488257]:     self.close()
  Oct 19 16:35:57 dimmy-server python[488257]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:35:57 dimmy-server python[488257]: [strata] stopped
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:35:57 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Consumed 1min 21.913s CPU time over 38.618s wall clock time, 48.8G memory peak.
===== STEP c1-ninfer end 16:36:08
===== STEP c1-off (off) start 16:36:16
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:36:16 уже off (юнит не запущен, профиль дефолтного 'ninfer') — no-op
--- snapshot [post] 16:36:20
  VRAM GPU0, 1199 MiB free
  VRAM GPU1, 709 MiB free
  RAM: avail 53537 MiB / used 7320 MiB
--- /api/profiles active: ninfer
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:35:57 dimmy-server python[488257]: Traceback (most recent call last):
  Oct 19 16:35:57 dimmy-server python[488257]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:35:57 dimmy-server python[488257]:     self.close()
  Oct 19 16:35:57 dimmy-server python[488257]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:35:57 dimmy-server python[488257]: [strata] stopped
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:35:57 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Consumed 1min 21.913s CPU time over 38.618s wall clock time, 48.8G memory peak.
===== STEP c1-off end 16:36:20
===== STEP c2-llama (llama) start 16:36:26
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:36:26 переход на родительский 'llama'
[strata-use] 16:36:28 VRAM Strata освобождена: GPU0 free 1199 MiB | GPU1 free 709 MiB
[strata-use] 16:36:28 профиль llama-swap: активен 'llama'
[strata-use] 16:36:28 GPU0 free 1199 MiB | GPU1 free 709 MiB; RAM available 53654 MiB
[strata-use] 16:36:28 ГОТОВО: 'llama' — движок загрузится на первом запросе к qwen3.8-27b
--- warmup qwen3.8-27b (родитель резидентен, max_tokens 8):
  HTTP 200, wall 9.008329s
  warmup ok
--- snapshot [post] 16:36:39
  VRAM GPU0, 983 MiB free
  VRAM GPU1, 1519 MiB free
  RAM: avail 55537 MiB / used 5320 MiB
--- /api/profiles active: llama
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:35:57 dimmy-server python[488257]: Traceback (most recent call last):
  Oct 19 16:35:57 dimmy-server python[488257]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:35:57 dimmy-server python[488257]:     self.close()
  Oct 19 16:35:57 dimmy-server python[488257]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:35:57 dimmy-server python[488257]: [strata] stopped
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:35:57 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:35:57 dimmy-server systemd[1]: strata.service: Consumed 1min 21.913s CPU time over 38.618s wall clock time, 48.8G memory peak.
===== STEP c2-llama end 16:36:39
===== STEP c2-iq3 (strata-iq3) start 16:36:47
--- snapshot [mid-1] 16:36:51
  VRAM GPU0, 14153 MiB free
  VRAM GPU1, 15314 MiB free
  RAM: avail 55721 MiB / used 5136 MiB
--- snapshot [mid-2] 16:36:55
  VRAM GPU0, 11033 MiB free
  VRAM GPU1, 9373 MiB free
  RAM: avail 24204 MiB / used 36652 MiB
--- snapshot [mid-3] 16:37:01
  VRAM GPU0, 11033 MiB free
  VRAM GPU1, 9373 MiB free
  RAM: avail 16910 MiB / used 43947 MiB
--- snapshot [mid-4] 16:37:05
  VRAM GPU0, 10953 MiB free
  VRAM GPU1, 9293 MiB free
  RAM: avail 15738 MiB / used 45119 MiB
--- snapshot [mid-5] 16:37:09
  VRAM GPU0, 10953 MiB free
  VRAM GPU1, 9293 MiB free
  RAM: avail 15715 MiB / used 45141 MiB
--- SCRIPT_EXIT=0 elapsed=26s
--- лог strata-use.sh:
[strata-use] 16:36:47 переход на strata-iq3 (конфиг strata-iq3_xxs.json)
[strata-use] 16:36:50 VRAM Strata освобождена: GPU0 free 983 MiB | GPU1 free 1519 MiB
[strata-use] 16:36:50 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 16:36:50 RAM available 57344 MiB ≥ порог 46000 MiB — родительский стек не держит idle-cache
[strata-use] 16:36:50 симлинк /etc/strata/active.json → /opt/strata/strata-iq3_xxs.json
[strata-use] 16:36:50 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 16:37:13 /health :8081 → model=qwen3.8-flash-next-iq3_xxs loaded=true (за 23 с)
[strata-use] 16:37:13 профиль llama-swap: активен 'strata-iq3'
[strata-use] 16:37:13 GPU0 free 811 MiB | GPU1 free 1673 MiB; RAM available 13537 MiB
[strata-use] 16:37:13 ГОТОВО: strata-iq3 — доступен через llama-swap :8080 (публичный ID 'strata-iq3')
--- snapshot [post] 16:37:13
  VRAM GPU0, 811 MiB free
  VRAM GPU1, 1672 MiB free
  RAM: avail 13536 MiB / used 47321 MiB
--- /api/profiles active: strata-iq3
--- /v1/models: ["strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:36:53 dimmy-server python[489387]:          Please wait and don't close this window; the browser opens when it is ready.
  Oct 19 16:37:10 dimmy-server python[489387]: [strata] experts loaded: 39.97 GiB at 5.42 GiB/s (20 s so far)
  Oct 19 16:37:10 dimmy-server python[489387]: [strata] filling the GPU's expert cache (6606 experts, 9.55 GiB of VRAM) ...
  Oct 19 16:37:11 dimmy-server python[489387]: [strata] almost ready ...
  Oct 19 16:37:13 dimmy-server python[489387]: ready: http://172.17.0.1:8081/v1  (OpenAI: /v1/chat/completions, Anthropic: /v1/messages, context 131072 tokens, images on)
  Oct 19 16:37:13 dimmy-server python[489387]:        open http://172.17.0.1:8081/ in a browser to chat; close this window to stop the model
  Oct 19 16:37:13 dimmy-server python[489387]:        from other devices: http://192.168.17.99:8081/   (API: http://192.168.17.99:8081/v1)
  Oct 19 16:37:13 dimmy-server python[489387]:        WARNING: no API key - anyone on your network can use this model. Add "api_key": "..." to the config (clients send it as their API key; the web page asks for it)
===== STEP c2-iq3 end 16:37:13
===== STEP c2-iq2 (strata-iq2) start 16:37:29
--- snapshot [mid-1] 16:37:33
  VRAM GPU0, 15919 MiB free
  VRAM GPU1, 15242 MiB free
  RAM: avail 56964 MiB / used 3893 MiB
--- snapshot [mid-2] 16:37:37
  VRAM GPU0, 10371 MiB free
  VRAM GPU1, 9189 MiB free
  RAM: avail 54741 MiB / used 6115 MiB
--- snapshot [mid-3] 16:37:41
  VRAM GPU0, 10305 MiB free
  VRAM GPU1, 8807 MiB free
  RAM: avail 20641 MiB / used 40216 MiB
--- snapshot [mid-4] 16:37:45
  VRAM GPU0, 2527 MiB free
  VRAM GPU1, 2144 MiB free
  RAM: avail 20707 MiB / used 40149 MiB
--- SCRIPT_EXIT=0 elapsed=20s
--- лог strata-use.sh:
[strata-use] 16:37:29 переход на strata-iq2 (конфиг strata-iq2_xs.json)
[strata-use] 16:37:29 останов юнита strata…
[strata-use] 16:37:34 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15242 MiB
[strata-use] 16:37:34 llama-swap: unload всех моделей (родительский стек, shims) — принято
[strata-use] 16:37:34 RAM available 56960 MiB ≥ порог 36000 MiB — родительский стек не держит idle-cache
[strata-use] 16:37:34 симлинк /etc/strata/active.json → /opt/strata/strata-iq2_xs.json
[strata-use] 16:37:34 старт юнита strata (systemctl start; автостарт disabled)…
[strata-use] 16:37:48 /health :8081 → model=qwen3.8-flash-next-iq2_xs loaded=true (за 14 с)
[strata-use] 16:37:48 профиль llama-swap: активен 'strata-iq2'
[strata-use] 16:37:48 GPU0 free 2173 MiB | GPU1 free 1701 MiB; RAM available 18585 MiB
[strata-use] 16:37:48 ГОТОВО: strata-iq2 — доступен через llama-swap :8080 (публичный ID 'strata-iq2')
--- snapshot [post] 16:37:49
  VRAM GPU0, 2173 MiB free
  VRAM GPU1, 1701 MiB free
  RAM: avail 18559 MiB / used 42297 MiB
--- /api/profiles active: strata-iq2
--- /v1/models: ["strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:37:37 dimmy-server python[491304]:          Please wait and don't close this window; the browser opens when it is ready.
  Oct 19 16:37:45 dimmy-server python[491304]: [strata] experts loaded: 33.02 GiB at 6.51 GiB/s (11 s so far)
  Oct 19 16:37:45 dimmy-server python[491304]: [strata] filling the GPU's expert cache (5750 experts, 7.60 GiB of VRAM) ...
  Oct 19 16:37:46 dimmy-server python[491304]: [strata] almost ready ...
  Oct 19 16:37:47 dimmy-server python[491304]: ready: http://172.17.0.1:8081/v1  (OpenAI: /v1/chat/completions, Anthropic: /v1/messages, context 262144 tokens, images on)
  Oct 19 16:37:47 dimmy-server python[491304]:        open http://172.17.0.1:8081/ in a browser to chat; close this window to stop the model
  Oct 19 16:37:47 dimmy-server python[491304]:        from other devices: http://192.168.17.99:8081/   (API: http://192.168.17.99:8081/v1)
  Oct 19 16:37:47 dimmy-server python[491304]:        WARNING: no API key - anyone on your network can use this model. Add "api_key": "..." to the config (clients send it as their API key; the web page asks for it)
===== STEP c2-iq2 end 16:37:49
===== STEP c2-ninfer (ninfer) start 16:38:08
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:38:08 переход на родительский 'ninfer'
[strata-use] 16:38:08 останов юнита strata…
[strata-use] 16:38:12 VRAM Strata освобождена: GPU0 free 15919 MiB | GPU1 free 15090 MiB
[strata-use] 16:38:12 профиль llama-swap: активен 'ninfer'
[strata-use] 16:38:12 GPU0 free 15919 MiB | GPU1 free 15090 MiB; RAM available 56710 MiB
[strata-use] 16:38:12 ГОТОВО: 'ninfer' — движок загрузится на первом запросе к qwen3.8-27b
--- warmup qwen3.8-27b (родитель резидентен, max_tokens 8):
  HTTP 200, wall 7.551647s
  warmup ok
--- snapshot [post] 16:38:20
  VRAM GPU0, 1355 MiB free
  VRAM GPU1, 711 MiB free
  RAM: avail 52981 MiB / used 7876 MiB
--- /api/profiles active: ninfer
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:38:09 dimmy-server python[491304]: Traceback (most recent call last):
  Oct 19 16:38:09 dimmy-server python[491304]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:38:09 dimmy-server python[491304]:     self.close()
  Oct 19 16:38:09 dimmy-server python[491304]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:38:09 dimmy-server python[491304]: [strata] stopped
  Oct 19 16:38:10 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:38:10 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:38:10 dimmy-server systemd[1]: strata.service: Consumed 59.723s CPU time over 35.626s wall clock time, 52.9G memory peak.
===== STEP c2-ninfer end 16:38:20
===== STEP c2-off (off) start 16:38:28
--- SCRIPT_EXIT=0 elapsed=4s
--- лог strata-use.sh:
[strata-use] 16:38:28 уже off (юнит не запущен, профиль дефолтного 'ninfer') — no-op
--- snapshot [post] 16:38:32
  VRAM GPU0, 1355 MiB free
  VRAM GPU1, 761 MiB free
  RAM: avail 53085 MiB / used 7771 MiB
--- /api/profiles active: ninfer
--- /v1/models: ["qwen3.8-27b","strata-iq2","strata-iq3"]
--- journalctl -u strata (хвост 8):
  Oct 19 16:38:09 dimmy-server python[491304]: Traceback (most recent call last):
  Oct 19 16:38:09 dimmy-server python[491304]:   File "/opt/strata/serve/server.py", line 2540, in shutdown
  Oct 19 16:38:09 dimmy-server python[491304]:     self.close()
  Oct 19 16:38:09 dimmy-server python[491304]: BrokenPipeError: [Errno 32] Broken pipe
  Oct 19 16:38:09 dimmy-server python[491304]: [strata] stopped
  Oct 19 16:38:10 dimmy-server systemd[1]: strata.service: Deactivated successfully.
  Oct 19 16:38:10 dimmy-server systemd[1]: Stopped strata.service - Strata native engine (Qwen3.8-Flash-Next, :8081, размер через /etc/strata/active.json).
  Oct 19 16:38:10 dimmy-server systemd[1]: strata.service: Consumed 59.723s CPU time over 35.626s wall clock time, 52.9G memory peak.
===== STEP c2-off end 16:38:32
```
