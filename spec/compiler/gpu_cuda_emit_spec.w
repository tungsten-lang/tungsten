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

# Short-circuit logic emits native C++ operators, not nested ifs.
expect_marker(cu, "sig.logic_ops", "logic_ops")
expect_marker(cu, "logic.and", "((i > 0) && (i < n))")
expect_marker(cu, "logic.or", "((i < 0) || (i >= n))")
expect_marker(cu, "logic.not", "(!(i < n))")

<< "gpu_cuda_emit_spec: all checks passed"
