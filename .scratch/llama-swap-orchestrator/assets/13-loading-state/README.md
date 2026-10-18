# Тикет 13 — `sendLoadingState: false`, баннер больше не в `reasoning_content`

Доказательство живого прогона 2026-10-17 после правки `router/config.yaml`
(`sendLoadingState: true → false`) и `docker compose restart llama-swap`.

## probe-banner-off.sh

1. `PUT /api/profiles/active {"name":"llama"}` — выгружает ninfer, llama.cpp
   не загружен.
2. Сразу стриминговый запрос `qwen3.8-27b`, `enable_thinking:false`,
   `max_tokens:8` — запрос платит загрузку llama.cpp (лог llama-swap:
   `load_model: loading model …` → `model loaded`). Дамп — `stream-cold.sse`.
3. Контроль: второй запрос с thinking on (дефолт шаблона), `max_tokens:3000`.
   Дамп — `stream-thinking.sse`.

## Результат

```
=== stream-cold.sse        (запрос, плативший загрузку движка)
reasoning_content (0 chars): ''
content          (2 chars): 'ok'
=== stream-thinking.sse    (контроль: горячий движок, thinking on)
reasoning_content (72 chars): 'User asks "What is 2+2? Answer briefly." … Final: 4.'
content          (1 chars): '4'
```

- В холодном дампе ноль чанков `reasoning_content` (grep -c = 0), текст баннера
  («llama-swap loading model», remarks, «Done!») не встречается ни в одном поле.
- Контроль показывает, что поле не мёртвое: когда reasoning реально есть у
  модели, он приходит в `reasoning_content` как раньше.

Сравнение с «до»: `assets/07-verify/banner-probe/stream.sse` (banner в
`reasoning_content` при `sendLoadingState: true`).
