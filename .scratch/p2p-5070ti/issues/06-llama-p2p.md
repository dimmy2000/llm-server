# 06 — llama.cpp: стоит ли GGML_CUDA_P2P (H4)

Type: grilling
Status: resolved
Blocked by: 04

## Question

Выигрывает ли llama-профиль (llama-swap, `-sm tensor`) от P2P и нужно ли
ставить `GGML_CUDA_P2P` в compose?

Проверки:
- environment в `llama/docker-compose.yaml`: `GGML_CUDA_P2P=1` +
  `NCCL_P2P_DISABLE=0` (рецепт чата 2026-09-25 на патченном драйвере);
- те же промпты, что в «Предполётном снапшоте»/«Смене драйвера»: prefill
  90k, decode 8192; дельта против baseline 595 и vanilla-615 (вычесть H2);
- корректность: сравнение выходов — доки llama.cpp предупреждают про
  «crashes or corrupted outputs» при включённом P2P на некоторых
  платах/BIOS.

Ожидание по данным (0010): ~0 (prefill/decode в пределах шума, утилизация
шины <7%, decode latency-bound).

Решение: держать `GGML_CUDA_P2P` в llama-профиле или нет (и оставлять ли
`NCCL_P2P_DISABLE=0`).

## Comments

### 2026-10-11 — замеры сняты (сессия выполнения, стек p2p-615.71.09)

Артефакты: `assets/06-llama-p2p/` (results-llama-p2p-*.json, vram-sampler-*.csv,
bench.py, промпты, llama-startup-p2p.log, vram-sampler.sh).

**Проведено**: `GGML_CUDA_P2P=1` + `NCCL_P2P_DISABLE=0` добавлены в environment
`llama/docker-compose.yaml`, ninfer down → llama up (тот же образ
`ghcr.io/mostlygeek/llama-swap:cuda13`, та же модель NVFP4-MTP-HIGH, тот же
`--split-mode tensor --tensor-split 50,50`), те же промпты тикетов 01/03.
Обнаружено: в образе **нет NCCL** («NCCL not compiled in; falling back to
internal AllReduce») — путь `cudaMemcpyPeerAsync` внутреннего all-reduce,
peer-доступ включается в `ggml_cuda_init` при `GGML_CUDA_P2P`; `NCCL_P2P_DISABLE=0`
в этом образе **инертен**. Вар достиг сервера (проверено `/proc/<pid>/environ`).

**Prefill 90k** (prompt-90k.txt, max_tokens 4, nonce auto):

| Прогон | tok/s | TTFT | prompt_n |
|---|---|---|---|
| run1 (холодный, сразу после загрузки) | 1901.3 | 47.29 с | 89741 |
| run2 | 2042.7 | 45.01 с | 89738 |
| run3 | 2042.6 | 44.93 с | 89742 |
| run4 | 2042.6 | 44.93 с | 89742 |

Стабильное значение **~2043 tok/s** (n=3); run1 — холодный выброс первого
запроса (−7%, CUDA-graph warm-up). Базы: 595-ваниль 2040 (тикет 01, холодный
single), 615-ваниль 1898 (тикет 03, **тоже** холодный single). Дельты: vs 595
+0.1%; vs 615-ваниль +7.6%; с учётом H2 (−7%) и холодного-эффекта
(наш run1 = 1901 ≡ 1898 у 615-ваниль, совпадение 0.15%) — **~0**.

**Decode 8192** (prompt-90k-continue, max_tokens 8192, nonce auto):

| Сессия | tok/s | draft (приём) | finish | токенов |
|---|---|---|---|---|
| p2p-615 (06) | 43.7 | 3767/5624 (67.0%) | length | 8192 |
| 595-ваниль (01) | 44.6 | 65.7% | length | 8192 |
| 615-ваниль (03) | 42.5 | 64.9% | stop | 5042 |

Дельты: vs 595 −2.0%; vs 615-ваниль +2.8%; за вычетом H2 (−4.8%) — **~0**,
внутри шума decode. Prefill decode-прогона 2051 tok/s (консистентно с базами
2047/2037) — без прироста.

**VRAM** (vram-sampler, 1 Hz): min free GPU1 prefill 1845 MiB / decode 1837 MiB,
GPU0 1282/1274 MiB — красная линия 512 MiB держится ~3.6× (сравнение с базами
01/03 некорректно — десктоп-зависимо).

**Корректность** (доки llama.cpp: «crashes or corrupted outputs… when IOMMU is
enabled»; у нас `iommu=pt`): все 4 prefill-комплекта = «The mountain railway
climbed» (байт-в-байт как в 01/03); decode-текст — связная проза, без мусора,
повторов и обрывов; приём драфта 67.0% в полосе баз (64.9–65.7%); крэшей/абортов
нет. Признаков порчи P2P-пути не найдено.

**Итог по данным**: H4 подтверждён — дельта P2P для llama.cpp **~0** (prefill в
пределах шума после вычета H2, decode latency-bound). Стабильное P2P-значение
2043 ≈ 595-база 2040; разница 615-ваниль (1898) vs p2p (2043) лежит в
холодный-выброс/конфаундер H2, выигрыш не демонстрируется.

## Answer

**GGML_CUDA_P2P в llama-профиле НЕ держим — оба env-ключа убраны из
`llama/docker-compose.yaml`** (решение пользователя, 2026-10-11).
`NCCL_P2P_DISABLE=0` при этом фактически инертен: в образе llama-swap:cuda13
NCCL не собран, works на внутренний AllReduce.

- **H4 подтверждён**: дельта P2P для llama.cpp ~0 на этом хосте. Prefill 90k —
  стабильно ~2043 tok/s против 2040 у 595-базы (+0.1%) и 1898 у 615-ваниль;
  с учётом H2 (−7%) и холодного-выброса первого запроса (наш run1 = 1901 ≡
  1898 у 615-ваниль на 0.15%) выигрыш не демонстрируется. Decode 8192 — 43.7
  tok/s против 44.6/42.5 (−2.0%/+2.8%, в шуме). Отличие от NInfer
  (+18…+26% prefill, тикет 05) объяснимо: доля all-reduce в шаге llama.cpp
  мала, decode latency-bound — как и ожидалось по 0010.
- **Корректность**: на этом хосте с `iommu=pt` P2P-путь llama.cpp отработал
  без сбоев и порчи данных (комплеты байт-в-байт как у баз, decode — связная
  проза, приём драфта в полосе). Это НЕ довод держать ключ: доки llama.cpp
  перечисляют «crashes or corrupted outputs» при IOMMU как известный риск, а
  выигрыша нет.
- **VRAM**: min free GPU1 под нагрузкой 1837–1845 MiB — красная линия 512 MiB
  держится с ~3.6× запасом (десктоп-зависимо, с базами не сравнимо).
- **Производство**: ninfer-профиль восстановлен после замеров, `p2p on`,
  `all-reduces: copies`, живой запрос отвечает; llama-профиль возвращён к
  базовому compose без env-ключей (P2P через llama.cpp не участвует в работе
  профиля — нулевая дельта и нулевой эффект от его отсутствия).

Решение по итоговому стеку (драйвер, iommu=pt, обслуживание) — тикет 08;
снятие `iommu=pt` отдельным решением после тикетов 04/07.
