# Совместимость API Strata с агентами

Status: resolved
Type: research

## Question

Стоить ли конфигурацию агент-тестов и оценивать годность Strata для агентов — нужны
факты о его API:

- OpenAI Chat Completions + `/v1/responses` (Responses API): какие фичи реально работают
  (streaming, tool calls, structured outputs, logprobs)?
- Tool calls: подтверждено на Flash-Next? Формат (xml/парсер), известные баги с
  opencode/agent-инструментами (поиск по issues).
- Reasoning: какие уровни (`off/low/medium/high`) и через какое поле (`reasoning_effort`,
  `chat_template_kwargs`); как мапится на наш контракт `low|medium|xhigh` /
  `enable_thinking: false`; поведение при невалидных значениях (400/500).
- Контекст: подтвержденные потолки и поведение длинных промптов «первое сообщение
  читается целиком ~1 минута/30k токенов, follow-up отрывками» — как это сказывается
  на агентских циклах (короткие шаги после длинного первого промпта).
- `parallel: 2` batching — статус и ограничения.
- Именование модели в `/v1/models`, аутентификация (any key).
- Vision: включение, серверные требования, работает ли через API агентского инструмента.

Источники: docs/DETAILS.md, docs/BATCHING.md, docs/MCP_SERVER.md репо Strata, тесты
`tests/`/`serve/` в репо, GitHub issues по «tool calls», «opencode», «responses api».

Доставить: матрица совместимости для агентских нагрузок + гэп-лист (что не работает /
известные обходы).

## Answer

Матрица по состоянию репо на 2026-10-17/18 (актуальные релизы движка 0.1.39–0.1.45; ветка
main активно движется, docs обновляются от тикетов). Источники: README «Using it»,
docs/DETAILS.md (секции API / Responses API and Codex CLI / Tools from MCP servers /
Images / JSON response formats / Troubleshooting), docs/BATCHING.md,
docs/TROUBLESHOOTING.md; issues/PR: #451/#759, #543, #592, #675, #754/#804, #843, #1058,
#1059, #1627, #1703, #2130/#2343, PR #1916; release notes 0.1.39–0.1.45.

### 1. Endpoints и матрица фич

| Фича | `/v1/chat/completions` | `/v1/responses` | Anthropic `/v1/messages` |
| --- | --- | --- | --- |
| Streaming | да: thinking → `reasoning_content`, ответ, tool calls (имя, потом аргументы по частям); keep-alive во время чтения длинного промпта; `return_progress: true` (opt-in) даёт `prompt_progress {total, cache, processed, time_ms}` в чанке с пустым delta | да, официальные события: `response.created`, `response.in_progress`, `output_item.added`, `response.reasoning_text.delta`, `response.output_text.delta`, `response.function_call_arguments.delta`, `output_item.done`, `response.completed/incomplete/failed`; при длинном промпте `response.in_progress` каждые 15 с (Codex считает активностью) | да, thinking в `thinking`-блоках |
| Tool calls | да (см. разд. 3), streaming tool calls подтверждены docs и Codex-тестом | да: `function`-tools, `namespace`-tools (модель видит `namespace.name`, call возвращается с namespace), `custom` (free-form input); replay `function_call(_output)` items | да (`tool_use`-блоки; баг «call внутри thinking» #804/#754 зафиксирован в 0.1.40) |
| Structured outputs | `response_format` `json_object`/`json_schema`: schema prompting + серверная валидация, НЕ constrained decoding; root схемы только `object` (иначе `400`); нарушение формата → `502` с `error.code: structured_output_failed`; полная валидация — только при установленном пакете `jsonschema` (setup его не ставит), без него проверка «валидный JSON object» + одноразовое предупреждение; в SSE ответ буферизуется и отдаётся после валидации; **совместное использование с tools/MCP отвергается явно**; статус фич — `/v1/status.structured_output` | `text.format` `json_schema`/`json_object` — тот же механизм «checked, not constrained» | не заявлено |
| `logprobs`/`top_logprobs` | PR #1916 (2026-10-11, CUDA/HIP-движок): OpenAI-совместимые `choices[0].logprobs.content` вкл. thinking; НЕ покрывает Responses, Anthropic и `--parallel` batch slots; мерж в main на 18.10.2026 не подтверждён (#675: раньше поле молча игнорировалось) | нет | нет |
| `logit_bias` | opt-in на поддерживающих CUDA/HIP без батчей (LOGIT_BIAS.md); issue #1627 (открыт): поле принималось, но эффекта нет — проверить на живом сервере | нет | нет |
| Прерывание стрима | закрытие соединения реально останавливает модель, следующий запрос стартует сразу | да | да |
| Спец-поля Strata | `strata_checkpoint: false` (one-shot без чекпоинтов), `strata_prefix` (pin длинного документа), `strata_mcp: true` (серверные MCP-инструменты), `reasoning_budget_tokens` | `include: ["reasoning.encrypted_content"]` (opaque base64, не зашифрован), `client_metadata["x-codex-turn-metadata"]` (`thread_title` opt-in, `session_id` для `codex_compaction_cache`) | — |

`GET /v1/models` показывает только загруженную модель с context limit и input modalities.
`GET /props` — оригинальный chat template, `chat_template_caps` (supports_tools /
supports_tool_calls / supports_parallel_tool_calls / supports_preserve_reasoning —
проверяются реальными probe-рендерами при загрузке шаблона, это подсказки клиенту).
В отличие от llama-swap, никаких «unloaded» записей нет: один процесс — одна модель.

### 2. Reasoning

Поля и уровни:
- OpenAI (chat): `"reasoning_effort"` top-level — `none | low | medium | high`; дефолт модели
  без параметра — `high`. Также принимаются `"reasoning": {"effort": ...}` и
  `"chat_template_kwargs": {"enable_thinking": false}`.
- Anthropic: `"output_config": {"effort": low|medium|high}`; `"thinking": {"type":"disabled"}`
  или `{"type":"enabled","budget_tokens":N}` (<2K = low, <8K = medium, выше = high;
  с 0.1.45 budget также буквально ограничивает thinking).
- Responses: `reasoning.effort` = `none/minimal`, `low`, `medium`, `high/xhigh`; без него —
  конфиговый `reasoning_effort` (учитывается начиная с 0.1.44+, release note;
  `reasoning_effort: false` = off).
- Дефолт — trained-level модели `high` (в `serve/server.py` константа EFFORT_TEXT несёт
  low/medium/xhigh, но публичная таблица chat-пути перечисляет только none/low/medium/high;
  `xhigh` в docs фигурирует только на Responses-пути и в механизме recovery).

Маппинг на наш контракт (`low|medium|xhigh` + `enable_thinking: false`):
- `low`/`medium` — прямое 1:1 через top-level `reasoning_effort` (opencode v2:
  `options.reasoningEffort`, variants).
- `enable_thinking: false` — канонический выключатель off-варианта; эквивалент
  `reasoning_effort: "none"`.
- `xhigh` на chat-пути официально не подтверждён docs'ом. Обход:
  variant `high` (поведение близко: high тоже может думать очень долго) или серверный дефолт
  `"reasoning_effort": "xhigh"` в `strata-<model>.json` вне `args` (ключ конфига принимает
  это значение, #1641). Гэп для живого теста, не блокер.
- Поведение при невалидных значениях (400/500) в docs не описано — поле `reasoning_effort`
  вне словаря не упоминается; проверить на живом тесте (как некогда у NInfer 400).

Уровни — инструкции, а не бюджет токенов (как у нас). Управление «бюджетом»:
- `reasoning_budget_tokens: N` (OpenAI и Anthropic): на N-м токене thinking закрывается
  короткой wrap-up строкой, ответ продолжается оттуда (промпт не перечитывается).
- 0.1.45 «answer_room»: при thinking on и `max_tokens >= 1024` сервер резервирует четверть
  капа на ответ (8192 → thinking до 6144 + ответ 2048) — агенты, шлющие полный
  `max_completion_tokens`, больше не теряют ответ mid-thinking.
- `reasoning_close_retry: true` (opt-in, #1053): ответ, закончившийся одной фразой reasoning
  без ответа и без tool call, продолжается один раз с закрытым thinking.
- `reasoning_loop_recovery: "stop"|"recover"` (opt-in, #728): детекция зацикленного
  reasoning раз в 512 токенов; `recover` продолжает с подменённой low-инструкцией и
  temperature >= 1.0, presence >= 1.5 (учитывать для воспроизводимости).
- `effort_position: "end"` (opt-in, 0.1.39, #458): смена усилия между агентскими шагами
  (переключение `none` на быстром шаге → `high` дальше) не перечитывает промпт.
- `anthropic_thinking: "on_request"` (opt-in, 0.1.32): запросы `/v1/messages` без явного
  thinking рендерятся без него (Claude Code helper-вызовы).
- `repeat_stop_tokens` (0.1.39, #606): ответ, повторяющий один токен 256 раз подряд,
  завершается с `finish_reason "length"` — защита от деградации длинного reasoning.
- NaN-guard (#879, включён по умолчанию): отравленная сессия сбрасывается, запрос до
  начала ответа повторяется прозрачно один раз.

### 3. Tool calls (формат, баги, opencode)

- Внутри модели — собственный XML-подобный формат вызова; сервер сам его парсит и
  возвращает API-клиенту стандартные OpenAI `tool_calls` / Anthropic `tool_use`.
  `supports_tools`/`supports_tool_calls` (в `/props`) проверяются probe-рендерами:
  определения инструментов и инструкции XML-формата, вызовы в истории в формате Strata
  с сохранёнными результатами.
- Streaming: имя инструмента → аргументы по частям (OpenAI/Anthropic-стиль).
- `tool_choice` (Responses): `"none"` скрывает инструменты, всё остальное — модель
  выбирает сама. Принудительный вызов конкретного инструмента (named/forced tool
  choice) не поддержан — тот же известный гэп, что на NInfer в нашем стеке.
- Parallel tool calls (несколько вызовов в одном assistant turn) поддержаны
  (probe `supports_parallel_tool_calls`).
- Баги/фиксы, релевантные opencode:
  - #843 (репорт от opencode-клиента, v0.1.39): пустой assistant turn (только reasoning,
    без текста и вызова) учит модель «имитировать» — следующие turns закрываются без
    tool-вызова, агент «зависает» (0–6/20 успешных вызовов; с фиксом 20/20). Исправлено
    в 0.1.40: сервер выбрасывает пустые assistant turns при рендере истории
    (`STRATA_KEEP_EMPTY_TURNS=1` возвращает старое поведение).
  - #804/#754 (Pi, Anthropic-путь): tool call целиком внутри thinking приходил как
    `end_turn` без `tool_use`. Фикс 0.1.40: такой вызов в начале строки вне code fences
    выполняется; 0.1.40.1 (#1058) сузил правило — quoted-вызов внутри thinking
    (и на обрезке max_tokens) остаётся текстом, а не превращается в реальный вызов.
  - #592: некорректная структура `tools` (строка, список имён, объект без name)
    обрывала соединение; с 0.1.39 — чистый `400` с подсказкой на chat и messages.
  - `tool_call_recovery: true` (opt-in): альтернативные формы мутаций
    (`<parameter=NAME>` вместо `<function=NAME>`, JSON внутри блока вызова, второй
    вызов в том же блоке) тоже парсятся; на корпусе 1 462 агентских turns (Claude Code)
    — 98.3% против 92.9% без флага. Для агентских нагрузок разумно включать.
- MCP: серверные MCP-инструменты Strata — только для веб-чата и chat-запросов с
  `"strata_mcp": true`; `/v1/responses` и `/v1/messages` MCP не запускают. opencode
  приносит собственные инструменты — это нормальный путь.

### 4. Длинные промпты и агентские циклы

- Первый промпт читается целиком. Prefill 1.6–2.7k tok/s на типовых сборках (RTX 50,
  Q2_0/IQ2_XS), чтение чанками до 8 192 токенов (`--prefill auto`; opt-in 32 768).
  «~1 мин / 30k токенов» из README — оценка для слабой машины; на хорошей сборке 30k
  занимают 15–25 с. TTFT = длина промпта / скорость prefill.
- Follow-up почти мгновенный: conversation cache — live session плюс до 6 чекпоинтов
  в RAM (старт каждого assistant turn, каждые 16K токенов, вечный root на конце
  system prompt, если он 2048 токенов и больше). В Codex-тесте позже turns переиспользуют
  ~96% промпта, чтение дельты 1–2 с.
- Кэш ломается от точного prefix-match: любые изменения в начале system-промпта
  перечитывают всё. opencode вставляет `<env>` (папка, сегодняшняя дата) в system —
  смена дня/папки перечитывает ~14K токенов каждый переход. Обход Strata:
  `"env_to_user": true` (opt-in) переставляет блок в первый user message и кэш снова
  работает (замер из тикета: 11.9 с → 1.1 с на первый запрос новой сессии при дисковом
  prefix cache). Stamp'ы Claude Code (`cch=...`) пинятся сервером автоматически.
- Side-запросы и sub-agents: по умолчанию живёт одна сессия; интерливинг второго разговора
  отбрасывает warm-сессию первого до 0 reused → полный re-read (#1703: 99.8% → 0%
  на тех же данных; главный вопрос живого теста для opencode с sub-agents). Обход:
  `--conversation-cache-mib N --conversation-cache-slots K` — парковка до K разговоров
  в RAM (resume 50–60 мс; 9,276-токен диалог — 51 мс); дополнительно `--prompt-cache-spread`
  делает чекпоинты геометрическими по глубине, чтобы история, переписанная d токенов
  назад, читалась ~d, а не заново.
- Контекст: потолок задаётся при установке (8K–262K, модельный максимум 262 144; rope
  scaling `yarn` — opt-in эксперимент, замеры до 421–714K). Запрос, не влезающий
  в контекст (prompt + max_tokens), — `400`, никогда не обрезается; `"fit_max_tokens":
  true` укорачивает max_tokens до места (важно агентам, всегда шлющим полный output
  cap; opencode-конфиг из #543 это и рекомендует: `limit.context` = контекст установщика,
  `limit.output` заметно меньше).
- В веб-чате и через API виден прогресс: `GET /status` (reading the prompt / answering),
  лог keep-alive каждые 15 с.

### 5. Batching / `parallel: N`

- Дефолт: 1 запрос за раз, остальные ждут в FIFO. Для opencode с параллельными
  sub-агентами это сериализация — второй запрос декодируется только после первого.
- `"parallel": N` (engine `--batch N`, 2..8) — opt-in batch slots: несколько разговоров
  декодируются в одном verify-окне (по одному токену каждого в окне). Greedy-вывод
  каждого разговора совпадает с solo (tools/batch_test.py); sampled-запросы тянутся
  счётчиком Philox(seed, position) на строку.
- Плата: каждый слот берёт VRAM у expert-cache (около 0.56 GiB на слот
  при 32K/8-bit KV). На 12 GB-карте, где большинство экспертов на CPU, это −9…−24%
  per-request (на 12 GB setup вообще не рекомендует parallel). Win — латентность очереди:
  4-й из 4 запросов стартует через 1.8 с вместо 11.2 с.
- `--batch-mtp` — отдельный opt-in (per-slot MTP-драфты, ~+15% на слое RAM-short).
  Без него разговор в batch-слоте декодирует 1 токен/окно; одиночный запрос
  автоматически возвращается на solo-путь (до 2 раз за запрос).
- Ограничения: repetition/frequency/presence penalties НЕ применяются в batch-окнах;
  admissions один за раз (два длинных промпта читаются подряд); session save/restore
  отвечает `501` при включённом batch.

### 6. Модель-name и apiKey

- Без `api_key` в конфиге принимается ЛЮБОЙ ключ (`apiKey: "none"` — каноничный
  opencode-вариант). С ключом — один, список или `STRATA_API_KEY`; Prometheus
  скрейпер шлёт его как bearer.
- `/v1/models` — единственная загруженная запись (id обычно `strata`, настраивается
  aliases). Запросы с любым именем модели всё равно обслуживаются («Any other name
  is still served») — нет 404 на незнакомое имя; Claude Code на Anthropic-пути требует
  знакомое имя модели, Strata его игнорирует.

### 7. Vision

- Установка с `Images? yes` скачивает mmproj (0.9 GB BF16; Q8_0-вариант рекомендован
  для CPU-encoder) и собирает helper `strata-vision` (llama.cpp mtmd).
- Через API: OpenAI `image_url`-parts (`data:`, `http(s)://`, локальный путь) и
  Anthropic `image`-blocks (base64/url). Форматы JPEG/PNG/BMP/GIF/WebP/TIFF/AVIF
  (WebP/TIFF/AVIF конвертируются в PNG — агентские скриншоты проходят).
- Стоимость: до 1 024 токенов контекста на картинку (640×480 = около 300); GPU-encoder
  0.1–0.5 с/картинку (резервирует около 1.4 GB VRAM, текстовые скорости −2…−8%);
  CPU-encoder примерно 3 с на 300 токенов. `elastic: true` (opt-in) — encoder
  поднимается по первой картинке и освобождает VRAM после 120 с простоя.
- Запрос с картинкой на сервере без `--vision` даёт ERR (раньше, до фикса #1059,
  повисал на 300 с — сейчас чистая ошибка). Vision на AMD под Windows недоступен
  (CPU-encoder Linux/SYCL); на наших NVIDIA-картах работает и GPU-, и CPU-путь.
- #2343: картинка, возвращённая MCP-инструментом, доставляется модели (раньше —
  `[image ... not shown]`). Для opencode-цикла важно: картинка в `tool_result` должна
  приходить как image-часть; base64-строка в text-tool-result разбухает ~0.73 токена
  на байт и убивает контекст.

### 8. Гэп-лист (критично для opencode)

1. `xhigh` на chat-пути не подтверждён docs (только none/low/medium/high); xhigh
   документирован только на Responses. Проверить live; обход — variant `high` или
   server-default `xhigh` в конфиге модели.
2. Невалидные значения reasoning_effort: поведение (400/500) не документировано —
   добавить в живой тест-чеклист.
3. Named/forced tool choice не поддержан (только `none` / auto).
4. `logprobs` — только PR #1916 (chat completions, CUDA/HIP); Responses/Anthropic/batch
   нет. `logit_bias` сомнительна (#1627 открыт: принято, эффект не подтверждён).
5. `json_schema`/`json_object` не совмещаются с tools; в Responses
   `text.format` — «checked, not constrained» (без гарантии грамматики).
6. Batch-слоты без `--batch-mtp`: 1 токен/окно, penalties не применяются; на
   12 GB-классе parallel замедляет одиночные ходы на 9–24%.
7. Vision-запрос без настроенного encoder — ошибка (недавний 300-сек hang по #1059
   исправлен; проверить на актуальной версии).
8. `previous_response_id` недоступен (stateless Responses) — клиенты таскают полную
   историю; выручают conversation cache и `codex_compaction_cache`.
9. Cold re-read при интерливинге разговоров/side-запросов без парковки — конфликт
   с opencode sub-agents и title-вызовами; лечится конфигом кэша.
10. Prefix-cache ломают любые изменения в начале system-промпта (даты, AGENTS.md,
    переупорядочивание tool-описаний): «внезапно» полный re-read; диагностика по строке
    `strata serve: prompt N tokens = X reused + Y read`.

### 9. opencode v2-конфиг (стартовый пункт)

Issue #543 (закрыт в 0.1.38) даёт готовый скелет `opencode.jsonc` в legacy-форме:
provider с `npm: @ai-sdk/openai-compatible`, `baseURL http://127.0.0.1:8080/v1`,
`apiKey: "none"`, `limit.context` = контекст установщика, `limit.output` заведомо
меньше, `options.reasoningEffort` как дефолт и `variants` low/medium/none
(`reasoningEffort` уходит в top-level `reasoning_effort`). С поправкой на наш
opencode v2 (от AGENTS.md): провайдер оформлять как `providers.strata` (v2-форма),
а не legacy `provider`-блок; мапа сохраняется — `reasoningEffort` → top-level
`reasoning_effort`, `enable_thinking: false` опционально через
`body.chat_template_kwargs`. `model` в запросе — любое (сервер всё равно отвечает);
в `opencode.jsonc` стоит проставить `model: "strata/strata"`.
