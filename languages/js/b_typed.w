# runtime/b_typed — ArrayBuffer, SharedArrayBuffer, the typed arrays and DataView.
# (Ported from blade/js/b_typed.w.) Storage is a ByteArray; elements are read and written
# little-endian. Float conversion goes through the IEEE bits (the jsr_f64_* / jsr_f32_*
# fns below, which hand untyped code 32-bit halves only), so values round-trip exactly.

in JS

+ ArrayBuffer < JS:Special
  rw :data, :blen, :max_len, :detached, :shared, :immutable

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
    @immutable = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

+ TypedArray < JS:Special
  rw :buffer, :offset, :len, :kind, :track, :view, :view_ep

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
    @view = nil
    @view_ep = -1
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

  -> get(k, receiver = JS_HOLE)
    i = js_ta_index_key(k)
    return js_ta_get(self, i) if i != nil
    super(k, receiver)

  -> set(k, v, receiver = JS_HOLE)
    i = js_ta_index_key(k)
    if i != nil
      return false if @buffer.immutable
      if receiver == JS_HOLE || receiver == self
        num = js_ta_convert(self, v)
        js_ta_set_num(self, i, num)
        return true
      return true if i < 0 || i >= js_ta_length(self)
      return js_set_on_receiver(receiver, k, v)
    super(k, v, receiver)

  -> prevent_extensions
    return false if @track || (@buffer.max_len != nil && !@buffer.shared)
    super()

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
      return JS:PropDesc.data(js_ta_get(self, i), @buffer.immutable ? ATTR_E : ATTR_ALL)
    super(k)

  -> define_own_property(k, desc)
    i = js_ta_index_key(k)
    if i != nil
      return false if i < 0 || i >= js_ta_length(self)
      if @buffer.immutable
        return false if desc.accessor? || desc.configurable == true || desc.enumerable == false || desc.writable == true
        return false if desc.has_value && !js_same_value(desc.value, js_ta_get(self, i))
        return true
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
TA_KINDS = [["Int8Array", 1], ["Uint8Array", 1], ["Uint8ClampedArray", 1], ["Int16Array", 2], ["Uint16Array", 2], ["Int32Array", 4], ["Uint32Array", 4], ["Float32Array", 4], ["Float64Array", 8], ["BigInt64Array", 8], ["BigUint64Array", 8], ["Float16Array", 2]]
TA_EBITS = [108, 8, 8, 116, 16, 33, 32, -32, -64, 66, 64, -16]
TA_BIG_START = 9

-> js_ta_size(kind)
  TA_KINDS[kind][1]

-> js_ta_big?(kind)
  kind == 9 || kind == 10

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

# IEEE-754 binary16 (half precision) exact round-to-nearest-even conversions.
-> js_f16_bits(x)
  lo = js_f64_lo(x)
  hi = js_f64_hi(x)
  sign = (hi >> 31) & 1
  exp = (hi >> 20) & 2047
  fhi = hi & 1048575
  if exp == 2047
    return (fhi != 0 || lo != 0) ? 0x7E00 : ((sign << 15) | 0x7C00)
  e = exp - 1023
  return (sign << 15) | 0x7C00 if e > 15
  if e >= -14
    mant = fhi >> 10
    rbit = (fhi >> 9) & 1
    sticky = (fhi & 511) != 0 || lo != 0
    if rbit == 1 && (sticky || (mant & 1) == 1)
      mant += 1
      if mant == 1024
        mant = 0
        e += 1
        return (sign << 15) | 0x7C00 if e > 15
    return (sign << 15) | ((e + 15) << 10) | mant
  if e >= -25
    sig = 1048576 | fhi
    sh = -4 - e
    mant = sig >> sh
    rbit = (sig >> (sh - 1)) & 1
    mask = (1 << (sh - 1)) - 1
    sticky = (sig & mask) != 0 || lo != 0
    mant += 1 if rbit == 1 && (sticky || (mant & 1) == 1)
    return (sign << 15) | mant
  sign << 15

-> js_f16_from_bits(u)
  sign = (u >> 15) & 1
  exp = (u >> 10) & 31
  frac = u & 1023
  if exp == 31
    return frac != 0 ? js_nan() : (sign == 1 ? NEG_INF : INF)
  if exp == 0
    return sign == 1 ? ~-0.0 : ~0.0 if frac == 0
    v = frac.to_f * ~5.9604644775390625e-8
    return sign == 1 ? (~0.0 - v) : v
  hi = (sign << 31) | ((exp + 1008) << 20) | (frac << 10)
  js_f64_make(0, hi)

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
  if kind == 3 || kind == 4 || kind == 11
    u = js_read_u16(data, pos, little)
    return js_f16_from_bits(u) if kind == 11
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
  if kind == 11
    js_write_u16(data, pos, js_f16_bits(js_to_number(v)), little)
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

JS_AB_EPOCH = i64[1]

fn jsr_ba_data_ptr(ba_bits) (i64) i64
  ll <<~IR
    %p = and i64 %ba_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

fn jsr_raw_ld_f64(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %d = load double, ptr %q, align 1
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %b = bitcast double %d2 to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_f64(base, off, v_bits) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %x = sub i64 %v_bits, 281474976710656
    %d = bitcast i64 %x to double
    store double %d, ptr %q, align 1
    ret i64 0
  IR

fn jsr_raw_ld_i32(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i32, ptr %q, align 1
    %d = sitofp i32 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_i32(base, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = trunc i64 %val to i32
    store i32 %w, ptr %q, align 1
    ret i64 0
  IR

# Native 1-instruction LLVM loads/stores for all remaining JS numeric widths:
# i8, u8, i16, u16, u32, f32, f16 (ARM64 hardware half!), i64, u64.
fn jsr_raw_ld_i8(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i8, ptr %q, align 1
    %d = sitofp i8 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_ld_u8(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i8, ptr %q, align 1
    %d = uitofp i8 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_u8(base, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = trunc i64 %val to i8
    store i8 %w, ptr %q, align 1
    ret i64 0
  IR

fn jsr_raw_ld_i16(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i16, ptr %q, align 1
    %d = sitofp i16 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_ld_u16(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i16, ptr %q, align 1
    %d = uitofp i16 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_u16(base, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = trunc i64 %val to i16
    store i16 %w, ptr %q, align 1
    ret i64 0
  IR

fn jsr_raw_ld_u32(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i32, ptr %q, align 1
    %d = uitofp i32 %w to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_ld_f32(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %f = load float, ptr %q, align 1
    %d = fpext float %f to double
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %b = bitcast double %d2 to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_f32(base, off, v_bits) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %x = sub i64 %v_bits, 281474976710656
    %d = bitcast i64 %x to double
    %f = fptrunc double %d to float
    store float %f, ptr %q, align 1
    ret i64 0
  IR

fn jsr_raw_ld_f16(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %h = load half, ptr %q, align 1
    %d = fpext half %h to double
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %b = bitcast double %d2 to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

fn jsr_raw_st_f16(base, off, v_bits) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %x = sub i64 %v_bits, 281474976710656
    %d = bitcast i64 %x to double
    %h = fptrunc double %d to half
    store half %h, ptr %q, align 1
    ret i64 0
  IR

fn jsr_raw_ld_i64(base, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    %w = load i64, ptr %q, align 1
    ret i64 %w
  IR

fn jsr_raw_st_i64(base, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %base, %off
    %q = inttoptr i64 %p to ptr
    store i64 %val, ptr %q, align 1
    ret i64 0
  IR

# Zero-copy raw Tungsten `ebits` WArray view cached directly on JS:TypedArray.
# Automatically invalidated whenever JS_AB_EPOCH advances (detach / transfer / resize).
-> js_ta_ebits_view(t)
  b = t.buffer
  return nil if b == nil || b.detached
  n = js_ta_length(t)
  return nil if n < 0
  ep = JS_AB_EPOCH[0]
  if t.view != nil && t.view_ep == ep && t.view.size == n
    return t.view
  base = jsr_ba_data_ptr(wvalue_bits(b.data) ## i64)
  off = t.offset ## i64
  eb = TA_EBITS[t.kind] ## i64
  v = wvalue_from_bits(ccall_nobox("w_array_view_raw", (base + off) ## i64, eb, n ## i64) ## i64)
  t.view = v
  t.view_ep = ep
  v

-> js_detach_buffer(b)
  js_throw_type("not an ArrayBuffer") if !b.is_a?(JS:ArrayBuffer)
  js_throw_type("Cannot detach an immutable ArrayBuffer") if b.immutable
  b.detached = true
  b.data = ByteArray.new(1)
  b.blen = 0
  JS_AB_EPOCH[0] = JS_AB_EPOCH[0] + 1
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
  js_throw_type("Species constructor returned an immutable buffer") if nb.immutable
  js_throw_type("Species constructor returned a too small buffer") if nb.blen < len
  js_throw_type("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") if b.detached
  k = 0
  while k < len && st + k < b.blen
    nb.data[k] = b.data[st + k]
    k += 1
  nb

-> js_buffer_slice_immutable(this, args)
  b = js_this_buffer(this, false)
  js_throw_type("Cannot perform ArrayBuffer.prototype.sliceToImmutable on a detached ArrayBuffer") if b.detached
  n = b.blen
  st = js_rel_index(js_arg(args, 0), n, 0)
  en = js_rel_index(js_arg(args, 1), n, n)
  len = en > st ? en - st : 0
  js_throw_type("Cannot perform ArrayBuffer.prototype.sliceToImmutable on a detached ArrayBuffer") if b.detached
  js_throw_range("ArrayBuffer shrunk below slice end") if b.blen < en
  nb = js_buffer_new(js_realm().intrinsic("ArrayBuffer.prototype"), len, nil, false)
  nb.immutable = true
  k = 0
  while k < len
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
  JS_AB_EPOCH[0] = JS_AB_EPOCH[0] + 1
  nil

-> js_buffer_transfer(this, nv, mode)
  b = js_this_buffer(this, false)
  n = nv == nil ? b.blen : js_to_index(nv)
  js_throw_type("Cannot transfer a detached ArrayBuffer") if b.detached
  js_throw_type("Cannot transfer an immutable ArrayBuffer") if b.immutable
  max_len = mode == :preserve ? b.max_len : nil
  nb = js_buffer_new(js_realm().intrinsic("ArrayBuffer.prototype"), n, max_len, false)
  nb.immutable = true if mode == :immutable
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
  k = t.kind
  base = jsr_ba_data_ptr(wvalue_bits(t.buffer.data) ## i64)
  off = t.offset
  return wvalue_from_bits(jsr_raw_ld_f64(base, (off + i * 8) ## i64)) if k == 8
  return wvalue_from_bits(jsr_raw_ld_f32(base, (off + i * 4) ## i64)) if k == 7
  return wvalue_from_bits(jsr_raw_ld_i32(base, (off + i * 4) ## i64)) if k == 5
  return wvalue_from_bits(jsr_raw_ld_u32(base, (off + i * 4) ## i64)) if k == 6
  return wvalue_from_bits(jsr_raw_ld_u8(base, (off + i) ## i64)) if k == 1 || k == 2
  return wvalue_from_bits(jsr_raw_ld_i8(base, (off + i) ## i64)) if k == 0
  return wvalue_from_bits(jsr_raw_ld_i16(base, (off + i * 2) ## i64)) if k == 3
  return wvalue_from_bits(jsr_raw_ld_u16(base, (off + i * 2) ## i64)) if k == 4
  return wvalue_from_bits(jsr_raw_ld_f16(base, (off + i * 2) ## i64)) if k == 11
  # BigInt64Array (9) / BigUint64Array (10): direct 64-bit raw load
  raw = jsr_raw_ld_i64(base, (off + i * 8) ## i64)
  return JS:BigIntValue.new(raw ## int) if k == 9
  u = raw < 0 ? ((raw ## int) + ((1 ## int) << 64)) : (raw ## int)
  JS:BigIntValue.new(u)

-> js_ta_set_num(t, i, num)
  n = js_ta_length(t)
  return nil if i < 0 || i >= n
  k = t.kind
  base = jsr_ba_data_ptr(wvalue_bits(t.buffer.data) ## i64)
  off = t.offset
  if k == 8
    jsr_raw_st_f64(base, (off + i * 8) ## i64, wvalue_bits(num) ## i64)
    return nil
  if k == 7
    jsr_raw_st_f32(base, (off + i * 4) ## i64, wvalue_bits(num) ## i64)
    return nil
  if k == 5 || k == 6
    jsr_raw_st_i32(base, (off + i * 4) ## i64, (k == 5 ? js_to_int32(num) : js_to_uint32(num)) ## i64)
    return nil
  if k == 0 || k == 1
    jsr_raw_st_u8(base, (off + i) ## i64, (js_to_int32(num) & 255) ## i64)
    return nil
  if k == 2
    jsr_raw_st_u8(base, (off + i) ## i64, js_clamp_u8(num) ## i64)
    return nil
  if k == 3 || k == 4
    jsr_raw_st_u16(base, (off + i * 2) ## i64, (js_to_int32(num) & 65535) ## i64)
    return nil
  if k == 11
    jsr_raw_st_f16(base, (off + i * 2) ## i64, wvalue_bits(num) ## i64)
    return nil
  # BigInt64Array (9) / BigUint64Array (10): direct 64-bit raw store
  m = (TWO32_INT ## int) * (TWO32_INT ## int)
  r = num.v % m
  r = r + m if r < 0
  signed = r >= ((1 ## int) << 63) ? (r - m) : r
  jsr_raw_st_i64(base, (off + i * 8) ## i64, signed ## i64)
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
  sz = js_ta_size(kind)
  js_throw_range("Invalid typed array length: " + len.to_s) if len > 2147483647 || len * sz > 2147483647
  b = js_buffer_new(r.intrinsic("ArrayBuffer.prototype"), len * sz, nil, false)
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
  a0 = js_arg(args, 0)
  if !js_object?(a0)
    n = js_to_index(a0)
    proto = r.proto_from(nt, nm)
    return js_ta_alloc(proto, kind, n)
  proto = r.proto_from(nt, nm)
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
  if m != nil
    vals = js_to_list(a0)
    t = js_ta_alloc(proto, kind, vals.size)
    i = 0
    while i < vals.size
      js_ta_set_num(t, i, js_ta_convert(t, vals[i]))
      i += 1
    return t
  n = js_len_of(a0)
  t = js_ta_alloc(proto, kind, n)
  i = 0
  while i < n
    js_ta_set_idx(t, i, js_el(a0, i))
    i += 1
  t

# TypedArraySpeciesCreate / TypedArrayCreateFromConstructor
-> js_ta_species(t, args, write = false)
  r = js_realm()
  dflt = r.intrinsic(TA_KINDS[t.kind][0])
  c = js_species_ctor(t, dflt)
  js_ta_from_ctor(c, args, t, write)

-> js_ta_from_ctor(c, args, like, write = false)
  n = js_construct(c, args, nil)
  js_ta_valid(n, "TypedArray species")
  js_throw_type("Cannot write to a TypedArray backed by an immutable ArrayBuffer") if write && n.buffer.immutable
  if args.size == 1 && js_number?(args[0])
    js_throw_type("TypedArray species constructor returned a too short array") if js_ta_length(n) < args[0].to_i
  if like != nil
    js_throw_type("Content types differ") if js_ta_big?(n.kind) != js_ta_big?(like.kind)
  n

-> js_ta_from(this, items, mapfn, this_arg)
  js_throw_type(js_err_display(this) + " is not a constructor") if !js_is_constructor?(this)
  js_throw_type(js_err_display(mapfn) + " is not a function") if mapfn != nil && !js_callable?(mapfn)
  m = js_get_method(items, SYM_ITERATOR)
  if m != nil
    rec = js_get_iterator_with(items, m)
    vals = []
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      vals.push(x)
    t = js_ta_from_ctor(this, [vals.size + ~0.0], nil, true)
    i = 0
    while i < vals.size
      v = vals[i]
      v = js_call(mapfn, this_arg, 2, v, i + ~0.0, nil, nil, nil) if mapfn != nil
      js_ta_set_idx(t, i, v)
      i += 1
    return t
  o = js_to_obj(items)
  n = js_len_of(o)
  t = js_ta_from_ctor(this, [n + ~0.0], nil, true)
  i = 0
  while i < n
    v = js_el(o, i)
    v = js_call(mapfn, this_arg, 2, v, i + ~0.0, nil, nil, nil) if mapfn != nil
    js_ta_set_idx(t, i, v)
    i += 1
  t

-> js_ta_of(this, args)
  js_throw_type(js_err_display(this) + " is not a constructor") if !js_is_constructor?(this)
  t = js_ta_from_ctor(this, [args.size + ~0.0], nil, true)
  i = 0
  while i < args.size
    js_ta_set_idx(t, i, args[i])
    i += 1
  t

-> js_ta_set(this, src, off_v)
  js_throw_type("%TypedArray%.prototype.set called on incompatible receiver " + js_err_display(this)) if !this.is_a?(JS:TypedArray)
  t = this
  js_throw_type("Cannot perform %TypedArray%.prototype.set on an immutable ArrayBuffer") if t.buffer.immutable
  off = js_to_integer(off_v)
  js_throw_range("offset is out of bounds") if off < ~0.0
  n = js_ta_length(t)
  js_throw_type("Cannot perform %TypedArray%.prototype.set on a detached ArrayBuffer") if n < 0
  if src.is_a?(JS:TypedArray)
    sn = js_ta_length(src)
    js_throw_type("Cannot perform %TypedArray%.prototype.set on a detached ArrayBuffer") if sn < 0
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
  res = js_ta_species(t, [len + ~0.0], true)
  if len > 0
    js_ta_valid(t, "%TypedArray%.prototype.slice")
    n2 = js_ta_length(t)
    en = n2 if en > n2
    cnt = en - st
    if cnt > 0
      if res.kind == t.kind
        js_ta_valid(res, "%TypedArray%.prototype.slice")
        sz = js_ta_size(t.kind)
        so = t.offset + st * sz
        do = res.offset
        sb = t.buffer.data
        db = res.buffer.data
        nb = cnt * sz
        bi = 0
        while bi < nb
          db[do + bi] = sb[so + bi]
          bi += 1
      else
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
  res = js_ta_species(t, [n + ~0.0], true)
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
  res = js_ta_species(t, [keep.size + ~0.0], true)
  i = 0
  while i < keep.size
    js_ta_set_idx(res, i, keep[i])
    i += 1
  res

-> js_ta_fill(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.fill")
  js_throw_type("Cannot perform %TypedArray%.prototype.fill on an immutable ArrayBuffer") if t.buffer.immutable
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
  js_throw_type("Cannot perform %TypedArray%.prototype.sort on an immutable ArrayBuffer") if t.buffer.immutable
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
  l = js_merge_sort_num(js_arr_copy(a, 0, mid))
  r = js_merge_sort_num(js_arr_copy(a, mid, n - mid))
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
  rel = js_to_integer(idx)
  actual = rel >= ~0.0 ? rel : rel + n
  num = js_ta_convert(t, v)
  cur_n = js_ta_length(t)
  js_throw_range("Invalid typed array index") if actual < ~0.0 || actual >= cur_n + ~0.0
  ai = actual.to_i
  res = js_ta_create(t.kind, n)
  k = 0
  while k < n
    if k == ai
      js_ta_set_num(res, k, num)
    else
      js_ta_set_idx(res, k, js_ta_get(t, k))
    k += 1
  res

-> js_ta_copy_within(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.copyWithin")
  js_throw_type("Cannot perform %TypedArray%.prototype.copyWithin on an immutable ArrayBuffer") if t.buffer.immutable
  n = js_ta_length(t)
  to = js_rel_index(js_arg(args, 0), n, 0)
  from = js_rel_index(js_arg(args, 1), n, 0)
  fin = js_rel_index(js_arg(args, 2), n, n)
  count = fin - from
  count = n - to if n - to < count
  if count > 0
    js_ta_valid(t, "%TypedArray%.prototype.copyWithin")
    n2 = js_ta_length(t)
    count = n2 - from if n2 - from < count
    count = n2 - to if n2 - to < count
    if count > 0
      if from < to && to < from + count
        k = count - 1
        while k >= 0
          js_ta_set_num(t, to + k, js_ta_get(t, from + k))
          k -= 1
      else
        k = 0
        while k < count
          js_ta_set_num(t, to + k, js_ta_get(t, from + k))
          k += 1
  t

-> js_ta_each(this, args, mode)
  t = js_ta_valid(this, "%TypedArray%.prototype." + mode.to_s)
  n = js_ta_length(t)
  f = js_fn_arg(args, 0, mode.to_s)
  this_arg = js_arg(args, 1)
  i = 0
  while i < n
    v = js_ta_get(t, i)
    res = js_call(f, this_arg, 3, v, i + ~0.0, t, nil, nil)
    return true if mode == :some && js_truthy(res)
    return false if mode == :every && !js_truthy(res)
    i += 1
  return true if mode == :every
  return false if mode == :some
  nil

-> js_ta_reduce(this, args, right)
  t = js_ta_valid(this, right ? "%TypedArray%.prototype.reduceRight" : "%TypedArray%.prototype.reduce")
  n = js_ta_length(t)
  f = js_fn_arg(args, 0, right ? "reduceRight" : "reduce")
  js_throw_type("Reduce of empty array with no initial value") if n == 0 && args.size < 2
  i = right ? n - 1 : 0
  acc = nil
  if args.size >= 2
    acc = args[1]
  else
    acc = js_ta_get(t, i)
    i += right ? -1 : 1
  while right ? i >= 0 : i < n
    acc = js_call(f, nil, 4, acc, js_ta_get(t, i), i + ~0.0, t, nil)
    i += right ? -1 : 1
  acc

-> js_ta_find(this, args, from_end, want_index)
  t = js_ta_valid(this, "%TypedArray%.prototype.find")
  n = js_ta_length(t)
  f = js_fn_arg(args, 0, "find")
  this_arg = js_arg(args, 1)
  i = from_end ? n - 1 : 0
  while from_end ? i >= 0 : i < n
    v = js_ta_get(t, i)
    if js_truthy(js_call(f, this_arg, 3, v, i + ~0.0, t, nil, nil))
      return want_index ? i + ~0.0 : v
    i += from_end ? -1 : 1
  want_index ? ~-1.0 : nil

-> js_ta_at(this, idx)
  t = js_ta_valid(this, "%TypedArray%.prototype.at")
  n = js_ta_length(t)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  return nil if i < ~0.0 || i >= n + ~0.0
  js_ta_get(t, i.to_i)

-> js_ta_includes(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.includes")
  n = js_ta_length(t)
  return false if n == 0
  x = js_arg(args, 0)
  k = js_rel_index(js_arg(args, 1), n, 0)
  while k < n
    return true if js_same_value_zero(js_ta_get(t, k), x)
    k += 1
  false

-> js_ta_index_of(this, args, last)
  t = js_ta_valid(this, last ? "%TypedArray%.prototype.lastIndexOf" : "%TypedArray%.prototype.indexOf")
  n = js_ta_length(t)
  return ~-1.0 if n == 0
  x = js_arg(args, 0)
  if last
    i = args.size > 1 ? js_to_integer(args[1]) : n - ~1.0
    i = i < ~0.0 ? i + n : (i > n - ~1.0 ? n - ~1.0 : i)
    k = i.to_i
    while k >= 0
      return k + ~0.0 if k < js_ta_length(t) && js_strict_eq(js_ta_get(t, k), x)
      k -= 1
    return ~-1.0
  k = js_rel_index(js_arg(args, 1), n, 0)
  while k < n
    return k + ~0.0 if k < js_ta_length(t) && js_strict_eq(js_ta_get(t, k), x)
    k += 1
  ~-1.0

-> js_ta_join(this, sep_v)
  t = js_ta_valid(this, "%TypedArray%.prototype.join")
  n = js_ta_length(t)
  sep = sep_v == nil ? "," : js_to_string(sep_v)
  sb = StringBuffer()
  i = 0
  while i < n
    sb.append(sep) if i > 0
    v = js_ta_get(t, i)
    sb.append(js_to_string(v)) if !js_nullish?(v)
    i += 1
  sb.to_s

-> js_ta_reverse(this)
  t = js_ta_valid(this, "%TypedArray%.prototype.reverse")
  js_throw_type("Cannot perform %TypedArray%.prototype.reverse on an immutable ArrayBuffer") if t.buffer.immutable
  n = js_ta_length(t)
  lo = 0
  hi = n - 1
  while lo < hi
    lv = js_ta_get(t, lo)
    hv = js_ta_get(t, hi)
    js_ta_set_num(t, lo, hv)
    js_ta_set_num(t, hi, lv)
    lo += 1
    hi -= 1
  t

-> js_ta_to_locale_string(this)
  t = js_ta_valid(this, "%TypedArray%.prototype.toLocaleString")
  n = js_ta_length(t)
  parts = []
  i = 0
  while i < n
    v = js_ta_get(t, i)
    parts.push(js_nullish?(v) ? "" : js_to_string(js_invoke(v, "toLocaleString", JS_NO_ARGS)))
    i += 1
  parts.join(",")

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
  js_throw_type("Cannot perform DataView constructor on a detached ArrayBuffer") if b.detached
  js_throw_range("Invalid DataView length " + len.to_s) if off + len > b.blen
  d = js_special_new(js_realm().proto_from(nt, "DataView"), "DataView", :view)
  js_throw_type("Cannot perform DataView constructor on a detached ArrayBuffer") if b.detached
  js_throw_range("Start offset " + off.to_s + " is outside the bounds of the buffer") if off > b.blen
  js_throw_range("Invalid DataView length " + len.to_s) if !track && off + len > b.blen
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
  js_throw_type("Cannot perform DataView set on an immutable ArrayBuffer") if setting && this.buffer.immutable
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
  r.getter(abp, "immutable", ->(this, args, nt) js_this_buffer(this, false).immutable)
  r.method(abp, "slice", 2, ->(this, args, nt) js_buffer_slice(this, args, false))
  r.method(abp, "sliceToImmutable", 2, ->(this, args, nt) js_buffer_slice_immutable(this, args))
  r.method(abp, "resize", 1, ->(this, args, nt) js_buffer_resize(this, js_arg(args, 0)))
  r.method(abp, "transfer", 0, ->(this, args, nt) js_buffer_transfer(this, js_arg(args, 0), :preserve))
  r.method(abp, "transferToFixedLength", 0, ->(this, args, nt) js_buffer_transfer(this, js_arg(args, 0), :fixed))
  r.method(abp, "transferToImmutable", 0, ->(this, args, nt) js_buffer_transfer(this, js_arg(args, 0), :immutable))
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
  r.method(tap, "toReversed", 0, ->(this, args, nt) js_ta_reverse(js_ta_copy_like(js_ta_valid(this, "toReversed"))))
  r.method(tap, "with", 2, ->(this, args, nt) js_ta_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(tap, "at", 1, ->(this, args, nt) js_ta_at(this, js_arg(args, 0)))
  r.method(tap, "copyWithin", 2, ->(this, args, nt) js_ta_copy_within(this, args))
  r.method(tap, "every", 1, ->(this, args, nt) js_ta_each(this, args, :every))
  r.method(tap, "some", 1, ->(this, args, nt) js_ta_each(this, args, :some))
  r.method(tap, "forEach", 1, ->(this, args, nt) js_ta_each(this, args, :each))
  r.method(tap, "find", 1, ->(this, args, nt) js_ta_find(this, args, false, false))
  r.method(tap, "findIndex", 1, ->(this, args, nt) js_ta_find(this, args, false, true))
  r.method(tap, "findLast", 1, ->(this, args, nt) js_ta_find(this, args, true, false))
  r.method(tap, "findLastIndex", 1, ->(this, args, nt) js_ta_find(this, args, true, true))
  r.method(tap, "includes", 1, ->(this, args, nt) js_ta_includes(this, args))
  r.method(tap, "indexOf", 1, ->(this, args, nt) js_ta_index_of(this, args, false))
  r.method(tap, "lastIndexOf", 1, ->(this, args, nt) js_ta_index_of(this, args, true))
  r.method(tap, "join", 1, ->(this, args, nt) js_ta_join(this, js_arg(args, 0)))
  r.method(tap, "reduce", 1, ->(this, args, nt) js_ta_reduce(this, args, false))
  r.method(tap, "reduceRight", 1, ->(this, args, nt) js_ta_reduce(this, args, true))
  r.method(tap, "reverse", 0, ->(this, args, nt) js_ta_reverse(this))
  r.method(tap, "toLocaleString", 0, ->(this, args, nt) js_ta_to_locale_string(this))
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
  [["Int8", 0], ["Uint8", 1], ["Int16", 3], ["Uint16", 4], ["Int32", 5], ["Uint32", 6], ["Float16", 11], ["Float32", 7], ["Float64", 8], ["BigInt64", 9], ["BigUint64", 10]].each ->(p)
    js_install_dv_methods(r, dvp, p[0], p[1])
  # Atomics (§25.4)
  atom = js_new_object(op)
  atom.define(SYM_TO_STRING_TAG, "Atomics", ATTR_C)
  r.method(atom, "add", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :add))
  r.method(atom, "sub", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :sub))
  r.method(atom, "and", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :and))
  r.method(atom, "or", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :or))
  r.method(atom, "xor", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :xor))
  r.method(atom, "exchange", 3, ->(this, args, nt) js_atomic_rmw(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), :xchg))
  r.method(atom, "compareExchange", 4, ->(this, args, nt) js_atomic_cmpxchg(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), js_arg(args, 3)))
  r.method(atom, "load", 2, ->(this, args, nt) js_atomic_load(js_arg(args, 0), js_arg(args, 1)))
  r.method(atom, "store", 3, ->(this, args, nt) js_atomic_store(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(atom, "isLockFree", 1, ->(this, args, nt) js_atomic_is_lock_free(js_arg(args, 0)))
  r.method(atom, "wait", 4, ->(this, args, nt) js_atomic_wait(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), js_arg(args, 3)))
  r.method(atom, "waitAsync", 4, ->(this, args, nt) js_atomic_wait_async(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2), js_arg(args, 3)))
  r.method(atom, "notify", 3, ->(this, args, nt) js_atomic_notify(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(atom, "pause", 0, ->(this, args, nt) js_atomic_pause(js_arg(args, 0)))
  r.global.define("Atomics", atom, BUILTIN_ATTRS)
  nil

# ---- Atomics (§25.4) ----

-> js_atomic_validate_ta(ta, waitable = false, mutating = false)
  js_throw_type("Atomics operation requires a TypedArray") if !ta.is_a?(JS:TypedArray)
  k = ta.kind
  if waitable
    js_throw_type("Atomics wait/notify requires Int32Array or BigInt64Array") if k != 5 && k != 9
  else
    js_throw_type("Atomics operation requires an integer TypedArray") if k == 2 || k == 7 || k == 8 || k == 11
  js_throw_type("Atomics operation cannot mutate an immutable ArrayBuffer") if mutating && ta.buffer.immutable
  js_throw_type("TypedArray buffer is detached or out of bounds") if js_ta_length(ta) < 0
  ta

-> js_atomic_validate_index(ta, req_idx)
  n = js_ta_length(ta)
  idx = js_to_index(req_idx)
  js_throw_range("Atomic index " + idx.to_s + " is out of bounds") if idx >= n
  idx

-> js_atomic_check_live(ta, idx)
  n = js_ta_length(ta)
  js_throw_type("TypedArray buffer is detached or out of bounds") if n < 0 || idx >= n
  ta.offset + idx * js_ta_size(ta.kind)

-> js_atomic_u64(v)
  m = (TWO32_INT ## int) * (TWO32_INT ## int)
  r = v % m
  r = r + m if r < 0
  r

-> js_atomic_i64(u)
  half = (TWO32_INT ## int) * 2147483648
  m = (TWO32_INT ## int) * (TWO32_INT ## int)
  u >= half ? u - m : u

-> js_atomic_rmw(ta, req_idx, val, op)
  js_atomic_validate_ta(ta, false, true)
  idx = js_atomic_validate_index(ta, req_idx)
  k = ta.kind
  if js_ta_big?(k)
    bv = js_to_bigint_from(val, false)
    pos = js_atomic_check_live(ta, idx)
    old = js_raw_get(ta.buffer.data, pos, k, true)
    ou = js_atomic_u64(old.v)
    vu = js_atomic_u64(bv.v)
    res_u = op == :add ? js_atomic_u64(ou + vu) : (op == :sub ? js_atomic_u64(ou - vu) : (op == :and ? (ou & vu) : (op == :or ? (ou | vu) : (op == :xor ? (ou ^ vu) : vu))))
    nv = JS:BigIntValue.new(k == 9 ? js_atomic_i64(res_u) : res_u)
    js_raw_set(ta.buffer.data, pos, k, nv, true)
    return old
  num = js_to_integer(val)
  pos = js_atomic_check_live(ta, idx)
  old = js_raw_get(ta.buffer.data, pos, k, true)
  oi = old.to_i
  vi = js_to_uint32(num)
  res = op == :add ? (oi + vi) : (op == :sub ? (oi - vi) : (op == :and ? (oi & vi) : (op == :or ? (oi | vi) : (op == :xor ? (oi ^ vi) : vi))))
  js_raw_set(ta.buffer.data, pos, k, res + ~0.0, true)
  old

-> js_atomic_cmpxchg(ta, req_idx, exp_v, repl_v)
  js_atomic_validate_ta(ta, false, true)
  idx = js_atomic_validate_index(ta, req_idx)
  k = ta.kind
  if js_ta_big?(k)
    eb = js_to_bigint_from(exp_v, false)
    rb = js_to_bigint_from(repl_v, false)
    pos = js_atomic_check_live(ta, idx)
    old = js_raw_get(ta.buffer.data, pos, k, true)
    if js_atomic_u64(old.v) == js_atomic_u64(eb.v)
      js_raw_set(ta.buffer.data, pos, k, rb, true)
    elsif JS_AGENT_YIELD_HOOK[0] != nil
      JS_AGENT_YIELD_HOOK[0].call(~0.0002)
    return old
  en = js_to_integer(exp_v)
  rn = js_to_integer(repl_v)
  pos = js_atomic_check_live(ta, idx)
  old = js_raw_get(ta.buffer.data, pos, k, true)
  mask = k <= 1 ? 255 : (k <= 4 ? 65535 : 4294967295)
  if (old.to_i & mask) == (js_to_uint32(en) & mask)
    js_raw_set(ta.buffer.data, pos, k, js_to_uint32(rn) + ~0.0, true)
  elsif JS_AGENT_YIELD_HOOK[0] != nil
    JS_AGENT_YIELD_HOOK[0].call(~0.0002)
  old

-> js_atomic_load(ta, req_idx)
  js_atomic_validate_ta(ta, false)
  idx = js_atomic_validate_index(ta, req_idx)
  pos = js_atomic_check_live(ta, idx)
  v = js_raw_get(ta.buffer.data, pos, ta.kind, true)
  if JS_AGENT_YIELD_HOOK[0] != nil
    JS_ATOMIC_SPIN[0] = JS_ATOMIC_SPIN[0] + 1
    if (JS_ATOMIC_SPIN[0] & 7) == 0
      JS_AGENT_YIELD_HOOK[0].call(~0.0002)
  v

-> js_atomic_store(ta, req_idx, val)
  js_atomic_validate_ta(ta, false, true)
  idx = js_atomic_validate_index(ta, req_idx)
  k = ta.kind
  if js_ta_big?(k)
    bv = js_to_bigint_from(val, false)
    pos = js_atomic_check_live(ta, idx)
    js_raw_set(ta.buffer.data, pos, k, bv, true)
    return bv
  num = js_to_integer(val)
  num = ~0.0 if num == ~0.0
  pos = js_atomic_check_live(ta, idx)
  js_raw_set(ta.buffer.data, pos, k, js_to_uint32(num) + ~0.0, true)
  num

-> js_atomic_is_lock_free(size)
  n = js_to_integer(size)
  n == ~1.0 || n == ~2.0 || n == ~4.0 || n == ~8.0

# Shared waiter list & multi-agent coordination hooks for Atomics.wait / waitAsync / notify.
+ AtomicWaiter
  rw :buf_data, :byte_pos, :is_async, :status, :promise, :resolve, :realm, :deadline
  -> new(@buf_data, @byte_pos, @is_async, @deadline)
    @status = nil
    @promise = nil
    @resolve = nil
    @realm = nil

JS_WAITERS = []
JS_CAN_BLOCK = [false]
JS_AGENT_YIELD_HOOK = [nil]
JS_ATOMIC_SPIN = [0]

-> js_wait_async_result(is_async, val)
  o = js_realm().new_object
  o.put_own("async", is_async)
  o.put_own("value", val)
  o

-> js_atomic_do_wait(ta, req_idx, val, timeout, is_async)
  js_atomic_validate_ta(ta, true)
  js_throw_type("Atomics." + (is_async ? "waitAsync" : "wait") + " requires a SharedArrayBuffer") if !ta.buffer.shared
  idx = js_atomic_validate_index(ta, req_idx)
  k = ta.kind
  exp_big = nil
  exp_i32 = 0
  if js_ta_big?(k)
    exp_big = js_atomic_i64(js_atomic_u64(js_to_bigint_from(val, false).v))
  else
    exp_i32 = js_to_int32(val)
  q = js_to_number(timeout)
  t = (q != q) ? INF : (q < ~0.0 ? ~0.0 : q)
  if !is_async && !JS_CAN_BLOCK[0]
    js_throw_type("Atomics.wait cannot be called in this context")
  pos = js_atomic_check_live(ta, idx)
  cur = js_raw_get(ta.buffer.data, pos, k, true)
  eq = js_ta_big?(k) ? (cur.v == exp_big) : (cur.to_i == exp_i32)
  if !eq
    return is_async ? js_wait_async_result(false, "not-equal") : "not-equal"
  if t == ~0.0
    return is_async ? js_wait_async_result(false, "timed-out") : "timed-out"
  dl = t == INF ? INF : (clock() + t / ~1000.0)
  w = JS:AtomicWaiter.new(ta.buffer.data, pos, is_async, dl)
  if is_async
    cap = js_new_capability()
    w.promise = cap.promise
    w.resolve = cap.resolve
    w.realm = js_realm()
    JS_WAITERS.push(w)
    return js_wait_async_result(true, cap.promise)
  JS_WAITERS.push(w)
  while w.status == nil
    if w.deadline != INF && clock() >= w.deadline
      wi = JS_WAITERS.index(w)
      JS_WAITERS.delete_at(wi) if wi != nil
      w.status = "timed-out"
      break
    if JS_AGENT_YIELD_HOOK[0] != nil
      JS_AGENT_YIELD_HOOK[0].call(~0.0005)
    else
      rem = w.deadline == INF ? ~0.001 : (w.deadline - clock())
      sleep(rem > ~0.001 ? ~0.001 : (rem > ~0.0 ? rem : ~0.0001))
  w.status

-> js_atomic_wait(ta, req_idx, val, timeout)
  js_atomic_do_wait(ta, req_idx, val, timeout, false)

-> js_atomic_wait_async(ta, req_idx, val, timeout)
  js_atomic_do_wait(ta, req_idx, val, timeout, true)

-> js_wait_async_poll
  now = clock()
  i = 0
  pending = 0
  while i < JS_WAITERS.size
    w = JS_WAITERS[i]
    if w.is_async
      if w.deadline != INF && now >= w.deadline
        JS_WAITERS.delete_at(i)
        w.status = "timed-out"
        prev = JS_REALM[0]
        JS_REALM[0] = w.realm
        begin
          js_call_arr(w.resolve, nil, ["timed-out"])
        rescue e
          nil
        JS_REALM[0] = prev
        next
      pending += 1
    i += 1
  pending

-> js_atomic_notify(ta, req_idx, count)
  js_atomic_validate_ta(ta, true)
  idx = js_atomic_validate_index(ta, req_idx)
  c = INF
  if count != nil
    ci = js_to_integer(count)
    c = ci < ~0.0 ? ~0.0 : ci
  return ~0.0 if !ta.buffer.shared
  pos = js_atomic_check_live(ta, idx)
  bdata = ta.buffer.data
  woken = 0
  i = 0
  while i < JS_WAITERS.size && (c == INF || woken + ~0.0 < c)
    w = JS_WAITERS[i]
    if w.buf_data == bdata && w.byte_pos == pos
      JS_WAITERS.delete_at(i)
      w.status = "ok"
      if w.is_async
        prev = JS_REALM[0]
        JS_REALM[0] = w.realm
        begin
          js_call_arr(w.resolve, nil, ["ok"])
        rescue e
          nil
        JS_REALM[0] = prev
      woken += 1
    else
      i += 1
  if woken == 0 && JS_AGENT_YIELD_HOOK[0] != nil
    JS_AGENT_YIELD_HOOK[0].call(~0.0002)
  woken + ~0.0

-> js_atomic_pause(n)
  if n != nil
    js_throw_type("Atomics.pause argument must be an integral number") if !js_is_integer?(n)
  nil

# ---- Uint8Array Base64 & Hex (ES2026) ----

JS_B64_STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
JS_B64_URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
JS_HEX_LO = "0123456789abcdef"

-> js_u8_check(this, what, mutating = false)
  js_throw_type("Uint8Array.prototype." + what + " requires a Uint8Array receiver") if !(this.is_a?(JS:TypedArray) && this.kind == 1)
  js_throw_type("Cannot perform Uint8Array.prototype." + what + " on an immutable ArrayBuffer") if mutating && this.buffer.immutable
  this

-> js_b64_opts(opts, for_encode)
  if opts == nil
    return for_encode ? ["base64", false] : ["base64", "loose"]
  js_throw_type("Options must be an object") if !js_object?(opts)
  alpha = jget(opts, "alphabet")
  if alpha == nil
    alpha = "base64"
  elsif alpha != "base64" && alpha != "base64url"
    js_throw_type("Invalid base64 alphabet")
  if for_encode
    omit = js_to_boolean(jget(opts, "omitPadding"))
    return [alpha, omit]
  lch = jget(opts, "lastChunkHandling")
  if lch == nil
    lch = "loose"
  elsif lch != "loose" && lch != "strict" && lch != "stop-before-partial"
    js_throw_type("Invalid lastChunkHandling option")
  [alpha, lch]

-> js_u8_b64_val(b, url)
  return b - 65 if b >= 65 && b <= 90
  return b - 71 if b >= 97 && b <= 122
  return b + 4 if b >= 48 && b <= 57
  if url
    return 62 if b == 45
    return 63 if b == 95
  else
    return 62 if b == 43
    return 63 if b == 47
  -1

-> js_u8_b64_ws?(b)
  b == 9 || b == 10 || b == 12 || b == 13 || b == 32

# Spec FromBase64(string, alphabet, lastChunkHandling, maxLength).
# Returns [read, bytes_array, err_msg_or_nil].
-> js_from_base64_core(s, alpha, lch, max_len)
  return [0, [], nil] if max_len != nil && max_len == 0
  url = alpha == "base64url"
  n = s.size
  out = []
  read = 0
  chunk = []
  i = 0
  while true
    while i < n && js_u8_b64_ws?(s.byte_at(i))
      i += 1
    if i >= n
      if chunk.size > 0
        return [read, out, nil] if lch == "stop-before-partial"
        return [read, out, "Base64 input missing padding in strict mode"] if lch == "strict"
        return [read, out, "Invalid base64 chunk length"] if chunk.size == 1
        if chunk.size == 2
          out.push((chunk[0] << 2) | (chunk[1] >> 4))
        else
          out.push((chunk[0] << 2) | (chunk[1] >> 4))
          out.push(((chunk[1] & 15) << 4) | (chunk[2] >> 2))
      return [n, out, nil]
    b = s.byte_at(i)
    i += 1
    if b == 61
      return [read, out, "Unexpected padding character"] if chunk.size < 2
      while i < n && js_u8_b64_ws?(s.byte_at(i))
        i += 1
      if chunk.size == 2
        if i >= n
          return [read, out, nil] if lch == "stop-before-partial"
          return [read, out, "Incomplete base64 padding"]
        return [read, out, "Invalid base64 padding"] if s.byte_at(i) != 61
        i += 1
        while i < n && js_u8_b64_ws?(s.byte_at(i))
          i += 1
      return [read, out, "Unexpected character after base64 padding"] if i < n
      if chunk.size == 2
        return [read, out, "Non-zero padding bits in strict mode"] if lch == "strict" && (chunk[1] & 15) != 0
        out.push((chunk[0] << 2) | (chunk[1] >> 4))
      else
        return [read, out, "Non-zero padding bits in strict mode"] if lch == "strict" && (chunk[2] & 3) != 0
        out.push((chunk[0] << 2) | (chunk[1] >> 4))
        out.push(((chunk[1] & 15) << 4) | (chunk[2] >> 2))
      return [n, out, nil]
    v = js_u8_b64_val(b, url)
    return [read, out, "Invalid base64 character"] if v < 0
    if max_len != nil
      rem = max_len - out.size
      if (rem == 1 && chunk.size == 2) || (rem == 2 && chunk.size == 3)
        return [read, out, nil]
    chunk.push(v)
    if chunk.size == 4
      out.push((chunk[0] << 2) | (chunk[1] >> 4))
      out.push(((chunk[1] & 15) << 4) | (chunk[2] >> 2))
      out.push(((chunk[2] & 3) << 6) | chunk[3])
      chunk.clear
      read = i
      return [read, out, nil] if max_len != nil && out.size == max_len
  [read, out, nil]

-> js_u8_from_base64(str, opts)
  js_throw_type("Uint8Array.fromBase64 requires a string argument") if !js_string?(str)
  o = js_b64_opts(opts, false)
  res = js_from_base64_core(str, o[0], o[1], nil)
  js_throw_syntax(res[2]) if res[2] != nil
  bytes = res[1]
  t = js_ta_create(1, bytes.size)
  d = t.buffer.data
  i = 0
  while i < bytes.size
    d[i] = bytes[i]
    i += 1
  t

-> js_u8_set_from_base64(this, str, opts)
  t = js_u8_check(this, "setFromBase64", true)
  js_throw_type("Uint8Array.prototype.setFromBase64 requires a string argument") if !js_string?(str)
  o = js_b64_opts(opts, false)
  n = js_ta_length(t)
  js_throw_type("Cannot perform Uint8Array.prototype.setFromBase64 on a detached ArrayBuffer") if n < 0
  res = js_from_base64_core(str, o[0], o[1], n)
  bytes = res[1]
  d = t.buffer.data
  off = t.offset
  i = 0
  while i < bytes.size
    d[off + i] = bytes[i]
    i += 1
  js_throw_syntax(res[2]) if res[2] != nil
  out = js_realm().new_object
  out.put_own("read", res[0] + ~0.0)
  out.put_own("written", bytes.size + ~0.0)
  out

-> js_u8_to_base64(this, opts)
  t = js_u8_check(this, "toBase64", false)
  o = js_b64_opts(opts, true)
  n = js_ta_length(t)
  js_throw_type("Cannot perform Uint8Array.prototype.toBase64 on a detached ArrayBuffer") if n < 0
  tbl = o[0] == "base64url" ? JS_B64_URL : JS_B64_STD
  omit = o[1]
  d = t.buffer.data
  off = t.offset
  sb = StringBuffer()
  i = 0
  while i + 2 < n
    v = (d[off + i] << 16) | (d[off + i + 1] << 8) | d[off + i + 2]
    sb.append(tbl.slice((v >> 18) & 63, 1))
    sb.append(tbl.slice((v >> 12) & 63, 1))
    sb.append(tbl.slice((v >> 6) & 63, 1))
    sb.append(tbl.slice(v & 63, 1))
    i += 3
  rem = n - i
  if rem == 1
    v = d[off + i]
    sb.append(tbl.slice((v >> 2) & 63, 1))
    sb.append(tbl.slice((v & 3) << 4, 1))
    sb.append("==") if !omit
  elsif rem == 2
    v = (d[off + i] << 8) | d[off + i + 1]
    sb.append(tbl.slice((v >> 10) & 63, 1))
    sb.append(tbl.slice((v >> 4) & 63, 1))
    sb.append(tbl.slice((v & 15) << 2, 1))
    sb.append("=") if !omit
  sb.to_s

-> js_u8_hex_digit(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 87 if b >= 97 && b <= 102
  return b - 55 if b >= 65 && b <= 70
  -1

-> js_from_hex_core(s, max_len)
  n = s.size
  js_throw_syntax("Hex string must have even length") if (n & 1) != 0
  return [0, [], nil] if max_len != nil && max_len == 0
  out = []
  i = 0
  while i < n
    break if max_len != nil && out.size >= max_len
    hi = js_u8_hex_digit(s.byte_at(i))
    lo = js_u8_hex_digit(s.byte_at(i + 1))
    return [i, out, "Invalid hex character"] if hi < 0 || lo < 0
    out.push((hi << 4) | lo)
    i += 2
  [i, out, nil]

-> js_u8_from_hex(str)
  js_throw_type("Uint8Array.fromHex requires a string argument") if !js_string?(str)
  res = js_from_hex_core(str, nil)
  js_throw_syntax(res[2]) if res[2] != nil
  bytes = res[1]
  t = js_ta_create(1, bytes.size)
  d = t.buffer.data
  i = 0
  while i < bytes.size
    d[i] = bytes[i]
    i += 1
  t

-> js_u8_set_from_hex(this, str)
  t = js_u8_check(this, "setFromHex", true)
  js_throw_type("Uint8Array.prototype.setFromHex requires a string argument") if !js_string?(str)
  n = js_ta_length(t)
  js_throw_type("Cannot perform Uint8Array.prototype.setFromHex on a detached ArrayBuffer") if n < 0
  res = js_from_hex_core(str, n)
  bytes = res[1]
  d = t.buffer.data
  off = t.offset
  i = 0
  while i < bytes.size
    d[off + i] = bytes[i]
    i += 1
  js_throw_syntax(res[2]) if res[2] != nil
  out = js_realm().new_object
  out.put_own("read", res[0] + ~0.0)
  out.put_own("written", bytes.size + ~0.0)
  out

-> js_u8_to_hex(this)
  t = js_u8_check(this, "toHex", false)
  n = js_ta_length(t)
  js_throw_type("Cannot perform Uint8Array.prototype.toHex on a detached ArrayBuffer") if n < 0
  d = t.buffer.data
  off = t.offset
  sb = StringBuffer()
  i = 0
  while i < n
    b = d[off + i]
    sb.append(JS_HEX_LO.slice((b >> 4) & 15, 1))
    sb.append(JS_HEX_LO.slice(b & 15, 1))
    i += 1
  sb.to_s

-> js_buffer_max(b)
  (b.max_len == nil ? b.blen : b.max_len) + ~0.0

-> js_buffer_grow(this, nv)
  b = js_this_buffer(this, true)
  js_throw_type("SharedArrayBuffer.prototype.grow called on a non-growable buffer") if b.max_len == nil
  n = js_to_index(nv)
  js_throw_range("Invalid length") if n > b.max_len || n < b.blen
  b.blen = n
  JS_AB_EPOCH[0] = JS_AB_EPOCH[0] + 1
  nil

-> js_install_ta_getter(r, tap, g)
  r.getter(tap, g, ->(this, args, nt) js_ta_getter(this, g))

-> js_install_ta_kind(r, tac, tap, k)
  nm = TA_KINDS[k][0]
  p = js_new_object(tap)
  c = r.constructor(nm, 3, ->(this, args, nt) js_ta_ctor(k, args, nt), p)
  c.set_prototype_of(tac)
  r.constant(c, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)
  r.constant(p, "BYTES_PER_ELEMENT", TA_KINDS[k][1] + ~0.0)
  if k == 1
    r.method(c, "fromBase64", 1, ->(this, args, nt) js_u8_from_base64(js_arg(args, 0), js_arg(args, 1)))
    r.method(c, "fromHex", 1, ->(this, args, nt) js_u8_from_hex(js_arg(args, 0)))
    r.method(p, "toBase64", 0, ->(this, args, nt) js_u8_to_base64(this, js_arg(args, 0)))
    r.method(p, "toHex", 0, ->(this, args, nt) js_u8_to_hex(this))
    r.method(p, "setFromBase64", 1, ->(this, args, nt) js_u8_set_from_base64(this, js_arg(args, 0), js_arg(args, 1)))
    r.method(p, "setFromHex", 1, ->(this, args, nt) js_u8_set_from_hex(this, js_arg(args, 0)))

-> js_install_dv_methods(r, dvp, nm, kind)
  r.method(dvp, "get" + nm, 1, ->(this, args, nt) js_dv_access(this, kind, args, false))
  r.method(dvp, "set" + nm, 2, ->(this, args, nt) js_dv_access(this, kind, args, true))

-> js_dv_check(v)
  js_throw_type("Receiver is not a DataView") if !v.is_a?(JS:DataView)
  v

-> js_dv_byte_length(this)
  d = js_dv_check(this)
  n = js_dv_len(d)
  n < 0 ? ~0.0 : n + ~0.0

-> js_dv_byte_offset(this)
  d = js_dv_check(this)
  js_dv_len(d) < 0 ? ~0.0 : d.offset + ~0.0
