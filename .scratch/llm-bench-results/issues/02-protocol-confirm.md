# Протокол: подтверждение замеров по итогам тикета 01

Status: resolved
Type: grilling
Blocked by: 01

## Question

По ответу тикета «Совместимость llm-bench с роутером :8080» подтвердить с
пользователем финальный протокол замеров **до** начала прогонов:

- глубины и число прогонов по моделям (база: `qwen3.8-27b`/`strata-iq2` —
  40k/150k/200k, `strata-iq3` — 40k/120k; 3 прогона/глубина + decode-пробник);
- если у NInfer не оказалось `usage`/`timings` — как мерить `qwen3.8-27b`
  (патч скрипта vs client-side протокол vs исключить метрику из таблицы);
- parallel-decode: `--concurrency 2` + solo-база, числа runs;
- всё, что выяснилось в тикете 01 и влияет на сопоставимость чисел между
  моделями.

Результат: финальный протокол, зафиксированный в ответе тикета.

## Answer

Финальный протокол (подтверждён пользователем 2026-11-17; детали и точные
команды — `assets/research-01-router-compat.md` §7):

1. **Патчи рабочей копии клона** (применить сразу после клона, до prepare;
   подтверждены пользователем с просмотром):
   `sed -i 's/"bench-prepare"/"qwen3.8-27b"/' bench-real-prefill-prepare.sh make-chunks.py`
   + `sed -i 's/depth \/\/ 12 + 1/depth \/\/ 15 + 1/' bench-real-prefill.sh`.
   FLUSH-шаг отключён (`FLUSH=0`).
2. **Сборка чанков** одним блоком до всех прогонов:
   `prepare DEPTHS=40000,150000,200000` → `prepare FORCE=1 DEPTHS=120000` →
   `make-chunks --depth 40000 --ranges 0-3,100-105,200-201`; всё
   `URL=http://localhost:8080 FLUSH=0`.
3. **Прогоны по моделям** (строго последовательно; `MODEL`/`--model` всегда
   явно): prefill — `bench-real-prefill.sh URL=http://localhost:8080 MODEL=<id>
   DEPTHS=…` (qwen3.8-27b/strata-iq2: 40000,150000,200000; strata-iq3:
   40000,120000; RUNS=3 + decode-пробник); parallel — канон:
   `--url http://localhost:8080 --model <id> --data-dir ./realdata
   --chunk-depth 40000 --solo --runs 2 --chunk-offset 0` +
   `--concurrency 2 --runs 3 --chunk-offset 100`.
4. **Порядок моделей**: старт с текущего резидента (на 2026-11-17:
   strata-iq3 → strata-iq2 → qwen3.8-27b); если на момент старта прогонов
   резидент другой — начинать с него.
5. **Контроль в ходе прогонов**: красная линия VRAM (GPU1 ≥ 512 MiB, минимум
   снять), кэш-контаминация = 0 (малый `cached_tokens` ~10–50 на первом замере
   глубины — норма, пометить в таблице), без постоянного свопа.
