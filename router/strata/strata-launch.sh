#!/bin/sh
# Лаунчер движка Strata для `cmd` llama-swap (ADR-0008).
#
# llama-swap исполняет cmd БЕЗ shell (shlex-сплит, exec.CommandContext), поэтому
# RAM-гейт живёт здесь: при нехватке MemAvailable — мгновенный отказ с причиной
# (fail fast, без ретраев, решение 08). При проходе — exec server.py: движок
# становится тем же PID, что трекает llama-swap (SIGTERM = graceful QUIT).
#
# argv: 1 — порог MemAvailable в KiB (46 GiB iq3 / 36 GiB iq2, унаследовано от
# strata-use.sh); 2 — путь к контейнерному конфигу; 3 — HTTP-порт (из ${PORT}).
#
# Весов касается не этот скрипт, а маунты compose: /opt/strata/{models,packs,
# mtp,data} — RO по абсолютным путям конфига.
set -eu

need=$1
config=$2
port=$3

avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
if [ "$avail" -lt "$need" ]; then
    echo "strata: RAM gate: need $((need / 1024 / 1024))GiB, MemAvailable $((avail / 1024))MiB — резидентный бэкенд не выгружен или память занята посторонними" >&2
    exit 1
fi

cd /opt/strata
exec /opt/strata/.venv/bin/python /opt/strata/serve/server.py --engine strata --config "$config" --port "$port"
