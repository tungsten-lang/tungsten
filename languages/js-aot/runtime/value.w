# runtime/value — JS values on Tungsten values, and the abstract operations (ECMA-262 §7).
#
#   undefined nil          null     JS_NULL (JS:Null)
#   boolean   true/false   number   Float, always (an immediate double in the NaN-box)
#   string    String       symbol   JS:Symbol
#   object    JS:Base subclasses, and JS arrays: core Arrays flagged in their header
#
# Number formatting and parsing are ported from Blade's engine (blade/js/value.w).

in JS

+ Symbol
  ro :description
  -> new(@description)
    nil
  -> to_s
    "Symbol(" + (@description == nil ? "" : @description) + ")"

# A thrown JS value travelling through Tungsten's raise/rescue.
+ Throw < Error
  ro :value
  -> new(@value)
    nil
  -> message
    v = @value
    if v.is_a?(JS:Base)
      m = v.get("message", v)
      n = v.get("name", v)
      return (n == nil ? "Error" : js_to_string(n)) + ": " + (m == nil ? "" : js_to_string(m))
    js_to_display(v)
  -> to_s
    message()

-> js_throw(v)
  raise JS:Throw.new(v)

# The JS value of anything raised: a JS throw, or a runtime error turned into a JS error.
-> js_error_value(e)
  return e.value if e.is_a?(JS:Throw)
  js_make_error("Error", e.is_a?(String) ? e : e.message.to_s)

JS_NAN = [nil]

-> js_nan
  JS_NAN[0] = ~0.0 / ~0.0 if JS_NAN[0] == nil
  JS_NAN[0]

-> js_number?(v)
  jsr_num(wvalue_bits(v) ## i64) != 0

-> js_string?(v)
  jsr_str(wvalue_bits(v) ## i64) != 0

# A JS array: a core Array whose header carries JS_AF_ARRAY.
-> js_array?(v)
  (jsr_aflags(wvalue_bits(v) ## i64) & JS_AF_ARRAY) != 0

-> js_object?(v)
  v.is_a?(JS:Base) || js_array?(v)

-> js_callable?(v)
  k = jsr_kind(wvalue_bits(v) ## i64) & 15
  k == KIND_FUNCTION || k == KIND_NATIVE || k == KIND_BOUND || (k == KIND_EXOTIC && v.callable?)

-> js_typeof(v)
  return "undefined" if v == nil
  return "boolean" if v == true || v == false
  return "number" if js_number?(v)
  return "string" if js_string?(v)
  return "object" if v == JS_NULL
  return "symbol" if v.is_a?(JS:Symbol)
  return "function" if js_callable?(v)
  return "bigint" if v.is_a?(JS:BigIntValue)
  "object"

+ BigIntValue
  ro :v
  -> new(@v)
    nil

-> js_nullish?(v)
  v == nil || v == JS_NULL

# ToBoolean (§7.1.2).
-> js_truthy(v)
  return v if v == true || v == false
  return false if v == nil || v == JS_NULL
  if js_number?(v)
    return v != ~0.0 && v == v
  return v.size > 0 if js_string?(v)
  return v.v != 0 if v.is_a?(JS:BigIntValue)
  true

# ---- conversions (§7.1) ----

-> js_to_primitive(v, hint = "default")
  return v if !js_object?(v)
  ex = js_get_value(v, SYM_TO_PRIMITIVE)
  if ex != nil && ex != JS_NULL
    r = js_call_arr(ex, v, [hint])
    js_throw_type("Cannot convert object to primitive value") if js_object?(r)
    return r
  order = hint == "string" ? ["toString", "valueOf"] : ["valueOf", "toString"]
  i = 0
  while i < 2
    f = js_get_value(v, order[i])
    if js_callable?(f)
      r = js_call_arr(f, v, [])
      return r if !js_object?(r)
    i += 1
  js_throw_type("Cannot convert object to primitive value")

-> js_to_number(v)
  return v if js_number?(v)
  return js_nan() if v == nil
  return ~0.0 if v == JS_NULL || v == false
  return ~1.0 if v == true
  return js_string_to_number(v) if js_string?(v)
  js_throw_type("Cannot convert a JS:Symbol value to a number") if v.is_a?(JS:Symbol)
  js_throw_type("Cannot convert a BigInt value to a number") if v.is_a?(JS:BigIntValue)
  js_throw_type("Cannot convert value to a number") if !js_object?(v)
  js_to_number(js_to_primitive(v, "number"))

-> js_to_string(v)
  return v if js_string?(v)
  return js_number_to_s(v) if js_number?(v)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "true" if v == true
  return "false" if v == false
  js_throw_type("Cannot convert a JS:Symbol value to a string") if v.is_a?(JS:Symbol)
  return v.v.to_s if v.is_a?(JS:BigIntValue)
  js_throw_type("Cannot convert value to a string") if !js_object?(v)
  js_to_string(js_to_primitive(v, "string"))

-> js_to_property_key(v)
  return v if js_string?(v) || v.is_a?(JS:Symbol)
  return js_number_to_s(v) if js_number?(v)
  p = js_to_primitive(v, "string")
  p.is_a?(JS:Symbol) ? p : js_to_string(p)

# ToInt32 / ToUint32 on any value.
-> js_to_int32(v)
  x = js_to_number(v)
  b = jsr_i32(wvalue_bits(x) ## i64)
  return b if b != JSR_NOI32
  return 0 if x != x || x == ~1.0 / ~0.0 || x == ~-1.0 / ~0.0
  t = x < ~0.0 ? Math.ceil(x) : Math.floor(x)
  m = t % ~4294967296.0
  m += ~4294967296.0 if m < ~0.0
  m >= ~2147483648.0 ? (m - ~4294967296.0).to_i : m.to_i

-> js_to_uint32(v)
  i = js_to_int32(v)
  i < 0 ? i + 4294967296 : i

-> js_array_index?(k)
  n = k.size
  return false if n == 0 || n > 10
  return k == "0" if k.byte_at(0) == 48
  i = 0
  while i < n
    b = k.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  k.to_i < 4294967295

-> js_to_object(v)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(v)
  v

-> js_key_display(k)
  k.is_a?(JS:Symbol) ? k.to_s : k

# ---- equality (§7.2) ----

-> js_strict_eq(a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_feq(ab, bb)) == true if jsr_nn(ab, bb) != 0
  return a == b if js_string?(a) && js_string?(b)
  return a.v == b.v if a.is_a?(JS:BigIntValue) && b.is_a?(JS:BigIntValue)
  ab == bb

-> js_loose_eq(a, b)
  return js_strict_eq(a, b) if js_typeof(a) == js_typeof(b) && !(js_nullish?(a) && js_nullish?(b))
  return true if js_nullish?(a) && js_nullish?(b)
  return false if js_nullish?(a) || js_nullish?(b)
  return js_strict_eq(a, js_to_number(b)) if js_number?(a) && js_string?(b)
  return js_strict_eq(js_to_number(a), b) if js_string?(a) && js_number?(b)
  return js_loose_eq(js_to_number(a), b) if a == true || a == false
  return js_loose_eq(a, js_to_number(b)) if b == true || b == false
  if (js_number?(a) || js_string?(a) || a.is_a?(JS:Symbol) || a.is_a?(JS:BigIntValue)) && js_object?(b)
    return js_loose_eq(a, js_to_primitive(b))
  if js_object?(a) && (js_number?(b) || js_string?(b) || b.is_a?(JS:Symbol) || b.is_a?(JS:BigIntValue))
    return js_loose_eq(js_to_primitive(a), b)
  return js_big_num_eq(a, b) if a.is_a?(JS:BigIntValue)
  return js_big_num_eq(b, a) if b.is_a?(JS:BigIntValue)
  false

# A BigInt loosely equal to a Number or a String.
-> js_big_num_eq(x, v)
  if js_string?(v)
    n = js_string_to_bigint(v)
    return n != nil && n == x.v
  return false if !js_number?(v) || v != v || v == INF || v == ~0.0 - INF
  return false if Math.floor(v) != v
  v.to_i == x.v

-> js_same_value(a, b)
  if js_number?(a) && js_number?(b)
    return true if a != a && b != b
    return false if a == ~0.0 && b == ~0.0 && (~1.0 / a) != (~1.0 / b)
    return a == b
  js_strict_eq(a, b)

# ---- display (console) ----

-> js_to_display(v)
  return v if js_string?(v)
  return js_to_string(v) if !js_object?(v) && !v.is_a?(JS:Symbol)
  return v.to_s if v.is_a?(JS:Symbol)
  js_inspect(v, 2)

-> js_inspect(v, depth, seen = nil)
  return "'" + v + "'" if js_string?(v)
  return js_to_display(v) if !js_object?(v)
  if js_array?(v)
    return "\[Array]" if depth <= 0
    parts = []
    i = 0
    while i < v.size
      e = v[i]
      parts.push(e == JS_HOLE ? "<1 empty item>" : js_inspect(e, depth - 1))
      i += 1
    return "\[ " + parts.join(", ") + " ]" if parts.size > 0
    return "\[]"
  if js_callable?(v)
    n = js_get_value(v, "name")
    return "\[Function: " + (n == nil || n == "" ? "(anonymous)" : js_to_string(n)) + "]"
  if v.is_a?(JS:Special) && v.cls == "Error"
    # an error shows as its toString and stack, as consoles print one
    st = v.get_own("stack")
    t = js_error_to_string(v)
    return js_string?(st) && st.size > 0 && st != t ? t + "\n" + st : t
  return "\[Object]" if depth <= 0
  parts = []
  v.own_keys.each ->(k)
    if v.enumerable?(k)
      parts.push(js_key_display(k) + ": " + js_inspect(v.get(k, v), depth - 1))
  return "{}" if parts.size == 0
  "{ " + parts.join(", ") + " }"

# ---- numbers (from blade/js/value.w) ----

# Number::toString(10): the shortest digits that round-trip, in JavaScript's notation.
-> js_number_to_s(x)
  return "NaN" if x != x
  return "Infinity" if x == ~1.0 / ~0.0
  return "-Infinity" if x == ~-1.0 / ~0.0
  return "0" if x == ~0.0
  if x == Math.floor(x) && x.abs < ~9007199254740992.0
    return x.to_i.to_s
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  de = js_digits_exp(a)
  ds = de[0]
  e = de[1]
  # subnormals print with 15 digits but may round-trip with fewer; others need search
  # only past 15
  k0 = a < ~2.2250738585072014e-308 ? 1 : 15
  if ds.size > k0
    k = k0
    found = false
    while k < ds.size && !found
      r = js_round_digits(ds, e, k)
      cand = r[0]
      ce = r[1]
      if js_digits_value(cand, ce) == a
        ds = cand
        e = ce
        found = true
      k += 1
  out = js_format_digits(ds, e)
  neg ? "-" + out : out

# [significant digits without leading/trailing zeros, n] where value = 0.d1d2... * 10^n.
-> js_digits_exp(a)
  s = a.to_s
  ep = s.index("e")
  ex = 0
  mant = s
  if ep != nil
    ex = s.slice(ep + 1, s.size - ep - 1).to_i
    mant = s.slice(0, ep)
  dot = mant.index(".")
  ip = dot == nil ? mant : mant.slice(0, dot)
  fp = dot == nil ? "" : mant.slice(dot + 1, mant.size - dot - 1)
  digits = ip + fp
  n = ip.size + ex
  lz = 0
  while lz < digits.size - 1 && digits.byte_at(lz) == 48
    lz += 1
  digits = digits.slice(lz, digits.size - lz)
  n -= lz
  tz = digits.size
  while tz > 1 && digits.byte_at(tz - 1) == 48
    tz -= 1
  [digits.slice(0, tz), n]

# Round digit string ds (point exponent n) to k digits, half up: [digits, n].
-> js_round_digits(ds, n, k)
  return [ds, n] if ds.size <= k
  head = ds.slice(0, k)
  up = ds.byte_at(k) >= 53
  if up
    bytes = head.bytes.to_a
    i = k - 1
    carry = true
    while i >= 0 && carry
      if bytes[i] == 57
        bytes[i] = 48
        i -= 1
      else
        bytes[i] = bytes[i] + 1
        carry = false
    sb = StringBuffer()
    sb.append("1") if carry
    bytes.each ->(b) sb.append(b.chr)
    head = sb.to_s
    n += 1 if carry
  tz = head.size
  while tz > 1 && head.byte_at(tz - 1) == 48
    tz -= 1
  [head.slice(0, tz), n]

-> js_digits_value(ds, n)
  ("0." + ds + "e" + n.to_s).to_f

# Number::toString layout for digits ds (k of them) with point position n (§6.1.6.1.20).
-> js_format_digits(ds, n)
  k = ds.size
  if k <= n && n <= 21
    return ds + "0" * (n - k)
  if 0 < n && n <= 21
    return ds.slice(0, n) + "." + ds.slice(n, k - n)
  if -6 < n && n <= 0
    return "0." + "0" * (0 - n) + ds
  ex = n - 1
  sign = ex < 0 ? "-" : "+"
  exs = (ex < 0 ? 0 - ex : ex).to_s
  return ds + "e" + sign + exs if k == 1
  ds.slice(0, 1) + "." + ds.slice(1, k - 1) + "e" + sign + exs

# StringToNumber (whitespace-trimmed decimal, hex/octal/binary, Infinity; else NaN).
-> js_string_to_number(s)
  t = js_trim(s)
  return ~0.0 if t.size == 0
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    if b == 120 || b == 111 || b == 98
      radix = b == 120 ? 16 : (b == 111 ? 8 : 2)
      v = ~0.0
      i = 2
      while i < t.size
        d = js_digit(t.byte_at(i))
        return js_nan() if d < 0 || d >= radix
        v = v * radix + d
        i += 1
      return v
  sign = ~1.0
  body = t
  if t.byte_at(0) == 43 || t.byte_at(0) == 45
    sign = t.byte_at(0) == 45 ? ~-1.0 : ~1.0
    body = t.slice(1, t.size - 1)
  return sign * (~1.0 / ~0.0) if body == "Infinity"
  return js_nan() if !js_decimal_literal?(body)
  sign * body.to_f

-> js_digit(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 87 if b >= 97 && b <= 122
  return b - 55 if b >= 65 && b <= 90
  -1

-> js_decimal_literal?(s)
  return false if s.size == 0
  i = 0
  n = s.size
  digits = 0
  while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
    i += 1
    digits += 1
  if i < n && s.byte_at(i) == 46
    i += 1
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      i += 1
      digits += 1
  return false if digits == 0
  if i < n && (s.byte_at(i) == 101 || s.byte_at(i) == 69)
    i += 1
    i += 1 if i < n && (s.byte_at(i) == 43 || s.byte_at(i) == 45)
    ed = 0
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      i += 1
      ed += 1
    return false if ed == 0
  i == n

JS_WS = [9, 10, 11, 12, 13, 32]

# WhiteSpace and LineTerminator (§12.2, §12.3) at both ends: the ASCII ones and U+00A0,
# U+1680, U+2000-200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.
-> js_trim(s)
  a = 0
  b = s.size
  while a < b
    n = js_ws_len_at(s, a)
    break if n == 0
    a += n
  while b > a
    n = js_ws_len_before(s, b)
    break if n == 0
    b -= n
  s.slice(a, b - a)

# Bytes of the whitespace character starting at byte i, or 0.
-> js_ws_len_at(s, i)
  c = s.byte_at(i)
  return 1 if c == 32 || (c >= 9 && c <= 13)
  return 0 if c < 192
  return (i + 1 < s.size && s.byte_at(i + 1) == 160) ? 2 : 0 if c == 194
  return 0 if i + 2 >= s.size || (c != 225 && c != 226 && c != 227 && c != 239)
  js_ws3?(c, s.byte_at(i + 1), s.byte_at(i + 2)) ? 3 : 0

# Bytes of the whitespace character ending just before byte e, or 0.
-> js_ws_len_before(s, e)
  c = s.byte_at(e - 1)
  return 1 if c == 32 || (c >= 9 && c <= 13)
  return 0 if c < 128
  return 2 if e >= 2 && c == 160 && s.byte_at(e - 2) == 194
  return 3 if e >= 3 && js_ws3?(s.byte_at(e - 3), s.byte_at(e - 2), c)
  0

-> js_ws3?(a, b, c)
  return b == 154 && c == 128 if a == 225
  return b == 128 && c == 128 if a == 227
  return b == 187 && c == 191 if a == 239
  return false if a != 226
  return (c >= 128 && c <= 138) || c == 168 || c == 169 || c == 175 if b == 128
  b == 129 && c == 159
