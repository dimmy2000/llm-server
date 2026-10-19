# Feasibility: llama-swap и Strata

Status: resolved
Type: research

## Question

Подключение делается ПОСЛЕ карты (out of scope), но отчет должен содержать feasibility:
сможет ли текущая инфраструктура вообще обслуживать выбранную Strata-модель «постоянно,
рядом с Qwen 3.8 27b»?

- llama-swap (v265, пин в `router/Dockerfile`; локальная копия репо — `../llama-swap`)
  запускает backend'ы как дочерние процессы **внутри контейнера**. Strata ставится
  нативно на хост. Совместимо ли это? Есть ли у llama-swap механизм хост-процессов,
  unix-socket, проксирование на внешний эндпоинт?
- Если живой вариант — Strata как **внешний** backend (`:8081`): умеет ли llama-swap
  проксировать/ссылаться на уже существующий эндпоинт, держать его health, включать
  в `/v1/models`? Что с exclusive-группой (движки не работают параллельно) — можно ли
  стрелять в чужой процесс?
- Понадобятся ли для Strata из-под llama-swap Docker-образ (свой `Dockerfile` есть
  в репо Strata) — совместима ли инсталляция в контейнер с нашими пинами driver/CUDA?
- Альтернативная тропа без llama-swap: второй провайдер в opencode v2
  (`providers.strata`, `http://localhost:8081/v1`) — что теряем (переключение руками
  через конфиг, нет единого ID) и что получаем.

Источники: локальный репо `../llama-swap` (docs, issues, код `internal/`), текущий
`router/config.yaml` + `config.d/`, опенковский конфиг `~/.config/opencode/opencode.jsonc`,
README Strata (API-глава).

Доставить: сравнение тройки троп (контейнерный cmd / внешний эндпоинт через llama-swap /
отдельный провайдер opencode) с ограничениями каждого; вывод «feasible / не feasible».

## Answer

Проверка кода/доков выполнена по локальной копии `../llama-swap`: HEAD = `a2796fb`,
входит в тег `v265` (release-коммит `d1e743f` «CHANGELOG: v265»; `git tag --contains HEAD`
подтверждает) — цитаты соответствуют запиненному v265. Источники Strata: README,
`docs/INSTALL.md`, `docs/DETAILS.md`, `Dockerfile` репо `Niko1221/Strata` (на 2026-10-18).
Хост — нативный Ubuntu (не WSL; `uname` без Microsoft-сигнатуры), поэтому WSL-caveat'и
Strata (`docs/DETAILS.md`: лимит ~1 GiB на pin через `cudaHostAlloc`, «never under WSL»
для kv-streaming) на этой машине не действуют.

### 1. Механизмы llama-swap v265 — что есть и чего нет

**Единственный способ запустить backend — дочерний процесс через `cmd`.** Старт любой
модели идёт через `SanitizedCommand` → `exec.CommandContext` внутри процесса llama-swap
(`../llama-swap/internal/process/process_command.go:459-534`). Факт: llama-swap не
умеет хост-процессов, docker-драйвером не обладают ни v265, ни наш образ (`docker.sock`
не смонтирован, `router/docker-compose.yaml`). В нашей топологии llama-swap живёт в
контейнере, значит `cmd` всегда исполняется **внутри** контейнера.

**Backend без `cmd` не существует.** Пустой `cmd` → ошибка `empty command`
(`../llama-swap/internal/config/commands.go:23-27`), старт невозможен
(`process_command.go:464-467`); док фиксирует: «cmd is the only required setting»
(`../llama-swap/docs/kb/guides/model-runtime/writing-cmd.md:12`). Обратная сторона:
`cmd` может быть «пустышкой» (shim, напр. `sleep infinity`), а `proxy:` — вести на любой
существующий http(s)-URL (`ModelConfig.Proxy`, `../llama-swap/internal/config/model_config.go:136`;
реверс-прокси `process_command.go:474`). Так включается проксирование на уже работающий
внешний эндпоинт — см. B2.

**Unix-socket не поддерживается.** Транспорт прокси — только TCP (`net.Dialer`,
`process_command.go:477-480`); в `internal/` нет ни одного проксируемого пути через
unix-сокет (единственное `net.Dial("unix")` — во внутреннем perf-monitor). У Strata
unix-сокета тоже нет (HTTP-only), так что канал в обе стороны мёртв.

**Health-check внешнего URL — есть и работает без нашего процесса.** `checkEndpoint`
(дефолт `/health`) опрашивается через тот же реверс-прокси, т.е. `GET proxy+checkEndpoint`
до HTTP 200 в пределах `healthCheckTimeout` (`process_command.go:575-624`); поддержан
JSON `{progress, message}`. Это готовый health-check чужого уже запущенного сервера —
Strata отвечает `/health` до API-key гейта (HEALTHCHECK в его Dockerfile). Важное
следствие: exit shim-команды во время поллинга → `prematureExit`
(`process_command.go:596-600`) — shim обязан быть long-running.

**Peers — канонический механизм «внешнего эндпоинта» (есть в v265).**
`peers.<id>.proxy/apiKey/models/timeouts/filters`; peer может быть «another llama-swap
or **any** server providing the `/v1/` endpoints» — официальный пример с openrouter
(`../llama-swap/docs/kb/examples/peers-and-multi-host.md:16-38`; guide
`docs/kb/guides/connectivity/remote-peers.md`). Ограничения (сборно из examples:125-132
и кода):
- адресация **всегда** FQN `strata/<model>`, и FQN обязательно виден в `/v1/models`
  (examples:127-128);
- пин/сокрытие peer-FQN запрещены валидацией (`../llama-swap/internal/config/peer.go:148-152`
  → «profile … pin … conflicts with fully qualified peer model name»);
- «llama-swap does not manage the peer's lifecycle. It cannot start, stop or TTL-unload
  anything on the other side» (examples:131-132);
- preload peer пропускается (`api.go startPreload` → «not a local model, skipping»);
- peer не входит в groups/маршрутизацию локальных моделей: dispatch `server.go:287-293`
  (local → group-роутер, peer → отдельная цепочка).

**Пин публичного ID НА peer-цель — валиден.** Target пина проверяется через
`ResolveBaseModel` (`../llama-swap/internal/config/config.go:302-318`), который включает
peer-модели; использующий проверку `validateProfiles` — `load.go:325-337`. Значит профиль
`strata: pins: qwen3.8-27b: strata/<model>` проходит; но сам FQN `strata/<model>` останется
навсегда видимым в `/v1/models` (см. выше) — B1 нарушает контракт «ровно один ID».

**Hooks — только два действия, произвольных команд нет.** `hooks.on_startup` = `preload[]`
+ активный `profile` (`config.go:137-144`; чистка preload — `load.go:276-288`; старт —
`server.go:247`); preload фактически фоновый `GET /` по локальным моделям (`api.go
startPreload`). «Запустить Strata перед стартом llama-swap» из конфига не выйдет — это
вопрос systemd/сервисного скрипта хоста.

### 2. Deployment-варианты

#### A — Strata как третий backend внутри `router/Dockerfile` (cmd-ребёнок)

Схема: сборка/копия движка Strata (`engine/strata`, опц. `strata-vision`, CUDA-libs;
для RTX 5070 Ti — `CUDA_ARCHITECTURES=120`) в образ по рецепту llama.cpp (пин + SHA-256
build-args); модель-пак (70–80 GB: `models/`, `packs/` с `experts.bin`, `mtp/`) готовится
**один раз нативно на хосте** `./setup.sh` (он же пишет `strata-<model>.json`:
`exe/args/port/vision/...`) и монтируется в контейнер volume'ом; `cmd` в
`router/config.d/30-strata.yaml` = бинарник движка с args из конфига, но `--port ${PORT}`;
`unlisted: true`, профиль `strata` пинит `qwen3.8-27b → backend-strata`. GPU контейнерная
передача уже есть (`router/docker-compose.yaml:25-34`).

Feasibility: **возможно технически, но дорого.** Ограничения:

- третий пин в образе поверх быстро обновляющегося upstream (Strata v0.1.x — почти
  еженедельные релизы); сборка «build it on the PC it runs on» (Strata Dockerfile — CPU-ядра
  машины, на которой образ собирается), ~20–40 минут на build;
- образная база: официальный путь Strata — `nvidia/cuda:13.0.0-devel-ubuntu24.04`; наша —
  ubuntu:26.04 + CUDA-13.3 libs от llama.cpp; движку также нужен `libatomic1`; libcudart
  13.3 ≥ 13.0 скорее совместим, но проверка обязательна;
- RAM: 34–43 GB page-locked — контейнеру нужен `ulimits: memlock: -1` (официальный рецепт
  Strata: `docker run --gpus all --ulimit memlock=-1`, INSTALL «Docker (Linux)»); setup.py
  читает host `/proc/meminfo`, cgroup-лимит контейнера он не видит — значит памяти
  контейнер не ограничиваем;
- stop: SIGTERM отпускает page-locked RAM «tens of GB» (INSTALL Docker: «takes longer than
  Docker's default 10 s») → per-model `unloadTimeout: 120`; каждый swap НА Strata
  вызывает повторную загрузку 34–43 GB в RAM (30–90 с после первого раза);
- обслуживание: python-подготовка пака остаётся на хосте — путь обновления пака при
  смене размера не автоматизирован llama-swap'ом.

**Главный плюс A — честная эксклюзивность**: Strata — ребёнок llama-swap, свап реально
останавливает его (`CmdStop`/SIGTERM), VRAM освобождается до старта llama/ninfer; красная
линия «движки никогда не работают параллельно» (ADR-0006) поддерживается автоматически
через `PUT /api/profiles/active`.

#### B — Strata вне роутера (нативно на хосте или своим контейнером), llama-swap проксирует

Рекомендуемый вариант компоновки; два подварианта:

- **B1 — peers.** `peers.strata.proxy: http://<host>:8081` + `models: [выбранный размер]`.
  ~10 строк YAML, без пересборки, `timeouts` на медленных ссылках. Ограничение каменное:
  FQN `strata/<model>` навсегда в `/v1/models` — нарушение «exactly one model-ID»
  (ADR-0006); preload/TTL/exclusive не имеют силы на peer.
- **B2 — shim-модель (рекомендация).** Модель `backend-strata` с `cmd: sleep infinity` +
  `proxy: http://<host>:8081` + `checkEndpoint: /health`. При переключении на профиль
  `strata` llama-swap стартует shim и health-check'ит живой `/health` чужого сервера —
  обычная модельная композиция llama-swap, только процесс-носитель внешний. Работает всё
  нативное:
  `unlisted`, `useModelName` (скорее не нужен: «Any API key and any model name work» —
  README), preload (Strata на `GET /` отвечает 200 — нет NInfer-косметики 404), health
  timeout, пины, «unloaded»-запись в `/v1/models`. Контракт «exactly one qwen3.8-27b»
  держится. Честная оговорка: «swap/unload» — косметика (exit sleep не освобождает
  VRAM/RAM Strata), параллельность живёт только по дисциплине оператора.
- Сеть: Strata дефолтно слушает `127.0.0.1:8080` — конфликт с router'ом `:8080` решаем
  `--port 8081` (README «Options»: `START-HERE.bat --port 8081`, в Docker `-e PORT`/`HOST`),
  а для досягаемости из контейнера — нативный Strata слушает `--host 0.0.0.0` (+`--api-key`
  перед выставлением; README) и адрес `proxy:` = host IP или
  `extra_hosts: host.docker.internal:host-gateway` в compose.

#### C — второй провайдер opencode v2 (`providers.strata`, `http://localhost:8081/v1`)

Форма уже работает в `~/.config/opencode/opencode.jsonc` (v2 `providers`; аналогия —
`self-hosted` от bifrost-шлюза; в legacy/первом блоке `provider` варианты в тело запроса
не уходят). Feasibility: тривиальна — блок как у `self-hosted`, ID вида `strata/<model>`.

Что теряем: эндпоинт **не** часть llama-swap — без `llm-monitoring`-метрик/Loki-логов,
без единого ID/переключения профиля, другие потребители (`bench.py`, launcher) его не
видят; «движки не работают параллельно» остаётся ручной дисциплиной. Что получаем: ноль
изменений в `router/` (Dockerfile не трогается), дешёвый старт/откат; reasoning-контракт
Strata — выбор off/low/medium/high через поле "reasoning effort" приложения (README);
mapping нашего `xhigh` на их `"high"` сверить в тикете 03.

### 3. Общие ограничения (все варианты)

- **RAM** (59 GiB, доступно ~47–48): кроме IQ3_XXS/IQ3_S (43/50 GB экспертов) в
  Strata-резидентном режиме почти вся RAM занята; рядом llama.cpp-профиль умеет
  `--cache-ram 40960` (KV spill до 40 GB на idle) — постоянное одновременное
  RAM-проживание обоих нереально; матрица тикета 07 фиксирует фактический минимум
  свободной RAM. Fallback — `--mmap-experts`/low-ram-режим Strata или размер IQ2_XS.
- **VRAM**: Strata заполняет свободную VRAM expert-cache на старте; красная линия
  GPU1 ≥ 512 MiB выражается флагом `--vram-reserve-mib` (дефолт 700; README/DETAILS).
  Пока Strata активна — llama/ninfer места нет; пока 27B-движок активен — Strata получит
  мало соседства и «no VRAM left for the expert cache»-варнинг (INSTALL).
- **Порт**: `:8080` занят router'ом → только `:8081` (Strata `--port`).
- **Reasoning/tools/Anthropic-API** (`/v1/messages`, `/v1/responses`, MCP) — проверить
  в тикете 03, троганье llama-swap'ом их не ломает (стрипаем только `repetition_penalty`).

### Вердикт и рекомендуемая траектория

**Feasible.** Все три тропы жизнеспособны; различие — «кто владеет lifecycle» и сколько
инфраструктурного кода писать. Рекомендация для следующего усилия (интеграции):

1. **Основной путь — B2 (shim-модель + пин в `config.d/30-strata.yaml`)**: без
   пересборки образа, сохраняет контракт ADR-0006 (один публичный ID, переключение
   через `PUT /api/profiles/active`), llama-swap получает health/метрики/логи поверх
   внешнего Strata. Доп. задача интеграции: systemd/скрипт-юнит для Strata на
   `:8081` + строка в runbook «перед свапом на llama/ninfer — стоп Strata (VRAM)» и
   ADR-0007.
2. **План B — A (контейнерный cmd)**: только если понадобится автоматический честный
   swap без ручных стопов. Состав работ: новый образ-пин Strata + `ulimits: memlock: -1`,
   `unloadTimeout: 120`, `--vram-reserve-mib 512`, ADR.
3. **Дешёвый старт — C (opencode-провайдер)**: включить сразу на период верификации
   (замеры тикетов 06/07 идут через нативный Strata на `:8081`), перевести в B2 при
   интеграции.
4. **B1 (peers)** — только если решим ослабить контракт «exactly one ID» (публичный
   `strata/<model>` в списке): механизм upstream-поддержан и самый простой после C.
5. **Не-go**: попытка «запускать» Strata через hooks (`on_startup` не умеет команды) и
   unix-socket (нет ни у llama-swap, ни у Strata).
