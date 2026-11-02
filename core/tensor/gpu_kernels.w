# Metal 4 cooperative tensor and f32 elementwise/softmax GPU kernels.

use core/metal

# ---- GPU linear-layer matmul via Metal 4 cooperative tensors --------------
#
# The f16_matmul_m4 kernel computes C[M,N] = A[M,K] · B[N,K]^T (the ML weight
# convention) using mpp::tensor_ops::matmul2d on `tensor<...>` params bound from
# the host argument table — i.e. it consumes Tensor's `.metal_tensor` faces for
# COMPUTE, the payoff of "plays nicely with the Metal 4 tensor". `\[\[ \]\]`
# escapes the attribute syntax from Tungsten string interpolation.

-> build_tensor_m4_kernel(elem, out_elem, kname)
  s = StringBuffer(2048)
  s << "#include <metal_stdlib>\n"
  s << "#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>\n"
  s << "using namespace metal;\n"
  s << "using namespace mpp;\n"
  s << "using namespace mpp::tensor_ops;\n"
  s << "kernel void " + kname + "(\n"
  s << "    tensor<device " + elem + ", dextents<int32_t, 2>> A \[\[buffer(0)\]\],\n"
  s << "    tensor<device " + elem + ", dextents<int32_t, 2>> B \[\[buffer(1)\]\],\n"
  s << "    tensor<device " + out_elem + ", dextents<int32_t, 2>> C \[\[buffer(2)\]\],\n"
  s << "    uint2 tgid \[\[threadgroup_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    constexpr auto desc = matmul2d_descriptor(\n"
  s << "        64, 32, static_cast<int>(metal::dynamic_extent), false, true, false);\n"
  s << "    matmul2d<desc, execution_simdgroups<4>> op;\n"
  s << "    auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);\n"
  s << "    auto mB = B.slice<dynamic_length_v<int32_t>, 32>(0, tgid.y * 32);\n"
  s << "    auto mC = C.slice<32, 64>(tgid.y * 32, tgid.x * 64);\n"
  s << "    op.run(mA, mB, mC);\n"
  s << "}\n"
  s.to_s()

# Lazy singleton: built on first .linear call (NOT at module load — a CPU-only
# Tensor program shouldn't compile an MTL4 pipeline at startup). Mutable holder
# because top-level globals can't be reassigned from a fn.
TENSOR_M4 = {}
-> tensor_m4_state(dt)
  key = :f16
  elem = "half"
  out_elem = "float"
  kname = "f16_matmul_m4"
  if dt == 121
    key = :bf16
    elem = "bfloat"
    out_elem = "float"
    kname = "bf16_matmul_m4"
  elsif dt == 45
    key = :i8
    elem = "int8_t"
    out_elem = "int32_t"
    kname = "i8_matmul_m4"
  if TENSOR_M4[key] == nil
    device = metal_device()
    compiler = metal4_compiler(device)
    queue = metal4_queue(device)
    alloc = metal4_allocator(device)
    lib = metal_compile_source(device, build_tensor_m4_kernel(elem, out_elem, kname))
    pipe = metal4_pipeline(compiler, lib, kname, 128, 1, 1)
    TENSOR_M4[key] = {:device => device, :queue => queue, :alloc => alloc, :pipe => pipe}
  TENSOR_M4[key]

# ---- GPU elementwise (legacy buffer kernel) -------------------------------
#
# A generic 1-D f32 elementwise kernel over the buffer faces: one thread per
# element, op selected by an int (0=add 1=sub 2=mul 3=div). Routes the
# same-shape contiguous f32 path here; broadcast / other dtypes / small sizes
# stay on the CPU reference. `\[ \]` escapes both attribute syntax and MSL
# array indexing from Tungsten string interpolation.

-> build_tensor_ew_kernel
  s = StringBuffer(4096)
  s << "#include <metal_stdlib>\n"
  s << "using namespace metal;\n"
  s << "inline float tensor_tg_max(float value, threadgroup float* scratch, uint lane, uint simd_id, uint simd_count) {\n"
  s << "    float partial = simd_max(value);\n"
  s << "    if (lane == 0) scratch\[simd_id\] = partial;\n"
  s << "    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "    partial = lane < simd_count ? scratch\[lane\] : -INFINITY;\n"
  s << "    float total = simd_id == 0 ? simd_max(partial) : -INFINITY;\n"
  s << "    if (simd_id == 0 && lane == 0) scratch\[0\] = total;\n"
  s << "    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "    return scratch\[0\];\n"
  s << "}\n"
  s << "inline float tensor_tg_sum(float value, threadgroup float* scratch, uint lane, uint simd_id, uint simd_count) {\n"
  s << "    float partial = simd_sum(value);\n"
  s << "    if (lane == 0) scratch\[simd_id\] = partial;\n"
  s << "    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "    partial = lane < simd_count ? scratch\[lane\] : 0.0f;\n"
  s << "    float total = simd_id == 0 ? simd_sum(partial) : 0.0f;\n"
  s << "    if (simd_id == 0 && lane == 0) scratch\[0\] = total;\n"
  s << "    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "    return scratch\[0\];\n"
  s << "}\n"
  s << "kernel void elementwise_f32(\n"
  s << "    device const float* a \[\[buffer(0)\]\],\n"
  s << "    device const float* b \[\[buffer(1)\]\],\n"
  s << "    device float* c \[\[buffer(2)\]\],\n"
  s << "    constant int& op \[\[buffer(3)\]\],\n"
  s << "    constant int& n \[\[buffer(4)\]\],\n"
  s << "    uint gid \[\[thread_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    if (gid >= uint(n)) return;\n"
  s << "    float av = a\[gid\];\n"
  s << "    float bv = b\[gid\];\n"
  s << "    float r = av + bv;\n"
  s << "    if (op == 1) r = av - bv;\n"
  s << "    else if (op == 2) r = av * bv;\n"
  s << "    else if (op == 3) r = av / bv;\n"
  s << "    c\[gid\] = r;\n"
  s << "}\n"
  s << "kernel void softmax_rows_f32(\n"
  s << "    device const float* x \[\[buffer(0)\]\],\n"
  s << "    device float* y \[\[buffer(1)\]\],\n"
  s << "    constant int& rows \[\[buffer(2)\]\],\n"
  s << "    constant int& cols \[\[buffer(3)\]\],\n"
  s << "    uint gid \[\[thread_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    if (gid >= uint(rows)) return;\n"
  s << "    device const float* row = x + gid * cols;\n"
  s << "    device float* out = y + gid * cols;\n"
  s << "    float mx = row\[0\];\n"
  s << "    for (int j = 1; j < cols; j++) mx = max(mx, row\[j\]);\n"
  s << "    float sm = 0.0f;\n"
  s << "    for (int j = 0; j < cols; j++) { float e = exp(row\[j\] - mx); out\[j\] = e; sm += e; }\n"
  s << "    for (int j = 0; j < cols; j++) out\[j\] /= sm;\n"
  s << "}\n"
  s << "kernel void softmax_rows_parallel_f32(\n"
  s << "    device const float* x \[\[buffer(0)\]\],\n"
  s << "    device float* y \[\[buffer(1)\]\],\n"
  s << "    constant int& rows \[\[buffer(2)\]\],\n"
  s << "    constant int& cols \[\[buffer(3)\]\],\n"
  s << "    uint3 tg_pos \[\[threadgroup_position_in_grid\]\],\n"
  s << "    uint3 tg_size \[\[threads_per_threadgroup\]\],\n"
  s << "    uint tid \[\[thread_index_in_threadgroup\]\],\n"
  s << "    uint lane \[\[thread_index_in_simdgroup\]\],\n"
  s << "    uint simd_id \[\[simdgroup_index_in_threadgroup\]\]\n"
  s << ") {\n"
  s << "    uint row_id = tg_pos.x;\n"
  s << "    if (row_id >= uint(rows)) return;\n"
  s << "    threadgroup float scratch\[32\];\n"
  s << "    device const float* row = x + row_id * cols;\n"
  s << "    device float* out = y + row_id * cols;\n"
  s << "    float local_max = -INFINITY;\n"
  s << "    for (uint j = tid; j < uint(cols); j += tg_size.x) local_max = max(local_max, row\[j\]);\n"
  s << "    float mx = tensor_tg_max(local_max, scratch, lane, simd_id, (tg_size.x + 31) / 32);\n"
  s << "    float local_sum = 0.0f;\n"
  s << "    for (uint j = tid; j < uint(cols); j += tg_size.x) { float e = exp(row\[j\] - mx); out\[j\] = e; local_sum += e; }\n"
  s << "    float sm = tensor_tg_sum(local_sum, scratch, lane, simd_id, (tg_size.x + 31) / 32);\n"
  s << "    for (uint j = tid; j < uint(cols); j += tg_size.x) out\[j\] /= sm;\n"
  s << "}\n"
  s.to_s()

TENSOR_EW = {}
-> tensor_ew_state
  if TENSOR_EW[:state] == nil
    device = metal_device()
    queue = metal_queue(device)
    lib = metal_compile_source(device, build_tensor_ew_kernel())
    pipe = metal_pipeline(lib, "elementwise_f32")
    softmax_pipe = metal_pipeline(lib, "softmax_rows_f32")
    # Keep the cooperative pipeline lazy: elementwise-only and short-row
    # workloads should not pay its pipeline construction cost.
    TENSOR_EW[:state] = {:device => device, :queue => queue, :lib => lib, :pipe => pipe, :softmax_pipe => softmax_pipe}
  TENSOR_EW[:state]

