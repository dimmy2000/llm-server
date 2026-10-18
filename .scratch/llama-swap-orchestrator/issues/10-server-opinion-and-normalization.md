# Остаточное серверное мнение: дефолт голого ID и нормализация контрактов

Type: grilling
Status: resolved
Blocked by: 03

## Question

Исследование контрактов показало, что строгое «у сервера нет мнения»
недостижимо, а «клиент владеет всем» технически возможно, но **не безвредно**.
Нужно решить, какое серверное мнение остаётся и где живёт нормализация.

Решить:

1. **Дефолт голого ID.** Сегодня `qwen3.8-27b` в llama/ninfer — non-thinking.
   Если убрать `setParamsByID`, голый ID станет thinking + `xhigh` на всех
   трёх профилях (дефолт шаблона). Оставляем ли серверный дефолт
   «instruct = без рассуждений» (задать на уровне движка:
   `--reasoning off`/`--no-thinking`/`--default-chat-template-kwargs`), или
   принимаем thinking+xhigh по умолчанию, или задаём нейтральный дефолт
   через set-if-undefined (`key?`)?
2. **Нормализация трёх контрактов.** Кто отвечает за расхождения:
   - `top_k: 0` — llama.cpp/vLLM «выключить», NInfer cap top-20;
   - `repetition_penalty ≠ 1` — NInfer `400`;
   - `reasoning_effort: high|minimal|max|adaptive` — llama.cpp/vLLM `500/400`;
   - разные поля ошибок и коды (`500` vs `400`).
   Оставляем ли **часть фильтров** в llama-swap как нормализующий слой, или
   весь риск на клиенте (тогда открытый контракт документируется)?
3. **Единый контракт.** Если фильтры убираются — зафиксировать и
   задокументировать «безопасное подмножество» параметров, которое
   безвредно для всех трёх backend'ов (таблица из отчёта 0013).
4. **Соотношение с задачей.** Пользователь просил «клиенты управляют
   настройками рассуждений»; уточнить, распространяется ли «клиент владеет
   всем» и на sampling, или sampling может остаться серверным.

Опора — отчёт `docs/research/0013-backend-request-contracts.md`
(сводная таблица и разделы о «безвредном» переносе).

## Answer

Разрешено живым обсуждением с человеком (HITL, 2026-10-17). Опора — отчёт
`docs/research/0013-backend-request-contracts.md`. Ссылки на факты из
репозиториев: `../llama-swap@a2796fb`, `../llama.cpp@62318cd57`.

Ключевая поправка к премисе тикета: **vLLM вне карты** (2026-10-17), поэтому
«три контракта» — это два, llama.cpp и NInfer. Все vLLM-расхождения
(`high`→400, имя поля `reasoning`) из решения выпадают.

### 1. Дефолт голого ID — дефолт шаблона, явного «instruct» нет

`setParamsByID` для reasoning не заводим; `--reasoning on` (llama.cpp) и
отсутствие `--no-thinking` (NInfer) остаются как есть. Голый `qwen3.8-27b` —
**thinking + effort `xhigh`** (дефолт шаблона) на обоих движках.

«Instruct» перестаёт быть серверным дефолтом и становится явным клиентским
запросом (`reasoning_effort: "none"` или
`chat_template_kwargs.enable_thinking: false`). Слово «instruct» уходит из
формулировок карты и тикетов 05/06/08.

Принятая цена: результат голого запроса теперь определяется движком и потому
различается (llama.cpp — свой sampling-пресет, NInfer — свой mode-aware).

### 2. Нормализация — тонкий страж в llama-swap

На обеих backend-моделях:

- `stripParams: "repetition_penalty"` — симметрично; единственный параметр,
  который нельзя выразить переносимо (NInfer `400` при значении ≠ 1,
  llama.cpp такого имени не знает вовсе).
- `useModelName: qwen3.8-27b` — обязателен на NInfer (`request.model` обязан
  совпасть с `--model-id`).

Больше llama-swap тело запроса не правит. Трансляцию имён фильтры не умеют
(`../llama-swap@a2796fb`, `internal/server/filters.go:130-171`: порядок
`useModelName → stripParams → setParams → setParamsByID`, есть только
strip/set, включая set-if-undefined `key?`), поэтому остальные расхождения —
на клиенте, а `top_k: 0` не стрипается и входит в документированное
подмножество как **запрещённый** (`top_k` ∈ `1..20`; на NInfer `0` — это
top-20 cap, а не «выключить»).

### 3. Безопасное подмножество — в ADR-0006 + README/AGENTS (тикет 08)

Отдельного клиентского документа не заводим: таблица живёт в ADR-0006 и в
разделе README/AGENTS «единый контракт» (тикет 08), там же —
«пресет sampling живёт в `cmd` движка». Содержимое — сводная таблица отчёта
0013 без vLLM:

Безвредно для обоих: `temperature` ∈ `[0,1]`, `top_p` ∈ `(0,1]`,
`top_k` ∈ `1..20`, `min_p` ∈ `[0,1]`, `presence_penalty`/`frequency_penalty` ∈
`[-2,2]`, `seed`, `max_tokens` ≥ 1, `reasoning_effort` ∈
`none|low|medium|xhigh` (плюс `high` — фолдится в `xhigh` обоими),
`chat_template_kwargs.{enable_thinking, preserve_thinking}` (bool).

Запрещено/непереносимо: `repetition_penalty` (стрипается), `top_k: 0`,
`reasoning_effort` вне словаря (llama.cpp `500`, NInfer `400`), а также фичи,
которые NInfer осознанно отклоняет, — `response_format: json_object`,
`logit_bias`, `logprobs`, `strict`, `parallel_tool_calls: false`, named tool
choice (`docs/serving.md:134-142`).

### 4. Sampling — дефолт на уровне движка, клиент может переопределить

- **llama.cpp**: пресет задаётся флагами в `cmd` (`--temp 1.0 --top-p 0.95
  --top-k 20 --min-p 0 --presence-penalty 0`) — CLI-значения это серверные
  дефолты, которые поля запроса перекрывают (`../llama.cpp@62318cd57`,
  `tools/server/server-schema.cpp:470`: «Sampling parameter defaults are loaded
  from the global server context (but individual requests can still override
  them)», `params.sampling = params_base.sampling`).
- **NInfer**: собственный mode-aware пресет не трогаем (thinking
  `1.0/0.95/20/0/0`, non-thinking `0.7/0.80/20/0/1.5`; `docs/serving.md:842-847`).
- **llama-swap**: sampling-фильтров нет (см. п. 2).
- **Reasoning**: остаётся полностью клиентским (п. 1).

Так «sampling серверный» реализуется без возврата фильтров в llama-swap, и
ответ вопроса 2 остаётся в силе. Следствия, принятые сознательно:

- голый ID (thinking) на llama.cpp получает thinking-пресет; non-thinking
  пресет `0.7/0.80/20/1.5` на llama.cpp недоступен как серверный дефолт
  (NInfer отдаёт его сам при `reasoning_effort: "none"`, llama.cpp — нет);
- `repeat_penalty 1.05` сегодняшнего llama-профиля не переносится (NInfer
  принимает только `1.0`) — конкретное значение решает тикет 05;
- opencode `top_k` в тело не шлёт (SDK помечает `top_k` unsupported,
  отчёт 0012), поэтому `top_k` на llama.cpp задаётся только серверной
  стороной; другой клиент может переопределить.

### Что это меняет в карте

- Заголовок карты и тикет 05: «instruct-endpoint» → «единый endpoint»;
  развилка «instruct vs нет мнения» в тикете 05 снята (решена здесь).
- Destination карты уточнён: reasoning — клиентский, sampling — серверный
  дефолт движка с клиентским переопределением, собственного мнения о
  reasoning у сервера нет.
- Fog-пункт «нужна ли отдельная клиентская спецификация» снят: решения —
  нет, таблица идёт в ADR-0006 + README (тикет 08).
- Тикет 08: ADR-0006 пишется без «instruct», включает таблицу безопасного
  подмножества и заметку про пресет в `cmd`.
- Тикет 06: формулировка ссылки на тикет конфига.

### Передано дальше

- **Тикет 05**: точные значения пресета в `cmd` llama.cpp (`repeat_penalty`:
  1.05 сегодня есть у llama, NInfer умеет только 1.0), состав `filters`
  (свести к `stripParams: repetition_penalty` + `useModelName`), `name`,
  `capabilities`, пины, совместимость с opencode.
- **Тикет 08**: таблица безопасного подмножества и формулировки ADR/README.

