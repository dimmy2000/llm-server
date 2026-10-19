# Strata на этом железе: факты развертывания

Status: resolved
Type: research

## Question

Можно ли запустить Strata (v0.1.x) нативно на этой машине и как именно? Собрать инженерные
факты, от которых зависят установка и протокол замеров:

- RTX 5070 Ti (Blackwell, 16 GB) — подтвержденная поддержка? Требования к CUDA/драйверу.
  Хост: open-модули 615.71.09-p2p (форк NVIDIA) + vanilla userland 615.71.09 — есть ли
  известные проблемы сочетания с Strata?
- Мульти-GPU: как трен strata распределяет модель на 2 карты? Учитывает ли дисплейную
  карту (GPU1 с графической сессией)? Можно ли явный пин карт (CUDA_VISIBLE_DEVICES)?
  Что с красной линией VRAM ≥ 512 MiB на дисплейной?
- RAM: как движок прикрепляет (mlock/pin) expertos; поведение на 59 GiB с экспертами
  43 GB (IQ3_XXS) и 50 GB (IQ3_S); когда включается low-ram режим и что он реально дает
  на 59 GiB.
- Порт: флаг смены порта с дефолтного `:8080` (конфликт с llama-swap).
- Установка: путь установки, `setup.sh` поведение при добавлении второго/третьего размера
  (`--setup`), величина диска под 3 размера (66–76 GB за размер + общие шарды), где лежат
  конфиги/логи.
- `./bench.sh`: что меряет, как конфигурируется, выдает ли отчет — годен ли для нашей
  матрицы.
- `--calibrate`: что делает, когда имеет смысл запускать.

Источники: README, docs/INSTALL.md, docs/MULTI_GPU.md, docs/DETAILS.md,
docs/TROUBLESHOOTING.md репозитория Niko1221/Strata; поиск по GitHub issues
(5070 Ti, two GPUs, 64 GB RAM, IQ3_S OOM); свежие release notes.

Доставить: сводка фактов + рекомендуемая командная строка установки и запуска для этой
машины + открытые риски.

## Answer

Research 18.10.2026; прочитаны актуальные README и docs/ ветки main (релиз v0.1.45 от
2026-10-17 — движок активно развивается, ориентироваться на 0.1.42+), а также GitHub
issues #1760, #922, #1250 и release notes.

### 1. Blackwell / RTX 5070 Ti и драйвер

- **Официально в списке**: «NVIDIA RTX 20, 30, 40 or 50 series, 12 GB VRAM or more»;
  нужен compute capability ≥ 7.5 (5070 Ti = sm_120, CC 12.0 — ок). Требование к драйверу:
  **NVIDIA ≥ 580** (docs/INSTALL.md «What you need», docs/DETAILS.md «Before you start»).
- Готовые движки собираются под CUDA 13.0 и включают sm_120 — **компиляция локально не
  нужна**; релизы прикладывают NVIDIA CUDA 12 / NVIDIA CUDA 13 / AMD HIP сборки. Замечание
  из TROUBLESHOOTING: при самостоятельной сборке CUDA 13.2.0/13.2.1 (nvcc 13.2.51)
  некорректно компилирует часть ядер под sm_120 (#892/#968) — но это про исходную сборку,
  не про готовый движок.
- **Живые подтверждения именно 5070 Ti:**
  - [#1760](https://github.com/Niko1221/Strata/issues/1760): 2× RTX 5070 Ti 16 GB, IQ3_S,
    layer split — **decode ~91 tok/s** (Windows, v0.1.40.4 и v0.1.42+ с
    `"gpu_order": "as_given"`);
  - [#922](https://github.com/Niko1221/Strata/issues/922): 1× RTX 5070 Ti 16 GB, IQ3_S —
    реальные **~84 tok/s, калибровка до 94.3 tok/s** после Strata 0.1.40.3 + драйвер
    617.42 (раньше было 9–14 tok/s: старый драйвер 591.74 + на Windows отказ large pages;
    симптом — GPU 100 % загрузки и < 60 W);
  - README: демо «voxel pagoda garden, IQ3_S, 128K on an RTX 5070».
- **Патченный драйвер 615.71.09-p2p**: прямых репортов о сочетании нет. Чувствительные
  точки Strata:
  - page-locked (pinned) экспертная арена — ключевой путь; на Linux известен старт,
    убиваемый по OOM при распиновке 43–50 GB, когда модельные файлы держат page cache
    [#1250](https://github.com/Niko1221/Strata/issues/1250) — починено в 0.1.40.2:
    поэтапное page-locking по 1 GiB, `STRATA_PIN_GUARD` / `STRATA_PIN_RESERVE_GIB`
    (headroom по умолчанию 4 GiB), непоместившаяся часть остаётся pageable с
    предупреждением («only N of M GiB could be page-locked»);
  - чувствительность к версии драйвера (#922: 591.74 → 617.42 = ~7× скорость). Наш
    615.71.09 лежит в этом диапазоне — при симптоме «GPU 100 % / power < 60 W / decode
    в единицах tok/s» сравнить с 617.x, но только не в ущерб P2P-патчу (см. ниже);
  - **P2P Strata не использует**: split — pipeline с hand-off через обычную pinned RAM
    («a few hundred KB through pinned RAM», docs/MULTI_GPU.md); NVLink/P2P не задействованы.
    Поэтому amd_iommu=on / iommu=pt и P2P-патч драйвера вне пути Strata — не мешают и не
    нужны (безопасно оставить как есть).

### 2. Мульти-GPU: как делятся веса, дисплейная карта, пин

- **Layer split (pipeline), не tensor parallelism** (docs/MULTI_GPU.md): слои делятся на
  диапазоны — карта 0 держит слои 0..K-1, карта 1 — остальные, плюс output head и
  MTP-draft (~0.8 GB). Каждая карта держит: копию dense-весов, **свой KV-кэш полного
  контекста**, свои prompt-буферы (~1.5 GB при дефолтном чанке) и **expert cache только
  своих слоёв**; в host RAM экспертная арена одна, общая. Hand-off — один раз на
  verify-окно через pinned RAM; P2P/NVLink не нужны, работают даже x1-слоты.
- **Две карты ≈ вдвое больший expert cache** — главный источник скорости («two cards hold
  about twice the experts one card holds»): на паре 16 GB + 24 GB (Coder) в VRAM держатся
  почти все эксперты.
- **Пин карт**: `--gpus 0,1` / `--gpus all` / `--gpu N` (нумерация = nvidia-smi; движку
  ставятся `CUDA_VISIBLE_DEVICES` + `CUDA_DEVICE_ORDER=PCI_BUS_ID`, issue #51), или в
  конфиге `"gpu": [0, 1]`; `"layer_split": "auto"` (размещение по свободной VRAM) либо
  числом — «первый слой каждой последующей карты», напр. `"24"`.
- **Порядок карт**: auto ставит быструю карту последней (#1352 — последний стадион гоняет
  head + draft + verify). Для двух одинаковых 5070 Ti показания clocks отличаются на ~1 %
  и авто-режим в 0.1.41 переворачивал порядок с потерей ~15 % decode
  (#1760); **с 0.1.42 карты со скоростями в пределах 5 % сохраняют заданный порядок**.
  Для нашей пары явно задавать `"gpu_order": "as_given"` в конфиге — дешёвая страховка.
- **Дисплейная карта (GPU1)**: Strata всегда оставляет свободным reserve
  `--vram-reserve-mib` (дефолт 700 MiB) и size с учётом того, что чужие процессы уже
  держат VRAM на старте (#493). Есть отдельный резерв для последующих карт:
  **`--vram-reserve-later-mib`** (дефолт = основному резерва) — док даёт ровно наш
  кейс: «the card that drives the monitors needs more headroom … display on the last
  card: `--vram-reserve-mib 300 --vram-reserve-later-mib 1800`». Красную линию ≥ 512 MiB
  на GPU1 держим так: GPU0 (headless) — маленький reserve, GPU1 (дисплейная, последняя в
  [0,1]) — большой. Контроль: стартовая строка «N MiB of VRAM free with everything
  loaded» (ниже ~256 MiB движок сам предлагает reserve), per-request warning 0.1.43.1
  при < 512 MiB (на Linux), `/metrics` (`strata:gpu_mem_used_bytes`, per-card), monitor-вкладка.
- KV-кэш обязательно целиком на каждой карте выбранного контекста — на 16 GB-картах
  контекст конечен (int8 KV ≈ 1.1 GB на 64K — считать по месту; `--kv q4_0`/`k8v4`
  уменьшают вдвое/на 23 % ценой качества).

### 3. RAM-механика: pin/mlock, экспертов в RAM vs VRAM, low-ram

- **Дефолт**: все 24 576 экспертов копируются в RAM и **page-lock’ятся** (пиннинг через
  `cudaHostAlloc`/`cudaHostRegister`; на Linux вся арена, без Windows-капов WDDM).
  CPU считает недостающие экспертов in place (AVX2/AVX-512), одновременно с GPU
  (docs/HOW_IT_WORKS.md, docs/DETAILS.md).
- **Малорамочные режимы** (setup выбирает сам, когда «эксперты + ~10 GB» не влезают в
  RAM; docs/MODELS.md «Will it fit», docs/DETAILS.md «Low-RAM mode»):
  - `--mmap-experts` — эксперты остаются **мапнутыми из файла** (`experts.bin` в паке, а
    с 0.1.31 для native IQ-паков прямо GGUF-шарды; DOCS: «Strata-data.models…»), в RAM
    живёт только OS page cache — «+23-50 GB of disk», RAM почти 0. Работает и в split
    (эксперты читаются через файловый кэш; при долгих промптах cache может съесть RAM).
  - `--resident-experts` (с 0.1.30) — в RAM **page-locked копия только тех экспертов,
    которых не держит GPU**; headroom по умолчанию 4 GiB
    (`STRATA_RESIDENT_HEADROOM_GIB`); «while it answers nothing is read from the SSD».
  - **С 0.1.40 resident-вариант работает в multi-GPU split** (#642/#848): RAM-копия
    оставляет только экспертов, которых нет **ни в одном** card-cache;setup больше не
    заставляет single-GPU в low-ram.
  - `--resident-budget-gib N` — RAM-бюджет (копируются самые «горячие» N GiB, остальное
    с файлов); `--low-ram on|off` (setup) / `--low-ram resident|mmap` (engine) — явный выбор.
  - Linux opt-in `STRATA_ARENA_MMAP=1` — мапнутая арена вместо RAM, для случая «карты
    держат большинство экспертов, RAM маленькая» (измерено на 2× 16 GB + 32 GB RAM:
    ~1 GB → 25 GB доступно) — запасной рычаг для нашего 59 GiB.
- **На этой машине (59 GiB total, доступно ~47–48 GiB):**
  - **IQ3_XXS** (43 GB экспертов): полный pin «эксперты + 10 GB» = ~53 GB → на预еле;
    отчётливо ожидаем **resident** low-ram: RAM ≈ 43 GB − то, что удержат оба кэша 2×16 GB
    (порядка 15–25 GB) + headroom — влезает спокойно.
  - **IQ3_S** (50 GB): 50+10 > 59 → полный pinned-арена почти не влезает с гос. нагрузкой;
    то же самое — resident. RAM ≈ 10–22 GB. При этом от splits выигрыш декода большой
    (см. #1760: 91 tok/s).
  - **Q2_0** (34 GB) / **IQ2_XS** (35.5 GB): влезают в полную pinned-арену с запасом —
    можно без low-ram вообще.
  - Контекст: с 64K setup включает KV streaming (`--kv-resident 32768`, KV в RAM ~13.7
    KB/токен → 1.7 GB на 128K). Для 59 GiB брать контекст **≤ 64K для IQ3_S, ≤128K для
    IQ3_XXS** (на «64 GB PC» для этих размеров setup сам советует ≤ 128K — docs/DETAILS).
  - Q2_0 на AVX-512 CPU дополнительно создаёт постоянный пак-файл ~40 GB (one-time) — по
    документации это только про Q2_0 (CPU kernel layout), не касается IQ-паков.

### 4. Порт и смежное

- Дефолт: `127.0.0.1:8080` (веб-UI + OpenAI-compat `/v1/chat/completions`, плюс
  `/v1/messages` (Anthropic) и `/v1/responses`). **Смена порта: `--port 8081`**
  (START-HERE.bat --port 8081 / ./setup.sh --port …; пишет `"port"` в конфиг
  `strata-<model>.json`, можно править руками — docs/INSTALL.md «Options without
  questions», docs/DETAILS.md «Using it»).
- Для запуска по сети дополнительно есть `--host 0.0.0.0 --api-key …` — на первой
  установке не нужно.
- Есть опции `--idle-unload 600`, `--min-free-vram-mib 11000`, `POST /unload` /
  `/load` (docs/DETAILS «Sharing the GPU») — удобно, чтобы между прогонами быстрее
  отдавать VRAM/RAM llama-swap’у.
- Очистая RAM: закрыть браузер и т.п. — на запуске Strata грузит 35–55 GB и «блокирует»
  часть RAM для GPU; первый старт машины может подвисать 1–3 минуты (норма; docs).

### 5. Установка: путь, добавление размеров, диск

- Путь: клонировать репо → `./setup.sh` → сам ставит Python 3.12 (`.venv/`), движок
  (ready-made CUDA 13, ~0.4 GB CUDA-библиотеки из pip), спрашивает модель / размер /
  контекст / images. Модель грузится в `Strata-data/` рядом с папкой Strata
  (`models/`, `packs/`, `mtp/`, ~70 GB per model + ~6 GB MTP; расположение запоминается
  в `~/.config/strata/settings.json`, `--data-dir` переопределяет).
- **Добавление второго/третьего размера**: `./setup.sh --setup` — «files another model
  shares are not downloaded again». Дефолтные загрузки по размерам (docs/MODELS.md):
  Q2_0 66 GB / IQ2_XS 68 GB / IQ3_XXS 76 GB → **все 3 размера ≈ 210 GB**; shard 2 (~29 GB
  n-gram определяемых таблица) общий для размеров оригинала и при повторном установе не
  перекачивается; MTP ~6 GB (once) + vision ~1 GB (once). С учётом этого нижний
  предел ~ 165 GB, верхний (если setup перекачает шарды из-за имени) — ~230 GB + Q2_0
  AVX-512 пак ~40 GB (только при установке Q2_0 на AVX-512 CPU). Ориентир docs/INSTALL:
  «Disk ~70-80 GB free per model» и «70–120 GB» вообще. **Диска 1.2 TB — хватает с запасом.**
- **Конфиги и логи**: `strata-<model>.json` (настройки), `run-<model>.sh` (стартовый
  скрипт), `strata-<model>.log` (лог) — в папке Strata; модель — в `Strata-data/`.
  Дополнительный конфиг-файл shared settings `strata-<model>.shared-settings.json`
  при надобности.
- Если setup вдруг не найдёт ready-made движок (напр. под новый CUDA/toolchain), он
  попросит поставить build tools (build-essential + CUDA toolkit на Ubuntu) и соберёт
  движок сам (10–40 мин, один раз); на Linux замечена пара багов компиляции (#601,
  gcc >14 vs CUDA ≤13.0): CXX=g++-14 ./setup.sh/helpers.

### 6. `./bench.sh`: что меряет и как конфигурируется

- Файл — обёртка над `tools/strata_bench.py` (подтверждено: bench.sh = 539 байт,
  `exec .venv/bin/python tools/strata_bench.py "$@"`). Опции `--clients N`, `--long`,
  `--compare <folder>`, `--out DIR`, `--url http://127.0.0.1:8081`.
- Съёмка по HTTP API на работающий (или самоподнимаемый) экземпл Strata; всё по 3
  прохода, **median + range**; движковые тайминги (`prompt_per_second`, `predicted_per_second`),
  TTFT — клиентский (docs/COMMUNITY_BENCHMARKS.md «Run the benchmark»):
  - **chat**: 3 коротких вопроса, ≤ 100 → decode tok/s, TTFT;
  - **4K и 16K prompt** (fresh word-list prompts; если контекст меньше — пропускаются) →
    prompt tok/s, TTFT;
  - **agent session**: system + 4 tools, 5 turn’ов по ~1 500 слов (продолжается от
    собственных ответов модели) → reused / re-read tokens, TTFT по turn;
  - `--clients N` — параллельные запросы (нужен `--batch` / серверная настройка);
  - `--long` — промпт ~32 768 токенов (или `--max-prompt-tokens` по желанию).
  Thinking off по умолчанию (`--think` — включить). Результаты падают в
  `bench/results/<date>-community-<gpu>-<model>/` (`README.md` в repo-шаблоне,
  `results.json`, engine-log-excerpt) — или в желаемую `--out` папку. Длительность ~3–10
  мин после загрузки модели.
- Для качественных замеров отдельно docs — `tools/needle_bench.py` (recall needles,
  `--lengths 32k,128k --depths 10,50,90`) и A/B — `tools/ab_engine.py`, отдельный
  скрипт сравнения двухfolders (COMMUNITY_BENCHMARKS). Использовать: `bench.sh` —
  скорость, `needle_bench.py` — recall, `ab_engine.py` — A/B на версиях/настройках.

### 7. `--calibrate`

- `./setup.sh --calibrate` (или вручную после установки): **NVIDIA-only**
  (docs/INSTALL.md, docs/MODELS.md), ~15–30 мин, грузит модель несколько раз (машина
  нагружена, может «подвисать» на 1–2 минуты, раз на рестарт); в конце **сам запускает
  модель** — не стартовать вручную.
- Что меряет (docs/DETAILS.md «Tuning for your PC», MULTI_GPU.md):
  - `--pcie-frac` — доля экспертов, гоняемых через PCIe (стриминг);
  - `--spec-min-p` — порог уверенности драфтера;
  - `--pool-workers` — число CPU-потоков expert pool;
  - `--adapt-every / --adapt-swaps / --adapt-decay` — «жадность» следования
    expert-cache за разговором;
  - при 2+ картах: `--prefill-pipe` — геометрия чанков pipeline промпта
    (calibrate меряет prompt-read скорость 2K/8K fresh prompts при разных
    разбиениях; документы описывают алгоритм и границы).
-.advanced: калибровка ставит настройку **только когда она быстрее более чем на 3 %**;
  результат запоминается per-PC + per-model (settings.json рядом с data-dir), сохран
  после update.
- **Когда запускать**: после install модели (setup предлагает сам), **до** bench-матрицы
  — иначе калибровочные опции смешаются с матрицей. Повторно: после изменения
  конфигурации железа (память / VRAM-распределение / запрет hugepages) и после апдейта
  Strata, если настройки не сохранились.
- Замеристика №922: на RTX 5070 Ti 16 GB IQ3_S калибровка подобрала `--pcie-frac 0.35`,
  `--spec-min-p 0.70`, `--adapt-every 1`, `--adapt-swaps 160`, `--adapt-decay 0.97` — и
  после апгрейда движка/драйвера декод вырос с ~14 до 94.3 tok/s (большая часть эффекта —
  драйвер, но выбор pcie-frac тоже важен).

### 8. Риски и открытые вопросы

- **Патченный драйвер 615.71.09-p2p**: прямых репортов Strata нет; готовый движок CUDA
  13/sm_120 должен работать на vanilla userland 615.71.09. Опыт #922 показывает, что на
  RTX 50-серии драйвер имел большее значение, чем железо; понаблюдать за
  «experts loaded … GiB/s», «large pages», power draw. Если при появлении «GPU 100 %
  / <60 W / 2–9 tok/s» — проверить large pages/THP статус, версию драйвера (наш 615 дома
  между 591 и 617) и только после этого поднимать 617.x (не сломав P2P-патч).
- **RAM 59 GiB и resident low-ram**: резидентный режим в split работает только с
  движком 0.1.40+ (и он современный код). Следить за warning’ом «only N of M GiB could
  be page-locked»; если разово не хватает — STRATA_PIN_GUARD=0 / меньший
  `--resident-budget-gib`. Поведение resident-vs-mmap на 59 GiB с двумя 16 GB кэшами —
  не задокументировано, измерить у себя и сравнить (`STRATA_ARENA_MMAP=1` — запасной
  вариант).
- **Дисплейная GPU1 и red line**: решено архитектурно —
  `--vram-reserve-later-mib`, `gpu_order: as_given`; но **наш split — первый запуск на
  двух identical 5070 Ti на Linux** — списывать по логу на первом же старте, если
  авто-режим уместит порядок «по-своему».
- **IQ3_S 2× 5070 Ti = ~91 tok/s (Windows #1760)** — наш ориентировочный upper bound
  для Linux; #639-style оптимизации и 0.1.43.1 тач-апы могут дать VM/Linux собственый
  boost. Реальная скорость — измерить у себя.
- **Контекстные потолки**: на 16 GB-картах с KV в VRAM дальние контексты упираются в
  VRAM каждой карты (KV целиком на карте); для 128K+ применяется KV streaming — но
  тогда RAM-след 1.7 GB на 128K поверх экспертной resident-копии. При 262K «IQ3_XXS +
  IQ3_S» см. доку: memory limit на 64 GB PC —на 59 GiB безопасный контекст ≤128K, ниже -
 ostrovnive.
- **`--batch`/parallel**: Страта дефолт — 1 concurrent (docs/README); если
  bench/матрица требует параллельности, понадобится `"parallel": 2` — и это ещё не
  проверено на нашем железе.
- **ndiswrapper**: Strata поovertsly предdrigаёт и начинает grGPU в `expert-cache auto`,
  наша GPU1 под нагрузкой стрессует стрессы (display/GUI) — стоит всё же мерить с
  графической сессией в фоне, потому что red line должны держаться под нагрузкой.

### 9. Рекомендуемая командная строка установки/запуска для этой машины

```bash
# 0) освободить GPU и :8080 — временно сдвинуть llama-swap:
#    docker compose stop llama-swap   (в проекте llm-server)

# 1) залить репо и запустить установку (короткая версия):
git clone https://github.com/Niko1221/Strata
cd Strata
./setup.sh --setup \
  --model IQ3_XXS --context 32768 --vision no \
  --gpus 0,1 --port 8081 --yes
# (или полностью интерактивно: ./setup.sh — и принимать recommended)

# 2) настроить config под дисплейную GPU1 и порядок карт — редактировать
#    strata-iq3_xxs.json:
#     "gpu": [0, 1],
#     "gpu_order": "as_given",
#     args += ["--vram-reserve-mib", "300",
#              "--vram-reserve-later-mib", "2048"]
#    (GPU0 headless — reserve 300; GPU1 дисплейная и «later» card —
#     reserve 2048 держит красную линию ≥ 512 MiB)

# 3) каждый запуск: ./run-iq3_xxs.sh   (или снова ./setup.sh)
#    добавить второй/третий размер: ./setup.sh --setup --model IQ3_S --yes

# 4) калибровка (15-30 мин, NVIDIA-only; машина нагружена; в конце сама стартует модель):
./setup.sh --calibrate

# 5) бенч по нашей матрице:
./bench.sh                          # chat + 4K + 16K + agent-session
./bench.sh --long                   # + 32K prompt
python tools/needle_bench.py --url http://127.0.0.1:8081 \
  --lengths 32k,64k,128k --depths 10,50,90
```

До первого запуска: закрыть браузер/мешающие программы (при загрузке 35–55 GB RAM
машина может подвисать 1–3 мин). После каждого запуска в логе смотреть строки
«layer split: …», «VRAM free with everything loaded», «memory guard: … available …»,
«resident RAM: …» — они отвечают на вопросы «влезла ли арена», «держится ли red line GPU1»
и «вгород стал resident ли mmap».

### Источники

- README, docs/INSTALL.md, docs/MULTI_GPU.md, docs/MODELS.md, docs/DETAILS.md,
  docs/TROUBLESHOOTING.md, docs/HOW_IT_WORKS.md, docs/COMMUNITY_BENCHMARKS.md —
  ветка main [Niko1221/Strata](https://github.com/Niko1221/Strata), октябрь 2026.
- GitHub issues: [#1760](https://github.com/Niko1221/Strata/issues/1760) (dual 5070 Ti,
  gpu_order regression, fix 0.1.42),
  [#922](https://github.com/Niko1221/Strata/issues/922) (5070 Ti 16 GB IQ3_S, драйвер +
  calibrate), [#1250](https://github.com/Niko1221/Strata/issues/1250) (Linux pinned OOM,
  fix 0.1.40.2), [#493](https://github.com/Niko1221/Strata/issues/493) /
  [#533](https://github.com/Niko1221/Strata/issues/533) (vram-reserve и expert cache),
  [#1631](https://github.com/Niko1221/Strata/issues/1631) (фича-RF: RAM
  budget + SSD-backed experts + split).
- [Releases](https://github.com/Niko1221/Strata/releases): v0.1.40 … v0.1.45
  (актуальные оптимизации multi-GPU/low-ram/Blackwell в 0.1.42–0.1.45).
