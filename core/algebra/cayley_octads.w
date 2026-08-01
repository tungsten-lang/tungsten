# Exact symmetric determinantal representations and Cayley-octad bitangent
# matrices for smooth plane quartics.
#
# For three symmetric 4x4 matrices A0,A1,A2, put
#
#   A(X) = X0*A0 + X1*A1 + X2*A2.
#
# A determinantal representation certifies det(A(X)) = c*f(X), c != 0.  If
# eight points O_i in P3 are common zeros of the corresponding quadrics, then
# O_i^t A(X) O_j is a bitangent for every i != j.  The resulting symmetric
# 8x8 matrix has zero diagonal and rank four.  This file checks all of those
# identities exactly; it does not infer a field of definition or a Galois
# descent datum for an octad that was not supplied.


+ Curve
  # Whether a nonzero line cuts a plane quartic in twice a degree-two divisor
  # over the algebraic closure.  No square roots are needed.  For
  #
  #   a U^4 + b U^3 V + c U^2 V^2 + d U V^3 + e V^4,
  #
  # the two identities below eliminate the coefficients of the square root
  # on the open set a != 0.  The remaining branches handle a = 0 exactly.
  -> geometric_bitangent_line?(line)
    return false if line.class_name != "Line" || line.space != @space
    return false if degree != 4 || field.characteristic == 2
    restricted = @equation.restrict_to(line)
    return false if restricted.zero?
    coefficients = binary_quartic_coefficients(restricted)
    a = coefficients[0]
    b = coefficients[1]
    c = coefficients[2]
    d = coefficients[3]
    e = coefficients[4]
    if !field.zero?(a)
      n = field.subtract(
        field.multiply(field.coerce(4), field.multiply(a, c)),
        field.multiply(b, b))
      left_d = field.multiply(
        field.coerce(8),
        field.multiply(field.multiply(a, a), d))
      right_d = field.multiply(b, n)
      return false if !field.equal?(left_d, right_d)
      left_e = field.multiply(
        field.coerce(64),
        field.multiply(field.multiply(field.multiply(a, a), a), e))
      right_e = field.multiply(n, n)
      return field.equal?(left_e, right_e)

    return false if !field.zero?(b)
    if !field.zero?(c)
      return field.equal?(
        field.multiply(d, d),
        field.multiply(field.coerce(4), field.multiply(c, e)))
    return false if !field.zero?(d)
    !field.zero?(e)


+ PlaneQuarticSymmetricDeterminantalRepresentationCertificate
  -> new(@representation)
    @verified_cache = nil

  -> representation
    @representation

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
    expected = "PlaneQuarticSymmetricDeterminantalRepresentation"
    return false if @representation.class_name != expected
    curve = @representation.curve
    return false if curve.class_name != "Curve"
    return false if curve.space.dimension != 2 || curve.degree != 4
    return false if curve.field.characteristic == 2
    return false if !curve.nonsingular?
    return false if !@representation.matrix_payload_valid?
    determinant = @representation.determinant
    return false if determinant.zero?
    return false if !determinant.homogeneous? || determinant.degree != 4
    scalar = @representation.determinant_scalar
    return false if scalar == nil || curve.field.zero?(scalar)
    scale = curve.space.ring.monomial_raw(
      scalar, curve.space.ring.zero_exponents)
    determinant.eql?(curve.equation * scale)

  -> certified?
    verified?

  -> proof_kind
    :exact_polynomial_identity

  -> kernel_checked?
    true


+ PlaneQuarticSymmetricDeterminantalRepresentation
  -> new(@curve, matrices)
    initialize_representation(matrices, false)

  -> new(@curve, matrices, raw)
    initialize_representation(matrices, raw)

  -> .raw(curve, matrices)
    PlaneQuarticSymmetricDeterminantalRepresentation.new(
      curve, matrices, true)

  -> initialize_representation(matrices, raw)
    @matrices = []
    if matrices.class_name == "Array"
      matrices.each -> (source_matrix)
        matrix = []
        if source_matrix.class_name == "Array"
          source_matrix.each -> (source_row)
            row = []
            if source_row.class_name == "Array"
              source_row.each -> (entry)
                value = raw ? @curve.field.normalize_element(entry) : (
                  @curve.field.coerce(entry))
                row.push(value)
            matrix.push(row)
        @matrices.push(matrix)
    @generic_matrix_cache = nil
    @determinant_cache = nil
    @determinant_scalar_cache = nil
    @certificate_cache = PlaneQuarticSymmetricDeterminantalRepresentationCertificate.new(self)

  -> curve
    @curve

  -> matrices
    out = []
    @matrices.each -> (matrix)
      copied = []
      matrix.each -> (row)
        copied_row = []
        row.each -> copied_row.push(item)
        copied.push(copied_row)
      out.push(copied)
    out

  -> matrix_payload_valid?
    return false if @matrices.size != 3
    matrix_index = 0
    while matrix_index < 3
      matrix = @matrices[matrix_index]
      return false if matrix.size != 4
      row = 0
      while row < 4
        return false if matrix[row].size != 4
        column = 0
        while column < 4
          return false if !@curve.field.equal?(
            matrix[row][column], matrix[column][row])
          column += 1
        row += 1
      matrix_index += 1
    true

  -> generic_matrix
    if @generic_matrix_cache == nil
      @generic_matrix_cache = []
      coordinates = @curve.space.coords
      row = 0
      while row < 4
        output_row = []
        column = 0
        while column < 4
          entry = @curve.space.ring.zero
          matrix_index = 0
          while matrix_index < 3
            scalar = @curve.space.ring.monomial_raw(
              @matrices[matrix_index][row][column],
              @curve.space.ring.zero_exponents)
            entry = entry + coordinates[matrix_index] * scalar
            matrix_index += 1
          output_row.push(entry)
          column += 1
        @generic_matrix_cache.push(output_row)
        row += 1
    out = []
    @generic_matrix_cache.each -> (row)
      copied = []
      row.each -> copied.push(item)
      out.push(copied)
    out

  -> determinant
    if @determinant_cache == nil
      @determinant_cache = Polynomial.polynomial_bareiss_determinant(
        generic_matrix, @curve.space.ring)
    @determinant_cache

  -> determinant_scalar
    return @determinant_scalar_cache if @determinant_scalar_cache != nil
    target = @curve.equation
    candidate = determinant
    scalar = nil
    target.each_term -> (coefficient, exponents)
      if scalar == nil
        candidate_coefficient = candidate.coeff(exponents)
        scalar = @curve.field.divide(candidate_coefficient, coefficient)
    return nil if scalar == nil || @curve.field.zero?(scalar)
    scale = @curve.space.ring.monomial_raw(
      scalar, @curve.space.ring.zero_exponents)
    return nil if !candidate.eql?(target * scale)
    @determinant_scalar_cache = scalar
    scalar

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> cayley_octad(points)
    CayleyOctadBitangentMatrix.new(self, points)


+ CayleyOctadBitangentMatrixCertificate
  -> new(@bitangent_matrix)
    @verified_cache = nil

  -> bitangent_matrix
    @bitangent_matrix

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
    expected = "CayleyOctadBitangentMatrix"
    return false if @bitangent_matrix.class_name != expected
    representation = @bitangent_matrix.representation
    return false if !representation.certificate.verified?
    return false if !@bitangent_matrix.point_payload_valid?
    return false if !@bitangent_matrix.points_are_distinct?
    return false if !@bitangent_matrix.points_are_common_quadric_zeros?
    # Every four octad points span P3.  Besides excluding degenerate supplied
    # configurations, this proves every principal 4x4 bitangent minor is a
    # nonzero scalar multiple of the quartic.
    return false if !@bitangent_matrix.every_four_points_span?
    lines = @bitangent_matrix.bitangent_lines
    return false if lines.size != 28
    i = 0
    while i < lines.size
      return false if !representation.curve.geometric_bitangent_line?(lines[i])
      j = 0
      while j < i
        return false if lines[i].eql?(lines[j])
        j += 1
      i += 1
    @bitangent_matrix.principal_minors_replay_quartic?

  -> certified?
    verified?

  -> proof_kind
    :exact_cayley_octad_replay

  -> kernel_checked?
    true

  # The complete-intersection implication uses the classical Cayley-octad
  # theorem after the exact smoothness, base-locus, and general-position
  # checks above.  Keep that trust boundary visible to downstream proofs.
  -> complete_intersection_theorem
    "a regular net of quadrics has a Cayley octad base locus and Hesse quartic"

  -> complete_intersection_kernel_checked?
    false


+ CayleyOctadBitangentMatrix
  -> new(@representation, points)
    @points = []
    if points.class_name == "Array"
      points.each -> @points.push(item)
    @bitangent_lines_cache = nil
    @bitangent_matrix_cache = nil
    @certificate_cache = CayleyOctadBitangentMatrixCertificate.new(self)

  -> representation
    @representation

  -> curve
    @representation.curve

  -> points
    out = []
    @points.each -> out.push(item)
    out

  -> point_payload_valid?
    return false if @points.size != 8
    space = @points[0].space
    return false if space.dimension != 3
    return false if space.field != curve.field
    @points.all? -> item.class_name == "ProjectivePoint" && item.space == space

  -> points_are_distinct?
    i = 0
    while i < @points.size
      j = 0
      while j < i
        return false if @points[i] == @points[j]
        j += 1
      i += 1
    true

  -> bilinear_value(matrix, left, right)
    field = curve.field
    answer = field.zero
    row = 0
    while row < 4
      column = 0
      while column < 4
        term = field.multiply(left.coordinates[row], matrix[row][column])
        term = field.multiply(term, right.coordinates[column])
        answer = field.add(answer, term)
        column += 1
      row += 1
    answer

  -> points_are_common_quadric_zeros?
    matrices = @representation.matrices
    point_index = 0
    while point_index < @points.size
      matrix_index = 0
      while matrix_index < matrices.size
        value = bilinear_value(
          matrices[matrix_index],
          @points[point_index], @points[point_index])
        return false if !curve.field.zero?(value)
        matrix_index += 1
      point_index += 1
    true

  -> four_point_indices
    out = []
    a = 0
    while a < 8
      b = a + 1
      while b < 8
        c = b + 1
        while c < 8
          d = c + 1
          while d < 8
            out.push([a, b, c, d])
            d += 1
          c += 1
        b += 1
      a += 1
    out

  -> point_coordinate_minor(indices)
    matrix = []
    indices.each -> (index)
      matrix.push(@points[index].coordinates)
    Algebra.determinant_raw(matrix, curve.field)

  -> every_four_points_span?
    four_point_indices.all? ->
      !self.curve.field.zero?(self.point_coordinate_minor(item))

  -> bitangent_coefficients(left_index, right_index)
    matrices = @representation.matrices
    out = []
    matrix_index = 0
    while matrix_index < matrices.size
      out.push(bilinear_value(
        matrices[matrix_index],
        @points[left_index], @points[right_index]))
      matrix_index += 1
    out

  -> bitangent_line(left_index, right_index)
    if left_index == right_index
      raise "a Cayley-octad diagonal is zero, not a line"
    Line.raw(curve.space,
             bitangent_coefficients(left_index, right_index))

  -> bitangent_lines
    if @bitangent_lines_cache == nil
      @bitangent_lines_cache = []
      i = 0
      while i < 8
        j = i + 1
        while j < 8
          @bitangent_lines_cache.push(bitangent_line(i, j))
          j += 1
        i += 1
    out = []
    @bitangent_lines_cache.each -> out.push(item)
    out

  -> bitangent_matrix
    if @bitangent_matrix_cache == nil
      @bitangent_matrix_cache = []
      i = 0
      while i < 8
        row = []
        j = 0
        while j < 8
          if i == j
            row.push(curve.space.ring.zero)
          else
            coefficients = bitangent_coefficients(i, j)
            entry = curve.space.ring.zero
            k = 0
            while k < 3
              entry = entry + curve.space.coords[k] * coefficients[k]
              k += 1
            row.push(entry)
          j += 1
        @bitangent_matrix_cache.push(row)
        i += 1
    out = []
    @bitangent_matrix_cache.each -> (row)
      copied = []
      row.each -> copied.push(item)
      out.push(copied)
    out

  -> principal_minor(indices)
    source = bitangent_matrix
    matrix = []
    indices.each -> (row_index)
      row = []
      indices.each -> (column_index)
        row.push(source[row_index][column_index])
      matrix.push(row)
    Polynomial.polynomial_bareiss_determinant(
      matrix, curve.space.ring)

  -> principal_minors_replay_quartic?
    field = curve.field
    expected_scalar = @representation.determinant_scalar
    four_point_indices.all? -> (indices)
      coordinate_determinant = self.point_coordinate_minor(indices)
      scalar = field.multiply(
        expected_scalar,
        field.multiply(coordinate_determinant, coordinate_determinant))
      scale_polynomial = self.curve.space.ring.monomial_raw(
        scalar, self.curve.space.ring.zero_exponents)
      self.principal_minor(indices).eql?(
        self.curve.equation * scale_polynomial)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


# Canonical exact row reduction used by the octad-to-net producer.  The
# returned vectors form a basis of the right kernel of the supplied matrix.
+ CayleyOctadLinearAlgebra
  -> .right_nullspace(field, matrix, width = nil)
    column_count = width
    if column_count == nil
      column_count = matrix.size == 0 ? 0 : matrix[0].size
    work = []
    matrix.each -> (source_row)
      if source_row.class_name != "Array" || source_row.size != column_count
        raise "Cayley-octad row reduction received a ragged matrix"
      row = []
      source_row.each -> row.push(field.normalize_element(item))
      work.push(row)

    pivot_columns = []
    pivot_row = 0
    column = 0
    while column < column_count && pivot_row < work.size
      selected = pivot_row
      while selected < work.size && field.zero?(work[selected][column])
        selected += 1
      if selected < work.size
        if selected != pivot_row
          temporary = work[pivot_row]
          work[pivot_row] = work[selected]
          work[selected] = temporary
        inverse = field.inverse(work[pivot_row][column])
        j = 0
        while j < column_count
          work[pivot_row][j] = field.multiply(
            work[pivot_row][j], inverse)
          j += 1
        row_index = 0
        while row_index < work.size
          if row_index != pivot_row
            scale = work[row_index][column]
            if !field.zero?(scale)
              j = 0
              while j < column_count
                product = field.multiply(scale, work[pivot_row][j])
                work[row_index][j] = field.subtract(
                  work[row_index][j], product)
                j += 1
          row_index += 1
        pivot_columns.push(column)
        pivot_row += 1
      column += 1

    free_columns = []
    column = 0
    while column < column_count
      free_columns.push(column) if !pivot_columns.include?(column)
      column += 1
    basis = []
    free_columns.each -> (free_column)
      vector = []
      column_count.times -> vector.push(field.zero)
      vector[free_column] = field.one
      row_index = 0
      while row_index < pivot_columns.size
        vector[pivot_columns[row_index]] = field.negate(
          work[row_index][free_column])
        row_index += 1
      basis.push(vector)
    basis

  -> .matrix_vector_product(field, matrix, vector)
    out = []
    matrix.each -> (row)
      value = field.zero
      column = 0
      while column < row.size
        value = field.add(
          value, field.multiply(row[column], vector[column]))
        column += 1
      out.push(value)
    out


+ CayleyOctadNetCertificate
  -> new(@net)
    @verified_cache = nil

  -> net
    @net

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
    return false if @net.class_name != "CayleyOctadNet"
    return false if !@net.input_payload_valid?
    evaluation = @net.evaluation_matrix
    basis = @net.net_basis_vectors
    return false if basis.size != 3
    field = @net.field
    basis.each -> (vector)
      return false if vector.size != 10
      product = CayleyOctadLinearAlgebra.matrix_vector_product(
        field, evaluation, vector)
      return false if product.any? -> !field.zero?(item)
    return false if !@net.representation.certificate.verified?
    @net.bitangent_matrix.certificate.verified?

  -> certified?
    verified?

  -> proof_kind
    :exact_octad_net_nullspace

  -> kernel_checked?
    true


# Construct the three-dimensional net of quadrics through eight supplied P3
# points.  The caller supplies the P2 parameter space so its exact field-family
# tag and coordinate names remain explicit in Tungsten's type surface.
+ CayleyOctadNet
  -> new(points, @parameter_space)
    @points = []
    if points.class_name == "Array"
      points.each -> @points.push(item)
    @evaluation_matrix_cache = nil
    @net_basis_vectors_cache = nil
    @matrices_cache = nil
    @representation_cache = nil
    @bitangent_matrix_cache = nil
    @certificate_cache = CayleyOctadNetCertificate.new(self)

  -> points
    out = []
    @points.each -> out.push(item)
    out

  -> parameter_space
    @parameter_space

  -> field
    @parameter_space.field

  -> input_payload_valid?
    return false if @points.size != 8
    return false if @parameter_space.dimension != 2
    source_space = @points[0].space
    return false if source_space.dimension != 3
    return false if source_space.field != field
    i = 0
    while i < @points.size
      return false if @points[i].class_name != "ProjectivePoint"
      return false if @points[i].space != source_space
      j = 0
      while j < i
        return false if @points[i] == @points[j]
        j += 1
      i += 1
    true

  -> quadratic_evaluation_row(point)
    f = field
    u = point.coordinates
    two = f.coerce(2)
    [
      f.multiply(u[0], u[0]),
      f.multiply(two, f.multiply(u[0], u[1])),
      f.multiply(two, f.multiply(u[0], u[2])),
      f.multiply(two, f.multiply(u[0], u[3])),
      f.multiply(u[1], u[1]),
      f.multiply(two, f.multiply(u[1], u[2])),
      f.multiply(two, f.multiply(u[1], u[3])),
      f.multiply(u[2], u[2]),
      f.multiply(two, f.multiply(u[2], u[3])),
      f.multiply(u[3], u[3])
    ]

  -> evaluation_matrix
    if @evaluation_matrix_cache == nil
      @evaluation_matrix_cache = []
      @points.each -> @evaluation_matrix_cache.push(
        quadratic_evaluation_row(item))
    out = []
    @evaluation_matrix_cache.each -> (row)
      copied = []
      row.each -> copied.push(item)
      out.push(copied)
    out

  -> net_basis_vectors
    if @net_basis_vectors_cache == nil
      @net_basis_vectors_cache = CayleyOctadLinearAlgebra.right_nullspace(
        field, evaluation_matrix, 10)
    out = []
    @net_basis_vectors_cache.each -> (vector)
      copied = []
      vector.each -> copied.push(item)
      out.push(copied)
    out

  -> symmetric_matrix_from_vector(vector)
    [
      [vector[0], vector[1], vector[2], vector[3]],
      [vector[1], vector[4], vector[5], vector[6]],
      [vector[2], vector[5], vector[7], vector[8]],
      [vector[3], vector[6], vector[8], vector[9]]
    ]

  -> matrices
    if @matrices_cache == nil
      @matrices_cache = []
      net_basis_vectors.each ->
        @matrices_cache.push(symmetric_matrix_from_vector(item))
    out = []
    @matrices_cache.each -> (matrix)
      copied_matrix = []
      matrix.each -> (row)
        copied_row = []
        row.each -> copied_row.push(item)
        copied_matrix.push(copied_row)
      out.push(copied_matrix)
    out

  -> representation
    if @representation_cache == nil
      # First form the determinant without presupposing a Curve object.
      coordinates = @parameter_space.coords
      generic = []
      row = 0
      while row < 4
        output_row = []
        column = 0
        while column < 4
          value = @parameter_space.ring.zero
          index = 0
          while index < 3
            value = value + coordinates[index] * matrices[index][row][column]
            index += 1
          output_row.push(value)
          column += 1
        generic.push(output_row)
        row += 1
      determinant = Polynomial.polynomial_bareiss_determinant(
        generic, @parameter_space.ring)
      curve = Curve.new(@parameter_space, determinant)
      @representation_cache = (
        PlaneQuarticSymmetricDeterminantalRepresentation.new(
          curve, matrices))
    @representation_cache

  -> curve
    representation.curve

  -> bitangent_matrix
    if @bitangent_matrix_cache == nil
      @bitangent_matrix_cache = representation.cayley_octad(@points)
    @bitangent_matrix_cache

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


# Elsenhans--Jahnel's trace-zero etale construction.  For a separable monic
#
#   f(t) = t^8 + a6*t^6 + ... + a0
#
# the eight geometric points (1:r:r^2:r^4), one for each root r, are the base
# locus of the following three quadrics.  We keep the points in the finite
# etale algebra K[t]/(f), so the net and its Hesse quartic are constructed over
# K without materializing a splitting field.
+ TraceZeroEtaleCayleyOctadCertificate
  -> new(@construction)
    @verified_cache = nil

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
    expected = "TraceZeroEtaleCayleyOctad"
    return false if @construction.class_name != expected
    polynomial = @construction.polynomial
    return false if polynomial.class_name != "Polynomial"
    return false if polynomial.ring.arity != 1 || polynomial.degree != 8
    return false if !polynomial.eql?(polynomial.monic)
    field = polynomial.ring.field
    return false if field.characteristic == 2
    return false if !field.zero?(polynomial.coeff([7]))
    algebra = @construction.etale_algebra
    return false if !algebra.certificate.verified?
    return false if algebra.dimension != 8
    return false if !algebra.generator.trace.zero?

    matrices = @construction.matrices
    expected_matrices = @construction.recompute_matrices
    return false if matrices.to_s != expected_matrices.to_s
    point = @construction.universal_point
    return false if point.size != 4
    matrices.each -> (matrix)
      return false if !@construction.quadratic_value(matrix, point).zero?

    @construction.representation.certificate.verified?

  -> certified?
    verified?

  -> proof_kind
    :exact_trace_zero_etale_octad_net

  -> kernel_checked?
    true

  -> theorem
    "the conjugates of (1:alpha:alpha^2:alpha^4) form a Galois-invariant Cayley octad"

  -> theorem_reference
    "Elsenhans-Jahnel, Proposition 2.6"

  -> geometric_octad_theorem_kernel_checked?
    false


+ TraceZeroEtaleCayleyOctad
  -> new(@polynomial, @parameter_space, components = [])
    @components = []
    if components.class_name == "Array"
      components.each -> @components.push(item)
    @etale_algebra = EtaleAlgebra.new(@polynomial, @components)
    @matrices_cache = nil
    @representation_cache = nil
    @certificate_cache = TraceZeroEtaleCayleyOctadCertificate.new(self)

  -> polynomial
    @polynomial

  -> parameter_space
    @parameter_space

  -> etale_algebra
    @etale_algebra

  -> components
    out = []
    @components.each -> out.push(item)
    out

  -> component_degrees
    out = []
    @components.each -> out.push(item.degree)
    out

  -> universal_point
    alpha = @etale_algebra.generator
    [@etale_algebra.one, alpha, alpha**2, alpha**4]

  -> recompute_matrices
    field = @polynomial.ring.field
    half = field.inverse(field.coerce(2))
    minus_half = field.negate(half)
    zero = field.zero
    one = field.one
    q1 = [
      [zero, zero, minus_half, zero],
      [zero, one, zero, zero],
      [minus_half, zero, zero, zero],
      [zero, zero, zero, zero]
    ]
    q2 = [
      [zero, zero, zero, minus_half],
      [zero, zero, zero, zero],
      [zero, zero, one, zero],
      [minus_half, zero, zero, zero]
    ]
    a0 = @polynomial.coeff([0])
    a1 = @polynomial.coeff([1])
    a2 = @polynomial.coeff([2])
    a3 = @polynomial.coeff([3])
    a4 = @polynomial.coeff([4])
    a5 = @polynomial.coeff([5])
    a6 = @polynomial.coeff([6])
    q3 = [
      [a0, field.multiply(a1, half),
       field.multiply(a2, half), field.multiply(a4, half)],
      [field.multiply(a1, half), zero,
       field.multiply(a3, half), field.multiply(a5, half)],
      [field.multiply(a2, half), field.multiply(a3, half),
       zero, field.multiply(a6, half)],
      [field.multiply(a4, half), field.multiply(a5, half),
       field.multiply(a6, half), one]
    ]
    [q1, q2, q3]

  -> matrices
    @matrices_cache = recompute_matrices if @matrices_cache == nil
    out = []
    @matrices_cache.each -> (matrix)
      copied = []
      matrix.each -> (row)
        copied_row = []
        row.each -> copied_row.push(item)
        copied.push(copied_row)
      out.push(copied)
    out

  -> quadratic_value(matrix, point)
    algebra = @etale_algebra
    answer = algebra.zero
    row = 0
    while row < 4
      column = 0
      while column < 4
        term = point[row] * algebra.coerce(matrix[row][column])
        term = term * point[column]
        answer = answer + term
        column += 1
      row += 1
    answer

  -> representation
    if @representation_cache == nil
      if @parameter_space.dimension != 2 || (
         @parameter_space.field != @polynomial.ring.field)
        raise "trace-zero octad needs a matching projective parameter plane"
      coordinates = @parameter_space.coords
      generic = []
      row = 0
      while row < 4
        output_row = []
        column = 0
        while column < 4
          value = @parameter_space.ring.zero
          index = 0
          while index < 3
            value = value + coordinates[index] * matrices[index][row][column]
            index += 1
          output_row.push(value)
          column += 1
        generic.push(output_row)
        row += 1
      determinant = Polynomial.polynomial_bareiss_determinant(
        generic, @parameter_space.ring)
      curve = Curve.new(@parameter_space, determinant)
      @representation_cache = (
        PlaneQuarticSymmetricDeterminantalRepresentation.new(
          curve, matrices))
    @representation_cache

  -> curve
    representation.curve

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ Algebra
  -> .trace_zero_cayley_octad(polynomial, parameter_space, components = [])
    TraceZeroEtaleCayleyOctad.new(
      polynomial, parameter_space, components)
