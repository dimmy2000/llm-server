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
- На старте прелоадится `qwen3.8-27b` (`hooks.on_startup.preload`).
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
| `qwen3.8-27b-instruct` | быстрые ответы | off |
| `qwen3.8-27b-chat` | чат, reasoning скрыт (preserve off), effort medium | on |
| `qwen3.8-27b-agent-code` | агент-кодинг, preserve on, effort medium | on |
| `qwen3.8-27b-agent-plan` | агент-планирование, preserve on, effort xhigh | on |

Алиас `qwen3.8` эквивалентен режиму `qwen3.8-27b-agent-plan`. Изменение
`llama/config.yaml` требует перезапуска `llama-swap`.

Модели хоста: `/opt/models/ornith-9b-Q8_0.gguf` и
`/opt/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf`, внутри контейнера
соответственно `/models/ornith-9b-Q8_0.gguf` и
`/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf`. Алиасы llama.cpp:
`ornith-9b`, `qwen3.8`.

Qwen3.8-27B: 65 слоёв, полное внимание каждые 4 слоя (17 слоёв с KV-cache,
остальные SSM без KV); Q4_K_M ~15.9 GiB веса, KV q8_0 при `--ctx-size 262144`
~11.4 GiB, суммарная загрузка VRAM ~0.92 (включая графическую сессию; без неё
~0.89). `--tensor-split 52,48` слегка смещает модель на GPU0, чтобы на GPU1
(дисплей) оставалось ≥512 MiB свободной VRAM: под пиковой нагрузкой GPU1
~700 MiB свободно, GPU0 ~480 MiB. При каждой загрузке llama.cpp сначала
пытается выделить compute-буферы с pipeline parallelism и получает OOM, затем
успешно ретраит без него - это нормальный путь загрузки, не ошибка.
`--ctx-checkpoints` и MTP не включены. `--fit off`: контекст задаётся явно.

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
