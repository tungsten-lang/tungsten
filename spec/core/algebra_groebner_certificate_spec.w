# Representation-carrying Buchberger certificates and ideal membership.

use algebra

-> groebner_certificate_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :grevlex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

generators = [x**2 - y, x*y - 1]
certified = Ideal.new(
  generators).certified_groebner_basis
groebner_certificate_check("basis.certified",
                            certified.certified?)
groebner_certificate_check("basis.nonempty",
                            certified.size > 0)
groebner_certificate_check("basis.theorem_boundary",
                            certified.certificate.proof_kind ==
                              :trusted_theorem_import &&
                            !certified.certificate.kernel_checked? &&
                            certified.certificate.
                              arithmetic_replay_checked?)
groebner_certificate_check("basis.source_reductions",
                            certified.certificate.
                              source_reductions.all? ->
                                item.verified? &&
                                item.zero_remainder?)
groebner_certificate_check("basis.s_pairs",
                            certified.certificate.
                              s_pair_reductions.all? ->
                                item.verified? &&
                                item.zero_remainder?)
first_pair = certified.certificate.s_pair_reductions[0]
tampered_reduction = PolynomialReductionCertificate.new(
  first_pair.dividend, first_pair.divisors,
  first_pair.quotients, R.one)
groebner_certificate_check("reduction.tamper_rejected",
                            !tampered_reduction.verified?)

derived = x**3 - 1
membership = certified.membership_certificate(derived)
groebner_certificate_check("membership.value",
                            membership.polynomial == derived)
groebner_certificate_check("membership.verified",
                            membership.verified? &&
                            membership.kernel_checked? &&
                            membership.proof_kind ==
                              :exact_ideal_membership_identity)

nonmember_rejected = false
begin
  certified.membership_certificate(x)
rescue error
  nonmember_rejected = true
groebner_certificate_check("membership.nonmember_rejected",
                            nonmember_rejected)

tampered_multipliers = []
membership.multipliers.each ->
  tampered_multipliers.push(item)
tampered_multipliers[0] += R.one
tampered_membership = (
  PolynomialIdealMembershipCertificate.new(
    derived, generators, tampered_multipliers))
groebner_certificate_check("membership.tamper_rejected",
                            !tampered_membership.verified?)

tampered_representations = []
certified.representations.each -> (representation)
  copied = []
  representation.each -> copied.push(item)
  tampered_representations.push(copied)
tampered_representations[0][0] += R.one
tampered_basis = GroebnerBasisCertificate.new(
  generators, certified.basis,
  tampered_representations,
  certified.certificate.source_reductions,
  certified.certificate.s_pair_reductions)
groebner_certificate_check("basis.tamper_rejected",
                            !tampered_basis.verified?)

unit = Ideal.new(
  [x, x - 1]).certified_groebner_basis
groebner_certificate_check("unit.basis",
                            unit.size == 1 &&
                            unit[0].one? &&
                            unit.certified?)
one_membership = unit.membership_certificate(R.one)
groebner_certificate_check("unit.membership",
                            one_membership.verified?)

zero = Ideal.new([R.zero]).certified_groebner_basis
groebner_certificate_check("zero.basis",
                            zero.size == 0 &&
                            zero.certified?)
zero_membership = zero.membership_certificate(R.zero)
groebner_certificate_check("zero.membership",
                            zero_membership.verified?)

# Extension-field coefficients are already normalized field elements.  They
# must not be embedded through the prime subfield again while making labeled
# remainders monic (in F_4 the packed element 2 would otherwise coerce to 0).
F4 = FiniteField.extension(2, 2)
R4 = PolynomialRing.new([:u, :v], F4, :grevlex)
u4, v4 = R4.generators
a4 = F4.generator
a4_plus_one = F4.add(a4, F4.one)
scaled_u = R4.monomial_raw(a4_plus_one, [1, 0]) + R4.one
extension_initial = Ideal.new(
  [scaled_u]).certified_groebner_basis
groebner_certificate_check("extension.initial_scale_certified",
                            extension_initial.certified?)
groebner_certificate_check("extension.initial_scale_monic",
                            F4.equal?(
                              extension_initial[0].leading_coefficient,
                              F4.one))

# S(u^2 + a v, u v + 1) = a v^2 - u has an extension-valued leading
# coefficient, exercising the later S-pair normalization path as well.
a4_v = R4.monomial_raw(a4, [0, 1])
extension_pairs = Ideal.new([
  u4**2 + a4_v,
  u4 * v4 + R4.one
]).certified_groebner_basis
groebner_certificate_check("extension.s_pair_scale_certified",
                            extension_pairs.certified?)
groebner_certificate_check("extension.s_pair_present",
                            extension_pairs.certificate.
                              s_pair_reductions.size > 0)
groebner_certificate_check("extension.s_pair_basis_monic",
                            extension_pairs.basis.all? ->
                              F4.equal?(
                                item.leading_coefficient,
                                F4.one))
