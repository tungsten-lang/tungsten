# Replay supplied S-unit generators for all three shell-width bitangent-field
# components and certify the direct true-descent S-unit square-class space.
#
#   bin/tungsten compile scripts/algebra/shell_width_s_units_verify.w \
#     --out /tmp/shell-width-s-units-verify
#   /tmp/shell-width-s-units-verify D6_GENERATORS D9_GENERATORS \
#     D12_GENERATORS [AUXILIARY_PRIME_LIMIT] [ONLY_DEGREE|-] \
#     [LOCAL_PRIME] [LOCAL_IMAGE_MODE] [CONSTRAINT_OUTPUT]
#
# `LOCAL_IMAGE_MODE=rank` is the fail-closed, monolithic rank theorem lane. It
# replays the three S-class relation artifacts, binds the S-unit space to the
# true descent setup, computes all four complete local images, and constructs
# the BPS rank-bound certificate in one process.
#
# `LOCAL_IMAGE_MODE=saturation` additionally evaluates a rational difference
# of two degree-two closed places and tests whether it and the known rational
# point difference span the full mod-two Kummer quotient.
#
# Generator discovery is external to this checker. Every ideal support,
# archimedean sign, auxiliary residue character, and F2 rank is reconstructed
# exactly.

use algebra
use core/file

-> read_generators(path)
  out = []
  read_file(path).split("\n").each -> (line)
    if line != "" && !line.starts_with?("#")
      coefficients = []
      line.split(",").each -> (text)
        parts = text.split("/")
        if parts.size != 2
          raise "invalid S-unit generator coefficient in " + path
        coefficients.push(Rational.new(
          parts[0].to_i, parts[1].to_i))
      out.push(coefficients)
  out

-> read_relation_witnesses(path)
  out = []
  read_file(path).split("\n").each -> (line)
    if line != "" && !line.starts_with?("#")
      coefficients = []
      line.split(",").each -> (text)
        parts = text.split("/")
        if parts.size != 2
          raise "invalid S-class relation coefficient in " + path
        coefficients.push(Rational.new(
          parts[0].to_i, parts[1].to_i))
      out.push(coefficients)
  out

-> replay_s_class_proof(source_field, model_field,
                        rational_s, relation_path,
                        bounds_kind, factor_base_start)
  s_primes = []
  rational_s.each -> (rational_prime)
    model_field.prime_ideals_above(
      rational_prime).each -> (prime)
      s_primes.push(prime)
  witnesses = read_relation_witnesses(relation_path)
  replay_bounds = NumberFieldIdealGeneratorBounds.new(
    1, 1, 3, bounds_kind,
    1, 1, 1_000_000, 1,
    nil, 3, false)
  replay = model_field.search_s_class_two_torsion(
    s_primes, 0, factor_base_start,
    10_000, 250_000, 250_000,
    replay_bounds, witnesses)
  if !replay.complete? || !replay.certified?
    raise "incomplete shell-width S-class artifact " + relation_path
  NumberFieldIsomorphicSClassTwoTorsionProof.new(
    source_field, rational_s, replay.proof)

-> report_norm_local_intersection(label, norm_map,
                                  local_condition)
  system = F2LinearSystem.new(
    norm_map.source.dimension)
  norm_map.matrix.each -> (row)
    system.add_equation(
      row, 0, "global norm")
  local_condition.matrix.each -> (row)
    system.add_equation(
      row, 0,
      "complete local image")
  certificate = system.certificate
  if !certificate.certified?
    raise "shell-width norm/local intersection failed F2 replay"
  << [label + "_norm_local_dimension",
      certificate.kernel_dimension]
  << [label + "_norm_local_rank",
      certificate.rank]
  << [label + "_norm_local_certified",
      certificate.certified?]

-> report_bps_local_comparison(label, global_comparison,
                               local_theta_dimension,
                               local_image)
  comparison = global_comparison.local_comparison(
    local_theta_dimension, local_image)
  << [label + "_comparison_kernel_dimensions",
      comparison.possible_kernel_dimensions]
  << [label + "_comparison_kernel_dimension",
      comparison.local_comparison_kernel_dimension]
  << [label + "_kummer_kernel_dimension",
      comparison.kummer_kernel_dimension]
  << [label + "_w_v_dimension",
      comparison.w_v_dimension]
  << [label + "_w_v_zero",
      comparison.w_v_zero?]
  << [label + "_global_k_localization_ranks",
      comparison.possible_global_localization_ranks]
  << [label + "_global_k_localization_rank",
      comparison.global_localization_rank]
  << [label + "_global_kernel_killed",
      comparison.global_kernel_killed?]
  << [label + "_comparison_certified",
      comparison.certified?]
  comparison

-> write_local_constraint(path, norm_map,
                          local_condition)
  return nil if path == nil
  lines = []
  lines.push("# tungsten-shell-width-local-constraint-v1")
  lines.push("# prime=" +
             local_condition.rational_prime.to_s)
  lines.push("# width=" +
             norm_map.source.dimension.to_s)
  lines.push("# complete_local_image=" +
             local_condition.local_image.complete?.to_s)
  lines.push("# local_constraint_certified=" +
             local_condition.certified?.to_s)
  lines.push("# norm_map_certified=" +
             norm_map.certified?.to_s)
  norm_map.matrix.each -> (row)
    lines.push("N," + row.join(""))
  local_condition.matrix.each -> (row)
    lines.push("L," + row.join(""))
  write_file(path, lines.join("\n") + "\n")
  << ["local_constraint_output", path]

arguments = argv()
if arguments.size < 3
  << "usage: shell_width_s_units_verify D6 D9 D12 [AUX_PRIME_LIMIT]"
  exit(2)
auxiliary_prime_limit = arguments.size > 3 ? arguments[3].to_i : 100
only_degree = nil
if arguments.size > 4 && arguments[4] != "-"
  only_degree = arguments[4].to_i
local_prime_argument = arguments.size > 5 ? arguments[5] : nil
local_image_mode = arguments.size > 6 ? arguments[6] : nil
constraint_output = arguments.size > 7 ? arguments[7] : nil
saturation_requested = local_image_mode == "saturation"
rank_bound_requested = (
  local_image_mode == "rank" ||
  saturation_requested)

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)

source6 = x**6*16 + x**5*96 - x**4*1152
source6 += x**3*3240 + x**2*8748 - x*52488 + 59049
model6 = x**6 - x**5*2 + x**4 - x**3*2 - x**2 + 1
model6_certificate = NumberField.modular_irreducibility_certificate(
  model6, 20)
root6 = x**5 * Rational.new(9, 2)
root6 -= x**4 * Rational.new(15, 2)
root6 += x**3 * 3
root6 -= x**2 * Rational.new(21, 2)
root6 -= x * Rational.new(15, 2)
root6 -= 3
isomorphism6 = NumberField.isomorphic_model_irreducibility_certificate(
  source6, model6, root6, model6_certificate)
field6 = NumberField.new(source6, :a6, isomorphism6)

source9 = x**9*64 + x**8*1920 + x**7*41472
source9 += x**6*221616 - x**5*874800 - x**4*4723920
source9 += x**3*14880348 + x**2*6377292
source9 -= x*172186884
source9 += 387420489
model9 = x**9 - x**8 + x**7*6 - x**6*2
model9 -= x**5*4 + x**4*4 + x**2*4 + x*3 + 1
base9 = NumberField.new(
  x**3 - x**2*4 + x*14 - 12, :u9)
relative_ring9 = PolynomialRing.new([:z9], base9)
z9 = relative_ring9.generator(0)
relative9 = z9**3 + z9**2*(base9.one - base9.generator)
relative9 -= z9 + 1
relative_certificate9 = NumberField.relative_modular_irreducibility_certificate(
  relative9, 20)
model_certificate9 = NumberField.tower_irreducibility_certificate(
  model9, relative9, relative_certificate9)
root9 = x**8 * Rational.new(-147, 44)
root9 += x**7 * Rational.new(171, 44)
root9 -= x**6 * Rational.new(819, 44)
root9 += x**5 * Rational.new(357, 44)
root9 += x**4 * Rational.new(1053, 44)
root9 += x**3 * Rational.new(309, 44)
root9 -= x**2 * Rational.new(501, 44)
root9 -= x * Rational.new(3, 44)
root9 += Rational.new(24, 11)
isomorphism9 = NumberField.isomorphic_model_irreducibility_certificate(
  source9, model9, root9, model_certificate9)
field9 = NumberField.new(source9, :a9, isomorphism9)

source12 = x**12*256 + x**11*18432 + x**10*767232
source12 += x**9*13250304 + x**8*104976000
source12 += x**7*370355328 + x**6*85030560
source12 -= x**5*306110016
source12 += x**4*48212327520 + x**3*204558018192
source12 += x**2*83682825624 + 2541865828329
model12 = x**12 - x**11*6 + x**10*17 - x**9*30
model12 += x**8*36 - x**7*30 + x**6*19 - x**5*12
model12 += x**4*6 - x**2 + 1
base12_polynomial = x**6 - x**5*2 + x**4 - x**3*2 - x**2 + 1
base12_certificate = NumberField.modular_irreducibility_certificate(
  base12_polynomial, 20)
base12 = NumberField.new(
  base12_polynomial, :u12, base12_certificate)
relative_ring12 = PolynomialRing.new([:z12], base12)
z12 = relative_ring12.generator(0)
relative12 = z12**2 - z12 + base12.generator
relative_certificate12 = NumberField.relative_modular_irreducibility_certificate(
  relative12, 20)
model_certificate12 = NumberField.tower_irreducibility_certificate(
  model12, relative12, relative_certificate12)
root12 = x**11 * Rational.new(1467, 122)
root12 -= x**10 * Rational.new(4446, 61)
root12 += x**9 * Rational.new(12168, 61)
root12 -= x**8 * Rational.new(657, 2)
root12 += x**7 * Rational.new(43479, 122)
root12 -= x**6 * Rational.new(31329, 122)
root12 += x**5 * Rational.new(8712, 61)
root12 -= x**4 * Rational.new(6642, 61)
root12 += x**3 * Rational.new(7101, 122)
root12 += x**2 * Rational.new(2727, 122)
root12 -= x * Rational.new(189, 61)
root12 -= Rational.new(2385, 122)
isomorphism12 = NumberField.isomorphic_model_irreducibility_certificate(
  source12, model12, root12, model_certificate12)
field12 = NumberField.new(source12, :a12, isomorphism12)

rational_s = [2, 3, 13]
fields = [field6, field9, field12]
model_fields = [
  isomorphism6.model_field,
  isomorphism9.model_field,
  isomorphism12.model_field
]
bases = []
i = 0
while i < fields.size
  field = model_fields[i]
  if only_degree != nil && field.degree != only_degree
    bases.push(nil)
    i += 1
    next
  write_file("/tmp/shell-width-s-units-progress",
             "degree " + field.degree.to_s + ": S primes\n")
  s_primes = []
  rational_s.each -> (rational_prime)
    field.prime_ideals_above(
      rational_prime).each -> (prime)
      s_primes.push(prime)
  generator_coordinates = read_generators(arguments[i])
  generators = []
  generator_coordinates.each -> (coordinates)
    generators.push(field.coerce(coordinates))
  debug_kind = env("TUNGSTEN_SUNIT_SUPPORT_DEBUG")
  if debug_kind == "1"
    generator_index = 0
    generators.each -> (generator)
      write_file("/tmp/shell-width-s-units-progress",
                 "degree " + field.degree.to_s + ": support "
                 + generator_index.to_s + "\n")
      ideal = field.principal_fractional_ideal(generator)
      write_file("/tmp/shell-width-s-units-progress",
                 "degree " + field.degree.to_s + ": supported "
                 + generator_index.to_s + " factors "
                 + ideal.algebra_fractional_ideal.factors.size.to_s + "\n")
      generator_index += 1
    exit(0)
  if debug_kind == "arch"
    arch = field.archimedean_data
    generator_index = 0
    generators.each -> (generator)
      write_file("/tmp/shell-width-s-units-progress",
                 "degree " + field.degree.to_s + ": signs "
                 + generator_index.to_s + "\n")
      signs = arch.square_class_signature(generator)
      write_file("/tmp/shell-width-s-units-progress",
                 "degree " + field.degree.to_s + ": signed "
                 + generator_index.to_s + " " + signs.to_s + "\n")
      generator_index += 1
    exit(0)
  write_file("/tmp/shell-width-s-units-progress",
             "degree " + field.degree.to_s + ": basis\n")
  model_basis = field.certify_s_unit_square_class_basis(
    s_primes, generators, auxiliary_prime_limit)
  basis = NumberFieldIsomorphicSUnitSquareClassBasis.new(
    fields[i], rational_s, model_basis)
  bases.push(basis)
  character_data = []
  model_basis.residue_characters.each -> (character)
    prime = character.prime_ideal
    character_data.push([
      prime.rational_prime, prime.residue_degree
    ])
  << ["degree", field.degree,
      "dimension", model_basis.dimension,
      "characters", character_data]
  write_file("/tmp/shell-width-s-units-progress",
             "degree " + field.degree.to_s + ": certified\n")
  i += 1

exit(0) if only_degree != nil

product_order = EtaleProductOrder.new([
  source6, source9, source12
])
space = product_order.s_unit_square_class_space(
  rational_s, [[bases[0]], [bases[1]], [bases[2]]])
<< ["dimension", space.dimension]
<< ["true_descent", space.true_descent?]
<< ["modulo_diagonal", space.modulo_diagonal?]
<< ["certified", space.certified?]
<< ["proof_kind", space.certificate.proof_kind]
norm_map = space.norm_map
raise "unexpected shell-width true ambient dimension" if space.dimension != 35
raise "unexpected shell-width norm target dimension" if norm_map.target.dimension != 4
raise "unexpected shell-width norm rank" if norm_map.kernel_certificate.rank != 4
raise "unexpected shell-width norm kernel dimension" if norm_map.kernel_dimension != 31
<< ["norm_target_dimension", norm_map.target.dimension]
<< ["norm_matrix", norm_map.matrix]
<< ["norm_rank", norm_map.kernel_certificate.rank]
<< ["norm_kernel_dimension", norm_map.kernel_dimension]
<< ["norm_certified", norm_map.certified?]

local_prime_text = (
  local_prime_argument != nil ?
  local_prime_argument :
  env("TUNGSTEN_SUNIT_LOCAL_PRIME"))
local_prime_text = nil if rank_bound_requested
if local_prime_argument != nil
  << ["local_arguments", local_prime_argument, local_image_mode]
local_map = nil
if local_prime_text != nil
  local_prime = local_prime_text.to_i
  local_map = space.localization_map(local_prime)
  << ["local_prime", local_prime]
  << ["local_factor_count", local_map.local_factor_count]
  << ["local_target_dimension", local_map.target_dimension]
  local_theta_orbits = [1]
  local_map.prime_ideals.each -> (prime_ideal)
    local_theta_orbits.push(
      prime_ideal.ramification_index *
      prime_ideal.residue_degree)
  << ["local_theta_orbit_degrees",
      GenusThreeThetaPermutation.sort_integers(
        local_theta_orbits)]
  << ["local_matrix", local_map.matrix]
  << ["local_rank", local_map.rank]
  << ["local_kernel_dimension", local_map.kernel_dimension]
  << ["local_certified", local_map.certified?]
  if local_prime == 2
    raise "unexpected shell-width 2-adic factor count" if local_map.local_factor_count != 4
    raise "unexpected shell-width 2-adic target dimension" if local_map.target_dimension != 35
    raise "unexpected shell-width 2-adic localization rank" if local_map.rank != 29
    raise "unexpected shell-width 2-adic kernel dimension" if local_map.kernel_dimension != 6
  elsif local_prime == 3
    raise "unexpected shell-width 3-adic factor count" if local_map.local_factor_count != 9
    raise "unexpected shell-width 3-adic target dimension" if local_map.target_dimension != 18
    raise "unexpected shell-width 3-adic localization rank" if local_map.rank != 17
    raise "unexpected shell-width 3-adic kernel dimension" if local_map.kernel_dimension != 18
  elsif local_prime == 13
    raise "unexpected shell-width 13-adic factor count" if local_map.local_factor_count != 7
    raise "unexpected shell-width 13-adic target dimension" if local_map.target_dimension != 14
    raise "unexpected shell-width 13-adic localization rank" if local_map.rank != 13
    raise "unexpected shell-width 13-adic kernel dimension" if local_map.kernel_dimension != 22

function_data = nil
descent_setup = nil
bps_comparison = nil
rank_constraint_blocks = []
rank_kernel_local_comparison = nil
p3_local_image_requested = (
  local_image_mode == "p3" ||
  rank_bound_requested ||
  env("TUNGSTEN_SUNIT_P3_LOCAL_IMAGE") == "1" ||
  env("TUNGSTEN_SUNIT_IMPLICIT_LOCAL_IMAGE") == "1")
p2_local_image_requested = (
  local_image_mode == "p2" ||
  rank_bound_requested ||
  env("TUNGSTEN_SUNIT_P2_LOCAL_IMAGE") == "1")
need_descent_functions = (
  env("TUNGSTEN_SUNIT_POINT_VALUES") == "1" ||
  rank_bound_requested ||
  local_image_mode == "p5" ||
  local_image_mode == "p13" ||
  env("TUNGSTEN_SUNIT_GOOD_LOCAL_IMAGE") == "1" ||
  env("TUNGSTEN_SUNIT_SMOOTH_LOCAL_IMAGE") == "1" ||
  p2_local_image_requested ||
  p3_local_image_requested)
if need_descent_functions
  P2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
  B = P2.coords[0]
  S = P2.coords[1]
  Z = P2.coords[2]
  equation = B**3 * Z * 16 + B * S**2 * Z * 48
  equation -= S**4 * 3
  equation += S**3 * Z * 8
  equation += S**2 * Z**2 * 162
  equation += Z**4 * 729
  curve = Curve.new(P2, equation)
  infinity = Line.new(P2, [0, 0, 1])
  descent_setup = curve.jacobian.two_descent_setup(
    distinguished_bitangent: infinity)
  function_data = descent_setup.certify_divisor_function_data
  if rank_bound_requested
    class6 = replay_s_class_proof(
      fields[0], model_fields[0], rational_s,
      "spec/fixtures/algebra/shell_width_degree6_s_class.rel",
      :approximate, 1)
    class9 = replay_s_class_proof(
      fields[1], model_fields[1], rational_s,
      "spec/fixtures/algebra/shell_width_degree9_s_class.rel",
      :exact, 1_000)
    class12 = replay_s_class_proof(
      fields[2], model_fields[2], rational_s,
      "spec/fixtures/algebra/shell_width_degree12_s_class.rel",
      :approximate, 1)
    class_proof = EtaleProductSClassTwoTorsionProof.new(
      product_order, rational_s, [
      [class6], [class9], [class12]
    ])
    norm_constraint = (
      descent_setup.certify_global_norm_condition(
        space, class_proof))
    norm_map = norm_constraint.norm_map
    invalid_rank_space = space.dimension != 35
    invalid_rank_space = true if (
      norm_constraint.dimension != 31)
    if invalid_rank_space
      raise "unexpected arithmetic-bound shell-width norm space"
    rank_constraint_blocks.push(
      norm_constraint.constraint_block)
    << ["rank_s_class_certified", class_proof.certified?]
    << ["rank_global_norm_certified",
        norm_constraint.certified?]
  bps_comparison = (
    descent_setup.certify_bps_true_finite_comparison)
  bps_comparison = (
    descent_setup.certify_bps_true_finite_comparison)
  << ["bps_rational_two_torsion_dimension",
      bps_comparison.rational_two_torsion_dimension]
  << ["bps_global_comparison_kernel_dimension",
      bps_comparison.comparison_kernel_dimension]
  << ["bps_global_comparison_certified",
      bps_comparison.arithmetic_certified?]
  << ["bps_theorem_10_14_complete",
      bps_comparison.bps_theorem_10_14_complete?]

point_value = nil
if (env("TUNGSTEN_SUNIT_POINT_VALUES") == "1" ||
    saturation_requested)
  point_a = P2.point([0, 9, 1])
  point_b = P2.point([-3, -3, 1])
  point_value = function_data.certify_point_difference(
    space, point_a, point_b)
  expected_point_vector = [
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0
  ]
  if point_value.coordinates.to_s != expected_point_vector.to_s
    raise "unexpected shell-width rational point-difference descent vector"
  << ["point_difference", [point_a, point_b]]
  << ["point_difference_vector", point_value.coordinates]
  << ["point_difference_norm", point_value.norm_vector]
  << ["point_difference_certified", point_value.certified?]
  if local_map != nil
    known_local = local_map.certify_known_jacobian_image(
      [point_value])
    << ["known_local_prime", known_local.rational_prime]
    << ["known_local_vectors", known_local.vectors]
    << ["known_local_dimension", known_local.dimension]
    << ["known_local_lower_bound_only", known_local.lower_bound_only?]
    << ["known_local_certified", known_local.certified?]
    expected_local_vector = nil
    if known_local.rational_prime == 2
      expected_local_vector = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 1, 1, 0
      ]
    elsif known_local.rational_prime == 3
      expected_local_vector = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 1
      ]
    elsif known_local.rational_prime == 13
      expected_local_vector = [
        0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1
      ]
    if expected_local_vector != nil
      if known_local.vectors[0].to_s != expected_local_vector.to_s
        raise "unexpected shell-width known odd-local image vector"
      if known_local.dimension != 1
        raise "unexpected shell-width known odd-local image dimension"

if (rank_bound_requested ||
    local_image_mode == "p5" ||
    env("TUNGSTEN_SUNIT_GOOD_LOCAL_IMAGE") == "1")
  local_map = space.localization_map(5) if rank_bound_requested
  if local_map == nil || local_map.rational_prime != 5
    raise "shell-width complete good local image currently needs local prime 5"
  theta_fiber = descent_setup.certify_theta_fiber_at_five
  good_local_image = function_data.good_reduction_local_image(
    local_map, theta_fiber, 8)
  << ["good_local_prime", good_local_image.rational_prime]
  << ["good_local_clean_disks", good_local_image.clean_disk_count]
  << ["good_local_target_dimension", good_local_image.target_dimension]
  << ["good_local_expected_dimension", good_local_image.expected_dimension]
  << ["good_local_dimension", good_local_image.dimension]
  << ["good_local_basis", good_local_image.image_basis]
  << ["good_local_complete", good_local_image.complete?]
  << ["good_local_certified", good_local_image.certified?]
  certificate = good_local_image.certificate
  << ["good_local_residue_replay",
      certificate.arithmetic_replay_checked?]
  << ["good_local_frobenius_replay",
      certificate.frobenius_fixed_dimension_replayed?]
  if good_local_image.expected_dimension != 1
    raise "unexpected shell-width p=5 Frobenius-fixed dimension"
  if good_local_image.dimension != 1
    raise "shell-width p=5 clean disks did not span the local image"
  if !good_local_image.complete?
    raise "shell-width p=5 local image is not complete"
  good_local_comparison = (
    bps_comparison.good_reduction_local_comparison(
      theta_fiber, good_local_image))
  << ["good_local_comparison_kernel_dimension",
      good_local_comparison.local_comparison_kernel_dimension]
  << ["good_local_kummer_dimension",
      good_local_comparison.local_kummer_dimension]
  << ["good_local_kummer_kernel_dimension",
      good_local_comparison.kummer_kernel_dimension]
  << ["good_local_w_v_dimension",
      good_local_comparison.w_v_dimension]
  << ["good_local_w_v_zero",
      good_local_comparison.w_v_zero?]
  << ["good_local_comparison_certified",
      good_local_comparison.certified?]
  good_local_condition = good_local_image.local_condition
  << ["good_local_constraint_rows",
      good_local_condition.matrix.size]
  << ["good_local_preimage_dimension",
      good_local_condition.dimension]
  << ["good_local_constraint_matrix",
      good_local_condition.matrix]
  << ["good_local_constraint_certified",
      good_local_condition.certified?]
  report_norm_local_intersection(
    "good_local", norm_map,
    good_local_condition)
  write_local_constraint(
    constraint_output, norm_map,
    good_local_condition)
  if rank_bound_requested
    rank_constraint_blocks.push(
      good_local_condition.constraint_block)

if (rank_bound_requested ||
    local_image_mode == "p13" ||
    env("TUNGSTEN_SUNIT_SMOOTH_LOCAL_IMAGE") == "1")
  local_map = space.localization_map(13) if rank_bound_requested
  if local_map == nil || local_map.rational_prime == 2
    raise "shell-width smooth-locus image needs an odd local prime"
  dimension_certificate = nil
  if local_map.rational_prime == 13
    dimension_certificate = (
      curve.certify_cuspidal_regular_model(
        13, [1, 8, 1]))
    << ["cuspidal_model_certified",
        dimension_certificate.certified?]
    << ["cuspidal_normalization_genus",
        dimension_certificate.normalization_genus]
    << ["cuspidal_normalization_zeta",
        dimension_certificate.normalization_zeta_numerator]
    << ["cuspidal_normalization_jacobian_order",
        dimension_certificate.normalization_jacobian_order]
    << ["cuspidal_local_dimension_bound",
        dimension_certificate.dimension_upper_bound]
  smooth_image = function_data.smooth_locus_local_image(
    local_map, 8, dimension_certificate)
  << ["smooth_local_prime", smooth_image.rational_prime]
  << ["smooth_local_disks", smooth_image.cover.smooth_point_count]
  << ["smooth_local_singular_classes",
      smooth_image.cover.singular_point_count]
  << ["smooth_local_clean_disks", smooth_image.clean_disk_count]
  << ["smooth_local_target_dimension", smooth_image.target_dimension]
  << ["smooth_local_upper_bound", smooth_image.dimension_upper_bound]
  << ["smooth_local_dimension", smooth_image.dimension]
  << ["smooth_local_basis", smooth_image.image_basis]
  << ["smooth_local_complete", smooth_image.complete?]
  << ["smooth_local_certified", smooth_image.certified?]
  if local_map.rational_prime == 13
    if smooth_image.dimension != 2 || !smooth_image.complete?
      raise "shell-width p=13 smooth disks did not complete the local image"
  if smooth_image.complete?
    smooth_local_theta_dimension = (
      descent_setup.certify_local_theta_dimension(
        local_map))
    report_bps_local_comparison(
      "smooth_local", bps_comparison,
      smooth_local_theta_dimension,
      smooth_image)
    smooth_local_condition = smooth_image.local_condition
    << ["smooth_local_constraint_rows",
        smooth_local_condition.matrix.size]
    << ["smooth_local_preimage_dimension",
        smooth_local_condition.dimension]
    << ["smooth_local_constraint_matrix",
        smooth_local_condition.matrix]
    << ["smooth_local_constraint_certified",
        smooth_local_condition.certified?]
    report_norm_local_intersection(
      "smooth_local", norm_map,
      smooth_local_condition)
    write_local_constraint(
      constraint_output, norm_map,
      smooth_local_condition)
    if rank_bound_requested
      rank_constraint_blocks.push(
        smooth_local_condition.constraint_block)

if p2_local_image_requested
  local_map = space.localization_map(2) if rank_bound_requested
  if local_map == nil || local_map.rational_prime != 2
    raise "shell-width dyadic local image needs local prime 2"
  cover2 = curve.p_adic_smooth_residue_disks(2, 8)
  if cover2.smooth_point_count != 0
    raise "unexpected shell-width p=2 smooth residue-disk count"
  frontier = cover2.singular_cells
  dyadic_disks = []
  refinement_depth = 0
  while frontier.size > 0 && refinement_depth < 8
    next_frontier = []
    frontier.each -> (cell)
      next if cell.empty?
      refinement = cell.refine
      if !refinement.certified?
        raise "shell-width p=2 cell refinement is uncertified"
      refinement.smooth_disks.each -> (disk)
        dyadic_disks.push(disk)
      refinement.singular_children.each -> (child)
        next_frontier.push(child) if !child.empty?
    frontier = next_frontier
    refinement_depth += 1
  if frontier.size != 0
    raise "shell-width p=2 residue-cell cover remains unresolved"
  if dyadic_disks.size != 8
    raise "unexpected shell-width p=2 Hensel-disk count"

  maximum_evaluation_refinements = 1
  maximum_evaluation_text = env(
    "TUNGSTEN_SUNIT_P2_EVALUATION_REFINEMENTS")
  if (maximum_evaluation_text != nil &&
      maximum_evaluation_text != "")
    maximum_evaluation_refinements = (
      maximum_evaluation_text.to_i)
  stable_dyadic_disks = []
  unresolved_dyadic_disks = []
  unresolved_dyadic_errors = []
  evaluation_frontier = dyadic_disks
  evaluation_refinements = 0
  while evaluation_frontier.size > 0
    next_evaluation_frontier = []
    evaluation_frontier.each -> (disk)
      stable = false
      failure = nil
      begin
        PlaneQuarticBPSHenselDiskArithmetic.line_value_data(
          function_data, local_map, disk)
        stable = true
      rescue error
        failure = error.to_s
      if stable
        stable_dyadic_disks.push(disk)
      else
        if evaluation_refinements >= (
             maximum_evaluation_refinements)
          unresolved_dyadic_disks.push(disk)
          unresolved_dyadic_errors.push([
            disk.center_coordinates, failure])
        else
          disk.refine.each -> (subdisk)
            next_evaluation_frontier.push(subdisk)
    evaluation_frontier = next_evaluation_frontier
    evaluation_refinements += 1
  if stable_dyadic_disks.size == 0
    << ["dyadic_local_unresolved_errors",
        unresolved_dyadic_errors]
    raise "shell-width p=2 has no square-stable Hensel disks"

  local_theta_dimension = (
    descent_setup.certify_local_theta_dimension(
      local_map))
  << ["dyadic_local_theta_orbits",
      local_theta_dimension.orbit_signature]
  << ["dyadic_local_theta_subgroups",
      local_theta_dimension.compatible_subgroup_count]
  << ["dyadic_local_theta_possible_torsion_dimensions",
      local_theta_dimension.possible_torsion_dimensions]
  << ["dyadic_local_theta_torsion_dimension",
      local_theta_dimension.torsion_dimension]
  << ["dyadic_local_theta_analytic_dimension",
      local_theta_dimension.analytic_dimension]
  << ["dyadic_local_theta_dimension",
      local_theta_dimension.dimension]
  << ["dyadic_local_theta_certified",
      local_theta_dimension.certified?]
  if local_theta_dimension.torsion_dimension != 1
    raise "unexpected shell-width p=2 rational 2-torsion dimension"
  if local_theta_dimension.analytic_dimension != 3
    raise "unexpected shell-width p=2 analytic Kummer contribution"
  if local_theta_dimension.dimension != 4
    raise "unexpected shell-width p=2 local Kummer dimension"

  dyadic_centers = []
  stable_dyadic_disks.each -> (disk)
    dyadic_centers.push(disk.center_coordinates)
  dyadic_image = function_data.local_disk_image(
    local_map, stable_dyadic_disks,
    local_theta_dimension)
  dyadic_values = []
  dyadic_image.disk_values.each -> (value)
    dyadic_values.push(value.vector)
  << ["dyadic_local_refinement_depth",
      refinement_depth]
  << ["dyadic_local_evaluation_refinements",
      evaluation_refinements - 1]
  << ["dyadic_local_stable_disks",
      stable_dyadic_disks.size]
  << ["dyadic_local_unresolved_disks",
      unresolved_dyadic_disks.size]
  << ["dyadic_local_unresolved_errors",
      unresolved_dyadic_errors]
  << ["dyadic_local_centers", dyadic_centers]
  << ["dyadic_local_values", dyadic_values]
  << ["dyadic_local_basis", dyadic_image.image_basis]
  << ["dyadic_local_dimension", dyadic_image.dimension]
  << ["dyadic_local_lower_bound_only",
      dyadic_image.lower_bound_only?]
  << ["dyadic_local_complete",
      dyadic_image.complete?]
  << ["dyadic_local_certified",
      dyadic_image.certified?]
  if dyadic_image.dimension != 4
    raise "shell-width p=2 ordinary disks do not span the local image"
  if !dyadic_image.complete?
    raise "shell-width p=2 local image is not complete"
  report_bps_local_comparison(
    "dyadic_local", bps_comparison,
    local_theta_dimension,
    dyadic_image)
  dyadic_local_condition = dyadic_image.local_condition
  << ["dyadic_local_constraint_rows",
      dyadic_local_condition.matrix.size]
  << ["dyadic_local_preimage_dimension",
      dyadic_local_condition.dimension]
  << ["dyadic_local_constraint_matrix",
      dyadic_local_condition.matrix]
  << ["dyadic_local_constraint_certified",
      dyadic_local_condition.certified?]
  report_norm_local_intersection(
    "dyadic_local", norm_map,
    dyadic_local_condition)
  write_local_constraint(
    constraint_output, norm_map,
    dyadic_local_condition)
  if rank_bound_requested
    rank_constraint_blocks.push(
      dyadic_local_condition.constraint_block)

if p3_local_image_requested
  local_map = space.localization_map(3) if rank_bound_requested
  if local_map == nil || local_map.rational_prime != 3
    raise "shell-width implicit local image currently needs local prime 3"
  cover3 = curve.p_adic_smooth_residue_disks(3, 8)
  if cover3.smooth_point_count != 3
    raise "unexpected shell-width p=3 smooth residue-disk count"
  implicit_a = cover3.disks[0].implicit_coordinate(2)
  implicit_b = cover3.disks[1].implicit_coordinate(2)
  implicit_c = cover3.disks[2].implicit_coordinate(
    2, [1])
  implicit_d = cover3.disks[2].implicit_coordinate(
    2, [2])
  implicit_image = function_data.implicit_disk_local_image(
    local_map, [
      implicit_a, implicit_b,
      implicit_c, implicit_d])
  disk_values = implicit_image.disk_values
  << ["implicit_local_prime", implicit_image.rational_prime]
  << ["implicit_local_points", [
    implicit_a.reduction_point,
    implicit_b.reduction_point,
    implicit_c.reduction_point]]
  << ["implicit_local_centers", [
    implicit_a.center_coordinates,
    implicit_b.center_coordinates,
    implicit_c.center_coordinates,
    implicit_d.center_coordinates]]
  implicit_vectors = []
  disk_values.each -> (value)
    implicit_vectors.push(value.vector)
  << ["implicit_local_values", implicit_vectors]
  << ["implicit_local_basis", implicit_image.image_basis]
  << ["implicit_local_dimension", implicit_image.dimension]
  << ["implicit_local_lower_bound_only",
      implicit_image.lower_bound_only?]
  << ["implicit_local_certified", implicit_image.certified?]
  if implicit_image.dimension != 0
    raise "unexpected shell-width p=3 implicit-disk span"

  singular_cells = cover3.singular_cells
  if singular_cells.size != 4
    raise "unexpected shell-width p=3 singular residue-class count"
  origin_refinement = singular_cells[0].refine
  central_refinement = (
    origin_refinement.children[0].refine)
  positive_cell = central_refinement.children[0]
  positive_disk = positive_cell.refine.smooth_disks[0]
  negative_cell = origin_refinement.children[2]
  negative_disk = negative_cell.refine.smooth_disks[2]
  positive_disk = positive_disk.subdisk([0, 0])
  positive_disk = positive_disk.subdisk([0, 0])
  negative_disk = negative_disk.subdisk([2, 2])
  negative_disk = negative_disk.subdisk([2, 2])
  hensel_image = function_data.hensel_disk_local_image(
    local_map, [positive_disk, negative_disk])
  hensel_vectors = []
  hensel_image.disk_values.each -> (value)
    hensel_vectors.push(value.vector)
  << ["resolved_local_centers", [
    positive_disk.center_coordinates,
    negative_disk.center_coordinates]]
  << ["resolved_local_values", hensel_vectors]
  << ["resolved_local_basis", hensel_image.image_basis]
  << ["resolved_local_dimension", hensel_image.dimension]
  << ["resolved_local_lower_bound_only",
      hensel_image.lower_bound_only?]
  << ["resolved_local_certified",
      hensel_image.certified?]
  if hensel_image.dimension != 1
    raise "unexpected shell-width p=3 resolved branch span"

  local_theta_dimension = (
    descent_setup.certify_local_theta_dimension(
      local_map))
  << ["local_theta_orbits",
      local_theta_dimension.orbit_signature]
  << ["local_theta_subgroups",
      local_theta_dimension.compatible_subgroup_count]
  << ["local_theta_possible_dimensions",
      local_theta_dimension.possible_dimensions]
  << ["local_theta_dimension",
      local_theta_dimension.dimension]
  << ["local_theta_certified",
      local_theta_dimension.certified?]

  combined_image = function_data.local_disk_image(
    local_map, [
      implicit_a,
      positive_disk,
      negative_disk],
    local_theta_dimension)
  << ["combined_local_basis",
      combined_image.image_basis]
  << ["combined_local_dimension",
      combined_image.dimension]
  << ["combined_local_lower_bound_only",
      combined_image.lower_bound_only?]
  << ["combined_local_complete",
      combined_image.complete?]
  << ["combined_local_certified",
      combined_image.certified?]
  if combined_image.dimension != 2
    raise "unexpected shell-width p=3 combined disk span"
  if !combined_image.complete?
    raise "shell-width p=3 disk span did not complete the local image"
  combined_bps_comparison = report_bps_local_comparison(
    "combined_local", bps_comparison,
    local_theta_dimension,
    combined_image)
  combined_local_condition = combined_image.local_condition
  << ["combined_local_constraint_rows",
      combined_local_condition.matrix.size]
  << ["combined_local_preimage_dimension",
      combined_local_condition.dimension]
  << ["combined_local_constraint_matrix",
      combined_local_condition.matrix]
  << ["combined_local_constraint_certified",
      combined_local_condition.certified?]
  report_norm_local_intersection(
    "combined_local", norm_map,
    combined_local_condition)
  write_local_constraint(
    constraint_output, norm_map,
    combined_local_condition)
  if rank_bound_requested
    rank_constraint_blocks.push(
      combined_local_condition.constraint_block)
    rank_kernel_local_comparison = (
      combined_bps_comparison)

if rank_bound_requested
  if rank_constraint_blocks.size != 5
    raise "shell-width rank lane did not assemble five arithmetic blocks"
  if rank_kernel_local_comparison == nil
    raise "shell-width rank lane lacks a kernel-killing local comparison"
  intersection = ExplicitSelmerIntersectionCertificate.new(
    space.dimension, rank_constraint_blocks)
  if !intersection.certified? || intersection.dimension != 2
    raise "shell-width arithmetic explicit intersection is not dimension two"
  rank_bound = PlaneQuarticBPSRankUpperBound.new(
    bps_comparison, intersection,
    rank_kernel_local_comparison)
  << ["rank_explicit_intersection_dimension",
      intersection.dimension]
  << ["rank_explicit_intersection_certified",
      intersection.certified?]
  << ["rank_selmer_dimension_upper_bound",
      rank_bound.selmer_dimension_upper_bound]
  << ["rank_jacobian_upper_bound",
      rank_bound.rank_upper_bound]
  << ["rank_chabauty_eligible",
      rank_bound.chabauty_eligible?]
  << ["rank_bound_certified",
      rank_bound.certified?]
  if saturation_requested
    split_line = Line.new(P2, [2, 1, -3])
    split_intersection = curve.line_intersection(
      split_line)
    closed_places = []
    split_intersection.divisor.terms.each -> (term)
      place = term[1]
      if term[0] != 1 || place.class_name != "ClosedPlace"
        raise "shell-width saturation line did not split into simple closed places"
      closed_places.push(place)
    if closed_places.size != 2
      raise "shell-width saturation line did not give two closed places"
    if closed_places[0].degree != 2 || (
         closed_places[1].degree != 2)
      raise "shell-width saturation places do not both have degree two"
    << ["saturation_line", split_line]
    << ["saturation_closed_place_polynomials", [
      closed_places[0].defining_polynomial,
      closed_places[1].defining_polynomial
    ]]
    null_closed_value = (
      function_data.certify_closed_place_difference(
        space, class_proof,
        closed_places[0], closed_places[1]))
    << ["saturation_split_difference_vector",
        null_closed_value.coordinates]
    << ["saturation_split_difference_certified",
        null_closed_value.certified?]
    candidate_lines = [
      Line.new(P2, [0, 1, -9]),
      Line.new(P2, [0, 1, 3]),
      Line.new(P2, [4, -1, 9])
    ]
    closed_value = nil
    candidate_lines.each -> (candidate_line)
      intersection = curve.line_intersection(candidate_line)
      candidate_place = nil
      intersection.divisor.terms.each -> (term)
        if term[0] == 1 && (
             term[1].class_name == "ClosedPlace") && (
             term[1].degree == 2)
          candidate_place = term[1]
      if candidate_place == nil
        raise "shell-width rational-secant line has no residual quadratic place"
      candidate_value = (
        function_data.certify_closed_place_difference(
          space, class_proof,
          candidate_place, closed_places[0]))
      << ["saturation_candidate_line", candidate_line]
      << ["saturation_candidate_place_polynomial",
          candidate_place.defining_polynomial]
      << ["saturation_candidate_vector",
          candidate_value.coordinates]
      << ["saturation_candidate_certified",
          candidate_value.certified?]
      span = F2LinearSystem.new(space.dimension)
      span.add_equation(point_value.coordinates)
      span.add_equation(candidate_value.coordinates)
      closed_value = candidate_value if span.rank == 2
    if closed_value == nil
      raise "no tested rational secant divisor completed the Kummer span"
    saturation = PlaneQuarticBPSModTwoSaturation.new(
      rank_bound, [point_value, closed_value])
    << ["saturation_image_span_dimension",
        saturation.image_span_dimension]
    << ["saturation_mod_two_dimension",
        saturation.mod_two_dimension]
    << ["saturation_exact_rank",
        saturation.exact_rank]
    << ["saturation_selmer_dimension",
        saturation.selmer_dimension]
    << ["saturation_sha_two_dimension",
        saturation.sha_two_dimension]
    << ["saturation_two_saturated",
        saturation.two_saturated?]
    << ["saturation_certified",
        saturation.certified?]
