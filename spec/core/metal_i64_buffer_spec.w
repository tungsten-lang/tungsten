# End-to-end 64-bit Metal integer smoke. This covers both pieces needed by
# exact bit-mask search: device i64 buffers and threadgroup i64 scratch.

use core/metal

## i64[]: input
## i64[]: output
@gpu fn roundtrip_i64(input, output)
  tid = gpu.thread_position_in_grid.x ## i32
  lane = gpu.thread_position_in_threadgroup.x ## i32
  scratch = gpu.shared_i64(8)
  scratch[lane] = input[tid]
  output[tid] = scratch[lane] ^ 34359738368

msl = read_file("spec/core/metal_i64_buffer_spec.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "roundtrip_i64")

input = metal_buffer(device, 64)
output = metal_buffer(device, 64)
i = 0
while i < 8
  metal_buffer_write_i64(input, i, 68719476735 - i)
  i += 1

queue = metal_queue(device)
metal_dispatch_groups(queue, pipeline, [input, output], 1, 8)

i = 0
while i < 8
  want = (68719476735 - i) ^ 34359738368
  got = metal_buffer_read_i64(output, i)
  if got != want
    << "metal i64 smoke FAILED at " + i.to_s() + ": got " + got.to_s() + ", want " + want.to_s()
    exit 1
  i += 1
<< "metal i64 smoke ok"
