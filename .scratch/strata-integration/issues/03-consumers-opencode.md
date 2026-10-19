# Потребители: opencode и полевой доступ

Status: open
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
