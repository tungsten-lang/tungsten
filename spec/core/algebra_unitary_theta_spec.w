# spec: interpreter
# Hermitian forms, definite unitary groups, Hermitian lattice theta series,
# and Stepanov path-quadric Fourier sums (remark.pdf footnote 3).

use core/algebra/unitary_theta

-> ut_check(name, cond)
  raise "FAIL " + name if !cond
  << "PASS " + name

# --- 1. Hermitian forms & definite unitary group U(2) -------------------------
h2 = HermitianForm.new([
  [Complex<f64>.real(~2.0), Complex<f64>.i],
  [Complex<f64>.zero - Complex<f64>.i, Complex<f64>.real(~2.0)]
])
ut_check("herm.hermitian", h2.hermitian?)
ut_check("herm.pos_def", h2.positive_definite?)

id2 = HermitianForm.identity(2)
u2 = UnitaryGroup.new(id2)
c = Math.cos(~0.7)
s = Math.sin(~0.7)
rot = [
  [Complex<f64>.real(c), Complex<f64>.i.scale(s)],
  [Complex<f64>.i.scale(s), Complex<f64>.real(c)]
]
ut_check("unitary.member", u2.member?(rot))
ut_check("unitary.det_unit", (u2.determinant(rot).abs - ~1.0).abs < ~1.0e-12)
prod = u2.multiply(rot, u2.adjoint(rot))
ut_check("unitary.inv_identity",
  (prod[0][0] - Complex<f64>.one).abs < ~1.0e-12 &&
  (prod[1][1] - Complex<f64>.one).abs < ~1.0e-12 &&
  prod[0][1].abs < ~1.0e-12)

# --- 2. Hermitian lattice theta series over Z[i] ------------------------------
# Rank-1 standard Z[i] lattice: r(m) = r_2(m) = 1, 4, 4, 0, 4, 8, ...
tk1 = ThetaKernel.new(HermitianForm.identity(1))
r1 = tk1.representation_counts(5, 3)
ut_check("theta.z_i_counts", r1 == [1, 4, 4, 0, 4, 8])

# Jacobi identity check at q = 0.1: theta_{Z[i]^2}(q) = (theta_{Z[i]}(q))^2
tk2 = ThetaKernel.new(HermitianForm.identity(2))
q = Complex<f64>.real(~0.1)
t1 = tk1.theta_series(q, 8, 3)
t2 = tk2.theta_series(q, 8, 3)
ut_check("theta.product_identity", (t2 - t1 * t1).abs < ~1.0e-6)

# --- 3. Stepanov path-quadric Fourier identity q*N = M^k + R ------------------
# For q = 5, k = 3, t(x) = Legendre(x) + 1 (or any real weights):
# verify qN = M^3 + R and exact match with direct count N of x1*x2 + x2*x3 = 0 mod 5.
weights = [~1.0, ~2.0, ~0.5, ~1.5, ~1.0]
res = ThetaKernel.stepanov_path_sum(5, 3, weights)
qn = res[0]
mk = res[1]
rem = res[2]
ut_check("stepanov.identity", (qn - (mk + rem)).abs < ~1.0e-10)
direct_n = ~0.0
x1 = 0
while x1 < 5
  x2 = 0
  while x2 < 5
    x3 = 0
    while x3 < 5
      if (x1 * x2 + x2 * x3) % 5 == 0
        direct_n += weights[x1] * weights[x2] * weights[x3]
      x3 += 1
    x2 += 1
  x1 += 1
ut_check("stepanov.direct_count", (qn - Complex<f64>.real(~5.0 * direct_n)).abs < ~1.0e-10)
