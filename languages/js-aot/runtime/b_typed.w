# runtime/b_typed — ArrayBuffer, SharedArrayBuffer, the typed arrays and DataView.
# (Ported from blade/js/b_typed.w.) Storage is a ByteArray; elements are read and written
# little-endian. Float conversion goes through the IEEE bits (the jsr_f64_* / jsr_f32_*
# fns below, which hand untyped code 32-bit halves only), so values round-trip exactly.

in JS

+ ArrayBuffer < JS:Special
  rw :data, :blen, :max_len, :detached, :shared

  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @data = nil
    @blen = 0
    @max_len = nil
    @detached = false
    @shared = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

+ TypedArray < JS:Special
  rw :buffer, :offset, :len, :kind, :track

  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @buffer = nil
    @offset = 0
    @len = 0
    @kind = 0
    @track = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> has_own?(k)
    i = js_ta_index_key(k)
    return i >= 0 && i < js_ta_length(self) if i != nil
    super(k)

  -> has_own_slot?(k)
    has_own?(k)

  -> get_own(k)
    i = js_ta_index_key(k)
    if i != nil
      v = js_ta_get(self, i)
      return v == nil ? JS_HOLE : v
    super(k)

  -> enumerable?(k)
    return true if js_ta_index_key(k) != nil
    super(k)

  -> get(k, receiver = nil)
    i = js_ta_index_key(k)
    return js_ta_get(self, i) if i != nil
    super(k, receiver)

  -> set(k, v, receiver = nil)
    i = js_ta_index_key(k)
    if i != nil && (receiver == nil || receiver == self)
      num = js_ta_convert(self, v)
      js_ta_set_num(self, i, num)
      return true
    if i != nil && (i < 0 || i >= js_ta_length(self))
      return true if !js_object?(receiver)
    super(k, v, receiver)

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
      return JS:PropDesc.data(js_ta_get(self, i), ATTR_ALL)
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
    rest = super()
    i = 0
    while i < rest.size
      out.push(rest[i])
      i += 1
    out

+ DataView < JS:Special
  rw :buffer, :offset, :len, :track

  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @buffer = nil
    @offset = 0
    @len = 0
    @track = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

-> js_special_new(proto, cls, klass)
  sh = js_root_shape(proto, SP_INLINE, SP_IBASE)
  return JS:ArrayBuffer.new(sh, cls) if klass == :buffer
  return JS:TypedArray.new(sh, cls) if klass == :typed
  JS:DataView.new(sh, cls)

# kind index → [name, element size]
TA_KINDS = [["Int8Array", 1], ["Uint8Array", 1], ["Uint8ClampedArray", 1], ["Int16Array", 2], ["Uint16Array", 2], ["Int32Array", 4], ["Uint32Array", 4], ["Float32Array", 4], ["Float64Array", 8], ["BigInt64Array", 8], ["BigUint64Array", 8]]
TA_BIG_START = 9

-> js_ta_size(kind)
  TA_KINDS[kind][1]

-> js_ta_big?(kind)
  kind >= TA_BIG_START

# ---- IEEE bits (typed fns: the 64-bit patterns never reach untyped code whole) ----

# The low / high 32 bits of a number's IEEE representation.
fn jsr_f64_lo(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %r = and i64 %x, 4294967295
    ret i64 %r
  IR

fn jsr_f64_hi(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %r = lshr i64 %x, 32
    ret i64 %r
  IR

# The number with these IEEE halves (NaN payloads become the canonical NaN).
fn jsr_f64_make(lo, hi) (i64 i64) i64
  ll <<~IR
    %h = shl i64 %hi, 32
    %l = and i64 %lo, 4294967295
    %b = or i64 %h, %l
    %e = and i64 %b, 9218868437227405312
    %ie = icmp eq i64 %e, 9218868437227405312
    %m = and i64 %b, 4503599627370495
    %mz = icmp ne i64 %m, 0
    %n = and i1 %ie, %mz
    %c = select i1 %n, i64 9221120237041090560, i64 %b
    %r = add i64 %c, 281474976710656
    ret i64 %r
  IR

# float32 bits of a number (round to nearest even) and back.
fn jsr_f32_bits(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %d = bitcast i64 %x to double
    %f = fptrunc double %d to float
    %i = bitcast float %f to i32
    %r = zext i32 %i to i64
    ret i64 %r
  IR

fn jsr_f32_value(u) (i64) i64
  ll <<~IR
    %t = trunc i64 %u to i32
    %f = bitcast i32 %t to float
    %d = fpext float %f to double
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %b = bitcast double %d2 to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

-> js_f64_lo(x)
  jsr_f64_lo(wvalue_bits(x) ## i64)

-> js_f64_hi(x)
  jsr_f64_hi(wvalue_bits(x) ## i64)

-> js_f64_make(lo, hi)
  wvalue_from_bits(jsr_f64_make(lo ## i64, hi ## i64))

-> js_f32_bits(x)
  jsr_f32_bits(wvalue_bits(x) ## i64)

-> js_f32_from_bits(u)
  wvalue_from_bits(jsr_f32_value(u ## i64))

# ---- raw element access on a ByteArray ----

-> js_read_u16(data, pos, little)
  return data[pos] | (data[pos + 1] << 8) if little
  (data[pos] << 8) | data[pos + 1]

-> js_read_u32(data, pos, little)
  return data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24) if little
  (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]

-> js_write_u16(data, pos, u, little)
  if little
    data[pos] = u & 255
    data[pos + 1] = (u >> 8) & 255
  else
    data[pos] = (u >> 8) & 255
    data[pos + 1] = u & 255
  nil

-> js_write_u32(data, pos, u, little)
  if little
    data[pos] = u & 255
    data[pos + 1] = (u >> 8) & 255
    data[pos + 2] = (u >> 16) & 255
    data[pos + 3] = (u >> 24) & 255
  else
    data[pos] = (u >> 24) & 255
    data[pos + 1] = (u >> 16) & 255
    data[pos + 2] = (u >> 8) & 255
    data[pos + 3] = u & 255
  nil

TWO32_INT = 4294967296

-> js_raw_get(data, pos, kind, little)
  if kind <= 2
    b = data[pos]
    return (b >= 128 ? b - 256 : b) + ~0.0 if kind == 0
    return b + ~0.0
  if kind == 3 || kind == 4
    u = js_read_u16(data, pos, little)
    return (u >= 32768 ? u - 65536 : u) + ~0.0 if kind == 3
    return u + ~0.0
  if kind <= 7
    u = js_read_u32(data, pos, little)
    return (u >= 2147483648 ? u - 4294967296 : u) + ~0.0 if kind == 5
    return u + ~0.0 if kind == 6
    return js_f32_from_bits(u)
  lo = js_read_u32(data, little ? pos : pos + 4, little)
  hi = js_read_u32(data, little ? pos + 4 : pos, little)
  return js_f64_make(lo, hi) if kind == 8
  v = (hi ## int) * (TWO32_INT ## int) + (lo ## int)
  v = v - (TWO32_INT ## int) * (TWO32_INT ## int) if kind == 9 && hi >= 2147483648
  JS:BigIntValue.new(v)

-> js_raw_set(data, pos, kind, v, little)
  if kind <= 2
    data[pos] = kind == 2 ? js_clamp_u8(v) : (js_to_int32(v) & 255)
    return nil
  if kind == 3 || kind == 4
    js_write_u16(data, pos, js_to_int32(v) & 65535, little)
    return nil
  if kind == 5 || kind == 6
    js_write_u32(data, pos, js_to_uint32(v), little)
    return nil
  if kind == 7
    js_write_u32(data, pos, js_f32_bits(js_to_number(v)), little)
    return nil
  lo = 0
  hi = 0
  if kind == 8
    x = js_to_number(v)
    lo = js_f64_lo(x)
    hi = js_f64_hi(x)
  else
    m = (TWO32_INT ## int) * (TWO32_INT ## int)
    r = v.v % m
    r = r + m if r < 0
    lo = (r % (TWO32_INT ## int)).to_i
    hi = (r / (TWO32_INT ## int)).to_i
  js_write_u32(data, little ? pos : pos + 4, lo, little)
  js_write_u32(data, little ? pos + 4 : pos, hi, little)
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

# ---- ArrayBuffer ----

-> js_buffer_new(proto, n, max_len, shared)
  b = js_special_new(proto, shared ? "SharedArrayBuffer" : "ArrayBuffer", :buffer)
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
  if js_object?(opts)
    ml = jget(opts, "maxByteLength")
    if ml != nil
      max_len = js_to_index(ml)
      js_throw_range("Invalid array buffer max length") if n > max_len
  # OrdinaryCreateFromConstructor runs before the allocation can fail
  proto = js_realm().proto_from(nt, nm)
  js_throw_range("Array buffer allocation failed") if n > 2147483647 || (max_len != nil && max_len > 2147483647)
  js_buffer_new(proto, n, max_len, shared)

-> js_this_buffer(v, shared)
  js_throw_type("Method called on incompatible receiver " + js_err_display(v)) if !(v.is_a?(JS:ArrayBuffer) && v.shared == shared)
  v

-> js_detach_buffer(b)
  js_throw_type("not an ArrayBuffer") if !b.is_a?(JS:ArrayBuffer)
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
  r = js_realm()
  c = js_species_ctor(b, r.intrinsic(shared ? "SharedArrayBuffer" : "ArrayBuffer"))
  nb = js_construct(c, [len + ~0.0], nil)
  js_throw_type("ArrayBuffer subclass returned this from species constructor") if !nb.is_a?(JS:ArrayBuffer) || nb == b || nb.shared != shared
  js_throw_type("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") if nb.detached
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
  js_throw_range("ArrayBuffer.prototype.resize: Invalid length parameter") if n > b.max_len
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
  nb = js_buffer_new(js_realm().intrinsic("ArrayBuffer.prototype"), n, max_len, false)
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
  js_throw_type(what + " called on incompatible receiver " + js_err_display(t)) if !t.is_a?(JS:TypedArray)
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
  return nil if !js_string?(k) || k.size == 0
  b = k.byte_at(0)
  return nil if !((b >= 48 && b <= 57) || b == 45 || b == 73 || b == 78)
  return k.to_i if js_array_index?(k)
  return -1 if k == "-0"
  n = js_string_to_number(k)
  return nil if js_number_to_s(n) != k
  return -1 if n != Math.floor(n) || n < ~0.0 || n != n || n == INF
  return -1 if n >= ~4294967295.0
  n.to_i

-> js_ta_set_idx(t, i, v)
  num = js_ta_convert(t, v)
  js_ta_set_num(t, i, num)
  true

-> js_ta_tag(this)
  return nil if !this.is_a?(JS:TypedArray)
  TA_KINDS[this.kind][0]

# The length an array iterator over a typed array sees (TypeError when out of bounds).
-> js_typed_iter_length(o)
  n = js_ta_length(o)
  js_throw_type("Cannot perform %ArrayIteratorPrototype%.next on a detached ArrayBuffer") if n < 0
  n

-> js_ta_create(kind, len)
  r = js_realm()
  nm = TA_KINDS[kind][0]
  js_ta_alloc(r.intrinsic(nm + ".prototype"), kind, len)

-> js_ta_alloc(proto, kind, len)
  r = js_realm()
  js_throw_range("Invalid typed array length: " + len.to_s) if len > 2147483647
  b = js_buffer_new(r.intrinsic("ArrayBuffer.prototype"), len * js_ta_size(kind), nil, false)
  t = js_special_new(proto, TA_KINDS[kind][0], :typed)
  t.buffer = b
  t.offset = 0
  t.len = len
  t.kind = kind
  t.track = false
  t

-> js_ta_ctor(kind, args, nt)
  nm = TA_KINDS[kind][0]
  js_throw_type("Constructor " + nm + " requires 'new'") if nt == nil
  r = js_realm()
  proto = r.proto_from(nt, nm)
  a0 = js_arg(args, 0)
  if !js_object?(a0)
    n = js_to_index(a0)
    return js_ta_alloc(proto, kind, n)
  if a0.is_a?(JS:ArrayBuffer)
    sz = js_ta_size(kind)
    off = js_to_index(js_arg(args, 1))
    js_throw_range("start offset of " + nm + " should be a multiple of " + sz.to_s) if off % sz != 0
    lv = js_arg(args, 2)
    newlen = lv == nil ? -1 : js_to_index(lv)
    js_throw_type("Cannot perform Construct on a detached ArrayBuffer") if a0.detached
    t = js_special_new(proto, nm, :typed)
    t.buffer = a0
    t.offset = off
    t.kind = kind
    t.track = false
    if newlen < 0
      if a0.max_len != nil
        js_throw_range("Start offset is outside the bounds of the buffer") if off > a0.blen
        t.track = true
        t.len = 0
      else
        js_throw_range("byte length of " + nm + " should be a multiple of " + sz.to_s) if a0.blen % sz != 0
        js_throw_range("Start offset " + off.to_s + " is outside the bounds of the buffer") if off > a0.blen
        t.len = (a0.blen - off) / sz
    else
      js_throw_range("Invalid typed array length: " + newlen.to_s) if off + newlen * sz > a0.blen
      t.len = newlen
    return t
  if a0.is_a?(JS:TypedArray)
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
  r = js_realm()
  dflt = r.intrinsic(TA_KINDS[t.kind][0])
  c = js_species_ctor(t, dflt)
  js_ta_from_ctor(c, args, t)

-> js_ta_from_ctor(c, args, like)
  n = js_construct(c, args, nil)
  js_ta_valid(n, "TypedArray species")
  if args.size == 1 && js_number?(args[0])
    js_throw_type("TypedArray species constructor returned a too short array") if js_ta_length(n) < args[0].to_i
  if like != nil
    js_throw_type("Content types differ") if js_ta_big?(n.kind) != js_ta_big?(like.kind)
  n

-> js_ta_from(this, items, mapfn, this_arg)
  js_throw_type(js_err_display(this) + " is not a constructor") if !js_is_constructor?(this)
  js_throw_type(js_err_display(mapfn) + " is not a function") if mapfn != nil && !js_callable?(mapfn)
  m = js_get_method(items, SYM_ITERATOR)
  vals = m != nil ? js_to_list(items) : js_list_from_array_like(js_to_obj(items))
  t = js_ta_from_ctor(this, [vals.size + ~0.0], nil)
  i = 0
  while i < vals.size
    v = vals[i]
    v = js_call(mapfn, this_arg, 2, v, i + ~0.0, nil, nil, nil) if mapfn != nil
    js_ta_set_idx(t, i, v)
    i += 1
  t

-> js_ta_of(this, args)
  js_throw_type(js_err_display(this) + " is not a constructor") if !js_is_constructor?(this)
  t = js_ta_from_ctor(this, [args.size + ~0.0], nil)
  i = 0
  while i < args.size
    js_ta_set_idx(t, i, args[i])
    i += 1
  t

-> js_ta_set(this, src, off_v)
  t = js_ta_valid(this, "%TypedArray%.prototype.set")
  off = js_to_integer(off_v)
  js_throw_range("offset is out of bounds") if off < ~0.0
  n = js_ta_length(t)
  if src.is_a?(JS:TypedArray)
    js_ta_valid(src, "%TypedArray%.prototype.set")
    sn = js_ta_length(src)
    js_throw_range("offset is out of bounds") if off + sn > n + ~0.0
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
  s = js_to_obj(src)
  sn = js_len_of(s)
  js_throw_range("offset is out of bounds") if off + sn > n + ~0.0
  o = off.to_i
  i = 0
  while i < sn
    v = js_el(s, i)
    js_ta_set_idx(t, o + i, v)
    i += 1
  nil

-> js_ta_subarray(this, args)
  js_throw_type("%TypedArray%.prototype.subarray called on incompatible receiver") if !this.is_a?(JS:TypedArray)
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
      js_ta_set_idx(res, j, js_ta_get(t, k))
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
    js_ta_set_idx(res, i, js_call(f, js_arg(args, 1), 3, js_ta_get(t, i), i + ~0.0, t, nil, nil))
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
    keep.push(v) if js_truthy(js_call(f, js_arg(args, 1), 3, v, i + ~0.0, t, nil, nil))
    i += 1
  res = js_ta_species(t, [keep.size + ~0.0])
  i = 0
  while i < keep.size
    js_ta_set_idx(res, i, keep[i])
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
  js_check_cmp(cmp)
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
  if a.is_a?(JS:BigIntValue)
    return a.v < b.v
  return false if a != a
  return true if b != b
  return true if a == ~0.0 && b == ~0.0 && (~1.0 / a) < ~0.0 && (~1.0 / b) > ~0.0
  a < b

-> js_merge_sort_num(a)
  n = a.size
  return a if n < 2
  mid = n / 2
  l = js_merge_sort_num(a.slice(0, mid).dup)
  r = js_merge_sort_num(a.slice(mid, n - mid).dup)
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
  js_throw_range("Invalid typed array index") if i < ~0.0 || i >= js_ta_length(t) + ~0.0
  res = js_ta_copy_like(t)
  js_ta_set_num(res, i.to_i, num)
  res

-> js_ta_getter(this, what)
  js_throw_type("%TypedArray%.prototype." + what + " called on incompatible receiver") if !this.is_a?(JS:TypedArray)
  n = js_ta_length(this)
  if what == "length"
    return n < 0 ? ~0.0 : n + ~0.0
  if what == "byteLength"
    return n < 0 ? ~0.0 : (n * js_ta_size(this.kind)) + ~0.0
  if what == "byteOffset"
    return n < 0 ? ~0.0 : this.offset + ~0.0
  this.buffer

-> js_ta_generic(this, fnname, f, args)
  js_ta_valid(this, "%TypedArray%.prototype." + fnname)
  js_call_arr(f, this, args)

# ---- DataView ----

-> js_dataview_ctor(args, nt)
  js_throw_type("Constructor DataView requires 'new'") if nt == nil
  b = js_arg(args, 0)
  js_throw_type("First argument to DataView constructor must be an ArrayBuffer") if !b.is_a?(JS:ArrayBuffer)
  off = js_to_index(js_arg(args, 1))
  js_throw_type("Cannot perform DataView constructor on a detached ArrayBuffer") if b.detached
  js_throw_range("Start offset " + off.to_s + " is outside the bounds of the buffer") if off > b.blen
  lv = js_arg(args, 2)
  track = lv == nil && b.max_len != nil
  len = lv == nil ? b.blen - off : js_to_index(lv)
  js_throw_range("Invalid DataView length " + len.to_s) if off + len > b.blen
  d = js_special_new(js_realm().proto_from(nt, "DataView"), "DataView", :view)
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
  js_throw_type("Method DataView.prototype.get called on incompatible receiver") if !this.is_a?(JS:DataView)
  idx = js_to_index(js_arg(args, 0))
  v = nil
  if setting
    v = js_ta_big?(kind) ? js_to_bigint_from(js_arg(args, 1), false) : js_to_number(js_arg(args, 1))
  little = js_to_boolean(js_arg(args, setting ? 2 : 1))
  n = js_dv_len(this)
  js_throw_type("Cannot perform DataView access on a detached ArrayBuffer") if n < 0
  sz = js_ta_size(kind)
  js_throw_range("Offset is outside the bounds of the DataView") if idx + sz > n
  pos = this.offset + idx
  if setting
    js_raw_set(this.buffer.data, pos, kind, v, little)
    return nil
  js_raw_get(this.buffer.data, pos, kind, little)

js_install(->(r) js_install_typed(r))

-> js_install_typed(r)
  op = r.object_proto
  # ArrayBuffer
  abp = js_new_object(op)
  abc = r.constructor("ArrayBuffer", 1, ->(this, args, nt) js_buffer_ctor(args, nt, false), abp)
  r.method(abc, "isView", 1, ->(this, args, nt) js_arg(args, 0).is_a?(JS:TypedArray) || js_arg(args, 0).is_a?(JS:DataView))
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
  sbp = js_new_object(op)
  sbc = r.constructor("SharedArrayBuffer", 1, ->(this, args, nt) js_buffer_ctor(args, nt, true), sbp)
  r.getter(sbc, SYM_SPECIES, ->(this, args, nt) this)
  r.getter(sbp, "byteLength", ->(this, args, nt) js_this_buffer(this, true).blen + ~0.0)
  r.getter(sbp, "growable", ->(this, args, nt) js_this_buffer(this, true).max_len != nil)
  r.getter(sbp, "maxByteLength", ->(this, args, nt) js_buffer_max(js_this_buffer(this, true)))
  r.method(sbp, "slice", 2, ->(this, args, nt) js_buffer_slice(this, args, true))
  r.method(sbp, "grow", 1, ->(this, args, nt) js_buffer_grow(this, js_arg(args, 0)))
  sbp.define(SYM_TO_STRING_TAG, "SharedArrayBuffer", ATTR_C)
  # %TypedArray%
  tap = js_new_object(op)
  tac = r.native("TypedArray", 0, ->(this, args, nt) js_throw_type("Abstract class TypedArray not directly constructable"), true)
  tac.define("prototype", tap, 0)
  tap.define("constructor", tac, BUILTIN_ATTRS)
  r.set_intrinsic("%TypedArray%", tac)
  r.method(tac, "from", 1, ->(this, args, nt) js_ta_from(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(tac, "of", 0, ->(this, args, nt) js_ta_of(this, args))
  r.getter(tac, SYM_SPECIES, ->(this, args, nt) this)
  ["length", "byteLength", "byteOffset", "buffer"].each ->(g)
    js_install_ta_getter(r, tap, g)
  tag = r.native("get \[Symbol.toStringTag]", 0, ->(this, args, nt) js_ta_tag(this))
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
  tap.define("toString", r.intrinsic("%ArrayProto_toString%"), BUILTIN_ATTRS)
  k = 0
  while k < TA_KINDS.size
    js_install_ta_kind(r, tac, tap, k)
    k += 1
  # DataView
  dvp = js_new_object(op)
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
  js_throw_range("Invalid length") if n > b.max_len || n < b.blen
  b.blen = n
  nil

-> js_install_ta_getter(r, tap, g)
  r.getter(tap, g, ->(this, args, nt) js_ta_getter(this, g))

-> js_install_ta_generic(r, tap, nm)
  f = r.array_proto.get_own(nm)
  r.method(tap, nm, jget(f, "length").to_i, ->(this, args, nt) js_ta_generic(this, nm, f, args))

-> js_install_ta_kind(r, tac, tap, k)
  nm = TA_KINDS[k][0]
  p = js_new_object(tap)
  c = r.constructor(nm, 3, ->(this, args, nt) js_ta_ctor(k, args, nt), p)
  c.set_prototype_of(tac)
  r.constant(c, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)
  r.constant(p, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)

-> js_install_dv_methods(r, dvp, nm, kind)
  r.method(dvp, "get" + nm, 1, ->(this, args, nt) js_dv_access(this, kind, args, false))
  r.method(dvp, "set" + nm, 2, ->(this, args, nt) js_dv_access(this, kind, args, true))

-> js_dv_check(v)
  js_throw_type("Receiver is not a DataView") if !v.is_a?(JS:DataView)
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
