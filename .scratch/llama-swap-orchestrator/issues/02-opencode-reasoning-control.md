# opencode: управление reasoning и tools через openai-compatible провайдер

Type: research
Status: resolved
Blocked by: —

## Question

Как в opencode выдать субагенту задачу **с размышлениями и без**, **с вызовом
инструментов и без**, обращаясь к новому единому endpoint'у `qwen3.8-27b`, и
какие ровно reasoning/sampling-параметры opencode умеет передавать в
OpenAI-совместимый провайдер?

Нужны факты по:

1. **Передача reasoning.** Как `@ai-sdk/openai-compatible` и opencode
   конфиг прокидывают `reasoning_effort` и/или `chat_template_kwargs`
   (`enable_thinking`, `preserve_thinking`, `reasoning_effort`) на уровень
   HTTP-запроса `/v1/chat/completions`. Какие поля конфига opencode
   (`provider.*.models.*.options`, `options.reasoningEffort`,
   `chat_template_kwargs`) доходят до тела запроса, а какие нет.
2. **Настройка агентов/субагентов.** Как задать разные reasoning-настройки
   для основного агента и для субагента (`agent.<name>.model`,
   `agent.*.options`), как запустить субагента из CLI и из этой сессии.
3. **Наблюдение результата.** Как доказать, что размышления включены/выключены:
   поле `reasoning_content` в ответе, логи opencode, `--print-logs`, JSON-вывод.
4. **Tool calls.** Как opencode передаёт tools и как проверить, что вызов
   инструмента произошёл (или не произошёл).
5. **Адрес и порт.** Текущий конфиг указывает `baseURL
   http://192.168.17.69:9000/v1`; выяснить, что на `:9000` (форвард на
   WSL `:8080`?) и как правильно нацелить opencode на локальный
   `http://localhost:8080/v1`.
6. **Версия/докой.** Подтвердить по официальной документации opencode
   (https://opencode.ai/docs) и, при необходимости, по локально
   установленным `~/.config/opencode/node_modules/@ai-sdk/openai-compatible`.

## Answer

Отчёт: `docs/research/0012-opencode-reasoning-tools.md`
(сырые артефакты: `.scratch/llama-swap-orchestrator/assets/02-opencode/`).

**Gist.** opencode (1.18.35) собирает `options` из
`provider.<id>.models.<m>.options` + `agent.<n>.options` (плюс любых
неизвестных топовых ключей агента), кладёт их под ключ провайдера в
`providerOptions["self-hosted"]`, и bundled `@ai-sdk/openai-compatible@2.0.41`
разворачивает это в тело `/v1/chat/completions`.

Ключевые факты:

- `reasoningEffort` → тело `reasoning_effort`; `textVerbosity` → `verbosity`.
  Использовать **camelCase** `reasoningEffort` — snake_case
  `reasoning_effort` перезаписывается и выбрасывается.
- `chat_template_kwargs` (объект) и любые несхемные ключи проходят в тело
  **как есть** — так можно слать `enable_thinking` / `preserve_thinking`.
- Agent-опции мержатся поверх model-опций; `StructWithRest` сведёт любой
  топовый ключ агента в `options`.
- Tools ON/OFF = включён ли набор разрешённых инструментов:
  `permission: {"*":"deny"}` ⇒ в теле запроса **нет поля `tools` вообще**.
- Доказательство reasoning: `opencode run --format json --thinking` →
  события `{"type":"reasoning"}`; сервер должен вернуть `reasoning_content`
  **или** `reasoning`. Tool-call: событие `{"type":"tool_use"}`.
- `--agent` в `run` принимает только primary-агента.

**Адрес (Q5):** текущий `baseURL http://192.168.17.69:9000/v1` неверен —
`:9000` стек не публикует. Правильно `http://localhost:8080/v1` (compose
публикует `8080`, port-forward пробрасывает тот же порт, сейчас работает
профиль ninfer). Отдельная ошибка: ключи моделей с префиксом `llama/` не
совпадают с голыми ID сервера — их надо переименовать (или задать явный
`id`). Готовая конфигурация с 4 агентами (reasoning × tools) — в разделе
«Готовая конфигурация» отчёта.
