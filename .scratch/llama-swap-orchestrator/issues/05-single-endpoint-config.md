# Конфиг единого endpoint'а

Type: grilling
Status: resolved
Blocked by: 02, 03, 10

## Question

Каким ровно должен быть конфиг llama-swap (`llama/config.yaml` /
`ninfer/config.yaml` — или один общий файл, если так решит тикет
«Топология»), чтобы публичный контракт был ровно один ID `qwen3.8-27b`
(режим задаёт клиент, sampling — серверный дефолт движка с клиентским
переопределением)?

> Премиса уточнена тикетом «Остаточное серверное мнение и нормализация»:
> «instruct-режим» и «полный клиентский контроль sampling» сняты — голый ID
> отдаёт дефолт шаблона (thinking + `xhigh`), sampling живёт в `cmd` движка.
> Пункты 1 и 2 решены там; здесь остаётся их конфиг-выражение.

Решить по каждому backend'у:

1. **Фильтры.** Решено в тикете 10: на обеих backend-моделях
   `stripParams: repetition_penalty`, на NInfer обязателен
   `useModelName: qwen3.8-27b`; больше тело запроса не правится. Записать
   точный состав `filters` по backend'ам.
2. **Дефолт голого ID и пресет sampling.** Дефолт голого ID решён в тикете
   10: дефолт шаблона, `setParamsByID` не заводим. Здесь — **пресет
   sampling**: точные флаги `cmd` для llama.cpp (`--temp/--top-p/--top-k/
   --min-p/--presence-penalty`), судьба `repeat_penalty 1.05` (NInfer
   принимает только `1.0`) и подтверждение, что NInfer-пресет не трогаем.
3. **Единственный ID и `name`.** Что показывать в `/v1/models`; убрать ли
   суффиксы backend'а/версии из `name`; как это сочетается с пинами и
   `unlisted` у моделей `backend-*`.
4. **Backend-специфичные дельты.** `useModelName` (NInfer), `capabilities`
   (vision, tools, context), `--parallel`, `--ctx-size` — остаются ли как
   есть или меняются.
5. **Совместимость с opencode.** Проверить конфиг против рецепта из тикета
   «opencode: управление reasoning и tools»: сможет ли opencode выставить
   reasoning и tools на этом единственном ID.

## Answer

Разрешено живым обсуждением с человеком (HITL, 2026-10-17). Опора — решения
тикетов «Остаточное серверное мнение и нормализация» (10), «Топология…» (04),
«Выбор версии образа llama-swap» (09), отчёты `docs/research/0013`, `0011`,
`0012`. Проверки схемы/семантики — по `../llama-swap@a2796fb` (v264+, схема
v265): `internal/config/merge.go` (слияние `-config-dir`),
`internal/server/filters.go:114-172` (`resolveFilters` через
`RealModelName`, порядок `useModelName → stripParams → setParams`),
`docs/kb/guides/routing/profiles-and-selectors.md`,
`docs/kb/guides/model-runtime/capabilities-and-model-listings.md`.

### Раскладка файлов (из тикета 04)

```
router/
  config.yaml            # глобалы + hooks + profiles (пины)
  config.d/10-llama.yaml # models.backend-llama
  config.d/20-ninfer.yaml# models.backend-ninfer
```

`profiles` и `models` — identity-map'ы при слиянии `-config-dir`
(`merge.go:17-26`): один и тот же ключ в двух файлах — жёсткая ошибка, поэтому
профили живут ровно в одном файле (`config.yaml`), а движки — по одному на
файл. Глобальные ключи задаются один раз.

### `router/config.yaml`

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json
healthCheckTimeout: 600   # максимум прежних 300 (llama) / 600 (ninfer); отсчёт сбрасывается на прогрессе загрузки
logLevel: info
logToStdout: both
sendLoadingState: true

hooks:
  on_startup:
    profile: ninfer          # публичный ID есть сразу после старта, не «мигает»
    preload:
      - backend-ninfer       # тёплый на старте NInfer; только один движок (exclusive-группа)

profiles:
  llama:
    description: "llama.cpp active (single public ID qwen3.8-27b)"
    pins:
      qwen3.8-27b: backend-llama
      backend-ninfer: ~      # неактивный движок запрещён (404), не только спрятан
  ninfer:
    description: "NInfer TP=2 active (single public ID qwen3.8-27b)"
    pins:
      qwen3.8-27b: backend-ninfer
      backend-llama: ~
```

`globalTTL` не задаём (0 — движок не выгружается по простою). `includeAliasesInList`
удалён: алиасов больше нет. `store.path` не задаём: `capabilities` объявлены
явно, in-memory кэш дискавери не нужен.

### `router/config.d/10-llama.yaml`

```yaml
models:
  backend-llama:
    name: "llama.cpp"
    unlisted: true
    env:
      - LD_LIBRARY_PATH=/app:/usr/local/cuda-13.3/lib64
    cmd: >
      /app/llama-server --host 127.0.0.1 --port ${PORT}
      --model /models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf
      --mmproj /models/Qwen3.8-27B-NVFP4-MTP-GGUF/mmproj-BF16.gguf
      --mmproj-offload
      --n-gpu-layers 999
      --split-mode tensor
      --tensor-split 50,50
      --ctx-size 180224
      --parallel 1
      --cache-type-k q8_0
      --cache-type-v q8_0
      --cache-ram 40960
      --cache-idle-slots
      --batch-size 2048
      --ubatch-size 512
      --threads 8
      --flash-attn on
      --fit off
      --jinja
      --reasoning on
      --temp 1.0
      --top-p 0.95
      --top-k 20
      --min-p 0
      --presence-penalty 0
      --repeat-penalty 1.0
      --spec-type draft-mtp,ngram-mod
      --spec-draft-type-k q8_0
      --spec-draft-type-v q8_0
      --spec-draft-n-max 4
      --spec-draft-p-min 0.75
      --spec-ngram-mod-n-match 20
      --spec-ngram-mod-n-min 4
      --spec-ngram-mod-n-max 48
    capabilities:
      in: [text, image]
      out: [text]
      tools: true
      context: 180224
    filters:
      stripParams: "repetition_penalty"
```

### `router/config.d/20-ninfer.yaml`

```yaml
models:
  backend-ninfer:
    name: "NInfer TP=2"
    unlisted: true
    useModelName: qwen3.8-27b
    env:
      - LD_LIBRARY_PATH=/opt/ninfer/lib:/app:/usr/local/cuda-13.3/lib64
    cmd: |
      /opt/ninfer/bin/ninfer-serve
      /models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/qwen3_8_27b_nvfp4.ninfer
      --host 127.0.0.1
      --port ${PORT}
      --model-id qwen3.8-27b
      --tp 2
      --devices 0,1
      --kv-dtype nvfp4
      --max-context 262144
      --kv-capacity auto
      --vram-headroom-mib 640
      --max-concurrency 2
      --device-state-slots 4
      --spec dflash2
      --draft-tokens 7
      --lm-head-draft
      --vision
      --vision-device 0
      --max-vision-tokens 4096
      --embedding-host
      --default-max-tokens 16384
      --pending-timeout-ms 600000
    capabilities:
      in: [text, image]
      out: [text]
      tools: true
      context: 262144
    filters:
      stripParams: "repetition_penalty"
```

### 1. Фильтры — ровно `stripParams: repetition_penalty`, без `setParamsByID`

- Обе backend-модели: `stripParams: "repetition_penalty"`. Других фильтров нет,
  `setParams`/`setParamsByID` не заводятся.
- Выбрано (решение человека) **только** `repetition_penalty`, без второго имени
  `repeat_penalty`. Следствие, принятое сознательно: knob остаётся достижим для
  клиента под llama.cpp-именем `repeat_penalty` (движок применит, перекрыв
  серверный `--repeat-penalty 1.0`); NInfer неизвестное поле игнорирует молча.
  Это непереносимость, а не ошибка, и она уходит в таблицу safe-subset тикета
  08 как «`repetition_penalty` стрипается; `repeat_penalty` — llama.cpp-only,
  NInfer игнорирует».
- `useModelName: qwen3.8-27b` — **только** на `backend-ninfer` (требование
  движка: `request.model == --model-id`). `backend-llama` его не несёт:
  под пином запрос приходит как `qwen3.8-27b`, а llama-server имя модели не
  проверяет; фильтры резолвятся по `RealModelName(requested)`
  (`filters.go:114-125`), поэтому запрос под пином получает фильтры целевой
  backend-модели.
- Никакого другого правления тела нет: reasoning (`reasoning_effort`,
  `chat_template_kwargs`) и sampling идут от клиента как есть.

### 2. Пресет sampling и дефолт голого ID

- **llama.cpp**: серверный пресет — CLI-флаги в `cmd`:
  `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0
  --repeat-penalty 1.0`. Это thinking-пресет (голый ID = thinking+xhigh,
  дефолт шаблона), совпадающий с thinking-пресетом NInfer; `--repeat-penalty
  1.0` выбран вместо сегодняшних `repeat_penalty 1.05`, потому что NInfer
  принимает только `1.0` — так пресет переносим. CLI-значения — серверные
  дефолты, поля запроса их перекрывают (отчёт 0013; `server-schema.cpp`).
- **NInfer**: пресет не трогаем — движок сам выбирает mode-aware
  (thinking `1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5`) по
  выведенному режиму thinking; sampling-флагов в `cmd` нет.
- **Дефолт голого ID**: `setParamsByID` нет; llama.cpp `--reasoning on`,
  NInfer без `--no-thinking` → голый `qwen3.8-27b` = thinking + effort `xhigh`
  (дефолт шаблона) на обоих движках. Явное «instruct» — клиентский
  `reasoning_effort: "none"` (или `enable_thinking: false`).
- Принятая асимметрия: non-thinking пресет `0.7/0.80/20/0/1.5` доступен как
  серверный дефолт только у NInfer; на llama.cpp его задаёт клиент.

### 3. Единственный ID и `name`

- `/v1/models` под активным профилем показывает **ровно** `qwen3.8-27b`
  (синтетическая запись из пина: `name` пустой, `capabilities`/`context_length`
  отсутствуют, `meta.llamaswap.type = profile`, `status: unloaded`) — как
  решено в тикете 04. Суффиксов backend'а/версии в публичном ID/`name` нет.
- `backend-llama`/`backend-ninfer` — `unlisted: true` (не видны снаружи) с
  короткими описательными `name` (`llama.cpp`, `NInfer TP=2`) для
  UI/`/api/models` и логов; под неактивным профилем дополнительно закрыты
  пином `~` (404).
- Алиасов (`-chat-*`/`-agent-*`) больше нет: режим задаёт клиент, поэтому
  `includeAliasesInList` удалён. Публичный ID достижим только при активном
  профиле; `hooks.on_startup.profile: ninfer` гарантирует, что он есть всегда.

### 4. Backend-специфичные дельты

- `--parallel 1`, `--ctx-size 180224`, spec-декод, `--split-mode tensor`
  (`backend-llama`) — **как есть**, без перемеров.
- `capabilities` объявлены явно у **обоих** (решение человека): llama —
  `in: [text, image]`, `out: [text]`, `tools: true`, `context: 180224`; ninfer —
  то же с `context: 262144`. Это снимает зависимость от in-memory
  автодискавери (`/props` у llama-server, у NInfer ничего не читается) и от
  отсутствия `store.path`.
- `env` пер-модельный (обязателен, тикет 04): у `backend-ninfer`
  `/opt/ninfer/lib` **первым** (у бинарника нет RPATH, иначе подхватывает
  `libcudart.so.13` из CUDA 13.3); у `backend-llama` — `/app` и CUDA 13.3.
- `useModelName` — только ninfer (см. п. 1).

### 5. Совместимость с opencode (проверка против рецепта тикета 02)

Да, единственный ID управляем со стороны opencode:

- `reasoningEffort` → тело `reasoning_effort`, `chat_template_kwargs` → тело
  как есть; оба движка их принимают, фильтры их не трогают → opencode задаёт
  reasoning сам (thinking on/off и effort) на обоих backend'ах.
- Tools: opencode включает/выключает набор инструментов
  (`permission: {"*":"deny"}` ⇒ в теле нет `tools`); llama backend с `--jinja`,
  NInfer — оба умеют tool calls; `capabilities.tools: true` нужен только для
  листинга.
- Sampling: opencode SDK не шлёт `top_k`; `temperature`/`top_p`/`min_p`/
  `presence_penalty` идут от клиента и перекрывают серверный пресет — ровно
  «дефолт движка + клиентское переопределение».
- Значения effort/сэмплинга у клиента должны лежать в safe-subset тикета 08
  (`none|low|medium|xhigh`; не `high|minimal|max|adaptive` — llama.cpp 500;
  `top_k` не `0`).
- Публичный ID виден opencode стабильно (активный профиль с startup), поэтому
  модель не «мигает» в списке провайдера. Правка самого
  `~/.config/opencode/opencode.jsonc` (baseURL `:8080`, голые ID, дефолтный
  агент + `plan`) — тикет 06.

### Что это меняет в других тикетах

- **Тикет 06** (реализация): в `filters` действительно остаётся только
  `stripParams: repetition_penalty` + `useModelName` (у ninfer); точные
  `cmd`/`capabilities`/`env`/`name` — выше. Правка потребителей.
- **Тикет 08** (документация): safe-subset дополнить строкой про
  `repeat_penalty` (llama.cpp-only, NInfer игнорирует) и зафиксировать
  «пресет sampling — CLI-флаги `cmd` llama.cpp + mode-aware пресет NInfer»;
  процедура переключения — `PUT /api/profiles/active` (из тикета 04, не
  compose-профили).

### Непроверенное

- Схема/семантика сверены с локальным `../llama-swap@a2796fb`, но живой
  `-validate` собранного `router/`-конфига и загрузка движков на GPU — тикеты
  06/07.
- Пин `~` на неактивный backend и единый ID в `/v1/models` проверены на
  фиктивных backend'ах (тикет 04), не на реальном конфиге.
