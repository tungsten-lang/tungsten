# Multivariate probability distributions over dense binary64 vectors.

use core/math
use core/probability/distribution
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/rng

+ MultivariateRealSupport
  -> new(dimension)
    if !ProbabilityNumerics.integer?(dimension) || dimension <= 0
      raise "probability multivariate support dimension must be positive"
    @dimension = dimension
    self

  -> dimension
    @dimension

  -> contains?(value)
    return false if value.class_name != "Array" || value.size != @dimension
    i = 0
    while i < value.size
      converted = value[i].to_f
      return false if converted != converted || converted.infinite?
      i += 1
    true

  -> to_s
    "RealVectorSupport(dimension=" + @dimension.to_s + ")"


+ MultivariateProbabilityDistribution
  -> dimension
    raise "dimension is not implemented for " + self.class_name

  -> log_probability(value)
    raise "log probability is not implemented for " + self.class_name

  -> log_prob(value)
    log_probability(value)

  -> probability(value)
    Math.exp(log_probability(value))

  -> pdf(value)
    probability(value)

  -> mean
    raise "mean is not implemented for " + self.class_name

  -> covariance
    raise "covariance is not implemented for " + self.class_name

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    raise "sample is not implemented for " + self.class_name

  -> samples(count, rng = nil)
    ProbabilityNumerics.validate_count(count)
    ProbabilityRandom.require_rng(rng)
    values = []
    count.times -> values.push(sample(rng))
    values

  -> log_probabilities(values)
    if values.class_name != "Array"
      raise "probability batch must be an Array"
    result = []
    i = 0
    while i < values.size
      result.push(log_probability(values[i]))
      i += 1
    result


+ MultivariateNormalDistribution < MultivariateProbabilityDistribution
  -> new(mean, covariance)
    @mean = ProbabilityLinearAlgebra.vector(mean, "multivariate Normal mean")
    @dimension = @mean.size
    @covariance = ProbabilityLinearAlgebra.symmetric_matrix(
      covariance, @dimension, "multivariate Normal covariance")
    @cholesky = ProbabilityLinearAlgebra.cholesky(
      @covariance, "multivariate Normal covariance")
    @log_determinant = ProbabilityLinearAlgebra.log_determinant_from_cholesky(
      @cholesky)
    @log_normalizer = ~-0.5*(
      (@dimension + ~0.0)*~1.8378770664093453 + @log_determinant)
    @support = MultivariateRealSupport.new(@dimension)
    self

  -> dimension
    @dimension

  -> mean
    ProbabilityNumerics.copy_array(@mean)

  -> covariance
    ProbabilityLinearAlgebra.copy_matrix(@covariance)

  -> cholesky
    ProbabilityLinearAlgebra.copy_matrix(@cholesky)

  -> log_determinant
    @log_determinant

  -> support
    @support

  -> validate_value(value)
    ProbabilityLinearAlgebra.vector_dimension(
      value, @dimension, "multivariate Normal value")

  -> mahalanobis_squared(value)
    vector = validate_value(value)
    difference = ProbabilityLinearAlgebra.subtract(vector, @mean)
    ProbabilityLinearAlgebra.mahalanobis_squared(@cholesky, difference)

  -> log_probability(value)
    @log_normalizer - ~0.5*mahalanobis_squared(value)

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    standard = []
    @dimension.times -> standard.push(ProbabilityRandom.standard_normal(rng))
    transformed = ProbabilityLinearAlgebra.matvec(@cholesky, standard)
    ProbabilityLinearAlgebra.add(@mean, transformed)

  -> marginal(indices)
    selected = ProbabilityLinearAlgebra.validate_indices(
      indices, @dimension, "marginal indices")
    MultivariateNormalDistribution.new(
      ProbabilityLinearAlgebra.subvector(@mean, selected),
      ProbabilityLinearAlgebra.submatrix(@covariance, selected, selected))

  # Conditional law of all unobserved coordinates given selected coordinates.
  -> condition(observed_indices, observed_values)
    observed = ProbabilityLinearAlgebra.validate_indices(
      observed_indices, @dimension, "conditioning indices")
    values = ProbabilityLinearAlgebra.vector_dimension(
      observed_values, observed.size, "conditioning values")
    if observed.size >= @dimension
      raise "probability conditioning must leave at least one coordinate"
    marked = []
    @dimension.times -> marked.push(false)
    i = 0
    while i < observed.size
      marked[observed[i]] = true
      i += 1
    unobserved = []
    i = 0
    while i < @dimension
      unobserved.push(i) if !marked[i]
      i += 1

    covariance_oo = ProbabilityLinearAlgebra.submatrix(
      @covariance, observed, observed)
    covariance_uo = ProbabilityLinearAlgebra.submatrix(
      @covariance, unobserved, observed)
    covariance_ou = ProbabilityLinearAlgebra.transpose(covariance_uo)
    covariance_uu = ProbabilityLinearAlgebra.submatrix(
      @covariance, unobserved, unobserved)
    conditioning_cholesky = ProbabilityLinearAlgebra.cholesky(
      covariance_oo, "conditioning covariance")
    mean_o = ProbabilityLinearAlgebra.subvector(@mean, observed)
    mean_u = ProbabilityLinearAlgebra.subvector(@mean, unobserved)
    delta = ProbabilityLinearAlgebra.subtract(values, mean_o)
    solved_delta = ProbabilityLinearAlgebra.solve_spd_from_cholesky(
      conditioning_cholesky, delta)
    conditional_mean = ProbabilityLinearAlgebra.add(
      mean_u, ProbabilityLinearAlgebra.matvec(covariance_uo, solved_delta))

    correction = LinAlg.zeros(unobserved.size, unobserved.size)
    column = 0
    while column < unobserved.size
      right_hand_side = []
      row = 0
      while row < observed.size
        right_hand_side.push(covariance_ou[row][column])
        row += 1
      solved_column = ProbabilityLinearAlgebra.solve_spd_from_cholesky(
        conditioning_cholesky, right_hand_side)
      row = 0
      while row < unobserved.size
        correction[row][column] = ProbabilityLinearAlgebra.dot(
          covariance_uo[row], solved_column)
        row += 1
      column += 1
    conditional_covariance = LinAlg.zeros(unobserved.size, unobserved.size)
    i = 0
    while i < unobserved.size
      j = 0
      while j < unobserved.size
        conditional_covariance[i][j] = covariance_uu[i][j] - correction[i][j]
        j += 1
      i += 1
    MultivariateNormalDistribution.new(
      conditional_mean, conditional_covariance)

  # Exact affine image A X + b; A must have full row rank so covariance is SPD.
  -> affine(matrix, offset)
    transform = ProbabilityLinearAlgebra.matrix(
      matrix, "affine transform matrix")
    if transform[0].size != @dimension
      raise "probability affine transform has the wrong input dimension"
    shift = ProbabilityLinearAlgebra.vector_dimension(
      offset, transform.size, "affine transform offset")
    transformed_mean = ProbabilityLinearAlgebra.add(
      ProbabilityLinearAlgebra.matvec(transform, @mean), shift)
    transformed_covariance = ProbabilityLinearAlgebra.matmul(
      ProbabilityLinearAlgebra.matmul(transform, @covariance),
      ProbabilityLinearAlgebra.transpose(transform))
    MultivariateNormalDistribution.new(
      transformed_mean, transformed_covariance)

  -> to_s
    "MultivariateNormal(dimension=" + @dimension.to_s + ")"
