# Таблица в docs/benchmarks.md + ссылка из README

Status: claimed
Type: task
Blocked by: 03, 05, 06, 07

## Question

Собрать прогоны тикетов «Прогон: qwen3.8-27b (NInfer)», «Прогон: strata-iq3»
и «Прогон: strata-iq2» в таблицу по скелету тикета «Скелет docs/benchmarks.md и
формат таблицы» (файл `docs/benchmarks.md`):

- заполнить все секции (prefill по глубинам, decode-пробник, parallel decode
  solo vs c2), пометить, где метрики engine-side, а где client-side
  (NInfer без `timings`), флаги контаминации, минимумы VRAM за прогоны;
- добавить ссылку на `docs/benchmarks.md` в `README.md` в одобренном
  тикетом «Скелет docs/benchmarks.md и формат таблицы» месте;
- показать результат пользователю.

Коммит: английский Conventional Commit, только ASCII, subject ≤ 72 символа.

Результат: готовый файл + ссылка, хеш коммита.
