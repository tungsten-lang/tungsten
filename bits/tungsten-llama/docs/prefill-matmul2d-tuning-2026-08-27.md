# Qwen3.8-27B prefill matmul2d (M5 Neural Accelerators) tuning — 2026-08-27

**Box:** Apple M5 Max, 128 GB, macOS 26.6. All NVFP4 (A=fp16, W4/gs16), err=0
(c0/mid/last vs analytic K on all-ones data). Isolated GEMM timings; ratios are
the trustworthy signal (see cold-weight note). Harnesses:
`scripts/bench/qwen38_prefill_gemm_sweep.w`, `qwen38_m4_tile_bench.w`,
`qwen38_m4_coldweight.w`, template `scripts/bench/kernels/nvfp4_matmul_m4_param.metal.in`.

## Headline

The prefill GEMM should run on the **M5 GPU Neural Accelerators** (Metal-4
`mpp::tensor_ops::matmul2d`), NOT the current simdgroup path — and the shipped
matmul2d tile is badly under-sized.

1. **matmul2d beats the current simdgroup GEMM** (`nvfp4_gemm_f32`) on every
   Qwen3.8 projection at prefill batch: crossover at **M≈48–64**, then
   1.65–1.86× by M≈1024 (plateaus by ~2048). Below M=32 it loses (0.5–0.9×) —
   so it must stay OUT of decode/verify (M≤8).
2. **Tile geometry is a 2.4× lever** the current kernel leaves on the floor.
3. The win is **compute-bound, so it survives cold DRAM weights** (real prefill).

## #1 Tile grid (M=1024, cold-equivalent). Winner: 128 × 64 × 128, 4 simdgroups

| tile (MT×NT×KT, SG) | ffn_gate_up | ffn_down | attn_qkv |
|---|---|---|---|
| 64×32×64 sg4 (**current**) | 19,490 | 17,264 | 18,800 |
| 128×64×64 sg4 | 42,826 | 39,946 | 39,252 |
| **128×64×128 sg4** | **46,030** | **43,401** | **42,341** |
| speedup vs current | **2.36×** | **2.51×** | **2.25×** |

Monotonic: bigger M_TILE/N_TILE/K_TILE win; **4 simdgroups beats 8** everywhere
(8 ≈ half throughput). Past the winner it regresses: MT=256, NT=128, and KT=256
all fall off (occupancy / 32 KB threadgroup-mem pressure). ffn_down (tall K)
improves the MOST — K_TILE=128 absorbs the long reduction.

## #2 Cold weights (rotate 8 distinct weight sets → DRAM, not L2)

| shape | tile | warm ms | cold ms | eff. weight BW |
|---|---|---|---|---|
| ffn_gate_up | 128×64×128 | 4.08 | 3.99 | 11 GB/s |
| ffn_down | 128×64×128 | 4.87 | 4.23 | 11 GB/s |
| attn_qkv | 128×64×128 | 2.07 | 2.00 | 10 GB/s |

cold ≈ warm; effective weight BW ~10–11 GB/s vs 614 GB/s peak ⇒ the matrix
units, not memory, are the limiter. Prefill at M≥512 has ~500 FLOP/byte
arithmetic intensity → compute-bound → the 2.4× tile win is real, not a cache
artifact.

## #3 Split-K for ffn_down — NOT warranted

K_TILE=128 is already optimal for ffn_down (K=17408): K_TILE=256 regresses
(37,555 vs 43,178), M_TILE=64 regresses (38,049 vs 43,455). ~640 threadgroups
launched ⇒ occupancy ample. The tile tuning already captured the tall-K benefit;
a split-K kernel would add complexity for no gain.

## Landed (verified)

- `nvfp4_matmul_m4.metal` rewritten: templated impl, **two entry points** —
  `nvfp4_matmul_m4` (128×64×128) for long prefill and `nvfp4_matmul_m4_m64`
  (64×64×128) for the `MULTI_MAX=64` chunk (avoids the 128-tile over-compute at
  M≤64) — both `execution_simdgroups<4>`, 128 threads, tgmem 16384. Old tile
  kept in git history (`git show c6dadba6:bits/tungsten-llama/lib/kernels/nvfp4_matmul_m4.metal`).
- **`global_scale` (buffer 5)** added, matching `nvfp4_gemm_f32`'s
  `y = gscale·Σ A·decode(W)`. Verified: gs=3 → 3K, gs=2.5 → 2.5K, err=0; m64
  variant err=0 at M=64.
- Callers `nvfp4_m4_smoke.w` / `qwen38_prefill_gemm_sweep.w` updated
  (argtable size 6, gscale slot, 128-tile dispatch). Smoke err_max=0.

## Remaining: the forward_multi wiring is a DUAL COMMAND-STREAM integration

Not a kernel swap. `enqueue_scaled_multi` (the FFN gate/up + down projections in
`forward_multi`) dispatches `nvfp4_gemm_f32` on the model's **legacy**
`MTLCommandQueue` inside one `metal_batch_begin_concurrent` batch. matmul2d runs
on the separate **MTL4** stream (`m4_queue`). So wiring requires:
1. **f32→f16 activation conversion** per projection (`nvfp4/f32_to_f16.metal`
   already exists) — matmul2d needs an fp16 MTLTensor input; activations are f32.
2. **Cross-stream sync**: commit the legacy batch up to the projection, run
   matmul2d on `m4_queue`, sync (shared event or commit+wait), resume — which
   breaks the concurrent batch and needs pipelining to stay a net win.
3. Swap gate/up (non-residual) + down (residual — needs a `_residual` matmul2d
   entry, or matmul2d→tmp then the existing add kernel) across all 64 layers.
4. Parity gate: 5-token "capital of France" → token 11751 (" Paris"), then a
   longer prompt.

`bench_lightning_long_prefill.w` demonstrates the dual-stream pattern, but on a
**f16-dequantized** weight path (`f16_matmul_m4` + upfront dequant) that the 27B
can't afford in memory — so the nvfp4-in-tile kernel landed here is the right
one; only the interleaving pattern transfers. Expected prefill-GEMM speedup once
wired ≈ (1.7× kernel) × (2.4× tile) in the compute-bound regime; end-to-end
prefill/TTFT gain is less (attention/RoPE/norm are not GEMMs).

### Numerical parity de-risk (PASSED)

matmul2d(f16 acts) vs `nvfp4_gemm_f32`(f32 acts) on the real gate shape
(K=5120, random NVFP4 weights + random f32 acts, m=64): **per-row argmax match
64/64**, max abs error 0.002 on mean |y| 1.47 (~0.1%, below nvfp4 quant noise;
the large max_rel is a divide-by-≈0 artifact). So the f16-activation drop
preserves argmax — the wiring is parity-safe at the projection level, and the
model already tolerates `nvfp4_gemm_f32` ("gate on ids").

### The blocker: forward_multi is ONE concurrent command buffer

`forward_multi` opens `metal_batch_begin_concurrent(queue)` once and commits
ONCE at the end (all 64 layers + lm_head in a single command buffer — a
deliberate decode optimization). matmul2d must run on the separate MTL4 stream
with a commit boundary, so inserting it mid-forward means segmenting that single
batch into hundreds of commits — a fundamental restructure of forward_multi's
batching, and it's the SHARED prefill+verify path (breaking it risks decode
parity). `bench_lightning_long_prefill.w` shows the commit-segment pattern IS
viable for prefill (~6 commits/layer), but it is a **dedicated** prefill forward.

**Correct path (a focused build, not a wiring):** add a dedicated
`forward_prefill_m4` for gemm-prefill mode — a commit-segmented, matmul2d-native
prefill forward for the hybrid arch (gated-delta + full-attn), leaving the
parity-clean `forward_multi` untouched. Kernel + numerics are proven; this is
the remaining engineering. Verify with the built-in 5-token → 11751 (" Paris")
gate plus a long prompt.

## LANDED 2026-08-27: matmul2d FFN prefill in the main model path

Wired into `scripts/bench/qwen38_mlx.w`, gated so ONLY gemm-prefill takes the
matmul2d branch (verify/decode byte-identical, single-batch). Implementation:
`enqueue_ffn_multi` branches on `g_m4_ffn` to `ffn_m4`, which commit-segments the
batch around the MTL4 stream — convert xn→f16 + commit, gate/up on `m4_queue`
(`nvfp4_matmul_m4_m64`), silu + convert h→f16 + commit, down on `m4_queue`, then
residual add. `m4_proj` builds the argtable per projection; weights carry their
`.global_scale` (buffer 5). Toggle: `M4_FFN=0` env falls back to
`nvfp4_gemm_f32`.

**Verified:** 5-token "capital of France" → **parity PASS, first token 11751
(" Paris")**, coherent generation. 256-token A/B: **identical ids** (parity),
**prefill 2396 ms (M4) vs 2500 ms (legacy) — ~4% faster**, 106.8 vs 102.4 tok/s.

**Why only ~4% end-to-end** (vs 2.4× kernel in isolation): prefill is dominated
by attention (gated-delta recurrence + full-attn, still on the legacy path),
cold weight streaming, and the commit-segment overhead (~5 GPU round-trips/layer
from the per-dispatch MTL4 commit). The FFN GEMM is only a fraction of prefill,
and matmul2d's win is diluted by those. **To get more:** (1) route the attention
q/k/v/o projections through matmul2d too, (2) cut commits (a batched MTL4
dispatch, or a fused gate+up projection so gate/up is one matmul2d, not two).
