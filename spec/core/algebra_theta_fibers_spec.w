# Exact finite-fiber theta labeling for the shell-width quartic.
#
# The field-linear identities are ordinary regressions.  Reconstructing all
# 27 roots and 315 contact-conic incidences is an opt-in certificate lane:
#
#   TUNGSTEN_THETA_FIBER=1 \
#     bin/tungsten run spec/core/algebra_theta_fibers_spec.w

use algebra

-> theta_fiber_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

F = FiniteField.new(5)
theta_fiber_check(
  "row_rank.full",
  ExactFieldRowReduction.rank(
    F, [[1, 2, 3], [0, 1, 4], [0, 0, 1]]),
  3)
theta_fiber_check(
  "row_rank.dependent",
  ExactFieldRowReduction.rank(
    F, [[1, 2, 3], [2, 4, 1], [0, 0, 0]]),
  1)

if env("TUNGSTEN_THETA_FIBER") == "1"
  C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0
  infinity = Line.new(C.space, [0, 0, 1])
  setup = C.two_descent_setup(
    distinguished_bitangent: infinity)
  setup.certify_bitangent_scheme
  fiber = setup.certify_theta_fiber_at_five

  theta_fiber_check("fiber.certified",
                    fiber.certified?, true)
  theta_fiber_check("fiber.field_order",
                    fiber.splitting_field.order, 15625)
  theta_fiber_check("fiber.root_count",
                    fiber.roots.size, 27)
  theta_fiber_check("fiber.labels",
                    fiber.theta_labels.sort.to_s,
                    (0..27).to_a.to_s)
  theta_fiber_check("fiber.distinguished_label",
                    fiber.distinguished_theta_label, 15)
  theta_fiber_check("fiber.frobenius_cycles",
                    fiber.source_frobenius_cycle_lengths.to_s,
                    "\[1, 3, 6, 6, 6, 6\]")
  theta_fiber_check("fiber.theta_cycles",
                    fiber.theta_permutation.cycle_lengths.to_s,
                    "\[1, 3, 6, 6, 6, 6\]")
  theta_fiber_check("fiber.F5_bitangents",
                    fiber.source_indices_defined_over(1).size, 1)
  theta_fiber_check("fiber.F125_bitangents",
                    fiber.source_indices_defined_over(3).size, 4)
  theta_fiber_check("fiber.F125_syzygetic_quadruple",
                    fiber.every_source_triple_syzygetic?(
                      fiber.source_indices_defined_over(3)), true)
  theta_fiber_check("fiber.F15625_bitangents",
                    fiber.source_indices_defined_over(6).size, 28)
  theta_fiber_check(
    "fiber.arithmetic_fiber_labeling",
    fiber.certificate.
      arithmetic_fiber_labeling_checked?,
    true)
  theta_fiber_check(
    "fiber.not_global_labeling",
    fiber.global_arithmetic_labeling_certified?,
    false)
  splitting_lines = fiber.splitting_bitangent_lines
  theta_fiber_check("fiber.splitting_bitangent_count",
                    splitting_lines.size, 28)
  theta_fiber_check("fiber.splitting_bitangents_exact",
                    splitting_lines.all? ->
                      fiber.splitting_curve.geometric_bitangent_line?(item),
                    true)
  theta_fiber_check("fiber.first_triple_azygetic",
                    fiber.source_triple_syzygetic?(
                      fiber.first_azygetic_source_triple[0],
                      fiber.first_azygetic_source_triple[1],
                      fiber.first_azygetic_source_triple[2]),
                    false)
  fixed_even = fiber.fixed_even_characteristics
  theta_fiber_check("fiber.fixed_even_nonempty",
                    fixed_even.size > 0, true)
  fixed_triple = fiber.dixon_source_triple(fixed_even[0])
  theta_fiber_check("fiber.fixed_even_triple_azygetic",
                    fiber.source_triple_syzygetic?(
                      fixed_triple[0], fixed_triple[1], fixed_triple[2]),
                    false)
  finite_dixon = fiber.dixon_representation
  theta_fiber_check("fiber.dixon_certified",
                    finite_dixon.certified?, true)
  theta_fiber_check("fiber.dixon_representation_certified",
                    finite_dixon.representation.certified?, true)
  theta_fiber_check("fiber.dixon_field_order",
                    finite_dixon.curve.field.order, 15625)
  finite_descent = FiniteFieldDeterminantalFrobeniusDescent.new(
    fiber, finite_dixon.representation)
  theta_fiber_check("fiber.descent_certified",
                    finite_descent.certified?, true)
  theta_fiber_check("fiber.descent_congruence",
                    finite_descent.frobenius_congruence_replays?, true)
  theta_fiber_check("fiber.descent_normalized_congruence",
                    finite_descent.normalized_frobenius_congruence_replays?,
                    true)
  theta_fiber_check("fiber.descent_cocycle",
                    finite_descent.normalized_cocycle_replays?, true)
  theta_fiber_check("fiber.descent_hilbert_ninety",
                    finite_descent.semilinear_fixed_matrix_replays?, true)
  theta_fiber_check("fiber.descent_scalar",
                    finite_descent.descent_scalar_replays?, true)
  theta_fiber_check("fiber.descent_reembedding",
                    finite_descent.descended_representation_replays?, true)
  theta_fiber_check("fiber.descent_field_order",
                    finite_descent.representation.curve.field.order, 5)
  expected_b = [
    [2, 4, 4, 2], [4, 0, 3, 3],
    [4, 3, 0, 3], [2, 3, 3, 3]]
  expected_s = [
    [1, 4, 2, 3], [4, 4, 4, 4],
    [2, 4, 0, 1], [3, 4, 1, 4]]
  expected_z = [
    [0, 0, 1, 0], [0, 2, 1, 1],
    [1, 1, 1, 1], [0, 1, 1, 2]]
  theta_fiber_check("fiber.descent_explicit_matrix",
                    finite_descent.representation.matrices.to_s,
                    [expected_b, expected_s, expected_z].to_s)
  theta_fiber_check("fiber.theorem_boundary",
                    fiber.certificate.proof_kind,
                    :trusted_theorem_import)
  tampered_labels = fiber.theta_labels
  first_label = tampered_labels[0]
  tampered_labels[0] = tampered_labels[1]
  tampered_labels[1] = first_label
  tampered_rejected = false
  begin
    PlaneQuarticFiniteThetaFiber.new(
      fiber.scheme_certificate, fiber.prime,
      fiber.splitting_field.modulus,
      fiber.roots, tampered_labels,
      fiber.theta_permutation.transformation.matrix)
  rescue error
    tampered_rejected = true
  theta_fiber_check("fiber.tampered_labeling_rejected",
                    tampered_rejected, true)
  theta_fiber_check("setup.still_incomplete",
                    setup.complete?, false)

<< "algebra_theta_fibers_spec: all checks passed"
