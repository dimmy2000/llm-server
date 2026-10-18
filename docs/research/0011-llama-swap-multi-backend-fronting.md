# llama-swap как фронт нескольких backend'ов

Дата: 2026-10-17. Статус: исследование.

## Источники истины

- Локальный репозиторий: `/home/dimmy/projects/00 infra/llama-swap` (commit `a2796fb`, 2026-10-14, ~v264-3). Файлы: `docs/kb/guides/routing/*.md`, `docs/kb/guides/connectivity/*.md`, `docs/kb/guides/model-runtime/*.md`, `config-schema.json`, `internal/config/*.go`, `internal/server/filters.go`, `internal/router/*.go`, `internal/process/process_command.go`. При необходимости — `git pull` в локальном репозитории.
- Образ `ghcr.io/mostlygeek/llama-swap:cuda13`: из docker inspect на момент исследования — `version: v240 (6b5320d)`, `org.opencontainers.image.created 2026-07-15`. Разница с локальным репозиторием (v240 → v264+) существенна по ключевым механизмам (пин-профили `profiles` с `pins` отсутствуют в v240; `globalConcurrencyLimit` отсутствует; `selectors` отсутствуют в текущем виде и т.д.).
- Текущие конфиги проекта: `../llama/config.yaml`, `../ninfer/config.yaml`, `../vllm/config.yaml`, `../docker-compose.yaml`, `../llama/docker-compose.yaml`, `../ninfer/docker-compose.yaml`, `../vllm/docker-compose.yaml`.
- ADR/исследования: `../docs/adr/0003-ninfer-profile-llama-swap.md`, `../docs/research/0009-ninfer-tp2-two-5070ti.md`.

## 1. Upstream/proxy: cmd vs proxy, "proxy-only" vs peers

### Факты (локальный репозиторий)

- `models.*` — модельная запись обязана иметь `cmd` (required: ["cmd"], minLength 1). `proxy` опционален (по умолчанию `http://localhost:${PORT}`). См. `config-schema.json` (properties.models.additionalProperties.required → ["cmd"]; properties.proxy default). Источник: `/home/dimmy/projects/00 infra/llama-swap/config-schema.json`.
- `cmd` запускает дочерний процесс llama-swap (exec.CommandContext). `proxy` — URL, куда llama-swap проксирует запросы к этому процессу. См. `internal/process/process_command.go`: использует `p.config.Proxy`, парсит `url.Parse`, запускает `httputil.NewSingleHostReverseProxy(proxyURL)`. Источник: `internal/process/process_command.go:461–474`, `internal/process/process_command.go:520–560`.
- Вариантов «либо cmd, либо proxy» нет — это разные поля одной и той же модельной записи. Невозможно создать «proxy-only» модель без `cmd` по схеме. При `checkEndpoint: none` процесс может быть запущен как no-op/блокирующий, однако lifecycle остаётся под управлением llama-swap (если cmd сразу завершается — процесс уйдёт в stopped и при следующем запросе попытается стартовать заново). См. `internal/process/process_command.go:564–600`, `config-schema.json`.
- Альтернативный способ проксирования к внешнему серверу без запуска дочернего процесса — **peers** (раздел верхнего уровня `peers:`). Peers — это чистый прокси к удалённому llama-swap или любому OpenAI-совместимому серверу. Для peer модель адресуется как `<peerID>/<modelID>`; нефинальный (unqualified) ID работает только когда ровно один peer её предоставляет и локальные/alias-модели не перехватывают его. Локальные модели всегда имеют приоритет перед peer-моделями при диспетчеризации. См. `docs/kb/guides/connectivity/remote-peers.md`, `docs/kb/examples/peers-and-multi-host.md`, `internal/server/api.go:200–250`, `internal/server/api.go:523–545`, `internal/router/peer.go`.

### Факты (образ v240, для контраста с развернутым)

- В v240 `cmd` тоже обязателен (есть `UseModelName`, `Models map[string]ModelConfig` с `Cmd`), `proxy` дефолтный. Peers поддерживаются как generic proxy к любому OpenAI-совместимому (не только llama-swap). Но отсутствуют `profiles` с `pins`, `selectors` в том виде, что описывается в свежих доках. См. результаты сравнения по тегу v240 выше.

### Вывод по Q1

- Модельная запись не может быть одновременно «только proxy» и «только cmd» — это единый тип (`cmd` + `proxy`). Запись с `proxy`, указывающим на внешний контейнер (vLLM, NInfer), и `cmd`, который ничего не делает/блокирует — теоретически возможна при аккуратном `checkEndpoint`/жизненном цикле, но **не является штатным «proxy-only» типом**. Штатный путь для внешнего (уже запущенного отдельно) OpenAI-совместимого сервера — `peers` (внешний сервер не управляется llama-swap). Если же нужно, чтобы llama-swap стартовал контейнер — `cmd` запускает `docker run ...` с `cmdStop: docker stop ...` (пример: `docs/kb/guides/upstreams/comfyui.md`).


## 2. Единственный публичный ID `qwen3.8-27b`

### Факты (локальный репозиторий, v264)

- `useModelName` переписывает модель, отправляемую на upstream (локальную модель), для JSON и multipart/form-data. Применяется к локальным моделям через middleware, на peer-модели не применяется (peer сам решает, каким именем посылать). См. `internal/server/filters.go:71–120` (CreateFilterMiddleware/CreateFormFilterMiddleware, `resolveFilters`: локальные → берёт `mc.UseModelName`, peers → пусто).
- Алиасы моделей: `models.*.aliases` — альтернативные имена для той же конфигурации. Глобально уникальны (валидация). В `/v1/models` алиасы показываются при `includeAliasesInList: true` (как отдельные записи типа `alias` с `modelID`). См. `config-schema.json`, `docs/config.example.yaml` (aliases), `internal/server/api.go:222–247`.
- `setParamsByID` создаёт автоматические алиасы для каждого ключа в карте — клиенты могут запрашивать `model:key` как отдельный ID, параметры применяются в порядке: stripParams, setParams, setParamsByID. См. `docs/kb/guides/api-integration/filters-and-request-rewriting.md` (порядок 1–6), `internal/server/filters.go:140–200` (applyFilters).
- Профили (`profiles`): в локальном репозитории есть пин-база `profiles.<name>.pins` (map ключ=запрашиваемый ID → цель, может быть null для отключения). Пины применяются до алиасов/фильтров/роутинга? Docs: «Pins are applied first, before aliases, filters and routing.» (profiles-and-selectors.md). Целью может быть локальная модель, FQN peer-модели (`peer/model`), alias, setParamsByID-alias, селектор. См. `docs/kb/guides/routing/profiles-and-selectors.md`, `internal/config/config.go:248–250` (ProfileConfig), `internal/config/load.go` (validateProfiles), `config-schema.json` (pins).
- Селекторы (`selectors`): виртуальный ID резолвится по стратегии (warm/pin/spillover) **на каждый запрос**. Целями не могут быть селекторы. Не поддерживаются на `/upstream/<model>`. См. `docs/kb/guides/routing/profiles-and-selectors.md`, `internal/config/selectors.go`.

### Факты (v240 — контраст с текущим образом)

- В v240 пин-профили (`profiles` с map pins) отсутствуют; вместо них была реализована иная семантика (группы). Документация warns «Profile functionality has been removed in favor of Groups». См. `v240/internal/config/config.go:134` (`Profiles map[string][]string` в v240) и предупреждения в коде. Селекторы в v240 отсутствуют.
- Следовательно, возможность держать один публичный ID и переключать его на разные бэкенды **через `profiles.pins`** есть только в версиях после v241 (в текущем локальном репозитории есть). В образе v240 этой возможности нет. Это ключевой delta между тем, что описано в docs свежего репозитория, и тем, что реально работает в `cuda13` образе.

### Взаимодействие с переписыванием имени (NInfer требует `request.model == --model-id`)

- `useModelName` переписывает имя только на **локальном** upstream. Если NInfer ожидает конкретное `--model-id`, то в модели должен быть `useModelName: <expected>` — это гарантирует, что в запросе к движку окажется именно это имя (включая после применения алиасов/пинов). См. `internal/server/filters.go:71–145` (UseModelName rewrite).
- `setParamsByID` создаёт алиасы, но не переписывает `model` сам по себе — переписывание `model` выполняет `applyFilters` (useModelName блок). Порядок: сначала резолвятся пины/алиасы (RealModelName), потом применяются фильтры (useModelName, stripParams, setParams, setParamsByID). См. `internal/server/filters.go:140–200`, порядок из docs (п.1–6 в разделе filters-and-request-rewriting).
- Для NInfer в текущем проекте: `useModelName: qwen3.8-27b` обязателен, алиасы режимов задаются через `setParamsByID` (ключи вида `qwen3.8-27b-chat-*`, `qwen3.8-27b-agent-*`). Клиент запрашивает такой ID — он резолвится как алиас реальной модели; `useModelName` переписывает тело запроса на каноническое `qwen3.8-27b` перед отправкой в NInfer. Это соответствует описанию в `ninfer/config.yaml` (комментарии про требование NInfer). Источник: `../ninfer/config.yaml:60–128`.

### Вывод по Q2

- **Да**, в текущем локальном репозитории (v264) один публичный ID `qwen3.8-27b` можно в разные моменты обслуживать разным бэкендом путём **профилей с pins** (`profiles.<p>.pins: { "qwen3.8-27b": "backend-llama" | "peer-ninfer/ninfer-model" | ... }`) с переключением активного профиля (API/UI). Также возможны варианты через селекторы (автоматические) или через разные конфиги (ручное переключение конфига целиком).
- В образе `cuda13` (v240) **пин-профили отсутствуют**; возможность единым публичным ID переключать бэкенд там ограничена и требует иного подхода (например, иметь разные конфиги/разные точки входа, либо переключать модельные записи другими способами).
- `useModelName` → только локальный upstream, переписывает тело запроса на нужное имя (обход требования `request.model == --model-id`). `aliases` → глобальные алиасы, видны в `/v1/models` при включении флага. `setParamsByID` → создаёт алиасы-варианты с разными параметрами (не меняет реальный процесс). Все эти механизмы работают **после** резолва пинов/алиасов и **перед/в ходе** применения фильтров согласно описанному порядку.

## 3. Непараллельность: как выгружать один backend при старте другого, можно ли выключить

### Факты (локальный репозиторий)

- По умолчанию (без `routing`) работает **одна локальная модель за раз** (instance-wide). Это обеспечивается router'ом по умолчанию: `AddDefaultGroupToConfig` создаёт дефолтную группу со всеми локальными моделями, `swap: true, exclusive: true`. Источник: `internal/config/config.go:329–375` (добавление дефолтной группы), `docs/kb/guides/routing/groups-and-matrix.md` («group — default, simpler»).
- Механизмы маршрутизации (при наличии `routing`): `group` (swap, exclusive, persistent) и `matrix` (выражения + evict_costs). См. `docs/kb/guides/routing/groups-and-matrix.md`.
- Автовыгрузка по неактивности: `globalTTL` (0 = никогда), `models.*.ttl` (-1 наследует, 0 никогда, >0 сек). `unloadTimeout` — таймаут на graceful shutdown. Peers в TTL/eviction не участвуют (не управляются llama-swap). См. `docs/kb/guides/model-runtime/ttl-and-unloading.md`, `config-schema.json`.
- Параллелизм запросов: `concurrencyLimit` (на модель), `globalConcurrencyLimit` (глобальный семафор; в v240 отсутствует). При превышении глобального лимита — HTTP 429 немедленно (без очереди). См. `docs/kb/guides/routing/capacity-and-queues.md`, `config-schema.json`.
- **Вопрос 3 просит конкретный список ключей**: `groups`, `matrix`, `ttl`, `unloadTimeout`, `capacity`. `capacity` как отдельного ключа в llama-swap нет (вероятно имелось в виду `concurrencyLimit`/параметры capacity). Конфиги групп/матрицы влияют на выгрузку при старте другой модели (swap/eviction). TTL — автовыгрузка по простоям, не «при старте другого», а по времени. См. выше.
- Чтобы **переключение оставалось строго ручным** (без автоматической выгрузки при запросе другой модели и без автовыгрузки по времени):
  - Если используются только **локальные** модели: либо держать ровно **одну** локальную модельную запись в конфиге (тогда дефолтная группа её содержит и других нет — автоматического swap по запросу другой нет, т.к. другой нет). Либо не запрашивать другие локальные модели. Обратить внимание: дефолт `swap:true, exclusive:true` означает, что при запросе модели B, которая есть в той же группе, модель A будет выгружена. Это **автоматическое** поведение при запросе, а не «ручное переключение». Чтобы избежать автоматического переключения по запросу, нужно не иметь нескольких моделей, доступных для запроса одновременно, либо сконфигурировать группы так, чтобы они не конфликтовали — но проще: иметь ровно одну локальную модель в конфиге на время работы конкретного backend'а.
  - **Peerc»-модели** не участвуют в swap/grovps TTL (они проксируются напрямую, lifecycle вне llama-swap). Поэтому если использовать peer для vLLM (внешний контейнер), локальные модели не будут выгружаться из-за него автоматически по механике swap groups (это другой роутерный путь: локальный vs peer).
  - Выключить TTL: `globalTTL: 0`, у всех моделей `ttl: 0` или `-1` (наследует globalTTL). Это выключает автовыгрузку по простоям.
  - Группы/матрицу можно **не определять** вовсе — будет применён дефолт (одна модель за раз). Если вы хотите, чтобы вообще **никакой** автоматической выгрузки при старте/запросе другой не происходило — необходимо, чтобы не было нескольких локальных моделей, которые роутер может выбрать. Вариант: держать в конфиге ровно одну локальную модельную запись; peer-модели живут в другом роуте.
- Ключ `capacity` в llama-swap отсутствует. См. `config-schema.json` (нет ключа `capacity` на верхних уровнях/в routing).

### Вывод по Q3

- Механизмы выгрузки: дефолтная группа (swap/exclusive) — выгружает одну локальную модель при старте/запросе другой; `groups.matrix` (matrix) — решает наборы для одновременной работы и решает, кого выгружать по evict_costs; `ttl/globalTTL` — выгружает по неактивности; `unloadTimeout` — не механизм выгрузки, а таймаут её завершения. `capacity` отсутствует. `concurrencyLimit/globalConcurrencyLimit` ограничивают параллельные запросы, не управляют выгрузкой backend'ов.
- Для **строго ручного** переключения без автоматической выгрузки при запросе другой модели: держите ровно **одну локальную модельную запись** в активном конфиге llama-swap (либо не объявляйте вторую локальную модель как доступную). Если использовать **peers** — peer-модели не вызывают swap локальных моделей. Отключите TTL: `globalTTL: 0`, `models.*.ttl: 0` (или -1 с globalTTL 0). Оставить groups/matrix не заданными — нормально при единственной локальной модели.

## 4. Жизненный цикл модели, определённой как внешний upstream

Важно: в llama-swap нет отдельного «external upstream model type». Есть два пути:

### A. Локальная модельная запись (`cmd` + `proxy`) — llama-swap управляет дочерним процессом
- При запросе (или при preload/hook) llama-swap запускает `cmd`, ждёт health check (`checkEndpoint`, дефолт `/health`; можно `none`). Если `checkEndpoint: none` — пропускает ожидание и помечает как готовый сразу после старта (но процесс может выйти). Источник: `internal/process/process_command.go:564–650`.
- Состояние видимо в `/v1/models` через `status` записи (локальные модели имеют статус `process.State`). В текущем коде локальные модели попадают в список со статусом, вычисляемым `modelStatus(id)`. Peer/aliases попадают иначе. См. `internal/server/api.go:200–250` (модельные записи для локальных → `status := modelStatus(id)`; peer → `"unloaded"`).
- Если backend лежит (процесс не запущен, health не проходит, процесс завершился) — при запросе llama-swap **попытается его «загрузить»** (запустить cmd, ждать health check). При неуспехе (health timeout, premature exit) возвращает 500 с сообщением (например, "upstream command exited prematurely", "health check timed out"). См. `internal/process/process_command.go` (старт и ошибки), `internal/router/loading_test.go` (примеры ошибок).
- В `/v1/models` локальная модель отображается даже если не загружена — её статус отражает состояние (stopped/starting/ready и др.). См. `internal/server/api.go` (модельные записи добавляются для всех `cfg.Models`).

### B. Peer (`peers:`) — внешний OpenAI-совместимый сервер, без lifecycle
- llama-swap **не пытается «загрузить»** peer. Он просто проксирует запрос при обращении к `<peerID>/<modelID>` (или unqualified при уникальности). См. `internal/router/peer.go`, `internal/server/api.go:523–545`.
- В `/v1/models` peer-модели всегда присутствуют со статусом `"unloaded"` и метаданными типа `peer`. См. `internal/server/api.go:230–247`.
- Когда backend лежит — запрос к peer-модели сразу проксируется в `proxy` URL; при соединении/ответе peer'а вернётся 502 `peer proxy error: ...` (вместо попытки старта). См. `internal/router/peer.go:140–185` (ErrorHandler peer).

### Вывод по Q4

- **Локальная модельная запись** (cmd+proxy): llama-swap **пытается загрузить** её при первом запросе (и может по preload). В `/v1/models` она видна; статус показывает состояние процесса. Когда backend лежит — при запросе запускается cmd, health check, при сбое ответ — 500 с соответствующим сообщением.
- **Peer** (peers.*): llama-swap **не пытается загрузить** его. В `/v1/models` виден как peer со статусом "unloaded". Когда backend лежит — прямая проксирующая ошибка 502 от peer-router'а.
- «Внешний upstream» в терминологии llama-swap чаще относится к проксируемому upstream'у (proxy/peer), но концептуально нет отдельного типа без cmd. Штатный путь к уже работающему внешнему OpenAI-совместимому контейнеру — peer.

## 5. Версия llama-swap в образе vs локальная

- Образ `ghcr.io/mostlygeek/llama-swap:cuda13`: `llama-swap --version` → `version: v240 (6b5320d), built at 2026-07-15T01:08:41Z`. (Проверено docker run на момент исследования.)
- Локальный репозиторий `../llama-swap`: HEAD `a2796fb` (2026-10-14), теговое описание ~`v264-3-ga2796fb` (последний тег v264 от 2026-10-11). См. `git log -1 --format='%H %ci %d'`, `git describe --tags`.
- Отставание: ~3 коммита после v264 локально относительно текущего HEAD? Либо HEAD — a2796fb, v264 — 3 коммита до него. По reflog локальный репозиторий был в 41ec321 (clone), затем сделан pull → a2796fb.
- Критические различия (поведение релевантно для архитектурных решений):
  - Пин-профили (`profiles` с `pins`): есть в локальном (v264+), **отсутствуют** в v240. В v240 была другая семантика профилей (удалена в пользу groups).
  - Selectors: есть в локальном, отсутствуют в v240.
  - `globalConcurrencyLimit`: есть в локальном, **отсутствует** в v240.
  - Некоторые поля/семантика docs (routing, profiles/selectors) описывают поведение более свежей версии, чем лежит в `cuda13` образе.
- GitHub-репозиторий upstream: `https://github.com/mostlygeek/llama-swap` (origin). Теги по дате: v264 (2026-10-11) — последний на момент проверки. Образ `cuda13` основан на v240 (2026-07-15). Это **стабильный движковый тег образа**, но функционально старше локального репозитория.

## Fact vs unknown

### Факты (установлены)

- Модельная запись требует `cmd` (обязателен), `proxy` дефолтный. Нет «proxy-only» типа модели — есть модель (cmd+proxy) vs peer (отдельный раздел).
- Peer — чистый прокси, не управляет lifecycle; модели peer видны в `/v1/models` как type=peer со статусом "unloaded", запрос проксируется напрямую, ошибка при падении backend'а → 502.
- Локальная модель (cmd+proxy) — llama-swap пытается её загрузить, в `/v1/models` статус отражает состояние; при падении при запросе пытается стартовать, ошибки старта/health check → 500.
- Диспетчеризация: локальные модели имеют приоритет перед peer-моделями.
- Default: одна локальная модель за раз (group swap/exclusive). TTL/конкурентность — как описано. Ключа `capacity` в llama-swap нет.
- `useModelName` применяется только к локальным upstream; переписывает model в теле запроса. `aliases`, `setParamsByID` — работают по описанному порядку. В локальном репозитории есть `profiles.pins` + переключение активного профиля; в образе v240 они отсутствуют.
- Разница версий: образ v240 (6b5320d, 2026-07-15) vs локальный репозиторий a2796fb (2026-10-14, v264-3). Это важный контекст для любого планирования архитектуры на основе текущего образа.

### Unknown / требует уточнения

- Поведение при `cmd` = no-op + `checkEndpoint: none` в боевых условиях (race между выходом cmd и health-check/polling) не было подробно исследовано в рамках этого отчёта — достаточно теории из кода.
- Точная применимость `profiles.pins` для переключения между локальной моделью и peer-моделью в конкретной конфигурации (с учетом приоритета локальных над peer и уникальности ID) требует практической проверки на целевой конфигурации (особенно с учётом версии образа).
- Что именно содержится в образе `cuda13` в плане build-ветки llama.cpp/llama-swap (бинарь llama-swap v240, но внутри образа могут быть иные библиотеки) — за рамками этого исследования (не критично для вопросов контрактов).

## Ссылки на артефакты

- Исходники, задействованные в выводах: `internal/config/config.go`, `internal/config/model_config.go`, `internal/config/peer.go`, `internal/config/selectors.go`, `internal/server/filters.go`, `internal/server/api.go`, `internal/router/peer.go`, `internal/process/process_command.go`, `config-schema.json`, `docs/kb/guides/*`.
- Конфиги проекта: `../llama/config.yaml`, `../ninfer/config.yaml`, `../vllm/config.yaml`.
- Docker/compose: `../docker-compose.yaml`, `../llama/docker-compose.yaml`, `../ninfer/docker-compose.yaml`, `../vllm/docker-compose.yaml`.
