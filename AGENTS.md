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

- Единственный сервис `llama-swap` использует образ
  `ghcr.io/mostlygeek/llama-swap:cuda13` и публикует `:8080`; бинарник
  `llama-server` и CUDA-библиотеки входят в этот образ. Отдельного контейнера
  `llama-server` нет: обе модели запускаются llama-swap как дочерние процессы
  через `cmd` (аргументы ядра в секциях `cmd` в `llama/config.yaml`).
- Параметры ядра (`--model`, `--ctx-size`, `--threads`, `--cache-type-*`,
  `--flash-attn`, базовый sampling) находятся только в `llama/config.yaml`.
- Конфигурация моделей и режимов находится в `llama/config.yaml`.
- `qwen3.8-27b` загружается лениво по первому запросу
  (`hooks.on_startup.preload` отключен); переключение с ornith — через
  `POST /api/models/unload/:model_id`.
- В VRAM одновременно помещается только одна модель (ornith ~9.3 GiB веса +
  qwen ~15.9 GiB веса + KV не влезают вместе). Переключение явное:
  `curl -X POST http://localhost:8080/api/models/unload/:model_id`, затем
  запрос к другой модели (загрузится сама, ~40-60 c для qwen).

`llama-swap` удаляет клиентские параметры `temperature`, `top_p`, `top_k`,
`min_p`, `presence_penalty`, `repeat_penalty`; для `qwen3.8-27b` дополнительно
`reasoning`, `reasoning_effort`, `chat_template_kwargs`. Для llama-профиля
sampling и thinking управляются только через `setParamsByID` в
`llama/config.yaml`.

| ID | Назначение | reasoning |
|---|---|---|
| `ornith-9b-thinking` | чат с reasoning | on |
| `ornith-9b-instruct` | быстрые ответы | off |
| `qwen3.8-27b` | быстрые ответы | off |
| `qwen3.8-27b-chat-low` | чат, reasoning скрыт (preserve off), effort low | on |
| `qwen3.8-27b-chat-medium` | чат, reasoning скрыт (preserve off), effort medium | on |
| `qwen3.8-27b-chat-xhigh` | чат, reasoning скрыт (preserve off), effort xhigh | on |
| `qwen3.8-27b-agent-low` | агент, preserve on, effort low | on |
| `qwen3.8-27b-agent-medium` | агент, preserve on, effort medium | on |
| `qwen3.8-27b-agent-xhigh` | агент, preserve on, effort xhigh | on |

Изменение `llama/config.yaml` требует перезапуска `llama-swap`.

Старые публичные ID (`qwen3.8`, `qwen3.8-27b-instruct`,
`qwen3.8-27b-chat`, `qwen3.8-27b-agent-code`, `qwen3.8-27b-agent-plan`)
удалены без backcompat-алиасов; миграция внешних потребителей — отдельный
процесс.

Модели хоста: `/opt/models/ornith-9b-Q8_0.gguf` и
`/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`,
внутри контейнера соответственно `/models/ornith-9b-Q8_0.gguf` и
`/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf`. Алиасы
llama.cpp: `ornith-9b`.

Qwen3.8-27B: 65 слоёв, полное внимание каждые 4 слоя (17 слоёв с KV-cache,
остальные SSM без KV). В llama-профиле используется NVFP4-MTP квантизация
тира HIGH (файл ~17.6 GB) со спекулятивным декодированием MTP
(`--spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75`).
Требуются `--split-mode tensor` и `--tensor-split 50,50` в паре: дефолтный
LAYER-режим копит KV на дисплейной GPU1 и при большом ctx падает OOM на
первом decode (`cublasCreate_v2` в common.cuh). `--parallel -1` даёт
4 слота с единым KV-пулом (`kv_unified`). Узкое место VRAM — GPU0: при
`--ctx-size 262144` и 196608 не проходит даже startup (OOM аллокации
KV-буфера); проверенный стабильный максимум — `--ctx-size 163840`. Под
пиковой нагрузкой после серии запросов GPU0 ~1.2 GiB свободно, GPU1 ~0.6 GiB
(дисплей, требование ≥512 MiB выполнено). `--ctx-checkpoints` не включены;
MTP включен через `--spec-type draft-mtp`. `--fit off`: контекст задаётся
явно.

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
