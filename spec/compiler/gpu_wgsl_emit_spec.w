# Portable WGSL emit smoke. No WebGPU runtime or hardware is required: the
# compiled host program inspects its generated sibling sidecar.

## i32[]: counters
## f32[]: values
## i32: n
@gpu fn wgsl_control(counters, values, n)
  tile = gpu.shared_f32(256)
  i = gpu.thread_position_in_grid.x ## i32
  lane = gpu.thread_position_in_threadgroup.x ## i32
  group = gpu.threadgroup_position_in_grid.x ## i32
  if n < 0
    return
  while i < n
    if lane == 0
      old_add = gpu.atomic_fetch_add_i32(counters, group, 1) ## i32
    else
      old_load = gpu.atomic_load_i32(counters, group) ## i32
    old_exchange = gpu.atomic_exchange_i32(counters, group, lane) ## i32
    old_min = gpu.atomic_min_i32(counters, group, old_exchange) ## i32
    gpu.atomic_store_i32(counters, group, old_min)
    tile[lane] = values[i]
    threadgroup_barrier()
    i += gpu.threads_per_threadgroup

## f32[]: output
@gpu fn wgsl_secondary(output)
  i = gpu.thread_position_in_grid.x ## i32
  output[i] = 1.0

wgsl = read_file("spec/compiler/gpu_wgsl_emit_spec.wgsl")

-> expect_marker(text, label, needle)
  if text.include?(needle)
    << "PASS " + label
  else
    << "FAIL " + label + " missing " + needle
    << "--- wgsl begin ---"
    << text
    << "--- wgsl end ---"
    exit 1

expect_marker(wgsl, "header", "WGSL dialect")
expect_marker(wgsl, "signature", "fn wgsl_control")
expect_marker(wgsl, "local_id", "@builtin(local_invocation_id)")
expect_marker(wgsl, "group_id", "@builtin(workgroup_id)")
expect_marker(wgsl, "shared", "var<workgroup> tungsten_internal_wg_wgsl_control_tile : array<f32, 256>;")
expect_marker(wgsl, "atomic_buffer", "array<atomic<i32>>")
expect_marker(wgsl, "atomic_add", "atomicAdd(&tungsten_internal_bind_wgsl_control_counters\[group], 1)")
expect_marker(wgsl, "atomic_load", "atomicLoad(&tungsten_internal_bind_wgsl_control_counters\[group])")
expect_marker(wgsl, "atomic_exchange", "atomicExchange(&tungsten_internal_bind_wgsl_control_counters\[group], lane)")
expect_marker(wgsl, "atomic_min", "atomicMin(&tungsten_internal_bind_wgsl_control_counters\[group], old_exchange)")
expect_marker(wgsl, "atomic_store", "atomicStore(&tungsten_internal_bind_wgsl_control_counters\[group], old_min);")
expect_marker(wgsl, "loop", "loop {")
expect_marker(wgsl, "loop_guard", "break;")
expect_marker(wgsl, "barrier", "workgroupBarrier();")
expect_marker(wgsl, "return", "return;")
expect_marker(wgsl, "compound", "i += 256;")
expect_marker(wgsl, "second_kernel", "fn wgsl_secondary")
expect_marker(wgsl, "unique_binding", "@group(0) @binding(3) var<storage, read_write> tungsten_internal_bind_wgsl_secondary_output")

<< "gpu_wgsl_emit_spec: all checks passed"
