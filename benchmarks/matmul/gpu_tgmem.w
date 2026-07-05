# Probe: threadgroup (cooperative) memory as fast per-thread scratch.
# Each thread uses its own slice sm[i*TPG + ltid] -- no cross-thread sharing,
# so no barriers. Coalesced threadgroup layout (adjacent ltid -> adjacent addr).

## i32[]: out
## i32: n
@gpu fn tgtest(out, n)
  ltid = gpu.thread_position_in_threadgroup.x ## i32
  gtid = gpu.thread_position_in_grid.x ## i32
  sm = gpu.shared_i32(512)
  i = 0 ## i32
  acc = 0 ## i32
  i = 0
  while i < n
    sm[i * 32 + ltid] = i * gtid + 1
    i = i + 1
  i = 0
  acc = 0
  while i < n
    acc = acc + sm[i * 32 + ltid]
    i = i + 1
  out[gtid] = acc

use core/metal

msl = read_file("benchmarks/matmul/gpu_tgmem.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "tgtest")

N = 64
out_buf = metal_buffer(device, N * 4)
n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, 10)
queue = metal_queue(device)
metal_dispatch_groups(queue, pipeline, [out_buf, n_buf], 2, 32)
i = 0
while i < N
  << "out " + i.to_s() + " = " + metal_buffer_read_i32(out_buf, i).to_s()
  i += 1
