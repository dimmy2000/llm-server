# Совместимость llm-bench с роутером :8080

Status: resolved
Type: research

## Question

Работают ли скрипты llm-bench (клон для чтения: `/tmp/llm-bench-peek`) без
изменений через роутер llama-swap v265 (`http://localhost:8080`) для каждой из
трёх моделей — и каков план запуска по моделям?

Разобрать конкретно:

1. **Путь prepare** — `POST /v1/messages/count_tokens`: как llama-swap v265
   роутит этот запрос (какая модель, из какого поля тела; локальный исходник —
   `/home/dimmy/projects/00 infra/llama-swap`, найти коммит/тег, соответствующий
   пину v265 — пин в `router/Dockerfile`/`router/docker-compose.yaml`; если
   репозиторий отстаёт — `git pull` и читать код на версии пина, не на HEAD).
   Живой прогон: короткий `count_tokens`-запрос к `strata-iq3` (свап платит
   13–21 c — норма; полный prepare НЕ запускать). Что отвечает `ninfer-serve`
   на тот же вызов для `qwen3.8-27b`? Если у NInfer эндпоинта нет — обходной
   путь для подготовки чанков NInfer: идентичен ли токенеризатор Strata
   (Qwen3.8-Flash-Next, `/opt/strata/packs/*/`) токенеризатору Qwen3.8-27B
   (сравнить файлы токенеризаторов, либо сверить `count_tokens` на одном и том же
   тексте с известным числом токенов) и какой запас до потолка контекста
   (131072 у iq3, 262144 у остальных) это даёт.
2. **Контракт стрима NInfer** — живой прогон: стриминговый запрос
   `qwen3.8-27b` (`/v1/chat/completions`, `stream_options.include_usage`,
   короткий промпт, `max_tokens` ≤ 16): есть ли `usage.prompt_tokens`
   (prefill-скрипт хард-фейлит без него — «no usage in stream»), есть ли блок
   `timings` (engine tok/s; нет — скрипт фоллбечит на client-side).
3. **Поведение роутера** на пине v265: как проксируются
   `stream_options`/`chat_template_kwargs`, что ещё роутер переписывает в теле
   запроса (помимо `stripParams: repetition_penalty`), порядок ID в
   `/v1/models` (скрипты берут первый ID как дефолт).
4. **Требования к чанкам**: сколько чанков нужно протоколу карты (per depth:
   `a,b,c` + `d1..d3`; parallel c2 × runs 3 + solo × runs 2 на глубине 40k),
   даёт ли дефолтный prepare всё или нужен `make-chunks.py`; что делает FLUSH-шаг
   prepare и что он шлёт через роутер.

Результат: план запуска по моделям (точные env/флаги каждого скрипта), список
обходных путей и рисков. Детальные находки — в
`.scratch/llm-bench-results/assets/research-01-router-compat.md`, в тикете —
сводка + указатель на ассет.

## Answer

**Вердикт: стриминговые бенчи (prefill + parallel-decode) работают через
:8080 как есть для всех трёх моделей; чанк-сборка (prepare/make-chunks) —
нет, без двух однострочных патчей рабочей копии клона.**

1. **Стрим NInfer — лучше, чем предполагалось.** Живой прогон
   `qwen3.8-27b` (`stream_options.include_usage` +
   `chat_template_kwargs.enable_thinking`): 200, финальный чанк несёт И
   `usage.prompt_tokens` (prefill-скрипт не фейлится), И полный блок
   `timings` того же schema, что у Strata (`prompt_n/prompt_ms`,
   `predicted_n/predicted_ms`, `draft_n/draft_n_accepted`, `cache_n`) →
   engine tok/s берётся из движка и у NInfer, client-side фоллбек не нужен.
   `stream_options`/`chat_template_kwargs` проксируются роутером без
   изменений (в конвейере body-фильтров у нашего конфига — только
   `stripParams: repetition_penalty`, `useModelName`/`setParams` не заданы).
2. **count_tokens — есть у обоих движков, токенизаторы идентичны.**
   `POST /v1/messages/count_tokens` маршрутизируется роутером по топ-
   уровневому полю `model` тела (неизвестный ID → 404 «no router for
   requested model»). `model: qwen3.8-27b` → 200 `{"input_tokens":…}`
   (эндпоинт у NInfer ЕСТЬ), `model: strata-iq3` → 200 (свап 16.6 c).
   Один текст → 71 токен и у NInfer, и у Strata (пусто → 52); статическое
   сравнение файлов: мержи идентичны (247587, порядок), vocab идентичен
   0..248043 (+276 спец-токенов в хвосте у Strata = те же id, что
   `added_tokens` у HF). Обходной путь для чанков NInfer не нужен — габарит
   считается его собственным count_tokens (сдвиг шаблона ~40 токенов
   систематичен и поглощается допуском ±0.5%).
3. **Блокер prepare/make-chunks: хардкод `model: "bench-prepare"`.** Оба
   скрипта (count_tokens + FLUSH) шлют этот ID → через роутер 404 (живой
   факт), prepare хард-фейлит после 5 ретраев. Патч рабочей копии клона
   (1 строка): `sed 's/"bench-prepare"/"qwen3.8-27b"/'` в обоих файлах —
   qwen резидентна (прелоад), считает идентично, FLUSH 235k влезает в её
   ctx 262144. FLUSH при этом всё равно безвредно выключить (`FLUSH=0`):
   он шлёт один 235k-токенный `chat/completions` для вытеснения кэша, а
   per-depth warmup prefill-скрипта делает то же на целевом движке.
4. **Warmup prefill-скрипта не влезает в ctx iq3 на глубине 120k**
   (150 020 > 131 072) → 400 → незахваченный `RuntimeError`, скрипт падает
   на этой глубине. Патч (1 строка, рабочая копия): в
   `bench-real-prefill.sh` `depth // 12 + 1` → `depth // 15 + 1`
   (warmup ≈ 1.07×depth: 120k→128 035 ✓, 200k→213 366 < 262 144 ✓; вытеснение
   кэша сохраняется — warmup больше любого чанка на ±0.5%).
5. **Порядок `/v1/models`** — алфавитный, детерминирован
   (сортировка `api.go`): `qwen3.8-27b, strata-iq2, strata-iq3`; первый ID =
   `qwen3.8-27b`. Скрипты по умолчанию берут первый ID → `MODEL=`/`--model`
   задавать ЯВНО для каждой модели (иначе всё побенчится на qwen3.8-27b).
6. **Чанки**: prefill — дефолтный prepare даёт ровно нужные 6 слотов на
   глубину (a,b,c,d1..d3); параллельный decode ТРЕБУЕТ `make-chunks.py`
   (числовые слоты; без них параллель-слоты укатываются на текст prefill и
   на филлер). Объём нового текста ~2.82M из корпуса ~3.3M — влезает с
   запасом (риск №6 в ассете).
7. **План запуска** (точные env/флаги, порядок, патчи — полный раздел 7
   ассета): сборка чанков одним блоком
   (`prepare DEPTHS=40000,150000,200000` → `prepare FORCE=1 DEPTHS=120000` →
   `make-chunks --depth 40000 --ranges 0-3,100-105,200-201`, всё
   `URL=http://localhost:8080 FLUSH=0`); затем на каждую модель:
   `bench-real-prefill.sh` (`URL=http://localhost:8080 MODEL=<id> DEPTHS=…` —
   qwen/iq2: 40000,150000,200000; iq3: 40000,120000) + два вызова
   `bench-parallel-decode.py` (`--url http://localhost:8080 --model <id>
   --data-dir ./realdata --chunk-depth 40000 --solo --runs 2 --concurrency 2
   --chunk-offset 0` и `--runs 3 --concurrency 2 --chunk-offset 100` —
   канонический par-3). Прогоны строго последовательны; каждый переход
   между моделями = 1 свап (NInfer 6–9 c, Strata 13–21 c), warmup впитывает
   холодный старт. Порядок моделей свободный (текущий резидент — iq3).
8. **Риски/ограничения** (раздел 8 ассета): патчи обязательны; FLUSH не
   работает через роутер (митигция FLUSH=0 + warmup); первый замер глубины
   может дать малый `cached_tokens` (~10–50, общая обёртка промпта — не
   заражение); книги — узкое место (запас ~0.5M); поведение на полных
   глубинах и стрим Strata через роутер короткими пробами не проверялись.

Детали, команды и живые ответы — `assets/research-01-router-compat.md`.
