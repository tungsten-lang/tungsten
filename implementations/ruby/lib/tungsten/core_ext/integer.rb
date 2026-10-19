class Integer
  # Number of 1 bits in the magnitude, matching Tungsten's Int#popcount
  # (Python int.bit_count): 0 -> 0, 255 -> 8, -255 -> 8.
  def popcount
    abs.digits(2).sum
  end

  alias_method :bit_count, :popcount

  def modpow(exponent, modulus)
    raise Tungsten::Error, "modpow: negative exponent" if exponent < 0
    raise Tungsten::Error, "modpow: modulus must be nonzero" if modulus.zero?
    m = modulus.abs
    return 0 if m == 1
    (self % m).pow(exponent, m)
  end

  alias_method :powmod, :modpow

  def invmod(modulus)
    raise Tungsten::Error, "Integer#invmod: modulus must be nonzero" if modulus.zero?
    m = modulus.abs
    return 0 if m == 1
    a = self % m
    t = 0
    newt = 1
    r = m
    newr = a
    while newr != 0
      q = r / newr
      t, newt = newt, t - q * newt
      r, newr = newr, r - q * newr
    end
    raise Tungsten::Error, "Integer#invmod: not invertible" if r > 1
    t += m if t < 0
    t
  end

  def tdiv(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    q = abs / other.abs
    (negative? ^ other.negative?) ? -q : q
  end

  def tmod(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    r = abs % other.abs
    negative? ? -r : r
  end

  def tdivmod(other)
    [tdiv(other), tmod(other)]
  end

  def fdiv(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    div(other)
  end

  def fmod(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    modulo(other)
  end

  def fdivmod(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    divmod(other)
  end

  def cdiv(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    q, r = tdivmod(other)
    q += 1 if r != 0 && (r.negative? == other.negative?)
    q
  end

  def cmod(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    _q, r = tdivmod(other)
    r -= other if r != 0 && (r.negative? == other.negative?)
    r
  end

  def cdivmod(other)
    raise Tungsten::ZeroDivisionError, "division by zero" if other.zero?
    q, r = tdivmod(other)
    if r != 0 && (r.negative? == other.negative?)
      q += 1
      r -= other
    end
    [q, r]
  end

  def divexact(other)
    tdiv(other)
  end

  def divisible?(other)
    return zero? if other.zero?
    (self % other).zero?
  end

  alias_method :divisible_by?, :divisible?

  def congruent?(c, d)
    (self - c).divisible?(d)
  end

  def isqrt
    raise Tungsten::DomainError, "isqrt of negative number" if negative?
    Integer.sqrt(self)
  end

  def isqrt_rem
    s = isqrt
    [s, self - s * s]
  end

  def iroot_rem(n)
    raise Tungsten::DomainError, "iroot degree must be positive" if n <= 0
    raise Tungsten::DomainError, "even root of negative number" if negative? && n.even?
    return [0, 0] if zero?
    return [self, 0] if n == 1 || abs == 1
    a = abs
    bits = a.bit_length
    if n >= bits
      r = a - 1
      return negative? ? [-1, -r] : [1, r]
    end
    x = 1 << ((bits - 1) / n + 1)
    nm1 = n - 1
    loop do
      x_nm1 = x**nm1
      q = a / x_nm1
      x_next = (nm1 * x + q) / n
      break if x_next >= x
      x = x_next
    end
    rem = a - (x**n)
    negative? ? [-x, -rem] : [x, rem]
  end

  def iroot(n)
    iroot_rem(n)[0]
  end

  def perfect_square?
    return false if negative?
    s = Integer.sqrt(self)
    s * s == self
  end

  def perfect_power?
    return true if zero? || abs == 1
    a = abs
    bits = a.bit_length
    2.upto(bits) do |p|
      next if negative? && p.even?
      _r, rem = a.iroot_rem(p)
      return true if rem.zero?
    end
    false
  end

  def gcdext(other)
    return [0, 0, 0] if zero? && other.zero?
    return [abs, negative? ? -1 : 1, 0] if other.zero?
    return [other.abs, 0, other.negative? ? -1 : 1] if zero?
    old_r = abs
    r = other.abs
    old_s = 1
    s = 0
    old_t = 0
    t = 1
    while r != 0
      q = old_r / r
      old_r, r = r, old_r - q * r
      old_s, s = s, old_s - q * s
      old_t, t = t, old_t - q * t
    end
    old_s = -old_s if negative?
    old_t = -old_t if other.negative?
    [old_r, old_s, old_t]
  end

  def jacobi(n)
    raise Tungsten::DomainError, "jacobi requires positive odd modulus" if n <= 0 || n.even?
    return 1 if n == 1
    a = self % n
    result = 1
    while a != 0
      while a.even?
        a >>= 1
        result = -result if (n & 7) == 3 || (n & 7) == 5
      end
      a, n = n, a
      result = -result if (a & 3) == 3 && (n & 3) == 3
      a %= n
    end
    n == 1 ? result : 0
  end

  def kronecker(b)
    return (abs == 1 ? 1 : 0) if b.zero?
    result = (negative? && b.negative?) ? -1 : 1
    b_abs = b.abs
    tz = b_abs.trailing_zeros
    if tz > 0
      return 0 if even?
      if tz.odd?
        a8 = abs & 7
        result = -result if a8 == 3 || a8 == 5
      end
      b_abs >>= tz
    end
    result * jacobi(b_abs)
  end

  def remove_factor(f)
    raise Tungsten::DomainError, "remove_factor requires |factor| > 1" if f.abs <= 1
    return [0, 0] if zero?
    cur = self
    mult = 0
    while cur.divisible?(f)
      cur = cur.tdiv(f)
      mult += 1
    end
    [cur, mult]
  end

  def double_factorial
    raise Tungsten::DomainError, "double_factorial of negative number < -1" if self < -1
    return 1 if self <= 1
    acc = 1
    cur = self
    while cur > 1
      acc *= cur
      cur -= 2
    end
    acc
  end

  def multifactorial(m)
    raise Tungsten::DomainError, "multifactorial of negative number" if negative?
    raise Tungsten::DomainError, "multifactorial step must be positive" if m <= 0
    return 1 if self <= 1
    acc = 1
    cur = self
    while cur > 1
      acc *= cur
      cur -= m
    end
    acc
  end

  def binomial(k)
    return 0 if k < 0
    return 1 if k.zero?
    if self >= 0
      return 0 if k > self
      k = self - k if k > self - k
    end
    num = 1
    den = 1
    1.upto(k) do |i|
      num *= (self - i + 1)
      den *= i
    end
    num / den
  end

  alias_method :choose, :binomial

  def fib2
    raise Tungsten::DomainError, "fib2 of negative index" if negative?
    return [0, 1] if zero?
    a = 0
    b = 1
    (bit_length - 1).downto(0) do |i|
      c = a * ((b << 1) - a)
      d = a * a + b * b
      if ((self >> i) & 1) == 1
        a = d
        b = c + d
      else
        a = c
        b = d
      end
    end
    [a, b - a]
  end

  def fib
    raise Tungsten::DomainError, "fib of negative index" if negative?
    return 0 if zero?
    fib2[0]
  end

  def lucas2
    raise Tungsten::DomainError, "lucas2 of negative index" if negative?
    return [2, -1] if zero?
    fn, fnm1 = fib2
    ln = fn + (fnm1 << 1)
    lnm1 = (fn << 1) - fnm1
    [ln, lnm1]
  end

  def lucas
    raise Tungsten::DomainError, "lucas of negative index" if negative?
    return 2 if zero?
    lucas2[0]
  end

  def sizeinbase(base = 10)
    raise Tungsten::DomainError, "sizeinbase requires base in 2..62" if base < 2 || base > 62
    return 1 if zero?
    if (base & (base - 1)).zero?
      k = base.trailing_zeros
      return (abs.bit_length + k - 1) / k
    end
    ((abs.bit_length - 1) / Math.log2(base)).floor + 1
  end

  alias_method :size_in_base, :sizeinbase

  def hamdist(other)
    return -1 if negative? != other.negative?
    (self ^ other).popcount
  end

  alias_method :hamming_distance, :hamdist

  def trailing_zeros
    return 0 if zero?
    a = abs
    (a & -a).bit_length - 1
  end

  def scan1(start = 0)
    start = 0 if start < 0
    return -1 if zero?
    return (~self).scan0(start) if negative?
    shifted = self >> start
    return -1 if shifted.zero?
    start + shifted.trailing_zeros
  end

  def scan0(start = 0)
    start = 0 if start < 0
    return start if zero?
    return (~self).scan1(start) if negative?
    inv = (~self) >> start
    start + inv.trailing_zeros
  end

  def tstbit(idx)
    return 0 if idx < 0
    self[idx]
  end

  def bit_set?(idx)
    tstbit(idx) == 1
  end

  def setbit(idx)
    raise Tungsten::DomainError, "bit index must be non-negative" if idx < 0
    self | (1 << idx)
  end

  def clrbit(idx)
    raise Tungsten::DomainError, "bit index must be non-negative" if idx < 0
    self & ~(1 << idx)
  end

  def combit(idx)
    raise Tungsten::DomainError, "bit index must be non-negative" if idx < 0
    self ^ (1 << idx)
  end

  def cmpabs(other)
    abs <=> other.abs
  end

  def to_bytes(order = :big)
    return Tungsten::ByteArray.new([]) if zero?
    a = abs
    nbytes = (a.bit_length + 7) >> 3
    bytes = Array.new(nbytes) { |i| (a >> (i << 3)) & 0xFF }
    is_le = (order == :little || order == :le || order == "little" || order == "le" || (order.is_a?(Integer) && order < 0))
    bytes.reverse! unless is_le
    Tungsten::ByteArray.new(bytes)
  end

  def self.from_bytes(bytes, order = :big)
    raw =
      case bytes
      when Tungsten::ByteArray then bytes.bytes
      when String then bytes.bytes
      when Array then bytes.map { |b| b.to_i & 0xFF }
      else raise Tungsten::Error, "from_bytes: expected ByteArray, Array, or String"
      end
    return 0 if raw.empty?
    is_le = (order == :little || order == :le || order == "little" || order == "le" || (order.is_a?(Integer) && order < 0))
    ordered = is_le ? raw.reverse : raw
    ordered.reduce(0) { |acc, b| (acc << 8) | (b & 0xFF) }
  end
end

