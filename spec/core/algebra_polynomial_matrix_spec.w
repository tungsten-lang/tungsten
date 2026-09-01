# Polynomial matrices over F_101[z]: row degrees, row reduction, kernels.

use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/polynomial_matrix

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = FiniteField.new(101)
ring = PolynomialRing.new([:z], field)
z = ring.generator(0)
one = ring.one
zero = ring.zero

-> all_zero(vector)
  result = true
  vector.each -> (value)
    result = false if !value.zero?
  result

# --- row degrees and reducedness ---
m1 = PolynomialMatrix.new(ring, [[z, 1], [z * z + 1, z]])
check("row_degrees", m1.row_degrees.join(","), "1,2")
check("leading matrix", m1.leading_row_coefficient_matrix.to_s, "\[\[1, 0\], \[1, 0\]\]")
check("not row reduced", m1.row_reduced?, false)
m2 = PolynomialMatrix.new(ring, [[z, 1], [1, z]])
check("row reduced", m2.row_reduced?, true)
check("Bareiss determinant", m2.determinant, z * z - 1)
pivoted = PolynomialMatrix.new(ring, [[zero, one], [one, z]])
check("Bareiss determinant row swap", pivoted.determinant, zero - one)
singular = PolynomialMatrix.new(ring, [[z, one], [z, one]])
check("Bareiss determinant singular", singular.determinant, zero)
check("Bareiss determinant empty", PolynomialMatrix.new(ring, []).determinant, one)

# --- row reduction with a unimodular transform (2x2) ---
pair = m1.row_reduce_with_transform
r1 = pair[0]
u1 = pair[1]
check("2x2 reduced is row reduced", r1.row_reduced?, true)
check("2x2 rank preserved", r1.rows, 2)
check("2x2 transform reproduces", (u1 * m1).to_s, r1.to_s)
check("2x2 transform unimodular", u1.determinant.degree, 0)
check("2x2 transform nonzero", u1.determinant.zero?, false)

# --- row reduction (3x3) ---
m3 = PolynomialMatrix.new(ring, [[z * z + 1, z, 1], [z * z * z, z * z, z], [z, 1, z + 1]])
pair3 = m3.row_reduce_with_transform
r3 = pair3[0]
u3 = pair3[1]
check("3x3 reduced is row reduced", r3.row_reduced?, true)
check("3x3 transform reproduces", (u3 * m3).to_s, r3.to_s)
check("3x3 rank preserved", r3.rows, 3)
check("3x3 transform unimodular", u3.determinant.degree, 0)
check("3x3 transform nonzero", u3.determinant.zero?, false)
check("3x3 degree sum does not grow",
      r3.row_degrees[0] + r3.row_degrees[1] + r3.row_degrees[2] <= 1 + 3 + 3, true)

# --- kernel (a): known one-dimensional kernel (1, -z, z^2) ---
ka = PolynomialMatrix.new(ring, [[z, 1, 0], [0, z, 1]])
kernel_a = ka.minimal_kernel_basis(4)
check("kernel a size", kernel_a[0].size, 1)
check("kernel a degree", kernel_a[1][0], 2)
va = kernel_a[0][0]
check("kernel a annihilated", all_zero(ka.apply(va)), true)
scale = va[0]
check("kernel a shape", (va[1] * scale - va[0] * (zero - z)).zero? && (va[2] * scale - va[0] * z * z).zero?, true)

# --- kernel (b): random 4x6 matrix with degree-1 entries ---
state = [12345]
-> next_value(state)
  state[0] = (state[0] * 1103515245 + 12345) % 2147483648
  (state[0] / 7) % 101
entries = []
i = 0
while i < 4
  row = []
  j = 0
  while j < 6
    row.push(ring.constant(next_value(state)) + z * next_value(state))
    j += 1
  entries.push(row)
  i += 1
kb = PolynomialMatrix.new(ring, entries)
kernel_b = kb.minimal_kernel_basis(8)
check("kernel b rank", kernel_b[0].size, 2)
ok = true
kernel_b[0].each -> (vector)
  ok = false if !all_zero(kb.apply(vector))
check("kernel b annihilated", ok, true)
basis_b = PolynomialMatrix.new(ring, kernel_b[0])
check("kernel b row reduced", basis_b.row_reduced?, true)
check("kernel b degree profile sum", kernel_b[1][0] + kernel_b[1][1], 4)

# --- kernel (c): tiny interpolation-type system with a planted solution ---
# Rows: evaluations of (c0 + c1 z, c2 + c3 z) at z-dependent points; the
# planted vector (z, -1, 1, 0) is annihilated by construction.
kc = PolynomialMatrix.new(ring, [[1, z, 0, 0], [0, 0, 1, z], [z, z * z, 0, 0]])
kernel_c = kc.minimal_kernel_basis(3)
ok = true
kernel_c[0].each -> (vector)
  ok = false if !all_zero(kc.apply(vector))
check("kernel c annihilated", ok, true)
check("kernel c rank", kernel_c[0].size, 2)
check("kernel c degrees", kernel_c[1].join(","), "1,1")
<< "all polynomial matrix checks passed"
