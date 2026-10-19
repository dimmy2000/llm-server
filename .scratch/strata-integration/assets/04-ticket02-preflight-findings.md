# Тикет 02 (нативный lifecycle): материалы преграйда оркестратора

Дата: 2026-10-19. Собрано до отдачи тикета субагенту.

## Подтверждённые живые проверки (из системы, не из документов)

- `systemctl status strata` / `list-unit-files`: юнита `strata.service` НЕ существует —
  задача «спроектировать и реализовать юнит» актуальна в полном объёме.
- `/opt/strata/*.json`: есть `strata-iq3_xxs.json`, `strata-iq2_xs.json`,
  `strata-iq3_s.json` (+ вспомогательные pre-cal/pre-vision/test варианты).
- Состояние ключевого конфига `strata-iq3_xxs.json` (полный листинг — в истории
  сессии оркестратора; тикет 01 его уже трогал):
  - `"exe": "/opt/strata/engine/strata"`, `"cwd": "/opt/strata"`;
  - `"port": 8081`, `"host": "172.17.0.1"` (docker0, привязка согласована с
    `router/docker-compose.yaml` extra_hosts host-gateway);
  - `"model_name": "qwen3.8-flash-next-iq3_xxs"` — канон native-ID, поле `model`
    в `/health` ожидается ровно это имя ( дискриминатор размера);
  - `"log": "/opt/strata/strata-iq3_xxs.json.log"` → точнее:
    `/opt/strata/strata-iq3_xxs.log` (файл-лог движка);
  - `"gpu": [0, 1]` — обе карты;ertia
  - `--expert-cache 4400`, `--kv int8`, `--max-context 131072`.
- Скрипты в репо: `scripts/nvidia-p2p/{rebuild-modules.sh,p2p-verify.sh,p2p-snapshot.sh}`
  — образец конвенций для нового `scripts/strata/`.
- Стек роутера активен, `/v1/models` публикует три ID (qwen3.8-27b, strata-iq2,
  strata-iq3); активный профиль — ninfer; страта-юнит не запущен (RAM/VRAM
  фоновые).

## Из ответа тикета 01 (обязательные ограничения для 02)

- Порядок ролей при переходе на Strata: unload родителя → старт юнита →
  дождаться `/health` → выставить профиль strata-iq3/strata-iq2. При резидентном
  родителе старт Strata падает OOM VRAM (замерено на iq2: arena cudaMalloc при
  869 MiB свободных).
- `/health` нативного сервера содержит `model` (размер) и `loaded` (готовность) —
  создать health-джоб для ожидания и дискриминации размера.
- SIGTERM server.py однажды проглотился, движок-ребёнок жил и держал VRAM/RAM до
  прямого kill — ExecStop обязан гарантированно добивать дерево (kill по pid-файлу
  или pkill -f engine/strata).
- RAM (47/36 ГиБExperts page-locked) освобождается убийством движка за секунды;
  llama.cpp idle-cache до ~40 GB RAM освобождается его kill/unload за секунды —
  fog «RAM-баланс» скорее закроется простой гигиеной через unload (проверить
  в тикете, эскалация — если unload не освобождает).

## Что ждать в ответе субагента

- Файлы: systemd-юнит (disabled, не в автозапуске), `scripts/strata/strata-use.sh`
  (или другое место — с обоснованием по конвенциям репо), health-джоб-хелпер.
- Живой прогон цикла `strata-use.sh` llama → strata-iq3 → strata-iq2 → ninfer → off,
  raw-логи в `.scratch/strata-integration/assets/` (коммит конфигов — в репо).
- Ответы на три вопроса тела тикета: RAM-гигиена, дискриминатор рассинхрона,
  расположение скриптов; ExecStop-стратегия; решение об автовосстановлении.
