# Exact algebraic structures.
#
# `use algebra` is the single feature flag.  The implementation is split by
# mathematical layer so coefficient domains, polynomial arithmetic, ideals,
# projective geometry, and curves can evolve independently:
#
#   Field -> PolynomialRing[K][x, ...] -> Ideal / Scheme / Curve
#                    ^
#             local surface rewrite
#
# The source rewrite is deliberately local to algebra declarations and the
# generic entry points documented in doc/algebra.md.  It does not install
# implicit multiplication for ordinary Tungsten expressions.

use core/numeric/rational
use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/polynomial_resultant
use core/algebra/polynomial_gcd
use core/algebra/polynomial_factor
use core/algebra/number_field
use core/algebra/groebner
use core/algebra/f2_linear
use core/algebra/projective
use core/algebra/curves
use core/algebra/divisors
use core/algebra/quartics
use core/algebra/descent
use core/algebra/point_search
use core/algebra/quartic_invariants
use core/algebra/automorphisms
use core/algebra/zeta
use core/algebra/galois


+ Algebra
  -> .field(name)
    return Field.require_supported(name) if Field.supported?(name)
    Field.for(name)

  -> .rational_field
    RationalField.new

  -> .finite_field(characteristic)
    FiniteField.new(characteristic)

  -> .finite_field(characteristic, degree)
    FiniteField.extension(characteristic, degree)

  -> .number_field(polynomial, name = :a)
    NumberField.new(polynomial, name)

  -> .rational_projective_plane(x = :X, y = :Y, z = :Z)
    ProjectiveSpace<ℚ, 2>.new(x, y, z)

  # Exact determinant over an explicit coefficient field.  This is
  # intentionally separate from LinAlg's floating-point determinant path.
  #
  # Over ℚ each row is scaled to integers and eliminated with Bareiss's
  # fraction-free algorithm: every intermediate entry is itself a minor of
  # the integer matrix, so the two-by-two update divides exactly and entries
  # stay near the Hadamard determinant bound instead of the combinatorial
  # numerator/denominator growth of rational Gaussian pivoting.  Any other
  # field uses exact division-based elimination, where coefficient growth is
  # not the failure mode.
  -> .determinant(matrix, coefficient_field = nil)
    field = coefficient_field == nil ? RationalField.new : Field.require_supported(coefficient_field)
    Algebra.determinant_elements(matrix, field, false)

  # Internal/raw variant for matrices whose entries are already normalized
  # coefficient-field elements.
  -> .determinant_raw(matrix, coefficient_field = nil)
    field = coefficient_field == nil ? RationalField.new : Field.require_supported(coefficient_field)
    Algebra.determinant_elements(matrix, field, true)

  -> .determinant_elements(matrix, field, raw)
    n = matrix.size
    return field.one if n == 0

    rows = []
    matrix.each -> (source_row)
      raise "determinant needs a square matrix" if source_row.size != n
      row = []
      source_row.each -> (entry)
        value = raw ? field.normalize_element(entry) : field.coerce(entry)
        row.push(value)
      rows.push(row)

    return Algebra.bareiss_rational_determinant(rows) if field.class_name == "RationalField"
    Algebra.field_gaussian_determinant(rows, field)

  # Bareiss fraction-free elimination on the integerized matrix.  Rows of
  # Rational entries are each scaled by their denominators' LCM; the integer
  # determinant is divided back by the product of the row scales at the end.
  -> .bareiss_rational_determinant(rows)
    n = rows.size
    work = []
    scale = 1
    rows.each -> (row)
      common = 1
      row.each ->
        d = item.denominator
        common = (common / common.gcd(d)) * d
      ints = []
      row.each -> ints.push(item.numerator * (common / item.denominator))
      work.push(ints)
      scale = scale * common

    sign = 1
    previous_pivot = 1
    k = 0
    while k < n
      pivot = k
      while pivot < n && work[pivot][k] == 0
        pivot += 1
      return Rational.new(0) if pivot == n
      if pivot != k
        swapped = work[k]
        work[k] = work[pivot]
        work[pivot] = swapped
        sign = 0 - sign
      i = k + 1
      while i < n
        j = k + 1
        while j < n
          # Exact by construction: the numerator is prev_pivot times a
          # 2x2-condensed minor of the original integer matrix.
          work[i][j] = (work[i][j] * work[k][k] - work[i][k] * work[k][j]) / previous_pivot
          j += 1
        work[i][k] = 0
        i += 1
      previous_pivot = work[k][k]
      k += 1
    Rational.new(sign * work[n - 1][n - 1], scale)

  # Division-based exact elimination for fields where entry growth is not a
  # concern (finite fields, once they exist).
  -> .field_gaussian_determinant(rows, field)
    n = rows.size
    sign = field.one
    column = 0
    while column < n
      pivot = column
      while pivot < n && field.equal?(rows[pivot][column], field.zero)
        pivot += 1
      return field.zero if pivot == n

      if pivot != column
        swapped = rows[column]
        rows[column] = rows[pivot]
        rows[pivot] = swapped
        sign = field.negate(sign)

      row = column + 1
      while row < n
        if !field.equal?(rows[row][column], field.zero)
          factor = field.divide(rows[row][column], rows[column][column])
          cell = column
          while cell < n
            rows[row][cell] = field.subtract(
              rows[row][cell],
              field.multiply(factor, rows[column][cell]))
            cell += 1
        row += 1
      column += 1

    result = sign
    diagonal = 0
    while diagonal < n
      result = field.multiply(result, rows[diagonal][diagonal])
      diagonal += 1
    result
