# GPU (Metal) fusion-chain benchmark — y = sin(a*x + b) + c as a @gpu kernel.
#
# f32 end-to-end: MSL has no double, so this row is NOT bit-comparable to the
# f64 CPU rows in fusion_bench.w — sums land close but not equal. Buffers are
# zero-copy wraps of page-aligned typed arrays (metal_array + metal_buffer_for)
# and stay resident across iterations; what's timed is dispatch + compute.
#
#   tungsten_gpu        — one synchronous dispatch per iteration (each waits
#                         for completion: honest per-call round-trip latency)
#   tungsten_gpu_batch  — all iterations encoded into one command buffer;
#                         amortizes the per-dispatch sync overhead
#
# Run at n=200k (the fusion_bench.w workload) and n=20M (where the GPU's
# bandwidth actually gets used). The 20M block includes a threaded f64 CPU
# reference (same NT=8 partitioning as fusion_bench.w) for the crossover.

use core/metal

## f32[]: x
## f32[]: y
## i32: n
@gpu fn fuse_chain(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    y[i] = sin(2.0 * x[i] + 0.5) + 0.1

-> fill_range(y, x, a, b, c, lo, hi) (f64[] f64[] f64 f64 f64 i64 i64) i64
  i = lo ## i64
  while i < hi
    y[i] = Math.sin(a * x[i] + b) + c
    i = i + 1
  0

device = metal_device()
msl = read_file("fusion_gpu_bench.metal")
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "fuse_chain")
queue = metal_queue(device)

# ---------------- n = 200,000 (the fusion_bench.w workload) ----------------
n = 200000
x = metal_array(-32, n)
i = 0 ## i64
while i < n
  x[i] = (i + ~0.0) * ~0.00001
  i = i + 1
y = metal_array(-32, n)

xb = metal_buffer_for(device, x)
yb = metal_buffer_for(device, y)
nb = metal_buffer(device, 4)
metal_buffer_write_i32(nb, 0, n)
bufs = [xb, yb, nb]

metal_dispatch_n(queue, pipeline, bufs, n)

iters = 50
t0 = ccall("__w_clock_ms")
k = 0
while k < iters
  metal_dispatch_n(queue, pipeline, bufs, n)
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n
  s = s + y[i]
  i = i + 1
<< "tungsten_gpu n=" + n.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s() + " (f32)"

t0 = ccall("__w_clock_ms")
metal_batch_begin(queue)
k = 0
while k < iters
  metal_dispatch_n(queue, pipeline, bufs, n)
  k = k + 1
metal_batch_commit(queue)
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
<< "tungsten_gpu_batch n=" + n.to_s() + " avg_ms=" + ms.to_s() + " (f32)"

# ---------------- n = 20,000,000 (bandwidth regime) ----------------
n2 = 20000000
x2 = metal_array(-32, n2)
i = 0 ## i64
while i < n2
  x2[i] = (i + ~0.0) * ~0.0000001
  i = i + 1
y2 = metal_array(-32, n2)

xb2 = metal_buffer_for(device, x2)
yb2 = metal_buffer_for(device, y2)
nb2 = metal_buffer(device, 4)
metal_buffer_write_i32(nb2, 0, n2)
bufs2 = [xb2, yb2, nb2]

metal_dispatch_n(queue, pipeline, bufs2, n2)

iters2 = 20
t0 = ccall("__w_clock_ms")
k = 0
while k < iters2
  metal_dispatch_n(queue, pipeline, bufs2, n2)
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters2 + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n2
  s = s + y2[i]
  i = i + 1
<< "tungsten_gpu n=" + n2.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s() + " (f32)"

# Threaded f64 CPU reference at 20M (same shape as fusion_bench.w's
# tungsten_threads row).
xd = f64[n2]
i = 0 ## i64
while i < n2
  xd[i] = (i + ~0.0) * ~0.0000001
  i = i + 1
yd = f64[n2]
a = ~2.0
b = ~0.5
c = ~0.1
NT = 8

workers = []
t = 0
while t < NT
  lo = (n2 * t) / NT
  hi = (n2 * (t + 1)) / NT
  w = Thread.new ->
    bw = fill_range(yd, xd, a, b, c, lo, hi)
  workers.push(w)
  t = t + 1
wj = 0
while wj < workers.size()
  workers[wj].join
  wj = wj + 1

t0 = ccall("__w_clock_ms")
k = 0
while k < iters2
  workers = []
  t = 0
  while t < NT
    lo = (n2 * t) / NT
    hi = (n2 * (t + 1)) / NT
    w = Thread.new ->
      bw = fill_range(yd, xd, a, b, c, lo, hi)
    workers.push(w)
    t = t + 1
  wj = 0
  while wj < workers.size()
    workers[wj].join
    wj = wj + 1
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters2 + ~0.0)
s = ~0.0
i = 0 ## i64
while i < n2
  s = s + yd[i]
  i = i + 1
<< "tungsten_threads n=" + n2.to_s() + " nt=" + NT.to_s() + " avg_ms=" + ms.to_s() + " sum=" + s.to_s() + " (f64)"
