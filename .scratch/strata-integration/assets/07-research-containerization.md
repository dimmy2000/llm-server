# Research 07: феасибилити контейнеризации Strata и механики автостарта

Дата: 2026-10-19. Первоисточники: `/opt/strata/*` (файлы/строки), `../llama-swap`
(код v265, теги origin), `router/Dockerfile`, `router/docker-compose.yaml`.

## Вывод-резюме (что это значит для выбора механики)

Контейнеризация Strata — **феасибилити высокая, путь upstream-поддержанный**.
Проект несёт готовый `Dockerfile` + `docker-entrypoint.sh` (движок собирается на
build-стадии, веса — на томе/маунтах, `CONFIG=` умеет подменить конфиг,
`STRATA_EXECV=1` делает сервер PID 1 — SIGTERM доходит). Апстрим llama-swap после
v265 **ничего нового не дал** (v265 — свежайший тег), но в самом v265 найден
неиспользованный механизм **`cmdStop`** — per-model stop-команда с подстановкой
`${PID}`, работающая на Linux (`model_config.go:135`, `process_command.go:649–693`).
Итог: у тикета 08 три жизнеспособных варианта — (A) движок Strata прямо в
роутер-контейнере как обычный ребёнок llama-swap («ровно как qwen»), (B) отдельный
strata-контейнер, управляемый llama-swap через docker.sock-шим + `cmdStop`,
(C) натив + host-агент + `cmdStop`. Детали и риски — ниже.

## 1. Контейнеризация Strata — готовый путь?

- **Образ** (`/opt/strata/Dockerfile`): база `nvidia/cuda:13.0.0-devel-ubuntu24.04`,
  движок (strata + strata-vision) собирается на build-стадии под CPU той машины
  (нативный код — «build it on the PC it runs on», строки 68–71); `CUDA_ARCHITECTURES`
  фиксируется build-arg'ом (для RTX 5070 Ti — arch 120); `BUILD_VISION=0`/runtime
  `VISION=cpu` закрывают наш CPU-vision стандарт. `.dockerignore` держит образ
  source-only: `/engine/`, `/build*/`, `/packs/`, `/models/`, `/mtp/`, `.venv/`
  исключены.
- **Запуск** (`docker-entrypoint.sh`): все настройки через env (`MODEL`, `CONTEXT`,
  `VISION no|yes|cpu`, `HOST`, `PORT`, `KV`, `GPU/GPUS/LAYER_SPLIT`, `LOW_RAM`,
  `GGUF_DIR`, `API_KEY`); **`CONFIG=` побеждает** выбор модели (строка 35, 59–67) —
  можно смонтировать модифицированную копию нашего конфига. Идемпотентный setup-пасс
  пропускается, если конфиг уже на томе (`REINSTALL=1` — переделать).
- **Веса/артефакты — остаются снаружи**: конфиги ссылаются на абсолютные пути
  `/opt/strata/{models,packs,mtp,data}` (iq3_xxs.json: строки 4–18). Объёмы:
  `models/` 160G, `packs/` 52G, `mtp/` + `data/expert-profile.bin` (2.1M), mmproj
  в models/. Маунт этих каталогов RO в те же пути внутри контейнера — конфиги
  работают без правки путей.
- **CUDA-версии**: наш нативный движок собран под CUDA 13.3 (`lib_dirs:
  /usr/local/cuda-13.3/{bin,lib64}`, iq3_xxs.json:44–47). Upstream-образ — CUDA
  **13.0** devel → движок в образе пересобирается под базу образа (это и есть
  upstream-путь; build на этой машине). Роутер-образ уже на CUDA 13.3 базе
  (`router/Dockerfile:39–40` — ubuntu:26.04 + бинарники ggml-org cuda13.3) —
  важно для варианта A.
- **Хост-драйвер**: образ требует драйвер ≥ 580 (Dockerfile:17); у нас
  615.71.09-p2p — совместимо.
- **Запуск требует** `--ulimit memlock=-1` (Dockerfile:20); в
  `router/docker-compose.yaml` ulimit сейчас **не задан** — для варианта A добавить.

## 2. Потери и риски контейнера

- **GPU**: nvidia container runtime уже используется роутером
  (`router/docker-compose.yaml`: devices nvidia count all, `NVIDIA_VISIBLE_DEVICES:
  all`) — обе карты видны; NInfer tp2 уже работает в этом контейнере с P2P
  (ADR-0005), движок Strata просит gpu `[0,1]`, `layer_split: auto` — профиль тот же.
- **Память**: page-locked профили — те же 47/36 ГиБ; memlock ulimit — см. выше.
  `LOW_RAM`-нюанс касается только setup-пасса (setup.py читает /proc/meminfo = хост);
  у нас конфиги пре-сделаны (`expert-cache 4400`), setup в контейнере не нужен.
- **Сеть/хост-биндинг**: `server.py` берёт host **только из конфига** (AGENTS.md);
  в наших конфигах захардкожено `host: 172.17.0.1` — внутри контейнерного netns
  бинд по этому адресу не встанет. Нужна контейнерная копия конфига с
  `host: 0.0.0.0` (и `port` — CLI-флаг, свободен). Путь `CONFIG=`/маунт копии —
  тривиален; «конфиги фиксированы» (AGENTS.md) — решить в 08/09 как оформлять
  контейнерный вариант.
- **Логи**: `journalctl -u strata` исчезает вместе с юнитом; источники — stdout
  контейнера (`docker compose logs`) и файл-лог из конфига (`/opt/strata/strata-*.log`
  — маунтить writable-каталог либо оставить stdout). Метрики первой итерации
  сохраняются в виде логов движка, но канал другой — отразить в док-тике 12.
- **Производительность**: ожидание регресса нет (тот же драйвер, тот же runtime;
  memory pinning решается ulimit; /dev/shm для движка не критичен — IPC через
  драйвер). Проверить замером в тикете 11 (санити-decode в допуске 0016).

## 3. Апстрим llama-swap после v265

- `git ls-remote --tags origin` в `../llama-swap`: свежайший тег — **v265** (пин
  проекта). Новых релизов, вводящих proxy-only/внешние модели или hook-команды,
  **нет**.
- Код v265 подтверждает отсутствие механизмов: `HooksConfig` — только
  `on_startup {preload, profile}` (`internal/config/config.go:137–142`);
  per-model `healthCheckTimeout` перезаписывается глобальным (`internal/config/load.go:136`).
- **Находка: `cmdStop`** (`internal/config/model_config.go:135`): per-model
  stop-команда, выполняется при штатной остановке модели с подстановкой `${PID}`
  (`process_command.go:649–693`: если задана — исполняется вместо SIGTERM, с
  bound pipe-copy, hanging-CmdStop защищён; при ошибке sanitize — fallback
  terminateProcessTree). На Linux по умолчанию пуста (taskkill — только Windows,
  `model_config.go:212–215`), но **задаваема**. Это первоклассный крюк для
  остановки внешнего процесса — упрощает варианты B и C.

## 4. Fallback: натив + host-агент (минимальный дизайн)

- **Старт**: `cmd` шима в роутер-контейнере — curl к host-агенту на 172.17.0.1
  (docker0 уже доступен через `extra_hosts: host-gateway`,
  `router/docker-compose.yaml:29–33`) с параметром размера (iq3/iq2); агент
  (мини-HTTP-демон на хосте, root) делает stop старого (если есть) →
  `systemctl start strata` (конфиг — симлинк `/etc/strata/active.json`, механика
  первой итерации); шим после запроса поллит `/health :8081` до `loaded: true`,
  затем блокируется (ждёт).
- **Останов**: `cmdStop` — curl к агенту `stop` (вместо SIGTERM-только шима).
  exclusive-группа llama-swap гарантирует порядок unload→start; `cmdStop` закрывает
  старую проблему «шим умер — нативное дерево живо».
- **Сложность/хрупкость**: самописный root-демон на хосте (поверхность атаки —
  неаутентифицированный старт/стоп системных юнитов; нужен токен/бинд строго на
  docker0), races (движок умер — шим ждёт: нужен health-проброс в код возврата
  шима), lifecycle агента (его кто-то должен супервизировать). Существенно сложнее
  контейнерных вариантов; оправдан только если контейнеризация сорвётся.
