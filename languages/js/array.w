# runtime/array — JS arrays are core Arrays (polymorphic, ebits 65) marked as JS arrays
# in the spare header byte (WArray._pad[0], jsr_aflags): one allocation and core speed
# for indexing, push, pop and the rest, with the JS semantics keyed off the flags.
#
#   JS_AF_ARRAY   it is a JS array (a core Array without it is engine-internal)
#   JS_AF_HOLES   it may contain JS_HOLE; when clear, an in-bounds read needs no check
#   JS_AF_EXT     it has an entry in JS_AEXT: named properties, a non-default prototype,
#                 sparse elements or a non-writable length, kept in a JS:Object
#
# Elements with non-default attributes (accessors, read-only, non-enumerable or
# non-configurable ones) live in the side object under their index keys, with a hole in
# the dense store so every fast path misses on them (V8's dictionary elements, roughly).
#
# A core copy or dup of a JS array is an unflagged core Array, so engine-internal arrays
# never pass for JS ones by accident. (V8 tracks the same facts as elements kinds and a
# separate properties backing store; JSC calls them indexing types and the butterfly.)

in JS

JS_AF_ARRAY = 1
JS_AF_HOLES = 2
JS_AF_EXT = 4
JS_AF_SPARSE = 8

# Engine-only keys in an array's side object (private names never show as properties).
JS_AK_PROTO = JS:PrivateName.new("proto")
JS_AK_LENRO = JS:PrivateName.new("length-read-only")
JS_AK_SEALED = JS:PrivateName.new("sealed")
JS_AK_FROZEN = JS:PrivateName.new("frozen")
JS_AK_LEN = JS:PrivateName.new("sparse-length")

SPARSE_GAP = 65536

# Side tables keyed by the array's bits; entries are created only for arrays that need one.
JS_AEXT = {}
JS_AEXT_KEEP = {}
JS_MULTI_REALM = [false]
JS_ARR_REALM_PROTO = {}

# Mark a fresh core Array as a JS array (it must not be shared with engine code).
-> js_mark_array(a)
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, JS_AF_ARRAY)
  if JS_MULTI_REALM[0] && JS_REALM[0] != nil
    JS_ARR_REALM_PROTO[ab & 140737488355312] = JS_REALM[0].array_proto
  JS_GC_ON[0] ? js_gc_reg(a) : a

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
  if JS_MULTI_REALM[0]
    ap = JS_ARR_REALM_PROTO[(wvalue_bits(a) ## i64) & 140737488355312]
    return ap if ap != nil
    return JS_FIRST_REALM[0].array_proto if JS_FIRST_REALM[0] != nil
  js_realm().array_proto

# a[i] for a number i (the caller has checked the array flag).
-> js_array_get_index(a, i)
  ix = jsr_index(wvalue_bits(i) ## i64)
  if ix >= 0
    r = jsr_aget(wvalue_bits(a) ## i64, ix)
    if r != (6 ## i64)
      v = wvalue_from_bits(r)
      return v if v != JS_HOLE
  js_array_get(a, js_to_property_key(i))

-> js_arr_len(a)
  return a.size if (js_array_flags(a) & JS_AF_SPARSE) == 0
  js_array_ext(a, false).get_own(JS_AK_LEN)

-> js_array_make_sparse(a, new_len)
  x = js_array_ext(a, true)
  x.put_own(JS_AK_LEN, new_len)
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_SPARSE | JS_AF_HOLES)
  x

-> js_sort_ints_asc(arr)
  i = 1
  while i < arr.size
    v = arr[i]
    j = i - 1
    while j >= 0 && arr[j] > v
      arr[j + 1] = arr[j]
      j -= 1
    arr[j + 1] = v
    i += 1
  arr

-> js_sort_ints_desc(arr)
  i = 1
  while i < arr.size
    v = arr[i]
    j = i - 1
    while j >= 0 && arr[j] < v
      arr[j + 1] = arr[j]
      j -= 1
    arr[j + 1] = v
    i += 1
  arr

-> js_array_sparse_indices(a)
  out = []
  x = (js_array_flags(a) & JS_AF_EXT) != 0 ? js_array_ext(a, false) : nil
  i = 0
  while i < a.size
    if a[i] != JS_HOLE
      out.push(i)
    elsif x != nil && x.has_own?(i.to_s)
      out.push(i)
    i += 1
  if x != nil && (js_array_flags(a) & JS_AF_SPARSE) != 0
    extra = []
    ks = x.own_keys
    j = 0
    while j < ks.size
      k = ks[j]
      if k.is_a?(String) && js_array_index?(k)
        idx = k.to_i
        extra.push(idx) if idx >= a.size
      j += 1
    js_sort_ints_asc(extra)
    j = 0
    while j < extra.size
      out.push(extra[j])
      j += 1
  out

# a[key] for a property key.
-> js_array_get(a, key, receiver = JS_HOLE)
  r = receiver == JS_HOLE ? a : receiver
  if key.is_a?(String)
    if key == "length"
      return js_arr_len(a).to_f
    if js_array_index?(key)
      i = key.to_i
      if i < a.size
        v = a[i]
        return v if v != JS_HOLE
      x = js_array_slow_elem(a, key)
      return x.get(key, r) if x != nil
      return js_proto_get(js_array_proto(a), key, r)
  if (js_array_flags(a) & JS_AF_EXT) != 0
    x = js_array_ext(a, false)
    i = x.shape.slot_of(key)
    return x.get(key, r) if i >= 0
  js_proto_get(js_array_proto(a), key, r)

-> js_proto_get(p, key, receiver)
  return nil if p == nil
  return js_array_get(p, key, receiver) if js_array?(p)
  p.get(key, receiver)

# a[key] = v. Returns true when the write took effect.
-> js_array_set(a, key, v)
  if js_number?(key)
    ix = jsr_index(wvalue_bits(key) ## i64)
    if ix >= 0
      return js_array_set_index(a, ix, v, false)
    key = js_to_property_key(key)
  elsif !key.is_a?(String) && !key.is_a?(JS:Symbol)
    key = js_to_property_key(key)
  if key.is_a?(String)
    if key == "length"
      return js_array_set_length(a, v, true)
    if js_array_index?(key)
      return js_array_set_index(a, key.to_i, v, false)
  if (js_array_flags(a) & JS_AF_EXT) != 0
    x0 = js_array_ext(a, false)
    return x0.set(key, v, a) if x0.has_own?(key)
  p = js_array_proto(a)
  while p != nil
    if !js_array?(p) && p.exotic?
      return p.set(key, v, a)
    d = jget_own_property(p, key)
    if d != nil
      if d.accessor?
        return false if d.setter == nil
        js_call_arr(d.setter, a, [v])
        return true
      return false if d.writable != true
      break
    p = jproto(p)
  x = js_array_ext(a, true)
  return false if !x.is_extensible?
  x.define(key, v, ATTR_DEFAULT)
  true

ARRAY_GAP = 16777216

-> js_array_set_index(a, i, v, is_define = false)
  n = a.size
  flags = js_array_flags(a)
  sparse = (flags & JS_AF_SPARSE) != 0
  cur_len = sparse ? js_array_ext(a, false).get_own(JS_AK_LEN) : n
  if !is_define && JS_PROTO_INDEX[0] && (i >= n || a[i] == JS_HOLE)
    r = js_array_hole_set(a, i, v)
    return r if r != nil
  if (flags & JS_AF_EXT) != 0
    # frozen: no element is writable; not extensible (sealed too): no element is added
    return false if !is_define && js_array_frozen?(a)
    if i >= n || a[i] == JS_HOLE
      x = js_array_ext(a, false)
      k = i.to_s
      return js_array_set_slow(a, x, k, v) if !is_define && x.has_own?(k)
      return false if !x.is_extensible? || (i >= cur_len && !js_array_length_writable?(a))
  if !sparse
    if i < n
      a[i] = v
      return true
    if i == n
      a.push(v)
      return true
    if i - n <= SPARSE_GAP
      while a.size < i
        a.push(JS_HOLE)
      a.push(v)
      ab = wvalue_bits(a) ## i64
      jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
      return true
    x = js_array_make_sparse(a, i + 1)
    x.define(i.to_s, v, ATTR_DEFAULT)
    return true
  if i < n
    a[i] = v
    return true
  x = js_array_ext(a, true)
  x.define(i.to_s, v, ATTR_DEFAULT)
  x.put_own(JS_AK_LEN, i + 1) if i >= cur_len
  true

# OrdinarySet's walk for an element the array lacks: an inherited setter runs, an
# inherited read-only element refuses (false); nil when neither is found.
-> js_array_hole_set(a, i, v)
  k = i.to_s
  if (js_array_flags(a) & JS_AF_EXT) != 0 && js_array_ext(a, false).has_own?(k)
    return nil
  p = js_array_proto(a)
  while p != nil
    if !js_array?(p) && p.exotic?
      return p.set(k, v, a)
    d = jget_own_property(p, k)
    if d != nil
      if d.accessor?
        return false if d.setter == nil
        js_call_arr(d.setter, a, [v])
        return true
      return false if d.writable != true
      return nil
    p = jproto(p)
  nil

-> js_array_set_length(a, v, from_set = false)
  len = js_to_uint32(v)
  n = js_to_number(v)
  js_throw_range("Invalid array length") if len.to_f != n
  flags = js_array_flags(a)
  sparse = (flags & JS_AF_SPARSE) != 0
  old_len = sparse ? js_array_ext(a, false).get_own(JS_AK_LEN) : a.size
  if (flags & JS_AF_EXT) != 0
    if !js_array_length_writable?(a)
      return false if from_set || len != old_len
      return true
  if sparse
    x = js_array_ext(a, false)
    if len < old_len
      sidx = []
      ks = x.own_keys
      si = 0
      while si < ks.size
        k = ks[si]
        if k.is_a?(String) && js_array_index?(k)
          idx = k.to_i
          sidx.push(idx) if idx >= len && idx >= a.size
        si += 1
      js_sort_ints_desc(sidx)
      si = 0
      while si < sidx.size
        idx = sidx[si]
        if !x.delete_own(idx.to_s)
          x.put_own(JS_AK_LEN, idx + 1)
          return false
        si += 1
      if a.size > len
        sealed = js_array_sealed?(a)
        j = a.size - 1
        while j >= len
          if a[j] != JS_HOLE && sealed
            while a.size > j + 1
              a.pop
            x.put_own(JS_AK_LEN, j + 1)
            return false
          if a[j] == JS_HOLE
            k = j.to_s
            if x.has_own?(k) && !x.delete_own(k)
              while a.size > j + 1
                a.pop
              x.put_own(JS_AK_LEN, j + 1)
              return false
          j -= 1
        while a.size > len
          a.pop
    x.put_own(JS_AK_LEN, len)
    return true
  if (flags & JS_AF_EXT) != 0 && len < a.size
    x = js_array_ext(a, false)
    sealed = js_array_sealed?(a)
    j = a.size - 1
    while j >= len
      if a[j] != JS_HOLE && sealed
        while a.size > j + 1
          a.pop
        return false
      if a[j] == JS_HOLE
        k = j.to_s
        if x.has_own?(k) && !x.delete_own(k)
          while a.size > j + 1
            a.pop
          return false
      j -= 1
  while a.size > len
    a.pop
  if a.size < len
    if len - a.size > SPARSE_GAP
      js_array_make_sparse(a, len)
      return true
    while a.size < len
      a.push(JS_HOLE)
    ab = wvalue_bits(a) ## i64
    jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
  true

-> js_array_own_keys(a)
  out = []
  flags = js_array_flags(a)
  x = (flags & JS_AF_EXT) != 0 ? js_array_ext(a, false) : nil
  i = 0
  while i < a.size
    if a[i] != JS_HOLE
      out.push(i.to_s)
    elsif x != nil
      k = i.to_s
      out.push(k) if x.has_own?(k)
    i += 1
  if x != nil && (flags & JS_AF_SPARSE) != 0
    extra = []
    ks = x.own_keys
    j = 0
    while j < ks.size
      k = ks[j]
      if k.is_a?(String) && js_array_index?(k)
        idx = k.to_i
        extra.push(idx) if idx >= a.size
      j += 1
    js_sort_ints_asc(extra)
    j = 0
    while j < extra.size
      out.push(extra[j].to_s)
      j += 1
  out.push("length")
  if x != nil
    x.own_keys.each ->(k) out.push(k) if !(k.is_a?(String) && js_array_index?(k))
  out

# ---- the array exotic object's internal methods (§10.4.2) ----

-> js_array_get_own(a, key)
  if key.is_a?(String)
    return js_arr_len(a).to_f if key == "length"
    if js_array_index?(key)
      i = key.to_i
      return a[i] if i < a.size && a[i] != JS_HOLE
      x = js_array_slow_elem(a, key)
      return x == nil ? JS_HOLE : x.get_own(key)
  return JS_HOLE if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own(key)

-> js_array_has_own?(a, key)
  js_array_get_own(a, key) != JS_HOLE

-> js_array_get_own_property(a, key)
  if key.is_a?(String)
    if key == "length"
      return JS:PropDesc.data(js_arr_len(a).to_f, js_array_length_writable?(a) ? ATTR_W : 0)
    if js_array_index?(key)
      i = key.to_i
      return nil if i >= js_arr_len(a)
      if i < a.size && a[i] != JS_HOLE
        return JS:PropDesc.data(a[i], js_array_frozen?(a) ? ATTR_E : (js_array_sealed?(a) ? ATTR_E + ATTR_W : ATTR_DEFAULT))
      x = js_array_slow_elem(a, key)
      return x == nil ? nil : x.get_own_property(key)
  return nil if (js_array_flags(a) & JS_AF_EXT) == 0
  js_array_ext(a, false).get_own_property(key)

# The side object when it holds element key (one with non-default attributes), else nil.
-> js_array_slow_elem(a, key)
  return nil if (js_array_flags(a) & JS_AF_EXT) == 0
  x = js_array_ext(a, false)
  x.has_own?(key) ? x : nil

# a[i] = v on an element kept in the side object x.
-> js_array_set_slow(a, x, key, v)
  d = x.get_own_property(key)
  if d.accessor?
    return false if d.setter == nil
    js_call_arr(d.setter, a, [v])
    return true
  return false if d.writable != true
  nd = JS:PropDesc.new
  nd.value = v
  nd.has_value = true
  x.define_own_property(key, nd)

# Give element i non-default attributes: it moves to the side object.
-> js_array_define_slow(a, i, key, d)
  n = a.size
  flags = js_array_flags(a)
  sparse = (flags & JS_AF_SPARSE) != 0
  cur_len = sparse ? js_array_ext(a, false).get_own(JS_AK_LEN) : n
  exists = i < n && a[i] != JS_HOLE
  return false if !exists && i >= cur_len && !js_array_length_writable?(a)
  x = js_array_ext(a, true)
  if exists
    # (a failed redefinition of a sealed or frozen element leaves the same property)
    x.define(key, a[i], js_array_frozen?(a) ? ATTR_E : (js_array_sealed?(a) ? ATTR_E + ATTR_W : ATTR_DEFAULT))
  ok = x.define_own_property(key, d)
  return false if !ok && !exists
  if i < n
    a[i] = JS_HOLE
    ab = wvalue_bits(a) ## i64
    jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
    return ok
  if sparse || i - n > SPARSE_GAP
    js_array_make_sparse(a, i >= cur_len ? i + 1 : cur_len)
    return ok
  while a.size <= i
    a.push(JS_HOLE)
  a[i] = JS_HOLE
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
  ok

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
      # ArraySetLength (§10.4.2.4): the value is converted (ToUint32, then ToNumber) and
      # checked before the attributes
      len = -1
      if d.has_value
        len = js_to_uint32(d.value)
        n = js_to_number(d.value)
        js_throw_range("Invalid array length") if len.to_f != n
      # length is a non-configurable, non-enumerable data property
      return false if d.accessor? || d.configurable == true || d.enumerable == true
      return false if d.writable == true && !js_array_length_writable?(a)
      ok = true
      if len >= 0
        old_len = js_arr_len(a)
        return false if len != old_len && !js_array_length_writable?(a)
        ok = js_array_set_length(a, len.to_f, false) if len != old_len
      if d.writable == false
        js_array_ext(a, true).define(JS_AK_LENRO, true, 0)
      return ok
    if js_array_index?(key)
      i = key.to_i
      x = js_array_slow_elem(a, key)
      return x.define_own_property(key, d) if x != nil
      cur_len = js_arr_len(a)
      exists = i < a.size && a[i] != JS_HOLE
      if d.accessor? || (d.writable == false) || (d.enumerable == false) || (d.configurable == false) || (!exists && (d.writable != true || d.enumerable != true || d.configurable != true)) || (exists && (js_array_frozen?(a) || js_array_sealed?(a)))
        return js_array_define_slow(a, i, key, d)
      return false if i >= cur_len && !js_array_length_writable?(a)
      return js_array_set_index(a, i, d.has_value ? d.value : (exists ? a[i] : nil), true)
  js_array_ext(a, true).define_own_property(key, d)

-> js_array_set_proto(a, p)
  p = nil if p == JS_NULL
  return true if p == js_array_proto(a)
  return false if !jextensible?(a)
  JS_PROTO_INDEX[0] = true if p != nil
  js_array_ext(a, true).put_own(JS_AK_PROTO, p == nil ? JS_NULL : p)
  true
