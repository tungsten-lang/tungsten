# Certified finite Selmer kernel and BPS plane-quartic setup.
#
#   bin/tungsten run spec/core/algebra_descent_spec.w
#   bin/tungsten compile spec/core/algebra_descent_spec.w \
#     --out /tmp/algebra-descent-spec

use algebra

-> descent_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

+ DescentSpecArithmeticCertificate
  -> new(@name, @width, matrix, right_hand_side)
    @name = @name.to_s
    @matrix = F2LinearAlgebra.copy_matrix(matrix)
    @right_hand_side = F2LinearAlgebra.copy_vector(right_hand_side)

  -> certified?
    true

  -> verified?
    true

  -> verify_selmer_constraint(name, width, matrix, right_hand_side)
    return false if name.to_s != @name || width != @width
    return false if !F2LinearAlgebra.same_matrix?(matrix, @matrix)
    F2LinearAlgebra.same_vector?(right_hand_side, @right_hand_side)

+ DescentSpecUnboundArithmeticCertificate
  -> certified?
    true

  -> verified?
    true

+ DescentSpecUncheckedArithmeticCertificate
  -> certified?
    true

  -> verified?
    false

  -> verify_selmer_constraint(name, width, matrix, right_hand_side)
    true

+ DescentSpecForgedConstraintBlock
  -> width
    2

  -> matrix
    [[1, 0]]

  -> right_hand_side
    [0]

  -> arithmetic_certified?
    true

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0

infinity = Line.new(C.space, [0, 0, 1])
hyperflex = RationalHyperflexCertificate.new(C, infinity)
descent_check("hyperflex.certified", hyperflex.certified?, true)
descent_check("hyperflex.point", hyperflex.point.to_s, "\[1:0:0\]")
descent_check("hyperflex.half_degree", hyperflex.half_intersection.degree, 2)

setup = C.jacobian.two_descent_setup(distinguished_bitangent: infinity)
descent_check("setup.geometric_prerequisites",
              setup.geometric_prerequisites_certified?, true)
descent_check("setup.not_completed_certificate", setup.certified?, false)
descent_check("setup.intended_kind", setup.intended_descent_kind, :true)
descent_check("setup.not_true_yet", setup.true_setup?, false)
descent_check("setup.expected_etale_degree", setup.expected_etale_degree, 27)
descent_check("setup.complete", setup.complete?, false)

bitangent_scheme = setup.certify_bitangent_scheme
descent_check("bitangent_scheme.certified",
              bitangent_scheme.certified?, true)
descent_check("bitangent_scheme.etale_degree",
              bitangent_scheme.etale_degree, 27)
descent_check("bitangent_scheme.component_degrees",
              bitangent_scheme.component_degrees.to_s, "\[6, 9, 12\]")
descent_check("bitangent_scheme.geometric_degree",
              bitangent_scheme.geometric_degree, 28)
descent_check("bitangent_scheme.count_theorem",
              bitangent_scheme.count_certificate.certified?, true)
descent_check("bitangent_scheme.squarefree_projection",
              bitangent_scheme.primary_certificate.squarefree?, true)
descent_check("bitangent_scheme.count_theorem_import",
              bitangent_scheme.count_certificate.proof_kind,
              :trusted_theorem_import)
descent_check("bitangent_scheme.count_not_kernel_checked",
              bitangent_scheme.count_certificate.kernel_checked?, false)

bitangent_algebra = bitangent_scheme.etale_algebra
descent_check("bitangent_algebra.certified",
              bitangent_algebra.certified?, true)
descent_check("bitangent_algebra.dimension",
              bitangent_algebra.dimension, 27)
descent_check("bitangent_algebra.component_degrees",
              bitangent_algebra.component_degrees.to_s,
              "\[6, 9, 12\]")
descent_check("bitangent_algebra.source_certificate",
              bitangent_algebra.certificate.source_certificate,
              bitangent_scheme.primary_certificate)
descent_check("bitangent_algebra.generator_relation",
              bitangent_algebra.from_polynomial(
                bitangent_scheme.projection_polynomial.monic).zero?,
              true)
descent_check("bitangent_algebra.component_maps",
              bitangent_algebra.generator.components.size, 3)
descent_check("integral_order.initially_missing",
              setup.requirements[4].status, "missing")

bps_data = setup.certify_divisor_function_data
descent_check("bps_functions.certified",
              bps_data.certified?, true)
descent_check("bps_functions.true_setup",
              setup.true_setup?, true)
descent_check("bps_functions.setup_certified",
              setup.certified?, true)
descent_check("bps_functions.etale_degree",
              bps_data.etale_degree, 27)
descent_check("bps_functions.component_degrees",
              bps_data.component_degrees.to_s,
              "\[6, 9, 12\]")
descent_check("bps_functions.contact_components",
              bps_data.contact_components.size, 3)
descent_check("bps_functions.contact_certified",
              bps_data.contact_components.all? ->
                item.certified?,
              true)
descent_check("bps_functions.beta_components",
              bps_data.beta_components.size, 3)
descent_check("bps_functions.beta_certified",
              bps_data.beta_components.all? ->
                item.certified?,
              true)
bps_beta_degrees = bps_data.beta_components.map ->
  item.relative_degree
descent_check("bps_functions.beta_relative_degrees",
              bps_beta_degrees.to_s, "\[0, 0, 0\]")
descent_check("bps_functions.function_certified",
              bps_data.function_components.all? ->
                item.certified?,
              true)
bps_multipliers = bps_data.function_components.map ->
  item.divisor_multiplier
descent_check("bps_functions.divisor_multiplier",
              bps_multipliers.to_s, "\[2, 2, 2\]")
descent_check("bps_functions.theorem_import",
              bps_data.certificate.proof_kind,
              :trusted_theorem_import)
descent_check("bps_functions.requirement_complete",
              setup.requirements[5].complete?, true)

affine_known_point = C.space.point([0, 9, 1])
bps_component_values = bps_data.evaluate_components(
  affine_known_point)
descent_check("bps_functions.point_component_count",
              bps_component_values.size, 3)
descent_check("bps_functions.point_values_are_units",
              bps_component_values.all? ->
                item.unit?,
              true)
scaled_known_point = C.space.point([0, 18, 2])
scaled_bps_values = bps_data.evaluate_components(
  scaled_known_point)
descent_check("bps_functions.projective_scale_invariant",
              scaled_bps_values.to_s,
              bps_component_values.to_s)
bps_pole_is_loud = false
begin
  bps_data.evaluate_components(hyperflex.point)
rescue error
  bps_pole_is_loud = true
descent_check("bps_functions.pole_is_loud",
              bps_pole_is_loud, true)

# The degree-27 CRT replay constructs three large Bezout idempotents. Keep the
# ordinary regression quick; the same native suite with this flag checks both
# the full executable product decomposition and the component power orders.
if env("TUNGSTEN_DESCENT_FULL") == "1"
  descent_check("bitangent_algebra.CRT_certificate",
                bitangent_algebra.
                  decomposition_certificate.verified?,
                true)
  integral_order = setup.certify_integral_product_order
  descent_check("integral_order.certified",
                integral_order.certified?, true)
  descent_check("integral_order.rank", integral_order.rank, 27)
  descent_check("integral_order.component_ranks",
                integral_order.component_ranks.to_s, "\[6, 9, 12\]")
  scales = integral_order.component_orders.map -> item.generator_scale
  descent_check("integral_order.generator_scales",
                scales.to_s, "\[16, 64, 256\]")
  descent_check("integral_order.requirement_complete",
                setup.requirements[4].complete?, true)
  bps_value = bps_data.evaluate(affine_known_point)
  descent_check("bps_functions.full_value_unit",
                bps_value.unit?, true)
  descent_check("bps_functions.CRT_round_trip",
                bps_value.components.to_s,
                bps_component_values.to_s)

if env("TUNGSTEN_DESCENT_MAXIMAL") == "1"
  maximal_order = setup.certify_maximal_product_order
  maximal_computation = setup.maximal_product_order_computation
  descent_check("maximal_order.certified",
                maximal_computation.certified?, true)
  descent_check("maximal_order.rank", maximal_order.rank, 27)
  descent_check("maximal_order.component_ranks",
                maximal_order.component_ranks.to_s, "\[6, 9, 12\]")
  maximal_discriminants = maximal_order.component_orders.map ->
    item.discriminant
  descent_check("maximal_order.component_discriminants",
                maximal_discriminants.to_s,
                "\[1168128, 133451615232, 1364523024384\]")
  descent_check("maximal_order.strict_overorder",
                maximal_computation.index > 1, true)
  descent_check("maximal_order.requirement_complete",
                setup.requirements[6].complete?, true)

if env("TUNGSTEN_DESCENT_S_PRIMES") == "1"
  s_prime_data = setup.certify_s_prime_data
  descent_check("s_primes.certified",
                s_prime_data.certified?, true)
  descent_check("s_primes.rational_primes",
                s_prime_data.rational_primes.to_s,
                "\[2, 3, 13\]")
  descent_check("s_primes.factor_count",
                s_prime_data.factor_count, 20)
  s_prime_data.decompositions.each -> (decomposition)
    local_degree = 0
    decomposition.prime_ideals.each -> (ideal)
      local_degree += ideal.ramification_index * ideal.residue_degree
    descent_check(
      "s_primes.degree_" + decomposition.prime.to_s,
      local_degree, 27)
    signatures = []
    decomposition.component_decompositions.each -> (component)
      signatures.push([
        component.ramification_indices,
        component.residue_degrees
      ])
    expected_signatures = ""
    if decomposition.prime == 2
      expected_signatures = "\[\[\[6\], \[1\]\], \[\[6, 3\], \[1, 1\]\], \[\[6\], \[2\]\]\]"
    elsif decomposition.prime == 3
      expected_signatures = "\[\[\[2, 2\], \[2, 1\]\], \[\[2, 1, 2, 1\], \[2, 1, 1, 2\]\], \[\[2, 2, 2\], \[2, 2, 2\]\]\]"
    elsif decomposition.prime == 13
      expected_signatures = "\[\[\[3, 1\], \[1, 3\]\], \[\[3\], \[3\]\], \[\[1, 1, 3, 3\], \[3, 3, 1, 1\]\]\]"
    descent_check(
      "s_primes.signature_" + decomposition.prime.to_s,
      signatures.to_s, expected_signatures)
  descent_check("s_primes.requirement_complete",
                setup.requirements[7].complete?, true)

reference_component = bitangent_scheme.primary_certificate.components[0]
component_chart = bitangent_scheme.primary_chart
factor_coefficients = [59049, -52488, 8748, 3240, -1152, 96, 16]
image_coefficients = [616734, -269001, -30132, 20124, -3000, -368]
factor = reference_component.factor
u_image = reference_component.u_image
image_numerator = u_image * 19683

wrong_factor = BitangentEtaleComponentCertificate.new(
  component_chart, factor + factor.ring.one, u_image,
  image_numerator, 19683, factor_coefficients, image_coefficients)
descent_check("bitangent_component.binds_dense_factor",
              wrong_factor.verified?, false)

wrong_image = BitangentEtaleComponentCertificate.new(
  component_chart, factor, u_image + u_image.ring.one,
  image_numerator, 19683, factor_coefficients, image_coefficients)
descent_check("bitangent_component.binds_public_image",
              wrong_image.verified?, false)

changed_image_coefficients = [
  616735, -269001, -30132, 20124, -3000, -368
]
wrong_dense_image = BitangentEtaleComponentCertificate.new(
  component_chart, factor, u_image,
  image_numerator, 19683, factor_coefficients, changed_image_coefficients)
descent_check("bitangent_component.binds_dense_image",
              wrong_dense_image.verified?, false)

zero_denominator = BitangentEtaleComponentCertificate.new(
  component_chart, factor, u_image,
  image_numerator, 0, factor_coefficients, image_coefficients)
descent_check("bitangent_component.rejects_zero_denominator",
              zero_denominator.verified?, false)

rank_error = false
begin
  setup.rank_upper_bound
rescue e
  blocker = setup.missing_requirements[0].name
  rank_error = e.to_s.index(blocker) != nil
descent_check("setup.rank_gate", rank_error, true)

conditions = SelmerConstraintSystem.new(5)
conditions.add_condition(
  "global norm",
  [[1, 1, 1, 0, 0]],
  DescentSpecArithmeticCertificate.new(
    "global norm", 5, [[1, 1, 1, 0, 0]], [0]))
conditions.add_condition(
  "unramified outside S",
  [[0, 0, 1, 1, 0]],
  DescentSpecArithmeticCertificate.new(
    "unramified outside S", 5, [[0, 0, 1, 1, 0]], [0]))
conditions.add_condition(
  "local image at 2",
  [[0, 0, 0, 1, 1]],
  DescentSpecArithmeticCertificate.new(
    "local image at 2", 5, [[0, 0, 0, 1, 1]], [0]))
intersection = conditions.solve
descent_check("constraint_block.certified",
              conditions.blocks[0].certified?, true)
descent_check("intersection.finite_certificate",
              intersection.finite_certified?, true)
descent_check("intersection.arithmetic_certificate",
              intersection.arithmetic_certified?, true)
descent_check("intersection.certified", intersection.certified?, true)
descent_check("intersection.dimension", intersection.dimension, 2)

finite_only = SelmerConstraintSystem.new(2)
finite_only.add_condition("unverified local image", [[1, 1]])
finite_result = finite_only.solve
descent_check("finite_only.linear", finite_result.finite_certified?, true)
descent_check("finite_only.not_arithmetic",
              finite_result.arithmetic_certified?, false)
descent_check("finite_only.not_certified", finite_result.certified?, false)

unbound = SelmerConstraintSystem.new(2)
unbound.add_condition(
  "unbound claim", [[1, 0]], DescentSpecUnboundArithmeticCertificate.new)
descent_check("unbound_producer.rejected",
              unbound.solve.arithmetic_certified?, false)

unchecked = SelmerConstraintSystem.new(2)
unchecked.add_condition(
  "unchecked claim", [[1, 0]],
  DescentSpecUncheckedArithmeticCertificate.new)
descent_check("unchecked_producer.rejected",
              unchecked.solve.arithmetic_certified?, false)

wrong_producer = DescentSpecArithmeticCertificate.new(
  "first condition", 2, [[1, 0]], [0])
reused = SelmerConstraintSystem.new(2)
reused.add_condition("different condition", [[0, 1]], wrong_producer)
descent_check("reused_producer.rejected",
              reused.solve.arithmetic_certified?, false)

forged_block_error = false
begin
  ExplicitSelmerIntersectionCertificate.new(
    2, [DescentSpecForgedConstraintBlock.new])
rescue e
  forged_block_error = true
descent_check("forged_constraint_block.rejected", forged_block_error, true)

missing_requirement_error = false
begin
  DescentRequirement.new("forged", "complete", "no proof")
rescue e
  missing_requirement_error = true
descent_check("completed_requirement.needs_certificate",
              missing_requirement_error, true)

comparison_error = false
begin
  intersection.rank_upper_bound
rescue e
  comparison_error = e.to_s.index("not a rank certificate") != nil
descent_check("intersection.rank_gate", comparison_error, true)

<< "algebra_descent_spec: all checks passed"
