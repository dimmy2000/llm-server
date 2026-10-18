# Выбор версии образа llama-swap

Type: grilling
Status: resolved
Blocked by: 01

## Question

Образ `ghcr.io/mostlygeek/llama-swap:cuda13` — это **v240** (без
`profiles.pins`, `selectors`, `globalConcurrencyLimit`), а локальный репозиторий
и документация описывают **v264+**, где пины есть. Топология «все три backend'а
за одним llama-swap с ручным переключением единого ID» опирается на эти
механизмы.

Решить:

1. **Пинить ли более новый образ** llama-swap (собрать/найти версию с
   `profiles.pins`), или остаться на `cuda13` v240 и строить переключение без
   пин-профилей.
2. Если обновлять: какой именно тег/дайджест, откуда берётся (у образа
   `cuda13` теги не фиксируют версию llama-swap; проверить доступные теги и
   release-notes), и как это скажется на профиле `ninfer` (там
   `llama-swap` копируется статически из образа llama-профиля — см.
   `ninfer/Dockerfile`).
3. Если не обновлять: какой fallback-механизм даёт единый публичный ID при
   ручном переключении (ровно одна модель в конфиге на профиль; `peers` без
   `cmd`; перезапуск llama-swap с другим конфигом).
4. Риски обновления: расхождения `config-schema`, поведение `filters`,
   совместимость с vLLM/llama.cpp,NInfer как дочерними процессами.

Опора — отчёт `docs/research/0011-llama-swap-multi-backend-fronting.md`.

> Премиса вопроса уточнена при разрешении: `cuda13` — плавающий тег, сейчас
> он указывает на v265, а не на v240 (v240 — то, что было подтянуто локально);
> vLLM выведен из карты. Детали — в «Answer» и
> `assets/09-llama-swap-version/README.md`.

## Answer

Доказательства: `.scratch/llama-swap-orchestrator/assets/09-llama-swap-version/`
(`README.md`, `run-checks.sh` + `run.log`, `pins-test.yaml`, `pins-test2.yaml`,
`fake_backend.py`).

**Решение.** `profiles.pins` нужны: они дают единый публичный ID
`qwen3.8-27b` поверх двух объявленных моделей в **одном долгоживущем
контейнере llama-swap** (`backend-llama` → llama-server, `backend-ninfer` →
ninfer-serve), переключаемом вручную через активный профиль llama-swap.
Плавающий образ меняем на **свой образ** из двух запиненных компонентов:
llama-swap **v265** (нужен ≥ v241 — именно там появились профили) поверх
llama.cpp **b10068** — той сборки, на которой сняты все текущие замеры
профиля llama.

**Значения пинов.**

- llama.cpp: `ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865bd031283c5f66ff2a82984cdb282ec37484cf2a9bfc7b4cb1f85708e`
  (индекс; amd64-ребёнок — `sha256:1c0cc37edc5f6c0a0aeffcbab85db41d74baa5e238bf78e56f7bd90184e84fea`).
- llama-swap: релиз `v265`, `llama-swap_265_linux_amd64.tar.gz`,
  `sha256=cb1f9a94be05afa129d3c17868f1dd2ca710b919333c7b868239dc31575dcfa1`;
  сверять можно и с `llama-swap_265_checksums.txt` из того же релиза.
- Проверка SHA-256 на сборке — идиома проекта (`NINFER_SHA256` в
  `ninfer/Dockerfile`).

**Почему пинить обязательно.** Плавающий `cuda13` уже уехал: удалённо это
тот же дайджест, что `v265-cuda13-b11706` (`sha256:62f47d09…`, сборка
2026-10-17, llama.cpp `b11706`), а локально запущенный образ —
`v240 (6b5320d)` + llama.cpp `10068 (571d0d540)`. При этом дайджест
локального образа `sha256:3d49d5d9…` в реестре отвечает **404**: то, что
работает сейчас, невоспроизводимо. Последствие для документации: строка
«стоит `ghcr.io/mostlygeek/llama-swap:cuda13`» больше не описывает ни
фактическую версию, ни будущую.

**Почему llama.cpp не едет за роутером.** Ветка `cuda13` собирает образ
`llama.cpp server-cuda13` + релизный бинарник llama-swap по тегу
`v<llama-swap>-cuda13-b<llama.cpp>` (`.github/workflows/containers.yml`,
`docker/build-container.sh`), то есть пинить роутер отдельно от llama.cpp
штатными тегами нельзя. Свой образ развязывает оси: роутер обновляется
осознанно, а провалидированные `--ctx-size 180224`, spec-декод
(`draft-mtp,ngram-mod`), `--split-mode tensor` и запас VRAM на дисплейной
GPU1 остаются валидными без перемеров. Переезд llama.cpp — отдельное
решение, не эта карта.

**Проверено (v265, без GPU).** Конфиг с пинами валидируется
(`config is valid: 2 model(s)`); на v240 тот же конфиг вообще не запускается
с `-validate` (флага нет). Сквозной прогон: `/v1/models` без активного
профиля показывает только `backend-*`; после
`PUT /api/profiles/active {"name":"llama"|"ninfer"}` появляется
`qwen3.8-27b`, `POST /v1/chat/completions` с `model=qwen3.8-27b` приходит в
выбранный backend, и `model` в теле запроса уже `qwen3.8-27b` — значит
`useModelName` применяется **после** разрешения пина и требование NInfer
`request.model == --model-id` выполнимо. Пин `~` убирает публичный ID из
списка. Текущие `llama/config.yaml` и `ninfer/config.yaml` на v265
валидны — миграция конфигов не ломается о схему.

**Передано дальше (не решено здесь).**

- Тикет «Топология»: как собрать один образ на два движка. База llama.cpp
  `server-cuda13-b10068` — **Ubuntu 24.04** + CUDA 13.3, бинарники в `/app`;
  NInfer требует **Ubuntu 26.04** (glibc 2.42) и FFmpeg 8 (`libavcodec62`).
  Значит база — вероятно `ubuntu:26.04` с `COPY --from=<llama.cpp@digest>`.
  Там же: что происходит с `ninfer/Dockerfile` (статический COPY llama-swap
  из образа llama-профиля больше не нужен) и остаётся ли `cuda13` у
  какого-либо сервиса.
- Тикет «Топология»: с одним контейнером переключение уезжает из
  `docker compose up/down` в активный профиль llama-swap, а прогрев при
  старте (`hooks.on_startup.preload`) становится проблемой — прелоадить
  оба движка нельзя по VRAM. Также нужно решить, как исключить
  автоматический swap по запросу (вероятно `unlisted: true` у `backend-*`,
  чтобы снаружи был только запиненный ID).
- Остаточный риск: поведение v265 на боевых конфигах не проверялось живым
  запуском (только `-validate` и маршрутизация на фиктивных backend'ах) —
  это предмет тикета «Проверка через opencode-субагентов».
