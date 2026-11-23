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
  return a + b if js_string?(a) && js_string?(b)
  pa = js_to_primitive(a)
  pb = js_to_primitive(b)
  return js_to_string(pa) + js_to_string(pb) if js_string?(pa) || js_string?(pb)
  if pa.is_a?(JS:BigIntValue) || pb.is_a?(JS:BigIntValue)
    return JS:BigIntValue.new(pa.v + pb.v) if pa.is_a?(JS:BigIntValue) && pb.is_a?(JS:BigIntValue)
    js_throw_type("Cannot mix BigInt and other types, use explicit conversions")
  js_to_number(pa) + js_to_number(pb)

-> js_sub(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fsub(ab, bb)) if jsr_nn(ab, bb) != 0
  js_to_number(a) - js_to_number(b)

-> js_mul(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fmul(ab, bb)) if jsr_nn(ab, bb) != 0
  x = js_to_number(a)
  y = js_to_number(b)
  wvalue_from_bits(jsr_fmul(wvalue_bits(x) ## i64, wvalue_bits(y) ## i64))

-> js_div(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fdiv(ab, bb)) if jsr_nn(ab, bb) != 0
  x = js_to_number(a)
  y = js_to_number(b)
  wvalue_from_bits(jsr_fdiv(wvalue_bits(x) ## i64, wvalue_bits(y) ## i64))

-> js_mod(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fmod(ab, bb)) if jsr_nn(ab, bb) != 0
  x = js_to_number(a)
  y = js_to_number(b)
  wvalue_from_bits(jsr_fmod(wvalue_bits(x) ## i64, wvalue_bits(y) ## i64))

-> js_neg(a)
  ab = wvalue_bits(a) ## i64
  return wvalue_from_bits(jsr_fneg(ab)) if jsr_num(ab) != 0
  x = js_to_number(a)
  wvalue_from_bits(jsr_fneg(wvalue_bits(x) ## i64))

-> js_plus(a)
  return a if js_number?(a)
  js_to_number(a)

-> js_pow(a, b)
  x = js_to_number(a)
  y = js_to_number(b)
  return js_nan() if y != y
  return ~1.0 if y == ~0.0
  return js_nan() if (x == ~1.0 || x == ~-1.0) && (y == ~1.0 / ~0.0 || y == ~-1.0 / ~0.0)
  x ** y

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
  nx = js_to_number(px)
  ny = js_to_number(py)
  return nil if nx != nx || ny != ny
  nx < ny

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
  return b if b != JSR_NOI32 && js_number?(v)
  js_to_int32(v)

-> js_bitor(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x | y)) if x != JSR_NOI32 && y != JSR_NOI32
  wvalue_from_bits(jsr_box_int((js_to_int32(a) | js_to_int32(b)) ## i64))

-> js_bitand(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x & y)) if x != JSR_NOI32 && y != JSR_NOI32
  wvalue_from_bits(jsr_box_int((js_to_int32(a) & js_to_int32(b)) ## i64))

-> js_bitxor(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  if jsr_nn(ab, bb) != 0
    x = jsr_i32(ab)
    y = jsr_i32(bb)
    return wvalue_from_bits(jsr_box_int(x ^ y)) if x != JSR_NOI32 && y != JSR_NOI32
  wvalue_from_bits(jsr_box_int((js_to_int32(a) ^ js_to_int32(b)) ## i64))

-> js_bitnot(a)
  x = js_to_int32(a) ## i64
  wvalue_from_bits(jsr_box_int(x ^ -1))

-> js_shl(a, b)
  x = js_int32_of(a) ## i64
  n = (js_to_uint32(b) & 31) ## i64
  r = (x << n) & 4294967295
  r = r - 4294967296 if r >= 2147483648
  wvalue_from_bits(jsr_box_int(r))

-> js_sar(a, b)
  x = js_int32_of(a) ## i64
  n = (js_to_uint32(b) & 31) ## i64
  wvalue_from_bits(jsr_box_int(x >> n))

-> js_shr(a, b)
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
    return wvalue_from_bits(jsr_box_int(x)) if x != JSR_NOI32
  wvalue_from_bits(jsr_box_int(js_to_int32(a) ## i64))
