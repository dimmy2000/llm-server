# Локальный LLM-инференс: llama.cpp (Gemma 4)

## Описание

Docker Compose-стек для запуска LLM-модели **Gemma 4 (26B)** локально на GPU через [llama.cpp](https://github.com/ggml-org/llama.cpp).

Стек состоит из одного сервиса:

- **llama-server** (контейнер `gemma4`) — инференс-сервер на базе `llama.cpp` с GPU-ускорением NVIDIA CUDA. Запускает квантованную модель Gemma 4 26B (IQ4_XS).

## Требования

- Docker Engine 24+ с поддержкой Compose v2
- NVIDIA GPU с 16+ GB VRAM (протестировано на одной видеокарте)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (`nvidia-ctk`)
- Модели Gemma 4, размещённые в каталоге `./models/`

## Структура

```
llm-server/
├── docker-compose.yaml          # конфигурация сервисов
├── models/                      # каталог с файлами моделей (GGUF)
│   ├── gemma-4-26B-A4B-it-UD-IQ4_XS.gguf
│   └── gemma-4-26B-A4B-it-mmproj-F32.gguf
└── tool_chat_template_gemma4.jinja  # Jinja2-шаблон chat template
```

> **Примечание:** каталог `models/` необходимо создать вручную и поместить в него файлы моделей. Шаблон `tool_chat_template_gemma4.jinja` должен лежать рядом с `docker-compose.yaml`.

## Запуск

```bash
# Запуск стека
docker compose -f docker-compose.yaml up -d

# Просмотр логов
docker compose -f docker-compose.yaml logs -f

# Остановка
docker compose -f docker-compose.yaml down

# Перезапуск конкретного сервиса
docker compose -f docker-compose.yaml restart llama-server
```

## Доступ

| Сервис        | Адрес                         |
|---------------|-------------------------------|
| llama-server  | http://localhost:8080          |

## Сервисы

### llama-server / Gemma 4 (`ghcr.io/ggml-org/llama.cpp:server-cuda13`)

- **Порт:** `8080 → 8080`
- **GPU:** все доступные NVIDIA GPU
- **Модель:** `gemma-4-26B-A4B-it-UD-IQ4_XS.gguf` (26B, IQ4_XS — 4-битная квантизация)
- **Мультимодальность:** `gemma-4-26B-A4B-it-mmproj-F32.gguf` (F32 проектор), отключён offload проектора на GPU
- **Chat template:** Jinja2 (файл `gemma4.tmpl`)

#### Параметры инференса

| Параметр           | Значение | Пояснение                                |
|--------------------|----------|------------------------------------------|
| `--ctx-size`       | 65536    | Максимальный контекст (64K токенов)      |
| `--batch-size`     | 2048     | Размер батча                             |
| `--ubatch-size`    | 1024     | Размер микро-батча                       |
| `--temp`           | 1.0      | Температура сэмплирования                |
| `--top-p`          | 0.95     | Nucleus sampling                         |
| `--top-k`          | 64       | Top-K sampling                           |
| `--n-gpu-layers`   | 99       | Все слои на GPU                          |
| `--threads`        | 9        | Потоков для обработки                    |
| `--threads-batch`  | 9        | Потоков для батчевой обработки           |
| `--flash-attn`     | on       | Flash attention (экономия VRAM)          |
| `--cache-type-k`   | q8_0     | Квантование KV-кэша (key)                |
| `--cache-type-v`   | q8_0     | Квантование KV-кэша (value)              |
| `--no-kv-offload`  | —        | KV-кэш остаётся на GPU                   |
| `--cache-ram`      | 0        | Кэш не выгружается в RAM                 |
| `--parallel`       | 1        | Один параллельный запрос                 |

#### Healthcheck

Контейнер проверяет доступность эндпоинта `/health` каждые 50 секунд (5 попыток, таймаут 10 секунд). При недоступности Docker перезапускает контейнер (`restart: unless-stopped`).

## Логирование

Сервис использует драйвер `json-file` с ротацией:
- Максимальный размер файла: 100 MB
- Количество архивов: 5

## Мониторинг

Стек мониторинга (Grafana + Prometheus + Loki + nvidia-smi-exporter) описан в отдельном проекте [`llm-monitoring/`](../llm-monitoring/README.md). Для совместного запуска используйте скрипт `llm-stack.sh` из каталога мониторинга.

## Примечания

- Модель Gemma 4 (26B) в квантизации IQ4_XS занимает ~14–15 GB VRAM. С контекстом 64K и KV-кэшем в q8_0 расход может превышать 16 GB. При OOM-ошибках уменьшите `--ctx-size`.
- Параметр `--no-warmup` отключает прогрев модели — первый запрос будет медленнее.
- `--no-mmproj-offload` держит мультимодальный проектор на CPU (экономит VRAM ценой скорости обработки изображений).
- Если модель не загружается, проверьте, что файлы `.gguf` лежат в `./models/` и совпадают по именам.
```