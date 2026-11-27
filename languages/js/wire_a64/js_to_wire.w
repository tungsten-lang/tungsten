# languages/js/wire_a64/js_to_wire — Direct JS AST -> WIRE IR -> Native Machine Code Lowerer!
#
# Bypasses Tungsten source generation, `.ll` emission, `llvm-extract`, `opt`, `llc`, and `clang`
# completely! Lowers qualifying JS functions directly from `JsNode` AST -> `WireFunc` (WIRE IR),
# supporting both blazing-fast single-pass Tier-1 baseline compilation (~4-6 us) and in-place
# Tier-2 optimizing compilation with hardware multi-limb BigInt carry chains and SIMD kernels.

use ./backend

# Map TypedArray kind (0..11) to Tungsten `ebits`
J2W_TA_EBITS = [108, 8, 8, 116, 16, 33, 32, -32, -64, 66, 64, -16]

-> j2w_is_u128_ty?(t)
  t == :u128 || t == :u128_add2 || t == :u128_add2_c || t == :u128_add3 || t == :u128_mul || t == :u128_mul1 || t == :u128_mul2

-> j2w_is_i128_sub_ty?(t)
  t == :i128_diff || t == :i128_sub1 || t == :i128_sub2

-> j2w_is_wide_big?(t)
  j2w_is_u128_ty?(t) || j2w_is_i128_sub_ty?(t)

-> j2w_norm_ty(t)
  return :u64 if t == :u1_big || t == :u64
  return :i64 if t == :i64_big || t == :i64
  return :u128 if j2w_is_u128_ty?(t)
  return :i128_diff if j2w_is_i128_sub_ty?(t)
  t

+ JsToWireLowerer
  rw :wf, :var_slots, :var_hi_slots, :var_diff_borrow, :var_types, :param_ta_kinds, :param_ptrs, :ret_type
  rw :loop_break, :loop_cont, :failed

  -> new(@wf, @param_ta_kinds, @ret_type)
    @var_slots = {}
    @var_hi_slots = {}
    @var_diff_borrow = {}
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
      return t != nil ? j2w_norm_ty(t) : :f64
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
    elsif k == :unary
      if n.str == "-" && n.a != nil && n.a.kind == :binary && n.a.str == ">>" && expr_type(n.a.a) == :i128_diff && n.a.b.kind == :bigint && n.a.b.str == "64"
        return :u64
      return :i64 if n.str == "~" || n.str == "!"
      return expr_type(n.a)
    elsif k == :binary
      op = n.str
      return :i64 if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
      lt = expr_type(n.a)
      rt = expr_type(n.b)
      if op == ">>" && n.b.kind == :bigint && n.b.str == "64"
        return :u64 if lt == :u128
        return :i64 if lt == :i128_diff
      if op == "&" && (lt == :u64 || rt == :u64 || lt == :u128 || lt == :i128_diff)
        return :u64
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
        return (lt == :u64 || rt == :u64) ? :u64 : :i64
      if op == "+" && (lt == :u64 || lt == :u128) && (rt == :u64 || rt == :u128)
        return :u128
      if op == "*" && lt == :u64 && rt == :u64
        return :u128
      if op == "-"
        if n.a.kind == :bigint && n.a.str == "0" && n.b.kind == :binary && n.b.str == ">>" && expr_type(n.b.a) == :i128_diff && n.b.b.kind == :bigint && n.b.b.str == "64"
          return :u64
        if (lt == :u64 || lt == :i128_diff) && rt == :u64
          return :i128_diff
      return :u64 if lt == :u64 || rt == :u64
      if op != "/" && ((lt == :i64 || lt == :intlit) && (rt == :i64 || rt == :intlit)) && (lt == :i64 || rt == :i64)
        return :i64
      return :f64
    elsif k == :cond
      tt = expr_type(n.b)
      ft = expr_type(n.c)
      return :u64 if tt == :u64 || ft == :u64
      return :i64 if (tt == :i64 || tt == :intlit) && (ft == :i64 || ft == :intlit)
      return :f64
    elsif k == :call
      if n.a.kind == :member && n.a.a.kind == :ident && n.a.a.str == "BigInt"
        return n.a.b.str == "asUintN" ? :u64 : :i64
      if n.a.kind == :member && n.a.a.kind == :ident && n.a.a.str == "Math" && n.a.b.str == "imul"
        return :i64
    :f64

  # Lower an exact 128-bit BigInt expression (`:u128` or `:i128_diff`) into `[lo_vr, hi_or_brw_vr, is_borrow]`.
  -> lower_wide_big(n)
    k = n.kind
    if k == :ident
      nm = n.str
      sl_lo = @var_slots[nm]
      sl_hi = @var_hi_slots[nm]
      if sl_lo != nil && sl_hi != nil
        return [@wf.emit_load_slot(sl_lo), @wf.emit_load_slot(sl_hi), @var_diff_borrow[nm] == true]
      lo = lower_expr(n, :u64)
      return [lo, @wf.emit_const_i64(0), false]
    elsif k == :binary
      op = n.str
      lt = expr_type(n.a)
      rt = expr_type(n.b)
      if op == "*" && lt == :u64 && rt == :u64
        la = lower_expr(n.a, :u64)
        rb = lower_expr(n.b, :u64)
        lo = @wf.emit_bin(:mul_i64, la, rb, :i64)
        hi = @wf.emit_mulhi_u64(la, rb)
        return [lo, hi, false]
      elsif op == "+"
        if lt == :u64 && rt == :u64
          la = lower_expr(n.a, :u64)
          rb = lower_expr(n.b, :u64)
          lo = @wf.emit_bin(:add_i64, la, rb, :i64)
          hi = @wf.emit_addcarry_u64(la, rb)
          return [lo, hi, false]
        elsif lt == :u128 && rt == :u64
          lp = lower_wide_big(n.a)
          if lp[2]
            @failed = true
            return [@wf.emit_const_i64(0), @wf.emit_const_i64(0), false]
          rb = lower_expr(n.b, :u64)
          lo = @wf.emit_bin(:add_i64, lp[0], rb, :i64)
          c = @wf.emit_addcarry_u64(lp[0], rb)
          hi = @wf.emit_bin(:add_i64, lp[1], c, :i64)
          return [lo, hi, false]
        elsif lt == :u64 && rt == :u128
          la = lower_expr(n.a, :u64)
          rp = lower_wide_big(n.b)
          if rp[2]
            @failed = true
            return [@wf.emit_const_i64(0), @wf.emit_const_i64(0), false]
          lo = @wf.emit_bin(:add_i64, la, rp[0], :i64)
          c = @wf.emit_addcarry_u64(la, rp[0])
          hi = @wf.emit_bin(:add_i64, rp[1], c, :i64)
          return [lo, hi, false]
        elsif lt == :u128 && rt == :u128
          lp = lower_wide_big(n.a)
          rp = lower_wide_big(n.b)
          if lp[2] || rp[2]
            @failed = true
            return [@wf.emit_const_i64(0), @wf.emit_const_i64(0), false]
          lo = @wf.emit_bin(:add_i64, lp[0], rp[0], :i64)
          c = @wf.emit_addcarry_u64(lp[0], rp[0])
          h1 = @wf.emit_bin(:add_i64, lp[1], rp[1], :i64)
          hi = @wf.emit_bin(:add_i64, h1, c, :i64)
          return [lo, hi, false]
      elsif op == "-"
        if lt == :u64 && rt == :u64
          la = lower_expr(n.a, :u64)
          rb = lower_expr(n.b, :u64)
          lo = @wf.emit_bin(:sub_i64, la, rb, :i64)
          brw = @wf.emit_subborrow_u64(la, rb)
          return [lo, brw, true]
        elsif lt == :i128_diff && rt == :u64
          lp = lower_wide_big(n.a)
          if !lp[2]
            @failed = true
            return [@wf.emit_const_i64(0), @wf.emit_const_i64(0), true]
          rb = lower_expr(n.b, :u64)
          lo = @wf.emit_bin(:sub_i64, lp[0], rb, :i64)
          b2 = @wf.emit_subborrow_u64(lp[0], rb)
          brw = @wf.emit_bin(:add_i64, lp[1], b2, :i64)
          return [lo, brw, true]
    @failed = true
    [@wf.emit_const_i64(0), @wf.emit_const_i64(0), false]

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
      if @var_hi_slots[nm] != nil
        # Reading a wide 128-bit var in a 64-bit truncating context (e.g. `out[i] = s`, `BigInt.asUintN(64, s)`)
        vr = @wf.emit_load_slot(@var_slots[nm])
        return convert_val(vr, :u64, want_ty)
      sl = @var_slots[nm]
      if sl != nil
        vr = @wf.emit_load_slot(sl)
        return convert_val(vr, j2w_norm_ty(@var_types[nm]), want_ty)
      # Parameter vreg
      pvr = @wf.name_to_vreg[nm]
      if pvr != nil
        return convert_val(pvr, j2w_norm_ty(@var_types[nm]), want_ty)
      @failed = true
      return @wf.emit_const_i64(0)
    elsif k == :num
      v = n.a
      if want_ty == :i64 || want_ty == :u64
        return @wf.emit_const_i64(v.to_i)
      return @wf.emit_const_f64(v)
    elsif k == :bigint
      # Parse 64-bit integer literal string (decimal, 0x, 0b, 0o, _) into signed i64 bit pattern
      u = js_bigint_literal(n.str).v
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
        # `-(d >> 64n)` on `:i128_diff` extracts the exact 0/1 borrow directly!
        if n.a != nil && n.a.kind == :binary && n.a.str == ">>" && expr_type(n.a.a) == :i128_diff && n.a.b.kind == :bigint && n.a.b.str == "64"
          wp = lower_wide_big(n.a.a)
          return convert_val(wp[1], :u64, want_ty)
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
      # Exact wide-128 BigInt borrow/carry extractors!
      if op == ">>" && n.b.kind == :bigint && n.b.str == "64"
        lt_w = expr_type(n.a)
        if lt_w == :u128
          wp = lower_wide_big(n.a)
          return convert_val(wp[1], :u64, want_ty)
        elsif lt_w == :i128_diff
          wp = lower_wide_big(n.a)
          return convert_val(@wf.emit_un(:neg_i64, wp[1], :i64), :i64, want_ty)
      if op == "&" && n.b.kind == :bigint && n.b.str == "1" && n.a.kind == :binary && n.a.str == ">>" && expr_type(n.a.a) == :i128_diff && n.a.b.kind == :bigint && n.a.b.str == "64"
        wp = lower_wide_big(n.a.a)
        return convert_val(wp[1], :u64, want_ty)
      if op == "-" && n.a.kind == :bigint && n.a.str == "0" && n.b.kind == :binary && n.b.str == ">>" && expr_type(n.b.a) == :i128_diff && n.b.b.kind == :bigint && n.b.b.str == "64"
        wp = lower_wide_big(n.b.a)
        return convert_val(wp[1], :u64, want_ty)

      if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
        lt = expr_type(n.a)
        rt = expr_type(n.b)
        # `d < 0n` (or `0n > d`) on `:i128_diff` is the exact 0/1 borrow!
        if op == "<" && lt == :i128_diff && n.b.kind == :bigint && n.b.str == "0"
          wp = lower_wide_big(n.a)
          return wp[1]
        if op == ">" && rt == :i128_diff && n.a.kind == :bigint && n.a.str == "0"
          wp = lower_wide_big(n.b)
          return wp[1]
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
        if lt == :u128 || lt == :i128_diff
          # Truncating bitwise mask in 64-bit context (e.g. `s & 0xffffffffffffffffn`)
          wp = lower_wide_big(n.a)
          la = wp[0]
          rb = lower_expr(n.b, :u64)
          wop = op == "|" ? :or_i64 : (op == "&" ? :and_i64 : :xor_i64)
          rv = @wf.emit_bin(wop, la, rb, :i64)
          return convert_val(rv, :u64, want_ty)
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
        # ECMAScript 32-bit bitwise ops (exact W-register / 32-bit wrapping!)
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
        is_u64 = (lt == :u64 || rt == :u64 || lt == :u128 || rt == :u128 || lt == :i128_diff)
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
      # Avoid redundant `select_i64(cv, 1, 0)` when `cv` is already an exact 0/1 comparison/borrow!
      if ty == :i64 && n.a != nil && n.a.kind == :binary && (n.a.str == "<" || n.a.str == ">" || n.a.str == "<=" || n.a.str == ">=" || n.a.str == "==" || n.a.str == "===" || n.a.str == "!=" || n.a.str == "!==")
        is_one = (n.b.kind == :bigint && n.b.str == "1") || (n.b.kind == :num && n.b.a == ~1.0)
        is_zero = (n.c.kind == :bigint && n.c.str == "0") || (n.c.kind == :num && n.c.a == ~0.0)
        return cv if is_one && is_zero
      tv = lower_expr(n.b, ty)
      fv = lower_expr(n.c, ty)
      return @wf.emit_sel(ty == :f64 ? :select_f64 : :select_i64, cv, tv, fv, ty)
    elsif k == :call
      cal = n.a
      if cal.kind == :member && cal.a.kind == :ident && cal.a.a == nil && cal.a.str == "BigInt"
        if cal.b.str == "asUintN" && n.list.size == 2
          return convert_val(lower_expr(n.list[1], :u64), :u64, want_ty)
        if cal.b.str == "asIntN" && n.list.size == 2
          return convert_val(lower_expr(n.list[1], :i64), :i64, want_ty)
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
    elsif tk == 10 || tk == 9
      rt_w = expr_type(rhs_node)
      if rt_w == :u128 || rt_w == :i128_diff
        wp = lower_wide_big(rhs_node)
        @wf.emit_ta_set(ptr_vr, idx_vr, wp[0], eb)
      else
        v = lower_expr(rhs_node, tk == 10 ? :u64 : :i64)
        @wf.emit_ta_set(ptr_vr, idx_vr, v, eb)
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
        if j2w_is_wide_big?(t)
          sl_lo = @var_slots[nm]
          sl_hi = @var_hi_slots[nm]
          if sl_lo == nil
            sl_lo = @wf.new_slot(:i64, nm + "_lo")
            @var_slots[nm] = sl_lo
          if sl_hi == nil
            sl_hi = @wf.new_slot(:i64, nm + "_hi")
            @var_hi_slots[nm] = sl_hi
          @var_diff_borrow[nm] = j2w_is_i128_sub_ty?(t)
          if d.b != nil
            wp = lower_wide_big(d.b)
            @wf.emit_store_slot(sl_lo, wp[0])
            @wf.emit_store_slot(sl_hi, wp[1])
          else
            z = @wf.emit_const_i64(0)
            @wf.emit_store_slot(sl_lo, z)
            @wf.emit_store_slot(sl_hi, z)
        else
          nt = j2w_norm_ty(t)
          sl_ty = nt == :f64 ? :f64 : :i64
          sl = @var_slots[nm]
          if sl == nil
            sl = @wf.new_slot(sl_ty, nm)
            @var_slots[nm] = sl
          vr = d.b != nil ? lower_expr(d.b, nt) : (sl_ty == :f64 ? @wf.emit_const_f64(~0.0) : @wf.emit_const_i64(0))
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
          raw_t = @var_types[nm] != nil ? @var_types[nm] : :f64
          if j2w_is_wide_big?(raw_t)
            if e.str != "=" || @var_hi_slots[nm] == nil
              @failed = true
              return nil
            wp = lower_wide_big(e.b)
            @wf.emit_store_slot(sl, wp[0])
            @wf.emit_store_slot(@var_hi_slots[nm], wp[1])
          else
            t = j2w_norm_ty(raw_t)
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
              elsif t == :u64 || raw_t == :i64_big
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
        t = j2w_norm_ty(@var_types[nm] != nil ? @var_types[nm] : :i64)
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
  return :u64 if (t1 == :u1_big && t2 == :u64) || (t1 == :u64 && t2 == :u1_big)
  return :u128 if j2w_is_u128_ty?(t1) && j2w_is_u128_ty?(t2)
  return :i128_diff if j2w_is_i128_sub_ty?(t1) && j2w_is_i128_sub_ty?(t2)
  return :u64 if t1 == :u64 || t2 == :u64 || t1 == :i64_big || t2 == :i64_big
  :f64

-> j2w_expr_ty(n, vtypes, ta_kinds)
  return :f64 if n == nil
  k = n.kind
  if k == :ident
    t = vtypes[n.str]
    return t != nil ? t : :f64
  if k == :bigint
    return (n.str == "0" || n.str == "1") ? :u1_big : :u64
  return j2w_int_lit?(n) ? :i64 : :f64 if k == :num
  return :i64 if k == :true || k == :false
  if k == :member
    if n.has?(F_COMPUTED)
      tk = ta_kinds[n.a.str]
      return :u64 if tk == 10
      return :i64_big if tk == 9
      return :i64 if tk != nil && tk <= 6
      return :f64
    return :i64
  if k == :unary
    if n.str == "-" && n.a != nil && n.a.kind == :binary && n.a.str == ">>" && j2w_is_i128_sub_ty?(j2w_expr_ty(n.a.a, vtypes, ta_kinds)) && n.a.b.kind == :bigint && n.a.b.str == "64"
      return :u1_big
    return :i64 if n.str == "~" || n.str == "!"
    return j2w_expr_ty(n.a, vtypes, ta_kinds)
  if k == :binary
    op = n.str
    return :i64 if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
    lt = j2w_expr_ty(n.a, vtypes, ta_kinds)
    rt = j2w_expr_ty(n.b, vtypes, ta_kinds)
    if op == ">>" && n.b.kind == :bigint && n.b.str == "64"
      return :u64 if j2w_is_u128_ty?(lt)
      return :i64_big if j2w_is_i128_sub_ty?(lt)
    if op == "&" && n.b.kind == :bigint && n.b.str == "1" && (j2w_is_i128_sub_ty?(lt) || lt == :i64_big || lt == :u64 || lt == :u1_big)
      return :u1_big
    if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
      return (lt == :u64 || rt == :u64 || lt == :u1_big || rt == :u1_big || lt == :i64_big || rt == :i64_big) ? :u64 : :i64
    if op == "+" && (lt == :u64 || lt == :u1_big || j2w_is_u128_ty?(lt)) && (rt == :u64 || rt == :u1_big || j2w_is_u128_ty?(rt))
      return :u128
    if op == "*" && (lt == :u64 || lt == :u1_big) && (rt == :u64 || rt == :u1_big)
      return :u128
    if op == "-"
      if n.a.kind == :bigint && n.a.str == "0" && n.b.kind == :binary && n.b.str == ">>" && j2w_is_i128_sub_ty?(j2w_expr_ty(n.b.a, vtypes, ta_kinds)) && n.b.b.kind == :bigint && n.b.b.str == "64"
        return :u1_big
      if (lt == :u64 || lt == :u1_big || j2w_is_i128_sub_ty?(lt)) && (rt == :u64 || rt == :u1_big)
        return :i128_diff
    return :u64 if lt == :u64 || rt == :u64 || lt == :i64_big || rt == :i64_big
    return :f64 if op == "/" || lt == :f64 || rt == :f64
    return :i64 if (op == "+" || op == "-" || op == "*") && lt == :i64 && rt == :i64
    return :f64
  if k == :cond
    return j2w_join_ty(j2w_expr_ty(n.b, vtypes, ta_kinds), j2w_expr_ty(n.c, vtypes, ta_kinds))
  if k == :call && n.a.kind == :member && n.a.a.kind == :ident
    return :u64 if n.a.a.str == "BigInt" && n.a.b.str == "asUintN"
    return :i64_big if n.a.a.str == "BigInt"
    return :i64 if n.a.a.str == "Math" && n.a.b.str == "imul"
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
        nm = s.a.a.str
        rt = j2w_expr_ty(s.a.b, vtypes, ta_kinds)
        nt = rt
        if s.a.str != "="
          bop = s.a.str.slice(0, s.a.str.size - 1)
          cur = vtypes[nm]
          if bop == "^" || bop == "|" || bop == "&"
            nt = (cur == :u64 || rt == :u64 || cur == :i64_big || rt == :i64_big || cur == :u1_big || rt == :u1_big) ? :u64 : :i64
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

# Lower a qualifying `JaFunc` AST into a reusable `WireFunc` (without running IR passes yet).
# This `WireFunc` can be compiled immediately at `tier = 1` (~5 us) and later re-compiled at
# `tier = 2` (full multi-pass optimizer + hardware carry chains + SIMD) to hot-swap `desc.fp`!
-> wire_a64_lower_js_func(jf, param_specs, ret_type_str, inferred_vtypes = nil)
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
    elsif sp[0] == :i64 || sp[0] == :u64
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
      vt[params[pi]] = sp[0] == :ta ? :arr : (sp[0] == :u64 ? :u64 : (sp[0] == :i64 ? :i64 : :f64))
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
    elsif sp[0] == :u64
      lo.var_types[nm] = :u64
    elsif sp[0] == :i64
      lo.var_types[nm] = :i64
    else
      lo.var_types[nm] = :f64
    i += 1
  fn_node.b.each ->(st) lo.lower_stmt(st)
  return nil if lo.failed
  # Fallback default return at end of function
  wf.emit_ret(rty == :f64 ? wf.emit_const_f64(~0.0) : wf.emit_const_i64(0))
  wf

# Compile a qualifying JaFunc AST directly via WIRE IR -> native machine code (ZERO clang, ZERO LLVM!).
# `tier = 1`: blazing-fast single-pass baseline; `tier = 2` (default): full multi-pass optimizer.
# Returns [fp, code_bytes, compile_us] or nil if unsupported.
-> wire_a64_compile_js_func(jf, param_specs, ret_type_str, inferred_vtypes = nil, tier = 2)
  wf = wire_a64_lower_js_func(jf, param_specs, ret_type_str, inferred_vtypes)
  return nil if wf == nil
  res = wire_compile_func_tier(wf, tier)
  return nil if res[0] == 0
  res
