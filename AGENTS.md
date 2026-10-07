# AGENTS.md

Docker-стек локального LLM-инференса с переключаемыми backend-профилями
llama.cpp, NInfer и vLLM. Прикладного кода, тестов, CI и линтинга нет. Не
выдумывать `make`, `npm`, `pytest` и подобные команды.

## Общая архитектура

Корневой `docker-compose.yaml` задает имя проекта `llm-server` и через
`include` подключает `llama/docker-compose.yaml`,
`ninfer/docker-compose.yaml` и `vllm/docker-compose.yaml`.

- Профиль `llama` публикует llama.cpp через `llama-swap`.
- Профиль `ninfer` публикует NInfer TP=2 через тот же `llama-swap`.
- Профиль `vllm` публикует OpenAI API самого vLLM.
- Все backend занимают порт `8080` и все GPU. Одновременно их не запускать.
- Без явно указанного профиля сервисы не запускаются.

Перед переключением всегда выполнять:

```bash
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans
```

## Профиль llama

- Единственный сервис `llama-swap` использует образ
  `ghcr.io/mostlygeek/llama-swap:cuda13` и публикует `:8080`; бинарник
  `llama-server` и CUDA-библиотеки входят в этот образ. Отдельного контейнера
  `llama-server` нет: модель запускается llama-swap как дочерний процесс
  через `cmd` (аргументы ядра в секциях `cmd` в `llama/config.yaml`).
- Параметры ядра (`--model`, `--ctx-size`, `--threads`, `--cache-type-*`,
  `--cache-ram`, `--cache-idle-slots`, `--flash-attn`, базовый sampling)
  находятся только в `llama/config.yaml`.
- Конфигурация модели и режимов находится в `llama/config.yaml`.
- В профиле одна модель — `qwen3.8-27b`, она прелоадится при старте
  (`hooks.on_startup.preload`): прогрев ~40–60 c, дальше первый запрос
  обслуживается сразу. Переключения моделей и ручного unload больше нет.

`llama-swap` удаляет клиентские параметры `temperature`, `top_p`, `top_k`,
`min_p`, `presence_penalty`, `repeat_penalty`; для `qwen3.8-27b` дополнительно
`reasoning`, `reasoning_effort`, `chat_template_kwargs`. Для llama-профиля
sampling и thinking управляются только через `setParamsByID` в
`llama/config.yaml`.

| ID | Назначение | reasoning |
|---|---|---|
| `qwen3.8-27b` | быстрые ответы | off |
| `qwen3.8-27b-chat-low` | чат, reasoning скрыт (preserve off), effort low | on |
| `qwen3.8-27b-chat-medium` | чат, reasoning скрыт (preserve off), effort medium | on |
| `qwen3.8-27b-chat-xhigh` | чат, reasoning скрыт (preserve off), effort xhigh | on |
| `qwen3.8-27b-agent-low` | агент, preserve on, effort low | on |
| `qwen3.8-27b-agent-medium` | агент, preserve on, effort medium | on |
| `qwen3.8-27b-agent-xhigh` | агент, preserve on, effort xhigh | on |

Изменение `llama/config.yaml` требует перезапуска `llama-swap`.

Старые публичные ID (`qwen3.8`, `qwen3.8-27b-instruct`,
`qwen3.8-27b-chat`, `qwen3.8-27b-agent-code`, `qwen3.8-27b-agent-plan`, а также
`ornith-9b`, `ornith-9b-thinking`, `ornith-9b-instruct`) удалены без
backcompat-алиасов; миграция внешних потребителей — отдельный процесс.
Модель Ornith 9B убрана из проекта целиком, решение — ADR-0004.

Модель хоста:
`/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`,
внутри контейнера
`/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`.
Алиас llama.cpp: `qwen3.8-27b`.

Qwen3.8-27B: 65 слоёв, полное внимание каждые 4 слоя (17 слоёв с KV-cache,
остальные SSM без KV). В llama-профиле используется NVFP4-MTP квантизация
тира HIGH (файл ~17.6 GB) со спекулятивным декодированием
(`--spec-type draft-mtp,ngram-mod --spec-draft-type-k q8_0
--spec-draft-type-v q8_0 --spec-draft-n-max 4 --spec-draft-p-min 0.75
--spec-ngram-mod-n-match 20 --spec-ngram-mod-n-min 4
--spec-ngram-mod-n-max 48`). ngram-mod (приоритет 4) работает первым,
draft-mtp (приоритет 8) — fallback. MTP-draft KV — отдельный
`llama_kv_cache` на один слой nextn, глубиной в полный ctx, целиком на GPU1;
по умолчанию он F16, а `--spec-draft-type-k/v q8_0` ужимает его (на 300 MiB
при ctx 163840 и больше при большем ctx). Требуются `--split-mode tensor` и
`--tensor-split 50,50` в паре: дефолтный LAYER-режим копит KV на дисплейной
GPU1 и при большом ctx падает OOM на первом decode (`cublasCreate_v2` в
common.cuh). `--parallel 1`: один слот, KV строго под ctx, без unified
KV-пула. Узкое место VRAM — дисплейная GPU1 (9 KV-слоёв: 8 full-attn +
nextn): при `--ctx-size 262144` и 196608 модель не работает — на 196608
KV-буферы аллоцируются, но первый же decode падает OOM (flash-attn workspace);
проверенный стабильный максимум — `--ctx-size 180224`. Под пиковой нагрузкой
(жатренный prefill 62–159k токенов + генерация) GPU0 ~1.26 GiB свободно,
GPU1 ~1.75 GiB (дисплей, требование ≥512 MiB выполнено). При `--parallel 1`
`--cache-idle-slots` и `--cache-ram 40960` сериализуют KV в RAM при
завершении запроса (prefix reuse для повторных запросов), но НЕ освобождают
VRAM (освобождение через unified KV — только при `--parallel -1`).
`--ctx-checkpoints` не включены; `--fit off`: контекст задаётся явно.

## Профиль ninfer

- Единственный сервис `ninfer-swap` собирается из `ninfer/Dockerfile`
  (`ubuntu:26.04` + готовые бинарники движка + статический `llama-swap` из
  образа llama-профиля), публикует `:8080`, имя контейнера — `llama-swap`.
  Имя сервиса обязано отличаться от `llama-swap` в llama-профиле: compose
  `include` молча сливает сервисы с одинаковым именем (проверено на compose
  5.5.1).
- Отдельного контейнера `ninfer-serve` нет: движок запускается llama-swap как
  дочерний процесс через `cmd` в `ninfer/config.yaml`. Аргументы
  `ninfer-serve` находятся только там.
- Движок — релиз `ninfer-tp2 v0.4.5` из форка `ValerioDolci/ninfer-tp2`
  (upstream `Neroued/ninfer` одноплатовый). SHA-256 архива зафиксирован в
  `ninfer/Dockerfile` и проверяется на сборке, `container_version` и
  `cuda_architecture` берутся из манифеста артефакта. Обновление движка = новый
  тег образа + новые `NINFER_*` build-args + `docker compose --profile ninfer
  build`.
- Модель хоста: `/opt/models/Qwen3.8-27B-nvfp4-NInfer/qwen3_8_27b_nvfp4.ninfer`
  (официальный артефакт `neroued/Qwen3.8-27B-nvfp4-NInfer`, 23.7 GB, веса
  20.9 GiB, компоненты text + vision + mtp + dflash2), внутри контейнера тот
  же путь от `/models`. Скачивание с проверкой SHA-256:
  `./ninfer/fetch-model.sh`.
- Базовый профиль: `--tp 2 --devices 0,1`, `--kv-dtype nvfp4`,
  `--max-context 262144 --kv-capacity 495104`, `--max-concurrency 2`,
  `--device-state-slots 3`, `--spec mtp --draft-tokens 3`,
  `--vision --vision-device 0 --max-vision-tokens 4096`, `--embedding-host`.
  Переключение с прежнего `int8` 241664 / C=1 / H=4 — тикет 12 (2026-10-07):
  nvfp4 и две полосы для теста в рабочих задачах; общий порог проекта
  ≥ 512 MiB на дисплейной GPU1 (для добавления слота ради +1 слота удержания диалогов).
  Startup-sweep (nvfp4, C=2, `--max-context 262144`), свободно после старта
  MiB (GPU0/GPU1): пул 524288/H=2 → 554/439 (ниже 512), 503296/H=2 →
  750/635, 503296/H=3 → 676/513 (впритык), **495104/H=3 → 752/589
  (базовый)**, 491520/H=2 → 860/745, 491520/H=4 → 712/597,
  491520/H=8 → 418/303, 489472/H=4 → 732/617. Прайс линеен: ~9.5 MiB на
  1024 токена пула, ~74 MiB на каждый device-state-slot (на ранг;
  подтверждено: 503296 H=2→H=3 = 750→676 на GPU0 без десктопа). Выбор
  495104/H=3: запас 589 над 512 покрывает разброс занятости десктопа на
  GPU1 (до ±50 MiB) и нагрузку (под парой 150k×2 минимум равен стартовому
  752/589), тогда как максимум 503296/H=3 оставляет 513 — на 1 MiB. Одиночный
  запрос достигает моделиных 262144 (пул больше), две полосы делят 495104
  (~247 552 на каждую при равных промптах), промпт
  264 000 токенов отклоняется чистым `400 context_length_exceeded`.
  `--vision-device 0` — плата без дисплея: башня Vision и
  draft-стадии живут на ней, дисплейная GPU1 должна сохранять ≥ 512 MiB.
- `--host-state-slots` и `--host-kv-mib` на `--tp 2` обязаны быть 0: удерживаемые
  диалоги живут только в device-state слотах, при вытеснении их следующий turn
  префиллится заново. `--kv-capacity` задан явно (не `auto`): `auto` берёт
  максимум по остатку VRAM с запасом 1 GiB и может отличаться от расчёта.
- `nvfp4` KV принят в базовый профиль (тикет 12): пул в ~1.8× плотнее `int8`,
  префилл −1.3…−1.6 %, decode в пределах разброса (126.3 против 127.6 tok/s на
  коротком контексте, 106.8 против 107.0 на 139k), приём MTP одинаков.
  Заявленные форком +4…8 % decode для MTP3 не воспроизводятся. Качество
  4-битного KV локально не проверялось и не проверено — главная открытая
  оговорка переключения; при проблемах с качеством возвращаться к прежнему
  `int8` 241664 / C=1 / H=4 (свободно 1250/606 MiB).
- Рецепты тикета 11 (2026-10-06) вошли в базовый профиль: **A** — одиночный
  запрос до модельных 262144 (предельный промпт 260 629, дальше чистый
  `400 context_length_exceeded`, prefill ~1950 tok/s, TTFT ~133 с) теперь
  достижим при `--max-concurrency 2`; **B** — две полосы, пул 495104 даёт
  ~247 552 на каждую при равных промптах (прежний рецепт — 408832 и по
  204 169). Жёсткие пределы не изменились: позиционная ёмкость артефакта
  262144 (`--max-context 262145` не стартует), пул 524288 с двумя полосами не
  влезает (резерв runtime требует 5.85 GiB после весов против 5.64
  доступных). Цифры —
  `docs/research/0009-ninfer-tp2-two-5070ti.md`, раздел «Контекст выше
  196608»; recipes A/B — в git-истории `ninfer/config.yaml`.
- Две полосы в работе: llama-swap пропускает до 10 параллельных запросов на
  модель (дефолтный `concurrencyLimit`), движок держит 2 активных, decode
  двух диалогов идёт одновременно. Префиллы при этом **сериализуются**:
  префилл второго запроса ждёт префилл первого (замеры 2026-10-07: 150k×2 →
  `queue 55 с` у второго, 60k×2 → `queue 15 с`; на пуле 408832 тот же
  паттерн, то есть это поведение движка, а не пула). Минимум свободной VRAM
  под парой 150k×2 на базовых 495104/H=3 равен стартовому (752/589 MiB);
  на прежней конфигурации 503296/H=2 пары сидели на 748/633–648 MiB.
- DFlash2 измерен на этой машине и в базовый профиль не входит. На tp2
  обязательны `--spec dflash2 --draft-tokens 7 --lm-head-draft` (без
  `--lm-head-draft` движок падает на старте), драфтер в v0.4.5 разделён между
  ранками (16/4 головы, селектор на rank 1). Пределы с официальным артефактом:
  на `int8` — 131072 и 2 слота (при 196608 контейнер стартует, но на дисплейной
  GPU1 остаётся 132 MiB против требуемых 512); на `nvfp4` — 196608 с 4 слотами
  и даже 262144 с 2 слотами. Decode против MTP3: 179 против 126 tok/s на
  коротком контексте, но 119–126 против 113 на 110k токенах, приём драфта падает
  с 29 % до 18–25 %, префилл медленнее на ~2 %. Отдельный профиль не заводим:
  либо теряем треть контекста и два слота, либо переходим на непроверенный
  `nvfp4` KV. Возвращаться при потребности в decode > 200 tok/s на контексте
  100k+, после подтверждения качества `nvfp4` KV или при появлении
  опубликованного артефакта с DFlash2 на 196608 + 4 слота с `int8`. Цифры —
  `docs/research/0009-ninfer-tp2-two-5070ti.md`, раздел «DFlash2 на этой
  машине».
- Железо и разбор tp2 (VRAM-бюджет, пределы по слотам и контексту, mailbox vs
  p2p, `--embedding-host`, сравнение артефактов, замеры против llama.cpp) —
  в `docs/research/0009-ninfer-tp2-two-5070ti.md`. Решения — в
  `docs/adr/0003-ninfer-profile-llama-swap.md`.

Публичные ID профиля `ninfer` (совпадают с llama-профилем):

| ID | Назначение | thinking | preserve_thinking |
|---|---|---|---|
| `qwen3.8-27b` | быстрые ответы, instruct | off (`reasoning_effort: none`) | — |
| `qwen3.8-27b-chat-low` | чат с thinking | on, effort low (сервер) | false |
| `qwen3.8-27b-chat-medium` | чат с thinking | on, effort medium (сервер) | false |
| `qwen3.8-27b-chat-xhigh` | чат с thinking | on, effort xhigh (сервер) | false |
| `qwen3.8-27b-agent-low` | агент, thinking в контексте | on, effort low (сервер) | true |
| `qwen3.8-27b-agent-medium` | агент, thinking в контексте | on, effort medium (сервер) | true |
| `qwen3.8-27b-agent-xhigh` | агент, thinking в контексте | on, effort xhigh (сервер) | true |

Особенности API-контракта профиля `ninfer`:

- `ninfer-serve` отклоняет запрос, если `request.model` не равен `--model-id`,
  поэтому в конфиге модели обязателен `useModelName: qwen3.8-27b`; все
  алиасы режимов переписываются на каноническое имя.
- Effort (`low|medium|xhigh`) задаёт сервер по имени алиаса, как в
  llama-профиле: `reasoning_effort` стоит в `setParamsByID` жёстким ключом и
  перезаписывает клиентское значение. Клиенту effort передавать не нужно.
  Effort в NInfer — не бюджет токенов, а инструкция в системном промпте,
  которую подставляет chat template артефакта; дефолт шаблона — `xhigh`
  (`chat_template.jinja:58`), поэтому клиент без effort получил бы xhigh молча.
  Движок принимает и `none, minimal, high, max, adaptive`, но опираться
  следует на `low|medium|xhigh`. Замеры —
  `docs/research/0009-ninfer-tp2-two-5070ti.md`, раздел «Уровень reasoning на
  стороне сервера».
- `chat_template_kwargs` задан в конфиге объектом, поэтому заменяется целиком
  вместе с клиентскими ключами, и клиентский `enable_thinking` до движка не
  доходит. На thinking-режимах конфликт `conflicting_template_option` не
  воспроизводится; на instruct-режиме, где сервер `chat_template_kwargs` не
  задаёт, клиентский `enable_thinking` доходит и конфликтует с серверным
  `reasoning_effort: none` — `400 conflicting_template_option` (код 400, не
  401).
- `preserve_thinking: false` не скрывает `reasoning_content` от текущего
  запроса — он убирает reasoning из последующих запросов диалога. Это
  отличается от llama-профиля. Флаг действует только на историю, пересланную
  клиентом: сам сервер в промпт ничего не досылает.
- `device-state-slots 3` при `--max-concurrency 2` дают стартовый лог
  `context cache | 2 active + 3 cached device states`: два активных диалога
  плюс три удерживаемых после завершения. Удержанные сессии отвечают за
  ~0.15 с против ~2.4 с полного префилла; вытесненные не падают, а
  префилятся заново.
- Пресет сэмплирования выбирает движок по выведенному режиму thinking:
  non-thinking `0.7 / 0.80 / 20 / 0 / 1.5`, thinking `1.0 / 0.95 / 20 / 0 /
  0`. Клиентские `temperature`, `top_p`, `top_k`, `min_p`,
  `presence_penalty`, `frequency_penalty`, `repetition_penalty`
  отбрасываются (`stripParams`).
- `repetition_penalty` в NInfer принимается только в значении 1.0, поэтому
  `repeat_penalty 1.05` llama-профиля недоступен.
- Разрыва совместимости с llama-профилем по списку model-ID больше нет: набор
  публичных ID одинаков (ADR-0004).
- Есть только `/v1/chat/completions` (плюс Anthropic Messages и Responses);
  `/v1/completions` нет.

Изменение `ninfer/config.yaml` требует перезапуска `ninfer-swap`.

Проверено на этой машине (2026-10-05, официальный артефакт, v0.4.5):

- Движок готов через 6.1 с после старта контейнера, веса 18.5 GiB читаются за
  4.5 с (4.07 GiB/s); `p2p off (host-staged copies)`, mailbox захвачен, probe
  0.03 ms; `--embedding-host` уводит 1.18 GiB в host-mapped.
- Prefill: 4597 tok/s на 30k, 3319 tok/s на 98 849 (TTFT 29.8 с), 2605 tok/s на
  164 733 (TTFT 63.2 с). Для сравнения, llama.cpp на тех же картах даёт
  1372 tok/s на 90k — выигрыш 2.42×.
- Decode: 130.1 tok/s (1880 токенов), 131.5 tok/s (4834 токена), 106.3 tok/s на
  контексте 131 830. llama.cpp в тех же условиях — 80.5 tok/s (1.63×).
  Приём MTP 46–48 %.
- Минимум свободной VRAM под нагрузкой (префилл 165k плюс генерация): GPU0
  2018 MiB, GPU1 1501 MiB — запас GPU1 над требованием 512 MiB почти
  трёхкратный. KV-пул не растёт от длины запроса.
- Превышение контекста отвечает чистым `400 context_length_exceeded`, сервис
  остаётся жив.
- `preserve_thinking` измеряем: при пересылке `reasoning_content` в истории
  диалога `false` вырезает reasoning из промпта следующего turn (352 → 246
  токенов), `true` оставляет (352).
- Уровень reasoning измеряем по длине промпта (инструкция effort дописывается
  в системный промпт): instruct 13, `chat-medium` 25, `chat-low` 41,
  `chat-xhigh` 67 prompt-токенов. Клиентский `reasoning_effort` эти значения
  не меняет, клиентский `enable_thinking` на thinking-режимах до движка не
  доходит. Без effort шаблон даёт тот же промпт, что явный `xhigh`. Effort не
  ограничивает рассуждение токенами: `xhigh` дошёл до лимита `max_tokens:
  16000`, `low` закрыл рассуждение сам на 12 254 токенах.
- `qwen3.8-27b` остаётся instruct даже с клиентским `reasoning_effort:
  medium`; Effort из имени ID не подставляется — `chat-medium` и
  `agent-xhigh` без effort тоже дают thinking (дефолт движка).
- Tool calls работают; Vision отвечает верно по картинке (99 prompt-токенов).

Не проверено: качество при 4-битном KV (`nvfp4` локально не оценивалось),
DFlash2, одновременные диалоги в разных device-state слотах на полной длине —
тикеты `.scratch/ninfer-tp2/`.

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
# vLLM
docker compose --profile vllm up -d --wait --wait-timeout 1800
docker compose --profile vllm logs -f vllm-server
docker compose --profile vllm restart vllm-server

# llama.cpp
docker compose --profile llama up -d --wait --wait-timeout 1800
docker compose --profile llama logs -f llama-swap
docker compose --profile llama restart llama-swap

# NInfer TP=2
docker compose --profile ninfer build
./ninfer/fetch-model.sh
docker compose --profile ninfer up -d --wait --wait-timeout 1800
docker compose --profile ninfer logs -f ninfer-swap
docker compose --profile ninfer restart ninfer-swap
```

Публичный API всех профилей: `http://localhost:8080`.

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
  Compose-сервис профиля `ninfer` называется `ninfer-swap`, а контейнер —
  `llama-swap`, поэтому дашборды по имени контейнера `llama-swap` работают для
  обоих llama-подобных профилей без изменений.
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
