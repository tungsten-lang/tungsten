# Tungsten matmul benchmark — direct Metal dispatch.
#
# This is the "no MLX layer" comparison row. We hand-write a naive
# Metal kernel (one thread per output element, no tiling, no
# threadgroup memory), compile it via metal_compile_source, and
# dispatch via Tungsten's core/metal facade. No MLX, no MPS, no
# Accelerate — pure Tungsten → Metal Shading Language → GPU.
#
# Naive expectation: a tiled MPS matmul will beat this by ~10×.
# The interesting question is whether the naive kernel still beats
# Accelerate (AMX) at large N, and where it sits relative to MLX's
# 7000 GFLOPS at N=2048.

use core/metal
use core/blas

# Inlined MSL source via StringBuffer — Tungsten strings can't span
# raw newlines, so we assemble with explicit "\n".
msl_src = StringBuffer(1024)
msl_src << "#include <metal_stdlib>\n"
msl_src << "using namespace metal;\n"
msl_src << "kernel void matmul_naive(\n"
msl_src << "    device const float* a \[\[ buffer(0) \]\],\n"
msl_src << "    device const float* b \[\[ buffer(1) \]\],\n"
msl_src << "    device float* c \[\[ buffer(2) \]\],\n"
msl_src << "    constant int& n \[\[ buffer(3) \]\],\n"
msl_src << "    uint gid \[\[ thread_position_in_grid \]\]\n"
msl_src << ") {\n"
msl_src << "    int i = gid / n;\n"
msl_src << "    int j = gid % n;\n"
msl_src << "    float acc = 0.0;\n"
msl_src << "    for (int k = 0; k < n; k++) {\n"
msl_src << "        acc += a\[i * n + k\] * b\[k * n + j\];\n"
msl_src << "    }\n"
msl_src << "    c\[i * n + j\] = acc;\n"
msl_src << "}\n"

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

device = metal_device()
library = metal_compile_source(device, msl_src.to_s)
pipeline = metal_pipeline(library, "matmul_naive")

# Page-aligned f32 arrays so metal_buffer_for can stay zero-copy.
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

# Warmup — amortize first-dispatch kernel JIT + GPU spin-up.
metal_dispatch_n(queue, pipeline, [a_buf, b_buf, c_buf, n_buf], size)
metal_dispatch_n(queue, pipeline, [a_buf, b_buf, c_buf, n_buf], size)

t0 = clock()
iter = 0
while iter < k_iters
  metal_dispatch_n(queue, pipeline, [a_buf, b_buf, c_buf, n_buf], size)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-metal-naive\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
