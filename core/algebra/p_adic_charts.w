# Recursive exact p-adic cells for rational plane curves.
#
# Fixing one projective coordinate to one identifies a cell with
#
#   x_i = c_i + p^d u_i.
#
# Substitution into the source equation, removal of the exact common
# p-power, and reduction modulo p produce the strict-transform equation for
# the next digits. Its complete F_p point set partitions every p-adic
# solution in the cell. Smooth points are Hensel disks; singular points can
# be refined again. The finite arithmetic is replayed exactly, while the
# cover interpretation is an explicitly named p-adic cell-decomposition
# theorem import.

+ PadicPlaneCurveCellArithmetic
  -> .integer?(value)
    kind = value.class_name
    return true if kind == "Integer"
    return true if kind == "Int"
    kind == "BigInt"

  -> .valuation(value, prime)
    PadicField.new(prime, 4).coerce(value).valuation

  -> .chart_polynomial(
       curve, pivot_index, center_coordinates,
       prime, depth)
    ring = PolynomialRing.new(
      [:u, :v], RationalField.new, :grevlex)
    local_indices = []
    index = 0
    while index < center_coordinates.size
      local_indices.push(index) if index != pivot_index
      index += 1
    if local_indices.size != 2
      raise "p-adic plane cell needs two affine coordinates"
    step = prime**depth
    substitutions = []
    local_index = 0
    index = 0
    while index < center_coordinates.size
      if index == pivot_index
        substitutions.push(ring.one)
      else
        substitutions.push(
          ring.constant(center_coordinates[index]) +
          ring.generator(local_index)*step)
        local_index += 1
      index += 1
    result = ring.zero
    curve.equation.each_term -> (coefficient, exponents)
      term = ring.constant(coefficient)
      index = 0
      while index < exponents.size
        term *= substitutions[index]**exponents[index]
        index += 1
      result += term
    [result, local_indices]

  -> .primitive_at_prime(polynomial, prime)
    if polynomial.zero?
      raise "p-adic cell substitution annihilated the curve equation"
    minimum = nil
    polynomial.each_term -> (coefficient, exponents)
      valuation = PadicPlaneCurveCellArithmetic.valuation(
        coefficient, prime)
      minimum = valuation if (
        minimum == nil || valuation < minimum)
    if minimum == nil
      raise "p-adic cell polynomial has no terms"
    power = nil
    if minimum < 0
      power = Rational.new(1, prime**(0 - minimum))
    else
      power = prime**minimum
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      terms.push([
        coefficient / power,
        exponents
      ])
    [Polynomial.new(polynomial.ring, terms), minimum]

  -> .reduce_polynomial(polynomial, prime)
    field = FiniteField.new(prime)
    ring = PolynomialRing.new(
      polynomial.ring.names, field,
      polynomial.ring.order)
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      reduced = field.coerce(coefficient)
      if !field.zero?(reduced)
        terms.push([reduced, exponents])
    reduced = Polynomial.new(ring, terms)
    if reduced.zero?
      raise "p-adic primitive cell equation vanished modulo p"
    reduced

  -> .residue_points(polynomial)
    field = polynomial.ring.field
    if (field.class_name != "FiniteField" ||
        !field.prime_field?)
      raise "p-adic cell residue scan needs a prime field"
    points = []
    first = 0
    while first < field.order
      second = 0
      while second < field.order
        coordinates = [first, second]
        if field.zero?(
             polynomial.evaluate_raw(coordinates))
          points.push(coordinates)
        second += 1
      first += 1
    points

  -> .smooth?(polynomial, coordinates)
    field = polynomial.ring.field
    index = 0
    while index < 2
      value = polynomial.derivative(index).evaluate_raw(
        coordinates)
      return true if !field.zero?(value)
      index += 1
    false


+ PadicPlaneCurveCellCertificate
  -> new(@cell)
    @verified_cache = nil

  -> theorem
    "primitive affine substitution gives the exact next-digit equation in a p-adic plane-curve cell"

  -> theorem_reference
    "p-adic cell decomposition and multivariate Hensel lemma"

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @cell.class_name != "PadicPlaneCurveCell"
    curve = @cell.curve
    return false if curve.class_name != "Curve"
    return false if curve.field.class_name != "RationalField"
    return false if curve.space.coordinate_count != 3
    prime = @cell.prime
    return false if !prime.prime?
    depth = @cell.depth
    return false if depth < 1
    return false if @cell.step != prime**depth
    pivot = @cell.pivot_coordinate_index
    return false if pivot < 0 || pivot >= 3
    coordinates = @cell.center_coordinates
    return false if coordinates.size != 3
    return false if coordinates[pivot] != 1
    index = 0
    while index < coordinates.size
      return false if !PadicPlaneCurveCellArithmetic.integer?(
        coordinates[index])
      if index != pivot
        return false if coordinates[index] < 0
        return false if coordinates[index] >= @cell.step
      index += 1

    data = PadicPlaneCurveCellArithmetic.chart_polynomial(
      curve, pivot, coordinates, prime, depth)
    return false if data[0] != @cell.raw_polynomial
    return false if data[1].to_s != (
      @cell.local_coordinate_indices.to_s)
    primitive = PadicPlaneCurveCellArithmetic.primitive_at_prime(
      data[0], prime)
    return false if primitive[0] != @cell.primitive_polynomial
    return false if primitive[1] != @cell.content_valuation
    reduced = PadicPlaneCurveCellArithmetic.reduce_polynomial(
      primitive[0], prime)
    return false if reduced != @cell.reduction_polynomial
    points = PadicPlaneCurveCellArithmetic.residue_points(
      reduced)
    return false if points.to_s != @cell.residue_points.to_s
    smooth = []
    singular = []
    points.each -> (point)
      if PadicPlaneCurveCellArithmetic.smooth?(
           reduced, point)
        smooth.push(point)
      else
        singular.push(point)
    return false if smooth.to_s != @cell.smooth_residue_points.to_s
    return false if singular.to_s != (
      @cell.singular_residue_points.to_s)
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_p_adic_cell_with_exact_substitution

  -> kernel_checked?
    false

  -> substitution_kernel_checked?
    true

  -> arithmetic_replay_checked?
    true

  -> finite_residue_scan_replayed?
    true

  -> complete_next_digit_cover_checked?
    verified?


+ PadicPlaneCurveCell
  -> new(@curve, @prime, center_coordinates,
         @pivot_coordinate_index = nil, @depth = 1)
    if @curve.class_name != "Curve"
      raise "p-adic plane cell needs a Curve"
    if @curve.field.class_name != "RationalField"
      raise "p-adic plane cell currently needs a rational curve"
    if @curve.space.coordinate_count != 3
      raise "p-adic plane cell needs a projective plane curve"
    if !@prime.prime?
      raise "p-adic plane cell needs a prime"
    if @depth < 1
      raise "p-adic plane cell depth must be positive"
    if (center_coordinates.class_name != "Array" ||
        center_coordinates.size != 3)
      raise "p-adic plane cell needs three center coordinates"
    @center_coordinates = []
    center_coordinates.each -> (coordinate)
      if !PadicPlaneCurveCellArithmetic.integer?(coordinate)
        raise "p-adic plane cell centers must be integral"
      @center_coordinates.push(coordinate)
    if @pivot_coordinate_index == nil
      @pivot_coordinate_index = 0
      while (@pivot_coordinate_index < 3 &&
             @center_coordinates[
               @pivot_coordinate_index] != 1)
        @pivot_coordinate_index += 1
      if @pivot_coordinate_index == 3
        raise "p-adic plane cell needs a center coordinate equal to one"
    if (@pivot_coordinate_index < 0 ||
        @pivot_coordinate_index >= 3)
      raise "p-adic plane cell pivot is out of range"
    if @center_coordinates[@pivot_coordinate_index] != 1
      raise "p-adic plane cell pivot coordinate must equal one"
    @step = @prime**@depth
    index = 0
    while index < @center_coordinates.size
      if index != @pivot_coordinate_index
        if (@center_coordinates[index] < 0 ||
            @center_coordinates[index] >= @step)
          raise "p-adic plane cell center is not canonical at its depth"
      index += 1

    data = PadicPlaneCurveCellArithmetic.chart_polynomial(
      @curve, @pivot_coordinate_index,
      @center_coordinates, @prime, @depth)
    @raw_polynomial = data[0]
    @local_coordinate_indices = data[1]
    primitive = PadicPlaneCurveCellArithmetic.primitive_at_prime(
      @raw_polynomial, @prime)
    @primitive_polynomial = primitive[0]
    @content_valuation = primitive[1]
    @reduction_polynomial = (
      PadicPlaneCurveCellArithmetic.reduce_polynomial(
        @primitive_polynomial, @prime))
    @residue_points = (
      PadicPlaneCurveCellArithmetic.residue_points(
        @reduction_polynomial))
    @smooth_residue_points = []
    @singular_residue_points = []
    @residue_points.each -> (point)
      if PadicPlaneCurveCellArithmetic.smooth?(
           @reduction_polynomial, point)
        @smooth_residue_points.push(point)
      else
        @singular_residue_points.push(point)
    @certificate_cache = PadicPlaneCurveCellCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "p-adic plane cell failed certification"

  -> curve
    @curve

  -> prime
    @prime

  -> depth
    @depth

  -> step
    @step

  -> pivot_coordinate_index
    @pivot_coordinate_index

  -> local_coordinate_indices
    out = []
    @local_coordinate_indices.each -> out.push(item)
    out

  -> center_coordinates
    out = []
    @center_coordinates.each -> out.push(item)
    out

  -> raw_polynomial
    @raw_polynomial

  -> primitive_polynomial
    @primitive_polynomial

  -> content_valuation
    @content_valuation

  -> reduction_polynomial
    @reduction_polynomial

  -> residue_points
    out = []
    @residue_points.each -> (point)
      out.push([point[0], point[1]])
    out

  -> smooth_residue_points
    out = []
    @smooth_residue_points.each -> (point)
      out.push([point[0], point[1]])
    out

  -> singular_residue_points
    out = []
    @singular_residue_points.each -> (point)
      out.push([point[0], point[1]])
    out

  -> residue_point_count
    @residue_points.size

  -> smooth_residue_point_count
    @smooth_residue_points.size

  -> singular_residue_point_count
    @singular_residue_points.size

  -> empty?
    @residue_points.size == 0

  -> reduction_smooth?(point)
    PadicPlaneCurveCellArithmetic.smooth?(
      @reduction_polynomial, point)

  -> child(point)
    if point.class_name != "Array" || point.size != 2
      raise "p-adic plane child needs two residue coordinates"
    found = @residue_points.any? -> (candidate)
      candidate.to_s == point.to_s
    if !found
      raise "p-adic plane child is not on the reduced cell"
    coordinates = center_coordinates
    local_index = 0
    @local_coordinate_indices.each -> (coordinate_index)
      digit = point[local_index]
      if digit < 0 || digit >= @prime
        raise "p-adic plane child digit is out of range"
      coordinates[coordinate_index] += digit*@step
      local_index += 1
    PadicPlaneCurveCell.new(
      @curve, @prime, coordinates,
      @pivot_coordinate_index, @depth + 1)

  -> refine
    PadicPlaneCurveCellRefinement.new(self)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    ("p-adic plane cell p=" + @prime.to_s +
     " depth=" + @depth.to_s +
     " center=" + @center_coordinates.to_s)

  -> inspect
    to_s


+ PadicPlaneCurveCellRefinementCertificate
  -> new(@refinement)
    @verified_cache = nil

  -> theorem
    "the reduced strict-transform points partition all next p-adic digits in a plane-curve cell"

  -> theorem_reference
    "p-adic digit decomposition and multivariate Hensel lemma"

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    expected = "PadicPlaneCurveCellRefinement"
    return false if @refinement.class_name != expected
    parent = @refinement.parent
    return false if !parent.certificate.verified?
    points = parent.residue_points
    entries = @refinement.entries
    return false if entries.size != points.size
    index = 0
    while index < entries.size
      entry = entries[index]
      return false if entry.size != 3
      point = entry[0]
      return false if point.to_s != points[index].to_s
      smooth = parent.reduction_smooth?(point)
      return false if entry[1] != smooth
      child = entry[2]
      return false if child.class_name != "PadicPlaneCurveCell"
      return false if !child.certificate.verified?
      expected_child = parent.child(point)
      return false if child.center_coordinates.to_s != (
        expected_child.center_coordinates.to_s)
      return false if child.depth != parent.depth + 1
      return false if child.prime != parent.prime
      return false if child.curve != parent.curve
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_complete_p_adic_digit_partition

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> finite_partition_replayed?
    true

  -> complete_cover_checked?
    verified?


+ PadicPlaneCurveCellRefinement
  -> new(@parent)
    if @parent.class_name != "PadicPlaneCurveCell"
      raise "p-adic cell refinement needs a plane cell"
    if !@parent.certificate.verified?
      raise "p-adic cell refinement parent is uncertified"
    @entries = []
    @parent.residue_points.each -> (point)
      @entries.push([
        point,
        @parent.reduction_smooth?(point),
        @parent.child(point)
      ])
    @certificate_cache = (
      PadicPlaneCurveCellRefinementCertificate.new(self))
    if !@certificate_cache.verified?
      raise "p-adic plane-cell refinement failed certification"

  -> parent
    @parent

  -> entries
    out = []
    @entries.each -> (entry)
      out.push([
        [entry[0][0], entry[0][1]],
        entry[1], entry[2]
      ])
    out

  -> children
    out = []
    @entries.each -> out.push(item[2])
    out

  -> smooth_children
    out = []
    @entries.each ->
      out.push(item[2]) if item[1]
    out

  -> smooth_disks
    out = []
    @entries.each -> (entry)
      if entry[1]
        out.push(PadicPlaneCurveHenselDisk.new(
          @parent, entry[0], entry[2]))
    out

  -> singular_children
    out = []
    @entries.each ->
      out.push(item[2]) if !item[1]
    out

  -> smooth_branch_count
    smooth_children.size

  -> singular_branch_count
    singular_children.size

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PadicPlaneCurveHenselDiskCertificate
  -> new(@disk)
    @verified_cache = nil

  -> theorem
    "a smooth reduced point of a primitive p-adic plane cell lifts to a nonempty one-dimensional residue disk"

  -> theorem_reference
    "multivariate Hensel lemma"

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @disk.class_name != "PadicPlaneCurveHenselDisk"
    parent = @disk.parent_cell
    return false if !parent.certificate.verified?
    point = @disk.residue_point
    found = parent.smooth_residue_points.any? -> (candidate)
      candidate.to_s == point.to_s
    return false if !found
    return false if !parent.reduction_smooth?(point)
    child = @disk.child_cell
    return false if !child.certificate.verified?
    expected = parent.child(point)
    return false if child.center_coordinates.to_s != (
      expected.center_coordinates.to_s)
    return false if child.depth != parent.depth + 1
    return false if @disk.depth != child.depth
    return false if @disk.step != child.step
    return false if @disk.center_coordinates.to_s != (
      child.center_coordinates.to_s)
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_multivariate_hensel_disk

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> nonempty_disk_checked?
    verified?


+ PadicPlaneCurveHenselDisk
  -> new(@parent_cell, residue_point,
         child_cell = nil)
    if @parent_cell.class_name != "PadicPlaneCurveCell"
      raise "p-adic Hensel disk needs a plane cell"
    if !@parent_cell.certificate.verified?
      raise "p-adic Hensel disk parent is uncertified"
    if (residue_point.class_name != "Array" ||
        residue_point.size != 2)
      raise "p-adic Hensel disk needs a reduced point"
    @residue_point = [
      residue_point[0], residue_point[1]]
    if !@parent_cell.reduction_smooth?(@residue_point)
      raise "p-adic Hensel disk needs a smooth reduced point"
    @child_cell = child_cell
    if @child_cell == nil
      @child_cell = @parent_cell.child(
        @residue_point)
    @certificate_cache = (
      PadicPlaneCurveHenselDiskCertificate.new(self))
    if !@certificate_cache.verified?
      raise "p-adic plane Hensel disk failed certification"

  -> parent_cell
    @parent_cell

  -> child_cell
    @child_cell

  -> curve
    @parent_cell.curve

  -> prime
    @parent_cell.prime

  -> residue_point
    [@residue_point[0], @residue_point[1]]

  -> pivot_coordinate_index
    @parent_cell.pivot_coordinate_index

  -> local_coordinate_indices
    @parent_cell.local_coordinate_indices

  -> center_coordinates
    @child_cell.center_coordinates

  -> depth
    @child_cell.depth

  -> step
    @child_cell.step

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> subdisk(residue_point)
    PadicPlaneCurveHenselDisk.new(
      @child_cell, residue_point)

  -> refine
    @child_cell.refine.smooth_disks

  -> to_s
    ("Q_" + prime.to_s +
     " Hensel disk at " +
     center_coordinates.to_s +
     " mod " + step.to_s)

  -> inspect
    to_s


+ Curve
  -> p_adic_cell(prime, center_coordinates,
                  pivot_coordinate_index = nil,
                  depth = 1)
    PadicPlaneCurveCell.new(
      self, prime, center_coordinates,
      pivot_coordinate_index, depth)


+ PadicCurveSmoothResidueDiskCover
  -> singular_cells
    out = []
    @singular_points.each -> (point)
      pivot = 0
      coordinates = point.coordinates
      while coordinates[pivot] == 0
        pivot += 1
      out.push(PadicPlaneCurveCell.new(
        @curve, @prime, coordinates,
        pivot, 1))
    out
