# Integer elementwise-chain benchmark.
#
# Build the same source with the compiler before/after integer fusion and run
# with TUNGSTEN_FUSED_THREADS=1 to isolate temporary-allocation and loop-fusion
# costs from the existing parallel scheduler. The hand-written loop is the
# no-temporary floor for the expression under test.

n = 200000
iters = 100
a = 3 ## i64
b = 17 ## i64
c = 5 ## i64

x = i64[n]
i = 0 ## i64
while i < n
  x[i] = i
  i = i + 1

# Warm both paths and fault in their output buffers.
y = (x .* a .+ b) .- c
manual = i64[n]
i = 0 ## i64
while i < n
  manual[i] = (x[i] * a + b) - c
  i = i + 1

t0 = ccall("__w_clock_ms")
k = 0 ## i64
while k < iters
  y = (x .* a .+ b) .- c
  k = k + 1
t1 = ccall("__w_clock_ms")
chain_ms = (t1 - t0 + ~0.0) / (iters + ~0.0)

t0 = ccall("__w_clock_ms")
k = 0 ## i64
while k < iters
  i = 0 ## i64
  while i < n
    manual[i] = (x[i] * a + b) - c
    i = i + 1
  k = k + 1
t1 = ccall("__w_clock_ms")
manual_ms = (t1 - t0 + ~0.0) / (iters + ~0.0)

checksum = 0 ## i64
i = 0 ## i64
while i < n
  if y[i] != manual[i]
    << "FAIL integer_fusion at " + i.to_s()
    exit(1)
  checksum = checksum + y[i]
  i = i + 1

<< "integer_chain n=" + n.to_s() + " avg_ms=" + chain_ms.to_s() + " checksum=" + checksum.to_s()
<< "integer_manual n=" + n.to_s() + " avg_ms=" + manual_ms.to_s() + " checksum=" + checksum.to_s()
