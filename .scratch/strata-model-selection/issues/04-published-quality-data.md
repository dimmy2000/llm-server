# Опубликованные данные качества и скорости

Status: resolved
Type: research

## Question

Собрать качество- и скорость-референсы для размеров **IQ3_XXS, IQ3_S, IQ2_XS** (контекст —
Coder/Swift для полноты таблицы), чтобы в отчете решать на опубликованных данных + субъективных
агент-сессиях:

- Официальные таблицы Strata (DETAILS.md, QUANTS.md): скорость per size на RTX 5070/5070 Ti/3090,
  prefill, 128K-контекст, оценки качества (top-token match с Q8_0, бенчмарки авторов).
- Community benchmarks (COMMUNITY_BENCHMARKS.md): ближайшие к нашему железу (Blackwell 2×16/24 GB,
  64 GB RAM) замеры, особенно IQ3_XXS/IQ3_S на 64 GB RAM — есть ли факты OOM/swap/деградации.
- Качество размера: чем жертвуем IQ2_XS vs IQ3_XXS vs IQ3_S по опубликованным тестам; чего
  IQ3_S стоит по RAM (54.8 GB требование vs наши 59 GiB) — официальные предупреждения.
- Проблемные области модели (known weaknesses): неанглийские языки, агрессивный thinking и пр.

Доставить: сводная таблица для отчета + ссылки на источники + выделенные риски по RAM.

## Answer

Источники: `docs/DETAILS.md`, `docs/QUANTS.md`, `docs/MODELS.md`, `docs/HOW_IT_WORKS.md`, `docs/COMMUNITY_BENCHMARKS.md`
(ветка `main` репо [Niko1221/Strata](https://github.com/Niko1221/Strata)) + GitHub-issues. Все данные на дату fetch 2026-10-18.

### 1. Скорость per size — официальные таблицы

DETAILS.md § "Speed (measured)": RTX 5070 **12 GB**, Ryzen 5 7600, 64 GB DDR5-5200, Windows, engine 0.1.26,
`--prefill auto`, int8 KV > 4K, KV streaming с 64K, MTP on, thinking off, 256 токенов out. СвежееIQ2_XS
измерено на Swift 1.5 (та же скорость).

Prefill tok/s (1K / 4K / 32K / 64K / 128K / 262K):

| Size | 1K | 4K | 32K | 64K | 128K | 262K |
|---|---:|---:|---:|---:|---:|---:|
| IQ2_XS | 534 | 1 256 | 2 092 | 1 754 | 1 752 | 1 181* |
| IQ3_XXS | 482 | 1 007 | 1 745 | 1 609 | 1 602 | — |
| IQ3_S | 427 | 913 | 1 624 | 1 640 | 1 443 | — |

Output tok/s (та же сетка):

| Size | 1K | 4K | 32K | 64K | 128K | 262K |
|---|---:|---:|---:|---:|---:|---:|
| IQ2_XS | 79.6 | 78.6 | 76.3 | 63.7 | 62.7 | 52.8 |
| IQ3_XXS | 61.9 | 61.6 | 58.5 | 57.2 | 49.0 | — |
| IQ3_S | 52.4 | 53.3 | 48.3 | 46.3 | 45.5 | — |

MODELS.md цитирует ту же машину округлённо: IQ2_XS 79/63, IQ3_XXS 62/49, IQ3_S 53/46 tok/s (short/128K),
prefill 2 090/1 750/1 620 tok/s. Decode у GDN-внимания почти плоский по контексту (O(1) per token) — деградация
к 128K мягкая; 262K для IQ3-сайзов авторами на 64 GB не измерялся (см. RAM-механику).

Движок 0.1.36 (DETAILS.md): RTX 50 decode-кернелы — Q2_0 4K 89→93.5, 128K 64.5→76.4 tok/s;
`STRATA_PF_FUSED=1` — IQ2_XS prefill +12 % @4K / +3 % @32K, IQ3-паки ≈ равно. Т.е. цифры выше (0.1.26) — заниженная база.

### 2. Community-замеры, ближайшие к нашему железу (Blackwell 16 GB-класс + 64 GB RAM)

Наш риг: 2× RTX 5070 Ti 16 GB (32 GB VRAM) + 59 GiB RAM. Скорость в основном от VRAM-доля экспертов
(~700 экспертов/GB, HOW_IT_WORKS; 48 MoE-слоёв × 512 экспертов = 24 576):

- **RTX 5070 Ti 16 GB + i5-13600KF + 64 GB (63.8 GiB) RAM, IQ3_S @ 262K ctx, 0.1.43.1** (#2772):
  decode 38.1 tok/s (short chat) / 42.2 (agent-ходы), TTFT 0.95 / 3.94 c; prefill 932 tok/s @4K,
  1 200 tok/s @16K; agent-cache hit 68.5 %. Ближайший аналог нашему ригу по GPU и RAM.
- **RX 9070 16 GB + 5800X3D + 64 GB, IQ3_XXS @ 131K** (COMMUNITY_BENCHMARKS.md): decode 58.7/57.9/57.9
  (4K/32K/128K), prefill 586/804/833 tok/s, needle 6/6. Обрати внимание: IQ3_XXS на сопоставимой карте
  заметно быстрее IQ3_S (#2333: +19 % decode, +9.5 % prefill on 12 GB 3060, 64 GB RAM, 0.1.44).
- **RX 9060 XT 16 GB + 9800X3D + 64 GB**: IQ2_XS vs IQ3_XXS, matched 32K coding 9/9 обе, IQ2_XS ~17 % быстрее decode.
- **RTX 5090 32 GB + 285K + 64 GB Linux (62.19 GiB), IQ2_XS @ 131K, 0.1.29** (bench/results/2026-09-30):
  decode 179.4/175.7/165.0 (4K/32K/128K), prefill 4 270/5 543/5 779 tok/s; пик host RAM 45.5 GiB,
  GPU 31.0 GiB, swap 425 MB, OOM нет; needle 6/6. Показывает потолок при ~2× наша VRAM.
- **RTX 4080 16 GB + 12900KF + 128 GB, IQ3_S @ 262K, 0.1.43** (#2117): decode 66.0/70.3 tok/s,
  prefill 1 436 (4K) / 1 996 (16K) / 2 012 (32K) tok/s; 150–225K префиллы 1 600–1 620 tok/s.
  RAM 128 GB — не наш кейс по памяти, но по скорости карта ближе всех к 5070 Ti.
- **RTX 5060 Ti 16 GB, Windows, IQ3_S** (#1200): стедi-state 36–42 tok/s; `spec-min-p` локально 0.7 лучше
  0.5 (gain на Chinese); Windows **large pages** — если отклонены → 3–5× просадка decode; PLE FP8-таблица — бесплатный апгрейд точности.
- Официальная база для минимума: RTX 3060 12 GB, IQ3_XXS 26 / IQ3_S 19–20 tok/s decode (DETAILS.md; 0.1.41-сообщение — 20–27).

Вывод по скорости: на 16 GB Blackwell IQ3_S → ~38–42 tok/s decode (0.1.43.1), IQ3_XXS → ~55–60,
IQ2_XS → ~75–80 (масштабируя по CPU-части; на двух 5070 Ti — плюс больше экспертов в VRAM, как на #2408-конфигах/48 GB).

### 3. RAM-механика per size и предупреждения для наших 59 GiB

MODELS.md «The sizes» (RAM+VRAM requirement / экспертов в shard 1):

| Size | RAM+VRAM req | Эксперты | Скорость | Качество (авторы) |
|---|---:|---:|---|---|
| Q2_0 | 37.6 GB | 34 GB | fastest | good |
| IQ2_XS | 39.2 GB | 35.5 GB | fast | better (recommended) |
| IQ3_XXS | 47.0 GB | 43 GB | slower | great |
| IQ3_S | 54.8 GB | 50 GB | slowest | best: matches the full model on the published tests |

Правило: RAM ≥ эксперты + ~10 GB на систему. Mode «Will it fit»: 64 GB — все сайты («IQ3_S с мало
открытым лишним»), 48 GB — только Q2_0/IQ2_XS. PR #2557: **setup с 0.1.44 рекомендует IQ3_S для 64 GB** (docs ещё не обновлены).
Low-RAM mode (DETAILS.md): при дефиците RAM эксперты мапятся с SSD/`experts.bin` (`--mmap-experts`) или
resident-вариант (`--resident-experts`, `--resident-budget-gib N`); в low-RAM KV остаётся в VRAM и контекст
**не съедает RAM**. KV streaming: +13.7 KB RAM на токен контекста → +1.7 GB @128K (int8; k8v4 на 23 % меньше).

Яркие точки для 59 GiB:
- IQ3_S (54.8) впритык: наши 59 GiB с VM/system → свободно меньше, чем в 64 GB-репортах; авторы прямо
  пишут «IQ3_S с мало открытым лишним», 262K ctx setup отрунет до 128K «по оценке» — но на живом железе
  это перестраховка: **#406** (64 GB Linux, IQ3_S, Ubuntu) — setup сбросил 256K→128K, юзер вручную вернул и
  запустил 256K «с нулём проблем», >6 GB свободной RAM при полном контексте.
- Фактические рессиденты (0.1.44, RTX 3060 12 GB + 64 GB) — #2333: процесс Strata IQ3_S = 48.3 GiB
  (система свободна 4.7 GiB), IQ3_XXS = 42.5 GiB (свободно 10.7 GiB). Т.е. IQ3_XXS почти {};
  IQ3_S при наших 59 GiB (просчитано минус 4 GiB от 64) будет близко к той же точке безворнинг-зоны.
- Механические деградации под RAM-пресур, не подетектуемые как «OOM»: #2923 (IQ3_S, 79.9 GB, RTX 3090,
  сессия 320–390K) — 4 раза под RAM-пресур движок пропускал восстановление parked-снапшота → **полный
  re-prefill 310–372K токенов (233–285 c)** вместо секунд; снапшот 380K-сессии весит 6.4–7.7 GB каждая.
  #2934: glibc heap висит freed-памятью → в длинных сессиях parking эвиктирует все диалоги.
- 2-GPU специфика для нас: **#2408** — CUDA OOM при восстановлении long-снапшота на 2-GPU layer split
  (restore-путь не гейтится free-VRAM на каждый девайс; 0.1.40). Если берем Strata на двойной сплит,
  держим `--vram-reserve-mib` щедрым и `--conversation-cache-mib` маленьким.
- Против OOM под нагрузкой: 3060-отчет (0.1.41) показал, что и IQ3_S resident runs на 12 GB-карте идут
  при min available RAM 25.95–28.12 GiB и system commit ≤ 76 % на 64 GB Windows — «выживают», IQ2_XS при 260K
  там упирался в harness guard (83–89 %), не в движок.

### 4. Качество per size на публике

QUANTS.md «yardstick» (течcher-forced, top-1 agreement с Q8_0 на фиксированном наборе, 4 995 позиций, HIP/EPYC):

| Quant | Same top token as Q8_0 | mean KL | KL p99 | PPL (Q8_0 = 4.052) |
|---|---:|---:|---:|---:|
| IQ3_S | 87.69 % | 0.144 | 1.975 | 4.097 |
| IQ3_XXS | 84.46 % | 0.202 | 2.433 | 4.119 |
| Q2_0 | 80.60 % | 0.315 | 3.643 | 4.475 |
| (ref: UD-IQ4_XS 88.9 %, UD-Q4_K_XL 93.1 %) | | | | |

**IQ2_XS в авторской таблице QUANTS.md отсутствует** — топ-1 связь публикуется только для Q2_0 (2.0 BPW),
IQ3_XXS, IQ3_S. Официальная лестница качества (MODELS.md): Q2_0 good → IQ2_XS «better» →
IQ3_XXS «great» → IQ3_S «best: matches the full model on the published tests». Репортируя
«где IQ2_XS теряет», неуемно: только качественная анкета авторов + косвенные факты, чтобы не
завышать. Swift 1.5 авторы рекомендуют IQ2_XS (their own line), и шестой размер (Coder, IQ1_M) —
наоборот, «лучше всех на коде, слабее всего на non-English» (#438: CJK 0/10 против 10/10 en).

Внешние quality-факты: HumanEval 0–39 (EvalPlus base+plus, 3060-отчет 0.1.41): Q2_0 37/40, IQ2_XS 35/40,
IQ3_XXS 37/40, IQ3_S 34/40 — маленький н-субсет (40 задач, IQ3-ранию at 131K ctx vs 8K), направление
нежесткое: на «просадке IQ3_S» форсить выводы нельзя. Japanese 12 маленьких задач: IQ2_XS/IQ3_XXS/IQ3_S по 11/12,
Q2_0 8/12. Community coding 9/9 и matched-задачи — level между IQ2_XS и IQ3_XXS (9060 XT-report).
Решение «качество vs цена»: IQ3_S = +3.2 pp top-token и −0.022 PPL против IQ3_XXS за −25–30 % decode
на нашем 16 GB-классе; IQ2_XS — лучшая speed-форка (−20–40 % RAM, ~+35–50 % decode), но без
публикуемой точности Q8_0-сравнения.

### 5. Known weaknesses модели (сообщество)

- **CJK-коллапс на длинных ответах** (#1827, closed, IQ3_S unpruned): после ~400–1400 токенов китайский
  ответ впадает в детерминированный токен-цикл (`颊 cheek face …`), greedy 5/5 byte-identical, English
  чистый до 1 885 токенов; похожесть: #438 (Coder IQ1_M CJK 0/10). Не зависит от reasoning-loop
  (`reasoning_effort none` ухудшает), penalty-политики не помогают, `finish_reason: stop` — клиент не
  видит поврежденность. Не memory-баг (эксперты в RAM 0 байт, full reviewer) — квант-артефакт модели.
- **Кириллица и драфт-ворд-букет**: с 0.1.27 дефолтный MTP `draft_vocab.bin` содержит все CJK-токены;
  кириллицы в поставляемых subset'ах только 142 из 18 580 — русский/украинский медленный без
  `--draft-vocab cyrillic` (на RTX 5090-форке 83→109 tok/s; ан-английские языки 15–38 % ускорение от полного subset).
  **#137** (closed): старый draft vocab без CJK давал MTP acceptance collapse на китайском.
- **Агрессивный thinking**: базовая модель думает больше, чем нужно (Swift 1.5 fine-tune режет 63 %
  thinking-токенов при <1 % loss — аргумент.AUTH). Серверные боковины: #2141 — `thinking_budget_tokens`
  игнорируется (клиентов llama.cpp-style → unbounded thinking); #1814/#1053/#1178/#804 — если ответ
  обрывается внутри `<think>` (нет `</think>`), ход один токен/пусkt с `finish_reason: stop`, без tool_calls → агент молча останавливается.
  Для нами-планируемого usage — важно: thinking long-outputь может обрезаться при `max_tokens` ниже 12–16K (аналог NInfer-ticket 13).
- **Деградация на длинных сессиях и RAM-пресуре**: #1944 (**RTX 5070 Ti, 7950X3D, 64 GB RAM**): story-генератор
  после ~12K контекста выдает single-token ответы на каждом следующем ходу (0.1.42 regression, 0.1.39 не воспроизводит);
  #2923 (см. RAM) полный re-prefill 300K+ при RAM-пресуре; #2316 повторные запросы с крупным префиксом падают в
  checkpoint-replay 7–21 tok/s (лечится `--prompt-cache 0`); #2934 heap-залипание в long sessions.
- **Version-specific квант-регрессии**: #2457: 0.1.44 on HIP (RX 6950 XT) IQ3_S выдает мусор при рабочем Q2_0,
  0.1.43.1 рабочий → при апгрейде движка обязательно дегхигieni-check IQ3_S/IQ3_XXS.

### 6. Сводная таблица (для отчета)

| Size | RAM+VRAM req (GB) | Эксперты (GB) | Top-token vs Q8_0 | PPL Δ от Q8_0 | Decode short/128K (авторы) | Decode на 16 GB Blackwell-классе + 64 GB (community) | Основной компромисс |
|---|---:|---:|---:|---:|---|---|---|
| IQ2_XS | 39.2 | 35.5 | не публикуется (оценочно между Q2_0 и IQ3_XXS) | — | 79 / 63 tok/s | ~75–80 tok/s | −20 % RAM, +35–50 % decode, качествоauthors-ranked ниже |
| IQ3_XXS | 47.0 | 43 | 84.46 % | +0.067 | 62 / 49 tok/s | ~55–60 tok/s (RX 9070: 57.9) | рост decode лимитируется CPU i-quant работой |
| IQ3_S | 54.8 | 50 | 87.69 % | +0.045 | 53 / 46 tok/s | ~38–42 tok/s (5070 Ti #2772) | лучший качества-на-публике, но RAM-фрерж и самый медленный |

### 7. Риски для нашего rig (59 GiB + 2× 16 GB)

1. **IQ3_SRAM-зазор**: 54.8 GB против 59 GiB — на наших 5 GiB системы, KV streaming (+1.7 GB @128K), спекs и
   sweep-запас почти нет; риск = деградация курсором (#2923, #2934, #2316), а не чистый «top-level OOM».
   Mitigation: `--kv-resident` меньше/`--kv k8v4`/`--kv q4_0`, `--resident-budget-gib` (на our 32 GB VRAM
   экспертов на GPU больше, чем у 16 GB-репортов → RAM-часть меньwheel), консл IEX `--conversation-cache-mib`.
   IQ3_XXS (47.0) и IQ2_XS (39.2) безопасны по RAM.
2. **Central дегradация на длинных agent-сессиях**: reproducciones на том же GPU+RAM-строе #1944.
   Вероятность catching этимостей высок🍋 — тестировать длинные ходы на том же движке, который будем take.
3. **CJK/Other-loop long outputs** (#1827): если ответы на non-English (CJK, возможно многие) длинные,
   лиbsная поврежденность без `finish_reason: length` — добыча через runtime health-check, а не через API.
4. **Скачок движка-версии**: менять версию Strata одновременно с измерением качества нельзя (#2457 pattern);
   считать каждую версию — новая точка калибровки.

### 8. Ссылки

- docs: [DETAILS.md](https://github.com/Niko1221/Strata/blob/main/docs/DETAILS.md),
  [QUANTS.md](https://github.com/Niko1221/Strata/blob/main/docs/QUANTS.md),
  [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md),
  [HOW_IT_WORKS.md](https://github.com/Niko1221/Strata/blob/main/docs/HOW_IT_WORKS.md),
  [COMMUNITY_BENCHMARKS.md](https://github.com/Niko1221/Strata/blob/main/docs/COMMUNITY_BENCHMARKS.md)
- benchmarks: [RTX 5090 IQ2_XS 64 GB](https://github.com/Niko1221/Strata/tree/main/bench/results/2026-09-30-community-rtx-5090),
  [RTX 3060 0.1.41 sweep](https://github.com/Niko1221/Strata/tree/main/bench/results/2026-10-09-community-rtx-3060-0141)
- issues: [#2772](https://github.com/Niko1221/Strata/issues/2772) (5070 Ti 64 GB IQ3_S 262K),
  [#2333](https://github.com/Niko1221/Strata/issues/2333) (IQ3_XXS vs IQ3_S 0.1.44),
  [#2117](https://github.com/Niko1221/Strata/issues/2117) (4080 IQ3_S 262K),
  [#1200](https://github.com/Niko1221/Strata/issues/1200) (5060 Ti tuning),
  [#406](https://github.com/Niko1221/Strata/issues/406) (IQ3_S 256K на 64 GB),
  [#1944](https://github.com/Niko1221/Strata/issues/1944) (degradation long story, 5070 Ti),
  [#2923](https://github.com/Niko1221/Strata/issues/2923) (RAM-пресура re-prefill),
  [#2408](https://github.com/Niko1221/Strata/issues/2408) (OOM restore на 2-GPU split),
  [#2934](https://github.com/Niko1221/Strata/issues/2934) (long sessions heap),
  [#2316](https://github.com/Niko1221/Strata/issues/2316) (prefix replay collapse),
  [#1827](https://github.com/Niko1221/Strata/issues/1827) (CJK loop IQ3_S),
  [#438](https://github.com/Niko1221/Strata/issues/438) (Coder CJK),
  [#137](https://github.com/Niko1221/Strata/issues/137) (draft vocab CJK),
  [#2141](https://github.com/Niko1221/Strata/issues/2141) (thinking budget ignored),
  [#1814](https://github.com/Niko1221/Strata/issues/1814) / [#1053](https://github.com/Niko1221/Strata/issues/1053) / [#1178](https://github.com/Niko1221/Strata/issues/1178) / [#804](https://github.com/Niko1221/Strata/issues/804) (`</think>`-обрыв),
  [#2457](https://github.com/Niko1221/Strata/issues/2457) (0.1.44 HIP IQ3_S мусор),
  [PR #2557](https://github.com/Niko1221/Strata/pull/2557) (setup 0.1.44 рекомендует IQ3_S для 64 GB)
