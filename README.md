# Локальный LLM-инференс

## Описание

Репозиторий содержит три взаимозаменяемых Docker Compose-профиля с единым
OpenAI-совместимым адресом `http://localhost:8080`:

| Профиль | Движок | Модель | Публичный model-ID |
|---|---|---|---|
| `llama` | llama.cpp + llama-swap | Ornith 9B Q8_0, Qwen3.8-27B NVFP4-MTP | `ornith-9b-*`, `qwen3.8-27b-*` |
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
- `/opt/models/ornith-9b-Q8_0.gguf` для llama.cpp.
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

Публичной точкой входа остается `llama-swap` на `:8080`. Обе модели
запускаются llama-swap как дочерние процессы llama-server (бинарник входит в
образ `llama-swap:cuda13`); отдельный контейнер llama-server не используется.
В VRAM одновременно помещается только одна модель, поэтому при старте
прелоадится `qwen3.8-27b` (время загрузки ~40-60 c), а переключение
выполняется вручную:

```bash
# Выгрузить текущую модель, затем запросить другую - она загрузится сама
curl -X POST http://localhost:8080/api/models/unload/qwen3.8-27b
curl -X POST http://localhost:8080/api/models/unload/ornith-9b
```

Доступные model-ID:

| ID | Назначение |
|---|---|
| `ornith-9b-thinking` | чат с reasoning |
| `ornith-9b-instruct` | быстрые ответы без reasoning |
| `qwen3.8-27b` | быстрые ответы без thinking |
| `qwen3.8-27b-chat-low` | чат с thinking (reasoning скрыт, preserve off), effort low |
| `qwen3.8-27b-chat-medium` | чат с thinking (reasoning скрыт, preserve off), effort medium |
| `qwen3.8-27b-chat-xhigh` | чат с thinking (reasoning скрыт, preserve off), effort xhigh |
| `qwen3.8-27b-agent-low` | агент, thinking с preserve, effort low |
| `qwen3.8-27b-agent-medium` | агент, thinking с preserve, effort medium |
| `qwen3.8-27b-agent-xhigh` | агент, thinking с preserve, effort xhigh |

Параметры ядра
каждой модели находятся в `llama/config.yaml` (секции `cmd`). Sampling и
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

Базовый профиль движка: `--tp 2 --devices 0,1`, KV `int8`, контекст и пул
196608 токенов, одна активная последовательность, 4 слота device-state,
спекулятивное декодирование MTP с 3 draft-токенами, Vision на плате без
дисплея и вынос таблицы embedding в host RAM. 196608 — верхняя граница для
этого артефакта с Vision на двух 16 ГиБ платах; на 262144 MTP3 работает, но
только без Vision и с 4 слотами. Дисплейная GPU1 должна сохранять ≥ 512 MiB
свободной VRAM.

Проверено на этой машине (2026-10-05, официальный артефакт, v0.4.5): движок
готов через 6.1 с, веса читаются за 4.5 с; prefill 4597 tok/s на 30k и 3319
tok/s на 98 849 токенов (TTFT 29.8 с); decode 130.1–131.5 tok/s и 106.3 tok/s
на контексте 131 830; приём MTP 46–48 %. Минимум свободной VRAM под нагрузкой
(префилл 165k плюс длинная генерация) — 2018 MiB на GPU0 и 1501 MiB на GPU1,
то есть запас GPU1 над требованием 512 MiB почти трёхкратный. Для сравнения,
llama.cpp на тех же картах даёт 1372 tok/s на prefill 90k и 80.5 tok/s на
генерации — NInfer быстрее в 2.42× и 1.63×.

Публичные model-ID совпадают с llama-профилем: `qwen3.8-27b` (instruct, без
reasoning) и шесть алиасов `-chat-{low,medium,xhigh}` (thinking, reasoning не
возвращается в следующие запросы диалога) и `-agent-{low,medium,xhigh}`
(thinking с сохранением reasoning в контексте). Effort задаёт агент через
`reasoning_effort`; `low`, `medium` и `xhigh` в имени алиаса — только
маркер потребителя. `ornith-9b-*` в этом профиле недоступен: NInfer не
загружает GGUF.

Движок сам выбирает пресет сэмплирования по режиму thinking, поэтому клиентские
sampling-параметры отбрасываются; `repeat_penalty 1.05` из llama-профиля
недоступен, потому что NInfer принимает `repetition_penalty` только равный
1.0. Разбор tp2, бюджет VRAM, сравнение артефактов и замеры против llama.cpp —
в `docs/research/0009-ninfer-tp2-two-5070ti.md`.

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
