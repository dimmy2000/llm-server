# Финальное состояние стека после тикета 03 (2026-10-19T13:08:36Z)

- Переключения весь тикет — только через strata-use.sh: strata-iq3 → strata-iq2 →
  strata-iq3 → ninfer (возврат в исходное состояние).

```
GET /api/profiles (active):
{
  "active": "ninfer"
}
GET /v1/models:
qwen3.8-27b
strata-iq2
strata-iq3
systemctl is-active strata: inactive
strata процессы (pgrep): 471309 471319
free -m Mem:
  total 60857  / used 7400  / available 53457 MiB
nvidia-smi free VRAM:
  GPU0: 1201 MiB
  GPU1: 711 MiB
docker llama-swap: Up 17 minutes (healthy)
```

## Допроверка (сразу после снапшота)

- Указанные pgrep'ом PID 471309/471319 — самообхват: pgrep -f поймал собственную
  команду оболочки (строка с 'opt/strata' была в ней). Проверка `ps -p
  471309,471319` — PID отсутствуют; повторный pgrep по
  'serve/server\.py --engine|engine/strata' пуст; `systemctl is-active strata` →
  inactive. Процессов Strata нет.
- `/etc/strata/active.json` → `/opt/strata/strata-iq3_xxs.json` — симлинк от
  последнего страта-окна (нормальное состояние: юнит не активен; следующий
  strata-use.sh поставит симлинк нужного размера сам).
- GPU1 711 MiB свободно — это исходная точка «профиль ninfer без загруженного
  движка» (движок стартует по первому запросу; под загруженным Strata замеры
  окна: GPU1 1671–1707 МиБ, всегда выше красной линии 512 МиБ).
