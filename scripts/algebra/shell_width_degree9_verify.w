# Merge and replay degree-nine shell-width S-class relation artifacts.
#
#   bin/tungsten compile scripts/algebra/shell_width_degree9_verify.w \
#     --out /tmp/shell-width-degree9-verify
#   /tmp/shell-width-degree9-verify \
#     spec/fixtures/algebra/shell_width_degree9_s_class.rel
#   /tmp/shell-width-degree9-verify --write /tmp/degree9.rel /tmp/d9-*.rel
#
# Incomplete rank exits 1 and is not a theorem. Full rank constructs the
# ordinary model-field certificate and then transfers it to the original
# bitangent-component presentation through the exact isomorphic-model
# certificate.

use algebra
use core/file

-> read_relation_witnesses(path)
  out = []
  File.read(path).split("\n").each -> (line)
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
  << "usage: shell_width_degree9_verify RELATION_FILE..."
  exit(2)

witnesses = []
paths.each -> (path)
  append_unique_witnesses(
    witnesses, read_relation_witnesses(path))

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
source_polynomial = x**9*64 + x**8*1920 + x**7*41472
source_polynomial += x**6*221616 - x**5*874800
source_polynomial -= x**4*4723920
source_polynomial += x**3*14880348 + x**2*6377292
source_polynomial -= x*172186884
source_polynomial += 387420489

model_polynomial = x**9 - x**8 + x**7*6 - x**6*2
model_polynomial -= x**5*4 + x**4*4 + x**2*4 + x*3 + 1

base = NumberField.new(
  x**3 - x**2*4 + x*14 - 12, :u)
relative_ring = PolynomialRing.new([:z], base)
z = relative_ring.generator(0)
relative = z**3 + z**2*(base.one - base.generator)
relative -= z + 1
relative_certificate = NumberField.relative_modular_irreducibility_certificate(
  relative, 20)
model_certificate = NumberField.tower_irreducibility_certificate(
  model_polynomial, relative, relative_certificate)

source_root = x**8 * Rational.new(-147, 44)
source_root += x**7 * Rational.new(171, 44)
source_root -= x**6 * Rational.new(819, 44)
source_root += x**5 * Rational.new(357, 44)
source_root += x**4 * Rational.new(1053, 44)
source_root += x**3 * Rational.new(309, 44)
source_root -= x**2 * Rational.new(501, 44)
source_root -= x * Rational.new(3, 44)
source_root += Rational.new(24, 11)

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
  1, 1, 3, :exact,
  1, 1, 1_000_000, 1,
  nil, 3, false)
replay = model_field.search_s_class_two_torsion(
  model_s_primes, 0, 1_000,
  10_000, 250_000, 250_000,
  replay_bounds, witnesses)

<< ["witness_count", witnesses.size]
<< ["factor_base_size", replay.factor_base.size]
<< ["rank", replay.rank]
if !replay.complete?
  << "degree-nine S-class relation artifact is incomplete"
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
  lines.push("# field_component_degree=9")
  lines.push("# field_discriminant=" + model_field.field_discriminant.to_s)
  lines.push("# rational_S=2,3,13")
  lines.push("# factor_base_size=" + replay.factor_base.size.to_s)
  lines.push("# relation_rank=" + replay.rank.to_s)
  lines.push("# model_certified=true")
  lines.push("# source_transfer_certified=true")
  witnesses.each -> (witness)
    coefficients = []
    witness.each -> (coefficient)
      text = coefficient.numerator.to_s
      coefficients.push(
        text + "/" + coefficient.denominator.to_s)
    lines.push(coefficients.join(","))
  write_file(output_path, lines.join("\n") + "\n")
  << ["output", output_path, witnesses.size]
