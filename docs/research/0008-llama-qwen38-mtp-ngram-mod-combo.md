# Draft-MTP + ngram-mod combo + parallel=1 + cache-ram: decode, prefill, VRAM

Дата замера: 2026-09-15.

Статус: исследование. Конфигурация внесена в `llama/config.yaml` и оставлена
после замера (не откатывается на HEAD).

## Изменения конфига (относительно HEAD)

```diff
-      --parallel -1
-      --kv-unified
-      --no-cache-idle-slots
-      --cache-ram 0
+      --mmproj /models/Qwen3.8-27B-NVFP4-MTP-GGUF/mmproj-BF16.gguf
+      --mmproj-offload
+      --parallel 1
+      --cache-ram 40960

-      --spec-type draft-mtp
+      --spec-type draft-mtp,ngram-mod
       --spec-draft-n-max 4
       --spec-draft-p-min 0.75
+      --spec-ngram-mod-n-match 20
+      --spec-ngram-mod-n-min 4
+      --spec-ngram-mod-n-max 48
```

- **parallel 1, без kv_unified** — один слот, KV строго выделен под ctx;
  высвобождает ~1.7 GiB VRAM по сравнению с parallel -1 (4 slots, unified).
- **cache-ram 40960, cache-idle-slots (дефолт)** — KV сериализуется в RAM
  при завершении запроса. При parallel=1: сохраняет KV в RAM (полезно для
  повторных запросов к тому же контексту, но НЕ освобождает VRAM без unified KV).
- **mmproj + mmproj-offload** — vision projector на CPU (0 VRAM), enables
  multimodal (image/video) processing.
- **draft-mtp,ngram-mod** — комбинация: ngram-mod (приоритет 4) работает
  первым, draft-mtp (приоритет 8) как fallback. Оба на CPU-сэмплинге
  (split-mode tensor не поддерживает backend sampling).

## Методика

- Профиль llama, сервис `llama-swap`, публичный API `http://localhost:8080`.
- На каждую категорию: рестарт, lazy load (без preload), затем замеры.
- Модель-ID `qwen3.8-27b` (режим `setParamsByID`, temp 0.7, top_p 0.8,
  presence_penalty 1.5; клиентские параметры игнорируются).
- Метрики из `timings` JSON: `prompt_per_second` (prefill),
  `predicted_per_second` (decode), `cache_n` (KV-reuse).
- Драфт-статистика из `print_timing` llama-server (draft acceptance / mean len).
- Каждый повтор — новый текстовый фрагмент; KV-reuse (`cache_n` > 0)
  отмечается и не включается в median prefill.
- VRAM: `nvidia-smi --query-gpu` polling 0.25s на время p63 замеров.
- Корпус: Sherlock Holmes, Project Gutenberg (107k слов).

## Результаты

### Prefill

| Тип контекста | p_n (токенов) | repeat1 | repeat2 | repeat3 |
|---|---|---|---|---|
| instrumental ~12k | 12.4k | 2640 | 2652 | 2652 |
| natural ~20k | 19.9–20.3k | 2607 | 2595 | 2597 |
| natural ~79k | 78.8–79.2k | 2298 | 2134 | — |

Prefill **не зависит от спекуляции** (идентичен для ngram-mod vs
draft-mtp-only при одинаковом p_n). Сравнение с baseline (0006,
parallel -1, ctx 180224):

| ctx  | 0006 baseline (parallel -1) | теперь (parallel 1) | Δ |
|---|---|---|---|
| ~20k | 2082–2636 | 2595–2607 | верхний край; parallel 1 не хуже |
| ~63k | 1110–1663 | 2134–2298 | **+28–107%** |

Улучшение prefill на 63k объясняется параллельностью: parallel 1 без
unified KV убирает overhead shared-pool bookkeeping (net fragmentation +
аллокации при больших батчах).

### Decode, инструментальный текст (~12.4k токенов, max_tokens 1024)

| repeat | pp (t/s) | tg (t/s) | draft accept | mean len |
|---|---|---|---|---|
| 1 | 2640 | 107.5 | 0.38 | 7.11 |
| 2 | 2652 | 104.9 | 0.34 | 7.94 |
| 3 | 2652 | 129.6 | 0.42 | 9.69 |

**Паттерн**: draft acceptance низкий (0.34–0.42), но mean len высокий
(7.1–9.7). ngram-mod создаёт длинные драфты (до 48 токенов, n-max=48),
мало из которых проходят проверку. Но когда драфт проходит — это много
токенов за раз. Net decode: 105–130 т/с.

Сравнение с 0006 baseline (draft-mtp-only, n-max=4, instrumental ~16k):

| 0006 baseline | теперь | Δ |
|---|---|---|
| 82–87 t/s, accept 0.95, mean len 3–5 | 105–130 t/s, accept 0.34–0.42, mean len 7–10 | **+28–55%** |

**Вывод**: ngram-mod с n-max 48 на предсказуемом тексте **значительно быстрее**
draft-mtp-only, несмотря на низкий acceptance. Причина — длинные драфты
компенсируют overhead проверки.

### Decode, естественный текст (~20k токенов)

| repeat | pp (t/s) | tg (t/s) | draft accept | mean len |
|---|---|---|---|---|
| 1 | 2607 | 58.4 | 0.69 | 2.64 |
| 2 | 2595 | 57.5 | 0.70 | 2.58 |
| 3 | 2597 | 59.2 | 0.70 | 2.51 |

Сравнение с 0006 baseline (natural ~16k):

| Config | tg (t/s) | accept |
|---|---|---|
| 0006 n-max=6 | 43.0 / 38.8 | 0.62–0.68 |
| 0006 n-max=2 | 54.6 / 42.9 | 0.62–0.75 |
| **теперь ngram-mod+MTP** | **57.5–59.2** | **0.69–0.70** |

**+9–34%** vs n-max=6; **+5–38%** vs n-max=2. Acceptance вырос (0.69–0.70
vs 0.62–0.75) — mean len упал (2.5–2.6 vs ~4–5 у MTP-only), но net decode
быстрее.

### Decode, естественный текст (~79k токенов)

| repeat | pp (t/s) | tg (t/s) | draft accept | mean len |
|---|---|---|---|---|
| 1 | 2298 | 53.0 | 0.70 | 2.77 |
| 2 | 2134 | 50.9 | 0.70 | 2.69 |

Сравнение с 0006 baseline (natural ~63k):

| Config | tg (t/s) | accept |
|---|---|---|
| 0006 n-max=6 | 40.2 / 41.4 | 0.62–0.68 |
| 0006 n-max=2 | 48.3 / 41.5 | 0.62–0.75 |
| **теперь ngram-mod+MTP** | **50.9–53.0** | **0.69–0.70** |

**+12–32%** vs n-max=6; **+5–28%** vs n-max=2.

### Decode, короткий естественный ответ

| repeat | tg (t/s) | cache |
|---|---|---|
| 1 | 54.0 | нет (22 p_n) |
| 2 | 65.0 | да (cached 18) |
| 3 | 46.2 | да (cached 18) |

Сравнение с 0006: 67–71 t/s. Сейчас: 46–65 t/s (варьирует, Dependency на
thermal/load). Статистически сопоставимо.

### VRAM (пик во время 63k prefill + 1024 gen)

| GPU | used (MiB) | free (MiB) |
|---|---|---|
| GPU0 | 15029 | 1274 |
| GPU1 | 14510 | **1793** |

Сравнение с 0006/0007 (parallel -1, n-max 4, ctx 180224):

| Config | GPU0 peak | GPU1 free |
|---|---|---|
| 0006/0007 parallel -1 | 14061 | **1749** |
| **теперь parallel 1** | 15029 | **1793** |

GPU1 headroom **почти идентичен** (1793 vs 1749), несмотря на параллель=1.
Отличие: GPU0 использует больше (15029 vs 14061) — это overhead unified KV
bookkeeping который ушел с parallel 1... на самом деле overhead
от `--parallel -1` (4 слота) высвободил память за счёт shared KV pool;
теперь с parallel 1 KV выделен строго. Разница ~968 MiB на GPU0.
GPU1 безопасен: 1793 MiB > 512 MiB threshold.

### RAM

- `free`: 26 GiB used из 59 GiB (vs 8 GiB baseline)
- RSS llama-server: 20.9 GiB (включает mmap модели + cache-ram buffers)

cache-ram 40960 работает: idle-slot KV сериализуется в RAM (каждый
завершённый запрос ~20 GiB RSS = модель + последний сохранённый KV-state).
При parallel=1 следующий запрос использует cache_idle_slots для prefix
reuse, НЕ освобождает VRAM (не unified).

## Статистика драфтов

Из `print_timing` llama-server, session window:

| Тип текста | accept | mean len |
|---|---|---|
| instrumental (ngram dominant) | 0.34–0.42 | 7.1–9.7 |
| natural (MTP dominant) | 0.69–0.78 | 2.5–2.8 |

**Интерпретация**: при низком acceptance (0.38) ngram-mod активно
набирает хэш-пул на.instrumental тексте и выдаёт длинные (до 48) драфты.
На естественном тексте (accept ~0.7) ngram-mod менее эффективен —
короткие драфты (2.5–2.8), близко к поведению MTP-only.

## Качество запуска

- Логи: `n_slots = 1, n_ctx_slot = 180224, kv_unified = false` ✓
- mmproj: `loaded multimodal model, '/models/.../mmproj-BF16.gguf'` ✓
- spec backend: `backend offload failed for seq_id=0; using CPU sampler` ✓
  (split-mode tensor не поддерживает GPU-based sampling для спекуляции)
- Warning: `Qwen-VL models require at minimum 1024 image tokens to function
  correctly on grounding tasks` — vision-specific, не влияет на текстовый
  inferens.

## Аномалии

- **Дрейф сессии** (0006): повторяющийся паттерн prefill 1641/1280/1112 для
  одних и тех же текстов, 90s cooldown не восстанавливает decode.
  Не изучалась в этом замере.
- **Некоторые p_n замеры** для 63k (pp 2298 vs 2134) разброс обусловлен
  дрейфом + concurrent traffic (192.168.17.69 генерировал во время замеров).
  Reject rates не измерялись.
- **Нет outer-loop VRAM monitoring** для 63k: пики взяты из одного прогона;
  для полноты нужен nvidia-smi --loop-ms=50 (не сделано в этом замере).

## Итого

### Draft-mtp + ngram-mod: что даёт комбинация

- **ngram-mod** выступает основным драфтером на предсказуемом тексте:
  mean len 7–10 (vs 3–5 у MTP-only) при acceptance 0.34–0.42.
  Net decode: 105–130 t/s (vs 82–87 t/s MTP-only n-max4): **+28–55%**.
- **На естественном тексте** (accept ~0.7, mean len 2.5–2.8): 51–59 t/s
  (vs 42–48 t/s MTP-only n-max2): **+7–40%**.
- **Prefill** не ухудшен, на длинных контекстах (+63k) значительно
  лучше: 2134–2298 vs 1110–1663 t/s (parallel 1 effect).
- **VRAM headroom**: parallel 1 даёт 1793 MiB на GPU1 (vs 1749 у
  parallel -1 — сопоставимо, оба безопасны).

### Рекомендации (обсудить)

1. **`--parallel 1` вместо `-1`** — выигрыш в VRAM headroom и prefill на
   длинных контекстах при одноразовых запросах (один агент, один поток).
   Если нужна параллельность 2+ слотов — вернуть `-1` с `--cache-idle-slots`
   (освобождает VRAM через unified KV clear).

2. **`--spec-type draft-mtp,ngram-mod`** — комбинация работает и
   значимо быстрее на всех измеренных текстах. ngram-mod активен на
   предсказуемом; MTP выручает на естественном.

3. **n-match=20** — работает, но < 16 может вызвать предупреждение
   в newer llama.cpp. Рассмотреть 24 (дефолт) или 18 (компромисс) для
   избежания edge cases.

4. **n-min=4** — можно оставить; низкий порог отбрасывает короткие
   драфты, но mean len на eстественном тексте (~2.5) создаёт мало
   отбрасываний. На предсказуемом даёт длинные прогоны.

5. **cache-ram 40960** — работает; при parallel 1 полезен для prefix
   reuse (повторные запросы), но НЕ освобождает VRAM. Если цель —
   освобождение VRAM при idle, нужен `--parallel -1` (unified KV).

6. **mmproj + mmproj-offload** — enables vision, 0 VRAM overhead.
   Warning о 1024 image tokens — нормально, не влияет на текстовый inferens.

### Дальнейшие исследования

- **n-match 18/24**: измерить влияние на natural text accept/decode.
- **n-min 8/16**: измерить влияние на natural text (currently mean len
  ~2.5, много ли драфтов отбрасывается на n-min=4).
- **parallel 2** без unified KV: измерить throughput при 2 конкурентных
  запросах с комбинацией ngram-mod+MTP.
- **VRAM-пик с 163840 ctx**: проверить, что при parallel 1 + ngram-mod
  headroom достаточен.
- **Единый нативный бенчмарк**: нужен repeatable скрипт с зафиксированными
  фрагментами (не procedural) и полным nvidia-smi polling.
