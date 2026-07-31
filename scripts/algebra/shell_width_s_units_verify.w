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
if local_prime_text != nil && local_prime_text != ""
  local_prime = local_prime_text.to_i
  local_map = space.odd_localization_map(local_prime)
  << ["local_prime", local_prime]
  << ["local_factor_count", local_map.local_factor_count]
  << ["local_target_dimension", local_map.target_dimension]
  << ["local_matrix", local_map.matrix]
  << ["local_rank", local_map.rank]
  << ["local_kernel_dimension", local_map.kernel_dimension]
  << ["local_certified", local_map.certified?]
  if local_prime == 3
    raise "unexpected shell-width 3-adic factor count" if local_map.local_factor_count != 9
    raise "unexpected shell-width 3-adic target dimension" if local_map.target_dimension != 18
    raise "unexpected shell-width 3-adic localization rank" if local_map.rank != 17
    raise "unexpected shell-width 3-adic kernel dimension" if local_map.kernel_dimension != 18
  elsif local_prime == 13
    raise "unexpected shell-width 13-adic factor count" if local_map.local_factor_count != 7
    raise "unexpected shell-width 13-adic target dimension" if local_map.target_dimension != 14
    raise "unexpected shell-width 13-adic localization rank" if local_map.rank != 13
    raise "unexpected shell-width 13-adic kernel dimension" if local_map.kernel_dimension != 22
