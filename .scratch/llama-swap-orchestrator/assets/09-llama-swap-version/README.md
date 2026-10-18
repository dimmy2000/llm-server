# Evidence — ticket 09 «Выбор версии образа llama-swap»

Дата: 2026-10-17. Проверка выполнена на хосте проекта, без запуска backend'ов
на GPU (все `cmd` в тестовых конфигах — `sleep`, proxy — на фиктивные
HTTP-серверы).

Воспроизведение: `bash run-checks.sh` (нужен docker и сеть до ghcr.io /
github.com). Вывод — `run.log`.

## Что проверялось

1. **Версия плавающего тега.** `ghcr.io/mostlygeek/llama-swap:cuda13`
   удалённо — это тот же дайджест, что `v265-cuda13-b11706`
   (`sha256:62f47d09…`, образ собран 2026-10-17, llama.cpp `b11706`).
2. **Локально запущенный образ — невоспроизводим.** Дайджест локального
   образа `sha256:3d49d5d9…` отвечает **404** в GHCR; версия внутри —
   llama-swap `v240 (6b5320d)`, llama.cpp `10068 (571d0d540)`.
3. **`profiles.pins` есть в v265, нет в v240.** Один и тот же конфиг с
   пинами (`pins-test.yaml`): v265 — `config is valid: 2 model(s)`;
   v240 — `flag provided but not defined: -validate`.
4. **Единый ID действительно переключается.** `pins-test2.yaml`, два
   backend'а (`useModelName: qwen3.8-27b`, proxy на фиктивные серверы):
   `/v1/models` показывает `backend-llama`/`backend-ninfer`, после
   `PUT /api/profiles/active {"name":"llama"|"ninfer"}` появляется
   `qwen3.8-27b`, и `POST /v1/chat/completions` с `model=qwen3.8-27b`
   попадает в выбранный backend; тело запроса приходит туда с
   `model=qwen3.8-27b` (то есть `useModelName` применяется **после**
   разрешения пина — требование NInfer `request.model == --model-id`
   выполнимо). Пин `~` убирает публичный ID из списка.
5. **Текущие конфиги проекта валидны на v265.** И `llama/config.yaml`, и
   `ninfer/config.yaml` → `config is valid: 1 model(s)`.

## Значения для пинов (зафиксированы решением тикета)

| Что | Значение |
|---|---|
| llama.cpp база | `ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865bd031283c5f66ff2a82984cdb282ec37484cf2a9bfc7b4cb1f85708e` (индекс; amd64-ребёнок `sha256:1c0cc37edc5f6c0a0aeffcbab85db41d74baa5e238bf78e56f7bd90184e84fea`) |
| llama-swap бинарник | релиз `v265`, `llama-swap_265_linux_amd64.tar.gz`, `sha256=cb1f9a94be05afa129d3c17868f1dd2ca710b919333c7b868239dc31575dcfa1` |
| upstream-контроль | `llama-swap_265_checksums.txt` в том же релизе |

## Дополнительные факты для следующего тикета (топология)

- База llama.cpp `server-cuda13-b10068` — **Ubuntu 24.04** + CUDA 13.3,
  бинарники в `/app` (Entrypoint `/app/llama-server`), glibc 24.04.
  NInfer требует **Ubuntu 26.04** (glibc 2.42) и FFmpeg 8 (`libavcodec62`),
  см. `ninfer/Dockerfile`. Значит «один контейнер на два движка» не может
  быть основан на образе llama.cpp — база, вероятно, `ubuntu:26.04` с
  `COPY --from=<llama.cpp@digest> /app …`.
- NInfer-артефакт совместим с `ninfer-serve` v0.4.6, движок ставится из
  релиза `ValerioDolci/ninfer-tp2` с проверкой SHA-256.
