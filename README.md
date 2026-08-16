# Локальный LLM-инференс

## Описание

Репозиторий содержит два взаимозаменяемых Docker Compose-профиля с единым
OpenAI-совместимым адресом `http://localhost:8080`:

| Профиль | Движок | Модель | Публичный model-ID |
|---|---|---|---|
| `llama` | llama.cpp + llama-swap | Ornith 9B Q8_0 | `gemma4-*` |
| `vllm` | vLLM | Qwen3.8-27B NVFP4 | `qwen3.8` |

Профили используют один порт и одни GPU, поэтому одновременно запускать их
нельзя. Корневой `docker-compose.yaml` только подключает конфигурации из
`llama/` и `vllm/`; параметры инференса хранятся внутри соответствующего
каталога.

## Требования

- Docker Engine 24+ с Docker Compose, поддерживающим `include` и `profiles`.
- NVIDIA Container Toolkit (`nvidia-ctk`).
- Для профиля `llama`: NVIDIA GPU с 16+ ГиБ VRAM.
- Для текущего профиля `vllm`: две NVIDIA Blackwell GPU по 16 ГиБ VRAM.
- `/opt/models/ornith-9b-Q8_0.gguf` для llama.cpp.
- `/opt/models/Qwen3.8-27B-NVFP4/` для vLLM.

Модели монтируются в контейнеры read-only и в Git не добавляются.

## Структура

```text
llm-server/
├── docker-compose.yaml
├── llama/
│   ├── docker-compose.yaml
│   ├── config.yaml
│   ├── Dockerfile.llama-mtp
│   └── tool_chat_template_gemma4.jinja
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

Профиль публикует один model-ID: `qwen3.8`. Он запускает модель в text-only
режиме на двух GPU с FP8 KV-cache, контекстом до 131072 токенов и не более
чем двумя активными последовательностями scheduler. На текущей машине startup
показывает 132578 токенов KV-cache, или `1.01x` для запроса на 131072 токена:
один полный 128K-контекст помещается, два одновременно полностью заполненных
контекста — нет. Фактическая суммарная вместимость выводится в логах vLLM при
каждом старте.

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
docker compose --profile llama logs -f llama-server llama-swap
```

Публичной точкой входа остается `llama-swap` на `:8080`. Доступные model-ID:

| ID | Назначение |
|---|---|
| `gemma4-thinking` | чат с reasoning |
| `gemma4-instruct` | быстрые ответы без reasoning |
| `gemma4-agent-plan` | агентное планирование |
| `gemma4-agent-code` | агентная разработка кода |

Параметры ядра llama.cpp находятся в `llama/docker-compose.yaml`. Sampling и
режим reasoning задаются сервером через `llama/config.yaml`; переданные
клиентом sampling-параметры `llama-swap` удаляет.

## Управление

```bash
# Остановить любой активный профиль
docker compose --profile llama --profile vllm down --remove-orphans

# Применить изменения Compose или образа vLLM
docker compose --profile vllm up -d --force-recreate

# Перезапустить vLLM после изменения vllm/config.yaml
docker compose --profile vllm restart vllm-server

# Перезапустить llama.cpp или только конфигурацию llama-swap
docker compose --profile llama restart llama-server
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
использовать имя сервиса выбранного backend: `llama-server` или `vllm-server`.
