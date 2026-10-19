# Живой тест reasoning-вариантов Strata через llama-swap :8080 (тикет 03, 2026-10-19)

Стек: профиль strata-iq3 (потом strata-iq2 — spot), юнит active, запросы через
`http://localhost:8080/v1/chat/completions` (публичные ID; путь llama-swap →
shim → нативная Strata :8081). Проверяются (а) top-level `reasoning_effort`,
(б) `chat_template_kwargs.reasoning_effort`, (в) `chat_template_kwargs.enable_thinking`,
словарь движка и поведение `xhigh`. Температура 0. Поле `model` ответа — native
canon (`qwen3.8-flash-next-iq*_…`) — не сверяем, это задокументировано в тикете 01.

## Серия 1 — strata-iq3, промпт «Саша и Лена … 48 грибов» (max_tokens 600)

| запрос | HTTP | reasoning | content | описание |
|---|---|---|---|---|
| top-level `reasoning_effort: none` | 200 | 0 chars | 19 chars | instruct, без reasoning |
| top-level `low` | 200 | 153 chars | 29 chars | reasoning есть, короткое |
| top-level `medium` | 200 | 313 chars | 29 chars | длиннее |
| top-level `high` | 200 | 284 chars | 21 chars | |
| top-level `xhigh` | 200 | 284 chars | 21 chars | как high |
| kwargs `reasoning_effort: none` | 200 | 0 chars | 19 chars | как top none |
| kwargs `low` | 200 | 153 | 29 | как top low |
| kwargs `medium` | 200 | 313 | 29 | как top medium |
| kwargs `high` | 200 | 284 | 21 | |
| kwargs `xhigh` | 200 | 284 | 21 | |
| kwargs `enable_thinking: false` | 200 | 0 | 19 | instruct |
| kwargs `enable_thinking: true` | 200 | 284/344 | 21 | дефолт |

NB при temp 0 присутствует незначительный токен-джиттер (speculative MTP/draft):
одинаковые запросы дают 337 vs 344 reasoning chars, 117 vs 123 completion tokens —
сравнение одиночных сэмплов не строгое.

## Серия 2 — контроль словаря и дефолта (strata-iq3)

- дефолт без полей: HTTP 200, reasoning 344, content «Лена — 12, Саша — 36.», comp=123
- невалидный top effort `banana`: **HTTP 400**, `unknown reasoning effort 'banana': use none, low, medium or high`
- невалидный `null`: **HTTP 400**, то же сообщение
- kwargs `xhigh`: HTTP 200 (поведение дефолта)

## Серия 3 — high vs xhigh, робастное сравнение (strata-iq3)

Сложный промпт (NZ-задача о трёхзначном числе), max_tokens 4000, по 6 сэмплов на effort, temp 0:

- `high`: completion_tokens = 3859 3664 4000 3753 3848 3667 → mean ≈ 3798.5
- `xhigh`: completion_tokens = 3692 3865 3683 3796 4000 3798 → mean ≈ 3805.7

Статистически неразличимы → **xhigh принимается (200), но поведение неотличимо
от high/дефолта**; отдельно не даётся (в конфиге opencode максимум Strata = high).

## Серия 4 — spot strata-iq2 (switch через strata-use.sh)

- top `none`: 200, reasoning 0, полный instruct-ответ (16 груш)
- top `low`: 200, reasoning 193 chars
- top `high`: 200, reasoning 298
- top `xhigh`: 200, reasoning 246 («как high»)
- kwargs `enable_thinking: false` (2+2): 200, reasoning 0, content «4»

## Выводы для opencode.jsonc (модели strata-iq3/strata-iq2)

1. Оба механики доезжают через :8080: top-level `reasoning_effort` llama-swap НЕ съедает; kwargs тоже.
2. Словарь Strata: `none|low|medium|high` (ошибка валидации перечисляет ровно их). `xhigh` → 200, но неотличим от `high`.
3. `off` = top-level `reasoning_effort: "none"` — канон словаря движка, 0 reasoning-content
   (эквивалентен `enable_thinking:false`); в вариантах opencode взят `none`.
4. `chat_template_kwargs.enable_thinking=false` работает, но как рычаг уровня словаря
   избран `none` — единый спецификатор (поле top), меньше сущностей.
5. reasoning_content доставляется: чанк-канал llm-swap не трогает, opencode
   `compatibility.reasoningField: "reasoning_content"` видит мысль (headless-пассы).

Сырьё-скрипты прогонов: /tmp/opencode/strata-variant-test*.sh, strata-iq2-spot.sh (транспорт — curl к :8080).
