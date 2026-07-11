# Elementwise chain: y = sin(a*x + b) + c  over n points.
# Reference for fusion work; compare to Python/NumPy/Numba/JAX via run.sh
#
# Four variants:
#   tungsten_fused   — the array-expression form `(x .* a .+ b).sin() .+ c`;
#                      the compiler fuses the whole tree into one raw loop
#                      (no temporaries), LLVM + -fveclib vectorizes it
#                      (_simd_sin_d2), and the runtime AUTO-SELECTS the
#                      backend by size: single-core below 32k elements,
#                      4 threads to 128k, 8 above (measured inflections;
#                      TUNGSTEN_FUSED_* env overrides). The JAX/XLA peer,
#                      parallelism included.
#   tungsten_threads — the same partitioning written by hand with
#                      Thread.new — what tungsten_fused now does for you.
#   tungsten_typed   — hand-written loop over preallocated f64[] buffers,
#                      the numba @njit peer.
#   tungsten_boxed   — growable boxed array via push, the naive form; kept
#                      to show what boxing costs.
#
# NOTE: the worker fn takes x/y/a/b/c via main-scope captures snapshotted at
# Thread.new, NOT via typed fn params of an intermediate helper — capturing a
# RAW-f64 param slot into a block mis-boxes it (+2^48 in the bits; e.g. 2.5
# arrives as 2.625). TODO: fix closure capture of raw-typed slots in lowering.

-> fill_range(y, x, a, b, c, lo, hi) (f64[] f64[] f64 f64 f64 i64 i64) i64
  i = lo ## i64
  while i < hi
    y[i] = Math.sin(a * x[i] + b) + c
    i = i + 1
  0

n = 200000
a = ~2.0
b = ~0.5
c = ~0.1

# ---- typed variant ----
x = f64[n]
i = 0 ## i64
while i < n
  x[i] = (i + ~0.0) * ~0.00001
  i = i + 1

y = f64[n]
# warmup
i = 0 ## i64
while i < n
  y[i] = Math.sin(a * x[i] + b) + c
  i = i + 1

t0 = ccall("__w_clock_ms")
iters = 50
k = 0
while k < iters
  i = 0 ## i64
  while i < n
    y[i] = Math.sin(a * x[i] + b) + c
    i = i + 1
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n
  s = s + y[i]
  i = i + 1
<< "tungsten_typed n=" + n.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s()

# ---- fused array-expression variant ----
yf = (x .* a .+ b).sin() .+ c

t0 = ccall("__w_clock_ms")
iters = 50
k = 0
while k < iters
  yf = (x .* a .+ b).sin() .+ c
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n
  s = s + yf[i]
  i = i + 1
<< "tungsten_fused n=" + n.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s()

# ---- fused + ## reuse (persistent output buffer, no alloc per iteration) ----
yr = (x .* a .+ b).sin() .+ c ## reuse
t0 = ccall("__w_clock_ms")
iters = 50
k = 0
while k < iters
  yr = (x .* a .+ b).sin() .+ c ## reuse
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n
  s = s + yr[i]
  i = i + 1
<< "tungsten_fused_reuse n=" + n.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s()

# ---- multithreaded typed loop ----
NT = 8
yt = f64[n]
workers = []
t = 0
while t < NT
  lo = (n * t) / NT
  hi = (n * (t + 1)) / NT
  w = Thread.new ->
    bw = fill_range(yt, x, a, b, c, lo, hi)
  workers.push(w)
  t = t + 1
wj = 0
while wj < workers.size()
  workers[wj].join
  wj = wj + 1

t0 = ccall("__w_clock_ms")
iters = 50
k = 0
while k < iters
  workers = []
  t = 0
  while t < NT
    lo = (n * t) / NT
    hi = (n * (t + 1)) / NT
    w = Thread.new ->
      bw = fill_range(yt, x, a, b, c, lo, hi)
    workers.push(w)
    t = t + 1
  wj = 0
  while wj < workers.size()
    workers[wj].join
    wj = wj + 1
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n
  s = s + yt[i]
  i = i + 1
<< "tungsten_threads n=" + n.to_s() + " nt=" + NT.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s()

# ---- boxed variant ----
yb = []
i = 0
while i < n
  yb = yb.push(Math.sin(a * x[i] + b) + c)
  i = i + 1

t0 = ccall("__w_clock_ms")
iters = 5
k = 0
while k < iters
  yb = []
  i = 0
  while i < n
    yb = yb.push(Math.sin(a * x[i] + b) + c)
    i = i + 1
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0
while i < n
  s = s + yb[i]
  i = i + 1
<< "tungsten_boxed n=" + n.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s()
