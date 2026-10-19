# Прогон матрицы замеров

Status: resolved
Type: task
Blocked by: 05, 06

## Progress (2026-10-18)

- **IQ3_XXS: окно закрыто полностью** — все сценарии протокола done/pass
  (статус-борд и детали: `assets/status.md`, свод: `assets/summary-matrix.md`,
  паспорт прогона: `assets/IQ3_XXS/cover.json`). Ключевое: decode 129–153 tok/s
  (~6.5× репера llama.cpp 20 tok/s) на всех дистанциях вплоть до 110K контекста;
  red-line VRAM GPU1 ≥512 MiB не нарушена за окно; agent-live подтверждён headless
  (по решению пользователя — «провести сам, достаточно убедиться, что работа идёт»,
  `--standalone`, сессия `ses_eaffb5f15ffe64gyaIJH7l8VuO`); soak pass; vision-smoke
  pass (Q8_0 mmproj локальным квантованием + CPU-энкодер).
- Попутно установлен старт-лествицей: XS @32K = prefill 4096 + cache 6800;
  S @32K: `--resident-experts` — блокер движка (cuBLAS status 3),fallback
  non-resident cache 4000. Конфиги `/opt/strata/strata-{iq3_s,iq2_xs}.json`
  перезаписаны начисто на эти значения.
- **IQ3_S: окно закрыто полностью 2026-10-18/19** — все сценарии протокола done/pass
  (паспорт `assets/IQ3_S/cover.json`, статус-борд — секция IQ3_S в `assets/status.md`,
  свод — `assets/summary-matrix.md`). Потолок **65536** — старт с 1-й попытки на нативных
  chunk 4096 / cache 4000 (лествица не потребовалась). Ядро: chat decode мед 122.4 tok/s
  (**~6.1× репера llama.cpp 20 tok/s**), prefill 4K/16K/32K/fresh-64K = 2426/4062/4525/4726
  tok/s, decode при полном KV 141.3, longgen 4500 tok @ 174.1 tok/s (admission 93.2 %);
  agent-live headless pass (prefix-cache работает); multiturn 60 262 tok (92 %) reuse каждый
  тур; soak pass (3×20 c, цикл 12/24/16 c); vision-smoke pass (CPU-encoder). Красная линия
  GPU1 (min 1296 MiB) и пороги RAM/диска соблюдены; RAM тесная (min 2.9 GiB avail) —
  ожидаемая плата non-resident режима при блокере `--resident-experts`. **Вердикт: стабильно.**
  Окно разбито на два субагент-прохода (прерывание первого — не причина данных): все артефакты
  таким образом собраны и финализированы в `assets/IQ3_S/`.
- **IQ2_XS: окно выполнено и закрыто в этот же день (2026-10-18, 20:14–20:52 UTC)** —
  детализирующий блок ниже (пункт оставлен из очереди планирования, помечен выполненным;
  конфиг в итоге: prefill 4096 + cache 5400 @262144).
- (2026-10-19,UTC дубль-проход IQ3_S) Параллельная (дубльная) сессия повторила остаток
  S-окна 21:12–21:55Z после разъезда параллельных окон (конфликт 20:00–20:16Z задокументирован
  в `assets/IQ3_S/cover.json`): все сценарии независимо подтверждены — agent-live вторая
  сессия `ses_eaf159f5cffeBejAVFA6JgsdI1` (prompt 14 382 fresh @ 3334.8; финальный ответ
  1013 tok @ 157.0; reuse-цепочка работает), multiturn 60 259 tok = 91.9 % pass, soak 3×24 c
  pass, vision 2/2 pass; два НОВЫХ env-фикса для будущих окон: (1) http(s)_proxy окружения
  ломает bun-fetch opencode (запуск с env -u …), (2) имя провайдера `llama-swap` в
  strata-конфиге конфликтует с глобальным (:8080) — переименовать (использован `strata-s`).
  Дополнение вписано в `summary-matrix.md` § IQ3_S «Дополнение — второй (дубльный) проход»;
  паспорт дубля — `assets/IQ3_S/cover.json`.


## Question

(Исполняемая задача, HITL — нужны окна остановленного стека) Прогнать согласованную
матрицу из тикета протокола для каждой модели:

- Вытесняющий режим: стек вниз (`docker compose down`), Strata на `:8081`, обе карты
  (fallback на одну — если VRAM GPU1 рушит красную линию).
- Порядок: IQ3_XXS → IQ3_S → IQ2_XS; ранний стоп при непреодолимых OOM.
- Фиксировать в `.scratch/strata-model-selection/assets/`: сырые логи, таблицы
  decode/prefill, 128K-потолок, агент-сессия (ссылка на opencode-сессию + впечатления
  пользователя субъективно), многотуровой чат, soak, RAM/swap/VRAM-кривые.
- Пользователь в цикле: окна времени, субъективная оценка агент-сессий, итоговые
  «стабильно/нестабильно» по каждой модели.

Resolved when: матрица прогнана, сырые данные сложены, первые выводы зафиксированы.

## Answer

Матрица прогнана полностью — **все три окна done/pass, «матрица завершена»** (2026-10-18,
19:14–21:58Z). Свод — `assets/summary-matrix.md`, статус-борд — `assets/status.md`,
паспорта — `assets/{IQ3_XXS,IQ3_S,IQ2_XS}/cover.json`.

- **IQ3_XXS (@131072)**: decode 129–153 tok/s (~6.5× репера llama.cpp 20 tok/s) до 110K;
  красная линия GPU1 не нарушена (min 1494 MiB). Стабильно.
- **IQ3_S (@65536)**: chat decode мед 122.4 tok/s (~6.1×), prefill 2426→4726 tok/s,
  decode при полном KV 141.3, longgen 4500 tok @ 174.1 (admission 93.2 %); GPU1 min 1296 MiB;
  RAM тесная non-resident (min 2.9 GiB avail, своп-пик +667 MiB) — ожидаемая плата блокера
  `--resident-experts`. Стабильно. Дубльный проход 21:12–21:55Z независимо подтвердил
  multiturn/soak/agent-live (+2 env-фикса opencode: прокси ломает bun-fetch; конфликт имени
  провайдера `llama-swap` с глобальным — переименован в `strata-s`).
- **IQ2_XS (@262144)**: потолок максимальный из трёх (лествица cache 6800→5400;
  262144@6800 — CUDA0 160 MiB LOW); chat decode мед 144.90 tok/s, agent 154.70, prefill
  2698→4886 tok/s, fresh-232k prefill 4571.7 (TTFT 50.9 с), decode при полном KV 136.4,
  longgen 4096 @ 156.4 (admission 81.9 %); GPU1 min **1605 MiB** (лучшая из трёх), RAM min
  6.0 GiB (XS целиком в RAM), своп-пик +1451 MiB на цикле S. Стабильно.
- Общее: друг у друга пороги VRAM/своп/диск не нарушены ни в одном сценарии; 0 падений
  движка и 0 ретранов за три окна; всем gapes-профиль одинаков (forced tool работает,
  structured+tools → 400, невалидный effort → 400, xhigh/low → 200); vision CPU-encoder
  pass у всех трёх; калибровка XXS 37 мин / S 8.5 / XS 6.
- Дальше — тикет «Финальный отчет и решение» (08): сравнение размеров и выбор «какой
  держать постоянно». Fog-вопрос карты «что дальше, если 3-бит не держат RAM» сужен:
  RAM обе 3-бит версии держат, поэтому выбор — между XXS (потолок 131072, плата лествицы
  на старте), XS (потолок 262144, целиком в RAM, лучшая VRAM-гигиена) и S (тот же потолок
  64K, RAM-теснота non-resident + движковый блокер resident).

## Progress

- IQ3_XXS: окно 2026-10-18 — все сценарии pass, декод 129–153 tok/s на каждой
  дистанции до 116K, soak OK, агент-сессия подтверждена. Матрица —
  `assets/summary-matrix.md` (раздел IQ3_XXS), детали — `assets/IQ3_XXS/`.
- IQ3_S: окно 2026-10-18/19 закрыто (продолжение после обрыва суб-агента, суб-агентским
  окном finished: steps 1–6). Все этапы pass: потолок 65536 с 1-й попытки, калибровка
  ~8.5 мин, chat decode мед 122.4 tok/s, fresh-ceiling префилл 4725.5 tok/s, decode при
  полном KV 141.3, longgen ровно 4096 токенов (EOS-порок прошлого прогона — артефакт
  filler-промпта, не движка), multiturn 15 туров до 60262 tok (структурно; реакции туров
  8–15 = 2 tok — EOS при temp 0, сноска), agent-live + vision-smoke + soak 6/6.
  Аудит порогов: GPU0 min 683 / GPU1 min 1296 MiB, swap max +667 MiB, падение движка 0.
  Матрица/борд: `assets/summary-matrix.md` (## IQ3_S), `assets/status.md` (## IQ3_S),
  артефакты — `assets/IQ3_S/` (cover.json, watch-аннотации.md, slices/).
- **IQ2_XS: окно 2026-10-18 (20:14–20:52 UTC) закрыто полностью, все этапы pass.** Потолок
  **262144** (лествица: 32768 смоук → 131072 OK с 1-й → 262144 cache 6800 → CUDA0 160 MiB LOW →
  **cache 5400** OK 2176/1706 MiB — максимум-потолок из трёх моделей; калибровка ~6 мин →
  pcie-frac 0.20 / spec-min-p 0.70, adaptive НЕ записан калибратором — дефолт-tier остался).
  Числа: chat 144.90 tok/s, agent 154.70, prefill 4K 2698 / 16K 4431 / 32K 4886, fresh-потолок
  232118 tok = 88.5 % @ 4571.7 tok/s (TTFT 50.9 c), decode при полном KV 136.4, longgen
  4096 @ 156.4 tok/s (admission 81.9 %), reuse до 232123 tok (TTFT 0.074 c). Гэпы: forced tool
  200 / structured+tools 400 / json_schema без tools 200 / невалидный effort 400 / xhigh-low 200
  (= XXS/S). Multiturn 15×16000 pass (240258 tok = 92 %). Agent-live headless pass (cold 14450 →
  20722 reused, decode 162.8 tok/s). Vision pass (CPU-encoder, 2/2 корректно, 2.1–2.4 c). Soak
  pass (3×cold READY 17/16/16 с, цикл 16/24/16 с). Аудит порогов: **GPU0 min 2103 / GPU1 min
  1605 MiB** (лучшая из трёх), swap max 2167 (пик на цикле S; net +650), RAM min 6047 MiB,
  NVMe-штормов нет, падений/ретраев 0. Матрица: `assets/summary-matrix.md` (## IQ2_XS),
  борд: `assets/status.md` (## IQ2_XS), артефакты: `assets/IQ2_XS/` (cover.json с
  thresholds_audit/verdict_final, watch-аннотации.md, slices/, bootstrap). **Матрица
  завершена — все три окна закрыты.**
