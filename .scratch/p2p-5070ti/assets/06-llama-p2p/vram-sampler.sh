#!/usr/bin/env bash
# VRAM sampler: epoch, gpu0_used, gpu0_util%|gpu1_used, gpu1_util%
# Usage: vram-sampler.sh <csv-out> &  ... kill %1 after the run
OUT="${1:?usage: vram-sampler.sh <csv-out>}"
while true; do
  line=$(nvidia-smi --query-gpu=index,memory.used,utilization.gpu \
    --format=csv,noheader,nounits 2>/dev/null \
    | awk -F', ' '{printf "%s, %s, %s", $1, $2, $3; if (NR==1) printf "|"}')
  echo "$(date +%s),${line}" >> "$OUT"
  sleep 1
done
