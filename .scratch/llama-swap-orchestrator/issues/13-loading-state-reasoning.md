# `sendLoadingState` отдаёт баннер загрузки как `reasoning_content`

Type: task
Status: resolved

## Question

`router/config.yaml` включает `sendLoadingState: true`. На запросе, который платит
за загрузку движка (первый запрос после смены профиля), llama-swap стримит свой
баннер **в поле `reasoning_content`** — как если бы это был reasoning модели.
Замер тикета 07 (`assets/07-verify/banner-probe/stream.sse`,
`probe-loading-banner.sh`):

```
reasoning: '━━━━━\nllama-swap loading model: backend-llama\n\nWhispering sweet nothings…\nDone! (2.58s)\n━━━━━\n'
content:   'ok'
```

Проблема: любой потребитель, определяющий «был ли reasoning» по непустому
`reasoning_content`, получает **ложное срабатывание** на запросе загрузки. Для
карты это прямо релевантно — «клиент управляет reasoning» ломается ровно на
первом запросе после переключения backend'а. В самой матрице 07 эффект обойдён
прогревом движка перед прогоном, но в эксплуатации он есть.

Решить:

1. `sendLoadingState: false` — что теряет UX/launcher (индикатор загрузки)?
   Посмотреть, кто потребляет loading-state (`llm-monitoring`, opencode).
2. Есть ли у llama-swap настройка канала для loading-state (не
   `reasoning_content`), или фильтр, отсекающий баннер?
3. Если оставляем как есть — задокументировать (тикет 08), что первый запрос
   после смены профиля нельзя использовать как доказательство reasoning.

Решение — часть destination карты; зафиксировать в ADR-0006/README.

## Answer

**Решение: `sendLoadingState: false` в `router/config.yaml`** — применено,
контейнер перезапущен, подтверждено живым прогоном.

Короткая формулировка для тикета 08 (ADR-0006/README): *баннер загрузки
llama-swap стримится только в `delta.reasoning_content` — канал зашит в код
(`internal/router/loading.go`, `sendData`), настраиваемого канала нет; поэтому
`sendLoadingState` выключен глобально: непустой `reasoning_content` на первом
запросе после смены профиля — ложный reasoning, ломающий контракт «клиент
управляет reasoning». Плата: первый запрос после переключения движка молчит
40–60 c (llama.cpp) без in-stream индикатора.*

### Обоснование

1. **Канал не настраивается, фильтр невозможен.** Исходники llama-swap v265
   (локальный репо ровно на `a2796fb`, pull не требовался): баннер
   (`━━━━━ / llama-swap loading model: … / Done!`) стримит `loadingWriter`
   (`internal/router/loading.go`) через `sendData()`, который маршалит только
   `{"delta":{"reasoning_content": …}}` — другого канала в коде нет. Тумблер
   один: `sendLoadingState` глобально + per-model override
   (`internal/config/model_config.go:164`, `config-schema.json:545`), но это
   вкл/выкл, не выбор поля. Баннер эмитится до запуска upstream-обработчика
   (`loadingWriter` держит ResponseWriter, пока модель не готова,
   `internal/router/base.go:539`), поэтому `filters` его в принципе не видят —
   и, кроме того, фильтры llama-swap плоские (тикет 11), поле/контент они
   убрать не могут. Вариант «безопасно оставить баннер вне reasoning_content»
   не существует без форка/апстрима.
2. **Потребителей loading-state нет.**
   - `infrastructure/llm-monitoring`: promtail/Loki собирают stdout контейнера
     (там баннер и так виден как лог), Grafana-дашборды и
     nvidia-smi-exporter `reasoning_content` не читают — grep по репо пуст.
     Рядом лежащий `LLM-Switcher-Monitoring` — unrelated Steam-детектор.
   - opencode (`~/.config/opencode/opencode.jsonc`): reasoning задаёт клиентом
     (`reasoningEffort` / kwargs); `reasoning_content` только отображает —
     баннер показался бы пользователю как фейковое рассуждение модели, т.е.
     вред, а не польза.
   - `bench.py` (`scripts/nvidia-p2p/bench.py`): reasoning не парсит.
3. **По духу карты** «клиент управляет reasoning» мёртвое поле
   `reasoning_content` с баннером ломает контракт ровно на первом запросе
   после переключения — вариант «оставить как есть и задокументировать»
   отклонён.

### Применение и проверка

- Дифф: `router/config.yaml`, `sendLoadingState: true → false` (с комментарием
  о причине и плате UX); `docker compose restart llama-swap` выполнен при
  активном `ninfer` без активной генерации (`/api/profiles` проверен заранее).
- Живое доказательство: `.scratch/llama-swap-orchestrator/assets/13-loading-state/`
  (`probe-banner-off.sh`, `README.md`, дампы `stream-cold.sse`,
  `stream-thinking.sse`):
  - запрос, плативший загрузку llama.cpp (лог: `load_model: loading model … →
    model loaded`), — **ноль** чанков `reasoning_content`, текст баннера не
    встречается ни в одном поле, content `ok`;
  - контроль с thinking on — `reasoning_content` непустой (реальный reasoning
    модели, 72 chars), поле не мёртвое.
- Сравнение «до»: `assets/07-verify/banner-probe/stream.sse` (баннер в
  `reasoning_content` при `sendLoadingState: true`).
- После прогона состояние возвращено к дефолту конфига: активен `ninfer`,
  прогрет.

### Не закрыто / вне карты

- Индикатор загрузки UX пропал совсем (кроме логов promtail/Loki). Если
  когда-нибудь понадобится in-stream прогресс — только апстрим-issue в
  llama-swap на настраиваемый канал (не `reasoning_content`); по состоянию
  v265 это единственный путь.
- opencode-потребители — тикет 14; доки (ADR-0006, README) — тикет 08,
  формулировка выше.
