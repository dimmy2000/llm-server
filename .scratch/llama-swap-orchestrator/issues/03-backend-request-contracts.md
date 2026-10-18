# Контракты backend'ов при пустом stripParams

Type: research
Status: resolved
Blocked by: —

## Question

Что произойдёт с reasoning- и sampling-параметрами, которые клиент шлёт в
`/v1/chat/completions`, если llama-swap **перестанет** их вырезать
(`stripParams` и `setParamsByID` убраны)? Достижимо ли «у сервера нет мнения»
на каждом из backend'ов?

Нужны факты по каждому backend'у:

1. **llama-server** (профиль `llama`, текущий `cmd` с `--reasoning on`,
   `--jinja`). Как обрабатываются клиентские:
   - `reasoning_effort` (принимает ли значения `none/low/medium/xhigh`, маппинг
     в шаблон);
   - `chat_template_kwargs`: `enable_thinking`, `preserve_thinking`,
     `reasoning_effort` (дефолты шаблона Qwen при их отсутствии);
   - sampling (`temperature`, `top_p`, `top_k`, `min_p`, `presence_penalty`,
     `repeat_penalty`).
   Источник — локальный `../llama.cpp` (server, chat template, README) и
   `llama/config.yaml`.
2. **NInfer-serve** (профиль `ninfer`, `reasoning_effort` на сервере сейчас
   форсится). Что делает движок, если `reasoning_effort` в запросе есть,
   отсутствует или невалиден; как ведёт себя `chat_template_kwargs`
   (`conflicting_template_option`, замена объекта целиком); принимает ли
   клиентский sampling и `repetition_penalty` (известно: только `1.0`).
   Источник — `ninfer/config.yaml`, справка бинаря, `docs/research/0009`,
   `docs/adr/0003`.
3. **vLLM** (профиль `vllm`). Как vLLM трактует `reasoning_effort` и
   `chat_template_kwargs.enable_thinking`; текущий `vllm/config.yaml`.
4. **Расхождения.** Составить таблицу «параметр → llama.cpp / NInfer / vLLM»:
   принимает / игнорирует / ошибается. Явно отметить параметры, которые
   нельзя передавать всем трём безвредно (кандидаты на shim или на отказ от
   «клиент владеет всем»).
5. **Дефолт голого ID.** Если клиент не шлёт ничего — что делает каждый
   backend (thinking on/off, effort, sampling) по умолчанию.

## Answer

**Полное исследование:** `docs/research/0013-backend-request-contracts.md`
(сырые артефакты — `.scratch/llama-swap-orchestrator/assets/03-backend-contracts/`).

### Гист

1. **«У сервера нет мнения» в смысле «нет дефолтов» недостижимо.** У каждого
   backend'а есть неснимаемые дефолты: sampling-пресет, дефолт шаблона
   (`enable_thinking`, `reasoning_effort = xhigh`), лимит `max_tokens`. Их не
   выключить ни `stripParams`, ни отсутствием `setParamsByID`.
2. **Снятие фильтров меняет поведение голого ID.** Сегодня `qwen3.8-27b` в
   `llama`/`ninfer` — non-thinking (`0.7/0.80/20/0/1.5`). Без `setParamsByID`
   он становится thinking + effort xhigh на всех трёх профилях. Чтобы
   сохранить текущее поведение, это надо явно выставить на стороне движка
   (`--reasoning off` / `--no-thinking` / `--default-chat-template-kwargs`) —
   то есть сервер обязан иметь мнение.
3. **«Клиент владеет всем» достижимо технически, но не безвредно.** Все три
   принимают клиентские параметры и игнорируют неизвестные top-level поля,
   но расходятся по диапазонам, поведению на мусор и словарю `reasoning_effort`
   → нужен shim либо сохранение части фильтров в llama-swap.
4. **llama-swap-слой сейчас несёт функцию однородного контракта.** Убрав
   `stripParams`/`setParamsByID`, мы переносим разночтение трёх контрактов на
   клиентов. Это же суть тикета 02/03: единый endpoint ≠ единый контракт.

### Сводная таблица (полная — отчёт, раздел 4)

Легенда: **A** принимает и применяет, **C** clamp'ит, **E** ошибка, **I**
игнорирует.

| Параметр | llama.cpp | NInfer v0.4.6 | vLLM dev19754 |
|---|---|---|---|
| неизвестные top-level поля | I | I | I (`extra="allow"`) |
| выход за диапазон sampling | **C** (clamp, `server-schema.cpp:532-547`) | **E 400** | **E 400** |
| `top_k: 0` | выкл (весь словарь) | **top-20 cap** | выкл |
| `repetition_penalty` | I (нужно имя `repeat_penalty`) | только `1`, иначе **E 400** | любое > 0 |
| `reasoning_effort: none\|low\|medium\|xhigh` | работает | работает | работает |
| `reasoning_effort: high\|minimal\|max\|adaptive` | `high` работает, остальные **E 500** | работает (fold) | **E 400** |
| невалидный `reasoning_effort` | **E 500** (ошибка шаблона) | **E 400** | **E 400** |
| `enable_thinking` | только через `chat_template_kwargs`; строка → **E 400** | top-level или kwargs; конфликт с effort → **E 400** `conflicting_template_option` | только kwargs + авто-вставка из `reasoning_effort` |
| `preserve_thinking` | как переменная шаблона (серверная капа — `preserve_reasoning`) | top-level или kwargs, bool/null, конфликт → **E 400** | как переменная шаблона |
| `chat_template_kwargs` | по-ключевой merge поверх CLI | merge + конфликт-проверки, часть ключей запрещена | merge, `None`/`"auto"` отбрасываются |
| ошибка шаблона | **500** | **400** | **400** |
| reasoning в ответе | `reasoning_content` | `reasoning_content` | `reasoning` (compat-shim) |

### Ответ на вопрос о «безвредном» переносе

Без shim всем трём безопасно слать: `temperature` ∈ `[0,1]`, `top_p` ∈ `(0,1]`
(**не 0**), `top_k` ∈ `1..20` (не `0`), `min_p` ∈ `[0,1]`,
`presence_penalty`/`frequency_penalty` ∈ `[-2,2]`, `seed`,
`reasoning_effort` из `none|low|medium|xhigh`,
`chat_template_kwargs.{enable_thinking,preserve_thinking}` (bool),
`max_tokens` ≥ 1.

Не переносится без shim: `top_k: 0`, `repetition_penalty` ≠ 1,
`reasoning_effort: high|minimal|max|adaptive`, JSON-структурированный вывод и
прочие поля, которые NInfer осознанно отклоняет
(`docs/serving.md:134-142`).

**Не проверено на живом сервере** (вывод из кода, см. отчёт, раздел 7):
статус 500 на невалидном `reasoning_effort` в llama.cpp; диапазон
`temperature` у NInfer **Chat**; `reasoning_effort="high"` → 400 в vLLM.
