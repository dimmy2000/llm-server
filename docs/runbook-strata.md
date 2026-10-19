# Runbook: Strata — аварийное ручное переключение ролей

Нормальный путь переключения ролей — **только**
`scripts/strata/strata-use.sh {llama|ninfer|strata-iq3|strata-iq2|off}`
(нуль ручных шагов; подробности — `scripts/strata/README.md`, ADR-0007).
Этот ранбук — аварийный путь руками, когда скрипт недоступен или отказал
(коды выхода 1–7: см. шапку скрипта). Порядок шагов нарушать нельзя:
при резидентном родительском движке старт Strata падает OOM VRAM.

Константы: llama-swap `:8080`; нативная Strata `172.17.0.1:8081`
(bind docker0 — с LAN не виден); юнит `strata` (linked, НЕ enabled,
`Restart=no`); симлинк конфига `/etc/strata/active.json`; RAM-гейты
46 ГиБ (iq3) / 36 ГиБ (iq2); красная линия VRAM — ≥ 512 MiB на дисплейной
GPU1. Native-ID для `/health`: `qwen3.8-flash-next-iq3_xxs` /
`qwen3.8-flash-next-iq2_xs`.

## Переход с Strata на родителя (llama | ninfer)

1. Убедиться, что текущие генерации завершились.
2. Остановить юнит и дождаться добивания дерева:

   ```bash
   sudo systemctl stop strata
   # ExecStop (strata-stop) TERM → ≤10 c → KILL всё дерево (server.py,
   # engine/strata, strata-vision); TimeoutStopSec=25.
   ```

3. Дождаться ухода процессов и VRAM (до 60 c):

   ```bash
   pgrep -af 'opt/strata/(serve/server|engine/strata)'          # пусто
   nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader
   # строк со strata быть не должно; после ухода подождать ~2 c —
   # драйвер отпускает VRAM. Если процессы висят: /usr/local/sbin/strata-stop
   ```

4. Выставить профиль:

   ```bash
   curl -X PUT http://localhost:8080/api/profiles/active \
        -H 'Content-Type: application/json' -d '{"name":"ninfer"}'  # или "llama"
   curl -s http://localhost:8080/api/profiles | jq -r .active
   ```

5. Движок родителя стартует на **первом запросе** к `qwen3.8-27b`
   (llama.cpp 40–60 c, NInfer ~6 c; при `sendLoadingState: false` запрос
   молчит — индикатор только в логах контейнера). Прогреть при желании
   коротким запросом.

## Переход на Strata (iq3 | iq2) — вручную

1. Убедиться, что генерации завершились; запомнить активный профиль
   (`curl -s http://localhost:8080/api/profiles | jq -r .active`).
2. Остановить родительский бэкенд и освободить RAM — `POST
   /api/models/unload` = unload-all (оба родительских бэкенда + shim-процессы,
   идемпотентно): убивает процесс родителя, page-locked RAM (47/36 ГиБ)
   уходит за секунды:

   ```bash
   curl -X POST http://localhost:8080/api/models/unload
   ```

3. RAM-гейт (иначе старт Strata уйдёт в своп/отказ):

   ```bash
   free -m | awk '/^Mem:/{print $7}'   # available MiB ≥ 46000 (iq3) / 36000 (iq2)
   ```

   Если порог не достигнут — проверить, что родительский процесс убит
   (`pgrep -af 'llama-server|ninfer-serve'`) и idle-cache llama.cpp
   (`--cache-ram 40960`) ушёл вместе с процессом. Не достигается —
   эскалировать, старт не выполнять.

4. Выставить симлинк конфига размера (без него ExecStartPre откажет):

   ```bash
   sudo ln -sfn /opt/strata/strata-iq3_xxs.json /etc/strata/active.json   # iq3
   # или /opt/strata/strata-iq2_xs.json                                   # iq2
   readlink -f /etc/strata/active.json
   ```

5. Старт юнита и ожидание готовности:

   ```bash
   sudo systemctl start strata
   # Готовность: /health 200 с НУЖНЫМ model и loaded=true
   # (iq3 ~20-24 c, iq2 ~14 c; дискриминатор размера — поле model:
   curl -s http://172.17.0.1:8081/health | jq
   # ждать {"status":"ok","model":"qwen3.8-flash-next-iq3_xxs","loaded":true}
   ```

   Поле `model` обязано совпасть с конфигом: `/health` отвечает 200 при
   любом размере — совпадение единственная защита от рассинхрона
   «профиль ↔ резидентный размер».

6. Выставить strata-профиль:

   ```bash
   curl -X PUT http://localhost:8080/api/profiles/active \
        -H 'Content-Type: application/json' -d '{"name":"strata-iq3"}'  # или "strata-iq2"
   curl -s http://localhost:8080/api/profiles | jq -r .active
   ```

7. Проверка: запрос к `strata-iq3`/`strata-iq2` через `:8080` отвечает;
   поле `model` в ответе — native canon (не сверять с запрошенным ID);
   `nvidia-smi` — GPU1 свободно ≥ 512 MiB (под Strata норма ~1.7 ГиБ).

## Смена размера внутри Strata (iq3 ↔ iq2)

Сначала полный переход на родителя или `off` (шаги 1–3 второго раздела
наоборот не работают: оба размера резидентно не живут) — фактически:
`systemctl stop strata` → дождаться VRAM → симлинк на другой конфиг →
`systemctl start strata` → `/health` с новым native-ID → профиль соседнего
размера не забыть (профиль и резидентный размер должны совпадать).

## Типовые отказы strata-ID (диагностика от клиента)

| Симптом | Причина | Действие |
|---|---|---|
| `404 no model id could be identified` (мгновенно) | активен родительский профиль — strata-ID закрыты пинами `~` | `strata-use.sh strata-iq3\|strata-iq2` |
| `500 upstream command exited prematurely` (~1.5 c) | strata-профиль активен, но юнит не запущен — shim-watchdog умер | `strata-use.sh strata-iq3\|strata-iq2` |
| UI llama-swap: модель «unloaded», кнопка включения не помогает | llama-swap стартует только shim (умирает без `/health`), нативный юнит поднять не может | только `strata-use.sh <роль>` |
| opencode: модель видна в списке, запрос падает 404 | то же, что строка 1 — выбор модели в клиенте не переключает профиль | `strata-use.sh <роль>` перед сессией |

Переключение ролей из opencode/UI невозможно по архитектуре (ADR-0007):
нативный юнит — процесс хоста вне досягаемости llama-swap, последовательный
доступ обеспечивает только оркестратор.

## Метрики и логи

- Логи/метрики движка: `journalctl -u strata -f` (логи server.py: запуск,
  останов, decode/admission-строки движка) и файл-лог движка
  `/opt/strata/strata-*.log`.
- Собственный мониторинг Strata — первичный источник метрик; llm-monitoring
  (promtail/Loki/Grafana) выключен (7 контейнеров stopped, `unless-stopped`)
  и вне текущей топологии; его возврат требует сначала увести его cadvisor
  с занятого `:8081`.
- Состояние роутера: `GET /api/profiles` (поле `active`), SSE `/api/events`;
  `GET /v1/models` под strata-профилем показывает 2 записи — это семантика
  пинов v265, не регресс.
- Красные линии: VRAM GPU1 ≥ 512 MiB (`nvidia-smi --query-gpu=index,memory.free
  --format=csv,noheader`); RAM — без постоянного свопа (транзиентные
  si/so-всплески 2–3 c на старте iq3 — норма). Нарушение линии VRAM —
  останов лишнего резидента, не игнорировать.
