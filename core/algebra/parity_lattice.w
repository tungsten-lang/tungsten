# Exact Construction-A parity lift for affine binary systems.  A consistent
# system Hx=b determines the lattice L={z in Z^n : Hz=0 mod 2} and a coset
# representative u with Hu=b.  In systematic coordinates the basis is
#
#       [ I   0 ]
#   B = [ P  2I ],
#
# so |det B|=2^rank(H).  Reducing u-lambda coordinatewise modulo two turns
# closest-vector candidates into affine binary solutions; minimizing any
# l_p^p distance therefore recovers minimum Hamming weight.  This file builds
# and replays the finite algebraic construction; it is not a general CVP
# solver.

use core/algebra/lattice_polytope
use core/algebra/integer_lattice

+ ParityLiftLinearAlgebra
  -> .rref_with_rhs(matrix, rhs)
    if matrix.class_name != "Array" || rhs.class_name != "Array"
      raise "parity lift needs a matrix and right-hand side"
    if matrix.size != rhs.size
      raise "parity matrix and right-hand side have different heights"
    width = matrix.size == 0 ? 0 : matrix[0].size
    rows = []
    values = []
    i = 0
    while i < matrix.size
      if matrix[i].class_name != "Array" || matrix[i].size != width
        raise "parity matrix rows have inconsistent widths"
      row = []
      matrix[i].each -> (entry)
        if !LatticeCombinatorics.integer?(entry)
          raise "parity matrix entries must be integers"
        row.push(PrimeLinearAlgebra.normalize(entry, 2))
      if !LatticeCombinatorics.integer?(rhs[i])
        raise "parity right-hand side entries must be integers"
      rows.push(row)
      values.push(PrimeLinearAlgebra.normalize(rhs[i], 2))
      i += 1

    pivots = []
    pivot_row = 0
    column = 0
    while pivot_row < rows.size && column < width
      selected = pivot_row
      while selected < rows.size && rows[selected][column] == 0
        selected += 1
      if selected == rows.size
        column += 1
      else
        if selected != pivot_row
          temporary = rows[pivot_row]
          rows[pivot_row] = rows[selected]
          rows[selected] = temporary
          temporary_value = values[pivot_row]
          values[pivot_row] = values[selected]
          values[selected] = temporary_value
        row = 0
        while row < rows.size
          if row != pivot_row && rows[row][column] != 0
            cell = column
            while cell < width
              rows[row][cell] = rows[row][cell] ^ rows[pivot_row][cell]
              cell += 1
            values[row] = values[row] ^ values[pivot_row]
          row += 1
        pivots.push(column)
        pivot_row += 1
        column += 1

    row = pivot_row
    while row < rows.size
      nonzero = false
      rows[row].each -> nonzero = true if item != 0
      if !nonzero && values[row] != 0
        raise "affine parity system is inconsistent"
      row += 1
    [rows, values, pivots]


+ ParityLiftCertificate
  -> new(@lift)

  -> proof_kind
    :exact_construction_a_parity_lift

  -> verified?
    begin
      return verify!
    rescue error
      false

  -> verify!
    return false if @lift.class_name != "ParityLiftLattice"
    return false if !@lift.affine_solution?(@lift.particular_solution)
    basis = @lift.basis
    return false if basis.size != @lift.dimension
    determinant = ExactIntegerLinearAlgebra.determinant(basis).abs
    return false if determinant != 2 ** @lift.rank
    column = 0
    while column < @lift.dimension
      vector = []
      row = 0
      while row < @lift.dimension
        vector.push(basis[row][column])
        row += 1
      return false if !@lift.kernel_vector?(vector)
      column += 1
    true


+ ParityLiftLattice
  -> new(parity_checks, rhs = nil)
    if parity_checks.class_name != "Array" || parity_checks.size == 0
      raise "parity lift needs at least one parity check"
    @dimension = parity_checks[0].size
    if @dimension < 1
      raise "parity lift needs at least one binary variable"
    supplied_rhs = rhs
    if supplied_rhs == nil
      supplied_rhs = []
      parity_checks.size.times -> supplied_rhs.push(0)
    reduced = ParityLiftLinearAlgebra.rref_with_rhs(
      parity_checks, supplied_rhs)
    @rref = reduced[0]
    @reduced_rhs = reduced[1]
    @pivots = reduced[2]
    @checks = []
    parity_checks.each -> (source)
      row = []
      source.each -> row.push(PrimeLinearAlgebra.normalize(item, 2))
      @checks.push(row)
    @rhs = []
    supplied_rhs.each -> @rhs.push(PrimeLinearAlgebra.normalize(item, 2))
    @free = []
    column = 0
    while column < @dimension
      @free.push(column) if !@pivots.include?(column)
      column += 1
    @particular = build_particular_solution
    @basis = build_basis
    @certificate = ParityLiftCertificate.new(self)

  -> dimension
    @dimension

  -> rank
    @pivots.size

  -> nullity
    @free.size

  -> pivot_columns
    LatticeCombinatorics.copy_vector(@pivots)

  -> free_columns
    LatticeCombinatorics.copy_vector(@free)

  -> basis
    LatticeCombinatorics.copy_matrix(@basis)

  -> particular_solution
    LatticeCombinatorics.copy_vector(@particular)

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> build_particular_solution
    solution = []
    @dimension.times -> solution.push(0)
    row = 0
    while row < @pivots.size
      solution[@pivots[row]] = @reduced_rhs[row]
      row += 1
    solution

  -> build_basis
    rows = []
    @dimension.times ->
      row = []
      @dimension.times -> row.push(0)
      rows.push(row)

    basis_column = 0
    @free.each -> (free_column)
      rows[free_column][basis_column] = 1
      pivot_row = 0
      while pivot_row < @pivots.size
        rows[@pivots[pivot_row]][basis_column] = @rref[pivot_row][free_column]
        pivot_row += 1
      basis_column += 1

    @pivots.each -> (pivot_column)
      rows[pivot_column][basis_column] = 2
      basis_column += 1
    rows

  -> syndrome(vector)
    if vector.class_name != "Array" || vector.size != @dimension
      raise "parity vector has the wrong dimension"
    out = []
    @checks.each -> (check)
      value = 0
      i = 0
      while i < @dimension
        if !LatticeCombinatorics.integer?(vector[i])
          raise "parity vectors must have integer coordinates"
        value = value ^ (
          check[i] & PrimeLinearAlgebra.normalize(vector[i], 2))
        i += 1
      out.push(value)
    out

  -> kernel_vector?(vector)
    syndrome(vector).each -> return false if item != 0
    true

  -> affine_solution?(vector)
    values = syndrome(vector)
    return false if values.size != @rhs.size
    i = 0
    while i < values.size
      return false if values[i] != @rhs[i]
      i += 1
    true

  # Every lattice vector gives a binary solution by reducing u-lambda mod 2.
  -> solution_from_lattice_vector(vector)
    raise "vector is not in the parity lattice" if !kernel_vector?(vector)
    solution = []
    i = 0
    while i < @dimension
      solution.push(PrimeLinearAlgebra.normalize(
        @particular[i] - vector[i], 2))
      i += 1
    solution

  # Small exact reference search for tests and benchmark generation.  The
  # exponential limit is explicit; production minimum decoding belongs in a
  # SAT/CVP engine.
  -> minimum_hamming_solution(candidate_limit = 16_777_216)
    total = 1 << @dimension
    if total > candidate_limit
      raise "minimum Hamming search exceeds its explicit candidate limit"
    best_weight = @dimension + 1
    best = nil
    mask = 0
    while mask < total
      vector = []
      weight = 0
      i = 0
      while i < @dimension
        bit = (mask >> i) & 1
        vector.push(bit)
        weight += bit
        i += 1
      if weight < best_weight && affine_solution?(vector)
        best_weight = weight
        best = vector
      mask += 1
    [best_weight, best]
