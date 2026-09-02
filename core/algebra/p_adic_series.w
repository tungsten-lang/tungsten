# Truncated p-adic power series over Z/p^K with explicit digit accounting.
#
# Elements are Integer residues in [0, p^K).  A series knows how many p-adic
# digits of every coefficient are trustworthy (`known_digits`, at most K):
# sums and products take the minimum, exact division by p^e lowers it by e,
# and the linear-algebra layer reports the digits lost to non-unit pivots
# instead of comparing against a hand-set slack.  Zero counts inside a disk
# come from the lower convex hull of the p-adic Newton polygon, Weierstrass
# factors from digitwise Hensel lifting against the mod-p unit cofactor, and
# power sums from Newton's identities.  Nothing here is a theorem about
# curves; `core/algebra/coleman` layers the geometry on top.

use core/algebra/p_adic

+ PadicSeriesRing
  -> new(@prime, @precision, @length)
    raise "p-adic series ring needs a prime >= 2" if @prime < 2
    raise "p-adic series ring needs positive precision" if @precision < 1
    raise "p-adic series ring needs positive length" if @length < 1
    @modulus = @prime**@precision

  -> prime
    @prime

  -> precision
    @precision

  -> length
    @length

  -> modulus
    @modulus

  -> normalize(value)
    out = value % @modulus
    out += @modulus if out < 0
    out

  -> valuation(value)
    normalized = normalize(value)
    return @precision if normalized == 0
    PadicArithmetic.integer_valuation(normalized, @prime)

  -> unit_inverse(value)
    PadicArithmetic.inverse_mod(normalize(value), @modulus)

  # Exact division of a residue by p^exponent.  The quotient is only known to
  # precision - exponent digits; callers propagate that through known_digits.
  -> divide_power(value, exponent)
    normalized = normalize(value)
    divisor = @prime**exponent
    raise "p-adic residue is not divisible by the requested power" if normalized % divisor != 0
    normalized / divisor

  -> series(coefficients, known_digits = nil)
    PadicSeries.new(self, coefficients, known_digits)

  -> constant(value)
    series([value])

  -> parameter
    series([0, 1])

  -> zero
    series([])

  -> one
    series([1])

  -> to_s
    "Z/" + @prime.to_s + "^" + @precision.to_s + " series mod t^" + @length.to_s

  -> inspect
    to_s


+ PadicSeries
  -> new(@ring, coefficients, known_digits = nil)
    if @ring.class_name != "PadicSeriesRing"
      raise "p-adic series needs a PadicSeriesRing"
    if coefficients.class_name != "Array"
      raise "p-adic series needs an Array of coefficients"
    @coefficients = []
    index = 0
    while index < coefficients.size && index < @ring.length
      @coefficients.push(@ring.normalize(coefficients[index]))
      index += 1
    while @coefficients.size < @ring.length
      @coefficients.push(0)
    @known_digits = known_digits
    @known_digits = @ring.precision if @known_digits == nil
    @known_digits = @ring.precision if @known_digits > @ring.precision
    raise "p-adic series has no trustworthy digits left" if @known_digits < 1

  -> ring
    @ring

  -> known_digits
    @known_digits

  -> length
    @ring.length

  -> coefficient(index)
    return 0 if index < 0 || index >= @coefficients.size
    @coefficients[index]

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  # First index whose coefficient is nonzero mod p^K, or the length.
  -> order
    index = 0
    while index < @coefficients.size
      return index if @coefficients[index] != 0
      index += 1
    @coefficients.size

  -> zero?
    order >= @coefficients.size

  -> constant_term
    coefficient(0)

  -> unit?
    @ring.valuation(coefficient(0)) == 0

  # Copy into another ring of the same prime and precision (typically a
  # different truncation length); coefficients beyond the source are unknown
  # and left as zero, so only shortening is exact.
  -> resize(target_ring)
    if target_ring.prime != @ring.prime || target_ring.precision != @ring.precision
      raise "p-adic series resize needs the same prime and precision"
    PadicSeries.new(target_ring, @coefficients, @known_digits)

  # Reduce every coefficient modulo p^known_digits so that a coefficient which
  # vanishes to the trustworthy precision is stored as an exact zero.
  -> reduce_to_known
    modulus = @ring.prime**@known_digits
    out = []
    @coefficients.each -> out.push(item % modulus)
    PadicSeries.new(@ring, out, @known_digits)

  -> with_known_digits(digits)
    PadicSeries.new(@ring, @coefficients, digits)

  -> shared_digits(other)
    digits = @known_digits
    digits = other.known_digits if other.known_digits < digits
    digits

  -> +(value)
    if value.class_name == "PadicSeries"
      out = []
      index = 0
      while index < @coefficients.size
        out.push(@coefficients[index] + value.coefficient(index))
        index += 1
      return PadicSeries.new(@ring, out, shared_digits(value))
    out = coefficients
    out[0] = out[0] + value
    PadicSeries.new(@ring, out, @known_digits)

  -> -(value)
    if value.class_name == "PadicSeries"
      return self + value.negate
    self + (0 - value)

  -> negate
    out = []
    @coefficients.each -> out.push(0 - item)
    PadicSeries.new(@ring, out, @known_digits)

  -> -@
    negate

  -> scale(factor)
    out = []
    @coefficients.each -> out.push(item * factor)
    PadicSeries.new(@ring, out, @known_digits)

  -> *(value)
    return scale(value) if value.class_name != "PadicSeries"
    length = @coefficients.size
    out = []
    index = 0
    while index < length
      out.push(0)
      index += 1
    modulus = @ring.modulus
    i = order
    top = value.order
    while i < length
      a = @coefficients[i]
      if a != 0
        j = top
        while i + j < length
          b = value.coefficient(j)
          out[i + j] = (out[i + j] + a * b) % modulus if b != 0
          j += 1
      i += 1
    PadicSeries.new(@ring, out, shared_digits(value))

  # Multiply by t^count, dropping what falls off the truncation.
  -> shift(count)
    raise "p-adic series shift needs a nonnegative count" if count < 0
    out = []
    index = 0
    while index < count && index < @coefficients.size
      out.push(0)
      index += 1
    index = 0
    while out.size < @coefficients.size
      out.push(@coefficients[index])
      index += 1
    PadicSeries.new(@ring, out, @known_digits)

  # Divide by t^count; the dropped leading coefficients must vanish mod p^K.
  # The tail gains `count` unknown coefficients, so callers that need full
  # length must have started with a longer ring.
  -> unshift(count)
    raise "p-adic series unshift needs a nonnegative count" if count < 0
    index = 0
    while index < count
      if coefficient(index) != 0
        raise "p-adic series is not divisible by the requested parameter power"
      index += 1
    out = []
    index = count
    while index < @coefficients.size
      out.push(@coefficients[index])
      index += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> divide_power(exponent)
    out = []
    @coefficients.each -> out.push(@ring.divide_power(item, exponent))
    PadicSeries.new(@ring, out, @known_digits - exponent)

  -> derivative
    out = []
    index = 1
    while index < @coefficients.size
      out.push(@coefficients[index] * index)
      index += 1
    PadicSeries.new(@ring, out, @known_digits)

  # p^scale_exponent * integral_0^t of the series, through the coefficient of
  # t^order.  Each term a_m t^(m+1)/(m+1) is made integral by the uniform
  # p-power, so the result keeps every known digit; the scale must cover
  # v_p(m+1) for every retained m, which is checked.
  -> scaled_antiderivative(order, scale_exponent)
    raise "antiderivative order exceeds the ring length" if order > @coefficients.size
    prime = @ring.prime
    modulus = @ring.modulus
    scale = prime**scale_exponent
    out = [0]
    m = 0
    while m + 1 < order
      denominator = m + 1
      power = 0
      unit = denominator
      while unit % prime == 0
        unit = unit / prime
        power += 1
      if power > scale_exponent
        raise "antiderivative scale does not clear the denominator " + denominator.to_s
      numerator = (@coefficients[m] * scale) / (prime**power)
      out.push((numerator % modulus) * @ring.unit_inverse(unit))
      m += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> evaluate(value)
    modulus = @ring.modulus
    accumulator = 0
    index = @coefficients.size - 1
    while index >= 0
      accumulator = (accumulator * value + @coefficients[index]) % modulus
      index -= 1
    accumulator += modulus if accumulator < 0
    accumulator

  # Series inverse of a unit; a_0 must be a p-adic unit.
  -> inverse
    raise "p-adic series inverse needs a unit constant term" if !unit?
    length = @coefficients.size
    modulus = @ring.modulus
    lead = @ring.unit_inverse(@coefficients[0])
    out = [lead]
    n = 1
    while n < length
      acc = 0
      k = 1
      while k <= n
        a = @coefficients[k]
        acc = (acc + a * out[n - k]) % modulus if a != 0
        k += 1
      value = (0 - acc * lead) % modulus
      value += modulus if value < 0
      out.push(value)
      n += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> newton_polygon_points
    out = []
    index = 0
    while index < @coefficients.size
      if @coefficients[index] != 0
        out.push([index, @ring.valuation(@coefficients[index])])
      index += 1
    out

  # Weierstrass degree: the first index carrying a unit coefficient.  Equal to
  # the number of zeros with positive valuation (open unit disk) counted with
  # multiplicity, by the p-adic Weierstrass preparation theorem.
  -> weierstrass_degree
    index = 0
    while index < @coefficients.size
      return index if @ring.valuation(@coefficients[index]) == 0
      index += 1
    raise "no unit coefficient within the truncation; Weierstrass degree is undetermined"

  # Zeros with v_p(t) >= radius, counted with multiplicity, by Strassmann's
  # theorem on the rescaled series a_j p^(radius j).  Result is
  # [count, best_valuation, runner_up_valuation].  The count is certified only
  # when best_valuation < known_digits and below the caller's tail floor (a
  # lower bound for v(a_j) + radius j over every omitted j >= length); the
  # runner-up gap tells how far the decision sits above the noise.
  -> disk_zero_count(radius, tail_floor)
    best = nil
    best_index = 0
    second = nil
    index = 0
    while index < @coefficients.size
      if @coefficients[index] != 0
        weight = @ring.valuation(@coefficients[index]) + radius * index
        if best == nil || weight < best || (weight == best && index > best_index)
          if best != nil && weight != best
            second = best
          best = weight
          best_index = index
        elsif second == nil || weight < second
          second = weight
      index += 1
    raise "series vanishes to working precision; zero count is undetermined" if best == nil
    if best >= @known_digits
      raise "Strassmann minimum " + best.to_s + " is not below the known digits " + @known_digits.to_s
    if best >= tail_floor
      raise "Strassmann minimum " + best.to_s + " is not below the tail floor " + tail_floor.to_s
    second = @known_digits if second == nil || second > @known_digits
    [best_index, best, second]

  # Monic Weierstrass polynomial g of the given degree with phi = g * h, h a
  # unit series, obtained by digitwise Hensel lifting from g = t^degree mod p.
  # Returns the coefficient Array [c_0, ..., c_(degree-1), 1] and verifies
  # the product mod (p^K, t^length); all non-leading coefficients must lie in
  # pZ_p, as the roots have positive valuation.
  -> weierstrass_factor(degree)
    prime = @ring.prime
    precision = @known_digits
    length = @coefficients.size
    if degree < 0 || degree >= length
      raise "Weierstrass degree is outside the truncation"
    index = 0
    while index < degree
      if @ring.valuation(@coefficients[index]) == 0
        raise "Weierstrass factor degree contradicts a unit coefficient"
      index += 1
    if @ring.valuation(@coefficients[degree]) != 0
      raise "Weierstrass factor needs a unit coefficient at its degree"
    # mod-p unit cofactor and its inverse
    hbar = []
    index = degree
    while index < length
      hbar.push(@coefficients[index] % prime)
      index += 1
    while hbar.size < length
      hbar.push(0)
    hinv = PadicSeries.mod_p_inverse(hbar, prime, length)
    modulus = @ring.modulus
    g = []
    index = 0
    while index < degree
      g.push(0)
      index += 1
    g.push(1)
    h = []
    index = 0
    while index < length
      h.push(hbar[index])
      index += 1
    step = 1
    power = prime
    while step < precision
      product = PadicSeries.integer_product(g, h, length, modulus)
      e = []
      index = 0
      while index < length
        residual = (@coefficients[index] - product[index]) % modulus
        residual += modulus if residual < 0
        if residual % power != 0
          raise "Hensel lifting lost agreement at digit " + step.to_s
        e.push((residual / power) % prime)
        index += 1
      q = PadicSeries.integer_product(e, hinv, length, prime)
      delta_g = []
      index = 0
      while index < degree
        delta_g.push(q[index])
        index += 1
      # e - hbar*delta_g is divisible by t^degree; its quotient is delta_h.
      correction = PadicSeries.integer_product(delta_g, hbar, length, prime)
      delta_h = []
      index = 0
      while index < length
        value = (e[index] - correction[index]) % prime
        value += prime if value < 0
        if index < degree
          raise "Hensel cofactor correction is not divisible by the pivot power" if value != 0
        else
          delta_h.push(value)
        index += 1
      while delta_h.size < length
        delta_h.push(0)
      index = 0
      while index < degree
        g[index] = (g[index] + delta_g[index] * power) % modulus
        index += 1
      index = 0
      while index < length
        h[index] = (h[index] + delta_h[index] * power) % modulus
        index += 1
      step += 1
      power = power * prime
    product = PadicSeries.integer_product(g, h, length, modulus)
    check_modulus = prime**precision
    index = 0
    while index < length
      difference = (@coefficients[index] - product[index]) % check_modulus
      difference += check_modulus if difference < 0
      raise "Weierstrass factorization failed verification" if difference != 0
      index += 1
    index = 0
    while index < degree
      if g[index] % prime != 0
        raise "Weierstrass factor has a unit non-leading coefficient"
      index += 1
    g

  # sum_k coefficients[k] * series_list[k], accumulated in one coefficient
  # Array so that long linear combinations allocate nothing per term.
  -> .combination(series_list, coefficients, ring, digits)
    length = ring.length
    modulus = ring.modulus
    out = []
    index = 0
    while index < length
      out.push(0)
      index += 1
    k = 0
    while k < series_list.size
      c = coefficients[k]
      if c != 0
        source = series_list[k]
        i = source.order
        while i < length
          a = source.coefficient(i)
          out[i] = (out[i] + c * a) % modulus if a != 0
          i += 1
      k += 1
    PadicSeries.new(ring, out, digits)

  # Series product of two coefficient Arrays truncated to `length`, mod m.
  -> .integer_product(left, right, length, modulus)
    out = []
    index = 0
    while index < length
      out.push(0)
      index += 1
    i = 0
    while i < left.size && i < length
      a = left[i]
      if a != 0
        j = 0
        while j < right.size && i + j < length
          b = right[j]
          out[i + j] = (out[i + j] + a * b) % modulus if b != 0
          j += 1
      i += 1
    out

  -> .mod_p_inverse(series, prime, length)
    lead = PadicArithmetic.inverse_mod(series[0] % prime, prime)
    out = [lead]
    n = 1
    while n < length
      acc = 0
      k = 1
      while k <= n
        a = 0
        a = series[k] if k < series.size
        acc = (acc + a * out[n - k]) % prime if a != 0
        k += 1
      value = (0 - acc * lead) % prime
      value += prime if value < 0
      out.push(value)
      n += 1
    out

  # Power sums p_1..p_count of the roots of a monic polynomial given as
  # [c_0, ..., c_(d-1), 1], by Newton's identities, mod p^K.
  -> .power_sums(monic, count, modulus)
    degree = monic.size - 1
    # elementary symmetric functions e_i = (-1)^i c_(d-i), e_0 = 1
    e = [1]
    i = 1
    while i <= degree
      value = monic[degree - i]
      value = 0 - value if i % 2 == 1
      value = value % modulus
      value += modulus if value < 0
      e.push(value)
      i += 1
    # Newton: p_k = sum_(i=1)^(k-1) (-1)^(i-1) e_i p_(k-i) + (-1)^(k-1) k e_k
    sums = [degree % modulus]
    k = 1
    while k <= count
      acc = 0
      i = 1
      while i < k && i <= degree
        term = e[i] * sums[k - i]
        if i % 2 == 1
          acc = acc + term
        else
          acc = acc - term
        i += 1
      if k <= degree
        term = e[k] * k
        if k % 2 == 1
          acc = acc + term
        else
          acc = acc - term
      acc = acc % modulus
      acc += modulus if acc < 0
      sums.push(acc)
      k += 1
    sums

  -> to_s
    text = ""
    shown = 0
    index = 0
    while index < @coefficients.size && shown < 8
      if @coefficients[index] != 0
        text = text + " + " if text != ""
        text = text + @coefficients[index].to_s + "*t^" + index.to_s
        shown += 1
      index += 1
    text = "0" if text == ""
    text + " (known to " + @known_digits.to_s + " digits)"

  -> inspect
    to_s


# Kernel of an integer matrix over Z/p^K by valuation-pivoted elimination.
# Unlike a field elimination, a pivot of valuation v divides by p^v during
# back substitution and costs v digits; the result records the digits that
# survive and the corank actually found, so a caller that expects a
# one-dimensional kernel can assert it rather than assume it.
+ PadicKernel
  -> new(rows, width, @ring)
    if rows.class_name != "Array"
      raise "p-adic kernel needs an Array of rows"
    @width = width
    @row_count = rows.size
    matrix = []
    rows.each -> (row)
      raise "p-adic kernel row has the wrong width" if row.size != width
      copy = []
      row.each -> copy.push(@ring.normalize(item))
      matrix.push(copy)
    @original = []
    matrix.each -> (row)
      copy = []
      row.each -> copy.push(item)
      @original.push(copy)
    eliminate(matrix)

  -> ring
    @ring

  -> width
    @width

  -> rank
    @pivot_columns.size

  -> dimension
    @width - @pivot_columns.size

  -> pivot_valuations
    out = []
    @pivot_valuations.each -> out.push(item)
    out

  -> lost_digits
    @lost_digits

  -> known_digits
    @ring.precision - @lost_digits

  -> vectors
    out = []
    @vectors.each -> (vector)
      copy = []
      vector.each -> copy.push(item)
      out.push(copy)
    out

  -> eliminate(matrix)
    modulus = @ring.modulus
    precision = @ring.precision
    prime = @ring.prime
    @pivot_columns = []
    @pivot_rows = []
    @pivot_valuations = []
    used = []
    r = 0
    while r < @row_count
      used.push(false)
      r += 1
    free_columns = []
    column = 0
    while column < @width
      # choose the unused row with the smallest valuation in this column
      best_row = nil
      best_valuation = precision
      r = 0
      while r < @row_count
        if !used[r] && matrix[r][column] != 0
          v = @ring.valuation(matrix[r][column])
          if best_row == nil || v < best_valuation
            best_row = r
            best_valuation = v
        r += 1
      if best_row == nil || best_valuation >= precision
        free_columns.push(column)
      else
        used[best_row] = true
        @pivot_columns.push(column)
        @pivot_rows.push(best_row)
        @pivot_valuations.push(best_valuation)
        pivot = matrix[best_row][column]
        pivot_power = prime**best_valuation
        pivot_unit_inverse = @ring.unit_inverse(pivot / pivot_power)
        r = 0
        while r < @row_count
          if !used[r] && matrix[r][column] != 0
            entry = matrix[r][column]
            if entry % pivot_power != 0
              raise "p-adic kernel pivot selection failed the divisibility invariant"
            factor = ((entry / pivot_power) * pivot_unit_inverse) % modulus
            k = column
            while k < @width
              if matrix[best_row][k] != 0
                value = (matrix[r][k] - factor * matrix[best_row][k]) % modulus
                value += modulus if value < 0
                matrix[r][k] = value
              k += 1
          r += 1
      column += 1
    total_loss = 0
    @pivot_valuations.each -> total_loss += item
    @lost_digits = total_loss
    # Back substitution in scaled form: entries represent p^total_loss times
    # the true coordinate, so every division by a pivot power is exact.
    scale = prime**total_loss
    @vectors = []
    free_columns.each -> (free)
      vector = []
      c = 0
      while c < @width
        vector.push(0)
        c += 1
      vector[free] = scale % modulus
      index = @pivot_columns.size - 1
      while index >= 0
        column = @pivot_columns[index]
        row = @pivot_rows[index]
        valuation = @pivot_valuations[index]
        acc = 0
        k = column + 1
        while k < @width
          entry = matrix[row][k]
          acc = (acc + entry * vector[k]) % modulus if entry != 0 && vector[k] != 0
          k += 1
        pivot = matrix[row][column]
        pivot_power = prime**valuation
        unit_inverse = @ring.unit_inverse(pivot / pivot_power)
        numerator = (0 - acc) % modulus
        numerator += modulus if numerator < 0
        if numerator % pivot_power != 0
          raise "p-adic kernel back substitution lost exactness"
        vector[column] = ((numerator / pivot_power) * unit_inverse) % modulus
        index -= 1
      @vectors.push(vector)
    # Entries are trustworthy only modulo p^(precision - total_loss); reduce
    # them to canonical representatives of that quotient before use.
    check_modulus = prime**(precision - total_loss)
    reduced = []
    @vectors.each -> (vector)
      copy = []
      vector.each -> copy.push(item % check_modulus)
      reduced.push(copy)
    @vectors = reduced
    # Verify each vector against the original rows to the surviving digits.
    @vectors.each -> (vector)
      @original.each -> (row)
        acc = 0
        c = 0
        while c < @width
          acc = (acc + row[c] * vector[c]) % modulus if row[c] != 0 && vector[c] != 0
          c += 1
        if acc % check_modulus != 0
          raise "p-adic kernel vector failed replay against the original rows"
    nil

  # Primitive rescaling of a kernel vector: divide out the common p-power and
  # report the digits that remain trustworthy.
  -> primitive_vector(index)
    vector = @vectors[index]
    minimum = @ring.precision
    vector.each -> (entry)
      if entry != 0
        v = @ring.valuation(entry)
        minimum = v if v < minimum
    raise "p-adic kernel vector vanishes to working precision" if minimum >= known_digits
    reduced_modulus = @ring.prime**(known_digits - minimum)
    out = []
    vector.each -> out.push(@ring.divide_power(item, minimum) % reduced_modulus)
    [out, known_digits - minimum]
