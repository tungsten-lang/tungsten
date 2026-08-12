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

-> fill(arr, n) (f64[] i64)
  v = ~0.5
  i = 0
  while i < n
    arr[i] = v
    v = v + ~0.25
    if v > ~9.0
      v = ~0.5
    i += 1

# Allocation- and dispatch-free arithmetic floors for the fixed shapes.
# Inputs and output are prevalidated f64 buffers; these isolate codegen from
# the Mat3/Mat4 API and allocation costs measured below.
-> mat3_kernel(a, b, o) (f64[] f64[] f64[])
  o[0] = a[0] * b[0] + a[3] * b[1] + a[6] * b[2]
  o[1] = a[1] * b[0] + a[4] * b[1] + a[7] * b[2]
  o[2] = a[2] * b[0] + a[5] * b[1] + a[8] * b[2]
  o[3] = a[0] * b[3] + a[3] * b[4] + a[6] * b[5]
  o[4] = a[1] * b[3] + a[4] * b[4] + a[7] * b[5]
  o[5] = a[2] * b[3] + a[5] * b[4] + a[8] * b[5]
  o[6] = a[0] * b[6] + a[3] * b[7] + a[6] * b[8]
  o[7] = a[1] * b[6] + a[4] * b[7] + a[7] * b[8]
  o[8] = a[2] * b[6] + a[5] * b[7] + a[8] * b[8]
  0 ## i64

-> mat4_kernel(a, b, o) (f64[] f64[] f64[])
  o[0]  = a[0] * b[0]  + a[4] * b[1]  + a[8]  * b[2]  + a[12] * b[3]
  o[1]  = a[1] * b[0]  + a[5] * b[1]  + a[9]  * b[2]  + a[13] * b[3]
  o[2]  = a[2] * b[0]  + a[6] * b[1]  + a[10] * b[2]  + a[14] * b[3]
  o[3]  = a[3] * b[0]  + a[7] * b[1]  + a[11] * b[2]  + a[15] * b[3]
  o[4]  = a[0] * b[4]  + a[4] * b[5]  + a[8]  * b[6]  + a[12] * b[7]
  o[5]  = a[1] * b[4]  + a[5] * b[5]  + a[9]  * b[6]  + a[13] * b[7]
  o[6]  = a[2] * b[4]  + a[6] * b[5]  + a[10] * b[6]  + a[14] * b[7]
  o[7]  = a[3] * b[4]  + a[7] * b[5]  + a[11] * b[6]  + a[15] * b[7]
  o[8]  = a[0] * b[8]  + a[4] * b[9]  + a[8]  * b[10] + a[12] * b[11]
  o[9]  = a[1] * b[8]  + a[5] * b[9]  + a[9]  * b[10] + a[13] * b[11]
  o[10] = a[2] * b[8]  + a[6] * b[9]  + a[10] * b[10] + a[14] * b[11]
  o[11] = a[3] * b[8]  + a[7] * b[9]  + a[11] * b[10] + a[15] * b[11]
  o[12] = a[0] * b[12] + a[4] * b[13] + a[8]  * b[14] + a[12] * b[15]
  o[13] = a[1] * b[12] + a[5] * b[13] + a[9]  * b[14] + a[13] * b[15]
  o[14] = a[2] * b[12] + a[6] * b[13] + a[10] * b[14] + a[14] * b[15]
  o[15] = a[3] * b[12] + a[7] * b[13] + a[11] * b[14] + a[15] * b[15]
  0 ## i64

# Schoolbook NxN, ikj order (cache-friendly, FMA-shaped).
-> matmul_school(a, b, c, n) (f64[] f64[] f64[] i64)
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

m3out = Mat3<f64>.zero
t0 = clock()
acc = ~0.0
i = 0
while i < iters
  c = m3a.mul_into(m3b, m3out)
  acc = acc + c.at(0, 0)
  i += 1
t1 = clock()
<< "Mat3 into: " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc.to_s() + ")"

m3ae = m3a.elements
m3be = m3b.elements
m3oe = m3out.elements
t0 = clock()
acc = ~0.0
i = 0
while i < iters
  mat3_kernel(m3ae, m3be, m3oe)
  acc = acc + m3oe[0]
  i += 1
t1 = clock()
<< "Mat3 kern: " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc.to_s() + ")"

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

m4out = Mat4<f64>.zero
t0 = clock()
acc4 = ~0.0
i = 0
while i < iters
  c = m4a.mul_into(m4b, m4out)
  acc4 = acc4 + c.at(0, 0)
  i += 1
t1 = clock()
<< "Mat4 into: " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc4.to_s() + ")"

m4ae = m4a.elements
m4be = m4b.elements
m4oe = m4out.elements
t0 = clock()
acc4 = ~0.0
i = 0
while i < iters
  mat4_kernel(m4ae, m4be, m4oe)
  acc4 = acc4 + m4oe[0]
  i += 1
t1 = clock()
<< "Mat4 kern: " + ((t1 - t0) / (iters ## f64) * ~1.0e9).to_s() + " ns/op   (acc=" + acc4.to_s() + ")"

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
