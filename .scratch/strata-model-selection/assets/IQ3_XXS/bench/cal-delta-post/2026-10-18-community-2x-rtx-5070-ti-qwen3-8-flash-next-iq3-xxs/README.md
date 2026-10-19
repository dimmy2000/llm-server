# Community benchmark on NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti

Measured on 2026-10-18 with `tools/strata_bench.py` (suite 1, 3 runs per test, medians with ranges). Speeds are the engine's own timings; first-token times are measured by the client over HTTP. Speed only: no correctness check was run.

## Hardware and software

- GPU and VRAM: NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti, 32 GiB VRAM
- CPU: AMD Ryzen 9 9950X3D 16-Core Processor (16 cores, 32 threads); installed RAM: 59.4 GiB; storage: not measured
- OS: Linux 7.0.0-38-generic; GPU driver: 615.71.09; CUDA: not read
- Strata: project 0.1.45, commit 477ac13c; engine 0.1.45
- Background workloads and power limits: not recorded

## Model and configuration

- Model and quantization: qwen3.8-flash-next-iq3_xxs
- Context: 131072 tokens; parallel slots: 1
- Settings: the install's own configuration, unchanged; thinking off for the suite; temperature 0

```text
strata --pack iq3_xxs --native Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf --ple-gguf Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf --expert-profile expert-profile.bin --expert-cache 4400 --spec 4 --mtp rt --max-context 131072 --kv int8 --prefill 4096 --vram-reserve-mib 300 --vram-reserve-later-mib 2048 --pcie-frac 0.20 --spec-min-p 0.70 --adapt-every 1 --adapt-swaps 160 --adapt-decay 0.97
```

## Method

Run by `python tools/strata_bench.py` against the HTTP API of a Strata server (already running); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 129.3 (115.2-171.9) | 0.21 (0.19-0.24) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2565.8 (2503.0-2568.7) | not measured | 1.58 (1.58-1.62) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 4313.2 (4249.5-4317.2) | not measured | 3.74 (3.74-3.80) |
| agent session, follow-up turns | 14601 (14564-14614) at the last turn | see below | up to 64 | 3 | see below | 153.1 (81.2-182.0) | 1.44 (1.20-1.60) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 68.7 % (68.6-68.9); earlier-turn tokens read again per session: 73 (4-73) (earlier turns that the cache did not hold; the 13717 (13717-13718) new tokens of the files are read once); first turn (nothing cached) first token: 0.96 s (0.96-0.96).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 641.0 | 0.964 | 126.7 |
| 1 | 3776 | 656 | 3120 | 2006.2 | 1.572 | 153.0 |
| 2 | 5309 | 3839 | 1470 | 1201.4 | 1.238 | 153.1 |
| 3 | 8742 | 5372 | 3370 | 2129.4 | 1.599 | 141.3 |
| 4 | 11655 | 8793 | 2862 | 1958.1 | 1.479 | 154.9 |
| 5 | 14601 | 11702 | 2899 | 2025.7 | 1.447 | 122.9 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 58 s.
