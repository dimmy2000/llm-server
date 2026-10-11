#!/usr/bin/env bash
# Verify patched-driver P2P after a reboot or kernel rebuild. Read-only except
# for running the p2p-bin CUDA samples. Exits non-zero if any check fails.
#
# Usage: p2p-verify.sh
#   EXPECT_DRIVER=615.71.09 P2P_BIN=/opt/nvidia-615.71.09/p2p-bin p2p-verify.sh
#
# See docs/NVIDIA_P2P.md.
set -uo pipefail

P2P_BIN=${P2P_BIN:-/opt/nvidia-615.71.09/p2p-bin}
EXPECT_DRIVER=${EXPECT_DRIVER:-615.71.09}
MIN_FREE_MIB=${MIN_FREE_MIB:-512}
fail=0

pass() { printf '  ok   %s\n' "$1"; }
warn() { printf '  warn %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }

echo "P2P verification ($(date -Is))"

drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
if [[ "$drv" == "$EXPECT_DRIVER" ]]; then
  pass "driver $drv"
else
  bad "driver '$drv' != expected '$EXPECT_DRIVER'"
fi

count=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | wc -l)
if [[ "$count" -eq 2 ]]; then
  pass "both GPUs visible"
else
  bad "GPU count $count (expected 2)"
fi

ok_cells=$(nvidia-smi topo -p2p r 2>/dev/null \
  | grep -E '^[[:space:]]*GPU[0-9]' | grep -c 'OK')
if [[ "$ok_cells" -eq 2 ]]; then
  pass "topo -p2p r = OK/OK"
else
  bad "topo -p2p r not OK ($ok_cells OK cells; see nvidia-smi topo -p2p r)"
fi

bar1=$(nvidia-smi -q 2>/dev/null | awk '/BAR1 Memory Usage/{f=1} f&&/Total/{print $3; exit}')
if [[ "$bar1" == "16384" ]]; then
  pass "BAR1 16384 MiB"
else
  bad "BAR1 Total = '${bar1:-?}' MiB (expected 16384)"
fi

if [[ -x "$P2P_BIN/simpleP2P" ]]; then
  out=$(cd "$P2P_BIN" && ./simpleP2P 2>&1)
  if grep -q 'Peer access.*Yes' <<<"$out" \
     && grep -q 'Test passed' <<<"$out" \
     && ! grep -qiE 'error|fail' <<<"$out"; then
    pass "simpleP2P: peer access + Test passed"
  else
    bad "simpleP2P failed; full output:"
    sed 's/^/       /' <<<"$out"
  fi
else
  warn "simpleP2P not found at $P2P_BIN/simpleP2P (skipped)"
fi

dm=$(dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || true)
if [[ -n "$dm" ]]; then
  errs=$({ grep -E 'Xid \(' <<<"$dm"; \
           grep -iE 'cuda error|nvrm.*(error|fail)' <<<"$dm"; } || true)
  if [[ -z "$errs" ]]; then
    pass "dmesg: no Xid / CUDA / NVRM errors since boot"
  else
    bad "dmesg errors:"
    sed 's/^/       /' <<<"$errs"
  fi
else
  warn "dmesg not readable (re-run with sudo for the Xid check)"
fi

free1=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | sed -n '2p')
if [[ -n "$free1" ]]; then
  if [[ "$free1" -ge "$MIN_FREE_MIB" ]]; then
    pass "GPU1 free ${free1} MiB (idle, >= ${MIN_FREE_MIB})"
  else
    warn "GPU1 free ${free1} MiB < ${MIN_FREE_MIB} (idle; red line is under load)"
  fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
exit "$fail"
