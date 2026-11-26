# runtime/b_collections — High-speed Map, Set, WeakMap, WeakSet, WeakRef, FinalizationRegistry.
#
# Compact Ordered Open-Addressed Hash Table (zero MapEntry allocations, 100% ECMA-262
# insertion-order & live-mutation iteration semantics, pure-LLVM fast paths for immediate keys).
#
# Key representation:
#   - Numbers: -0.0 canonicalized to +0.0, all NaNs canonicalized to canonical quiet NaN -> bit-exact!
#   - Inline strings (0..5 bytes, mode <= 5): unique canonical 64-bit immediate -> bit-exact!
#   - Booleans, undefined, null, Symbol, JS:Object, JS:Array: compared by identity -> bit-exact!
#   - Non-inline strings (len >= 6: slab, heap, rope): content-hashed & compared via String ==
#   - BigInt: stored in auxiliary `big` Hash (with insertion-order slot in keys/vals!)

in JS

# ---- LLVM low-level key canonicalization, hashing, and raw table probing ----

# Sentinel returned by jmap_canon_bits for non-inline strings (mode 6/7 or rope) and BigIntValue.
# 0xFFF8000000000000 is unused in JS WValues.
fn jmap_canon_bits(k) (i64) i64
  ll <<~IR
    ; Fast check: number (biased double in [2^48, 0xFFF1 << 48))
    %x = sub i64 %k, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    br i1 %isn, label %num, label %not_num
  num:
    ; Canonicalize -0.0 (0x8001000000000000) -> +0.0 (0x0001000000000000)
    %is_nz = icmp eq i64 %k, u0x8001000000000000
    br i1 %is_nz, label %ret_pz, label %chk_nan
  ret_pz:
    ret i64 281474976710656
  chk_nan:
    %d = bitcast i64 %x to double
    %isnan = fcmp uno double %d, %d
    %res_n = select i1 %isnan, i64 u0x7FF9000000000000, i64 %k
    ret i64 %res_n
  not_num:
    ; Check string tag 0xFFF9 (bit 0 clear)
    %st = and i64 %k, u0xFFFF000000000001
    %is_str = icmp eq i64 %st, u0xFFF9000000000000
    br i1 %is_str, label %str, label %other
  str:
    %m0 = lshr i64 %k, 1
    %mode = and i64 %m0, 7
    %is_inl = icmp ule i64 %mode, 5
    %res_s = select i1 %is_inl, i64 %k, i64 u0xFFF8000000000000
    ret i64 %res_s
  other:
    ; Check rope (generic heap obj with low nibble 0 and >= 16 and type byte 9)
    %lo = and i64 %k, u0xFFFF00000000000F
    %is_gen = icmp eq i64 %lo, 0
    %big = icmp uge i64 %k, 16
    %maybe_r = and i1 %is_gen, %big
    br i1 %maybe_r, label %chk_rope, label %chk_obj
  chk_rope:
    %rq = inttoptr i64 %k to ptr
    %rty = load i8, ptr %rq, align 8
    %isr = icmp eq i8 %rty, 9
    %res_r = select i1 %isr, i64 u0xFFF8000000000000, i64 %k
    ret i64 %res_r
  chk_obj:
    ; Check object instance (low nibble 4): reject BigIntValue (kind == 0 & class_id == BIGINT_CLSID)
    ; Handled safely via caller's big_clsid check or fast kind != 0!
    ret i64 %k
  IR

fn jmap_is_slow_sentinel(cb) (i64) i64
  ll <<~IR
    %c = icmp eq i64 %cb, u0xFFF8000000000000
    %r = zext i1 %c to i64
    ret i64 %r
  IR

# Check if v is a non-heap immediate WValue (nil/false/true, Number, or Inline String <= 5 bytes).
# Safe to store directly into pre-allocated WArray slots without escape-analysis issues!
fn jmap_is_imm(v) (i64) i64
  ll <<~IR
    %small = icmp ule i64 %v, 2
    br i1 %small, label %yes, label %chk_num
  chk_num:
    %x = sub i64 %v, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    br i1 %isn, label %yes, label %chk_str
  chk_str:
    %st = and i64 %v, u0xFFFF000000000001
    %iss = icmp eq i64 %st, u0xFFF9000000000000
    br i1 %iss, label %chk_inl, label %no
  chk_inl:
    %m0 = lshr i64 %v, 1
    %mode = and i64 %m0, 7
    %ok = icmp ule i64 %mode, 5
    %r = zext i1 %ok to i64
    ret i64 %r
  yes:
    ret i64 1
  no:
    ret i64 0
  IR

fn jmap_is_bigint_bits(k, bi_clsid) (i64 i64) i64
  ll <<~IR
    %lo = and i64 %k, u0xFFFF00000000000F
    %c1 = icmp eq i64 %lo, 4
    %c2 = icmp uge i64 %k, 16
    %ok = and i1 %c1, %c2
    br i1 %ok, label %chk, label %no
  chk:
    %p = and i64 %k, 140737488355312
    %q = inttoptr i64 %p to ptr
    %id16 = load i16, ptr %q, align 2
    %id = zext i16 %id16 to i64
    %eq = icmp eq i64 %id, %bi_clsid
    %r = zext i1 %eq to i64
    ret i64 %r
  no:
    ret i64 0
  IR

# Fast 1-multiply 31-bit hash (avg 1.053 probes on 50K sequential IEEE doubles, bit 31 clear -> fits in signed i32!).
fn jmap_hash64(cb) (i64) i64
  ll <<~IR
    %x1 = lshr i64 %cb, 32
    %x2 = xor i64 %cb, %x1
    %x3 = mul i64 %x2, -4658895280553007687
    %x4 = lshr i64 %x3, 32
    %r = and i64 %x4, 2147483647
    ret i64 %r
  IR

fn jmap_st_i64(p, v) (i64 i64) i64
  ll <<~IR
    %q = inttoptr i64 %p to ptr
    store i64 %v, ptr %q, align 8
    ret i64 0
  IR

# Pure LLVM open-addressing probe for canonical bit-exact keys (ZERO boxing, ~3 ns/probe!).
# meta layout (i64[8]):
#   [0]=buckets_ptr [1]=mask [2]=keys_ptr [3]=vals_ptr [4]=hashes_ptr [5]=len [6]=used [7]=size
# Returns: entry index (>=0) if found, -1 if not found, -2 if slow key (long string / BigInt).
fn jmap_find_raw(meta_p, kbits, bi_clsid) (i64 i64 i64) i64
  ll <<~IR
    ; 1. Canonicalize kbits -> cb
    %x = sub i64 %kbits, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    br i1 %isn, label %c_num, label %c_not_num
  c_num:
    %is_nz = icmp eq i64 %kbits, u0x8001000000000000
    br i1 %is_nz, label %c_pz, label %c_nan
  c_pz:
    br label %c_done
  c_nan:
    %d = bitcast i64 %x to double
    %isnan = fcmp uno double %d, %d
    %cb_n = select i1 %isnan, i64 u0x7FF9000000000000, i64 %kbits
    br label %c_done
  c_not_num:
    %st = and i64 %kbits, u0xFFFF000000000001
    %iss = icmp eq i64 %st, u0xFFF9000000000000
    br i1 %iss, label %c_str, label %c_other
  c_str:
    %m0 = lshr i64 %kbits, 1
    %mode = and i64 %m0, 7
    %isinl = icmp ule i64 %mode, 5
    br i1 %isinl, label %c_done, label %ret_slow
  c_other:
    %lo = and i64 %kbits, u0xFFFF00000000000F
    %isgen = icmp eq i64 %lo, 0
    %big = icmp uge i64 %kbits, 16
    %mr = and i1 %isgen, %big
    br i1 %mr, label %c_rope, label %c_obj
  c_rope:
    %rq = inttoptr i64 %kbits to ptr
    %rty = load i8, ptr %rq, align 8
    %isr = icmp eq i8 %rty, 9
    br i1 %isr, label %ret_slow, label %c_done
  c_obj:
    %isinst = icmp eq i64 %lo, 4
    %obig = and i1 %isinst, %big
    br i1 %obig, label %c_bi, label %c_done
  c_bi:
    %op = and i64 %kbits, 140737488355312
    %oq = inttoptr i64 %op to ptr
    %cid16 = load i16, ptr %oq, align 2
    %cid = zext i16 %cid16 to i64
    %isbi = icmp eq i64 %cid, %bi_clsid
    br i1 %isbi, label %ret_slow, label %c_done
  c_done:
    %cb = phi i64 [ 281474976710656, %c_pz ], [ %cb_n, %c_nan ], [ %kbits, %c_str ], [ %kbits, %c_rope ], [ %kbits, %c_obj ], [ %kbits, %c_bi ]
    %mp = inttoptr i64 %meta_p to ptr
    %maskp = getelementptr i64, ptr %mp, i64 1
    %mask = load i64, ptr %maskp, align 8
    %zmask = icmp eq i64 %mask, 0
    br i1 %zmask, label %ret_miss, label %probe_init
  probe_init:
    %baddr = load i64, ptr %mp, align 8
    %bptr = inttoptr i64 %baddr to ptr
    %kptrp = getelementptr i64, ptr %mp, i64 2
    %kaddr = load i64, ptr %kptrp, align 8
    %kptr = inttoptr i64 %kaddr to ptr
    ; 1-multiply 31-bit hash
    %h1 = lshr i64 %cb, 32
    %h2 = xor i64 %cb, %h1
    %h3 = mul i64 %h2, -4658895280553007687
    %h4 = lshr i64 %h3, 32
    %h = and i64 %h4, 2147483647
    %idx0 = and i64 %h, %mask
    br label %loop
  loop:
    %idx = phi i64 [ %idx0, %probe_init ], [ %nidx, %step ]
    %bp = getelementptr i32, ptr %bptr, i64 %idx
    %b32 = load i32, ptr %bp, align 4
    %b = sext i32 %b32 to i64
    %is0 = icmp eq i64 %b, 0
    br i1 %is0, label %ret_miss, label %chk_pos
  chk_pos:
    %pos = icmp sgt i64 %b, 0
    br i1 %pos, label %cmp_key, label %step
  cmp_key:
    %ei = sub i64 %b, 1
    %kp = getelementptr i64, ptr %kptr, i64 %ei
    %ek = load i64, ptr %kp, align 8
    %eq = icmp eq i64 %ek, %cb
    br i1 %eq, label %ret_hit, label %step
  step:
    %idx1 = add i64 %idx, 1
    %nidx = and i64 %idx1, %mask
    br label %loop
  ret_hit:
    ret i64 %ei
  ret_miss:
    ret i64 -1
  ret_slow:
    ret i64 -2
  IR

# Load raw WValue bits at entry index ei from vals array.
fn jmap_val_at(meta_p, ei) (i64 i64) i64
  ll <<~IR
    %mp = inttoptr i64 %meta_p to ptr
    %vpp = getelementptr i64, ptr %mp, i64 3
    %vaddr = load i64, ptr %vpp, align 8
    %vptr = inttoptr i64 %vaddr to ptr
    %ep = getelementptr i64, ptr %vptr, i64 %ei
    %v = load i64, ptr %ep, align 8
    ret i64 %v
  IR

# Pure LLVM Map#set / Set#add for immediate keys & immediate values (Number / InlineStr / Bool / Nil)!
# Handles BOTH in-place updates AND fresh insertions directly in LLVM with ZERO boxing/allocations!
# Returns: 1 on complete fast success, 0 if grow/rehash or heap key/val needs Tungsten path.
fn jmap_put_imm_raw(meta_p, kbits, vbits, keys_cap, bi_clsid) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    ; 1. Verify vbits is immediate (<=2, Number, or InlineStr <= 5 bytes)
    %v_sm = icmp ule i64 %vbits, 2
    br i1 %v_sm, label %v_ok, label %v_num
  v_num:
    %vx = sub i64 %vbits, 281474976710656
    %visn = icmp ult i64 %vx, u0xFFF0000000000001
    br i1 %visn, label %v_ok, label %v_str
  v_str:
    %vst = and i64 %vbits, u0xFFFF000000000001
    %viss = icmp eq i64 %vst, u0xFFF9000000000000
    br i1 %viss, label %v_inl, label %ret_slow
  v_inl:
    %vm0 = lshr i64 %vbits, 1
    %vm = and i64 %vm0, 7
    %vok = icmp ule i64 %vm, 5
    br i1 %vok, label %v_ok, label %ret_slow
  v_ok:
    ; 2. Verify kbits is immediate & canonicalize -> cb
    %k_sm = icmp ule i64 %kbits, 2
    br i1 %k_sm, label %k_done, label %k_num
  k_num:
    %kx = sub i64 %kbits, 281474976710656
    %kisn = icmp ult i64 %kx, u0xFFF0000000000001
    br i1 %kisn, label %k_cnum, label %k_str
  k_cnum:
    %k_nz = icmp eq i64 %kbits, u0x8001000000000000
    br i1 %k_nz, label %k_pz, label %k_nan
  k_pz:
    br label %k_done
  k_nan:
    %kd = bitcast i64 %kx to double
    %knan = fcmp uno double %kd, %kd
    %cb_n = select i1 %knan, i64 u0x7FF9000000000000, i64 %kbits
    br label %k_done
  k_str:
    %kst = and i64 %kbits, u0xFFFF000000000001
    %kiss = icmp eq i64 %kst, u0xFFF9000000000000
    br i1 %kiss, label %k_inl, label %ret_slow
  k_inl:
    %km0 = lshr i64 %kbits, 1
    %km = and i64 %km0, 7
    %kok = icmp ule i64 %km, 5
    br i1 %kok, label %k_done, label %ret_slow
  k_done:
    %cb = phi i64 [ %kbits, %v_ok ], [ 281474976710656, %k_pz ], [ %cb_n, %k_nan ], [ %kbits, %k_inl ]
    %mp = inttoptr i64 %meta_p to ptr
    %maskp = getelementptr i64, ptr %mp, i64 1
    %mask = load i64, ptr %maskp, align 8
    %zm = icmp eq i64 %mask, 0
    br i1 %zm, label %ret_slow, label %p_init
  p_init:
    %baddr = load i64, ptr %mp, align 8
    %bptr = inttoptr i64 %baddr to ptr
    %kptrp = getelementptr i64, ptr %mp, i64 2
    %kaddr = load i64, ptr %kptrp, align 8
    %kptr = inttoptr i64 %kaddr to ptr
    %vptrp = getelementptr i64, ptr %mp, i64 3
    %vaddr = load i64, ptr %vptrp, align 8
    %vptr = inttoptr i64 %vaddr to ptr
    %h1 = lshr i64 %cb, 32
    %h2 = xor i64 %cb, %h1
    %h3 = mul i64 %h2, -4658895280553007687
    %h4 = lshr i64 %h3, 32
    %h = and i64 %h4, 2147483647
    %idx0 = and i64 %h, %mask
    br label %loop
  loop:
    %idx = phi i64 [ %idx0, %p_init ], [ %nidx, %step ]
    %fdel = phi i64 [ -1, %p_init ], [ %nfdel, %step ]
    %bp = getelementptr i32, ptr %bptr, i64 %idx
    %b32 = load i32, ptr %bp, align 4
    %b = sext i32 %b32 to i64
    %is0 = icmp eq i64 %b, 0
    br i1 %is0, label %do_ins, label %chk_pos
  chk_pos:
    %pos = icmp sgt i64 %b, 0
    br i1 %pos, label %cmp_key, label %rec_del
  cmp_key:
    %ei = sub i64 %b, 1
    %kp = getelementptr i64, ptr %kptr, i64 %ei
    %ek = load i64, ptr %kp, align 8
    %eq = icmp eq i64 %ek, %cb
    br i1 %eq, label %do_upd, label %step_keep
  do_upd:
    %vp = getelementptr i64, ptr %vptr, i64 %ei
    store i64 %vbits, ptr %vp, align 8
    ret i64 1
  rec_del:
    %no_del = icmp slt i64 %fdel, 0
    %df = select i1 %no_del, i64 %idx, i64 %fdel
    br label %step
  step_keep:
    br label %step
  step:
    %nfdel = phi i64 [ %df, %rec_del ], [ %fdel, %step_keep ]
    %idx1 = add i64 %idx, 1
    %nidx = and i64 %idx1, %mask
    br label %loop
  do_ins:
    %lenp = getelementptr i64, ptr %mp, i64 5
    %len = load i64, ptr %lenp, align 8
    %usedp = getelementptr i64, ptr %mp, i64 6
    %used = load i64, ptr %usedp, align 8
    %full_k = icmp sge i64 %len, %keys_cap
    %u1 = add i64 %used, 1
    %u4 = shl i64 %u1, 2
    %cap = add i64 %mask, 1
    %c3 = mul i64 %cap, 3
    %full_b = icmp sgt i64 %u4, %c3
    %need_grow = or i1 %full_k, %full_b
    br i1 %need_grow, label %ret_slow, label %write_ins
  write_ins:
    %has_del = icmp sge i64 %fdel, 0
    %slot = select i1 %has_del, i64 %fdel, i64 %idx
    %hptrp = getelementptr i64, ptr %mp, i64 4
    %haddr = load i64, ptr %hptrp, align 8
    %hptr = inttoptr i64 %haddr to ptr
    %kwp = getelementptr i64, ptr %kptr, i64 %len
    store i64 %cb, ptr %kwp, align 8
    %vwp = getelementptr i64, ptr %vptr, i64 %len
    store i64 %vbits, ptr %vwp, align 8
    %h32 = trunc i64 %h to i32
    %hwp = getelementptr i32, ptr %hptr, i64 %len
    store i32 %h32, ptr %hwp, align 4
    %nlen = add i64 %len, 1
    %nlen32 = trunc i64 %nlen to i32
    %bwp = getelementptr i32, ptr %bptr, i64 %slot
    store i32 %nlen32, ptr %bwp, align 4
    store i64 %nlen, ptr %lenp, align 8
    %nused = select i1 %has_del, i64 %used, i64 %u1
    store i64 %nused, ptr %usedp, align 8
    %szp = getelementptr i64, ptr %mp, i64 7
    %sz = load i64, ptr %szp, align 8
    %nsz = add i64 %sz, 1
    store i64 %nsz, ptr %szp, align 8
    ret i64 1
  ret_slow:
    ret i64 0
  IR

# Returns 1 ONLY for non-inline strings (mode >= 6 or rope) that require content hashing.
fn jmap_is_slow_str(k) (i64) i64
  ll <<~IR
    %st = and i64 %k, u0xFFFF000000000001
    %iss = icmp eq i64 %st, u0xFFF9000000000000
    br i1 %iss, label %chk_m, label %chk_r
  chk_m:
    %m0 = lshr i64 %k, 1
    %mode = and i64 %m0, 7
    %big = icmp ugt i64 %mode, 5
    %r1 = zext i1 %big to i64
    ret i64 %r1
  chk_r:
    %lo = and i64 %k, u0xFFFF00000000000F
    %isg = icmp eq i64 %lo, 0
    %ok = icmp uge i64 %k, 16
    %mr = and i1 %isg, %ok
    br i1 %mr, label %hdr, label %no
  hdr:
    %q = inttoptr i64 %k to ptr
    %ty = load i8, ptr %q, align 8
    %isr = icmp eq i8 %ty, 9
    %r2 = zext i1 %isr to i64
    ret i64 %r2
  no:
    ret i64 0
  IR

# Hash bytes of a non-inline string (FNV-1a 64-bit).
-> jmap_hash_str_bytes(src_ptr, len) (i64 i64) i64
  h = 1469598103934665603 ## i64
  i = 0 ## i64
  while i < len
    h = (h ^ jb_ld_u8(src_ptr + i)) * 1099511628211
    i += 1
  jmap_hash64(h)

# Pure-LLVM rehash of all live entries 0..len-1 into fresh i32 bucket table `nbptr` with `nmask`.
fn jmap_rehash_raw(nbptr, nmask, kptr, hptr, len, hole_bits) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %nbp = inttoptr i64 %nbptr to ptr
    %kp = inttoptr i64 %kptr to ptr
    %hp = inttoptr i64 %hptr to ptr
    br label %cond
  cond:
    %ei = phi i64 [ 0, %0 ], [ %nei, %next ]
    %more = icmp slt i64 %ei, %len
    br i1 %more, label %body, label %done
  body:
    %kep = getelementptr i64, ptr %kp, i64 %ei
    %kv = load i64, ptr %kep, align 8
    %ishole = icmp eq i64 %kv, %hole_bits
    br i1 %ishole, label %next, label %ins
  ins:
    %hep = getelementptr i32, ptr %hp, i64 %ei
    %hv32 = load i32, ptr %hep, align 4
    %hv = zext i32 %hv32 to i64
    %idx0 = and i64 %hv, %nmask
    br label %ploop
  ploop:
    %idx = phi i64 [ %idx0, %ins ], [ %nidx, %pstep ]
    %bp = getelementptr i32, ptr %nbp, i64 %idx
    %bv = load i32, ptr %bp, align 4
    %emp = icmp eq i32 %bv, 0
    br i1 %emp, label %store, label %pstep
  pstep:
    %idx1 = add i64 %idx, 1
    %nidx = and i64 %idx1, %nmask
    br label %ploop
  store:
    %ei1 = add i64 %ei, 1
    %ei32 = trunc i64 %ei1 to i32
    store i32 %ei32, ptr %bp, align 4
    br label %next
  next:
    %nei = add i64 %ei, 1
    br label %cond
  done:
    ret i64 0
  IR

# Pure-LLVM zero of i32 bucket array.
fn jmap_zero_i32(p, n) (i64 i64) i64
  ll <<~IR
    %bp = inttoptr i64 %p to ptr
    br label %cond
  cond:
    %i = phi i64 [ 0, %0 ], [ %ni, %body ]
    %more = icmp slt i64 %i, %n
    br i1 %more, label %body, label %done
  body:
    %ep = getelementptr i32, ptr %bp, i64 %i
    store i32 0, ptr %ep, align 4
    %ni = add i64 %i, 1
    br label %cond
  done:
    ret i64 0
  IR

JS_BIGINT_CLSID = i64[1]

-> js_bigint_clsid
  if JS_BIGINT_CLSID[0] == 0
    JS_BIGINT_CLSID[0] = jit_obj_clsid(wvalue_bits(JS:BigIntValue.new(0)) ## i64)
  JS_BIGINT_CLSID[0]

+ MapData
  rw :meta_ptr, :keys_cap, :keys, :vals, :buckets, :hashes, :meta, :big, :gen, :bi_clsid

  -> new
    @keys = Array.new(8, JS_HOLE)
    @vals = Array.new(8, nil)
    @buckets = i32[16]
    @hashes = i32[8]
    @meta = i64[9]
    @meta_ptr = jit_arr_slots_ptr(wvalue_bits(@meta) ## i64)
    @keys_cap = 8
    @big = nil
    @gen = 0
    @bi_clsid = js_bigint_clsid()
    sync_meta(0, 0, 0)

  -> sync_meta(len, used, sz)
    @meta[0] = jit_arr_slots_ptr(wvalue_bits(@buckets) ## i64)
    @meta[1] = (@buckets.size - 1) ## i64
    @meta[2] = jit_arr_slots_ptr(wvalue_bits(@keys) ## i64)
    @meta[3] = jit_arr_slots_ptr(wvalue_bits(@vals) ## i64)
    @meta[4] = jit_arr_slots_ptr(wvalue_bits(@hashes) ## i64)
    @meta[5] = len ## i64
    @meta[6] = used ## i64
    @meta[7] = sz ## i64
    @meta[8] = @keys_cap ## i64
    nil

  -> size
    @meta[7]

  -> len
    @meta[5]

  -> ensure_entries_cap(need)
    return nil if need <= @keys_cap
    nc = @keys_cap <= 16384 ? @keys_cap * 4 : @keys_cap * 2
    while nc < need
      nc = nc * 2
    nk = Array.new(nc, JS_HOLE)
    nv = Array.new(nc, nil)
    nh = i32[nc]
    l = @meta[5]
    nkp = jit_arr_slots_ptr(wvalue_bits(nk) ## i64)
    nvp = jit_arr_slots_ptr(wvalue_bits(nv) ## i64)
    nhp = jit_arr_slots_ptr(wvalue_bits(nh) ## i64)
    if l > 0
      nbytes = l * 8
      jb_memcpy_raw(nkp, 0, @meta[2], nbytes)
      jb_memcpy_raw(nvp, 0, @meta[3], nbytes)
      jb_memcpy_raw(nhp, 0, @meta[4], l * 4)
    @keys = nk
    @vals = nv
    @hashes = nh
    @keys_cap = nc
    @meta[2] = nkp
    @meta[3] = nvp
    @meta[4] = nhp
    @meta[8] = nc ## i64
    nil

  -> rehash(new_bcap)
    nb = i32[new_bcap]
    nbp = jit_arr_slots_ptr(wvalue_bits(nb) ## i64)
    jmap_rehash_raw(nbp, (new_bcap - 1) ## i64, @meta[2], @meta[4], @meta[5], wvalue_bits(JS_HOLE) ## i64)
    @buckets = nb
    @meta[0] = nbp
    @meta[1] = (new_bcap - 1) ## i64
    @meta[6] = @meta[7]
    nil

JS_MAPDATA_METAP_OFF = i64[1]

-> js_find_ivar_off(db, want) (i64 i64) i64
  iv = 0 ## i64
  while iv < 24
    return (iv + 1) * 8 if jsr_ivar(db, iv) == want
    iv += 1
  0

-> js_mapdata_metap_off
  if JS_MAPDATA_METAP_OFF[0] == 0
    d = JS:MapData.new
    JS_MAPDATA_METAP_OFF[0] = js_find_ivar_off(wvalue_bits(d) ## i64, wvalue_bits(d.meta_ptr) ## i64)
  JS_MAPDATA_METAP_OFF[0]

+ NanKey
  -> new
    nil
JS_NAN_KEY = JS:NanKey.new

-> js_map_key(k)
  if js_number?(k)
    if k != k
      k = JS_NAN_KEY
    elsif k == ~0.0
      k = ~0.0
  elsif js_array?(k)
    k = (wvalue_bits(k) ## i64) & 140737488355312
  k

-> js_map_key_hash(k)
  if js_string?(k)
    bv = ccall("w_string_bytes_view", k) ## u8[]
    return jmap_hash_str_bytes(jit_bytearray_ptr(wvalue_bits(bv) ## i64), k.size ## i64)
  js_map_canon_hash(wvalue_bits(k) ## i64)

-> js_map_canon_hash(kbits) (i64) i64
  jmap_hash64(jmap_canon_bits(kbits))

# General lookup returning entry index (>= 0) or -1.
-> js_map_find_idx(d, k)
  ei = jmap_find_raw(d.meta_ptr, wvalue_bits(k) ## i64, d.bi_clsid)
  return ei if ei != -2
  if k.is_a?(JS:BigIntValue)
    return -1 if d.big == nil
    res = d.big[k.v]
    return res == nil ? -1 : res
  # Non-inline string (>= 6 bytes)
  h = js_map_key_hash(k)
  mask = d.meta[1]
  bks = d.buckets
  ks = d.keys
  hs = d.hashes
  idx = h & mask
  while true
    b = bks[idx]
    return -1 if b == 0
    if b > 0
      e = b - 1
      if hs[e] == h && js_string?(ks[e]) && ks[e] == k
        return e
    idx = (idx + 1) & mask
  -1

-> js_map_has(d, k)
  ei = jmap_find_raw(d.meta_ptr, wvalue_bits(k) ## i64, d.bi_clsid)
  return ei >= 0 if ei != -2
  js_map_find_idx(d, k) >= 0

-> js_map_get(d, k)
  ei = jmap_find_raw(d.meta_ptr, wvalue_bits(k) ## i64, d.bi_clsid)
  return wvalue_from_bits(jmap_val_at(d.meta_ptr, ei)) if ei >= 0
  return nil if ei == -1
  ei = js_map_find_idx(d, k)
  ei >= 0 ? d.vals[ei] : nil

-> js_set_add_fast(s, k)
  d = s.internal
  return s if jmap_put_imm_raw(d.meta_ptr, wvalue_bits(k) ## i64, wvalue_bits(k) ## i64, d.keys_cap ## i64, d.bi_clsid) != 0
  js_map_put(d, k, k)
  s

-> js_map_set_fast(m, k, v)
  d = m.internal
  return m if jmap_put_imm_raw(d.meta_ptr, wvalue_bits(k) ## i64, wvalue_bits(v) ## i64, d.keys_cap ## i64, d.bi_clsid) != 0
  js_map_put(d, k, v)
  m

-> js_map_put(d, k, v)
  if jmap_put_imm_raw(d.meta_ptr, wvalue_bits(k) ## i64, wvalue_bits(v) ## i64, d.keys_cap ## i64, d.bi_clsid) != 0
    return nil
  # Canonicalize -0.0 -> +0.0 per SameValueZero
  k = ~0.0 if js_number?(k) && k == ~0.0
  # BigInt key path
  if k.is_a?(JS:BigIntValue)
    if d.big != nil
      ex = d.big[k.v]
      if ex != nil
        d.vals[ex] = v
        return nil
    else
      d.big = {}
    len = d.meta[5]
    d.ensure_entries_cap(len + 1) if len >= d.keys_cap
    d.keys[len] = k
    d.vals[len] = v
    d.hashes[len] = 0 ## i32
    d.big[k.v] = len
    d.meta[5] = len + 1
    d.meta[7] = d.meta[7] + 1
    return nil
  # General path (heap object/string key or needs grow/rehash)
  if (d.meta[6] + 1) * 4 > (d.meta[1] + 1) * 3
    cur_bcap = d.meta[1] + 1
    if d.meta[7] * 2 >= cur_bcap
      ncap = cur_bcap <= 32768 ? cur_bcap * 4 : cur_bcap * 2
    else
      ncap = cur_bcap
    ncap = 16 if ncap < 16
    d.rehash(ncap)
  is_s = jmap_is_slow_str(wvalue_bits(k) ## i64) != 0
  h = is_s ? js_map_key_hash(k) : js_map_canon_hash(wvalue_bits(k) ## i64)
  mask = d.meta[1]
  bks = d.buckets
  ks = d.keys
  hs = d.hashes
  idx = h & mask
  first_del = -1
  while true
    b = bks[idx]
    if b == 0
      len = d.meta[5]
      d.ensure_entries_cap(len + 1) if len >= d.keys_cap
      d.keys[len] = k
      d.vals[len] = v
      d.hashes[len] = h ## i32
      slot = first_del >= 0 ? first_del : idx
      bks[slot] = (len + 1) ## i32
      d.meta[5] = len + 1
      d.meta[6] = d.meta[6] + 1 if first_del < 0
      d.meta[7] = d.meta[7] + 1
      return nil
    if b > 0
      e = b - 1
      if hs[e] == h && (is_s ? (js_string?(ks[e]) && ks[e] == k) : js_same_value_zero(ks[e], k))
        d.vals[e] = v
        return nil
    elsif first_del < 0
      first_del = idx
    idx = (idx + 1) & mask
  nil

-> js_map_remove(d, k)
  if k.is_a?(JS:BigIntValue)
    return false if d.big == nil
    e = d.big[k.v]
    return false if e == nil
    d.big.delete(k.v)
    d.keys[e] = JS_HOLE
    d.vals[e] = nil
    d.meta[7] = d.meta[7] - 1
    return true
  is_s = jmap_is_slow_str(wvalue_bits(k) ## i64) != 0
  h = is_s ? js_map_key_hash(k) : js_map_canon_hash(wvalue_bits(k) ## i64)
  mask = d.meta[1]
  bks = d.buckets
  ks = d.keys
  hs = d.hashes
  idx = h & mask
  while true
    b = bks[idx]
    return false if b == 0
    if b > 0
      e = b - 1
      if hs[e] == h && (is_s ? (js_string?(ks[e]) && ks[e] == k) : js_same_value_zero(ks[e], k))
        bks[idx] = -1 ## i32
        ks[e] = JS_HOLE
        d.vals[e] = nil
        d.meta[7] = d.meta[7] - 1
        return true
    idx = (idx + 1) & mask
  false

-> js_map_clear(d)
  l = d.meta[5]
  ks = d.keys
  vs = d.vals
  i = 0
  while i < l
    ks[i] = JS_HOLE
    vs[i] = nil
    i += 1
  jmap_zero_i32(d.meta[0], d.buckets.size ## i64)
  d.meta[5] = 0
  d.meta[6] = 0
  d.meta[7] = 0
  d.big = nil
  d.gen += 1
  nil

# Legacy compatibility shim (returns truthy/nil for internal checks)
-> js_map_find(d, k)
  js_map_find_idx(d, k) >= 0 ? true : nil

-> js_coll_new(proto, cls)
  m = js_new_special(proto, cls)
  m.internal = JS:MapData.new
  m

-> js_map_new
  js_coll_new(js_realm().intrinsic("Map.prototype"), "Map")

-> js_map_set(m, k, v)
  js_map_put(m.internal, k, v)
  m

-> js_this_map(v, cls)
  js_throw_type("Method " + cls + ".prototype method called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, cls) && v.internal.is_a?(JS:MapData))
  v.internal

-> js_coll_ctor(cls, args, nt, adder_name, pairs)
  js_throw_type("Constructor " + cls + " requires 'new'") if nt == nil
  r = js_realm()
  m = js_coll_new(r.proto_from(nt, cls), cls)
  it = js_arg(args, 0)
  return m if js_nullish?(it)
  adder = m.get(adder_name, m)
  js_throw_type("'" + js_err_display(adder) + "' returned for property '" + adder_name + "' of object '#<" + cls + ">' is not callable") if !js_callable?(adder)
  native_add = adder == r.intrinsic("%" + cls + "_" + adder_name + "%")
  if js_array?(it) && js_array_iter_pristine?(it)
    i = 0
    while i < js_arr_len(it)
      js_coll_add_item(m, adder, native_add, js_arr_elem(it, i), pairs, cls)
      i += 1
    return m
  rec = js_get_iterator(it)
  begin
    while true
      e = js_iter_step(rec)
      break if e == JS_ITER_DONE
      js_coll_add_item(m, adder, native_add, e, pairs, cls)
  rescue ex
    js_iter_close_quiet(rec) if !rec.done
    raise ex
  m

-> js_coll_add_item(m, adder, native_add, e, pairs, cls)
  if pairs
    js_throw_type("Iterator value " + js_err_display(e) + " is not an entry object") if !js_object?(e)
    k = jget(e, "0")
    v = jget(e, "1")
    if native_add
      js_weak_check(k, cls) if cls == "WeakMap"
      js_map_put(m.internal, k, v)
    else
      js_call_arr(adder, m, [k, v])
  else
    if native_add
      js_weak_check(e, cls) if cls == "WeakSet"
      js_map_put(m.internal, e, e)
    else
      js_call_arr(adder, m, [e])
  nil

-> js_weak_check(k, cls)
  js_throw_type("Invalid value used " + (cls == "WeakMap" ? "as weak map key" : "in weak set")) if !(js_object?(k) || (k.is_a?(JS:Symbol) && !js_registered_symbol?(k)))

-> js_registered_symbol?(s)
  reg = js_realm().symbol_registry
  ks = reg.keys
  i = 0
  while i < ks.size
    return true if reg[ks[i]] == s
    i += 1
  false

# A Map or Set iterator's state (integer index into keys/vals + clear-epoch tracking).
+ MapIterState
  rw :map, :idx, :kind, :gen, :done
  -> new(@map, @kind)
    @idx = 0
    @gen = @map.internal.gen
    @done = false

-> js_map_iter(m, kind, proto_name)
  it = js_new_special(js_realm().intrinsic(proto_name), proto_name == "%MapIteratorPrototype%" ? "Map Iterator" : "Set Iterator")
  it.internal = JS:MapIterState.new(m, kind)
  it

-> js_map_iter_next(this, cls)
  js_throw_type("next method called on incompatible receiver " + js_err_display(this)) if !(js_special?(this, cls) && this.internal.is_a?(JS:MapIterState))
  it = this.internal
  return js_iter_result(nil, true) if it.done
  d = it.map.internal
  if it.gen != d.gen
    it.gen = d.gen
    it.idx = 0
  idx = it.idx
  len = d.meta[5]
  ks = d.keys
  while idx < len && ks[idx] == JS_HOLE
    idx += 1
  if idx >= len
    it.done = true
    return js_iter_result(nil, true)
  ek = ks[idx]
  ev = d.vals[idx]
  it.idx = idx + 1
  k = it.kind
  return js_iter_result(ek, false) if k == :keys
  return js_iter_result(ev, false) if k == :values
  js_iter_result(js_realm().adopt_array([ek, ev]), false)

-> js_coll_for_each(m, cls, f, t)
  d = js_this_map(m, cls)
  js_throw_type(js_err_display(f) + " is not a function") if !js_callable?(f)
  g = d.gen
  i = 0
  while i < d.meta[5]
    if d.gen != g
      g = d.gen
      i = 0
      next
    ek = d.keys[i]
    if ek != JS_HOLE
      js_call_arr(f, t, [d.vals[i], ek, m])
    i += 1
  nil

# GetSetRecord (§24.2.1.2): [size, has, keys].
-> js_set_record(other)
  js_throw_type("other is not an object") if !js_object?(other)
  rs = jget(other, "size")
  n = js_to_number(rs)
  js_throw_type("The 'size' property must be a number") if n != n
  sz = js_to_integer(n)
  js_throw_range("The 'size' property must not be negative") if sz < ~0.0
  has = jget(other, "has")
  js_throw_type("other.has is not a function") if !js_callable?(has)
  keys = jget(other, "keys")
  js_throw_type("other.keys is not a function") if !js_callable?(keys)
  [sz, has, keys]

-> js_set_keys_iter(other, keys)
  it = js_call_arr(keys, other, JS_NO_ARGS)
  js_throw_type("keys() result is not an object") if !js_object?(it)
  nx = jget(it, "next")
  js_throw_type("keys() iterator's next is not a function") if !js_callable?(nx)
  JS:IterRecord.new(it, nx)

# Next live entry index >= idx, or -1 if none.
-> js_set_next_live_idx(d, idx)
  len = d.meta[5]
  ks = d.keys
  while idx < len && ks[idx] == JS_HOLE
    idx += 1
  idx < len ? idx : -1

-> js_set_copy_data(d)
  out = JS:MapData.new
  len = d.meta[5]
  ks = d.keys
  i = 0
  while i < len
    ek = ks[i]
    js_map_put(out, ek, ek) if ek != JS_HOLE
    i += 1
  out

-> js_set_canon(k)
  k = ~0.0 if js_number?(k) && k == ~0.0
  k

# The Set methods of ES2025 (§24.2.4)
-> js_set_op(this, other, op)
  d = js_this_map(this, "Set")
  rec = js_set_record(other)
  osize = rec[0]
  has = rec[1]
  keys = rec[2]
  this_size = d.size + ~0.0
  if op == :union
    it = js_set_keys_iter(other, keys)
    out = js_set_copy_data(d)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      k = js_set_canon(k)
      js_map_put(out, k, k)
    return js_set_from_data(out)
  if op == :intersection
    out = JS:MapData.new
    if this_size <= osize
      idx = js_set_next_live_idx(d, 0)
      while idx >= 0
        k = d.keys[idx]
        if js_truthy(js_call_arr(has, other, [k]))
          js_map_put(out, k, k) if !js_map_has(out, k)
        idx = js_set_next_live_idx(d, idx + 1)
    else
      it = js_set_keys_iter(other, keys)
      while true
        k = js_iter_step(it)
        break if k == JS_ITER_DONE
        k = js_set_canon(k)
        js_map_put(out, k, k) if js_map_has(d, k) && !js_map_has(out, k)
    return js_set_from_data(out)
  if op == :difference
    out = js_set_copy_data(d)
    if this_size <= osize
      idx = js_set_next_live_idx(out, 0)
      while idx >= 0
        k = out.keys[idx]
        js_map_remove(out, k) if js_truthy(js_call_arr(has, other, [k]))
        idx = js_set_next_live_idx(out, idx + 1)
    else
      it = js_set_keys_iter(other, keys)
      while true
        k = js_iter_step(it)
        break if k == JS_ITER_DONE
        js_map_remove(out, js_set_canon(k))
    return js_set_from_data(out)
  if op == :symmetric
    it = js_set_keys_iter(other, keys)
    out = js_set_copy_data(d)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      k = js_set_canon(k)
      if js_map_has(d, k)
        js_map_remove(out, k)
      elsif !js_map_has(out, k)
        js_map_put(out, k, k)
    return js_set_from_data(out)
  if op == :subset
    return false if this_size > osize
    idx = js_set_next_live_idx(d, 0)
    while idx >= 0
      return false if !js_truthy(js_call_arr(has, other, [d.keys[idx]]))
      idx = js_set_next_live_idx(d, idx + 1)
    return true
  if op == :superset
    return false if this_size < osize
    it = js_set_keys_iter(other, keys)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      if !js_map_has(d, k)
        js_iter_close(it)
        return false
    return true
  # :disjoint
  if this_size <= osize
    idx = js_set_next_live_idx(d, 0)
    while idx >= 0
      return false if js_truthy(js_call_arr(has, other, [d.keys[idx]]))
      idx = js_set_next_live_idx(d, idx + 1)
  else
    it = js_set_keys_iter(other, keys)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      if js_map_has(d, k)
        js_iter_close(it)
        return false
  true

-> js_set_from_data(data)
  s = js_set_new_empty()
  s.internal = data
  s

-> js_set_new_empty
  js_coll_new(js_realm().intrinsic("Set.prototype"), "Set")

js_install(->(r) js_install_collections(r))

-> js_install_collections(r)
  op = r.object_proto
  ip = r.intrinsics["%IteratorPrototype%"]
  ip = op if ip == nil
  # Map
  mp = js_new_object(op)
  mc = r.constructor("Map", 0, ->(this, args, nt) js_coll_ctor("Map", args, nt, "set", true), mp)
  mg = r.method(mp, "get", 1, ->(this, args, nt) js_map_get(js_this_map(this, "Map"), js_arg(args, 0)))
  r.set_intrinsic("%Map_get%", mg)
  ms = r.method(mp, "set", 2, ->(this, args, nt) js_map_set_m(this, "Map", js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%Map_set%", ms)
  mh = r.method(mp, "has", 1, ->(this, args, nt) js_map_has(js_this_map(this, "Map"), js_arg(args, 0)))
  r.set_intrinsic("%Map_has%", mh)
  r.method(mp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "Map"), js_arg(args, 0)))
  r.method(mp, "clear", 0, ->(this, args, nt) js_map_clear(js_this_map(this, "Map")))
  r.method(mp, "getOrInsert", 2, ->(this, args, nt) js_map_get_or_insert(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(mp, "getOrInsertComputed", 2, ->(this, args, nt) js_map_get_or_insert_computed(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(mp, "forEach", 1, ->(this, args, nt) js_coll_for_each(this, "Map", js_arg(args, 0), js_arg(args, 1)))
  r.getter(mp, "size", ->(this, args, nt) js_this_map(this, "Map").size + ~0.0)
  r.method(mp, "keys", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :keys))
  r.method(mp, "values", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :values))
  me = r.method(mp, "entries", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :entries))
  mp.define(SYM_ITERATOR, me, BUILTIN_ATTRS)
  mp.define(SYM_TO_STRING_TAG, "Map", ATTR_C)
  r.method(mc, "groupBy", 2, ->(this, args, nt) js_object_group_by(js_arg(args, 0), js_arg(args, 1), true))
  r.getter(mc, SYM_SPECIES, ->(this, args, nt) this)
  mip = js_new_object(ip)
  r.set_intrinsic("%MapIteratorPrototype%", mip)
  r.method(mip, "next", 0, ->(this, args, nt) js_map_iter_next(this, "Map Iterator"))
  mip.define(SYM_TO_STRING_TAG, "Map Iterator", ATTR_C)
  # Set
  sp = js_new_object(op)
  sc = r.constructor("Set", 0, ->(this, args, nt) js_coll_ctor("Set", args, nt, "add", false), sp)
  sa = r.method(sp, "add", 1, ->(this, args, nt) js_map_set_m(this, "Set", js_arg(args, 0), js_arg(args, 0)))
  r.set_intrinsic("%Set_add%", sa)
  sh = r.method(sp, "has", 1, ->(this, args, nt) js_map_has(js_this_map(this, "Set"), js_arg(args, 0)))
  r.set_intrinsic("%Set_has%", sh)
  r.method(sp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "Set"), js_arg(args, 0)))
  r.method(sp, "clear", 0, ->(this, args, nt) js_map_clear(js_this_map(this, "Set")))
  r.method(sp, "forEach", 1, ->(this, args, nt) js_coll_for_each(this, "Set", js_arg(args, 0), js_arg(args, 1)))
  r.getter(sp, "size", ->(this, args, nt) js_this_map(this, "Set").size + ~0.0)
  r.method(sp, "entries", 0, ->(this, args, nt) js_map_iter_checked(this, "Set", :entries))
  sv = r.method(sp, "values", 0, ->(this, args, nt) js_map_iter_checked(this, "Set", :keys))
  sp.define("keys", sv, BUILTIN_ATTRS)
  sp.define(SYM_ITERATOR, sv, BUILTIN_ATTRS)
  sp.define(SYM_TO_STRING_TAG, "Set", ATTR_C)
  r.method(sp, "union", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :union))
  r.method(sp, "intersection", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :intersection))
  r.method(sp, "difference", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :difference))
  r.method(sp, "symmetricDifference", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :symmetric))
  r.method(sp, "isSubsetOf", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :subset))
  r.method(sp, "isSupersetOf", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :superset))
  r.method(sp, "isDisjointFrom", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :disjoint))
  r.getter(sc, SYM_SPECIES, ->(this, args, nt) this)
  sip = js_new_object(ip)
  r.set_intrinsic("%SetIteratorPrototype%", sip)
  r.method(sip, "next", 0, ->(this, args, nt) js_map_iter_next(this, "Set Iterator"))
  sip.define(SYM_TO_STRING_TAG, "Set Iterator", ATTR_C)
  # WeakMap / WeakSet
  wmp = js_new_object(op)
  r.constructor("WeakMap", 0, ->(this, args, nt) js_coll_ctor("WeakMap", args, nt, "set", true), wmp)
  r.method(wmp, "get", 1, ->(this, args, nt) js_map_get(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  wms = r.method(wmp, "set", 2, ->(this, args, nt) js_weak_set(this, "WeakMap", js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%WeakMap_set%", wms)
  r.method(wmp, "has", 1, ->(this, args, nt) js_map_has(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  r.method(wmp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  r.method(wmp, "getOrInsert", 2, ->(this, args, nt) js_weak_get_or_insert(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(wmp, "getOrInsertComputed", 2, ->(this, args, nt) js_weak_get_or_insert_computed(this, js_arg(args, 0), js_arg(args, 1)))
  wmp.define(SYM_TO_STRING_TAG, "WeakMap", ATTR_C)
  wsp = js_new_object(op)
  r.constructor("WeakSet", 0, ->(this, args, nt) js_coll_ctor("WeakSet", args, nt, "add", false), wsp)
  wsa = r.method(wsp, "add", 1, ->(this, args, nt) js_weak_set(this, "WeakSet", js_arg(args, 0), js_arg(args, 0)))
  r.set_intrinsic("%WeakSet_add%", wsa)
  r.method(wsp, "has", 1, ->(this, args, nt) js_map_has(js_this_map(this, "WeakSet"), js_arg(args, 0)))
  r.method(wsp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakSet"), js_arg(args, 0)))
  wsp.define(SYM_TO_STRING_TAG, "WeakSet", ATTR_C)
  # WeakRef / FinalizationRegistry
  wrp = js_new_object(op)
  r.constructor("WeakRef", 1, ->(this, args, nt) js_weakref_ctor(args, nt), wrp)
  r.method(wrp, "deref", 0, ->(this, args, nt) js_special?(this, "WeakRef") ? this.internal : js_throw_type("WeakRef.prototype.deref called on incompatible receiver"))
  wrp.define(SYM_TO_STRING_TAG, "WeakRef", ATTR_C)
  frp = js_new_object(op)
  r.constructor("FinalizationRegistry", 1, ->(this, args, nt) js_fin_reg_ctor(args, nt), frp)
  r.method(frp, "register", 2, ->(this, args, nt) js_fin_reg_check(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(frp, "unregister", 1, ->(this, args, nt) js_fin_reg_unregister(this, js_arg(args, 0)))
  r.method(frp, "cleanupSome", 0, ->(this, args, nt) nil)
  frp.define(SYM_TO_STRING_TAG, "FinalizationRegistry", ATTR_C)
  nil

-> js_map_set_m(m, cls, k, v)
  js_map_put(js_this_map(m, cls), k, v)
  m

-> js_weak_set(m, cls, k, v)
  d = js_this_map(m, cls)
  js_weak_check(k, cls)
  js_map_put(d, k, v)
  m

-> js_map_get_or_insert(m, k, v)
  d = js_this_map(m, "Map")
  k = ~0.0 if js_number?(k) && k == ~0.0
  ei = js_map_find_idx(d, k)
  return d.vals[ei] if ei >= 0
  js_map_put(d, k, v)
  v

-> js_map_get_or_insert_computed(m, k, cb)
  d = js_this_map(m, "Map")
  js_throw_type(js_err_display(cb) + " is not a function") if !js_callable?(cb)
  k = ~0.0 if js_number?(k) && k == ~0.0
  ei = js_map_find_idx(d, k)
  return d.vals[ei] if ei >= 0
  v = js_call_arr(cb, nil, [k])
  js_map_put(d, k, v)
  v

-> js_weak_get_or_insert(m, k, v)
  d = js_this_map(m, "WeakMap")
  js_weak_check(k, "WeakMap")
  ei = js_map_find_idx(d, k)
  return d.vals[ei] if ei >= 0
  js_map_put(d, k, v)
  v

-> js_weak_get_or_insert_computed(m, k, cb)
  d = js_this_map(m, "WeakMap")
  js_weak_check(k, "WeakMap")
  js_throw_type(js_err_display(cb) + " is not a function") if !js_callable?(cb)
  ei = js_map_find_idx(d, k)
  return d.vals[ei] if ei >= 0
  v = js_call_arr(cb, nil, [k])
  js_map_put(d, k, v)
  v

-> js_map_iter_checked(m, cls, kind)
  js_this_map(m, cls)
  js_map_iter(m, kind, cls == "Map" ? "%MapIteratorPrototype%" : "%SetIteratorPrototype%")

-> js_weakref_ctor(args, nt)
  js_throw_type("Constructor WeakRef requires 'new'") if nt == nil
  t = js_arg(args, 0)
  js_throw_type("WeakRef: target must be an object") if !(js_object?(t) || (t.is_a?(JS:Symbol) && !js_registered_symbol?(t)))
  w = js_new_special(js_realm().proto_from(nt, "WeakRef"), "WeakRef")
  w.internal = t
  js_gc_reg_weakref(w)

-> js_fin_reg_ctor(args, nt)
  js_throw_type("Constructor FinalizationRegistry requires 'new'") if nt == nil
  f = js_arg(args, 0)
  js_throw_type("FinalizationRegistry: cleanup must be callable") if !js_callable?(f)
  o = js_new_special(js_realm().proto_from(nt, "FinalizationRegistry"), "FinalizationRegistry")
  o.internal = f
  o.s0 = []
  js_gc_reg_finreg(o)

-> js_fin_reg_this(v)
  js_throw_type("FinalizationRegistry method called on incompatible receiver") if !js_special?(v, "FinalizationRegistry")
  v

-> js_can_be_held_weakly?(v)
  js_object?(v) || (v.is_a?(JS:Symbol) && !js_registered_symbol?(v))

-> js_fin_reg_check(this, target, held, token = nil)
  js_fin_reg_this(this)
  js_throw_type("FinalizationRegistry.prototype.register: invalid target") if !js_can_be_held_weakly?(target)
  js_throw_type("FinalizationRegistry.prototype.register: target and holdings must not be same") if js_same_value(target, held)
  if token != nil && !js_can_be_held_weakly?(token)
    js_throw_type("FinalizationRegistry.prototype.register: invalid unregisterToken")
  recs = this.s0
  if !recs.is_a?(Array)
    recs = []
    this.s0 = recs
  recs.push([target, held, token])
  nil

-> js_fin_reg_unregister(this, token)
  js_fin_reg_this(this)
  js_throw_type("Invalid unregisterToken ('" + js_err_display(token) + "')") if !js_can_be_held_weakly?(token)
  recs = this.s0
  return false if !recs.is_a?(Array) || recs.size == 0
  removed = false
  out = []
  i = 0
  while i < recs.size
    if recs[i][2] != nil && js_same_value(recs[i][2], token)
      removed = true
    else
      out.push(recs[i])
    i += 1
  this.s0 = out if removed
  removed
