# wasm/runtime — the store, run-time objects, instantiation and the interpreter driver.
#
#   store = wasm_store()                       # the process-wide store
#   inst = wasm_instantiate(m, resolver)       # resolver: ->(module, name) extern value or nil
#   results = wasm_call(f, args)               # f: WFunc; args/results: raw values (below)
#
# Raw values at the host boundary: i32 → Int (0 ≤ v < 2^32), i64 → Int (signed), f32/f64 →
# their IEEE bits as Int, v128 → WV128, references → nil (null), WFunc, WStruct, WArray,
# Int (i31ref), WExtern (a host value), WExn.

+ WV128
  rw :lo, :hi
  -> new(@lo, @hi)

# A host (embedder) value travelling as externref / anyref.
+ WExtern
  rw :v
  -> new(@v)

+ WFunc
  rw :fid, :type, :inst, :index, :host, :name, :jit
  -> new(@type, @inst, @index, @host)
    @fid = 0
    @name = nil
    @jit = nil

  -> sig
    W_TYPES.types[@type]

+ WTable
  rw :elems, :fids, :type, :max, :is64

  -> new(@type, n, @max, @is64, init)
    @elems = []
    k = 0
    while k < n
      @elems.push(init)
      k += 1
    @fids = nil
    if wt_heap_sub?(wt_ht(@type), HT_FUNC) || wt_ht(@type) == HT_FUNC
      @fids = i64[n + 1]
      if init != nil
        k = 0
        while k < n
          @fids[k] = init.fid
          k += 1

  -> size
    @elems.size

  -> get(i)
    @elems[i]

  -> set(i, v)
    @elems[i] = v
    if @fids != nil
      @fids[i] = v == nil ? 0 : v.fid
    nil

  # Grow by n with init; returns the old size or -1.
  -> grow(n, init)
    old = @elems.size
    nw = old + n
    lim = @is64 ? 1048576 * 64 : 4294967295
    lim = @max if @max != nil && w_ult_eq?(@max, lim)
    return -1 if n < 0 || nw > lim || nw > 10000000
    k = 0
    while k < n
      @elems.push(init)
      k += 1
    if @fids != nil
      nf = i64[nw + 1]
      k = 0
      while k < nw
        e = @elems[k]
        nf[k] = e == nil ? 0 : e.fid
        k += 1
      @fids = nf
    old

-> w_ult_eq?(a, b)
  a <= b

+ WMemory
  rw :data, :size, :max, :shared, :is64, :page_log2, :on_grow, :buffer, :lock

  -> new(pages, @max, @shared, @is64, @page_log2)
    @size = pages << @page_log2
    @on_grow = nil
    @buffer = nil
    @lock = nil
    cap = @size
    if @shared && @max != nil
      cap = @max << @page_log2
      cap = 4294967296 if cap > 4294967296
    @data = ByteArray.new(cap == 0 ? 1 : cap)

  -> pages
    @size >> @page_log2

  -> limit_pages
    lim = @is64 ? 65536 : 65536
    lim = 4294967296 if @page_log2 == 0 && !@is64
    lim = @max if @max != nil && @max < lim
    lim

  # memory.grow: the old size in pages, or -1.
  -> grow(n)
    old = pages()
    return old if n == 0
    return -1 if n < 0
    nw = old + n
    return -1 if nw > limit_pages()
    nbytes = nw << @page_log2
    if @shared
      return -1 if nbytes > @data.size
      @size = nbytes
    else
      nd = ByteArray.new(nbytes)
      wk_memcpy2(nd, 0, @data, 0, @size) if @size > 0
      @data = nd
      @size = nbytes
    @on_grow.call(self) if @on_grow != nil
    old

+ WGlobal
  rw :type, :mutable, :nums, :refs, :at

  -> new(@type, @mutable)
    @nums = i64[2]
    @refs = [nil]
    @at = 0

  -> get
    return @refs[@at] if wt_ref?(@type)
    return WV128.new(@nums[@at * 2], @nums[@at * 2 + 1]) if @type == V128
    @nums[@at * 2]

  -> set(v)
    if wt_ref?(@type)
      @refs[@at] = v
    elsif @type == V128
      @nums[@at * 2] = v.lo
      @nums[@at * 2 + 1] = v.hi
    else
      @nums[@at * 2] = v
    nil

+ WTag
  rw :type
  -> new(@type)

  -> sig
    W_TYPES.types[@type]

# A thrown exception: its tag and payload (raw values).
+ WExn
  rw :tag, :vals
  -> new(@tag, @vals)

# GC objects.
+ WStruct
  rw :type, :nums, :refs
  -> new(@type, n)
    @nums = i64[n * 2 + 1]
    @refs = []
    k = 0
    while k < n
      @refs.push(nil)
      k += 1

+ WArray
  rw :type, :len, :nums, :refs, :wide
  -> new(@type, @len, is_ref, @wide)
    @nums = nil
    @refs = nil
    if is_ref
      @refs = []
      k = 0
      while k < @len
        @refs.push(nil)
        k += 1
    else
      @nums = i64[(@wide ? @len * 2 : @len) + 1]

+ WInstance
  rw :id, :mod, :funcs, :tables, :mems, :globals, :glob, :gref, :gimports, :tags, :elems, :datas, :exports, :export_list, :dropped_data

  -> new(@id, @mod)
    @funcs = []
    @tables = []
    @mems = []
    @globals = []
    @tags = []
    @elems = []
    @datas = []
    @exports = {}
    @export_list = []
    @gimports = {}
    @dropped_data = []

  -> export(name)
    @exports[name]

# The process-wide store: every function has an id and four words of info in sx.
+ WStore
  rw :funcs, :sx, :ninst, :instances

  -> new
    @funcs = [nil]
    @sx = i64[1024]
    @ninst = 0
    @instances = [nil]

  -> add_func(f)
    f.fid = @funcs.size
    @funcs.push(f)
    need = (f.fid + 1) * 4
    if need > @sx.size
      ns = i64[@sx.size * 2 + need]
      k = 0
      while k < @sx.size
        ns[k] = @sx[k]
        k += 1
      @sx = ns
    b = f.fid * 4
    if f.inst != nil
      m = f.inst.mod
      @sx[b] = m.fentry[f.index - m.n_imp_funcs].entry
      @sx[b + 1] = f.inst.id
      @sx[b + 3] = f.index
    else
      @sx[b] = -1
      @sx[b + 1] = 0
      @sx[b + 3] = -1
    @sx[b + 2] = f.type
    f

W_STORE = [nil]

-> wasm_store
  W_STORE[0] = WStore.new if W_STORE[0] == nil
  W_STORE[0]

# A host function of canonical type t: proc ->(args) returns a raw value, an Array of raw
# values (multi-value), or nil (no results).
-> wasm_host_func(t, proc)
  wasm_store().add_func(WFunc.new(t, nil, -1, proc))

# ---- execution context (one per thread) ----

W_STACK_SLOTS = 1048576
W_CSTACK = 120000

+ WExec
  rw :stk, :ostk, :cstk, :st, :top, :csp, :depth

  -> new
    @stk = i64[W_STACK_SLOTS + 64]
    @ostk = []
    k = 0
    while k < W_STACK_SLOTS + 64
      @ostk.push(nil)
      k += 1
    @cstk = i64[W_CSTACK + 8]
    @st = i64[16]
    @top = 0
    @csp = 0
    @depth = 0

W_EXEC = [nil]

-> wasm_exec
  W_EXEC[0] = WExec.new if W_EXEC[0] == nil
  W_EXEC[0]

W_TRAP_MSGS = ["", "unreachable", "integer divide by zero", "integer overflow", "invalid conversion to integer", "out of bounds memory access", "undefined element", "uninitialized element", "indirect call type mismatch", "call stack exhausted", "null reference", "out of bounds table access", "cast failure", "out of bounds array access", "null function reference", "null structure reference", "null array reference", "null i31 reference", "null exception reference", "data segment out of bounds", "misaligned memory access", "expected shared memory"]

-> w_trap_code(code)
  msg = code < W_TRAP_MSGS.size ? W_TRAP_MSGS[code] : "trap " + code.to_s
  raise WasmTrap.new(msg)

-> w_ref_eq?(a, b)
  a == b

# ---- reading / writing slots ----

-> w_slot_read(ex, t, s)
  return ex.ostk[s] if wt_ref?(t)
  return WV128.new(ex.stk[s], ex.stk[s + 1]) if t == V128
  ex.stk[s]

-> w_slot_write(ex, t, s, v)
  if wt_ref?(t)
    ex.ostk[s] = v
  elsif t == V128
    ex.stk[s] = v.lo
    ex.stk[s + 1] = v.hi
  else
    ex.stk[s] = v
  nil

-> w_write_values(ex, types, base, vals)
  s = base
  k = 0
  while k < types.size
    w_slot_write(ex, types[k], s, vals[k])
    s += wt_slots(types[k])
    k += 1
  nil

-> w_read_values(ex, types, base)
  out = []
  s = base
  k = 0
  while k < types.size
    out.push(w_slot_read(ex, types[k], s))
    s += wt_slots(types[k])
    k += 1
  out

# Call any function with raw args; returns an Array of raw results.
-> wasm_call(f, args)
  ex = wasm_exec()
  ft = f.sig
  w_trap_raise_arity(ft, args)
  base = ex.top
  w_write_values(ex, ft.params, base, args)
  w_call_at(ex, f, base, base + w_max(ft.param_slots, ft.result_slots) + 2)
  w_read_values(ex, ft.results, base)

-> w_trap_raise_arity(ft, args)
  raise ArgumentError, "wasm: wrong number of arguments" if args.size != ft.params.size
  nil

-> w_max(a, b)
  a > b ? a : b

# Call f with its arguments already at slots base.. (results replace them).
# top: the first free slot above the caller's frame.
-> w_call_at(ex, f, base, top)
  if f.host != nil
    ft = f.sig
    args = w_read_values(ex, ft.params, base)
    saved = ex.top
    ex.top = top
    ex.depth += 1
    begin
      raise WasmExhaustion.new("call stack exhausted") if ex.depth > 900
      r = f.host.call(args)
    ensure
      ex.depth -= 1
      ex.top = saved
    if ft.results.size == 1
      r = [r] if !r.is_a?(Array) || wt_ref?(ft.results[0])
      w_slot_write(ex, ft.results[0], base, r[0])
    elsif ft.results.size > 1
      w_write_values(ex, ft.results, base, r)
    return nil
  inst = f.inst
  m = inst.mod
  meta = m.fentry[f.index - m.n_imp_funcs]
  w_run(ex, inst, meta.entry, base, top)
  nil

# Run code from entry with the frame at base until it returns.
-> w_run(ex, inst, entry, base, top)
  m = inst.mod
  st = ex.st
  saved_top = ex.top
  csp0 = ex.csp
  raise WasmExhaustion.new("call stack exhausted") if csp0 + 4 >= W_CSTACK || ex.depth > 900
  cstk = ex.cstk
  cstk[csp0] = -1
  cstk[csp0 + 1] = base
  pc = entry
  fp = base
  csp = csp0 + 2
  store = wasm_store()
  ex.depth += 1
  begin
    while true
      mem = inst.mems.size > 0 ? inst.mems[0] : nil
      st[0] = pc
      st[1] = fp
      st[2] = csp
      st[3] = mem == nil ? 0 : mem.size
      st[5] = inst.id
      st[6] = W_STACK_SLOTS
      st[7] = W_CSTACK
      t0 = inst.tables.size > 0 ? inst.tables[0] : nil
      st[9] = (t0 == nil || t0.fids == nil) ? 0 : t0.size
      r = wexec(m.code, ex.stk, ex.ostk, mem == nil ? W_NOMEM : mem.data, inst.glob, inst.gref, (t0 == nil || t0.fids == nil) ? W_NOTAB : t0.fids, store.sx, cstk, st)
      pc = st[0]
      fp = st[1]
      csp = st[2]
      if r == 0
        break
      elsif r == 1
        w_trap_code(st[4])
      elsif r == 6
        raise WasmExhaustion.new("call stack exhausted")
      else
        ex.csp = csp
        res = w_slow(ex, inst, r, pc, fp, csp)
        pc = res[0]
        fp = res[1]
        csp = res[2]
        break if pc < 0
  ensure
    ex.depth -= 1
    ex.csp = csp0
    ex.top = saved_top
  nil

W_NOMEM = ByteArray.new(1)
W_NOTAB = i64[1]

# The slow path: returns [pc, fp, csp] to resume at (pc < 0: the activation returned).
-> w_slow(ex, inst, r, pc, fp, csp)
  code = inst.mod.code
  begin
    if r == 2
      return w_ext(ex, inst, pc, fp, csp)
    elsif r == 3
      fi = code[pc + 1]
      base = code[pc + 2]
      fsz = code[pc + 3]
      w_call_at(ex, inst.funcs[fi], fp + base, fp + fsz)
      return [pc + 4, fp, csp]
    elsif r == 4
      ti = code[pc + 1]
      canon = code[pc + 2]
      base = code[pc + 3]
      a = code[pc + 4]
      fsz = code[pc + 5]
      f = w_table_func(inst, ti, ex.stk[fp + a], canon)
      return w_do_call(ex, inst, f, pc, pc + 6, fp, csp, base, fsz)
    elsif r == 5
      canon = code[pc + 1]
      base = code[pc + 2]
      a = code[pc + 3]
      fsz = code[pc + 4]
      f = ex.ostk[fp + a]
      w_trap_code(14) if f == nil
      return w_do_call(ex, inst, f, pc, pc + 5, fp, csp, base, fsz)
  rescue e
    if e.is_a?(WasmException)
      return w_unwind(ex, inst, e.exn, pc, fp, csp)
    raise e
  w_trap_code(99)
  [pc, fp, csp]

# Call f from the instruction at pc (resuming at next); same-instance wasm functions are
# entered in place (a new frame on the control stack).
-> w_do_call(ex, inst, f, pc, nxt, fp, csp, base, fsz)
  if f.inst == inst && f.host == nil
    raise WasmExhaustion.new("call stack exhausted") if csp + 2 >= W_CSTACK
    ex.cstk[csp] = nxt
    ex.cstk[csp + 1] = fp
    m = inst.mod
    return [m.fentry[f.index - m.n_imp_funcs].entry, fp + base, csp + 2]
  w_call_at(ex, f, fp + base, fp + fsz)
  [nxt, fp, csp]

# The function at table[ti][idx] checked against canonical type canon.
-> w_table_func(inst, ti, idx, canon)
  t = inst.tables[ti]
  w_trap_code(6) if idx < 0 || idx >= t.size
  f = t.elems[idx]
  w_trap_code(7) if f == nil
  w_trap_code(8) if !W_TYPES.sub?(f.type, canon)
  f

# Return from the current frame (after a tail call to another instance / host).
-> w_ret(ex, fp, csp)
  csp -= 2
  [ex.cstk[csp], ex.cstk[csp + 1], csp]

# ---- exceptions ----

# The compiled function containing code address pc.
-> w_func_at(m, pc)
  lo = 0
  hi = m.fentry.size - 1
  while lo < hi
    mid = (lo + hi + 1) / 2
    if m.fentry[mid].entry <= pc
      lo = mid
    else
      hi = mid - 1
  m.fentry[lo]

-> w_tag_matches?(inst, tagidx, exn)
  inst.tags[tagidx] == exn.tag

# Unwind from pc/fp looking for a handler; raises WasmException when none in this activation.
-> w_unwind(ex, inst, exn, pc, fp, csp)
  m = inst.mod
  csp0 = ex.csp
  while true
    meta = w_func_at(m, pc)
    depth_limit = 1000000
    hs = meta.handlers
    k = 0
    while k < hs.size
      h = hs[k]
      if pc >= h.start && pc < h.stop && h.depth < depth_limit
        kind = h.kind
        if kind == 6
          depth_limit = h.tag + 1
        else
          ok = kind == 2 || kind == 3 || kind == 5 || (exn.tag != nil && w_tag_matches?(inst, h.tag, exn))
          if ok
            s = fp + h.slot
            if kind == 0 || kind == 1 || kind == 4
              tt = exn.tag.sig
              w_write_values(ex, tt.params, s, exn.vals)
              tt.params.each ->(t) s += wt_slots(t)
            if kind == 1 || kind == 3
              ex.ostk[s] = exn
            if h.hidden >= 0
              ex.ostk[fp + h.hidden] = exn
            return [h.target, fp, csp]
      k += 1
    # pop the frame
    csp -= 2
    rpc = ex.cstk[csp]
    if rpc < 0
      raise WasmException.new(exn)
    pc = rpc - 1
    fp = ex.cstk[csp + 1]
  nil

-> w_throw(ex, inst, exn, pc, fp, csp)
  w_unwind(ex, inst, exn, pc, fp, csp)

# ---- OP_EXT ----

-> w_mem(inst, mi)
  inst.mems[mi]

-> w_ea(ex, mem, addr, off, n)
  ea = addr + off
  w_trap_code(5) if addr < 0 || off < 0 || ea < 0 || ea + n > mem.size
  ea

-> w_ext(ex, inst, pc, fp, csp)
  code = inst.mod.code
  len = code[pc + 1]
  sub = code[pc + 2]
  o = pc + 3
  nxt = pc + len
  stk = ex.stk
  ostk = ex.ostk
  if sub == 0x23
    g = inst.gimports[code[o + 1]]
    w_slot_write(ex, g.type, fp + code[o], g.get)
  elsif sub == 0x24
    g = inst.gimports[code[o]]
    g.set(w_slot_read(ex, g.type, fp + code[o + 1]))
  elsif sub == 0x25
    t = inst.tables[code[o]]
    i = stk[fp + code[o + 2]]
    w_trap_code(11) if i < 0 || i >= t.size
    ostk[fp + code[o + 1]] = t.get(i)
  elsif sub == 0x26
    t = inst.tables[code[o]]
    i = stk[fp + code[o + 1]]
    w_trap_code(11) if i < 0 || i >= t.size
    t.set(i, ostk[fp + code[o + 2]])
  elsif sub == 0x3f
    mem = inst.mems[code[o]]
    stk[fp + code[o + 1]] = mem.pages
  elsif sub == 0x40
    mem = inst.mems[code[o]]
    n = stk[fp + code[o + 2]]
    n = n & 0xffffffff if !mem.is64
    r = mem.grow(n)
    stk[fp + code[o + 1]] = mem.is64 ? r : (r & 0xffffffff)
  elsif sub == 0xd2
    ostk[fp + code[o]] = inst.funcs[code[o + 1]]
  elsif sub == 0x08
    tag = inst.tags[code[o]]
    vals = w_read_values(ex, tag.sig.params, fp + code[o + 1])
    return w_throw(ex, inst, WExn.new(tag, vals), pc, fp, csp)
  elsif sub == 0x0a
    e = ostk[fp + code[o]]
    w_trap_code(18) if e == nil
    return w_throw(ex, inst, e, pc, fp, csp)
  elsif sub == 0x09
    e = ostk[fp + code[o]]
    return w_throw(ex, inst, e, pc, fp, csp)
  elsif sub == 0x12
    f = inst.funcs[code[o]]
    base = code[o + 1]
    w_call_at(ex, f, fp + base, fp + base + w_max(f.sig.param_slots, f.sig.result_slots) + 2)
    w_move_results(ex, f.sig, fp + base, fp)
    return w_ret(ex, fp, csp)
  elsif sub == 0x13 || sub == 0x15
    canon = code[o]
    base = code[o + 1]
    a = code[o + 2]
    f = nil
    if sub == 0x13
      f = w_table_func(inst, code[o + 3], stk[fp + a], canon)
    else
      f = ostk[fp + a]
      w_trap_code(14) if f == nil
    ft = f.sig
    if f.inst == inst && f.host == nil
      n = ft.param_slots
      k = 0
      while k < n
        stk[fp + k] = stk[fp + base + k]
        ostk[fp + k] = ostk[fp + base + k]
        k += 1
      m = inst.mod
      return [m.fentry[f.index - m.n_imp_funcs].entry, fp, csp]
    w_call_at(ex, f, fp + base, fp + base + w_max(ft.param_slots, ft.result_slots) + 2)
    w_move_results(ex, ft, fp + base, fp)
    return w_ret(ex, fp, csp)
  elsif sub >= 0x10000 && sub < 0x20000
    w_ext_mem(ex, inst, sub - 0x10000, code, o, fp)
  elsif sub >= 0xfc0000 && sub < 0xfd0000
    w_ext_fc(ex, inst, sub - 0xfc0000, code, o, fp)
  elsif sub >= 0xfb0000 && sub < 0xfc0000
    w_ext_gc(ex, inst, sub - 0xfb0000, code, o, fp)
  elsif sub >= 0xfd0000 && sub < 0xfe0000
    w_ext_simd_mem(ex, inst, sub - 0xfd0000, code, o, fp)
  elsif sub >= 0xfe0000 && sub < 0xff0000
    w_ext_atomic(ex, inst, sub - 0xfe0000, code, o, fp)
  else
    w_trap_code(99)
  [nxt, fp, csp]

-> w_move_results(ex, ft, from, to)
  n = ft.result_slots
  k = 0
  while k < n
    ex.stk[to + k] = ex.stk[from + k]
    ex.ostk[to + k] = ex.ostk[from + k]
    k += 1
  nil

# Loads and stores on memories other than 0 (operands as OP_LD*/OP_ST*).
-> w_ext_mem(ex, inst, opc, code, o, fp)
  mem = inst.mems[code[o]]
  stk = ex.stk
  if opc >= OP_ST32 && opc <= OP_ST16
    addr = stk[fp + code[o + 1]]
    v = stk[fp + code[o + 2]]
    off = code[o + 3]
    n = opc == OP_ST32 ? 4 : (opc == OP_ST64 ? 8 : (opc == OP_ST8 ? 1 : 2))
    ea = w_ea(ex, mem, addr, off, n)
    if n == 4
      wk_st32(mem.data, ea, v)
    elsif n == 8
      wk_st64(mem.data, ea, v)
    elsif n == 1
      wk_st8(mem.data, ea, v)
    else
      wk_st16(mem.data, ea, v)
    return nil
  d = fp + code[o + 1]
  addr = stk[fp + code[o + 2]]
  off = code[o + 3]
  data = mem.data
  if opc == OP_LD32
    stk[d] = wk_ld32u(data, w_ea(ex, mem, addr, off, 4))
  elsif opc == OP_LD64
    stk[d] = wk_ld64(data, w_ea(ex, mem, addr, off, 8))
  elsif opc == OP_LD8S32
    stk[d] = wk_ld8s(data, w_ea(ex, mem, addr, off, 1)) & 0xffffffff
  elsif opc == OP_LD8U
    stk[d] = wk_ld8u(data, w_ea(ex, mem, addr, off, 1))
  elsif opc == OP_LD16S32
    stk[d] = wk_ld16s(data, w_ea(ex, mem, addr, off, 2)) & 0xffffffff
  elsif opc == OP_LD16U
    stk[d] = wk_ld16u(data, w_ea(ex, mem, addr, off, 2))
  elsif opc == OP_LD8S64
    stk[d] = wk_ld8s(data, w_ea(ex, mem, addr, off, 1))
  elsif opc == OP_LD16S64
    stk[d] = wk_ld16s(data, w_ea(ex, mem, addr, off, 2))
  elsif opc == OP_LD32S64
    stk[d] = wk_ld32s(data, w_ea(ex, mem, addr, off, 4))
  nil

-> w_ext_fc(ex, inst, sub, code, o, fp)
  stk = ex.stk
  ostk = ex.ostk
  if sub == 8
    mem = inst.mems[code[o]]
    di = code[o + 1]
    d = stk[fp + code[o + 2]]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    seg = inst.mod.datas[di]
    slen = inst.dropped_data[di] ? 0 : seg.size
    w_trap_code(5) if s + n > slen || d < 0 || d + n > mem.size
    wk_memcpy2(mem.data, d, inst.mod.bytes, seg.start + s, n) if n > 0
  elsif sub == 9
    inst.dropped_data[code[o]] = true
  elsif sub == 10
    m1 = inst.mems[code[o]]
    m2 = inst.mems[code[o + 1]]
    d = stk[fp + code[o + 2]]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    w_trap_code(5) if d < 0 || s < 0 || n < 0 || d + n > m1.size || s + n > m2.size
    wk_memcpy2(m1.data, d, m2.data, s, n) if n > 0
  elsif sub == 11
    mem = inst.mems[code[o]]
    d = stk[fp + code[o + 1]]
    v = stk[fp + code[o + 2]]
    n = stk[fp + code[o + 3]]
    w_trap_code(5) if d < 0 || n < 0 || d + n > mem.size
    wk_memset(mem.data, d, v, n) if n > 0
  elsif sub == 12
    t = inst.tables[code[o]]
    seg = inst.elems[code[o + 1]]
    d = stk[fp + code[o + 2]]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    w_table_init(t, seg, d, s, n)
  elsif sub == 13
    inst.elems[code[o]] = []
  elsif sub == 14
    t1 = inst.tables[code[o]]
    t2 = inst.tables[code[o + 1]]
    d = stk[fp + code[o + 2]]
    s = stk[fp + code[o + 3]]
    n = stk[fp + code[o + 4]]
    w_trap_code(11) if d < 0 || s < 0 || n < 0 || d + n > t1.size || s + n > t2.size
    if d <= s
      k = 0
      while k < n
        t1.set(d + k, t2.get(s + k))
        k += 1
    else
      k = n - 1
      while k >= 0
        t1.set(d + k, t2.get(s + k))
        k -= 1
  elsif sub == 15
    t = inst.tables[code[o]]
    v = ostk[fp + code[o + 2]]
    n = stk[fp + code[o + 3]]
    r = t.grow(n, v)
    stk[fp + code[o + 1]] = t.is64 ? r : (r & 0xffffffff)
  elsif sub == 16
    t = inst.tables[code[o]]
    stk[fp + code[o + 1]] = t.size
  elsif sub == 17
    t = inst.tables[code[o]]
    d = stk[fp + code[o + 1]]
    v = ostk[fp + code[o + 2]]
    n = stk[fp + code[o + 3]]
    w_trap_code(11) if d < 0 || n < 0 || d + n > t.size
    k = 0
    while k < n
      t.set(d + k, v)
      k += 1
  nil

-> w_table_init(t, seg, d, s, n)
  w_trap_code(11) if d < 0 || s < 0 || n < 0 || s + n > seg.size || d + n > t.size
  k = 0
  while k < n
    t.set(d + k, seg[s + k])
    k += 1
  nil

# ---- instantiation ----

-> w_link_fail(msg)
  raise WasmLinkError, msg

-> w_import_ok?(m, imp, v)
  k = imp.kind
  if k == 0
    return false if !v.is_a?(WFunc)
    return W_TYPES.sub?(v.type, m.canon[imp.desc])
  if k == 1
    return false if !v.is_a?(WTable)
    tt = imp.desc
    return false if v.type != tt.elem || v.is64 != tt.is64
    return false if v.size < tt.min
    if tt.max != nil
      return false if v.max == nil || v.max > tt.max
    return true
  if k == 2
    return false if !v.is_a?(WMemory)
    mt = imp.desc
    return false if v.shared != mt.shared || v.is64 != mt.is64 || v.page_log2 != mt.page_log2
    return false if v.pages < mt.min
    if mt.max != nil
      return false if v.max == nil || v.max > mt.max
    return true
  if k == 3
    return false if !v.is_a?(WGlobal)
    gt = imp.desc
    return false if v.mutable != gt.mutable
    return v.type == gt.type if gt.mutable
    return wt_sub?(v.type, gt.type)
  if k == 4
    return false if !v.is_a?(WTag)
    return v.type == m.canon[imp.desc]
  false

# Instantiate m (validated); resolver: ->(module, name) the extern value or nil.
-> wasm_instantiate(m, resolver)
  wasm_validate(m)
  store = wasm_store()
  store.ninst += 1
  inst = WInstance.new(store.ninst, m)
  store.instances.push(inst)
  ng = m.globals.size
  inst.glob = i64[ng * 2 + 2]
  inst.gref = []
  k = 0
  while k < ng + 1
    inst.gref.push(nil)
    k += 1
  # imports
  gi = 0
  m.imports.each ->(imp)
    v = resolver.call(imp.mod, imp.name)
    w_link_fail("unknown import " + imp.mod + "." + imp.name) if v == nil
    w_link_fail("incompatible import type for " + imp.mod + "." + imp.name) if !w_import_ok?(m, imp, v)
    if imp.kind == 0
      inst.funcs.push(v)
    elsif imp.kind == 1
      inst.tables.push(v)
    elsif imp.kind == 2
      inst.mems.push(v)
    elsif imp.kind == 3
      inst.globals.push(v)
      inst.gimports[gi] = v
      w_store_global(inst, gi, v.type, v.get)
      gi += 1
    else
      inst.tags.push(v)
  # functions
  fi = m.n_imp_funcs
  while fi < m.funcs.size
    f = WFunc.new(m.canon[m.funcs[fi]], inst, fi, nil)
    f.name = m.func_names[fi]
    store.add_func(f)
    inst.funcs.push(f)
    fi += 1
  # tags
  ti = m.n_imp_tags
  while ti < m.tags.size
    inst.tags.push(WTag.new(m.canon[m.tags[ti]]))
    ti += 1
  # globals (in order; each may use earlier ones)
  gi = m.n_imp_globals
  while gi < ng
    g = m.globals[gi]
    v = w_eval_const(inst, g.init)
    w_store_global(inst, gi, g.type, v)
    wg = WGlobal.new(g.type, g.mutable)
    wg.nums = inst.glob
    wg.refs = inst.gref
    wg.at = gi
    inst.globals.push(wg)
    gi += 1
  # memories
  mi = m.n_imp_mems
  while mi < m.mems.size
    mt = m.mems[mi]
    w_link_fail("memory size too large") if mt.min > 65536 && mt.page_log2 == 16
    inst.mems.push(WMemory.new(mt.min, mt.max, mt.shared, mt.is64, mt.page_log2))
    mi += 1
  # tables
  ti = m.n_imp_tables
  while ti < m.tables.size
    tt = m.tables[ti]
    init = tt.init == nil ? nil : w_eval_const(inst, tt.init)
    w_link_fail("table size too large") if tt.min > 10000000
    inst.tables.push(WTable.new(tt.elem, tt.min, tt.max, tt.is64, init))
    ti += 1
  # exports
  m.exports.each ->(x)
    v = nil
    if x.kind == 0
      v = inst.funcs[x.index]
    elsif x.kind == 1
      v = inst.tables[x.index]
    elsif x.kind == 2
      v = inst.mems[x.index]
    elsif x.kind == 3
      v = inst.globals[x.index]
    else
      v = inst.tags[x.index]
    inst.exports[x.name] = v
    inst.export_list.push([x.name, x.kind, v])
  # element segments
  m.elems.each ->(e)
    items = []
    if e.funcs != nil
      e.funcs.each ->(f) items.push(inst.funcs[f])
    else
      e.items.each ->(ce) items.push(w_eval_const(inst, ce))
    inst.elems.push(items)
  m.datas.each ->(d) inst.dropped_data.push(false)
  ei = 0
  m.elems.each ->(e)
    if e.mode == 0
      off = w_eval_const(inst, e.offset)
      t = inst.tables[e.table]
      items = inst.elems[ei]
      w_table_init(t, items, off, 0, items.size)
      inst.elems[ei] = []
    elsif e.mode == 2
      inst.elems[ei] = []
    ei += 1
  di = 0
  m.datas.each ->(d)
    if d.mode == 0
      off = w_eval_const(inst, d.offset)
      mem = inst.mems[d.mem]
      w_trap_code(5) if off < 0 || off + d.size > mem.size
      wk_memcpy2(mem.data, off, m.bytes, d.start, d.size) if d.size > 0
      inst.dropped_data[di] = true
    di += 1
  if m.start != nil
    wasm_call(inst.funcs[m.start], [])
  inst

-> w_store_global(inst, gi, t, v)
  if wt_ref?(t)
    inst.gref[gi] = v
  elsif t == V128
    inst.glob[gi * 2] = v.lo
    inst.glob[gi * 2 + 1] = v.hi
  else
    inst.glob[gi * 2] = v
  nil

# Evaluate a constant expression to a raw value.
-> w_eval_const(inst, ce)
  m = inst.mod
  r = WReader.new(m.bytes, ce.start, ce.stop + 1, m)
  st = []
  while true
    op = r.byte()
    if op == 0x0b
      break
    elsif op == 0x41
      st.push(r.vs32() & 0xffffffff)
    elsif op == 0x42
      st.push(r.vs64())
    elsif op == 0x43
      st.push(r.vf32())
    elsif op == 0x44
      st.push(r.vf64())
    elsif op == 0xd0
      r.heap_type()
      st.push(nil)
    elsif op == 0xd2
      st.push(inst.funcs[r.vu32()])
    elsif op == 0x23
      st.push(inst.globals[r.vu32()].get)
    elsif op == 0x6a
      b = st.pop
      a = st.pop
      st.push((a + b) & 0xffffffff)
    elsif op == 0x6b
      b = st.pop
      a = st.pop
      st.push((a - b) & 0xffffffff)
    elsif op == 0x6c
      b = st.pop
      a = st.pop
      st.push((a * b) & 0xffffffff)
    elsif op == 0x7c
      b = st.pop
      a = st.pop
      st.push((a + b) ## i64)
    elsif op == 0x7d
      b = st.pop
      a = st.pop
      st.push((a - b) ## i64)
    elsif op == 0x7e
      b = st.pop
      a = st.pop
      st.push((a * b) ## i64)
    elsif op == 0xfd
      r.vu32()
      lo = r.vf64()
      hi = r.vf64()
      st.push(WV128.new(lo, hi))
    elsif op == 0xfb
      w_eval_const_gc(inst, r, r.vu32(), st)
  st[0]
