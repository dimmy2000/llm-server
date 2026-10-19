# AGENTS.md

Docker-стек локального LLM-инференса: единый маршрутизатор llama-swap с двумя
взаимоисключающими движками (llama.cpp и NInfer) плюс отдельный compose-профиль
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
- Публичный API — `http://localhost:8080`, ровно один model-ID
  `qwen3.8-27b`. Какой движок за ним стоит, выбирает активный профиль
  llama-swap: `llama` или `ninfer`. Переключение только вручную
  (см. «Переключение движков»); движки никогда не работают параллельно,
  автоматического swap по запросу нет (дефолтная exclusive-группа, селекторов
  нет, backend'ы `unlisted` с пинами).
- **Черновик интеграции Strata (карта `.scratch/strata-integration/`, финал —
  ADR-0007):** публичных ID становится три — добавлены `strata-iq3` и
  `strata-iq2` (shim-модели из `router/config.d/30-strata.yaml`; нативный
  движок Strata на хосте, `:8081`, юнит + `strata-use.sh` — в работе).
  Профили `strata-iq3`/`strata-iq2`; в родительских профилях strata-ID
  закрыты пинами, последовательный доступ. Этот пункт заменится разделом
  «Движок Strata» по готовности юнита.
- Профиль `vllm` (сервис `vllm-server`) — отдельная топология на том же
  `:8080` и тех же GPU; вне текущего усилия, одновременно с роутером не
  запускать.
- Пины версий: llama-swap v265 (SHA-256 архива в build-args), llama.cpp
  `server-cuda13-b10438@sha256:bb81f3e4…6283` (образ ggml-org), NInfer
  `ninfer-tp2 v0.4.6` (SHA-256 архива). Обновление движка = новый пин/тег в
  `router/Dockerfile` + новые build-args + `docker compose build llama-swap`.

Решение — ADR-0006 (`docs/adr/0006-single-endpoint-llama-swap-orchestrator.md`);
проверка на живом железе — `docs/research/0014`, `0015`; доказательства —
`.scratch/llama-swap-orchestrator/assets/`.

## Единый контракт

Конфигурация роутера: `router/config.yaml` (глобалы, hooks, профили с пинами)
+ `router/config.d/10-llama.yaml` и `20-ninfer.yaml` (по одному движку на
файл). Изменение любого из них требует `docker compose restart llama-swap`.

- Публичный ID один — `qwen3.8-27b`; в `/v1/models` ровно эта запись.
  `status: unloaded` у пин-записи — косметика llama-swap (hardcode для пинов,
  v265 api.go); правдивое состояние — `GET /api/profiles`, SSE `/api/events`
  или `/health` upstream-порта (issues/12, ADR-0006).
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
- opencode v2 управляет reasoning вариантами модели, конфиг
  `~/.config/opencode/opencode.jsonc` (issues/14, доп. 2026-10-18). Два пути
  к локальной модели: `providers.llama-swap` (`http://localhost:8080/v1`, ID
  `qwen3.8-27b`) — варианты `body.chat_template_kwargs`: `off` (instruct) и
  `low|medium|xhigh` (`reasoning_effort`); `providers.self-hosted`
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
  launcher `llm-monitoring`, `bench.py`).

## Переключение движков

1. Убедиться, что текущие генерации завершились (выполняющийся запрос
   продолжается на старом движке).
2. `curl -X PUT http://localhost:8080/api/profiles/active -H 'Content-Type:
   application/json' -d '{"name":"llama"}'` (или `"ninfer"`, или UI llama-swap
   на `:8080`).
3. Проверка: `GET /api/profiles` (поле `active`), `GET /v1/models` (ровно
   `qwen3.8-27b`).
4. Смена профиля сам движок не грузит: swap происходит на первом запросе к
   `qwen3.8-27b`, и он платит загрузку весов — llama.cpp 40–60 c, NInfer ~6 c;
   при `sendLoadingState: false` запрос молчит, индикатор — только логи
   контейнера.
5. Движки не работают параллельно: exclusive-группа выгружает старый движок до
   старта нового. При OOM/зависании — логи контейнера и `nvidia-smi` (красная
   линия: ≥ 512 MiB свободной VRAM на дисплейной GPU1). Порт `8080` общий с
   vLLM-профилем — одновременно не запускать.

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
# Роутер (llama.cpp + NInfer; сервис без compose-профилей)
docker compose up -d --wait --wait-timeout 1800
docker compose logs -f llama-swap
docker compose restart llama-swap     # после изменения router/config*.yaml
docker compose build llama-swap       # после смены пинов в router/Dockerfile
docker compose down --remove-orphans  # остановит и vLLM, если поднят

# Скачивание артефакта NInfer
./router/fetch-model.sh
```

Публичный API роутера: `http://localhost:8080`. Переключение движка —
`PUT /api/profiles/active` (см. «Переключение движков»); compose-профилей,
выбирающих движок, больше нет.

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
- Важно: `llm-*` мониторинг и GPU-метрики (nvidia-smi-exporter) от драйвера
  не зависят; патченные модули переживают reboot без ручных действий
  (проверено двумя циклами).

## Локальные репозитории llama-swap и llama.cpp

Репозитории `llama-swap` и `llama.cpp` находятся на локальном диске в папке
родителе относительно этого проекта: `../llama-swap` и `../llama.cpp`.
Если нужно собрать информацию о работе этих проектов или прочитать их
документацию, обращаться к этим локальным репозиториям. Если их состояние
сильно отстало от текущих настроек инференса в проекте, предварительно
выполнить `git pull` в исследуемом репозитории.

## Сопутствующие проекты

- `scripts/port-forwarding-rules.ps1` запускается в PowerShell Windows-хоста,
  не внутри WSL или контейнера.
- Мониторинг находится в отдельном репозитории `llm-monitoring`
  (`infrastructure/llm-monitoring`). Его launcher `llm-stack.sh` принимает
  профиль вторым аргументом (`./llm-stack.sh up ninfer`) и передаёт его в
  `docker compose --profile`; базовый файл задаётся через `BASE_COMPOSE`.
  Роутер поднимается всегда, launcher мапит `llama`/`ninfer` на контейнер
  `llama-swap`, а для `vllm` исключает роутер (иначе конфликт за `:8080`);
  дашборды по имени контейнера `llama-swap` работают для обоих движков без
  правок.
  GPU-метрики (nvidia-smi-exporter, `gpus: all`) и promtail/Loki-логи
  контейнеров не зависят от профиля. Специфичные для llama.cpp панели
  (метрики сервера llama.cpp, API llama-swap) в дашборде отсутствуют — для
  `ninfer` это отсутствие, а не деградация; разбор по профилям — в README
  `llm-monitoring`, раздел «Панели по профилям».

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/` in this repo, one ticket per file. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage roles, each label string equal to its name — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` at the repo root plus `docs/adr/` for architectural decisions. See `docs/agents/domain.md`.
