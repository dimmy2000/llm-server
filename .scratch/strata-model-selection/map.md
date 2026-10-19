# Strata: выбор размера Qwen3.8-Flash-Next для постоянного использования

Status: resolved
Labels: wayfinder:map

## Destination

Отчет в `docs/research/` с замерами скорости и отказоустойчивости Strata (Qwen3.8-Flash-Next)
на этой машине + зафиксированное решение «какой размер держать постоянно» (или вывод «никакой
не подходит»). Подключение выбранной модели через llama-swap — отдельное последующее усилие.

## Notes

- Железо: 2× RTX 5070 Ti (16 GB, GPU1 — дисплейная, красная линия ≥ 512 MiB), 59 GiB RAM
  (доступно ~47–48 при обычной загрузке), NVMe 1.2 TB свободно, драйвер 615.71.09-p2p
  (open-модули форка + vanilla userland). Стек llama-swap на `:8080` (`docs/AGENTS.md`,
  `AGENTS.md` в корне).
- Кандидаты и приоритет: **IQ3_XXS** (приоритет 1), **IQ3_S** (приоритет 2),
  **IQ2_XS** (страховочный при OOM у обеих 3-бит).
- Замеры: вытесняющий режим — контейнеры остановлены, Strata нативно на порту `:8081`;
  обе карты; VRAM-минимум GPU1 входит в критерии.
- Критерии годности: стабильность (жёстко: матрица без OOM/зависаний/дисковых штормов,
  RAM без постоянного свопа, VRAM GPU1 ≥ 512 MiB), decode > 20 tok/s, контекст — фиксируем
  по максимуму каждой модели без порогов. Качество — только опубликованные данные + субъективная
  оценка из агент-сессий. Базовая линия стабильности/скорости — исторические данные Qwen 3.8 27b
  (AGENTS.md, `docs/research/0014`, `0015`) — без повторных прогонов 27b.
- Язык сессий и отчета — русский. Страновые навыки: `/research` для research-тикетов.
- Raw-артефакты замеров кладутся в `.scratch/strata-model-selection/assets/`.
- Прогон матрицы многосессионный: статус по каждой модели фиксируется по ходу в
  `assets/status.md`, свод по окончании собирается в `assets/summary-matrix.md`
  (протокол — `issues/06-benchmark-protocol.md`).

## Decisions so far

- **[Отчет и решение](../../docs/research/0016-strata-flash-next-selection.md) закрыт
  (2026-10-19, тикет 08)** — пункт назначения достигнут: отчет собран
  (`docs/research/0016-strata-flash-next-selection.md`), решение зафиксировано.
  Держать постоянно **две модели** (условное — финальная ротация по пилоту на рабочих
  задачах после интеграции): **IQ3_XXS @131072** — сложные вопросы, планы работ,
  постановка задач субагентам; **IQ2_XS @262144** — простые задачи как аналог
  Qwen 3.8 27B (нужно окно ~262k). **IQ3_S — не выбрана** (RAM-теснота
  non-resident, блокер `--resident-experts`, потолок без собственной роли);
  runner-up — IQ3_S условный; fallback — существующий стек 27B. Решение условное:
  пересмотр по пилоту на рабочих задачах, критерии качественные (§10.1 отчета).
  Зафиксированы исключение UD-IQ4_XS (RAM-бюджет), feasibility для следующего
  усилия (основной путь B2 shim-модель) и операционный caveat (XXS и XS
  не резидентны одновременно — переключение = перезагрузка весов).

- [Окно IQ3_XXS закрыто (2026-10-18, тикет 07)](assets/summary-matrix.md) — все сценарии
  протокола pass; последовательный decode XXS **129–153 tok/s** (~6.5× репера llama.cpp
  20 tok/s) вплоть до 110K контекста; red-line VRAM GPU1 не нарушена; калиброванное
  состояние принято за замер. Субъективная оценка agent-сессии заменена headless-проверкой
  по решению пользователя («достаточно убедиться, что работа идёт»); headless-проверка:
  4 корректных tool-вызова, качественный отчёт, prefix-cache в агентном цикле работает.
  Старт-лествица по ходу: XS @32K = prefill 4096 + expert-cache 6800;
  S @32K: `--resident-experts` — блокер движка (cuBLAS status 3, три попытки), fallback
  non-resident cache 4000 (RAM под загрузкой уходит в page-cache, avail 5.4 GiB без
  свопа). Vision: mmproj Q8_0 получен локальным квантованием BF16 (апстрим-артефакта нет),
  CPU-энкодер strata-vision собран и отклик корректен. S/XS-окна продолжить в новых
  wayfinder-сессиях.
- [Окно IQ3_S закрыто (2026-10-18/19, тикет 07)](assets/summary-matrix.md) — потолок **65536**
  стартовал с 1-й попытки на нативных chunk 4096 / cache 4000 (лествица не потребовалась;
  без `--resident-experts` — блокер движка); chat decode мед **122.4 tok/s** (~6.1× репера
  llama.cpp 20 tok/s), prefill 2426→4726 tok/s, decode при полном KV 141.3, longgen 174.1;
  красная линия GPU1 (min 1296 MiB) не нарушена; RAM тесная non-resident (min 2.9 GiB avail,
  своп-пик +667 MiB) — плата блокера resident. Дубльный проход 21:12–21:55Z независимо
  подтвердил multiturn/soak/agent-live (+2 env-фикса opencode: http(s)_proxy ломает
  bun-fetch; имя провайдера `llama-swap` конфликтует с глобальным — в strata-конфиге
  opencode переименовано в `strata-s`). Стабильно.
- [Окно IQ2_XS закрыто (2026-10-18, тикет 07)](assets/summary-matrix.md) — потолок
  **262144** (максимальный из трёх; лествица cache 6800→5400: @6800 CUDA0 160 MiB LOW),
  калибровка ~6 мин (pcie-frac 0.20 / spec-min-p 0.70; adaptive калибратором не записан —
  дефолт-tier); chat decode мед **144.90 tok/s**, agent 154.70, fresh-232k prefill 4571.7
  tok/s (TTFT 50.9 с), decode при полном KV 136.4, longgen 4096 @ 156.4; GPU1 min
  **1605 MiB** (лучшая из трёх), RAM min 6.0 GiB (модель целиком в RAM), своп-пик +1451
  MiB на цикле переключений S. Стабильно — лучший VRAM/RAM-профиль тройки.
- [Установка Strata и скачивание моделей](issues/05-install-and-download.md) — Strata в
  `/opt/strata`, движок собран (CUDA 13.3), три размера IQ3_XXS/IQ3_S/IQ2_XS скачаны
  (hard-link shard2 общий), конфиги на `:8081`, `gpus [0,1]`, `gpu_order: as_given`,
  базовый контекст 32768, vision off, reserve GPU1 2048 MiB; реальный запуск не выполнялся.
- [issues/02 — Feasibility: llama-swap и Strata (resolved)](issues/02-llamaswap-feasibility.md):
  **feasible**. Механизмы v265: backend только как дочерний `cmd`-процесс (механизма
  хост-процессов и unix-socket нет), `checkEndpoint` умеет health-check внешнего URL,
  `peers:` — канонический внешний эндпоинт, пин публичного ID может целить в peer-модель.
  Тропы: A = контейнерный cmd (честная эксклюзивность, но третий образ-пин + memlock/
  unloadTimeout — план B), B1 = peers (дёшево, но ломает контракт «exactly one ID»),
  B2 = shim-модель (`cmd: sleep infinity` + `proxy: <host>:8081` + health `/health`) —
  рекомендуемый основной путь (сохраняет ADR-0006, без пересборки образа, Strata живёт
  нативно на `:8081` под systemd/скриптом), C = второй провайдер opencode — дешёвый
  старт. Не viable: запуск Strata через hooks (в `on_startup` нет команд). Общие рамки:
  RAM-конфликт резидентного Strata против llama.cpp `--cache-ram`, VRAM-резерв через
  `--vram-reserve-mib`, порт только `:8081`.

- [Совместимость API Strata с агентами](issues/03-api-agent-compat.md) — opencode-стриминг
  tool calls совместим (фиксы под opencode в 0.1.40, opt-in `tool_call_recovery`); наши
  механизмы reasoning (`reasoning_effort`, `enable_thinking: false`) поддержаны, `none/off` +
  `low|medium|high` (наш `xhigh` без документации на chat-пути); agentские гэпы — forced tool
  choice, structured outputs + tools, cold re-read при интерливинге sub-agents — сведены в
  чеклист живого теста.

- [Strata на этом железе: факты развертывания](issues/01-strata-hardware-facts.md) — 5070 Ti
  поддерживается, P2P-патч драйвера вне пути Strata; схема `--gpus 0,1` + `vram-reserve-later-mib`
  (GPU0 300 / GPU1 2048 MiB) как механика красной линии; на 59 GiB для IQ3_XXS/IQ3_S ожидаем
  auto low-ram (контекст ≤ 64K/128K), IQ2_XS влезает целиком; установка одной командой,
  порт `--port 8081`, `--calibrate` перед матрицей.
- [Опубликованные данные качества и скорости](issues/04-published-quality-data.md) — есть
  точный community-аналог железа (5070 Ti 16 GB + 64 GB RAM, IQ3_S @262K: 38–42 tok/s,
  prefill 920–1200); IQ3_S на наших 59 GiB впритык, риски — тихие деградации под RAM-пресурой,
  не OOM; качество: IQ3_S 87.69 % top-token match vs Q8_0, IQ3_XXS 84.46 %, IQ2_XS — не публикуется.
- [Финальный протокол замеров](issues/06-benchmark-protocol.md) — протокол утверждён
  (grilling, все решения пользователя): калибровка каждой модели до её матрицы, замер —
  калиброванного состояния (дельта-микробенч до/после — один раз на IQ3_XXS); vision — mmproj
  Q8_0 на все размеры, текст без encoder-резерва, smoke с картинкой при **CPU-encoder — наш
  стандарт использования** (fallback GPU-elastic); гэп-проверки opencode (forced choice,
  structured outputs + tools, невалидный effort, `xhigh`) — разово на модель, side-запрос +
  prefix-cache — наблюдением в каждой агент-сессии; **параллелизм не цель: `parallel: 1`,
  batching не замеряем, приоритет — контекст**; потолки: IQ3_S 64K, IQ3_XXS 128K, IQ2_XS до
  262 144 по стартовой строке (≥ 1 GiB свободной VRAM на карте); нагрузки — bench.sh
  chat/16K/32K + потолочный пробой ×3 + agent-session (bench + живая opencode) + многотуровый
  чат до красной линии RAM + soak; артефакты per-model в `assets/` (+ `status.md` —
  статус-борд многосессионного прогона, `summary-matrix.md` — свод по окончании), watch.log
  per-model 2 с; пороги: VRAM GPU1 ≥ 512 MiB, swap > 2 GiB, 200 MB/s NVMe вне prefill,
  120 c hang + политика ретранов (1 ретран, environment-retry, перенос сценариев между
  сессиями); порядок XXS→S→XS, RAM-сбой XXS пропускает S, нерam-сбой порядок сохраняет.

## Not yet specified

- (пусто — карта завершена; RAM-вопрос «что дальше, если 3-бит не держат» разрешен
  матрицей и перелит в тикет 08, тикет 08 разрешен отчетом и решением)

## Out of scope

- **Unsloth UD-IQ4_XS и вся семья UD-Q4_K_XL+**: исключены по RAM-бюджету (экспертам нужно
  ~72 GB RAM, у вас 59 GiB) — официально описанный SSD-стриминг даёт ~7–8.5 tok/s. Решение
  зафиксировано картой; вернётся только при апгрейде RAM как новое усилие.
- **Апгрейд RAM (до 96+ GB)** — инфраструктурное решение вне этой карты.
- **Интеграция выбранной модели в llama-swap** (конфиги, профиль, конвертация, ADR, мульти-
  размерное переключение `run-<model>.sh`, мониторинг llm-monitoring для Strata) — следующее
  усилие; для отчета собирается только feasibility (тикет Feasibility: llama-swap и Strata).
- **Формальные бенчмарки качества** (eval-харнесс, SWE-bench-прогоны на локальной машине).
- **vLLM и другие движки** — вне картины.
