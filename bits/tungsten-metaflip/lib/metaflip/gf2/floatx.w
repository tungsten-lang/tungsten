# Exact IEEE-754 double <-> decimal conversion for the GF(2) toolchain.
#
# Python's `json.dumps` prints a float with `repr` (the shortest digit string
# that reads back to the same double), `f'{x:.2f}'` rounds the exact binary
# value half-even, and `float(text)` reads text with correct rounding. Tungsten's
# own `Float#to_s` prints 17 significant digits, and its decimal literals are a
# different type, so byte-identical manifests, logs and reports need their own
# exact conversion. Everything here is integer arithmetic on the double's bit
# pattern (BigInt where a scale factor needs it); no libm, no printf.
#
# A Float here is a Tungsten `Float` (an IEEE double; write `~1.5` or use
# `String#to_f`). Int, BigInt and Decimal arguments are converted first with
# `Floatx.of`, exactly like Python converts an int before formatting it.
# Arithmetic that must reproduce a Python float has to run on Floats, not on
# Decimals: `0.1 + 0.2` is exactly 0.3 in Tungsten and 0.30000000000000004 in
# Python, `~0.1 + ~0.2` matches Python.
#
# Users (original -> function):
#   json.dumps float              -> repr          (jsonx.w writer)
#   json.loads float              -> from_decimal  (jsonx.w parser)
#   f'{x:.4f}', '%.1f'            -> fixed         (textx.w)
#   f'{x:g}'                      -> general
#   f'{x:.1%}', f'{x:.0%}'        -> percent
#   round(t, 2) in the JSONL logs -> round
#   float(os.environ[...]), argparse type=float -> parse
#   statistics.median of an even count (a + b) / 2 -> ratio
+ FloatxError < Error

+ Floatx
  # ---- bit level ---------------------------------------------------------

  # [negative, exponent field, mantissa field] of a Float (IEEE-754 binary64).
  # A boxed double is its bit pattern plus 2^48, see wvalue_encoding.md.
  -> .fields(x)
    raw = (wvalue_bits(x) - 281474976710656) ## i64
    [raw < 0, (raw >> 52) & 2047, raw & 4503599627370495]

  # The Float with these fields. NaN is canonicalised like the runtime does.
  -> .from_fields(negative, exponent, mantissa)
    return wvalue_from_bits(9221120237041090560 ## i64) if exponent == 2047 && mantissa != 0
    raw = ((exponent << 52) | mantissa) ## i64
    if negative
      sign = (0 - 9223372036854775807 - 1) ## i64
      raw = (raw | sign) ## i64
    wvalue_from_bits((raw + 281474976710656) ## i64)

  -> .nan?(x)
    fields = Floatx.fields(x)
    fields[1] == 2047 && fields[2] != 0

  -> .infinite?(x)
    fields = Floatx.fields(x)
    fields[1] == 2047 && fields[2] == 0

  -> .negative?(x)
    Floatx.fields(x)[0]

  -> .zero(negative = false)
    Floatx.from_fields(negative, 0, 0)

  -> .infinity(negative = false)
    Floatx.from_fields(negative, 2047, 0)

  -> .nan
    Floatx.from_fields(false, 2047, 1)

  # Any number as a Float, rounded to nearest even like Python's float(n).
  -> .of(number)
    kind = type(number)
    return number if kind == "Float"
    return Floatx.from_integer(number) if kind == "Int" || kind == "BigInt"
    return Floatx.parse(number.to_s) if kind == "Decimal"
    raise FloatxError.new("cannot convert " + kind + " to a float")

  # The magnitude of a finite Float as [f, e] with |x| = f * 2^e, f an integer.
  -> .magnitude(x)
    fields = Floatx.fields(x)
    exponent = fields[1]
    mantissa = fields[2]
    return [mantissa, 0 - 1074] if exponent == 0
    [mantissa + 4503599627370496, exponent - 1075]

  # ---- decimal -> double -------------------------------------------------

  # Nearest double (ties to even) to an integer.
  -> .from_integer(n)
    return Floatx.zero if n == 0
    negative = n < 0
    magnitude = negative ? 0 - n : n
    Floatx.round_to_double(negative, magnitude, 1, magnitude.bit_length - 53)

  # numerator / denominator for integers, correctly rounded like Python's int / int.
  -> .ratio(numerator, denominator)
    raise FloatxError.new("division by zero") if denominator == 0
    return Floatx.zero if numerator == 0
    negative = (numerator < 0) != (denominator < 0)
    top = numerator < 0 ? 0 - numerator : numerator
    bottom = denominator < 0 ? 0 - denominator : denominator
    Floatx.round_to_double(negative, top, bottom, top.bit_length - bottom.bit_length - 53)

  # Nearest double to (+-) mantissa * 10^exp10, correctly rounded (ties to
  # even), including subnormals, underflow to a signed zero and overflow to
  # infinity. `mantissa` is a non-negative Integer of any size.
  -> .from_decimal(negative, mantissa, exp10)
    return Floatx.zero(negative) if mantissa == 0
    top = mantissa.to_s.size + exp10
    return Floatx.infinity(negative) if top > 310
    return Floatx.zero(negative) if top < -324
    numerator = mantissa
    denominator = 1
    if exp10 >= 0
      numerator = mantissa * (10 ** exp10)
    else
      denominator = 10 ** (0 - exp10)
    Floatx.round_to_double(negative, numerator, denominator, numerator.bit_length - denominator.bit_length - 53)

  # Round numerator/denominator (positive integers) to a double. `guess` is a
  # first estimate of the binary exponent k such that the quotient
  # numerator / (denominator * 2^k) has 53 bits.
  -> .round_to_double(negative, numerator, denominator, guess)
    k = guess
    k = 0 - 1074 if k < 0 - 1074
    quotient = 0
    remainder = 0
    scaled = denominator
    while true
      if k >= 0
        scaled = denominator << k
        parts = numerator.divmod(scaled)
      else
        scaled = denominator
        parts = (numerator << (0 - k)).divmod(denominator)
      quotient = parts[0]
      remainder = parts[1]
      break if quotient < 9007199254740992
      k += 1
    twice = remainder * 2
    quotient += 1 if twice > scaled || (twice == scaled && quotient % 2 == 1)
    # (k + 1074) * 2^52 + quotient is the bit pattern for every case: normal
    # numbers, subnormals (k = -1074) and the carry into the next binade.
    raw = ((k + 1074) << 52) + quotient
    return Floatx.infinity(negative) if raw >= 9218868437227405312
    Floatx.from_fields(negative, raw >> 52, raw & 4503599627370495)

  # Python's float(text) for decimal text: optional sign and surrounding
  # whitespace, digits with an optional fraction and exponent (single
  # underscores between digits allowed), or inf / infinity / nan.
  -> .parse(text)
    body = text.strip
    negative = false
    start = 0
    if body.starts_with?("-") || body.starts_with?("+")
      negative = body.starts_with?("-")
      start = 1
    word = body.slice(start, body.size - start).downcase
    return Floatx.infinity(negative) if word == "inf" || word == "infinity"
    return Floatx.nan if word == "nan"
    view = ccall("w_string_bytes_view", body) ## u8[]
    n = body.size ## i64
    whole = Floatx.scan_digits(view, n, start)
    digits = whole[0]
    pos = whole[1] ## i64
    fraction = 0
    if pos < n && view[pos] == 46
      part = Floatx.scan_digits(view, n, pos + 1)
      digits = digits + part[0]
      fraction = part[0].size
      pos = part[1]
    Floatx.bad_float(text) if digits.size == 0
    exponent = 0
    if pos < n && (view[pos] == 101 || view[pos] == 69)
      pos += 1
      sign = 1
      if pos < n && (view[pos] == 43 || view[pos] == 45)
        sign = view[pos] == 45 ? 0 - 1 : 1
        pos += 1
      part = Floatx.scan_digits(view, n, pos)
      Floatx.bad_float(text) if part[0].size == 0
      exponent = sign * part[0].to_i
      pos = part[1]
    Floatx.bad_float(text) if pos != n
    Floatx.from_decimal(negative, digits.to_i, exponent - fraction)

  # The digits at pos (a single '_' may separate two digits), as [text, next].
  -> .scan_digits(view, n, pos)
    at = pos ## i64
    text = ""
    while at < n
      b = view[at] ## i64
      if b >= 48 && b <= 57
        text = text + b.chr
      elsif b == 95 && text.size > 0 && at + 1 < n && view[at + 1] >= 48 && view[at + 1] <= 57
        text = text
      else
        break
      at += 1
    [text, at]

  -> .bad_float(text)
    raise FloatxError.new("could not convert string to float: '" + text + "'")

  # ---- double -> shortest decimal ----------------------------------------

  # Shortest digit string that reads back to x (Steele-White / Burger-Dybvig
  # free-format, the digits Python's repr and Ruby's Float#to_s print) as
  # [digits, decpt]: |x| = 0.DIGITS * 10^decpt. x must be finite and non-zero.
  -> .shortest(x)
    parts = Floatx.magnitude(x)
    f = parts[0]
    e = parts[1]
    even = f % 2 == 0
    if e >= 0
      be = 1 << e
      if f != 4503599627370496
        r = f * be * 2
        s = 2
        m_plus = be
        m_minus = be
      else
        r = f * be * 4
        s = 4
        m_plus = be * 2
        m_minus = be
    elsif e == 0 - 1074 || f != 4503599627370496
      r = f * 2
      s = (1 << (0 - e)) * 2
      m_plus = 1
      m_minus = 1
    else
      r = f * 4
      s = (1 << (1 - e)) * 2
      m_plus = 2
      m_minus = 1
    # k: the smallest power with the upper boundary below 10^k
    k = Floatx.floor_div((f.bit_length + e - 1) * 30103, 100000)
    if k >= 0
      s = s * (10 ** k)
    else
      scale = 10 ** (0 - k)
      r = r * scale
      m_plus = m_plus * scale
      m_minus = m_minus * scale
    while (even ? r + m_plus >= s : r + m_plus > s)
      s = s * 10
      k += 1
    digits = ""
    while true
      r = r * 10
      m_plus = m_plus * 10
      m_minus = m_minus * 10
      parts = r.divmod(s)
      d = parts[0]
      r = parts[1]
      low = even ? r <= m_minus : r < m_minus
      high = even ? r + m_plus >= s : r + m_plus > s
      if !low && !high
        digits = digits + d.to_s
      else
        # both boundaries reached: the closer digit, an exact tie goes to the even one
        d += 1 if high && (!low || r * 2 > s || (r * 2 == s && d % 2 == 1))
        digits = digits + d.to_s
        break
    [digits, k]

  -> .floor_div(a, b)
    quotient = a / b
    quotient -= 1 if a % b != 0 && (a < 0) != (b < 0)
    quotient

  # ---- formatting ---------------------------------------------------------

  # Python repr(float): '0.1', '1e-05', '1.5e+20', '100.0', 'inf', 'nan'.
  -> .repr(number)
    x = Floatx.of(number)
    special = Floatx.special(x, "inf", "nan")
    return special if special != nil
    negative = Floatx.negative?(x)
    return (negative ? "-0.0" : "0.0") if Floatx.zero?(x)
    parts = Floatx.shortest(x)
    Floatx.layout(negative, parts[0], parts[1])

  -> .zero?(x)
    fields = Floatx.fields(x)
    fields[1] == 0 && fields[2] == 0

  # The spelling of inf / nan, or nil for a finite number.
  -> .special(x, infinity, not_a_number)
    fields = Floatx.fields(x)
    return nil if fields[1] != 2047
    return not_a_number if fields[2] != 0
    fields[0] ? "-" + infinity : infinity

  # Place shortest digits the way Python's repr does: fixed notation while the
  # decimal point falls inside (-4, 16], exponent form ('1e-05', '1.5e+20') outside.
  -> .layout(negative, digits, decpt)
    count = digits.size
    text = ""
    if decpt > 16 || decpt <= 0 - 4
      first = digits.slice(0, 1)
      rest = digits.slice(1, count - 1)
      mantissa = first
      if count > 1
        mantissa = first + "." + rest
      exponent = decpt - 1
      sign = exponent < 0 ? "-" : "+"
      magnitude = exponent < 0 ? 0 - exponent : exponent
      text = mantissa + "e" + sign + (magnitude < 10 ? "0" : "") + magnitude.to_s
    elsif decpt <= 0
      text = "0." + ("0" * (0 - decpt)) + digits
    elsif decpt >= count
      text = digits + ("0" * (decpt - count)) + ".0"
    else
      text = digits.slice(0, decpt) + "." + digits.slice(decpt, count - decpt)
    negative ? "-" + text : text

  # Round num/den (non-negative integers) half to even.
  -> .round_ratio(numerator, denominator)
    parts = numerator.divmod(denominator)
    quotient = parts[0]
    twice = parts[1] * 2
    quotient += 1 if twice > denominator || (twice == denominator && quotient % 2 == 1)
    quotient

  # '%.{places}f' % x, exact: the binary value rounded half to even.
  -> .fixed(number, places)
    x = Floatx.of(number)
    special = Floatx.special(x, "inf", "nan")
    return special if special != nil
    parts = Floatx.magnitude(x)
    f = parts[0]
    e = parts[1]
    scale = 10 ** places
    scaled = 0
    if e >= 0
      scaled = (f << e) * scale
    else
      scaled = Floatx.round_ratio(f * scale, 1 << (0 - e))
    text = scaled.to_s
    if places > 0
      text = ("0" * (places + 1 - text.size)) + text if text.size <= places
      text = text.slice(0, text.size - places) + "." + text.slice(text.size - places, places)
    Floatx.negative?(x) ? "-" + text : text

  # The first `count` significant digits of |x| (half-even) as [digits, exp10]
  # with |x| ~ D.DDD * 10^exp10. x must be finite and non-zero.
  -> .significant(x, count)
    parts = Floatx.magnitude(x)
    f = parts[0]
    e = parts[1]
    exp10 = Floatx.floor_div((f.bit_length + e - 1) * 30103, 100000)
    low = 10 ** (count - 1)
    high = low * 10
    while true
      shift = exp10 - count + 1
      numerator = f
      denominator = 1
      if e >= 0
        numerator = f << e
      else
        denominator = 1 << (0 - e)
      if shift >= 0
        denominator = denominator * (10 ** shift)
      else
        numerator = numerator * (10 ** (0 - shift))
      quotient = Floatx.round_ratio(numerator, denominator)
      if quotient >= high
        exp10 += 1
      elsif quotient < low
        exp10 -= 1
      else
        return [quotient.to_s, exp10]

  # '%.{precision}g' / format(x, 'g'): fixed for -4 <= exponent < precision,
  # otherwise exponent form, trailing zeros removed.
  -> .general(number, precision = 6)
    x = Floatx.of(number)
    special = Floatx.special(x, "inf", "nan")
    return special if special != nil
    negative = Floatx.negative?(x)
    return (negative ? "-0" : "0") if Floatx.zero?(x)
    p = precision == 0 ? 1 : precision
    parts = Floatx.significant(x, p)
    digits = parts[0]
    exp10 = parts[1]
    text = ""
    if exp10 < 0 - 4 || exp10 >= p
      mantissa = Floatx.strip_zeros(digits.slice(0, 1) + "." + digits.slice(1, p - 1))
      magnitude = exp10 < 0 ? 0 - exp10 : exp10
      text = mantissa + "e" + (exp10 < 0 ? "-" : "+") + (magnitude < 10 ? "0" : "") + magnitude.to_s
    elsif exp10 >= 0
      text = Floatx.strip_zeros(digits.slice(0, exp10 + 1) + "." + digits.slice(exp10 + 1, p - exp10 - 1))
    else
      text = Floatx.strip_zeros("0." + ("0" * (0 - exp10 - 1)) + digits)
    negative ? "-" + text : text

  # "12.500" -> "12.5", "3.000" -> "3", "100" -> "100" (no fraction: kept).
  -> .strip_zeros(text)
    return text if !text.include?(".")
    cut = text.size
    while cut > 0 && text.slice(cut - 1, 1) == "0"
      cut -= 1
    cut -= 1 if cut > 0 && text.slice(cut - 1, 1) == "."
    text.slice(0, cut)

  # f'{x:.{places}%}': the double x * 100, fixed, followed by '%'.
  -> .percent(number, places)
    x = Floatx.of(number)
    special = Floatx.special(x, "inf", "nan")
    return special + "%" if special != nil
    Floatx.fixed(x * Floatx.of(100), places) + "%"

  # Python round(x, places): the double nearest the half-even rounding of x.
  -> .round(number, places)
    x = Floatx.of(number)
    return x if Floatx.special(x, "inf", "nan") != nil
    Floatx.parse(Floatx.fixed(x, places))
