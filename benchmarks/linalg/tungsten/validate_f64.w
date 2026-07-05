# Precision validator for f64 sgemm:
#   1. Run a small N=64 matmul via Accelerate dgemm (trusted IEEE 754 binary64).
#   2. Run the same matmul via MLX dgemm.
#   3. Diff element-wise. Report max abs/rel error and a few sample values.
#
# Expected outcomes:
#   - All-zero error: MLX is doing real fp64. Safe to dispatch.
#   - Errors ≤ ~1e-6: MLX is using f32 internally (~7 decimal digits). Unsafe
#     for any user expecting binary64 precision.
#   - Errors ≤ ~1e-3: MLX is using bf16 internally (~3 decimal digits). Extra
#     unsafe.
#
# Run:
#   benchmarks/linalg/tungsten/validate_f64

use core/blas
use core/mlx

# Override via ARGV[0] for sweep mode
n = 64
if ARGV.size() > 0
  n = ARGV[0].to_i
size = n * n

# Use values that span a few orders of magnitude so precision matters.
a = f64_array(size)
b = f64_array(size)
c_ref = f64_array(size)
c_mlx = f64_array(size)

i = 0
while i < size
  # Mix of small and large values — exposes precision differences.
  a[i] = ((i * 7 + 13) % 17) * ~1.0 / ~3.7
  b[i] = ((i * 11 + 5) % 19) * ~1.0 / ~5.3
  i += 1

# Trusted reference: Apple Accelerate cblas_dgemm. AMX has fp64 support.
dgemm(a, b, c_ref, n, n, n)

# Test path: MLX dgemm.
mlx_dgemm(a, b, c_mlx, n, n, n)

# Diff. Track max absolute error, max relative error, and first divergence.
max_abs = ~0.0
max_rel = ~0.0
first_div_idx = -1
first_ref = ~0.0
first_mlx = ~0.0

i = 0
while i < size
  r = c_ref[i]
  m = c_mlx[i]
  diff = r - m
  if diff < ~0.0
    diff = ~0.0 - diff
  if diff > max_abs
    max_abs = diff
  # Relative error — avoid div-by-zero on entries that round to 0.
  abs_r = r
  if abs_r < ~0.0
    abs_r = ~0.0 - abs_r
  # Avoid div-by-zero — skip relative error when ref < ~1e-12 in magnitude.
  tiny = ~0.000000000001
  if abs_r > tiny
    rel = diff / abs_r
    if rel > max_rel
      max_rel = rel
  # Record first non-trivial divergence (>= 1e-12).
  if first_div_idx < 0 && diff > tiny
    first_div_idx = i
    first_ref = r
    first_mlx = m
  i += 1

<< "=== f64 precision validation (N=" + n.to_s + " matmul) ==="
<< "Reference: Accelerate cblas_dgemm (trusted fp64)"
<< "Subject:   MLX mlx_dgemm"
<< ""
<< "C[0]   ref=" + c_ref[0].to_s + "  mlx=" + c_mlx[0].to_s
<< "C[100] ref=" + c_ref[100].to_s + "  mlx=" + c_mlx[100].to_s
<< ""
<< "max absolute error: " + max_abs.to_s
<< "max relative error: " + max_rel.to_s

if first_div_idx >= 0
  << "first divergence at idx " + first_div_idx.to_s + ":"
  << "  ref=" + first_ref.to_s
  << "  mlx=" + first_mlx.to_s

# Classify. Tolerances expressed as repeated decimal — Tungsten's `1e-N`
# scientific-notation parser emits malformed IR; the `~0.0001...` form
# rounds to the same fp64 value but lexes cleanly.
tol_fp64 = ~0.00000000000001    # 1e-14
tol_fp32 = ~0.00001              # 1e-5
tol_bf16 = ~0.01                 # 1e-2

if max_abs < tol_fp64
  << ""
  << "VERDICT: MLX appears to use true fp64. Safe for dgemm_auto dispatch."
elsif max_rel < tol_fp32
  << ""
  << "VERDICT: MLX likely uses fp32 internally (~6-7 digits precision)."
  << "  UNSAFE for users requiring binary64 precision."
elsif max_rel < tol_bf16
  << ""
  << "VERDICT: MLX likely uses bf16/half internally (~3 digits precision)."
  << "  VERY UNSAFE — would silently corrupt scientific computing workloads."
else
  << ""
  << "VERDICT: Large divergence — possible algorithmic difference or bug."
