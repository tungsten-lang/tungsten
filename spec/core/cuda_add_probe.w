# CUDA dialect emit probe — compiles a trivial @gpu kernel and checks that
# the sibling .cu sidecar contains the expected CUDA markers. No GPU required
# for the emit check; a host harness under benchmarks/ can run it on NVIDIA.

## f32[]: x
## f32[]: y
## i32: n
@gpu fn add_one(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    y[i] = x[i] + 1.0

# After `tungsten compile` this file's sibling .cu is written next to the source.
cu = read_file("spec/core/cuda_add_probe.cu")
if cu == nil
  << "cuda emit FAILED: no .cu sidecar (compile this file first)"
  exit 1

ok = true
if !cu.include?("__global__")
  << "cuda emit FAILED: missing __global__"
  ok = false
if !cu.include?("add_one")
  << "cuda emit FAILED: missing kernel name"
  ok = false
if !cu.include?("threadIdx") && !cu.include?("blockIdx")
  << "cuda emit FAILED: missing thread/block indices"
  ok = false
if !cu.include?("float *x")
  << "cuda emit FAILED: missing float *x param"
  ok = false

if ok
  << "cuda emit ok"
else
  exit 1
