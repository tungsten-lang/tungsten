# runtime/b_number — Number, Math and BigInt. (Ported from blade/js/b_number.w.)

in JS

-> js_this_num(v, what)
  return v if js_number?(v)
  return v.internal if js_special?(v, "Number") && js_number?(v.internal)
  js_throw_type("Number.prototype." + what + " requires that 'this' be a Number")

fn js_make_f64_bits(neg, bexp, fhi, flo) (i64 i64 i64 i64) i64
  ll <<~IR
    %s = shl i64 %neg, 63
    %e = shl i64 %bexp, 52
    %h = shl i64 %fhi, 30
    %t1 = or i64 %s, %e
    %t2 = or i64 %h, %flo
    %bits = or i64 %t1, %t2
    %r = add i64 %bits, 281474976710656
    ret i64 %r
  IR

JS_BI_POW1024 = (2 ## int) ** 1024

-> js_bigint_to_number(b)
  return ~0.0 if b == 0
  neg = b < 0
  a = neg ? 0 - b : b
  if a <= 1073741823
    f = a.to_f
    return neg ? ~0.0 - f : f
  if a <= 9007199254740991
    hi = (a / 1073741824).to_i
    lo = (a % 1073741824).to_i
    f = hi.to_f * ~1073741824.0 + lo.to_f
    return neg ? ~0.0 - f : f
  return neg ? NEG_INF : INF if a >= JS_BI_POW1024
  lo = 54
  hi = 1024
  while lo < hi
    mid = (lo + hi) / 2
    if a >= ((2 ## int) ** mid)
      lo = mid + 1
    else
      hi = mid
  bl = lo
  shift = bl - 53
  div = (2 ## int) ** shift
  m = a / div
  rem = a - m * div
  half = div / 2
  if rem > half || (rem == half && (m % 2) == 1)
    m = m + 1
  if m == 9007199254740992
    m = 4503599627370496
    shift += 1
  return neg ? NEG_INF : INF if shift > 971
  bexp = shift + 52 + 1023
  fhi = ((m / 1073741824).to_i) & 4194303
  flo = (m % 1073741824).to_i
  wvalue_from_bits(js_make_f64_bits(neg ? 1 : 0, bexp, fhi, flo))

-> js_number_ctor(args, nt)
  n = ~0.0
  if args.size > 0
    p = js_numeric_value(args[0])
    n = p.is_a?(JS:BigIntValue) ? js_bigint_to_number(p.v) : p
  return n if nt == nil
  o = js_new_special(js_realm().proto_from(nt, "Number"), "Number")
  o.internal = n
  o

JS_DIGITS36 = "0123456789abcdefghijklmnopqrstuvwxyz"

-> js_num_to_radix(x, radix)
  return js_number_to_s(x) if radix == 10
  return "NaN" if x != x
  return "Infinity" if x == INF
  return "-Infinity" if x == NEG_INF
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  ip = Math.floor(a)
  fp = a - ip
  ds = ""
  if ip == ~0.0
    ds = "0"
  elsif ip < ~9007199254740992.0
    i = ip.to_i
    while i > 0
      ds = JS_DIGITS36.slice(i % radix, 1) + ds
      i = i / radix
  else
    # large: repeated float division (exact enough for the leading digits)
    t = ip
    while t >= ~1.0
      d = (t - Math.floor(t / radix) * radix).to_i
      d = 0 if d < 0
      d = radix - 1 if d >= radix
      ds = JS_DIGITS36.slice(d, 1) + ds
      t = Math.floor(t / radix)
  # shortest fraction digits that round-trip (V8/JSC DoubleToRadixCString): stop once the
  # remainder is below half the distance to the next double, rounding the last digit
  if fp > ~0.0
    delta = ~0.5 * (js_next_up(a) - a)
    tiny = ~5.0e-324
    delta = tiny if delta < tiny
    if fp >= delta
      fd = []
      carry = false
      done = false
      while !done
        fp = fp * radix
        delta = delta * radix
        d = Math.floor(fp).to_i
        fd.push(d)
        fp = fp - d
        if fp > ~0.5 || (fp == ~0.5 && (d & 1) == 1)
          if fp + delta > ~1.0
            # round up, propagating the carry through the digits (and into the integer part)
            j = fd.size - 1
            while j >= 0 && fd[j] + 1 >= radix
              fd.pop
              j -= 1
            if j < 0
              carry = true
            else
              fd[j] = fd[j] + 1
            done = true
        done = true if fp < delta
      if carry
        return js_num_to_radix(neg ? ~0.0 - (ip + ~1.0) : ip + ~1.0, radix)
      if fd.size > 0
        ds = ds + "."
        q = 0
        while q < fd.size
          ds = ds + JS_DIGITS36.slice(fd[q], 1)
          q += 1
  neg ? "-" + ds : ds

-> js_num_to_string(this, rv)
  x = js_this_num(this, "toString")
  rr = rv == nil ? ~10.0 : js_to_integer(rv)
  js_throw_range("toString() radix must be between 2 and 36") if rr < ~2.0 || rr > ~36.0
  js_num_to_radix(x, rr.to_i)

# Decimal digits of |x| * 10^f rounded half-up, as an Integer (exact via BigInt for big values).
-> js_scaled_digits(a, f)
  v = a * (~10.0 ** f)
  if v < ~9.0e15
    r = v.round
    # correct the half-way cases the scaled float can't represent
    return r.to_i
  js_decimal_digits_of(a, f)

# Exact decimal expansion of a finite double, rounded at f fraction digits (half-up).
-> js_decimal_digits_of(a, f)
  m = a
  e = 0
  while m != Math.floor(m) && e < 1100
    m = m * ~2.0
    e += 1
  mi = js_float_to_bigint(m) ## int
  # value = mi / 2^e ; want round(value * 10^f) (f may be negative)
  num = mi
  den = (2 ## int) ** e
  if f >= 0
    num = mi * ((10 ## int) ** f)
  else
    den = den * ((10 ## int) ** (0 - f))
  q = num / den
  rem = num - q * den
  q += 1 if rem * 2 >= den
  q

-> js_float_to_bigint(x)
  # x is a non-negative integer-valued double; above 2^53 halving is exact
  k = 0
  t = x
  while t >= ~9007199254740992.0
    t = t / ~2.0
    k += 1
  # below 2^53 the two 32-bit halves convert exactly
  hi = Math.floor(t / ~4294967296.0)
  lo = t - hi * ~4294967296.0
  ((hi.to_i ## int) * (4294967296 ## int) + (lo.to_i ## int)) * ((2 ## int) ** k)

-> js_num_to_fixed(this, fd)
  x = js_this_num(this, "toFixed")
  f = js_to_integer(fd)
  js_throw_range("toFixed() digits argument must be between 0 and 100") if f < ~0.0 || f > ~100.0
  return js_number_to_s(x) if x != x || x.abs >= ~1.0e21
  fi = f.to_i
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  n = js_decimal_digits_of(a, fi)
  s = n.to_s
  if fi > 0
    while s.size <= fi
      s = "0" + s
    s = s.slice(0, s.size - fi) + "." + s.slice(s.size - fi, fi)
  neg ? "-" + s : s

-> js_num_to_precision(this, pv)
  x = js_this_num(this, "toPrecision")
  return js_number_to_s(x) if pv == nil
  p = js_to_integer(pv)
  return js_number_to_s(x) if x != x || x == INF || x == NEG_INF
  js_throw_range("toPrecision() argument must be between 1 and 100") if p < ~1.0 || p > ~100.0
  pi = p.to_i
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  if a == ~0.0
    s = "0"
    s = s + "." + "0" * (pi - 1) if pi > 1
    return s
  e = Math.floor(Math.log10(a)).to_i
  n = js_round_sig(a, pi, e)
  ds = n[0]
  e = n[1]
  if e < -6 || e >= pi
    m = ds.slice(0, 1)
    m = m + "." + ds.slice(1, ds.size - 1) if pi > 1
    out = m + "e" + (e < 0 ? "-" : "+") + e.abs.to_s
    return neg ? "-" + out : out
  if e >= 0
    out = ds.slice(0, e + 1)
    out = out + "." + ds.slice(e + 1, pi - e - 1) if pi > e + 1
  else
    out = "0." + "0" * (0 - e - 1) + ds
  neg ? "-" + out : out

# p significant digits of a (> 0) whose decimal exponent is about e: [digit string, exponent].
-> js_round_sig(a, p, e)
  # Refine decimal exponent e exactly using BigInt so boundary values like 1e-21 (< 10^-21) get exact e=-22.
  m = a
  eb = 0
  while m != Math.floor(m) && eb < 1100
    m = m * ~2.0
    eb += 1
  mi = js_float_to_bigint(m) ## int
  den = (2 ## int) ** eb
  # Adjust e so 10^e <= mi / den < 10^(e + 1)
  while true
    if e >= 0
      lo_ok = mi >= den * ((10 ## int) ** e)
      hi_ok = mi < den * ((10 ## int) ** (e + 1))
    else
      lo_ok = mi * ((10 ## int) ** (0 - e)) >= den
      hi_ok = e == -1 ? (mi < den) : (mi * ((10 ## int) ** (0 - e - 1)) < den)
    if !lo_ok
      e -= 1
    elsif !hi_ok
      e += 1
    else
      break
  fdig = p - 1 - e
  n = js_decimal_digits_of(a, fdig)
  s = n.to_s
  if s.size > p
    e += 1
    fdig = p - 1 - e
    n = js_decimal_digits_of(a, fdig)
    s = n.to_s
  if s.size < p
    e -= 1
    fdig = p - 1 - e
    n = js_decimal_digits_of(a, fdig)
    s = n.to_s
  [s, e]

-> js_num_to_exponential(this, fv)
  x = js_this_num(this, "toExponential")
  f = js_to_integer(fv)
  return js_number_to_s(x) if x != x || x == INF || x == NEG_INF
  js_throw_range("toExponential() argument must be between 0 and 100") if f < ~0.0 || f > ~100.0
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  if fv == nil
    return (neg ? "-" : "") + "0e+0" if a == ~0.0
    s = js_number_to_s(a)
    # shortest digits, exponent form
    e = a == ~0.0 ? 0 : Math.floor(Math.log10(a)).to_i
    ds = js_shortest_digits(a)
    m = ds.slice(0, 1)
    m = m + "." + ds.slice(1, ds.size - 1) if ds.size > 1
    e = js_exp_of(a, ds)
    out = m + "e" + (e < 0 ? "-" : "+") + e.abs.to_s
    return neg ? "-" + out : out
  fi = f.to_i
  if a == ~0.0
    m = "0"
    m = m + "." + "0" * fi if fi > 0
    return (neg ? "-" : "") + m + "e+0"
  e = Math.floor(Math.log10(a)).to_i
  n = js_round_sig(a, fi + 1, e)
  ds = n[0]
  e = n[1]
  m = ds.slice(0, 1)
  m = m + "." + ds.slice(1, ds.size - 1) if fi > 0
  out = m + "e" + (e < 0 ? "-" : "+") + e.abs.to_s
  neg ? "-" + out : out

-> js_shortest_digits(a)
  s = js_number_to_s(a)
  e = s.index("e")
  s = s.slice(0, e) if e != nil
  s = s.sub(".", "")
  while s.size > 1 && s.byte_at(0) == 48
    s = s.slice(1, s.size - 1)
  while s.size > 1 && s.ends_with?("0")
    s = s.slice(0, s.size - 1)
  s

-> js_exp_of(a, ds)
  e = Math.floor(Math.log10(a)).to_i
  # adjust for log10 rounding at powers of ten
  e += 1 if (~10.0 ** (e + 1)) <= a
  e -= 1 if (~10.0 ** e) > a
  e

-> js_num_to_locale(this, args)
  x = js_this_num(this, "toLocaleString")
  js_format_grouped(x, 0, 3)

# Grouped decimal with between min and max fraction digits (en-US).
-> js_format_grouped(x, minf, maxf)
  return "NaN" if x != x
  return "∞" if x == INF
  return "-∞" if x == NEG_INF
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  n = js_decimal_digits_of(a, maxf)
  s = n.to_s
  while s.size <= maxf
    s = "0" + s
  ip = s.slice(0, s.size - maxf)
  fp = s.slice(s.size - maxf, maxf)
  while fp.size > minf && fp.ends_with?("0")
    fp = fp.slice(0, fp.size - 1)
  g = ""
  while ip.size > 3
    g = "," + ip.slice(ip.size - 3, 3) + g
    ip = ip.slice(0, ip.size - 3)
  g = ip + g
  out = fp.size > 0 ? g + "." + fp : g
  (neg && n != 0) ? "-" + out : out

-> js_is_integer?(v)
  js_number?(v) && v == v && v != INF && v != NEG_INF && v == Math.floor(v)

# ---- Math ----

# TODO(js-aot): per thread once workers run JS.
JS_RNG = [0, 0]

# Two xorshift32 generators (every intermediate stays below 2^45: Tungsten integers past
# 47 bits become BigInts, and the old 64-bit xorshift128+ here grew its state by 23 bits
# per call — a page calling Math.random in a loop ran out of memory).
-> js_math_random
  s = JS_RNG
  if s[0] == 0 || s[1] == 0
    b = Random.bytes(8)
    s[0] = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) | 1
    s[1] = ((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]) | 2
  s[0] = js_xorshift32(s[0])
  s[1] = js_xorshift32(s[1])
  # 26 + 27 bits → a double in [0, 1)
  ((s[0] >> 6).to_f * ~134217728.0 + (s[1] >> 5).to_f) / ~9007199254740992.0

-> js_xorshift32(x)
  x = x ^ ((x << 13) & 4294967295)
  x = x ^ (x >> 17)
  x ^ ((x << 5) & 4294967295)

-> js_math_round(x)
  return x if x != x || x == INF || x == NEG_INF
  return x if x == Math.floor(x)
  f = Math.floor(x)
  # (x + 0.5 would round up for the largest double below 0.5)
  f = f + ~1.0 if x - f >= ~0.5
  return ~-0.0 if f == ~0.0 && x < ~0.0
  f

-> js_math_trunc(x)
  return x if x != x || x == INF || x == NEG_INF
  x < ~0.0 ? Math.ceil(x) : Math.floor(x)

-> js_math_sign(x)
  return x if x != x || x == ~0.0
  x > ~0.0 ? ~1.0 : ~-1.0

-> js_math_minmax(args, is_max)
  r = is_max ? NEG_INF : INF
  nan = false
  i = 0
  while i < args.size
    v = args[i]
    v = js_to_number(v) if !js_number?(v)
    if v != v
      nan = true
    elsif is_max
      r = v if v > r || (v == ~0.0 && r == ~0.0 && (~1.0 / r) < ~0.0)
    else
      r = v if v < r || (v == ~0.0 && r == ~0.0 && (~1.0 / v) < ~0.0)
    i += 1
  nan ? js_nan() : r

-> js_math_hypot(args)
  s = ~0.0
  inf = false
  nan = false
  vals = []
  i = 0
  while i < args.size
    vals.push(js_to_number(args[i]))
    i += 1
  i = 0
  while i < vals.size
    v = vals[i]
    inf = true if v == INF || v == NEG_INF
    nan = true if v != v
    s = s + v * v
    i += 1
  return INF if inf
  return js_nan() if nan
  Math.sqrt(s)

-> js_math_clz32(x)
  n = js_u32(x)
  return ~32.0 if n == 0
  c = 0
  while (n & 2147483648) == 0
    n = n << 1
    c += 1
  c + ~0.0

-> js_math_imul(a, b)
  x = js_i32(a)
  y = js_i32(b)
  js_f(js_wrap32((x * y) & 4294967295))

-> js_fround(x) (f64) f64
  y = x ## f32
  y ## f64

-> js_math_f16round(x)
  js_f16_from_bits(js_f16_bits(x))

# Exact Math.sumPrecise(items) via exact arbitrary-precision dyadic integer sum + IEEE-754 RNE.
-> js_math_sum_precise(items)
  js_throw_type("Math.sumPrecise requires an object iterable") if !js_object?(items)
  rec = js_get_iterator(items)
  state = :mzero
  acc = 0 ## int
  min_sh = 0
  has_acc = false
  begin
    while true
      v = js_iter_step(rec)
      break if v == JS_ITER_DONE
      js_throw_type("Math.sumPrecise element is not a Number") if !js_number?(v)
      if v != v
        state = :nan
      elsif v == INF
        state = (state == :ninf || state == :nan) ? :nan : :pinf
      elsif v == NEG_INF
        state = (state == :pinf || state == :nan) ? :nan : :ninf
      elsif v == ~0.0
        state = :finite if state == :mzero && (~1.0 / v) > ~0.0
      else
        state = :finite if state == :mzero
        if state == :finite
          lo = js_f64_lo(v)
          hi = js_f64_hi(v)
          neg = ((hi >> 31) & 1) != 0
          exp = (hi >> 20) & 2047
          fhi = hi & 1048575
          if exp == 0
            mant = (fhi ## int) * (4294967296 ## int) + (lo ## int)
            sh = -1074
          else
            mant = ((1048576 + fhi) ## int) * (4294967296 ## int) + (lo ## int)
            sh = exp - 1075
          mant = 0 - mant if neg
          if !has_acc
            acc = mant
            min_sh = sh
            has_acc = true
          elsif sh == min_sh
            acc = acc + mant
          elsif sh > min_sh
            acc = acc + mant * ((2 ## int) ** (sh - min_sh))
          else
            acc = acc * ((2 ## int) ** (min_sh - sh)) + mant
            min_sh = sh
  rescue ex
    js_iter_close_quiet(rec) if !rec.done
    raise ex
  return ~-0.0 if state == :mzero
  return js_nan() if state == :nan
  return INF if state == :pinf
  return NEG_INF if state == :ninf
  return ~0.0 if !has_acc || acc == 0
  js_dyadic_to_number(acc, min_sh)

# Exact IEEE-754 double rounding (round-to-nearest-even) of non-zero dyadic integer a * 2^sh.
-> js_dyadic_to_number(a, sh)
  neg = a < 0
  mag = neg ? (0 - a) : a
  # Find bit length bl such that 2^(bl-1) <= mag < 2^bl
  bl = 1
  hi_b = 64
  while mag >= ((2 ## int) ** hi_b)
    hi_b = hi_b * 2
  lo_b = 1
  while lo_b < hi_b
    mid = (lo_b + hi_b) / 2
    if mag >= ((2 ## int) ** mid)
      lo_b = mid + 1
    else
      hi_b = mid
  bl = lo_b
  # Value is in [2^(bl-1+sh), 2^(bl+sh)); unbiased exponent e = bl - 1 + sh.
  e = bl - 1 + sh
  return neg ? NEG_INF : INF if e > 1023
  if e >= -1022
    # Normal: want 53 significant bits -> shift right by rsh = bl - 53
    rsh = bl - 53
    if rsh <= 0
      m = mag * ((2 ## int) ** (0 - rsh))
    else
      div = (2 ## int) ** rsh
      m = mag / div
      rem = mag - m * div
      half = div / 2
      m = m + 1 if rem > half || (rem == half && (m % 2) == 1)
      if m == 9007199254740992
        m = 4503599627370496
        e += 1
        return neg ? NEG_INF : INF if e > 1023
    bexp = e + 1023
    fhi = ((m / 1073741824).to_i) & 4194303
    flo = (m % 1073741824).to_i
    return wvalue_from_bits(js_make_f64_bits(neg ? 1 : 0, bexp, fhi, flo))
  # Subnormal or underflow: scale to units of 2^-1074 -> shift = sh + 1074
  # Value = mag * 2^(sh + 1074) * 2^-1074
  rsh = -1074 - sh
  if rsh <= 0
    m = mag * ((2 ## int) ** (0 - rsh))
  elsif rsh > bl + 1
    return neg ? ~-0.0 : ~0.0
  else
    div = (2 ## int) ** rsh
    m = mag / div
    rem = mag - m * div
    half = div / 2
    m = m + 1 if rem > half || (rem == half && (m % 2) == 1)
  return neg ? ~-0.0 : ~0.0 if m == 0
  if m >= 4503599627370496
    # Rounded up to smallest normal 2^-1022
    return wvalue_from_bits(js_make_f64_bits(neg ? 1 : 0, 1, 0, 0))
  fhi = ((m / 1073741824).to_i) & 4194303
  flo = (m % 1073741824).to_i
  wvalue_from_bits(js_make_f64_bits(neg ? 1 : 0, 0, fhi, flo))

-> js_math1(name, x)
  case name
  when "abs"
    x < ~0.0 ? ~0.0 - x : (x == ~0.0 ? ~0.0 : x)
  when "acos"
    (x > ~1.0 || x < ~-1.0) ? js_nan() : Math.atan2(Math.sqrt(~1.0 - x * x), x)
  when "acosh"
    x < ~1.0 ? js_nan() : (x >= ~1.0e8 ? Math.log(x) + ~0.6931471805599453 : Math.log1p((x - ~1.0) + Math.sqrt((x - ~1.0) * (x + ~1.0))))
  when "asin"
    (x > ~1.0 || x < ~-1.0) ? js_nan() : Math.atan2(x, Math.sqrt(~1.0 - x * x))
  when "asinh"
    x == ~0.0 ? x : Math.asinh(x)
  when "atan"
    x == ~0.0 ? x : Math.atan2(x, ~1.0)
  when "atanh"
    js_math_atanh(x)
  when "cbrt"
    Math.cbrt(x)
  when "ceil"
    (x != x || x == INF || x == NEG_INF) ? x : js_ceil(x)
  when "cos"
    Math.cos(x)
  when "cosh"
    Math.cosh(x)
  when "exp"
    Math.exp(x)
  when "expm1"
    x == ~0.0 ? x : Math.expm1(x)
  when "floor"
    (x != x || x == INF || x == NEG_INF) ? x : Math.floor(x)
  when "fround"
    js_fround(x)
  when "log"
    x < ~0.0 ? js_nan() : Math.log(x)
  when "log1p"
    x < ~-1.0 ? js_nan() : (x == ~0.0 ? x : Math.log1p(x))
  when "log10"
    x < ~0.0 ? js_nan() : js_log10(x)
  when "log2"
    x < ~0.0 ? js_nan() : Math.log2(x)
  when "round"
    js_math_round(x)
  when "sign"
    js_math_sign(x)
  when "sin"
    x == ~0.0 ? x : Math.sin(x)
  when "sinh"
    js_math_sinh(x)
  when "sqrt"
    x < ~0.0 ? js_nan() : Math.sqrt(x)
  when "tan"
    x == ~0.0 ? x : Math.tan(x)
  when "tanh"
    js_math_tanh(x)
  when "trunc"
    js_math_trunc(x)
  else
    js_nan()

-> js_math_atanh(x)
  return js_nan() if x != x || x < ~-1.0 || x > ~1.0
  return x if x == ~0.0
  return INF if x == ~1.0
  return NEG_INF if x == ~-1.0
  ax = x < ~0.0 ? ~0.0 - x : x
  r = ax < ~0.5 ? ~0.5 * Math.log1p(~2.0 * ax + ~2.0 * ax * ax / (~1.0 - ax)) : ~0.5 * Math.log1p(~2.0 * ax / (~1.0 - ax))
  x < ~0.0 ? ~0.0 - r : r

-> js_math_sinh(x)
  return x if x != x || x == ~0.0 || x == INF || x == NEG_INF
  ax = x < ~0.0 ? ~0.0 - x : x
  if ax < ~22.0
    t = Math.expm1(ax)
    r = ax < ~1.0 ? ~0.5 * (~2.0 * t - t * t / (t + ~1.0)) : ~0.5 * (t + t / (t + ~1.0))
  elsif ax < ~709.782712893384
    r = ~0.5 * Math.exp(ax)
  else
    w = Math.exp(~0.5 * ax)
    r = ~0.5 * w * w
  x < ~0.0 ? ~0.0 - r : r

-> js_math_tanh(x)
  return x if x != x || x == ~0.0
  return ~1.0 if x == INF
  return ~-1.0 if x == NEG_INF
  ax = x < ~0.0 ? ~0.0 - x : x
  if ax < ~22.0
    if ax < ~1.0
      t = Math.expm1(~-2.0 * ax)
      r = (~0.0 - t) / (t + ~2.0)
    else
      t = Math.expm1(~2.0 * ax)
      r = ~1.0 - ~2.0 / (t + ~2.0)
  else
    r = ~1.0
  x < ~0.0 ? ~0.0 - r : r

# log10, exact at powers of ten.
-> js_log10(x)
  r = Math.log10(x)
  return r if r != r || r == INF || r == NEG_INF
  k = Math.round(r)
  return k if (k - r).abs < ~1.0e-9 && (~10.0 ** k) == x
  r

-> js_ceil(x)
  c = Math.ceil(x)
  return ~-0.0 if c == ~0.0 && x < ~0.0
  c

# ---- BigInt ----

-> js_bigint_ctor(args, nt)
  js_throw_type("BigInt is not a constructor") if nt != nil
  js_to_bigint_from(js_arg(args, 0), true)

-> js_to_bigint_from(v, from_number)
  p = js_to_primitive(v, "number")
  if js_number?(p)
    js_throw_type("Cannot convert " + js_number_to_s(p) + " to a BigInt") if !from_number
    js_throw_range("The number " + js_number_to_s(p) + " cannot be converted to a BigInt because it is not an integer") if !js_is_integer?(p)
    return JS:BigIntValue.new(js_float_to_bigint(p.abs) * (p < ~0.0 ? -1 : 1))
  return p if p.is_a?(JS:BigIntValue)
  return JS:BigIntValue.new(p ? 1 : 0) if p == true || p == false
  if js_string?(p)
    v2 = js_string_to_bigint(p)
    js_throw_syntax("Cannot convert " + p + " to a BigInt") if v2 == nil
    return JS:BigIntValue.new(v2)
  js_throw_type("Cannot convert " + js_err_display(p) + " to a BigInt")

-> js_this_bigint(v)
  return v if v.is_a?(JS:BigIntValue)
  return v.internal if js_internal(v).is_a?(JS:BigIntValue)
  js_throw_type("BigInt.prototype.valueOf requires that 'this' be a BigInt")

-> js_bigint_to_string(v, rv)
  b = js_this_bigint(v)
  rr = rv == nil ? ~10.0 : js_to_integer(rv)
  js_throw_range("toString() radix must be between 2 and 36") if rr < ~2.0 || rr > ~36.0
  radix = rr.to_i
  return b.v.to_s if radix == 10
  n = b.v
  neg = n < 0
  n = 0 - n if neg
  return "0" if n == 0
  s = ""
  while n > 0
    s = JS_DIGITS36.slice((n % radix).to_i, 1) + s
    n = n / radix
  neg ? "-" + s : s

-> js_bigint_as(bits_v, bv, signed)
  bits = js_to_index(bits_v)
  b = js_to_bigint_from(bv, false).v
  return JS:BigIntValue.new(0) if bits == 0
  if bits > 4096
    if b >= 0 && b.to_s.size * 4 < bits - 1
      return JS:BigIntValue.new(b)
    if b < 0 && signed && (0 - b).to_s.size * 4 < bits - 1
      return JS:BigIntValue.new(b)
    js_throw_range("Maximum BigInt size exceeded") if bits > 1000000
  m = (2 ## int) ** bits
  r = b % m
  r = r + m if r < 0
  if signed && r >= (2 ## int) ** (bits - 1)
    r = r - m
  JS:BigIntValue.new(r)

-> js_to_index(v)
  return 0 if v == nil
  n = js_to_integer(v)
  js_throw_range("Invalid index") if n < ~0.0 || n > ~9007199254740991.0
  n.to_i

js_install(->(r) js_install_number(r))

-> js_install_number(r)
  np = js_new_special(r.object_proto, "Number")
  np.internal = ~0.0
  nc = r.constructor("Number", 1, ->(this, args, nt) js_number_ctor(args, nt), np)
  r.constant(nc, "MAX_SAFE_INTEGER", ~9007199254740991.0)
  r.constant(nc, "MIN_SAFE_INTEGER", ~-9007199254740991.0)
  r.constant(nc, "EPSILON", ~2.220446049250313e-16)
  r.constant(nc, "MAX_VALUE", ~1.7976931348623157e308)
  r.constant(nc, "MIN_VALUE", ~5.0e-324)
  r.constant(nc, "NaN", js_nan())
  r.constant(nc, "POSITIVE_INFINITY", INF)
  r.constant(nc, "NEGATIVE_INFINITY", NEG_INF)
  r.method(nc, "isInteger", 1, ->(this, args, nt) js_is_integer?(js_arg(args, 0)))
  r.method(nc, "isSafeInteger", 1, ->(this, args, nt) js_is_integer?(js_arg(args, 0)) && js_arg(args, 0).abs <= ~9007199254740991.0)
  r.method(nc, "isFinite", 1, ->(this, args, nt) js_number?(js_arg(args, 0)) && js_finite?(js_arg(args, 0)))
  r.method(nc, "isNaN", 1, ->(this, args, nt) js_is_nan?(js_arg(args, 0)))
  g = r.global
  nc.define("parseFloat", g.get_own("parseFloat"), BUILTIN_ATTRS)
  nc.define("parseInt", g.get_own("parseInt"), BUILTIN_ATTRS)
  r.method(np, "toString", 1, ->(this, args, nt) js_num_to_string(this, js_arg(args, 0)))
  r.method(np, "toFixed", 1, ->(this, args, nt) js_num_to_fixed(this, js_arg(args, 0)))
  r.method(np, "toPrecision", 1, ->(this, args, nt) js_num_to_precision(this, js_arg(args, 0)))
  r.method(np, "toExponential", 1, ->(this, args, nt) js_num_to_exponential(this, js_arg(args, 0)))
  r.method(np, "toLocaleString", 0, ->(this, args, nt) js_num_to_locale(this, args))
  r.method(np, "valueOf", 0, ->(this, args, nt) js_this_num(this, "valueOf"))
  # Math
  m = js_new_object(r.object_proto)
  g.define("Math", m, BUILTIN_ATTRS)
  m.define(SYM_TO_STRING_TAG, "Math", ATTR_C)
  r.constant(m, "E", ~2.718281828459045)
  r.constant(m, "LN10", ~2.302585092994046)
  r.constant(m, "LN2", ~0.6931471805599453)
  r.constant(m, "LOG10E", ~0.4342944819032518)
  r.constant(m, "LOG2E", ~1.4426950408889634)
  r.constant(m, "PI", ~3.141592653589793)
  r.constant(m, "SQRT1_2", ~0.7071067811865476)
  r.constant(m, "SQRT2", ~1.4142135623730951)
  names = ["acos", "acosh", "asin", "asinh", "atan", "atanh", "cbrt", "cos", "cosh", "exp", "expm1", "fround", "log", "log1p", "log10", "log2", "sign", "sin", "sinh", "tan", "tanh"]
  i = 0
  while i < names.size
    js_install_math1(r, m, names[i])
    i += 1
  # the common ones without the dispatch on the name
  r.method(m, "abs", 1, ->(this, args, nt) js_math_abs(js_num_arg(args)))
  r.method(m, "ceil", 1, ->(this, args, nt) js_math_ceil(js_num_arg(args)))
  r.method(m, "floor", 1, ->(this, args, nt) Math.floor(js_num_arg(args)))
  r.method(m, "round", 1, ->(this, args, nt) js_math_round(js_num_arg(args)))
  r.method(m, "sqrt", 1, ->(this, args, nt) js_math_sqrt(js_num_arg(args)))
  r.method(m, "trunc", 1, ->(this, args, nt) js_math_trunc(js_num_arg(args)))
  r.method(m, "atan2", 2, ->(this, args, nt) Math.atan2(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  r.method(m, "pow", 2, ->(this, args, nt) js_pow(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  r.method(m, "max", 2, ->(this, args, nt) js_math_minmax(args, true))
  r.method(m, "min", 2, ->(this, args, nt) js_math_minmax(args, false))
  r.method(m, "hypot", 2, ->(this, args, nt) js_math_hypot(args))
  r.method(m, "random", 0, ->(this, args, nt) js_math_random())
  r.method(m, "clz32", 1, ->(this, args, nt) js_math_clz32(js_to_number(js_arg(args, 0))))
  r.method(m, "imul", 2, ->(this, args, nt) js_math_imul(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  r.method(m, "f16round", 1, ->(this, args, nt) js_math_f16round(js_to_number(js_arg(args, 0))))
  r.method(m, "sumPrecise", 1, ->(this, args, nt) js_math_sum_precise(js_arg(args, 0)))
  # BigInt
  bp = js_new_object(r.object_proto)
  bc = r.constructor("BigInt", 1, ->(this, args, nt) js_bigint_ctor(args, nt), bp)
  r.method(bc, "asUintN", 2, ->(this, args, nt) js_bigint_as(js_arg(args, 0), js_arg(args, 1), false))
  r.method(bc, "asIntN", 2, ->(this, args, nt) js_bigint_as(js_arg(args, 0), js_arg(args, 1), true))
  r.method(bp, "toString", 0, ->(this, args, nt) js_bigint_to_string(this, js_arg(args, 0)))
  r.method(bp, "toLocaleString", 0, ->(this, args, nt) js_bigint_to_string(this, nil))
  r.method(bp, "valueOf", 0, ->(this, args, nt) js_this_bigint(this))
  bp.define(SYM_TO_STRING_TAG, "BigInt", ATTR_C)
  nil

-> js_install_math1(r, m, nm)
  r.method(m, nm, 1, ->(this, args, nt) js_math1(nm, js_to_number(js_arg(args, 0))))

# The first argument as a number (a native's fast path when it already is one).
-> js_num_arg(args)
  x = args.size > 0 ? args[0] : nil
  return x if js_number?(x)
  js_to_number(x)

-> js_math_abs(x)
  x < ~0.0 ? ~0.0 - x : (x == ~0.0 ? ~0.0 : x)

-> js_math_ceil(x)
  (x != x || x == INF || x == NEG_INF) ? x : js_ceil(x)

-> js_math_sqrt(x)
  x < ~0.0 ? js_nan() : Math.sqrt(x)

# The next double above a positive finite number.
fn jsr_fnext_up(a) (i64) i64
  ll <<~IR
    %r = add i64 %a, 1
    ret i64 %r
  IR

-> js_next_up(a)
  wvalue_from_bits(jsr_fnext_up(wvalue_bits(a) ## i64))

-> js_string_to_bigint(s)
  t = js_trim(s)
  return 0 if t.size == 0
  neg = false
  signed = false
  if t.byte_at(0) == 45 || t.byte_at(0) == 43
    neg = t.byte_at(0) == 45
    signed = true
    t = t.slice(1, t.size - 1)
  return nil if t.size == 0
  radix = 10
  if t.size > 2 && t.byte_at(0) == 48 && (t.byte_at(1) | 32) == 120
    radix = 16
    t = t.slice(2, t.size - 2)
  elsif t.size > 2 && t.byte_at(0) == 48 && (t.byte_at(1) | 32) == 111
    radix = 8
    t = t.slice(2, t.size - 2)
  elsif t.size > 2 && t.byte_at(0) == 48 && (t.byte_at(1) | 32) == 98
    radix = 2
    t = t.slice(2, t.size - 2)
  return nil if signed && radix != 10
  v = 0 ## int
  i = 0
  while i < t.size
    d = js_digit(t.byte_at(i))
    return nil if d < 0 || d >= radix
    v = v * radix + d
    i += 1
  neg ? 0 - v : v
