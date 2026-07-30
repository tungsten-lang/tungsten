# Certified finite etale quotients, CRT decompositions, units, idempotents,
# trace, and norm.
#
# Run both ways:
#   bin/tungsten run spec/core/algebra_etale_algebra_spec.w
#   bin/tungsten compile spec/core/algebra_etale_algebra_spec.w --out /tmp/algebra-etale-spec

use algebra

-> etale_check(name, got, want)
  equal = got == want
  if got.class_name == "EtaleAlgebraElement"
    equal = got.eql?(want)
  elsif got.class_name == "Polynomial" && want.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

rq = PolynomialRing.new([:t], RationalField.new)
tq = rq.generator(0)
left_q = tq**2 - 1
right_q = tq**2 - 2
modulus_q = left_q * right_q
aq = EtaleAlgebra.new(modulus_q, [left_q, right_q])
theta_q = aq.generator

etale_check("Q.dimension", aq.dimension, 4)
etale_check("Q.component_degrees", aq.component_degrees, [2, 2])
etale_check("Q.certificate", aq.certificate.verified?, true)
etale_check("Q.decomposition_certificate",
            aq.decomposition_certificate.verified?, true)
etale_check("Q.generator_relation",
            theta_q**4 - theta_q**2*3 + 2, aq.zero)
etale_check("Q.generator_unit", theta_q.unit?, true)
etale_check("Q.generator_inverse",
            theta_q * theta_q.inverse, aq.one)
etale_check("Q.generator_trace",
            theta_q.trace, Rational.new(0))
etale_check("Q.generator_norm",
            theta_q.norm, Rational.new(2))

idempotents_q = aq.primitive_idempotents
etale_check("Q.idempotent_count", idempotents_q.size, 2)
etale_check("Q.idempotent_sum",
            idempotents_q[0] + idempotents_q[1], aq.one)
etale_check("Q.idempotent_square",
            idempotents_q[0]**2, idempotents_q[0])
etale_check("Q.idempotent_orthogonal",
            idempotents_q[0] * idempotents_q[1], aq.zero)
etale_check("Q.idempotent_zero_divisor",
            idempotents_q[0].zero_divisor?, true)

value_q = theta_q**3 + theta_q + 3
components_q = value_q.components
etale_check("Q.component_count", components_q.size, 2)
etale_check("Q.CRT_round_trip",
            aq.from_components(components_q), value_q)

zero_division_failed = false
begin
  idempotents_q[0].inverse
rescue error
  zero_division_failed = "[error]".include?("zero divisor")
etale_check("Q.zero_divisor_inverse_is_loud",
            zero_division_failed, true)

tampered_components = EtaleAlgebraCertificate.new(
  modulus_q.monic, [left_q.monic, (right_q + 1).monic])
etale_check("certificate.rejects_wrong_product",
            tampered_components.verified?, false)

repeated_failed = false
begin
  EtaleAlgebra.new(left_q**2)
rescue error
  repeated_failed = "[error]".include?("failed certification")
etale_check("nonsquarefree_is_loud", repeated_failed, true)

# A quotient need not be decomposed to be etale.
single_q = EtaleAlgebra.new(tq**3 - tq - 1)
etale_check("single.certificate", single_q.certified?, true)
etale_check("single.dimension", single_q.dimension, 3)
single_decomposition_failed = false
begin
  single_q.primitive_idempotents
rescue error
  single_decomposition_failed = "[error]".include?("no supplied")
etale_check("single.decomposition_is_loud",
            single_decomposition_failed, true)

# Positive characteristic and packed extension coefficients use the same
# quotient API without treating raw residues as external Integers.
f4 = FiniteField.extension(2, 2)
r4 = PolynomialRing.new([:u], f4)
u4 = r4.generator(0)
a4_raw = f4.generator
a4 = r4.monomial_raw(a4_raw, r4.zero_exponents)
quadratic4 = u4**2 + u4 + a4
linear4 = u4 + 1
etale4 = EtaleAlgebra.new(
  quadratic4 * linear4, [quadratic4, linear4])
theta4 = etale4.generator
embedded_a4 = etale4.embed_base_element(a4_raw)
etale_check("F4.dimension", etale4.dimension, 3)
etale_check("F4.certificate", etale4.certified?, true)
etale_check("F4.decomposition_certificate",
            etale4.decomposition_certificate.certified?, true)
etale_check("F4.raw_embedding_nonzero",
            embedded_a4.zero?, false)
etale_check("F4.generator_relation",
            etale4.from_polynomial(
              (quadratic4 * linear4).monic),
            etale4.zero)
value4 = theta4 + embedded_a4
etale_check("F4.CRT_round_trip",
            etale4.from_components(value4.components), value4)

# Derivative-zero quotients in characteristic p are non-etale.
f2 = FiniteField.new(2)
r2 = PolynomialRing.new([:z], f2)
z2 = r2.generator(0)
inseparable_failed = false
begin
  EtaleAlgebra.new(z2**2 + 1)
rescue error
  inseparable_failed = "[error]".include?("failed certification")
etale_check("F2.inseparable_is_loud", inseparable_failed, true)

<< "algebra_etale_algebra_spec: all checks passed"
