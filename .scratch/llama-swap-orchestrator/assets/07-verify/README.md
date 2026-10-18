# Доказательства тикета 07 — единый endpoint, reasoning × tools

Живая проверка одного публичного ID `qwen3.8-27b` на llama.cpp и NInfer через
opencode-субагентов. Выводы — `docs/research/0014-opencode-single-endpoint-live-verification.md`.

## Два прохода

Разница — в способе, которым клиент задаёт reasoning (см. research 0014).

- `pass1-toplevel-effort/<backend>/` — проход 1: варианты модели через
  `settings: {reasoningEffort: …}` → top-level `reasoning_effort`. Диагностика:
  NInfer слушает, llama.cpp b10068 игнорирует.
- `pass2-kwargs/<backend>/` — проход 2 (итоговый): варианты через
  `body: {chat_template_kwargs: …}`. Одна конфигурация клиента работает на обоих
  движках.

`<backend>` = `ninfer` | `llama` (какой профиль был активен во время прогона).

## Что внутри каталога прохода

| Файл | Что |
|---|---|
| `tap/` | тело каждого запроса (`*.req.txt`), сырой SSE (`*.resp.txt`), тайминги/статус (`*.meta.txt`) |
| `opencode/` | события `opencode run --format json` (`<case>.json`) и stderr |
| `tap-summary.json` | разбор всех пар req/resp (`analyze.py`) |
| `vram.csv`, `vram-min.txt` | свободная VRAM по GPU за прогон и её минимум |
| `ps.txt` | какие движки были живы (доказательство непараллельности) |
| `container.log` | `docker logs llama-swap` |
| `tap.log` | старт tap-прокси |

## Кейсы матрицы (id)

| id | вариант | агент (tools) |
|---|---|---|
| `01-none-notools` | `off` | нет |
| `02-low-notools` | `low` | нет |
| `03-none-tools` | `off` | 12 инструментов |
| `04-medium-tools` | `medium` | 12 инструментов |
| `05-bare-default` | голый ID | нет |
| `06-xhigh-notools` | `xhigh` | нет |

В tap на кейс 2–3 записи: сначала **title generator** (тот же вариант, без
`tools`), затем шаги агента. Реальные шаги агента — там, где системный промпт
начинается с «You are an AI agent running in OpenCode».

## Инструменты

| Файл | Что |
|---|---|
| `tap-proxy.py` | пишущий reverse-proxy `:8090` → `:8080` (`TAP_LOG_DIR`, `TAP_PORT`) |
| `analyze.py` | сводка по каталогу `tap/` → JSON |
| `run-matrix.sh` | матрица прохода 1 |
| `run-pass2.sh` | матрица прохода 2 (+ tap, + сэмплер VRAM, + `docker logs`) |
| `probe-reasoning.sh` | прямые curl-пробы контракта reasoning (`curl-probes/`) |
| `probe-loading-banner.sh` | провокация баннера загрузки (`banner-probe/`) |

## Клиентские конфиги

- `opencode-test.json` — проход 2 (`body.chat_template_kwargs`).
- `opencode-test-pass1.json` — проход 1 (`settings.reasoningEffort`).
- `opencode-test-v2.json`, `probe-agents.json` — черновые конфиги разведки
  поведения opencode v2.0.32.
