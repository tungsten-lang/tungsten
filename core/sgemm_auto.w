# core/sgemm_auto — backend-selecting sgemm dispatch.
#
# Default: STRICT (true f32) precision. Routes only to backends verified
# bit-exact against `cblas_sgemm` via benchmarks/linalg/tungsten/validate_backend.w.
#
# Opt-in fast mode: set `TUNGSTEN_FAST_MATH=1` in the process environment
# (or build with `bin/tungsten --fast-math` once that flag lands) to route
# `sgemm_auto` to `sgemm_fast` instead. Fast uses MLX's TF32/NAX path
# at large N for 2-3× throughput at the cost of bf16-quality precision.
#
# Re-tune for a new machine: run
#   benchmarks/linalg/tungsten/sgemm_capabilities.sh
# That overwrites ~/.tungsten/sgemm-policy.json. The fast-mode dispatcher
# re-reads on the next process start.

use core/blas
use core/mlx
use core/metal_sgemm
use core/metal_sgemm_bf16

# --- Policy loader (used by sgemm_fast) ----------------------------------

# Load + parse the policy. Returns the threshold list, or a hardcoded
# default if the file is absent / unreadable / malformed.
-> load_sgemm_policy
  home = env("HOME")
  if home == nil || home == ""
    return sgemm_default_policy()
  path = home + "/.tungsten/sgemm-policy.json"
  if !file?(path)
    return sgemm_default_policy()
  text = read_file(path)
  data = JSON.parse(text)
  if data == nil
    return sgemm_default_policy()
  thresholds = data["policy_single"]
  if thresholds == nil || thresholds.size() == 0
    return sgemm_default_policy()
  thresholds

-> sgemm_default_policy
  [
    {"n_max" => 1024, "backend" => "accelerate"},
    {"n_max" => 1000000, "backend" => "mlx"}
  ]

SGEMM_POLICY = load_sgemm_policy()

# Pick the right backend for an input size (used by fast).
-> sgemm_auto_pick_backend(largest)
  i = 0
  while i < SGEMM_POLICY.size()
    entry = SGEMM_POLICY[i]
    if largest <= entry["n_max"]
      return entry["backend"]
    i += 1
  SGEMM_POLICY[SGEMM_POLICY.size() - 1]["backend"]

# Fast-math mode is a COMPILE-TIME choice via Tungsten's `-D` flag.
# `bin/tungsten --fast-math` translates to `-D FAST_MATH=true`, which
# the compiler turns into a build-time boolean constant. The `if
# FAST_MATH` branch in sgemm_auto below sees a literal `true` or
# `false` at lowering time, so LLVM's SimplifyCFG pass folds the
# branch into an unconditional jump. No runtime global, no per-call
# load+compare.

# --- sgemm_fast: mixed-precision, max-throughput dispatch ----------------
#
# Routes per the autotuned policy in ~/.tungsten/sgemm-policy.json. At
# large N this picks MLX, which uses TF32/NAX (bf16-internal). Output
# precision matches bf16 (~3 decimal digits).
#
# Use this when you DON'T need bit-exact f32 — e.g. ML inference, where
# the precision/perf trade is documented and expected.
fn sgemm_fast(a, b, c, m, n, k)
  largest = m
  if n > largest
    largest = n
  if k > largest
    largest = k

  backend = sgemm_auto_pick_backend(largest)

  if backend == "accelerate"
    sgemm(a, b, c, m, n, k)
  elsif backend == "metal-tiled"
    if m == n && n == k && (n % 32) == 0
      metal_sgemm(a, b, c, m, n, k)
    else
      mlx_sgemm(a, b, c, m, n, k)
  elsif backend == "metal-bf16"
    if m == n && n == k && (n % 32) == 0
      metal_sgemm_bf16(a, b, c, m, n, k)
    else
      mlx_sgemm(a, b, c, m, n, k)
  else
    mlx_sgemm(a, b, c, m, n, k)

# --- sgemm_strict: true-f32 dispatch (verified bit-exact) ----------------
#
# Routes ONLY to backends that produce bit-exact-vs-cblas_sgemm results.
#
# Verified strict backends (via validate_backend.w):
#   accelerate    — max_abs_err = 0 (self-compare)
#   metal-tiled   — max_abs_err = 0 (Tungsten-native simdgroup_matrix)
#
# Excluded:
#   mlx           — TF32-by-default (bf16-internal); see sgemm_fast
#   metal-bf16    — explicit bf16-internal (purpose-built reduced prec)
fn sgemm_strict(a, b, c, m, n, k)
  largest = m
  if n > largest
    largest = n
  if k > largest
    largest = k

  if largest < 1024
    sgemm(a, b, c, m, n, k)
  else
    if m == n && n == k && (n % 32) == 0
      metal_sgemm(a, b, c, m, n, k)
    else
      # Shape doesn't fit metal_sgemm's square-multiple-of-32 contract.
      # Fall back to accelerate — slower but always correct + strict.
      sgemm(a, b, c, m, n, k)

# --- sgemm_auto: STRICT by default; compile-time alias via FAST_MATH ----
#
# This is the dispatcher most callers should use. The `if FAST_MATH`
# check below is constant-folded at compile time:
#   - `bin/tungsten -o foo file.w`             → FAST_MATH is undefined
#                                                → routes to sgemm_strict
#   - `bin/tungsten --fast-math -o foo file.w` → FAST_MATH=true
#                                                → routes to sgemm_fast
#   - `bin/tungsten --no-fast-math -o foo file.w` → FAST_MATH=false
#                                                → routes to sgemm_strict
#
# Either way, the produced binary has ONE instruction in sgemm_auto's
# body — a direct branch to one of the implementations. No runtime
# global, no per-call load.
fn sgemm_auto(a, b, c, m, n, k)
  if FAST_MATH
    sgemm_fast(a, b, c, m, n, k)
  else
    sgemm_strict(a, b, c, m, n, k)

# Batched dispatch — for callers that can fold K matmuls into a single
# sync barrier (e.g. transformer training inner loops). Always fast.
fn sgemm_auto_batch(a, b, c, m, n, k, iters)
  largest = m
  if n > largest
    largest = n
  if k > largest
    largest = k

  backend = sgemm_auto_pick_backend(largest)
  if backend == "accelerate"
    i = 0
    while i < iters
      sgemm(a, b, c, m, n, k)
      i += 1
  else
    mlx_sgemm_batch(a, b, c, m, n, k, iters)

# Double-precision auto-dispatch. Both backends call cblas_dgemm
# internally — within noise. Default to accelerate; mlx_dgemm exists
# for graph composition.
fn dgemm_auto(a, b, c, m, n, k)
  dgemm(a, b, c, m, n, k)

# bf16 policy: which backend handles a square-multiple-of-32 shape up to
# each n_max. Tunable via "policy_bf16" in ~/.tungsten/sgemm-policy.json;
# the default routes every eligible shape to the Tungsten-native
# metal-bf16 kernel (measured on M-series: 246 GFLOPS at n=512, 1300 at
# 1024, 6627 at 2048 — scaling cleanly), everything else to MLX as before.
-> load_bgemm_policy
  home = env("HOME")
  return bgemm_default_policy() if home == nil || home == ""
  path = home + "/.tungsten/sgemm-policy.json"
  return bgemm_default_policy() if !file?(path)
  data = JSON.parse(read_file(path))
  return bgemm_default_policy() if data == nil
  thresholds = data["policy_bf16"]
  return bgemm_default_policy() if thresholds == nil || thresholds.size() == 0
  thresholds

-> bgemm_default_policy
  [
    {"n_max" => 1000000, "backend" => "metal-bf16"}
  ]

BGEMM_POLICY = load_bgemm_policy()

-> bgemm_pick_backend(largest)
  i = 0
  while i < BGEMM_POLICY.size()
    entry = BGEMM_POLICY[i]
    if largest <= entry["n_max"]
      return entry["backend"]
    i += 1
  BGEMM_POLICY[BGEMM_POLICY.size() - 1]["backend"]

# bfloat16 auto-dispatch over PACKED bf16 arrays (MLX's contract — see
# core/mlx::f32_to_bf16). MLX is the only backend speaking packed bf16,
# so this stays a direct call; the POLICY lives one level up in
# sgemm_bf16_auto, whose f32-array contract both backends can serve.
fn bgemm_auto(a, b, c, m, n, k)
  mlx_bgemm(a, b, c, m, n, k)

# bf16-internal matmul over F32 ARRAYS: precision of bf16, convenience of
# f32 buffers. Square-multiple-of-32 shapes follow policy_bf16 (default:
# the Tungsten-native metal-bf16 kernel, which takes f32 and converts on
# the GPU — measured 246/1300/6627 GFLOPS at n=512/1024/2048). Other
# shapes are the caller's explicit choice: pack with f32_to_bf16 and call
# bgemm_auto/mlx_bgemm directly (no silent conversion path is provided —
# there is no validated bf16->f32 return conversion today).
fn sgemm_bf16_auto(a, b, c, m, n, k)
  if m == n && n == k && (n % 32) == 0
    backend = bgemm_pick_backend(m)
    if backend == "metal-bf16"
      return metal_sgemm_bf16(a, b, c, m, n, k)
    return mlx_sgemm(a, b, c, m, n, k)
  raise "sgemm_bf16_auto: square multiple-of-32 shapes only — pack bf16 and use bgemm_auto for other shapes"
