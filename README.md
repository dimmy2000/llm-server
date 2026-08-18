# Локальный LLM-инференс

## Описание

Репозиторий содержит два взаимозаменяемых Docker Compose-профиля с единым
OpenAI-совместимым адресом `http://localhost:8080`:

| Профиль | Движок | Модель | Публичный model-ID |
|---|---|---|---|
| `llama` | llama.cpp + llama-swap | Ornith 9B Q8_0, Qwen3.8-27B Q4_K_M | `ornith-9b-*`, `qwen3.8-27b-*` |
| `vllm` | vLLM | Qwen3.8-27B NVFP4 | `qwen3.8-27b` |

Профили используют один порт и одни GPU, поэтому одновременно запускать их
нельзя. Корневой `docker-compose.yaml` только подключает конфигурации из
`llama/` и `vllm/`; параметры инференса хранятся внутри соответствующего
каталога.

## Требования

- Docker Engine 24+ с Docker Compose, поддерживающим `include` и `profiles`.
- NVIDIA Container Toolkit (`nvidia-ctk`).
- Для профиля `llama`: две NVIDIA GPU по 16+ ГиБ VRAM (Qwen3.8-27B занимает
  обе GPU).
- Для текущего профиля `vllm`: две NVIDIA Blackwell GPU по 16 ГиБ VRAM.
- `/opt/models/ornith-9b-Q8_0.gguf` для llama.cpp.
- `/opt/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf` для llama.cpp.
- `/opt/models/Qwen3.8-27B-NVFP4/` для vLLM.

Модели монтируются в контейнеры read-only и в Git не добавляются.

## Структура

```text
llm-server/
├── docker-compose.yaml
├── llama/
│   ├── docker-compose.yaml
│   ├── config.yaml
│   └── Dockerfile.llama-mtp
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
docker compose --profile llama --profile vllm down --remove-orphans
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
docker compose --profile llama --profile vllm down --remove-orphans
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

Qwen3.8-27B запускается с полным контекстом 262144 токена (веса Q4_K_M
15.9 GiB + KV q8_0 17 full-attention слоёв ≈ 11.4 GiB), суммарная загрузка
VRAM ≈ 92%, а `--tensor-split 52,48` оставляет на GPU1 (дисплей) ~700 MiB
свободной VRAM. `--ctx-checkpoints` для неё не включён; MTP не используется.

## Управление

```bash
# Остановить любой активный профиль
docker compose --profile llama --profile vllm down --remove-orphans

# Применить изменения Compose или образа vLLM
docker compose --profile vllm up -d --force-recreate

# Перезапустить vLLM после изменения vllm/config.yaml
docker compose --profile vllm restart vllm-server

# Перезапустить llama-swap после изменения llama/config.yaml или llama/docker-compose.yaml
docker compose --profile llama restart llama-swap
```

Альтернативный llama.cpp-образ с экспериментальной поддержкой MTP собирается
отдельно и не подключен к Compose:

```bash
docker build -f llama/Dockerfile.llama-mtp -t local/llama-server:mtp llama
```

## Мониторинг

Grafana, Prometheus, Loki и nvidia-smi-exporter находятся в отдельном проекте
`llm-monitoring`. Его launcher должен передавать активный Compose-профиль и
использовать имя сервиса выбранного backend: `llama-swap` или `vllm-server`.
