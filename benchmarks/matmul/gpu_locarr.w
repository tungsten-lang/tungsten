# Probe: does the @gpu emitter support THREAD-PRIVATE arrays inside a kernel?
# If so, each walker's scheme can live in fast private memory instead of slow
# device/global memory -- the key perf lever.

## i32[]: out
## i32: n
@gpu fn locarr(out, n)
  tid = gpu.thread_position_in_grid.x ## i32
  buf = i32[64]
  i = 0 ## i32
  while i < n
    buf[i] = i * tid + 1
    i = i + 1
  acc = 0 ## i32
  i = 0
  while i < n
    acc = acc + buf[i]
    i = i + 1
  out[tid] = acc

use core/metal

msl = read_file("benchmarks/matmul/gpu_locarr.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "locarr")

N = 8
out_buf = metal_buffer(device, N * 4)
n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, 10)
queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [out_buf, n_buf], N)
i = 0
while i < N
  << "out " + i.to_s() + " = " + metal_buffer_read_i32(out_buf, i).to_s()
  i += 1
