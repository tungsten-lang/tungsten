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

  ro :ambient_dimension, :prime, :dimension

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

  ro :residue_algebra

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

  ro :order, :prime, :radical, :quotient

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
    cached = @lifted_idempotents_cache[index]
    if cached == nil
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
      cached = lifted
    out = []
    cached.each -> (entry)
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

# Certified prime ideals of maximal Z-orders.
#
# A rational prime p is first checked against the Round 2 fixed-point
# criterion.  The reduced finite algebra O/radical(pO) is then split into
# finite fields by its primitive idempotents.  Each projection
#
#   O -> O/radical(pO) -> k_i
#
# is replayed on an order basis; its kernel is a maximal ideal above p.
# Frobenius-lifted idempotents in O/pO give the local dimensions e_i f_i, so
# residue degrees and ramification indices are certified together.

+ OrderResidueFieldMapCertificate
  -> new(@residue_map)
    @verified_cache = nil

  ro :residue_map

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @residue_map.class_name != "OrderResidueFieldMap"
      raise "residue-field-map certificate has the wrong subject"
    residue = @residue_map.residue_algebra
    if !residue.certificate.verified?
      raise "residue-field map has an uncertified reduced algebra"
    field = @residue_map.field
    if field.class_name != "FiniteField"
      raise "residue-field target is not a finite field"
    if field.characteristic != residue.prime
      raise "residue-field characteristic changed"
    if field.degree != @residue_map.residue_degree
      raise "residue-field degree changed"
    found_idempotent = false
    residue.primitive_idempotents.each -> (idempotent)
      found_idempotent = true if residue.equal?(
        idempotent, @residue_map.idempotent)
    if !found_idempotent
      raise "residue-field map uses a nonprimitive idempotent"
    if !field.one?(@residue_map.image(
         @residue_map.order.one))
      raise "residue-field map does not preserve one"
    if !field.zero?(@residue_map.image(
         @residue_map.order.zero))
      raise "residue-field map does not preserve zero"

    order_basis = @residue_map.order.basis
    images = []
    order_basis.each -> (element)
      images.push(@residue_map.image(element))
    image_columns = []
    images.each -> (image)
      image_columns.push(field.element_coefficients(image))
    image_rank = PrimeLinearAlgebra.rank_columns(
      image_columns, residue.prime, field.degree)
    if image_rank != field.degree
      raise "residue-field map is not surjective"

    i = 0
    while i < order_basis.size
      j = 0
      while j < order_basis.size
        source_sum = @residue_map.order.algebra.add(
          order_basis[i], order_basis[j])
        image_sum = field.add(images[i], images[j])
        if !field.equal?(
             @residue_map.image(source_sum), image_sum)
          raise "residue-field map does not preserve addition"
        source_product = @residue_map.order.algebra.multiply(
          order_basis[i], order_basis[j])
        image_product = field.multiply(images[i], images[j])
        if !field.equal?(
             @residue_map.image(source_product), image_product)
          raise "residue-field map does not preserve multiplication"
        j += 1
      i += 1

    kernel = @residue_map.kernel_lattice
    if !@residue_map.order.lattice.contains_lattice?(kernel)
      raise "residue-field kernel is not contained in its order"
    kernel.basis_vectors.each -> (vector)
      element = @residue_map.order.algebra.coerce(vector)
      if !field.zero?(@residue_map.image(element))
        raise "displayed residue-field kernel has a nonzero image"
    index = @residue_map.order.lattice.index_from(kernel)
    if index != field.order
      raise "residue-field kernel has the wrong lattice index"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "OrderResidueFieldMapCertificate(F_"
    text + @residue_map.field.order.to_s + ")"

  -> inspect
    to_s


+ OrderResidueFieldMap
  -> new(@residue_algebra, idempotent,
         @generator_search_limit = 250_000)
    if @residue_algebra.class_name != "OrderResidueAlgebra"
      raise "residue-field map needs an OrderResidueAlgebra"
    if @generator_search_limit < 1
      raise "residue-field generator search limit must be positive"
    @order = @residue_algebra.order
    @prime = @residue_algebra.prime
    @idempotent = @residue_algebra.normalize(idempotent)
    primitive = false
    @residue_algebra.primitive_idempotents.each -> (candidate)
      primitive = true if @residue_algebra.equal?(
        candidate, @idempotent)
    if !primitive
      raise "residue-field map needs a primitive idempotent"
    @component_basis = @residue_algebra.component_basis(
      @idempotent)
    @residue_degree = @component_basis.size
    if @residue_degree < 1
      raise "residue-field component has zero degree"
    @generator = nil
    @minimal_polynomial = nil
    @power_basis = []
    choose_generator
    @kernel_lattice_cache = nil
    @certificate_cache = OrderResidueFieldMapCertificate.new(self)
    if !@certificate_cache.verified?
      raise "residue-field map failed certification"

  ro :residue_algebra, :order, :prime

  -> idempotent
    out = []
    @idempotent.each -> (entry)
      out.push(entry)
    out

  ro :residue_degree, :field

  -> generator
    out = []
    @generator.each -> (entry)
      out.push(entry)
    out

  ro :minimal_polynomial

  -> component_basis
    out = []
    @component_basis.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> power_basis
    out = []
    @power_basis.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> candidate_from_code(code)
    remaining = code
    value = @residue_algebra.zero
    i = 0
    while i < @component_basis.size
      coefficient = remaining % @prime
      remaining = remaining / @prime
      if coefficient != 0
        value = @residue_algebra.add(
          value,
          @residue_algebra.scale(
            @component_basis[i], coefficient))
      i += 1
    value

  -> choose_generator
    if @residue_degree == 1
      @generator = @idempotent
      @field = FiniteField.new(@prime)
      @power_basis = [@idempotent]
      ring = PolynomialRing.new(
        [:T], FiniteField.new(@prime))
      @minimal_polynomial = ring.generator(0) - 1
      return self

    candidate_count = @prime ** @residue_degree
    code = 1
    attempts = 0
    while code < candidate_count
      attempts += 1
      if attempts > @generator_search_limit
        raise "residue-field generator search limit exceeded; prime decomposition unknown"
      candidate = candidate_from_code(code)
      polynomial = @residue_algebra.minimal_polynomial(
        candidate, @idempotent)
      if polynomial.degree == @residue_degree
        @generator = candidate
        @minimal_polynomial = polynomial
        @field = FiniteField.new(
          @prime, polynomial.coefficients)
        break
      code += 1
    if @generator == nil
      raise "residue-field generator search exhausted the component"

    @power_basis = []
    value = @idempotent
    i = 0
    while i < @residue_degree
      @power_basis.push(value)
      value = @residue_algebra.multiply(
        value, @generator)
      i += 1
    rank = PrimeLinearAlgebra.rank_columns(
      @power_basis, @prime,
      @residue_algebra.dimension)
    if rank != @residue_degree
      raise "residue-field power basis is dependent"
    self

  -> component_coordinates(value)
    projected = @residue_algebra.multiply(
      @idempotent,
      @residue_algebra.normalize(value))
    PrimeLinearAlgebra.solve_columns(
      @power_basis, projected, @prime)

  -> image_order_coordinates(coordinates)
    reduced = @residue_algebra.project_order_coordinates(
      coordinates)
    @field.encode_coefficients(
      component_coordinates(reduced))

  -> integer_order_coordinates(value)
    element = @order.coerce(value)
    coordinates = @order.coordinates(element)
    out = []
    coordinates.each -> (coefficient)
      if coefficient.denominator != 1
        raise "residue-field source is not integral in its order"
      out.push(coefficient.numerator)
    out

  -> image(value)
    image_order_coordinates(
      integer_order_coordinates(value))

  -> reduce(value)
    image(value)

  -> kernel_basis_vectors
    columns = []
    i = 0
    while i < @order.rank
      coordinates = PrimeLinearAlgebra.zero_vector(
        @order.rank)
      coordinates[i] = 1
      image = image_order_coordinates(coordinates)
      columns.push(@field.element_coefficients(image))
      i += 1
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, @residue_degree, @prime)
    kernel = PrimeLinearAlgebra.kernel_data(
      matrix, @prime, @order.rank)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < @order.rank
        value = i == pivot ? @prime : 0
        vector.push(Rational.new(value))
        i += 1
      relative.push(vector)
    if relative.size != @order.rank
      raise "residue-field kernel lattice has the wrong rank"
    ExactRationalLinearAlgebra.compose_columns(
      @order.basis_vectors, relative)

  -> kernel_lattice
    if @kernel_lattice_cache == nil
      @kernel_lattice_cache = AlgebraOrderLattice.new(
        @order.algebra, kernel_basis_vectors)
    @kernel_lattice_cache

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "OrderResidueFieldMap(p=" + @prime.to_s
    text + ", f=" + @residue_degree.to_s + ")"

  -> inspect
    to_s


+ DedekindLinearRootCertificate
  -> new(@maximal_order_computation, @prime, root)
    @root = PrimeLinearAlgebra.normalize(
      root, @prime)
    source = @maximal_order_computation.source
    polynomial = source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      polynomial.ring.names,
      FiniteField.new(@prime))
    @polynomial = polynomial.change_ring(
      finite_ring).monic
    @factor = finite_ring.generator(0) - @root

  ro :maximal_order_computation, :prime, :root, :polynomial, :factor

  -> polynomial_zero_at_root?
    coefficients = @polynomial.coefficients
    value = 0
    i = coefficients.size - 1
    while i >= 0
      value = PrimeLinearAlgebra.normalize(
        value * @root + coefficients[i],
        @prime)
      i -= 1
    value == 0

  -> verified?
    expected = "MaximalOrderComputation"
    return false if @maximal_order_computation.class_name != expected
    return false if !@maximal_order_computation.certificate.verified?
    return false if @prime < 2 || !@prime.prime?
    return false if @maximal_order_computation.index % @prime == 0
    return false if @root < 0 || @root >= @prime
    source = @maximal_order_computation.source
    source_polynomial = source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      source_polynomial.ring.names,
      FiniteField.new(@prime))
    expected_polynomial = source_polynomial.change_ring(
      finite_ring).monic
    return false if !@polynomial.eql?(expected_polynomial)
    return false if !@factor.eql?(
      finite_ring.generator(0) - @root)
    polynomial_zero_at_root?

  -> certified?
    verified?

  -> proof_kind
    :exact_modular_root

  -> kernel_checked?
    true


+ DedekindOrderResidueFieldMapCertificate
  -> new(@residue_map)
    @verified_cache = nil

  ro :residue_map

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    expected = "DedekindOrderResidueFieldMap"
    return false if @residue_map.class_name != expected
    computation = @residue_map.maximal_order_computation
    return false if computation.class_name != "MaximalOrderComputation"
    return false if !computation.certificate.verified?
    return false if !@residue_map.order.same_order?(
      computation.order)
    return false if !@residue_map.source_order.same_order?(
      computation.source)
    prime = @residue_map.prime
    return false if prime < 2 || !prime.prime?
    return false if computation.index % prime == 0

    factorization = @residue_map.factorization
    root_certificate = @residue_map.root_certificate
    polynomial = nil
    if factorization != nil
      return false if factorization.class_name != "PolynomialFactorization"
      return false if !factorization.certificate.verified?
      polynomial = factorization.polynomial
    else
      expected_root_class = "DedekindLinearRootCertificate"
      return false if root_certificate.class_name != expected_root_class
      return false if !root_certificate.verified?
      return false if root_certificate.maximal_order_computation != computation
      return false if root_certificate.prime != prime
      polynomial = root_certificate.polynomial
    return false if polynomial.ring.field.class_name != "FiniteField"
    return false if !polynomial.ring.field.prime_field?
    return false if polynomial.ring.field.characteristic != prime
    expected_polynomial = computation.source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      expected_polynomial.ring.names,
      FiniteField.new(prime))
    expected_reduction = expected_polynomial.change_ring(
      finite_ring).monic
    return false if !polynomial.eql?(expected_reduction)

    factor = @residue_map.factor
    return false if factor.class_name != "Polynomial"
    return false if factor.ring != polynomial.ring
    return false if factor.degree < 1
    return false if !factor.eql?(factor.monic)
    if factorization != nil
      found = false
      factors = factorization.factors
      i = 0
      while i < factors.size
        found = true if factors[i].eql?(factor)
        i += 1
      return false if !found
    else
      return false if !root_certificate.factor.eql?(factor)

    field = @residue_map.field
    return false if field.class_name != "FiniteField"
    return false if field.characteristic != prime
    return false if field.degree != factor.degree
    if factor.degree == 1
      return false if !field.prime_field?
    else
      return false if field.modulus.to_s != factor.coefficients.to_s

    expected_images = @residue_map.recompute_basis_images
    return false if expected_images.to_s != @residue_map.basis_images.to_s
    order_basis = @residue_map.order.basis
    images = @residue_map.basis_images
    return false if images.size != order_basis.size
    image_columns = []
    i = 0
    while i < images.size
      image_columns.push(field.element_coefficients(
        images[i]))
      i += 1
    image_rank = PrimeLinearAlgebra.rank_columns(
      image_columns, prime, field.degree)
    return false if image_rank != field.degree

    i = 0
    while i < order_basis.size
      return false if !field.equal?(
        @residue_map.image(order_basis[i]),
        images[i])
      j = 0
      while j < order_basis.size
        source_product = @residue_map.order.algebra.multiply(
          order_basis[i], order_basis[j])
        image_product = field.multiply(
          images[i], images[j])
        return false if !field.equal?(
          @residue_map.image(source_product),
          image_product)
        j += 1
      i += 1

    kernel = @residue_map.kernel_lattice
    return false if !@residue_map.order.lattice.contains_lattice?(
      kernel)
    kernel_vectors = kernel.basis_vectors
    i = 0
    while i < kernel_vectors.size
      element = @residue_map.order.algebra.coerce(
        kernel_vectors[i])
      return false if !field.zero?(
        @residue_map.image(element))
      i += 1
    index = @residue_map.order.lattice.index_from(kernel)
    return false if index != field.order
    @verified_cache = true
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_dedekind_residue_map

  -> kernel_checked?
    true

  -> to_s
    text = "DedekindOrderResidueFieldMapCertificate(F_"
    text + @residue_map.field.order.to_s + ")"

  -> inspect
    to_s


+ DedekindOrderResidueFieldMap
  -> new(@maximal_order_computation, @prime,
         @factor, @factorization)
    initialize_dedekind_residue_map(nil)

  -> new(@maximal_order_computation, @prime,
         @factor, @factorization,
         root_certificate)
    initialize_dedekind_residue_map(
      root_certificate)

  -> initialize_dedekind_residue_map(root_certificate)
    expected = "MaximalOrderComputation"
    if @maximal_order_computation.class_name != expected
      raise "Dedekind residue map needs a maximal-order computation"
    if !@maximal_order_computation.certificate.verified?
      raise "Dedekind residue map needs a certified maximal order"
    if @prime < 2 || !@prime.prime?
      raise "Dedekind residue map needs a rational prime"
    if @maximal_order_computation.index % @prime == 0
      raise "Dedekind residue map needs index prime to p"
    @order = @maximal_order_computation.order
    @source_order = @maximal_order_computation.source
    @root_certificate = root_certificate
    if @factor.class_name != "Polynomial" || @factor.degree < 1
      raise "Dedekind residue map needs a nonconstant factor"
    if @factorization == nil && @root_certificate == nil
      raise "Dedekind residue map needs a factor proof"
    @residue_degree = @factor.degree
    if @residue_degree == 1
      @field = FiniteField.new(@prime)
      if @root_certificate == nil
        @root = @field.coerce(0 - @factor.coeff(0))
      else
        @root = @field.coerce(
          @root_certificate.root)
    else
      @field = FiniteField.new(
        @prime, @factor.coefficients)
      @root = @field.generator
    @basis_images = recompute_basis_images
    @kernel_lattice_cache = nil
    @certificate_cache = DedekindOrderResidueFieldMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "Dedekind residue-field map failed certification"

  ro :maximal_order_computation, :order, :source_order, :prime, :factor, :factorization
  ro :root_certificate, :residue_degree, :field, :root

  -> rational_mod_prime(value)
    rational = Rational.coerce(value)
    numerator = PrimeLinearAlgebra.normalize(
      rational.numerator, @prime)
    denominator = PrimeLinearAlgebra.normalize(
      rational.denominator, @prime)
    if denominator == 0
      raise "order basis denominator is not invertible modulo p"
    inverse = PrimeLinearAlgebra.inverse(
      denominator, @prime)
    @field.coerce(numerator * inverse)

  -> evaluate_power_coordinates(coordinates)
    value = @field.zero
    power = @field.one
    i = 0
    while i < coordinates.size
      coefficient = rational_mod_prime(
        coordinates[i])
      if !@field.zero?(coefficient)
        value = @field.add(
          value,
          @field.multiply(coefficient, power))
      power = @field.multiply(power, @root)
      i += 1
    value

  -> recompute_basis_images
    out = []
    @order.basis_vectors.each -> (vector)
      out.push(evaluate_power_coordinates(vector))
    out

  -> basis_images
    out = []
    @basis_images.each -> (image)
      out.push(image)
    out

  -> image_order_coordinates(coordinates)
    if coordinates.class_name != "Array"
      raise "residue-field order coordinates must be an Array"
    if coordinates.size != @order.rank
      raise "residue-field order coordinates have the wrong dimension"
    value = @field.zero
    i = 0
    while i < coordinates.size
      coefficient = @field.coerce(coordinates[i])
      if !@field.zero?(coefficient)
        term = @field.multiply(
          coefficient, @basis_images[i])
        value = @field.add(value, term)
      i += 1
    value

  -> integer_order_coordinates(value)
    element = @order.coerce(value)
    coordinates = @order.coordinates(element)
    out = []
    coordinates.each -> (coefficient)
      if coefficient.denominator != 1
        raise "residue-field source is not integral in its order"
      out.push(coefficient.numerator)
    out

  -> image(value)
    image_order_coordinates(
      integer_order_coordinates(value))

  -> reduce(value)
    image(value)

  -> kernel_basis_vectors
    columns = []
    i = 0
    while i < @order.rank
      columns.push(@field.element_coefficients(
        @basis_images[i]))
      i += 1
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, @residue_degree, @prime)
    kernel = PrimeLinearAlgebra.kernel_data(
      matrix, @prime, @order.rank)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < @order.rank
        value = i == pivot ? @prime : 0
        vector.push(Rational.new(value))
        i += 1
      relative.push(vector)
    if relative.size != @order.rank
      raise "residue-field kernel lattice has the wrong rank"
    ExactRationalLinearAlgebra.compose_columns(
      @order.basis_vectors, relative)

  -> kernel_lattice
    if @kernel_lattice_cache == nil
      @kernel_lattice_cache = AlgebraOrderLattice.new(
        @order.algebra, kernel_basis_vectors)
    @kernel_lattice_cache

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "DedekindOrderResidueFieldMap(p=" + @prime.to_s
    text + ", f=" + @residue_degree.to_s + ")"

  -> inspect
    to_s


