# Exact prime-power factorization values.
#
# Integer#factor and Int#factor construct an IntegerFactorization. Iteration
# yields PrimePower values in increasing prime order, so callers can write
#
#   n.factor.map -> item.prime
#
# or use the convenience `n.factor.primes` to obtain the distinct prime
# divisors. Pipeline `/method` currently has an array/range storage boundary;
# this value remains an ordinary Enumerable instead of pretending to be one.

+ PrimePower
  -> new(@prime, @exponent)
    raise "PrimePower: prime must be at least 2" if @prime < 2
    raise "PrimePower: base must be prime" if !@prime.prime?
    raise "PrimePower: exponent must be positive" if @exponent < 1

  -> prime
    @prime

  -> exponent
    @exponent

  -> value
    @prime ** @exponent

  -> ==(other)
    return false if other == nil || other.class_name != "PrimePower"
    @prime == other.prime && @exponent == other.exponent

  -> eql?(other)
    self == other

  -> to_s
    return @prime.to_s if @exponent == 1
    @prime.to_s + "^" + @exponent.to_s

  -> inspect
    to_s


+ IntegerFactorization
  is Enumerable

  -> new(number)
    raise "Integer#factor: factorization of zero is undefined" if number == 0

    @number = number
    @sign = number < 0 ? -1 : 1
    remaining = number < 0 ? 0 - number : number
    @factors = []

    remaining = extract_factor(remaining, 2)
    remaining = extract_factor(remaining, 3)

    # Every prime greater than three is 6k +/- 1. Trial division is exact and
    # is deliberately sufficient for the algebra program's discriminant,
    # whose support is {2, 3, 13}. A later Pollard-rho implementation can live
    # behind this value API without changing callers.
    candidate = 5
    step = 2
    while candidate * candidate <= remaining
      remaining = extract_factor(remaining, candidate)
      candidate += step
      step = 6 - step

    if remaining > 1
      @factors.push(PrimePower.new(remaining, 1))
    self

  -> extract_factor(number, prime)
    return number if number % prime != 0
    exponent = 0
    remaining = number
    while remaining % prime == 0
      remaining = remaining / prime
      exponent += 1
    @factors.push(PrimePower.new(prime, exponent))
    remaining

  -> number
    @number

  -> sign
    @sign

  -> size
    @factors.size

  -> empty?
    @factors.empty?

  -> [](index)
    @factors[index]

  -> each(&)
    @factors.each -> (factor)
      &(factor)
    self

  -> to_a
    out = []
    each -> (factor)
      out.push(factor)
    out

  -> primes
    out = []
    each -> (factor)
      out.push(factor.prime)
    out

  -> value
    result = @sign
    each -> (factor)
      result *= factor.value
    result

  -> ==(other)
    return false if other == nil || other.class_name != "IntegerFactorization"
    return false if @sign != other.sign || @factors.size != other.size
    i = 0
    while i < @factors.size
      return false if @factors[i] != other[i]
      i += 1
    true

  -> eql?(other)
    self == other

  -> to_s
    return "1" if @sign > 0 && @factors.empty?
    return "-1" if @sign < 0 && @factors.empty?

    parts = []
    parts.push("-1") if @sign < 0
    each -> (factor)
      parts.push(factor.to_s)
    parts.join(" * ")

  -> inspect
    to_s
