# Solver-independent diagnostics for finite-volume calculations.
#
# These routines measure output arrays; they do not prove TVD, convergence,
# conservation, or stability of a numerical scheme. In particular,
# `cfl_contract?` checks a caller-supplied method-specific bound rather than
# deriving a stable CFL limit.

+ FiniteVolumeDiagnostics
  -> .finite_number?(value)
    name = value.class_name
    numeric = name == "Float" || name == "Integer"
    numeric = true if name == "BigInt" || name == "Decimal"
    return false if !numeric
    number = value.to_f()
    !number.nan? && !number.infinite?

  -> .validate_finite(value, label)
    if !FiniteVolumeDiagnostics.finite_number?(value)
      raise label + " must be a finite number"
    true

  -> .validate_values(values, label)
    if values.class_name != "Array" || values.size == 0
      raise label + " must be a nonempty Array"
    i = 0
    while i < values.size
      validate_finite(values[i], label + " entry")
      i += 1
    true

  -> .validate_pair(values, reference)
    validate_values(values, "values")
    validate_values(reference, "reference")
    if values.size != reference.size
      raise "diagnostic arrays must have the same size"
    true

  -> .validate_cell_width(cell_width)
    validate_finite(cell_width, "cell width")
    raise "cell width must be positive" if cell_width <= ~0.0
    true

  # Sum of adjacent jumps. Periodic mode also includes the closing jump.
  -> .total_variation(values, periodic = false)
    validate_values(values, "values")
    variation = ~0.0
    i = 1
    while i < values.size
      variation += (values[i] - values[i - 1]).abs
      i += 1
    if periodic && values.size > 1
      variation += (values[0] - values[values.size - 1]).abs
    variation

  -> .tvd?(before, after, tolerance = ~1.0e-12, periodic = false)
    validate_finite(tolerance, "TVD tolerance")
    raise "TVD tolerance cannot be negative" if tolerance < ~0.0
    before_tv = total_variation(before, periodic)
    after_tv = total_variation(after, periodic)
    scale = before_tv
    scale = ~1.0 if scale < ~1.0
    after_tv <= before_tv + tolerance * scale

  -> .l1_error(values, reference, cell_width = ~1.0)
    validate_pair(values, reference)
    validate_cell_width(cell_width)
    total = ~0.0
    i = 0
    while i < values.size
      total += (values[i] - reference[i]).abs
      i += 1
    total * cell_width

  -> .l2_error(values, reference, cell_width = ~1.0)
    validate_pair(values, reference)
    validate_cell_width(cell_width)
    total = ~0.0
    i = 0
    while i < values.size
      difference = values[i] - reference[i]
      total += difference * difference
      i += 1
    Math.sqrt(total * cell_width)

  -> .linf_error(values, reference)
    validate_pair(values, reference)
    maximum = ~0.0
    i = 0
    while i < values.size
      difference = (values[i] - reference[i]).abs
      maximum = difference if difference > maximum
      i += 1
    maximum

  -> .l2_norm(values, cell_width = ~1.0)
    validate_values(values, "values")
    validate_cell_width(cell_width)
    total = ~0.0
    i = 0
    while i < values.size
      total += values[i] * values[i]
      i += 1
    Math.sqrt(total * cell_width)

  # Quadratic cell-average entropy integral for scalar Burgers diagnostics.
  -> .quadratic_entropy(values, cell_width = ~1.0)
    validate_values(values, "values")
    validate_cell_width(cell_width)
    total = ~0.0
    i = 0
    while i < values.size
      total += ~0.5 * values[i] * values[i]
      i += 1
    total * cell_width

  -> .nonincreasing?(before, after, tolerance = ~1.0e-12)
    validate_finite(before, "initial value")
    validate_finite(after, "current value")
    validate_finite(tolerance, "comparison tolerance")
    raise "comparison tolerance cannot be negative" if tolerance < ~0.0
    scale = before.abs
    scale = ~1.0 if scale < ~1.0
    after <= before + tolerance * scale

  # p = log(E_h / E_(h/r)) / log(r).
  -> .observed_order(coarse_error, fine_error, refinement_ratio = ~2.0)
    validate_finite(coarse_error, "coarse error")
    validate_finite(fine_error, "fine error")
    validate_finite(refinement_ratio, "refinement ratio")
    if coarse_error <= ~0.0 || fine_error <= ~0.0
      raise "observed order needs positive errors"
    if refinement_ratio <= ~1.0
      raise "refinement ratio must exceed one"
    (Math.log(coarse_error / fine_error) /
     Math.log(refinement_ratio))

  -> .conservation_drift(initial_totals, current_totals)
    validate_pair(initial_totals, current_totals)
    drift = []
    i = 0
    while i < initial_totals.size
      drift.push(current_totals[i] - initial_totals[i])
      i += 1
    drift

  -> .relative_conservation_drift(initial_totals, current_totals,
                                  normalization_floor = ~1.0e-30)
    validate_pair(initial_totals, current_totals)
    validate_finite(normalization_floor, "normalization floor")
    if normalization_floor <= ~0.0
      raise "normalization floor must be positive"
    drift = []
    i = 0
    while i < initial_totals.size
      scale = initial_totals[i].abs
      scale = normalization_floor if scale < normalization_floor
      drift.push((current_totals[i] - initial_totals[i]) / scale)
      i += 1
    drift

  # Only validates a supplied contract. The caller remains responsible for
  # choosing the bound appropriate to its flux, limiter, and time integrator.
  -> .cfl_contract?(courant_number, maximum_allowed, tolerance = ~0.0)
    validate_finite(courant_number, "Courant number")
    validate_finite(maximum_allowed, "maximum CFL")
    validate_finite(tolerance, "CFL tolerance")
    if maximum_allowed <= ~0.0
      raise "maximum CFL must be positive"
    raise "CFL tolerance cannot be negative" if tolerance < ~0.0
    (courant_number >= ~0.0 &&
     courant_number <= maximum_allowed + tolerance)
