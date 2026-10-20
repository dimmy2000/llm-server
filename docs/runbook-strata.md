# Runbook: Strata — контейнерный движок, диагностика и контейнерные операции

Страта — третий движок роутер-контейнера наравне с llama.cpp и NInfer
(ADR-0008): llama-swap стартует и останавливает её сам, по запросу к
`strata-iq3`/`strata-iq2`, в безопасном порядке unload→start дефолтной
exclusive-группы. **Ручных шагов переключения нет и быть не может** — выбор
ID в клиенте или UI (`:8080`) и есть переключение. Этот ранбук — про
диагностику отказов и надзор за красными линиями, не про переключение.

Константы: llama-swap `:8080` (контейнер `llama-swap`, образ
`llm-server/router:v265-strata1`); RAM-гейты лаунчера 46 ГиБ (iq3) / 36 ГиБ
(iq2); красная линия VRAM — ≥ 512 MiB на дисплейной GPU1; метки конфигов
Strata — `router/strata/*.container.json`, лаунчер —
`router/strata/strata-launch.sh`.

## Окна молчания и тайминги (выдержка, полные данные — ADR-0008 и assets/11)

| Бэкенд | Холодный старт (платит первый запрос) | Резидентный ответ |
|---|---|---|
| NInfer | ~6–7 c | 0.05–0.12 c |
| Strata iq3 | 17.8–20.9 c (норма 15–25) | быстрый |
| Strata iq2 | 12.7–13.8 c | быстрый |
| llama.cpp | 7–9 c на тёплом page cache; до 40–60 c на холодном диске | быстрый |

При `sendLoadingState: false` холодный запрос молчит без индикатора — это
ожидаемо, не зависание: индикатор только в логах контейнера. Клиентские
таймауты менять не нужно (`healthCheckTimeout: 600` глобальный, отсчёт
сбрасывается на прогрессе загрузки).

## Типовые отказы (диагностика от клиента) и первая помощь

| Симптом | Причина | Действие |
|---|---|---|
| `500 upstream command exited prematurely` за ~2 c, в логах `strata: RAM gate: need …GiB, MemAvailable …MiB` | RAM-гейт не пройден: посторонние процессы съели память (резидентный бэкенд выгружается до гейта — при недостижимом пороге память занята вне инференса) | жёсткий быстрый отказ, лежит в природе автомата; освободить RAM на хосте и повторить запрос. Ретраев llama-swap нет — по дизайну |
| `500 upstream command exited prematurely`, traceback движка в логах | провал старта/health-check движка (битые маунты весов, конфиг, OOM VRAM) | `docker logs llama-swap --tail 200`; смотреть причину. Маунты/конфиги чинить на хосте, пересоздать контейнер |
| Запрос к strata-ID висит сотни секунд без ответа | не гейт: глобальный `healthCheckTimeout: 600` при прогрессирующем старте — норма ожидания свапа (+ холодная загрузка) | ждать; индикация — логи контейнера |
| `404 no model id could be identified` | этого отказа больше нет (старые пины `~` удалены); если воспроизводится — конфиги откатились к пред-автоматной версии | проверить `git status` роутера-содержимого и активную сборку образа |

## Логи и метрики

- Server.py и движок — stdout контейнера:

  ```bash
  docker logs -f llama-swap          # старт/останов/decode/admission-строки
  ```

- Файл-лог движка — внутри контейнера (маунта на хост нет):

  ```bash
  docker exec llama-swap cat /opt/strata/strata-iq3_xxs.log
  docker exec llama-swap cat /opt/strata/strata-iq2_xs.log
  ```

- Состояние роутера: `GET /api/profiles` (поле `active`), SSE `/api/events`,
  `GET /v1/models` — три ID в любом состоянии.
  `status: unloaded` в `/v1/models` — косметика llama-swap (hardcode для
  пинов); реальное состояние — `/api/profiles`, `/api/events` или `/health`
  upstream-порта.

- Красные линии: VRAM GPU1 ≥ 512 MiB — `nvidia-smi --query-gpu=index,memory.free
  --format=csv,noheader`; RAM — без постоянного свопа (транзиентные si/so
  всплески 2–3 c на старте iq3 — норма). Нарушение линии VRAM — увести
  резидента (запрос к другому ID или PowerOff в UI), не игнорировать.

## Контейнерные операции (аварийные, вместо прежнего ручного пути)

`strata-use.sh`, `strata.service`, `strata-stop`, симлинк
`/etc/strata/active.json` — демонтированы (ADR-0008, тик 10); нативная
`/opt/strata` на хосте осталась как база отката в первую итерацию
(инструкция отката — комментарий Answer тика 10). Все аварийные действия
сейчас — контейнерные:

```bash
docker compose restart llama-swap       # после правок config.d/ или router/strata/
docker compose up -d --force-recreate llama-swap   # после правки router/config.yaml подменой файла
docker compose build llama-swap         # после смены пинов движков/исходников Strata в Dockerfile
```

UI llama-swap на `:8080` — полноправное управление страта-движком: Play
стартует движок, PowerOff посылает SIGTERM (graceful QUIT движка).
`PUT /api/profiles/active` — только выбор движка родителя llama/ninfer
(предпочтение производительности, не условие работоспособности).

llm-monitoring (promtail/Loki/Grafana) выключен и вне топологии.
