# core/metal.w — Tungsten surface for Metal compute dispatch.
#
# Thin facade over the C runtime in `runtime/metal.m`. Bare top-level
# fns named `metal_*` rather than a class so the smoke spec can drive
# the dispatch end-to-end with as little surface as possible. A
# class-style facade (`Metal.device()`) lands in a follow-up once the
# v1 dispatch shape stabilizes.
#
# Lifetime: every value returned here (device, library, pipeline,
# buffer, queue) is a heap-backed WValue with a retained `id` inside.
# v1 leaks them. The Tungsten GC integration that wires these into
# finalizers is in the runtime TODO list.

# Default GPU. Raises on hosts without Metal (Linux / Windows).
-> metal_device
  ccall("w_metal_device_default")

# Compile MSL source against `device`, return a library handle.
# Raises with the Metal compiler diagnostics on syntax errors.
#
# `strict` opts out of the default fast math: strict:true compiles the kernel
# with IEEE-conforming Safe math + preserved invariance (the GPU analogue of
# @strictmath) for kernels that need exact / reproducible float results;
# the default (false) keeps fast math (aggressive FMA / reciprocals).
-> metal_compile_source(device, source, strict = false)
  if strict
    ccall("w_metal_compile_source_opts", device, source, 1)
  else
    ccall("w_metal_compile_source", device, source)

# Look up a kernel by name in a compiled library, build a compute
# pipeline state. Raises if the kernel isn't present.
-> metal_pipeline(library, name)
  ccall("w_metal_pipeline_for", library, name)

# Allocate a Metal buffer of `byte_length` bytes (shared storage).
# Contents are zero-initialized.
# Declared `->` not `fn`: historically routed around broken impure-ccall
# detection (fixed in the slab-AST guard repair); `->` retained to avoid churn.
-> metal_buffer(device, byte_length)
  ccall("w_metal_buffer_new", device, byte_length)

# Phase 7a (#12): zero-copy wrap of a typed array as a Metal buffer.
# Apple Silicon's unified memory means the GPU sees the same physical
# pages as the CPU array — no upload, no copy. The buffer is a
# borrowed view; caller must keep the source array alive while the
# buffer is in use.
#
# Accepts either a typed Array (size < 2^32) or a BigArray (int64 size,
# typically the return of `mmap.view_at(byte_offset, ebits, n_elements)`).
# The BigArray path is the bridge for zero-copy weight loads: mmap a
# safetensors / GGUF file, view a tensor's slice, hand it to Metal —
# the GPU and the file pages are the same physical bytes.
#
# Suitable element types: u8/i8/u16/i16/u32/u64/f32/f64/bf16/f8/f4.
# Bit-packed (u1/u4) and polymorphic w64 arrays are rejected.
# Page-aligned bases (mmap regions; arrays from `array_aligned`) take
# the true zero-copy path; otherwise falls back to a one-shot copy.
# Declared `->` not `fn`: historically routed around broken impure-ccall
# detection (fixed in the slab-AST guard repair); `->` retained to avoid churn.
-> metal_buffer_for(device, arr)
  ccall("w_array_as_metal_buffer", device, arr)

# Phase 7b (#68): page-aligned typed-array allocator. Returns a
# fixed-size (size = cap = N) typed array whose slots are mmap-backed
# at a page boundary, enabling the no-copy MTLBuffer wrap to actually
# stay zero-copy. Use this for arrays you intend to bind to the GPU.
#
# Fill via `arr[i] = value` — the array isn't growable (cap is fixed),
# so .push past N reallocates into a fresh non-aligned heap block and
# breaks GPU binding.
#
# `ebits` encodes the element format: 8 = u8, 108 = i8, 16 = u16,
# 116 = i16, 32 = u32, 64 = u64, -32 = f32, -64 = f64, -116 = bf16,
# -108/-109 = f8, -104 = f4.
# Declared `->` not `fn`: historically routed around broken impure-ccall
# detection (fixed in the slab-AST guard repair); `->` retained to avoid churn.
-> metal_array(ebits, size)
  ccall("w_array_new_aligned", ebits, size)

# Buffer length in bytes.
-> metal_buffer_length(buffer)
  ccall("w_metal_buffer_length", buffer)

# Write a single f32 / i32 into the buffer at element index `i`
# (NOT byte offset). Index 0 is byte 0, index 1 is byte 4, etc.
fn metal_buffer_write_f32(buffer, i, value)
  ccall("w_metal_buffer_write_f32", buffer, i, value)

fn metal_buffer_read_f32(buffer, i)
  ccall("w_metal_buffer_read_f32", buffer, i)

# Same as the f32 variants but storing IEEE half-precision (2 bytes per
# element). Buffer index is the f16 element index — index 0 is byte 0,
# index 1 is byte 2. The conversion goes through the C `__fp16` type so
# rounding matches Metal's `half`.
fn metal_buffer_write_f16(buffer, i, value)
  ccall("w_metal_buffer_write_f16", buffer, i, value)

fn metal_buffer_read_f16(buffer, i)
  ccall("w_metal_buffer_read_f16", buffer, i)

fn metal_buffer_write_i32(buffer, i, value)
  ccall("w_metal_buffer_write_i32", buffer, i, value)

fn metal_buffer_read_i32(buffer, i)
  ccall("w_metal_buffer_read_i32", buffer, i)

# bfloat16 element access (2 bytes per element, index = bf16 element index).
# Write rounds f32→bf16 round-to-nearest-even; read widens back to f32. This
# is the dominant ML weight format, so Tensor's CPU face routes bf16 here.
fn metal_buffer_write_bf16(buffer, i, value)
  ccall("w_metal_buffer_write_bf16", buffer, i, value)

fn metal_buffer_read_bf16(buffer, i)
  ccall("w_metal_buffer_read_bf16", buffer, i)

# Zero-copy typed-array view over a buffer's shared contents. `ebits` is the
# element encoding (-32 = f32, -64 = f64, -116 = bf16), `length` the element
# count. The view aliases the GPU-visible bytes — Tensor.matmul uses it to feed
# the shared buffers to Accelerate sgemm without a copy.
fn metal_buffer_view(buffer, ebits, length)
  ccall("w_metal_buffer_view", buffer, ebits, length)

# Bulk-copy a region of an mmap into a Metal buffer. Used by GGUF
# loaders to push tensor weights onto the GPU in one memcpy.
fn metal_buffer_write_from_mmap(buffer, dst_offset, mmap, src_offset, byte_length)
  ccall("w_metal_buffer_write_from_mmap", buffer, dst_offset, mmap, src_offset, byte_length)

# Q8_0 deinterleave: walk on-disk Q8_0 blocks (2-byte f16 scale +
# 32-byte i8 quants per 34-byte block), split into separate scales
# and quants Metal buffers for kernels that expect that layout.
fn metal_q8_split_blocks(scales_buf, quants_buf, mmap, src_offset, n_blocks)
  ccall("w_q8_split_blocks", scales_buf, quants_buf, mmap, src_offset, n_blocks)

# Dequantize ONE Q8_0 row from mmap directly into a Metal f32 buffer
# at a given f32 offset. For inference-time embedding lookup: read
# n_blocks Q8_0 blocks (= n_blocks * 32 quants), produce n_blocks*32
# float values via scale * quant.
fn metal_q8_dequant_row(dst_buf, dst_offset_floats, mmap, src_offset, n_blocks)
  ccall("w_q8_dequant_row", dst_buf, dst_offset_floats, mmap, src_offset, n_blocks)

# Command queue (one per program is enough for v1).
-> metal_queue(device)
  ccall("w_metal_queue_new", device)

# Synchronous dispatch for the v1 add_one shape: 3 buffers at slots
# 0 / 1 / 2, `threads` linear threads along x. Commits + waits.
# Raises on encoder error.
fn metal_dispatch1(queue, pipeline, buf0, buf1, buf2, threads)
  ccall("w_metal_dispatch1", queue, pipeline, buf0, buf1, buf2, threads)

# Variable-buffer dispatch. `bufs` is an array of metal_buffers bound
# at slots 0..n-1 in array order — matches the @gpu kernel parameter
# order. `threads` is the linear grid extent along x. Commits + waits.
# Raises on bad arg type or encoder error.
fn metal_dispatch_n(queue, pipeline, bufs, threads)
  ccall("w_metal_dispatch_n", queue, pipeline, bufs, threads)

# Dispatch with explicit threadgroup shape. Use this when threads need
# to cooperate within a threadgroup (simdgroup reductions, threadgroup
# memory). Total grid threads = n_groups * threads_per_group; pass a
# multiple of 32 for threads_per_group on Apple Silicon for clean SIMD
# alignment.
fn metal_dispatch_groups(queue, pipeline, bufs, n_groups, threads_per_group)
  ccall("w_metal_dispatch_groups", queue, pipeline, bufs, n_groups, threads_per_group)

# 3D dispatch — explicit (x, y, z) for both the threadgroup grid and the
# threads-per-threadgroup. Use when the kernel indexes
# `threadgroup_position_in_grid.y/z` or `thread_position_in_threadgroup.y/z`
# (e.g. qwen3.6 Mamba/SSM step kernel).
fn metal_dispatch_3d(queue, pipeline, bufs, n_tg_x, n_tg_y, n_tg_z, threads_x, threads_y, threads_z)
  ccall("w_metal_dispatch_groups_3d", queue, pipeline, bufs, n_tg_x, n_tg_y, n_tg_z, threads_x, threads_y, threads_z)

# Phase 7e (#12): one-shot compute helper.
# Compiles `source` against the default device, looks up `kernel_name`,
# dispatches with `bufs` (each elem may be a Metal buffer or a typed
# array) over `threads` linear threads. Compile + pipeline + queue are
# cached internally — the FIRST call for a given (source, kernel_name)
# pair pays the compile + pipeline cost (~tens of ms); subsequent calls
# are dispatch-only.
#
# Use a heredoc for the MSL source — it doesn't interpolate brackets,
# so MSL's [[buffer(N)]] attribute syntax passes through cleanly.
fn metal_compute(source, kernel_name, bufs, threads)
  ccall("w_metal_compute", source, kernel_name, bufs, threads)

# Phase 7f (#12): copy a Metal buffer's contents back into a typed
# array. Needed only when the array isn't page-aligned (so its wrap
# took the COPY path) and the GPU has written through. For
# page-aligned arrays from metal_array() this is a no-op (the buffer's
# contents pointer IS the array's slots pointer).
-> metal_sync_array(arr, buf)
  ccall("w_metal_sync_array_from_buffer", arr, buf)

# Open a deferred-dispatch batch on the queue. While the batch is open,
# metal_dispatch_n / metal_dispatch_groups encode into one shared
# MTLCommandBuffer without committing. Use when you want to collapse
# many back-to-back kernels into a single commit/wait round trip — the
# critical perf lever for long forward passes.
#
# Caller MUST call metal_batch_commit before reading any output buffer
# produced by the batch's dispatches — the GPU hasn't run them yet.
-> metal_batch_begin(queue)
  ccall("w_metal_batch_begin", queue)

# Open a CONCURRENT batch on the queue. Same as metal_batch_begin
# except the encoder is created with MTLDispatchTypeConcurrent: the
# GPU may execute dispatches in any order when their data dependencies
# allow. Caller must use metal_batch_barrier between phases that have
# read-after-write hazards.
-> metal_batch_begin_concurrent(queue)
  ccall("w_metal_batch_begin_concurrent", queue)

# Memory barrier inside an open concurrent batch. Forces all dispatches
# encoded BEFORE the call to complete before any dispatch encoded AFTER
# it begins. Cheap no-op on a serial batch.
-> metal_batch_barrier(queue)
  ccall("w_metal_batch_barrier", queue)

# Resource-specific barrier — only barriers on the listed Metal buffers.
# Cheaper than the scope-wide barrier when only a few resources have
# RAW deps between phases. `bufs` is an array of buffers.
-> metal_batch_barrier_resources(queue, bufs)
  ccall("w_metal_batch_barrier_resources", queue, bufs)

# Allocate `length` bytes of threadgroup-scoped memory at the given
# binding index for the NEXT dispatch on the open batch's encoder.
# The MSL kernel must declare a `threadgroup T*` arg with the
# matching `[[threadgroup(index)]]` attribute.
fn metal_set_threadgroup_memory(queue, length, index)
  ccall("w_metal_set_threadgroup_memory", queue, length, index)

# Build a pipeline for `kernel_name` with `values` (an array of i32s)
# bound as Metal function constants at indices 0..values.size-1.
# The MSL kernel must declare matching `constant T NAME [[function_constant(I)]]`
# at file scope. Lets the compiler specialize the kernel to known shapes.
fn metal_pipeline_with_int_constants(library, kernel_name, values)
  ccall("w_metal_pipeline_for_with_int_constants", library, kernel_name, values)

# Create an MTLBinaryArchive to cache compiled pipeline state objects.
# Subsequent pipeline creation can reuse cached AIR bytecode, skipping
# the MSL→AIR compile step. macOS already caches pipelines globally
# across runs, so this mostly affects first-time startup.
-> metal_binary_archive_new(device)
  ccall("w_metal_binary_archive_new", device)

# End the open encoder, commit the command buffer, wait for GPU to
# finish. Output buffers are safe to read after this returns. Raises
# with the GPU error's localizedDescription if the batch failed.
-> metal_batch_commit(queue)
  ccall("w_metal_batch_commit", queue)

# Async commit — submits the command buffer to the GPU and returns a
# handle WITHOUT waiting. Caller must eventually call
# `metal_command_buffer_wait` on the handle. Lets the host overlap
# encoding the next batch while the previous batch executes on the GPU.
-> metal_batch_commit_async(queue)
  ccall("w_metal_batch_commit_async", queue)

# Block until the given async-committed cmd buffer completes; release it.
-> metal_command_buffer_wait(cb_handle)
  ccall("w_metal_command_buffer_wait", cb_handle)

-> metal_batch_commit_ms(queue, nonce)
  ccall("w_metal_batch_commit_ms", queue)

# Programmatic Metal frame capture for shader-level profiling.
# Bracket the GPU work you want to capture; opens in Xcode Frame Debugger.
# Requires METAL_CAPTURE_ENABLED=1 in env when running outside Xcode.
-> metal_capture_begin(device, path)
  ccall("w_metal_capture_begin", device, path)

fn metal_capture_end
  ccall("w_metal_capture_end")

# ============================================================
# Metal 4 tensor + MTL4 command path (macOS 26+)
#
# The legacy MTLComputeCommandEncoder has no setTensor / argument-table
# binding API, so kernel parameters typed as `tensor<...>` (consumed by
# matmul2d cooperative tensors) require this parallel command stack.
# Existing buffer-only kernels keep using the legacy path; MTL4 is opt-in
# per-kernel.
# ============================================================

# MTLTensorDataType identifiers (mirrors MTLTensorDataType enum). Use these
# when calling metal_tensor_2d so kernel and host agree on element format.
METAL_DTYPE_FLOAT32  =   3
METAL_DTYPE_FLOAT16  =  16
METAL_DTYPE_INT32    =  29
METAL_DTYPE_UINT32   =  33
METAL_DTYPE_INT16    =  37
METAL_DTYPE_INT8     =  45
METAL_DTYPE_UINT8    =  49
METAL_DTYPE_BFLOAT16 = 121
METAL_DTYPE_INT4     = 143
METAL_DTYPE_UINT4    = 144

# Wrap a slice of an MTLBuffer as a 2D MTLTensor.
#   buffer:      MTLBuffer that owns the storage
#   dtype:       one of METAL_DTYPE_*
#   rows, cols:  logical dimensions (row-major)
#   stride_rows: row stride in elements (pass 0 for tightly-packed = cols)
#   byte_offset: starting byte offset into buffer (typically 0)
fn metal_tensor_2d(buffer, dtype, rows, cols, stride_rows, byte_offset)
  ccall("w_metal_tensor_2d", buffer, dtype, rows, cols, stride_rows, byte_offset)

# Rank-N MTLTensor over a slice of an MTLBuffer (aliases the bytes — no copy).
#   shape:   Array of dims, row-major outer→inner (e.g. [batch, rows, cols])
#   strides: Array of element strides in the same order, or [] for tightly-packed
#   byte_offset: starting byte offset into buffer
# The runtime reverses to Apple's innermost-first extents. This is the
# primitive the Tensor class's `.metal_tensor` face is built on.
fn metal_tensor_nd(buffer, dtype, shape, strides, byte_offset)
  ccall("w_metal_tensor_nd", buffer, dtype, shape, strides, byte_offset)

# Create an MTL4 compiler. Required for compute pipelines that use
# cooperative tensors (matmul2d) since only MTL4ComputePipelineDescriptor
# can set requiredThreadsPerThreadgroup. Reuse one compiler across many
# pipeline builds.
fn metal4_compiler(device)
  ccall("w_metal4_compiler_new", device)

# Build a compute pipeline via MTL4Compiler with requiredThreadsPerThreadgroup.
# `threads_x`, `threads_y`, `threads_z` must match the dispatch's
# threadsPerThreadgroup exactly. For cooperative-tensor kernels using
# `execution_simdgroups<N>`, threads_x = N * threadExecutionWidth (= N * 32
# on Apple Silicon).
fn metal4_pipeline(compiler, library, function_name, threads_x, threads_y, threads_z)
  ccall("w_metal4_pipeline_for", compiler, library, function_name, threads_x, threads_y, threads_z)

# Create an MTL4 command queue (separate from MTLCommandQueue).
fn metal4_queue(device)
  ccall("w_metal4_queue_new", device)

# Create an MTL4 command allocator. Reused across dispatches; reset
# happens implicitly inside metal4_dispatch_groups_3d after the GPU
# finishes the work.
fn metal4_allocator(device)
  ccall("w_metal4_allocator_new", device)

# Create an MTL4 argument table sized for `max_buffers` binding slots
# (1..31). Matches the kernel's [[buffer(0)]] .. [[buffer(N-1)]] indices.
fn metal4_argtable(device, max_buffers)
  ccall("w_metal4_argtable_new", device, max_buffers)

# Bind a buffer to a slot. The slot index matches the kernel's
# [[buffer(N)]] attribute.
fn metal4_argtable_set_buffer(argtable, index, buffer)
  ccall("w_metal4_argtable_set_buffer", argtable, index, buffer)

# Bind a buffer at a byte offset.
fn metal4_argtable_set_buffer_offset(argtable, index, buffer, byte_offset)
  ccall("w_metal4_argtable_set_buffer_offset", argtable, index, buffer, byte_offset)

# Bind a tensor to a slot. Tensor parameters in kernels (`tensor<...>`)
# bind via the same buffer-binding range as plain buffers.
fn metal4_argtable_set_tensor(argtable, index, tensor)
  ccall("w_metal4_argtable_set_tensor", argtable, index, tensor)

# All-in-one dispatch: begins cmdbuffer, encodes one dispatch with the
# given pipeline + argtable, ends, commits, waits. Synchronous. Use this
# for benchmarks and v1 integration; finer control comes later if we
# need to batch multiple dispatches per cmdbuffer.
#
# `resources` is an array of MTLBuffer / MTLTensor instances bound for
# this dispatch — MTL4 requires explicit residency tracking (legacy
# `setBuffer` did this implicitly), so each resource must be listed
# here so it can be added to a transient residency set on the queue.
fn metal4_dispatch_groups_3d(queue, allocator, pipeline, argtable, resources, tg_mem_bytes, n_tg_x, n_tg_y, n_tg_z, threads_x, threads_y, threads_z)
  ccall("w_metal4_dispatch_groups_3d", queue, allocator, pipeline, argtable, resources, tg_mem_bytes, n_tg_x, n_tg_y, n_tg_z, threads_x, threads_y, threads_z)
