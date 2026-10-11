#!/usr/bin/env bash
# Rebuild (and optionally install) the patched aikitoria P2P NVIDIA kernel
# modules for a target kernel.
#
# The host runs driver 615.71.09 with the "p2p" patch, built from source and
# NOT via DKMS. An HWE kernel update therefore leaves the new kernel without a
# loadable nvidia module until these are rebuilt for it. See docs/NVIDIA_P2P.md.
#
# Usage:
#   rebuild-modules.sh                        # build for the running kernel
#   rebuild-modules.sh -k 7.0.0-40-generic    # build for another kernel
#   sudo rebuild-modules.sh -k 7.0.0-40-generic --install
#
# Requires the target kernel's headers (/lib/modules/<kver>/build).
set -euo pipefail

SRC=${SRC:-/opt/nvidia-615.71.09/open-gpu-kernel-modules-615.71.09-p2p}
BACKUP_ROOT=${BACKUP_ROOT:-/opt/nvidia-615.71.09/module-backups}
KVER=$(uname -r)
DO_INSTALL=0
JOBS=$(nproc)

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--kernel) KVER=$2; shift 2 ;;
    --install)   DO_INSTALL=1; shift ;;
    --src)       SRC=$2; shift 2 ;;
    -j|--jobs)   JOBS=$2; shift 2 ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
done

[[ -d "$SRC/kernel-open" ]] || die "source tree not found: $SRC"
[[ -d "/lib/modules/$KVER/build" ]] \
  || die "no headers for $KVER (install linux-headers-$KVER)"

if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "source: $SRC @ $(git -C "$SRC" rev-parse --short HEAD) ($(git -C "$SRC" rev-parse --abbrev-ref HEAD))"
fi
echo "target kernel: $KVER"
echo "jobs: $JOBS"

echo "== build =="
make -C "$SRC" modules -j"$JOBS" KERNEL_UNAME="$KVER"

if [[ "$DO_INSTALL" -eq 0 ]]; then
  echo
  echo "build ok. re-run with --install to install into /lib/modules/$KVER"
  exit 0
fi

[[ $EUID -eq 0 ]] || die "--install requires root (use sudo)"

MODDIR="/lib/modules/$KVER/kernel/drivers/video"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$BACKUP_ROOT/$KVER-$STAMP"
mkdir -p "$BACKUP"
if compgen -G "$MODDIR/nvidia*.ko" >/dev/null; then
  cp -a "$MODDIR"/nvidia*.ko "$BACKUP/"
  echo "backed up existing modules -> $BACKUP"
fi

echo "== install =="
make -C "$SRC" modules_install KERNEL_UNAME="$KVER"
depmod -a "$KVER"

echo "== installed =="
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem; do
  f=$(find "/lib/modules/$KVER" -name "$m.ko" -print -quit 2>/dev/null || true)
  if [[ -n "$f" ]]; then
    printf '  %s  %s\n' "$(modinfo -F vermagic "$f" 2>/dev/null)" "$f"
  else
    echo "  MISSING: $m.ko"
  fi
done

echo
echo "install ok. reboot into $KVER, then run scripts/nvidia-p2p/p2p-verify.sh"
