# DFlash2 drafter + width-n verify port — measured, 2026-08-26

**Status:** built and correctness-checked in `scripts/bench/qwen38_mlx.w`
(uncommitted). Timing table at the end is filled from load-gated runs only;
every number here was produced on this box today.

Plan: `~/.claude/plans/make-a-plan-for-lovely-feigenbaum.md` (DFlash2 first,
GEMM prefill second). Reference runtime: `~/src/dflash` (z-lab, MLX) in
`~/src/dflash-venv` (mlx 0.32.2, mlx-lm 0.31.3 — current PyPI); drafter
`z-lab/Qwen3.8-27B-DFlash2` @ 50307d4c (5 layers, **1.92B params, 3.85 GB
bf16** — the plan's "~1B" was wrong by 2x).

## 1. What DFlash2 actually is (from the source, not the blog)

Per round: block = `[anchor, MASK x (n-1)]` at positions `p .. p+n-1`, context
= five target taps (residual stream after layers 5/19/33/47/61, pre-final-norm)
of every committed position `< p`, concatenated to 25600 and projected by
`fc` + `hidden_norm`. Five sliding-attention qwen3 layers (hidden 5120, 32/8
heads, hd 128, full RoPE base 1e7), each wrapped in **two-tap grouped dynamic
causal convs** (`kernel_projection` 5120->1280 = 2 sets x 2 taps x 320 groups
of 16; `base_kernel` [2][2][5120]) around attention and MLP; the block attends
bidirectionally to itself and causally (window 2048) to the context K/V cache
(one row per committed token, appended at ingestion — never rolled back).
Target `lm_head` on rows 1..n-1, then the **selector**: top-16 per row,
`score_k = logit_k + <pred_cb[prev] * hp[row], succ_cb[cand_k]>` (rank 256),
argmax, walk. Verify = target on the n rows; accept the matching prefix; commit
`accepted + 1`; the next context rows are the verify's own taps for the
committed rows. dflash-mlx (davidtai) caps the block at 5 and uses a sink+window
draft cache; z-lab uses 8 and a rotating 2047 cache. Nothing else is hidden.

## 2. Gate 0 — tap precision (PASS)

Same drafter, same greedy trajectory (tungsten's), taps from tungsten's NVFP4
engine vs from the MLX 4-bit target:

| fixture | tungsten taps tok/cycle | MLX taps tok/cycle | tap cos mean / min |
|---|---|---|---|
| raw prose 64/256 (119 cycles) | 2.160 | 2.160 | 0.969 / 0.554 |
| chat-thinking 198/256 (79 cycles) | 3.241 | 3.200 | 0.930 / 0.429 |

Taps are not OOD. Regime matters far more than precision: raw prose is a hard
fixture (first-draft hit 0.6, half the cycles accept 0 drafts); the reference's
free-run 5.02 tok/cycle on the chat fixture was **prompt quoting** (its
thinking copied the passage verbatim) — 3.2 is the honest chat number.

## 3. What was built

| piece | file | check |
|---|---|---|
| tap dump (serial run -> `[pos][5][5120]` f32 + ids) | `qwen38_mlx.w` `concurrent ... tapdump <prefix> [ids.json]` | prompt ids == HF tokenizer; serial ids == mtp2 ids |
| runtime-width verify `forward_multi(n<=8)`, tape-replay rollback | `kernels/qwen3_6/decode_multi.metal`, `ARGV[7]=multi` | ids + acceptance byte-identical to triplet/quad paths (31/64, 10/32; 31/67) |
| wide-GEMV rungs widths 1..8, split-hoist `wides_b6/b8` | `nvfp4_matvec_mlx_scaled_wide.metal` | exact (same per-row expression) |
| f32 simdgroup-matrix NVFP4 GEMM, global scale, M tiles 8..64 | `nvfp4/nvfp4_gemm_f32.metal`, rung `g` | max abs diff 1.7e-5 vs GEMV; ids identical to the exact path on mtp2 64/64 AND dflash2 chat 256/256 (0 argmax flips so far) |
| DFlash2 drafter kernels (bf16 wide matvec, dyn conv, hd128 block attn, top-16, selector walk) | `kernels/qwen3_6/dflash2_draft.metal` | probe vs reference on same taps: ctx proj cos 1.000, final hidden cos >= 0.998, top-16 overlap 12-15/16 |
| mode `dflash2` (b<k>[q] block spec, rung, prompt-ids file, `probe:`) | `qwen38_mlx.w` | lossless: ids == serial trajectory on raw 64 and chat 256; chat 175/552 drafts, 81 rounds, 3.16 tok/round (predicted 3.24); raw 39/160, 2.67 tok/round |
| NVFP4 drafter conversion (global-scaled e4m3, MLX nibble layout), 3.85 GB -> 1.27 GB | `~/src/dflash-gate0/quantize_dflash2.py` -> `~/.cache/tungsten/dflash2-nvfp4`, block spec `b8q` | encoder round-trip checked against the kernel decode; acceptance raw 2.56 tok/round (bf16 2.67), chat 3.28 (bf16 3.16) — within noise |
| GEMM prefill arm (64-row chunks, last-row logits via serial path) | `ARGV[6]=gemm-prefill` | mtp2 64/64 ids and acceptance identical to serial prefill |

Rollback is tape replay (the verify writes only its final recurrent state;
`gated_delta_multi` re-runs `accepted+1` tokens from the intact ping-pong
input, bit-identical to what the verify held), instead of 7 x 3 MB interior
snapshots per layer (~1 GB/round at width 8).

## 4. The number that decides it: exact verify width ladder

`mtp3 8 r2 mmap profile 64 auto row-scan-multi`, 40 reps, alone, cool:

| width | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| serial/pair/triplet/quad | 33 | 36 | 41 | 48 | | | | |
| exact multi (auto rungs) | 36 | 39 | 44 | 55 | 67 | 112 | 133 | 105 |

The scalar-FMA cross-row GEMV is ALU-bound past width 4: eight rows x 30 G
weights of FMAs is ~60 ms at peak by itself. An exact width-8 verify is ~2.9x
serial, so at 2.2-3.2 tokens/round DFlash2 cannot beat the MTP head (47 tok/s
on raw prose) on the exact path. Only a matrix-unit GEMM changes this; the
simdgroup-matrix f32 GEMM (rung `g`) is that arm — see the timing table.
Within-run ratios are trustworthy; sequential runs on a hot or loaded box are
not (width 4 read 55, then 72 ms hot, then 1225 ms with an LLVM build running).

## 5. Timing (load-gated, `TUNGSTEN_PERF_MAX_LOAD=4`)

_filled in below when the gated runs complete_
