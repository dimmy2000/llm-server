# ADR-0009: Безпрофильная топология — три прямые cmd-модели и образ v265-strata1-nollama

Status: accepted (2026-11-17; верифицирован 2026-11-17 на живом железе).

Supersedes ADR-0008 §2 в части отклонения полностью плоской схемы (без
профилей) и ADR-0006 в части бэкенда llama.cpp и vLLM-профиля. Контейнерная
механика ADR-0008 (Strata — ребёнок llama-swap, RAM-гейт, fail fast,
автоматический swap) и клиентский контракт трёх ID остаются в силе.

## Контекст

После ADR-0008 система — это llama-swap v265 с двумя профилями родителя
(`llama`/`ninfer`) и двумя strata `cmd`-моделями. Механика профилей
существовала исключительно для выражения «один ID → два движка» для
`qwen3.8-27b`
(llama.cpp ↔ NInfer по `PUT /api/profiles/active` или пикеру UI).

Решение пользователя (2026-11-17): убрать бэкенд llama.cpp из роутера и из
образа, вынести vLLM-профиль из топологии. Оба шага снимают основания
профильной схемы:

- отклонение плоской схемы в ADR-0008 §2 — «у v265 одна модель = один
  `cmd`, а `groups`/`matrix` не выражают «один ID → два движка»» —
  аннулируется: второго родителя нет, у `qwen3.8-27b` ровно один движок
  (NInfer);
- vLLM-профиль был выделен из топологии заранее и не используется.

Двойное следствие удаления llama.cpp:

1. **Конфиг**: `qwen3.8-27b` становится прямой `cmd`-моделью наравне со
   strata-ID, секция `profiles:` удаляется целиком (вариант пользователя —
   именно полное удаление, не один фиксированный профиль).
2. **Образ**: ggml-образ `llama.cpp:server-cuda13-b10438` был источником и
   бинарника llama.cpp (`/app`), и CUDA 13.3 runtime-библиотек
   (`/usr/local/cuda-13.3/lib64`), на которые линкуются NInfer и Strata.
   Наивное удаление стадии ломает оба движка — библиотеки обязаны сохраниться
   бит в бит (смена бита библиотек = новая точка калибровки, см. правило
   AGENTS про версии движков).

Проверка реализуемости по источникам v265 (`../llama-swap`): конфиг без
секции `profiles:` валиден (проверяются только ошибки профилей/пинов, правила
непустоты нет); `hooks.on_startup.preload` разрешается по ID моделей
независимо от профилей; `ActiveProfile()` возвращает `""` и обрабатывается
nullable-путём; модели без явного `routing:` переписываются
`AddDefaultGroupToConfig` в дефолтную exclusive-группу — порядок unload→start
сохраняется.

## Решение

### 1. Топология без профилей: три прямые cmd-модели

- `router/config.yaml`: секция `profiles:` удалена целиком;
  `hooks.on_startup: {preload: [qwen3.8-27b]}` (без ключа `profile:` —
  прелоад по публичному ID). Глобальные ключи без изменений
  (`healthCheckTimeout: 600`, `logLevel: info`, `logToStdout: both`,
  `sendLoadingState: false`).
- `router/config.d/20-ninfer.yaml`: ключ модели `backend-ninfer` →
  `qwen3.8-27b`; убраны `unlisted: true` и `useModelName: qwen3.8-27b`
  (в `cmd` уже есть `--model-id qwen3.8-27b`, `request.model` совпадает
  без переписывания); `env` (`LD_LIBRARY_PATH` с `/opt/ninfer/lib` первым),
  `cmd` и прочее — без изменений.
- `router/config.d/10-llama.yaml` удалён; каталог `vllm/` удалён, include
  `./vllm/docker-compose.yaml` убран из корневого `docker-compose.yaml`
  (остался только `./router/docker-compose.yaml`).
- Все три модели живут в одной дефолтной exclusive-группе v265 — автоматический
  swap, FIFO-сериализация, RAM/VRAM-безопасность ADR-0008 без изменений.
  `GET /api/profiles` = `{"active": null, "profiles": []}`.
- Ручного выбора движка больше нет: `PUT /api/profiles/active` не нужен,
  backend-моделей `backend-*` нет; выбор движка — только через ID.

### 2. Образ `v265-strata1-nollama`: без бинарника llama.cpp, CUDA 13.3 сохранена

- `router/Dockerfile`: строка `COPY --from=<ggml> /app /app` (бинарник
  llama.cpp) заменена на `RUN mkdir -p /app` — следующая строка
  `tar -xzf … -C /app llama-swap` требует каталог. Строка
  `COPY --from=<ggml> /usr/local/cuda-13.3/lib64 /usr/local/cuda-13.3/lib64`
  сохранена **без изменений** с тем же digest-пином
  `server-cuda13-b10438@sha256:bb81f3e4…6283`: CUDA 13.3 runtime
  (`libcudart.so.13.3.29`, `libcublas.so.13.5.1.27`) — бит в бит с
  работающим образом, новая точка калибровки не возникает.
- Почему именно ggml-образ, а не `nvidia/cuda`: b10438 — последний
  опубликованный cuda13-образ ggml-org с CUDA 13.3 (с b11706 ggml-org
  перешёл на 13.4). Миграция источника библиотек на `nvidia/cuda` —
  отдельный будущий тикет (смена бита библиотек требует повторной
  калибровки обоих движков).
- Строка apt (`libssl3t64`, `libgomp1`, `libatomic1`, `libav*62` — общие
  зависимости), build-стадия `strata-build`, пин NInfer v0.4.6 — без
  изменений. Тег `llm-server/router:v265-strata1-nollama`; старый образ
  `v265-strata1` не удаляется — точка отката.
- В `/app` образа теперь только `llama-swap` (конфиги и `strata/` —
  маунты). Образ 6.54 ГиБ против 6.88 ГиБ старого (−~340 МБ — бинарник
  llama.cpp).

### 3. Верификация (2026-11-17, живое железо)

- Сборка: `docker compose build llama-swap` — 5 мин 06 с, exit 0
  (тяжёлая компиляция `strata-build` не пересобиралась).
- Старт: контейнер пересоздан на новый образ, healthy ~6 c; on_startup —
  `preloading model: qwen3.8-27b`; NInfer готов за 6.9 c (weights 20.3 GiB,
  4.12 GiB/s, `p2p on`); строка `[ERROR] failed to preload model
  qwen3.8-27b: status 404` — ожидаемая косметика (у NInfer нет
  warmup-эндпоинта). Ошибок отсутствующих библиотек нет.
- Библиотеки (детерминированно): `ls /app` — только `llama-swap` (нет
  llama-server); `/usr/local/cuda-13.3/lib64` содержит libcudart/libcublas;
  `dpkg` — libatomic1/libgomp1/libssl3t64/libavcodec62 на месте;
  ldd-сета «not found» трёх бинарников движков (`strata`, `strata-vision`,
  `ninfer-serve`) **бит в бит идентичны** в старом и новом образах
  (сравнение `docker run`).
- API: `/v1/models` — ровно `qwen3.8-27b`, `strata-iq2`, `strata-iq3`;
  `/api/profiles` — `{"active": null, "profiles": []}`.
- Функционально: completion `200` + непустой ответ на все три ID
  (`qwen3.8-27b` — с `chat_template_kwargs: {enable_thinking: false}`;
  strata-ID — с `reasoning_effort: none`); поле `model` в ответе strata —
  канон native-ID (`qwen3.8-flash-next-iq3_xxs`/`…-iq2_xs`), как требует
  контракт ADR-0007/0008.
- Swap-цикл qwen → iq3 → iq2 → qwen (стоимость первого запроса, client-side):
  37.8 / 22.7 / 8.0 c. Внутреннее: iq3 — эксперты 39.97 GiB за 23 c
  (6.21 GiB/s), health движка через +36.5 c от старта (холодный page cache
  после пересоздания: MemAvailable ~49 ГиБ, experts в кэше не были);
  iq2 — эксперты 33.02 GiB (6.46 GiB/s), health +20.6 c; NInfer после
  вытеснения — engine ready 7.1 c.
- Красная линия: GPU1 free 709 MiB после цикла (≥ 512 MiB). Замечание:
  client-side iq3 37.8 c против прежних сэмплов 17.8–20.9 c (тик 11) —
  расхождение объясняется холодным page cache; iq2 и qwen-cold в пределах
  прежних профилей (12.7–13.8 c и 7.4–8.9 c).

## Отвергнутые альтернативы

- **Один фиксированный профиль `ninfer`**: сохраняет механику профилей,
  `PUT` API и пикер UI без содержания; плоская схема реализуема на v265,
  когда второго родительского движка нет (см. «Контекст», проверка по
  источникам).
- **Новый источник CUDA — `nvidia/cuda:13.x`**: смена бита библиотек для
  обоих движков = новая точка калибровки; ggml-digest бит в бит с работающим
  образом. Отклонено, отложено отдельным тикетом.
- **Переиспользование тега `v265-strata1`**: теряется точка отката.
  Отклонено.
- **Пересборка `--no-cache`**: входы `strata-build` не менялись; обычная
  сборка за 5 минут использовала кэш. Отклонено.

## Последствия

- Профилей llama-swap больше нет: `PUT /api/profiles/active`, пикер UI,
  preference родителя и backend-модели уходят в историю. Состояние системы —
  SSE `/api/events`, `GET /v1/models`, `/health` upstream-порта.
- `qwen3.8-27b` — только NInfer; reasoning/sampling-контракт — ninfer'овский
  (top-level `reasoning_effort` `none|low|medium|xhigh`,
  `chat_template_kwargs.{enable_thinking, preserve_thinking}`, невалидное →
  `400`); `stripParams: repetition_penalty` — у всех трёх моделей.
- Публичный контракт трёх ID и конфиг opencode не меняются; клиенты не
  тронуты.
- GGUF-модель `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/` сохранена на хосте
  (вне топологии); раздел «Движок llama.cpp» AGENTS.md — архивная заметка.
- vLLM вне топологии: `vllm/` и include снесены; модель хоста
  `/opt/models/Qwen3.8-27B-NVFP4/` сохранена.
- Механика ADR-0008 (страта-ребёнок, RAM-гейт 46/36 ГиБ, fail fast без
  ретраев, автоматический swap) действует без изменений; отклонённое в нём
  §2 (плоская схема) теперь реализовано.
- Откат: образ `v265-strata1` + конфигурации из git-истории; нативная
  Strata 0.1.44 на хосте сохранена.

Опора: ADR-0008 (§2 — отклонённая плоская схема, пп. 1–3 — механика,
которая сохраняется), ADR-0006 (пин llama.cpp, безопасное подмножество,
контракты), источники v265 в `../llama-swap` (валидация конфига без
`profiles:`, `hooks.on_startup.preload` по ID моделей, `ActiveProfile()`
nullable, `AddDefaultGroupToConfig`), docker-лог сборки (exit 0),
`docker logs llama-swap` от 2026-11-17 (stарт-прелоад, swap-цикл, строки
движков), ldd-сравнение старого/нового образов, `nvidia-smi`.
