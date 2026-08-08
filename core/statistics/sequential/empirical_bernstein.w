# Closed-form empirical-Bernstein confidence sequences after Chugg and Ramdas
# (2025).  The scalar theorem tracks an average conditional mean for bounded,
# adapted observations; independence and a constant mean are not required.

+ StatisticsConfidenceSequenceResult
  -> new(count, center, lower, upper, raw_half_width, numerical_guard,
         variance_process, predictor, active_from, status, miscoverage,
         kappa, support, clipped, assumptions, warnings)
    @count = count
    @center = center
    @lower = lower
    @upper = upper
    @raw_half_width = raw_half_width
    @numerical_guard = numerical_guard
    @variance_process = variance_process
    @predictor = predictor
    @active_from = active_from
    @status = status
    @miscoverage = miscoverage
    @kappa = kappa
    @support = Statistics.copy_values(support)
    @clipped = clipped
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  -> count
    @count

  -> center
    @center

  -> lower
    @lower

  -> upper
    @upper

  -> interval
    [@lower, @upper]

  -> raw_half_width
    @raw_half_width

  -> numerical_guard
    @numerical_guard

  -> variance_process
    @variance_process

  -> predictor
    @predictor

  -> active_from
    @active_from

  -> active?
    @status == :active

  -> status
    @status

  -> target
    :average_conditional_mean

  -> miscoverage
    @miscoverage

  -> confidence_level
    ~1.0 - @miscoverage

  -> kappa
    @kappa

  -> support
    Statistics.copy_values(@support)

  -> clipped?
    @clipped

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsEmpiricalBernsteinSequence
  -> new(miscoverage, support_lower = ~0.0, support_upper = ~1.0,
         kappa = ~0.25)
    @miscoverage = Statistics.open_probability(
      miscoverage, "empirical Bernstein miscoverage")
    @support_lower = Statistics.scalar(support_lower)
    @support_upper = Statistics.scalar(support_upper)
    if @support_upper <= @support_lower
      raise "empirical Bernstein support upper bound must exceed lower bound"
    @support_width = Statistics.finite_result(
      @support_upper - @support_lower, "empirical Bernstein support width")
    @kappa = Statistics.positive_scalar(kappa, "empirical Bernstein kappa")

    inverse_kappa = ~1.0 / @kappa
    @base_u = Statistics.finite_result(
      ~0.5 * inverse_kappa * inverse_kappa,
      "empirical Bernstein mixture scale")
    inverse_scaled_kappa = inverse_kappa / Math.sqrt(~2.0)
    z = Special.erf(inverse_scaled_kappa)
    @kappa_z = Statistics.finite_result(
      @kappa * z, "empirical Bernstein mixture normalization")
    if @kappa_z <= ~0.0
      raise "empirical Bernstein kappa is outside the representable mixture range"
    log_boundary = Math.log(@kappa_z) + (
      ~0.5 * Math.log(~6.283185307179586)) - Math.log(@miscoverage)
    @log_boundary = Statistics.finite_result(
      log_boundary, "empirical Bernstein log boundary")

    @count = 0
    @sum = ~0.0
    @sum_compensation = ~0.0
    @variance_sum = ~0.0
    @variance_compensation = ~0.0
    @last_predictor = nil
    @active_from = nil

  -> count
    @count

  -> active?
    @active_from != nil

  -> active_from
    @active_from

  -> mergeable?
    false

  -> support
    [@support_lower, @support_upper]

  -> miscoverage
    @miscoverage

  -> kappa
    @kappa

  -> variance_process
    @variance_sum + @variance_compensation

  -> .psi(value)
    ~0.0 - Math.log1p(~0.0 - value) - value

  -> .log_hitting_left(u_value)
    quarter = u_value / ~4.0
    log_difference = quarter + Math.log1p(
      ~-0.5 * Math.exp(~0.0 - quarter))
    ~0.5 * (Math.log(~3.141592653589793) - Math.log(u_value)) + (
      log_difference)

  -> push(value)
    observed = Statistics.scalar(value)
    if observed < @support_lower || observed > @support_upper
      raise "empirical Bernstein observation lies outside the declared support"
    normalized = (observed - @support_lower) / @support_width

    next_count = @count + 1
    previous_total = @sum + @sum_compensation
    predictor = (~0.5 + previous_total) / (next_count + ~0.0)
    deviation = (normalized - predictor).abs
    if deviation >= ~1.0
      raise "empirical Bernstein precision exhausted at a unit deviation"
    psi_value = StatisticsEmpiricalBernsteinSequence.psi(deviation)
    Statistics.finite_result(psi_value, "empirical Bernstein variance update")

    next_sum = Statistics.compensated_add(
      @sum, @sum_compensation, normalized)
    Statistics.finite_result(
      next_sum[0] + next_sum[1], "empirical Bernstein running sum")
    next_variance = Statistics.compensated_add(
      @variance_sum, @variance_compensation, psi_value)
    next_variance_total = Statistics.finite_result(
      next_variance[0] + next_variance[1],
      "empirical Bernstein variance process")

    u_value = @base_u + next_variance_total
    Statistics.finite_result(u_value, "empirical Bernstein U process")
    next_active_from = @active_from
    if next_active_from == nil && (
       StatisticsEmpiricalBernsteinSequence.log_hitting_left(u_value) >= (
         @log_boundary))
      next_active_from = next_count

    @count = next_count
    @sum = next_sum[0]
    @sum_compensation = next_sum[1]
    @variance_sum = next_variance[0]
    @variance_compensation = next_variance[1]
    @last_predictor = predictor
    @active_from = next_active_from
    self

  -> snapshot
    assumptions = [:bounded_adapted_observations,
                   :predictor_is_past_measurable,
                   :fixed_kappa_before_stream]
    warnings = [
      "binary64 evaluation is not a formal coverage certificate",
      "the target is the historical average conditional mean, not an instantaneous drifting mean"]
    variance = variance_process
    if @count == 0
      return StatisticsConfidenceSequenceResult.new(
        0, nil, @support_lower, @support_upper, nil, ~0.0, variance, nil,
        nil, :warming_up, @miscoverage, @kappa,
        [@support_lower, @support_upper], false, assumptions, warnings)

    normalized_center = (@sum + @sum_compensation) / (@count + ~0.0)
    normalized_center = ~0.0 if normalized_center < ~0.0
    normalized_center = ~1.0 if normalized_center > ~1.0
    center = Statistics.finite_result(
      @support_lower + @support_width * normalized_center,
      "empirical Bernstein center")

    if @active_from == nil
      return StatisticsConfidenceSequenceResult.new(
        @count, center, @support_lower, @support_upper, nil, ~0.0,
        variance, @last_predictor, nil, :warming_up, @miscoverage, @kappa,
        [@support_lower, @support_upper], false, assumptions, warnings)

    u_value = @base_u + variance
    denominator = ~0.0 - Math.expm1(~0.0 - u_value / ~4.0)
    if denominator <= ~0.0
      raise "empirical Bernstein closed-form denominator is not positive"
    ell = Math.log(@kappa_z / @miscoverage) - Math.log(denominator)
    radicand_term = ell + ~0.5 * Math.log(~2.0 * u_value)
    if radicand_term <= ~0.0
      raise "empirical Bernstein closed-form radicand is not positive"
    normalized_half_width = (~2.0 / (@count + ~0.0)) * Math.sqrt(
      u_value * radicand_term)
    raw_half_width = @support_width * normalized_half_width

    if raw_half_width.nan? || raw_half_width.infinite?
      warnings.push(
        "active closed-form width exceeded floating-point range; returning known support")
      return StatisticsConfidenceSequenceResult.new(
        @count, center, @support_lower, @support_upper, nil, ~0.0,
        variance, @last_predictor, @active_from, :active, @miscoverage,
        @kappa, [@support_lower, @support_upper], true, assumptions, warnings)

    numerical_guard = ~3.552713678800501e-15 * (
      ~1.0 + center.abs + raw_half_width.abs)
    candidate_lower = center - raw_half_width - numerical_guard
    candidate_upper = center + raw_half_width + numerical_guard
    lower = candidate_lower
    upper = candidate_upper
    clipped = false
    if lower < @support_lower
      lower = @support_lower
      clipped = true
    if upper > @support_upper
      upper = @support_upper
      clipped = true
    StatisticsConfidenceSequenceResult.new(
      @count, center, lower, upper, raw_half_width, numerical_guard,
      variance, @last_predictor, @active_from, :active, @miscoverage,
      @kappa, [@support_lower, @support_upper], clipped, assumptions, warnings)
