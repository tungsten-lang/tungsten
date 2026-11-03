# Gaussian copulas and copula-composed continuous multivariate laws.

use core/math
use core/probability/linear_algebra
use core/probability/multivariate
use core/probability/primitives
use core/probability/rng
use core/probability/special

+ GaussianCopula
  -> new(correlation)
    @correlation = ProbabilityLinearAlgebra.symmetric_matrix(
      correlation, nil, "Gaussian copula correlation")
    i = 0
    while i < @correlation.size
      if ProbabilityLinearAlgebra.absolute(@correlation[i][i] - ~1.0) > ~1.0e-12
        raise "probability copula correlation diagonal must equal one"
      j = 0
      while j < @correlation.size
        if @correlation[i][j] < ~-1.0 || @correlation[i][j] > ~1.0
          raise "probability copula correlations must be between -1 and 1"
        j += 1
      i += 1
    mean = []
    @correlation.size.times -> mean.push(~0.0)
    @normal = MultivariateNormalDistribution.new(mean, @correlation)
    self

  -> dimension
    @correlation.size

  -> correlation
    ProbabilityLinearAlgebra.copy_matrix(@correlation)

  -> latent_normal
    @normal

  -> latent_values(uniforms)
    values = ProbabilityLinearAlgebra.vector_dimension(
      uniforms, dimension, "copula value")
    latent = []
    i = 0
    while i < values.size
      if values[i] <= ~0.0 || values[i] >= ~1.0
        raise "probability copula values must be strictly between zero and one"
      latent.push(ProbabilitySpecial.normal_quantile(values[i]))
      i += 1
    latent

  -> log_density(uniforms)
    latent = latent_values(uniforms)
    independent_log = ~0.0
    i = 0
    while i < latent.size
      independent_log += (~-0.5*latent[i]*latent[i] -
                          ~0.9189385332046727)
      i += 1
    @normal.log_prob(latent) - independent_log

  -> density(uniforms)
    Math.exp(log_density(uniforms))

  -> sample(rng = nil)
    latent = @normal.sample(rng)
    uniforms = []
    i = 0
    while i < latent.size
      uniforms.push(ProbabilitySpecial.standard_normal_cdf(latent[i]))
      i += 1
    uniforms

  -> samples(count, rng = nil)
    ProbabilityNumerics.validate_count(count)
    ProbabilityRandom.require_rng(rng)
    result = []
    count.times -> result.push(sample(rng))
    result


+ CopulaDistribution < MultivariateProbabilityDistribution
  ro :copula, :support

  -> new(copula, marginals)
    if marginals.class_name != "Array" || marginals.size != copula.dimension
      raise "probability copula marginals must match copula dimension"
    @copula = copula
    @marginals = ProbabilityNumerics.copy_array(marginals)
    i = 0
    while i < @marginals.size
      if !@marginals[i].continuous? || !@marginals[i].respond_to?("quantile")
        raise "probability copula marginals must be continuous distributions"
      i += 1
    @support = MultivariateRealSupport.new(@marginals.size)
    self

  -> dimension
    @marginals.size

  -> marginals
    ProbabilityNumerics.copy_array(@marginals)

  -> log_probability(value)
    vector = ProbabilityLinearAlgebra.vector_dimension(
      value, dimension, "copula-distribution value")
    uniforms = []
    marginal_log = ~0.0
    i = 0
    while i < dimension
      uniform = @marginals[i].cdf(vector[i])
      return ProbabilityNumerics.negative_infinity if (
        uniform <= ~0.0 || uniform >= ~1.0)
      uniforms.push(uniform)
      marginal_log += @marginals[i].log_prob(vector[i])
      i += 1
    @copula.log_density(uniforms) + marginal_log

  -> sample(rng = nil)
    uniforms = @copula.sample(rng)
    result = []
    i = 0
    while i < dimension
      result.push(@marginals[i].quantile(uniforms[i]))
      i += 1
    result
