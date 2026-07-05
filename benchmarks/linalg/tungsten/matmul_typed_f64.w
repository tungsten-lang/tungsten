# Tungsten typed-f64 matmul — the math-mode-sensitive CPU kernel.
#
# Unlike matmul.w (generic Array#[] → boxed w_mul/w_add runtime calls, which the
# `--strict-math` / `--fast` flags can't touch), this uses `f64[size]` typed
# arrays, so the inner `acc + a[..]*b[..]` lowers to INLINE LLVM float ops and is
# sensitive to the floating-point math mode:
#
#   --strict-math : bare `fmul` + `fadd`   (no FMA, no reassoc)
#   (default)     : `llvm.fmuladd.f64`     (FMA contraction of the direct a*b+c)
#   --fast        : `fmul fast`/`fadd fast` (reassoc → SIMD-vectorizable reduction)
#
# ijk order with a scalar f64 accumulator: the reduction's serial dependency
# chain is what fast-math's reassoc license breaks into parallel SIMD lanes —
# the canonical case where -ffast-math wins (1.3-1.5x compute-bound; converges
# to ~1x once memory-bandwidth-bound at larger N). NOTE: the scalar-f64 RMW
# accumulator only works inside a function, so matmul_ijk is a `-> fn`.
#
# Run (compare modes):
#   for m in "--strict-math" "" "--fast"; do
#     bin/tungsten $m --release -o /tmp/mm benchmarks/linalg/tungsten/matmul_typed_f64.w
#     /tmp/mm 128 300
#   done
use core/blas

-> matmul_ijk(a, b, c, n) (f64[] f64[] f64[])
  ii = 0
  while ii < n
    j = 0
    while j < n
      acc = ~0.0
      kk = 0
      while kk < n
        acc = acc + a[ii * n + kk] * b[kk * n + j]
        kk += 1
      c[ii * n + j] = acc
      j += 1
    ii += 1

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = f64[size]
b = f64[size]
c = f64[size]

i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

matmul_ijk(a, b, c, n)   # warm up

t0 = clock()
iter = 0
while iter < k_iters
  matmul_ijk(a, b, c, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / (k_iters ## f64)
gflops = (~2.0 * (n ## f64) * (n ## f64) * (n ## f64) * (k_iters ## f64)) / (elapsed_sec * ~1.0e9)
checksum = c[0] + c[size - 1]

<< "{\"impl\":\"tungsten-typed-f64\",\"N\":" + n.to_s() + ",\"K\":" + k_iters.to_s() + ",\"median_ms\":" + median_ms.to_s() + ",\"gflops\":" + gflops.to_s() + ",\"checksum\":" + checksum.to_s() + "}"
