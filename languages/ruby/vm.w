# tungsten/languages/ruby/vm.w — Fast Flat-Register Bytecode Compiler & VM for Ruby 4.0.
#
# Compiles hot Ruby methods (and pure loop bodies) into flat 4-array `i64[]` register
# bytecode (`op`, `a`, `b`, `c`) executed over a single pre-allocated register stack
# (`@reg_stack`) with inline-cached direct calls (`OP_CALL_SELF_1` / `OP_CALL_SELF_2`):
#   - ZERO Hash lookups for local variables (O(1) register slot `stack[fp + r]`)
#   - ZERO RbEnv / Array / Hash heap allocations per recursive call (`fib(30)` = 0 allocs!)
#   - Fused compare-and-branch (`OP_JGE`, `OP_JGE_IMM`, `OP_JGT_IMM`) and immediate ops
#     (`OP_ADD_IMM`, `OP_SUB_IMM`, `OP_INC_LOCAL`)
#   - Epoch-guarded inline caches automatically invalidated on any method definition/alias/undef
#   - Seamless automatic fallback to the full AST evaluator (`eval_stmts`) for methods using
#     closures, blocks, `begin/rescue`, `super`, `eval`, or keyword/splat parameters.

RB_OP_RET          = 1   # return reg[a]
RB_OP_MOV          = 2   # reg[a] = reg[b]
RB_OP_INT          = 3   # reg[a] = b (inline i64 immediate)
RB_OP_CONST        = 4   # reg[a] = consts[b]
RB_OP_NIL          = 5   # reg[a] = nil
RB_OP_BOOL         = 6   # reg[a] = (b != 0)
RB_OP_SELF         = 7   # reg[a] = self_obj
RB_OP_ADD          = 8   # reg[a] = reg[b] + reg[c]
RB_OP_SUB          = 9   # reg[a] = reg[b] - reg[c]
RB_OP_MUL          = 10  # reg[a] = reg[b] * reg[c]
RB_OP_DIV          = 11  # reg[a] = reg[b] / reg[c] (Ruby floor div)
RB_OP_MOD          = 12  # reg[a] = reg[b] % reg[c] (Ruby floor mod)
RB_OP_ADD_IMM      = 13  # reg[a] = reg[b] + c
RB_OP_SUB_IMM      = 14  # reg[a] = reg[b] - c
RB_OP_LT           = 15  # reg[a] = reg[b] < reg[c]
RB_OP_LE           = 16  # reg[a] = reg[b] <= reg[c]
RB_OP_GT           = 17  # reg[a] = reg[b] > reg[c]
RB_OP_GE           = 18  # reg[a] = reg[b] >= reg[c]
RB_OP_EQ           = 19  # reg[a] = reg[b] == reg[c]
RB_OP_NEQ          = 20  # reg[a] = reg[b] != reg[c]
RB_OP_LT_IMM       = 21  # reg[a] = reg[b] < c
RB_OP_LE_IMM       = 22  # reg[a] = reg[b] <= c
RB_OP_EQ_IMM       = 23  # reg[a] = reg[b] == c
RB_OP_NOT          = 24  # reg[a] = !truthy(reg[b])
RB_OP_NEG          = 25  # reg[a] = -reg[b]
RB_OP_BIT_AND      = 26  # reg[a] = reg[b] & reg[c]
RB_OP_BIT_OR       = 27  # reg[a] = reg[b] | reg[c]
RB_OP_BIT_XOR      = 28  # reg[a] = reg[b] ^ reg[c]
RB_OP_SHL          = 29  # reg[a] = reg[b] << reg[c]
RB_OP_SHR          = 30  # reg[a] = reg[b] >> reg[c]
RB_OP_JMP          = 31  # pc = a
RB_OP_JMP_FALSE    = 32  # if !truthy(reg[a]) then pc = b
RB_OP_JMP_TRUE     = 33  # if truthy(reg[a]) then pc = b
RB_OP_JGE          = 34  # if reg[a] >= reg[b] then pc = c (for `while a < b`)
RB_OP_JGT          = 35  # if reg[a] > reg[b] then pc = c (for `while a <= b`)
RB_OP_JGE_IMM      = 36  # if reg[a] >= b then pc = c (for `if n < 2`)
RB_OP_JGT_IMM      = 37  # if reg[a] > b then pc = c (for `if n <= 1`)
RB_OP_CALL_SELF_0  = 38  # reg[a] = self.<names[b]>()
RB_OP_CALL_SELF_1  = 39  # reg[a] = self.<names[b]>(reg[c])
RB_OP_CALL_SELF_2  = 40  # reg[a] = self.<names[b]>(reg[c], reg[c+1])
RB_OP_CALL_SELF_N  = 41  # reg[a] = self.<names[b]>(reg[c..c+k-1]) (aux = k)
RB_OP_SEND         = 42  # reg[a] = reg[b].<names[c]>(...) (aux = [arg_base, argc])
RB_OP_ARRAY_NEW    = 43  # reg[a] = [reg[b]..reg[b+c-1]]
RB_OP_IDX_GET      = 44  # reg[a] = reg[b][reg[c]]
RB_OP_IDX_SET      = 45  # reg[a][reg[b]] = reg[c]
RB_OP_IVAR_GET     = 46  # reg[a] = self.@<names[b]>
RB_OP_IVAR_SET     = 47  # self.@<names[a]> = reg[b]
RB_OP_STR_LIT      = 48  # reg[a] = RbString.new(consts[b], UTF8, c != 0)
RB_OP_STR_PUSH     = 49  # reg[a] << reg[b] (String or Array fast push)
RB_OP_CONST_GET    = 50  # reg[a] = resolve_const(names[b])
RB_OP_MATCH        = 51  # reg[a] = reg[b].match(reg[c]) (fast RbRegexp#match)
RB_OP_TO_I         = 52  # reg[a] = reg[b].to_i (fast RbString#to_i / Integer)
RB_OP_SIZE         = 53  # reg[a] = reg[b].size (fast Array/RbString/RbHash)
RB_OP_MUL_IMM      = 54  # reg[a] = reg[b] * c (inline i64 immediate)
RB_OP_MOD_IMM      = 55  # reg[a] = reg[b] % c (inline positive i64 floor mod)

+ RbBytecode
  rw :name, :arity, :frame_size, :ops, :a, :b, :c, :nops
  rw :consts, :names, :aux, :local_names
  rw :ic_epoch, :ic_cls, :ic_code

  -> new(@name, @arity, @frame_size, @ops, @a, @b, @c, @nops, @consts, @names, @aux, @local_names = nil)
    @ic_epoch = i64[@nops]
    @ic_cls = []
    @ic_code = []
    i = 0
    while i < @nops
      @ic_epoch[i] = -1
      @ic_cls.push(nil)
      @ic_code.push(nil)
      i += 1

+ RbCompiler
  rw :failed, :locals, :local_list, :next_reg, :max_reg, :ops, :a, :b, :c, :consts, :names, :aux
  rw :loop_breaks, :loop_nexts, :loop_redos, :outer_env, :is_block

  -> new(name, params, @outer_env = nil, @is_block = false)
    @name = name
    @failed = false
    @locals = {}
    @local_list = []
    @next_reg = 0
    @max_reg = 0
    @ops = []
    @a = []
    @b = []
    @c = []
    @consts = []
    @names = []
    @aux = []
    @loop_breaks = []
    @loop_nexts = []
    @loop_redos = []
    i = 0
    while i < params.size
      p = params[i]
      if p[0] != :req
        @failed = true
        break
      @locals[p[1]] = @next_reg
      @local_list.push(p[1])
      @next_reg += 1
      i += 1
    @max_reg = @next_reg

  -> seed_locals(names)
    return nil if names == nil
    names.each ->(nm) local_slot(nm)
    nil

  -> alloc_reg
    r = @next_reg
    @next_reg += 1
    @max_reg = @next_reg if @next_reg > @max_reg
    r

  -> local_slot(nm)
    return @locals[nm] if @locals.has_key?(nm)
    if @is_block && @outer_env != nil && @outer_env.has?(nm)
      @failed = true
      return 0
    r = alloc_reg()
    @locals[nm] = r
    @local_list.push(nm)
    r

  -> add_const(v)
    idx = @consts.size
    @consts.push(v)
    idx

  -> add_name(nm)
    i = 0
    while i < @names.size
      return i if @names[i] == nm
      i += 1
    idx = @names.size
    @names.push(nm)
    idx

  -> emit(op, av = 0, bv = 0, cv = 0, auxv = nil)
    pc = @ops.size
    @ops.push(op)
    @a.push(av)
    @b.push(bv)
    @c.push(cv)
    @aux.push(auxv)
    pc

  -> patch_a(pc, v)
    @a[pc] = v

  -> patch_b(pc, v)
    @b[pc] = v

  -> patch_c(pc, v)
    @c[pc] = v

  # Pre-scan all assigned local variable names in the body so Ruby lexical scoping is exact.
  -> prescan_locals(node)
    return nil if node == nil || @failed
    if node.is_a?(Array)
      node.each ->(x) prescan_locals(x)
      return nil
    return nil if !node.is_a?(RbNode)
    k = node.kind
    if k == :assign && node.a.kind == :var
      local_slot(node.a.a)
    elsif k == :compound_assign && node.b.kind == :var
      local_slot(node.b.a)
    elsif k == :block || k == :lambda || k == :class_def || k == :module_def || k == :method_def ||
          k == :singleton_class || k == :begin || k == :case_in || k == :pat_test || k == :super ||
          k == :yield || k == :defined || k == :alias || k == :undef || k == :multi_assign || k == :for ||
          (@is_block && (k == :return || k == :break || k == :next || k == :redo || k == :retry))
      @failed = true
      return nil
    prescan_locals(node.a)
    prescan_locals(node.b)
    prescan_locals(node.c)
    prescan_locals(node.d)
    nil

  -> compile_stmts(stmts, dst)
    if stmts == nil || stmts.size == 0
      emit(RB_OP_NIL, dst) if dst >= 0
      return nil
    last = stmts.size - 1
    i = 0
    while i < stmts.size && !@failed
      compile_expr(stmts[i], i == last ? dst : -1)
      i += 1
    nil

  -> compile_cond_jump_false(cond, target_placeholder)
    # Fused compare-and-branch superinstructions!
    if cond.kind == :binary_op
      op = cond.a
      if op == "<" && cond.c.kind == :int
        r1 = alloc_temp(cond.b)
        pc = emit(RB_OP_JGE_IMM, r1, cond.c.a, target_placeholder)
        return [pc, :c]
      if op == "<=" && cond.c.kind == :int
        r1 = alloc_temp(cond.b)
        pc = emit(RB_OP_JGT_IMM, r1, cond.c.a, target_placeholder)
        return [pc, :c]
      if op == "<"
        r1 = alloc_temp(cond.b)
        r2 = alloc_temp(cond.c)
        pc = emit(RB_OP_JGE, r1, r2, target_placeholder)
        return [pc, :c]
      if op == "<="
        r1 = alloc_temp(cond.b)
        r2 = alloc_temp(cond.c)
        pc = emit(RB_OP_JGT, r1, r2, target_placeholder)
        return [pc, :c]
    rc = alloc_reg()
    compile_expr(cond, rc)
    pc = emit(RB_OP_JMP_FALSE, rc, target_placeholder)
    [pc, :b]

  -> alloc_temp(node)
    if node.kind == :var && @locals.has_key?(node.a)
      return @locals[node.a]
    r = alloc_reg()
    compile_expr(node, r)
    r

  -> compile_expr(n, dst)
    return nil if @failed
    if n == nil
      emit(RB_OP_NIL, dst) if dst >= 0
      return nil
    save_reg = @next_reg
    discard = dst < 0
    case n.kind
    when :int
      if !discard
        v = n.a
        if v >= -1000000000 && v <= 1000000000
          emit(RB_OP_INT, dst, v)
        else
          emit(RB_OP_CONST, dst, add_const(v))
    when :float
      emit(RB_OP_CONST, dst, add_const(n.a)) if !discard
    when :bool
      emit(RB_OP_BOOL, dst, n.a ? 1 : 0) if !discard
    when :nil
      emit(RB_OP_NIL, dst) if !discard
    when :self
      emit(RB_OP_SELF, dst) if !discard
    when :symbol
      emit(RB_OP_CONST, dst, add_const(RbSym.new(n.a))) if !discard
    when :regex
      emit(RB_OP_CONST, dst, add_const(RbRegexp.new(n.a, n.b == nil ? "" : n.b))) if !discard
    when :string
      emit(RB_OP_STR_LIT, dst, add_const(n.a), n.b == true ? 1 : 0) if !discard
    when :var
      if @locals.has_key?(n.a)
        if !discard
          slot = @locals[n.a]
          emit(RB_OP_MOV, dst, slot) if dst != slot
      elsif @is_block && @outer_env != nil && @outer_env.has?(n.a)
        @failed = true
      else
        rd = discard ? alloc_reg() : dst
        emit(RB_OP_CALL_SELF_0, rd, add_name(n.a))
    when :ivar
      emit(RB_OP_IVAR_GET, dst, add_name(n.a)) if !discard
    when :const_ref
      emit(RB_OP_CONST_GET, dst, add_name(n.a)) if !discard
    when :assign
      t = n.a
      if t.kind == :var
        slot = local_slot(t.a)
        compile_expr(n.b, slot)
        emit(RB_OP_MOV, dst, slot) if !discard && dst != slot
      elsif t.kind == :ivar
        rv = discard ? alloc_reg() : dst
        compile_expr(n.b, rv)
        emit(RB_OP_IVAR_SET, add_name(t.a), rv)
      elsif t.kind == :index && t.b.size == 1
        r_arr = alloc_temp(t.a)
        r_idx = alloc_temp(t.b[0])
        rv = discard ? alloc_reg() : dst
        compile_expr(n.b, rv)
        emit(RB_OP_IDX_SET, r_arr, r_idx, rv)
      else
        @failed = true
    when :compound_assign
      op = n.a
      t = n.b
      if t.kind == :var && (op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%=")
        slot = local_slot(t.a)
        if op == "+=" && n.c.kind == :int
          emit(RB_OP_ADD_IMM, slot, slot, n.c.a)
        elsif op == "-=" && n.c.kind == :int
          emit(RB_OP_SUB_IMM, slot, slot, n.c.a)
        else
          r2 = alloc_temp(n.c)
          bop = op == "+=" ? RB_OP_ADD : (op == "-=" ? RB_OP_SUB : (op == "*=" ? RB_OP_MUL : (op == "/=" ? RB_OP_DIV : RB_OP_MOD)))
          emit(bop, slot, slot, r2)
        emit(RB_OP_MOV, dst, slot) if !discard && dst != slot
      else
        @failed = true
    when :unary_op
      r1 = alloc_temp(n.b)
      if n.a == "!"
        emit(RB_OP_NOT, dst, r1)
      elsif n.a == "-@"
        emit(RB_OP_NEG, dst, r1)
      elsif n.a == "+@"
        emit(RB_OP_MOV, dst, r1) if dst != r1
      else
        @failed = true
    when :not
      r1 = alloc_temp(n.a)
      emit(RB_OP_NOT, dst, r1)
    when :and
      compile_expr(n.a, dst)
      jf = emit(RB_OP_JMP_FALSE, dst, 0)
      compile_expr(n.b, dst)
      patch_b(jf, @ops.size)
    when :or
      compile_expr(n.a, dst)
      jt = emit(RB_OP_JMP_TRUE, dst, 0)
      compile_expr(n.b, dst)
      patch_b(jt, @ops.size)
    when :binary_op
      op = n.a
      rd = discard ? alloc_reg() : dst
      if (op == "+" || op == "-") && n.c.kind == :int && n.c.a >= -1000000000 && n.c.a <= 1000000000
        r1 = alloc_temp(n.b)
        emit(op == "+" ? RB_OP_ADD_IMM : RB_OP_SUB_IMM, rd, r1, n.c.a)
      elsif op == "*" && n.c.kind == :int && n.c.a >= -1000000000 && n.c.a <= 1000000000
        r1 = alloc_temp(n.b)
        emit(RB_OP_MUL_IMM, rd, r1, n.c.a)
      elsif op == "%" && n.c.kind == :int && n.c.a > 0 && n.c.a <= 1000000000
        r1 = alloc_temp(n.b)
        emit(RB_OP_MOD_IMM, rd, r1, n.c.a)
      elsif (op == "<" || op == "<=" || op == "==") && n.c.kind == :int && n.c.a >= -1000000000 && n.c.a <= 1000000000
        r1 = alloc_temp(n.b)
        bop = op == "<" ? RB_OP_LT_IMM : (op == "<=" ? RB_OP_LE_IMM : RB_OP_EQ_IMM)
        emit(bop, rd, r1, n.c.a)
      elsif op == "<<"
        r1 = alloc_temp(n.b)
        r2 = alloc_temp(n.c)
        emit(RB_OP_STR_PUSH, r1, r2)
        emit(RB_OP_MOV, dst, r1) if !discard && dst != r1
      else
        r1 = alloc_temp(n.b)
        r2 = alloc_temp(n.c)
        case op
        when "+" then emit(RB_OP_ADD, rd, r1, r2)
        when "-" then emit(RB_OP_SUB, rd, r1, r2)
        when "*" then emit(RB_OP_MUL, rd, r1, r2)
        when "/" then emit(RB_OP_DIV, rd, r1, r2)
        when "%" then emit(RB_OP_MOD, rd, r1, r2)
        when "<" then emit(RB_OP_LT, rd, r1, r2)
        when "<=" then emit(RB_OP_LE, rd, r1, r2)
        when ">" then emit(RB_OP_GT, rd, r1, r2)
        when ">=" then emit(RB_OP_GE, rd, r1, r2)
        when "==" then emit(RB_OP_EQ, rd, r1, r2)
        when "!=" then emit(RB_OP_NEQ, rd, r1, r2)
        when "&" then emit(RB_OP_BIT_AND, rd, r1, r2)
        when "|" then emit(RB_OP_BIT_OR, rd, r1, r2)
        when "^" then emit(RB_OP_BIT_XOR, rd, r1, r2)
        when ">>" then emit(RB_OP_SHR, rd, r1, r2)
        else
          @failed = true
    when :if
      jp = compile_cond_jump_false(n.a, 0)
      compile_stmts(n.b, dst)
      if n.c != nil && n.c.size > 0
        jend = emit(RB_OP_JMP, 0)
        if jp[1] == :c
          patch_c(jp[0], @ops.size)
        else
          patch_b(jp[0], @ops.size)
        compile_stmts(n.c, dst)
        patch_a(jend, @ops.size)
      elsif discard
        if jp[1] == :c
          patch_c(jp[0], @ops.size)
        else
          patch_b(jp[0], @ops.size)
      else
        jend = emit(RB_OP_JMP, 0)
        if jp[1] == :c
          patch_c(jp[0], @ops.size)
        else
          patch_b(jp[0], @ops.size)
        emit(RB_OP_NIL, dst)
        patch_a(jend, @ops.size)
    when :while
      is_until = n.c == true
      loop_top = @ops.size
      breaks = []
      nexts = []
      @loop_breaks.push(breaks)
      @loop_nexts.push(nexts)
      jp = nil
      if is_until
        rc = alloc_reg()
        compile_expr(n.a, rc)
        jp = [emit(RB_OP_JMP_TRUE, rc, 0), :b]
      else
        jp = compile_cond_jump_false(n.a, 0)
      compile_stmts(n.b, -1)
      emit(RB_OP_JMP, loop_top)
      loop_end = @ops.size
      if jp[1] == :c
        patch_c(jp[0], loop_end)
      else
        patch_b(jp[0], loop_end)
      emit(RB_OP_NIL, dst) if !discard
      after_end = @ops.size
      @loop_breaks.pop
      @loop_nexts.pop
      breaks.each ->(bp)
        patch_a(bp[0], after_end)
      nexts.each ->(np) patch_a(np, loop_top)
    when :break
      if @loop_breaks.size == 0
        @failed = true
      else
        rd = discard ? alloc_reg() : dst
        compile_expr(n.a, rd) if n.a != nil
        emit(RB_OP_NIL, rd) if n.a == nil
        jp = emit(RB_OP_JMP, 0)
        @loop_breaks[@loop_breaks.size - 1].push([jp])
    when :next
      if @loop_nexts.size == 0
        @failed = true
      else
        jp = emit(RB_OP_JMP, 0)
        @loop_nexts[@loop_nexts.size - 1].push(jp)
    when :return
      rd = discard ? alloc_reg() : dst
      if n.a != nil
        compile_expr(n.a, rd)
      else
        emit(RB_OP_NIL, rd)
      emit(RB_OP_RET, rd)
    when :array
      n.a.each ->(el) @failed = true if el.is_a?(RbNode) && el.kind == :splat
      if !@failed
        base = @next_reg
        i = 0
        while i < n.a.size
          r = alloc_reg()
          compile_expr(n.a[i], r)
          i += 1
        emit(RB_OP_ARRAY_NEW, dst, base, n.a.size)
    when :index
      if n.b.size == 1
        r_arr = alloc_temp(n.a)
        r_idx = alloc_temp(n.b[0])
        emit(RB_OP_IDX_GET, dst, r_arr, r_idx)
      else
        @failed = true
    when :call
      spec = n.c
      if spec[1].size > 0 || spec[2] != nil || spec[3] != nil || n.b == "eval" || n.b == "binding" || n.b == "block_given?"
        @failed = true
      else
        pargs = spec[0]
        pargs.each ->(pa) @failed = true if pa.is_a?(RbNode) && pa.kind == :splat
        if !@failed
          nm_idx = add_name(n.b)
          rd = discard ? alloc_reg() : dst
          if n.a == nil
            argc = pargs.size
            if argc == 0
              emit(RB_OP_CALL_SELF_0, rd, nm_idx)
            elsif argc == 1
              r0 = alloc_temp(pargs[0])
              emit(RB_OP_CALL_SELF_1, rd, nm_idx, r0)
            elsif argc == 2
              base = @next_reg
              r0 = alloc_reg()
              r1 = alloc_reg()
              compile_expr(pargs[0], r0)
              compile_expr(pargs[1], r1)
              emit(RB_OP_CALL_SELF_2, rd, nm_idx, base)
            else
              base = @next_reg
              i = 0
              while i < argc
                r = alloc_reg()
                compile_expr(pargs[i], r)
                i += 1
              emit(RB_OP_CALL_SELF_N, rd, nm_idx, base, argc)
          else
            argc = pargs.size
            if n.b == "[]" && argc == 1
              r_recv = alloc_temp(n.a)
              r_idx = alloc_temp(pargs[0])
              emit(RB_OP_IDX_GET, rd, r_recv, r_idx)
            elsif n.b == "[]=" && argc == 2
              r_recv = alloc_temp(n.a)
              r_idx = alloc_temp(pargs[0])
              compile_expr(pargs[1], rd)
              emit(RB_OP_IDX_SET, r_recv, r_idx, rd)
            elsif n.b == "match" && argc == 1
              r_recv = alloc_temp(n.a)
              r_arg = alloc_temp(pargs[0])
              emit(RB_OP_MATCH, rd, r_recv, r_arg)
            elsif n.b == "to_i" && argc == 0
              r_recv = alloc_temp(n.a)
              emit(RB_OP_TO_I, rd, r_recv)
            elsif (n.b == "size" || n.b == "length") && argc == 0
              r_recv = alloc_temp(n.a)
              emit(RB_OP_SIZE, rd, r_recv)
            else
              r_recv = alloc_temp(n.a)
              base = @next_reg
              i = 0
              while i < argc
                r = alloc_reg()
                compile_expr(pargs[i], r)
                i += 1
              emit(RB_OP_SEND, rd, r_recv, nm_idx, [base, argc])
    else
      @failed = true
    @next_reg = save_reg if @next_reg > save_reg
    nil

  -> finish
    return nil if @failed
    n = @ops.size
    ops_i = i64[n]
    a_i = i64[n]
    b_i = i64[n]
    c_i = i64[n]
    i = 0
    while i < n
      ops_i[i] = @ops[i]
      a_i[i] = @a[i]
      b_i[i] = @b[i]
      c_i[i] = @c[i]
      i += 1
    RbBytecode.new(@name, @locals.size, @max_reg + 2, ops_i, a_i, b_i, c_i, n, @consts, @names, @aux, @local_list)

-> rb_compile_method_bytecode(m)
  return nil if m == nil || m.native_fn != nil || m.body == nil
  comp = RbCompiler.new(m.name, m.params)
  return nil if comp.failed
  comp.prescan_locals(m.body)
  return nil if comp.failed
  ret_reg = comp.alloc_reg()
  comp.compile_stmts(m.body, ret_reg)
  return nil if comp.failed
  comp.emit(RB_OP_RET, ret_reg)
  bc = comp.finish()
  return nil if bc == nil
  bc.arity = m.params.size
  bc

-> rb_compile_block_bytecode(pr)
  return nil if pr == nil || pr.native_fn != nil || pr.body == nil || pr.params.size == 0
  comp = RbCompiler.new("<block>", pr.params, pr.env, true)
  return nil if comp.failed
  comp.prescan_locals(pr.body)
  return nil if comp.failed
  ret_reg = comp.alloc_reg()
  comp.compile_stmts(pr.body, ret_reg)
  return nil if comp.failed
  comp.emit(RB_OP_RET, ret_reg)
  bc = comp.finish()
  return nil if bc == nil
  bc.arity = pr.params.size
  bc

-> rb_compile_stmts_bytecode(stmts, seed_names = nil)
  comp = RbCompiler.new("<main>", [])
  comp.seed_locals(seed_names)
  comp.prescan_locals(stmts)
  return nil if comp.failed
  ret_reg = comp.alloc_reg()
  comp.compile_stmts(stmts, ret_reg)
  return nil if comp.failed
  comp.emit(RB_OP_RET, ret_reg)
  bc = comp.finish()
  return nil if bc == nil
  bc.arity = 0
  bc
