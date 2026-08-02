# Finite mixtures of distributions with a common measure type.

use core/math
use core/probability/distribution
use core/probability/primitives
use core/probability/sampling
use core/probability/support

+ MixtureDistribution < ProbabilityDistribution
  -> new(components, weights)
    if components.class_name != "Array" || components.size == 0
      raise "probability mixture components must be a nonempty Array"
    if weights.class_name != "Array" || weights.size != components.size
      raise "probability mixture weights must match components"
    @components = ProbabilityNumerics.copy_array(components)
    @weights = ProbabilityNumerics.normalized_weights(
      weights, "mixture weights")
    @discrete = @components[0].discrete?
    supports = []
    i = 0
    while i < @components.size
      if !@components[i].respond_to?("probability") || (
         @components[i].discrete? != @discrete)
        raise "probability mixture components must share one measure type"
      supports.push(@components[i].support)
      i += 1
    @support = ProbabilityUnionSupport.new(supports)
    self

  -> components
    ProbabilityNumerics.copy_array(@components)

  -> weights
    ProbabilityNumerics.copy_array(@weights)

  -> component_count
    @components.size

  -> discrete?
    @discrete

  -> support
    @support

  -> pdf(value)
    if @discrete
      raise "pdf is not defined for a discrete probability mixture"
    total = ~0.0
    i = 0
    while i < @components.size
      total += @weights[i]*@components[i].pdf(value)
      i += 1
    total

  -> pmf(value)
    if !@discrete
      raise "pmf is not defined for a continuous probability mixture"
    total = ~0.0
    i = 0
    while i < @components.size
      total += @weights[i]*@components[i].pmf(value)
      i += 1
    total

  -> log_probability(value)
    terms = []
    i = 0
    while i < @components.size
      term = ProbabilityNumerics.negative_infinity
      if @weights[i] > ~0.0
        term = Math.log(@weights[i]) + @components[i].log_prob(value)
      terms.push(term)
      i += 1
    ProbabilityNumerics.logsumexp(terms)

  -> cdf(value)
    total = ~0.0
    i = 0
    while i < @components.size
      total += @weights[i]*@components[i].cdf(value)
      i += 1
    total

  -> mean
    total = ~0.0
    i = 0
    while i < @components.size
      total += @weights[i]*@components[i].mean
      i += 1
    total

  -> variance
    center = mean
    total = ~0.0
    i = 0
    while i < @components.size
      component_mean = @components[i].mean
      offset = component_mean - center
      total += @weights[i]*(@components[i].variance + offset*offset)
      i += 1
    total

  -> sample(rng = nil)
    index = ProbabilitySampling.categorical_index(@weights, rng)
    @components[index].sample(rng)

  -> to_s
    ("Mixture(components=" + @components.size.to_s +
     ", weights=" + @weights.to_s + ")")
