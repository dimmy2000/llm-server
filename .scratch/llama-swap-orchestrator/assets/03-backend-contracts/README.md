# 03-backend-request-contracts — сырые артефакты

Сырые материалы к отчёту
[`docs/research/0013-backend-request-contracts.md`](../../../../docs/research/0013-backend-request-contracts.md)
(тикет `.scratch/llama-swap-orchestrator/issues/03-backend-request-contracts.md`).

Всё получено статически (чтение исходников, `--help`, `strings`, `docker ps`,
`/v1/models`). Контейнеры не перезапускались, инференс-запросы не отправлялись.

## Структура

| Каталог / файл | Что это | Как получено |
|---|---|---|
| `llama-cpp/revisions-and-sources.txt` | ревизии llama.cpp / vLLM-образа / NInfer и ссылки на первоисточники | `git rev-parse`, `docker images`, `docker run --entrypoint python3` |
| `llama-cpp/server-common-1390-1480.cpp` | путь разбора запроса: `reasoning_format`, merge `chat_template_kwargs`, `enable_thinking`, `reasoning_effort`, `reasoning_budget_tokens`, копирование остальных ключей тела в `llama_params` | `sed` из `../llama.cpp/tools/server/server-common.cpp` |
| `llama-cpp/chat-cpp-884-922.cpp` | контекст шаблона: `preserve_reasoning`, `reasoning_effort` → капы | `sed` из `common/chat.cpp` |
| `llama-cpp/arg-cpp-reasoning-flags.cpp` | CLI `--reasoning`, `--reasoning-effort`, `--reasoning-budget`, deprecated `--chat-template-kwargs` | `sed` из `common/arg.cpp` |
| `llama-cpp/server-schema-sampling-fields.cpp` | регистрация sampling-полей и их диапазоны | `sed` из `tools/server/server-schema.cpp` |
| `llama-cpp/server-schema-clamp-and-null.cpp` | `has_value` (null → absent), `handle_with_catch`, clamp vs hard limits | то же |
| `llama-cpp/server-ex-wrapper.cpp` | маппинг исключений на HTTP-статусы (400/500) | `sed` из `tools/server/server.cpp` |
| `llama-cpp/common-h-sampling-defaults.h` | дефолты `common_params_sampling` | `sed` из `common/common.h` |
| `llama-cpp/server-readme-reasoning-flags.md` | таблица reasoning-флагов из README | `sed` из `tools/server/README.md` |
| `llama-cpp/gguf-embedded-chat-template.jinja` | embedded chat template модели llama-профиля (official Qwen3.8) | извлечён из `/opt/models/Qwen3.8-27B-NVFP4-MTP-GGUF/Qwen3.8-27B-NVFP4-MTP-HIGH.gguf` |
| `llama-swap/filters.go` | порядок фильтров: `useModelName → stripParams → setParams → setParamsByID` | копия `../llama-swap/internal/server/filters.go` |
| `config/llama-config.yaml`, `config/ninfer-config.yaml`, `config/vllm-config.yaml` | конфиги на момент исследования | копия из корня проекта |
| `ninfer/ninfer-serve-help.txt` | полный `--help` запущенного бинаря | `docker exec llama-swap /opt/ninfer/bin/ninfer-serve --help` |
| `ninfer/serving-chat-completions.md` | контракт Chat Completions из `docs/serving.md` (строки 94-253) | `sed` из сохранённого `docs/serving.md` @ `47d47864` |
| `ninfer/serving-responses-fields.md` | таблица полей Responses (`temperature [0,2]`, `top_p [0,1]`, `reasoning.effort`) | `sed` (строки 410-440) |
| `ninfer/serving-server-options.md` | таблица server-опций (`--no-thinking`, `--preserve-thinking`, sampler overrides) + пресеты Qwen3.8-27B | `sed` (строки 812-848) |
| `ninfer/embedded-chat-template-qwen3_8.jinja` | шаблон, встроенный в артефакт | `curl` raw.githubusercontent.com @ `47d47864` |
| `ninfer/validation-strings.txt` | строки валидации/ошибок из бинаря (`reasoning_effort must be…`, `repetition_penalty_not_supported`, диапазоны) | `grep -n` по `strings ninfer-serve` |
| `vllm/protocol-excerpt-deployed.txt` | `reasoning_effort` Literal, sampling-поля, `chat_template_kwargs`, `build_chat_params`, `OpenAIBaseModel(extra="allow")` **из развёрнутого образа** | `docker run --entrypoint bash 4a2f33a88422` + `sed` |
| `vllm/error-mapping.txt` | `create_error_response`: `VLLMValidationError`→400, `TemplateError`→400, `ValueError`→400; `validation_exception_handler`→400 | то же |
| `vllm/sampling-validation-and-kwargs.txt` | `SamplingParams._verify_args` (диапазоны), `merge_kwargs` (отбрасывает `None`/`"auto"`), `resolve_chat_template_kwargs` (фильтр по объявленным vars) | то же |
| `vllm/chat-completion-protocol-main.py` | `chat_completion/protocol.py` с ветки `main` (для сравнения с развёрнутой версией) | `curl` raw.githubusercontent.com |
| `vllm/model-generation-config.json` | дефолты sampling модели (`generation-config: auto`) | копия `/opt/models/Qwen3.8-27B-NVFP4/generation_config.json` |
| `vllm/model-chat-template-excerpt.jinja` | усилие шаблона vLLM-модели (нет фолда `high→xhigh`) | `sed` из `/opt/models/Qwen3.8-27B-NVFP4/chat_template.jinja` |

## Версии

- llama.cpp: `62318cd57dc63900ecb153272c0b10f78550855d` (2026-10-17, после `git pull`)
- NInfer: `llm-server/ninfer-tp2:v0.4.6`, форк `ValerioDolci/ninfer-tp2` @
  `47d47864b9e903ab7f800e7c128b7e300230ec00` (`docs/serving.md` и
  `tools/chat_templates/qwen3_8.jinja` взяты с того же коммита)
- vLLM: `vllm/vllm-openai:qwen38` = `4a2f33a88422` = `0.1.dev19754+g3a0914114`
- llama-swap: `a2796fb`
