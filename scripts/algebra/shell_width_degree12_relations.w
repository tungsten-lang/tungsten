# Checkpointable exact relation collector for the degree-twelve field in the
# shell-width quartic's bitangent algebra.
#
# Compile this script: the tree-walking interpreter is intentionally not the
# production lane for this large exact-number-field workload.
#
#   bin/tungsten compile scripts/algebra/shell_width_degree12_relations.w \
#     --out /tmp/shell-width-degree12-relations
#   /tmp/shell-width-degree12-relations \
#     0 10 10000 /tmp/d12-0.rel 1 approximate
#   /tmp/shell-width-degree12-relations \
#     1000000 1 1 /tmp/d12-order.rel 1 approximate -1 500000
#
# Arguments are factor-base start index, factor-base count, the maximum
# coefficient vectors tested for each ideal, an optional output path, and the
# coefficient height, and `approximate` or `exact` for the LLL producer. An
# optional anchor index enables AP and A^2P searches before P^3; use `-1` for
# no anchor. The next optional value enables that many bounded height-one
# maximal-order candidates before the ideal slice. A final relation-artifact
# path replays an earlier checkpoint before either search. The artifact stores
# exact NumberField#coerce inputs.

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

args = argv()
start_index = args.size > 0 ? args[0].to_i : 0
prime_count = args.size > 1 ? args[1].to_i : 10
candidate_limit = args.size > 2 ? args[2].to_i : 10_000
output_path = args.size > 3 ? args[3] : nil
coefficient_bound = args.size > 4 ? args[4].to_i : 1
reduction_producer = :approximate
if args.size > 5
  if args[5] == "exact"
    reduction_producer = :exact
  elsif args[5] != "approximate"
    raise "reduction producer must be approximate or exact"
relation_anchor = nil
if args.size > 6 && args[6].to_i >= 0
  relation_anchor = args[6].to_i
order_element_limit = args.size > 7 ? args[7].to_i : 1
order_coefficient_bound = order_element_limit > 1 ? 1 : 0
initial_witnesses = []
if args.size > 8
  initial_witnesses = read_relation_witnesses(args[8])

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
model = x**12 - x**11*6 + x**10*17 - x**9*30
model += x**8*36 - x**7*30 + x**6*19 - x**5*12
model += x**4*6 - x**2 + 1

# In the model field, u = b - b^2 has the degree-six polynomial below and b
# satisfies b^2 - b + u. This relative quadratic is the kernel-checked
# irreducibility path for a field whose Galois structure prevents a
# degree-twelve irreducible reduction modulo a rational prime.
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
  model, relative, relative_certificate)
field = NumberField.new(model, :b, model_certificate)

s_primes = []
[2, 3, 13].each -> (rational_prime)
  field.prime_ideals_above(rational_prime).each -> (prime)
    s_primes.push(prime)

attempt_limit = prime_count
attempt_limit *= 3 if relation_anchor != nil
total_limit = candidate_limit * attempt_limit
bounds = NumberFieldIdealGeneratorBounds.new(
  coefficient_bound, candidate_limit, 3, reduction_producer,
  attempt_limit, total_limit,
  start_index, prime_count,
  relation_anchor, 3,
  relation_anchor != nil)
checkpoint = field.search_s_class_two_torsion(
  s_primes, order_coefficient_bound, order_element_limit,
  10_000, 250_000, 250_000,
  bounds, initial_witnesses)

<< ["field_discriminant", field.field_discriminant]
<< ["minkowski_bound", checkpoint.factor_base.bound]
<< ["factor_base_size", checkpoint.factor_base.size]
<< ["slice", start_index, prime_count, candidate_limit]
<< ["order_element_limit", order_element_limit]
<< ["initial_witness_count", initial_witnesses.size]
<< ["rank", checkpoint.rank]
<< ["tested_ideals", checkpoint.tested_ideals]
<< ["tested_ideal_elements", checkpoint.tested_ideal_elements]
<< ["resolved", checkpoint.resolved_factor_base_indices]
<< ["unresolved", checkpoint.unresolved_factor_base_indices]
<< ["anchor", checkpoint.principal_relation_anchor_index]
witnesses = checkpoint.relation_coordinate_witnesses
if output_path == nil
  << ["witnesses", witnesses]
else
  lines = []
  lines.push("# tungsten-s-class-relations-v1")
  lines.push("# field_discriminant=" + field.field_discriminant.to_s)
  lines.push("# factor_base_size=" + checkpoint.factor_base.size.to_s)
  slice_text = "# slice=" + start_index.to_s
  slice_text += "," + prime_count.to_s
  slice_text += "," + candidate_limit.to_s
  slice_text += "," + coefficient_bound.to_s
  slice_text += "," + order_element_limit.to_s
  lines.push(slice_text)
  lines.push("# resolved=" + checkpoint.resolved_factor_base_indices.to_s)
  lines.push("# unresolved=" + checkpoint.unresolved_factor_base_indices.to_s)
  witnesses.each -> (witness)
    coefficients = []
    witness.each -> (coefficient)
      text = coefficient.numerator.to_s
      coefficients.push(
        text + "/" + coefficient.denominator.to_s)
    lines.push(coefficients.join(","))
  write_file(output_path, lines.join("\n") + "\n")
  << ["output", output_path, witnesses.size]
