# Metric — a symmetric covariant rank-two field with explicit signature.

+ MetricSignature
  -> new(signs)
    if signs.class_name != "Array" || signs.size == 0
      raise "metric signature needs a nonempty Array of signs"
    @signs = []
    signs.each -> (sign)
      if sign != -1 && sign != 1
        raise "metric signature entries must be -1 or 1"
      @signs.push(sign)

  -> signs
    Geometry.copy_array(@signs)

  -> dimension
    @signs.size

  -> negative_count
    count = 0
    @signs.each -> (sign) count += 1 if sign == -1
    count

  -> positive_count
    self.dimension - self.negative_count

  -> lorentzian?
    self.negative_count == 1 || self.positive_count == 1

  -> riemannian?
    self.negative_count == 0 || self.positive_count == 0

  -> to_s
    "Signature(" + self.negative_count.to_s + "," + self.positive_count.to_s + ")"

  -> inspect
    to_s


+ Metric
  -> new(@chart, components, signature = nil)
    if @chart.class_name != "Chart"
      raise "metric needs a Chart"
    if @chart.dimension > 6
      raise "symbolic metrics currently support dimensions through 6"
    @components = Geometry.wrap_tensor(components, @chart.dimension, 2)
    row = 0
    while row < @chart.dimension
      column = row + 1
      while column < @chart.dimension
        difference = Geometry.simplify_scalar(
          @components[row][column] - @components[column][row])
        if !Geometry.zero_scalar?(difference)
          raise "metric components must be symmetric"
        column += 1
      row += 1
    if signature == nil
      signs = []
      @chart.dimension.times -> signs.push(1)
      @signature = MetricSignature.new(signs)
    elsif signature.class_name == "MetricSignature"
      @signature = signature
    else
      @signature = MetricSignature.new(signature)
    if @signature.dimension != @chart.dimension
      raise "metric signature dimension does not match its chart"
    @determinant_cache = nil
    @inverse_cache = nil
    @connection_cache = nil
    @curvature_cache = nil

  -> chart
    @chart

  -> dimension
    @chart.dimension

  -> signature
    @signature

  -> components
    Geometry.deep_copy(@components)

  -> component(row, column)
    @components[row][column]

  -> [](row, column)
    component(row, column)

  -> tensor
    TensorField.new(@chart, @components, [
      TensorIndex.covariant(:mu), TensorIndex.covariant(:nu)])

  -> determinant
    if @determinant_cache == nil
      @determinant_cache = Geometry.matrix_determinant(@components)
    @determinant_cache

  -> inverse_components
    if @inverse_cache == nil
      @inverse_cache = Geometry.matrix_inverse(@components)
    Geometry.deep_copy(@inverse_cache)

  -> inverse_component(row, column)
    self.inverse_components[row][column]

  -> inverse_tensor
    TensorField.new(@chart, self.inverse_components, [
      TensorIndex.contravariant(:mu),
      TensorIndex.contravariant(:nu)])

  -> evaluate(point)
    Geometry.evaluate_tensor(@components, @chart.bindings(point))

  -> inverse_at(point)
    Geometry.evaluate_tensor(self.inverse_components, @chart.bindings(point))

  -> connection
    if @connection_cache == nil
      @connection_cache = LeviCivitaConnection.new(self)
    @connection_cache

  -> curvature
    if @curvature_cache == nil
      @curvature_cache = RiemannCurvature.new(self.connection)
    @curvature_cache

  -> geodesic_system
    GeodesicSystem.new(self)

  -> to_s
    "Metric(dim=" + self.dimension.to_s + ", " + @signature.to_s + ")"

  -> inspect
    to_s
