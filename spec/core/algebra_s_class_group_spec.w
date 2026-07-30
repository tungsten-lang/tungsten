# Unconditional S-class-group 2-torsion certificates.

use algebra

-> sclass_check(name, got, want)
  if got != want
    text = "FAIL " + name + ": got " + got.to_s
    raise text + ", want " + want.to_s
  << "PASS " + name

R = PolynomialRing.new([:t], RationalField.new)
t = R.generator(0)

# Q(sqrt(5)) has no prime ideal inside the deliberately rational upper
# Minkowski bound 2, so the empty relation matrix already proves odd class
# number (indeed class number one).
K5 = NumberField.new(t**2 - 5, :a)
factor_base5 = K5.minkowski_factor_base
sclass_check("minkowski.real_quadratic.bound",
             factor_base5.bound, 2)
sclass_check("minkowski.real_quadratic.empty",
             factor_base5.size, 0)
sclass_check("minkowski.real_quadratic.certified",
             factor_base5.certified?, true)
proof5 = K5.certify_s_class_two_torsion
sclass_check("sclass.real_quadratic.certified",
             proof5.certified?, true)
sclass_check("sclass.real_quadratic.rank",
             proof5.rank_certificate.rank, 0)
sclass_check("sclass.real_quadratic.trivial_two_torsion",
             proof5.two_torsion_trivial?, true)
sclass_check("sclass.real_quadratic.proof_kind",
             proof5.certificate.proof_kind,
             :trusted_theorem_import)
sclass_check("sclass.real_quadratic.arithmetic_replay",
             proof5.certificate.arithmetic_replay_checked?, true)
sclass_check("sclass.real_quadratic.not_kernel_theorem",
             proof5.certificate.kernel_checked?, false)

# Q(sqrt(-5)) has class group Z/2.  Its Minkowski factor base consists of the
# ramified prime above 2 and the two primes above 3.  The principal ideals of
# 1 +/- sqrt(-5) give only rank two, so an empty-S proof must be rejected.
imaginary_field = NumberField.new(t**2 + 5, :b)
b = imaginary_field.generator
factor_base_m5 = imaginary_field.minkowski_factor_base
sclass_check("minkowski.imaginary_quadratic.discriminant",
             imaginary_field.field_discriminant, -20)
sclass_check("minkowski.imaginary_quadratic.bound",
             factor_base_m5.bound, 4)
sclass_check("minkowski.imaginary_quadratic.primes",
             (factor_base_m5.primes.map ->
               item.rational_prime).to_s,
             "\[2, 3, 3\]")

relation_minus = NumberFieldPrincipalClassRelation.new(
  factor_base_m5, imaginary_field.one - b)
relation_plus = NumberFieldPrincipalClassRelation.new(
  factor_base_m5, imaginary_field.one + b)
sclass_check("relation.minus.vector",
             relation_minus.vector.to_s, "\[1, 0, 1\]")
sclass_check("relation.plus.vector",
             relation_plus.vector.to_s, "\[1, 1, 0\]")
relations_certified = relation_minus.certified?
relations_certified = false if !relation_plus.certified?
sclass_check("relation.certified",
             relations_certified, true)

empty_s_failed = false
begin
  NumberFieldSClassTwoTorsionProof.new(
    factor_base_m5,
    [imaginary_field.one - b, imaginary_field.one + b])
rescue error
  empty_s_failed = "[error]".include?(
    "do not certify trivial S-class-group 2-torsion")
sclass_check("sclass.nontrivial_two_torsion_rejected",
             empty_s_failed, true)

# The relation of 1-2b contains a prime above 7, outside the bound.  It must
# not be truncated to a bogus factor-base relation.
outside_factor_base_failed = false
begin
  NumberFieldPrincipalClassRelation.new(
    factor_base_m5, imaginary_field.one - b*2)
rescue error
  outside_factor_base_failed = "[error]".include?(
    "not supported on the displayed factor base")
sclass_check("relation.outside_factor_base_rejected",
             outside_factor_base_failed, true)

# Inverting the nontrivial class represented by the prime above 2 kills the
# class group.  The bounded search uses the canonical relation of (3) and one
# small algebraic integer; the S-prime row raises the replayed F2 rank to
# three.
P2 = imaginary_field.prime_ideals_above(2)[0]
search_m5 = NumberFieldSClassTwoTorsionSearch.new(
  imaginary_field, [P2], 1, 100)
proof_m5 = search_m5.proof
sclass_check("sclass.norm_support.accepts_relation",
             search_m5.norm_support_within_factor_base?(
               imaginary_field.one - b),
             true)
sclass_check("sclass.norm_support.rejects_outside_prime",
             search_m5.norm_support_within_factor_base?(
               imaginary_field.one - b*2),
             false)
sclass_check("sclass.localized.relation_count",
             proof_m5.principal_relations.size, 2)
sclass_check("sclass.localized.matrix",
             proof_m5.relation_matrix.to_s,
             "\[\[1, 0, 0\], \[0, 1, 1\], \[1, 0, 1\]\]")
sclass_check("sclass.localized.full_rank",
             proof_m5.rank_certificate.rank, 3)
sclass_check("sclass.localized.certified",
             proof_m5.certified?, true)
sclass_check("sclass.localized.two_torsion_trivial",
             proof_m5.certificate.proves_two_torsion_trivial?,
             true)

search_limit_failed = false
begin
  NumberFieldSClassTwoTorsionSearch.new(
    imaginary_field, [], 0, 1)
rescue error
  search_limit_failed = "[error]".include?(
    "2-torsion remains unknown")
sclass_check("sclass.search_limit_is_loud",
             search_limit_failed, true)

prime_limit_failed = false
begin
  NumberFieldMinkowskiFactorBase.new(
    imaginary_field, [], 3)
rescue error
  prime_limit_failed = "[error]".include?(
    "prime limit exceeded")
sclass_check("minkowski.prime_limit_is_loud",
             prime_limit_failed, true)

duplicate_s_failed = false
begin
  NumberFieldMinkowskiFactorBase.new(
    imaginary_field, [P2, P2])
rescue error
  duplicate_s_failed = "[error]".include?(
    "failed certification")
sclass_check("minkowski.duplicate_S_prime_rejected",
             duplicate_s_failed, true)

# A finite etale component may be reducible.  Product certification accepts a
# complete, pairwise-coprime field decomposition and independently checks
# every prime above the rational S before composing the field proofs.
S5 = K5.prime_ideals_above(2)
proof5_at_2 = K5.certify_s_class_two_torsion(
  S5, 1, 100)
reducible_order = EtaleProductOrder.new([
  (t**2 - 5) * (t**2 + 5)
])
product_proof = EtaleProductSClassTwoTorsionProof.new(
  reducible_order, [2],
  [[proof5_at_2, proof_m5]])
sclass_check("sclass.product.field_count",
             product_proof.field_count, 2)
sclass_check("sclass.product.reducible_component",
             product_proof.certified?, true)
sclass_check("sclass.product.two_torsion_trivial",
             product_proof.certificate.proves_two_torsion_trivial?,
             true)

missing_s_prime_failed = false
begin
  EtaleProductSClassTwoTorsionProof.new(
    reducible_order, [2],
    [[proof5, proof_m5]])
rescue error
  missing_s_prime_failed = "[error]".include?(
    "failed certification")
sclass_check("sclass.product.missing_S_prime_rejected",
             missing_s_prime_failed, true)

<< "algebra_s_class_group_spec: all checks passed"
