# Number and text formatting for the benchmark reports.
use stats

+ Format
  # Decimal digits of the integer n, zero padded to at least `width` digits.
  -> .padded(n, width)
    text = n.to_s
    while text.size < width
      text = "0" + text
    text

  # The low 32 bits of n as eight lowercase hexadecimal digits.
  -> .hex32(n) (i64)
    digits = "0123456789abcdef"
    out = ""
    shift = 28 ## i64
    while shift >= 0
      out = out + digits.slice((n >> shift) & 15, 1)
      shift -= 4
    out

  # a * b without overflow: a call boundary keeps the product a BigInt.
  -> .times(a, b)
    a * b

  # x with `decimals` digits after the point, rounded half away from zero on
  # the exact binary value of x.
  -> .fixed(x, decimals) (f64 i64)
    if x != x
      return "nan"
    if x == Stats.inf()
      return "inf"
    v = x ## f64
    negative = x < 0.0
    if negative
      v = 0.0 - x
    # v = m * 2^e with m an integer below 2^53
    e = 0 ## i64
    limit = (2 ** 53).to_f ## f64
    while v >= limit
      v = v / 2.0
      e += 1
    while v != Math.floor(v)
      v = v * 2.0
      e -= 1
    scaled = Format.times(v.to_i, 10 ** decimals)
    q = scaled
    if e > 0
      q = Format.times(scaled, 2 ** e)
    elsif e < 0
      unit = 2 ** (0 - e)
      q = scaled / unit
      if 2 * (scaled % unit) >= unit
        q = q + 1
    digits = Format.padded(q, decimals + 1)
    whole = digits.slice(0, digits.size - decimals)
    text = whole
    if decimals > 0
      text = whole + "." + digits.slice(digits.size - decimals, decimals)
    if negative && q != 0
      text = "-" + text
    text

  # x with at most `decimals` digits after the point: trailing zeros and a
  # dangling point are dropped.
  -> .trimmed(x, decimals) (f64 i64)
    text = Format.fixed(x, decimals)
    if !text.include?(".")
      return text
    while text.ends_with?("0")
      text = text.slice(0, text.size - 1)
    if text.ends_with?(".")
      text = text.slice(0, text.size - 1)
    text

  # An integer with `{,}` between groups of three digits, for LaTeX math mode.
  -> .thousands_tex(n) (i64)
    digits = n.to_s
    sign = ""
    if n < 0
      sign = "-"
      digits = digits.slice(1, digits.size - 1)
    out = ""
    i = 0 ## i64
    while i < digits.size
      if i > 0 && (digits.size - i) % 3 == 0
        out = out + "{,}"
      out = out + digits.slice(i, 1)
      i += 1
    sign + out

  # A cost with a precision that follows its magnitude: whole numbers from
  # 1000, one decimal from 100, two from 1, three below.
  -> .cost(x) (f64)
    if x != x
      return "nan"
    if x == Stats.inf()
      return "inf"
    if x >= 1000.0
      return Format.fixed(x, 0)
    if x >= 100.0
      return Format.fixed(x, 1)
    if x >= 1.0
      return Format.fixed(x, 2)
    Format.fixed(x, 3)
