# План: ребрендинг llama-профиля с Gemma4 на Ornith-9b

Дата: 2026-08-17.

## Цель

- Убрать устаревшие режимы `gemma4-agent-plan` и `gemma4-agent-code`.
- Заменить имя `gemma4` на `ornith-9b` во всех настройках llama-профиля.
- Удалить устаревший jinja-шаблон `tool_chat_template_gemma4.jinja`.

## Принятые ограничения

- `ornith-9b` короче `ornith1.0-9b`, поэтому выбирается для публичного model-ID.
- Сама модель `ornith-9b-Q8_0.gguf` не переименовывается.
- Jinja-шаблон никуда не монтируется, поэтому удаляется, а не переименовывается.
- Изменяются оба конфига llama-профиля (аргументы ядра и config llama-swap), оба
  сервиса перезапускаются.

## Исходное состояние

- `llama/config.yaml`: ключ модели `gemma4`, режимы `gemma4-thinking`,
  `gemma4-instruct`, `gemma4-agent-plan`, `gemma4-agent-code`.
- `llama/docker-compose.yaml`: `--alias gemma4`.
- `README.md` и `AGENTS.md`: таблицы режимов, алиас, упоминание jinja-шаблона.

## Шаги

1. **`llama/config.yaml`**
   - Удалить режимы `gemma4-agent-plan` и `gemma4-agent-code` из `setParamsByID`.
   - Ключ модели и `name`: `gemma4` -> `ornith-9b`.
   - Режимы: `gemma4-thinking` -> `ornith-9b-thinking`,
     `gemma4-instruct` -> `ornith-9b-instruct` (sampling-параметры без изменений).

2. **`llama/docker-compose.yaml`**
   - `--alias gemma4` -> `--alias ornith-9b` (совпадает с `name` в llama-swap).

3. **Удалить `llama/tool_chat_template_gemma4.jinja`**.

4. **`README.md`**
   - Таблица профилей: `gemma4-*` -> `ornith-9b-*`.
   - Таблица режимов: только `ornith-9b-thinking` и `ornith-9b-instruct`.
   - Структура: убрать упоминание jinja-шаблона.

5. **`AGENTS.md`**
   - Таблица режимов: 2 строки с новыми ID.
   - Алиас: `gemma4` -> `ornith-9b`.
   - Убрать строку про `tool_chat_template_gemma4.jinja`.

6. **Перезапуск**

   ```bash
   docker compose --profile llama restart llama-server llama-swap
   ```

## Тестирование

1. Список моделей — ожидаются `ornith-9b`, `ornith-9b-thinking`,
   `ornith-9b-instruct`:

   ```bash
   curl http://localhost:8080/v1/models
   ```

2. Для каждого из трёх ID отправить запрос «расскажи о себе»:

   ```bash
   curl http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model": "<ID>", "messages": [{"role": "user", "content": "расскажи о себе"}]}'
   ```

3. Проверить: HTTP 200, непустой `choices[0].message.content`, у
   `ornith-9b-thinking` — наличие reasoning, у `ornith-9b-instruct` — его
   отсутствие.