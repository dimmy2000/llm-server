# Локальный LLM-инференс: llama.cpp (Gemma 4)

## Описание

 Сервис `llama-swap` предоставляет интерфейс для работы с моделью Gemma 4 через проксирование запросов к `llama-server`. Конфигурация `llama-server` (включая параметры инференса и специфику Draft MTP) задается в `docker-compose.yaml`, а различные режимы работы (например, thinking, instruct) управляются через `config.yaml` в `llama-swap`.

## Требования

- Docker Engine 24+ с поддержкой Compose v2
- NVIDIA GPU с 16+ GB VRAM (протестировано на одной видеокарте)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (`nvidia-ctk`)
- Модели Gemma 4, размещённые в каталоге `/opt/models/` сервера или виртуальной машины

## Структура

```
llm-server/
├── docker-compose.yaml              # конфигурация сервисов
├── Dockerfile.llama-mtp             # конфигурация сборки образа с возможностью запуска MTP для Gemma4
├── config.yaml                      # конфигурация режимов llama-swap

```

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
| llama-swap    | http://localhost:8080         |


#### Параметры инференса
 
При запуске контейнера основная конфигурация `llama-server` (включая модель, `ctx-size`, `threads` и др.) задается в файле `docker-compose.yaml`.

Сервис `llama-swap` позволяет переключаться между различными режимами работы (например, `gemma4-thinking`, `gemma4-instruct`) путем переопределения параметров инференса на основе конфигурации в файле `config.yaml`.

## Логирование

Сервис использует драйвер `json-file` с ротацией:
- Максимальный размер файла: 100 MB
- Количество архивов: 5

## Мониторинг

Стек мониторинга (Grafana + Prometheus + Loki + nvidia-smi-exporter) описан в отдельном проекте [`llm-monitoring/`](../llm-monitoring/README.md). Для совместного запуска используйте скрипт `llm-stack.sh` из каталога мониторинга.
