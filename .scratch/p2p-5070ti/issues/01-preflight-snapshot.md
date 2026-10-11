# 01 — Предполётный снапшот: baseline и артефакты отката

Type: task
Status: resolved
Blocked by: 

## Question

Какой полный «до»-снапшот зафиксировать на текущем драйвере 595.99.02,
чтобы любые дельты после смены драйвера и включения P2P мерились против
актуального состояния, а не против цифр из документации?

Что снять (артефакты — файл/раздел в `docs/research/` или asset тикета):
- `nvidia-smi topo -m`, `topo -p2p r/w` (CNS), BAR1 (16G), PCIe-линки
  (Gen5 x8), GRUB, версия apt-драйвера и nvidia-модулей в `/lib/modules` —
  база для отката;
- `p2pBandwidthLatencyTest` без P2P (staging-полоса) — «до» для дельты H1;
- NInfer mailbox-baseline: быстрый повтор приёмки (prefill 30k/90k, decode
  короткий, приём драфта ~47%) — документ 0009 снимался на 595.91.07,
  подтвердить на 595.99.02;
- llama.cpp tensor-baseline на текущем драйвере: prefill 90k + decode 8192
  (AGENTS.md: 1372/80.5 — подтвердить; требует остановки NInfer-контейнера,
  GPU общие).

Решение: «до»-артефакт в репо + числа, против которых сравниваются тикеты
03/05/06; путь к снапшоту отката зафиксирован.

## Answer

Снапшот снят 2026-10-10 на драйвере 595.99.02 (vanilla apt), ядро 7.0.0-38,
NInfer v0.4.6 (DFlash2, nvfp4 KV, пул 342 784, `p2p off (host-staged copies)`,
mailbox probe 0.03 ms). Артефакты: `.scratch/p2p-5070ti/assets/01-preflight/`
(`system-snapshot.txt`, `bench.py`, промпты, results-*.json, vram-sampler-*.csv,
p2pBandwidthLatencyTest/simpleP2P выводы).

**Методика** (переиспользуется тикетами 03/05/06 без изменений):
`bench.py` — streaming TTFT + движковые `timings` из финального чанка;
промпты `prompt-30k.txt` (29 964 tok) / `prompt-90k.txt` (89 742 tok) из
филлера ~82.3 tok/юнит; каждый прогон с nonce-префиксом — иначе device-state
кэш NInfer реплеит префикс (наблюдалось `cache 99.6%`, фейковый prefill 848 tok/s).

**NInfer mailbox-baseline (595.99.02):**

| Метрика | Значение |
|---|---|
| Prefill 30k | 4571 tok/s (TTFT 6.57 s) |
| Prefill 90k | 3411 tok/s (TTFT 26.35 s), повтор 3413 |
| Decode 600, `chat-medium`, essay | 166.6 tok/s, приём DFlash2 399/1392 (28.7%) |
| Decode 600, `chat-medium`, story | 152.2 tok/s, 380/1519 (25.0%) |
| Decode 600, `chat-medium`, essay-rerun | 139.5 tok/s, 360/1656 (21.7%) |
| Decode 600, instruct alias | 129.2 tok/s, 341/1791 (19.0%) |
| Min free VRAM под 90k prefill | GPU1 613 MiB, GPU0 1320 MiB (десктоп-зависимо) |

Расхождение с приёмкой тикета 13 (decode ~235 tok/s, 47%): точный промпт той
приёмки не записан, приём DFlash2 сильно prompt-зависим (проверено на четырёх
промптах: 19–29%). Канон для дельт — числа выше на записанных промптах.

**llama.cpp tensor-baseline (595.99.02, NVFP4-MTP-HIGH, ctx 180224):**

| Метрика | Значение |
|---|---|
| Prefill 90k | 2040 tok/s (TTFT 44.1 s) |
| Decode 8192 (prompt-90k-continue, finish=length) | 44.6 tok/s, draft 3743/5695 (65.7%) |
| Min free VRAM под нагрузкой | GPU1 1133 MiB, GPU0 814 MiB |

Оба эталона AGENTS.md (1372/80.5) сняты на Q8_0-кванте до перехода на
NVFP4-MTP-HIGH: prefill на NVFP4 заметно быстрее (2040 vs 1372), decode на
длинном контексте медленнее эталона (44.6 vs 80.5) — эталон устарел, тикету 06
сравниваться против чисел выше, не против AGENTS.md.

**P2P staging-базе (H1 «до»):** `simpleP2P` — peer access не обнаружен
(ожидаемо); `p2pBandwidthLatencyTest` (cuda-samples v12.4.1 @ `5f97d7d0`,
nvcc 13.3 `-arch=native`, бинарник в `/tmp/opencode/p2p-bin/`, пересобрать по
команде из Answer при необходимости): P2P Disabled cross-GPU **24.85 GB/s**
unidirectional (bidirectional 27.5), latency 12.5–14.4 µs. Бинарник временный
— тикету 04 после смены драйвера пересобрать той же командой.

**Система для отката:** apt `nvidia-driver-595-open 595.99.02-0ubuntu0.26.04.1`
(installed == candidate), dkms `nvidia/595.99.02` собран под 7.0.0-29/-34/-38,
`/lib/modules/7.0.0-38/updates/dkms/nvidia*.ko.zst` на месте; GRUB без
iommu-параметров; BAR1 16384 MiB обе карты; PCIe Gen5 x8 (max 16); Secure Boot
off; IOMMU активен (ivhd0) без `pt`. Образы: `llm-server/ninfer-tp2:v0.4.6`
(f8d6ebcc), `ghcr.io/mostlygeek/llama-swap:cuda13` (3d49d5d9). Профиль ninfer
после снапшота восстановлен и проверен живым запросом.
