# Evidence — ticket 04 «Топология: llama.cpp и NInfer за одним llama-swap»

Дата: 2026-10-17. Проверка на хосте проекта: запиненный бинарник **llama-swap
v265** (`llama-swap_265_linux_amd64.tar.gz`,
`sha256=cb1f9a94be05afa129d3c17868f1dd2ca710b919333c7b868239dc31575dcfa1`,
`version: v265 (d1e743f), built at 2026-10-14T08:30:34Z`) + фиктивные backend'ы
(`assets/09-llama-swap-version/fake_backend.py`). GPU не использовался: все
`cmd` в тестовых конфигах — `sleep 3600`, `checkEndpoint: none`.

## Файлы

| Файл | Что показывает |
|---|---|
| `topo-test.yaml` | профили `llama`/`ninfer` с пинами (`qwen3.8-27b` → backend, неактивный backend → `~`), `unlisted: true`, `hooks.on_startup.profile: llama`, `preload: [backend-llama]` |
| `topo-test3.yaml` | то же + фантомная реальная модель `qwen3.8-27b` (проверка метаданных в `/v1/models`) |
| `topo-test4.yaml` | то же, но стартовый профиль `ninfer`, `preload: [backend-ninfer]`, плюс третий backend `other-model` с собственным публичным ID |
| `topo.log` | лог `topo-test.yaml`: `preloading model: backend-llama`, `group: starting swap for model backend-ninfer, evicting [backend-llama]` → `process stopped by llama-swap` → старт нового cmd |
| `topo2.log` | лог смены профиля без запроса (движок остаётся загруженным) |
| `topo4.log` | лог `topo-test4.yaml` |
| `Dockerfile.draft` | черновик объединённого образа (проверен сборкой, в репозиторий не внесён) |
| `combined-image-checks.txt` | `--version`, `ldd`, glibc и объёмы этого образа |

## Воспроизведение

```bash
# бинарник v265
curl -sL -o ls265.tar.gz https://github.com/mostlygeek/llama-swap/releases/download/v265/llama-swap_265_linux_amd64.tar.gz
sha256sum ls265.tar.gz   # cb1f9a94…5dcfa1
tar -xzf ls265.tar.gz
./llama-swap -config topo-test.yaml -validate        # config is valid: 2 model(s)
python3 fake_backend.py fakellama 19001 &
python3 fake_backend.py fakeninfer 19002 &
./llama-swap -config topo-test.yaml -listen 127.0.0.1:8128

# черновик объединённого образа
docker build -f Dockerfile.draft -t imgtest/router-draft .
```

## Наблюдения, использованные в решении

- **Стартовый профиль.** `hooks.on_startup.profile` есть в v265: сразу после
  старта `GET /api/profiles` → `{"active":"llama",…}`, `/v1/models` показывает
  ровно `qwen3.8-27b` (`meta.llamaswap.type = "profile"`) — публичный ID не
  «мигает» после перезапуска.
- **Пин `~` = запрет.** `POST /v1/chat/completions {"model":"backend-ninfer"}`
  при активном профиле `llama` → `404`; `POST
  /upstream/backend-ninfer/v1/chat/completions` → тоже `404`. Обходной тропы к
  выключенному движку нет.
- **Публичный ID маршрутизируется.** `model: qwen3.8-27b` приходит в
  выбранный `proxy` с `received_model: qwen3.8-27b` (значит `useModelName`
  применяется после пина — требование NInfer `request.model == --model-id`
  выполнимо, подтверждает тикет 09).
- **Непараллельность.** `topo.log`: `starting swap for model backend-ninfer,
  evicting [backend-llama]` → `[backend-llama] process stopped by llama-swap` →
  `Executing start command` для нового движка. Выгрузка строго до старта;
  в `pgrep -ax sleep` в любой момент ровно один процесс.
- **Смена профиля ≠ выгрузка.** `PUT /api/profiles/active {"name":"ninfer"}`
  без запросов: процесс ранее прелоаднутого движка продолжает работать;
  первый запрос после переключения и вызывает swap.
- **Метаданные единого ID.** Запись из пина синтетическая: `name` пустой,
  `capabilities`/`context_length` отсутствуют, `status: unloaded` всегда. У
  реальной модели с тем же ID (`topo-test3.yaml`) `/v1/models` отдаёт
  `name`, `architecture.input_modalities`, `capabilities.function_calling`,
  `context_length: 180224`, но запросы всё равно перехватывает пин, а `status`
  остаётся `unloaded` (фантом никто не запускает).
- **Новый backend по своему ID.** `topo-test4.yaml`: профиль `ninfer` активен,
  `other-model` не спрятан и не запинен → `/v1/models` показывает
  `['other-model', 'qwen3.8-27b']`; запрос `other-model` уходит в третий
  backend и выгружает NInfer (pid процесса сменился) — автопереключение по
  запросу работает без правок compose.
- **Объединённый образ.** `ubuntu:26.04` + `COPY --from=llama.cpp /app` и
  `/usr/local/cuda-13.3/lib64` + `/opt/ninfer`: собирается; `/app/llama-server
  --version` → `10068 (571d0d540)`; glibc 2.43 запускает бинарники, собранные
  на glibc 24.04; `ldd` чист, кроме `libcuda.so.1` (даёт runtime хоста).
  `ninfer-serve` без GPU не стартует даже с `--version` (нужен
  `libcuda.so.1`) и при общем `ENV LD_LIBRARY_PATH` подхватывает
  `libcudart.so.13` из CUDA 13.3, а не свой из `/opt/ninfer/lib` (RPATH нет;
  проектный `serve-tp2.sh` сам ставит `$here/lib` первым) → per-model
  `env:` обязателен. Объёмы: `/app` 185 M, CUDA 1.7 G, `/opt/ninfer` 782 M.

## Не проверено здесь

- Реальная загрузка моделей на GPU в объединённом образе (в т.ч. выбор
  libcudart для NInfer) — тикет «Проверка через opencode-субагентов».
- Свободная VRAM дисплейной GPU1 — вне этого тикета (red line из карты).
