# spec: interpreter
# Dirichlet characters, von Mangoldt sums, Dirichlet L-functions / Riemann zeta
# functional equation, and CM types on (Z/lZ)^*.

use core/algebra/dirichlet

-> nt_check(name, cond)
  raise "FAIL " + name if !cond
  << "PASS " + name

# --- 1. Von Mangoldt & Statement.lean sums ------------------------------------
nt_check("vm.prime_powers",
  VonMangoldt.prime_power(1) == nil &&
  VonMangoldt.prime_power(6) == nil &&
  VonMangoldt.prime_power(7) == [7, 1] &&
  VonMangoldt.prime_power(8) == [2, 3] &&
  VonMangoldt.prime_power(9) == [3, 2])

# psi(10) = log(2)*3 + log(3)*2 + log(5) + log(7) = log(2520)
nt_check("vm.psi_10", (VonMangoldt.psi(10) - Math.log(~2520.0)).abs < ~1.0e-12)

# ForcedSumIdentity: b * Sz(a/b) = a * (log(a/b) - 1 - gamma) + b * Gz(a/b)
a = ~35.0
b = ~2.5
lhs = b * VonMangoldt.weighted_sum_zeta(a / b)
rhs = a * (Math.log(a / b) - ~1.0 - VonMangoldt.euler_gamma) + b * VonMangoldt.error_gz(a / b)
nt_check("vm.forced_sum_identity", (lhs - rhs).abs < ~1.0e-11)

# --- 2. Dirichlet characters --------------------------------------------------
chi4 = DirichletCharacter.quadratic_mod4
nt_check("dchar.chi4_props",
  chi4.modulus == 4 && !chi4.trivial? && chi4.real? && chi4.odd? && chi4.primitive? && chi4.conductor == 4)
# tau(chi4) = 2i
nt_check("dchar.chi4_gauss", (chi4.gauss_sum - Complex<f64>.i.scale(~2.0)).abs < ~1.0e-12)

# All characters mod 12: phi(12) = 4, pairwise orthogonal
chars12 = DirichletCharacter.all(12)
nt_check("dchar.mod12_count", chars12.size == 4)
ortho_ok = true
i = 0
while i < chars12.size
  j = 0
  while j < chars12.size
    expected = i == j ? ~4.0 : ~0.0
    ortho_ok = false if (chars12[i].orthogonality_sum(chars12[j]) - Complex<f64>.real(expected)).abs > ~1.0e-10
    j += 1
  i += 1
nt_check("dchar.mod12_orthogonality", ortho_ok)

# Conductor & primitive induction: mod 12 has conductors 1, 3, 4, 12
conds12 = chars12.map -> (c) c.conductor
conds12 = conds12.sort
nt_check("dchar.mod12_conductors", conds12 == [1, 3, 4, 12])

# --- 3. Riemann zeta & Dirichlet L-functions + functional equation ------------
# zeta(2) = pi^2 / 6
pi = ~3.14159265358979323846
z2 = DirichletL.riemann_zeta(Complex<f64>.real(~2.0))
nt_check("lfunc.zeta_2", (z2 - Complex<f64>.real(pi * pi / ~6.0)).abs < ~1.0e-12)

# First Riemann zero s = 1/2 + 14.13472514173469379i
z_zero = DirichletL.riemann_zeta(Complex<f64>.real(~0.5) + Complex<f64>.i.scale(~14.13472514173469379))
nt_check("lfunc.zeta_first_zero", z_zero.abs < ~1.0e-10)

# L(chi4, 1) = pi / 4
l_chi4_1 = DirichletL.l_function(chi4, Complex<f64>.one)
nt_check("lfunc.chi4_at_1", (l_chi4_1 - Complex<f64>.real(pi / ~4.0)).abs < ~1.0e-12)

# Functional equation for primitive character mod 5 (non-real quartic character!)
chars5 = DirichletCharacter.all(5)
quartic5 = nil
chars5.each -> (c)
  quartic5 = c if !c.real?
nt_check("lfunc.quartic5_primitive", quartic5 != nil && quartic5.primitive?)
s_test = Complex<f64>.real(~0.35) + Complex<f64>.i.scale(~2.7)
lhs_fe = DirichletL.completed_l(quartic5, s_test)
rhs_fe = DirichletL.root_number(quartic5) * DirichletL.completed_l(quartic5.conjugate, Complex<f64>.one - s_test)
nt_check("lfunc.functional_eq_mod5", (lhs_fe - rhs_fe).abs < ~1.0e-10)

# --- 4. CM Types (Formalism/StatementCM.lean: TwoTypes & HalfTypes) -----------
all7 = CMType.all_with_one(7)
nt_check("cm.l7_count", all7.size == 4)
two_types_ok = true
all7.each -> (phi)
  dphi = phi.dual
  two_types_ok = false if !phi.valid? || !dphi.valid? || !dphi.has_one?
  sigma = 2
  while sigma < 6
    two_types_ok = false if phi.counts?(sigma) == dphi.counts?(sigma)
    sigma += 1
nt_check("cm.two_types_l7", two_types_ok)

# HalfTypes at l = 7: for every sigma != 1, -1, exactly half of all CM types with 1 in Phi count sigma
half_ok = true
sigma = 2
while sigma < 6
  cnt = 0
  all7.each -> (phi) cnt += 1 if phi.counts?(sigma)
  half_ok = false if 2 * cnt != all7.size
  sigma += 1
nt_check("cm.half_types_l7", half_ok)
