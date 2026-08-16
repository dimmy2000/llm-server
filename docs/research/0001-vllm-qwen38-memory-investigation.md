# Исследование OOM и перезапусков vLLM с Qwen3.8-27B-NVFP4

Дата наблюдений: 2026-08-16.

## Краткий вывод

Основная причина сбоя - не исчерпание KV cache и не Docker OOM kill. На
`Worker_TP1`, работающем на GPU с графической сессией, закончилась память при
обработке двух запросов одним scheduler-шагом на 4096 токенов. Обычным
активациям BF16 понадобились блоки 68 и 136 MiB, когда физически свободными
оставались только 53-101 MiB. В момент сбоя KV cache был занят лишь на 15%.

После CUDA OOM процесс worker перестал отвечать, но API продолжал возвращать
`200` на `/health` почти пять минут. Это соответствует встроенному
`VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=300`: только после timeout EngineCore был
помечен мертвым, API завершился, а `restart: unless-stopped` перезапустил
контейнер. Один из последующих стартов отдельно не прошел проверку минимального
KV cache для контекста 122880.

Есть и независимая причина отказа клиентов. Текущий `vllm/config.yaml`
публикует model-ID `qwen3.8-27b`, тогда как `README.md` и `AGENTS.md` определяют
публичный ID как `qwen3.8`. Проверка first-party API `/v1/models` 2026-08-16
вернула только `qwen3.8-27b`; запрос с `model: qwen3.8` вернул `404 The model
qwen3.8 does not exist`, а короткая генерация с `qwen3.8-27b` и
`chat_template_kwargs.enable_thinking=false` успешно вернула `OK`. Это не
вызывает OOM или restart, но напрямую ломает клиентов со старым ID. Нужно либо
вернуть `served-model-name: qwen3.8` согласно контракту репозитория, либо
одновременно перенастроить клиентов и документацию.

Наиболее безопасная первая конфигурация для текущей машины с display-нагрузкой:

```yaml
max-model-len: 49152
max-num-seqs: 1
max-num-batched-tokens: 1024
enable-chunked-prefill: true
gpu-memory-utilization: 0.85
```

Это рекомендация для последующей проверки, а не примененное изменение. Во
время исследования конфигурация и работающий контейнер не изменялись и не
перезапускались.

## Область и воспроизводимость

### Исследованный стек

| Компонент | Точная версия или идентификатор |
|---|---|
| GPU | 2 x NVIDIA GeForce RTX 5070 Ti, по 16303 MiB |
| NVIDIA host | driver 595.84, CUDA API 13.2 по `docs/NVIDIA_SETUP.md` |
| OCI image | `vllm/vllm-openai:qwen38@sha256:4a2f33a884222f7049b983263ad9976f89452bb81affecf5b67d89ad35c1bc31` |
| Docker Hub tag | `qwen38`, manifest digest `sha256:4a2f...`, опубликован 2026-08-12 ([первичный API Docker Hub](https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/qwen38)) |
| vLLM package | `0.1.dev19754+g3a0914114` |
| OCI revision label | `3a0914114705fa38d4c3171d0746c1a6b6f10209` |
| PyTorch | `2.13.0+cu130` |
| Transformers | `5.15.0` |
| FlashInfer | `0.6.17` |
| compressed-tensors | `0.17.0` |
| Локальный checkpoint | `unsloth/Qwen3.8-27B-NVFP4`, локальный commit `9c73e2daee1d0fd494ffbd1d8753f2174a953796` |
| Базовая модель | `Qwen/Qwen3.8-27B`, commit `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0` |

OCI labels называют revision `3a0914...`, однако этого commit нет в публичном
`vllm-project/vllm`: GitHub API возвращает 422, а поиск commit возвращает ноль
результатов. Wheel также собран локально (`direct_url.json` указывает на
`file:///vllm-workspace/dist/...whl`). Поэтому точным источником поведения
сборки являются извлеченные из immutable image исходники в
`/tmp/opencode/vllm-image-src/vllm`.

Для проверяемых web-ссылок исходники сопоставлены с публичным commit vLLM
[`7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9`](https://github.com/vllm-project/vllm/commit/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9).
Ключевые config-файлы совпадают побайтно; релевантные memory-фрагменты
`gpu_worker.py` также совпадают, а отличия файла относятся к profiler backend.
Это точнее, чем ссылаться на плавающую ветку `main`, но публичный commit не
следует считать полным source revision образа.

Локальный commit Unsloth `9c73...` был создан командой super-squash 2026-08-14
и уже недоступен через Hugging Face. Текущий Hub revision -
[`16b6615af3548b88e2d8e382457bc705b00479cf`](https://huggingface.co/api/models/unsloth/Qwen3.8-27B-NVFP4).
Локальные факты о checkpoint ниже взяты именно из смонтированного read-only
каталога, а не приписаны текущей Hub-ревизии.

### Активная конфигурация

`vllm/config.yaml` задает:

```yaml
language-model-only: true
tensor-parallel-size: 2
disable-custom-all-reduce: true
max-model-len: 122880
max-num-seqs: 2
max-num-batched-tokens: 4096
enable-chunked-prefill: true
no-enable-prefix-caching: true
gpu-memory-utilization: 0.88
kv-cache-dtype: fp8
no-enable-flashinfer-autotune: true
```

Первый исследованный старт еще использовал `max-model-len=131072`; следующие
два старта использовали текущее unstaged-значение `122880`. Изменение model-ID
на `qwen3.8-27b` находится в index. Эти существующие изменения не создавались и
не корректировались в рамках исследования.

## Хронология инцидента

| Время UTC | Событие |
|---|---|
| 15:48:20 | Старт vLLM с `max_model_len=131072`, TP=2, batch tokens=4096, seqs=2. |
| 15:48:43 | Модель загрузилась, расход на rank составил `10.45 GiB`. Checkpoint в логах: `21.81 GiB`. |
| 15:48:48 | Для KV выделено около `2.11/2.13 GiB`; емкость `132578` токенов, concurrency для 131072 - `1.01x`. |
| 15:48:50 | CUDA graphs заняли `0.46 GiB`. На старте GPU0 имел 14.95 GiB free, display-GPU1 - 13.83 GiB free. |
| 15:51:13 | Два streaming POST получили HTTP 200, затем `Worker_TP1` получил серию CUDA OOM на выделениях 68/136 MiB. |
| 15:51:23-15:56:11 | Throughput стал нулевым, два запроса оставались `Running`, `/health` продолжал отвечать 200. |
| 15:56:13 | Через 300 секунд `sample_tokens` завершился timeout; EngineCore стал dead, streaming generator получил `EngineDeadError`. |
| 15:56:18 | API завершился; `restart: unless-stopped` запустил контейнер снова. |
| 15:58:07 | Старт с `max_model_len=122880` получил только `1.27 GiB` KV при требуемых `1.96 GiB`; оценка допустимого контекста - `78400`. Процесс завершился. |
| 15:58:18 | Следующий автоматический старт с теми же параметрами прошел; KV capacity - `131871` токен. |

Read-only `docker inspect` после инцидента показал:

```text
RestartCount=2 OOMKilled=false Status=running Health=healthy
```

Следовательно, контейнер не был убит Linux OOM killer. Сначала сломался GPU
worker внутри vLLM, затем завершился основной процесс, и только это активировало
Docker restart policy.

## Непосредственная причина CUDA OOM

Перед финальным timeout vLLM сохранил точный scheduler input:

```text
num_running_reqs=2
prompt_token_ids_len=12718
max_tokens=32000
num_scheduled_tokens={existing_request: 1, new_request: 4095}
total_num_scheduled_tokens=4096
kv_cache_usage=0.14942528735632188
```

Первый стек завершился на создании BF16 tensor формы `(4096, 8704)`:

```text
4096 * 8704 * 2 bytes = 71,303,168 bytes = 68 MiB
```

Второй стек завершился в обычном FlashInfer NVFP4 GEMM на output tensor формы,
соответствующей `(4096, 17408)`:

```text
4096 * 17408 * 2 bytes = 142,606,336 bytes = 136 MiB
```

Это не FlashInfer autotune: autotune был явно отключен и startup подтвердил
`Skipping FlashInfer autotune`. OOM произошел в штатном forward, где размер
активации прямо определяется `max_num_batched_tokens=4096`.

На GPU1 в сообщениях OOM оставалось 52.75-100.75 MiB. PyTorch одновременно
сообщал 321-415 MiB `reserved but unallocated`, поэтому фрагментация allocator
могла усилить проблему. Однако главный факт остается прежним: гарантированного
физического запаса не хватало даже для одного ожидаемого output tensor.
Официальная документация PyTorch 2.13 описывает
[`expandable_segments`](https://docs.pytorch.org/docs/2.13/notes/cuda.html#optimizing-memory-usage-with-pytorch-alloc-conf)
как экспериментальное средство для меняющихся batch sizes, а
`max_split_size_mb` - как last resort. Это возможные дополнительные
эксперименты, но не замена свободной VRAM.

## Почему запас оказался слишком мал

В этой сборке `gpu_memory_utilization` умножается на полную память устройства,
а не на текущую свободную память:

```python
requested_memory = ceil(total_memory * gpu_memory_utilization)
```

См. [`request_memory`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/worker/utils.py#L446-L466)
и описание
[`gpu_memory_utilization`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/cache.py#L69-L76).
На 15.47 GiB `0.88` означает budget `13.61 GiB`.

На display-GPU перед стартом было свободно 13.83 GiB. После резервирования
budget vLLM физический зазор до полной карты составлял примерно:

```text
13.83 - 13.61 = 0.22 GiB
```

Это меньше нескольких нормальных активаций forward и чувствительно к любому
росту памяти графической сессии. Для сравнения, GPU0 стартовал с 14.95 GiB free.

По исходникам доступный auto KV cache вычисляется из requested budget после
профилирования model/activation/CUDA graph memory, см.
[`determine_available_memory`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/worker/gpu_worker.py#L461-L612)
и
[`memory_profiling`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/utils/mem_utils.py#L233-L326).
Это расчет размера cache, а не жесткий runtime-лимит процесса. Изменение
занятости GPU после startup и недооцененный live working set могут привести к
выходу за физический предел.

Read-only снимок после восстановления подтверждает co-tenancy GPU1:

```text
GPU0: display disabled, VLLM::Worker_TP0 ~14110 MiB
GPU1: display enabled,  VLLM::Worker_TP1 ~14110 MiB
GPU1: telegram-desktop 148 MiB, ptyxis 52 MiB, gnome-calculator 13 MiB
```

Кроме перечисленных процессов память занимает сама графическая сессия и
драйвер. Наблюдаемая свободная память GPU1 менялась как минимум от 363 до
708 MiB уже после восстановления.

## Почему уменьшение только `max-model-len` недостаточно

`max_model_len` задает допустимую сумму prompt и output и минимальную KV
емкость, необходимую для хотя бы одного такого запроса. При недостатке памяти
vLLM сравнивает required KV с available KV и оценивает максимально допустимую
длину, см.
[`_check_enough_kv_cache_memory`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/core/kv_cache_utils.py#L731-L819).

При auto sizing vLLM продолжает заполнять доступный budget KV cache независимо
от более низкого admission limit. Поэтому уменьшение только
`max-model-len: 131072 -> 122880` не высвободило runtime-headroom: успешный
повторный старт все равно создал cache на 131871 токен.

Уменьшать `max_model_len` нужно совместно с уменьшением
`gpu_memory_utilization` или явным `kv_cache_memory_bytes`. Иначе меняется
проверка допустимости запросов, но не общий memory budget.

Для этой hybrid-модели цена KV также ступенчатая. vLLM выровнял attention block
до 1568 токенов, чтобы page был не меньше Mamba/Gated DeltaNet state page, см.
[`platforms/interface.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/platforms/interface.py#L853-L940).
Линейная интерполяция GiB на токен ниже пригодна лишь для выбора стартовой
точки, а не для доказательства, что конкретная длина пройдет startup.

## Проверка гипотез

| Гипотеза | Наблюдение | Вывод |
|---|---|---|
| KV cache закончился | Usage 14.94%, capacity 132578 | Опровергнуто для runtime OOM |
| Слишком большой scheduler batch | Ровно 4096 scheduled tokens; failed tensors линейно имеют первую размерность 4096 | Подтверждено |
| Два запроса усилили пик | `Running: 2`, один decode token плюс 4095 prefill tokens | Подтверждено |
| Display workload отнял запас | Startup free 13.83 против 14.95 GiB; OOM только TP1 | Подтверждено как усилитель |
| FlashInfer autotune вызвал OOM | Autotune отключен; стек в обычном `mm_fp4` output allocation | Опровергнуто |
| Linux/Docker OOM kill | `OOMKilled=false`; Python `torch.OutOfMemoryError` | Опровергнуто |
| `max_model_len` вызвал runtime OOM | Активные последовательности были намного короче, KV занят на 15% | Опровергнуто как непосредственная причина |
| `max_model_len` вызвал restart-loop startup | 1.27 GiB available против 1.96 GiB required для 122880 | Подтверждено для одного повторного старта |
| CUDA allocator fragmentation | 321-415 MiB reserved/unallocated при failed allocation 68/136 MiB | Возможный дополнительный фактор |
| Vision encoder расходует VRAM | Логи: text-only; tower автоматически заменяется missing stage при нулевых modality limits | Опровергнуто |
| MTP расходует VRAM | `speculative_config=None`; loader пропускает `mtp.*` | Опровергнуто |

## Значение параметров для этого инцидента

| Параметр | Реальное действие | Решение |
|---|---|---|
| `max-num-batched-tokens` | Максимум токенов одного iteration; в инциденте напрямую создал BF16 outputs 68/136 MiB | Снизить первым до 1024 |
| `max-num-seqs` | Максимум одновременно обрабатываемых sequences; не ограничивает размер одного prefill chunk | Снизить до 1 вместе с batch tokens |
| `gpu-memory-utilization` | Определяет executor/KV budget от total VRAM; не является runtime hard cap | Снизить до 0.85 на display-системе |
| `max-model-len` | Admission limit prompt+output и минимально требуемая KV capacity | Снизить совместно с memory budget |
| `kv-cache-memory-bytes` | Фиксированный KV размер на GPU, полностью игнорирует `gpu_memory_utilization` ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/cache.py#L180-L187)) | Не использовать первым при изменчивой внешней нагрузке |
| `enforce-eager` | Отключает CUDA graphs и всегда выполняет eager PyTorch ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/model.py#L210-L241)) | Fallback, если длинный контекст важнее throughput |
| `kv-cache-dtype: fp8` | Снижает размер attention KV; может влиять на точность без корректных scales | Оставить, checkpoint содержит `kv_cache_scheme` |
| Prefix caching | Переиспользует уже выделенные blocks, но не создает гарантированный runtime-headroom | Не включать как исправление OOM |
| `kv-offloading-size` | Добавляет CPU buffer для offload KV ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/cache.py#L189-L198)) | Не поможет activation OOM при 15% KV usage |
| `cpu-offload-gb` | Offload весов на CPU на GPU; данные нужны через CPU-GPU interconnect при каждом forward ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/offload.py#L15-L32)) | Только отдельный эксперимент с latency benchmark |
| `tensor-parallel-size: 2` | Делит checkpoint 21.81 GiB между двумя 16 GiB GPU | Оставить; TP=1 не помещает модель |
| `language-model-only: true` | Обнуляет modality limits ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/multimodal.py#L97-L104)); tower components автоматически пропускаются ([source](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/model_executor/models/interfaces.py#L296-L337)) | Оставить |

Определения scheduler-параметров находятся в первичном
[`SchedulerConfig`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/config/scheduler.py#L49-L76).
Официальная страница vLLM также рекомендует уменьшать context/batch и при
необходимости отключать CUDA graphs: [Conserving Memory, developer preview,
2026-07-09](https://docs.vllm.ai/en/latest/configuration/conserving_memory/).

## Приоритетные изменения

### P0. Согласовать публичный model-ID

Для восстановления существующих клиентов вернуть задокументированный ID:

```yaml
served-model-name:
  - qwen3.8
```

Альтернатива - оставить `qwen3.8-27b`, но тогда все клиенты, `README.md` и
`AGENTS.md` должны быть изменены вместе. Это отдельное исправление API-контракта
и не заменяет memory-настройки ниже.

### P0. Убрать внешнюю нагрузку с TP1, если это возможно

Самое эффективное исправление без потери model context и throughput - сделать
обе GPU dedicated compute devices: перенести графическую сессию на iGPU/другую
GPU либо закрыть GPU-приложения до запуска vLLM. Разница startup free между
GPU0 и GPU1 была 1.12 GiB, что значительно больше failed allocations.

Если display-сессия обязательна, перейти к следующему профилю.

### P0. Консервативный validation profile для display-GPU

Предлагаемый первый тест:

```yaml
max-model-len: 49152
max-num-seqs: 1
max-num-batched-tokens: 1024
enable-chunked-prefill: true

gpu-memory-utilization: 0.85
kv-cache-dtype: fp8
```

Обоснование:

- Переход `0.88 -> 0.85` уменьшает budget примерно на
  `0.03 * 15.47 = 0.46 GiB`, увеличивая физический запас display-GPU примерно
  с 0.22 до 0.68 GiB при том же startup co-tenant usage.
- Переход `4096 -> 1024` уменьшает конкретные failed output tensors с 68/136
  MiB примерно до 17/34 MiB. Это точная линейная оценка только для показанных
  shapes, не для полного activation peak.
- `max-num-seqs: 1` исключает сочетание двух running requests, наблюдавшееся в
  инциденте. Второй запрос должен ждать scheduler, а не выполняться параллельно.
- По startup error 122880 токенов требовали 1.96 GiB KV. Линейная нижняя оценка
  для 49152 составляет около 0.78 GiB; реальное значение будет округлено по
  hybrid blocks размером 1568 токенов.
- Наблюдавшийся запрос просил `12718 + 32000 = 44718` токенов. Limit 49152
  сохраняет возможность принять такой запрос, в отличие от 32768.

Если первый cold start после изменения compile shape все равно сообщает, что
KV недостаточно, безопасный fallback - `max-model-len: 32768`, а не повышение
`gpu-memory-utilization`.

### P1. Расширять контекст только после стабильного теста

После прохождения критериев ниже повышать только `max-model-len`, по одному
шагу:

```text
49152 -> 65536 -> 98304
```

На каждом шаге ориентироваться на фактические startup-строки `Available KV
cache memory`, `GPU KV cache size` и `Maximum concurrency`. Не возвращать
одновременно `max-num-seqs: 2` и 122880/131072: тогда будет невозможно понять,
какое изменение вернуло OOM.

### P1. Вариант, если 122880 обязательно

Отдельно проверить профиль с меньшим batch, одной sequence и eager mode:

```yaml
max-model-len: 122880
max-num-seqs: 1
max-num-batched-tokens: 1024
enable-chunked-prefill: true
gpu-memory-utilization: 0.85
enforce-eager: true
```

`enforce-eager` убирает наблюдавшиеся 0.46 GiB CUDA graph memory и может
позволить разместить требуемые 1.96 GiB KV при меньшем общем budget. Цена -
снижение throughput и необходимость нового benchmark. Auto KV sizing может
занять освобожденную память, поэтому eager mode не заменяет снижение
`gpu-memory-utilization`.

Этот вариант менее надежен, чем 49152, и может быть отвергнут startup-проверкой.
В таком случае не повышать utilization до 0.91, несмотря на startup-подсказку:
это восстановит KV capacity ценой того самого runtime-headroom, которого не
хватило при инциденте.

### P2. Сократить период зависшего API

В сборке default равен 300 секундам, а `execute_model` и `sample_tokens`
используют этот timeout. Публичный сопоставленный source:

- [`VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=300`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/envs.py#L228-L235)
- [`multiproc_executor.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/executor/multiproc_executor.py#L327-L356)

После исправления памяти можно отдельно проверить более короткое значение в
Compose, например:

```yaml
environment:
  VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS: "120"
```

Это containment, а не memory fix. Слишком низкое значение может ошибочно убить
действительно долгий kernel/compile step, поэтому сначала нужно измерить
максимальную длительность нормального iteration.

## Почему текущий healthcheck не предотвращает зависание

Endpoint `/health` возвращает 503 только после `EngineDeadError`, см.
[`health.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/entrypoints/serve/instrumentator/health.py#L22-L33).
До истечения worker RPC timeout объект AsyncLLM еще не был помечен `errored`,
поэтому endpoint продолжал отдавать 200.

Кроме того, Docker healthcheck только устанавливает состояние
healthy/unhealthy. Обычная Compose restart policy применяется, когда контейнер
завершается. Это следует из двух первичных документов Docker:

- [`healthcheck` в Compose Specification](https://docs.docker.com/reference/compose-file/services/#healthcheck)
- [`unless-stopped` и условия restart policy](https://docs.docker.com/engine/containers/start-containers-automatically/#use-a-restart-policy)

Уменьшение `retries` не перезапустит зависший контейнер само по себе и не
поможет, пока `/health` ложно отвечает 200. Если нужен жесткий SLA, после
стабилизации памяти потребуется внешний watchdog, проверяющий завершение
минимальной генерации или progress metrics, а не только TCP/HTTP health.

## Что не следует включать как исправление

### MTP

Checkpoint содержит `model_mtp.safetensors`, а config базовой модели сообщает
`mtp_num_hidden_layers: 1`. Но runtime явно вывел `speculative_config=None`, и
обычный loader пропускает `mtp.*`, см.
[`qwen3_5.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/model_executor/models/qwen3_5.py#L423-L428).
MTP сейчас не причина расхода памяти. Его включение добавит draft weights,
state и activation pressure, поэтому до устранения OOM оно противопоказано.

### TurboQuant

TurboQuant уменьшает attention KV, но инцидент произошел при 15% KV usage и на
BF16 activation allocation. В этой сборке preset-комментарии заявляют
деградацию perplexity от `+1.17%` до `+20.59%`, а для hybrid-моделей отключена
boundary protection, см.
[`TurboQuantConfig`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/model_executor/layers/quantization/turboquant/config.py#L45-L86)
и
[`hybrid handling`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/model_executor/layers/quantization/turboquant/config.py#L177-L202).
Это не безопасное минимальное исправление.

### `swap-space`

В исходниках установленной сборки аргумент `swap_space` отсутствует. Вместо
него есть отдельные `kv_offloading_size` и weight `cpu_offload_gb` с другой
семантикой. Добавлять устаревший параметр не следует.

### Простое повышение `gpu-memory-utilization`

Startup error предлагает увеличить utilization, потому что рассматривает
только минимальную KV capacity. Для данного инцидента это локально устраняет
startup-проверку, но уменьшает физический запас runtime и повышает вероятность
повторного activation OOM. На display-GPU это неверное направление изменения.

## Замечание о startup-подсказке `kv-cache-memory`

После успешного старта логи предлагали около 1.50-1.53 GiB fixed KV для
requested budget, хотя auto cache уже использовал 2.11-2.13 GiB. В точном
source сборки `peak_activation_memory` уже включает CUDA graph estimate, после
чего post-capture suggestion еще раз прибавляет фактическую graph memory и
150 MiB buffer:

- включение estimate: [`gpu_worker.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/worker/gpu_worker.py#L507-L549)
- формирование suggestion: [`gpu_worker.py`](https://github.com/vllm-project/vllm/blob/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9/vllm/v1/worker/gpu_worker.py#L736-L792)

Поэтому эта подсказка в dev-сборке выглядит консервативной примерно на размер
CUDA graph pool. Значение 1.5 GiB можно исследовать как безопасный fixed cap с
контекстом до 64K, но нельзя считать его независимым доказательством точного
budget. Fixed cap также перестает адаптироваться к изменению свободной памяти
display-GPU.

## План проверки после согласованного изменения

Перед переключением профиля следовать обязательному порядку репозитория:

```bash
docker compose --profile llama --profile vllm down --remove-orphans
docker compose config
docker compose --profile vllm up -d --wait --wait-timeout 1800
```

Проверить startup без фильтрации ошибок:

```bash
docker compose --profile vllm logs vllm-server
docker inspect --format 'restart={{.RestartCount}} oom={{.State.OOMKilled}} status={{.State.Status}} health={{.State.Health.Status}}' vllm-server
nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,display_active --format=csv
```

Проверить API и фактически опубликованный model-ID:

```bash
curl --fail http://localhost:8080/health
curl --fail http://localhost:8080/v1/models
```

Затем повторить наблюдавшийся workload: prompt около 12718 токенов,
`max_tokens=32000`, сначала одним клиентом, затем двумя одновременно. При
`max-num-seqs=1` второй запрос должен ждать, а не увеличивать running batch.
Для streaming необходимо дождаться завершающего `[DONE]`; сам HTTP 200 не
считается успехом.

### Критерии успеха

- Первый cold start после изменения завершается без второго restart.
- `GPU KV cache size` не меньше `max-model-len`, а startup не предлагает
  поднять utilization для выбранной длины.
- На display-GPU под пиковым workload стабильно остается не менее 512 MiB
  физически свободной памяти.
- Оба последовательных и два одновременно отправленных streaming-запроса
  завершаются `[DONE]`; второй может ждать scheduler.
- В логах нет `torch.OutOfMemoryError`, `EngineDeadError`, `RPC call ... timed
  out` и повторяющихся `No available shared memory broadcast block`.
- `/health` остается 200, throughput не зависает на нуле при `Running > 0`.
- `RestartCount` не меняется минимум 30 минут нагрузки и во время длинного
  ответа.

### Порядок дальнейшего расширения

1. Зафиксировать стабильность 49152/1/1024/0.85.
2. Повысить только `max-model-len` до 65536 и повторить cold start и нагрузку.
3. При необходимости проверить 98304 либо отдельный eager-профиль 122880.
4. Только после этого вернуть `max-num-seqs: 2`, не меняя одновременно другие
   параметры.
5. MTP, TurboQuant, prefix caching и FlashInfer autotune проверять отдельными
   экспериментами с quality и длительными streaming-тестами.

## Первичные источники

- Docker Hub API для immutable image tag:
  <https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/qwen38>
- Сопоставленный публичный source commit vLLM:
  <https://github.com/vllm-project/vllm/commit/7aa248fcfef5ba7a6bfb0ce314e328ce63abb9f9>
- vLLM developer docs, Conserving Memory, обновлено 2026-07-09:
  <https://docs.vllm.ai/en/latest/configuration/conserving_memory/>
- vLLM engine arguments:
  <https://docs.vllm.ai/en/latest/configuration/engine_args/>
- Qwen3.8-27B model card, commit `1d4bf0...`:
  <https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/README.md>
- Qwen3.8-27B config, commit `1d4bf0...`:
  <https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/config.json>
- Текущая first-party metadata квантованного checkpoint Unsloth:
  <https://huggingface.co/api/models/unsloth/Qwen3.8-27B-NVFP4>
- PyTorch 2.13 CUDA allocator documentation:
  <https://docs.pytorch.org/docs/2.13/notes/cuda.html#optimizing-memory-usage-with-pytorch-alloc-conf>
- Docker restart policies:
  <https://docs.docker.com/engine/containers/start-containers-automatically/#use-a-restart-policy>
- Docker Compose healthcheck:
  <https://docs.docker.com/reference/compose-file/services/#healthcheck>

## Прочитанные локальные материалы

- `AGENTS.md`
- `README.md`
- `docker-compose.yaml`
- `vllm/docker-compose.yaml`
- `vllm/config.yaml`
- `docs/NVIDIA_SETUP.md`
- `/opt/models/Qwen3.8-27B-NVFP4/config.json`
- `/opt/models/Qwen3.8-27B-NVFP4/generation_config.json`
- `/opt/models/Qwen3.8-27B-NVFP4/model.safetensors.index.json`
- `/opt/models/Qwen3.8-27B-NVFP4/preprocessor_config.json`
- `/opt/models/Qwen3.8-27B-NVFP4/README.md`
- Извлеченный source установленного image в
  `/tmp/opencode/vllm-image-src/vllm`, включая `config/*`,
  `v1/worker/gpu_worker.py`, `utils/mem_utils.py`,
  `v1/core/kv_cache_utils.py`, `v1/executor/multiproc_executor.py`,
  `model_executor/models/qwen3_5.py` и
  `model_executor/models/interfaces.py`.
- Полный read-only Docker log, сохраненный инструментом в
  `/home/dimmy/.local/share/opencode/tool-output/tool_00b616ec1001XyqvaO7OZ7LHlq`.
