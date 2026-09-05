# Coordinate-wise derivatives of opaque scalar/vector f64 callbacks.

+ NumericalArrayResult
  -> new(components, @rank, @evaluations)
    if @rank != 1 && @rank != 2
      raise "numerical array result rank must be one or two"
    @components = @rank == 1 ? Calculus.copy_vector(components) : Calculus.copy_matrix(components)
    if !Calculus.integer?(@evaluations) || @evaluations < 0
      raise "numerical array evaluation count must be nonnegative"
    if @rank == 2 && @components.size > 0
      width = @components[0].size
      @components.each ->
        raise "numerical array result rows must have equal lengths" if item.size != width
    @status = :converged
    @available = true
    flat = []
    if @rank == 1
      flat = @components
    else
      @components.each -> (row)
        row.each -> (component) flat.push(component)
    flat.each ->
      if item.class_name != "NumericalDerivativeResult"
        raise "numerical array components must be derivative results"
      @available = false if !item.estimate_available?
      @status = item.status if @status == :converged && !item.converged?

  -> component_results
    @rank == 1 ? Calculus.copy_vector(@components) : Calculus.copy_matrix(@components)
  -> status
    @status
  -> evaluations
    @evaluations
  -> rank
    @rank
  -> converged?
    @status == :converged
  -> estimate_available?
    @available
  -> certified?
    false
  -> value
    return nil if !@available
    if @rank == 1
      return @components.map -> item.value
    @components.map -> (row)
      row.map -> (component) component.value
  -> error_estimate
    return nil if !@available
    if @rank == 1
      return @components.map -> item.error_estimate
    @components.map -> (row)
      row.map -> (component) component.error_estimate
  -> to_s
    "NumericalArrayResult(" + @status.to_s + ", evaluations=" + @evaluations.to_s + ")"

+ Calculus
  -> .validate_f64_point(point)
    if point.class_name != "Array"
      raise "numerical point must be an Array"
    point.each ->
      raise "numerical point entries must be finite f64" if !Calculus.finite_f64?(item)
    point

  -> .numerical_gradient(f, point, scheme = :central, initial_step = nil,
                         abs_tol = ~1.0e-10, rel_tol = ~1.0e-8,
                         max_levels = 10)
    Calculus.validate_f64_point(point)
    Calculus.numerical_initial_step(~0.0, 1, scheme, initial_step,
      abs_tol, rel_tol, max_levels, ~1.4, 64)
    base = Calculus.copy_vector(point)
    components = []
    evaluations = 0
    i = 0
    while i < base.size
      coordinate = i
      scalar = -> (x)
        probe = Calculus.copy_vector(base)
        probe[coordinate] = x
        f(probe)
      result = Calculus.numerical_derivative(scalar, base[i], 1,
        scheme, initial_step, abs_tol, rel_tol, max_levels)
      components.push(result)
      evaluations += result.evaluations
      i += 1
    NumericalArrayResult.new(components, 1, evaluations)

  -> .numerical_jacobian(f, point, scheme = :central, initial_step = nil,
                         abs_tol = ~1.0e-10, rel_tol = ~1.0e-8,
                         max_levels = 10)
    Calculus.validate_f64_point(point)
    Calculus.numerical_initial_step(~0.0, 1, scheme, initial_step,
      abs_tol, rel_tol, max_levels, ~1.4, 64)
    base = Calculus.copy_vector(point)
    initial = f(Calculus.copy_vector(base))
    if initial.class_name != "Array"
      raise "numerical jacobian callback must return an Array"
    output_size = initial.size
    rows = []
    output_size.times -> rows.push([])
    counts = [1]
    i = 0
    while i < base.size
      coordinate = i
      # Each coordinate sample is shared across all output components.
      cache = {}
      cache[base[i]] = Calculus.copy_vector(initial)
      j = 0
      while j < output_size
        output = j
        scalar = -> (x)
          values = cache[x]
          if values == nil
            probe = Calculus.copy_vector(base)
            probe[coordinate] = x
            values = f(probe)
            counts[0] += 1
            if values.class_name != "Array" || values.size != output_size
              raise "numerical jacobian callback output shape changed"
            values = Calculus.copy_vector(values)
            cache[x] = values
          values[output]
        result = Calculus.numerical_derivative(scalar, base[i], 1,
          scheme, initial_step, abs_tol, rel_tol, max_levels)
        rows[j].push(result)
        j += 1
      i += 1
    NumericalArrayResult.new(rows, 2, counts[0])
