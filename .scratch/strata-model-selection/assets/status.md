# Статус-борд прогона матрицы

Многосессионный статус по протоколу (`issues/06-benchmark-protocol.md`).
Порядок: IQ3_XXS → IQ3_S → IQ2_XS; RAM-сбой XXS пропускает S.
Сценарии: calibrate / delta (XXS only) / chat / 16K / 32K / ceiling / agent-bench /
agent-live (HITL, opencode) / gaps / multiturn / soak / vision-smoke.

## IQ3_XXS (сессия от 2026-10-18)

- Решения перед стартом: draft-vocab **cyrillic** (все три модели, файл заменён в `mtp/rt`),
  потолок 131072 в конфиге, мониторинг-стек остановлен.
- Старт-лествница (4 неудачи): chunk 8192→4096 (cuBLAS OOM на CUDA1), cache auto→4400
  (verify-arena 70 MiB не влезал); с `--expert-cache-device1` на 2-stage сплите нельзя.
  Старт ОК на 131072 с chunk 4096 + cache 4400.
- uncal-delta (до калибровки): chat decode **125.3 tok/s** (мед.), TTFT 0.26 c,
  prefill 4K 2538.7 tok/s, 16K **4309.3 tok/s**; agent 5 туров: hit 68.75 %, re-read 4.
- calibrate: done (~37 мин): --pcie-frac 0.20, --spec-min-p 0.70, adaptive (--adapt-every 1
  --adapt-swaps 160 --adapt-decay 0.97); модель стартовала сама.
- delta после калибровки: chat decode **129.3 tok/s** (+3 %), TTFT 0.21 c, 4K 2565.8,
  16K 4313.2 (ровно), agent decode 153.1 (+5 %) — выгода, калиброванное состояние принято.
- chat: done (калиброванное: см. cal-delta-post)
- 16K: done (калиброванное)
- гэп-чеклист: done (см. ниже)
- потолок (128K×3): done
- multiturn: done
- agent-bench: done (в составе suite: hit 68.7 %, re-read 4)
- agent-live (opencode, `--standalone` против :8081): **done, работа идёт**. Фиксированный
  таск (анализ config.yaml + config.d + ADR-0006): 4 параллельных `read`-tool вызова
  корректны; отчёт качественный (дубли `stripParams`/контекстных чисел, напряжение
  `--reasoning on` с ADR-0006 §3, 3 предложения по структуре — вкл. проверку парности
  зеркал). Числа: первый prompt 14 518 tok (read 14 518 @ 3235 tok/s, 4.5 c), follow-up
  21 443 tok = 14 664 reused + 6779 read — prefix-cache в агентном цикле работает,
  re-read только на новые tool-выводы; ответ 5384 токенов @ **144.7 tok/s**, MTP
  admission 75.6 %. Сессия `ses_eaffb5f15ffe64gyaIJH7l8VuO`; строки движка —
  `assets/IQ3_XXS/agent-live-prompt-lines.log`, JSON-лог — `agent-live-opencode.jsonl`.
  Замечание: без `--standalone` opencode уходит в background service со своим конфигом
  (:8080, llama-swap остановлен) → ConnectionRefused; для Strata-окон — `--standalone`.
- soak: done — 3 холодных старта XXS: **READY 16 c** каждый (тёплый page-cache: до
- гэп-чеклист (gaps.json): forced tool choice **работает** (200 + корректный call);
  structured outputs + tools → 400 «structured response_format with tools/MCP is not
  supported»; невалидный effort → 400 со словарём «none, low, medium or high»;
  `xhigh` принят (200); `low` 200.
- потолок (custom_scenarios.py ceiling): 116 066 токенов (88.5 % потолка); fresh prefill
  **4782.2 tok/s**, TTFT 24.3 c; decode при полном KV 118.2–148.9 tok/s; длительная
  генерация 4096/4096 токенов @ ~110K контекста: decode **141.5 tok/s**, admission 80.6%;
  VRAM min GPU0 741 / GPU1 1612 MiB; prefix reuse ~116k → TTFT 0.056 c. **pass**
- multiturn (15 туров по 8K): prompt вырос до 120 265 (92 % потолка), reuse каждый тур
  (read ~8011), TTFT 2.4–2.6 c, VRAM GPU1 min 1610, swap 0, RAM avail min 10.9 GiB. **pass**
- watch-аннотации (весь день): GPU1 min **1494 MiB** (красная линия держится);
  GPU0 min 63 MiB (транзитор на загрузке), RAM avail min 8.8 GiB, своп макс 3313 MiB
  (ростка за калибровкой до перезагрузки; после перезагрузки своп 0 и не рос).
- soak: done — 3 холодных старта XXS: **READY 16 c** каждый (тёплый page-cache: до
  страницы бенчей старт был ~40-60 c); цикл переключений XS 12 c / S 24 c / XXS 16 c;
  после останова RAM avail 57.5 GiB, своп 586 MiB — возвращается. **pass**
- vision-smoke: **done, PASS** — strata-vision CPU собран (engine/strata-vision),
  mmproj квантован BF16→Q8_0 локально (588 MB, 27/334 fallback); секция vision добавлена
  в конфиг без тронутых калиброванных args (бэкоп pre-vision). Две пробы: обе **корректны**
  (объекты+цвета названы верно), 200 за 2.9 c / 2.3 c (часть — encode CPU ~1 c);
  prompt 377/325 img-токенов (read 935/695 мс), ген 152/176 tok/s; VRAM GPU1 min 1604,
  RAM min 11.2 GiB, своп не рос. Детали — vision-smoke.log. Тем самым XXS-окна сценарии
  протокола закрыты.

## Лествница старта (все модели, по ходу выяснено)

- IQ3_XXS @ 131072: chunk 8192→**4096** (cuBLAS OOM CUDA1), cache auto→**4400**
  (verify-arena 70 MiB); `--expert-cache-device1` на 2-stage сплите нельзя (exit 2).
- IQ2_XS @32768: chunk 4096 + **deprecated cache 6800** — старт ОК (12 c).
- IQ2_XS @262144 (окно 2026-10-18): 131072 стартует с cache 6800 с 1-й попытки (1380/1706 MiB);
  262144 с **cache 6800** стартует, но CUDA0 free 160 MiB (LOW) → лествица cache → **5400** даёт
  2176/1706 MiB — PASS. 131072 при ≥1 GiB на картах → XS живёт на потолке 262144.
- IQ3_S @ 32768: **`--resident-experts` блокер движка на 2-GPU сплите** —
  `prefill gemm: cublasCreate: cuBLAS status 3` даже с chunk 4096 и cache 4000
  (три попытки). Без resident (пул с SSD/mmap) стартует с chunk 4096 + cache
  **4000**; калиброванное де-факто состояние S будет этим. RAM станд. состояние S:
  в page-cache 51 GiB → RAM avail 5.4 GiB под нагрузкой загрузки, без свопа.
- vision-smoke (XXS/S/XS): done во всех трёх окнах (CPU-encoder, Q8_0 mmproj; XS — 2026-10-18)
- 32K (--long): done — prefill 4802.8 tok/s (TTFT 6.70 c) (bench/32k-long)
- ceiling (128K×3): done (выше)
- multiturn: done (выше)

## IQ3_S

- Сессия: **выполнена 2026-10-18/19, окно закрыто, все этапы pass** (детали: `assets/IQ3_S/cover.json`).
  Конфиг: `strata-iq3_s.json` — prefill 4096, expert-cache 4000, **без `--resident-experts`**
  (блокер движка, см. выше), потолок **65536** (лествица не потребовалась — старт с 1-й попытки,
  ~25 c, free 754/1647 MiB). Калибровка ~8.5 мин → pcie-frac 0.20, spec-min-p 0.70, adaptive.
- Ядро замера: chat decode мед **122.4 tok/s** (TTFT 0.20–0.22 c); prefill 4K 2426 / 16K 4061.7 /
  32K 4524.7 tok/s; агент hit 68.68 %, turn decode мед 141.8 tok/s.
- Потолок: **58034 tok (88.5 %)** ×3; fresh prefill 4725.5 tok/s, reuse TTFT 0.049 c,
  decode при полном KV мед 141.3 tok/s. Длинная генерация на ~59k KV: **4500 токенов
  @ 174.1 tok/s** wall (движок 184.5), admission 93.2 %; первый вариант (filler без
  задания) закрылся EOS на 65 токенах — порок клиента, не модели.
- Контакт/гэпы: forced tool 200; structured+tools 400; json_schema без tools 200;
  невалидный effort 400; xhigh/low 200. Agent-live (opencode --standalone) — pass,
  prefix-cache работает (cold 14454 → 16862 reused).
- Multiturn 15×4000: структурно pass (60262 tok, reuse 56253, TTFT ~1.75 c, swap net 0),
  но ответы туров 8–15 = 2 tok (EOS при temp 0 на filler-подтверждении) — артефакт данных.
- Vision: секция добавлена в конфиг (бэкап pre-vision), CPU-энкодер 0.6–0.75 c,
  обе пробы верны (объекты+цвета); GPU-фоллбек не потребовался.
- Soak: 3×cold S READY 20 c; цикл XS 12 / S 24 / XXS 16 c; RAM вернулась (57004 MiB),
  своп net 0 (720 MiB). Аудит порогов за окно: GPU0 min 683 / GPU1 min 1296 MiB (линия ≥512
  не тронута), swap max 1207 (+667 от базеля; порог +2 GiB не тронут), RAM min 2983 MiB.
- Вердикт: **стабильно**; следующий двор — IQ2_XS.
- (Дубль-проход 2026-10-18/19 21:12–21:55 UTC, сессия-субагент) После разъезда параллельных окон
  второй проход повторил остаток на чистом порте и независимо подтвердил: chat 122.4 / prefill
  4524.7 (32K) / longgen 4500 @ 174.1 tok/s; agent-live вторая сессия `ses_eaf159f5cffeBejAVFA6JgsdI1`
  (14 382 fresh @ 3334.8 tok/s; финал 1013 tok @ 157.0; reuse 20578+); multiturn 60 259 = 91.9 %;
  soak 3×24 c (RAM 57 232 / своп 1310); vision 2/2. Конфликт 20:00–20:16Z (параллельное окно
  занимало :8081+GPUs, был убит env-restart и watch-монитор потом) задокументирован в cover.json;
  два env-фикса opencode (proxy / имя провайдера `llama-swap`→`strata-s`) — в cover.json и summary.

## IQ2_XS

- Сессия: **выполнена 2026-10-18 (20:14–20:52 UTC), окно закрыто, все этапы pass** (детали:
  `assets/IQ2_XS/cover.json`). Конфиг: `strata-iq2_xs.json` — prefill 4096, **expert-cache 5400**
  (лествица: 6800 @262144 даёт CUDA0 free 160 MiB LOW → 5400 без сноса), потолок **262144**
  (лествица: 32768 смоук → 131072 OK с 1-й попытки (1380/1706 MiB) → 262144 cache 5400 OK
  (2176/1706 MiB); 131072 обе карты ≥1 GiB). Калибровка ~6 мин → pcie-frac 0.20, spec-min-p 0.70;
  **adaptive НЕ записан** (дефолт-tier 172.4 vs adapt 1/160/0.97 → 174.9 tok/s — калибратор оставил
  дефолт; отличие от XXS/S).
- Ядро замера: chat decode мед **144.90 tok/s** (TTFT 0.20 c); agent turn decode 154.70; prefill
  4K 2698.2 / 16K 4430.9 / 32K 4886.5 tok/s; агент hit 68.63 %, re-read 74 tok/сессия.
- Потолок: **232118 tok (88.5 %) ×3**; fresh prefill 4571.7 tok/s (TTFT 50.9 c), reuse TTFT 0.074 c,
  decode при полном KV мед 136.4 (127.0–139.1). Longgen (ratio 0.6, KV ~157k): **4096/4096 токенов
  @ 156.4 tok/s** wall (движок 159.7), admission 81.9 %.
- Контракт/гэпы: forced tool 200; structured+tools 400; json_schema без tools 200; невалидный
  effort 400; xhigh/low 200 — профиль = XXS/S. Agent-live (opencode --standalone) — pass,
  prefix-cache работает (cold 14450 → 20722 reused по турам), decode 995 tok @ 162.8 tok/s.
- Multiturn 15×16000: pass (240258 tok = 92 % потолка, reuse каждый тур, TTFT 4.0–4.8 c, VRAM
  2103/1607 MiB); decode None с тура 3 — EOS-артефакт temp 0 (как окно S), reuse-механика чистая.
- Vision: секция добавлена (бэкап pre-vision), CPU-энкодер, обе пробы корректны (объекты+цвета),
  2.40/2.14 c, 134 img+text tok.
- Soak: 3×cold XS READY 17/16/16 c; цикл XS 16 / S 24 / XXS 16 c; RAM вернулась (57306 MiB),
  своп net +650 (1366 MiB). Аудит порогов за окно: **GPU0 min 2103 / GPU1 min 1605 MiB** (линия
  ≥512 не тронута; GPU0 161 — транзиент отброшенной попытки), swap max 2167 MiB (пик на цикле
  S), RAM min 6047 MiB. Вердикт: **стабильно**; сцены матрицы закрыты — все три окна done.

## Напоминание следующей сессии (критический порядок!)

`llm-cadvisor` из llm-monitoring публикуется на host **:8081** — тот же порт, что Strata.
Перед ЛЮБЫМ окном замера: сначала `docker stop llm-monitoring`-контейнеры, потом старт
Strata-сервера; после окна — сервер остановить, мониторинг вернуть (как сделано 2026-10-18).
Наоборот — Strata не забиндит 8081.
