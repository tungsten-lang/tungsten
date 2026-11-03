# Mergeable paired moments for covariance and Pearson correlation.

+ StatisticsBivariateSummary
  -> new(@count, @mean_x, @mean_y, @m2_x, @m2_y, @co_moment)

  ro :count

  -> empty?
    @count == 0

  -> mean_x
    if empty?
      raise "paired mean requires at least one observation"
    Statistics.finite_result(@mean_x, "paired x mean")

  -> mean_y
    if empty?
      raise "paired mean requires at least one observation"
    Statistics.finite_result(@mean_y, "paired y mean")

  -> covariance(correction = 1)
    Statistics.validate_correction(correction, @count, "covariance")
    co_moment = Statistics.finite_result(@co_moment, "covariance moment")
    co_moment / (@count - correction + ~0.0)

  -> population_covariance
    covariance(0)

  -> sample_covariance
    covariance(1)

  -> correlation
    if @count < 2
      raise "correlation requires at least two paired observations"
    x_variation = Statistics.nonnegative_moment(
      @m2_x, "correlation x moment")
    y_variation = Statistics.nonnegative_moment(
      @m2_y, "correlation y moment")
    if x_variation == ~0.0 || y_variation == ~0.0
      raise "correlation is undefined for zero-variance observations"
    co_moment = Statistics.finite_result(
      @co_moment, "correlation co-moment")
    value = co_moment / Math.sqrt(x_variation) / Math.sqrt(y_variation)
    Statistics.finite_result(value, "correlation")
    return ~1.0 if value > ~1.0
    return ~-1.0 if value < ~-1.0
    value

  -> to_s
    if empty?
      return "StatisticsBivariateSummary(count=0)"
    text = "StatisticsBivariateSummary(count=" + @count.to_s
    text += ", mean_x=" + mean_x.to_s
    text + ", mean_y=" + mean_y.to_s + ")"

  -> inspect
    to_s


+ StatisticsBivariateAccumulator
  -> new
    @count = 0
    @sum_x = ~0.0
    @compensation_x = ~0.0
    @sum_y = ~0.0
    @compensation_y = ~0.0
    @moment_mean_x = ~0.0
    @moment_mean_y = ~0.0
    @m2_x = ~0.0
    @m2_y = ~0.0
    @co_moment = ~0.0

  ro :count, :moment_mean_x, :moment_mean_y, :m2_x, :m2_y, :co_moment

  -> empty?
    @count == 0

  -> sum_x
    @sum_x + @compensation_x

  -> sum_y
    @sum_y + @compensation_y

  -> push(x_value, y_value)
    x = Statistics.scalar(x_value)
    y = Statistics.scalar(y_value)

    added_x = Statistics.compensated_add(@sum_x, @compensation_x, x)
    @sum_x = added_x[0]
    @compensation_x = added_x[1]
    added_y = Statistics.compensated_add(@sum_y, @compensation_y, y)
    @sum_y = added_y[0]
    @compensation_y = added_y[1]

    @count += 1
    if @count == 1
      @moment_mean_x = x
      @moment_mean_y = y
      return self

    delta_x = x - @moment_mean_x
    delta_y = y - @moment_mean_y
    @moment_mean_x += delta_x / (@count + ~0.0)
    @moment_mean_y += delta_y / (@count + ~0.0)
    @m2_x += delta_x * (x - @moment_mean_x)
    @m2_y += delta_y * (y - @moment_mean_y)
    @co_moment += delta_x * (y - @moment_mean_y)
    self

  -> merge(other)
    if other.class_name != "StatisticsBivariateAccumulator"
      raise "can only merge another StatisticsBivariateAccumulator"
    return self if other.empty?

    if empty?
      @count = other.count
      @sum_x = other.sum_x
      @compensation_x = ~0.0
      @sum_y = other.sum_y
      @compensation_y = ~0.0
      @moment_mean_x = other.moment_mean_x
      @moment_mean_y = other.moment_mean_y
      @m2_x = other.m2_x
      @m2_y = other.m2_y
      @co_moment = other.co_moment
      return self

    left_count = @count
    combined_count = left_count + other.count
    weight = (left_count + ~0.0) * (other.count + ~0.0) / (combined_count + ~0.0)
    delta_x = other.moment_mean_x - @moment_mean_x
    delta_y = other.moment_mean_y - @moment_mean_y
    @m2_x += other.m2_x + delta_x * delta_x * weight
    @m2_y += other.m2_y + delta_y * delta_y * weight
    @co_moment += other.co_moment + delta_x * delta_y * weight
    @moment_mean_x += delta_x * (other.count + ~0.0) / (combined_count + ~0.0)
    @moment_mean_y += delta_y * (other.count + ~0.0) / (combined_count + ~0.0)
    @count = combined_count

    added_x = Statistics.compensated_add(@sum_x, @compensation_x, other.sum_x)
    @sum_x = added_x[0]
    @compensation_x = added_x[1]
    added_y = Statistics.compensated_add(@sum_y, @compensation_y, other.sum_y)
    @sum_y = added_y[0]
    @compensation_y = added_y[1]
    self

  -> snapshot
    total_x = sum_x
    total_y = sum_y
    mean_x = nil
    mean_y = nil
    if @count > 0
      if total_x.nan? || total_x.infinite?
        mean_x = @moment_mean_x
      else
        mean_x = total_x / (@count + ~0.0)
      if total_y.nan? || total_y.infinite?
        mean_y = @moment_mean_y
      else
        mean_y = total_y / (@count + ~0.0)
    StatisticsBivariateSummary.new(
      @count, mean_x, mean_y, @m2_x, @m2_y, @co_moment)
