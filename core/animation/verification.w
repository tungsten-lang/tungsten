# Deterministic verification of Allen interval relations between declared
# node-property track supports. This layer verifies timeline data, not rendered
# motion, object bounds, or author intent.

+ AnimationTrackIntervalAssertion
  -> new(id, left_target, left_property, relation,
         right_target, right_property)
    @id = id.to_s()
    @left_target = left_target.to_s()
    @left_property = left_property.to_s()
    @relation = relation
    @right_target = right_target.to_s()
    @right_property = right_property.to_s()
    invalid_left = @id.size == 0 || @left_target.size == 0 || @left_property.size == 0
    invalid_right = @right_target.size == 0 || @right_property.size == 0
    if invalid_left || invalid_right
      raise "animation assertion identifiers must be nonempty"
    if !AnimationVerifier.relations.include?(@relation)
      raise "unsupported animation interval relation: " + @relation.to_s()

  -> id
    @id

  -> left_target
    @left_target

  -> left_property
    @left_property

  -> relation
    @relation

  -> right_target
    @right_target

  -> right_property
    @right_property

  -> to_data
    {
      :schema => "tungsten.animation.interval-assertion/v1",
      :id => @id,
      :kind => :track_interval_relation,
      :left => {:target => @left_target, :property => @left_property},
      :relation => @relation,
      :right => {:target => @right_target, :property => @right_property}
    }


+ AnimationVerificationResult
  -> new(@assertion, @status, @observed_relation,
         @left_interval, @right_interval, @candidate_relations, @diagnostics)
    if @assertion.class_name != "AnimationTrackIntervalAssertion"
      raise "animation verification result needs an interval assertion"
    if ![:pass, :fail, :unknown].include?(@status)
      raise "animation verification result status must be pass, fail, or unknown"
    if @candidate_relations.class_name != "Array" || @diagnostics.class_name != "Array"
      raise "animation verification result candidates and diagnostics must be Arrays"
    if @left_interval != nil && @left_interval.class_name != "Hash"
      raise "animation verification result left interval must be a Hash or nil"
    if @right_interval != nil && @right_interval.class_name != "Hash"
      raise "animation verification result right interval must be a Hash or nil"
    if @observed_relation != nil && !AnimationVerifier.relations.include?(@observed_relation)
      raise "animation verification result has an unsupported observed relation"
    @left_interval = PlotData.portable(
      @left_interval, "animation verification left interval")
    @right_interval = PlotData.portable(
      @right_interval, "animation verification right interval")
    @candidate_relations = PlotData.portable(
      @candidate_relations, "animation verification candidates")
    @diagnostics = PlotData.portable(
      @diagnostics, "animation verification diagnostics")
    intervals = [@left_interval, @right_interval]
    interval_index = 0
    while interval_index < intervals.size
      interval = intervals[interval_index]
      if interval != nil
        if !interval.has_key?(:start) || !interval.has_key?(:end)
          raise "animation verification intervals need start and end"
        PlotData.number(interval[:start], "animation verification interval start")
        PlotData.number(interval[:end], "animation verification interval end")
      interval_index += 1
    relation_index = 0
    while relation_index < @candidate_relations.size
      if !AnimationVerifier.relations.include?(@candidate_relations[relation_index])
        raise "animation verification result has an unsupported candidate relation"
      relation_index += 1
    allowed_diagnostics = [
      :track_missing, :track_ambiguous,
      :degenerate_interval, :epsilon_ambiguous
    ]
    diagnostic_index = 0
    while diagnostic_index < @diagnostics.size
      diagnostic = @diagnostics[diagnostic_index]
      invalid_diagnostic = diagnostic.class_name != "Hash"
      invalid_diagnostic = invalid_diagnostic || !allowed_diagnostics.include?(
        diagnostic[:code])
      if invalid_diagnostic
        raise "animation verification result has an unsupported diagnostic"
      side = diagnostic[:side]
      if ![:left, :right, :relation].include?(side)
        raise "animation verification diagnostic has an unsupported side"
      if diagnostic[:code] == :epsilon_ambiguous && side != :relation
        raise "animation epsilon ambiguity diagnostic must use relation side"
      if diagnostic[:code] != :epsilon_ambiguous && side == :relation
        raise "animation track diagnostic must use left or right side"
      diagnostic_index += 1
    unique_observed = @candidate_relations.size == 1
    unique_observed = unique_observed && @candidate_relations[0] == @observed_relation
    if @status == :pass
      invalid_pass = !unique_observed || @observed_relation != @assertion.relation
      invalid_pass = invalid_pass || @left_interval == nil || @right_interval == nil
      invalid_pass = invalid_pass || @diagnostics.size != 0
      if invalid_pass
        raise "animation pass result contradicts its observed relation"
    if @status == :fail
      invalid_fail = !unique_observed || @observed_relation == @assertion.relation
      invalid_fail = invalid_fail || @left_interval == nil || @right_interval == nil
      invalid_fail = invalid_fail || @diagnostics.size != 0
      if invalid_fail
        raise "animation fail result contradicts its observed relation"
    if @status == :unknown
      invalid_unknown = @observed_relation != nil || @diagnostics.size == 0
      invalid_unknown = invalid_unknown || @candidate_relations.size == 1
      if invalid_unknown
        raise "animation unknown result needs diagnostics and no observed relation"

  -> assertion
    @assertion

  -> status
    @status

  -> observed_relation
    @observed_relation

  -> left_interval
    PlotData.copy(@left_interval)

  -> right_interval
    PlotData.copy(@right_interval)

  -> candidate_relations
    PlotData.copy(@candidate_relations)

  -> diagnostics
    PlotData.copy(@diagnostics)

  -> passed?
    @status == :pass

  -> to_data
    {
      :assertion => @assertion.to_data,
      :status => @status,
      :observed_relation => @observed_relation,
      :left_interval => PlotData.copy(@left_interval),
      :right_interval => PlotData.copy(@right_interval),
      :candidate_relations => PlotData.copy(@candidate_relations),
      :diagnostics => PlotData.copy(@diagnostics)
    }


+ AnimationVerificationReport
  -> new(@results, @epsilon)
    if @results.class_name != "Array" || @results.size == 0
      raise "animation verification report needs nonempty results"
    @epsilon = PlotData.number(@epsilon, "animation verifier epsilon")
    raise "animation verifier epsilon must be nonnegative" if @epsilon < ~0.0
    index = 0
    while index < @results.size
      if @results[index].class_name != "AnimationVerificationResult"
        raise "animation verification report results must be verification results"
      result = @results[index]
      if result.status != :unknown
        left = result.left_interval
        right = result.right_interval
        if left == nil || right == nil
          raise "animation pass/fail reports need both witness intervals"
        left_proper = AnimationVerifier.strictly_less?(
          left[:start], left[:end], @epsilon)
        right_proper = AnimationVerifier.strictly_less?(
          right[:start], right[:end], @epsilon)
        candidates = AnimationVerifier.candidate_relations(left, right, @epsilon)
        consistent = left_proper && right_proper && candidates.size == 1
        consistent = consistent && candidates[0] == result.observed_relation
        if !consistent
          raise "animation pass/fail report contradicts its interval evidence"
      else
        left = result.left_interval
        right = result.right_interval
        diagnostics = result.diagnostics
        has_lookup = false
        has_epsilon = false
        left_degenerate = false
        right_degenerate = false
        consistent = true
        diagnostic_index = 0
        while diagnostic_index < diagnostics.size
          diagnostic = diagnostics[diagnostic_index]
          code = diagnostic[:code]
          side = diagnostic[:side]
          if code == :track_missing || code == :track_ambiguous
            has_lookup = true
            if side == :left
              consistent = false if left != nil
            else
              consistent = false if right != nil
          if code == :epsilon_ambiguous
            has_epsilon = true
          if code == :degenerate_interval
            left_degenerate = true if side == :left
            right_degenerate = true if side == :right
          diagnostic_index += 1

        if has_lookup
          consistent = false if result.candidate_relations.size != 0
          consistent = false if has_epsilon
          if left == nil
            consistent = false if left_degenerate
          else
            left_proper = AnimationVerifier.strictly_less?(
              left[:start], left[:end], @epsilon)
            consistent = false if left_degenerate == left_proper
          if right == nil
            consistent = false if right_degenerate
          else
            right_proper = AnimationVerifier.strictly_less?(
              right[:start], right[:end], @epsilon)
            consistent = false if right_degenerate == right_proper
        else
          if left == nil || right == nil
            consistent = false
          else
            left_proper = AnimationVerifier.strictly_less?(
              left[:start], left[:end], @epsilon)
            right_proper = AnimationVerifier.strictly_less?(
              right[:start], right[:end], @epsilon)
            if !left_proper || !right_proper
              consistent = false if result.candidate_relations.size != 0
              consistent = false if has_epsilon
              consistent = false if left_degenerate == left_proper
              consistent = false if right_degenerate == right_proper
            else
              recomputed = AnimationVerifier.candidate_relations(
                left, right, @epsilon)
              consistent = false if recomputed.size == 1
              consistent = false if !AnimationVerifier.same_relations?(
                recomputed, result.candidate_relations)
              consistent = false if !has_epsilon
              consistent = false if left_degenerate || right_degenerate
        if !consistent
          raise "animation unknown report contradicts its interval evidence"
      index += 1
    @results = PlotData.copy(@results)

  -> results
    PlotData.copy(@results)

  -> epsilon
    @epsilon

  -> status
    has_unknown = false
    index = 0
    while index < @results.size
      return :fail if @results[index].status == :fail
      has_unknown = true if @results[index].status == :unknown
      index += 1
    has_unknown ? :unknown : :pass

  -> passed?
    status == :pass

  -> summary
    counts = {:pass => 0, :fail => 0, :unknown => 0}
    index = 0
    while index < @results.size
      result_status = @results[index].status
      counts[result_status] = counts[result_status] + 1
      index += 1
    counts

  -> to_data
    values = []
    index = 0
    while index < @results.size
      values.push(@results[index].to_data)
      index += 1
    {
      :schema => "tungsten.animation.verification/v1",
      :scope => :declared_track_support,
      :interval_model => :proper_closed,
      :epsilon_seconds => @epsilon,
      :status => status,
      :passed => passed?,
      :summary => summary,
      :results => values,
      :spatial_verification => :not_supported
    }

  -> to_json
    JSON.encode(to_data)


+ AnimationVerifier
  -> .relations
    [
      :before, :meets, :overlaps, :starts, :during, :finishes, :equals,
      :after, :met_by, :overlapped_by, :started_by, :contains, :finished_by
    ]

  -> .same_relations?(left, right)
    return false if left.size != right.size
    index = 0
    while index < left.size
      return false if left[index] != right[index]
      index += 1
    true

  -> .absolute(value)
    value < ~0.0 ? ~0.0 - value : value

  -> .close?(left, right, epsilon)
    absolute(left - right) <= epsilon

  -> .strictly_less?(left, right, epsilon)
    right - left > epsilon

  # Return every relation consistent with the tolerance. A caller may trust a
  # classification only when this contains exactly one relation.
  -> .candidate_relations(left, right, epsilon = ~0.0)
    tolerance = PlotData.number(epsilon, "animation verifier epsilon")
    raise "animation verifier epsilon must be nonnegative" if tolerance < ~0.0
    a = PlotData.number(left[:start], "left interval start")
    b = PlotData.number(left[:end], "left interval end")
    c = PlotData.number(right[:start], "right interval start")
    d = PlotData.number(right[:end], "right interval end")
    candidates = []

    candidates.push(:before) if strictly_less?(b, c, tolerance)
    candidates.push(:meets) if close?(b, c, tolerance)
    overlaps = strictly_less?(a, c, tolerance) && strictly_less?(c, b, tolerance)
    overlaps = overlaps && strictly_less?(b, d, tolerance)
    if overlaps
      candidates.push(:overlaps)
    if close?(a, c, tolerance) && strictly_less?(b, d, tolerance)
      candidates.push(:starts)
    if strictly_less?(c, a, tolerance) && strictly_less?(b, d, tolerance)
      candidates.push(:during)
    if strictly_less?(c, a, tolerance) && close?(b, d, tolerance)
      candidates.push(:finishes)
    if close?(a, c, tolerance) && close?(b, d, tolerance)
      candidates.push(:equals)
    candidates.push(:after) if strictly_less?(d, a, tolerance)
    candidates.push(:met_by) if close?(d, a, tolerance)
    overlapped_by = strictly_less?(c, a, tolerance) && strictly_less?(a, d, tolerance)
    overlapped_by = overlapped_by && strictly_less?(d, b, tolerance)
    if overlapped_by
      candidates.push(:overlapped_by)
    if close?(a, c, tolerance) && strictly_less?(d, b, tolerance)
      candidates.push(:started_by)
    if strictly_less?(a, c, tolerance) && strictly_less?(d, b, tolerance)
      candidates.push(:contains)
    if strictly_less?(a, c, tolerance) && close?(b, d, tolerance)
      candidates.push(:finished_by)
    candidates

  -> .track_matches(timeline, target, property)
    matches = []
    tracks = timeline.tracks
    index = 0
    while index < tracks.size
      track = tracks[index]
      if track.target == target && track.property == property
        matches.push(track)
      index += 1
    matches

  -> .verify(timeline, assertions, epsilon = ~0.0)
    tolerance = PlotData.number(epsilon, "animation verifier epsilon")
    raise "animation verifier epsilon must be nonnegative" if tolerance < ~0.0
    if assertions.class_name != "Array" || assertions.size == 0
      raise "animation verification needs a nonempty Array of assertions"

    seen = {}
    results = []
    assertion_index = 0
    while assertion_index < assertions.size
      assertion = assertions[assertion_index]
      if assertion.class_name != "AnimationTrackIntervalAssertion"
        raise "animation verification assertions must be AnimationTrackIntervalAssertion values"
      if seen[assertion.id] == true
        raise "animation assertion ids must be unique: " + assertion.id
      seen[assertion.id] = true

      left_matches = track_matches(
        timeline, assertion.left_target, assertion.left_property)
      right_matches = track_matches(
        timeline, assertion.right_target, assertion.right_property)
      diagnostics = []
      left_interval = nil
      right_interval = nil

      if left_matches.size == 1
        left_interval = {
          :start => left_matches[0].start_time,
          :end => left_matches[0].end_time
        }
      else
        code = left_matches.size == 0 ? :track_missing : :track_ambiguous
        diagnostics.push({:side => :left, :code => code,
                          :matches => left_matches.size})

      if right_matches.size == 1
        right_interval = {
          :start => right_matches[0].start_time,
          :end => right_matches[0].end_time
        }
      else
        code = right_matches.size == 0 ? :track_missing : :track_ambiguous
        diagnostics.push({:side => :right, :code => code,
                          :matches => right_matches.size})

      left_degenerate = left_interval != nil && !strictly_less?(
        left_interval[:start], left_interval[:end], tolerance)
      if left_degenerate
        diagnostics.push({:side => :left, :code => :degenerate_interval})
      right_degenerate = right_interval != nil && !strictly_less?(
        right_interval[:start], right_interval[:end], tolerance)
      if right_degenerate
        diagnostics.push({:side => :right, :code => :degenerate_interval})

      candidates = []
      observed = nil
      result_status = :unknown
      if diagnostics.size == 0
        candidates = candidate_relations(left_interval, right_interval, tolerance)
        if candidates.size == 1
          observed = candidates[0]
          result_status = observed == assertion.relation ? :pass : :fail
        else
          diagnostics.push({:side => :relation, :code => :epsilon_ambiguous,
                            :matches => candidates.size})

      results.push(AnimationVerificationResult.new(
        assertion, result_status, observed, left_interval, right_interval,
        candidates, diagnostics))
      assertion_index += 1
    AnimationVerificationReport.new(results, tolerance)
