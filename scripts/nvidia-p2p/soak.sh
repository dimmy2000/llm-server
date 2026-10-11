#!/usr/bin/env bash
# 24h P2P soak: sustained inference load + VRAM / error monitoring.
#
# Drives the OpenAI endpoint on :8080 (whichever profile is up), samples free
# VRAM on both GPUs every second, watches dmesg for Xid / NVRM / CUDA errors,
# and reports the minimum free VRAM on the display GPU (red line: >= 512 MiB).
#
# Usage:
#   scripts/nvidia-p2p/soak.sh --hours 24 --outdir /tmp/soak-p2p
#   scripts/nvidia-p2p/soak.sh --hours 0.02 --outdir /tmp/smoke   # quick check
#
# Run it detached for a real soak, e.g.:
#   nohup scripts/nvidia-p2p/soak.sh --hours 24 --outdir ~/soak-p2p >/dev/null 2>&1 &
#
# Options:
#   --hours N         duration in hours, fractional ok (default 24)
#   --outdir DIR      artifact dir (default soak-<timestamp>)
#   --host H --port P endpoint (default 127.0.0.1:8080)
#   --model ID        model id (default qwen3.8-27b)
#   --decode-tokens N tokens per decode request (default 256)
#   --long-prompt F   prompt file for periodic long prefill (optional)
#   --long-every N    seconds between long prefills (default 3600)
#   --min-free MiB    red line for GPU1 (default 512)
#
# See docs/NVIDIA_P2P.md.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOURS=24
OUTDIR=""
HOST=127.0.0.1
PORT=8080
MODEL=qwen3.8-27b
DECODE_TOKENS=256
LONG_PROMPT=""
LONG_EVERY=3600
MIN_FREE=512

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)         HOURS=$2; shift 2 ;;
    --outdir)        OUTDIR=$2; shift 2 ;;
    --host)          HOST=$2; shift 2 ;;
    --port)          PORT=$2; shift 2 ;;
    --model)         MODEL=$2; shift 2 ;;
    --decode-tokens) DECODE_TOKENS=$2; shift 2 ;;
    --long-prompt)   LONG_PROMPT=$2; shift 2 ;;
    --long-every)    LONG_EVERY=$2; shift 2 ;;
    --min-free)      MIN_FREE=$2; shift 2 ;;
    -h|--help)       grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               die "unknown argument: $1" ;;
  esac
done

[[ -n "$OUTDIR" ]] || OUTDIR="soak-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
BENCH="$HERE/bench.py"
[[ -f "$BENCH" ]] || die "bench.py not found next to soak.sh ($BENCH)"

DURATION_S=$(awk -v h="$HOURS" 'BEGIN{printf "%d", h*3600}')
NOW=$(date +%s)
DEADLINE=$((NOW + DURATION_S))
VRAM_CSV="$OUTDIR/vram.csv"
ROUNDS_LOG="$OUTDIR/rounds.log"
ERRORS_LOG="$OUTDIR/errors.log"

echo "soak start $(date -Is)"
echo "  dir:      $OUTDIR"
echo "  duration: ${HOURS}h (${DURATION_S}s)"
echo "  endpoint: http://$HOST:$PORT  model=$MODEL  decode-tokens=$DECODE_TOKENS"
echo "  long prefill: ${LONG_PROMPT:-none} every ${LONG_EVERY}s"
echo "  red line:   GPU1 free >= ${MIN_FREE} MiB"

# Build a large-but-bounded prompt so the request is real decode load, not a
# trivial completion. The model id selects thinking/instruct mode server-side.
DECODE_PROMPT="Write a long, detailed technical essay (several sections) about alpine railway engineering, tourism and politics. Do not stop early; target at least ${DECODE_TOKENS} tokens."

sample_vram() {
  while :; do
    local row
    row=$(nvidia-smi --query-gpu=memory.free,memory.used,utilization.gpu \
      --format=csv,noheader,nounits 2>/dev/null | paste -sd, -)
    [[ -n "$row" ]] && echo "$(date +%s),$row" >> "$VRAM_CSV"
    sleep 1
  done
}
sample_vram &
SAMPLER=$!
trap 'kill "$SAMPLER" 2>/dev/null' EXIT

check_errors() {
  local dm
  dm=$(dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || true)
  [[ -z "$dm" ]] && return 0
  { grep -E 'Xid \(' <<<"$dm"; grep -iE 'cuda error|nvrm.*(error|fail)' <<<"$dm"; } \
    | sed "s/^/$(date -Is) /" >> "$ERRORS_LOG" 2>/dev/null || true
}

alive() {
  curl -fsS -o /dev/null -m 10 "http://$HOST:$PORT/health" 2>/dev/null && return 0
  curl -fsS -o /dev/null -m 10 "http://$HOST:$PORT/v1/models" 2>/dev/null && return 0
  return 1
}

rounds_ok=0
rounds_fail=0
next_long=$NOW

while [[ $(date +%s) -lt $DEADLINE ]]; do
  tag="decode $(date +%Y%m%d-%H%M%S)"
  if python3 "$BENCH" --host "$HOST" --port "$PORT" --model "$MODEL" \
       --prompt "$DECODE_PROMPT" --max-tokens "$DECODE_TOKENS" \
       --out "$OUTDIR/last.json" --label "$tag" >> "$ROUNDS_LOG" 2>&1; then
    rounds_ok=$((rounds_ok + 1))
  else
    rounds_fail=$((rounds_fail + 1))
    echo "$tag FAILED" >> "$ROUNDS_LOG"
  fi

  if [[ -n "$LONG_PROMPT" && $(date +%s) -ge $next_long ]]; then
    tag="prefill $(date +%Y%m%d-%H%M%S)"
    if python3 "$BENCH" --host "$HOST" --port "$PORT" --model "$MODEL" \
         --prompt-file "$LONG_PROMPT" --max-tokens 4 \
         --out "$OUTDIR/last-prefill.json" --label "$tag" >> "$ROUNDS_LOG" 2>&1; then
      rounds_ok=$((rounds_ok + 1))
    else
      rounds_fail=$((rounds_fail + 1))
      echo "$tag FAILED" >> "$ROUNDS_LOG"
    fi
    next_long=$(( $(date +%s) + LONG_EVERY ))
  fi

  check_errors
  alive || echo "$(date -Is) endpoint not responding" >> "$ERRORS_LOG"
  sleep 2
done

kill "$SAMPLER" 2>/dev/null
wait "$SAMPLER" 2>/dev/null

min_free_g0=$(awk -F, 'NR>1 && (m=="" || $2<m){m=$2} END{print m+0}' "$VRAM_CSV" 2>/dev/null)
min_free_g1=$(awk -F, 'NR>1 && (m=="" || $5<m){m=$5} END{print m+0}' "$VRAM_CSV" 2>/dev/null)
err_unique=$(sort -u "$ERRORS_LOG" 2>/dev/null | wc -l)

{
  echo
  echo "=== soak summary $(date -Is) ==="
  echo "duration requested: ${HOURS}h"
  echo "rounds ok:          $rounds_ok"
  echo "rounds failed:      $rounds_fail"
  echo "vram samples:       $(wc -l < "$VRAM_CSV" 2>/dev/null)"
  echo "min free GPU0:      ${min_free_g0} MiB"
  echo "min free GPU1:      ${min_free_g1} MiB"
  echo "red line GPU1:      >= ${MIN_FREE} MiB -> $([[ ${min_free_g1:-0} -ge $MIN_FREE ]] && echo HOLD || echo BREACH)"
  echo "distinct errors:    $err_unique"
  [[ "$err_unique" -gt 0 ]] && sort -u "$ERRORS_LOG" | sed 's/^/  /'
} | tee "$OUTDIR/summary.txt"
