# Finite residue algebras of exact Z-orders.
#
# For an order O and a rational prime p, O/pO is represented in the order
# basis as a finite-dimensional F_p-algebra.  Its nilradical is the Frobenius
# kernel already used by Round 2.  Quotienting by that kernel gives the finite
# reduced algebra
#
#   O / radical(pO) = product_i k_i.
#
# The primitive idempotents are found by the Buchmann--Lenstra finite
# separable-algebra algorithm: the fixed space of x |-> x^p has one dimension
# per field factor, and a nonscalar fixed element splits an idempotent by its
# squarefree linear minimal polynomial.  No random choices enter the result.

+ PrimeLinearAlgebra
  -> .zero_vector(size)
    out = []
    i = 0
    while i < size
      out.push(0)
      i += 1
    out

  -> .vector_equal?(left, right, prime)
    return false if left.size != right.size
    i = 0
    while i < left.size
      a = PrimeLinearAlgebra.normalize(left[i], prime)
      b = PrimeLinearAlgebra.normalize(right[i], prime)
      return false if a != b
      i += 1
    true

  -> .zero_vector?(vector, prime)
    i = 0
    while i < vector.size
      return false if PrimeLinearAlgebra.normalize(
        vector[i], prime) != 0
      i += 1
    true

  -> .add_vectors(left, right, prime)
    if left.size != right.size
      raise "prime-field vector dimensions do not match"
    out = []
    i = 0
    while i < left.size
      out.push(PrimeLinearAlgebra.normalize(
        left[i] + right[i], prime))
      i += 1
    out

  -> .subtract_vectors(left, right, prime)
    if left.size != right.size
      raise "prime-field vector dimensions do not match"
    out = []
    i = 0
    while i < left.size
      out.push(PrimeLinearAlgebra.normalize(
        left[i] - right[i], prime))
      i += 1
    out

  -> .scale_vector(vector, scalar, prime)
    factor = PrimeLinearAlgebra.normalize(scalar, prime)
    out = []
    vector.each -> (entry)
      out.push(PrimeLinearAlgebra.normalize(
        entry * factor, prime))
    out

  -> .matrix_from_columns(columns, row_count, prime)
    rows = []
    row = 0
    while row < row_count
      values = []
      column = 0
      while column < columns.size
        if columns[column].class_name != "Array"
          raise "prime-field matrix columns must be arrays"
        if columns[column].size != row_count
          raise "prime-field matrix columns have inconsistent sizes"
        values.push(PrimeLinearAlgebra.normalize(
          columns[column][row], prime))
        column += 1
      rows.push(values)
      row += 1
    rows

  -> .independent_columns(columns, prime, row_count = nil)
    return [] if columns.size == 0
    rows_count = row_count == nil ? columns[0].size : row_count
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, rows_count, prime)
    pivots = PrimeLinearAlgebra.rref(
      matrix, prime, columns.size)[1]
    out = []
    pivots.each -> (pivot)
      out.push(columns[pivot])
    out

  -> .rank_columns(columns, prime, row_count = nil)
    PrimeLinearAlgebra.independent_columns(
      columns, prime, row_count).size

  # Solve sum_i coefficients[i] * columns[i] = target.  The columns must be
  # independent; a target outside their span raises instead of returning a
  # partial solution.
  -> .solve_columns(columns, target, prime)
    if columns.size == 0
      return [] if PrimeLinearAlgebra.zero_vector?(
        target, prime)
      raise "target is outside the empty prime-field span"
    row_count = target.size
    matrix = []
    row = 0
    while row < row_count
      values = []
      column = 0
      while column < columns.size
        if columns[column].size != row_count
          raise "prime-field solve has inconsistent column sizes"
        values.push(columns[column][row])
        column += 1
      values.push(target[row])
      matrix.push(values)
      row += 1
    reduced = PrimeLinearAlgebra.rref(
      matrix, prime, columns.size + 1)
    rows = reduced[0]
    pivots = reduced[1]
    if pivots.include?(columns.size)
      raise "target is outside the prime-field column span"
    variable_pivots = []
    pivots.each -> (pivot)
      variable_pivots.push(pivot) if pivot < columns.size
    if variable_pivots.size != columns.size
      raise "prime-field solve needs independent columns"
    solution = PrimeLinearAlgebra.zero_vector(columns.size)
    pivot_row = 0
    while pivot_row < pivots.size
      pivot = pivots[pivot_row]
      if pivot < columns.size
        solution[pivot] = PrimeLinearAlgebra.normalize(
          rows[pivot_row][columns.size], prime)
      pivot_row += 1
    solution


+ PrimeVectorQuotient
  -> new(@ambient_dimension, subspace_basis, @prime)
    if @ambient_dimension < 1
      raise "prime-field quotient needs positive ambient dimension"
    if @prime < 2 || !@prime.prime?
      raise "prime-field quotient needs a prime modulus"
    reduced = PrimeLinearAlgebra.rref(
      subspace_basis, @prime, @ambient_dimension)
    rows = reduced[0]
    @pivots = reduced[1]
    @relations = []
    i = 0
    while i < @pivots.size
      @relations.push(rows[i])
      i += 1
    @free_columns = []
    column = 0
    while column < @ambient_dimension
      @free_columns.push(column) if !@pivots.include?(column)
      column += 1
    @dimension = @free_columns.size

  -> ambient_dimension
    @ambient_dimension

  -> prime
    @prime

  -> dimension
    @dimension

  -> pivots
    out = []
    @pivots.each -> (pivot)
      out.push(pivot)
    out

  -> free_columns
    out = []
    @free_columns.each -> (column)
      out.push(column)
    out

  -> relations
    out = []
    @relations.each -> (source)
      row = []
      source.each -> (entry)
        row.push(entry)
      out.push(row)
    out

  -> project(vector)
    invalid = vector.class_name != "Array"
    if !invalid
      invalid = true if vector.size != @ambient_dimension
    if invalid
      raise "prime-field quotient vector has the wrong dimension"
    reduced = []
    vector.each -> (entry)
      reduced.push(PrimeLinearAlgebra.normalize(
        entry, @prime))
    row = 0
    while row < @relations.size
      pivot = @pivots[row]
      factor = reduced[pivot]
      if factor != 0
        column = 0
        while column < @ambient_dimension
          reduced[column] = PrimeLinearAlgebra.normalize(
            reduced[column] - factor * @relations[row][column],
            @prime)
          column += 1
      row += 1
    out = []
    @free_columns.each -> (column)
      out.push(reduced[column])
    out

  -> lift(vector)
    invalid = vector.class_name != "Array"
    if !invalid
      invalid = true if vector.size != @dimension
    if invalid
      raise "prime-field quotient lift has the wrong dimension"
    out = PrimeLinearAlgebra.zero_vector(
      @ambient_dimension)
    i = 0
    while i < @free_columns.size
      out[@free_columns[i]] = PrimeLinearAlgebra.normalize(
        vector[i], @prime)
      i += 1
    out

  -> zero
    PrimeLinearAlgebra.zero_vector(@dimension)

  -> basis
    out = []
    i = 0
    while i < @dimension
      vector = PrimeLinearAlgebra.zero_vector(@dimension)
      vector[i] = 1
      out.push(vector)
      i += 1
    out

  -> kernel_dimension
    @pivots.size

  -> to_s
    text = "F_" + @prime.to_s + "^" + @ambient_dimension.to_s
    text + " / dimension " + kernel_dimension.to_s

  -> inspect
    to_s


+ OrderResidueAlgebraCertificate
  -> new(@residue_algebra)
    @verified_cache = nil

  -> residue_algebra
    @residue_algebra

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @residue_algebra.class_name != "OrderResidueAlgebra"
      raise "residue-algebra certificate has the wrong subject"
    order = @residue_algebra.order
    prime = @residue_algebra.prime
    if !order.certificate.verified?
      raise "residue algebra has an uncertified order"
    if prime < 2 || !prime.prime?
      raise "residue algebra has a nonprime characteristic"
    if !@residue_algebra.radical.certificate.verified?
      raise "residue algebra has an uncertified p-radical"
    if @residue_algebra.dimension < 1
      raise "reduced residue algebra cannot be zero"
    if @residue_algebra.nilradical_kernel_basis.size != 0
      raise "residue algebra is not reduced"

    idempotents = @residue_algebra.primitive_idempotents
    fixed = @residue_algebra.frobenius_fixed_basis
    if idempotents.size == 0 || idempotents.size != fixed.size
      raise "primitive idempotents do not match the Frobenius fixed space"
    sum = @residue_algebra.zero
    lifted_sum = PrimeLinearAlgebra.zero_vector(order.rank)
    local_dimension_sum = 0
    i = 0
    while i < idempotents.size
      idempotent = idempotents[i]
      if @residue_algebra.zero?(idempotent)
        raise "primitive idempotent is zero"
      square = @residue_algebra.multiply(
        idempotent, idempotent)
      if !@residue_algebra.equal?(square, idempotent)
        raise "residue-algebra idempotent does not square to itself"
      if @residue_algebra.component_fixed_basis(
           idempotent).size != 1
        raise "residue-algebra idempotent is not primitive"
      j = 0
      while j < i
        product = @residue_algebra.multiply(
          idempotent, idempotents[j])
        if !@residue_algebra.zero?(product)
          raise "primitive idempotents are not orthogonal"
        j += 1
      sum = @residue_algebra.add(sum, idempotent)

      lifted = @residue_algebra.lift_idempotent(idempotent)
      lifted_square = order.multiply_coordinates_mod(
        lifted, lifted, prime)
      if !PrimeLinearAlgebra.vector_equal?(
           lifted_square, lifted, prime)
        raise "lifted residue idempotent is not idempotent modulo p"
      j = 0
      while j < i
        other = @residue_algebra.lift_idempotent(
          idempotents[j])
        product = order.multiply_coordinates_mod(
          lifted, other, prime)
        if !PrimeLinearAlgebra.zero_vector?(product, prime)
          raise "lifted residue idempotents are not orthogonal"
        j += 1
      lifted_sum = PrimeLinearAlgebra.add_vectors(
        lifted_sum, lifted, prime)
      local_dimension_sum += @residue_algebra.local_dimension(
        idempotent)
      i += 1
    if !@residue_algebra.equal?(sum, @residue_algebra.one)
      raise "primitive idempotents do not sum to one"
    if !PrimeLinearAlgebra.vector_equal?(
         lifted_sum, order.one_coordinates, prime)
      raise "lifted primitive idempotents do not sum to one modulo p"
    if local_dimension_sum != order.rank
      raise "local residue components have the wrong total dimension"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "OrderResidueAlgebraCertificate(p="
    text + @residue_algebra.prime.to_s + ")"

  -> inspect
    to_s


+ OrderResidueAlgebra
  -> new(@order, @prime, @factor_search_limit = 250_000)
    if @order.class_name != "AlgebraOrder"
      raise "residue algebra needs an AlgebraOrder"
    if @prime < 2 || !@prime.prime?
      raise "residue algebra needs a rational prime"
    if @factor_search_limit < 1
      raise "residue-algebra factor search limit must be positive"
    @radical = @order.p_radical(@prime)
    radical_kernel = @order.p_radical_kernel_data(@prime)[0]
    @quotient = PrimeVectorQuotient.new(
      @order.rank, radical_kernel, @prime)
    @one = @quotient.project(@order.one_coordinates)
    @fixed_basis_cache = nil
    @idempotents_cache = nil
    @lifted_idempotents_cache = []
    @certificate_cache = OrderResidueAlgebraCertificate.new(self)
    if !@certificate_cache.verified?
      raise "reduced residue algebra failed certification"

  -> order
    @order

  -> prime
    @prime

  -> radical
    @radical

  -> quotient
    @quotient

  -> dimension
    @quotient.dimension

  -> zero
    @quotient.zero

  -> one
    out = []
    @one.each -> (entry)
      out.push(entry)
    out

  -> basis
    @quotient.basis

  -> normalize(value)
    if value.class_name != "Array" || value.size != dimension
      raise "residue-algebra element has the wrong dimension"
    out = []
    value.each -> (entry)
      out.push(PrimeLinearAlgebra.normalize(
        entry, @prime))
    out

  -> zero?(value)
    PrimeLinearAlgebra.zero_vector?(
      normalize(value), @prime)

  -> equal?(left, right)
    PrimeLinearAlgebra.vector_equal?(
      normalize(left), normalize(right), @prime)

  -> add(left, right)
    PrimeLinearAlgebra.add_vectors(
      normalize(left), normalize(right), @prime)

  -> subtract(left, right)
    PrimeLinearAlgebra.subtract_vectors(
      normalize(left), normalize(right), @prime)

  -> scale(value, scalar)
    PrimeLinearAlgebra.scale_vector(
      normalize(value), scalar, @prime)

  -> project_order_coordinates(coordinates)
    @quotient.project(coordinates)

  -> lift_order_coordinates(value)
    @quotient.lift(normalize(value))

  -> multiply(left, right)
    a = @quotient.lift(normalize(left))
    b = @quotient.lift(normalize(right))
    @quotient.project(@order.multiply_coordinates_mod(
      a, b, @prime))

  -> power(value, exponent)
    if exponent < 0
      raise "residue-algebra power needs a nonnegative exponent"
    result = one
    factor = normalize(value)
    remaining = exponent
    while remaining > 0
      result = multiply(result, factor) if remaining.odd?
      remaining = remaining / 2
      factor = multiply(factor, factor) if remaining > 0
    result

  -> evaluate_polynomial(polynomial, value, identity = nil)
    invalid = polynomial.class_name != "Polynomial"
    if !invalid
      invalid = true if polynomial.ring.arity != 1
    if invalid
      raise "residue-algebra evaluation needs a univariate polynomial"
    field = polynomial.ring.field
    matching = field.class_name == "FiniteField"
    matching = matching && field.prime_field?
    matching = matching && field.characteristic == @prime
    if !matching
      raise "residue-algebra polynomial has the wrong coefficient field"
    unit = identity == nil ? one : normalize(identity)
    result = zero
    coefficients = polynomial.coefficients
    i = coefficients.size - 1
    while i >= 0
      result = add(multiply(result, value),
                   scale(unit, coefficients[i]))
      i -= 1
    result

  # The first linear dependence among 1,a,... is the monic minimal
  # polynomial.  A component idempotent may be supplied as the identity so
  # the same routine works inside eA.
  -> minimal_polynomial(value, identity = nil, name = :T)
    element = normalize(value)
    unit = identity == nil ? one : normalize(identity)
    if zero?(unit)
      raise "minimal polynomial needs a nonzero component identity"
    powers = []
    current = unit
    exponent = 0
    while exponent <= dimension
      powers.push(current)
      if exponent > 0
        matrix = PrimeLinearAlgebra.matrix_from_columns(
          powers, dimension, @prime)
        relations = PrimeLinearAlgebra.kernel(
          matrix, @prime, powers.size)
        relation = nil
        relations.each -> (candidate)
          if candidate[exponent] != 0 && relation == nil
            relation = candidate
        if relation != nil
          inverse = PrimeLinearAlgebra.inverse(
            relation[exponent], @prime)
          terms = []
          i = 0
          while i <= exponent
            coefficient = PrimeLinearAlgebra.normalize(
              relation[i] * inverse, @prime)
            terms.push([coefficient, [i]]) if coefficient != 0
            i += 1
          ring = PolynomialRing.new(
            [name], FiniteField.new(@prime))
          polynomial = Polynomial.new(ring, terms).monic
          if !zero?(evaluate_polynomial(
               polynomial, element, unit))
            raise "residue-algebra minimal polynomial failed replay"
          return polynomial
      current = multiply(current, element)
      exponent += 1
    raise "residue-algebra minimal polynomial exceeded its dimension"

  -> frobenius_fixed_basis
    if @fixed_basis_cache == nil
      columns = []
      basis.each -> (vector)
        columns.push(subtract(power(vector, @prime), vector))
      matrix = PrimeLinearAlgebra.matrix_from_columns(
        columns, dimension, @prime)
      @fixed_basis_cache = PrimeLinearAlgebra.kernel(
        matrix, @prime, dimension)
    out = []
    @fixed_basis_cache.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> nilradical_kernel_basis
    rounds = 0
    bound = 1
    while bound < dimension
      bound *= @prime
      rounds += 1
    columns = []
    basis.each -> (source)
      value = source
      i = 0
      while i < rounds
        value = power(value, @prime)
        i += 1
      columns.push(value)
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, dimension, @prime)
    PrimeLinearAlgebra.kernel(
      matrix, @prime, dimension)

  -> component_fixed_basis(idempotent)
    columns = []
    frobenius_fixed_basis.each -> (value)
      columns.push(multiply(idempotent, value))
    PrimeLinearAlgebra.independent_columns(
      columns, @prime, dimension)

  -> component_basis(idempotent)
    columns = []
    basis.each -> (value)
      columns.push(multiply(idempotent, value))
    PrimeLinearAlgebra.independent_columns(
      columns, @prime, dimension)

  -> scalar_multiple?(left, right)
    PrimeLinearAlgebra.rank_columns(
      [normalize(left), normalize(right)],
      @prime, dimension) == 1

  -> split_idempotent(idempotent)
    fixed = component_fixed_basis(idempotent)
    return [idempotent] if fixed.size == 1
    alpha = nil
    fixed.each -> (candidate)
      if alpha == nil && !scalar_multiple?(
           idempotent, candidate)
        alpha = candidate
    if alpha == nil
      raise "failed to find a nonscalar Frobenius-fixed splitter"

    polynomial = minimal_polynomial(
      alpha, idempotent)
    factors = polynomial.factor(@factor_search_limit)
    roots = []
    factors.each -> (factor)
      if factor.degree != 1
        raise "Frobenius-fixed splitter has a nonlinear factor"
      root = PrimeLinearAlgebra.normalize(
        0 - factor.coeff(0), @prime)
      roots.push(root) if !roots.include?(root)
    if roots.size < 2
      raise "nonscalar Frobenius-fixed splitter did not split"

    pieces = []
    roots.each -> (root)
      piece = idempotent
      denominator = 1
      roots.each -> (other)
        if other != root
          shifted = subtract(alpha, scale(
            idempotent, other))
          piece = multiply(piece, shifted)
          denominator = PrimeLinearAlgebra.normalize(
            denominator * (root - other), @prime)
      piece = scale(piece, PrimeLinearAlgebra.inverse(
        denominator, @prime))
      pieces.push(piece) if !zero?(piece)

    sum = zero
    i = 0
    while i < pieces.size
      square = multiply(pieces[i], pieces[i])
      if !equal?(square, pieces[i])
        raise "splitter interpolation did not produce an idempotent"
      j = 0
      while j < i
        if !zero?(multiply(pieces[i], pieces[j]))
          raise "splitter interpolation produced overlapping pieces"
        j += 1
      sum = add(sum, pieces[i])
      i += 1
    if !equal?(sum, idempotent)
      raise "splitter interpolation lost a residue component"
    pieces

  -> primitive_idempotents
    if @idempotents_cache == nil
      pending = [one]
      @idempotents_cache = []
      while pending.size > 0
        idempotent = pending[0]
        pending.delete_at(0)
        pieces = split_idempotent(idempotent)
        if pieces.size == 1
          @idempotents_cache.push(idempotent)
        else
          pieces.each -> (piece)
            pending.push(piece)
      if @idempotents_cache.size != frobenius_fixed_basis.size
        raise "primitive-idempotent count disagrees with Frobenius fixed space"
    out = []
    @idempotents_cache.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  # Idempotents lift uniquely through the nilradical.  If p^r is at least the
  # ambient rank, Frobenius^r kills every nilpotent correction to a 0/1
  # component, so any linear lift becomes an exact idempotent in O/pO.
  -> lift_idempotent(idempotent)
    sought = normalize(idempotent)
    index = nil
    primitives = primitive_idempotents
    i = 0
    while i < primitives.size
      index = i if index == nil && equal?(
        primitives[i], sought)
      i += 1
    if index == nil
      raise "can only lift a certified primitive idempotent"
    if @lifted_idempotents_cache[index] == nil
      lifted = @quotient.lift(sought)
      rounds = 0
      bound = 1
      while bound < @order.rank
        bound *= @prime
        rounds += 1
      round = 0
      while round < rounds
        lifted = @order.power_coordinates_mod(
          lifted, @prime, @prime)
        round += 1
      if !equal?(@quotient.project(lifted), sought)
        raise "Frobenius idempotent lift changed its reduced component"
      @lifted_idempotents_cache[index] = lifted
    out = []
    @lifted_idempotents_cache[index].each -> (entry)
      out.push(entry)
    out

  -> local_dimension(idempotent)
    lifted = lift_idempotent(idempotent)
    columns = []
    i = 0
    while i < @order.rank
      basis_vector = PrimeLinearAlgebra.zero_vector(
        @order.rank)
      basis_vector[i] = 1
      columns.push(@order.multiply_coordinates_mod(
        lifted, basis_vector, @prime))
      i += 1
    PrimeLinearAlgebra.rank_columns(
      columns, @prime, @order.rank)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "OrderResidueAlgebra(p=" + @prime.to_s
    text + ", dimension=" + dimension.to_s
    text + ", components=" + primitive_idempotents.size.to_s + ")"

  -> inspect
    to_s
