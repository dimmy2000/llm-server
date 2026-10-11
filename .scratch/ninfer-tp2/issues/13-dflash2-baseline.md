# 13 — DFlash2 и glfenix-артефакт в базовом профиле

Type: research
Status: claimed
Blocked by: 05

## Question

Перевести базовый профиль `ninfer` с официального артефакта + MTP3 на
glfenix-артефакт с DFlash2 и переписанный VRAM-бюджет, принятые
grilling-сессией 2026-10-08, и переснять неопределившиеся цифры.

## Принятые решения (grilling 2026-10-08)

Решения согласованы в grilling-сессии; карта и обоснование — в
`docs/research/0009-ninfer-tp2-two-5070ti.md`, раздел «Переход на DFlash2 в
базовый профиль (тикет 13, 2026-10-08)». Применено к файлам без коммита.

| Ось | Было | Стало |
|---|---|---|
| Артефакт | `neroued/Qwen3.8-27B-nvfp4-NInfer` (23.7 GB) | `glfenix/…-DFlash2NVFP4drafter-NInfer` (21.54 GB) |
| Движок | v0.4.5 | v0.4.6 (C++-дерево == v0.4.7, у v0.4.7 нет ассетов) |
| Спекуляция | `--spec mtp --draft-tokens 3` | `--spec dflash2 --draft-tokens 7 --lm-head-draft` |
| KV-пул | `--kv-capacity 495104` | `--kv-capacity auto --vram-headroom-mib 640` (без sweep) |
| Слоты | `--device-state-slots 3` | `--device-state-slots 4` (всего C+H=6) |
| Лимит вывода | `--default-max-tokens 32768` | `--default-max-tokens 16384` |

Не перенимались (остаются наши): `--host`/`--api-key`/`--port` (у нас
`127.0.0.1:8080` без ключа), `--pending-timeout-ms 600000`, `--tp 2
--devices 0,1`, `--kv-dtype nvfp4`, `--max-context 262144`,
`--max-concurrency 2`, Vision на device 0, `--embedding-host`. Весь
API-контракт llama-swap без изменений.

## Acceptance

Проверка по варианту B (см. research 0009, раздел сессии):

- [x] started: стартовая строка движка `capacity | KV 342 784, nvfp4, auto |
  free 708.7 MiB`. Пул ниже бумажного прогноза ≳ 2×~190k (факт ~171k/полоса),
  стартовый free ≥ 512 выполнен; под нагрузкой min free GPU1 264–278 MiB
  (порог не держится — решено оставить headroom 640, см. Comments);
- [x] `/health` 200, `/v1/models` отдаёт 7 алиасов (name «DFlash2, nvfp4 KV,
  262144 ctx, 2 lanes»);
- [x] короткий chat на `qwen3.8-27b` (600 токенов, `chat-medium`): `draft_n
  975 / draft_n_accepted 459` (47 %), decode ~235 tok/s;
- [x] `preserve_thinking`: `chat-medium` вырезает reasoning из истории
  (`prompt_n 25`), `agent-medium` оставляет (`prompt_n 74`);
- [x] effort из имени алиаса: instruct `prompt_n 22` (без thinking),
  `chat-low` 50, `chat-xhigh` 62 — инструкция дописывается в промпт;
- [x] Vision-smoke по системной иконке: `prompt_n 87`, ответ осмысленный;
- [x] цифры decode/приём драфта на коротком и длинном контексте дописаны
  в research 0009.

## Comments

2026-10-08: решения из grilling-сессии применены к `ninfer/Dockerfile`,
`ninfer/docker-compose.yaml`, `ninfer/fetch-model.sh`, `ninfer/config.yaml`,
`AGENTS.md`, `README.md`, `docs/research/0009`,
`docs/adr/0003-ninfer-profile-llama-swap.md`. Коммит не делался. Тикет 13
отвязан от тикета 05: 05 остаётся историей измерений DFlash2 на
официальном артефакте, вывод «отдельный профиль не заводим» устарел.

2026-10-10: начало выполнения. `docker compose --profile ninfer build` →
образ `llm-server/ninfer-tp2:v0.4.6` собран, SHA архива и `SHA256SUMS`
внутри сходятся. Скачивание glfenix-артефакта (curl, ~5.9 из 21.54 GiB)
прервано: пользователь выбрал перезагрузку хоста. Причина — полуобновлённый
драйвер (userspace 595.99.02 установлен, модуль ядра в работе 595.91.07,
`nvidia-persistenced` мёртв): новый GPU-контейнер не стартует до перезагрузки,
хост `nvidia-smi` уже сломан. До кача: `/opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/
qwen3_8_27b_nvfp4.ninfer` (докачка `curl -C -` тем же fetch-model.sh). После
перезагрузки: `./ninfer/fetch-model.sh` → `down --remove-orphans` →
`up -d --wait --wait-timeout 1800` → приёмка по чек-листу выше. Старый профиль
(v0.4.5) до перезагрузки работал, но стартовая строка показывала `free 254.9 MiB`
— ниже порога 512 на дисплейной GPU1.

2026-10-10: перезагрузка выполнена (вручную, `systemctl reboot` блокировался
block-ингибитором пользовательской сессии). После ребута: драйвер 595.99.02,
persistenced active, старый `llama-swap` (v0.4.5) автоподнялся; докачка
модели завершена, SHA `bfc05a70…` подтверждён; `docker rm -f llama-swap`
(старый контейнер не снимался штатным `down` — конфликт имени) →
`up -d --wait --wait-timeout 1800` → контейнер v0.4.6 healthy. Приёмка
по чек-листу выше пройдена (кроме двух оговорок): фактический пул
342784 (~171k/полоса) ниже прогноза ≳ ~190k/полоса; min free GPU1 под
нагрузкой 264–278 MiB — ниже порога 512. По решению пользователя
`--vram-headroom-mib` остаётся 640 (пул не урезаем); вариант подъёма до
~1020 с урезкой пула до ~300k задокументирован в research 0009 на случай
деградации десктопа. Коммит не делался.