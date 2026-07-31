# Replay supplied S-unit generators for all three shell-width bitangent-field
# components and certify the direct true-descent S-unit square-class space.
#
#   bin/tungsten compile scripts/algebra/shell_width_s_units_verify.w \
#     --out /tmp/shell-width-s-units-verify
#   /tmp/shell-width-s-units-verify D6_GENERATORS D9_GENERATORS \
#     D12_GENERATORS [AUXILIARY_PRIME_LIMIT] [ONLY_DEGREE]
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

arguments = argv()
if arguments.size < 3
  << "usage: shell_width_s_units_verify D6 D9 D12 [AUX_PRIME_LIMIT]"
  exit(2)
auxiliary_prime_limit = arguments.size > 3 ? arguments[3].to_i : 100
only_degree = arguments.size > 4 ? arguments[4].to_i : nil

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

local_prime_text = env("TUNGSTEN_SUNIT_LOCAL_PRIME")
local_map = nil
if local_prime_text != nil && local_prime_text != ""
  local_prime = local_prime_text.to_i
  local_map = space.localization_map(local_prime)
  << ["local_prime", local_prime]
  << ["local_factor_count", local_map.local_factor_count]
  << ["local_target_dimension", local_map.target_dimension]
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
need_descent_functions = (
  env("TUNGSTEN_SUNIT_POINT_VALUES") == "1" ||
  env("TUNGSTEN_SUNIT_GOOD_LOCAL_IMAGE") == "1" ||
  env("TUNGSTEN_SUNIT_SMOOTH_LOCAL_IMAGE") == "1")
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

if env("TUNGSTEN_SUNIT_POINT_VALUES") == "1"
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

if env("TUNGSTEN_SUNIT_GOOD_LOCAL_IMAGE") == "1"
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

if env("TUNGSTEN_SUNIT_SMOOTH_LOCAL_IMAGE") == "1"
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
