# Exact replay of the finite shell-width theta subgroup candidates.

use algebra

-> theta_galois_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

certificate = Algebra.shell_width_theta_subgroup_identification
candidate = certificate.identified_candidate

theta_galois_check("table.records_replayed",
                    certificate.table.finite_records_replayed?, true)
theta_galois_check("table.completeness_boundary",
                    certificate.table.completeness_replayed?, false)
theta_galois_check("identification.verified",
                    certificate.verified?, true)
theta_galois_check("identification.unique",
                    certificate.survivors.size, 1)
theta_galois_check("identification.class",
                    candidate.class_id, 693)
theta_galois_check("identification.order",
                    candidate.group.order, 36)
theta_galois_check("identification.orbits",
                    candidate.orbit_sizes.to_s, "\[1, 6, 9, 12\]")
theta_galois_check("identification.subdegrees",
                    candidate.stabilizer_orbit_signatures_for_orbit_size(6)[0].to_s,
                    "\[1, 1, 2, 2, 2, 2, 3, 3, 6, 6\]")
theta_galois_check("identification.arithmetic_boundary",
                    certificate.arithmetic_invariants_checked?, false)
theta_galois_check("identification.global_boundary",
                    certificate.global_galois_group_certified?, false)

fixed_space = candidate.group.theta_fixed_space
theta_galois_check("fixed_space.certified",
                    fixed_space.certified?, true)
theta_galois_check("fixed_space.dimension",
                    fixed_space.dimension, 1)
theta_galois_check("fixed_space.basis",
                    fixed_space.basis.to_s,
                    "\[\[1, 0, 0, 0, 1, 1\]\]")

determinantal_fixed = candidate.group.determinantal_fixed_set
theta_galois_check("determinantal_fixed.certified",
                    determinantal_fixed.certified?, true)
theta_galois_check("determinantal_fixed.even_total",
                    determinantal_fixed.even_characteristics.size, 36)
theta_galois_check("determinantal_fixed.count",
                    determinantal_fixed.fixed_count, 1)
theta_galois_check("determinantal_fixed.characteristic",
                    determinantal_fixed.fixed_characteristics[0].characteristic.to_s,
                    "\[0, 0, 0, 1, 1, 1\]")
theta_galois_check("determinantal_fixed.permutation_obstruction",
                    determinantal_fixed.permutation_fixed_class_obstruction?,
                    false)
theta_galois_check("determinantal_fixed.arithmetic_descent_boundary",
                    determinantal_fixed.arithmetic_descent_certified?, false)
theta_galois_check("determinantal_fixed.theorem_boundary",
                    determinantal_fixed.certificate.classification_theorem_kernel_checked?,
                    false)

octad_action = determinantal_fixed.unique_fixed_octad_action
theta_galois_check("octad.labeling_certified",
                    octad_action.labeling.certified?, true)
theta_galois_check("octad.aronhold_rows",
                    octad_action.labeling.rows.size, 8)
theta_galois_check("octad.action_certified",
                    octad_action.certified?, true)
theta_galois_check("octad.action_order",
                    octad_action.group.order, candidate.group.order)
theta_galois_check("octad.geometric_theorem_boundary",
                    octad_action.labeling.certificate.geometric_correspondence_kernel_checked?,
                    false)
theta_galois_check("octad.orbit_sizes",
                    octad_action.orbit_sizes.to_s, "\[2, 6\]")
theta_galois_check("octad.etale_component_degrees",
                    octad_action.component_degrees.to_s, "\[2, 6\]")
orbit_matches = octad_action.matching_orbit_pairs
theta_galois_check("octad.bitangent_component_matches",
                    orbit_matches.size, 1)
theta_galois_check("octad.sextic_source_orbit",
                    orbit_matches[0][0].to_s,
                    "\[8, 11, 12, 13, 24, 27\]")
theta_galois_check("octad.sextic_target_orbit",
                    orbit_matches[0][1].to_s,
                    "\[2, 3, 4, 5, 6, 7\]")
theta_galois_check("octad.sextic_equivariant_map_count",
                    orbit_matches[0][2].size, 1)

subfield_profile = octad_action.subfield_profile
theta_galois_check("octad.subfield_profile_certified",
                    subfield_profile.certified?, true)
theta_galois_check("octad.index_two_subgroups",
                    subfield_profile.index_two_subgroups.size, 3)
theta_galois_check("octad.pair_quadratic_subfields",
                    subfield_profile.pair_quadratic_subfield_count, 1)
theta_galois_check("octad.sextic_quadratic_subfields",
                    subfield_profile.sextic_quadratic_subfield_count, 1)
theta_galois_check("octad.degree_twelve_quadratic_subfields",
                    subfield_profile.degree_twelve_quadratic_subfield_count,
                    3)
theta_galois_check("octad.subfield_theorem_boundary",
                    subfield_profile.certificate.galois_correspondence_kernel_checked?,
                    false)

# Cycle lengths alone leave twelve class-693 elements compatible with the
# certified p=5 finite-fiber Frobenius.  Exact Sp6(F2) conjugacy splits them
# into six genuine matches and six exhaustive linear-intertwiner
# obstructions.  Every genuine match fixes the two-point octad orbit.
p5_theta = PlaneQuarticFiniteThetaFiber.shell_width_frobenius_at_five
p5_class = octad_action.frobenius_class_test(
  p5_theta.transformation)
theta_galois_check("octad.p5_class_certified",
                    p5_class.certified?, true)
theta_galois_check("octad.p5_cycle_compatible",
                    p5_class.cycle_compatible_count, 12)
theta_galois_check("octad.p5_conjugate",
                    p5_class.matching_elements.size, 6)
theta_galois_check("octad.p5_obstructed",
                    p5_class.obstructed_elements.size, 6)
theta_galois_check("octad.p5_pair_cycles",
                    p5_class.pair_cycle_lengths.to_s, "\[1, 1\]")
theta_galois_check("octad.p5_pair_fixed",
                    p5_class.pair_fixed?, true)
theta_galois_check("octad.p5_not_pair_swapped",
                    p5_class.pair_swapped?, false)
theta_galois_check("octad.p5_finite_proof_kind",
                    p5_class.certificate.proof_kind,
                    :exact_symplectic_frobenius_class_filter)
theta_galois_check("octad.p5_arithmetic_binding_boundary",
                    p5_class.certificate.arithmetic_frobenius_binding_checked?,
                    false)
F5 = FiniteField.new(5)
theta_galois_check("octad.p5_minus_one_splits",
                    F5.square?(-1), true)
theta_galois_check("octad.p5_minus_three_inert",
                    F5.square?(-3), false)

# The small degree-six model used by the certified shell-width component
# contains sqrt(3).  The relative degree-twelve bitangent model
# z^2-z+u therefore has discriminant 1-4u in both square classes -1 and -3.
# This proves the compositum identity exactly while retaining the unresolved
# choice of the two-point octad field.
field_ring = PolynomialRing.new([:x], RationalField.new)
field_x = field_ring.generator(0)
sextic_model = field_x**6 - field_x**5*2 + field_x**4
sextic_model = sextic_model - field_x**3*2 - field_x**2 + 1
sextic_irreducibility = NumberField.modular_irreducibility_certificate(
  sextic_model, 20)
sextic_field = NumberField.new(
  sextic_model, :u, sextic_irreducibility)
u = sextic_field.generator
sqrt_three = -u**5 + u**4*2 - u**3 + u**2 + u*2
relative_discriminant = sextic_field.one - u*4
sqrt_minus_one_class = u**5 - u**4*2 + u**3 - u**2*3
sqrt_minus_three_class = u**4*Rational.new(2, 3)
sqrt_minus_three_class -= u**3*Rational.new(4, 3)
sqrt_minus_three_class += u**2*Rational.new(2, 3)
sqrt_minus_three_class -= u*Rational.new(2, 3)
sqrt_minus_three_class -= Rational.new(1, 3)
theta_galois_check("octad.sextic_sqrt_three",
                    sqrt_three**2, sextic_field.coerce(3))
theta_galois_check("octad.relative_discriminant_minus_one",
                    sqrt_minus_one_class**2,
                    -relative_discriminant)
theta_galois_check("octad.relative_discriminant_minus_three",
                    sqrt_minus_three_class**2 * -3,
                    relative_discriminant)
theta_galois_check("octad.relative_square_classes_compatible",
                    sqrt_three * sqrt_minus_three_class,
                    sqrt_minus_one_class)

comparison = PlaneQuarticBPSTrueComparison.new(certificate)
theta_galois_check("comparison.finite_certified",
                    comparison.certified?, true)
theta_galois_check("comparison.arithmetic_boundary",
                    comparison.arithmetic_certified?, false)
theta_galois_check("comparison.coordinates",
                    comparison.true_coordinate_count, 27)
theta_galois_check("comparison.alpha_dimension",
                    comparison.finite_computation.subspace_dimension, 6)
theta_galois_check("comparison.rational_two_torsion_dimension",
                    comparison.rational_two_torsion_dimension, 1)
theta_galois_check("comparison.ambient_fixed_dimension",
                    comparison.finite_computation.ambient_fixed_dimension, 3)
theta_galois_check("comparison.subspace_fixed_dimension",
                    comparison.finite_computation.subspace_fixed_dimension, 1)
theta_galois_check("comparison.quotient_fixed_dimension",
                    comparison.finite_computation.quotient_fixed_dimension, 3)
theta_galois_check("comparison.kernel_dimension",
                    comparison.comparison_kernel_dimension, 1)
theta_galois_check("comparison.theorem_boundary",
                    comparison.bps_theorem_10_14_complete?, false)

<< "algebra_theta_galois_spec: all checks passed"
