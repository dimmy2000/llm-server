# Локальный LLM-инференс

## Описание

Репозиторий содержит три взаимозаменяемых Docker Compose-профиля с единым
OpenAI-совместимым адресом `http://localhost:8080`:

| Профиль | Движок | Модель | Публичный model-ID |
|---|---|---|---|
| `llama` | llama.cpp + llama-swap | Qwen3.8-27B NVFP4-MTP | `qwen3.8-27b-*` |
| `ninfer` | NInfer TP=2 + llama-swap | Qwen3.8-27B NVFP4 (артефакт `.ninfer`) | `qwen3.8-27b-*` |
| `vllm` | vLLM | Qwen3.8-27B NVFP4 | `qwen3.8-27b` |

Профили используют один порт и одни GPU, поэтому одновременно запускать их
нельзя. Корневой `docker-compose.yaml` только подключает конфигурации из
`llama/`, `ninfer/` и `vllm/`; параметры инференса хранятся внутри
соответствующего каталога.

## Требования

- Docker Engine 24+ с Docker Compose, поддерживающим `include` и `profiles`.
- NVIDIA Container Toolkit (`nvidia-ctk`).
- Для профилей `llama` и `ninfer`: две NVIDIA GPU по 16+ ГиБ VRAM (Qwen3.8-27B
  занимает обе GPU).
- Для текущего профиля `vllm`: две NVIDIA Blackwell GPU по 16 ГиБ VRAM.
- `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf` для
  llama.cpp.
- `/opt/models/Qwen3.8-27B-nvfp4-NInfer/qwen3_8_27b_nvfp4.ninfer` для NInfer.
- `/opt/models/Qwen3.8-27B-NVFP4/` для vLLM.

Модели монтируются в контейнеры read-only и в Git не добавляются.

## Структура

```text
llm-server/
├── docker-compose.yaml
├── llama/
│   ├── docker-compose.yaml
│   └── config.yaml
├── ninfer/
│   ├── Dockerfile
│   ├── docker-compose.yaml
│   ├── config.yaml
│   └── fetch-model.sh
├── vllm/
│   ├── docker-compose.yaml
│   └── config.yaml
├── docs/
│   └── NVIDIA_SETUP.md
└── scripts/
    └── port-forwarding-rules.ps1
```

## Запуск vLLM

Сначала удалите контейнеры другого профиля, затем запустите vLLM. Первый
запуск включает загрузку большого образа и JIT-компиляцию CUDA-ядер.

```bash
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans
docker compose --profile vllm up -d --wait --wait-timeout 1800
docker compose --profile vllm logs -f vllm-server
```

Проверка API:

```bash
curl --fail http://localhost:8080/health
curl --fail http://localhost:8080/v1/models
```

Профиль публикует единственный model-ID: `qwen3.8-27b`. Базовая проверяемая
конфигурация запускает модель в text-only режиме на двух GPU с FP8 KV-cache,
контекстом 49152 токена, одной активной sequence, chunked prefill и лимитом
1024 токена на scheduler iteration. Второй конкурентный запрос ожидает в
scheduler, а не увеличивает число одновременно выполняемых sequences.

Для совместной работы с графической сессией используется
`gpu-memory-utilization: 0.85`. Под пиковой нагрузкой на GPU1 должно оставаться
не менее 512 MiB физически свободной VRAM. Нельзя повышать utilization только
ради прохождения startup-проверки KV cache. Максимальный стабильный context
limit определяется отдельным cold-start и нагрузочным тестом после проверки
базового профиля. На текущей машине `49152` прошёл проверку, а `65536` не
прошёл startup из-за недостаточного KV cache, поэтому `49152` является
максимальным проверенным context limit.

Qwen3.8 по умолчанию использует thinking. Клиент может управлять им через
`reasoning_effort` или передать
`chat_template_kwargs: {"enable_thinking": false}`. В отличие от llama-профиля,
vLLM не отбрасывает клиентские sampling-параметры. Reasoning возвращается в
поле `reasoning` OpenAI-совместимого ответа.

MTP/speculative decoding, TurboQuant KV-cache и prefix caching намеренно не
включены в базовый профиль. Их следует добавлять только после отдельной
проверки корректности длинных streaming-ответов и расхода VRAM.

## Запуск llama.cpp

```bash
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans
docker compose --profile llama up -d --wait --wait-timeout 1800
docker compose --profile llama logs -f llama-swap
```

Публичной точкой входа остается `llama-swap` на `:8080`. Единственная модель
запускается llama-swap как дочерний процесс llama-server (бинарник входит в
образ `llama-swap:cuda13`); отдельный контейнер llama-server не используется.
Модель прелоадится при старте контейнера (время загрузки ~40-60 c), после
чего первый запрос обслуживается сразу.

Доступные model-ID:

| ID | Назначение |
|---|---|
| `qwen3.8-27b` | быстрые ответы без thinking |
| `qwen3.8-27b-chat-low` | чат с thinking (reasoning скрыт, preserve off), effort low |
| `qwen3.8-27b-chat-medium` | чат с thinking (reasoning скрыт, preserve off), effort medium |
| `qwen3.8-27b-chat-xhigh` | чат с thinking (reasoning скрыт, preserve off), effort xhigh |
| `qwen3.8-27b-agent-low` | агент, thinking с preserve, effort low |
| `qwen3.8-27b-agent-medium` | агент, thinking с preserve, effort medium |
| `qwen3.8-27b-agent-xhigh` | агент, thinking с preserve, effort xhigh |

Параметры ядра модели находятся в `llama/config.yaml` (секция `cmd`). Sampling и
режим reasoning задаются сервером через `setParamsByID`; переданные клиентом
sampling-параметры и параметры thinking `llama-swap` удаляет.

Qwen3.8-27B запускается с контекстом 180224 токена (NVFP4-MTP квантизация
тира HIGH, файл ~17.6 GB) и спекулятивным декодированием: draft-mtp с
fallback на ngram-mod. Требуется пара `--split-mode tensor` и
`--tensor-split 50,50`; проверенный стабильный максимум контекста — 180224,
на 196608 первый же decode падает OOM на дисплейной GPU1. `--ctx-checkpoints`
не включены. Подробный разбор — в `docs/research/0008-llama-qwen38-mtp-ngram-mod-combo.md`.

## Запуск NInfer TP=2

Профиль `ninfer` отдаёт ту же публичную точку входа `llama-swap` на `:8080`,
но за ней стоит NInfer с tensor parallelism на две GPU.

```bash
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans
docker compose --profile ninfer build
./ninfer/fetch-model.sh
docker compose --profile ninfer up -d --wait --wait-timeout 1800
docker compose --profile ninfer logs -f ninfer-swap
```

Движок берётся из готовых бинарников релиза `ninfer-tp2 v0.4.5`: образ
собирается из `ubuntu:26.04` плюс архив релиза с проверкой SHA-256, а
llama-swap копируется из образа llama-профиля, поэтому версии маршрутизатора
совпадают. Compose-сервис называется `ninfer-swap`, контейнер —
`llama-swap`. Модель — официальный артефакт
`neroued/Qwen3.8-27B-nvfp4-NInfer` (23.7 GB, скачивается
`ninfer/fetch-model.sh` с проверкой контрольной суммы).

Базовый профиль движка: `--tp 2 --devices 0,1`, KV `nvfp4`, контекст
модели 262144 токенов и KV-пул 495104, две активные последовательности
(`--max-concurrency 2`), 3 слота device-state, спекулятивное декодирование
MTP с 3 draft-токенами, Vision на плате без дисплея и вынос таблицы
embedding в host RAM. Переключение с прежнего профиля (`int8`, контекст и
пул 241664, одна последовательность, 4 слота) — тикет 12 (2026-10-07): две
полосы под нагрузку реальных задач. Пул 495104 и три слота выбраны по
startup-sweep под требование GPU1 ≥ 512 MiB: после старта свободно
752/589 MiB (GPU0/GPU1), минимум под нагрузкой пары 150k-промптов равен
стартовому. Максимум 503296 при том же числе слотов оставлял бы 513 MiB —
запас в 1 MiB против разброса занятости десктопа до ±50 MiB. Позиционный
потолок артефакта — 262144 токенов, промпт 270 000 токенов отклоняется
чистым `400 context_length_exceeded`.

Проверено на этой машине (2026-10-05, официальный артефакт, v0.4.5, на
контексте 196608): движок
готов через 6.1 с, веса читаются за 4.5 с; prefill 4597 tok/s на 30k и 3319
tok/s на 98 849 токенов (TTFT 29.8 с); decode 130.1–131.5 tok/s и 106.3 tok/s
на контексте 131 830; приём MTP 46–48 %. Минимум свободной VRAM под нагрузкой
(префилл 165k плюс длинная генерация) — 2018 MiB на GPU0 и 1501 MiB на GPU1,
то есть запас GPU1 над требованием 512 MiB почти трёхкратный. Для сравнения,
llama.cpp на тех же картах даёт 1372 tok/s на prefill 90k и 80.5 tok/s на
генерации — NInfer быстрее в 2.42× и 1.63×. На контексте 241664 (2026-10-06):
старт 6 с, runtime пула 4.63 GiB, свободно 1250/606 MiB (GPU0/GPU1).
Нагрузочные прогоны снимались на верхней точке sweep 245760: prefill ~2074
tok/s на промпте 243 195 (TTFT ~117 с), decode 129–131 tok/s, приём MTP 73 %,
минимум свободной VRAM под нагрузкой 1180 MiB на GPU0 и 533 MiB на GPU1 — на
241664 запас над требованием 512 MiB больше на 71 MiB.

На базовом профиле (2026-10-07, `nvfp4`, пул 495104, H=3, две полосы):
движок готов через 6.0 с, runtime пула 5.11 GiB, после старта 752/589 MiB
(GPU0/GPU1). Prefill 3.93k tok/s на 60k, 2.70–2.71k на 150k, 1.96k на
259 498 токенов (TTFT 2m 12.8s), decode 75–92 tok/s на длинном контексте.
Две полосы: decode двух диалогов идёт одновременно, но префиллы
сериализуются — при паре 150k×2 второй запрос ждёт 55 с в очереди (TTFT
55.4 с и 1m 51.2s), при паре 5.1k×2 очередь не превышает 1.0 с и decode
идёт со 128–136 tok/s. Минимум свободной VRAM под нагрузкой пары 150k×2 —
752/589 MiB, то есть GPU1 держит порог 512 MiB.

Публичные model-ID совпадают с llama-профилем: `qwen3.8-27b` (instruct, без
reasoning) и шесть алиасов `-chat-{low,medium,xhigh}` (thinking, reasoning не
возвращается в следующие запросы диалога) и `-agent-{low,medium,xhigh}`
(thinking с сохранением reasoning в контексте). Уровень reasoning задаёт
сервер по имени алиаса, как в llama-профиле, клиенту `reasoning_effort`
передавать не нужно. Быстрые задачи, которым раньше был нужен отдельный
небольшой instruct-режим, обслуживает `qwen3.8-27b`: он доступен во всех трёх
профилях и быстрее по задержке, поэтому отдельный запасной профиль не нужен.

Effort в NInfer — не бюджет токенов, а инструкция в системном промпте,
которую подставляет chat template артефакта: `xhigh` на длинной задаче дошёл
до лимита `max_tokens: 16000`, `low` закрыл рассуждение сам на 12 254 токенах.
Движок принимает effort шире (`none, minimal, low, medium, high, xhigh, max,
adaptive`), но опираться следует на `low | medium | xhigh`. Клиентский
`enable_thinking` на thinking-режимах до движка не доходит, потому что
`chat_template_kwargs` задан в конфиге объектом и заменяется целиком; на
instruct-режиме он доходит и даёт `400 conflicting_template_option`.

Движок сам выбирает пресет сэмплирования по режиму thinking, поэтому клиентские
sampling-параметры отбрасываются; `repeat_penalty 1.05` из llama-профиля
недоступен, потому что NInfer принимает `repetition_penalty` только равный
1.0. Разбор tp2, бюджет VRAM, сравнение артефактов и замеры против llama.cpp —
в `docs/research/0009-ninfer-tp2-two-5070ti.md`.

Спекулятивное декодирование DFlash2 (`--spec dflash2` `--draft-tokens 7`
`--lm-head-draft`) измерено на этой машине и в профиль не включено: на `int8` оно
требует 131072 контекста и 2 слотов, то есть вдвое меньший контекст, чем
базовый профиль, а на `nvfp4` — того же
непроверенного 4-битного KV. Выигрыш decode есть только на коротких генерациях
(179 против 126 tok/s), на контексте 110k токенов он сходит к 119–126 против
113 tok/s у MTP3, префилл медленнее на ~2 %.

## Управление

```bash
# Остановить любой активный профиль
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans

# Применить изменения Compose или образа vLLM
docker compose --profile vllm up -d --force-recreate

# Перезапустить vLLM после изменения vllm/config.yaml
docker compose --profile vllm restart vllm-server

# Перезапустить llama-swap после изменения llama/config.yaml или llama/docker-compose.yaml
docker compose --profile llama restart llama-swap

# Пересобрать образ NInfer после смены версии и перезапустить профиль
docker compose --profile ninfer build
docker compose --profile ninfer restart ninfer-swap
```

## Мониторинг

Grafana, Prometheus, Loki и nvidia-smi-exporter находятся в отдельном проекте
`llm-monitoring`. Его launcher должен передавать активный Compose-профиль и
использовать имя сервиса выбранного backend: `llama-swap`, `ninfer-swap` или
`vllm-server`.
