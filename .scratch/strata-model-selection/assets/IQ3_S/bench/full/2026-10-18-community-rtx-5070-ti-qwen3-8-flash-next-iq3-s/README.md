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

Run by `python tools/strata_bench.py` against the HTTP API of a Strata server (already running); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 122.4 (113.3-157.5) | 0.22 (0.21-0.26) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2426.2 (2370.3-2427.1) | not measured | 1.67 (1.67-1.71) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 4061.7 (4032.4-4062.1) | not measured | 3.97 (3.97-4.00) |
| agent session, follow-up turns | 14599 (14510-14602) at the last turn | see below | up to 64 | 3 | see below | 141.8 (115.8-174.5) | 1.58 (1.43-1.71) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 68.7 % (68.7-68.8); earlier-turn tokens read again per session: 3 (2-74) (earlier turns that the cache did not hold; the 13717 (13716-13718) new tokens of the files are read once); first turn (nothing cached) first token: 1.15 s (1.15-1.16).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 537.0 | 1.148 | 98.6 |
| 1 | 3743 | 623 | 3120 | 1845.0 | 1.707 | 116.3 |
| 2 | 5276 | 3807 | 1469 | 1013.7 | 1.465 | 125.6 |
| 3 | 8694 | 5325 | 3369 | 2022.0 | 1.682 | 158.2 |
| 4 | 11583 | 8721 | 2862 | 1775.8 | 1.628 | 149.3 |
| 5 | 14510 | 11611 | 2899 | 1843.4 | 1.589 | 124.0 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 63 s.
