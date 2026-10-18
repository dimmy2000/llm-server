# Доказательства тикета 11 — бамп llama.cpp b10068 → b10438

Собрано 2026-10-17. Цель — показать, что пин
`ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4…6283` в
`router/Dockerfile` действительно содержит обработку OAI-поля
`reasoning_effort`, что оно работает через единый endpoint `:8080` под обоими
движками, и что красная линия VRAM при этом держится. Отчёт —
`docs/research/0015-llama-cpp-bump-reasoning-effort.md`.

## Верхний уровень

| Файл | Что это |
|---|---|
| `image-checks.txt` | статическая проверка образа после пересборки: ID образа `llm-server/router:v265` (`sha256:ef2b6277…`), `llama-server --version` (`build 10438, commit 9d57ce456`), список `/app`, `grep -a` по `reasoning_effort`/`enable_thinking` в `libllama-server-impl.so` и `libllama-common.so` — и тот же grep по негативному контролю (старый пин b10068: 0 вхождений `reasoning_effort`) |
| `probe-reasoning.sh` | 12 кейсов reasoning: голый ID, top-level `none/low/medium/xhigh`, kwargs `enable_thinking:false`, kwargs `reasoning_effort: none/low/xhigh/banana`, top-level `banana`, top-level `low` + kwargs `enable_thinking:true`. Streaming через `:8080`, сводка — длина `reasoning_content` + `content` |
| `probe-tools.sh` | 4 кейса tools: `tools` с голым ID / с top-level `none`, и контроль без `tools` (проверка, что инструмент не исполняется) |
| `run-pass.sh` | обёртка для одного движка: запускает оба пробника под сэмплером VRAM (каждые 2 с), снимает `ps.txt` и `docker logs llama-swap` |
| `apply-template-probe.py` | только llama: `POST /apply-template` напрямую в `llama-server` (`:5800` внутри контейнера, минуя llama-swap) — возвращает собранный шаблоном промпт; проверяет, дошло ли поле клиента до шаблона |

Пробники требуют уже загруженного движка (иначе первая проба платит загрузку
весов и ловит баннер llama-swap в `reasoning_content` — тикет 13). Профиль
переключается снаружи: `PUT /api/profiles/active {"name":"llama"|"ninfer"}`,
скрипты его не трогают.

## Подкаталоги `llama/` и `ninfer/`

Одинаковая структура на каждый движок:

- `NN-<case>.sse` / `NN-<case>.json` — сырые ответы проб (streaming SSE /
  non-streaming JSON); нумерация и имена кейсов соответствуют порядку в
  `probe-reasoning.sh` (01–12) и `probe-tools.sh` (01–04);
- `probe-reasoning.txt`, `probe-tools.txt` — сводки пробников (то, что печатает
  скрипт);
- `vram.csv` — свободная VRAM по GPU за прогон (сэмпл каждые 2 с,
  `index,memory.free` через `;`); `vram-min.txt` — минимум по каждому GPU
  (красная линия — ≥ 512 MiB на дисплейной GPU1);
- `ps.txt` — какой движок был жив во время прогона (доказательство
  непараллельности);
- `container.log` — `docker logs llama-swap` за прогон.

Только в `llama/`:

- `apply-template.txt` — вывод `apply-template-probe.py`: длина промпта и
  первый блок рендера для каждого кейса (bare, effort-none/low/medium/xhigh,
  banana, kwargs enable_thinking:false, kwargs effort low, none+kwargs-false,
  none+kwargs-effort-low). Ключевые строки: `effort-none` == bare (325, xhigh),
  `kwargs-enable-false` — 99, `none + kwargs-effort-low` — 325 (доказательство,
  что ветка `none` стирает kwargs).

## Что здесь читается как доказательство

- **Бамп реально в образе**: `image-checks.txt` (`build 10438, commit
  9d57ce456`; `reasoning_effort` = 1/5 вхождений против 0/0 у контроля b10068);
  `system_fingerprint":"b10438-9d57ce456"` в каждом сыром ответе `.sse`/`.json`.
- **Top-level `reasoning_effort: low|medium|xhigh` работает на llama b10438**:
  `llama/probe-reasoning.txt` (191/391/444 chars против инертного 441 у `none`
  и 384 у bare) — до бампа все эти кейсы давали thinking без реакции.
- **Top-level `none` инертен на llama, работает на NInfer**:
  `llama/probe-reasoning.txt` (441) против `ninfer/probe-reasoning.txt` (0);
  механика стирания kwargs — `llama/apply-template.txt`.
- **Невалидные значения**: llama `500` (raise шаблона), NInfer `400` с списком
  допустимых значений — `llama/0{8,11}*` и `ninfer/0{8,11}*`.
- **Tools не деградировали**: `llama/probe-tools.txt` / `ninfer/probe-tools.txt`
  — `get_weather` с корректными аргументами с thinking и без.
- **Красная линия VRAM**: `*/vram-min.txt` — llama GPU0 915 / GPU1 1171 MiB,
  ninfer GPU0 1199 / GPU1 710 MiB.
- **Непараллельность**: `*/ps.txt` — ровно один движок за прогон.

## Воспроизведение

```bash
# 1. собрав образ и подняв стек, переключить профиль и дождаться загрузки движка
curl -s -X PUT localhost:8080/api/profiles/active -H 'Content-Type: application/json' -d '{"name":"llama"}'
# прогреть одним запросом (см. probe-reasoning.sh 01-bare)

# 2. снять доказательства
cd .scratch/llama-swap-orchestrator/assets/11-llama-bump
./run-pass.sh llama

# 3. то же для ninfer
curl -s -X PUT localhost:8080/api/profiles/active -H 'Content-Type: application/json' -d '{"name":"ninfer"}'
./run-pass.sh ninfer

# 4. render-пробы (только llama, профиль llama активен)
python3 apply-template-probe.py > llama/apply-template.txt

# 5. статическая проверка образа (команды — ниже и в отчёте 0015)
# результат ложится в image-checks.txt
```

Статическая проверка из `image-checks.txt` делается командами вида:

```bash
docker run --rm --entrypoint /app/llama-server <image> --version
docker run --rm --entrypoint sh <image> -c \
  'for f in /app/libllama-server-impl.so /app/libllama-common.so*; do
     echo "$f $(grep -ao reasoning_effort $f | wc -l)"; done'
```
