# A tensor-like unaligned byte range can remain file-backed: the runtime wraps
# outward to VM pages and binds the leading byte offset to the Metal kernel.

use core/file
use core/metal

## u8[]: src
## u32[]: dst
@gpu fn copy_mmap_bytes(src, dst)
  i = gpu.thread_position_in_grid.x ## i32
  if i < 4
    dst[i] = src[i]

tmp = Tempfile.new("tungsten-metal-mmap-buffer")
path = tmp.path
tmp.close!()
mmap = nil

begin
  File.write(path, ("p" * 424) + "ABCD" + ("z" * 20000))
  mmap = File.mmap(path)
  device = metal_device()
  queue = metal_queue(device)
  src = metal_buffer_for_mmap(device, mmap, 424, 4)
  if metal_buffer_length(src) != 4
    raise "mmap Metal view exposes aligned backing length instead of logical length"

  cpu_view = metal_buffer_view(src, 8, 4)
  if cpu_view[0] != 65 || cpu_view[1] != 66 || cpu_view[2] != 67 || cpu_view[3] != 68
    raise "mmap Metal view CPU offset mismatch"

  source = read_file("spec/core/metal_mmap_buffer_spec.metal")
  pipe = metal_pipeline(metal_compile_source(device, source), "copy_mmap_bytes")
  dst = metal_buffer(device, 16)
  metal_dispatch_n(queue, pipe, [src, dst], 4)
  d0 = metal_buffer_read_i32(dst, 0)
  d1 = metal_buffer_read_i32(dst, 1)
  d2 = metal_buffer_read_i32(dst, 2)
  d3 = metal_buffer_read_i32(dst, 3)
  if d0 != 65 || d1 != 66 || d2 != 67 || d3 != 68
    raise "mmap Metal view GPU binding offset mismatch"
  << "PASS Metal mmap buffer offset"
ensure
  mmap.close if mmap != nil
  File.unlink(path) if File.exist?(path)
