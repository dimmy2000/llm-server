# Конфигурация llama-swap: strata-iq3 / strata-iq2

> **Архив 2026-10-19:** карта переработана под автоматический swap по запросам к llama-swap — это решение первой итерации устарело (полностью или частично); ещё-валидные факты перенесены в Notes map.md. История сохраняется как справочник.

Status: resolved
Type: task
Blocked by:

## Question

(Исполняемый тикет, AFK) Настроить llama-swap v265 на публикацию двух новых публичных ID
через shim-модели, не трогая родительский контракт `backend-llama`/`backend-ninfer`:

- `router/config.d/30-strata.yaml`: модели `strata-iq3` и `strata-iq2` — **видимые**
  (не `unlisted`; это осознанный пересмотр ADR-0006, зафиксированный в Notes карты).
  Каждая: `cmd: sleep infinity` (shim, long-running обязателен — `prematureExit`),
  `proxy: http://<host>:8081`, `checkEndpoint: /health`; `useModelName`: Strata
  принимает any model name (README; карта selection, тикет 02), так что per-shim
  `useModelName` скорее не нужен — проверить на живом `/v1/chat/completions`, что
  имя не стрипается и ответ возвращается с запрошенным ID.
- Сеть из контейнера: нативный Strata слушает `--host 0.0.0.0` (`:8081`) — host IP или
  `extra_hosts: host.docker.internal:host-gateway`; решить конкретно на этом хосте.
- Профили: родительские `llama`/`ninfer` остаются как есть (`qwen3.8-27b` → их backend);
  вопрос, нужен ли профиль-владелец для strata-ID (или прямые запросы к ID достаточно) —
  решить по коду v265 (pins/unlisted/unload-семантика для видимых моделей) и зафиксировать.
- `docker compose restart llama-swap` после правок; проверка `GET /v1/models` — три ID:
  `qwen3.8-27b`, `strata-iq3`, `strata-iq2`.

Resolved when: `/v1/models` публикует ровно три ID; запрос к каждому отвечает
(родители — на своих движках, strata-ID — на нативной Strata `:8081` правильного размера);
в `AGENTS.md`-контракте появился черновой маячок (финализирует тикет «Документация»).

## Answer

(2026-10-19, живой стек; сырьё — `../assets/01-test-log.md` + снимки конфигов)

**Сделано.** Новый `router/config.d/30-strata.yaml` (strata-iq3 @131072 /
strata-iq2 @262144, видимые); пины в `router/config.yaml`; `extra_hosts`
host-gateway в `router/docker-compose.yaml`; нативные конфиги `/opt/strata/*.json`
(port 8081→8082, bind 172.17.0.1) с before-снимками в assets; черновой маячок в AGENTS.md.
`docker compose up -d` (recreate) + `restart` после правок — `/v1/models` отдаёт
ровно `qwen3.8-27b, strata-iq2, strata-iq3`; оба strata-ID и оба открытых статуса
проверены живыми запросами через `:8080` (non-stream + stream на iq3, non-stream
на iq2), родители целы (qwen3.8-27b на ninfer 200).

**Имена shim-моделей.** Shim-модели названы прямо публичными ID (без
backend-посредников и alias'ов — промежуточное имя ничего не добавляет, а пины
профилей ссылаются на реальные имена моделей). `useModelName` не нужен:
Strata-сервер отрабатывает любой `model` запроса (model_for), но поле `model`
в ответе — канон native-ID (`qwen3.8-flash-next-iq3_xxs`/`…-iq2_xs`),
llama-swap ответ не переписывает — клиентов предупредить не сверять `model`
ответа с запрошенным ID (в тикет 03).

**Решение по профилям (вопрос тела тикета).** Прямые запросы к ID без
профиля-владельца отклонены: нужны два страта-профиля —
по одному на размер (`strata-iq3`, `strata-iq2` с пинами
`~` на родителя `qwen3.8-27b`, backend-llama/backend-ninfer и соседний
размер); в родительских llama/ninfer strata-ID закрыты пинами `~`.
Обоснование по коду v265: пины работают только над запрошенным именем
(CreateProfileMiddleware) и не производят ни start, ни stop — переключение
профиля ничего не грузит; значит (a) незакрытый strata-ID под родительским
профилем стартовал бы shim по случайному запросу, выгнал бы родительский
движок (дефолтная exclusive-группа останавливает живой процесс) и завис на
мёртвом upstream — недопустимо; (b) 404 пина — быстрый чистый отказ;
(c) честность переключения держит strata-use.sh (юнит ↔ профиль), llama-swap
не владеет нативным движком и не претендует.

**Сеть.** Нативный Strata привязан к **172.17.0.1 (docker0)** на **:8082** —
:8081 занят llm-cadvisor (факт, в selection-карте предполагался свободным).
Контейнер достаёт его через `extra_hosts: host.docker.internal:host-gateway`
(развёртывается в 172.17.0.1). Пара «bind docker0 + proxy
host.docker.internal» проходит без allowed_hosts: при не-loopback привязке
Strata сама допускает имя host.docker.internal (serve/server.py
host_names_for). При bind docker0 сервер не виден с LAN (проверено: отказ на
192.168.17.99:8082 и 127.0.0.1:8082, слушает только 172.17.0.1) — без API-ключа
и без сетевой экспозиции (README рекомендует ключ только для 0.0.0.0; не пригодилось).
Если Docker-демон когда-нибудь сменит host-gateway — в паре менять и привязку
(примечание в config.d/30-strata.yaml).

**Открытие: fast-fail против 600-секундного зависания.** Пер-модельный
`healthCheckTimeout` на v265 не работает: config/load.go:136 перезаписывает
его глобальным (global 600 c — максимум родительских холодных загрузок).
Первая попытка конфигурации с `healthCheckTimeout: 20` зависала до глобальных
600 c при остановленном юните (замерено). Решение — watchdog-shim:
`cmd: sh -c 'while curl -sfm 2 http://host.docker.internal:8082/health …; do
sleep 1; done'` — shim живёт, только пока нативный /health отвечает; при
остановленном юните процесс выходит за ~2 c → prematureExit (llama-swap
abort) → ошибка запроса сразу. Замеры: 0.56 c (юнит выключен), 0.26 c (юнит
умер под живым shim). Поле `healthCheckTimeout` из модели убрано (no-op),
феномен задокументирован в комментариях файла.

**Что досталось соседним тикетам.**
- Тикет 02 (юнит/оркестратор): порядок ролей обязателен «unload родителя →
  старт юнита → дождаться /health → PUT profile» — при резидентном родителе
  старт Strata падает OOM VRAM (замерено на iq2: arena cudaMalloc при 869 MiB
  свободных). /health содержит дискриминатор размера (`model`) и готовность
  (`loaded`). SIGTERM server.py однажды проглотился (движок-ребёнок продолжал
  жить и держал VRAM/RAM до прямого kill) — ExecStop должен добивать дерево.
  RAM (47/36 ГиБ page-locked) освобождается убийством движка за секунды —
  fog-пункт карты «RAM-баланс llama.cpp idle ↔ Strata» может закрыться без
  эскалации, подтвердить на юните.
- Тикет 04 (верификация): ручной проход уже покрыл смены состояний iq3 и iq2
  и обратный возврат на ninfer (~8 c); полный цикл strata-use.sh и красные
  линии — там.
- Windows-порты (fog): снаружи потребителей новый маршрут не нужен, всё
  через :8080 (уточнение — тикет 03).

**Состояние после тикета:** конфиги в репозитории + AGENTS.md-маячок; активен
профиль ninfer; страта-юнит не запущен (автостарт не создавался — VRAM
захватывается только по strata-use.sh); RAM/VRAM фоновые.

## Comments

### 2026-10-19: порт 8081 вместо 8082 (решение пользователя)

Стек llm-monitoring остановлен (`docker stop` семи контейнеров: grafana,
promtail, loki, prometheus, nvidia-smi-exporter, node-exporter, cadvisor;
restart-policy `unless-stopped` удержит их выключенными и после reboot;
роутер llama-swap не тронут — `./llm-stack.sh down` не использовался, он бы
остановил и роутер). :8081 освободился, Strata пересажена на канонический
порт selection-карты:

- `/opt/strata/strata-{iq3_xxs,iq2_xs,iq3_s}.json`: port 8082 → 8081 (bind
  172.17.0.1 сохранён);
- `router/config.d/30-strata.yaml`: shim cmd/proxy → :8081, комментарий порта
  обновлён (если мониторинг возвращать — сначала увести его cadvisor с 8081);
- AGENTS.md-маячок → :8081; `docker compose restart llama-swap` — `/v1/models`
  три ID.

Живая перепроверка перевода: нативный iq3 на :8081 (~23 c до `/health` 200 —
страница экспертов тёплая), запрос через `:8080` профиль strata-iq3 → 200
(«Семь»), останов юнита → fast-fail watchdog (1.5 с full round-trip), возврат
ninfer (200). RAM/VRAM исходные. Сырё пополнено в `../assets/01-test-log.md`
(раздел «Пересадка на :8081»).
