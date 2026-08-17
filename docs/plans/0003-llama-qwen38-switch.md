# План: Qwen3.8-27B в llama-профиле через llama-swap

Дата: 2026-08-17.

## Цель

- Добавить модель `qwen3.8-27b` (Q4_K_M, `/opt/models/Qwen3.8-27B-GGUF/`) в
  llama-профиль.
- Перевести обе модели (`ornith-9b`, `qwen3.8-27b`) на cmd-модели llama-swap и
  удалить отдельный контейнер `llama-server`.
- Добавить 4 режима: `qwen3.8-27b-instruct/-chat/-agent-code/-agent-plan`.
- Прелоад `qwen3.8-27b` при старте; переключение моделей через unload API.

## Принятые ограничения

- Обе модели не помещаются в VRAM одновременно, поэтому переключение только
  явное через `POST /api/models/unload/:model_id` (вариант B), а не ttl.
- `--ctx-size 262144` задаётся явно (вариант A), `--fit off`; проверка
  загрузки VRAM через nvidia-smi при имплементации.
- Sampling и thinking управляются только через `setParamsByID`; для qwen
  stripParams дополнительно удаляет `reasoning`, `reasoning_effort`,
  `chat_template_kwargs`.
- MTP и `--ctx-checkpoints` для qwen не включаются.
- Прелоадится qwen (основной рабочий режим), ornith грузится по запросу.

## Исходное состояние

- `llama/config.yaml`: модель `ornith-9b` как proxy на
  `http://llama-server:8080` с `cmd: sleep infinity`, режимы
  `ornith-9b-thinking`, `ornith-9b-instruct`.
- `llama/docker-compose.yaml`: сервисы `llama-server` (образ
  `ghcr.io/ggml-org/llama.cpp:server-cuda13`) и `llama-swap` (proxy-конфиг).
- README.md/AGENTS.md описывают llama-server и 2 режима ornith.

## Шаги

1. **`llama/docker-compose.yaml`**
   - Удалить сервис `llama-server`.
   - `llama-swap`: добавить GPU (`deploy.resources.devices`, count all),
     `NVIDIA_VISIBLE_DEVICES=all`, volume `/opt/models:/models:ro`; убрать
     `depends_on`.

2. **`llama/config.yaml`**
   - Модель `ornith-9b`: `cmd` со спавном
     `/app/llama-server --host 127.0.0.1 --port ${PORT}` и прежними
     аргументами ядра; режимы без изменений.
   - Модель `qwen3.8-27b`: `name: qwen3.8-27b`, `alias: qwen3.8`, `cmd` с
     `--model /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf`,
     `--alias qwen3.8`, `--ctx-size 262144`, те же флаги ядра, что у ornith,
     кроме `--ctx-checkpoints`.
   - `stripParams` для qwen: 6 sampling + `reasoning`, `reasoning_effort`,
     `chat_template_kwargs`.
   - `setParamsByID`: режимы `qwen3.8-27b-instruct/-chat/-agent-code/
     -agent-plan` (параметры по unsloth-докам) и запись для алиаса `qwen3.8`
     = agent-plan.
   - `hooks.on_startup.preload: [qwen3.8-27b]`.

3. **README.md, AGENTS.md** — таблицы режимов (6 ID), путь модели,
   команды переключения, логи/restart только llama-swap.

4. **Документы** — этот план, ADR 0001, CONTEXT.md.

## Тестирование

1. Старт: `docker compose --profile llama up -d --wait --wait-timeout 1800`.
2. Загрузка VRAM: `nvidia-smi` — суммарная загрузка ~87%, на GPU1 свободно
   не менее 512 MiB, графическая сессия жива.
3. `/v1/models` — ожидаются `qwen3.8-27b`, `qwen3.8`, `ornith-9b` и 6 ID
   режимов.
4. `/apply-template` с `enable_thinking: false` и `preserve_thinking` —
   шаблон не падает (риск: официальный шаблон Qwen3.8 может кидать
   исключение на `enable_thinking: false`; fallback — убрать kwarg, оставить
   `reasoning: off` + `reasoning-budget: 0`).
5. По одному streaming-запросу на каждый из 6 ID: HTTP 200, контент непустой;
   reasoning присутствует/скрыт по режиму; effort применяется.
6. Переключение: unload qwen -> запрос ornith -> unload ornith -> запрос
   qwen (~40-60 c загрузки).

## Результаты (2026-08-17)

Все проверки пройдены:

1. Старт и прелоад `qwen3.8-27b` за ~10 c (страницы в page cache).
2. Загрузка VRAM: суммарная ~0.92 (включая графическую сессию; без неё
   ~0.89). Для соблюдения правила ≥512 MiB свободно на GPU1 (дисплей)
   добавлен `--tensor-split 52,48`: GPU1 ~700 MiB свободно, GPU0 ~480 MiB.
   При каждой загрузке llama.cpp сначала получает OOM при резервировании
   compute-буферов с pipeline parallelism и успешно ретраит без него —
   нормальный путь загрузки.
3. `/v1/models` — все 9 ID + алиас `qwen3.8`.
4. `/apply-template` с `enable_thinking: false` не падает (риск froggeric не
   подтвердился); шаблон всегда эмитит thinking-блоки, а отключение
   обеспечивает `reasoning: off` + `reasoning-budget: 0`.
5. Все 6 ID отвечают; reasoning возвращается в поле `reasoning_content`
   (не `reasoning`, как у vLLM); у `qwen3.8-27b-chat` он скрыт из content,
   у agent-режимов preserve работает (прошлый reasoning попадает в промпт
   следующих ходов — prompt_tokens 95 против 40).
6. `reasoning_effort` применяется (xhigh добавляет system-инструкцию).
7. Переключение через unload API работает в обе стороны: qwen -> ornith
   (4 c), ornith -> qwen (~10 c). Стриминг стабилен (reasoning_content в
   дельтах, ~40 t/s, 600 токенов, VRAM без изменений).