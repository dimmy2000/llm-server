# Включение-выключение модели через llama-swap

Дата среза: 2026-08-17.

Статус: исследование. Конфигурация, контейнеры и runtime в рамках работы не
изменялись. Все утверждения проверены по первичным источникам — клон
llama-swap commit `08f1076cb777e787eba3f57170350aa09513341a` (2026-08-16,
ветка main), `config-schema.json`, `README.md`, `docs/configuration.md`,
`config.example.yaml`, исходники `internal/` и `cmd/vllm-wrapper/`.

## Краткий вывод

У llama-swap нет понятия keepAlive модели и нет отдельного HTTP-эндпоинта
«загрузить модель». Жизненный цикл управляется парой ключей `ttl`
(автовыгрузка по простою) и `unloadTimeout` (graceful-таймаут до SIGKILL),
плюс ручной выгрузкой через `POST /api/models/unload[/{model_id}]`. Загрузка
всегда происходит по первому запросу; ключей «не автостартовать» нет —
только обходные пути (профили с пустым pin, `unlisted`, отсутствие модели в
группах).

В текущей конфигурации репозитория `cmd: "sleep infinity"` (llama/config.yaml:14)
дает только виртуальный on/off: llama-swap загружает/выгружает процесс-заглушку,
а реальный llama-server-контейнер и VRAM при unload не трогаются. Чтобы
получить настоящий on/off, нужно либо перенести запуск llama-server в `cmd`
llama-swap (вариант B), либо управлять контейнером с хоста и чистить состояние
llama-swap через API (вариант A).

## Что делает `cmd` и зачем `sleep infinity`

`cmd` — обязательное поле модели: в `config-schema.json` секция `models`
содержит `"required": ["cmd"]` с описанием «Command to run to start the
inference server»
([config-schema.json](https://raw.githubusercontent.com/mostlygeek/llama-swap/main/config-schema.json),
секция `models`). При пустом `cmd` загрузка падает с ошибкой `empty command` —
`internal/config/commands.go:38-41` (`SanitizeCommand`), вызов из `doStart` —
`internal/process/process_command.go:409-412`.

При старте модели llama-swap реально запускает `cmd` как дочерний процесс и
проксирует запросы на `proxy` (reverse-proxy создается в `doStart` —
`internal/process/process_command.go:404-560`). По умолчанию `proxy` равен
`http://localhost:${PORT}` (`internal/config/model_config.go:11,128`); в этом
репозитории переопределен на `http://llama-server:8080` (llama/config.yaml:13).

Вывод про `sleep infinity`: это не документированный прием llama-swap, а
локальная практика репозитория. `cmd` обязателен, но upstream (llama-server)
управляется отдельным Compose-сервисом, поэтому заглушка удовлетворяет
валидации и делает llama-swap чистым прокси. Следствие: TTL-выгрузка убьет
только `sleep`, а llama-server продолжит работать с моделью в VRAM, поэтому
on/off через llama-swap в текущей конфигурации виртуальный — меняется только
состояние процесса в `/v1/models` и `/running`.

## Ключи конфигурации жизненного цикла

Все значения — из `config-schema.json` (main) и исходников.

### Модельные ключи (`models.<id>.*`)

| Ключ | По умолчанию | Семантика | Источник |
|---|---|---|---|
| `ttl` | `-1` (= использовать `globalTTL`) | Автовыгрузка после `ttl` секунд простоя. `0` — никогда не выгружать | schema (`ttl`); `internal/config/model_config.go:84,132`; `internal/config/load.go:139-145` |
| `unloadTimeout` | `0` (= использовать глобальный) | Graceful-таймаут выгрузки (ручной, API, TTL) до SIGKILL. Глобальный дефолт `10` сек | schema; `internal/config/config.go:12` (`DEFAULT_UNLOAD_TIMEOUT = 10`); `load.go:86-88,148-153`; `internal/router/base.go:344-349` |
| `cmdStop` | `""` | Команда остановки вместо SIGTERM. Макрос `${PID}` | schema; `config.example.yaml:477-486`; `internal/process/process_command.go:572-591` |
| `checkEndpoint` | `"/health"` | Путь health-check при загрузке. `"none"` — пропустить. Опрос через reverse-proxy до HTTP 200 или `healthCheckTimeout` | schema; `internal/process/process_command.go:513-545` |
| `sendLoadingState` | наследует глобальный (`false`) | SSE-поток «загрузка модели» в `reasoning_content` для streaming-запросов во время swap | schema; `internal/config/model_config.go:108`; `load.go:181-184`; `internal/router/loading.go:16-27`; `internal/router/base.go:529-548` |
| `unlisted` | `false` | Скрыть из `/v1/models`, но запросы продолжают работать | schema; `internal/server/api.go:194-196` |
| `concurrencyLimit` | `0` (= 10) | Кап одновременных HTTP-запросов; превышение — HTTP 429 | schema; `internal/router/scheduler/fifo.go:15-17,361-366` |
| `timeouts.keepalive` | `30` | TCP keepalive соединения с upstream, НЕ жизненный цикл модели | schema; `internal/config/model_config.go:63,143`; `internal/process/process_command.go:424` |
| `compat.ignoreWebsockets` | `false` | WebSocket-соединения не участвуют в жизненном цикле (не грузят модель, не считаются в TTL-активности) | schema; `internal/config/model_config.go:71-75`; `internal/router/base.go:472-485` |

### Глобальные ключи

| Ключ | По умолчанию | Семантика | Источник |
|---|---|---|---|
| `globalTTL` | `0` (никогда) | Дефолтный TTL для всех моделей | schema; `internal/config/config.go:145`; `load.go:47,79-81,139-141` |
| `unloadTimeout` | `10` | Глобальный graceful-таймаут выгрузки | `config.go:12`; `load.go:83-88` |
| `healthCheckTimeout` | `120`, минимум `15` | Сколько ждать готовности модели при загрузке | schema; `load.go:40,63-65`; `internal/router/base.go:332-338`; `process_command.go:525-537` |
| `sendLoadingState` | `false` | Глобальный флаг SSE-статусов загрузки | schema; `internal/config/config.go:174` |
| `hooks.on_startup.preload` | `[]` | Список model-ID для предзагрузки при старте llama-swap | schema; `internal/server/api.go:375-404` |
| `profiles.<name>.pins` | — | Runtime-переписывание model-ID. Пустая строка или null «отключает» model-ID (запросы к нему не резолвятся) | schema (`profiles`); `internal/server/profiles.go:13-41`; `internal/config/load.go:311-335` |
| `upstream.ignorePaths` | regex статики | Пути, совпавшие с regex, не триггерят swap (для `/upstream/...`) | schema; `internal/server/api.go:513-533` |

### Чего нет (важно)

- `keepAlive` как ключ жизненного цикла модели не существует. В llama-swap
  `keepalive` — только TCP-таймаут (`timeouts.keepalive`). В llama.cpp есть
  свой `--keep-alive` (время жизни слотов в llama-server) — это параметр ядра
  из `llama/docker-compose.yaml`, к llama-swap отношения не имеет.
- `gracefulShutdown` не существует; аналог — `unloadTimeout` + `cmdStop`.
- `parallel` не ключ llama-swap (это флаг llama.cpp `--parallel`, число слотов).
  Ближайший аналог — `concurrencyLimit` (HTTP-кап).
- `startOnRequest`, `disabled`, `enabled` не существуют (проверено по полной
  схеме и структуре `ModelConfig` — `internal/config/model_config.go:77-121`).
- Отдельного HTTP-эндпоинта «загрузить модель» нет — загрузка происходит
  только по запросу или `preload`.

## HTTP API для управления on/off

Маршруты регистрируются в `internal/server/server.go:252-331`.

| Эндпоинт | Поведение | Источник |
|---|---|---|
| `POST /api/models/unload` | Выгрузить все запущенные локальные модели | `server.go:320`; `apigroup.go:137-142`; [README.md:48](https://github.com/mostlygeek/llama-swap/blob/main/README.md) |
| `POST /api/models/unload/{model_id}` | Выгрузить конкретную модель (404, если не найдена / не локальная) | `server.go:321`; `apigroup.go:144-159`; README.md:49 |
| `GET /unload` | Legacy: выгрузить все | `server.go:300`; `api.go:325-329` |
| `GET /running` | Список запущенных: `model, state, cmd, proxy, ttl, name, description` | `server.go:301`; `api.go:331-352`; README.md:47 |
| `GET /health` | Просто `OK` (без проверки upstream!) | `server.go:288`; `api.go:417-420`; README.md:60 |
| `GET /v1/models`, `GET /models` | Список всех моделей со статусом `"loaded"`/`"unloaded"` в `status.value` | `server.go:282-283`; `api.go:136-219` |
| `GET /upstream/{model}/` | Пасстхру к upstream; GET на этот путь — документированный способ «загрузить» модель (так UI-кнопка Load делает `fetch('/upstream/${model}/?_=...')`) | `server.go:311`; `api.go:481-543`; `ui/src/stores/api.ts:430-446`; README.md:44 |
| `GET /metrics`, `/logs*`, `/api/profiles`, `PUT /api/profiles/active`, `/api/inflight/{id}/cancel`, `/api/events`, `/api/version`, `/api/hardware`, `/ui` | Служебные | `server.go:284-331` |

Защита: все `/api/*`, `/v1/models`, `/logs` и т.п. проходят `authMW`
(`apiChain := chain.New(authMW)` — `server.go:254,266`); API-ключи задаются
`apiKeys` (schema; `internal/server/auth.go`). В текущем конфиге репозитория
`apiKeys` нет — эндпоинты открыты.

## Автостарт по запросу и «как не дать модели стартовать»

Запрос к остановленной модели всегда инициирует загрузку. Дерево решений
FIFO-планировщика: `OnRequest` → шаг 6 «start a new swap» → `StartSwap` →
`doSwap` → `EnsureReady` (с health-check и таймаутом) —
`internal/router/scheduler/fifo.go:94-141`; `internal/router/base.go:179-182,
243-276`. Несуществующая модель → `ErrModelNotFound` → HTTP 404
(`fifo.go:96-100`; `internal/swaputil/http.go:46,98-99`).

Ключей «не автостартовать» нет. Обходные пути (все подтверждены):

1. Профиль с пустым pin — `profiles` с `pins: {ornith-9b: ""}`; schema прямо
   говорит: «An empty string or null disables the model ID». При активном
   профиле model-ID в запросе переписывается в пустую строку
   (`profiles.go:13-41`), резолв не находится → HTTP 404 «no model id could be
   identified» (`swaputil/http.go:93-95`). Переключение профиля:
   `PUT /api/profiles/active` (`server.go:323`; `apigroup.go:69-95`). Это
   выключатель на уровне маршрутизации, но не освобождение VRAM.
2. `unlisted: true` скрывает из `/v1/models`, но запросы продолжают работать
   (schema; `api.go:194-196`), т.е. как выключатель не годится.
3. `groups`/`matrix` — модель, не входящая ни в одну группу, вообще не
   обслуживается (процессы создаются только для членов групп —
   `internal/router/group.go:31-52`), но это статическая настройка, не
   runtime-переключатель.
4. `upstream.ignorePaths` — только для `/upstream/` путей; если модель не
   загружена и путь совпал с regex — 409 без триггера swap (`api.go:513-533`).

## Как происходит выгрузка и что с in-flight запросами

TTL-выгрузка — `internal/process/process_command.go:306-325`:
- горутина-таймер тикает раз в секунду; выгрузка только если состояние
  `StateReady`, `inflight == 0` и `now - lastUse > ttl`;
- `lastUse` обновляется при завершении каждого запроса
  (`process_command.go:760-765`);
- при срабатывании: `p.Stop(unloadTimeout)`.

Ручная/API выгрузка — `FIFO.OnUnload` (`fifo.go:222-267`): выгружает процессы
синхронно (блокирует до остановки), ожидающие в очереди запросы к
выгружаемой модели получают ошибку, waiters незавершенных swap — тоже.
In-flight запросы не ждут: «In-flight requests being served by an unloaded
process are not waited for — Stop kills the upstream, those callers see
whatever error the reverse proxy surfaces and may retry» —
`internal/router/base.go:387-390`.

Механика остановки процесса — `killProcess` (`process_command.go:563-658`):
1. `sendStopSignal`: если задан `cmdStop` — выполняется он (с `${PID}`); иначе
   SIGTERM всей process group (`terminateProcessTree`);
2. ожидание до graceful-таймаута (`unloadTimeout`, по умолчанию 10 сек; для
   eviction при swap — `healthCheckTimeout`, `base.go:243-256`);
3. если жив — SIGKILL process group.

Другие причины выгрузки: swap-eviction при запросе другой модели (группы:
`internal/router/group.go:59-104`), hot-reload конфига (`llama-swap.go:202-304`
— старый сервер полностью Shutdown, т.е. все модели выгружаются; включается
флагом `--watch-config`, в этом репозитории не используется), остановка
llama-swap.

## Практические варианты для этого репозитория

Текущая схема (llama/config.yaml:14 — `cmd: "sleep infinity"`) дает только
виртуальный on/off. Варианты:

**Вариант A — оставить прокси-схему, управлять реальным контейнером с хоста
(минимальные изменения).**
- Выключение: `docker compose --profile llama stop llama-server`
  (совместимо с AGENTS.md — ядро по-прежнему в compose). Выгрузка
  «виртуальной» модели: `curl -X POST http://localhost:8080/api/models/unload/ornith-9b`
  — чистит состояние в `/v1/models` и `/running`.
- Включение: `docker compose --profile llama start llama-server` + первый
  запрос (или `curl http://localhost:8080/upstream/ornith-9b/` для
  принудительной загрузки состояния).
- Ограничение: llama-swap не знает о реальном состоянии контейнера
  (health-check только при загрузке, `checkEndpoint: "none"`); запросы во
  время простоя вернут ошибку reverse-proxy (502/503), а не авто-пробуждение.
- Опционально: заменить `checkEndpoint: "none"` на `"/health"` — тогда при
  загрузке llama-swap будет проверять реальную готовность llama-server
  (медленнее переход в Ready, но честнее; `process_command.go:513-545`).

**Вариант B — перенести запуск llama-server в `cmd` llama-swap (реальный on/off
с TTL).**
- Образ `ghcr.io/mostlygeek/llama-swap:cuda13` — это legacy-образ на основе
  `ghcr.io/ggml-org/llama.cpp:server-cuda13` (docker/llama-swap.Containerfile:1-3;
  платформа `cuda13` в .github/workflows/containers.yml:37; BASE_TAG
  `server-${ARCH}-${LCPP_TAG}` в docker/build-container.sh:126-129), т.е. бинарь
  `llama-server` внутри контейнера llama-swap есть.
- Тогда `cmd: llama-server --port ${PORT} ...` (макрос `${PORT}`,
  `startPort: 5800`), `ttl: 60` и т.п. — выгрузка реально убьет llama-server
  (SIGTERM), VRAM освободится, следующий запрос — cold start.
- Trade-off (флаг по AGENTS.md): все kernel args (`--model`, `--ctx-size`,
  `--flash-attn`, ...) сейчас живут только в `llama/docker-compose.yaml`; их
  перенос в `cmd` — решение о переносе конфигурации, плюс придется:
  - добавить сервису `llama-swap` GPU-резервации и volume
    `/opt/models:/models:ro` (сейчас их нет — llama/docker-compose.yaml:44-53
    vs 6-16);
  - удалить сервис `llama-server` из compose (или оставить выключенным) и
    `depends_on`;
  - помнить: `healthCheckTimeout` у репозитория `300`, проверка пойдет через
    reverse-proxy на реальный `/health` llama-server.
- TTL-семантика при этом честная: `ttl` + `unloadTimeout` работают ровно как
  описано в разделе выше.

**Вариант C — `cmdStop: docker stop llama-server` — отклонен:** `cmdStop`
выполняется внутри контейнера llama-swap, где нет docker CLI и docker.sock (не
смонтирован). Потребовался бы привилегированный маунт — плохая практика.
Документированный docker-паттерн llama-swap (`cmd` + `cmdStop: docker stop ${MODEL_ID}`,
config.example.yaml:468-486) предполагает, что `cmd` сам запускает контейнер —
это вариант B с `docker run`, тоже требует docker.sock.

**Вариант D — vLLM-профиль (справка на будущее):** для vLLM llama-swap
официально предоставляет `vllm-wrapper` (входит в unified-образ):
`cmd: vllm-wrapper serve ...` / `cmdStop: vllm-wrapper sleep` поверх vLLM
`--enable-sleep-mode` — сон без остановки процесса, почти мгновенное
пробуждение, освобождение VRAM (cmd/vllm-wrapper/README.md). Для llama.cpp
аналога сна нет — только полный stop/start.

Общее: смена `llama/config.yaml` требует рестарта `llama-swap` (AGENTS.md;
hot-reload `--watch-config` в compose не включен, а при reload все модели
выгружаются — llama-swap.go:263-265).

## Подтверждено vs спекуляция

Подтверждено первичными источниками:
- `ttl`/`globalTTL`/`unloadTimeout` — точные ключи и семантика (schema +
  process_command.go:306-325, base.go:344-349).
- `cmd` обязателен (schema `required`, commands.go:38-41); `cmdStop` с `${PID}`
  (process_command.go:572-591).
- Эндпоинты `POST /api/models/unload[/{model_id}]`, `GET /unload`, `GET /running`,
  `/health`, `/v1/models` со статусами, `GET /upstream/{model}/` как способ
  принудительной загрузки (server.go, api.go, apigroup.go,
  ui/src/stores/api.ts:430-446).
- Автостарт по первому запросу безусловен; ключей `disabled`/`startOnRequest`
  нет (schema полностью).
- Пустой pin профиля = отключение model-ID (schema + profiles.go +
  load.go:311-335).
- In-flight запросы при выгрузке не ждут (base.go:387-390, fifo.go:222-267).
- `keepAlive`/`gracefulShutdown`/`parallel` как ключи llama-swap отсутствуют;
  `keepalive` — только TCP (schema, model_config.go:63).
- Образ `llama-swap:cuda13` содержит llama-server (Containerfile,
  build-container.sh, workflows).
- Отдельного «start/load» HTTP-эндпоинта нет — только через запрос/preload.

Спекуляция / не подтверждено:
- «sleep infinity» как рекомендуемый прием llama-swap — в доках не встречается
  (grep по README/docs/config.example: 0 совпадений); это локальный идиом
  репозитория.
- Временные оценки cold start при варианте B (скорость загрузки 9B-Q8 на
  5070 Ti) не проверялись — нужен замер.
- Поведение llama-server на SIGTERM (освобождает ли VRAM мгновенно, завершает
  ли слоты) — свойство llama.cpp, вне llama-swap; рекомендуется проверка.
- Комментарий в config.example.yaml:484 «processes have 5 seconds to shutdown»
  расходится с кодом (дефолт `unloadTimeout = 10`, config.go:12) — код
  авторитетнее.

## Источники

- [README](https://github.com/mostlygeek/llama-swap/blob/main/README.md) —
  API-список (строки 44-67); ttl/unloadTimeout (224-225).
- [docs/configuration.md](https://github.com/mostlygeek/llama-swap/blob/main/docs/configuration.md)
- [config-schema.json](https://raw.githubusercontent.com/mostlygeek/llama-swap/main/config-schema.json)
- [config.example.yaml](https://github.com/mostlygeek/llama-swap/blob/main/config.example.yaml) —
  docker+cmdStop (468-486); ttl (295-307); unloadTimeout (303-307).
- Исходники: клон llama-swap commit `08f1076cb777e787eba3f57170350aa09513341a`
  (2026-08-16): `internal/...`, `llama-swap.go`,
  `docker/llama-swap.Containerfile`, `docker/build-container.sh`,
  `.github/workflows/containers.yml`, `ui/src/stores/api.ts`,
  `cmd/vllm-wrapper/README.md` — номера строк указаны в тексте.
- Официального сайта документации `llama-swap.mostlygeek.dev` не существует
  (транспортная ошибка при обращении) — документация живет только в
  репозитории.