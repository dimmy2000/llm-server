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
strata --pack iq3_xxs --native Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf --ple-gguf Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf --expert-profile expert-profile.bin --expert-cache 4400 --spec 4 --spec-min-p 0.5 --mtp rt --max-context 131072 --kv int8 --prefill 4096 --vram-reserve-mib 300 --vram-reserve-later-mib 2048
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
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 125.3 (109.2-147.4) | 0.26 (0.22-0.28) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2538.7 (2495.3-2564.9) | not measured | 1.60 (1.58-1.62) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 4309.3 (4253.8-4319.7) | not measured | 3.75 (3.73-3.79) |
| agent session, follow-up turns | 14550 (14549-14582) at the last turn | see below | up to 64 | 3 | see below | 146.0 (83.3-178.6) | 1.44 (1.20-1.59) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 68.7 % (68.6-68.8); earlier-turn tokens read again per session: 4 (3-74) (earlier turns that the cache did not hold; the 13719 (13718-13720) new tokens of the files are read once); first turn (nothing cached) first token: 0.96 s (0.95-0.96).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 641.6 | 0.964 | 121.2 |
| 1 | 3760 | 637 | 3123 | 2005.5 | 1.574 | 118.3 |
| 2 | 5293 | 3753 | 1540 | 1245.2 | 1.26 | 114.2 |
| 3 | 8726 | 5357 | 3369 | 2138.1 | 1.592 | 140.1 |
| 4 | 11627 | 8765 | 2862 | 1951.7 | 1.483 | 123.5 |
| 5 | 14550 | 11651 | 2899 | 2016.4 | 1.454 | 109.3 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 63 s.
