# metal_sgemm — Tungsten-native tiled Metal matmul (core/metal_sgemm.w).
#
# METAL LANE, COMPILED ONLY. `use core/metal_sgemm` compiles and caches the
# pipeline at module load, so importing the module already needs a Metal device:
# the native interpreter refuses with "Unsupported ccall 'w_metal_device_default'".
#
# This spec covers the CPU-testable surface — the generated MSL source and the
# cached pipeline state — and never dispatches a kernel.
#
# Run:
#   bin/tungsten -o /tmp/metal_sgemm_spec spec/core/metal_sgemm_spec.w && /tmp/metal_sgemm_spec

use core/metal_sgemm

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- the generated MSL kernel source ----
msl = build_metal_sgemm_msl()
check("MSL source is a string", type(msl) == "String")
check("MSL source is substantial", msl.size > 1000)
check("MSL source is deterministic", build_metal_sgemm_msl() == msl)
check("includes metal_stdlib", msl.include?("#include <metal_stdlib>"))
check("includes metal_simdgroup_matrix", msl.include?("#include <metal_simdgroup_matrix>"))
check("uses the metal namespace", msl.include?("using namespace metal;"))
check("declares the kernel the pipeline looks up", msl.include?("kernel void matmul_tiled"))
check("takes a, b, c and n buffers",
      msl.include?("buffer(0)") && msl.include?("buffer(1)") &&
      msl.include?("buffer(2)") && msl.include?("buffer(3)"))
check("reads the threadgroup position", msl.include?("threadgroup_position_in_grid"))

# 32x32 output tile built from a 4x4 grid of simdgroup_float8x8 accumulators.
check("accumulators are simdgroup_float8x8", msl.include?("simdgroup_float8x8"))
check("first accumulator", msl.include?("c00"))
check("last accumulator", msl.include?("c33"))
check("sixteen accumulators are stored",
      msl.include?("simdgroup_store(c00") && msl.include?("simdgroup_store(c33"))
check("the k loop steps by 8", msl.include?("k += 8"))
check("tiles are 32 rows", msl.include?("int(tgid.y) * 32"))
check("tiles are 32 columns", msl.include?("int(tgid.x) * 32"))
check("loads a and b fragments",
      msl.include?("simdgroup_load(a0") && msl.include?("simdgroup_load(b3"))
check("multiply-accumulates", msl.include?("simdgroup_multiply_accumulate"))
check("the MSL closes its braces", msl.include?("}\n"))
# The interpolation-escaped [[ ... ]] attributes must survive into the source.
check("buffer attributes are emitted unescaped", msl.include?("\[\[ buffer(0) \]\]"))
check("device pointers are declared", msl.include?("device const float* a"))

# ---- the cached pipeline state, built once at module load ----
state = METAL_SGEMM_STATE
check("state is a hash", type(state) == "Hash")
check("state has exactly device, queue and pipeline", state.size == 3)
check("device is present", state[:device] != nil)
check("queue is present", state[:queue] != nil)
check("pipeline is present", state[:pipeline] != nil)
check("state is a module-level singleton", METAL_SGEMM_STATE == state)

# ---- shape contract (documented, enforced by callers such as sgemm_auto) ----
# metal_sgemm requires M == N == K with N a multiple of 32; the dispatch computes
# n / 32 threadgroups per axis.
check("512 is an eligible shape", 512 % 32 == 0 && 512 / 32 == 16)
check("1024 is an eligible shape", 1024 % 32 == 0 && 1024 / 32 == 32)
check("100 is not an eligible shape", 100 % 32 != 0)

<< "ALL PASS metal_sgemm_spec ([passed.load()] checks)"
