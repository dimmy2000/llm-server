# AGENTS.md

Docker-стек локального LLM-инференса: единый маршрутизатор llama-swap с тремя
взаимоисключающими движками — двумя в контейнере (llama.cpp и NInfer) и одним
нативным на хосте (Strata, systemd-юнит) — плюс отдельный compose-профиль
vLLM, выведенный из текущей топологии. Прикладного кода, тестов, CI и линтинга
нет. Не выдумывать `make`, `npm`, `pytest` и подобные команды.

## Общая архитектура

Корневой `docker-compose.yaml` задает имя проекта `llm-server` и через
`include` подключает `router/docker-compose.yaml` и `vllm/docker-compose.yaml`.

- Единственный сервис роутера `llama-swap` поднимается всегда (сервис без ключа
  `profiles:`), контейнер — `llama-swap`, образ — `llm-server/router:v265`
  (собирается из `router/Dockerfile`). В образе запинены llama-swap **v265**,
  llama.cpp **b10438** и NInfer **v0.4.6**; оба движка запускаются llama-swap
  как дочерние процессы через `cmd`. Отдельных контейнеров движков нет,
  `docker.sock` не монтируется.
- Публичный API — `http://localhost:8080`, три model-ID: `qwen3.8-27b`
  (llama.cpp или NInfer по активному профилю `llama`/`ninfer`) и `strata-iq3` /
  `strata-iq2` (нативная Strata на хосте, см. «Движок Strata»). Движки никогда
  не работают параллельно — доступ строго последовательный, ровно один бэкенд
  резидентен. Переключение ролей — через `scripts/strata/strata-use.sh`
  (см. «Переключение ролей»); автоматического swap по запросу нет
  (дефолтная exclusive-группа, селекторов нет, backend'ы `unlisted` с пинами).
- Профили llama-swap: `llama`, `ninfer`, `strata-iq3`, `strata-iq2` (шим-модели
  страта-ID — в `router/config.d/30-strata.yaml`). В родительских профилях
  strata-ID закрыты пинами `~`, в страта-профилях закрыты родитель
  `qwen3.8-27b`, оба родительских backend'а и соседний размер.
- Профиль `vllm` (сервис `vllm-server`) — отдельная топология на том же
  `:8080` и тех же GPU; вне текущего усилия, одновременно с роутером не
  запускать.
- Пины версий: llama-swap v265 (SHA-256 архива в build-args), llama.cpp
  `server-cuda13-b10438@sha256:bb81f3e4…6283` (образ ggml-org), NInfer
  `ninfer-tp2 v0.4.6` (SHA-256 архива). Обновление движка = новый пин/тег в
  `router/Dockerfile` + новые build-args + `docker compose build llama-swap`.

Решения — ADR-0006 (`docs/adr/0006-single-endpoint-llama-swap-orchestrator.md`)
и ADR-0007 (`docs/adr/0007-strata-llamaswap-sequential.md` — Strata, три
публичных ID, последовательный доступ); проверка на живом железе —
`docs/research/0014`, `0015` (роутер), `docs/research/0016` (Strata);
доказательства — `.scratch/llama-swap-orchestrator/assets/` и
`.scratch/strata-integration/assets/`.

## Единый контракт

Конфигурация роутера: `router/config.yaml` (глобалы, hooks, профили с пинами)
+ `router/config.d/10-llama.yaml`, `20-ninfer.yaml` и `30-strata.yaml` (по
одному движку на файл). Изменение любого из них требует `docker compose
restart llama-swap` (для правок `router/config.yaml` подменой файла —
`up -d --force-recreate`, см. «Команды»).

- Публичных ID три — `qwen3.8-27b`, `strata-iq3`, `strata-iq2`; все видны в
  `/v1/models` (под страта-профилем — две записи: родитель исчезает из
  листинга при пине `~`, семантика пинов v265). `status: unloaded` у
  пин-записи — косметика llama-swap (hardcode для пинов, v265 api.go);
  правдивое состояние — `GET /api/profiles`, SSE `/api/events` или
  `/health` upstream-порта (issues/12, ADR-0006).
- Backend-модели `backend-llama`/`backend-ninfer` скрыты (`unlisted: true`) и
  закрыты пином `~` в неактивном профиле (прямой запрос → `404`).
- Старт: `hooks.on_startup` — активен `ninfer` с прелоадом `backend-ninfer`
  (~6 c), публичный ID есть сразу. Строки `[ERROR] failed to preload model
  backend-ninfer: status 404` в старте — косметика: у NInfer нет
  warmup-эндпоинта, прелоад при этом запускает и прогревает движок.
- `sendLoadingState: false` (issues/13, ADR-0006): баннер загрузки llama-swap
  стримится только в `delta.reasoning_content` — канал зашит в код
  (`internal/router/loading.go`), потребителей нет. Плата: первый запрос после
  переключения молчит 40–60 c (llama.cpp) без in-stream индикатора.
- Reasoning задаёт клиент; сервер мнения не задаёт. Голый ID = дефолт chat
  template (thinking + `xhigh`) на обоих движках. Переносимый контракт:
  выключить thinking — `chat_template_kwargs: {"enable_thinking": false}`;
  уровень — `reasoning_effort: low|medium|xhigh` (top-level или в kwargs).
  Top-level `none` выключает thinking только на NInfer (на llama.cpp инертен:
  CLI-флаг `--reasoning on` в `cmd` инжектит `enable_thinking: true`, который
  побеждает; разбор — `docs/research/0015`). Невалидное значение → `500`
  (llama) / `400` (NInfer).
- Контракт strata-ID (детали — «Движок Strata», ADR-0007): словарь reasoning
  движка `none|low|medium|high` (top-level и `chat_template_kwargs` через
  `:8080` работают оба; `xhigh` принимается, но неотличим от `high` — не
  предлагается), невалидное значение → `400`; tool calls работают
  (forced tool choice → 200), structured output + tools → `400`. Strata
  отрабатывает любой `model` запроса (`useModelName` шимам не нужен), но
  поле `model` в **ответе** — канон native-ID
  (`qwen3.8-flash-next-iq3_xxs`/`…-iq2_xs`), llama-swap его не переписывает:
  не сверять `model` ответа с запрошенным ID. `repetition_penalty`
  стрипается и на страта-шимах. Диагностика отказов strata-ID: `404 no model
  id could be identified` — активен родительский профиль (пины `~`), strata-ID
  через opencode/UI напрямую недостижимы — переключить роль
  `scripts/strata/strata-use.sh strata-iq3|strata-iq2`; `500 upstream command
  exited prematurely` (~1.5 c) — профиль strata активен, но нативный юнит не
  запущен (llama-swap не умеет стартовать процессы хоста) — та же команда.
  Выбор модели в opencode/UI переключателем ролей НЕ является.
- opencode v2 управляет reasoning вариантами модели, конфиг
  `~/.config/opencode/opencode.jsonc` (issues/14, доп. 2026-10-18; страта-ID
  добавлены 2026-10-19, тикет 03 карты strata-integration). Три модели в
  `providers.llama-swap` (`http://localhost:8080/v1`): `qwen3.8-27b` —
  варианты `body.chat_template_kwargs`: `off` (instruct) и `low|medium|xhigh`
  (`reasoning_effort`); `strata-iq3` (context 131072) и `strata-iq2`
  (262144) — варианты top-level `reasoning_effort`: `off`→`none`,
  `low|medium|high` (словарь движка; `xhigh` не даётся), у обеих
  `compatibility.reasoningField: "reasoning_content"`. Второй путь к
  родителю: `providers.self-hosted`
  (bifrost-шлюз `http://192.168.17.69:9000/v1`, ID `llama/qwen3.8-27b`) —
  шлюз стрипует `chat_template_kwargs`/`options`, поэтому variants только
  `low|medium|xhigh` на top-level `reasoning_effort` (единственное, что шлюз
  досылает; instruct через шлюз недостижим). `self-hosted` в v2-форме
  `providers` (legacy-блок `provider` для этого ID не работает: варианты
  ложатся под `options.body`, при конфликте ID v2 выигрывает и legacy-блок
  пропускается); `provider.openai` в legacy-форме оставлен.
- Sampling — серверный дефолт движка, клиентские поля перекрывают: пресет
  llama.cpp — CLI-флаги в `cmd` (`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0
  --presence-penalty 0 --repeat-penalty 1.0`), NInfer — mode-aware пресет
  движка (thinking `1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5`).
  llama-swap тело запроса правит только `stripParams: repetition_penalty` на
  обоих и `useModelName: qwen3.8-27b` на `backend-ninfer`.
- Безопасное подмножество параметров клиента (оба движка; полная таблица —
  ADR-0006, сводка — `docs/research/0013`): `temperature` `[0,1]`, `top_p`
  `(0,1]`, `top_k` `1..20` (не 0 — на NInfer это cap top-20), `min_p` `[0,1]`,
  `presence_penalty`/`frequency_penalty` `[-2,2]`, `seed`, `max_tokens ≥ 1`,
  `reasoning_effort` из `none|low|medium|xhigh`,
  `chat_template_kwargs.{enable_thinking, preserve_thinking}` (bool).
  Непереносимо: `repetition_penalty` (стрипается), `repeat_penalty`
  (llama.cpp-only, NInfer молча игнорирует), `top_k: 0`, `reasoning_effort`
  вне словаря, NInfer-несовместимые фичи (`response_format: json_object`,
  `logit_bias`, `logprobs`, `strict`, `parallel_tool_calls: false`, named tool
  choice).
- Старые публичные ID (`qwen3.8`, `qwen3.8-27b-instruct`, алиасы
  `-chat-*`/`-agent-*`, а также `ornith-9b*`) удалены без backcompat-алиасов
  (ADR-0004, ADR-0006); миграция внешних потребителей выполнена (opencode,
  `bench.py`).

## Переключение ролей

Роли: `llama`, `ninfer`, `strata-iq3`, `strata-iq2`, `off`. **Обычный путь —
всегда `scripts/strata/strata-use.sh <роль>`** — единственная точка правды
(коды выхода 0–7, идемпотентен; RAM-гейты, health-дискриминатор и порядок
внутри; см. «Движок Strata» и `scripts/strata/README.md`). Ручной путь ниже —
только для родительских ролей `llama`/`ninfer`, когда трогается исключительно
профиль llama-swap:

1. Убедиться, что текущие генерации завершились (выполняющийся запрос
   продолжается на старом движке).
2. `curl -X PUT http://localhost:8080/api/profiles/active -H 'Content-Type:
   application/json' -d '{"name":"llama"}'` (или `"ninfer"`, или UI llama-swap
   на `:8080`).
3. Проверка: `GET /api/profiles` (поле `active`), `GET /v1/models`.
4. Смена профиля сам движок не грузит: swap происходит на первом запросе к
   `qwen3.8-27b`, и он платит загрузку весов — llama.cpp 40–60 c, NInfer ~6 c;
   при `sendLoadingState: false` запрос молчит, индикатор — только логи
   контейнера.
5. Движки не работают параллельно: exclusive-группа выгружает старый движок до
   старта нового. При OOM/зависании — логи контейнера и `nvidia-smi` (красная
   линия: ≥ 512 MiB свободной VRAM на дисплейной GPU1). Порт `8080` общий с
   vLLM-профилем — одновременно не запускать.

### Аварийный ручной путь

Когда `strata-use.sh` недоступен или отказал (exit 1–7) — переключение
ролей руками, строго в порядке runbook: останов/старт юнита `systemctl`,
unload родителя `POST /api/models/unload`, RAM-гейты, симлинк
`/etc/strata/active.json`, ожидание `/health` на `172.17.0.1:8081` с нужным
`model`+`loaded`, затем `PUT /api/profiles/active`. Пошагово —
`docs/runbook-strata.md`; метрики и логи — там же (`journalctl -u strata`,
файл-лог движка, красные линии). Нарушение порядка = OOM VRAM или
рассинхрон «профиль ↔ резидентный размер».

## Движок llama.cpp (backend-llama)

- Параметры ядра — только в `router/config.d/10-llama.yaml` (секция `cmd`);
  конфигурация модели и пинов — в `router/config.yaml`.
- Пин llama.cpp **b10438** — бамп с b10068 ради top-level `reasoning_effort`
  (issues/11); A/B на протоколе 0005 регресса не показало (prefill +5–7 %,
  decode в пределах разброса, wall-clock равен или лучше) — `docs/research/0015`.

Модель хоста:
`/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`,
внутри контейнера
`/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`.

Qwen3.8-27B: 65 слоёв, полное внимание каждые 4 слоя (17 слоёв с KV-cache,
остальные SSM без KV). NVFP4-MTP квантизация тира HIGH (файл ~17.6 GB) со
спекулятивным декодированием (`--spec-type draft-mtp,ngram-mod` …): ngram-mod
(приоритет 4) работает первым, draft-mtp (приоритет 8) — fallback. MTP-draft
KV — отдельный `llama_kv_cache` на один слой nextn, глубиной в полный ctx,
целиком на GPU1; `--spec-draft-type-k/v q8_0` ужимает его. Требуются
`--split-mode tensor` и `--tensor-split 50,50` в паре: дефолтный LAYER-режим
копит KV на дисплейной GPU1 и при большом ctx падает OOM на первом decode.
`--parallel 1`: один слот, KV строго под ctx. Узкое место VRAM — дисплейная
GPU1 (9 KV-слоёв): проверенный стабильный максимум — `--ctx-size 180224`, на
196608 первый decode падает OOM (flash-attn workspace). Под пиковой нагрузкой
(жатренный prefill 62–159k + генерация) GPU0 ~1.26 GiB свободно, GPU1
~1.75 GiB. `--cache-idle-slots` и `--cache-ram 40960` сериализуют KV в RAM при
завершении запроса (prefix reuse), но НЕ освобождают VRAM. `--ctx-checkpoints`
не включены; `--fit off`: контекст задаётся явно. Красная линия подтверждена
на b10438: GPU1 min 1345 MiB (`assets/15-verify-b10438/`).

## Движок NInfer TP=2 (backend-ninfer)

- Движок — релиз `ninfer-tp2 v0.4.6` из форка `ValerioDolci/ninfer-tp2`
  (upstream `Neroued/ninfer` одноплатовый); по C++-дереву v0.4.6 == v0.4.7
  (release notes v0.4.7: «the C++ tree is the same as v0.4.6, v0.4.6 tarball
  runs it»), у v0.4.7 published-ассетов нет, поэтому ставим архив v0.4.6.
  v0.4.6 — минимум, требуемый артефактом. SHA-256 архива зафиксирован в
  build-args `router/docker-compose.yaml`/`router/Dockerfile` и проверяется на
  сборке. Обновление движка = новый тег образа + новые `NINFER_*` build-args +
  `docker compose build llama-swap`.
- Аргументы `ninfer-serve` — только в `router/config.d/20-ninfer.yaml`
  (секция `cmd`); `ninfer-serve` отклоняет запрос, если `request.model` не
  равен `--model-id`, поэтому на записи обязателен
  `useModelName: qwen3.8-27b`; пер-модельный `env` обязан ставить
  `/opt/ninfer/lib` первым в `LD_LIBRARY_PATH` (своего RPATH у бинарника нет,
  иначе подхватывает `libcudart.so.13` из CUDA 13.3).
- Модель хоста:
  `/opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/qwen3_8_27b_nvfp4.ninfer`
  (артефакт `glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer`, 21.54 GB;
  весовая часть побитово равна официальному `neroued/Qwen3.8-27B-nvfp4-NInfer`
  — greedy-выход совпадает, — отличается только блок DFlash2: NVFP4-драфтер и
  proposal-голова), внутри контейнера тот же путь от `/models`. Скачивание с
  проверкой SHA-256: `./router/fetch-model.sh`.
- Базовый профиль (тикет 13, 2026-10-08): `--tp 2 --devices 0,1`,
  `--kv-dtype nvfp4`, `--max-context 262144` (позиционный потолок артефакта),
  `--kv-capacity auto --vram-headroom-mib 640`, `--max-concurrency 2`,
  `--device-state-slots 4` (всего C+H=6), `--spec dflash2 --draft-tokens 7
  --lm-head-draft`, `--vision --vision-device 0 --max-vision-tokens 4096`,
  `--embedding-host`, `--default-max-tokens 16384`,
  `--pending-timeout-ms 600000`. `auto` берёт пул из остатка VRAM с запасом
  `--vram-headroom-mib` (640); фактическая свободная VRAM видна в стартовой
  строке движка `capacity | KV … auto | … free … MiB`. Порог проекта —
  ≥ 512 MiB на дисплейной GPU1. Одиночный запрос достигает модельных 262144;
  промпт сверх ёмкости отклоняется чистым `400 context_length_exceeded`.
  `--vision-device 0` — плата без дисплея: башня Vision и draft-стадии живут
  на ней, дисплейная GPU1 должна сохранять ≥ 512 MiB.
- `--host-state-slots` и `--host-kv-mib` на `--tp 2` обязаны быть 0: удерживаемые
  диалоги живут только в device-state слотах, при вытеснении их следующий turn
  префиллится заново. `device-state-slots 4` при `--max-concurrency 2` дают
  стартовый лог `context cache | 2 active + 4 cached device states`;
  удержанные сессии отвечают за ~0.15 с против ~2.4 с полного префилла.
- DFlash2: на tp2 `--lm-head-draft` обязателен (без него движок падает на
  старте), драфтер разделён между ранками. Бэкенд спекуляции выбирается только
  на старте, поэтому откат к MTP — правка `cmd` на `--spec mtp --draft-tokens
  3` в `20-ninfer.yaml` и `docker compose restart llama-swap`, без пересборки.
  Разбор — раздел «DFlash2 на этой машине» в `docs/research/0009-…`.
- `nvfp4` KV — пул в ~1.8× плотнее `int8`, префилл −1.3…−1.6 %, decode в
  пределах разброса, приём MTP совпадает. Качество 4-битного KV локально не
  проверено — главная открытая оговорка.
- Две полосы: llama-swap пропускает до 10 параллельных запросов на модель
  (дефолтный `concurrencyLimit`), движок держит 2 активных, decode двух
  диалогов идёт одновременно. Префиллы при этом **сериализуются**: префилл
  второго запроса ждёт префилл первого (150k×2 → `queue 55 с` у второго,
  60k×2 → `queue 15 с`; это поведение движка, не пула).
- Железо и разбор tp2 (VRAM-бюджет, пределы по слотам и контексту, mailbox vs
  p2p, `--embedding-host`, сравнение артефактов, замеры против llama.cpp) —
  в `docs/research/0009-ninfer-tp2-two-5070ti.md`. Решения — ADR-0003. Прежний
  профиль и sweep — в git-истории удалённого `ninfer/config.yaml`.

Замеры ниже — прежний профиль (официальный артефакт, v0.4.5, MTP3, 2026-10-05),
сохранены как база сравнения:

- Движок готов через 6.1 с после старта контейнера, веса 18.5 GiB читаются за
  4.5 с (4.07 GiB/s); `p2p off (host-staged copies)`, mailbox захвачен, probe
  0.03 ms; `--embedding-host` уводит 1.18 GiB в host-mapped.
- Prefill: 4597 tok/s на 30k, 3319 tok/s на 98 849 (TTFT 29.8 с), 2605 tok/s на
  164 733 (TTFT 63.2 с). llama.cpp на тех же картах — 1372 tok/s на 90k
  (выигрыш 2.42×). Decode: 130.1 tok/s (1880 токенов), 131.5 tok/s (4834),
  106.3 tok/s на контексте 131 830 (llama.cpp 80.5 tok/s, 1.63×). Приём MTP
  46–48 %.
- Минимум свободной VRAM под нагрузкой (префилл 165k + генерация): GPU0
  2018 MiB, GPU1 1501 MiB. KV-пул не растёт от длины запроса.
- Effort — не бюджет токенов, а инструкция в системном промпте от chat
  template артефакта: `xhigh` дошёл до лимита `max_tokens: 16000`, `low`
  закрыл рассуждение сам на 12 254 токенах. `preserve_thinking: false`
  вырезает reasoning из промпта следующего turn (352 → 246 токенов).
- Tool calls работают; Vision отвечает верно по картинке (99 prompt-токенов).

Не проверено: качество при 4-битном KV, приём драфта и decode DFlash2 на
glfenix-артефакте, минимум свободной VRAM на `auto`/640/H=4 — тикеты
`.scratch/ninfer-tp2/`.

## Движок Strata (нативный, strata-iq3 / strata-iq2)

- Движок — нативная установка Strata (Qwen3.8-Flash-Next) на хосте
  `/opt/strata`, сборка 0.1.44-линейки на CUDA 13.3; llama-swap его **не
  запускает и не останавливает** — подключение через shim-модели
  (`router/config.d/30-strata.yaml`): `cmd` — watchdog-пустышка
  (`while curl /health …`), `proxy: http://host.docker.internal:8081`,
  `checkEndpoint: /health`. Fast-fail при остановленном движке даёт сам
  watchdog (~2 c → `prematureExit`): пер-модельный `healthCheckTimeout` в
  v265 не работает (`config/load.go:136` перезаписывает его глобальными
  600 c). Сеть: движок привязан к `172.17.0.1` (docker0) — с LAN не виден;
  контейнер достаёт через `extra_hosts: host-gateway`. Решение — ADR-0007,
  выбор размеров — `docs/research/0016-strata-flash-next-selection.md`.
- Два размера (выбор 0016; последовательный доступ — эксперты 43 + 35.5 GB
  не живут резидентно вместе при 59 ГиБ RAM):
  `strata-iq3` = IQ3_XXS @131072 (конфиг `/opt/strata/strata-iq3_xxs.json`,
  native-ID `qwen3.8-flash-next-iq3_xxs`) и `strata-iq2` = IQ2_XS @262144
  (`/opt/strata/strata-iq2_xs.json`, `qwen3.8-flash-next-iq2_xs`).
  IQ3_S (`strata-iq3_s.json`) — runner-up, вне карты: возвращается отдельным
  тикетом при починке апстрим-блокера `--resident-experts`. Конфиги движка
  (port 8081, host 172.17.0.1, model_name) зафиксированы — `scripts/strata`
  их не изменяет.
- Единственный формат запуска: `python serve/server.py --engine strata
  --config <json> --port 8081` (из `/opt/strata`). HTTP-порт берётся
  **только из CLI** (дефолт 8095 — `--port 8081` обязателен), host —
  **только из конфига** (172.17.0.1).
- Юнит `strata.service` (`scripts/strata/`, установлен симлинками в
  `/etc/systemd/system/`): **linked, НЕ enabled** (после ребута VRAM не
  захватывается в обход родительского профиля — проверено cold-имитацией),
  `Restart=no`; `ExecStartPre` отказывается без симлинка
  `/etc/strata/active.json` → конфиг размера (ставит только скрипт).
  `ExecStop` (`/usr/local/sbin/strata-stop` ← `scripts/strata/strata-stop`)
  добивает дерево: TERM (server.py, engine/strata, strata-vision) →
  ждать ≤ 10 c → KILL, + `KillMode=control-group`, `TimeoutStopSec=25`
  (SIGTERM server.py однажды проглотился, движок-ребёнок держал VRAM/RAM).
- Оркестратор — **единственная точка правды переключения**:
  `scripts/strata/strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}`
  (идемпотентен). Порядок перехода на Strata обязателен: останов юнита →
  `POST /api/models/unload` (убивает родителя, page-locked RAM 47/36 ГиБ
  уходит за секунды; при резидентном родителе старт = OOM VRAM) → RAM-гейт
  available ≥ **46 ГиБ** (iq3) / **36 ГиБ** (iq2), иначе exit 5 → симлинк →
  `systemctl start strata` → ждать `/health :8081` с **нужным** `model` +
  `loaded: true` (дискриминатор рассинхрона: `/health` отвечает 200 при
  любом размере; iq3 ~20–24 c, iq2 ~14 c) → только затем `PUT` профиля.
  Коды выхода: 0 ок · 1 аргумент · 2 API/профиль · 3 юнит/конфиг ·
  4 дерево не добито · 5 RAM-порог · 6 таймаут /health · 7 VRAM не
  освободилась.
- RAM/VRAM-рамки: 59 ГиБ RAM; page-locked 47/36 ГиБ; после переходов
  available 52–57 ГиБ; красная линия GPU1 ≥ 512 MiB держится (под Strata
  1671–1707 MiB, минимум цикла 709 MiB при резидентном ninfer). Своп —
  только транзиентные si/so-всплески 2–3 c на старте iq3.
- Проверено верификацией (тикет 04, цикл ×2, 10/10 шагов): тайминги
  воспроизводимы (iq3 26–29 c, iq2 20 c на переход; родители ~4 c + прогрев
  8–12 c), санити-decode iq3 132–133 / iq2 134–138 tok/s (нормы 130/145
  ±20 %), admission MTP 72–81 %, гэп-профиль совпадает с 0016, vision smoke
  на CPU-энкодере корректен (`strata-vision` на CPU — наш стандарт, GPU не
  занимает; mmproj Q8_0).
- Нюансы reasoning: словарь движка **`none|low|medium|high`**; `xhigh`
  принимается (200), но статистически неотличим от `high` (6 сэмплов:
  3799 vs 3806 completion tokens) — в opencode для strata-ID не даётся.
  Невалидное значение → `400`. Обе механики через `:8080` работают
  (top-level `reasoning_effort` и `chat_template_kwargs`).
- Лимиты и риски (0016 §6; у нас не воспроизведены, но относимы):
  CJK-коллапс на длинных выводах; агрессивный thinking — обрыв ответа внутри
  `</think>` без закрытия → агент молча останавливается; задавать
  `max_tokens` с запасом ≥ 12–16K; деградации под RAM-пресурой на длинных
  сессиях. **Каждая смена версии движка — новая точка калибровки** и
  smoke-check кванта. Наблюдение пилота: следить за деградациями #1944-типа
  (single-token после ~12K), CJK, thinking-обрывами, RAM-прессурой.
- Метрики: `journalctl -u strata -f` (логи server.py: запуск/останов,
  decode/admission-строки) + файл-лог движка `/opt/strata/strata-*.log` +
  собственный мониторинг движка. llm-monitoring (promtail/Loki/Grafana)
  выключен (7 контейнеров stopped, `unless-stopped`) и вне топологии; его
  останов освободил `:8081` — при возврате сначала увести его cadvisor с
  8081.

## Профиль vLLM

- Единственный сервис `vllm-server` напрямую публикует `:8000` контейнера на
  `:8080` хоста.
- Compose-настройки находятся в `vllm/docker-compose.yaml`.
- Аргументы `vllm serve` находятся в `vllm/config.yaml`.
- Модель хоста: `/opt/models/Qwen3.8-27B-NVFP4/`, внутри контейнера
  `/models/Qwen3.8-27B-NVFP4`.
- Публичный model-ID: `qwen3.8-27b`.
- Используются обе RTX 5070 Ti через tensor parallelism 2.
- Vision encoder отключен флагом `language-model-only`, чтобы оставить VRAM
  под FP8 KV-cache.
- Базовый профиль использует `max-model-len: 49152`,
  `max-num-seqs: 1`, `max-num-batched-tokens: 1024` и
  `gpu-memory-utilization: 0.85`, чтобы оставить место графической сессии на
  второй GPU. Под пиковой нагрузкой на GPU1 должно оставаться не менее 512 MiB
  физически свободной VRAM.
- FlashInfer autotune отключен: его временная аллокация вызывает OOM и
  зависание startup на GPU с графической сессией.
- Клиентские sampling-параметры не удаляются.
- Thinking включен шаблоном модели по умолчанию и управляется через
  `reasoning_effort` или `chat_template_kwargs.enable_thinking`.
- Tool calls разбираются parser `qwen3_xml`, reasoning parser `qwen3`.

Не включать MTP, TurboQuant KV-cache, prefix caching или FlashInfer autotune
без отдельной проверки длинных streaming-ответов и запаса VRAM.
`max-num-seqs: 1` означает, что второй конкурентный запрос ожидает scheduler.
Не повышать `gpu-memory-utilization` только ради startup-проверки KV cache.
Максимальный стабильный context limit определяется отдельным cold-start и
нагрузочным тестом. На текущей машине проверен limit `49152`; `65536` не
проходит startup из-за недостаточного KV cache.

Изменение `vllm/config.yaml` требует перезапуска `vllm-server`.

## Команды

```bash
# Роутер (llama.cpp + NInfer + strata-шимы; сервис без compose-профилей)
docker compose up -d --wait --wait-timeout 1800
docker compose logs -f llama-swap
docker compose restart llama-swap     # после изменения router/config*.yaml
docker compose build llama-swap       # после смены пинов в router/Dockerfile
docker compose down --remove-orphans  # остановит и vLLM, если поднят

# Переключение ролей (единственный обычный путь; sudo сам, коды выхода 0-7)
scripts/strata/strata-use.sh llama|ninfer|strata-iq3|strata-iq2|off

# Скачивание артефакта NInfer
./router/fetch-model.sh
```

Внимание: `router/config.yaml` смонтирован **одиночным файлом** — правка
подменой файла (rename редактором) меняет инод, и `docker compose restart`
продолжает видеть старое содержимое. Если правили подменой —
`docker compose up -d --force-recreate llama-swap`. `config.d/` смонтирован
директорией — там проблема невозможна, достаточно `restart`.

Публичный API роутера: `http://localhost:8080` (три ID). Переключение ролей —
`scripts/strata/strata-use.sh` (см. «Переключение ролей»); ручной
`PUT /api/profiles/active` — только для родительских ролей и аварийного пути
(`docs/runbook-strata.md`); compose-профилей, выбирающих движок, больше нет.

## Хост: патченный драйвер и P2P

Решение и цифры — ADR-0005, исследование — `docs/research/0010-p2p-two-5070ti.md`,
ops-ранбук (смена драйвера, обновление ядра, откаты, soak) — `docs/NVIDIA_P2P.md`.

- Драйвер хоста — open-модули ветки `615.71.09-p2p` форка
  `aikitoria/open-gpu-kernel-modules` + vanilla userland 615.71.09,
  nouveau в blacklist. Заменяет штатный apt `nvidia-driver-595-open`.
- GRUB содержит `amd_iommu=on iommu=pt` — это осознанный компромисс (см.
  ADR-0005), без него P2P не работает; снятие не планируется.
- P2P между картами подтверждается `nvidia-smi topo -p2p r/w` = OK/OK и
  стартовой строкой NInfer `tensor parallel ... p2p on` +
  `captured all-reduces: copies`. NInfer-профиль не имеет P2P-параметров
  (рантайм-детект `canPeer`); llama.cpp работает без `GGML_CUDA_P2P`
  (выигрыша нет, риск corruption по докам llama.cpp).
- HWE-ядро не пинится: после каждого обновления ядра пересобрать патченные
  модули (`./scripts/nvidia-p2p/rebuild-modules.sh`, алерт по vermagic —
  в ранбуке). После ребута/сборки прогонять `scripts/nvidia-p2p/p2p-verify.sh`
  и снимать снапшот `p2p-snapshot.sh` (бэкап GRUB и модулей).
- Красная линия «≥ 512 MiB свободной VRAM на дисплейной GPU1 под пиковой
  нагрузкой» на текущем ninfer-профиле держится не всегда: под долгими
  диалогами в device-state слотах + 90k-prefills зафиксирован минимум 19 MiB
  (тикет 07). Нарушение принято как документированный регресс текущего
  профиля (возможен вклад фоновых задач вне инференса) — при изменениях
  профиля следить за свободной VRAM GPU1 по стартовой строке движка.
- Важно: патченные модули переживают reboot без ручных действий (проверено
  двумя циклами).

## Локальные репозитории llama-swap и llama.cpp

Репозитории `llama-swap` и `llama.cpp` находятся на локальном диске в папке
родителе относительно этого проекта: `../llama-swap` и `../llama.cpp`.
Если нужно собрать информацию о работе этих проектов или прочитать их
документацию, обращаться к этим локальным репозиториям. Если их состояние
сильно отстало от текущих настроек инференса в проекте, предварительно
выполнить `git pull` в исследуемом репозитории.

## Сопутствующие проекты

- `scripts/port-forwarding-rules.ps1` (PowerShell Windows-хоста) — **устарел
  и не используется** (решение пользователя, 2026-10-19): достаточно, чтобы
  `:8080` был доступен по локальной сети — все три публичных ID идут через
  один порт роутера. Специального прохода к Strata `:8081` снаружи не
  требуется (и невозможен без DNAT: движок слушает только docker0).

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/` in this repo, one ticket per file. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage roles, each label string equal to its name — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` at the repo root plus `docs/adr/` for architectural decisions. See `docs/agents/domain.md`.
