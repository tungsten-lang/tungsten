# Focused checks for deterministic Allen interval verification. Run in both
# engines:
#   bin/tungsten run spec/core/animation_verification_spec.w
#   bin/tungsten compile spec/core/animation_verification_spec.w \
#     --out /tmp/animation-verification-spec
#   /tmp/animation-verification-spec

use core/animation

-> verification_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> verification_track(timeline, target, property, start_time, end_time,
                      from = ~0.0, to = ~1.0)
  track = Animation.track(target, property, [
    Animation.keyframe(start_time, from),
    Animation.keyframe(end_time, to)
  ])
  timeline.add(track)
  track

-> verification_assertion(id, left_property, relation, right_property)
  Animation.assert_track_relation(
    id, "subject", left_property, relation, "subject", right_property)


scene = Plot.scene()
scene.add(Plot.polyline(
  [[~0.0, ~0.0], [~1.0, ~1.0]], false, "subject"))
timeline = Animation.timeline(scene, ~4.0, 4)

# Six support intervals suffice as canonical witnesses for all thirteen Allen
# relations. Property values are incidental: verification uses the declared
# first/last keyframe times, not whether a value actually changes.
verification_track(timeline, "subject", :i01, ~0.0, ~1.0)
verification_track(timeline, "subject", :i23, ~2.0, ~3.0)
verification_track(timeline, "subject", :i13, ~1.0, ~3.0)
verification_track(timeline, "subject", :i02, ~0.0, ~2.0)
verification_track(timeline, "subject", :i03, ~0.0, ~3.0)
verification_track(timeline, "subject", :i12, ~1.0, ~2.0)

canonical_assertions = [
  verification_assertion("before", :i01, :before, :i23),
  verification_assertion("meets", :i01, :meets, :i13),
  verification_assertion("overlaps", :i02, :overlaps, :i13),
  verification_assertion("starts", :i02, :starts, :i03),
  verification_assertion("during", :i12, :during, :i03),
  verification_assertion("finishes", :i13, :finishes, :i03),
  verification_assertion("equals", :i03, :equals, :i03),
  verification_assertion("after", :i23, :after, :i01),
  verification_assertion("met-by", :i13, :met_by, :i01),
  verification_assertion("overlapped-by", :i13, :overlapped_by, :i02),
  verification_assertion("started-by", :i03, :started_by, :i02),
  verification_assertion("contains", :i03, :contains, :i12),
  verification_assertion("finished-by", :i03, :finished_by, :i13)
]
canonical_report = Animation.verify(timeline, canonical_assertions)
canonical_results = canonical_report.results
canonical_relations = AnimationVerifier.relations

verification_check("relations.count", canonical_relations.size == 13)
verification_check("canonical.result_count", canonical_results.size == 13)
all_canonical_pass = true
canonical_order = true
index = 0
while index < canonical_results.size
  result = canonical_results[index]
  all_canonical_pass = false if result.status != :pass
  all_canonical_pass = false if result.observed_relation != canonical_relations[index]
  canonical_order = false if result.assertion.id != canonical_assertions[index].id
  index += 1
verification_check("canonical.all_relations", all_canonical_pass)
verification_check("canonical.input_order", canonical_order)
verification_check("canonical.report_status", canonical_report.status == :pass)
verification_check("canonical.report_passed", canonical_report.passed?)
verification_check("canonical.default_exact", canonical_report.epsilon == ~0.0)

# Every non-self relation is paired with its inverse by reversing the two
# interval references in the canonical table above.
inverse_pairs = (
  canonical_results[0].observed_relation == :before &&
  canonical_results[7].observed_relation == :after &&
  canonical_results[1].observed_relation == :meets &&
  canonical_results[8].observed_relation == :met_by &&
  canonical_results[2].observed_relation == :overlaps &&
  canonical_results[9].observed_relation == :overlapped_by &&
  canonical_results[3].observed_relation == :starts &&
  canonical_results[10].observed_relation == :started_by &&
  canonical_results[4].observed_relation == :during &&
  canonical_results[11].observed_relation == :contains &&
  canonical_results[5].observed_relation == :finishes &&
  canonical_results[12].observed_relation == :finished_by &&
  canonical_results[6].observed_relation == :equals)
verification_check("canonical.inverse_pairs", inverse_pairs)

# Tolerance is explicit. At epsilon zero these proper overlapping intervals
# have exactly one relation. A deliberately large epsilon makes both `meets`
# and `equals` candidates; the verifier must report unknown, not pick first.
verification_track(timeline, "subject", :ambiguous_left, ~1.0, ~2.5)
verification_track(timeline, "subject", :ambiguous_right, ~1.5, ~3.0)
exact_overlap = verification_assertion(
  "exact-overlap", :ambiguous_left, :overlaps, :ambiguous_right)
exact_overlap_report = Animation.verify(timeline, [exact_overlap])
verification_check("epsilon.exact_observed",
                   exact_overlap_report.results[0].observed_relation == :overlaps)
verification_check("epsilon.exact_pass", exact_overlap_report.passed?)

ambiguous_meets = verification_assertion(
  "ambiguous-meets", :ambiguous_left, :meets, :ambiguous_right)
ambiguous_report = Animation.verify(timeline, [ambiguous_meets], ~1.0)
ambiguous_result = ambiguous_report.results[0]
verification_check("epsilon.ambiguous_status",
                   ambiguous_result.status == :unknown)
verification_check("epsilon.ambiguous_candidates",
                   ambiguous_result.candidate_relations.size == 2 &&
                   ambiguous_result.candidate_relations[0] == :meets &&
                   ambiguous_result.candidate_relations[1] == :equals)
verification_check("epsilon.ambiguous_diagnostic",
                   ambiguous_result.diagnostics.size == 1 &&
                   ambiguous_result.diagnostics[0][:side] == :relation &&
                   ambiguous_result.diagnostics[0][:code] == :epsilon_ambiguous &&
                   ambiguous_result.diagnostics[0][:matches] == 2)
verification_check("epsilon.ambiguous_aggregate",
                   ambiguous_report.status == :unknown &&
                   !ambiguous_report.passed?)

stale_epsilon_report_rejected = false
begin
  AnimationVerificationReport.new(ambiguous_report.results, ~0.0)
rescue error
  stale_epsilon_report_rejected = error.to_s.include?(
    "unknown report contradicts its interval evidence")
verification_check("epsilon.report_consistency",
                   stale_epsilon_report_rejected)

# Ordinary floating-point endpoint noise can be accepted by an explicit small
# epsilon while the default continues to report the exact retained ordering.
rounded_end = ~0.1 + ~0.2
verification_track(timeline, "subject", :rounded_left, ~0.0, rounded_end)
verification_track(timeline, "subject", :rounded_right, ~0.3, ~1.0)
rounded_meets = verification_assertion(
  "rounded-meets", :rounded_left, :meets, :rounded_right)
rounded_exact = Animation.verify(timeline, [rounded_meets])
rounded_tolerant = Animation.verify(timeline, [rounded_meets], ~1.0e-12)
verification_check("epsilon.rounded_exact_fail",
                   rounded_exact.results[0].status == :fail &&
                   rounded_exact.results[0].observed_relation == :overlaps)
verification_check("epsilon.rounded_tolerant_pass", rounded_tolerant.passed?)

# A two-keyframe track has declared support even when its values are equal.
verification_track(
  timeline, "subject", :constant01, ~0.0, ~1.0, ~7.0, ~7.0)
constant_assertion = verification_assertion(
  "constant-meets", :constant01, :meets, :i13)
verification_check("support.equal_values",
                   Animation.verify(timeline, [constant_assertion]).passed?)

# A one-keyframe track is a point interval, so exact Allen classification is
# intentionally unknown rather than allowing several relations to overlap.
point_track = Animation.track("subject", :point1, [
  Animation.keyframe(~1.0, ~0.0)
])
timeline.add(point_track)
degenerate_assertion = verification_assertion(
  "point-before", :point1, :before, :i23)
degenerate_report = Animation.verify(timeline, [degenerate_assertion])
degenerate_result = degenerate_report.results[0]
verification_check("degenerate.status", degenerate_result.status == :unknown)
verification_check("degenerate.interval",
                   degenerate_result.left_interval[:start] == ~1.0 &&
                   degenerate_result.left_interval[:end] == ~1.0)
verification_check("degenerate.diagnostic",
                   degenerate_result.diagnostics.size == 1 &&
                   degenerate_result.diagnostics[0][:side] == :left &&
                   degenerate_result.diagnostics[0][:code] == :degenerate_interval)

# Missing evidence is unknown. Diagnostics retain left/right ordering when
# both references are absent.
missing_left = Animation.assert_track_relation(
  "missing-left", "absent", :opacity, :before, "subject", :i23)
missing_right = Animation.assert_track_relation(
  "missing-right", "subject", :i01, :before, "absent", :opacity)
missing_both = Animation.assert_track_relation(
  "missing-both", "absent-a", :opacity, :before, "absent-b", :translate)
missing_report = Animation.verify(
  timeline, [missing_left, missing_right, missing_both])
missing_results = missing_report.results
verification_check("missing.all_unknown",
                   missing_results[0].status == :unknown &&
                   missing_results[1].status == :unknown &&
                   missing_results[2].status == :unknown)
verification_check("missing.left_diagnostic",
                   missing_results[0].diagnostics[0][:side] == :left &&
                   missing_results[0].diagnostics[0][:code] == :track_missing &&
                   missing_results[0].diagnostics[0][:matches] == 0)
verification_check("missing.right_diagnostic",
                   missing_results[1].diagnostics[0][:side] == :right &&
                   missing_results[1].diagnostics[0][:code] == :track_missing)
verification_check("missing.both_order",
                   missing_results[2].diagnostics.size == 2 &&
                   missing_results[2].diagnostics[0][:side] == :left &&
                   missing_results[2].diagnostics[1][:side] == :right)
verification_check("missing.aggregate", missing_report.status == :unknown)

# A mixed report proves stable input order, distinct result states, aggregate
# fail precedence, summary counts, and portable schemas.
pass_assertion = verification_assertion("mixed-pass", :i01, :meets, :i13)
fail_assertion = verification_assertion("mixed-fail", :i01, :before, :i13)
unknown_assertion = Animation.assert_track_relation(
  "mixed-unknown", "absent", :opacity, :before, "subject", :i23)
mixed_report = Animation.verify(
  timeline, [pass_assertion, fail_assertion, unknown_assertion])
mixed_results = mixed_report.results
mixed_data = mixed_report.to_data
mixed_summary = mixed_report.summary
verification_check("mixed.statuses",
                   mixed_results[0].status == :pass &&
                   mixed_results[1].status == :fail &&
                   mixed_results[2].status == :unknown)
verification_check("mixed.result_order",
                   mixed_results[0].assertion.id == "mixed-pass" &&
                   mixed_results[1].assertion.id == "mixed-fail" &&
                   mixed_results[2].assertion.id == "mixed-unknown")
verification_check("mixed.aggregate_fail",
                   mixed_report.status == :fail && !mixed_report.passed?)
verification_check("mixed.summary",
                   mixed_summary[:pass] == 1 &&
                   mixed_summary[:fail] == 1 &&
                   mixed_summary[:unknown] == 1)
verification_check("schema.report",
                   mixed_data[:schema] == "tungsten.animation.verification/v1" &&
                   mixed_data[:scope] == :declared_track_support &&
                   mixed_data[:interval_model] == :proper_closed)
verification_check("schema.assertion",
                   mixed_data[:results][0][:assertion][:schema] ==
                   "tungsten.animation.interval-assertion/v1" &&
                   mixed_data[:results][0][:assertion][:kind] ==
                   :track_interval_relation)
verification_check("schema.spatial_scope",
                   mixed_data[:spatial_verification] == :not_supported)
verification_check("json.deterministic", mixed_report.to_json == mixed_report.to_json)

# Public result/report values preserve their evidence and reject contradictory
# pass states rather than allowing callers to manufacture a green report.
manual_left = {:start => ~0.0, :end => ~1.0}
manual_right = {:start => ~1.0, :end => ~3.0}
manual_candidates = [:meets]
manual_diagnostics = []
manual_result = AnimationVerificationResult.new(
  pass_assertion, :pass, :meets, manual_left, manual_right,
  manual_candidates, manual_diagnostics)
manual_results = [manual_result]
manual_report = AnimationVerificationReport.new(manual_results, ~0.0)
manual_left[:start] = ~99.0
manual_right[:end] = ~99.0
manual_candidates.push(:equals)
manual_diagnostics.push({:side => :relation, :code => :changed})
manual_results.push(manual_result)
verification_check("values.result_copies",
                   manual_result.left_interval[:start] == ~0.0 &&
                   manual_result.right_interval[:end] == ~3.0 &&
                   manual_result.candidate_relations.size == 1 &&
                   manual_result.diagnostics.size == 0)
verification_check("values.report_copy", manual_report.results.size == 1)

contradictory_pass_rejected = false
begin
  AnimationVerificationResult.new(
    pass_assertion, :pass, :before,
    {:start => ~0.0, :end => ~1.0},
    {:start => ~2.0, :end => ~3.0}, [:before], [])
rescue error
  contradictory_pass_rejected = error.to_s.include?("pass result contradicts")
verification_check("validation.contradictory_pass",
                   contradictory_pass_rejected)

unsupported_unknown_rejected = false
begin
  AnimationVerificationResult.new(
    pass_assertion, :unknown, nil,
    {:start => ~0.0, :end => ~1.0}, nil, [], [])
rescue error
  unsupported_unknown_rejected = error.to_s.include?(
    "unknown result needs diagnostics")
verification_check("validation.unknown_diagnostics",
                   unsupported_unknown_rejected)

epsilon_report_rejected = false
begin
  AnimationVerificationReport.new([manual_result], ~1.0)
rescue error
  epsilon_report_rejected = error.to_s.include?(
    "report contradicts its interval evidence")
verification_check("validation.report_epsilon_evidence",
                   epsilon_report_rejected)

# Invalid API shapes are programming errors, unlike unsupported evidence.
duplicate_ids_rejected = false
begin
  Animation.verify(timeline, [
    verification_assertion("duplicate", :i01, :before, :i23),
    verification_assertion("duplicate", :i01, :meets, :i13)
  ])
rescue error
  duplicate_ids_rejected = error.to_s.include?("ids must be unique")
verification_check("validation.duplicate_ids", duplicate_ids_rejected)

bad_relation_rejected = false
begin
  verification_assertion("bad-relation", :i01, :touches, :i23)
rescue error
  bad_relation_rejected = error.to_s.include?("unsupported animation interval relation")
verification_check("validation.relation", bad_relation_rejected)

empty_identifier_rejected = false
begin
  verification_assertion("", :i01, :before, :i23)
rescue error
  empty_identifier_rejected = error.to_s.include?("identifiers must be nonempty")
verification_check("validation.identifier", empty_identifier_rejected)

negative_epsilon_rejected = false
begin
  Animation.verify(timeline, [canonical_assertions[0]], ~-1.0e-12)
rescue error
  negative_epsilon_rejected = error.to_s.include?("epsilon must be nonnegative")
verification_check("validation.epsilon", negative_epsilon_rejected)

empty_assertions_rejected = false
begin
  Animation.verify(timeline, [])
rescue error
  empty_assertions_rejected = error.to_s.include?("nonempty Array")
verification_check("validation.empty_assertions", empty_assertions_rejected)

nonarray_assertions_rejected = false
begin
  Animation.verify(timeline, nil)
rescue error
  nonarray_assertions_rejected = error.to_s.include?("nonempty Array")
verification_check("validation.nonarray_assertions", nonarray_assertions_rejected)

wrong_assertion_type_rejected = false
begin
  Animation.verify(timeline, ["not-an-assertion"])
rescue error
  wrong_assertion_type_rejected = error.to_s.include?(
    "must be AnimationTrackIntervalAssertion")
verification_check("validation.assertion_type", wrong_assertion_type_rejected)

<< "animation_verification_spec: all checks passed"
