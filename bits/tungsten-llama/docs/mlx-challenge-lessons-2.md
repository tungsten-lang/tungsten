# Lessons from the MLX Qwen3.8-27B MTP challenge, part 2

**Date:** 2026-08-25.
**Source:** `Layr-Labs/qwen-3.8-mtp-challenge` @ `036fd9c..0863b06a` — the 17
accepted-submission commits merged 2026-08-18 → 2026-08-23, read through
their public `yukon submission-note`s plus the tip's `Qwen35.swift` /
`Qwen36MTPBlockSession.swift`. Part 1 (`mlx-challenge-lessons.md`) covers
`32b94cb..036fd9c`.
**Hardware behind the numbers:** the ranked Apple M5 Max, 128 GB, 512-token
seed + 512-token decode, score = median over 8 hidden prompts of
serial-s/token ÷ candidate-s/token. Serial on that box is ~26 tok/s; the
current crown (3.729×) is therefore ~97 tok/s of exact-greedy decode.

Nothing here has been re-measured on our tree. Every number is somebody
else's ranked receipt or an isolated microbench they published.

---

## 0. The arc, so the sizes are in proportion

| date | tip score | what moved it |
|---|---:|---|
| 08-14 | 0.994 | stock tree, fixed depth 2, empty head cache every round |
| 08-15 | 1.25 → 1.38 | fused FA QKV; fused K=1 verify; **exact hierarchical top-2 verifier readout** (1.3525); argmax dedup (1.376) |
| 08-15 | ~2.33 | **committed MTP-head history** (K=1 accept 0.64 → 0.9+), one blocking sync per round, per-row GDN checkpoints (no repair forward), streak-laddered depth, asyncEval ladder |
| 08-16 | 2.51 | **SDPA width wall cracked**: widths 6–8 verify bit-exact by splitting attention into ≤5-row calls → depth cap 8 |
| 08-16 | 2.90 → 2.93 | cost-model draft policy (h=0.18), compiled/packed GDN, MLP fuse at S≤9/16, **4-bit head** (849 → 239 MB) |
| 08-17 | 2.95 → 3.08 | DIRECT_NIBBLES QMV at M=6/9 (+2.06%), warm the normed-verify shape (+0.16%), **precision-island head** (3.037), islands + M=8 nibbles (3.077), **M=4 IPG 4→2** (2.4× cheaper width) |
| 08-18 | 3.146 → 3.191 | **affine-2 coarse readout + top-32 + affine-4 exact rerank** declared head (+1.43%) |
| 08-18 | 3.196 → 3.243 | M=8 4+4 (+0.23%); **fused residual+RMSNorm boundary chain** (+1.42%); two-dispatch top-32 replacing `argPartition`; wired residency + 512 MiB command buffers (3.243, ours) |
| 08-19/20 | 3.25 → 3.31 | `setenv` overwrite fix for the 512 MiB profile; **flat cap 7, streak gate removed** (3.3096 on a fast tree) |
| 08-21 | 3.328 → 3.350 | **E87 two-level cluster index** over the draft vocab (12,292 leaves × 8 rows, 2-bit centroids); island dead-work elimination; one-dispatch selected-row affine-4 rerank |
| 08-22 | 3.35 → 3.52 | **E120 candidate-owned wide verify QMV + activation chunk-sum table (+13.24%)**; E121 32-value/lane cluster kernels (+2.62%); E87 select in two dispatches (+0.72%) |
| 08-22/23 | 3.525 → **3.729** | **tight launch geometry** — only `ceil(M/IPG)` x-groups (3.525 → 3.682, +4.4%); probe fraction 0.25 → 0.15 (3.691); M=2 through the same launcher (3.704, +1.29%); skip an unused JIT (3.729) |

Three things carried most of the 0.994 → 3.73: head context (the head was
drafting blind), verify-width kernels (the target forward at M=3..9 was
paying for register cliffs, empty threadgroups and recomputed sums), and the
draft readout (a 98k-row lm_head sweep per proposed token became a 15k-row
cluster probe). Everything else is ≤1.5% each and mostly launch count.

---

## 1. Verify-side kernels: the target QMV at widths 3..9

The verify forward at width M is one wide cross-row affine-4/group-64 QMV
per projection — 257 calls per decode round on that tower. Almost every
late-board gain is this one kernel family.

### 1.1 Own the dispatch first (E120, +13.24% with §1.3)

MLX's launcher was replicated as a Swift-dispatched custom kernel with
*identical* arithmetic and *identical* geometry (`grid (M*32, N/8*2, 1)`,
threadgroup `(32,2,1)`, same nibble decode, same `simd_sum`) and proven
bit-exact before anything was built on it. Only then did the two real wins
become possible, because both are launch-side: the library's dispatch
chooses the grid and the buffer list, and you cannot fix either from inside
the kernel body. One caution they hit: making K and N template constants
unrolled the K loop and the compiler produced wrong answers at NA=5, K=5120
(174,072 of 174,080 outputs off) — K, N stay runtime values.

**Rule:** if a library kernel is on the hot path and the fix is in the
*launch* (grid volume, extra bound buffers, width plan), replicate it
bit-exact under your own dispatch and prove equality first. Tungsten owns
every dispatch already; this is the one structural advantage we have over
the MLX trees and we should not give it back by wrapping a library.

### 1.2 Launch only the threadgroups that can work (+4.4%)

The wide kernel maps x-group `g` to `first_m = g*IPG` and returns before any
read when `first_m >= M`. The library launched `M` x-groups anyway:

| M | IPG | launched | working | no-op |
|--:|--:|--:|--:|--:|
| 3 | 3 | 3 | 1 | 2 |
| 4 | 4 | 4 | 1 | 3 |
| 5 | 5 | 5 | 1 | 4 |
| 6 | 3 | 6 | 2 | 4 |
| 7 | 4 | 7 | 2 | 5 |
| 8 | 4 | 8 | 2 | 6 |
| 9 | 3 | 9 | 3 | 6 |

42 → 12 groups across the width table, and — because every one of those
empty groups is multiplied by `N/8` y-groups — 3.525 → 3.682 on the ranked
median. Then routing M=2 through the same launcher (the library's pair
kernel launched two x-groups, one dead) gave a further +1.29%.

**Rule:** count the working threadgroups, not the natural ones. An
early-returning group is not free when it is one of `N/8` × M of them.
**Audited 2026-08-25 — tungsten is already clean.** Our input batch (2/3/4
tokens) is a compile-time template constant in
`nvfp4_matvec_mlx_scaled_pair/_triplet/_wide` and `decode_pair/triplet/quad`,
not a grid dimension; the grid is only over output rows
(`ceil(rows / (2·ROWS))` groups) and the tail guard trims a partial group,
never whole no-op groups. MLX's bug was launching `M` *input-row* groups where
only `ceil(M/IPG)` work — an axis tungsten compiles away. Nothing to fix.

### 1.3 Hoist the activation chunk sums (affine only)

Affine quantization needs `sum(x[group])` per (row, group) for the
zero-point term `scale*dot + sum*bias`. The library recomputed that sum
inside every output-row block; E120 computes it once per activation tensor
into a table indexed `(k_block, lane, m)` — 10,240 bytes at K=5120, M≤8 —
and the wide kernel reads it. The table is then produced *for free* by the
fused RMSNorm kernel's epilogue (the norm just wrote those bytes) and handed
to the consumer through a weak-keyed sidecar so a table can never be applied
to the wrong tensor. Measured net per matvec on an M4 Pro:

| shape | M=3 | M=4 | M=5 | M=6 | M=7 | M=8 | M=9 |
|---|--:|--:|--:|--:|--:|--:|--:|
| mlp.gate_up (µs) | −0.55 | +24.8 | +35.4 | +23.4 | +40.7 | +58.8 | +34.8 |
| mlp.down | 0.0 | +11.2 | +10.5 | +9.3 | +18.9 | +28.5 | +14.6 |
| lm_head | +17.1 | +199 | +275 | +190 | +314 | +440 | +265 |

Pays at every M≥4; M=3 is a wash and is declined outright rather than
per-shape-tuned. Exactness: the table entry is the *same BF16 expression
tree in the same order* (`s += xv[0]+xv[1]+xv[2]+xv[3]`, float accumulator);
filling it from host float32 would break bit-identity.

**Transfer:** NVFP4 has no zero point, so this does not apply to the
`nvfp4_*` family. It applies verbatim to `lib/kernels/int8_affine/` and to
any future affine-4 (MLX-format) backbone. The *shape* of the idea — anything
the producer kernel can emit as an epilogue that every consumer would
otherwise recompute — applies everywhere.

### 1.4 The width plan has holes; sweep it, then sweep it again

Part 1 recorded the M=8 register cliff (3+3+2 beat 4+4). This pull adds:

- **M=4, IPG 4 → 2: the single largest local delta on the board, +17% decode
  wall.** M=4 (the modal width) cost 65.6 ms/emitted-token against 30.5 at
  M=5 because IPG=4 instantiated NA=4 and fell off the occupancy cliff. The
  fix selects the NA=2 tail path M=5 already used. The per-width cost table
  was read straight from the harness's own `block_request_seconds` zipped
  with `effective_draft_lengths` — no kernel harness needed.
- **M=8 4+4 later beat 3+3+2** (+0.23%, then +0.67% isolated) once
  DIRECT_NIBBLES was on: fewer weight streams won after the ALU trade
  changed. The same cell flipped sign between two kernel generations.
- **M=7 is stuck at IPG=4** because `7 % 2 == 7 % 3 == 1` and the template
  refuses one-input tails. Fixing it needs the tail groups outlined into
  separate specializations so Metal stops allocating the union register set.

**Rule (restated, stronger):** the cost curve is non-monotonic in width and
*changes when any other kernel property changes*. Re-run the full width scan
after every kernel change, and read the per-width cost off the real decode
loop, not a microbench.

### 1.5 DIRECT_NIBBLES: the amortization rule, now bracketed

Part 1 §1 gave the rule "fold the nibble shift into the operand loaded
fewer times". The board then measured the boundary: shifting the weight
wins at NA≥3 (+5–8% per matvec, M=6/9) and **loses at M=1 (+15% slower on
gate_up) and M=2 (+21% slower on down)** — one shift+mask per multiply with
nothing to amortize it over. Family-wide adoption was tried, measured, and
reverted. Also confirmed again: the affine bias sum must stay the BF16
expression `xm[0]+xm[1]+xm[2]+xm[3]` — a float-summed prototype mismatched
50/50 random cells.

### 1.6 Per-width compile-time bodies with single-pass accumulators

senpai's arm: one compiled entry per width, and at widths 6 and 7 all rows
accumulated in one pass over K instead of 3 or 4 passes (each pass re-reads
activations and the weight block). It only fits after moving the per-row
scale/bias loads and the chunk-sum read *to the point of consumption*:

| width, single pass | registers (of 126) | spilled |
|---|--:|--:|
| 6 | 105 | 0 |
| 7 | 118 | 0 |
| 7, before the code motion | 126 | 16 B |
| 8 | spills | — (not shipped) |

Predicted 3–9%. It was accepted, then overlaid by a zero-delta resample of a
sibling tree within the same day, so its ranked value was never isolated;
the tip runs the IPG-split table (6→3+3, 7→4+3). Treat the register census
as the transferable fact: **at head-dim-scale K the single-pass body is one
load-placement decision away from spilling.** Our `nvfp4_wideh_*`
half-footprint trick (part 1 handoff) is the same fight from the other side.

### 1.7 The SDPA width wall and how it was cracked

Verify widths ≥6 drifted from the serial trajectory in top-2 *values* (ids
held) and the drifted K/V rows contaminated every later round under the
exact-value replay. The GDN scan was suspected and cleared (sequential in T,
per-row arithmetic T-independent). The one op whose arithmetic changes above
width 5 is SDPA: `qL * gqa > 32` falls off the fused vector path. Fix:
split a 6..9-row causal decode attention into two ≤5-row SDPA calls whose
bottom-right-aligned windows are byte-identical to the ≤5-row rounds';
segmenting the whole *forward* (two model calls) was also exact but paid a
second weight pass (~25 ms) and lost. Widths 6–8 measured bit-exact per
position afterwards.

**Transfer:** our `sdpa_decode_hd256.metal` / `sdpa_vector_hd256.metal` are
ours, so we do not have MLX's dispatch cliff — but we do have a GQA×width
product, and `decode_quad` is the first width where it matters. Before any
width-5+ ladder: a hexfloat per-row top-2 comparison of the wide forward
against serial (their `MLX_QWEN_MTP_TRACE`-style gate), not argmax equality.

---

## 2. Launch-count mechanics in the target loop

- **Fused residual-add + RMSNorm at every layer boundary, +1.42%.** The
  residual flows through the 64-layer loop as an unmerged `(base, delta)`
  pair; each layer performs the previous exit merge and its own entry norm
  in one launch. Exact because the add is rounded to BF16 *before* squaring
  (mirroring the eager write-back) and the reduction tree copies
  `rms_norm.metal`. ~127 launches/forward removed. Rounds on M5-class
  silicon are ~75% per-op dispatch by their profile, so this pays even
  though no bytes move.
- **Attention copy elimination:** two real `Copy` kernels per FA layer
  (flattening the packed q/gate split and the transposed SDPA output) fed
  an elementwise `x * sigmoid(gate)`. Keep both operands 4-D — the compiled
  elementwise handles strided inputs — and flatten *after*, on the
  contiguous output, where it is a free view. 32 launches/forward.
- **Memoized geometry constants** (`pow(headKDim, -0.5)` and its bf16 cast
  were fresh graph nodes per layer per call: ~96 nodes/round at 37–70 µs
  host cost each).
- Dual pre-fc RMSNorm as *one Metal kernel* — accepted; the same arithmetic
  behind `mx.compile` had scored −5.05%.

What did **not** pay, repeatedly: `compile()` of small satellite graphs
(−4.1%, −5.05%), extending the asyncEval ladder to wide S (−0.9%: the eval
wall there is execution, not host build), `MLX_MAX_OPS_PER_BUFFER` 12 or
100 (slower / nothing), and — on the fastest tree — every host-side
plumbing removal (device-resident primary, draft-id eval drop, identity
slice removal): none set a new per-prompt minimum.

**Transfer:** we already fuse residuals into matvec epilogues
(`*_residual.metal`, `moe_combine_8_packed_residual`) and norms into
`rms_norm_gated`. The remaining audit is *copies*: any transpose/flatten
that materializes between a matvec and its consumer.

---

## 3. The draft readout: from a 98k-row sweep to a 15k-row probe

Per proposed token the head must pick argmax over the compact draft vocab
(98,336 rows × 5120). Part 1 §3 recorded the affine-2 coarse + top-32 +
affine-4 rerank idea (283 → 157 MB). This pull made it ~10× smaller again
and fixed the selection ops around it.

### 3.1 `argPartition` was a full sort

MLX's `ArgPartition::eval_gpu` is a stub that calls the merge sort: for a
98,330-wide bf16 row that is `multi_block_sort` — 1 block sort + 6
partition/merge levels + copy = **14 dependent dispatches and 5 temporaries
to read 32 elements**. Replaced by two fixed-shape kernels (64 tiles × 256
threads; per-simdgroup top-32 by 32 rounds of `simd_max` over
`(ordinal, index)` pairs; one finalize group): 247 → 144 µs/call, ~100 µs
per proposed token. Element-wise identical to the sort's tail, *including
tie order*: stable ascending sort ⇒ ties break to the higher index, NaN
above every number, `-0` must be folded into `+0` before the monotone
bit-map, all NaN payloads collapsed to one ordinal. A bug it found: at 8
tiles the per-thread slot count (49) overflowed a 32-bit `taken` mask and
corrupted 1 trial in 120 — now a `static_assert`.

### 3.2 E87: a derived two-level cluster index (3.256 → 3.328 → …)

Built once at warm from the head this process already loaded — no new
weights, no file:

1. Dequantize the exact affine-4 compact lm_head rows; bisecting k-means
   partition (8 iterations) into leaves of **8 rows**; canonical order =
   compact ids ascending within a leaf. 98,336 / 8 = 12,292 leaves.
2. Centroid = leaf mean, quantized **2-bit** group-64, like the rows.
3. Per draft step: 2-bit centroid QMV (N=12,292) → select the top
   `probeFraction` leaves → gathered 2-bit QMV over those leaves' rows
   → top-32 → affine-4 exact rerank of 32 rows → one id.

Probe fraction is the whole quality/speed knob and it has a cliff:

| probe fraction | leaves probed | rows read | ranked |
|--:|--:|--:|---|
| 1.0 (dense coarse) | 12,292 | 98,336 | 3.256 baseline |
| 0.25 | 3,073 | 24,584 | 3.328 |
| 0.15 | 1,844 | 14,752 | 3.691 (+0.25% over 0.25 on the same tree) |
| 0.12 | 1,475 | 11,800 | **3.646 (−4.5%)**, 0/7 prompts faster, schedule drifted — proposal-quality loss |

Bytes per proposed token on the tip: centroids 0.8 MB + 14,752 coarse rows
~19 MB + 32 exact rows ~0.1 MB, against 283 MB for the exact full sweep. A
shortlist-miss instrument (poison the winning slot; 1536/1536 flips) showed
0/3068 misses at K=32 on real prose — the acceptance deficit is
scorer-vs-target disagreement, not shortlist coverage. K=96 = K=32.

Everything that touched the selection ops after that was launch count:
the probe select and shortlist as two 1024-thread dispatches instead of two
merge sorts (+0.72%; 16-bit ordinal keys exact for bf16, two 8-bit
histogram passes for the threshold, popcount walk for the index cut), the
32-row exact rerank fused with its argmax into one dispatch, and E121
(+2.62%): the centroid QMV at N=12,292 had been on the *bounds-checked
non-fast* path because 12,292 % 8 ≠ 0, and the 3,073-tile gather likewise —
both rewritten as 32-value/lane kernels with `ulong` loads.

**Transfer — the biggest single item for us.** Our head step is 1.95 ms of
which ~1.2 ms is bandwidth over ~540 MB, half of it the 252 MB draft
projection (`mtp_draft_select_fast.metal` scans it exactly). A derived
cluster index at 0.15 cuts that read ~13× and costs nothing but acceptance
that must be *measured*: the 0.12 cliff says re-run `rank-probe` at every
fraction. The `q2draft` ABBA loss was a 2× cut; this is a 13× cut, so the
earlier verdict does not carry.

### 3.3 Precision islands, then their dead work

The declared head ships exact BF16 rows for Q (1,024 worst-SSE rows) and
*all* 1,024 K and 1,024 V rows, scattered over the quantized QKV output
with `putAlong`. Once the K/V islands are complete permutations, the
quantized K/V columns are 100% overwritten before any read: skipping that
GEMM and building the output by `take` with an inverse-permutation order is
bit-identical by construction (~9 MB dead weight stream per draft step,
0.4–1 ms once on the 511-row priming flush). Local +0.42% with identical
acceptance.

---

## 4. Head weights (proposal-only, so lossy is legal)

| head | size | MTP s/tok | accept | local ratio |
|---|--:|--:|--:|--:|
| bf16 pinned | 849 MB | 0.01572 | 0.991 | 2.30 |
| **4-bit affine g64** | 239 MB | 0.01505 | 0.956 | **2.42** |
| mixed (q/fc/MLP 4-bit, k/v/o bf16) | — | 0.01528 | 0.947 | 2.36 |
| 2-bit MLP | — | — | −3.9 pp | lost |

−3.5 pp acceptance is worth +4.5% head speed here; the mixed head was worse
on *both* axes because the loss is in the large fc/MLP tensors, not
attention. 8-bit was blocked by the loader, not measured. A 1M-token head
fine-tune moved accept@1 by +0.14 pp (noise); a retrained bf16 head
(0.652) did not beat the shipped 4-bit + islands head (0.642) enough to
submit. The board's remaining margin is per-position acceptance, and nobody
found a cheap way to buy it.

---

## 5. The draft schedule, settled

> **Superseded for sampling engines — see §8b.** Everything below is
> the *greedy-median* optimum. On MTPLX's 16K stochastic ABBA the adaptive /
> streak / EMA family regressed 5–14%; ship a fixed block instead.


The shipped policy, verbatim in shape:

```
reach = 1; expected = 0; depth = 0
while depth < cap (=7):
    p = EMA_accept[depth]                      # per-position EMA, alpha 0.15
    if depth == 0: p = min(p, sigmoid(margin/2))   # target top-2 margin of the pending primary
    if depth == 1: p = min(p, sigmoid(margin/3))
    reach *= p
    threshold = h * (1 + expected) / (1 + depth*h)  # h = 0.18, flat per position
    if reach <= threshold: break
    expected += reach; depth += 1
```

What the receipts pinned:

- **h is bracketed on both sides**: 0.14 → 2.766, 0.15 → 2.667, 0.18 →
  crown, 0.32 → 2.846 (−3%, baseline leg flat, every draft shorter,
  candidate decode *slower*), 0.40 → −4.5%. The true marginal (row slope
  7.4 ms + head 2.5 ms over a 31 ms forward = 0.32) is the wrong price
  because **this pool rewards depth**: the marginal draft is worth more than
  its verify row.
- **Buy depth with the cap, not the price.** A price moves every round
  including hard prompts (0.32 dragged prompt 6 from 0.17 to 0.06 drafts).
  Then the streak gate itself turned out to be a *floor* that truncated the
  deepest-accepting prompt after every reject (−2.6% on that prompt);
  **flat cap 7, no gate** beat cap 8 + gate 2 (3.3096 vs 3.3022 on the same
  tree). Gate 1 was −7.1%; a three-rung ladder degenerated into plain cap 8
  because full-accept streaks ≥4 are common at this acceptance.
- **The schedule is a closed loop.** Changing a price changes which drafts
  are proposed, which changes observed acceptance, which moves the EMAs,
  which moves depth again. An open-loop "charge one more row above width 5"
  predicted 4.23 and got 4.58 on the median prompt and cost the deep prompt
  6% (3.203, a clean negative).
- **Non-uniform per-position prices are fitted to one dispatch table.**
  `pbfit` (marginal price proportional to the measured verify-width step
  costs, e.g. step into width 6 = 27.3 ms vs 13.4 into width 5) won −3.5%
  on the tree it was fitted on and +0.33% on the crown's table. Refit
  whenever the QMV group shapes move.

**Transfer:** `mtp3`'s `segmentedStreakGate` is exactly the floor the board
deleted. Our depth choice is driven by p = 0.50–0.62 where theirs is
0.75–0.8 per position on hidden prose (§dflash2 doc), so the cap does not
bind for us yet — but when acceptance moves, replace the gate with the
marginal rule above and *sweep h*, expecting the optimum well below the
measured marginal.

---

## 6. Warm-up and driver residency

- **Every scored shape must be compiled before the clock starts**, and the
  list keeps growing: the normed-verify variant at widths ≥2 (+0.16%), SDPA
  query lengths `{1,2,3,4,5}` at the 1024 and 1025+ windows (+0.18%; qL 2/3
  are hit as the second chunk of width-7/8 verifies), the 128-block SDPA
  family that engages once N > 1024, the top-32 kernels, the E87 kernels.
  Constructing a kernel object you never dispatch still walks the JIT
  catalog on first use (skipping one: +0.7%, the current crown).
- **Wired residency + command-buffer size**: a zero-headroom
  `WiredMemoryTicket` sized at `active + 64 MiB` after warm, plus
  `MLX_MAX_MB_PER_BUFFER=512 / MLX_MAX_OPS_PER_BUFFER=50` (+0.12%). The
  512 was a comment, not a fact, until `setenv(..., overwrite=1)` — the
  first version used overwrite=0 and lost to an earlier export.

---

## 7. Methodology that decided more than any kernel

- **Restoration sweeps.** Submissions are whole-file overlays; an archive
  built on a stale base silently evicts every sibling mechanism in the files
  it carries. At least six promotions in this window were *restores* of
  something a previous accept had deleted (fusion chain, residency hooks,
  M=8 4+4, qL warms, probe-select). After every merge: diff the tip against
  the previous crown per mechanism, not per file.
- **Serial is stable, candidate is right-skewed.** Serial s/token cv 0.11%
  across all scored runs; the candidate side across 84 identical-schedule
  runs on one prompt: min 0.012106 / median 0.012139 / p90 0.012403 / max
  0.014716. **A run can land above its tree's true speed but never below,
  so compare minimums, and only a new minimum is evidence.** Even-8 median
  noise is σ ≈ 0.5–1.5%; a bad draw and a drafting-side regression are
  indistinguishable by score.
- **Schedule fingerprint as the null check** — rounds / accepted-draft rate
  / declared rows digit-identical across five kernel archives proved they
  perturbed no logit the accept walk consumes. Same instrument as our
  acceptance check, formalized.
- **The per-width cost table is free.** `block_request_seconds` × per-round
  draft length from any timed run found the M=4 cliff.
- **Local proxies did not transfer for kernel-table effects**: one account
  went 0/4 with mechanisms faster on M4 Pro and sub-crown on M5 and stopped
  submitting mechanisms.
- **One mechanism per archive.** The same fusion scored +0.4% alone and flat
  bundled with a schedule tweak; the bundle was the drag.

---

## 8. Negative results, priced (do not re-walk)

| tried | result |
|---|---|
| DIRECT_NIBBLES at M=1 / M=2 | +15% / +21% slower (no amortization) |
| single-stream NA=M QMV (one weight pass for all rows) | −5–8% at M=5..8 *only* with grid.x=1; in-kernel frozen-grid variant a wash |
| compact draft vocab 98,304 → 49,152 or 65,536 | accept 1.00 → 0.877, −9%; 1/64 of argmaxes live in the dropped band |
| probe fraction 0.12 | −4.5%, 0/7 |
| head `mx.compile` chains, compiled pre-fc fuse | −4.1%, −5.05% |
| asyncEval ladder at S ≤ 9 | −0.9% |
| deferred head-cache trim | −6.7% |
| exact-QKV install skip | −8.8% |
| `MLX_MAX_OPS_PER_BUFFER` 12 / 100 | slower / nothing |
| chunk-B attention-row price in the schedule | −1.3% (closed loop) |
| streak gate 1 / three-rung ladder | −7.1% / degenerates to cap 8 |
| 2-bit head MLP | −3.9 pp accept for ~1.5% bytes |
| target-side HALF_K footprint | MTP parity **fail** (verify reduction tree moved) |
| 1M-token head fine-tune | +0.14 pp, noise |

---

## 8b. Authoritative cross-check — the same 54 rows re-run on a real runtime

**The ranked median mis-ranked several of these.** David Tai's MTPLX PR
(`youssofal/MTPLX#335` @ `9a6f48e6`, `docs/perf/qwen38-challenge-port-ledger.md`)
re-ran all 54 Yukon proposals on a real MLX runtime at **16,384 Python tokens,
1,024 output, temperature 1.0 / top-p 0.95 / top-k 20 (stochastic), four ABBA
arms under an exclusive GPU lock**. The challenge scored 512-token *greedy*
median; these two disagree, and for a production engine the ABBA-at-16K column
is the one to trust. Full reconciliation in `dflash2-speculation.md §2`; the
load-bearing corrections:

- **Three ranked wins REGRESS on the real workload:** packed target QKV
  **−4.06%**, paired G32/M4 target QMV **−3.84%**, and four-way GDN input
  projection through S≤9 **−0.99%** — the last was an *accepted challenge
  submission* (`3e157ad9`, the one-line `S<=2 → S<=9` guard lift). Ranked +0.2%
  at 512 greedy, negative at 16K stochastic.
- **The entire draft-schedule family (§5) LOSES under sampling:** position-EMA
  policy −5.6%, streak-gate constant −5.5%, first-margin clamp −4.3%,
  streak-3 revision **−14.3%**. Under stochastic block verify a fixed block
  beats the greedy marginal-depth rule. **§5 below is a greedy-median artifact;
  do not port the adaptive schedule to a sampling engine.** (This also retires
  the handoff's `mtp3` `segmentedStreakGate` direction.)
- **Greedy-only mechanisms are undefined under temperature:** second-argmax
  reuse and argmax-only selectors have no meaning when the target samples.
- **DIRECT_NIBBLES (§1.5) does NOT transfer to a separate drafter's matvec:**
  M6/M7/M8 direct-nibble on the DFlash draft path measured −4.3 / −3.9 / −7.1%,
  all rejected. It pays on the **target** path only. Where target-shape exact
  kernels were swept (exact M5 K-split +1.4%, M7→M8 pad +1.3%, selected-M6,
  M8 K/V/MLP), each was a small additive win — §1.4's "sweep every width"
  confirmed, but the sign only appears on the real workload.

**What robustly transferred (RETAINED, real Δwall):** device-resident draft-id
chain +3.6%, compact Q4/G64 vocab +3.0%, K/V-only committed history +2.1%,
three-layer prefill cadence +1.7%, exact Q4/G64 MTP block +1.4%, fused Q/K
RMSNorm+RoPE +1.3%, memoized GDN decay +1.0%, fused dual RMSNorm+concat +1.0%,
boundary residual/RMSNorm fusion +0.9%, wired residency +0.8%, Q/K L≤16 fence +
eval ladder +0.8%, 512 MiB/50-op command buffers +0.5%. Port from this list,
not from the ranked scores.

**And the headline the whole PR exists to establish:** replacing the native MTP
head with a **separate trained W4 DFlash2 drafter** was +7% (fixed M8, isolated)
to +20–25% (1K ABBA) decode over the fully-ported MTP stack. For tungsten the
drafter architecture is a bigger lever than any kernel here — see
`dflash2-speculation.md`.

## 9. Transfer list, in order of expected payoff for tungsten-llama

> **Re-prioritized 2026-08-25 after §8b.** The largest lever is not in this
> kernel list at all — it is the **drafter architecture** (a separate trained
> W4 DFlash2-style draft model beat the MTP head by 7–25% on a real runtime;
> see `dflash2-speculation.md`). Among engine items, port from §8b's RETAINED
> list and skip its REGRESSED list; the cluster index below is still the top
> *readout* item but re-ABBA it at 16K, not 512 greedy.

1. **Derived cluster index for the draft selector** (§3.2) —
   `lib/kernels/qwen3_6/mtp_draft_select_fast.metal` becomes the *rerank*
   stage; new: leaf partition at load, 2-bit centroid matvec, probe select,
   gathered leaf matvec, top-32. Sweep probe fraction with `rank-probe`;
   expect the cliff between 0.15 and 0.12. Size: ~0.4 ms of the 1.95 ms head
   step, i.e. ~1 ms/round at depth 2, ~2%, more at deeper drafts.
2. **Tight-grid audit of every multi-row kernel** (§1.2) — pair/triplet/
   quad and the wide QMV. Count groups that can return before their first
   load; if any, the grid is over-launched by that fraction × N/…
3. **Per-width cost table from the real loop** (§1.4) — instrument the bench
   to zip round time with draft length; look for the non-monotone width.
4. **Hexfloat row gate for widths ≥5** (§1.7) before any ladder past
   `decode_quad`.
5. **Marginal-rule schedule** (§5) replacing `segmentedStreakGate`, with h
   swept, once acceptance is high enough for the cap to bind.
6. **Copy audit** in the target loop (§2) — transposes/flattens between a
   matvec and its consumer.
7. **Chunk-sum epilogue** (§1.3) — `int8_affine` only.
