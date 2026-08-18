# Qwen3.8-27B decode work — handoff

**Box:** Apple M5 Max, 128 GB. **Model:** `qwen3.8:27b-mlx` (Ollama NVFP4 blobs, mmap).
**Bench:** `bin/tungsten run scripts/bench/qwen38_mlx.w <mode> <n_gen> <schedule> mmap <flag> <prompt_tokens> <variant> [diag]`

Everything below is measured on this box, alternating A/B, and every change is
**parity-clean**: byte-identical greedy token ids, with draft acceptance used as
the null check (a pure kernel change must not move it).

## Headline

| | before | after |
|---|---|---|
| literary fixture, 64-tok prompt | 37.96 tok/s | **49.7** |
| expository fixture (`prose-tech`) | — | **55.1** (`mtp2`), +4.6% with gated `mtp3` |
| serial (non-speculative) | 30.30 | unchanged |

Matched against Ollama's MLX runner (`"raw": true`, identical 64-token prefix,
byte-identical continuation): tungsten **wins literary 49.7 vs 45.0**, trails
**expository 55.1 vs 61.2**.

## Wins that came from the MLX challenge repo

1. **Cross-row wide QMV** — `lib/kernels/nvfp4/nvfp4_matvec_mlx_scaled_wide.metal`.
   MLX's `qmv_fast_crossrow_affine4_g64_wide` shape: ROWS output rows per SIMD
   group with the activations loaded ONCE and shared. Replaced a quad/quint
   kernel that gave each SIMD group one output row and therefore issued 256 bytes
   of activation load per 8 bytes of weight. **1.6–2.6x at widths 4/5**, err=0 on
   all ten production shapes. +2% end-to-end at width 3.
2. **Sweep the row ladder, never extrapolate it** (MLX's M=9-cheaper-than-M=8
   note). `r4` beats `r2` on mlp-down (K=17408) and loses at K=5120 — shipped
   split is `r4` when `kdim == FFN`, `r2` otherwise. +1%, 3/3.
3. **Streak-gated draft depth** (`segmentedStreakGate`). Go deeper only after 2
   consecutive fully-accepted rounds; any reject resets. See `mtp3` below.

## Wins found here, NOT in the upstream set

4. **Tiled draft selector** — `lib/kernels/qwen3_6/mtp_draft_select_fast.metal`.
   **Biggest single win.** `mtp_compact_draft_select` scanned 98,330 logits with
   ONE 32-thread simdgroup, *twice* (once for the max, once for the index). This
   repo had already fixed exactly that pattern for the full-vocabulary argmax
   (1,648 us -> 3.92 us with 1024-logit tiles) and never applied it to the draft
   path. Two tiled stages, tie-break preserved exactly (control ids >= 248,044
   all exceed prefix ids < 98,304, so lowest-id order == logical index order).
   **Head step 3.14 -> 1.95 ms (-38%)**, +3.2% end-to-end, 3/3.
5. **Half-footprint width-4 QMV** — `nvfp4_wideh_*` in the wide kernel file.
   8 K-values per lane instead of 16, splitting an NVFP4 group across two lanes
   (free — `simd_sum` already reduces across lanes, and both halves share the
   group scale). Cuts hoisted activations from 64 to 32 registers, back under the
   occupancy cliff. **Row-4 marginal +9 ms -> +5 ms.** This is a different
   mechanism from upstream's grid-split (IPG) answer to width scaling.
6. **MTP-2 was already faster than MTP-1 and wasn't the default** (+15%). The
   docs recorded depth-1 as fastest; that verdict was set on a saturated fixture.
7. **`mtp3`: depth-3 with a streak gate.** `lib/kernels/qwen3_6/decode_quad.metal`
   (nine kernels; conv and gated-delta carry a third interior recurrent-state
   snapshot so rollback can pick any accepted prefix), `rollback_quad_states`,
   four-way accept walk. Ungated it wins expository (+3.1%, 4/4) and *loses*
   literary (-13%) because that chain decays too fast. Gated: **+4.6% expository,
   parity on literary**, ids byte-identical.
8. **Folded the hidden-copy into the head's command buffer** — `hidden-copy` went
   from 0.17 ms x2-3 per round to `0 ms/0`. Neutral-to-slightly-positive; kept.

## Measurement corrections (these mattered more than any kernel)

- **The Ollama target was a chat-template artifact.** 61–68 tok/s in the old
  README was Ollama writing an assistant *reply* (`acceptance=0.79 max_draft=4`).
  Always send `"raw": true` and the exact token prefix; verify
  `prompt_eval_count` matches and both emit the same continuation. Read its stats
  from `~/.ollama/logs/server.log` (`source=speculate_stats.go`).
- **The 512-token fixture was tiling** the passage 5x (the model said so in its
  own output). Prose is now long enough and the runner **warns** instead of
  silently tiling. A fake 0.796 acceptance nearly justified a whole program.

## Negative results — do not repeat

| tried | result |
|---|---|
| Pre-norm hidden for the MTP head (reference says post-norm double-normalizes) | **zero change, byte-for-byte** — `RMSNorm(c*v)==RMSNorm(v)` cancels it |
| Draft step is GPU->CPU sync latency | no — removing the readback: 3.10 -> 2.72 ms |
| Resource-scoped barriers (`memoryBarrierWithResources`) | median round identical in 4/4 |
| Nibble decode is the ALU bottleneck | no-decode ablation within 0.3–4% |
| Longer context raises acceptance | it does not (64/256/512 = 0.484/0.370/0.550) |
| simdgroup-matrix GEMM, v1 and v2 | exact (err 1e-6) and **3–10x slower**; occupancy, not the MMA units — M<=8 has too little arithmetic intensity, and staging beats the register-resident GEMV |

## Cost model (use this before building anything)

```
row ladder (in-situ, ARGV[7]="row-scan"):  33 / 37 / 39 / 44 ms  at widths 1-4
head step (MTP forward):                   1.95 ms
round(d) = verify(d+1) + 1.95*d
E[tokens] caps at 1/(1-p);  measured p = 0.50 (literary) .. 0.64 (expository)
```
Rows 2–3 are nearly free (bandwidth-bound, weights streamed once); row 4 is where
it turns compute/occupancy-bound. At p=0.64, depth 2 gives 55 tok/s and that is
*exactly* what is measured — the shipped config sits on its own optimum.

## What is left

- **Head step is the binding constraint** (1.95 ms; ~1.2 ms is irreducible
  bandwidth over ~540 MB: draft projection 252 MB + MTP layer 227 MB). Halving
  the draft projection with a 2-bit coarse sweep + exact top-32 rerank (the MLX
  board's declared-head trick) is worth ~0.3 ms.
- **Acceptance** is the other lever and it needs a better/trained MTP head — a
  weights lever, not an inference-engine one. The ranked board makes the head
  substitutable precisely because that is where its remaining margin lives.

## Discipline (learned the hard way here)

- Always `scripts/bench/perf_lock.sh`. It serializes tungsten runs but **cannot**
  serialize Docker VMs, browsers, or other agents' builds — check `uptime` and
  `macmon`. Dispatch encoding is host-bound, so CPU load halves tok/s with
  acceptance unchanged. GPU >65 C also degrades; alternate A/B **order** (ABBA),
  because whichever arm runs second gets the hotter slot.
- Trust the **median round** and paired win counts, not absolute tok/s.
- Acceptance is deterministic and reproduces byte-for-byte — if it moved, your
  "pure kernel change" wasn't.
