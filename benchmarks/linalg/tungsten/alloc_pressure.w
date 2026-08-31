# Allocation-pressure census for the dense LinAlg / Tensor tier.
#
# Read-only measurement (no fixes here): quantifies what the boxed
# Vec-of-rows representation and per-call fresh allocation cost against the
# flat/BLAS path that lives one file away, so the workspace-reuse work has
# honest before numbers. Deterministic inputs.
#
#   bin/tungsten --release -o /tmp/alloc_pressure benchmarks/linalg/tungsten/alloc_pressure.w
#   /tmp/alloc_pressure

use core/blas

-> now_ms
  ccall("__w_clock_ms")

+ BenchRandom
  -> new(@seed)
  -> next_float
    @seed = (@seed * 1103515245 + 12345) % 2147483648
    (@seed % 1000000) / ~1000000.0

# 128x128 nested-list matmul (LinAlg tier).
rng = BenchRandom.new(7)
n = 128
a = []
b = []
i = 0
while i < n
  ra = []
  rb = []
  j = 0
  while j < n
    ra.push(rng.next_float + ~0.5)
    rb.push(rng.next_float + ~0.5)
    j += 1
  a.push(ra)
  b.push(rb)
  i += 1
t0 = now_ms
c = LinAlg.matmul(a, b)
t1 = now_ms
<< "BENCH linalg_matmul_128 ms=" + (t1 - t0).to_s + " c00=" + c[0][0].round(3).to_s

# Same product through the flat f64 + Accelerate dgemm path.
flat_a = f64_array(n * n)
flat_b = f64_array(n * n)
flat_c = f64_array(n * n)
i = 0
while i < n
  j = 0
  while j < n
    flat_a[i * n + j] = a[i][j]
    flat_b[i * n + j] = b[i][j]
    j += 1
  i += 1
t0 = now_ms
reps = 0
while reps < 100
  dgemm(flat_a, flat_b, flat_c, n, n, n)
  reps += 1
t1 = now_ms
<< "BENCH blas_dgemm_128_x100 ms=" + (t1 - t0).to_s + " c00=" + flat_c[0].round(3).to_s

# solve() copies the matrix per call (copy_mat + fresh zeros).
rhs = []
i = 0
while i < n
  rhs.push(rng.next_float)
  i += 1
t0 = now_ms
reps = 0
x = nil
while reps < 10
  x = LinAlg.solve(a, rhs)
  reps += 1
t1 = now_ms
<< "BENCH linalg_solve_128_x10 ms=" + (t1 - t0).to_s + " x0=" + x[0].round(3).to_s

# charpoly calls matmul n times on fresh matrices.
small = []
i = 0
while i < 40
  row = []
  j = 0
  while j < 40
    row.push(rng.next_float - ~0.5)
    j += 1
  small.push(row)
  i += 1
t0 = now_ms
cp = LinAlg.charpoly(small)
t1 = now_ms
<< "BENCH linalg_charpoly_40 ms=" + (t1 - t0).to_s + " coeffs=" + cp.size.to_s

# Tensor#binop: documented boxed per-element loop with per-element coord
# allocation on the broadcast path.
ta = Tensor.zeros_cpu(Tensor.f64, [256, 256])
tb = Tensor.zeros_cpu(Tensor.f64, [256, 256])
i = 0
while i < 256
  j = 0
  while j < 256
    ta.set([i, j], rng.next_float)
    tb.set([i, j], rng.next_float)
    j += 1
  i += 1
t0 = now_ms
tc = ta + tb
t1 = now_ms
<< "BENCH tensor_add_256 ms=" + (t1 - t0).to_s

<< "alloc_pressure done"
