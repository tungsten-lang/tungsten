# Mergeable weighted scalar moments.
#
# Population variance divides by sum(w). Reliability variance uses the
# unbiased denominator sum(w) - sum(w^2)/sum(w). Frequency variance is only
# available when every weight is a nonnegative integer and divides by
# sum(w) - 1. These conventions are intentionally distinct.

+ StatisticsWeightedSummary
  -> new(@count, @positive_weight_count, @weight_sum, @weight_square_sum,
         @mean, @m2, @frequency_compatible)

  -> count
    @count

  -> positive_weight_count
    @positive_weight_count

  -> empty?
    @positive_weight_count == 0

  -> total_weight
    Statistics.finite_result(@weight_sum, "weight sum")

  -> squared_weight_sum
    Statistics.finite_result(@weight_square_sum, "squared weight sum")

  -> mean
    if empty?
      raise "weighted mean requires positive total weight"
    Statistics.finite_result(@mean, "weighted mean")

  -> sum_of_weighted_squared_deviations
    Statistics.nonnegative_moment(@m2, "weighted variance moment")

  -> frequency_compatible?
    @frequency_compatible

  -> effective_sample_size
    if empty? || squared_weight_sum == ~0.0
      raise "effective sample size requires positive total weight"
    total_weight / (squared_weight_sum / total_weight)

  -> population_variance
    if empty?
      raise "weighted population variance requires positive total weight"
    sum_of_weighted_squared_deviations / total_weight

  -> reliability_degrees_of_freedom
    if empty?
      raise "weighted reliability variance requires positive total weight"
    denominator = total_weight - squared_weight_sum / total_weight
    if denominator <= ~0.0
      raise "weighted reliability variance requires positive effective degrees of freedom"
    denominator

  -> reliability_variance
    sum_of_weighted_squared_deviations / reliability_degrees_of_freedom

  -> frequency_variance
    if !frequency_compatible?
      raise "weighted frequency variance requires integer frequency weights"
    if total_weight <= ~1.0
      raise "weighted frequency variance requires total weight greater than one"
    sum_of_weighted_squared_deviations / (total_weight - ~1.0)

  -> reliability_standard_error
    Math.sqrt(reliability_variance / effective_sample_size)

  -> to_s
    if empty?
      return "StatisticsWeightedSummary(count=" + @count.to_s + ", total_weight=0.0)"
    text = "StatisticsWeightedSummary(count=" + @count.to_s
    text += ", total_weight=" + total_weight.to_s
    text + ", mean=" + mean.to_s + ")"

  -> inspect
    to_s


+ StatisticsWeightedAccumulator
  -> new
    @count = 0
    @positive_weight_count = 0
    @weight_sum = ~0.0
    @weight_compensation = ~0.0
    @weight_square_sum = ~0.0
    @weight_square_compensation = ~0.0
    @moment_mean = ~0.0
    @m2 = ~0.0
    @frequency_compatible = true

  -> count
    @count

  -> positive_weight_count
    @positive_weight_count

  -> empty?
    @positive_weight_count == 0

  -> total_weight
    @weight_sum + @weight_compensation

  -> squared_weight_sum
    @weight_square_sum + @weight_square_compensation

  -> moment_mean
    @moment_mean

  -> m2
    @m2

  -> frequency_compatible?
    @frequency_compatible

  -> push(value, weight_value = ~1.0)
    x = Statistics.scalar(value)
    weight = Statistics.weight(weight_value)
    @count += 1
    if weight == ~0.0
      return self

    weight_square = Statistics.finite_result(weight * weight, "squared weight")
    @frequency_compatible = false if Math.floor(weight) != weight
    old_weight = total_weight
    added = Statistics.compensated_add(
      @weight_sum, @weight_compensation, weight)
    @weight_sum = added[0]
    @weight_compensation = added[1]
    added_square = Statistics.compensated_add(
      @weight_square_sum, @weight_square_compensation, weight_square)
    @weight_square_sum = added_square[0]
    @weight_square_compensation = added_square[1]
    new_weight = total_weight
    Statistics.finite_result(new_weight, "weight sum")
    @positive_weight_count += 1

    if old_weight == ~0.0
      @moment_mean = x
      return self

    delta = x - @moment_mean
    @moment_mean += delta * (weight / new_weight)
    @m2 += weight * delta * (x - @moment_mean)
    Statistics.finite_result(@moment_mean, "weighted mean")
    Statistics.nonnegative_moment(@m2, "weighted variance moment")
    self

  -> merge(other)
    if other.class_name != "StatisticsWeightedAccumulator"
      raise "can only merge another StatisticsWeightedAccumulator"
    @count += other.count
    return self if other.empty?

    if empty?
      @positive_weight_count = other.positive_weight_count
      @weight_sum = other.total_weight
      @weight_compensation = ~0.0
      @weight_square_sum = other.squared_weight_sum
      @weight_square_compensation = ~0.0
      @moment_mean = other.moment_mean
      @m2 = other.m2
      @frequency_compatible = other.frequency_compatible?
      return self

    left_weight = total_weight
    right_weight = other.total_weight
    combined_weight = left_weight + right_weight
    Statistics.finite_result(combined_weight, "weight sum")
    delta = other.moment_mean - @moment_mean
    cross_weight = left_weight * (right_weight / combined_weight)
    @m2 += other.m2 + delta * delta * cross_weight
    @moment_mean += delta * (right_weight / combined_weight)
    @positive_weight_count += other.positive_weight_count
    @frequency_compatible = (
      @frequency_compatible && other.frequency_compatible?)

    added = Statistics.compensated_add(
      @weight_sum, @weight_compensation, right_weight)
    @weight_sum = added[0]
    @weight_compensation = added[1]
    added_square = Statistics.compensated_add(
      @weight_square_sum, @weight_square_compensation,
      other.squared_weight_sum)
    @weight_square_sum = added_square[0]
    @weight_square_compensation = added_square[1]
    Statistics.nonnegative_moment(@m2, "weighted variance moment")
    self

  -> snapshot
    mean = nil
    mean = @moment_mean if !empty?
    StatisticsWeightedSummary.new(
      @count, @positive_weight_count, total_weight, squared_weight_sum,
      mean, @m2, @frequency_compatible)
