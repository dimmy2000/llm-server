# Research 01: Совместимость llm-bench с роутером llama-swap v265 (:8080)

Дата: 2026-11-17. Среда: роутер `llama-swap` v265 (контейнер `llama-swap`, API
`http://localhost:8080`), три модели в одной exclusive-группе. Исходники
llama-swap читались на теге `v265` (коммит `d1e743f`, «CHANGELOG: v265») —
локальное репо на HEAD новее (v273+4), поэтому дерево пина было распаковано
`git archive v265` в `/tmp/llama-swap-v265` (рабочее дерево репо не тронуто).

Ключевые вердикты (подробности ниже):

1. **Стриминг через роутер — работает как есть** для всех трёх моделей:
   `stream_options.include_usage` и `chat_template_kwargs` проксируются без
   изменений; у NInfer в финальном чанке есть И `usage.prompt_tokens`, И блок
   `timings` (стр. «Стрим NInfer»). Prefill-скрипт работает как есть, причём
   для NInfer даже без client-side фоллбека.
2. **Главный блокер — prepare/make-chunks**: оба хардкодят
   `model: "bench-prepare"` в `count_tokens` и FLUSH-запросе. Через роутер это
   404 «no router for requested model» (живой факт). Нужен однострочный патч
   в рабочей копии клона (заменить на реальный ID модели).
3. **`/v1/messages/count_tokens` есть у ОБОИХ движков** (у NInfer тоже!):
   через роутер отвечает 200 `{"input_tokens": N}`. Токенизаторы совпадают
   (статическое сравнение + живой кросс-счёт: один текст → 71 токен и у NInfer,
   и у Strata). Чанки можно габаритировать одним движком для всех моделей.
4. **`/v1/models` упорядочен по алфавиту ID** (детерминировано):
   `qwen3.8-27b, strata-iq2, strata-iq3`; первый ID = `qwen3.8-27b`. Скрипты
   по умолчанию берут первый ID → **MODEL/--model надо задавать явно**
   (иначе бенчится qwen3.8-27b для всех трёх моделей).
5. **Warmup prefill-скрипта на глубине 120k у iq3 не влезает в контекст**
   (150 020 токенов > 131 072) → 400 → незахваченное исключение, скрипт
   умирает на глубине 120k. Однострочный патч коэффициента `depth // 12` →
   `depth // 15` (стр. «Бюджет контекста»).
6. FLUSH-шаг prepare/make-chunks (235k-токенный запрос) через роутер не
   сработает в любом случае (404 на bench-prepare; после патча — 400 на iq3,
   т.к. 235k > 131k). Это не фатально: per-depth warmup prefill-скрипта
   выполняет ту же функцию вытеснения кэша на целевом движке. Рекомендация:
   `FLUSH=0` при сборке чанков.

---

## 1. Что шлют скрипты (факты из кода, `/tmp/llm-bench-peek`)

### bench-real-prefill.sh
- Env: `URL` (дефолт `http://localhost:8082`), `MODEL` (дефолт — первый ID из
  `/v1/models`), `DATA_DIR` (дефолт `<dir скрипта>/realdata`),
  `DEPTHS` (дефолт `40000,150000,200000`), `RUNS=3`, `MAX_TOKENS=16`,
  `DECODE_PROBE=1`, `DECODE_TOKENS=128`, `DECODE_RUNS=3`, `CLIENT=0`,
  `QUIET=1`.
- Тело запроса (`POST /v1/chat/completions`, SSE-стрим):
  `{"model": MODEL, "messages": [user], "max_tokens": …, "stream": true,
  "stream_options": {"include_usage": true},
  "chat_template_kwargs": {"enable_thinking": false}}`.
- **Хард-фейл без `usage` в стриме** (`RuntimeError: no usage in stream
  (engine did not echo prompt_tokens)`); `timings` — опционален (нет →
  client-side tok/s).
- На каждую глубину: warmup (filler ~`depth//12` повторов строки, max_tokens=4,
  НЕ в try/except), затем decode-пробник (RUNS=3, чанки `{depth}-d1..d3.txt`),
  затем замер prefill (RUNS=3, чанки `{depth}-{a,b,c}.txt`). Итого на глубину
  6 чанков — ровно то, что строит prepare.
- `manifest.json` читается, но не используется (только `json.load`).

### bench-real-prefill-prepare.sh
- Env: `URL` (дефолт :8082), `DATA_DIR`, `DEPTHS` (дефолт 40/150/200k),
  `FORCE`, `FLUSH` (дефолт 1). **Никакого env для модели — в теле
  `count_tokens` и FLUSH-запроса хардкод `"model": "bench-prepare"`** (2 места).
- Габаритирование: бинарный поиск по `POST /v1/messages/count_tokens`
  (то же тело, `input_tokens` из ответа), допуск ±0.5%, рез по абзацам.
- На глубину создаёт 6 чанков: `a,b,c` + `d1,d2,d3` (PLAN: фикс. книги на
  слоты; для не-дефолтных DEPTHS — round-robin по книгам). Текст всех чанков
  в рамках одного прогона взаимно непересекаемый (курсоры по книгам).
- Книги: 6 PDF/текст с Gutenberg (~13.2 МБ суммарно, ~3.3M токенов); первый
  запуск скачивает (~12 МБ, нужен интернет).
- **FLUSH-шаг** (идёт даже при skip по манифесту): считаем через
  `count_tokens` 160k случайных NATO-слов, обрезаем до ~235k токенов и шлём
  ОДИН non-stream `POST /v1/chat/completions` (`model: "bench-prepare"`,
  `max_tokens: 1`) — чтобы вытеснить точные тексты чанков из контекст-кэша
  движка (кэш матчит подпоследовательности тела; соль в префиксе его не бьёт).
  Ошибка — мягкая (`WARN: cache flush failed`).

### bench-parallel-decode.py
- Аргументы: `--url` (env `URL`, дефолт :8082), `--model` (дефолт — первый ID
  из `/v1/models`; **env для модели НЕТ** — только флаг), `--concurrency` (2),
  `--runs` (3), `--depth` (4000 — филлер), `--max-tokens` (128),
  `--data-dir` (дефолт `<dir>/realdata`), `--chunk-depth` (дефолт = --depth),
  `--solo`, `--chunk-offset` (0), `--timeout` (600), `--verbose`.
- Тело: то же, что у prefill (model, messages, max_tokens, stream,
  stream_options.include_usage, chat_template_kwargs.enable_thinking=false).
  Хард-фейл без usage в стриме; timings опционален.
- Имена чанков (на глубину `D`): parallel run r, поток p → слот
  `offset + r*concurrency + p`: пробует `D-<slot>.txt` (числовой, строит
  make-chunks.py), затем `D-<letter>.txt` (letter = slot%26). Solo run r →
  слот `offset + 200 + r`: пробует `D-<200+r>.txt`, затем `D-d{r+1}.txt`
  (decode-чанки prepare), затем letter. Нет файла → **филлер** (loud WARN,
  «не с остальными не сравним»).
- Warmup: один маленький запрос (4 токена) — в любой контекст.

### make-chunks.py
- Аргументы: `--url` (env `URL`), `--data-dir`, `--depth`, `--ranges`
  (числовые слоты, напр. `0-5,200-202`), `--tol` (0.005); env `FLUSH` (дефолт
  1 — выключает только flush, не саму сборку).
- **То же хардкод `"model": "bench-prepare"`** в `count_tokens` и в
  `flush_cache` (235k-запрос, timeout 1800s).
- Курсоры: за край ВСЕГО, что уже на диске в `chunks/` (по файлам, не только
  по манифесту) + по манифесту → новые чанки не пересекаются ни с prepare, ни
  с прошлыми сборками. Готовые слоты пропущаются.
- Манифест дополняется (не перезаписывается) — в отличие от prepare (prepare
  с FORCE=1 перезаписывает манифест только своими DEPTHS — на prefill/parallel
  не влияет, т.к. они манифест не используют).

## 2. Роутер llama-swap v265: как устроена маршрутизация (код на теге v265)

- Маршруты с моделью в JSON-теле (`internal/server/server.go:132-169`,
  `modelPostJSONRoutes`): `/v1/chat/completions`, `/v1/messages`,
  **`/v1/messages/count_tokens`** и др. Модель читается из **топ-уровневого
  поля `model` тела** (`internal/swaputil/http.go`, `extractContext`,
  `gjson ... "model"`); GET-эндпоинты — из query. Модель отсутствует/пустая →
  404 `no model id could be identified`.
- Диспетч (`localPeerHandler`): `cfg.RealModelName(model)` (alias→ID), затем
  `local.Handles(ID)` (модель в конфиге роутера) / `peer.Handles(ID)`.
  **Неизвестный ID (например `bench-prepare`) → 404 `no router for requested
  model`** (JSON-огибающая `{"src":"llama-swap","error":{"message":…,"type":
  "invalid_request_error","code":"not_found"}}`). Живой факт — раздел 4.3b.
- Переписывание тела (`internal/server/filters.go`), конвейер:
  `useModelName` → `stripParams` → `setParams` → `setParamsByID`. В конфиге
  этого деплоя (router/config.d): `useModelName` НЕ задан ни одной модели
  (NInfer принимает `model: qwen3.8-27b` — `--model-id` совпадает; Strata
  принимает любое значение поля `model` — оригинальные скрипты успешно гоняли
  туда `bench-prepare` напрямую на :8082); `stripParams: repetition_penalty`
  (у всех трёх; скрипты его не шлют); `setParams`/`setParamsByID` не заданы.
  **Итог: `stream_options` и `chat_template_kwargs` проходят к движку без
  изменений**; тело сериализуется заново через sjson (порядок ключей может
  измениться, содержимое — нет), Content-Length/Transfer-Encoding
  пересчитываются.
- Стриминг: обратный прокси 1:1, SSE-чанки (включая финальный с
  `usage`/`timings`) передаются без изменений (живой факт — раздел 4.2).
- `/v1/models` (`internal/server/api.go:306`): список **сортируется по
  алфавиту ID** (`sort.Slice … data[i].ID < data[j].ID`) → порядок
  детерминирован: `qwen3.8-27b, strata-iq2, strata-iq3` (живой факт — 8
  подряд идентичных ответов, раздел 4.1). Первый ID = `qwen3.8-27b`.
- Контекст-лимиты на запросы роутер не проверяет: превышение ctx отвечает
  движок (400) — важно для warmup/flush, раздел 5.

## 3. Токенизаторы: статическое сравнение (диск, без сети)

Файлы:
- Strata (Qwen3.8-Flash-Next): `/opt/strata/packs/{iq3_xxs,iq2_xs}/tokenizer/`
  — `vocab.json` (248 320 токенов), `merges.txt` (247 587),
  `chat_template.jinja`, stub `tokenizer.json` (pre_pattern типа QWEN35).
- NInfer (Qwen3.8-27B): `.ninfer`-артефакт — единый 23 ГБ бинарник
  (токенизатор внутри, извлекать сложно); использован исходный HF-токенизатор
  артефакта `/opt/models/Qwen3.8-27B-NVFP4/tokenizer.json` (HF fast BPE).

Результаты сравнения (python3, точные):
- **Мержи: идентичны** — 247 587 пар, равны и по множеству, и по порядку.
- **Vocab: идентичны для id 0..248 043** (248 044 токенов). Strata
  дописывает 276 спец-токенов в хвост (id 248 044..248 319: `<|endoftext|>`,
  `<|im_start|>`, `<|im_end|>`, vision/tool/FIM-токены). В HF-токенизаторе
  эти же токены есть как `added_tokens` с ТЕМИ ЖЕ id (`<|endoftext|>`=248044,
  `<|im_start|>`=248045, `<|im_end|>`=248046, …) — т.е. это один и тот же
  словарь, а не расхождение.
- Pre-tokenizer: паттерны совпадают по смыслу; отличия: (а) HF пишет
  `(?i:'s|'t|…)` (case-insensitive), llama-swap/Strata расписывает явными
  `'[sS]`-классами — для ASCII эквивалентно; (б) в классовых альтернативах у
  Strata есть `\p{M}` (combining marks), у HF-файла — нет. Для ASCII/
  Gutenberg-текста (наши чанки) — функционально идентично; на текстах с
  combining marks возможны единичные расхождения.
- **Живое подтверждение**: один и тот же текст даёт идентичные
  `count_tokens` у обоих движков через роутер (раздел 4.3a/4.4).

Вывод: чанки, откалиброванные `count_tokens` одного движка, габаритны
идентично у другого. Обходной путь для NInfer не нужен — у него свой
`count_tokens` (раздел 4.3a).

## 4. Живые пробы через http://localhost:8080 (короткие, max_tokens ≤ 16)

Порядок минимизировал свапы: сначала NInfer (резидентен), один свап на
`strata-iq3` в конце. Итоговое состояние: `strata-iq3` резидентна — ок.

### 4.1 GET /v1/models
```
curl -s http://localhost:8080/v1/models
```
Ответ (8 повторных запросов — порядок стабилен):
`["qwen3.8-27b", "strata-iq2", "strata-iq3"]`; `status.value`: loaded/unloaded
по факту резидентности; `meta.n_ctx`: 262144 / 262144 / 131072.
Порядок = алфавитный (код: `api.go:306`), первый ID = `qwen3.8-27b`.

### 4.2 Стрим NInfer (qwen3.8-27b) — контракт финального чанка
`POST /v1/chat/completions`, тело как у скриптов (`stream: true`,
`stream_options: {include_usage: true}`, `chat_template_kwargs:
{enable_thinking: false}`, max_tokens 8, «Reply with the single word DONE.»):
```
HTTP 200; TTFT 0.08s; контент «DONE»; finish_reason=stop
```
Финальный чанк (с пустым `choices`):
```json
{
  "timings": {
    "cache_n": 0, "draft_n": 6, "draft_n_accepted": 1,
    "predicted_ms": 19.913688, "predicted_n": 2,
    "predicted_per_second": 50.22, "predicted_per_token_ms": 19.913688,
    "prompt_ms": 49.645704, "prompt_n": 19,
    "prompt_per_second": 382.71, "prompt_per_token_ms": 2.61
  },
  "usage": {
    "completion_tokens": 2,
    "completion_tokens_details": {"reasoning_tokens": 0},
    "prompt_tokens": 19,
    "prompt_tokens_details": {"cached_tokens": 0},
    "total_tokens": 21
  },
  "model": "qwen3.8-27b", "object": "chat.completion.chunk", "choices": []
}
```
Выводы:
- **`usage.prompt_tokens` ЕСТЬ** → prefill-скрипт не упрётся в «no usage in
  stream». `usage.prompt_tokens_details.cached_tokens` — есть (флаг cache hit
  работает).
- **Блок `timings` ЕСТЬ и того же schema, что у Strata** (`prompt_n/
  prompt_ms`, `predicted_n/predicted_ms`, `draft_n/draft_n_accepted`,
  `cache_n`) → engine tok/s берётся из движка и для NInfer; client-side
  фоллбек не нужен. Это сильнее, чем закладывалось в карте
  («timings — фича Strata»). В таблице помечать: у всех трёх моделей —
  engine-метрики из `timings`.
- `chat_template_kwargs.enable_thinking: false` принят (200; ответ короткий,
  без reasoning — `reasoning_tokens: 0`).

### 4.3 `POST /v1/messages/count_tokens` (через роутер)

a) `model: qwen3.8-27b` (NInfer резидентен — свап не платился):
```
{"model":"qwen3.8-27b","messages":[{"role":"user","content":"Привет, как дела? Короткий текст для подсчёта токенов."}]}
→ HTTP 200 {"input_tokens": 71}
{"…", "content": ""}              → HTTP 200 {"input_tokens": 52}
{"…", "content": "Привет"}        → HTTP 200 {"input_tokens": 55}
{"…", "content": "Read the following text. Reply with the single word DONE. word word … (×500)"}
                                  → HTTP 200 {"input_tokens": 564}
```
**У NInfer эндпоинт count_tokens ЕСТЬ.** Калибровка: база шаблона чата = 52
токена (пустой контент), дельты совпадают с независимым локальным счётом
(HF tokenizer.json, venv /tmp/tokenv + `tokenizers`, truncation выключена):
«Привет»=3, русское предложение=19, англ. 2.5k-знаковое=514≈512 (±2,
пре-токенизация повторений). Т.е. движок считает тем же токенизатором;
систематический сдвиг между `count_tokens` (база 52) и `usage.prompt_tokens`
в стриме (база ~12 на тот же шаблон — см. 4.2: prompt_tokens=19 при
контенте 7) ≈ 40 токенов — константа, покрывается допуском ±0.5%
бинарного поиска prepare.

b) `model: bench-prepare` (как шлют prepare/make-chunks):
```
→ HTTP 404
{"src":"llama-swap","error":{"message":"no router for requested model",
 "type":"invalid_request_error","param":null,"code":"not_found"}}
```
**Подтверждает блокер №1**: без патча prepare/make-chunks через роутер не
сработают (count_tokens — 5 ретраев и хард-фейл; FLUSH — мягкий WARN).

### 4.4 `count_tokens` на strata-iq3 (один свап, 13–21 c)
```
{"model":"strata-iq3","messages":[{"role":"user","content":"Привет, как дела? Короткий текст для подсчёта токенов."}]}
→ HTTP 200 {"input_tokens": 71}   (время curl 16.6 c — включая свап)
{"…", "content": ""}    → HTTP 200 {"input_tokens": 52}
{"…", "content": "Привет"}        → HTTP 200 {"input_tokens": 55}
```
Те же 71/52/55, что у NInfer на тех же текстах → **оба движка считают
идентично** (токенизатор + шаблон). Strata iq3 после этого резидентна
(`/v1/models`: strata-iq3=loaded, остальные unloaded) — допустимое
итоговое состояние.

## 5. Бюджет контекста (счёт реальным токенизатором, truncation=off)

Обёртки промптов (локальный счёт): prefill «[bench salt] Read … DONE.» ≈ 17
токенов; decode/parallel «[bench salt] … CONTINUE … 192 words.» ≈ 50 токенов.
Warmup prefill-скрипта = строка 16 токенов × (`depth//12 + 1`) + префикс:

| модель (ctx)  | depth  | warmup     | prefill промпт | decode промпт | статус |
|---------------|--------|------------|----------------|---------------|--------|
| qwen3.8-27b (262144) | 40k  | 50 015  | ~40 017 | ~40 050 | ок |
| qwen3.8-27b (262144) | 150k | 187 520 | ~150 017| ~150 050| ок |
| qwen3.8-27b (262144) | 200k | 250 010 | ~200 017| ~200 050| ок (запас ~12k) |
| strata-iq2 (262144)  | —    | — (то же, что qwen) | — | — | ок |
| strata-iq3 (131072)  | 40k  | 50 015  | ~40 017 | ~40 050 | ок |
| strata-iq3 (131072)  | 120k | **150 020** | ~120 017 | ~120 050 | **warmup > ctx** |

- Warmup у iq3 на 120k (150 020 > 131 072) → движок 400 → `RuntimeError` из
  `warmup()` не пойман → **скрипт падает на глубине 120k** (последней при
  DEPTHS=40000,120000 — 40k успевает замериться).
- **Патч (рабочая копия клона, 1 строка)**: в `bench-real-prefill.sh`
  `depth // 12 + 1` → `depth // 15 + 1`. Тогда warmup ≈ 1.07×depth:
  120k→128 035 (< 131 072 ✓), 40k→42 700 (больше любого чанка 40k±0.5%+50
  ≈ 40 250 — вытеснение кэша сохраняется ✓), 200k→213 366 (< 262 144 ✓).
  Альтернатива (без патча) — потерять глубину 120k у iq3.
- Parallel decode на chunk-depth 40000: промпт ~40 050 — влезает даже в ctx
  iq3 ✓.
- FLUSH prepare/make-chunks: 235k токенов → > 131 072 (iq3: 400), влезает в
  262 144 (qwen/iq2). Через роутер в любом случае 404 (bench-prepare) →
  FLUSH=0 (см. план).

## 6. Требования к чанкам и их сборка

Протокол карты: prefill (RUNS=3 + decode d1..d3) на глубинах qwen/iq2
40k/150k/200k и iq3 40k/120k; parallel — solo 2 + c2×3 на 40k.

- **Prefill**: prepare по умолчанию даёт ровно нужные 6 чанков на глубину
  (a,b,c + d1..d3) → **make-chunks.py для prefill НЕ нужен**.
- **Parallel decode (40k)**: числовые слоты:
  - strict-протокол (2 вызова, см. план): solo 200,201; parallel-вызов-1
    слоты 0-3; parallel-вызов-2 слоты 100-105 → `make-chunks.py
    --depth 40000 --ranges 0-3,100-105,200-201` (12 чанков, 480k токенов).
  - Без make-chunks parallel сломан: слоты 0-2 откатятся на `40000-a/b/c.txt`
    (текст prefill → риск cache hit), 3-5 — на филлер (несравнимо, WARN).
- Бюджет книг: ~3.3M токенов суммарно; prepare pass A (40/150/200k, 18
  чанков) ≈ 2.34M + make-chunks 0.48M ≈ 2.82M нового текста — влезает с
  запасом ~0.5M. (prepare pass B для 120k перечитывает книги с начала —
  курсор не сохраняется между запусками prepare; новое потребление 0.)
  Остаток книг после pass A ≈ 0.98M ≥ 0.48M ✓.
- Пересечение текстов между pass A и pass B (120k-a ⊃ 40k-a и т.п.):
  безвредно — 120k-чанки бенчатся только у iq3, и per-depth warmup
  (1.07–1.33×depth нерелевантного текста) вытесняет последовательности
  предыдущих чанков из кэша целевого движка перед замером каждой глубины.
- Чанки 40k (a,b,c,d1-3 + числовые) переиспользуются всеми тремя моделями:
  токенизаторы идентичны, движки разные (кэши не пересекаются).

## 7. План запуска (рабочий клон — `/home/dimmy/projects/00 infra/llm-bench`)

### 7.1 Обязательные патчи рабочей копии (минимум, 3 строки)
1. `bench-real-prefill-prepare.sh` и `make-chunks.py`: заменить
   `"model": "bench-prepare"` → `"model": "qwen3.8-27b"` (по 2 места:
   count_tokens + flush). Модель-счётчик = qwen3.8-27b, потому что: (а)
   прелоадится на старте → резидентна, sizing-фаза без единого свапа; (б)
   count_tokens у неё есть и считает идентично (71/52/55); (в) FLUSH 235k
   влезает в её ctx 262144 (на iq3 235k не влезал бы).
   `sed -i 's/"bench-prepare"/"qwen3.8-27b"/' bench-real-prefill-prepare.sh make-chunks.py`
2. `bench-real-prefill.sh`: warmup `depth // 12 + 1` → `depth // 15 + 1`
   (иначе iq3@120k падает на warmup, раздел 5).
   `sed -i 's/depth \/\/ 12 + 1/depth \/\/ 15 + 1/' bench-real-prefill.sh`

### 7.2 Сборка чанков (одним блоком, до всех бенчей; NInfer резидентна → 0 свапов)
```
cd "/home/dimmy/projects/00 infra/llm-bench"
# Pass A: 18 чанков (40k,150k,200k × a,b,c,d1..d3) — qwen, iq2, (40k iq3)
URL=http://localhost:8080 FLUSH=0 DEPTHS=40000,150000,200000 \
  ./bench-real-prefill-prepare.sh
# Pass B: 120k-чанки для iq3 (FORCE — манифест уже есть от pass A)
URL=http://localhost:8080 FLUSH=0 FORCE=1 DEPTHS=120000 \
  ./bench-real-prefill-prepare.sh
# Числовые слоты для parallel decode (40k)
URL=http://localhost:8080 FLUSH=0 ./make-chunks.py --depth 40000 --ranges 0-3,100-105,200-201
```
- `FLUSH=0`: 235k-flush через роутер бесполезен для целевого движка (см.
  7.1(а)) и стоит ~10 мин prefill NInfer на каждый запуск; вытеснение кэша
  делает per-depth warmup prefill-скрипта.
- Проверить после сборки: в `realdata/chunks/` 18 + 6 + 12 = 36 файлов
  (40k: a,b,c,d1-3,0-3,100-105,200-201; 150k/200k: a,b,c,d1-3; 120k:
  a,b,c,d1-3); в логах prepare/make-chunks — «ок»-отклонения ≤5%, WARN-ов
  «остатка не хватает» нет (книги кончились = риск №6).

### 7.3 Прогоны по моделям (URL=http://localhost:8080; строго последовательно)
Порядок моделей свободный; каждый переход = 1 свап (NInfer 6–9 c, Strata
13–21 c), warmup скриптов впитывает холодный старт. Порядок ниже
минимизирует свапы при старте с текущего состояния (iq3 резидентна):

**1) strata-iq3** (текущий резидент — свап не платится):
```
URL=http://localhost:8080 MODEL=strata-iq3 DEPTHS=40000,120000 \
  ./bench-real-prefill.sh          # RUNS=3, MAX_TOKENS=16, DECODE_* — дефолты
URL=http://localhost:8080 --model strata-iq3 --data-dir ./realdata \
  --chunk-depth 40000 --solo --runs 2 --concurrency 2 --chunk-offset 0 \
  ./bench-parallel-decode.py       # solo 200,201; par-2 (слоты 0-3) — бонус
URL=http://localhost:8080 --model strata-iq3 --data-dir ./realdata \
  --chunk-depth 40000 --runs 3 --concurrency 2 --chunk-offset 100 \
  ./bench-parallel-decode.py       # канонический par-3 (слоты 100-105)
```
**2) strata-iq2** (свап iq3→iq2, 13–21 c):
```
URL=http://localhost:8080 MODEL=strata-iq2 DEPTHS=40000,150000,200000 \
  ./bench-real-prefill.sh
URL=http://localhost:8080 --model strata-iq2 --data-dir ./realdata \
  --chunk-depth 40000 --solo --runs 2 --concurrency 2 --chunk-offset 0 \
  ./bench-parallel-decode.py
URL=http://localhost:8080 --model strata-iq2 --data-dir ./realdata \
  --chunk-depth 40000 --runs 3 --concurrency 2 --chunk-offset 100 \
  ./bench-parallel-decode.py
```
**3) qwen3.8-27b** (свап в NInfer, 6–9 c):
```
URL=http://localhost:8080 MODEL=qwen3.8-27b DEPTHS=40000,150000,200000 \
  ./bench-real-prefill.sh
# parallel — те же два вызова, что выше, но --model qwen3.8-27b
```
Примечания:
- `MODEL=` (prefill) и `--model` (parallel) — ОБЯЗАТЕЛЬНО: без них оба
  скрипта возьмут первый ID из `/v1/models` = `qwen3.8-27b`.
- `DECODE_RUNS=3`/`DECODE_TOKENS=128`/`RUNS=3` — дефолты скриптов (протокол
  карты). `CLIENT=0` по дефолту: engine-метрики (у всех трёх моделей timings
  есть, раздел 4.2); при желании `CLIENT=1` — дублировать client-скорости.
- Parallel: par-2 (слоты 0-3) из первого вызова — дополнительный прогон
  теплоты; в таблицу брать par-3 (слоты 100-105). Solo 2 runs — протокол.
- Сырые stdout каждого прогона → `.scratch/llm-bench-results/assets/run-<model>/`
  (решение карты).
- Красные линии прогонов (карта): ≥512 MiB свободной VRAM на дисплейной
  GPU1, без постоянного свопа.

## 8. Риски и ограничения

1. **Патчи клона обязательны** (7.1): без них prepare/make-chunks не
   работают через роутер (404 bench-prepare), iq3@120k падает на warmup.
   Патчи — в рабочем клоне `/home/dimmy/projects/00 infra/llm-bench` (вне git
   llm-server); peek-клон /tmp/llm-bench-peek не трогать.
2. **FLUSH не работает через роутер** (404; после патча — 400 на iq3).
   Митигция: FLUSH=0 + per-depth warmup. Риск: если warmup вдруг не
   вытеснит (изменение кэша движка), первый замер глубины может показать
   `cached>0` — скрипт пометит `⚠ CACHE`/CONTAMINATED, прогон глубины
   повторяем.
3. **Первый замер каждой глубины** может показать малый `cached_tokens`
   (~10–50): страта-кэш матчит подпоследовательности ТЕЛА, а обёртка
   «Read the following text…» общая у всех запросов (соль её не бьёт, она
   внутри тела). Это не заражение (чанк холоден), но `⚠`-флаг в логах
   появится; в таблицу — пометка.
4. **NInfer: `count_tokens` ≠ `usage.prompt_tokens` по шаблону** (сдвиг ~40
   токенов: база 52 против ~12). Систематичен, поглощается допуском ±0.5%;
   фактическая глубина замеров будет на ~40 токенов МЕНЬШЕ таргета (т.е.
   консервативно).
5. **Токенизаторы идентичны для ASCII-текстов**, но pre-tokenizer Strata
   шире (`\p{M}`). Чанки — ASCII/Gutenberg → расхождений нет; если в будущие
   замеры пойдут тексты с combining marks — пересмотреть.
6. **Книги (корпус ~3.3M токенов) — узкое место**: план потребляет ~2.82M
   нового текста. Остаток после pass A ≈ 0.98M ≥ 0.48M make-chunks, но
   запас небольшой; make-chunks при нехватке слота падает с явной ошибкой
   («книги кончились») — тогда добавить текст в `realdata/src/` и
   перезапустить make-chunks (готовые слоты пропустятся).
7. **Замены/смерти движка во время прогона** (красные линии VRAM) — не
   проверялись; при 4xx/5xx в замере скрипт пишет FAIL-строку и идёт
   дальше (RUNS=3 частично страхует).
8. Не проверялось (вне скоупа «короткие пробы»): поведение движков на
   полных глубинах (150k/200k/120k), стрим Strata через роутер (контракт
   `usage`/`timings` у Strata известен из контекста проекта; проба iq3
   `count_tokens` дала 200 через роутер, что доказывает проксирование),
   max-конкурренции (потолок NInfer = 2 совпадает с `--concurrency 2`).
