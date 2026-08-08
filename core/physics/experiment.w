# Experimental observations and covariance-aware constant estimation.
#
# Units are observable metadata in this layer. Measurement values and standard
# uncertainties must be expressed in that common unit before constructing a
# dataset. Omitting covariance explicitly selects an independent diagonal
# model; a supplied covariance is validated as symmetric positive definite.
# This keeps the independence assumption visible at the dataset boundary.

+ Physics
  -> .finite_number?(value)
    Measurement.finite_number?(value)

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

  -> .validate_covariance(matrix, observations)
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
      if !Physics.covariance_close?(matrix[row][row], expected_variance)
        raise "covariance diagonal must match observation uncertainty"
      column = 0
      while column < row
        if !Physics.covariance_close?(
          matrix[row][column], matrix[column][row])
          raise "covariance must be symmetric"
        column += 1
      row += 1
    # Cholesky is both the current positive-definiteness gate and a loud
    # failure for exactly singular correlation models.
    LinAlg.cholesky(matrix)
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
    label + " [" + unit.to_s + "]"

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
      @observations.push(observation)

    if covariance == nil
      @covariance_source = :independent
      @covariance = ExperimentalDataset.diagonal_covariance(@observations)
    else
      @covariance_source = :supplied
      @covariance = Physics.copy_matrix(covariance)
    Physics.validate_covariance(@covariance, @observations)

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

  # Generalized least-squares estimate of one constant shared by all rows:
  #   mu = (1^T C^-1 y)/(1^T C^-1 1), u(mu)^2 = 1/(1^T C^-1 1).
  -> gls_mean
    count = size
    ones = []
    count.times -> ones.push(~1.0)
    weights = LinAlg.solve(@covariance, ones)
    information = LinAlg.dot(ones, weights)
    if !Physics.finite_number?(information) || information <= ~0.0
      raise "covariance produced nonpositive information"
    mean = LinAlg.dot(weights, values) / information
    result_uncertainty = Math.sqrt(~1.0 / information)
    if (!Physics.finite_number?(mean) ||
        !Physics.finite_number?(result_uncertainty))
      raise "GLS constant fit produced a nonfinite estimate"

    residuals = []
    values.each -> (value) residuals.push(value - mean)
    solved_residuals = LinAlg.solve(@covariance, residuals)
    chi_square = LinAlg.dot(residuals, solved_residuals)
    chi_square = ~0.0 if chi_square < ~0.0 && chi_square > ~-1.0e-12
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
