# Irreducibility certificates through exact relative number-field towers.

use algebra

-> tower_check(name, got, want)
  if got != want
    text = "FAIL " + name + ": got " + got.to_s
    raise text + ", want " + want.to_s
  << "PASS " + name

rational_ring = PolynomialRing.new(
  [:x], RationalField.new)
x = rational_ring.generator(0)
base = NumberField.new(x**2 - 2, :u)
relative_ring = PolynomialRing.new([:z], base)
z = relative_ring.generator(0)
relative = z**2 - base.generator

relative_certificate = NumberField.relative_modular_irreducibility_certificate(
    relative, 30)
tower_check("relative.prime",
            relative_certificate.prime_ideal.rational_prime, 5)
tower_check("relative.residue_degree",
            relative_certificate.prime_ideal.residue_degree, 2)
tower_check("relative.certified",
            relative_certificate.verified?, true)
tower_check("relative.proof_kind",
            relative_certificate.proof_kind,
            :relative_modular_rabin)
tower_check("relative.kernel_checked",
            relative_certificate.kernel_checked?, true)

model = x**4 - 2
tower_certificate = NumberField.tower_irreducibility_certificate(
    model, relative, relative_certificate)
tower_check("tower.certified",
            tower_certificate.verified?, true)
tower_check("tower.primitive_determinant",
            tower_certificate.primitive_element_determinant,
            Rational.new(-1))
tower_check("tower.proof_kind",
            tower_certificate.proof_kind,
            :relative_modular_tower)
model_field = NumberField.new(
  model, :m, tower_certificate)
tower_check("tower.field_degree",
            model_field.degree, 4)
tower_check("tower.field_certificate",
            model_field.irreducibility_certificate,
            tower_certificate)

# Scaling the primitive element may destroy every convenient modular witness.
# An exact expression in an already certified model transfers irreducibility
# after its minimal polynomial is replayed.
source = x**4*16 - 2
root_expression = x / 2
isomorphic_certificate = NumberField.isomorphic_model_irreducibility_certificate(
    source, model, root_expression,
    tower_certificate)
tower_check("isomorphic.certified",
            isomorphic_certificate.verified?, true)
tower_check("isomorphic.proof_kind",
            isomorphic_certificate.proof_kind,
            :isomorphic_irreducible_model)
tower_check("isomorphic.kernel_checked",
            isomorphic_certificate.kernel_checked?, true)
source_field = NumberField.new(
  source, :a, isomorphic_certificate)
tower_check("isomorphic.field_degree",
            source_field.degree, 4)
tower_check("isomorphic.generator_relation",
            (source_field.generator**4*16 - 2).zero?,
            true)

reducible_relative = z**2 - 1
bad_relative = NumberFieldRelativeModularIrreducibilityCertificate.new(
    reducible_relative,
    relative_certificate.prime_ideal)
tower_check("relative.reducible_rejected",
            bad_relative.verified?, false)

wrong_tower_failed = false
begin
  NumberField.tower_irreducibility_certificate(
    x**4 - 3, relative,
    relative_certificate)
rescue error
  wrong_tower_failed = "[error]".include?(
    "tower irreducibility certificate failed")
tower_check("tower.wrong_absolute_polynomial_rejected",
            wrong_tower_failed, true)

wrong_model_failed = false
begin
  NumberField.isomorphic_model_irreducibility_certificate(
    source, model, x, tower_certificate)
rescue error
  wrong_model_failed = "[error]".include?(
    "isomorphic-model irreducibility certificate failed")
tower_check("isomorphic.wrong_root_rejected",
            wrong_model_failed, true)

wrong_subject_failed = false
begin
  NumberField.new(x**4 - 3, :b,
                  tower_certificate)
rescue error
  wrong_subject_failed = "[error]".include?(
    "supplied number-field irreducibility certificate failed")
tower_check("tower.wrong_subject_rejected",
            wrong_subject_failed, true)

<< "algebra_number_field_tower_spec: all checks passed"
