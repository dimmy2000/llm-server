# 04 — Включение P2P: модули 615.71.09-p2p + iommu=pt + верификация (H1/H5)

Type: task
Status: resolved
Blocked by: 03

## Question

Как включить P2P и доказать, что данные передаются корректно (матрица OK ≠
данные OK, issue #25)?

Шаги:
- бэкап `/etc/default/grub`; `amd_iommu=on iommu=pt` в
  `GRUB_CMDLINE_LINUX_DEFAULT`, `update-grub`;
- собрать + установить модули ветки `615.71.09-p2p` (тот же userland
  615.71.09), reboot;
- верификация: `nvidia-smi topo -p2p r/w` = `OK/OK`; `simpleP2P` — без
  verification errors; `p2pBandwidthLatencyTest` — ожидается ~12–15 GB/s
  unidirectional (потолок Gen5 x8 ~15.75 GB/s, обе связи x8);
- записать дельты против «Предполётного снапшота» (staging) и «Смены
  драйвера» (vanilla);
- если P2P не завёлся: сначала iommu=pt / BAR1 (16G) / NVRM-строки в dmesg,
  затем фолбэк-ветка из «Драйверной ветки».

Решение: P2P работает с верифицированными данными + число полосы; ответ на
«нужен ли iommu=pt» (H5) в той мере, в какой он выяснится здесь.

## Comments

### 2026-10-10 22:45 — подготовка выполнена, ожидание reboot (сессия выполнения)

До reboot сделано:

- Источники: `/opt/nvidia-615.71.09/open-gpu-kernel-modules-615.71.09-p2p/`,
  ветка `615.71.09-p2p`, HEAD `c8bff54` (совпадает с тикетом 02). Патч
  затрагивает bus/p2p/mem-mgr (`nv.c`, `nv-dma.c`, `nv-mmap.c`, `nv-usermap.c`,
  `os-mlock.c`, `uvm_devmem.c`, `kernel_bif.c`, `p2p_caps.c`, `io_vaspace.c`,
  `mem_desc.c`, `virt_mem_allocator_*`, `mapping_list.h`) + `install.sh` +
  `patch-libcuda-p2p.py` (не нужен — пара однопоколенная).
- Сборка: `make modules -j32` под `7.0.0-38-generic` — чисто, 5 модулей
  (nvidia, modeset, drm, uvm, peermem), тот же warning «Skipping BTF», что и у
  vanilla.
- Установка: `sudo make modules_install` →
  `/lib/modules/7.0.0-38-generic/kernel/drivers/video/` (тот же путь поверх
  vanilla), `depmod 7.0.0-38-generic` выполнен; sha256 всех 5 установленных
  `.ko` отличаются от vanilla (`backup-vanilla-modules-7.0.0-38/
  sha256sums-{installed,p2p-installed}.txt`); `modprobe --show-depends`
  резолвится в новые файлы; `modinfo -F version` = 615.71.09, vermagic
  `7.0.0-38-generic … modversions`. Initramfs nvidia-модулей не содержит
  (`lsinitramfs | grep -c nvidia` = 0) — перегенерация не требуется
  (blacklist nouveau из тикета 03 на месте).
- GRUB: бэкап `/etc/default/grub.bak-p2p-20261010`;
  `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_iommu=on iommu=pt"`,
  `update-grub` выполнен, параметр в 3 записях `grub.cfg`.
- CUDA-сэмплы пересобраны (`/tmp` от тикета 01 вычищен): тег `v13.3`
  cuda-samples (в master-е сэмпл удалён в 13.4), nvcc 13.3 `-arch=native`,
  бинарники в `/opt/nvidia-615.71.09/p2p-bin/{simpleP2P,p2pBandwidthLatencyTest}`
  (персистентно, переживёт reboot).
- Контейнеры: `compose down` (ninfer-профиль), `docker stop llm-*` — как в
  тикете 03; `docker ps` пуст. Vanilla-модули забэкаплены в
  `/opt/nvidia-615.71.09/backup-vanilla-modules-7.0.0-38/`.

### Runbook после reboot (если сессия оборвётся)

1. Проверки стека: `cat /proc/cmdline` → `amd_iommu=on iommu=pt`;
   `nvidia-smi` → 615.71.09, обе карты, gnome-shell на GPU1 жив;
   `nvidia-smi -q | grep -A4 BAR1` → 16384 MiB (H7);
   `sudo dmesg | grep -iE 'nvrm|nvidia|iommu'` — без NVRM-ошибок;
   `nvidia-smi topo -p2p r/w` → ожидание **OK/OK** (CNS/NS → триггер фолбэка,
   см. ниже).
2. Верификация данных (матрица OK ≠ данные OK, issue #25):
   `/opt/nvidia-615.71.09/p2p-bin/simpleP2P` → Peer access Yes/Yes, без
   verification errors (артефакт
   `assets/04-p2p/simpleP2P-p2p-615.txt`);
   `/opt/nvidia-615.71.09/p2p-bin/p2pBandwidthLatencyTest` → P2P=Enabled
   ожидание ~12–15 GB/s unidirectional, latency ~0.3–0.4 us
   (артефакт `assets/04-p2p/p2pBandwidthLatencyTest-p2p-615.txt`).
3. Если P2P не завёлся (по тикету): сначала iommu=pt в cmdline / BAR1 16G /
   NVRM-строки в dmesg → фолбэк-ветка `610.57.04-p2p-v3` (тикет 02: полный
   стек 610.57.04 + пересъёмка vanilla-baseline). Не-триггеры фолбэка:
   полоса < 10 GB/s (H8/H6), выпадение после ребута (тикет 07).
4. Записать дельты против staging (24.85 GB/s, `assets/01-preflight/`) и
   vanilla-615 (`assets/03-vanilla-615/`), Answer, закрыть тикет,
   обновить map.md.
5. Движки (H3/H4/H12) — НЕ здесь: тикеты 05/06. Здесь только драйверная
   верификация.

**Откат** (проверяемый, без пересборки): `sudo cp /opt/nvidia-615.71.09/
backup-vanilla-modules-7.0.0-38/nvidia*.ko
/lib/modules/7.0.0-38-generic/kernel/drivers/video/`,
`sudo cp /etc/default/grub.bak-p2p-20261010 /etc/default/grub`,
`sudo update-grub`, `sudo depmod -a 7.0.0-38-generic`, reboot →
рабочий vanilla-стек тикета 03 (P2P не работает, всё остальное живо).
Терминальный откат на apt 595.99.02 — как в тикете 03.

## Answer

P2P между 5070 Ti включён и **верифицирован по данным** 2026-10-10 (reboot
ручной, контейнеры на время окна остановлены). Артефакты:
`assets/04-p2p/` (system-snapshot-p2p-615.txt, simpleP2P-p2p-615.txt,
p2pBandwidthLatencyTest-p2p-615.txt); стек — `/opt/nvidia-615.71.09/`
(исходники ветки `615.71.09-p2p` HEAD `c8bff54`, бинарники сэмплов
`p2p-bin/`, бэкап vanilla-модулей `backup-vanilla-modules-7.0.0-38/`).

**Стек**: тот же userland/GSP 615.71.09 из тикета 03 + патченные модули
ветки `615.71.09-p2p` (5 модулей, тот же путь
`/lib/modules/7.0.0-38-generic/kernel/drivers/video/`, depmod вручную после
modules_install — как в тикете 03). Провенанс подтверждён: NVRM-строка
dmesg несёт таймштамп p2p-сборки (22:39; vanilla была 14:13). GRUB:
`amd_iommu=on iommu=pt`, dmesg подтверждает
`iommu: Default domain type: Passthrough (set via kernel command line)`.
dmesg без NVRM-ошибок/Xid, gnome-shell на GPU1 жив, BAR1 16384 MiB обе
карты (H7 ✓), десктоп-VRAM GPU1 423 MiB (в простое).

**H1 — P2P работает**:

| Проверка | Staging 595.99.02 (тикет 01) | Vanilla 615 (тикет 03) | p2p 615.71.09 (тикет 04) |
|---|---|---|---|
| `topo -p2p r/w` | CNS | GNS | **OK / OK** |
| `simpleP2P` | waived (нет peer) | — (GNS) | **Test passed**, Peer Yes/Yes, без verification errors |
| Unidirectional P2P=Enabled (P2P Writes) | 24.84–24.85 GB/s (fallback=staging) | — | **28.66 / 28.65 GB/s** |
| Bidirectional P2P=Enabled | 27.40–27.48 GB/s (fallback) | — | **56.07 / 56.09 GB/s** |
| Latency GPU↔GPU (P2P Writes) | 12.5–14.4 us (fallback) | — | **0.33–0.34 us (−97 %)** |
| P2P=Disabled (sanity staging-пути) | 24.85 GB/s | — | 24.67–24.74 GB/s — без изменений |

Критерий успеха H1 (0010): simpleP2P без ошибок + полоса ≥ 10 GB/s —
выполнен с запасом 2.9×. cudaMemcpyPeer в simpleP2P — 26.59 GB/s
(согласуется с матрицей).

**Поправка к ожиданиям 0010**: расчёт «Gen5 x8 → ~15.75 GB/s на
направление» ошибочен (это потолок Gen4 x8; Gen5 x8 ≈ 31.4 GB/s raw на
направление). Измеренные 28.66 GB/s — ~91 % от raw-потолка Gen5 x8, что
согласуется с 5090-парой на EPYC (27 GB/s, x16-gen4-класс) и с сентябрьским
замером этой же пары на старом хосте (8.9 GB/s, PCIe 3.0). P2P-write
быстрее staging-пути (+15 % к 24.85), латентность транзакций — 0.3–0.4 us
из README aikitoria воспроизведена (0.33–0.34 us против ~12.5–14.4 us
через CPU).

**H5 (iommu=pt) — частично**: P2P работает при `amd_iommu=on iommu=pt`
(dmesg: Passthrough default domain), конфликтов NVRM/IOMMU нет. Изолировать
вклад pt (модули без pt) не тестировалось — это требование README ветки
(«The IOMMU must be configured for passthrough»), отдельный reboot-цикл не
оправдан. Вопрос «можно ли снять pt (вернуть DMA-изоляцию)» остаётся
отдельным решением после тикетов 04/07 (уже в Not yet specified карты).

**Наблюдение (H12, без бенчей — тикет 05)**: тот же образ
`llm-server/ninfer-tp2:v0.4.6` без пересборки стартует со строкой
`p2p on` и `captured all-reduces: copies` (вместо
`mailbox | exchange kernel pipelined` без P2P) — рантайм-детект подхватил
peer access; KV-пул auto 381 376 токенов против 351 488 у vanilla-615,
free 709.8 MiB (старт после окна, запрос обслужен, драфт 2/2). Артефакт —
`assets/04-p2p/ninfer-startup-p2p-on.log`. Замеры эффектов — тикет 05.

**Откат** зафиксирован в Comments (восстановление vanilla-модулей + GRUB,
без пересборки); терминальный откат на apt 595.99.02 — как в тикете 03.
