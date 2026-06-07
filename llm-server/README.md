# Локальный LLM-инференс: llama.cpp (Gemma 4)

## Описание

Сервис `llama-server` работает как оркестратор: он автоматически переключается между моделями, указанными в файле `models.ini`, в зависимости от запроса.

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
├── models.ini                       # конфигурация пресетов моделей
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
| llama-server  | http://localhost:8080          |


#### Параметры инференса
 
При запуске контейнера передаются следующие основные параметры:
```
--models-preset /models.ini
--models-max 1
--host 0.0.0.0
--port 8080
```
Все остальные параметры моделей (такие как `ctx-size`, `threads`, `temp`, `top_p` и др.) управляются через соответствующие секции в файле `models.ini`.

#### Healthcheck

Контейнер проверяет доступность эндпоинта `/health` каждые 50 секунд (5 попыток, таймаут 10 секунд). При недоступности Docker перезапускает контейнер (`restart: unless-stopped`).

## Логирование

Сервис использует драйвер `json-file` с ротацией:
- Максимальный размер файла: 100 MB
- Количество архивов: 5

## Мониторинг

Стек мониторинга (Grafana + Prometheus + Loki + nvidia-smi-exporter) описан в отдельном проекте [`llm-monitoring/`](../llm-monitoring/README.md). Для совместного запуска используйте скрипт `llm-stack.sh` из каталога мониторинга.
