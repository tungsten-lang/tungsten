# wasm/validate — module-level validation and compilation.
#
#   wasm_validate(m)   # raises WasmInvalid / WasmMalformed; fills m.code and m.fentry
#
# Function bodies are validated and compiled together (compile.w); this file checks the
# module's other components and constant expressions.

MAX_PAGES32 = 65536
MAX_PAGES64 = 281474976710656

-> w_check_limits(mn, mx, cap, what)
  w_invalid(what + " size must be at most " + cap.to_s) if mn < 0 || mn > cap || (mx != nil && (mx < 0 || mx > cap))
  w_invalid("size minimum must not be greater than maximum") if mx != nil && mn > mx
  nil

-> w_valid_mem(mt)
  cap = mt.is64 ? MAX_PAGES64 : MAX_PAGES32
  cap = mt.is64 ? 18446744073709551615 : 4294967296 if mt.page_log2 == 0
  w_check_limits(mt.min, mt.max, cap, "memory")
  w_invalid("shared memory must have maximum") if mt.shared && mt.max == nil
  nil

-> w_valid_table(tt)
  cap = tt.is64 ? 18446744073709551615 : 4294967295
  mx = tt.max
  w_invalid("size minimum must not be greater than maximum") if mx != nil && w_ugt?(tt.min, mx)
  nil

-> w_ugt?(a, b)
  # unsigned 64-bit compare of wrapped values
  ua = a < 0 ? a + 18446744073709551616 : a
  ub = b < 0 ? b + 18446744073709551616 : b
  ua > ub

# Validate a constant expression; returns its type. nglob: globals it may reference.
-> w_valid_const(m, ce, expect, nglob)
  r = WReader.new(m.bytes, ce.start, ce.stop + 1, m)
  st = []
  while true
    op = r.byte()
    if op == 0x0b
      break
    elsif op == 0x41
      r.vs32()
      st.push(I32)
    elsif op == 0x42
      r.vs64()
      st.push(I64)
    elsif op == 0x43
      r.vf32()
      st.push(F32)
    elsif op == 0x44
      r.vf64()
      st.push(F64)
    elsif op == 0xd0
      st.push(wt_ref(true, r.heap_type()))
    elsif op == 0xd2
      fi = r.vu32()
      w_invalid("unknown function " + fi.to_s) if fi >= m.funcs.size
      m.declared_funcs[fi] = true
      st.push(wt_ref(false, m.canon[m.funcs[fi]]))
    elsif op == 0x23
      gi = r.vu32()
      w_invalid("unknown global " + gi.to_s) if gi >= nglob
      g = m.globals[gi]
      w_invalid("constant expression required") if g.mutable
      st.push(g.type)
    elsif op == 0x6a || op == 0x6b || op == 0x6c || op == 0x7c || op == 0x7d || op == 0x7e
      t = op <= 0x6c ? I32 : I64
      w_invalid("type mismatch") if st.size < 2 || st.pop != t || st.pop != t
      st.push(t)
    elsif op == 0xfd
      sub = r.vu32()
      w_invalid("constant expression required") if sub != 12
      r.bytes(16)
      st.push(V128)
    elsif op == 0xfb
      sub = r.vu32()
      if sub == 0 || sub == 1
        ti = r.vu32()
        w_invalid("unknown type") if ti >= m.types.size
        t = m.type_at(ti)
        w_invalid("type mismatch") if !t.struct?
        if sub == 0
          k = t.ftypes.size - 1
          while k >= 0
            w_invalid("type mismatch") if st.size == 0 || !wt_sub?(st.pop, wt_unpack(t.ftypes[k]))
            k -= 1
        st.push(wt_ref(false, m.canon[ti]))
      elsif sub == 6 || sub == 7 || sub == 8
        ti = r.vu32()
        w_invalid("unknown type") if ti >= m.types.size
        t = m.type_at(ti)
        w_invalid("type mismatch") if !t.array?
        if sub == 8
          n = r.vu32()
          k = 0
          while k < n
            w_invalid("type mismatch") if st.size == 0 || !wt_sub?(st.pop, wt_unpack(t.ftypes[0]))
            k += 1
        else
          w_invalid("type mismatch") if st.size == 0 || st.pop != I32
          if sub == 6
            w_invalid("type mismatch") if st.size == 0 || !wt_sub?(st.pop, wt_unpack(t.ftypes[0]))
        st.push(wt_ref(false, m.canon[ti]))
      elsif sub == 28
        w_invalid("type mismatch") if st.size == 0 || st.pop != I32
        st.push(wt_ref(false, HT_I31))
      elsif sub == 26 || sub == 27
        w_invalid("type mismatch") if st.size == 0
        t = st.pop
        w_invalid("type mismatch") if !wt_ref?(t)
        st.push(wt_ref(wt_nullable?(t), sub == 26 ? HT_ANY : HT_EXTERN))
      else
        w_invalid("constant expression required")
    else
      # an ordinary instruction: skip it and reject
      w_invalid("constant expression required")
  w_invalid("type mismatch") if st.size != 1
  w_invalid("type mismatch: constant expression") if expect != nil && !wt_sub?(st[0], expect)
  st[0]

-> wasm_validate(m)
  return m if m.compiled
  ng_imp = m.n_imp_globals
  # functions and tags must name function types
  m.funcs.each ->(ti)
    w_invalid("unknown type " + ti.to_s) if ti >= m.types.size
    w_invalid("type mismatch: not a function type") if !m.type_at(ti).func?
  m.tags.each ->(ti)
    w_invalid("unknown type " + ti.to_s) if ti >= m.types.size
    t = m.type_at(ti)
    w_invalid("type mismatch: not a function type") if !t.func?
    w_invalid("non-empty tag result type") if t.results.size != 0
  m.mems.each ->(mt) w_valid_mem(mt)
  m.tables.each ->(tt) w_valid_table(tt)
  # globals: each init may use earlier globals
  gi = 0
  m.globals.each ->(g)
    if gi >= ng_imp
      w_valid_const(m, g.init, g.type, gi)
    gi += 1
  ti = 0
  m.tables.each ->(tt)
    if ti >= m.n_imp_tables
      if tt.init != nil
        w_valid_const(m, tt.init, tt.elem, m.n_imp_globals)
      elsif !wt_nullable?(tt.elem)
        w_invalid("type mismatch: table without initializer")
    ti += 1
  # elems
  m.elems.each ->(e)
    if e.funcs != nil
      e.funcs.each ->(fi)
        w_invalid("unknown function " + fi.to_s) if fi >= m.funcs.size
        m.declared_funcs[fi] = true
    else
      e.items.each ->(ce) w_valid_const(m, ce, e.type, m.globals.size)
    if e.mode == 0
      w_invalid("unknown table " + e.table.to_s) if e.table >= m.tables.size
      tt = m.tables[e.table]
      w_valid_const(m, e.offset, tt.is64 ? I64 : I32, m.globals.size)
      w_invalid("type mismatch: elem segment type") if !wt_sub?(e.type, tt.elem)
  m.datas.each ->(d)
    if d.mode == 0
      w_invalid("unknown memory " + d.mem.to_s) if d.mem >= m.mems.size
      w_valid_const(m, d.offset, m.mems[d.mem].is64 ? I64 : I32, m.globals.size)
  # exports
  names = {}
  m.exports.each ->(x)
    w_invalid("duplicate export name") if names.has_key?(x.name)
    names[x.name] = true
    k = x.kind
    if k == 0
      w_invalid("unknown function " + x.index.to_s) if x.index >= m.funcs.size
      m.declared_funcs[x.index] = true
    elsif k == 1
      w_invalid("unknown table " + x.index.to_s) if x.index >= m.tables.size
    elsif k == 2
      w_invalid("unknown memory " + x.index.to_s) if x.index >= m.mems.size
    elsif k == 3
      w_invalid("unknown global " + x.index.to_s) if x.index >= m.globals.size
    else
      w_invalid("unknown tag " + x.index.to_s) if x.index >= m.tags.size
  if m.start != nil
    w_invalid("unknown function " + m.start.to_s) if m.start >= m.funcs.size
    st = m.func_type(m.start)
    w_invalid("start function") if st.params.size != 0 || st.results.size != 0
  # bodies
  code = []
  c = WCompiler.new(m, code)
  metas = []
  fi = m.n_imp_funcs
  while fi < m.funcs.size
    metas.push(c.compile_func(fi))
    fi += 1
  # patch direct calls with entry addresses
  c.call_sites.each ->(p)
    f = code[p]
    code[p] = metas[f - m.n_imp_funcs].entry
  arr = i64[code.size + 1]
  i = 0
  while i < code.size
    arr[i] = code[i]
    i += 1
  arr[code.size] = OP_RET
  m.code = arr
  m.fentry = metas
  m.compiled = true
  m

+ WCompiler
  -> call_sites
    @calls
