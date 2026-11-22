# wasm/atomic — threads proposal: atomic loads, stores, read-modify-write and cmpxchg
# (LLVM IR atomics, sequentially consistent, on the memory's bytes in place) and
# memory.atomic.wait / notify.
#
# A shared memory is allocated at its maximum size up front, so its bytes never move and
# other threads can keep using them while it grows (WMemory.grow only moves the bound).

fn wa_load_i8(m, ea) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %o = load atomic i8, ptr %q seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_store_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    store atomic i8 %t, ptr %q seq_cst, align 1
    ret i64 0
  IR

fn wa_add_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw add ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_sub_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw sub ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_and_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw and ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_or_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw or ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_xor_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw xor ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_xchg_i8(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i8
    %o = atomicrmw xchg ptr %q, i8 %t seq_cst, align 1
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_cmpxchg_i8(m, ea, e, v) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %te = trunc i64 %e to i8
    %tr = trunc i64 %v to i8
    %p = cmpxchg ptr %q, i8 %te, i8 %tr seq_cst seq_cst, align 1
    %o = extractvalue { i8, i1 } %p, 0
    %r = zext i8 %o to i64
    ret i64 %r
  IR

fn wa_load_i16(m, ea) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %o = load atomic i16, ptr %q seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_store_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    store atomic i16 %t, ptr %q seq_cst, align 2
    ret i64 0
  IR

fn wa_add_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw add ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_sub_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw sub ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_and_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw and ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_or_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw or ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_xor_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw xor ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_xchg_i16(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i16
    %o = atomicrmw xchg ptr %q, i16 %t seq_cst, align 2
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_cmpxchg_i16(m, ea, e, v) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %te = trunc i64 %e to i16
    %tr = trunc i64 %v to i16
    %p = cmpxchg ptr %q, i16 %te, i16 %tr seq_cst seq_cst, align 2
    %o = extractvalue { i16, i1 } %p, 0
    %r = zext i16 %o to i64
    ret i64 %r
  IR

fn wa_load_i32(m, ea) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %o = load atomic i32, ptr %q seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_store_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    store atomic i32 %t, ptr %q seq_cst, align 4
    ret i64 0
  IR

fn wa_add_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw add ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_sub_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw sub ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_and_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw and ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_or_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw or ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_xor_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw xor ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_xchg_i32(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = trunc i64 %v to i32
    %o = atomicrmw xchg ptr %q, i32 %t seq_cst, align 4
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_cmpxchg_i32(m, ea, e, v) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %te = trunc i64 %e to i32
    %tr = trunc i64 %v to i32
    %p = cmpxchg ptr %q, i32 %te, i32 %tr seq_cst seq_cst, align 4
    %o = extractvalue { i32, i1 } %p, 0
    %r = zext i32 %o to i64
    ret i64 %r
  IR

fn wa_load_i64(m, ea) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %o = load atomic i64, ptr %q seq_cst, align 8
    ret i64 %o
  IR

fn wa_store_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    store atomic i64 %t, ptr %q seq_cst, align 8
    ret i64 0
  IR

fn wa_add_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw add ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_sub_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw sub ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_and_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw and ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_or_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw or ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_xor_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw xor ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_xchg_i64(m, ea, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %t = add i64 %v, 0
    %o = atomicrmw xchg ptr %q, i64 %t seq_cst, align 8
    ret i64 %o
  IR

fn wa_cmpxchg_i64(m, ea, e, v) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %te = add i64 %e, 0
    %tr = add i64 %v, 0
    %p = cmpxchg ptr %q, i64 %te, i64 %tr seq_cst seq_cst, align 8
    %o = extractvalue { i64, i1 } %p, 0
    ret i64 %o
  IR

# Waiters: key "memory id:address" → cells [notified]. One lock for all.
W_WAIT = [nil, {}]

-> w_wait_lock
  W_WAIT[0] = Mutex.new if W_WAIT[0] == nil
  W_WAIT[0]

# The value (zero-extended for narrow ops) an atomic op returns; dispatch by sub-opcode.
-> w_ext_atomic(ex, inst, sub, code, o, fp)
  mem = inst.mems[code[o]]
  stk = ex.stk
  data = mem.data
  if sub == 0
    ea = w_ea(ex, mem, stk[fp + code[o + 2]], code[o + 4], 4)
    w_trap_code(20) if (ea & 3) != 0
    n = stk[fp + code[o + 3]]
    stk[fp + code[o + 1]] = w_notify(mem, ea, n)
    return nil
  if sub == 1 || sub == 2
    sz = sub == 1 ? 4 : 8
    ea = w_ea(ex, mem, stk[fp + code[o + 2]], code[o + 5], sz)
    w_trap_code(20) if (ea & (sz - 1)) != 0
    w_trap_code(21) if !mem.shared
    exp = stk[fp + code[o + 3]]
    to = stk[fp + code[o + 4]]
    stk[fp + code[o + 1]] = w_wait(mem, ea, sz, exp, to)
    return nil
  j = (sub - 0x10) % 7
  sz = [4, 8, 1, 2, 1, 2, 4][j]
  if sub <= 0x16
    ea = w_ea(ex, mem, stk[fp + code[o + 2]], code[o + 3], sz)
    w_trap_code(20) if (ea & (sz - 1)) != 0
    stk[fp + code[o + 1]] = wa_load(data, ea, sz)
  elsif sub <= 0x1d
    ea = w_ea(ex, mem, stk[fp + code[o + 1]], code[o + 3], sz)
    w_trap_code(20) if (ea & (sz - 1)) != 0
    wa_store(data, ea, sz, stk[fp + code[o + 2]])
  elsif sub <= 0x47
    ea = w_ea(ex, mem, stk[fp + code[o + 2]], code[o + 4], sz)
    w_trap_code(20) if (ea & (sz - 1)) != 0
    op = (sub - 0x1e) / 7
    stk[fp + code[o + 1]] = wa_rmw(data, ea, sz, op, stk[fp + code[o + 3]])
  else
    ea = w_ea(ex, mem, stk[fp + code[o + 2]], code[o + 5], sz)
    w_trap_code(20) if (ea & (sz - 1)) != 0
    e = stk[fp + code[o + 3]]
    v = stk[fp + code[o + 4]]
    # compare only the access width
    e = e & ((1 << (8 * sz)) - 1) if sz < 8
    stk[fp + code[o + 1]] = wa_cas(data, ea, sz, e, v)
  nil

-> wa_load(d, ea, sz)
  return wa_load_i32(d, ea) if sz == 4
  return wa_load_i64(d, ea) if sz == 8
  return wa_load_i8(d, ea) if sz == 1
  wa_load_i16(d, ea)

-> wa_store(d, ea, sz, v)
  if sz == 4
    wa_store_i32(d, ea, v)
  elsif sz == 8
    wa_store_i64(d, ea, v)
  elsif sz == 1
    wa_store_i8(d, ea, v)
  else
    wa_store_i16(d, ea, v)
  nil

# op: 0 add 1 sub 2 and 3 or 4 xor 5 xchg
-> wa_rmw(d, ea, sz, op, v)
  if sz == 4
    return wa_add_i32(d, ea, v) if op == 0
    return wa_sub_i32(d, ea, v) if op == 1
    return wa_and_i32(d, ea, v) if op == 2
    return wa_or_i32(d, ea, v) if op == 3
    return wa_xor_i32(d, ea, v) if op == 4
    return wa_xchg_i32(d, ea, v)
  if sz == 8
    return wa_add_i64(d, ea, v) if op == 0
    return wa_sub_i64(d, ea, v) if op == 1
    return wa_and_i64(d, ea, v) if op == 2
    return wa_or_i64(d, ea, v) if op == 3
    return wa_xor_i64(d, ea, v) if op == 4
    return wa_xchg_i64(d, ea, v)
  if sz == 1
    return wa_add_i8(d, ea, v) if op == 0
    return wa_sub_i8(d, ea, v) if op == 1
    return wa_and_i8(d, ea, v) if op == 2
    return wa_or_i8(d, ea, v) if op == 3
    return wa_xor_i8(d, ea, v) if op == 4
    return wa_xchg_i8(d, ea, v)
  return wa_add_i16(d, ea, v) if op == 0
  return wa_sub_i16(d, ea, v) if op == 1
  return wa_and_i16(d, ea, v) if op == 2
  return wa_or_i16(d, ea, v) if op == 3
  return wa_xor_i16(d, ea, v) if op == 4
  wa_xchg_i16(d, ea, v)

-> wa_cas(d, ea, sz, e, v)
  return wa_cmpxchg_i32(d, ea, e, v) if sz == 4
  return wa_cmpxchg_i64(d, ea, e, v) if sz == 8
  return wa_cmpxchg_i8(d, ea, e, v) if sz == 1
  wa_cmpxchg_i16(d, ea, e, v)

-> w_wait_key(mem, ea)
  mem.uid.to_s + ":" + ea.to_s

# memory.atomic.wait: 0 woken, 1 value differed, 2 timed out (timeout in ns, < 0 forever).
-> w_wait(mem, ea, sz, exp, timeout)
  lk = w_wait_lock()
  lk.lock
  cur = sz == 4 ? wa_load_i32(mem.data, ea) : wa_load_i64(mem.data, ea)
  if (sz == 4 && cur != (exp & 0xffffffff)) || (sz == 8 && cur != exp)
    lk.unlock
    return 1
  if timeout == 0
    lk.unlock
    return 2
  key = w_wait_key(mem, ea)
  cell = [false]
  q = W_WAIT[1][key]
  if q == nil
    q = []
    W_WAIT[1][key] = q
  q.push(cell)
  lk.unlock
  t0 = clock_ms()
  while !cell[0]
    if timeout > 0 && (clock_ms() - t0) * 1000000 >= timeout
      lk.lock
      woke = cell[0]
      W_WAIT[1][key] = W_WAIT[1][key].reject ->(c) c == cell
      lk.unlock
      return woke ? 0 : 2
    sleep(~0.0001)
  0

-> w_notify(mem, ea, n)
  lk = w_wait_lock()
  lk.lock
  key = w_wait_key(mem, ea)
  q = W_WAIT[1][key]
  woken = 0
  if q != nil
    while q.size > 0 && woken < n
      c = q.shift
      c[0] = true
      woken += 1
  lk.unlock
  woken
