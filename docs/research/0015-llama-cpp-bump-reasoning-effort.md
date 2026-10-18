# 0015 — Бамп llama.cpp `b10068 → b10438`: top-level `reasoning_effort` под единым endpoint'ом

Дата: 2026-10-17. Исследование по тикету
`.scratch/llama-swap-orchestrator/issues/11-llama-reasoning-effort-skew.md`
(карта `.scratch/llama-swap-orchestrator/map.md`). Раздел «Доказательная база
на b10438» добавлен по тикету
`.scratch/llama-swap-orchestrator/issues/15-verify-b10438.md` — он закрывает
три пункта «Не проверено» исходного отчёта.

Вопрос тикета: запиненный в `router/Dockerfile` llama.cpp **b10068 не
обрабатывает `reasoning_effort` вообще** (в бинарниках образа 0 вхождений
строки, живой прогон тикета 07 — поле полностью инертно), поэтому часть
клиентов (включая opencode, который транслирует `settings.reasoningEffort`
именно в `reasoning_effort`) не может управлять reasoning через единый
model-ID. Требовалось выбрать между (1) бампом образа, (2) документированием
top-level `reasoning_effort` как no-op и (3) shim'ом в llama-swap — и
обосновать выбор.

**Решение: вариант 1 — бамп пина на `server-cuda13-b10438`.** Разрыв закрыт для
значений `low|medium|xhigh` на обоих движках одним и тем же клиентским полем.
Варианты 2 и 3 отвергнуты по фактам (ниже). Остаточный разрыв: top-level
`reasoning_effort: "none"` на b10438 по-прежнему **не выключает** thinking
(NInfer выключает); переносимый способ — `chat_template_kwargs`.

## Что изменено

Единственная содержательная правка — пин llama.cpp в `router/Dockerfile`:

```dockerfile
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4…6283 /app /app
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4…6283 /usr/local/cuda-13.3/lib64 /usr/local/cuda-13.3/lib64
```

| | было (тикеты 06/07) | стало (тикет 11) |
|---|---|---|
| Тег | `server-cuda13-b10068` | `server-cuda13-b10438` |
| Дайджест индекса | `sha256:6447a865bd031283c5f66ff2a82984cdb282ec37484cf2a9bfc7b4cb1f85708e` | `sha256:bb81f3e4ef93697f025156849e55b8d6a92ef10b7cae3460bf0cf8a4d6ea6283` |
| amd64-ребёнок | `sha256:1c0cc37edc5f…` | `sha256:551298aeeb34d927fbce8f5df9da5214d25822f8eb01bba039b5c8a9ad7d564e` |
| Ревизия llama.cpp | `b10068` / `571d0d540` | `b10438` / `9d57ce456` |
| База образа | Ubuntu 24.04 + CUDA **13.3** | Ubuntu 24.04 + CUDA **13.3** (без изменений) |
| Путь CUDA-библиотек | `/usr/local/cuda-13.3/lib64` | тот же |

`router/config.yaml`, `router/config.d/10-llama.yaml`, `20-ninfer.yaml` и
`docker-compose.yaml` не менялись: флаги ядра (`--spec-type`, `--cache-*`,
`--reasoning`, `--fit`, `--split-mode tensor`, `--tensor-split`) в b10438
существуют с теми же именами и дефолтами, поэтому `cmd` llama-движка остался
побайтово прежним. Пины llama-swap (`v265`) и NInfer (`v0.4.6`) не тронуты.

Пересборка: `docker compose build` → `llm-server/router:v265`
`sha256:ef2b62774977470f52c82aed870e27e91fa56f31782ece8a06e6707fdecef349`
(2026-10-17T19:11:28+03:00). Дальше `docker compose down --remove-orphans` +
`up -d --wait`, контейнер healthy, профиль переключался вручную через
`PUT /api/profiles/active`.

## Археология версий: почему именно b10438

Обработка OAI-поля `reasoning_effort` в llama.cpp появилась двумя независимыми
коммитами, и для контракта карты нужны **оба**:

| Коммит | Что даёт | Первый тег | Опубликован ли `server-cuda13-b*` |
|---|---|---|---|
| `27209a598` «server: support "reasoning_effort": "none" in OAI API (#26045)» | `none` → `inputs.enable_thinking = false` | `b10121` | да (`sha256:2d24cdff26e0…`) |
| `7e4c0a968` «chat : pass reasoning_effort to template» | остальные значения → `chat_template_kwargs.reasoning_effort`, т.е. уходят в шаблон | `b10434` | **нет** (HTTP 404) |

ggml-org публикует `server-cuda13-b*` разреженно (не на каждый тег), поэтому
`b10434` взять нельзя. `b10438` (`9d57ce456`) — **первый опубликованный
cuda13-образ, содержащий оба коммита**. Проверка публикации — анонимный
GHCR-token и `Docker-Content-Digest` тега (метод тот же, которым проверялся
существующий пин b10068: дайджест воспроизводится байт в байт).

Почему не выше: с `b11706` ggml-org перешёл на CUDA **13.4**, и путь
`/usr/local/cuda-13.3/lib64` во втором `COPY` перестал бы существовать — это
отдельная правка образа и отдельный риск. `b10438` остаётся на той же базе
CUDA 13.3, что и b10068, поэтому бамп сводится к замене двух строк.

Статическая проверка на самих образах (`grep -a` по бинарникам, binutils в
образе нет):

| Бинарник | `reasoning_effort` | `enable_thinking` |
|---|---|---|
| b10438 `libllama-server-impl.so` | **1** | 4 |
| b10438 `libllama-common.so.0.1.0` | **5** | 5 |
| b10068 `libllama-server-impl.so` | **0** | 4 |
| b10068 `libllama-common.so.0.0.10068` | **0** | 5 |

`llama-server --version` в собранном образе: `0.1.0-dev (build 10438, commit
9d57ce456)`; `system_fingerprint` в ответах — `b10438-9d57ce456`. Доказательство
негативного контроля (b10068 = 0 вхождений) совпадает с находкой тикета 07
(research 0014, раздел «Версионная рассинхронизация»).

## Метод живого прогона

Два прохода по одной сетке проб на каждом движке, при уже загруженном движке
(иначе первая проба платит загрузку весов и llama-swap подмешивает свой баннер
в `reasoning_content` — см. тикет 13):

1. `probe-reasoning.sh <backend>` — 12 кейсов streaming `/v1/chat/completions`
   через `:8080` (единый ID `qwen3.8-27b`), фиксируются длина
   `reasoning_content` и `content`;
2. `probe-tools.sh <backend>` — 4 кейса non-streaming с `tools` и без;
3. `apply-template-probe.py` — только для llama: `POST /apply-template`
   **напрямую в `llama-server` (`:5800`, минуя llama-swap)**. Эндпоинт вызывает
   ту же `oaicompat_chat_params_parse`, что и chat completions, и возвращает
   ровно собранный шаблоном промпт — так видно, дошло ли поле клиента до
   шаблона, не гадая по ответу модели;
4. `run-pass.sh <backend>` — обёртка: сэмплер свободной VRAM каждые 2 с
   (`vram.csv` → `vram-min.txt`), `ps.txt` (какой движок жив —
   непараллельность), `container.log`.

Промпт-задача: «Compute 419 multiplied by 137 step by step, then reply with
only the number», `max_tokens: 300`. Длины `reasoning_content` — не метрика
качества, а индикатор «thinking включён/выключен и на каком уровне»; разброс
между прогонами на одном уровне ожидаем.

## Результаты: reasoning

| Кейс клиента | llama.cpp **b10438** | NInfer **v0.4.6** | llama.cpp b10068 (тикеты 07/0014) |
|---|---|---|---|
| голый ID | thinking, `xhigh` — 384 | thinking, `xhigh` — 515 | thinking, `xhigh` |
| top-level `reasoning_effort: none` | **441 — ИНЕРТНО** | **0 — выключено** | инертно |
| top-level `low` | 191 | 249 | инертно |
| top-level `medium` | 391 | 290 | инертно |
| top-level `xhigh` | 444 | 328 | инертно |
| kwargs `enable_thinking: false` | **0** | **0** | 0 |
| kwargs `reasoning_effort: none` | **500** (raise шаблона) | 0 | — |
| kwargs `reasoning_effort: low` | 243 | 218 | — |
| kwargs `reasoning_effort: xhigh` | 497 | 288 | — |
| kwargs `reasoning_effort: banana` | **500** | **400** `invalid_template_option` | — |
| top-level `banana` | **500** | **400** `reasoning_effort must be one of none, minimal, low, medium, high, xhigh, max, or adaptive` | инертно (200) |
| top-level `low` + kwargs `enable_thinking: true` | 242 | 297 | — |

Главное: **top-level `reasoning_effort: low|medium|xhigh` теперь работает на
обоих движках одним и тем же полем клиента** — до бампа под llama-профилем оно
молча игнорировалось. Это ровно тот разрыв, который ломал цель карты «клиент
управляет reasoning» и переносимость клиентского контракта.

### Остаточный разрыв: top-level `none`

`reasoning_effort: "none"` под llama.cpp b10438 thinking **не выключает**:
ответ содержит reasoning (441 chars), а `/apply-template` рендерит промпт
длиной 325 — **побайтово как голый запрос**, с тем же системным промптом
«Reasoning effort is set to xhigh…».

При этом ветка `none` в движке **исполняется**: она стирает
`chat_template_kwargs.reasoning_effort`, и это видно из пробы
`{"reasoning_effort": "none", "chat_template_kwargs": {"reasoning_effort":
"low"}}` — рендер падает обратно к дефолтному `xhigh` (325) вместо `low` (254).
То есть поле до сервера доходит, `erase` срабатывает, а `enable_thinking =
false` (в b10438 это `tools/server/server-common.cpp:1299`) до рендера шаблона
не доходит. Механизм не установлен: чтение b10438 (`server-common.cpp` →
`common_chat_templates_apply_jinja` → `common_chat_params_init_qwen3_coder` →
`common_chat_template_direct_apply_impl`, где `inp["enable_thinking"] =
inputs.enable_thinking`) не объясняет наблюдаемое, а на HEAD (`62318cd57`)
производная `enable_thinking = params_base.enable_reasoning != 0 &&
template_supports_thinking` (`server-context.cpp:1613`) остаётся той же, так
что «починится следующим бампом» утверждать нельзя. Разбор требует дампа
встроенного шаблона модели и, вероятно, upstream-репорта — вынесено в тикет 15.

Следствие для контракта: **`none` как способ выключить thinking непереносим.**
Переносимый способ — `chat_template_kwargs: {"enable_thinking": false}` (0
символов reasoning на обоих движках, рендер llama падает с 325 до 99).

### Расхождения, которые остались после бампа

| Поведение | llama.cpp b10438 | NInfer v0.4.6 |
|---|---|---|
| top-level `none` | инертно (thinking xhigh) | выключает thinking |
| kwargs `reasoning_effort: none` | `500`, raise шаблона «Unexpected reasoning effort» | `200`, thinking выключен |
| невалидное значение (`banana`) | `500`, raise шаблона | `400` с внятным списком допустимых значений |
| Ошибка клиента vs сервера | шаблон падает → 500 | валидация до движка → 400 |

`500` на невалидном значении — поведение самого Jinja-шаблона модели
(`raise_exception`), а не llama-swap; до бампа поле игнорировалось и тот же
запрос отвечал `200`. То есть бамп превратил молчаливое игнорирование в явную
ошибку — это лучше для отладки, но потребитель, шлющий произвольную строку в
`reasoning_effort`, теперь получит 500 вместо «просто thinking».

## Результаты: tools

| Кейс | llama.cpp b10438 | NInfer v0.4.6 |
|---|---|---|
| `tools`, голый ID | `finish=tool_calls`, `get_weather`, args `{"city":"Paris"}`, reasoning 99 | то же, reasoning 140 |
| `tools` + top-level `none` | `finish=tool_calls`, `get_weather`, args `{"city":"Paris"}`, reasoning 140 | то же, reasoning 0 |
| без `tools`, голый ID | `finish=stop`, tool_calls нет, reasoning 328 | `finish=stop`, reasoning 160 |
| без `tools` + top-level `none` | `finish=length`, reasoning 1378 | `finish=stop`, reasoning 0 |

Разбор tool-calls на b10438 не деградировал (вызов, имя и аргументы верны как
с thinking, так и без него); контрольный кейс без `tools` инструмент не
исполняет. Строка `finish=length` у llama в кейсе «без tools + none» — прямое
следствие того, что `none` инертен: модель ушла в длинное рассуждение и уперлась
в `max_tokens: 300`, тогда как NInfer ответил коротко без thinking.

## Красная линия VRAM (дисплейная GPU1 ≥ 512 MiB)

Минимум свободной VRAM за прогон (сэмпл каждые 2 с):

| Профиль | GPU0 | GPU1 |
|---|---|---|
| llama (b10438) | 915 MiB | **1171 MiB** |
| ninfer (v0.4.6) | 1199 MiB | **710 MiB** |

Красная линия держится на обоих. Непараллельность подтверждена `ps.txt`: в
каждом прогоне жив ровно один движок (`llama-server` или `ninfer-serve`).

## Предупреждения в логе llama-движка

`W spec common_specu: backend offload failed for seq_id=0; using CPU sampler` —
**не регресс бампа**: та же строка есть в логах b10068 из тикета 07
(`assets/07-verify/pass1-toplevel-effort/llama/container.log:341`,
`pass2-kwargs/llama/container.log:341,869`).

`[ERROR] failed to preload model backend-ninfer: status 404` в
`llama/container.log` — известный дефект NInfer-прелоада (тикет 12), к бампу
отношения не имеет.

## Доказательная база на b10438 (тикет 15): матрица субагентов, A/B, механизм `none`

Все прогоны через единый `:8080`, llama-профиль активен, `system_fingerprint`
в ответах `b10438-9d57ce456`; после работ система возвращена на ninfer.
Доказательства — `.scratch/llama-swap-orchestrator/assets/15-verify-b10438/`
(подкаталоги `matrix/`, `bench/`, `none-mechanism/`).

### Матрица opencode-субагентов на b10438

Метод — проход 2 из 0014 без изменений: opencode v2.0.32, tap-прокси (`:8090`,
тела запросов и сырые SSE-ответы на диск), изоляция `HOME`, та же задача
«notes.txt × 137» (верный ответ `57403`), варианты на
`body.chat_template_kwargs`; агенты `tools-on`/`tools-off` (deny-all
permissions). Top-level варианты в матрице не использовались — как и в
итоговом конфиге потребителя (тикет 14). NInfer-сторона не переснималась (пин
NInfer не менялся), столбец 0014 приведён как есть.

`reas` — длина `reasoning_content` в символах; запросы агента (title-запросы
опущены — там поведение то же: `off` → 0, effort → непусто):

| Кейс (тикет) | variant | tools в теле | b10438 `reas` | b10068 (0014) | NInfer (0014) | вызов инструмента | финал |
|---|---|---|---|---|---|---|---|
| 1. без reasoning, без tools | `off` | нет поля | `0` | `0` | `0` | — | псевдо-`<tool_call>` текстом |
| 2. reasoning low, без tools | `low` | нет поля | `134` | `102` | `143` | — | псевдо-`<tool_call>` текстом |
| 3. без reasoning, с tool call | `off` | 12 | `0` | `0` | `0` | **`read`** | `57403` |
| 4. reasoning medium, с tool call | `medium` | 12 | `88` + `137` | `22` + `81` | `28` + `185` | **`read`** | `57403` |
| 5. голый ID (дефолт) | — | нет поля | `592` | `2157` | `329` | — | псевдо-`<tool>` текстом |
| 6. reasoning xhigh, без tools | `xhigh` | нет поля | `160` | `470` | `294` | — | псевдо-`<tool_call>` текстом |

**Матрица тикета 07 закрыта на b10438 в полном объёме**, картина та же, что на
b10068 и NInfer: `reasoning_content` присутствует ровно тогда, когда запрошен
thinking; инструмент вызывается ровно тогда, когда в теле есть `tools` (12), и
цикл приводит к верному `57403`; голый ID — дефолт шаблона (thinking +
`xhigh`). Бамп поведения reasoning/tools не изменил. Длины reasoning —
индикатор, не метрика: монотонность по effort здесь не строгая (`low` 134,
`xhigh` 160, `medium` 804 в другой ячейке) — в пределах ожидаемого разброса.

`matrix/vram-min.txt`: GPU0 905 / GPU1 **1345** MiB — красная линия держится;
`matrix/ps.txt` — жив ровно один движок (`llama-server`).

### A/B производительности: b10438 против b10068

Метод — `bench/bench.py` (протокол 0005, адаптирован под единый endpoint):
`/v1/chat/completions` non-streaming, reasoning off
(`chat_template_kwargs.enable_thinking: false`), temperature 0.7 + пресет
0005, уникальный связный промпт на каждый замер (без переиспользования
KV-префикса), метрики из `timings` ответа; по одному прогону на кейс на каждую
сборку. Флаги движка в обоих прогонах совпадают байт в байт (`bench/ps-b10068.txt`
vs `matrix/ps.txt`), сборки подтверждены `system_fingerprint`
(`b10068-571d0d540` / `b10438-9d57ce456`).

| Кейс | Метрика | b10068 | b10438 | Δ |
|---|---|---|---|---|
| tiny-temp0 (128 ток.) | prefill tok/s | 1002 | 1312 | — (промпты разные: 155 vs 272 ток., кейс не показателен) |
| | decode tok/s | 158.6 | 160.2 | +1.0 % |
| p16k-gen1024 (промпт ~26k ток.) | prefill | 2543 | 2726 | **+7.2 %** |
| | decode | 52.3 | 54.2 | +3.5 % |
| | приём драфта | 0.663 | 0.684 | |
| p16k-gen1024-rep | prefill | 2529 | 2706 | **+7.0 %** |
| | decode | 53.0 | 51.1 | −3.6 % |
| | приём драфта | 0.690 | 0.615 | |
| p60k-gen1024 (~96k ток.) | prefill | 1986 | 2099 | **+5.7 %** |
| | decode | 44.6 | 41.9 | −5.9 % |
| | приём драфта | 0.677 | 0.608 | |
| p100k-gen256 (~160k ток.) | prefill | 1623 | 1699 | **+4.7 %** |
| | decode | 29.5 | 37.1 | +25.6 % |
| | приём драфта | 0.571 | 0.558 | |
| wall-clock, с (p16k / rep / p60k / p100k) | | 29.9 / 30.0 / 72.0 / 108.1 | 28.5 / 29.9 / 70.7 / 101.7 | везде ≤ |

**Вывод: регресса нет, пин b10438 остаётся.** Prefill на больших промптах
стабильно на 5–7 % быстрее, decode — в пределах разброса одиночных прогонов
(−6…+26 %), приём драфта сопоставим (0.56–0.68 против 0.57–0.69), wall-clock
равен или лучше на всех кейсах. OOM и ошибок нет; префилл 159k токенов прошёл
на обеих сборках с включённой спекуляцией. Оговорки: один прогон на кейс,
temperature 0.7 (sampling недетерминирован), промпты уникальны — разницу в
несколько процентов строго атрибутировать нельзя; но и признаков регресса
(просадка приёма при росте wall-clock, OOM, ошибки) нет. Если бы регресс
нашёлся, варианты были бы: (1) бисекция b10068…b10438 в поиске коммита,
(2) откат пина с потерей `reasoning_effort` (возврат контрактной проблемы
тикета 11), (3) принятие с документированием цены. Актуальность снята.

VRAM bench-прогонов (`bench/vram-*.csv`): GPU0 min 903/905, GPU1 min
**1345** MiB (b10068/b10438) — красная линия держится на обеих сборках
одинаково.

### Механизм инертности top-level `none` — установлен

Гипотеза из раздела «Остаточный разрыв» подтвердилась и сужена: **виноват
CLI-флаг `--reasoning on`** (стоит в `cmd` llama-движка,
`router/config.d/10-llama.yaml`). Цепочка (b10438, `9d57ce456`; на HEAD
`62318cd57` код тот же — «починится следующим бампом» утверждать нельзя):

1. `--reasoning on` инжектит CLI-дефолт
   `params.default_template_kwargs["enable_thinking"] = "true"`
   (`common/arg.cpp:3635-3637`).
2. CLI-дефолты становятся per-request kwargs: `server-context.cpp:1431`
   передаёт `params_base.default_template_kwargs` в
   `oaicompat_chat_params_parse()`, откуда инициализируется
   `inputs.chat_template_kwargs` (`server-common.cpp:1280`).
3. Ветка `none` ставит `inputs.enable_thinking = false`, но стирает из kwargs
   только `reasoning_effort` (`server-common.cpp:1298-1300`) — CLI-дефолт
   `enable_thinking: "true"` выживает.
4. На рендере `extra_context` (из `chat_template_kwargs`) накладывается
   **после** распарсенного флага и побеждает (`common/chat.cpp:3443-3447`;
   значения перечитываются `json::parse`, поэтому строка `"true"` становится
   булевым `true`). Шаблон модели гейтит thinking ровно одним kwarg —
   `enable_thinking` (`chat-template.jinja:58,178`); значения `none` в его
   словаре нет вовсе, top-level `none` действует только через
   `inputs.enable_thinking`, которое перебивается.

Клиентский путь `chat_template_kwargs.enable_thinking: false` работает именно
потому, что клиентские kwargs мержатся **после** CLI-дефолтов
(`server-common.cpp:1281-1283`) и перезаписывают `"true"`; у top-level `none`
такой перезаписи нет. Снятие `--reasoning on` не рассматривается как фикс:
флаг стоит в `cmd` профиля сознательно (тикет 06), а переносимый контракт
top-level `none` и не использует.

Доказательства:

- **Дифрепро** (`none-mechanism/repro-reasoning-on.sh`): два CPU-инстанса
  b10438 на Qwen3-0.6B, отличие только во флаге. С `--reasoning on`: рендер
  `none` == bare, живой ответ — 200 токенов `reasoning_content`
  (`repro-on-response.json`). Без флага (`auto`): `none` даёт пустой
  `<think>\n\n</think>` и чистый ответ «Two» без reasoning
  (`repro-auto-response.json`).
- **Живой 27B** (`render-*.txt` через `/apply-template`): `none` — 325 байт,
  побайтово как bare; `none` + kwargs `enable_thinking: false` — 99 байт с
  пустым think-блоком; `none` + kwargs `true` — 325. Тот же рендер `none` на
  b10438, что зафиксирован в исходном прогоне тикета 11, — механизм один и
  тот же.

#### Черновик upstream-репорта

`none-mechanism/upstream-issue-draft.md` — DRAFT, не отправлен. Оценка:
**готов к подаче после вычитки**. Сильные стороны: минимальный дифрепро на
крошечной модели (воспроизводится мейнтейнерами без 27B и GPU, один бинарник
— отличие только флагом), причинная цепочка с file:line на b10438 и HEAD,
предлагаемый фикс (`inputs.chat_template_kwargs.erase("enable_thinking")` в
ветке `none`) и честно поставленный семантический вопрос к мейнтейнерам
(клиентский `enable_thinking: true` рядом с `none` при таком фиксе стирался
бы тоже — тогда CLI-дефолты нужно разделять с клиентскими kwargs). Локальная
правка: ссылка на отчёт исправлена на `docs/research/0015-…`. Сама подача —
за человеком (учётка GitHub, решение вне карты).

### Следствия

- Пин `b10438` подтверждён по всем трём осям (матрица, производительность,
  разбор `none`) — откат не требуется; переносимый контракт из «Короткого
  ответа» не меняется.
- Доказательная база «проверено opencode-субагентами на обоих движках» снова
  актуальна: llama-сторона переснята на текущем пине.
- Тикету 08 (доки) достаточно ссылаться на этот раздел как на актуальную
  доказательную базу b10438 и на черновик upstream-репорта как на
  отложенный внешн. action.

## Не проверено

- ~~Производительность движка после бампа~~ — закрыто тикетом 15 (A/B в
  разделе выше, регресса нет).
- ~~Матрица opencode-субагентов на b10438~~ — закрыто тикетом 15 (раздел выше).
- ~~Механизм инертности top-level `none`~~ — установлен тикетом 15 (раздел
  выше); upstream-репорт подготовлен, не отправлен.
- Длинный контекст (180224) и стабильность `--spec-type draft-mtp,ngram-mod`
  на b10438 под длительной нагрузкой: A/B частично покрывает (префилл 159k
  токенов прошёл без OOM на обеих сборках), но многочасовой soak и генерация
  на полном ctx не снимались; `--ctx-checkpoints`, `--fit` не пересматривались.
- A/B — одиночный прогон на кейс (temperature 0.7, уникальные промпты):
  строгая атрибуция разницы в несколько процентов невозможна, для точных
  цифр нужны повторы.
- Качество reasoning на b10438 не оценивалось (только наличие/длина);
  NInfer-сторона матрицы не переснималась (пин NInfer не менялся).

## Доказательства

`.scratch/llama-swap-orchestrator/assets/11-llama-bump/`:

| Путь | Что это |
|---|---|
| `README.md` | раскладка каталога |
| `image-checks.txt` | `llama-server --version` после бампа, grep по бинарникам, негативный контроль b10068, ID собранного образа |
| `probe-reasoning.sh`, `probe-tools.sh`, `run-pass.sh`, `apply-template-probe.py` | сами пробники (воспроизводимо) |
| `llama/`, `ninfer/` | по одному подкаталогу на движок: `NN-*.sse`/`NN-*.json` — сырые ответы, `probe-reasoning.txt`/`probe-tools.txt` — сводки, `apply-template.txt` (только llama), `vram.csv`/`vram-min.txt`, `ps.txt`, `container.log` |
| `15-verify-b10438/matrix/` | матрица субагентов на b10438: `tap/` (req+resp+meta), `tap-summary.json`, `run-matrix.sh`, `opencode/` (события), `opencode-test.json`, `vram.csv`/`vram-min.txt`, `ps.txt`, `container.log` |
| `15-verify-b10438/bench/` | A/B b10068 vs b10438: `bench.py`, `summary-*.jsonl`, `vram-*.csv`, `ps-*.txt`, `version-*.txt`, `container-*.log` |
| `15-verify-b10438/none-mechanism/` | разбор `none`: дифрепро `repro-reasoning-on.sh` + `repro-*`, живые рендеры 27B `render-*.txt`, `chat-template.jinja`, `props.json`, черновик upstream-репорта |

Связанные отчёты: `docs/research/0014-opencode-single-endpoint-live-verification.md`
(исходная находка разрыва, раздел «Версионная рассинхронизация»),
`docs/research/0013-backend-request-contracts.md` (таблица совместимости
параметров), `docs/research/0009-ninfer-tp2-two-5070ti.md` (NInfer-сторона).

## Короткий ответ

Бамп — правильный способ закрыть разрыв: он единственный из трёх вариантов
делает top-level `reasoning_effort: low|medium|xhigh` работающим на **обоих**
движках одним и тем же клиентским полем, стоит двух строк в `router/Dockerfile`
и не тянет за собой смену CUDA-базы, конфигов или флагов ядра. Документирование
no-op (вариант 2) оставило бы контракт тикета 10 («instruct = явный
`reasoning_effort: none`») ложным под llama.cpp и сохранило бы молчаливое
игнорирование `low|medium|xhigh`. Shim в llama-swap (вариант 3) невыразим
конфигом: `filters` умеют только плоские `stripParams`/`setParams`/
`setParamsByID` (`../llama-swap/internal/config/filters.go`), без условного
маппинга значений и без перезаписи вложенного `chat_template_kwargs`, а жёсткий
`setParams` затирал бы клиентские kwargs — то есть создавал бы серверное
мнение, которое карта запрещает.

После бампа переносимый клиентский контракт такой:

- выключить thinking: `chat_template_kwargs: {"enable_thinking": false}` —
  работает на обоих движках;
- уровень reasoning: `reasoning_effort: low|medium|xhigh` (top-level, оба
  движка) либо `chat_template_kwargs: {"reasoning_effort": …}` (оба движка);
- `reasoning_effort: "none"` — **только NInfer**; под llama.cpp инертно;
- `reasoning_effort` в kwargs со значением `none` под llama.cpp — `500`;
- невалидное значение: `500` (llama.cpp) против `400` (NInfer).

Документирование этого (ADR-0006, README, AGENTS.md, `CONTEXT.md`) и замена
упоминаний `b10068` на `b10438` — работа тикета 08.

Тикет 15 подтвердил бамп по всем осям: матрица субагентов закрыта на b10438 с
той же картиной, что на b10068 и NInfer; A/B на одном бенчмарке регресса не
показал (prefill +5–7 % на промптах 26k–160k, decode в пределах разброса
одиночных прогонов, wall-clock равен или лучше) — пин остаётся; инертность
top-level `none` объяснена CLI-дефолтом `enable_thinking: "true"` от флага
`--reasoning on`, черновик upstream-репорта готов к подаче.
