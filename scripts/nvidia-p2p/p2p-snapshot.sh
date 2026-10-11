#!/usr/bin/env bash
# Full system + P2P state dump for before/after comparison across reboots,
# driver changes and kernel rebuilds. Read-only.
#
# Usage: p2p-snapshot.sh [outfile]      (default: stdout)
#
# See docs/NVIDIA_P2P.md.
set -uo pipefail

OUT="${1:-}"
if [[ -n "$OUT" ]]; then
  exec > >(tee "$OUT") 2>&1
fi

P2P_BIN=${P2P_BIN:-/opt/nvidia-615.71.09/p2p-bin}
KVER=$(uname -r)

sec() { printf '\n=== %s ===\n' "$1"; }

sec "p2p-snapshot $(date -Is)"
echo "kernel:  $KVER"
echo "cmdline: $(cat /proc/cmdline)"

sec "driver"
nvidia-smi --query-gpu=index,name,driver_version,memory.used,memory.total,memory.free \
  --format=csv,noheader 2>&1

sec "modinfo nvidia"
modinfo nvidia 2>&1 | grep -E '^(filename|version|vermagic):'

sec "installed modules ($KVER)"
ls -l "/lib/modules/$KVER/kernel/drivers/video/"nvidia*.ko 2>&1
sha256sum "/lib/modules/$KVER/kernel/drivers/video/"nvidia*.ko 2>&1

sec "topo -p2p r"
nvidia-smi topo -p2p r 2>&1
sec "topo -p2p w"
nvidia-smi topo -p2p w 2>&1

sec "BAR1"
nvidia-smi -q 2>/dev/null | grep -A3 'BAR1 Memory Usage'

sec "iommu groups"
printf 'groups: %s\n' "$(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l)"

sec "dmesg nvidia/iommu/xid (tail)"
if dmesg >/dev/null 2>&1; then
  dmesg | grep -iE 'nvrm|nvidia|iommu|xid' | grep -vE 'XID [0-9a-f]+' | tail -40
else
  sudo -n dmesg 2>/dev/null | grep -iE 'nvrm|nvidia|iommu|xid' \
    | grep -vE 'XID [0-9a-f]+' | tail -40 \
    || echo "(dmesg restricted; run with sudo for this section)"
fi

sec "containers"
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>&1

if [[ -x "$P2P_BIN/simpleP2P" ]]; then
  sec "simpleP2P"
  (cd "$P2P_BIN" && ./simpleP2P 2>&1)
fi

sec "end"
