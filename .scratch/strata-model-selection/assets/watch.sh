#!/bin/sh
# Watch script per run-matrix protocol: RAM/swap/VRAM(both GPUs)/NVMe-read rate every 2 s.
# Usage: watch.sh <outfile> [interval]
out=${1:?output file required}
iv=${2:-2}
prev_disk=0
prev_t=0
if [ ! -s "$out" ]; then
    echo "ts\tgpu0_free_MiB\tgpu1_free_MiB\tram_avail_MiB\tswap_used_MiB\tnvme_read_MBps" > "$out"
else
    printf 'restarted\t%s\theader-lines %s\n' "$(date -u +%FT%TZ)" "$(wc -l < "$out")" >> "$out"
fi
while :; do
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    g0=$(nvidia-smi -i 0 --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null)
    g1=$(nvidia-smi -i 1 --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null)
    ram=$(free -k | awk 'NR==2{printf "%.0f", $7/1024}')
    sw=$(free -k | awk 'NR==3{printf "%.0f", $3/1024}')
    rd=$(awk '/nvme/{s+=$6} END{print s+0}' /proc/diskstats)
    now=$(date +%s.%N)
    if [ "$prev_t" != "0" ]; then
        rate=$(awk -v r="$rd" -v p="$prev_disk" -v t="$now" -v pt="$prev_t" 'BEGIN{printf "%.1f", (r-p)*512/1048576/(t-pt)}')
    else
        rate=0.0
    fi
    prev_disk=$rd
    prev_t=$now
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$g0" "$g1" "$ram" "$sw" "$rate" >> "$out"
    sleep "$iv"
done
