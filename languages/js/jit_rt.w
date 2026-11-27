# jsn/jit_rt — Runtime helper dispatch table and ABI constants for the ARM64 JS JIT.
#
# Inside every JITted ARM64 function:
#   x19 = JIT_RT_BASE (pointer to JIT_RT_TBL i64[128])
#   x20 = 0x0001000000000000 (WValue double bias)
#   x21 = 0xFFF0000000000001 (WValue biased double range limit)
#
# Every runtime helper is stored as a zero-capture Tungsten closure's raw C fn_ptr:
# calling entry `idx` with (a0, a1, ...) is simply:
#   mov x0, #0        (captures = NULL)
#   ... args in x1..x7 ...
#   ldr x16, [x19, #(idx*8)]
#   blr x16
# Result arrives in x0 (a boxed WValue).

in JS

# ---- Runtime table slot indices ----
RT_ADD          = 0
RT_SUB          = 1
RT_MUL          = 2
RT_DIV          = 3
RT_MOD          = 4
RT_POW          = 5
RT_LT           = 6
RT_LE           = 7
RT_GT           = 8
RT_GE           = 9
RT_EQ           = 10
RT_SEQ          = 11
RT_BITOR        = 12
RT_BITAND       = 13
RT_BITXOR       = 14
RT_SHL          = 15
RT_SAR          = 16
RT_SHR          = 17
RT_BITNOT       = 18
RT_NEG          = 19
RT_PLUS         = 20
RT_TRUTHY       = 21
RT_TYPEOF       = 22
RT_IN           = 23
RT_INSTANCEOF   = 24
RT_GETP_MISS    = 25   # (o, key, ic_arr, k) -> v
RT_SETP_MISS    = 26   # (o, key, v, ic_arr, k, strict) -> v
RT_GETV         = 27   # (o, key) -> v
RT_SETV         = 28   # (o, key, v, strict) -> v
RT_CALL_0       = 29   # (f, this) -> v
RT_CALL_1       = 30   # (f, this, a0) -> v
RT_CALL_2       = 31   # (f, this, a0, a1) -> v
RT_CALL_3       = 32   # (f, this, a0, a1, a2) -> v
RT_CALL_4       = 33   # (f, this, a0, a1, a2, a3) -> v
RT_CALL_N       = 34   # (f, this, args_arr) -> v
RT_NEW_0        = 35   # (f, ic, k) -> obj
RT_NEW_1        = 36   # (f, ic, k, a0) -> obj
RT_NEW_2        = 37   # (f, ic, k, a0, a1) -> obj
RT_NEW_N        = 38   # (f, args_arr) -> obj
RT_CLOSURE      = 39   # (code, env) -> fn
RT_LIT          = 40   # (shape, a0, a1, a2, a3, a4, a5) -> obj
RT_LIT_N        = 41   # (shape, vals_arr) -> obj
RT_NEW_ARR      = 42   # () -> empty JS array
RT_ARR_PUSH     = 43   # (arr, val) -> new length (slow path / grow)
RT_GGET         = 44   # (cell) -> v
RT_GSET         = 45   # (cell, v, strict) -> v
RT_LSET         = 46   # (cell, v) -> v
RT_LINIT        = 47   # (cell, v, is_const) -> v
RT_ENV_NEW      = 48   # (up) -> JS:Env
RT_ENVN_NEW     = 49   # (up, n) -> JS:EnvN
RT_ENV_GET      = 50   # (env, i) -> v
RT_ENV_SET      = 51   # (env, i, v) -> v
RT_THROW        = 52   # (v) -> never
RT_TO_INT32     = 53   # (v) -> boxed number (int32)
RT_TO_NUMBER    = 54   # (v) -> boxed number
RT_TO_STRING    = 55   # (v) -> string
RT_STR_CAT      = 56   # (a, b) -> string
RT_FMOD_D       = 57   # (a, b) -> boxed fmod
RT_MATH_ROUND   = 58   # (v) -> boxed Math.round(v)
RT_TA_INFO      = 59   # (obj, out_i64_arr) -> 1 if TypedArray & valid, 0 otherwise
RT_GET_PIC_MISS = 60   # (o, key, pic_arr) -> v   (4-way polymorphic IC)
RT_ARR_NEW_CAP  = 61   # (cap_boxed) -> empty JS array with capacity
RT_ARR_MAP_SLOW = 62
RT_SLOPPY_THIS  = 63   # (this) -> boxed sloppy this
RT_DELETE       = 64   # (o, key, strict) -> bool
RT_GDECLARE     = 65   # (cell, v, is_fn) -> nil
RT_OBJ_PROTO    = 66   # () -> realm.object_proto
RT_NEW_OBJ      = 67   # (shape) -> JS:Object.new(shape)
RT_ARR_MARK     = 68   # (arr) -> marked JS array
RT_TONUMERIC    = 69   # (v) -> numeric
RT_INC          = 70   # (v, up) -> v +/- 1
RT_STR_CHARCODE = 71   # (s, idx_boxed) -> boxed charCodeAt
RT_ARR_SORT_NUM = 72   # (arr, cmp_fn) -> arr
RT_MAP_GET      = 73   # (m, k) -> v
RT_MAP_SET      = 74   # (m, k, v) -> m
RT_SET_ADD      = 75   # (s, k) -> s
RT_SET_HAS      = 76   # (s, k) -> bool
RT_STR_SPLIT_CH = 77   # (s, sep) -> JS array
RT_ARR_JOIN     = 78   # (arr, sep) -> string
RT_STR_INDEXOF  = 79   # (s, sub) -> boxed int
RT_STR_SLICE    = 80   # (s, a, b) -> string
RT_INT_TO_STR   = 81   # (i_boxed) -> string
RT_STR_CAT_INT  = 82   # (s, i_boxed) -> string
RT_CALL_METHOD_PIC = 83 # (o, key, pic, argc, a0, a1, a2) -> v
RT_SB_NEW       = 84   # (init_str) -> StringBuffer
RT_SB_APP_VAL   = 85   # (sb, val) -> nil
RT_SB_APP_TPL1  = 86   # (sb, pre, val, suf) -> nil
RT_SB_FINISH    = 87   # (sb) -> string
RT_STR_LEN      = 88   # (s) -> boxed len
RT_TPL1         = 89   # (pre, val, suf) -> string
RT_BA_SB_NEW    = 90   # (init_str) -> JS:JitByteBuf or nil
RT_BA_SB_TPL_I32 = 91  # (jb, pre_str, int_val, suf_str) -> nil
RT_BA_SB_FINISH = 92   # (jb) -> flat String
RT_PROM_THEN    = 93   # (p, on_f, on_r) -> Promise
RT_PROM_RESOLVE = 94   # (v) -> Promise
RT_PROM_THEN_JIT = 95  # (p, fn) -> Promise (pre-verified intrinsic Promise + callable fn)

# ---- Constant slots in JIT_RT_TBL (indices 96..127) ----
RT_K_EPOCH_PTR    = 96
RT_K_AB_EPOCH_PTR = 97
RT_K_NULL_BITS    = 98
RT_K_HOLE_BITS    = 99
RT_K_NAN_BITS     = 100
RT_K_TA_CLSID     = 101
RT_K_OBJ_CLSID    = 102
RT_K_FN_CLSID     = 103
RT_K_PROTO_IDX_PTR = 104
RT_K_SP_LIMIT     = 105  # Native stack floor guard (prevents SIGBUS on deep JIT recursion)
RT_NEW_REGEX      = 106  # (rx) -> JS:Special RegExp
RT_RX_EXEC        = 107  # (re, s) -> match or null
RT_STR_REPLACE    = 108  # (s, pat, repl) -> string
RT_RX_EXEC_CAPS   = 109  # (re, s, caps_arr) -> boxed Int (>=0 match, -1 miss, -2 deopt)
RT_GTYPEOF        = 110  # (cell) -> typeof global without ReferenceError
RT_STR_CHARCODE_IC = 111 # (s, idx_boxed, ic_arr) -> boxed charCodeAt (populates ASCII ptr/len IC)
RT_STR_INDEXOF_IC  = 112 # (s, sub, ic_arr) -> boxed indexOf (populates immutable (s, sub)->res IC)
RT_ARR_NEW_EMPTY_CAP = 113 # (cap_boxed) -> empty JS array pre-reserved to cap (or nil if out of range)
RT_NEW_3           = 114 # (f, ic, a0, a1, a2) -> obj
RT_NEW_4           = 115 # (f, ic, a0, a1, a2, a3) -> obj
RT_STR_INDEXOF2    = 116 # (s, sub, from) -> boxed int
RT_FOR_IN_KEYS     = 117 # (obj) -> Array of enumerable string keys
RT_HAS_PROP        = 118 # (obj, key) -> bool
RT_MAP_DELETE      = 119 # (m, k) -> bool
RT_WM_SET          = 120 # (wm, k, v) -> wm
RT_RX_TEST         = 121 # (re, s) -> bool
RT_OBJ_KEYS        = 122 # (o) -> JS array of own enumerable keys

JIT_RT_TBL = i64[128]
JIT_RT_KEEP = []
JIT_RT_READY = [false]

# Helper: extract the 16-bit WObject.class_id from an object WValue.
fn jit_obj_clsid(v_bits) (i64) i64
  ll <<~IR
    %p = and i64 %v_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %id = load i16, ptr %q, align 2
    %r = zext i16 %id to i64
    ret i64 %r
  IR

# Helper: current native frame/stack pointer for JIT stack-overflow guard.
fn jit_cur_sp() () i64
  ll <<~IR
    %fp = call ptr @llvm.frameaddress.p0(i32 0)
    %r = ptrtoint ptr %fp to i64
    ret i64 %r
  IR

# Fill out_i64[0] = raw byte ptr, out_i64[1] = len, out_i64[2] = kind, out_i64[3] = JS_AB_EPOCH[0].
# Returns true if obj is a valid non-detached JS:TypedArray, false otherwise.
-> jit_ta_info_helper(o, out)
  return false if !o.is_a?(JS:TypedArray) || o.buffer.immutable
  n = js_ta_length(o)
  return false if n < 0
  base = jsr_ba_data_ptr(wvalue_bits(o.buffer.data) ## i64) + (o.offset ## i64)
  out[0] = base
  out[1] = n ## i64
  out[2] = o.kind ## i64
  out[3] = JS_AB_EPOCH[0]
  true

# 4-way polymorphic inline cache miss handler for property reads.
# Layout of pic (i64[16]): 4 entries of [shape, slot_enc, holder, epoch].
-> jit_get_pic_miss(o, key, pic)
  return js_get_prim(o, key) if !o.is_a?(JS:Base)
  s = o.shape
  if !s.dict && js_ivar_cacheable?(o)
    sb = wvalue_bits(s) ## i64
    # Find an empty slot (or overwrite slot 3 if full, keeping first 3 hot shapes)
    slot_k = -1
    e = 0
    while e < 4
      if pic[e * 4] == 0 || pic[e * 4] == sb
        slot_k = e * 4
        break
      e += 1
    slot_k = 12 if slot_k < 0
    i = s.slot_of(key)
    if i >= 0
      if (s.attrs_of(key) & ATTR_ACCESSOR) == 0
        enc = i < s.inline ? (s.ibase + i) : (0 - (i - s.inline) - 1)
        js_ic_fill_get(pic, slot_k, sb, enc ## i64, 0 ## i64, 0 ## i64)
    else
      p = s.proto
      if p != nil && p.is_a?(JS:Base) && js_ivar_cacheable?(p) && p.get_virtual(key) == JS_HOLE && o.get_virtual(key) == JS_HOLE
        ps = p.shape
        j = ps.slot_of(key)
        if j >= 0 && !ps.dict && (ps.attrs_of(key) & ATTR_ACCESSOR) == 0
          enc = j < ps.inline ? (ps.ibase + j) : (0 - (j - ps.inline) - 1)
          js_ic_fill_get(pic, slot_k, sb, enc ## i64, wvalue_bits(p) ## i64, JS_EPOCH[0])
  o.get(key, o)

-> jit_reg(idx, cl)
  JIT_RT_KEEP.push(cl)
  JIT_RT_TBL[idx] = jit_cl_fn(wvalue_bits(cl) ## i64)
  nil

-> jit_arr_push_slow(a, v)
  if js_growable_array?(a)
    a.push(v)
    return a.size + ~0.0
  ok = jset(a, js_len_of(a).to_s, v)
  js_set_failed(a, "push") if !ok
  n = js_len_of(a)
  js_set_len(a, n)
  n + ~0.0

-> jit_math_round(v)
  x = js_to_number(v)
  return x if x != x || x == ~0.0 || x == INF || x == ~0.0 - INF
  return ~-0.0 if x < ~0.0 && x >= ~-0.5
  Math.floor(x + ~0.5)

-> jit_new_arr_empty
  js_mark_array([])

-> jit_new_arr_cap(n)
  ni = js_to_int32(n)
  ni = 0 if ni < 0
  js_mark_array(Array.new(ni, nil))

-> jit_new_arr_empty_cap(n)
  ni = js_to_int32(n)
  return nil if ni <= 0 || ni > 4194304
  a = Array.new(ni, nil)
  a.clear
  js_mark_array(a)

-> jit_sb_new(s)
  return nil if !js_string?(s)
  sb = StringBuffer()
  sb.append(s) if s.size > 0
  sb

-> jit_sb_app_val(sb, v)
  sb.append(js_string?(v) ? v : js_to_string(v))
  nil

-> jit_sb_app_tpl1(sb, pre, v, suf)
  sb.append(pre) if pre.size > 0
  sb.append(js_string?(v) ? v : js_to_string(v))
  sb.append(suf) if suf.size > 0
  nil

-> jit_sb_finish(sb)
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> jit_tpl1(pre, v, suf)
  sv = js_string?(v) ? v : js_to_string(v)
  if pre.size == 0
    return suf.size == 0 ? sv : js_str_cat(sv, suf)
  if suf.size == 0
    return js_str_cat(pre, sv)
  js_str_cat(js_str_cat(pre, sv), suf)

-> jit_str_len(s)
  (s.ascii? ? s.size : js_len(s)) + ~0.0

# Fast LLVM check: returns 1 if every slot in dense WArray `arr_bits` is a flat String (0xFFF9, bit 0 clear).
fn jsr_all_flat_strs(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %stp = getelementptr i8, ptr %q, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st = sext i32 %st32 to i64
    %szp = getelementptr i8, ptr %q, i64 8
    %sz32 = load i32, ptr %szp, align 4
    %sz = sext i32 %sz32 to i64
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    %end = add i64 %st, %sz
    br label %loop
  loop:
    %i = phi i64 [ %st, %0 ], [ %ni, %next ]
    %done = icmp sge i64 %i, %end
    br i1 %done, label %ok, label %body
  body:
    %ep = getelementptr i64, ptr %sl, i64 %i
    %v = load i64, ptr %ep, align 8
    %t = and i64 %v, u0xFFFF000000000001
    %is_s = icmp eq i64 %t, u0xFFF9000000000000
    br i1 %is_s, label %next, label %no
  next:
    %ni = add i64 %i, 1
    br label %loop
  ok:
    ret i64 1
  no:
    ret i64 0
  IR

# Typed LLVM raw byte buffer helpers (shared by loop StringBuilder & JSON.stringify!).
-> jit_u8_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  doff + n

-> jit_u8_put_i64(dst, pos, v) (u8[] i64 i64) i64
  if v == 0
    dst[pos] = 48 ## u8
    return pos + 1
  if v < 0
    dst[pos] = 45 ## u8
    pos += 1
    v = 0 - v
  # Write digits reversed starting at pos, then reverse in-place!
  st = pos
  while v > 0
    q = v / 10
    d = v - q * 10
    dst[pos] = (48 + d) ## u8
    pos += 1
    v = q
  l = st
  r = pos - 1
  while l < r
    tmp = dst[l]
    dst[l] = dst[r]
    dst[r] = tmp
    l += 1
    r -= 1
  pos

+ JitByteBuf
  rw :hdr, :buf, :pos, :cap
  -> new(init_cap = 2048)
    @buf = ByteArray.new(init_cap)
    @pos = 0
    @cap = init_cap
    @hdr = i64[3]
    @hdr[0] = jit_bytearray_ptr(wvalue_bits(@buf) ## i64)
    @hdr[1] = 0
    @hdr[2] = init_cap ## i64
  -> reserve(need)
    return nil if @pos + need <= @cap
    nc = @cap * 2
    while nc < @pos + need
      nc = nc * 2
    nb = ByteArray.new(nc)
    jit_u8_copy(nb, 0, @buf, 0, @pos) if @pos > 0
    @buf = nb
    @cap = nc
    @hdr[0] = jit_bytearray_ptr(wvalue_bits(@buf) ## i64)
    @hdr[2] = nc ## i64
    nil

JIT_BA_POOL = [nil]
JIT_STR_VIEW_CACHE = {}

-> jit_str_view(s)
  v = JIT_STR_VIEW_CACHE[s]
  if v == nil
    v = ccall("w_string_bytes_view", s) ## u8[]
    JIT_STR_VIEW_CACHE[s] = v if JIT_STR_VIEW_CACHE.size < 256
  v

-> jit_ba_sb_new(s)
  return nil if !js_string?(s)
  jb = JIT_BA_POOL[0]
  if jb != nil
    JIT_BA_POOL[0] = nil
    jb.pos = 0
    jb.hdr[1] = 0
  else
    jb = JS:JitByteBuf.new(2048)
  if s.size > 0
    jb.reserve(s.size)
    sv = ccall("w_string_bytes_view", s) ## u8[]
    p = jit_u8_copy(jb.buf, 0, sv, 0, s.size)
    jb.pos = p
    jb.hdr[1] = p
  jb

-> jit_ba_sb_tpl_i32(jb, pre, iv, suf)
  plen = pre.size
  slen = suf.size
  jb.pos = jb.hdr[1]
  jb.reserve(plen + slen + 16)
  p = jb.pos ## i64
  b = jb.buf
  if plen > 0
    pv = jit_str_view(pre)
    p = jit_u8_copy(b, p, pv, 0, plen)
  p = jit_u8_put_i64(b, p, iv ## i64)
  if slen > 0
    sv = jit_str_view(suf)
    p = jit_u8_copy(b, p, sv, 0, slen)
  jb.pos = p
  jb.hdr[1] = p
  nil

-> jit_ba_sb_finish(jb)
  n = jb.hdr[1]
  res = ""
  if n > 0
    out = ByteArray.new(n + 1)
    jit_u8_copy(out, 0, jb.buf, 0, n)
    res = ccall("w_string_take_byte_array", out, n)
  jb.pos = 0
  jb.hdr[1] = 0
  JIT_BA_POOL[0] = jb if JIT_BA_POOL[0] == nil && jb.cap <= 65536
  res

JIT_SPLIT_BUF = i64[256]

# Fast 1-byte ASCII split scanner: packs <=5 byte tokens as inline WStrings and looks up 6..7 byte
# tokens in lock-free JS_S7 cache! Returns token count (>=1) on full hit, or -1 on cache miss / long token.
-> jit_split1_scan(src_ptr, n, sep_b, out_p, max_out, s7k_p, s7v_p) (i64 i64 i64 i64 i64 i64 i64) i64
  cnt = 0 ## i64
  st = 0 ## i64
  i = 0 ## i64
  while i <= n
    if i == n || jb_ld_u8(src_ptr + i) == sep_b
      return -1 if cnt >= max_out
      len = i - st
      if len <= 5
        jb_st_i64_u(out_p + cnt * 8, jp_pack_inline(src_ptr, st, len))
      elsif len == 6 || len == 7
        hit = js_s7_probe_bits(src_ptr, st, len, s7k_p, s7v_p)
        return -1 if hit == 0
        jb_st_i64_u(out_p + cnt * 8, hit)
      else
        return -1
      cnt += 1
      st = i + 1
    i += 1
  cnt

-> jit_fill_arr_i64(arr_bits, src_p, cnt) (i64 i64 i64) i64
  dst = jit_arr_slots_ptr(arr_bits)
  jb_memcpy_raw(dst, 0, src_p, cnt * 8)
  0

-> jit_str_split_fast(s, sep)
  if js_string?(s) && js_string?(sep) && sep.size > 0
    n = s.size
    return js_mark_array([""]) if n == 0
    if sep.size == 1 && s.ascii?
      sp = jp_flat_str_ptr(wvalue_bits(s) ## i64)
      if sp != 0
        out_p = jit_arr_slots_ptr(wvalue_bits(JIT_SPLIT_BUF) ## i64)
        s7k_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64)
        s7v_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_VALS) ## i64)
        cnt = jit_split1_scan(sp, n ## i64, sep.byte_at(0) ## i64, out_p, 256, s7k_p, s7v_p)
        if cnt > 0
          arr = Array.new(cnt, nil)
          jit_fill_arr_i64(wvalue_bits(arr) ## i64, out_p, cnt)
          return js_mark_array(arr)
        # Cold miss: run native split and warm JS_S7 cache once if cache has room!
        res = s.split(sep)
        if JS_S7_FILL[0] < 8192
          sep_b = sep.byte_at(0) ## i64
          st = 0 ## i64
          i = 0 ## i64
          ti = 0
          while i <= n && ti < res.size
            if i == n || jb_ld_u8(sp + i) == sep_b
              len = i - st
              js_s7_cache_set(sp, st, len, res[ti]) if len == 6 || len == 7
              ti += 1
              st = i + 1
            i += 1
        return js_mark_array(res)
    return js_mark_array(s.split(sep))
  js_str_split(s, sep, nil)

-> jit_str_indexof_fast(s, sub)
  if js_string?(s) && js_string?(sub) && s.ascii?
    return ~0.0 if sub.size == 0
    bi = s.index(sub, 0)
    return (bi == nil ? -1 : bi) + ~0.0
  js_str_index_of(js_this_str(s, "indexOf"), js_to_string(sub), 0) + ~0.0

-> jit_str_indexof2_fast(s, sub, from)
  if js_string?(s) && js_string?(sub) && s.ascii? && js_number?(from)
    n = s.size
    fi = from.to_i
    fi = 0 if fi < 0
    if sub.size == 0
      return (fi > n ? n : fi) + ~0.0
    return ~-1.0 if fi >= n
    bi = s.index(sub, fi)
    return (bi == nil ? -1 : bi) + ~0.0
  js_str_index_of(js_this_str(s, "indexOf"), js_to_string(sub), js_to_integer(js_to_number(from))) + ~0.0

-> jit_str_slice_fast(s, a, b)
  if js_string?(s) && s.ascii? && js_number?(a)
    n = s.size
    ai = a.to_i
    if ai >= 0 && ai <= n && ai.to_f == a
      if b == nil
        return s.slice(ai, n - ai)
      if js_number?(b)
        bi = b.to_i
        if bi >= ai && bi <= n && bi.to_f == b
          return s.slice(ai, bi - ai)
  js_str_slice(js_this_str(s, "slice"), a, b)

# Single-pass flat ByteArray join for dense string arrays (inline 0..5, slab 6, heap 7).
# Returns nil if any element or sep is non-flat/rope/slice-slab (caller falls back cleanly).
-> jit_flat_str_len(v_bits, slab_base) (i64 i64) i64
  return -1 if jb_is_flat_str(v_bits) == 0
  mode = (v_bits >> 1) & 7
  return mode if mode <= 5
  if mode == 6
    return -1 if slab_base == 0
    slot = slab_base + ((v_bits >> 4) & 16777215) * 32
    return -1 if (jb_ld_u8(slot) & 1) == 0
    return jb_ld_u8(slot + 1)
  ws = jb_mask_ptr48(v_bits)
  jb_ld_u32(ws + 8) & 2147483647

-> jit_flat_str_copy(dst_ptr, pos, v_bits, slab_base) (i64 i64 i64 i64) i64
  mode = (v_bits >> 1) & 7
  if mode <= 5
    d = dst_ptr + pos
    j = 0 ## i64
    while j < mode
      jb_st_u8(d + j, (v_bits >> (4 + j * 8)) & 255)
      j += 1
    return pos + mode
  src = 0 ## i64
  len = 0 ## i64
  if mode == 6
    slot = slab_base + ((v_bits >> 4) & 16777215) * 32
    len = jb_ld_u8(slot + 1)
    src = slot + 2
  else
    ws = jb_mask_ptr48(v_bits)
    len = jb_ld_u32(ws + 8) & 2147483647
    src = ws + 16
  jb_memcpy_raw(dst_ptr, pos, src, len)

-> jit_join_measure(arr_bits, sep_len, slab_base) (i64 i64 i64) i64
  sz = jsr_asize(arr_bits)
  return 0 if sz == 0
  st = jb_arr_start(arr_bits)
  sl = jit_arr_slots_ptr(arr_bits) + st * 8
  total = (sz - 1) * sep_len
  i = 0 ## i64
  while i < sz
    el = jb_ld_i64(sl + i * 8)
    l = jit_flat_str_len(el, slab_base)
    return -1 if l < 0
    total += l
    i += 1
  total

-> jit_join_fill(dst_ptr, arr_bits, sep_bits, sep_len, slab_base) (i64 i64 i64 i64 i64) i64
  sz = jsr_asize(arr_bits)
  st = jb_arr_start(arr_bits)
  sl = jit_arr_slots_ptr(arr_bits) + st * 8
  pos = 0 ## i64
  i = 0 ## i64
  while i < sz
    if i > 0 && sep_len > 0
      pos = jit_flat_str_copy(dst_ptr, pos, sep_bits, slab_base)
    el = jb_ld_i64(sl + i * 8)
    pos = jit_flat_str_copy(dst_ptr, pos, el, slab_base)
    i += 1
  pos

-> jit_arr_join_flat(arr, sep)
  js_json_init_lits()
  sb = JS_JSON_SLAB_BASE[0]
  sep_len = jit_flat_str_len(wvalue_bits(sep) ## i64, sb)
  return nil if sep_len < 0
  total = jit_join_measure(wvalue_bits(arr) ## i64, sep_len, sb)
  return nil if total < 0
  return "" if total == 0
  out = ByteArray.new(total + 1)
  dp = jit_bytearray_ptr(wvalue_bits(out) ## i64)
  jit_join_fill(dp, wvalue_bits(arr) ## i64, wvalue_bits(sep) ## i64, sep_len, sb)
  ccall("w_string_take_byte_array", out, total)

# Pack inline ASCII prefix (0..4 bytes) + non-negative integer (total <= 5 bytes) directly into
# an immediate inline WString WValue! Zero allocations, zero memory loads!
fn jit_pack_str_u31_inl(pre_bits, iv) (i64 i64) i64
  ll <<~IR
    %m0 = lshr i64 %pre_bits, 1
    %plen = and i64 %m0, 7
    ; Count digits of iv (caller verified total <= 5 and iv >= 0)
    %lt10 = icmp slt i64 %iv, 10
    br i1 %lt10, label %d1, label %chk2
  d1:
    %c0 = add i64 %iv, 48
    %sh1 = shl i64 %plen, 3
    %sh1b = add i64 %sh1, 4
    %b1 = shl i64 %c0, %sh1b
    %nl1 = add i64 %plen, 1
    %nl1s = shl i64 %nl1, 1
    %p1 = and i64 %pre_bits, -16
    %r1 = or i64 %p1, %nl1s
    %r1f = or i64 %r1, %b1
    ret i64 %r1f
  chk2:
    %lt100 = icmp slt i64 %iv, 100
    br i1 %lt100, label %d2, label %chk3
  d2:
    %q2 = sdiv i64 %iv, 10
    %t2 = mul i64 %q2, 10
    %rem2 = sub i64 %iv, %t2
    %a2 = add i64 %q2, 48
    %b2v = add i64 %rem2, 48
    %b2s = shl i64 %b2v, 8
    %pack2 = or i64 %a2, %b2s
    %sh2 = shl i64 %plen, 3
    %sh2b = add i64 %sh2, 4
    %b2 = shl i64 %pack2, %sh2b
    %nl2 = add i64 %plen, 2
    %nl2s = shl i64 %nl2, 1
    %p2 = and i64 %pre_bits, -16
    %r2 = or i64 %p2, %nl2s
    %r2f = or i64 %r2, %b2
    ret i64 %r2f
  chk3:
    %lt1000 = icmp slt i64 %iv, 1000
    br i1 %lt1000, label %d3, label %chk4
  d3:
    %q3a = sdiv i64 %iv, 100
    %r3a = sub i64 %iv, %q3a
    %t3a = mul i64 %q3a, 100
    %rem3a = sub i64 %iv, %t3a
    %q3b = sdiv i64 %rem3a, 10
    %t3b = mul i64 %q3b, 10
    %rem3b = sub i64 %rem3a, %t3b
    %c30 = add i64 %q3a, 48
    %c31 = add i64 %q3b, 48
    %c32 = add i64 %rem3b, 48
    %c31s = shl i64 %c31, 8
    %c32s = shl i64 %c32, 16
    %p3a = or i64 %c30, %c31s
    %pack3 = or i64 %p3a, %c32s
    %sh3 = shl i64 %plen, 3
    %sh3b = add i64 %sh3, 4
    %b3 = shl i64 %pack3, %sh3b
    %nl3 = add i64 %plen, 3
    %nl3s = shl i64 %nl3, 1
    %p3 = and i64 %pre_bits, -16
    %r3 = or i64 %p3, %nl3s
    %r3f = or i64 %r3, %b3
    ret i64 %r3f
  chk4:
    %lt10000 = icmp slt i64 %iv, 10000
    br i1 %lt10000, label %d4, label %d5
  d4:
    %q4a = sdiv i64 %iv, 1000
    %t4a = mul i64 %q4a, 1000
    %rem4a = sub i64 %iv, %t4a
    %q4b = sdiv i64 %rem4a, 100
    %t4b = mul i64 %q4b, 100
    %rem4b = sub i64 %rem4a, %t4b
    %q4c = sdiv i64 %rem4b, 10
    %t4c = mul i64 %q4c, 10
    %rem4c = sub i64 %rem4b, %t4c
    %c40 = add i64 %q4a, 48
    %c41 = add i64 %q4b, 48
    %c42 = add i64 %q4c, 48
    %c43 = add i64 %rem4c, 48
    %c41s = shl i64 %c41, 8
    %c42s = shl i64 %c42, 16
    %c43s = shl i64 %c43, 24
    %p4a = or i64 %c40, %c41s
    %p4b = or i64 %p4a, %c42s
    %pack4 = or i64 %p4b, %c43s
    %sh4 = shl i64 %plen, 3
    %sh4b = add i64 %sh4, 4
    %b4 = shl i64 %pack4, %sh4b
    %nl4 = add i64 %plen, 4
    %nl4s = shl i64 %nl4, 1
    %p4 = and i64 %pre_bits, -16
    %r4 = or i64 %p4, %nl4s
    %r4f = or i64 %r4, %b4
    ret i64 %r4f
  d5:
    %q5a = sdiv i64 %iv, 10000
    %t5a = mul i64 %q5a, 10000
    %rem5a = sub i64 %iv, %t5a
    %q5b = sdiv i64 %rem5a, 1000
    %t5b = mul i64 %q5b, 1000
    %rem5b = sub i64 %rem5a, %t5b
    %q5c = sdiv i64 %rem5b, 100
    %t5c = mul i64 %q5c, 100
    %rem5c = sub i64 %rem5b, %t5c
    %q5d = sdiv i64 %rem5c, 10
    %t5d = mul i64 %q5d, 10
    %rem5d = sub i64 %rem5c, %t5d
    %c50 = add i64 %q5a, 48
    %c51 = add i64 %q5b, 48
    %c52 = add i64 %q5c, 48
    %c53 = add i64 %q5d, 48
    %c54 = add i64 %rem5d, 48
    %c51s = shl i64 %c51, 8
    %c52s = shl i64 %c52, 16
    %c53s = shl i64 %c53, 24
    %c54s = shl i64 %c54, 32
    %p5a = or i64 %c50, %c51s
    %p5b = or i64 %p5a, %c52s
    %p5c = or i64 %p5b, %c53s
    %pack5 = or i64 %p5c, %c54s
    %b5 = shl i64 %pack5, 4
    %r5 = or i64 u0xFFF900000000000A, %b5
    ret i64 %r5
  IR

-> jit_str_cat_i32_fast(pre, iv)
  if iv >= 0
    pl = pre.size
    if (pl == 1 && iv < 10000) || (pl == 2 && iv < 1000) || (pl == 3 && iv < 100) || (pl == 4 && iv < 10) || (pl == 0 && iv < 100000)
      return wvalue_from_bits(jit_pack_str_u31_inl(wvalue_bits(pre) ## i64, iv ## i64))
  js_str_cat(pre, js_number_to_s(iv + ~0.0))

-> jit_str_charcode_fast(s, idx)
  if js_string?(s) && s.ascii? && js_number?(idx)
    ii = idx.to_i
    if ii.to_f == idx
      return (ii >= 0 && ii < s.size) ? (s.byte_at(ii) + ~0.0) : js_nan()
  js_str_char_code_at(js_this_str(s, "charCodeAt"), idx)

-> jit_rx_test_fast(o, s)
  r = js_realm()
  sv = js_string?(s) ? s : js_to_string(s)
  if o.is_a?(JS:Special) && o.shape == r.regexp_shape && sv.ascii?
    rx = o.internal
    if rx.is_a?(JS:Regex)
      fp = rx.jit_tried ? rx.jit_fp : js_rx_ensure_jit(rx)
      if fp != 0
        caps = JS_RX_CAPS
        caps_p = jit_arr_slots_ptr(wvalue_bits(caps) ## i64)
        en = js_rx_exec_caps_raw(o, sv, caps_p)
        return false if en == -1
        if en >= 0
          js_rx_record_legacy(r, rx, sv, caps)
          return true
  res = js_regexp_builtin_exec(o, sv)
  res != JS_NULL && res != nil

# Populate 3-slot IC [str_bits, ascii_ptr, byte_len] when s is an ASCII flat heap string (size >= 6).
-> jit_str_charcode_ic(s, idx, ic)
  if js_string?(s) && s.size >= 6 && s.ascii?
    sp = jp_flat_str_ptr(wvalue_bits(s) ## i64)
    if sp != 0
      ic[0] = wvalue_bits(s) ## i64
      ic[1] = sp
      ic[2] = s.size ## i64
  js_str_char_code_at(js_this_str(s, "charCodeAt"), idx)

# Populate 3-slot IC [str_bits, needle_bits, result_i64] for pure immutable String.prototype.indexOf!
-> jit_str_indexof_ic(s, sub, ic)
  res = jit_str_indexof_fast(s, sub)
  if js_string?(s) && js_string?(sub) && js_number?(res)
    ic[0] = wvalue_bits(s) ## i64
    ic[1] = wvalue_bits(sub) ## i64
    ic[2] = res.to_i ## i64
  res

-> jit_rt_init
  return jit_i64_ptr(JIT_RT_TBL) if JIT_RT_READY[0]
  JIT_RT_READY[0] = true
  jit_reg(RT_ADD,        ->(a, b) js_add(a, b))
  jit_reg(RT_SUB,        ->(a, b) js_sub(a, b))
  jit_reg(RT_MUL,        ->(a, b) js_mul(a, b))
  jit_reg(RT_DIV,        ->(a, b) js_div(a, b))
  jit_reg(RT_MOD,        ->(a, b) js_mod(a, b))
  jit_reg(RT_POW,        ->(a, b) js_pow(a, b))
  jit_reg(RT_LT,         ->(a, b) js_lt(a, b))
  jit_reg(RT_LE,         ->(a, b) js_le(a, b))
  jit_reg(RT_GT,         ->(a, b) js_gt(a, b))
  jit_reg(RT_GE,         ->(a, b) js_ge(a, b))
  jit_reg(RT_EQ,         ->(a, b) js_eq(a, b))
  jit_reg(RT_SEQ,        ->(a, b) js_seq(a, b))
  jit_reg(RT_BITOR,      ->(a, b) js_bitor(a, b))
  jit_reg(RT_BITAND,     ->(a, b) js_bitand(a, b))
  jit_reg(RT_BITXOR,     ->(a, b) js_bitxor(a, b))
  jit_reg(RT_SHL,        ->(a, b) js_shl(a, b))
  jit_reg(RT_SAR,        ->(a, b) js_sar(a, b))
  jit_reg(RT_SHR,        ->(a, b) js_shr(a, b))
  jit_reg(RT_BITNOT,     ->(a) js_bitnot(a))
  jit_reg(RT_NEG,        ->(a) js_neg(a))
  jit_reg(RT_PLUS,       ->(a) js_plus(a))
  jit_reg(RT_TRUTHY,     ->(a) js_truthy(a))
  jit_reg(RT_TYPEOF,     ->(a) js_typeof(a))
  jit_reg(RT_IN,         ->(a, b) js_in(a, b))
  jit_reg(RT_INSTANCEOF, ->(a, b) js_instanceof(a, b))
  jit_reg(RT_GETP_MISS,  ->(o, k, ic, off) js_get_miss(o, k, ic, off))
  jit_reg(RT_SETP_MISS,  ->(o, k, v, ic, off, st) js_set_miss(o, k, v, ic, off, st))
  jit_reg(RT_GETV,       ->(o, k) js_getv(o, k))
  jit_reg(RT_SETV,       ->(o, k, v, st) js_setv(o, k, v, st))
  jit_reg(RT_CALL_0,     ->(f, t) js_call(f, t, 0, nil, nil, nil, nil, nil))
  jit_reg(RT_CALL_1,     ->(f, t, a0) js_call(f, t, 1, a0, nil, nil, nil, nil))
  jit_reg(RT_CALL_2,     ->(f, t, a0, a1) js_call(f, t, 2, a0, a1, nil, nil, nil))
  jit_reg(RT_CALL_3,     ->(f, t, a0, a1, a2) js_call(f, t, 3, a0, a1, a2, nil, nil))
  jit_reg(RT_CALL_4,     ->(f, t, a0, a1, a2, a3) js_call(f, t, 4, a0, a1, a2, a3, nil))
  jit_reg(RT_CALL_N,     ->(f, t, args) js_call_arr(f, t, args))
  jit_reg(RT_NEW_0,      ->(f, ic, k) js_new_t(f, ic, k, 0, nil, nil, nil, nil, nil))
  jit_reg(RT_NEW_1,      ->(f, ic, k, a0) js_new_t(f, ic, k, 1, a0, nil, nil, nil, nil))
  jit_reg(RT_NEW_2,      ->(f, ic, k, a0, a1) js_new_t(f, ic, k, 2, a0, a1, nil, nil, nil))
  jit_reg(RT_NEW_N,      ->(f, args) js_new_arr(f, args))
  jit_reg(RT_CLOSURE,    ->(c, e) js_closure(c, e))
  jit_reg(RT_LIT,        ->(sh, a0, a1, a2, a3, a4, a5) js_lit(sh, a0, a1, a2, a3, a4, a5))
  jit_reg(RT_LIT_N,      ->(sh, vs) js_lit_n(sh, vs))
  jit_reg(RT_NEW_ARR,    ->() jit_new_arr_empty())
  jit_reg(RT_ARR_PUSH,   ->(a, v) jit_arr_push_slow(a, v))
  jit_reg(RT_GGET,       ->(c) js_gget(c))
  jit_reg(RT_GSET,       ->(c, v, st) js_gset(c, v, st))
  jit_reg(RT_LSET,       ->(c, v) js_lset(c, v))
  jit_reg(RT_LINIT,      ->(c, v, ic) js_linit(c, v, ic))
  jit_reg(RT_ENV_NEW,    ->(up) JS:Env.new(up))
  jit_reg(RT_ENVN_NEW,   ->(up, n) JS:EnvN.new(up, n))
  jit_reg(RT_ENV_GET,    ->(e, i) js_env_get(e, i))
  jit_reg(RT_ENV_SET,    ->(e, i, v) js_env_set(e, i, v))
  jit_reg(RT_THROW,      ->(v) js_throw(v))
  jit_reg(RT_TO_INT32,   ->(v) js_to_int32(v) + ~0.0)
  jit_reg(RT_TO_NUMBER,  ->(v) js_to_number(v))
  jit_reg(RT_TO_STRING,  ->(v) js_to_string(v))
  jit_reg(RT_STR_CAT,    ->(a, b) js_str_cat(a, b))
  jit_reg(RT_FMOD_D,     ->(a, b) js_mod(a, b))
  jit_reg(RT_MATH_ROUND, ->(v) jit_math_round(v))
  jit_reg(RT_TA_INFO,    ->(o, out) jit_ta_info_helper(o, out))
  jit_reg(RT_GET_PIC_MISS, ->(o, k, pic) jit_get_pic_miss(o, k, pic))
  jit_reg(RT_ARR_NEW_CAP, ->(n) jit_new_arr_cap(n))
  jit_reg(RT_SLOPPY_THIS, ->(t) js_sloppy_this(t))
  jit_reg(RT_DELETE,     ->(o, k, st) js_delete(o, k, st))
  jit_reg(RT_GDECLARE,   ->(c, v, isf) js_gdeclare(c, v, isf))
  jit_reg(RT_OBJ_PROTO,  ->() js_realm().object_proto)
  jit_reg(RT_NEW_OBJ,    ->(sh) JS:Object.new(sh))
  jit_reg(RT_ARR_MARK,   ->(a) js_mark_array(a))
  jit_reg(RT_TONUMERIC,  ->(v) js_tonumeric(v))
  jit_reg(RT_INC,        ->(v, up) js_inc(v, up))
  jit_reg(RT_STR_CHARCODE, ->(s, idx) jit_str_charcode_fast(s, idx))
  jit_reg(RT_MAP_GET,      ->(m, k) js_map_get(m.internal, k))
  jit_reg(RT_MAP_SET,      ->(m, k, v) js_map_set_fast(m, k, v))
  jit_reg(RT_SET_ADD,      ->(s, k) js_set_add_fast(s, k))
  jit_reg(RT_SET_HAS,      ->(s, k) js_map_has(s.internal, k))
  jit_reg(RT_STR_CAT_INT,  ->(pre, iv) jit_str_cat_i32_fast(pre, iv))
  jit_reg(RT_STR_SPLIT_CH, ->(s, sep) jit_str_split_fast(s, sep))
  jit_reg(RT_ARR_JOIN,     ->(a, sep) js_arr_join(a, sep))
  jit_reg(RT_STR_INDEXOF,  ->(s, sub) jit_str_indexof_fast(s, sub))
  jit_reg(RT_STR_SLICE,    ->(s, a, b) jit_str_slice_fast(s, a, b))
  jit_reg(RT_SB_NEW,       ->(s) jit_sb_new(s))
  jit_reg(RT_SB_APP_VAL,   ->(sb, v) jit_sb_app_val(sb, v))
  jit_reg(RT_SB_APP_TPL1,  ->(sb, pre, v, suf) jit_sb_app_tpl1(sb, pre, v, suf))
  jit_reg(RT_SB_FINISH,    ->(sb) jit_sb_finish(sb))
  jit_reg(RT_STR_LEN,      ->(s) jit_str_len(s))
  jit_reg(RT_TPL1,         ->(pre, v, suf) jit_tpl1(pre, v, suf))
  jit_reg(RT_BA_SB_NEW,    ->(s) jit_ba_sb_new(s))
  jit_reg(RT_BA_SB_TPL_I32, ->(jb, pre, iv, suf) jit_ba_sb_tpl_i32(jb, pre, iv, suf))
  jit_reg(RT_BA_SB_FINISH, ->(jb) jit_ba_sb_finish(jb))
  jit_reg(RT_PROM_THEN,    ->(p, f, rj) js_promise_then_fast(p, f, rj))
  jit_reg(RT_PROM_RESOLVE, ->(v) js_promise_resolve_fast(v))
  jit_reg(RT_PROM_THEN_JIT, ->(p, f, sh) js_promise_then_jit(p, f, sh))
  jit_reg(RT_NEW_REGEX,    ->(rx) js_regexp_from_rx(rx))
  jit_reg(RT_RX_EXEC,      ->(re, s) js_regexp_builtin_exec(re, js_to_string(s)))
  jit_reg(RT_STR_REPLACE,  ->(s, pat, repl) js_str_replace_fast(s, pat, repl))
  jit_reg(RT_RX_EXEC_CAPS, ->(re, s, caps) js_rx_exec_caps_rt(re, s, caps))
  jit_reg(RT_GTYPEOF,      ->(c) js_gtypeof(c))
  jit_reg(RT_STR_CHARCODE_IC, ->(s, idx, ic) jit_str_charcode_ic(s, idx, ic))
  jit_reg(RT_STR_INDEXOF_IC,  ->(s, sub, ic) jit_str_indexof_ic(s, sub, ic))
  jit_reg(RT_ARR_NEW_EMPTY_CAP, ->(n) jit_new_arr_empty_cap(n))
  jit_reg(RT_NEW_3,           ->(f, ic, a0, a1, a2) js_new_t(f, ic, 0, 3, a0, a1, a2, nil, nil))
  jit_reg(RT_NEW_4,           ->(f, ic, a0, a1, a2, a3) js_new_t(f, ic, 0, 4, a0, a1, a2, a3, nil))
  jit_reg(RT_STR_INDEXOF2,    ->(s, sub, from) jit_str_indexof2_fast(s, sub, from))
  jit_reg(RT_FOR_IN_KEYS,     ->(o) js_for_in_keys(o))
  jit_reg(RT_HAS_PROP,        ->(o, k) js_object?(o) ? jhas_property?(o, k) : true)
  jit_reg(RT_MAP_DELETE,      ->(m, k) js_map_remove(m.internal, k))
  jit_reg(RT_WM_SET,          ->(wm, k, v) js_weak_set(wm, "WeakMap", k, v))
  jit_reg(RT_RX_TEST,         ->(re, s) jit_rx_test_fast(re, s))
  jit_reg(RT_OBJ_KEYS,        ->(o) js_object_keys(o, :keys))

  # Constants & class IDs (discovered dynamically at runtime — zero hardcoded ABI guesses!)
  JIT_RT_TBL[RT_K_EPOCH_PTR]    = jit_i64_ptr(JS_EPOCH)
  JIT_RT_TBL[RT_K_AB_EPOCH_PTR] = jit_i64_ptr(JS_AB_EPOCH)
  JIT_RT_TBL[RT_K_NULL_BITS]    = wvalue_bits(JS_NULL) ## i64
  JIT_RT_TBL[RT_K_HOLE_BITS]    = wvalue_bits(JS_HOLE) ## i64
  JIT_RT_TBL[RT_K_NAN_BITS]     = wvalue_bits(js_nan()) ## i64
  tmp_obj = JS:Object.new(nil)
  tmp_ta  = JS:TypedArray.new(nil, "Float64Array")
  tmp_fn  = JS:Function.new(nil, nil, nil)
  JIT_RT_TBL[RT_K_OBJ_CLSID]    = jit_obj_clsid(wvalue_bits(tmp_obj) ## i64)
  JIT_RT_TBL[RT_K_TA_CLSID]     = jit_obj_clsid(wvalue_bits(tmp_ta) ## i64)
  JIT_RT_TBL[RT_K_FN_CLSID]     = jit_obj_clsid(wvalue_bits(tmp_fn) ## i64)
  jit_i64_ptr(JIT_RT_TBL)

# ---- Native ARM64 Stable Bottom-Up Merge Sort for Non-NaN Biased-Double WValue Arrays ----
# Signature: i64 sort_f64(i64 slots_ptr, i64 tmp_ptr, i64 n, i64 dir)
#   dir > 0: ascending; dir < 0: descending.
#   100% stable, zero function calls, pure register ARM64 (`ldr + sub + fmov + fcmp`)!
#   Compiled ONCE via JS:A64 on first use (~0.01ms compile, ~1ms for 200x1667 sorts!).
JIT_SORT_FP = i64[2]   # [asc_fp, desc_fp]

-> jit_compile_sort_f64(asc)
  a = JS:A64.new(256)
  # Save callee-saved x19..x26 on stack (64 bytes)
  a.stp_pre(R_X19, R_X20, R_SP, -64)
  a.stp_x(R_X21, R_X22, R_SP, 16)
  a.stp_x(R_X23, R_X24, R_SP, 32)
  a.stp_x(R_X25, R_X26, R_SP, 48)
  # x19 = slots, x20 = tmp, x21 = n, x22 = W_DOUBLE_BIAS (2^48)
  a.mov_r(R_X19, R_X0)
  a.mov_r(R_X20, R_X1)
  a.mov_r(R_X21, R_X2)
  a.mov_imm64(R_X22, 281474976710656)
  # --- Pass 1: insertion sort each run of 24 in slots ---
  a.movz_x(R_X9, 0)         # lo = 0
  l_r1 = a.new_label
  l_r1_end = a.new_label
  a.bind(l_r1)
  a.cmp_r(R_X9, R_X21)
  a.b_cond(CC_GE, l_r1_end)
  a.add_i(R_X10, R_X9, 24)  # hi = min(lo + 24, n)
  a.cmp_r(R_X10, R_X21)
  a.csel_x(R_X10, R_X21, R_X10, CC_GT)
  a.add_i(R_X11, R_X9, 1)   # i = lo + 1
  l_ins_i = a.new_label
  l_ins_i_end = a.new_label
  a.bind(l_ins_i)
  a.cmp_r(R_X11, R_X10)
  a.b_cond(CC_GE, l_ins_i_end)
  a.ldr_x_idx(R_X12, R_X19, R_X11)    # kv = slots[i]
  a.sub_r(R_X14, R_X12, R_X22)
  a.fmov_d_x(R_D0, R_X14)             # kd = f64(kv)
  a.sub_i(R_X13, R_X11, 1)            # j = i - 1
  l_ins_j = a.new_label
  l_ins_j_end = a.new_label
  a.bind(l_ins_j)
  a.cmp_r(R_X13, R_X9)
  a.b_cond(CC_LT, l_ins_j_end)
  a.ldr_x_idx(R_X15, R_X19, R_X13)    # slots[j]
  a.sub_r(R_X14, R_X15, R_X22)
  a.fmov_d_x(R_D1, R_X14)             # dj = f64(slots[j])
  a.fcmp_d(R_D1, R_D0)                # asc: shift while dj > kd (GT); desc: shift while dj < kd (MI)
  a.b_cond(asc ? CC_LE : CC_PL, l_ins_j_end)
  a.add_i(R_X16, R_X13, 1)
  a.str_x_idx(R_X15, R_X19, R_X16)    # slots[j+1] = slots[j]
  a.sub_i(R_X13, R_X13, 1)
  a.b(l_ins_j)
  a.bind(l_ins_j_end)
  a.add_i(R_X16, R_X13, 1)
  a.str_x_idx(R_X12, R_X19, R_X16)    # slots[j+1] = kv
  a.add_i(R_X11, R_X11, 1)
  a.b(l_ins_i)
  a.bind(l_ins_i_end)
  a.add_i(R_X9, R_X9, 24)
  a.b(l_r1)
  a.bind(l_r1_end)

  # --- Pass 2: bottom-up ping-pong merge (width = 24, 48, 96, ...) ---
  # x23 = src, x24 = dst, x25 = width
  a.mov_r(R_X23, R_X19)
  a.mov_r(R_X24, R_X20)
  a.movz_x(R_X25, 24)
  l_w = a.new_label
  l_w_end = a.new_label
  a.bind(l_w)
  a.cmp_r(R_X25, R_X21)
  a.b_cond(CC_GE, l_w_end)
  a.lsl_xi(R_X26, R_X25, 1)   # step = width * 2
  a.movz_x(R_X9, 0)           # lo = 0
  l_lo = a.new_label
  l_lo_end = a.new_label
  a.bind(l_lo)
  a.cmp_r(R_X9, R_X21)
  a.b_cond(CC_GE, l_lo_end)
  a.add_r(R_X10, R_X9, R_X25) # mid = lo + width
  a.add_r(R_X11, R_X9, R_X26) # hi = min(lo + step, n)
  a.cmp_r(R_X11, R_X21)
  a.csel_x(R_X11, R_X21, R_X11, CC_GT)
  l_copy_all = a.new_label
  l_merge_done = a.new_label
  a.cmp_r(R_X10, R_X11)
  a.b_cond(CC_GE, l_copy_all)
  # Pre-check already ordered: src[mid-1] <= src[mid] (asc) / >= (desc)
  a.sub_i(R_X12, R_X10, 1)
  a.ldr_x_idx(R_X14, R_X23, R_X12)
  a.ldr_x_idx(R_X15, R_X23, R_X10)
  a.sub_r(R_X14, R_X14, R_X22)
  a.sub_r(R_X15, R_X15, R_X22)
  a.fmov_d_x(R_D0, R_X14)
  a.fmov_d_x(R_D1, R_X15)
  a.fcmp_d(R_D0, R_D1)
  a.b_cond(asc ? CC_LS : CC_GE, l_copy_all)
  # Merge [lo..mid) and [mid..hi) -> dst[lo..hi)
  # x12 = i, x13 = j, x14 = k
  a.mov_r(R_X12, R_X9)
  a.mov_r(R_X13, R_X10)
  a.mov_r(R_X14, R_X9)
  # Preload vi (x15, d0) and vj (x16, d1)
  a.ldr_x_idx(R_X15, R_X23, R_X12)
  a.sub_r(R_X17, R_X15, R_X22)
  a.fmov_d_x(R_D0, R_X17)
  a.ldr_x_idx(R_X16, R_X23, R_X13)
  a.sub_r(R_X17, R_X16, R_X22)
  a.fmov_d_x(R_D1, R_X17)
  l_mg = a.new_label
  l_take_j = a.new_label
  l_rem_i = a.new_label
  l_rem_j = a.new_label
  a.bind(l_mg)
  # Stable: take right ONLY if vj < vi (asc) or vj > vi (desc)
  a.fcmp_d(R_D1, R_D0)
  a.b_cond(asc ? CC_MI : CC_GT, l_take_j)
  # Take left (vi)
  a.str_x_idx(R_X15, R_X24, R_X14)
  a.add_i(R_X14, R_X14, 1)
  a.add_i(R_X12, R_X12, 1)
  a.cmp_r(R_X12, R_X10)
  a.b_cond(CC_GE, l_rem_j)
  a.ldr_x_idx(R_X15, R_X23, R_X12)
  a.sub_r(R_X17, R_X15, R_X22)
  a.fmov_d_x(R_D0, R_X17)
  a.b(l_mg)
  a.bind(l_take_j)
  a.str_x_idx(R_X16, R_X24, R_X14)
  a.add_i(R_X14, R_X14, 1)
  a.add_i(R_X13, R_X13, 1)
  a.cmp_r(R_X13, R_X11)
  a.b_cond(CC_GE, l_rem_i)
  a.ldr_x_idx(R_X16, R_X23, R_X13)
  a.sub_r(R_X17, R_X16, R_X22)
  a.fmov_d_x(R_D1, R_X17)
  a.b(l_mg)
  # Copy remaining left
  a.bind(l_rem_i)
  a.cmp_r(R_X12, R_X10)
  a.b_cond(CC_GE, l_merge_done)
  a.ldr_x_idx(R_X15, R_X23, R_X12)
  a.str_x_idx(R_X15, R_X24, R_X14)
  a.add_i(R_X12, R_X12, 1)
  a.add_i(R_X14, R_X14, 1)
  a.b(l_rem_i)
  # Copy remaining right
  a.bind(l_rem_j)
  a.cmp_r(R_X13, R_X11)
  a.b_cond(CC_GE, l_merge_done)
  a.ldr_x_idx(R_X16, R_X23, R_X13)
  a.str_x_idx(R_X16, R_X24, R_X14)
  a.add_i(R_X13, R_X13, 1)
  a.add_i(R_X14, R_X14, 1)
  a.b(l_rem_j)
  # Copy whole run [lo..hi)
  a.bind(l_copy_all)
  a.mov_r(R_X14, R_X9)
  l_ca_lp = a.new_label
  a.bind(l_ca_lp)
  a.cmp_r(R_X14, R_X11)
  a.b_cond(CC_GE, l_merge_done)
  a.ldr_x_idx(R_X15, R_X23, R_X14)
  a.str_x_idx(R_X15, R_X24, R_X14)
  a.add_i(R_X14, R_X14, 1)
  a.b(l_ca_lp)
  a.bind(l_merge_done)
  a.add_r(R_X9, R_X9, R_X26)
  a.b(l_lo)
  a.bind(l_lo_end)
  # Swap src <-> dst, width *= 2
  a.mov_r(R_X15, R_X23)
  a.mov_r(R_X23, R_X24)
  a.mov_r(R_X24, R_X15)
  a.mov_r(R_X25, R_X26)
  a.b(l_w)
  a.bind(l_w_end)

  # If src != slots, copy back to slots
  l_ret = a.new_label
  a.cmp_r(R_X23, R_X19)
  a.b_cond(CC_EQ, l_ret)
  a.movz_x(R_X14, 0)
  l_cb = a.new_label
  a.bind(l_cb)
  a.cmp_r(R_X14, R_X21)
  a.b_cond(CC_GE, l_ret)
  a.ldr_x_idx(R_X15, R_X23, R_X14)
  a.str_x_idx(R_X15, R_X19, R_X14)
  a.add_i(R_X14, R_X14, 1)
  a.b(l_cb)
  a.bind(l_ret)
  a.movz_x(R_X0, 0)
  a.ldp_x(R_X25, R_X26, R_SP, 48)
  a.ldp_x(R_X23, R_X24, R_SP, 32)
  a.ldp_x(R_X21, R_X22, R_SP, 16)
  a.ldp_post(R_X19, R_X20, R_SP, 64)
  a.ret
  a.finalize

-> jit_sort_f64_arm64(slots, tmp, n, dir)
  idx = dir > 0 ? 0 : 1
  fp = JIT_SORT_FP[idx]
  if fp == 0
    return false if !jit_mem_ready?()
    fp = jit_compile_sort_f64(dir > 0)
    return false if fp == 0
    JIT_SORT_FP[idx] = fp
  jit_raw_call3(fp, slots, tmp, n)
  true
