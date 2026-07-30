# Merge and replay degree-twelve shell-width S-class relation artifacts.
#
#   bin/tungsten compile scripts/algebra/shell_width_degree12_verify.w \
#     --out /tmp/shell-width-degree12-verify
#   /tmp/shell-width-degree12-verify RELATION_FILE...
#   /tmp/shell-width-degree12-verify --write /tmp/degree12.rel \
#     RELATION_FILE...
#
# Incomplete rank exits 1 and is not a theorem. Full rank constructs the
# ordinary model-field certificate and then transfers it to the original
# bitangent-component presentation through the exact isomorphic-model
# certificate.

use algebra
use core/file

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

-> append_unique_witnesses(target, source)
  source.each -> (witness)
    key = witness.to_s
    found = false
    target.each -> (existing)
      found = true if existing.to_s == key
    target.push(witness) if !found

arguments = argv()
paths = []
output_path = nil
i = 0
while i < arguments.size
  if arguments[i] == "--write"
    if i + 1 >= arguments.size
      raise "--write needs an output path"
    output_path = arguments[i + 1]
    i += 2
  else
    paths.push(arguments[i])
    i += 1
if paths.size == 0
  << "usage: shell_width_degree12_verify RELATION_FILE..."
  exit(2)

witnesses = []
paths.each -> (path)
  append_unique_witnesses(
    witnesses, read_relation_witnesses(path))

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
source_polynomial = x**12*256 + x**11*18432 + x**10*767232
source_polynomial += x**9*13250304 + x**8*104976000
source_polynomial += x**7*370355328 + x**6*85030560
source_polynomial -= x**5*306110016
source_polynomial += x**4*48212327520 + x**3*204558018192
source_polynomial += x**2*83682825624 + 2541865828329

model_polynomial = x**12 - x**11*6 + x**10*17 - x**9*30
model_polynomial += x**8*36 - x**7*30 + x**6*19 - x**5*12
model_polynomial += x**4*6 - x**2 + 1

base_polynomial = x**6 - x**5*2 + x**4 - x**3*2 - x**2 + 1
base_certificate = NumberField.modular_irreducibility_certificate(
  base_polynomial, 20)
base = NumberField.new(
  base_polynomial, :u, base_certificate)
relative_ring = PolynomialRing.new([:z], base)
z = relative_ring.generator(0)
relative = z**2 - z + base.generator
relative_certificate = NumberField.relative_modular_irreducibility_certificate(
  relative, 20)
model_certificate = NumberField.tower_irreducibility_certificate(
  model_polynomial, relative, relative_certificate)

source_root = x**11 * Rational.new(1467, 122)
source_root -= x**10 * Rational.new(4446, 61)
source_root += x**9 * Rational.new(12168, 61)
source_root -= x**8 * Rational.new(657, 2)
source_root += x**7 * Rational.new(43479, 122)
source_root -= x**6 * Rational.new(31329, 122)
source_root += x**5 * Rational.new(8712, 61)
source_root -= x**4 * Rational.new(6642, 61)
source_root += x**3 * Rational.new(7101, 122)
source_root += x**2 * Rational.new(2727, 122)
source_root -= x * Rational.new(189, 61)
source_root -= Rational.new(2385, 122)

isomorphism = NumberField.isomorphic_model_irreducibility_certificate(
  source_polynomial, model_polynomial,
  source_root, model_certificate)
source_field = NumberField.new(
  source_polynomial, :a, isomorphism)
model_field = isomorphism.model_field

rational_s = [2, 3, 13]
model_s_primes = []
rational_s.each -> (rational_prime)
  model_field.prime_ideals_above(
    rational_prime).each -> (prime)
    model_s_primes.push(prime)

# A factor-base start beyond the final column disables new ideal searches.
replay_bounds = NumberFieldIdealGeneratorBounds.new(
  1, 1, 3, :approximate,
  1, 1, 1_000_000, 1,
  nil, 3, false)
replay = model_field.search_s_class_two_torsion(
  model_s_primes, 0, 1,
  10_000, 250_000, 250_000,
  replay_bounds, witnesses)

<< ["witness_count", witnesses.size]
<< ["factor_base_size", replay.factor_base.size]
<< ["rank", replay.rank]
if !replay.complete?
  << "degree-twelve S-class relation artifact is incomplete"
  exit(1)

transferred = NumberFieldIsomorphicSClassTwoTorsionProof.new(
  source_field, rational_s, replay.proof)
<< ["model_certified", replay.certified?]
<< ["source_certified", transferred.certified?]
<< ["proof_kind", transferred.certificate.proof_kind]

if output_path != nil
  lines = []
  lines.push("# tungsten-s-class-relations-v1")
  lines.push("# theorem=Cl(O_K,S)\[2\]=0")
  lines.push("# field_component_degree=12")
  lines.push("# field_discriminant=" + model_field.field_discriminant.to_s)
  lines.push("# rational_S=2,3,13")
  lines.push("# factor_base_size=" + replay.factor_base.size.to_s)
  lines.push("# relation_rank=" + replay.rank.to_s)
  lines.push("# model_certified=true")
  lines.push("# source_transfer_certified=true")
  replay.relation_coordinate_witnesses.each -> (witness)
    coefficients = []
    witness.each -> (coefficient)
      text = coefficient.numerator.to_s
      coefficients.push(
        text + "/" + coefficient.denominator.to_s)
    lines.push(coefficients.join(","))
  write_file(output_path, lines.join("\n") + "\n")
  << ["output", output_path,
      replay.relation_coordinate_witnesses.size]
