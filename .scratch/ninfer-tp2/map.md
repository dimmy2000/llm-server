# NInfer TP=2 — переход llm-server на движок NInfer

Type: wayfinder:map

## Destination

Профиль `ninfer` в `llm-server`, проверенный на этой машине: NInfer TP=2 за
llama-swap, официальный артефакт Qwen3.8-27B, те же публичные model-ID, что и
в llama-профиле, замеры против llama.cpp на одинаковых промптах и решение по
судьбе несовместимых потребителей (уровни effort в имени модели,
`repeat_penalty`).

Профиль запущен и проверен на живом железе 2026-10-05: контейнер `llama-swap`
из сервиса `ninfer-swap`, официальный артефакт, все 7 ID работают, baseline
против llama.cpp снят, VRAM-бюджет подтверждён, `nvfp4` KV против `int8`
измерен. Замеры — в `docs/research/0009-ninfer-tp2-two-5070ti.md` и в
`AGENTS.md`. Осталось: профиль с DFlash2, миграция потребителей и мониторинг;
судьба `ornith-9b-*` закрыта — модель удалена из проекта (ADR-0004).

## Notes

Источники и разбор — `docs/research/0009-ninfer-tp2-two-5070ti.md`, решения —
`docs/adr/0003-ninfer-profile-llama-swap.md`. Из истории чата выжимка в
`/opt/vaults/LLMVault/NInfer Two GPU Insights.md`.

Железо: 2× RTX 5070 Ti 16303 MiB (sm_120a), driver 595.91.07, CUDA 13.3,
Ubuntu 26.04.1, дисплей на GPU1 (~478 MiB постоянно), требование проекта —
≥ 512 MiB свободной VRAM на GPU1 под пиковой нагрузкой.

Движок: релиз `ninfer-tp2 v0.4.5` форка `ValerioDolci/ninfer-tp2` (upstream
`Neroued/ninfer` одноплатовый). Архив под ubuntu26.04, SHA-256 зафиксирован в
Dockerfile и проверен на сборке; в архиве только бинарники и `libcudart.so.13`,
Dockerfile ставит FFmpeg 8 и libcurl4t64. Бинарь `llama-swap` копируется из
образа llama-профиля (версия v240).

Модель: `neroued/Qwen3.8-27B-nvfp4-NInfer`, 23.7 GB, веса 20.9 GiB, SHA-256
из репозитория артефакта зафиксирован в `ninfer/fetch-model.sh`. Компоненты:
text, vision, mtp, dflash2.

Пределы VRAM на двух 16 ГиБ платах (README форка): MTP3 даёт 262144 токена при
4 слотах либо 196608 с Vision и 4 слотах; дефолтные 8 слотов с Vision на
196608 не влезают; DFlash2-драфтер живёт целиком на первой GPU и с официальным
артефактом ограничивает контекст ~150k. `--embedding-host` возвращает 1.18 GiB
на плату (таблица embedding в pinned host RAM, результаты те же).

Пресеты сэмплирования NInfer совпадают с llama-профилем по режимам thinking,
поэтому клиентские sampling-параметры отбрасываются; effort задаёт агент.
`preserve_thinking: false` убирает reasoning из следующих запросов диалога, но
не скрывает `reasoning_content` текущего запроса.

Что уже сделано: `docker compose --profile ninfer build` (образ
`llm-server/ninfer-tp2:v0.4.5`), проверка конфига llama-swap (все 7 ID видны в
`/v1/models`), сверка всех флагов `cmd` с `--help` бинаря v0.4.5, скачивание и
проверка артефакта, живой запуск и baseline (тикеты 01–03 resolved).

Baseline: движок готов через 6.1 с, веса 18.5 GiB за 4.5 с; prefill 4597 tok/s
на 30k, 3319 на 98.8k, 2605 на 165k; decode 130.1–131.5 tok/s и 106.3 tok/s на
контексте 131830; приём MTP 46–48 %; минимум свободной VRAM под нагрузкой
GPU0 2018 MiB, GPU1 1501 MiB. Против llama.cpp на тех же картах — 2.42× по
prefill и 1.63× по decode. Проверены также Vision, tool calls, отказ контекста
сверх 196608 и неизвестного effort.

## Frontier

- 08 — профиль ninfer в мониторинге

## Decisions so far

- [01 — Скачать и проверить официальный артефакт](issues/01-download-and-verify-artifact.md)
- [02 — Cold-start профиля и baseline против llama.cpp](issues/02-cold-start-and-baseline.md)
- [03 — VRAM-бюджет под пиковой нагрузкой](issues/03-vram-budget-under-load.md)
- [04 — nvfp4 KV против int8 и контекст 262144](issues/04-nvfp4-kv-tradeoff.md)
- [05 — Профиль с DFlash2](issues/05-dflash2-profile.md) (resolved)
- [06 — Effort на стороне агентов](issues/06-agent-side-effort.md) (resolved)
- [07 — Судьба ornith-9b и instruct-режима](issues/07-ornith-and-instruct.md) (resolved)
- [08 — Профиль ninfer в мониторинге](issues/08-monitoring-integration.md)
- [09 — Обновить документацию по результатам замеров](issues/09-update-docs.md)
- [10 — Вытеснение device-state слотов при нескольких диалогах](issues/10-device-state-slot-eviction.md)

Ответы тикетов 01–03: артефакт цел и грузится; baseline и VRAM подтверждены
без правок профиля, `--embedding-host` оставлен. Тикет 10: удержание состояния
измерено — 3 диалога из любого числа, четвёртый префиллится заново, ошибок нет.
Тикет 04: A/B снят — `nvfp4` 262144 помещается с Vision и 4 слотами (KV-пул
2.98 против 3.87 GiB, +920 MiB свободно на плату, префилл −1.3…−1.6 %, decode
в разбросе), но в базовом профиле оставлен `int8`: 196608 уже больше, чем даёт
llama-профиль, качество 4-битного KV локально не проверено. Тикет 09 закрыт по
итогам 02–03: цифры перенесены в research 0009, `AGENTS.md`, `README.md` и в
заметку `/opt/vaults/LLMVault`. Тикет 05 закрыт: DFlash2 измерен на этой машине;
в базовый профиль не включается (на `int8` теряет треть контекста и два слота,
на `nvfp4` — непроверенное качество KV), триггеры возврата зафиксированы.
Тикет 06 закрыт: effort в NInfer — инструкция в системном промпте от chat
template артефакта, а дефолт шаблона `xhigh`, поэтому прежняя передача effort
клиенту означала молчаливую подмену уровня. Effort возвращён на сервер по имени
алиаса (жёсткий ключ в `setParamsByID`), миграция потребителей не требуется;
заодно исправлен код 400 (не 401) у `conflicting_template_option` и опровергнуто
утверждение, что конфликт бывает на thinking-режимах — там клиентский
`chat_template_kwargs` заменяется целиком. Потребители: только
`~/.config/opencode/opencode.jsonc` (`agent-medium`, `agent-xhigh`) — работает
без правок; `llm-monitoring` не знает model-ID вообще. Тикет 07 закрыт:
модель Ornith 9B удалена из проекта целиком (ADR-0004), быстрые задачи
обслуживает instruct-режим `qwen3.8-27b` (~106–131 tok/s decode против
~40–60 у Ornith), агентам показывается единый список `qwen3.8-27b*`; в
llama-профиле осталась одна модель, поэтому ручное переключение снято и
включён прелоад. Открыт 08 (мониторинг).

## Not yet specified

- Стратегия переключения между профилями: держать ли оба контейнера
  одновременно выключенными и переключаться профилями, или вводить
  дополнительный маршрут на уровне порта.
- Нужен ли отдельный профиль `ninfer-dflash2` как второй compose-профиль или
  как переключаемая конфигурация внутри `ninfer/`.
- Тикет 08: launcher `llm-stack.sh` в `infrastructure/llm-monitoring` не имеет
  параметра профиля и ссылается на `docker-compose.monitoring.yml`, тогда как
  файл на диске называется `.yaml`; `AGENTS.md` описывает профиль как
  существующий, а он отсутствует.
- Проверка длинных streaming-ответов под нагрузкой (общая практика профиля
  vLLM), если она потребуется после первых результатов.

## Out of scope

- Сборка движка из исходников (используем готовые бинарники релиза).
- Портирование tp2 в upstream `Neroued/ninfer`.
- Сравнение качества ответов официального артефакта и QUASAR-артефактов на
  этой машине: задача качества, а не конфигурации профиля.
- Тепловое тюнингование хоста (отдельный effort в `infrastructure`).
