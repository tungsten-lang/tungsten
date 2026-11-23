# runtime/array — JS arrays are core Arrays (polymorphic, ebits 65) marked as JS arrays
# in the spare header byte (WArray._pad[0], jsr_aflags): one allocation and core speed
# for indexing, push, pop and the rest, with the JS semantics keyed off the flags.
#
#   JS_AF_ARRAY   it is a JS array (a core Array without it is engine-internal)
#   JS_AF_HOLES   it may contain JS_HOLE; when clear, an in-bounds read needs no check
#   JS_AF_EXT     it has an entry in JS_AEXT: named properties, a non-default prototype,
#                 sparse elements or a non-writable length, kept in a JS:Object
#
# A core copy or dup of a JS array is an unflagged core Array, so engine-internal arrays
# never pass for JS ones by accident. (V8 tracks the same facts as elements kinds and a
# separate properties backing store; JSC calls them indexing types and the butterfly.)

in JS

JS_AF_ARRAY = 1
JS_AF_HOLES = 2
JS_AF_EXT = 4

# Side tables keyed by the array's bits; entries are created only for arrays that need one.
JS_AEXT = {}
JS_AEXT_KEEP = {}

# Mark a fresh core Array as a JS array (it must not be shared with engine code).
-> js_mark_array(a)
  jsr_set_aflags(wvalue_bits(a) ## i64, JS_AF_ARRAY)
  a

-> js_new_array(n)
  js_mark_array([])

-> js_array_flags(a)
  jsr_aflags(wvalue_bits(a) ## i64)

-> js_array_ext(a, create)
  ab = wvalue_bits(a) ## i64
  key = ab & 140737488355312   # the WArray pointer (fits an immediate Int)
  x = JS_AEXT[key]
  if x == nil && create
    x = js_new_object(nil)
    JS_AEXT[key] = x
    JS_AEXT_KEEP[key] = a
    jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_EXT)
  x

# The array's prototype: its realm's Array.prototype unless set otherwise.
-> js_array_proto(a)
  if (js_array_flags(a) & JS_AF_EXT) != 0
    x = js_array_ext(a, false)
    p = x.get_own("__proto__")
    return (p == JS_NULL ? nil : p) if p != JS_HOLE
  js_realm().array_proto

# a[i] for a number i (the caller has checked the array flag).
-> js_array_get_index(a, i)
  ix = jsr_index(wvalue_bits(i) ## i64)
  if ix >= 0
    r = jsr_aget(wvalue_bits(a) ## i64, ix)
    if r != JSR_SLOW
      v = wvalue_from_bits(r)
      return v if v != JS_HOLE
  js_array_get(a, js_to_property_key(i))

# a[key] for a property key.
-> js_array_get(a, key)
  if key.is_a?(String)
    if key == "length"
      return a.size.to_f
    if js_array_index?(key)
      i = key.to_i
      if i < a.size
        v = a[i]
        return v if v != JS_HOLE
      return js_proto_get(js_array_proto(a), key, a)
  if (js_array_flags(a) & JS_AF_EXT) != 0
    x = js_array_ext(a, false)
    i = x.shape.slot_of(key)
    return x.get(key, a) if i >= 0
  js_proto_get(js_array_proto(a), key, a)

-> js_proto_get(p, key, receiver)
  return nil if p == nil
  p.get(key, receiver)

# a[key] = v. Returns true when the write took effect.
-> js_array_set(a, key, v)
  if js_number?(key)
    ix = jsr_index(wvalue_bits(key) ## i64)
    if ix >= 0
      return js_array_set_index(a, ix, v)
    key = js_to_property_key(key)
  if key.is_a?(String)
    if key == "length"
      return js_array_set_length(a, v)
    if js_array_index?(key)
      return js_array_set_index(a, key.to_i, v)
  js_array_ext(a, true).set(key, v, js_array_ext(a, true))
  true

ARRAY_GAP = 65536

-> js_array_set_index(a, i, v)
  n = a.size
  if i < n
    a[i] = v
    return true
  if i == n
    a.push(v)
    return true
  js_throw_range("Array index far past the end is not supported yet") if i - n > ARRAY_GAP
  while a.size < i
    a.push(JS_HOLE)
  a.push(v)
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
  true

-> js_array_set_length(a, v)
  n = js_to_number(v)
  len = js_to_uint32(n)
  js_throw_range("Invalid array length") if len.to_f != n
  while a.size > len
    a.pop
  if a.size < len
    js_throw_range("Array length far past the end is not supported yet") if len - a.size > ARRAY_GAP
    while a.size < len
      a.push(JS_HOLE)
    ab = wvalue_bits(a) ## i64
    jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
  true

-> js_array_own_keys(a)
  out = []
  i = 0
  while i < a.size
    out.push(i.to_s) if a[i] != JS_HOLE
    i += 1
  out.push("length")
  if (js_array_flags(a) & JS_AF_EXT) != 0
    js_array_ext(a, false).own_keys.each ->(k) out.push(k) if k != "__proto__"
  out
