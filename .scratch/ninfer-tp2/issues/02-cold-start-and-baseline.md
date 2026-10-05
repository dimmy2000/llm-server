# 02 — Cold-start профиля ninfer и baseline против llama.cpp

Type: task
Status: resolved

## Question

Первый раз запустить профиль `ninfer` на живом железе и снять baseline, который
станет точкой отсчёта для остальных тикетов:

```bash
docker compose --profile llama --profile ninfer --profile vllm down --remove-orphans
docker compose --profile ninfer up -d --wait --wait-timeout 1800
docker compose --profile ninfer logs -f ninfer-swap
```

Зафиксировать:

- время старта контейнера до готовности и время загрузки модели;
- поведение `/health`, `/v1/models` (7 ID) и одного запроса к
  `/v1/chat/completions` с `model: qwen3.8-27b` (instruct) — reasoning должен
  отсутствовать;
- то же для `qwen3.8-27b-chat-medium` с `reasoning_effort: medium` — должен
  прийти `reasoning_content`;
- строку `tensor parallel` из лога (`p2p on` или `p2p off (host-staged
  copies)`) и строки рангов (`replicated` / `host-mapped`);
- prefill и decode на одинаковых промптах с замерами из истории чата
  (prefill 90k cold, генерация 8192 токенов), чтобы сравнение с llama.cpp
  было apples-to-apples;
- ошибки в логе: 4xx от движка (неверное имя модели, конфликт шаблонных
  опций), падения CUDA graph, таймауты очереди.

Останавливать работающий llama-профиль только с согласия пользователя;
прогон занимает обе GPU, поэтому восстановление llama-сервиса после теста —
обязательный шаг.

## Acceptance

- Контейнер поднялся, `/v1/models` отдаёт 7 ID, instruct и thinking ведут себя
  как задумано.
- В логе есть строка транспорта между ранками и нет ошибок 4xx.
- Цифры prefill/decode и VRAM после старта записаны в комментарий к тикету и
  используются как baseline для тикетов 03–05.

## Answer

Профиль поднят на живом железе 2026-10-05 (пользователь остановил llama-профиль
и дал согласие на запуск). Базовые линии:

- старт: контейнер `llama-swap` healthy, движок готов через 6.1 с, веса
  18.5 GiB за 4.5 с (4.07 GiB/s), CUDA graphs 66.8 ms;
- транспорт: `p2p off (host-staged copies)`, mailbox захвачен, probe 0.03 ms;
- ранги: `--embedding-host` даёт `host-mapped 1.18 GiB`;
- KV: 196608 / int8 / runtime 3.87 GiB, запас 1.34 GiB на старте;
- `/v1/models` — 7 ID; `/health` — 200;
- instruct `qwen3.8-27b`: `reasoning_tokens: 0`, decode 164 tok/s, MTP 3/3;
- thinking `chat-medium` + `reasoning_effort: medium`: `reasoning_content`
  приходит, 46 reasoning-токенов, decode 173.6 tok/s, MTP 38/48.

Prefill: 4597 tok/s на 29 985; 3318.9 tok/s на 98 849 (TTFT 29.8 с); 2605.2
tok/s на 164 733 (TTFT 63.2 с). Decode: 130.1 tok/s (1880 токенов), 131.5 tok/s
(4834 токена, приём MTP 47.8 %), 106.3 tok/s на контексте 131 830. Против
llama.cpp на тех же картах (prefill 90k 1372 tok/s, генерация 80.5 tok/s):
2.42× и 1.63×.

Дополнительно проверено в рамках тикета: Vision (корректное описание
сгенерированного PNG, 99 prompt-токенов), tool calls (`finish_reason:
tool_calls`), отказ контекста сверх 196608 (`400 context_length_exceeded`,
сервис жив), отказ неизвестного effort (`400` со списком значений), неизменность
instruct при клиентском `reasoning_effort: medium`.

Логи и числа перенесены в `docs/research/0009-ninfer-tp2-two-5070ti.md`
(раздел «Замеры профиля `ninfer` из этого репозитория») и в `AGENTS.md`.
