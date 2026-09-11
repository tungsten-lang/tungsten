# CUDA and Metal challenge ports, 2026-09-11

The applicable Qwen3.8-125B/A6B challenge mechanisms are now available in
Tungsten's Flash Next NVFP4 runner. The new paths are opt-in while full-model
parity and throughput remain unmeasured. Kernel speedups below are isolated
Metal measurements, not model tokens/s or leaderboard scores.

## Source pins and scope

- CUDA challenge: [Layr-Labs/cudafast-qwen38-125b-a6b-engine](https://github.com/Layr-Labs/cudafast-qwen38-125b-a6b-engine/tree/f0dd8b67f118e7b2acb55e47505cba7b485085e0),
  `f0dd8b67f118e7b2acb55e47505cba7b485085e0` (26 commits fetched since
  `4b382fd94274911d4e6a5b9999318b7811e4a1bb`). Sources:
  `ds4/ds4_cuda_qwen4exp.cu`, especially the warp router and grouped QSA.
- Metal challenge: [Layr-Labs/mlxfast-qwen38-125b-a6b-engine](https://github.com/Layr-Labs/mlxfast-qwen38-125b-a6b-engine/tree/b22bf811d429f6c49c204011b0154cb15e73ac2d),
  `b22bf811d429f6c49c204011b0154cb15e73ac2d` (14 commits fetched).
  Sources: `Runner/FastModel/TrackFastMoE.swift` (`routeSource`) and
  `Runner/FastModel/TrackFastKernels2.swift` (`injectNormWideSource`).
- Tungsten was fetched and already contained `origin/main`; no merge was
  needed. The existing 125B runner is
  [`scripts/bench/qwen38fn_mlx.w`](../../../scripts/bench/qwen38fn_mlx.w).
  This is separate from the older 27B `qwen38_mlx.w` ports.
- Upstream MIT notices are retained in
  [upstream-cuda-metal-LICENSES.txt](upstream-cuda-metal-LICENSES.txt).

The CUDA challenge uses GGUF Q4_K/Q5_K/Q8_0; the Metal challenge uses affine
quantization. Tungsten's routed weights are NVFP4, its activations are f32,
and its dense backbone starts as bf16. Preserve each representation's
unpacking, scaling, rounding and reduction contracts when transferring ideas.

## Available paths

| Mechanism | Tungsten adaptation | Selection |
|---|---|---|
| One-warp top-10 router | `router_softmax_topk10_warp.metal`: 16 experts per lane, live masks and stable low-index ties. Serial, recorded decode, multi-token and MTP call sites all use the matching 32-thread launch. | `FN_ROUTER_WARP=1`; unset/0 uses the original 512-thread router. |
| CUDA router counterpart | `router_softmax_topk10_warp.cu`: same 512-expert/top-10 data contract, one block of 32 threads per row. Handwritten source with an explicit Git ignore exception. | Reusable kernel and native CUDA regression fixture; no CUDA Flash Next host runner was added. |
| Grouped-query prefill reuse | `qsa_selected_group2.metal`: two query heads in one KV group share selected K/V loads while keeping independent accumulators and the old reduction order. 18,520 bytes of static threadgroup scratch. | `FN_QSA_GROUP2=1` at widths >=64 when QSA is active and both GQA factor and head count are even. `FN_QSA_PAR=0` keeps the old path. Narrow/MTP widths retain the old attention dispatch. |
| Wide normalization with virtual warps | `grouped_rms_norm_warp.metal`: 32/64/128 physical threads reproduce the old 256-thread reduction. The normalization helper supports direct and recorded multi-token paths. | Experimental `FN_NORM_THREADS=32`, `64`, or `128` at widths >=128. Default `256` remains faster on most tested shapes. |

The router intentionally retains Tungsten's **full 512-way softmax before
top-k over probabilities**, followed by serial renormalization of the chosen
10 probabilities. Upstream selects logits first and normalizes selected
logits. Those are algebraically equivalent in ordinary cases but can differ
in floating-point ties and underflow. The port retains the original
stride-halving sum tree and uses `#pragma clang fp reassociate(off)` in the
Metal helper; the first fast-math test exposed a one-bit weight difference
without that restriction. Inputs are finite f32 logits.

Tungsten already has token-parallel GDN convolution, recorded dispatch
programs, multi-row NVFP4 kernels and staged/grouped MoE GEMM. These were
inspected rather than duplicated. CUDA graph code and GGUF integer MMA/dp4a
kernels cannot be dropped into the Metal NVFP4 runner as-is.

## Validation and measurements

Machine: Apple M5 Max, 128 GiB unified memory, macOS 26.6.2 (25G83),
Xcode 26.4.1 (17E202). The following checks passed:

- Standalone Metal gate: **1,350,071,040 output bytes compared exactly**
  with fast math both disabled and enabled. Router widths
  1/2/3/7/8/9/16/32/64/128/1024, six input patterns (including ties,
  near-ties, underflow and large finite logits), plus the single-row entry.
- Normalization: all three thread counts, the same eleven widths,
  dimensions 127/128/640/2560/10240 and the complete output tensors.
- Selected attention: widths 1/7/64/128/1024; visible counts
  0/1/31/32/255/256/257/1024/2048/2051, ragged per-token lengths,
  permuted selections, 24 query heads, GQA 12, head dimension 256.
- The actual Tungsten bridge exercised direct and recorded dispatch,
  including scalar argument binding, all three normalization variants,
  single/multi router entrypoints and grouped selected attention.
- `bin/tungsten-compiler --check scripts/bench/qwen38fn_mlx.w` passed.
- Clang 23.1.0 with official CUDA 13.0 headers compiled the CUDA router
  and its reference fixture to PTX for **sm_100 and sm_121**, and passed
  host syntax checking. This is not an NVCC build, linked CUDA binary,
  NVIDIA execution test or cross-vendor floating-point parity result.

See the adjacent [measurement JSONL](upstream-cuda-metal-2026-09-11.jsonl)
for every timed sample and [manifest](upstream-cuda-metal-2026-09-11.json)
for source hashes and commands. Timings use ABBA twice (four observations
per arm), compare medians, and use warm synthetic data. Router/norm samples
contain 64 launches through width 128 and 8 at width 1024; QSA samples use
one launch. They do not represent the full model's cache or concurrency.

No full-model run was attempted: the configured local cache currently lacks
all 192 routed-expert shards and two backbone-index shards. No weights were
downloaded. The Runpod was stopped at the user's request and its persistent
weights volume was retained.

| Isolated kernel | Tested timed widths | Reference / candidate time |
|---|---|---|
| Router | 1/8/32/128/1024 | **3.47–7.44x** |
| Grouped QSA (256 or 2048 selected positions) | 64/128/1024 | **1.58–1.97x** |
| Norm, 32 threads | 1/8/32/128/1024 | 0.18–0.78x (slower) |
| Norm, 64 threads | 1/8/32/128/1024 | 0.34–0.87x (slower) |
| Norm, 128 threads | 1/8/32/128/1024 | 0.62–1.08x (mixed; 0.92x at width 1024) |

## Reproduce

From the repository root, without model weights:

```sh
bash bits/tungsten-llama/scripts/test_upstream_kernels.sh
BIT_HOME="$PWD/bits" bin/tungsten run bits/tungsten-llama/scripts/test_upstream_dispatch.w
BIT_HOME="$PWD/bits" bin/tungsten-compiler --check scripts/bench/qwen38fn_mlx.w
```

On a compatible, already-running NVIDIA host with CUDA 13:

```sh
CUDA_ARCH=sm_100 bash bits/tungsten-llama/scripts/test_upstream_router_cuda.sh
# GB10 target: CUDA_ARCH=sm_121
```

The CUDA script builds and runs both precise and fast-math variants against
an independent 512-thread reference, including batch-placement invariance.
It has not been executed on an NVIDIA GPU in this porting session.

For later full-model comparison, keep checkpoint, prompts, MTP depth,
quantization, context, cache state and other settings identical. Compare
`FN_ROUTER_WARP=0/1`; compare `FN_QSA_GROUP2=0/1` with QSA active and a
prefill chunk of at least 64. Require matching generated IDs and paired
prefill/decode measurements before changing defaults. Recheck available
memory including buffers/KV/OS and disk before restoring model weights.

## Earlier CUDA sweep learnings retained

The B200 sweep screened 134 MMA and 32 dp4a configurations, all correct in
their declared synthetic cases. Winners depended on width and gate/up
versus down projection. The initial 36-cell quantizer/row/depth model grid
showed only +0.33% prefill and effectively unchanged decode across matched
pairs. Later integrated candidates on `32eb7add` were slower in single
comparisons affected by run-order drift. None earned promotion or a
submission. These layouts and the packed quantizer are not NVFP4 wins.

The practical transfers are shape-specific selection, complete-output
correctness, matched serial/MTP row invariance, paired timings and a
full-model promotion gate. The slower normalization variants stay explicit
experiments; an isolated-kernel winner does not set a production default.
