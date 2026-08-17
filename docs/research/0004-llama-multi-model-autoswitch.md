# Авто-переключение нескольких моделей: llama.cpp router-mode (models-preset) vs llama-swap groups/matrix

Дата среза: 2026-08-17.

Статус: исследование. Конфигурация, контейнеры и runtime в рамках работы не
изменялись. Все утверждения проверены по первичным источникам:

- клон llama.cpp master commit `058df671b214a7447f33b3e962501175b3a752f4`
  (2026-08-17): `tools/server/README.md`, `tools/server/server-models.cpp/.h`,
  `tools/server/server.cpp`, `common/preset.cpp`, `common/arg.cpp`,
  `common/arg.h`, `common/common.h`, `common/subproc.cpp`, `CMakeLists.txt`,
  `docs/preset.md`, `tools/server/tests/unit/test_router.py`; история PR —
  GitHub API (PR #17470, #17859, #18161, #26572, #18228, #26102);
- клон llama-swap commit `08f1076cb777e787eba3f57170350aa09513341a`
  (2026-08-16, тот же, что в 0003): `config.example.yaml`,
  `config-schema.json`, `docs/configuration.md`,
  `internal/router/group.go`, `internal/router/matrix.go`,
  `internal/router/matrix_solver.go`, `internal/matrix/program.go`,
  `internal/router/scheduler/fifo.go`, `internal/router/base.go`;
- локальные файлы репозитория: `docs/llama-config/run_server.bat`,
  `docs/llama-config/config/models.ini`, `llama/config.yaml`;
- предыдущее исследование
  [0003-llama-swap-model-toggle.md](0003-llama-swap-model-toggle.md) —
  жизненный цикл llama-swap (ttl, unloadTimeout, healthCheckTimeout,
  автостарт по первому запросу, эндпоинты). Не дублируется, цитируется.

## Краткий вывод

Обе технологии умеют «несколько моделей, одна резиденция в VRAM,
авто-переключение по первому запросу», но механика разная:

1. **llama.cpp router mode** (`--models-preset models.ini --models-max 1`,
   запуск без `-m`): роутер-процесс спавнит дочерние `llama-server`
   (субпроцессы), по одному на модель. `--models-max 1` гарантирует ровно один
   запущенный инстанс: запрос к невыгруженной модели встаёт в очередь,
   LRU-планировщик выгружает простаивающую модель (не трогая занятую) и только
   потом загружает новую (stop-then-start, VRAM между загрузками свободна).
   Весь контекст моделей — INI-пресеты (секции `[*]` global + per-model);
   sampling, ctx-size, tensor-split, device, spec-* — любые аргументы
   llama-server как ключи. Это ровно то, что делает Windows-батник
   `run_server.bat`; режим кроссплатформенный (Linux включён по умолчанию).
   Swap = stop старой (до `stop-timeout`, дефолт 10 с) + cold-start новой
   (qwen3.8-27b ~40-60 c). Плюс есть `--sleep-idle-seconds` — сон с полным
   освобождением VRAM без убийства процесса. Минус: KV-cache между моделями не
   переиспользуется (у каждой модели свой процесс и свой контекст).

2. **llama-swap** (текущая конфигурация репозитория — `cmd: "sleep infinity"`,
   см. 0003): переключение моделей в одной группе с `swap: true` даёт то же
   «только одна модель»: eviction при запросе безусловный (не зависит от
   `ttl`; `ttl` управляет только автовыгрузкой по простою без запроса).
   `evict_models` как ключа не существует — механизм один: членство в группе.
   Маршрутизация — строго по model-ID, без выбора по длине промпта/контексту
   («matrix» в llama-swap — это новый движок эвикции на множествах
   (`sets`/`evict_costs`), а не роутинг по размеру запроса). Для задачи
   «одна модель в VRAM» группа из двух моделей с `swap: true, exclusive: true`
   эквивалентна `--models-max 1`. Swap-latency budget — `healthCheckTimeout`
   (в репо 300 c), eviction тоже ждёт остановки до этого таймаута.

3. Рекомендация для этого репозитория (2x RTX 5070 Ti 16 GB, дисплей на GPU1,
   одна модель в VRAM, авто-переключение по первому запросу): оба варианта
   формально удовлетворяют, но для llama.cpp router mode надо перенести
   kernel-args из `llama/docker-compose.yaml` в INI (нарушает текущий договор
   AGENTS.md «параметры ядра только в llama/config.yaml»), а llama-swap —
   достаточно добавить `routing`-секцию в существующий `llama/config.yaml`
   (и, для реального освобождения VRAM, перенести llama-server в `cmd` — это
   уже расписанный в 0003 «Вариант B»). Драфты конфигов — в разделе
   «Практические рекомендации».

## Часть A — llama.cpp router mode / models-preset

### A.1 Что это и как включить

Router mode активируется запуском `llama-server` **без** `--model`
(tools/server/README.md:1646-1650). Роутер-процесс сам ничего не инференсит:
он спавнит дочерние инстансы `llama-server` как субпроцессы и проксирует
запросы (`server-models.cpp:979-1007`, `server-models.h:44-50` — адрес ребёнка
жёстко `127.0.0.1`, `server-models.cpp:47-49`). Источники моделей — три
(README.md:1654-1657): кэш HF (`LLAMA_CACHE`), `--models-dir`, `--models-preset`.
Смешивать можно: пресеты из всех источников каскадируются
(`server-models.cpp:504-552`; `common/preset.cpp:477-501`).

### A.2 Флаги

| Флаг | Дефолт | Семантика | Источник |
|---|---|---|---|
| `--models-preset PATH` | disabled | путь к INI с пресетами моделей роутера (env `LLAMA_ARG_MODELS_PRESET`) | README.md:223; `common/common.h:667` |
| `--models-max N` | `4` (0 = без лимита) | максимум одновременно загруженных моделей | README.md:224; `common/common.h:668`; `common/arg.cpp:3598-3601` |
| `--models-autoload / --no-models-autoload` | enabled | авто-загрузка модели по запросу; отключается глобально или per-request `?autoload=true\|false` | README.md:225,1787; `server-models.cpp:1757-1783` |
| `--models-dir PATH` | disabled | каталог с GGUF (mmproj/мультишард — подкаталоги, имена-префиксы `mmproj`, `mtp-`/`dspark-`/`dflash-`) | README.md:222,1667-1693; `common/preset.cpp:387-463` |
| `-a, --alias STRING` | — | алиасы model-ID (comma-separated); в router mode инжектится в ребёнка из пресета, у роутера вырезается | README.md:184,1752; `common/arg.cpp:2966-2978`; `server-models.cpp:445-450` |
| `--kv-unified` / `--no-kv-unified` | enabled, если число слотов auto | единый KV-буфер на все последовательности — обычный флаг ребёнка, НЕ роутерный | README.md:167; `common/arg.cpp:1714-1720` |
| `--cache-idle-slots` | enabled (требует `--cache-ram`) | сохранять idle-слоты в prompt-cache при новой задаче и очищать их при unified KV | README.md:168; `common/arg.cpp` |
| `--cache-reuse N` | `0` | мин. размер чанка для переиспользования KV-сдвигом (требует prompt caching) | README.md:216 |
| `--sleep-idle-seconds N` | `-1` (выкл) | сон после N секунд простоя; работает и в single-, и в multi-model режиме | README.md:239,2061-2072 |
| `-dev, --device dev1,dev2` | — | список устройств для offload (ребёнок; per-model в INI через `device`) | README.md:80; `common/arg.cpp:2699` |

Флагов `--model-alias`, `--aliases`, `--swap-timeout` в llama.cpp **нет**:
алиас — только `-a/--alias` (comma-separated), отдельного таймаута swap не
существует (есть per-model `stop-timeout` в пресете, см. A.4). Проверено
grep'ом по `common/arg.cpp` и README: 0 совпадений.

Важно для интерпретации батника: `--kv-unified`, `--cache-idle-slots`,
`--cache-reuse`, `--sleep-idle-seconds`, `-np`, `--device` — это обычные
аргументы сервера, которые роутер **наследует** (README.md:1701: «model
instances inherit both command line arguments and environment variables from
the router server») и накладывает поверх пресета каждой модели
(`server-models.cpp:548-552`: `preset.merge(base_preset)`). То есть в
`run_server.bat` они задают дефолт для всех детей, а `models.ini` их
переопределяет per-model.

### A.3 Авто-переключение по первому запросу

Поток запроса (POST: `server-models.cpp:1870-1899`; GET: `1856-1868`):

1. `router_validate_model` — имя из поля `model` (или query-параметра)
   резолвится в canonical name (в т.ч. через алиасы `--alias`);
   `--no-models-autoload` + не-running → 400 «model is not loaded»
   (`server-models.cpp:1757-1774`).
2. `ensure_model_ready` (`server-models.cpp:1325-1444`):
   - модель READY → проксировать сразу; SLEEPING → проксировать (ребёнок
     проснётся сам, `server-models.cpp:1333-1335`);
   - UNLOADED и есть слот → `load(name)` (спавн ребёнка, синхронно до ready);
   - слотов нет → встать в очередь (`sched->join`); если есть
     простаивающая модель — сразу `unload(victim)` («evicting idle LRU ...»,
     `server-models.cpp:1354-1367`), иначе ждать.
3. Выбор жертвы — `pick_victim` (`server-models.cpp:83-101`): LRU по
   `last_used`, **исключая занятые** (`req_count != 0`) и не-ready. Занятая
   модель не выгружается посреди запроса: запрос к B ждёт, а когда A
   завершает работу, `on_model_idle` отдаёт её слот очереди
   (`server-models.cpp:1492-1498, 172-215`).
4. `load` перед спавном вызывает `unload_lru` (LRU-эвикция при достижении
   лимита, `server-models.cpp:897-921`) и под локом перепроверяет
   `count_active >= models_max` → «model limit reached, try again later»
   (`server-models.cpp:951-965`).

`--models-max 1` гарантирует: **не более одного** ребёнка в состоянии
LOADED/LOADING/SLEEPING в любой момент (проверка под mutex при каждом load
плюс очередь). Swap всегда stop-then-start: `unload_lru` ждёт статуса UNLOADED
(`server-models.cpp:914-919`), очередь ждёт слота. Выгрузка — graceful: ребёнку
пишется `cmd_router_to_child:exit` в stdin, ожидание до `stop-timeout`
(дефолт `DEFAULT_STOP_TIMEOUT = 10` с, `server-models.cpp:42`; per-model
переопределяется ключом `stop-timeout` пресета), затем force-kill
(`server-models.cpp:1039-1069`). Ребёнок при завершении освобождает VRAM —
подтверждено кодом сна: `destroy()` уничтожает контекст и модель
(`server-context.cpp:898-910`), а это тот же механизм, что на stop.

Поведение подтверждено юнит-тестами роутера
(`tools/server/tests/unit/test_router.py:119-145` — `test_router_models_max_evicts_lru`;
`test_router_queue_does_not_evict_busy_model`).

### A.4 Формат INI-пресета

Парсер: `common/preset.cpp:170-249` (PEG-грамматика: секции `[ident]`,
`key = value`, комментарии `;`/`#`, ключи `[a-zA-Z_][a-zA-Z0-9_.-]*`).
Загрузка: `common/preset.cpp:285-348`.

- `version = 1` — ключ зарезервирован и **игнорируется**
  (`preset.cpp:304-307`: `if (key == "version") continue`). Писать не
  обязательно.
- Секция `[*]` — глобальные настройки, наследуются всеми пресетами; per-model
  ключ перекрывает глобальный (`preset.cpp:339-344`, затем каскад
  `cascade()` — `preset.cpp:492-501`). Прецедент CLI > секция модели >
  `[*]` (README.md:1754-1758).
- Имя секции — это model-ID (для HF-моделей вида `repo:quant`). Если в
  конфиге уже есть модель с таким именем (кэш/`--models-dir`), ключи секции
  сливаются с её пресетом; иначе требуется ключ `model` (путь) или `hf`
  (README.md:1728-1750). Тэг после `:` канонизируется (`preset.cpp:292-300`).
- Ключи — это **любые** аргументы llama-server без ведущих `--` (полные,
  короткие `c`, `ngl` и env-имена `LLAMA_ARG_*` взаимозаменяемы),
  README.md:1713-1715. Неизвестный ключ → ошибка
  (`preset.cpp:317-332`). Именно поэтому в `models.ini` валидны
  `ctx-size`, `tensor-split`, `split-mode`, `device`, `device-draft`,
  `spec-type`, `spec-ngram-mod-*`, `spec-draft-n-max`, `model-draft`,
  `fa`, `n-gpu-layers`, `cache-type-k/v`, `temp`, `top-p`, `top-k`, `min-p`,
  `repeat-penalty`, `reasoning-budget`, `main-gpu`, `mmproj`,
  `no-mmproj-offload` — все это обычные флаги llama-server.
- Специальные (только пресет, не CLI): `load-on-startup` (bool; автозагрузка
  при старте роутера) и `stop-timeout` (секунды graceful-shutdown до
  force-kill; дефолт 10)
  (`common/arg.cpp:4644-4660`; README.md:1759-1761).
- `--models-preset` **не требует** `--models-max`: лимит по умолчанию 4
  (`common/common.h:668`). Обратное ограничение есть: число моделей с
  `load-on-startup` не должно превышать `--models-max` — иначе ошибка при
  старте (`server-models.cpp:642-646`).
- Router-контролируемые аргументы у детей вырезаются: SSL, api-key,
  `--models-dir/max/preset/autoload`, а при старте детей — `model`, `mmproj`,
  `alias`, `hf` (заменяются на инжект `--host 127.0.0.1 --port <free>
  --alias <name>`, `server-models.cpp:300-318, 359-383`).

### A.5 Эндпоинты роутера

Маршруты: `server.cpp:225-231` (роутер-блок), `/health` — `server.cpp:233`,
`GET /models`/`/v1/models` — `server.cpp:238-239`.

| Эндпоинт | Что делает | Источник |
|---|---|---|
| `GET /models` (и `/v1/models`) | список всех моделей со статусом `unloaded/loading/loaded/sleeping/downloading/failed`, аргументами инстанса, `aliases`, `preset`, `can_remove` | README.md:1789-1872; `server-models.cpp:1924-1999` |
| `POST /models/load` | принудительно загрузить (`{"model": "..."}`); уже running → 400 | README.md:1874-1894; `server-models.cpp:1901-1912` |
| `POST /models/unload` | выгрузить модель | README.md:1896-1914; `server-models.cpp` |
| `GET /models/sse` | события `model_status` (в т.ч. прогресс загрузки), `models_reload` | README.md:1916-1987 |
| `POST /models` / `DELETE /models` | скачать модель в кэш / удалить из кэша (только кэш, не пресеты) | README.md:1989-2043 |
| `GET /health` | публичный health роутера | `server.cpp:233` |
| `GET /props?model=...` | в router mode — `role: router`, `max_instances` (= `--models-max`), `models_autoload`; с `?model=` — пропуск к ребёнку | `server-models.cpp:1829-1854` |

`POST /models/swap` и `/models/health` **не существуют** (проверено по
регистрации маршрутов `server.cpp:225-231` — только load/unload/sse).

### A.6 Платформы и известные оговорки

- Кроссплатформенность: router mode требует `LLAMA_SUBPROCESS`, по умолчанию
  **ON** на Linux/Windows/macOS, OFF только iOS/Android/WASM
  (`CMakeLists.txt:105-111`; `common/subproc.cpp:3-8`). Windows-батник — не
  особенность режима, тот же режим работает в Linux-контейнере.
- `--sleep-idle-seconds` в multi-model режиме: ребёнок засыпает (статус
  `sleeping`), процесс живёт, но модель+KV выгружены из памяти
  (`server-queue.cpp:266-345`; `server-context.cpp:898-910` — `destroy()`;
  README.md:2063-2072). Новый запрос будит ребёнка (холодная загрузка).
  `GET /health`, `/props`, `/models` не считаются активностью (README.md:2069-2072).
- «Нормальный» путь с OOM-reтry при pipeline-parallel (см. AGENTS.md про
  qwen3.8) к роутеру отношения не имеет — это свойство загрузки llama.cpp.
- MTP/vision: ограничений для preset-режима в исходниках нет; `model-draft`,
  `mmproj`, `no-mmproj-offload` проходят как обычные ключи. Проверено grep по
  README/коду: отдельных предупреждений «несовместимо с router mode» нет.
- Оговорка: конфиг меняется только рестартом роутера; `GET /models?reload=1`
  перечитает пресеты и **выгрузит** запущенные модели, чей пресет изменился
  (`server-models.cpp:653-675`) — т.е. reload = выгрузка всего.
- `--fit off` и пр. — обычные флаги ребёнка; в INI задаются per-model.

### A.7 Когда появилось

- Router mode (мульти-модельный API): PR #17470, merged 2025-12-01.
- INI-пресеты (`--models-preset`): PR #17859, merged 2025-12-10
  (docs/preset.md:5 прямо ссылается на #17859).
- Глобальная секция `[*]` и каскад источников: PR #18161 (commit
  `98c1c7a7bf`, 2025-12-19).
- LRU-планировщик и очередь (текущее поведение eviction): PR #26572,
  2026-08-07.
- Сон: PR #18228. Subprocess-обёртка: PR #26102.
- По датам релизов (GitHub API, b-теги): b7200 = 2025-11-29, b7400 =
  2025-12-14 → router+presets впервые появились в сборках между b7200 и b7400
  (декабрь 2025). Точный первый тег не проверен (rate-limit API; PR-номер +
  дата слияния — точные факты).

## Часть B — llama-swap: groups и matrix

Базовый жизненный цикл (ttl/unloadTimeout/healthCheckTimeout, автостарт,
эндпоинты) — в 0003. Здесь — только то, что 0003 оставил открытым: семантика
eviction между моделями.

### B.1 Механизм «одна модель в VRAM»: groups

Механизм один — членство в группах (ключ `evict_models` **не существует**:
grep по всему репо — 0 совпадений). Движок выбирается
`routing.router.use: group|matrix` (дефолт `group`)
(config.example.yaml:518-523; config-schema.json `properties/routing`).

Группа (`config.example.yaml:537-587`; schema `definitions/groupsConfig`):

| Ключ группы | Дефолт | Семантика |
|---|---|---|
| `swap` | `true` | внутри группы: `true` — только одна модель running; `false` — все вместе |
| `exclusive` | `true` | для других групп: `true` — запуск члена выгружает все остальные группы; `false` — не трогает |
| `persistent` | `false` | другие группы не могут выгрузить членов этой группы |
| `members` | required | model-ID из `models`; модель может быть только в одной группе (`group.go:16-24` — ошибка при дубликате) |

Eviction-логика `groupSwapper.EvictionFor`
(`internal/router/group.go:59-104`):
- запрос к B, в группе уже running A, `swap: true` → **A выгружается
  безусловно**, независимо от `ttl`. `ttl` (и `globalTTL`) управляет только
  автовыгрузкой по простою **без** запроса (см. 0003, `process_command.go:306-325`).
- `swap: false` → члены живут вместе;
- cross-group: при `exclusive: true` цели выгружаются все другие группы
  (кроме `persistent`); при `exclusive: false` — не трогаются (gotcha
  совместимости, `group.go:88-96`).

Единственная группа `{ornith-9b, qwen3.8-27b}` с `swap: true, exclusive: true`
— точный аналог `--models-max 1`: запрос к B эвиктит A до старта B
(`doSwap` — stop всех `toStop`, потом `EnsureReady`, `base.go:243-276`),
т.е. VRAM между ними свободна. Если A занята in-flight запросом, FIFO
откладывает swap: шаг (5) «would evict a busy process — queue until it
drains» (`scheduler/fifo.go:126-135, 516-520`).

### B.2 «Matrix» — не роутинг по контексту

В llama-swap «matrix» — это **второй движок эвикции**, а не выбор инстанса по
длине промпта (grep по router/докам: никакой логики context/prompt-size
нет — 0 совпадений). Роутинг строго по model-ID из запроса
(`scheduler/fifo.go:82-98`; резолв model-ID — в 0003).

Matrix-движок (`config.example.yaml:589-656`; schema `matrixConfig`;
`internal/router/matrix.go`; `internal/matrix/program.go:222-288`):
- `vars` — короткие имена моделей; `sets` — выражения `&` (AND), `|` (OR),
  `()` (группировка), `+ref` (вставка другого сета), каждое выражение
  разворачивается в конкретные наборы допустимых комбинаций;
- `evict_costs` — относительная цена потери running-модели (дефолт 1);
- решатель: для запроса X выбирает набор, содержащий X, с минимальной суммой
  cost выгружаемых моделей; выгружает ровно то, что вне набора
  (`program.go:222-288`); модель, не входящая ни в один сет, может
  работать только одна (`program.go:268-272` — Evict = все running);
- «subset semantics»: набор `[a,b]` разрешает подмножества; вне набора не
  прелоадится ничего (config.example.yaml:603-606);
- конфиг обязан использовать либо `groups`, либо `matrix`, не оба
  (schema `matrixConfig.description`).

Для «только одна модель» matrix эквивалентен сета `ornith: "o", qwen: "q"`
и `sets: { alone: "o | q" }` → разворачивается в `[o], [q]` — каждая модель
только сама с собой.

### B.3 Eviction mid-request и бюджет swap

- In-flight запросы при **ручной** выгрузке не ждут (0003, base.go:387-390).
  При **swap-eviction** FIFO ждёт завершения in-flight запросов жертвы
  (шаг 5, fifo.go:516-520) — разница важная: эвикция по запросу дожидается
  drain, потом stop-then-start.
- Бюджет одной swap-операции: и stop жертвы, и start цели идут с
  `healthCheckTimeout` (`base.go:243-265`; дефолт 120 с, в репо 300 —
  llama/config.yaml:3; см. 0003). То есть худший случай swap ≈
  healthCheckTimeout на stop + healthCheckTimeout на start.

## Часть C — сравнение и рекомендация

### C.1 Сравнительная таблица

| Критерий | llama.cpp router (`--models-preset` + `--models-max 1`) | llama-swap (группа `swap: true`) |
|---|---|---|
| Авто-свитч по первому запросу | да, `--models-autoload` (дефолт on); per-request `?autoload` | да, безусловно (0003) |
| Гарантия «одна модель в VRAM» | да, `--models-max 1`: максимум один running-инстанс; busy-модель не эвиктится, запрос ждёт | да, группа `swap: true`; busy-модель тоже не трогается (FIFO шаг 5) |
| Политика эвикции | LRU по `last_used`, только idle-модели; очередь при занятости | статично по конфигу группы (все члены с `swap:true`); матрица — min evict-cost |
| Порядок swap | stop-then-start (ждёт UNLOADED) | stop-then-start (`doSwap`) |
| KV-cache между моделями | нет — каждый ребёнок свой процесс; только per-child `--cache-reuse`/`--cache-idle-slots`/`--cache-ram` | нет — каждый upstream свой процесс; то же |
| Per-model sampling/ctx | да, любые ключи в INI (temp, ctx-size, tensor-split, spec-*) | да, через `cmd` каждой модели + filters/stripParams/setParamsByID (llama/config.yaml) |
| Дочерний процесс | свой `llama-server` на `127.0.0.1:<free port>`, alias = model-ID | свой upstream per model, `${PORT}` макрос |
| Оба GPU (tensor-split) | да, `tensor-split`, `device` в INI | да, в `cmd` |
| Swap latency | stop (≤10 с, `stop-timeout`) + cold start (qwen ~40-60 с) | stop до `healthCheckTimeout` (300 с в репо) + cold start |
| Сон вместо выгрузки | `--sleep-idle-seconds`: VRAM освобождается, процесс жив, wake = reload | нет аналога для llama.cpp (vllm-wrapper только для vLLM, см. 0003) |
| Linux | да, subprocess ON по умолчанию | да (это Go-сервис) |
| Конфиг | INI-пресеты (крон: `[*]` + секции) | YAML `routing.router.settings.groups` / `matrix` |
| Контроль эвикции runtime | авто (LRU), плюс POST /models/load|unload | авто (группы), плюс POST /api/models/unload[/{id}] |
| Рестарт при смене конфига | требуется | требуется (в репо без `--watch-config`; reload выгружает всё — 0003) |

### C.2 Рекомендация для этого репозитория

Ограничения: 2x RTX 5070 Ti 16 GB, графическая сессия на GPU1 (нужен запас
≥512 MiB), в VRAM помещается только одна модель (qwen ~15.9 GiB веса + KV
~11.4 GiB), авто-переключение по первому запросу, `--tensor-split 52,48` для
qwen и оба GPU для ornith.

Оба варианта формально подходят. Ограничения каждого:

- **llama.cpp router mode** даёт всё из коробки (LRU-эвикция, очередь,
  stop-then-start, sleep-режим), но требует переноса параметров ядра из
  `llama/docker-compose.yaml` + `llama/config.yaml` в INI — прямой конфликт с
  договором AGENTS.md («параметры ядра — только в llama/config.yaml»), плюс
  уход от llama-swap (потеря setParamsByID-режимов, которыми сейчас
  управляются 5 режимов qwen/ornith). Алиасы режимов в router mode можно
  частично воспроизвести: model-ID = имя секции, а «режимы» — отдельные
  секции с разным sampling на одном файле модели (это ровно тот приём, что
  в Windows-`models.ini`: `_Qwen3.6-27B--128k--8XL--NMp` и `--FST` — разные
  секции на одном GGUF; в router mode алиас режима = имя секции + `--alias`).
- **llama-swap** — минимальное изменение текущего конфига: добавить секцию
  `routing` (группа из двух моделей). Eviction-политика проще (не LRU, а
  «все члены группы»), но для двух моделей это эквивалентно. Реального
  освобождения VRAM не будет, пока `cmd: "sleep infinity"` (0003): llama-swap
  убьёт заглушку, а llama-server продолжит держать модель. Чтобы получить
  настоящий on/off — «Вариант B» из 0003 (llama-server в `cmd`).

Драфты (НЕ применяются к репозиторию):

```ini
; Драфт A: llama.cpp router mode — models.ini (аналог run_server.bat для Linux)
; Запуск: llama-server --models-preset /etc/llama/models.ini --models-max 1 \
;   --host 0.0.0.0 --port 8080 --kv-unified --cache-idle-slots --cache-reuse 256 \
;   --cache-ram 65536 --sleep-idle-seconds 3600 -np 2 --jinja
version = 1

[*]
; глобальные настройки для всех моделей
fa = true
n-gpu-layers = -1
cache-type-k = q8_0
cache-type-v = q8_0
split-mode = tensor
fit = off
batch-size = 2048
ubatch-size = 512
threads = 8
reasoning = on

[ornith-9b]
model = /models/ornith-9b-Q8_0.gguf
alias = ornith-9b
ctx-size = 262144
tensor-split = 52,48
load-on-startup = false
stop-timeout = 20

[qwen3.8-27b]
model = /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf
alias = qwen3.8
ctx-size = 262144
tensor-split = 52,48
load-on-startup = true   ; аналог hooks.on_startup.preload
stop-timeout = 20
```

```yaml
# Драфт B: llama-swap — только routing-секция поверх текущего llama/config.yaml
# (для настоящего on/off нужен также перенос llama-server в cmd — Вариант B из 0003)
routing:
  router:
    use: group
    settings:
      groups:
        # одна группа = одна модель в VRAM (swap: true выгружает члена
        # группы при запросе другого; exclusive неважен — группа одна)
        vram-single:
          swap: true
          exclusive: true
          members:
            - ornith-9b
            - qwen3.8-27b
```

## Подтверждено vs спекуляция

Подтверждено первичными источниками:

- llama.cpp: все флаги, дефолты и семантика из таблицы A.2 (README.md
  строки 167-168, 184, 216, 222-225, 239; `common/arg.cpp`; `common/common.h:667-668`).
- Авто-загрузка, очередь, LRU-эвикция, «busy не трогаем» — код
  `server-models.cpp:83-101, 172-215, 897-965, 1325-1444` + юнит-тесты
  `test_router.py:119-145`.
- Формат INI и `version = 1` (игнорируется), `[*]`, наследование, любой ключ
  = аргумент llama-server, `load-on-startup`/`stop-timeout`, отсутствие
  требования `--models-max` — `common/preset.cpp:170-348, 477-501`,
  `common/arg.cpp:4644-4660`, README.md:1705-1761.
- Эндпоинты (в т.ч. отсутствие `/models/swap`, `/models/health`) —
  `server.cpp:225-239`, README.md:1789-2043.
- Кроссплатформенность — `CMakeLists.txt:105-111`, `common/subproc.cpp`.
- Sleep освобождает модель+KV при живом процессе — `server-context.cpp:898-910`,
  `server-queue.cpp:266-345`, README.md:2061-2072.
- История: PR #17470 (2025-12-01), #17859 (2025-12-10), #18161 (2025-12-19),
  #26572 (2026-08-07) — GitHub API (message/date коммитов).
- llama-swap: семантика `swap`/`exclusive`/`persistent`/`members`, отсутствие
  `evict_models`, «либо groups, либо matrix» — `config.example.yaml:505-656`,
  `config-schema.json` (`groupsConfig`, `matrixConfig`),
  `internal/router/group.go:59-104`, `internal/router/matrix.go`,
  `internal/matrix/program.go:222-288`.
- Eviction безусловен (не зависит от ttl; ttl — только idle-автовыгрузка) —
  `group.go:59-104` + `scheduler/fifo.go:90-141` (fast-path/queue/swap),
  `base.go:243-276` (stop-then-start с healthCheckTimeout).
- Маршрутизация строго по model-ID; никакой выборки по длине промпта/контексту
  не существует (grep по llama-swap router + docs: 0 совпадений).
- In-flight при swap-eviction: FIFO ждёт drain жертвы (`fifo.go:516-520`);
  при ручной выгрузке не ждёт (0003).
- `--model-alias`/`--aliases`/`--swap-timeout` в llama.cpp отсутствуют
  (grep по `common/arg.cpp` + README: 0 совпадений; есть только `-a, --alias`).

Спекуляция / не подтверждено:

- Точный первый b-тег релиза с router/presets: определен только диапазон
  b7200 (2025-11-29) … b7400 (2025-12-14) — API упёрся в rate-limit;
  PR-номер и дата слияния — точные факты.
- Реальный swap-latency на этой машине (stop qwen + cold-start ornith) не
  замерен; оценка 40-60 с для qwen — из AGENTS.md (холодный старт).
- Поведение llama-server при force-kill (`stop-timeout` истекает) —
  освобождает ли VRAM мгновенно — не проверялось (свойство ОС/драйвера).
- Совместимость MTP-моделей с router mode на этой машине не проверялась:
  в исходниках ограничений нет, но MTP+draft на двух GPU в роутере — не
  тестированный сценарий.
- «Пи»-нагрузка: `--models-max 1` + два параллельных запроса к разным
  моделям — очередь, но время ожидания второго не замерялось.

## Источники

- llama.cpp (клон `/tmp/opencode/llama.cpp`, commit
  `058df671b214a7447f33b3e962501175b3a752f4`, 2026-08-17):
  - `tools/server/README.md` — раздел «Using multiple models» (1642-2043),
    таблица флагов (167-168, 184, 216, 222-225, 239, 80),
    «Sleeping on Idle» (2061-2072);
  - `tools/server/server-models.cpp` — LRU-планировщик (73-101, 172-215),
    unload_lru (897-921), load (923-965), unload (1128-1153),
    ensure_model_ready (1325-1444), proxy_request/on_model_idle
    (1446-1498), роутинг и autoload (1757-1899), эндпоинты (1901-1999),
    инжект host/port/alias (359-383), загрузка пресетов (504-552);
  - `tools/server/server.cpp` — маршруты (225-231, 246-250);
  - `tools/server/server-context.cpp` — sleep = destroy/reload (898-910);
  - `tools/server/server-queue.cpp` — sleep-цикл (266-345);
  - `common/preset.cpp` — парсер INI (170-249), load_from_ini (285-348),
    cascade (477-501), load_from_models_dir (387-463);
  - `common/arg.cpp` — флаги (alias 2966-2978, kv-unified 1714-1720,
    cache-idle-slots, cache-reuse, sleep-idle-seconds 3751, models-max 3598,
    preset-only опции 4644-4660); `common/arg.h` (14-15);
  - `common/common.h` — дефолты (667-670); `common/subproc.cpp`; `CMakeLists.txt` (105-111);
  - `docs/preset.md` (PR #17859); `tools/server/tests/unit/test_router.py` (119-145);
  - GitHub API: коммиты/PR #17470, #17859, #18161, #26572, #18228, #26102;
    даты b-тегов b7200/b7400.
- llama-swap (клон `/tmp/opencode/llama-swap`, commit
  `08f1076cb777e787eba3f57170350aa09513341a`, 2026-08-16 — тот же, что в 0003):
  - `config.example.yaml` — routing/groups/matrix (505-656);
  - `config-schema.json` — `groupsConfig`, `matrixConfig`, `routing`;
  - `docs/configuration.md` — hot swap и `${PORT}`/matrix (13-25, 79);
  - `internal/router/group.go` — единственность группы, EvictionFor (16-24, 59-104);
  - `internal/router/matrix.go`, `internal/router/matrix_solver.go`,
    `internal/matrix/program.go` — Solve (222-288);
  - `internal/router/scheduler/fifo.go` — шаги OnRequest (82-141),
    conflictsWithInFlight (516-520);
  - `internal/router/base.go` — doSwap: stop-then-start, healthCheckTimeout (243-276);
  - README.md — API и ключи (строки 44-67, 224-225).
- Предыдущее исследование: `docs/research/0003-llama-swap-model-toggle.md`.
- Локальные файлы: `docs/llama-config/run_server.bat`,
  `docs/llama-config/config/models.ini`, `llama/config.yaml`, AGENTS.md.