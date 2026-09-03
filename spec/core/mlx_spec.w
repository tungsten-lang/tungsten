# MLX — Apple MLX (Metal-backed) compute bridge (core/mlx.w).
#
# METAL LANE. Every function is a thin ccall into runtime/mlx_bridge.c, which is an
# opt-in link. The spec begins with an availability query and skips the dispatch
# half when the bridge is absent (the native interpreter has no ccall entry for
# these symbols at all), so both lanes stay green.
#
# Shapes are deliberately tiny (2x2 / 4-element) — this is a contract spec, not a
# benchmark. The benchmark suite lives in benchmarks/linalg/tungsten/.
#
# Run:
#   bin/tungsten run --interpret spec/core/mlx_spec.w
#   bin/tungsten -o /tmp/mlx_spec spec/core/mlx_spec.w && /tmp/mlx_spec

use core/mlx
use core/blas

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < ~1.0e-5

-> filled(n, v)
  arr = f32_array(n)
  i = 0
  while i < n
    arr[i] = v
    i += 1
  arr

# ---- availability query ----
mlx_ok = true
begin
  probe_a = filled(4, ~1.0)
  probe_b = filled(4, ~2.0)
  probe_c = filled(4, ~0.0)
  mlx_sgemm(probe_a, probe_b, probe_c, 2, 2, 2)
  if probe_c[0] != ~4.0
    mlx_ok = false
rescue e
  mlx_ok = false

if !mlx_ok
  << "SKIP mlx (runtime/mlx_bridge.c not linked into this build)"
else
  # ---- sgemm: C = A · B, row-major, with GPU->CPU readback ----
  a = filled(16, ~1.0)
  b = filled(16, ~2.0)
  c = filled(16, ~-1.0)
  check("sgemm reports success", mlx_sgemm(a, b, c, 4, 4, 4) == 1)
  # every row of A is four 1s, every column of B four 2s -> 8
  check("sgemm computes the product", c[0] == ~8.0)
  check("sgemm fills the whole output", c[15] == ~8.0)
  check("sgemm overwrites the previous contents", c[7] == ~8.0)

  small = filled(4, ~1.0)
  small_b = filled(4, ~3.0)
  small_c = filled(4, ~0.0)
  mlx_sgemm(small, small_b, small_c, 2, 2, 2)
  check("a 2x2 product", small_c[0] == ~6.0)

  # ---- no_readback / batch skip the GPU->CPU copy, by contract ----
  nr_c = filled(4, ~0.0)
  check("no_readback reports success", mlx_sgemm_no_readback(small, small_b, nr_c, 2, 2, 2) == 1)
  check("no_readback leaves the CPU buffer untouched", nr_c[0] == ~0.0)
  batch_c = filled(4, ~0.0)
  check("batch reports success", mlx_sgemm_batch(small, small_b, batch_c, 2, 2, 2, 3) == 1)
  check("batch leaves the CPU buffer untouched", batch_c[0] == ~0.0)

  # ---- dgemm: the f64 twin ----
  da = f64_array(4)
  db = f64_array(4)
  dc = f64_array(4)
  i = 0
  while i < 4
    da[i] = ~1.0
    db[i] = ~2.0
    dc[i] = ~0.0
    i += 1
  check("dgemm reports success", mlx_dgemm(da, db, dc, 2, 2, 2) == 1)
  check("dgemm computes the product", dc[0] == ~4.0)

  # ---- elementwise ops ----
  three = filled(4, ~3.0)
  four = filled(4, ~4.0)
  out = filled(4, ~0.0)
  check("add reports success", mlx_add(three, four, out, 4) == 1)
  check("add", out[0] == ~7.0)
  check("add covers every element", out[3] == ~7.0)
  mlx_mul(three, four, out, 4)
  check("mul", out[0] == ~12.0)
  mlx_sub(four, three, out, 4)
  check("sub", out[0] == ~1.0)
  mlx_div(four, three, out, 4)
  check("div", near(out[0], ~4.0 / ~3.0))
  mlx_exp(filled(4, ~0.0), out, 4)
  check("exp of 0 is 1", out[0] == ~1.0)
  mlx_log(filled(4, ~1.0), out, 4)
  check("log of 1 is 0", out[0] == ~0.0)
  mlx_sqrt(four, out, 4)
  check("sqrt of 4 is 2", out[0] == ~2.0)
  mlx_tanh(filled(4, ~0.0), out, 4)
  check("tanh of 0 is 0", out[0] == ~0.0)

  # ---- reductions ----
  check("sum reduces over every element", mlx_sum(three, 4) == ~12.0)
  check("max reduces over every element", mlx_max(four, 4) == ~4.0)
  ramp = f32_array(4)
  ramp[0] = ~1.0
  ramp[1] = ~5.0
  ramp[2] = ~2.0
  ramp[3] = ~3.0
  check("max picks the largest", mlx_max(ramp, 4) == ~5.0)
  check("sum of a ramp", mlx_sum(ramp, 4) == ~11.0)

  # ---- row-wise softmax over a 2x2 matrix of equal entries ----
  sm_in = filled(4, ~0.0)
  sm_out = filled(4, ~0.0)
  check("softmax reports success", mlx_softmax_rows(sm_in, sm_out, 2, 2) == 1)
  check("equal logits give a uniform row", sm_out[0] == ~0.5 && sm_out[1] == ~0.5)
  check("every row is normalized", near(sm_out[2] + sm_out[3], ~1.0))

  # ---- FFT: in-place over split re/im, orthonormal (1/sqrt(N)) scaling ----
  re = filled(4, ~0.0)
  im = filled(4, ~0.0)
  re[0] = ~1.0
  check("fft reports success", mlx_fft(re, im, 4, 0) == 1)
  # A unit impulse transforms to a flat spectrum, 1/sqrt(4) = 0.5 per bin.
  check("impulse transforms flat", re[0] == ~0.5 && re[1] == ~0.5 && re[2] == ~0.5 && re[3] == ~0.5)
  check("an impulse has no imaginary part", im[0] == ~0.0 && im[2] == ~0.0)
  dc_re = filled(4, ~1.0)
  dc_im = filled(4, ~0.0)
  mlx_fft(dc_re, dc_im, 4, 0)
  # A constant signal is all DC: 4/sqrt(4) = 2 in bin 0, nothing elsewhere.
  check("a constant signal is pure DC", dc_re[0] == ~2.0)
  check("a constant signal has no other bins", dc_re[1] == ~0.0 && dc_re[3] == ~0.0)

  # ---- RNG ----
  uni = f32_array(8)
  check("random_uniform reports success", mlx_random_uniform(uni, 8, ~0.0, ~1.0, 42) == 1)
  in_range = true
  i = 0
  while i < 8
    if uni[i] < ~0.0 || uni[i] > ~1.0
      in_range = false
    i += 1
  check("random_uniform respects its bounds", in_range)
  shifted = f32_array(8)
  mlx_random_uniform(shifted, 8, ~10.0, ~11.0, 42)
  shifted_ok = true
  i = 0
  while i < 8
    if shifted[i] < ~10.0 || shifted[i] > ~11.0
      shifted_ok = false
    i += 1
  check("random_uniform honours a shifted range", shifted_ok)
  repeat = f32_array(8)
  mlx_random_uniform(repeat, 8, ~0.0, ~1.0, 42)
  check("the same seed reproduces the same draw", repeat[0] == uni[0] && repeat[7] == uni[7])
  other = f32_array(8)
  mlx_random_uniform(other, 8, ~0.0, ~1.0, 43)
  check("a different seed draws differently", other[0] != uni[0])
  norm = f32_array(8)
  check("random_normal reports success", mlx_random_normal(norm, 8, ~0.0, ~1.0, 7) == 1)
  degenerate = f32_array(8)
  mlx_random_normal(degenerate, 8, ~5.0, ~0.0, 7)
  check("a zero standard deviation collapses to the mean", degenerate[0] == ~5.0)

  # ---- eval barrier ----
  check("eval synchronizes and reports success", mlx_eval() == 1)

<< "ALL PASS mlx_spec ([passed.load()] checks)"
