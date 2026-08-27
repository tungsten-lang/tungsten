# Lessons from the MLX Qwen3.8-27B MTP challenge

**Date:** 2026-08-18.
**Source:** `Layr-Labs/qwen-3.8-mtp-challenge` @ `32b94cb..036fd9c`
(accepted-submission commits merged into that repo's `main`).
**Continued in:** `mlx-challenge-lessons-2.md` (accepts `036fd9c..0863b06a`,
2026-08-18 → 08-23, board 3.19 → 3.73) and `dflash2-speculation.md` (the
design synthesis for our own block speculation).
**Hardware behind the numbers:** Apple M5 Max, 128 GB. Ours is M3 Max —
treat every microsecond below as a *shape* of result, not a target.

These are other people's measured results on a vendored MLX/Metal fork,
extracted because four of them transfer directly to kernels we already
have. Nothing here has been re-measured on our tree.

The model there: Qwen3.8-27B, affine 4-bit **group-64** (not Q8_0, not
NVFP4 — plain affine nibbles with per-group scale + bias/zero-point),
hidden 5120, compact draft vocab 98,336 rows of 248,320. Speculative
decode with an MTP proposal head, block-verified against the target.

---

## 1. Nibble extraction: whose operand pays the shift

Upstream MLX's `qdot` never shifts the weight. It masks in place —

```c
accum += x[4*i]   * (w[i] & 0x000f)
       + x[4*i+1] * (w[i] & 0x00f0)
       + x[4*i+2] * (w[i] & 0x0f00)
       + x[4*i+3] * (w[i] & 0xf000);
```

— and pays for it on the *activation* side, inside `load_vector`, which
pre-divides `x[1] /= 16`, `x[2] /= 256`, `x[3] /= 4096`. The 4× shift per
nibble quad is folded into three float multiplies per activation quad.
That is a win exactly when one activation vector feeds many weight rows:
you scale `x` once and save shifts on every row.

The challenge's `qmv_fast_crossrow_affine4_g64_wide` inverts the reuse
ratio. It is a **cross-row** kernel: one weight stream serves `NA` input
rows (up to 4) so the other host groups can return without touching
weights. Now the activations are the *many* side. The accepted change
(`DIRECT_NIBBLES`) drops the pre-scale and shifts the weight directly:

```c
partial[r] += a0 * ( packed[r][i]        & 0x000f)
            + a1 * ((packed[r][i] >> 4)  & 0x000f)
            + a2 * ((packed[r][i] >> 8)  & 0x000f)
            + a3 * ((packed[r][i] >> 12) & 0x000f);
```

**The rule:** fold the nibble shift into whichever operand is loaded
*fewer* times. Single-token matvec → fold into the activation (MLX's
default, correct there). Multi-token / cross-row → shift the weight.

**Where this bites us.** `lib/kernels/q4_k/q4_k_matvec.metal` already
shifts directly (`(q >> 8) & 0x0f`, …) — right call for a single-token
matvec only by accident, since it has no activation reuse to exploit.
The NVFP4 decoders (`nvfp4_decode_half*`) do a bit-reinterpret rather
than a multiply, so the trick does not apply as-is; but the reuse-ratio
question is the same one to ask in
`nvfp4_matvec_mlx_scaled_pair/_triplet.metal`, which are our cross-row
kernels. Worth a bakeoff entry.

One caution the accepted diff is careful about: the bias-correction sum
(`sum(x)` over the group, multiplied by the affine zero-point) has to
keep its **original expression tree and dtype**, or greedy argmax flips
on near-ties. They kept `sums[m] += xm[0]+xm[1]+xm[2]+xm[3]` in the
weight dtype rather than letting the float path re-associate it.

---

## 2. The even split is not the fast split — a register cliff at M=8

The same kernel dispatches `M` input rows as groups of `IPG` rows each.
Public cross-row profile from that repo, same kernel, same shapes:

| M (input rows) | split   | time   |
|----------------|---------|--------|
| 7              | 4+3     | 319 us |
| 8              | 4+4     | 437 us |
| 9              | 3+3+3   | 216 us |

**M=9 does more work than M=8 and runs 2× faster.** M=8 is the only hot
width whose even split needs two simultaneous `vec<float,4>` accumulator
sets in every live worker; that tips register allocation over a cliff and
occupancy collapses. The accepted fix is to split 8 as **3+3+2**, not
4+4 — deliberately uneven, deliberately not the "natural" tiling.

**Why this matters to the schedule language.** `docs/schedule-language.md`
proposes `.tile` / `.split` with the schedule choosing widths. This is the
concrete argument that the *autotuner cannot skip even one width* and that
a cost model over "work done" will pick the wrong split. The search space
has non-monotonic holes; `lib/autotune.w` must sweep, not interpolate.
Our own cross-row ladder stops at 3 (`_pair`, `_triplet`) — before ever
reaching the cliff — so we have not seen this yet. We will the moment we
try 4+.

**Exactness note, worth stealing verbatim as a review rule:**
reassigning a row from lane 3 of a four-wide accumulator to lane 0 of a
two-wide one is *bit-exact*, because those lanes carry independent output
rows and are never reduced across each other — the `simd_sum` reduces
along K *within* a row. Vectorizing across independent outputs is
free of reassociation risk; vectorizing across a reduction axis is not.
That distinction is what makes width retuning safe to do without
re-running fidelity gates.

---

## 3. Two-stage readout: coarse shortlist, exact rerank

The largest single matvec in a decode step is the vocabulary projection.
Their accepted draft head splits it in two:

1. Sweep the **whole** compact vocab (98,336 rows) at **affine 2-bit**,
   group-64 — 320 u32/row instead of 640.
2. `argPartition` the coarse logits to a **32-row shortlist**.
3. `take()` those 32 rows out of the *exact* 4-bit head and re-score them.
4. One-simdgroup reduction picks the winner, using the incumbent
   (value, id) total order so ties break identically.

Bytes moved per readout, hidden 5120, bf16 scales+biases:

| pass                    | weights  | scales+biases | total    |
|-------------------------|----------|---------------|----------|
| exact 4-bit, full sweep | 251.7 MB | 31.5 MB       | 283.2 MB |
| 2-bit sweep + 32 rerank | 125.9 MB | 31.5 MB       | 157.4 MB |

**~44% fewer bytes**, and the result is *identical* to the exact head
whenever the true argmax lands in the coarse top-32.

**The architectural point, which is the real lesson:** speculative
decoding manufactures a place where approximation is free. A proposal
head only *proposes*; the target re-scores and the verifier catches every
miss. So a draft path can be arbitrarily lossy — 2-bit, a truncated
vocabulary, a shortlist — and the only cost is acceptance rate, never
correctness. On the *target* path the same trick is a heuristic (nothing
bounds the true argmax into the top-32), so it needs a fallback or a
guarantee; on the draft path it needs neither.

**Where this lands for us.** We already have the compact-vocab half:
`lib/kernels/qwen3_6/mtp_draft_select.metal` restricts the draft
projection to the common prefix plus the control range. We do not have
the coarse/exact split. On our qwen3 shapes `lm_head` is 2048×151936 =
**330 MB/token**, the biggest single read in the model
(`docs/qwen3-moe-shapes.md`), and our measured lm_head matvec is 162 GB/s
against llama.cpp's 311 (`docs/q8-matvec-bakeoff.md`). A Q2 shortlist
pass over the compact draft vocab plus a 32-row Q8 rerank would be the
single largest bandwidth cut available on the MTP draft path, and it
composes with — does not compete with — closing the GB/s gap.

The shortlist reducer is small enough to be worth copying in shape: 32
candidates, one simdgroup, `simd_shuffle_down` ladder from offset 16, NaN
handled explicitly, lowest-id-wins on exact ties.

---

## 4. Precision islands

Same submission, separate idea. Keep a weight matrix quantized, but ship
alongside it a handful of **exact BF16 rows** plus their row indices.
At runtime: quantized matmul as usual, one tiny dense matmul for the
island rows, then scatter the exact values over the quantized result
(`putAlong` on the output axis).

Applied there to the proposal head's Q/K/V projections only. It is a
cheap way to buy back accuracy on the specific output rows quantization
hurts most, without moving the whole tensor up a bit width — the island
weight is a few hundred rows of a 12,288-row projection.

We have no analogue. The natural place is the same one they used: the
MTP head, where a couple of percent of acceptance rate is worth more than
the bandwidth of a few exact rows. Requires knowing *which* rows to
promote, which is an offline calibration step we do not have tooling for
yet.

---

## 5. Draft-depth scheduling: depth is worth more than verify rows

Their scoring anchors at serial = 1.0, so a speculative build that does
not pay for itself scores below a build that simply does not draft. Two
results from that repo's tuning that are worth knowing before we tune
ours:

- **The pool rewards depth.** Raising the per-step cost ratio (the price
  a marginal draft must beat) from 0.18 → 0.32 shortened every draft
  (mean depth 4.35/4.89/5.78/5.33/5.04 → 3.36/4.01/4.53/4.03/4.76) and
  candidate decode time went *up* 0.95% — a clean −3% on score with the
  baseline leg flat. Bracketed on the other side too (0.15 and 0.14 both
  lose). The marginal draft is worth more than the verify row it costs.
- **Buy depth with the cap, not the price.** The price term moves the
  rule on *every* round including hard prompts. A cap gated on *observed*
  perfect acceptance (streak resets to 0 on any reject) cannot touch a
  cold or hard prompt at all — it only shortens the re-qualification ramp
  where the head is already proving itself. Their qualifying streak
  landed at 2 (gate 1 measured −7.1%, gate 0 only tied).

This also names the diagnostic our `mtp_draft_rank.metal` already
computes: accept rate measures P(rank == 0) and nothing else; the
coverage curve past rank 0 is what decides whether tree drafting pays.
Depth tuning and tree drafting are answering the same question from
opposite ends.

---

## What actually transferred (measured 2026-08-18, M5 Max)

Ported and shipped. Full detail in
`lib/models/qwen3_8_27b_mlx/README.md`; headline: **37.96 -> 46.99 tok/s
(+23.8%)** on the 64-token prose fixture, greedy ids byte-identical throughout.

1. **The cross-row wide kernel (§1/§2) — landed, and it was the big one.**
   `nvfp4_matvec_mlx_scaled_wide.metal` gives each SIMD group ROWS output rows
   with the activations loaded once and shared, which is
   `qmv_fast_crossrow_affine4_g64_wide`'s shape. It replaced a quad/quint kernel
   that had one output row per SIMD group and therefore issued 256 bytes of
   activation load per 8 bytes of weight. Measured 1.6-2.6x at widths 4/5 and
   1.05-1.21x at width 3, `err=0` on all ten production shapes.
2. **"Sweep the ladder, expect a hole" (§2) — confirmed, from the other side.**
   MLX found M=9 cheaper than M=8. We found ROWS=4 beats ROWS=2 by 1.21x on
   mlp-down (K=17408) and *loses* at K=5120 (0.91x, 0.76x). Same lesson: the
   fast split is not the natural one, and a work-based cost model picks wrong.
   The shipped rule is r4 when `kdim == FFN`, r2 otherwise.
3. **The exactness rule (§2) — used as the review gate.** Every kernel change
   here is a pure row-regrouping, so acceptance must not move. It didn't: it is
   byte-identical across all nine A/B runs, which is what caught that the
   comparison was measuring only kernel speed.

Not yet worth it here, with the reason:

4. **Two-stage coarse/exact readout (§3) — correct but too small.** The draft
   head is 252 MB of a 3.05 ms head step; halving it saves ~0.25 ms on a 42 ms
   round, ~0.6%. It becomes worth building only if the head step is attacked as
   a whole.
5. **Depth 3-4 (§5) — the kernel objection is gone, the economics still say no.**
   With `verify(W) = 29 + 3W` ms and a 3.05 ms head step, depth 2 is the optimum
   (22.1 ms/token vs 22.6 at depth 1 and 23.4 at depth 3) because a head step
   costs as much as a verify row while buying a decaying probability. Even a
   free head step caps this at ~52 tok/s. Deeper needs higher acceptance, not
   faster verification.

## The methodological lesson that mattered most

The MLX board's fixture-band finding (a saturated fixture cannot discriminate
any schedule change) applies to the **baseline you are chasing**, not just to
your own harness. This document's model README carried a 61-68 tok/s Ollama
target for months. That number was measured through Ollama's chat template: the
model was writing an assistant *reply*, which is far more predictable prose, and
Ollama's own log reports `acceptance=0.79 max_draft=4` there. Re-run with
`"raw": true` on the identical 64-token prefix, Ollama emits the byte-identical
continuation, its controller backs off to depth 1, and it measures 44.99 tok/s
against our 46.99.

Two hypotheses were killed by measurement rather than argument, which is the
habit worth keeping:

- Feeding the MTP head the pre-final-norm hidden (the mlx-swift-lm reference is
  explicit that post-norm "would double-normalize") changed acceptance by
  *exactly zero, byte-for-byte* — because `RMSNorm(c*v) == RMSNorm(v)`, so the
  head's own norm cancels the backbone norm's scaling.
- The 3.05 ms head step is not GPU->CPU sync latency. Removing the readback
  moved it to 2.72 ms. It is real work in dispatches too small to saturate.

## Remaining gap to the ranked board

Against the best runner using this model's *stock* MTP head, tungsten now leads.
Against the `qwen3.8-27b-mtp-v1` crown (~2.95x its serial leg) tungsten is at
1.55x, and the analysis above says the difference is per-position acceptance,
not kernels or depth. That board makes the head itself editable
(`mtp-head.manifest.json`, declared and digest-verified), and its winners
substitute trained or re-quantized heads. That is the lever, and it is not one a
kernel port can reach.

## Transfer list, in order of expected payoff

1. **Coarse/exact two-stage draft readout** (§3) — biggest byte cut, and
   free on the draft path. Needs a Q2 pack of the compact draft vocab and
   an `argPartition`-equivalent; the rerank kernel is ~40 lines.
2. **Widen the cross-row ladder past 3, sweeping every width** (§2) —
   `nvfp4_matvec_mlx_scaled_pair/_triplet` are M=2 and M=3. Add 4..9 as
   autotune entrypoints *and expect a hole*, probably at M=4 or M=8 given
   our 4-rows-per-simdgroup layout. Do not let a cost model prune it.
3. **Nibble-shift side selection in cross-row kernels** (§1) — a bakeoff
   entry, not a rewrite.
4. **Precision islands** (§4) — blocked on offline row-selection tooling.
5. **Depth-policy shape** (§5) — reference for when the MTP path is
   actually being tuned for throughput.
