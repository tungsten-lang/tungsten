# runtime/b_json — High-speed JSON.parse and JSON.stringify (100% ECMA-262 / RFC 8259).
#
# Fast paths (all 100% spec-exact with full fallback for edge cases):
#   JSON.parse:
#     - Raw byte-pointer scanning via LLVM-inlined primitives (zero u8[] bounds checks)
#     - Zero-allocation immediate inline WString packing for clean strings <= 5 bytes
#     - Zero-substring exact integer & <=15-digit IEEE-754 decimal parsing
#     - Fused shape-transition key prediction ("key": + ws in one native call)
#     - Direct inline-slot JS:Object construction
#   JSON.stringify:
#     - Reusable flat ByteArray output buffer (zero StringBuffer/intermediate string allocs)
#     - Direct WString decoding (inline 0..5, slab 6..61, heap 62+) — zero w_string_bytes_view
#     - Cached raw key-pointer plans on immutable JS:Shape + monomorphic array-element cache
#     - Pure native primitive, primitive-array, and primitive-object serializers

in JS

# ---- Tiny LLVM raw memory & NaN-box primitives (inlined at -O3) ----

fn jb_ld_u8(p) (i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %b = load i8, ptr %q, align 1
    %r = zext i8 %b to i64
    ret i64 %r
  IR

fn jb_st_u8(p, v) (i64 i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %b = trunc i64 %v to i8
    store i8 %b, ptr %q, align 1
    ret i64 0
  IR

fn jb_ld_u32(p) (i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %w = load i32, ptr %q, align 1
    %r = zext i32 %w to i64
    ret i64 %r
  IR

fn jb_st_u32(p, v) (i64 i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %w = trunc i64 %v to i32
    store i32 %w, ptr %q, align 1
    ret i64 0
  IR

fn jb_ld_i64(p) (i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %v = load i64, ptr %q, align 8
    ret i64 %v
  IR

fn jb_ld_i64_u(p) (i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    %v = load i64, ptr %q, align 1
    ret i64 %v
  IR

fn jb_st_i64_u(p, v) (i64 i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    store i64 %v, ptr %q, align 1
    ret i64 0
  IR

# Pure LLVM 2-way set-associative 6..15-byte string intern cache helpers (32,768 sets x 2 ways = 65,536 slots).
# Key layout per slot: [k_lo, k_hi] where:
#   - len 6..7:  k_lo = bytes 0..len-1 (zero-padded), k_hi = len << 56
#   - len 8:     k_lo = bytes 0..7,                   k_hi = 8 << 56
#   - len 9..15: k_lo = bytes 0..7,                   k_hi = (bytes 8..len-1 in low bytes) | (len << 56)
# k_hi is ALWAYS non-zero (top byte == len in 6..15), so empty slots (k_hi == 0) never collide!
fn js_s7_set_of(src_ptr, st, len) (i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %ge8 = icmp uge i64 %len, 8
    br i1 %ge8, label %b8, label %b67
  b67:
    %w32 = load i32, ptr %q, align 1
    %k0 = zext i32 %w32 to i64
    %p4 = getelementptr i8, ptr %q, i64 4
    %w16 = load i16, ptr %p4, align 1
    %k4 = zext i16 %w16 to i64
    %k4s = shl i64 %k4, 32
    %k6 = or i64 %k0, %k4s
    %is7 = icmp eq i64 %len, 7
    br i1 %is7, label %b7, label %b67_done
  b7:
    %p6 = getelementptr i8, ptr %q, i64 6
    %b6 = load i8, ptr %p6, align 1
    %k6z = zext i8 %b6 to i64
    %k6s = shl i64 %k6z, 48
    %k7 = or i64 %k6, %k6s
    br label %b67_done
  b67_done:
    %lo67 = phi i64 [ %k6, %b67 ], [ %k7, %b7 ]
    %hi67 = shl i64 %len, 56
    br label %hash
  b8:
    %lo8 = load i64, ptr %q, align 1
    %is8 = icmp eq i64 %len, 8
    br i1 %is8, label %b8_eq, label %b9p
  b8_eq:
    %hi8 = shl i64 8, 56
    br label %hash
  b9p:
    %off = sub i64 %len, 8
    %q2 = getelementptr i8, ptr %q, i64 %off
    %raw_hi = load i64, ptr %q2, align 1
    %rem = sub i64 16, %len
    %sh = shl i64 %rem, 3
    %shi = lshr i64 %raw_hi, %sh
    %ls = shl i64 %len, 56
    %hi9p = or i64 %shi, %ls
    br label %hash
  hash:
    %k_lo = phi i64 [ %lo67, %b67_done ], [ %lo8, %b8_eq ], [ %lo8, %b9p ]
    %k_hi = phi i64 [ %hi67, %b67_done ], [ %hi8, %b8_eq ], [ %hi9p, %b9p ]
    %hm1 = mul i64 %k_hi, -4658895280553007687
    %hx0 = xor i64 %k_lo, %hm1
    %hx1 = lshr i64 %hx0, 32
    %hx = xor i64 %hx0, %hx1
    %hm2 = mul i64 %hx, -7046029254386353131
    %hs = lshr i64 %hm2, 49
    %set = and i64 %hs, 32767
    ret i64 %set
  IR

fn js_s7_commit_slot(src_ptr, st, len, keys_p, slot) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %ge8 = icmp uge i64 %len, 8
    br i1 %ge8, label %b8, label %b67
  b67:
    %w32 = load i32, ptr %q, align 1
    %k0 = zext i32 %w32 to i64
    %p4 = getelementptr i8, ptr %q, i64 4
    %w16 = load i16, ptr %p4, align 1
    %k4 = zext i16 %w16 to i64
    %k4s = shl i64 %k4, 32
    %k6 = or i64 %k0, %k4s
    %is7 = icmp eq i64 %len, 7
    br i1 %is7, label %b7, label %b67_done
  b7:
    %p6 = getelementptr i8, ptr %q, i64 6
    %b6 = load i8, ptr %p6, align 1
    %k6z = zext i8 %b6 to i64
    %k6s = shl i64 %k6z, 48
    %k7 = or i64 %k6, %k6s
    br label %b67_done
  b67_done:
    %lo67 = phi i64 [ %k6, %b67 ], [ %k7, %b7 ]
    %hi67 = shl i64 %len, 56
    br label %store
  b8:
    %lo8 = load i64, ptr %q, align 1
    %is8 = icmp eq i64 %len, 8
    br i1 %is8, label %b8_eq, label %b9p
  b8_eq:
    %hi8 = shl i64 8, 56
    br label %store
  b9p:
    %off = sub i64 %len, 8
    %q2 = getelementptr i8, ptr %q, i64 %off
    %raw_hi = load i64, ptr %q2, align 1
    %rem = sub i64 16, %len
    %sh = shl i64 %rem, 3
    %shi = lshr i64 %raw_hi, %sh
    %ls = shl i64 %len, 56
    %hi9p = or i64 %shi, %ls
    br label %store
  store:
    %k_lo = phi i64 [ %lo67, %b67_done ], [ %lo8, %b8_eq ], [ %lo8, %b9p ]
    %k_hi = phi i64 [ %hi67, %b67_done ], [ %hi8, %b8_eq ], [ %hi9p, %b9p ]
    %koff = shl i64 %slot, 1
    %kp0 = inttoptr i64 %keys_p to ptr
    %plo = getelementptr i64, ptr %kp0, i64 %koff
    %phi = getelementptr i64, ptr %plo, i64 1
    store i64 %k_lo, ptr %plo, align 8
    store i64 %k_hi, ptr %phi, align 8
    ret i64 0
  IR

# Pure LLVM lock-free 6..15-byte string cache 2-way probe (ZERO BigInt boxing!).
fn js_s7_probe_bits(src_ptr, st, len, keys_p, vals_p) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %ge8 = icmp uge i64 %len, 8
    br i1 %ge8, label %b8, label %b67
  b67:
    %w32 = load i32, ptr %q, align 1
    %k0 = zext i32 %w32 to i64
    %p4 = getelementptr i8, ptr %q, i64 4
    %w16 = load i16, ptr %p4, align 1
    %k4 = zext i16 %w16 to i64
    %k4s = shl i64 %k4, 32
    %k6 = or i64 %k0, %k4s
    %is7 = icmp eq i64 %len, 7
    br i1 %is7, label %b7, label %b67_done
  b7:
    %p6 = getelementptr i8, ptr %q, i64 6
    %b6 = load i8, ptr %p6, align 1
    %k6z = zext i8 %b6 to i64
    %k6s = shl i64 %k6z, 48
    %k7 = or i64 %k6, %k6s
    br label %b67_done
  b67_done:
    %lo67 = phi i64 [ %k6, %b67 ], [ %k7, %b7 ]
    %hi67 = shl i64 %len, 56
    br label %kd
  b8:
    %lo8 = load i64, ptr %q, align 1
    %is8 = icmp eq i64 %len, 8
    br i1 %is8, label %b8_eq, label %b9p
  b8_eq:
    %hi8 = shl i64 8, 56
    br label %kd
  b9p:
    %off = sub i64 %len, 8
    %q2 = getelementptr i8, ptr %q, i64 %off
    %raw_hi = load i64, ptr %q2, align 1
    %rem = sub i64 16, %len
    %sh = shl i64 %rem, 3
    %shi = lshr i64 %raw_hi, %sh
    %ls = shl i64 %len, 56
    %hi9p = or i64 %shi, %ls
    br label %kd
  kd:
    %k_lo = phi i64 [ %lo67, %b67_done ], [ %lo8, %b8_eq ], [ %lo8, %b9p ]
    %k_hi = phi i64 [ %hi67, %b67_done ], [ %hi8, %b8_eq ], [ %hi9p, %b9p ]
    %hm1 = mul i64 %k_hi, -4658895280553007687
    %hx0 = xor i64 %k_lo, %hm1
    %hx1 = lshr i64 %hx0, 32
    %hx = xor i64 %hx0, %hx1
    %hm2 = mul i64 %hx, -7046029254386353131
    %hs = lshr i64 %hm2, 49
    %set = and i64 %hs, 32767
    %slot0 = shl i64 %set, 1
    %koff0 = shl i64 %slot0, 1
    %kp0 = inttoptr i64 %keys_p to ptr
    %p0_lo = getelementptr i64, ptr %kp0, i64 %koff0
    %e0_lo = load i64, ptr %p0_lo, align 8
    %eq0_lo = icmp eq i64 %e0_lo, %k_lo
    br i1 %eq0_lo, label %chk0_hi, label %way1
  chk0_hi:
    %p0_hi = getelementptr i64, ptr %p0_lo, i64 1
    %e0_hi = load i64, ptr %p0_hi, align 8
    %eq0_hi = icmp eq i64 %e0_hi, %k_hi
    br i1 %eq0_hi, label %hit0, label %way1
  hit0:
    %vp0 = inttoptr i64 %vals_p to ptr
    %vp_0 = getelementptr i64, ptr %vp0, i64 %slot0
    %v0 = load i64, ptr %vp_0, align 8
    ret i64 %v0
  way1:
    %p1_lo = getelementptr i64, ptr %p0_lo, i64 2
    %e1_lo = load i64, ptr %p1_lo, align 8
    %eq1_lo = icmp eq i64 %e1_lo, %k_lo
    br i1 %eq1_lo, label %chk1_hi, label %miss
  chk1_hi:
    %p1_hi = getelementptr i64, ptr %p0_lo, i64 3
    %e1_hi = load i64, ptr %p1_hi, align 8
    %eq1_hi = icmp eq i64 %e1_hi, %k_hi
    br i1 %eq1_hi, label %hit1, label %miss
  hit1:
    %slot1 = or i64 %slot0, 1
    %vp1 = inttoptr i64 %vals_p to ptr
    %vp_1 = getelementptr i64, ptr %vp1, i64 %slot1
    %v1 = load i64, ptr %vp_1, align 8
    ret i64 %v1
  miss:
    ret i64 0
  IR

# General 16..31-byte ASCII string intern cache (4096 sets x 2 ways = 8192 slots, 4 qwords per key).
# Key layout: [w0 (0..7), w1 (8..15), w2 (16..23), w3 (24..30 | len<<56)]. w3 != 0 for all valid entries!
JS_S31_KEYS = i64[32768]
JS_S31_VALS = Array.new(8192, nil)
JS_S31_FILL = i64[1]
JS_S64_HASH = i64[4096]
JS_S64_VALS = Array.new(4096, nil)
JS_S64_FILL = i64[1]
JS_S31_PTRS = i64[6]   # [s7_kp, s7_vp, s31_kp, s31_vp, s64_hp, s64_vp]
JS_S31_PTRS_P = i64[1]

fn js_i64_at_ll(arr_b, idx) (i64 i64) i64
  ll <<~IR
    %ap_i = and i64 %arr_b, 140737488355312
    %ap = inttoptr i64 %ap_i to ptr
    %slp = getelementptr i8, ptr %ap, i64 16
    %sl = load ptr, ptr %slp, align 8
    %ep = getelementptr i64, ptr %sl, i64 %idx
    %v = load i64, ptr %ep, align 8
    ret i64 %v
  IR

-> js_s_cache_init_p(dummy) (i64) i64
  p = js_i64_at_ll(wvalue_bits(JS_S31_PTRS_P) ## i64, 0)
  return p if p != 0
  JS_S31_PTRS[0] = jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64)
  JS_S31_PTRS[1] = jit_arr_slots_ptr(wvalue_bits(JS_S7_VALS) ## i64)
  JS_S31_PTRS[2] = jit_arr_slots_ptr(wvalue_bits(JS_S31_KEYS) ## i64)
  JS_S31_PTRS[3] = jit_arr_slots_ptr(wvalue_bits(JS_S31_VALS) ## i64)
  JS_S31_PTRS[4] = jit_arr_slots_ptr(wvalue_bits(JS_S64_HASH) ## i64)
  JS_S31_PTRS[5] = jit_arr_slots_ptr(wvalue_bits(JS_S64_VALS) ## i64)
  p = jit_arr_slots_ptr(wvalue_bits(JS_S31_PTRS) ## i64)
  JS_S31_PTRS_P[0] = p
  p

-> js_s7_probe_fast(sp, ai, sl) (i64 i64 i64) i64
  p = js_s_cache_init_p(0)
  js_s7_probe_bits(sp, ai, sl, jb_ld_i64(p), jb_ld_i64(p + 8))

-> js_s31_probe_fast(sp, ai, sl) (i64 i64 i64) i64
  p = js_s_cache_init_p(0)
  js_s31_probe_bits(sp, ai, sl, jb_ld_i64(p + 16), jb_ld_i64(p + 24))

# Pure-LLVM 64-bit word hash for 16..64-byte ASCII slices (returns non-zero hash with bit 0 set).
fn js_s64_hash_raw(src_ptr, st, len) (i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %lim = sub i64 %len, 8
    br label %lp
  lp:
    %i = phi i64 [ 0, %0 ], [ %ni, %bd ]
    %h = phi i64 [ %len, %0 ], [ %nh, %bd ]
    %more = icmp slt i64 %i, %lim
    br i1 %more, label %bd, label %tail
  bd:
    %ep = getelementptr i8, ptr %q, i64 %i
    %w = load i64, ptr %ep, align 1
    %xh = xor i64 %h, %w
    %nh = mul i64 %xh, -7046029254386353131
    %ni = add i64 %i, 8
    br label %lp
  tail:
    %tp = getelementptr i8, ptr %q, i64 %lim
    %wt = load i64, ptr %tp, align 1
    %h1 = xor i64 %h, %wt
    %h2 = mul i64 %h1, -4658895280553007687
    %h3 = lshr i64 %h2, 32
    %h4 = xor i64 %h2, %h3
    %h5 = mul i64 %h4, -7046029254386353131
    %res = or i64 %h5, 1
    ret i64 %res
  IR

# Pure-LLVM byte equality between raw ASCII buffer [src_p, len>=16) and flat ASCII WString `sv_bits` (mode 6 or 7).
fn js_s64_eq_str(src_p, len, sv_bits, slab_base) (i64 i64 i64 i64) i64
  ll <<~IR
    %tg = and i64 %sv_bits, u0xFFFF00000000000F
    %is7 = icmp eq i64 %tg, u0xFFF900000000000E
    br i1 %is7, label %m7, label %chk6
  m7:
    %wsi = and i64 %sv_bits, u0x0000FFFFFFFFFFF0
    %ws = inttoptr i64 %wsi to ptr
    %lfp = getelementptr i8, ptr %ws, i64 8
    %lf = load i32, ptr %lfp, align 4
    %asc7 = icmp slt i32 %lf, 0
    br i1 %asc7, label %m7_len, label %no
  m7_len:
    %l32 = and i32 %lf, 2147483647
    %l7 = zext i32 %l32 to i64
    %eq7 = icmp eq i64 %l7, %len
    br i1 %eq7, label %m7_ptr, label %no
  m7_ptr:
    %vp7 = getelementptr i8, ptr %ws, i64 16
    br label %cmp
  chk6:
    %is6 = icmp eq i64 %tg, u0xFFF900000000000C
    %hsb = icmp ne i64 %slab_base, 0
    %ok6 = and i1 %is6, %hsb
    br i1 %ok6, label %m6, label %no
  m6:
    %s1 = lshr i64 %sv_bits, 4
    %sidx = and i64 %s1, 16777215
    %soff = shl i64 %sidx, 5
    %saddr = add i64 %slab_base, %soff
    %sp = inttoptr i64 %saddr to ptr
    %sf = load i8, ptr %sp, align 1
    %sfa = and i8 %sf, 9
    %sfok = icmp eq i8 %sfa, 9
    br i1 %sfok, label %m6_len, label %no
  m6_len:
    %slp = getelementptr i8, ptr %sp, i64 1
    %sl8 = load i8, ptr %slp, align 1
    %l6 = zext i8 %sl8 to i64
    %eq6 = icmp eq i64 %l6, %len
    br i1 %eq6, label %m6_ptr, label %no
  m6_ptr:
    %vp6 = getelementptr i8, ptr %sp, i64 2
    br label %cmp
  cmp:
    %vp = phi ptr [ %vp7, %m7_ptr ], [ %vp6, %m6_ptr ]
    %qp = inttoptr i64 %src_p to ptr
    %lim = sub i64 %len, 8
    br label %clp
  clp:
    %i = phi i64 [ 0, %cmp ], [ %ni, %cbd ]
    %more = icmp slt i64 %i, %lim
    br i1 %more, label %cbd, label %ctail
  cbd:
    %ap = getelementptr i8, ptr %qp, i64 %i
    %bp = getelementptr i8, ptr %vp, i64 %i
    %aw = load i64, ptr %ap, align 1
    %bw = load i64, ptr %bp, align 1
    %weq = icmp eq i64 %aw, %bw
    %ni = add i64 %i, 8
    br i1 %weq, label %clp, label %no
  ctail:
    %atp = getelementptr i8, ptr %qp, i64 %lim
    %btp = getelementptr i8, ptr %vp, i64 %lim
    %atw = load i64, ptr %atp, align 1
    %btw = load i64, ptr %btp, align 1
    %teq = icmp eq i64 %atw, %btw
    %r = zext i1 %teq to i64
    ret i64 %r
  no:
    ret i64 0
  IR

-> js_s64_probe_fast(sp, ai, sl, slb) (i64 i64 i64 i64) i64
  p = js_s_cache_init_p(0)
  hp = jb_ld_i64(p + 32)
  vp = jb_ld_i64(p + 40)
  h = js_s64_hash_raw(sp, ai, sl)
  slot0 = ((h >> 48) & 2047) << 1
  if jb_ld_i64(hp + slot0 * 8) == h
    v0 = jb_ld_i64(vp + slot0 * 8)
    return v0 if v0 != 0 && js_s64_eq_str(sp + ai, sl, v0, slb) != 0
  slot1 = slot0 | 1
  if jb_ld_i64(hp + slot1 * 8) == h
    v1 = jb_ld_i64(vp + slot1 * 8)
    return v1 if v1 != 0 && js_s64_eq_str(sp + ai, sl, v1, slb) != 0
  0

-> js_s64_cache_set(sp, ai, sl, res)
  h = js_s64_hash_raw(sp, ai, sl)
  slot0 = ((h >> 48) & 2047) << 1
  slot = JS_S64_HASH[slot0] == 0 ? slot0 : (JS_S64_HASH[slot0 | 1] == 0 ? (slot0 | 1) : -1)
  if slot >= 0
    JS_S64_VALS[slot] = res
    JS_S64_HASH[slot] = h
    JS_S64_FILL[0] = JS_S64_FILL[0] + 1
  nil

fn js_s31_probe_bits(src_ptr, st, len, keys_p, vals_p) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %w0 = load i64, ptr %q, align 1
    %q1 = getelementptr i8, ptr %q, i64 8
    %w1 = load i64, ptr %q1, align 1
    %is16 = icmp eq i64 %len, 16
    br i1 %is16, label %b16, label %gt16
  b16:
    %h16 = shl i64 16, 56
    br label %hash
  gt16:
    %lt24 = icmp ult i64 %len, 24
    br i1 %lt24, label %b17_23, label %ge24
  b17_23:
    %o2 = sub i64 %len, 8
    %qp2 = getelementptr i8, ptr %q, i64 %o2
    %r2 = load i64, ptr %qp2, align 1
    %rem2 = sub i64 24, %len
    %sh2 = shl i64 %rem2, 3
    %w2_a = lshr i64 %r2, %sh2
    %w3_a = shl i64 %len, 56
    br label %hash
  ge24:
    %q2 = getelementptr i8, ptr %q, i64 16
    %w2_b = load i64, ptr %q2, align 1
    %is24 = icmp eq i64 %len, 24
    br i1 %is24, label %b24, label %b25_31
  b24:
    %w3_b = shl i64 24, 56
    br label %hash
  b25_31:
    %o3 = sub i64 %len, 8
    %qp3 = getelementptr i8, ptr %q, i64 %o3
    %r3 = load i64, ptr %qp3, align 1
    %rem3 = sub i64 32, %len
    %sh3 = shl i64 %rem3, 3
    %s3 = lshr i64 %r3, %sh3
    %ls3 = shl i64 %len, 56
    %w3_c = or i64 %s3, %ls3
    br label %hash
  hash:
    %w2 = phi i64 [ 0, %b16 ], [ %w2_a, %b17_23 ], [ %w2_b, %b24 ], [ %w2_b, %b25_31 ]
    %w3 = phi i64 [ %h16, %b16 ], [ %w3_a, %b17_23 ], [ %w3_b, %b24 ], [ %w3_c, %b25_31 ]
    %m1 = mul i64 %w1, -4658895280553007687
    %m2 = mul i64 %w2, -7046029254386353131
    %m3 = mul i64 %w3, -4658895280553007687
    %x0 = xor i64 %w0, %m1
    %x1 = xor i64 %x0, %m2
    %x2 = xor i64 %x1, %m3
    %x3 = lshr i64 %x2, 32
    %x4 = xor i64 %x2, %x3
    %hm = mul i64 %x4, -7046029254386353131
    %hs = lshr i64 %hm, 52
    %set = and i64 %hs, 4095
    %slot0 = shl i64 %set, 1
    %koff0 = shl i64 %slot0, 2
    %kp0 = inttoptr i64 %keys_p to ptr
    %p0_0 = getelementptr i64, ptr %kp0, i64 %koff0
    %e0_0 = load i64, ptr %p0_0, align 8
    %eq0_0 = icmp eq i64 %e0_0, %w0
    br i1 %eq0_0, label %c0_1, label %way1
  c0_1:
    %p0_1 = getelementptr i64, ptr %p0_0, i64 1
    %e0_1 = load i64, ptr %p0_1, align 8
    %eq0_1 = icmp eq i64 %e0_1, %w1
    br i1 %eq0_1, label %c0_2, label %way1
  c0_2:
    %p0_2 = getelementptr i64, ptr %p0_0, i64 2
    %e0_2 = load i64, ptr %p0_2, align 8
    %eq0_2 = icmp eq i64 %e0_2, %w2
    br i1 %eq0_2, label %c0_3, label %way1
  c0_3:
    %p0_3 = getelementptr i64, ptr %p0_0, i64 3
    %e0_3 = load i64, ptr %p0_3, align 8
    %eq0_3 = icmp eq i64 %e0_3, %w3
    br i1 %eq0_3, label %hit0, label %way1
  hit0:
    %vp0 = inttoptr i64 %vals_p to ptr
    %vp_0 = getelementptr i64, ptr %vp0, i64 %slot0
    %v0 = load i64, ptr %vp_0, align 8
    ret i64 %v0
  way1:
    %p1_0 = getelementptr i64, ptr %p0_0, i64 4
    %e1_0 = load i64, ptr %p1_0, align 8
    %eq1_0 = icmp eq i64 %e1_0, %w0
    br i1 %eq1_0, label %c1_1, label %miss
  c1_1:
    %p1_1 = getelementptr i64, ptr %p0_0, i64 5
    %e1_1 = load i64, ptr %p1_1, align 8
    %eq1_1 = icmp eq i64 %e1_1, %w1
    br i1 %eq1_1, label %c1_2, label %miss
  c1_2:
    %p1_2 = getelementptr i64, ptr %p0_0, i64 6
    %e1_2 = load i64, ptr %p1_2, align 8
    %eq1_2 = icmp eq i64 %e1_2, %w2
    br i1 %eq1_2, label %c1_3, label %miss
  c1_3:
    %p1_3 = getelementptr i64, ptr %p0_0, i64 7
    %e1_3 = load i64, ptr %p1_3, align 8
    %eq1_3 = icmp eq i64 %e1_3, %w3
    br i1 %eq1_3, label %hit1, label %miss
  hit1:
    %slot1 = or i64 %slot0, 1
    %vp1 = inttoptr i64 %vals_p to ptr
    %vp_1 = getelementptr i64, ptr %vp1, i64 %slot1
    %v1 = load i64, ptr %vp_1, align 8
    ret i64 %v1
  miss:
    ret i64 0
  IR

fn js_s31_commit_ll(src_ptr, st, len, keys_p) (i64 i64 i64 i64) i64
  ll <<~IR
    %p0 = add i64 %src_ptr, %st
    %q = inttoptr i64 %p0 to ptr
    %w0 = load i64, ptr %q, align 1
    %q1 = getelementptr i8, ptr %q, i64 8
    %w1 = load i64, ptr %q1, align 1
    %is16 = icmp eq i64 %len, 16
    br i1 %is16, label %b16, label %gt16
  b16:
    %h16 = shl i64 16, 56
    br label %hash
  gt16:
    %lt24 = icmp ult i64 %len, 24
    br i1 %lt24, label %b17_23, label %ge24
  b17_23:
    %o2 = sub i64 %len, 8
    %qp2 = getelementptr i8, ptr %q, i64 %o2
    %r2 = load i64, ptr %qp2, align 1
    %rem2 = sub i64 24, %len
    %sh2 = shl i64 %rem2, 3
    %w2_a = lshr i64 %r2, %sh2
    %w3_a = shl i64 %len, 56
    br label %hash
  ge24:
    %q2 = getelementptr i8, ptr %q, i64 16
    %w2_b = load i64, ptr %q2, align 1
    %is24 = icmp eq i64 %len, 24
    br i1 %is24, label %b24, label %b25_31
  b24:
    %w3_b = shl i64 24, 56
    br label %hash
  b25_31:
    %o3 = sub i64 %len, 8
    %qp3 = getelementptr i8, ptr %q, i64 %o3
    %r3 = load i64, ptr %qp3, align 1
    %rem3 = sub i64 32, %len
    %sh3 = shl i64 %rem3, 3
    %s3 = lshr i64 %r3, %sh3
    %ls3 = shl i64 %len, 56
    %w3_c = or i64 %s3, %ls3
    br label %hash
  hash:
    %w2 = phi i64 [ 0, %b16 ], [ %w2_a, %b17_23 ], [ %w2_b, %b24 ], [ %w2_b, %b25_31 ]
    %w3 = phi i64 [ %h16, %b16 ], [ %w3_a, %b17_23 ], [ %w3_b, %b24 ], [ %w3_c, %b25_31 ]
    %m1 = mul i64 %w1, -4658895280553007687
    %m2 = mul i64 %w2, -7046029254386353131
    %m3 = mul i64 %w3, -4658895280553007687
    %x0 = xor i64 %w0, %m1
    %x1 = xor i64 %x0, %m2
    %x2 = xor i64 %x1, %m3
    %x3 = lshr i64 %x2, 32
    %x4 = xor i64 %x2, %x3
    %hm = mul i64 %x4, -7046029254386353131
    %hs = lshr i64 %hm, 52
    %set = and i64 %hs, 4095
    %slot0 = shl i64 %set, 1
    %koff0 = shl i64 %slot0, 2
    %kp0 = inttoptr i64 %keys_p to ptr
    %p0_3 = getelementptr i64, ptr %kp0, i64 %koff0
    %q0_3 = getelementptr i64, ptr %p0_3, i64 3
    %e0_3 = load i64, ptr %q0_3, align 8
    %em0 = icmp eq i64 %e0_3, 0
    br i1 %em0, label %w_slot0, label %chk1
  chk1:
    %q1_3 = getelementptr i64, ptr %p0_3, i64 7
    %e1_3 = load i64, ptr %q1_3, align 8
    %em1 = icmp eq i64 %e1_3, 0
    br i1 %em1, label %w_slot1, label %full
  w_slot0:
    store i64 %w0, ptr %p0_3, align 8
    %s0_1 = getelementptr i64, ptr %p0_3, i64 1
    %s0_2 = getelementptr i64, ptr %p0_3, i64 2
    store i64 %w1, ptr %s0_1, align 8
    store i64 %w2, ptr %s0_2, align 8
    store i64 %w3, ptr %q0_3, align 8
    ret i64 %slot0
  w_slot1:
    %p1_0 = getelementptr i64, ptr %p0_3, i64 4
    %s1_1 = getelementptr i64, ptr %p0_3, i64 5
    %s1_2 = getelementptr i64, ptr %p0_3, i64 6
    store i64 %w0, ptr %p1_0, align 8
    store i64 %w1, ptr %s1_1, align 8
    store i64 %w2, ptr %s1_2, align 8
    store i64 %w3, ptr %q1_3, align 8
    %slot1 = or i64 %slot0, 1
    ret i64 %slot1
  full:
    ret i64 -1
  IR

-> js_s31_cache_set(src_ptr, st, len, str_val)
  return nil if JS_S31_FILL[0] >= 6144
  p = js_s_cache_init_p(0)
  sl = js_s31_commit_ll(src_ptr, st, len, jb_ld_i64(p + 16))
  if sl >= 0
    JS_S31_VALS[sl] = str_val
    JS_S31_FILL[0] += 1
  nil

fn jb_is_slab_str(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF00000000000F
    %c = icmp eq i64 %t, u0xFFF900000000000C
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn jb_is_flat_str(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF000000000001
    %c = icmp eq i64 %t, u0xFFF9000000000000
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn jb_mask_ptr48(v) (i64) i64
  ll <<~IR
    %p = and i64 %v, u0x0000FFFFFFFFFFF0
    ret i64 %p
  IR

fn jb_is_dense_arr(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF000000000000
    %c = icmp eq i64 %t, u0xFFF4000000000000
    br i1 %c, label %yes, label %no
  yes:
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 2
    %k = load i8, ptr %a, align 2
    %m = and i8 %k, 15
    %ok = icmp eq i8 %m, 1
    %r = zext i1 %ok to i64
    ret i64 %r
  no:
    ret i64 0
  IR

fn jb_arr_start(v) (i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 4
    %s32 = load i32, ptr %a, align 4
    %s = sext i32 %s32 to i64
    ret i64 %s
  IR

# Classify a WValue number into:
#   (iv << 2) | 1    if exact integer with |d| <= 2^53 - 1
#   (iv10 << 2) | 3  if exact 1-decimal double with |d| < 900719925474099.0
#   0                otherwise (not a number, NaN, Inf, >2^53, >=2 decimals)
fn jb_classify_num(v_bits) (i64) i64
  ll <<~IR
    %x = sub i64 %v_bits, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    br i1 %isn, label %num, label %other
  num:
    %d = bitcast i64 %x to double
    %xa = and i64 %x, 9223372036854775807
    %ab = bitcast i64 %xa to double
    %in_int = fcmp ole double %ab, 9007199254740991.0
    br i1 %in_int, label %chk_int, label %other
  chk_int:
    %iv = fptosi double %d to i64
    %df = sitofp i64 %iv to double
    %eq_i = fcmp oeq double %df, %d
    br i1 %eq_i, label %ret_int, label %chk_d1
  ret_int:
    %sh_i = shl i64 %iv, 2
    %ri = or i64 %sh_i, 1
    ret i64 %ri
  chk_d1:
    %in_d1 = fcmp olt double %ab, 900719925474099.0
    br i1 %in_d1, label %try_d1, label %other
  try_d1:
    %d10 = fmul double %d, 10.0
    %iv10 = fptosi double %d10 to i64
    %df10 = sitofp i64 %iv10 to double
    %eq10 = fcmp oeq double %df10, %d10
    br i1 %eq10, label %chk_rt, label %other
  chk_rt:
    %rt = fdiv double %df10, 10.0
    %eqrt = fcmp oeq double %rt, %d
    br i1 %eqrt, label %ret_d1, label %other
  ret_d1:
    %sh_d = shl i64 %iv10, 2
    %rd = or i64 %sh_d, 3
    ret i64 %rd
  other:
    ret i64 0
  IR

# Pack 0..5 raw UTF-8 bytes at src_ptr[st .. st+len) into an immediate inline WString WValue!
fn jp_pack_inline(src_ptr, st, len) (i64 i64 i64) i64
  ll <<~IR
    %l1 = shl i64 %len, 1
    %base = or i64 u0xFFF9000000000000, %l1
    %p0 = add i64 %src_ptr, %st
    %ptr = inttoptr i64 %p0 to ptr
    br label %loop
  loop:
    %i = phi i64 [ 0, %0 ], [ %ni, %body ]
    %acc = phi i64 [ %base, %0 ], [ %nacc, %body ]
    %done = icmp sge i64 %i, %len
    br i1 %done, label %ret, label %body
  body:
    %ep = getelementptr i8, ptr %ptr, i64 %i
    %b8 = load i8, ptr %ep, align 1
    %b = zext i8 %b8 to i64
    %sh0 = shl i64 %i, 3
    %sh = add i64 %sh0, 4
    %bs = shl i64 %b, %sh
    %nacc = or i64 %acc, %bs
    %ni = add i64 %i, 1
    br label %loop
  ret:
    ret i64 %acc
  IR

# Exact IEEE-754 f64(val) / 10^frac boxed as a Tungsten WValue double.
# Exact whenever |val| < 2^53 and 0 <= frac <= 15 (both val and 10^frac are exact in IEEE-754 double!).
fn jp_box_dec(val, frac) (i64 i64) i64
  ll <<~IR
    %d = sitofp i64 %val to double
    %is0 = icmp eq i64 %frac, 0
    br i1 %is0, label %done, label %div
  div:
    %is1 = icmp eq i64 %frac, 1
    br i1 %is1, label %d1, label %loop
  d1:
    %q1 = fdiv double %d, 10.0
    br label %done
  loop:
    %k = phi i64 [ 0, %div ], [ %nk, %loop ]
    %p = phi double [ 1.0, %div ], [ %np, %loop ]
    %np = fmul double %p, 10.0
    %nk = add i64 %k, 1
    %more = icmp slt i64 %nk, %frac
    br i1 %more, label %loop, label %divn
  divn:
    %qn = fdiv double %d, %np
    br label %done
  done:
    %res = phi double [ %d, %0 ], [ %q1, %d1 ], [ %qn, %divn ]
    %bits = bitcast double %res to i64
    %box = add i64 %bits, 281474976710656
    ret i64 %box
  IR

# ---- Native typed byte helpers (compiled to LLVM -O3) ----

-> jb_memcpy_raw(dst_ptr, pos, src_ptr, len) (i64 i64 i64 i64) i64
  d = dst_ptr + pos
  j = 0 ## i64
  while j + 8 <= len
    jb_st_i64_u(d + j, jb_ld_i64_u(src_ptr + j))
    j += 8
  while j < len
    jb_st_u8(d + j, jb_ld_u8(src_ptr + j))
    j += 1
  pos + len

-> jb_put_i64_ptr(dst_ptr, pos, v) (i64 i64 i64) i64
  if v >= 0 && v < 100
    if v < 10
      jb_st_u8(dst_ptr + pos, 48 + v)
      return pos + 1
    q = v / 10
    jb_st_u8(dst_ptr + pos, 48 + q)
    jb_st_u8(dst_ptr + pos + 1, 48 + (v - q * 10))
    return pos + 2
  if v < 0
    jb_st_u8(dst_ptr + pos, 45)
    pos += 1
    v = 0 - v
  st = pos
  while v > 0
    q = v / 10
    d = v - q * 10
    jb_st_u8(dst_ptr + pos, 48 + d)
    pos += 1
    v = q
  l = st
  r = pos - 1
  while l < r
    tmp = jb_ld_u8(dst_ptr + l)
    jb_st_u8(dst_ptr + l, jb_ld_u8(dst_ptr + r))
    jb_st_u8(dst_ptr + r, tmp)
    l += 1
    r -= 1
  pos

-> jb_put_dec1_ptr(dst_ptr, pos, v10) (i64 i64 i64) i64
  if v10 < 0
    jb_st_u8(dst_ptr + pos, 45)
    pos += 1
    v10 = 0 - v10
  ip = v10 / 10
  fp = v10 - ip * 10
  pos = jb_put_i64_ptr(dst_ptr, pos, ip)
  jb_st_u8(dst_ptr + pos, 46)
  jb_st_u8(dst_ptr + pos + 1, 48 + fp)
  pos + 2

# Write a clean quoted flat WString directly from its raw bytes into dst_ptr[pos..].
# Returns new pos (>= 0), -1 if capacity needed, or -3 if not a clean inline/slab/heap string.
-> jb_write_str_raw(dst_ptr, pos, cap, v_bits, slab_base) (i64 i64 i64 i64 i64) i64
  mode = (v_bits >> 1) & 7
  if mode <= 5
    return -1 if pos + mode + 2 > cap
    d = dst_ptr + pos
    jb_st_u8(d, 34)
    j = 0 ## i64
    while j < mode
      b = (v_bits >> (4 + j * 8)) & 255
      return -3 if b < 32 || b == 34 || b == 92 || b == 237
      jb_st_u8(d + 1 + j, b)
      j += 1
    jb_st_u8(d + 1 + mode, 34)
    return pos + mode + 2
  src = 0 ## i64
  len = 0 ## i64
  if mode == 6
    return -3 if slab_base == 0
    idx = (v_bits >> 4) & 16777215
    slot = slab_base + idx * 32
    flags = jb_ld_u8(slot)
    return -3 if (flags & 1) == 0
    len = jb_ld_u8(slot + 1)
    src = slot + 2
  else
    ws = jb_mask_ptr48(v_bits)
    len = jb_ld_u32(ws + 8) & 2147483647
    src = ws + 16
  return -1 if pos + len + 2 > cap
  d = dst_ptr + pos
  jb_st_u8(d, 34)
  j = 0 ## i64
  while j < len
    b = jb_ld_u8(src + j)
    return -3 if b < 32 || b == 34 || b == 92 || b == 237
    jb_st_u8(d + 1 + j, b)
    j += 1
  jb_st_u8(d + 1 + len, 34)
  pos + len + 2

# Write any fast JS primitive directly to dst_ptr[pos..].
# Returns >= 0 (new pos), -1 (need grow), -2 (undefined), -3 (non-fast / complex).
-> jb_write_prim_val(dst_ptr, pos, cap, v_bits, null_bits, slab_base) (i64 i64 i64 i64 i64 i64) i64
  nk = jb_classify_num(v_bits)
  if nk != 0
    return -1 if pos + 32 > cap
    if (nk & 3) == 1
      return jb_put_i64_ptr(dst_ptr, pos, nk >> 2)
    return jb_put_dec1_ptr(dst_ptr, pos, nk >> 2)
  if jb_is_flat_str(v_bits) != 0
    return jb_write_str_raw(dst_ptr, pos, cap, v_bits, slab_base)
  if v_bits == 2
    return -1 if pos + 4 > cap
    jb_st_u32(dst_ptr + pos, 1702195828)  # "true"
    return pos + 4
  if v_bits == 1
    return -1 if pos + 5 > cap
    jb_st_u32(dst_ptr + pos, 1936482662)  # "fals"
    jb_st_u8(dst_ptr + pos + 4, 101)      # 'e'
    return pos + 5
  if v_bits == null_bits
    return -1 if pos + 4 > cap
    jb_st_u32(dst_ptr + pos, 1819047278)  # "null"
    return pos + 4
  return -2 if v_bits == 0
  -3

# Write a dense JS_AF_ARRAY containing only fast primitives/undefined directly to dst_ptr[pos..].
# Guaranteed cycle-free (no nested objects/arrays). Returns >=0, -1 (grow), or -3 (complex -> slow path).
-> jb_write_prim_arr(dst_ptr, pos, cap, arr_bits, null_bits, slab_base) (i64 i64 i64 i64 i64 i64) i64
  return -1 if pos + 2 > cap
  sz = jsr_asize(arr_bits)
  p = pos
  jb_st_u8(dst_ptr + p, 91)  # '['
  p += 1
  if sz > 0
    st = jb_arr_start(arr_bits)
    sl = jit_arr_slots_ptr(arr_bits) + st * 8
    j = 0 ## i64
    while j < sz
      if j > 0
        return -1 if p + 1 > cap
        jb_st_u8(dst_ptr + p, 44)  # ','
        p += 1
      el = jb_ld_i64(sl + j * 8)
      r = jb_write_prim_val(dst_ptr, p, cap, el, null_bits, slab_base)
      if r >= 0
        p = r
      elsif r == -2
        return -1 if p + 4 > cap
        jb_st_u32(dst_ptr + p, 1819047278)  # "null"
        p += 4
      else
        return r
      j += 1
  return -1 if p + 1 > cap
  jb_st_u8(dst_ptr + p, 93)  # ']'
  p + 1

# Write a plain JS:Object (with cached shape plan) whose fields are primitives or primitive-only arrays.
# Guaranteed cycle-free; returns >=0, -1 (grow), or -3 (nested object / symbol / fn / escape -> fallback).
-> jb_write_obj_fast(dst_ptr, pos, cap, ob, n, kptrs_p, klens_p, ivars_p, null_bits, slab_base) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  return -1 if pos + 2 > cap
  p = pos
  jb_st_u8(dst_ptr + p, 123)  # '{'
  p += 1
  first = 1 ## i64
  i = 0 ## i64
  while i < n
    iv = jb_ld_i64(ivars_p + i * 8)
    vb = jsr_ivar(ob, iv)
    if vb != 0
      kp = jb_ld_i64(kptrs_p + i * 8)
      kl = jb_ld_i64(klens_p + i * 8)
      if first != 0
        kp += 1
        kl -= 1
      return -1 if p + kl + 2 > cap
      p2 = jb_memcpy_raw(dst_ptr, p, kp, kl)
      r = jb_write_prim_val(dst_ptr, p2, cap, vb, null_bits, slab_base)
      if r >= 0
        p = r
        first = 0
      elsif r == -1
        return -1
      elsif jb_is_dense_arr(vb) != 0
        r2 = jb_write_prim_arr(dst_ptr, p2, cap, vb, null_bits, slab_base)
        return r2 if r2 < 0
        p = r2
        first = 0
      else
        return -3
    i += 1
  return -1 if p + 1 > cap
  jb_st_u8(dst_ptr + p, 125)  # '}'
  p + 1

JS_SLAB_BASE_FAST = i64[1]

-> jp_init_slab_fast(dummy) (i64) i64
  js_json_init_lits()
  b = JS_JSON_SLAB_BASE[0]
  JS_SLAB_BASE_FAST[0] = b
  b

# Return raw byte pointer of a mode-7 heap string or mode-6 interned slab string, or 0 for inline/rope.
-> jp_flat_str_ptr(sb) (i64) i64
  return 0 if jb_is_flat_str(sb) == 0
  mode = (sb >> 1) & 7
  return jb_mask_ptr48(sb) + 16 if mode == 7
  return 0 if mode != 6
  base = JS_SLAB_BASE_FAST[0]
  if base == 0
    base = jp_init_slab_fast(0)
    return 0 if base == 0
  slot = base + ((sb >> 4) & 16777215) * 32
  flags = jb_ld_u8(slot)
  return slot + 2 if (flags & 1) != 0
  return jb_ld_i64_u(slot + 10) if (flags & 4) != 0
  0

-> jb_probe_slab_base(pb, ptr, expect_len) (i64 i64 i64) i64
  return 0 if jb_is_flat_str(pb) == 0
  return 0 if ((pb >> 1) & 7) != 6
  idx = (pb >> 4) & 16777215
  base = ptr - idx * 32 - 2
  jb_verify_slab(base, idx, expect_len) != 0 ? base : 0

# Typed monomorphic dense-array serializer loop: stays 100% in unboxed i64 registers!
# Writes elements start_i..n-1 directly into dp[pos..cap).
# Updates out_st[0] = new_pos, out_st[1] = next_i.
# Returns 0 when finished (i == n), -1 when buffer grow needed, or -3 when element i needs untyped dispatch.
-> jb_write_arr_run(dp, pos, cap, arr_bits, start_i, n, sh_bits, ln, lkp, lkl, liv, nb, sb, out_st) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  st = jb_arr_start(arr_bits)
  sl = jit_arr_slots_ptr(arr_bits) + st * 8
  i = start_i
  while i < n
    p_elem = pos
    if i > 0
      if p_elem >= cap
        out_st[0] = pos
        out_st[1] = i
        return -1
      jb_st_u8(dp + p_elem, 44)
      p_elem += 1
    eb = jb_ld_i64(sl + i * 8)
    if sh_bits != 0 && jsr_shape(eb) == sh_bits
      ro = jb_write_obj_fast(dp, p_elem, cap, eb, ln, lkp, lkl, liv, nb, sb)
      if ro >= 0
        pos = ro
        i += 1
        next
      out_st[0] = pos
      out_st[1] = i
      return ro
    r1 = jb_write_prim_val(dp, p_elem, cap, eb, nb, sb)
    if r1 >= 0
      pos = r1
      i += 1
      next
    if r1 == -2
      if p_elem + 4 > cap
        out_st[0] = pos
        out_st[1] = i
        return -1
      jb_st_u32(dp + p_elem, 1819047278)
      pos = p_elem + 4
      i += 1
      next
    out_st[0] = pos
    out_st[1] = i
    return r1
  out_st[0] = pos
  out_st[1] = i
  0

# Typed helper to avoid boxing a 64-bit WValue ivar into an untyped local in write_plain_obj_slow.
-> jb_ivar_is_undef(ob, iv) (i64 i64) i64
  jsr_ivar(ob, iv) == 0 ? 1 : 0

-> jb_try_write_ivar_prim(dp, pos, cap, ob, iv, kp, kl, nb, sb) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  vb = jsr_ivar(ob, iv)
  return -2 if vb == 0
  r = jb_write_prim_val(dp, pos + kl, cap, vb, nb, sb)
  if r >= 0
    jb_memcpy_raw(dp, pos, kp, kl)
  r

-> jb_verify_slab(base, idx, expect_len) (i64 i64 i64) i64
  slot = base + idx * 32
  flags = jb_ld_u8(slot)
  return 0 if (flags & 1) == 0
  len = jb_ld_u8(slot + 1)
  len == expect_len ? 1 : 0

-> jb_is_clean_str(sv, n) (u8[] i64) i64
  i = 0 ## i64
  while i < n
    b = sv[i] ## i64
    return 0 if b < 32 || b == 34 || b == 92 || b == 237
    i += 1
  1

# ---- Fast raw-pointer JSON.parse scanners ----

-> jp_skip_ws_ptr(src_ptr, i, n) (i64 i64 i64) i64
  while i < n
    b = jb_ld_u8(src_ptr + i)
    break if b != 32 && b != 9 && b != 10 && b != 13
    i += 1
  i

-> jp_scan_str_end_ptr(src_ptr, i, n) (i64 i64 i64) i64
  while i < n
    b = jb_ld_u8(src_ptr + i)
    return i if b == 34
    return -1 if b == 92 || b < 32
    i += 1
  -1

# Match optional ws + `"key":` + optional ws at src_ptr[pos..]. Returns new pos on match, -1 on miss.
-> jp_match_pred_key(src_ptr, pos, n, kptr, klen) (i64 i64 i64 i64 i64) i64
  if pos < n && jb_ld_u8(src_ptr + pos) <= 32
    pos = jp_skip_ws_ptr(src_ptr, pos, n)
  return -1 if pos + klen > n
  s = src_ptr + pos
  j = 0 ## i64
  while j + 8 <= klen
    return -1 if jb_ld_i64_u(s + j) != jb_ld_i64_u(kptr + j)
    j += 8
  if j + 4 <= klen
    return -1 if jb_ld_u32(s + j) != jb_ld_u32(kptr + j)
    j += 4
  while j < klen
    return -1 if jb_ld_u8(s + j) != jb_ld_u8(kptr + j)
    j += 1
  pos += klen
  if pos < n && jb_ld_u8(src_ptr + pos) <= 32
    pos = jp_skip_ws_ptr(src_ptr, pos, n)
  pos

# Pure LLVM JSON value scanner: writes 64-bit WValue DIRECTLY into dst_p[dst_idx] (ZERO BigInt boxing!).
# Also checks lock-free JS_S7 cache for 6..7 byte clean strings directly in LLVM!
# Return tags:
#   1: immediate / S7-cached WValue written to dst_p[dst_idx]; next pos in out_p[0]
#   2: clean string >= 6 bytes (S7 miss): byte start in out_p[1], len in out_p[2], next pos in out_p[0]
#   3: '[' array start, next pos in out_p[0]
#   4: '{' object start, next pos in out_p[0]
#   0: slow fallback (escaped string, exponent/long number, syntax error)
fn jp_scan_prim_ll(src_ptr, pos, n, out_p, dst_p, dst_idx, null_bits, s7k_p, s7v_p) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %sp = inttoptr i64 %src_ptr to ptr
    %op = inttoptr i64 %out_p to ptr
    br label %ws_chk
  ws_chk:
    %p = phi i64 [ %pos, %0 ], [ %p_ws, %ws_step ]
    %eof = icmp sge i64 %p, %n
    br i1 %eof, label %ret0, label %ws_ld
  ws_ld:
    %bp0 = getelementptr i8, ptr %sp, i64 %p
    %b08 = load i8, ptr %bp0, align 1
    %b = zext i8 %b08 to i64
    %le32 = icmp ule i64 %b, 32
    br i1 %le32, label %ws_test, label %dispatch
  ws_test:
    %is_sp = icmp eq i64 %b, 32
    %is_tb = icmp eq i64 %b, 9
    %is_nl = icmp eq i64 %b, 10
    %is_cr = icmp eq i64 %b, 13
    %w1 = or i1 %is_sp, %is_tb
    %w2 = or i1 %is_nl, %is_cr
    %is_ws = or i1 %w1, %w2
    br i1 %is_ws, label %ws_step, label %ret0
  ws_step:
    %p_ws = add i64 %p, 1
    br label %ws_chk
  dispatch:
    ; String '"' (34)
    %is_q = icmp eq i64 %b, 34
    br i1 %is_q, label %str_start, label %chk_num
  str_start:
    %st = add i64 %p, 1
    br label %str_loop
  str_loop:
    %sj = phi i64 [ %st, %str_start ], [ %nsj, %str_next ]
    %seof = icmp sge i64 %sj, %n
    br i1 %seof, label %ret0, label %str_ld
  str_ld:
    %sjp = getelementptr i8, ptr %sp, i64 %sj
    %sc8 = load i8, ptr %sjp, align 1
    %sc = zext i8 %sc8 to i64
    %is_eq = icmp eq i64 %sc, 34
    br i1 %is_eq, label %str_end, label %str_chk
  str_chk:
    %is_bs = icmp eq i64 %sc, 92
    %is_ctl = icmp ult i64 %sc, 32
    %sbad = or i1 %is_bs, %is_ctl
    br i1 %sbad, label %ret0, label %str_next
  str_next:
    %nsj = add i64 %sj, 1
    br label %str_loop
  str_end:
    %slen = sub i64 %sj, %st
    %send = add i64 %sj, 1
    store i64 %send, ptr %op, align 8
    %is_inl = icmp sle i64 %slen, 5
    br i1 %is_inl, label %pack_inl, label %chk_s7
  pack_inl:
    %l1 = shl i64 %slen, 1
    %ibase = or i64 u0xFFF9000000000000, %l1
    %sptr0 = getelementptr i8, ptr %sp, i64 %st
    br label %ploop
  ploop:
    %pi = phi i64 [ 0, %pack_inl ], [ %npi, %pbody ]
    %acc = phi i64 [ %ibase, %pack_inl ], [ %nacc, %pbody ]
    %pdone = icmp sge i64 %pi, %slen
    br i1 %pdone, label %store_ret1, label %pbody
  pbody:
    %pep = getelementptr i8, ptr %sptr0, i64 %pi
    %pb8 = load i8, ptr %pep, align 1
    %pb = zext i8 %pb8 to i64
    %psh0 = shl i64 %pi, 3
    %psh = add i64 %psh0, 4
    %pbs = shl i64 %pb, %psh
    %nacc = or i64 %acc, %pbs
    %npi = add i64 %pi, 1
    br label %ploop
  chk_s7:
    %ge6 = icmp uge i64 %slen, 6
    %le15 = icmp ule i64 %slen, 15
    %in615 = and i1 %ge6, %le15
    %has_s7 = icmp ne i64 %s7k_p, 0
    %do_s7 = and i1 %in615, %has_s7
    br i1 %do_s7, label %try_s7, label %ret_str2
  try_s7:
    %q7 = getelementptr i8, ptr %sp, i64 %st
    %s7_ge8 = icmp uge i64 %slen, 8
    br i1 %s7_ge8, label %s7_b8, label %s7_b67
  s7_b67:
    %w32 = load i32, ptr %q7, align 1
    %k0 = zext i32 %w32 to i64
    %q74 = getelementptr i8, ptr %q7, i64 4
    %w16 = load i16, ptr %q74, align 1
    %k4 = zext i16 %w16 to i64
    %k4s = shl i64 %k4, 32
    %k6 = or i64 %k0, %k4s
    %is7 = icmp eq i64 %slen, 7
    br i1 %is7, label %s7_b7, label %s7_67d
  s7_b7:
    %q76 = getelementptr i8, ptr %q7, i64 6
    %b68 = load i8, ptr %q76, align 1
    %b6 = zext i8 %b68 to i64
    %b6s = shl i64 %b6, 48
    %k7 = or i64 %k6, %b6s
    br label %s7_67d
  s7_67d:
    %lo67 = phi i64 [ %k6, %s7_b67 ], [ %k7, %s7_b7 ]
    %hi67 = shl i64 %slen, 56
    br label %s7_kd
  s7_b8:
    %lo8 = load i64, ptr %q7, align 1
    %is8 = icmp eq i64 %slen, 8
    br i1 %is8, label %s7_8e, label %s7_9p
  s7_8e:
    %hi8 = shl i64 8, 56
    br label %s7_kd
  s7_9p:
    %off9 = sub i64 %slen, 8
    %q72 = getelementptr i8, ptr %q7, i64 %off9
    %rhi9 = load i64, ptr %q72, align 1
    %rem9 = sub i64 16, %slen
    %sh9 = shl i64 %rem9, 3
    %shi9 = lshr i64 %rhi9, %sh9
    %kls9 = shl i64 %slen, 56
    %hi9p = or i64 %shi9, %kls9
    br label %s7_kd
  s7_kd:
    %k_lo = phi i64 [ %lo67, %s7_67d ], [ %lo8, %s7_8e ], [ %lo8, %s7_9p ]
    %k_hi = phi i64 [ %hi67, %s7_67d ], [ %hi8, %s7_8e ], [ %hi9p, %s7_9p ]
    %hm1 = mul i64 %k_hi, -4658895280553007687
    %hx0 = xor i64 %k_lo, %hm1
    %hx1 = lshr i64 %hx0, 32
    %hx = xor i64 %hx0, %hx1
    %km = mul i64 %hx, -7046029254386353131
    %ks = lshr i64 %km, 49
    %kset = and i64 %ks, 32767
    %kslot0 = shl i64 %kset, 1
    %koff0 = shl i64 %kslot0, 1
    %kp0 = inttoptr i64 %s7k_p to ptr
    %kp0_lo = getelementptr i64, ptr %kp0, i64 %koff0
    %ek0_lo = load i64, ptr %kp0_lo, align 8
    %keq0_lo = icmp eq i64 %ek0_lo, %k_lo
    br i1 %keq0_lo, label %s7_chk0_hi, label %s7_way1
  s7_chk0_hi:
    %kp0_hi = getelementptr i64, ptr %kp0_lo, i64 1
    %ek0_hi = load i64, ptr %kp0_hi, align 8
    %keq0_hi = icmp eq i64 %ek0_hi, %k_hi
    br i1 %keq0_hi, label %s7_hit0, label %s7_way1
  s7_hit0:
    %vp0 = inttoptr i64 %s7v_p to ptr
    %vp_0 = getelementptr i64, ptr %vp0, i64 %kslot0
    %sv0 = load i64, ptr %vp_0, align 8
    br label %store_ret1
  s7_way1:
    %kp1_lo = getelementptr i64, ptr %kp0_lo, i64 2
    %ek1_lo = load i64, ptr %kp1_lo, align 8
    %keq1_lo = icmp eq i64 %ek1_lo, %k_lo
    br i1 %keq1_lo, label %s7_chk1_hi, label %ret_str2
  s7_chk1_hi:
    %kp1_hi = getelementptr i64, ptr %kp0_lo, i64 3
    %ek1_hi = load i64, ptr %kp1_hi, align 8
    %keq1_hi = icmp eq i64 %ek1_hi, %k_hi
    br i1 %keq1_hi, label %s7_hit1, label %ret_str2
  s7_hit1:
    %kslot1 = or i64 %kslot0, 1
    %vp1 = inttoptr i64 %s7v_p to ptr
    %vp_1 = getelementptr i64, ptr %vp1, i64 %kslot1
    %sv1 = load i64, ptr %vp_1, align 8
    br label %store_ret1
  ret_str2:
    %op1 = getelementptr i64, ptr %op, i64 1
    store i64 %st, ptr %op1, align 8
    %op2 = getelementptr i64, ptr %op, i64 2
    store i64 %slen, ptr %op2, align 8
    ret i64 2

  chk_num:
    %is_neg = icmp eq i64 %b, 45
    %ge48 = icmp uge i64 %b, 48
    %le57 = icmp ule i64 %b, 57
    %is_dig = and i1 %ge48, %le57
    %is_num = or i1 %is_neg, %is_dig
    br i1 %is_num, label %num_start, label %chk_arr
  num_start:
    %nj0 = select i1 %is_neg, i64 1, i64 0
    %nj1 = add i64 %p, %nj0
    %neof0 = icmp sge i64 %nj1, %n
    br i1 %neof0, label %ret0, label %num_b0
  num_b0:
    %nbp0 = getelementptr i8, ptr %sp, i64 %nj1
    %nb08 = load i8, ptr %nbp0, align 1
    %nb0 = zext i8 %nb08 to i64
    %nb0_ge = icmp uge i64 %nb0, 48
    %nb0_le = icmp ule i64 %nb0, 57
    %nb0_ok = and i1 %nb0_ge, %nb0_le
    br i1 %nb0_ok, label %num_zchk, label %ret0
  num_zchk:
    %is_z0 = icmp eq i64 %nb0, 48
    br i1 %is_z0, label %num_zero, label %num_iloop
  num_zero:
    %nz1 = add i64 %nj1, 1
    %nz_in = icmp slt i64 %nz1, %n
    br i1 %nz_in, label %num_z2, label %num_after_int
  num_z2:
    %nzp = getelementptr i8, ptr %sp, i64 %nz1
    %nz8 = load i8, ptr %nzp, align 1
    %nzb = zext i8 %nz8 to i64
    %nz_ge = icmp uge i64 %nzb, 48
    %nz_le = icmp ule i64 %nzb, 57
    %nz_bad = and i1 %nz_ge, %nz_le
    br i1 %nz_bad, label %ret0, label %num_after_int
  num_iloop:
    %ij = phi i64 [ %nj1, %num_zchk ], [ %nij, %num_iacc ]
    %iacc = phi i64 [ 0, %num_zchk ], [ %niacc, %num_iacc ]
    %idigs = phi i64 [ 0, %num_zchk ], [ %nidigs, %num_iacc ]
    %ieof = icmp sge i64 %ij, %n
    br i1 %ieof, label %num_after_int, label %num_ild
  num_ild:
    %ip = getelementptr i8, ptr %sp, i64 %ij
    %ib8 = load i8, ptr %ip, align 1
    %ib = zext i8 %ib8 to i64
    %ig = icmp uge i64 %ib, 48
    %il = icmp ule i64 %ib, 57
    %idok = and i1 %ig, %il
    br i1 %idok, label %num_istep, label %num_after_int
  num_istep:
    %nidigs = add i64 %idigs, 1
    %itoom = icmp sgt i64 %nidigs, 15
    br i1 %itoom, label %ret0, label %num_iacc
  num_iacc:
    %i10 = mul i64 %iacc, 10
    %idv = sub i64 %ib, 48
    %niacc = add i64 %i10, %idv
    %nij = add i64 %ij, 1
    br label %num_iloop
  num_after_int:
    %aj = phi i64 [ %nz1, %num_zero ], [ %nz1, %num_z2 ], [ %ij, %num_iloop ], [ %ij, %num_ild ]
    %aacc = phi i64 [ 0, %num_zero ], [ 0, %num_z2 ], [ %iacc, %num_iloop ], [ %iacc, %num_ild ]
    %adigs = phi i64 [ 0, %num_zero ], [ 0, %num_z2 ], [ %idigs, %num_iloop ], [ %idigs, %num_ild ]
    %a_in = icmp slt i64 %aj, %n
    br i1 %a_in, label %chk_dot, label %num_fin
  chk_dot:
    %dp = getelementptr i8, ptr %sp, i64 %aj
    %db8 = load i8, ptr %dp, align 1
    %is_dot = icmp eq i8 %db8, 46
    br i1 %is_dot, label %frac_start, label %chk_exp
  frac_start:
    %fj0 = add i64 %aj, 1
    %feof0 = icmp sge i64 %fj0, %n
    br i1 %feof0, label %ret0, label %frac_loop
  frac_loop:
    %fj = phi i64 [ %fj0, %frac_start ], [ %nfj, %frac_acc ]
    %facc = phi i64 [ %aacc, %frac_start ], [ %nfacc, %frac_acc ]
    %fdigs = phi i64 [ %adigs, %frac_start ], [ %nfdigs, %frac_acc ]
    %ffd = phi i64 [ 0, %frac_start ], [ %nffd, %frac_acc ]
    %feof = icmp sge i64 %fj, %n
    br i1 %feof, label %frac_end, label %frac_ld
  frac_ld:
    %fp = getelementptr i8, ptr %sp, i64 %fj
    %fb8 = load i8, ptr %fp, align 1
    %fb = zext i8 %fb8 to i64
    %fg = icmp uge i64 %fb, 48
    %fl = icmp ule i64 %fb, 57
    %fdok = and i1 %fg, %fl
    br i1 %fdok, label %frac_step, label %frac_end
  frac_step:
    %nffd = add i64 %ffd, 1
    %nfdigs = add i64 %fdigs, 1
    %ftoom = icmp sgt i64 %nfdigs, 15
    br i1 %ftoom, label %ret0, label %frac_acc
  frac_acc:
    %f10 = mul i64 %facc, 10
    %fdv = sub i64 %fb, 48
    %nfacc = add i64 %f10, %fdv
    %nfj = add i64 %fj, 1
    br label %frac_loop
  frac_end:
    %fzero = icmp eq i64 %ffd, 0
    br i1 %fzero, label %ret0, label %chk_exp_f
  chk_exp_f:
    %f_in = icmp slt i64 %fj, %n
    br i1 %f_in, label %chk_exp2, label %num_fin
  chk_exp:
    %db_e = or i8 %db8, 32
    %is_e = icmp eq i8 %db_e, 101
    br i1 %is_e, label %ret0, label %num_fin
  chk_exp2:
    %ep2 = getelementptr i8, ptr %sp, i64 %fj
    %eb2 = load i8, ptr %ep2, align 1
    %eb2e = or i8 %eb2, 32
    %is_e2 = icmp eq i8 %eb2e, 101
    br i1 %is_e2, label %ret0, label %num_fin
  num_fin:
    %endj = phi i64 [ %aj, %num_after_int ], [ %aj, %chk_exp ], [ %fj, %chk_exp_f ], [ %fj, %chk_exp2 ]
    %macc = phi i64 [ %aacc, %num_after_int ], [ %aacc, %chk_exp ], [ %facc, %chk_exp_f ], [ %facc, %chk_exp2 ]
    %mfrac = phi i64 [ 0, %num_after_int ], [ 0, %chk_exp ], [ %ffd, %chk_exp_f ], [ %ffd, %chk_exp2 ]
    %acc_z = icmp eq i64 %macc, 0
    %neg_z = and i1 %is_neg, %acc_z
    br i1 %neg_z, label %ret0, label %box_num
  box_num:
    %nacc0 = sub i64 0, %macc
    %sval = select i1 %is_neg, i64 %nacc0, i64 %macc
    %dval = sitofp i64 %sval to double
    %fr0 = icmp eq i64 %mfrac, 0
    br i1 %fr0, label %box_done, label %box_div
  box_div:
    %fr1 = icmp eq i64 %mfrac, 1
    br i1 %fr1, label %box_d1, label %box_div2
  box_d1:
    %qd1 = fdiv double %dval, 10.0
    br label %box_done
  box_div2:
    %fr2 = icmp eq i64 %mfrac, 2
    br i1 %fr2, label %box_d2, label %box_dlp
  box_d2:
    %qd2 = fdiv double %dval, 100.0
    br label %box_done
  box_dlp:
    %dk = phi i64 [ 0, %box_div2 ], [ %ndk, %box_dlp ]
    %dpw = phi double [ 1.0, %box_div2 ], [ %ndpw, %box_dlp ]
    %ndpw = fmul double %dpw, 10.0
    %ndk = add i64 %dk, 1
    %dmore = icmp slt i64 %ndk, %mfrac
    br i1 %dmore, label %box_dlp, label %box_dn
  box_dn:
    %qdn = fdiv double %dval, %ndpw
    br label %box_done
  box_done:
    %fres = phi double [ %dval, %box_num ], [ %qd1, %box_d1 ], [ %qd2, %box_d2 ], [ %qdn, %box_dn ]
    %fbits = bitcast double %fres to i64
    %nbox = add i64 %fbits, 281474976710656
    store i64 %endj, ptr %op, align 8
    br label %store_ret1

  chk_arr:
    %is_lb = icmp eq i64 %b, 91
    br i1 %is_lb, label %ret_arr, label %chk_obj
  ret_arr:
    %pa1 = add i64 %p, 1
    store i64 %pa1, ptr %op, align 8
    ret i64 3
  chk_obj:
    %is_lc = icmp eq i64 %b, 123
    br i1 %is_lc, label %ret_obj, label %chk_true
  ret_obj:
    %po1 = add i64 %p, 1
    store i64 %po1, ptr %op, align 8
    ret i64 4
  chk_true:
    %is_t = icmp eq i64 %b, 116
    br i1 %is_t, label %try_true, label %chk_false
  try_true:
    %p4 = add i64 %p, 4
    %t_in = icmp sle i64 %p4, %n
    br i1 %t_in, label %t_ld, label %ret0
  t_ld:
    %tp = getelementptr i8, ptr %sp, i64 %p
    %tw = load i32, ptr %tp, align 1
    %tok = icmp eq i32 %tw, 1702195828
    br i1 %tok, label %t_ok, label %ret0
  t_ok:
    store i64 %p4, ptr %op, align 8
    br label %store_ret1
  chk_false:
    %is_f = icmp eq i64 %b, 102
    br i1 %is_f, label %try_false, label %chk_null
  try_false:
    %p5 = add i64 %p, 5
    %fl_in = icmp sle i64 %p5, %n
    br i1 %fl_in, label %f_ld, label %ret0
  f_ld:
    %fp0 = getelementptr i8, ptr %sp, i64 %p
    %fw = load i32, ptr %fp0, align 1
    %f4p = getelementptr i8, ptr %fp0, i64 4
    %f4 = load i8, ptr %f4p, align 1
    %fok1 = icmp eq i32 %fw, 1936482662
    %fok2 = icmp eq i8 %f4, 101
    %fok = and i1 %fok1, %fok2
    br i1 %fok, label %f_ok, label %ret0
  f_ok:
    store i64 %p5, ptr %op, align 8
    br label %store_ret1
  chk_null:
    %is_n = icmp eq i64 %b, 110
    br i1 %is_n, label %try_null, label %ret0
  try_null:
    %pn4 = add i64 %p, 4
    %n_in = icmp sle i64 %pn4, %n
    br i1 %n_in, label %n_ld, label %ret0
  n_ld:
    %np0 = getelementptr i8, ptr %sp, i64 %p
    %nw = load i32, ptr %np0, align 1
    %nok = icmp eq i32 %nw, 1819047278
    br i1 %nok, label %n_ok, label %ret0
  n_ok:
    store i64 %pn4, ptr %op, align 8
    br label %store_ret1

  store_ret1:
    %val = phi i64 [ %acc, %ploop ], [ %sv0, %s7_hit0 ], [ %sv1, %s7_hit1 ], [ %nbox, %box_done ], [ 2, %t_ok ], [ 1, %f_ok ], [ %null_bits, %n_ok ]
    %dp0 = inttoptr i64 %dst_p to ptr
    %dwp = getelementptr i64, ptr %dp0, i64 %dst_idx
    store i64 %val, ptr %dwp, align 8
    ret i64 1
  ret0:
    ret i64 0
  IR

-> jp_scan_prim(src_ptr, pos, n, out, null_bits) (i64 i64 i64 i64[] i64) i64
  op = jit_arr_slots_ptr(wvalue_bits(out) ## i64)
  jp_scan_prim_ll(src_ptr, pos, n, op, op, 1, null_bits, 0, 0)

# Pure LLVM object inline-slot writer: copies tag==1 WValues directly from fvals_p[0..k-1]
# into obj->ivars[ibase + f] with ZERO WBigint boxing! Returns bitmask of fields with tag != 1.
fn jp_fill_obj_ll(obj_bits, fvals_p, ftags_p, k, ibase) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %op = sub i64 %obj_bits, 4
    %optr = inttoptr i64 %op to ptr
    %fv = inttoptr i64 %fvals_p to ptr
    %ft = inttoptr i64 %ftags_p to ptr
    br label %loop
  loop:
    %f = phi i64 [ 0, %0 ], [ %nf, %next ]
    %mask = phi i64 [ 0, %0 ], [ %nmask, %next ]
    %done = icmp sge i64 %f, %k
    br i1 %done, label %ret_m, label %body
  body:
    %tp = getelementptr i64, ptr %ft, i64 %f
    %t = load i64, ptr %tp, align 8
    %is1 = icmp eq i64 %t, 1
    br i1 %is1, label %store_f, label %mark_bit
  store_f:
    %vp = getelementptr i64, ptr %fv, i64 %f
    %v = load i64, ptr %vp, align 8
    %iv = add i64 %ibase, %f
    %iv1 = add i64 %iv, 1
    %dp = getelementptr i64, ptr %optr, i64 %iv1
    store i64 %v, ptr %dp, align 8
    br label %next
  mark_bit:
    %bit = shl i64 1, %f
    %m2 = or i64 %mask, %bit
    br label %next
  next:
    %nmask = phi i64 [ %mask, %store_f ], [ %m2, %mark_bit ]
    %nf = add i64 %f, 1
    br label %loop
  ret_m:
    ret i64 %mask
  IR

# Pure LLVM WArray slot copier: copies acnt 64-bit WValues from abuf_p[astart..] into arr->slots[0..].
fn jp_fill_arr_ll(arr_bits, abuf_p, astart, acnt) (i64 i64 i64 i64) i64
  ll <<~IR
    %ap = and i64 %arr_bits, 140737488355312
    %aq = inttoptr i64 %ap to ptr
    %slp = getelementptr i8, ptr %aq, i64 16
    %dst = load ptr, ptr %slp, align 8
    %src0 = inttoptr i64 %abuf_p to ptr
    %src = getelementptr i64, ptr %src0, i64 %astart
    br label %loop
  loop:
    %j = phi i64 [ 0, %0 ], [ %nj, %body ]
    %done = icmp sge i64 %j, %acnt
    br i1 %done, label %fin, label %body
  body:
    %sp = getelementptr i64, ptr %src, i64 %j
    %v = load i64, ptr %sp, align 8
    %dp = getelementptr i64, ptr %dst, i64 %j
    store i64 %v, ptr %dp, align 8
    %nj = add i64 %j, 1
    br label %loop
  fin:
    ret i64 0
  IR

fn jp_set_slot_ll(ob, f, vb) (i64 i64 i64) i64
  ll <<~IR
    %raw = sub i64 %ob, 4
    %p = inttoptr i64 %raw to ptr
    %idx = add i64 %f, 3
    %sp = getelementptr i64, ptr %p, i64 %idx
    store i64 %vb, ptr %sp, align 8
    ret i64 0
  IR

-> jp_set_inline_slot(o, f, v)
  jp_set_slot_ll(wvalue_bits(o) ## i64, f ## i64, wvalue_bits(v) ## i64)
  nil

# Lock-free 65536-entry (32768 sets x 2 ways) intern cache for 6..15 byte immutable flat strings!
# Non-evicting per slot (once occupied, slot stays pinned in JS_S7_VALS -> 100% GC/escape safe).
JS_S7_KEYS = i64[131072]
JS_S7_VALS = Array.new(65536, nil)
JS_S7_FILL = i64[1]

-> js_s7_cache_set(src_ptr, st, len, s)
  return s if len < 6 || len > 15
  return s if jb_is_flat_str(wvalue_bits(s) ## i64) == 0
  set = js_s7_set_of(src_ptr, st, len)
  s0 = set * 2
  if JS_S7_VALS[s0] == nil
    JS_S7_VALS[s0] = s
    js_s7_commit_slot(src_ptr, st, len, jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64), s0)
    JS_S7_FILL[0] = JS_S7_FILL[0] + 1
  elsif JS_S7_VALS[s0 + 1] == nil
    JS_S7_VALS[s0 + 1] = s
    js_s7_commit_slot(src_ptr, st, len, jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64), s0 + 1)
    JS_S7_FILL[0] = JS_S7_FILL[0] + 1
  s

# Fused whole-object native scanner for schema-predicted inline-slot objects (1..8 properties),
# with optional 1-level nested inline-slot object sub-plans via `sub_ctx_p = [sub_meta_p, sfvals_p, sftags_p]`.
# Returns new byte pos after '}' (>= 0) on full match, or -1 on fallback.
# Uses raw pointers for fvals/ftags/abuf/ameta/out (ZERO bounds checks, ZERO BigInt boxing!).
-> jp_scan_obj_fast(p, i, n, k, kptrs_p, klens_p, vals_p, tags_p, abuf_p, ameta_p, out_p, nb, s7k_p, s7v_p, sub_ctx_p) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  apos = 0 ## i64
  f = 0 ## i64
  while f < k
    if f > 0
      if i < n && jb_ld_u8(p + i) <= 32
        i = jp_skip_ws_ptr(p, i, n)
      return -1 if i >= n || jb_ld_u8(p + i) != 44
      i += 1
    kp = jb_ld_i64(kptrs_p + f * 8)
    kl = jb_ld_i64(klens_p + f * 8)
    i = jp_match_pred_key(p, i, n, kp, kl)
    return -1 if i < 0
    tag = jp_scan_prim_ll(p, i, n, out_p, vals_p, f, nb, s7k_p, s7v_p)
    if tag == 1
      jb_st_i64_u(tags_p + f * 8, 1)
      i = jb_ld_i64(out_p)
    elsif tag == 2
      st = jb_ld_i64(out_p + 8)
      len = jb_ld_i64(out_p + 16)
      return -1 if len >= 16777216 || st >= 8388608
      jb_st_i64_u(vals_p + f * 8, (st << 24) | len)
      jb_st_i64_u(tags_p + f * 8, 2)
      i = jb_ld_i64(out_p)
    elsif tag == 3
      return -1 if ameta_p == 0
      j = jb_ld_i64(out_p)
      if j < n && jb_ld_u8(p + j) <= 32
        j = jp_skip_ws_ptr(p, j, n)
      return -1 if j >= n
      astart = apos
      if jb_ld_u8(p + j) == 93
        jb_st_i64_u(ameta_p + f * 16, astart)
        jb_st_i64_u(ameta_p + f * 16 + 8, 0)
        jb_st_i64_u(tags_p + f * 8, 3)
        i = j + 1
      else
        acnt = 0 ## i64
        while true
          return -1 if apos >= 32
          atag = jp_scan_prim_ll(p, j, n, out_p, abuf_p, apos, nb, s7k_p, s7v_p)
          return -1 if atag != 1
          apos += 1
          acnt += 1
          j = jb_ld_i64(out_p)
          if j < n && jb_ld_u8(p + j) <= 32
            j = jp_skip_ws_ptr(p, j, n)
          return -1 if j >= n
          cb = jb_ld_u8(p + j)
          j += 1
          break if cb == 93
          return -1 if cb != 44
        jb_st_i64_u(ameta_p + f * 16, astart)
        jb_st_i64_u(ameta_p + f * 16 + 8, acnt)
        jb_st_i64_u(tags_p + f * 8, 3)
        i = j
    elsif tag == 4 && sub_ctx_p != 0
      sm_p = jb_ld_i64(sub_ctx_p)
      return -1 if sm_p == 0
      sk = jb_ld_i64(sm_p + f * 8)
      return -1 if sk <= 0
      skp = jb_ld_i64(sm_p + (8 + f) * 8)
      skl = jb_ld_i64(sm_p + (16 + f) * 8)
      sfv_p = jb_ld_i64(sub_ctx_p + 8) + f * 64
      sft_p = jb_ld_i64(sub_ctx_p + 16) + f * 64
      j = jp_scan_obj_fast(p, jb_ld_i64(out_p), n, sk, skp, skl, sfv_p, sft_p, abuf_p, 0, out_p, nb, s7k_p, s7v_p, 0)
      return -1 if j < 0
      jb_st_i64_u(tags_p + f * 8, 4)
      i = j
    else
      return -1
    f += 1
  if i < n && jb_ld_u8(p + i) <= 32
    i = jp_skip_ws_ptr(p, i, n)
  return -1 if i >= n || jb_ld_u8(p + i) != 125
  i + 1

# ---- JSON.parse ----

JS_JP_VIEW_BA = ByteArray.new(1)

fn jp_view_set(ba_bits, ptr, len) (i64 i64 i64) i64
  ll <<~IR
    %p = and i64 %ba_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %ps = getelementptr i8, ptr %q, i64 8
    %l32 = trunc i64 %len to i32
    store i32 %l32, ptr %ps, align 4
    %pd = getelementptr i8, ptr %q, i64 16
    %old = load i64, ptr %pd, align 8
    store i64 %ptr, ptr %pd, align 8
    ret i64 %old
  IR

-> jp_slice_bytes(src_ptr, st, len)
  return "" if len <= 0
  ba = JS_JP_VIEW_BA
  old = jp_view_set(wvalue_bits(ba) ## i64, src_ptr + st, len)
  res = ccall("w_string_from_byte_array", ba)
  jp_view_set(wvalue_bits(ba) ## i64, old, 1)
  res

+ JsonParser
  rw :i, :n, :s, :src_ptr, :bv_keep, :is_ascii, :root_sh, :out, :out_p, :obj_plan, :fvals, :fvals_p, :ftags, :ftags_p, :abuf, :abuf_p, :ameta, :ameta_p, :sfvals, :sfvals_p, :sftags, :sftags_p, :sub_ctx, :sub_ctx_p

  -> new(@s)
    @out = i64[4]
    @out_p = jit_arr_slots_ptr(wvalue_bits(@out) ## i64)
    @fvals = i64[8]
    @fvals_p = jit_arr_slots_ptr(wvalue_bits(@fvals) ## i64)
    @ftags = i64[8]
    @ftags_p = jit_arr_slots_ptr(wvalue_bits(@ftags) ## i64)
    @abuf = i64[32]
    @abuf_p = jit_arr_slots_ptr(wvalue_bits(@abuf) ## i64)
    @ameta = i64[16]
    @ameta_p = jit_arr_slots_ptr(wvalue_bits(@ameta) ## i64)
    @sfvals = i64[64]
    @sfvals_p = jit_arr_slots_ptr(wvalue_bits(@sfvals) ## i64)
    @sftags = i64[64]
    @sftags_p = jit_arr_slots_ptr(wvalue_bits(@sftags) ## i64)
    @sub_ctx = i64[3]
    @sub_ctx[0] = 0
    @sub_ctx[1] = @sfvals_p
    @sub_ctx[2] = @sftags_p
    @sub_ctx_p = jit_arr_slots_ptr(wvalue_bits(@sub_ctx) ## i64)
    reset(@s)

  -> reset(s)
    @s = s
    @i = 0
    @n = s.size
    @is_ascii = s.ascii?
    @bv_keep = nil
    if @n == 0
      @src_ptr = 0
    else
      fp = jp_flat_str_ptr(wvalue_bits(s) ## i64)
      if fp != 0
        @src_ptr = fp
      else
        bv = ccall("w_string_bytes_view", s) ## u8[]
        @bv_keep = bv
        @src_ptr = jit_bytearray_ptr(wvalue_bits(bv) ## i64)
    @r = js_realm()
    @root_sh = js_root_shape(@r.object_proto, OBJ_INLINE, OBJ_IBASE)
    @obj_plan = nil
    self

  -> fail(msg)
    js_throw_syntax(msg + " in JSON at position " + @i.to_s)

  -> parse_top
    p = @src_ptr
    n = @n ## i64
    out = @out
    nb = wvalue_bits(JS_NULL) ## i64
    i = jp_skip_ws_ptr(p, 0, n)
    tag = jp_scan_prim(p, i, n, out, nb)
    v = nil
    if tag == 1
      v = wvalue_from_bits(out[1])
      i = out[0]
    elsif tag == 2
      v = @is_ascii ? @s.slice(out[1], out[2]) : jp_slice_bytes(p, out[1], out[2])
      i = out[0]
    elsif tag == 3
      v = jp_parse_arr(self, @s, @is_ascii, p, out[0], n, @root_sh, out, nb)
      i = out[3]
    elsif tag == 4
      v = jp_parse_obj(self, @s, @is_ascii, p, out[0], n, @root_sh, out, nb)
      i = out[3]
    else
      @i = i
      v = j_value_slow()
      i = @i ## i64
    i = jp_skip_ws_ptr(p, i, n)
    if i < n
      @i = i
      fail("Unexpected non-whitespace character after JSON")
    v

  -> j_value_slow
    p = @src_ptr
    n = @n ## i64
    nb = wvalue_bits(JS_NULL) ## i64
    @i = jp_skip_ws_ptr(p, @i ## i64, n)
    fail("Unexpected end of JSON input") if @i >= @n
    b = jb_ld_u8(p + (@i ## i64))
    if b == 123
      v = jp_parse_obj(self, @s, @is_ascii, p, (@i ## i64) + 1, n, @root_sh, @out, nb)
      @i = @out[3]
      return v
    if b == 91
      v = jp_parse_arr(self, @s, @is_ascii, p, (@i ## i64) + 1, n, @root_sh, @out, nb)
      @i = @out[3]
      return v
    if b == 34
      return j_string_slow()
    if b == 116
      if @i + 4 <= @n && jb_ld_u32(p + (@i ## i64)) == 1702195828
        @i += 4
        return true
      fail("Unexpected token")
    if b == 102
      if @i + 5 <= @n && jb_ld_u32(p + (@i ## i64)) == 1936482662 && jb_ld_u8(p + (@i ## i64) + 4) == 101
        @i += 5
        return false
      fail("Unexpected token")
    if b == 110
      if @i + 4 <= @n && jb_ld_u32(p + (@i ## i64)) == 1819047278
        @i += 4
        return JS_NULL
      fail("Unexpected token")
    if b == 45 || (b >= 48 && b <= 57)
      return j_number_slow()
    fail("Unexpected token '" + jp_slice_bytes(p, @i ## i64, 1) + "'")

  -> j_number_slow
    p = @src_ptr
    n = @n ## i64
    i = @i ## i64
    st = i
    i += 1 if jb_ld_u8(p + i) == 45
    if i >= n || jb_ld_u8(p + i) < 48 || jb_ld_u8(p + i) > 57
      @i = i
      fail("No number after minus sign")
    if jb_ld_u8(p + i) == 48
      i += 1
      if i < n && jb_ld_u8(p + i) >= 48 && jb_ld_u8(p + i) <= 57
        @i = i
        fail("Unexpected number")
    else
      while i < n && jb_ld_u8(p + i) >= 48 && jb_ld_u8(p + i) <= 57
        i += 1
    if i < n && jb_ld_u8(p + i) == 46
      i += 1
      d = i
      while i < n && jb_ld_u8(p + i) >= 48 && jb_ld_u8(p + i) <= 57
        i += 1
      if i == d
        @i = i
        fail("Unterminated fractional number")
    if i < n && ((jb_ld_u8(p + i) | 32) == 101)
      i += 1
      i += 1 if i < n && (jb_ld_u8(p + i) == 43 || jb_ld_u8(p + i) == 45)
      d = i
      while i < n && jb_ld_u8(p + i) >= 48 && jb_ld_u8(p + i) <= 57
        i += 1
      if i == d
        @i = i
        fail("Exponent part is missing a number")
    @i = i
    t = @is_ascii ? @s.slice(st, i - st) : jp_slice_bytes(p, st, i - st)
    t.to_f

  -> j_string_slow
    p = @src_ptr
    n = @n ## i64
    @i += 1
    st = @i ## i64
    en = jp_scan_str_end_ptr(p, st, n)
    if en >= 0
      @i = en + 1
      len = en - st
      return wvalue_from_bits(jp_pack_inline(p, st, len)) if len <= 5
      return @is_ascii ? @s.slice(st, len) : jp_slice_bytes(p, st, len)
    # Slow path with escapes / validation
    while @i < @n
      b = jb_ld_u8(p + (@i ## i64))
      break if b == 34 || b == 92 || b < 32
      @i += 1
    sb = StringBuffer()
    if (@i ## i64) > st
      sb.append(@is_ascii ? @s.slice(st, (@i ## i64) - st) : jp_slice_bytes(p, st, (@i ## i64) - st))
    while true
      fail("Unterminated string") if @i >= @n
      b = jb_ld_u8(p + (@i ## i64))
      if b == 34
        @i += 1
        res = sb.to_s
        ccall("w_value_free_w", sb)
        return res
      fail("Bad control character in string literal") if b < 32
      if b == 92
        @i += 1
        fail("Unterminated string") if @i >= @n
        c = jb_ld_u8(p + (@i ## i64))
        @i += 1
        if c == 110
          sb.append("\n")
        elsif c == 116
          sb.append("\t")
        elsif c == 114
          sb.append("\r")
        elsif c == 98
          sb.append(js_cp_str(8))
        elsif c == 102
          sb.append(js_cp_str(12))
        elsif c == 34 || c == 92 || c == 47
          sb.append(c.chr)
        elsif c == 117
          u = hex4()
          if u >= 0xD800 && u <= 0xDBFF && @i + 1 < @n && jb_ld_u8(p + (@i ## i64)) == 92 && jb_ld_u8(p + (@i ## i64) + 1) == 117
            save = @i
            @i += 2
            lo = hex4()
            if lo >= 0xDC00 && lo <= 0xDFFF
              u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
            else
              @i = save
          sb.append(js_cp_str(u))
        else
          fail("Bad escaped character")
      else
        j = @i ## i64
        while j < n
          bb = jb_ld_u8(p + j)
          break if bb == 34 || bb == 92 || bb < 32
          j += 1
        sb.append(@is_ascii ? @s.slice(@i, j - (@i ## i64)) : jp_slice_bytes(p, @i ## i64, j - (@i ## i64)))
        @i = j
    nil

  -> hex4
    fail("Bad Unicode escape") if @i + 4 > @n
    p = @src_ptr
    v = 0
    k = 0
    while k < 4
      h = js_hexv(jb_ld_u8(p + (@i ## i64) + k))
      fail("Bad Unicode escape") if h < 0
      v = v * 16 + h
      k += 1
    @i += 4
    v

# Module-level hot JSON array & object parsers (zero self/ivar reads in inner loops!).
-> jp_parse_arr(parser, s, is_ascii, p, i, n, root_sh, out, nb)
  i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
  if i < n && jb_ld_u8(p + i) == 93
    out[3] = i + 1
    return js_arr0_fast()
  fast_alloc = !JS_MULTI_REALM[0] && !JS_GC_ON[0]
  arr = fast_alloc ? wvalue_from_bits(jsr_arr0_raw()) : []
  cls_b = js_obj_cls_bits()
  arena_p = JS_ARENA_STATE[0] != 0 ? JS_ARENA_STATE[7] : 0
  sb = wvalue_bits(s) ## i64
  fvals = parser.fvals
  fvals_p = parser.fvals_p
  ftags = parser.ftags
  ftags_p = parser.ftags_p
  abuf_p = parser.abuf_p
  ameta = parser.ameta
  ameta_p = parser.ameta_p
  sfvals = parser.sfvals
  sfvals_p = parser.sfvals_p
  sftags_p = parser.sftags_p
  sub_ctx = parser.sub_ctx
  sub_ctx_p = parser.sub_ctx_p
  out_p = parser.out_p
  arr_plan = nil
  while true
    # Ultra-fast hoisted array-of-objects inner loop (supports nested inline-slot sub-objects too!)
    op = arr_plan != nil ? arr_plan : parser.obj_plan
    if op != nil
      op_sh = op[0]
      op_sh_b = wvalue_bits(op_sh) ## i64
      op_k = op[1]
      op_kp = op[2]
      op_kl = op[3]
      op_s7k = op[7]
      op_s7v = op[8]
      op_subs = op[9]
      op_sm_p = op[11]
      sc_p = op_sm_p != 0 ? sub_ctx_p : 0
      sub_ctx[0] = op_sm_p if sc_p != 0
      done_arr = false
      while true
        i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
        break if i >= n || jb_ld_u8(p + i) != 123
        ni = jp_scan_obj_fast(p, i + 1, n, op_k, op_kp, op_kl, fvals_p, ftags_p, abuf_p, ameta_p, out_p, nb, op_s7k, op_s7v, sc_p)
        break if ni < 0
        ob_cur = 0 ## i64
        if arena_p != 0
          ob_cur = jsr_arena_alloc_obj_raw(arena_p, op_sh_b)
          if ob_cur != 0
            o = wvalue_from_bits(ob_cur)
          else
            o = js_arena_alloc_obj_slow(op_sh)
            ob_cur = wvalue_bits(o) ## i64
        else
          if fast_alloc
            ob_cur = jsr_new_obj_raw(cls_b, op_sh_b)
            o = wvalue_from_bits(ob_cur)
          else
            o = js_new_obj_fast(op_sh)
            ob_cur = wvalue_bits(o) ## i64
        rem = jp_fill_obj_ll(ob_cur, fvals_p, ftags_p, op_k, OBJ_IBASE ## i64)
        if rem != 0
          f = 0 ## i64
          while rem != 0
            if (rem & 1) != 0
              ft = jb_ld_i64(ftags_p + f * 8)
              fv = nil
              if ft == 2
                enc = jb_ld_i64(fvals_p + f * 8)
                st = enc >> 24
                len = enc & 16777215
                if is_ascii && len >= 16 && len <= 31
                  hit31 = js_s31_probe_fast(p, st, len)
                  if hit31 != 0
                    fv = wvalue_from_bits(hit31)
                  else
                    fv = wvalue_from_bits(jsr_str_slice_raw(sb, st, len))
                    js_s31_cache_set(p, st, len, fv) if JS_S31_FILL[0] < 6144
                else
                  fv = is_ascii ? wvalue_from_bits(jsr_str_slice_raw(sb, st, len)) : jp_slice_bytes(p, st, len)
                  js_s7_cache_set(p, st, len, fv) if len >= 6 && len <= 15
              elsif ft == 3
                as = jb_ld_i64(ameta_p + f * 16)
                ac = jb_ld_i64(ameta_p + f * 16 + 8)
                if ac == 0
                  fv = fast_alloc ? wvalue_from_bits(jsr_arr0_raw()) : js_arr0_fast()
                elsif arena_p != 0 && ac <= 8
                  ab_a = jsr_arena_alloc_arr_raw(arena_p, ac, JS_AF_ARRAY ## i64)
                  if ab_a != 0
                    jp_fill_arr_ll(ab_a, abuf_p, as, ac)
                    fv = wvalue_from_bits(ab_a)
                  else
                    fv = wvalue_from_bits(jsr_arr_from_buf_raw(abuf_p, as, ac))
                elsif fast_alloc
                  fv = wvalue_from_bits(jsr_arr_from_buf_raw(abuf_p, as, ac))
                else
                  sub = Array.new(ac, nil)
                  jp_fill_arr_ll(wvalue_bits(sub) ## i64, abuf_p, as, ac)
                  fv = js_mark_array(sub)
              elsif ft == 4
                sp = op_subs[f]
                sp_sh = sp[0]
                sp_sh_b = wvalue_bits(sp_sh) ## i64
                sob_cur = 0 ## i64
                so = nil
                if arena_p != 0
                  sob_cur = jsr_arena_alloc_obj_raw(arena_p, sp_sh_b)
                  if sob_cur != 0
                    so = wvalue_from_bits(sob_cur)
                  else
                    so = js_arena_alloc_obj_slow(sp_sh)
                    sob_cur = wvalue_bits(so) ## i64
                else
                  if fast_alloc
                    sob_cur = jsr_new_obj_raw(cls_b, sp_sh_b)
                    so = wvalue_from_bits(sob_cur)
                  else
                    so = js_new_obj_fast(sp_sh)
                    sob_cur = wvalue_bits(so) ## i64
                f64 = f * 64
                srem = jp_fill_obj_ll(sob_cur, sfvals_p + f64, sftags_p + f64, sp[1], OBJ_IBASE ## i64)
                if srem != 0
                  sf = 0 ## i64
                  while srem != 0
                    if (srem & 1) != 0
                      senc = jb_ld_i64(sfvals_p + f64 + sf * 8)
                      sst = senc >> 24
                      slen = senc & 16777215
                      sfv = is_ascii ? wvalue_from_bits(jsr_str_slice_raw(sb, sst, slen)) : jp_slice_bytes(p, sst, slen)
                      js_s7_cache_set(p, sst, slen, sfv) if slen >= 6 && slen <= 15
                      jp_set_slot_ll(sob_cur, sf, wvalue_bits(sfv) ## i64)
                    srem = srem >> 1
                    sf += 1
                fv = so
              else
                fv = jp_decode_field(s, is_ascii, p, f, fvals, ftags, abuf_p, ameta)
              jp_set_slot_ll(ob_cur, f, wvalue_bits(fv) ## i64)
            rem = rem >> 1
            f += 1
        ccall("w_array_push", arr, o)
        i = ni
        i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
        if i >= n
          parser.i = i
          parser.fail("Unterminated array")
        b = jb_ld_u8(p + i)
        i += 1
        if b == 93
          done_arr = true
          break
        if b != 44
          parser.i = i - 1
          parser.fail("Expected ',' or ']' after array element")
      break if done_arr
    tag = jp_scan_prim(p, i, n, out, nb)
    el = nil
    if tag == 1
      el = wvalue_from_bits(out[1])
      i = out[0]
    elsif tag == 2
      el = is_ascii ? wvalue_from_bits(jsr_str_slice_raw(sb, out[1], out[2])) : jp_slice_bytes(p, out[1], out[2])
      i = out[0]
    elsif tag == 3
      el = jp_parse_arr(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
      i = out[3]
    elsif tag == 4
      el = jp_parse_obj(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
      i = out[3]
    else
      parser.i = i
      el = parser.j_value_slow()
      i = parser.i ## i64
    arr.push(el)
    if arr_plan == nil && arr.size == 1 && el.is_a?(JS:Object) && !el.shape.dict && el.shape.count >= 1 && el.shape.count <= OBJ_INLINE
      arr_plan = jp_build_obj_plan(root_sh, el.shape, el.shape.count)
      jp_plan_learn_subs(arr_plan, root_sh, el) if arr_plan != nil
    i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
    if i >= n
      parser.i = i
      parser.fail("Unterminated array")
    b = jb_ld_u8(p + i)
    i += 1
    break if b == 93
    if b != 44
      parser.i = i - 1
      parser.fail("Expected ',' or ']' after array element")
  out[3] = i
  fast_alloc ? arr : js_mark_array(arr)

-> jp_materialize(sh, cnt, v0, v1, v2, v3, v4, v5, v6, v7)
  o = js_new_obj_fast(sh)
  o.s0 = v0 if cnt >= 1
  o.s1 = v1 if cnt >= 2
  o.s2 = v2 if cnt >= 3
  o.s3 = v3 if cnt >= 4
  o.s4 = v4 if cnt >= 5
  o.s5 = v5 if cnt >= 6
  o.s6 = v6 if cnt >= 7
  o.s7 = v7 if cnt >= 8
  o

-> jp_decode_field(s, is_ascii, p, f, fvals, ftags, abuf_p, ameta)
  t = ftags[f]
  return wvalue_from_bits(fvals[f]) if t == 1
  if t == 2
    enc = fvals[f]
    st = enc >> 24
    len = enc & 16777215
    str = is_ascii ? wvalue_from_bits(jsr_str_slice_raw(wvalue_bits(s) ## i64, st, len)) : jp_slice_bytes(p, st, len)
    js_s7_cache_set(p, st, len, str) if len >= 6 && len <= 15
    return str
  as = ameta[f * 2]
  ac = ameta[f * 2 + 1]
  return js_arr0_fast() if ac == 0
  if !JS_MULTI_REALM[0] && !JS_GC_ON[0]
    return wvalue_from_bits(jsr_arr_from_buf_raw(abuf_p, as ## i64, ac ## i64))
  arr = Array.new(ac, nil)
  jp_fill_arr_ll(wvalue_bits(arr) ## i64, abuf_p, as ## i64, ac ## i64)
  js_mark_array(arr)

JS_JSON_PARSE_PLANS = {}

-> jp_build_obj_plan(root_sh, final_sh, cnt)
  cached = JS_JSON_PARSE_PLANS[final_sh]
  return cached if cached != nil
  ks = final_sh.key_list
  return nil if ks.size != cnt
  kptrs = i64[cnt]
  klens = i64[cnt]
  keep = []
  f = 0
  while f < cnt
    k = ks[f]
    return nil if !js_string?(k)
    pat = "\"" + k + "\":"
    kbv = ccall("w_string_bytes_view", pat) ## u8[]
    kptrs[f] = jit_bytearray_ptr(wvalue_bits(kbv) ## i64)
    klens[f] = pat.size ## i64
    keep.push(pat)
    keep.push(kbv)
    f += 1
  s7k_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64)
  s7v_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_VALS) ## i64)
  # [9]=sub_plans(Array|nil), [10]=sub_meta(i64[24]|nil), [11]=sub_meta_p(i64)
  plan = [final_sh, cnt ## i64, jit_arr_slots_ptr(wvalue_bits(kptrs) ## i64), jit_arr_slots_ptr(wvalue_bits(klens) ## i64), kptrs, klens, keep, s7k_p, s7v_p, nil, nil, 0 ## i64]
  JS_JSON_PARSE_PLANS[final_sh] = plan if JS_JSON_PARSE_PLANS.size < 256
  plan

-> jp_plan_learn_subs(plan, root_sh, sample_obj)
  cnt = plan[1]
  f = 0
  while f < cnt
    v = sample_obj.slot_get(f)
    if v.is_a?(JS:Object) && !v.shape.dict && v.shape.count >= 1 && v.shape.count <= OBJ_INLINE
      sp = jp_build_obj_plan(root_sh, v.shape, v.shape.count)
      if sp != nil
        subs = plan[9]
        if subs == nil
          subs = Array.new(8, nil)
          sm = i64[24]
          plan[9] = subs
          plan[10] = sm
          plan[11] = jit_arr_slots_ptr(wvalue_bits(sm) ## i64)
        if subs[f] == nil
          subs[f] = sp
          sm = plan[10]
          sm[f] = sp[1]
          sm[8 + f] = sp[2]
          sm[16 + f] = sp[3]
    f += 1
  nil

-> jp_parse_obj(parser, s, is_ascii, p, i, n, root_sh, out, nb)
  # Ultra-fast whole-object schema scan (ONE native call for all fields + closing '}'!)
  op = parser.obj_plan
  if op != nil
    fvals = parser.fvals
    fvals_p = parser.fvals_p
    ftags = parser.ftags
    ftags_p = parser.ftags_p
    abuf_p = parser.abuf_p
    ameta = parser.ameta
    k = op[1]
    ni = jp_scan_obj_fast(p, i, n, k, op[2], op[3], fvals_p, ftags_p, abuf_p, parser.ameta_p, parser.out_p, nb, op[7], op[8], 0)
    if ni >= 0
      out[3] = ni
      o = js_new_obj_fast(op[0])
      rem = jp_fill_obj_ll(wvalue_bits(o) ## i64, fvals_p, ftags_p, k, OBJ_IBASE ## i64)
      if rem != 0
        f = 0
        while rem != 0
          if (rem & 1) != 0
            jp_set_inline_slot(o, f, jp_decode_field(s, is_ascii, p, f, fvals, ftags, abuf_p, ameta))
          rem = rem >> 1
          f += 1
      return o
  i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
  if i < n && jb_ld_u8(p + i) == 125
    out[3] = i + 1
    return js_new_obj_fast(root_sh)
  sh = root_sh
  cnt = 0
  v0 = nil; v1 = nil; v2 = nil; v3 = nil; v4 = nil; v5 = nil; v6 = nil; v7 = nil
  o = nil
  while true
    if o == nil && cnt < OBJ_INLINE
      # Ultra-fast path: match predicted `"key":` + optional ws in ONE native call!
      pred = sh.json_pred
      if pred != nil
        ni = jp_match_pred_key(p, i, n, pred[0], pred[1])
        if ni >= 0
          sh = pred[2]
          tag = jp_scan_prim(p, ni, n, out, nb)
          v = nil
          if tag == 1
            v = wvalue_from_bits(out[1])
            i = out[0]
          elsif tag == 2
            v = is_ascii ? s.slice(out[1], out[2]) : jp_slice_bytes(p, out[1], out[2])
            i = out[0]
          elsif tag == 3
            v = jp_parse_arr(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
            i = out[3]
          elsif tag == 4
            v = jp_parse_obj(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
            i = out[3]
          else
            parser.i = ni
            v = parser.j_value_slow()
            i = parser.i ## i64
          if cnt == 0
            v0 = v
          elsif cnt == 1
            v1 = v
          elsif cnt == 2
            v2 = v
          elsif cnt == 3
            v3 = v
          elsif cnt == 4
            v4 = v
          elsif cnt == 5
            v5 = v
          elsif cnt == 6
            v6 = v
          else
            v7 = v
          cnt += 1
          i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
          if i >= n
            parser.i = i
            parser.fail("Unterminated object")
          b = jb_ld_u8(p + i)
          i += 1
          break if b == 125
          if b != 44
            parser.i = i - 1
            parser.fail("Expected ',' or '}' after property value")
          next
      # Prediction miss (first occurrence of this shape transition or escaped/spaced key)
      i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
      if i >= n || jb_ld_u8(p + i) != 34
        parser.i = i
        parser.fail("Expected property name")
      kst = i + 1
      ken = jp_scan_str_end_ptr(p, kst, n)
      if ken >= 0
        klen = ken - kst
        k = klen <= 5 ? wvalue_from_bits(jp_pack_inline(p, kst, klen)) : (is_ascii ? s.slice(kst, klen) : jp_slice_bytes(p, kst, klen))
        i = ken + 1
        i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
        if i >= n || jb_ld_u8(p + i) != 58
          parser.i = i
          parser.fail("Expected ':' after property name")
        i += 1
        tag = jp_scan_prim(p, i, n, out, nb)
        v = nil
        if tag == 1
          v = wvalue_from_bits(out[1])
          i = out[0]
        elsif tag == 2
          v = is_ascii ? s.slice(out[1], out[2]) : jp_slice_bytes(p, out[1], out[2])
          i = out[0]
        elsif tag == 3
          v = jp_parse_arr(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
          i = out[3]
        elsif tag == 4
          v = jp_parse_obj(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
          i = out[3]
        else
          parser.i = i
          v = parser.j_value_slow()
          i = parser.i ## i64
        if k != "__proto__" && sh.slot_of(k) < 0
          nsh = sh.add(k, ATTR_DEFAULT)
          if sh.json_pred == nil
            ks_pat = "\"" + k + "\":"
            kbv = ccall("w_string_bytes_view", ks_pat) ## u8[]
            kptr = jit_bytearray_ptr(wvalue_bits(kbv) ## i64)
            sh.json_pred = [kptr, ks_pat.size ## i64, nsh, [ks_pat, kbv]]
          sh = nsh
          if cnt == 0
            v0 = v
          elsif cnt == 1
            v1 = v
          elsif cnt == 2
            v2 = v
          elsif cnt == 3
            v3 = v
          elsif cnt == 4
            v4 = v
          elsif cnt == 5
            v5 = v
          elsif cnt == 6
            v6 = v
          else
            v7 = v
          cnt += 1
        else
          o = jp_materialize(sh, cnt, v0, v1, v2, v3, v4, v5, v6, v7)
          if k == "__proto__"
            o.define(k, v, ATTR_ALL)
          else
            o.put_own(k, v)
      else
        o = jp_materialize(sh, cnt, v0, v1, v2, v3, v4, v5, v6, v7)
        parser.i = i
        k = parser.j_string_slow()
        i = parser.i ## i64
        i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
        if i >= n || jb_ld_u8(p + i) != 58
          parser.i = i
          parser.fail("Expected ':' after property name")
        i += 1
        parser.i = i
        v = parser.j_value_slow()
        i = parser.i ## i64
        if k == "__proto__"
          o.define(k, v, ATTR_ALL)
        else
          o.put_own(k, v)
    else
      o = jp_materialize(sh, cnt, v0, v1, v2, v3, v4, v5, v6, v7) if o == nil
      i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
      if i >= n || jb_ld_u8(p + i) != 34
        parser.i = i
        parser.fail("Expected property name")
      parser.i = i
      k = parser.j_string_slow()
      i = parser.i ## i64
      i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
      if i >= n || jb_ld_u8(p + i) != 58
        parser.i = i
        parser.fail("Expected ':' after property name")
      i += 1
      tag = jp_scan_prim(p, i, n, out, nb)
      v = nil
      if tag == 1
        v = wvalue_from_bits(out[1])
        i = out[0]
      elsif tag == 2
        v = is_ascii ? s.slice(out[1], out[2]) : jp_slice_bytes(p, out[1], out[2])
        i = out[0]
      elsif tag == 3
        v = jp_parse_arr(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
        i = out[3]
      elsif tag == 4
        v = jp_parse_obj(parser, s, is_ascii, p, out[0], n, root_sh, out, nb)
        i = out[3]
      else
        parser.i = i
        v = parser.j_value_slow()
        i = parser.i ## i64
      if k == "__proto__"
        o.define(k, v, ATTR_ALL)
      else
        o.put_own(k, v)
    i = jp_skip_ws_ptr(p, i, n) if i < n && jb_ld_u8(p + i) <= 32
    if i >= n
      parser.i = i
      parser.fail("Unterminated object")
    b = jb_ld_u8(p + i)
    i += 1
    break if b == 125
    if b != 44
      parser.i = i - 1
      parser.fail("Expected ',' or '}' after property value")
  out[3] = i
  return o if o != nil
  parser.obj_plan = jp_build_obj_plan(root_sh, sh, cnt) if parser.obj_plan == nil && cnt >= 1
  jp_materialize(sh, cnt, v0, v1, v2, v3, v4, v5, v6, v7)

JS_JP_POOL = [nil]

-> js_json_parse(text, reviver)
  s = js_to_string(text)
  if js_callable?(reviver)
    pr = js_json_parse_snap(s)
    root = js_realm().new_object
    root.put_own("", pr[0])
    return js_json_revive_src(root, "", reviver, pr[1])
  jp = JS_JP_POOL[0]
  if jp != nil
    JS_JP_POOL[0] = nil
    jp.reset(s)
  else
    jp = JS:JsonParser.new(s)
  v = nil
  begin
    v = jp.parse_top
  rescue e
    jp.s = nil
    jp.bv_keep = nil
    JS_JP_POOL[0] = jp if JS_JP_POOL[0] == nil
    raise e
  jp.s = nil
  jp.bv_keep = nil
  JS_JP_POOL[0] = jp if JS_JP_POOL[0] == nil
  v

# Recursive JSON parser that also captures raw source slices for reviver context.source (ES2026).
+ JsonSnapParser
  rw :s, :i, :n, :r

  -> new(@s)
    @i = 0
    @n = @s.size
    @r = js_realm()

  -> fail(msg)
    js_throw_syntax(msg + " in JSON at position " + @i.to_s)

  -> skip_ws
    while @i < @n
      b = @s.byte_at(@i)
      break if b != 32 && b != 9 && b != 10 && b != 13
      @i += 1
    nil

  -> parse_top
    skip_ws()
    res = parse_val()
    skip_ws()
    fail("Unexpected non-whitespace character after JSON") if @i < @n
    res

  -> parse_val
    skip_ws()
    fail("Unexpected end of JSON input") if @i >= @n
    b = @s.byte_at(@i)
    return parse_obj() if b == 123
    return parse_arr() if b == 91
    st = @i
    if b == 34
      sv = parse_str()
      return [sv, [:prim, sv, @s.slice(st, @i - st)]]
    if b == 116
      if @i + 4 <= @n && @s.slice(@i, 4) == "true"
        @i += 4
        return [true, [:prim, true, "true"]]
      fail("Unexpected token")
    if b == 102
      if @i + 5 <= @n && @s.slice(@i, 5) == "false"
        @i += 5
        return [false, [:prim, false, "false"]]
      fail("Unexpected token")
    if b == 110
      if @i + 4 <= @n && @s.slice(@i, 4) == "null"
        @i += 4
        return [JS_NULL, [:prim, JS_NULL, "null"]]
      fail("Unexpected token")
    if b == 45 || (b >= 48 && b <= 57)
      nv = parse_num()
      return [nv, [:prim, nv, @s.slice(st, @i - st)]]
    fail("Unexpected token")

  -> parse_arr
    @i += 1
    arr = []
    snaps = []
    skip_ws()
    if @i < @n && @s.byte_at(@i) == 93
      @i += 1
      ja = js_mark_array(arr)
      return [ja, [:arr, ja, snaps]]
    while true
      el = parse_val()
      arr.push(el[0])
      snaps.push(el[1])
      skip_ws()
      fail("Unterminated array") if @i >= @n
      b = @s.byte_at(@i)
      @i += 1
      break if b == 93
      fail("Expected ',' or ']' after array element") if b != 44
    ja = js_mark_array(arr)
    [ja, [:arr, ja, snaps]]

  -> parse_obj
    @i += 1
    o = @r.new_object
    snaps = {}
    skip_ws()
    if @i < @n && @s.byte_at(@i) == 125
      @i += 1
      return [o, [:obj, o, snaps]]
    while true
      skip_ws()
      fail("Expected property name") if @i >= @n || @s.byte_at(@i) != 34
      k = parse_str()
      skip_ws()
      fail("Expected ':' after property name") if @i >= @n || @s.byte_at(@i) != 58
      @i += 1
      pv = parse_val()
      if k == "__proto__"
        o.define(k, pv[0], ATTR_ALL)
      else
        o.put_own(k, pv[0])
      snaps[k] = pv[1]
      skip_ws()
      fail("Unterminated object") if @i >= @n
      b = @s.byte_at(@i)
      @i += 1
      break if b == 125
      fail("Expected ',' or '}' after property value") if b != 44
    [o, [:obj, o, snaps]]

  -> parse_num
    st = @i
    @i += 1 if @s.byte_at(@i) == 45
    fail("No number after minus sign") if @i >= @n || @s.byte_at(@i) < 48 || @s.byte_at(@i) > 57
    if @s.byte_at(@i) == 48
      @i += 1
      fail("Unexpected number") if @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
    else
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
    if @i < @n && @s.byte_at(@i) == 46
      @i += 1
      d = @i
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
      fail("Unterminated fractional number") if @i == d
    if @i < @n && ((@s.byte_at(@i) | 32) == 101)
      @i += 1
      @i += 1 if @i < @n && (@s.byte_at(@i) == 43 || @s.byte_at(@i) == 45)
      d = @i
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
      fail("Exponent part is missing a number") if @i == d
    @s.slice(st, @i - st).to_f

  -> parse_str
    @i += 1
    sb = StringBuffer()
    while true
      fail("Unterminated string") if @i >= @n
      b = @s.byte_at(@i)
      if b == 34
        @i += 1
        res = sb.to_s
        ccall("w_value_free_w", sb)
        return res
      fail("Bad control character in string literal") if b < 32
      if b == 92
        @i += 1
        fail("Unterminated string") if @i >= @n
        c = @s.byte_at(@i)
        @i += 1
        if c == 110
          sb.append("\n")
        elsif c == 116
          sb.append("\t")
        elsif c == 114
          sb.append("\r")
        elsif c == 98
          sb.append(js_cp_str(8))
        elsif c == 102
          sb.append(js_cp_str(12))
        elsif c == 34 || c == 92 || c == 47
          sb.append(c.chr)
        elsif c == 117
          u = hex4()
          if u >= 0xD800 && u <= 0xDBFF && @i + 1 < @n && @s.byte_at(@i) == 92 && @s.byte_at(@i + 1) == 117
            save = @i
            @i += 2
            lo = hex4()
            if lo >= 0xDC00 && lo <= 0xDFFF
              u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
            else
              @i = save
          sb.append(js_cp_str(u))
        else
          fail("Bad escaped character")
      else
        st = @i
        while @i < @n
          bb = @s.byte_at(@i)
          break if bb == 34 || bb == 92 || bb < 32
          @i += 1
        sb.append(@s.slice(st, @i - st))
    nil

  -> hex4
    fail("Bad Unicode escape") if @i + 4 > @n
    v = 0
    k = 0
    while k < 4
      h = js_hexv(@s.byte_at(@i + k))
      fail("Bad Unicode escape") if h < 0
      v = v * 16 + h
      k += 1
    @i += 4
    v

-> js_json_parse_snap(s)
  JS:JsonSnapParser.new(s).parse_top

-> js_json_revive_src(holder, k, reviver, snap)
  v = jget(holder, k)
  ctx = js_realm().new_object
  if js_object?(v)
    if js_is_array(v)
      n = js_len_of(v)
      csnaps = (snap != nil && snap[0] == :arr && snap[1] == v) ? snap[2] : nil
      i = 0
      while i < n
        cs = (csnaps != nil && i < csnaps.size) ? csnaps[i] : nil
        nv = js_json_revive_src(v, i.to_s, reviver, cs)
        if nv == nil
          jdelete(v, i.to_s)
        else
          jdefine_own_property(v, i.to_s, JS:PropDesc.data(nv, ATTR_ALL))
        i += 1
    else
      ks = js_own_enum_keys(v)
      csnaps = (snap != nil && snap[0] == :obj && snap[1] == v) ? snap[2] : nil
      i = 0
      while i < ks.size
        pk = ks[i]
        cs = csnaps != nil ? csnaps[pk] : nil
        nv = js_json_revive_src(v, pk, reviver, cs)
        if nv == nil
          jdelete(v, pk)
        else
          jdefine_own_property(v, pk, JS:PropDesc.data(nv, ATTR_ALL))
        i += 1
  elsif snap != nil && snap[0] == :prim && js_same_value(v, snap[1])
    ctx.put_own("source", snap[2])
  js_call_arr(reviver, holder, [k, v, ctx])

-> js_json_raw_json(text)
  s = js_to_string(text)
  n = s.size
  js_throw_syntax("JSON.rawJSON cannot be empty") if n == 0
  b0 = s.byte_at(0)
  bn = s.byte_at(n - 1)
  if b0 == 9 || b0 == 10 || b0 == 13 || b0 == 32 || bn == 9 || bn == 10 || bn == 13 || bn == 32
    js_throw_syntax("JSON.rawJSON text cannot start or end with whitespace")
  js_throw_syntax("JSON.rawJSON text must be a JSON primitive") if b0 == 123 || b0 == 91
  # Validate as a single complete JSON primitive value
  js_json_parse_snap(s)
  o = js_new_special(nil, "RawJSON")
  o.define("rawJSON", s, ATTR_ALL)
  js_freeze(o)
  o

-> js_json_is_raw_json(v)
  js_special?(v, "RawJSON")

# ---- Fast-path JSON.stringify (reusable flat ByteArray + cached JS:Shape plans) ----

JS_JSON_ESC = ["\\u0000", "\\u0001", "\\u0002", "\\u0003", "\\u0004", "\\u0005", "\\u0006", "\\u0007", "\\b", "\\t", "\\n", "\\u000b", "\\f", "\\r", "\\u000e", "\\u000f", "\\u0010", "\\u0011", "\\u0012", "\\u0013", "\\u0014", "\\u0015", "\\u0016", "\\u0017", "\\u0018", "\\u0019", "\\u001a", "\\u001b", "\\u001c", "\\u001d", "\\u001e", "\\u001f"]

JS_JSON_INIT = [false]
JS_JSON_SLAB_BASE = i64[1]
JS_JSON_BUF_POOL = [nil]

-> js_json_init_lits
  return nil if JS_JSON_INIT[0]
  JS_JSON_INIT[0] = true
  probe = "__blade_slab_probe__"
  pbv = ccall("w_string_bytes_view", probe) ## u8[]
  JS_JSON_SLAB_BASE[0] = jb_probe_slab_base(wvalue_bits(probe) ## i64, jit_bytearray_ptr(wvalue_bits(pbv) ## i64), 20)
  nil

+ JsonFastWriter
  rw :buf, :dst_ptr, :pos, :cap, :stack, :obj_proto, :r, :slab_base, :run_st

  -> new(@r)
    @buf = ByteArray.new(16384)
    @dst_ptr = jit_bytearray_ptr(wvalue_bits(@buf) ## i64)
    @pos = 0
    @cap = 16384
    @stack = []
    @obj_proto = @r.object_proto
    @slab_base = JS_JSON_SLAB_BASE[0]
    @run_st = i64[2]

  -> reset(r)
    @r = r
    @obj_proto = r.object_proto
    @pos = 0
    @stack.clear
    @slab_base = JS_JSON_SLAB_BASE[0]
    self

  -> grow(min_extra)
    need = (@pos ## i64) + (min_extra ## i64)
    nc = (@cap ## i64) * 2
    while nc < need
      nc = nc * 2
    nb = ByteArray.new(nc)
    np = jit_bytearray_ptr(wvalue_bits(nb) ## i64)
    jb_memcpy_raw(np, 0, @dst_ptr, @pos ## i64) if @pos > 0
    @buf = nb
    @dst_ptr = np
    @cap = nc
    nil

  -> reserve(need)
    grow(need) if (@pos ## i64) + (need ## i64) > (@cap ## i64)
    nil

  -> put_byte(b)
    grow(64) if @pos >= @cap
    jb_st_u8(@dst_ptr + (@pos ## i64), b ## i64)
    @pos += 1
    nil

  -> put_null
    reserve(4)
    jb_st_u32(@dst_ptr + (@pos ## i64), 1819047278)
    @pos += 4
    nil

  -> put_str_raw(s)
    n = s.size
    return nil if n == 0
    reserve(n)
    sv = ccall("w_string_bytes_view", s) ## u8[]
    sp = jit_bytearray_ptr(wvalue_bits(sv) ## i64)
    @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, sp, n ## i64)
    nil

  -> put_quoted_slow(s)
    n = s.size
    if n == 0
      reserve(2)
      jb_st_u8(@dst_ptr + (@pos ## i64), 34)
      jb_st_u8(@dst_ptr + (@pos ## i64) + 1, 34)
      @pos += 2
      return nil
    sv = ccall("w_string_bytes_view", s) ## u8[]
    if jb_is_clean_str(sv, n) != 0
      reserve(n + 2)
      sp = jit_bytearray_ptr(wvalue_bits(sv) ## i64)
      jb_st_u8(@dst_ptr + (@pos ## i64), 34)
      p = jb_memcpy_raw(@dst_ptr, (@pos ## i64) + 1, sp, n ## i64)
      jb_st_u8(@dst_ptr + p, 34)
      @pos = p + 1
      return nil
    put_str_raw(js_json_quote(s))
    nil

  -> check_cycle(v)
    st = @stack
    n = st.size
    i = 0
    while i < n
      js_throw_type("Converting circular structure to JSON") if js_ident?(st[i], v)
      i += 1
    nil

  -> build_shape_plan(sh)
    ks = sh.key_list
    n = ks.size
    kptrs = i64[n]
    klens = i64[n]
    ivars = i64[n]
    keep = []
    i = 0
    while i < n
      k = ks[i]
      if !js_string?(k) || k == "toJSON"
        sh.json_plan = false
        return false
      at = sh.attrs_of(k)
      if (at & ATTR_ACCESSOR) != 0 || (at & ATTR_E) == 0
        sh.json_plan = false
        return false
      sl = sh.slot_of(k)
      if sl < 0 || sl >= sh.inline
        sh.json_plan = false
        return false
      s2 = "," + js_json_quote(k) + ":"
      bv = ccall("w_string_bytes_view", s2) ## u8[]
      keep.push(s2)
      keep.push(bv)
      kptrs[i] = jit_bytearray_ptr(wvalue_bits(bv) ## i64)
      klens[i] = s2.size ## i64
      ivars[i] = (sh.ibase + sl) ## i64
      i += 1
    kp_ptr = jit_arr_slots_ptr(wvalue_bits(kptrs) ## i64)
    kl_ptr = jit_arr_slots_ptr(wvalue_bits(klens) ## i64)
    iv_ptr = jit_arr_slots_ptr(wvalue_bits(ivars) ## i64)
    plan = [n ## i64, kp_ptr, kl_ptr, iv_ptr, kptrs, klens, ivars, keep]
    sh.json_plan = plan
    plan

  -> write_val(v)
    nb = wvalue_bits(JS_NULL) ## i64
    r = jb_write_prim_val(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, nb, @slab_base)
    if r >= 0
      @pos = r
      return nil
    if r == -1
      grow(1024)
      r = jb_write_prim_val(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, nb, @slab_base)
      if r >= 0
        @pos = r
        return nil
    if js_number?(v)
      if js_finite?(v)
        put_str_raw(js_number_to_s(v))
      else
        put_null()
      return nil
    if js_string?(v)
      put_quoted_slow(v)
      return nil
    if v.is_a?(JS:BigIntValue)
      js_throw_type("Do not know how to serialize a BigInt")
    # Plain dense JS Array fast path (with pure-LLVM monomorphic run loop!)
    if jb_is_dense_arr(wvalue_bits(v) ## i64) != 0
      rp = jb_write_prim_arr(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, nb, @slab_base)
      if rp >= 0
        @pos = rp
        return nil
      if rp == -1
        grow(1024)
        rp = jb_write_prim_arr(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, nb, @slab_base)
        if rp >= 0
          @pos = rp
          return nil
      check_cycle(v)
      @stack.push(v)
      put_byte(91)
      n = v.size
      last_sh = 0
      ln = 0
      lkp = 0
      lkl = 0
      liv = 0
      i = 0
      st_out = @run_st
      while i < n
        rc = jb_write_arr_run(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, i ## i64, n ## i64, last_sh ## i64, ln ## i64, lkp ## i64, lkl ## i64, liv ## i64, nb, @slab_base, st_out)
        @pos = st_out[0]
        i = st_out[1]
        break if rc == 0
        if rc == -1
          grow(4096)
          next
        # Element i needs untyped dispatch (new shape, nested array, escaped string, symbol, etc.)
        put_byte(44) if i > 0
        el = v[i]
        if el.is_a?(JS:Object) && el.shape.proto == @obj_proto && !el.shape.dict
          sh = el.shape
          plan = sh.json_plan
          plan = build_shape_plan(sh) if plan == nil
          if plan != false
            last_sh = wvalue_bits(sh) ## i64
            ln = plan[0]
            lkp = plan[1]
            lkl = plan[2]
            liv = plan[3]
            ro = jb_write_obj_fast(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(el) ## i64, ln ## i64, lkp ## i64, lkl ## i64, liv ## i64, nb, @slab_base)
            if ro == -1
              grow(4096)
              ro = jb_write_obj_fast(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(el) ## i64, ln ## i64, lkp ## i64, lkl ## i64, liv ## i64, nb, @slab_base)
            if ro >= 0
              @pos = ro
            else
              write_plain_obj_slow(el, plan)
          else
            write_slow_val(v, i.to_s, el, true)
        elsif js_number?(el)
          if js_finite?(el)
            put_str_raw(js_number_to_s(el))
          else
            put_null()
        elsif js_string?(el)
          put_quoted_slow(el)
        elsif el == nil || el.is_a?(JS:Symbol)
          put_null()
        elsif js_callable?(el)
          if el.is_a?(JS:Base) && (el.has_own?("toJSON") || el.proto != @r.function_proto || @r.function_proto.has_own?("toJSON") || @r.function_proto.proto != @r.object_proto)
            write_slow_val(v, i.to_s, el, true)
          else
            put_null()
        elsif jb_is_dense_arr(wvalue_bits(el) ## i64) != 0
          write_val(el)
        else
          write_slow_val(v, i.to_s, el, true)
        i += 1
      put_byte(93)
      @stack.pop
      return nil
    # Plain JS:Object with cached shape plan fast path
    if v.is_a?(JS:Object) && v.shape.proto == @obj_proto && !v.shape.dict
      sh = v.shape
      plan = sh.json_plan
      plan = build_shape_plan(sh) if plan == nil
      if plan != false
        ro = jb_write_obj_fast(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, plan[0], plan[1], plan[2], plan[3], nb, @slab_base)
        if ro >= 0
          @pos = ro
          return nil
        if ro == -1
          grow(4096)
          ro = jb_write_obj_fast(@dst_ptr, @pos ## i64, @cap ## i64, wvalue_bits(v) ## i64, plan[0], plan[1], plan[2], plan[3], nb, @slab_base)
          if ro >= 0
            @pos = ro
            return nil
        write_plain_obj_slow(v, plan)
        return nil
    write_slow_val(nil, "", v, false)
    nil

  -> write_plain_obj_slow(o, plan)
    check_cycle(o)
    @stack.push(o)
    put_byte(123)
    ob = wvalue_bits(o) ## i64
    nb = wvalue_bits(JS_NULL) ## i64
    sh = o.shape
    n = plan[0]
    kp_ptr = plan[1]
    kl_ptr = plan[2]
    iv_ptr = plan[3]
    first = true
    i = 0
    while i < n
      iv = jb_ld_i64(iv_ptr + (i ## i64) * 8)
      if jb_ivar_is_undef(ob, iv) == 0
        kp = jb_ld_i64(kp_ptr + (i ## i64) * 8)
        kl = jb_ld_i64(kl_ptr + (i ## i64) * 8)
        if first
          kp += 1
          kl -= 1
        r = jb_try_write_ivar_prim(@dst_ptr, @pos ## i64, @cap ## i64, ob, iv, kp, kl, nb, @slab_base)
        if r == -1
          grow(kl + 1024)
          r = jb_try_write_ivar_prim(@dst_ptr, @pos ## i64, @cap ## i64, ob, iv, kp, kl, nb, @slab_base)
        if r >= 0
          @pos = r
          first = false
        else
          val = wvalue_from_bits(jsr_ivar(ob, iv))
          if !val.is_a?(JS:Symbol) && (!js_callable?(val) || (val.is_a?(JS:Base) && (val.has_own?("toJSON") || val.proto != @r.function_proto || @r.function_proto.has_own?("toJSON") || @r.function_proto.proto != @r.object_proto)))
            if js_number?(val)
              reserve(kl + 32)
              @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, kp, kl)
              if js_finite?(val)
                put_str_raw(js_number_to_s(val))
              else
                put_null()
              first = false
            elsif js_string?(val)
              reserve(kl + 4)
              @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, kp, kl)
              put_quoted_slow(val)
              first = false
            elsif jb_is_dense_arr(wvalue_bits(val) ## i64) != 0 || (val.is_a?(JS:Object) && val.shape.proto == @obj_proto && !val.shape.dict && val.shape.json_plan != false)
              if val.is_a?(JS:Object) && val.shape.json_plan == nil
                build_shape_plan(val.shape)
              if !val.is_a?(JS:Object) || val.shape.json_plan != false
                reserve(kl + 4)
                @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, kp, kl)
                write_val(val)
                first = false
              else
                w = JS:JsonWriter.new(nil, nil, "")
                w.stack = @stack.dup
                p = js_json_prep(w, o, sh.key_list[i], val)
                if p != JS_HOLE
                  reserve(kl + 4)
                  @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, kp, kl)
                  js_json_write(w, p)
                  put_str_raw(w.sb.to_s)
                  first = false
            else
              w = JS:JsonWriter.new(nil, nil, "")
              w.stack = @stack.dup
              p = js_json_prep(w, o, sh.key_list[i], val)
              if p != JS_HOLE
                reserve(kl + 4)
                @pos = jb_memcpy_raw(@dst_ptr, @pos ## i64, kp, kl)
                js_json_write(w, p)
                put_str_raw(w.sb.to_s)
                first = false
      i += 1
    put_byte(125)
    @stack.pop
    nil

  -> write_slow_val(holder, key, v, in_arr)
    w = JS:JsonWriter.new(nil, nil, "")
    w.stack = @stack.dup
    ok = js_json_ser(w, holder, key, v)
    if ok
      put_str_raw(w.sb.to_s)
    elsif in_arr
      put_null()
    nil

  -> finish
    n = @pos ## i64
    return "" if n == 0
    return wvalue_from_bits(jp_pack_inline(@dst_ptr, 0, n)) if n <= 5
    out = ByteArray.new(n + 1)
    jb_memcpy_raw(jit_bytearray_ptr(wvalue_bits(out) ## i64), 0, @dst_ptr, n)
    res = ccall("w_string_take_byte_array", out, n)
    ccall("w_value_free_w", out)
    res

# ---- Standard stringify (replacer / space / edge cases) ----

+ JsonWriter
  rw :sb, :stack, :indent, :gap, :replacer, :allow

  -> new(@replacer, @allow, @gap)
    @sb = StringBuffer()
    @stack = []
    @indent = ""

-> js_json_quote(s)
  sb = StringBuffer()
  sb.append("\"")
  n = s.size
  st = 0
  i = 0
  while i < n
    b = s.byte_at(i)
    if b < 32 || b == 34 || b == 92
      sb.append(s.slice(st, i - st)) if i > st
      if b == 34
        sb.append("\\\"")
      elsif b == 92
        sb.append("\\\\")
      else
        sb.append(JS_JSON_ESC[b])
      st = i + 1
    elsif b == 0xED && i + 2 < n && s.byte_at(i + 1) >= 0xA0
      # a lone surrogate (WTF-8): escape it
      sb.append(s.slice(st, i - st)) if i > st
      cp = ((b & 0x0F) << 12) | ((s.byte_at(i + 1) & 0x3F) << 6) | (s.byte_at(i + 2) & 0x3F)
      sb.append("\\u" + JS_DIGITS36.slice((cp >> 12) & 15, 1) + JS_DIGITS36.slice((cp >> 8) & 15, 1) + JS_DIGITS36.slice((cp >> 4) & 15, 1) + JS_DIGITS36.slice(cp & 15, 1))
      i += 2
      st = i + 1
    i += 1
  sb.append(s.slice(st, n - st)) if n > st
  sb.append("\"")
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_json_stringify(v, replacer, space)
  r = js_realm()
  # Fast path: no replacer, no space indentation, pristine Object.prototype/Array.prototype (no toJSON)
  if replacer == nil && space == nil && !r.object_proto.has_own?("toJSON") && !r.array_proto.has_own?("toJSON")
    if jb_is_dense_arr(wvalue_bits(v) ## i64) != 0 || (v.is_a?(JS:Object) && v.shape.proto == r.object_proto && !v.shape.dict && !v.has_own?("toJSON"))
      js_json_init_lits()
      fw = JS_JSON_BUF_POOL[0]
      if fw != nil
        JS_JSON_BUF_POOL[0] = nil
        fw.reset(r)
      else
        fw = JS:JsonFastWriter.new(r)
      res = nil
      begin
        fw.write_val(v)
        res = fw.finish()
      rescue e
        JS_JSON_BUF_POOL[0] = fw if JS_JSON_BUF_POOL[0] == nil && fw.cap <= 262144
        raise e
      JS_JSON_BUF_POOL[0] = fw if JS_JSON_BUF_POOL[0] == nil && fw.cap <= 262144
      return res
  fun = nil
  allow = nil
  if js_callable?(replacer)
    fun = replacer
  elsif js_is_array(replacer)
    allow = []
    n = js_len_of(replacer)
    i = 0
    while i < n
      e = js_el(replacer, i)
      item = nil
      if js_string?(e)
        item = e
      elsif js_number?(e)
        item = js_number_to_s(e)
      elsif js_cls(e) == "String" || js_cls(e) == "Number"
        item = js_to_string(e)
      allow.push(item) if item != nil && !allow.include?(item)
      i += 1
  sp = space
  if js_cls(sp) == "Number"
    sp = js_to_number(sp)
  elsif js_cls(sp) == "String"
    sp = js_to_string(sp)
  gap = ""
  if js_number?(sp)
    k = js_to_integer(sp)
    k = ~10.0 if k > ~10.0
    gap = " " * k.to_i if k >= ~1.0
  elsif js_string?(sp)
    gap = js_len(sp) > 10 ? js_substring(sp, 0, 10) : sp
  w = JS:JsonWriter.new(fun, allow, gap)
  wrapper = r.new_object
  wrapper.put_own("", v)
  ok = js_json_ser(w, wrapper, "", v)
  if !ok
    ccall("w_value_free_w", w.sb)
    return nil
  res_s = w.sb.to_s
  ccall("w_value_free_w", w.sb)
  res_s

# toJSON and the replacer, then unwrap boxed primitives. JS_HOLE: not serializable (skip).
-> js_json_prep(w, holder, key, v)
  if js_object?(v) || v.is_a?(JS:BigIntValue)
    tj = js_get_value(v, "toJSON")
    v = js_call_arr(tj, v, [key]) if js_callable?(tj)
  v = js_call_arr(w.replacer, holder, [key, v]) if w.replacer != nil
  c = js_cls(v)
  if c != nil
    if c == "Number"
      v = js_to_number(v)
    elsif c == "String"
      v = js_to_string(v)
    elsif c == "Boolean"
      v = v.internal
    elsif v.internal.is_a?(JS:BigIntValue)
      v = v.internal
  return JS_HOLE if v == nil || v.is_a?(JS:Symbol) || js_callable?(v)
  v

-> js_json_ser(w, holder, key, v)
  p = js_json_prep(w, holder, key, v)
  return false if p == JS_HOLE
  js_json_write(w, p)
  true

-> js_json_write(w, v)
  sb = w.sb
  if v == JS_NULL
    sb.append("null")
  elsif v == true
    sb.append("true")
  elsif v == false
    sb.append("false")
  elsif js_string?(v)
    sb.append(js_json_quote(v))
  elsif js_number?(v)
    sb.append(js_finite?(v) ? js_number_to_s(v) : "null")
  elsif v.is_a?(JS:BigIntValue)
    js_throw_type("Do not know how to serialize a BigInt")
  elsif js_special?(v, "RawJSON")
    sb.append(v.get_own("rawJSON"))
  else
    st = w.stack
    i = 0
    while i < st.size
      js_throw_type("Converting circular structure to JSON") if js_ident?(st[i], v)
      i += 1
    w.stack.push(v)
    stepback = w.indent
    w.indent = w.indent + w.gap
    if js_is_array(v)
      js_json_array(w, v)
    else
      js_json_object(w, v)
    w.stack.pop
    w.indent = stepback
  nil

-> js_json_object(w, o)
  keys = w.allow != nil ? w.allow : js_own_enum_keys(o)
  sb = w.sb
  sb.append("{")
  first = true
  i = 0
  while i < keys.size
    k = keys[i]
    p = js_json_prep(w, o, k, jget(o, k))
    if p != JS_HOLE
      sb.append(",") if !first
      sb.append("\n" + w.indent) if w.gap != ""
      sb.append(js_json_quote(k))
      sb.append(w.gap != "" ? ": " : ":")
      js_json_write(w, p)
      first = false
    i += 1
  if !first && w.gap != ""
    sb.append("\n" + w.indent.slice(0, w.indent.size - w.gap.size))
  sb.append("}")
  nil

-> js_json_array(w, a)
  n = js_len_of(a)
  sb = w.sb
  sb.append("\[")
  i = 0
  while i < n
    sb.append(",") if i > 0
    sb.append("\n" + w.indent) if w.gap != ""
    sb.append("null") if !js_json_ser(w, a, i.to_s, js_el(a, i))
    i += 1
  if n > 0 && w.gap != ""
    sb.append("\n" + w.indent.slice(0, w.indent.size - w.gap.size))
  sb.append("]")
  nil

js_install(->(r) js_install_json(r))

-> js_install_json(r)
  j = js_new_object(r.object_proto)
  r.global.define("JSON", j, BUILTIN_ATTRS)
  j.define(SYM_TO_STRING_TAG, "JSON", ATTR_C)
  r.method(j, "parse", 2, ->(this, args, nt) js_json_parse(js_arg(args, 0), js_arg(args, 1)))
  r.method(j, "stringify", 3, ->(this, args, nt) js_json_stringify(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(j, "rawJSON", 1, ->(this, args, nt) js_json_raw_json(js_arg(args, 0)))
  r.method(j, "isRawJSON", 1, ->(this, args, nt) js_json_is_raw_json(js_arg(args, 0)))
  nil
