# wasm/compile — validation and compilation of function bodies in one pass.
#
# The validator follows the spec's algorithm (operand stack of types, control frames,
# polymorphic stack after unconditional branches). As it goes it emits the interpreter's
# register code: every operand-stack position has a fixed frame slot (locals first, then
# the operand area; v128 takes two slots, references live in the parallel object stack at
# the same index), so a wasm instruction becomes one 3-address op on slots.
#
# Deferred operands: local.get and constants do not emit anything; the stack entry just
# names the local's slot or carries the constant, and the consumer reads the local directly
# or uses an immediate form (ADDI32, JLTSI32, ...). A compare followed by br_if/if fuses into
# one compare-and-branch. A local.set right after an op retargets that op's destination.
# Deferred entries are materialised at control-flow boundaries and before a local they alias
# is overwritten, which keeps the scheme exact.
#
# Rare or complex instructions compile to OP_EXT, executed by the driver (runtime.w).

W_DEBUG = [true]

K_SLOT = 0
K_CONST = 1
K_CMP = 2

# compare kinds (index into the fused op tables)
CMP_EQ = 0
CMP_NE = 1
CMP_LTU = 2
CMP_GTU = 3
CMP_LEU = 4
CMP_GEU = 5
CMP_LTS32 = 6
CMP_GTS32 = 7
CMP_LES32 = 8
CMP_GES32 = 9
CMP_LTS64 = 10
CMP_GTS64 = 11
CMP_LES64 = 12
CMP_GES64 = 13
CMP_INV = [1, 0, 5, 4, 3, 2, 9, 8, 7, 6, 13, 12, 11, 10]
CMP_SWAP = [0, 1, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12]

-> w_cmp_op(c)
  OP_EQ + c

# A control frame. kind: 0 func, 1 block, 2 loop, 3 if, 4 else, 5 try_table, 6 try, 7 catch
+ WCtl
  rw :kind, :params, :results, :height, :base, :unreachable, :fixups, :loop_pc, :else_fix, :handler_start, :catches, :hidden, :depth, :try_idx, :pdead, :init_save

  -> new(@kind, @params, @results, @height, @base)
    @unreachable = false
    @fixups = []
    @loop_pc = -1
    @else_fix = -1
    @handler_start = -1
    @catches = nil
    @hidden = -1
    @depth = 0
    @try_idx = -1
    @pdead = false

  -> label_types
    @kind == 2 ? @params : @results

# An exception handler range. kind: 0 catch tag, 1 catch_ref tag, 2 catch_all, 3 catch_all_ref,
# 4 legacy catch tag, 5 legacy catch_all, 6 delegate (tag = target depth).
# target: code index; slot: frame slot of the first payload value; hidden: legacy exn slot.
+ WHandler
  rw :start, :stop, :kind, :tag, :target, :slot, :depth, :hidden
  -> new(@start, @stop, @kind, @tag, @target, @slot, @depth)
    @hidden = -1

# Per-function compiled metadata.
+ WFuncCode
  rw :entry, :stop, :fsize, :nparams, :nresults, :handlers, :index, :param_slots, :result_slots, :ltypes, :lslot
  -> new(@index)
    @entry = 0
    @stop = 0
    @fsize = 0
    @handlers = []

+ WCompiler
  rw :m, :code

  -> new(@m, @code)
    @calls = []
    @dead = false

  # ---- stack ----

  -> reset_stack
    @st_t = []
    @st_k = []
    @st_v = []
    @st_h = []
    @top = @nls       # next free slot
    @maxs = @nls
    @ctl = []
    @last_pos = -1
    @last_dest = -1
    @dead = false
    @hidden_n = 0
    @hidden_fix = []
    @fsize_fix = []
    @pending_handlers = []
    @try_end = 0

  -> sp
    @st_t.size

  -> push_entry(t, k, v)
    h = @top
    @st_t.push(t)
    @st_k.push(k)
    @st_v.push(v)
    @st_h.push(h)
    @top = h + wt_slots(t)
    @maxs = @top if @top > @maxs
    h

  # Push an operation result: the value lives in its home slot. Returns the slot.
  -> push(t)
    push_entry(t, K_SLOT, @top)

  -> push_const(t, v)
    push_entry(t, K_CONST, v)

  -> push_alias(t, slot)
    push_entry(t, K_SLOT, slot)

  -> pop_raw
    @st_t.pop
    @st_k.pop
    @st_v.pop
    h = @st_h.pop
    @top = h
    nil

  # Pop a value of type t (or any if t == nil). Sets @pt, @pk, @pv (type, kind, value).
  -> pop(t)
    f = @ctl[@ctl.size - 1]
    if sp() == f.height
      w_invalid("type mismatch: stack underflow") if !f.unreachable
      @pt = t == nil ? BOT : BOT
      @pk = K_SLOT
      @pv = 0
      return BOT
    i = sp() - 1
    at = @st_t[i]
    if t != nil && !wt_sub?(at, t)
      w_invalid("type mismatch: expected " + wt_name(t) + " got " + wt_name(at))
    flush_cmp() if @st_k[i] == K_CMP
    @pt = @st_t[i]
    @pk = @st_k[i]
    @pv = @st_v[i]
    pop_raw()
    @pt

  # Pop an operand and return the slot holding it (materialising constants into the home).
  -> pop_slot(t)
    pop(t)
    if @pk == K_CONST
      emit_const(@top, @pt, @pv)
      return @top
    @pv

  # Pop a ref of any reference type.
  -> pop_ref
    f = @ctl[@ctl.size - 1]
    if sp() == f.height && f.unreachable
      @pt = BOT
      @pk = K_SLOT
      @pv = 0
      return BOT
    t = pop(nil)
    w_invalid("type mismatch: expected reference") if t != BOT && !wt_ref?(t)
    t

  -> emit_const(slot, t, v)
    if wt_ref?(t)
      emit2(OP_REFNULL, slot)
    else
      emit3(OP_CONST, slot, v)

  # Make entry i live in its home slot.
  -> materialize(i)
    k = @st_k[i]
    h = @st_h[i]
    if k == K_CMP
      flush_cmp()
      return nil
    if k == K_CONST
      emit_const(h, @st_t[i], @st_v[i])
    elsif @st_v[i] != h
      emit_move(@st_t[i], h, @st_v[i])
    @st_k[i] = K_SLOT
    @st_v[i] = h
    nil

  -> materialize_all
    i = 0
    n = sp()
    while i < n
      materialize(i) if @st_k[i] != K_SLOT || @st_v[i] != @st_h[i]
      i += 1
    nil

  -> materialize_top(n)
    f = @ctl[@ctl.size - 1]
    j = sp() - n
    j = f.height if j < f.height
    while j < sp()
      materialize(j) if @st_k[j] != K_SLOT || @st_v[j] != @st_h[j]
      j += 1
    nil

  -> materialize_aliases(slot)
    i = 0
    n = sp()
    while i < n
      materialize(i) if @st_k[i] == K_SLOT && @st_v[i] == slot && @st_h[i] != slot
      i += 1
    nil

  -> emit_move(t, d, s)
    return nil if d == s
    if t == V128
      emit3(OP_MOV2, d, s)
    elsif wt_ref?(t)
      emit3(OP_MOVR, d, s)
    else
      emit3(OP_MOV, d, s)

  # ---- emission ----

  -> pc
    @code.size

  -> emit1(a)
    return nil if @dead
    @last_pos = -1
    @code.push(a)

  -> emit2(a, b)
    return nil if @dead
    @last_pos = -1
    @code.push(a)
    @code.push(b)

  -> emit3(a, b, c)
    return nil if @dead
    @last_pos = @code.size
    @code.push(a)
    @code.push(b)
    @code.push(c)

  -> emit4(a, b, c, d)
    return nil if @dead
    @last_pos = @code.size
    @code.push(a)
    @code.push(b)
    @code.push(c)
    @code.push(d)

  # Emit with a destination at operand 1 (retargetable by local.set).
  -> emit_d(arr)
    return nil if @dead
    @last_pos = @code.size
    arr.each ->(x) @code.push(x)
    nil

  -> emit_n(arr)
    return nil if @dead
    @last_pos = -1
    arr.each ->(x) @code.push(x)
    nil

  # An OP_EXT: [EXT, len, sub, operands...]
  -> ext(sub, args)
    return nil if @dead
    @last_pos = -1
    @code.push(OP_EXT)
    @code.push(args.size + 3)
    @code.push(sub)
    args.each ->(x) @code.push(x)
    nil

  -> bind_label
    @last_pos = -1

  # Emit a jump to a control frame's label (fixup for forward labels).
  -> jump_to(f, op_words)
    return nil if @dead
    @last_pos = -1
    op_words.each ->(x) @code.push(x)
    if f.kind == 2
      @code.push(f.loop_pc)
    else
      f.fixups.push(@code.size)
      @code.push(-1)
    nil

  -> patch_here(fixups)
    t = pc()
    fixups.each ->(p) @code[p] = t
    nil

  # ---- the pending compare ----

  -> push_cmp(c, a, bk, b)
    # bk: 0 slot, 1 immediate
    @cmp_c = c
    @cmp_a = a
    @cmp_bk = bk
    @cmp_b = b
    push_entry(I32, K_CMP, 0)

  -> flush_cmp
    i = sp() - 1
    return nil if i < 0 || @st_k[i] != K_CMP
    h = @st_h[i]
    @st_k[i] = K_SLOT
    @st_v[i] = h
    if @cmp_bk == 1
      emit4(OP_EQI + @cmp_c, h, @cmp_a, @cmp_b)
    else
      emit4(OP_EQ + @cmp_c, h, @cmp_a, @cmp_b)
    nil

  # Pop an i32 condition: returns [cmp, a, bk, b] describing "jump if true".
  -> pop_cond
    i = sp() - 1
    f = @ctl[@ctl.size - 1]
    if i >= f.height && @st_k[i] == K_CMP
      r = [@cmp_c, @cmp_a, @cmp_bk, @cmp_b]
      @st_k[i] = K_SLOT
      pop_raw()
      return r
    pop(I32)
    if @pk == K_CONST
      return [CMP_NE, -1, 1, @pv & 0xffffffff]
    [CMP_NE, @pv, 1, 0]

  # Emit "jump to target-frame if cond (or !cond when invert)". Returns nothing.
  -> emit_cond_jump(cond, invert, f)
    c = invert ? CMP_INV[cond[0]] : cond[0]
    if cond[1] < 0
      # constant condition
      taken = cond[3] != 0
      taken = !taken if invert
      jump_to(f, [OP_JMP]) if taken
      return nil
    if cond[2] == 1 && cond[3] == 0 && (c == CMP_NE || c == CMP_EQ)
      jump_to(f, [c == CMP_NE ? OP_JNZ : OP_JZ, cond[1]])
    elsif cond[2] == 1
      jump_to(f, [OP_JEQI + c, cond[1], cond[3]])
    else
      jump_to(f, [OP_JEQ + c, cond[1], cond[3]])
    nil

  # A forward jump to a fresh fixup list (returns the list).
  -> emit_cond_jump_fwd(cond, invert)
    tmp = WCtl.new(1, [], [], 0, 0)
    emit_cond_jump(cond, invert, tmp)
    tmp.fixups

  # ---- control ----

  -> push_ctl(kind, params, results)
    # params have been popped (pop_params) and are re-pushed after
    h = sp()
    base = h < sp() ? @st_h[h] : @top
    f = WCtl.new(kind, params, results, h, base)
    f.depth = @ctl.size
    f.pdead = @dead
    f.init_save = @init.dup
    @ctl.push(f)
    f

  -> set_unreachable
    f = @ctl[@ctl.size - 1]
    while sp() > f.height
      pop_raw()
    f.unreachable = true
    @dead = true

  # Check the label's values on top of the stack (without popping them for good).
  -> check_label_values(types)
    vals = []
    k = types.size - 1
    while k >= 0
      pop(types[k])
      vals.push([@pt, @pk, @pv])
      k -= 1
    # push them back
    k = vals.size - 1
    while k >= 0
      v = vals[k]
      push_entry(v[0], v[1], v[2])
      k -= 1
    nil

  # Give the top values the label's types (br_if / br_on_null: pop then push label types).
  -> retype_top(types)
    n = types.size
    i = sp() - n
    k = 0
    while k < n
      @st_t[i + k] = types[k] if i + k >= 0
      k += 1
    nil

  # Move the top n values (types) into the label slots of frame f.
  -> branch_moves(f, types)
    n = types.size
    return nil if n == 0
    i = sp() - n
    if f.kind == 0
      j = i < 0 ? 0 : i
      while j < sp()
        materialize(j) if @st_k[j] != K_SLOT || @st_v[j] != @st_h[j]
        j += 1
    slot = f.base
    k = 0
    while k < n
      t = types[k]
      if i + k >= 0 && i + k < sp()
        kk = @st_k[i + k]
        if kk == K_CONST
          emit_const(slot, t, @st_v[i + k])
        elsif kk == K_SLOT
          emit_move(t, slot, @st_v[i + k])
      slot += wt_slots(t)
      k += 1
    nil

  -> needs_moves?(f, types)
    n = types.size
    i = sp() - n
    slot = f.base
    k = 0
    while k < n
      return true if i + k < 0
      return true if @st_k[i + k] != K_SLOT || @st_v[i + k] != slot
      slot += wt_slots(types[k])
      k += 1
    false

  -> label(depth)
    w_invalid("unknown label") if depth >= @ctl.size
    @ctl[@ctl.size - 1 - depth]

  -> block_sig(bt)
    if bt[0] < 0
      return [[], []]
    if bt[0] == 0
      return [[], [bt[1]]]
    w_invalid("unknown type") if bt[1] >= @m.types.size
    t = @m.type_at(bt[1])
    w_invalid("type mismatch: block type is not a function type") if !t.func?
    [t.params, t.results]

  # ---- module helpers ----

  -> check_mem(mi)
    w_invalid("unknown memory " + mi.to_s) if mi >= @m.mems.size
    @m.mems[mi]

  -> addr_type(mi)
    check_mem(mi).is64 ? I64 : I32

  -> table_addr(ti)
    w_invalid("unknown table " + ti.to_s) if ti >= @m.tables.size
    @m.tables[ti].is64 ? I64 : I32

  -> check_table(ti)
    w_invalid("unknown table " + ti.to_s) if ti >= @m.tables.size
    @m.tables[ti]

  -> check_func(fi)
    w_invalid("unknown function " + fi.to_s) if fi >= @m.funcs.size
    @m.func_type(fi)

  -> check_global(gi)
    w_invalid("unknown global " + gi.to_s) if gi >= @m.globals.size
    @m.globals[gi]

  -> check_type(ti)
    w_invalid("unknown type " + ti.to_s) if ti >= @m.types.size
    @m.type_at(ti)

  -> check_tag(ti)
    w_invalid("unknown tag " + ti.to_s) if ti >= @m.tags.size
    t = @m.tag_type(ti)
    t

  -> check_data(di)
    w_malformed("data count section required") if @m.data_count == nil
    w_invalid("unknown data segment " + di.to_s) if di >= @m.data_count
    nil

  -> check_elem(ei)
    w_invalid("unknown elem segment " + ei.to_s) if ei >= @m.elems.size
    @m.elems[ei]

  -> func_ref_declared?(fi)
    @m.declared_funcs.has_key?(fi)

  # memarg → [memidx, offset]; validates alignment against the natural size (log2)
  -> memarg(natural)
    a = @r.vu32()
    mi = 0
    if (a & 64) != 0
      a = a - 64
      mi = @r.vu32()
    w_malformed("malformed memop flags") if a >= 64
    off = @r.vu64()
    mt = check_mem(mi)
    w_invalid("alignment must not be larger than natural") if a > natural
    w_invalid("offset out of range") if !mt.is64 && (off < 0 || off > 4294967295)
    [mi, off]

  # ---- function compilation ----

  -> compile_func(fi)
    ci = fi - @m.n_imp_funcs
    wc = @m.codes[ci]
    ft = @m.func_type(fi)
    meta = WFuncCode.new(fi)
    @meta = meta
    @r = WReader.new(@m.bytes, wc.start, wc.stop, @m)
    # locals
    @ltypes = []
    @lslot = []
    s = 0
    ft.params.each ->(t)
      @ltypes.push(t)
      @lslot.push(s)
      s += wt_slots(t)
    nps = s
    has_ref_locals = false
    wc.locals.each ->(g)
      k = 0
      t = g[1]
      w_invalid("too many locals") if g[0] > 50000
      while k < g[0]
        @ltypes.push(t)
        @lslot.push(s)
        s += wt_slots(t)
        k += 1
      has_ref_locals = true if wt_ref?(t)
    # non-defaultable locals (non-nullable refs) need init tracking
    @nondef = []
    @init = []
    i = 0
    while i < @ltypes.size
      t = @ltypes[i]
      @init.push(i < ft.params.size || !(wt_ref?(t) && !wt_nullable?(t)))
      i += 1
    @init_stack = []
    @nls = s
    reset_stack()
    meta.entry = pc()
    meta.param_slots = nps
    meta.result_slots = ft.result_slots
    meta.nparams = ft.params.size
    meta.nresults = ft.results.size
    meta.ltypes = @ltypes
    meta.lslot = @lslot
    # ENTER fsize zlo zhi refs (fsize patched at the end)
    @enter_pos = pc()
    emit_n([OP_ENTER, 0, nps, s, 0])
    f = WCtl.new(0, [], ft.results, 0, 0)
    @ctl.push(f)
    @results = ft.results
    @body_ref = has_ref_locals
    begin
      body()
    rescue e
      if e.is_a?(WasmInvalid) && W_DEBUG[0]
        nm = ""
        @m.exports.each ->(x) nm = x.name if x.kind == 0 && x.index == fi
        raise WasmInvalid, e.to_s + " (func " + fi.to_s + " " + nm + " at byte " + @r.pos.to_s + ")"
      raise e
    w_malformed("section size mismatch") if @r.pos != wc.stop
    fsize = @maxs + @hidden_n
    @code[@enter_pos + 1] = fsize
    @fsize_fix.each ->(p) @code[p] = fsize
    @code[@enter_pos + 4] = (has_ref_locals || @hidden_n > 0) ? 1 : 0
    @hidden_fix.each ->(p) @code[p] = @code[p] - 1000000000 + @maxs
    meta.handlers.each ->(h) h.hidden = h.hidden - 1000000000 + @maxs if h.hidden >= 1000000000
    meta.fsize = fsize
    meta.stop = pc()
    meta

  # A hidden ref slot (legacy try's caught exception); patched to maxs + k at the end.
  -> hidden_slot
    k = @hidden_n
    @hidden_n += 1
    1000000000 + k

  -> do_return
    # move results to slots 0.. and RET (materialised first: a source may be a local in 0..)
    n = @results.size
    i = sp() - n
    j = i < 0 ? 0 : i
    while j < sp()
      materialize(j) if @st_k[j] != K_SLOT || @st_v[j] != @st_h[j]
      j += 1
    slot = 0
    k = 0
    while k < n
      t = @results[k]
      if i + k >= 0
        kk = @st_k[i + k]
        if kk == K_CONST
          emit_const(slot, t, @st_v[i + k])
        elsif kk == K_CMP
          materialize(i + k)
          emit_move(t, slot, @st_h[i + k])
        else
          emit_move(t, slot, @st_v[i + k])
      slot += wt_slots(t)
      k += 1
    emit1(OP_RET)

  -> body
    r = @r
    while true
      if @ctl.size == 0
        return nil
      op = r.byte()
      # a pending compare survives only into br_if / if / i32.eqz-free consumers
      if sp() > 0 && @st_k[sp() - 1] == K_CMP && op != 0x0d && op != 0x04
        flush_cmp()
      instr(op)
    nil

  -> end_frame
    f = @ctl[@ctl.size - 1]
    # results on the stack
    k = f.results.size - 1
    vals = []
    while k >= 0
      pop(f.results[k])
      vals.push([@pk, @pv, @pt])
      k -= 1
    w_invalid("type mismatch: values remaining on stack") if sp() != f.height
    # fallthrough: move results into the frame's slots
    if !@dead
      slot = f.base
      k = 0
      n = vals.size
      while k < n
        v = vals[n - 1 - k]
        t = f.results[k]
        if v[0] == K_CONST
          emit_const(slot, t, v[1])
        else
          emit_move(t, slot, v[1])
        slot += wt_slots(t)
        k += 1
    f

  -> push_results(types)
    types.each ->(t) push(t)

  # ---- instructions ----

  -> instr(op)
    r = @r
    if op == 0x00
      emit2(OP_TRAP, 1)
      set_unreachable()
    elsif op == 0x01
      nil
    elsif op == 0x02 || op == 0x03
      sig = block_sig(r.block_type())
      pop_params(sig[0])
      materialize_all()
      f = push_ctl(op == 0x02 ? 1 : 2, sig[0], sig[1])
      repush(sig[0])
      if op == 0x03
        bind_label()
        f.loop_pc = pc()
    elsif op == 0x04
      sig = block_sig(r.block_type())
      cond = pop_cond()
      pop_params(sig[0])
      materialize_all()
      repush(sig[0])
      pop_params(sig[0])
      fix = @dead ? [] : emit_cond_jump_fwd(cond, true)
      f = push_ctl(3, sig[0], sig[1])
      f.else_fix = fix
      repush(sig[0])
    elsif op == 0x05
      f = @ctl[@ctl.size - 1]
      w_invalid("else without if") if f.kind != 3
      end_frame()
      was_dead = @dead
      j = []
      if !@dead
        jump_to(f, [OP_JMP])
      bind_label()
      @dead = f.pdead
      patch_here(f.else_fix)
      f.else_fix = []
      f.kind = 4
      f.unreachable = false
      while sp() > f.height
        pop_raw()
      repush(f.params)
      @init = f.init_save.dup
    elsif op == 0x0b
      instr_end()
    elsif op == 0x0c
      d = r.vu32()
      f = label(d)
      lt = f.label_types
      check_label_values(lt)
      branch_moves(f, lt)
      jump_to(f, [OP_JMP])
      set_unreachable()
    elsif op == 0x0d
      d = r.vu32()
      f = label(d)
      cond = pop_cond()
      lt = f.label_types
      check_label_values(lt)
      if !@dead
        if needs_moves?(f, lt)
          materialize_top(lt.size)
        if needs_moves?(f, lt)
          skip = emit_cond_jump_fwd(cond, true)
          branch_moves(f, lt)
          jump_to(f, [OP_JMP])
          bind_label()
          patch_here(skip)
        else
          emit_cond_jump(cond, false, f)
      # values stay (their types become the label's)
      k = lt.size - 1
      vals = []
      while k >= 0
        pop(lt[k])
        vals.push([@pk, @pv])
        k -= 1
      k = vals.size - 1
      while k >= 0
        push_entry(lt[lt.size - 1 - k], vals[k][0], vals[k][1])
        k -= 1
    elsif op == 0x0e
      instr_br_table()
    elsif op == 0x0f
      check_label_values(@results)
      do_return()
      set_unreachable()
    elsif op == 0x10
      fi = r.vu32()
      ft = check_func(fi)
      do_call(fi, ft, false)
    elsif op == 0x11
      ti = r.vu32()
      tab = r.vu32()
      ft = check_type(ti)
      w_invalid("type mismatch: not a function type") if !ft.func?
      tt = check_table(tab)
      w_invalid("type mismatch: table is not funcref") if !wt_sub?(tt.elem, FUNCREF)
      do_call_indirect(ti, ft, tab, false)
    elsif op == 0x12
      fi = r.vu32()
      ft = check_func(fi)
      check_tail_results(ft)
      do_call(fi, ft, true)
    elsif op == 0x13
      ti = r.vu32()
      tab = r.vu32()
      ft = check_type(ti)
      w_invalid("type mismatch: not a function type") if !ft.func?
      tt = check_table(tab)
      w_invalid("type mismatch: table is not funcref") if !wt_sub?(tt.elem, FUNCREF)
      check_tail_results(ft)
      do_call_indirect(ti, ft, tab, true)
    elsif op == 0x14 || op == 0x15
      ti = r.vu32()
      ft = check_type(ti)
      w_invalid("type mismatch: not a function type") if !ft.func?
      check_tail_results(ft) if op == 0x15
      do_call_ref(ti, ft, op == 0x15)
    elsif op == 0x1a
      f = @ctl[@ctl.size - 1]
      if sp() == f.height && f.unreachable
        nil
      else
        pop(nil)
    elsif op == 0x1b || op == 0x1c
      instr_select(op)
    elsif op == 0x20
      li = r.vu32()
      w_invalid("unknown local " + li.to_s) if li >= @ltypes.size
      w_invalid("uninitialized local") if !@init[li]
      push_alias(@ltypes[li], @lslot[li])
    elsif op == 0x21 || op == 0x22
      li = r.vu32()
      w_invalid("unknown local " + li.to_s) if li >= @ltypes.size
      local_set(li, op == 0x22)
    elsif op == 0x23
      gi = r.vu32()
      g = check_global(gi)
      if gi < @m.n_imp_globals && g.mutable
        d = push(g.type)
        ext(0x23, [d, gi])
      elsif g.type == V128
        d = push(g.type)
        emit_d([OP_GGET2, d, gi])
      elsif wt_ref?(g.type)
        d = push(g.type)
        emit_d([OP_GGETR, d, gi])
      else
        d = push(g.type)
        emit_d([OP_GGET, d, gi])
    elsif op == 0x24
      gi = r.vu32()
      g = check_global(gi)
      w_invalid("global is immutable") if !g.mutable
      a = pop_slot(g.type)
      if gi < @m.n_imp_globals
        ext(0x24, [gi, a])
      elsif g.type == V128
        emit_n([OP_GSET2, gi, a])
      elsif wt_ref?(g.type)
        emit_n([OP_GSETR, gi, a])
      else
        emit_n([OP_GSET, gi, a])
    elsif op == 0x25
      ti = r.vu32()
      tt = check_table(ti)
      a = pop_slot(tt.is64 ? I64 : I32)
      d = push(tt.elem)
      ext(0x25, [ti, d, a])
    elsif op == 0x26
      ti = r.vu32()
      tt = check_table(ti)
      v = pop_slot(tt.elem)
      a = pop_slot(tt.is64 ? I64 : I32)
      ext(0x26, [ti, a, v])
    elsif op >= 0x28 && op <= 0x3e
      instr_mem(op)
    elsif op == 0x3f
      mi = r.vu32()
      mt = check_mem(mi)
      d = push(mt.is64 ? I64 : I32)
      if mi == 0
        emit_d([OP_MSIZE, d, mt.page_log2])
      else
        ext(0x3f, [mi, d])
    elsif op == 0x40
      mi = r.vu32()
      mt = check_mem(mi)
      at = mt.is64 ? I64 : I32
      a = pop_slot(at)
      d = push(at)
      ext(0x40, [mi, d, a])
    elsif op == 0x41
      push_const(I32, r.vs32() & 0xffffffff)
    elsif op == 0x42
      push_const(I64, r.vs64())
    elsif op == 0x43
      push_const(F32, r.vf32())
    elsif op == 0x44
      push_const(F64, r.vf64())
    elsif op >= 0x45 && op <= 0xc4
      instr_num(op)
    elsif op == 0xd0
      ht = r.heap_type()
      d = push(wt_ref(true, ht))
      emit2(OP_REFNULL, d)
    elsif op == 0xd1
      pop_ref()
      a = @pv
      d = push(I32)
      emit_d([OP_ISNULL, d, a])
    elsif op == 0xd2
      fi = r.vu32()
      ft = check_func(fi)
      w_invalid("undeclared function reference") if !@m.declared_funcs.has_key?(fi)
      d = push(wt_ref(false, @m.canon[@m.funcs[fi]]))
      ext(0xd2, [d, fi])
    elsif op == 0xd3
      b = pop_slot(wt_ref(true, HT_EQ))
      a = pop_slot(wt_ref(true, HT_EQ))
      d = push(I32)
      emit_d([OP_REFEQ, d, a, b])
    elsif op == 0xd4
      t = pop_ref()
      a = @pv
      nt = t == BOT ? BOT : w_nonnull(t)
      emit2(OP_ASNONNULL, a)
      push_alias(nt == BOT ? wt_ref(false, HT_BOT) : nt, a)
    elsif op == 0xd5 || op == 0xd6
      instr_br_on_null(op)
    elsif op == 0x06 || op == 0x07 || op == 0x08 || op == 0x09 || op == 0x0a || op == 0x18 || op == 0x19 || op == 0x1f
      instr_eh(op)
    elsif op == 0xfb
      instr_gc(r.vu32())
    elsif op == 0xfc
      instr_fc(r.vu32())
    elsif op == 0xfd
      instr_simd(r.vu32())
    elsif op == 0xfe
      instr_atomic(r.vu32())
    else
      w_malformed("illegal opcode " + op.to_s)
    nil

  -> pop_params(types)
    k = types.size - 1
    @saved = []
    while k >= 0
      pop(types[k])
      @saved.push([@pk, @pv])
      k -= 1
    nil

  # Re-push block params after push_ctl (they keep their kinds; materialized by caller).
  -> repush(types)
    n = types.size
    k = 0
    while k < n
      s = @saved[n - 1 - k]
      push_entry(types[k], s[0], s[1])
      k += 1
    # entries were materialized before; make sure they sit in their homes
    i = sp() - n
    while i < sp()
      materialize(i) if @st_k[i] != K_SLOT || @st_v[i] != @st_h[i]
      i += 1
    nil

  -> instr_end
    f = @ctl[@ctl.size - 1]
    if f.kind == 3
      # if without else: params must match results
      w_invalid("type mismatch: if without else") if !w_types_sub?(f.params, f.results)
    if f.kind == 0
      n = f.results.size
      j = sp() - n
      j = f.height if j < f.height
      while j < sp()
        materialize(j) if @st_k[j] != K_SLOT || @st_v[j] != @st_h[j]
        j += 1
      end_frame()
      emit1(OP_RET)
      @ctl.pop
      bind_label()
      @dead = false
      patch_here(f.fixups)
      resolve_pending(f)
      emit1(OP_RET)
      return nil
    end_frame()
    @try_end = pc()
    @ctl.pop
    bind_label()
    @dead = f.pdead
    if f.kind == 3
      patch_here(f.else_fix)
    patch_here(f.fixups)
    resolve_pending(f)
    @init = f.init_save
    if f.kind == 5 || f.kind == 6 || f.kind == 7
      finish_try(f)
    # results now live in the frame's slots
    while sp() > f.height
      pop_raw()
    push_results(f.results)
    nil

  # Handlers whose catch label is frame f get its (now known) end address.
  -> resolve_pending(f)
    keep = []
    t = pc()
    @pending_handlers.each ->(e)
      if e[1] == f
        e[0].target = t
      else
        keep.push(e)
    @pending_handlers = keep
    nil

  -> check_tail_results(ft)
    w_invalid("type mismatch: tail call results") if ft.results.size != @results.size
    i = 0
    while i < ft.results.size
      w_invalid("type mismatch: tail call results") if !wt_sub?(ft.results[i], @results[i])
      i += 1
    nil

  -> args_to_homes(ft)
    n = ft.params.size
    f = @ctl[@ctl.size - 1]
    i = sp() - n
    # type check
    k = n - 1
    while k >= 0
      j = i + k
      if j < f.height
        w_invalid("type mismatch: stack underflow") if !f.unreachable
      else
        w_invalid("type mismatch: call argument") if !wt_sub?(@st_t[j], ft.params[k])
      k -= 1
    j = i < f.height ? f.height : i
    while j < sp()
      materialize(j) if @st_k[j] != K_SLOT || @st_v[j] != @st_h[j]
      j += 1
    base = i >= 0 && i < sp() ? @st_h[i] : @top
    # pop them
    while sp() > (i < f.height ? f.height : i)
      pop_raw()
    base

  -> do_call(fi, ft, tail)
    base = args_to_homes(ft)
    base = @top if base > @top
    if tail
      if fi < @m.n_imp_funcs
        ext(0x12, [fi, base, ft.param_slots])
      else
        @calls.push(pc() + 1) if !@dead
        emit_n([OP_RET_CALL, fi, ft.param_slots, base])
      set_unreachable()
      return nil
    if fi < @m.n_imp_funcs
      emit_n([OP_CALL_IMPORT, fi, base, 0])
      @fsize_fix.push(pc() - 1) if !@dead && @fsize_fix != nil
    else
      @calls.push(pc() + 1) if !@dead
      emit_n([OP_CALL, fi, base])
    push_results(ft.results)
    # results start at base
    nil

  -> do_call_indirect(ti, ft, tab, tail)
    a = pop_slot(@m.tables[tab].is64 ? I64 : I32)
    base = args_to_homes(ft)
    canon = @m.canon[ti]
    if tail
      ext(0x13, [canon, base, a, tab, ft.param_slots])
      set_unreachable()
      return nil
    emit_n([OP_CALL_IND, tab, canon, base, a, 0])
    @fsize_fix.push(pc() - 1) if !@dead
    push_results(ft.results)

  -> do_call_ref(ti, ft, tail)
    t = pop(wt_ref(true, @m.canon[ti]))
    a = @pk == K_SLOT ? @pv : 0
    base = args_to_homes(ft)
    canon = @m.canon[ti]
    if tail
      ext(0x15, [canon, base, a, ft.param_slots])
      set_unreachable()
      return nil
    emit_n([OP_CALL_REF, canon, base, a, 0])
    @fsize_fix.push(pc() - 1) if !@dead
    push_results(ft.results)

  -> local_set(li, tee)
    t = @ltypes[li]
    ls = @lslot[li]
    pop(t)
    k = @pk
    v = @pv
    if !@dead
      if k == K_CONST
        materialize_aliases(ls)
        emit_const(ls, t, v)
      elsif v == ls
        nil
      else
        # retarget the producing op when the value was just computed into its home
        alias = false
        i = 0
        while i < sp()
          alias = true if @st_k[i] == K_SLOT && @st_v[i] == ls
          i += 1
        if !alias && @last_pos >= 0 && v == @top && @code[@last_pos + 1] == v
          @code[@last_pos + 1] = ls
        else
          materialize_aliases(ls)
          emit_move(t, ls, v)
    @init[li] = true
    if tee
      push_alias(t, ls)
    @last_pos = -1
    nil

  -> instr_select(op)
    t = nil
    if op == 0x1c
      n = @r.vu32()
      w_invalid("invalid result arity") if n != 1
      t = @r.val_type()
    cond = pop_slot(I32)
    if t == nil
      # untyped select: numeric/vector operands only
      t2 = pop(nil)
      k2 = @pk
      v2 = @pv
      b = k2 == K_CONST ? const_to_slot(t2, v2) : v2
      t1 = pop(nil)
      k1 = @pk
      v1 = @pv
      a = k1 == K_CONST ? const_to_slot(t1, v1) : v1
      w_invalid("type mismatch: select operands") if (wt_ref?(t1) && t1 != BOT) || (wt_ref?(t2) && t2 != BOT)
      w_invalid("type mismatch: select operands") if t1 != t2 && t1 != BOT && t2 != BOT
      rt = t1 == BOT ? t2 : t1
    else
      b = pop_slot(t)
      a = pop_slot(t)
      rt = t
    d = push(rt)
    if rt == V128
      emit_d([OP_SELECT2, d, a, b, cond])
    elsif wt_ref?(rt)
      emit_d([OP_SELECTR, d, a, b, cond])
    else
      emit_d([OP_SELECT, d, a, b, cond])

  # A constant materialised into a scratch slot above the stack top.
  -> const_to_slot(t, v)
    s = @top + 2
    @maxs = s + 2 if s + 2 > @maxs
    # use the home of where it was: the caller has popped it, so @top is its home
    emit_const(@top, t, v)
    @top

  -> instr_br_table
    r = @r
    n = r.vu32()
    w_malformed("br_table too long") if n > 1000000
    ls = []
    k = 0
    while k <= n
      ls.push(r.vu32())
      k += 1
    a = pop_slot(I32)
    # arity checks
    dflt = label(ls[n])
    arity = dflt.label_types.size
    ls.each ->(d)
      f = label(d)
      lt = f.label_types
      w_invalid("type mismatch: br_table arity") if lt.size != arity
      check_label_values(lt)
    if !@dead
      materialize_top(arity)
      tpos = pc() + 3
      emit_n([OP_BR_TABLE, a, n])
      k = 0
      while k <= n
        @code.push(-1)
        k += 1
      # stubs
      k = 0
      while k <= n
        f = label(ls[k])
        lt = f.label_types
        if needs_moves?(f, lt)
          @code[tpos + k] = pc()
          branch_moves(f, lt)
          jump_to(f, [OP_JMP])
        elsif f.kind == 2
          @code[tpos + k] = f.loop_pc
        else
          f.fixups.push(tpos + k)
        k += 1
    set_unreachable()

  -> instr_br_on_null(op)
    d = @r.vu32()
    f = label(d)
    t = pop_ref()
    a = @pk == K_SLOT ? @pv : 0
    nt = t == BOT ? wt_ref(false, HT_BOT) : w_nonnull(t)
    lt = f.label_types
    if op == 0xd5
      check_label_values(lt)
      retype_top(lt)
      if !@dead
        if needs_moves?(f, lt)
          tmp = WCtl.new(1, [], [], 0, 0)
          jump_to(tmp, [OP_BRNONNULL, a])
          branch_moves(f, lt)
          jump_to(f, [OP_JMP])
          bind_label()
          patch_here(tmp.fixups)
        else
          jump_to(f, [OP_BRNULL, a])
      push_alias(nt, a)
    else
      # br_on_non_null: label's last type must be a supertype of the non-null ref
      w_invalid("type mismatch: br_on_non_null") if lt.size == 0
      w_invalid("type mismatch: br_on_non_null") if !wt_sub?(nt, lt[lt.size - 1])
      push_alias(nt, a)
      check_label_values(lt)
      retype_top(lt)
      if !@dead
        if needs_moves?(f, lt)
          tmp = WCtl.new(1, [], [], 0, 0)
          jump_to(tmp, [OP_BRNULL, a])
          branch_moves(f, lt)
          jump_to(f, [OP_JMP])
          bind_label()
          patch_here(tmp.fixups)
        else
          jump_to(f, [OP_BRNONNULL, a])
      pop(nil)

  # ---- memory ----

  -> instr_mem(op)
    # [natural log2, value type, is store, op]
    if op == 0x28
      ld(2, I32, OP_LD32)
    elsif op == 0x29
      ld(3, I64, OP_LD64)
    elsif op == 0x2a
      ld(2, F32, OP_LD32)
    elsif op == 0x2b
      ld(3, F64, OP_LD64)
    elsif op == 0x2c
      ld(0, I32, OP_LD8S32)
    elsif op == 0x2d
      ld(0, I32, OP_LD8U)
    elsif op == 0x2e
      ld(1, I32, OP_LD16S32)
    elsif op == 0x2f
      ld(1, I32, OP_LD16U)
    elsif op == 0x30
      ld(0, I64, OP_LD8S64)
    elsif op == 0x31
      ld(0, I64, OP_LD8U)
    elsif op == 0x32
      ld(1, I64, OP_LD16S64)
    elsif op == 0x33
      ld(1, I64, OP_LD16U)
    elsif op == 0x34
      ld(2, I64, OP_LD32S64)
    elsif op == 0x35
      ld(2, I64, OP_LD32)
    elsif op == 0x36
      st(2, I32, OP_ST32)
    elsif op == 0x37
      st(3, I64, OP_ST64)
    elsif op == 0x38
      st(2, F32, OP_ST32)
    elsif op == 0x39
      st(3, F64, OP_ST64)
    elsif op == 0x3a
      st(0, I32, OP_ST8)
    elsif op == 0x3b
      st(1, I32, OP_ST16)
    elsif op == 0x3c
      st(0, I64, OP_ST8)
    elsif op == 0x3d
      st(1, I64, OP_ST16)
    elsif op == 0x3e
      st(2, I64, OP_ST32)
    nil

  # Memory operand checks for memory64 / huge offsets. Returns the effective offset to
  # encode, or -1 when the access always traps.
  -> mem_prep(mi, a, off)
    mt = @m.mems[mi]
    if mt.is64
      emit2(OP_CHK64, a)
      return -1 if off < 0 || off > 281474976710656
    off

  -> ld(natural, t, opc)
    ma = memarg(natural)
    mi = ma[0]
    at = addr_type(mi)
    a = pop_slot(at)
    d = push(t)
    if mi != 0
      ext(0x10000 + opc, [mi, d, a, ma[1]])
      return nil
    off = mem_prep(mi, a, ma[1])
    if off < 0
      emit2(OP_TRAP, 5)
    else
      emit_d([opc, d, a, off])

  -> st(natural, t, opc)
    ma = memarg(natural)
    mi = ma[0]
    at = addr_type(mi)
    v = pop_slot(t)
    a = pop_slot(at)
    if mi != 0
      ext(0x10000 + opc, [mi, a, v, ma[1]])
      return nil
    off = mem_prep(mi, a, ma[1])
    if off < 0
      emit2(OP_TRAP, 5)
    else
      emit_n([opc, a, v, off])

  # ---- numeric ----

  -> unop(ta, tr, opc)
    a = pop_slot(ta)
    d = push(tr)
    emit_d([opc, d, a])

  # Binary op; imm_op (or -1) is used when the right operand is a constant.
  -> binop(t, tr, opc, imm_op)
    pop(t)
    bk = @pk
    bv = @pv
    a = pop_slot(t)
    if bk == K_CONST && imm_op >= 0
      d = push(tr)
      emit_d([imm_op, d, a, bv])
      return nil
    b = bv
    if bk == K_CONST
      # materialise b into its home (which is just above a's home)
      b = @top + wt_slots(t)
      @maxs = b + 1 if b + 1 > @maxs
      emit_const(b, t, bv)
    d = push(tr)
    emit_d([opc, d, a, b])

  # Integer compare: becomes a pending compare (fusable with br_if / if).
  -> cmpop(t, c)
    pop(t)
    bk = @pk
    bv = @pv
    pop(t)
    ak = @pk
    av = @pv
    if ak == K_CONST && bk != K_CONST
      # swap so the constant is the immediate
      c = CMP_SWAP[c]
      tk = ak
      tv = av
      ak = bk
      av = bv
      bk = tk
      bv = tv
    if ak == K_CONST
      av = const_to_slot(t, av)
    if t == I32 && bk == K_CONST
      bv = bv & 0xffffffff
    push_cmp(c, av, bk == K_CONST ? 1 : 0, bv)

  -> instr_num(op)
    if op == 0x45
      pop(I32)
      if @pk == K_CONST
        push_const(I32, @pv == 0 ? 1 : 0)
      else
        push_cmp(CMP_EQ, @pv, 1, 0)
    elsif op >= 0x46 && op <= 0x4f
      c = [CMP_EQ, CMP_NE, CMP_LTS32, CMP_LTU, CMP_GTS32, CMP_GTU, CMP_LES32, CMP_LEU, CMP_GES32, CMP_GEU][op - 0x46]
      cmpop(I32, c)
    elsif op == 0x50
      pop(I64)
      if @pk == K_CONST
        push_const(I32, @pv == 0 ? 1 : 0)
      else
        push_cmp(CMP_EQ, @pv, 1, 0)
    elsif op >= 0x51 && op <= 0x5a
      c = [CMP_EQ, CMP_NE, CMP_LTS64, CMP_LTU, CMP_GTS64, CMP_GTU, CMP_LES64, CMP_LEU, CMP_GES64, CMP_GEU][op - 0x51]
      cmpop(I64, c)
    elsif op >= 0x5b && op <= 0x60
      binop(F32, I32, OP_FEQ32 + (op - 0x5b), -1)
    elsif op >= 0x61 && op <= 0x66
      binop(F64, I32, OP_FEQ64 + (op - 0x61), -1)
    elsif op == 0x67
      unop(I32, I32, OP_CLZ32)
    elsif op == 0x68
      unop(I32, I32, OP_CTZ32)
    elsif op == 0x69
      unop(I32, I32, OP_POPCNT)
    elsif op == 0x6a
      binop(I32, I32, OP_ADD32, OP_ADDI32)
    elsif op == 0x6b
      sub_op(I32)
    elsif op == 0x6c
      binop(I32, I32, OP_MUL32, OP_MULI32)
    elsif op == 0x6d
      binop(I32, I32, OP_DIVS32, -1)
    elsif op == 0x6e
      binop(I32, I32, OP_DIVU32, -1)
    elsif op == 0x6f
      binop(I32, I32, OP_REMS32, -1)
    elsif op == 0x70
      binop(I32, I32, OP_REMU32, -1)
    elsif op == 0x71
      binop(I32, I32, OP_AND, OP_ANDI)
    elsif op == 0x72
      binop(I32, I32, OP_OR, OP_ORI)
    elsif op == 0x73
      binop(I32, I32, OP_XOR, OP_XORI)
    elsif op == 0x74
      shift_op(I32, OP_SHL32, OP_SHLI32, 31)
    elsif op == 0x75
      shift_op(I32, OP_SHRS32, OP_SHRSI32, 31)
    elsif op == 0x76
      shift_op(I32, OP_SHRU32, OP_SHRUI32, 31)
    elsif op == 0x77
      binop(I32, I32, OP_ROTL32, -1)
    elsif op == 0x78
      binop(I32, I32, OP_ROTR32, -1)
    elsif op == 0x79
      unop(I64, I64, OP_CLZ64)
    elsif op == 0x7a
      unop(I64, I64, OP_CTZ64)
    elsif op == 0x7b
      unop(I64, I64, OP_POPCNT)
    elsif op == 0x7c
      binop(I64, I64, OP_ADD64, OP_ADDI64)
    elsif op == 0x7d
      sub_op(I64)
    elsif op == 0x7e
      binop(I64, I64, OP_MUL64, OP_MULI64)
    elsif op == 0x7f
      binop(I64, I64, OP_DIVS64, -1)
    elsif op == 0x80
      binop(I64, I64, OP_DIVU64, -1)
    elsif op == 0x81
      binop(I64, I64, OP_REMS64, -1)
    elsif op == 0x82
      binop(I64, I64, OP_REMU64, -1)
    elsif op == 0x83
      binop(I64, I64, OP_AND, OP_ANDI)
    elsif op == 0x84
      binop(I64, I64, OP_OR, OP_ORI)
    elsif op == 0x85
      binop(I64, I64, OP_XOR, OP_XORI)
    elsif op == 0x86
      shift_op(I64, OP_SHL64, OP_SHLI64, 63)
    elsif op == 0x87
      shift_op(I64, OP_SHRS64, OP_SHRSI64, 63)
    elsif op == 0x88
      shift_op(I64, OP_SHRU64, OP_SHRUI64, 63)
    elsif op == 0x89
      binop(I64, I64, OP_ROTL64, -1)
    elsif op == 0x8a
      binop(I64, I64, OP_ROTR64, -1)
    elsif op >= 0x8b && op <= 0x91
      unop(F32, F32, OP_FABS32 + (op - 0x8b))
    elsif op >= 0x92 && op <= 0x98
      binop(F32, F32, OP_FADD32 + (op - 0x92), -1)
    elsif op >= 0x99 && op <= 0x9f
      unop(F64, F64, OP_FABS64 + (op - 0x99))
    elsif op >= 0xa0 && op <= 0xa6
      binop(F64, F64, OP_FADD64 + (op - 0xa0), -1)
    elsif op == 0xa7
      unop(I64, I32, OP_WRAP)
    elsif op == 0xa8
      unop(F32, I32, OP_TRUNC_F32_S32)
    elsif op == 0xa9
      unop(F32, I32, OP_TRUNC_F32_U32)
    elsif op == 0xaa
      unop(F64, I32, OP_TRUNC_F64_S32)
    elsif op == 0xab
      unop(F64, I32, OP_TRUNC_F64_U32)
    elsif op == 0xac
      unop(I32, I64, OP_EXTS32)
    elsif op == 0xad
      reinterpret(I32, I64)
    elsif op == 0xae
      unop(F32, I64, OP_TRUNC_F32_S64)
    elsif op == 0xaf
      unop(F32, I64, OP_TRUNC_F32_U64)
    elsif op == 0xb0
      unop(F64, I64, OP_TRUNC_F64_S64)
    elsif op == 0xb1
      unop(F64, I64, OP_TRUNC_F64_U64)
    elsif op == 0xb2
      unop(I32, F32, OP_CVT_S32_F32)
    elsif op == 0xb3
      unop(I32, F32, OP_CVT_U32_F32)
    elsif op == 0xb4
      unop(I64, F32, OP_CVT_S64_F32)
    elsif op == 0xb5
      unop(I64, F32, OP_CVT_U64_F32)
    elsif op == 0xb6
      unop(F64, F32, OP_DEMOTE)
    elsif op == 0xb7
      unop(I32, F64, OP_CVT_S32_F64)
    elsif op == 0xb8
      unop(I32, F64, OP_CVT_U32_F64)
    elsif op == 0xb9
      unop(I64, F64, OP_CVT_S64_F64)
    elsif op == 0xba
      unop(I64, F64, OP_CVT_U64_F64)
    elsif op == 0xbb
      unop(F32, F64, OP_PROMOTE)
    elsif op == 0xbc
      reinterpret(F32, I32)
    elsif op == 0xbd
      reinterpret(F64, I64)
    elsif op == 0xbe
      reinterpret(I32, F32)
    elsif op == 0xbf
      reinterpret(I64, F64)
    elsif op == 0xc0
      unop(I32, I32, OP_EXT8S32)
    elsif op == 0xc1
      unop(I32, I32, OP_EXT16S32)
    elsif op == 0xc2
      unop(I64, I64, OP_EXT8S64)
    elsif op == 0xc3
      unop(I64, I64, OP_EXT16S64)
    elsif op == 0xc4
      unop(I64, I64, OP_EXTS32)
    nil

  # Same bits, new type: no code (i64.extend_i32_u too, since i32 slots are zero-extended).
  -> reinterpret(ta, tr)
    pop(ta)
    k = @pk
    v = @pv
    push_entry(tr, k, v)

  -> sub_op(t)
    pop(t)
    bk = @pk
    bv = @pv
    if bk == K_CONST
      a = pop_slot(t)
      d = push(t)
      nk = t == I32 ? ((0 - bv) & 0xffffffff) : ((0 - bv) ## i64)
      emit_d([t == I32 ? OP_ADDI32 : OP_ADDI64, d, a, nk])
      return nil
    push_entry(t, bk, bv)
    binop(t, t, t == I32 ? OP_SUB32 : OP_SUB64, -1)

  -> shift_op(t, opc, imm_op, mask)
    pop(t)
    bk = @pk
    bv = @pv
    push_entry(t, bk, bv)
    if bk == K_CONST
      binop(t, t, opc, imm_op)
      # mask the immediate
      @code[@code.size - 1] = bv & mask if !@dead
    else
      binop(t, t, opc, -1)

  # ---- 0xFC prefix ----

  -> instr_fc(sub)
    r = @r
    if sub <= 7
      ta = (sub == 0 || sub == 1 || sub == 4 || sub == 5) ? F32 : F64
      tr = sub <= 3 ? I32 : I64
      unop(ta, tr, OP_SAT_F32_S32 + sub)
    elsif sub == 8
      di = r.vu32()
      mi = r.vu32()
      at = addr_type(mi)
      check_data(di)
      n = pop_slot(I32)
      s = pop_slot(I32)
      d = pop_slot(at)
      ext(0xfc0008, [mi, di, d, s, n])
    elsif sub == 9
      di = r.vu32()
      check_data(di)
      ext(0xfc0009, [di])
    elsif sub == 10
      m1 = r.vu32()
      m2 = r.vu32()
      a1 = addr_type(m1)
      a2 = addr_type(m2)
      nt = (a1 == I64 && a2 == I64) ? I64 : I32
      n = pop_slot(nt)
      s = pop_slot(a2)
      d = pop_slot(a1)
      if m1 == 0 && m2 == 0
        emit_n([OP_MCOPY, d, s, n])
      else
        ext(0xfc000a, [m1, m2, d, s, n])
    elsif sub == 11
      mi = r.vu32()
      at = addr_type(mi)
      n = pop_slot(at)
      v = pop_slot(I32)
      d = pop_slot(at)
      if mi == 0
        emit_n([OP_MFILL, d, v, n])
      else
        ext(0xfc000b, [mi, d, v, n])
    elsif sub == 12
      ei = r.vu32()
      ti = r.vu32()
      e = check_elem(ei)
      tt = check_table(ti)
      w_invalid("type mismatch: elem segment type") if !wt_sub?(e.type, tt.elem)
      n = pop_slot(I32)
      s = pop_slot(I32)
      d = pop_slot(tt.is64 ? I64 : I32)
      ext(0xfc000c, [ti, ei, d, s, n])
    elsif sub == 13
      ei = r.vu32()
      check_elem(ei)
      ext(0xfc000d, [ei])
    elsif sub == 14
      t1 = r.vu32()
      t2 = r.vu32()
      tt1 = check_table(t1)
      tt2 = check_table(t2)
      w_invalid("type mismatch: table.copy") if !wt_sub?(tt2.elem, tt1.elem)
      nt = (tt1.is64 && tt2.is64) ? I64 : I32
      n = pop_slot(nt)
      s = pop_slot(tt2.is64 ? I64 : I32)
      d = pop_slot(tt1.is64 ? I64 : I32)
      ext(0xfc000e, [t1, t2, d, s, n])
    elsif sub == 15
      ti = r.vu32()
      tt = check_table(ti)
      at = tt.is64 ? I64 : I32
      n = pop_slot(at)
      v = pop_slot(tt.elem)
      d = push(at)
      ext(0xfc000f, [ti, d, v, n])
    elsif sub == 16
      ti = r.vu32()
      tt = check_table(ti)
      d = push(tt.is64 ? I64 : I32)
      ext(0xfc0010, [ti, d])
    elsif sub == 17
      ti = r.vu32()
      tt = check_table(ti)
      at = tt.is64 ? I64 : I32
      n = pop_slot(at)
      v = pop_slot(tt.elem)
      d = pop_slot(at)
      ext(0xfc0011, [ti, d, v, n])
    else
      w_malformed("illegal opcode 0xfc " + sub.to_s)
    nil

  # ---- exceptions ----

  -> instr_eh(op)
    r = @r
    if op == 0x08
      ti = r.vu32()
      tt = check_tag(ti)
      w_invalid("type mismatch: tag results") if tt.results.size != 0
      base = args_to_homes(tt)
      ext(0x08, [ti, base])
      set_unreachable()
    elsif op == 0x0a
      a = pop_slot(EXNREF)
      ext(0x0a, [a])
      set_unreachable()
    elsif op == 0x1f
      sig = block_sig(r.block_type())
      n = r.vu32()
      cs = []
      k = 0
      while k < n
        kind = r.byte()
        w_malformed("malformed catch clause") if kind > 3
        tag = kind < 2 ? r.vu32() : -1
        lab = r.vu32()
        cs.push([kind, tag, lab])
        k += 1
      # validate catch labels against the enclosing context
      cs.each ->(c)
        f = label(c[2])
        lt = f.label_types
        want = []
        if c[0] < 2
          tt = check_tag(c[1])
          want = tt.params.dup
        want.push(wt_ref(false, HT_EXN)) if c[0] == 1 || c[0] == 3
        w_invalid("type mismatch: catch label") if want.size != lt.size
        i = 0
        while i < want.size
          w_invalid("type mismatch: catch label") if !wt_sub?(want[i], lt[i])
          i += 1
      pop_params(sig[0])
      materialize_all()
      f = push_ctl(5, sig[0], sig[1])
      repush(sig[0])
      bind_label()
      f.handler_start = pc()
      # catch targets refer to frames outside this one: record frame objects
      f.catches = cs.map ->(c) [c[0], c[1], label(c[2] + 1)]
    elsif op == 0x06
      sig = block_sig(r.block_type())
      pop_params(sig[0])
      materialize_all()
      f = push_ctl(6, sig[0], sig[1])
      repush(sig[0])
      bind_label()
      f.handler_start = pc()
      f.catches = []
      f.hidden = hidden_slot()
    elsif op == 0x07 || op == 0x19
      f = @ctl[@ctl.size - 1]
      w_invalid("catch without try") if f.kind != 6 && f.kind != 7
      tag = -1
      tt = nil
      if op == 0x07
        tag = r.vu32()
        tt = check_tag(tag)
      end_frame()
      if !@dead
        jump_to(f, [OP_JMP])
      if f.kind == 6
        f.try_idx = pc()
        f.catches.push([-2, f.handler_start, pc()])
      bind_label()
      @dead = f.pdead
      f.kind = 7
      f.unreachable = false
      while sp() > f.height
        pop_raw()
      f.catches.push([op == 0x07 ? 4 : 5, tag, pc()])
      if tt != nil
        tt.params.each ->(t) push(t)
    elsif op == 0x18
      d = r.vu32()
      f = @ctl[@ctl.size - 1]
      w_invalid("delegate without try") if f.kind != 6
      end_frame()
      @ctl.pop
      tgt = label(d)
      # handler range: the try body
      h = WHandler.new(f.handler_start, pc(), 6, tgt.depth, -1, 0, f.depth)
      @meta.handlers.push(h)
      bind_label()
      @dead = f.pdead
      patch_here(f.fixups)
      resolve_pending(f)
      while sp() > f.height
        pop_raw()
      push_results(f.results)
    elsif op == 0x09
      d = r.vu32()
      f = label(d)
      w_invalid("invalid rethrow label") if f.kind != 7
      ext(0x09, [f.hidden])
      @hidden_fix.push(pc() - 1) if !@dead
      set_unreachable()
    nil

  # Register handlers when a try_table / try ends (inner handlers come first).
  -> finish_try(f)
    if f.kind == 5
      f.catches.each ->(c)
        tf = c[2]
        h = WHandler.new(f.handler_start, @try_end, c[0], c[1], -1, tf.base, f.depth)
        @meta.handlers.push(h)
        # target: the frame's label
        if tf.kind == 2
          h.target = tf.loop_pc
        else
          @pending_handlers.push([h, tf])
    elsif f.kind == 6 || f.kind == 7
      # legacy try: body range ends where the first catch begins
      body_end = f.try_idx >= 0 ? f.try_idx : @try_end
      f.catches.each ->(c)
        if c[0] == 4 || c[0] == 5
          h = WHandler.new(f.handler_start, body_end, c[0], c[1], c[2], f.base, f.depth)
          h.hidden = f.hidden
          @meta.handlers.push(h)
    nil

  # ---- GC ----

  -> struct_type(ti)
    t = check_type(ti)
    w_invalid("type mismatch: not a struct type") if !t.struct?
    t

  -> array_type(ti)
    t = check_type(ti)
    w_invalid("type mismatch: not an array type") if !t.array?
    t

  -> instr_gc(sub)
    r = @r
    sx = 0xfb0000 + sub
    if sub == 0 || sub == 1
      ti = r.vu32()
      t = struct_type(ti)
      if sub == 0
        base = args_to_homes(w_struct_sig(t))
      else
        t.ftypes.each ->(ft) w_invalid("type mismatch: field not defaultable") if !w_defaultable?(ft)
        base = @top
      d = push(wt_ref(false, @m.canon[ti]))
      ext(sx, [ti, d, base])
    elsif sub >= 2 && sub <= 4
      ti = r.vu32()
      fi = r.vu32()
      t = struct_type(ti)
      w_invalid("unknown field") if fi >= t.ftypes.size
      ftt = t.ftypes[fi]
      w_invalid("type mismatch: packed field") if (sub == 2) == wt_packed?(ftt)
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      d = push(wt_unpack(ftt))
      ext(sx, [ti, fi, d, a])
    elsif sub == 5
      ti = r.vu32()
      fi = r.vu32()
      t = struct_type(ti)
      w_invalid("unknown field") if fi >= t.ftypes.size
      w_invalid("field is immutable") if !t.fmuts[fi]
      v = pop_slot(wt_unpack(t.ftypes[fi]))
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      ext(sx, [ti, fi, a, v])
    elsif sub == 6 || sub == 7
      ti = r.vu32()
      t = array_type(ti)
      n = pop_slot(I32)
      v = -1
      if sub == 6
        v = pop_slot(wt_unpack(t.ftypes[0]))
      else
        w_invalid("type mismatch: array element not defaultable") if !w_defaultable?(t.ftypes[0])
      d = push(wt_ref(false, @m.canon[ti]))
      ext(sx, [ti, d, v, n])
    elsif sub == 8
      ti = r.vu32()
      n = r.vu32()
      t = array_type(ti)
      et = wt_unpack(t.ftypes[0])
      ps = []
      k = 0
      while k < n
        ps.push(et)
        k += 1
      sig = WSubType.new(0)
      sig.params = ps
      base = args_to_homes(sig)
      d = push(wt_ref(false, @m.canon[ti]))
      ext(sx, [ti, d, base, n])
    elsif sub == 9 || sub == 10
      ti = r.vu32()
      si = r.vu32()
      t = array_type(ti)
      et = t.ftypes[0]
      if sub == 9
        check_data(si)
        w_invalid("type mismatch: array type is not numeric or vector") if wt_ref?(et)
      else
        e = check_elem(si)
        w_invalid("type mismatch: elem segment type") if !wt_sub?(e.type, et)
      n = pop_slot(I32)
      s = pop_slot(I32)
      d = push(wt_ref(false, @m.canon[ti]))
      ext(sx, [ti, si, d, s, n])
    elsif sub >= 11 && sub <= 13
      ti = r.vu32()
      t = array_type(ti)
      et = t.ftypes[0]
      w_invalid("type mismatch: packed element") if (sub == 11) == wt_packed?(et)
      i = pop_slot(I32)
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      d = push(wt_unpack(et))
      ext(sx, [ti, d, a, i])
    elsif sub == 14
      ti = r.vu32()
      t = array_type(ti)
      w_invalid("array is immutable") if !t.fmuts[0]
      v = pop_slot(wt_unpack(t.ftypes[0]))
      i = pop_slot(I32)
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      ext(sx, [ti, a, i, v])
    elsif sub == 15
      a = pop_slot(wt_ref(true, HT_ARRAY))
      d = push(I32)
      ext(sx, [d, a])
    elsif sub == 16
      ti = r.vu32()
      t = array_type(ti)
      w_invalid("array is immutable") if !t.fmuts[0]
      n = pop_slot(I32)
      v = pop_slot(wt_unpack(t.ftypes[0]))
      i = pop_slot(I32)
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      ext(sx, [ti, a, i, v, n])
    elsif sub == 17
      t1 = r.vu32()
      t2 = r.vu32()
      at1 = array_type(t1)
      at2 = array_type(t2)
      w_invalid("array is immutable") if !at1.fmuts[0]
      w_invalid("type mismatch: array.copy") if !wt_sub?(at2.ftypes[0], at1.ftypes[0]) && !(at1.ftypes[0] == at2.ftypes[0])
      n = pop_slot(I32)
      s = pop_slot(I32)
      b = pop_slot(wt_ref(true, @m.canon[t2]))
      di = pop_slot(I32)
      a = pop_slot(wt_ref(true, @m.canon[t1]))
      ext(sx, [t1, t2, a, di, b, s, n])
    elsif sub == 18 || sub == 19
      ti = r.vu32()
      si = r.vu32()
      t = array_type(ti)
      w_invalid("array is immutable") if !t.fmuts[0]
      et = t.ftypes[0]
      if sub == 18
        check_data(si)
        w_invalid("type mismatch: array type is not numeric or vector") if wt_ref?(et)
      else
        e = check_elem(si)
        w_invalid("type mismatch: elem segment type") if !wt_sub?(e.type, et)
      n = pop_slot(I32)
      s = pop_slot(I32)
      i = pop_slot(I32)
      a = pop_slot(wt_ref(true, @m.canon[ti]))
      ext(sx, [ti, si, a, i, s, n])
    elsif sub >= 20 && sub <= 23
      ht = r.heap_type()
      nullable = sub == 21 || sub == 23
      tt = wt_ref(nullable, ht)
      t = pop_ref()
      a = @pk == K_SLOT ? @pv : 0
      w_invalid("type mismatch: cast to unrelated type") if t != BOT && wt_ht_top(wt_ht(t)) != wt_ht_top(ht) && wt_ht(t) != HT_BOT
      if sub <= 21
        d = push(I32)
        ext(sx, [ht, d, a])
      else
        d = push(tt)
        ext(sx, [ht, d, a])
    elsif sub == 24 || sub == 25
      flags = r.byte()
      w_malformed("malformed br_on_cast flags") if flags > 3
      lab = r.vu32()
      h1 = r.heap_type()
      h2 = r.heap_type()
      t1 = wt_ref((flags & 1) != 0, h1)
      t2 = wt_ref((flags & 2) != 0, h2)
      w_invalid("type mismatch: br_on_cast types") if !wt_sub?(t2, t1)
      f = label(lab)
      lt = f.label_types
      w_invalid("type mismatch: br_on_cast label") if lt.size == 0
      t = pop(t1)
      a = @pk == K_SLOT ? @pv : (@pk == K_CONST ? const_to_slot(t1, @pv) : 0)
      # the type that remains on fallthrough: t1 \ t2
      diff = (flags & 2) != 0 ? w_nonnull(t1) : t1
      if sub == 24
        w_invalid("type mismatch: br_on_cast label") if !wt_sub?(t2, lt[lt.size - 1])
        push_alias(t2, a)
        check_label_values(lt)
        retype_top(lt)
        pop(nil)
        push_alias(diff, a)
        jt = 1
      else
        w_invalid("type mismatch: br_on_cast_fail label") if !wt_sub?(diff, lt[lt.size - 1])
        push_alias(diff, a)
        check_label_values(lt)
        retype_top(lt)
        pop(nil)
        push_alias(t2, a)
        jt = 0
      if !@dead
        # EXT computes the test into a scratch i32 slot, then branch
        tmp = @top
        @maxs = tmp + 1 if tmp + 1 > @maxs
        ext(0xfb0014 + ((flags & 2) != 0 ? 1 : 0), [h2, tmp, a])
        if needs_moves?(f, lt) || true
          # move the value into the label slot when taken
          skip = WCtl.new(1, [], [], 0, 0)
          jump_to(skip, [jt == 1 ? OP_JZ : OP_JNZ, tmp])
          branch_moves(f, lt)
          jump_to(f, [OP_JMP])
          bind_label()
          patch_here(skip.fixups)
    elsif sub == 26
      t = pop(wt_ref(true, HT_EXTERN))
      a = @pk == K_SLOT ? @pv : const_to_slot(t, @pv)
      nt = wt_ref(t == BOT ? false : wt_nullable?(t), HT_ANY)
      d = push(nt)
      ext(sx, [d, a])
    elsif sub == 27
      t = pop(wt_ref(true, HT_ANY))
      a = @pk == K_SLOT ? @pv : const_to_slot(t, @pv)
      nt = wt_ref(t == BOT ? false : wt_nullable?(t), HT_EXTERN)
      d = push(nt)
      ext(sx, [d, a])
    elsif sub == 28
      a = pop_slot(I32)
      d = push(wt_ref(false, HT_I31))
      ext(sx, [d, a])
    elsif sub == 29 || sub == 30
      a = pop_slot(wt_ref(true, HT_I31))
      d = push(I32)
      ext(sx, [d, a])
    else
      w_malformed("illegal opcode 0xfb " + sub.to_s)
    nil

  # ---- atomics (threads) ----

  -> instr_atomic(sub)
    r = @r
    if sub == 3
      b = r.byte()
      w_malformed("malformed atomic.fence") if b != 0
      return nil
    nat = 2
    vt = I32
    kind = 0
    if sub == 0
      nat = 2
    elsif sub == 1
      nat = 2
    elsif sub == 2
      nat = 3
    elsif sub >= 0x10 && sub <= 0x4e
      # loads 0x10-0x16, stores 0x17-0x1d, rmw 0x1e-0x47 (7 ops each x 6), cmpxchg 0x48-0x4e
      j = (sub - 0x10) % 7
      nat = [2, 3, 0, 1, 0, 1, 2][j]
      vt = (j == 0 || j == 2 || j == 3) ? I32 : I64
    else
      w_malformed("illegal opcode 0xfe " + sub.to_s)
    a = r.vu32()
    mi = 0
    if (a & 64) != 0
      a = a - 64
      mi = r.vu32()
    off = r.vu64()
    mt = check_mem(mi)
    w_invalid("alignment must be natural") if a != nat
    w_invalid("offset out of range") if !mt.is64 && (off < 0 || off > 4294967295)
    at = mt.is64 ? I64 : I32
    sx = 0xfe0000 + sub
    if sub == 0
      n = pop_slot(I32)
      p = pop_slot(at)
      d = push(I32)
      ext(sx, [mi, d, p, n, off])
    elsif sub == 1 || sub == 2
      to = pop_slot(I64)
      e = pop_slot(sub == 1 ? I32 : I64)
      p = pop_slot(at)
      d = push(I32)
      ext(sx, [mi, d, p, e, to, off])
    elsif sub <= 0x16
      p = pop_slot(at)
      d = push(vt)
      ext(sx, [mi, d, p, off])
    elsif sub <= 0x1d
      v = pop_slot(vt)
      p = pop_slot(at)
      ext(sx, [mi, p, v, off])
    elsif sub <= 0x47
      v = pop_slot(vt)
      p = pop_slot(at)
      d = push(vt)
      ext(sx, [mi, d, p, v, off])
    else
      rep = pop_slot(vt)
      exp = pop_slot(vt)
      p = pop_slot(at)
      d = push(vt)
      ext(sx, [mi, d, p, exp, rep, off])
    nil

  # ---- SIMD ----

  -> instr_simd(sub)
    wasm_simd_compile(self, @r, sub)

  # helpers used by simd.w
  -> simd_unop(ta, tr, sub)
    a = pop_slot(ta)
    d = push(tr)
    emit_d([OP_VOP, d, a, 0, 0, sub])

  -> simd_binop(ta, tb, tr, sub)
    b = pop_slot(tb)
    a = pop_slot(ta)
    d = push(tr)
    emit_d([OP_VOP, d, a, b, 0, sub])

  -> simd_ternop(t, sub)
    c = pop_slot(t)
    b = pop_slot(t)
    a = pop_slot(t)
    d = push(t)
    emit_d([OP_VOP, d, a, b, c, sub])

  -> simd_lane_op(ta, tr, sub, lane)
    a = pop_slot(ta)
    d = push(tr)
    emit_d([OP_VOP, d, a, lane, 0, sub])

  -> simd_replace(ts, sub, lane)
    b = pop_slot(ts)
    a = pop_slot(V128)
    d = push(V128)
    emit_d([OP_VOP, d, a, b, lane, sub])

  -> simd_const(lo, hi)
    d = push(V128)
    emit_d([OP_CONST2, d, lo, hi])

  -> simd_mem(sub, natural, store, lane)
    ma = memarg(natural)
    mi = ma[0]
    at = addr_type(mi)
    if lane >= 0
      v = pop_slot(V128)
      a = pop_slot(at)
      if store
        ext(0xfd0000 + sub, [mi, a, v, ma[1], lane])
      else
        d = push(V128)
        ext(0xfd0000 + sub, [mi, d, a, ma[1], lane, v])
      return nil
    if store
      v = pop_slot(V128)
      a = pop_slot(at)
      if sub == 11 && mi == 0 && !@m.mems[0].is64
        emit_n([OP_ST128, a, v, ma[1]])
      else
        ext(0xfd0000 + sub, [mi, a, v, ma[1]])
    else
      a = pop_slot(at)
      d = push(V128)
      if sub == 0 && mi == 0 && !@m.mems[0].is64
        emit_d([OP_LD128, d, a, ma[1]])
      else
        ext(0xfd0000 + sub, [mi, d, a, ma[1]])
    nil

  -> dead?
    @dead

-> w_types_eq?(a, b)
  return false if a.size != b.size
  i = 0
  while i < a.size
    return false if a[i] != b[i]
    i += 1
  true

-> w_types_sub?(a, b)
  return false if a.size != b.size
  i = 0
  while i < a.size
    return false if !wt_sub?(a[i], b[i])
    i += 1
  true

-> w_defaultable?(t)
  !wt_ref?(t) || wt_nullable?(t)

-> w_struct_sig(t)
  s = WSubType.new(0)
  s.params = t.ftypes.map ->(x) wt_unpack(x)
  s

-> w_nonnull(t)
  wt_nullable?(t) ? t - NULL_BIT : t
