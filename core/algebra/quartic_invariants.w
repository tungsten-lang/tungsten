# Exact discriminants for ternary quartics.
#
# The three first partial derivatives of a ternary quartic are homogeneous
# cubics.  Their homogeneous resultant is computed with Macaulay's degree-7
# matrix: a 36x36 determinant divided by its 9x9 extraneous minor.  This is a
# coefficient-independent construction; no quartic family or fixture is
# recognized specially.
#
# Macaulay's quotient is evaluated in a chart where the extraneous minor is
# nonzero.  Permuting or taking invertible linear combinations of the three
# input cubics changes the resultant by a known determinant power, which is
# divided back out.  If every inexpensive chart degenerates, an exact
# projective Groebner test still certifies the zero-resultant case.  A rare
# root-free system outside these charts fails loudly rather than returning a
# guessed value.

+ MacaulayResultant
  -> .ternary(forms)
    if forms.class_name != "Array" || forms.size != 3
      raise "a ternary Macaulay resultant needs three forms"
    degrees = []
    forms.each ->
      if item.class_name != "Polynomial" || item.zero?
        raise "cannot infer the declared degree of a zero Macaulay form"
      degrees.push(item.degree)
    MacaulayResultant.ternary(forms, degrees)

  -> .ternary(forms, degrees)
    if forms.class_name != "Array" || forms.size != 3
      raise "a ternary Macaulay resultant needs three forms"
    if degrees.class_name != "Array" || degrees.size != 3
      raise "a ternary Macaulay resultant needs three declared degrees"

    ring = forms[0].ring
    i = 0
    while i < 3
      if forms[i].class_name != "Polynomial" || forms[i].ring != ring
        raise "Macaulay forms must belong to one polynomial ring"
      if degrees[i] <= 0
        raise "Macaulay form degrees must be positive"
      if !forms[i].zero?
        if !forms[i].homogeneous? || forms[i].degree != degrees[i]
          raise "Macaulay forms must be homogeneous of their declared degrees"
      i += 1
    if ring.arity != 3
      raise "a ternary Macaulay resultant needs a three-variable ring"

    # Linear mixing preserves degrees only in the unmixed case.  That is the
    # case needed by quartic partials and gives enough deterministic charts to
    # avoid the 0/0 specialization common for sparse systems.
    if degrees[0] == degrees[1] && degrees[1] == degrees[2]
      candidate = MacaulayResultant.ternary_unmixed(forms, degrees[0])
      return candidate if candidate != nil
    else
      candidate = MacaulayResultant.macaulay_quotient(forms, degrees)
      return candidate if candidate != nil

    # A vanishing resultant is still decidable when every extraneous minor
    # vanishes: the forms have a common projective zero exactly when one of
    # the three affine chart ideals is not the unit ideal.
    if MacaulayResultant.projective_common_zero?(forms)
      return ring.field.zero

    raise "Macaulay resultant chart search exhausted for a root-free system"

  -> .ternary_unmixed(forms, degree)
    transformations = MacaulayResultant.permutation_matrices
    transformations.each -> (matrix)
      value = MacaulayResultant.transformed_quotient(forms, degree, matrix)
      return value if value != nil

    # Along this Vandermonde family det(A)=2.  Each entry has degree at most
    # two in t, while the cubic extraneous minor has size nine, so testing
    # nineteen values exhausts any nonzero restriction of that minor.
    t = 0
    while t <= 18
      matrix = [
        [1, t, t * t],
        [1, t + 1, (t + 1) * (t + 1)],
        [1, t + 2, (t + 2) * (t + 2)]
      ]
      value = MacaulayResultant.transformed_quotient(forms, degree, matrix)
      return value if value != nil
      t += 1
    nil

  -> .permutation_matrices
    [
      [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
      [[1, 0, 0], [0, 0, 1], [0, 1, 0]],
      [[0, 1, 0], [1, 0, 0], [0, 0, 1]],
      [[0, 1, 0], [0, 0, 1], [1, 0, 0]],
      [[0, 0, 1], [1, 0, 0], [0, 1, 0]],
      [[0, 0, 1], [0, 1, 0], [1, 0, 0]]
    ]

  -> .integer_matrix_determinant(matrix)
    first = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
    second = matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0])
    third = matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
    first - second + third

  -> .mix_forms(forms, matrix)
    ring = forms[0].ring
    mixed = []
    row = 0
    while row < 3
      form = ring.zero
      column = 0
      while column < 3
        coefficient = matrix[row][column]
        form = form + forms[column] * coefficient if coefficient != 0
        column += 1
      mixed.push(form)
      row += 1
    mixed

  -> .transformed_quotient(forms, degree, matrix)
    determinant = MacaulayResultant.integer_matrix_determinant(matrix)
    field = forms[0].ring.field
    determinant_element = field.coerce(determinant)
    return nil if field.zero?(determinant_element)

    mixed = MacaulayResultant.mix_forms(forms, matrix)
    quotient = MacaulayResultant.macaulay_quotient(
      mixed, [degree, degree, degree])
    return nil if quotient == nil

    # For three forms of common degree d,
    # Res(A f_0, A f_1, A f_2) = det(A)^(d^2) Res(f_0,f_1,f_2).
    field.divide(quotient, field.power(determinant_element, degree * degree))

  -> .degree_monomials(total)
    monomials = []
    first = total
    while first >= 0
      second = total - first
      while second >= 0
        monomials.push([first, second, total - first - second])
        second -= 1
      first -= 1
    monomials

  -> .same_exponents?(left, right)
    left[0] == right[0] && left[1] == right[1] && left[2] == right[2]

  -> .monomial_index(monomials, target)
    i = 0
    while i < monomials.size
      return i if MacaulayResultant.same_exponents?(monomials[i], target)
      i += 1
    raise "Macaulay matrix produced a monomial outside its degree"

  -> .macaulay_matrix(forms, degrees, monomials)
    field = forms[0].ring.field
    matrix = []
    row_index = 0
    while row_index < monomials.size
      monomial = monomials[row_index]
      selected = 0
      while selected < 3 && monomial[selected] < degrees[selected]
        selected += 1
      if selected == 3
        raise "Macaulay degree did not cover every row monomial"

      multiplier = [monomial[0], monomial[1], monomial[2]]
      multiplier[selected] -= degrees[selected]
      row = []
      column = 0
      while column < monomials.size
        row.push(field.zero)
        column += 1

      forms[selected].each_term -> (coefficient, exponents)
        target = [
          multiplier[0] + exponents[0],
          multiplier[1] + exponents[1],
          multiplier[2] + exponents[2]
        ]
        column = MacaulayResultant.monomial_index(monomials, target)
        row[column] = coefficient
      matrix.push(row)
      row_index += 1
    matrix

  -> .nonreduced_indices(monomials, degrees)
    indices = []
    i = 0
    while i < monomials.size
      divisible = 0
      variable = 0
      while variable < 3
        divisible += 1 if monomials[i][variable] >= degrees[variable]
        variable += 1
      indices.push(i) if divisible >= 2
      i += 1
    indices

  -> .submatrix(matrix, indices)
    result = []
    indices.each -> (row_index)
      row = []
      indices.each -> (column_index)
        row.push(matrix[row_index][column_index])
      result.push(row)
    result

  # Macaulay's homogeneous resultant formula:
  #
  #   Res(f0,f1,f2) = det(M_delta) / det(E_delta),
  #   delta = (d0-1)+(d1-1)+(d2-1)+1.
  #
  # E is the principal submatrix indexed by monomials divisible by at least
  # two of X^d0, Y^d1, Z^d2.  For three cubics M is 36x36 and E is 9x9.
  -> .macaulay_quotient(forms, degrees)
    total = degrees[0] + degrees[1] + degrees[2] - 2
    monomials = MacaulayResultant.degree_monomials(total)
    matrix = MacaulayResultant.macaulay_matrix(forms, degrees, monomials)
    nonreduced = MacaulayResultant.nonreduced_indices(monomials, degrees)
    extraneous = MacaulayResultant.submatrix(matrix, nonreduced)
    field = forms[0].ring.field
    denominator = Algebra.determinant_raw(extraneous, field)
    return nil if field.zero?(denominator)
    numerator = Algebra.determinant_raw(matrix, field)
    field.divide(numerator, denominator)

  -> .projective_common_zero?(forms)
    ring = forms[0].ring
    variable = 0
    while variable < 3
      generators = []
      forms.each -> generators.push(item)
      generators.push(ring.generator(variable) - ring.field.one)
      return true if !Ideal.new(generators).unit?
      variable += 1
    false


# This object is deliberately not an Array of thirteen zero-filled entries.
# Only I27 is implemented, so asking for another Dixmier--Ohno invariant is an
# explicit capability error.  `.last` preserves the useful Magma-shaped call
# in quartic programs without pretending that I3,...,J21 were computed.
+ PartialDixmierOhnoInvariants
  -> new(@i27)

  -> i27
    @i27

  -> last
    @i27

  -> size
    1

  -> complete?
    false

  -> weights
    [27]

  -> to_a
    [@i27]

  -> [](index)
    return @i27 if index == 0 || index == -1
    raise "only the Dixmier-Ohno invariant I27 is implemented"

  -> invariant(name)
    return @i27 if name.to_s == "I27" || name.to_s == "i27"
    raise "only the Dixmier-Ohno invariant I27 is implemented"

  -> to_s
    "PartialDixmierOhnoInvariants(I27=" + @i27.to_s + ")"

  -> inspect
    to_s


+ Polynomial
  -> assert_ternary_quartic_over_rationals
    if @ring.arity != 3
      raise "ternary quartic invariants need a three-variable polynomial"
    if @ring.field.class_name != "RationalField"
      raise "ternary quartic I27 currently requires coefficients in ℚ"
    if zero? || !homogeneous? || degree != 4
      raise "ternary quartic invariants need a nonzero homogeneous quartic"
    self

  -> ternary_quartic_partial_resultant
    assert_ternary_quartic_over_rationals
    partials = [derivative(0), derivative(1), derivative(2)]
    MacaulayResultant.ternary(partials, [3, 3, 3])

  # Magma's `IntegralNormalization := true` /
  # `DiscriminantOfTernaryQuartic` normalization:
  #
  #   D(f) = -Res(f_X,f_Y,f_Z) / 4^7.
  #
  # It has degree 27 in the quartic coefficients and equals -2^40 on
  # X^4+Y^4+Z^4.
  -> ternary_quartic_discriminant
    resultant = ternary_quartic_partial_resultant
    @ring.field.divide(
      @ring.field.negate(resultant),
      @ring.field.coerce(4 ** 7))

  -> discriminant_of_ternary_quartic
    ternary_quartic_discriminant

  # Magma's default (non-IntegralNormalization) return value in the I27 slot.
  # It is the value above divided by 2^40.  The handbook discusses the
  # integral-normalized degree-27 invariant, while the intrinsic defaults to
  # this scaled value; keeping the intrinsic's default scale is what makes
  # `f.dixmier_ohno.last` agree with the shell-width companion calculation.
  -> dixmier_ohno_i27
    @ring.field.divide(
      ternary_quartic_discriminant,
      @ring.field.coerce(2 ** 40))

  -> dixmier_ohno
    PartialDixmierOhnoInvariants.new(dixmier_ohno_i27)


+ Curve
  -> ternary_quartic_discriminant
    @equation.ternary_quartic_discriminant

  -> dixmier_ohno
    @equation.dixmier_ohno
