# RiemannCurvature — curvature derived from one Levi-Civita connection.
#
# Convention:
#   R^rho_(sigma mu nu) = d_mu Gamma^rho_(nu sigma)
#                       - d_nu Gamma^rho_(mu sigma)
#                       + Gamma^rho_(mu lambda) Gamma^lambda_(nu sigma)
#                       - Gamma^rho_(nu lambda) Gamma^lambda_(mu sigma)
#   Ricci_(sigma nu) = R^rho_(sigma rho nu)

+ RiemannCurvature
  -> new(@connection)
    if @connection.class_name != "LeviCivitaConnection"
      raise "Riemann curvature needs a LeviCivitaConnection"
    @riemann_cache = nil
    @ricci_cache = nil
    @scalar_cache = nil
    @einstein_cache = nil
    @lowered_cache = nil
    @kretschmann_cache = nil

  -> connection
    @connection

  -> metric
    @connection.metric

  -> chart
    @connection.chart

  -> dimension
    @connection.dimension

  -> riemann_components
    if @riemann_cache == nil
      dimension = self.dimension
      gamma = @connection.components
      result = Geometry.zero_tensor(dimension, 4)
      upper = 0
      while upper < dimension
        carried = 0
        while carried < dimension
          first = 0
          while first < dimension
            second = first + 1
            while second < dimension
              value = gamma[upper][second][carried].derivative(
                self.chart.coordinate_name(first))
              value -= gamma[upper][first][carried].derivative(
                self.chart.coordinate_name(second))
              contracted = 0
              while contracted < dimension
                value += gamma[upper][first][contracted] * (
                  gamma[contracted][second][carried])
                value -= gamma[upper][second][contracted] * (
                  gamma[contracted][first][carried])
                contracted += 1
              value = Geometry.simplify_scalar(value)
              result[upper][carried][first][second] = value
              result[upper][carried][second][first] = -value
              second += 1
            first += 1
          carried += 1
        upper += 1
      @riemann_cache = result
    Geometry.deep_copy(@riemann_cache)

  -> riemann_tensor
    TensorField.new(self.chart, self.riemann_components, [
      TensorIndex.contravariant(:rho),
      TensorIndex.covariant(:sigma),
      TensorIndex.covariant(:mu),
      TensorIndex.covariant(:nu)])

  -> riemann
    self.riemann_tensor

  -> ricci_components
    if @ricci_cache == nil
      dimension = self.dimension
      riemann = self.riemann_components
      result = Geometry.zero_tensor(dimension, 2)
      row = 0
      while row < dimension
        column = 0
        while column < dimension
          value = Geometry.zero
          contracted = 0
          while contracted < dimension
            value += riemann[contracted][row][contracted][column]
            contracted += 1
          result[row][column] = Geometry.simplify_scalar(value)
          column += 1
        row += 1
      @ricci_cache = result
    Geometry.deep_copy(@ricci_cache)

  -> ricci_tensor
    TensorField.new(self.chart, self.ricci_components, [
      TensorIndex.covariant(:mu), TensorIndex.covariant(:nu)])

  -> ricci
    self.ricci_tensor

  -> scalar_curvature
    if @scalar_cache == nil
      inverse = self.metric.inverse_components
      ricci = self.ricci_components
      value = Geometry.zero
      row = 0
      while row < self.dimension
        column = 0
        while column < self.dimension
          value += inverse[row][column] * ricci[row][column]
          column += 1
        row += 1
      @scalar_cache = Geometry.simplify_scalar(value)
    @scalar_cache

  -> scalar
    self.scalar_curvature

  -> einstein_components
    if @einstein_cache == nil
      metric_components = self.metric.components
      ricci = self.ricci_components
      scalar = self.scalar_curvature
      result = Geometry.zero_tensor(self.dimension, 2)
      row = 0
      while row < self.dimension
        column = 0
        while column < self.dimension
          result[row][column] = Geometry.simplify_scalar(
            ricci[row][column] - Geometry.half * (
              metric_components[row][column]) * scalar)
          column += 1
        row += 1
      @einstein_cache = result
    Geometry.deep_copy(@einstein_cache)

  -> einstein_tensor
    TensorField.new(self.chart, self.einstein_components, [
      TensorIndex.covariant(:mu), TensorIndex.covariant(:nu)])

  -> einstein
    self.einstein_tensor

  -> lowered_riemann_components
    if @lowered_cache == nil
      metric_components = self.metric.components
      mixed = self.riemann_components
      result = Geometry.zero_tensor(self.dimension, 4)
      first = 0
      while first < self.dimension
        second = 0
        while second < self.dimension
          third = 0
          while third < self.dimension
            fourth = 0
            while fourth < self.dimension
              value = Geometry.zero
              contracted = 0
              while contracted < self.dimension
                value += metric_components[first][contracted] * (
                  mixed[contracted][second][third][fourth])
                contracted += 1
              result[first][second][third][fourth] = (
                Geometry.simplify_scalar(value))
              fourth += 1
            third += 1
          second += 1
        first += 1
      @lowered_cache = result
    Geometry.deep_copy(@lowered_cache)

  -> lowered_riemann_tensor
    TensorField.new(self.chart, self.lowered_riemann_components, [
      TensorIndex.covariant(:rho),
      TensorIndex.covariant(:sigma),
      TensorIndex.covariant(:mu),
      TensorIndex.covariant(:nu)])

  # Full contraction R_abcd R^abcd.  A diagonal-metric fast path reduces the
  # contraction from eight loops to four, which covers the standard exact
  # metrics used by the initial geometry layer.
  -> kretschmann_scalar
    return @kretschmann_cache if @kretschmann_cache != nil
    metric_components = self.metric.components
    inverse = self.metric.inverse_components
    mixed = self.riemann_components
    value = Geometry.zero
    if Geometry.matrix_diagonal?(metric_components)
      first = 0
      while first < self.dimension
        second = 0
        while second < self.dimension
          third = 0
          while third < self.dimension
            fourth = 0
            while fourth < self.dimension
              component = mixed[first][second][third][fourth]
              if !Geometry.zero_scalar?(component)
                coefficient = metric_components[first][first]
                coefficient *= inverse[second][second]
                coefficient *= inverse[third][third]
                coefficient *= inverse[fourth][fourth]
                value += coefficient * component * component
              fourth += 1
            third += 1
          second += 1
        first += 1
      @kretschmann_cache = Geometry.simplify_scalar(value)
      return @kretschmann_cache

    # General metric contraction:
    # g_(ae) g^(bf) g^(cg) g^(dh) R^a_(bcd) R^e_(fgh).
    a = 0
    while a < self.dimension
      b = 0
      while b < self.dimension
        c = 0
        while c < self.dimension
          d = 0
          while d < self.dimension
            left = mixed[a][b][c][d]
            if !Geometry.zero_scalar?(left)
              e = 0
              while e < self.dimension
                f = 0
                while f < self.dimension
                  g = 0
                  while g < self.dimension
                    h = 0
                    while h < self.dimension
                      right = mixed[e][f][g][h]
                      if !Geometry.zero_scalar?(right)
                        coefficient = metric_components[a][e]
                        coefficient *= inverse[b][f]
                        coefficient *= inverse[c][g]
                        coefficient *= inverse[d][h]
                        if !Geometry.zero_scalar?(coefficient)
                          value += coefficient * left * right
                      h += 1
                    g += 1
                  f += 1
                e += 1
            d += 1
          c += 1
        b += 1
      a += 1
    @kretschmann_cache = Geometry.simplify_scalar(value)
    @kretschmann_cache

  -> evaluate(point)
    bindings = self.chart.bindings(point)
    {
      riemann: Geometry.evaluate_tensor(self.riemann_components, bindings),
      ricci: Geometry.evaluate_tensor(self.ricci_components, bindings),
      scalar: self.scalar_curvature.evaluate(bindings),
      einstein: Geometry.evaluate_tensor(self.einstein_components, bindings)
    }

  -> to_s
    "RiemannCurvature(dim=" + self.dimension.to_s + ")"

  -> inspect
    to_s
