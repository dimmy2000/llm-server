# Draft upstream issue: llama.cpp — top-level `reasoning_effort: "none"` is inert when `--reasoning on` is set

Status: DRAFT — not submitted. Prepared by the llm-server local stack effort
(ticket 15, `.scratch/llama-swap-orchestrator/issues/15-verify-b10438.md`).
Verified on `b10438` (9d57ce456); the `none` branch and the `--reasoning`
kwarg injection are identical at HEAD `62318cd57`.

## Summary

When the server is started with `--reasoning on`, an OpenAI-compatible request
with top-level `"reasoning_effort": "none"` does **not** disable thinking,
although the `none` branch in `oaicompat_chat_params_parse()` executes and
sets `inputs.enable_thinking = false`. The thinking-disable is silently
overridden at template-render time by the `enable_thinking: "true"` default
chat-template kwarg that `--reasoning on` injects. Without `--reasoning on`
(`--reasoning auto`, the default), the same request disables thinking
correctly.

## Reproduction

Any model whose template gates thinking on the `enable_thinking` kwarg
(e.g. Qwen3). Minimal repro, same binary, only the flag differs:

```bash
LLAMA_ARGS="-m Qwen3-0.6B-Q8_0.gguf --jinja -ngl 0 -c 4096"

# server A
llama-server $LLAMA_ARGS --reasoning on --port 5811
# server B
llama-server $LLAMA_ARGS --port 5812

curl http://127.0.0.1:5811/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"What is 2+2?"}],"reasoning_effort":"none","max_tokens":200}'
# -> message.reasoning_content non-empty (thinking ran)

curl http://127.0.0.1:5812/v1/chat/completions ... # same body
# -> message.reasoning_content empty (empty <think></think> block; thinking disabled)
```

Also visible via `POST /apply-template`: with `--reasoning on`, the rendered
prompt for `reasoning_effort: "none"` is byte-identical to the bare render
(thinking-generation prompt, default effort instruction); without the flag it
ends with the empty `<think>\n\n</think>\n\n` block.

`"chat_template_kwargs": {"enable_thinking": false}` still works with
`--reasoning on` — only the top-level `none` path is affected.

## Cause (b10438, `9d57ce456`)

1. `--reasoning on` injects a CLI default kwarg:
   `common/arg.cpp:3635-3637` — `params.default_template_kwargs["enable_thinking"] = "true"`.
2. These defaults become per-request defaults:
   `tools/server/server-context.cpp:1431` passes `params_base.default_template_kwargs`
   as `chat_template_kwargs` into `oaicompat_chat_params_parse()`, which
   initializes `inputs.chat_template_kwargs` from it
   (`tools/server/server-common.cpp:1280`).
3. The `none` branch sets the flag but does not clear the kwarg:
   `tools/server/server-common.cpp:1298-1300` —
   ```cpp
   if (reasoning_effort == "none") {
       inputs.enable_thinking = false;
       inputs.chat_template_kwargs.erase("reasoning_effort"); // enable_thinking survives
   }
   ```
4. At render, kwarg context is applied **after** the parsed flag and wins:
   `common/chat.cpp` `common_chat_template_direct_apply_impl()` sets
   `inp["enable_thinking"] = inputs.enable_thinking` (false), then merges
   `inputs.extra_context` over it; `extra_context` comes from
   `inputs.chat_template_kwargs` (`common/chat.cpp:3443-3447`, values are
   re-parsed with `json::parse`, so `"true"` becomes boolean `true`).
   Template sees `enable_thinking == true` → thinking on.

Note the client-side path works precisely because client kwargs are merged
into `inputs.chat_template_kwargs` **after** the CLI defaults
(`server-common.cpp:1281-1283`), so a client `enable_thinking: false`
overwrites the CLI `true`. The top-level `none` branch has no such overwrite.

Same code at HEAD (`62318cd57`): `server-common.cpp:1421-1429`,
`common/arg.cpp:3716-3719`.

## Suggested direction

Make the explicit top-level `"none"` authoritative over CLI-injected kwargs,
e.g. in the `none` branch also
`inputs.chat_template_kwargs.erase("enable_thinking")`. Semantics question for
maintainers: an explicit client `chat_template_kwargs.enable_thinking: true`
sent together with `"reasoning_effort": "none"` would also be erased by that
one-liner; if client kwargs should take precedence over the OAI field, the
CLI defaults would need to be kept separate from request kwargs instead.

## Local evidence

- Differential repro script + renders: `.scratch/llama-swap-orchestrator/assets/15-verify-b10438/none-mechanism/` (repro-reasoning-on.sh, repro-*.txt, repro-*-response.json).
- 27B live renders: apply-template-probe.py, render-*.txt (none == bare, byte-identical, 325 chars).
- Report: docs/research/0015-llama-cpp-bump-reasoning-effort.md (section
  «Доказательная база на b10438»).
