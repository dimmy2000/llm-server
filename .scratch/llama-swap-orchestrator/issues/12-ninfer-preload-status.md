# NInfer: preload падает 404 и статус `unloaded` при загруженном движке

Type: task
Status: resolved

## Question

В стартовом логе llama-swap (тикет 07, `assets/07-verify/pass2-kwargs/ninfer/container.log`):

```
[INFO] preloading model: backend-ninfer
[INFO] <backend-ninfer> Health check passed on http://localhost:5801/health
[ERROR] failed to preload model backend-ninfer: status 404
```

Двигатель при этом **уже загружен и прогрет** (первый реальный запрос
обслуживается за ~0.16 с), но `/v1/models` и дальше отдаёт
`status: {"value":"unloaded"}`.

Причина: llama-swap прелоадит модель запросом `GET /` (llama-swap
`internal/server/api.go:387-414`), а `ninfer-serve` обслуживает только `/health`,
на `/` отвечает 404. То есть прелоад технически «провалился», хотя прогреву это
не мешает (движок стартует как дочерний процесс и греется сам).

Решить, нужно ли это чинить и как:

1. Есть ли у NInfer `/` или другой путь, который llama-swap мог бы дёргать для
   прелоада (некоторый «warmup»-эндпоинт)? Посмотреть `ninfer-serve --help` и
   docs форка.
2. Если нет — можно ли заменить `hooks.on_startup.preload` на healthcheck-driven
   поведение, чтобы не было ERROR в логе.
3. Статус `unloaded` в `/v1/models`: это следствие провалившегося прелоада или
   отдельная логика llama-swap? Влияет ли он на потребителей (health-дашборды,
   launcher-скрипты, `llm-monitoring`)?

Оценить, насколько это косметика, а насколько — нарушение «единого контракта
состояния» единого endpoint'а.

## Answer

Разобрано на живом стеке (`llm-server/router:v265`, профиль `ninfer` активен,
2026-10-17). Доказательства — `assets/12-ninfer-preload-status/evidence.txt`.

**1. Warmup-эндпоинта у NInfer нет.** `ninfer-serve --help` (v0.4.6, снят из
образа router) объявляет только OpenAI Responses/Chat Completions и Anthropic
Messages; на живом upstream-порте `GET /` → 404, `GET /health` → 200,
`GET /v1/models` → 200. Патчить движок (добавлять обработчик `/`) — сборка из
исходников, вне карты.

**2. Заменить прелоад healthcheck-driven поведением нельзя — прелоад и есть
механизм старта.** В llama-swap единственный способ запустить движок на старте
— `hooks.on_startup.preload`: он шлёт через прокси внутренний `GET /` с
контекстом модели (`startPreload`, api.go:390-419, одинаково в v265 и HEAD
a2796fb), и именно этот запрос стартует дочерний процесс (лог: «preloading» →
«Health check passed»). Убрать прелоад = первый реальный запрос платит
загрузку — нарушение destination. Docker-HEALTHCHECK (`curl -f :8080/`)
трогает только UI-редирект llama-swap (302) и движки не запускает.

**3. `unloaded` — отдельная логика llama-swap, с провалившимся прелоадом не
связана.** В `handleListModels` записи пинов профиля всегда получают
жёстко прописанный `unloaded` (v265 `api.go:294-302`); в отличие от селекторов
(api.go:254-266, сверяются с `RunningModels`), пины состояние цели не
разрешают вообще. Проверено живьём: движок загружен (upstream healthy, GPU
14.7/15.3 GiB), а `/v1/models` отдаёт `status: unloaded` для `qwen3.8-27b`.

**4. Влияние на потребителей — нулевое.** `ModelPreloadedEvent{Success:false}`
не имеет подписчиков в коде llama-swap (emitted в пустоту; на UI/метрики не
влияет). `llm-monitoring` вообще не читает `/v1/models`; opencode и bench поле
`status` не используют. Реальное состояние доступно: `GET /api/profiles`
(active), SSE `/api/events` (`modelStatus()` через `RunningStatus` — видит и
unlisted-модели), `/health` upstream-порта.

**Оценка:** это косметика, «единый контракт состояния» не нарушен —
destination не обещает правдивый `status` в `/v1/models`, а источник правды
(активный профиль + запущенный процесс) наблюдаем через `/api/profiles` и UI.
Чинить в этой карте нечего: оба дефекта (404-на-прелоад, always-unloaded пин)
находятся в бинарнике llama-swap v265 и в движке NInfer — правка возможна
только форком/апстримом. Задокументировано: комментарий в
`router/config.yaml` (блок hooks); README/ADR-0006 — тикет 08. Опциональный
follow-up вне карты: upstream-issue в llama-swap — резолвить состояние цели
для пин-записей так же, как это делают селекторы (асимметрия очевидна в
одном файле).
