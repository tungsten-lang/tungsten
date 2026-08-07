# Exact one-parameter orbits in a flat torus.
#
# For integer generators v = (v_1, ..., v_n), FlatTorusOrbit models
#
#   t |-> (v_1 t, ..., v_n t) mod Z^n.
#
# The minimum coordinate distance to Z is the Lonely Runner objective.  It is
# a lower envelope of triangular waves.  Its maximum occurs at an apex of one
# wave or at an intersection of two affine pieces.  Those event times satisfy
#
#   2 v_i t in Z,  (v_i - v_j)t in Z, or (v_i + v_j)t in Z,
#
# so the exact finite event sweep below loses no extrema.  The implementation
# is intended for exact low- and medium-height investigations; its event count
# grows with the generator heights and it is not a replacement for lattice or
# sieve methods on very large inputs.

+ FlatTorusOrbitExtremum
  -> new(@value, @times)
    @times = @times.dup

  ro :value
  ro :times

  -> witness_time
    @times[0]


# An exact GL(n,Z) coordinate change which sends an integer torus direction
# to its gcd times the first coordinate vector.  For a primitive direction v,
#
#   U v = e_1,  U in SL(n,Z).
#
# Thus an integer FlatTorusOrbit is a single coordinate circle in a different
# integral chart.  This does not make the Lonely Runner target axis-aligned:
# the inverse image of the coordinate cube is skewed by U^-1.  Keeping both
# matrices explicit prevents that geometric reformulation from being mistaken
# for a proof that the coordinate constraints have disappeared.
+ FlatTorusOrbitStraightening
  -> new(generators)
    if generators.class_name != "Array" || generators.size == 0
      raise "flat torus straightening needs a nonempty integer direction"
    @source = []
    generators.each -> (generator)
      integer = generator.class_name == "Integer" || generator.class_name == "Int"
      raise "flat torus straightening needs integer coordinates" if !integer
      @source.push(generator)

    @matrix = integer_identity(@source.size)
    @inverse = integer_identity(@source.size)
    working = @source.dup
    pivot = working[0]
    index = 1
    while index < working.size
      other = working[index]
      bezout = extended_gcd(pivot, other)
      divisor = bezout[0]
      left = bezout[1]
      right = bezout[2]
      if divisor != 0
        first_row = @matrix[0].dup
        second_row = @matrix[index].dup
        column = 0
        while column < first_row.size
          first_value = left*first_row[column]
          first_value += right*second_row[column]
          second_value = (0 - other / divisor)*first_row[column]
          second_value += (pivot / divisor)*second_row[column]
          @matrix[0][column] = first_value
          @matrix[index][column] = second_value
          column += 1
        # U_new = E U, so U_new^-1 = U^-1 E^-1.
        row = 0
        while row < @inverse.size
          first_value = @inverse[row][0]
          second_value = @inverse[row][index]
          new_first = (pivot / divisor)*first_value
          new_first += (other / divisor)*second_value
          new_second = (0 - right)*first_value
          new_second += left*second_value
          @inverse[row][0] = new_first
          @inverse[row][index] = new_second
          row += 1
      pivot = divisor
      working = matrix_vector(@matrix, @source)
      index += 1

    if pivot < 0
      # This case is normally absorbed by extended_gcd, but retain a
      # deterministic positive gcd even for one-dimensional negative input.
      row = 0
      while row < @matrix[0].size
        @matrix[0][row] = 0 - @matrix[0][row]
        row += 1
      row = 0
      while row < @inverse.size
        @inverse[row][0] = 0 - @inverse[row][0]
        row += 1

    @image = matrix_vector(@matrix, @source)
    @divisor = @image[0]
    raise "zero direction has no primitive torus straightening" if @divisor == 0
    if !certified?
      raise "flat torus unimodular straightening failed certification"

  ro :source
  ro :matrix
  ro :inverse
  ro :image
  ro :divisor

  -> primitive?
    @divisor == 1

  -> integer_identity(size)
    rows = []
    row = 0
    while row < size
      values = []
      column = 0
      while column < size
        values.push(row == column ? 1 : 0)
        column += 1
      rows.push(values)
      row += 1
    rows

  -> extended_gcd(left, right)
    old_r = left
    r = right
    old_s = 1
    s = 0
    old_t = 0
    t = 1
    while r != 0
      quotient = old_r / r
      next_r = old_r - quotient*r
      old_r = r
      r = next_r
      next_s = old_s - quotient*s
      old_s = s
      s = next_s
      next_t = old_t - quotient*t
      old_t = t
      t = next_t
    if old_r < 0
      old_r = 0 - old_r
      old_s = 0 - old_s
      old_t = 0 - old_t
    [old_r, old_s, old_t]

  -> matrix_vector(matrix, vector)
    result = []
    row = 0
    while row < matrix.size
      value = 0
      column = 0
      while column < vector.size
        value += matrix[row][column]*vector[column]
        column += 1
      result.push(value)
      row += 1
    result

  -> matrix_product(left, right)
    product = []
    row = 0
    while row < left.size
      values = []
      column = 0
      while column < right.size
        value = 0
        index = 0
        while index < right.size
          value += left[row][index]*right[index][column]
          index += 1
        values.push(value)
        column += 1
      product.push(values)
      row += 1
    product

  -> vectors_equal?(left, right)
    return false if left.size != right.size
    index = 0
    while index < left.size
      return false if left[index] != right[index]
      index += 1
    true

  -> matrices_equal?(left, right)
    return false if left.size != right.size
    row = 0
    while row < left.size
      return false if !vectors_equal?(left[row], right[row])
      row += 1
    true

  -> certified?
    expected = []
    @source.size.times -> (index)
      expected.push(index == 0 ? @divisor : 0)
    return false if !vectors_equal?(@image, expected)
    identity = integer_identity(@source.size)
    forward = matrices_equal?(matrix_product(@matrix, @inverse), identity)
    backward = matrices_equal?(matrix_product(@inverse, @matrix), identity)
    forward && backward

  -> straighten(vector)
    raise "flat torus point has the wrong dimension" if vector.size != @source.size
    matrix_vector(@matrix, vector)

  -> unstraighten(vector)
    raise "flat torus point has the wrong dimension" if vector.size != @source.size
    matrix_vector(@inverse, vector)

+ FlatTorusOrbit
  -> new(generators)
    if generators.class_name != "Array" || generators.size == 0
      raise "flat torus orbit needs a nonempty Array of integer generators"

    normalized = []
    common = 0
    generators.each -> (generator)
      integer = generator.class_name == "Integer" || generator.class_name == "Int"
      raise "flat torus orbit generators must be nonzero integers" if !integer
      value = generator.abs
      raise "flat torus orbit generators must be nonzero integers" if value == 0
      normalized.push(value)
      common = common == 0 ? value : common.gcd(value)

    if common > 1
      index = 0
      while index < normalized.size
        normalized[index] /= common
        index += 1
    @generators = normalized

  ro :generators

  -> dimension
    @generators.size

  -> primitive?
    common = @generators[0]
    index = 1
    while index < @generators.size
      common = common.gcd(@generators[index])
      index += 1
    common == 1

  -> coordinate_distance(index, time)
    raise "flat torus coordinate index is out of bounds" if index < 0 || index >= dimension
    value = Rational.coerce(time) * @generators[index]
    denominator = value.denominator
    residue = value.numerator % denominator
    residue += denominator if residue < 0
    residue = denominator - residue if residue * 2 > denominator
    Rational.new(residue, denominator)

  -> minimum_coordinate_distance(time)
    best = coordinate_distance(0, time)
    index = 1
    while index < dimension
      candidate = coordinate_distance(index, time)
      best = candidate if candidate < best
      index += 1
    best

  -> active_coordinate_indices(time)
    minimum = minimum_coordinate_distance(time)
    active = []
    index = 0
    while index < dimension
      active.push(index) if coordinate_distance(index, time) == minimum
      index += 1
    active

  -> coordinate_indices
    indices = []
    dimension.times -> (index) indices.push(index)
    indices

  -> sorted_rationals(values)
    sorted = []
    values.each -> (value)
      sorted.push(value)
      index = sorted.size - 1
      while index > 0 && sorted[index] < sorted[index - 1]
        previous = sorted[index - 1]
        sorted[index - 1] = sorted[index]
        sorted[index] = previous
        index -= 1
    sorted

  -> validate_arc_radius(radius)
    exact = Rational.coerce(radius)
    if exact <= Rational.new(0) || exact > Rational.new(1, 2)
      raise "flat torus arc radius must lie in (0, 1/2]"
    exact

  -> validate_coordinate_indices(indices)
    if indices.class_name != "Array" || indices.size == 0
      raise "flat torus coordinate selection must be a nonempty Array"
    seen = {}
    indices.each -> (index)
      integer = index.class_name == "Integer" || index.class_name == "Int"
      if !integer || index < 0 || index >= dimension
        raise "flat torus coordinate index is out of bounds"
      key = index.to_s
      raise "flat torus coordinate selection contains a duplicate" if seen.has_key?(key)
      seen[key] = true
    indices

  # Boundaries of {t : ||v_i*t|| < radius} on the unit circle, represented in
  # [0, 1].  Endpoints are retained even though they have measure zero because
  # bad_sets_cover? must distinguish full measure from a genuine open cover.
  -> bad_arc_boundaries(radius, indices = nil)
    exact_radius = validate_arc_radius(radius)
    selected = indices == nil ? coordinate_indices : validate_coordinate_indices(indices)
    seen = {"0" => true, "1" => true}
    boundaries = [Rational.new(0), Rational.new(1)]
    selected.each -> (index)
      speed = @generators[index]
      integer = 0
      while integer < speed
        plus = (Rational.new(integer) + exact_radius) / speed
        key = plus.to_s
        if !seen.has_key?(key)
          seen[key] = true
          boundaries.push(plus)
        integer += 1
      integer = 1
      while integer <= speed
        minus = (Rational.new(integer) - exact_radius) / speed
        key = minus.to_s
        if !seen.has_key?(key)
          seen[key] = true
          boundaries.push(minus)
        integer += 1
    sorted_rationals(boundaries)

  -> bad_coordinate_count(time, radius, indices = nil)
    exact_radius = validate_arc_radius(radius)
    selected = indices == nil ? coordinate_indices : validate_coordinate_indices(indices)
    count = 0
    selected.each -> (index)
      count += 1 if coordinate_distance(index, time) < exact_radius
    count

  # Exact Haar measure of cells with each bad-coordinate multiplicity.  The
  # returned Array has selected.size+1 Rational entries and sums to one.
  -> bad_multiplicity_measures(radius, indices = nil)
    exact_radius = validate_arc_radius(radius)
    selected = indices == nil ? coordinate_indices : validate_coordinate_indices(indices)
    boundaries = bad_arc_boundaries(exact_radius, selected)
    measures = []
    (selected.size + 1).times -> measures.push(Rational.new(0))
    cell = 0
    while cell + 1 < boundaries.size
      left = boundaries[cell]
      right = boundaries[cell + 1]
      if right > left
        midpoint = (left + right) / Rational.new(2)
        count = bad_coordinate_count(midpoint, exact_radius, selected)
        measures[count] += right - left
      cell += 1
    measures

  -> bad_intersection_measure(indices, radius)
    selected = validate_coordinate_indices(indices)
    bad_multiplicity_measures(radius, selected)[selected.size]

  -> bad_union_measure(radius, indices = nil)
    measures = bad_multiplicity_measures(radius, indices)
    Rational.new(1) - measures[0]

  # Exact one-dimensional Haar measure of times on this orbit for which every
  # selected coordinate is at least radius from Z.  This pullback measure can
  # be zero even though the corresponding target has positive ambient volume.
  -> lonely_time_measure(radius, indices = nil)
    bad_multiplicity_measures(radius, indices)[0]

  # Haar volume of the axis-aligned target in the full selected-coordinate
  # torus.  At the Lonely Runner threshold for n coordinates this is
  # ((n-1)/(n+1))^n, tending to exp(-2); orbit correlations, not ambient
  # volume scarcity, are the issue for resonant integer directions.
  -> ambient_lonely_region_measure(radius, indices = nil)
    exact_radius = validate_arc_radius(radius)
    selected = indices == nil ? coordinate_indices : validate_coordinate_indices(indices)
    side = Rational.new(1) - Rational.new(2)*exact_radius
    measure = Rational.new(1)
    selected.size.times -> measure *= side
    measure

  -> ambient_bad_region_measure(radius, indices = nil)
    Rational.new(1) - ambient_lonely_region_measure(radius, indices)

  # Full measure is insufficient for strict bad arcs: equality witness times
  # can be the only uncovered points.  Check every event boundary as well as
  # the open cells represented by bad_union_measure.
  -> bad_sets_cover?(radius, indices = nil)
    exact_radius = validate_arc_radius(radius)
    selected = indices == nil ? coordinate_indices : validate_coordinate_indices(indices)
    if bad_union_measure(exact_radius, selected) != Rational.new(1)
      return false
    boundaries = bad_arc_boundaries(exact_radius, selected)
    index = 0
    while index < boundaries.size
      if bad_coordinate_count(boundaries[index], exact_radius, selected) == 0
        return false
      index += 1
    true

  -> add_event_times(seen, times, denominator)
    if denominator <= 0
      return nil
    numerator = 0
    limit = denominator / 2
    while numerator <= limit
      time = Rational.new(numerator, denominator)
      key = time.to_s
      if !seen.has_key?(key)
        seen[key] = true
        times.push(time)
      numerator += 1

  # Exact candidate set on [0, 1/2].  Reflection t -> 1-t preserves every
  # coordinate distance, so this half-period contains a global maximum.
  -> critical_times
    seen = {}
    times = []
    left = 0
    while left < dimension
      a = @generators[left]
      # The self-sum 2*a contributes all apices of ||a*t||.
      add_event_times(seen, times, 2*a)
      right = left + 1
      while right < dimension
        b = @generators[right]
        add_event_times(seen, times, a + b)
        difference = (a - b).abs
        add_event_times(seen, times, difference) if difference > 0
        right += 1
      left += 1
    sorted_rationals(times)

  -> maximum_minimum_coordinate_distance
    times = critical_times
    best = Rational.new(-1)
    witnesses = []
    times.each -> (time)
      value = minimum_coordinate_distance(time)
      if value > best
        best = value
        witnesses = [time]
      elsif value == best
        witnesses.push(time)
    FlatTorusOrbitExtremum.new(best, witnesses)

  -> maximum_loneliness
    maximum_minimum_coordinate_distance

  -> unimodular_straightening
    FlatTorusOrbitStraightening.new(@generators)

  -> linfinity_distance_to_half
    Rational.new(1, 2) - maximum_loneliness.value

  -> witness_at_least?(threshold)
    maximum_loneliness.value >= Rational.coerce(threshold)
