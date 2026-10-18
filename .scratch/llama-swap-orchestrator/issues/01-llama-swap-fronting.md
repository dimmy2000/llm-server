# llama-swap как фронт нескольких backend'ов

Type: research
Status: resolved
Blocked by: —

## Question

Какие возможности llama-swap позволяют поставить **все три** backend'а
(llama.cpp, NInfer, vLLM) за один фронт на `:8080` с единым публичным
model-ID, и как при этом гарантировать, что backend'ы никогда не работают
параллельно?

Нужны факты по:

1. **Upstream/proxy.** Как llama-swap проксирует к внешнему OpenAI-совместимому
   процессу (vLLM в отдельном контейнере) — `proxy`, `peers`,
   upstream-passthrough. Может ли запись модели одновременно иметь `cmd`
   (дочерний процесс) и `proxy` (внешний контейнер), или это разные типы
   записей.
2. **Единственный публичный ID.** Можно ли держать один публичный model-ID
   `qwen3.8-27b`, за которым в разные моменты стоит разный backend; как
   `useModelName`, алиасы и `setParamsByID` взаимодействуют с переписыванием
   имени на backend'е (NInfer требует `request.model == --model-id`).
3. **Непараллельность.** Какие механизмы (`groups`, `matrix`, `ttl`,
   `unloadTimeout`, `capacity`) умеют выгружать один backend при старте
   другого и можно ли их выключить/не использовать, чтобы переключение
   осталось строго ручным.
4. **Жизненный цикл.** Что llama-swap делает с моделью, определённой как
   внешний upstream: пытается ли её «загрузить», видит ли в `/v1/models`,
   что показывает, когда backend лежит.
5. **Версия.** Какая версия llama-swap реально стоит в образе
   `ghcr.io/mostlygeek/llama-swap:cuda13`, и отличается ли её поведение от
   локального `../llama-swap` (при отставании — `git pull`, зафиксировать
   коммит/тег).

Источник истины — локальный репозиторий `../llama-swap` (`docs/kb/guides/routing/*`,
`docs/kb/guides/connectivity/*`, `config-schema.json`, исходники
`internal/`), а не пересказ в блогах.

## Answer

Кратко: основной подход зависит от версии образа. В **образе cuda13 (v240)** нет пин-профилей `profiles.pins`, поэтому переключение единого публичного ID через llama-swap не поддерживается напрямую. В **локальном репозитории (v264+)** есть `profiles.pins`. При любом подходе строгая взаимоисключаемость достигается либо держанием ровно одной локальной модели в конфиге (дефолтная группа swap/exclusive = одна за раз), либо использованием `peers` и переключением конфигурации вручную.

Ключевые факты:

- **1) cmd + proxy vs peers.** Модельная запись — всегда `cmd` (обязателен) + `proxy` (опционален, дефолт `http://localhost:${PORT}`) в одной записи. «Proxy-only» без `cmd` нет. Для внешнего уже работающего OpenAI-совместимого сервера (vLLM в отдельном контейнере) правильнее использовать **`peers`** (верхний уровень) — не управляет lifecycle. Если нужно, чтобы llama-swap сам запускал контейнер — `cmd: docker run ...` + `proxy` + `cmdStop`. Источники: `config-schema.json`, `internal/process/process_command.go`, `internal/router/peer.go`, `docs/kb/guides/connectivity/remote-peers.md`.
- **2) Единый ID.** `useModelName` переписывает имя только для локальных моделей. `aliases` глобальны. `setParamsByID` создаёт алиасы-варианты. В локальном репозитории есть **`profiles.pins`** (пины применяются до алиасов) — позволяет вручную переключать `qwen3.8-27b` между разными целями (локальная/peer/selector). В v240 пин-профили отсутствуют. Для NInfer требование `request.model == --model-id` выполняется через `useModelName`. Источники: `internal/server/filters.go`, `docs/kb/guides/routing/profiles-and-selectors.md`, `../ninfer/config.yaml`.
- **3) Непараллельность.** Дефолт — группа `swap:true, exclusive:true` (одна локальная модель за раз) — автоматическая выгрузка при запросе другой. `groups/matrix` управляют одновременной работой/eviction. `ttl/globalTTL` — автовыгрузка по простоям (выключить: `globalTTL:0`, `ttl:0`). `unloadTimeout` — таймаут shutdown, не механизм выгрузки. Ключа `capacity` в llama-swap нет (`concurrencyLimit/globalConcurrencyLimit` — лимиты запросов). Для строго ручного переключения без автоматического swap-переключения по запросу: иметь ровно одну локальную модельную запись в конфиге. Peer-модели не вызывают swap. Источники: `internal/config/config.go` (default group), `docs/kb/guides/routing/groups-and-matrix.md`, `docs/kb/guides/model-runtime/ttl-and-unloading.md`.
- **4) Жизненный цикл.** **Локальная модель (cmd+proxy)** — llama-swap пытается загрузить при запросе/preload, видна в `/v1/models` со статусом процесса. При лежащем backend'е при запросе запускает cmd, ждёт health check (`checkEndpoint`), при ошибке — 500 ("health check timed out" или "upstream command exited prematurely"). **Peer** — не пытается загрузить, виден в `/v1/models` как `type=peer` со статусом `"unloaded"`, при лежащем backend'е при запросе — 502 от peer-прокси. Источники: `internal/process/process_command.go`, `internal/router/peer.go`, `internal/server/api.go`.
- **5) Версия.** Образ `cuda13` → `version: v240 (6b5320d)`, собран 2026-07-15. Локальный репозиторий → `a2796fb` (2026-10-14), ~v264-3. **Критичное расхождение:** в v240 отсутствуют `profiles.pins` (пин-профили), `selectors` и `globalConcurrencyLimit` — эти механизмы есть только в свежем репозитории. Перед принятием решения о переключении через llama-swap-профили необходимо учитывать эту разницу.

Полный подробный отчёт: [`/home/dimmy/projects/00 infra/llm-server/docs/research/0011-llama-swap-multi-backend-fronting.md`](../../docs/research/0011-llama-swap-multi-backend-fronting.md) (с явным разделом «Fact vs unknown» и ссылками на источники).

## Comments

**2026-10-17 (тикет «Выбор версии образа llama-swap»).** Утверждение «образ
`cuda13` = v240» описывало только локально подтянутый образ. Сам тег
плавающий и с тех пор уехал: удалённо `cuda13` — тот же дайджест, что
`v265-cuda13-b11706` (llama-swap v265, llama.cpp `b11706`), а дайджест
запущенного локально образа в реестре отвечает 404. Версия роутера должна
быть `v265`, llama.cpp — `b10068`; см. `issues/09-llama-swap-version.md` и
`../assets/09-llama-swap-version/`.

