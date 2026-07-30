# Exact q-expansion arithmetic and classical level-one modular forms.

use algebra

-> q_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

e4 = ClassicalModularForms.e4(12)
e6 = ClassicalModularForms.e6(12)
delta = ClassicalModularForms.delta(12)

q_check("e4.weight", e4.weight, 4)
q_check("e4.a0", e4[0], 1)
q_check("e4.a1", e4[1], 240)
q_check("e4.a2", e4[2], 2160)
q_check("e4.a5", e4[5], 30240)
q_check("e4.certificate", e4.certificate.verified?, true)

q_check("e6.weight", e6.weight, 6)
q_check("e6.a0", e6[0], 1)
q_check("e6.a1", e6[1], -504)
q_check("e6.a2", e6[2], -16632)
q_check("e6.certificate", e6.certificate.verified?, true)

tau = [0, 1, -24, 252, -1472, 4830, -6048,
       -16744, 84480, -113643, -115920, 534612]
i = 0
while i < tau.size
  q_check("delta.tau_" + i.to_s, delta[i], tau[i])
  i += 1
q_check("delta.weight", delta.weight, 12)
q_check("delta.valuation", delta.q_expansion.valuation, 1)
q_check("delta.certificate", delta.certificate.verified?, true)
q_check("delta.theorem_boundary",
        delta.certificate.kernel_checked?, false)

identity = (e4.q_expansion**3 - e6.q_expansion**2).scale(
  Rational.new(1, 1728))
q_check("e4_e6_delta_identity", identity, delta.q_expansion)

q8 = QExpansion.q(8)
one8 = QExpansion.one(8)
q_check("q.power_zero", q8**0, one8)
q_check("q.square.valuation", (q8*q8).valuation, 2)
q_check("q.truncate.precision", delta.q_expansion.truncate(5).precision, 5)
q_check("q.agreement",
        delta.q_expansion.agrees_through?(identity, 11), true)

short = QExpansion.new([1, 2, 3])
long = QExpansion.new([4, 5, 6, 7])
q_check("q.mixed_precision", (short + long).precision, 3)
q_check("q.product.coefficients",
        (short*long).coefficients.join(","),
        QExpansion.new([4, 13, 28]).coefficients.join(","))

unknown_rejected = false
begin
  short[3]
rescue error
  unknown_rejected = error.to_s.include?("beyond known precision")
q_check("q.unknown_coefficient_rejected", unknown_rejected, true)

wrong_e4 = QExpansion.new([1, 241, 2160])
bad_certificate = ClassicalModularFormCertificate.new(
  :E4, Gamma0.new(1), 4, wrong_e4)
q_check("e4.tamper_rejected", bad_certificate.verified?, false)

q_check("facade.e4", Algebra.eisenstein_e4(4)[3], 6720)
q_check("facade.e6", Algebra.eisenstein_e6(4)[3], -122976)
q_check("facade.delta", Algebra.modular_delta(4)[3], 252)
