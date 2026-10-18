# 0012 — opencode: управление reasoning и tools через openai-compatible провайдер

Исследование по тикету
`.scratch/llama-swap-orchestrator/issues/02-opencode-reasoning-control.md`.

Цель: понять, как клиент **opencode** (версия `1.18.35`) прокидывает
`reasoning_effort` / `chat_template_kwargs` и tool-вызовы в тело запроса
`POST /v1/chat/completions` нашего единого endpoint'а `qwen3.8-27b`, и дать
готовую конфигурацию для режимов «с размышлениями / без» и «с инструментами /
без».

## Что проверяли и на чём

| Артефакт | Источник | Версия |
|---|---|---|
| opencode binary | `/home/dimmy/.opencode/bin/opencode` | `1.18.35` |
| `@ai-sdk/openai-compatible` (bundled) | `packages/opencode/package.json@v1.18.35:71` → `2.0.41` | `2.0.41` |
| opencode source | GitHub tag `v1.18.35` (`packages/opencode/src/*`, `packages/core/src/v1/config/*`) | `v1.18.35` |
| Docs | https://opencode.ai/docs/{providers,config,agents,models,cli} | snapshot 2026-10-17 |
| Endpoint | `http://localhost:8080/v1` | профиль `ninfer` |

**Важно про версию SDK.** `@ai-sdk/openai-compatible` **bundled** внутри
бинарника (`packages/opencode/src/provider/provider.ts:158` —
`BUNDLED_PROVIDERS["@ai-sdk/openai-compatible"]`). Локально в
`~/.config/opencode/node_modules/@ai-sdk/` его **нет** (там только каталог
`provider`) — ставить его не нужно и негде. Bundled-версия по
`package.json` = **2.0.41**. npm-канал между 2.0.41 и свежим `3.0.7x`
сохранил механизм без изменений (см. раздел «Версии»), поэтому рецепт ниже
устойчив к обновлению.

Сырые артефакты (исходники, grep по бинарнику, `/v1/models`):
`.scratch/llama-swap-orchestrator/assets/02-opencode/`.

---

## 1. Адрес и порт (Q5)

**Текущий конфиг указывает неверно.** `~/.config/opencode/opencode.jsonc:14`
содержит `baseURL: http://192.168.17.69:9000/v1`, но порта `:9000` в стеке
нет:

- Compose публикует только `:8080`: `llama/docker-compose.yaml:6-7`
  (`8080:8080`), `ninfer/docker-compose.yaml:19-20` (`8080:8080`),
  `vllm/docker-compose.yaml:14-15` (`8080:8000`).
- Проба: `localhost:8080/v1/models` → `200`; `localhost:9000/v1/models` →
  connection refused (`assets/02-opencode/port-probe.txt`).
- Фактически сейчас работает `ninfer`:
  `docker ps` → контейнер `llama-swap`, образ
  `llm-server/ninfer-tp2:v0.4.6`, `0.0.0.0:8080->8080/tcp`.

`scripts/port-forwarding-rules.ps1:29-32` пробрасывает **каждый** опубликованный
docker-порт на WSL-IP **с тем же портом**
(`netsh ... listenport=$Port connectport=$Port connectaddress=$wslIp`).
Публикуется `8080`, значит пробрасывается `8080`, а не `9000`. WSL-IP
сейчас `192.168.17.99` (а не `.69` — адрес устарел).

Правильные значения:

| Клиент | baseURL |
|---|---|
| opencode **внутри WSL** | `http://localhost:8080/v1` |
| opencode на Windows-хосте | `http://localhost:8080/v1` (portproxy) или `http://192.168.17.99:8080/v1` |
| opencode на другом хосте LAN | `http://192.168.17.99:8080/v1` |

### Сопутствующая ошибка: имя модели

В конфиге ключи моделей записаны с префиксом `llama/`:
`llama/qwen3.8-27b`, `llama/qwen3.8-27b-agent-medium`, …
Но opencode отправляет в тело запроса **значение `model` = ключ моделей**:

- `parseModel("self-hosted/llama/qwen3.8-27b")` даёт
  `modelID = "llama/qwen3.8-27b"` (остальное после первого `/` —
  `packages/opencode/src/provider/provider.ts:2079-2084`);
- `api.id = model.id ?? ... ?? modelID` (`provider.ts:1546`) — явное поле
  `id` не задано, значит `api.id = "llama/qwen3.8-27b"`;
- SDK шлёт `model: this.modelId` (`api.id`) —
  `sdk/chat(api.id)`, `provider.ts:1938`.

Наш endpoint отдаёт в `/v1/models` **только голые ID** без префикса:

```
qwen3.8-27b
qwen3.8-27b-agent-low / -medium / -xhigh
qwen3.8-27b-chat-low  / -medium / -xhigh
```

(`assets/02-opencode/endpoint-8080-models.json`). Значит opencode сейчас
отправит `model: "llama/qwen3.8-27b"`, чего сервер не знает. **Либо переименовать
ключи моделей в голые ID, либо задать на каждой модели явный `id`.** См. рецепт в
разделе «Готовая конфигурация». (Это, кстати, согласуется с AGENTS.md: llama-swap
переписывает клиентское имя на каноническое `qwen3.8-27b` через `useModelName`,
но префикс `llama/` он тоже не знает.)

---

## 2. Механизм прокидывания reasoning в тело запроса (Q1)

Цепочка из трёх слоёв: **opencode собирает options → кладёт их под ключ
провайдера в `providerOptions` → SDK разворачивает их в тело HTTP-запроса.**

### 2.1 Сборка `options` в opencode

`packages/opencode/src/session/llm/request.ts:80-91`:

```
variant   = model.variants[user.model.variant] ?? {}      // для qwen = {} 
base      = ProviderTransform.options({model, sessionID, providerOptions: provider.options})
options   = mergeDeep( mergeDeep( mergeDeep(base, model.options), agent.options), variant )
```

- `model.options` — из `provider.<id>.models.<modelId>.options`
  (`packages/core/src/v1/config/provider.ts:67`, тип `Record(String, Any)` —
  любые ключи).
- `agent.options` — из `agent.<name>.options` **плюс любых неизвестных
  топовых ключей агента** (см. 3.1).
- `variant` — `model.variants`. **Для qwen это пусто**: функция
  `variants()` возвращает `{}` для всех моделей с `id.includes("qwen")`
  (`packages/opencode/src/provider/transform.ts:851`). Авто-варианты
  `low/medium/high/xhigh` для qwen opencode **не создаёт** — reasoning
  задаётся только явными options.

`base` **не утекает в тело**: `ProviderTransform.options`
(`transform.ts:1220-1387`) для нашего провайдера возвращает `{}` (нет ни
`openai`, ни `gpt-5` веток). Provider-level `options` (`baseURL`, `apiKey`,
`timeout` …) используются **только** при сборке SDK-инстанса, а не в теле
запроса. Проверено: `transform.ts` читает из `input.provider.options` лишь
`setCacheKey` / `useCompletionUrls`.

### 2.2 Ключ `providerOptions`

`transform.ts:1462-1478` (`ProviderTransform.providerOptions`):

```
key = sdkKey(npm) ?? (openai-compatible ? providerID.split(".")[0] : providerID)
return { [key]: normalized }
```

Для `npm: "@ai-sdk/openai-compatible"` → `key = "self-hosted"` (providerID
без точки). Результат вызывается как `streamText({ providerOptions: ... })`
(`session/llm.ts:316`).

### 2.3 Как SDK инстанцируется

`provider/provider.ts:1853-1859`:

```
factory({ name: model.providerID, ...options })   // name = "self-hosted"
```

Внутри SDK `config.provider = `${name}.chat``, и
`providerOptionsName = config.provider.split(".")[0]` =
**`"self-hosted"`** (`@ai-sdk/openai-compatible@2.0.41`
`chat/openai-compatible-chat-language-model.ts:103-105`). То есть ключ, под
которым opencode кладёт options, **совпадает** с тем, что читает SDK.

### 2.4 Тело запроса SDK (2.0.41)

`openai-compatible-chat-language-model.ts:146-252`:

1. `compatibleOptions` собирается из **четырёх алиасов** (`:146-163`):
   `openai-compatible` (deprecated), `openaiCompatible`,
   `providerOptionsName` (`"self-hosted"`), `toCamelCase(providerOptionsName)`
   (`"selfHosted"`). Проходят **только 4 схемных поля** (см. 2.5).
2. Затем в тело (`:231-244`):

```js
...Object.fromEntries(
  Object.entries({
    ...providerOptions?.[this.providerOptionsName],     // ["self-hosted"]
    ...providerOptions?.[toCamelCase(this.providerOptionsName)], // ["selfHosted"]
  }).filter(([key]) =>
    !Object.keys(openaiCompatibleLanguageModelChatOptions.shape).includes(key)
  ),
),
reasoning_effort: compatibleOptions.reasoningEffort,
verbosity: compatibleOptions.textVerbosity,
```

То есть: **всё содержимое `providerOptions["self-hosted"]`, кроме 4 схемных
ключей, кладётся в тело как есть**, а поверх явно пишутся `reasoning_effort`
и `verbosity`.

### 2.5 Что попадает в тело, а что нет

Схема SDK (`chat/openai-compatible-chat-options.ts`) знает ровно 4 поля:

| option в конфиге | поле тела | примечание |
|---|---|---|
| `reasoningEffort` | `reasoning_effort` | `:243` |
| `textVerbosity` | `verbosity` | `:244` |
| `user` | `user` | `:205` |
| `strictJsonSchema` | `strict` внутри `json_schema` | `:221` |

Всё остальное — **произвольный pass-through**:

- `chat_template_kwargs` (объект) → тело как есть (не схемный ключ, проходит
  фильтром). Так можно передать `enable_thinking`, `preserve_thinking`,
  `thinking_mode` и т.д. — **ровно то, что нужно нашему endpoint'у**.
- Любые другие ключи (`reasoning`, `min_p`, `logit_bias`, `response_format`
  не-схемный и т.п.) → тоже в тело.

Важные ловушки:

- **`reasoning_effort` (snake_case) не сработает.** Он не в схеме, проходит
  в spread, но тут же перезаписывается явным
  `reasoning_effort: compatibleOptions.reasoningEffort` (`:243`). Если
  `reasoningEffort` не задан, значение становится `undefined` и
  **выбрасывается при `JSON.stringify`** — ключ исчезнет. Используйте
  **camelCase `reasoningEffort`**.
- `topK` opencode **не шлёт** в body для openai-compatible — SDK помечает его
  `unsupported` (`:167-169`). `temperature` / `top_p` / `frequency_penalty` /
  `presence_penalty` шлются как есть (`:208-212`).
- `reasoning_effort: "none"` → тело `reasoning_effort: "none"` (сервер сам
  трактует как off). Если **не задавать** `reasoningEffort` вообще — ключ
  `reasoning_effort` в теле **отсутствует**, и решение остаётся за
  серверным дефолтом. Оба варианта валидны — выбирайте в зависимости от
  того, какой дефолт у backend (см. «Факт vs неизвестно»).

---

## 3. Агенты и субагенты (Q2)

### 3.1 Как агент получает свои options

Схема агента — `packages/core/src/v1/config/agent.ts`. Ключевой приём:
`AgentSchema = Schema.StructWithRest(knownFields, [Schema.Record(String, Any)])`,
а `normalize()` (`:31-46`) **переносит любой неизвестный топовый ключ в
`options`**:

```ts
for (const [key, value] of Object.entries(agent))
  if (!KNOWN_KEYS.has(key)) options[key] = value
```

`KNOWN_KEYS` = name, model, variant, prompt, description, temperature, top_p,
mode, hidden, color, steps, maxSteps, options, permission, disable, tools.

Выводы:

- `"agent": {"deep": {"model": "...", "reasoningEffort": "high"}}` —
  `reasoningEffort` уедет в `agent.options` и попадёт в тело. Так и делает
  официальная дока (docs/agents → «Additional»).
- Можно писать явно `"options": { ... }` — результат тот же
  (`agent_agent.ts:292`: `item.options = mergeDeep(item.options, value.options ?? {})`).

Приоритет при `mergeDeep` (request.ts:91): `agent.options` > `model.options` >
`base`. Агент всегда перекрывает глобальные model options — это подтверждает и
дока («The agent config overrides any global options here», docs/models).

### 3.2 Разные настройки для основного агента и субагента

Агенты независимы: у каждого свой `model` и свои options. Пример:

```jsonc
{
  "model": "self-hosted/qwen3.8-27b-agent-medium",
  "agent": {
    "think-deep":  { "model": "self-hosted/qwen3.8-27b-agent-xhigh", "reasoningEffort": "xhigh" },
    "think-fast":  { "reasoningEffort": "low" },
    "no-think":    { "reasoningEffort": "none" }
  }
}
```

`reasoningEffort` агента перекрывает `reasoningEffort` модели: если на модели
задан `"reasoningEffort": "medium"`, а на агенте `"none"` — в тело уедет
`"none"`.

### 3.3 Как запустить субагента

- **Из CLI** — `opencode run --agent <name> --model <provider/model> "задача"`.
  Но `--agent` принимает **только primary-агент**: если `mode: subagent`,
  run падает с предупреждением «agent … is a subagent, not a primary agent.
  Falling back to default agent» (`cli/cmd/run.ts:610-614`).
  `mode: all` (дефолт) тоже подходит — тогда агент primary.
- **Из сессии** — упоминание `@<agent>` в автокомплите, либо инструмент
  `task` (другой агент вызывает субагента программно; доступ регулируется
  `permission.task`, docs/agents → «Task permissions»).
- Глубина вложенности субагентов — `subagent_depth` (дефолт 1).

---

## 4. Tool calls (Q4)

### 4.1 Как opencode передаёт tools

`request.ts:148-158, 210-216`: `resolveTools` берёт все доступные инструменты
и фильтрует по `permission` (агент + глобальный). Затем `streamText({
tools: prepared.tools, toolChoice })` (`session/llm.ts:318-319`) → SDK
`prepareTools` (`openai-compatible-prepare-tools.ts`):

- пустой список инструментов превращается в `undefined`
  (`:34` — `tools = tools?.length ? tools : undefined`);
- в тело попадают `tools: [{type:"function", function:{name, description, parameters}}]`
  и `tool_choice` (`chat-language-model.ts:249-251`).

То есть **tools on/off = включены ли инструменты в списке разрешённых**. Если
все запрещены — в теле запроса **нет поля `tools` вообще**. Это поведение
подтверждается и нашим endpoint'ом: `/v1/models` отдаёт
`"supported_parameters": ["tools","tool_choice"]` — сервер tool-calls
поддерживает.

### 4.2 Как включить/выключить tools для агента

Способ 1 (рекомендуемый, `permission`):

```jsonc
"agent": {
  "no-tools": { "permission": { "*": "deny" } }
}
```

Способ 2 (deprecated `tools`): `tools: { "*": false }` — `core/config/agent.ts:31-46`
конвертирует `tools` в `permission` (`false → deny`), затем мержит явный
`permission`. Дока: «true ≡ {"*":"allow"}, false ≡ {"*":"deny"}» (docs/agents).

Тонкости:

- Глобальные `tools: { "write": false, ... }` тоже конвертируются в
  `permission` на уровне конфига (`config/config.ts:567-577`).
- Даже при пустом наборе tools opencode вставляет «пустышку» `_noop` только
  для github-copilot (`request.ts:159-175`) — для нашего openai-compatible
  провайдера этого нет, тело остаётся без `tools`.

### 4.3 Как проверить, что вызов произошёл (или не произошёл)

CLI `opencode run --format json` (`cli/cmd/run.ts:174-178`) эмитит события
по типам частей (`:678`, `:724-790`):

| событие | источник |
|---|---|
| `tool_use` | `part.type === "tool"` → `:725` |
| `reasoning` | `part.type === "reasoning" && thinking` → `:766` |
| `text` | `part.type === "text"` → `:754` |
| `step_start` / `step_finish` | `:746`, `:750` |

- **Tool-call состоялся** — в JSON-потоке есть `{"type":"tool_use", ...}`.
- **Tool-call НЕ состоялся** — события `tool_use` нет (и в теле запроса
  отсутствовали `tools`, если агент без инструментов).
- В TUI соответствующий `ToolPart` рендерится (тот же код, но через
  `tool(part)`, `run.ts:90-107`).

---

## 5. Как доказать, что размышления включены/выключены (Q3)

Три уровня доказательства, от слабого к сильному:

**A. События opencode (клиентская сторона).** Включить `--thinking` (в
неинтерактивном режиме он по умолчанию **выключен** —
`cli/cmd/run.ts:275`) и смотреть на `reasoning`-события:

```bash
opencode run --format json --thinking \
  --model self-hosted/qwen3.8-27b-agent-medium \
  "Ответь одно слово: 2+2"
# ищем: {"type":"reasoning", ...}   <-- reasoning включён
# отсутствие "type":"reasoning"     <-- reasoning выключен
```

**B. Что сервер должен вернуть.** opencode (точнее SDK) распознаёт
`reasoning_content` **или** `reasoning` в ответе — и в не-стриминг
(`openai-compatible-chat-language-model.ts:293-295`), и в стриме
(`:483`). Если сервер не вернёт ни того, ни другого поля, opencode не
покажет `reasoning`-частей, даже если модель рассуждала. Значит: ключ
`reasoning_content` в ответе = фактическое доказательство.

**C. Что реально ушло в тело запроса (сильнейшее).** opencode **не
логирует** сырой HTTP-body по умолчанию. Надёжные способы:

- лог движка/llama-swap на стороне сервера (виден входящий
  `reasoning_effort` / `chat_template_kwargs`);
- воспроизведение того же тела через `curl` к `http://localhost:8080/v1/chat/completions`
  и сравнение ответа;
- `--print-logs` (глобальный флаг opencode) — показывает выбор runtime и
  ошибки стрима (`session/llm.ts:244-275`), но не сам body.

Статус «прямой дамп исходящего тела из самой opencode» — см. «Факт vs
неизвестно».

---

## 6. Готовая конфигурация (recipe)

Полный рабочий фрагмент для локального стека. Ключи моделей = **голые ID**
сервера (см. раздел 1), `baseURL` = `localhost:8080`. Ниже четыре агента,
покрывающие все комбинации reasoning × tools.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",

  "model": "self-hosted/qwen3.8-27b-agent-medium",

  "agent": {
    // reasoning ON + tools ON (основной режим)
    "think-tools": {
      "model": "self-hosted/qwen3.8-27b-agent-medium",
      "reasoningEffort": "medium"          // → тело: reasoning_effort: "medium"
    },

    // reasoning OFF + tools ON
    "nothink-tools": {
      "model": "self-hosted/qwen3.8-27b",
      "reasoningEffort": "none"            // → тело: reasoning_effort: "none"
    },

    // reasoning ON + tools OFF
    "think-notools": {
      "reasoningEffort": "xhigh",
      "permission": { "*": "deny" }        // → в теле НЕТ поля tools
    },

    // reasoning OFF + tools OFF
    "nothink-notools": {
      "reasoningEffort": "none",
      "permission": { "*": "deny" }
    },

    // агент, которому нужны server-side thinking-флаги (chat template)
    "think-preserve": {
      "options": {
        "reasoningEffort": "medium",
        "chat_template_kwargs": { "enable_thinking": true, "preserve_thinking": true }
      }
    }
  },

  "provider": {
    "self-hosted": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Self Hosted",
      "options": {
        "baseURL": "http://localhost:8080/v1"   // было http://192.168.17.69:9000/v1
      },
      "models": {
        // ключи = голые ID endpoint'а (иначе сервер не найдёт модель)
        "qwen3.8-27b":          { "name": "Qwen 3.8 27B Instruct" },
        "qwen3.8-27b-chat-low": { "name": "Qwen 3.8 27B Chat Low" },
        "qwen3.8-27b-chat-medium": { "name": "Qwen 3.8 27B Chat Medium" },
        "qwen3.8-27b-chat-xhigh": { "name": "Qwen 3.8 27B Chat XHigh" },
        "qwen3.8-27b-agent-low": { "name": "Qwen 3.8 27B Agent Low" },
        "qwen3.8-27b-agent-medium": { "name": "Qwen 3.8 27B Agent Medium" },
        "qwen3.8-27b-agent-xhigh": { "name": "Qwen 3.8 27B Agent XHigh" }
      }
    }
  }
}
```

Запуск:

```bash
# reasoning ON,  tools ON
opencode run --agent think-tools "Посчитай число r в слове strawberry"

# reasoning OFF, tools ON
opencode run --agent nothink-tools "…"

# reasoning ON,  tools OFF  + доказательство в JSON
opencode run --format json --thinking --agent think-notools "…"

# CLI-агент должен быть primary: если пометить агент mode:"subagent",
# run упадёт. Либо mode:"all" (дефолт), либо вызывать из сессии через @имя / task.
```

Замечания:

- `reasoningEffort` можно писать и в `options`, и как топовый ключ агента —
  `StructWithRest` сведёт к `options` (раздел 3.1).
- `chat_template_kwargs` кладётся в тело **как объект целиком**. Если сервер
  заменяет его собственным, клиентские ключи будут потеряны — это свойство
  backend'а, не opencode (см. AGENTS.md, профиль ninfer).
- `variant`/`--variant` для qwen бесполезны: `variants()` возвращает `{}`.
- Если хотите, чтобы `model` на сервере точно совпал, можно вместо переименования
  ключей задать явный `"id"`: `"llama/whatever": { "id": "qwen3.8-27b", ... }`.

---

## 7. Версии и доки (Q6)

**Подтверждено по официальной документации** (snapshot 2026-10-17):

- docs/agents, «Additional»: *«Any other options you specify in your agent
  configuration will be passed through directly to the provider as model
  options»* — пример использует `reasoningEffort` / `textVerbosity`. Ровно
  наш случай.
- docs/agents, «Tools (deprecated)»: `tools: {x:false}` ≡
  `permission: {"*":"deny"}`; `true` ≡ `allow`.
- docs/models, «Configure models»: `provider.<id>.models.<model>.options`
  принимает `reasoningEffort`, `textVerbosity` и др.
- docs/config: provider-`options` — `timeout`, `headerTimeout`,
  `chunkTimeout`, `setCacheKey`; `baseURL`/`apiKey` — общие.
- docs/cli: `opencode run --agent/--model/--format/--variant/--thinking`,
  `--print-logs` (глобальный).

**Подтверждено по исходникам `v1.18.35`:** см. разделы 2–4, все пути
`packages/opencode/src/*` и `packages/core/src/v1/config/*`.

**Пакет в локальной машине:** `@ai-sdk/openai-compatible` в
`~/.config/opencode/node_modules/` **отсутствует** — он bundled. Проверять
локально нечего; соответствие bundled-версии (2.0.41) подтверждено по
`package.json` тега `v1.18.35` и grep'ом бинарника
(`assets/02-opencode/binary-grep-evidence.txt`).

**Разрыв версий 2.0.41 → 3.0.7x** (свежий npm): добавился fallback
`reasoning_effort ?? isCustomReasoning(...)` и второй дубль пути
`providerOptionsName`. Схемные поля, pass-through spread и `verbosity`
**не изменились** — рецепт устойчив.

---

## Факт vs неизвестно

### Факты (проверено на этой машине / в исходниках)

- Базовый URL в текущем конфиге неверен; правильный — `localhost:8080`.
- Порт `9000` в стеке не публикуется и не пробрасывается.
- opencode `1.18.35`, bundled SDK `@ai-sdk/openai-compatible@2.0.41`.
- `reasoningEffort` → тело `reasoning_effort`; `textVerbosity` → `verbosity`.
- `chat_template_kwargs` и любые несхемные ключи проходят в тело как есть.
- snake_case `reasoning_effort` перезаписывается и выбрасывается — нужен
  camelCase `reasoningEffort`.
- Agent-опции (в т.ч. любые топовые ключи) мержатся поверх model-опций и
  идут в тело.
- Пустой набор tools ⇒ в теле нет поля `tools`.
- `reasoning_content` **или** `reasoning` в ответе ⇒ SDK превращает в
  `reasoning`-части; в `--format json --thinking` видны как `reasoning`.
- `--agent` в `run` принимает только primary-агента.
- Ключи моделей в текущем конфиге с префиксом `llama/` не совпадают с голыми
  ID сервера.

### Неизвестно / требует проверки

- Дефолтное поведение нашего backend при **отсутствии** `reasoning_effort`
  в теле: считать ли reasoning включённым или выключенным. Клиентский
  `reasoningEffort: "none"` всегда шлёт `reasoning_effort: "none"` — надёжнее,
  чем полагаться на серверный дефолт. (Конкретика — в тикетах оркестратора
  llama-swap.)
- Прямой дамп исходящего HTTP-body **из самой opencode** (нет встроенной
  опции; нужен лог движка, прокси или `curl`-реплика).
- Будет ли `chat_template_kwargs` из клиента перезаписан backend'ом целиком
  (свойство конфига llama-swap `setParamsByID`, не opencode).
- Реальная задержка/поведение при `permission: {"*":"deny"}` на длинных
  диалогах (вне объёма этого тикета).
