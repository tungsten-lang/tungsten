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
use core/algebra/polynomial_factor_finite
use core/algebra/simple_extension
use core/algebra/etale_algebra
use core/algebra/integer_lattice
use core/algebra/orders
use core/algebra/maximal_orders
use core/algebra/lattice_reduction
use core/algebra/residue_algebra
use core/algebra/real_roots
use core/algebra/groebner
use core/algebra/algebraic_real
use core/algebra/expression
use core/algebra/number_field
use core/algebra/prime_ideals
use core/algebra/ideal_arithmetic
use core/algebra/archimedean
use core/algebra/f2_linear
use core/algebra/s_units
use core/algebra/s_class_group
use core/algebra/projective
use core/algebra/curves
use core/algebra/local_geometry
use core/algebra/local_normalization
use core/algebra/local_invariants
use core/algebra/elliptic
use core/algebra/elliptic_tate
use core/algebra/modular_forms
use core/algebra/q_expansion
use core/algebra/modular_symbols
use core/algebra/hecke
use core/algebra/old_new
use core/algebra/newforms
use core/algebra/divisors
use core/algebra/quartics
use core/algebra/descent
use core/algebra/descent_functions
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

  -> .finite_field(characteristic, degree = nil)
    return FiniteField.new(characteristic) if degree == nil
    FiniteField.extension(characteristic, degree)

  -> .number_field(polynomial, name = :a)
    NumberField.new(polynomial, name)

  -> .extension(polynomial, name = :a)
    SimpleExtensionField.new(polynomial, name)

  -> .simple_extension(polynomial, name = :a)
    SimpleExtensionField.new(polynomial, name)

  -> .etale_algebra(polynomial)
    EtaleAlgebra.new(polynomial)

  -> .etale_algebra(polynomial, components)
    EtaleAlgebra.new(polynomial, components)

  -> .order(polynomial)
    MonogenicOrder.new(polynomial)

  -> .product_order(polynomials)
    EtaleProductOrder.new(polynomials)

  -> .maximal_order(
       order, factor_search_limit = 1_000_000,
       step_limit = 10_000)
    order.maximal_order(
      factor_search_limit, step_limit)

  -> .prime_decomposition(
       order, prime,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    order.prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit)

  -> .rational_projective_plane(x = :X, y = :Y, z = :Z)
    ProjectiveSpace<ℚ, 2>.new(x, y, z)

  -> .integral_weierstrass(a1, a2, a3, a4, a6)
    IntegralWeierstrassModel.new(a1, a2, a3, a4, a6)

  -> .frey_curve(a, b, exponent)
    FreyCurve.new(a, b, exponent)

  -> .frey_curve_from_solution(a, b, c, exponent)
    FreyCurve.from_fermat_solution(a, b, c, exponent)

  -> .gamma0(level)
    Gamma0.new(level)

  -> .modular_curve_x0(level)
    ModularCurveX0.new(level)

  -> .cusp_forms(level, weight = 2)
    CuspForms.new(level, weight)

  -> .modular_forms(level, weight = 2)
    ModularForms.new(level, weight)

  -> .eisenstein_e4(precision = 12)
    ClassicalModularForms.e4(precision)

  -> .eisenstein_e6(precision = 12)
    ClassicalModularForms.e6(precision)

  -> .modular_delta(precision = 12)
    ClassicalModularForms.delta(precision)

  -> .modular_symbols(level, weight = 2,
                      search_limit = 1_000_000)
    WeightTwoModularSymbols.new(
      level, weight, search_limit)

  -> .hecke_operator(level, prime,
                     search_limit = 1_000_000)
    WeightTwoModularSymbols.new(
      level, 2, search_limit).hecke_operator(prime)

  -> .old_new_decomposition(level,
                            search_limit = 1_000_000)
    WeightTwoModularSymbols.new(
      level, 2, search_limit).old_new_decomposition

  -> .rational_newform(level, precision = 12,
                       search_limit = 1_000_000)
    RationalWeightTwoNewform.new(
      level, precision, search_limit)

  -> .eigenpackets(level, search_limit = 1_000_000)
    WeightTwoHeckeEigenpacketDecomposition.new(
      level, search_limit)

  -> .newton_polygon(polynomial, x_variable = 0,
                      y_variable = 1, center = nil)
    polynomial.newton_polygon(
      x_variable, y_variable, center)

  -> .local_singularity(polynomial, x_variable = 0,
                         y_variable = 1, point = nil)
    polynomial.local_singularity(
      x_variable, y_variable, point)

  -> .puiseux_branches(polynomial, x_variable = 0,
                        y_variable = 1, center = nil,
                        maximum_power = 6,
                        search_margin = 0,
                        recursion_limit = 8)
    polynomial.puiseux_branches(
      x_variable, y_variable, center,
      maximum_power, search_margin,
      recursion_limit)

  -> .puiseux_sheets(polynomial, x_variable = 0,
                      y_variable = 1, center = nil,
                      maximum_power = 6,
                      search_margin = 0,
                      recursion_limit = 8)
    polynomial.puiseux_sheets(
      x_variable, y_variable, center,
      maximum_power, search_margin,
      recursion_limit)

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
