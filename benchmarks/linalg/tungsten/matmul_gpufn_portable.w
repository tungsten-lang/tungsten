# Portable Tungsten @gpu fn matmul — one thread per output element, plain
# while-loop dot product. Deliberately inside the CUDA/WGSL v0 emitter
# subset so the SAME kernel source benches Apple silicon (Metal dispatch)
# and NVIDIA silicon (TUNGSTEN_GPU_DIALECTS=cuda → nvcc).
#
#   bin/tungsten -o /tmp/mmp benchmarks/linalg/tungsten/matmul_gpufn_portable.w
#   /tmp/mmp <N> <iters> [msl_path]

use core/metal

## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_naive(a, b, c, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n * n
    row = i / n ## i32
    col = i % n ## i32
    acc = ~0.0 ## f32
    k = 0 ## i32
    while k < n
      acc = acc + a[row * n + k] * b[k * n + col]
      k = k + 1
    c[i] = acc

# Register-blocked variant: each thread computes a 4x4 output tile with 16
# scalar accumulators — 4x the arithmetic intensity of the naive kernel,
# still inside the portable (CUDA-emittable) subset. Requires n % 4 == 0.
## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_reg4(a, b, c, n)
  t = gpu.thread_position_in_grid.x ## i32
  nt = n / 4 ## i32
  if t < nt * nt
    tr = (t / nt) * 4 ## i32
    tc = (t % nt) * 4 ## i32
    acc00 = ~0.0 ## f32
    acc01 = ~0.0 ## f32
    acc02 = ~0.0 ## f32
    acc03 = ~0.0 ## f32
    acc10 = ~0.0 ## f32
    acc11 = ~0.0 ## f32
    acc12 = ~0.0 ## f32
    acc13 = ~0.0 ## f32
    acc20 = ~0.0 ## f32
    acc21 = ~0.0 ## f32
    acc22 = ~0.0 ## f32
    acc23 = ~0.0 ## f32
    acc30 = ~0.0 ## f32
    acc31 = ~0.0 ## f32
    acc32 = ~0.0 ## f32
    acc33 = ~0.0 ## f32
    k = 0 ## i32
    while k < n
      a0 = a[(tr + 0) * n + k] ## f32
      a1 = a[(tr + 1) * n + k] ## f32
      a2 = a[(tr + 2) * n + k] ## f32
      a3 = a[(tr + 3) * n + k] ## f32
      b0 = b[k * n + tc + 0] ## f32
      b1 = b[k * n + tc + 1] ## f32
      b2 = b[k * n + tc + 2] ## f32
      b3 = b[k * n + tc + 3] ## f32
      acc00 = acc00 + a0 * b0
      acc01 = acc01 + a0 * b1
      acc02 = acc02 + a0 * b2
      acc03 = acc03 + a0 * b3
      acc10 = acc10 + a1 * b0
      acc11 = acc11 + a1 * b1
      acc12 = acc12 + a1 * b2
      acc13 = acc13 + a1 * b3
      acc20 = acc20 + a2 * b0
      acc21 = acc21 + a2 * b1
      acc22 = acc22 + a2 * b2
      acc23 = acc23 + a2 * b3
      acc30 = acc30 + a3 * b0
      acc31 = acc31 + a3 * b1
      acc32 = acc32 + a3 * b2
      acc33 = acc33 + a3 * b3
      k = k + 1
    c[(tr + 0) * n + tc + 0] = acc00
    c[(tr + 0) * n + tc + 1] = acc01
    c[(tr + 0) * n + tc + 2] = acc02
    c[(tr + 0) * n + tc + 3] = acc03
    c[(tr + 1) * n + tc + 0] = acc10
    c[(tr + 1) * n + tc + 1] = acc11
    c[(tr + 1) * n + tc + 2] = acc12
    c[(tr + 1) * n + tc + 3] = acc13
    c[(tr + 2) * n + tc + 0] = acc20
    c[(tr + 2) * n + tc + 1] = acc21
    c[(tr + 2) * n + tc + 2] = acc22
    c[(tr + 2) * n + tc + 3] = acc23
    c[(tr + 3) * n + tc + 0] = acc30
    c[(tr + 3) * n + tc + 1] = acc31
    c[(tr + 3) * n + tc + 2] = acc32
    c[(tr + 3) * n + tc + 3] = acc33

# Shared-memory tiled variant: 16x16 threadgroup tiles staged through
# threadgroup/__shared__ memory with barriers — the classic k-tiling.
# Uses the gpu.shared_f32 + threadgroup_barrier() emitter surface, which
# the CUDA dialect maps to __shared__ + __syncthreads(). 2-D dispatch:
# (n/16, n/16) groups of (16, 16) threads. Requires n % 16 == 0.
## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_tile16(a, b, c, n)
  ta = gpu.shared_f32(256)
  tb = gpu.shared_f32(256)
  tx = gpu.thread_position_in_threadgroup.x ## i32
  ty = gpu.thread_position_in_threadgroup.y ## i32
  row = gpu.threadgroup_position_in_grid.y * 16 + ty ## i32
  col = gpu.threadgroup_position_in_grid.x * 16 + tx ## i32
  acc = ~0.0 ## f32
  kt = 0 ## i32
  while kt < n
    ta[ty * 16 + tx] = a[row * n + kt + tx]
    tb[ty * 16 + tx] = b[(kt + ty) * n + col]
    threadgroup_barrier()
    kk = 0 ## i32
    while kk < 16
      acc = acc + ta[ty * 16 + kk] * tb[kk * 16 + tx]
      kk = kk + 1
    threadgroup_barrier()
    kt = kt + 16
  c[row * n + col] = acc

# Combined variant: 64x64 block tiles staged through shared memory, each
# thread computing a 4x4 register tile — shared k-reuse AND register-level
# arithmetic intensity. 16x16 threads per group; n % 64 == 0.
## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_t64r4(a, b, c, n)
  ta = gpu.shared_f32(1024)
  tb = gpu.shared_f32(1024)
  tx = gpu.thread_position_in_threadgroup.x ## i32
  ty = gpu.thread_position_in_threadgroup.y ## i32
  lin = ty * 16 + tx ## i32
  brow = gpu.threadgroup_position_in_grid.y * 64 ## i32
  bcol = gpu.threadgroup_position_in_grid.x * 64 ## i32
  acc00 = ~0.0 ## f32
  acc01 = ~0.0 ## f32
  acc02 = ~0.0 ## f32
  acc03 = ~0.0 ## f32
  acc10 = ~0.0 ## f32
  acc11 = ~0.0 ## f32
  acc12 = ~0.0 ## f32
  acc13 = ~0.0 ## f32
  acc20 = ~0.0 ## f32
  acc21 = ~0.0 ## f32
  acc22 = ~0.0 ## f32
  acc23 = ~0.0 ## f32
  acc30 = ~0.0 ## f32
  acc31 = ~0.0 ## f32
  acc32 = ~0.0 ## f32
  acc33 = ~0.0 ## f32
  kt = 0 ## i32
  while kt < n
    e0 = lin * 4 ## i32
    l = 0 ## i32
    while l < 4
      e = e0 + l ## i32
      ta[e] = a[(brow + e / 16) * n + kt + e % 16]
      tb[e] = b[(kt + e / 64) * n + bcol + e % 64]
      l = l + 1
    threadgroup_barrier()
    kk = 0 ## i32
    while kk < 16
      a0 = ta[(ty * 4 + 0) * 16 + kk] ## f32
      a1 = ta[(ty * 4 + 1) * 16 + kk] ## f32
      a2 = ta[(ty * 4 + 2) * 16 + kk] ## f32
      a3 = ta[(ty * 4 + 3) * 16 + kk] ## f32
      b0 = tb[kk * 64 + tx * 4 + 0] ## f32
      b1 = tb[kk * 64 + tx * 4 + 1] ## f32
      b2 = tb[kk * 64 + tx * 4 + 2] ## f32
      b3 = tb[kk * 64 + tx * 4 + 3] ## f32
      acc00 = acc00 + a0 * b0
      acc01 = acc01 + a0 * b1
      acc02 = acc02 + a0 * b2
      acc03 = acc03 + a0 * b3
      acc10 = acc10 + a1 * b0
      acc11 = acc11 + a1 * b1
      acc12 = acc12 + a1 * b2
      acc13 = acc13 + a1 * b3
      acc20 = acc20 + a2 * b0
      acc21 = acc21 + a2 * b1
      acc22 = acc22 + a2 * b2
      acc23 = acc23 + a2 * b3
      acc30 = acc30 + a3 * b0
      acc31 = acc31 + a3 * b1
      acc32 = acc32 + a3 * b2
      acc33 = acc33 + a3 * b3
      kk = kk + 1
    threadgroup_barrier()
    kt = kt + 16
  r0 = brow + ty * 4 ## i32
  c0 = bcol + tx * 4 ## i32
  c[(r0 + 0) * n + c0 + 0] = acc00
  c[(r0 + 0) * n + c0 + 1] = acc01
  c[(r0 + 0) * n + c0 + 2] = acc02
  c[(r0 + 0) * n + c0 + 3] = acc03
  c[(r0 + 1) * n + c0 + 0] = acc10
  c[(r0 + 1) * n + c0 + 1] = acc11
  c[(r0 + 1) * n + c0 + 2] = acc12
  c[(r0 + 1) * n + c0 + 3] = acc13
  c[(r0 + 2) * n + c0 + 0] = acc20
  c[(r0 + 2) * n + c0 + 1] = acc21
  c[(r0 + 2) * n + c0 + 2] = acc22
  c[(r0 + 2) * n + c0 + 3] = acc23
  c[(r0 + 3) * n + c0 + 0] = acc30
  c[(r0 + 3) * n + c0 + 1] = acc31
  c[(r0 + 3) * n + c0 + 2] = acc32
  c[(r0 + 3) * n + c0 + 3] = acc33

# Vectorized variant of t64r4: the same 64x64 shared tiles + 4x4 register
# tile, but global memory moves through 128-bit float4 transactions —
# one gpu.load_f4 per array per thread per k-step, float4 stores for C.
## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_t64r4v(a, b, c, n)
  ta = gpu.shared_f32(1024)
  tb = gpu.shared_f32(1024)
  tx = gpu.thread_position_in_threadgroup.x ## i32
  ty = gpu.thread_position_in_threadgroup.y ## i32
  lin = ty * 16 + tx ## i32
  brow = gpu.threadgroup_position_in_grid.y * 64 ## i32
  bcol = gpu.threadgroup_position_in_grid.x * 64 ## i32
  acc00 = ~0.0 ## f32
  acc01 = ~0.0 ## f32
  acc02 = ~0.0 ## f32
  acc03 = ~0.0 ## f32
  acc10 = ~0.0 ## f32
  acc11 = ~0.0 ## f32
  acc12 = ~0.0 ## f32
  acc13 = ~0.0 ## f32
  acc20 = ~0.0 ## f32
  acc21 = ~0.0 ## f32
  acc22 = ~0.0 ## f32
  acc23 = ~0.0 ## f32
  acc30 = ~0.0 ## f32
  acc31 = ~0.0 ## f32
  acc32 = ~0.0 ## f32
  acc33 = ~0.0 ## f32
  e0 = lin * 4 ## i32
  eb = (lin / 16) * 64 + (lin % 16) * 4 ## i32
  kt = 0 ## i32
  while kt < n
    av = gpu.load_f4(a, ((brow + lin / 4) * n + kt) / 4 + lin % 4) ## f32x4
    bv = gpu.load_f4(b, ((kt + lin / 16) * n + bcol) / 4 + lin % 16) ## f32x4
    ta[e0 + 0] = av.x
    ta[e0 + 1] = av.y
    ta[e0 + 2] = av.z
    ta[e0 + 3] = av.w
    tb[eb + 0] = bv.x
    tb[eb + 1] = bv.y
    tb[eb + 2] = bv.z
    tb[eb + 3] = bv.w
    threadgroup_barrier()
    kk = 0 ## i32
    while kk < 16
      a0 = ta[(ty * 4 + 0) * 16 + kk] ## f32
      a1 = ta[(ty * 4 + 1) * 16 + kk] ## f32
      a2 = ta[(ty * 4 + 2) * 16 + kk] ## f32
      a3 = ta[(ty * 4 + 3) * 16 + kk] ## f32
      b0 = tb[kk * 64 + tx * 4 + 0] ## f32
      b1 = tb[kk * 64 + tx * 4 + 1] ## f32
      b2 = tb[kk * 64 + tx * 4 + 2] ## f32
      b3 = tb[kk * 64 + tx * 4 + 3] ## f32
      acc00 = acc00 + a0 * b0
      acc01 = acc01 + a0 * b1
      acc02 = acc02 + a0 * b2
      acc03 = acc03 + a0 * b3
      acc10 = acc10 + a1 * b0
      acc11 = acc11 + a1 * b1
      acc12 = acc12 + a1 * b2
      acc13 = acc13 + a1 * b3
      acc20 = acc20 + a2 * b0
      acc21 = acc21 + a2 * b1
      acc22 = acc22 + a2 * b2
      acc23 = acc23 + a2 * b3
      acc30 = acc30 + a3 * b0
      acc31 = acc31 + a3 * b1
      acc32 = acc32 + a3 * b2
      acc33 = acc33 + a3 * b3
      kk = kk + 1
    threadgroup_barrier()
    kt = kt + 16
  r0 = brow + ty * 4 ## i32
  c0 = bcol + tx * 4 ## i32
  gpu.store_f4(c, ((r0 + 0) * n + c0) / 4, gpu.f4(acc00, acc01, acc02, acc03))
  gpu.store_f4(c, ((r0 + 1) * n + c0) / 4, gpu.f4(acc10, acc11, acc12, acc13))
  gpu.store_f4(c, ((r0 + 2) * n + c0) / 4, gpu.f4(acc20, acc21, acc22, acc23))
  gpu.store_f4(c, ((r0 + 3) * n + c0) / 4, gpu.f4(acc30, acc31, acc32, acc33))

# Tensor-core variant (CUDA-only; Metal's analog is the simdgroup_* surface):
# one warp per 16x16 output tile through wmma bf16 fragments with f32
# accumulation. Launch: grid (n/16, n/16), block 32 threads (one warp).
## bf16[]: a
## bf16[]: b
## f32[]: c
## i32: n
@gpu fn matmul_wmma_bf16(a, b, c, n)
  am = gpu.wmma_frag_a_bf16()
  bm = gpu.wmma_frag_b_bf16()
  cm = gpu.wmma_frag_acc_f32()
  gpu.wmma_fill(cm, ~0.0)
  row = gpu.threadgroup_position_in_grid.y * 16 ## i32
  col = gpu.threadgroup_position_in_grid.x * 16 ## i32
  k = 0 ## i32
  while k < n
    gpu.wmma_load(am, a, row * n + k, n)
    gpu.wmma_load(bm, b, k * n + col, n)
    gpu.wmma_mma(cm, am, bm, cm)
    k = k + 16
  gpu.wmma_store(c, row * n + col, n, cm)

# Fragment-blocked tensor-core variant: one warp owns a 64x64 output tile as
# a 4x4 grid of wmma fragments — 8 loads feed 16 mma ops per k-step (4x the
# operand reuse of the single-fragment version). CUDA-only.
## bf16[]: a
## bf16[]: b
## f32[]: c
## i32: n
@gpu fn matmul_wmma4_bf16(a, b, c, n)
  am0 = gpu.wmma_frag_a_bf16()
  am1 = gpu.wmma_frag_a_bf16()
  am2 = gpu.wmma_frag_a_bf16()
  am3 = gpu.wmma_frag_a_bf16()
  bm0 = gpu.wmma_frag_b_bf16()
  bm1 = gpu.wmma_frag_b_bf16()
  bm2 = gpu.wmma_frag_b_bf16()
  bm3 = gpu.wmma_frag_b_bf16()
  cm00 = gpu.wmma_frag_acc_f32()
  cm01 = gpu.wmma_frag_acc_f32()
  cm02 = gpu.wmma_frag_acc_f32()
  cm03 = gpu.wmma_frag_acc_f32()
  cm10 = gpu.wmma_frag_acc_f32()
  cm11 = gpu.wmma_frag_acc_f32()
  cm12 = gpu.wmma_frag_acc_f32()
  cm13 = gpu.wmma_frag_acc_f32()
  cm20 = gpu.wmma_frag_acc_f32()
  cm21 = gpu.wmma_frag_acc_f32()
  cm22 = gpu.wmma_frag_acc_f32()
  cm23 = gpu.wmma_frag_acc_f32()
  cm30 = gpu.wmma_frag_acc_f32()
  cm31 = gpu.wmma_frag_acc_f32()
  cm32 = gpu.wmma_frag_acc_f32()
  cm33 = gpu.wmma_frag_acc_f32()
  gpu.wmma_fill(cm00, ~0.0)
  gpu.wmma_fill(cm01, ~0.0)
  gpu.wmma_fill(cm02, ~0.0)
  gpu.wmma_fill(cm03, ~0.0)
  gpu.wmma_fill(cm10, ~0.0)
  gpu.wmma_fill(cm11, ~0.0)
  gpu.wmma_fill(cm12, ~0.0)
  gpu.wmma_fill(cm13, ~0.0)
  gpu.wmma_fill(cm20, ~0.0)
  gpu.wmma_fill(cm21, ~0.0)
  gpu.wmma_fill(cm22, ~0.0)
  gpu.wmma_fill(cm23, ~0.0)
  gpu.wmma_fill(cm30, ~0.0)
  gpu.wmma_fill(cm31, ~0.0)
  gpu.wmma_fill(cm32, ~0.0)
  gpu.wmma_fill(cm33, ~0.0)
  row = gpu.threadgroup_position_in_grid.y * 64 ## i32
  col = gpu.threadgroup_position_in_grid.x * 64 ## i32
  k = 0 ## i32
  while k < n
    gpu.wmma_load(am0, a, (row + 0) * n + k, n)
    gpu.wmma_load(am1, a, (row + 16) * n + k, n)
    gpu.wmma_load(am2, a, (row + 32) * n + k, n)
    gpu.wmma_load(am3, a, (row + 48) * n + k, n)
    gpu.wmma_load(bm0, b, k * n + col + 0, n)
    gpu.wmma_load(bm1, b, k * n + col + 16, n)
    gpu.wmma_load(bm2, b, k * n + col + 32, n)
    gpu.wmma_load(bm3, b, k * n + col + 48, n)
    gpu.wmma_mma(cm00, am0, bm0, cm00)
    gpu.wmma_mma(cm01, am0, bm1, cm01)
    gpu.wmma_mma(cm02, am0, bm2, cm02)
    gpu.wmma_mma(cm03, am0, bm3, cm03)
    gpu.wmma_mma(cm10, am1, bm0, cm10)
    gpu.wmma_mma(cm11, am1, bm1, cm11)
    gpu.wmma_mma(cm12, am1, bm2, cm12)
    gpu.wmma_mma(cm13, am1, bm3, cm13)
    gpu.wmma_mma(cm20, am2, bm0, cm20)
    gpu.wmma_mma(cm21, am2, bm1, cm21)
    gpu.wmma_mma(cm22, am2, bm2, cm22)
    gpu.wmma_mma(cm23, am2, bm3, cm23)
    gpu.wmma_mma(cm30, am3, bm0, cm30)
    gpu.wmma_mma(cm31, am3, bm1, cm31)
    gpu.wmma_mma(cm32, am3, bm2, cm32)
    gpu.wmma_mma(cm33, am3, bm3, cm33)
    k = k + 16
  gpu.wmma_store(c, (row + 0) * n + col + 0, n, cm00)
  gpu.wmma_store(c, (row + 0) * n + col + 16, n, cm01)
  gpu.wmma_store(c, (row + 0) * n + col + 32, n, cm02)
  gpu.wmma_store(c, (row + 0) * n + col + 48, n, cm03)
  gpu.wmma_store(c, (row + 16) * n + col + 0, n, cm10)
  gpu.wmma_store(c, (row + 16) * n + col + 16, n, cm11)
  gpu.wmma_store(c, (row + 16) * n + col + 32, n, cm12)
  gpu.wmma_store(c, (row + 16) * n + col + 48, n, cm13)
  gpu.wmma_store(c, (row + 32) * n + col + 0, n, cm20)
  gpu.wmma_store(c, (row + 32) * n + col + 16, n, cm21)
  gpu.wmma_store(c, (row + 32) * n + col + 32, n, cm22)
  gpu.wmma_store(c, (row + 32) * n + col + 48, n, cm23)
  gpu.wmma_store(c, (row + 48) * n + col + 0, n, cm30)
  gpu.wmma_store(c, (row + 48) * n + col + 16, n, cm31)
  gpu.wmma_store(c, (row + 48) * n + col + 32, n, cm32)
  gpu.wmma_store(c, (row + 48) * n + col + 48, n, cm33)

args = argv()
n = 1024
if args.size() > 0
  n = args[0].to_i
k_iters = 5
if args.size() > 1
  k_iters = args[1].to_i

size = n * n

kname = "matmul_naive"
if args.size() > 2
  kname = args[2]
tg = 256
if args.size() > 3
  tg = args[3].to_i

msl_path = nil
if args.size() > 4
  msl_path = args[4]
if msl_path == nil
  msl_path = "benchmarks/linalg/tungsten/matmul_gpufn_portable.metal"

msl = read_file(msl_path)
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, kname)

a = metal_array(-32, size)
b = metal_array(-32, size)
c = metal_array(-32, size)
i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

a_buf = metal_buffer_for(device, a)
b_buf = metal_buffer_for(device, b)
c_buf = metal_buffer_for(device, c)
n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, n)

queue = metal_queue(device)
total_threads = size
if kname == "matmul_reg4"
  total_threads = (n / 4) * (n / 4)
n_groups = (total_threads + tg - 1) / tg
bufs = [a_buf, b_buf, c_buf, n_buf]

gx = n_groups
gy = 1
bx = tg
by = 1
if kname == "matmul_tile16"
  gx = n / 16
  gy = n / 16
  bx = 16
  by = 16
if kname == "matmul_t64r4" || kname == "matmul_t64r4v"
  gx = n / 64
  gy = n / 64
  bx = 16
  by = 16

metal_dispatch_3d(queue, pipeline, bufs, gx, gy, 1, bx, by, 1)
metal_dispatch_3d(queue, pipeline, bufs, gx, gy, 1, bx, by, 1)

t0 = clock()
iter = 0
while iter < k_iters
  metal_dispatch_3d(queue, pipeline, bufs, gx, gy, 1, bx, by, 1)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
avg_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"" + kname + "-metal\",\"tg\":" + tg.to_s + ",\"N\":" + n.to_s + ",\"K\":" + k_iters.to_s + ",\"avg_ms\":" + avg_ms.to_s + ",\"gflops\":" + gflops.to_s + ",\"c7\":" + c[7].to_s + "}"
