# llama-swap как оркестратор backend'ов — единый endpoint

Type: wayfinder:map

## Destination

Один долгоживущий llama-swap — единая точка входа (`:8080`) для llama.cpp и
NInfer. Публичный контракт — ровно один model-ID `qwen3.8-27b`; режим
(reasoning) задаёт клиент, sampling — серверный дефолт движка, который клиент
может переопределить; собственного мнения о reasoning у сервера нет (голый ID
отдаёт дефолт шаблона). Движки объявлены моделями внутри llama-swap, единый ID
переключается вручную (активный профиль llama-swap с пинами), движки никогда не
работают параллельно, и процедура переключения задокументирована. Результат
проверен opencode-субагентами (задача с reasoning и без, с вызовом инструментов
и без) на llama.cpp и NInfer; отчёты и доказательства лежат в `docs/`.

## Notes

- Тип усилия: **изменение на месте**. Notes переопределяют дефолт wayfinder —
  исполнение (правка конфигов/compose/потребителей, тесты, документация)
  входит в карту, а не остаётся «только решения».
- **Домен** (`CONTEXT.md`): Профиль, Движок, Маршрутизатор, Публичный
  model-ID, Режим, Тип режима, Уровень reasoning, Preserve thinking. Часть
  этих терминов станет мёртвой после схлопывания алиасов — обновление
  глоссария в тикете «Документация».
- **Личные предпочтения усилия**: клиент управляет всем; сервер не задаёт ни
  reasoning, ни sampling. Backend'ы никогда не работают параллельно; красная
  линия — ≥ 512 MiB свободной VRAM на дисплейной GPU1 под пиковой нагрузкой.
- **Источники фактов**: локальный репозиторий `../llama-swap` (читать docs/kb,
  schema; при отставании — `git pull`), `../llama.cpp`, `ninfer/`,
  `docs/research/0009-ninfer-tp2-two-5070ti.md`, `docs/adr/0003`.
- **Исследования** — субагент `/research`, отчёт в `docs/research/NNNN-*.md`
  (продолжить нумерацию с 0011) со ссылкой из тикета. Доказательства тестов —
  `.scratch/llama-swap-orchestrator/assets/`.
- **Потребители** (уже найдено): `~/.config/opencode/opencode.jsonc` (7 llama
  ID, дефолт `llama/qwen3.8-27b-agent-medium`, baseURL
  `http://192.168.17.69:9000/v1`); `llm-monitoring` не знает model-ID. Полная
  инвентаризация остальных потребителей — в тикете реализации.

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [llama-swap как фронт нескольких backend'ов](issues/01-llama-swap-fronting.md) — образ локально был `cuda13` = **v240 без `profiles.pins`/`selectors`**, локальный репо v264+ (тег с тех пор уехал, см. «Выбор версии образа llama-swap»); `cmd`+`proxy` живут в одной записи; единый ID переключается пинами только на новом образе; непараллельность = ровно одна локальная модель.
- [opencode: управление reasoning и tools через openai-compatible](issues/02-opencode-reasoning-control.md) — opencode 1.18.35 шлёт `reasoningEffort`→`reasoning_effort`, `chat_template_kwargs` проходит как есть, tools = `permission`; доказательства через `run --format json --thinking`. Текущий конфиг содержит баги (`:9000` и префикс `llama/`).
- [Контракты backend'ов при пустом stripParams](issues/03-backend-request-contracts.md) — «нет дефолтов» недостижимо; снятие фильтров переводит голый ID в thinking+xhigh; есть таблица совместимости и список параметров, требующих shim (`top_k:0`, `repetition_penalty≠1`, `reasoning_effort: high|…`).
- [Выбор версии образа llama-swap](issues/09-llama-swap-version.md) — пины нужны (один контейнер, единый ID); плавающий `cuda13` уже уехал на v265, а локальный v240 невоспроизводим (404); свой образ = llama-swap **v265** + llama.cpp **b10438** (бамп с b10068 — тикет 11), база и бинарник пинятся дайджестом/SHA-256.
- [Остаточное серверное мнение и нормализация](issues/10-server-opinion-and-normalization.md) — явного «instruct» нет: голый ID = дефолт шаблона (thinking + `xhigh`), instruct — явный `reasoning_effort: "none"`; llama-swap правит запрос только `stripParams: repetition_penalty` + `useModelName`; sampling — пресет в `cmd` движка (llama.cpp CLI-флаги, NInfer mode-aware), перекрываемый клиентом; безопасное подмножество — в ADR-0006 + README (тикет 08).
- [Топология: llama.cpp и NInfer за одним llama-swap](issues/04-orchestrator-topology.md) — один образ `router/Dockerfile` (`ubuntu:26.04` + `COPY --from` llama.cpp `/app` и CUDA + ninfer-тарбол + llama-swap v265), оба движка дочерними процессами, `docker.sock` не нужен; конфиг — `router/config.yaml` + `config.d/10-llama.yaml`/`20-ninfer.yaml`; прелоад и стартовый профиль — NInfer; непараллельность и «только ручное» = дефолтная exclusive-группа + `unlisted` + пин `~` на неактивный backend; переключение — `PUT /api/profiles/active` без скрипта; один compose-сервис `llama-swap` без профиля, контейнер `llama-swap`.
- [Конфиг единого endpoint'а](issues/05-single-endpoint-config.md) — раскладка `router/config.yaml` (глобалы, hooks, profiles с пинами) + `config.d/{10-llama,20-ninfer}.yaml` (identity-map'ы, один движок на файл); `filters` — ровно `stripParams: repetition_penalty` на обоих, `useModelName` только у ninfer; пресет sampling — CLI-флаги llama.cpp `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0 --repeat-penalty 1.0`, mode-aware пресет NInfer не трогаем; `healthCheckTimeout 600`, голый ID = thinking+`xhigh`; backend'ы `unlisted` с явными `capabilities` и пер-модельным `env` (`LD_LIBRARY_PATH`); opencode управляет reasoning/tools на едином ID.
- [Реализация: конфиги, compose и потребители](issues/06-implement.md) — топология внесена на месте: новый `router/` (`Dockerfile` на запиненных llama-swap v265 / llama.cpp b10068 / NInfer v0.4.6, один compose-сервис `llama-swap` **без** `profiles`, `config.yaml` + `config.d/`, `fetch-model.sh`); `llama/` и `ninfer/` удалены, корневой `include` → `router/`+`vllm/`; потребители — `opencode.jsonc` (один ID, `localhost:8080`, reasoning клиентом), launcher+README `llm-monitoring`, `bench.py`; проверено `-validate`, сборкой образа (`ninfer-serve` берёт свой `libcudart`) и offline-смоуком (единый ID, пины `~`/404, `useModelName`, stripParams, непараллельность). Живой GPU-прогон — тикет 07, доки — тикет 08.
- [Проверка через opencode-субагентов + доказательства](issues/07-verify-opencode.md) — на живом железе (router:v265, llama.cpp b10068, NInfer v0.4.6; клиент opencode v2.0.32, tap-прокси) матрица reasoning×tools закрыта на **обоих** движках через единый `qwen3.8-27b`: без reasoning `reasoning_content` пуст, с effort `low|medium|xhigh` — непуст и растёт с effort; `tools` включает реальный вызов `read` → `57403`, без `tools` тот же текст не исполняется. Общий переносимый рецепт — только `chat_template_kwargs` (`enable_thinking:false` / `reasoning_effort`): top-level `reasoning_effort` llama.cpp b10068 **игнорирует** (в сборке нет обработки), NInfer слушает; голый ID = thinking+`xhigh` на обоих; непараллельность и красная линия VRAM подтверждены. Отчёт — `docs/research/0014-…`, доказательства — `assets/07-verify/`. Находки → тикеты 11–14.
- [Бамп llama.cpp по `reasoning_effort`](issues/11-llama-reasoning-effort-skew.md) — пин в `router/Dockerfile` поднят `b10068 → server-cuda13-b10438@sha256:bb81f3e4…6283` (первый опубликованный cuda13-образ с обоими коммитами обработки `reasoning_effort`: `27209a598`→b10121, `7e4c0a968`→b10434 [образ не публиковался]; база та же CUDA 13.3, с b11706 — уже 13.4). Shim невозможен (`filters` llama-swap только плоские), no-op-документирование отвергнуто. Живьём: top-level `low|medium|xhigh` теперь работают на **обоих** движках; **остаточный разрыв — top-level `none` инертен на llama.cpp** (ветка исполняется, но thinking не выключает; NInfer выключает), переносимый контракт: instruct = `chat_template_kwargs.enable_thinking:false`, effort = `reasoning_effort: low|medium|xhigh` (top-level или kwargs); невалид → 500 (llama) / 400 (NInfer). Красная линия VRAM держится (llama GPU1 1171, ninfer GPU1 710 MiB). Отчёт — `docs/research/0015-…`, доказательства — `assets/11-llama-bump/`. Производительность b10438 и пересъёмка матрицы субагентов — тикет 15; доки (ADR-0006, README, AGENTS, б10068-упоминания) — тикет 08.
- [NInfer: preload 404 и статус `unloaded`](issues/12-ninfer-preload-status.md) — оба артефакта **косметика, чинить в карте нечего**. Warmup-эндпоинта у `ninfer-serve` нет (`/` → 404 живьём), а `hooks.on_startup.preload` — единственный механизм старта движка (внутренний `GET /` через прокси запускает дочерний процесс; «Health check passed» подтверждает прогрев, ERROR — лишь ответ upstream). `unloaded` в `/v1/models` — отдельный hardcode для пин-записей профилей (`api.go:294-302` v265; селекторы состояние цели резолвят, пины — нет), не следствие прелоада; `ModelPreloadedEvent` без подписчиков, потребители (`llm-monitoring`, opencode, bench) поле `status` не читают; правдивое состояние — `/api/profiles`, SSE `/api/events`, `/health` upstream. Задокументировано комментарием в `router/config.yaml`; README/ADR — тикет 08. Доказательства — `assets/12-ninfer-preload-status/`. Опционально вне карты: upstream-issue в llama-swap о резолве состояния пин-цели.
- [`sendLoadingState` отдаёт баннер загрузки как `reasoning_content`](issues/13-loading-state-reasoning.md) — выставлен `sendLoadingState: false` в `router/config.yaml` и проверен живьём: на запросе, платящем загрузку, в `reasoning_content` больше нуля чанков (реальный reasoning с thinking on не пострадал). Баннер стримится только в `delta.reasoning_content` — канал зашит в код (`internal/router/loading.go`), тумблер только вкл/выкл, фильтр невозможен (эмит до upstream-обработчика, `filters` плоские). Потребителей loading-state нет (llm-monitoring читает stdout-логи, opencode бы показал баннер как фейковое рассуждение, bench.py не парсит). Плата: первый запрос после переключения молчит 40–60 c без in-stream индикатора. Формулировка для ADR-0006/README (тикет 08) — в Answer тикета; доказательства — `assets/13-loading-state/`. Опционально вне карты: upstream-issue на настраиваемый канал.
- [opencode v2: consumer-конфиг и оверлеи на уровне агента](issues/14-opencode-v2-consumer-config.md) — `~/.config/opencode/opencode.jsonc` переписан под v2.0.32: новый провайдер `llama-swap` (`http://localhost:8080/v1`, один ID `qwen3.8-27b`, провайдер `self-hosted` на `192.168.17.69:9000` был мёртв по маршрутизации), reasoning — 4 вариантами `{id, body.chat_template_kwargs}`: `off` (`enable_thinking:false`, переносимо на оба движка), `low|medium|xhigh` (`reasoning_effort`); top-level `none` сознательно не используется (инертен на llama.cpp). Мёртвые `agent.plan.reasoningEffort` и provider-оверлеи убраны; корневой `model` без `#variant` — v2 вариант там игнорирует (проверено живьём). Проверено через tap-прокси на ninfer: `#off` → reasoning пуст, `#medium/#xhigh` → reasoning растёт с effort. Бэкап — `opencode.jsonc.bak-ticket14`, доказательства — `assets/14-opencode-v2/`. Новый конфиг подхватывается следующим стартом opencode.
- [Пересъёмка на llama.cpp b10438: opencode-субагенты и производительность](issues/15-verify-b10438.md) — доказательная база восстановлена на b10438. **Матрица** reasoning × tools (метод 0014, tap-прокси) закрыта полностью, картина идентична b10068 и NInfer: reasoning ровно когда запрошен (`off` → 0, растёт с effort, голый ID → thinking+xhigh), инструмент исполняется только при `tools` в теле; VRAM GPU1 min 1345 MiB — красная линия держится, движок ровно один. **A/B** на одном бенчмарке (протокол 0005, кейсы 26k–160k): prefill +5–7 %, decode в пределах разброса, приём драфта сопоставим, wall-clock равен или лучше — **регресса нет, пин остаётся** (оговорка: один прогон на кейс). **Механизм top-level `none` установлен**: CLI-флаг `--reasoning on` в `cmd` профиля инжектит `default_template_kwargs["enable_thinking"]="true"` (`arg.cpp:3635`), ветка `none` стирает только `reasoning_effort` (`server-common.cpp:1298`), а `extra_context` накладывается после флага и побеждает; доказано дифрепро на Qwen3-0.6B без GPU. Черновик upstream-репорта — `assets/15-verify-b10438/none-mechanism/upstream-issue-draft.md` (подача — за человеком). Отчёт — `docs/research/0015`, раздел «Доказательная база на b10438».
- [Документация: инструкция переключения, ADR, AGENTS/README/CONTEXT](issues/08-docs.md) — документация приведена к текущей топологии. Новый `docs/adr/0006-single-endpoint-llama-swap-orchestrator.md`: оркестратор с пинами (v265 / b10438 / v0.4.6), единый endpoint, клиентский reasoning-контракт (таблица + механизм инертности top-level `none`), sampling как дефолт `cmd` движка, таблица безопасного подмножества (сводка 0013 без vLLM), `sendLoadingState: false`, шесть отвергнутых альтернатив. `README.md` переписан: топология `router/`, пошаговое переключение (`PUT /api/profiles/active`, проверки, молчаливый первый запрос 40–60 c, OOM/порт), единый контракт, команды без compose-профилей. `AGENTS.md`: вместо «Профиль llama/ninfer» с 7 ID — «Общая архитектура», «Единый контракт», «Переключение движков», разделы двух движков; «Профиль vLLM» и «Хост/P2P» сохранены дословно. `CONTEXT.md`: мёртвые термины («Режим», «Тип режима», «Уровень reasoning», «Preserve thinking») убраны, введены Маршрутизатор, Пин, Публичный model-ID, Reasoning-контракт, Безопасное подмножество. Бамп b10068→b10438 выполнен во всех живых упоминаниях (map, ADR, README, AGENTS, комментарий `config.d/10-llama.yaml`, плашка 0014); исторические протоколы прогонов на b10068 (0005, 0014-прото, 0015-A/B) сознательно не тронуты.

## Not yet specified

<!-- Проверка тикета 07 не оставила тумана: найденные вопросы заведены
     конкретными тикетами (11 — version skew llama.cpp по reasoning_effort,
     12 — preload 404 / статус unloaded у NInfer [решён 2026-10-17: косметика,
     оба артефакта — в бинарниках llama-swap v265 / ninfer-serve, правки
     только форком/апстримом; комментарий в router/config.yaml], 13 — баннер
     sendLoadingState в reasoning_content, 14 — consumer-конфиг opencode v2).
     Тикет 11 решён бампом пина и завёл тикет 15 — пересъёмка на b10438
     (матрица opencode-субагентов и A/B производительности) и разбор
     остаточного разрыва top-level `reasoning_effort: none`. -->

## Out of scope

- **vLLM как backend** (compose-профиль `vllm`, `vllm/config.yaml`, `vllm/`,
  vLLM за llama-swap, model-ID для vLLM) — не используется; выведен из карты
  2026-10-17. Файлы `vllm/` этим усилием не меняются и не удаляются; если
  vLLM понадобится, это отдельный effort, а не возврат в эту карту.
- Сборка/обновление движков из исходников (tp2, DFlash2, форки) — отдельный
  effort; здесь используются текущие бинарники/образы.
- Смена артефактов моделей и квантизации (качество), включая оценку качества
  `nvfp4` KV.
- Автоматическое переключение backend'ов (TTL, группы, автоскачивание и
  автоматический swap по запросу) — по условию задачи переключение только
  ручное.
- Удалённые/multi-host peers llama-swap и сетевой доступ за пределы хоста.
- Патченный драйвер, P2P, GRUB/IOMMU и тепло хоста — `docs/NVIDIA_P2P.md`,
  ADR-0005.
