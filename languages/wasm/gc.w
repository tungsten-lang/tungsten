# wasm/gc — GC proposal: struct / array / i31 instructions (OP_EXT slow path), casts, and the
# GC instructions allowed in constant expressions.
#
# Representation: struct fields live in WStruct.nums (two words per field, enough for
# v128) or WStruct.refs; array elements in WArray.nums (one word, two for v128) or refs.
# Packed i8/i16 values are stored masked to their width. i31ref is a Tungsten Int in
# [0, 2^31) (the low 31 bits), so ref.eq on i31 compares values.

-> w_storage_bytes(t)
  return 1 if t == T_I8
  return 2 if t == T_I16
  return 4 if t == T_I32 || t == T_F32
  return 16 if t == T_V128
  8

# Store a value (slot-normalised) into packed storage width.
-> w_pack(t, v)
  return v & 0xff if t == T_I8
  return v & 0xffff if t == T_I16
  v

# Read a packed field as an i32 (signed or not).
-> w_unpack(t, v, signed)
  if t == T_I8
    return signed && v >= 128 ? (v - 256) & 0xffffffff : v
  if t == T_I16
    return signed && v >= 32768 ? (v - 65536) & 0xffffffff : v
  v

-> w_struct_new(st, vals)
  n = st.ftypes.size
  s = WStruct.new(st.canon, n)
  k = 0
  while k < n
    w_field_set(s, st, k, vals == nil ? nil : vals[k])
    k += 1
  s

-> w_field_set(s, st, k, v)
  t = st.ftypes[k]
  if wt_ref?(t)
    s.refs[k] = v
  elsif t == T_V128
    s.nums[2 * k] = v == nil ? 0 : v.lo
    s.nums[2 * k + 1] = v == nil ? 0 : v.hi
  else
    s.nums[2 * k] = v == nil ? 0 : w_pack(t, v)
  nil

-> w_field_get(s, st, k, signed)
  t = st.ftypes[k]
  return s.refs[k] if wt_ref?(t)
  return WV128.new(s.nums[2 * k], s.nums[2 * k + 1]) if t == T_V128
  w_unpack(t, s.nums[2 * k], signed)

-> w_array_alloc(at, n)
  w_trap_code(13) if n < 0 || n > 100000000
  t = at.ftypes[0]
  WArray.new(at.canon, n, wt_ref?(t), t == T_V128)

-> w_elem_set(a, at, i, v)
  t = at.ftypes[0]
  if wt_ref?(t)
    a.refs[i] = v
  elsif t == T_V128
    a.nums[2 * i] = v.lo
    a.nums[2 * i + 1] = v.hi
  else
    a.nums[i] = w_pack(t, v)
  nil

-> w_elem_get(a, at, i, signed)
  t = at.ftypes[0]
  return a.refs[i] if wt_ref?(t)
  return WV128.new(a.nums[2 * i], a.nums[2 * i + 1]) if t == T_V128
  w_unpack(t, a.nums[i], signed)

# Read one element of storage type t from bytes at p (little-endian).
-> w_read_elem_bytes(b, p, t)
  n = w_storage_bytes(t)
  if n == 16
    return WV128.new(w_read_le(b, p, 8), w_read_le(b, p + 8, 8))
  w_read_le(b, p, n)

-> w_read_le(b, p, n)
  v = 0
  k = 0
  while k < n
    v = (v | (b[p + k] << (8 * k))) ## i64
    k += 1
  v

# Does reference v match heap type ht (null allowed iff nullable)?
-> w_ref_test?(v, ht, nullable)
  return nullable if v == nil
  if ht < HT_ABS
    return W_TYPES.sub?(v.type, ht) if v.is_a?(WStruct) || v.is_a?(WArray) || v.is_a?(WFunc)
    return false
  return v.is_a?(Integer) || v.is_a?(WStruct) || v.is_a?(WArray) || v.is_a?(WExtern) if ht == HT_ANY
  return v.is_a?(Integer) || v.is_a?(WStruct) || v.is_a?(WArray) if ht == HT_EQ
  return v.is_a?(Integer) if ht == HT_I31
  return v.is_a?(WStruct) if ht == HT_STRUCT
  return v.is_a?(WArray) if ht == HT_ARRAY
  return v.is_a?(WFunc) if ht == HT_FUNC
  return v.is_a?(WExn) if ht == HT_EXN
  return true if ht == HT_EXTERN
  false

-> w_ext_gc(ex, inst, sub, code, o, fp)
  stk = ex.stk
  ostk = ex.ostk
  m = inst.mod
  if sub == 0 || sub == 1
    st = m.type_at(code[o])
    vals = nil
    if sub == 0
      vals = []
      s = fp + code[o + 2]
      st.ftypes.each ->(t)
        ut = wt_unpack(t)
        vals.push(w_slot_read(ex, ut, s))
        s += wt_slots(ut)
    ostk[fp + code[o + 1]] = w_struct_new(st, vals)
  elsif sub >= 2 && sub <= 4
    st = m.type_at(code[o])
    fi = code[o + 1]
    s = ostk[fp + code[o + 3]]
    w_trap_code(15) if s == nil
    w_slot_write(ex, wt_unpack(st.ftypes[fi]), fp + code[o + 2], w_field_get(s, st, fi, sub == 3))
  elsif sub == 5
    st = m.type_at(code[o])
    fi = code[o + 1]
    s = ostk[fp + code[o + 2]]
    w_trap_code(15) if s == nil
    w_field_set(s, st, fi, w_slot_read(ex, wt_unpack(st.ftypes[fi]), fp + code[o + 3]))
  elsif sub == 6 || sub == 7
    at = m.type_at(code[o])
    n = stk[fp + code[o + 3]]
    a = w_array_alloc(at, n)
    if sub == 6
      v = w_slot_read(ex, wt_unpack(at.ftypes[0]), fp + code[o + 2])
      k = 0
      while k < n
        w_elem_set(a, at, k, v)
        k += 1
    ostk[fp + code[o + 1]] = a
  elsif sub == 8
    at = m.type_at(code[o])
    n = code[o + 3]
    a = w_array_alloc(at, n)
    ut = wt_unpack(at.ftypes[0])
    s = fp + code[o + 2]
    k = 0
    while k < n
      w_elem_set(a, at, k, w_slot_read(ex, ut, s))
      s += wt_slots(ut)
      k += 1
    ostk[fp + code[o + 1]] = a
  elsif sub == 9
    at = m.type_at(code[o])
    di = code[o + 1]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    t = at.ftypes[0]
    sz = w_storage_bytes(t)
    seg = m.datas[di]
    slen = inst.dropped_data[di] ? 0 : seg.size
    w_trap_code(5) if s + n * sz > slen
    a = w_array_alloc(at, n)
    k = 0
    while k < n
      w_elem_set(a, at, k, w_read_elem_bytes(m.bytes, seg.start + s + k * sz, t))
      k += 1
    ostk[fp + code[o + 2]] = a
  elsif sub == 10
    at = m.type_at(code[o])
    seg = inst.elems[code[o + 1]]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    w_trap_code(11) if s + n > seg.size
    a = w_array_alloc(at, n)
    k = 0
    while k < n
      w_elem_set(a, at, k, seg[s + k])
      k += 1
    ostk[fp + code[o + 2]] = a
  elsif sub >= 11 && sub <= 13
    at = m.type_at(code[o])
    a = ostk[fp + code[o + 2]]
    w_trap_code(16) if a == nil
    i = stk[fp + code[o + 3]]
    w_trap_code(13) if i >= a.len
    w_slot_write(ex, wt_unpack(at.ftypes[0]), fp + code[o + 1], w_elem_get(a, at, i, sub == 12))
  elsif sub == 14
    at = m.type_at(code[o])
    a = ostk[fp + code[o + 1]]
    w_trap_code(16) if a == nil
    i = stk[fp + code[o + 2]]
    w_trap_code(13) if i >= a.len
    w_elem_set(a, at, i, w_slot_read(ex, wt_unpack(at.ftypes[0]), fp + code[o + 3]))
  elsif sub == 15
    a = ostk[fp + code[o + 1]]
    w_trap_code(16) if a == nil
    stk[fp + code[o]] = a.len
  elsif sub == 16
    at = m.type_at(code[o])
    a = ostk[fp + code[o + 1]]
    w_trap_code(16) if a == nil
    i = stk[fp + code[o + 2]]
    v = w_slot_read(ex, wt_unpack(at.ftypes[0]), fp + code[o + 3])
    n = stk[fp + code[o + 4]]
    w_trap_code(13) if i + n > a.len
    k = 0
    while k < n
      w_elem_set(a, at, i + k, v)
      k += 1
  elsif sub == 17
    at1 = m.type_at(code[o])
    at2 = m.type_at(code[o + 1])
    a = ostk[fp + code[o + 2]]
    di = stk[fp + code[o + 3]]
    b = ostk[fp + code[o + 4]]
    si = stk[fp + code[o + 5]]
    n = stk[fp + code[o + 6]]
    w_trap_code(16) if a == nil || b == nil
    w_trap_code(13) if di + n > a.len || si + n > b.len
    if di <= si
      k = 0
      while k < n
        w_elem_set(a, at1, di + k, w_elem_get(b, at2, si + k, false))
        k += 1
    else
      k = n - 1
      while k >= 0
        w_elem_set(a, at1, di + k, w_elem_get(b, at2, si + k, false))
        k -= 1
  elsif sub == 18 || sub == 19
    at = m.type_at(code[o])
    si = code[o + 1]
    a = ostk[fp + code[o + 2]]
    i = stk[fp + code[o + 3]]
    s = stk[fp + code[o + 4]]
    n = stk[fp + code[o + 5]]
    w_trap_code(16) if a == nil
    w_trap_code(13) if i + n > a.len
    if sub == 18
      t = at.ftypes[0]
      sz = w_storage_bytes(t)
      seg = m.datas[si]
      slen = inst.dropped_data[si] ? 0 : seg.size
      w_trap_code(5) if s + n * sz > slen
      k = 0
      while k < n
        w_elem_set(a, at, i + k, w_read_elem_bytes(m.bytes, seg.start + s + k * sz, t))
        k += 1
    else
      seg = inst.elems[si]
      w_trap_code(11) if s + n > seg.size
      k = 0
      while k < n
        w_elem_set(a, at, i + k, seg[s + k])
        k += 1
  elsif sub == 20 || sub == 21
    v = ostk[fp + code[o + 2]]
    stk[fp + code[o + 1]] = w_ref_test?(v, code[o], sub == 21) ? 1 : 0
  elsif sub == 22 || sub == 23
    v = ostk[fp + code[o + 2]]
    w_trap_code(12) if !w_ref_test?(v, code[o], sub == 23)
    ostk[fp + code[o + 1]] = v
  elsif sub == 26 || sub == 27
    ostk[fp + code[o]] = ostk[fp + code[o + 1]]
  elsif sub == 28
    ostk[fp + code[o]] = stk[fp + code[o + 1]] & 0x7fffffff
  elsif sub == 29 || sub == 30
    v = ostk[fp + code[o + 1]]
    w_trap_code(17) if v == nil
    if sub == 29 && v >= 1073741824
      stk[fp + code[o]] = (v - 2147483648) & 0xffffffff
    else
      stk[fp + code[o]] = v
  else
    w_trap_code(99)
  nil

# GC instructions in constant expressions; st is the evaluation stack.
-> w_eval_const_gc(inst, r, sub, st)
  m = inst.mod
  if sub == 0 || sub == 1
    t = m.type_at(r.vu32())
    vals = nil
    if sub == 0
      n = t.ftypes.size
      vals = []
      k = 0
      while k < n
        vals.push(st[st.size - n + k])
        k += 1
      k = 0
      while k < n
        st.pop
        k += 1
    st.push(w_struct_new(t, vals))
  elsif sub == 6 || sub == 7
    at = m.type_at(r.vu32())
    n = st.pop
    v = sub == 6 ? st.pop : nil
    a = w_array_alloc(at, n)
    if sub == 6
      k = 0
      while k < n
        w_elem_set(a, at, k, v)
        k += 1
    st.push(a)
  elsif sub == 8
    at = m.type_at(r.vu32())
    n = r.vu32()
    a = w_array_alloc(at, n)
    vals = []
    k = 0
    while k < n
      vals.push(st[st.size - n + k])
      k += 1
    k = 0
    while k < n
      st.pop
      k += 1
    k = 0
    while k < n
      w_elem_set(a, at, k, vals[k])
      k += 1
    st.push(a)
  elsif sub == 28
    st.push(st.pop & 0x7fffffff)
  elsif sub == 26 || sub == 27
    nil
  nil
