# Device-scope atomic primitives used by persistent FlipFleet kernel pools.

use core/metal

## i32[]: counters, ring
@gpu fn atomic_pool_smoke(counters, ring)
  tid = gpu.thread_position_in_grid.x ## i32
  slot = gpu.atomic_fetch_add_i32(counters, 0, 1) ## i32
  ring[slot] = tid
  old = gpu.atomic_min_i32(counters, 1, tid) ## i32

msl = read_file("spec/core/metal_atomic_spec.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "atomic_pool_smoke")
counters = metal_array(32, 2)
ring = metal_array(32, 32)
counters[0] = 0
counters[1] = 999999
counters_buf = metal_buffer_for(device, counters)
ring_buf = metal_buffer_for(device, ring)
queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [counters_buf, ring_buf], 32)
if counters[0] != 32 || counters[1] != 0
  << "metal atomic smoke FAILED"
  exit(1)
seen = i64[32]
i = 0 ## i64
while i < 32
  value = ring[i] ## i64
  if value >= 0 && value < 32
    seen[value] = 1
  i += 1
i = 0
while i < 32
  if seen[i] != 1
    << "metal atomic ring FAILED"
    exit(1)
  i += 1
<< "metal atomic smoke ok"
