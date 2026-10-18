# 0013 — Контракты backend'ов: что делает сервер с параметрами клиента

Дата: 2026-10-17. Исследование по тикету
`.scratch/llama-swap-orchestrator/issues/03-backend-request-contracts.md`.

Вопрос тикета: что произойдёт с reasoning- и sampling-параметрами, которые
клиент шлёт в `/v1/chat/completions`, если llama-swap **перестанет** их вырезать
(`stripParams` и `setParamsByID` убраны, `llama/config.yaml:51-151`,
`ninfer/config.yaml:57-97`)? Достижимо ли «у сервера нет мнения» на каждом из
backend'ов?

## Что проверяли и на чём

| Артефакт | Источник | Версия |
|---|---|---|
| llama.cpp | локальный репозиторий `../llama.cpp` | `62318cd57dc63900ecb153272c0b10f78550855d` (2026-10-17, `git pull` перед работой; до этого отставал на 785 коммитов) |
| Модель llama-профиля | `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf` — embedded chat template | — |
| NInfer | образ `llm-server/ninfer-tp2:v0.4.6`, бинарь `/opt/ninfer/bin/ninfer-serve` | форк `ValerioDolci/ninfer-tp2` @ `47d47864b9e903ab7f800e7c128b7e300230ec00` |
| NInfer docs | `https://raw.githubusercontent.com/ValerioDolci/ninfer-tp2/47d47864.../docs/serving.md` | тот же коммит, что и `--help` бинаря (совпадение флагов/описаний) |
| NInfer embedded template | `.../tools/chat_templates/qwen3_8.jinja` (built from artifact) | тот же коммит |
| NInfer validation strings | `strings` бинаря из контейнера | — |
| vLLM | локальный образ `vllm/vllm-openai:qwen38` (`4a2f33a88422`), профиль `vllm` | `0.1.dev19754+g3a0914114` |
| vLLM template | `/opt/models/Qwen3.8-27B-NVFP4/chat_template.jinja` + `generation_config.json` | transformers 5.14.1 |
| llama-swap | локальный репозиторий `../llama-swap` | `a2796fb` |

Все исходники, `--help`, `strings`-grep, `serving.md`-фрагменты и шаблоны
сохранены в
`.scratch/llama-swap-orchestrator/assets/03-backend-contracts/`
(структура — `README.md` в этом каталоге).

Исследование статическое (чтение исходников, `--help`, `strings`, `docker
ps`/`/v1/models`). Ни один контейнер не перезапускался и не переконфигурировался,
инференс-запросы не отправлялись. Ниже помечено, что требует живой проверки.

## Короткий ответ

1. **«У сервера нет мнения» в смысле «нет дефолтов» недостижимо.** У каждого
   backend'а есть неснимаемые дефолты, которые проявляются, когда клиент ничего
   не прислал: sampling-пресет, дефолт шаблона (`enable_thinking`,
   `reasoning_effort`), лимиты на `max_tokens`. Их нельзя «выключить» ни
   `stripParams`, ни отсутствием `setParamsByID` — это свойства движка.
2. **«Клиент владеет всем» достижимо технически**: все три backend'а принимают
   клиентские sampling-параметры и reasoning-поля и не отбрасывают их. Но это
   не безвредно: три разных контракта расходятся по словарю допустимых значений,
   по поведению на мусор и по семантике одинаково названных полей
   (`top_k: 0`, `repetition_penalty`, `reasoning_effort` со значениями
   `high`/`minimal`/`max`). Подробности — раздел «Параметры, нельзя передавать
   всем трём».
3. **llama-swap-слой сейчас несёт функцию однородного контракта.** Убрав
   `stripParams`/`setParamsByID`, мы не просто «дадим клиенту то, что он хочет»,
   а заставим клиентов знать три разных контракта (или писать shim). Это и есть
   содержание тикета 02/03: единый endpoint ≠ единый контракт.
4. **Разрывы, которые нельзя закрыть одной конфигурацией backend'а:**
   - `reasoning_effort="high"`: работает в llama.cpp (шаблон фолдит
     `high→xhigh`) и NInfer (движок фолдит), но в vLLM валидный литерал
     `high` уходит в шаблон, который `high` не принимает → **400**.
   - невалидный `reasoning_effort`: в NInfer и vLLM → **400**, в llama.cpp →
     **500** (исключение шаблона трактуется как серверная ошибка).
   - `top_k: 0`: в llama.cpp и vLLM — «выключить» (весь словарь / всё
     отключено), в NInfer — **выбрать top-20** (`--help`: «0..20; zero selects
     the top-20 cap»).
   - `repetition_penalty`: llama.cpp знает имя `repeat_penalty`, NInfer
     принимает `repetition_penalty` **только в значении 1**, vLLM принимает
     любое > 0.
5. **Голый ID после снятия фильтров меняет поведение.** `qwen3.8-27b` в llama-
   и ninfer-профилях сегодня — это non-thinking с пресетом `0.7/0.80/20/…`.
   Без `setParamsByID` голый ID на всех трёх backend'ах превращается в
   **thinking + effort xhigh** (дефолт шаблона) и в собственный sampling-пресет
   движка. Разница — в таблице «Голый ID: до и после».

## Голый ID: до и после

`llama` и `ninfer` профили сегодня задают режим через `setParamsByID` по
алиасу; `vllm` профиля фильтров не имеет вообще
(`vllm/config.yaml:1-32`, в нём нет `filters:`).

| Backend | Сегодня (`qwen3.8-27b` + фильтры) | Без `stripParams`/`setParamsByID` |
|---|---|---|
| llama.cpp | temp 0.7, top_p 0.8, top_k 20, min_p 0.0, presence 1.5, repeat 1.05, `enable_thinking: false` → thinking **off** (`llama/config.yaml:56-67`) | temp 0.80, top_p 0.95, top_k 40, min_p 0.05, presence 0, freq 0, repeat 1.0, seed случайный (`common/common.h:233-245`) + thinking **on** (`--reasoning on`, `llama/config.yaml:41`) + effort **xhigh** (дефолт шаблона) |
| NInfer | `reasoning_effort: "none"` → thinking **off**, пресет `0.7/0.80/20/0/1.5` (`ninfer/config.yaml:65-66`, `docs/serving.md:842-847`) | thinking **on** (серверный дефолт `--no-thinking` off, `docs/serving.md:823`), effort **xhigh** (дефолт шаблона), пресет `1.0/0.95/20/0/0`, `max_tokens` = `--default-max-tokens 16384` |
| vLLM | без фильтров — уже как «без фильтров» | thinking **on**, effort **xhigh** (дефолт `chat_template.jinja:47`), temp 1.0, top_p 0.95, top_k 20 (`generation-config: auto` + `generation_config.json`), `max_tokens` = `49152 − prompt` |

Вывод: для «голого ID» снятие фильтров **не сохраняет** текущее поведение —
оно меняется с non-thinking на thinking/xhigh в двух профилях. Чтобы сохранить
текущее поведение «клиент ничего не решает», это нужно явно выставить на
стороне движка (`--reasoning off` / `--no-thinking` / `--default-chat-template-kwargs
'{"enable_thinking": false}'`) — то есть сервер обязан иметь мнение.

## 1. llama.cpp (профиль `llama`)

Путь запроса: `post_chat_completions` (`server-context.cpp:5557`) →
`oaicompat_chat_params_parse` (`server-common.cpp:1272-1489`: OAI-тело →
`llama_params` + `common_chat_templates_inputs`) → `eval_llama_cmpl_schema`
(`server-schema.cpp:467`, вызывается в `server-context.cpp:4937`), где
sampling-поля и читаются.

### Sampling

- Поля регистрируются схемой `tools/server/server-schema.cpp:88-145`:
  `top_k [0, INT32_MAX]`, `top_p [0,1]`, `min_p [0,1]`, `temperature [0, ∞)`,
  `repeat_penalty` без границ, `frequency_penalty`/`presence_penalty` без
  границ; мягкие границы (`set_limits`) у всех, жёсткие (`set_hard_limits`) —
  только у `repeat_last_n [0, INT32_MAX]` (`:88-145`).
- **Выход за границы не ошибка, а clamp** (кроме полей с `set_hard_limits`):
  `field_num::eval` → `std::max(min, std::min(max, value))`
  (`tools/server/server-schema.cpp:532-547`). То есть `temperature: -1`
  превращается в `0` (greedy), `top_p: 5` — в `1.0`.
- **Ошибки типа** — 400: `handle_with_catch` бросает
  `std::invalid_argument("Field '<name>': …")` (`:518-524`), `ex_wrapper`
  мапит `invalid_argument` → 400, прочие исключения → 500
  (`tools/server/server.cpp:55-88`).
- `null` у известного поля игнорируется («клиент просит серверный дефолт»):
  `has_value` (`:526-529`).
- **Имя `repeat_penalty`** — llama-специфичное (`server-schema.cpp:130`);
  OAI-имя `frequency_penalty` тоже читается, `repetition_penalty` — нет.

### Reasoning и шаблон

- `reasoning_effort` (top-level): `"none"` → `enable_thinking=false` и стирание
  kwarg; любое другое непустое значение кладётся в
  `chat_template_kwargs["reasoning_effort"]` **без валидации значения**
  (`tools/server/server-common.cpp:1421-1430`). Неверный тип поля через
  `json_value` **молча заменяется дефолтом** (лог-предупреждение, не 400):
  `tools/server/server-common.h:42-55`.
- `enable_thinking` читается **только** из `chat_template_kwargs`; строка
  вместо bool → `invalid_argument` → 400
  (`server-common.cpp:1411-1418`). CLI-дефолт: `--reasoning on` →
  `enable_reasoning=1` + `default_template_kwargs["enable_thinking"]="true"`
  (`common/arg.cpp:3710-3727`).
- `chat_template_kwargs` — **по-ключевой merge** поверх CLI-дефолтов, тело
  не заменяет объект целиком (`server-common.cpp:1404-1409`). CLI
  `--chat-template-kwargs` для `enable_thinking`/`preserve_reasoning`
  объявлен устаревшим (`common/arg.cpp:3560-3565`).
- `preserve_reasoning` (bool) из kwargs включает капы
  `preserve_thinking`/`clear_thinking`/`truncate_history_thinking`/`drop_thinking`
  в контексте шаблона (`common/chat.cpp:912-916`,
  `common/jinja/caps.cpp:17-23`). Поле `preserve_thinking` как таковое сервером
  не парсится — оно попадает в шаблон как обычная переменная, и официальный
  Qwen-шаблон его читает напрямую.
- `reasoning_effort` в шаблоне дополнительно устанавливает
  `reasoning_strength` (`common/jinja/caps.cpp:25-29`) — для шаблонов, которые
  используют это имя.
- **Невалидный effort → 500.** Шаблон бросает `raise_exception`, в
  llama.cpp это `raised_exception : std::exception` (не
  `invalid_argument`: `common/jinja/value.cpp:420-426`,
  `common/jinja/runtime.h:694`), `ex_wrapper` мапит это на **500**
  (`tools/server/server.cpp:60-66`).
- Неизвестные top-level поля тела игнорируются: `eval_llama_cmpl_schema`
  итерирует по зарегистрированным полям схемы, а не по телу
  (`server-schema.cpp:467-500`), а перед этим `oaicompat_chat_params_parse`
  копирует **все** «оставшиеся» ключи тела в `llama_params` — «This allows
  user to use llama.cpp-specific params like "mirostat", ... via OAI
  endpoint» (`server-common.cpp:1472-1479`). То есть неизвестные ключи
  доходят до схемы и просто никем не читаются.
- Имена `reasoning` и `reasoning-budget` из `setParamsByID` — это **флаги
  CLI**, а не поля тела (`common/arg.cpp:3710-3747`); тело-поле для бюджета
  называется `reasoning_budget_tokens` (принимается и под алиасом
  `thinking_budget_tokens`: `server-common.cpp:1442-1444`;
  `server-schema.cpp:335-337`).
  То, что сейчас проставляет llama-swap (`llama/config.yaml:64-65`), в тело
  запроса **инертно**. Включение thinking определяется не этим, а
  `chat_template_kwargs.enable_thinking` (плюс CLI `--reasoning on`).
- Дефолт шаблона (embedded GGUF, тот же, что у llama-профиля):
  `enable_thinking is undefined or true` → thinking on;
  `reasoning_effort|default('xhigh')`, `high`→`xhigh`, иначе
  `raise_exception` (assets, `gguf-embedded-chat-template.jinja:60-66`);
  `preserve_thinking is undefined or true` → думание всех turn'ов сохраняется
  (`:121`).

## 2. NInfer v0.4.6 (профиль `ninfer`)

Источники: `docs/serving.md` @ `47d47864`, `--help` бинаря, `strings` бинаря,
embedded `qwen3_8.jinja`.

### Sampling

- Chat Completions принимает `temperature`, `top_p`, presence/frequency
  penalties, `seed`; расширения `top_k` (`0..20`) и `min_p` (`0..1`);
  `n:1`; до 4 stop-строк (`docs/serving.md:109-128`).
- Диапазоны подтверждены таблицей Responses (`docs/serving.md:421-422`):
  `temperature` — «finite number in `[0,2]`», `top_p` — «finite in `[0,1]`».
  Для Chat таблицы диапазонов в документации нет; в бинаре строка
  `temperature must be in [0,2]` лежит рядом с Responses-полями
  (`max_output_tokens`, `max_tool_calls`, `service_tier`), а строка
  `temperature must be in [0,1]` — рядом с Anthropic `stop_sequences`
  (assets `ninfer/validation-strings.txt`). **Вывод: для Chat/Responses
  `[0,2]`, для Anthropic `[0,1]` — это выведение, а не прямая цитата; на
  живом сервере не проверялось.**
- Жёсткая валидация: `top_k must be in [0,20]`,
  `resolved top_k must be in [1,20]`, `min_p must be in [0,1]`,
  `presence_penalty must be in [-2,2]`, `frequency_penalty must be in [-2,2]`,
  `sampling parameters must be finite` (assets `ninfer/validation-strings.txt`).
  Мусор не clamp'ится, а отвечает **400** (`docs/serving.md:160-164`:
  «Malformed protocol values return field-specific HTTP 400 errors»).
- `repetition_penalty` принимается **только в значении 1**: «a non-neutral
  repetition_penalty requires a sampler transform that NInfer does not
  provide; only repetition_penalty=1 is accepted» (strings) и
  `docs/serving.md:156-157`.
- Пресеты движка выбираются по resolved thinking mode: Qwen3.8-27B thinking
  `1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5` (temp/top_p/top_k/min_p/
  presence penalty), frequency penalty 0; процессные флаги перекрывают
  дефолты, поля запроса перекрывают процессные флаги, `--greedy` наконец
  принуждает temp 0 (`docs/serving.md:842-847`).
- `null` у стандартных опций = «unspecified» (`docs/serving.md:202-205`).
- Неизвестные top-level поля игнорируются (`docs/serving.md:148`).
- Поля, поведение которых движок дать не может, **отклоняются** (JSON output,
  ненулевой `logit_bias`, `logprobs`, `strict:true`, named/required tool
  choice, `parallel_tool_calls:false` и т.д.), с указанием поля и кода
  (`docs/serving.md:134-142`). Это принципиальное отличие от
  «ignore-контракта» llama.cpp.

### Reasoning и шаблон

- `reasoning_effort` (top-level): `"none"` → thinking off; `high`, `max`,
  `adaptive` рендерятся как `xhigh`; `minimal` → `low`; `low`/`medium`/`xhigh`
  проходят как есть; **любое другое значение → HTTP 400**
  (`docs/serving.md:225-231`). В бинаре:
  «`reasoning_effort must be a string or null`», «`reasoning_effort must be
  one of none, minimal, low, medium, high, xhigh, max, or adaptive`».
- **Отсутствующий `reasoning_effort`** → шаблонный дефолт `xhigh` + thinking on
  (embedded `qwen3_8.jinja:52-55`, `docs/serving.md:233-235`).
- `enable_thinking` и `preserve_thinking` принимаются **и top-level, и** в
  `chat_template_kwargs` (`docs/serving.md:129-131`). Конфликт явного
  `enable_thinking` с effort → `conflicting_template_option`
  (`docs/serving.md:231`, strings). `preserve_thinking` обязан быть
  bool/null (`preserve_thinking must be a boolean or null`,
  `chat_template_kwargs.preserve_thinking must be a boolean or null`).
- `chat_template_kwargs` передаётся в шаблон как объект; значения,
  дублируемые типизированными полями, обязаны совпадать; **«Messages, tools,
  generation mode and tokenizer special tokens cannot be overridden through
  kwargs»** (`docs/serving.md:202-205`; в бинаре строка
  `chat_template_kwargs cannot override ` + `conflicting chat template
  parameter: `).
- Объект целиком в запросе — да, но конфликт-проверки меж-полей остаются:
  это именно «merge + валидация», а не слепая замена.
- `preserve_thinking: false` работает только по истории, пересланной клиентом
  (AGENTS.md, раздел «Профиль ninfer»; измерено в тикете 05/13).
- Бюджет thinking: серверный флаг `--default-thinking-budget`; в Chat нет
  типизированного поля бюджета (`docs/serving.md:207-213`). В Anthropic
  Messages есть `thinking:{type:"enabled",budget_tokens:N}`.
- `--no-thinking` / `--preserve-thinking` — серверные дефолты; поля запроса
  их перекрывают; unspecified берётся из шаблона
  (`docs/serving.md:233-235`, `:823-824`).
- Нет `/v1/completions` — только Chat Completions, Responses и Anthropic
  Messages (`docs/serving.md:55-69` — таблица endpoints).

## 3. vLLM (профиль `vllm`)

Версия образа `0.1.dev19754+g3a0914114` (`vllm/vllm-openai:qwen38`,
`4a2f33a88422`); все цитаты ниже — из **этого** образа, а не с `main`
(`main` сверен дополнительно, отличия отмечены).

### Схема запроса и «неизвестные»

- `ChatCompletionRequest` наследует `OpenAIBaseModel` с
  `model_config = ConfigDict(extra="allow")`
  (`vllm/entrypoints/openai/engine/protocol.py:31-33`) → **неизвестные
  top-level поля разрешены и игнорируются** (как и в NInfer Chat).
- `reasoning_effort: Literal["none","minimal","low","medium","high","xhigh","max"] | None`
  (`vllm/entrypoints/openai/chat_completion/protocol.py:244-256`). Значение
  вне списка → `RequestValidationError` → `validation_exception_handler` →
  **HTTP 400** (не 422): `vllm/entrypoints/serve/utils/server_utils.py:541`.
- Sampling-поля принимаются как есть: `temperature`, `top_p`, `top_k`,
  `min_p`, `frequency_penalty`, `presence_penalty`, `repetition_penalty`,
  `seed` (`protocol.py:217-268`). Валидация — в `SamplingParams`:
  `temperature` конечное, неотрицательное, `[0,2]`; `top_p` в `(0,1]`;
  `top_k` = 0 или ≥1; `min_p` в `[0,1]`; `presence_penalty`/`frequency_penalty`
  в `[-2,2]`; `repetition_penalty` конечное и >0
  (`vllm/sampling_params.py:515-581`). Любая ошибка → `VLLMValidationError` →
  **400** (`vllm/entrypoints/serve/utils/error_response.py:38-40`).
  **Нет clamp** — в отличие от llama.cpp.

### Reasoning и шаблон

- `build_chat_params` (`protocol.py:564-582`): `reasoning_effort` всегда
  кладётся в `extra_kwargs`, а если он задан и клиент **не** передал
  `enable_thinking`, то дополнительно вставляется
  `enable_thinking = (reasoning_effort != "none")`. Явный клиентский
  `enable_thinking` имеет приоритет (`protocol.py:580-582`).
- Значение `None` (поле не прислано) **отбрасывается** слиянием:
  `merge_kwargs(..., unset_values=(None, "auto"))`
  (`vllm/renderers/params.py:27-40`) — шаблон получает только явные значения,
  дефолт шаблона не затирается.
- В шаблон попадают только ключи, объявленные шаблоном или поддерживаемые
  `apply_chat_template` (`vllm/renderers/hf.py:633-662`).
- Дефолт шаблона модели: `reasoning_effort|default('xhigh')`, принимаются
  только `('xhigh','medium','low')`, **фолда `high→xhigh` в этом шаблоне нет**
  (`/opt/models/Qwen3.8-27B-NVFP4/chat_template.jinja:46-55`). Поэтому
  валидный литерал `high`/`minimal`/`max` доходит до шаблона и вызывает
  `raise_exception`.
- **Ошибка шаблона → 400**: `create_error_response` мапит любой класс с
  именем `TemplateError` в MRO на `BadRequestError` / 400
  (`vllm/entrypoints/serve/utils/error_response.py:74-77`). То есть vLLM и
  NInfer отвечают 400 на сломанный шаблон, а llama.cpp — 500.
- Sampling-дефолты берутся из `generation-config: auto`
  (`vllm/config.yaml:31`) → `generation_config.json` модели:
  `temperature 1.0`, `top_k 20`, `top_p 0.95`, `do_sample true`.
- Поле в ответе — `reasoning` (новое имя); `reasoning_content` принимается
  через compat-shim и переписывается в `reasoning`
  (`protocol.py:61`, `:524-540`).
- `--reasoning-parser qwen3`, `--tool-call-parser qwen3_xml`,
  `enable-auto-tool-choice` (`vllm/config.yaml:27-30`).
- Есть `include_reasoning` и `thinking_token_budget`
  (`protocol.py:257-258`) — дополнительные рычаги, которых нет у двух других.

## 4. Сводная таблица: параметр → llama.cpp / NInfer / vLLM

Легенда: **A** — принимает и применяет; **C** — принимает, но clamp'ит;
**E** — принимает и отвечает ошибкой; **I** — игнорирует.

| Параметр | llama.cpp (`62318cd57`, профиль `llama`) | NInfer `v0.4.6` (профиль `ninfer`) | vLLM `dev19754` (профиль `vllm`) |
|---|---|---|---|
| Неизвестные top-level поля | **I** (`server-schema.cpp:467-500`) | **I** (`serving.md:148`) | **I** (`extra="allow"`) |
| `null` у известного поля | **I** → серверный дефолт (`server-schema.cpp:526-529`) | **I** → «unspecified» (`serving.md:202-205`) | **I** → серверный дефолт (`renderers/params.py:27-40`) |
| `temperature` | **A**/**C** `[0,∞)` (`server-schema.cpp:116-118`) | **E** `[0,2]` (выведено из `serving.md:421` + strings) | **E** `[0,2]` (`sampling_params.py:555-561`) |
| `top_p` | **A**/**C** `[0,1]` | **E** `[0,1]` (`serving.md:422`) | **E** `(0,1]` (`sampling_params.py:567`) |
| `top_k` | **A**/**C** `[0,∞)`, `≤0` = весь словарь (выкл) | **E** `[0,20]`; **`0` = top-20 cap** | **E** `0` (или `-1`) = выкл, иначе ≥1 (`sampling_params.py:573-579`) |
| `min_p` | **A**/**C** `[0,1]`, `0` = off | **E** `[0,1]` | **E** `[0,1]` |
| `presence_penalty` | **A**/**C** без границ, `0` = off | **E** `[-2,2]` | **E** `[-2,2]` |
| `frequency_penalty` | **A**/**C** без границ | **E** `[-2,2]` | **E** `[-2,2]` |
| `repetition_penalty` | **I** (нет такого имени) | **E**, кроме значения `1` | **A** любое > 0 |
| `repeat_penalty` (имя llama) | **A**/**C** | **I** | **I** |
| `seed` | **A** | **A** | **A** |
| `reasoning_effort` (top-level) | **A**: `none` → thinking off; иное → в шаблон без валидации; невалид → **500** | **A** c fold'ом; невалид → **E 400**; неверный тип → **E 400** | **A** `Literal`; невалид → **E 400**; `high`/`minimal`/`max` → шаблон → **E 400** |
| `chat_template_kwargs` | **A** по-ключевой merge поверх CLI (`server-common.cpp:1404-1409`) | **A** merge с typed полями, конфликт → **E 400**, часть ключей защищена (`serving.md:202-205`) | **A** merge, `None`/`"auto"` отбрасываются, фильтр по объявленным vars |
| `…enable_thinking` | **A** только через kwargs, строка → **E 400** | **A** top-level или kwargs; конфликт с effort → **E 400** | **A** только kwargs; авто-вставка из `reasoning_effort` (`protocol.py:580-582`) |
| `…preserve_thinking` | **A** как переменная шаблона (серверная капа называется `preserve_reasoning`) | **A** top-level или kwargs; bool/null; конфликт → **E 400** | **A** как переменная шаблона (серверной капы нет) |
| `…reasoning_effort` (в kwargs) | **A** (тот же путь, что top-level) | **A** (те же правила fold/валидации) | **A** (те же правила Literal) |
| `reasoning` (top-level) | **I** (это имя CLI-флага `--reasoning`, не поля тела) | **I** | **I** |
| `reasoning_budget_tokens` | **A** (`-1`/`0`/`N`) | **I** (бюджет только серверный флаг / Anthropic `thinking`) | частично: `thinking_token_budget` |
| `reasoning_format` | **A** (`auto`/`none`/`deepseek`/…) | **I** | **I** |
| Ошибка шаблона (`raise_exception`) | **E 500** | **E 400** | **E 400** |
| Поле reasoning в ответе | `reasoning_content` (при `reasoning_format deepseek/auto`) | `reasoning_content` | `reasoning` (compat-shim со старого `reasoning_content`) |
| Политика на «движок не может это дать» | ignore (нет таких проверок) | **E 400** с указанием поля и гарантии (`serving.md:134-142`) | **E 400** через `VLLMValidationError` |

## 5. Параметры, нельзя передавать всем трём безвредно

Кандидаты на shim (пере-маппинг на клиенте/в llama-swap) или на отказ от
«клиент владеет всем»:

1. **`top_k: 0`** — три разных значения. llama.cpp: выкл (весь словарь);
   vLLM: выкл; NInfer: **top-20 cap**, т.е. не выкл. Клиент, шлющий `0` как
   «выключить», получит в ninfer-профиле top-20.
2. **`repetition_penalty`** — имя + ограничение. NInfer принимает только `1`;
   llama.cpp вообще не знает это имя (знает `repeat_penalty`); vLLM принимает
   любое. Без shim «повторный штраф» работает только на vLLM.
3. **`reasoning_effort`** — разные словари и разные коды ошибок:

   | Значение | llama.cpp | NInfer | vLLM |
   |---|---|---|---|
   | `none` | thinking off | thinking off | thinking off |
   | `low` / `medium` / `xhigh` | работает | работает | работает |
   | `high` | работает (fold → xhigh) | работает (fold → xhigh) | **400** |
   | `minimal` | **500** (шаблон) | работает (fold → low) | **400** |
   | `max` | **500** (шаблон) | работает (fold → xhigh) | **400** |
   | `adaptive` | **500** (шаблон) | работает (fold → xhigh) | **400** |
   | другое | **500** | **400** | **400** |

   Без shim безопасен общий словарь `none|low|medium|xhigh` (+ `high`, если
   vLLM-профиль не нужен, либо если vLLM-шаблон заменить на фордящий).
4. **`temperature` вне `[0,1]`** — llama.cpp примет и clamp'нет молча (включая
   отрицательные → greedy), NInfer/vLLM ответят 400. «Валидный на одном,
   ошибка на другом» — нехудший исход, но **различный**: ошибку клиент увидит
   только на части профилей.
5. **Поля, которые NInfer осознанно отклоняет** (`response_format: json_object`,
   `logit_bias`, `logprobs`, `strict`, `parallel_tool_calls:false`, named
   tool choice, `functions` и др., `serving.md:134-142`): в llama.cpp/vLLM они
   либо работают, либо игнорируются. Значит «один клиент на три профиля» не
   может слать JSON-структурированный вывод.
6. **Имя поля reasoning в ответе** различается (`reasoning_content` против
   `reasoning`) — это уже выяснено в тикете 02; shim нужен на стороне чтения
   ответа.

Что можно слать всем трём без shim: `temperature` в `[0,1]`, `top_p` в
`(0,1]` (**не 0** — vLLM требует строго больше нуля, `sampling_params.py:567`),
`top_k` в `1..20` (не 0), `min_p` в `[0,1]`, `presence_penalty`/
`frequency_penalty` в `[-2,2]`, `seed`, `reasoning_effort` из
`none|low|medium|xhigh`, `chat_template_kwargs.enable_thinking` и
`preserve_thinking` как bool, `max_tokens ≥ 1` (vLLM: `max_tokens < 1` → 400,
`sampling_params.py:581-586`).

## 6. Выводы для решения тикета

- **Если цель — «сервер без мнения, клиент владеет всем»:** технически
  достижимо (все три принимают клиентские параметры), но требует (а) shim-слоя
  поверх трёх контрактов и (б) явного решения о том, какие режимы всё равно
  обязаны существовать на сервере, — потому что дефолты шаблона
  (`enable_thinking`/`reasoning_effort = xhigh`) и дефолт `max_tokens` убрать
  нельзя.
- **Если цель — «однородный контракт»:** это ровно то, что сейчас делает
  llama-swap-слой `stripParams` + `setParamsByID`. Он гасит расхождения
  (диапазоны, `top_k: 0`, `repetition_penalty`, словари effort) и делает
  поведение одинаковым. Убрав его, мы переносим эту сложность на клиентов.
- **Рекомендуемый компромисс** (не реализуется этим тикетом, только
  фиксируется): оставить на сервере явное мнение для **reasoning-режимов**
  (их семантика backend-зависимая: fold, `conflicting_template_option`,
  авто-вставка `enable_thinking`), а клиенту разрешить свободно управлять
  только **sampling-параметрами внутри общего пересечения** диапазонов — с
  shim'ом для `repetition_penalty`/`repeat_penalty` и запретом `top_k: 0`.

## 7. Что не проверено на живом сервере

- Реальный HTTP-статус llama.cpp на невалидном `reasoning_effort`
  (вывод: 500 — из цепочки `raised_exception → ex_wrapper → ERROR_TYPE_SERVER`;
  проверяется `curl -d '{"model":"qwen3.8-27b","messages":[...],"reasoning_effort":"ultra"}'`).
- Реальный диапазон `temperature` у NInfer **Chat** (`[0,2]` — выведение из
  строк бинаря и таблицы Responses; `[0,1]` относится к Anthropic).
- Поведение NInfer на `top_k`/`min_p` вне диапазона (вывод: 400 — из строк
  бинаря; clamp или reject не подтверждён).
- vLLM: `reasoning_effort="high"` → 400 выводится из расхождения Literal
  (принимает `high`) и шаблона (не принимает) + маппинга `TemplateError` → 400.
  На живом сервере не воспроизводилось.
- Качество/длина ответа при clamp'е `temperature` в llama.cpp (что
  `temperature: -1` и `temperature: 0` дают один и тот же greedy-режим на
  текущей версии) — вывод из кода `common/common.h:239` и schema-clamp.

## Источники (кратко)

- llama.cpp `62318cd57`: `tools/server/server-common.cpp:1272-1489`,
  `tools/server/server-common.h:42-55`, `tools/server/server-schema.cpp:88-145,335-337,467-500,516-548`,
  `tools/server/server.cpp:55-88`, `tools/server/server-context.cpp:4931-4941,5557-5576`,
  `common/chat.cpp:884-922`,
  `common/jinja/caps.cpp:17-29`, `common/jinja/value.cpp:420-426`,
  `common/jinja/runtime.h:694`, `common/arg.cpp:3560-3568,3700-3747`,
  `common/common.h:226-245`, `tools/server/README.md:232-239`.
- NInfer `ValerioDolci/ninfer-tp2@47d47864`: `docs/serving.md:109-164,196-235,410-439,823-847`,
  `tools/chat_templates/qwen3_8.jinja`, `--help` бинаря, `strings` бинаря.
- vLLM `0.1.dev19754+g3a0914114`: `vllm/entrypoints/openai/chat_completion/protocol.py:217-268,357-362,524-540,564-582`,
  `vllm/entrypoints/openai/engine/protocol.py:31-33`,
  `vllm/entrypoints/serve/utils/error_response.py:18-81`,
  `vllm/entrypoints/serve/utils/server_utils.py:496-541`,
  `vllm/sampling_params.py:515-581`, `vllm/renderers/params.py:27-40`,
  `vllm/renderers/hf.py:633-662`,
  `https://docs.vllm.ai/en/latest/features/reasoning_outputs.html` (snapshot 2026-10-17).
- llama-swap `a2796fb`: `internal/server/filters.go:18-69,114-172`
  (порядок `useModelName → stripParams → setParams → setParamsByID`).
- Конфиги: `llama/config.yaml:40-151`, `ninfer/config.yaml:23-97`,
  `vllm/config.yaml:1-32`.
