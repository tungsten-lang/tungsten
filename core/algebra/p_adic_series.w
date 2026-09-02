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

# ----------------------------------------------------------------------------
# Machine lane.  When p^K < 2^62 every residue fits a signed 64-bit word and
# the coefficient buffers are i64 arrays holding MONTGOMERY forms a R mod N
# with R = 2^64.  Products are reduced with `mulhi` and wrapping 64-bit
# arithmetic only (REDC), so these top-level typed functions run as raw
# machine loops with no boxing and no BigInt temporaries.  Two toolchain
# facts shaped this (2026-09-02): a u128 intermediate or a u64-typed helper
# return is boxed to a BigInt on every use, and in boxed code the difference
# of two u64[] element reads wraps as unsigned -- hence i64 buffers, i64
# signatures, and `(a + n - b) % n` for every modular subtraction.

-> padic_mont_mul(a, b, n, ninv) (i64 i64 i64 i64) i64
  ua = a ## u64
  ub = b ## u64
  hi = mulhi(ua, ub) ## i64
  lo = ua * ub
  m = lo * (ninv ## u64)
  mn_hi = mulhi(m, n ## u64) ## i64
  t = hi + mn_hi
  t = t + 1 if lo != 0
  t = t - n if t >= n
  t

-> padic_lane_product(left, right, out, length, n, ninv, left_order, right_order) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  i = left_order ## i64
  while i < length
    a = left[i] ## i64
    if a != 0
      ua = a ## u64
      j = right_order ## i64
      while i + j < length
        b = right[j] ## i64
        if b != 0
          ub = b ## u64
          hi = mulhi(ua, ub) ## i64
          lo = ua * ub
          m = lo * uninv
          mn_hi = mulhi(m, un) ## i64
          t = hi + mn_hi
          t = t + 1 if lo != 0
          t = t - n if t >= n
          current = out[i + j] ## i64
          total = current + t
          total = total - n if total >= n
          out[i + j] = total
        j += 1
    i += 1
  0

-> padic_lane_axpy(out, source, factor, length, n, ninv, order) (i64[] i64[] i64 i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ua = factor ## u64
  i = order ## i64
  while i < length
    a = source[i] ## i64
    if a != 0
      ub = a ## u64
      hi = mulhi(ua, ub) ## i64
      lo = ua * ub
      m = lo * uninv
      mn_hi = mulhi(m, un) ## i64
      t = hi + mn_hi
      t = t + 1 if lo != 0
      t = t - n if t >= n
      current = out[i] ## i64
      total = current + t
      total = total - n if total >= n
      out[i] = total
    i += 1
  0

-> padic_lane_copy(source, out, source_from, out_from, count) (i64[] i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    value = source[source_from + i] ## i64
    out[out_from + i] = value
    i += 1
  0

# out[i-1] = i * source[i]; `r2` = R^2 mod n converts the plain multiplier i.
-> padic_lane_derivative(source, out, length, n, ninv, r2) (i64[] i64[] i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ur2 = r2 ## u64
  i = 1 ## i64
  while i < length
    a = source[i] ## i64
    ua = i ## u64
    ub = ur2
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    factor = hi + mn_hi
    factor = factor + 1 if lo != 0
    factor = factor - n if factor >= n
    ua = a ## u64
    ub = factor ## u64
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    t = hi + mn_hi
    t = t + 1 if lo != 0
    t = t - n if t >= n
    out[i - 1] = t
    i += 1
  0

# Horner with a Montgomery-form point; returns a Montgomery form.
-> padic_lane_evaluate(coefficients, length, value, n, ninv) (i64[] i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ub = value ## u64
  acc = 0 ## i64
  i = length - 1 ## i64
  while i >= 0
    c = coefficients[i] ## i64
    ua = acc ## u64
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    t = hi + mn_hi
    t = t + 1 if lo != 0
    t = t - n if t >= n
    acc = t + c
    acc = acc - n if acc >= n
    i -= 1
  acc

-> padic_lane_inverse(coefficients, out, length, n, ninv, lead_inverse) (i64[] i64[] i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ulead = lead_inverse ## u64
  out[0] = lead_inverse
  k = 1 ## i64
  while k < length
    acc = 0 ## i64
    j = 1 ## i64
    while j <= k
      a = coefficients[j] ## i64
      if a != 0
        b = out[k - j] ## i64
        ua = a ## u64
        ub = b ## u64
        hi = mulhi(ua, ub) ## i64
        lo = ua * ub
        m = lo * uninv
        mn_hi = mulhi(m, un) ## i64
        t = hi + mn_hi
        t = t + 1 if lo != 0
        t = t - n if t >= n
        acc = acc + t
        acc = acc - n if acc >= n
      j += 1
    negated = n - acc
    negated = 0 if negated == n
    ua = negated ## u64
    ub = ulead
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    t = hi + mn_hi
    t = t + 1 if lo != 0
    t = t - n if t >= n
    out[k] = t
    k += 1
  0

# out[i] = to_mont((from_mont(source[i]) mod m2)); `one` is the plain 1 (so
# mont_mul(x, 1) = x / R) and `r2` converts back.
-> padic_lane_mod(source, out, length, n, ninv, r2, m2) (i64[] i64[] i64 i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ur2 = r2 ## u64
  i = 0 ## i64
  while i < length
    x = source[i] ## i64
    ua = x ## u64
    ub = 1 ## u64
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    plain = hi + mn_hi
    plain = plain + 1 if lo != 0
    plain = plain - n if plain >= n
    reduced = plain % m2
    ua = reduced ## u64
    ub = ur2
    hi = mulhi(ua, ub) ## i64
    lo = ua * ub
    m = lo * uninv
    mn_hi = mulhi(m, un) ## i64
    t = hi + mn_hi
    t = t + 1 if lo != 0
    t = t - n if t >= n
    out[i] = t
    i += 1
  0

# row = row - factor * pivot_row on columns from..width-1 (Montgomery forms)
-> padic_lane_row_eliminate(row, pivot_row, factor, from, width, n, ninv) (i64[] i64[] i64 i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ua = factor ## u64
  k = from ## i64
  while k < width
    a = pivot_row[k] ## i64
    if a != 0
      ub = a ## u64
      hi = mulhi(ua, ub) ## i64
      lo = ua * ub
      m = lo * uninv
      mn_hi = mulhi(m, un) ## i64
      t = hi + mn_hi
      t = t + 1 if lo != 0
      t = t - n if t >= n
      current = row[k] ## i64
      total = current + n - t
      total = total - n if total >= n
      row[k] = total
    k += 1
  0

-> padic_lane_dot(row, vector, from, width, n, ninv) (i64[] i64[] i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  acc = 0 ## i64
  k = from ## i64
  while k < width
    a = row[k] ## i64
    if a != 0
      b = vector[k] ## i64
      if b != 0
        ua = a ## u64
        ub = b ## u64
        hi = mulhi(ua, ub) ## i64
        lo = ua * ub
        m = lo * uninv
        mn_hi = mulhi(m, un) ## i64
        t = hi + mn_hi
        t = t + 1 if lo != 0
        t = t - n if t >= n
        acc = acc + t
        acc = acc - n if acc >= n
    k += 1
  acc

# Flat row-major matrix helpers for the kernel: entries are Montgomery forms.
-> padic_lane_scatter(flat, width, column, source, count) (i64[] i64 i64 i64[] i64) i64
  m = 0 ## i64
  while m < count
    value = source[m] ## i64
    flat[m * width + column] = value
    m += 1
  0

# Best unused row for a column by p-adic valuation: returns row * 128 +
# valuation, or -1 when the column is zero on every unused row.
-> padic_lane_pivot_search(flat, width, row_count, column, used, prime, precision) (i64[] i64 i64 i64 i64[] i64 i64) i64
  best_row = 0 - 1 ## i64
  best_valuation = precision ## i64
  r = 0 ## i64
  while r < row_count
    flag = used[r] ## i64
    if flag == 0
      entry = flat[r * width + column] ## i64
      if entry != 0
        v = 0 ## i64
        remaining = entry ## i64
        while remaining % prime == 0 && v < precision
          remaining = remaining / prime
          v += 1
        if best_row < 0 || v < best_valuation
          best_row = r
          best_valuation = v
    r += 1
  return 0 - 1 if best_row < 0
  best_row * 128 + best_valuation

-> padic_lane_row_eliminate_flat(flat, width, row, pivot_row, factor, from, n, ninv) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  ua = factor ## u64
  base = row * width ## i64
  pivot_base = pivot_row * width ## i64
  k = from ## i64
  while k < width
    a = flat[pivot_base + k] ## i64
    if a != 0
      ub = a ## u64
      hi = mulhi(ua, ub) ## i64
      lo = ua * ub
      m = lo * uninv
      mn_hi = mulhi(m, un) ## i64
      t = hi + mn_hi
      t = t + 1 if lo != 0
      t = t - n if t >= n
      current = flat[base + k] ## i64
      total = current + n - t
      total = total - n if total >= n
      flat[base + k] = total
    k += 1
  0

# Eliminate one pivot column from every unused row.  `params` packs
# [pivot_row, pivot_power, inverse_mont, n, ninv]; returns the first row whose
# entry is not divisible by the pivot power, or -1.
-> padic_lane_eliminate_column(flat, width, row_count, column, used, params) (i64[] i64 i64 i64 i64[] i64[]) i64
  pivot_row = params[0] ## i64
  pivot_power = params[1] ## i64
  inverse_mont = params[2] ## i64
  n = params[3] ## i64
  ninv = params[4] ## i64
  un = n ## u64
  uninv = ninv ## u64
  uinv = inverse_mont ## u64
  pivot_base = pivot_row * width ## i64
  r = 0 ## i64
  while r < row_count
    flag = used[r] ## i64
    if flag == 0
      base = r * width ## i64
      entry = flat[base + column] ## i64
      if entry != 0
        return r if entry % pivot_power != 0
        quotient = entry / pivot_power ## i64
        ua = quotient ## u64
        ub = uinv
        hi = mulhi(ua, ub) ## i64
        lo = ua * ub
        m = lo * uninv
        mn_hi = mulhi(m, un) ## i64
        factor = hi + mn_hi
        factor = factor + 1 if lo != 0
        factor = factor - n if factor >= n
        ua = factor ## u64
        k = column ## i64
        while k < width
          a = flat[pivot_base + k] ## i64
          if a != 0
            ub = a ## u64
            hi = mulhi(ua, ub) ## i64
            lo = ua * ub
            m = lo * uninv
            mn_hi = mulhi(m, un) ## i64
            t = hi + mn_hi
            t = t + 1 if lo != 0
            t = t - n if t >= n
            current = flat[base + k] ## i64
            total = current + n - t
            total = total - n if total >= n
            flat[base + k] = total
          k += 1
    r += 1
  0 - 1

-> padic_lane_dot_flat(flat, width, row, vector, from, n, ninv) (i64[] i64 i64 i64[] i64 i64 i64) i64
  un = n ## u64
  uninv = ninv ## u64
  base = row * width ## i64
  acc = 0 ## i64
  k = from ## i64
  while k < width
    a = flat[base + k] ## i64
    if a != 0
      b = vector[k] ## i64
      if b != 0
        ua = a ## u64
        ub = b ## u64
        hi = mulhi(ua, ub) ## i64
        lo = ua * ub
        m = lo * uninv
        mn_hi = mulhi(m, un) ## i64
        t = hi + mn_hi
        t = t + 1 if lo != 0
        t = t - n if t >= n
        acc = acc + t
        acc = acc - n if acc >= n
    k += 1
  acc

# target[i] = (target[i] + delta[i] * power) mod n for i < count; delta < p
# and power <= n / p, so the product stays below n.
-> padic_lane_hensel_update(target, delta, count, power, n) (i64[] i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    d = delta[i] ## i64
    if d != 0
      current = target[i] ## i64
      total = (current + d * power) % n
      target[i] = total
    i += 1
  0

# e[i] = ((phi[i] - product[i]) mod n) / power mod p; returns the first index
# where the difference is not divisible by power, or -1.
-> padic_lane_hensel_residual(phi, product, e, length, n, power, prime) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < length
    a = phi[i] ## i64
    b = product[i] ## i64
    residual = a + n - b
    residual = residual - n if residual >= n
    return i if residual % power != 0
    e[i] = (residual / power) % prime
    i += 1
  0 - 1

+ PadicSeriesRing
  -> new(@prime, @precision, @length)
    raise "p-adic series ring needs a prime >= 2" if @prime < 2
    raise "p-adic series ring needs positive precision" if @precision < 1
    raise "p-adic series ring needs positive length" if @length < 1
    @modulus = @prime**@precision
    @machine = @modulus < 2**62
    if @machine
      @ninv = PadicSeriesRing.montgomery_ninv(@modulus)
      @r2 = (2**128) % @modulus
      @one = (2**64) % @modulus
      @prime_ninv = PadicSeriesRing.montgomery_ninv(@prime)
      @prime_r2 = (2**128) % @prime
      @prime_one = (2**64) % @prime

  # -N^-1 mod 2^64 as a two's-complement i64 bit pattern.
  -> .montgomery_ninv(n)
    inverse = PadicArithmetic.inverse_mod(n, 2**64)
    value = (2**64 - inverse) % (2**64)
    value -= 2**64 if value >= 2**63
    value

  # True when residues fit a signed 64-bit word and the native lane is used.
  -> machine?
    @machine

  -> buffer(length)
    i64[length]

  -> ninv
    @ninv

  -> r2
    @r2

  # Montgomery form of 1, i.e. R mod N.
  -> mont_one
    @one

  -> prime_ninv
    @prime_ninv

  -> prime_r2
    @prime_r2

  -> prime_one
    @prime_one

  -> to_mont(value)
    padic_mont_mul(normalize(value), @r2, @modulus, @ninv)

  -> from_mont(value)
    padic_mont_mul(value, 1, @modulus, @ninv)

  -> to_mont_prime(value)
    normalized = value % @prime
    normalized += @prime if normalized < 0
    padic_mont_mul(normalized, @prime_r2, @prime, @prime_ninv)

  -> from_mont_prime(value)
    padic_mont_mul(value, 1, @prime, @prime_ninv)

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
  # `coefficients` is an Array of integers; `buffer`, when given, is a
  # full-length u64 ring buffer adopted without copying (machine lane only).
  -> new(@ring, coefficients, known_digits = nil, buffer = nil)
    if @ring.class_name != "PadicSeriesRing"
      raise "p-adic series needs a PadicSeriesRing"
    if buffer != nil && @ring.machine?
      if buffer.size != @ring.length
        raise "p-adic series buffer must match the machine ring length"
      @coefficients = buffer
    elsif buffer != nil
      coefficients = buffer
    if buffer != nil && @ring.machine?
      nil
    elsif coefficients.class_name == "Array"
      if @ring.machine?
        @coefficients = @ring.buffer(@ring.length)
        index = 0
        while index < coefficients.size && index < @ring.length
          @coefficients[index] = @ring.to_mont(coefficients[index])
          index += 1
      else
        @coefficients = []
        index = 0
        while index < coefficients.size && index < @ring.length
          @coefficients.push(@ring.normalize(coefficients[index]))
          index += 1
        while @coefficients.size < @ring.length
          @coefficients.push(0)
    else
      raise "p-adic series needs an Array of coefficients"
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
    return @ring.from_mont(@coefficients[index]) if @ring.machine?
    @coefficients[index]

  -> coefficients
    out = []
    index = 0
    while index < @coefficients.size
      out.push(coefficient(index))
      index += 1
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
    @ring.valuation(@coefficients[0]) == 0

  # Copy into another ring of the same prime and precision (typically a
  # different truncation length); coefficients beyond the source are unknown
  # and left as zero, so only shortening is exact.
  -> resize(target_ring)
    if target_ring.prime != @ring.prime || target_ring.precision != @ring.precision
      raise "p-adic series resize needs the same prime and precision"
    PadicSeries.new(target_ring, coefficients, @known_digits)

  # Reduce every coefficient modulo p^known_digits so that a coefficient which
  # vanishes to the trustworthy precision is stored as an exact zero.
  -> reduce_to_known
    modulus = @ring.prime**@known_digits
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_mod(@coefficients, out, @ring.length, @ring.modulus, @ring.ninv, @ring.r2, modulus)
      return PadicSeries.new(@ring, nil, @known_digits, out)
    out = []
    index = 0
    while index < @coefficients.size
      out.push(@coefficients[index] % modulus)
      index += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> with_known_digits(digits)
    return PadicSeries.new(@ring, nil, digits, @coefficients) if @ring.machine?
    PadicSeries.new(@ring, @coefficients, digits)

  -> shared_digits(other)
    digits = @known_digits
    digits = other.known_digits if other.known_digits < digits
    digits

  -> machine_buffer_copy
    out = @ring.buffer(@ring.length)
    padic_lane_copy(@coefficients, out, 0, 0, @ring.length)
    out

  -> +(value)
    if value.class_name == "PadicSeries"
      if @ring.machine?
        out = machine_buffer_copy
        padic_lane_axpy(out, value.raw_coefficients, @ring.mont_one, @ring.length, @ring.modulus, @ring.ninv, value.order)
        return PadicSeries.new(@ring, nil, shared_digits(value), out)
      out = []
      index = 0
      while index < @coefficients.size
        out.push(@coefficients[index] + value.coefficient(index))
        index += 1
      return PadicSeries.new(@ring, out, shared_digits(value))
    if @ring.machine?
      out = machine_buffer_copy
      out[0] = (out[0] + @ring.to_mont(value)) % @ring.modulus
      return PadicSeries.new(@ring, nil, @known_digits, out)
    out = coefficients
    out[0] = out[0] + value
    PadicSeries.new(@ring, out, @known_digits)

  # The underlying buffer (machine lane) or Array; read-only use.
  -> raw_coefficients
    @coefficients

  -> -(value)
    if value.class_name == "PadicSeries"
      return self + value.negate
    self + (0 - value)

  -> negate
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_axpy(out, @coefficients, @ring.to_mont(@ring.modulus - 1), @ring.length, @ring.modulus, @ring.ninv, order)
      return PadicSeries.new(@ring, nil, @known_digits, out)
    out = []
    @coefficients.each -> out.push(0 - item)
    PadicSeries.new(@ring, out, @known_digits)

  -> -@
    negate

  -> scale(factor)
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_axpy(out, @coefficients, @ring.to_mont(factor), @ring.length, @ring.modulus, @ring.ninv, order)
      return PadicSeries.new(@ring, nil, @known_digits, out)
    out = []
    @coefficients.each -> out.push(item * factor)
    PadicSeries.new(@ring, out, @known_digits)

  -> *(value)
    return scale(value) if value.class_name != "PadicSeries"
    length = @coefficients.size
    if @ring.machine?
      out = @ring.buffer(length)
      padic_lane_product(@coefficients, value.raw_coefficients, out, length, @ring.modulus, @ring.ninv, order, value.order)
      return PadicSeries.new(@ring, nil, shared_digits(value), out)
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
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_copy(@coefficients, out, 0, count, @ring.length - count) if count < @ring.length
      return PadicSeries.new(@ring, nil, @known_digits, out)
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
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_copy(@coefficients, out, count, 0, @ring.length - count)
      return PadicSeries.new(@ring, nil, @known_digits, out)
    out = []
    index = count
    while index < @coefficients.size
      out.push(@coefficients[index])
      index += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> divide_power(exponent)
    out = []
    index = 0
    while index < @coefficients.size
      out.push(@ring.divide_power(coefficient(index), exponent))
      index += 1
    PadicSeries.new(@ring, out, @known_digits - exponent)

  -> derivative
    if @ring.machine?
      out = @ring.buffer(@ring.length)
      padic_lane_derivative(@coefficients, out, @ring.length, @ring.modulus, @ring.ninv, @ring.r2)
      return PadicSeries.new(@ring, nil, @known_digits, out)
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
      numerator = (coefficient(m) * scale) / (prime**power)
      out.push((numerator % modulus) * @ring.unit_inverse(unit))
      m += 1
    PadicSeries.new(@ring, out, @known_digits)

  -> evaluate(value)
    modulus = @ring.modulus
    if @ring.machine?
      mont_value = @ring.to_mont(value)
      return @ring.from_mont(padic_lane_evaluate(@coefficients, @ring.length, mont_value, modulus, @ring.ninv))
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
    if @ring.machine?
      lead = @ring.to_mont(@ring.unit_inverse(@ring.from_mont(@coefficients[0])))
      out = @ring.buffer(length)
      padic_lane_inverse(@coefficients, out, length, modulus, @ring.ninv, lead)
      return PadicSeries.new(@ring, nil, @known_digits, out)
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
    return weierstrass_factor_machine(degree) if @ring.machine?
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
    if ring.machine?
      out = ring.buffer(length)
      k = 0
      while k < series_list.size
        c = coefficients[k]
        if c != 0
          source = series_list[k]
          padic_lane_axpy(out, source.raw_coefficients, ring.to_mont(c), length, modulus, ring.ninv, source.order)
        k += 1
      return PadicSeries.new(ring, nil, digits, out)
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

  # Machine-lane Weierstrass factor: the same digitwise Hensel lift with every
  # intermediate in a u64 buffer and the products on the native lane.
  -> weierstrass_factor_machine(degree)
    prime = @ring.prime
    precision = @known_digits
    length = @coefficients.size
    modulus = @ring.modulus
    ninv = @ring.ninv
    prime_ninv = @ring.prime_ninv
    if degree < 0 || degree >= length
      raise "Weierstrass degree is outside the truncation"
    index = 0
    while index < degree
      if @ring.valuation(@coefficients[index]) == 0
        raise "Weierstrass factor degree contradicts a unit coefficient"
      index += 1
    if @ring.valuation(@coefficients[degree]) != 0
      raise "Weierstrass factor needs a unit coefficient at its degree"
    # mod-p cofactor and its inverse, in Montgomery form modulo p (the
    # Montgomery form modulo N reduces to the Montgomery form modulo p)
    hbar = i64[length]
    index = degree
    while index < length
      hbar[index - degree] = @coefficients[index] % prime
      index += 1
    hinv = i64[length]
    lead = @ring.to_mont_prime(PadicArithmetic.inverse_mod(@ring.from_mont_prime(hbar[0]), prime))
    padic_lane_inverse(hbar, hinv, length, prime, prime_ninv, lead)
    g = i64[length]
    g[degree] = @ring.mont_one
    h = i64[length]
    padic_lane_copy(hbar, h, 0, 0, length)
    e = i64[length]
    q = i64[length]
    delta_g = i64[length]
    correction = i64[length]
    delta_h = i64[length]
    product = i64[length]
    step = 1
    power = prime
    while step < precision
      index = 0
      while index < length
        product[index] = 0
        q[index] = 0
        delta_g[index] = 0
        correction[index] = 0
        delta_h[index] = 0
        index += 1
      padic_lane_product(g, h, product, length, modulus, ninv, 0, 0)
      failed = padic_lane_hensel_residual(@coefficients, product, e, length, modulus, power, prime)
      if failed >= 0
        raise "Hensel lifting lost agreement at digit " + step.to_s
      padic_lane_product(e, hinv, q, length, prime, prime_ninv, 0, 0)
      index = 0
      while index < degree
        delta_g[index] = q[index]
        index += 1
      padic_lane_product(delta_g, hbar, correction, length, prime, prime_ninv, 0, 0)
      index = 0
      while index < length
        value = (e[index] + prime - correction[index]) % prime
        if index < degree
          raise "Hensel cofactor correction is not divisible by the pivot power" if value != 0
        else
          delta_h[index - degree] = value
        index += 1
      padic_lane_hensel_update(g, delta_g, degree, power, modulus)
      padic_lane_hensel_update(h, delta_h, length, power, modulus)
      step += 1
      power = power * prime
    index = 0
    while index < length
      product[index] = 0
      index += 1
    padic_lane_product(g, h, product, length, modulus, ninv, 0, 0)
    check_modulus = prime**precision
    index = 0
    while index < length
      difference = (@coefficients[index] + modulus - product[index]) % modulus
      raise "Weierstrass factorization failed verification" if difference % check_modulus != 0
      index += 1
    out = []
    index = 0
    while index <= degree
      value = @ring.from_mont(g[index])
      if index < degree && value % prime != 0
        raise "Weierstrass factor has a unit non-leading coefficient"
      out.push(value)
      index += 1
    out

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
        text = text + coefficient(index).to_s + "*t^" + index.to_s
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
  # `rows` is an Array of integer rows.  On the machine lane a caller may
  # instead hand over `flat`, a row-major i64 buffer of `row_count` rows whose
  # entries are already Montgomery forms (as produced by series buffers).
  -> new(rows, width, @ring, flat = nil, row_count = nil)
    @width = width
    if flat != nil
      raise "flat kernel input needs the machine lane" if !@ring.machine?
      raise "flat kernel input needs its row count" if row_count == nil
      @row_count = row_count
      @original = nil
      eliminate_flat(flat)
      return nil
    if rows.class_name != "Array"
      raise "p-adic kernel needs an Array of rows"
    @row_count = rows.size
    if @ring.machine?
      buffer = i64[@row_count * width]
      r = 0
      while r < @row_count
        row = rows[r]
        raise "p-adic kernel row has the wrong width" if row.size != width
        c = 0
        while c < width
          buffer[r * width + c] = @ring.to_mont(row[c])
          c += 1
        r += 1
      @original = nil
      eliminate_flat(buffer)
      return nil
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

  # Machine lane: rows live in u64 buffers and every row operation, dot
  # product, and verification runs natively.
  -> eliminate_flat(flat)
    modulus = @ring.modulus
    precision = @ring.precision
    prime = @ring.prime
    ninv = @ring.ninv
    original = i64[@row_count * @width]
    padic_lane_copy(flat, original, 0, 0, @row_count * @width)
    @pivot_columns = []
    @pivot_rows = []
    @pivot_valuations = []
    used = i64[@row_count]
    free_columns = []
    column = 0
    while column < @width
      found = padic_lane_pivot_search(flat, @width, @row_count, column, used, prime, precision)
      best_row = found / 128
      best_valuation = found % 128
      if found < 0 || best_valuation >= precision
        free_columns.push(column)
      else
        used[best_row] = 1
        @pivot_columns.push(column)
        @pivot_rows.push(best_row)
        @pivot_valuations.push(best_valuation)
        pivot_power = prime**best_valuation
        pivot_entry = flat[best_row * @width + column]
        pivot_unit = @ring.from_mont(pivot_entry / pivot_power)
        inverse_mont = @ring.to_mont(@ring.unit_inverse(pivot_unit))
        params = i64[5]
        params[0] = best_row
        params[1] = pivot_power
        params[2] = inverse_mont
        params[3] = modulus
        params[4] = ninv
        bad = padic_lane_eliminate_column(flat, @width, @row_count, column, used, params)
        if bad >= 0
          raise "p-adic kernel pivot selection failed the divisibility invariant"
      column += 1
    total_loss = 0
    @pivot_valuations.each -> total_loss += item
    @lost_digits = total_loss
    scale = (prime**total_loss) % modulus
    check_modulus = prime**(precision - total_loss)
    @vectors = []
    free_columns.each -> (free)
      vector = i64[@width]
      vector[free] = @ring.to_mont(scale)
      index = @pivot_columns.size - 1
      while index >= 0
        column = @pivot_columns[index]
        row = @pivot_rows[index]
        valuation = @pivot_valuations[index]
        acc = padic_lane_dot_flat(flat, @width, row, vector, column + 1, modulus, ninv)
        pivot_power = prime**valuation
        pivot_unit = @ring.from_mont(flat[row * @width + column] / pivot_power)
        inverse_mont = @ring.to_mont(@ring.unit_inverse(pivot_unit))
        numerator = (modulus - acc) % modulus
        if numerator % pivot_power != 0
          raise "p-adic kernel back substitution lost exactness"
        vector[column] = padic_mont_mul(numerator / pivot_power, inverse_mont, modulus, ninv)
        index -= 1
      reduced = []
      check = i64[@width]
      c = 0
      while c < @width
        plain = @ring.from_mont(vector[c]) % check_modulus
        reduced.push(plain)
        check[c] = @ring.to_mont(plain)
        c += 1
      r = 0
      while r < @row_count
        if @ring.from_mont(padic_lane_dot_flat(original, @width, r, check, 0, modulus, ninv)) % check_modulus != 0
          raise "p-adic kernel vector failed replay against the original rows"
        r += 1
      @vectors.push(reduced)
    nil

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
