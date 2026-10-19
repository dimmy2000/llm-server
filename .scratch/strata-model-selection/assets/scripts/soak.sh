#!/bin/sh
# Soak-сценарий протокола (issues/06 §4.7): 3 холодных старта модели + полный цикл
# переключений XXS→S→XS→стоп. Запускается когда жилой сервер остановлен.
# Использование: soak.sh <log-file> [model-tags...]  (default: iq3_xxs для стартов, потом цикл xxs s xs)
out=${1:?log file}
cd /opt/strata || exit 1
stamp() { date -u +%FT%TZ; }
ram_snapshot() { free -k | awk 'NR==2{printf "ram_avail_MiB=%.0f ", $7/1024} NR==3{printf "swap_used_MiB=%.0f", $3/1024}'; }

say() { printf '%s %s %s\n' "$(stamp)" "$1" "$(ram_snapshot)" | tee -a "$out"; }

wait_ready() {  # $1 port, $2 timeout
    n=$((($2 + 3) / 4))
    k=1
    while [ "$k" -le "$n" ]; do
        if curl -s -m 3 "http://127.0.0.1:$1/health" | grep -q '"status": "ok"'; then return 0; fi
        sleep 4
        k=$((k + 1))
    done
    return 1
}

stop_all() { pkill -f 'serve/server.py --engine strata' 2>/dev/null; sleep 8; }

say "soak start: 3 cold starts + switch cycle"

for i in 1 2 3; do
    stop_all
    t0=$(date +%s)
    setsid nohup .venv/bin/python serve/server.py --engine strata --config /opt/strata/strata-iq3_xxs.json --port 8081 </dev/null > /dev/null 2>&1 &
    if wait_ready 8081 600; then
        t1=$(date +%s)
        say "cold_start_$i: READY in $((t1 - t0)) s"
    else
        say "cold_start_$i: FAILED (нет health за 600 c)"
    fi
done

# полный цикл переключений
for tag in iq2_xs iq3_s iq3_xxs; do
    stop_all
    t0=$(date +%s)
    setsid nohup .venv/bin/python serve/server.py --engine strata --config "/opt/strata/strata-$tag.json" --port 8081 </dev/null > /dev/null 2>&1 &
    if wait_ready 8081 900; then
        t1=$(date +%s)
        say "switch_cycle $tag: READY in $((t1 - t0)) s"
    else
        say "switch_cycle $tag: FAILED"
    fi
done

stop_all
sleep 5
say "soak end (все остановлены)"
