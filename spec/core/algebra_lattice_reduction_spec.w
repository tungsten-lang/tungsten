# Exact Gram-matrix LLL reduction and number-field ideal generators.

use algebra

-> lattice_check(name, got, want)
  if got != want
    text = "FAIL " + name + ": got " + got.to_s
    raise text + ", want " + want.to_s
  << "PASS " + name

reduction = ExactGramLatticeReduction.new(
  [[1, 0], [0, 1]],
  [[4, 1], [1, 0]])
lattice_check("lll.reduced_basis",
              reduction.reduced_basis.to_s,
              "\[\[1, 0\], \[0, 1\]\]")
lattice_check("lll.transformation",
              reduction.transformation.to_s,
              "\[\[0, 1\], \[1, -4\]\]")
lattice_check("lll.orthogonal_norms",
              reduction.orthogonal_norms.to_s,
              "\[1/1, 1/1\]")
lattice_check("lll.certified",
              reduction.certified?, true)
lattice_check("lll.proof_kind",
              reduction.certificate.proof_kind,
              :exact_lll)
lattice_check("lll.kernel_checked",
              reduction.certificate.kernel_checked?, true)

indefinite_failed = false
begin
  ExactGramLatticeReduction.new(
    [[1, 0], [0, -1]])
rescue error
  indefinite_failed = "[error]".include?(
    "positive-definite symmetric Gram matrix")
lattice_check("lll.indefinite_rejected",
              indefinite_failed, true)

singular_basis_failed = false
begin
  ExactGramLatticeReduction.new(
    [[1, 0], [0, 1]],
    [[1, 0], [2, 0]])
rescue error
  singular_basis_failed = "[error]".include?(
    "full-rank integer basis")
lattice_check("lll.singular_basis_rejected",
              singular_basis_failed, true)

R = PolynomialRing.new([:t], RationalField.new)
t = R.generator(0)
field = NumberField.new(t**2 - 5, :a)
prime = field.prime_ideals_above(2)[0]
generator_search = prime.principal_generator_search(
  1, 10)
lattice_check("ideal_generator.found",
              generator_search.found?, true)
lattice_check("ideal_generator.certified",
              generator_search.certified?, true)
lattice_check("ideal_generator.proof_kind",
              generator_search.certificate.proof_kind,
              :exact_principal_ideal)
lattice_check("ideal_generator.norm",
              generator_search.generator.norm.abs,
              Rational.new(prime.norm))
lattice_check("ideal_generator.reconstructs",
              field.principal_ideal(
                generator_search.generator).eql?(
                  prime.as_ideal),
              true)

nonprincipal_field = NumberField.new(
  t**2 + 5, :b)
nonprincipal_prime = nonprincipal_field.prime_ideals_above(2)[0]
nonprincipal_search = nonprincipal_prime.principal_generator_search(
  2, 100)
lattice_check("ideal_generator.nonprincipal_not_claimed",
              nonprincipal_search.found?, false)
lattice_check("ideal_generator.nonprincipal_not_certified",
              nonprincipal_search.certified?, false)

unknown_is_loud = false
begin
  nonprincipal_prime.principal_generator(2, 100)
rescue error
  unknown_is_loud = "[error]".include?(
    "principality unknown")
lattice_check("ideal_generator.unknown_is_loud",
              unknown_is_loud, true)

<< "algebra_lattice_reduction_spec: all checks passed"
