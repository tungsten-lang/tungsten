# blade/js/ops — JavaScript operators (ECMA-262 §13) on the value model in value.w.
#
# Every operator has a fast path for the common case (two numbers, two strings)
# and falls back to the spec's abstract operations.

INF = ~1.0 / ~0.0
NEG_INF = ~-1.0 / ~0.0
TWO32 = ~4294967296.0

# ToInt32, fast for numbers already in range.
-> js_i32(v)
  if v.is_a?(Float) && v >= ~-2147483648.0 && v <= ~2147483647.0
    return v.to_i
  js_to_int32(v)

-> js_u32(v)
  if v.is_a?(Float) && v >= ~0.0 && v <= ~4294967295.0
    return v.to_i
  js_to_uint32(v)

-> js_f(i)
  i + ~0.0

-> js_add(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return a + b
  if a.is_a?(String) && b.is_a?(String)
    return js_str_cat(a, b)
  pa = js_to_primitive(a)
  pb = js_to_primitive(b)
  if pa.is_a?(String) || pb.is_a?(String)
    return js_str_cat(js_to_string(pa), js_to_string(pb))
  na = js_numeric_value(pa)
  nb = js_numeric_value(pb)
  if na.is_a?(JsBigInt) || nb.is_a?(JsBigInt)
    js_bigint_both(na, nb)
    return JsBigInt.new(na.v + nb.v)
  js_dyn(na + nb)

-> js_bigint_both(a, b)
  js_throw_type("Cannot mix BigInt and other types, use explicit conversions") if !(a.is_a?(JsBigInt) && b.is_a?(JsBigInt))

# Numeric binary operators other than +; op is a Symbol.
-> js_arith(op, a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return js_num_op(op, a, b)
  na = js_numeric_value(a)
  nb = js_numeric_value(b)
  if na.is_a?(JsBigInt) || nb.is_a?(JsBigInt)
    js_bigint_both(na, nb)
    return js_big_op(op, na.v, nb.v)
  js_dyn(js_num_op(op, na, nb))

-> js_num_op(op, a, b)
  case op
  when :sub
    a - b
  when :mul
    a * b
  when :div
    a / b
  when :mod
    js_mod(a, b)
  when :pow
    js_pow(a, b)
  when :shl
    js_f(js_wrap32(js_i32(a) << (js_u32(b) & 31)))
  when :sar
    js_f(js_i32(a) >> (js_u32(b) & 31))
  when :shr
    js_f(js_u32(a) >> (js_u32(b) & 31))
  when :band
    js_f(js_i32(a) & js_i32(b))
  when :bor
    js_f(js_i32(a) | js_i32(b))
  when :bxor
    js_f(js_i32(a) ^ js_i32(b))
  else
    js_nan()

-> js_wrap32(i)
  m = i & 0xFFFFFFFF
  m >= 2147483648 ? m - 4294967296 : m

-> js_mod(a, b)
  return js_nan() if a != a || b != b || a == INF || a == NEG_INF || b == ~0.0
  return a if b == INF || b == NEG_INF
  return a if a == ~0.0
  r = a % b
  # keep the sign of the dividend (fmod); -0 when the dividend is negative
  if r == ~0.0 && a < ~0.0
    return ~-0.0
  r

-> js_pow(a, b)
  return js_nan() if b != b
  return ~1.0 if b == ~0.0
  return js_nan() if (a == ~1.0 || a == ~-1.0) && (b == INF || b == NEG_INF)
  a ** b

-> js_big_op(op, a, b)
  case op
  when :sub
    JsBigInt.new(a - b)
  when :mul
    JsBigInt.new(a * b)
  when :div
    raise JsThrow.new(js_range_error("Division by zero")) if b == 0
    q = a.abs / b.abs
    JsBigInt.new((a < 0) != (b < 0) ? 0 - q : q)
  when :mod
    raise JsThrow.new(js_range_error("Division by zero")) if b == 0
    r = a.abs % b.abs
    JsBigInt.new(a < 0 ? 0 - r : r)
  when :pow
    raise JsThrow.new(js_range_error("Exponent must be non-negative")) if b < 0
    JsBigInt.new(a ** b)
  when :shl
    JsBigInt.new(b >= 0 ? a * (2 ** b) : js_big_floor_div(a, 2 ** (0 - b)))
  when :sar
    JsBigInt.new(b >= 0 ? js_big_floor_div(a, 2 ** b) : a * (2 ** (0 - b)))
  when :shr
    js_throw_type("BigInts have no unsigned right shift, use >> instead")
  when :band
    JsBigInt.new(a & b)
  when :bor
    JsBigInt.new(a | b)
  when :bxor
    JsBigInt.new(a ^ b)
  else
    nil

-> js_big_floor_div(a, b)
  q = a / b
  q -= 1 if (a % b != 0) && ((a < 0) != (b < 0)) && q * b != a && q * b > a
  q

-> js_neg(v)
  return ~0.0 - v if v.is_a?(Float) && v != ~0.0
  return (v == ~0.0 && (~1.0 / v) > ~0.0) ? ~-0.0 : ~0.0 if v.is_a?(Float)
  n = js_numeric_value(v)
  return JsBigInt.new(0 - n.v) if n.is_a?(JsBigInt)
  js_dyn(js_neg(n))

-> js_bitnot(v)
  return js_f(-1 - js_i32(v)) if v.is_a?(Float)
  n = js_numeric_value(v)
  return JsBigInt.new(-1 - n.v) if n.is_a?(JsBigInt)
  js_dyn(js_f(-1 - js_i32(n)))

-> js_inc(v, d)
  return v + d if v.is_a?(Float)
  n = js_numeric_value(v)
  return JsBigInt.new(n.v + (d > ~0.0 ? 1 : -1)) if n.is_a?(JsBigInt)
  js_dyn(n + d)

# Abstract relational comparison: true, false, or nil (undefined: NaN involved).
-> js_compare(a, b, left_first = true)
  if a.is_a?(Float) && b.is_a?(Float)
    return nil if a != a || b != b
    return a < b
  if a.is_a?(String) && b.is_a?(String)
    return js_str_cmp(a, b) < 0
  if left_first
    pa = js_to_primitive(a, "number")
    pb = js_to_primitive(b, "number")
  else
    pb = js_to_primitive(b, "number")
    pa = js_to_primitive(a, "number")
  return js_str_cmp(pa, pb) < 0 if pa.is_a?(String) && pb.is_a?(String)
  if pa.is_a?(JsBigInt) && pb.is_a?(String)
    nb = js_string_to_bigint(pb)
    return nil if nb == nil
    return pa.v < nb
  if pa.is_a?(String) && pb.is_a?(JsBigInt)
    na = js_string_to_bigint(pa)
    return nil if na == nil
    return na < pb.v
  na = pa.is_a?(JsBigInt) ? pa : js_to_number(pa)
  nb = pb.is_a?(JsBigInt) ? pb : js_to_number(pb)
  if na.is_a?(JsBigInt) && nb.is_a?(JsBigInt)
    return na.v < nb.v
  if na.is_a?(JsBigInt)
    return nil if nb != nb
    return nb > ~0.0 if nb == INF || nb == NEG_INF
    return js_big_lt_num(na.v, nb)
  if nb.is_a?(JsBigInt)
    return nil if na != na
    return na < ~0.0 if na == INF || na == NEG_INF
    return js_num_lt_big(na, nb.v)
  return nil if na != na || nb != nb
  na < nb

-> js_big_lt_num(i, x)
  f = Math.floor(x)
  return i < f.to_i if f == x
  i <= f.to_i

-> js_num_lt_big(x, i)
  c = Math.ceil(x)
  return c.to_i < i if c == x
  c.to_i <= i

-> js_string_to_bigint(s)
  t = js_trim(s)
  return 0 if t.size == 0
  neg = false
  if t.byte_at(0) == 45 || t.byte_at(0) == 43
    neg = t.byte_at(0) == 45
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
  v = 0 ## int
  i = 0
  while i < t.size
    d = js_digit(t.byte_at(i))
    return nil if d < 0 || d >= radix
    v = v * radix + d
    i += 1
  neg ? 0 - v : v

-> js_lt(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return a < b
  r = js_compare(a, b, true)
  r == true

-> js_gt(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return a > b
  r = js_compare(b, a, false)
  r == true

-> js_le(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return a <= b
  r = js_compare(b, a, false)
  r == false

-> js_ge(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return a >= b
  r = js_compare(a, b, true)
  r == false

-> js_instanceof(v, target)
  js_throw_type("Right-hand side of 'instanceof' is not an object") if !target.is_a?(JsObject)
  h = target.get(SYM_HAS_INSTANCE)
  if !js_nullish?(h) && !(h.is_a?(JsFunction) && h.native != nil && h.fname == "\[Symbol.hasInstance]" && JS_REALM[0] != nil && h == JS_REALM[0].intrinsic("%FunctionProto_hasInstance%"))
    return js_to_boolean(js_call(h, target, [v]))
  js_throw_type("Right-hand side of 'instanceof' is not callable") if !target.callable?
  js_ordinary_has_instance(target, v)

-> js_ordinary_has_instance(c, v)
  return false if !c.callable?
  if c.is_a?(JsFunction) && c.bound != nil
    return js_instanceof(v, c.bound[0])
  return false if !v.is_a?(JsObject)
  p = c.get("prototype")
  js_throw_type("Function has non-object prototype in instanceof check") if !p.is_a?(JsObject)
  o = v.get_prototype_of
  while o != JS_NULL && o != nil
    return true if o == p
    o = o.get_prototype_of
  false

-> js_in(k, o)
  js_throw_type("Cannot use 'in' operator to search for '" + js_to_display(k) + "' in " + js_to_display(o)) if !o.is_a?(JsObject)
  o.has_property?(js_to_property_key(k))

# typeof for any value, objects that are callable report "function".
-> js_typeof_v(v)
  return "undefined" if v.is_a?(JsObject) && v.htmldda?
  return "function" if v.is_a?(JsObject) && v.callable?
  js_typeof(v)

# String concatenation on WTF-8: a lone high surrogate at the end of a and a lone low
# surrogate at the start of b join into one code point (4-byte UTF-8), so the result is
# the same string as the one literals and fromCharCode produce.
-> js_str_cat(a, b)
  na = a.size
  if na >= 3 && b.size >= 3 && a.byte_at(na - 3) == 237 && b.byte_at(0) == 237
    h2 = a.byte_at(na - 2)
    l2 = b.byte_at(1)
    if h2 >= 160 && h2 <= 175 && l2 >= 176 && l2 <= 191
      hi = 55296 + ((h2 & 15) << 6) + (a.byte_at(na - 1) & 63)
      lo = 56320 + ((l2 & 15) << 6) + (b.byte_at(2) & 63)
      cp = 65536 + ((hi - 55296) << 10) + (lo - 56320)
      return a.slice(0, na - 3) + js_chr(cp) + b.slice(3, b.size - 3)
  a + b

# Compare strings by UTF-16 code units (-1, 0, 1). UTF-8 byte order is code point order,
# which differs only where a supplementary character meets a BMP one at or above U+E000.
-> js_str_cmp(a, b)
  na = a.size
  nb = b.size
  n = na < nb ? na : nb
  i = 0
  while i < n && a.byte_at(i) == b.byte_at(i)
    i += 1
  if i == n
    return na < nb ? -1 : (na > nb ? 1 : 0)
  # back up to the start of the differing code point (the prefix is shared)
  while i > 0 && (a.byte_at(i) & 192) == 128
    i -= 1
  ua = js_first_unit_at(a, i)
  ub = js_first_unit_at(b, i)
  if ua[0] != ub[0]
    return ua[0] < ub[0] ? -1 : 1
  ua[1] < ub[1] ? -1 : (ua[1] > ub[1] ? 1 : 0)

# [first UTF-16 unit, second unit or -1] of the code point starting at byte i.
-> js_first_unit_at(s, i)
  b0 = s.byte_at(i)
  cp = b0
  if b0 >= 240 && i + 3 <= s.size - 1
    cp = ((b0 & 7) << 18) | ((s.byte_at(i + 1) & 63) << 12) | ((s.byte_at(i + 2) & 63) << 6) | (s.byte_at(i + 3) & 63)
  elsif b0 >= 224 && i + 2 <= s.size - 1
    cp = ((b0 & 15) << 12) | ((s.byte_at(i + 1) & 63) << 6) | (s.byte_at(i + 2) & 63)
  elsif b0 >= 192 && i + 1 <= s.size - 1
    cp = ((b0 & 31) << 6) | (s.byte_at(i + 1) & 63)
  return [cp, -1] if cp < 65536
  [55296 + ((cp - 65536) >> 10), 56320 + ((cp - 65536) & 1023)]
