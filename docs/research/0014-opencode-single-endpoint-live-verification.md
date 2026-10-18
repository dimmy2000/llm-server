# 0014 — Единый endpoint на живом железе: opencode-субагенты, reasoning × tools

Дата: 2026-10-17. Исследование по тикету
`.scratch/llama-swap-orchestrator/issues/07-verify-opencode.md` (карта
`.scratch/llama-swap-orchestrator/map.md`).

> Обновление (после тикета 11): пин llama.cpp в `router/Dockerfile` поднят
> `b10068 → b10438`, матрица пере-снята на b10438 — `docs/research/0015`
> (раздел «Доказательная база на b10438»). Все упоминания `b10068` ниже —
> сборка **до** бампа: исторические пробы этого отчёта. Актуальное состояние
> top-level `reasoning_effort` на llama.cpp — `low|medium|xhigh` работают,
> `none` остаётся инертным (0015).

Вопрос тикета: подтвердить на живом железе, что **один** публичный model-ID
`qwen3.8-27b` за одним llama-swap действительно работает и на llama.cpp, и на
NInfer; что **клиент** управляет reasoning (thinking off / разные effort) и
может вызывать инструменты; и что **одна и та же клиентская конфигурация** даёт
разное поведение при разных клиентских настройках. Доказательства — сырые
логи/JSON в `.scratch/llama-swap-orchestrator/assets/07-verify/`.

## На чём проверяли (версии и хеши)

| Артефакт | Значение |
|---|---|
| Образ-оркестратор | `llm-server/router:v265`, `sha256:190c9b485faa45d634c6e815f3f6bbca98d8737a648b376bc9e9ccb507be8c7a` |
| llama-swap | релиз `v265` (запинен в `router/Dockerfile`, SHA-256 архива проверяется на сборке) |
| llama.cpp | **`b10068`** (образ `ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068`, `system_fingerprint: b10068-571d0d540`) |
| NInfer TP=2 | **`v0.4.6`** (форк `ValerioDolci/ninfer-tp2`), артефакт `qwen3_8_27b_nvfp4.ninfer` |
| `router/config.yaml` | `sha256:df9a940f5c28…` (активный профиль, пины, `sendLoadingState: true`) |
| `router/config.d/10-llama.yaml` | `sha256:9815d44f0b00…` |
| `router/config.d/20-ninfer.yaml` | `sha256:06a33567865f…` |
| `router/Dockerfile` | `sha256:0c5bd9ed6fd6…` |
| Клиент | **opencode `v2.0.32`** (исследование 0012 писалось против 1.18.35) |

Активный профиль выбирался вручную `PUT http://localhost:8080/api/profiles/active
{"name":"llama"|"ninfer"}`. Все прогоны шли через один `:8080`.

## Метод

Весь HTTP-трафик клиента пропускался через пишущий reverse-proxy **tap**
(`assets/07-verify/tap-proxy.py`, `127.0.0.1:8090` → `127.0.0.1:8080`): на каждый
запрос сохраняются тело (`…req.txt`), сырой SSE-ответ (`…resp.txt`) и тайминги
(`…meta.txt`), из которых `analyze.py` делает сводку. Так доказательство берётся
из тела запроса и ответа, а не из событий opencode.

Изоляция клиента от пользовательского `~/.config/opencode/opencode.jsonc`
(иначе его `model.options` подмешиваются в тело): `HOME=/tmp/opencode/oc-home`,
`XDG_DATA_HOME`, `XDG_CACHE_HOME`, `OPENCODE_CONFIG=<тестовый конфиг>`.
`XDG_CONFIG_HOME` для глобального конфига **не** учитывается, а `OPENCODE_CONFIG`
всё равно **сливается** с `~/.config/opencode/opencode.jsonc`. Рабочий каталог
вне репозитория (`/tmp/opencode/oc-work` + `notes.txt` = `419`), иначе opencode
подхватывает проектный `AGENTS.md`.

Задача во всех прогонах одна:

> `Read the file ./notes.txt using the read tool. Reply with only the number stored in it, multiplied by 137.`

Верный ответ — `57403` (требует реального вызова инструмента; если инструмента
нет, модель печатает псевдо-вызов текстом).

## Что важно знать про opencode v2.0.32 (иначе доказательства читаются неверно)

1. **Оверлеи на уровне агента не уходят в запрос.** `agent.*.options`,
   top-level `reasoningEffort` и `agent.*.request.body` сохраняются, но в тело не
   попадают (документированное поведение V2). Reasoning задаётся на уровне
   провайдера/модели/варианта.
2. **Вариант — это объект `{id, settings, headers, body}`**, а не только
   `settings`. `settings` сливаются в опции провайдера, а `body` **deep-merge’ится
   в тело запроса** (через провайдерный `body`). Именно `body` позволяет передать
   произвольное поле, которого нет в словаре AI-SDK, например
   `chat_template_kwargs`.
3. **Вариант выбирается только на прогон:** `--model self-hosted/qwen3.8-27b#<variant>`.
   Корневой `model` в конфиге вариант `#…` игнорирует.
4. **Каждая сессия делает дополнительный запрос «title generator»** (тот же
   вариант модели, но **без** поля `tools`), параллельно с первым шагом агента.
   В tap-логах на кейс поэтому 2–3 записи: title + шаг(и) агента. Это не второй
   ответ модели на задачу — разбор `tap-summary.json` нужно вести по запросам,
   где системный промпт начинается с «You are an AI agent running in OpenCode».
5. **`tools` управляются правами агента.** Агент с
   `permissions: [{action:"*",resource:"*",effect:"deny"}]` даёт тело **без**
   поля `tools`; обычный агент — **12** инструментов в `tools`.

## Два прохода и главный вывод

Оказалось, что клиентский способ задать reasoning важен: два разных способа
выглядят одинаково в конфиге opencode, но по-разному доезжают до движков.

### Проход 1 (диагностический): top-level `reasoning_effort`

Варианты были `settings: {reasoningEffort: …}` → в тело уходило **top-level**
поле `reasoning_effort`. Результат (assets `pass1-toplevel-effort/`):

- NInfer: `none` → reasoning пуст, `low/medium/xhigh` → reasoning есть;
  неверный effort → `400`.
- llama.cpp b10068: **top-level `reasoning_effort` полностью игнорируется** —
  thinking включён при любом значении (`none/banana/xhigh/…`), ответы текстовые
  как при thinking.

То есть «общая» настройка `reasoningEffort` **не переносима**: на llama.cpp она
не работает вовсе.

### Проход 2 (итоговый): `chat_template_kwargs`

Варианты переписаны на `body`:

```json
"variants": [
  { "id": "off",    "body": { "chat_template_kwargs": { "enable_thinking": false } } },
  { "id": "low",    "body": { "chat_template_kwargs": { "reasoning_effort": "low" } } },
  { "id": "medium", "body": { "chat_template_kwargs": { "reasoning_effort": "medium" } } },
  { "id": "xhigh",  "body": { "chat_template_kwargs": { "reasoning_effort": "xhigh" } } }
]
```

Это **одна и та же конфигурация** (`assets/07-verify/opencode-test.json`), и она
работает на обоих движках. Правило: `enable_thinking: false` → instruct,
`reasoning_effort: low|medium|xhigh` → thinking нужного уровня; голый ID — дефолт
шаблона (thinking + `xhigh`) на обоих движках.

## Результаты прохода 2 (главная таблица)

Матрица тикета: `(reasoning?) × (tools?)`. Записи — **запросы агента** (title-запрос
опущен). `reas` — длина `reasoning_content` в символах, `tools` — поле `tools` в
теле запроса.

| Кейс (тикет) | variant | tools в теле | reasoning | llama.cpp `reas` | NInfer `reas` | вызов инструмента | финал |
|---|---|---|---|---|---|---|---|
| 1. без reasoning, без tools | `off` | нет поля | нет | `0` | `0` | — | псевдо-`<tool_call>` текстом, не исполняется |
| 2. reasoning (low), без tools | `low` | нет поля | есть | `102` | `143` | — | псевдо-`<tool_call>` текстом, не исполняется |
| 3. без reasoning, с tool call | `off` | 12 | нет | `0` | `0` | **`read`** | `57403` |
| 4. reasoning (medium), с tool call | `medium` | 12 | есть | `22` + `81` | `28` + `185` | **`read`** | `57403` |
| 5. голый ID (дефолт), без tools | — | нет поля | есть | `2157` | `329` | — | псевдо-`<tool_call>` текстом |
| 6. reasoning (xhigh), без tools | `xhigh` | нет поля | есть | `470` | `294` | — | псевдо-`<tool_call>` текстом |

Наблюдения:

- **Ячейки 1–4 тикета закрыты на обоих движках.** `reasoning_content` присутствует
  ровно тогда, когда запрошен thinking; вызов инструмента происходит ровно тогда,
  когда в теле есть `tools` (12 шт.), и приводит к верному `57403`.
- **Effort виден на глаз:** длина reasoning растёт `low < medium < xhigh` в одной
  и той же задаче (llama `102 < 22+81 < 470`; ninfer `143 < 28+185 < 294`). Это
  длина текста `reasoning_content`, не бюджет токенов — как и документирует
  профиль (effort = инструкция шаблона).
- **Без инструментов модель всё равно «зовёт» инструмент** — печатает
  `<tool_call>…` в обычном `content`. opencode это не исполняет (поля `tools` нет,
  цикла вызова нет), поэтому в tap у таких кейсов `tool_calls` пусто. Это
  доказывает, что именно наличие `tools` в теле включает исполнение.
- **Голый ID = thinking + `xhigh`** на обоих движках (llama `reas=2157`; ninfer
  `reas=329`) — согласуется с решением «у сервера нет собственного мнения,
  голый ID отдаёт дефолт шаблона».

### Прямые curl-пробы (независимо от opencode)

`assets/07-verify/curl-probes/{llama,ninfer}/` — прямые запросы на `:8080`,
подтверждают контракт каждого движка (и версию-специфичность llama.cpp):

| Поле клиента | llama.cpp b10068 | NInfer v0.4.6 |
|---|---|---|
| ни чего (голый) | thinking on | thinking on |
| top-level `reasoning_effort: none` | **игнор** (thinking on) | thinking off |
| top-level `reasoning_effort: low/high/xhigh/banana` | **игнор** (thinking on) | форвардится шаблону; неверное → `400` |
| `chat_template_kwargs.enable_thinking: false` | thinking off | thinking off |
| `chat_template_kwargs.reasoning_effort: low/xhigh` | OK (низкий/высокий) | OK |
| `chat_template_kwargs.reasoning_effort: none` | шаблон не принимает `none` → `400` (ошибка рендера шаблона) | OK |

Практический вывод: **общий транскрипт-переносимый рецепт** — только
`chat_template_kwargs`; `reasoning_effort` верхнего уровня под llama.cpp b10068
бесполезен. (На текущем пине b10438 top-level `low|medium|xhigh` работают —
бамп тикета 11, `docs/research/0015`; инертным остаётся только `none`.)

## Найденные дефекты и оговорки

### 1. Версионная рассинхронизация llama.cpp по `reasoning_effort` (регресс)

Запиненный **b10068 не содержит обработки `reasoning_effort` вообще**:

- `git grep reasoning_effort b10068 -- tools/server/` → **пусто**; на локальном
  `../llama.cpp` (`62318cd57`, 2026-10-17) — 9 вхождений, в
  `tools/server/server-common.cpp:1421` есть `if (reasoning_effort == "none")`
  с выключением reasoning.
- В образе: `strings libllama-server-impl.so` = 0 вхождений `reasoning_effort`
  (при этом `enable_thinking` — есть); `strings libllama-common.so.0.0.10068` — тоже 0.

Значит: либо бампить образ llama.cpp до сборки с обработкой `reasoning_effort`,
либо считать top-level `reasoning_effort` неконтрактным для llama-профиля.
Исследование 0013 в этой части описывает поведение **не** запиненной сборки.

### 2. `sendLoadingState` отдаёт загрузочную плашку как `reasoning_content`

`llama-swap sendLoadingState: true` (в `router/config.yaml`) на запросе, который
платит за загрузку движка, стримит баннер **в поле `reasoning_content`**. Замер
(`assets/07-verify/banner-probe/stream.sse`, запрос на llama.cpp после
перезагрузки профиля):

```
reasoning: '━━━━━\nllama-swap loading model: backend-llama\n\nWhispering sweet nothings…\nDone! (2.58s)\n━━━━━\n'
content:   'ok'
```

Для любого потребителя, который определяет «было ли reasoning» по непустому
`reasoning_content`, это **ложное срабатывание** на запросе загрузки. В самой
матрице эффект обойдён прогревом движка до прогона (все запросы матрицы —
«тёплые»), но при реальной эксплуатации первый запрос после смены профиля
загрязняет reasoning. Варианты: `sendLoadingState: false` либо фильтровать
баннер на стороне потребителя.

### 3. Старт профиля `ninfer`: preload падает 404, `/v1/models` показывает `unloaded`

В стартовом логе llama-swap:

```
[INFO] preloading model: backend-ninfer
[INFO] <backend-ninfer> Health check passed on http://localhost:5801/health
[ERROR] failed to preload model backend-ninfer: status 404
```

Причина: llama-swap прелоадит модель запросом `GET /` (llama-swap
`internal/server/api.go:387-414`), а `ninfer-serve` отдаёт только `/health`, `/`
= 404. Двигатель при этом **уже загружен и прогрет** (первый реальный запрос
обслуживается за ~0.16 с — в tap `…meta.txt`), но `/v1/models` продолжает
показывать `status: {"value":"unloaded"}`. Это косметический/статусный баг: он не
ломает работу, но ломает «единый контракт состояния» и пугает в логах.

### 4. `repetition_penalty` остаётся единственным stripParams-различием

Подтверждено косвенно: оба профиля оставляют `stripParams: repetition_penalty`
(тело записи в `router/config.d/`), клиентские sampling-поля не вырезаются, кроме
этого одного. Прямых проб sampling в этот проход не гоняли.

## Не проверено

- **vLLM** (профиль `vllm`, model-ID, единый endpoint за ним) — выведен из карты
  (Out of scope) и в матрицу не входил.
- **Качество при `nvfp4` KV** на NInfer — не оценивалось (открытая оговорка
  профиля из ADR-0003).
- **`preserve_thinking` на едином endpoint** (влияние на историю диалога) — не
  прогонялось; в матрице задача одноходовая.
- **Одновременные диалоги в разных device-state слотах**, второй конкурентный
  запрос, `context_length_exceeded`, vision-вход — не входили в матрицу 07.
- **Точное содержание reasoning** (качество) — измерялась только длина/наличие.
- **Смена драйвера/P2P** — не трогали.

## Доказательства

Каталог `.scratch/llama-swap-orchestrator/assets/07-verify/`:

| Путь | Что |
|---|---|
| `opencode-test.json` | клиентский конфиг прохода 2 (варианты на `body.chat_template_kwargs`) |
| `opencode-test-pass1.json` | клиентский конфиг прохода 1 (`settings.reasoningEffort`) |
| `run-pass2.sh` | матрица прохода 2 с tap + сэмплером VRAM (по backend) |
| `pass2-kwargs/<backend>/` | `tap/` (req+resp+meta), `opencode/` (события), `tap-summary.json`, `vram.csv`/`vram-min.txt`, `ps.txt`, `container.log` |
| `pass1-toplevel-effort/<backend>/` | те же артефакты для прохода 1 |
| `curl-probes/<backend>/` | прямые curl-пробы контракта reasoning |
| `banner-probe/stream.sse` | баннер загрузки как `reasoning_content` |
| `probe-reasoning.sh`, `analyze.py`, `tap-proxy.py` | инструменты |

`ps.txt` каждого прогона фиксирует **ровно один** живой движок
(`ninfer-serve` *или* `llama-server`) — непараллельность подтверждена.

## Красная линия VRAM (дисплейная GPU1 ≥ 512 MiB)

`vram-min.txt` (сэмплер `nvidia-smi` раз в 2 с во время прогона):

| Профиль | GPU0 min free | GPU1 min free |
|---|---|---|
| ninfer | 1139 MiB | **709 MiB** |
| llama | 905 MiB | **1501 MiB** |

Оба прогона держат запас GPU1; минимум по GPU1 за прогоны — 709 MiB ≥ 512 MiB.
Это лёгкая нагрузка (короткие задачи): известный регресс «долгие диалоги в
device-state слотах + 90k-prefill» (минимум 19 MiB, тикет 07 прежнего набора)
этот прогон не воспроизводит.

## Короткий ответ

1. Один публичный ID `qwen3.8-27b` за одним llama-swap **работает и на llama.cpp
   b10068, и на NInfer v0.4.6**; переключение — `PUT /api/profiles/active`.
2. **Клиент управляет reasoning на обоих движках**, если использует
   `chat_template_kwargs` (`enable_thinking: false` / `reasoning_effort:
   low|medium|xhigh`). **Одна конфигурация клиента** даёт: без reasoning — пустой
   `reasoning_content`; с reasoning — непустой, и длина растёт с effort.
3. **Вызов инструмента управляется полем `tools`**: с tools (12) модель зовёт
   `read`, результат `57403`; без tools — тот же текст, но как обычный контент, не
   исполняется.
4. **Переносимая настройка — только `chat_template_kwargs`.** Top-level
   `reasoning_effort` под запиненным llama.cpp b10068 не работает (в сборке нет
   обработки); NInfer его понимает. Это дефект профиля (либо бамп образа, либо
   зафиксировать `chat_template_kwargs` как единственный контракт).
   Закрыто бампом до b10438 (тикет 11, `docs/research/0015`) — top-level
   `low|medium|xhigh` теперь работают на обоих движках, инертен только `none`.
5. Побочные дефекты-для-тикетов: preload 404 + `unloaded` у ninfer; загрузочная
   плашка как `reasoning_content` из-за `sendLoadingState`.
