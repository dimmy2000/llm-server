# Проверка через opencode-субагентов + доказательства

Type: task
Status: resolved
Blocked by: 06, 02

## Question

Подтвердить на живом железе, что новый единый endpoint работает и что клиент
действительно управляет reasoning и может вызывать инструменты.

Матрица (по тикету «Тест scope»): на **llama.cpp и NInfer** прогнать через
opencode субагентов:

1. задача **без** reasoning (thinking off), без инструментов;
2. задача **с** reasoning (thinking on, разные effort по возможности), без
   инструментов;
3. задача без reasoning **с** вызовом инструмента;
4. задача с reasoning **с** вызовом инструмента.

Для каждого прогона зафиксировать доказательства: запрос/ответ
(`reasoning_content` присутствует/отсутствует), факт вызова инструмента,
использованный model-ID и переданные параметры, версию профиля. Убедиться,
что одна и та же конфигурация (без алиасов) даёт разное поведение при разных
клиентских настройках.

Сложить:
- сырые логи/JSON — `.scratch/llama-swap-orchestrator/assets/<дата>/...`;
- отчёт с выводами — `docs/research/NNNN-*.md` (или отдельный
  `docs/tests/NNNN-*`, согласовать с тикетом «Документация»), со ссылками на
  доказательства.

Отметить, что не проверено (например vLLM, если он не попал в обязательную
матрицу).

## Answer

Проверено на живом железе (образ `llm-server/router:v265`, llama.cpp **b10068**,
NInfer **v0.4.6**), клиент — **opencode v2.0.32**, весь трафик писался через
tap-прокси (`:8090`). Отчёт — `docs/research/0014-opencode-single-endpoint-live-verification.md`,
доказательства — `.scratch/llama-swap-orchestrator/assets/07-verify/`
(`README.md` там описывает структуру).

**Матрица закрыта на обоих движках.** Одна задача (`read ./notes.txt`, ответ
`57403`) через единый `qwen3.8-27b`:

- без reasoning + без tools → `reasoning_content` пуст, поля `tools` в теле нет;
- reasoning (effort `low|medium|xhigh`) + без tools → `reasoning_content`
  непуст, длина растёт с effort (llama `102 < 22+81 < 470`, ninfer
  `143 < 28+185 < 294`);
- без reasoning + tools (12) → вызов `read` → финал `57403`;
- reasoning + tools → то же, с reasoning.

**Клиент действительно управляет reasoning, но общий рецепт — только
`chat_template_kwargs`.** Проход 1 (`settings.reasoningEffort` → top-level
`reasoning_effort`) показал: NInfer слушает `reasoning_effort`, а llama.cpp
b10068 **игнорирует его полностью** (в сборке нет обработки:
`git grep reasoning_effort b10068 -- tools/server/` пусто; в образе 0 вхождений
в `libllama-server-impl.so`). Проход 2 (`body.chat_template_kwargs:
{enable_thinking:false}` / `{reasoning_effort: low|medium|xhigh}`) — **одна и та
же конфигурация клиента работает на обоих движках**. Голый ID = дефолт шаблона
(thinking + `xhigh`) на обоих.

**Вызов инструмента управляется полем `tools`:** с tools модель зовёт `read`,
без tools тот же текст печатается как обычный контент и не исполняется.

**Непараллельность подтверждена:** `ps.txt` каждого прогона — ровно один живой
движок (`ninfer-serve` *или* `llama-server`); переключение —
`PUT /api/profiles/active`. Красная линия VRAM на этом прогоне выдержана
(минимум GPU1: ninfer 709 MiB, llama 1501 MiB).

**Не проверено:** vLLM (вне карты), качество `nvfp4` KV, `preserve_thinking` на
одном endpoint, одновременные диалоги в device-state слотах,
`context_length_exceeded`, vision.

**Побочные находки → новые тикеты** (см. ниже): llama.cpp version skew по
`reasoning_effort`; preload 404 + статус `unloaded` у NInfer; баннер загрузки
`sendLoadingState` в `reasoning_content`; opencode v2 не шлёт agent-level
`reasoningEffort`/overlays (влияет на миграцию потребителей).

## Comments

- Проход 1 (`pass1-toplevel-effort/`) оставлен как диагностическое
  доказательство смены подхода; клиентские конфиги обоих проходов
  зафиксированы (`opencode-test-pass1.json`, `opencode-test.json`).

