# Применимость Reddit-рекомендаций Qwen3.6 NVFP4/MTP к локальному Qwen3.8-27B

Дата среза: 2026-08-16.

Статус: исследование. Конфигурация, контейнеры и runtime в рамках работы не
изменялись.

## Краткий вывод

Конфигурацию из Reddit нельзя переносить целиком. Исходный запуск использовал
одну RTX 5090 с 32 GB непрерывной VRAM, Qwen3.6 другого автора, другой
quantization artifact, TP1 и другую сборку vLLM. Локальный профиль использует
Qwen3.8, две RTX 5070 Ti по 16 GB, TP2 через PCIe Host Bridge без P2P и
графическую нагрузку на GPU1
([Reddit-пост](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/),
`docs/NVIDIA_SETUP.md:3-7,52-61`, `vllm/config.yaml:1-22`).

Приоритет рекомендациям обсуждения меняет очередь экспериментов:

1. Prefix caching следует поднять из общего запрета до отдельного A/B-теста на
   текущем image, но только с выключенным speculative decoding.
2. MTP следует поднять из отложенной оптимизации до приоритетного isolated
   A/B-теста на текущем image при неизменных `max-num-seqs: 1` и выключенном
   prefix cache. Проверять нужно MTP1, MTP2 и MTP3; MTP3 остается целевым
   вариантом из Reddit и официального recipe, а не заранее отвергнутым режимом.
3. Correctness fix vLLM
   [#51812](https://github.com/vllm-project/vllm/pull/51812) остается gate перед
   повышением concurrency, смешанным MTP/prefix-cache workload и production
   rollout, но affected mixed-request layout недостижим при одной running
   sequence.
4. `performance-mode: interactivity` следует проверять только после включения
   MTP: без MTP оба режима создают одинаковые CUDA graph sizes `[1, 2]`.

Приоритет Reddit не перевешивает прямые локальные измерения. Context 200K,
`gpu-memory-utilization: 0.90-0.95` и scheduler batch 4096-8192 следует
отклонить: локальный batch 4096 уже вызвал activation OOM на display-GPU, а
контекст 65536 не прошел cold-start при безопасном memory budget
(`docs/research/0001-vllm-qwen38-memory-investigation.md:131-169`,
`README.md:66-79`).

Рекомендуемая последовательность:

1. Сохранить текущий профиль как контрольную точку.
2. Проверить prefix caching без MTP.
3. Вернуть prefix cache в off и провести isolated sweep MTP1 -> MTP2 -> MTP3
   при `max-num-seqs: 1`.
4. Найти immutable vLLM image, содержащий #51812, и подтвердить на нем baseline
   перед production rollout или повышением concurrency.
5. Для выбранного MTP depth отдельно проверить `performance-mode: interactivity`.
6. Только после раздельного успеха проверить сочетание MTP и prefix caching,
   предпочтительно уже на image с #51812.

## Область исследования

Проверялось, какие настройки и выводы из обсуждения
[Qwen3.6 27B NVFP4 + MTP on a single RTX 5090: 200k context working in
vLLM](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)
применимы к текущему профилю:

- модель `Qwen3.8-27B-NVFP4`;
- две RTX 5070 Ti по 16 GB;
- `tensor-parallel-size: 2`;
- display-нагрузка на GPU1;
- pinned image `vllm/vllm-openai:qwen38`;
- публичный model-ID `qwen3.8-27b`.

Текущие значения взяты из `vllm/config.yaml:1-32` и
`vllm/docker-compose.yaml:1-35`. Hardware и topology зафиксированы в
`docs/NVIDIA_SETUP.md:3-7,52-61`.

Обозначения:

- **Факт** - подтвержден локальным artifact/log или первичным upstream-источником.
- **Вывод** - инженерное следствие из подтвержденных фактов.
- **Неизвестно** - требует отдельного запуска на текущем hardware и workload.

## Источники и ограничения Reddit

Технические свойства vLLM, модели и GPU проверялись по официальной
документации, исходному коду, model card, immutable revisions и локальным
runtime logs. Reddit используется как первичный источник того, что именно
предлагали и измеряли участники, но не как доказательство свойств vLLM.

Обычный Reddit JSON endpoint и `old.reddit.com` на дату доступа возвращали
`403`. First-party
[oEmbed](https://www.reddit.com/oembed?url=https%3A%2F%2Fwww.reddit.com%2Fr%2FLocalLLaMA%2Fcomments%2F1t5dya8%2Fqwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k%2F)
и embed-страница подтверждали post и автора. Для удаленного текста применялся
[Arctic Shift snapshot](https://arctic-shift.photon-reddit.com/api/posts/ids?ids=1t5dya8)
только как архивный transport. Все технические выводы из архивного текста
перепроверены по источнику, который владеет соответствующим кодом или
artifact.

Основные прямые Reddit permalink:

- основной post:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/>;
- исправленный context и MTP sweep:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okacrd2/>;
- AutoRound:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/ok9gppj/>;
- nightly-команда:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/oki4fml/>;
- Cobra/Genesis stack:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okch4q7/>;
- исправление ошибочной single/dual GPU таблицы:
  <https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okb2ryb/>.

Reddit-числа ниже являются self-reported результатами. Они не воспроизводились
на локальной машине и не считаются benchmark текущего профиля.

## Текущая локальная baseline

### Конфигурация

`vllm/config.yaml:1-31` задает:

```yaml
model: /models/Qwen3.8-27B-NVFP4
served-model-name:
  - qwen3.8-27b
model-impl: vllm

language-model-only: true
tensor-parallel-size: 2
disable-custom-all-reduce: true

max-model-len: 49152
max-num-seqs: 1
max-num-batched-tokens: 1024
enable-chunked-prefill: true
no-enable-prefix-caching: true

gpu-memory-utilization: 0.85
kv-cache-dtype: fp8
no-enable-flashinfer-autotune: true

reasoning-parser: qwen3
enable-auto-tool-choice: true
tool-call-parser: qwen3_xml
```

Compose использует immutable manifest
`vllm/vllm-openai:qwen38@sha256:4a2f33a884222f7049b983263ad9976f89452bb81affecf5b67d89ad35c1bc31`
(`vllm/docker-compose.yaml:1-28`). Docker Hub API подтверждает tag, digest и
дату публикации
([first-party API](https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/qwen38)).

Runtime log фиксирует пакет `0.1.dev19754+g3a0914114`,
`speculative_config=None`, TP2, context 49152, FP8 KV, включенный chunked
prefill и выключенный prefix cache
(`/home/dimmy/.local/share/opencode/tool-output/tool_00bf0a21b0027syRx4YDXKUR9M:17`).

### Hardware и topology

| Параметр | Локальное значение | Источник |
|---|---|---|
| GPU | 2 x RTX 5070 Ti, по 16 GB | `docs/NVIDIA_SETUP.md:3-7` |
| Compute capability | Blackwell sm_120 | `docs/NVIDIA_SETUP.md:3-7` |
| GPU interconnect | PCIe Host Bridge (`PHB`) | `docs/NVIDIA_SETUP.md:52-61` |
| P2P | `CNS`; отключен через `NCCL_P2P_DISABLE=1` | `docs/NVIDIA_SETUP.md:52-61`, `vllm/docker-compose.yaml:21-27` |
| Tensor parallelism | 2 | `vllm/config.yaml:10-12` |
| Display workload | GPU1 | `docs/research/0001-vllm-qwen38-memory-investigation.md:171-214` |

Две карты по 16 GB не образуют один 32 GB address space. Target и MTP draft
при TP2 выполняют межранговые операции через PHB, тогда как исходный Reddit
запуск был single-GPU. Это не запрещает MTP, но не позволяет переносить его
throughput uplift без локального A/B (`docs/NVIDIA_SETUP.md:52-61`,
`/tmp/opencode/vllm-image-src/vllm/config/speculative.py:1263-1296`,
[Reddit-пост](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)).

### Подтвержденный runtime

Последний успешный baseline startup зафиксировал:

| Показатель | Значение | Первичный источник |
|---|---:|---|
| Model load на rank | 10.45 GiB | runtime log, line 54 |
| Peak activation profile | 0.56 GiB | runtime log, lines 86, 89 |
| CUDA graph pool | 0.44 GiB | runtime log, lines 85, 88 |
| KV cache | 1.96 GiB на GPU | runtime log, lines 72, 86, 89 |
| KV capacity | 113751 токен | runtime log, line 74 |
| Startup free GPU0 | 14.97 GiB | runtime log, line 89 |
| Startup free GPU1 | 14.62 GiB | runtime log, line 86 |
| GDN decode | Triton | runtime log, line 41 |
| Main attention | FlashInfer | runtime log, line 43 |
| NVFP4 GEMM | `FlashInferCutlassNvFp4LinearKernel` | runtime log, line 42 |

Здесь runtime log означает
`/home/dimmy/.local/share/opencode/tool-output/tool_00bf0a21b0027syRx4YDXKUR9M`.
В длинном тесте второй одновременный request оставался `Waiting: 1`, а один
активный decode стабилизировался примерно на 54-56 tok/s
(тот же log, lines 174-311). Это локальная контрольная точка, а не
стандартизованный benchmark.

Предыдущий профиль с двумя sequences и batch 4096 получил allocations 68 и
136 MiB при 52.75-100.75 MiB физически свободной VRAM на GPU1. Scheduler dump
показывал 4096 scheduled tokens и лишь 14.94% использования KV cache
(`/home/dimmy/.local/share/opencode/tool-output/tool_00b616ec1001XyqvaO7OZ7LHlq:211,423,560-561`).
Это прямое локальное доказательство против возврата batch 4096 и повышения
memory utilization.

## Что проверял Reddit-пост

### Основной запуск

| Параметр | Значение в обсуждении |
|---|---|
| GPU | 1 x RTX 5090, 32 GB |
| Model artifact | `Peutlefaire/Qwen3.6-27B-NVFP4` |
| vLLM | `0.20.1.dev0+g88d34c640.d20260502` |
| Commit | `88d34c6409e9fb3c7b8ca0c04756f061d2099eb1` |
| Tensor parallelism | 1 |
| Исходный `max-model-len` | 230400 |
| Публично проверенная глубина | около 200000 токенов |
| `gpu-memory-utilization` | 0.95 |
| `max-num-batched-tokens` | 4096 |
| `max-num-seqs` | 1 |
| KV cache | FP8 E4M3 |
| Speculative decoding | native MTP3 |
| Prefix caching | включен |
| Performance mode | `interactivity` |
| Attention | принудительно FlashInfer |
| Vision | выключен |

Источник таблицы - основной
[post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/).
Artifact закреплен на Hugging Face revision
[`71d4621`](https://huggingface.co/Peutlefaire/Qwen3.6-27B-NVFP4/tree/71d46214a7ef0f1205dd536f63203e5b51b415ee).

Автор сообщил около 8.3 GiB доступного KV cache и около 30.5 из 32.6 GB общей
GPU memory в использовании. Этот запас относится к машине без TP2; post не
документирует display co-tenancy, сопоставимую с локальной GPU1. Перенос `0.95`
на локальную GPU1 поэтому не обоснован
([post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/),
`docs/research/0001-vllm-qwen38-memory-investigation.md:171-214`).

### 200K и MTP

Для десяти self-reported запусков с `llama-benchy 0.3.7`, prompt processing
2048, generation 480, concurrency 1 и cache off автор привел первые пять
метрик ниже. Acceptance, acceptance length и max KV usage опубликованы отдельно
как telemetry всего benchmark run:

| Метрика | Reddit result | Scope |
|---|---:|---|
| Успешные запуски | 10/10 | ten-run stability series |
| Mean prefill | 2883 tok/s | ten-run stability series |
| Mean generation | 73.6 tok/s | ten-run stability series |
| Generation stddev | 13.5 tok/s | ten-run stability series |
| Mean TTFT | 70.2 s | ten-run stability series |
| MTP acceptance | 42.7% | telemetry всего benchmark run |
| Mean acceptance length | 2.28 | telemetry всего benchmark run |
| Max KV usage | 88% | telemetry всего benchmark run |

Источник чисел - основной
[post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/).
Высокий разброс и различия harness/prompt/output не позволяют напрямую
сравнивать 73.6 tok/s с локальными 54-56 tok/s.

В follow-up автор исправил target context на 204800 и опубликовал sweep:

| Variant | Generation на 200K | TTFR |
|---|---:|---:|
| Thinking off, MTP3, batch 4096 | 78.15 tok/s | 69.67 s |
| Thinking on, MTP2, batch 4096 | 76.74 tok/s | 70.08 s |
| Thinking off, MTP2, batch 4096 | 71.46 tok/s | 70.17 s |
| Thinking off, MTP3, batch 8192 | 66.62 tok/s | 66.87 s |
| Thinking off, MTP3, batch 6144 | 63.80 tok/s | 67.19 s |

В той же ветке MTP3 с thinking on завершился CUDA OOM. Увеличение batch до
6144/8192 не улучшило generation throughput даже на 5090. Thinking и MTP depth
менялись одновременно в части сравнений, поэтому из таблицы нельзя выводить
причинное влияние thinking на acceptance
([follow-up `okacrd2`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okacrd2/)).

### Prefix caching

Для повторного идентичного 200K prefix автор сообщил:

| Запуск | Generation | TTFT |
|---|---:|---:|
| Cold | 65.2 tok/s | 68.8 s |
| Warm | 59.6 tok/s | 2.8 s |

Self-reported результат показывает потенциально сильное снижение TTFT при
повторном точном prefix. Он не доказывает ускорение уникальных prompts или
decode throughput
([основной post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)).

### Альтернативные artifacts и patches

Комментарий про AutoRound относится к Qwen3.6 W4A16 и другому runtime stack.
Immutable model card рекомендует MTP1 и описывает short-prompt тест на одной
RTX 5090, а не текущий Qwen3.8 checkpoint
([Reddit `ok9gppj`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/ok9gppj/),
[AutoRound card, revision `c3aea2d`](https://huggingface.co/Lorbus/Qwen3.6-27B-int4-AutoRound/blob/c3aea2d531678621989e5e2db034e32b22536e79/README.md)).

Предложения TurboQuant/GGUF меняют precision, engine или model artifact. Они
не устраняют подтвержденный локальный activation OOM при 15% KV usage и потому
не являются настройкой текущего baseline
(`docs/research/0001-vllm-qwen38-memory-investigation.md:131-169,413-433`).

Сторонний `CobraPhil/qwen36-27b-single-5090` не является воспроизводимой
основой текущего профиля: он относится к Qwen3.6/5090, подтягивает плавающие
patches, а README и validation scripts расходятся по проверенному context и
tool calling
([repository, commit `fe6b030`](https://github.com/CobraPhil/qwen36-27b-single-5090/tree/fe6b0305d54f3f7c5554520623efa8b6b3040ef2),
[issue #4](https://github.com/CobraPhil/qwen36-27b-single-5090/issues/4),
[Reddit `olr38av`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/olr38av/)).

Удаленный комментарий `ok99kzv` первоначально представлял данные 5060 Ti как
single/dual comparison. Автор позже уточнил, что baseline и оба MTP-запуска
фактически выполнялись на двух GPU. Поэтому исходные labels не используются
как evidence
([исправление `okb2ryb`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okb2ryb/)).

## Различия model artifacts

Локальный checkpoint имеет `total_size: 23417592488` bytes в
`/opt/models/Qwen3.8-27B-NVFP4/model.safetensors.index.json:1-4`, то есть около
21.81 GiB до учета runtime allocations. Это уже больше 16 GB одной RTX 5070 Ti,
поэтому TP1 не является доступной настройкой текущего artifact.

Локальный `config.json` описывает mixed compressed-tensors quantization:
NVFP4 применяется преимущественно к MLP, тогда как attention и многие GDN
projections используют FP8; `linear_attn.in_proj_a`, `in_proj_b` и ряд других
GDN tensors находятся в ignore list
(`/opt/models/Qwen3.8-27B-NVFP4/config.json:12-87,201-393`). Reddit artifact
Qwen3.6 имеет другую layout/quantization revision. Поэтому VRAM, MTP acceptance
и context capacity нельзя переносить только по одинаковому числу `27B`
([Reddit model revision](https://huggingface.co/Peutlefaire/Qwen3.6-27B-NVFP4/tree/71d46214a7ef0f1205dd536f63203e5b51b415ee)).

Локальный model config содержит один MTP layer:

```json
"mtp_num_hidden_layers": 1,
"mtp_use_dedicated_embeddings": false
```

Источник: `/opt/models/Qwen3.8-27B-NVFP4/config.json:494-503`. Это означает
наличие native draft head, но MTP2/MTP3 не означают два или три разных layer.
Текущий vLLM повторно вызывает тот же layer и предупреждает, что
`num_speculative_tokens > 1` может снизить acceptance
(`/tmp/opencode/vllm-image-src/vllm/config/speculative.py:943-952`).

## Проверка рекомендаций по upstream

### MTP correctness gate

PR vLLM [#51812](https://github.com/vllm-project/vllm/pull/51812) исправляет
Qwen GDN speculative decoding для mixed batch, где non-speculative tokens
расположены перед speculative tokens. Tensors `a` и `b` должны
индексироваться тем же `spec_token_indx`, что и Q/K/V
([merged source](https://github.com/vllm-project/vllm/blob/5af7c8dad798bf899813f8f3c6b9eaf08a748e17/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py#L1252-L1262),
[kernel call](https://github.com/vllm-project/vllm/blob/5af7c8dad798bf899813f8f3c6b9eaf08a748e17/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py#L1382-L1392)).
PR merged 2026-08-11 commit
`5af7c8dad798bf899813f8f3c6b9eaf08a748e17`.

В active generic path текущего immutable image Q/K/V выбираются через
`spec_token_indx`, но recurrent update получает полные `a` и `b`
(`/tmp/opencode/vllm-image-src/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py:1324-1333,1497-1519`).
Startup подтверждает, что текущая sm_120 машина использует именно Triton path
(runtime log `tool_00bf0a21b0027syRx4YDXKUR9M:41`). Следовательно, текущий
image нельзя считать содержащим семантику #51812.

В текущем baseline `max-num-seqs: 1` задает максимум одной running request:
scheduler присваивает это значение `max_num_running_reqs`, прекращает admission
следующей waiting request при достижении limit и проверяет invariant после
schedule
(`/tmp/opencode/vllm-image-src/vllm/v1/core/sched/scheduler.py:109-115,691-700,1102-1113`).
Full CUDA graph padding также ограничен `max_num_reqs=1`
(`/tmp/opencode/vllm-image-src/vllm/v1/worker/gpu/model_runner.py:1000-1042`).
Одна request не может одновременно образовать affected mixed spec/non-spec
layout. Поэтому #51812 не является доказанной технической предпосылкой для
isolated seq-1 MTP A/B на текущем image.

[#51812](https://github.com/vllm-project/vllm/pull/51812) остается
консервативным production gate и становится обязательным до
`max-num-seqs > 1`, concurrent MTP traffic или смешанного workload, способного
сформировать несколько spec/non-spec rows. Isolated тест все равно требует
сравнения outputs и logprobs с no-MTP baseline, поскольку локальная корректность
текущего artifact ранее не проверялась.

### Fused GDN kernel #51674

PR [#51674](https://github.com/vllm-project/vllm/pull/51674) является прежде
всего performance path: он добавляет fused CUDA post-conv MTP decode kernel.
В final merged source selector называется
`VLLM_GDN_DECODE_KERNEL={cuda,triton}`, default равен `cuda`
([merged envs.py](https://github.com/vllm-project/vllm/blob/1be36283678a9a94fc8fdaad6c95c2896d6b4015/vllm/envs.py#L1213-L1221)).
Runtime guard разрешает CC 8.0+, а CUDA 13 build list включает `12.0f`
([merged model source](https://github.com/vllm-project/vllm/blob/1be36283678a9a94fc8fdaad6c95c2896d6b4015/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py#L512-L534),
[CMake](https://github.com/vllm-project/vllm/blob/1be36283678a9a94fc8fdaad6c95c2896d6b4015/CMakeLists.txt#L1118-L1146)).

Специализированный CUDA MTP op дополнительно требует
`num_v_heads == 8 * num_k_heads`
([dispatch](https://github.com/vllm-project/vllm/blob/1be36283678a9a94fc8fdaad6c95c2896d6b4015/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py#L1798-L1812)).
Локальная модель имеет 48 value heads и 16 key heads, ratio 3
(`/opt/models/Qwen3.8-27B-NVFP4/config.json:494-502`). Поэтому sm_120 не
блокирует сборку нового kernel, но headline ratio-8 fast path для этой модели
не dispatchится.

Итог: #51812 является correctness gate для mixed concurrent GDN speculative
workload. #51674 не обязателен для isolated Triton MTP на локальной ratio-3
модели и не дает основания ожидать заявленный fused-kernel uplift.

### Официальный Qwen3.8 recipe

Официальный vLLM recipe на immutable revision
[`0025768`](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml)
рекомендует:

```text
--speculative-config '{"method":"mtp","num_speculative_tokens":3}'
```

Recipe одновременно сообщает, что связанные GDN speculative changes
[#51812](https://github.com/vllm-project/vllm/pull/51812) и
[#51674](https://github.com/vllm-project/vllm/pull/51674) еще не входили ни в
один released tag
([recipe lines 29-34](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L29-L34)).
MTP3 и измеренные acceptance values описаны в
[lines 73-83](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L73-L83).

Recipe проверен end-to-end на GB300, а его NVFP4 variant -
`Inferact/Qwen3.8-27B-NVFP4`, не локальный mixed compressed-tensors artifact
([recipe lines 14-19](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L14-L19),
[lines 113-123](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L113-L123)).
Это делает MTP3 приоритетной гипотезой, но не production default без локального
A/B.

Параметр depth следует задавать явно. В локальном config
`mtp_num_hidden_layers` находится внутри `text_config`, а текущий generic Qwen
branch читает поле у top-level `hf_config`
(`/opt/models/Qwen3.8-27B-NVFP4/config.json:415-503`,
`/tmp/opencode/vllm-image-src/vllm/config/speculative.py:531-548`). Официальный
recipe также явно задает `num_speculative_tokens` по этой причине
([recipe lines 73-83](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L73-L83)).

### Prefix caching и MTP

Upstream reproduction, опубликованный в PR #51812, наблюдал misordered mixed
layouts при MTP3 с prefix caching и не наблюдал их в двух no-prefix arms. Тест
использовал восемь concurrent streams, adversarial traffic и downstream fork,
а не текущий seq-1 профиль. Автор связал достижимость с full prefix-cache hit,
оставляющим один новый token; он отдельно не утверждает, что наблюдавшиеся
forward passes изменили emitted token
([upstream issue comment](https://github.com/vllm-project/vllm/pull/51812#issuecomment-5307331574)).

Это не локальная частота и не доказательство reachability при
`max-num-seqs: 1`. Также это не основание запретить prefix caching без MTP.
Когда speculative decoding выключен, GDN metadata оставляет
`spec_sequence_masks=None`, поэтому конкретный gate-alignment bug #51812 не
активируется
(`/tmp/opencode/vllm-image-src/vllm/v1/attention/backends/gdn_attn.py:190-225`).
Prefix-only A/B на текущем image допустим, но должен пройти long-context и
streaming-проверку как самостоятельное изменение.

Политика эксперимента:

1. На текущем image проверять prefix caching только с MTP off.
2. На текущем image разрешен isolated MTP A/B при `max-num-seqs: 1` и prefix
   cache off.
3. Сочетать MTP и prefix caching только после раздельного успеха обоих режимов;
   на текущем image сохранять seq-1, а для production/concurrency сначала
   перейти на image с #51812.

### Performance mode

Source описывает `interactivity` как latency-oriented режим для малого batch
(`/tmp/opencode/vllm-image-src/vllm/config/vllm.py:415-420`). В исследуемом
snapshot его наблюдаемое отличие - fine-grained CUDA graph sizes
(`/tmp/opencode/vllm-image-src/vllm/config/vllm.py:1883-1946`).

Для текущего baseline `num_speculative_tokens=0`, поэтому
`decode_query_len=1`, а default max graph size равен
`max_num_seqs * decode_query_len * 2 = 1 * 1 * 2 = 2`. `balanced` создает
`[1, 2]`, и `interactivity` также создает `[1, 2]`; startup подтверждает
`PIECEWISE=2 (largest=2)` (runtime log lines 67-68). Отдельный pre-MTP A/B
является no-op.

При MTP1 max graph size становится 4: `balanced` дает `[1, 2, 4]`, а
`interactivity` - `[1, 2, 3, 4]`. При более глубоком MTP различие растет.
Поэтому параметр следует проверять только после выбора MTP depth, контролируя
изменение graph pool memory.

### FlashInfer и NVFP4

Принудительный `attention-backend: flashinfer` не нужен: текущий auto selection
уже выбрал FlashInfer attention, а NVFP4 GEMM использует
`FlashInferCutlassNvFp4LinearKernel`
(runtime log `tool_00bf0a21b0027syRx4YDXKUR9M:42-43`). Принудительный backend
не показывает нового локального выигрыша и ограничивает fallback.

`no-enable-flashinfer-autotune: true` не отключает runtime FlashInfer kernels.
Он только предотвращает transient autotune allocations, которые уже вызывали
локальный OOM/hang; этот параметр следует сохранить
(`vllm/config.yaml:21-25`, `AGENTS.md`, runtime log lines 42-43).

### Context, batch и memory utilization

Qwen3.8 model card заявляет native context 262144 и возможность расширения до
1M
([official Qwen model card, revision `1d4bf0f`](https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/README.md)).
Это model capability, а не гарантия размещения KV/activations на конкретном
hardware.

Локальный limit 65536 не прошел startup из-за недостаточного KV cache при
текущем safe budget; 49152 остается максимальным проверенным limit
(`README.md:66-79`, `docs/NVIDIA_SETUP.md:131-147`). Повышение
`gpu-memory-utilization` ради startup уменьшило бы физический runtime headroom,
которого уже не хватало при activation OOM
(`docs/research/0001-vllm-qwen38-memory-investigation.md:171-202,441-446`).

Chunked prefill и batch 1024 следует сохранить. В локальном incident первая
размерность failed BF16 tensors совпадала с 4096 scheduled tokens; уменьшение
batch до 1024 уменьшает соответствующие allocations примерно в четыре раза
(`docs/research/0001-vllm-qwen38-memory-investigation.md:131-169,302-334`).

### Text-only, parser и вспомогательные flags

`language-model-only: true` уже отключает vision encoder и оставляет VRAM
текстовому workload (`vllm/config.yaml:8-12`; официальная возможность также
указана в
[recipe lines 84-92](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L84-L92)).
Дополнительный `skip-mm-profiling` не имеет подтвержденной пользы в профиле,
где multimodal stage уже выключен.

`trust-remote-code` не нужен: официальный recipe оставляет `base_args` пустым
и отмечает native vLLM handler
([recipe lines 20-38](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L20-L38)).
Quantization также уже определяется как `compressed-tensors` runtime-ом
(runtime log `tool_00bf0a21b0027syRx4YDXKUR9M:17`), поэтому принудительный
quantization flag не нужен.

Официальный recipe называет tool parser `qwen3_coder`
([recipe lines 61-70](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L61-L70)).
В текущем image `qwen3_coder` и `qwen3_xml` зарегистрированы на один
`Qwen3EngineToolParser`, поэтому замена текущего alias не дает подтвержденного
изменения поведения
(`/tmp/opencode/vllm-image-src/vllm/tool_parsers/__init__.py`). После смены
image aliases нужно проверить заново.

`safetensors-load-strategy=prefetch` имеет низкий приоритет: checkpoint лежит
на локальном EXT4, а model load baseline занял 2.45 s после начала загрузки
(runtime log `tool_00bf0a21b0027syRx4YDXKUR9M:44-45,53-54`).
Serving-throughput benefit для prefetch не показан; его ожидаемая область
действия ограничена чтением checkpoint при startup.

## Матрица решений

| Рекомендация | Отличие от baseline | Решение | Основание |
|---|---|---|---|
| Prefix caching | Сейчас явно выключен | **A/B сейчас, MTP off** | Reddit сообщил warm TTFT 68.8 -> 2.8 s для повторного 200K prefix; конкретный bug #51812 без speculative decoding не активен ([основной post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/), local GDN metadata `gdn_attn.py:190-225`) |
| `performance-mode: interactivity` | Сейчас default `balanced` | **No-op без MTP; A/B после MTP** | При seq-1/no-MTP оба режима создают `[1, 2]`; с MTP1 sets впервые расходятся (`vllm.py:1883-1946`, runtime log lines 67-68) |
| Native MTP1/2/3 | Сейчас `speculative_config=None` | **Isolated A/B сейчас; production после #51812** | Seq-1 исключает affected mixed-request layout; official recipe и Reddit делают MTP3 целевой гипотезой, а локальный artifact и TP2 требуют sweep ([recipe](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L73-L83), [`okacrd2`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okacrd2/), local scheduler `scheduler.py:109-115,691-700`) |
| MTP + prefix cache на текущем image | Оба выключены | **Только после раздельных A/B, строго seq-1** | #51812 reproduction требует mixed concurrent rows; production или повышение concurrency сначала требуют fixed image ([#51812](https://github.com/vllm-project/vllm/pull/51812#issuecomment-5307331574)) |
| MTP3 как немедленный default | MTP off | **Не применять без sweep** | Локально один MTP layer повторяется, а official result получен на GB300/другом artifact (`config.json:494-503`, `speculative.py:943-952`) |
| Context 200K/230400 | Сейчас 49152 | **Отклонить** | 65536 уже не прошел local startup; Reddit использовал одну 5090 и меньший artifact (`README.md:66-79`, [post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)) |
| `gpu-memory-utilization: 0.90-0.95` | Сейчас 0.85 | **Отклонить** | Уменьшает запас display-GPU после подтвержденного activation OOM (`docs/research/0001-vllm-qwen38-memory-investigation.md:171-202`) |
| Batch 4096 | Сейчас 1024 | **Отклонить** | Именно 4096 scheduled tokens создали failed 68/136 MiB allocations (raw log `tool_00b616...:211,423,560-561`) |
| Batch 6144/8192 | Сейчас 1024 | **Отклонить** | Локальный риск выше, а Reddit получил меньшие generation results ([`okacrd2`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okacrd2/)) |
| `max-num-seqs: 1` | Уже включен | **Сохранить** | Второй request ожидает scheduler; исключает прежний двух-request scheduler step (`vllm/config.yaml:14-19`, runtime log lines 174, 214) |
| FP8 KV cache | Уже включен | **Сохранить** | Baseline успешно стартует с 1.96 GiB KV (`vllm/config.yaml:21-25`, runtime log lines 72, 74) |
| Chunked prefill | Уже включен | **Сохранить** | Ограничивает prefill текущим safe batch 1024 (`vllm/config.yaml:14-19`) |
| Text-only | Уже включен | **Сохранить** | Освобождает vision-stage VRAM ([official recipe](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L84-L92)) |
| TP1 | Сейчас TP2 | **Невозможно** | Weight index 23.42 GB больше 16 GB одной карты (`model.safetensors.index.json:1-4`) |
| Force FlashInfer | Auto уже выбрал FlashInfer | **Не добавлять** | Startup подтвердил FlashInfer attention и NVFP4 GEMM (runtime log lines 42-43) |
| FlashInfer autotune | Сейчас выключен | **Оставить выключенным** | Runtime kernels остаются активны, transient autotune уже вызывал OOM (`vllm/config.yaml:21-25`, `AGENTS.md`) |
| `skip-mm-profiling` | Не задан | **Не добавлять** | Text-only уже отключает encoder; отдельная польза не показана (`vllm/config.yaml:8-12`) |
| `trust-remote-code` | Не задан | **Не добавлять** | Native handler; official recipe не требует flag ([recipe](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml#L20-L38)) |
| Explicit compressed-tensors | Auto detection | **Не добавлять** | Runtime уже определил quantization (runtime log line 17) |
| Safetensors prefetch | Не задан | **Низкий приоритет** | Local model load 2.45 s; serving benefit не подтвержден (runtime log lines 44-45, 53-54) |
| `qwen3_coder` вместо `qwen3_xml` | Сейчас `qwen3_xml` | **Не менять на current image** | Оба имени являются aliases одного parser (`tool_parsers/__init__.py`) |
| AutoRound/TurboQuant/GGUF | Другая модель/precision | **Отдельное исследование** | Не являются настройками текущего artifact ([AutoRound card](https://huggingface.co/Lorbus/Qwen3.6-27B-int4-AutoRound/blob/c3aea2d531678621989e5e2db034e32b22536e79/README.md)) |
| Cobra/Genesis patches | Сторонний runtime | **Отклонить** | Floating dependency и противоречивый validation state ([commit](https://github.com/CobraPhil/qwen36-27b-single-5090/tree/fe6b0305d54f3f7c5554520623efa8b6b3040ef2), [issue #4](https://github.com/CobraPhil/qwen36-27b-single-5090/issues/4)) |

## Приоритетный план экспериментов

Каждый этап меняет только один фактор. Не следует компенсировать неудачную
оптимизацию повышением utilization, уменьшением safety headroom или
одновременной сменой model artifact.

### Этап 0. Контрольная точка

Сохранить без изменений:

```yaml
max-model-len: 49152
max-num-seqs: 1
max-num-batched-tokens: 1024
enable-chunked-prefill: true
no-enable-prefix-caching: true
gpu-memory-utilization: 0.85
kv-cache-dtype: fp8
no-enable-flashinfer-autotune: true
```

Повторно записать baseline TTFT, output throughput, peak VRAM обеих GPU,
startup memory breakdown, tool calls и reasoning behavior. Существующие
значения находятся в runtime log `tool_00bf0a21b0027syRx4YDXKUR9M`.

### Этап 1. Prefix-only A/B

Имеет смысл только для workload с повторяющимся идентичным system/tool/repo
prefix. Единственное изменение:

```yaml
enable-prefix-caching: true
```

Одновременно удалить `no-enable-prefix-caching: true`. MTP и performance mode
не менять. Принимать вариант только при подтвержденном cache hit и измеримом
снижении warm TTFT; для уникальных prompts оставить cache выключенным.

### Этап 2. Isolated MTP sweep

Вернуть prefix cache в off. На текущем image при неизменном
`max-num-seqs: 1` сначала проверить:

```yaml
speculative-config: '{"method":"mtp","num_speculative_tokens":1}'
```

Затем, меняя только depth:

```yaml
speculative-config: '{"method":"mtp","num_speculative_tokens":2}'
```

```yaml
speculative-config: '{"method":"mtp","num_speculative_tokens":3}'
```

MTP3 является целевым вариантом по Reddit и official recipe. Последовательность
1 -> 2 -> 3 нужна для измерения memory overhead, TP2 communication cost и
acceptance каждого дополнительного draft position, а не для понижения
приоритета MTP3.

Во всем sweep сохранять context 49152, batch 1024, sequences 1, utilization
0.85, prefix cache off, backend auto, `performance-mode: balanced` и текущие
parser settings. Это laboratory A/B; production rollout требует следующего
этапа.

### Этап 3. Image correctness gate

Перед production rollout, повышением concurrency или mixed MTP workload:

1. Найти новый immutable image digest, не floating nightly.
2. Извлечь source этого image.
3. Подтвердить, что active Qwen GDN speculative path индексирует `a` и `b` по
   `spec_token_indx`, как в #51812.
4. Запустить новый image с текущим baseline и `speculative_config=None`.
5. Повторить cold start, long streaming, tools, reasoning и VRAM validation.
6. Повторить выбранный на этапе 2 MTP depth на новом image.

Наличие #51674 не является обязательным gate для ratio-3 модели. Обязателен
correctness fix #51812 для mixed concurrent layout.

### Этап 4. Interactivity A/B после MTP

Зафиксировать выбранный MTP depth и изменить только:

```yaml
performance-mode: interactivity
```

Сравнить TTFT, inter-token latency, throughput и CUDA graph pool. Без MTP этот
этап пропустить, поскольку `balanced` и `interactivity` дают одинаковые graph
sizes `[1, 2]`.

### Этап 5. MTP с prefix caching

Проверять только если prefix-only и выбранный MTP depth отдельно прошли все
correctness, stability и memory gates. На текущем image сохранять
`max-num-seqs: 1`; для production и любого повышения concurrency сначала
перейти на image с #51812. Это отдельный A/B, а не автоматическая сумма двух
успешных оптимизаций.

## Протокол проверки

Перед каждым cold-start вариантом следовать обязательному порядку репозитория:

```bash
docker compose --profile llama --profile vllm down --remove-orphans
docker compose config
docker compose --profile vllm up -d --wait --wait-timeout 1800
```

После startup проверить:

```bash
docker compose --profile vllm logs vllm-server
docker inspect --format 'restart={{.RestartCount}} oom={{.State.OOMKilled}} status={{.State.Status}} health={{.State.Health.Status}}' vllm-server
nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,display_active --format=csv
curl --fail http://localhost:8080/health
curl --fail http://localhost:8080/v1/models
curl --fail http://localhost:8080/metrics
```

### Workload matrix

| Workload | Проверяемое свойство |
|---|---|
| Короткий no-thinking, output 2048+ | Decode throughput и MTP acceptance |
| Тот же prompt с thinking | Влияние thinking как отдельной dimension |
| Coding/agent prompt | Реальный рабочий throughput |
| Tool-call prompt | Parser и `tool_calls[]` correctness |
| Длинный streaming response | SSE progress, ITL и завершающий `[DONE]` |
| Prompt около 12718, `max_tokens=32000` | Повтор прежнего incident workload |
| Prompt близко к 49152 total limit | Long-context correctness и VRAM |
| Два одновременно отправленных request | `Running: 1`, `Waiting: 1` |
| Один большой prefix дважды | Только prefix-cache candidate |

Для коротких workload использовать один warmup и минимум пять измеряемых
повторов. Для основного long decode желательно десять повторов: Reddit серия
показала значительный run-to-run разброс
([post](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)).

### Метрики

Собирать:

- TTFT/TTFR;
- end-to-end latency;
- inter-token latency;
- output и prompt tok/s;
- p50 и p95;
- input/output token counts и finish reason;
- peak VRAM и минимально свободную VRAM каждой GPU;
- startup model, activation, CUDA graph и KV memory;
- restart count и наличие CUDA/RPC errors;
- корректность tool calls, reasoning fields и streaming `[DONE]`.

Для MTP использовать дельты Prometheus counters:

```text
vllm:spec_decode_num_drafts_total
vllm:spec_decode_num_draft_tokens_total
vllm:spec_decode_num_accepted_tokens_total
vllm:spec_decode_num_accepted_tokens_per_pos_total
```

Формулы текущей реализации:

```text
draft acceptance rate = accepted_tokens / draft_tokens
mean acceptance length = 1 + accepted_tokens / drafts
```

Источник формул:
`/tmp/opencode/vllm-image-src/vllm/v1/spec_decode/metrics.py:82-118,177-196`.
Сравнивать нужно дельты counters до и после каждого benchmark, а не накопленные
абсолютные значения.

### Локальные критерии принятия

Следующие thresholds являются предлагаемой локальной политикой, а не upstream
measurements:

- не менее 512 MiB физически свободной VRAM на GPU1 под пиком;
- отсутствие startup OOM, automatic restart, `EngineDeadError` и RPC timeout;
- завершение каждого streaming response маркером `[DONE]`;
- отсутствие regression в tool calls и reasoning separation;
- для MTP median output throughput минимум на 15% выше baseline;
- для MTP draft acceptance не ниже 50% и mean acceptance length не ниже 1.5;
- для следующего MTP depth дополнительный устойчивый выигрыш около 5% или
  больше относительно предыдущего depth;
- для prefix caching warm TTFT минимум на 30% ниже при реальном cache hit;
- для post-MTP `interactivity` TTFT или ITL минимум на 10% лучше без нарушения
  memory headroom и без падения основного long-decode throughput.

Acceptance сама по себе не доказывает ускорение. Итоговое решение принимается
по end-to-end latency/throughput и correctness.

## Rollback

Для каждого эксперимента изменять только одну строку или один image digest.
При отказе:

1. Вернуть предыдущий immutable image digest.
2. Удалить единственный экспериментальный параметр.
3. Восстановить baseline 49152/1/1024/0.85.
4. Выполнить новый cold start.
5. Повторить health, model-ID, long streaming и VRAM checks.

Не компенсировать неудачный MTP повышением utilization, batch 4096,
одновременным отключением CUDA graphs, TurboQuant или заменой модели. Если MTP
помещается только после уменьшения проверенного context, это отдельный product
trade-off, а не успешная оптимизация текущего профиля.

## Оставшиеся неизвестные

Без отдельного A/B на текущей машине неизвестны:

- acceptance локального Qwen3.8 mixed FP8/NVFP4 artifact;
- per-rank MTP memory overhead;
- стоимость MTP TP2 collectives через PHB без P2P;
- изменение CUDA graph pool для MTP1/2/3 и `interactivity`;
- throughput на реальном long agent workload;
- доля повторяющихся точных prefix в реальном трафике;
- наличие подходящего immutable image с #51812;
- совместная стабильность prefix caching и MTP после source fix.

Эти значения нельзя получить из single-5090 benchmark или model card.

## Итоговая рекомендация

Текущий production baseline не следует менять одним пакетом настроек из
Reddit. При этом рекомендации обсуждения должны изменить очередь экспериментов:

- prefix caching без MTP становится первым доступным A/B;
- MTP становится главным isolated throughput A/B уже на текущем image при
  строгом `max-num-seqs: 1` и prefix cache off;
- image с #51812 обязателен перед production rollout, concurrency выше единицы
  и mixed MTP workload;
- `performance-mode: interactivity` становится отдельным latency A/B только
  после включения MTP;
- MTP3 остается целевой гипотезой, но выбирается по sweep MTP1/2/3;
- 200K context, utilization 0.90-0.95 и batch 4096+ отклоняются из-за прямых
  локальных startup/OOM данных;
- AutoRound, TurboQuant, GGUF и сторонние patches не смешиваются с оптимизацией
  текущего artifact.

Reddit-пост подтверждает, что Qwen3.6 NVFP4 с MTP может обслуживать 200K на
одной RTX 5090 в описанном автором stack. Он не подтверждает, что те же memory
параметры безопасны или быстрее для Qwen3.8 на двух RTX 5070 Ti с TP2,
отсутствующим P2P и display-нагрузкой.

## Первичные источники

### Локальные

- `vllm/config.yaml`
- `vllm/docker-compose.yaml`
- `docs/NVIDIA_SETUP.md`
- `docs/research/0001-vllm-qwen38-memory-investigation.md`
- `/opt/models/Qwen3.8-27B-NVFP4/config.json`
- `/opt/models/Qwen3.8-27B-NVFP4/model.safetensors.index.json`
- `/tmp/opencode/vllm-image-src/vllm/config/speculative.py`
- `/tmp/opencode/vllm-image-src/vllm/config/vllm.py`
- `/tmp/opencode/vllm-image-src/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py`
- `/tmp/opencode/vllm-image-src/vllm/v1/attention/backends/gdn_attn.py`
- `/tmp/opencode/vllm-image-src/vllm/v1/spec_decode/metrics.py`
- `/home/dimmy/.local/share/opencode/tool-output/tool_00bf0a21b0027syRx4YDXKUR9M`
- `/home/dimmy/.local/share/opencode/tool-output/tool_00b616ec1001XyqvaO7OZ7LHlq`

### Upstream

- [Docker Hub API: `vllm/vllm-openai:qwen38`](https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/qwen38)
- [Official vLLM Qwen3.8 recipe, commit `0025768`](https://github.com/vllm-project/recipes/blob/002576894984c12e203bb25421635fbb3f408e9d/models/Qwen/Qwen3.8-27B.yaml)
- [vLLM PR #51812: GDN speculative gate alignment](https://github.com/vllm-project/vllm/pull/51812)
- [vLLM PR #51674: fused CUDA GDN MTP decode](https://github.com/vllm-project/vllm/pull/51674)
- [Official Qwen3.8-27B model card, commit `1d4bf0f`](https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/README.md)
- [Reddit Qwen3.6 artifact, revision `71d4621`](https://huggingface.co/Peutlefaire/Qwen3.6-27B-NVFP4/tree/71d46214a7ef0f1205dd536f63203e5b51b415ee)
- [AutoRound artifact, revision `c3aea2d`](https://huggingface.co/Lorbus/Qwen3.6-27B-int4-AutoRound/tree/c3aea2d531678621989e5e2db034e32b22536e79)
- [CobraPhil stack, commit `fe6b030`](https://github.com/CobraPhil/qwen36-27b-single-5090/tree/fe6b0305d54f3f7c5554520623efa8b6b3040ef2)

### Обсуждение

- [Исходный Reddit-пост](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/qwen36_27b_nvfp4_mtp_on_a_single_rtx_5090_200k/)
- [Основной follow-up `okacrd2`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okacrd2/)
- [AutoRound comment `ok9gppj`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/ok9gppj/)
- [Nightly comment `oki4fml`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/oki4fml/)
- [Cobra comment `okch4q7`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okch4q7/)
- [Dual-GPU correction `okb2ryb`](https://www.reddit.com/r/LocalLLaMA/comments/1t5dya8/comment/okb2ryb/)
- [Arctic Shift archival transport](https://arctic-shift.photon-reddit.com/api/posts/ids?ids=1t5dya8)
