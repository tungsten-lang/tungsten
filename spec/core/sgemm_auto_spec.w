# sgemm_auto — backend-selecting sgemm dispatch (core/sgemm_auto.w).
#
# METAL LANE, COMPILED ONLY. The module pulls in core/metal_sgemm and
# core/metal_sgemm_bf16, both of which build a Metal pipeline at load time, so
# the native interpreter refuses it with
# "Unsupported ccall 'w_metal_device_default'".
#
# Covered here: the policy loader, the two backend pickers, the default
# policies, and the shape validation / error message of sgemm_bf16_auto.
# No matmul is dispatched — that is the benchmark suite's job.
#
# Run:
#   bin/tungsten -o /tmp/sgemm_auto_spec spec/core/sgemm_auto_spec.w && /tmp/sgemm_auto_spec

use core/sgemm_auto

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- the hardcoded f32 fallback policy ----
policy = sgemm_default_policy()
check("default policy has two bands", policy.size == 2)
check("small shapes go to accelerate", policy[0]["backend"] == "accelerate")
check("the accelerate band tops out at 1024", policy[0]["n_max"] == 1024)
check("large shapes go to mlx", policy[1]["backend"] == "mlx")
check("the mlx band is effectively unbounded", policy[1]["n_max"] == 1000000)
check("the default policy is rebuilt fresh", sgemm_default_policy() == policy)

# ---- the hardcoded bf16 fallback policy ----
bpolicy = bgemm_default_policy()
check("bf16 default policy has one band", bpolicy.size == 1)
check("every eligible bf16 shape goes to the native kernel", bpolicy[0]["backend"] == "metal-bf16")
check("the bf16 band is effectively unbounded", bpolicy[0]["n_max"] == 1000000)

# ---- the loaders fall back to the defaults when no tuning file exists ----
# ~/.tungsten/sgemm-policy.json is written by
# benchmarks/linalg/tungsten/sgemm_capabilities.sh; absent it, the defaults stand.
check("load_sgemm_policy falls back to the default", load_sgemm_policy() == sgemm_default_policy())
check("load_bgemm_policy falls back to the default", load_bgemm_policy() == bgemm_default_policy())
check("SGEMM_POLICY is loaded once at module load", SGEMM_POLICY == load_sgemm_policy())
check("BGEMM_POLICY is loaded once at module load", BGEMM_POLICY == load_bgemm_policy())

# ---- sgemm_auto_pick_backend: first band whose n_max covers the size ----
check("the smallest shape picks the first band", sgemm_auto_pick_backend(1) == "accelerate")
check("a mid-band shape picks the first band", sgemm_auto_pick_backend(512) == "accelerate")
check("the band boundary is inclusive", sgemm_auto_pick_backend(1024) == "accelerate")
check("one past the boundary falls through", sgemm_auto_pick_backend(1025) == "mlx")
check("a large shape picks the last band", sgemm_auto_pick_backend(8192) == "mlx")
# Past every n_max the loop falls out and the last band is used as the catch-all.
check("beyond every band the last one wins", sgemm_auto_pick_backend(1000001) == "mlx")
check("zero picks the first band", sgemm_auto_pick_backend(0) == "accelerate")

# ---- bgemm_pick_backend: a single band, so every size lands on it ----
check("bf16 picks the native kernel for a small shape", bgemm_pick_backend(1) == "metal-bf16")
check("bf16 picks the native kernel for a large shape", bgemm_pick_backend(4096) == "metal-bf16")
check("bf16 catch-all beyond the band", bgemm_pick_backend(1000001) == "metal-bf16")

# ---- FAST_MATH is a compile-time constant; undefined means strict routing ----
# `bin/tungsten -o ...` leaves it undefined, so sgemm_auto routes to sgemm_strict.
check("FAST_MATH is undefined in a plain build", FAST_MATH == nil)

# ---- shape eligibility, as the dispatchers compute it ----
# metal-tiled / metal-bf16 both need m == n == k with n % 32 == 0.
-> eligible(m, n, k)
  return m == n && n == k && (n % 32) == 0

check("a square multiple of 32 is eligible", eligible(512, 512, 512))
check("a non-square shape is not eligible", !eligible(512, 256, 512))
check("a square non-multiple of 32 is not eligible", !eligible(100, 100, 100))
check("k must match too", !eligible(512, 512, 256))
check("32 is the smallest eligible size", eligible(32, 32, 32))

# ---- sgemm_bf16_auto rejects everything but square multiples of 32 ----
a = f32_array(16)
b = f32_array(16)
c = f32_array(16)
message = ""
begin
  sgemm_bf16_auto(a, b, c, 4, 4, 4)
rescue e
  message = e
check("sgemm_bf16_auto raises on an ineligible shape", message != "")
check("the error names the constraint", message.include?("square multiple-of-32 shapes only"))
check("the error points at the alternative", message.include?("bgemm_auto"))

non_square = ""
begin
  sgemm_bf16_auto(a, b, c, 32, 64, 32)
rescue e
  non_square = e
check("sgemm_bf16_auto raises on a non-square shape",
      non_square.include?("square multiple-of-32 shapes only"))

<< "ALL PASS sgemm_auto_spec ([passed.load()] checks)"
