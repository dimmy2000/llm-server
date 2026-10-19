# Community benchmark on NVIDIA GeForce RTX 5070 Ti

Measured on 2026-10-18 with `tools/strata_bench.py` (suite 1, 3 runs per test, medians with ranges). Speeds are the engine's own timings; first-token times are measured by the client over HTTP. Speed only: no correctness check was run.

## Hardware and software

- GPU and VRAM: NVIDIA GeForce RTX 5070 Ti, 16 GiB VRAM
- CPU: AMD Ryzen 9 9950X3D 16-Core Processor (16 cores, 32 threads); installed RAM: 59.4 GiB; storage: not measured
- OS: Linux 7.0.0-38-generic; GPU driver: 615.71.09; CUDA: not read
- Strata: project 0.1.45, commit 477ac13c; engine 0.1.45
- Background workloads and power limits: not recorded

## Model and configuration

- Model and quantization: qwen3.8-flash-next-iq3_s
- Context: 65536 tokens; parallel slots: 1
- Settings: the install's own configuration, unchanged; thinking off for the suite; temperature 0

## Method

Run by `python tools/strata_bench.py --long` against the HTTP API of a Strata server (already running); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 121.1 (114.4-157.3) | 0.23 (0.21-0.26) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2413.7 (2409.0-2423.7) | not measured | 1.68 (1.67-1.68) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 4046.9 (4046.8-4052.6) | not measured | 3.98 (3.98-3.98) |
| 32K prompt, fresh | 32049 (32049-32049) | 0 (0-0) | 24 cap | 3 | 4524.7 (4521.8-4531.9) | not measured | 7.11 (7.09-7.11) |
| agent session, follow-up turns | 14592 (14575-14606) at the last turn | see below | up to 64 | 3 | see below | 137.0 (122.9-165.0) | 1.56 (1.43-1.62) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 68.7 % (68.4-68.8); earlier-turn tokens read again per session: 74 (3-144) (earlier turns that the cache did not hold; the 13717 (13717-13717) new tokens of the files are read once); first turn (nothing cached) first token: 1.15 s (1.14-1.16).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 538.8 | 1.143 | 103.1 |
| 1 | 3743 | 623 | 3120 | 1989.5 | 1.582 | 125.1 |
| 2 | 5276 | 3736 | 1540 | 1078.6 | 1.441 | 136.9 |
| 3 | 8709 | 5269 | 3440 | 2141.4 | 1.622 | 130.5 |
| 4 | 11624 | 8762 | 2862 | 1851.5 | 1.562 | 150.4 |
| 5 | 14575 | 11676 | 2899 | 1877.0 | 1.559 | 131.3 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 85 s.
