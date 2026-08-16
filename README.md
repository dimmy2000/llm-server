# Локальный LLM-инференс

## Описание

Репозиторий содержит два взаимозаменяемых Docker Compose-профиля с единым
OpenAI-совместимым адресом `http://localhost:8080`:

| Профиль | Движок | Модель | Публичный model-ID |
|---|---|---|---|
| `llama` | llama.cpp + llama-swap | Ornith 9B Q8_0 | `gemma4-*` |
| `vllm` | vLLM | Qwen3.8-27B NVFP4 | `qwen3.8-27b` |

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
