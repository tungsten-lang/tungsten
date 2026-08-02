# LeviCivitaConnection — torsion-free metric-compatible connection.
# Components are ordered Gamma[upper][lower][lower].  They are deliberately not
# exposed as a TensorField: connection coefficients do not transform tensorially.

+ LeviCivitaConnection
  -> new(@metric)
    if @metric.class_name != "Metric"
      raise "Levi-Civita connection needs a Metric"
    @components_cache = nil

  -> metric
    @metric

  -> chart
    @metric.chart

  -> dimension
    @metric.dimension

  -> components
    if @components_cache == nil
      dimension = self.dimension
      metric_components = @metric.components
      inverse = @metric.inverse_components
      gamma = Geometry.zero_tensor(dimension, 3)
      upper = 0
      while upper < dimension
        left = 0
        while left < dimension
          right = 0
          while right < dimension
            value = Geometry.zero
            contracted = 0
            while contracted < dimension
              term = metric_components[contracted][right].derivative(
                self.chart.coordinate_name(left))
              term += metric_components[contracted][left].derivative(
                self.chart.coordinate_name(right))
              term -= metric_components[left][right].derivative(
                self.chart.coordinate_name(contracted))
              value += Geometry.half * inverse[upper][contracted] * term
              contracted += 1
            gamma[upper][left][right] = Geometry.simplify_scalar(value)
            right += 1
          left += 1
        upper += 1
      @components_cache = gamma
    Geometry.deep_copy(@components_cache)

  -> component(upper, left, right)
    self.components[upper][left][right]

  -> [](upper, left, right)
    component(upper, left, right)

  -> evaluate(point)
    Geometry.evaluate_tensor(self.components, self.chart.bindings(point))

  -> to_s
    "LeviCivitaConnection(dim=" + self.dimension.to_s + ")"

  -> inspect
    to_s
