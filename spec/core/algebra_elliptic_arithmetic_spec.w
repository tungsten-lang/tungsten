# Certified integral minimization, local reduction, and conductors.

use algebra

-> elliptic_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

# The conductor-11 curve y^2 + y = x^3 - x^2.
e11 = IntegralWeierstrassModel.new(0, -1, 1, 0, 0)
elliptic_check("e11.discriminant", e11.discriminant, -11)
elliptic_check("e11.minimal", e11.minimal_model.same_model?(e11), true)
elliptic_check("e11.minimal_certificate",
               e11.minimal_model_computation.certificate.verified?, true)

at2 = e11.local_reduction(2)
elliptic_check("e11.good_at_2", at2.kind, :good)
elliptic_check("e11.good_exponent", at2.conductor_exponent, 0)
elliptic_check("e11.good_certificate", at2.certificate.verified?, true)

at11 = e11.local_reduction(11)
elliptic_check("e11.multiplicative_at_11", at11.kind, :multiplicative)
elliptic_check("e11.multiplicative_exponent", at11.conductor_exponent, 1)
elliptic_check("e11.local_certificate", at11.certificate.verified?, true)

e11_conductor = e11.conductor_computation
elliptic_check("e11.conductor", e11_conductor.conductor, 11)
elliptic_check("e11.conductor_certificate",
               e11_conductor.certificate.verified?, true)
bad_conductor = EllipticConductorCertificate.new(
  e11, e11_conductor.minimal_model_computation,
  e11_conductor.factorization, e11_conductor.local_reductions, 121)
elliptic_check("e11.tampered_conductor_rejected",
               bad_conductor.verified?, false)

# A visibly nonminimal integral equation scales back to the same conductor-11
# model. This exercises global composition rather than a no-op minimum.
scaled_e11 = IntegralWeierstrassModel.new(0, -4, 8, 0, 0)
scaled_minimum = scaled_e11.minimal_model_computation
elliptic_check("scaled_e11.steps",
               scaled_minimum.local_computations[0].transformations.size, 1)
elliptic_check("scaled_e11.minimum",
               scaled_minimum.model.coefficients.join(","), "0,-1,1,0,0")
elliptic_check("scaled_e11.discriminant_scaling",
               scaled_e11.discriminant, e11.discriminant * 2**12)
elliptic_check("scaled_e11.conductor", scaled_e11.conductor, 11)
elliptic_check("scaled_e11.certificate",
               scaled_minimum.certificate.verified?, true)

# For odd a=3 and even b=2, p=5, the u=2 transformation is integral:
# [0,-211,0,-7776,0] -> [1,-53,0,-486,0].
frey = FreyCurve.new(3, 2, 5)
raw = frey.model
elliptic_check("frey.raw_not_invariant_minimal",
               raw.locally_minimal_by_invariants?(2), false)
local_minimum = raw.local_minimal_model_computation(2)
elliptic_check("frey.two_minimal_steps",
               local_minimum.transformations.size, 1)
elliptic_check("frey.two_minimal_coefficients",
               local_minimum.model.coefficients.join(","), "1,-53,0,-486,0")
elliptic_check("frey.transform_certificate",
               local_minimum.transformations[0].certificate.verified?, true)
elliptic_check("frey.local_minimum_certificate",
               local_minimum.certificate.verified?, true)
elliptic_check("frey.discriminant_scaling",
               raw.discriminant,
               local_minimum.model.discriminant * 2**12)

frey_conductor = frey.model.conductor_computation
elliptic_check("frey.global_minimum",
               frey_conductor.model.coefficients.join(","), "1,-53,0,-486,0")
elliptic_check("frey.conductor", frey_conductor.conductor, 330)
elliptic_check("frey.semistable", frey_conductor.semistable?, true)
elliptic_check("frey.conductor_certificate",
               frey_conductor.certificate.verified?, true)

bad_transform = IntegralWeierstrassTransformationCertificate.new(
  raw, local_minimum.model, 2, 1, 1, 0)
elliptic_check("frey.tampered_transform_rejected",
               bad_transform.verified?, false)

limited_search_rejected = false
begin
  raw.local_minimal_model_computation(2, 63)
rescue error
  limited_search_rejected = error.to_s.include?("exceeds limit")
elliptic_check("frey.search_limit_is_unknown", limited_search_rejected, true)

# At primes >= 5 additive reduction is tame and has conductor exponent 2.
additive5 = IntegralWeierstrassModel.new(0, 0, 0, 0, 5)
at5 = additive5.local_reduction(5)
elliptic_check("additive.kind", at5.kind, :additive)
elliptic_check("additive.tame_exponent", at5.conductor_exponent, 2)
elliptic_check("additive.certificate", at5.certificate.verified?, true)

# The opposite Frey orientation is wild additive at 2. It remains explicit
# `unknown` until the small-prime branches of Tate's algorithm are present.
wild_unknown = false
begin
  FreyCurve.new(2, 3, 5).conductor
rescue error
  wild_unknown = error.to_s.include?("Tate")
elliptic_check("wild_additive_fails_loudly", wild_unknown, true)
