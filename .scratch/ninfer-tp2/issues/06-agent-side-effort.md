# 06 — Effort на стороне агентов

Type: task
Status: resolved

## Question

Кто и как выставляет `reasoning_effort`, если сервер больше не задаёт уровень
мышления режимом.

Сейчас в llama-профиле уровень зашит в имя model-ID (`-chat-medium`,
`agent-xhigh`), а агент может его не передавать. В профиле `ninfer` движок
выбирает пресет сэмплирования и режим thinking по выведенному из
`reasoning_effort` режиму, поэтому без `reasoning_effort` агент получит
дефолт движка, а не заявленный в имени режима уровень.

Что решить:

- инвентаризировать потребителей, которые зовут `qwen3.8-27b-chat-*` и
  `qwen3.8-27b-agent-*` (агентские конфиги, `llm-monitoring`, скрипты);
- решить, остаются ли `low|medium|xhigh` в имени как маркер или имена
  упрощаются до единого thinking-режима (это уже breaking change для
  потребителей, см. ADR-0002 про локальные ID);
- проверить фактическое поведение: запрос с `chat-xhigh` без
  `reasoning_effort` и с `reasoning_effort: xhigh` — совпадает ли режим;
- проверить, что `enable_thinking` в `chat_template_kwargs` клиента вместе с
  `reasoning_effort` даёт 401 `conflicting_template_option` и что
  `stripParams`/`setParamsByID` в `ninfer/config.yaml` это не усугубляют.

## Acceptance

- Список потребителей и их model-ID зафиксирован.
- Зафиксировано поведение запроса без `reasoning_effort` (в тикет или в
  research-док).
- Решение по именам режимов принято и отражено в `docs/adr/0003-ninfer-profile-llama-swap.md`
  или новом ADR.

## Answer

### Инвентаризация потребителей

Потребителей model-ID в этом репозитории нет: он содержит только compose,
конфиги и документацию, прикладного кода, тестов и CI нет. Реальные
потребители — внешние:

| Потребитель | Model-ID | Effort | Статус |
|---|---|---|---|
| `~/.config/opencode/opencode.jsonc` — `model` по умолчанию (все агенты) | `self-hosted/llama/qwen3.8-27b-agent-medium` | не передаёт | рабочий, без правок |
| то же, `agent.plan.model` | `self-hosted/llama/qwen3.8-27b-agent-xhigh` | не передаёт | рабочий, без правок |
| `~/.config/opencode/opencode.jsonc:233` — список моделей | `qwen3.8-27b`, шесть `-chat-*`/`-agent-*` | — | описательные записи |
| `llm-monitoring` (`/home/dimmy/projects/00 infra/infrastructure/llm-monitoring`) | не упоминает ни одного model-ID | — | ноль попаданий по `qwen3.8`, `ornith`, `reasoning_effort` |
| `/home/dimmy/projects/00 infra/homelab-chat-history/files/trace_dump_local.py` | через env `MODEL`, по умолчанию чужой стек | кладёт effort в `chat_template_kwargs`, значения `high\|max` | другой API, несовместим: effort в неправильном поле и вне `low\|medium\|xhigh` |
| бэкапы `opencode.jsonc.bak-*` | все шесть алиасов | per-model `reasoningEffort` со значениями `low\|medium\|high\|xhigh\|none` | не активны; `high` профилем не принимается как уровень |

Ни один потребитель не передаёт `reasoning_effort` в `self-hosted`-провайдере,
поэтому при прежней конфигурации `agent-medium` и `agent-xhigh` молча работали
с дефолтом шаблона. Профиль `llm-monitoring` до тикета 08 не в состоянии чинить
ничего из этого: он не знает model-ID вообще.

### Поведение запроса без `reasoning_effort`

Уровень в NInfer — инструкция в системном промпте от chat template артефакта
(`chat_template.jinja:56-67`), а не бюджет токенов, и дефолт шаблона равен
`xhigh` (строка 58). Отсюда: запрос к `chat-xhigh` без effort даёт промпт,
идентичный явному `xhigh` (67 prompt-токенов в обоих случаях), а `medium`
не добавляет инструкции вовсе (25 токенов) и `low` добавляет короткую (55).

Проверено на живом профиле (2026-10-05, v0.4.5):

- без effort против `reasoning_effort: xhigh` на `chat-xhigh` — тот же промпт
  (67/67 токенов на двух разных промптах); расхождение текста ответов
  объясняется тем, что `stripParams` убирает клиентский `temperature`, а движок
  сэмплирует своим пресетом 1.0/0.95/20, и тем, что MTP-драфт вносит
  недетерминизм: три одинаковых greedy-прогона дали три разных хеша в обеих
  группах;
- effort не ограничивает рассуждение: на задаче «лампочки 3×3» `low` закрыл
  рассуждение сам на 12 254 токенах, `xhigh` и дефолт упёрлись в
  `max_tokens: 16000` (finish_reason `length`);
- движок принимает `none, minimal, low, medium, high, xhigh, max, adaptive`
  (ошибка перечисляет все восемь), но непротиворечиво отображает в лог
  `minimal` → `low`, `high` → `xhigh`, `max` → `xhigh`, `adaptive` → `xhigh`;
  опираться следует на `low | medium | xhigh`;
- неизвестное значение → `400 invalid_request_error` с перечислением
  допустимых; не-строка → `400` «must be a string or null»;
- instruct-режим: клиентский `reasoning_effort` любого значения не включает
  thinking, `reasoning_tokens: 0` во всех вариантах.

### `enable_thinking` и 400/401

Прежняя запись в тикете, ADR-0003, research 0009 и AGENTS.md утверждала
401 `conflicting_template_option` на thinking-режимах. Это неверно в двух
местах: HTTP-код 400, а не 401, и на thinking-режимах конфликт не
воспроизводится.

Причина в compose правил llama-swap: `chat_template_kwargs` задан в
`setParamsByID` объектом, а `applyFilters` пишет его через
`sjson.SetBytes(body, "chat_template_kwargs", ...)` — замена объекта целиком,
не слияние по ключам (`internal/server/filters.go:166`, поведение подтверждено
измерением: клиентский `enable_thinking` до движка не доходит). Проверено 11
вариантов клиентских полей × 6 thinking-алиасов — `200` во всех, включая
`reasoning_effort` вместе с `enable_thinking`. Конфликт воспроизводится только
на instruct-режиме `qwen3.8-27b`, где сервер `chat_template_kwargs` не задаёт:
`enable_thinking: true` → `400 conflicting_template_option`, и это происходит
даже без клиентского effort, потому что серверный `reasoning_effort: none`
уже присутствует в теле.

Отдельно проверено, что `stripParams`/`setParamsByID` конфликт не усугубляют:
`stripParams` перечисляет только sampling-параметры, а `reasoning_effort` и
`chat_template_kwargs` в него не входят.

### Решение по именам режимов

Имена сохраняются, и `low|medium|xhigh` в них снова задают уровень на сервере,
как в llama-профиле: `reasoning_effort` добавлен в `setParamsByID` каждого
thinking-алиаса жёстким ключом. Миграция потребителей не требуется, breaking
change не нужен, а `~/.config/opencode/opencode.jsonc` работает без правок.

Основание — расхождение молчаливое в обе стороны: агент без effort получал
`xhigh` вместо запрошенного уровня, а агент с effort мог получить уровень,
противоречащий model-ID, который сам же запросил. Ни одно из расхождений не
диагностируется ни ошибкой, ни строкой лога.

Проверено на профиле с новым конфигом (11 × 6 вариантов): `chat-low` с
клиентским `reasoning_effort: xhigh` даёт `thinking low` и 41 prompt-токен,
`chat-medium` — `thinking medium` и 11, `chat-xhigh` — `thinking xhigh` и 53;
`agent-*` даёт те же уровни с `preserve thinking`; instruct остаётся `thinking
off` при 13 токенах.

Изменения: `ninfer/config.yaml`, `docs/adr/0003-ninfer-profile-llama-swap.md`
(пункт 5 решения и новый раздел «Альтернативы»), раздел «Уровень reasoning на
стороне сервера» в `docs/research/0009-ninfer-tp2-two-5070ti.md`, `AGENTS.md`,
`README.md`, `CONTEXT.md`.

Не проверено: качество ответов на уровнях `low` и `medium` против `xhigh` —
тикет про контракт API, а не про качество; сравнение уровней на llama.cpp уже
делалось отдельно.
