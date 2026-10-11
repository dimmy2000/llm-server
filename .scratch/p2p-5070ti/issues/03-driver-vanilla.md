# 03 — Смена драйвера на 615.71.09: vanilla userland + vanilla-модули, vanilla-baseline (H2)

Type: task
Status: resolved
Blocked by: 01, 02

## Question

Как выполнить этап 2 из 0010 — смену драйверного стека БЕЗ P2P-патча — и
изолировать конфаундер версии драйвера до того, как мерить эффект P2P?

Последовательность (maintenance-окно, NInfer остановлен, сессия по SSH/TTY —
при снятии 595.99 GPU на дисплее сломается):
- снять apt `nvidia-driver-595-open` + dkms-остатки (чистка `/lib/modules`
  от nvidia* — по заметке vladie в issue #25, чтобы не смешать модули);
- userland 615.71.09: `.run --no-kernel-modules` (GSP firmware, nvidia-smi,
  libcuda, nvidia-container-toolkit-совместимость);
- собрать vanilla open-модули 615.71.09 (без p2p-патча) под ядро
  `7.0.0-38-generic`, установить;
- reboot: nvidia-smi 615.71.09, контейнеры `llama-swap` (NInfer) и
  мониторинг `llm-*` поднялись, P2P по-прежнему CNS (vanilla не включает —
  ожидаемо);
- vanilla-baseline: NInfer (prefill 30k/90k, decode, приём драфта) и
  llama.cpp (prefill 90k, decode 8192) — дельта H2 «vanilla 615 vs vanilla
  595», которую нужно вычитать из любого «прироста P2P».

Откат (зафиксировать в Answer): вернуть apt `nvidia-driver-595-open`,
GRUB не меняться, контейнеры штатно.

Решение: рабочий vanilla-стек 615.71.09 + числа H2.

## Comments

### 2026-10-10 — прогресс подготовки (сессия выполнения)

- Статус: claimed. Артефакты этапа — `.scratch/p2p-5070ti/assets/03-vanilla-615/`
  (bench.py, prompt-30k/90k/90k-continue, vram-sampler.sh).
- Userland 615.71.09: `/opt/nvidia-615.71.09/NVIDIA-Linux-x86_64-615.71.09.run`
  (sha256 `cdceed22bbeb61248d1a6deabc2596673e3a6501698ee71ac8d2fdc28f3b70fe`).
  Vanilla-исходники: официальный тег `615.71.09`
  (`/opt/nvidia-615.71.09/open-gpu-kernel-modules-615.71.09/`, sha256 тарбола
  `caf48cda7d5fe7374d1d24ca4a90efb4dc783eefabfad5fa4b64fdc24213b62a`).
- **Риск снят заранее**: `make modules -j32` под `7.0.0-38-generic` собрался
  чисто (gcc 15.2 == компилятор ядра; MODVERSIONS=y, Secure Boot off) —
  все 5 модулей (nvidia, modeset, drm, uvm, peermem).
- GSP-firmware идёт из `.run --no-kernel-modules` (README исходников прямо
  рекомендует эту пару). Контейнерные пакеты (nvidia-container-toolkit,
  libnvidia-container*) не трогаются. GRUB не меняется.

### Runbook после reboot (если сессия оборвётся)

1. Проверки: `nvidia-smi` → 615.71.09, обе карты; `nvidia-smi -q | grep -A4 BAR1`
   → 16384 MiB; `nvidia-smi topo -p2p r/w` → CNS (ожидаемо, vanilla);
   `dmesg | grep -iE 'nvidia|nvrm'` — чисто; gnome-shell жив.
2. `cd ../infrastructure/llm-monitoring && ./llm-stack.sh up ninfer`; дождаться
   health; в логе `llama-swap` строка движка: `p2p off (host-staged copies)`,
   `KV … free … MiB` — записать free (H10).
3. NInfer-бенчи (методика тикета 01, nonce auto, канон — движковые timings):
   prefill 30k (`bench.py --model qwen3.8-27b --prompt-file prompt-30k.txt
   --max-tokens 4`), prefill 90k, decode 600 chat-medium essay/story/instruct
   (`--max-tokens 600`), результаты в `results-*-615-*.json`; vram-sampler
   фоном на 90k prefill (min free GPU1, красная линия 512 MiB).
4. llama.cpp: `--profile ninfer down` → `--profile llama up --wait`; prefill 90k
   (`--model qwen3.8-27b --prompt-file prompt-90k.txt --max-tokens 4`), decode
   8192 (`--prompt-file prompt-90k-continue.txt --max-tokens 8192`, finish=length),
   vram-sampler. Вернуть ninfer-профиль.
5. Записать Answer (таблица H2: vanilla-615 против vanilla-595 из тикета 01),
   закрыть тикет, обновить Decisions so far карты.
- Откат в любой момент: `sudo apt-get install nvidia-driver-595-open`,
  удалить модули из /lib/modules/7.0.0-38-generic (не-dkms пути), reboot.
  GRUB не трогать.

### 2026-10-10 14:15 — состояние перед reboot

Стек собран и установлен, ребут не выполнен:
- apt 595.99.02 снят (purge 17 пакетов), dkms пуст; linux-headers и старые
  ядра 7.0.0-29/-34 НЕ тронуты (страховка отката), GRUB не менялся.
- userland 615.71.09 установлен (`.run --no-kernel-modules`, второй прогон —
  первый скипнулся из-за X-сервера; `--no-x-check` решает). GSP-прошивки:
  `/lib/firmware/nvidia/615.71.09/{gsp_ga10x.bin,ucodes_ga10x.bin}`.
  `nvidia-smi` сейчас даёт ожидаемый `NVML mismatch 615.71/595.99` — уйдёт
  после reboot.
- vanilla-модули 615.71.09 установлены в
  `/lib/modules/7.0.0-38-generic/kernel/drivers/video/` (nvidia, modeset,
  drm, uvm, peermem); `modprobe --show-depends` для всех пяти резолвится в
  новый путь; depmod снят вручную (modules_install пишет «missing
  System.map» — это его безобидный пропуск depmod).
- Blacklist nouveau создан руками:
  `/etc/modprobe.d/nvidia-vanilla-blacklist.conf` (purge снёс убунтовский,
  `.run --no-kernel-modules` свой не пишет). nvidiafb уже блокируется
  убунтовским `blacklist-framebuffer.conf`. initramfs -38 перегенерирован.
- Контейнеры: все остановлены (llm-* — `docker stop`, политика
  unless-stopped переживает reboot; llama-swap — compose down).
- Ожидание на reboot: P2P остаётся CNS; при загрузке gnome-shell должен
  подняться на GPU1.

## Answer

Vanilla-стек 615.71.09 развёрнут и отработан 2026-10-10 (maintenance-окно,
reboot ручной). Артефакты: `.scratch/p2p-5070ti/assets/03-vanilla-615/`
(results-*.json, vram-sampler-*.csv, run-ninfer.sh); стек — `/opt/nvidia-615.71.09/`
(userland `.run` sha256 `cdceed2…b70fe`, исходники — официальный тег
`615.71.09`, tarball sha256 `caf48cd…13b62a`).

**Стек**: NVRM Open Kernel Module 615.71.09 (собран на этой машине: gcc 15.2 ==
компилятор ядра 7.0.0-38, MODVERSIONS=y, Secure Boot off), userland/GSP из
`.run --no-kernel-modules` (`/lib/firmware/nvidia/615.71.09/gsp_ga10x.bin`),
модули в `/lib/modules/7.0.0-38-generic/kernel/drivers/video/` (nvidia,
modeset, drm, uvm, peermem), depmod руками (modules_install пропускает depmod
без System.map — безобидно). Blacklist nouveau создан вручную
(`/etc/modprobe.d/nvidia-vanilla-blacklist.conf`): purge apt-пакетов сносит
убунтовский, `.run --no-kernel-modules` свой не пишет — без него nouveau
перехватил бы карты на загрузке. Первый прогон `.run` скипнулся на живом
X-сервере (silent auto-answer «Abort»), лечится `--no-x-check`. BAR1 16384 MiB
обе карты (H7 ✓), dmesg чистый, дисплей на GPU1 жив. Контейнерные пакеты
(nvidia-container-toolkit) не тронуты.

**P2P**: `topo -p2p r/w` = **GNS** (GPU not supported) — на 595 код был CNS;
vanilla 615 P2P по-прежнему не включает, ожидаемо. NInfer стартовая строка:
`p2p off (host-staged copies)`, mailbox probe 0.09 ms (было 0.11) — H12-паттерн
подтверждён: транспорт чисто рантайм-детект.

**H2 «vanilla 615 vs vanilla 595» (канон «до» — `assets/01-preflight/`):**

| Метрика | 595.99.02 (тикет 01) | 615.71.09 | Дельта |
|---|---|---|---|
| NInfer prefill 30k | 4571 tok/s | 4594 tok/s | +0.5% |
| NInfer prefill 90k | 3411 / 3413 tok/s | 3416 / 3408 tok/s | ~0% |
| NInfer KV-пул (auto, nvfp4) | 342 784 | 351 488 | +2.5% |
| NInfer free VRAM на старте | 708.7 MiB | 707.3 MiB | ~0 |
| NInfer min free GPU1 под 90k | 613 MiB | 1079 MiB | десктоп-зависимо, линия 512 держится |
| NInfer decode 600 (4 промпта) | 129.2–166.6 tok/s, приём 19.0–28.7% | 132.0–161.2 tok/s, приём 20.2–27.8% | та же полоса |
| llama.cpp prefill 90k | 2040 tok/s (TTFT 44.1 s) | 1898 tok/s (TTFT 47.4 s) | **−7.0%** |
| llama.cpp decode 8192 | 44.6 tok/s, draft 65.7% | 42.5 tok/s, draft 64.9% | −4.8% |
| llama.cpp min free GPU1 | 1133 MiB | 2022 MiB | десктоп-зависимо |

Оговорки к измерениям: NInfer-decode промпты 01 не сохранялись — на 615 сняты
реконструированные (тема та же), поэтому decode/приём сравниваются только
направленно; префиллы — на тех же файлах промптов, сравнение точное.
llama.cpp decode-8192 дошёл до `finish=stop` на 5042 токенах (у 01 —
`length` на 8192; стохастика семплинга при том серверном sampling-профиле).
Главный H2-факт: **prefill llama.cpp на 615 ниже на 7%** (направление
совпадает с прецедентом 610→615 −14% с другого хоста) — эту дельту вычитать
из любого «прироста P2P» тикетов 04–06; NInfer-префиллу смена драйвера не
повредила.

**Откат** (проверяемый): `sudo apt-get install nvidia-driver-595-open`
(вернёт userland+dkms), `sudo rm /lib/modules/7.0.0-38-generic/kernel/drivers/video/nvidia*.ko
/opt/nvidia-615.71.09 -r` (vanilla-модули и артефакты), удалить
`/etc/modprobe.d/nvidia-vanilla-blacklist.conf`, `sudo depmod -a
7.0.0-38-generic && sudo update-initramfs -u -k 7.0.0-38-generic`, reboot.
GRUB не менялся (проверено: `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"`),
контейнеры штатно (compose ninfer + monitoring llm-* подняты и проверены
живым запросом).
