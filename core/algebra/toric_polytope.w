# Exact low-dimensional lattice polytopes, Newton polytopes, and their
# homogenizing cones.  The implementation is intentionally certificate-first:
# facets are enumerated from exact rational nullspaces, lattice-point counts
# are checked in the original ambient lattice, and lattice-dual claims are
# made only when the selected intrinsic coordinate projection is saturated.
#
# This is designed for sparse Symanzik and Laurent polynomials (typically at
# most six variables and a few dozen monomials), not for large computational
# geometry workloads.

use core/algebra/lattice_polytope
use core/algebra/polynomial

+ ToricLinearAlgebra
  -> .copy_rational_matrix(matrix)
    out = []
    matrix.each -> (source)
      row = []
      source.each -> row.push(Rational.coerce(item))
      out.push(row)
    out

  # Returns [rref, pivot columns].  `width` is required for an empty matrix.
  -> .rref(matrix, width = nil)
    if matrix.class_name != "Array"
      raise "toric RREF needs an array of rows"
    if matrix.size == 0
      raise "empty toric RREF needs a width" if width == nil
      return [[], []]
    columns = matrix[0].size
    rows = ToricLinearAlgebra.copy_rational_matrix(matrix)
    rows.each ->
      raise "toric matrix rows have inconsistent widths" if item.size != columns

    pivots = []
    pivot_row = 0
    column = 0
    while pivot_row < rows.size && column < columns
      selected = pivot_row
      while selected < rows.size && rows[selected][column].zero?
        selected += 1
      if selected == rows.size
        column += 1
      else
        if selected != pivot_row
          temporary = rows[pivot_row]
          rows[pivot_row] = rows[selected]
          rows[selected] = temporary
        pivot = rows[pivot_row][column]
        cell = 0
        while cell < columns
          rows[pivot_row][cell] = rows[pivot_row][cell] / pivot
          cell += 1
        row = 0
        while row < rows.size
          if row != pivot_row && !rows[row][column].zero?
            factor = rows[row][column]
            cell = 0
            while cell < columns
              rows[row][cell] -= factor * rows[pivot_row][cell]
              cell += 1
          row += 1
        pivots.push(column)
        pivot_row += 1
        column += 1
    [rows, pivots]

  -> .rank(matrix, width = nil)
    ToricLinearAlgebra.rref(matrix, width)[1].size

  -> .nullspace(matrix, width = nil)
    reduced = ToricLinearAlgebra.rref(matrix, width)
    rows = reduced[0]
    pivots = reduced[1]
    columns = width
    columns = matrix[0].size if columns == nil
    pivot_set = {}
    pivots.each -> pivot_set[item.to_s] = true
    basis = []
    free = 0
    while free < columns
      if pivot_set[free.to_s] == nil
        vector = []
        columns.times -> vector.push(Rational.new(0))
        vector[free] = Rational.new(1)
        row = 0
        while row < pivots.size
          vector[pivots[row]] = 0 - rows[row][free]
          row += 1
        basis.push(vector)
      free += 1
    basis

  -> .transpose(matrix)
    raise "transpose needs a nonempty matrix" if matrix.size == 0
    out = []
    column = 0
    while column < matrix[0].size
      row = []
      i = 0
      while i < matrix.size
        raise "transpose matrix rows have inconsistent widths" if matrix[i].size != matrix[0].size
        row.push(Rational.coerce(matrix[i][column]))
        i += 1
      out.push(row)
      column += 1
    out

  -> .dot(left, right)
    raise "dot-product dimensions do not match" if left.size != right.size
    value = 0
    i = 0
    while i < left.size
      value += left[i] * right[i]
      i += 1
    value

  -> .lcm(left, right)
    return right.abs if left == 0
    return left.abs if right == 0
    (left / left.gcd(right) * right).abs

  -> .primitive_integer_vector(vector)
    common_denominator = 1
    vector.each -> (entry)
      value = Rational.coerce(entry)
      common_denominator = ToricLinearAlgebra.lcm(
        common_denominator, value.denominator)
    integers = []
    vector.each -> (entry)
      value = Rational.coerce(entry)
      integers.push(value.numerator *
                    (common_denominator / value.denominator))
    divisor = 0
    integers.each -> divisor = divisor.gcd(item.abs)
    raise "zero vector has no primitive representative" if divisor == 0
    integers.map -> item / divisor

  -> .append_combinations(out, current, start, count, wanted)
    if current.size == wanted
      out.push(LatticeCombinatorics.copy_vector(current))
      return out
    remaining = wanted - current.size
    value = start
    while value <= count - remaining
      current.push(value)
      ToricLinearAlgebra.append_combinations(
        out, current, value + 1, count, wanted)
      current.pop
      value += 1
    out

  -> .combinations(count, wanted)
    return [[]] if wanted == 0
    return [] if wanted < 0 || wanted > count
    ToricLinearAlgebra.append_combinations([], [], 0, count, wanted)

  -> .same_integer_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true


+ LatticePolytope
  -> new(points)
    if points.class_name != "Array" || points.size == 0
      raise "a lattice polytope needs at least one point"
    if points[0].class_name != "Array" || points[0].size == 0
      raise "lattice-polytope points need positive ambient dimension"
    @ambient_dimension = points[0].size
    @support_points = []
    seen = {}
    points.each -> (source)
      if source.class_name != "Array" || source.size != @ambient_dimension
        raise "lattice-polytope points have inconsistent dimensions"
      point = []
      source.each -> (coordinate)
        if !LatticeCombinatorics.integer?(coordinate)
          raise "lattice-polytope coordinates must be integers"
        point.push(coordinate)
      key = point.join(",")
      if seen[key] == nil
        seen[key] = true
        @support_points.push(point)
    @base_point = @support_points[0]
    @difference_rows = []
    i = 1
    while i < @support_points.size
      row = []
      coordinate = 0
      while coordinate < @ambient_dimension
        row.push(@support_points[i][coordinate] - @base_point[coordinate])
        coordinate += 1
      @difference_rows.push(row)
      i += 1
    reduced = ToricLinearAlgebra.rref(
      @difference_rows, @ambient_dimension)
    @row_basis = []
    reduced[1].size.times -> (row)
      @row_basis.push(reduced[0][row])
    @affine_dimension = @row_basis.size
    choose_projection
    @projected_points = @support_points.map -> project(item)
    hull = incremental_hull
    @facets = hull[0]
    @vertices = []
    hull[1].each -> @vertices.push(
      LatticeCombinatorics.copy_vector(@support_points[item]))
    @triangulated_facets = hull[2]
    @intrinsic_interior = hull[3]
    @h_star = nil
    @lattice_points_cache = {}
    @codegree_cache = {}

  ro :ambient_dimension, :affine_dimension

  -> dimension
    @affine_dimension

  -> support_points
    LatticeCombinatorics.copy_matrix(@support_points)

  -> points
    support_points

  -> vertices
    LatticeCombinatorics.copy_matrix(@vertices)

  -> pivot_coordinates
    LatticeCombinatorics.copy_vector(@projection_coordinates)

  -> saturated_projection?
    @saturated_projection

  -> choose_projection
    if @affine_dimension == 0
      @projection_coordinates = []
      @projection_lifts = []
      @saturated_projection = true
      return self
    fallback = ToricLinearAlgebra.rref(
      @difference_rows, @ambient_dimension)[1]
    @projection_coordinates = fallback
    @projection_lifts = []
    @saturated_projection = false

    ToricLinearAlgebra.combinations(
      @ambient_dimension, @affine_dimension).each -> (coordinates)
      square = []
      @row_basis.each -> (basis_row)
        row = []
        coordinates.each -> row.push(basis_row[item])
        square.push(row)
      next if Algebra.determinant(square).zero?
      inverse_transpose = ExactRationalLinearAlgebra.inverse(
        ToricLinearAlgebra.transpose(square))
      lifts = []
      saturated = true
      coordinate = 0
      while coordinate < @affine_dimension
        unit = []
        @affine_dimension.times -> (i)
          unit.push(Rational.new(i == coordinate ? 1 : 0))
        coefficients = ExactRationalLinearAlgebra.matrix_vector(
          inverse_transpose, unit)
        lift = []
        ambient = 0
        while ambient < @ambient_dimension
          value = Rational.new(0)
          i = 0
          while i < @affine_dimension
            value += coefficients[i] * @row_basis[i][ambient]
            i += 1
          saturated = false if value.denominator != 1
          lift.push(value)
          ambient += 1
        lifts.push(lift)
        coordinate += 1
      if saturated
        @projection_coordinates = coordinates
        @projection_lifts = lifts
        @saturated_projection = true
        return self
    self

  -> project(point)
    out = []
    @projection_coordinates.each -> out.push(point[item])
    out

  -> initial_simplex_indices
    return [0] if @affine_dimension == 0
    selected = [0]
    candidate = 1
    while candidate < @projected_points.size
      break if selected.size >= @affine_dimension + 1
      rows = []
      trial = selected + [candidate]
      i = 1
      while i < trial.size
        row = []
        coordinate = 0
        while coordinate < @affine_dimension
          row.push(@projected_points[trial[i]][coordinate] -
                   @projected_points[trial[0]][coordinate])
          coordinate += 1
        rows.push(row)
        i += 1
      if ToricLinearAlgebra.rank(rows, @affine_dimension) == trial.size - 1
        selected.push(candidate)
      candidate += 1
    if selected.size != @affine_dimension + 1
      raise "failed to find a full-dimensional intrinsic simplex"
    selected

  -> facet_simplex(indices, interior)
    selected = []
    indices.each -> selected.push(@projected_points[item])
    edge_rows = []
    i = 1
    while i < selected.size
      row = []
      coordinate = 0
      while coordinate < @affine_dimension
        row.push(selected[i][coordinate] - selected[0][coordinate])
        coordinate += 1
      edge_rows.push(row)
      i += 1
    return nil if ToricLinearAlgebra.rank(
      edge_rows, @affine_dimension) != @affine_dimension - 1
    nullspace = ToricLinearAlgebra.nullspace(
      edge_rows, @affine_dimension)
    return nil if nullspace.size != 1
    normal = ToricLinearAlgebra.primitive_integer_vector(nullspace[0])
    bound = ToricLinearAlgebra.dot(normal, selected[0])
    if ToricLinearAlgebra.dot(normal, interior) > bound
      normal = normal.map -> 0 - item
      bound = 0 - bound
    [indices.sort, normal, bound]

  # Exact beneath--beyond hull.  Facets remain triangulated internally; the
  # public facet list below merges coplanar simplices by primitive equation.
  -> incremental_hull
    if @affine_dimension == 0
      return [[], [0], [], []]
    simplex = initial_simplex_indices
    interior = []
    coordinate = 0
    while coordinate < @affine_dimension
      total = Rational.new(0)
      simplex.each -> total += @projected_points[item][coordinate]
      interior.push(total / simplex.size)
      coordinate += 1

    triangulated = []
    omitted = 0
    while omitted < simplex.size
      indices = []
      i = 0
      while i < simplex.size
        indices.push(simplex[i]) if i != omitted
        i += 1
      triangulated.push(facet_simplex(indices, interior))
      omitted += 1

    initial = {}
    simplex.each -> initial[item.to_s] = true
    point_index = 0
    while point_index < @projected_points.size
      if initial[point_index.to_s] != nil
        point_index += 1
        next
      visible = []
      facet_index = 0
      while facet_index < triangulated.size
        facet = triangulated[facet_index]
        if ToricLinearAlgebra.dot(
            facet[1], @projected_points[point_index]) > facet[2]
          visible.push(facet_index)
        facet_index += 1
      if visible.size == 0
        point_index += 1
        next

      visible_set = {}
      visible.each -> visible_set[item.to_s] = true
      ridges = {}
      visible.each -> (position)
        facet = triangulated[position]
        ToricLinearAlgebra.combinations(
          facet[0].size, @affine_dimension - 1).each -> (local_indices)
          ridge = []
          local_indices.each -> ridge.push(facet[0][item])
          ridge = ridge.sort
          key = ridge.join(",")
          record = ridges[key]
          if record == nil
            ridges[key] = [ridge, 1]
          else
            record[1] += 1
            ridges[key] = record

      retained = []
      facet_index = 0
      while facet_index < triangulated.size
        retained.push(triangulated[facet_index]) if visible_set[facet_index.to_s] == nil
        facet_index += 1
      ridges.each -> (key, record)
        if record[1] == 1
          new_facet = facet_simplex(record[0] + [point_index], interior)
          retained.push(new_facet) if new_facet != nil
      triangulated = retained
      point_index += 1

    facets = []
    facet_seen = {}
    vertex_seen = {}
    triangulated.each -> (facet)
      key = facet[1].join(",") + "<=" + facet[2].to_s
      if facet_seen[key] == nil
        facet_seen[key] = true
        facets.push([facet[1], facet[2]])
      facet[0].each -> vertex_seen[item.to_s] = item
    vertex_indices = vertex_seen.values.sort
    [facets, vertex_indices, triangulated, interior]

  -> primitive_facets
    out = []
    @facets.each -> (facet)
      out.push([LatticeCombinatorics.copy_vector(facet[0]), facet[1]])
    out

  -> facet_count
    @facets.size

  -> minimum_weight(weight)
    if weight.class_name != "Array" || weight.size != @ambient_dimension
      raise "polytope weight has the wrong ambient dimension"
    value = nil
    @vertices.each -> (point)
      candidate = ToricLinearAlgebra.dot(weight, point)
      value = candidate if value == nil || candidate < value
    value

  -> maximum_weight(weight)
    if weight.class_name != "Array" || weight.size != @ambient_dimension
      raise "polytope weight has the wrong ambient dimension"
    value = nil
    @vertices.each -> (point)
      candidate = ToricLinearAlgebra.dot(weight, point)
      value = candidate if value == nil || candidate > value
    value

  -> minimizing_face(weight)
    minimum = minimum_weight(weight)
    out = []
    @support_points.each -> (point)
      if ToricLinearAlgebra.dot(weight, point) == minimum
        out.push(LatticeCombinatorics.copy_vector(point))
    out

  -> affine_member?(point, dilation = 1)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "polytope dilation")
    if point.class_name != "Array" || point.size != @ambient_dimension
      return false
    coordinate = 0
    while coordinate < point.size
      return false if !LatticeCombinatorics.integer?(point[coordinate])
      coordinate += 1
    if k == 0
      coordinate = 0
      while coordinate < point.size
        return false if point[coordinate] != 0
        coordinate += 1
      return true
    difference = []
    i = 0
    while i < @ambient_dimension
      difference.push(point[i] - k*@base_point[i])
      i += 1
    ToricLinearAlgebra.rank(
      @difference_rows + [difference], @ambient_dimension) == @affine_dimension

  -> lattice_point?(point, dilation = 1)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "polytope dilation")
    return false if !affine_member?(point, k)
    return true if k == 0 || @affine_dimension == 0
    projected = project(point)
    index = 0
    while index < @facets.size
      facet = @facets[index]
      return false if ToricLinearAlgebra.dot(facet[0], projected) > k*facet[1]
      index += 1
    true

  -> interior_lattice_point?(point, dilation = 1)
    k = LatticeCombinatorics.positive_integer(
      dilation, "polytope dilation")
    return false if !affine_member?(point, k)
    return true if @affine_dimension == 0
    projected = project(point)
    index = 0
    while index < @facets.size
      facet = @facets[index]
      return false if ToricLinearAlgebra.dot(facet[0], projected) >= k*facet[1]
      index += 1
    true

  -> enumeration_bounds(dilation)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "polytope dilation")
    bounds = []
    coordinate = 0
    while coordinate < @ambient_dimension
      minimum = @vertices[0][coordinate]
      maximum = minimum
      @vertices.each -> (point)
        minimum = point[coordinate] if point[coordinate] < minimum
        maximum = point[coordinate] if point[coordinate] > maximum
      bounds.push([k*minimum, k*maximum])
      coordinate += 1
    bounds

  # Bounds in a saturated intrinsic lattice chart.  When the selected
  # coordinate projection is saturated, every integral projected point lifts
  # to exactly one point of the ambient affine lattice.  Enumerating here
  # avoids scanning the (usually much larger) ambient box and avoids an exact
  # rank computation for every candidate.
  -> projected_enumeration_bounds(dilation)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "polytope dilation")
    bounds = []
    coordinate = 0
    while coordinate < @affine_dimension
      minimum = @projected_points[0][coordinate]
      maximum = minimum
      @projected_points.each -> (point)
        minimum = point[coordinate] if point[coordinate] < minimum
        maximum = point[coordinate] if point[coordinate] > maximum
      bounds.push([k*minimum, k*maximum])
      coordinate += 1
    bounds

  -> projected_lattice_point?(projected, dilation, interior)
    index = 0
    while index < @facets.size
      facet = @facets[index]
      value = ToricLinearAlgebra.dot(facet[0], projected)
      if interior
        return false if value >= dilation*facet[1]
      else
        return false if value > dilation*facet[1]
      index += 1
    true

  -> lift_projected_lattice_point(projected, dilation)
    point = []
    ambient = 0
    while ambient < @ambient_dimension
      value = Rational.new(dilation*@base_point[ambient])
      coordinate = 0
      while coordinate < @affine_dimension
        delta = (projected[coordinate] -
                 dilation*@base_point[@projection_coordinates[coordinate]])
        value += delta*@projection_lifts[coordinate][ambient]
        coordinate += 1
      if value.denominator != 1
        raise "saturated intrinsic lattice lift was not integral"
      point.push(value.numerator)
      ambient += 1
    point

  -> intrinsic_lattice_points(dilation, interior, box_limit)
    bounds = projected_enumeration_bounds(dilation)
    box_size = 1
    bounds.each -> box_size *= item[1] - item[0] + 1
    if box_size > box_limit
      raise "intrinsic lattice-point enumeration box exceeds limit: " + box_size.to_s
    out = []
    projected = []
    @affine_dimension.times -> projected.push(0)
    visit = nil
    visit = -> (coordinate)
      if coordinate == @affine_dimension
        if projected_lattice_point?(projected, dilation, interior)
          out.push(lift_projected_lattice_point(projected, dilation))
      else
        value = bounds[coordinate][0]
        while value <= bounds[coordinate][1]
          projected[coordinate] = value
          visit.call(coordinate + 1)
          value += 1
    visit.call(0)
    out

  -> lattice_points(dilation = 1, interior = false, box_limit = 5_000_000)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "polytope dilation")
    if interior && k == 0
      raise "the zero dilation has no relative interior enumeration"
    cache_key = interior ? "interior:" : "closed:"
    cache_key += k.to_s
    cached = @lattice_points_cache[cache_key]
    return LatticeCombinatorics.copy_matrix(cached) if cached != nil
    if @saturated_projection
      points = intrinsic_lattice_points(k, interior, box_limit)
      @lattice_points_cache[cache_key] = points
      return LatticeCombinatorics.copy_matrix(points)
    bounds = enumeration_bounds(k)
    box_size = 1
    bounds.each -> box_size *= item[1] - item[0] + 1
    if box_size > box_limit
      raise "lattice-point enumeration box exceeds limit: " + box_size.to_s
    out = []
    point = []
    @ambient_dimension.times -> point.push(0)
    visit = nil
    visit = -> (coordinate)
      if coordinate == @ambient_dimension
        accepted = interior ? interior_lattice_point?(point, k) : lattice_point?(point, k)
        out.push(LatticeCombinatorics.copy_vector(point)) if accepted
      else
        value = bounds[coordinate][0]
        while value <= bounds[coordinate][1]
          point[coordinate] = value
          visit.call(coordinate + 1)
          value += 1
    visit.call(0)
    @lattice_points_cache[cache_key] = out
    LatticeCombinatorics.copy_matrix(out)

  -> lattice_point_count(dilation = 1, box_limit = 5_000_000)
    lattice_points(dilation, false, box_limit).size

  -> interior_lattice_points(dilation = 1, box_limit = 5_000_000)
    lattice_points(dilation, true, box_limit)

  -> interior_lattice_point_count(dilation = 1, box_limit = 5_000_000)
    interior_lattice_points(dilation, box_limit).size

  -> h_star_coefficients(box_limit = 5_000_000)
    return LatticeCombinatorics.copy_vector(@h_star) if @h_star != nil
    counts = []
    k = 0
    while k <= @affine_dimension
      counts.push(lattice_point_count(k, box_limit))
      k += 1
    coefficients = []
    i = 0
    while i <= @affine_dimension
      value = 0
      j = 0
      while j <= i
        sign = ((i - j) % 2 == 0) ? 1 : -1
        value += sign * LatticeCombinatorics.binomial(
          @affine_dimension + 1, i - j) * counts[j]
        j += 1
      coefficients.push(value)
      i += 1
    @h_star = coefficients
    LatticeCombinatorics.copy_vector(@h_star)

  -> normalized_volume(box_limit = 5_000_000)
    total = 0
    h_star_coefficients(box_limit).each -> total += item
    total

  # Exact full-dimensional normalized volume from the triangulated boundary
  # already produced by the beneath--beyond hull.  Unlike the Ehrhart path
  # above, this does not enumerate a coordinate box, so it remains practical
  # for sparse polytopes with very large coordinates.  Lower-dimensional
  # polytopes have zero volume in their ambient lattice, as required by mixed
  # volume polarization.
  -> ambient_normalized_volume
    return 0 if @affine_dimension < @ambient_dimension
    return 1 if @ambient_dimension == 0
    if !@saturated_projection
      raise "ambient normalized volume needs a saturated lattice chart"
    total = Rational.new(0)
    @triangulated_facets.each -> (facet)
      matrix = []
      facet[0].each -> (point_index)
        row = []
        coordinate = 0
        while coordinate < @affine_dimension
          row.push(Rational.new(@projected_points[point_index][coordinate]) -
                   @intrinsic_interior[coordinate])
          coordinate += 1
        matrix.push(row)
      total += Algebra.determinant(matrix).abs
    if total.denominator != 1
      raise "triangulated normalized volume was not integral"
    total.numerator

  # The normalized mixed volume of exactly d lattice polytopes in a common
  # d-dimensional ambient lattice.  Polarization uses ambient volumes, so
  # segments and other lower-dimensional summands are handled correctly.
  -> normalized_mixed_volume(*others)
    polytopes = [self] + others
    dimension = @ambient_dimension
    if polytopes.size != dimension
      raise "normalized mixed volume needs one summand per ambient dimension"
    polytopes.each -> (polytope)
      compatible = polytope.respond_to?("ambient_dimension")
      compatible = false if compatible && polytope.ambient_dimension != dimension
      if !compatible
        raise "mixed-volume summands have different ambient dimensions"
    total = 0 ## BigInt
    subset = 1
    limit = 1 << dimension
    while subset < limit
      sum = nil
      count = 0
      index = 0
      while index < dimension
        if (subset & (1 << index)) != 0
          count += 1
          sum = sum == nil ? polytopes[index] : sum.minkowski_sum(polytopes[index])
        index += 1
      value = sum.ambient_normalized_volume
      if (dimension - count) % 2 == 0
        total += value
      else
        total -= value
      subset += 1
    divisor = dimension.factorial
    if total % divisor != 0
      raise "normalized mixed-volume polarization was not integral"
    total / divisor

  -> volume(box_limit = 5_000_000)
    Rational.new(normalized_volume(box_limit), @affine_dimension.factorial)

  -> translate(vector)
    if vector.class_name != "Array" || vector.size != @ambient_dimension
      raise "polytope translation has the wrong dimension"
    vector.each ->
      raise "polytope translation must be integral" if !LatticeCombinatorics.integer?(item)
    translated = []
    @vertices.each -> (vertex)
      point = []
      i = 0
      while i < @ambient_dimension
        point.push(vertex[i] + vector[i])
        i += 1
      translated.push(point)
    LatticePolytope.new(translated)

  -> dilate(factor)
    k = LatticeCombinatorics.nonnegative_integer(
      factor, "polytope dilation")
    scaled = []
    @vertices.each -> (vertex)
      scaled.push(vertex.map -> item*k)
    LatticePolytope.new(scaled)

  -> minkowski_sum(other)
    compatible = other.respond_to?("ambient_dimension")
    compatible = false if compatible && other.ambient_dimension != @ambient_dimension
    if !compatible
      raise "Minkowski summands have different ambient dimensions"
    sums = []
    @vertices.each -> (left)
      other.vertices.each -> (right)
        point = []
        i = 0
        while i < @ambient_dimension
          point.push(left[i] + right[i])
          i += 1
        sums.push(point)
    LatticePolytope.new(sums)

  -> origin
    out = []
    @ambient_dimension.times -> out.push(0)
    out

  -> reflexive?
    return false if !@saturated_projection
    return false if !interior_lattice_point?(origin)
    index = 0
    while index < @facets.size
      return false if @facets[index][1] != 1
      index += 1
    true

  # Reflexivity is translation invariant, but `reflexive?` deliberately asks
  # whether this particular presentation is centered at the origin.  This
  # variant recognizes a polytope with a unique interior lattice point whose
  # translation to the origin is reflexive.
  -> reflexive_up_to_translation?
    gorenstein_index == 1

  -> reflexive_center
    return nil if !reflexive_up_to_translation?
    interior_lattice_points(1)[0]

  -> codegree(limit = nil, box_limit = 5_000_000)
    maximum = limit == nil ? @affine_dimension + 1 : limit
    LatticeCombinatorics.positive_integer(maximum, "codegree limit")
    cache_key = maximum.to_s
    cached = @codegree_cache[cache_key]
    return cached if cached != nil
    k = 1
    while k <= maximum
      if interior_lattice_point_count(k, box_limit) > 0
        @codegree_cache[cache_key] = k
        return k
      k += 1
    nil

  -> gorenstein_index(limit = nil, box_limit = 5_000_000)
    return nil if !@saturated_projection
    index = codegree(limit, box_limit)
    return nil if index == nil
    interior = interior_lattice_points(index, box_limit)
    return nil if interior.size != 1
    translation = interior[0].map -> 0 - item
    centered = dilate(index).translate(translation)
    centered.reflexive? ? index : nil

  -> homogenized_cone
    HomogenizedCone.new(self)


+ NewtonPolytope
  # Semantic factory. Native class autoloads do not copy an arbitrary
  # superclass method table into a late-loaded subclass, so a mathematical
  # Newton polytope uses the common exact LatticePolytope value type rather
  # than adding a fragile wrapper.
  -> new(points)
    LatticePolytope.new(points)

  -> .from_polynomial(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "Newton polytope needs a Polynomial"
    raise "the zero polynomial has no Newton polytope" if polynomial.zero?
    exponents = []
    polynomial.each_term -> (coefficient, powers)
      exponents.push(powers)
    LatticePolytope.new(exponents)


+ Polynomial
  -> newton_polytope
    NewtonPolytope.from_polynomial(self)

  -> toric_hypersurface_period(center = nil)
    ToricHypersurfacePeriod.new(self, center)


# Fundamental constant-term period attached to a Laurent polynomial obtained
# by translating a polynomial's Newton polytope.  If `m` is the chosen center,
#
#   CT((x^-m f)^n) = [x^(n m)] f^n.
#
# Computing the right-hand side keeps all internal exponents nonnegative and
# therefore reuses Polynomial's exact sparse arithmetic without introducing a
# second, partially overlapping Laurent-polynomial implementation.
+ ToricHypersurfacePeriod
  -> new(@polynomial, center = nil)
    if @polynomial.class_name != "Polynomial" || @polynomial.zero?
      raise "a toric hypersurface period needs a nonzero Polynomial"
    polytope = @polynomial.newton_polytope
    if center == nil
      centers = polytope.interior_lattice_points(1)
      if centers.size != 1
        raise "automatic toric-period normalization needs one interior lattice point"
      @center = centers[0]
    else
      if center.class_name != "Array" || center.size != @polynomial.ring.arity
        raise "toric-period center has the wrong arity"
      @center = []
      center.each -> (coordinate)
        if !LatticeCombinatorics.integer?(coordinate)
          raise "toric-period center must be integral"
        @center.push(coordinate)
    if !polytope.saturated_projection?
      raise "toric-period constant terms need a saturated intrinsic chart"
    @projection_coordinates = polytope.pivot_coordinates
    @projected_terms = []
    @minimum_step = []
    @maximum_step = []
    @projection_coordinates.size.times -> (i)
      @minimum_step.push(nil)
      @maximum_step.push(nil)
    @polynomial.each_term -> (coefficient, exponents)
      shifted = []
      coordinate = 0
      while coordinate < @projection_coordinates.size
        ambient = @projection_coordinates[coordinate]
        value = exponents[ambient] - @center[ambient]
        shifted.push(value)
        minimum = @minimum_step[coordinate]
        maximum = @maximum_step[coordinate]
        @minimum_step[coordinate] = value if minimum == nil || value < minimum
        @maximum_step[coordinate] = value if maximum == nil || value > maximum
        coordinate += 1
      @projected_terms.push([coefficient, shifted])
    @coefficients = [@polynomial.ring.field.one]

  ro :polynomial

  -> center
    LatticeCombinatorics.copy_vector(@center)

  -> normalized_laurent_terms
    out = []
    @polynomial.each_term -> (coefficient, exponents)
      shifted = []
      i = 0
      while i < exponents.size
        shifted.push(exponents[i] - @center[i])
        i += 1
      out.push([coefficient, shifted])
    out

  -> can_return_to_origin?(state, remaining)
    coordinate = 0
    while coordinate < state.size
      minimum_reachable = state[coordinate] + remaining*@minimum_step[coordinate]
      maximum_reachable = state[coordinate] + remaining*@maximum_step[coordinate]
      return false if minimum_reachable > 0 || maximum_reachable < 0
      coordinate += 1
    true

  # Fixed-target dynamic programming.  Coordinatewise return bounds discard
  # any partial exponent which cannot possibly reach the origin in the
  # remaining multiplications.  States live in the saturated intrinsic chart,
  # reducing a homogeneous n-variable support to n-1 coordinates.
  -> constant_term_power(order)
    return @polynomial.ring.field.one if order == 0
    field = @polynomial.ring.field
    zero_state = []
    @projection_coordinates.size.times -> zero_state.push(0)
    current = {zero_state.join(",") => [zero_state, field.one]}
    step = 0
    while step < order
      remaining = order - step - 1
      next_states = {}
      current.each -> (key, record)
        @projected_terms.each -> (term)
          state = []
          coordinate = 0
          while coordinate < record[0].size
            state.push(record[0][coordinate] + term[1][coordinate])
            coordinate += 1
          next if !can_return_to_origin?(state, remaining)
          state_key = state.join(",")
          contribution = field.multiply(record[1], term[0])
          existing = next_states[state_key]
          if existing == nil
            next_states[state_key] = [state, contribution]
          else
            coefficient = field.add(existing[1], contribution)
            if field.zero?(coefficient)
              next_states.delete(state_key)
            else
              existing[1] = coefficient
              next_states[state_key] = existing
      current = next_states
      step += 1
    result = current[zero_state.join(",")]
    result == nil ? field.zero : result[1]

  -> coefficients(maximum_order)
    maximum = LatticeCombinatorics.nonnegative_integer(
      maximum_order, "toric-period order")
    while @coefficients.size <= maximum
      @coefficients.push(constant_term_power(@coefficients.size))
    LatticeCombinatorics.copy_vector(@coefficients.slice(0, maximum + 1))

  -> coefficient(order)
    coefficients(order)[order]


+ HomogenizedCone
  -> new(polytope)
    compatible = polytope.respond_to?("vertices")
    compatible = false if compatible && !polytope.respond_to?("lattice_point_count")
    if !compatible
      raise "homogenized cone needs a lattice polytope"
    @polytope = polytope

  ro :polytope

  -> dimension
    @polytope.dimension + 1

  -> ambient_dimension
    @polytope.ambient_dimension + 1

  # Height is the first coordinate: the height-k slice is kP.
  -> rays
    out = []
    @polytope.vertices.each -> (vertex)
      out.push([1] + vertex)
    out

  -> slice(height)
    @polytope.dilate(height)

  -> slice_lattice_point_count(height, box_limit = 5_000_000)
    @polytope.lattice_point_count(height, box_limit)

  -> contains_semigroup_point?(point)
    return false if point.class_name != "Array"
    return false if point.size != ambient_dimension
    height = point[0]
    return false if !LatticeCombinatorics.integer?(height) || height < 0
    spatial = []
    i = 1
    while i < point.size
      spatial.push(point[i])
      i += 1
    @polytope.lattice_point?(spatial, height)

  # If n.x <= b cuts out P, then b*h-n.x >= 0 cuts out its cone.
  -> dual_inequalities
    out = []
    @polytope.primitive_facets.each -> (facet)
      out.push([[facet[1]] + facet[0].map -> 0 - item, 0])
    out

  -> hilbert_numerator(box_limit = 5_000_000)
    @polytope.h_star_coefficients(box_limit)

  -> hilbert_denominator_power
    @polytope.dimension + 1

  -> gorenstein_index(limit = nil, box_limit = 5_000_000)
    @polytope.gorenstein_index(limit, box_limit)
