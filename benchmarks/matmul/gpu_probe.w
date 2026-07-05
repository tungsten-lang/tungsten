# Feasibility probe: do the @gpu (Metal) emitter + dispatch support the exact
# constructs a flip-graph walker needs -- per-thread id, i32[] read/write,
# modulo LCG, XOR/shift/and, and NESTED while loops with data-dependent bounds?

## i32[]: out
## i32: steps
@gpu fn probe(out, steps)
  tid = gpu.thread_position_in_grid.x ## i32
  state = (tid * 2 + 12345) ## i32
  acc = 0 ## i32
  s = 0 ## i32
  while s < steps
    state = (state * 1103515 + 12345) % 2147483
    r = (state % 13) ## i32
    inner = 0 ## i32
    j = 0 ## i32
    while j < r
      inner = inner + 1
      j = j + 1
    acc = (acc ^ inner) % 1000000
    s = s + 1
  out[tid] = acc

use core/metal

msl = read_file("benchmarks/matmul/gpu_probe.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "probe")

N = 8
out_buf = metal_buffer(device, N * 4)
steps_buf = metal_buffer(device, 4)
metal_buffer_write_i32(steps_buf, 0, 200)
queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [out_buf, steps_buf], N)

i = 0
while i < N
  << "out[" + i.to_s() + "] = " + metal_buffer_read_i32(out_buf, i).to_s()
  i += 1
