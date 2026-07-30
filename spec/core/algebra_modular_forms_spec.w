# Gamma_0(N), modular-curve, cusp-space, and Sturm-bound regressions.
#
# Numeric fixtures are differential values from Sage 10.9. Certificates name
# the classical theorem imports and replay the finite arithmetic.

use algebra

-> modular_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

g1 = Gamma0.new(1)
modular_check("gamma0_1.index", g1.index, 1)
modular_check("gamma0_1.cusps", g1.number_of_cusps, 1)
modular_check("gamma0_1.nu2", g1.order_two_elliptic_points, 1)
modular_check("gamma0_1.nu3", g1.order_three_elliptic_points, 1)
modular_check("gamma0_1.genus", g1.genus, 0)
modular_check("gamma0_1.certificate", g1.certificate.verified?, true)
modular_check("gamma0_1.proof_kind",
              g1.certificate.proof_kind, :trusted_theorem_import)
modular_check("gamma0_1.kernel_boundary",
              g1.certificate.kernel_checked?, false)

g11 = Gamma0.new(11)
modular_check("gamma0_11.index", g11.index, 12)
modular_check("gamma0_11.cusps", g11.number_of_cusps, 2)
modular_check("gamma0_11.nu2", g11.order_two_elliptic_points, 0)
modular_check("gamma0_11.nu3", g11.order_three_elliptic_points, 0)
modular_check("gamma0_11.genus", g11.genus, 1)

x11 = g11.modular_curve
modular_check("x0_11.dimension", x11.dimension, 1)
modular_check("x0_11.genus", x11.genus, 1)
modular_check("x0_11.certificate", x11.certificate.verified?, true)

s11 = CuspForms.new(g11, 2)
modular_check("s2_gamma0_11.dimension", s11.dimension, 1)
modular_check("s2_gamma0_11.sturm", s11.sturm_bound, 2)
modular_check("s2_gamma0_11.precision", s11.q_expansion_precision, 3)
modular_check("s2_gamma0_11.certificate",
              s11.dimension_certificate.verified?, true)
modular_check("s2_gamma0_11.theorem_boundary",
              s11.dimension_certificate.kernel_checked?, false)

m11 = ModularForms.new(g11, 2)
modular_check("m2_gamma0_11.dimension", m11.dimension, 2)
modular_check("m2_gamma0_11.cusp_dimension", m11.cusp_dimension, 1)
modular_check("m2_gamma0_11.eisenstein_dimension",
              m11.eisenstein_dimension, 1)

# The terminal finite-space fact in the Frey/Ribet FLT application is now an
# executable, theorem-labelled calculation: S_2(Gamma_0(2)) is zero.
s2 = Algebra.cusp_forms(2, 2)
modular_check("flt_level_2.dimension", s2.dimension, 0)
modular_check("flt_level_2.zero", s2.zero?, true)
modular_check("flt_level_2.certificate", s2.certified?, true)
modular_check("flt_level_2.sturm", s2.sturm_bound, 1)

modular_check("s12_gamma0_1.dimension",
              CuspForms.new(g1, 12).dimension, 1)
modular_check("s4_gamma0_5.dimension",
              CuspForms.new(5, 4).dimension, 1)
modular_check("s2_gamma0_389.dimension",
              CuspForms.new(389, 2).dimension, 32)
modular_check("s4_gamma0_389.dimension",
              CuspForms.new(389, 4).dimension, 97)
modular_check("s2_gamma0_2005.dimension",
              CuspForms.new(2005, 2).dimension, 199)
modular_check("gamma0_389.sturm",
              Gamma0.new(389).sturm_bound(2), 65)
modular_check("gamma0_100.sturm",
              Gamma0.new(100).sturm_bound(2), 30)

sturm = g11.sturm(2)
modular_check("sturm.certificate", sturm.certificate.verified?, true)
modular_check("sturm.proof_kind",
              sturm.certificate.proof_kind, :trusted_theorem_import)
bad_sturm = SturmBoundCertificate.new(g11, 2, 3)
modular_check("sturm.tamper_rejected", bad_sturm.verified?, false)

modular_check("facade.gamma0", Algebra.gamma0(13).genus, 0)
modular_check("facade.x0", Algebra.modular_curve_x0(11).genus, 1)
modular_check("facade.modular_forms",
              Algebra.modular_forms(11, 2).dimension, 2)

bad_level = false
begin
  Gamma0.new(0)
rescue error
  bad_level = error.to_s.include?("positive integer")
modular_check("invalid.level", bad_level, true)

bad_weight = false
begin
  CuspForms.new(11, -2)
rescue error
  bad_weight = error.to_s.include?("nonnegative integer")
modular_check("invalid.weight", bad_weight, true)

bad_sturm_weight = false
begin
  Gamma0.new(11).sturm_bound(0)
rescue error
  bad_sturm_weight = error.to_s.include?("at least 2")
modular_check("invalid.sturm_weight", bad_sturm_weight, true)
