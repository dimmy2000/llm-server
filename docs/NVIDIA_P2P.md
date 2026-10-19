# Патченный NVIDIA-драйвер и P2P между двумя RTX 5070 Ti

Ops-ранбук для нестандартного драйверного стека хоста: зачем он такой, как
жить с ним при обновлениях ядра (HWE), как проверять и как откатывать.
Обоснование решения и измеренные дельты — `docs/research/0010-p2p-two-5070ti.md`
и `.scratch/p2p-5070ti/` (тикеты 01–08).

## Текущий стек

| Компонент | Значение |
|---|---|
| Ядро | `7.0.0-38-generic` (HWE-линия `linux-*-generic-hwe-26.04`) |
| Драйвер | `615.71.09`, NVRM Open Kernel Modules |
| Модули | патченная ветка `615.71.09-p2p` (aikitoria P2P-патч), собраны на хосте |
| Источники | `/opt/nvidia-615.71.09/open-gpu-kernel-modules-615.71.09-p2p` (HEAD `c8bff54`) |
| Vanilla-исходники | `/opt/nvidia-615.71.09/open-gpu-kernel-modules-615.71.09` (тег `615.71.09`) |
| Userland/GSP | `/opt/nvidia-615.71.09/NVIDIA-Linux-x86_64-615.71.09.run` (`--no-kernel-modules`) |
| Модули в | `/lib/modules/<kernel>/kernel/drivers/video/nvidia*.ko` |
| GRUB | `amd_iommu=on iommu=pt` в `GRUB_CMDLINE_LINUX_DEFAULT` |
| CUDA-сэмплы | `/opt/nvidia-615.71.09/p2p-bin/{simpleP2P,p2pBandwidthLatencyTest}` |
| Бэкап vanilla-модулей | `/opt/nvidia-615.71.09/backup-vanilla-modules-7.0.0-38/` |
| Бэкап GRUB | `/etc/default/grub.bak-p2p-20261010` |

Драйвер установлен **не** из apt и **не** через DKMS: apt-драйвер 595.99.02
снят (тикет 03), `dkms status` пуст. Модули — результат `make modules` из
патченной ветки, поэтому их никто, кроме этого ранбука, не пересобирает.

**Ключевое следствие:** обновление HWE-ядра ставит новое ядро и его headers,
но патченные модули под него не появятся. Новое ядро загрузится **без
NVIDIA-модуля** (nouveau заблокирован), дисплей и GPU-профили не поднимутся,
пока не выполнится пересборка по разделу ниже.

Почему нельзя вернуться на apt-драйвер как основной: P2P между GeForce
официально не поддерживается, работает только с патчем; на этом стеке NInfer
tp2 даёт +18…+26 % prefill (тикет 05), llama.cpp от P2P не выигрывает, поэтому
патч нужен именно ради NInfer-профиля.

## Проверка состояния (read-only)

```bash
scripts/nvidia-p2p/p2p-snapshot.sh                 # полный дамп в stdout
scripts/nvidia-p2p/p2p-snapshot.sh /tmp/before.txt # или в файл
scripts/nvidia-p2p/p2p-verify.sh                   # pass/fail, exit != 0 при провале
```

`p2p-verify.sh` проверяет: версию драйвера, обе карты, `topo -p2p r` = OK/OK,
BAR1 16 ГиБ, `simpleP2P` без verification errors, отсутствие Xid/NVRM-ошибок в
dmesg. `p2p-snapshot.sh` дополнительно сохраняет sha256 модулей и `free` VRAM —
для сравнения до/после ребута или пересборки.

Признак рабочего P2P в логе NInfer (`docker compose logs llama-swap`, при
активном ninfer-профиле):
строка `tensor parallel | ... | p2p on` и `captured all-reduces: copies`
(вместо `p2p off (host-staged copies)` / `mailbox`).

## Обновление ядра (HWE) — политика и ранбук

**Политика: ядро не пинится, HWE обновляется штатно; после каждого
обновления ядра модули пересобираются вручную по этому ранбуку.** Ядро
фиксировать не нужно, а «само не пересоберётся» лечится не пином, а
процедурой. Пин выбран не был, потому что HWE-обновления приносят
исправления безопасности, а пересборка занимает минуты.

Порядок (после `apt upgrade`, который поставил `linux-image-<new>` и
`linux-headers-<new>-generic`):

```bash
# 1. Убедиться, что новое ядро и его headers установлены:
uname -r                                   # текущее (старое) ядро
ls /lib/modules/                           # должно появиться новое <new>
ls -d /usr/src/linux-headers-<new>-generic # headers нового ядра

# 2. Собрать и установить патченные модули под новое ядро (без ребута):
sudo scripts/nvidia-p2p/rebuild-modules.sh --kernel <new> --install

# 3. Перезагрузиться в новое ядро и проверить:
sudo reboot
# после загрузки:
uname -r
scripts/nvidia-p2p/p2p-verify.sh
```

`rebuild-modules.sh` без `--install` только собирает (можно прогнать для
проверки, что драйвер вообще компилируется под новое ядро, до установки).
Перед установкой он бэкапит уже лежащие в `/lib/modules/<kernel>/...` модули в
`/opt/nvidia-615.71.09/module-backups/<kernel>-<timestamp>/`.

## Ребут

P2P поднимается сам при загрузке: патченные модули и `iommu=pt` уже в системе,
дополнительных действий не требуется. После ребута всегда выполнять
`scripts/nvidia-p2p/p2p-verify.sh` (критерий H9: `topo -p2p r` = OK/OK и
`simpleP2P` = Test passed без ручных действий).

## Плановый откат

### Откат на vanilla-модули (без пересборки; P2P пропадает, всё остальное живо)

```bash
sudo cp /opt/nvidia-615.71.09/backup-vanilla-modules-7.0.0-38/nvidia*.ko \
        /lib/modules/7.0.0-38-generic/kernel/drivers/video/
sudo cp /etc/default/grub.bak-p2p-20261010 /etc/default/grub
sudo update-grub
sudo depmod -a 7.0.0-38-generic
sudo reboot
```

### Терминальный откат на apt-драйвер 595.99.02

```bash
sudo apt-get install nvidia-driver-595-open
sudo rm /lib/modules/7.0.0-38-generic/kernel/drivers/video/nvidia*.ko
sudo depmod -a 7.0.0-38-generic
sudo reboot
```

## Soak, мониторинг и красная линия

24-часовой прогон под нагрузкой: `scripts/nvidia-p2p/soak.sh` (см. `--help`).
Скрипт гоняет inference-нагрузку через `:8080`, раз в секунду пишет `free`
VRAM по обеим картам, ищет в dmesg `Xid`/`NVRM`/CUDA-ошибки и считает минимум
свободной VRAM GPU1.

Красная линия проекта: **под пиковой нагрузкой на дисплейной GPU1 ≥ 512 MiB
свободной VRAM**. Xid и CUDA-ошибки удобно смотреть через `soak.sh` (dmesg),
свободную VRAM — через `nvidia-smi` или тот же лог soak-а (раз в секунду
`free` VRAM по обеим картам).
