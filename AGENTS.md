# AGENTS.md

Docker-стек локального LLM-инференса с переключаемыми backend-профилями
llama.cpp и vLLM. Прикладного кода, тестов, CI и линтинга нет. Не выдумывать
`make`, `npm`, `pytest` и подобные команды.

## Общая архитектура

Корневой `docker-compose.yaml` задает имя проекта `llm-server` и через
`include` подключает `llama/docker-compose.yaml` и
`vllm/docker-compose.yaml`.

- Профиль `llama` публикует llama.cpp через `llama-swap`.
- Профиль `vllm` публикует OpenAI API самого vLLM.
- Оба backend занимают порт `8080` и все GPU. Одновременно их не запускать.
- Без явно указанного профиля сервисы не запускаются.

Перед переключением всегда выполнять:

```bash
docker compose --profile llama --profile vllm down --remove-orphans
```

## Профиль llama

- `llama/llama-server` использует образ
  `ghcr.io/ggml-org/llama.cpp:server-cuda13`.
- Все параметры ядра (`--model`, `--ctx-size`, `--threads`,
  `--cache-type-*`, `--flash-attn`, базовый sampling) находятся только в
  `llama/docker-compose.yaml`.
- `llama-swap` слушает публичный `:8080`, а `llama-server` доступен только во
  внутренней Compose-сети.
- Конфигурация proxy и режимов находится в `llama/config.yaml`.

`llama-swap` удаляет клиентские параметры `temperature`, `top_p`, `top_k`,
`min_p`, `presence_penalty`, `repeat_penalty`. Для llama-профиля sampling
управляется только через `setParamsByID` в `llama/config.yaml`.

| ID | Назначение | reasoning |
|---|---|---|
| `ornith-9b-thinking` | чат с reasoning | on |
| `ornith-9b-instruct` | быстрые ответы | off |

Изменение `llama/config.yaml` требует перезапуска `llama-swap`. Изменение
аргументов ядра требует перезапуска `llama-server`.

Модель хоста: `/opt/models/ornith-9b-Q8_0.gguf`, внутри контейнера
`/models/ornith-9b-Q8_0.gguf`. Алиас llama.cpp: `ornith-9b`.

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
docker compose --profile llama logs -f llama-server llama-swap
docker compose --profile llama restart llama-server
docker compose --profile llama restart llama-swap
```

Публичный API обоих профилей: `http://localhost:8080`.

## Альтернативный llama.cpp-образ

`llama/Dockerfile.llama-mtp` собирает llama.cpp из PR `${LLAMA_CPP_PR}` для
экспериментального MTP. `CUDA_ARCH=120` означает Blackwell. Образ не подключен
к Compose и собирается вручную:

```bash
docker build -f llama/Dockerfile.llama-mtp -t local/llama-server:mtp llama
```

## Сопутствующие проекты

- `scripts/port-forwarding-rules.ps1` запускается в PowerShell Windows-хоста,
  не внутри WSL или контейнера.
- Мониторинг находится в отдельном репозитории `llm-monitoring`; его launcher
  должен передавать нужный Compose-профиль.
