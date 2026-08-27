# Protocol-neutral coding-theory foundations.  Run in both engines:
#
#   bin/tungsten run spec/core/coding_theory_spec.w
#   bin/tungsten compile spec/core/coding_theory_spec.w --no-lto \
#     --out /tmp/coding-theory-spec && /tmp/coding-theory-spec

use coding_theory
use ../fixtures/coding_theory/canonical_v1

-> coding_check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

-> same_elements?(field, left, right)
  return false if left.class_name != "Array" || right.class_name != "Array"
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if !field.equal?(left[i], right[i])
    i += 1
  true

-> same_rows?(field, left, right)
  return false if left.class_name != "Array" || right.class_name != "Array"
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if !same_elements?(field, left[i], right[i])
    i += 1
  true

# Array and Hash equality are identity based, so interchange checks recurse
# explicitly over the plain-data tree.
-> same_plain_data?(left, right)
  left_name = left == nil ? "Nil" : left.class_name
  right_name = right == nil ? "Nil" : right.class_name
  return false if left_name != right_name
  if left_name == "Array"
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !same_plain_data?(left[i], right[i])
      i += 1
    return true
  if left_name == "Hash"
    return false if left.size != right.size
    keys = left.keys
    i = 0
    while i < keys.size
      key = keys[i]
      return false if !right.has_key?(key)
      return false if !same_plain_data?(left[key], right[key])
      i += 1
    return true
  left == right

-> close_float?(left, right)
  (left - right).abs <= ~0.000000000001

# --- Ordered finite-field domains and affine lines -----------------------

f4 = FiniteField.new(2, [1, 1, 1])
f4_domain = FiniteFieldEvaluationDomain.canonical(f4, 4)
exposed_modulus = f4.modulus
exposed_modulus[0] = 0
coding_check("field.modulus_defensive_copy",
             f4.multiply(2, 2) == 3 && f4.modulus.to_s == "\[1, 1, 1\]")
coding_check("domain.canonical_raw_order",
             same_elements?(f4, f4_domain.points, [0, 1, 2, 3]))
coding_check("domain.raw_membership", f4_domain.include_raw?(2))
coding_check("domain.external_membership_distinct",
             f4_domain.index_of(2) == 0 && f4_domain.index_of_raw(2) == 2)

source_points = [2, 0, 3, 1]
ordered_domain = FiniteFieldEvaluationDomain.raw(f4, source_points)
source_points[0] = 1
coding_check("domain.constructor_defensive_copy",
             same_elements?(f4, ordered_domain.points, [2, 0, 3, 1]))
returned_points = ordered_domain.points
returned_points[0] = 1
coding_check("domain.getter_defensive_copy", ordered_domain.at(0) == 2)

affine = AffineLineGenerator.new(f4)
coding_check("affine.coordinates_external",
             same_elements?(f4, affine.coordinates(2), [1, 0]))
coding_check("affine.coordinates_raw",
             same_elements?(f4, affine.coordinates_raw(2), [1, 2]))
coding_check("affine.combine_external", affine.combine(1, 2, 2) == 1)
coding_check("affine.combine_raw", affine.combine_raw(1, 2, 2) == 2)

affine_image = f4_domain.affine_image_raw(1, 2)
coding_check("affine.domain_order_preserved",
             same_elements?(f4, affine_image.points, [1, 3, 2, 0]))

base_word = FiniteFieldCodeword.raw(f4, [1, 0])
direction_word = FiniteFieldCodeword.raw(f4, [2, 1])
combined_word = affine.combine_words_raw(base_word, direction_word, 2)
coding_check("affine.word_combination",
             same_elements?(f4, combined_word.symbols, [2, 2]))

bad_raw_domain = false
begin
  FiniteFieldEvaluationDomain.raw(f4, [0, 4])
rescue error
  bad_raw_domain = true
coding_check("domain.rejects_out_of_range_raw_element", bad_raw_domain)

external_collision = false
begin
  FiniteFieldEvaluationDomain.new(f4, [0, 2])
rescue error
  external_collision = true
coding_check("domain.rejects_duplicate_after_external_coercion", external_collision)

zero_affine_direction = false
begin
  f4_domain.affine_image_raw(0, 0)
rescue error
  zero_affine_direction = true
coding_check("affine.rejects_zero_domain_direction", zero_affine_direction)

bad_affine_raw = false
begin
  affine.coordinates_raw(4)
rescue error
  bad_affine_raw = true
coding_check("affine.rejects_out_of_range_raw_parameter", bad_affine_raw)

# --- Reed-Solomon evaluation ---------------------------------------------

f7 = FiniteField.new(7)
rs_domain = FiniteFieldEvaluationDomain.canonical(f7, 4)
rs = ReedSolomonCode.new(rs_domain, 3)
rs_word = rs.encode_raw([3, 2, 1])
coding_check("rs.fixture",
             same_elements?(f7, rs_word.symbols, [3, 6, 4, 4]))
coding_check("rs.parameters",
             rs.length == 4 && rs.degree_bound == 3 && rs.dimension == 3)
coding_check("rs.distance_rate",
             rs.minimum_distance == 2 && rs.rate == Rational.new(3, 4))
coding_check("rs.injective", rs.encoder_injective? && !rs.zero_code?)
coding_check("rs.membership",
             rs.contains?(rs_word) && rs.include?(rs_word))
rs_nonmember = FiniteFieldCodeword.raw(f7, [0, 0, 0, 1])
coding_check("rs.rejects_nonmember_predicate", !rs.contains?(rs_nonmember))
coding_check("rs.polynomial_evaluation",
             rs.encode_polynomial(rs.message_polynomial_raw([3, 2, 1])) == rs_word)

# In an extension field, ordinary inputs are external prime-subfield scalars;
# raw inputs are packed extension elements.  These two calls must differ.
f4_rs = ReedSolomonCode.new(f4_domain, 2)
f4_external_word = f4_rs.encode([1, 2])
f4_raw_word = f4_rs.encode_raw([1, 2])
coding_check("rs.external_coefficients",
             same_elements?(f4, f4_external_word.symbols, [1, 1, 1, 1]))
coding_check("rs.raw_extension_coefficients",
             same_elements?(f4, f4_raw_word.symbols, [1, 3, 2, 0]))
coding_check("rs.raw_extension_polynomial",
             f4_rs.encode_polynomial(
               f4_rs.message_polynomial_raw([1, 2])) == f4_raw_word)
f4.prepare_arithmetic!
coding_check("rs.prepared_extension_arithmetic",
             f4.arithmetic_prepared? &&
             f4_rs.encode_raw([1, 2]) == f4_raw_word)

# Caller-supplied domain order is coordinate order, not a set to sort.
ordered_rs = ReedSolomonCode.new(ordered_domain, 2)
coding_check("rs.ordered_domain",
             same_elements?(f4, ordered_rs.encode_raw([1, 2]).symbols,
                            [2, 1, 0, 3]))

# Degree bounds larger than the block length remain executable, but their
# dimensions saturate and their encoders are explicitly noninjective.
saturated = ReedSolomonCode.new(rs_domain, 6)
coding_check("rs.saturated_metadata",
             saturated.dimension == 4 && !saturated.encoder_injective? &&
             saturated.minimum_distance == 1)
coding_check("rs.saturated_accepts_ambient_word",
             saturated.contains?(
               saturated.codeword_raw([1, 2, 3, 4])))
vanishing_message = [0, 1, 4, 1, 1, 0]
coding_check("rs.saturated_kernel_witness",
             same_elements?(f7, saturated.encode_raw(vanishing_message).symbols,
                            [0, 0, 0, 0]))

zero_rs = ReedSolomonCode.new(rs_domain, 0)
coding_check("rs.zero_code_metadata",
             zero_rs.dimension == 0 && zero_rs.zero_code? &&
             zero_rs.minimum_distance == 0 &&
             zero_rs.rate == Rational.new(0, 4))
coding_check("rs.zero_code_encoding",
             same_elements?(f7, zero_rs.encode([]).symbols, [0, 0, 0, 0]))

zero_nonmember = false
begin
  zero_rs.codeword_raw([0, 0, 0, 1])
rescue error
  zero_nonmember = true
coding_check("rs.zero_code_rejects_nonmember", zero_nonmember)

bad_rs_message = false
begin
  rs.encode_raw([3, 2])
rescue error
  bad_rs_message = true
coding_check("rs.rejects_wrong_message_length", bad_rs_message)

bad_rs_raw = false
begin
  f4_rs.encode_raw([1, 4])
rescue error
  bad_rs_raw = true
coding_check("rs.rejects_out_of_range_raw_coefficient", bad_rs_raw)

bad_rs_codeword = false
begin
  rs.codeword_raw([1, 2, 3])
rescue error
  bad_rs_codeword = true
coding_check("rs.rejects_wrong_codeword_length", bad_rs_codeword)

bad_rs_membership = false
begin
  rs.codeword_raw(rs_nonmember.symbols)
rescue error
  bad_rs_membership = true
coding_check("rs.codeword_constructor_checks_membership", bad_rs_membership)

foreign_polynomial = PolynomialRing.new([:x], FiniteField.new(5)).generator(0)
bad_rs_field = false
begin
  rs.encode_polynomial(foreign_polynomial)
rescue error
  bad_rs_field = true
coding_check("rs.rejects_foreign_polynomial", bad_rs_field)

high_polynomial = (
  rs.message_polynomial_raw([0, 0, 1]) *
  PolynomialRing.new([:x], f7).generator(0))
bad_rs_degree = false
begin
  rs.encode_polynomial(high_polynomial)
rescue error
  bad_rs_degree = true
coding_check("rs.rejects_polynomial_at_degree_bound", bad_rs_degree)

# Codewords own both constructor inputs and values returned by accessors.
source_symbols = [1, 3, 2, 0]
owned_scalar_word = FiniteFieldCodeword.raw(f4, source_symbols)
source_symbols[0] = 0
copy_symbols = owned_scalar_word.symbols
copy_symbols[1] = 0
coding_check("codeword.scalar_defensive_copies",
             same_elements?(f4, owned_scalar_word.symbols, [1, 3, 2, 0]))

# --- Interleaved Reed-Solomon --------------------------------------------

interleaved_domain = FiniteFieldEvaluationDomain.canonical(f7, 3)
irs = InterleavedReedSolomonCode.new(interleaved_domain, 5, 2)
coding_check("irs.floor_metadata",
             irs.requested_dimension == 5 && irs.lane_degree_bound == 2 &&
             irs.message_size == 4 && irs.dimension == 4 &&
             irs.floor_remainder == 1 && irs.saturation_loss == 0 &&
             irs.unrepresented_budget == 1 && !irs.budget_exact?)
coding_check("irs.code_metadata",
             irs.length == 3 && irs.interleaving == 2 &&
             irs.component_dimension == 2 && irs.encoder_injective? &&
             irs.minimum_distance == 2 && irs.rate == Rational.new(2, 3))

columns = [[1, 2], [3, 4]]
irs_word = irs.encode_columns_raw(columns)
expected_rows = [[1, 3], [3, 0], [5, 4]]
coding_check("irs.column_encoding",
             same_rows?(f7, irs_word.rows, expected_rows))
coding_check("irs.membership", irs.contains?(irs_word) && irs.include?(irs_word))
coding_check("irs.lane_major_encoding",
             irs.encode_lane_major_raw([1, 2, 3, 4]) == irs_word)

columns[0][0] = 6
returned_rows = irs_word.rows
returned_rows[0][0] = 6
single_row = irs_word.row(1)
single_row[0] = 6
coding_check("codeword.interleaved_defensive_copies",
             same_rows?(f7, irs_word.rows, expected_rows))

bad_floor_message = false
begin
  irs.encode_lane_major_raw([1, 2, 3, 4, 5])
rescue error
  bad_floor_message = true
coding_check("irs.never_drops_floor_remainder", bad_floor_message)

bad_lane_count = false
begin
  irs.encode_columns_raw([[1, 2]])
rescue error
  bad_lane_count = true
coding_check("irs.rejects_wrong_lane_count", bad_lane_count)

bad_lane_length = false
begin
  irs.encode_columns_raw([[1], [3, 4]])
rescue error
  bad_lane_length = true
coding_check("irs.rejects_ragged_message", bad_lane_length)

bad_interleaving = false
begin
  InterleavedReedSolomonCode.new(interleaved_domain, 5, 0)
rescue error
  bad_interleaving = true
coding_check("irs.rejects_zero_interleaving", bad_interleaving)

bad_interleaved_word = false
begin
  irs.codeword_raw([[1, 3], [3], [5, 4]])
rescue error
  bad_interleaved_word = true
coding_check("irs.rejects_ragged_codeword", bad_interleaved_word)

irs_nonmember = InterleavedCodeword.raw(
  f7, [[1, 3], [3, 0], [0, 4]], 2)
coding_check("irs.rejects_nonmember_predicate", !irs.contains?(irs_nonmember))
bad_irs_membership = false
begin
  irs.codeword_raw(irs_nonmember.rows)
rescue error
  bad_irs_membership = true
coding_check("irs.codeword_constructor_checks_membership", bad_irs_membership)

small_budget_irs = InterleavedReedSolomonCode.new(
  interleaved_domain, 1, 2)
coding_check("irs.budget_below_interleaving",
             small_budget_irs.lane_degree_bound == 0 &&
             small_budget_irs.dimension == 0 &&
             small_budget_irs.floor_remainder == 1 &&
             small_budget_irs.minimum_distance == 0 &&
             same_rows?(f7, small_budget_irs.encode_raw([[], []]).rows,
                        [[0, 0], [0, 0], [0, 0]]))

saturated_irs = InterleavedReedSolomonCode.new(
  interleaved_domain, 14, 2)
coding_check("irs.saturation_metadata",
             saturated_irs.lane_degree_bound == 7 &&
             saturated_irs.component_dimension == 3 &&
             saturated_irs.message_size == 14 &&
             saturated_irs.dimension == 6 &&
             saturated_irs.floor_remainder == 0 &&
             saturated_irs.saturation_loss == 8 &&
             saturated_irs.unrepresented_budget == 8 &&
             !saturated_irs.encoder_injective? &&
             saturated_irs.minimum_distance == 1)

# The flat external path must not coerce an extension element twice after it
# splits lane-major storage into columns.
f4_irs = InterleavedReedSolomonCode.new(f4_domain, 4, 2)
f4_irs_raw_columns = [[1, 2], [0, 1]]
f4_irs_external_columns = [[1, [0, 1]], [0, 1]]
f4_irs_word = f4_irs.encode_columns_raw(f4_irs_raw_columns)
coding_check("irs.extension_external_columns",
             f4_irs.encode_columns(f4_irs_external_columns) == f4_irs_word)
coding_check("irs.extension_external_lane_major",
             f4_irs.encode_lane_major([1, [0, 1], 0, 1]) == f4_irs_word)

# --- Agreement and Hamming metrics --------------------------------------

# Metrics deliberately accept ambient/received words as well as members of the
# code.  Use the generic owned word type for the corrupted observation.
equal_copy = InterleavedCodeword.raw(f7, [[1, 3], [3, 0], [5, 4]], 2)
two_lane_change_one_block = InterleavedCodeword.raw(
  f7, [[2, 2], [3, 0], [5, 4]], 2)
coding_check("metrics.structural_whole_block_equality",
             CodingTheoryMetrics.agreement_count(irs_word, equal_copy) == 3)
coding_check("metrics.whole_block_distance",
             CodingTheoryMetrics.hamming_distance(
               irs_word, two_lane_change_one_block) == 1)
coding_check("metrics.component_distances",
             CodingTheoryMetrics.component_hamming_distance(
               irs_word, two_lane_change_one_block, 0) == 1 &&
             CodingTheoryMetrics.component_hamming_distance(
               irs_word, two_lane_change_one_block, 1) == 1)
coding_check("metrics.exact_fractions",
             CodingTheoryMetrics.agreement_fraction(
               irs_word, two_lane_change_one_block) == Rational.new(2, 3) &&
             CodingTheoryMetrics.relative_distance(
               irs_word, two_lane_change_one_block) == Rational.new(1, 3))
coding_check("metrics.agreement_indices",
             same_elements?(f7,
               CodingTheoryMetrics.agreement_indices(
                 irs_word, two_lane_change_one_block), [1, 2]))
coding_check("metrics.enumerated_ball",
             CodingTheoryMetrics.enumerated_ball_count(
               [irs_word, equal_copy, two_lane_change_one_block],
               irs_word, 0) == 2 &&
             CodingTheoryMetrics.enumerated_ball_count(
               [irs_word, equal_copy, two_lane_change_one_block],
               irs_word, 1) == 3)

bad_metric_shape = false
begin
  CodingTheoryMetrics.hamming_distance(
    irs_word, InterleavedCodeword.raw(f7, [[1, 3]], 2))
rescue error
  bad_metric_shape = true
coding_check("metrics.rejects_shape_mismatch", bad_metric_shape)

bad_metric_representation = false
begin
  CodingTheoryMetrics.hamming_distance(irs_word, rs_word)
rescue error
  bad_metric_representation = true
coding_check("metrics.rejects_representation_mismatch",
             bad_metric_representation)

bad_component = false
begin
  CodingTheoryMetrics.component_hamming_distance(irs_word, equal_copy, 2)
rescue error
  bad_component = true
coding_check("metrics.rejects_lane_out_of_range", bad_component)

# --- Numerical bounds and explicit alignment thresholds -----------------

coding_check("johnson.capacity",
             close_float?(JohnsonBound.capacity_radius(~0.75), ~0.5))
coding_check("johnson.mds_rate",
             close_float?(JohnsonBound.mds_asymptotic_radius(~0.25), ~0.5))
coding_check("johnson.endpoints",
             close_float?(JohnsonBound.capacity_radius(0), ~0.0) &&
             close_float?(JohnsonBound.capacity_radius(1), ~1.0))
tiny_johnson = JohnsonBound.capacity_radius(~1.0e-20)
coding_check("johnson.tiny_distance_is_stable",
             tiny_johnson > ~0.0 &&
             (tiny_johnson / ~5.0e-21 - ~1.0).abs < ~1.0e-12)
coding_check("johnson.q_ary",
             close_float?(JohnsonBound.q_ary_radius(2, ~0.5), ~0.5))
coding_check("johnson.finite_list",
             close_float?(JohnsonBound.finite_list_radius(2, 2, 1), ~0.5))
coding_check("johnson.q_ary_exact_boundary",
             close_float?(
               JohnsonBound.q_ary_radius(29, Rational.new(28, 29)),
               Rational.new(28, 29).to_f))
coding_check("johnson.finite_list_exact_boundary",
             close_float?(
               JohnsonBound.finite_list_radius(
                 7, 13, Rational.new(13, 14)),
               Rational.new(6, 7).to_f))

bad_johnson_interval = false
begin
  JohnsonBound.capacity_radius(Rational.new(-1, 10))
rescue error
  bad_johnson_interval = true
coding_check("johnson.rejects_outside_unit_interval", bad_johnson_interval)

bad_johnson_nan = false
begin
  JohnsonBound.capacity_radius(Math.log(~-1.0))
rescue error
  bad_johnson_nan = true
coding_check("johnson.rejects_nan", bad_johnson_nan)

bad_johnson_string = false
begin
  JohnsonBound.capacity_radius("not-a-distance")
rescue error
  bad_johnson_string = true
coding_check("johnson.rejects_string_coercion", bad_johnson_string)

huge_johnson_q = 10**10000
huge_johnson_value = JohnsonBound.q_ary_radius(huge_johnson_q, ~0.5)
coding_check("johnson.huge_alphabet_is_stable",
             !huge_johnson_value.nan? && !huge_johnson_value.infinite?)
huge_johnson_list = JohnsonBound.finite_list_radius(
  2, huge_johnson_q, ~0.5)
coding_check("johnson.huge_list_is_stable",
             !huge_johnson_list.nan? && !huge_johnson_list.infinite?)

bad_johnson_alphabet = false
begin
  JohnsonBound.q_ary_radius(1, ~0.5)
rescue error
  bad_johnson_alphabet = true
coding_check("johnson.rejects_small_alphabet", bad_johnson_alphabet)

bad_johnson_list = false
begin
  JohnsonBound.finite_list_radius(2, 1, ~0.5)
rescue error
  bad_johnson_list = true
coding_check("johnson.rejects_small_list", bad_johnson_list)

bad_johnson_radicand = false
begin
  JohnsonBound.q_ary_radius(2, ~0.75)
rescue error
  bad_johnson_radicand = true
coding_check("johnson.rejects_negative_radicand", bad_johnson_radicand)

alignment = AffineLineAlignmentThresholds.new(10, 3, 2)
coding_check("alignment.thresholds",
             alignment.minimum_challenge_count == 3 &&
             alignment.minimum_projection_size == 7 &&
             alignment.minimum_aligned_challenge_count == 5)
coding_check("alignment.challenge_strictness",
             !alignment.challenge_count_met?(2) &&
             alignment.challenge_count_met?(3))
coding_check("alignment.projection_boundary",
             !alignment.projection_size_met?(6) &&
             alignment.projection_size_met?(7) &&
             alignment.projection_size_met?(10) &&
             !alignment.projection_size_met?(11))
coding_check("alignment.conclusion_strictness",
             !alignment.aligned_challenge_count_met?(4) &&
             alignment.aligned_challenge_count_met?(5))
coding_check("alignment.cardinality_contract",
             alignment.premise_cardinalities_met?(3, [7, 8, 10]) &&
             !alignment.premise_cardinalities_met?(3, [7, 6, 10]) &&
             !alignment.premise_cardinalities_met?(2, [7, 7]))

bad_alignment_budget = false
begin
  AffineLineAlignmentThresholds.new(10, 11, 2)
rescue error
  bad_alignment_budget = true
coding_check("alignment.rejects_excess_error_budget", bad_alignment_budget)

bad_alignment_count = false
begin
  alignment.challenge_count_met?(-1)
rescue error
  bad_alignment_count = true
coding_check("alignment.rejects_negative_count", bad_alignment_count)

bad_alignment_sizes = false
begin
  alignment.premise_cardinalities_met?(2, nil)
rescue error
  bad_alignment_sizes = true
coding_check("alignment.validates_sizes_when_count_fails", bad_alignment_sizes)

# --- Versioned canonical plain-data interchange -------------------------

field_record = CodingTheoryInterchange.field_to_record(f4)
field_round_trip = CodingTheoryInterchange.field_from_record(field_record)
coding_check("interchange.header",
             field_record["format"] == "tungsten-coding-theory" &&
             field_record["schema_version"] == 1 &&
             field_record["kind"] == "finite-field")
coding_check("interchange.field_round_trip", field_round_trip == f4)
coding_check("interchange.field_canonical_modulus",
             same_plain_data?(field_record["modulus"], [1, 1, 1]))
coding_check("interchange.element_power_basis",
             same_plain_data?(
               CodingTheoryInterchange.element_to_coefficients(f4, 2), [0, 0]) &&
             same_plain_data?(
               CodingTheoryInterchange.element_to_coefficients_raw(f4, 2),
               [0, 1]) &&
             CodingTheoryInterchange.element_from_coefficients(
               f4, [0, 1]) == 2)

domain_record = CodingTheoryInterchange.domain_to_record(ordered_domain)
domain_round_trip = CodingTheoryInterchange.domain_from_record(domain_record)
coding_check("interchange.domain_round_trip",
             domain_round_trip.field == f4 &&
             same_elements?(f4, domain_round_trip.points, [2, 0, 3, 1]))
coding_check("interchange.domain_record_stable",
             same_plain_data?(
               CodingTheoryInterchange.domain_to_record(domain_round_trip),
               domain_record))

rs_parameters_record = CodingTheoryInterchange.reed_solomon_parameters_to_record(rs)
rs_parameters_round_trip = CodingTheoryInterchange.reed_solomon_parameters_from_record(
  rs_parameters_record)
coding_check("interchange.rs_parameters",
             rs_parameters_round_trip.length == 4 &&
             rs_parameters_round_trip.degree_bound == 3 &&
             rs_parameters_round_trip.dimension == 3 &&
             rs_parameters_round_trip.encoder_injective?)

rs_message_record = CodingTheoryInterchange.reed_solomon_message_to_record(
  rs, [3, 2, 1])
coding_check("interchange.rs_message",
             same_elements?(f7,
               CodingTheoryInterchange.reed_solomon_message_from_record(
                 rs_message_record), [3, 2, 1]))
rs_message_bundle = (
  CodingTheoryInterchange.reed_solomon_message_bundle_from_record(
    rs_message_record))
coding_check("interchange.rs_message_bundle_retains_code",
             rs_message_bundle["code"].encode_raw(
               rs_message_bundle["message"]) == rs_word)

saturated_message_record = (
  CodingTheoryInterchange.reed_solomon_message_to_record_raw(
    saturated, vanishing_message))
saturated_message_round_trip = (
  CodingTheoryInterchange.reed_solomon_message_from_record(
    saturated_message_record))
coding_check("interchange.rs_saturated_message_uses_degree_bound",
             same_elements?(f7, saturated_message_round_trip,
                            vanishing_message) &&
             same_elements?(f7,
               saturated.encode_raw(saturated_message_round_trip).symbols,
               [0, 0, 0, 0]))

rs_word_record = CodingTheoryInterchange.reed_solomon_codeword_to_record(
  rs, rs_word)
coding_check("interchange.rs_codeword",
             CodingTheoryInterchange.reed_solomon_codeword_from_record(
               rs_word_record) == rs_word)
rs_word_bundle = (
  CodingTheoryInterchange.reed_solomon_codeword_bundle_from_record(
    rs_word_record))
coding_check("interchange.rs_codeword_bundle_retains_code",
             rs_word_bundle["code"].contains?(
               rs_word_bundle["codeword"]) &&
             rs_word_bundle["codeword"] == rs_word)

bad_rs_word_record = false
begin
  CodingTheoryInterchange.reed_solomon_codeword_to_record(rs, rs_nonmember)
rescue error
  bad_rs_word_record = true
coding_check("interchange.rejects_nonmember_writer", bad_rs_word_record)

corrupt_rs_word_record = CodingTheoryInterchange.reed_solomon_codeword_to_record(
  rs, rs_word)
corrupt_rs_word_record["symbols"][3] = [[5]]
bad_rs_word_loader = false
begin
  CodingTheoryInterchange.reed_solomon_codeword_from_record(
    corrupt_rs_word_record)
rescue error
  bad_rs_word_loader = true
coding_check("interchange.rejects_nonmember_loader", bad_rs_word_loader)

irs_parameters_record = CodingTheoryInterchange.interleaved_parameters_to_record(irs)
irs_parameters_round_trip = CodingTheoryInterchange.interleaved_parameters_from_record(
  irs_parameters_record)
coding_check("interchange.irs_floor_metadata",
             irs_parameters_round_trip.dimension_budget == 5 &&
             irs_parameters_round_trip.lane_degree_bound == 2 &&
             irs_parameters_round_trip.dimension == 4 &&
             irs_parameters_round_trip.floor_remainder == 1)

saturated_irs_record = (
  CodingTheoryInterchange.interleaved_parameters_to_record(saturated_irs))
saturated_irs_round_trip = (
  CodingTheoryInterchange.interleaved_parameters_from_record(
    saturated_irs_record))
coding_check("interchange.irs_saturation_metadata",
             saturated_irs_round_trip.dimension == 6 &&
             saturated_irs_round_trip.saturation_loss == 8 &&
             saturated_irs_round_trip.unrepresented_budget == 8 &&
             !saturated_irs_round_trip.encoder_injective?)

irs_message_record = CodingTheoryInterchange.interleaved_message_to_record(
  irs, [[1, 2], [3, 4]])
coding_check("interchange.irs_message",
             same_rows?(f7,
               CodingTheoryInterchange.interleaved_message_from_record(
                 irs_message_record), [[1, 2], [3, 4]]))
irs_message_bundle = (
  CodingTheoryInterchange.interleaved_message_bundle_from_record(
    irs_message_record))
coding_check("interchange.irs_message_bundle_retains_code",
             irs_message_bundle["code"].encode_columns_raw(
               irs_message_bundle["message"]) == irs_word)

f4_irs_message_record = (
  CodingTheoryInterchange.interleaved_message_to_record(
    f4_irs, f4_irs_external_columns))
coding_check("interchange.irs_extension_external_and_raw",
             same_plain_data?(
               f4_irs_message_record,
               CodingTheoryInterchange.interleaved_message_to_record_raw(
                 f4_irs, f4_irs_raw_columns)))

irs_word_record = CodingTheoryInterchange.interleaved_codeword_to_record(
  irs, irs_word)
coding_check("interchange.irs_codeword",
             CodingTheoryInterchange.interleaved_codeword_from_record(
               irs_word_record) == irs_word)
irs_word_bundle = (
  CodingTheoryInterchange.interleaved_codeword_bundle_from_record(
    irs_word_record))
coding_check("interchange.irs_codeword_bundle_retains_code",
             irs_word_bundle["code"].contains?(
               irs_word_bundle["codeword"]) &&
             irs_word_bundle["codeword"] == irs_word)

# Hand-authored schema-v1 records pin canonical field-element coordinates,
# domain/message ordering, floor metadata, and honest provenance independently
# from the writer implementation.
fixture_metadata = CodingTheoryCanonicalV1Fixture.metadata
coding_check("interchange.fixture_metadata_honest",
             fixture_metadata["producer"] == "tungsten-self-hosted" &&
             fixture_metadata["external_fixture_status"] == "planned" &&
             fixture_metadata["compatibility_claim"] == "none")
coding_check("interchange.fixture_f4_field",
             same_plain_data?(
               CodingTheoryInterchange.field_to_record(f4),
               CodingTheoryCanonicalV1Fixture.f4_field))
f8 = FiniteField.new(2, [1, 1, 0, 1])
coding_check("interchange.fixture_asymmetric_f8_modulus",
             same_plain_data?(
               CodingTheoryInterchange.field_to_record(f8),
               CodingTheoryCanonicalV1Fixture.f8_field) &&
             CodingTheoryInterchange.field_from_record(
               CodingTheoryCanonicalV1Fixture.f8_field).modulus.to_s ==
               "\[1, 1, 0, 1\]")
coding_check("interchange.fixture_f4_domain",
             same_plain_data?(
               CodingTheoryInterchange.domain_to_record(ordered_domain),
               CodingTheoryCanonicalV1Fixture.f4_domain))
coding_check("interchange.fixture_f4_rs_parameters",
             same_plain_data?(
               CodingTheoryInterchange.reed_solomon_parameters_to_record(
                 ordered_rs),
               CodingTheoryCanonicalV1Fixture.f4_reed_solomon_parameters))
coding_check("interchange.fixture_f4_rs_message",
             same_plain_data?(
               CodingTheoryInterchange.reed_solomon_message_to_record(
                 ordered_rs, [[1, 0], [0, 1]]),
               CodingTheoryCanonicalV1Fixture.f4_reed_solomon_message) &&
             same_plain_data?(
               CodingTheoryInterchange.reed_solomon_message_to_record_raw(
                 ordered_rs, [1, 2]),
               CodingTheoryCanonicalV1Fixture.f4_reed_solomon_message))
coding_check("interchange.fixture_f4_rs_codeword",
             same_plain_data?(
               CodingTheoryInterchange.reed_solomon_codeword_to_record(
                 ordered_rs, ordered_rs.encode_raw([1, 2])),
               CodingTheoryCanonicalV1Fixture.f4_reed_solomon_codeword))
coding_check("interchange.fixture_f7_irs_parameters",
             same_plain_data?(
               CodingTheoryInterchange.interleaved_parameters_to_record(irs),
               CodingTheoryCanonicalV1Fixture.f7_interleaved_parameters))
coding_check("interchange.fixture_f7_irs_message",
             same_plain_data?(
               CodingTheoryInterchange.interleaved_message_to_record(
                 irs, [[1, 2], [3, 4]]),
               CodingTheoryCanonicalV1Fixture.f7_interleaved_message))
coding_check("interchange.fixture_f7_irs_codeword",
             same_plain_data?(
               CodingTheoryInterchange.interleaved_codeword_to_record(
                 irs, irs_word),
               CodingTheoryCanonicalV1Fixture.f7_interleaved_codeword))

bad_record_version = CodingTheoryInterchange.domain_to_record(ordered_domain)
bad_record_version["schema_version"] = 2
rejected_record_version = false
begin
  CodingTheoryInterchange.domain_from_record(bad_record_version)
rescue error
  rejected_record_version = true
coding_check("interchange.rejects_unknown_version", rejected_record_version)

bad_record_version_type = CodingTheoryInterchange.domain_to_record(ordered_domain)
bad_record_version_type["schema_version"] = ~1.0
rejected_record_version_type = false
begin
  CodingTheoryInterchange.domain_from_record(bad_record_version_type)
rescue error
  rejected_record_version_type = true
coding_check("interchange.rejects_noninteger_version",
             rejected_record_version_type)

bad_record_kind = CodingTheoryInterchange.domain_to_record(ordered_domain)
bad_record_kind["kind"] = "finite-field"
rejected_record_kind = false
begin
  CodingTheoryInterchange.domain_from_record(bad_record_kind)
rescue error
  rejected_record_kind = true
coding_check("interchange.rejects_wrong_kind", rejected_record_kind)

bad_modulus_record = CodingTheoryInterchange.field_to_record(f4)
bad_modulus_record["modulus"] = [1, -1, 1]
rejected_modulus = false
begin
  CodingTheoryInterchange.field_from_record(bad_modulus_record)
rescue error
  rejected_modulus = true
coding_check("interchange.rejects_noncanonical_modulus", rejected_modulus)

bad_modulus_layout = CodingTheoryInterchange.field_to_record(f8)
bad_modulus_layout["modulus_layout"] = "high-degree-first"
rejected_modulus_layout = false
begin
  CodingTheoryInterchange.field_from_record(bad_modulus_layout)
rescue error
  rejected_modulus_layout = true
coding_check("interchange.rejects_modulus_layout", rejected_modulus_layout)

bad_element_width = false
begin
  CodingTheoryInterchange.element_from_coefficients(f4, [0])
rescue error
  bad_element_width = true
coding_check("interchange.rejects_element_width", bad_element_width)

bad_domain_layout = CodingTheoryInterchange.domain_to_record(ordered_domain)
bad_domain_layout["layout"] = "unordered-points"
rejected_domain_layout = false
begin
  CodingTheoryInterchange.domain_from_record(bad_domain_layout)
rescue error
  rejected_domain_layout = true
coding_check("interchange.rejects_domain_layout", rejected_domain_layout)

bad_rs_metadata = CodingTheoryInterchange.reed_solomon_parameters_to_record(rs)
bad_rs_metadata["dimension"] = 2
rejected_rs_metadata = false
begin
  CodingTheoryInterchange.reed_solomon_parameters_from_record(bad_rs_metadata)
rescue error
  rejected_rs_metadata = true
coding_check("interchange.rejects_inconsistent_rs_metadata",
             rejected_rs_metadata)

bad_irs_metadata = CodingTheoryInterchange.interleaved_parameters_to_record(irs)
bad_irs_metadata["floor_remainder"] = 0
rejected_irs_metadata = false
begin
  CodingTheoryInterchange.interleaved_parameters_from_record(bad_irs_metadata)
rescue error
  rejected_irs_metadata = true
coding_check("interchange.rejects_inconsistent_floor_metadata",
             rejected_irs_metadata)

bad_message_layout = CodingTheoryInterchange.reed_solomon_message_to_record(
  rs, [3, 2, 1])
bad_message_layout["layout"] = "high-degree-first"
rejected_message_layout = false
begin
  CodingTheoryInterchange.reed_solomon_message_from_record(bad_message_layout)
rescue error
  rejected_message_layout = true
coding_check("interchange.rejects_message_layout", rejected_message_layout)

bad_message_helper = false
begin
  CodingTheoryInterchange.reed_solomon_message_to_record_raw(rs, [1])
rescue error
  bad_message_helper = true
coding_check("interchange.raw_message_writer_validates_shape",
             bad_message_helper)

bad_rows_record = CodingTheoryInterchange.interleaved_codeword_to_record(
  irs, irs_word)
bad_rows_record["rows"][0] = [[1]]
rejected_rows = false
begin
  CodingTheoryInterchange.interleaved_codeword_from_record(bad_rows_record)
rescue error
  rejected_rows = true
coding_check("interchange.rejects_ragged_codeword", rejected_rows)

<< "coding_theory_spec: all checks passed"
