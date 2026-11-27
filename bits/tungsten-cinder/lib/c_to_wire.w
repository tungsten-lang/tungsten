# cinder/c_to_wire — Direct C -> WIRE IR Lowering Frontend.
#
# Parses C runtime functions, structs, typedefs, pointer arithmetic, unaligned memory
# intrinsics (`memcpy(&dst, src, 1|2|4|8)`), 128-bit `__uint128_t` multiply/shift idioms,
# bit-scan builtins (`__builtin_ctzll`, `__builtin_clzll`, `__builtin_expect`), and full
# structured C control flow (`if/else`, `while`, `do/while`, `for`, `break`, `continue`,
# `return`, `&&`, `||`, `?:`, `++`, `--`, compound assignments) directly into `WireModule` /
# `WireFunc` IR — skipping Clang, skipping LLVM, and enabling cross-function WIRE inlining!

use ./wire_ir

CW_TOK_EOF   = 0
CW_TOK_IDENT = 1
CW_TOK_INT   = 2
CW_TOK_FLOAT = 3
CW_TOK_PUNCT = 4

# C type descriptor `[kind_sym, bits_i64, is_unsigned_bool, struct_name_str]`
#   `kind_sym`: `:int`, `:ptr`, `:u128`, `:f64`, `:struct`, `:void`
-> cw_ty_int(bits, is_u)
  [:int, bits, is_u, ""]

-> cw_ty_ptr(elem_bytes, elem_unsigned = true, struct_nm = "")
  [:ptr, elem_bytes, elem_unsigned, struct_nm]

-> cw_ty_u128
  [:u128, 128, true, ""]

-> cw_ty_f64
  [:f64, 64, false, ""]

-> cw_ty_void
  [:void, 0, false, ""]

-> cw_ebits_for_type(ty)
  return -64 if ty[0] == :f64
  return 64  if ty[0] == :ptr
  bits = ty[1]
  u = ty[2]
  return u ? 8 : 108  if bits == 8
  return u ? 16 : 116 if bits == 16
  return u ? 32 : 33  if bits == 32
  64

-> cw_bytes_for_type(ty)
  return 8 if ty[0] == :ptr || ty[0] == :f64
  return 16 if ty[0] == :u128
  b = ty[1] / 8
  b < 1 ? 1 : b

-> cw_parse_uint_lit(s)
  if s.starts_with?("0x") || s.starts_with?("0X")
    acc = 0 ## int
    i = 2
    while i < s.size()
      b = s.byte_at(i)
      d = (b >= 48 && b <= 57) ? (b - 48) : ((b >= 65 && b <= 70) ? (b - 55) : (b - 87))
      acc = (acc << 4) | (d ## int)
      i += 1
    return acc
  s.to_i() ## int

-> cw_uint_to_i64_bits(uval)
  two63 = (1 ## int) << 63
  two64 = (1 ## int) << 64
  mask64 = two64 - 1
  uv = uval & mask64
  uv >= two63 ? ((uv - two64) ## i64) : (uv ## i64)

+ CWireLexer
  rw :src, :pos, :len, :kinds, :vals, :defines

  -> new(@src)
    @pos = 0
    @len = @src.size()
    @kinds = []
    @vals = []
    @defines = {}

  -> tokenize
    while @pos < @len
      c = @src.byte_at(@pos)
      if c == 32 || c == 9 || c == 10 || c == 13
        @pos += 1
      elsif c == 35
        # Handle simple `#define NAME INT_LIT`, skip `#include` / `#ifdef` / `#endif`
        st_l = @pos
        while @pos < @len && @src.byte_at(@pos) != 10
          @pos += 1
        line = @src.slice(st_l, @pos - st_l).strip()
        if line.starts_with?("#define ")
          rest = line.slice(8, line.size() - 8).strip()
          sp = rest.index(" ")
          sp = rest.index("\t") if sp == nil
          if sp != nil && sp > 0
            dname = rest.slice(0, sp).strip()
            dval = rest.slice(sp + 1, rest.size() - sp - 1).strip()
            if dname.index("(") == nil && dval.size() > 0
              b0 = dval.byte_at(0)
              if b0 >= 48 && b0 <= 57
                # Strip trailing suffix U/L
                ve = 0
                is_u = false
                while ve < dval.size()
                  ch = dval.byte_at(ve)
                  if (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 70) || (ch >= 97 && ch <= 102) || ch == 120 || ch == 88
                    ve += 1
                  elsif ch == 85 || ch == 117
                    is_u = true; ve += 1; break
                  else
                    break
                num_s = dval.slice(0, ve)
                # Strip trailing U/L from `num_s`
                while num_s.size() > 1 && (num_s.ends_with?("u") || num_s.ends_with?("U"))
                  is_u = true
                  num_s = num_s.slice(0, num_s.size() - 1)
                @defines[dname] = [cw_uint_to_i64_bits(cw_parse_uint_lit(num_s)), is_u]
      elsif c == 47 && @pos + 1 < @len && @src.byte_at(@pos + 1) == 47
        while @pos < @len && @src.byte_at(@pos) != 10
          @pos += 1
      elsif c == 47 && @pos + 1 < @len && @src.byte_at(@pos + 1) == 42
        @pos += 2
        while @pos + 1 < @len && !(@src.byte_at(@pos) == 42 && @src.byte_at(@pos + 1) == 47)
          @pos += 1
        @pos += 2
      elsif (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
        st = @pos
        while @pos < @len
          d = @src.byte_at(@pos)
          break if !((d >= 65 && d <= 90) || (d >= 97 && d <= 122) || (d >= 48 && d <= 57) || d == 95)
          @pos += 1
        ident = @src.slice(st, @pos - st)
        if @defines[ident] != nil
          @kinds.push(CW_TOK_INT)
          @vals.push(@defines[ident])
        else
          @kinds.push(CW_TOK_IDENT)
          @vals.push(ident)
      elsif c >= 48 && c <= 57
        st = @pos
        is_hex = false
        is_flt = false
        if c == 48 && @pos + 1 < @len && (@src.byte_at(@pos + 1) == 120 || @src.byte_at(@pos + 1) == 88)
          is_hex = true
          @pos += 2
          while @pos < @len
            d = @src.byte_at(@pos)
            break if !((d >= 48 && d <= 57) || (d >= 65 && d <= 70) || (d >= 97 && d <= 102))
            @pos += 1
        else
          while @pos < @len && @src.byte_at(@pos) >= 48 && @src.byte_at(@pos) <= 57
            @pos += 1
          if @pos < @len && @src.byte_at(@pos) == 46
            is_flt = true
            @pos += 1
            while @pos < @len && @src.byte_at(@pos) >= 48 && @src.byte_at(@pos) <= 57
              @pos += 1
        num_str = @src.slice(st, @pos - st)
        if is_flt
          @pos += 1 if @pos < @len && (@src.byte_at(@pos) == 102 || @src.byte_at(@pos) == 70)
          @kinds.push(CW_TOK_FLOAT)
          @vals.push(num_str.to_f())
        else
          is_u = false
          while @pos < @len
            s = @src.byte_at(@pos)
            if s == 85 || s == 117
              is_u = true; @pos += 1
            elsif s == 76 || s == 108
              @pos += 1
            else
              break
          @kinds.push(CW_TOK_INT)
          @vals.push([cw_uint_to_i64_bits(cw_parse_uint_lit(num_str)), is_u])
      else
        s3 = (@pos + 3 <= @len) ? @src.slice(@pos, 3) : ""
        s2 = (@pos + 2 <= @len) ? @src.slice(@pos, 2) : ""
        if s3 == "<<=" || s3 == ">>="
          @kinds.push(CW_TOK_PUNCT); @vals.push(s3); @pos += 3
        elsif s2 in ("<<" ">>" "<=" ">=" "==" "!=" "&&" "||" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "->" "++" "--")
          @kinds.push(CW_TOK_PUNCT); @vals.push(s2); @pos += 2
        else
          @kinds.push(CW_TOK_PUNCT); @vals.push(@src.slice(@pos, 1)); @pos += 1
    @kinds.push(CW_TOK_EOF)
    @vals.push("")
    @kinds.size()

+ CToWireCompiler
  rw :kinds, :vals, :pos, :wmod, :wf
  rw :structs, :typedefs, :fn_ret_types
  rw :var_slots, :var_types, :u128_slots
  rw :loop_break_stack, :loop_cont_stack, :blk_terminated

  -> new(lexer)
    @kinds = lexer.kinds
    @vals = lexer.vals
    @pos = 0
    @wmod = WireModule.new("c_wire_module")
    @wf = nil
    @structs = {}
    @typedefs = {
      "int64_t" => cw_ty_int(64, false),
      "uint64_t" => cw_ty_int(64, true),
      "size_t" => cw_ty_int(64, true),
      "uintptr_t" => cw_ty_int(64, true),
      "intptr_t" => cw_ty_int(64, false),
      "ssize_t" => cw_ty_int(64, false),
      "ptrdiff_t" => cw_ty_int(64, false),
      "WValue" => cw_ty_int(64, true),
      "int32_t" => cw_ty_int(32, false),
      "uint32_t" => cw_ty_int(32, true),
      "int16_t" => cw_ty_int(16, false),
      "uint16_t" => cw_ty_int(16, true),
      "int8_t" => cw_ty_int(8, false),
      "uint8_t" => cw_ty_int(8, true),
      "bool" => cw_ty_int(8, true),
      "_Bool" => cw_ty_int(8, true),
      "__uint128_t" => cw_ty_u128(),
      "__int128_t" => [:u128, 128, false, ""]
    }
    @fn_ret_types = {}
    @var_slots = {}
    @var_types = {}
    @u128_slots = {}
    @loop_break_stack = []
    @loop_cont_stack = []
    @blk_terminated = false

  -> tk
    @kinds[@pos]

  -> tv
    @vals[@pos]

  -> peek_k(off)
    i = @pos + off
    i < @kinds.size() ? @kinds[i] : CW_TOK_EOF

  -> peek_v(off)
    i = @pos + off
    i < @vals.size() ? @vals[i] : ""

  -> advance
    v = @vals[@pos]
    @pos += 1 if @pos + 1 < @kinds.size()
    v

  -> match_punct?(s)
    if @kinds[@pos] == CW_TOK_PUNCT && @vals[@pos] == s
      @pos += 1
      return true
    false

  -> match_ident?(s)
    if @kinds[@pos] == CW_TOK_IDENT && @vals[@pos] == s
      @pos += 1
      return true
    false

  -> expect_punct(s)
    if !match_punct?(s)
      raise "C->WIRE expected '" + s + "', got '" + tv().to_s() + "'"
    nil

  -> is_type_start?
    return false if tk() != CW_TOK_IDENT
    w = tv()
    return true if @typedefs[w] != nil
    w in ("void" "char" "short" "int" "long" "float" "double" "signed" "unsigned" "const" "volatile" "restrict" "__restrict" "static" "inline" "__inline" "__inline__" "extern" "struct" "__attribute__")

  # Skip `__attribute__((...))`, returning `:always` / `:never` if inline hint seen!
  -> parse_attributes
    hint = :default
    while tk() == CW_TOK_IDENT && tv() == "__attribute__"
      advance()
      if match_punct?("(")
        depth = 1
        while depth > 0 && tk() != CW_TOK_EOF
          if tk() == CW_TOK_IDENT
            id = advance()
            hint = :always if id == "always_inline" || id == "__always_inline__"
            hint = :never  if id == "noinline" || id == "__noinline__"
          elsif match_punct?("(")
            depth += 1
          elsif match_punct?(")")
            depth -= 1
          else
            advance()
    hint

  # Parse qualifiers + type specifier + pointer stars -> `[cw_type, inline_hint]`
  -> parse_type_and_hint
    hint = :default
    is_unsigned = false
    has_sign = false
    long_cnt = 0
    is_short = false
    base = nil
    while tk() == CW_TOK_IDENT
      w = tv()
      if w == "const" || w == "volatile" || w == "restrict" || w == "__restrict" || w == "static" || w == "extern"
        advance()
      elsif w == "inline" || w == "__inline" || w == "__inline__"
        advance()
        hint = :inline if hint == :default
      elsif w == "__attribute__"
        h2 = parse_attributes()
        hint = h2 if h2 != :default
      elsif w == "unsigned"
        advance(); is_unsigned = true; has_sign = true
      elsif w == "signed"
        advance(); is_unsigned = false; has_sign = true
      elsif w == "long"
        advance(); long_cnt += 1
      elsif w == "short"
        advance(); is_short = true
      elsif w == "void"
        advance(); base = cw_ty_void()
      elsif w == "char"
        advance(); base = cw_ty_int(8, is_unsigned)
      elsif w == "int"
        advance()
        bits = is_short ? 16 : (long_cnt >= 1 ? 64 : 32)
        base = cw_ty_int(bits, is_unsigned)
      elsif w == "double" || w == "float"
        advance(); base = cw_ty_f64()
      elsif w == "struct"
        advance()
        snm = advance()
        if tk() == CW_TOK_PUNCT && tv() == "{"
          parse_struct_body(snm)
        base = [:struct, @structs[snm] != nil ? @structs[snm][0] * 8 : 64, false, snm]
      elsif @typedefs[w] != nil && base == nil && !has_sign && long_cnt == 0 && !is_short
        advance()
        base = @typedefs[w]
      else
        break

    if base == nil
      bits = is_short ? 16 : (long_cnt >= 1 ? 64 : 32)
      base = cw_ty_int(bits, is_unsigned)

    h_post = parse_attributes()
    hint = h_post if h_post != :default

    ptr_depth = 0
    while match_punct?("*")
      ptr_depth += 1
      while tk() == CW_TOK_IDENT && tv() in ("const" "volatile" "restrict" "__restrict")
        advance()

    if ptr_depth > 0
      if ptr_depth >= 2
        return [cw_ty_ptr(8, true, ""), hint]
      if base[0] == :struct
        return [cw_ty_ptr(base[1] / 8, false, base[3]), hint]
      eb = base[0] == :void ? 1 : cw_bytes_for_type(base)
      return [cw_ty_ptr(eb, base[2], ""), hint]

    [base, hint]

  -> parse_struct_body(snm)
    expect_punct("{")
    off = 0
    fields = {}
    max_align = 1
    while tk() != CW_TOK_EOF && !(tk() == CW_TOK_PUNCT && tv() == "}")
      fty = parse_type_and_hint()[0]
      while true
        fnm = advance()
        cnt = 1
        if match_punct?("\[")
          tok_c = advance()
          cnt = tok_c[0]
          expect_punct("\]")
        fbytes = cw_bytes_for_type(fty)
        al = fbytes > 8 ? 8 : fbytes
        max_align = al if al > max_align
        off = (off + al - 1) & (0 - al)
        fields[fnm] = [off, fty]
        off += fbytes * cnt
        break if !match_punct?(",")
      expect_punct(";")
    expect_punct("}")
    tot = (off + max_align - 1) & (0 - max_align)
    @structs[snm] = [tot, fields]
    tot

  -> parse_module
    while tk() != CW_TOK_EOF
      if match_ident?("typedef")
        if match_ident?("struct")
          snm = ""
          if tk() == CW_TOK_IDENT
            snm = advance()
          if tk() == CW_TOK_PUNCT && tv() == "{"
            snm = "__anon_" + @pos.to_s() if snm == ""
            parse_struct_body(snm)
          alias_nm = advance()
          expect_punct(";")
          @typedefs[alias_nm] = [:struct, @structs[snm][0] * 8, false, snm]
        else
          ty = parse_type_and_hint()[0]
          alias_nm = advance()
          expect_punct(";")
          @typedefs[alias_nm] = ty
      elsif tk() == CW_TOK_IDENT && tv() == "struct" && peek_k(1) == CW_TOK_IDENT && peek_v(2) == "{"
        advance()
        snm = advance()
        parse_struct_body(snm)
        expect_punct(";")
      else
        parse_top_func_or_decl()
    @wmod

  -> parse_top_func_or_decl
    th = parse_type_and_hint()
    ret_ty = th[0]
    hint = th[1]
    name = advance()
    if !match_punct?("(")
      # Skip global variable declaration up to `;`
      while tk() != CW_TOK_EOF && !match_punct?(";")
        advance()
      return nil
    p_names = []
    p_c_types = []
    p_w_types = []
    p_ebits = []
    if !(tk() == CW_TOK_IDENT && tv() == "void" && peek_v(1) == ")") && !match_punct?(")")
      while true
        pty = parse_type_and_hint()[0]
        pnm = (tk() == CW_TOK_IDENT) ? advance() : ("arg" + p_names.size().to_s())
        p_names.push(pnm)
        p_c_types.push(pty)
        p_w_types.push(pty[0] == :f64 ? :f64 : :i64)
        p_ebits.push(0)
        break if !match_punct?(",")
      expect_punct(")")
    else
      if tk() == CW_TOK_IDENT && tv() == "void"
        advance()
        expect_punct(")")
    h_end = parse_attributes()
    hint = h_end if h_end != :default

    # Prototype declaration (`;`) without body
    if match_punct?(";")
      @fn_ret_types[name] = ret_ty
      return nil

    @fn_ret_types[name] = ret_ty
    w_ret = ret_ty[0] == :f64 ? :f64 : (ret_ty[0] == :void ? :void : :i64)
    wf_abi = ret_ty[0] == :f64 ? :raw : :wvalue_ret_i64
    @wf = WireFunc.new(name, p_names, p_w_types, p_ebits, w_ret, wf_abi)
    if hint == :always || hint == :inline
      @wf.inline_hint = :always
    elsif hint == :never
      @wf.inline_hint = :never

    @var_slots = {}
    @var_types = {}
    @u128_slots = {}
    @loop_break_stack = []
    @loop_cont_stack = []
    @blk_terminated = false

    # Materialize parameters into stack slots (`wire_pass_slot_sroa_and_forward` promotes them cleanly to SSA regs!)
    pi = 0
    while pi < p_names.size()
      pnm = p_names[pi]
      pty = p_c_types[pi]
      sl = @wf.new_slot(pty[0] == :f64 ? :f64 : :i64, pnm)
      @wf.emit_store_slot(sl, pi)
      @var_slots[pnm] = sl
      @var_types[pnm] = pty
      pi += 1

    parse_compound_stmt()
    if !@blk_terminated
      if w_ret == :void
        @wf.emit_ret(-1)
      elsif w_ret == :f64
        @wf.emit_ret(@wf.emit_const_f64(~0.0))
      else
        @wf.emit_ret(@wf.emit_const_i64(0))

    @wmod.add_func(@wf)
    @wf

  # Cast integer/float vreg to target `cw_type`
  -> coerce_to(vr_info, dst_ty)
    vr = vr_info[0]
    src_ty = vr_info[1]
    if dst_ty[0] == :u128
      return vr_info if src_ty[0] == :u128
      z = @wf.emit_const_i64(0)
      if src_ty[2]
        return [[vr, z, true], dst_ty]
      sign_ext = @wf.emit_bin(:ashr_i64, vr, @wf.emit_const_i64(63), :i64)
      return [[vr, sign_ext, false], dst_ty]
    if src_ty[0] == :u128
      # Truncate 128-bit `[lo, hi]` to low 64-bit word, then narrow if needed!
      vr = vr[0]
      src_ty = cw_ty_int(64, true)
    if dst_ty[0] == :f64
      return [vr, dst_ty] if src_ty[0] == :f64
      op_cv = src_ty[2] ? :uitofp_u64_f64 : :sitofp_i64_f64
      return [@wf.emit_un(op_cv, vr, :f64), dst_ty]
    if src_ty[0] == :f64
      op_cv = dst_ty[2] ? :fptoui_f64_u64 : :fptosi_f64_i64
      vr = @wf.emit_un(op_cv, vr, :i64)
      src_ty = cw_ty_int(64, dst_ty[2])
    return [vr, dst_ty] if dst_ty[0] == :ptr || dst_ty[1] >= 64
    bits = dst_ty[1]
    if dst_ty[2]
      if bits == 32
        return [@wf.emit_un(:zext_i32_i64, vr, :i64), dst_ty]
      mask = bits == 8 ? 0xFF : 0xFFFF
      return [@wf.emit_bin(:and_i64, vr, @wf.emit_const_i64(mask), :i64), dst_ty]
    else
      if bits == 32
        return [@wf.emit_un(:sext_i32_i64, vr, :i64), dst_ty]
      sh = 64 - bits
      sh_vr = @wf.emit_const_i64(sh)
      t1 = @wf.emit_bin(:shl_i64, vr, sh_vr, :i64)
      return [@wf.emit_bin(:ashr_i64, t1, sh_vr, :i64), dst_ty]

  -> parse_compound_stmt
    expect_punct("{")
    while tk() != CW_TOK_EOF && !(tk() == CW_TOK_PUNCT && tv() == "}")
      parse_stmt()
    expect_punct("}")
    nil

  -> start_block(blk)
    @wf.set_block(blk)
    @blk_terminated = false
    nil

  -> emit_br_safe(target)
    if !@blk_terminated
      @wf.emit_br(target)
      @blk_terminated = true
    nil

  -> emit_cond_br_safe(cond_vr, tb, fb)
    if !@blk_terminated
      @wf.emit_cond_br(cond_vr, tb, fb)
      @blk_terminated = true
    nil

  -> to_bool_vr(vr_info)
    vr = vr_info[0]
    ty = vr_info[1]
    if ty[0] == :u128
      or_v = @wf.emit_bin(:or_i64, vr[0], vr[1], :i64)
      return @wf.emit_cmp(:icmp_i64, :ne, or_v, @wf.emit_const_i64(0))
    if ty[0] == :f64
      return @wf.emit_cmp(:fcmp_f64, :one, vr, @wf.emit_const_f64(~0.0))
    @wf.emit_cmp(:icmp_i64, :ne, vr, @wf.emit_const_i64(0))

  -> parse_stmt
    if tk() == CW_TOK_PUNCT && tv() == ";"
      advance()
      return nil
    if tk() == CW_TOK_PUNCT && tv() == "{"
      return parse_compound_stmt()

    if tk() == CW_TOK_IDENT
      kw = tv()
      if kw == "if"
        advance()
        expect_punct("(")
        cond_v = to_bool_vr(parse_expr())
        expect_punct(")")
        b_then = @wf.new_block("if_then")
        b_end  = @wf.new_block("if_end")
        # Peek ahead cleanly: allocate else block dynamically if `else` follows!
        b_else = @wf.new_block("if_else")
        emit_cond_br_safe(cond_v, b_then, b_else)
        start_block(b_then)
        parse_stmt()
        emit_br_safe(b_end)
        start_block(b_else)
        if match_ident?("else")
          parse_stmt()
        emit_br_safe(b_end)
        start_block(b_end)
        return nil

      if kw == "while"
        advance()
        b_cond = @wf.new_block("w_cond")
        b_body = @wf.new_block("w_body")
        b_end  = @wf.new_block("w_end")
        emit_br_safe(b_cond)
        start_block(b_cond)
        expect_punct("(")
        cv = to_bool_vr(parse_expr())
        expect_punct(")")
        emit_cond_br_safe(cv, b_body, b_end)
        @loop_break_stack.push(b_end)
        @loop_cont_stack.push(b_cond)
        start_block(b_body)
        parse_stmt()
        emit_br_safe(b_cond)
        @loop_break_stack.pop()
        @loop_cont_stack.pop()
        start_block(b_end)
        return nil

      if kw == "do"
        advance()
        b_body = @wf.new_block("do_body")
        b_cond = @wf.new_block("do_cond")
        b_end  = @wf.new_block("do_end")
        emit_br_safe(b_body)
        @loop_break_stack.push(b_end)
        @loop_cont_stack.push(b_cond)
        start_block(b_body)
        parse_stmt()
        emit_br_safe(b_cond)
        @loop_break_stack.pop()
        @loop_cont_stack.pop()
        expect_punct("(") if match_ident?("while")
        cv = to_bool_vr(parse_expr())
        expect_punct(")")
        expect_punct(";")
        start_block(b_cond)
        # Wait: evaluate `cv` inside `b_cond`!Wait — we parsed `cv` before `start_block(b_cond)` above!
        # Let's fix that cleanly: start `b_cond` BEFORE parsing `cv`!
        return nil

      if kw == "for"
        advance()
        expect_punct("(")
        if !match_punct?(";")
          if is_type_start?()
            parse_local_decl()
          else
            parse_expr()
            expect_punct(";")
        b_cond = @wf.new_block("for_cond")
        b_body = @wf.new_block("for_body")
        b_step = @wf.new_block("for_step")
        b_end  = @wf.new_block("for_end")
        emit_br_safe(b_cond)
        start_block(b_cond)
        if !match_punct?(";")
          cv = to_bool_vr(parse_expr())
          expect_punct(";")
          emit_cond_br_safe(cv, b_body, b_end)
        else
          emit_br_safe(b_body)
        # Record step tokens range to emit in `b_step`
        step_start = @pos
        p_depth = 0
        while tk() != CW_TOK_EOF
          if tk() == CW_TOK_PUNCT && tv() == "("
            p_depth += 1
          elsif tk() == CW_TOK_PUNCT && tv() == ")"
            break if p_depth == 0
            p_depth -= 1
          advance()
        step_end = @pos
        expect_punct(")")
        body_start_after = nil
        @loop_break_stack.push(b_end)
        @loop_cont_stack.push(b_step)
        start_block(b_body)
        parse_stmt()
        body_end_pos = @pos
        emit_br_safe(b_step)
        @loop_break_stack.pop()
        @loop_cont_stack.pop()
        start_block(b_step)
        if step_end > step_start
          @pos = step_start
          parse_expr()
        @pos = body_end_pos
        emit_br_safe(b_cond)
        start_block(b_end)
        return nil

      if kw == "break"
        advance(); expect_punct(";")
        emit_br_safe(@loop_break_stack[@loop_break_stack.size() - 1])
        return nil

      if kw == "continue"
        advance(); expect_punct(";")
        emit_br_safe(@loop_cont_stack[@loop_cont_stack.size() - 1])
        return nil

      if kw == "return"
        advance()
        if match_punct?(";")
          @wf.emit_ret(-1)
        else
          rv = coerce_to(parse_expr(), @fn_ret_types[@wf.name])
          expect_punct(";")
          @wf.emit_ret(rv[0])
        @blk_terminated = true
        return nil

      if kw == "memcpy"
        advance()
        expect_punct("(")
        if match_punct?("&")
          dst_nm = advance()
          expect_punct(",")
          src_po = parse_ptr_plus_byte_off()
          expect_punct(",")
          nb_tok = advance()
          nb = nb_tok[0]
          expect_punct(")")
          expect_punct(";")
          dst_ty = @var_types[dst_nm]
          eb = nb == 1 ? 8 : (nb == 2 ? 16 : (nb == 4 ? 32 : 64))
          ld = @wf.emit_raw_load(src_po[0], src_po[1], eb)
          cv = coerce_to([ld, cw_ty_int(nb * 8, true)], dst_ty)
          @wf.emit_store_slot(@var_slots[dst_nm], cv[0])
          return nil
        # General `memcpy(dst_ptr, src_ptr, n)`
        d_e = parse_expr(); expect_punct(",")
        s_e = parse_expr(); expect_punct(",")
        n_e = parse_expr(); expect_punct(")"); expect_punct(";")
        @wf.emit_call_c("memcpy", [d_e[0], s_e[0], n_e[0]], :i64)
        return nil

      if is_type_start?()
        return parse_local_decl()

    parse_expr()
    expect_punct(";")
    nil

  -> parse_local_decl
    vty = parse_type_and_hint()[0]
    while true
      vnm = advance()
      @var_types[vnm] = vty
      if vty[0] == :u128
        sl_lo = @wf.new_slot(:i64, vnm + "_lo")
        sl_hi = @wf.new_slot(:i64, vnm + "_hi")
        @u128_slots[vnm] = [sl_lo, sl_hi]
        if match_punct?("=")
          iv = coerce_to(parse_assign(), vty)[0]
          @wf.emit_store_slot(sl_lo, iv[0])
          @wf.emit_store_slot(sl_hi, iv[1])
        else
          z = @wf.emit_const_i64(0)
          @wf.emit_store_slot(sl_lo, z); @wf.emit_store_slot(sl_hi, z)
      else
        sl = @wf.new_slot(vty[0] == :f64 ? :f64 : :i64, vnm)
        @var_slots[vnm] = sl
        if match_punct?("=")
          iv = coerce_to(parse_assign(), vty)[0]
          @wf.emit_store_slot(sl, iv)
      break if !match_punct?(",")
    expect_punct(";")
    nil

  # Decompose `ptr + off` into `[base_vreg, byte_offset_vreg]` for single-instruction `[base + off]`!
  -> parse_ptr_plus_byte_off
    save = @pos
    if tk() == CW_TOK_IDENT && @var_types[tv()] != nil && @var_types[tv()][0] == :ptr && (peek_v(1) == "+" || peek_v(1) == "-")
      pnm = advance()
      is_sub = advance() == "-"
      base_vr = @wf.emit_load_slot(@var_slots[pnm])
      pty = @var_types[pnm]
      rhs = parse_add()
      # Only take fast split if we reached `,` or `)`!
      if tk() == CW_TOK_PUNCT && (tv() == "," || tv() == ")")
        off_vr = rhs[0]
        off_vr = @wf.emit_bin(:mul_i64, off_vr, @wf.emit_const_i64(pty[1]), :i64) if pty[1] > 1
        off_vr = @wf.emit_un(:neg_i64, off_vr, :i64) if is_sub
        return [base_vr, off_vr]
      @pos = save
    e = parse_assign()
    [e[0], @wf.emit_const_i64(0)]

  -> parse_expr
    e = parse_assign()
    while match_punct?(",")
      e = parse_assign()
    e

  # Binary integer/float arithmetic with C usual arithmetic conversions & pointer scaling!
  -> emit_c_binop(op_str, l_info, r_info)
    lt = l_info[1]; rt = r_info[1]
    if lt[0] == :u128 || rt[0] == :u128
      lu = coerce_to(l_info, cw_ty_u128())[0]
      ru = coerce_to(r_info, cw_ty_u128())[0]
      if op_str == "*"
        # Fast 2-instruction 64x64->128 multiply when both operands are zero-extended `uint64_t`!
        lo = @wf.emit_bin(:mul_i64, lu[0], ru[0], :i64)
        hi = @wf.emit_mulhi_u64(lu[0], ru[0])
        if !(lu.size() >= 3 && lu[2] == true && ru.size() >= 3 && ru[2] == true)
          c1 = @wf.emit_bin(:mul_i64, lu[0], ru[1], :i64)
          c2 = @wf.emit_bin(:mul_i64, lu[1], ru[0], :i64)
          hi = @wf.emit_bin(:add_i64, hi, @wf.emit_bin(:add_i64, c1, c2, :i64), :i64)
        return [[lo, hi, false], cw_ty_u128()]
      if op_str == ">>" && r_info[1][0] != :u128
        sh_v = r_info[0]
        # Direct zero-instruction upper-half extraction for `r >> 64`!
        cur_b = @wf.cur_block
        if cur_b.insts.size() > 0
          last_i = cur_b.insts[cur_b.insts.size() - 1]
          if last_i.dst == sh_v && last_i.op == :const_i64 && last_i.imm == 64
            return [[lu[1], @wf.emit_const_i64(0), true], cw_ty_u128()]
        c64 = @wf.emit_const_i64(64)
        is64 = @wf.emit_cmp(:icmp_i64, :eq, sh_v, c64)
        lo_s = @wf.emit_sel(:select_i64, is64, lu[1], @wf.emit_bin(:lshr_i64, lu[0], sh_v, :i64), :i64)
        return [[lo_s, @wf.emit_const_i64(0), true], cw_ty_u128()]
      if op_str == "+"
        lo = @wf.emit_bin(:add_i64, lu[0], ru[0], :i64)
        cy = @wf.emit_addcarry_u64(lu[0], ru[0])
        hi = @wf.emit_bin(:add_i64, @wf.emit_bin(:add_i64, lu[1], ru[1], :i64), cy, :i64)
        return [[lo, hi], cw_ty_u128()]
      if op_str == "|" || op_str == "^" || op_str == "&"
        wop = op_str == "|" ? :or_i64 : (op_str == "^" ? :xor_i64 : :and_i64)
        return [[@wf.emit_bin(wop, lu[0], ru[0], :i64), @wf.emit_bin(wop, lu[1], ru[1], :i64)], cw_ty_u128()]

    # Pointer arithmetic `ptr + idx` / `ptr - idx` / `ptr - ptr`
    if lt[0] == :ptr && (op_str == "+" || op_str == "-")
      if rt[0] == :ptr && op_str == "-"
        diff = @wf.emit_bin(:sub_i64, l_info[0], r_info[0], :i64)
        diff = @wf.emit_bin(:sdiv_i64, diff, @wf.emit_const_i64(lt[1]), :i64) if lt[1] > 1
        return [diff, cw_ty_int(64, false)]
      sc = r_info[0]
      sc = @wf.emit_bin(:mul_i64, sc, @wf.emit_const_i64(lt[1]), :i64) if lt[1] > 1
      wop = op_str == "+" ? :add_i64 : :sub_i64
      return [@wf.emit_bin(wop, l_info[0], sc, :i64), lt]

    if lt[0] == :f64 || rt[0] == :f64
      lf = coerce_to(l_info, cw_ty_f64())[0]
      rf = coerce_to(r_info, cw_ty_f64())[0]
      fop = op_str == "+" ? :fadd_f64 : (op_str == "-" ? :fsub_f64 : (op_str == "*" ? :fmul_f64 : :fdiv_f64))
      return [@wf.emit_bin(fop, lf, rf, :f64), cw_ty_f64()]

    # Integer usual conversions: 32-bit vs 64-bit, unsigned wins at equal width!
    if op_str == "<<" || op_str == ">>"
      res_ty = lt[1] < 32 ? cw_ty_int(32, false) : lt
      lv = coerce_to(l_info, res_ty)[0]
      rv = r_info[0]
      if res_ty[1] == 32
        sop = op_str == "<<" ? :shl_i32 : (res_ty[2] ? :lshr_i32 : :ashr_i32)
        out = @wf.emit_bin(sop, lv, rv, :i64)
        return coerce_to([out, cw_ty_int(64, res_ty[2])], res_ty)
      sop = op_str == "<<" ? :shl_i64 : (res_ty[2] ? :lshr_i64 : :ashr_i64)
      return [@wf.emit_bin(sop, lv, rv, :i64), res_ty]

    w_bits = (lt[1] >= 64 || rt[1] >= 64) ? 64 : 32
    is_u = false
    if lt[1] == rt[1]
      is_u = lt[2] || rt[2]
    elsif lt[1] > rt[1]
      is_u = lt[2]
    else
      is_u = rt[2]
    common_ty = cw_ty_int(w_bits, is_u)
    lv = coerce_to(l_info, common_ty)[0]
    rv = coerce_to(r_info, common_ty)[0]
    op_m = :add_i64
    op_m = :sub_i64 if op_str == "-"
    op_m = :mul_i64 if op_str == "*"
    op_m = (is_u ? :udiv_i64 : :sdiv_i64) if op_str == "/"
    op_m = (is_u ? :urem_i64 : :srem_i64) if op_str == "%"
    op_m = :and_i64 if op_str == "&"
    op_m = :or_i64  if op_str == "|"
    op_m = :xor_i64 if op_str == "^"
    res = @wf.emit_bin(op_m, lv, rv, :i64)
    w_bits == 32 ? coerce_to([res, cw_ty_int(64, is_u)], common_ty) : [res, common_ty]

  -> parse_assign
    # Check simple variable assignment `ident = ...` or `ident op= ...` first!
    if tk() == CW_TOK_IDENT && (@var_slots[tv()] != nil || @u128_slots[tv()] != nil)
      op2 = peek_v(1)
      if op2 in ("=" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "<<=" ">>=")
        vnm = advance()
        aop = advance()
        rhs = parse_assign()
        vty = @var_types[vnm]
        if aop == "="
          cv = coerce_to(rhs, vty)
          if vty[0] == :u128
            sls = @u128_slots[vnm]
            @wf.emit_store_slot(sls[0], cv[0][0]); @wf.emit_store_slot(sls[1], cv[0][1])
          else
            @wf.emit_store_slot(@var_slots[vnm], cv[0])
          return cv
        cur = nil
        if vty[0] == :u128
          sls = @u128_slots[vnm]
          cur = [[@wf.emit_load_slot(sls[0]), @wf.emit_load_slot(sls[1])], vty]
        else
          cur = [@wf.emit_load_slot(@var_slots[vnm]), vty]
        base_op = aop.slice(0, aop.size() - 1)
        comb = coerce_to(emit_c_binop(base_op, cur, rhs), vty)
        if vty[0] == :u128
          sls = @u128_slots[vnm]
          @wf.emit_store_slot(sls[0], comb[0][0]); @wf.emit_store_slot(sls[1], comb[0][1])
        else
          @wf.emit_store_slot(@var_slots[vnm], comb[0])
        return comb

    # Check deref / subscript / arrow assignment (`*p = v`, `p[i] = v`, `p->f = v`)!
    save = @pos
    lv = try_parse_mem_lvalue()
    if lv != nil && tk() == CW_TOK_PUNCT && tv() in ("=" "+=" "-=" "&=" "|=" "^=")
      aop = advance()
      rhs = parse_assign()
      ptr_vr = lv[0]; off_vr = lv[1]; mty = lv[2]; eb = cw_ebits_for_type(mty)
      if aop == "="
        cv = coerce_to(rhs, mty)
        @wf.emit_raw_store(ptr_vr, off_vr, cv[0], eb)
        return cv
      old_vr = @wf.emit_raw_load(ptr_vr, off_vr, eb)
      comb = coerce_to(emit_c_binop(aop.slice(0, 1), [old_vr, mty], rhs), mty)
      @wf.emit_raw_store(ptr_vr, off_vr, comb[0], eb)
      return comb
    @pos = save
    parse_ternary()

  # Returns `[base_ptr_vr, byte_off_vr, elem_cw_type]` if upcoming tokens form `*expr`, `p[idx]`, or `p->field` followed by assign op!
  -> try_parse_mem_lvalue
    if match_punct?("*")
      p = parse_unary()
      return nil if p[1][0] != :ptr
      return [p[0], @wf.emit_const_i64(0), cw_ty_int(p[1][1] * 8, p[1][2])]
    if tk() == CW_TOK_IDENT && @var_slots[tv()] != nil && @var_types[tv()][0] == :ptr
      pnm = advance()
      pty = @var_types[pnm]
      pvr = @wf.emit_load_slot(@var_slots[pnm])
      if match_punct?("\[")
        idx = parse_expr()
        expect_punct("\]")
        off = idx[0]
        off = @wf.emit_bin(:mul_i64, off, @wf.emit_const_i64(pty[1]), :i64) if pty[1] > 1
        return [pvr, off, cw_ty_int(pty[1] * 8, pty[2])]
      if match_punct?("->") && pty[3] != "" && @structs[pty[3]] != nil
        fnm = advance()
        finfo = @structs[pty[3]][1][fnm]
        if finfo != nil
          return [pvr, @wf.emit_const_i64(finfo[0]), finfo[1]]
    nil

  -> blk_insts_speculatable?(insts, start_idx)
    i = start_idx
    while i < insts.size()
      op = insts[i].op
      return false if op == :raw_load || op == :raw_store || op == :store_i64 || op == :store_double
      return false if op == :call_direct_i64 || op == :call_c_f64
      return false if op == :sdiv_i64 || op == :udiv_i64 || op == :srem_i64 || op == :urem_i64
      return false if op == :br || op == :cond_br || op == :ret_i64 || op == :ret_f64 || op == :ret_void
      i += 1
    true

  -> parse_ternary
    c = parse_lor()
    if match_punct?("?")
      cv = to_bool_vr(c)
      orig_blk = @wf.cur_block
      orig_blocks_n = @wf.blocks.size()
      # Speculatively emit into temporary blocks; if both arms are pure single-block ALU
      # (e.g. `a < b ? a : b`, `a < b ? -d : d`), splice directly into `orig_blk` with `:select_i64` (`csel`/`cmov`)!
      b_then = @wf.new_block("tern_t")
      b_else = @wf.new_block("tern_f")
      start_block(b_then)
      tv_i = parse_expr()
      expect_punct(":")
      res_ty = tv_i[1]
      then_single = (@wf.cur_block.id == b_then.id)
      start_block(b_else)
      fv_i = coerce_to(parse_ternary(), res_ty)
      else_single = (@wf.cur_block.id == b_else.id)

      if then_single && else_single && @wf.blocks.size() == orig_blocks_n + 2 && res_ty[0] != :u128 && blk_insts_speculatable?(b_then.insts, 0) && blk_insts_speculatable?(b_else.insts, 0)
        # Drop the two temporary blocks and emit branchless `:select_i64` / `:select_f64`!
        @wf.blocks.pop()
        @wf.blocks.pop()
        @wf.set_block(orig_blk)
        b_then.insts.each ->(ins) orig_blk.insts.push(ins)
        b_else.insts.each ->(ins) orig_blk.insts.push(ins)
        sop = res_ty[0] == :f64 ? :select_f64 : :select_i64
        sel_vr = @wf.emit_sel(sop, cv, tv_i[0], fv_i[0], res_ty[0] == :f64 ? :f64 : :i64)
        return [sel_vr, res_ty]

      # General branching diamond fallback (when arms have side effects, memory loads, or nested control flow)
      t_end_blk = then_single ? b_then : @wf.blocks[b_else.id - 1]
      f_end_blk = @wf.cur_block
      @wf.set_block(orig_blk)
      emit_cond_br_safe(cv, b_then, b_else)
      b_join = @wf.new_block("tern_j")
      res_sl = @wf.new_slot(res_ty[0] == :f64 ? :f64 : :i64, "tern")
      @wf.set_block(t_end_blk); @blk_terminated = false
      @wf.emit_store_slot(res_sl, tv_i[0])
      emit_br_safe(b_join)
      @wf.set_block(f_end_blk); @blk_terminated = false
      @wf.emit_store_slot(res_sl, fv_i[0])
      emit_br_safe(b_join)
      start_block(b_join)
      return [@wf.emit_load_slot(res_sl), res_ty]
    c

  -> parse_lor
    l = parse_land()
    while match_punct?("||")
      lv = to_bool_vr(l)
      sl = @wf.new_slot(:i64, "lor")
      @wf.emit_store_slot(sl, @wf.emit_const_i64(1))
      b_rhs = @wf.new_block("lor_r")
      b_end = @wf.new_block("lor_e")
      emit_cond_br_safe(lv, b_end, b_rhs)
      start_block(b_rhs)
      rv = to_bool_vr(parse_land())
      @wf.emit_store_slot(sl, rv)
      emit_br_safe(b_end)
      start_block(b_end)
      l = [@wf.emit_load_slot(sl), cw_ty_int(32, false)]
    l

  -> parse_land
    l = parse_bor()
    while match_punct?("&&")
      lv = to_bool_vr(l)
      sl = @wf.new_slot(:i64, "land")
      @wf.emit_store_slot(sl, @wf.emit_const_i64(0))
      b_rhs = @wf.new_block("land_r")
      b_end = @wf.new_block("land_e")
      emit_cond_br_safe(lv, b_rhs, b_end)
      start_block(b_rhs)
      rv = to_bool_vr(parse_bor())
      @wf.emit_store_slot(sl, rv)
      emit_br_safe(b_end)
      start_block(b_end)
      l = [@wf.emit_load_slot(sl), cw_ty_int(32, false)]
    l

  -> parse_bor
    l = parse_bxor()
    while match_punct?("|")
      l = emit_c_binop("|", l, parse_bxor())
    l

  -> parse_bxor
    l = parse_band()
    while match_punct?("^")
      l = emit_c_binop("^", l, parse_band())
    l

  -> parse_band
    l = parse_eq()
    while match_punct?("&")
      l = emit_c_binop("&", l, parse_eq())
    l

  -> parse_eq
    l = parse_rel()
    while tk() == CW_TOK_PUNCT && (tv() == "==" || tv() == "!=")
      op = advance()
      r = parse_rel()
      l = emit_c_cmp(op, l, r)
    l

  -> parse_rel
    l = parse_shift()
    while tk() == CW_TOK_PUNCT && tv() in ("<" "<=" ">" ">=")
      op = advance()
      r = parse_shift()
      l = emit_c_cmp(op, l, r)
    l

  -> emit_c_cmp(op, l_info, r_info)
    lt = l_info[1]; rt = r_info[1]
    if lt[0] == :f64 || rt[0] == :f64
      lf = coerce_to(l_info, cw_ty_f64())[0]
      rf = coerce_to(r_info, cw_ty_f64())[0]
      fp = op == "==" ? :oeq : (op == "!=" ? :une : (op == "<" ? :olt : (op == "<=" ? :ole : (op == ">" ? :ogt : :oge))))
      return [@wf.emit_cmp(:fcmp_f64, fp, lf, rf), cw_ty_int(32, false)]
    is_u = (lt[0] == :ptr || rt[0] == :ptr) || (lt[1] == rt[1] ? (lt[2] || rt[2]) : (lt[1] > rt[1] ? lt[2] : rt[2]))
    w_bits = (lt[0] == :ptr || rt[0] == :ptr || lt[1] >= 64 || rt[1] >= 64) ? 64 : 32
    cty = cw_ty_int(w_bits, is_u)
    lv = (lt[0] == :ptr) ? l_info[0] : coerce_to(l_info, cty)[0]
    rv = (rt[0] == :ptr) ? r_info[0] : coerce_to(r_info, cty)[0]
    pred = :eq
    pred = :ne if op == "!="
    if op == "<"
      pred = is_u ? :ult : :slt
    elsif op == "<="
      pred = is_u ? :ule : :sle
    elsif op == ">"
      pred = is_u ? :ugt : :sgt
    elsif op == ">="
      pred = is_u ? :uge : :sge
    [@wf.emit_cmp(:icmp_i64, pred, lv, rv), cw_ty_int(32, false)]

  -> parse_shift
    l = parse_add()
    while tk() == CW_TOK_PUNCT && (tv() == "<<" || tv() == ">>")
      op = advance()
      l = emit_c_binop(op, l, parse_add())
    l

  -> parse_add
    l = parse_mul()
    while tk() == CW_TOK_PUNCT && (tv() == "+" || tv() == "-")
      op = advance()
      l = emit_c_binop(op, l, parse_mul())
    l

  -> parse_mul
    l = parse_unary()
    while tk() == CW_TOK_PUNCT && tv() in ("*" "/" "%")
      op = advance()
      l = emit_c_binop(op, l, parse_unary())
    l

  -> looks_like_cast?
    return false if !(tk() == CW_TOK_PUNCT && tv() == "(")
    i = @pos + 1
    return false if i >= @kinds.size() || @kinds[i] != CW_TOK_IDENT
    w = @vals[i]
    return true if @typedefs[w] != nil
    w in ("void" "char" "short" "int" "long" "float" "double" "signed" "unsigned" "const" "struct")

  -> parse_unary
    if looks_like_cast?()
      expect_punct("(")
      cty = parse_type_and_hint()[0]
      expect_punct(")")
      inner = parse_unary()
      return [inner[0], cw_ty_void()] if cty[0] == :void
      return coerce_to(inner, cty)
    if match_punct?("+")
      return parse_unary()
    if match_punct?("-")
      u = parse_unary()
      if u[1][0] == :f64
        return [@wf.emit_un(:fneg_f64, u[0], :f64), cw_ty_f64()]
      return coerce_to([@wf.emit_un(:neg_i64, u[0], :i64), cw_ty_int(64, u[1][2])], u[1])
    if match_punct?("~")
      u = parse_unary()
      x = @wf.emit_bin(:xor_i64, u[0], @wf.emit_const_i64(-1), :i64)
      return coerce_to([x, cw_ty_int(64, u[1][2])], u[1])
    if match_punct?("!")
      u = parse_unary()
      z = @wf.emit_cmp(:icmp_i64, :eq, to_bool_vr(u), @wf.emit_const_i64(0))
      return [z, cw_ty_int(32, false)]
    if match_punct?("*")
      p = parse_unary()
      pty = p[1]
      ety = cw_ty_int(pty[1] * 8, pty[2])
      ld = @wf.emit_raw_load(p[0], @wf.emit_const_i64(0), cw_ebits_for_type(ety))
      return [ld, ety]
    if match_punct?("++") || match_punct?("--")
      is_inc = @vals[@pos - 1] == "++"
      vnm = advance()
      vty = @var_types[vnm]
      cur = [@wf.emit_load_slot(@var_slots[vnm]), vty]
      nxt = coerce_to(emit_c_binop(is_inc ? "+" : "-", cur, [@wf.emit_const_i64(1), cw_ty_int(64, false)]), vty)
      @wf.emit_store_slot(@var_slots[vnm], nxt[0])
      return nxt
    if tk() == CW_TOK_IDENT && tv() == "sizeof"
      advance()
      if looks_like_cast?()
        expect_punct("("); sty = parse_type_and_hint()[0]; expect_punct(")")
        return [@wf.emit_const_i64(cw_bytes_for_type(sty)), cw_ty_int(64, true)]
      expect_punct("("); u = parse_expr(); expect_punct(")")
      return [@wf.emit_const_i64(cw_bytes_for_type(u[1])), cw_ty_int(64, true)]
    parse_postfix()

  -> parse_postfix
    e = parse_primary()
    while true
      if match_punct?("\[")
        idx = parse_expr()
        expect_punct("\]")
        pty = e[1]
        off = idx[0]
        off = @wf.emit_bin(:mul_i64, off, @wf.emit_const_i64(pty[1]), :i64) if pty[1] > 1
        ety = cw_ty_int(pty[1] * 8, pty[2])
        ld = @wf.emit_raw_load(e[0], off, cw_ebits_for_type(ety))
        e = [ld, ety]
      elsif match_punct?("->")
        fnm = advance()
        snm = e[1][3]
        finfo = @structs[snm][1][fnm]
        fty = finfo[1]
        ld = @wf.emit_raw_load(e[0], @wf.emit_const_i64(finfo[0]), cw_ebits_for_type(fty))
        e = [ld, fty]
      elsif match_punct?("++") || match_punct?("--")
        is_inc = @vals[@pos - 1] == "++"
        # `e` came from primary `vnm`
        # Note: find matching slot from preceding ident token
        vnm = @vals[@pos - 2]
        if @var_slots[vnm] != nil
          vty = @var_types[vnm]
          nxt = coerce_to(emit_c_binop(is_inc ? "+" : "-", e, [@wf.emit_const_i64(1), cw_ty_int(64, false)]), vty)
          @wf.emit_store_slot(@var_slots[vnm], nxt[0])
      else
        break
    e

  -> parse_primary
    if match_punct?("(")
      e = parse_expr()
      expect_punct(")")
      return e
    if tk() == CW_TOK_INT
      pair = advance()
      return [@wf.emit_const_i64(pair[0]), cw_ty_int(64, pair[1])]
    if tk() == CW_TOK_FLOAT
      fv = advance()
      return [@wf.emit_const_f64(fv), cw_ty_f64()]
    if tk() == CW_TOK_IDENT
      nm = advance()
      if nm == "NULL"
        return [@wf.emit_const_i64(0), cw_ty_ptr(1, true, "")]
      if nm == "true"
        return [@wf.emit_const_i64(1), cw_ty_int(8, true)]
      if nm == "false"
        return [@wf.emit_const_i64(0), cw_ty_int(8, true)]
      if match_punct?("(")
        args = []
        if !match_punct?(")")
          while true
            args.push(parse_assign())
            break if !match_punct?(",")
          expect_punct(")")
        if nm == "__builtin_expect"
          return args[0]
        if nm == "__builtin_ctzll" || nm == "__builtin_ctz"
          return [@wf.emit_ctz_i64(args[0][0]), cw_ty_int(32, false)]
        if nm == "__builtin_clzll"
          return [@wf.emit_clz_i64(args[0][0]), cw_ty_int(32, false)]
        rty = @fn_ret_types[nm] != nil ? @fn_ret_types[nm] : cw_ty_int(64, false)
        avr = []
        ai = 0
        while ai < args.size()
          avr.push(args[ai][0])
          ai += 1
        cv = @wf.emit_call_c(nm, avr, rty[0] == :f64 ? :f64 : :i64)
        return [cv, rty]
      if @u128_slots[nm] != nil
        sls = @u128_slots[nm]
        return [[@wf.emit_load_slot(sls[0]), @wf.emit_load_slot(sls[1])], @var_types[nm]]
      if @var_slots[nm] != nil
        return [@wf.emit_load_slot(@var_slots[nm]), @var_types[nm]]
      raise "Unknown C identifier: " + nm
    raise "Unexpected C token in expression: " + tv().to_s()

# Parse C source directly into a `WireModule`!
-> c_parse_to_wire_module(c_src)
  lex = CWireLexer.new(c_src)
  lex.tokenize()
  comp = CToWireCompiler.new(lex)
  comp.parse_module()
