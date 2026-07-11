# Array expression fusion — and what Numba/JAX are

## Numba

[Numba](https://numba.pydata.org/) is a **JIT compiler for Python**. You
decorate a function `@njit`; Numba compiles the Python bytecode to LLVM
machine code. Good for numeric loops without rewriting in C.

## JAX

[JAX](https://jax.readthedocs.io/) is a **NumPy-like API + autodiff +
XLA compiler**. You write array code; JAX traces it into a computation
graph, fuses ops, and runs on CPU/GPU/TPU. `jax.jit` is the key.

## What XLA fusion is

Without fusion, `sin(a*x + b) + c` over an array is four whole-array
ops — multiply, add, sin, add — each writing a full temporary to
memory: four allocations, four passes. XLA (JAX's compiler) traces the
expression into a graph, **fuses** the elementwise ops into one kernel
(one loop: read `x[i]`, compute the whole scalar chain, write `y[i]`),
and vectorizes it — including the `sin`, which it inlines as a SIMD
polynomial rather than calling libm per element.

## Fusion in Tungsten (shipped)

The lowering pass exists (`lowering/ops.w` `try_fuse_elementwise`).
An f64 elementwise expression tree —

```
y = (x .* a .+ b).sin() .+ c
```

— compiles to ONE raw loop: hoisted element pointers, then per element
`load double → fmul → fadd → call @sin → fadd → store double`. No
temporaries, no boxing (guarded by
`spec/compiler/elementwise_fusion_spec.w`). Kernel semantics are
preserved exactly: lhs must be array-valued, rhs arrays must match the
lhs size (same raise), scalars broadcast; f32/int arrays and single
bare DOT ops keep the runtime kernels.

On macOS the loop is then vectorized by LLVM with
`-fveclib=Darwin_libsystem_m` — the scalar `@sin` becomes libsystem_m's
2-lane NEON `_simd_sin_d2`. (This needed `memory(none)` on the libm
declares; a call that may write memory only gets scalarized inside the
vector loop.)

## Automatic backend selection (shipped)

Each fused site also outlines its loop body into a worker
(`__w_fuse_worker_N(blk, lo, hi)`) and gates on the runtime array size
(`w_fused_should_mt` / `w_fused_parallel_run` in runtime.c). The ladder
comes from a measured size sweep (M-series, sin-chain, spawn-per-call
pthreads):

| n | backend | why |
|---|---------|-----|
| < 32k | inline single-core loop | thread spawn+join floor (~30–60 µs) dominates |
| 32k – 128k | 4 threads | past the spawn floor, memory system not yet saturated |
| ≥ 128k | 8 threads | full core count pays from here |

Env overrides: `TUNGSTEN_FUSED_MT_MIN`, `TUNGSTEN_FUSED_T8_MIN`,
`TUNGSTEN_FUSED_THREADS` (≤1 disables threading). Results are
bit-identical across tiers — threads compute disjoint ranges of the
same f64 loop.

Fusion also covers f32 (and mixed f32/f64) trees with kernel-exact
dtype semantics: a DOT op inherits its lhs dtype, and the array
math.h-backed methods (sin/cos/sqrt/exp/log/tan) promote to f64 output (`array_map_f64` allocates f64
regardless of input).

**`## reuse` output buffers — the big allocation lever.** A fused
expression allocates a fresh result array per execution; in a loop
that's a calloc plus page fault-in every iteration. `y = <fused expr>
## reuse` (same user-assertion contract as `f64[n] ## reuse`) gives the
site a persistent output buffer instead. Measured on the 2-input f32
chain, CPU ladder, ms/iter — 1.3–4× at every size:

| n | fresh out | `## reuse` |
|---|-----------|------------|
| 4M | 1.25 | **0.3** |
| 16M | 4.5 | **1.4** |
| 64M | 8.8 | **4.6** |
| 256M | 24.3 | **17.3** |
| 500M | 45.3 | **32** |

**GPU tier**: on by default for arithmetic-only f32 trees with
**fresh outputs**, inside a measured window of **2M–32M elements**
(`TUNGSTEN_FUSED_GPU=0` disables; `_MIN`/`_MAX` move the window).
Buffers are zero-copy wraps of the arrays' own pages
(`newBufferWithBytesNoCopy`, unified memory), cached per site keyed by
(array identity, base, length) — stable inputs wire once. With the
input-wrap cache, the fresh-out window measures ~2× over fresh-out CPU
(0.75 vs 1.25 ms at 4M, 2.1 vs 4.5 at 16M). Outside the window the
CPU ladder runs: below it dispatch latency dominates; above it the
per-call VM wiring of the fresh multi-GB output does. When the output
is **stable** (`## reuse`), the runtime skips the GPU entirely — the
allocation-free CPU stream measured faster than the GPU at every size
for arithmetic trees, so reuse sites always take the CPU ladder.

The trees where the GPU wins ~30× (sin at 10M: 0.45 ms vs 23.6 ms)
remain CPU-side, blocked by the f64-promotion semantics above (MSL has
no double). Unlocking that is a language decision: either `.sin()` on
f32 arrays returns f32 (breaking change to kernel semantics), or an
explicit opt-in surface (`@offload`-style) licenses f32 transcendental
math on the GPU.

## Installing Numba and JAX

Both are optional — `fusion_baselines.py` skips any backend it can't
import. Bare `pip install` fails on Homebrew/system Pythons
(PEP 668 "externally-managed-environment"), so install into a venv at
the repo root — `run.sh` uses `.venv/bin/python3` automatically when
it exists:

```bash
# from the repo root, with uv (fast):
uv venv .venv
uv pip install numba jax            # CPU-only JAX; enough for jax.jit

# or with stock Python:
python3 -m venv .venv
.venv/bin/pip install numba jax
```

Notes:

- Numba needs a NumPy version it supports; if `pip` reports a conflict,
  let it downgrade NumPy or pin per Numba's error message.
- On Apple Silicon there is an experimental Metal backend
  (`pip install jax-metal`), but the benchmark only needs the default
  CPU wheel.

## Benchmarks

`benchmarks/fusion/` compares:

| Impl | Notes |
|------|--------|
| `tungsten_fused` | array expression, fused to one SIMD loop — JAX single-core peer |
| `tungsten_threads` | typed loop over NT=8 `Thread.new` slices — XLA-parallelism peer |
| `tungsten_gpu` | `@gpu fn` Metal kernel, f32 (MSL has no double), sync per dispatch |
| `tungsten_gpu_batch` | same kernel, all iterations in one command buffer |
| `tungsten_typed` | hand-written loop over `f64[]` buffers — the Numba peer |
| `tungsten_boxed` | growable boxed array via `push` — shows boxing cost |
| Python list loops | baseline |
| NumPy ufuncs | vectorized C |
| Numba `@njit` | LLVM JIT |
| JAX `jit` | XLA (float64 forced — its float32 default is a different problem) |

Run: `benchmarks/fusion/run.sh` (the GPU block is darwin-only and
skips gracefully without Metal).

Representative numbers (M-series, avg ms/iter). `fused` is the plain
array expression — auto-selection picks its backend:

| n | fused (auto) | threads (8, manual) | gpu | gpu_batch | typed | numba | numpy | jax |
|---|--------------|---------------------|-----|-----------|-------|-------|-------|-----|
| 200k | 0.20 | 0.16–0.18 | 0.26–0.30 | 0.02–0.08 | 0.40–0.46 | 0.39–0.45 | 0.44–0.47 | 0.15 |
| 1M   | 0.60 | 0.49      | 0.19 (f32) | —        | 1.6–2.2   | —     | —     | —   |
| 20M  | —    | 7.3       | 0.7–0.85  | —         | —         | —     | —     | 10.6 |

How to read it:

- Single core is sin-throughput-bound and Tungsten sits at
  numba/numpy parity. JAX's edge at 200k is **multithreading, not
  better per-core code**: its dumped HLO shows the same fused loop
  over the same `<2 x double>` NEON width (`llvm.sin.v2f64`, peer of
  our `_simd_sin_d2`) but split across 5 threads
  (`outer_dimension_partitions=[5]`; 8.4s user / 3.2s wall).
- `tungsten_threads` — 8 `Thread.new` slices over the same typed
  loop — matches JAX at 200k (0.14 vs 0.15) and beats it 1.4× at 20M
  (7.3 vs 10.6), even spawning fresh pthreads every iteration.
- The GPU kernel is latency-bound at 200k (~0.25 ms/dispatch
  round-trip; batching amortizes it away) and bandwidth-bound at 20M
  (~0.8 ms ≈ 160 MB over ~200 GB/s), where it is ~10× the 8-thread
  CPU and ~13× JAX. f32 only — MSL has no f64 — so its sums differ
  from the f64 rows below display precision.
- Making the *fused expression form* reach the threads/GPU numbers
  automatically = parallelizing/offloading the fused loop in the
  compiler, which is the remaining doc'd future work.
