# Тикет 14 — consumer-конфиг opencode v2

Дата: 2026-10-17. Клиент opencode v2.0.32. Активный профиль llama-swap:
`ninfer` (проверка на одном движке — достаточна, контракт вариантов
переносим на оба, см. тикеты 07/11 карты).

## Что здесь

| Файл | Что |
|---|---|
| `opencode.jsonc` | новый consumer-конфиг (как он был собран; JSON без комментариев) |
| `opencode.jsonc.installed` | точная копия установленного `~/.config/opencode/opencode.jsonc` (JSONC с комментариями) |
| `tap-proxy.py` | копия пишущего reverse-proxy из `assets/07-verify/` (TAP_PORT/TAP_LOG_DIR) |
| `analyze.py` | сводка tap-логов: kwargs в теле, tools, длины reasoning/content |
| `tap-summary.txt` | сводка всех захваченных запросов |
| `tap/` | сырые `*.req.txt` / `*.resp.txt` / `*.meta.txt` |

## Метод

Изоляция от рабочего конфига: `HOME=/tmp/opencode/t14/home`,
`XDG_DATA_HOME`, `XDG_CACHE_HOME`, `OPENCODE_CONFIG=<тестовый конфиг>`,
cwd `/tmp/opencode/t14/work`. Порт managed service разведён через
`opencode service set port 49990` в изолированном HOME (дефолтный 49374 занят
живой сессией opencode). ВАЖНО: managed service читает конфиг при старте и
живёт между CLI-вызовами — после смены `OPENCODE_CONFIG` нужен
`opencode service stop`, иначе прогон уйдёт в старый конфиг (здесь это дало
ложный «прогон мимо tap», см. tap-записи 001–003/004).

Весь HTTP — через tap `127.0.0.1:8091` → `127.0.0.1:8080` (baseURL в тестовой
копии конфига подменён sed'ом; установленный конфиг указывает на
`http://localhost:8080/v1` напрямую).

## Результаты (ninfer активен)

| Прогон | тело запроса | reasoning_content |
|---|---|---|
| `-m …#off` (агент, tools=12) | `chat_template_kwargs:{enable_thinking:false}` | **0** |
| `-m …#medium` (агент, tools=12) | `chat_template_kwargs:{reasoning_effort:"medium"}` | 54 |
| `-m …#xhigh` (агент, tools=12) | `chat_template_kwargs:{reasoning_effort:"xhigh"}` | 138 |
| корневой `model: …#medium` без `-m` | kwargs=null (вариант игнорирован) | 133 (голый ID = thinking+xhigh) |

- `opencode models` на новом конфиге: резолвятся и `llama-swap/qwen3.8-27b`,
  и модели deprecated-блока `provider` (`self-hosted/...`) — coexistence
  `provider` + `providers` работает.
- Корневой `model` с `#variant` игнорируется (подтверждено на v2.0.32,
  согласуется с research 0014) → в конфиге корневая модель без варианта.
- Инструменты: агентский запрос уходит с `tools` (12), title-генератор — без.

## Установленный конфиг

`~/.config/opencode/opencode.jsonc` переписан (бэкап рядом:
`opencode.jsonc.bak-ticket14`). Структурные изменения против бэкапа — только:

- `model`: `self-hosted/qwen3.8-27b` → `llama-swap/qwen3.8-27b`;
- `agent.plan`: модель перенаправлена, мёртвый `reasoningEffort: xhigh` удалён;
- удалена запись `provider.self-hosted.models.qwen3.8-27b` (была сломана
  маршрутизацией: baseURL шлюза `192.168.17.69:9000`, где такого ID нет);
- добавлен `providers.llama-swap` (v2-форма) с 4 вариантами на
  `body.chat_template_kwargs`;
- блоки `provider.self-hosted` (остальные модели), `provider.openai` —
  без изменений.
