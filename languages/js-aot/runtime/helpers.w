# runtime/helpers — abstract operations the builtins share (ported from Blade's engine:
# blade/js/realm.w, value.w, ops.w, runtime.w): the well-known symbols, the iteration
# protocol (§7.4), calls and construction with argument Arrays, UTF-16 string helpers,
# and small conversions.

in JS

# ---- well-known symbols (SYM_ITERATOR and SYM_TO_PRIMITIVE are in realm.w) ----

SYM_ASYNC_ITERATOR = JS:Symbol.new("Symbol.asyncIterator")
SYM_TO_STRING_TAG = JS:Symbol.new("Symbol.toStringTag")
SYM_HAS_INSTANCE = JS:Symbol.new("Symbol.hasInstance")
SYM_SPECIES = JS:Symbol.new("Symbol.species")
SYM_UNSCOPABLES = JS:Symbol.new("Symbol.unscopables")
SYM_IS_CONCAT_SPREADABLE = JS:Symbol.new("Symbol.isConcatSpreadable")
SYM_MATCH = JS:Symbol.new("Symbol.match")
SYM_MATCH_ALL = JS:Symbol.new("Symbol.matchAll")
SYM_REPLACE = JS:Symbol.new("Symbol.replace")
SYM_SEARCH = JS:Symbol.new("Symbol.search")
SYM_SPLIT = JS:Symbol.new("Symbol.split")

INF = ~1.0 / ~0.0
NEG_INF = ~-1.0 / ~0.0
TWO32 = ~4294967296.0

# ---- the iteration protocol (§7.4) ----

+ IterRecord
  rw :iterator, :next_fn, :done
  -> new(@iterator, @next_fn)
    @done = false

-> js_get_iterator(v, async_kind = false)
  m = nil
  if async_kind
    m = js_get_method(v, SYM_ASYNC_ITERATOR)
  m = js_get_method(v, SYM_ITERATOR) if m == nil
  js_throw_type(js_to_display_short(v) + " is not iterable") if m == nil
  it = js_call_arr(m, v, JS_NO_ARGS)
  js_throw_type("Result of the Symbol.iterator method is not an object") if !js_object?(it)
  JS:IterRecord.new(it, jget(it, "next"))

# GetMethod: nil when undefined or null.
-> js_get_method(v, key)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(v)
  f = js_get_value(v, key)
  return nil if js_nullish?(f)
  js_throw_type(js_to_display(js_key_display(key)) + " is not a function") if !js_callable?(f)
  f

# The next value, or JS_ITER_DONE.
+ IterDone
  -> new
    nil
JS_ITER_DONE = JS:IterDone.new

-> js_iter_step(rec)
  r = js_call_arr(rec.next_fn, rec.iterator, JS_NO_ARGS)
  js_throw_type("Iterator result is not an object") if !js_object?(r)
  if js_truthy(jget(r, "done"))
    rec.done = true
    return JS_ITER_DONE
  jget(r, "value")

-> js_iter_close(rec)
  return nil if rec.done
  rec.done = true
  ret = js_get_method(rec.iterator, "return")
  if ret != nil
    r = js_call_arr(ret, rec.iterator, JS_NO_ARGS)
    js_throw_type("Iterator result is not an object") if !js_object?(r)
  nil

# IteratorClose for an abrupt completion that is a throw: errors from return() are
# swallowed so the original exception wins.
-> js_iter_close_quiet(rec)
  return nil if rec.done
  rec.done = true
  begin
    ret = js_get_method(rec.iterator, "return")
    js_call_arr(ret, rec.iterator, JS_NO_ARGS) if ret != nil
  rescue e
    nil
  nil

# Is iteration of this array still the built-in one (no user override)? Before the
# iterator builtins are installed every array counts as pristine.
-> js_array_iter_pristine?(a)
  r = js_realm()
  return false if js_array_proto(a) != r.array_proto
  if (js_array_flags(a) & JS_AF_EXT) != 0
    return false if js_array_ext(a, false).has_own?(SYM_ITERATOR)
  v = r.intrinsics["%ArrayProto_values%"]
  return true if v == nil
  return false if r.array_proto.get_own(SYM_ITERATOR) != v
  aip = r.intrinsics["%ArrayIteratorPrototype%"]
  aip == nil || aip.get_own("next") == r.intrinsics["%ArrayIteratorProto_next%"]

-> js_string_iter_pristine?
  r = js_realm()
  f = r.intrinsics["%StringProto_iterator%"]
  return true if f == nil
  return false if r.string_proto.get_own(SYM_ITERATOR) != f
  sip = r.intrinsics["%StringIteratorPrototype%"]
  sip == nil || sip.get_own("next") == r.intrinsics["%StringIteratorProto_next%"]

# Element i of an array as its iterator reads it: the dense slot, else [[Get]] (holes
# read through the prototype chain).
-> js_arr_elem(v, i)
  if i < v.size
    x = v[i]
    return x if x != JS_HOLE
  js_array_get(v, i.to_s)

# Iterate a JS iterable with a Tungsten block; the iterator is closed if the block raises.
# (A block costs a closure: hot callers inline the loop instead.)
-> js_for_of(v, f)
  # fast path: plain arrays whose iterator is the intrinsic one
  if js_array?(v) && js_array_iter_pristine?(v)
    i = 0
    while i < v.size
      f.call(js_arr_elem(v, i))
      i += 1
    return nil
  rec = js_get_iterator(v)
  begin
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      f.call(x)
  rescue e
    js_iter_close_quiet(rec) if !rec.done
    raise e
  nil

-> js_iter_result(value, done)
  o = js_new_object(js_realm().object_proto)
  o.put_own("value", value)
  o.put_own("done", done)
  o

# A JS array → Tungsten Array of values (holes as undefined); other iterables via the
# protocol.
-> js_to_list(v)
  out = []
  js_append_iterable(out, v)
  out

# ...v appended to the Tungsten Array out (spread, rest, Array.from): arrays and ASCII
# strings with the built-in iterators take a loop, anything else the protocol.
-> js_append_iterable(out, v)
  if js_array?(v) && js_array_iter_pristine?(v)
    i = 0
    while i < v.size
      out.push(js_arr_elem(v, i))
      i += 1
    return out
  if js_string?(v) && v.ascii? && js_string_iter_pristine?()
    i = 0
    while i < v.size
      out.push(v.slice(i, 1))
      i += 1
    return out
  rec = js_get_iterator(v)
  begin
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      out.push(x)
  rescue e
    js_iter_close_quiet(rec) if !rec.done
    raise e
  out

# ---- bound functions (Function.prototype.bind) ----

# @shape @ext @target @bthis @args + three inline slots (name and length are real
# properties, defined when bound).
+ BoundFunction < JS:Base
  rw :target, :bthis, :args, :s0, :s1, :s2

  -> new(@shape, @target, @bthis, @args)
    @ext = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_BOUND)

  -> callable?
    true

  -> constructor?
    js_is_constructor?(@target)

  -> construct(args, nt)
    js_construct(@target, @args + args, nt == self ? @target : nt)

BF_IBASE = 5
BF_INLINE = 3

-> js_bound_function(target, bthis, args)
  p = jproto(target)
  JS:BoundFunction.new(js_root_shape(p, BF_INLINE, BF_IBASE), target, bthis, args)

# ---- calls and construction with argument Arrays ----

-> js_call_named(f, this, args, what)
  js_throw_type(what + " is not a function") if !js_callable?(f)
  js_call_arr(f, this, args)

-> js_construct_named(f, args, what)
  js_throw_type(what + " is not a constructor") if !js_is_constructor?(f)
  js_construct(f, args, nil)

# A compiled function's entry with an argument Array (no kind checks).
-> js_call_arr_entry(f, this, args)
  n = args.size
  js_dispatch(f.code.index, f, this, n, n > 0 ? args[0] : nil, n > 1 ? args[1] : nil, n > 2 ? args[2] : nil, n > 3 ? args[3] : nil, n > 4 ? args : nil)

# ---- errors ----

-> js_type_error(msg)
  js_make_error("TypeError", msg)

-> js_range_error(msg)
  js_make_error("RangeError", msg)

-> js_reference_error(msg)
  js_make_error("ReferenceError", msg)

-> js_syntax_error(msg)
  js_make_error("SyntaxError", msg)

-> js_throw_syntax(msg)
  js_throw(js_syntax_error(msg))

-> js_throw_value(v)
  js_throw(v)

-> js_set_failed(o, k)
  js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(k)) + "' of " + (js_object?(o) ? "object" : js_typeof(o)))

# ---- conversions ----

-> js_to_boolean(v)
  js_truthy(v)

-> js_f(i)
  i + ~0.0

-> js_i32(v)
  js_to_int32(v)

-> js_u32(v)
  js_to_uint32(v)

-> js_wrap32(i)
  m = i & 4294967295
  m >= 2147483648 ? m - 4294967296 : m

-> js_is_nan?(x)
  js_number?(x) && x != x

# Keeps a value's static type dynamic (see blade/js/value.w: a Float tail on a path that
# also returns objects once made compiled code expect a Float).
-> js_dyn(x)
  x

-> js_numeric_value(v)
  p = js_to_primitive(v, "number")
  return p if p.is_a?(JS:BigIntValue) || js_number?(p)
  js_dyn(js_to_number(p))

# ToIntegerOrInfinity
-> js_to_integer(v)
  n = js_to_number(v)
  return ~0.0 if n != n
  return n if n == INF || n == NEG_INF
  n < ~0.0 ? ~0.0 - Math.floor(~0.0 - n) : Math.floor(n)

# ToObject (§7.1.18): primitives become their wrapper objects.
-> js_to_obj(v)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(v)
  return v if js_object?(v)
  js_realm().wrap_primitive(v)

-> js_same_value_zero(a, b)
  return true if js_number?(a) && js_number?(b) && a != a && b != b
  js_strict_eq(a, b)

# CreateDataPropertyOrThrow
-> js_create_data(o, k, v)
  ok = jdefine_own_property(o, k, JS:PropDesc.data(v, ATTR_ALL))
  if !ok
    js_throw_type("Cannot add property " + js_to_display(js_key_display(k)) + ", object is not extensible") if !jhas_own?(o, k)
    js_throw_type("Cannot redefine property: " + js_to_display(js_key_display(k)))
  v

# ---- strings (UTF-16 view over UTF-8) ----

# One code point as UTF-8 (WTF-8 for lone surrogates).
-> js_cp_str(cp)
  cp == 0 ? "\0" : cp.chr

-> js_hexv(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 87 if b >= 97 && b <= 102
  return b - 55 if b >= 65 && b <= 70
  -1

-> js_ascii?(s)
  s.ascii?

# UTF-16 code units of s, as an Array of Ints. The last two conversions are cached, so a
# loop over charCodeAt(i) of one non-ASCII string converts it once.
# TODO(js-aot): per thread once workers run JS.
JS_UNITS_CACHE = [nil, nil, nil, nil]

-> js_units(s)
  c = JS_UNITS_CACHE
  return c[1] if c[0] != nil && c[0] == s
  return c[3] if c[2] != nil && c[2] == s
  u = js_units_raw(s)
  c[2] = c[0]
  c[3] = c[1]
  c[0] = s
  c[1] = u
  u

-> js_units_raw(s)
  out = []
  n = s.size
  i = 0
  while i < n
    b = s.byte_at(i)
    if b < 128
      out.push(b)
      i += 1
    elsif b < 224 && i + 1 < n
      out.push(((b & 31) << 6) | (s.byte_at(i + 1) & 63))
      i += 2
    elsif b < 240 && i + 2 < n
      out.push(((b & 15) << 12) | ((s.byte_at(i + 1) & 63) << 6) | (s.byte_at(i + 2) & 63))
      i += 3
    elsif i + 3 < n
      cp = ((b & 7) << 18) | ((s.byte_at(i + 1) & 63) << 12) | ((s.byte_at(i + 2) & 63) << 6) | (s.byte_at(i + 3) & 63)
      c = cp - 65536
      out.push(55296 + (c >> 10))
      out.push(56320 + (c & 1023))
      i += 4
    else
      out.push(65533)
      i += 1
  out

-> js_len(s)
  return s.size if s.ascii?
  js_units(s).size

# The code unit at i as a number, or nil out of range.
-> js_unit_at(s, i)
  if s.ascii?
    return nil if i < 0 || i >= s.size
    return s.byte_at(i) + ~0.0
  u = js_units(s)
  return nil if i < 0 || i >= u.size
  u[i] + ~0.0

# Code units → String (a lone surrogate stays as its WTF-8 bytes).
-> js_from_units(u)
  sb = StringBuffer()
  i = 0
  while i < u.size
    c = u[i]
    if c >= 55296 && c <= 56319 && i + 1 < u.size && u[i + 1] >= 56320 && u[i + 1] <= 57343
      cp = 65536 + ((c - 55296) << 10) + (u[i + 1] - 56320)
      sb.append(js_cp_str(cp))
      i += 2
    else
      sb.append(js_cp_str(c))
      i += 1
  sb.to_s

# s.substring(a, b) in UTF-16 units.
-> js_substring(s, a, b)
  return "" if b <= a
  return s.slice(a, b - a) if s.ascii?
  u = js_units(s)
  js_from_units(u.slice(a, b - a))

-> js_char_at(s, i)
  return s.slice(i, 1) if s.ascii?
  u = js_units(s)
  return "" if i < 0 || i >= u.size
  js_from_units([u[i]])

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
      return a.slice(0, na - 3) + js_cp_str(cp) + b.slice(3, b.size - 3)
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

# ---- objects ----

# Identity (for JS arrays too, which core == compares by contents).
-> js_ident?(a, b)
  (wvalue_bits(a) ## i64) == (wvalue_bits(b) ## i64)

# cls / internal of a JS:Special; nil for any other value.
-> js_cls(o)
  o.is_a?(JS:Special) ? o.cls : nil

-> js_internal(o)
  o.is_a?(JS:Special) ? o.internal : nil

-> js_special?(o, cls)
  o.is_a?(JS:Special) && o.cls == cls

# The target of a Proxy (b_reflect.w).
-> js_proxy_target(p)
  p.proxy_target

# ---- regular expressions ----

# IsRegExp (§7.2.8)
-> js_is_regexp?(v)
  return false if !js_object?(v)
  m = jget(v, SYM_MATCH)
  return js_truthy(m) if m != nil
  js_special?(v, "RegExp")

# A regex literal /pattern/flags (stand-in until runtime/regexp.w lands).
-> js_regexp_create(pattern, flags)
  js_throw_syntax("RegExp is not available yet: /" + pattern + "/" + flags)
