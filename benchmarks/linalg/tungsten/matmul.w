# Tungsten matmul benchmark — naive triple loop. Uses `~` approx-Float
# (native f64) arithmetic. Array element access still goes through
# Array#[] method dispatch — the per-call load cost dominates the actual
# fmul/fadd cost today, which is the next-biggest target for codegen
# work (typed-array fast-path bypassing dispatch). See PERFORMANCE.md
# for the optimization stack.
#
# Run via the harness:
#   ./benchmarks/linalg/run.sh --only tungsten
#
# Or directly:
#   bin/tungsten -o /tmp/tt_mm benchmarks/linalg/tungsten/matmul.w
#   /tmp/tt_mm 256 2

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = []
b = []
c = []
i = 0
while i < size
  a.push(~0.0)
  b.push(~0.0)
  c.push(~0.0)
  i += 1

i = 0
while i < size
  ai_int = (i * 31 + 7) % 17
  bi_int = (i * 13 + 3) % 19
  a[i] = ai_int * ~1.0 / ~17.0
  b[i] = bi_int * ~1.0 / ~19.0
  i += 1

# Warm up.
ii = 0
while ii < n
  j = 0
  while j < n
    acc = ~0.0
    kk = 0
    while kk < n
      acc += a[ii * n + kk] * b[kk * n + j]
      kk += 1
    c[ii * n + j] = acc
    j += 1
  ii += 1

# Timed loop (single trial; harness wraps K_inner iters in one
# clock_gettime region since Tungsten's clock() resolution is fine).
t0 = clock()
iter = 0
while iter < k_iters
  ii = 0
  while ii < n
    j = 0
    while j < n
      acc = ~0.0
      kk = 0
      while kk < n
        acc += a[ii * n + kk] * b[kk * n + j]
        kk += 1
      c[ii * n + j] = acc
      j += 1
    ii += 1
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

# Single-line JSON, matching the other implementations' format. The
# `<<` chain produces multi-line output today because each `<<` does
# its own newline; the harness's JSON extractor joins them.
<< "{\"impl\":\"tungsten-native-f64\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
