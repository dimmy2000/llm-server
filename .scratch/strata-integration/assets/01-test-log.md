# Тестовый проход конфигурации llama-swap (тикет 01-llamaswap-config)

Дата: 2026-10-19. Всё выполнялось на живом стеке: `docker compose up -d` (recreate
llama-swap) + ручной старт нативного Strata IQ3_XXS на :8082 (systemd-юнита ещё
нет — тикет 02).

## Конфигурация на момент прохода

- `router/config.d/30-strata.yaml` (новый): strata-iq3 / strata-iq2, watchdog-shim
  (`sh -c 'while curl -sfm 2 http://host.docker.internal:8082/health; do sleep 1; done'`),
  `proxy: http://host.docker.internal:8082`, capabilities text+image/tools,
  context 131072 / 262144, `stripParams: repetition_penalty`.
- `router/config.yaml` (изменён): пины strata-ID `~` в llama/ninfer; новые
  профили strata-iq3 / strata-iq2 (родитель и соседний размер закрыты `~`).
- `router/docker-compose.yaml` (изменён): `extra_hosts: host.docker.internal:host-gateway`.
- Нативные конфиги `/opt/strata/strata-{iq3_xxs,iq2_xs,iq3_s}.json`: `port` 8081→8082,
  добавлен `host: "172.17.0.1"` (before-снимки в этой папке). `.pre-*.json`
  (артефакты selection-фазы) не тронуты; `run-*.sh`/`soak-*.sh` остались на 8081
  (теперь не взойдут без правки — заменяются systemd-юнитом тикета 02).

## Факты прохода

1. `GET /v1/models` → ровно `['qwen3.8-27b', 'strata-iq2', 'strata-iq3']` (профиль ninfer активен).
2. Родительский контракт цел: `POST /v1/chat/completions {qwen3.8-27b, reasoning_effort: low}`
   → 200, content «один», TTFT 32 мс на прогретом контексте (NInfer dflash2, приём 75.5%).
3. Страта-ID под родительским профилем → 404 быстро (3 мс, «no model id could be
   identified») — пин `~`, без побочных эффектов.
4. Страта-ID под страта-профилем при ОСТАНОВЛЕННОМ юните → fast-fail 0.56 с:
   «upstream command exited prematurely» (сработал watchdog-shim). Одиночная запись
   в `/v1/models` «unloaded» — косметика пина (известно, v265 api.go).
   Замечание: первая попытка с `healthCheckTimeout: 20` в пер-модельном
   конфиге завершилась зависанием на глобальных 600 c — на v265 пер-модельный
   `healthCheckTimeout` перезаписывается глобальным (config/load.go:136),
   поле удалено из конфигов; fast-fail обеспечен watchdog-shim.
5. Нативный Strata IQ3_XXS :8082 (bind 172.17.0.1): начал слушать /health за ~10 с
   (страница экспертов отдавалась из кэша прошлого прогона; холодный старт —
   «1–3 минуты», см. boot-лог). `/health` → 200 {status, max_context 131072,
   model qwen3.8-flash-next-iq3_xxs, loaded: true} (`strata-iq3-health-ua.json`).
6. Нативный Strata IQ2_XS :8082: тот же канал; `/health` → 200
   {max_context 262144, model qwen3.8-flash-next-iq2_xs, loaded: true}
   (`strata-iq2-health-ua.json`). Первый прыжок IQ2_XS под резидентный
   родительский движок → движок падал OOM VRAM (cudaMalloc arena при
   869 MiB свободных) — доказательство в порядке strata-use.sh: сначала
   выгрузить родительский бэкенд (VRAM), затем стартовать юнит, затем
   коммутация профиля. После выгрузки `POST /api/models/unload/backend-ninfer`
   загрузка прошла штатно.
7. Публикация LAN: соединение на 192.168.17.99:8082 и 127.0.0.1:8082 → отказ
   (connection refused) — слушает ТОЛЬКО 172.17.0.1. Сообщение в boot-логе
   «from other devices: http://192.168.17.99:8082/» — косметика Strata
   (печатается для любой не-loopback привязки), реальных сокетов на LAN нет.
8. DNS-rebinding защита Strata: probe-запрос llama-swap (Host
   `host.docker.internal:8082`) прошёл без allowed_hosts — при не-loopback
   привязке имя host.docker.internal уже в host_names (serve/server.py).
9. Полный путь через `:8080`: non-stream и stream 200 на strata-iq3
   (content «два»/«три»), non-stream 200 на strata-iq2 (content «пять») —
   ответ `model` — native-ID (`qwen3.8-flash-next-iq*_…`, имя запроса в ответ
   не возвращается — задокументировано в config.d/30-strata.yaml).
10. Пины-фильтры: в профиле strata-iq2 запросы к strata-iq3 и qwen3.8-27b → 404
    быстро (родитель и соседний размер закрыты).
11. Остановка нативного сервера (SIGTERM server.py) → дети (engine/strata,
    strata-vision) умерли, VRAM освободилась (15/579 MiB); RAM (47 ГиБ / 36 ГиБ
    экспертов, page-locked) выгрузилась обратно за секунды; следующий запрос к
    strata-iq3 → fast-fail 0.26 с, шимов в контейнере не осталось.
    Нюанс для юнита (тикет 02): один из SIGTERM server.py был проглочен
    (движок-ребёнок остался жив, VRAM/RAM удерживал до прямого kill) —
    ExecStop должен уметь добивать дерево процессов, а скрипт проверять
    «движки погибли» перед следующим шагом.
12. Обратный цикл: PUT /api/profiles/active {"name":"ninfer"} → qwen3.8-27b
    грузится первым же запросом за ~7.8 c и отвечает. Состояние после теста:
    активен ninfer, страта-юнит погашен, RAM/VRAM фоновые.

## Открытое для следующих тикетов

## Пересадка на :8081 (2026-10-19, следом за проходом)

llm-monitoring остановлен (`docker stop` grafana/promtail/loki/prometheus/
nvidia-smi-exporter/node-exporter/cadvisor; restart-policy `unless-stopped`
переживает reboot; роутер не тронут), :8081 освобождён — Strata переведена на
канонический порт: json `port` 8082→8081, shim cmd/proxy → :8081, AGENTS.md,
`docker compose restart llama-swap`. Проверено живьём: iq3 на :8081 → `/health`
200 через ~23 c, запрос через `:8080` (профиль strata-iq3) → 200 «Семь»;
останов юнита → fast-fail 1.5 c; возврат ninfer → 200. Конфиг неожиданностей
не предъявил. Условие для будущих возвращений мониторинга: его cadvisor
сначала увести с :8081.

## Открытое для следующих тикетов

- Proxy `http://host.docker.internal:8082` разворачивается в host-gateway
  `172.17.0.1`. Если сменить дефолт демона (`--host-gateway`) — в паре менять
  и привязку нативного сервера (примечание в config.d/30-strata.yaml).
- Логика юнита (тикет 02) может опираться на: /health payload (дискриминатор
  размера — поле `model`, готовность — `loaded`), цикл старта «дождаться
  GET /health 200 → PUT profile», правило NO-автостарта юнита (окно VRAM
  захватывается только по strata-use.sh).
- Windows port-forwarding: снаружи потребителей только через :8080 — новые
  маршруты не понадобятся (уточнение — тикет 03).
