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

# Engine-only keys in an array's side object (private names never show as properties).
JS_AK_PROTO = JS:PrivateName.new("proto")
JS_AK_LENRO = JS:PrivateName.new("length-read-only")
JS_AK_SEALED = JS:PrivateName.new("sealed")
JS_AK_FROZEN = JS:PrivateName.new("frozen")

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
    p = x.get_own(JS_AK_PROTO)
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
    js_array_ext(a, false).own_keys.each ->(k) out.push(k)
  out

# ---- the array exotic object's internal methods (§10.4.2) ----

-> js_array_get_own(a, key)
  if key.is_a?(String)
    return a.size.to_f if key == "length"
    if js_array_index?(key)
      i = key.to_i
      return i < a.size && a[i] != JS_HOLE ? a[i] : JS_HOLE
  return JS_HOLE if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own(key)

-> js_array_has_own?(a, key)
  js_array_get_own(a, key) != JS_HOLE

-> js_array_get_own_property(a, key)
  if key.is_a?(String)
    if key == "length"
      return JS:PropDesc.data(a.size.to_f, js_array_length_writable?(a) ? ATTR_W : 0)
    if js_array_index?(key)
      i = key.to_i
      return nil if i >= a.size || a[i] == JS_HOLE
      return JS:PropDesc.data(a[i], js_array_frozen?(a) ? ATTR_E : (js_array_sealed?(a) ? ATTR_E + ATTR_W : ATTR_DEFAULT))
  return nil if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own_property(key)

-> js_array_length_writable?(a)
  return true if (js_array_flags(a) & JS_AF_EXT) == 0
  x = js_array_ext(a, false)
  x.get_own(JS_AK_LENRO) == JS_HOLE

-> js_array_sealed?(a)
  return false if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own(JS_AK_SEALED) != JS_HOLE

-> js_array_frozen?(a)
  return false if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own(JS_AK_FROZEN) != JS_HOLE

-> js_array_define(a, key, v, flags = ATTR_DEFAULT)
  d = JS:PropDesc.data(v, flags)
  js_array_define_own_property(a, key, d)
  v

-> js_array_define_own_property(a, key, d)
  if key.is_a?(String)
    if key == "length"
      return false if d.accessor?
      if d.has_value
        n = js_to_number(d.value)
        len = js_to_uint32(n)
        js_throw_range("Invalid array length") if len.to_f != n
        return false if len != a.size && !js_array_length_writable?(a)
        js_array_set_length(a, d.value)
      if d.writable == false
        js_array_ext(a, true).define(JS_AK_LENRO, true, 0)
      return true
    if js_array_index?(key)
      i = key.to_i
      if d.accessor? || (d.writable == false) || (d.enumerable == false) || (d.configurable == false)
        # non-default attributes on an element: elements no longer fit the dense store
        js_throw_type("Array element with non-default attributes is not supported yet")
      return false if i >= a.size && !js_array_length_writable?(a)
      js_array_set_index(a, i, d.has_value ? d.value : (i < a.size && a[i] != JS_HOLE ? a[i] : nil))
      return true
  js_array_ext(a, true).define_own_property(key, d)

-> js_array_set_proto(a, p)
  p = nil if p == JS_NULL
  return true if p == js_array_proto(a)
  js_array_ext(a, true).put_own(JS_AK_PROTO, p == nil ? JS_NULL : p)
  true
