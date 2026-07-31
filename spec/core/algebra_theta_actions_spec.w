# Exact Sp6(F2) actions on the 28 odd theta characteristics and optional
# arithmetic Frobenius cycle constraints for the shell-width quartic.
#
#   bin/tungsten run spec/core/algebra_theta_actions_spec.w
#   TUNGSTEN_THETA_FROBENIUS=1 \
#     bin/tungsten run spec/core/algebra_theta_actions_spec.w

use algebra

-> theta_action_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

incidence = Algebra.genus_three_theta_incidence
space = incidence.space

identity_map = SymplecticF2Map.identity(space)
theta_action_check("identity.symplectic",
                   identity_map.certified?, true)
identity = GenusThreeThetaPermutation.new(
  incidence, identity_map)
theta_action_check("identity.theta_certified",
                   identity.certified?, true)
theta_action_check("identity.fixed_count",
                   identity.fixed_indices.size, 28)
theta_action_check("identity.cycle_count",
                   identity.cycle_lengths.size, 28)

transvection_map = SymplecticF2Map.transvection(
  space, space.vector(1))
theta_action_check("transvection.symplectic",
                   transvection_map.certified?, true)
transvection = GenusThreeThetaPermutation.new(
  incidence, transvection_map)
theta_action_check("transvection.theta_certified",
                   transvection.certified?, true)
theta_action_check("transvection.cycles",
                   transvection.cycle_lengths.to_s,
                   "\[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2\]")
lifted_transvection = (
  GenusThreeThetaPermutation.from_permutation(
    incidence, transvection.permutation))
theta_action_check("transvection.inverse_lift",
                   lifted_transvection.transformation.
                     matrix.to_s,
                   transvection_map.matrix.to_s)
transvection_group = FinitePermutationGroup.new([
  FinitePermutation.new(transvection.permutation)
])
transvection_fixed = transvection_group.theta_fixed_space(
  incidence)
theta_action_check("transvection.subgroup_fixed_certified",
                   transvection_fixed.certified?, true)
theta_action_check("transvection.subgroup_fixed_dimension",
                   transvection_fixed.dimension, 5)

action = ThetaPermutationAction.new(
  incidence, [transvection])
theta_action_check("action.certified",
                   action.certified?, true)
theta_action_check("action.orbit_sizes",
                   action.orbit_sizes.to_s,
                   "\[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2\]")

rejected = false
begin
  SymplecticF2Map.new(space, [
    [0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0]
  ])
rescue error
  rejected = true
theta_action_check("nonsymplectic.rejected", rejected, true)

# This exact symplectic matrix has the same 1+3+6+6+6+6 cycle shape as
# Frobenius at p=5 on the shell-width quartic's 28 bitangents.  The standard
# suite checks the finite theta action.  The opt-in block also factors the
# exact degree-27 projection modulo 5 and binds the two certificates.
frobenius_map = SymplecticF2Map.new(space, [
  [0, 0, 1, 0, 1, 0],
  [0, 1, 0, 1, 1, 1],
  [0, 1, 0, 0, 1, 1],
  [0, 1, 1, 1, 0, 0],
  [1, 0, 1, 0, 1, 0],
  [1, 1, 0, 0, 0, 1]
])
frobenius = GenusThreeThetaPermutation.new(
  incidence, frobenius_map)
theta_action_check("frobenius.theta_certified",
                   frobenius.certified?, true)
theta_action_check("frobenius.cycles",
                   frobenius.cycle_lengths.to_s,
                   "\[1, 3, 6, 6, 6, 6\]")
theta_action_check("frobenius.distinguished_fixed",
                   frobenius.fixed_indices.size, 1)
theta_action_check("frobenius.fixed_2_torsion_dimension",
                   frobenius_map.fixed_dimension, 1)
theta_action_check("frobenius.fixed_2_torsion_certified",
                   frobenius_map.fixed_subspace_certificate.verified?,
                   true)

if env("TUNGSTEN_THETA_FROBENIUS") == "1"
  C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0
  infinity = Line.new(C.space, [0, 0, 1])
  setup = C.two_descent_setup(
    distinguished_bitangent: infinity)
  setup.certify_bitangent_scheme
  constraint = setup.certify_theta_frobenius_constraint(
    5, frobenius, frobenius.fixed_indices[0])
  theta_action_check("constraint.certified",
                     constraint.certified?, true)
  theta_action_check("constraint.factor_degrees",
                     constraint.factor_degrees.to_s,
                     "\[3, 6, 6, 6, 6\]")
  theta_action_check("constraint.cycles",
                     constraint.cycle_lengths.to_s,
                     "\[1, 3, 6, 6, 6, 6\]")
  theta_action_check("constraint.finite_replay",
                     constraint.certificate.
                       finite_replay_checked?,
                     true)
  theta_action_check("constraint.theorem_boundary",
                     constraint.certificate.proof_kind,
                     :trusted_theorem_import)
  theta_action_check("constraint.not_arithmetic_labeling",
                     constraint.
                       arithmetic_labeling_certified?,
                     false)
  ramified_rejected = false
  begin
    setup.certify_theta_frobenius_constraint(
      11, identity, identity.fixed_indices[0])
  rescue error
    ramified_rejected = error.include?("ramified")
  theta_action_check("constraint.ramified_prime_rejected",
                     ramified_rejected, true)
  theta_action_check("setup.still_incomplete",
                     setup.complete?, false)

<< "algebra_theta_actions_spec: all checks passed"
