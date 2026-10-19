# Потребители: opencode и полевой доступ

Status: resolved
Type: task
Blocked by: 01

## Question

(Исполняемый тикет, AFK) Перевести потребителей на новый публичный набор ID:

- **opencode** `~/.config/opencode/opencode.jsonc`: три модели в одном провайдере
  llama-swap (`qwen3.8-27b`, `strata-iq3`, `strata-iq2`); reasoning-варианты для
  Strata — сверить с контрактом Strata (`reasoning_effort none/low/medium/high`;
  наш `xhigh` на chat-пути Strata отвечал 200 — карта selection, тикет 03;
  top-level vs `chat_template_kwargs` — у Strata проверить, что llama-swap не съедает).
  Имя провайдера оставить `llama-swap` (конфликт имен был только при прямом
  opencode→`8081`, теперь через `:8080`).
- Headless-верификация агентного цикла на каждом ID: tool calls, prefix-cache,
  reasoning off/low (env-nuances: `env -u http_proxy -u https_proxy`,
  `--standalone`).
- Проверить прочих потребителей: launcher `llm-monitoring`, `bench.py` — ломает ли
  их появление двух новых ID в `/v1/models` (дефолт-логика «первая модель»).
- Windows port-forwarding (`scripts/port-forwarding-rules.ps1`): нужен ли проброс
  новых рутов — уточнить у пользователя, как он достаёт стек из Windows.

Resolved when: opencode видит и запускает сессии на всех трёх ID (headless-pass по
циклу тика 07 selection-карты, сокращённый: tool-call + prefix reuse + effort),
старые потребители не падают.

## Comments

### 2026-10-19 (сессия оркестратора): claim перед делегированием

Тикет 02 решён (юнит + strata-use.sh работают), 03 — свободен; исполнение передано
субагенту. Контекст: Strata принимает any model name; поле `model` в ответе —
канон native-ID (клиентов не сверять — из тикета 01/02).

### 2026-10-19 (субагент тикета 03): сделано — opencode на три ID, headless-пассы, прочие потребители

**Файл конфига** `~/.config/opencode/opencode.jsonc` — добавлены `strata-iq3`
(limit.context 131072) и `strata-iq2` (262144) в `providers.llama-swap`; у обеих
`compatibility.reasoningField: "reasoning_content"` и варианты массивом объектов
v2-формата: `off` = top-level `reasoning_effort:"none"`, `low|medium|high` = top-level
`reasoning_effort`. **xhigh для Strata НЕ даётся:** живой тест (сырьё
`../assets/03-strata-variant-tests.md`) показал — движок принимает xhigh (200,
не из ошибки валидации «use none, low, medium or high»), но поведение
статистически неотличимо от high (6 сэмплов each: mean completion_tokens
3799 vs 3806). Решение документировано в комментарии шапки конфига. Оба механики
через :8080 работают (top-level и chat_template_kwargs), избран top-level —
канон словаря движка; прочие блоки (self-hosted, provider.openai, корневой
"model", agent.plan.model) не тронуты. Бэкап перед правкой:
`~/.config/opencode/opencode.jsonc.bak-20261019-strata` (sha256 = pre-edit config).

**Headless-пассы** (`env -u http_proxy -u https_proxy … --standalone`, сырьё
`../assets/03-headless-{iq3,iq2,parent}.md`):
- `strata-iq3`: run1 `#low` cold → tool-use read + reasoning + ответ
  (ses_eabbc1e49ffeFasSqmZmGWme6C, 6.7 c); run2 та же сессия, схожий промпт →
  cache.read 14447 (write 0), 1.7 c; run3 `#off` → «486» без reasoning (4.3 c).
- `strata-iq2`: run1 `#low` → tool-use + reasoning + ответ
  (ses_eabbd706affeZh7cmInPazxCxs); run2 → cache.read 14440, 1.6 c; run3 `#off` → «391».
- `qwen3.8-27b`: smoke `#off` → tool-use + «Инна, Олег, Света»
  (ses_eabbb2b4cffejsEfFfpUS3ML3a; NInfer прогрузился на первом запросе).

**Прочие потребители.** `bench.py` — модель всегда явно (`--model` required,
порт эндпоинта не меняются); замерены живьём: `strata-iq3` total 0.41 с
(prefill 225 tok/s, draft 4/4), `qwen3.8-27b` (ninfer) total 0.12 с (draft 2/1)
— `../assets/03-bench.md`. Логика «первая модель из /v1/models»: grep по
исполняемым скриптам (без .scratch/docs) — единственный встречающийся
`/v1/models` — liveness-check в `scripts/nvidia-p2p/soak.sh` (не читает список,
только 200) → появление двух новых ID не обработает ничто. llm-monitoring
остался выключен (7 контейнеров Exited 4 ч назад), живой роутер `healthy`,
`/v1/models` 200 → его отсутствие ничего не ломает.

**Windows port-forwarding — HITL-вопрос из тела тикета.** Факты:
`scripts/port-forwarding-rules.ps1` авто-дискаверит порты из `docker ps`
(паттерн `0.0.0.0:<port>->`) и делает netsh portproxy + firewall-правила;
из контейнеров публикуется только `0.0.0.0:8080` (llama-swap) — все три
публичных ID (`qwen3.8-27b`, `strata-iq3`, `strata-iq2`) доступны снаружи через
один :8080, специального прохода не нужно. Нативная Strata слушает
172.17.0.1:8081 (docker0) — docker-publish нет, поэтому авто-скрипт её не
подхватит; из Windows до docker0 напрямую не достучаться (управлять двумя
портами требует socat/iptables DNAT в WSL). Вопрос пользователю — в «Not yet
specified» карты.

**Состояние стека после тикета:** исходное (профиль ninfer активен, юнит strata
inactive); переключения весь тикет — только через strata-use.sh (strata-iq3 →
strata-iq2 → strata-iq3 → ninfer). Красная линия GPU1 соблюдена: под Strata
1671–1707 MiB свободно (замеры стартовых строк), окончательный хвост — см.
`../assets/03-final-stack-state.md`.

### 2026-10-19 (пользователь, via оркестратор): Windows-вопрос закрыт

Ответ: `scripts/port-forwarding-rules.ps1` — устаревший скрипт, сейчас не
используется; достаточно, чтобы порт `:8080` был доступен по локальной сети.
Специального прохода к Strata `:8081` снаружи не требуется (и невозможно без
DNAT — не нужно). Оглушённый статус скрипта (устарел) отразить в AGENTS.md
(раздел «Сопутствующие проекты») — тикету документации (05). Вещь снята с
Not yet specified карты.

