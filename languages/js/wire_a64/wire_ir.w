# blade/wire_a64/wire_ir — Pure-Tungsten WIRE IR Data Model, Builder & Text Parser.
#
# Mirrors Tungsten's `compiler/lib/wire.w` and `wire_instruction_schema.json` opcodes so
# both standalone `--emit-wire`-style IR text and direct AST->WIRE lowerers (like jsn_t)
# can compile straight to ARM64 machine code without invoking clang or LLVM.

# ---- Value & Type Tags ----
# Types: :i64, :u64, :i32, :u32, :f64, :f32, :f16, :arr, :void, :wval
# Array ebits:
#   108=i8, 8=u8, 116=i16, 16=u16, 33=i32, 32=u32, 66=i64, 64=u64, -16=f16, -32=f32, -64=f64

+ WireInst
  rw :op, :dst, :a, :b, :c, :imm, :fimm, :pred, :ebits, :sym, :args, :t_true, :t_false, :ty

  -> new(@op, @dst = -1, @a = -1, @b = -1, @c = -1)
    @imm = 0
    @fimm = ~0.0
    @pred = nil
    @ebits = 0
    @sym = nil
    @args = nil
    @t_true = -1
    @t_false = -1
    @ty = :i64

+ WireBlock
  rw :id, :name, :insts, :preds, :succs

  -> new(@id, @name)
    @insts = []
    @preds = []
    @succs = []

+ WireFunc
  rw :name, :params, :param_types, :param_ebits, :ret_type, :abi
  rw :blocks, :block_by_name, :cur_block
  rw :next_vreg, :vreg_types, :vreg_names, :name_to_vreg
  rw :slots, :slot_types, :slot_names

  -> new(@name, @params, @param_types, @param_ebits, @ret_type, @abi = :wvalue)
    @blocks = []
    @block_by_name = {}
    @cur_block = nil
    @next_vreg = 0
    @vreg_types = []
    @vreg_names = []
    @name_to_vreg = {}
    @slots = 0
    @slot_types = []
    @slot_names = {}
    # Reserve virtual registers 0..params.size-1 for function parameters
    i = 0
    while i < @params.size
      pt = @param_types[i]
      vr = new_vreg(pt, @params[i])
      i += 1
    entry = new_block("__entry")
    set_block(entry)

  -> new_vreg(ty = :i64, nm = nil)
    id = @next_vreg
    @next_vreg += 1
    @vreg_types.push(ty)
    @vreg_names.push(nm)
    @name_to_vreg[nm] = id if nm != nil
    id

  -> new_slot(ty = :i64, nm = nil)
    id = @slots
    @slots += 1
    @slot_types.push(ty)
    @slot_names[nm] = id if nm != nil
    id

  -> new_block(nm)
    id = @blocks.size
    b = WireBlock.new(id, nm)
    @blocks.push(b)
    @block_by_name[nm] = b
    b

  -> set_block(b)
    @cur_block = b
    b

  -> emit(inst)
    @cur_block.insts.push(inst)
    inst

  -> emit_const_i64(val)
    d = new_vreg(:i64)
    ins = WireInst.new(:const_i64, d)
    ins.imm = val
    emit(ins)
    d

  -> emit_const_f64(val)
    d = new_vreg(:f64)
    ins = WireInst.new(:const_f64, d)
    ins.fimm = val
    ins.ty = :f64
    emit(ins)
    d

  -> emit_load_slot(slot)
    ty = @slot_types[slot]
    op = ty == :f64 ? :load_double : :load_i64
    d = new_vreg(ty)
    ins = WireInst.new(op, d)
    ins.imm = slot
    ins.ty = ty
    emit(ins)
    d

  -> emit_store_slot(slot, val_vreg)
    ty = @slot_types[slot]
    op = ty == :f64 ? :store_double : :store_i64
    ins = WireInst.new(op, -1, val_vreg)
    ins.imm = slot
    ins.ty = ty
    emit(ins)
    nil

  -> emit_un(op, a, ty = :i64)
    d = new_vreg(ty)
    ins = WireInst.new(op, d, a)
    ins.ty = ty
    emit(ins)
    d

  -> emit_bin(op, a, b, ty = :i64)
    d = new_vreg(ty)
    ins = WireInst.new(op, d, a, b)
    ins.ty = ty
    emit(ins)
    d

  -> emit_bin_imm(op, a, imm, ty = :i64)
    d = new_vreg(ty)
    ins = WireInst.new(op, d, a)
    ins.imm = imm
    ins.ty = ty
    emit(ins)
    d

  -> emit_cmp(op, pred, a, b)
    d = new_vreg(:i64)
    ins = WireInst.new(op, d, a, b)
    ins.pred = pred
    ins.ty = :i64
    emit(ins)
    d

  -> emit_sel(op, cond, tv, fv, ty)
    d = new_vreg(ty)
    ins = WireInst.new(op, d, cond, tv, fv)
    ins.ty = ty
    emit(ins)
    d

  -> emit_arr_ptr(arr_vreg, ebits)
    d = new_vreg(:i64)
    ins = WireInst.new(:arr_data_ptr, d, arr_vreg)
    ins.ebits = ebits
    emit(ins)
    d

  -> emit_arr_len(arr_vreg)
    d = new_vreg(:i64)
    ins = WireInst.new(:array_size_raw, d, arr_vreg)
    emit(ins)
    d

  -> emit_ta_get(ptr_vreg, idx_vreg, ebits)
    ty = (ebits == -64 || ebits == -32 || ebits == -16) ? :f64 : :i64
    d = new_vreg(ty)
    ins = WireInst.new(:typed_array_get_inline, d, ptr_vreg, idx_vreg)
    ins.ebits = ebits
    ins.ty = ty
    emit(ins)
    d

  -> emit_ta_set(ptr_vreg, idx_vreg, val_vreg, ebits)
    ins = WireInst.new(:typed_array_set_inline, -1, ptr_vreg, idx_vreg, val_vreg)
    ins.ebits = ebits
    emit(ins)
    nil

  -> emit_br(target_block)
    ins = WireInst.new(:br)
    ins.t_true = target_block.id
    emit(ins)
    nil

  -> emit_cond_br(cond_vreg, tb, fb)
    ins = WireInst.new(:cond_br, -1, cond_vreg)
    ins.t_true = tb.id
    ins.t_false = fb.id
    emit(ins)
    nil

  -> emit_call_c(sym, args_vregs, ret_ty)
    d = new_vreg(ret_ty)
    ins = WireInst.new(ret_ty == :f64 ? :call_c_f64 : :call_direct_i64, d)
    ins.sym = sym
    ins.args = args_vregs
    ins.ty = ret_ty
    emit(ins)
    d

  -> emit_ret(val_vreg)
    op = @ret_type == :f64 ? :ret_f64 : (@ret_type == :void ? :ret_void : :ret_i64)
    ins = WireInst.new(op, -1, val_vreg)
    ins.ty = @ret_type
    emit(ins)
    nil

+ WireModule
  rw :name, :functions

  -> new(@name = "module")
    @functions = []

  -> add_func(wf)
    @functions.push(wf)
    wf

# ---- Text WIRE IR Parser (parses standard WIRE text format into WireModule) ----
# Example syntax:
#   function dot_f32(a:f32[], b:f32[], n:i64) -> f64
#     __entry:
#       %vs.0 = alloca_f64
#       %vs.1 = alloca_i64
#       %p0 = arr_data_ptr %a ebits=-32
#       %p1 = arr_data_ptr %b ebits=-32
#       %c0 = const_f64 0.0
#       store_double %c0 %vs.0
#       %z = const_i64 0
#       store_i64 %z %vs.1
#       br while.cond
#     while.cond:
#       %i = load_i64 %vs.1
#       %cmp = icmp_i64 slt %i %n
#       cond_br %cmp while.body while.end
#     ...

-> wire_ebits_from_type(ts)
  return 108 if ts == "i8[]"
  return 8   if ts == "u8[]"
  return 116 if ts == "i16[]"
  return 16  if ts == "u16[]"
  return 33  if ts == "i32[]"
  return 32  if ts == "u32[]"
  return 66  if ts == "i64[]"
  return 64  if ts == "u64[]"
  return -16 if ts == "f16[]"
  return -32 if ts == "f32[]"
  return -64 if ts == "f64[]"
  0

-> wire_parse_type(ts)
  return :arr if ts.ends_with?("[]")
  return :f64 if ts == "f64" || ts == "double"
  return :f32 if ts == "f32"
  return :f16 if ts == "f16"
  return :u64 if ts == "u64"
  return :i32 if ts == "i32"
  return :u32 if ts == "u32"
  return :void if ts == "void"
  :i64

-> wire_get_vr(wf, vmap, tok, ty)
  return vmap[tok] if vmap[tok] != nil
  id = wf.new_vreg(ty, tok)
  vmap[tok] = id
  id

-> wire_parse_text(src)
  mod = WireModule.new("parsed")
  lines = src.split("\n")
  wf = nil
  vmap = {}
  smap = {}
  bmap = {}
  # Pre-collect functions & labels per function so forward branches resolve cleanly
  fn_lines = []
  cur_fn = nil
  li = 0
  while li < lines.size
    ln = lines[li].strip
    if ln.size > 0 && !ln.starts_with?("#") && !ln.starts_with?(";")
      if ln.starts_with?("function ")
        cur_fn = [ln, []]
        fn_lines.push(cur_fn)
      elsif cur_fn != nil
        cur_fn[1].push(ln)
    li += 1

  fi = 0
  while fi < fn_lines.size
    hdr = fn_lines[fi][0]
    body = fn_lines[fi][1]
    # Parse header: `function NAME(p0:t0, p1:t1) -> ret`
    lp = hdr.index("(")
    rp = hdr.index(")")
    fname = hdr.slice(9, lp - 9).strip
    pstr = hdr.slice(lp + 1, rp - lp - 1).strip
    ar = hdr.index("->")
    rstr = ar != nil ? hdr.slice(ar + 2, hdr.size - ar - 2).strip : "i64"
    pnames = []
    ptypes = []
    pebits = []
    if pstr.size > 0
      pstr.split(",").each ->(part)
        pt = part.strip
        col = pt.index(":")
        if col != nil
          pn = pt.slice(0, col).strip
          tn = pt.slice(col + 1, pt.size - col - 1).strip
        else
          pn = pt
          tn = "i64"
        pnames.push(pn)
        ptypes.push(wire_parse_type(tn))
        pebits.push(wire_ebits_from_type(tn))
    wf = WireFunc.new(fname, pnames, ptypes, pebits, wire_parse_type(rstr), :wvalue)
    vmap = {}
    smap = {}
    bmap = {"__entry" => wf.blocks[0]}
    pi = 0
    while pi < pnames.size
      vmap["%" + pnames[pi]] = pi
      vmap[pnames[pi]] = pi
      pi += 1
    # Pre-register all block labels
    bi = 0
    while bi < body.size
      bl = body[bi]
      if bl.ends_with?(":")
        bn = bl.slice(0, bl.size - 1).strip
        bmap[bn] = wf.new_block(bn) if bmap[bn] == nil
      bi += 1
    # Emit instructions
    bi = 0
    while bi < body.size
      bl = body[bi]
      if bl.ends_with?(":")
        bn = bl.slice(0, bl.size - 1).strip
        wf.set_block(bmap[bn])
        bi += 1
        next
      toks = bl.split(" ").select(->(x) x.size > 0)
      if toks.size == 0
        bi += 1
        next
      dst_nm = nil
      op_idx = 0
      if toks.size >= 3 && toks[1] == "="
        dst_nm = toks[0]
        op_idx = 2
      op_s = toks[op_idx]
      op = op_s.to_sym
      if op == :alloca_i64 || op == :alloca_f64 || op == :alloca_double
        ty = op == :alloca_i64 ? :i64 : :f64
        smap[dst_nm] = wf.new_slot(ty, dst_nm)
      elsif op == :const_i64
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(:const_i64, d)
        ins.imm = toks[op_idx + 1].to_i
        wf.emit(ins)
      elsif op == :const_f64
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(:const_f64, d)
        ins.fimm = toks[op_idx + 1].to_f
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :load_i64 || op == :load_double
        ty = op == :load_double ? :f64 : :i64
        d = wire_get_vr(wf, vmap, dst_nm, ty)
        sl_tok = toks[op_idx + 1]
        sl_tok = sl_tok.slice(4, sl_tok.size - 4) if sl_tok.starts_with?("ptr=")
        smap[sl_tok] = wf.new_slot(ty, sl_tok) if smap[sl_tok] == nil
        ins = WireInst.new(op, d)
        ins.imm = smap[sl_tok]
        ins.ty = ty
        wf.emit(ins)
      elsif op == :store_i64 || op == :store_double
        ty = op == :store_double ? :f64 : :i64
        vtok = toks[op_idx + 1]
        sl_tok = toks[op_idx + 2]
        sl_tok = sl_tok.slice(4, sl_tok.size - 4) if sl_tok.starts_with?("ptr=")
        smap[sl_tok] = wf.new_slot(ty, sl_tok) if smap[sl_tok] == nil
        vv = vmap[vtok]
        if vv == nil
          vv = ty == :f64 ? wf.emit_const_f64(vtok.to_f) : wf.emit_const_i64(vtok.to_i)
        ins = WireInst.new(op, -1, vv)
        ins.imm = smap[sl_tok]
        ins.ty = ty
        wf.emit(ins)
      elsif op == :arr_data_ptr
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        av = wire_get_vr(wf, vmap, toks[op_idx + 1], :arr)
        eb = 0
        if toks.size > op_idx + 2 && toks[op_idx + 2].starts_with?("ebits=")
          eb = toks[op_idx + 2].slice(6, toks[op_idx + 2].size - 6).to_i
        ins = WireInst.new(:arr_data_ptr, d, av)
        ins.ebits = eb
        wf.emit(ins)
      elsif op == :typed_array_get_inline
        eb = toks[op_idx + 3].starts_with?("ebits=") ? toks[op_idx + 3].slice(6, toks[op_idx + 3].size - 6).to_i : toks[op_idx + 3].to_i
        ty = (eb == -64 || eb == -32 || eb == -16) ? :f64 : :i64
        d = wire_get_vr(wf, vmap, dst_nm, ty)
        ins = WireInst.new(:typed_array_get_inline, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64), wire_get_vr(wf, vmap, toks[op_idx + 2], :i64))
        ins.ebits = eb
        ins.ty = ty
        wf.emit(ins)
      elsif op == :typed_array_set_inline
        eb = toks[op_idx + 4].starts_with?("ebits=") ? toks[op_idx + 4].slice(6, toks[op_idx + 4].size - 6).to_i : toks[op_idx + 4].to_i
        vty = (eb == -64 || eb == -32 || eb == -16) ? :f64 : :i64
        ins = WireInst.new(:typed_array_set_inline, -1, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64), wire_get_vr(wf, vmap, toks[op_idx + 2], :i64), wire_get_vr(wf, vmap, toks[op_idx + 3], vty))
        ins.ebits = eb
        wf.emit(ins)
      elsif op == :icmp_i64 || op == :fcmp_f64
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        aty = op == :fcmp_f64 ? :f64 : :i64
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 2], aty), wire_get_vr(wf, vmap, toks[op_idx + 3], aty))
        ins.pred = toks[op_idx + 1].to_sym
        wf.emit(ins)
      elsif op == :br
        lbl = toks[op_idx + 1]
        lbl = lbl.slice(1, lbl.size - 1) if lbl.starts_with?("%")
        wf.emit_br(bmap[lbl])
      elsif op == :cond_br
        cv = wire_get_vr(wf, vmap, toks[op_idx + 1], :i64)
        tl = toks[op_idx + 2]
        fl = toks[op_idx + 3]
        tl = tl.slice(1, tl.size - 1) if tl.starts_with?("%")
        fl = fl.slice(1, fl.size - 1) if fl.starts_with?("%")
        wf.emit_cond_br(cv, bmap[tl], bmap[fl])
      elsif op == :ret_i64 || op == :ret_f64 || op == :ret_void
        if op == :ret_void
          wf.emit_ret(-1)
        else
          rty = op == :ret_f64 ? :f64 : :i64
          wf.emit_ret(wire_get_vr(wf, vmap, toks[op_idx + 1], rty))
      elsif op == :select_i64 || op == :select_f64
        ty = op == :select_f64 ? :f64 : :i64
        d = wire_get_vr(wf, vmap, dst_nm, ty)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64), wire_get_vr(wf, vmap, toks[op_idx + 2], ty), wire_get_vr(wf, vmap, toks[op_idx + 3], ty))
        ins.ty = ty
        wf.emit(ins)
      elsif op == :fadd_f64 || op == :fsub_f64 || op == :fmul_f64 || op == :fdiv_f64 || op == :fmin_f64 || op == :fmax_f64
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :f64), wire_get_vr(wf, vmap, toks[op_idx + 2], :f64))
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :fneg_f64 || op == :fsqrt_f64 || op == :fabs_f64 || op == :ffloor_f64 || op == :fceil_f64
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :f64))
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :sitofp_i64_f64 || op == :uitofp_u64_f64
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64))
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :fptosi_f64_i64 || op == :fptoui_f64_u64 || op == :nanbox_float
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :f64))
        ins.ty = :i64
        wf.emit(ins)
      elsif op == :unbox_float
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64))
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :neg_i64 || op == :sext_i32_i64 || op == :zext_i32_i64 || op == :trunc_i64_i32 || op == :array_size_raw
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64))
        wf.emit(ins)
      elsif toks.size >= op_idx + 3
        # Generic binary i64/i32 ALU op
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64), wire_get_vr(wf, vmap, toks[op_idx + 2], :i64))
        wf.emit(ins)
      bi += 1
    mod.add_func(wf)
    fi += 1
  mod
