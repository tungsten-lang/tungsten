# blade/js/b_typed — ArrayBuffer, SharedArrayBuffer, the typed arrays and DataView.
# Storage is a ByteArray; elements are read and written little-endian. Float conversion
# goes through the IEEE bits (Float#js_bits below), so values round-trip exactly.

+ Float
  -> js_bits
    ((($value ## i64) - (0x0001000000000000 ## i64)) ## i64)

-> js_float_from_bits(b)
  bb = b ## i64
  wvalue_from_bits((bb + (0x0001000000000000 ## i64)) ## i64)

+ JsArrayBuffer < JsObject
  rw :data, :blen, :max_len, :detached, :shared

+ JsTypedArray < JsObject
  rw :buffer, :offset, :len, :kind, :track

+ JsDataView < JsObject
  rw :buffer, :offset, :len, :track

# kind index → [name, element size]
TA_KINDS = [["Int8Array", 1], ["Uint8Array", 1], ["Uint8ClampedArray", 1], ["Int16Array", 2], ["Uint16Array", 2], ["Int32Array", 4], ["Uint32Array", 4], ["Float32Array", 4], ["Float64Array", 8], ["BigInt64Array", 8], ["BigUint64Array", 8]]
TA_BIG_START = 9

-> js_ta_size(kind)
  TA_KINDS[kind][1]

-> js_ta_big?(kind)
  kind >= TA_BIG_START

# ---- raw element access on a ByteArray ----

-> js_raw_get(data, pos, kind, little)
  size = TA_KINDS[kind][1]
  if size == 1
    b = data[pos]
    return (b >= 128 ? b - 256 : b) + ~0.0 if kind == 0
    return b + ~0.0
  u = 0
  if little
    k = size - 1
    while k >= 0
      u = (u << 8) | data[pos + k]
      k -= 1
  else
    k = 0
    while k < size
      u = (u << 8) | data[pos + k]
      k += 1
  if kind == 3
    return (u >= 32768 ? u - 65536 : u) + ~0.0
  if kind == 4
    return u + ~0.0
  if kind == 5
    return (u >= 2147483648 ? u - 4294967296 : u) + ~0.0
  if kind == 6
    return u + ~0.0
  if kind == 7
    return js_f32_from_bits(u)
  if kind == 8
    return js_float_from_bits(u)
  if kind == 9
    return JsBigInt.new(js_u64_to_signed(u))
  JsBigInt.new(js_u64_to_unsigned(u))

-> js_u64_to_signed(u)
  u

-> js_u64_to_unsigned(u)
  return u if u >= 0
  (u ## int) + (2 ## int) ** 64

-> js_raw_set(data, pos, kind, v, little)
  size = TA_KINDS[kind][1]
  u = 0
  if kind <= 2
    if kind == 2
      u = js_clamp_u8(v)
    else
      u = js_to_int32(v) & 0xFF
    data[pos] = u
    return nil
  if kind == 3 || kind == 4
    u = js_to_int32(v) & 0xFFFF
  elsif kind == 5 || kind == 6
    u = js_to_int32(v) & 0xFFFFFFFF
  elsif kind == 7
    u = js_f32_bits(js_to_number(v))
  elsif kind == 8
    u = js_to_number(v).js_bits
  else
    b = v.v
    m = (2 ## int) ** 64
    r = b % m
    r = r + m if r < 0
    if r >= (2 ## int) ** 63
      r = r - m
    u = r ## i64
  if little
    k = 0
    while k < size
      data[pos + k] = u & 0xFF
      u = u >> 8
      k += 1
  else
    k = size - 1
    while k >= 0
      data[pos + k] = u & 0xFF
      u = u >> 8
      k -= 1
  nil

-> js_clamp_u8(v)
  n = js_to_number(v)
  return 0 if n != n || n <= ~0.0
  return 255 if n >= ~255.0
  f = Math.floor(n)
  d = n - f
  return f.to_i + 1 if d > ~0.5
  return f.to_i if d < ~0.5
  f.to_i % 2 == 0 ? f.to_i : f.to_i + 1

# float32 bits ↔ value (exact).
-> js_f32_bits(x)
  f = js_fround(x)
  b = f.js_bits
  sign = b < 0 ? 0x80000000 : 0
  e64 = (b >> 52) & 0x7FF
  m64 = b & 0xFFFFFFFFFFFFF
  if e64 == 0x7FF
    return sign | 0x7F800000 | (m64 != 0 ? 0x400000 : 0)
  return sign if e64 == 0 && m64 == 0
  e32 = e64 - 1023 + 127
  if e32 >= 1
    return sign | (e32 << 23) | (m64 >> 29)
  # subnormal float32
  m = m64 | 0x10000000000000
  sh = 29 + 1 - e32
  return sign if sh >= 64
  sign | (m >> sh)

-> js_f32_from_bits(u)
  sign = (u & 0x80000000) != 0
  e = (u >> 23) & 0xFF
  m = u & 0x7FFFFF
  v = ~0.0
  if e == 0xFF
    v = m != 0 ? js_nan() : INF
  elsif e == 0
    v = (m + ~0.0) * (~2.0 ** -149)
  else
    v = (~1.0 + (m + ~0.0) / ~8388608.0) * (~2.0 ** (e - 127))
  sign ? ~0.0 - v : v

# ---- ArrayBuffer ----

-> js_buffer_new(proto, n, max_len, shared)
  b = JsArrayBuffer.new(proto, shared ? "SharedArrayBuffer" : "ArrayBuffer")
  b.data = ByteArray.new(max_len == nil ? (n == 0 ? 1 : n) : (max_len == 0 ? 1 : max_len))
  b.blen = n
  b.max_len = max_len
  b.detached = false
  b.shared = shared
  b

-> js_buffer_ctor(args, nt, shared)
  nm = shared ? "SharedArrayBuffer" : "ArrayBuffer"
  js_throw_type("Constructor " + nm + " requires 'new'") if nt == nil
  n = js_to_index(js_arg(args, 0))
  max_len = nil
  opts = js_arg(args, 1)
  if opts.is_a?(JsObject)
    ml = opts.get("maxByteLength", opts)
    if ml != nil
      max_len = js_to_index(ml)
      raise JsThrow.new(js_range_error("Invalid array buffer max length")) if n > max_len
  raise JsThrow.new(js_range_error("Array buffer allocation failed")) if n > 2147483647 || (max_len != nil && max_len > 2147483647)
  js_buffer_new(JS_REALM[0].proto_from(nt, nm), n, max_len, shared)

-> js_this_buffer(v, shared)
  js_throw_type("Method called on incompatible receiver " + js_to_display(v)) if !(v.is_a?(JsArrayBuffer) && v.shared == shared)
  v

-> js_detach_buffer(b)
  js_throw_type("not an ArrayBuffer") if !b.is_a?(JsArrayBuffer)
  b.detached = true
  b.data = ByteArray.new(1)
  b.blen = 0
  nil

-> js_buffer_slice(this, args, shared)
  b = js_this_buffer(this, shared)
  js_throw_type("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") if b.detached
  n = b.blen
  st = js_rel_index(js_arg(args, 0), n, 0)
  en = js_rel_index(js_arg(args, 1), n, n)
  len = en > st ? en - st : 0
  r = JS_REALM[0]
  c = js_species_ctor(b, r.intrinsic(shared ? "SharedArrayBuffer" : "ArrayBuffer"))
  nb = js_construct(c, [len + ~0.0], nil)
  js_throw_type("ArrayBuffer subclass returned this from species constructor") if !nb.is_a?(JsArrayBuffer) || nb == b
  js_throw_type("Species constructor returned a too small buffer") if nb.blen < len
  js_throw_type("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") if b.detached
  k = 0
  while k < len && st + k < b.blen
    nb.data[k] = b.data[st + k]
    k += 1
  nb

-> js_buffer_resize(this, nv)
  b = js_this_buffer(this, false)
  js_throw_type("Method ArrayBuffer.prototype.resize called on incompatible receiver") if b.max_len == nil
  n = js_to_index(nv)
  js_throw_type("Cannot resize a detached ArrayBuffer") if b.detached
  raise JsThrow.new(js_range_error("ArrayBuffer.prototype.resize: Invalid length parameter")) if n > b.max_len
  k = n
  while k < b.blen
    b.data[k] = 0
    k += 1
  b.blen = n
  nil

-> js_buffer_transfer(this, nv, fixed)
  b = js_this_buffer(this, false)
  n = nv == nil ? b.blen : js_to_index(nv)
  js_throw_type("Cannot transfer a detached ArrayBuffer") if b.detached
  max_len = fixed ? nil : b.max_len
  nb = js_buffer_new(JS_REALM[0].intrinsic("ArrayBuffer.prototype"), n, max_len, false)
  k = 0
  while k < n && k < b.blen
    nb.data[k] = b.data[k]
    k += 1
  js_detach_buffer(b)
  nb

# ---- typed arrays ----

# Current element count (length-tracking views follow a resizable buffer); -1 when out of bounds.
-> js_ta_length(t)
  b = t.buffer
  return -1 if b.detached
  if t.track
    return -1 if t.offset > b.blen
    return (b.blen - t.offset) / js_ta_size(t.kind)
  return -1 if t.offset + t.len * js_ta_size(t.kind) > b.blen
  t.len

-> js_ta_out_of_bounds?(t)
  js_ta_length(t) < 0

-> js_ta_valid(t, what)
  js_throw_type(what + " called on incompatible receiver " + js_to_display(t)) if !t.is_a?(JsTypedArray)
  js_throw_type("Cannot perform " + what + " on a detached ArrayBuffer") if js_ta_out_of_bounds?(t)
  t

-> js_ta_get(t, i)
  n = js_ta_length(t)
  return nil if i < 0 || i >= n
  sz = js_ta_size(t.kind)
  js_raw_get(t.buffer.data, t.offset + i * sz, t.kind, true)

-> js_ta_set_num(t, i, num)
  n = js_ta_length(t)
  return nil if i < 0 || i >= n
  sz = js_ta_size(t.kind)
  js_raw_set(t.buffer.data, t.offset + i * sz, t.kind, num, true)
  nil

# The value converted for this array's content type (ToNumber or ToBigInt).
# TODO(tungsten): js_dyn keeps the BigInt path from being typed as Float (repros/numeric_infer.w)
-> js_ta_convert(t, v)
  return js_dyn(js_to_bigint_from(v, false)) if js_ta_big?(t.kind)
  js_dyn(js_to_number(v))

# CanonicalNumericIndexString: an Int index, -1 for an invalid numeric key, nil for other keys.
-> js_ta_index_key(k)
  return nil if !k.is_a?(String) || k.size == 0
  b = k.byte_at(0)
  return nil if !((b >= 48 && b <= 57) || b == 45 || b == 73 || b == 78)
  return k.to_i if js_array_index?(k)
  return -1 if k == "-0"
  n = js_string_to_number(k)
  return nil if js_number_to_s(n) != k
  return -1 if n != Math.floor(n) || n < ~0.0 || n != n || n == INF
  return -1 if n >= ~4294967295.0
  n.to_i

+ JsTypedArray
  -> length
    n = js_ta_length(self)
    n < 0 ? 0 : n

  -> get_idx(i)
    js_ta_get(self, i)

  -> set_idx(i, v)
    num = js_ta_convert(self, v)
    js_ta_set_num(self, i, num)
    true

  -> has_own?(k)
    i = js_ta_index_key(k)
    return i >= 0 && i < js_ta_length(self) if i != nil
    super(k)

  -> has_own_slot?(k)
    has_own?(k)

  -> own_value(k, receiver)
    i = js_ta_index_key(k)
    return js_ta_get(self, i) if i != nil
    super(k, receiver)

  -> get(k, receiver = nil)
    i = js_ta_index_key(k)
    return js_ta_get(self, i) if i != nil
    ord_get(k, receiver)

  -> set(k, v, receiver = nil)
    i = js_ta_index_key(k)
    if i != nil && (receiver == nil || receiver == self)
      num = js_ta_convert(self, v)
      js_ta_set_num(self, i, num)
      return true
    if i != nil && (i < 0 || i >= js_ta_length(self))
      return true if !receiver.is_a?(JsObject)
    ord_set(k, v, receiver)

  -> put_own(k, v)
    set(k, v, self)

  -> has_property?(k)
    i = js_ta_index_key(k)
    return i >= 0 && i < js_ta_length(self) if i != nil
    super(k)

  -> get_own_property(k)
    i = js_ta_index_key(k)
    if i != nil
      return nil if i < 0 || i >= js_ta_length(self)
      return JsPropDesc.data(js_ta_get(self, i), ATTR_ALL)
    super(k)

  -> define_own_property(k, desc)
    i = js_ta_index_key(k)
    if i != nil
      return false if i < 0 || i >= js_ta_length(self)
      return false if desc.configurable == false || desc.enumerable == false || desc.accessor? || desc.writable == false
      if desc.has_value
        num = js_ta_convert(self, desc.value)
        js_ta_set_num(self, i, num)
      return true
    super(k, desc)

  -> delete_own(k)
    i = js_ta_index_key(k)
    return !(i >= 0 && i < js_ta_length(self)) if i != nil
    super(k)

  -> own_keys
    out = []
    n = js_ta_length(self)
    i = 0
    while i < n
      out.push(i.to_s)
      i += 1
    super().each ->(k) out.push(k)
    out

-> js_ta_create(kind, len)
  r = JS_REALM[0]
  nm = TA_KINDS[kind][0]
  js_ta_alloc(r.intrinsic(nm + ".prototype"), kind, len)

-> js_ta_alloc(proto, kind, len)
  r = JS_REALM[0]
  raise JsThrow.new(js_range_error("Invalid typed array length: " + len.to_s)) if len > 2147483647
  b = js_buffer_new(r.intrinsic("ArrayBuffer.prototype"), len * js_ta_size(kind), nil, false)
  t = JsTypedArray.new(proto, TA_KINDS[kind][0])
  t.buffer = b
  t.offset = 0
  t.len = len
  t.kind = kind
  t.track = false
  t

-> js_ta_ctor(kind, args, nt)
  nm = TA_KINDS[kind][0]
  js_throw_type("Constructor " + nm + " requires 'new'") if nt == nil
  r = JS_REALM[0]
  proto = r.proto_from(nt, nm)
  a0 = js_arg(args, 0)
  if !a0.is_a?(JsObject)
    n = js_to_index(a0)
    return js_ta_alloc(proto, kind, n)
  if a0.is_a?(JsArrayBuffer)
    sz = js_ta_size(kind)
    off = js_to_index(js_arg(args, 1))
    raise JsThrow.new(js_range_error("start offset of " + nm + " should be a multiple of " + sz.to_s)) if off % sz != 0
    lv = js_arg(args, 2)
    newlen = lv == nil ? -1 : js_to_index(lv)
    js_throw_type("Cannot perform Construct on a detached ArrayBuffer") if a0.detached
    t = JsTypedArray.new(proto, nm)
    t.buffer = a0
    t.offset = off
    t.kind = kind
    t.track = false
    if newlen < 0
      if a0.max_len != nil
        raise JsThrow.new(js_range_error("Start offset is outside the bounds of the buffer")) if off > a0.blen
        t.track = true
        t.len = 0
      else
        raise JsThrow.new(js_range_error("byte length of " + nm + " should be a multiple of " + sz.to_s)) if a0.blen % sz != 0
        raise JsThrow.new(js_range_error("Start offset " + off.to_s + " is outside the bounds of the buffer")) if off > a0.blen
        t.len = (a0.blen - off) / sz
    else
      raise JsThrow.new(js_range_error("Invalid typed array length: " + newlen.to_s)) if off + newlen * sz > a0.blen
      t.len = newlen
    return t
  if a0.is_a?(JsTypedArray)
    js_ta_valid(a0, nm)
    n = js_ta_length(a0)
    t = js_ta_alloc(proto, kind, n)
    js_throw_type("Content types differ") if js_ta_big?(kind) != js_ta_big?(a0.kind)
    i = 0
    while i < n
      js_ta_set_num(t, i, js_ta_get(a0, i))
      i += 1
    return t
  # iterable or array-like
  m = js_get_method(a0, SYM_ITERATOR)
  vals = m != nil ? js_to_list(a0) : js_list_from_array_like(a0)
  t = js_ta_alloc(proto, kind, vals.size)
  i = 0
  while i < vals.size
    js_ta_set_num(t, i, js_ta_convert(t, vals[i]))
    i += 1
  t

# TypedArraySpeciesCreate / TypedArrayCreateFromConstructor
-> js_ta_species(t, args)
  r = JS_REALM[0]
  dflt = r.intrinsic(TA_KINDS[t.kind][0])
  c = js_species_ctor(t, dflt)
  js_ta_from_ctor(c, args, t)

-> js_ta_from_ctor(c, args, like)
  n = js_construct(c, args, nil)
  js_ta_valid(n, "TypedArray species")
  if args.size == 1 && args[0].is_a?(Float)
    js_throw_type("TypedArray species constructor returned a too short array") if js_ta_length(n) < args[0].to_i
  if like != nil
    js_throw_type("Content types differ") if js_ta_big?(n.kind) != js_ta_big?(like.kind)
  n

-> js_ta_from(this, items, mapfn, this_arg)
  js_throw_type(js_to_display(this) + " is not a constructor") if !(this.is_a?(JsObject) && js_is_constructor?(this))
  js_throw_type(js_to_display(mapfn) + " is not a function") if mapfn != nil && !(mapfn.is_a?(JsObject) && mapfn.callable?)
  m = js_get_method(items, SYM_ITERATOR)
  vals = m != nil ? js_to_list(items) : js_list_from_array_like(js_to_object(items))
  t = js_ta_from_ctor(this, [vals.size + ~0.0], nil)
  i = 0
  while i < vals.size
    v = vals[i]
    v = js_call(mapfn, this_arg, [v, i + ~0.0]) if mapfn != nil
    t.set_idx(i, v)
    i += 1
  t

-> js_ta_of(this, args)
  js_throw_type(js_to_display(this) + " is not a constructor") if !(this.is_a?(JsObject) && js_is_constructor?(this))
  t = js_ta_from_ctor(this, [args.size + ~0.0], nil)
  i = 0
  while i < args.size
    t.set_idx(i, args[i])
    i += 1
  t

-> js_ta_set(this, src, off_v)
  t = js_ta_valid(this, "%TypedArray%.prototype.set")
  off = js_to_integer(off_v)
  raise JsThrow.new(js_range_error("offset is out of bounds")) if off < ~0.0
  n = js_ta_length(t)
  if src.is_a?(JsTypedArray)
    js_ta_valid(src, "%TypedArray%.prototype.set")
    sn = js_ta_length(src)
    raise JsThrow.new(js_range_error("offset is out of bounds")) if off + sn > n + ~0.0
    js_throw_type("Content types differ") if js_ta_big?(t.kind) != js_ta_big?(src.kind)
    o = off.to_i
    vals = []
    i = 0
    while i < sn
      vals.push(js_ta_get(src, i))
      i += 1
    i = 0
    while i < sn
      js_ta_set_num(t, o + i, vals[i])
      i += 1
    return nil
  s = js_to_object(src)
  sn = js_len_of(s)
  raise JsThrow.new(js_range_error("offset is out of bounds")) if off + sn > n + ~0.0
  o = off.to_i
  i = 0
  while i < sn
    v = js_el(s, i)
    t.set_idx(o + i, v)
    i += 1
  nil

-> js_ta_subarray(this, args)
  js_throw_type("%TypedArray%.prototype.subarray called on incompatible receiver") if !this.is_a?(JsTypedArray)
  t = this
  n = js_ta_length(t)
  n = 0 if n < 0
  st = js_rel_index(js_arg(args, 0), n, 0)
  en = js_rel_index(js_arg(args, 1), n, n)
  len = en > st ? en - st : 0
  sz = js_ta_size(t.kind)
  boff = t.offset + st * sz
  if t.track && js_arg(args, 1) == nil
    return js_ta_species(t, [t.buffer, boff + ~0.0])
  js_ta_species(t, [t.buffer, boff + ~0.0, len + ~0.0])

-> js_ta_slice(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.slice")
  n = js_ta_length(t)
  st = js_rel_index(js_arg(args, 0), n, 0)
  en = js_rel_index(js_arg(args, 1), n, n)
  len = en > st ? en - st : 0
  res = js_ta_species(t, [len + ~0.0])
  if len > 0
    js_ta_valid(t, "%TypedArray%.prototype.slice")
    n2 = js_ta_length(t)
    en = n2 if en > n2
    k = st
    j = 0
    while k < en
      res.set_idx(j, js_ta_get(t, k))
      k += 1
      j += 1
  res

-> js_ta_map(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.map")
  f = js_fn_arg(args, 0, "map")
  n = js_ta_length(t)
  res = js_ta_species(t, [n + ~0.0])
  i = 0
  while i < n
    res.set_idx(i, js_call(f, js_arg(args, 1), [js_ta_get(t, i), i + ~0.0, t]))
    i += 1
  res

-> js_ta_filter(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.filter")
  f = js_fn_arg(args, 0, "filter")
  n = js_ta_length(t)
  keep = []
  i = 0
  while i < n
    v = js_ta_get(t, i)
    keep.push(v) if js_truthy(js_call(f, js_arg(args, 1), [v, i + ~0.0, t]))
    i += 1
  res = js_ta_species(t, [keep.size + ~0.0])
  i = 0
  while i < keep.size
    res.set_idx(i, keep[i])
    i += 1
  res

-> js_ta_fill(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.fill")
  n = js_ta_length(t)
  v = js_ta_convert(t, js_arg(args, 0))
  st = js_rel_index(js_arg(args, 1), n, 0)
  en = js_rel_index(js_arg(args, 2), n, n)
  js_ta_valid(t, "%TypedArray%.prototype.fill")
  n2 = js_ta_length(t)
  en = n2 if en > n2
  k = st
  while k < en
    js_ta_set_num(t, k, v)
    k += 1
  t

-> js_ta_sort(this, cmp)
  js_throw_type("The comparison function must be either a function or undefined") if cmp != nil && !(cmp.is_a?(JsObject) && cmp.callable?)
  t = js_ta_valid(this, "%TypedArray%.prototype.sort")
  n = js_ta_length(t)
  vals = []
  i = 0
  while i < n
    vals.push(js_ta_get(t, i))
    i += 1
  sorted = js_ta_sort_values(vals, cmp)
  n2 = js_ta_length(t)
  i = 0
  while i < sorted.size && i < n2
    js_ta_set_num(t, i, sorted[i])
    i += 1
  t

-> js_ta_sort_values(vals, cmp)
  if cmp != nil
    return js_merge_sort(vals, cmp)
  js_merge_sort_num(vals)

-> js_ta_num_lt(a, b)
  if a.is_a?(JsBigInt)
    return a.v < b.v
  return false if a != a
  return true if b != b
  return true if a == ~0.0 && b == ~0.0 && (~1.0 / a) < ~0.0 && (~1.0 / b) > ~0.0
  a < b

-> js_merge_sort_num(a)
  n = a.size
  return a if n < 2
  mid = n / 2
  l = js_merge_sort_num(a.slice(0, mid))
  r = js_merge_sort_num(a.slice(mid, n - mid))
  out = []
  i = 0
  j = 0
  while i < l.size && j < r.size
    if js_ta_num_lt(r[j], l[i])
      out.push(r[j])
      j += 1
    else
      out.push(l[i])
      i += 1
  while i < l.size
    out.push(l[i])
    i += 1
  while j < r.size
    out.push(r[j])
    j += 1
  out

-> js_ta_copy_like(t)
  n = js_ta_length(t)
  res = js_ta_create(t.kind, n)
  i = 0
  while i < n
    js_ta_set_num(res, i, js_ta_get(t, i))
    i += 1
  res

-> js_ta_with(this, idx, v)
  t = js_ta_valid(this, "%TypedArray%.prototype.with")
  n = js_ta_length(t)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  num = js_ta_convert(t, v)
  raise JsThrow.new(js_range_error("Invalid typed array index")) if i < ~0.0 || i >= js_ta_length(t) + ~0.0
  res = js_ta_copy_like(t)
  js_ta_set_num(res, i.to_i, num)
  res

-> js_ta_getter(this, what)
  js_throw_type("%TypedArray%.prototype." + what + " called on incompatible receiver") if !this.is_a?(JsTypedArray)
  n = js_ta_length(this)
  if what == "length"
    return n < 0 ? ~0.0 : n + ~0.0
  if what == "byteLength"
    return n < 0 ? ~0.0 : (n * js_ta_size(this.kind)) + ~0.0
  if what == "byteOffset"
    return n < 0 ? ~0.0 : this.offset + ~0.0
  this.buffer

-> js_ta_generic(this, fnname, args)
  js_ta_valid(this, "%TypedArray%.prototype." + fnname)
  js_call(JS_REALM[0].array_proto.get(fnname), this, args)

# ---- DataView ----

-> js_dataview_ctor(args, nt)
  js_throw_type("Constructor DataView requires 'new'") if nt == nil
  b = js_arg(args, 0)
  js_throw_type("First argument to DataView constructor must be an ArrayBuffer") if !b.is_a?(JsArrayBuffer)
  off = js_to_index(js_arg(args, 1))
  js_throw_type("Cannot perform DataView constructor on a detached ArrayBuffer") if b.detached
  raise JsThrow.new(js_range_error("Start offset " + off.to_s + " is outside the bounds of the buffer")) if off > b.blen
  lv = js_arg(args, 2)
  track = lv == nil && b.max_len != nil
  len = lv == nil ? b.blen - off : js_to_index(lv)
  raise JsThrow.new(js_range_error("Invalid DataView length " + len.to_s)) if off + len > b.blen
  d = JsDataView.new(JS_REALM[0].proto_from(nt, "DataView"), "DataView")
  js_throw_type("Cannot perform DataView constructor on a detached ArrayBuffer") if b.detached
  d.buffer = b
  d.offset = off
  d.len = len
  d.track = track
  d

-> js_dv_len(d)
  b = d.buffer
  return -1 if b.detached
  if d.track
    return -1 if d.offset > b.blen
    return b.blen - d.offset
  return -1 if d.offset + d.len > b.blen
  d.len

-> js_dv_access(this, kind, args, setting)
  js_throw_type("Method DataView.prototype.get called on incompatible receiver") if !this.is_a?(JsDataView)
  idx = js_to_index(js_arg(args, 0))
  v = nil
  if setting
    v = js_ta_big?(kind) ? js_to_bigint_from(js_arg(args, 1), false) : js_to_number(js_arg(args, 1))
  little = js_to_boolean(js_arg(args, setting ? 2 : 1))
  n = js_dv_len(this)
  js_throw_type("Cannot perform DataView access on a detached ArrayBuffer") if n < 0
  sz = js_ta_size(kind)
  raise JsThrow.new(js_range_error("Offset is outside the bounds of the DataView")) if idx + sz > n
  pos = this.offset + idx
  if setting
    js_raw_set(this.buffer.data, pos, kind, v, little)
    return nil
  js_raw_get(this.buffer.data, pos, kind, little)

js_install(->(r) js_install_typed(r))

-> js_install_typed(r)
  op = r.object_proto
  # ArrayBuffer
  abp = JsObject.new(op, "Object")
  abc = r.constructor("ArrayBuffer", 1, ->(this, args, nt) js_buffer_ctor(args, nt, false), abp)
  r.method(abc, "isView", 1, ->(this, args, nt) js_arg(args, 0).is_a?(JsTypedArray) || js_arg(args, 0).is_a?(JsDataView))
  r.getter(abc, SYM_SPECIES, ->(this, args, nt) this)
  r.getter(abp, "byteLength", ->(this, args, nt) js_this_buffer(this, false).blen + ~0.0)
  r.getter(abp, "maxByteLength", ->(this, args, nt) js_buffer_max(js_this_buffer(this, false)))
  r.getter(abp, "resizable", ->(this, args, nt) js_this_buffer(this, false).max_len != nil)
  r.getter(abp, "detached", ->(this, args, nt) js_this_buffer(this, false).detached)
  r.method(abp, "slice", 2, ->(this, args, nt) js_buffer_slice(this, args, false))
  r.method(abp, "resize", 1, ->(this, args, nt) js_buffer_resize(this, js_arg(args, 0)))
  r.method(abp, "transfer", 0, ->(this, args, nt) js_buffer_transfer(this, js_arg(args, 0), false))
  r.method(abp, "transferToFixedLength", 0, ->(this, args, nt) js_buffer_transfer(this, js_arg(args, 0), true))
  abp.define(SYM_TO_STRING_TAG, "ArrayBuffer", ATTR_C)
  sbp = JsObject.new(op, "Object")
  sbc = r.constructor("SharedArrayBuffer", 1, ->(this, args, nt) js_buffer_ctor(args, nt, true), sbp)
  r.getter(sbc, SYM_SPECIES, ->(this, args, nt) this)
  r.getter(sbp, "byteLength", ->(this, args, nt) js_this_buffer(this, true).blen + ~0.0)
  r.getter(sbp, "growable", ->(this, args, nt) js_this_buffer(this, true).max_len != nil)
  r.getter(sbp, "maxByteLength", ->(this, args, nt) js_buffer_max(js_this_buffer(this, true)))
  r.method(sbp, "slice", 2, ->(this, args, nt) js_buffer_slice(this, args, true))
  r.method(sbp, "grow", 1, ->(this, args, nt) js_buffer_grow(this, js_arg(args, 0)))
  sbp.define(SYM_TO_STRING_TAG, "SharedArrayBuffer", ATTR_C)
  # %TypedArray%
  tap = JsObject.new(op, "Object")
  tac = r.native("TypedArray", 0, ->(this, args, nt) js_throw_type("Abstract class TypedArray not directly constructable"), true)
  tac.define("prototype", tap, 0)
  tap.define("constructor", tac, BUILTIN_ATTRS)
  r.set_intrinsic("%TypedArray%", tac)
  r.method(tac, "from", 1, ->(this, args, nt) js_ta_from(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(tac, "of", 0, ->(this, args, nt) js_ta_of(this, args))
  r.getter(tac, SYM_SPECIES, ->(this, args, nt) this)
  ["length", "byteLength", "byteOffset", "buffer"].each ->(g)
    js_install_ta_getter(r, tap, g)
  tag = r.native("get \[Symbol.toStringTag]", 0, ->(this, args, nt) this.is_a?(JsTypedArray) ? TA_KINDS[this.kind][0] : nil)
  tap.define_accessor(SYM_TO_STRING_TAG, tag, nil, ATTR_C)
  r.method(tap, "set", 1, ->(this, args, nt) js_ta_set(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(tap, "subarray", 2, ->(this, args, nt) js_ta_subarray(this, args))
  r.method(tap, "slice", 2, ->(this, args, nt) js_ta_slice(this, args))
  r.method(tap, "map", 1, ->(this, args, nt) js_ta_map(this, args))
  r.method(tap, "filter", 1, ->(this, args, nt) js_ta_filter(this, args))
  r.method(tap, "fill", 1, ->(this, args, nt) js_ta_fill(this, args))
  r.method(tap, "sort", 1, ->(this, args, nt) js_ta_sort(this, js_arg(args, 0)))
  r.method(tap, "toSorted", 1, ->(this, args, nt) js_ta_sort(js_ta_copy_like(js_ta_valid(this, "toSorted")), js_arg(args, 0)))
  r.method(tap, "toReversed", 0, ->(this, args, nt) js_arr_reverse(js_ta_copy_like(js_ta_valid(this, "toReversed"))))
  r.method(tap, "with", 2, ->(this, args, nt) js_ta_with(this, js_arg(args, 0), js_arg(args, 1)))
  ["at", "copyWithin", "every", "find", "findIndex", "findLast", "findLastIndex", "forEach", "includes", "indexOf", "join", "lastIndexOf", "reduce", "reduceRight", "reverse", "some", "toLocaleString"].each ->(nm)
    js_install_ta_generic(r, tap, nm)
  r.method(tap, "keys", 0, ->(this, args, nt) js_array_iter(js_ta_valid(this, "keys"), :keys))
  r.method(tap, "entries", 0, ->(this, args, nt) js_array_iter(js_ta_valid(this, "entries"), :entries))
  tv = r.method(tap, "values", 0, ->(this, args, nt) js_array_iter(js_ta_valid(this, "values"), :values))
  tap.define(SYM_ITERATOR, tv, BUILTIN_ATTRS)
  tap.define("toString", r.array_proto.get("toString"), BUILTIN_ATTRS)
  k = 0
  while k < TA_KINDS.size
    js_install_ta_kind(r, tac, tap, k)
    k += 1
  # DataView
  dvp = JsObject.new(op, "Object")
  r.constructor("DataView", 1, ->(this, args, nt) js_dataview_ctor(args, nt), dvp)
  r.getter(dvp, "buffer", ->(this, args, nt) js_dv_check(this).buffer)
  r.getter(dvp, "byteLength", ->(this, args, nt) js_dv_byte_length(this))
  r.getter(dvp, "byteOffset", ->(this, args, nt) js_dv_byte_offset(this))
  dvp.define(SYM_TO_STRING_TAG, "DataView", ATTR_C)
  [["Int8", 0], ["Uint8", 1], ["Int16", 3], ["Uint16", 4], ["Int32", 5], ["Uint32", 6], ["Float32", 7], ["Float64", 8], ["BigInt64", 9], ["BigUint64", 10]].each ->(p)
    js_install_dv_methods(r, dvp, p[0], p[1])
  nil

-> js_buffer_max(b)
  (b.max_len == nil ? b.blen : b.max_len) + ~0.0

-> js_buffer_grow(this, nv)
  b = js_this_buffer(this, true)
  js_throw_type("SharedArrayBuffer.prototype.grow called on a non-growable buffer") if b.max_len == nil
  n = js_to_index(nv)
  raise JsThrow.new(js_range_error("Invalid length")) if n > b.max_len || n < b.blen
  b.blen = n
  nil

-> js_install_ta_getter(r, tap, g)
  r.getter(tap, g, ->(this, args, nt) js_ta_getter(this, g))

-> js_install_ta_generic(r, tap, nm)
  r.method(tap, nm, 1, ->(this, args, nt) js_ta_generic(this, nm, args))

-> js_install_ta_kind(r, tac, tap, k)
  nm = TA_KINDS[k][0]
  p = JsObject.new(tap, "Object")
  c = r.constructor(nm, 3, ->(this, args, nt) js_ta_ctor(k, args, nt), p)
  c.proto = tac
  r.constant(c, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)
  r.constant(p, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)

-> js_install_dv_methods(r, dvp, nm, kind)
  r.method(dvp, "get" + nm, 1, ->(this, args, nt) js_dv_access(this, kind, args, false))
  r.method(dvp, "set" + nm, 2, ->(this, args, nt) js_dv_access(this, kind, args, true))

-> js_dv_check(v)
  js_throw_type("Receiver is not a DataView") if !v.is_a?(JsDataView)
  v

-> js_dv_byte_length(this)
  d = js_dv_check(this)
  n = js_dv_len(d)
  js_throw_type("Cannot perform DataView.prototype.byteLength on a detached ArrayBuffer") if n < 0
  n + ~0.0

-> js_dv_byte_offset(this)
  d = js_dv_check(this)
  js_throw_type("Cannot perform DataView.prototype.byteOffset on a detached ArrayBuffer") if js_dv_len(d) < 0
  d.offset + ~0.0
