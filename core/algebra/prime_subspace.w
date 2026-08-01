# Canonical linear subspaces over prime fields.
#
# Rows are vectors in F_p^n.  Every subspace is stored as the nonzero rows of
# its unique reduced row-echelon basis, so equality, containment, sums, and
# intersections are exact and deterministic.  This is deliberately a small
# prime-field layer: extension-field linear algebra belongs in a later module.

+ PrimeFieldSubspaceCertificate
  -> new(@subspace)
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
    return false if @subspace.class_name != "PrimeFieldSubspace"
    prime = @subspace.prime
    return false if prime < 2 || !prime.prime?
    ambient = @subspace.ambient_dimension
    return false if ambient < 0
    basis = @subspace.basis
    reduced = PrimeLinearAlgebra.rref(basis, prime, ambient)
    return false if reduced[1].to_s != @subspace.pivots.to_s
    return false if reduced[1].size != basis.size
    index = 0
    while index < basis.size
      return false if basis[index].size != ambient
      return false if reduced[0][index].to_s != basis[index].to_s
      return false if basis[index][reduced[1][index]] != 1
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_prime_field_rref_replay

  -> theorem
    "the nonzero rows of reduced row-echelon form are a canonical basis for a prime-field subspace"

  -> theorem_reference
    "Gaussian elimination over F_p"

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true


+ PrimeFieldSubspace
  -> new(@prime, @ambient_dimension, vectors = [])
    if @prime.class_name != "Integer" && @prime.class_name != "Int" && (
         @prime.class_name != "BigInt")
      raise "prime-field subspace modulus must be an integer"
    if @prime < 2 || !@prime.prime?
      raise "prime-field subspace needs a prime modulus"
    if @ambient_dimension.class_name != "Integer" && (
         @ambient_dimension.class_name != "Int") && (
         @ambient_dimension.class_name != "BigInt")
      raise "prime-field subspace ambient dimension must be an integer"
    raise "prime-field subspace dimension must be nonnegative" if (
      @ambient_dimension < 0)
    if vectors.class_name != "Array"
      raise "prime-field subspace vectors must be an array"
    vectors.each -> (vector)
      if vector.class_name != "Array" || vector.size != @ambient_dimension
        raise "prime-field subspace vector has wrong dimension"

    reduced = PrimeLinearAlgebra.rref(
      vectors, @prime, @ambient_dimension)
    @pivots = reduced[1]
    @basis = []
    index = 0
    while index < @pivots.size
      @basis.push(copy_vector(reduced[0][index]))
      index += 1
    @certificate_cache = PrimeFieldSubspaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "prime-field subspace failed certification"

  -> .zero(prime, ambient_dimension)
    PrimeFieldSubspace.new(prime, ambient_dimension, [])

  -> .full(prime, ambient_dimension)
    basis = []
    row = 0
    while row < ambient_dimension
      vector = []
      column = 0
      while column < ambient_dimension
        vector.push(row == column ? 1 : 0)
        column += 1
      basis.push(vector)
      row += 1
    PrimeFieldSubspace.new(prime, ambient_dimension, basis)

  -> .kernel(matrix, prime, ambient_dimension = nil)
    count = ambient_dimension
    if count == nil
      count = matrix.size == 0 ? 0 : matrix[0].size
    basis = PrimeLinearAlgebra.kernel(matrix, prime, count)
    PrimeFieldSubspace.new(prime, count, basis)

  -> copy_vector(source)
    out = []
    index = 0
    while index < source.size
      out.push(PrimeLinearAlgebra.normalize(source[index], @prime))
      index += 1
    out

  -> prime
    @prime

  -> ambient_dimension
    @ambient_dimension

  -> dimension
    @basis.size

  -> codimension
    @ambient_dimension - dimension

  -> zero?
    dimension == 0

  -> full?
    dimension == @ambient_dimension

  -> basis
    out = []
    index = 0
    while index < @basis.size
      out.push(copy_vector(@basis[index]))
      index += 1
    out

  -> pivots
    out = []
    index = 0
    while index < @pivots.size
      out.push(@pivots[index])
      index += 1
    out

  -> compatible!(other)
    if other.class_name != "PrimeFieldSubspace"
      raise "prime-field subspace operation needs another subspace"
    if other.prime != @prime
      raise "prime-field subspaces have different moduli"
    if other.ambient_dimension != @ambient_dimension
      raise "prime-field subspaces have different ambient dimensions"
    true

  -> normalize_vector(vector)
    if vector.class_name != "Array" || vector.size != @ambient_dimension
      raise "prime-field vector has wrong dimension"
    copy_vector(vector)

  -> contains_vector?(vector)
    work = normalize_vector(vector)
    row = 0
    while row < @basis.size
      pivot = @pivots[row]
      scale = work[pivot]
      if scale != 0
        column = 0
        while column < @ambient_dimension
          work[column] = PrimeLinearAlgebra.normalize(
            work[column] - scale*@basis[row][column], @prime)
          column += 1
      row += 1
    column = 0
    while column < @ambient_dimension
      return false if work[column] != 0
      column += 1
    true

  -> contains_subspace?(other)
    compatible!(other)
    rows = other.basis
    index = 0
    while index < rows.size
      return false if !contains_vector?(rows[index])
      index += 1
    true

  -> same_subspace?(other)
    return false if other.class_name != "PrimeFieldSubspace"
    return false if other.prime != @prime
    return false if other.ambient_dimension != @ambient_dimension
    @basis.to_s == other.basis.to_s

  -> eql?(other)
    same_subspace?(other)

  -> coordinates(vector)
    normalized = normalize_vector(vector)
    if !contains_vector?(normalized)
      raise "vector is not in the prime-field subspace"
    out = []
    row = 0
    while row < @pivots.size
      out.push(normalized[@pivots[row]])
      row += 1
    out

  -> linear_combination(coefficients)
    if coefficients.class_name != "Array" || (
         coefficients.size != dimension)
      raise "prime-field coefficient vector has wrong dimension"
    out = []
    column = 0
    while column < @ambient_dimension
      value = 0
      row = 0
      while row < @basis.size
        value += coefficients[row]*@basis[row][column]
        row += 1
      out.push(PrimeLinearAlgebra.normalize(value, @prime))
      column += 1
    out

  -> sum(other)
    compatible!(other)
    PrimeFieldSubspace.new(
      @prime, @ambient_dimension, basis + other.basis)

  -> intersection(other)
    compatible!(other)
    left = basis
    right = other.basis
    width = left.size + right.size
    equations = []
    column = 0
    while column < @ambient_dimension
      equation = []
      index = 0
      while index < left.size
        equation.push(left[index][column])
        index += 1
      index = 0
      while index < right.size
        equation.push(PrimeLinearAlgebra.normalize(
          0 - right[index][column], @prime))
        index += 1
      equations.push(equation)
      column += 1
    relations = PrimeLinearAlgebra.kernel(
      equations, @prime, width)
    vectors = []
    index = 0
    while index < relations.size
      coefficients = []
      left_index = 0
      while left_index < left.size
        coefficients.push(relations[index][left_index])
        left_index += 1
      vector = []
      column = 0
      while column < @ambient_dimension
        value = 0
        left_index = 0
        while left_index < left.size
          value += coefficients[left_index]*left[left_index][column]
          left_index += 1
        vector.push(PrimeLinearAlgebra.normalize(value, @prime))
        column += 1
      vectors.push(vector)
      index += 1
    PrimeFieldSubspace.new(@prime, @ambient_dimension, vectors)

  -> orthogonal_complement
    PrimeFieldSubspace.kernel(basis, @prime, @ambient_dimension)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    ("F_" + @prime.to_s + " subspace(" + dimension.to_s + "/" +
     @ambient_dimension.to_s + ")")

  -> inspect
    to_s
