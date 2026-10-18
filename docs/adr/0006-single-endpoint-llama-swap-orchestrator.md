# ADR-0006: llama-swap как общий оркестратор — единый endpoint и клиентский контракт reasoning

Status: accepted (2026-10-17).

## Контекст

До этого решения стек состоял из трёх compose-профилей (`llama`, `ninfer`,
`vllm`), каждый со своим образом и своим набором публичных model-ID
(`qwen3.8-27b` плюс шесть алиасов `-chat-*`/`-agent-*`). Уровень reasoning
задавал сервер (`setParamsByID` по имени алиаса), sampling тоже жил на сервере,
клиентские поля вырезались. Смена движка = пересоздание compose-стека.

Проблемы: потребители (opencode, скрипты) обязаны знать семь ID и уметь
переключать compose-профили; один и тот же клиентский запрос ведёт себя
по-разному на llama.cpp и NInfer (разные фильтры и пресеты); выбор движка
требует docker-операций, а не HTTP-вызова. Исследования контрактов
(`docs/research/0011`–`0013`) показали, что строгое «у сервера нет дефолтов»
недостижимо, но переносимый клиентский контракт возможен.

## Решение

### 1. llama-swap — общий оркестратор, один контейнер, два движка

Один долгоживущий compose-сервис `llama-swap` (каталог `router/`, образ
`llm-server/router:v265`) без compose-профилей. В образе запинены:

- llama-swap **v265** (SHA-256 архива в build-args);
- llama.cpp **b10438** (`ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4…6283`; бамп с b10068 ради обработки `reasoning_effort`, `docs/research/0015`);
- NInfer **v0.4.6** (`ninfer-tp2`, SHA-256 архива).

Оба движка (`llama-server`, `ninfer-serve`) запускаются llama-swap как дочерние
процессы через `cmd`; `docker.sock` не монтируется. Конфиг — `router/config.yaml`
(глобалы, hooks, профили с пинами) + `router/config.d/{10-llama,20-ninfer}.yaml`
(по одному движку на файл). Каталоги `llama/` и `ninfer/` удалены.

### 2. Единый endpoint, ровно один публичный ID

Публичный контракт — один model-ID `qwen3.8-27b` на `http://localhost:8080`.
Движки объявлены записями `backend-llama`/`backend-ninfer` с `unlisted: true` и
закрыты пином `~` в неактивном профиле (прямой запрос → `404`). Непараллельность
гарантирует дефолтная exclusive-группа llama-swap; селекторов нет — swap по
запросу клиента невозможен, переключение только ручное:
`PUT /api/profiles/active {"name":"llama"|"ninfer"}` (или UI llama-swap).

Смена профиля не грузит движок сразу: swap происходит на первом запросе к
`qwen3.8-27b`, и именно он платит загрузку весов (llama.cpp 40–60 c, NInfer
~6 c). На старте активен профиль `ninfer` с прелоадом (`hooks.on_startup`),
поэтому публичный ID есть сразу и не «мигает».

### 3. Reasoning — клиентский; сервер мнения не задаёт

`setParamsByID` не заводится. Голый ID отдаёт дефолт chat template:
**thinking on + effort `xhigh`** на обоих движках. Переносимый клиентский
контракт (проверен на обоих движках — `docs/research/0014`, `0015`):

| Цель | Что слать клиент | Оба движка |
|---|---|---|
| выключить thinking | `chat_template_kwargs: {"enable_thinking": false}` | да |
| уровень reasoning | `reasoning_effort: low\|medium\|xhigh` (top-level или в kwargs) | да |
| выключить thinking через top-level | `reasoning_effort: "none"` | **только NInfer** |

Оговорки: top-level `none` на llama.cpp инертен — CLI-флаг `--reasoning on` в
`cmd` инжектит `enable_thinking: true`, который побеждает ветку `none`
(механизм разобран в `docs/research/0015`, раздел «Механизм инертности `none`»);
поэтому переносимый способ выключить thinking — только kwargs. Невалидное
значение `reasoning_effort` → `500` (llama.cpp) / `400` (NInfer).

opencode v2 управляет reasoning вариантами модели
(`body.chat_template_kwargs`: `off`/`low`/`medium`/`xhigh`) — конфиг
`~/.config/opencode/opencode.jsonc` переведён на этот контракт
(`docs/research/0012`, `0014`).

### 4. Sampling — серверный дефолт движка, клиентское переопределение

Пресет sampling живёт в `cmd` движка: llama.cpp — CLI-флаги
(`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0
--repeat-penalty 1.0` — thinking-пресет, совпадающий с thinking-пресетом
NInfer); NInfer — собственный mode-aware пресет (thinking
`1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5`). CLI-значения —
серверные дефолты, поля запроса их перекрывают. llama-swap тело запроса не
правит, кроме `stripParams: repetition_penalty` на обоих движках и
`useModelName: qwen3.8-27b` на `backend-ninfer` (требование движка:
`request.model == --model-id`).

### 5. Безопасное подмножество параметров клиента

Сводная таблица отчёта `docs/research/0013` (без vLLM) — что можно слать обоим
движкам без риска различного поведения:

| Поле | Переносимый диапазон |
|---|---|
| `temperature` | `[0, 1]` |
| `top_p` | `(0, 1]` (не 0) |
| `top_k` | `1..20` |
| `min_p` | `[0, 1]` |
| `presence_penalty`, `frequency_penalty` | `[-2, 2]` |
| `seed` | любое |
| `max_tokens` | `≥ 1` |
| `reasoning_effort` | `none\|low\|medium\|xhigh` (`high` фолдится в `xhigh` обоими) |
| `chat_template_kwargs.{enable_thinking, preserve_thinking}` | bool |

Запрещено/непереносимо:

- `repetition_penalty` — вырезается llama-swap (`stripParams`; NInfer принимает
  только `1`, llama.cpp такого имени не знает);
- `repeat_penalty` — llama.cpp-only knob (не стрипается), NInfer молча
  игнорирует;
- `top_k: 0` — llama.cpp «выключить», NInfer «cap top-20»;
- `reasoning_effort` вне словаря → `500` (llama) / `400` (NInfer);
- фичи, которые NInfer отклоняет: `response_format: json_object`,
  `logit_bias`, `logprobs`, `strict`, `parallel_tool_calls: false`, named tool
  choice (`docs/serving.md` артефакта).

### 6. `sendLoadingState: false`

Баннер загрузки llama-swap стримится только в `delta.reasoning_content` — канал
зашит в код (`internal/router/loading.go`), настроить нельзя, потребителей
loading-state нет. Непустой `reasoning_content` на первом запросе после смены
профиля был бы ложным reasoning и ломал контракт п. 3, поэтому
`sendLoadingState: false` в `router/config.yaml`. Плата: первый запрос после
переключения молчит 40–60 c (llama.cpp) без in-stream индикатора
(`docs/research/0014`, раздел о `sendLoadingState`; доказательства —
`assets/13-loading-state/`).

## Отвергнутые альтернативы

- **Автоматическое переключение backend'ов** (селекторы, swap по запросу,
  TTL): нарушает «движки никогда не работают параллельно» и делает смену
  движка неявной для клиента; селекторная стратегия `warm` дала бы
  автоматический выбор движка по запросу. Переключение — только ручное
  (условие задачи).
- **vLLM как третий backend за llama-swap**: выведен из карты 2026-10-17;
  файлы `vllm/` не меняются, возврат — отдельный effort, не возврат в эту
  топологию.
- **Сохранение алиасов `-chat-*`/`-agent-*`**: алиасы — это серверное мнение о
  reasoning (`setParamsByID`), противоречащее клиентскому контракту. Удалены
  без backcompat-алиасов — прецедент ADR-0002/0004; миграция внешних
  потребителей выполнена (opencode — на варианты `body.chat_template_kwargs`).
- **Явный instruct-дефолт сервера** (`--reasoning off`/`--no-thinking`):
  против «у сервера нет мнения о reasoning»; голый ID отдаёт дефолт шаблона
  (thinking + `xhigh`), «instruct» — явный клиентский запрос
  (`enable_thinking: false`).
- **Shim в llama-swap** (`reasoning_effort: none` → `enable_thinking: false`):
  невыразим — `filters` llama-swap поддерживают только плоские
  `stripParams`/`setParams` без условного маппинга значений и без перезаписи
  вложенного `chat_template_kwargs` (проверено по `../llama-swap`,
  `internal/config/filters.go`).
- **Документировать no-op вместо бампа llama.cpp** (оставить b10068 и описать
  top-level `reasoning_effort` как no-op): контракт стал бы ложным на половине
  бэкендов, одинаковое тело запроса давало бы разное поведение по профилям.
  Бамп до b10438 закрыл разрыв двумя строками пина (`docs/research/0015`);
  A/B на одном бенчмарке регресса не показало — пин остаётся.

## Последствия

- Потребители: opencode — один ID `llama-swap/qwen3.8-27b` + варианты; launcher
  `llm-monitoring` мапит `llama`/`ninfer` на `llama-swap`; старые ID
  (`qwen3.8-27b-chat-*`/`-agent-*`) и compose-профили `llama`/`ninfer` не
  работают — миграция завершена, backcompat-алиасов нет.
- Косметика, правки не требует: `[ERROR] failed to preload model
  backend-ninfer: status 404` в стартовом логе (у NInfer нет warmup-эндпоинта,
  прелоад — единственный механизм старта движка) и `status: unloaded` у
  пин-записи в `/v1/models` (hardcode llama-swap v265 для пинов). Правдивое
  состояние — `GET /api/profiles`, SSE `/api/events`, `/health` upstream-порта
  (`docs/research/0014`, раздел о preload; `assets/12-ninfer-preload-status/`).
- Красная линия VRAM (≥ 512 MiB свободной на дисплейной GPU1 под пиковой
  нагрузкой) подтверждена на обоих движках (`assets/11-llama-bump/`,
  `assets/15-verify-b10438/`).
- Изменение `router/config*.yaml` требует `docker compose restart llama-swap`;
  обновление движков — новые пины в `router/Dockerfile`/build-args + build.

Опора: `docs/research/0011`–`0015`, доказательства
`.scratch/llama-swap-orchestrator/assets/{04,05,06,07,09,11,12,13,14,15}-*/`.
