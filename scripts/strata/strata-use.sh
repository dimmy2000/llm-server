#!/usr/bin/env bash
#
# strata-use.sh — ЕДИНСТВЕННАЯ ТОЧКА ПРАВДЫ переключения ролей инференса.
#
#   strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}
#
#   llama|ninfer   — остановить юнит strata (добить дерево, дождаться
#                    освобождения VRAM/RAM) → PUT /api/profiles/active.
#                    Движок родителя стартует на первом запросе (manual
#                    regime llama-swap; профиль НЕ грузит движок сам).
#   strata-iq3|…   — нативный Strata нужного размера: останов юнита,
#                    unload родительского бэкенда через API llama-swap
#                    (оба движка + shim-процессы; RAM-гигиена llama.cpp
#                    --cache-ram 40960), проверить запас RAM, поставить
#                    симлинк /etc/strata/active.json, старт юнита, ждать
#                    /health на :8081 с НУЖНЫМ model (дискриминатор
#                    размера) и loaded==true, затем PUT профиль.
#                    ПОРЯДОК ОБЯЗАТЕЛЕН (тикет 01): unload родителя →
#                    юнит → /health → профиль; иначе OOM VRAM.
#   off            — остановить юнит, выставить дефолт-профиль ninfer
#                    (hooks on_startup в router/config.yaml; подтверждено).
#                    Родительский движок принудительно не стартует —
#                    просто доступность через профиль.
#
# Защита от рассинхрона: перед стартом юнита проверяется симлинк конфига;
# после — /health.model == ожидаемого native-ID и loaded==true; профиль
# ставится ТОЛЬКО после этого. Если юнит уже работает с другим размером —
# корректный рестарт на нужную конфигурацию (на рассинхроне не работаем).
#
# Коды выхода: 0 ок; 1 неверный аргумент; 2 ошибка API/профиля;
# 3 юнит strata не установлен; 4 дерево Strata не добито;
# 5 RAM-гигиена (запас памяти после unload родителя не достигнут);
# 6 таймаут /health нужного размера; 7 VRAM не освободилась после юнита.
#
# Сырьё/обоснования: .scratch/strata-integration/ (map.md, issues/01/02).

set -euo pipefail

ROUTER="http://localhost:8080"
HEALTH_URL="http://172.17.0.1:8081/health"
UNIT="strata"
ACTIVE_LINK="/etc/strata/active.json"
STOP_HELPER="/usr/local/sbin/strata-stop"
HEALTH_TIMEOUT=300    # холодного ожидания /health (прогрев страницы экспертов ~20-30 c)
FREEDOM_TIMEOUT=60    # ожидания исчезновения процессов/VRAM Strata
RAM_TIMEOUT=90        # ожидания освобождения RAM после unload родителя

# Размер → конфиг / native-ID / нижняя граница available RAM (MiB) перед стартом.
# RAM-порог: на живом стеке после unload родителя доступно ~50 ГиБ; страница-
# locked эксперты IQ3_XXS ~47 ГиБ, IQ2_XS ~36 ГиБ (тикет 01). Порог ниже
# типичного свободного, но много выше «родитель не выгружен» (~10 ГиБ).
declare -A ST_CONFIG=(
  [strata-iq3]="/opt/strata/strata-iq3_xxs.json"
  [strata-iq2]="/opt/strata/strata-iq2_xs.json"
)
declare -A ST_MODEL=(
  [strata-iq3]="qwen3.8-flash-next-iq3_xxs"
  [strata-iq2]="qwen3.8-flash-next-iq2_xs"
)
declare -A ST_RAM_MIB=(
  [strata-iq3]=46000
  [strata-iq2]=36000
)
DEFAULT_PROFILE="ninfer"
GPU_RED_LINE_MIB=512   # дисплейная GPU1 — красная линия проекта
PROC_RE='/opt/strata/(serve/server\.py|engine/strata)'   # server.py + движок + strata-vision

TS() { date '+%H:%M:%S'; }
log() { echo "[strata-use] $(TS) $*"; }
die() { echo "[strata-use] $(TS) ERROR: $*" >&2; exit "$1"; }

# --- API llama-swap (:8080) --------------------------------------------------

api_up() {
  curl -sfm 10 "$ROUTER/api/profiles" >/dev/null \
    || die 2 "llama-swap не отвечает на $ROUTER/api/profiles"
}

profile_active() { curl -sfm 10 "$ROUTER/api/profiles" | jq -r '.active'; }

set_profile() {                 # $1 = имя профиля
  local p="$1" got
  curl -sfm 30 -X PUT "$ROUTER/api/profiles/active" \
       -H 'Content-Type: application/json' -d "{\"name\":\"$p\"}" >/dev/null \
    || die 2 "PUT /api/profiles/active name=$p не удался"
  got="$(profile_active)"
  [[ "$got" == "$p" ]] || die 2 "профиль после PUT: '$got', ожидался '$p'"
  log "профиль llama-swap: активен '$p'"
}

unload_all() {                  # остановить ВСЕ процессы-модели llama-swap (родители + shims)
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 30 -X POST "$ROUTER/api/models/unload" || true)"
  case "$code" in
    2??) log "llama-swap: unload всех моделей (родительский стек, shims) — принято" ;;
    *)   die 2 "POST /api/models/unload → HTTP $code" ;;
  esac
}

# --- Процессы/VRAM/RAM нативной Strata --------------------------------------

strata_procs() { pgrep -f "$PROC_RE" 2>/dev/null || true; }

unit_installed() { systemctl cat "$UNIT" >/dev/null 2>&1; }
unit_active()   { systemctl is-active --quiet "$UNIT" 2>/dev/null; }

# RAM available (MiB)
ram_avail_mib() { free -m | awk '/^Mem:/{print $7}'; }

# Суммарно свободной VRAM по картам (MiB) + строка по картам для лога
vram_report() {
  nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits \
    | awk -F', ' -v rl="$GPU_RED_LINE_MIB" '
      { a[$1]=$2; n++ }
      END {
        s="";
        for (i=0; i<n; i++) {
          if (s != "") s = s " | ";
          s = s "GPU" i " free " a[i] " MiB";
          if (a[i]+0 < rl+0) s = s " (!! НИЖЕ КРАСНОЙ ЛИНИИ " rl " MiB)";
        }
        print s;
      }'
}

vram_has_strata() {          # 0 — процесс strata/движка ещё виден nvidia-smi'у
  nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null \
    | grep -q -i 'strata'
}

stop_strata() {              # остановить юнит и ДОБИТЬ дерево; дождаться отсутствия
  if unit_active; then
    log "останов юнита $UNIT…"
    systemctl stop "$UNIT" || { "$STOP_HELPER" || die 4 "systemctl stop упал, добивание тоже не очистило дерево"; }
  fi
  # страховка: юнит мог не двигать процессы или их нет — гоняем helper всегда
  if pgrep -f "$PROC_RE" >/dev/null 2>&1; then
    log "остались процессы Strata — добивание через helper"
    "$STOP_HELPER" || die 4 "дерево Strata не добито (helper exit 4)"
  fi
  local t="${FREEDOM_TIMEOUT}"
  while [[ $t -gt 0 ]]; do
    [[ -z "$(strata_procs)" ]] || { sleep 1; t=$((t-1)); continue; }
    # nvidia-smi: убедиться, что движок вылетел из списка compute-процессов
    if ! vram_has_strata; then
      sleep 2   # драйверу время отпустить VRAM
      log "VRAM Strata освобождена: $(vram_report)"
      return 0
    fi
    sleep 1; t=$((t-1))
  done
  die 7 "процессы Strata исчезли, но nvidia-smi всё ещё видит их — VRAM не освободилась за ${FREEDOM_TIMEOUT}s"
}

wait_ram() {                 # $1 = порог MiB
  local need="$1" t="${RAM_TIMEOUT}" have
  while [[ $t -gt 0 ]]; do
    have="$(ram_avail_mib)"
    if [[ "$have" -ge "$need" ]]; then
      log "RAM available ${have} MiB ≥ порог ${need} MiB — родительский стек не держит idle-cache"
      return 0
    fi
    sleep 2; t=$((t-2))
  done
  have="$(ram_avail_mib)"
  die 5 "RAM available ${have} MiB < порог ${need} MiB после unload родителя — idle-cache не освободился. Проверь /api/profiles и процессы llama-server/ninfer; если активный unload не освобождает RAM — эскалация: fog-пункт карты «RAM-баланс» (эскалируй в тикет)"
}

# ---
# --- /health нативного движка ------------------------------------------------

health_body() { curl -sfm 5 "$HEALTH_URL" 2>/dev/null || true; }

# 0 — /health отвечает и совпадает с ожидаемым размером и готов
health_match() {              # $1 = ожидаемый native model
  local body
  body="$(health_body)"
  [[ -n "$body" ]] || return 1
  health_res="$(jq -e --arg m "$1" '
      .status=="ok" and .model==$m and .loaded==true
    ' <<<"$body" >/dev/null 2>&1 && echo ok || echo no)"
  [[ "$health_res" == "ok" ]]
}

wait_health() {               # $1 = ожидаемый native model
  local want="$1" t=0 t0=$SECONDS
  while [[ $t -lt $HEALTH_TIMEOUT ]]; do
    if health_match "$want"; then
      log "/health :8081 → model=$want loaded=true (за $((SECONDS-t0)) с)"
      return 0
    fi
    sleep 2; t=$((SECONDS-t0))
  done
  local got
  got="$(jq -r '.model? // "?"' <<<"$(health_body)" 2>/dev/null || echo 'нет ответа')"
  die 6 "таймаут ${HEALTH_TIMEOUT}s на /health с model=$want (сейчас: '$got'; journald -u strata)"
}

ensure_link() {               # $1 = конфиг, $2 = ожидаемая цель симлинка
  if [[ "$(readlink -f "$ACTIVE_LINK" 2>/dev/null || true)" != "$1" ]]; then
    mkdir -p "$(dirname "$ACTIVE_LINK")"
    ln -sfn "$1" "$ACTIVE_LINK.tmp.$$"
    mv -f "$ACTIVE_LINK.tmp.$$" "$ACTIVE_LINK"
    log "симлинк $ACTIVE_LINK → $1"
  fi
  [[ "$(readlink -f "$ACTIVE_LINK" 2>/dev/null || true)" == "$1" ]] \
    || die 3 "$ACTIVE_LINK не указывает на $1"
}

# --- Переходы ----------------------------------------------------------------

to_strata() {                 # $1 = strata-iq3|strata-iq2
  local target="$1" cfg="${ST_CONFIG[$1]}" model="${ST_MODEL[$1]}"
  local already=0

  # идемпотентный no-op: юнит уже с нужным размером и профиль уже нужный
  if unit_active && [[ "$(readlink -f "$ACTIVE_LINK" 2>/dev/null || true)" == "$cfg" ]] \
     && health_match "$model" && [[ "$(profile_active)" == "$target" ]]; then
    log "уже активен $target (юнит жив, /health совпадает, профиль выставлен) — no-op"
    log "$(vram_report); RAM available $(ram_avail_mib) MiB"
    return 0
  fi

  log "переход на $target (конфиг $(basename "$cfg"))"
  stop_strata                 # юнит мог портить VRAM чужим размером/быть мёртвым
  unload_all                  # RAM-гигиена: llama.cpp --cache-ram и RESVRAM родителя
  wait_ram "${ST_RAM_MIB[$1]}"
  ensure_link "$cfg" "$target"

  log "старт юнита $UNIT (systemctl start; автостарт disabled)…"
  systemctl start "$UNIT" || die 3 "systemctl start $UNIT не удался (см. journalctl -u strata)"
  wait_health "$model"
  set_profile "$target"
  log "$(vram_report); RAM available $(ram_avail_mib) MiB"
  log "ГОТОВО: $target — доступен через llama-swap :8080 (публичный ID '$target')"
}

to_parent() {                 # $1 = llama|ninfer
  local p="$1"
  if ! unit_active && [[ -z "$(strata_procs)" ]] && [[ "$(profile_active)" == "$p" ]]; then
    log "уже активен профиль '$p', юнит strata не запущен — no-op"
    return 0
  fi
  log "переход на родительский '$p'"
  stop_strata
  set_profile "$p"
  log "$(vram_report); RAM available $(ram_avail_mib) MiB"
  log "ГОТОВО: '$p' — движок загрузится на первом запросе к qwen3.8-27b"
}

do_off() {
  if ! unit_active && [[ -z "$(strata_procs)" ]] && [[ "$(profile_active)" == "$DEFAULT_PROFILE" ]]; then
    log "уже off (юнит не запущен, профиль дефолтного '$DEFAULT_PROFILE') — no-op"
    return 0
  fi
  log "off: останов юнита, дефолт-профиль '$DEFAULT_PROFILE' (hooks on_startup), движок не стартую"
  stop_strata
  set_profile "$DEFAULT_PROFILE"
  log "$(vram_report)"
  log "ГОТОВО: off — доступность родителя через профиль '$DEFAULT_PROFILE' по первому запросу"
}

# --- main --------------------------------------------------------------------

usage() { echo "usage: strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}"; }

if [[ $# -ne 1 ]]; then
  usage; exit 1
fi

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$0" "$@"   # нужен для systemctl и прав на /etc (sudo -n passwordless на этой машине)
fi

unit_installed || die 3 "юнит $UNIT не установлен: см. scripts/strata/strata.service (симлинки /etc/systemd/system + /usr/local/sbin/strata-stop, daemon-reload)"
[[ -x "$STOP_HELPER" ]] || die 3 "нет исполняемого $STOP_HELPER (симлинк на scripts/strata/strata-stop)"
api_up

case "$1" in
  llama|ninfer)        to_parent "$1" ;;
  strata-iq3|strata-iq2)
    [[ -f "${ST_CONFIG[$1]}" ]] || die 3 "конфиг ${ST_CONFIG[$1]} не найден (движок менял тикет 01, скрипт конфиги не правит)"
    to_strata "$1" ;;
  off)                 do_off ;;
  *)                   usage; die 1 "неизвестный аргумент '$1'" ;;
esac
