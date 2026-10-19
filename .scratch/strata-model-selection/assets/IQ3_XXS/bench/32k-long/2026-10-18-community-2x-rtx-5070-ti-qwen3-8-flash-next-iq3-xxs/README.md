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

Run by `python tools/strata_bench.py --long` against the HTTP API of a Strata server (already running); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 128.3 (111.5-172.4) | 0.21 (0.20-0.25) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 2562.8 (2547.5-2564.0) | not measured | 1.58 (1.58-1.59) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 4314.6 (4310.4-4336.5) | not measured | 3.74 (3.72-3.74) |
| 32K prompt, fresh | 32049 (32049-32049) | 0 (0-0) | 24 cap | 3 | 4802.8 (4784.3-4806.6) | not measured | 6.70 (6.69-6.72) |
| agent session, follow-up turns | 14566 (14545-14594) at the last turn | see below | up to 64 | 3 | see below | 150.5 (81.2-175.3) | 1.41 (1.20-1.50) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 68.7 % (68.7-68.8); earlier-turn tokens read again per session: 4 (3-74) (earlier turns that the cache did not hold; the 13718 (13717-13718) new tokens of the files are read once); first turn (nothing cached) first token: 0.96 s (0.94-0.96).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 653.1 | 0.945 | 128.2 |
| 1 | 3763 | 642 | 3121 | 2187.0 | 1.44 | 134.5 |
| 2 | 5296 | 3756 | 1540 | 1293.4 | 1.205 | 150.5 |
| 3 | 8729 | 5359 | 3370 | 2262.7 | 1.504 | 129.9 |
| 4 | 11648 | 8786 | 2862 | 2059.6 | 1.405 | 165.1 |
| 5 | 14594 | 11695 | 2899 | 2075.6 | 1.412 | 129.3 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 78 s.
