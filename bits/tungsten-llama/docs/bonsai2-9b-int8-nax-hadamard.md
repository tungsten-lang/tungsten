# Bonsai2-9B / Qwen3.5 / DFlash 2 Port: Integer NAX, Signed Block-Hadamard, Exact Verify Head, Fused GDN Verify, and Speculative Pipeline Overlap

**Date:** 2026-10-17
**Source:** `Layr-Labs/mlxfast-bonsai2-9b-engine` (`origin/main` @ `7430b66`, `cf2933d`, PR #268) and `Layr-Labs/cudafast-bonsai2-9b-engine` (`cf34c34`)

This document records the architecture, kernel inventory, compiler/core-library additions, and scheduling patterns ported into `~/tungsten` and `bits/tungsten-llama`.

---

## 1. Integer M5 Neural Accelerator (`int8 × u2/u4/i8 -> int32`) for Both Prefill and 2..16-Row Verify

Previously, `bits/tungsten-llama/lib/kernels/na/` only used the M5 Neural Accelerator (`mpp::tensor_ops::matmul2d`) for `half × half -> float` prefill (`M >= 64`). In `Layr-Labs/mlxfast-bonsai2-9b-engine`, the M5 Neural Accelerator runs **`int8_t × int8_t -> int32_t`** at full throughput for **both** 64-row prefill tiles **and** 2..16-row speculative verification (`bonsai_q8_verify_matmul_nax_fast1..3`, `bonsai_q8_verify_matmul_nax_fast_wide1..3`) as well as DFlash 2's 16-row block-diffusion drafter (`df2_i8_matmul1..3`, `df2_w4g{64,128}_1..6`).

### Key Algebraic Decomposition

For group-quantized weights $W_{n, k} = s_{g, n} \cdot u_{n, k} + b_{g, n}$ with $u_{n, k} \in \{0, \dots, 2^B - 1\}$ and per-row, per-group symmetrically quantized activations $x_{m, k} \approx a_{m, g} \cdot q_{m, k}$ with $q_{m, k} \in [-127, 127]$:

1. Center the unsigned $B$-bit weight code around zero so it fits in signed `int8_t` ($c_{n, k} = u_{n, k} - 2^{B-1}$):
   - **2-bit ($B=2$, offset $2$):** byte-table lookup `lut2[byte]` unpacks 4× 2-bit codes directly into `char4` in `{-2, -1, 0, 1}` (or direct unsigned 2-bit mask `(v >> (2*q)) & 0x03030303u` folded with `rsb`).
   - **4-bit ($B=4$, offset $8$):** bitwise nibble unpack `(((v & 0x0F0F0F0Fu) + 0x78787878u) ^ 0x80808080u)`.
   - **8-bit ($B=8$, offset $128$):** single XOR `wv ^ 0x80808080u`.
2. Precompute the row-group activation sum $S_{m, g} = \sum_{k \in g} x_{m, k}$ (or `rsb = sum(xq) - 2 * round(sum(x)/ascale)`) inside the boundary quantizer kernel (`signed_block_hadamard_*_4096_q8` or `df2_act_q8g*`).
3. Run `mpp::tensor_ops::matmul2d` with `execution_simdgroup` over `int8_t` activation slice $A$ and threadgroup-staged `int8_t` weight tile $B_t$ (`16 × 32 × 128` for verify/draft, `32 × 32 × 128` × 4 simdgroups = `64 × 64` for prefill) accumulating into `int32_t` cooperative tensor `cT`.
4. Dequantize once per group in the epilogue:
   $$\text{acc}_{m, n} \mathrel{+}= (s_{g, n} \cdot a_{m, g}) \cdot \text{float}(cT_{m, n}) + (b_{g, n} + 2^{B-1} s_{g, n}) \cdot S_{m, g}$$

### Ported Files
- **Metal Kernels:** `bits/tungsten-llama/lib/kernels/na/int8_hadamard_matmul_na.metal`
  - `bonsai_q8_prompt_matmul_nax_sg1..3`: 64×64 prompt tile (4 simdgroups, each running `32×32×128` `int8` NAX matmul2d) for 1, 2, or 3 sibling projections sharing the quantized activation.
  - `bonsai_q8_verify_matmul_nax_fast1..3`: 16×32 verify tile (4 simdgroups splitting K by 4, each running `16×32×128` `int8` NAX matmul2d) for 2..16-row verification.
  - `bonsai_q8_verify_matmul_nax_fast_wide1..3` (`cf2933d` + PR #268): replaces 8 strided 4-byte `uint32_t` weight loads per lane with **two 16-byte `uint4` loads** (`wr = lane >> 1`, `wq = 4 * (lane & 1)` for rows `wr` and `wr + 16`), rotates threadgroup stores by `rot = wr & 3` (`qq = (q + rot) & 3`) to eliminate threadgroup bank conflicts, and prefetches weight `uint4` pairs **two K-groups ahead** in registers (`wv0/wv1` + `nv0/nv1`).
- **Core `Tensor` (`~/tungsten/core/tensor.w`):**
  - Added `Tensor.storage_i32`, `Tensor.storage_i8`, `Tensor.storage_u8`, and `i8`/`u8`/`i32` support in `Tensor.cpu_zeros`, `Tensor#read_flat`, and `Tensor#write_flat`.
  - Upgraded `build_tensor_m4_kernel`, `tensor_m4_state`, and `Tensor#linear(weight)` to dispatch **`Tensor.i8` (`int8_t × int8_t -> int32_t`)** directly to the M5 Neural Accelerator (`mpp::tensor_ops::matmul2d`) with CPU parity fallback.
- **Compiler (`~/tungsten/compiler/lib/metal_emitter/msl.w`):**
  - Added packed vector types (`:i8x4`/`:char4`, `:u8x4`/`:uchar4`, `:i16x4`/`:short4`, `:u16x4`/`:ushort4`, `:f16x2`/`:half2`, `:bf16x2`/`:bfloat2`), `gpu.shared_f16`/`gpu.shared_i8`/`gpu.shared_u8` threadgroup allocations, and 2-argument SIMD-group shuffle intrinsics (`simd_shuffle_xor`, `simd_shuffle`, `simd_shuffle_down`, `simd_shuffle_up`, `simd_broadcast`) plus `fma`, `popcount`, `clz`, `ctz`.

---

## 2. Signed Block-Hadamard Transform (4096-Wide 3-Pass Radix-16 Butterfly) Fused with Boundary Ops

2-bit and 4-bit Hadamard-quantized checkpoints (Bonsai 2 9B, Qwen3.5 Hadamard) store weights in the rotated basis $\tilde{W} = W H D$ (where $H$ is the normalized $4096 \times 4096$ Sylvester Walsh-Hadamard matrix and $D = \text{diag}(\text{signs})$). Instead of materializing intermediate FP32 buffers between norms/activations, Hadamard rotation, and `int8` quantization, all three steps are fused into a single 256-thread (`8` simdgroups × `16` elements/thread = `4096`) threadgroup kernel using **3 radix-16 butterfly passes** (2 threadgroup memory stages + 1 final register-butterfly + `simd_shuffle_xor(8)` stage):

- **Metal Kernels (`bits/tungsten-llama/lib/kernels/na/int8_hadamard_matmul_na.metal`):**
  - `signed_block_hadamard_4096_f32`: standalone forward (`scale * (H @ (signs * x))`) and inverse (`signs * (scale * (H @ x))`) 4096-wide transform.
  - `signed_block_hadamard_4096_q8`: fused forward Hadamard + group-128 `int8` quantizer (`codes`, `ascale`, `rsb`).
  - `signed_block_hadamard_swiglu_4096_q8`: fused `silu(gate) * up` + forward Hadamard + group-128 `int8` quantizer.
  - `signed_block_hadamard_residual_norm_4096_q8`: fused `residual + x` + `RMSNorm` + forward Hadamard + group-128 `int8` quantizer (also writes the un-rotated FP32 residual sum and optionally the FP32 normed row for dense FP32 GDN `[b | a]` gate projections).
  - `signed_block_hadamard_embed_norm_4096_q8`: Layer-0 fused 2-bit embedding table lookup/dequant + inverse Hadamard + `RMSNorm` + forward Hadamard + group-128 `int8` quantizer.
  - `signed_block_hadamard_gated_norm_4096_q8`: GDN output boundary fusing per-head 128-wide `RMSNorm(y)` + `silu(z)` gate + forward Hadamard + group-128 `int8` quantizer.
  - `signed_block_hadamard_attention_gate_4096_q8`: Full-attention output boundary reading head-major `[1, 16, L, 256]` SDPA output directly without transpose, multiplying by `sigmoid(gate)` from the 512-wide `q_proj`, and fusing forward Hadamard + group-128 `int8` quantizer.
- **Core `LinAlg` & `Tensor` (`~/tungsten/core/linalg.w`, `~/tungsten/core/tensor.w`, `~/tungsten/spec/core/linalg_fwht_spec.w`):**
  - Added `LinAlg.power_of_two?(n)`, `LinAlg.fwht(v, normalize)`, `LinAlg.fwht_rows(a, normalize)`, `LinAlg.block_fwht_rows(a, block_size, signs, inverse)`, `LinAlg.hadamard_matrix(n, normalize)`, and `Tensor#fwht(block_size, signs, inverse)`.

---

## 3. Full DFlash 2 (`DF2Fast`) 16-Row Block-Diffusion Drafter Suite (incl. `7430b66` Upgrades)

Upgraded `bits/tungsten-llama/lib/kernels/qwen3_6/dflash2_draft.metal` to `DRAFT_MAX_TOK = 16` with the complete `DF2Fast` M5 Neural Accelerator kernel suite:

1. **8-bit g32 NAX Path:** `df2_act_q8`, `df2_act_q8_swiglu`, `df2_i8_matmul1..3` (`16×32×32` `int8` NAX matmul2d with 8-way K-split).
2. **4-bit g64/g128 Re-Quantized NAX Path (`7430b66`):**
   - At load time, pinned drafter linears are re-quantized in-memory to 4-bit affine codes (`group = 64` or `128`) by grid-searching the clip shrink factor $c \in \{1.0, 0.95, 0.9, 0.85, 0.8, 0.75\}$ minimizing $L_2$ reconstruction error per group.
   - `df2_act_q8g{64,128}{,_swiglu,_hm}`: 16 contiguous columns per thread (`c0 = tid * 16`), single-pass register buffering (`nv[16]`), `simd_shuffle_xor(1, 2, 4)` for `amax`, and `simd_shuffle` for exact left-to-right `seq_sum`, supporting fused `SwiGLU` and direct head-major `[1, 32, R, 128]` reads for `o_proj`.
   - `df2_act_q8g{64,128}_conv0`: fuses `DFlash2GroupedDynamicCausalConv(part: 0, residual: nil)` directly into the 16-columns/thread SIMD-shuffle `int8` activation quantizer before `q/k/v` and `gate/up` projections.
   - `df2_w4g{64,128}_{1..6}`: `16×32×G` `int8` NAX matmul2d for **1..6** sibling/cross-layer drafter projections (`7430b66`), allowing the drafter to project `[kProj, vProj]` across **3 drafter layers at once** (`kv012` and `kv345`) from the single quantized context tensor `cCodes`.
3. **Fused Norm + W4 Int8 Group Quantization (`7430b66`):**
   - `df2_rms_q8g{64,128}`: fuses `RMSNorm` (`D = 4096`) + `W4Codes` int8 group quantization into a single launch (`hiddenNorm(fcOut)` -> `(context, cCodes)` and `layers[0].inputLayerNorm(h)` -> `(normed, normedCodes)`).
   - `df2_dyn_conv_rms_q8g{64,128}{,_tail}`: fuses `dynConv(part: 1, residual)` + next sublayer's `RMSNorm` + `W4Codes` int8 group quantization (with `qStart = logitsStart` slicing on the final layer so `finalCodes` feeds `sel.hiddenProjection` and the LM head directly).
4. **Fused Norm + YarnRoPE + Head-Major Transpose:**
   - `df2_qkv_norm_rope`, `df2_ctx_kv_norm_rope`, and `df2_qkv_all_norm_rope`: single-launch `qNorm` + `kNorm` + `YarnRoPE` (`mscale` + `freqs`) + `[1, S, H, 128] -> [1, H, S, 128]` transpose for both the 16-token block and the newly committed context tokens.
5. **96K Prefix Vocabulary Head (`DF2Vocab.rows = 98304`, `7430b66`):**
   - Slices the drafter's `HadamardQuantizedLinear` LM head to the first `98,304` (`96 * 1024`) token rows (covering all Latin, code, punctuation, and byte-level BPE merges while keeping the full 248,320 vocabulary for target verification), cutting drafter LM-head compute and bandwidth by **60.4%**.
6. **Single-Barrier Register Top-16 + Ping-Pong Codebook Selector (`7430b66`):**
   - `df2_topk16_mb8`: each simdgroup finds its own 16 winners directly from `tv[0]`/`ti[0]` in registers via `simd_max`/`simd_min`, writes `wv[128]`/`wi[128]`, and after a **single** `threadgroup_barrier`, `sg == 0` merges the 128 candidates in registers.
   - `df2_selector_mb8`: uses double-buffered `threadgroup float ev[2][16]` (`buf = p & 1`) and warp-wide `simd_max`/`simd_min` across lanes `0..15` so every simdgroup knows the winning `pr = tc[p][best]` with only **one** `threadgroup_barrier` per position.

---

## 4. Certified Two-Stage Int8 NAX Screen + Exact FP32 Shortlist Rescore (`ExactVerifyHead`)

During 16-row target verification over a 248,320-token vocabulary (`[16, 4096] × [248320, 4096]^T`), computing the full exact FP32/BF16 LM head is bandwidth-bound. `bits/tungsten-llama/lib/kernels/na/exact_verify_head_na.metal` implements a **mathematically certified, zero-flip** two-stage argmax:

1. **`hadamard_xhead_bounds`**: Rotates and quantizes the $R \le 16$ final hidden rows (`xq`), and computes each row's exact quantization rounding error vector $e_{m, k} = x_{m, k} - a_{m, g} q_{m, k}$ along with its per-group positive/negative error sums:
   $$e^+_{m, g} = \sum_{k \in g} \max(e_{m, k}, 0), \qquad e^-_{m, g} = \sum_{k \in g} \min(e_{m, k}, 0)$$
   Using Cauchy-Schwarz and the precomputed per-column weight group norms, this yields a **rigorous upper bound on the discrepancy** $|\hat{y}_{m, n} - y^{\text{exact}}_{m, n}| \le \Delta_{m, n}$ between the Int8 NAX dot product $\hat{y}_{m, n}$ and the exact FP32 logit $y^{\text{exact}}_{m, n}$.
2. **`hadamard_xhead_select_scan`**: Runs `16×32×128` `int8` NAX matmul2d across all 248,320 vocabulary columns (7,760 tiles of 32 columns). Each tile tracks the highest lower bound $\hat{y}_{m, n} - \Delta_{m, n}$ and retains only candidate columns whose upper bound $\hat{y}_{m, n} + \Delta_{m, n}$ can still beat the tile/global lower bound (up to 32 shortlist candidates per 128-column block).
3. **`hadamard_xhead_select_rescore`**: Evaluates the **exact FP32** dot product (`#pragma clang fp contract(off)`) only on the surviving shortlist columns whose upper bound exceeds the global lower bound `maxLower[m]`.
4. **`hadamard_xhead_select_merge`**: Reduces the exact rescored shortlist across blocks to emit the bit-identical greedy token ID per verify row (`out[m]`).

---

## 5. Single-Launch 16-Row Fused GatedDeltaNet Verify & In-Kernel Lazy Rollback

Ported to `bits/tungsten-llama/lib/kernels/qwen3_6/gdn_fused.metal` (and `qwen35_verify_qk_norm_rope` in `bits/tungsten-llama/lib/kernels/qwen3_6/decode_multi.metal`):

- **`qwen35_gdn_verify_fused`**: Replaces 5 separate per-layer launches (`concat` + `conv1d` + `silu` + `qk_rms_norm` + `gated_delta_recurrence`) during 2..16-row target verification with **one** kernel launch (`grid = (1, 4, Hv)`, `threadgroup = (128, 1, 1)`):
  - Immediately issues `float4` loads of the recurrent state `[Dv, Dk]` into registers (`R = 16` Dk elements × `DVPL = 2` Dv rows per lane) so DRAM latency overlaps the conv/norm stages.
  - Computes the 4-tap depthwise causal convolution + stable `SiLU` for its key head's `q` and `k` channels and its 32 `v` channels into threadgroup memory (`qk_raw`, `v_tile`), while writing `conv_in`, `conv_out`, and the detached full-acceptance `conv_tail`.
  - Runs 128-wide per-head `RMSNorm` with $128^{-1/2}$ scaling on `qk_raw` in threadgroup memory.
  - Steps the register-resident `[128, 128]` recurrent state across all $T \le 16$ verify tokens using 3-step butterfly reductions (`simd_shuffle_xor` with masks `4, 2, 1` across the 8 lanes that partition `Dk = 128`).
- **`qwen35_gdn_register_simd_state_only`**: Fast rollback replay kernel for partial speculative acceptance (`accepted + 1 < T`), advancing only the recurrent state from `k`, `v`, `a`, `b` without reading `q` or writing `y`.
- **`qwen35_gdn_verify_lazy_rollback`** (ported from `cudafast-bonsai2-9b-engine` `gated_delta_net_kernel.cuh`): Eliminates both eager per-token 2 MB state snapshots (32 MB per layer for 16 verify tokens) and separate post-verify host-launched state-repair kernels. Each threadgroup `(n, tgid.y)` records its compact per-token inputs `(k[128], v[64], g, beta)` (194 floats/token) during verify round $N$, and on entry to verify round $N+1$, lazily replays the `replay_tokens = 1 + accepted` steps in registers from `state_io`, commits the new base state to `state_io`, and immediately executes the new verify window in the same kernel launch.
- **`qwen35_gdn_dense_ba_rows`**: Fuses the dense FP32 `in_proj_b` and `in_proj_a` projections across $2 \dots 16$ verify rows into a single launch.
- **`qwen35_verify_qk_norm_rope`**: Single-launch full-attention `q_norm` + `k_norm` + non-traditional partial `RoPE` (using `simd_shuffle_xor(y[0][j], HALF_ROT / 4)`) + head-major `[1, H, L, 256]` transpose, reading `q` in-place from the `512`-wide `[q | gate]` projection.

---

## 6. Speculative Pipeline Overlap & OS Workgroup Interval Hints

In `Layr-Labs/mlxfast-bonsai2-9b-engine` (`7430b66`, `EngineLoopV2+MTPFinalize.swift`, `DFlash2Draft.swift`, `BenchmarkCLI.swift`), four host/GPU pipeline techniques eliminate inter-round stalls:

1. **Incremental Context Absorption (`absorbContext` / `absorbPendingContext`):**
   - For long prompts ($> 448$ tokens), as soon as the last prompt chunk enters the target tower, the previously committed prompt chunks' tapped hidden states (`[B, C, 5 * hidden]`) are projected through the drafter's `fc` + `hidden_norm` and each drafter layer's `k_proj`/`v_proj` + `df2_ctx_kv_norm_rope` (`absorbContext`), populating the drafter's KV cache before the first `propose()` call begins.
2. **Pre-Staged Drafter Async Evaluation Before Target Rollback (`prestageBlock`, `7430b66`):**
   - In `EngineLoopV2+MTPFinalize.swift`, as soon as the verify round's `accepted` count is read on the host, the engine **first** calls `stateful.finalizeRound` + `block.prestageBlock(anchor: kept[confirmed - 1], depth: k)` (which builds the next round's DFlash 2 proposal graph and dispatches it via `asyncEval(...)`) **before** executing the target's 24-layer GDN state repair (`commitCapturedWindow`) and KV cache rollback (`sequence.rollback(rejected)`). Because the drafter only depends on `committedTargetHidden` from round $N$ (and not the repaired GDN recurrent state), the GPU pipelines the next round's drafter proposal and round $N$'s GDN state repair back-to-back while the CPU finishes scheduler bookkeeping.
3. **Combined QKV + Context KV Norm/RoPE (`df2_qkv_all_norm_rope` + `updateWithCombined`):**
   - Instead of launching separate `df2_ctx_kv_norm_rope` (for the $C = \text{accepted} + 1$ newly committed target taps) and `df2_qkv_norm_rope` (for the $L = 16$ draft block positions), `df2_qkv_all_norm_rope` norms, rotates, and transposes `q` (`[1, 32, L, 128]`), `ck | bk` (`[1, 8, C + L, 128]`), and `cv | bv` (`[1, 8, C + L, 128]`) in a **single launch**, writing directly into the sliding KV cache slice `kBuf[end ..< end + C + L]` and advancing `end += C`.
4. **macOS Real-Time GPU/CPU Workgroup Interval (`CBv2EngineWorkInterval`):**
   - Elevates the inference decode thread to `PTHREAD_QOS_CLASS_USER_INTERACTIVE` and joins an `os_workgroup_interval_t` (`OS_WORKGROUP_INTERVAL_TYPE_DEFAULT`) with 8 ms frame-paced `os_workgroup_interval_start` / `os_workgroup_interval_update` ticks so the macOS scheduler keeps the CPU submission thread and M5 Max AGX command processor at peak P-state across the entire speculative decode loop.

---

## 7. CUDA Architecture & Kernel Learnings (`cudafast-bonsai2-9b-engine` -> `bits/tungsten-llama` & `~/tungsten` CUDA Dialect)

In addition to Metal, `~/tungsten` emits CUDA C (`.cu`) and `bits/tungsten-llama` now includes the CUDA kernel headers ported from `Layr-Labs/cudafast-bonsai2-9b-engine` (`cf34c34`, DGX Spark `sm_121` / Hopper `sm_90+` / Ampere `sm_80+`):

### A. Tungsten Compiler CUDA Dialect Emitter (`~/tungsten/compiler/lib/metal_emitter/dialects.w`, `msl.w`, `spec/compiler/gpu_cuda_emit_spec.w`)
- **Cross-Dialect Warp Shuffles & Reductions:** `@gpu fn` kernels using `simd_shuffle_xor(x, mask)`, `simd_shuffle(x, lane)`, `simd_shuffle_down(x, delta)`, `simd_shuffle_up(x, delta)`, `simd_broadcast(x, lane)`, `simd_broadcast_first(x)`, `simd_sum(x)`, `simd_max(x)`, and `simd_min(x)` now compile directly to CUDA C (`__shfl_xor_sync(0xffffffffu, ...)`, `__shfl_sync`, `__shfl_down_sync`, `__shfl_up_sync`, and inline `__w_cuda_simd_{sum,max,min}` butterfly helpers) in addition to Metal!
- **Hardware Integer Dot & Byte-Permute Intrinsics (`dp4a`, `byte_perm`):**
  - `dp4a(a, b, c)` lowers to native `__dp4a(a, b, c)` (`dp4a.s32.s32`) in CUDA and `as_type<char4>` 4-way dot-accumulate in Metal.
  - `byte_perm(x, y, s)` lowers to native `__byte_perm(x, y, s)` (`prmt.b32` 4-byte hardware LUT instruction) in CUDA.
- **Packed Low-Precision & Vector Types in CUDA:** Extended `cuda_type_name` with `char4`, `uchar4`, `short4`, `ushort4`, `half2 -> __half2` (`#include <cuda_fp16.h>`), and `bfloat2 -> __nv_bfloat162`, plus `__shared__ char` (`gpu.shared_i8`) and implicit `return` emission for `@gpu fn` device helpers in CUDA.

### B. Fused Boundary + 4096-Wide FWHT + `block_q8_1_mmq` D4 Quantizers & Pre-PDL Constant Preload (`bits/tungsten-llama/lib/kernels/na/bonsai_hadamard_mmq_cuda.cuh`)
- **Programmatic Dependent Launch (PDL) + Pre-Wait Constant Preload (`bonsai_fwht_quantize_mmq_d4_add_rms_cuda`):**
  - Uses Hopper/Blackwell (`__CUDA_ARCH__ >= 900`) `cudaGridDependencySynchronize()` (`griddepcontrol.wait`) and `cudaTriggerProgrammaticLaunchCompletion()` (`griddepcontrol.launch_dependents`).
  - Crucially, static model weights (`w_rms` and Hadamard `signs`) are loaded into registers **before** `bonsai_cuda_pdl_wait()`, hiding global constant memory latency behind the tail of the upstream producer kernel.
- **Single-CTA 4096-Wide FWHT + D4 `block_q8_1_mmq` Quantizer:**
  - Executes 2 butterfly stages in 4 thread registers, 5 warp stages via `__shfl_xor_sync`, a bank-conflict-free `s_data[32][132]` shared-memory transpose, and 5 cross-warp butterfly stages, immediately packing 144-byte `block_q8_1_mmq` blocks (`half2(d, d * sum_q)` + `int8_t qs[128]`).

### C. Shared-Memory-Free Direct-to-Register `mma.sync.aligned.m16n8k32.s8` (`J=16` Verify) & IEEE-754 `0x4B400000` Magic Bias (`bits/tungsten-llama/lib/kernels/na/bonsai_hadamard_mmq_cuda.cuh`)
- **Zero-Shared-Memory, Zero-Barrier `PQ2_0` Verify (`bonsai_mul_mat_pq2_j16_cuda`):**
  - Each warp (`lane = 4*g + c`) reads its own 16-bit slice of 2-bit weights directly from global memory and unpacks 8× 2-bit codes into two `s8x4` Tensor Core `A` fragment registers in **4 hardware `__byte_perm` instructions** (`__byte_perm(0x020100FFu, 0x020100FFu, q16)` and `q16 >> 2`, interleaved via `0x5140u` / `0x7362u`).
- **IEEE-754 Magic Bias (`0x4B400000 = 12582912.0f`) Inside `mma.sync` Accumulator:**
  - Seeds the `mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32` accumulator `C[0..3]` with `0x4B400000` (`1.5 * 2^23`) before the instruction. The Tensor Core integer adder deposits `idot` (`|idot| <= 8128 < 2^22`) directly into the FP32 mantissa bits, so `__int_as_float(C[l]) - 12582912.0f` recovers `(float)idot` with **zero `I2F` conversion instructions**.
- **Lossless Base-3 `PTQ1_0` Ternary Register Unpacker (`bonsai_ptq1_unpack_5trits_x4`):**
  - Any 2-bit weight block whose codes lie in `{0, 1, 2}` (`{-d, 0, +d}`) is losslessly repacked at load time into 28-byte `PTQ1_0` (5 trits/byte, saving 17.6% weight bandwidth) and decoded in registers without integer division using $H_k(b) = \lfloor b \cdot 3^k / 256 \rfloor$ via `__byte_perm(lo * 3^k, hi * 3^k, 0x7351u)` and $t_k = H_{k+1} - 3 H_k$.
- **Hopper/Blackwell `L2::evict_first` Policy (`bonsai_cuda_evict_first_policy`):**
  - Uses `createpolicy.fractional.L2::evict_first.b64` on streaming weight loads so quantized weight pages do not displace L2-resident activation blocks.

### D. Certified Warp-Minimum Threshold Top-K, Single-Warp 32-Way Merge, and Streaming-Cache Lazy GDN (`bits/tungsten-llama/lib/kernels/qwen3_6/dflash2_gdn_cuda.cuh`)
- **64-Bit Order-Preserving Key Pack & Certified Warp-Minimum Threshold (`dflash2_topk_partial_certified_cuda`):**
  - Packs `(float v, int col)` into a single `uint64_t` (`(uint64_t(twiddle(v)) << 32) | ~uint32_t(col)`) so value-descending order with lowest-index tie-breaking is a single unsigned `>` comparison.
  - Across 16 warps (512 threads), computes each warp's maximum $M_w$ and takes their minimum $T = \min_{w=0}^{15} M_w$. Because the 16 warp maxima are distinct keys, at least 16 keys in the block are $\ge T$; for $k \le 16$, all keys $< T$ are provably pruned in one pass before Warp 0 selects the top $k$ in registers.
- **Single-Warp Zero-Barrier 32-Way Merge (`dflash2_topk_merge_warp_cuda`):**
  - Merges up to 32 chunk top-$k$ lists in **one single warp (32 threads) with zero shared memory and zero `__syncthreads()` barriers**, advancing only the winning lane's register cursor `++pos` on each step.
- **Lazy-Rollback GatedDeltaNet with Streaming L2 Cache Operators (`gated_delta_net_lazy_rollback_cuda`):**
  - Uses `__ldcs` / `__stcs` (`ld.global.cs` / `st.global.cs`) on recurrent state and rollback records so state traffic does not evict L2-resident activations, overlaps warp butterfly reductions across all 4 state columns (`gdn_warp_reduce_sum_n`), and rolls back rejected speculative tokens in-register before advancing the recurrent state.


