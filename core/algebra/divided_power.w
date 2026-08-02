# Exact degree-two divided powers over F2 and the associated binary-carry
# group.  In characteristic two Gamma^2(V) is not safely interchangeable with
# ordinary symmetric-square coinvariants: the diagonal divided powers retain
# information that drives the carry cocycle.

use core/algebra/lattice_polytope
use core/algebra/integer_lattice

+ DividedSquareSpace
  -> new(dimension)
    @dimension = LatticeCombinatorics.positive_integer(
      dimension, "divided-square dimension")
    @basis_pairs = []
    i = 0
    while i < @dimension
      j = i
      while j < @dimension
        @basis_pairs.push([i, j])
        j += 1
      i += 1

  -> dimension
    @dimension

  -> divided_dimension
    @basis_pairs.size

  -> basis_pairs
    LatticeCombinatorics.copy_matrix(@basis_pairs)

  -> normalize_vector(vector, expected, label)
    if vector.class_name != "Array" || vector.size != expected
      actual = vector.class_name == "Array" ? vector.size.to_s : vector.class_name
      raise (label + " has the wrong dimension: expected " +
             expected.to_s + ", got " + actual)
    out = []
    vector.each -> (coordinate)
      if !LatticeCombinatorics.integer?(coordinate)
        raise label + " coordinates must be integers"
      out.push(PrimeLinearAlgebra.normalize(coordinate, 2))
    out

  -> vector(value)
    normalize_vector(value, @dimension, "F2 vector")

  -> divided_vector(value)
    normalize_vector(value, divided_dimension, "divided-square vector")

  -> add(left, right)
    a = vector(left)
    b = vector(right)
    out = []
    i = 0
    while i < @dimension
      out.push(a[i] ^ b[i])
      i += 1
    out

  -> add_divided(left, right)
    a = divided_vector(left)
    b = divided_vector(right)
    out = []
    i = 0
    while i < divided_dimension
      out.push(a[i] ^ b[i])
      i += 1
    out

  # Quadratic divided square gamma_2(v).  Diagonal coordinates are v_i;
  # off-diagonal coordinates are v_i*v_j.
  -> square(value)
    v = vector(value)
    out = []
    @basis_pairs.each -> (pair)
      i = pair[0]
      j = pair[1]
      out.push(i == j ? v[i] : v[i] * v[j])
    out

  # Polarization gamma_2(v+w)+gamma_2(v)+gamma_2(w).  It vanishes on the
  # diagonal and records v_i*w_j+v_j*w_i off diagonal.
  -> polarization(left, right)
    v = vector(left)
    w = vector(right)
    out = []
    @basis_pairs.each -> (pair)
      i = pair[0]
      j = pair[1]
      value = i == j ? 0 : ((v[i] * w[j]) ^ (v[j] * w[i]))
      out.push(value)
    out

  # Restriction of l tensor l' to the span of v tensor v.  Unlike
  # polarization, its diagonal coordinate is l_i*l'_i; c(l,l) is precisely
  # the order-four signature in the binary-carry group.
  -> carry(left, right)
    l = vector(left)
    r = vector(right)
    out = []
    @basis_pairs.each -> (pair)
      i = pair[0]
      j = pair[1]
      value = l[i] * r[i]
      if i != j
        value = (l[i] * r[j]) ^ (l[j] * r[i])
      out.push(value)
    out

  -> basis_vector(index)
    if index < 0 || index >= @dimension
      raise "F2 basis index is out of range"
    out = []
    i = 0
    while i < @dimension
      out.push(i == index ? 1 : 0)
      i += 1
    out

  -> validate_matrix(matrix)
    if matrix.class_name != "Array" || matrix.size != @dimension
      raise "linear action has the wrong height"
    out = []
    row_index = 0
    while row_index < matrix.size
      source = matrix[row_index]
      if source.class_name != "Array" || source.size != @dimension
        raise "linear action must be square"
      row = []
      column = 0
      while column < source.size
        entry = source[column]
        if !LatticeCombinatorics.integer?(entry)
          raise "linear action entries must be integers"
        row.push(PrimeLinearAlgebra.normalize(entry, 2))
        column += 1
      out.push(row)
      row_index += 1
    out

  -> apply_matrix(matrix, value)
    action = validate_matrix(matrix)
    v = vector(value)
    out = []
    row = 0
    while row < @dimension
      coordinate = 0
      column = 0
      while column < @dimension
        coordinate = coordinate ^ (action[row][column] * v[column])
        column += 1
      out.push(coordinate)
      row += 1
    out

  -> apply_divided_matrix(matrix, value)
    if matrix.class_name != "Array" || matrix.size != divided_dimension
      raise "divided action has the wrong height"
    v = divided_vector(value)
    out = []
    row = 0
    while row < divided_dimension
      if (matrix[row].class_name != "Array" ||
          matrix[row].size != divided_dimension)
        raise "divided action must be square"
      coordinate = 0
      column = 0
      while column < divided_dimension
        entry = PrimeLinearAlgebra.normalize(matrix[row][column], 2)
        coordinate = coordinate ^ (entry * v[column])
        column += 1
      out.push(coordinate)
      row += 1
    out

  # The functorial Gamma^2 action.  Diagonal basis columns map by square;
  # off-diagonal basis columns map by polarization.
  -> lifted_action(matrix)
    action = validate_matrix(matrix)
    rows = []
    output_index = 0
    while output_index < divided_dimension
      output_pair = @basis_pairs[output_index]
      values = []
      input_index = 0
      while input_index < divided_dimension
        input_pair = @basis_pairs[input_index]
        p = output_pair[0]
        q = output_pair[1]
        i = input_pair[0]
        j = input_pair[1]
        value = 0
        if i == j
          if p == q
            value = action[p][i]
          else
            value = action[p][i] * action[q][i]
        else
          if p != q
            value = ((action[p][i] * action[q][j]) ^
                     (action[q][i] * action[p][j]))
        values.push(value)
        input_index += 1
      rows.push(values)
      output_index += 1
    rows

  -> action_certificate(matrix)
    DividedSquareActionCertificate.new(self, validate_matrix(matrix))


+ DividedSquareActionCertificate
  -> new(@space, @action)
    @lifted = @space.lifted_action(@action)

  -> proof_kind
    :exact_f2_divided_square_action

  -> action
    LatticeCombinatorics.copy_matrix(@action)

  -> lifted_action
    LatticeCombinatorics.copy_matrix(@lifted)

  -> same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> verified?
    begin
      return verify!
    rescue error
      false

  # Squares of basis vectors and their pairwise polarizations determine the
  # quadratic map, so this finite replay checks functoriality exactly.
  -> verify!
    i = 0
    while i < @space.dimension
      basis = @space.basis_vector(i)
      transformed = @space.apply_matrix(@action, basis)
      left = @space.apply_divided_matrix(@lifted, @space.square(basis))
      return false if !same_vector?(left, @space.square(transformed))
      j = i + 1
      while j < @space.dimension
        other = @space.basis_vector(j)
        transformed_other = @space.apply_matrix(@action, other)
        left = @space.apply_divided_matrix(
          @lifted, @space.polarization(basis, other))
        right = @space.polarization(transformed, transformed_other)
        return false if !same_vector?(left, right)
        j += 1
      i += 1
    true


+ BinaryCarryGroup
  -> new(dimension)
    @space = DividedSquareSpace.new(dimension)

  -> dimension
    @space.dimension

  -> divided_dimension
    @space.divided_dimension

  -> space
    @space

  -> element(linear, quadratic = nil)
    q = quadratic
    if q == nil
      q = []
      divided_dimension.times -> q.push(0)
    [@space.vector(linear), @space.divided_vector(q)]

  -> identity
    linear = []
    quadratic = []
    dimension.times -> linear.push(0)
    divided_dimension.times -> quadratic.push(0)
    [linear, quadratic]

  -> validate_element(value)
    if value.class_name != "Array" || value.size != 2
      raise "binary-carry element must be [linear, quadratic]"
    element(value[0], value[1])

  -> same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> same_element?(left, right)
    a = validate_element(left)
    b = validate_element(right)
    same_vector?(a[0], b[0]) && same_vector?(a[1], b[1])

  -> direct_product(left, right)
    a = validate_element(left)
    b = validate_element(right)
    [@space.add(a[0], b[0]), @space.add_divided(a[1], b[1])]

  -> carry_product(left, right)
    a = validate_element(left)
    b = validate_element(right)
    linear = @space.add(a[0], b[0])
    quadratic = @space.add_divided(a[1], b[1])
    quadratic = @space.add_divided(
      quadratic, @space.carry(a[0], b[0]))
    [linear, quadratic]

  -> product(left, right, law = :carry)
    return direct_product(left, right) if law == :direct
    return carry_product(left, right) if law == :carry
    raise "binary group law must be direct or carry"

  -> inverse(value, law = :carry)
    element_value = validate_element(value)
    return element_value if law == :direct
    if law == :carry
      correction = @space.carry(element_value[0], element_value[0])
      return [element_value[0],
              @space.add_divided(element_value[1], correction)]
    raise "binary group law must be direct or carry"

  -> identity?(value)
    same_element?(value, identity)

  -> order(value, law = :carry)
    element_value = validate_element(value)
    return 1 if identity?(element_value)
    squared = product(element_value, element_value, law)
    return 2 if identity?(squared)
    fourth = product(squared, squared, law)
    return 4 if identity?(fourth)
    raise "binary-carry element exceeded the expected exponent four"

  -> elements(candidate_limit = 65_536)
    coordinate_count = dimension + divided_dimension
    total = 1 << coordinate_count
    if total > candidate_limit
      raise "binary-carry enumeration exceeds its candidate limit"
    out = []
    mask = 0
    while mask < total
      linear = []
      quadratic = []
      index = 0
      while index < dimension
        linear.push((mask >> index) & 1)
        index += 1
      while index < coordinate_count
        quadratic.push((mask >> index) & 1)
        index += 1
      out.push([linear, quadratic])
      mask += 1
    out
