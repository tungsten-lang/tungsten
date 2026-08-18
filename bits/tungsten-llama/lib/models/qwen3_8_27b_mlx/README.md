# qwen3.8/27b-mlx

Status: **working decode inference from Ollama MLX blobs.**

The runner supports the dense Qwen3.5-family text architecture used by
`qwen3.8:27b-mlx`: 48 GatedDeltaNet layers, 16 full-attention layers, dense
SwiGLU FFNs, partial RoPE, recurrent state, and KV caching. It consumes the
Ollama weight blobs through mmap-backed symlinks; the 18 GB of tensors are not
copied.

## Setup and run

```sh
ollama pull qwen3.8:27b-mlx
ruby scripts/bench/prepare_ollama_mlx.rb qwen3.8:27b-mlx
python3 bits/tungsten-llama/scripts/tokenizer_pack.py \
  ~/.cache/tungsten/qwen3.8-27b-mlx/tokenizer.json \
  ~/.cache/tungsten/qwen3.8-27b-mlx/tokenizer.json.bin
bin/tungsten run scripts/bench/qwen38_mlx.w concurrent 12
bin/tungsten run scripts/bench/qwen38_mlx.w mtp 24
bin/tungsten run scripts/bench/qwen38_mlx.w mtp-auto 48
```

Wrap any timed run in the lock so a concurrent agent cannot overlap it --
two GPU runs at once do not fail, they return plausible wrong numbers:

```sh
scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/qwen38_mlx.w mtp 64
```

Two diagnostics share `ARGV[7]`, both of which need a real prose prompt
(`ARGV[5]` above 5 tokens) to say anything:

```sh
# Marginal cost of the 1st/2nd/3rd verified row, interleaved in one process.
# Needs mtp2 or mtp-auto: triplet scratch is only allocated there.
bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 8 r2 mmap none 64 auto row-scan

# Rank of the target's token in the MTP head's draft distribution.
bin/tungsten run scripts/bench/qwen38_mlx.w mtp 64 r2 mmap none 64 auto rank-probe
```

The runner checks raw-prompt parity before benchmarking: `The capital of
France is` must predict token 11751 (` Paris`). Baseline, optimized-serial,
optimized-concurrent, and MTP modes emit the same greedy token sequence.

## Measured decode performance

Apple M5 Max, 128 GB, 12 generated-token forwards, three alternating runs:

| Mode | Median |
|---|---:|
| per-layer commits, unfused | 19.74 tok/s |
| fused, one serial command buffer/token | 26.49 tok/s |
| fused, dependency-barrier concurrent phases | 26.91 tok/s |

The concurrent result is 36.3% faster than the matched baseline. These are
decode-only numbers at short context; they do not characterize long-context
prefill.

### Actual MLX comparison (2026-08-16)

Two opt-in runners separate the questions "how fast is a complete MLX graph?"
and "what happens if Tungsten crosses into MLX for each projection?":

```sh
# Requires mlx-lm 0.31.3 (tested with mlx 0.32.0).
python3 scripts/bench/qwen38_mlx_lm.py --tokens 48 --runs 5

# Builds a Tungsten executable linked to mlx-c and calls
# mlx_quantized_matmul from Tungsten on every profiled QMV.
scripts/bench/build_qwen38_tungsten_mlx_qmv.sh
```

On the same M5 Max, checkpoint, raw prompt IDs, greedy argmax, and 48 timed
target forwards, five alternating process pairs produced 28.322 tok/s median
for the complete MLX-LM serial graph and 26.432 tok/s for Tungsten's ordinary
concurrent graph. MLX led the matched target-only comparison by 7.15%. Every
one of the 49 emitted token IDs matched. A separate five-run Tungsten MTP-1
sample measured 36.309 tok/s median with 24/24 drafts accepted, but that is a
different decoding strategy and is reported separately rather than attributed
to faster target kernels.

The C-API runner validates single- and two-row output samples on all eight
production QMV shapes; maximum absolute error was 4.77e-7. Across four process
runs, the projection-count-weighted serial total was 19.49--32.56 ms for
Tungsten's custom Metal kernels and 93.31--112.19 ms for per-projection MLX
bridge calls. Those are deliberately different timing contracts: Tungsten is
measured with batched Metal GPU timestamps, while each MLX call must evaluate
and synchronize before a custom Tungsten kernel could consume its output. The
bridge result is therefore the cost of the actual hybrid boundary, not a claim
that MLX's isolated GPU kernel takes the reported wall time. The full MLX-LM
result shows why keeping the complete lazy graph inside MLX avoids that cost.

### Packed mmap and row-group validation (2026-08-16)

The runner now wraps each safetensors shard's page-aligned mmap region and
binds the tensor's byte offset in Metal. A warmed matched loader comparison
with eight generated tokens measured 1.95 s wall / 0.562 GB maximum process
RSS for mmap binding versus 2.86 s / 34.55 GB for the one-time copy fallback.
The RSS figure is process accounting, not total GPU/file-cache residency.
Decode remained noise-level equivalent.

`scripts/bench/autotune_qwen38.w` sweeps 4, 8, and 16 output rows per
threadgroup plus the MLX-style `r=2` packed-qdot path against real weights,
using Metal GPU timestamps for every production QMV shape. It also validates
and times the two- and three-token shared-weight projections used by MTP
verification, including lower-register candidates.
`scripts/bench/autotune_qwen38_model.rb` runs the full greedy graph across
ordinary/MTP modes and 4r/8r/16r/r2/auto schedules, rejects
any candidate whose token IDs diverge, and reports the median winner.

```sh
bin/tungsten run scripts/bench/autotune_qwen38.w
ruby scripts/bench/autotune_qwen38_model.rb
bin/tungsten run scripts/bench/autotune_qwen38_layout.w
bin/tungsten run scripts/bench/autotune_qwen38_fusion.w
bin/tungsten run scripts/bench/profile_qwen38_components.w
```

### MTP-1 speculative decoding (2026-08-16)

The inline `mtp.*` tensors now drive a one-layer self-draft head. Verification
runs the current token and one draft as a causal pair: each NVFP4 group is
loaded/dequantized once and dotted with both f32 activation rows. On rejection,
the full-attention row is overwritten at the next position and each
GatedDeltaNet layer swaps to the retained state after the pair's first token.

Three alternating 24-token runs on the M5 Max measured 27.810 tok/s median for
ordinary concurrent decode and 36.199 tok/s for MTP-1, a 1.302x improvement.
The benchmark prompt accepted 12/12 drafts and produced byte-identical greedy
token IDs. A forced first-round rejection plus a natural rejection accepted
11/13 drafts and still reproduced the ordinary sequence, exercising the
recurrent rollback path.

The MTP proposal path now also carries two MLX.fast-derived savings that do
not touch target logits:

- draft selection projects only rows 0...98,303 plus Qwen control-token rows
  248,044...248,069, while target verification keeps the full 248,320-token
  LM head;
- committed history updates stop after writing the MTP attention K/V row,
  skipping the unused Q/attention output, MLP, final norm, and LM-head work.

Five alternating 48-token runs measured 39.152 tok/s median for this path and
34.532 tok/s for `legacy-mtp`, a matched 1.134x improvement with 24/24 drafts
accepted and identical emitted IDs. Isolated ablations measured 4.95% from the
compact draft vocabulary and 2.58% from K/V-only history. Against ordinary
concurrent decode in a separate five-pair run, optimized MTP measured 37.267
versus 25.960 tok/s median (1.436x). The spread between runs is thermal, so the
alternating comparisons—not cross-run absolute rates—are the useful result.

An experimental `mtp2` mode drafts two tokens and verifies three target rows
in one causal pass. It is parity-clean, including forced first-draft rejection
and both recurrent rollback prefixes, but is not the default: five alternating
48-token pairs measured 32.967 tok/s median for MTP-2 versus 38.247 tok/s for
MTP-1. The triplet QMV profiler explains the loss. Even its lower-register
variant takes roughly twice the pair kernel on the large backbone shapes, while
the second draft is accepted only about 61% conditionally on this prompt
(29/37 total draft acceptance). The arm remains available to autotune future
triplet kernels without weakening the faster MTP-1 path.

`mtp-auto` turns the two implementations into measured runtime arms. It sends
real decode rounds through depth one and depth two, scores emitted tokens per
wall-clock millisecond (including drafting, verification, history updates,
copies, and rollback), then retains the faster depth. In two order-reversed
48-token comparisons it selected depth one: the depth-one arm measured
50.98/53.59 tok/s while depth two measured 36.70/36.36 tok/s. Probe-inclusive
`mtp-auto` ran at 48.63/50.74 tok/s versus 52.23/52.46 tok/s for fixed MTP-1.
The mode is therefore an experimental controller scaffold for a long-lived
runner, where probes can be amortized across requests; `mtp` remains the fast
short-process default. All four runs emitted identical greedy IDs.

Additional width-three kernel experiments explain why the controller cannot
yet profitably retain depth two. Concurrent pair-QMV plus single-QMV improved
isolated backbone projections by roughly 18--32%, but three matched 48-token
full-model pairs measured 44.44 tok/s median versus 46.83 tok/s for the single
triplet grid: the extra grids contend with projections already overlapping in
the concurrent encoder. Restricting the split to residual-only phases was
neutral (44.28 versus 44.53 tok/s in a matched 24-token pair). A K-major
interleaved-activation QMV, a scalar packed-qdot variant, and an 8-row
simdgroup-matrix kernel were also exact but slower, so none is on the decode
path. The real remaining requirement for deeper MTP is a width-three/four
quantized matmul that scales without triplet register pressure or extra-grid
contention.

The model autotuner can sweep the ablations directly:

```sh
KERNELS=0 MODES=mtp SCHEDULES=r2 \
  MTP_VARIANTS=optimized,legacy,full-vocab,full-history \
  ruby scripts/bench/autotune_qwen38_model.rb
```

Fixed and adaptive draft-depth arms use the same parity gate:

```sh
KERNELS=0 MODES=mtp,mtp2,mtp-auto SCHEDULES=r2 RUNS=2 \
  ruby scripts/bench/autotune_qwen38_model.rb
```

### Component and Ollama gap analysis (2026-08-16)

Ollama 0.32.13's MLX runner is not faster because Metal has a native NVFP4
instruction. It uses MLX quantized matmul, compiled elementwise functions,
fused causal-convolution/GatedDelta kernels, packed QKV+Z and beta+alpha
projection rows, and—most importantly for its warm headline number—an
adaptive MTP controller that probes and retains draft depths up to four.

On the same model and 48-token raw prompt, five warm Ollama requests measured
61.05--68.58 tok/s (64.99 median). The log reported only 16--18 target
iterations, maximum draft depths three or four, and 1.67--2.00 accepted drafts
per iteration. Disabling speculation with `logprobs` measured about 30.53
tok/s warm. Thus Ollama's target-only advantage over Tungsten is small; its
remaining end-to-end advantage is primarily more accepted output tokens per
target forward.

Two avoidable Tungsten reductions were material:

| Kernel | Previous | Autotuned |
|---|---:|---:|
| RMSNorm, width 1 | 23.96 us | 3.25 us |
| RMSNorm, width 2 | 48.38 us | 3.31 us |
| RMSNorm, width 3 | 35.31 us | 3.32 us |
| full-vocabulary argmax, width 1 | 1,648 us | 3.92 us |
| full-vocabulary argmax, width 2 | 849 us | 4.90 us |
| full-vocabulary argmax, width 3 | 897 us | 5.94 us |

The new RMS kernel uses one 512-thread threadgroup per activation row. The new
exact argmax uses 1024-logit first-stage tiles followed by one reduction per
row; validation covers independent rows and tied maxima with lowest-index tie
breaking. Four alternating legacy/new 48-token pairs measured 27.74 -> 30.98
tok/s median for ordinary decode (+11.7%) and 40.99 -> 53.33 tok/s for MTP-1
(+30.1%), with identical greedy IDs.

The final full-model schedule sweep used two parity-checked 48-token runs for
each mode/schedule pair. It selected 16r ordinary at 30.799 tok/s, r2 MTP-1 at
52.922 tok/s, and r2 MTP-2 at 46.467 tok/s. MTP-1 accepted 24/24 drafts on the
benchmark; MTP-2 accepted 29/37 overall and 11/18 second drafts.

The non-QMV profiler shows why KV handling is not the short-context gap:

| Component | Width 1 | Width 2 | Width 3 |
|---|---:|---:|---:|
| depthwise causal conv | 1.39 us | 1.78 us | 2.05 us |
| GatedDelta recurrence | 11.79 us | 20.76 us | 30.06 us |
| KV write | 2.11 us | 1.23 us | 1.26 us |
| SDPA, context 5 | 3.72 us | 4.76 us | 5.35 us |
| SDPA, context 64 | 31.43 us | 32.39 us | 33.09 us |
| SDPA, context 126 | 60.90 us | 61.76 us | 62.03 us |
| BF16 5120x48 projection | 18.89 us | 19.84 us | 20.17 us |

NVFP4 QMV remains the dominant target cost. In a profiled 48-token MTP-1 run,
24 pair target forwards took about 817 ms; all drafting took about 80 ms and
history/copy/rollback work was negligible by comparison.

Projection fusion was measured rather than assumed. QKV+Z took 117.8 us as a
combined grid versus 72.0 us as independent concurrent dispatches. Gate+up was
180.2 versus 177.7 us, K+V was 10.26 versus 10.78 us, and down+residual was
68.4 versus 69.7 us. Consequently the runner keeps independent concurrent
large projections and the modest residual-store fusion; Ollama-style row
packing is not a general win for these QMV kernels.

The checkpoint's output-row-major layout also wins for backbone projections.
The group-major experiment was 1.1--3.2x slower for QKV and 5.8--10.5x slower
for MLP-down at widths one through five. It helps only the very tall LM head:
at widths three/four/five it was 1.28x/1.34x/1.49x faster after a one-time
3.74 ms repack. That isolated win is too small to rescue MTP-2, whose complete
triplet target is about 14 ms slower than a pair target.

Finally, mmap binding directly exposes page-rounded safetensor regions as
shared Metal buffers. A measured mmap run spent 155 ms in setup, 841 ms in
the first weight-touching forward, 162 ms across the next four prefill tokens,
and 391 ms across 12 decode tokens. The copy fallback spent 1,758 ms in setup,
110 ms on first touch, 129 ms on the remaining prefill tokens, and 387 ms on
decode. Copying therefore front-loads 1.6 seconds and substantial anonymous
memory without a steady decode benefit. Packed NVFP4 weights stay mmap-backed
and are decoded in registers on every QMV; no f16 expansion is stored on disk
or materialized at load.

### Benchmark fixture: the prompt must be real prose (2026-08-17)

`profile_prompt_tokens > 5` used to tile the 5-token parity seed
`[760, 6511, 314, 9338, 369]` cyclically. A period-5 sequence is trivially
predictable, so the MTP head accepted essentially every draft — that is the
source of the 12/12 and 24/24 acceptance recorded above. **Acceptance near
1.0 is a saturated regime in which no draft-schedule decision has a sign:**
every depth looks good because a rejected draft never happens, so the
marginal cost of over-drafting is invisible. The MTP-1-vs-MTP-2 comparison,
the `mtp-auto` controller and the reported speedups were all decided there.

Long prompts now tokenize a real English passage instead. The 5-token parity
fixture is untouched (still asserts first token 11751, ` Paris`). With a
64-token prose prompt the model produces coherent continuation and
acceptance lands at **0.55**, which is the band those decisions actually
live in.

Re-measured on that fixture, three alternating pairs, 64-token prompt and 32
generated tokens:

| arm | accept | tok/s |
|---|---:|---|
| MTP-1 | 11/20 = 0.55 | 35.44 / 35.32 / 34.45 |
| MTP-2 | 16/32 = 0.50 | 32.36 / 32.32 / 31.10 |

**MTP-1 still wins, 3/3, by 9–11%** — the earlier verdict survives contact
with honest material. The reason is now quantified rather than inferred:
MTP-2 commits *more* tokens per round (2.0 vs 1.6, +25%) and is still
slower, because the triplet round costs ~62 ms against the pair's ~45 ms.
The third verified row costs **+17 ms, +38% of a round**, which matches the
"~14 ms slower than a pair target" figure measured earlier. For MTP-2 to
break even at this acceptance the third row's marginal has to drop below
roughly 11 ms.

Acceptance is also the right instrument on a contended or thermally drifting
machine: it is deterministic and reproduced byte-for-byte across all three
repetitions above (0.55000000000000004 and 0.5), while tok/s moved ~3%.

### The wide/r1 triplet split survives in-situ re-checking

The `kdim == FFN || rows == N_VOCAB -> wide, else r1` split in
`enqueue_scaled_triplet` was chosen from isolated kernel timings, which on
this kernel family are a known way to get the wrong answer: a 44-89 MB
weight tile re-read back to back is served by the system cache, while in the
real forward ~18 GB streams past and nothing is resident. `ARGV[6]` now
forces `r1` or `wide` everywhere so the split can be re-checked against the
full model.

Three alternating triples, MTP-2, 64-token prose prompt, 32 generated:

| variant | tok/s | acceptance |
|---|---|---|
| `auto` (shipped) | 32.49 / 32.36 / 31.75 | 0.50 |
| `r1` forced | 32.29 / 32.26 / 30.77 | 0.50 |
| `wide` forced | 31.62 / 31.40 / 25.26 | 0.50 |

**The shipped heuristic wins 3/3.** Acceptance is identical in all nine runs,
which is the null check: these are pure kernel-speed changes and nothing
behavioural moved. Forcing `wide` everywhere is clearly worse; forcing `r1`
everywhere is close but never better. Recorded so the split is not
re-litigated, and because it is a case where the isolated-timing choice held
up under the in-situ test.

### The third verified row was costing 8x the second (2026-08-17)

The whole speculative-decode economy turns on one number: what a marginal
verified row costs. A draft schedule buys expected tokens per round and pays
for them in rows, so if rows are cheap every deeper or wider schedule looks
attractive, and if they are expensive none of them do.

Comparing whole decode runs cannot measure it -- this box drifts more than 30%
between runs, which is larger than the effect. `ARGV[7] = "row-scan"` measures
it properly: it interleaves widths 1/2/3 **inside one process** on an
already-warm cache in a single thermal state, 40 repetitions, median. Positions
are reused deliberately -- the outputs are garbage, the timings are not. The
instrument reproduces to +/-1 ms where end-to-end wall clock swings 33%.

What it found:

| verified rows | median | marginal |
|---|---|---|
| 1 | 39 ms | -- |
| 2 | 43 ms | **+4** |
| 3 | 72 ms | **+29** |

One row is ~18 GB of weight streaming at roughly 450 GB/s, so the second row
is nearly free, exactly as a memory-bound decode should behave. The third
costing 8x the second is not physics.

It was not the wide/r1 split -- forcing either variant everywhere moved
nothing (70/72/74 and 74/81/76 ms across reps). The cause was in the kernel:
`nvfp4_matvec_mlx_scaled_triplet` dereferences `x0`/`x1`/`x2` through device
pointers *inside* the per-output-row macro, so each of the two output rows
re-issues all twelve activation loads -- **24 loads per group where the pair
kernel issues 8**, because the pair hoists its 8 `float4` once and reuses them
across both rows. The activations are tiny and L1-resident, so each load is
cheap; they were competing for the load/store issue slots that the weight
stream needs, and keeping that stream saturated is the kernel's entire job.

`nvfp4_matvec_mlx_scaled_triplet_hoist` hoists all twelve `float4` before the
macro. Arithmetic and summation order are untouched, so it is bit-identical by
construction. Interleaved against the old kernel, three reps:

| | 2 rows | 3 rows | row-3 marginal |
|---|---|---|---|
| old | 39 / 41 / 46 ms | 55 / 61 / 73 ms | 16 / 20 / 27 ms |
| hoisted | 40 / 43 / 46 ms | 43 / 49 / 55 ms | **3 / 6 / 9 ms** |

3/3, and the 2-row column is the null control: it is identical between arms,
as it must be, since the pair kernel is untouched. The marginal third row is
now ~3x cheaper and matches the second. End-to-end on MTP-2 it wins 4/4, and
all four variants emit **byte-identical token ids and identical acceptance**
-- the correctness gate for a change that claims to be bit-exact.

`auto` is now the hoisted kernel everywhere; `wide` and `rowsplit` remain
selectable so the old split stays re-checkable. This supersedes the wide/r1
result above: that comparison was real but both of its arms carried this
defect, so it was measuring which of two encumbered kernels lost less.

Worth generalising: the earlier finding on this kernel family was that
*register pressure beats instruction count*, and it led to reverting a hoist.
Here the opposite hoist wins. The reconcilable rule is that hoisting a value
reused **across output rows** pays, while hoisting one already invariant
within a row just adds live registers for nothing.

#### What the hoist is worth in tok/s

Honest accounting, because the headline number and the useful number differ.

Total wall clock could not answer this: paired runs gave anything from -1% to
+24%, because a single descheduled round drags a whole run. The bench now
reports the **median round**, which rejects those outliers, and benchmarks run
under `scripts/bench/perf_lock.sh` so a neighbouring agent cannot overlap.
Six interleaved reps, 64-token prose prompt, 64 generated:

| rep | MTP-2 legacy | MTP-2 hoisted | MTP-1 (untouched) |
|---|---|---|---|
| 1 | 55 ms | 44 ms | 38 ms |
| 2 | 56 ms | 48 ms | 39 ms |
| 3 | 57 ms | 47 ms | 46 ms |
| 4 | 71 ms | 55 ms | 47 ms |
| 5 | 82 ms | 61 ms | 48 ms |
| 6 | 83 ms | 69 ms | 53 ms |

**6/6, median -19% on the round, i.e. about +23% tok/s for MTP-2.** The ratio
holds steady while absolute times climb 50% with box temperature, which is the
point of the paired design.

**Overall best-mode tok/s is unchanged.** MTP-1 never calls the triplet kernel,
so it is untouched, and it was and remains the fastest mode. Per emitted token
(round / E[tokens], 1.615 for depth-1 and 1.909 for depth-2) the fix moves
depth-2 from ~20% behind depth-1 to roughly **tied**, trading wins rep to rep.

So the fix is worth +23% on a mode that is not the mode you would run today.
Its value is that depth-2 stops being a dead end: it is what the `mtp-auto`
controller's second arm costs, and it is the floor under any wider schedule,
since every one of them verifies three or more rows.

### Tree drafting: measured, and it does not pay here

Tree drafting -- verifying the head's top-k candidates as siblings instead of
extending one chain -- was evaluated before building it, because the decision
turns entirely on a quantity nothing in the harness reported.

Acceptance only tells you P(rank == 0): a draft is accepted when the head's
argmax matches the target's. It cannot distinguish a near miss from a
blow-out, and a k-branch tree's ceiling is exactly P(rank < k).
`mtp_draft_rank.metal` measures the full curve by counting logits strictly
greater than the target's, with the selector's lowest-index tie-break so rank
0 agrees with an accepted draft. `ARGV[7] = "rank-probe"` histograms it on the
MTP-1 path, where the head's logits are still intact when the target becomes
known.

64-token prose prompt, 64 generated, 39 drafts:

| | P(rank < k) | marginal |
|---|---|---|
| rank < 1 | 0.6154 | -- |
| rank < 2 | 0.7436 | +0.128 |
| rank < 3 | 0.8974 | +0.154 |
| rank < 4 | 0.9231 | +0.026 |
| rank < 5 | 0.9487 | +0.026 |

`rank < 1` reproduces the accept rate 0.6154 exactly, which validates the
probe. Nothing fell outside the compact draft vocabulary, so the head's
restricted projection is not the limit.

The curve is steep, and it still does not help. Compare what one extra row
buys, using the post-fix row costs (verify 37/40/43 ms at widths 1/2/3) and a
measured ~3 ms MTP head step:

| schedule | round | E[tokens] | ms/token |
|---|---|---|---|
| depth-1 pair | 43 ms | 1.615 | 26.6 |
| depth-2 chain | 49 ms | 1.909 | **25.7** |
| 2-branch tree | 46 ms | 1.744 | 26.4 |

The tree does save one head step -- both branches come from logits the head
already computed -- but that is worth ~3 ms, and it cannot cover the coverage
deficit. **A sibling branch adds +0.128 expected tokens where extending the
chain adds +0.303**, and every later branch (+0.154, +0.026, +0.026) stays
below the chain's marginal too. The reason is structural rather than a
property of this checkpoint: a sibling only pays when the head's first choice
is *wrong* and its second is right, whereas a chain extension pays when the
first choice is right and the next one is too -- and this head is right 62% of
the time.

On top of that, a tree needs an attention mask siblings do not currently have
(`enqueue_full_triplet` builds a causal chain, so row 3 attends to row 2) and a
more complex rollback. That is real work for, at best, a tie with a schedule
that already exists.

**Not implemented, deliberately.** Re-open it if the head's acceptance ever
drops far enough that the chain's marginal falls below a branch's -- the
probe is checked in, so re-deciding costs one run.

### Cross-row wide verify, and the fixture band applies to the BASELINE too (2026-08-18)

Two results, and the second one invalidates a target this document had been
chasing.

#### 1. The width-4/5 verify kernel had the pre-hoist defect

`nvfp4_matvec_mlx_scaled_batch.metal` (quad/quint) gives each SIMD group ONE
output row while issuing `BATCH*4` float4 activation loads against 2 u32 of
weight -- 256 bytes of activation per 8 bytes of weight at BATCH=4. That is the
same load/store issue-slot starvation the triplet hoist fixed, except a
one-output-row kernel has nothing to hoist across. It showed up as quad/quint
*regressing* against plain per-token qmv on mlp-down (0.96x and 0.77x).

`nvfp4_matvec_mlx_scaled_wide.metal` gives each SIMD group ROWS output rows and
loads the activations ONCE into registers shared across them, which is the shape
of MLX's `qmv_fast_crossrow_affine4_g64_wide`. Bakeoff on real weights,
`scripts/bench/autotune_qwen38_wide.w`, every candidate validated against the
production 8-row qmv first (`err=0` on all ten shapes, all widths):

| shape | quad -> best wide | quint -> best wide |
|---|---|---|
| mlp down | 293.0 -> 141.6 us (**2.07x**) | 454.7 -> 172.3 us (**2.64x**) |
| lm head | 2733 -> 1489 us (**1.84x**) | 3218 -> 1868 us (**1.72x**) |
| attention q | 143.1 -> 82.6 us (**1.73x**) | 168.1 -> 106.0 us (**1.59x**) |
| mlp gate | 200.3 -> 116.2 us (**1.72x**) | 235.7 -> 144.6 us (**1.63x**) |
| mtp fuse | 120.1 -> 75.5 us (1.59x) | 144.1 -> 96.4 us (1.49x) |

`b4_r1` -- same one-row-per-SIMD-group shape as quad, just written with register
arrays -- gains only ~1.12x. So the win is the activation sharing, not the
rewrite, which is the mechanism the change claims.

**The ROWS ladder is non-monotonic and shape-dependent, so it is swept.** r4
wins where the activation working set is large relative to the weight tile
(mlp-down K=17408: 1.21x r2 at width 3, 2.07x vs 1.76x at width 4) and *loses*
everywhere K=5120 (attention q 0.91x, attention k 0.76x at width 3). The shipped
split is r4 when `kdim == FFN`, r2 otherwise. This is the same hazard MLX hit
from the other side: it profiled M=9 as CHEAPER than M=8 (216 us vs 437 us)
because M=8's even 4+4 split needs two simultaneous four-wide accumulator sets.
Do not let a cost model prune this axis.

At width 3 the wide kernel is a smaller but repeatable win over the hoisted
triplet, measured end-to-end, alternating, 64-token prose, 32 generated:

| variant | tok/s | acceptance |
|---|---|---|
| `hoist` (previous `auto`) | 42.95 / 45.65 / 45.52 | 0.50 / 0.3125 |
| `b3` (r2 everywhere) | 46.51 / 46.38 / 46.11 | 0.50 / 0.3125 |
| `auto` (r4 for FFN, r2 else) | **46.99 / 46.99 / 46.72** | 0.50 / 0.3125 |

3/3 and 3/3. Acceptance is byte-identical across all nine runs, which is the null
check: these are pure kernel-speed changes and nothing behavioural moved.

#### 2. MTP-2 is the faster mode on prose, and Ollama's 64.99 was a chat prompt

`mtp` (depth 1) is documented above as the fast default. On the prose fixture it
is not: depth 2 wins by 15%, because it commits 2.0 tokens per round against
depth 1's 1.52 while the round costs only 43 ms against 38 ms.

| mode | round | tokens/round | tok/s |
|---|---|---|---|
| `mtp` (depth 1) | 38 ms | 1.52 | 37.96 |
| `mtp2` (depth 2) | 43 ms | 2.00 | 45.65 |

Combined with the wide kernel: **37.96 -> 46.99 tok/s, +23.8%**, greedy ids
byte-identical to the pre-change baseline throughout.

**The Ollama comparison recorded above is not matched material.** The 61-68
tok/s figure was measured through Ollama's *chat template*: a ~100-token passage
arrives as `prompt_eval_count=113` and the model writes an assistant *reply*
rather than continuing the prose. Replies are much more predictable -- Ollama's
own log reports `acceptance=0.79 avg_draft=2.80 max_draft=4` there. That is the
fixture-band lesson from the section above applied to the BASELINE instead of to
our own harness, and it had been sitting in this document as a 1.6x target that
does not exist.

Re-run with `"raw": true` on the exact 64-token prefix this bench uses, Ollama
emits the byte-identical continuation and its controller backs off to depth 1:

| runner | tok/s | forwards for 32 tok | tokens/forward | acceptance |
|---|---|---|---|---|
| Ollama MLX (`raw`, 64-tok prefix) | 44.81 / 46.93 / 44.99 | 20 | 1.60 | 0.71, avg_draft 0.85 |
| **Tungsten `mtp2` `auto`** | **46.99 / 46.99 / 46.72** | **16** | **2.00** | 0.50 |

Same model, same prompt, same emitted tokens, same box. Tungsten is ahead, and
extracts more tokens per target forward. Ollama's per-position acceptance on raw
prose is 0.52-0.71 -- **not** meaningfully better than ours, so there is no
head-quality gap to chase. The apparent one was entirely the chat template.

#### Why depth 3+ does not pay, quantified

Component profile (`ARGV[4] = "profile"`, mtp2, 64-token prose):

```
verify=365 ms/10 rounds   -> 36.5 ms per 3-row verify
draft=65 ms/21            -> 3.10 ms per MTP head step
history=27 ms/76          -> 0.36 ms
hidden-copy=4 ms/23, rollback=0 ms/6
```

With `verify(W) = 29 + 3W` (row-scan: 32/35/38 ms at W=1/2/3) and a 3.05 ms head
step, `round(d) = 32 + 6.05d`. At the measured chain (p1 = 0.6875,
p2|1 = 0.4545):

| depth | round | E[tokens] | ms/token |
|---|---|---|---|
| 1 | 38.1 ms | 1.687 | 22.6 |
| 2 | 44.1 ms | 2.000 | **22.1** |
| 3 | 50.2 ms | 2.141 | 23.4 |
| 4 | 56.2 ms | 2.204 | 25.5 |

Depth 2 is the optimum and depth 3 loses, because the head step costs as much as
a verify row while buying a rapidly decaying probability. Even with a *free*
head step the ceiling is ~52 tok/s at this acceptance. The wide kernel is
therefore banked for when the head step gets cheap or acceptance rises -- it
removes the kernel objection to depth 3/4, which is not the binding one.

Two hypotheses were killed by measurement and are recorded so they are not
retried:

- **Pre-norm hidden for the MTP head.** The head takes `xn` (post-final-norm)
  where the mlx-swift-lm reference is explicit that `pre_fc_norm_hidden` expects
  the raw backbone output and "passing post-norm would double-normalize".
  Changing it moved acceptance by exactly zero, byte-for-byte, because
  `RMSNorm(c*v) == RMSNorm(v)` for positive scalar c -- the head's own norm
  cancels the backbone norm's scaling, and `final_norm` is stored as a small
  delta from one, so what remains is a negligible elementwise reweighting. The
  change is kept because it matches the reference contract and costs nothing,
  but it is not a speedup.
- **The draft step is GPU->CPU sync latency.** It is not. Skipping the readback
  entirely (output invalid, timing only) moved the head step 3.10 -> 2.72 ms.
  The remaining ~2.7 ms is real GPU work in many small dispatches that never
  saturate bandwidth.

### The draft selector was the old single-simdgroup argmax (2026-08-18)

`mtp_compact_draft_select` scans the 98,304-row draft vocabulary with ONE
32-thread simdgroup, and scans it TWICE -- once for the maximum, once to recover
its index. That is precisely the pattern this repo already replaced for the
full-vocabulary argmax (measured 1,648 us -> 3.92 us by switching to 1024-logit
tiles); it was simply never applied to the draft path.

`mtp_draft_select_fast.metal` does the same reduction in two tiled stages,
preserving the tie-break exactly: the two logit buffers are treated as one
logical index space, and because every control id (>= 248,044) exceeds every
prefix id (< 98,304), lowest-id ordering agrees with logical index order, so a
single (value, id) reduction reproduces the original answer.

| | head step (`draft=`) | verify |
|---|---|---|
| single-simdgroup select | 3.14 ms | 36.9 ms |
| tiled select | **1.95 ms** | 36.6 ms |

**-38% on the head step**, verify unchanged as expected. End to end, alternating,
64-token prose, 32 generated:

| variant | tok/s | acceptance |
|---|---|---|
| `slowsel` | 46.85 / 46.58 / 45.85 | 0.50 / 0.3125 |
| `auto` (tiled) | **49.31 / 48.05 / 46.72** | 0.50 / 0.3125 |

3/3, ids and acceptance byte-identical.

**Why the head step is the number that matters.** It is what caps draft depth.
With the row-scan now measuring 32 / 35 / 37 ms at widths 1/2/3 (the wide kernel
took the third row's marginal from 3 ms to 2 ms) and a 1.95 ms head step,
`round(d) = verify(d+1) + 1.95d`. On the expository fixture
(p1 = 0.714, p2|1 = 0.75):

| depth | round | E[tokens] | ms/token | tok/s |
|---|---|---|---|---|
| 2 (shipped) | 40.9 ms | 2.25 | 18.2 | 55.0 (measured 54.0-54.5) |
| 3 | 44.9 ms | 2.63 | 17.1 | **58.5** |
| 4 | 48.8 ms | 2.89 | 16.9 | **59.2** |

Depth 3-4 now pays. It did not before: at a 3.05 ms head step and the literary
fixture's p2|1 = 0.45 the same arithmetic said depth 3 loses, which is why this
document previously recorded depth 2 as optimal. **Both inputs moved, so the
conclusion moved.** Reaching depth 3 requires width-4 versions of the nine
`decode_triplet.metal` kernels plus an N-slot recurrent-state snapshot for
rollback; the QMV half is already done and validated
(`nvfp4_matvec_mlx_scaled_wide.metal`).

### Material sets the acceptance band; two more hypotheses died

Acceptance is a property of the text, not of the context length:

| fixture | 64 tok | 256 tok | 512 tok |
|---|---|---|---|
| literary prose | 0.484 | 0.370 | 0.550 |
| expository prose (`prose-tech`) | 0.636 | 0.614 | - |

An earlier sweep appeared to show acceptance climbing to 0.796 at 512 tokens.
That was the tiling artifact: `profile_prompt_tokens` beyond the passage length
wrapped the prompt, and the model said so in its own output ("The text you
provided is a single paragraph repeated five times"). The passage is now long
enough for 512 and the runner **prints a warning** rather than silently tiling.

- **Resource-scoped barriers.** `dependency_barrier` is
  `memoryBarrierWithScope:MTLBarrierScopeBuffers`, ~620 per width-3 verify, and
  Apple documents `memoryBarrierWithResources` as cheaper. Converting the FFN
  chain (256 of them) moved the median round not at all: 42 ms in all four
  alternating runs. Kept, because it is the more precise API and costs nothing,
  but it is **not** a speedup, and the verify is simply bandwidth-bound
  (14.69 GB / 36.6 ms = 402 GB/s against a serial forward's 432 GB/s).
- **Longer context raises acceptance.** See the table above: it does not.

### Where tungsten stands against Ollama, on matched material

Ollama driven with `"raw": true` on the exact 64-token prefix, byte-identical
continuations, same box:

| fixture | Ollama | tungsten `mtp2` | winner |
|---|---|---|---|
| literary | 44.81 / 46.93 / 44.99 | **49.31 / 48.05 / 46.72** | tungsten +6.8% |
| expository | 51.91 / **61.22** / 61.40 | 53.96 / 53.96 / 54.47 | Ollama +13.5% |

Ollama's stats explain the split. On literary prose its controller backs off to
depth 1 (`avg_draft=0.85`) and it loses. On expository prose it runs
`avg_draft=2.72 max_draft=4` and emits 2.56 tokens per target forward against
our 2.21 -- with *lower* per-position acceptance (0.57 vs 0.636). It wins on
schedule depth, not on head quality. Its round is ~41.8 ms for ~3.7 verify rows
plus 2.72 head steps, which implies a head step near 0.3 ms; ours is 1.95 ms
after the fix above. Depth, and the head-step cost that gates it, is the whole
remaining gap.

### Depth 3 is built, parity-clean, and does not pay (2026-08-18)

`mtp3` drafts three tokens and verifies FOUR target rows in one causal pass.
It exists: `decode_quad.metal` (nine kernels, the conv and gated-delta ones
carrying a third interior recurrent-state snapshot so rollback can select any
accepted prefix), width-4 wide QMV, `rollback_quad_states`, and a four-way
accept walk. It emits **byte-identical greedy ids** to `mtp2` and to the
pre-change baseline over a full 32-token run exercising all four accept paths.

It is not the default, because it ties or loses:

| fixture | `mtp2` | `mtp3` | tokens/round (2 -> 3) |
|---|---|---|---|
| expository | 53.16 tok/s | 53.20 tok/s | 2.21 -> 2.67 |
| literary | 48.63 | 40.76 | 2.00 -> 2.00 |

On expository prose depth 3 buys exactly the extra tokens the cost model
predicted (+21%, E = 2.63 predicted vs 2.67 measured) and the round costs +24%,
so it is a wash. On literary prose the chain decays too fast to buy anything.

**Why the model was wrong, and the lesson.** The in-situ row ladder is

```
width   1     2     3     4
       32    35    37    45   ms      (marginal +3, +2, +8)
```

I extrapolated +2 ms for the fourth row from the 2nd and 3rd. The real marginal
is +8 ms. Rows 2 and 3 are nearly free because the verify is bandwidth-bound and
the weight stream is read once regardless; by width 4 the FMA count per byte has
risen enough that the kernel is compute-bound, and further rows cost roughly in
proportion. Confirmed in the bakeoff: attention q is 62.6 us at b3_r2 and
81.9 us at b4_r2, +31% for +33% work.

The row-count ladder was then swept rather than reasoned about -- b4_r1 / r2 /
r3 / r4 -- and `r2` is simply best; there is no favourable odd split hiding at
width 4 the way MLX found one at M=8. **This is the same "sweep, do not
extrapolate" rule that produced the width-3 win, applied one step too late.**
The measurement corrected the estimate; the estimate was what justified the
port.

`mtp3` is kept because it is correct, it is the scaffold for any wider schedule,
and it will pay the moment either the width-4 QMV gets ~20% faster or the head's
per-position acceptance rises. Neither is available today.

**What would actually close the remaining gap.** Against Ollama on matched raw
material tungsten now wins the literary fixture (49.5 vs 45.0) and loses the
expository one (54.9 vs 61.2). Ollama's advantage there is depth-4 drafting at
`avg_draft=2.72`, which it can afford because its head step is ~0.3 ms against
our 1.95 ms. The head step, not the schedule and not the verify kernel, is the
binding constraint: ours is ~508 MB of weights (draft projection 252 MB, MTP
layer 227 MB) which is ~1.2 ms at the 432 GB/s this box sustains. Halving the
draft projection with a coarse-then-exact readout (2-bit shortlist, exact
rerank of the top 32 -- the trick the MLX board's declared heads use) is worth
~0.3 ms of that; the rest needs the head's FFN to shrink or to overlap the
verify.

### A simdgroup-matrix GEMM is exact and 4-10x slower

The reason depth 3 ties is that the multi-row GEMV turns compute-bound at width
4. MLX dispatches a GEMM for multi-row, so the obvious next move was an MMA
kernel: `nvfp4_matvec_mlx_mma.metal`, one simdgroup owning an 8(N) x 8(M)
accumulator, walking K in 32-wide blocks, decoding one u32 of packed weights per
lane and staging A and B through threadgroup memory.

It validates -- err 1e-6 against the production single-row qmv, so the shape and
the scale folding are right -- and it loses badly:

| shape | wide GEMV (b4_r2) | MMA (b4) |
|---|---|---|
| linear qkv | 68.5 us | 261.0 us |
| attention q | 81.2 us | 316.9 us |
| attention k | 12.8 us | 133.4 us |
| mlp down | 45.7 us | 203.0 us |

The cause is occupancy, not the MMA units. One simdgroup per 8 output rows
launches a quarter of the threads the GEMV does (32 threads per 8 rows against
64 per 4), so far fewer weight loads stay in flight -- and this problem is
bandwidth-bound, where latency hiding is the entire game. Staging A through
threadgroup memory each 32-k block makes it worse. This reproduces the earlier
finding in this document that an 8-row simdgroup-matrix kernel was "exact but
slower", and explains it.

**Conclusion for the kernel axis: it is closed.** The multi-row GEMV sits on the
bandwidth floor through width 3 (14.69 GB / 37 ms = 397 GB/s against a serial
forward's 459 GB/s on the same bytes), the nibble decode is free (no-decode
ablation within 0.3-4%), no row split beats r2 at width 4, and a GEMM is worse.
What remains is the head step and the schedule.

### Attribution

The fixture change above came out of the public solver notes on the Yukon
`eigenlabs/qwen38-challenge` MLX-Fast leaderboard, which runs the same model
under a bit-exactness contract. Credit where it is due:

- **samcm** — established that a fixture's *acceptance band* decides whether
  any draft-schedule measurement has a sign, that a saturated fixture
  "cannot discriminate any schedule change at all", and that free-form prose
  and repeated-frame material land in different bands. That is the finding
  this section applies.
- **Lieisyourlie** — persistent committed MTP-head history, the single
  largest algorithmic jump on that board (+20.4%). Tungsten's
  `enqueue_mtp_history` is the same idea, arrived at independently.
- **scarletbright** — cheap K=1 rollback: speculation only pays once
  rejection costs less than the work it saves.
- **mega-dmitriy** — replacing eager per-boundary recurrent checkpoints with
  a compact replay tape.
- **hadakang** — cracking the verify width wall by chunking wide verifies,
  and the sizing note on what a trained draft head actually costs.
- **polymorf** — the cost-model depth policy (per-position acceptance EMAs
  plus a greedy marginal rule) that Tungsten's adaptive `mtp-auto` mirrors.
- **newjordan, audreyt, vibecodooor, tanishq-dubey, noskillcoding,
  DawgZter** — the schedule-constant and declared-head work that showed how
  much of the remaining margin lives in calibration rather than kernels.
- **jasonjmcghee** — the correct statement of that benchmark's
  serial-denominator contract, which is why shared-path wins are measured
  differently there than here (Tungsten reports absolute tok/s, so every
  shared-path win counts in full — a simpler situation).
- **androolloyd, EternaPeptix** — identifying seed prefill as a large,
  largely untouched cost pool inside the timed window.
- **Claude Opus 5 (multiple accounts)** — falsifying the register-cliff
  theory for multi-row QMV by direct measurement, which is why the row-split
  variants here were not re-litigated.

### K/V cache overflow now fails loudly

`MAX_POS` is 128 and the caches are fixed at that size. Exceeding it did not
fault: it wrapped silently and the model emitted fluent-looking multilingual
garbage while still reporting a plausible 22.97 tok/s and an acceptance
figure. A 256-token prompt reproduced this. The runner now refuses
`prompt + generate > MAX_POS` before loading weights — a benchmark that lies
quietly is worse than one that stops.

## Model-specific details

- Newer Ollama NVFP4 tensors use packed U32 weights, E4M3 group scales, and a
  separate f32 `global_scale`. The scaled kernels cover plain, residual, and
  fused gate/up matvecs. They decode nibbles and scales in registers on every
  matvec; no expanded f16 weight matrix is materialized.
- Outer RMSNorm and q/k norm parameters are stored as deltas from one when MTP
  weights are present; GatedDeltaNet's inner norm is not shifted.
- The runner uses the dedicated `kv_write` kernel. `copy_f32_slice` offsets its
  source and must not be used to append cache rows.
- `MAX_POS` is 128 in the benchmark runner. The checkpoint supports 262144;
  production serving needs a dynamically sized cache and a long-context SDPA
  path.
