# llama.cpp

![llama](https://raw.githubusercontent.com/ggml-org/llama.brand/refs/heads/master/cover/llama-cpp/cover-llama-cpp-dark.svg)

<div align="center">

<b>LLM inference in C/C++</b>

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/github/v/release/ggml-org/llama.cpp?filter=v*&color=brightgreen)](https://github.com/ggml-org/llama.cpp/releases?q=tag:v0)
[![Nightly](https://img.shields.io/github/v/release/ggml-org/llama.cpp?label=nightly&filter=b*&color=orange)](https://github.com/ggml-org/llama.cpp/releases?q=b)
[![Server](https://img.shields.io/github/actions/workflow/status/ggml-org/llama.cpp/server.yml?label=Server)](https://github.com/ggml-org/llama.cpp/actions/workflows/server.yml)
[![Docker](https://img.shields.io/github/actions/workflow/status/ggml-org/llama.cpp/docker.yml?label=Docker)](https://github.com/ggml-org/llama.cpp/actions/workflows/docker.yml)
[![Winget](https://img.shields.io/github/actions/workflow/status/ggml-org/llama.cpp/winget.yml?label=Winget)](https://github.com/ggml-org/llama.cpp/actions/workflows/winget.yml)

[ggml](https://github.com/ggml-org/ggml) / [ops](https://github.com/ggml-org/llama.cpp/blob/master/docs/ops.md) / [maintainer PRs](https://github.com/ggml-org/llama.cpp/issues?q=is%3Apr%20is%3Aopen%20draft%3AFalse%20(author%3Argerganov%20OR%20author%3AKitaitiMakoto%20OR%20author%3Adanbev%20OR%20author%3Aaldehir%20OR%20author%3Amax-krasnyansky%20OR%20author%3ACISC%20OR%20author%3Aggerganov%20OR%20author%3Aam17an%20OR%20author%3Ajhen0409%20OR%20author%3Abartowski1182%20OR%20author%3Anikwen%20OR%20author%3Ahipudding%20OR%20author%3Aravi9%20OR%20author%3AServeurpersoCom%20OR%20author%3Apwilkin%20OR%20author%3Areeselevine%20OR%20author%3Angxson%20OR%20author%3Ajeffbolznv%20OR%20author%3Amarty1885%20OR%20author%3A0cc4m%20OR%20author%3ATitaniumtown%20OR%20author%3Aangt%20OR%20author%3AIMbackK%20OR%20author%3Aarthw%20OR%20author%3AJohannesGaessler%20OR%20author%3AORippler%20OR%20author%3Aruixiang63%20OR%20author%3Axctan%20OR%20author%3Aallozaur%20OR%20author%3Ayomaytk%20OR%20author%3Aaendk%20OR%20author%3Awine99%20OR%20author%3Agaugarg-nv%20OR%20author%3Ataronaeo%20OR%20author%3Aforforever73%20OR%20author%3Alhez%20OR%20author%3Anetrunnereve%20OR%20author%3Afairydreaming)%20sort%3Aupdated-desc) / [dev stats](https://github.com/ggml-org/llama.cpp-dev) / [lib llama API](https://github.com/ggml-org/llama.cpp/issues/9289) / [llama-server REST API](https://github.com/ggml-org/llama.cpp/issues/9291)

</div>

## Quick start

A few options to get `llama.cpp` installed on your machine:

- Visit https://llama.app and follow the instructions
- Run with Docker - see our [Docker documentation](docs/docker.md)
- Download pre-built binaries from the [releases page](https://github.com/ggml-org/llama.cpp/releases)
- Build from source by cloning this repository - check out [our build guide](docs/build.md)

Once installed:

```sh
# Download and run a model directly from Hugging Face
llama cli -hf ggml-org/Qwen3.5-0.8B-GGUF

# Launch OpenAI-compatible API server
llama serve -hf ggml-org/Qwen3.5-0.8B-GGUF
```

<table align="center">
    <tr>
        <td align="center" width=50%>
            <img width="1310" height="888" alt="VLM session with `llama cli`" src="https://github.com/user-attachments/assets/88726b48-1713-48aa-a525-95a02e78afc4" />
            <i>VLM session with <b>llama cli</b></i>
        </td>
        <td align="center">
            <img width="1392" height="958" alt="Built-in web UI against `llama serve` running Qwen 3.6" src="https://github.com/user-attachments/assets/b402f972-2e32-4def-8771-8d849f08cf2e" />
            <i>Built-in web UI against <b>llama serve</b></i>
        </td>
    </tr>
<table>

## Description

The main goal of `llama.cpp` is to enable LLM (and VLM) inference with minimal setup and state-of-the-art performance on
a wide range of hardware - locally and in the cloud.

- Plain C/C++ implementation without any dependencies
- Apple silicon is a first-class citizen - optimized via ARM NEON, Accelerate and Metal frameworks
- AVX, AVX2, AVX512 and AMX support for x86 architectures
- RVV, ZVFH, ZFH, ZICBOP and ZIHINTPAUSE support for RISC-V architectures
- 1.5-bit, 2-bit, 3-bit, 4-bit, 5-bit, 6-bit, and 8-bit integer quantization for faster inference and reduced memory use
- Custom CUDA kernels for running LLMs on NVIDIA GPUs (support for AMD GPUs via HIP and Moore Threads GPUs via MUSA)
- Vulkan and SYCL backend support
- CPU+GPU hybrid inference to partially accelerate models larger than the total VRAM capacity

The `llama.cpp` project is build on top of the [ggml](https://github.com/ggml-org/ggml) library.

## Supported backends

| Backend | Target devices |
| --- | --- |
| [BLAS](docs/build.md#blas-build) | All |
| [BLIS](docs/backend/BLIS.md) | All |
| [CANN](docs/build.md#cann) | Ascend NPU |
| [CUDA](docs/build.md#cuda) | Nvidia GPU |
| [HIP](docs/build.md#hip) | AMD GPU |
| [Hexagon](docs/backend/snapdragon/README.md) | Snapdragon |
| [IBM zDNN](docs/backend/zDNN.md) | IBM Z & LinuxONE |
| [MUSA](docs/build.md#musa) | Moore Threads GPU |
| [Metal](docs/build.md#metal-build) | Apple Silicon |
| [OpenCL](docs/backend/OPENCL.md) | Adreno GPU |
| [OpenVINO [In Progress]](docs/backend/OPENVINO.md) | Intel CPUs, GPUs, and NPUs |
| [RPC](https://github.com/ggml-org/llama.cpp/tree/master/tools/rpc) | All |
| [SYCL](docs/backend/SYCL.md) | Intel GPU |
| [VirtGPU](docs/backend/VirtGPU.md) | VirtGPU APIR |
| [Vulkan](docs/build.md#vulkan) | GPU |
| [WebGPU](docs/build.md#webgpu) | All |
| [ZenDNN](docs/build.md#zendnn) | AMD CPU |

## Documentation

#### Tools

- [cli](tools/cli/README.md)
- [completion](tools/completion/README.md)
- [server](tools/server/README.md)
- [GBNF grammars](grammars/README.md)

#### Development

- [How to build](docs/build.md)
- [Running on Docker](docs/docker.md)
- [Build on Android](docs/android.md)
- [Multi-GPU usage](docs/multi-gpu.md)
- [Performance troubleshooting](docs/development/token_generation_performance_tips.md)
- [GGML tips & tricks](https://github.com/ggml-org/llama.cpp/wiki/GGML-Tips-&-Tricks)
- [XCFramework](docs/xcframework.md)
- [Completions](docs/completions.md)
- [Models](docs/models.md)
- [Release process](docs/release.md)

## Contributing

- Contributors can open PRs
- Collaborators will be invited based on contributions
- Maintainers can push to branches in the `llama.cpp` repo and merge PRs into the `master` branch
- Any help with managing issues, PRs and projects is very appreciated!
- Read the [CONTRIBUTING.md](CONTRIBUTING.md) for more information

## Acknowledgements

- [yhirose/cpp-httplib](https://github.com/yhirose/cpp-httplib) - Single-header HTTP server, used by `llama-server` - MIT license
- [nothings/stb](https://github.com/nothings/stb) - Single-header image format decoder, used by multimodal subsystem - Public domain
- [nlohmann/json](https://github.com/nlohmann/json) - Single-header JSON library, used by various tools/examples - MIT License
- [mackron/miniaudio](https://github.com/mackron/miniaudio) - Single-header audio format decoder, used by multimodal subsystem - Public domain
- [sheredom/subprocess.h](https://github.com/sheredom/subprocess.h) - Single-header process launching solution for C and C++ - Public domain
# Using multiple GPUs with llama.cpp

This guide explains how to run [llama.cpp](https://github.com/ggml-org/llama.cpp) across more than one GPU. It covers the split modes, the command-line flags that control them, the limitations you need to know about, and ready-to-use recipes for `llama-cli` and `llama-server`.

The CLI arguments listed here are the same for both tools - or most llama.cpp binaries for that matter.

---

## When you need multi-GPU

Reach for multi-GPU when one of these is true:

- **The model doesn't fit in a single GPU's VRAM.** By spreading the weights across two or more GPUs the whole model can stay on accelerators. Otherwise part of the model will need to be run off of the comparatively slower system RAM.
- **You want more throughput.** By distributing the computation across multiple GPUs, each individual GPU has to do less work. This can result in better prefill and/or token generation performance, depending on the split mode and interconnect speed vs. the speed of an individual GPU.

---

## The split modes

Set with `--split-mode` / `-sm`.

| Mode | What it does | When to use |
|---|---|---|
| `none` | Use a single GPU only. Pick which one with `--main-gpu`. | You explicitly want to confine the model to one GPU even though more are visible. |
| `layer` (**default**) | Pipeline parallelism. Each GPU holds a contiguous slice of layers. The KV cache for layer *l* lives on the GPU that owns layer *l*. | Default and most compatible multi-GPU choice. You want more memory than a single GPU provides and your priority is a fast prefill. Can tolerate slow interconnect speeds between GPUs. |
| `row` | **Deprecated.** Older row-split tensor-parallel path with comparatively poor performance. Splits only dense weights across GPUs. Superseded by `tensor` which should be universally superior if it can be used. | Avoid in new deployments. |
| `tensor` | **EXPERIMENTAL.** Tensor parallelism that splits both weights *and* KV across the participating GPUs via a "meta device" abstraction. | You want more memory than a single GPU provides and your priority is fast token generation. Prefill speeds approach pipeline parallel speeds for large, dense models and fast GPU interconnect speeds. Treat as experimental as the code is less mature than pipeline parallelism. Performance should be good for multiple NVIDIA GPUs using the CUDA backend, no guarantees otherwise. |

> Pipeline parallel (`layer`) vs. tensor parallel (`tensor`): pipeline-parallel runs different layers on different GPUs and processes tokens sequentially through the pipeline. This minimizes data transfers between GPUs but requires many tokens to scale well. Tensor-parallel splits each layer across GPUs and does multiple cross-GPU reductions per layer. This enables parallelizing any workload but is much more bottlenecked by the GPU interconnect speed. Pipeline-parallel maximizes batch throughput; tensor-parallel minimizes latency.

---

## Command-line arguments reference

| Short | Long | Value | Default | Notes |
|---|---|---|---|---|
| `-sm` | `--split-mode` | `none` \| `layer` \| `tensor` | `layer` | See modes above. |
| `-ts` | `--tensor-split` | comma-separated proportions, e.g. `3,1` | mode-dependent | How much of the model goes to each GPU. If omitted, `layer`/`row` use automatic splitting proportional to memory, while `tensor` splits tensor segments evenly. With `3,1` on two GPUs, GPU 0 gets 75 %, GPU 1 gets 25 %. The values follow the order in `--device`. |
| `-mg` | `--main-gpu` | integer device index | `0` | The single GPU used in `--split-mode none`. |
| `-ngl` | `--n-gpu-layers` / `--gpu-layers` | integer \| `auto` \| `all` | `auto` | Maximum number of layers to keep in VRAM. Use `999` or `all` to push everything possible to the GPUs. |
| `-dev` | `--device` | comma-separated device names, or `none` | auto | Restrict which devices llama.cpp may use. See `--list-devices` for names. |
| | `--list-devices` | - | - | Print the available devices and their memory. Run this first to learn the names you'd pass to `--device`. |
| `-fa` | `--flash-attn` | `on` \| `off` \| `auto` | `auto` | Required when using `--split-mode tensor` and/or quantized V cache. Supported (and therefore enabled by default) for most combinations of models and backends. |
| `-ctk` | `--cache-type-k` | `f32` \| `f16` \| `bf16` \| `q8_0` \| `q4_0` \| ... | `f16` | KV cache type for K. |
| `-ctv` | `--cache-type-v` | same as `-ctk` | `f16` | KV cache type for V. |
| `-fit` | `--fit` | `on` \| `off` | `on` | Auto-fit unset args to device memory. **Not supported with `tensor`. You may need to manually set the `--ctx-size` to make the model fit.**  |

As for any CUDA program, the environment variable `CUDA_VISIBLE_DEVICES` can be used to control which GPUs to use for the CUDA backend: if you set it, llama.cpp only sees the specified GPUs. Use `--device` for selecting GPUs from among those visible to llama.cpp, this works for any backend.

---

## Recipes

### 1. Default - pipeline parallel across all visible GPUs

```bash
llama-cli -m model.gguf
llama-server -m model.gguf
```

Easiest configuration. KV cache spreads across the GPUs along with the layers. `--fit` (on by default) sizes things automatically.

### 2. Pipeline parallel with a custom split ratio

```bash
llama-cli -m model.gguf -ts 3,1
```

Useful when GPUs have different memory: GPU 0 (3 parts) and GPU 1 (1 part). Proportions are normalized so `-ts 3,1` is the same as e.g. `-ts 75,25`.

### 3. Single-GPU mode, picking a specific GPU

```bash
llama-cli --list-devices
llama-cli -m model.gguf -dev CUDA1
```

Use only the device listed as `CUDA1` when calling with `--list-devices`.

### 4. Tensor parallelism (experimental)

```bash
llama-cli -m model.gguf -sm tensor -ctk f16 -ctv f16
```

- `--flash-attn off` or (`--flash-attn auto` resolving to `off` when it isn't supported) is a hard error.
- KV cache types must be non-quantized: `f32`, `f16`, or `bf16`. Support for quantized KV cache is not implemented and trying to use it will result in an error.
- Mark this configuration as experimental in your tooling: validate output quality before deploying.
- `--split-mode tensor`is not implemented for all architectures. The following will fail with *"LLAMA_SPLIT_MODE_TENSOR not implemented for architecture '...'"*:

  - **MoE / hybrid:** Grok, MPT, OLMoE, DeepSeek2, GLM-DSA, Nemotron-H, Nemotron-H-MoE, Granite-Hybrid, LFM2-MoE, Minimax-M2, Mistral4, Kimi-Linear, Jamba, Falcon-H1
  - **State-space / RWKV-style:** Mamba, Mamba2 (and the hybrid Mamba-attention models above)
  - **Other:** PLAMO2, MiniCPM3, Gemma-3n, OLMo2, BitNet, T5

### 5. With NCCL

There's no runtime flag for NCCL - it's selected at build time (`-DGGML_CUDA_NCCL=ON`, this is the default). Note that NCCL is **not** automatically distributed with CUDA and you may need to install it manually - when in doubt check the CMake log to see whether or not it can find the package. When llama.cpp is compiled with NCCL support it uses it automatically for cross-GPU reductions in `tensor` mode. When NCCL is missing on a multi-GPU build, you'll see this one-time warning and performance will be lower:

```
NVIDIA Collective Communications Library (NCCL) is unavailable, multi GPU performance will be suboptimal
```

When using the "ROCm" backend (which is the ggml CUDA code translated for AMD via HIP), the AMD equivalent RCCL can be used by compiling with `-DGGML_HIP_RCCL=ON`. Note that RCCL is by default *disabled* because (unlike NCCL) it was not universally beneficial during testing.
### 6. With CUDA peer-to-peer access (`GGML_CUDA_P2P`)

CUDA peer-to-peer (P2P) lets GPUs transfer data directly between each other instead of going through system memory, which generally improves multi-GPU performance. It is **opt-in** at runtime - set the environment variable `GGML_CUDA_P2P` to any value to enable it:

```bash
GGML_CUDA_P2P=1 llama-cli -m model.gguf -sm tensor
```

P2P requires driver support (usually restricted to workstation/datacenter GPUs) and **may cause crashes or corrupted outputs on some motherboards or BIOS configurations** (e.g. when IOMMU is enabled). If you see instability after enabling it, unset the variable.

---

## Troubleshooting

| Symptom | How to fix |
|---|---|
| Startup error *"SPLIT_MODE_TENSOR requires flash_attn to be enabled"* | Add `-fa on` or remove `-fa off`. |
| Startup error *"simultaneous use of SPLIT_MODE_TENSOR and KV cache quantization not implemented"* | Use `-ctk f16 -ctv f16` (or `bf16`/`f32`) with `--split-mode tensor`. |
| Startup error *"LLAMA_SPLIT_MODE_TENSOR not implemented for architecture 'X'"* | Architecture not on the TENSOR allow-list. Use `--split-mode layer`. |
| Warning *"NCCL is unavailable, multi GPU performance will be suboptimal"* | llama.cpp wasn't built with NCCL. Either accept the lower performance or install NCCL and rebuild. |
| CUDA OOM at startup or during prefill in `--split-mode tensor` | Auto-fit is disabled in this mode, so reduce memory pressure yourself. In order from least to most disruptive: lower `--ctx-size` (`-c`) (KV cache is roughly proportional to `n_ctx`); for `llama-server`, lower `--parallel` (`-np`) (a slot KV cache is allocated per concurrent sequence); as a last resort, reduce `--n-gpu-layers` (`-ngl`) (the remaining layers run on CPU and inference will be much slower). |
| Performance is worse with multi-GPU than single-GPU | The performance is bottlenecked by GPU interconnect speed. For `--split-mode tensor`, verify that NCCL is being used. Try `--split-mode layer` (less communication than `tensor`). Increase GPU interconnect speed via more PCIe lanes or e.g. NVLink (if available). |
| GPU not used at all | `--n-gpu-layers` is `0` or too low - try explicitly setting `-ngl all`. Or you are accidentally hiding the GPUs via an environment variable like `CUDA_VISIBLE_DEVICES=-1`. Or your build doesn't include support for the relevant backend. |
| Crashes or corrupted outputs after setting `GGML_CUDA_P2P=1` | Some motherboards and BIOS settings (e.g. with IOMMU enabled) don't support CUDA peer-to-peer reliably. Unset `GGML_CUDA_P2P`. |
# Speculative Decoding

llama.cpp supports speculative decoding, a technique that can significantly accelerate token generation by predicting multiple tokens ahead of the main model.

[Speculative decoding](https://en.wikipedia.org/wiki/Transformer_(deep_learning)#Speculative_decoding) leverages the fact that computing n tokens in a batch (as in prompt processing) is more efficient than computing n sequentially (as in response generation). By generating draft tokens quickly and then verifying them with the target model in a single batch, this approach can achieve substantial speedups when the draft predictions are frequently correct.

## Implementations

The `llama-server` application supports several implementations of speculative decoding. An implementation with draft model can be mixed with an implementation without draft model.

### Draft Model (`draft`)

A much smaller model (called the _draft model_) generates drafts.
A draft model is the most used approach in speculative decoding.

### EAGLE-3 (`draft-eagle3`)

EAGLE-3 uses a small draft model that reads the target model's hidden states to predict the next tokens, so it
reaches higher acceptance than a standalone draft model of the same size. The draft is a one-layer transformer
trained for a specific target model; it shares the target model's tokenizer and, optionally, uses a reduced draft
vocabulary with its own `lm_head`, which is mapped back using a `d2t` table.

Convert the EAGLE-3 checkpoint with `--target-model-dir` so it inherits the target's tokenizer and the layer
indices to read. Both the SpecForge `LlamaForCausalLMEagle3` and the vLLM/AngelSlim `Eagle3LlamaForCausalLM`
checkpoint formats are supported (for example [`AngelSlim/Qwen3-4B_eagle3`](https://huggingface.co/AngelSlim/Qwen3-4B_eagle3)
for `Qwen/Qwen3-4B`):

```bash
python convert_hf_to_gguf.py AngelSlim/Qwen3-4B_eagle3 \
    --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-eagle3.gguf

llama-server -m Qwen3-4B.gguf -md Qwen3-4B-eagle3.gguf --spec-type draft-eagle3
```

Supported EAGLE-3 draft models include:

- [yuhuili/EAGLE3-LLaMA3.1-Instruct-8B](https://huggingface.co/yuhuili/EAGLE3-LLaMA3.1-Instruct-8B)
- [yuhuili/EAGLE3-LLaMA3.3-Instruct-70B](https://huggingface.co/yuhuili/EAGLE3-LLaMA3.3-Instruct-70B)
- [RedHatAI/gemma-4-31B-it-speculator.eagle3](https://huggingface.co/RedHatAI/gemma-4-31B-it-speculator.eagle3)
- [RedHatAI/gemma-4-26B-A4B-it-speculator.eagle3](https://huggingface.co/RedHatAI/gemma-4-26B-A4B-it-speculator.eagle3)
- [Tengyunw/qwen3_8b_eagle3](https://huggingface.co/Tengyunw/qwen3_8b_eagle3)
- [Tengyunw/qwen3_30b_moe_eagle3](https://huggingface.co/Tengyunw/qwen3_30b_moe_eagle3)
- [AngelSlim/Qwen3-1.7B_eagle3](https://huggingface.co/AngelSlim/Qwen3-1.7B_eagle3)
- [AngelSlim/Qwen3-4B_eagle3](https://huggingface.co/AngelSlim/Qwen3-4B_eagle3)
- [AngelSlim/Qwen3-8B_eagle3](https://huggingface.co/AngelSlim/Qwen3-8B_eagle3)
- [AngelSlim/Qwen3-14B_eagle3](https://huggingface.co/AngelSlim/Qwen3-14B_eagle3)
- [AngelSlim/Qwen3-32B_eagle3](https://huggingface.co/AngelSlim/Qwen3-32B_eagle3)
- [AngelSlim/Qwen3-a3B_eagle3](https://huggingface.co/AngelSlim/Qwen3-a3B_eagle3)
- [RedHatAI/gpt-oss-20b-speculator.eagle3](https://huggingface.co/RedHatAI/gpt-oss-20b-speculator.eagle3)
- [lmsys/EAGLE3-gpt-oss-120b-bf16](https://huggingface.co/lmsys/EAGLE3-gpt-oss-120b-bf16)
- [nvidia/gpt-oss-120b-Eagle3-long-context](https://huggingface.co/nvidia/gpt-oss-120b-Eagle3-long-context)

For the full and up-to-date list of supported models, see #18039.

### DFlash (`draft-dflash`)

DFlash produces an entire block of draft tokens in a single forward pass (block diffusion) and
injects the target model's hidden states into the draft model's attention, instead of drafting one
token at a time. This keeps the draft model small while making drafting GPU-friendly. Unlike EAGLE-3
(a single-layer autoregressive draft), the DFlash draft uses several transformer layers but emits a
whole block per draft step.

The draft is a small block-diffusion model trained for a specific target (for example
`z-lab/Qwen3-4B-DFlash` for `Qwen/Qwen3-4B`). Convert it with `--target-model-dir` so it inherits the
target's tokenizer and token embeddings:

```bash
python convert_hf_to_gguf.py z-lab/Qwen3-4B-DFlash \
    --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-DFlash.gguf

llama-server -m Qwen3-4B.gguf -md Qwen3-4B-DFlash.gguf \
    --spec-type draft-dflash --spec-draft-n-max 15 -fa on --jinja
```

`--spec-draft-n-max` is clamped to the draft model's trained block size.

See:

- #22105

### DSpark (`draft-dspark`)

DSpark extends DFlash with a semi-autoregressive _Markov head_: the draft still emits a whole
block per forward pass, but each block position's logits are biased by a low-rank term keyed on
the previous token, chained in-graph across the block. This keeps drafting at one decode per
block while recovering some of the left-to-right signal that pure block diffusion loses.

The draft is a small DeepSpec checkpoint trained for a specific target (for example
[`deepseek-ai/dspark_qwen3_4b_block7`](https://huggingface.co/deepseek-ai/dspark_qwen3_4b_block7)
for `Qwen/Qwen3-4B`). Convert it with `--target-model-dir` so it inherits the target's tokenizer
and token embeddings:

```bash
python convert_hf_to_gguf.py deepseek-ai/dspark_qwen3_4b_block7 \
    --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-DSpark.gguf

llama-server -m Qwen3-4B.gguf -md Qwen3-4B-DSpark.gguf \
    --spec-type draft-dspark --spec-draft-n-max 7 -fa on --jinja
```

`--spec-draft-n-max` is clamped to the draft model's trained block size.

`--spec-draft-conf-min P` truncates each drafted block at the first position whose predicted
acceptance (from the draft's confidence head, if present) falls below `P` (default 0 = disabled).

Currently only drafts with a Qwen3 backbone are supported; support for other backbones
(e.g. Gemma4) is planned.

DSpark drafts exported in the [speculators](https://github.com/vllm-project/speculators) format
(for example [`RedHatAI/gemma-4-31B-it-speculator.dspark`](https://huggingface.co/RedHatAI/gemma-4-31B-it-speculator.dspark))
convert the same way.

See:

- #25173

### n-gram Cache (`ngram-cache`)

An n-gram is a sequence of n tokens. The n-gram cache implementation maintains statistics about short n-gram sequences.
A draft is computed using probabilities derived from these statistics. External statistics can also be loaded from files for improved accuracy.

See:

- #5479, #6828, #6848

### n-gram Map (`ngram-simple`, `ngram-map-*`)

These implementations search the token history for patterns and use matching sequences as draft candidates.
They require no additional model but rely on patterns that have already appeared in the generated text.
An example to use this approach can be the rewriting of source code by a LLM.

#### n-gram Map (`ngram-simple`)

This implementation looks for the last n-gram in history that matches the current n-gram and creates a draft using the m tokens following the matched n-gram. It is the simplest self-speculative approach with minimal overhead.

```
llama-server [...] --spec-type ngram-simple --spec-draft-n-max 64
```

#### n-gram Map Key (`ngram-map-k`)

This implementation looks for the current n-gram of size n (called the _key_) in the token history. If the key n-gram is followed by the same m tokens (called the _mgram_) multiple times, it creates a draft using these m tokens. This approach requires a minimum number of occurrences (argument `--spec-ngram-map-k-min-hits`, default is 1) before generating drafts.

The number of accepted tokens is stored for each used n-gram.

**Example:**
```
llama-server [...] --spec-type ngram-map-k --spec-draft-n-max 64
```

#### n-gram Map Key-4-Values (`ngram-map-k4v`)

This experimental implementation looks for the current n-gram of size n (called the _key_) in the token history. For each key, up to four _values_ (n-grams of size m, called _mgrams_) are tracked. An internal statistic counts the occurrences of each mgram after the key n-gram. If one mgram is significantly more frequent than the others, it is used as the draft.

The number of accepted tokens is stored for each used n-gram.

**Example:** Server options to be used if there are a lot of longer repetitions.
```
llama-server [...] --spec-type ngram-map-k4v --spec-ngram-map-k4v-size-n 8 --spec-ngram-map-k4v-size-m 8 --spec-ngram-map-k4v-min-hits 2 --spec-draft-n-max 64
```

### n-gram Mod (`ngram-mod`)

Add basic ngram hasher for speculative decoding:

- For each ngram, compute a hash using LCG
- For each computed hash, store the next token
- During speculation, iteratively compute the rolling hash of the last n tokens and pick the next token from the storage

Some characteristics:

- Lightweight (~16 MB)
- Constant memory and complexity
- Can generate variable draft lengths (i.e. m is not fixed)

Currently, a single hash pool is shared across all server slots, so different requests can benefit from each other.

**Sample usage:**

```
# notes:
# - small `n` are not recommended
# - MoEs require long drafts
# - dense models: can reduce `--spec-ngram-mod-n-min` and `--spec-ngram-mod-n-max`

llama-server ... --spec-type ngram-mod --spec-ngram-mod-n-match 24 --spec-ngram-mod-n-min 48 --spec-ngram-mod-n-max 64
```

Applications:

- Iterating over a block of text/code (e.g. in llama.vim)
- Reasoning models (when they have to repeat their thinking in the final answer)
- Summarization

Example Video:

- See #19164

### Differences between ngram-simple, ngram-map and ngram-mod

- ngram-simple looks for a previous matching n-gram and inserts the following m-gram.
- ngram-map-k looks for a previous matching n-gram and inserts the following m-gram but uses an internal hash-map of n-grams in the current context window.
- ngram-mod uses a hash pool which is shared across all server slots. The hash pool is a map from n-gram hash to the next token (not the next m-gram as in ngram-map).

## Command-Line Options

If a draft model is combined with a draftless decoding the draftless decoding has higher precedence.

### Backend Sampling

Use `--backend-sampling` to run supported target-model samplers on the model backend. Draft-model sampling uses the backend by default and can be controlled with `--spec-draft-backend-sampling` and `--no-spec-draft-backend-sampling`.

Unsupported samplers and device layouts fall back to CPU sampling. Tensor split mode does not support backend sampling. A fixed seed produces repeatable random draws, but stochastic CPU and backend sampling can still select different tokens because floating-point operations can differ between implementations and devices. Use greedy sampling when exact output matching is required.

### Synthetic Acceptance

`llama-server` and `llama-cli` can replace normal speculative verification with synthetic decisions for benchmarking. The generated output is not valid model output because accepted draft tokens do not have to match the target model.

Use exactly one of these options:

- `--spec-synth-rates P0,P1,...` sets unconditional per-position acceptance probabilities. Entry `i` is the probability that the first `i+1` draft tokens are all accepted. The number of entries must match the effective maximum draft length. Values must be finite, within `[0, 1]`, and monotonically non-increasing.
- `--spec-synth-len L` sets the target mean acceptance length, including the target token. For `K` maximum draft tokens, `L` must be within `[1, K+1]`. The server finds a constant conditional probability `p` such that `p + p^2 + ... + p^K = L - 1`, then uses unconditional rates `[p, p^2, ..., p^K]`.

### General Speculative Parameters

```
--spec-type [none|draft-simple|draft-eagle3|draft-dflash|draft-dspark|draft-mtp|ngram-cache|ngram-simple|ngram-map-k|ngram-map-k4v|ngram-mod]
                                        comma-separated list of types of speculative decoding to use
                                        (default: none)
                                        (env: LLAMA_ARG_SPEC_TYPE)
--spec-default                          use default speculative decoding config
                                        (enables ngram-mod)
```

### Draft Model Parameters

```
--spec-draft-model, -md, --model-draft  FNAME
                                        draft model for speculative decoding (default: unused)
                                        (env: LLAMA_ARG_SPEC_DRAFT_MODEL)
--spec-draft-hf, -hfd, -hfrd, --hf-repo-draft  <user>/<model>[:quant]
                                        HuggingFace repository for the draft model
                                        (env: LLAMA_ARG_SPEC_DRAFT_HF_REPO)
--spec-draft-n-max                      N
                                        number of tokens to draft for speculative decoding (default: 3)
                                        (env: LLAMA_ARG_SPEC_DRAFT_N_MAX)
--spec-draft-n-min                      N
                                        minimum number of draft tokens to use for speculative decoding (default: 0)
                                        (env: LLAMA_ARG_SPEC_DRAFT_N_MIN)
--spec-draft-p-split, --draft-p-split   P
                                        speculative decoding split probability (default: 0.10)
                                        (env: LLAMA_ARG_SPEC_DRAFT_P_SPLIT)
--spec-draft-p-min, --draft-p-min       P
                                        minimum speculative decoding probability (greedy) (default: 0.00)
                                        (env: LLAMA_ARG_SPEC_DRAFT_P_MIN)
--spec-draft-ngl, -ngld, --gpu-layers-draft, --n-gpu-layers-draft  N
                                        max. number of draft model layers to store in VRAM, either an exact number, 'auto', or 'all' (default: auto)
                                        (env: LLAMA_ARG_N_GPU_LAYERS_DRAFT)
--spec-draft-device, -devd, --device-draft  <dev1,dev2,..>
                                        comma-separated list of devices to use for offloading the draft model
                                        (use --list-devices to see available devices)
```

### Draft Model CPU Scheduling Parameters

```
--spec-draft-threads, -td, --threads-draft  N
                                        number of CPU threads to use during generation
--spec-draft-threads-batch, -tbd, --threads-batch-draft  N
                                        number of threads to use during batch and prompt processing (default: same as --threads-draft)
--spec-draft-cpu-mask, -Cd, --cpu-mask-draft  M
                                        Draft model CPU affinity mask. Complements cpu-range-draft
--spec-draft-cpu-range, -Crd, --cpu-range-draft  lo-hi
                                        Ranges of CPUs for affinity. Complements --cpu-mask-draft
--spec-draft-cpu-strict, --cpu-strict-draft  <0|1>
                                        Use strict CPU placement for draft model (default: same as --cpu-strict)
--spec-draft-prio, --prio-draft  N
                                        set draft process/thread priority : 0-normal, 1-medium, 2-high, 3-realtime
--spec-draft-poll, --poll-draft  <0|1>
                                        Use polling to wait for draft model work (default: same as --poll)
--spec-draft-cpu-mask-batch, -Cbd, --cpu-mask-batch-draft  M
                                        Draft model CPU affinity mask for batch. Complements cpu-range-batch-draft
--spec-draft-cpu-range-batch, -Crbd, --cpu-range-batch-draft  lo-hi
                                        Ranges of CPUs for affinity for batch. Complements --cpu-mask-batch-draft
--spec-draft-cpu-strict-batch, --cpu-strict-batch-draft  <0|1>
                                        Use strict CPU placement for draft model batch (default: --cpu-strict-draft)
--spec-draft-prio-batch, --prio-batch-draft  N
                                        set draft process/thread priority for batch : 0-normal, 1-medium, 2-high, 3-realtime
--spec-draft-poll-batch, --poll-batch-draft  <0|1>
                                        Use polling to wait for draft model work for batch (default: --poll-draft)
```

### Draft Model KV Cache and Tensor Override Parameters

```
--spec-draft-type-k, -ctkd, --cache-type-k-draft  TYPE
                                        KV cache data type for K for the draft model
                                        allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
                                        (env: LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K)
--spec-draft-type-v, -ctvd, --cache-type-v-draft  TYPE
                                        KV cache data type for V for the draft model
                                        allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
                                        (env: LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V)
--spec-draft-override-tensor, -otd, --override-tensor-draft  <tensor name pattern>=<buffer type>,...
                                        override tensor buffer type for draft model
--spec-draft-cpu-moe, -cmoed, --cpu-moe-draft
                                        keep all Mixture of Experts (MoE) weights in the CPU for the draft model
                                        (env: LLAMA_ARG_SPEC_DRAFT_CPU_MOE)
--spec-draft-n-cpu-moe, --spec-draft-ncmoe, -ncmoed, --n-cpu-moe-draft  N
                                        keep the MoE weights of the first N layers in the CPU for the draft model
                                        (env: LLAMA_ARG_SPEC_DRAFT_N_CPU_MOE)
```

### n-gram Mod Parameters

```
--spec-ngram-mod-n-match                N
                                        ngram-mod lookup length (default: 24)
--spec-ngram-mod-n-min                  N
                                        minimum number of ngram tokens to use for ngram-based speculative decoding (default: 48)
--spec-ngram-mod-n-max                  N
                                        maximum number of ngram tokens to use for ngram-based speculative decoding (default: 64)
```

### n-gram Simple Parameters

```
--spec-ngram-simple-size-n              N
                                        ngram size N for ngram-simple speculative decoding, length of lookup n-gram (default: 12)
--spec-ngram-simple-size-m              N
                                        ngram size M for ngram-simple speculative decoding, length of draft m-gram (default: 48)
--spec-ngram-simple-min-hits            N
                                        minimum hits for ngram-simple speculative decoding (default: 1)
```

### n-gram Map Key Parameters

```
--spec-ngram-map-k-size-n               N
                                        ngram size N for ngram-map-k speculative decoding, length of lookup n-gram (default: 12)
--spec-ngram-map-k-size-m               N
                                        ngram size M for ngram-map-k speculative decoding, length of draft m-gram (default: 48)
--spec-ngram-map-k-min-hits             N
                                        minimum hits for ngram-map-k speculative decoding (default: 1)
```

### n-gram Map Key-4-Values Parameters

```
--spec-ngram-map-k4v-size-n             N
                                        ngram size N for ngram-map-k4v speculative decoding, length of lookup n-gram (default: 12)
--spec-ngram-map-k4v-size-m             N
                                        ngram size M for ngram-map-k4v speculative decoding, length of draft m-gram (default: 48)
--spec-ngram-map-k4v-min-hits           N
                                        minimum hits for ngram-map-k4v speculative decoding (default: 1)
```

### `--spec-type TYPE`

Specifies a comma-separated list of speculative decoding types to use.

| Type | Description |
|------|-------------|
| `none` | No speculative decoding (default) |
| `draft-simple` | Use a simple draft model for speculation |
| `draft-eagle3` | Use an EAGLE-3 draft model that reads the target's hidden states |
| `draft-dflash` | Use a DFlash block-diffusion draft model that emits a block per step |
| `draft-dspark` | Use a DSpark draft model (DFlash backbone + semi-autoregressive Markov head) |
| `draft-mtp` | Use Multi Token Prediction (MTP) heads from the main model |
| `ngram-cache` | Use n-gram cache lookup |
| `ngram-simple` | Use simple n-gram pattern matching |
| `ngram-map-k` | Use n-gram pattern matching with n-gram-keys |
| `ngram-map-k4v` | Use n-gram pattern matching with n-gram-keys and up to four m-gram values (experimental) |
| `ngram-mod` | Use basic ngram hasher for speculative decoding with shared pool |

**Example:** Server-instance used to refactor source code.
```bash
./llama-server [...] --spec-type ngram-simple
```

**Example:** Multiple speculative implementations.
```bash
./llama-server [...] --spec-type ngram-mod,ngram-map-k4v
```

### `--spec-ngram-*-size-n N`

Sets the size N of the lookup n-gram for n-gram map based speculative decoding.
The n-gram size N determines how many tokens in a row to look back when searching for matching patterns.

Each n-gram implementation has its own parameter:

- `--spec-ngram-simple-size-n` for `ngram-simple`
- `--spec-ngram-map-k-size-n` for `ngram-map-k`
- `--spec-ngram-map-k4v-size-n` for `ngram-map-k4v`
- `--spec-ngram-mod-n-match` for `ngram-mod`

### `--spec-ngram-*-size-m M`

Sets the size M of the draft m-gram for n-gram map based speculative decoding.
The m-gram size determines how many tokens to draft when a match is found.
Larger values can provide more speedup but may reduce acceptance rate.

Each n-gram implementation has its own parameter:

- `--spec-ngram-simple-size-m` for `ngram-simple`
- `--spec-ngram-map-k-size-m` for `ngram-map-k`
- `--spec-ngram-map-k4v-size-m` for `ngram-map-k4v`

### `--spec-ngram-*-min-hits H`

This option defines how often a key has to appear in the token history to be used as a draft (default is 1).

Each n-gram implementation has its own parameter:

- `--spec-ngram-simple-min-hits` for `ngram-simple`
- `--spec-ngram-map-k-min-hits` for `ngram-map-k`
- `--spec-ngram-map-k4v-min-hits` for `ngram-map-k4v`

## Statistics
Each speculative decoding implementation prints statistics.

```
draft acceptance rate = 0.57576 (  171 accepted /   297 generated)
statistics ngram_simple: #calls = 15, #gen drafts = 5, #acc drafts = 5, #gen tokens = 187, #acc tokens = 73
statistics draft: #calls = 10, #gen drafts = 10, #acc drafts = 10, #gen tokens = 110, #acc tokens = 98
```

```
draft acceptance rate = 0.70312 (   90 accepted /   128 generated)
statistics ngram_mod: #calls = 810, #gen drafts = 15, #acc drafts = 15, #gen tokens = 960, #acc tokens = 730, dur(b,g,a) = 0.149, 0.347, 0.005 ms
```

```
statistics ngram_map_k: #calls(b,g,a) = 6 1690 26, #gen drafts = 26, #acc drafts = 26, #gen tokens = 1248, #acc tokens = 968, dur(b,g,a) = 2.234, 1.427, 0.016 ms
```


- `#calls(b,g,a)`: number of calls of begin (new prompt), generation and accumulation of this implementations
- `#gen drafts`: number of drafts generated by this implementation
- `#acc drafts`: number of drafts accepted (partially) by the main model
- `#gen tokens`: number of tokens generated by this implementation (including rejected tokens)
- `#acc tokens`: number of tokens accepted by the main model
- `dur(b,g,a): durations of begin (new prompt), generation and accumulation (process acceptance).

## Benchmarking

To measure the end-to-end effect of speculative decoding (throughput, latency, and draft acceptance) across diverse prompts, see the SPEED-Bench client in [tools/server/bench/speed-bench](../tools/server/bench/speed-bench/README.md).
It runs against a running `llama-server` and can compare a baseline run against a speculative-decoding run.
# Function Calling

[chat.h](../common/chat.h) (https://github.com/ggml-org/llama.cpp/pull/9639) adds support for [OpenAI-style function calling](https://platform.openai.com/docs/guides/function-calling) and is used in:
- `llama-server` when started w/ `--jinja` flag

## Universal support w/ Native & Generic handlers

Function calling is supported for all models (see https://github.com/ggml-org/llama.cpp/pull/9639):

- Native tool call formats supported:
  - Llama 3.1 / 3.3 (including builtin tools support - tool names for `wolfram_alpha`, `web_search` / `brave_search`, `code_interpreter`), Llama 3.2
  - Functionary v3.1 / v3.2
  - Hermes 2/3, Qwen 2.5
  - Qwen 2.5 Coder
  - Mistral Nemo
  - Firefunction v2
  - Command R7B
  - DeepSeek R1 (WIP / seems reluctant to call any tools?)

- Generic tool call is supported when the template isn't recognized by native format handlers (you'll see `Chat format: Generic` in the logs).
  - Use `--chat-template-file` to override the template when appropriate (see examples below)
  - Generic support may consume more tokens and be less efficient than a model's native format.

- Multiple/parallel tool calling is supported on some models but disabled by default, enable it by passing `"parallel_tool_calls": true` in the completion endpoint payload.

<details>
<summary>Show some common templates and which format handler they use</summary>

| Template | Format |
|----------|--------|
| Almawave-Velvet-14B.jinja | Hermes 2 Pro |
| AtlaAI-Selene-1-Mini-Llama-3.1-8B.jinja | Llama 3.x |
| CohereForAI-aya-expanse-8b.jinja | Generic |
| CohereForAI-c4ai-command-r-plus-default.jinja | Generic |
| CohereForAI-c4ai-command-r-plus-rag.jinja | Generic |
| CohereForAI-c4ai-command-r-plus-tool_use.jinja | Generic |
| CohereForAI-c4ai-command-r7b-12-2024-default.jinja | Command R7B (extract reasoning) |
| CohereForAI-c4ai-command-r7b-12-2024-rag.jinja | Command R7B (extract reasoning) |
| CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja | Command R7B (extract reasoning) |
| CohereForAI-c4ai-command-r7b-12-2024.jinja | Generic |
| DavieLion-Llama-3.2-1B-SPIN-iter3.jinja | Generic |
| Delta-Vector-Rei-12B.jinja | Mistral Nemo |
| EpistemeAI-Mistral-Nemo-Instruct-12B-Philosophy-Math.jinja | Mistral Nemo |
| FlofloB-83k_continued_pretraining_Qwen2.5-0.5B-Instruct_Unsloth_merged_16bit.jinja | Hermes 2 Pro |
| FlofloB-test_continued_pretraining_Phi-3-mini-4k-instruct_Unsloth_merged_16bit.jinja | Generic |
| HelpingAI-HAI-SER.jinja | Generic |
| HuggingFaceTB-SmolLM2-1.7B-Instruct.jinja | Generic |
| HuggingFaceTB-SmolLM2-135M-Instruct.jinja | Generic |
| HuggingFaceTB-SmolLM2-360M-Instruct.jinja | Generic |
| INSAIT-Institute-BgGPT-Gemma-2-27B-IT-v1.0.jinja | Generic |
| Ihor-Text2Graph-R1-Qwen2.5-0.5b.jinja | Hermes 2 Pro |
| Infinigence-Megrez-3B-Instruct.jinja | Generic |
| Josephgflowers-TinyLlama_v1.1_math_code-world-test-1.jinja | Generic |
| LGAI-EXAONE-EXAONE-3.5-2.4B-Instruct.jinja | Generic |
| LGAI-EXAONE-EXAONE-3.5-7.8B-Instruct.jinja | Generic |
| LatitudeGames-Wayfarer-12B.jinja | Generic |
| Magpie-Align-Llama-3-8B-Magpie-Align-v0.1.jinja | Generic |
| Magpie-Align-Llama-3.1-8B-Magpie-Align-v0.1.jinja | Generic |
| MaziyarPanahi-calme-3.2-instruct-78b.jinja | Generic |
| MiniMaxAI-MiniMax-Text-01.jinja | Generic |
| MiniMaxAI-MiniMax-VL-01.jinja | Generic |
| NaniDAO-deepseek-r1-qwen-2.5-32B-ablated.jinja | DeepSeek R1 (extract reasoning) |
| NexaAIDev-Octopus-v2.jinja | Generic |
| NousResearch-Hermes-2-Pro-Llama-3-8B-default.jinja | Generic |
| NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja | Hermes 2 Pro |
| NousResearch-Hermes-2-Pro-Mistral-7B-default.jinja | Generic |
| NousResearch-Hermes-2-Pro-Mistral-7B-tool_use.jinja | Hermes 2 Pro |
| NousResearch-Hermes-3-Llama-3.1-70B-default.jinja | Generic |
| NousResearch-Hermes-3-Llama-3.1-70B-tool_use.jinja | Hermes 2 Pro |
| NovaSky-AI-Sky-T1-32B-Flash.jinja | Hermes 2 Pro |
| NovaSky-AI-Sky-T1-32B-Preview.jinja | Hermes 2 Pro |
| OnlyCheeini-greesychat-turbo.jinja | Generic |
| Orenguteng-Llama-3.1-8B-Lexi-Uncensored-V2.jinja | Llama 3.x |
| OrionStarAI-Orion-14B-Chat.jinja | Generic |
| PowerInfer-SmallThinker-3B-Preview.jinja | Generic |
| PrimeIntellect-INTELLECT-1-Instruct.jinja | Generic |
| Qwen-QVQ-72B-Preview.jinja | Generic |
| Qwen-QwQ-32B-Preview.jinja | Hermes 2 Pro |
| Qwen-Qwen1.5-7B-Chat.jinja | Generic |
| Qwen-Qwen2-7B-Instruct.jinja | Generic |
| Qwen-Qwen2-VL-72B-Instruct.jinja | Generic |
| Qwen-Qwen2-VL-7B-Instruct.jinja | Generic |
| Qwen-Qwen2.5-0.5B.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-1.5B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-14B-Instruct-1M.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-14B.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-32B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-32B.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-3B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-72B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-7B-Instruct-1M.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-7B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-7B.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-Coder-32B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-Coder-7B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-Math-1.5B.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-Math-7B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-VL-3B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-VL-72B-Instruct.jinja | Hermes 2 Pro |
| Qwen-Qwen2.5-VL-7B-Instruct.jinja | Hermes 2 Pro |
| RWKV-Red-Team-ARWKV-7B-Preview-0.1.jinja | Hermes 2 Pro |
| SakanaAI-TinySwallow-1.5B-Instruct.jinja | Hermes 2 Pro |
| SakanaAI-TinySwallow-1.5B.jinja | Hermes 2 Pro |
| Sao10K-70B-L3.3-Cirrus-x1.jinja | Llama 3.x |
| SentientAGI-Dobby-Mini-Leashed-Llama-3.1-8B.jinja | Llama 3.x |
| SentientAGI-Dobby-Mini-Unhinged-Llama-3.1-8B.jinja | Llama 3.x |
| Steelskull-L3.3-Damascus-R1.jinja | Llama 3.x |
| Steelskull-L3.3-MS-Nevoria-70b.jinja | Llama 3.x |
| Steelskull-L3.3-Nevoria-R1-70b.jinja | Llama 3.x |
| THUDM-glm-4-9b-chat.jinja | Generic |
| THUDM-glm-edge-1.5b-chat.jinja | Generic |
| Tarek07-Progenitor-V1.1-LLaMa-70B.jinja | Llama 3.x |
| TheBloke-FusionNet_34Bx2_MoE-AWQ.jinja | Generic |
| TinyLlama-TinyLlama-1.1B-Chat-v1.0.jinja | Generic |
| UCLA-AGI-Mistral7B-PairRM-SPPO-Iter3.jinja | Generic |
| ValiantLabs-Llama3.1-8B-Enigma.jinja | Llama 3.x |
| abacusai-Fewshot-Metamath-OrcaVicuna-Mistral.jinja | Generic |
| ai21labs-AI21-Jamba-1.5-Large.jinja | Generic |
| allenai-Llama-3.1-Tulu-3-405B-SFT.jinja | Generic |
| allenai-Llama-3.1-Tulu-3-405B.jinja | Generic |
| allenai-Llama-3.1-Tulu-3-8B.jinja | Generic |
| arcee-ai-Virtuoso-Lite.jinja | Hermes 2 Pro |
| arcee-ai-Virtuoso-Medium-v2.jinja | Hermes 2 Pro |
| arcee-ai-Virtuoso-Small-v2.jinja | Hermes 2 Pro |
| avemio-GRAG-NEMO-12B-ORPO-HESSIAN-AI.jinja | Generic |
| bespokelabs-Bespoke-Stratos-7B.jinja | Hermes 2 Pro |
| bfuzzy1-acheron-m1a-llama.jinja | Generic |
| bofenghuang-vigogne-2-70b-chat.jinja | Generic |
| bytedance-research-UI-TARS-72B-DPO.jinja | Generic |
| bytedance-research-UI-TARS-7B-DPO.jinja | Generic |
| bytedance-research-UI-TARS-7B-SFT.jinja | Generic |
| carsenk-phi3.5_mini_exp_825_uncensored.jinja | Generic |
| cyberagent-DeepSeek-R1-Distill-Qwen-14B-Japanese.jinja | DeepSeek R1 (extract reasoning) |
| cyberagent-DeepSeek-R1-Distill-Qwen-32B-Japanese.jinja | DeepSeek R1 (extract reasoning) |
| databricks-dbrx-instruct.jinja | Generic |
| deepseek-ai-DeepSeek-Coder-V2-Instruct.jinja | Generic |
| deepseek-ai-DeepSeek-Coder-V2-Lite-Base.jinja | Generic |
| deepseek-ai-DeepSeek-Coder-V2-Lite-Instruct.jinja | Generic |
| deepseek-ai-DeepSeek-R1-Distill-Llama-70B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Distill-Llama-8B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Distill-Qwen-1.5B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Distill-Qwen-14B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Distill-Qwen-32B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Distill-Qwen-7B.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1-Zero.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-R1.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-V2-Lite.jinja | Generic |
| deepseek-ai-DeepSeek-V2.5.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-DeepSeek-V3.jinja | DeepSeek R1 (extract reasoning) |
| deepseek-ai-deepseek-coder-33b-instruct.jinja | Generic |
| deepseek-ai-deepseek-coder-6.7b-instruct.jinja | Generic |
| deepseek-ai-deepseek-coder-7b-instruct-v1.5.jinja | Generic |
| deepseek-ai-deepseek-llm-67b-chat.jinja | Generic |
| deepseek-ai-deepseek-llm-7b-chat.jinja | Generic |
| dicta-il-dictalm2.0-instruct.jinja | Generic |
| ehristoforu-Falcon3-8B-Franken-Basestruct.jinja | Hermes 2 Pro |
| fireworks-ai-llama-3-firefunction-v2.jinja | FireFunction v2 |
| godlikehhd-alpaca_data_sampled_ifd_new_5200.jinja | Hermes 2 Pro |
| godlikehhd-alpaca_data_score_max_0.7_2600.jinja | Hermes 2 Pro |
| google-gemma-2-27b-it.jinja | Generic |
| google-gemma-2-2b-it.jinja | Generic |
| google-gemma-2-2b-jpn-it.jinja | Generic |
| google-gemma-7b-it.jinja | Generic |
| huihui-ai-DeepSeek-R1-Distill-Llama-70B-abliterated.jinja | DeepSeek R1 (extract reasoning) |
| huihui-ai-DeepSeek-R1-Distill-Llama-8B-abliterated.jinja | DeepSeek R1 (extract reasoning) |
| huihui-ai-DeepSeek-R1-Distill-Qwen-14B-abliterated-v2.jinja | DeepSeek R1 (extract reasoning) |
| huihui-ai-DeepSeek-R1-Distill-Qwen-32B-abliterated.jinja | DeepSeek R1 (extract reasoning) |
| huihui-ai-DeepSeek-R1-Distill-Qwen-7B-abliterated-v2.jinja | DeepSeek R1 (extract reasoning) |
| huihui-ai-Qwen2.5-14B-Instruct-1M-abliterated.jinja | Hermes 2 Pro |
| ibm-granite-granite-3.1-8b-instruct.jinja | Generic |
| indischepartij-MiniCPM-3B-OpenHermes-2.5-v2.jinja | Generic |
| inflatebot-MN-12B-Mag-Mell-R1.jinja | Generic |
| jinaai-ReaderLM-v2.jinja | Generic |
| kms7530-chemeng_qwen-math-7b_24_1_100_1_nonmath.jinja | Hermes 2 Pro |
| knifeayumu-Cydonia-v1.3-Magnum-v4-22B.jinja | Mistral Nemo |
| langgptai-qwen1.5-7b-chat-sa-v0.1.jinja | Generic |
| lightblue-DeepSeek-R1-Distill-Qwen-7B-Japanese.jinja | DeepSeek R1 (extract reasoning) |
| mattshumer-Reflection-Llama-3.1-70B.jinja | Generic |
| meetkai-functionary-medium-v3.1.jinja | Functionary v3.1 Llama 3.1 |
| meetkai-functionary-medium-v3.2.jinja | Functionary v3.2 |
| meta-llama-Llama-2-7b-chat-hf.jinja | Generic |
| meta-llama-Llama-3.1-8B-Instruct.jinja | Llama 3.x |
| meta-llama-Llama-3.2-11B-Vision-Instruct.jinja | Llama 3.x |
| meta-llama-Llama-3.2-1B-Instruct.jinja | Llama 3.x |
| meta-llama-Llama-3.2-3B-Instruct.jinja | Llama 3.x |
| meta-llama-Llama-3.3-70B-Instruct.jinja | Llama 3.x |
| meta-llama-Meta-Llama-3-8B-Instruct.jinja | Generic |
| meta-llama-Meta-Llama-3.1-8B-Instruct.jinja | Llama 3.x |
| microsoft-Phi-3-medium-4k-instruct.jinja | Generic |
| microsoft-Phi-3-mini-4k-instruct.jinja | Generic |
| microsoft-Phi-3-small-8k-instruct.jinja | Generic |
| microsoft-Phi-3.5-mini-instruct.jinja | Generic |
| microsoft-Phi-3.5-vision-instruct.jinja | Generic |
| microsoft-phi-4.jinja | Generic |
| migtissera-Tess-3-Mistral-Nemo-12B.jinja | Generic |
| ministral-Ministral-3b-instruct.jinja | Generic |
| mistralai-Codestral-22B-v0.1.jinja | Generic |
| mistralai-Mistral-7B-Instruct-v0.1.jinja | Generic |
| mistralai-Mistral-7B-Instruct-v0.2.jinja | Generic |
| mistralai-Mistral-7B-Instruct-v0.3.jinja | Mistral Nemo |
| mistralai-Mistral-Large-Instruct-2407.jinja | Mistral Nemo |
| mistralai-Mistral-Large-Instruct-2411.jinja | Generic |
| mistralai-Mistral-Nemo-Instruct-2407.jinja | Mistral Nemo |
| mistralai-Mistral-Small-24B-Instruct-2501.jinja | Generic |
| mistralai-Mixtral-8x7B-Instruct-v0.1.jinja | Generic |
| mkurman-Qwen2.5-14B-DeepSeek-R1-1M.jinja | Hermes 2 Pro |
| mlabonne-AlphaMonarch-7B.jinja | Generic |
| mlx-community-Josiefied-Qwen2.5-0.5B-Instruct-abliterated-v1-float32.jinja | Hermes 2 Pro |
| mlx-community-Qwen2.5-VL-7B-Instruct-8bit.jinja | Hermes 2 Pro |
| mobiuslabsgmbh-DeepSeek-R1-ReDistill-Qwen-1.5B-v1.1.jinja | DeepSeek R1 (extract reasoning) |
| netcat420-MFANNv0.20.jinja | Generic |
| netcat420-MFANNv0.24.jinja | Generic |
| netease-youdao-Confucius-o1-14B.jinja | Hermes 2 Pro |
| nvidia-AceMath-7B-RM.jinja | Hermes 2 Pro |
| nvidia-Eagle2-1B.jinja | Hermes 2 Pro |
| nvidia-Eagle2-9B.jinja | Hermes 2 Pro |
| nvidia-Llama-3.1-Nemotron-70B-Instruct-HF.jinja | Llama 3.x |
| onnx-community-DeepSeek-R1-Distill-Qwen-1.5B-ONNX.jinja | DeepSeek R1 (extract reasoning) |
| open-thoughts-OpenThinker-7B.jinja | Hermes 2 Pro |
| openchat-openchat-3.5-0106.jinja | Generic |
| pankajmathur-orca_mini_v6_8b.jinja | Generic |
| princeton-nlp-Mistral-7B-Base-SFT-RDPO.jinja | Generic |
| princeton-nlp-Mistral-7B-Instruct-DPO.jinja | Generic |
| princeton-nlp-Mistral-7B-Instruct-RDPO.jinja | Generic |
| prithivMLmods-Bellatrix-Tiny-1.5B-R1.jinja | Hermes 2 Pro |
| prithivMLmods-Bellatrix-Tiny-1B-R1.jinja | Llama 3.x |
| prithivMLmods-Bellatrix-Tiny-1B-v3.jinja | Generic |
| prithivMLmods-Bellatrix-Tiny-3B-R1.jinja | Llama 3.x |
| prithivMLmods-Blaze-14B-xElite.jinja | Generic |
| prithivMLmods-Calcium-Opus-14B-Elite2-R1.jinja | Hermes 2 Pro |
| prithivMLmods-Calme-Ties-78B.jinja | Generic |
| prithivMLmods-Calme-Ties2-78B.jinja | Generic |
| prithivMLmods-Calme-Ties3-78B.jinja | Generic |
| prithivMLmods-ChemQwen2-vL.jinja | Generic |
| prithivMLmods-GWQ2b.jinja | Generic |
| prithivMLmods-LatexMind-2B-Codec.jinja | Generic |
| prithivMLmods-Llama-3.2-6B-AlgoCode.jinja | Llama 3.x |
| prithivMLmods-Megatron-Opus-14B-Exp.jinja | Hermes 2 Pro |
| prithivMLmods-Megatron-Opus-14B-Stock.jinja | Hermes 2 Pro |
| prithivMLmods-Megatron-Opus-7B-Exp.jinja | Hermes 2 Pro |
| prithivMLmods-Omni-Reasoner-Merged.jinja | Hermes 2 Pro |
| prithivMLmods-Omni-Reasoner4-Merged.jinja | Hermes 2 Pro |
| prithivMLmods-Primal-Opus-14B-Optimus-v1.jinja | Hermes 2 Pro |
| prithivMLmods-QwQ-Math-IO-500M.jinja | Hermes 2 Pro |
| prithivMLmods-Qwen-7B-Distill-Reasoner.jinja | DeepSeek R1 (extract reasoning) |
| prithivMLmods-Qwen2.5-1.5B-DeepSeek-R1-Instruct.jinja | Hermes 2 Pro |
| prithivMLmods-Qwen2.5-14B-DeepSeek-R1-1M.jinja | Hermes 2 Pro |
| prithivMLmods-Qwen2.5-32B-DeepSeek-R1-Instruct.jinja | Hermes 2 Pro |
| prithivMLmods-Qwen2.5-7B-DeepSeek-R1-1M.jinja | Hermes 2 Pro |
| prithivMLmods-Triangulum-v2-10B.jinja | Hermes 2 Pro |
| qingy2024-Falcon3-2x10B-MoE-Instruct.jinja | Hermes 2 Pro |
| rubenroy-Zurich-14B-GCv2-5m.jinja | Hermes 2 Pro |
| rubenroy-Zurich-7B-GCv2-5m.jinja | Hermes 2 Pro |
| silma-ai-SILMA-Kashif-2B-Instruct-v1.0.jinja | Generic |
| simplescaling-s1-32B.jinja | Hermes 2 Pro |
| sometimesanotion-Lamarck-14B-v0.7.jinja | Hermes 2 Pro |
| sonthenguyen-zephyr-sft-bnb-4bit-DPO-mtbr-180steps.jinja | Generic |
| sthenno-tempesthenno-icy-0130.jinja | Generic |
| sumink-qwft.jinja | Hermes 2 Pro |
| teknium-OpenHermes-2.5-Mistral-7B.jinja | Generic |
| thirdeyeai-elevate360m.jinja | Generic |
| tiiuae-Falcon3-10B-Instruct.jinja | Hermes 2 Pro |
| unsloth-DeepSeek-R1-Distill-Llama-8B-unsloth-bnb-4bit.jinja | DeepSeek R1 (extract reasoning) |
| unsloth-DeepSeek-R1-Distill-Llama-8B.jinja | DeepSeek R1 (extract reasoning) |
| unsloth-DeepSeek-R1.jinja | DeepSeek R1 (extract reasoning) |
| unsloth-Mistral-Small-24B-Instruct-2501-unsloth-bnb-4bit.jinja | Generic |
| upstage-solar-pro-preview-instruct.jinja | Generic |
| whyhow-ai-PatientSeek.jinja | Generic |
| xwen-team-Xwen-72B-Chat.jinja | Hermes 2 Pro |
| xwen-team-Xwen-7B-Chat.jinja | Hermes 2 Pro |

This table can be generated with:

<!-- TODO @ngxson : we should update this, since minja dependency has been removed -->

```bash
./build/bin/test-chat ../minja/build/tests/*.jinja 2>/dev/null
```

</details>

# Usage - need tool-aware Jinja template

First, start a server with any model, but make sure it has a tools-enabled template: you can verify this by inspecting the `chat_template` or `chat_template_tool_use` properties in `http://localhost:8080/props`).

Here are some models known to work (w/ chat template override when needed):

```shell
# Native support:

llama-server --jinja -fa -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M
llama-server --jinja -fa -hf bartowski/Mistral-Nemo-Instruct-2407-GGUF:Q6_K_L
llama-server --jinja -fa -hf bartowski/Llama-3.3-70B-Instruct-GGUF:Q4_K_M
llama-server --jinja -fa -hf ibm-granite/granite-4.1-3b-GGUF:Q4_K_M

# Native support for DeepSeek R1 works best w/ our template override (official template is buggy, although we do work around it)

llama-server --jinja -fa -hf bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF:Q6_K_L \
    --chat-template-file models/templates/llama-cpp-deepseek-r1.jinja

llama-server --jinja -fa -hf bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF:Q4_K_M \
    --chat-template-file models/templates/llama-cpp-deepseek-r1.jinja

# Native support requires the right template for these GGUFs:

llama-server --jinja -fa -hf bartowski/functionary-small-v3.2-GGUF:Q4_K_M
    --chat-template-file models/templates/meetkai-functionary-medium-v3.2.jinja

llama-server --jinja -fa -hf bartowski/Hermes-2-Pro-Llama-3-8B-GGUF:Q4_K_M \
    --chat-template-file models/templates/NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja

llama-server --jinja -fa -hf bartowski/Hermes-3-Llama-3.1-8B-GGUF:Q4_K_M \
    --chat-template-file models/templates/NousResearch-Hermes-3-Llama-3.1-8B-tool_use.jinja

llama-server --jinja -fa -hf bartowski/firefunction-v2-GGUF -hff firefunction-v2-IQ1_M.gguf \
    --chat-template-file models/templates/fireworks-ai-llama-3-firefunction-v2.jinja

llama-server --jinja -fa -hf bartowski/c4ai-command-r7b-12-2024-GGUF:Q6_K_L \
    --chat-template-file models/templates/CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja

# Generic format support
llama-server --jinja -fa -hf bartowski/phi-4-GGUF:Q4_0
llama-server --jinja -fa -hf bartowski/gemma-2-2b-it-GGUF:Q8_0
llama-server --jinja -fa -hf bartowski/c4ai-command-r-v01-GGUF:Q2_K
```

To get the official template from original HuggingFace repos, you can use [scripts/get_chat_template.py](../scripts/get_chat_template.py) (see examples invocations in [models/templates/README.md](../models/templates/README.md))

> [!TIP]
> If there is no official `tool_use` Jinja template, you may want to set `--chat-template chatml` to use a default that works with many models (YMMV!), or write your own (e.g. we provide a custom [llama-cpp-deepseek-r1.jinja](../models/templates/llama-cpp-deepseek-r1.jinja) for DeepSeek R1 distills)

> [!CAUTION]
> Beware of extreme KV quantizations (e.g. `-ctk q4_0`), they can substantially degrade the model's tool calling performance.

Test in CLI (or with any library / software that can use OpenAI-compatible API backends):

```bash
curl http://localhost:8080/v1/chat/completions -d '{
    "model": "gpt-3.5-turbo",
    "tools": [
        {
        "type":"function",
        "function":{
            "name":"python",
            "description":"Runs code in an ipython interpreter and returns the result of the execution after 60 seconds.",
            "parameters":{
            "type":"object",
            "properties":{
                "code":{
                "type":"string",
                "description":"The code to run in the ipython interpreter."
                }
            },
            "required":["code"]
            }
        }
        }
    ],
    "messages": [
        {
        "role": "user",
        "content": "Print a hello world message with python."
        }
    ]
}'


curl http://localhost:8080/v1/chat/completions -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
        {"role": "system", "content": "You are a chatbot that uses tools/functions. Dont overthink things."},
        {"role": "user", "content": "What is the weather in Istanbul?"}
    ],
    "tools": [{
        "type":"function",
        "function":{
            "name":"get_current_weather",
            "description":"Get the current weather in a given location",
            "parameters":{
                "type":"object",
                "properties":{
                    "location":{
                        "type":"string",
                        "description":"The city and country/state, e.g. `San Francisco, CA`, or `Paris, France`"
                    }
                },
                "required":["location"]
            }
        }
    }]
}'
```

<details>
<summary>Show output</summary>

```json
{
"choices": [
    {
    "finish_reason": "tool",
    "index": 0,
    "message": {
        "content": null,
        "tool_calls": [
        {
            "name": "python",
            "arguments": "{\"code\":\" \\nprint(\\\"Hello, World!\\\")\"}"
        }
        ],
        "role": "assistant"
    }
    }
],
"created": 1727287211,
"model": "gpt-3.5-turbo",
"object": "chat.completion",
"usage": {
    "completion_tokens": 16,
    "prompt_tokens": 44,
    "total_tokens": 60
},
"id": "chatcmpl-Htbgh9feMmGM0LEH2hmQvwsCxq3c6Ni8"
}
```

</details>
