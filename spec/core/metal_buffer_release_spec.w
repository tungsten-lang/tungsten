# spec: compiled -- needs a Metal device and the native runtime
# metal_buffer_release (core/metal.w): storage is returned immediately and a
# released buffer can no longer be used.  Native only (needs a Metal device).
#
# Run:
#   bin/tungsten -o /tmp/metal_buffer_release_spec spec/core/metal_buffer_release_spec.w && /tmp/metal_buffer_release_spec

use core/metal

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

device = metal_device()
buffer = metal_buffer(device, 4096)
metal_buffer_write_i32(buffer, 3, 41)
check("a live buffer reads back", metal_buffer_read_i32(buffer, 3) == 41)
check("a live buffer reports its length", metal_buffer_length(buffer) == 4096)
metal_buffer_release(buffer)
raised = false
begin
  ignored = metal_buffer_length(buffer)
rescue error
  raised = true
end
check("a released buffer raises on use", raised)
raised_twice = false
begin
  metal_buffer_release(buffer)
rescue error
  raised_twice = true
end
check("releasing twice raises", raised_twice)

wrapped_source = i64[512]
wrapped_source[7] = 9
wrapped = metal_buffer_for(device, wrapped_source)
metal_buffer_release(wrapped)
check("releasing a wrapped array leaves the array intact", wrapped_source[7] == 9)

# 48 x 256 MiB = 12 GiB if storage were retained; with release the process
# stays near one buffer.  The capture shell's parent is this process.
round = 0
while round < 48
  big = metal_buffer(device, 268_435_456)
  metal_buffer_write_i32(big, 0, round)
  metal_buffer_release(big)
  round += 1
rss_kib = OS.capture("ps -o rss= -p $PPID").strip().to_i()
check("48 released 256 MiB buffers keep RSS under 2 GiB (rss_kib=[rss_kib])", rss_kib > 0 && rss_kib < 2_097_152)
<< "metal_buffer_release_spec: all checks passed"
