# Реализация: конфиги, compose и потребители

Type: task
Status: resolved
Blocked by: 04, 05

## Question

Внести изменения, зафиксированные тикетами «Топология» и «Конфиг единого
endpoint'а»:

1. Привести конфиг(и) llama-swap к решению тикета конфига: один ID
   `qwen3.8-27b`, без алиасов `-chat-*`/`-agent-*`, без серверного мнения о
   reasoning (sampling — дефолт движка в `cmd`; в `filters` остаются
   `stripParams: repetition_penalty` и `useModelName`); пины и профили — по
   тикету «Топология».
2. Привести `docker-compose.yaml` и профильные compose-файлы к топологии из
   тикета «Топология»: свой образ llama-swap (запиненные llama-swap v265 +
   llama.cpp b10068, см. тикет «Выбор версии образа llama-swap»), два
   движка за одним контейнером. `vllm/` не трогать — вне карты.
3. Обновить потребителей:
   - `~/.config/opencode/opencode.jsonc` — один ID, дефолтный агент и `plan`;
   - инвентаризировать остальных потребителей (llm-monitoring, заметки,
     сторонние клиенты) и обновить/зафиксировать.
4. Проверить конфиг llama-swap на валидность (`/v1/models`, запуск профилей)
   без полного нагрузочного прогона.

Материалы: решения тикетов 04/05, ADR-0002/0004 (прецедент удаления ID без
backcompat). Изменение конфига требует перезапуска llama-swap.

## Answer

Реализовано (2026-10-17) по решениям тикетов «Топология» (04), «Конфиг единого
endpoint'а» (05), «Выбор версии образа» (09) и «Остаточное серверное мнение»
(10). Доказательства — `.scratch/llama-swap-orchestrator/assets/06-implement/`
(`README.md`, `image-checks.txt`, `run-smoke.sh` + `smoke.log`, `smoke/`).
Изменения застейджены, не закоммичены; запущенный контейнер `llama-swap`
(старый образ `llm-server/ninfer-tp2:v0.4.6`) не тронут — живая смена
контейнера на новый образ это тикет 07.

### 1. Конфиг llama-swap → каталог `router/`

- `router/config.yaml` — глобалы (`healthCheckTimeout: 600`, `logToStdout:
  both`, `sendLoadingState: true`, без `includeAliasesInList`/`globalTTL`),
  `hooks.on_startup.profile: ninfer` + `preload: [backend-ninfer]` и профили
  `llama`/`ninfer` с пинами (`qwen3.8-27b` → движок, неактивный `backend-*` →
  `~`).
- `router/config.d/10-llama.yaml` — `models.backend-llama`: `unlisted: true`,
  пер-модельный `env: LD_LIBRARY_PATH=/app:/usr/local/cuda-13.3/lib64`, `cmd`
  llama-server (b10068) с sampling-пресетом в CLI
  (`--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0
  --repeat-penalty 1.0`), `capabilities` (`text+image`/`text`/`tools`/180224),
  `filters.stripParams: repetition_penalty`.
- `router/config.d/20-ninfer.yaml` — `models.backend-ninfer`: `unlisted`,
  `useModelName: qwen3.8-27b`, `env` с `/opt/ninfer/lib` первым, `cmd`
  ninfer-serve (DFlash2-профиль), `capabilities` (262144), тот же
  `stripParams`. `setParamsByID`/`filters` прочего нет — reasoning и sampling
  задаёт клиент, движок даёт пресет по умолчанию (ADR-0006).

### 2. Образ и compose

- `router/Dockerfile` — `ubuntu:26.04` + FFmpeg 8; `COPY --from`
  `ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865…708e`
  (`/app`, `/usr/local/cuda-13.3/lib64`); NInfer-тарбол v0.4.6 и бинарник
  llama-swap v265 — по SHA-256 (значения из тикета 09). ENTRYPOINT
  `llama-swap -config /app/config.yaml -config-dir /app/config.d`.
- `router/docker-compose.yaml` — единственный сервис `llama-swap`, **без**
  ключа `profiles:` (поднимается всегда, и с любым `--profile`); образ
  `llm-server/router:v265`, `container_name: llama-swap`, `:8080`, обе GPU,
  `compute,utility`, монтирование `/opt/models`, `config.yaml`, `config.d`.
- Корневой `docker-compose.yaml` — `include` теперь `./router/` и `./vllm/`.
- Удалены `llama/` (целиком) и `ninfer/`; `ninfer/fetch-model.sh` переехал в
  `router/fetch-model.sh` (пути/комментарии обновлены). `vllm/` не тронут.

### 3. Проверки (п.4, без полного нагрузочного прогона)

- `-validate` на запиненном v265: `config is valid: 2 model(s), 0 peer(s)` —
  и нативным бинарником, и внутри собранного образа с монтированием из compose.
- Образ собран: `llama-swap --version` → `v265 (d1e743f)`, `llama-server
  --version` → `10068 (571d0d540)`, glibc 2.43 / Ubuntu 26.04.1. Ключевое:
  `ninfer-serve` с пер-модельным `LD_LIBRARY_PATH` берёт `libcudart.so.13` из
  `/opt/ninfer/lib`, а не из CUDA 13.3 (`libcuda.so.1` даёт runtime хоста).
- `compose config --services`: `llama-swap` стартует без профиля и с
  `--profile llama`/`ninfer`; `--profile vllm` даёт `llama-swap` +
  `vllm-server` (оба на `:8080` — см. п.5).
- Offline-смоук с фиктивными backend'ами: `/v1/models` = ровно
  `['qwen3.8-27b']`, `backend-*` скрыты; смена профиля `llama`→`ninfer`→`none`
  (`none` убирает публичный ID); пин `~` → `404` и на `/v1`, и на `/upstream`;
  `useModelName` доходит как `model: qwen3.8-27b`; `repetition_penalty`
  вырезается, `temperature`/`reasoning_effort` проходят; у llama-swap в любой
  момент ровно один движок-ребёнок (непараллельность).

### 4. Потребители (инвентаризация)

- `~/.config/opencode/opencode.jsonc` — `baseURL` исправлен на
  `http://localhost:8080/v1` (был нерабочий `192.168.17.69:9000`); модели
  сведены к одному `qwen3.8-27b` с дефолтными client-side настройками
  (`reasoningEffort: medium`, `chat_template_kwargs.preserve_thinking: true`);
  `model` и `agent.plan` указывают на него, у `plan` — `reasoningEffort:
  xhigh`. JSON валиден.
- `llm-monitoring` (репозиторий `infrastructure`) — профиль `ninfer` больше не
  выбирает сервис: `llm-stack.sh` мапит `llama`/`ninfer` на `llama-swap`;
  для `vllm` launcher исключает всегда-поднимающийся роутер (иначе конфликт за
  `:8080`) и поднимает мониторинг + `vllm-server`; README-таблица и usage
  обновлены.
- `scripts/nvidia-p2p/bench.py` — пример с удалённым `qwen3.8-27b-chat-medium`
  заменён на `qwen3.8-27b`. `soak.sh` (дефолт `qwen3.8-27b`) правки не требует.
- Больше нигде в `projects/00 infra` (в т.ч. `local-llm-inference`,
  `llm-benchmark`, `bifrost-gateway`, `LLM-Switcher-Monitoring`) нет ссылок на
  старые ID: grep по `qwen3.8-27b-*`/`:9000` даёт только этот репозиторий и
  архив чатов `homelab-chat-history`.

### 5. Передано дальше / не покрыто

- **Тикет 08 (документация):** `AGENTS.md` (разделы про `llama/`, `ninfer/`,
  таблицы 7 ID, команды `--profile … build/logs/restart ninfer-swap`,
  `./ninfer/fetch-model.sh`), `README.md` (дерево каталогов, команды переключения,
  `llama/config.yaml`), `CONTEXT.md` (термины «Режим»/«Тип режима»/«Уровень
  reasoning»/«Preserve thinking», три профиля), `docs/NVIDIA_SETUP.md` и
  `docs/NVIDIA_P2P.md` (команды `--profile …`). Инструкция переключения —
  `PUT /api/profiles/active`, первый запрос после смены платит загрузку весов.
- **Тикет 07 (живой GPU-прогон):** замена запущенного контейнера на
  `llm-server/router:v265`, реальная загрузка llama.cpp/NInfer, минимум VRAM на
  дисплейной GPU1, поведение opencode-субагентов.
- **vLLM:** профиль `vllm` теперь соседствует с всегда-поднимающимся роутером
  (оба `:8080`). `vllm/` в этом усилии не меняется; сосуществование — отдельный
  effort (вне карты).

## Comments

**2026-10-17.** Тикет взят в работу при frontier-сканировании (06 открыт и
разблокирован: 04, 05 resolved). Подтверждены при выполнении: SHA-256 тарбола
llama-swap v265 (`cb1f9a94…5dcfa1`, member `llama-swap`) и дайджест образа
llama.cpp `server-cuda13-b10068`
(`sha256:6447a865…708e`) — оба совпали с тикетом 09.
