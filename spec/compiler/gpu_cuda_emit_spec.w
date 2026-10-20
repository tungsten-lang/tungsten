# spec: cuda-emit
# CUDA dialect emit smoke — `@gpu fn` → sibling .cu with expected markers.
#
# Compile with TUNGSTEN_GPU_DIALECTS=cuda (see scripts/test-specs.sh). The
# host binary only reads the emitted .cu text; no CUDA toolkit or GPU is
# required. Metal is also emitted as usual (text-only sidecar) and ignored.
#
# Run manually:
#   TUNGSTEN_GPU_DIALECTS=cuda bin/tungsten compile \
#     spec/compiler/gpu_cuda_emit_spec.w --out /tmp/gpu_cuda_emit
#   /tmp/gpu_cuda_emit

## f32[]: x
## f32[]: y
## i32: n
@gpu fn add_one(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  # Parenthesized occurrence-local hints stay on the expression AST. They
  # must emit a GPU scalar conversion, not trip the unsupported-node guard.
  wide_i = (i ## i64) ## i64
  if i < n
    y[i] = x[i] + 1.0

# Short-circuit logic in the GPU subset. `&&`, `||` and `!` used to be
# rejected with "unsupported expression node `and`", forcing nested ifs;
# MSL and CUDA are C++ dialects so they now pass straight through.
## f32[]: x
## f32[]: y
## i32: n
@gpu fn logic_ops(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i > 0 && i < n
    y[i] = x[i] + 1.0
  if i < 0 || i >= n
    y[i] = 0.0
  if !(i < n)
    y[i] = 0.0

# CUDA uses toolkit spellings for low-precision scalar parameters rather than
# leaking Metal's `bfloat` name into the sidecar.
## bf16: scale
@gpu fn low_precision_scalar(scale)
  value = 1 ## i32

# Device-address array arguments remain valid through helper signatures; the
# preflight address-space check only rejects incompatible local/shared arrays.
## f32[]: values
## f32: ret
@gpu fn first_value(values)
  values[0]

## f32[]: x
## f32[]: y
@gpu fn helper_call(x, y)
  y[0] = first_value(x)

# Warp-level FWHT butterfly shuffles, reductions, shared_i8, packed char4/uchar4, and dp4a.
## f32[]: x
## i32[]: q_packed
## i8x4[]: w_i8x4
## u8x4[]: w_u8x4
## f32[]: out
@gpu fn warp_hadamard_q8(x, q_packed, w_i8x4, w_u8x4, out)
  smem_q = gpu.shared_i8(128)
  lane = gpu.thread_index_in_simdgroup ## i32
  v = x[lane] ## f32
  p1 = simd_shuffle_xor(v, 1) ## f32
  p2 = simd_shuffle_down(p1, 2) ## f32
  p3 = simd_shuffle_up(p2, 1) ## f32
  p4 = simd_shuffle(p3, 0) ## f32
  p5 = simd_broadcast(p4, 0) ## f32
  s = simd_sum(p5) ## f32
  mx = simd_max(s) ## f32
  mn = simd_min(mx) ## f32
  bf = simd_broadcast_first(mn) ## f32
  smem_q[lane] = 1
  threadgroup_barrier()
  qa = q_packed[lane] ## i32
  qb = q_packed[0] ## i32
  acc = dp4a(qa, qb, 0) ## i32
  out[lane] = bf + float(acc) + float(smem_q[lane])

cu = read_file("spec/compiler/gpu_cuda_emit_spec.cu")

-> expect_marker(text, label, needle)
  if text.include?(needle)
    << "PASS " + label
  else
    << "FAIL " + label + " missing " + needle
    << "--- cu begin ---"
    << text
    << "--- cu end ---"
    exit 1

# Provenance header + CUDA includes from emit_gpu_kernels_cuda.
expect_marker(cu, "header.dialect", "CUDA C dialect")
expect_marker(cu, "include.runtime", "#include <cuda_runtime.h>")
expect_marker(cu, "include.fp16", "#include <cuda_fp16.h>")

# Kernel signature shape.
expect_marker(cu, "sig.extern", "extern")
expect_marker(cu, "sig.global", "__global__")
expect_marker(cu, "sig.name", "add_one")

# Thread/block builtins from the CUDA prologue.
expect_marker(cu, "builtin.threadIdx", "threadIdx")
expect_marker(cu, "builtin.blockIdx", "blockIdx")
expect_marker(cu, "builtin.blockDim", "blockDim")

# Body should lower the add.
expect_marker(cu, "body.add", "+")
expect_marker(cu, "body.expression_ascription", "long wide_i = long(i);")

# Short-circuit logic emits native C++ operators, not nested ifs.
expect_marker(cu, "sig.logic_ops", "logic_ops")
expect_marker(cu, "logic.and", "((i > 0) && (i < n))")
expect_marker(cu, "logic.or", "((i < 0) || (i >= n))")
expect_marker(cu, "logic.not", "(!(i < n))")
expect_marker(cu, "sig.bf16", "__nv_bfloat16 scale")
expect_marker(cu, "helper.signature", "__device__ float first_value(float *values)")
expect_marker(cu, "helper.return", "return values\[0];")
expect_marker(cu, "helper.call", "first_value(x)")

# Warp shuffles, reductions, shared_i8, packed vectors, and dp4a.
expect_marker(cu, "warp.char4_param", "char4 *w_i8x4")
expect_marker(cu, "warp.uchar4_param", "uchar4 *w_u8x4")
expect_marker(cu, "warp.shared_i8", "__shared__ char smem_q\[128];")
expect_marker(cu, "warp.shfl_xor", "__shfl_xor_sync(0xffffffffu, v, 1, 32)")
expect_marker(cu, "warp.shfl_down", "__shfl_down_sync(0xffffffffu, p1, 2, 32)")
expect_marker(cu, "warp.shfl_up", "__shfl_up_sync(0xffffffffu, p2, 1, 32)")
expect_marker(cu, "warp.shfl", "__shfl_sync(0xffffffffu, p3, 0, 32)")
expect_marker(cu, "warp.simd_sum", "__w_cuda_simd_sum(p5)")
expect_marker(cu, "warp.simd_max", "__w_cuda_simd_max(s)")
expect_marker(cu, "warp.simd_min", "__w_cuda_simd_min(mx)")
expect_marker(cu, "warp.dp4a", "__dp4a(qa, qb, 0)")

<< "gpu_cuda_emit_spec: all checks passed"
