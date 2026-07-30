# Tate's algorithm over Q for certified Kodaira symbols, Tamagawa numbers,
# split multiplicative status, and wild conductor exponents.
#
# Input is an integral model with a replay-certified p-minimality proof.
# Every coordinate change is an IntegralWeierstrassTransformation and the
# certificate reruns the complete branch calculation from the source model.

+ EllipticTateAlgorithm
  -> .mod(value, prime)
    reduced = value % prime
    reduced += prime if reduced < 0
    reduced

  -> .divisible_power?(value, prime, exponent)
    return true if value == 0
    value % (prime**exponent) == 0

  -> .exact_quotient(value, divisor)
    if value % divisor != 0
      raise "Tate algorithm expected an exact integral quotient"
    value / divisor

  -> .inverse_mod(value, prime)
    EllipticTateAlgorithm.mod(value, prime).invmod(prime)

  -> .nth_root_mod(value, exponent, prime, search_limit = 250_000)
    if prime > search_limit
      raise "Tate root search unknown: residue field exceeds limit"
    target = EllipticTateAlgorithm.mod(value, prime)
    candidate = 0
    while candidate < prime
      return candidate if candidate.pow(exponent, prime) == target
      candidate += 1
    raise "Tate algorithm expected a residue-field root"

  -> .quadratic_has_root?(a, b, c, prime, search_limit = 250_000)
    aa = EllipticTateAlgorithm.mod(a, prime)
    bb = EllipticTateAlgorithm.mod(b, prime)
    cc = EllipticTateAlgorithm.mod(c, prime)
    return bb != 0 || cc == 0 if aa == 0
    if prime == 2
      return true if cc == 0
      return EllipticTateAlgorithm.mod(aa + bb + cc, prime) == 0
    discriminant = EllipticTateAlgorithm.mod(
      bb**2 - 4*aa*cc, prime)
    return true if discriminant == 0
    discriminant.pow((prime - 1) / 2, prime) == 1

  -> .cubic_root_count(b, c, d, prime, search_limit = 250_000)
    if prime == 2
      count = 0
      candidate = 0
      while candidate < prime
        value = candidate**3 + b*candidate**2 + c*candidate + d
        count += 1 if EllipticTateAlgorithm.mod(value, prime) == 0
        candidate += 1
      return count

    # This method is called only after the cubic discriminant is known to be
    # nonzero. Its Frobenius permutation is a transposition exactly when the
    # discriminant is a nonsquare, giving one root. In the square case the
    # cubic either splits completely or is irreducible; x^p mod f tells which
    # in O(log p) field operations instead of scanning all residues.
    discriminant = (
      b**2*c**2 - 4*c**3 - 4*b**3*d - 27*d**2 + 18*b*c*d)
    residue_discriminant = EllipticTateAlgorithm.mod(
      discriminant, prime)
    character = residue_discriminant.pow((prime - 1) / 2, prime)
    return 1 if character != 1
    frobenius_x = EllipticTateAlgorithm.cubic_x_power(
      prime, b, c, d, prime)
    splits = (
      frobenius_x[0] == 0 &&
      frobenius_x[1] == 1 &&
      frobenius_x[2] == 0)
    splits ? 3 : 0

  -> .cubic_multiply(left, right, b, c, d, prime)
    raw = [0, 0, 0, 0, 0]
    i = 0
    while i < 3
      j = 0
      while j < 3
        raw[i + j] = EllipticTateAlgorithm.mod(
          raw[i + j] + left[i]*right[j], prime)
        j += 1
      i += 1

    degree = 4
    while degree >= 3
      coefficient = raw[degree]
      if coefficient != 0
        raw[degree] = 0
        raw[degree - 1] = EllipticTateAlgorithm.mod(
          raw[degree - 1] - coefficient*b, prime)
        raw[degree - 2] = EllipticTateAlgorithm.mod(
          raw[degree - 2] - coefficient*c, prime)
        raw[degree - 3] = EllipticTateAlgorithm.mod(
          raw[degree - 3] - coefficient*d, prime)
      degree -= 1
    [raw[0], raw[1], raw[2]]

  -> .cubic_x_power(exponent, b, c, d, prime)
    result = [1, 0, 0]
    base = [0, 1, 0]
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = EllipticTateAlgorithm.cubic_multiply(
          result, base, b, c, d, prime)
      remaining /= 2
      if remaining > 0
        base = EllipticTateAlgorithm.cubic_multiply(
          base, base, b, c, d, prime)
    result

  -> .translated(model, r, s, t, transformations)
    step = model.transform(1, r, s, t)
    transformations.push(step)
    step.target

  -> .initial_translation(model, prime, search_limit)
    b2 = model.b2
    b4 = model.b4
    b6 = model.b6
    c4 = model.c4
    c6 = model.c6
    r = 0
    t = 0
    if prime == 2
      if EllipticTateAlgorithm.divisible_power?(b2, prime, 1)
        r = EllipticTateAlgorithm.nth_root_mod(
          model.a4, 2, prime, search_limit)
        cubic = ((r + model.a2)*r + model.a4)*r + model.a6
        t = EllipticTateAlgorithm.nth_root_mod(
          cubic, 2, prime, search_limit)
      else
        inverse = EllipticTateAlgorithm.inverse_mod(model.a1, prime)
        r = inverse * model.a3
        t = inverse * (model.a4 + r**2)
    elsif prime == 3
      if EllipticTateAlgorithm.divisible_power?(b2, prime, 1)
        r = EllipticTateAlgorithm.nth_root_mod(
          0 - b6, 3, prime, search_limit)
      else
        r = (0 - EllipticTateAlgorithm.inverse_mod(b2, prime))*b4
      t = model.a1*r + model.a3
    else
      if EllipticTateAlgorithm.divisible_power?(c4, prime, 1)
        r = (0 - b2) * EllipticTateAlgorithm.inverse_mod(12, prime)
      else
        denominator = 12*c4
        r = ((0 - (c6 + b2*c4)) *
          EllipticTateAlgorithm.inverse_mod(denominator, prime))
      t = ((0 - (model.a1*r + model.a3)) *
        EllipticTateAlgorithm.inverse_mod(2, prime))
    [
      EllipticTateAlgorithm.mod(r, prime),
      0,
      EllipticTateAlgorithm.mod(t, prime)
    ]

  -> .second_translation(model, prime, search_limit)
    s = 0
    t = 0
    if prime == 2
      s = EllipticTateAlgorithm.nth_root_mod(
        model.a2, 2, prime, search_limit)
      a6_over_square = EllipticTateAlgorithm.exact_quotient(
        model.a6, prime**2)
      t = prime * EllipticTateAlgorithm.nth_root_mod(
        a6_over_square, 2, prime, search_limit)
    elsif prime == 3
      s = model.a1
      t = model.a3
    else
      s = ((0 - model.a1) *
        EllipticTateAlgorithm.inverse_mod(2, prime))
      t = ((0 - model.a3) *
        EllipticTateAlgorithm.inverse_mod(2, prime))
    [0, s, t]

  # Return:
  # [kind, conductor exponent, Kodaira symbol, Tamagawa number, split?,
  #  transformations, final translated model].
  -> .classify(model, prime, search_limit = 250_000)
    if model.class_name != "IntegralWeierstrassModel"
      raise "Tate algorithm needs an integral Weierstrass model"
    if prime < 2 || !prime.prime?
      raise "Tate algorithm needs a prime"
    if !model.nonsingular?
      raise "Tate algorithm needs a nonsingular model"

    val_disc = IntegralWeierstrassModel.valuation(
      model.discriminant, prime)
    transformations = []
    if val_disc == 0
      return [:good, 0, "I0", 1, nil, transformations, model]

    first = EllipticTateAlgorithm.initial_translation(
      model, prime, search_limit)
    current = EllipticTateAlgorithm.translated(
      model, first[0], first[1], first[2], transformations)
    if !EllipticTateAlgorithm.divisible_power?(current.a3, prime, 1)
      raise "Tate normalization failed to make p divide a3"
    if !EllipticTateAlgorithm.divisible_power?(current.a4, prime, 1)
      raise "Tate normalization failed to make p divide a4"
    if !EllipticTateAlgorithm.divisible_power?(current.a6, prime, 1)
      raise "Tate normalization failed to make p divide a6"

    if !EllipticTateAlgorithm.divisible_power?(current.c4, prime, 1)
      split = EllipticTateAlgorithm.quadratic_has_root?(
        1, current.a1, 0 - current.a2, prime, search_limit)
      tamagawa = 1
      tamagawa = val_disc if split
      if !split && val_disc.even?
        tamagawa = 2
      return [
        :multiplicative, 1, "I" + val_disc.to_s,
        tamagawa, split, transformations, current
      ]

    # Additive types II, III, and IV.
    if !EllipticTateAlgorithm.divisible_power?(
         current.a6, prime, 2)
      return [:additive, val_disc, "II", 1, nil, transformations, current]
    if !EllipticTateAlgorithm.divisible_power?(
         current.b8, prime, 3)
      return [
        :additive, val_disc - 1, "III", 2,
        nil, transformations, current
      ]
    if !EllipticTateAlgorithm.divisible_power?(
         current.b6, prime, 3)
      a3t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a3, prime), prime)
      a6t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a6, prime**2), prime)
      split_quadratic = EllipticTateAlgorithm.quadratic_has_root?(
        1, a3t, 0 - a6t, prime, search_limit)
      tamagawa = split_quadratic ? 3 : 1
      return [
        :additive, val_disc - 2, "IV", tamagawa,
        nil, transformations, current
      ]

    second = EllipticTateAlgorithm.second_translation(
      current, prime, search_limit)
    current = EllipticTateAlgorithm.translated(
      current, second[0], second[1], second[2], transformations)
    valid_second = EllipticTateAlgorithm.divisible_power?(
      current.a1, prime, 1)
    valid_second = false if !EllipticTateAlgorithm.divisible_power?(
      current.a2, prime, 1)
    valid_second = false if !EllipticTateAlgorithm.divisible_power?(
      current.a3, prime, 2)
    valid_second = false if !EllipticTateAlgorithm.divisible_power?(
      current.a4, prime, 2)
    valid_second = false if !EllipticTateAlgorithm.divisible_power?(
      current.a6, prime, 3)
    raise "Tate second normalization failed" if !valid_second

    b = EllipticTateAlgorithm.mod(
      EllipticTateAlgorithm.exact_quotient(current.a2, prime), prime)
    c = EllipticTateAlgorithm.mod(
      EllipticTateAlgorithm.exact_quotient(current.a4, prime**2), prime)
    d = EllipticTateAlgorithm.mod(
      EllipticTateAlgorithm.exact_quotient(current.a6, prime**3), prime)
    w = 27*d**2 - b**2*c**2 + 4*b**3*d - 18*b*c*d + 4*c**3
    x = 3*c - b**2
    w_divisible = EllipticTateAlgorithm.mod(w, prime) == 0
    x_divisible = EllipticTateAlgorithm.mod(x, prime) == 0

    if !w_divisible
      roots = EllipticTateAlgorithm.cubic_root_count(
        b, c, d, prime, search_limit)
      return [
        :additive, val_disc - 4, "I0*", 1 + roots,
        nil, transformations, current
      ]

    if !x_divisible
      return EllipticTateAlgorithm.classify_double_root(
        current, prime, val_disc, b, c, d,
        transformations, search_limit)

    EllipticTateAlgorithm.classify_triple_root(
      current, prime, val_disc, b, d,
      transformations, search_limit)

  -> .classify_double_root(
       model, prime, val_disc, b, c, d,
       transformations, search_limit)
    r = 0
    if prime == 2
      r = EllipticTateAlgorithm.nth_root_mod(
        c, 2, prime, search_limit)
    elsif prime == 3
      r = c * EllipticTateAlgorithm.inverse_mod(b, prime)
    else
      x = 3*c - b**2
      numerator = b*c - 9*d
      r = numerator * EllipticTateAlgorithm.inverse_mod(2*x, prime)
    r = prime * EllipticTateAlgorithm.mod(r, prime)
    current = EllipticTateAlgorithm.translated(
      model, r, 0, 0, transformations)

    ix = 3
    iy = 3
    mx = prime**2
    my = prime**2
    iterations = 0
    maximum_iterations = val_disc + 12
    tamagawa = nil
    while tamagawa == nil
      iterations += 1
      if iterations > maximum_iterations
        raise "Tate I_n* loop exceeded discriminant bound"
      a2t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a2, prime), prime)
      a3t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a3, my), prime)
      a4t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a4, prime*mx), prime)
      a6t = EllipticTateAlgorithm.mod(
        EllipticTateAlgorithm.exact_quotient(current.a6, mx*my), prime)

      if EllipticTateAlgorithm.mod(a3t**2 + 4*a6t, prime) == 0
        t = 0
        if prime == 2
          root = EllipticTateAlgorithm.nth_root_mod(
            a6t, 2, prime, search_limit)
          t = my*root
        else
          inverse_two = EllipticTateAlgorithm.inverse_mod(2, prime)
          t = my*EllipticTateAlgorithm.mod(
            (0 - a3t)*inverse_two, prime)
        current = EllipticTateAlgorithm.translated(
          current, 0, 0, t, transformations)
        my *= prime
        iy += 1

        a2t = EllipticTateAlgorithm.mod(
          EllipticTateAlgorithm.exact_quotient(current.a2, prime), prime)
        a3t = EllipticTateAlgorithm.mod(
          EllipticTateAlgorithm.exact_quotient(current.a3, my), prime)
        a4t = EllipticTateAlgorithm.mod(
          EllipticTateAlgorithm.exact_quotient(
            current.a4, prime*mx), prime)
        a6t = EllipticTateAlgorithm.mod(
          EllipticTateAlgorithm.exact_quotient(current.a6, mx*my), prime)
        if EllipticTateAlgorithm.mod(
             a4t**2 - 4*a6t*a2t, prime) == 0
          r = 0
          if prime == 2
            quotient = a6t * EllipticTateAlgorithm.inverse_mod(
              a2t, prime)
            root = EllipticTateAlgorithm.nth_root_mod(
              quotient, 2, prime, search_limit)
            r = mx*root
          else
            denominator = 2*a2t
            r = mx*EllipticTateAlgorithm.mod(
              ((0 - a4t) *
                EllipticTateAlgorithm.inverse_mod(denominator, prime)),
              prime)
          current = EllipticTateAlgorithm.translated(
            current, r, 0, 0, transformations)
          mx *= prime
          ix += 1
        else
          has_roots = EllipticTateAlgorithm.quadratic_has_root?(
            a2t, a4t, a6t, prime, search_limit)
          tamagawa = has_roots ? 4 : 2
      else
        has_roots = EllipticTateAlgorithm.quadratic_has_root?(
          1, a3t, 0 - a6t, prime, search_limit)
        tamagawa = has_roots ? 4 : 2

    index = ix + iy - 5
    conductor_exponent = val_disc - ix - iy + 1
    [
      :additive, conductor_exponent, "I" + index.to_s + "*",
      tamagawa, nil, transformations, current
    ]

  -> .classify_triple_root(
       model, prime, val_disc, b, d,
       transformations, search_limit)
    r = 0
    if prime == 2
      r = b
    elsif prime == 3
      r = EllipticTateAlgorithm.nth_root_mod(
        0 - d, 3, prime, search_limit)
    else
      r = (0 - b) * EllipticTateAlgorithm.inverse_mod(3, prime)
    r = prime * EllipticTateAlgorithm.mod(r, prime)
    current = EllipticTateAlgorithm.translated(
      model, r, 0, 0, transformations)

    valid = EllipticTateAlgorithm.divisible_power?(
      current.a2, prime, 2)
    valid = false if !EllipticTateAlgorithm.divisible_power?(
      current.a4, prime, 3)
    valid = false if !EllipticTateAlgorithm.divisible_power?(
      current.a6, prime, 4)
    raise "Tate triple-root normalization failed" if !valid

    a3t = EllipticTateAlgorithm.mod(
      EllipticTateAlgorithm.exact_quotient(current.a3, prime**2), prime)
    a6t = EllipticTateAlgorithm.mod(
      EllipticTateAlgorithm.exact_quotient(current.a6, prime**4), prime)
    if EllipticTateAlgorithm.mod(a3t**2 + 4*a6t, prime) != 0
      roots = EllipticTateAlgorithm.quadratic_has_root?(
        1, a3t, 0 - a6t, prime, search_limit)
      tamagawa = roots ? 3 : 1
      return [
        :additive, val_disc - 6, "IV*", tamagawa,
        nil, transformations, current
      ]

    t = 0
    if prime == 2
      root = EllipticTateAlgorithm.nth_root_mod(
        a6t, 2, prime, search_limit)
      t = (0 - prime**2)*root
    else
      inverse_two = EllipticTateAlgorithm.inverse_mod(2, prime)
      t = prime**2 * EllipticTateAlgorithm.mod(
        (0 - a3t)*inverse_two, prime)
    current = EllipticTateAlgorithm.translated(
      current, 0, 0, t, transformations)

    if !EllipticTateAlgorithm.divisible_power?(
         current.a4, prime, 4)
      return [
        :additive, val_disc - 7, "III*", 2,
        nil, transformations, current
      ]
    if !EllipticTateAlgorithm.divisible_power?(
         current.a6, prime, 6)
      return [
        :additive, val_disc - 8, "II*", 1,
        nil, transformations, current
      ]
    raise "Tate algorithm found a p-scaling on a certified minimal model"


+ EllipticTateLocalDataCertificate
  -> new(@source, @prime, @minimality_certificate,
         @kind, @conductor_exponent, @kodaira_symbol,
         @tamagawa_number, @split, @transformations,
         @final_model, @search_limit)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @source.class_name != "IntegralWeierstrassModel"
    valid_minimality = (@minimality_certificate.class_name ==
      "EllipticLocalMinimalModelCertificate")
    return false if !valid_minimality
    return false if @minimality_certificate.prime != @prime
    return false if !@minimality_certificate.model.same_model?(@source)
    return false if !@minimality_certificate.verified?
    replay = EllipticTateAlgorithm.classify(
      @source, @prime, @search_limit)
    return false if replay[0] != @kind
    return false if replay[1] != @conductor_exponent
    return false if replay[2] != @kodaira_symbol
    return false if replay[3] != @tamagawa_number
    return false if replay[4] != @split
    return false if replay[5].size != @transformations.size
    i = 0
    while i < @transformations.size
      expected = replay[5][i]
      supplied = @transformations[i]
      return false if supplied.class_name != "IntegralWeierstrassTransformation"
      return false if !supplied.certificate.verified?
      return false if supplied.u != expected.u
      return false if supplied.r != expected.r
      return false if supplied.s != expected.s
      return false if supplied.t != expected.t
      return false if !supplied.source.same_model?(expected.source)
      return false if !supplied.target.same_model?(expected.target)
      i += 1
    return false if !replay[6].same_model?(@final_model)
    true

  -> certified?
    verified?

  -> source
    @source

  -> prime
    @prime

  -> minimality_certificate
    @minimality_certificate

  -> kind
    @kind

  -> conductor_exponent
    @conductor_exponent

  -> kodaira_symbol
    @kodaira_symbol

  -> tamagawa_number
    @tamagawa_number

  -> split?
    @split

  -> transformations
    @transformations

  -> final_model
    @final_model

  -> search_limit
    @search_limit

  -> to_s
    ("EllipticTateLocalDataCertificate(p=" + @prime.to_s +
      ", " + @kodaira_symbol + ")")

  -> inspect
    to_s


+ EllipticTateLocalData
  -> new(@source, @prime, @minimality_certificate,
         @search_limit = 250_000)
    replay = EllipticTateAlgorithm.classify(
      @source, @prime, @search_limit)
    @kind = replay[0]
    @conductor_exponent = replay[1]
    @kodaira_symbol = replay[2]
    @tamagawa_number = replay[3]
    @split = replay[4]
    @transformations = replay[5]
    @final_model = replay[6]
    @certificate = EllipticTateLocalDataCertificate.new(
      @source, @prime, @minimality_certificate,
      @kind, @conductor_exponent, @kodaira_symbol,
      @tamagawa_number, @split, @transformations,
      @final_model, @search_limit)
    raise "Tate local-data certificate failed" if !@certificate.verified?

  -> source
    @source

  -> prime
    @prime

  -> kind
    @kind

  -> conductor_exponent
    @conductor_exponent

  -> kodaira_symbol
    @kodaira_symbol

  -> tamagawa_number
    @tamagawa_number

  -> split?
    @split

  -> transformations
    @transformations

  -> final_model
    @final_model

  -> certificate
    @certificate

  -> minimality_certificate
    @minimality_certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("EllipticTateLocalData(p=" + @prime.to_s +
      ", " + @kodaira_symbol + ", f=" +
      @conductor_exponent.to_s + ")")

  -> inspect
    to_s
