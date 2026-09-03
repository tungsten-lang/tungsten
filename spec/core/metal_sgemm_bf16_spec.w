# metal_sgemm_bf16 — bf16-input / fp32-accumulator Metal matmul (core/metal_sgemm_bf16.w).
#
# METAL LANE, COMPILED ONLY. Importing the module builds two pipelines at load
# time, so it needs a Metal device: the native interpreter refuses the module with
# "Unsupported ccall 'w_metal_device_default'".
#
# This spec covers the CPU-testable surface — the two generated MSL kernels and the
# cached pipeline state — and never dispatches a kernel.
#
# Run:
#   bin/tungsten -o /tmp/metal_sgemm_bf16_spec spec/core/metal_sgemm_bf16_spec.w && /tmp/metal_sgemm_bf16_spec

use core/metal_sgemm_bf16

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- the f32 -> bf16 conversion kernel ----
conv = build_bf16_conv_msl()
check("conversion MSL is a string", type(conv) == "String")
check("conversion MSL is deterministic", build_bf16_conv_msl() == conv)
check("conversion includes metal_stdlib", conv.include?("#include <metal_stdlib>"))
check("conversion declares the kernel the pipeline looks up", conv.include?("kernel void f32_to_bf16"))
check("conversion reads an f32 source", conv.include?("device const float* src"))
check("conversion writes a bfloat destination", conv.include?("device bfloat* dst"))
check("conversion is one thread per element", conv.include?("thread_position_in_grid"))
check("conversion converts elementwise", conv.include?("bfloat(src"))
check("conversion attributes survive interpolation escaping", conv.include?("\[\[ buffer(0) \]\]"))
check("conversion needs no simdgroup header", !conv.include?("metal_simdgroup_matrix"))

# ---- the bf16 tiled matmul kernel ----
mm = build_bf16_matmul_msl()
check("matmul MSL is a string", type(mm) == "String")
check("matmul MSL is substantial", mm.size > 1000)
check("matmul MSL is deterministic", build_bf16_matmul_msl() == mm)
check("matmul includes metal_simdgroup_matrix", mm.include?("#include <metal_simdgroup_matrix>"))
check("matmul declares the kernel the pipeline looks up", mm.include?("kernel void matmul_bf16"))
check("matmul takes bfloat inputs",
      mm.include?("device const bfloat* a") && mm.include?("device const bfloat* b"))
check("matmul writes an f32 output", mm.include?("device float* c"))
check("matmul takes the n constant", mm.include?("constant int& n"))
# bf16 fragments multiplied into fp32 accumulators — the whole point of the module.
check("fragments are simdgroup_bfloat8x8", mm.include?("simdgroup_bfloat8x8"))
check("accumulators are simdgroup_float8x8", mm.include?("simdgroup_float8x8"))
check("a 4x4 accumulator tile", mm.include?("c00") && mm.include?("c33"))
check("the k loop steps by 8", mm.include?("k += 8"))
check("32-row tiles", mm.include?("int(tgid.y) * 32"))
check("32-column tiles", mm.include?("int(tgid.x) * 32"))
check("multiply-accumulates", mm.include?("simdgroup_multiply_accumulate"))
check("stores every accumulator",
      mm.include?("simdgroup_store(c00") && mm.include?("simdgroup_store(c33"))
check("the two kernels are different sources", mm != conv)

# ---- the cached pipeline state, built once at module load ----
state = METAL_SGEMM_BF16_STATE
check("state is a hash", type(state) == "Hash")
check("state has device, queue, conv and mm", state.size == 4)
check("device is present", state[:device] != nil)
check("queue is present", state[:queue] != nil)
check("conversion pipeline is present", state[:conv] != nil)
check("matmul pipeline is present", state[:mm] != nil)
check("the two pipelines are distinct", state[:conv] != state[:mm])
check("scratch is allocated lazily, not at load", state[:scratch_n] == nil)
check("state is a module-level singleton", METAL_SGEMM_BF16_STATE == state)

# ---- shape contract: square, N a multiple of 32 (n/32 threadgroups per axis) ----
check("512 is an eligible shape", 512 % 32 == 0 && 512 / 32 == 16)
check("2048 is an eligible shape", 2048 % 32 == 0 && 2048 / 32 == 64)
check("48 is not an eligible shape", 48 % 32 != 0)

<< "ALL PASS metal_sgemm_bf16_spec ([passed.load()] checks)"
