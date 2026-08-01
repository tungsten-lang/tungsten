# Constructive Dixon representations for smooth plane quartics.
#
# Given an azygetic triple of bitangents l1,l2,l3, Dixon starts with the
# contact cubic v00=l1*l2*l3.  The four-dimensional space of cubics through
# the six contact points is recovered here without materializing those points:
# on each line, the binary restriction of a cubic must be divisible by the
# certified contact quadratic.  This turns the radical-ideal step in the
# classical presentation into exact linear algebra over the coefficient field.
#
# The remaining identities
#
#   v0i*v0j = v00*vij + f*hij
#
# are affine linear solves in the coefficients of a cubic vij and a quadratic
# hij.  The adjugate of V divided by f^2 is then checked entry by entry and
# passed to PlaneQuarticSymmetricDeterminantalRepresentation, whose certificate
# replays det(W)=c*f exactly.  Thus a successful result is kernel checked; the
# classical theorem is needed only to promise success for every azygetic input.


+ CayleyOctadLinearAlgebra
  # Solve matrix*x=target.  The first null vector of [matrix|-target] whose
  # homogeneous coordinate is nonzero gives a deterministic exact solution.
  -> .solve_affine(field, matrix, target, width = nil)
    if matrix.size != target.size
      raise "affine row reduction has the wrong target height"
    column_count = width
    if column_count == nil
      column_count = matrix.size == 0 ? 0 : matrix[0].size
    augmented = []
    row_index = 0
    while row_index < matrix.size
      row = []
      matrix[row_index].each -> row.push(item)
      if row.size != column_count
        raise "affine row reduction received a ragged matrix"
      row.push(field.negate(target[row_index]))
      augmented.push(row)
      row_index += 1
    kernel = right_nullspace(field, augmented, column_count + 1)
    kernel.each -> (candidate)
      scale = candidate[column_count]
      if !field.zero?(scale)
        inverse = field.inverse(scale)
        answer = []
        column = 0
        while column < column_count
          answer.push(field.multiply(candidate[column], inverse))
          column += 1
        return answer
    raise "affine linear system is inconsistent"

  -> .row_rank(field, matrix, width = nil)
    column_count = width
    if column_count == nil
      column_count = matrix.size == 0 ? 0 : matrix[0].size
    column_count - right_nullspace(field, matrix, column_count).size

  -> .identity_matrix(field, size)
    out = []
    row = 0
    while row < size
      target_row = []
      column = 0
      while column < size
        target_row.push(row == column ? field.one : field.zero)
        column += 1
      out.push(target_row)
      row += 1
    out

  -> .zero_matrix(field, rows, columns)
    out = []
    row = 0
    while row < rows
      target_row = []
      columns.times -> target_row.push(field.zero)
      out.push(target_row)
      row += 1
    out

  -> .transpose(matrix)
    return [] if matrix.size == 0
    out = []
    column = 0
    while column < matrix[0].size
      row_out = []
      row = 0
      while row < matrix.size
        row_out.push(matrix[row][column])
        row += 1
      out.push(row_out)
      column += 1
    out

  -> .matrix_multiply(field, left, right)
    if left.size == 0 || right.size == 0
      raise "matrix multiplication needs nonempty matrices"
    inner = left[0].size
    if right.size != inner
      raise "matrix multiplication dimensions do not agree"
    out = []
    row = 0
    while row < left.size
      target_row = []
      column = 0
      while column < right[0].size
        value = field.zero
        k = 0
        while k < inner
          value = field.add(
            value, field.multiply(left[row][k], right[k][column]))
          k += 1
        target_row.push(value)
        column += 1
      out.push(target_row)
      row += 1
    out

  -> .matrix_add(field, left, right)
    if left.size != right.size
      raise "matrix addition heights do not agree"
    out = []
    row = 0
    while row < left.size
      if left[row].size != right[row].size
        raise "matrix addition widths do not agree"
      target_row = []
      column = 0
      while column < left[row].size
        target_row.push(field.add(
          left[row][column], right[row][column]))
        column += 1
      out.push(target_row)
      row += 1
    out

  -> .matrix_scale(field, matrix, scalar)
    out = []
    matrix.each -> (source_row)
      row = []
      source_row.each ->
        row.push(field.multiply(scalar, item))
      out.push(row)
    out

  -> .matrix_frobenius(field, matrix, iterations = 1)
    out = []
    matrix.each -> (source_row)
      row = []
      source_row.each ->
        row.push(field.frobenius(item, iterations))
      out.push(row)
    out

  -> .same_matrix?(field, left, right)
    return false if left.size != right.size
    row = 0
    while row < left.size
      return false if left[row].size != right[row].size
      column = 0
      while column < left[row].size
        return false if !field.equal?(
          left[row][column], right[row][column])
        column += 1
      row += 1
    true

  -> .matrix_inverse(field, matrix)
    size = matrix.size
    raise "matrix inverse needs a square matrix" if size == 0
    matrix.each ->
      raise "matrix inverse needs a square matrix" if item.size != size
    columns = []
    column = 0
    while column < size
      target = []
      row = 0
      while row < size
        target.push(row == column ? field.one : field.zero)
        row += 1
      columns.push(solve_affine(field, matrix, target, size))
      column += 1
    transpose(columns)


+ PlaneQuarticDixonRepresentationCertificate
  -> new(@producer)
    @verified_cache = nil

  -> producer
    @producer

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
    expected = "PlaneQuarticDixonRepresentation"
    return false if @producer.class_name != expected
    curve = @producer.curve
    return false if curve.class_name != "Curve"
    return false if curve.space.dimension != 2 || curve.degree != 4
    return false if curve.field.characteristic == 2
    return false if !curve.nonsingular?
    return false if @producer.lines.size != 3
    @producer.lines.each -> (line)
      return false if line.class_name != "Line" || line.space != curve.space
      return false if !curve.geometric_bitangent_line?(line)
    return false if @producer.contact_cubics.size != 4
    return false if @producer.contact_space_dimension != 4
    return false if !@producer.contact_restrictions_replay?
    return false if @producer.relation_certificates.size != 6
    return false if !@producer.relation_certificates.all? -> item.verified?
    return false if @producer.cubic_matrix_determinant.zero?
    return false if !@producer.adjugate_divisions_replay?
    representation = @producer.representation
    return false if representation == nil || !representation.certified?
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_polynomial_identity

  -> kernel_checked?
    true

  -> existence_theorem
    "Dixon's construction succeeds for every azygetic bitangent triple"

  -> existence_theorem_reference
    "Dixon; Plaumann--Sturmfels--Vinzant Algorithm 2.5"

  -> existence_theorem_kernel_checked?
    false


+ PlaneQuarticDixonRepresentation
  -> new(@curve, source_lines)
    @lines = []
    if source_lines.class_name == "Array"
      source_lines.each -> @lines.push(item)
    @degree_two_monomials = MacaulayResultant.degree_monomials(2)
    @degree_three_monomials = MacaulayResultant.degree_monomials(3)
    @degree_six_monomials = MacaulayResultant.degree_monomials(6)
    @contact_quadratics = []
    @contact_cubics = []
    @contact_space_dimension = 0
    @relation_certificates = []
    @cubic_matrix = nil
    @cubic_matrix_determinant = nil
    @linear_matrix = nil
    @representation = nil
    @adjugate_divisions_replay = false
    @certificate_cache = nil
    build if valid_input_shape?
    @certificate_cache = PlaneQuarticDixonRepresentationCertificate.new(self)

  -> curve
    @curve

  -> lines
    out = []
    @lines.each -> out.push(item)
    out

  -> contact_quadratics
    out = []
    @contact_quadratics.each -> out.push(item)
    out

  -> contact_cubics
    out = []
    @contact_cubics.each -> out.push(item)
    out

  -> contact_space_dimension
    @contact_space_dimension

  -> relation_certificates
    out = []
    @relation_certificates.each -> out.push(item)
    out

  -> cubic_matrix
    copy_matrix(@cubic_matrix)

  -> cubic_matrix_determinant
    @cubic_matrix_determinant

  -> linear_matrix
    copy_matrix(@linear_matrix)

  -> representation
    @representation

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> valid_input_shape?
    return false if @curve.class_name != "Curve"
    return false if @lines.size != 3
    @lines.all? -> item.class_name == "Line" && item.space == @curve.space

  -> copy_matrix(source)
    return nil if source == nil
    out = []
    source.each -> (row)
      copied = []
      row.each -> copied.push(item)
      out.push(copied)
    out

  -> polynomial_vector(polynomial, monomials)
    out = []
    monomials.each -> out.push(polynomial.coeff(item))
    out

  -> polynomial_from_vector(vector, monomials)
    ring = @curve.space.ring
    terms = []
    index = 0
    while index < monomials.size
      if !@curve.field.zero?(vector[index])
        terms.push([vector[index], monomials[index]])
      index += 1
    Polynomial.new(ring, terms)

  -> ambient_monomial(exponents)
    @curve.space.ring.monomial_raw(@curve.field.one, exponents)

  # Return [q,scale] with restriction(curve)=scale*q^2.  The coefficient
  # order of q is U^2,UV,V^2 in the line's deterministic parameterization.
  -> contact_quadratic(line)
    restricted = @curve.equation.restrict_to(line)
    coefficients = @curve.binary_quartic_coefficients(restricted)
    field = @curve.field
    a = coefficients[0]
    b = coefficients[1]
    c = coefficients[2]
    d = coefficients[3]
    e = coefficients[4]
    if !field.zero?(a)
      two_a = field.multiply(field.coerce(2), a)
      q1 = field.divide(b, two_a)
      numerator = field.subtract(
        field.multiply(field.coerce(4), field.multiply(a, c)),
        field.multiply(b, b))
      denominator = field.multiply(
        field.coerce(8), field.multiply(a, a))
      q2 = field.divide(numerator, denominator)
      return [[field.one, q1, q2], a]
    if !field.zero?(b)
      raise "bitangent restriction has an impossible cubic leading term"
    if !field.zero?(c)
      q2 = field.divide(d, field.multiply(field.coerce(2), c))
      return [[field.zero, field.one, q2], c]
    if !field.zero?(d)
      raise "bitangent restriction has an impossible linear leading term"
    if field.zero?(e)
      raise "bitangent line is a component of the quartic"
    [[field.zero, field.zero, field.one], e]

  -> binary_quadratic_polynomial(line, coefficients)
    ring = line.parameter_ring
    Polynomial.new(ring, [
      [coefficients[0], [2, 0]],
      [coefficients[1], [1, 1]],
      [coefficients[2], [0, 2]]
    ])

  -> binary_linear_polynomial(line, first, second)
    ring = line.parameter_ring
    Polynomial.new(ring, [
      [first, [1, 0]], [second, [0, 1]]
    ])

  -> contact_space_matrix
    field = @curve.field
    # Unknowns are ten ambient cubic coefficients, followed by two quotient
    # coefficients for each of the three contact quadratics.
    columns = @degree_three_monomials.size + @lines.size*2
    rows = []
    line_index = 0
    while line_index < @lines.size
      line = @lines[line_index]
      q = binary_quadratic_polynomial(
        line, @contact_quadratics[line_index])
      restrictions = []
      @degree_three_monomials.each -> (exponents)
        restrictions.push(line.restrict(ambient_monomial(exponents)))
      quotient_u = q * binary_linear_polynomial(
        line, field.one, field.zero)
      quotient_v = q * binary_linear_polynomial(
        line, field.zero, field.one)
      binary_monomials = [[3,0], [2,1], [1,2], [0,3]]
      binary_monomials.each -> (powers)
        row = []
        restrictions.each -> row.push(item.coeff(powers))
        @lines.size.times ->
          row.push(field.zero)
          row.push(field.zero)
        offset = @degree_three_monomials.size + line_index*2
        row[offset] = field.negate(quotient_u.coeff(powers))
        row[offset + 1] = field.negate(quotient_v.coeff(powers))
        rows.push(row)
      line_index += 1
    rows

  -> extend_contact_basis(kernel)
    field = @curve.field
    v00 = @lines[0].equation * @lines[1].equation * @lines[2].equation
    basis_vectors = [polynomial_vector(v00, @degree_three_monomials)]
    rank = CayleyOctadLinearAlgebra.row_rank(
      field, basis_vectors, @degree_three_monomials.size)
    kernel.each -> (candidate)
      vector = candidate.slice(0, @degree_three_monomials.size)
      trial = []
      basis_vectors.each -> trial.push(item)
      trial.push(vector)
      next_rank = CayleyOctadLinearAlgebra.row_rank(
        field, trial, @degree_three_monomials.size)
      if next_rank > rank
        basis_vectors.push(vector)
        rank = next_rank
    @contact_cubics = []
    basis_vectors.each ->
      @contact_cubics.push(polynomial_from_vector(
        item, @degree_three_monomials))
    if @contact_cubics.size != 4
      raise "Dixon contact-cubic space did not have dimension four"

  -> solve_relation(target)
    ring = @curve.space.ring
    field = @curve.field
    v00 = @contact_cubics[0]
    matrix = []
    @degree_six_monomials.each -> (powers)
      row = []
      @degree_three_monomials.each -> (cubic_powers)
        row.push((v00 * ambient_monomial(cubic_powers)).coeff(powers))
      @degree_two_monomials.each -> (quadratic_powers)
        row.push((@curve.equation * ambient_monomial(quadratic_powers)).coeff(powers))
      matrix.push(row)
    target_vector = polynomial_vector(target, @degree_six_monomials)
    solution = CayleyOctadLinearAlgebra.solve_affine(
      field, matrix, target_vector,
      @degree_three_monomials.size + @degree_two_monomials.size)
    cubic = polynomial_from_vector(
      solution.slice(0, @degree_three_monomials.size),
      @degree_three_monomials)
    quadratic = polynomial_from_vector(
      solution.slice(
        @degree_three_monomials.size, @degree_two_monomials.size),
      @degree_two_monomials)
    difference = target - v00*cubic
    certificate = PolynomialIdealMembershipCertificate.new(
      difference, [@curve.equation], [quadratic])
    if !certificate.verified?
      raise "Dixon relation failed exact replay"
    [cubic, certificate]

  -> build_cubic_matrix
    matrix = []
    4.times ->
      row = []
      4.times -> row.push(@curve.space.ring.zero)
      matrix.push(row)
    i = 0
    while i < 4
      matrix[0][i] = @contact_cubics[i]
      matrix[i][0] = @contact_cubics[i]
      i += 1
    i = 1
    while i < 4
      j = i
      while j < 4
        solved = solve_relation(@contact_cubics[i] * @contact_cubics[j])
        matrix[i][j] = solved[0]
        matrix[j][i] = solved[0]
        @relation_certificates.push(solved[1])
        j += 1
      i += 1
    @cubic_matrix = matrix
    @cubic_matrix_determinant = Polynomial.polynomial_bareiss_determinant(
      @cubic_matrix, @curve.space.ring)

  -> minor_matrix(source, omitted_row, omitted_column)
    out = []
    row = 0
    while row < source.size
      if row != omitted_row
        target_row = []
        column = 0
        while column < source.size
          target_row.push(source[row][column]) if column != omitted_column
          column += 1
        out.push(target_row)
      row += 1
    out

  -> build_linear_adjugate
    ring = @curve.space.ring
    divisor = @curve.equation * @curve.equation
    matrix = []
    row = 0
    while row < 4
      output_row = []
      column = 0
      while column < 4
        # adj(V)[row,column] is cofactor(column,row).
        minor = minor_matrix(@cubic_matrix, column, row)
        cofactor = Polynomial.polynomial_bareiss_determinant(minor, ring)
        cofactor = -cofactor if (row + column) % 2 == 1
        division = cofactor.divide([divisor])
        if !division[1].zero?
          raise "Dixon adjugate entry is not divisible by f^2"
        entry = division[0][0]
        if !entry.zero? && (!entry.homogeneous? || entry.degree != 1)
          raise "Dixon adjugate quotient is not linear"
        output_row.push(entry)
        column += 1
      matrix.push(output_row)
      row += 1
    @linear_matrix = matrix
    @adjugate_divisions_replay = true

  -> build_representation
    coefficient_matrices = []
    variable = 0
    while variable < 3
      matrix = []
      row = 0
      while row < 4
        output_row = []
        column = 0
        while column < 4
          powers = [0, 0, 0]
          powers[variable] = 1
          output_row.push(@linear_matrix[row][column].coeff(powers))
          column += 1
        matrix.push(output_row)
        row += 1
      coefficient_matrices.push(matrix)
      variable += 1
    @representation = PlaneQuarticSymmetricDeterminantalRepresentation.raw(
      @curve, coefficient_matrices)

  -> build
    @lines.each -> (line)
      data = contact_quadratic(line)
      @contact_quadratics.push(data[0])
      q = binary_quadratic_polynomial(line, data[0])
      restricted = @curve.equation.restrict_to(line)
      scale = line.parameter_ring.monomial_raw(
        data[1], line.parameter_ring.zero_exponents)
      if restricted != q*q*scale
        raise "Dixon input line does not have an exact contact quadratic"
    contact_matrix = contact_space_matrix
    kernel = CayleyOctadLinearAlgebra.right_nullspace(
      @curve.field, contact_matrix,
      @degree_three_monomials.size + @lines.size*2)
    @contact_space_dimension = kernel.size
    extend_contact_basis(kernel)
    build_cubic_matrix
    raise "Dixon triple is syzygetic" if @cubic_matrix_determinant.zero?
    build_linear_adjugate
    build_representation

  -> contact_restrictions_replay?
    return false if @contact_cubics.size != 4
    @contact_cubics.each -> (cubic)
      line_index = 0
      while line_index < @lines.size
        restricted = @lines[line_index].restrict(cubic)
        q = binary_quadratic_polynomial(
          @lines[line_index], @contact_quadratics[line_index])
        division = restricted.divide([q])
        return false if !division[1].zero?
        line_index += 1
    true

  -> adjugate_divisions_replay?
    @adjugate_divisions_replay


+ FiniteFieldDeterminantalFrobeniusDescentCertificate
  -> new(@descent)
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
    expected = "FiniteFieldDeterminantalFrobeniusDescent"
    return false if @descent.class_name != expected
    return false if !@descent.source_representation.certified?
    field = @descent.field
    return false if field.class_name != "FiniteField" || field.prime_field?
    return false if @descent.intertwiner_kernel_dimension <= 0
    return false if !@descent.frobenius_congruence_replays?
    return false if !@descent.normalized_cocycle_replays?
    return false if !@descent.normalized_frobenius_congruence_replays?
    return false if !@descent.semilinear_fixed_matrix_replays?
    return false if !@descent.descent_scalar_replays?
    return false if !@descent.descended_entries_in_prime_field?
    return false if !@descent.descended_representation_replays?
    return false if !@descent.representation.certified?
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_field_frobenius_descent

  -> kernel_checked?
    true


# Explicit finite-field descent of a Frobenius-fixed symmetric determinantal
# class.  Simultaneous conjugacy of A^-1*B and A^-1*C finds the congruence
# intertwiner by linear algebra.  Finite-field norm and Hilbert-90 equations
# are then solved by exhaustive field enumeration, producing a matrix over the
# prime field and replaying its determinant there.
+ FiniteFieldDeterminantalFrobeniusDescent
  -> new(@fiber, @source_representation)
    @field = @source_representation.curve.field
    @intertwiner_kernel_dimension = 0
    @intertwiner = nil
    @frobenius_scalar = nil
    @normalized_intertwiner = nil
    @normalized_scalar = nil
    @fixed_change_of_basis = nil
    @descent_scalar = nil
    @descended_extension_matrices = nil
    @representation = nil
    build
    @certificate_cache = FiniteFieldDeterminantalFrobeniusDescentCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "finite determinantal Frobenius descent failed certification"

  -> fiber
    @fiber

  -> field
    @field

  -> source_representation
    @source_representation

  -> representation
    @representation

  -> intertwiner_kernel_dimension
    @intertwiner_kernel_dimension

  -> intertwiner
    copy_matrix(@intertwiner)

  -> frobenius_scalar
    @frobenius_scalar

  -> normalized_intertwiner
    copy_matrix(@normalized_intertwiner)

  -> normalized_scalar
    @normalized_scalar

  -> fixed_change_of_basis
    copy_matrix(@fixed_change_of_basis)

  -> descent_scalar
    @descent_scalar

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> copy_matrix(source)
    return nil if source == nil
    out = []
    source.each -> (row)
      copied = []
      row.each -> copied.push(item)
      out.push(copied)
    out

  -> matrix_determinant(matrix)
    Algebra.determinant_raw(matrix, @field)

  -> linear_combination(matrices, coefficients)
    out = CayleyOctadLinearAlgebra.zero_matrix(@field, 4, 4)
    index = 0
    while index < matrices.size
      scaled = CayleyOctadLinearAlgebra.matrix_scale(
        @field, matrices[index], coefficients[index])
      out = CayleyOctadLinearAlgebra.matrix_add(@field, out, scaled)
      index += 1
    out

  -> find_invertible_base(matrices)
    p = @field.characteristic
    first = 0
    while first < p
      second = 0
      while second < p
        third = 0
        while third < p
          if first != 0 || second != 0 || third != 0
            coefficients = [
              @field.coerce(first),
              @field.coerce(second),
              @field.coerce(third)]
            candidate = linear_combination(matrices, coefficients)
            if !@field.zero?(matrix_determinant(candidate))
              return [candidate, coefficients]
          third += 1
        second += 1
      first += 1
    raise "determinantal net has no invertible prime-field member"

  -> intertwiner_equations(operators, twisted_operators)
    equations = []
    operator_index = 0
    while operator_index < operators.size
      left = operators[operator_index]
      right = twisted_operators[operator_index]
      row = 0
      while row < 4
        column = 0
        while column < 4
          equation = []
          16.times -> equation.push(@field.zero)
          k = 0
          while k < 4
            left_index = k*4 + column
            equation[left_index] = @field.add(
              equation[left_index], left[row][k])
            right_index = row*4 + k
            equation[right_index] = @field.subtract(
              equation[right_index], right[k][column])
            k += 1
          equations.push(equation)
          column += 1
        row += 1
      operator_index += 1
    equations

  -> vector_matrix(vector)
    out = []
    row = 0
    while row < 4
      target_row = []
      column = 0
      while column < 4
        target_row.push(vector[row*4 + column])
        column += 1
      out.push(target_row)
      row += 1
    out

  -> first_invertible_kernel_matrix(kernel)
    kernel.each -> (vector)
      matrix = vector_matrix(vector)
      return matrix if !@field.zero?(matrix_determinant(matrix))
    left = 0
    while left < kernel.size
      right = left + 1
      while right < kernel.size
        vector = []
        index = 0
        while index < 16
          vector.push(@field.add(kernel[left][index], kernel[right][index]))
          index += 1
        matrix = vector_matrix(vector)
        return matrix if !@field.zero?(matrix_determinant(matrix))
        right += 1
      left += 1
    raise "simultaneous intertwiner kernel contains no invertible matrix"

  -> congruence_scalar(matrices, twisted, matrix)
    transpose = CayleyOctadLinearAlgebra.transpose(matrix)
    scalar = nil
    matrix_index = 0
    while matrix_index < matrices.size
      congruent = CayleyOctadLinearAlgebra.matrix_multiply(
        @field, transpose,
        CayleyOctadLinearAlgebra.matrix_multiply(
          @field, matrices[matrix_index], matrix))
      row = 0
      while row < 4
        column = 0
        while column < 4
          target = twisted[matrix_index][row][column]
          source = congruent[row][column]
          if scalar == nil && !@field.zero?(source)
            scalar = @field.divide(target, source)
          if scalar != nil
            expected = @field.multiply(scalar, source)
            return nil if !@field.equal?(target, expected)
          elsif !@field.zero?(target)
            return nil
          column += 1
        row += 1
      matrix_index += 1
    scalar

  -> frobenius_product(matrix)
    product = CayleyOctadLinearAlgebra.identity_matrix(@field, 4)
    iteration = 0
    while iteration < @field.degree
      product = CayleyOctadLinearAlgebra.matrix_multiply(
        @field, product,
        CayleyOctadLinearAlgebra.matrix_frobenius(
          @field, matrix, iteration))
      iteration += 1
    product

  -> scalar_identity_value(matrix)
    scalar = matrix[0][0]
    row = 0
    while row < 4
      column = 0
      while column < 4
        expected = row == column ? scalar : @field.zero
        return nil if !@field.equal?(matrix[row][column], expected)
        column += 1
      row += 1
    scalar

  -> norm(value)
    @field.power(
      value,
      (@field.order - 1) / (@field.characteristic - 1))

  -> norm_preimage(value)
    candidate = 1
    while candidate < @field.order
      return candidate if @field.equal?(norm(candidate), value)
      candidate += 1
    raise "finite-field norm equation has no solution"

  -> norm_product(value)
    product = @field.one
    iteration = 0
    while iteration < @field.degree
      product = @field.multiply(
        product, @field.frobenius(value, iteration))
      iteration += 1
    product

  -> tau_projection(matrix, cocycle)
    sum = CayleyOctadLinearAlgebra.zero_matrix(@field, 4, 4)
    prefix = CayleyOctadLinearAlgebra.identity_matrix(@field, 4)
    iteration = 0
    while iteration < @field.degree
      term = CayleyOctadLinearAlgebra.matrix_multiply(
        @field, prefix,
        CayleyOctadLinearAlgebra.matrix_frobenius(
          @field, matrix, iteration))
      sum = CayleyOctadLinearAlgebra.matrix_add(@field, sum, term)
      prefix = CayleyOctadLinearAlgebra.matrix_multiply(
        @field, prefix,
        CayleyOctadLinearAlgebra.matrix_frobenius(
          @field, cocycle, iteration))
      iteration += 1
    sum

  -> find_fixed_change_of_basis(cocycle)
    trials = [CayleyOctadLinearAlgebra.identity_matrix(@field, 4)]
    @field.power_basis.each -> (basis_value)
      row = 0
      while row < 4
        column = 0
        while column < 4
          matrix = CayleyOctadLinearAlgebra.zero_matrix(@field, 4, 4)
          matrix[row][column] = basis_value
          trials.push(matrix)
          column += 1
        row += 1
    projected = []
    trials.each ->
      candidate = tau_projection(item, cocycle)
      if !@field.zero?(matrix_determinant(candidate))
        return candidate
      projected.push(candidate)
    left = 0
    while left < projected.size
      right = left + 1
      while right < projected.size
        candidate = CayleyOctadLinearAlgebra.matrix_add(
          @field, projected[left], projected[right])
        if !@field.zero?(matrix_determinant(candidate))
          return candidate
        right += 1
      left += 1
    raise "additive Hilbert 90 did not expose an invertible fixed matrix"

  -> hilbert_ninety_scalar(value)
    candidate = 1
    while candidate < @field.order
      left = @field.multiply(
        @field.frobenius(candidate), value)
      return candidate if @field.equal?(left, candidate)
      candidate += 1
    raise "multiplicative Hilbert 90 equation has no solution"

  -> build
    if !@source_representation.certified?
      raise "finite descent needs a certified determinantal representation"
    if @field.class_name != "FiniteField" || @field.prime_field?
      raise "finite descent needs a non-prime finite splitting field"
    matrices = @source_representation.matrices
    twisted = []
    matrices.each ->
      twisted.push(CayleyOctadLinearAlgebra.matrix_frobenius(
        @field, item))

    base_data = find_invertible_base(matrices)
    base = base_data[0]
    twisted_base = CayleyOctadLinearAlgebra.matrix_frobenius(
      @field, base)
    base_inverse = CayleyOctadLinearAlgebra.matrix_inverse(@field, base)
    twisted_inverse = CayleyOctadLinearAlgebra.matrix_inverse(
      @field, twisted_base)
    operators = []
    twisted_operators = []
    index = 0
    while index < matrices.size
      operators.push(CayleyOctadLinearAlgebra.matrix_multiply(
        @field, base_inverse, matrices[index]))
      twisted_operators.push(CayleyOctadLinearAlgebra.matrix_multiply(
        @field, twisted_inverse, twisted[index]))
      index += 1
    equations = intertwiner_equations(operators, twisted_operators)
    kernel = CayleyOctadLinearAlgebra.right_nullspace(
      @field, equations, 16)
    @intertwiner_kernel_dimension = kernel.size
    @intertwiner = first_invertible_kernel_matrix(kernel)
    @frobenius_scalar = congruence_scalar(
      matrices, twisted, @intertwiner)
    if @frobenius_scalar == nil
      raise "Frobenius intertwiner is not a simultaneous congruence"

    cocycle_product = frobenius_product(@intertwiner)
    cocycle_scalar = scalar_identity_value(cocycle_product)
    if cocycle_scalar == nil || @field.zero?(cocycle_scalar)
      raise "projective Frobenius cocycle is not scalar"
    normalizer = norm_preimage(@field.inverse(cocycle_scalar))
    @normalized_intertwiner = CayleyOctadLinearAlgebra.matrix_scale(
      @field, @intertwiner, normalizer)
    @normalized_scalar = @field.divide(
      @frobenius_scalar,
      @field.multiply(normalizer, normalizer))
    normalized_product = frobenius_product(@normalized_intertwiner)
    identity = CayleyOctadLinearAlgebra.identity_matrix(@field, 4)
    if !CayleyOctadLinearAlgebra.same_matrix?(
         @field, normalized_product, identity)
      raise "normalized Frobenius intertwiner is not a cocycle"
    if !@field.one?(norm_product(@normalized_scalar))
      raise "normalized congruence scalar has nontrivial norm"

    @fixed_change_of_basis = find_fixed_change_of_basis(
      @normalized_intertwiner)
    @descent_scalar = hilbert_ninety_scalar(@normalized_scalar)
    transpose = CayleyOctadLinearAlgebra.transpose(@fixed_change_of_basis)
    descended_extension_matrices = []
    matrices.each -> (matrix)
      congruent = CayleyOctadLinearAlgebra.matrix_multiply(
        @field, transpose,
        CayleyOctadLinearAlgebra.matrix_multiply(
          @field, matrix, @fixed_change_of_basis))
      descended_extension_matrices.push(
        CayleyOctadLinearAlgebra.matrix_scale(
          @field, congruent, @descent_scalar))
    @descended_extension_matrices = descended_extension_matrices

    base_matrices = []
    descended_extension_matrices.each -> (matrix)
      base_matrix = []
      matrix.each -> (source_row)
        row = []
        source_row.each -> (entry)
          coefficients = @field.element_coefficients(entry)
          index = 1
          while index < coefficients.size
            if coefficients[index] != 0
              raise "descended matrix entry is not in the prime field"
            index += 1
          row.push(coefficients[0])
        base_matrix.push(row)
      base_matrices.push(base_matrix)
    base_curve = @fiber.scheme_certificate.setup.curve.reduce(@fiber.prime)
    @representation = PlaneQuarticSymmetricDeterminantalRepresentation.new(
      base_curve, base_matrices)

  -> frobenius_congruence_replays?
    matrices = @source_representation.matrices
    twisted = []
    matrices.each ->
      twisted.push(CayleyOctadLinearAlgebra.matrix_frobenius(
        @field, item))
    congruence_scalar(
      matrices, twisted, @intertwiner) == @frobenius_scalar

  -> normalized_cocycle_replays?
    identity = CayleyOctadLinearAlgebra.identity_matrix(@field, 4)
    CayleyOctadLinearAlgebra.same_matrix?(
      @field, frobenius_product(@normalized_intertwiner), identity)

  -> normalized_frobenius_congruence_replays?
    matrices = @source_representation.matrices
    twisted = []
    matrices.each ->
      twisted.push(CayleyOctadLinearAlgebra.matrix_frobenius(
        @field, item))
    congruence_scalar(
      matrices, twisted,
      @normalized_intertwiner) == @normalized_scalar

  -> semilinear_fixed_matrix_replays?
    left = CayleyOctadLinearAlgebra.matrix_multiply(
      @field, @normalized_intertwiner,
      CayleyOctadLinearAlgebra.matrix_frobenius(
        @field, @fixed_change_of_basis))
    CayleyOctadLinearAlgebra.same_matrix?(
      @field, left, @fixed_change_of_basis)

  -> descent_scalar_replays?
    @field.equal?(
      @field.multiply(
        @field.frobenius(@descent_scalar), @normalized_scalar),
      @descent_scalar)

  -> descended_entries_in_prime_field?
    return false if @descended_extension_matrices == nil
    @descended_extension_matrices.all? -> (matrix)
      matrix.all? -> (row)
        row.all? -> (entry)
          coefficients = @field.element_coefficients(entry)
          index = 1
          answer = true
          while index < coefficients.size
            answer = false if coefficients[index] != 0
            index += 1
          answer

  -> descended_representation_replays?
    return false if @descended_extension_matrices == nil
    base = @representation.matrices
    return false if base.size != @descended_extension_matrices.size
    matrix_index = 0
    while matrix_index < base.size
      row = 0
      while row < base[matrix_index].size
        column = 0
        while column < base[matrix_index][row].size
          embedded = @field.coerce(base[matrix_index][row][column])
          return false if !@field.equal?(
            embedded,
            @descended_extension_matrices[matrix_index][row][column])
          column += 1
        row += 1
      matrix_index += 1
    true


+ Curve
  -> dixon_representation(lines)
    PlaneQuarticDixonRepresentation.new(self, lines)
