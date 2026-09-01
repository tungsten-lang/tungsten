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
| 23. GPU sampling | Deferred | The benchmark's promoted path is greedy GPU argmax.  Sampled generation reads all logits on the CPU, while the shipping server also applies repetition and no-repeat policy before sampling.  There is no fixed-seed sampled whole-model parity fixture.  Moving only multinomial selection would not preserve server semantics; moving policy requires a device-side token-history/ban representation and a fixed RNG oracle first. |
| 24. Continuous batching / MoE grouping | Deferred | The service owns one module-global activation/KV state and processes stdin requests serially.  Qwen3.8's width-2..8 kernels are speculative rows from one sequence, not independent request states.  Continuous batching requires per-request KV, convolution, gated-delta, PLE, position, and RNG state plus a scheduler.  Expert grouping cannot pay or be validated until such a multi-request harness exists. |
| 25. Reusable Metal plans | Rejected | A native prevalidated plan executor passed a focused linear/barrier/scalar/3-D dispatch smoke, but the five-token FlashNext fixture returned token 220 instead of 11751.  A later control command buffer remained in the GPU driver until killed.  All code was reverted.  Immutable host plans are still plausible, but the next tranche needs per-step differential taps and lifecycle/error handling before a whole-model attempt. |
| 26. Tiled long-context SDPA | Deferred | The current HD256 kernel is exact only through 640 positions and stores the score row in threadgroup memory.  Both active Qwen3.8 runners cap KV at 640; FlashNext is also in QSA's dense-exact region below 2051 and has no sparse indexer wired.  A tiled online-softmax kernel has no in-scope long-context model oracle, and at the scored <=640 shape it would add dispatch/reduction overhead. |
| 27. Mamba fusion | Already present in FlashNext; Qwen3.8 port rejected | FlashNext already fuses conv+split and `g`+beta.  Porting the same kernels to Qwen3.8 preserved every ID through 128 generated tokens.  Whole-model timing changed sign: 261 vs 269 ms at 8 tokens, 1108 vs 1088 at 32, 2268 vs 2332 at 64, and a thermally throttled 128-token ABBA favored fusion by 2.4%.  The inconsistent end-to-end result fails the promotion gate, so the port was reverted. |
| 28. Bulk FlashNext PLE gather | Retained: `d61c20d6` | One checked native call now gathers all 16 FP8 rows instead of 16 bridge calls.  Exact hidden/logit/debug dumps and generated IDs match the scalar path.  The 10,000-gather micro improved from 286/287/288 ms to 9/8/8 ms (31-36x); loaded-box short decode won both matched pairs. |
| 29. Persistent prefill graph | Deferred | Qwen3.6's fixed prefill already encodes all 48 layers and the head into one concurrent command buffer.  Metal command buffers are one-shot.  Tungsten's Metal 4 API is currently an all-in-one, synchronous, one-dispatch call that creates a command buffer, residency set, and event each time.  A persistent graph therefore first needs a batched MTL4 API or a correct immutable-plan executor; item 25 showed that the latter is not ready. |
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

The smoke passed exact finite E4M3 decoding.  Three 10,000-call samples for
16x160 rows were scalar 286/287/288 ms and bulk 9/8/8 ms.

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
