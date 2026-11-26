# blade/js/b_number — Number, Math and BigInt.

-> js_this_num(v, what)
  return v if v.is_a?(Float)
  return v.internal if v.is_a?(JsObject) && v.cls == "Number" && v.internal.is_a?(Float)
  js_throw_type("Number.prototype." + what + " requires that 'this' be a Number")

-> js_number_ctor(args, nt)
  n = ~0.0
  if args.size > 0
    p = js_numeric_value(args[0])
    n = p.is_a?(JsBigInt) ? p.v + ~0.0 : p
  return n if nt == nil
  o = JsObject.new(JS_REALM[0].proto_from(nt, "Number"), "Number")
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
    delta = ~0.5 * (js_float_from_bits(a.js_bits + 1) - a)
    tiny = js_float_from_bits(1)
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
  radix = rv == nil ? 10 : js_to_integer(rv).to_i
  raise JsThrow.new(js_range_error("toString() radix must be between 2 and 36")) if radix < 2 || radix > 36
  js_num_to_radix(x, radix)

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
  # value = mi / 2^e ; want round(value * 10^f)
  num = mi * ((10 ## int) ** f)
  den = 2 ** e
  q = num / den
  rem = num - q * den
  q += 1 if rem * 2 >= den
  q

-> js_float_to_bigint(x)
  return x.to_i if x < ~9.0e15
  # x is an integer-valued double; peel off 2^k factors exactly
  k = 0
  t = x
  while t >= ~9.0e15
    t = t / ~2.0
    k += 1
  (Math.floor(t).to_i ## int) * (2 ** k)

-> js_num_to_fixed(this, fd)
  x = js_this_num(this, "toFixed")
  f = js_to_integer(fd)
  raise JsThrow.new(js_range_error("toFixed() digits argument must be between 0 and 100")) if f < ~0.0 || f > ~100.0
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
  (neg && (n != 0)) ? "-" + s : s

-> js_num_to_precision(this, pv)
  x = js_this_num(this, "toPrecision")
  return js_number_to_s(x) if pv == nil
  p = js_to_integer(pv)
  return js_number_to_s(x) if x != x || x == INF || x == NEG_INF
  raise JsThrow.new(js_range_error("toPrecision() argument must be between 1 and 100")) if p < ~1.0 || p > ~100.0
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
  fdig = p - 1 - e
  n = fdig >= 0 ? js_decimal_digits_of(a, fdig) : js_decimal_digits_of(a / (~10.0 ** (0 - fdig)), 0)
  s = n.to_s
  if s.size > p
    e += 1
    fdig = p - 1 - e
    n = fdig >= 0 ? js_decimal_digits_of(a, fdig) : js_decimal_digits_of(a / (~10.0 ** (0 - fdig)), 0)
    s = n.to_s
  if s.size < p
    e -= 1
    fdig = p - 1 - e
    n = fdig >= 0 ? js_decimal_digits_of(a, fdig) : js_decimal_digits_of(a / (~10.0 ** (0 - fdig)), 0)
    s = n.to_s
  [s, e]

-> js_num_to_exponential(this, fv)
  x = js_this_num(this, "toExponential")
  f = js_to_integer(fv)
  return js_number_to_s(x) if x != x || x == INF || x == NEG_INF
  raise JsThrow.new(js_range_error("toExponential() argument must be between 0 and 100")) if f < ~0.0 || f > ~100.0
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  if fv == nil
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
  v.is_a?(Float) && v == v && v != INF && v != NEG_INF && v == Math.floor(v)

# ---- Math ----

JS_RNG = JsTlsCell.new(2, 0)

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
  x = x ^ ((x << 13) & 0xFFFFFFFF)
  x = x ^ (x >> 17)
  x ^ ((x << 5) & 0xFFFFFFFF)

-> js_math_round(x)
  return x if x != x || x == INF || x == NEG_INF
  return x if x == Math.floor(x)
  f = Math.floor(x + ~0.5)
  return ~-0.0 if f == ~0.0 && x < ~0.0
  f

-> js_math_trunc(x)
  return x if x != x || x == INF || x == NEG_INF
  x < ~0.0 ? (~0.0 - Math.floor(~0.0 - x)) : Math.floor(x)

-> js_math_sign(x)
  return x if x != x || x == ~0.0
  x > ~0.0 ? ~1.0 : ~-1.0

-> js_math_minmax(args, is_max)
  r = is_max ? NEG_INF : INF
  nan = false
  args.each ->(a)
    v = js_to_number(a)
    if v != v
      nan = true
    elsif is_max
      r = v if v > r || (v == ~0.0 && r == ~0.0 && (~1.0 / r) < ~0.0)
    else
      r = v if v < r || (v == ~0.0 && r == ~0.0 && (~1.0 / v) < ~0.0)
  nan ? js_nan() : r

-> js_math_hypot(args)
  s = ~0.0
  inf = false
  nan = false
  args.each ->(a)
    v = js_to_number(a)
    inf = true if v == INF || v == NEG_INF
    nan = true if v != v
    s = s + v * v
  return INF if inf
  return js_nan() if nan
  Math.sqrt(s)

-> js_math_clz32(x)
  n = js_u32(x)
  return ~32.0 if n == 0
  c = 0
  while (n & 0x80000000) == 0
    n = n << 1
    c += 1
  c + ~0.0

-> js_math_imul(a, b)
  x = js_i32(a)
  y = js_i32(b)
  js_f(js_wrap32((x * y) & 0xFFFFFFFF))

-> js_fround(x) (f64) f64
  y = x ## f32
  y ## f64

-> js_math1(name, x)
  case name
  when "abs"
    x < ~0.0 ? ~0.0 - x : (x == ~0.0 ? ~0.0 : x)
  when "acos"
    (x > ~1.0 || x < ~-1.0) ? js_nan() : Math.atan2(Math.sqrt(~1.0 - x * x), x)
  when "acosh"
    x < ~1.0 ? js_nan() : Math.log(x + Math.sqrt(x * x - ~1.0))
  when "asin"
    (x > ~1.0 || x < ~-1.0) ? js_nan() : Math.atan2(x, Math.sqrt(~1.0 - x * x))
  when "asinh"
    x == ~0.0 ? x : Math.asinh(x)
  when "atan"
    x == ~0.0 ? x : Math.atan2(x, ~1.0)
  when "atanh"
    x == ~0.0 ? x : Math.atanh(x)
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
    x < ~0.0 ? js_nan() : Math.log10(x)
  when "log2"
    x < ~0.0 ? js_nan() : Math.log2(x)
  when "round"
    js_math_round(x)
  when "sign"
    js_math_sign(x)
  when "sin"
    x == ~0.0 ? x : Math.sin(x)
  when "sinh"
    x == ~0.0 ? x : Math.sinh(x)
  when "sqrt"
    x < ~0.0 ? js_nan() : Math.sqrt(x)
  when "tan"
    x == ~0.0 ? x : Math.tan(x)
  when "tanh"
    x == ~0.0 ? x : Math.tanh(x)
  when "trunc"
    js_math_trunc(x)
  else
    js_nan()

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
  if p.is_a?(Float)
    js_throw_type("Cannot convert " + js_number_to_s(p) + " to a BigInt") if !from_number
    raise JsThrow.new(js_range_error("The number " + js_number_to_s(p) + " cannot be converted to a BigInt because it is not an integer")) if !js_is_integer?(p)
    return JsBigInt.new(js_float_to_bigint(p.abs) * (p < ~0.0 ? -1 : 1))
  return p if p.is_a?(JsBigInt)
  return JsBigInt.new(p ? 1 : 0) if p == true || p == false
  if p.is_a?(String)
    v2 = js_string_to_bigint(p)
    raise JsThrow.new(js_syntax_error("Cannot convert " + p + " to a BigInt")) if v2 == nil
    return JsBigInt.new(v2)
  js_throw_type("Cannot convert " + js_to_display(p) + " to a BigInt")

-> js_this_bigint(v)
  return v if v.is_a?(JsBigInt)
  return v.internal if v.is_a?(JsObject) && v.internal.is_a?(JsBigInt)
  js_throw_type("BigInt.prototype.valueOf requires that 'this' be a BigInt")

-> js_bigint_to_string(v, rv)
  b = js_this_bigint(v)
  radix = rv == nil ? 10 : js_to_integer(rv).to_i
  raise JsThrow.new(js_range_error("toString() radix must be between 2 and 36")) if radix < 2 || radix > 36
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
  m = 2 ** bits
  r = b % m
  r = r + m if r < 0
  if signed && bits > 0 && r >= 2 ** (bits - 1)
    r = r - m
  JsBigInt.new(r)

-> js_to_index(v)
  return 0 if v == nil
  n = js_to_integer(v)
  raise JsThrow.new(js_range_error("Invalid index")) if n < ~0.0 || n > ~9007199254740991.0
  n.to_i

js_install(->(r) js_install_number(r))

-> js_install_number(r)
  np = JsObject.new(r.object_proto, "Number")
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
  r.method(nc, "isFinite", 1, ->(this, args, nt) js_arg(args, 0).is_a?(Float) && js_finite?(js_arg(args, 0)))
  r.method(nc, "isNaN", 1, ->(this, args, nt) js_is_nan?(js_arg(args, 0)))
  g = r.global
  nc.define("parseFloat", g.get("parseFloat"), BUILTIN_ATTRS)
  nc.define("parseInt", g.get("parseInt"), BUILTIN_ATTRS)
  r.method(np, "toString", 1, ->(this, args, nt) js_num_to_string(this, js_arg(args, 0)))
  r.method(np, "toFixed", 1, ->(this, args, nt) js_num_to_fixed(this, js_arg(args, 0)))
  r.method(np, "toPrecision", 1, ->(this, args, nt) js_num_to_precision(this, js_arg(args, 0)))
  r.method(np, "toExponential", 1, ->(this, args, nt) js_num_to_exponential(this, js_arg(args, 0)))
  r.method(np, "toLocaleString", 0, ->(this, args, nt) js_num_to_locale(this, args))
  r.method(np, "valueOf", 0, ->(this, args, nt) js_this_num(this, "valueOf"))
  # Math
  m = JsObject.new(r.object_proto, "Object")
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
  ["abs", "acos", "acosh", "asin", "asinh", "atan", "atanh", "cbrt", "ceil", "cos", "cosh", "exp", "expm1", "floor", "fround", "log", "log1p", "log10", "log2", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc"].each ->(nm)
    js_install_math1(r, m, nm)
  r.method(m, "atan2", 2, ->(this, args, nt) Math.atan2(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  r.method(m, "pow", 2, ->(this, args, nt) js_pow(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  r.method(m, "max", 2, ->(this, args, nt) js_math_minmax(args, true))
  r.method(m, "min", 2, ->(this, args, nt) js_math_minmax(args, false))
  r.method(m, "hypot", 2, ->(this, args, nt) js_math_hypot(args))
  r.method(m, "random", 0, ->(this, args, nt) js_math_random())
  r.method(m, "clz32", 1, ->(this, args, nt) js_math_clz32(js_to_number(js_arg(args, 0))))
  r.method(m, "imul", 2, ->(this, args, nt) js_math_imul(js_to_number(js_arg(args, 0)), js_to_number(js_arg(args, 1))))
  # BigInt
  bp = JsObject.new(r.object_proto, "Object")
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
