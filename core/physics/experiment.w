# Experimental observations and covariance-aware constant estimation.
#
# Units are observable metadata in this layer. Measurement values and standard
# uncertainties must be expressed in that common unit before constructing a
# dataset. Omitting covariance explicitly selects an independent diagonal
# model; a supplied covariance is validated as symmetric positive definite.
# This keeps the independence assumption visible at the dataset boundary.

+ Physics
  # Relative comparison for covariance entries. Unlike a general numerical
  # close predicate, this deliberately has no unit-scale absolute floor:
  # variances can be far below one in the observable's chosen unit.
  -> .covariance_close?(left, right, tolerance = ~1.0e-12)
    difference = (left - right).abs
    scale = left.abs
    scale = right.abs if right.abs > scale
    return difference == ~0.0 if scale == ~0.0
    difference <= tolerance * scale

  -> .copy_matrix(matrix)
    LinAlg.copy_mat(matrix)

  -> .copy_hash(hash)
    copy = {}
    hash.each -> (key, value)
      copy[key] = value
    copy

  # Return a validated copy. Tolerated input asymmetry is averaged before
  # any factorization, so the matrix stored and solved is exactly symmetric.
  -> .canonical_covariance(matrix, observations)
    count = observations.size
    if matrix.class_name != "Array" || matrix.size != count
      raise "covariance must have one row per observation"
    row = 0
    while row < count
      if matrix[row].class_name != "Array" || matrix[row].size != count
        raise "covariance must be square"
      column = 0
      while column < count
        if !Physics.finite_number?(matrix[row][column])
          raise "covariance entries must be finite numbers"
        column += 1
      if matrix[row][row] <= ~0.0
        raise "covariance diagonal must be positive"
      expected_variance = (
        observations[row].standard_uncertainty *
        observations[row].standard_uncertainty)
      if !Physics.finite_number?(expected_variance) || expected_variance <= ~0.0
        raise "observation variance is outside the representable covariance range"
      if !Physics.covariance_close?(matrix[row][row], expected_variance)
        raise "covariance diagonal must match observation uncertainty"
      column = 0
      while column < row
        if !Physics.covariance_close?(
          matrix[row][column], matrix[column][row])
          raise "covariance must be symmetric"
        column += 1
      row += 1
    canonical = Physics.copy_matrix(matrix)
    row = 0
    while row < count
      uncertainty = observations[row].standard_uncertainty
      canonical[row][row] = uncertainty * uncertainty
      column = 0
      while column < row
        left = canonical[row][column]
        right = canonical[column][row]
        midpoint = left + (right - left) * ~0.5
        canonical[row][column] = midpoint
        canonical[column][row] = midpoint
        column += 1
      row += 1
    canonical

  # C = D R D. Factoring the dimensionless correlation matrix avoids
  # forming inverse variances at the scale of the observable's units.
  -> .correlation_matrix(covariance, observations)
    count = observations.size
    result = LinAlg.eye(count)
    row = 0
    while row < count
      column = 0
      while column < row
        rho = (covariance[row][column] /
          observations[row].standard_uncertainty /
          observations[column].standard_uncertainty)
        if !Physics.finite_number?(rho) || rho.abs >= ~1.0
          raise "covariance must be strictly positive definite"
        result[row][column] = rho
        result[column][row] = rho
        column += 1
      row += 1
    result

  -> .validate_covariance(matrix, observations)
    canonical = Physics.canonical_covariance(matrix, observations)
    LinAlg.cholesky(Physics.correlation_matrix(canonical, observations))
    true


+ PhysicalObservable
  -> new(@name, @unit = nil, @symbol = nil, @description = nil)
    if name == nil || name.to_s.size == 0
      raise "observable name cannot be empty"

  -> name
    @name

  -> unit
    @unit

  -> symbol
    @symbol

  -> description
    @description

  -> compatible?(other)
    (other.class_name == "PhysicalObservable" &&
     name == other.name && unit == other.unit)

  -> to_s
    label = symbol == nil ? name.to_s : symbol.to_s
    return label if unit == nil
    label + " \[" + unit.to_s + "\]"

  -> inspect
    to_s


+ PhysicalObservation
  -> new(@observable, @measurement, @run_id,
         @captured_at = nil, @metadata = nil)
    if observable.class_name != "PhysicalObservable"
      raise "observation needs a PhysicalObservable"
    if measurement.class_name != "Measurement"
      raise "observation needs a Measurement"
    if run_id == nil
      raise "observation run_id cannot be nil"
    if measurement.uncertainty < ~0.0
      raise "observation uncertainty cannot be negative"
    if metadata == nil
      @metadata = {}
    elsif metadata.class_name == "Hash"
      @metadata = Physics.copy_hash(metadata)
    else
      raise "observation metadata must be a Hash"

  -> observable
    @observable

  -> measurement
    @measurement

  -> run_id
    @run_id

  -> captured_at
    @captured_at

  -> metadata
    Physics.copy_hash(@metadata)

  -> value
    measurement.value

  -> standard_uncertainty
    measurement.uncertainty

  -> unit
    observable.unit

  -> provenance
    result = measurement.provenance
    result.push("run " + run_id.to_s)
    result

  -> to_s
    observable.to_s + " = " + measurement.to_s

  -> inspect
    to_s


+ PhysicsEstimate
  -> new(@observable, @measurement, @chi_square,
         @degrees_of_freedom, @sample_size, @method,
         @covariance_source, @assumptions)

  -> observable
    @observable

  -> measurement
    @measurement

  -> value
    measurement.value

  -> uncertainty
    measurement.uncertainty

  -> standard_uncertainty
    measurement.uncertainty

  -> unit
    observable.unit

  -> chi_square
    @chi_square

  -> degrees_of_freedom
    @degrees_of_freedom

  -> sample_size
    @sample_size

  -> method
    @method

  -> covariance_source
    @covariance_source

  -> assumptions
    @assumptions.dup

  -> reduced_chi_square
    return nil if degrees_of_freedom == 0
    chi_square / (degrees_of_freedom + ~0.0)

  -> converged?
    true

  # A statistical estimate is not an exact/certified mathematical enclosure.
  -> certified?
    false

  -> to_s
    ("PhysicsEstimate(" + observable.to_s + " = " + measurement.to_s +
     ", chi2=" + chi_square.to_s + ", dof=" +
     degrees_of_freedom.to_s + ")")

  -> inspect
    to_s


+ ExperimentalDataset
  -> new(@observable, observations, covariance = nil)
    if observable.class_name != "PhysicalObservable"
      raise "dataset needs a PhysicalObservable"
    if observations.class_name != "Array" || observations.size == 0
      raise "dataset needs at least one observation"
    @observations = []
    observations.each -> (observation)
      if observation.class_name != "PhysicalObservation"
        raise "dataset entries must be PhysicalObservations"
      if !observable.compatible?(observation.observable)
        raise "dataset observations must describe the same observable and unit"
      if observation.standard_uncertainty <= ~0.0
        raise "GLS observations need positive standard uncertainty"
      @observations.each -> (previous)
        if (Measurement.same_object?(previous, observation) ||
            Measurement.same_object?(previous.measurement, observation.measurement))
          raise "dataset cannot repeat an observation or Measurement"
        if (covariance == nil &&
            previous.measurement.correlation_with(observation.measurement) != ~0.0)
          raise "correlated observations need an explicit covariance matrix"
      @observations.push(observation)

    if covariance == nil
      @covariance_source = :independent
      @covariance = ExperimentalDataset.diagonal_covariance(@observations)
    else
      @covariance_source = :supplied
      @covariance = covariance
    @covariance = Physics.canonical_covariance(@covariance, @observations)
    @cholesky = LinAlg.cholesky(
      Physics.correlation_matrix(@covariance, @observations))

  -> .diagonal_covariance(observations)
    count = observations.size
    covariance = LinAlg.zeros(count, count)
    i = 0
    while i < count
      uncertainty = observations[i].standard_uncertainty
      covariance[i][i] = uncertainty * uncertainty
      i += 1
    covariance

  -> observable
    @observable

  -> observations
    @observations.dup

  -> covariance
    Physics.copy_matrix(@covariance)

  -> covariance_source
    @covariance_source

  -> size
    @observations.size

  -> values
    result = []
    @observations.each -> (observation) result.push(observation.value)
    result

  -> standard_uncertainties
    result = []
    @observations.each -> (observation)
      result.push(observation.standard_uncertainty)
    result

  # Forward substitution in the retained Cholesky factor of R. A whitened
  # residual has squared Euclidean norm equal to its covariance chi-square.
  -> whiten(rhs)
    result = []
    i = 0
    while i < size
      value = rhs[i]
      j = 0
      while j < i
        value -= @cholesky[i][j] * result[j]
        j += 1
      value /= @cholesky[i][i]
      if !Physics.finite_number?(value)
        raise "GLS whitening exceeded numerical range"
      result.push(value)
      i += 1
    result

  # Generalized least-squares estimate of one constant shared by all rows:
  #   mu = (1^T C^-1 y)/(1^T C^-1 1), u(mu)^2 = 1/(1^T C^-1 1).
  -> gls_mean
    count = size
    uncertainty_scale = standard_uncertainties.min
    sample_values = values
    value_scale = ~0.0
    sample_values.each -> (value)
      value_scale = value.abs if value.abs > value_scale
    value_scale = ~1.0 if value_scale == ~0.0
    anchor = sample_values[0] / value_scale
    design = []
    centered = []
    i = 0
    while i < count
      weight = uncertainty_scale / @observations[i].standard_uncertainty
      design.push(weight)
      centered.push(weight * (sample_values[i] / value_scale - anchor))
      i += 1
    whitened_design = whiten(design)
    information = LinAlg.dot(whitened_design, whitened_design)
    if !Physics.finite_number?(information) || information <= ~0.0
      raise "covariance produced nonpositive information"
    correction = LinAlg.dot(whitened_design, whiten(centered)) / information
    mean = (anchor + correction) * value_scale
    result_uncertainty = uncertainty_scale / Math.sqrt(information)
    if (!Physics.finite_number?(mean) ||
        !Physics.finite_number?(result_uncertainty))
      raise "GLS constant fit produced a nonfinite estimate"

    residuals = []
    i = 0
    while i < count
      residual = sample_values[i] - mean
      uncertainty = @observations[i].standard_uncertainty
      if Physics.finite_number?(residual)
        residual /= uncertainty
      else
        residual = sample_values[i] / uncertainty - mean / uncertainty
      residuals.push(residual)
      i += 1
    whitened_residuals = whiten(residuals)
    chi_square = LinAlg.dot(whitened_residuals, whitened_residuals)
    if !Physics.finite_number?(chi_square) || chi_square < ~0.0
      raise "GLS constant fit produced an invalid chi-square"

    provenance = [
      "generalized least-squares constant fit",
      "covariance " + covariance_source.to_s
    ]
    @observations.each -> (observation)
      observation.provenance.each -> (source) provenance.push(source)

    degrees = count - 1
    result_measurement = Measurement.new(
      mean, result_uncertainty, result_uncertainty, result_uncertainty,
      ~1.0, nil, degrees, provenance)
    assumptions = [
      "one shared constant mean",
      "covariance is complete and fixed",
      "first-order Gaussian standard uncertainties"
    ]
    PhysicsEstimate.new(
      observable, result_measurement, chi_square, degrees, count,
      :generalized_least_squares, covariance_source, assumptions)

  -> fit_constant
    gls_mean
