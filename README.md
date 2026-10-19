# Локальный LLM-инференс

## Описание

Репозиторий содержит единую точку входа `http://localhost:8080`: контейнер
`llama-swap` (образ `router:v265` из `router/Dockerfile` — llama-swap v265,
llama.cpp b10438 и NInfer v0.4.6 как дочерние процессы). Публичный контракт —
ровно один model-ID `qwen3.8-27b`; какой движок за ним стоит, выбирает активный
профиль llama-swap, переключаемый вручную. Движки никогда не работают
параллельно.

| Активный профиль | Движок | Модель |
|---|---|---|
| `llama` | llama.cpp | Qwen3.8-27B NVFP4-MTP (`.gguf`) |
| `ninfer` | NInfer TP=2 | Qwen3.8-27B NVFP4 DFlash2 (`.ninfer`) |

Решение зафиксировано в ADR-0006 (`docs/adr/`), проверка на живом железе — в
`docs/research/0014` и `0015`, доказательства — в
`.scratch/llama-swap-orchestrator/assets/`.

Отдельно в репозитории остаётся `vllm/` — compose-профиль vLLM, выведенный из
текущей топологии (ADR-0006). Он занимает тот же порт `8080` и те же GPU;
одновременно с роутером не запускать.

## Требования

- Docker Engine 24+ с Docker Compose, поддерживающим `include`.
- NVIDIA Container Toolkit (`nvidia-ctk`).
- Две NVIDIA GPU по 16+ ГиБ VRAM (Qwen3.8-27B занимает обе).
- `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf` для
  llama.cpp.
- `/opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/qwen3_8_27b_nvfp4.ninfer`
  для NInfer (скачивается `./router/fetch-model.sh`).
- Для vLLM: `/opt/models/Qwen3.8-27B-NVFP4/`.

Модели монтируются в контейнер read-only и в Git не добавляются.

## Структура

```text
llm-server/
├── docker-compose.yaml
├── router/
│   ├── Dockerfile
│   ├── docker-compose.yaml
│   ├── config.yaml          # глобалы, hooks, профили с пинами
│   ├── config.d/
│   │   ├── 10-llama.yaml    # models.backend-llama (llama.cpp)
│   │   └── 20-ninfer.yaml   # models.backend-ninfer (NInfer)
│   └── fetch-model.sh
├── vllm/                    # вне текущей топологии
│   ├── docker-compose.yaml
│   └── config.yaml
├── docs/
│   ├── adr/
│   ├── research/
│   └── NVIDIA_SETUP.md
└── scripts/
```

## Запуск роутера

```bash
docker compose up -d --wait --wait-timeout 1800
docker compose logs -f llama-swap
```

Сервис без compose-профилей — поднимается всегда. При старте активен профиль
`ninfer`, NInfer прелоадится (~6 c), после чего первый запрос обслуживается
сразу. Строки `[ERROR] failed to preload model backend-ninfer: status 404` в
стартовом логе — косметика: у NInfer нет warmup-эндпоинта, прелоад при этом
запускает и прогревает движок (ADR-0006).

## Переключение движков

1. Убедиться, что текущие генерации завершились (выполняющийся запрос
   продолжается на старом движке; его прерывает только swap).
2. Переключить профиль:

   ```bash
   curl -X PUT http://localhost:8080/api/profiles/active \
     -H 'Content-Type: application/json' \
     -d '{"name":"llama"}'   # или "ninfer"
   ```

   (или UI llama-swap на `http://localhost:8080`).

3. Проверить состояние:

   ```bash
   curl -s http://localhost:8080/api/profiles   # поле active
   curl -s http://localhost:8080/v1/models      # ровно qwen3.8-27b
   ```

   `status: unloaded` у пин-записи в `/v1/models` — косметика llama-swap
   (hardcode для пинов); правдивое состояние — `/api/profiles`.

4. Смена профиля сам движок не грузит: swap происходит на первом запросе к
   `qwen3.8-27b`, и он платит загрузку весов — llama.cpp 40–60 c, NInfer ~6 c.
   При `sendLoadingState: false` этот запрос молчит, без in-stream баннера
   загрузки (ADR-0006): индикатор — только логи контейнера
   (`docker compose logs -f llama-swap`).

Backend'ы не работают параллельно: дефолтная exclusive-группа llama-swap
выгружает старый движок до старта нового. Прямые запросы к неактивному движку
невозможны — его ID скрыт и закрыт пином (`404`).

При OOM или зависании на первом запросе смотреть логи контейнера и
`nvidia-smi`: красная линия проекта — ≥ 512 MiB свободной VRAM на дисплейной
GPU1 под пиковой нагрузкой. Порт `8080` общий с vLLM-профилем — одновременно их
не запускать.

## Единый контракт

Публичный model-ID один — `qwen3.8-27b`. Режим reasoning задаёт клиент;
серверного мнения о reasoning нет (голый ID отдаёт дефолт chat template —
thinking + `xhigh`). Проверено на обоих движках (`docs/research/0014`, `0015`):

| Цель | Что слать клиент | Оба движка |
|---|---|---|
| выключить thinking | `chat_template_kwargs: {"enable_thinking": false}` | да |
| уровень reasoning | `reasoning_effort: low\|medium\|xhigh` (top-level или в kwargs) | да |
| выключить thinking через top-level | `reasoning_effort: "none"` | только NInfer |

Невалидное значение `reasoning_effort` → `500` (llama.cpp) / `400` (NInfer).
Top-level `none` на llama.cpp инертен — переносимый способ выключить thinking
только через kwargs (разбор — `docs/research/0015`). opencode v2 управляет
reasoning вариантами модели (`body.chat_template_kwargs`), см. ADR-0006.

Sampling — серверный дефолт движка с клиентским переопределением: пресет живёт
в `cmd` движка (`router/config.d/`), поля запроса его перекрывают. llama-swap
правит тело запроса только `stripParams: repetition_penalty` (+ `useModelName`
на NInfer).

Безопасное подмножество параметров (безразлично обоим движкам; полная таблица —
ADR-0006, сводка — `docs/research/0013`):

- переносимо: `temperature` `[0,1]`, `top_p` `(0,1]`, `top_k` `1..20` (не 0),
  `min_p` `[0,1]`, `presence_penalty`/`frequency_penalty` `[-2,2]`, `seed`,
  `max_tokens ≥ 1`, `reasoning_effort` из
  `none|low|medium|xhigh`, `chat_template_kwargs.{enable_thinking,
  preserve_thinking}` (bool);
- непереносимо: `repetition_penalty` (стрипается llama-swap), `repeat_penalty`
  (llama.cpp-only, NInfer молча игнорирует), `top_k: 0`, `reasoning_effort`
  вне словаря, а также фичи, которые NInfer отклоняет (`response_format:
  json_object`, `logit_bias`, `logprobs`, `strict`,
  `parallel_tool_calls: false`, named tool choice).

## Модель llama.cpp (профиль `llama`)

Параметры ядра находятся только в `router/config.d/10-llama.yaml` (секция
`cmd`). Qwen3.8-27B запускается с контекстом 180224 токена (NVFP4-MTP
квантизация тира HIGH, файл ~17.6 GB) и спекулятивным декодированием:
draft-mtp с fallback на ngram-mod. Требуется пара `--split-mode tensor` и
`--tensor-split 50,50`; проверенный стабильный максимум контекста — 180224, на
196608 первый же decode падает OOM на дисплейной GPU1. `--ctx-checkpoints` не
включены. Подробный разбор — в `docs/research/0008-llama-qwen38-mtp-ngram-mod-combo.md`.

Активный пин llama.cpp — **b10438** (бамп с b10068 ради top-level
`reasoning_effort`; A/B b10438 против b10068 на протоколе 0005 регресса не
показало — prefill +5–7 %, decode в пределах разброса, wall-clock равен или
лучше; `docs/research/0015`).

## Модель NInfer (профиль `ninfer`)

Движок — релиз `ninfer-tp2 v0.4.6` из форка `ValerioDolci/ninfer-tp2` (по
C++-дереву v0.4.6 == v0.4.7; у v0.4.7 published-ассетов нет). SHA-256 архива
зафиксирован в `router/Dockerfile` и проверяется на сборке. Модель — артефакт
`glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer` (21.54 GB, скачивается
`./router/fetch-model.sh` с проверкой контрольной суммы): весовая часть
побитово равна официальному `neroued/Qwen3.8-27B-nvfp4-NInfer`, отличается
только блок DFlash2 (NVFP4-драфтер и proposal-голова).

Базовый профиль движка: `--tp 2 --devices 0,1`, KV `nvfp4`, контекст модели
262144 токенов, KV-пул `auto` (`--vram-headroom-mib 640`), две активные
последовательности (`--max-concurrency 2`), 4 слота device-state, спекулятивное
декодирование DFlash2 (`--spec dflash2 --draft-tokens 7 --lm-head-draft`),
Vision на плате без дисплея и вынос таблицы embedding в host RAM,
`--default-max-tokens 16384`. Фактическая свободная VRAM видна в стартовой
строке движка `capacity | KV … auto | … free … MiB`; порог проекта — ≥ 512 MiB
на дисплейной GPU1. Одиночный запрос достигает модельных 262144, промпт сверх
ёмкости отклоняется чистым `400 context_length_exceeded`.

`--host-state-slots` и `--host-kv-mib` на `--tp 2` обязаны быть 0: удерживаемые
диалоги живут только в device-state слотах. Две полосы: decode двух диалогов
идёт одновременно, но префиллы сериализуются. Замеры и разбор tp2 (VRAM-бюджет,
пределы, сравнение артефактов и против llama.cpp) —
`docs/research/0009-ninfer-tp2-two-5070ti.md`, решения — ADR-0003.

Откат DFlash2 к MTP — правка `cmd` на `--spec mtp --draft-tokens 3` в
`router/config.d/20-ninfer.yaml` и `docker compose restart llama-swap`, без
пересборки образа.

## vLLM (вне текущей топологии)

Compose-профиль `vllm` остался в репозитории (`vllm/`), но выведен из текущей
топологии (ADR-0006). Он публикует OpenAI API самого vLLM на том же `:8080`,
поэтому одновременно с роутером не запускать:

```bash
docker compose down --remove-orphans
docker compose --profile vllm up -d --wait --wait-timeout 1800
docker compose --profile vllm logs -f vllm-server
```

Публичный model-ID — `qwen3.8-27b`. Базовая конфигурация: text-only на двух GPU
с FP8 KV-cache, контекст 49152 токена (`65536` не проходит startup), одна
активная sequence (`max-num-seqs: 1`), `gpu-memory-utilization: 0.85` под
графическую сессию; на GPU1 под пиковой нагрузкой ≥ 512 MiB свободной VRAM.
Thinking управляется клиентом через `reasoning_effort` или
`chat_template_kwargs: {"enable_thinking": false}`; reasoning возвращается в
поле `reasoning`; клиентские sampling-параметры не отбрасываются. MTP,
TurboQuant KV-cache, prefix caching и FlashInfer autotune намеренно не
включены — только после отдельной проверки длинных streaming-ответов и VRAM.

## Управление

```bash
# Запуск / остановка роутера
docker compose up -d --wait --wait-timeout 1800
docker compose down --remove-orphans   # остановит и vLLM, если поднят

# Логи и перезапуск после изменения router/config*.yaml
docker compose logs -f llama-swap
docker compose restart llama-swap

# Пересборка образа после смены пинов в router/Dockerfile / build-args
docker compose build llama-swap

# Скачивание артефакта NInfer с проверкой SHA-256
./router/fetch-model.sh
```
