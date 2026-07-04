# BLAS dispatch — Apple Accelerate framework on macOS.
#
# Thin wrappers over the runtime's cblas_sgemm / cblas_dgemm bridges.
# Hands raw float pointers to AMX-tuned kernels with no nanbox /
# unbox round-trip, no Tungsten-side dispatch overhead.
#
# Usage:
#   a = f32_array(m * k)
#   b = f32_array(k * n)
#   c = f32_array(m * n)
#   fill_a(a); fill_b(b)
#   sgemm(a, b, c, m, n, k)    # C = A · B  (no transpose, row-major)
#
# On non-Apple platforms the underlying runtime helpers raise.

# Allocate an f32-typed array of length `n`. The result is a WArray with
# raw `float *` storage suitable for handing to BLAS / Metal / direct
# pointer arithmetic — no per-element nanboxing.
#
# Declared `->` not `fn`: the compiler memoizes top-level `fn` bodies
# whose only ccall isn't in compiler/lib/lowering/types.w's known-impure
# allowlist. `w_array_new_aligned` *should* be there but adding it via
# bootstrap rebuild hasn't taken effect (probable cache/stage-0 issue).
# The `->` form bypasses memoization entirely. See results.md, "Forensic
# update (2026-06-06)" for the full story.
-> f32_array(n)
  ccall("w_array_new_aligned", -32, n)

-> f64_array(n)
  ccall("w_array_new_aligned", -64, n)

# Single-precision matrix multiply: C = A · B (row-major, no transpose).
# A is M×K, B is K×N, C is M×N. Returns the C array.
fn sgemm(a, b, c, m, n, k)
  ccall("w_blas_sgemm_nn", a, b, c, m, n, k)

# Double-precision matrix multiply: C = A · B. Same shape conventions.
fn dgemm(a, b, c, m, n, k)
  ccall("w_blas_dgemm_nn", a, b, c, m, n, k)

# Fixed-size 4×4 f32 matrix multiply via NEON `<4 x float>` SIMD.
# Avoids Accelerate's ~20-100 ns per-call dispatch floor — does the
# entire 128-flop matmul in ~10-30 ns by keeping all 16 floats in
# vector registers. Use this for tight 4×4 hot paths (graphics
# transforms, per-vertex skinning); use sgemm for anything larger.
fn mat4_mul(a, b, c)
  ccall("w_mat4_mul_f32", a, b, c)

# 4-component f32 vector ops via NEON. All three operands must be
# f32_array(4) (or any f32[] of length ≥ 4 — the SIMD load reads
# 4 floats from the start offset). Result lands in `out`.
fn vec4_add(a, b, out)
  ccall("w_vec4_add_f32", a, b, out)

fn vec4_mul(a, b, out)
  ccall("w_vec4_mul_f32", a, b, out)

fn vec4_dot(a, b)
  ccall("w_vec4_dot_f32", a, b)

# ---- vDSP reductions over an f32 array (Apple Accelerate) ----
# `n` is the element count; pass 0 (or omit as 0) to use the whole array.
# All return a Float. AMX/SIMD-accelerated on Apple silicon.

# Σ a[i] — vDSP_sve.
fn fsum(a, n)
  ccall("w_blas_sum_f32", a, n)

# Σ a[i]·b[i] — vDSP_dotpr (dot product).
fn fdot(a, b, n)
  ccall("w_blas_dot_f32", a, b, n)

# Σ a[i]² — vDSP_svesq (sum of squares).
fn fsumsq(a, n)
  ccall("w_blas_sumsq_f32", a, n)

# ---- vDSP elementwise transcendentals: out[i] = f(a[i]) ----
# `out` may alias `a`. `n` = element count (0 ⇒ min(len a, len out)).
# Returns `out`. vForce vectorized (vvsinf / vvcosf / vvexpf / vvtanhf).
fn vsin(a, out, n)
  ccall("w_blas_vsin_f32", a, out, n)

fn vcos(a, out, n)
  ccall("w_blas_vcos_f32", a, out, n)

fn vexp(a, out, n)
  ccall("w_blas_vexp_f32", a, out, n)

fn vtanh(a, out, n)
  ccall("w_blas_vtanh_f32", a, out, n)
