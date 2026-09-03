# Exact rational linear algebra, canonical RREF and kernels over F_p, and
# the column-basis order lattices they support.
#   bin/tungsten run spec/core/algebra_integer_lattice_spec.w
#   bin/tungsten -o /tmp/algebra-integer-lattice-spec \
#     spec/core/algebra_integer_lattice_spec.w
#
# Gram matrices and LLL live in core/algebra/lattice_reduction.w and are
# covered by spec/core/algebra_lattice_reduction_spec.w; this file covers the
# exact coordinate-change and prime-field layer underneath them.

use algebra

-> integer_lattice_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> integer_lattice_same?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if Rational.coerce(left[i]) != Rational.coerce(right[i])
    i += 1
  true

-> integer_lattice_same_matrix?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if !integer_lattice_same?(left[i], right[i])
    i += 1
  true

-> integer_lattice_raises?(thunk)
  raised = false
  begin
    thunk.call
  rescue error
    raised = true
  raised

half = Rational.new(1, 2)
third = Rational.new(1, 3)

# --- ExactRationalLinearAlgebra ------------------------------------------------
integer_lattice_check("identity.three",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.identity(3),
                        [[1, 0, 0], [0, 1, 0], [0, 0, 1]]))
integer_lattice_check("identity.entries_are_rational",
                      ExactRationalLinearAlgebra.identity(2)[0][0].class_name == "Rational")

# Columns (1,2) and (3,4) build the matrix whose rows are (1,3) and (2,4).
columns = [[1, 2], [3, 4]]
matrix = ExactRationalLinearAlgebra.matrix_from_columns(columns)
integer_lattice_check("columns.to_matrix",
                      integer_lattice_same_matrix?(matrix, [[1, 3], [2, 4]]))
integer_lattice_check("columns.round_trip",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.columns_from_matrix(matrix), columns))
integer_lattice_check("columns.rectangular",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.matrix_from_columns([[1, 2, 3], [4, 5, 6]]),
                        [[1, 4], [2, 5], [3, 6]]))

# [[1,3],[2,4]] has determinant -2, so its inverse is
#   1/(-2) [[4,-3],[-2,1]] = [[-2, 3/2], [1, -1/2]].
inverse = ExactRationalLinearAlgebra.inverse(matrix)
integer_lattice_check("inverse.two_by_two",
                      integer_lattice_same_matrix?(
                        inverse,
                        [[-2, Rational.new(3, 2)], [1, Rational.new(-1, 2)]]))
integer_lattice_check("inverse.times_matrix_is_identity",
                      integer_lattice_same?(
                        ExactRationalLinearAlgebra.matrix_vector(inverse,
                          ExactRationalLinearAlgebra.matrix_vector(matrix, [5, 7])),
                        [5, 7]))
integer_lattice_check("inverse.needs_a_pivot_swap",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.inverse([[0, 1], [1, 0]]),
                        [[0, 1], [1, 0]]))
integer_lattice_check("inverse.rational_entries",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.inverse([[half, 0], [0, third]]),
                        [[2, 0], [0, 3]]))
integer_lattice_check("inverse.singular_rejected",
                      integer_lattice_raises?(->()
                        ExactRationalLinearAlgebra.inverse([[1, 2], [2, 4]])))
integer_lattice_check("inverse.non_square_rejected",
                      integer_lattice_raises?(->()
                        ExactRationalLinearAlgebra.inverse([[1, 2, 3], [4, 5, 6]])))
integer_lattice_check("inverse.empty_rejected",
                      integer_lattice_raises?(->() ExactRationalLinearAlgebra.inverse([])))

integer_lattice_check("matrix_vector.product",
                      integer_lattice_same?(
                        ExactRationalLinearAlgebra.matrix_vector([[1, 2], [3, 4]], [1, 1]),
                        [3, 7]))
integer_lattice_check("matrix_vector.rational",
                      integer_lattice_same?(
                        ExactRationalLinearAlgebra.matrix_vector([[half, half]], [1, 3]),
                        [2]))
integer_lattice_check("matrix_vector.dimension_mismatch",
                      integer_lattice_raises?(->()
                        ExactRationalLinearAlgebra.matrix_vector([[1, 2]], [1, 2, 3])))

# compose_columns re-expresses relative coordinates in the ambient basis:
# with base columns (1,1) and (0,1), the relative column (2,3) is
# 2(1,1) + 3(0,1) = (2,5).
integer_lattice_check("compose_columns.change_of_basis",
                      integer_lattice_same_matrix?(
                        ExactRationalLinearAlgebra.compose_columns([[1, 1], [0, 1]],
                                                                   [[2, 3], [1, 0]]),
                        [[2, 5], [1, 1]]))
integer_lattice_check("same_vector.exactness",
                      ExactRationalLinearAlgebra.same_vector?([1, 2], [Rational.new(2, 2), 2]) &&
                      !ExactRationalLinearAlgebra.same_vector?([1, 2], [1, 3]) &&
                      !ExactRationalLinearAlgebra.same_vector?([1], [1, 1]))
integer_lattice_check("matrix_from_columns.rejects_empty",
                      integer_lattice_raises?(->()
                        ExactRationalLinearAlgebra.matrix_from_columns([])))
integer_lattice_check("matrix_from_columns.rejects_ragged",
                      integer_lattice_raises?(->()
                        ExactRationalLinearAlgebra.matrix_from_columns([[1, 2], [3]])))

# --- PrimeLinearAlgebra: F_p arithmetic ----------------------------------------
integer_lattice_check("prime.normalize",
                      PrimeLinearAlgebra.normalize(9, 7) == 2 &&
                      PrimeLinearAlgebra.normalize(-1, 7) == 6 &&
                      PrimeLinearAlgebra.normalize(-8, 7) == 6 &&
                      PrimeLinearAlgebra.normalize(0, 7) == 0)
# 3 * 5 = 15 = 1 (mod 7); 2 * 3 = 6 = 1 (mod 5).
integer_lattice_check("prime.inverse",
                      PrimeLinearAlgebra.inverse(3, 7) == 5 &&
                      PrimeLinearAlgebra.inverse(5, 7) == 3 &&
                      PrimeLinearAlgebra.inverse(2, 5) == 3 &&
                      PrimeLinearAlgebra.inverse(1, 11) == 1 &&
                      PrimeLinearAlgebra.inverse(-1, 7) == 6)
inverse_ok = true
value = 1
while value < 13
  inverse_ok = false if PrimeLinearAlgebra.normalize(
    value * PrimeLinearAlgebra.inverse(value, 13), 13) != 1
  value += 1
integer_lattice_check("prime.inverse_is_an_inverse_mod_13", inverse_ok)
integer_lattice_check("prime.zero_has_no_inverse",
                      integer_lattice_raises?(->() PrimeLinearAlgebra.inverse(0, 7)))
integer_lattice_check("prime.multiple_of_p_has_no_inverse",
                      integer_lattice_raises?(->() PrimeLinearAlgebra.inverse(14, 7)))

# --- Canonical RREF over F_p ---------------------------------------------------
# [[1,2],[2,4]] has rank one mod 5: the second row is twice the first.
rank_one = PrimeLinearAlgebra.rref([[1, 2], [2, 4]], 5)
integer_lattice_check("rref.rank_one",
                      integer_lattice_same_matrix?(rank_one[0], [[1, 2], [0, 0]]) &&
                      integer_lattice_same?(rank_one[1], [0]))
# [[2,3],[1,4]] has determinant 5, so it is singular mod 5 and invertible mod 7.
mod_five = PrimeLinearAlgebra.rref([[2, 3], [1, 4]], 5)
integer_lattice_check("rref.singular_mod_five",
                      integer_lattice_same_matrix?(mod_five[0], [[1, 4], [0, 0]]) &&
                      mod_five[1].size == 1)
mod_seven = PrimeLinearAlgebra.rref([[2, 3], [1, 4]], 7)
integer_lattice_check("rref.invertible_mod_seven",
                      integer_lattice_same_matrix?(mod_seven[0], [[1, 0], [0, 1]]) &&
                      integer_lattice_same?(mod_seven[1], [0, 1]))
# A pivot search that has to swap rows.
swapped = PrimeLinearAlgebra.rref([[0, 1], [1, 0]], 3)
integer_lattice_check("rref.row_swap",
                      integer_lattice_same_matrix?(swapped[0], [[1, 0], [0, 1]]) &&
                      integer_lattice_same?(swapped[1], [0, 1]))
integer_lattice_check("rref.negative_entries_normalized",
                      integer_lattice_same_matrix?(
                        PrimeLinearAlgebra.rref([[-1, -2]], 5)[0], [[1, 2]]))
integer_lattice_check("rref.empty_matrix",
                      PrimeLinearAlgebra.rref([], 5, 3)[0].size == 0 &&
                      PrimeLinearAlgebra.rref([], 5, 3)[1].size == 0)
integer_lattice_check("rref.rejects_composite_modulus",
                      integer_lattice_raises?(->() PrimeLinearAlgebra.rref([[1, 1]], 6)))
integer_lattice_check("rref.rejects_ragged",
                      integer_lattice_raises?(->() PrimeLinearAlgebra.rref([[1, 1], [1]], 5)))

# --- Kernels over F_p -----------------------------------------------------------
# [[1,2,3],[4,5,6]] reduces mod 7 to [[1,0,6],[0,1,2]], so the kernel is
# spanned by (-6, -2, 1) = (1, 5, 1).
kernel_data = PrimeLinearAlgebra.kernel_data([[1, 2, 3], [4, 5, 6]], 7)
integer_lattice_check("kernel.rref_shape",
                      integer_lattice_same?(kernel_data[1], [0, 1]) &&
                      integer_lattice_same?(kernel_data[2], [2]))
integer_lattice_check("kernel.basis",
                      integer_lattice_same_matrix?(kernel_data[0], [[1, 5, 1]]))
integer_lattice_check("kernel.shortcut_agrees",
                      integer_lattice_same_matrix?(
                        PrimeLinearAlgebra.kernel([[1, 2, 3], [4, 5, 6]], 7),
                        kernel_data[0]))
# Independent replay: A v = 0 over F_7.
kernel_vector = kernel_data[0][0]
kernel_ok = true
rows = [[1, 2, 3], [4, 5, 6]]
row_index = 0
while row_index < rows.size
  total = 0
  column = 0
  while column < 3
    total += rows[row_index][column] * kernel_vector[column]
    column += 1
  kernel_ok = false if PrimeLinearAlgebra.normalize(total, 7) != 0
  row_index += 1
integer_lattice_check("kernel.annihilates", kernel_ok)

# Over F_2, [[1,1,0],[0,1,1]] has kernel spanned by (1,1,1).
integer_lattice_check("kernel.f2",
                      integer_lattice_same_matrix?(
                        PrimeLinearAlgebra.kernel([[1, 1, 0], [0, 1, 1]], 2), [[1, 1, 1]]))
integer_lattice_check("kernel.full_rank_is_empty",
                      PrimeLinearAlgebra.kernel([[1, 0], [0, 1]], 5).size == 0)
# A zero row leaves both columns free.
integer_lattice_check("kernel.zero_matrix",
                      integer_lattice_same_matrix?(
                        PrimeLinearAlgebra.kernel([[0, 0], [0, 0]], 3),
                        [[1, 0], [0, 1]]))

# --- AlgebraOrderLattice --------------------------------------------------------
# A = Q[t]/(t^2 - 1) = Q x Q, a two-dimensional etale algebra over Q.
ring = PolynomialRing.new([:t], RationalField.new)
t = ring.generator(0)
algebra = EtaleAlgebra.new(t**2 - 1, [t - 1, t + 1])
integer_lattice_check("lattice.algebra_dimension", algebra.dimension == 2)

standard = AlgebraOrderLattice.new(algebra, [[1, 0], [0, 1]])
integer_lattice_check("lattice.rank_and_algebra",
                      standard.rank == 2 && standard.algebra == algebra)
integer_lattice_check("lattice.determinant_one", standard.determinant == 1)
integer_lattice_check("lattice.basis_is_a_copy",
                      integer_lattice_same_matrix?(standard.basis_vectors, [[1, 0], [0, 1]]))
integer_lattice_check("lattice.coordinates_round_trip",
                      integer_lattice_same?(standard.coordinates([3, 5]), [3, 5]) &&
                      integer_lattice_same?(standard.ambient_vector([3, 5]), [3, 5]))
integer_lattice_check("lattice.contains_integer_vectors",
                      standard.contains_vector?([7, -2]) &&
                      !standard.contains_vector?([half, 0]))

# The sublattice 2Z (+) 3Z has index 6 and determinant 6.
sublattice = AlgebraOrderLattice.new(algebra, [[2, 0], [0, 3]])
integer_lattice_check("lattice.sublattice_determinant", sublattice.determinant == 6)
integer_lattice_check("lattice.contains_sublattice",
                      standard.contains_lattice?(sublattice) &&
                      !sublattice.contains_lattice?(standard))
integer_lattice_check("lattice.index_six", standard.index_from(sublattice) == 6)
integer_lattice_check("lattice.index_needs_containment",
                      integer_lattice_raises?(->() sublattice.index_from(standard)))
integer_lattice_check("lattice.sublattice_membership",
                      sublattice.contains_vector?([4, 9]) &&
                      !sublattice.contains_vector?([1, 3]) &&
                      !sublattice.contains_vector?([2, 1]))
integer_lattice_check("lattice.sublattice_coordinates",
                      integer_lattice_same?(sublattice.coordinates([4, 9]), [2, 3]))

# A unimodular change of basis gives the same lattice, a different basis.
sheared = AlgebraOrderLattice.new(algebra, [[1, 0], [1, 1]])
integer_lattice_check("lattice.unimodular_same_lattice",
                      standard.same_lattice?(sheared) && sheared.determinant == 1)
integer_lattice_check("lattice.not_same_as_sublattice",
                      !standard.same_lattice?(sublattice))

# compose re-expresses a relative basis in the ambient one, so composing the
# standard lattice with (2,0), (0,3) reproduces the index-six sublattice.
composed = standard.compose([[2, 0], [0, 3]])
integer_lattice_check("lattice.compose_reproduces_sublattice",
                      composed.same_lattice?(sublattice) && composed.determinant == 6)
# Composing a sublattice again multiplies the index: [L : 2L'] = 4 * 6 = 24.
doubled = sublattice.compose([[2, 0], [0, 2]])
integer_lattice_check("lattice.compose_multiplies_index",
                      standard.index_from(doubled) == 24 && doubled.determinant == 24)

integer_lattice_check("lattice.rejects_non_etale",
                      integer_lattice_raises?(->()
                        AlgebraOrderLattice.new(ring, [[1, 0], [0, 1]])))
integer_lattice_check("lattice.rejects_wrong_basis_count",
                      integer_lattice_raises?(->()
                        AlgebraOrderLattice.new(algebra, [[1, 0]])))
integer_lattice_check("lattice.rejects_wrong_dimension",
                      integer_lattice_raises?(->()
                        AlgebraOrderLattice.new(algebra, [[1, 0, 0], [0, 1, 0]])))
integer_lattice_check("lattice.rejects_singular_basis",
                      integer_lattice_raises?(->()
                        AlgebraOrderLattice.new(algebra, [[1, 2], [2, 4]])))

<< "algebra_integer_lattice_spec: all checks passed"
