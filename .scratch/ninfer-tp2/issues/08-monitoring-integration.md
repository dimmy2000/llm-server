# 08 — Профиль ninfer в мониторинге

Type: task
Status: resolved
Blocked by: 02

## Question

Научить `llm-monitoring` (отдельный репозиторий) работать с профилем
`ninfer`.

Текущее состояние:

- launcher (`llm-stack.sh`) принимает профиль и запускает Compose с ним;
  проверить, знает ли он профиль `ninfer` и передаёт ли его дальше;
- compose-сервис профиля называется `ninfer-swap`, контейнер — `llama-swap`,
  поэтому дашборды, привязанные к имени контейнера `llama-swap`, продолжат
  работать;
- метрики: `nvidia-smi-exporter` снимает VRAM всех GPU, поэтому профиль
  добавляется без новых targets; проверить, нет ли в Grafana панелей,
  привязанных к метрикам llama.cpp-профиля (например, число загруженных
  моделей через API llama-swap) — для NInfer часть из них неприменима;
- логи: promtail собирает stdout контейнеров; убедиться, что формат записей
  NInfer (`YYYY-MM-DD HH:MM:SS.mmm LEVEL message`) не ломает существующие
  парсеры и запросы в Loki.

## Acceptance

- Launcher мониторинга принимает профиль `ninfer` и стек поднимается.
- Дашборд показывает GPU-метрики и логи NInfer без ошибок парсинга.
- Зафиксировано, какие панели или запросы остались специфичными для
  llama.cpp-профиля и как они деградируют.

## Answer

Закрыто 2026-10-05. `llm-monitoring` работает с профилем `ninfer`; проверено
на живом стеке (профиль `ninfer`, v0.4.5, официальный артефакт).

Изменения (репозиторий `infrastructure/llm-monitoring`):

- `llm-stack.sh`: обязательный аргумент профиля
  (`./llm-stack.sh up ninfer`; `llama|ninfer|vllm`), передаётся в
  `docker compose --profile`. Дефолт compose-файла —
  `docker-compose.monitoring.yaml` (на диске `.yaml`, скрипт ссылался на
  `.yml`). `status`/`snapshot`/`logs` работают с актуальными контейнерами:
  `llama-swap` для `llama` и `ninfer`, `vllm-server` для `vllm`; устаревшие
  `gemma4`/`open-webui`/`llama-server` убраны. Так как compose резолвит
  относительные пути в `-f`-файлах от каталога первого файла, launcher
  собирает одноразовый umbrella-compose с `include` (пути резолвятся от
  каталога каждого файла) и именем проекта из `name:` базового файла — стек
  поднимается прямо из каталога `llm-monitoring` через
  `BASE_COMPOSE=.../llm-server/docker-compose.yaml`, проект остаётся
  `llm-server`, уже запущенный контейнер backend не перезапускается.
- Дашборд `llm-home.json`: панели 7/8 (mem/CPU cAdvisor) фильтруют
  `.*(llama-swap|vllm-server|open-webui).*`, панель 10 (Loki) —
  `{container=~"llama-swap|vllm-server|open-webui"}`; `open-webui` оставлен
  в регулярках для старых стеков, в стеке `llm-server` панели просто не
  строят такую серию.
- README `llm-monitoring`: новый контракт launcher'а, таблица
  профиль/сервис/контейнер и раздел «Панели по профилям» с зафиксированной
  деградацией.

Проверено (acceptance):

- Launcher принимает `ninfer`, стек поднимается: 7 контейнеров мониторинга
  (`llm-prometheus`, `llm-grafana`, `llm-loki`, `llm-promtail`,
  `llm-cadvisor`, `llm-node-exporter`, `llm-nvidia-smi-exporter`) в проекте
  `llm-server`; контейнер `llama-swap` (ninfer) не тронут (healthy).
  `status ninfer`, `snapshot ninfer`, `logs ninfer` работают; в снимке
  `llama-swap-inspect.json`, `llama-swap-last-30m.log` (логи NInfer) и
  `nvidia-smi-processes.csv` с хоста (видны процессы `ninfer-serve`).
- Дашборд показывает GPU-метрики и логи NInfer без ошибок парсинга:
  `nvidia_smi_gpu_*` по обеим GPU (VRAM 13825/14351 MiB под нагрузкой),
  все Prometheus-targets up; Loki хранит логи `llama-swap` с метками
  `compose_service=ninfer-swap`, `compose_project=llm-server` — метка
  `compose_service` разделяет логи двух llama-подобных профилей. Формат строк
  NInfer (`YYYY-MM-DD HH:MM:SS.mmm LEVEL message`) хранится как есть:
  pipeline promtail (`docker: {}`) не парсит содержимое строк, запросы Loki —
  по меткам.

Зафиксированная деградация (подробнее — README `llm-monitoring`,
раздел «Панели по профилям»):

- Специфичных для llama.cpp панелей (собственный Prometheus-эндпоинт
  llama.cpp, API llama-swap — число загруженных моделей) в дашборде нет —
  для `ninfer` это отсутствие, а не деградация: NInfer эти метрики не
  отдаёт. Панели 7/8/10 для `ninfer` работают без изменений (контейнер
  тот же `llama-swap`).
- Панели 7/8 (`Container memory/CPU usage`) пусты на этой машине для любого
  профиля: cAdvisor v0.49.1 не находит `layerdb/mounts` у WSL2
  storage-драйвера `overlayfs` и не идентифицирует docker-контейнеры.
  Замена — `docker stats` (в снимке `docker-stats.txt`).
- Панель 9 (`GPU processes`) пуста: exporter в контейнере со своим
  PID-неймспейсом, `nvidia-smi --query-compute-apps` внутри не видит
  процессы хоста (не зависит от профиля). Замена — `nvidia-smi-processes.csv`
  в снимке (снимок выполняется на хосте).
- `dmesg` в снимке пуст: в WSL2 нет прав на чтение kernel buffer,
  обрабатывается `|| true`.
