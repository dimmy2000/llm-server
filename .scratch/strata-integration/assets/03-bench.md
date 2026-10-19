# bench.py короткие прогоны (тикет 03, 2026-10-19T13:05:23Z)

## strata-iq3 (max-tokens 4, маленький prompt)
strata-iq3-smoke: ttft=Nones total=0.41s prompt=82 completion=4 finish=length
  engine: prompt_n=82 prefill=225.3 tok/s decode=98.5 tok/s draft=4/4
exit=0
```json
{
  "label": "strata-iq3-smoke",
  "model": "strata-iq3",
  "max_tokens": 4,
  "ttft_s": null,
  "total_s": 0.40863341999647673,
  "decode_span_s": null,
  "content_chars": 0,
  "content_chunks": 0,
  "completion_tokens": 4,
  "decode_tok_s_chunks": null,
  "decode_tok_s_usage": null,
  "usage": {
    "prompt_tokens": 82,
    "completion_tokens": 4,
    "total_tokens": 86,
    "prompt_tokens_details": {
      "cached_tokens": 0
    }
  },
  "timings": {
    "cache_n": 0,
    "prompt_n": 82,
    "prompt_ms": 364.0,
    "prompt_per_token_ms": 4.439,
    "prompt_per_second": 225.3,
    "predicted_n": 4,
    "predicted_ms": 40.6,
    "predicted_per_token_ms": 10.15,
    "predicted_per_second": 98.5,
    "draft_n": 4,
    "draft_n_accepted": 4
  },
  "finish_reason": "length",
  "text": ""
}```

## qwen3.8-27b родитель (ninfer, max-tokens 4, маленький prompt)
qwen3.8-27b-smoke: ttft=Nones total=0.12s prompt=82 completion=4 finish=length
  engine: prompt_n=82 prefill=1105.999982465854 tok/s decode=77.29222857043334 tok/s draft=2/1
exit=0
```json
{
  "label": "qwen3.8-27b-smoke",
  "model": "qwen3.8-27b",
  "max_tokens": 4,
  "ttft_s": null,
  "total_s": 0.11711908598954324,
  "decode_span_s": null,
  "content_chars": 0,
  "content_chunks": 0,
  "completion_tokens": 4,
  "decode_tok_s_chunks": null,
  "decode_tok_s_usage": null,
  "usage": {
    "completion_tokens": 4,
    "completion_tokens_details": {
      "reasoning_tokens": 4
    },
    "prompt_tokens": 82,
    "prompt_tokens_details": {
      "cached_tokens": 0
    },
    "total_tokens": 86
  },
  "timings": {
    "cache_n": 0,
    "draft_n": 2,
    "draft_n_accepted": 1,
    "predicted_ms": 38.813734000000004,
    "predicted_n": 4,
    "predicted_per_second": 77.29222857043334,
    "predicted_per_token_ms": 12.937911333333334,
    "prompt_ms": 74.14105,
    "prompt_n": 82,
    "prompt_per_second": 1105.999982465854,
    "prompt_per_token_ms": 0.9041591463414635
  },
  "finish_reason": "length",
  "text": ""
}```
