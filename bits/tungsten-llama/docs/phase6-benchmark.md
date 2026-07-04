# Phase 6 — tungsten-llama vs llama.cpp Metal benchmark

**Model:** `qwen3:30b-a3b-q8_0` (Q8_0 MoE, 48 blocks, 128 experts top-8,
hidden 2048, head_dim 128, GQA 32q/4kv).
**Hardware:** Apple M3 Max, 64 GB unified memory, macOS 25.3.0.
**Date:** 2026-04-23.

## Headline numbers

| Test                          | Tungsten        | llama.cpp Metal | Ratio          |
| ----------------------------- | --------------- | --------------- | -------------- |
| Decode (warm, short ctx, greedy)   | **43.5 tok/s**  | 70.7 tok/s      | **1.6× slower** |
| Decode (warm, short ctx, sampled¹) | ~32 tok/s       | —               | —              |
| Prefill (cold avg, 5 tokens)       | 1.9 tok/s       | 1315 tok/s @ 2k | ~690× slower   |
| 2k-context decode                  | not measured²   | 54.4 tok/s      | —              |

### Update history (2026-04-23)

| Stage | Decode tok/s | Notes |
|---|---|---|
| Phase 5 hand-tuned (Apr 23 morning) | 2.7 | initial steady-state measurement |
| + concurrent dispatch + moe_combine_8 (5ee75b8) | 21.7 | 8× speedup. The 8 expert chains run in parallel inside one MTLDispatchTypeConcurrent encoder, and the 8-dispatch wadd phase is replaced by a single fused 8-input combine kernel that removes the per-wadd serialization |
| + pre-router concurrent (05dae77) | 23.3 | small extra. Q/K/V projections, per-head norms, RoPE, KV writes all run concurrent within their phases (each phase 2-3 parallelizable dispatches separated from the next by a barrier) |
| + GPU router top-K (router_topk_8) | 27.8 | killed the per-layer CPU sync. The 128-element top-K + softmax + per-slot weight unpack now runs on the GPU as a single lane-0 dispatch in the same concurrent batch, so the host commits the layer once instead of twice (no readback between router matvec and expert dispatch) |
| + single command buffer per token | 41.7 | the entire 48-layer forward pass + lm_head + GPU argmax encodes into ONE concurrent batch with one commit per token (was 49 commits). Without per-layer host syncs holding things up, the GPU stays busy. Plus a wave of small fusions: combine_residual (combine+residual), per_head_norm_rope (norm+rope for Q+K), per_head_norm_rope_to_cache (K side writes K cache directly), f16_matvec_to_cache (V proj writes V cache directly), q8_matvec_coop_residual (o_proj+residual), silu_mul_8 (8 silu dispatches → 1), v3 expert kernels with 4-rows-per-TG. |
| + v4 multi-row TG for lm_head, device const annotations, fastMath, max-threads attribute | **43.5** | lm_head matvec uses 32 output rows per threadgroup (1024 threads, 32 simdgroups) with the activation cached in threadgroup memory. Cuts lm_head TG launches from 151936 to 4748 and reduces redundant activation reads. `device const` on weight buffers gives the compiler/cache hint of read-only. `[[max_total_threads_per_threadgroup(N)]]` lets the compiler tune register allocation per kernel. fastMath enables aggressive FMA contraction and approximated reciprocals. |

¹ Sampled = `TEMPERATURE = 0.7, TOP_K = 40`. The CPU-side
softmax + top-K + cumulative walk costs ~150 ms per sample on top
of the forward pass.

² Requires `MAX_POS = 2048` and ~13 minutes of wall time to fill
the cache at our current per-token latency. Skipped for now.

## What's behind the gap

The 2.5× decode gap is what's left after concurrent-dispatch +
fused-combine + GPU top-K. The remaining slack lives roughly in:
- Expert Q8 matvecs that still go through scalar i32-packed reads
  rather than Apple's `simdgroup_load_matrix_sync` matrix ops, which
  llama.cpp uses heavily.
- Small per-token Metal overhead (encoder setup, command-buffer
  commit, CPU→GPU sync at the lm_head argmax read-back).
- Pre-router phase still serial — the ~7 distinct kernels in the
  attention + projection chain transition between pipelines per
  layer, eating ~30 ms/token at 48 layers.

The 1400× prefill gap is structural, not implementation. Our prefill
loop is sequential — one token at a time, same forward pass as decode.
llama.cpp processes the prompt as one batched dispatch that parallelizes
across all prompt positions (Q/K/V projections become matrix-matrix
instead of matrix-vector, attention is one big kernel covering all
positions × all positions). Adding a batched prefill path to Tungsten
is its own substantial slice — not impossible, but it's not what got
built in Phase 5 (which targeted single-token decode).

## What we shipped

- 18 Q8 matvec schedule variants enumerated by the autotuner; the
  fastest validated variant runs at 334 GB/s effective on the
  qwen3 lm_head shape (151936×2048).
- Greedy + top-K + temperature sampling.
- Verifies argmax correctness against the qwen3 reference behavior
  ("Paris" for "The capital of France is").
- Coherent multi-token continuations on real prompts:
  > "The capital of France is Paris. The capital of the United
  > Kingdom is London. The capital of the United States is
  > Washington, D.C. The capital of Brazil is Brasília. The
  > capital of Japan is Tokyo. The capital of India is New Delhi.
  > The capital of Australia"
- Pure Tungsten — no FFI to llama.cpp/ggml, no hidden C
  linear-algebra, every `@gpu fn` is a `.w` source compiled through
  our own metal_emitter.

## What's left to close the gap

Updated 2026-04-23 afternoon after concurrent dispatch landed:

1. **Batched prefill kernel** — process N prompt positions in one
   forward pass. Q/K/V projections → matmul (N × hidden), attention →
   N × N+pos scores, etc. Closes most of the ~870× prefill gap. Still
   the biggest unlanded item.
2. **`simdgroup_load_matrix_sync` / matrix-multiply intrinsics** —
   would help **prefill** (Q is a matrix [N, hidden]) but not decode
   (Q is a single vector). Layered on top of #1.
3. **Flash attention** as one fused kernel — saves 2 of the 3 attention
   dispatches per layer × 48 layers ≈ 15 ms/token at our current
   per-dispatch cost. Marginal vs the ~430 ms total per token.
4. **Mmap zero-copy weights** — `newBufferWithBytesNoCopy:` would
   need a kernel rewrite to read interleaved Q8 layout (since the
   on-disk layout has a 2-byte scale per 32-byte block of quants
   that doesn't align to i32 boundaries for our current scale+quants
   split). Saves ~1-3 s of startup; doesn't help per-token.

Honest revision: the document earlier called #2 (simdgroup_matrix)
"likely the biggest single decode-side win." That was wrong on
re-examination — those intrinsics are designed for matrix-matrix
operations (matmul), and decode is matrix-vector (matvec). The
intrinsics don't accelerate matvec, they accelerate matmul.

The autotuner harness from Phase 4 stays useful for #2 once a
batched prefill path exists — the search grammar just gains a knob
for `:simdgroup_matrix` parallelization on the prefill kernels.
