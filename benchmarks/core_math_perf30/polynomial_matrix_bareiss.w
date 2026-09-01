use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/polynomial_matrix

# Dense rank-one perturbation zI + J. Its determinant is
# z^(n-1) * (z+n), giving an exact closed-form parity oracle while forcing
# the old cofactor implementation through every minor.
field = FiniteField.new(1009)
ring = PolynomialRing.new([:z], field)
z = ring.generator(0)
size = 7
entries = []
i = 0
while i < size
  row = []
  j = 0
  while j < size
    row.push(i == j ? z + 1 : ring.one)
    j += 1
  entries.push(row)
  i += 1
matrix = PolynomialMatrix.new(ring, entries)
expected = (z ** (size - 1)) * (z + size)

warm = matrix.determinant
raise "polynomial-matrix determinant mismatch" if !warm.eql?(expected)

rounds = 12
t0 = ccall("__w_clock_ms")
round = 0
checksum = 0
while round < rounds
  determinant = matrix.determinant
  raise "polynomial-matrix determinant mismatch" if !determinant.eql?(expected)
  checksum += determinant.coeff([size]) + determinant.coeff([size - 1])
  round += 1
t1 = ccall("__w_clock_ms")

<< "checksum=" + checksum.to_s()
<< "degree=" + expected.degree.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()
