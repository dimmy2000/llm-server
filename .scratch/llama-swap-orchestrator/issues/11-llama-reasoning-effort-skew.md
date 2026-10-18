# llama.cpp `reasoning_effort`: версионный разрыв запиненной сборки

Type: task
Status: resolved

## Question

Запиненный в `router/Dockerfile` llama.cpp **b10068 не обрабатывает
`reasoning_effort` вообще** — ни top-level, ни (частично) как смысловой
переключатель. Найденный тикетом 07 факт:

- живой прогон: top-level `reasoning_effort: none|low|high|xhigh|banana`
  полностью инертен, thinking всегда включён;
- `git grep reasoning_effort b10068 -- tools/server/` — пусто; на локальном
  `../llama.cpp` (`62318cd57`) — 9 вхождений, `tools/server/server-common.cpp:1421`
  (`none` выключает reasoning);
- в образе: `strings libllama-server-impl.so` и `libllama-common.so.0.0.10068`
  содержат `enable_thinking`, но **0** вхождений `reasoning_effort`.

Так запиненный движок нарушает цель карты «клиент управляет reasoning»: часть
клиентов шлёт именно `reasoning_effort` (в т.ч. как его транслирует opencode из
`settings.reasoningEffort`). Отчёт — research 0014, раздел «Версионная
рассинхронизация»; доказательства в `assets/07-verify/curl-probes/llama/` и
`pass1-toplevel-effort/llama/`.

Решить, чем закрыть разрыв:

1. **Бампить образ llama.cpp** до сборки, где `reasoning_effort` есть
   (`server-common.cpp` с `none` → `enable_thinking=false`). Выяснить, с какого
   тега/коммита эта обработка появилась, есть ли там CUDA13-сборка, совместимая с
   `ubuntu:26.04`-базой, и не тянет ли бамп другие изменения шаблона/сигнатур.
   Обновить пин дайджеста в `router/Dockerfile`.
2. **Оставить `chat_template_kwargs` единственным контрактом** и явно
   задокументировать, что top-level `reasoning_effort` под llama-профилем — no-op
   (в `README`/ADR-0006, тикет 08).
3. **Shim в llama-swap**: транслировать `reasoning_effort` → `enable_thinking`
   (для `none`) через `setParamsByID`/фильтры. Проверить, выражается ли это
   конфигом llama-swap без правки кода.

Нужен выбор с обоснованием; найденный факт уже ломает переносимость клиентского
контракта, поэтому решение — часть destination карты.

## Answer

**Решение: вариант 1 — бамп пина llama.cpp `b10068 → b10438`** в
`router/Dockerfile`. Вариант 2 отвергнут, вариант 3 невозможен. Отчёт —
`docs/research/0015-llama-cpp-bump-reasoning-effort.md`, доказательства —
`assets/11-llama-bump/`.

### Пин и его обоснование

```
ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4ef93697f025156849e55b8d6a92ef10b7cae3460bf0cf8a4d6ea6283
```

- Обработка `reasoning_effort` появилась двумя коммитами: `27209a598`
  (первый тег `b10121`; `none` → `enable_thinking=false`) и `7e4c0a968`
  (первый тег `b10434`; остальные значения уходят в шаблон как
  `chat_template_kwargs.reasoning_effort`). Для контракта карты нужны оба.
- `server-cuda13-b10434` ggml-org **не публиковал** (404), поэтому берётся
  `b10438` (`9d57ce456`) — первый опубликованный cuda13-образ с обоими
  коммитами. Публикации проверены анонимным GHCR-token'ом по
  `Docker-Content-Digest`; существующий пин b10068 тем же методом
  воспроизводится байт в байт.
- База та же (Ubuntu 24.04 + CUDA 13.3), путь `/usr/local/cuda-13.3/lib64`
  не меняется; выше брать нельзя — с `b11706` база переезжает на CUDA 13.4.
- Флаги ядра `cmd` (`--spec-type`, `--cache-*`, `--reasoning`, `--fit`,
  `--split-mode tensor`) в b10438 существуют с теми же именами, поэтому
  `router/config.d/10-llama.yaml` не менялся.

### Почему не вариант 2 (документировать no-op)

Контракт тикета 10 («instruct = явный клиентский `reasoning_effort: none`»)
стал бы ложным под llama.cpp; `low|medium|xhigh` остались бы молча
проигнорированными — то есть «клиент управляет reasoning» не выполнялся бы на
половине бэкендов, и потребитель получал бы разное поведение от одинаковых
запросов в зависимости от активного профиля. Бамп закрывает это двумя строками.

### Почему не вариант 3 (shim в llama-swap)

Не выражается конфигом llama-swap (проверено по `../llama-swap`,
HEAD a2796fb): `filters` поддерживают только плоские `stripParams`,
`setParams`, `setParamsByID` (`internal/config/filters.go`) — без условного
маппинга значений и без перезаписи вложенного `chat_template_kwargs`. Перевод
`none → enable_thinking:false` потребовал бы правки кода llama-swap, а жёсткий
`setParamsByID` затирал бы клиентские kwargs — серверное мнение, которое карта
запрещает.

### Проверено живьём (обязательная часть)

Собран образ `router:v265` (`sha256:ef2b6277…`), прогнаны одинаковые сетки
проб на обоих движках через единый `qwen3.8-27b` (`assets/11-llama-bump/`):

| Кейс | llama.cpp b10438 | NInfer v0.4.6 |
|---|---|---|
| top-level `low`/`medium`/`xhigh` | **работает** (191/391/444) | 249/290/328 |
| top-level `none` | **инертно** (441; рендер == bare) | **работает** (0) |
| kwargs `enable_thinking: false` | 0 | 0 |
| top-level `banana` | 500 (raise шаблона) | 400 |
| kwargs `reasoning_effort: none` | 500 | 0 |
| tools (`get_weather`) | работают, thinking on/off | работают |
| VRAM min free (GPU0/GPU1) | 915 / **1171** MiB | 1199 / **710** MiB |

Красная линия VRAM (≥ 512 MiB на дисплейной GPU1) держится; непараллельность
подтверждена `ps.txt`. Предупреждение `spec common_specu: backend offload
failed` в логе — не регресс (есть и в логах b10068 тикета 07).

### Остаточный разрыв и переносимый контракт

`reasoning_effort: "none"` по-прежнему выключает thinking **только на NInfer**.
Ветка `none` в b10438 исполняется (она стирает `chat_template_kwargs.reasoning_effort`),
но `enable_thinking=false` до рендера шаблона не доходит — механизм не
установлен, разбор вынесен в тикет 15. Переносимый контракт (в ADR-0006 и
README через тикет 08):

- выключить thinking: `chat_template_kwargs: {"enable_thinking": false}` —
  оба движка;
- уровень: `reasoning_effort: low|medium|xhigh` top-level или в kwargs — оба
  движка;
- `reasoning_effort: "none"` — только NInfer; невалидное значение: 500
  (llama) / 400 (NInfer).

### Что осталось за пределами тикета

- Производительность b10438 (decode, приём драфта) и матрица opencode-субагентов
  — тикет 15 (пробы этого тикета с базами не сопоставимы).
- Обновление ADR-0006 / README / AGENTS.md / `CONTEXT.md` и все места с
  упоминанием `b10068` (включая `map.md:47`, research 0014:20,88,150,160,270,279)
  — тикет 08.
