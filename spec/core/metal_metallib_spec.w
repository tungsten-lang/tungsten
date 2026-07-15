# End-to-end smoke for offline `.metallib` loading. The test driver compiles
# `metal_metallib_spec.metal` once and passes its path as argv[0].

use core/metal

av = argv()
if av.size() < 1
  << "usage: metal_metallib_spec <library.metallib>"
  exit(2)

device = metal_device()
library = metal_load_library(device, av[0])
pipeline = metal_pipeline(library, "metallib_smoke")
output = metal_buffer(device, 32 * 4)
queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [output], 32)

i = 0 ## i64
while i < 32
  if metal_buffer_read_i32(output, i) != i * 3 + 7
    << "metal metallib smoke FAILED at " + i.to_s()
    exit(1)
  i += 1
<< "metal metallib smoke ok"
