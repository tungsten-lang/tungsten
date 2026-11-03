# Mergeable one-pass moments and their immutable descriptive summary.

+ StatisticsSummary
  -> new(@count, @sum, @mean, @m2, @minimum, @maximum)

  ro :count, :minimum, :maximum

  -> empty?
    @count == 0

  -> sum
    Statistics.finite_result(@sum, "sum")

  -> mean
    if empty?
      raise "mean requires at least one observation"
    Statistics.finite_result(@mean, "mean")

  -> range
    if empty?
      raise "range requires at least one observation"
    @maximum - @minimum

  -> sum_of_squared_deviations
    Statistics.nonnegative_moment(@m2, "variance moment")

  -> variance(correction = 1)
    Statistics.validate_correction(correction, @count, "variance")
    sum_of_squared_deviations / (@count - correction + ~0.0)

  -> population_variance
    variance(0)

  -> sample_variance
    variance(1)

  -> standard_deviation(correction = 1)
    Math.sqrt(variance(correction))

  -> population_standard_deviation
    standard_deviation(0)

  -> sample_standard_deviation
    standard_deviation(1)

  -> standard_error
    Math.sqrt(sample_variance / (@count + ~0.0))

  -> mean_measurement
    mean ± standard_error

  -> to_s
    if empty?
      return "StatisticsSummary(count=0)"
    if @count == 1
      return "StatisticsSummary(count=1, mean=" + mean.to_s + ")"
    text = "StatisticsSummary(count=" + @count.to_s
    text += ", mean=" + mean.to_s
    text + ", sample_std=" + sample_standard_deviation.to_s + ")"

  -> inspect
    to_s


+ StatisticsAccumulator
  -> new
    @count = 0
    @sum = ~0.0
    @compensation = ~0.0
    @moment_mean = ~0.0
    @m2 = ~0.0
    @minimum = nil
    @maximum = nil

  ro :count, :compensation, :moment_mean, :m2, :minimum, :maximum

  -> empty?
    @count == 0

  -> sum
    @sum + @compensation

  -> push(value)
    x = Statistics.scalar(value)
    added = Statistics.compensated_add(@sum, @compensation, x)
    @sum = added[0]
    @compensation = added[1]

    @count += 1
    if @count == 1
      @moment_mean = x
      @minimum = x
      @maximum = x
      return self

    delta = x - @moment_mean
    @moment_mean += delta / (@count + ~0.0)
    @m2 += delta * (x - @moment_mean)
    @minimum = x if x < @minimum
    @maximum = x if x > @maximum
    self

  -> merge(other)
    if other.class_name != "StatisticsAccumulator"
      raise "can only merge another StatisticsAccumulator"
    return self if other.empty?

    if empty?
      @count = other.count
      @sum = other.sum
      @compensation = ~0.0
      @moment_mean = other.moment_mean
      @m2 = other.m2
      @minimum = other.minimum
      @maximum = other.maximum
      return self

    left_count = @count
    combined_count = left_count + other.count
    delta = other.moment_mean - @moment_mean
    cross_weight = (left_count + ~0.0) * (other.count + ~0.0) / (combined_count + ~0.0)
    @m2 += other.m2 + delta * delta * cross_weight
    @moment_mean += delta * (other.count + ~0.0) / (combined_count + ~0.0)
    @count = combined_count

    added = Statistics.compensated_add(@sum, @compensation, other.sum)
    @sum = added[0]
    @compensation = added[1]
    @minimum = other.minimum if other.minimum < @minimum
    @maximum = other.maximum if other.maximum > @maximum
    self

  -> snapshot
    total = sum
    average = nil
    if @count > 0
      if total.nan? || total.infinite?
        average = @moment_mean
      else
        average = total / (@count + ~0.0)
    StatisticsSummary.new(
      @count, total, average, @m2, @minimum, @maximum)
