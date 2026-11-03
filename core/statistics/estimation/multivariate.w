# Mergeable weighted multivariate moments and covariance matrices.

+ StatisticsMultivariateSummary
  -> new(@count, @positive_weight_count, @weight_sum, @weight_square_sum,
         @mean, @scatter, @frequency_compatible)

  ro :count, :positive_weight_count

  -> dimension
    @mean == nil ? 0 : @mean.size

  -> empty?
    @positive_weight_count == 0

  -> total_weight
    Statistics.finite_result(@weight_sum, "multivariate weight sum")

  -> squared_weight_sum
    Statistics.finite_result(@weight_square_sum, "multivariate squared weight sum")

  -> mean
    if empty?
      raise "multivariate mean requires positive total weight"
    copy = []
    @mean.each -> (value)
      copy.push(Statistics.finite_result(value, "multivariate mean"))
    copy

  -> scatter_matrix
    if empty?
      raise "multivariate scatter requires positive total weight"
    result = LinAlg.zeros(dimension, dimension)
    i = 0
    while i < dimension
      j = i
      while j < dimension
        value = (@scatter[i][j] + @scatter[j][i]) / ~2.0
        value = Statistics.finite_result(value, "multivariate scatter")
        if i == j
          value = Statistics.nonnegative_moment(
            value, "multivariate scatter diagonal")
        result[i][j] = value
        result[j][i] = value
        j += 1
      i += 1
    result

  -> frequency_compatible?
    @frequency_compatible

  -> effective_sample_size
    if empty? || squared_weight_sum == ~0.0
      raise "multivariate effective sample size requires positive total weight"
    total_weight / (squared_weight_sum / total_weight)

  -> covariance_with_denominator(denominator, operation)
    if denominator <= ~0.0
      raise operation + " requires positive effective degrees of freedom"
    scatter = scatter_matrix
    covariance = LinAlg.zeros(dimension, dimension)
    i = 0
    while i < dimension
      j = 0
      while j < dimension
        value = scatter[i][j] / denominator
        covariance[i][j] = Statistics.finite_result(value, operation)
        j += 1
      i += 1
    covariance

  -> population_covariance
    if empty?
      raise "multivariate population covariance requires positive total weight"
    covariance_with_denominator(total_weight, "multivariate population covariance")

  -> reliability_covariance
    if empty?
      raise "multivariate reliability covariance requires positive total weight"
    denominator = total_weight - squared_weight_sum / total_weight
    covariance_with_denominator(
      denominator, "multivariate reliability covariance")

  -> frequency_covariance
    if !frequency_compatible?
      raise "multivariate frequency covariance requires integer frequency weights"
    covariance_with_denominator(
      total_weight - ~1.0, "multivariate frequency covariance")

  -> correlation_matrix
    covariance = population_covariance
    correlation = LinAlg.zeros(dimension, dimension)
    i = 0
    while i < dimension
      if covariance[i][i] <= ~0.0
        raise "multivariate correlation is undefined for zero-variance dimensions"
      j = 0
      while j < dimension
        if covariance[j][j] <= ~0.0
          raise "multivariate correlation is undefined for zero-variance dimensions"
        value = covariance[i][j] / (
          Math.sqrt(covariance[i][i]) * Math.sqrt(covariance[j][j]))
        Statistics.finite_result(value, "multivariate correlation")
        value = ~1.0 if value > ~1.0
        value = ~-1.0 if value < ~-1.0
        correlation[i][j] = value
        j += 1
      i += 1
    correlation

  -> to_s
    text = "StatisticsMultivariateSummary(count=" + @count.to_s
    text + ", dimension=" + dimension.to_s + ")"

  -> inspect
    to_s


+ StatisticsMultivariateAccumulator
  -> new(dimension)
    if !Statistics.integer?(dimension) || dimension <= 0
      raise "multivariate dimension must be a positive integer"
    @dimension = dimension
    @count = 0
    @positive_weight_count = 0
    @weight_sum = ~0.0
    @weight_compensation = ~0.0
    @weight_square_sum = ~0.0
    @weight_square_compensation = ~0.0
    @moment_mean = []
    dimension.times ->
      @moment_mean.push(~0.0)
    @scatter = LinAlg.zeros(dimension, dimension)
    @frequency_compatible = true

  ro :dimension, :count, :positive_weight_count

  -> empty?
    @positive_weight_count == 0

  -> total_weight
    @weight_sum + @weight_compensation

  -> squared_weight_sum
    @weight_square_sum + @weight_square_compensation

  -> moment_mean
    Statistics.copy_vector(@moment_mean)

  -> scatter
    Statistics.copy_matrix(@scatter)

  -> frequency_compatible?
    @frequency_compatible

  -> validated_row(row)
    if row.size != @dimension
      raise "multivariate observation dimension does not match accumulator"
    values = []
    row.each -> (value)
      values.push(Statistics.scalar(value))
    values

  -> push(row, weight_value = ~1.0)
    values = validated_row(row)
    weight = Statistics.weight(weight_value)
    @count += 1
    return self if weight == ~0.0

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
    Statistics.finite_result(new_weight, "multivariate weight sum")
    @positive_weight_count += 1

    if old_weight == ~0.0
      @moment_mean = Statistics.copy_vector(values)
      return self

    delta = []
    i = 0
    while i < @dimension
      delta.push(values[i] - @moment_mean[i])
      @moment_mean[i] += delta[i] * (weight / new_weight)
      i += 1
    i = 0
    while i < @dimension
      j = 0
      while j < @dimension
        @scatter[i][j] += weight * delta[i] * (values[j] - @moment_mean[j])
        j += 1
      i += 1
    Statistics.finite_result(@moment_mean[0], "multivariate mean")
    self

  -> merge(other)
    if other.class_name != "StatisticsMultivariateAccumulator"
      raise "can only merge another StatisticsMultivariateAccumulator"
    if other.dimension != @dimension
      raise "cannot merge multivariate accumulators with different dimensions"
    @count += other.count
    return self if other.empty?

    if empty?
      @positive_weight_count = other.positive_weight_count
      @weight_sum = other.total_weight
      @weight_compensation = ~0.0
      @weight_square_sum = other.squared_weight_sum
      @weight_square_compensation = ~0.0
      @moment_mean = other.moment_mean
      @scatter = other.scatter
      @frequency_compatible = other.frequency_compatible?
      return self

    left_weight = total_weight
    right_weight = other.total_weight
    combined_weight = left_weight + right_weight
    Statistics.finite_result(combined_weight, "multivariate weight sum")
    cross_weight = left_weight * (right_weight / combined_weight)
    other_mean = other.moment_mean
    other_scatter = other.scatter
    delta = []
    i = 0
    while i < @dimension
      delta.push(other_mean[i] - @moment_mean[i])
      i += 1
    i = 0
    while i < @dimension
      j = 0
      while j < @dimension
        @scatter[i][j] += other_scatter[i][j] + (
          delta[i] * delta[j] * cross_weight)
        j += 1
      @moment_mean[i] += delta[i] * (right_weight / combined_weight)
      i += 1
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
    self

  -> snapshot
    StatisticsMultivariateSummary.new(
      @count, @positive_weight_count, total_weight, squared_weight_sum,
      moment_mean, scatter, @frequency_compatible)
