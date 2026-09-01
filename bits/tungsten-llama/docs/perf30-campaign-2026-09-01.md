# Llama perf30 campaign: items 23-30

Date: 2026-09-01

Baseline: `43642a9d`.  Worktree: `codex/perf30-llama`.  GPU runs used
`scripts/bench/perf_lock.sh`.  A change was eligible to remain only after an
exact output gate and a matched whole-model win.  The machine was under
unrelated CPU load, and the long Qwen3.8 sequence eventually throttled from
about 28 to 12.7 tokens/s, so sign-changing whole-model results were rejected.

## Result table

| Item | Result | Evidence and decision |
|---|---|---|
| 23. GPU sampling | Measured win; not retained | At `V=151936`, `K=40`, `T=0.7`, seed 1234567, a deliberately serial one-thread GPU top-k/softmax sampler chose the same token (145042) as the shipping CPU sampler.  Three process runs were 90/93/95 ms per CPU call versus 11/11/12 ms GPU wall and 9.72/9.83/10.26 ms device time (7-8x wall speedup).  It was not promoted because the server's real path also applies repetition penalties and no-repeat bans; moving only selection changes semantics. |
| 24. Continuous batching / MoE grouping | Existing kernels cross over at batch 2; scheduler deferred | A production-shape synthetic MoE (`2048 -> 768 -> 2048`, 128 experts, top-8) compared sequential request command buffers with the existing width-specialized batch kernels at B=1/2/4/8.  Every output matched exactly.  B=1 was noise; from B=2 onward batching reduced host wall time in every run.  At B=8 it was 2.94-3.79x faster for shared experts and 2.58-2.91x for disjoint experts, with 1.20-1.38x and 1.09-1.17x GPU-time wins respectively.  No runtime change remains because the service still has one module-global model state and a serial request loop; safe continuous batching needs per-request recurrent/KV/RNG state and scheduling. |
| 25. Reusable Metal plans | Rejected | A native prevalidated plan executor passed a focused linear/barrier/scalar/3-D dispatch smoke, but the five-token FlashNext fixture returned token 220 instead of 11751.  A later control command buffer remained in the GPU driver until killed.  All code was reverted.  Immutable host plans are still plausible, but the next tranche needs per-step differential taps and lifecycle/error handling before a whole-model attempt. |
| 26. Tiled long-context SDPA | Rejected | A tile-64 online-softmax HD256 kernel passed a synthetic parity oracle at 32/128/320/640 positions with maximum absolute error no larger than `6.76e-9`.  Its GPU micro was neutral to about 5% faster, but a 638-token full Qwen3.8 ABBA produced identical IDs and regressed median warm prefill from 26,218 to 26,790 ms (+2.18%); decode was also neutral/slightly worse.  The candidate was removed. |
| 27. Mamba fusion | Already present in FlashNext; Qwen3.8 port rejected | FlashNext already fuses conv+split and `g`+beta.  Porting the same kernels to Qwen3.8 preserved every ID through 128 generated tokens.  Whole-model timing changed sign: 261 vs 269 ms at 8 tokens, 1108 vs 1088 at 32, 2268 vs 2332 at 64, and a thermally throttled 128-token ABBA favored fusion by 2.4%.  The inconsistent end-to-end result fails the promotion gate, so the port was reverted. |
| 28. Bulk FlashNext PLE gather | Retained: `d61c20d6` | One checked native call now gathers all 16 FP8 rows instead of 16 bridge calls. Exact hidden/logit/debug dumps and generated IDs match the scalar path. The original 10,000-gather micro improved from 286/287/288 ms to 9/8/8 ms (31-36x); loaded-box short decode won both matched pairs. A final audit-tree decoder correction passed all 256 FP8 bytes and retained 36x/26x/32x throughput in three runs; that follow-up remains distinct from the committed item-28 implementation until the audit fixes commit. |
| 29. Persistent prefill graph | Measured proxy; no production change | A parity-checked 48-stage dependent graph measured one command buffer at 0.245/0.295 ms wall, four command buffers at 0.670/0.690 ms (2.34-2.73x slower), and 48 command buffers at 7.10/7.10 ms (24.1-29.0x slower).  The optimized Qwen3 fixed prefill and Qwen3.8/FlashNext target paths already use the winning one-command-buffer shape.  The older Qwen3.6 verifier is fragmented by CPU router readback and per-expert submissions, so it cannot become a persistent graph without first changing those semantics.  Metal command buffers are one-shot; item 25's reusable-plan attempt failed whole-model parity. |
| 30. Fused router/top-k | Rejected | The existing fused kernel was adapted to packed outputs and passed exact top-8 ID and weight parity.  On a 48-layer micro it took 11.5785 ms versus 3.5404 ms separate (0.306x).  One 1024-thread group serializes four router rows per SIMD group and loses the 128-group matvec occupancy; eliminating one dispatch cannot repay that loss.  All code was reverted. |

## Already-landed prerequisites

### Tokenizer (`43642a9d`)

The original commit records exact agreement with Hugging Face `tokenizers` on
2,842 multilingual strings (66,366 tokens).  That corpus harness was not
tracked, and the current Python environment has no `tokenizers` package, so
the large corpus could not be rerun from the checkout.  The stale tracked
smoke/throughput fixtures were repaired in `3a18e77e` to use the same packed
Qwen tokenizer as the current runners.  Current evidence:

- known tokens decode as `Hello`, `What`, `Paris`, and `?`;
- all four encode/decode round trips pass, including the engine fixture
  `The capital is Paris -> [760, 6511, 369, 11751]`;
- the prose benchmark reports round-trip `OK`, 2.18 MB/s and about 396k
  tokens/s on the loaded development host.

Commands:

```sh
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile --release \
  --out /tmp/perf30_tokenizer_smoke scripts/bench/tokenizer_smoke.w
/tmp/perf30_tokenizer_smoke

TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile --release \
  --out /tmp/perf30_tokenizer_bench scripts/bench/tokenizer_bench.w
/tmp/perf30_tokenizer_bench
```

### W-level prebuilt dispatch programs (`d07c4f3f`)

The landed commit records identical IDs and neutral encode time versus the old
per-call construction path; its conclusion is that bridge crossings, not W
array construction, dominate.  This campaign's default prebuilt path retained
the exact eight-token FlashNext sequence
`[11751, 13, 271, 57590, 369, 279, 6511, 314]` while validating item 28.

An attempted `FN_PREBUILT=0` reproduction of the old path did not finish its
first command buffer and had to be killed after more than two minutes in the
GPU driver.  The temporary switch was removed.  Consequently, the prior
commit is the timing authority; current evidence verifies the promoted path,
not a fresh healthy old-path comparison.

## Retained item 28 evidence

Focused smoke and microbenchmark:

```sh
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile --release \
  --out /tmp/perf30_metal_fp8_gather_smoke \
  scripts/bench/metal_fp8_gather_smoke.w
/tmp/perf30_metal_fp8_gather_smoke

TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile --release \
  --out /tmp/perf30_metal_fp8_gather_bench \
  scripts/bench/metal_fp8_gather_bench.w
/tmp/perf30_metal_fp8_gather_bench
```

The original smoke passed its finite E4M3 sample. Three 10,000-call samples for
16x160 rows were scalar 286/287/288 ms and bulk 9/8/8 ms.

The integration audit subsequently found that the committed bulk helper
decoded the two FlashNext/NVFP4 sentinel bytes differently from the canonical
kernel. The audit-tree correction maps `0x7f` and `0xff` to zero; an exhaustive
smoke passed exact parity for all 256 byte encodings. Three final 10,000-call
runs with that corrected decoder measured scalar/bulk 291/8 ms (36x), 290/11
ms (26x), and 290/9 ms (32x). These are live audit-tree results, not evidence
that the correction is already contained in commit `d61c20d6`.

Five-token scalar and bulk golden dumps compared byte-for-byte:

| Dump | SHA-256 |
|---|---|
| hidden | `d896ee5e...` |
| logits | `f202e990...` |
| debug taps | `ae86103b...` |

Both paths predicted token 11751 (` Paris`).  A loaded-box eight-token ABBA
used the same binary and `FN_QUANT=1 FN_TIME=1`:

| Run | Path | IDs | Host rope+PLE | Host encode | Tail | Decode |
|---|---|---|---:|---:|---:|---:|
| A1 | scalar | exact reference | 2.286 ms | 16.429 ms | 8.143 ms | 37.23 tok/s, 27 ms median |
| B1 | bulk | exact reference | 0.429 ms | 16.000 ms | 8.000 ms | 40.94 tok/s, 24 ms median |
| B2 | bulk | exact reference | 0.286 ms | 16.143 ms | 8.000 ms | 40.94 tok/s, 24 ms median |
| A2 | scalar | exact reference | 0.571 ms | 16.143 ms | 8.000 ms | 40.46 tok/s, 25 ms median |

The host micro is the clean attribution evidence; the whole-model numbers are
directional because the box was loaded.

## Losing-experiment details

### 23. GPU sampling

The temporary oracle used the production vocabulary and top-k shapes
(`151936`, `40`), temperature 0.7, and seed 1234567.  It filled one shared
Metal logits buffer deterministically, let `Sampler#sample` consume it, then
passed the same first xorshift uniform variate to a Metal implementation of
stable top-k insertion, softmax, and cumulative selection.  Both selected
token 145042.  Three fresh process samples:

| Run | CPU | GPU wall | GPU device | Wall speedup |
|---:|---:|---:|---:|---:|
| 1 | 93 ms | 12 ms | 10.263 ms | 7x |
| 2 | 95 ms | 11 ms | 9.826 ms | 8x |
| 3 | 90 ms | 11 ms | 9.716 ms | 8x |

Even a one-thread GPU implementation clears the bridge-heavy CPU loop, so a
parallel vocabulary reduction is a strong future tranche.  The production
gate is wider than this sampler oracle: `llama.w` builds a recent-token set,
applies a sign-sensitive 1.18 repetition penalty, excludes no-repeat 5-gram
continuations, and then advances its xorshift state.  A retained kernel must
take compact device-side penalty/ban inputs and reproduce that ordering and
RNG transition exactly.  The subcomponent harness was removed with the
unpromoted kernel.

### 24. Continuous batching / MoE grouping

The temporary harness used the existing single-row and batch function-
constant Q8 kernels at the production Qwen3 MoE shape: hidden 2048, expert FFN
768, 128 experts, top-8, and B=1/2/4/8.  It ran gate+up, SiLU, and down with
deterministic synthetic Q8 weights.  The control submitted one full MoE
command buffer per request; the candidate submitted one width-B buffer.  It
tested both complete expert overlap across requests and disjoint expert IDs.
All compared outputs had `max_abs=0`.

Across three fresh process runs, B=1 had no stable sign.  The useful
crossovers were:

| Pattern | B | Host wall speedup range | GPU-time speedup range |
|---|---:|---:|---:|
| shared experts | 2 | 1.22-3.20x | 1.10-1.21x |
| shared experts | 4 | 2.70-3.50x | 1.18-1.24x |
| shared experts | 8 | 2.94-3.79x | 1.20-1.38x |
| disjoint experts | 2 | 1.36-1.50x | 1.03-1.06x |
| disjoint experts | 4 | 2.00-2.21x | 1.07-1.12x |
| disjoint experts | 8 | 2.58-2.91x | 1.09-1.17x |

This validates the existing grouped kernel machinery and places the crossover
at two live requests on this host.  It does not validate a scheduler.  The
shipping service owns one set of module-global activations/KV buffers and its
stdin loop completes one request before reading the next.  Qwen3.8's width
kernels are speculative rows of one sequence and cannot stand in for
independent KV, convolution, gated-delta, PLE, position, and RNG state.  The
synthetic harness was removed; no production semantics changed.

### 26. Tiled long-context SDPA

The candidate replaced the 640-float score row with 64-position tiles and an
online `(max, denominator, output)` update in the existing 256-thread-per-head
HD256 structure.  Against the shipping kernel, maximum absolute output error
was `6.76e-9`, `3.96e-9`, `2.57e-9`, and `1.47e-9` at 32, 128, 320, and 640
positions.  Three 120-pair GPU samples gave candidate/control ratios:

| Positions | Candidate/control GPU-time ratio |
|---:|---:|
| 32 | 1.023 / 0.915 / 0.974 |
| 128 | 0.948 / 0.961 / 0.964 |
| 320 | 0.967 / 0.970 / 0.951 |
| 640 | 0.959 / 0.951 / 0.978 |

The micro result was promising but too small to promote.  A same-binary ABBA
then ran Qwen3.8 with a 638-token prompt and two decode tokens.  Every path
emitted `[279, 9605, 1056]`.  Excluding each process's first weight-touch
prefill, control took 25,731/26,705 ms and tiled took 27,374/26,206 ms: median
26,218 versus 26,790 ms, a 2.18% full-model regression.  Decode was 94/96 ms
control and 99/94 ms tiled.  The kernel and switch were removed.

### 29. Persistent prefill graph

The closest executable graph-overhead oracle chained 48 dependent Metal
kernels and verified the final state was 48 under every submission scheme.
Two fresh process runs measured:

| Submission shape | Wall ms/graph | Relative to one CB |
|---|---:|---:|
| one concurrent command buffer | 0.245 / 0.295 | 1.0x |
| four command buffers | 0.670 / 0.690 | 2.34-2.73x slower |
| one command buffer per stage | 7.10 / 7.10 | 24.1-29.0x slower |

This is direct evidence for the scheduling property that matters.  The
optimized Qwen3 fixed prefill already encodes all 48 layers and the output head
into one concurrent command buffer, while Qwen3.8 and FlashNext likewise keep
a target pass in one command buffer.  The older Qwen3.6 verifier is different:
it reads router top-k on the host at every layer and launches eight expert
command buffers, so those semantic synchronization points must first move to
the device/batch kernels before one graph is possible.  Reusing a committed
Metal command buffer is not supported; reducing the remaining host encoding
needs a correct immutable plan or batched Metal 4 API.  The plan prototype in
item 25 failed exact whole-model parity, so no graph code was retained.  The
proxy harness was removed after measurement.

### Native Metal plans

The prototype snapshotted pipelines, buffers, binding offsets, scalar boxes,
barrier resources, and 1-D/3-D geometry once, then encoded a layer with one
bridge call.  The isolated smoke covered linear dispatch, resource barriers,
scalar arguments, and `(2,2,2)x(2,2,1)` 3-D dispatch and passed.  The complete
FlashNext graph did not: its five-token first prediction was 220 rather than
11751, despite correct-looking step counts and geometry.  No part of the
prototype remains in the tree.

### Qwen3.8 GDN fusion

The experiment reused the already-shipped FlashNext `gdn_conv_split` and
`gdn_g_beta` kernels, guarded by a same-binary environment switch.  Control
and candidate produced the same 128-token sequence.  Short matched runs were
not stable enough to promote:

| Generated tokens | Control | Fused | Winner |
|---:|---:|---:|---|
| 8 | 261 ms | 269 ms | control |
| 32 | 1108 ms | 1088 ms | fused |
| 64 | 2268 ms | 2332 ms | control |
| 128 ABBA, throttled | 10009/10544 ms | 9963/10100 ms | fused, but invalid for promotion |

### Router/top-k fusion

The parity smoke used the production shapes (`hidden=2048`, `experts=128`,
top-8) and the same f32 reduction/top-k order as the separate kernels.  IDs
and weights matched exactly.  Timing 48 router layers in one command buffer:

```text
separate: 3.5403749789 ms
fused:   11.5784999798 ms
ratio:    0.3057714717x
```

This rules out the current one-threadgroup design.  A future fusion would
need an inter-threadgroup reduction/continuation mechanism that preserves the
router matvec's row occupancy; that is a different algorithm, not a tuning of
this kernel.
