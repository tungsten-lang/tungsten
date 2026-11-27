# cinder/wire_ir — Pure-Tungsten WIRE IR Data Model, Builder & Text Parser.

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

  -> clone
    cp = WireInst.new(@op, @dst, @a, @b, @c)
    cp.imm = @imm
    cp.fimm = @fimm
    cp.pred = @pred
    cp.ebits = @ebits
    cp.sym = @sym
    if @args != nil
      na = []
      i = 0
      while i < @args.size
        na.push(@args[i])
        i += 1
      cp.args = na
    cp.t_true = @t_true
    cp.t_false = @t_false
    cp.ty = @ty
    cp

+ WireBlock
  rw :id, :name, :insts, :preds, :succs

  -> new(@id, @name)
    @insts = []
    @preds = []
    @succs = []

+ WireFunc
  rw :name, :params, :param_types, :param_ebits, :ret_type, :abi, :inline_hint
  rw :blocks, :block_by_name, :cur_block
  rw :next_vreg, :vreg_types, :vreg_names, :name_to_vreg
  rw :slots, :slot_types, :slot_names

  -> new(@name, @params, @param_types, @param_ebits, @ret_type, @abi = :wvalue)
    @inline_hint = :default
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
    i = 0
    while i < @params.size
      pt = @param_types[i]
      new_vreg(pt, @params[i])
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

  # Carry, borrow, and 64x64->128 high-multiply primitives
  -> emit_addcarry_u64(a, b)
    emit_bin(:addcarry_u64, a, b, :i64)

  -> emit_subborrow_u64(a, b)
    emit_bin(:subborrow_u64, a, b, :i64)

  -> emit_mulhi_u64(a, b)
    emit_bin(:mulhi_u64, a, b, :i64)

  -> emit_urem_u64(a, b)
    emit_bin(:urem_i64, a, b, :i64)

  -> emit_fmadd_f64(a, b, c)
    emit_sel(:fmadd_f64, a, b, c, :f64)

  -> emit_adds_u64(a, b)
    emit_bin(:adds_u64, a, b, :i64)

  -> emit_adcs_u64(a, b)
    emit_bin(:adcs_u64, a, b, :i64)

  -> emit_cset_carry_u64
    d = new_vreg(:i64)
    emit(WireInst.new(:cset_carry_u64, d))
    d

  -> emit_subs_u64(a, b)
    emit_bin(:subs_u64, a, b, :i64)

  -> emit_sbcs_u64(a, b)
    emit_bin(:sbcs_u64, a, b, :i64)

  -> emit_cset_borrow_u64
    d = new_vreg(:i64)
    emit(WireInst.new(:cset_borrow_u64, d))
    d

  # Raw unaligned byte-offset memory accesses (`*(ptr + byte_off)`) & bit-scan intrinsics
  # `ebits`: 8 (u8), 108 (i8), 16 (u16), 116 (i16), 32 (u32), 33 (i32), 64 (u64/i64), -64 (f64)
  -> emit_raw_load(ptr_vreg, byte_off_vreg, ebits)
    ty = ebits == -64 ? :f64 : :i64
    d = new_vreg(ty)
    ins = WireInst.new(:raw_load, d, ptr_vreg, byte_off_vreg)
    ins.ebits = ebits
    ins.ty = ty
    emit(ins)
    d

  -> emit_raw_store(ptr_vreg, byte_off_vreg, val_vreg, ebits)
    ins = WireInst.new(:raw_store, -1, ptr_vreg, byte_off_vreg, val_vreg)
    ins.ebits = ebits
    emit(ins)
    nil

  -> emit_ctz_i64(a)
    emit_un(:ctz_i64, a, :i64)

  -> emit_clz_i64(a)
    emit_un(:clz_i64, a, :i64)

  -> clone
    np = []; npt = []; npe = []
    i = 0
    while i < @params.size
      np.push(@params[i]); npt.push(@param_types[i]); npe.push(@param_ebits[i])
      i += 1
    cp = WireFunc.new(@name, np, npt, npe, @ret_type, @abi)
    cp.inline_hint = @inline_hint
    cp.blocks = []
    cp.block_by_name = {}
    bi = 0
    while bi < @blocks.size
      ob = @blocks[bi]
      nb = WireBlock.new(ob.id, ob.name)
      ii = 0
      while ii < ob.insts.size
        nb.insts.push(ob.insts[ii].clone())
        ii += 1
      cp.blocks.push(nb)
      cp.block_by_name[ob.name] = nb
      bi += 1
    cp.cur_block = cp.blocks.size > 0 ? cp.blocks[cp.blocks.size - 1] : nil
    cp.next_vreg = @next_vreg
    cp.vreg_types = []
    cp.vreg_names = []
    vi = 0
    while vi < @vreg_types.size
      cp.vreg_types.push(@vreg_types[vi])
      cp.vreg_names.push(@vreg_names[vi])
      vi += 1
    cp.name_to_vreg = {}
    @name_to_vreg.keys.each ->(k) cp.name_to_vreg[k] = @name_to_vreg[k]
    cp.slots = @slots
    cp.slot_types = []
    si = 0
    while si < @slot_types.size
      cp.slot_types.push(@slot_types[si])
      si += 1
    cp.slot_names = {}
    @slot_names.keys.each ->(k) cp.slot_names[k] = @slot_names[k]
    cp

+ WireModule
  rw :name, :functions

  -> new(@name = "module")
    @functions = []

  -> add_func(wf)
    @functions.push(wf)
    wf

  -> find_func(nm)
    i = 0
    while i < @functions.size
      return @functions[i] if @functions[i].name == nm
      i += 1
    nil

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

# Shift factor `log2(elem_bytes)` for `WArray->start` byte offset calculation
-> wire_ebits_shift(eb)
  return 0 if eb == 8 || eb == 108
  return 1 if eb == 16 || eb == 116 || eb == -16
  return 2 if eb == 32 || eb == 33 || eb == -32
  3

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

G_WIRE_JIT_SYMS = {}

-> wire_register_jit_sym(nm, fp)
  G_WIRE_JIT_SYMS[nm] = fp
  fp

-> wire_lookup_jit_sym(nm)
  v = G_WIRE_JIT_SYMS[nm]
  v != nil ? v : 0

-> wire_parse_text(src)
  mod = WireModule.new("parsed")
  lines = src.split("\n")
  fn_lines = []
  cur_fn = nil
  li = 0
  while li < lines.size
    ln = lines[li].strip
    if ln.size > 0
      if ln == "; tungsten:alwaysinline" || ln == "# tungsten:alwaysinline"
        cur_fn[2] = :always if cur_fn != nil
      elsif ln == "; tungsten:noinline" || ln == "# tungsten:noinline"
        cur_fn[2] = :never if cur_fn != nil
      elsif !ln.starts_with?("#") && !ln.starts_with?(";")
        if ln.starts_with?("function ")
          ih = :default
          ih = :always if ln.ends_with?(" alwaysinline")
          ih = :never  if ln.ends_with?(" noinline")
          cur_fn = [ln, [], ih]
          fn_lines.push(cur_fn)
        elsif cur_fn != nil
          cur_fn[1].push(ln)
    li += 1

  fi = 0
  while fi < fn_lines.size
    hdr = fn_lines[fi][0]
    body = fn_lines[fi][1]
    ih = fn_lines[fi][2]
    lp = hdr.index("(")
    rp = hdr.index(")")
    fname = hdr.slice(9, lp - 9).strip
    pstr = hdr.slice(lp + 1, rp - lp - 1).strip
    ar = hdr.index("->")
    rstr = ar != nil ? hdr.slice(ar + 2, hdr.size - ar - 2).strip : "i64"
    if rstr.ends_with?(" alwaysinline")
      rstr = rstr.slice(0, rstr.size - 13).strip
      ih = :always
    elsif rstr.ends_with?(" noinline")
      rstr = rstr.slice(0, rstr.size - 9).strip
      ih = :never
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
    wf.inline_hint = ih
    vmap = {}
    smap = {}
    bmap = {"__entry" => wf.blocks[0]}
    pi = 0
    while pi < pnames.size
      vmap["%" + pnames[pi]] = pi
      vmap[pnames[pi]] = pi
      pi += 1
    bi = 0
    while bi < body.size
      bl = body[bi]
      if bl.ends_with?(":")
        bn = bl.slice(0, bl.size - 1).strip
        bmap[bn] = wf.new_block(bn) if bmap[bn] == nil
      bi += 1
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
      op = toks[op_idx].to_sym
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
      elsif op == :fmadd_f64 || op == :fmsub_f64
        d = wire_get_vr(wf, vmap, dst_nm, :f64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :f64), wire_get_vr(wf, vmap, toks[op_idx + 2], :f64), wire_get_vr(wf, vmap, toks[op_idx + 3], :f64))
        ins.ty = :f64
        wf.emit(ins)
      elsif op == :call_direct_i64 || op == :call_c_f64 || op == :call_direct_f64
        is_fp_ret = (op == :call_c_f64 || op == :call_direct_f64)
        norm_op = is_fp_ret ? :call_c_f64 : :call_direct_i64
        rty = is_fp_ret ? :f64 : :i64
        d = dst_nm != nil ? wire_get_vr(wf, vmap, dst_nm, rty) : -1
        cal_nm = toks[op_idx + 1]
        cal_nm = cal_nm.slice(1, cal_nm.size - 1) if cal_nm.starts_with?("@")
        cargs = []
        ai = op_idx + 2
        while ai < toks.size
          atk = toks[ai]
          # Infer f64 vs i64 from existing vreg if known, else i64 (or f64 for call_c_f64)
          avr = vmap[atk]
          if avr == nil
            avr = wire_get_vr(wf, vmap, atk, is_fp_ret ? :f64 : :i64)
          cargs.push(avr)
          ai += 1
        ins = WireInst.new(norm_op, d)
        ins.sym = cal_nm
        ins.args = cargs
        ins.ty = rty
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
      elsif op == :cset_carry_u64 || op == :cset_borrow_u64
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        wf.emit(WireInst.new(op, d))
      elsif op == :neg_i64 || op == :sext_i32_i64 || op == :zext_i32_i64 || op == :trunc_i64_i32 || op == :array_size_raw
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64))
        wf.emit(ins)
      elsif toks.size >= op_idx + 3
        d = wire_get_vr(wf, vmap, dst_nm, :i64)
        ins = WireInst.new(op, d, wire_get_vr(wf, vmap, toks[op_idx + 1], :i64), wire_get_vr(wf, vmap, toks[op_idx + 2], :i64))
        wf.emit(ins)
      bi += 1
    mod.add_func(wf)
    fi += 1
  mod
