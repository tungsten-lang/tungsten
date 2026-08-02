# Reparameterized mean-field Gaussian variational inference with Adam updates.
#
# The target must supply both log density and its analytic vector gradient.
# This is stochastic ELBO optimization, not a posterior-accuracy guarantee.

use core/math
use core/probability/inference/mcmc
use core/probability/linear_algebra
use core/probability/multivariate
use core/probability/primitives
use core/probability/rng

+ MeanFieldGaussianDistribution < MultivariateProbabilityDistribution
  -> new(mean, log_scales)
    @mean = ProbabilityLinearAlgebra.vector(mean, "variational mean")
    @log_scales = ProbabilityLinearAlgebra.vector_dimension(
      log_scales, @mean.size, "variational log scales")
    @scales = []
    i = 0
    while i < @log_scales.size
      scale = Math.exp(@log_scales[i])
      if scale <= ~0.0 || scale.infinite?
        raise "probability variational scale must be finite and positive"
      @scales.push(scale)
      i += 1
    @support = MultivariateRealSupport.new(@mean.size)
    self

  -> dimension
    @mean.size

  -> mean
    ProbabilityNumerics.copy_array(@mean)

  -> log_scales
    ProbabilityNumerics.copy_array(@log_scales)

  -> scales
    ProbabilityNumerics.copy_array(@scales)

  -> covariance
    matrix = LinAlg.zeros(dimension, dimension)
    i = 0
    while i < dimension
      matrix[i][i] = @scales[i]*@scales[i]
      i += 1
    matrix

  -> support
    @support

  -> log_probability(value)
    vector = ProbabilityLinearAlgebra.vector_dimension(
      value, dimension, "mean-field Gaussian value")
    total = ~0.0
    i = 0
    while i < dimension
      standardized = (vector[i] - @mean[i]) / @scales[i]
      total += (~-0.5*standardized*standardized - @log_scales[i] -
                ~0.9189385332046727)
      i += 1
    total

  -> entropy
    total = ~0.0
    i = 0
    while i < dimension
      total += @log_scales[i] + ~1.4189385332046727
      i += 1
    total

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    result = []
    i = 0
    while i < dimension
      result.push(@mean[i] + @scales[i]*ProbabilityRandom.standard_normal(rng))
      i += 1
    result


+ VariationalResult
  -> new(distribution, elbo_trace)
    @distribution = distribution
    @elbo_trace = ProbabilityNumerics.copy_array(elbo_trace)
    self

  -> distribution
    @distribution

  -> elbo_trace
    ProbabilityNumerics.copy_array(@elbo_trace)

  -> final_elbo
    return ProbabilityNumerics.negative_infinity if @elbo_trace.size == 0
    @elbo_trace[@elbo_trace.size - 1]


+ MeanFieldVariationalInference
  -> new(log_density, gradient, learning_rate = ~0.02,
         monte_carlo_samples = 8)
    @log_density = log_density
    @gradient = gradient
    @learning_rate = ProbabilityNumerics.positive_finite(
      learning_rate, "variational learning rate")
    @monte_carlo_samples = ProbabilityInference.positive_integer(
      monte_carlo_samples, "variational Monte Carlo sample count")
    self

  -> fit(initial_mean, initial_log_scales, iterations, rng)
    mean = ProbabilityLinearAlgebra.vector(initial_mean, "variational mean")
    log_scales = ProbabilityLinearAlgebra.vector_dimension(
      initial_log_scales, mean.size, "variational log scales")
    ProbabilityNumerics.validate_count(iterations, "variational iteration count")
    ProbabilityRandom.require_rng(rng)
    mean_first = []
    mean_second = []
    scale_first = []
    scale_second = []
    mean.size.times ->
      mean_first.push(~0.0)
      mean_second.push(~0.0)
      scale_first.push(~0.0)
      scale_second.push(~0.0)
    trace = []
    iteration = 0
    while iteration < iterations
      scales = []
      i = 0
      while i < log_scales.size
        scales.push(Math.exp(log_scales[i]))
        i += 1
      mean_gradient = []
      scale_gradient = []
      mean.size.times ->
        mean_gradient.push(~0.0)
        scale_gradient.push(~0.0)
      elbo = ~0.0
      draw = 0
      while draw < @monte_carlo_samples
        epsilon = []
        position = []
        i = 0
        while i < mean.size
          noise = ProbabilityRandom.standard_normal(rng)
          epsilon.push(noise)
          position.push(mean[i] + scales[i]*noise)
          i += 1
        target = ProbabilityInference.log_density_value(
          @log_density, position)
        target_gradient = ProbabilityInference.gradient_value(
          @gradient, position)
        approximation = MeanFieldGaussianDistribution.new(
          mean, log_scales).log_prob(position)
        elbo += target - approximation
        i = 0
        while i < mean.size
          mean_gradient[i] = mean_gradient[i] + target_gradient[i]
          scale_gradient[i] = (scale_gradient[i] +
            target_gradient[i]*scales[i]*epsilon[i] + ~1.0)
          i += 1
        draw += 1
      inverse_draws = ~1.0 / (@monte_carlo_samples + ~0.0)
      elbo *= inverse_draws
      trace.push(elbo)
      time = iteration + 1
      beta1_power = Math.exp((time + ~0.0)*Math.log(~0.9))
      beta2_power = Math.exp((time + ~0.0)*Math.log(~0.999))
      i = 0
      while i < mean.size
        mean_grad = mean_gradient[i]*inverse_draws
        scale_grad = scale_gradient[i]*inverse_draws
        mean_grad = ~100.0 if mean_grad > ~100.0
        mean_grad = ~-100.0 if mean_grad < ~-100.0
        scale_grad = ~100.0 if scale_grad > ~100.0
        scale_grad = ~-100.0 if scale_grad < ~-100.0
        mean_first[i] = ~0.9*mean_first[i] + ~0.1*mean_grad
        mean_second[i] = ~0.999*mean_second[i] + ~0.001*mean_grad*mean_grad
        scale_first[i] = ~0.9*scale_first[i] + ~0.1*scale_grad
        scale_second[i] = ~0.999*scale_second[i] + ~0.001*scale_grad*scale_grad
        corrected_mean = mean_first[i] / (~1.0 - beta1_power)
        corrected_mean_square = mean_second[i] / (~1.0 - beta2_power)
        corrected_scale = scale_first[i] / (~1.0 - beta1_power)
        corrected_scale_square = scale_second[i] / (~1.0 - beta2_power)
        mean[i] = mean[i] + @learning_rate*corrected_mean / (
          Math.sqrt(corrected_mean_square) + ~1.0e-8)
        log_scales[i] = (log_scales[i] +
          @learning_rate*corrected_scale /
          (Math.sqrt(corrected_scale_square) + ~1.0e-8))
        log_scales[i] = ~20.0 if log_scales[i] > ~20.0
        log_scales[i] = ~-20.0 if log_scales[i] < ~-20.0
        i += 1
      iteration += 1
    VariationalResult.new(
      MeanFieldGaussianDistribution.new(mean, log_scales), trace)
