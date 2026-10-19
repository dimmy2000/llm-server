# scripts/strata — нативный lifecycle Strata (тикет 02 карты strata-integration)

Нативный движок Strata (`/opt/strata`, Qwen3.8-Flash-Next) живёт на хосте рядом с llama-swap;
конвенции папки — как в `scripts/nvidia-p2p/` (исполняемые скрипты в репо, root-части
— симлинками на файлы репозитория).

| Файл | Роль |
|---|---|
| `strata-use.sh` | **Единственная точка правды переключения ролей** `{llama|ninfer|strata-iq3|strata-iq2|off}` |
| `strata.service` | systemd-юнит движка (в репо; устанавливается симлинком в `/etc/systemd/system/`) |
| `strata-stop` | ExecStop-добивание дерева процессов: SIGTERM server.py однажды был проглочен, а движок-ребёнок держал VRAM/RAM до прямого kill (тикет 01) |

## Установка (однократно)

```bash
sudo ln -s "<repo>/scripts/strata/strata.service" /etc/systemd/system/strata.service
sudo ln -s "<repo>/scripts/strata/strata-stop"    /usr/local/sbin/strata-stop
sudo systemctl daemon-reload
```

`/etc/strata/active.json` (симлинк на выбранный конфиг движка) создаёт сам `strata-use.sh`;
вручную юнит не запускать — ExecStartPre отказывается без симлинка.

## Использование

```bash
scripts/strata/strata-use.sh strata-iq3   # iq3_xxs @131072
scripts/strata/strata-use.sh strata-iq2   # iq2_xs  @262144
scripts/strata/strata-use.sh llama        # llama.cpp  (загрузится на первом запросе qwen3.8-27b)
scripts/strata/strata-use.sh ninfer       # NInfer TP=2 (также по первому запросу; дефолт)
scripts/strata/strata-use.sh off          # юнит down + дефолт-профиль ninfer, движки не грузятся
```

Скрипт идемпотентен: повтор того же состояния — no-op. Диагностика: `journalctl -u strata -f`
(логи server.py), `/opt/strata/strata-*.log` (файл-лог движка).

## Гарантии порядка и защиты

- Переход на Strata строго: **unload родителя (`POST /api/models/unload`) → RAM-порог →
  симлинк → `systemctl start` → `/health` с нужным `model`+`loaded=true` →
  `PUT /api/profiles/active`**. При резидентном родителе старт Strata = OOM VRAM (замер тикета 01).
- RAM-гигиена: llama.cpp держит до ~40 ГиБ `--cache-ram`; unload убивает процесс — RAM
  освобождается за секунды (подтверждено в тикете 02); страта-переход требует available ≥
  46 ГиБ (iq3) / 36 ГиБ (iq2), иначе отказ (exit 5).
- Рассинхрон: /health дискриминатор размера — поле `model` (`qwen3.8-flash-next-iq3_xxs` /
  `-iq2_xs`); профиль strata-iq3/iq2 ставится только после совпадения. Юнит, работающий
  чужим размером, корректно перезапускается.
- Останов: ExecStop (`strata-stop`) TERM → ждать → KILL всё дерево (server.py, движок,
  strata-vision); после — проверка процессов pgrep и nvidia-smi (exit 7, если VRAM держится).
- Автостарт юнита **выключен** (не enable): окно вытесняющего режима ручное, после ребута
  VRAM не захватывается в обход родительского профиля llama-swap.

## Коды выхода strata-use.sh

0 ок · 1 аргумент · 2 API/profiles · 3 юнит/конфиг отсутствуют · 4 дерево не добито ·
5 RAM-порог · 6 таймаут /health · 7 VRAM не освободилась.

## Что не трогать

Конфиги движка `/opt/strata/strata-*.json` (port 8081, host 172.17.0.1, model_name)
зафиксированы тикетом 01 — scripts/strata их не изменяет.
