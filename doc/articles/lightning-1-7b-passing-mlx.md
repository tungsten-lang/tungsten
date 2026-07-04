# From 0.71× to 1.16× MLX — Passing MLX on Lightning-1.7B Decode

The story of pushing Tungsten's pure-Tungsten Lightning-1.7B nvfp4 decode
from **146 tok/s (0.71× MLX)** to **240 tok/s (1.16× MLX)** in one
session, and what we learned along the way about Apple GPU performance
that's genuinely non-obvious.

The model is `bradyclarke/Lightning-1.7B-mlx-nvfp4` — a Qwen3-architecture
1.7B parameter model with NVIDIA-style 4-bit packed weights (E2M1 with
group_size=16 and E4M3 fp8 scales). Pure-Tungsten inference. M3 Max,
Apple Silicon. MLX baseline measured via `mlx_lm.benchmark` sustained:
207 tok/s decode, 4.83 ms/token GPU.

Starting point: every kernel hand-tuned, matvec at MLX parity per-call,
fused SDPA online softmax, bf16 KV cache. We had been "kernel-optimized"
for many rounds. The remaining gap to MLX was 30%.

Then we ran Frame Capture for the first time, and discovered the
bottleneck was a kernel nobody had ever measured.

## The performance ladder

```
                                       decode tok/s    GPU µs/token   MLX ratio
                                       ────────────    ────────────   ─────────
Session start                          146.4           6527           0.71×
+ Q/K/V + gate/up matvec fusion        146.6           6452           0.71×
+ argmax fixed (TG=32 → TG=1024)       183.3           5199           0.89×
+ rms_norm fixed (TG=32 → TG=512)      231.1           3938           1.12×
+ @gpu language extension              238.5           3772           1.15×
+ autotune-confirmed final settings    239.5 (mean)    3733           1.16×
```

Every rung came from peeling off one specific cost the previous version
was paying. Each is small in isolation; the total is a 64% improvement
in decode tok/s.

## Rung 0: The state we walked in with

After many earlier optimization rounds (hand-rolled `nvfp4_matvec_mlx`,
ported MLX `sdpa_vector` for fused attention, bf16 KV cache, zero-copy
mmap weight load, scalar-arg autobox), we had:

- 146.4 tok/s decode, 6527 µs/token GPU
- 95.6% GPU-bound — encode = 218 µs, GPU = 6527 µs, only ~300 µs of
  CPU-side slack
- Per-call matvec time **identical to MLX** (192 µs/call for both
  `mlx_quantized_matmul` and our `nvfp4_matvec` at K=N=2048, batch=1,
  verified through an mlx-c bridge)

The puzzle: if per-call matvec is at MLX parity, where is MLX gaining
30% on aggregate? Our intuition pointed at memory bandwidth (we measured
~31% of M3 Max DRAM peak; MLX is ~42%).

We tried two speculative kernel rewrites without instrumentation:

**Rung -1 (rejected): Per-row interleaved nvfp4 layout.** Hypothesis:
splitting quants and scales into two separate buffers creates two
competing DRAM streams that defeat the prefetcher; packing them
interleaved as `[1B scale | 8B quants]` per group should consolidate
into one stream. Built the repack kernel + 9-byte stride matvec
variant. **Result: perf-neutral.** Apple Silicon's DRAM controller
handles 8+ concurrent streams cleanly; the per-row scale-byte stream
is small enough (1B per 16 weights = 6% of weight BW) that the
controller already amortizes it efficiently. MLX, we eventually
confirmed, uses the same separate-buffer layout we had.

**Rung +0 (kept, small): Q/K/V and gate/up dispatch fusion.**
Combined three Q/K/V matvecs into one dispatch (TG_id picks which
weight matrix and output buffer to use); same for gate/up. **Result:
+0.1% tok/s, -75 µs GPU/token.** The dispatch-overhead saving was real
but small. Critically, this told us **Apple GPU per-dispatch overhead
is ~0.9 µs**, not the ~5 µs commonly quoted for x86-style GPUs:
84 saved dispatches × 0.9 µs ≈ 75 µs measured saving. Implication:
**kernel-fusion-for-launch-overhead is not a productive optimization
vector on Apple Silicon. Real costs live inside kernels.**

That left us still at 0.71× MLX with no clear path forward. Time to
get actual data.

## Rung 1: Frame Capture reveals the bug

We added programmatic Metal capture to the Tungsten runtime
(`runtime/metal.m:w_metal_capture_begin/end`, `MTLCaptureManager`
shared instance, `MTLCaptureDestinationGPUTraceDocument`). The bench
brackets one decode token in capture, gated on a `CAPTURE_TRACE=1`
env var so it's free when not in use:

```bash
CAPTURE_TRACE=1 METAL_CAPTURE_ENABLED=1 scripts/bench/bench_lightning.wc
open /tmp/bench_lightning.gputrace
```

Apple gates `MTLCaptureManager.startCaptureWithDescriptor:` on the
`METAL_CAPTURE_ENABLED=1` env var when launched outside Xcode (security:
prevents random binaries from spying on other apps' GPU work). The
output is a 3.5 GB bundle of MTLBuffer dumps that opens in Xcode's
Frame Debugger.

Xcode → Show GPU Performance ranks every kernel by GPU time. The top
of the list:

```
1. argmax            ← surprising
2. rms_norm          ← also surprising
3. nvfp4_matvec_mlx_gu
4. nvfp4_matvec_v4   (lm_head)
5. nvfp4_matvec_mlx_residual
6. nvfp4_matvec_mlx_qkv
```

**Argmax was #1 in GPU time.** A single reduction over 151,936 vocab
logits, dispatched once per token. Beating the entire 28-layer matvec
stack. That doesn't make sense unless the kernel is running on a
sliver of the GPU's compute.

Looking at the kernel:

```metal
kernel void argmax(
  device float *x [[buffer(0)]],
  device int *result [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int lane = int(__simd_lane);
  float m_local = -1000000000.0f;
  int i = lane;
  while ((i < n)) {
    float v = x[i];
    if ((v > m_local)) { m_local = v; }
    i = (i + 32);                          // ← stride 32 = 1 simdgroup
  }
  float m = simd_max(m_local);             // ← 32-lane reduction
  // ... second pass to find smallest tied index ...
  int g_best = simd_min(best);
  if ((lane == 0)) { result[0] = g_best; }
}
```

Dispatched at `1 TG × 32 threads = 1 simdgroup ≈ 0.25% of M3 Max
compute capacity`. Each lane sequentially scans 4748 elements. Twice
(once for max value, once for smallest tied index — `simd_max` doesn't
carry an index alongside the value).

In-isolation per-call cost: **1713 µs**. We had been burning ~1250 µs
of every 6527 µs decode-token budget on argmax alone, hidden because
Apple's GPU scheduler partially overlapped it with the prior wave's
matmul.

The same pattern showed up in `rms_norm`:

```tungsten
@gpu fn rms_norm(x, w, y, n, inv_n, eps)
  lane = gpu.thread_index_in_simdgroup ## i32
  sum_sq = 0.0 ## f32
  i = lane ## i32
  while i < n
    v = x[i] ## f32
    sum_sq = sum_sq + v * v
    i = i + 32                            # ← also stride 32
  total = simd_sum(sum_sq) ## f32         # ← also single-simdgroup
  rrms = ~1.0 / sqrt(total * inv_n + eps) ## f32
  i = lane
  while i < n
    y[i] = x[i] * rrms * w[i]
    i = i + 32
```

57 invocations per token (28 layers × 2 + final norm) × HIDDEN=2048.
Each lane scanned 64 elements with 1-simdgroup parallelism.

Both kernels were **algorithmically correct** and **dispatched
correctly**. The bug wasn't a bug in the usual sense. It was that
the Tungsten `@gpu` language only exposed *simdgroup-scoped* primitives
(`simd_sum`, `simd_max`, `simd_min`), so `1 TG × 32 threads` was
**the only dispatch shape compatible with the kernel as written**. A
larger TG would have each simdgroup compute its own independent
`simd_max` with no cross-simdgroup reduction; the answer would just be
the per-simdgroup max of the first simdgroup, dropped from the rest.

## Rung 2: Hand-roll the fix to confirm the diagnosis

Before changing the language, we wrote `argmax_v2.metal` by hand —
1024 threads (32 simdgroups), tracks `(value, index)` per thread,
reduces within each simdgroup, then cross-simdgroup via threadgroup
memory:

```metal
[[max_total_threads_per_threadgroup(1024)]]
kernel void argmax_v2(
  device const float *x [[buffer(0)]],
  device int *result [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  const int TG_SIZE = 1024;
  const int N_SIMDS = 32;
  float my_max = -INFINITY;
  int   my_idx = 0;
  for (int i = int(__tid_in_tg); i < n; i += TG_SIZE) {
    float v = x[i];
    if (v > my_max) { my_max = v; my_idx = i; }
  }
  float sm_max = simd_max(my_max);
  int   sm_idx = (my_max == sm_max) ? my_idx : INT_MAX;
  sm_idx = simd_min(sm_idx);

  threadgroup float tg_max[N_SIMDS];
  threadgroup int   tg_idx[N_SIMDS];
  if (__simd_lane == 0) {
    tg_max[__simd_id] = sm_max;
    tg_idx[__simd_id] = sm_idx;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (__simd_id == 0) {
    float v   = tg_max[__simd_lane];
    int   idx = tg_idx[__simd_lane];
    float gmax = simd_max(v);
    int   gidx = (v == gmax) ? idx : INT_MAX;
    gidx = simd_min(gidx);
    if (__simd_lane == 0) result[0] = gidx;
  }
}
```

Dispatched at TG=1024.

**Result: decode 146 → 183 tok/s (+25%), GPU 6527 → 5199 µs/token (-19%).**
Argmax bit-exact. Generation produced the exact same token IDs
(`[9625, 374, 198, 3798, 510, 32, 13, 12095]`).

Same fix for `rms_norm` (256 threads = 8 simdgroups, similar
threadgroup-memory cross-simdgroup reduction): **183 → 231 tok/s
(+26%), GPU 5199 → 3938 µs/token (-24%).**

We had crossed MLX. Two single-simdgroup kernels were burning ~2.5 ms
per token between them. Both fixes were 30-line changes once we knew
where to look.

## Rung 3: Extend the @gpu language so the fix lives in source

The `_v2.metal` files were hand-rolled MSL — divergent from the
`@gpu fn` source-of-truth pattern that produces the rest of Tungsten's
GPU kernels. The right fix is to extend the language so `argmax.w` and
`rms_norm.w` can express the same thing in declarative form.

The minimum extension: three new primitives.

```tungsten
total = tg_sum(sum_sq)     # threadgroup-wide sum
m     = tg_max(m_local)    # threadgroup-wide max
g_best = tg_min(best)      # threadgroup-wide min
```

Plus `gpu.threads_per_threadgroup` so the iteration stride scales with
dispatch shape instead of being hardcoded to 32:

```tungsten
@gpu fn argmax(x, result, n)
  tg_size = gpu.threads_per_threadgroup ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  m_local = ~-1000000000.0 ## f32
  i = tid ## i32
  while i < n
    v = x[i] ## f32
    if v > m_local
      m_local = v
    i = i + tg_size                          # ← scales with dispatch
  m = tg_max(m_local) ## f32                 # ← TG-wide reduction
  best = n ## i32
  i = tid
  while i < n
    if x[i] == m
      if i < best
        best = i
    i = i + tg_size
  g_best = tg_min(best) ## i32
  if tid == 0
    result[0] = g_best
```

Implementation in `compiler/lib/metal_emitter.w`:

1. **Auto-emit helper functions** at file top of every generated
   `.metal` file:

   ```metal
   inline float __tg_sum_f32(float v, threadgroup float *s,
                             uint sl, uint si, uint n_simds) {
     float sm = simd_sum(v);
     if (sl == 0) { s[si] = sm; }
     threadgroup_barrier(mem_flags::mem_threadgroup);
     float partial = (sl < n_simds) ? s[sl] : 0.0f;
     float total = (si == 0) ? simd_sum(partial) : 0.0f;
     if (si == 0 && sl == 0) { s[0] = total; }
     threadgroup_barrier(mem_flags::mem_threadgroup);
     return s[0];
   }
   // _max_f32 and _min_i32 same shape with their identity values
   ```

2. **Auto-inject per kernel** — `[[max_total_threads_per_threadgroup(1024)]]`
   attribute, `__tg_size [[threads_per_threadgroup]]` parameter, and
   `threadgroup float __tg_scratch_f[32]; threadgroup int __tg_scratch_i[32];`
   scratch arrays at body start.

3. **Type-route `tg_*(x)` calls** at emit time — infer the argument's
   type and dispatch to `__tg_*_f32` (with `__tg_scratch_f`) or
   `__tg_*_i32` (with `__tg_scratch_i`).

The 2-barrier helper with `n_simds = __tg_size / 32` gating is
*faster* than my hand-rolled v2 MSL: it broadcasts via the same
`scratch[0]` write that the final reduce uses, instead of a separate
`total_bcast` variable that needs its own write. One write fewer per
call. Compiler-emitted code more disciplined than hand-written.

After regenerating both kernels from source: **231 → 238 tok/s
(+3%), GPU 3938 → 3772 µs/token.**

The `@gpu` language extension is the key transferable artifact.
The auditing later in the session found the same single-simdgroup
pattern in `attn_softmax`, `attn_scores`, `attn_weighted_sum` (also
rewritten with `tg_*`, currently latent because the bench uses fused
`sdpa_vector_bf16` for decode). The pattern "single-simdgroup
reductions in `@gpu fn` are silent perf bugs at any vocab/hidden > 32"
is now structurally addressed.

## Rung 4: Autotune confirms (and corrects) the tuning

With three kernels now using `tg_*` primitives at hand-picked TG
sizes (1024 for argmax, 256 for rms_norm, 512 for attn_softmax), we
wrote a synthetic-input autotune harness:

```
TG_SIZES = [32, 64, 128, 256, 512, 1024]
WARMUP_ITERS = 5
MEASURE_ITERS = 30
```

Runs each kernel × each TG size, validates output (argmax index
check), reports best. No model load, runs in seconds.

Apple max TG is 1024 (32 lanes × 32 simdgroups); 2048+ is rejected by
MSL. The valid grid is `{32, 64, 128, 256, 512, 1024}`.

In-isolation findings:

```
kernel              best TG    µs/call    notes
──────────────      ───────    ────────   ─────────────────────────
rms_norm            512        8.85       HIDDEN=2048
argmax              1024       45         N_VOCAB=151936
attn_softmax        512        1.86       n_heads=16, n_pos=128

nvfp4 matvec variants (K=N=2048):
  nvfp4_matvec       1 row/TG    32 thr    8.46 µs  (original)
  nvfp4_matvec_mlx   8 rows/TG   64 thr    5.60 µs  ← bench pick
  nvfp4_matvec_v3    4 rows/TG   128 thr   8.63 µs
  nvfp4_matvec_v4    32 rows/TG  1024 thr  10.10 µs (designed for batched M>1)
```

Two findings stick:

- **My initial pick of TG=256 for rms_norm was wrong** — TG=512 is
  actually best in-isolation. The autotune saved us from leaving 3-5%
  on the table.
- **`nvfp4_matvec_mlx` is genuinely 38% faster** than alternatives at
  q_proj shape. No lurking better variant for decode. v4's
  TG-cached-activation design pays off only for batched M>1 prefill;
  at M=1 decode the 1024-thread occupancy cost isn't paid back.

The autotune also surfaced an honest discrepancy. In-isolation:
`rms_norm` TG=32 = 68 µs/call, TG=512 = 8.85 µs/call (7.7× faster).
In-bench: TG=512 only ~3% faster than TG=32 on median (~242 vs ~235
tok/s after alternating runs to control for thermal). Concurrency
context (encoder type, neighboring dispatches, barrier scope)
compresses isolated wins.

**Per-isolation autotune is necessary but not sufficient. Production
tuning still needs bench-level confirmation, especially under thermal
load.**

## Final state

5-run final at autotune-optimal settings (M3 Max, post-thermal-warmup):

```
run     decode tok/s    GPU µs/token
───     ────────────    ────────────
1       247.6           3632
2       232.9           3849
3       234.3           3766
4       236.9           3743
5       245.7           3676
mean    239.5           3733
median  236.9           3743
```

vs MLX `mlx_lm.benchmark` sustained: **207 tok/s decode, ~4830 µs/token GPU**.

**Tungsten 1.16× MLX mean, 1.14× MLX median, -23% GPU time/token.**

Optimal config now in `bench_lightning.w`:

| Component | Setting |
|---|---|
| rms_norm | TG=512 (16 simdgroups), `tg_sum` reduction |
| argmax | TG=1024 (32 simdgroups), `tg_max` + `tg_min` reduction |
| nvfp4 matvec | `nvfp4_matvec_mlx` variant (8 rows/TG, 64 threads) |
| Q/K/V projection | fused single dispatch |
| gate/up projection | fused single dispatch |
| KV cache | bf16 (halves attention BW) |
| SDPA | `sdpa_vector_bf16` fused (1024 thr/TG, online softmax) |
| Argmax & lm_head | GPU-side, only 1 i32 reads back per token |
| Weight load | zero-copy `mmap.view_at` → `metal_buffer_for` |

## Lessons

**Frame Capture was the inflection point.** Without it we were
guessing — interleaved layout, kernel fusion, both either neutral
or marginal. With it we found a 50%-perf-bug in 30 seconds. We should
have run capture before the speculative kernel work, not after. The
biggest single-session win came from a direct trace of what the GPU
was actually spending time on.

**The biggest unlock came from extending the language, not optimizing
kernels.** Both wins traced back to `@gpu fn` only exposing
simdgroup-scoped primitives. That mathematically forced 32-thread
dispatch shapes, which forced ~0.25% GPU utilization on kernels
that should have been using the whole machine. The fix at the language
layer benefits every future `@gpu fn` that needs a TG-wide reduction,
not just these two.

**Apple GPU per-dispatch overhead is ~0.9 µs.** Much lower than
typical x86-style GPUs. We measured this by shipping Q/K/V + gate/up
fusion (saves 84 dispatches/token), which produced exactly 75 µs of
GPU-time reduction = 0.89 µs/dispatch. Implication: kernel-fusion-
for-launch-overhead is a small lever on Apple Silicon. Real costs
live inside kernels — picking the right dispatch shape and per-thread
work is where the 10-100× wins are.

**Apple GPU sequencer handles oversubscription gracefully.** lm_head
dispatches `4748 TGs × 1024 threads = ~152,000 simdgroup-slots`
against ~2560 concurrent capacity = ~60 sequential waves. Each wave
is fully utilized — no resource contention. Wide dispatches are fine
on Apple Silicon as long as each TG fits register/threadgroup-memory
budgets. The "too wide" failure mode you might worry about is register
pressure, not thread count.

**Compiler-emitted code can be more disciplined than hand-rolled.**
The `@gpu`-generated `rms_norm` was 7 tok/s faster than my hand-rolled
v2 because the auto-emitted helper used one fewer write per call.
Easy to forget that small efficiency when writing MSL by hand.

**Single-simdgroup reductions in `@gpu fn` are silent perf bugs at
any reduction size > ~64 elements.** This pattern probably exists in
other GPU DSLs that expose simd-scope primitives without TG-scope
equivalents. Check before scaling up the workload.

## Reproducing

```bash
# Pre-cache Lightning weights
HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download bradyclarke/Lightning-1.7B-mlx-nvfp4

# Build + bench
bin/tungsten compile scripts/bench/bench_lightning.w
codesign --force -s - scripts/bench/bench_lightning.wc
scripts/bench/bench_lightning.wc

# Frame Capture (single-token GPU trace → /tmp/bench_lightning.gputrace)
CAPTURE_TRACE=1 METAL_CAPTURE_ENABLED=1 scripts/bench/bench_lightning.wc
open /tmp/bench_lightning.gputrace

# Autotune sweep (no model load, runs in seconds)
bin/tungsten compile scripts/bench/autotune_lightning.w
codesign --force -s - scripts/bench/autotune_lightning.wc
scripts/bench/autotune_lightning.wc

# MLX baseline
pip install mlx-lm
mlx_lm.benchmark --model bradyclarke/Lightning-1.7B-mlx-nvfp4
```

## Files

| Path | What |
|------|------|
| `scripts/bench/bench_lightning.w` | End-to-end bench |
| `scripts/bench/autotune_lightning.w` | TG_SIZE × variant autotune harness |
| `bits/tungsten-llama/lib/argmax.w` | `@gpu fn` source using `tg_max`/`tg_min` |
| `bits/tungsten-llama/lib/rms_norm.w` | `@gpu fn` source using `tg_sum` |
| `bits/tungsten-llama/lib/attn_softmax.w` | `tg_*`-based (latent, sdpa fused at decode) |
| `compiler/lib/metal_emitter.w` | `@gpu` language → MSL emitter (extended) |
| `runtime/metal.m` | `MTLCaptureManager` runtime hooks, `BigArray` → MTLBuffer bridge |
| `bits/tungsten-llama/lib/kernels/nvfp4/nvfp4_matvec_mlx_qkv.metal` | Fused Q/K/V matvec |
| `bits/tungsten-llama/lib/kernels/nvfp4/nvfp4_matvec_mlx_gu.metal` | Fused gate/up matvec |
