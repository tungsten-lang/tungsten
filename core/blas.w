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

# i32 typed array (ebits=33 — see runtime WArray signed int encoding).
-> i32_array(n)
  ccall("w_array_new_aligned", 33, n)

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

fn vlog(a, out, n)
  ccall("w_blas_vlog_f32", a, out, n)

fn vsqrt(a, out, n)
  ccall("w_blas_vsqrt_f32", a, out, n)

# ---- BLAS 1 / 2 ----
# y := a*x + y  (saxpy). In-place on y.
fn saxpy(a, x, y, n)
  ccall("w_blas_saxpy", a, x, y, n)

# y := A x  for A M×N row-major f32, x length N, y length M.
fn sgemv(a, x, y, m, n)
  ccall("w_blas_sgemv_n", a, x, y, m, n)

# ---- vDSP vector arithmetic ----
fn vadd(a, b, out, n)
  ccall("w_blas_vadd_f32", a, b, out, n)

fn vmul(a, b, out, n)
  ccall("w_blas_vmul_f32", a, b, out, n)

fn vsmul(a, s, out, n)
  ccall("w_blas_vsmul_f32", a, s, out, n)

# Fill out[0..n) with scalar s (zeros-by-default: use s=0 after allocate).
fn vfill(out, s, n)
  ccall("w_blas_vfill_f32", out, s, n)

# ---- Dense solve / Cholesky (pure C in blas_bridge — no clapack) ----
fn dgesv(a, b, n)
  ccall("w_blas_dgesv", a, b, n)

fn dpotrf(a, n)
  ccall("w_blas_dpotrf", a, n)

# vDSP FFT on f32 re/im arrays, length n = power of 2. inverse: 0|1.
fn fft_f32(re, im, n, inverse)
  ccall("w_blas_fft_f32", re, im, n, inverse)
