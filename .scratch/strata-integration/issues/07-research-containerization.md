# Research: феасибилити контейнеризации Strata и механики автостарта

Status: resolved
Type: research
Blocked by:

## Question

(AFK, research-субагент) Собрать факты, на которых тикет 08 выберет механику
автоматического старта/остановки Strata силами llama-swap. Llama-swap управляет
только процессами внутри своего контейнера; Strata сейчас нативная на хосте
(`/opt/strata`, CUDA 13.3, `python serve/server.py --engine strata --config <json>
--port <N>`). Ответить на вопросы:

1. **Контейнеризация Strata — готовый путь?** В `/opt/strata` есть upstream
   `Dockerfile` и `docker-entrypoint.sh`: что они делают, для чего рассчитаны,
   покрывают ли наш запуск (`--engine strata`, конфиги `strata-iq3_xxs.json` /
   `strata-iq2_xs.json`, vision на CPU, port 8081/другой)? Что должно попасть в
   образ (serve/, engine/, python-окружение `requirements.txt`, версия python),
   а что остаётся снаружи (весовые артефакты — где они лежат, размеры, как
   монтировать)? Какой базовый образ нужен под CUDA 13.3 (сравнить с рабочим
   `ggml-org/llama.cpp:server-cuda13-b10438`) и есть ли конфликт с драйвером
   615.71.09-p2p?
2. **Потери и риски контейнера:** доступ к GPU (nvidia container runtime уже
   используется роутером), производительность (нет ли причин ожидать регресса
   против нативного запуска — memory pinning, shm, `--ipc`), потеря page-locked
   RAM-профилей, что происходит с `journalctl -u strata`-логами (источник метрик
   первой итерации).
3. **Апстрим llama-swap:** проверить свежие релизы после v265 (репо
   `../llama-swap`, GitHub): появились ли механизмы для внешних/proxy-only моделей
   без cmd-процесса, hook-команды на swap/start/stop, per-model healthCheckTimeout.
   Заодно подтвердить по коду v265, что их действительно нет.
4. **Fallback-вариант — host-агент:** минимальный дизайн, если контейнеризация
   сорвётся: shim-cmd в контейнере дёргает маленький host-side агент (HTTP на
   docker0 / systemd socket), который стартует/останавливает strata.service; как
   гарантировать порядок unload→start (exclusive-группа llama-swap) и как агент
   узнаёт об остановке (SIGTERM шима → stop). Оценить сложность и хрупкость
   против контейнеризации.

Resolved when: факты собраны в `assets/07-research-containerization.md`
(с указанием первоисточников: файлы `/opt/strata`, код `../llama-swap`, релизы
GitHub), тикет закрыт, указатель добавлен в Decisions so far карты.

## Answer

(Выполнено в сессии 2026-10-19 — субагент дважды упал по таймауту стрима,
research проведён основным агентом; полные находки с первоисточниками —
`assets/07-research-containerization.md`.)

- **Контейнеризация — феасибилити высокая**, путь upstream-поддержанный: готовый
  `Dockerfile` (движок собирается на build-стадии, base `nvidia/cuda:13.0.0-devel`,
  драйвер ≥ 580 — наш 615.71.09 ok), `docker-entrypoint.sh` с `CONFIG=`-подменой
  конфига, `STRATA_EXECV=1` (сервер — PID 1, SIGTERM доходит). Веса наружу:
  маунт `/opt/strata/{models 160G, packs 52G, mtp, data}` RO по тем же абсолютным
  путям — конфиги работают как есть, кроме `host: 172.17.0.1` (нужна контейнерная
  копия с `host: 0.0.0.0`). Для варианта «движок в роутер-контейнере» база уже
  CUDA 13.3 (`router/Dockerfile`); memlock ulimit в compose сейчас не задан —
  добавить.
- **Апстрим llama-swap после v265 — ничего нового** (v265 — свежайший тег; hooks
  только on_startup, healthCheckTimeout по-прежнему глобальный). **Но в v265
  найден `cmdStop`** — per-model stop-команда с `${PID}`, работает на Linux
  (`model_config.go:135`, `process_command.go:649–693`): первоклассный крюк
  остановки внешнего процесса.
- **Три варианта для тикета 08**: (A) движок Strata как обычный ребёнок llama-swap
  в роутер-контейнере — «ровно как qwen», без docker.sock; (B) отдельный
  strata-контейнер, управление через docker.sock-шим + `cmdStop`; (C) натив +
  host-агент + `cmdStop` (самописный root-демон — самый хрупкий, теперь с честным
  stop-крюком).
