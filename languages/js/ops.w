# runtime/ops — the operators. Each has a number fast path (two tag tests and one
# machine instruction, inlined into compiled code) and a generic path with the full
# coercions (ECMA-262 §13).

in JS

-> js_add(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fadd(ab, bb)) if jsr_nn(ab, bb) != 0
  js_add_slow(a, b)

-> js_add_slow(a, b)
  return js_str_cat(a, b) if js_string?(a) && js_string?(b)
  pa = js_to_primitive(a)
  pb = js_to_primitive(b)
  return js_str_cat(js_to_string(pa), js_to_string(pb)) if js_string?(pa) || js_string?(pb)
  if pa.is_a?(JS:BigIntValue) || pb.is_a?(JS:BigIntValue)
    return JS:BigIntValue.new(pa.v + pb.v) if pa.is_a?(JS:BigIntValue) && pb.is_a?(JS:BigIntValue)
    js_throw_type("Cannot mix BigInt and other types, use explicit conversions")
  js_to_number(pa) + js_to_number(pb)

-> js_sub(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fsub(ab, bb)) if jsr_nn(ab, bb) != 0
  js_arith_slow(2, a, b)

-> js_mul(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fmul(ab, bb)) if jsr_nn(ab, bb) != 0
  js_arith_slow(3, a, b)

-> js_div(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fdiv(ab, bb)) if jsr_nn(ab, bb) != 0
  js_arith_slow(4, a, b)

-> js_mod(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fmod(ab, bb)) if jsr_nn(ab, bb) != 0
  js_arith_slow(5, a, b)

-> js_neg(a)
  ab = wvalue_bits(a) ## i64
  return wvalue_from_bits(jsr_fneg(ab)) if jsr_num(ab) != 0
  x = js_numeric_value(a)
  return JS:BigIntValue.new(0 - x.v) if x.is_a?(JS:BigIntValue)
  wvalue_from_bits(jsr_fneg(wvalue_bits(x) ## i64))

-> js_plus(a)
  return a if js_number?(a)
  js_to_number(a)

-> js_pow(a, b)
  x = a
  y = b
  if !js_number?(a) || !js_number?(b)
    x = js_numeric_value(a)
    y = js_numeric_value(b)
    return js_big_op(20, x, y) if x.is_a?(JS:BigIntValue) || y.is_a?(JS:BigIntValue)
  return js_nan() if y != y
  return ~1.0 if y == ~0.0
  return js_nan() if (x == ~1.0 || x == ~-1.0) && (y == ~1.0 / ~0.0 || y == ~-1.0 / ~0.0)
  x ** y

# -, *, /, % past the Number fast path: ToNumeric, then Number or BigInt arithmetic.
-> js_arith_slow(op, a, b)
  x = js_numeric_value(a)
  y = js_numeric_value(b)
  return js_big_op(op, x, y) if x.is_a?(JS:BigIntValue) || y.is_a?(JS:BigIntValue)
  xb = wvalue_bits(x) ## i64
  yb = wvalue_bits(y) ## i64
  return wvalue_from_bits(jsr_fsub(xb, yb)) if op == 2
  return wvalue_from_bits(jsr_fmul(xb, yb)) if op == 3
  return wvalue_from_bits(jsr_fdiv(xb, yb)) if op == 4
  wvalue_from_bits(jsr_fmod(xb, yb))

# A BigInt binary operator (op as in the walker's WK_OPS); both must be BigInts.
-> js_big_op(op, x, y)
  js_throw_type("Cannot mix BigInt and other types, use explicit conversions") if !(x.is_a?(JS:BigIntValue) && y.is_a?(JS:BigIntValue))
  a = x.v
  b = y.v
  return JS:BigIntValue.new(a + b) if op == 1
  return JS:BigIntValue.new(a - b) if op == 2
  return JS:BigIntValue.new(a * b) if op == 3
  if op == 4 || op == 5
    js_throw_range("Division by zero") if b == 0
    if op == 4
      q = a.abs / b.abs
      return JS:BigIntValue.new((a < 0) != (b < 0) ? 0 - q : q)
    r = a.abs % b.abs
    return JS:BigIntValue.new(a < 0 ? 0 - r : r)
  return JS:BigIntValue.new(a | b) if op == 14
  return JS:BigIntValue.new(a & b) if op == 15
  return JS:BigIntValue.new(a ^ b) if op == 16
  return JS:BigIntValue.new(b >= 0 ? a * (2 ** b) : js_big_floor_div(a, 2 ** (0 - b))) if op == 17
  return JS:BigIntValue.new(b >= 0 ? js_big_floor_div(a, 2 ** b) : a * (2 ** (0 - b))) if op == 18
  js_throw_type("BigInts have no unsigned right shift, use >> instead") if op == 19
  js_throw_range("Exponent must be non-negative") if b < 0
  JS:BigIntValue.new(a ** b)

-> js_big_floor_div(a, b)
  q = a / b
  q -= 1 if (a % b != 0) && ((a < 0) != (b < 0)) && q * b > a
  q

# x + 1 or x - 1 for ++ and -- (x already ToNumeric).
-> js_inc(x, up)
  return JS:BigIntValue.new(x.v + (up ? 1 : -1)) if x.is_a?(JS:BigIntValue)
  up ? js_add(x, ~1.0) : js_sub(x, ~1.0)

# ---- comparison ----

-> js_lt(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_flt(ab, bb)) if jsr_nn(ab, bb) != 0
  js_compare(a, b, false) == true

-> js_gt(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_flt(bb, ab)) if jsr_nn(ab, bb) != 0
  js_compare(b, a, true) == true

-> js_le(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fle(ab, bb)) if jsr_nn(ab, bb) != 0
  r = js_compare(b, a, true)
  r == false

-> js_ge(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fle(bb, ab)) if jsr_nn(ab, bb) != 0
  r = js_compare(a, b, false)
  r == false

# IsLessThan (§7.2.13): true, false, or nil (undefined: a NaN was involved).
-> js_compare(x, y, right_first)
  px = nil
  py = nil
  if right_first
    py = js_to_primitive(y, "number")
    px = js_to_primitive(x, "number")
  else
    px = js_to_primitive(x, "number")
    py = js_to_primitive(y, "number")
  if js_string?(px) && js_string?(py)
    return js_string_lt(px, py)
  if px.is_a?(JS:BigIntValue) || py.is_a?(JS:BigIntValue)
    return js_big_compare(px, py)
  nx = js_to_number(px)
  ny = js_to_number(py)
  return nil if nx != nx || ny != ny
  nx < ny

# x < y with at least one BigInt (primitives): true, false or nil.
-> js_big_compare(px, py)
  if js_string?(py)
    nb = js_string_to_bigint(py)
    return nil if nb == nil
    return px.v < nb
  if js_string?(px)
    na = js_string_to_bigint(px)
    return nil if na == nil
    return na < py.v
  nx = px.is_a?(JS:BigIntValue) ? px : js_to_number(px)
  ny = py.is_a?(JS:BigIntValue) ? py : js_to_number(py)
  return nx.v < ny.v if nx.is_a?(JS:BigIntValue) && ny.is_a?(JS:BigIntValue)
  if nx.is_a?(JS:BigIntValue)
    return nil if ny != ny
    return ny > ~0.0 if ny == INF || ny == ~0.0 - INF
    if ny.abs >= ~4503599627370496.0
      return nx.v < js_big_float_int(ny)
    f = Math.floor(ny)
    return nx.v < f.to_i if f == ny
    return nx.v <= f.to_i
  return nil if nx != nx
  return nx < ~0.0 if nx == INF || nx == ~0.0 - INF
  if nx.abs >= ~4503599627370496.0
    return js_big_float_int(nx) < ny.v
  c = Math.ceil(nx)
  return c.to_i < ny.v if c == nx
  c.to_i <= ny.v

# Strings compare by UTF-16 code units. UTF-8 byte order is code point order, which
# differs from code unit order only for characters above U+FFFF against U+E000-U+FFFF.
-> js_string_lt(a, b)
  return a < b if a.ascii? && b.ascii?
  ua = js_str_units(a)
  ub = js_str_units(b)
  n = ua.size < ub.size ? ua.size : ub.size
  i = 0
  while i < n
    return ua[i] < ub[i] if ua[i] != ub[i]
    i += 1
  ua.size < ub.size

-> js_eq(a, b)
  js_loose_eq(a, b)

-> js_seq(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_feq(ab, bb)) if jsr_nn(ab, bb) != 0
  return true if ab == bb && !js_number?(a)
  js_strict_eq(a, b)

# ---- bitwise (§13.12, ToInt32 / ToUint32) ----

-> js_int32_of(v)
  b = jsr_i32(wvalue_bits(v) ## i64)
  return b if b != (1099511627776 ## i64) && js_number?(v)
  js_to_int32(v)

-> js_bitor(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x | y)) if x != (1099511627776 ## i64) && y != (1099511627776 ## i64)
  x = js_numeric_value(a)
  y = js_numeric_value(b)
  return js_big_op(14, x, y) if x.is_a?(JS:BigIntValue) || y.is_a?(JS:BigIntValue)
  wvalue_from_bits(jsr_box_int((js_to_int32(x) | js_to_int32(y)) ## i64))

-> js_bitand(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x & y)) if x != (1099511627776 ## i64) && y != (1099511627776 ## i64)
  x = js_numeric_value(a)
  y = js_numeric_value(b)
  return js_big_op(15, x, y) if x.is_a?(JS:BigIntValue) || y.is_a?(JS:BigIntValue)
  wvalue_from_bits(jsr_box_int((js_to_int32(x) & js_to_int32(y)) ## i64))

-> js_bitxor(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x ^ y)) if x != (1099511627776 ## i64) && y != (1099511627776 ## i64)
  x = js_numeric_value(a)
  y = js_numeric_value(b)
  return js_big_op(16, x, y) if x.is_a?(JS:BigIntValue) || y.is_a?(JS:BigIntValue)
  wvalue_from_bits(jsr_box_int((js_to_int32(x) ^ js_to_int32(y)) ## i64))

-> js_bitnot(a)
  if !js_number?(a)
    n = js_numeric_value(a)
    return JS:BigIntValue.new(-1 - n.v) if n.is_a?(JS:BigIntValue)
    a = n
  x = js_to_int32(a) ## i64
  wvalue_from_bits(jsr_box_int(x ^ -1))

-> js_shl(a, b)
  if !js_number?(a) || !js_number?(b)
    a = js_numeric_value(a)
    b = js_numeric_value(b)
    return js_big_op(17, a, b) if a.is_a?(JS:BigIntValue) || b.is_a?(JS:BigIntValue)
  x = js_int32_of(a) ## i64
  n = (js_to_uint32(b) & 31) ## i64
  r = (x << n) & 4294967295
  r = r - 4294967296 if r >= 2147483648
  wvalue_from_bits(jsr_box_int(r))

-> js_sar(a, b)
  if !js_number?(a) || !js_number?(b)
    a = js_numeric_value(a)
    b = js_numeric_value(b)
    return js_big_op(18, a, b) if a.is_a?(JS:BigIntValue) || b.is_a?(JS:BigIntValue)
  x = js_int32_of(a) ## i64
  n = (js_to_uint32(b) & 31) ## i64
  wvalue_from_bits(jsr_box_int(x >> n))

-> js_shr(a, b)
  if !js_number?(a) || !js_number?(b)
    a = js_numeric_value(a)
    b = js_numeric_value(b)
    return js_big_op(19, a, b) if a.is_a?(JS:BigIntValue) || b.is_a?(JS:BigIntValue)
  x = (js_to_uint32(a)) ## i64
  n = (js_to_uint32(b) & 31) ## i64
  wvalue_from_bits(jsr_box_int(x >> n))

# ---- other unary operators ----

-> js_not(v)
  !js_truthy(v)

-> js_void(v)
  nil

# x | 0: ToInt32 alone.
-> js_int32(a)
  ab = wvalue_bits(a) ## i64
  if jsr_num(ab) != 0
    x = jsr_i32(ab)
    return wvalue_from_bits(jsr_box_int(x)) if x != (1099511627776 ## i64)
  wvalue_from_bits(jsr_box_int(js_to_int32(a) ## i64))
