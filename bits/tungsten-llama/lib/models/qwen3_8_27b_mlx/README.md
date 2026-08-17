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
