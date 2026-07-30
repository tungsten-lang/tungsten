# Replay degree-six shell-width S-class relation artifacts and transfer the
# result from a small monic model to the original bitangent component.
#
#   bin/tungsten compile scripts/algebra/shell_width_degree6_verify.w \
#     --out /tmp/shell-width-degree6-verify
#   /tmp/shell-width-degree6-verify --write /tmp/degree6.rel RELATION_FILE

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
  << "usage: shell_width_degree6_verify RELATION_FILE..."
  exit(2)

witnesses = []
paths.each -> (path)
  read_relation_witnesses(path).each -> (witness)
    witnesses.push(witness) if !witnesses.include?(witness)

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
source_polynomial = x**6*16 + x**5*96 - x**4*1152
source_polynomial += x**3*3240 + x**2*8748
source_polynomial -= x*52488
source_polynomial += 59049

model_polynomial = x**6 - x**5*2 + x**4 - x**3*2 - x**2 + 1
model_certificate = NumberField.modular_irreducibility_certificate(
  model_polynomial, 20)
source_root = x**5 * Rational.new(9, 2)
source_root -= x**4 * Rational.new(15, 2)
source_root += x**3 * 3
source_root -= x**2 * Rational.new(21, 2)
source_root -= x * Rational.new(15, 2)
source_root -= 3
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
  << "degree-six S-class relation artifact is incomplete"
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
  lines.push("# field_component_degree=6")
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
