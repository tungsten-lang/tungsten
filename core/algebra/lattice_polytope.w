# Exact lattice-polytope models used by Ehrhart, Newton-polygon, and shell
# calculations.  These classes deliberately cover a small replayable spine:
# simplices, lattice polygons, the centered sharp simplex, the diagonal-shell
# quotient polytope, and Laurent-monomial jet filtrations.  They do not claim
# to implement general convex hulls or the analytic Monge--Ampere argument.

use core/numeric/rational
use core/algebra/integer_lattice

+ LatticeCombinatorics
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .nonnegative_integer(value, label)
    if !LatticeCombinatorics.integer?(value) || value < 0
      raise label + " must be a nonnegative integer"
    value

  -> .positive_integer(value, label)
    if !LatticeCombinatorics.integer?(value) || value < 1
      raise label + " must be a positive integer"
    value

  # Exact multiplicative binomial coefficient.  The division at every step
  # is exact, and Integer transparently promotes to BigInt.
  -> .binomial(n, k)
    LatticeCombinatorics.nonnegative_integer(n, "binomial n")
    LatticeCombinatorics.nonnegative_integer(k, "binomial k")
    return 0 if k > n
    k = n - k if k > n - k
    value = 1
    i = 1
    while i <= k
      value = (value * (n - k + i)) / i
      i += 1
    value

  # Eulerian A(n,m), in the convention A_1(t)=1 and
  # A_3(t)=1+4t+t^2.
  -> .eulerian_coefficients(n)
    LatticeCombinatorics.positive_integer(n, "Eulerian order")
    row = [1]
    order = 2
    while order <= n
      next_row = []
      m = 0
      while m < order
        left = m < row.size ? (m + 1) * row[m] : 0
        right = m > 0 ? (order - m) * row[m - 1] : 0
        next_row.push(left + right)
        m += 1
      row = next_row
      order += 1
    row

  -> .copy_vector(vector)
    out = []
    vector.each -> out.push(item)
    out

  -> .copy_matrix(matrix)
    out = []
    matrix.each -> out.push(LatticeCombinatorics.copy_vector(item))
    out

  -> .append_compositions(out, current, index, remaining)
    if index == current.size - 1
      current[index] = remaining
      out.push(LatticeCombinatorics.copy_vector(current))
      return out
    value = 0
    while value <= remaining
      current[index] = value
      LatticeCombinatorics.append_compositions(
        out, current, index + 1, remaining - value)
      value += 1
    out

  # All nonnegative multi-indices with total degree strictly below order.
  -> .multi_indices_below(dimension, order)
    LatticeCombinatorics.positive_integer(dimension, "multi-index dimension")
    LatticeCombinatorics.nonnegative_integer(order, "jet order")
    out = []
    current = []
    dimension.times -> current.push(0)
    total = 0
    while total < order
      LatticeCombinatorics.append_compositions(
        out, current, 0, total)
      total += 1
    out

  -> .rational_rank(matrix)
    work = []
    matrix.each -> (source)
      row = []
      source.each -> row.push(Rational.coerce(item))
      work.push(row)
    return 0 if work.size == 0
    width = work[0].size
    work.each ->
      raise "rank matrix rows have inconsistent sizes" if item.size != width
    pivot_row = 0
    column = 0
    while pivot_row < work.size && column < width
      pivot = pivot_row
      while pivot < work.size && work[pivot][column].zero?
        pivot += 1
      if pivot == work.size
        column += 1
      else
        if pivot != pivot_row
          temporary = work[pivot_row]
          work[pivot_row] = work[pivot]
          work[pivot] = temporary
        pivot_value = work[pivot_row][column]
        j = column
        while j < width
          work[pivot_row][j] = work[pivot_row][j] / pivot_value
          j += 1
        row = pivot_row + 1
        while row < work.size
          if !work[row][column].zero?
            factor = work[row][column]
            j = column
            while j < width
              work[row][j] -= factor * work[pivot_row][j]
              j += 1
          row += 1
        pivot_row += 1
        column += 1
    pivot_row


+ LatticeSimplex
  -> new(vertices)
    if vertices.class_name != "Array" || vertices.size < 2
      raise "lattice simplex needs at least two vertices"
    dimension = vertices[0].size
    if dimension < 1 || vertices.size != dimension + 1
      raise "an n-dimensional simplex needs n+1 vertices"
    @vertices = []
    vertices.each -> (vertex)
      if vertex.class_name != "Array" || vertex.size != dimension
        raise "simplex vertices have inconsistent dimensions"
      copied = []
      vertex.each -> (coordinate)
        if !LatticeCombinatorics.integer?(coordinate)
          raise "lattice simplex coordinates must be integers"
        copied.push(coordinate)
      @vertices.push(copied)
    @dimension = dimension
    raise "simplex vertices must be affinely independent" if normalized_volume == 0

  -> dimension
    @dimension

  -> vertices
    LatticeCombinatorics.copy_matrix(@vertices)

  -> edge_columns
    columns = []
    i = 1
    while i < @vertices.size
      edge = []
      j = 0
      while j < @dimension
        edge.push(@vertices[i][j] - @vertices[0][j])
        j += 1
      columns.push(edge)
      i += 1
    columns

  -> edge_matrix
    ExactRationalLinearAlgebra.matrix_from_columns(edge_columns)

  -> normalized_volume
    determinant = Algebra.determinant(edge_matrix)
    determinant.abs.numerator

  -> volume
    Rational.new(normalized_volume, @dimension.factorial)

  -> barycenter
    center = []
    coordinate = 0
    while coordinate < @dimension
      sum = 0
      @vertices.each -> sum += item[coordinate]
      center.push(Rational.new(sum, @vertices.size))
      coordinate += 1
    center

  -> barycentric_coordinates(point)
    if point.class_name != "Array" || point.size != @dimension
      raise "point dimension does not match simplex"
    target = []
    i = 0
    while i < @dimension
      target.push(Rational.coerce(point[i]) - @vertices[0][i])
      i += 1
    inverse = ExactRationalLinearAlgebra.inverse(edge_matrix)
    tail = ExactRationalLinearAlgebra.matrix_vector(inverse, target)
    total = Rational.new(0)
    tail.each -> total += item
    [Rational.new(1) - total] + tail

  -> contains?(point)
    barycentric_coordinates(point).each -> return false if item < 0
    true

  -> interior_contains?(point)
    barycentric_coordinates(point).each -> return false if item <= 0
    true


+ LatticePolygon
  -> new(vertices)
    if vertices.class_name != "Array" || vertices.size < 3
      raise "lattice polygon needs at least three ordered vertices"
    @vertices = []
    vertices.each -> (vertex)
      if vertex.class_name != "Array" || vertex.size != 2
        raise "lattice polygon vertices must be two-dimensional"
      if (!LatticeCombinatorics.integer?(vertex[0]) ||
          !LatticeCombinatorics.integer?(vertex[1]))
        raise "lattice polygon coordinates must be integers"
      @vertices.push([vertex[0], vertex[1]])
    raise "lattice polygon must have positive area" if double_area == 0

  -> vertices
    LatticeCombinatorics.copy_matrix(@vertices)

  -> double_area
    signed = 0
    i = 0
    while i < @vertices.size
      next_index = (i + 1) % @vertices.size
      signed += @vertices[i][0] * @vertices[next_index][1]
      signed -= @vertices[i][1] * @vertices[next_index][0]
      i += 1
    signed.abs

  -> area
    Rational.new(double_area, 2)

  -> boundary_lattice_point_count
    count = 0
    i = 0
    while i < @vertices.size
      next_index = (i + 1) % @vertices.size
      dx = (@vertices[next_index][0] - @vertices[i][0]).abs
      dy = (@vertices[next_index][1] - @vertices[i][1]).abs
      count += dx.gcd(dy)
      i += 1
    count

  # Pick's theorem, exact for a simple lattice polygon supplied in boundary
  # order.  General polygon validation is intentionally outside this class.
  -> interior_lattice_point_count
    numerator = double_area - boundary_lattice_point_count + 2
    if numerator < 0 || numerator % 2 != 0
      raise "ordered vertices do not define a valid simple lattice polygon"
    numerator / 2


+ CenteredEhrhartSimplex
  -> new(dimension)
    @dimension = LatticeCombinatorics.positive_integer(
      dimension, "centered simplex dimension")

  -> dimension
    @dimension

  -> vertices
    base = []
    @dimension.times -> base.push(-1)
    out = [base]
    coordinate = 0
    while coordinate < @dimension
      vertex = []
      i = 0
      while i < @dimension
        vertex.push(i == coordinate ? @dimension : -1)
        i += 1
      out.push(vertex)
      coordinate += 1
    out

  -> simplex
    LatticeSimplex.new(vertices)

  -> barycenter
    simplex.barycenter

  -> normalized_volume
    (@dimension + 1) ** @dimension

  -> volume
    Rational.new(normalized_volume, @dimension.factorial)

  -> lattice_point_count(dilation)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "simplex dilation")
    LatticeCombinatorics.binomial(
      (@dimension + 1) * k + @dimension, @dimension)

  -> interior_lattice_point_count(dilation)
    k = LatticeCombinatorics.positive_integer(
      dilation, "simplex dilation")
    LatticeCombinatorics.binomial(
      (@dimension + 1) * k - 1, @dimension)

  -> jet_condition_count(order)
    j = LatticeCombinatorics.nonnegative_integer(order, "jet order")
    return 0 if j == 0
    LatticeCombinatorics.binomial(@dimension + j - 1, @dimension)

  -> unique_level_one_interior_lattice_point?
    interior_lattice_point_count(1) == 1


+ DiagonalShellPolytope
  # This is the (d-1)-dimensional quotient of the d-dimensional three-sided
  # shell along the diagonal.  Its lattice points satisfy
  # max(0,u_i)-min(0,u_i) <= k.
  -> new(shell_dimension)
    @shell_dimension = LatticeCombinatorics.positive_integer(
      shell_dimension, "shell dimension")
    if @shell_dimension < 2
      raise "diagonal shell polytope needs shell dimension at least two"

  -> shell_dimension
    @shell_dimension

  -> dimension
    @shell_dimension - 1

  -> lattice_point?(point, dilation = 1)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "shell dilation")
    if point.class_name != "Array" || point.size != dimension
      raise "point dimension does not match shell quotient"
    largest = 0
    smallest = 0
    point.each -> (coordinate)
      if !LatticeCombinatorics.integer?(coordinate)
        raise "shell quotient lattice points need integer coordinates"
      largest = coordinate if coordinate > largest
      smallest = coordinate if coordinate < smallest
    largest - smallest <= k

  -> interior_lattice_point?(point, dilation = 1)
    k = LatticeCombinatorics.positive_integer(
      dilation, "shell dilation")
    lattice_point?(point, k - 1)

  -> vertices
    out = []
    mask = 1
    limit = 1 << dimension
    while mask < limit
      positive = []
      negative = []
      coordinate = 0
      while coordinate < dimension
        bit = (mask >> coordinate) & 1
        positive.push(bit)
        negative.push(0 - bit)
        coordinate += 1
      out.push(positive)
      out.push(negative)
      mask += 1
    out

  -> lattice_point_count(dilation)
    k = LatticeCombinatorics.nonnegative_integer(
      dilation, "shell dilation")
    (k + 1) ** @shell_dimension - k ** @shell_dimension

  -> shell_count(dilation)
    lattice_point_count(dilation)

  -> interior_lattice_point_count(dilation)
    k = LatticeCombinatorics.positive_integer(
      dilation, "shell dilation")
    k ** @shell_dimension - (k - 1) ** @shell_dimension

  -> normalized_volume
    @shell_dimension.factorial

  -> volume
    Rational.new(@shell_dimension)

  -> h_star_coefficients
    LatticeCombinatorics.eulerian_coefficients(@shell_dimension)

  -> centrally_symmetric?
    true

  -> reflexive_by_construction?
    primitive_facet_certificate?

  # Facets u_i-u_j<=1 after adjoining the fixed coordinate u_0=0. Each
  # returned entry is [primitive_normal, bound].
  -> primitive_facets
    facets = []
    i = 0
    while i < @shell_dimension
      j = 0
      while j < @shell_dimension
        if i != j
          normal = []
          dimension.times -> normal.push(0)
          normal[i - 1] += 1 if i > 0
          normal[j - 1] -= 1 if j > 0
          facets.push([normal, 1])
        j += 1
      i += 1
    facets

  -> primitive_facet_certificate?
    primitive_facets.each -> (facet)
      normal = facet[0]
      return false if facet[1] != 1
      divisor = 0
      normal.each -> divisor = divisor.gcd(item.abs)
      return false if divisor != 1
    true

  -> reciprocity_holds?(dilation)
    k = LatticeCombinatorics.positive_integer(
      dilation, "shell dilation")
    signed_negative = ((1 - k) ** @shell_dimension -
                       (0 - k) ** @shell_dimension)
    if dimension.odd?
      signed_negative = 0 - signed_negative
    interior_lattice_point_count(k) == signed_negative


+ LaurentJetFiltration
  -> new(exponents)
    if exponents.class_name != "Array" || exponents.size == 0
      raise "Laurent jet filtration needs exponent vectors"
    @dimension = exponents[0].size
    LatticeCombinatorics.positive_integer(
      @dimension, "Laurent exponent dimension")
    @exponents = []
    seen = {}
    exponents.each -> (exponent)
      if exponent.class_name != "Array" || exponent.size != @dimension
        raise "Laurent exponent vectors have inconsistent dimensions"
      copied = []
      exponent.each -> (power)
        if !LatticeCombinatorics.integer?(power)
          raise "Laurent exponents must be integers"
        copied.push(power)
      key = copied.join(",")
      raise "Laurent exponent vectors must be distinct" if seen[key] != nil
      seen[key] = true
      @exponents.push(copied)

  -> dimension
    @dimension

  -> exponents
    LatticeCombinatorics.copy_matrix(@exponents)

  -> .falling_factorial(exponent, order)
    LatticeCombinatorics.nonnegative_integer(order, "derivative order")
    value = 1
    i = 0
    while i < order
      value *= exponent - i
      i += 1
    value

  -> derivative_at_one(exponent, multi_index)
    if exponent.class_name != "Array" || exponent.size != @dimension
      raise "Laurent exponent has the wrong dimension"
    if multi_index.class_name != "Array" || multi_index.size != @dimension
      raise "Laurent multi-index has the wrong dimension"
    value = 1
    i = 0
    while i < @dimension
      if !LatticeCombinatorics.integer?(exponent[i])
        raise "Laurent exponents must be integers"
      if !LatticeCombinatorics.integer?(multi_index[i]) || multi_index[i] < 0
        raise "Laurent multi-indices must be nonnegative integers"
      value *= LaurentJetFiltration.falling_factorial(
        exponent[i], multi_index[i])
      i += 1
    value

  -> jet_multi_indices(order)
    LatticeCombinatorics.multi_indices_below(@dimension, order)

  -> jet_matrix(order)
    rows = []
    jet_multi_indices(order).each -> (multi_index)
      row = []
      @exponents.each -> (exponent)
        row.push(derivative_at_one(exponent, multi_index))
      rows.push(row)
    rows

  -> jet_rank(order)
    LatticeCombinatorics.rational_rank(jet_matrix(order))

  -> vanishing_subspace_dimension(order)
    @exponents.size - jet_rank(order)

  -> condition_count_bound(order)
    j = LatticeCombinatorics.nonnegative_integer(order, "jet order")
    return 0 if j == 0
    LatticeCombinatorics.binomial(@dimension + j - 1, @dimension)
