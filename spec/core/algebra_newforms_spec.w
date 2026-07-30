# Rational weight-two newforms recovered from exact new Hecke quotients.
#
# The q-expansion fixtures are differential records from Sage 10.9.

use algebra

-> newform_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

f11 = RationalWeightTwoNewform.new(11, 16)
expected11 = QExpansion.new([
  0, 1, -2, -1, 2, 1, 2, -2,
  0, -2, -2, 1, -2, 4, 4, -1
])
newform_check("level11.q_expansion", f11.q_expansion, expected11)
newform_check("level11.a2", f11.hecke_eigenvalue(2), Rational.new(-2))
newform_check("level11.a11", f11.hecke_eigenvalue(11), Rational.new(1))
newform_check("level11.good_prime_recurrence",
              f11.coefficient(4),
              f11.coefficient(2)**2 - Rational.new(2))
newform_check("level11.bad_prime_recurrence",
              f11.coefficient(11), f11.hecke_eigenvalue(11))
newform_check("level11.certificate", f11.certified?, true)

f33 = Algebra.rational_newform(33, 16, 100_000_000)
expected33 = QExpansion.new([
  0, 1, 1, -1, -1, -2, -1, 4,
  -3, 1, -2, 1, 1, -2, 4, 2
])
newform_check("level33.q_expansion", f33.q_expansion, expected33)
newform_check("level33.multiplicative",
              f33.coefficient(14),
              f33.coefficient(2)*f33.coefficient(7))
newform_check("level33.certificate", f33.certified?, true)

not_one_packet = false
begin
  RationalWeightTwoNewform.new(37, 8)
rescue error
  not_one_packet = true
newform_check("multiple_packets.rejected", not_one_packet, true)

bad_certificate = RationalWeightTwoNewformCertificate.new("not a newform")
newform_check("newform.tamper_rejected",
              bad_certificate.verified?, false)
