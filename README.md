# Локальный LLM-инференс

## Описание

Docker-стек локального инференса с единой точкой входа `http://localhost:8080`.
Один контейнер `llama-swap` (образ `llm-server/router:v265-strata1` из
`router/Dockerfile`: llama-swap **v265**, llama.cpp **b10438**, NInfer TP=2
**v0.4.6**, Strata **0.1.45**) публикует три OpenAI-совместимых model-ID —
`qwen3.8-27b` (движок родителя: NInfer или llama.cpp по активному профилю),
`strata-iq3` и `strata-iq2` (Strata: Qwen3.8-Flash-Next в квантах IQ3_XXS и
IQ2_XS). Все три движка — дочерние процессы llama-swap, запускаемые через `cmd`;
они никогда не работают параллельно: резидентен ровно один бэкенд, а порядок
unload → start даёт дефолтная exclusive-группа v265. **Переключения как
отдельного действия нет** — запрос к любому из трёх ID сам приводит систему в
нужное состояние (ADR-0008). Стек рассчитан на две RTX 5070 Ti по 16 GiB
(одна дисплейная) и 59 GiB RAM.

Решения зафиксированы в ADR-0006 (единый endpoint и контракт reasoning),
ADR-0008 (контейнерная Strata и автоматический swap; supersede механику
ADR-0007, который остаётся первоисточником размеров и контракта strata-ID);
проверка на живом железе — `docs/research/0014`, `0015`, `0016` и
`.scratch/*/assets/`. Отдельно в репозитории лежит `vllm/` — compose-профиль
vLLM, выведенный из текущей топологии: тот же порт `8080` и те же GPU,
одновременно с роутером не запускать.

## Структура проекта

```text
llm-server/
├── docker-compose.yaml              # имя проекта llm-server, include роутера и vLLM
├── AGENTS.md                        # контракт работы агента: архитектура, лимиты, команды
├── CONTEXT.md                       # доменный словарь (профиль, пин, движок, RAM-гейт…)
├── router/
│   ├── Dockerfile                   # образ llm-server/router:v265-strata1: llama-swap +
│   │                                # llama.cpp + NInfer + build-стадия Strata
│   ├── docker-compose.yaml          # сервис llama-swap: порты, GPU, ulimits, RO-маунты
│   ├── config.yaml                  # глобалы, hooks, профили llama/ninfer с пинами
│   ├── config.d/
│   │   ├── 10-llama.yaml            # models.backend-llama (llama.cpp b10438)
│   │   ├── 20-ninfer.yaml           # models.backend-ninfer (NInfer TP=2 v0.4.6)
│   │   └── 30-strata.yaml           # models.strata-iq3 / strata-iq2 (Strata 0.1.45)
│   ├── strata/
│   │   ├── strata-launch.sh         # лаунчер движка: RAM-гейт по MemAvailable, exec server.py
│   │   ├── strata-iq3_xxs.container.json
│   │   ├── strata-iq2_xs.container.json   # копии нативных конфигов, готовка только host
│   └── fetch-model.sh             # скачивание артефакта NInfer с проверкой SHA-256
├── vllm/                            # compose-профиль vLLM, вне текущей топологии
│   ├── docker-compose.yaml
│   └── config.yaml
├── .scratch/                        # локальный issue-трекер: карты усилий, тикеты, assets/ с доказательствами
├── docs/
│   ├── adr/                         # ADR-0001…ADR-0008
│   ├── research/                    # отчёты 0001…0016 с замерами на живом железе
│   ├── runbook-strata.md            # диагностика отказов Strata, логи, красные линии
│   ├── NVIDIA_SETUP.md, NVIDIA_P2P.md   # драйвер, P2P, откаты и soak
│   ├── agents/                      # правила трекера issue, триаж-метки, доменные доки
│   ├── flowchart.md, sequence.md, states.md   # схемы работы
│   └── plans/                       # исторические планы прежних усилий
└── scripts/
    ├── nvidia-p2p/                  # rebuild-modules.sh, p2p-verify.sh, soak.sh, bench.py
    └── port-forwarding-rules.ps1    # устарел, не используется
```

Прикладного кода, тестов, CI и линтинга в репозитории нет: «код» — это
Dockerfile, compose-файлы и конфигурации движков.

## Схемы работы

- [Схема работы роутера](./docs/flowchart.md) — от model-ID до запущенного движка,
  с RAM-гейтом Strata и порядком unload → start.
- [Последовательность запроса и свапа](./docs/sequence.md) — запрос к `strata-iq3`
  при резидентном NInfer: выгрузка, гейт, старт, прокси.
- [Состояния бэкендов роутера](./docs/states.md) — жизненный цикл резидентного
  бэкенда: свап, холодный старт, отказ гейта, PowerOff.

## Используемые системы и инструменты

- Docker Engine 24+ и Docker Compose с поддержкой `include`.
- NVIDIA Container Toolkit (`nvidia-ctk`); две RTX 5070 Ti (sm_120), драйвер
  хоста — open-модули `615.71.09-p2p` форка `aikitoria/open-gpu-kernel-modules`
  (ADR-0005, `docs/NVIDIA_P2P.md`).
- llama-swap v265 — маршрутизатор и менеджер жизненного цикла движков, UI на `:8080`.
- llama.cpp `server-cuda13-b10438` — движок профиля `llama`.
- NInfer TP=2 v0.4.6 (форк `ValerioDolci/ninfer-tp2`, upstream `Neroued/ninfer`)
  — движок профиля `ninfer`.
- Strata 0.1.45 (`Niko1221/Strata`) — движок MoE-модели Qwen3.8-Flash-Next,
  собирается в образ из checkout `/opt/strata`.
- vLLM — профиль `vllm`, вне текущей топологии.
- OpenCode v2 — основной потребитель API (`providers.llama-swap` и
  `providers.self-hosted` в `~/.config/opencode/opencode.jsonc`).

Версии пинов и контрольные суммы архивов — в build-args
`router/docker-compose.yaml` и `router/Dockerfile`.

## Источники данных

### Входы

| Источник | Описание | Путь на хосте (RO-маунт в контейнер) |
| :--- | :--- | :--- |
| Артефакт llama.cpp | Qwen3.8-27B NVFP4-MTP, тир HIGH, ~17.6 GB + mmproj BF16 | `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/` → `/models/…` |
| Артефакт NInfer | `glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer`, 21.54 GB, скачивается `./router/fetch-model.sh` с проверкой SHA-256 | `/opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/qwen3_8_27b_nvfp4.ninfer` → `/models/…` |
| Веса Strata | Qwen3.8-Flash-Next IQ3_XXS и IQ2_XS, по два shard'а (второй — PLE), mmproj Q8_0 | `/opt/strata/models/` → `/opt/strata/models/` |
| Эксперт-паки Strata | pack'и `iq3_xxs` и `iq2_xs` (+ tokenizer) | `/opt/strata/packs/` → `/opt/strata/packs/` |
| MTP-драфт Strata | драфт-слой `rt` для спекулятивного декодирования | `/opt/strata/mtp/` → `/opt/strata/mtp/` |
| Expert-profile | профиль обращения к экспертам (`--expert-profile`) | `/opt/strata/data/` → `/opt/strata/data/` |
| Конфиги и лаунчер Strata | контейнерные копии конфигов и лаунчер с RAM-гейтом | `router/strata/` → `/app/strata/` |
| Артефакт vLLM (вне топологии) | safetensors-каталог Qwen3.8-27B-NVFP4 | `/opt/models/Qwen3.8-27B-NVFP4/` → `/models/…` |

Модели и артефакты в Git не добавляются; все маунты — read-only.

### Выходы

| Файл | Описание | Путь |
| :--- | :--- | :--- |
| Лог роутера и движков | старт/останов движков, decode- и admission-строки Strata, причины отказов RAM-гейта | stdout контейнера: `docker logs llama-swap` |
| Файл-лог движка Strata iq3 | внутренний лог движка (маунта на хост нет) | `docker exec llama-swap cat /opt/strata/strata-iq3_xxs.log` |
| Файл-лог движка Strata iq2 | то же для IQ2_XS | `docker exec llama-swap cat /opt/strata/strata-iq2_xs.log` |
| Снапшот P2P-настроек | бэкап GRUB и патченных модулей | `scripts/nvidia-p2p/p2p-snapshot.sh` |

## Работа с автоматизацией

### Установка

1. Docker Engine 24+ с Compose, поддерживающим `include`; NVIDIA Container
   Toolkit; драйвер хоста — патченные open-модули `615.71.09-p2p`
   (`docs/NVIDIA_P2P.md`, без них NInfer TP=2 работает на host-staged copies).
2. Две GPU по 16+ GiB VRAM и ~59 GiB RAM. Strata держит в RAM page-locked
   эксперты 47 GiB (IQ3_XXS) / 36 GiB (IQ2_XS) — двух тяжёлых бэкендов
   одновременно не хватает, отсюда последовательный доступ.
3. Артефакты моделей на хосте (см. «Источники данных»): GGUF llama.cpp,
   `./router/fetch-model.sh` для NInfer, каталоги `/opt/strata/{models,packs,mtp,data}`
   для Strata.
4. Сборка образа: `docker compose build llama-swap` (образ ~6.9 GB).
   Стадия сборки Strata берёт исходники из additional context
   `strata-src=/opt/strata` и компилирует под `CUDA_ARCHITECTURES=120`.

### Настройка

- Параметры движков — только в `router/config.d/` (секции `cmd`), профили и
  пины — в `router/config.yaml`, контейнерные настройки Strata —
  в `router/strata/*.container.json`.
- Любая правка требует `docker compose restart llama-swap`. Исключение:
  `router/config.yaml` смонтирован одиночным файлом — если редактор заменил
  файл (rename), инод меняется и `restart` видит старое содержимое; тогда
  `docker compose up -d --force-recreate llama-swap`. `config.d/` и
  `router/strata/` смонтированы директориями — там достаточно `restart`.
- `ulimits.memlock: -1` в `router/docker-compose.yaml` обязателен: без него
  Strata падает на mlock экспертов.
- Публикация порта: `"8080:8080"` публикует API на **всех** интерфейсах хоста,
  аутентификации в llama-swap нет — доступ снаружи ограничивается сетью хоста
  (LAN/файрвол). Это осознанное решение: три ID должны быть доступны по
  локальной сети. Если нужен только сам хост — `"127.0.0.1:8080:8080"`;
  если нужен один LAN-интерфейс — публикация на конкретном адресе
  (`"192.168.17.69:8080:8080"`). API считается открытым для любой машины,
  которой разрешён доступ к порту: агентные клиенты получают право запускать
  инструменты на хосте.

### Запуск

```bash
docker compose up -d --wait --wait-timeout 1800
docker compose logs -f llama-swap
```

Сервис роутера поднимается всегда (compose-профилей у него нет). Старт:
активен профиль `ninfer`, `backend-ninfer` прелоадится (~6 c), публичные ID
доступны сразу. Строки `[ERROR] failed to preload model backend-ninfer:
status 404` в стартовом логе — косметика: у NInfer нет warmup-эндпоинта,
прелоад при этом запускает и прогревает движок (ADR-0006).

Проверка после старта:

```bash
curl -s http://localhost:8080/v1/models | tr ',' '\n' | grep '"id"'   # три ID
curl -s http://localhost:8080/api/profiles                            # поле active
```

## Публичный контракт

### Три model-ID

| ID | Движок | Артефакт | Контекст | Reasoning-словарь |
| :--- | :--- | :--- | :--- | :--- |
| `qwen3.8-27b` | NInfer TP=2 (профиль `ninfer`, дефолт) или llama.cpp (профиль `llama`) | `.ninfer` / `.gguf` | 262144 (NInfer) / 180224 (llama.cpp) | `low\|medium\|xhigh`, `none` только через kwargs |
| `strata-iq3` | Strata 0.1.45 | IQ3_XXS | 131072 | `none\|low\|medium\|high` |
| `strata-iq2` | Strata 0.1.45 | IQ2_XS | 262144 | `none\|low\|medium\|high` |

Все три ID принимают текст и изображения (vision: mmproj у llama.cpp,
`--vision` на плате без дисплея у NInfer, CPU-энкодер `strata-vision` у Strata)
и поддерживают tool calls.

Все три ID всегда видны в `/v1/models` (404-ловушек прежней пин-схемы больше
нет). `status: unloaded` у записи — косметика llama-swap (hardcode v265);
правдивое состояние — `GET /api/profiles`, SSE `/api/events` или `/health`
upstream-порта. Backend-модели `backend-llama`/`backend-ninfer` скрыты
(`unlisted: true`), но не запинены — прямой запрос к ним работает как к обычной
модели exclusive-группы (API доступен только из localhost/LAN).

### Reasoning

Режим задаёт клиент, серверного мнения нет: голый ID отдаёт дефолт chat
template (thinking + `xhigh` у родителя).

| Цель | Что слать клиент | `qwen3.8-27b` | `strata-iq3` / `strata-iq2` |
| :--- | :--- | :--- | :--- |
| выключить thinking | `chat_template_kwargs: {"enable_thinking": false}` | да | да (или top-level `none`) |
| уровень reasoning | `reasoning_effort: low\|medium\|high\|xhigh` | да | да, но `xhigh` неотличим от `high` и не предлагается |
| выключить thinking top-level | `reasoning_effort: "none"` | только NInfer (на llama.cpp инертен) | да |
| невалидное значение | — | `500` (llama) / `400` (NInfer) | `400` |

Нюансы strata-ID: движок отрабатывает любой `model` в запросе (`useModelName`
не нужен), но поле `model` в **ответе** — канон native-ID
(`qwen3.8-flash-next-iq3_xxs` / `…-iq2_xs`), llama-swap его не переписывает:
не сверять ответ с запрошенным ID. Tool calls работают (forced tool choice →
200), `structured output + tools` → `400`.

### Sampling

Серверный дефолт движка, клиентские поля его перекрывают: у llama.cpp — CLI-флаги
в `cmd` (`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0
--repeat-penalty 1.0`), у NInfer — mode-aware пресет движка (thinking
`1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5`), у Strata — пресет движка.
llama-swap правит тело запроса только `stripParams: repetition_penalty` (на всех
трёх) и `useModelName: qwen3.8-27b` на `backend-ninfer`.

Безопасное подмножество (переносимо между родительскими движками; полная
таблица — ADR-0006, сводка — `docs/research/0013`): `temperature` `[0,1]`,
`top_p` `(0,1]`, `top_k` `1..20` (не 0), `min_p` `[0,1]`,
`presence_penalty`/`frequency_penalty` `[-2,2]`, `seed`, `max_tokens ≥ 1`,
`reasoning_effort` из словаря движка, `chat_template_kwargs.{enable_thinking,
preserve_thinking}` (bool).

Непереносимо: `repetition_penalty` (стрипается), `repeat_penalty`
(llama.cpp-only, NInfer молча игнорирует), `top_k: 0`, `reasoning_effort` вне
словаря, NInfer-несовместимые фичи (`response_format: json_object`,
`logit_bias`, `logprobs`, `strict`, `parallel_tool_calls: false`, named tool
choice).

Старые публичные ID (`qwen3.8`, `qwen3.8-27b-instruct`, `-chat-*`/`-agent-*`,
`ornith-9b*`) удалены без backcompat-алиасов (ADR-0002, ADR-0004, ADR-0006).

## Переключение движков и холодный старт

Отдельного действия переключения нет: выбор ID в клиенте или в UI llama-swap
(`http://localhost:8080`) и есть переключение. Конкурентный запрос, пришедший
во время свапа, отвечает 200 с ожиданием (FIFO-сериализация v265).

Ручным остаётся только выбор движка родителя — предпочтение производительности,
не условие работоспособности:

```bash
curl -X PUT http://localhost:8080/api/profiles/active \
  -H 'Content-Type: application/json' \
  -d '{"name":"llama"}'   # или "ninfer"
```

Первый запрос после свапа платит холодную загрузку весов; при
`sendLoadingState: false` он молчит без in-stream баннера — индикатор только в
логах контейнера (ADR-0006, `docs/runbook-strata.md`).

| Бэкенд | Холодный старт (платит первый запрос) |
| :--- | :--- |
| NInfer | ~6–7 c (прелоадится на старте контейнера) |
| llama.cpp | 7–9 c на тёплом page cache, до 40–60 c на холодном диске |
| Strata `strata-iq3` | 17.8–20.9 c |
| Strata `strata-iq2` | 12.7–13.8 c |

При отказе (нехватка RAM, сбой движка) strata-ID даёт быстрый `500 upstream
command exited prematurely` с точной причиной в логах контейнера; ретраев нет по
дизайну — освободить память или повторить запрос.

## Движок llama.cpp (профиль `llama`)

Параметры ядра — только в `router/config.d/10-llama.yaml`. Qwen3.8-27B
(NVFP4-MTP, тир HIGH, ~17.6 GB) с контекстом 180224 и спекулятивным
декодированием `--spec-type draft-mtp,ngram-mod` (ngram-mod приоритетнее,
draft-mtp — fallback). Обязательна пара `--split-mode tensor` +
`--tensor-split 50,50`: дефолтный LAYER-режим копит KV на дисплейной GPU1 и
падает OOM на первом decode. Узкое место VRAM — дисплейная GPU1 (9 KV-слоёв):
проверенный стабильный максимум — `--ctx-size 180224`, на 196608 первый decode
падает OOM. `--cache-idle-slots` и `--cache-ram 40960` сериализуют KV в RAM при
завершении запроса (prefix reuse), но VRAM не освобождают; `--fit off` —
контекст задаётся явно.

Пин llama.cpp — **b10438** (бамп с b10068 ради top-level `reasoning_effort`);
A/B на протоколе `docs/research/0005` регресса не показал — `docs/research/0015`.
Подробный разбор профиля — `docs/research/0008`.

## Движок NInfer TP=2 (профиль `ninfer`)

Релиз `ninfer-tp2 v0.4.6` (по C++-дереву == v0.4.7; published-ассетов у v0.4.7
нет), SHA-256 архива зафиксирован и проверяется на сборке. Артефакт —
`glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer` (21.54 GB): весовая
часть побитово равна официальному `neroued/Qwen3.8-27B-nvfp4-NInfer`,
отличается только блок DFlash2.

Базовый профиль: `--tp 2 --devices 0,1`, KV `nvfp4`, `--max-context 262144`,
`--kv-capacity auto --vram-headroom-mib 640`, `--max-concurrency 2`,
`--device-state-slots 4`, `--spec dflash2 --draft-tokens 7 --lm-head-draft`,
`--vision --vision-device 0`, `--embedding-host`, `--default-max-tokens 16384`.
`ninfer-serve` отклоняет запрос, если `request.model` не равен `--model-id`,
поэтому на записи обязателен `useModelName: qwen3.8-27b`; пер-модельный `env`
обязан ставить `/opt/ninfer/lib` первым в `LD_LIBRARY_PATH`.

Одиночный запрос достигает модельных 262144 токенов, промпт сверх ёмкости
отклоняется чистым `400 context_length_exceeded`. `--host-state-slots` и
`--host-kv-mib` на `--tp 2` обязаны быть 0. Две полосы: decode двух диалогов
идёт одновременно, префиллы сериализуются. Откат DFlash2 к MTP — правка `cmd`
на `--spec mtp --draft-tokens 3` и `docker compose restart llama-swap`, без
пересборки образа. Разбор — `docs/research/0009`, решения — ADR-0003.

## Движок Strata (`strata-iq3` / `strata-iq2`)

Третий движок роутер-контейнера наравне с llama.cpp и NInfer (ADR-0008):
обычный `cmd`-бэкенд llama-swap, автостарт по запросу к strata-ID, останов —
вытеснением или PowerOff в UI (SIGTERM, graceful QUIT). `cmd` исполняется без
shell, поэтому RAM-гейт живёт в лаунчере `router/strata/strata-launch.sh`:
нехватка `MemAvailable` (пороги 46 GiB для iq3, 36 GiB для iq2) → мгновенный
отказ с причиной, при проходе — `exec server.py`.

Размеры два, и это не «высокая точность»: IQ3_XXS и IQ2_XS — агрессивно
сжатые кванты, выбранные под бюджет 59 GiB RAM (page-locked эксперты
47/36 GiB). Более качественный IQ3_S (54.8 GB) вне рабочего набора из-за
апстрим-блокера `--resident-experts` на 2-GPU сплите; UD-IQ4_XS не проходит по
RAM. Опубликованные метрики качества (yardstick против Q8_0) — в
`docs/research/0016` §5; локально качество квантов не мерилось. Выбор размера
и нормы decode для 0.1.45 — `docs/research/0016` и тикет 11 карты
`.scratch/strata-integration/` (decode iq3 131–133, iq2 129–138 tok/s,
admission 71–79 %).

Лаунчер и контейнерные конфиги смонтированы с хоста (`./strata:/app/strata:ro`) —
правка переживает restart, пересборка не нужна. `ulimits.memlock: -1` обязателен.
Нюанс vision: в `args` конфига iq3 флаг `--vision` есть, у iq2 его нет —
`serve/server.py` сам добавляет `--vision` при наличии секции `vision` в
конфиге (фикс #1322), поэтому картинки принимают оба ID; в обеих копиях
конфигов `vision.gpu: false` (энкодер на CPU, VRAM не тратит). Логи — stdout
контейнера и файл-логи движка внутри него (`docs/runbook-strata.md`).

## Диагностика и красные линии

Пошаговый ранбук отказов (таблица типовых симптомов, логи, контейнерные
операции) — `docs/runbook-strata.md`. Быстрый путь:

```bash
docker logs --tail 200 llama-swap
nvidia-smi --query-gpu=index,memory.free --format=csv,noheader
free -m
curl -s http://localhost:8080/api/profiles
```

- Красная линия VRAM: ≥ 512 MiB свободной VRAM на дисплейной GPU1 под пиковой
  нагрузкой. Верификационный цикл автомата (тикет 11 карты
  `.scratch/strata-integration/`) держал минимум 710 MiB; на ninfer-профиле
  под долгими диалогами в device-state слотах + 90k-префиллами зафиксирован
  провал до 19 MiB — нарушение принято как документированный регресс текущего
  профиля (`docs/research/0010`, H10; `docs/adr/0005`). Запас над линией мал —
  следить за свободной VRAM при любом изменении профиля.
- RAM: постоянного свопа быть не должно; транзиентные si/so-всплески 2–3 c на
  старте iq3 — норма.
- Порт `8080` общий с vLLM-профилем — одновременно их не запускать.
- После ребута или обновления ядра — `scripts/nvidia-p2p/p2p-verify.sh`
  (пересборка модулей: `scripts/nvidia-p2p/rebuild-modules.sh`).

## Ручной smoke-набор

Автоматических тестов в репозитории нет; проверка после смены конфига, профиля
или версии движка — руками (верификационные проходы задокументированы в
`.scratch/llama-swap-orchestrator/` и `.scratch/strata-integration/`, тик 11).
Минимальный прогон:

```bash
# листинг и состояние
curl -s http://localhost:8080/v1/models
curl -s http://localhost:8080/api/profiles

# каждый ID: обычный ответ, reasoning, tools, холодный старт после свапа
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"Привет"}],"max_tokens":200}'
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"strata-iq3","messages":[{"role":"user","content":"Привет"}],"reasoning_effort":"low","max_tokens":200}'
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"strata-iq2","messages":[{"role":"user","content":"Привет"}],"max_tokens":200}'
```

Каждая смена версии движка Strata — новая точка калибровки: сверять decode и
admission с нормами `docs/research/0016` и прогонять длинный русскоязычный
ответ (риски CJK-коллапса, обрыва внутри `</think>` и деградаций #1944-типа).
Для strata-ID задавать `max_tokens` с запасом ≥ 12–16K.

## Что не проверено (открытое)

- Качество ответов: систематического бенчмарка трёх ID на задачах
  программирования нет; пилот на рабочих задачах открыт
  (`.scratch/strata-integration/issues/13-pilot-automation.md`).
- NInfer: качество при 4-битном (`nvfp4`) KV, приём DFlash2-драфта и decode на
  glfenix-артефакте, минимум свободной VRAM на `auto`/640/H=4
  (`.scratch/ninfer-tp2/`).
- Воспроизводимость сборки Strata: Dockerfile берёт исходники из checkout
  `/opt/strata` и не фиксирует Git-коммит; версия и хеш исходников
  (`"version": "0.1.45"`, `"src": "b95137167bd9b751"`) попадают только в
  `engine/BUILD.json` собранного образа. Две сборки с одной меткой могут
  содержать разный код, если checkout обновился; SHA-256 модельных артефактов
  Strata тоже не проверяются (проверяются архивы llama-swap и NInfer и артефакт
  NInfer при скачивании).
- Сетевая экспозиция: `8080` опубликован на всех интерфейсах без аутентификации
  (см. «Настройка»).

## Профиль vLLM (вне текущей топологии)

`vllm/` остался в репозитории, но выведен из текущей топологии (ADR-0006):
публикует OpenAI API самого vLLM на том же `:8080`, поэтому одновременно с
роутером не запускать.

```bash
docker compose down --remove-orphans
docker compose --profile vllm up -d --wait --wait-timeout 1800
docker compose --profile vllm logs -f vllm-server
```

Публичный model-ID — `qwen3.8-27b`. Конфигурация: text-only на двух GPU с FP8
KV-cache, контекст 49152 (`65536` не проходит startup), `max-num-seqs: 1`,
`gpu-memory-utilization: 0.85` под графическую сессию; FlashInfer autotune
отключён. Thinking управляется клиентом. MTP, TurboQuant KV-cache, prefix
caching и FlashInfer autotune намеренно не включены — только после отдельной
проверки длинных streaming-ответов и запаса VRAM. Изменение `vllm/config.yaml`
требует перезапуска `vllm-server`.

## Управление

```bash
# Роутер (llama.cpp + NInfer + Strata; сервис без compose-профилей)
docker compose up -d --wait --wait-timeout 1800
docker compose logs -f llama-swap
docker compose restart llama-swap       # после правок router/config*.yaml и router/strata/*
docker compose up -d --force-recreate llama-swap   # после подмены router/config.yaml
docker compose build llama-swap         # после смены пинов/исходников движков в router/Dockerfile
docker compose down --remove-orphans    # остановит и vLLM, если поднят

# Скачивание артефакта NInfer с проверкой SHA-256
./router/fetch-model.sh
```

## Контакты

### Разработчик

- [Dmitrii Samoilenko](mailto:dimsamoylenko@gmail.com)
