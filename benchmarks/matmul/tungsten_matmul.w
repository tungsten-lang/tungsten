# Tungsten-native matmul benchmark.
#
#   1. Mat3 / Mat4 `*` operator throughput (the current fixed-size types)
#   2. a hand-written NxN schoolbook on f64_array (the general-loop path)
#   3. Accelerate dgemm via core/blas (warmed — Accelerate lazy-inits AMX,
#      so the first call is a cold-start outlier)
#
# Compare against fixed_small.c (ideal small) and sweep.c (ideal NxN), all
# built at the same --release flags. Run via run.sh.
#
#   bin/tungsten -o /tmp/tm --release benchmarks/matmul/tungsten_matmul.w && /tmp/tm

use core/blas

-> fill(arr, n) (f64[])
  v = ~0.5
  i = 0
  while i < n
    arr[i] = v
    v = v + ~0.25
    if v > ~9.0
      v = ~0.5
    i += 1

# Schoolbook NxN, ikj order (cache-friendly, FMA-shaped).
-> matmul_school(a, b, c, n) (f64[] f64[] f64[])
  i = 0
  while i < n * n
    c[i] = ~0.0
    i += 1
  ii = 0
  while ii < n
    kk = 0
    while kk < n
      aik = a[ii * n + kk]
      base_a = ii * n
      base_b = kk * n
      jj = 0
      while jj < n
        c[base_a + jj] = c[base_a + jj] + aik * b[base_b + jj]
        jj += 1
      kk += 1
    ii += 1

# ---- 1. Mat3 / Mat4 fixed-size `*` throughput ----
m3a = Mat3<f64>.new([~1.0, ~2.0, ~3.0, ~4.0, ~5.0, ~6.0, ~7.0, ~8.0, ~9.0] ## f64[9])
m3b = Mat3<f64>.new([~9.0, ~8.0, ~7.0, ~6.0, ~5.0, ~4.0, ~3.0, ~2.0, ~1.0] ## f64[9])
iters = 3000000
t0 = clock()
acc = ~0.0
i = 0
while i < iters
  c = m3a * m3b
  acc = acc + c.at(0, 0)
  i += 1
t1 = clock()
<< "Mat3 *  : " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc.to_s() + ")"

m4a = Mat4<f64>.new([~1.0,~2.0,~3.0,~4.0,~5.0,~6.0,~7.0,~8.0,~9.0,~1.0,~2.0,~3.0,~4.0,~5.0,~6.0,~7.0] ## f64[16])
m4b = Mat4<f64>.new([~7.0,~6.0,~5.0,~4.0,~3.0,~2.0,~1.0,~9.0,~8.0,~7.0,~6.0,~5.0,~4.0,~3.0,~2.0,~1.0] ## f64[16])
t0 = clock()
acc4 = ~0.0
i = 0
while i < iters
  c = m4a * m4b
  acc4 = acc4 + c.at(0, 0)
  i += 1
t1 = clock()
<< "Mat4 *  : " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc4.to_s() + ")"

# ---- 2 & 3. NxN schoolbook (Tungsten loop) vs Accelerate dgemm ----
sizes = [128, 256, 512]
si = 0
while si < sizes.size()
  n = sizes[si]
  a = f64[n * n]
  b = f64[n * n]
  c = f64[n * n]
  fill(a, n * n)
  fill(b, n * n)

  reps = 5
  t0 = clock()
  r = 0
  while r < reps
    matmul_school(a, b, c, n)
    r += 1
  t1 = clock()
  sch = (t1 - t0) / (reps ## f64)
  gf_sch = (~2.0 * (n ## f64) * (n ## f64) * (n ## f64)) / sch / ~1.0e9

  dgemm(a, b, c, n, n, n)    # warmup x2 (Accelerate AMX lazy-init)
  dgemm(a, b, c, n, n, n)
  dreps = 50
  t0 = clock()
  r = 0
  while r < dreps
    dgemm(a, b, c, n, n, n)
    r += 1
  t1 = clock()
  dg = (t1 - t0) / (dreps ## f64)
  gf_dg = (~2.0 * (n ## f64) * (n ## f64) * (n ## f64)) / dg / ~1.0e9

  << "n=" + n.to_s() + "  school " + (sch * ~1000.0).to_s() + " ms (" + gf_sch.to_s() + " GF)   dgemm " + (dg * ~1000.0).to_s() + " ms (" + gf_dg.to_s() + " GF)"
  si += 1
