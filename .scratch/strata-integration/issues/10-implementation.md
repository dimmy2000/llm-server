# Внедрение: автоматический swap на живом роутере

Status: resolved
Type: task
Blocked by: 09

## Question

(Исполнение по решениям тикетов 08–09) Реализовать автоматический swap на живой
инфраструктуре:

1. Механика по решению 08: контейнеризация Strata (образ/пакетирование, монтирование
   весов, интеграция в compose/`router/Dockerfile`-мир) или host-агент + shim-cmd.
2. Конфиг llama-swap по решению 09: переписать `router/config.yaml` +
   `router/config.d/*` под схему «профили только для движка родителя,
   strata-ID без пинов, дефолтная exclusive-группа»; черновик YAML —
   `assets/09-config-draft.yaml` (включая заметки к реализации: memlock
   ulimit=-1, маунты RO весов, контейнерные конфиги `host: 0.0.0.0`,
   демонтаж-лист, `extra_hosts`). Комментарии в конфигах — минимальные и
   стабильные (указатели на ADR/runbook), без дублирования документации.
   Помнить про single-file-mount `router/config.yaml` (правка подменой →
   `up -d --force-recreate`, `config.d/` — обычный `restart`).
3. Демонтаж по демонтаж-листу 08: strata-use.sh, strata.service и его симлинки,
   watchdog-шимы, ручные профили — с сохранением того, что решено оставить.
4. Клиенты: opencode-конфиг правится только если решение 08/09 этого требует
   (цель — контракт клиентов не трогать); env-нюансы и reasoning-варианты не менять.
5. Откат-план: зафиксировать способ вернуть рабочее состояние первой итерации,
   пока верификация (тикет 11) не пройдена.

Resolved when: автомат работает на `:8080` — любой из трёх ID отвечает по запросу
без ручных шагов; старый lifecycle демонтирован (или изолирован по решению 08).

## Answer

(Исполнение 2026-10-19, по решениям 08–09. Все правки — образ
`llm-server/router:v265-strata1`, контейнер пересоздан, живой цикл свапа
проверен на `:8080`.)

1. **Механика — вариант (A), движок в роутер-контейнере.**
   - Сборка: build-стадия `strata-build` (`nvidia/cuda:13.0.0-devel-ubuntu24.04`,
     apt-шаг upstream) по upstream-пути `/opt/strata/Dockerfile` —
     `setup.cmake_build` + `BUILD.json`, arch 120, vision собран; в рантайм-стадию
     идут бинарники `engine/` + `serve/` + `tools/` (server.py кладёт tools/ в
     sys.path — `strata_tokenizer`) + venv (python 3.14, колёса numpy/pillow есть).
     Исходники — additional context `strata-src=/opt/strata` (compose),
     llama.cpp подтягивается setup.py zip'ом. В образ также копируется
     `libnccl.so.2` из devel-базы (NEEDED контейнерного strata-vision; нативный
     бинарь его не линковал — свежий llama.cpp пина setup.py), путь добавлен в
     lib_dirs контейнерных конфигов.
   - compose: `ulimits.memlock=-1`, RO-маунты
     `/opt/strata/{models,packs,mtp,data}`, `./strata:/app/strata:ro` (лаунчер +
     контейнерные конфиги — правка без пересборки), `extra_hosts` снят.
   - **Отступление от черновика 09**: llama-swap исполняет `cmd` БЕЗ shell
     (shlex-сплит, `exec.CommandContext(args[0])` — `../llama-swap`
     internal/config/commands.go), поэтому `sh -c '...'` из черновика заменён
     скриптом-лаунчером `router/strata/strata-launch.sh need_KiB config port`:
     RAM-гейт → `exec server.py` (движок = PID, который трекает llama-swap;
     SIGTERM → graceful QUIT по #96-пути server.py).
   - Контейнерные конфиги `router/strata/*.container.json` — копии нативных с
     `host: 0.0.0.0`; всё остальное (args, expert-cache, vision gpu:false,
     draft_vocab) — бит в бит с нативными. Движок **0.1.45** (нативный был
     0.1.44-линейки) — по правилу AGENTS это новая точка калибровки; замеры
    _decode/admission — тикет 11.
2. **Конфиг llama-swap — по схеме 09.** `config.yaml`: профили `llama`/`ninfer`
   с единственным пином `qwen3.8-27b → backend-*`; страта-ID нигде не запинены,
   дефолтная exclusive-группа; hooks/on_startup без изменений. `config.d/
   30-strata.yaml`: реальные cmd-модели (`proxy 127.0.0.1:${PORT}`,
   `checkEndpoint /health`), пороги RAM-гейта 48234496/37748736 KiB (46/36 ГиБ).
   Комментарии в конфигах — минимальные, указатели на ADR/runbook.
3. **Демонтаж** (полный, по решению 08): юнит остановлен, симлинки
   `/etc/systemd/system/strata.service`, `/usr/local/sbin/strata-stop`,
   `/etc/strata/active.json` сняты, daemon-reload; `git rm scripts/strata/`
   (strata-use.sh, strata-stop, strata.service, README — в git-истории).
   Watchdog-шимы и страта-профили заменены новым конфигом. `/opt/strata` на
   хосте не тронут (движок, нативные конфиги 172.17.0.1, venv — база отката).
4. **Клиенты не тронуты**: opencode-конфиг прежний (контракт трёх ID и
   reasoning-вариантов не изменился), bench.py без правок.
5. **Откат-план** (до прохождения верификации 11):
   - Точка отката: состояние первой итерации (коммит `7cc3ac8`) + старый образ
     `llm-server/router:v265` (в локальном store, не удалять).
   - `git checkout 7cc3ac8 -- router/ scripts/strata/` → пересоздать симлинки
     (команды в шапке scripts/strata/strata.service) + симлинк
     `/etc/strata/active.json → /opt/strata/strata-iq3_xxs.json` →
     `systemctl daemon-reload` → `docker compose build llama-swap` (или
     `docker tag llm-server/router:v265 llm-server/router:<tag>`) →
     `docker compose up -d --force-recreate llama-swap` → `strata-use.sh <роль>`.
     Нативный `/opt/strata` сохранён — откат в первую итерацию полный.

**Живая проверка (Resolved-when):** `/v1/models` — три ID при любом активном
профиле; цикл без ручных шагов: `strata-iq3` (35 c холодного старта, ответ
корректен, `model` = native-ID) → `qwen3.8-27b` (9.9 c, graceful останов Strata
+ NInfer) → `strata-iq2` (22.9 c, VRAM GPU1 ~2 ГиБ свободно — красная линия
держится) → `qwen3.8-27b` (8.1 c); MemAvailable после цикла 52.3 ГиБ. Стартовые
логи чистые (косметика `failed to preload backend-ninfer: status 404` —
известная). Полная верификация (тайминги, UI Play/PowerOff, пилот) — тикеты
11/13; документация (новый ADR, AGENTS.md, runbook) — тикет 12.

Наблюдение: отказ strata-ID при недоподнимаемом бэкенде — мгновенный
`500 upstream command exited prematurely` с traceback в логах контейнера
(два ранних падения при сборке образа пойманы так же) — ошибки клиента
специфицируемы, как и ожидалось в 08.
