# Checkpointable exact relation collector for the degree-nine field in the
# shell-width quartic's bitangent algebra.
#
# Compile this script: the tree-walking interpreter is intentionally not the
# production lane for this large exact-number-field workload.
#
#   bin/tungsten compile scripts/algebra/shell_width_degree9_relations.w \
#     --out /tmp/shell-width-degree9-relations
#   /tmp/shell-width-degree9-relations 0 10 10000 /tmp/d9-0.rel 1
#   /tmp/shell-width-degree9-relations 61 1 10000 /tmp/d9-61.rel 1 82
#
# Arguments are factor-base start index, factor-base count, the maximum ternary
# coefficient vectors tested for each ideal, an optional output path, and the
# coefficient height. An optional final anchor index enables AP and A^2P
# searches before P^3. Without it, each worker tests P^3 only. The artifact
# stores exact NumberField#coerce inputs.

use algebra
use core/file

args = argv()
start_index = args.size > 0 ? args[0].to_i : 0
prime_count = args.size > 1 ? args[1].to_i : 10
candidate_limit = args.size > 2 ? args[2].to_i : 10_000
output_path = args.size > 3 ? args[3] : nil
coefficient_bound = args.size > 4 ? args[4].to_i : 1
relation_anchor = args.size > 5 ? args[5].to_i : nil

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
model = x**9 - x**8 + x**7*6 - x**6*2
model -= x**5*4 + x**4*4 + x**2*4 + x*3 + 1

base = NumberField.new(
  x**3 - x**2*4 + x*14 - 12, :u)
relative_ring = PolynomialRing.new([:z], base)
z = relative_ring.generator(0)
relative = z**3 + z**2*(base.one - base.generator)
relative -= z + 1
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
  coefficient_bound, candidate_limit, 3, :exact,
  attempt_limit, total_limit,
  start_index, prime_count,
  relation_anchor, 3,
  relation_anchor != nil)
checkpoint = field.search_s_class_two_torsion(
  s_primes, 0, 1_000,
  10_000, 250_000, 250_000,
  bounds)

<< ["field_discriminant", field.field_discriminant]
<< ["factor_base_size", checkpoint.factor_base.size]
<< ["slice", start_index, prime_count, candidate_limit]
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
