# 06 — Effort на стороне агентов

Type: task
Status: unclaimed

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
