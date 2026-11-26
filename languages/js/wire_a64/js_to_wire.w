# blade/wire_a64/js_to_wire — Direct JS AST -> WIRE IR -> ARM64 Machine Code Lowerer!
#
# Bypasses Tungsten source generation, `tungsten compile --emit-ll`, `llvm-extract`,
# `opt`, `llc`, and `clang` completely! Compiles qualifying JS functions straight from
# JsNode AST -> WIRE IR -> MAP_JIT ARM64 machine code in tens of microseconds.

use ./backend

# Map TypedArray kind (0..11) to Tungsten `ebits`
J2W_TA_EBITS = [108, 8, 8, 116, 16, 33, 32, -32, -64, 66, 64, -16]

+ JsToWireLowerer
  rw :wf, :var_slots, :var_types, :param_ta_kinds, :param_ptrs, :ret_type
  rw :loop_break, :loop_cont, :failed

  -> new(@wf, @param_ta_kinds, @ret_type)
    @var_slots = {}
    @var_types = {}
    @param_ptrs = {}
    @loop_break = []
    @loop_cont = []
    @failed = false

  -> expr_type(n)
    return :f64 if n == nil
    k = n.kind
    if k == :ident
      t = @var_types[n.str]
      return t != nil ? t : :f64
    elsif k == :bigint
      return :u64
    elsif k == :num
      return (n.a == n.a.to_i.to_f && n.a >= ~-2147483648.0 && n.a <= ~2147483647.0) ? :intlit : :f64
    elsif k == :member
      if n.has?(F_COMPUTED)
        tk = @param_ta_kinds[n.a.str]
        if tk != nil
          return :u64 if tk == 10
          return :i64 if tk == 9
          return :i64 if tk == 0 || tk == 1 || tk == 2 || tk == 3 || tk == 4 || tk == 5 || tk == 6
          return :f64
      return :i64
    elsif k == :binary
      op = n.str
      return :i64 if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
      lt = expr_type(n.a)
      rt = expr_type(n.b)
      return :u64 if lt == :u64 || rt == :u64
      if op != "/" && ((lt == :i64 || lt == :intlit) && (rt == :i64 || rt == :intlit)) && (lt == :i64 || rt == :i64)
        return :i64
      return :f64
    elsif k == :call
      if n.a.kind == :member && n.a.a.kind == :ident && n.a.a.str == "BigInt"
        return n.a.b.str == "asUintN" ? :u64 : :i64
      if n.a.kind == :member && n.a.a.kind == :ident && n.a.a.str == "Math" && n.a.b.str == "imul"
        return :i64
    :f64

  -> convert_val(vr, from_ty, want_ty)
    return vr if from_ty == want_ty || want_ty == :any
    return vr if (from_ty == :i64 || from_ty == :u64) && (want_ty == :i64 || want_ty == :u64)
    if want_ty == :f64 && from_ty == :i64
      return @wf.emit_un(:sitofp_i64_f64, vr, :f64)
    elsif want_ty == :f64 && from_ty == :u64
      return @wf.emit_un(:uitofp_u64_f64, vr, :f64)
    elsif want_ty == :i64 && from_ty == :f64
      return @wf.emit_un(:fptosi_f64_i64, vr, :i64)
    elsif want_ty == :u64 && from_ty == :f64
      return @wf.emit_un(:fptoui_f64_u64, vr, :i64)
    vr

  -> lower_expr(n, want_ty)
    k = n.kind
    if k == :ident
      nm = n.str
      sl = @var_slots[nm]
      if sl != nil
        vr = @wf.emit_load_slot(sl)
        return convert_val(vr, @var_types[nm], want_ty)
      # Parameter vreg
      pvr = @wf.name_to_vreg[nm]
      if pvr != nil
        return convert_val(pvr, @var_types[nm], want_ty)
      @failed = true
      return @wf.emit_const_i64(0)
    elsif k == :num
      v = n.a
      if want_ty == :i64 || want_ty == :u64
        return @wf.emit_const_i64(v.to_i)
      return @wf.emit_const_f64(v)
    elsif k == :bigint
      # Parse 64-bit integer literal string into signed i64 bit pattern
      d = n.str
      u = d.to_i
      iv = u >= ((1 ## int) << 63) ? ((u - ((1 ## int) << 64)) ## i64) : (u ## i64)
      vr = @wf.emit_const_i64(iv)
      return convert_val(vr, :u64, want_ty)
    elsif k == :true
      return @wf.emit_const_i64(1)
    elsif k == :false
      return @wf.emit_const_i64(0)
    elsif k == :member
      if n.has?(F_COMPUTED)
        arr_nm = n.a.str
        tk = @param_ta_kinds[arr_nm]
        ptr_vr = @param_ptrs[arr_nm]
        if tk == nil || ptr_vr == nil
          @failed = true
          return @wf.emit_const_i64(0)
        idx_vr = lower_expr(n.b, :i64)
        eb = J2W_TA_EBITS[tk]
        rv = @wf.emit_ta_get(ptr_vr, idx_vr, eb)
        rty = (eb == -64 || eb == -32 || eb == -16) ? :f64 : (tk == 10 ? :u64 : :i64)
        return convert_val(rv, rty, want_ty)
      else
        pvr = @wf.name_to_vreg[n.a.str]
        rv = @wf.emit_arr_len(pvr)
        return convert_val(rv, :i64, want_ty)
    elsif k == :unary
      op = n.str
      if op == "-"
        if want_ty == :i64 || want_ty == :u64
          return @wf.emit_un(:neg_i64, lower_expr(n.a, :i64), :i64)
        return @wf.emit_un(:fneg_f64, lower_expr(n.a, :f64), :f64)
      elsif op == "~"
        m1 = @wf.emit_const_i64(-1)
        rv = @wf.emit_bin(:xor_i32, lower_expr(n.a, :i64), m1, :i64)
        return convert_val(rv, :i64, want_ty)
      elsif op == "!"
        z = @wf.emit_const_i64(0)
        return @wf.emit_cmp(:icmp_i64, :eq, lower_expr(n.a, :i64), z)
      return lower_expr(n.a, want_ty)
    elsif k == :binary
      op = n.str
      if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
        lt = expr_type(n.a)
        rt = expr_type(n.b)
        is_u64 = (lt == :u64 || rt == :u64)
        is_i64 = !is_u64 && ((lt == :i64 || lt == :intlit) && (rt == :i64 || rt == :intlit)) && (lt == :i64 || rt == :i64)
        if is_u64 || is_i64
          la = lower_expr(n.a, is_u64 ? :u64 : :i64)
          rb = lower_expr(n.b, is_u64 ? :u64 : :i64)
          pred = :eq
          if op == "!=" || op == "!=="
            pred = :ne
          elsif op == "<"
            pred = is_u64 ? :ult : :slt
          elsif op == "<="
            pred = is_u64 ? :ule : :sle
          elsif op == ">"
            pred = is_u64 ? :ugt : :sgt
          elsif op == ">="
            pred = is_u64 ? :uge : :sge
          return @wf.emit_cmp(:icmp_i64, pred, la, rb)
        else
          la = lower_expr(n.a, :f64)
          rb = lower_expr(n.b, :f64)
          pred = :oeq
          pred = :one if op == "!=" || op == "!=="
          pred = :olt if op == "<"
          pred = :ole if op == "<="
          pred = :ogt if op == ">"
          pred = :oge if op == ">="
          return @wf.emit_cmp(:fcmp_f64, pred, la, rb)
      elsif op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
        lt = expr_type(n.a)
        rt = expr_type(n.b)
        if lt == :u64 || rt == :u64
          la = lower_expr(n.a, :u64)
          rb = lower_expr(n.b, :u64)
          wop = :xor_i64
          wop = :or_i64   if op == "|"
          wop = :and_i64  if op == "&"
          wop = :shl_i64  if op == "<<"
          wop = :ashr_i64 if op == ">>"
          wop = :lshr_i64 if op == ">>>"
          rv = @wf.emit_bin(wop, la, rb, :i64)
          return convert_val(rv, :u64, want_ty)
        # ECMAScript 32-bit bitwise ops (exact ARM64 W-register wrapping!)
        la = lower_expr(n.a, :i64)
        rb = lower_expr(n.b, :i64)
        wop = :xor_i32
        wop = :or_i32   if op == "|"
        wop = :and_i32  if op == "&"
        wop = :shl_i32  if op == "<<"
        wop = :ashr_i32 if op == ">>"
        wop = :lshr_i32 if op == ">>>"
        rv = @wf.emit_bin(wop, la, rb, :i64)
        return convert_val(rv, :i64, want_ty)
      else
        lt = expr_type(n.a)
        rt = expr_type(n.b)
        is_u64 = (lt == :u64 || rt == :u64)
        is_int = (op != "/") && (lt == :i64 || lt == :intlit) && (rt == :i64 || rt == :intlit) && (lt == :i64 || rt == :i64)
        if is_u64 || ((want_ty == :i64 || want_ty == :u64) && is_int)
          ct = is_u64 ? :u64 : :i64
          la = lower_expr(n.a, ct)
          rb = lower_expr(n.b, ct)
          wop = :add_i64
          wop = :sub_i64 if op == "-"
          wop = :mul_i64 if op == "*"
          wop = is_u64 ? :udiv_i64 : :sdiv_i64 if op == "/"
          wop = :srem_i64 if op == "%"
          rv = @wf.emit_bin(wop, la, rb, :i64)
          return convert_val(rv, ct, want_ty)
        else
          la = lower_expr(n.a, :f64)
          rb = lower_expr(n.b, :f64)
          wop = :fadd_f64
          wop = :fsub_f64 if op == "-"
          wop = :fmul_f64 if op == "*"
          wop = :fdiv_f64 if op == "/"
          rv = @wf.emit_bin(wop, la, rb, :f64)
          return convert_val(rv, :f64, want_ty)
    elsif k == :cond
      cv = lower_expr(n.a, :i64)
      ty = want_ty == :f64 ? :f64 : :i64
      tv = lower_expr(n.b, ty)
      fv = lower_expr(n.c, ty)
      return @wf.emit_sel(ty == :f64 ? :select_f64 : :select_i64, cv, tv, fv, ty)
    elsif k == :call
      cal = n.a
      if cal.kind == :member && cal.a.kind == :ident && cal.a.str == "BigInt"
        if cal.b.str == "asUintN" && n.list.size == 2
          return convert_val(lower_expr(n.list[1], :u64), :u64, want_ty)
        if cal.b.str == "asIntN" && n.list.size == 2
          return convert_val(lower_expr(n.list[1], :i64), :i64, want_ty)
      if cal.kind == :member && cal.a.kind == :ident && cal.a.str == "Math"
        m = cal.b.str
        if m == "imul" && n.list.size == 2
          rv = @wf.emit_bin(:mul_i32, lower_expr(n.list[0], :i64), lower_expr(n.list[1], :i64), :i64)
          return convert_val(rv, :i64, want_ty)
        elsif m == "sqrt" && n.list.size == 1
          return convert_val(@wf.emit_un(:fsqrt_f64, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif m == "abs" && n.list.size == 1
          return convert_val(@wf.emit_un(:fabs_f64, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif m == "floor" && n.list.size == 1
          return convert_val(@wf.emit_un(:ffloor_f64, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif m == "ceil" && n.list.size == 1
          return convert_val(@wf.emit_un(:fceil_f64, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif m == "fround" && n.list.size == 1
          return convert_val(@wf.emit_un(:fround_f32, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif m == "f16round" && n.list.size == 1
          return convert_val(@wf.emit_un(:fround_f16, lower_expr(n.list[0], :f64), :f64), :f64, want_ty)
        elsif (m == "min" || m == "max") && n.list.size == 2
          wop = m == "min" ? :fmin_f64 : :fmax_f64
          return convert_val(@wf.emit_bin(wop, lower_expr(n.list[0], :f64), lower_expr(n.list[1], :f64), :f64), :f64, want_ty)
        elsif (m == "sin" || m == "cos") && n.list.size == 1
          rv = @wf.emit_call_c(m, [lower_expr(n.list[0], :f64)], :f64)
          return convert_val(rv, :f64, want_ty)
    @failed = true
    @wf.emit_const_i64(0)

  -> lower_store_elem(arr_nm, idx_node, rhs_node)
    tk = @param_ta_kinds[arr_nm]
    ptr_vr = @param_ptrs[arr_nm]
    if tk == nil || ptr_vr == nil
      @failed = true
      return nil
    idx_vr = lower_expr(idx_node, :i64)
    eb = J2W_TA_EBITS[tk]
    if tk == 2
      # Uint8ClampedArray: clamp to [0, 255]
      if expr_type(rhs_node) == :i64
        v = lower_expr(rhs_node, :i64)
        z = @wf.emit_const_i64(0)
        c255 = @wf.emit_const_i64(255)
        lt0 = @wf.emit_cmp(:icmp_i64, :slt, v, z)
        v1 = @wf.emit_sel(:select_i64, lt0, z, v, :i64)
        gt255 = @wf.emit_cmp(:icmp_i64, :sgt, v1, c255)
        v2 = @wf.emit_sel(:select_i64, gt255, c255, v1, :i64)
        @wf.emit_ta_set(ptr_vr, idx_vr, v2, 8)
      else
        v = lower_expr(rhs_node, :f64)
        z = @wf.emit_const_f64(~0.0)
        c255 = @wf.emit_const_f64(~255.0)
        v1 = @wf.emit_bin(:fmax_f64, v, z, :f64)
        v2 = @wf.emit_bin(:fmin_f64, v1, c255, :f64)
        iv = @wf.emit_un(:fptosi_f64_i64, v2, :i64)
        @wf.emit_ta_set(ptr_vr, idx_vr, iv, 8)
    elsif eb == -64 || eb == -32 || eb == -16
      v = lower_expr(rhs_node, :f64)
      @wf.emit_ta_set(ptr_vr, idx_vr, v, eb)
    elsif tk == 10
      v = lower_expr(rhs_node, :u64)
      @wf.emit_ta_set(ptr_vr, idx_vr, v, 64)
    else
      v = lower_expr(rhs_node, :i64)
      @wf.emit_ta_set(ptr_vr, idx_vr, v, eb)
    nil

  -> lower_stmt(s)
    return nil if s == nil || @failed
    k = s.kind
    if k == :block
      s.list.each ->(sub) lower_stmt(sub)
    elsif k == :var_decl
      s.list.each ->(d)
        nm = d.a.str
        t = @var_types[nm]
        if t == nil
          t = d.b != nil ? expr_type(d.b) : :f64
          t = :f64 if t == :intlit
          @var_types[nm] = t
        sl_ty = t == :f64 ? :f64 : :i64
        sl = @var_slots[nm]
        if sl == nil
          sl = @wf.new_slot(sl_ty, nm)
          @var_slots[nm] = sl
        vr = d.b != nil ? lower_expr(d.b, t) : (sl_ty == :f64 ? @wf.emit_const_f64(~0.0) : @wf.emit_const_i64(0))
        @wf.emit_store_slot(sl, vr)
    elsif k == :expr_stmt
      e = s.a
      if e.kind == :assign
        if e.a.kind == :member && e.a.has?(F_COMPUTED) && e.str == "="
          lower_store_elem(e.a.a.str, e.a.b, e.b)
        elsif e.a.kind == :ident
          nm = e.a.str
          sl = @var_slots[nm]
          if sl == nil
            @failed = true
            return nil
          t = @var_types[nm] != nil ? @var_types[nm] : :f64
          if e.str == "="
            @wf.emit_store_slot(sl, lower_expr(e.b, t))
          else
            bop = e.str.slice(0, e.str.size - 1)
            cur = @wf.emit_load_slot(sl)
            rhs = lower_expr(e.b, t)
            nv = cur
            if t == :f64
              wop = :fadd_f64
              wop = :fsub_f64 if bop == "-"
              wop = :fmul_f64 if bop == "*"
              wop = :fdiv_f64 if bop == "/"
              nv = @wf.emit_bin(wop, cur, rhs, :f64)
            elsif t == :u64
              wop = :add_i64
              wop = :sub_i64 if bop == "-"
              wop = :mul_i64 if bop == "*"
              wop = :xor_i64 if bop == "^"
              wop = :or_i64  if bop == "|"
              wop = :and_i64 if bop == "&"
              nv = @wf.emit_bin(wop, cur, rhs, :i64)
            else
              wop = :add_i64
              wop = :sub_i64 if bop == "-"
              wop = :mul_i64 if bop == "*"
              wop = :xor_i32 if bop == "^"
              wop = :or_i32  if bop == "|"
              wop = :and_i32 if bop == "&"
              nv = @wf.emit_bin(wop, cur, rhs, :i64)
            @wf.emit_store_slot(sl, nv)
      elsif e.kind == :update
        nm = e.a.str
        sl = @var_slots[nm]
        if sl == nil
          @failed = true
          return nil
        t = @var_types[nm] != nil ? @var_types[nm] : :i64
        cur = @wf.emit_load_slot(sl)
        if t == :f64
          one = @wf.emit_const_f64(~1.0)
          nv = @wf.emit_bin(e.str == "++" ? :fadd_f64 : :fsub_f64, cur, one, :f64)
          @wf.emit_store_slot(sl, nv)
        else
          one = @wf.emit_const_i64(1)
          nv = @wf.emit_bin(e.str == "++" ? :add_i64 : :sub_i64, cur, one, :i64)
          @wf.emit_store_slot(sl, nv)
    elsif k == :return
      if s.a == nil
        v = @ret_type == :f64 ? @wf.emit_const_f64(~0.0) : @wf.emit_const_i64(0)
        @wf.emit_ret(v)
      else
        @wf.emit_ret(lower_expr(s.a, @ret_type))
    elsif k == :break
      @wf.emit_br(@loop_break[@loop_break.size - 1]) if @loop_break.size > 0
    elsif k == :continue
      @wf.emit_br(@loop_cont[@loop_cont.size - 1]) if @loop_cont.size > 0
    elsif k == :if
      id = @wf.blocks.size
      b_then = @wf.new_block("if.then." + id.to_s)
      b_else = s.c != nil ? @wf.new_block("if.else." + id.to_s) : nil
      b_end  = @wf.new_block("if.end." + id.to_s)
      cv = lower_expr(s.a, :i64)
      @wf.emit_cond_br(cv, b_then, b_else != nil ? b_else : b_end)
      @wf.set_block(b_then)
      lower_stmt(s.b)
      @wf.emit_br(b_end)
      if b_else != nil
        @wf.set_block(b_else)
        lower_stmt(s.c)
        @wf.emit_br(b_end)
      @wf.set_block(b_end)
    elsif k == :while
      id = @wf.blocks.size
      b_cond = @wf.new_block("while.cond." + id.to_s)
      b_body = @wf.new_block("while.body." + id.to_s)
      b_end  = @wf.new_block("while.end." + id.to_s)
      @wf.emit_br(b_cond)
      @wf.set_block(b_cond)
      cv = lower_expr(s.a, :i64)
      @wf.emit_cond_br(cv, b_body, b_end)
      @loop_break.push(b_end)
      @loop_cont.push(b_cond)
      @wf.set_block(b_body)
      lower_stmt(s.b)
      @wf.emit_br(b_cond)
      @loop_break.pop
      @loop_cont.pop
      @wf.set_block(b_end)
    elsif k == :for
      # Init (respect sound inferred type — NEVER force float loop vars like `x += 0.5` to i64!)
      if s.a != nil
        if s.a.kind == :var_decl
          lower_stmt(s.a)
        else
          lower_stmt(JsNode.new(:expr_stmt, 0, 0, nil, s.a, nil, nil, nil, 0))
      id = @wf.blocks.size
      b_cond = @wf.new_block("for.cond." + id.to_s)
      b_body = @wf.new_block("for.body." + id.to_s)
      b_upd  = @wf.new_block("for.upd." + id.to_s)
      b_end  = @wf.new_block("for.end." + id.to_s)
      @wf.emit_br(b_cond)
      @wf.set_block(b_cond)
      if s.b != nil
        cv = lower_expr(s.b, :i64)
        @wf.emit_cond_br(cv, b_body, b_end)
      else
        @wf.emit_br(b_body)
      @loop_break.push(b_end)
      @loop_cont.push(b_upd)
      @wf.set_block(b_body)
      lower_stmt(s.d)
      @wf.emit_br(b_upd)
      @wf.set_block(b_upd)
      lower_stmt(JsNode.new(:expr_stmt, 0, 0, nil, s.c, nil, nil, nil, 0)) if s.c != nil
      @wf.emit_br(b_cond)
      @loop_break.pop
      @loop_cont.pop
      @wf.set_block(b_end)
    nil

# Lightweight sound fixed-point local type inference for standalone `wire_a64_compile_js_func` calls.
-> j2w_int_lit?(n)
  n != nil && n.kind == :num && n.a == n.a.to_i.to_f && n.a >= ~-2147483648.0 && n.a <= ~2147483647.0

-> j2w_join_ty(t1, t2)
  return t2 if t1 == nil
  return t1 if t2 == nil || t1 == t2
  return :u64 if t1 == :u64 || t2 == :u64
  :f64

-> j2w_expr_ty(n, vtypes, ta_kinds)
  return :f64 if n == nil
  k = n.kind
  if k == :ident
    t = vtypes[n.str]
    return t != nil ? t : :f64
  return :u64 if k == :bigint
  return j2w_int_lit?(n) ? :i64 : :f64 if k == :num
  return :i64 if k == :true || k == :false
  if k == :member
    if n.has?(F_COMPUTED)
      tk = ta_kinds[n.a.str]
      return :u64 if tk == 10
      return :i64 if tk != nil && (tk <= 6 || tk == 9)
      return :f64
    return :i64
  if k == :unary
    return :i64 if n.str == "~" || n.str == "!"
    return j2w_expr_ty(n.a, vtypes, ta_kinds)
  if k == :binary
    op = n.str
    return :i64 if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
    lt = j2w_expr_ty(n.a, vtypes, ta_kinds)
    rt = j2w_expr_ty(n.b, vtypes, ta_kinds)
    if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
      return (lt == :u64 || rt == :u64) ? :u64 : :i64
    return :u64 if lt == :u64 || rt == :u64
    return :f64 if op == "/" || lt == :f64 || rt == :f64
    return :i64 if (op == "+" || op == "-" || op == "*") && lt == :i64 && rt == :i64
    return :f64
  if k == :cond
    return j2w_join_ty(j2w_expr_ty(n.b, vtypes, ta_kinds), j2w_expr_ty(n.c, vtypes, ta_kinds))
  if k == :call && n.a.kind == :member && n.a.a.kind == :ident
    return :u64 if n.a.a.str == "BigInt" && n.a.b.str == "asUintN"
    return :i64 if n.a.a.str == "BigInt" || (n.a.a.str == "Math" && n.a.b.str == "imul")
  :f64

-> j2w_infer_stmts(stmts, vtypes, ta_kinds, changed)
  i = 0
  while i < stmts.size
    s = stmts[i]
    if s != nil
      k = s.kind
      if k == :block
        j2w_infer_stmts(s.list, vtypes, ta_kinds, changed)
      elsif k == :var_decl
        s.list.each ->(d)
          nm = d.a.str
          nt = d.b != nil ? j2w_expr_ty(d.b, vtypes, ta_kinds) : :f64
          prev = vtypes[nm]
          jt = j2w_join_ty(prev, nt)
          if jt != prev
            vtypes[nm] = jt
            changed[0] = true
      elsif k == :expr_stmt && s.a != nil && s.a.kind == :assign && s.a.a.kind == :ident
        nm = s.a.str
        nm = s.a.a.str
        rt = j2w_expr_ty(s.a.b, vtypes, ta_kinds)
        nt = rt
        if s.a.str != "="
          bop = s.a.str.slice(0, s.a.str.size - 1)
          cur = vtypes[nm]
          if bop == "^" || bop == "|" || bop == "&"
            nt = (cur == :u64 || rt == :u64) ? :u64 : :i64
          elsif bop == "/"
            nt = :f64
          else
            nt = j2w_join_ty(cur, rt)
        prev = vtypes[nm]
        jt = j2w_join_ty(prev, nt)
        if jt != prev
          vtypes[nm] = jt
          changed[0] = true
      elsif k == :if
        j2w_infer_stmts([s.b], vtypes, ta_kinds, changed) if s.b != nil
        j2w_infer_stmts([s.c], vtypes, ta_kinds, changed) if s.c != nil
      elsif k == :while
        j2w_infer_stmts([s.b], vtypes, ta_kinds, changed) if s.b != nil
      elsif k == :for
        j2w_infer_stmts([s.a], vtypes, ta_kinds, changed) if s.a != nil && s.a.kind == :var_decl
        j2w_infer_stmts([JsNode.new(:expr_stmt, 0, 0, nil, s.a, nil, nil, nil, 0)], vtypes, ta_kinds, changed) if s.a != nil && s.a.kind != :var_decl
        j2w_infer_stmts([JsNode.new(:expr_stmt, 0, 0, nil, s.c, nil, nil, nil, 0)], vtypes, ta_kinds, changed) if s.c != nil
        j2w_infer_stmts([s.d], vtypes, ta_kinds, changed) if s.d != nil
    i += 1
  nil

# Compile a qualifying JaFunc AST directly via WIRE IR -> ARM64 machine code (ZERO clang!).
# Accepts optional sound inferred type map `inferred_vtypes` (eliminates all name heuristics!).
# Returns [fp, code_bytes, compile_us] or nil if unsupported.
-> wire_a64_compile_js_func(jf, param_specs, ret_type_str, inferred_vtypes = nil)
  fn_node = jf.node
  return nil if fn_node == nil || !fn_node.b.is_a?(Array)
  params = fn_node.list.map(->(p) p.str)
  ptypes = []
  pebits = []
  ta_kinds_map = {}
  i = 0
  while i < params.size
    sp = param_specs[i]
    if sp[0] == :ta
      tk = sp[1]
      ptypes.push(:arr)
      pebits.push(J2W_TA_EBITS[tk])
      ta_kinds_map[params[i]] = tk
    elsif sp[0] == :i64
      ptypes.push(:i64)
      pebits.push(0)
    else
      ptypes.push(:f64)
      pebits.push(0)
    i += 1
  if inferred_vtypes == nil
    vt = {}
    pi = 0
    while pi < params.size
      sp = param_specs[pi]
      vt[params[pi]] = sp[0] == :ta ? :arr : (sp[0] == :i64 ? :i64 : :f64)
      pi += 1
    it = 0
    while it < 6
      ch = [false]
      j2w_infer_stmts(fn_node.b, vt, ta_kinds_map, ch)
      break if !ch[0]
      it += 1
    inferred_vtypes = vt
  rty = ret_type_str == "f64" ? :f64 : :i64
  abi = rty == :f64 ? :wvalue_ret_f64 : :wvalue_ret_i64
  wf = WireFunc.new(jf.name != nil ? jf.name : "js_wire", params, ptypes, pebits, rty, abi)
  lo = JsToWireLowerer.new(wf, ta_kinds_map, rty)
  if inferred_vtypes != nil
    inferred_vtypes.each ->(k, v) lo.var_types[k] = v
  # Hoist all TypedArray data pointers in entry block!
  i = 0
  while i < params.size
    sp = param_specs[i]
    nm = params[i]
    if sp[0] == :ta
      lo.var_types[nm] = :arr
      lo.param_ptrs[nm] = wf.emit_arr_ptr(i, J2W_TA_EBITS[sp[1]])
    elsif sp[0] == :i64
      lo.var_types[nm] = :i64
    else
      lo.var_types[nm] = :f64
    i += 1
  fn_node.b.each ->(st) lo.lower_stmt(st)
  return nil if lo.failed
  # Fallback default return at end of function
  wf.emit_ret(rty == :f64 ? wf.emit_const_f64(~0.0) : wf.emit_const_i64(0))
  res = wire_compile_func(wf)
  return nil if res[0] == 0
  res
