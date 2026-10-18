# opencode v2: consumer-конфиг и оверлеи на уровне агента

Type: task
Status: resolved

## Question

Тикет 07 гонялся на **opencode v2.0.32** (исследование 0012 писалось против
1.18.35). Выяснилось, что потребительский конфиг работает иначе, чем
предполагалось при миграции потребителей (тикет 06 правила
`~/.config/opencode/opencode.jsonc`):

- **оверлеи на уровне агента не уходят в запрос**: `agent.*.options`,
  top-level `reasoningEffort` и `agent.*.request.body` сохраняются, но в тело не
  попадают (документированное поведение V2). В частности
  `agent.plan.reasoningEffort: xhigh` в пользовательском `opencode.jsonc`
  **молча игнорируется**;
- reasoning управляется на уровне провайдера/модели/**варианта**; вариант — это
  `{id, settings, headers, body}`, где `settings` → опции провайдера, а `body`
  deep-merge'ится в тело запроса (именно так передаётся `chat_template_kwargs`);
- вариант выбирается только на прогон: `--model provider/model#variant`; корневой
  `model` в конфиге `#…` игнорирует;
- `OPENCODE_CONFIG` **сливается** с `~/.config/opencode/opencode.jsonc`
  (изоляция — только через `HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`);
- `XDG_CONFIG_HOME` для глобального конфига не учитывается.

Нужно привести пользовательский конфиг потребителя в соответствие: вынести
reasoning в варианты модели (`body.chat_template_kwargs`) или в `settings`
провайдера, убрать/переписать мёртвые `agent.*.options`/`reasoningEffort`.
Учесть вывод тикета 11 (top-level `reasoning_effort` под llama-профилем —
no-op), чтобы один и тот же конфиг работал на обоих движках.

Проверить: что именно сейчас лежит в `~/.config/opencode/opencode.jsonc`, и
какой режим reasoning фактически получает потребитель.

## Answer

2026-10-17. Клиент v2.0.32, активный профиль `ninfer` (одного движка
достаточно — контракт вариантов переносим, тикеты 07/11). Доказательства —
`assets/14-opencode-v2/` (README, tap-логи, `tap-summary.txt`).

### Что было (инвентаризация)

- **`agent.plan.reasoningEffort: "xhigh"`** — мёртвый: v2 не отправляет
  оверлеи агента (`agent.*.options`, top-level `reasoningEffort`,
  `agent.*.request.body`) в тело запроса. `agent.plan.model` при этом
  работает — указывал на ту же сломанную модель.
- **`provider.self-hosted.models["qwen3.8-27b"]`** (модельные
  `options.reasoningEffort: "medium"` + `chat_template_kwargs.preserve_thinking`)
  — запись была сломана маршрутизацией ещё до v2: провайдер `self-hosted`
  указывает на шлюз `http://192.168.17.69:9000/v1` (живая другая машина,
  старый llama-swap с ID `llama/qwen3.8-27b`), где ID `qwen3.8-27b` не
  существует; корневой `model: self-hosted/qwen3.8-27b` и план-агент
  указывали на неё. Плюс модельные options дали бы непереносимый top-level
  `reasoning_effort` (инертен на llama.cpp) — не тот контракт.
- Никаких `tools`/`permission`-настроек в конфиге не было; терять было нечего.

### Что стало

 reasoning управляется **вариантами модели** в новом провайдере
`providers.llama-swap` (v2-форма: `settings.baseURL: http://localhost:8080/v1`,
`package: @opencode/ai/providers/openai-compatible`, модель `qwen3.8-27b`,
`compatibility.reasoningField: reasoning_content`, `limit 262144/16384`).
Варианты — массив `{id, body}`, `body` deep-merge'ится в тело запроса, всё на
переносимом `chat_template_kwargs`:

| id | body |
|---|---|
| `off` | `chat_template_kwargs.enable_thinking: false` (instruct; top-level `none` сознательно не используется) |
| `low` / `medium` / `xhigh` | `chat_template_kwargs.reasoning_effort: low|medium|xhigh` |

Остальное: корневой `model: llama-swap/qwen3.8-27b` — **без** `#variant`
(вариант в корневом `model` v2.0.32 игнорирует — подтверждено живым прогоном:
в тело ушёл голый ID, `kwargs=null`); `agent.plan.model` →
`llama-swap/qwen3.8-27b`, мёртвый `reasoningEffort` удалён (голый ID и так
даёт thinking+xhigh — фактический эквивалент задуманного `xhigh`).
Мёртвая запись `self-hosted/qwen3.8-27b` удалена. Deprecated-блок `provider`
(`self-hosted` — шлюз с `rus-gpt/*`/`qwencloud/*`, `openai`) не тронут —
coexistence `provider` + `providers` в одном конфиге работает (проверено
`opencode models`: резолвятся и `llama-swap/qwen3.8-27b`, и `self-hosted/...`).

Выбор режима за потребителем: `opencode run -m 'llama-swap/qwen3.8-27b#off|low|medium|xhigh'`
или `variant_cycle` в TUI; без варианта — дефолт шаблона (thinking + xhigh).

### Чем подтверждено

Изолированный `HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME` + `OPENCODE_CONFIG`,
весь HTTP через tap-proxy `:8091` → `:8080`, движок NInfer. По телам запросов
и SSE-ответам (`tap-summary.txt`):

- `#off` — в теле `chat_template_kwargs:{enable_thinking:false}`, tools=12,
  `reasoning_content` **пуст** (0 символов);
- `#medium` — `reasoning_effort:"medium"`, reasoning 54 симв.;
- `#xhigh` — `reasoning_effort:"xhigh"`, reasoning 138 симв. (растёт с effort);
- корневой `model` с `#medium` — вариант отброшен, `kwargs=null`, reasoning 133
  (голый ID = thinking+xhigh) — дефект «корневой model игнорирует #» подтверждён.

Практические находки для будущих прогонов: managed service opencode читает
конфиг при старте и переживает CLI-вызовы — после смены `OPENCODE_CONFIG`
нужен `opencode service stop`; порт сервиса разводится
`opencode service set port <port>` (дефолт 49374 конфликтует с живой сессией).

Бэкап прежнего конфига: `~/.config/opencode/opencode.jsonc.bak-ticket14`.
Текущая запущенная сессия opencode продолжает работать на старом конфиге
(managed service держит его в памяти) — новый конфиг подхватит следующий
старт opencode.

## Comments

### 2026-10-18 — модель добавлена в провайдер `self-hosted` (bifrost-шлюз)

Пользовательский запрос: локальная модель используется пользователями через
bifrost-шлюз `http://192.168.17.69:9000/v1`; добавить модель в провайдер
`self-hosted`, `llama-swap` не трогать. Итог:

- `provider.self-hosted` (legacy, ~66 моделей `rus-gpt/*`, `qwencloud/*`)
  **перенесён целиком** в v2-блок `providers.self-hosted`
  (`package: @opencode/ai/providers/openai-compatible`,
  `settings.baseURL: http://192.168.17.69:9000/v1`), плюс новая модель
  `llama/qwen3.8-27b` (ID на шлюзе, owned_by llama-swap) с вариантами
  `low|medium|xhigh` на top-level `body.reasoning_effort`.
- Почему перенос, а не добавление в legacy-блок: (1) в v1-блоке variants
  ложатся в тело под `options.body.*` — шлюз стрипует `options` (проверено
  живьём: `options.body.chat_template_kwargs.enable_thinking:false` не
  выключает thinking), варианты были бы мёртвыми; (2) при совпадении ID в
  `provider` (legacy) и `providers` (v2) v2 выигрывает, legacy-блок
  пропускается целиком (diagnostic: «retained native value over legacy
  value»). В v1-блоке v2-variants в форме массива `[{id, body}]` валидацию не
  проходят — весь provider-блок скочится (diagnostic: «skipped malformed
  recognized value»); в v1-блоке принимается только object-map
  `variants: {id: {…}}`.
- Шлюз: `chat_template_kwargs` и `options` стрипуются (контроль:
  `enable_thinking:false` через шлюз — thinking не выключается), top-level
  `reasoning_effort` доходит и меняет поведение (live: `low` доводит
  рассуждение до ответа за 900 токенов, `xhigh`/голый ID — нет). Поэтому
  instruct-вариант `off` через шлюз **не предусмотрен**; reasoning
  через шлюз = только `low|medium|xhigh`.
- Проверено живьём (opencode v2.0.32, `--standalone`): `opencode models`
  резолвит 67 self-hosted (66 legacy + 1 новую); `self-hosted/llama/qwen3.8-27b#low`
  → в теле top-level `reasoning_effort:"low"`, ответ 408; `#xhigh` → 513;
  прямой `llama-swap/qwen3.8-27b#off` не затронут (156).
- Бэкап: `~/.config/opencode/opencode.jsonc.bak-20261018-gateway` (и
  прежний `.bak-ticket14`). Запущенные сессии подхватят конфиг при следующем
  старте opencode (managed service держит старый в памяти).
