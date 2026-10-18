| `--no-cuda-graph` | disable CUDA Graph decode | graphs on |
| `--no-tp-mailbox` | keep the captured `--tp 2` all-reduces on cross-device copies; see [Two GPUs](#two-gpus) | mailbox on without P2P |
| `--embedding-host` | keep the token embedding table in one copy in pinned host memory that every GPU reads in place over PCIe, instead of one copy per GPU: frees its VRAM (1.18 GiB per GPU for Qwen3.8-27B) for the KV pool, identical results; see [Two GPUs](#two-gpus) | off |
| `--no-prefix-reuse` | disable compatible-prefix caching | prefix reuse on |
| `--device-state-slots N` | extra Device checkpoint StateImages beyond the active-lane guarantee | `max-concurrency`; `max(2 * max-concurrency, 8)` at `--tp 2` |
| `--host-state-slots N` | pinned Host StateImage capacity | `8`; `0` at `--tp 2` |
| `--host-kv-mib N` | shared pinned Host Main/Backend KV byte capacity in MiB | `8192`; `0` at `--tp 2` |
| `--max-private-continuations N` | private continuation descriptor capacity | `2 * max-concurrency`; `max(2 * max-concurrency, 8)` at `--tp 2` |
| `--max-shared-prefixes N` | Engine-wide shared stable-prefix descriptor capacity | `max(max-concurrency, 4)` |
| `--max-long-anchors-per-continuation N` | private long-anchor limit per continuation | `2` |
| `--turn-anchors N` | private long-anchor opportunities at the last N message boundaries before the final message, so a cancelled or edited turn resumes from the end of the previous turn instead of re-prefilling the conversation (`0` disables) | `1` |
| `--no-thinking` | disable thinking by default | thinking on |
| `--preserve-thinking` | preserve closed-turn assistant reasoning by default | off |
| `--cors` | permissive browser CORS headers | off |
| `--temperature F` | process-level temperature override | unset |
| `--top-p F` | process-level top-p override | unset |
| `--top-k N` | process-level top-k override (`0..20`; zero selects the top-20 cap) | unset |
| `--min-p F` | process-level min-p override | unset |
| `--presence-penalty F` | process-level presence-penalty override | unset |
| `--frequency-penalty F` | process-level frequency-penalty override | unset |
| `--seed N` | fixed seed when a request omits one | fresh random seed per request |
| `--greedy` | force exact argmax for all requests | off |

Context-cost coefficients resolve once at startup from generic defaults, matching compiled values,
and optional transfer or prefill entries from `--context-cost-presets FILE`. Prefill entries match
the hardware and a signature derived from the actual Text/Vision configuration, bindings and Uses.
A new representation without a matching measurement uses generic prefill coefficients. A malformed
file aborts startup; the operational context-cost record and JSONL `server_start` identify the
selected source.

Engine selects sampling defaults from the loaded architecture and the request's resolved thinking mode.
Qwen3.6-27B and Qwen3.8-27B use `1.0/0.95/20/0/0` for
temperature/top-p/top-k/min-p/presence penalty in thinking mode and `0.7/0.80/20/0/1.5` in
non-thinking mode. Qwen3.6-35B-A3B differs only in its thinking presence penalty, which is `1.5`.
Frequency penalty is `0` for all registered presets. Process flags override registered values,
request fields override process flags, and `--greedy` finally forces temperature `0`.

