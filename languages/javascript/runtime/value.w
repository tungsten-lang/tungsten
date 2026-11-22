# blade/js/value — the JavaScript value model and abstract operations (ECMA-262 §6–7).
#
# Representation (chosen so the common cases are plain Tungsten values):
#   undefined → nil            null    → JS_NULL (a JsNull)
#   boolean   → true / false   number  → Float (always: JS has one number type)
#   string    → String (UTF-8; length and indexing are in UTF-16 code units, see js_len / js_char_code_at)
#   bigint    → JsBigInt (wraps a Tungsten Integer, kept distinct from number)
#   symbol    → JsSymbol       object  → JsObject and subclasses
#
# Properties: a data property with the default attributes (writable, enumerable,
# configurable) is just @props[key] = value. Non-default attributes live in
# @attrs[key] (bit flags), and accessors in @getters / @setters, so ordinary
# objects pay nothing for them. Keys are Strings or JsSymbols; array indices are
# canonical numeric strings ("0", "1", …) except in a JsArray's dense @elems.

+ JsNull
  -> new
  -> to_s
    "null"

JS_NULL = JsNull.new

# Marks an array hole (distinct from undefined).
+ JsHole
  -> new
JS_HOLE = JsHole.new

+ JsSymbol
  ro :description
  -> new(@description)
  -> to_s
    "Symbol(" + (@description == nil ? "" : @description) + ")"

+ JsBigInt
  ro :v
  -> new(@v)

# A thrown JavaScript value travelling through Tungsten's rescue.
+ JsThrow < Error
  ro :value
  -> new(@value)
  -> message
    v = @value
    if v.is_a?(JsObject)
      m = v.get_own("message")
      n = v.get_own("name")
      return (n == nil ? "Error" : n.to_s) + ": " + (m == nil ? "" : m.to_s)
    js_to_display(v)
  -> to_s
    message()

ATTR_W = 1
ATTR_E = 2
ATTR_C = 4
ATTR_ALL = 7

# Well-known symbols.
SYM_ITERATOR = JsSymbol.new("Symbol.iterator")
SYM_ASYNC_ITERATOR = JsSymbol.new("Symbol.asyncIterator")
SYM_TO_PRIMITIVE = JsSymbol.new("Symbol.toPrimitive")
SYM_TO_STRING_TAG = JsSymbol.new("Symbol.toStringTag")
SYM_HAS_INSTANCE = JsSymbol.new("Symbol.hasInstance")
SYM_SPECIES = JsSymbol.new("Symbol.species")
SYM_UNSCOPABLES = JsSymbol.new("Symbol.unscopables")
SYM_IS_CONCAT_SPREADABLE = JsSymbol.new("Symbol.isConcatSpreadable")
SYM_MATCH = JsSymbol.new("Symbol.match")
SYM_MATCH_ALL = JsSymbol.new("Symbol.matchAll")
SYM_REPLACE = JsSymbol.new("Symbol.replace")
SYM_SEARCH = JsSymbol.new("Symbol.search")
SYM_SPLIT = JsSymbol.new("Symbol.split")

+ JsObject
  rw :proto, :props, :attrs, :getters, :setters, :extensible, :cls, :internal

  -> new(@proto = JS_NULL, @cls = "Object")
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil

  # ---- own properties ----

  -> has_own?(k)
    @props.has_key?(k) || (@getters != nil && @getters.has_key?(k)) || (@setters != nil && @setters.has_key?(k))

  -> accessor?(k)
    (@getters != nil && @getters.has_key?(k)) || (@setters != nil && @setters.has_key?(k))

  -> attr(k)
    return ATTR_ALL if @attrs == nil || !@attrs.has_key?(k)
    @attrs[k]

  # The raw own data value (no getters), or nil.
  -> get_own(k)
    @props[k]

  # Define (or redefine) a data property.
  -> define(k, v, flags = ATTR_ALL)
    if @getters != nil
      @getters.delete(k)
    if @setters != nil
      @setters.delete(k)
    @props[k] = v
    if flags != ATTR_ALL
      @attrs = {} if @attrs == nil
      @attrs[k] = flags
    elsif @attrs != nil && @attrs.has_key?(k)
      @attrs.delete(k)
    self

  # Define an accessor property; g / s are JsFunctions or nil.
  -> define_accessor(k, g, s, flags = ATTR_E + ATTR_C)
    @props.delete(k)
    @getters = {} if @getters == nil
    @setters = {} if @setters == nil
    if g == nil
      @getters.delete(k)
    else
      @getters[k] = g
    if s == nil
      @setters.delete(k)
    else
      @setters[k] = s
    @attrs = {} if @attrs == nil
    @attrs[k] = flags & (ATTR_E + ATTR_C)
    # keep the key present even with neither half
    @getters[k] = nil if g == nil && s == nil
    self

  -> delete_own(k)
    return true if !has_own?(k)
    return false if (attr(k) & ATTR_C) == 0
    @props.delete(k)
    @getters.delete(k) if @getters != nil
    @setters.delete(k) if @setters != nil
    @attrs.delete(k) if @attrs != nil
    true

  # Own keys in spec order: integer indices ascending, then strings in insertion order, then symbols.
  -> own_keys
    ints = []
    strs = []
    syms = []
    add = ->(k)
      if k.is_a?(JsSymbol)
        syms.push(k)
      elsif js_array_index?(k)
        ints.push(k)
      else
        strs.push(k)
    @props.keys.each ->(k) add.call(k)
    if @getters != nil
      @getters.keys.each ->(k) add.call(k) if !@props.has_key?(k)
    if @setters != nil
      @setters.keys.each ->(k) add.call(k) if !@props.has_key?(k) && (@getters == nil || !@getters.has_key?(k))
    ints = ints.sort_by(->(k) k.to_i) if ints.size > 1
    ints + strs + syms

  -> enumerable?(k)
    (attr(k) & ATTR_E) != 0

  # ---- [[Get]] / [[Set]] with the prototype chain ----

  -> get(k, receiver = nil)
    o = self
    while o != JS_NULL && o != nil
      v = o.props[k]
      return v if v != nil
      if o.has_own_slot?(k)
        return o.own_value(k, receiver == nil ? self : receiver)
      o = o.proto
    nil

  # Is there an own slot for k (data or accessor, value possibly undefined)?
  -> has_own_slot?(k)
    has_own?(k)

  -> own_value(k, receiver)
    if accessor?(k)
      g = @getters == nil ? nil : @getters[k]
      return nil if g == nil
      return js_call(g, receiver, [])
    @props[k]

  -> set(k, v, receiver = nil)
    receiver = self if receiver == nil
    o = self
    while o != JS_NULL && o != nil
      if o.has_own_slot?(k)
        if o.accessor?(k)
          s = o.setters == nil ? nil : o.setters[k]
          raise JsThrow.new(js_type_error("Cannot set property " + js_key_display(k) + " which has only a getter")) if s == nil && JS_STRICT[0]
          js_call(s, receiver, [v]) if s != nil
          return true
        if (o.attr(k) & ATTR_W) == 0
          raise JsThrow.new(js_type_error("Cannot assign to read only property '" + js_key_display(k) + "'")) if JS_STRICT[0]
          return false
        break
      o = o.proto
    return receiver.put_own(k, v) if receiver.is_a?(JsObject)
    false

  # Create or overwrite an own data property through [[Set]].
  -> put_own(k, v)
    if @props.has_key?(k) || has_own?(k)
      if accessor?(k)
        return false
      return false if (attr(k) & ATTR_W) == 0
      @props[k] = v
      return true
    return false if !@extensible
    @props[k] = v
    true

  -> has_property?(k)
    o = self
    while o != JS_NULL && o != nil
      return true if o.has_own_slot?(k)
      o = o.proto
    false

  -> callable?
    false


# Arrays: indices in a dense Tungsten array (holes are JS_HOLE), the rest as ordinary properties.
+ JsArray < JsObject
  rw :elems

  -> new(@proto, @elems = [])
    @cls = "Array"
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil

  -> length
    @elems.size

  -> index_of_key(k)
    return -1 if !k.is_a?(String) || !js_array_index?(k)
    k.to_i

  -> has_own?(k)
    if k == "length"
      return true
    i = index_of_key(k)
    return i < @elems.size && @elems[i] != JS_HOLE if i >= 0
    super(k)

  -> has_own_slot?(k)
    has_own?(k)

  -> attr(k)
    return ATTR_W if k == "length"
    super(k)

  -> get_own(k)
    return (@elems.size + ~0.0) if k == "length"
    i = index_of_key(k)
    if i >= 0
      return nil if i >= @elems.size
      v = @elems[i]
      return v == JS_HOLE ? nil : v
    @props[k]

  -> get(k, receiver = nil)
    i = index_of_key(k)
    if i >= 0 && i < @elems.size
      v = @elems[i]
      return v if v != JS_HOLE
    return (@elems.size + ~0.0) if k == "length"
    super(k, receiver)

  -> own_value(k, receiver)
    return get_own(k) if k == "length" || index_of_key(k) >= 0
    super(k, receiver)

  -> put_own(k, v)
    if k == "length"
      set_length(js_to_number(v))
      return true
    i = index_of_key(k)
    if i >= 0
      while @elems.size < i
        @elems.push(JS_HOLE)
      if i == @elems.size
        @elems.push(v)
      else
        @elems[i] = v
      return true
    super(k, v)

  -> define(k, v, flags = ATTR_ALL)
    i = index_of_key(k)
    if i >= 0 && flags == ATTR_ALL
      put_own(k, v)
      return self
    if k == "length"
      set_length(js_to_number(v))
      return self
    super(k, v, flags)

  -> delete_own(k)
    i = index_of_key(k)
    if i >= 0
      @elems[i] = JS_HOLE if i < @elems.size
      return true
    return false if k == "length"
    super(k)

  -> set_length(n)
    len = n.to_i
    raise JsThrow.new(js_range_error("Invalid array length")) if len < 0 || n != len + ~0.0
    while @elems.size > len
      @elems.pop
    while @elems.size < len
      @elems.push(JS_HOLE)

  -> own_keys
    out = []
    i = 0
    while i < @elems.size
      out.push(i.to_s) if @elems[i] != JS_HOLE
      i += 1
    out.push("length")
    super().each ->(k) out.push(k)
    out

  -> enumerable?(k)
    return false if k == "length"
    super(k)


# Functions. A native function is a Tungsten lambda ->(this, args, new_target);
# interpreted functions carry their code and scope in @code / @scope for the interpreter.
+ JsFunction < JsObject
  rw :native, :code, :scope, :fname, :arity, :ctor, :this_mode, :home, :fields, :bound

  -> new(@proto, @native, @fname = "", @arity = 0, @ctor = false)
    @cls = "Function"
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil
    @code = nil
    @scope = nil
    @this_mode = :normal
    @home = nil
    @fields = nil
    @bound = nil
    define("name", @fname, ATTR_C)
    define("length", @arity + ~0.0, ATTR_C)

  -> callable?
    true


# The interpreter installs these: how to call an interpreted function, and the current realm.
JS_CALL_HOOK = [nil]
JS_CONSTRUCT_HOOK = [nil]
JS_REALM = [nil]
JS_STRICT = [false]

-> js_call(f, this, args)
  raise JsThrow.new(js_type_error(js_typeof(f) == "undefined" ? "undefined is not a function" : js_to_display(f) + " is not a function")) if !f.is_a?(JsFunction)
  return f.native.call(this, args, nil) if f.native != nil
  JS_CALL_HOOK[0].call(f, this, args)

-> js_construct(f, args, new_target = nil)
  raise JsThrow.new(js_type_error(js_to_display(f) + " is not a constructor")) if !f.is_a?(JsFunction) || !f.ctor
  new_target = f if new_target == nil
  if f.native != nil
    return f.native.call(nil, args, new_target)
  JS_CONSTRUCT_HOOK[0].call(f, args, new_target)


# ---- errors ----

-> js_make_error(kind, msg)
  r = JS_REALM[0]
  proto = r == nil ? JS_NULL : r.proto_of(kind)
  e = JsObject.new(proto, "Error")
  e.define("message", msg, ATTR_W + ATTR_C)
  e.define("stack", kind + ": " + msg + "\n    at <blade>", ATTR_W + ATTR_C)
  e

-> js_type_error(msg)
  js_make_error("TypeError", msg)

-> js_range_error(msg)
  js_make_error("RangeError", msg)

-> js_reference_error(msg)
  js_make_error("ReferenceError", msg)

-> js_syntax_error(msg)
  js_make_error("SyntaxError", msg)

-> js_throw_type(msg)
  raise JsThrow.new(js_type_error(msg))


# ---- type predicates and typeof ----

-> js_number?(v)
  v.is_a?(Float)

-> js_object?(v)
  v.is_a?(JsObject)

-> js_typeof(v)
  return "undefined" if v == nil
  return "object" if v == JS_NULL
  return "boolean" if v == true || v == false
  return "number" if v.is_a?(Float)
  return "string" if v.is_a?(String)
  return "symbol" if v.is_a?(JsSymbol)
  return "bigint" if v.is_a?(JsBigInt)
  return "function" if v.is_a?(JsFunction)
  "object"

-> js_nullish?(v)
  v == nil || v == JS_NULL


# ---- strings (UTF-16 view over UTF-8) ----

-> js_ascii?(s)
  n = s.size
  i = 0
  while i < n
    return false if s.byte_at(i) >= 128
    i += 1
  true

# UTF-16 code units of s, as an Array of Ints.
-> js_units(s)
  out = []
  s.codepoints.each ->(cp)
    if cp >= 0x10000
      c = cp - 0x10000
      out.push(0xD800 + (c >> 10))
      out.push(0xDC00 + (c & 0x3FF))
    else
      out.push(cp)
  out

-> js_len(s)
  return s.size if js_ascii?(s)
  js_units(s).size

-> js_char_code_at(s, i)
  if js_ascii?(s)
    return nil if i < 0 || i >= s.size
    return s.byte_at(i) + ~0.0
  u = js_units(s)
  return nil if i < 0 || i >= u.size
  u[i] + ~0.0

# Code units → String (lone surrogates become U+FFFD).
-> js_from_units(u)
  sb = StringBuffer()
  i = 0
  while i < u.size
    c = u[i]
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF
      cp = 0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00)
      sb.append(cp.chr)
      i += 2
      next
    if c >= 0xD800 && c <= 0xDFFF
      sb.append(0xFFFD.chr)
    else
      sb.append(c.chr)
    i += 1
  sb.to_s

# s.substring(a, b) in UTF-16 units.
-> js_substring(s, a, b)
  if js_ascii?(s)
    return "" if b <= a
    return s.slice(a, b - a)
  u = js_units(s)
  return "" if b <= a
  js_from_units(u.slice(a, b - a))


# ---- numbers ----

JS_NAN = [nil]

-> js_nan
  JS_NAN[0] = ~0.0 / ~0.0 if JS_NAN[0] == nil
  JS_NAN[0]

-> js_is_nan?(x)
  x.is_a?(Float) && x != x

# Number::toString(10). TODO(tungsten): JavaScript needs the shortest digits that round-trip;
# Tungsten's Float#to_s prints 17 significant digits. Float bit access and a shortest formatter
# are being added to core (branch float-bits); switch to it when it lands.
-> js_number_to_s(x)
  return "NaN" if x != x
  return "Infinity" if x == ~1.0 / ~0.0
  return "-Infinity" if x == ~-1.0 / ~0.0
  return "0" if x == ~0.0
  if x == x.floor && x.abs < ~1.0e21
    return x.to_i.to_s
  s = js_shortest(x)
  s

# Shortest round-trip digits by trying increasing precision (correct, not fast).
-> js_shortest(x)
  p = 1
  while p <= 17
    s = js_format_sig(x, p)
    return s if s.to_f == x
    p += 1
  x.to_s

# x with p significant digits, in JavaScript's notation (exponent form outside 1e-7 .. 1e21).
-> js_format_sig(x, p)
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  e = Math.log10(a).floor
  scaled = a / (~10.0 ** (e - p + 1))
  digits = scaled.round.to_i
  if digits >= 10 ** p
    digits = digits / 10
    e += 1
  ds = digits.to_s
  while ds.size > 1 && ds.ends_with?("0")
    ds = ds.slice(0, ds.size - 1)
  k = ds.size
  n = e + 1
  if k <= n && n <= 21
    out = ds + "0" * (n - k)
  elsif 0 < n && n <= 21
    out = ds.slice(0, n) + "." + ds.slice(n, k - n)
  elsif -6 < n && n <= 0
    out = "0." + "0" * (0 - n) + ds
  else
    ex = n - 1
    sign = ex < 0 ? "-" : "+"
    exs = (ex < 0 ? 0 - ex : ex).to_s
    out = k == 1 ? ds + "e" + sign + exs : ds.slice(0, 1) + "." + ds.slice(1, k - 1) + "e" + sign + exs
  neg ? "-" + out : out

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

-> js_trim(s)
  a = 0
  b = s.size
  while a < b && (JS_WS.include?(s.byte_at(a)) || js_unicode_space_at?(s, a))
    a += js_unicode_space_at?(s, a) ? js_unicode_space_len(s, a) : 1
  while b > a && JS_WS.include?(s.byte_at(b - 1))
    b -= 1
  s.slice(a, b - a)

# U+00A0, U+FEFF, U+2028/2029 and the Zs spaces are whitespace in JS too.
-> js_unicode_space_at?(s, i)
  b = s.byte_at(i)
  return s.slice(i, 2) == " " if b == 0xC2
  if b == 0xE2 || b == 0xEF || b == 0xE3 || b == 0xE1
    t = s.slice(i, 3)
    return t == " " || t == " " || t == "﻿" || t == "　" || t == " " || t == " " || t == " " || (t >= " " && t <= " ")
  false

-> js_unicode_space_len(s, i)
  s.byte_at(i) == 0xC2 ? 2 : 3


# ---- conversions (§7.1) ----

-> js_to_primitive(v, hint = "default")
  return v if !v.is_a?(JsObject)
  ex = v.get(SYM_TO_PRIMITIVE)
  if ex != nil && ex != JS_NULL
    r = js_call(ex, v, [hint])
    js_throw_type("Cannot convert object to primitive value") if r.is_a?(JsObject)
    return r
  order = hint == "string" ? ["toString", "valueOf"] : ["valueOf", "toString"]
  order.each ->(name)
    m = v.get(name)
    if m.is_a?(JsFunction)
      r = js_call(m, v, [])
      return r if !r.is_a?(JsObject)
  js_throw_type("Cannot convert object to primitive value")

-> js_to_boolean(v)
  return false if v == nil || v == JS_NULL || v == false
  return true if v == true
  return !(v == ~0.0 || v != v) if v.is_a?(Float)
  return v.size > 0 if v.is_a?(String)
  return v.v != 0 if v.is_a?(JsBigInt)
  true

-> js_to_number(v)
  return v if v.is_a?(Float)
  return js_nan() if v == nil
  return ~0.0 if v == JS_NULL || v == false
  return ~1.0 if v == true
  return js_string_to_number(v) if v.is_a?(String)
  js_throw_type("Cannot convert a Symbol value to a number") if v.is_a?(JsSymbol)
  js_throw_type("Cannot convert a BigInt value to a number") if v.is_a?(JsBigInt)
  return v + ~0.0 if v.is_a?(Integer)
  js_to_number(js_to_primitive(v, "number"))

-> js_to_numeric(v)
  p = js_to_primitive(v, "number")
  return p if p.is_a?(JsBigInt)
  js_to_number(p)

# ToIntegerOrInfinity
-> js_to_integer(v)
  n = js_to_number(v)
  return ~0.0 if n != n
  return n if n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
  n < ~0.0 ? ~0.0 - (~0.0 - n).floor : n.floor

-> js_to_int32(v)
  n = js_to_number(v)
  return 0 if n != n || n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
  i = (n < ~0.0 ? ~0.0 - (~0.0 - n).floor : n.floor)
  m = (i % ~4294967296.0)
  m = m + ~4294967296.0 if m < ~0.0
  r = m.to_i
  r >= 2147483648 ? r - 4294967296 : r

-> js_to_uint32(v)
  r = js_to_int32(v)
  r < 0 ? r + 4294967296 : r

-> js_to_string(v)
  return v if v.is_a?(String)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "true" if v == true
  return "false" if v == false
  return js_number_to_s(v) if v.is_a?(Float)
  return v.v.to_s if v.is_a?(JsBigInt)
  js_throw_type("Cannot convert a Symbol value to a string") if v.is_a?(JsSymbol)
  return js_number_to_s(v + ~0.0) if v.is_a?(Integer)
  js_to_string(js_to_primitive(v, "string"))

-> js_to_property_key(v)
  return v if v.is_a?(String)
  return v if v.is_a?(JsSymbol)
  if v.is_a?(Float) && v == v.floor && v >= ~0.0 && v < ~4294967295.0
    return v.to_i.to_s
  p = js_to_primitive(v, "string")
  return p if p.is_a?(JsSymbol)
  js_to_string(p)

-> js_array_index?(k)
  n = k.size
  return false if n == 0 || n > 10
  return k == "0" if k.byte_at(0) == 48
  i = 0
  while i < n
    b = k.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  n < 10 || k <= "4294967294"

-> js_to_object(v)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(v)
  return v if v.is_a?(JsObject)
  JS_REALM[0].wrap_primitive(v)

-> js_key_display(k)
  k.is_a?(JsSymbol) ? k.to_s : k

# A short human rendering for error messages and console output.
-> js_to_display(v)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "\"" + v + "\"" if v.is_a?(String) && v.size < 60
  return js_number_to_s(v) if v.is_a?(Float)
  return v.to_s if v.is_a?(JsSymbol)
  return v.v.to_s + "n" if v.is_a?(JsBigInt)
  return v.to_s if v == true || v == false
  if v.is_a?(JsFunction)
    return "function " + v.fname.to_s
  return "[object " + v.cls + "]" if v.is_a?(JsObject)
  v.to_s


# ---- equality (§7.2) ----

-> js_same_value(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return true if a != a && b != b
    return false if a == ~0.0 && b == ~0.0 && (~1.0 / a) != (~1.0 / b)
    return a == b
  js_strict_eq(a, b)

-> js_same_value_zero(a, b)
  return true if a.is_a?(Float) && b.is_a?(Float) && a != a && b != b
  js_strict_eq(a, b)

-> js_strict_eq(a, b)
  return a == b if a.is_a?(Float) && b.is_a?(Float)
  return a == b if a.is_a?(String) && b.is_a?(String)
  return a.v == b.v if a.is_a?(JsBigInt) && b.is_a?(JsBigInt)
  return false if a.is_a?(Float) || b.is_a?(Float) || a.is_a?(String) || b.is_a?(String)
  a.equal?(b) || (a == nil && b == nil) || (a == true && b == true) || (a == false && b == false)

-> js_loose_eq(a, b)
  ta = js_typeof(a)
  tb = js_typeof(b)
  ta = "object" if ta == "function"
  tb = "object" if tb == "function"
  if ta == tb && !(a == JS_NULL || b == JS_NULL) || (a == JS_NULL && b == JS_NULL)
    return js_strict_eq(a, b)
  return true if js_nullish?(a) && js_nullish?(b)
  return false if js_nullish?(a) || js_nullish?(b)
  return js_loose_eq(a, js_string_to_number(b)) if ta == "number" && tb == "string"
  return js_loose_eq(js_string_to_number(a), b) if ta == "string" && tb == "number"
  if ta == "bigint" && tb == "string"
    n = js_string_to_number(b)
    return n == n && n == n.floor && a.v == n.to_i
  return js_loose_eq(b, a) if ta == "string" && tb == "bigint"
  return js_loose_eq(js_to_number(a), b) if ta == "boolean"
  return js_loose_eq(a, js_to_number(b)) if tb == "boolean"
  return js_loose_eq(a, js_to_primitive(b)) if (ta == "number" || ta == "string" || ta == "bigint" || ta == "symbol") && tb == "object"
  return js_loose_eq(js_to_primitive(a), b) if ta == "object" && (tb == "number" || tb == "string" || tb == "bigint" || tb == "symbol")
  if (ta == "bigint" && tb == "number") || (ta == "number" && tb == "bigint")
    n = ta == "number" ? a : b
    bi = ta == "bigint" ? a : b
    return false if n != n || n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
    return n == n.floor && bi.v == n.to_i
  false
