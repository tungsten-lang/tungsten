# Construction-A parity lift from affine binary systems to integer lattices.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_parity_lattice_spec.w
#   bin/tungsten compile spec/core/algebra_parity_lattice_spec.w \
#     --out /tmp/algebra-parity-lattice-spec

use algebra

-> parity_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> same_parity_vector?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

-> direct_affine_solution?(matrix, rhs, vector)
  row = 0
  while row < matrix.size
    parity = 0
    column = 0
    while column < vector.size
      parity = parity ^ ((matrix[row][column] & 1) * vector[column])
      column += 1
    return false if parity != (rhs[row] & 1)
    row += 1
  true

-> direct_solution_summary(matrix, rhs, dimension)
  count = 0
  minimum = dimension + 1
  mask = 0
  while mask < (1 << dimension)
    vector = []
    weight = 0
    column = 0
    while column < dimension
      bit = (mask >> column) & 1
      vector.push(bit)
      weight += bit
      column += 1
    if direct_affine_solution?(matrix, rhs, vector)
      count += 1
      minimum = weight if weight < minimum
    mask += 1
  [count, minimum]

lift = ParityLiftLattice.new(
  [[1, 1, 0], [0, 1, 1]],
  [1, 0])

parity_check("rank", lift.rank == 2)
parity_check("nullity", lift.nullity == 1)
parity_check("determinant",
             ExactIntegerLinearAlgebra.determinant(lift.basis).abs == 4)
parity_check("particular",
             same_parity_vector?(lift.particular_solution, [1, 0, 0]))
parity_check("particular.solves", lift.affine_solution?(lift.particular_solution))
parity_check("certificate.kind",
             lift.certificate.proof_kind == :exact_construction_a_parity_lift)
parity_check("certificate.verified", lift.certified?)

minimum = lift.minimum_hamming_solution
parity_check("minimum.weight", minimum[0] == 1)
parity_check("minimum.solution", same_parity_vector?(minimum[1], [1, 0, 0]))

# The first systematic basis column is [1,1,1], a codeword.  Subtracting it
# from u and reducing modulo two gives the other affine solution [0,1,1].
codeword = []
row = 0
while row < lift.dimension
  codeword.push(lift.basis[row][0])
  row += 1
parity_check("basis.column.kernel", lift.kernel_vector?(codeword))
other = lift.solution_from_lattice_vector(codeword)
parity_check("coset.solution", same_parity_vector?(other, [0, 1, 1]))
parity_check("coset.solution.solves", lift.affine_solution?(other))

inconsistent_raised = false
begin
  ParityLiftLattice.new([[1], [1]], [0, 1])
rescue error
  inconsistent_raised = error.to_s.include?("inconsistent")
parity_check("inconsistent.rejected", inconsistent_raised)

# Exhaust every 2-by-3 binary matrix and right-hand side. This independently
# checks consistency, affine-solution count, and minimum weight for all 256
# systems against the certified systematic lift.
matrix_mask = 0
while matrix_mask < 64
  matrix = [[], []]
  bit_index = 0
  while bit_index < 6
    matrix[bit_index / 3].push((matrix_mask >> bit_index) & 1)
    bit_index += 1
  rhs_mask = 0
  while rhs_mask < 4
    rhs = [rhs_mask & 1, (rhs_mask >> 1) & 1]
    direct = direct_solution_summary(matrix, rhs, 3)
    if direct[0] == 0
      rejected = false
      begin
        ParityLiftLattice.new(matrix, rhs)
      rescue error
        rejected = error.to_s.include?("inconsistent")
      parity_check("exhaustive.inconsistent.[matrix_mask].[rhs_mask]", rejected)
    else
      candidate = ParityLiftLattice.new(matrix, rhs)
      found = candidate.minimum_hamming_solution
      parity_check("exhaustive.certified.[matrix_mask].[rhs_mask]",
                   candidate.certified?)
      parity_check("exhaustive.count.[matrix_mask].[rhs_mask]",
                   (1 << candidate.nullity) == direct[0])
      parity_check("exhaustive.minimum.[matrix_mask].[rhs_mask]",
                   found[0] == direct[1])
    rhs_mask += 1
  matrix_mask += 1

<< "algebra_parity_lattice_spec: all checks passed"
