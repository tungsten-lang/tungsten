# jsn/sm_coro — Stackless Resumable State-Machine Compiler & VM for async functions,
# generators (function*), and async generators (async function*).
#
# Zero goroutines, zero channels, zero live-generator limit!
# Any AST subtree without yield/await runs directly via wk_ex / wk_ev (full JIT OSR speed
# for inner sync loops!). Suspending control flow & expressions lower cleanly to flat
# bytecode with full try/catch/finally, labeled break/continue, yield*, for-in/for-of/for-await,
# and fast local bytecode ops for hot async/generator loops.

in JS

# ---- Pure LLVM fast numeric ops for stackless loop bytecode ----

# Returns biased-double WValue of ((a + b) | 0) if both a & b are finite numbers, else 6 (JSR_SLOW).
fn sm_add_i32_bits(ab, bb) (i64 i64) i64
  ll <<~IR
    %ax = sub i64 %ab, 281474976710656
    %an = icmp ult i64 %ax, u0xFFF0000000000001
    br i1 %an, label %chk_b, label %slow
  chk_b:
    %bx = sub i64 %bb, 281474976710656
    %bn = icmp ult i64 %bx, u0xFFF0000000000001
    br i1 %bn, label %do_add, label %slow
  do_add:
    %ad = bitcast i64 %ax to double
    %bd = bitcast i64 %bx to double
    %sd = fadd double %ad, %bd
    %sdb = bitcast double %sd to i64
    %sab = and i64 %sdb, 9223372036854775807
    %sa = bitcast i64 %sab to double
    %in_r = fcmp olt double %sa, 2147483648.0
    br i1 %in_r, label %fast_i, label %slow
  fast_i:
    %iw = fptosi double %sd to i32
    %id = sitofp i32 %iw to double
    %ib = bitcast double %id to i64
    %box = add i64 %ib, 281474976710656
    ret i64 %box
  slow:
    ret i64 6
  IR

# Returns biased-double WValue of (a + 1.0) if a is a number, else 6 (JSR_SLOW).
fn sm_inc_f64_bits(ab) (i64) i64
  ll <<~IR
    %ax = sub i64 %ab, 281474976710656
    %an = icmp ult i64 %ax, u0xFFF0000000000001
    br i1 %an, label %ok, label %slow
  ok:
    %ad = bitcast i64 %ax to double
    %rd = fadd double %ad, 1.0
    %rb = bitcast double %rd to i64
    %box = add i64 %rb, 281474976710656
    ret i64 %box
  slow:
    ret i64 6
  IR

# Returns 1 if a < b (both numbers), 0 if !(a < b) (both numbers), -1 if either is non-number.
fn sm_lt_f64_bits(ab, bb) (i64 i64) i64
  ll <<~IR
    %ax = sub i64 %ab, 281474976710656
    %an = icmp ult i64 %ax, u0xFFF0000000000001
    br i1 %an, label %chk_b, label %slow
  chk_b:
    %bx = sub i64 %bb, 281474976710656
    %bn = icmp ult i64 %bx, u0xFFF0000000000001
    br i1 %bn, label %cmp, label %slow
  cmp:
    %ad = bitcast i64 %ax to double
    %bd = bitcast i64 %bx to double
    %lt = fcmp olt double %ad, %bd
    %r = zext i1 %lt to i64
    ret i64 %r
  slow:
    ret i64 -1
  IR

# Pure-LLVM fast loop kernel for empty-queue pristine primitive `for (i < n) s = (s + await Promise.resolve(i)) | 0; i++`.
# Verified only when `q.head == q.tail` (resumed from microtask checkpoint, zero other microtasks),
# Promise/Promise.resolve/Promise.prototype.then pristine, and i, n, s are exact int32 numbers.
# Returns 1 if completed cleanly (updating locs[i] and locs[s]), 0 to fall back to bytecode stepping.
fn sm_run_acc_i32_loop(locs_p, i_idx, n_idx, s_idx) (i64 i64 i64 i64) i64
  ll <<~IR
    %lp = inttoptr i64 %locs_p to ptr
    %ip = getelementptr i64, ptr %lp, i64 %i_idx
    %np = getelementptr i64, ptr %lp, i64 %n_idx
    %sp = getelementptr i64, ptr %lp, i64 %s_idx
    %ib = load i64, ptr %ip, align 8
    %nb = load i64, ptr %np, align 8
    %sb = load i64, ptr %sp, align 8
    %ix = sub i64 %ib, 281474976710656
    %in = icmp ult i64 %ix, u0xFFF0000000000001
    br i1 %in, label %c_n, label %bail
  c_n:
    %nx = sub i64 %nb, 281474976710656
    %nn = icmp ult i64 %nx, u0xFFF0000000000001
    br i1 %nn, label %c_s, label %bail
  c_s:
    %sx = sub i64 %sb, 281474976710656
    %sn = icmp ult i64 %sx, u0xFFF0000000000001
    br i1 %sn, label %chk_int, label %bail
  chk_int:
    %id = bitcast i64 %ix to double
    %nd = bitcast i64 %nx to double
    %sd = bitcast i64 %sx to double
    %iw0 = fptosi double %id to i32
    %id2 = sitofp i32 %iw0 to double
    %ieq = fcmp oeq double %id2, %id
    %nw0 = fptosi double %nd to i32
    %nd2 = sitofp i32 %nw0 to double
    %neq = fcmp oeq double %nd2, %nd
    %sw0 = fptosi double %sd to i32
    %sd2 = sitofp i32 %sw0 to double
    %seq = fcmp oeq double %sd2, %sd
    %ok1 = and i1 %ieq, %neq
    %ok2 = and i1 %ok1, %seq
    %n_ok = icmp slt i32 %nw0, 100000000
    %i_ok = icmp sge i32 %iw0, -100000000
    %ok3 = and i1 %n_ok, %i_ok
    %ok = and i1 %ok2, %ok3
    br i1 %ok, label %loop, label %bail
  loop:
    %iw = phi i32 [ %iw0, %chk_int ], [ %niw, %body ]
    %sw = phi i32 [ %sw0, %chk_int ], [ %nsw, %body ]
    %more = icmp slt i32 %iw, %nw0
    br i1 %more, label %body, label %done
  body:
    %nsw = add i32 %sw, %iw
    %niw = add i32 %iw, 1
    br label %loop
  done:
    %idf = sitofp i32 %iw to double
    %ibf = bitcast double %idf to i64
    %ibx = add i64 %ibf, 281474976710656
    store i64 %ibx, ptr %ip, align 8
    %sdf = sitofp i32 %sw to double
    %sbf = bitcast double %sdf to i64
    %sbx = add i64 %sbf, 281474976710656
    store i64 %sbx, ptr %sp, align 8
    ret i64 1
  bail:
    ret i64 0
  IR

# ---- Bytecode opcodes ----

SM_STMT                  = 1   # a=stmt JsNode (non-suspending)
SM_EXPR                  = 2   # a=expr JsNode -> push wk_ev(a, act)
SM_POP                   = 3   # pop 1
SM_DUP                   = 4   # dup top
SM_PUSH_CONST            = 5   # a=val -> push a
SM_JMP                   = 6   # a=pc
SM_JMP_FALSE             = 7   # pop v; if !truthy(v) pc=a
SM_JMP_TRUE              = 8   # pop v; if truthy(v) pc=a
SM_JMP_TRUTHY_KEEP       = 9   # peek v; if truthy(v) pc=a else pop
SM_JMP_FALSY_KEEP        = 10  # peek v; if !truthy(v) pc=a else pop
SM_JMP_NOT_NULLISH_KEEP  = 11  # peek v; if !nullish(v) pc=a else pop
SM_AWAIT                 = 12  # pop v -> suspend :await
SM_YIELD                 = 13  # pop v -> suspend :yield
SM_ASYNC_YIELD           = 14  # pop v -> await then yield (async generator)
SM_YIELD_STAR_INIT       = 15  # pop iterable -> start yield*
SM_YIELD_STAR_STEP       = 16  # step active yield* on resume
SM_RETURN                = 17  # pop v -> unwind finallys then complete :return
SM_THROW                 = 18  # pop v -> unwind catch/finally
SM_TRY_PUSH              = 19  # a=catch_pc, b=finally_pc, c=catch_scope, d=catch_pat
SM_TRY_POP               = 20  # pop top try handler
SM_FINALLY_ENTER         = 21  # normal fallthrough into finally (pop try, push [:none, nil])
SM_FINALLY_END           = 22  # resume pending completion
SM_UNWIND_JMP            = 23  # a=target_pc, b=target_try_depth (break/continue across finally)
SM_SCOPE_ENTER           = 24  # a=JaScope (push old env on env_stack, enter scope)
SM_SCOPE_EXIT            = 25  # pop old env from env_stack
SM_ENV_COPY              = 26  # act.env = js_env_copy(act.env)
SM_HOIST_FNS             = 27  # a=stmts list
SM_BINOP                 = 28  # a=op str: pop rhs, lhs -> push wk_binop
SM_UNARY                 = 29  # a=op str: pop v -> push unary
SM_ASSIGN_REF            = 30  # a=JaRef, b=init bool: pop v, write ref, push v
SM_ASSIGN_OP_REF         = 31  # a=JaRef, b=binop str: pop rhs, lhs -> write & push
SM_BIND_PAT              = 32  # a=pat JsNode, b=decl bool: pop v, wk_bind
SM_GET_PROP              = 33  # a=key str: pop o -> push jget(o, key)
SM_GET_COMP              = 34  # pop k, o -> push js_getv(o, k)
SM_SET_PROP              = 35  # a=key str, b=strict: pop v, o -> set & push v
SM_SET_COMP              = 36  # a=strict: pop v, k, o -> set & push v
SM_ASSIGN_OP_PROP        = 37  # a=key str, b=binop str, c=strict: pop rhs, o -> get, op, set, push
SM_ASSIGN_OP_COMP        = 38  # a=binop str, b=strict: pop rhs, k, o -> get, op, set, push
SM_CALL                  = 39  # a=argc: stack [..., fn, this, a0..aN-1] -> push call result
SM_NEW                   = 40  # a=argc: stack [..., fn, a0..aN-1] -> push construct result
SM_ARRAY                 = 41  # a=count, b=spread_flags (Array of bools)
SM_OBJECT                = 42  # a=prop_specs
SM_TEMPLATE              = 43  # a=quasis (Array of strings)
SM_FOR_IN_INIT           = 44  # pop obj -> push [obj, keys, 0] on iters
SM_FOR_IN_NEXT           = 45  # a=end_pc: next live key -> push key or pop & jmp end_pc
SM_FOR_OF_INIT           = 46  # pop iterable -> push [rec, false] on iters
SM_FOR_OF_NEXT           = 47  # a=end_pc: step rec -> push v or pop & jmp end_pc
SM_FOR_OF_CLOSE          = 48  # pop & close iter if !done
SM_FOR_AWAIT_INIT        = 49  # pop iterable -> push [rec, sync] on iters
SM_FOR_AWAIT_NEXT        = 50  # a=end_pc: call rec.next(), await if !sync -> jmp/fallthrough
SM_FOR_AWAIT_STEP        = 51  # a=end_pc: check iter result, await value if sync
SM_FOR_AWAIT_CLOSE       = 52  # pop & async-close iter if !done
SM_DELETE_PROP           = 53  # a=key, b=strict
SM_DELETE_COMP           = 54  # a=strict
SM_ENV_SAVE              = 55  # push current act.env onto env_stack
SM_ENV_RESET             = 56  # restore act.env = env_stack.last (without popping)
SM_ITER_POP              = 57  # pop top of iters stack without closing
SM_THIS_SET_RV           = 58  # pop v; act.rv = v

# Specialized fast local loop opcodes (100% general, zero AST walk per microtask!)
SM_LOCAL_CONST           = 60  # a=lidx, b=const_val
SM_JGE_LOCAL             = 61  # a=i_lidx, b=n_lidx, c=end_pc
SM_AWAIT_RESOLVE_LOCAL   = 62  # a=lidx, b=prom_cell, c=orig_arg_expr
SM_ADD_LOCAL_I32         = 63  # a=s_lidx (adds top-of-stack v into locals[s] with | 0)
SM_INC_LOCAL             = 64  # a=lidx (locals[lidx] += 1.0)
SM_RETURN_LOCAL          = 65  # a=lidx (fast return locals[lidx])
SM_YIELD_LOCAL           = 66  # a=lidx (fast yield locals[lidx])
SM_LOCAL_GET             = 67  # a=lidx -> push locals[lidx]
SM_LOCAL_SET             = 68  # a=lidx -> pop v, locals[lidx] = v
SM_READ_REF              = 69  # a=JaRef -> push wk_read_ref(a, act)

# Extended opcodes (>= 70: private fields, with, destructuring, classes, optional chains)
SM_PRIV_IN               = 70  # a=JaRef (private_name): pop rhs -> push (#x in rhs)
SM_PRIV_GET              = 71  # a=JaRef (private_name): pop o -> push js_priv_get(o, pn)
SM_PRIV_SET              = 72  # a=JaRef (private_name): pop v, o -> js_priv_set(o, pn, v), push v
SM_PRIV_ASSIGN_OP        = 73  # a=JaRef (private_name), b=binop str: pop rhs, o -> get, op, set, push
SM_WITH_ENTER            = 74  # pop o -> push old env, act.env = WithEnv(act.env, js_to_object(o))
SM_SCOPE_ENTER_NOSAVE    = 75  # a=JaScope -> wk_scope_enter(a, act) without pushing env_stack
SM_TO_PROP_KEY           = 76  # pop k -> push js_to_property_key(k)
SM_JMP_NOT_UNDEF         = 77  # peek v; if v != nil pc=a (keep v) else pop v
SM_TEMP_PUSH             = 78  # pop v -> frame.temps.push(v)
SM_TEMP_GET              = 79  # a=offset from top (0=last) -> push frame.temps[size - 1 - a]
SM_TEMP_POP              = 80  # frame.temps.pop
SM_CHECK_OBJ_COERCIBLE   = 81  # peek v -> throw TypeError if js_nullish?(v)
SM_OBJ_REST_INIT         = 82  # frame.temps.push([])
SM_OBJ_REST_EXCLUDE      = 83  # peek k -> frame.temps.last.push(k)
SM_OBJ_REST_BUILD        = 84  # pop used from temps, peek v (temps.last) -> push rest object
SM_ITER_STEP_DSTR        = 85  # step top of frame.iters ([:of, rec]); push nil if done else v
SM_ITER_REST_DSTR        = 86  # drain top of frame.iters into Array, push array
SM_GET_VALUE             = 87  # pop k, o -> push js_get_value(o, k)
SM_SWAP                  = 88  # swap top 2 elements of vs
SM_JMP_NULLISH_SHORT     = 89  # peek v; if js_nullish?(v) { pop; push nil; pc=a }
SM_JMP_NULLISH_CALL_SHORT= 90  # peek fn (underneath this); if js_nullish?(fn) { pop fn; pop this; push nil; pc=a }
SM_CLASS_INIT_PRIVS      = 91  # a=JaScope: init all :private bindings in cs
SM_CLASS_HEAD            = 92  # a=node, b=has_extends: pop sup (if b), push [f, proto, [], [], []] on temps
SM_CLASS_METHOD          = 93  # a=member node, b=has_comp: pop key (if b), define method on class in temps
SM_CLASS_FIELD           = 94  # a=member node, b=has_comp: pop key (if b), record field on class in temps
SM_CLASS_STATIC_BLOCK    = 95  # a=member node: record static block on class in temps
SM_CLASS_FINISH          = 96  # a=node: pop class state from temps, bind inner name, run statics, push f
SM_SUPER_GET             = 97  # a=member node, b=has_comp: pop key (if b) -> push wk_super_get_key
SM_DISP_PUSH             = 98  # a=fin_pc: push DisposeCap on disps & dispose handler on tries
SM_DISP_ADD              = 99  # a=is_async: add top of vs to disps.last (leaves value on vs)
SM_DISP_ENTER            = 100 # a=fin_pc: normal exit into dispose step
SM_DISP_STEP             = 101 # step disposing cap in temps.last (may suspend :await)
SM_IMPORT_CALL           = 102 # a=phase_str_or_nil, b=has_opts_bool: pop opts(if b), spec -> push Promise

+ SmCode
  rw :ops, :a, :b, :c, :d, :len, :is_async, :is_gen, :has_try
  -> new(@is_async, @is_gen)
    @ops = i64[32]
    @a = []
    @b = []
    @c = []
    @d = []
    @len = 0
    @has_try = false

  -> emit(op, a = nil, b = nil, c = nil, d = nil)
    if @len >= @ops.size
      no = i64[@ops.size * 2]
      i = 0
      while i < @len
        no[i] = @ops[i]
        i += 1
      @ops = no
    idx = @len
    @ops[idx] = op ## i64
    @a.push(a)
    @b.push(b)
    @c.push(c)
    @d.push(d)
    @len += 1
    idx

  -> patch_a(idx, val)
    @a[idx] = val
    nil

  -> patch_b(idx, val)
    @b[idx] = val
    nil

  -> patch_c(idx, val)
    @c[idx] = val
    nil

# Does AST node `n` contain a yield, await, or for-await belonging to the CURRENT function?
-> sm_has_suspend?(n)
  return false if n == nil
  if n.is_a?(Array)
    i = 0
    while i < n.size
      return true if sm_has_suspend?(n[i])
      i += 1
    return false
  return false if !n.is_a?(JsNode)
  k = n.kind
  return false if k == :function || k == :arrow || k == :function_decl
  if k == :class || k == :class_decl
    return true if sm_has_suspend?(n.a) || sm_has_suspend?(n.b)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        m = n.list[i]
        return true if m != nil && m.has?(F_COMPUTED) && sm_has_suspend?(m.a)
        return true if m != nil && sm_has_suspend?(m.c)
        i += 1
    return false
  return true if k == :await || k == :yield
  return true if k == :for_of && n.has?(F_AWAIT)
  return true if k == :var_decl && (n.str == "using" || n.str == "await using")
  return true if sm_has_suspend?(n.a) || sm_has_suspend?(n.b) || sm_has_suspend?(n.c) || sm_has_suspend?(n.d)
  if n.list.is_a?(Array)
    i = 0
    while i < n.list.size
      return true if sm_has_suspend?(n.list[i])
      i += 1
  false

# Helper: extract local index if `e` is a direct non-captured local of `jf`, else -1.
-> sm_local_idx(e, jf)
  return -1 if jf.dynamic || e == nil || !e.is_a?(JsNode) || e.kind != :ident || e.x == nil
  b = e.x.binding
  return -1 if b == nil || b.global? || b.slot >= 0 || b.scope.func != jf || b.kind == :this || b.kind == :self || b.kind == :import
  b.lidx

# Recognize `Promise.resolve(expr)` where `Promise` is an unmodified global binding.
# Returns [prom_cell, arg_expr] or nil.
-> sm_match_prom_resolve(e)
  return nil if e == nil || e.kind != :call || e.list.size != 1
  c = e.a
  return nil if c.kind != :member || c.has?(F_COMPUTED) || c.b.str != "resolve"
  return nil if c.a.kind != :ident || c.a.str != "Promise" || c.a.x == nil
  b = c.a.x.binding
  return nil if b == nil || !b.global? || b.writes > 0
  [wk_cell(b), e.list[0]]

+ SmLoopInfo
  rw :labels, :break_patches, :cont_patches, :try_depth, :env_depth, :break_iter_depth, :cont_iter_depth, :is_switch, :fin_depth
  -> new(@labels, @try_depth, @env_depth, @break_iter_depth, @cont_iter_depth, @is_switch, @fin_depth = 0)
    @break_patches = []
    @cont_patches = []

+ SmCompiler
  rw :jf, :code, :try_depth, :env_depth, :iter_depth, :fin_depth, :loops

  -> new(@jf)
    n = @jf.node
    @code = JS:SmCode.new(n.has?(F_ASYNC), n.has?(F_GENERATOR))
    @try_depth = 0
    @env_depth = 0
    @iter_depth = 0
    @fin_depth = 0
    @loops = []

  -> compile(is_module = false)
    n = @jf.node
    if @jf.arrow && n.has?(F_EXPR_BODY)
      compile_expr(n.b)
      @code.emit(SM_RETURN)
    else
      has_disp = @jf.body_scope != nil && @jf.body_scope.has_dispose
      push_pc = -1
      if has_disp
        @code.has_try = true
        push_pc = @code.emit(SM_DISP_PUSH, 0)
        @try_depth += 1
      @code.emit(SM_HOIST_FNS, n.b) if !is_module
      compile_stmts(is_module ? n.list : n.b)
      if has_disp
        @try_depth -= 1
        j_ent = @code.emit(SM_DISP_ENTER, 0)
        fin_pc = @code.len
        @code.patch_a(push_pc, fin_pc)
        @code.patch_a(j_ent, fin_pc)
        @code.emit(SM_DISP_STEP)
      @code.emit(SM_PUSH_CONST, nil)
      @code.emit(SM_RETURN)
    @code

  -> compile_stmts(list)
    return nil if list == nil
    i = 0
    while i < list.size
      compile_stmt(list[i], nil)
      i += 1
    nil

  -> find_loop(label, is_cont)
    i = @loops.size - 1
    while i >= 0
      lp = @loops[i]
      if label == nil
        return lp if !is_cont || !lp.is_switch
      elsif lp.labels != nil && lp.labels.include?(label)
        return lp
      i -= 1
    nil

  -> compile_stmt(s, labels)
    return nil if s == nil
    k = s.kind
    if k == :empty || k == :debugger || k == :import_decl || k == :export_all
      return nil
    if k == :export_named
      compile_stmt(s.a, nil) if s.a != nil
      return nil
    if k == :export_default
      d = s.a
      if d.kind == :function_decl
        return nil
      if d.kind == :class_decl
        compile_stmt(d, nil)
        return nil
      compile_expr(d)
      @code.emit(SM_ASSIGN_REF, s.c, true)
      @code.emit(SM_POP)
      return nil
    if k == :labeled
      nl = labels == nil ? [s.str] : (labels + [s.str])
      ak = s.a.kind
      if ak == :labeled || ak == :for || ak == :while || ak == :do_while || ak == :for_in || ak == :for_of || ak == :switch
        compile_stmt(s.a, nl)
        return nil
      lp = JS:SmLoopInfo.new(nl, @try_depth, @env_depth, @iter_depth, @iter_depth, true, @fin_depth)
      @loops.push(lp)
      compile_stmt(s.a, nil)
      @loops.pop
      end_pc = @code.len
      lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
      return nil
    # Fast atomic path when statement has NO suspend AND cannot exit through active try/loop!
    if !sm_has_suspend?(s) && @try_depth == 0 && @loops.size == 0 && k != :return && k != :block && k != :if && k != :try && k != :for && k != :while && k != :do_while && k != :var_decl && k != :expr_stmt
      @code.emit(SM_STMT, s)
      return nil
    if k == :expr_stmt
      if !sm_has_suspend?(s.a)
        # Check fast `s = (s + expr) | 0` or `i++` or normal expr_stmt
        @code.emit(SM_STMT, s)
        return nil
      # Peephole: `local_s = (local_s + await ...) | 0` (huge win for async accumulator loops!)
      e = s.a
      if e.kind == :assign && e.str == "="
        sl = sm_local_idx(e.a, @jf)
        if sl >= 0 && e.b.kind == :binary && e.b.str == "|" && e.b.b.kind == :num && e.b.b.a == ~0.0
          add_e = e.b.a
          if add_e.kind == :binary && add_e.str == "+" && sm_local_idx(add_e.a, @jf) == sl && sm_has_suspend?(add_e.b)
            compile_expr(add_e.b)
            @code.emit(SM_ADD_LOCAL_I32, sl)
            return nil
      compile_expr(s.a)
      @code.emit(SM_POP)
      return nil
    if k == :var_decl
      if !sm_has_suspend?(s)
        # Fast `var s = 0` for plain local number init!
        if s.list.size == 1 && s.list[0].a.kind == :ident && s.list[0].b != nil && s.list[0].b.kind == :num
          li = sm_local_idx(s.list[0].a, @jf)
          if li >= 0
            @code.emit(SM_LOCAL_CONST, li, s.list[0].b.a)
            return nil
        @code.emit(SM_STMT, s)
        return nil
      is_lex = s.str != "var"
      is_disp = s.str == "using" || s.str == "await using"
      is_async_disp = s.str == "await using"
      i = 0
      while i < s.list.size
        d = s.list[i]
        if is_disp
          compile_expr(d.b)
          @code.emit(SM_DISP_ADD, is_async_disp)
          @code.emit(SM_ASSIGN_REF, d.a.x, true)
          @code.emit(SM_POP)
        elsif d.a.kind != :ident
          compile_expr(d.b)
          compile_bind(d.a, is_lex)
        elsif d.b != nil
          compile_expr(d.b)
          @code.emit(SM_ASSIGN_REF, d.a.x, is_lex)
          @code.emit(SM_POP)
        elsif is_lex
          @code.emit(SM_PUSH_CONST, nil)
          @code.emit(SM_ASSIGN_REF, d.a.x, true)
          @code.emit(SM_POP)
        i += 1
      return nil
    if k == :block
      if !sm_has_suspend?(s) && @try_depth == 0 && @loops.size == 0
        # Still check for return inside block
        compile_block(s)
        return nil
      compile_block(s)
      return nil
    if k == :return
      if s.a == nil
        @code.emit(SM_PUSH_CONST, nil)
        @code.emit(SM_RETURN)
        return nil
      if @code.is_async && @code.is_gen
        compile_expr(s.a)
        @code.emit(SM_AWAIT)
        @code.emit(SM_RETURN)
        return nil
      if @try_depth == 0
        li = sm_local_idx(s.a, @jf)
        if li >= 0
          @code.emit(SM_RETURN_LOCAL, li)
          return nil
      compile_expr(s.a)
      @code.emit(SM_RETURN)
      return nil
    if k == :throw
      compile_expr(s.a)
      @code.emit(SM_THROW)
      return nil
    if k == :break || k == :continue
      is_cont = k == :continue
      lp = find_loop(s.str, is_cont)
      if lp == nil
        @code.emit(SM_STMT, s)
        return nil
      tgt_id = is_cont ? lp.cont_iter_depth : lp.break_iter_depth
      # Unwind tries/finallys/envs if needed
      if @try_depth > lp.try_depth || @fin_depth > lp.fin_depth
        pi = @code.emit(SM_UNWIND_JMP, 0, (lp.try_depth << 16) | lp.fin_depth, lp.env_depth, tgt_id)
      else
        # Pop extra envs & close extra iters directly
        ec = @env_depth - lp.env_depth
        while ec > 0
          @code.emit(SM_SCOPE_EXIT)
          ec -= 1
        ic = @iter_depth - tgt_id
        while ic > 0
          @code.emit(SM_FOR_OF_CLOSE)
          ic -= 1
        pi = @code.emit(SM_JMP, 0)
      if is_cont
        lp.cont_patches.push(pi)
      else
        lp.break_patches.push(pi)
      return nil
    if k == :if
      if !sm_has_suspend?(s) && !sm_has_jump?(s)
        @code.emit(SM_STMT, s)
        return nil
      compile_expr(s.a)
      j_else = @code.emit(SM_JMP_FALSE, 0)
      compile_stmt(s.b, nil)
      if s.c != nil
        j_end = @code.emit(SM_JMP, 0)
        @code.patch_a(j_else, @code.len)
        compile_stmt(s.c, nil)
        @code.patch_a(j_end, @code.len)
      else
        @code.patch_a(j_else, @code.len)
      return nil
    if k == :while
      if !sm_has_suspend?(s) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth, @iter_depth, false, @fin_depth)
      @loops.push(lp)
      head_pc = @code.len
      compile_expr(s.a)
      j_end = @code.emit(SM_JMP_FALSE, 0)
      compile_stmt(s.b, nil)
      @code.emit(SM_JMP, head_pc)
      end_pc = @code.len
      @code.patch_a(j_end, end_pc)
      lp.cont_patches.each ->(pi) @code.patch_a(pi, head_pc)
      lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
      @loops.pop
      return nil
    if k == :do_while
      if !sm_has_suspend?(s) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth, @iter_depth, false, @fin_depth)
      @loops.push(lp)
      head_pc = @code.len
      compile_stmt(s.a, nil)
      cont_pc = @code.len
      compile_expr(s.b)
      @code.emit(SM_JMP_TRUE, head_pc)
      end_pc = @code.len
      lp.cont_patches.each ->(pi) @code.patch_a(pi, cont_pc)
      lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
      @loops.pop
      return nil
    if k == :for
      if !sm_has_suspend?(s) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      fs = s.x
      has_sc = fs.is_a?(JaScope)
      has_disp = has_sc && fs.has_dispose
      per = has_sc && fs.has_env?
      if has_sc
        @code.emit(SM_SCOPE_ENTER, fs)
        @env_depth += 1
      push_pc = -1
      if has_disp
        @code.has_try = true
        push_pc = @code.emit(SM_DISP_PUSH, 0)
        @try_depth += 1
      if s.a != nil
        if s.a.kind == :var_decl
          compile_stmt(s.a, nil)
        else
          compile_expr(s.a)
          @code.emit(SM_POP)
      @code.emit(SM_ENV_COPY) if per
      lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth, @iter_depth, false, @fin_depth)
      @loops.push(lp)
      head_pc = @code.len
      j_end = -1
      if s.b != nil
        # Peephole: `i < n` on two direct locals -> SM_JGE_LOCAL!
        if s.b.kind == :binary && s.b.str == "<"
          li = sm_local_idx(s.b.a, @jf)
          ni = sm_local_idx(s.b.b, @jf)
          if li >= 0 && ni >= 0
            j_end = @code.emit(SM_JGE_LOCAL, li, ni, 0)
          else
            compile_expr(s.b)
            j_end = @code.emit(SM_JMP_FALSE, 0)
        else
          compile_expr(s.b)
          j_end = @code.emit(SM_JMP_FALSE, 0)
      compile_stmt(s.d, nil)
      cont_pc = @code.len
      @code.emit(SM_ENV_COPY) if per
      if s.c != nil
        # Peephole: `i++` or `++i` on direct local -> SM_INC_LOCAL!
        if s.c.kind == :update && s.c.str == "++" && sm_local_idx(s.c.a, @jf) >= 0
          @code.emit(SM_INC_LOCAL, sm_local_idx(s.c.a, @jf))
        else
          compile_expr(s.c)
          @code.emit(SM_POP)
      @code.emit(SM_JMP, head_pc)
      end_pc = @code.len
      if j_end >= 0
        if @code.ops[j_end] == SM_JGE_LOCAL
          @code.patch_c(j_end, end_pc)
        else
          @code.patch_a(j_end, end_pc)
      lp.cont_patches.each ->(pi) @code.patch_a(pi, cont_pc)
      lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
      @loops.pop
      if has_disp
        @try_depth -= 1
        j_ent = @code.emit(SM_DISP_ENTER, 0)
        fin_pc = @code.len
        @code.patch_a(push_pc, fin_pc)
        @code.patch_a(j_ent, fin_pc)
        @code.emit(SM_DISP_STEP)
      if has_sc
        @code.emit(SM_SCOPE_EXIT)
        @env_depth -= 1
      return nil
    if k == :try
      compile_try(s)
      return nil
    if k == :for_in
      if !sm_has_suspend?(s) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      compile_for_in(s, labels)
      return nil
    if k == :for_of
      if !sm_has_suspend?(s) && !s.has?(F_AWAIT) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      if s.has?(F_AWAIT)
        compile_for_await(s, labels)
      else
        compile_for_of(s, labels)
      return nil
    if k == :switch
      if !sm_has_suspend?(s) && !sm_has_outer_jump?(s, labels)
        @code.emit(SM_STMT, s)
        return nil
      compile_switch(s, labels)
      return nil
    if k == :class_decl
      if !sm_has_suspend?(s)
        @code.emit(SM_STMT, s)
        return nil
      compile_class(s, true)
      return nil
    if k == :with
      if !sm_has_suspend?(s) && !sm_has_jump?(s)
        @code.emit(SM_STMT, s)
        return nil
      compile_expr(s.a)
      @code.emit(SM_WITH_ENTER)
      @env_depth += 1
      compile_stmt(s.b, nil)
      @code.emit(SM_SCOPE_EXIT)
      @env_depth -= 1
      return nil
    @code.emit(SM_STMT, s)
    nil

  -> compile_block(s)
    sc = s.x
    has_sc = sc.is_a?(JaScope)
    has_disp = has_sc && sc.has_dispose
    if has_sc
      @code.emit(SM_SCOPE_ENTER, sc)
      @env_depth += 1
    push_pc = -1
    if has_disp
      @code.has_try = true
      push_pc = @code.emit(SM_DISP_PUSH, 0)
      @try_depth += 1
    @code.emit(SM_HOIST_FNS, s.list)
    compile_stmts(s.list)
    if has_disp
      @try_depth -= 1
      j_ent = @code.emit(SM_DISP_ENTER, 0)
      fin_pc = @code.len
      @code.patch_a(push_pc, fin_pc)
      @code.patch_a(j_ent, fin_pc)
      @code.emit(SM_DISP_STEP)
    if has_sc
      @code.emit(SM_SCOPE_EXIT)
      @env_depth -= 1
    nil

  -> compile_try(s)
    @code.has_try = true
    has_c = s.c != nil
    has_f = s.d != nil
    cs = s.x.is_a?(JaScope) ? s.x : nil
    push_pc = @code.emit(SM_TRY_PUSH, -1, -1, cs, s.b)
    @try_depth += 1
    compile_stmt(s.a, nil)
    @try_depth -= 1
    if has_f
      j_to_fin = @code.emit(SM_FINALLY_ENTER, 0)
    else
      @code.emit(SM_TRY_POP)
      j_after_c = @code.emit(SM_JMP, 0)
    if has_c
      catch_pc = @code.len
      @code.patch_a(push_pc, catch_pc)
      # If there's also a finally, runtime pushes a finally-only handler when entering catch!
      @try_depth += 1 if has_f
      cs_env = cs != nil && cs.has_env?
      @env_depth += 1 if cs_env
      compile_block(s.c)
      if cs_env
        @code.emit(SM_SCOPE_EXIT)
        @env_depth -= 1
      @try_depth -= 1 if has_f
      if has_f
        @code.emit(SM_FINALLY_ENTER, 0)
    if has_f
      fin_pc = @code.len
      @code.patch_b(push_pc, fin_pc)
      @code.patch_a(j_to_fin, fin_pc)
      @fin_depth += 1
      compile_block(s.d)
      @fin_depth -= 1
      @code.emit(SM_FINALLY_END)
    else
      @code.patch_a(j_after_c, @code.len)
    nil

  -> compile_for_in(s, labels)
    fs = s.x
    has_sc = fs.is_a?(JaScope)
    if s.a.kind == :var_decl && s.a.list[0].b != nil
      compile_expr(s.a.list[0].b)
      compile_bind(s.a.list[0].a, true)
    @code.emit(SM_ENV_SAVE)
    @env_depth += 1
    @code.emit(SM_SCOPE_ENTER_NOSAVE, fs) if has_sc
    compile_expr(s.b)
    @code.emit(SM_FOR_IN_INIT)
    @iter_depth += 1
    lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth - 1, @iter_depth, false, @fin_depth)
    @loops.push(lp)
    head_pc = @code.len
    j_end = @code.emit(SM_FOR_IN_NEXT, 0)
    if has_sc
      @code.emit(SM_ENV_RESET)
      @code.emit(SM_SCOPE_ENTER_NOSAVE, fs)
    bind_pat = s.a.kind == :var_decl ? s.a.list[0].a : s.a
    compile_bind(bind_pat, s.a.kind == :var_decl)
    compile_stmt(s.d, nil)
    @code.emit(SM_JMP, head_pc)
    end_pc = @code.len
    @code.patch_a(j_end, end_pc)
    lp.cont_patches.each ->(pi) @code.patch_a(pi, head_pc)
    lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
    @loops.pop
    @iter_depth -= 1
    @code.emit(SM_SCOPE_EXIT)
    @env_depth -= 1
    nil

  -> compile_for_of(s, labels)
    fs = s.x
    has_sc = fs.is_a?(JaScope)
    is_disp = s.a.kind == :var_decl && (s.a.str == "using" || s.a.str == "await using")
    is_async_disp = s.a.kind == :var_decl && s.a.str == "await using"
    @code.emit(SM_ENV_SAVE)
    @env_depth += 1
    @code.emit(SM_SCOPE_ENTER_NOSAVE, fs) if has_sc
    compile_expr(s.b)
    @code.emit(SM_FOR_OF_INIT)
    @iter_depth += 1
    lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth - 1, @iter_depth, false, @fin_depth)
    @loops.push(lp)
    head_pc = @code.len
    j_end = @code.emit(SM_FOR_OF_NEXT, 0)
    if has_sc
      @code.emit(SM_ENV_RESET)
      @code.emit(SM_SCOPE_ENTER_NOSAVE, fs)
    bind_pat = s.a.kind == :var_decl ? s.a.list[0].a : s.a
    if is_disp
      @code.has_try = true
      @code.emit(SM_TEMP_PUSH)
      push_pc = @code.emit(SM_DISP_PUSH, 0)
      @try_depth += 1
      @code.emit(SM_TEMP_GET, 0)
      @code.emit(SM_TEMP_POP)
      @code.emit(SM_DISP_ADD, is_async_disp)
      @code.emit(SM_ASSIGN_REF, bind_pat.x, true)
      @code.emit(SM_POP)
      compile_stmt(s.d, nil)
      @try_depth -= 1
      j_ent = @code.emit(SM_DISP_ENTER, 0)
      fin_pc = @code.len
      @code.patch_a(push_pc, fin_pc)
      @code.patch_a(j_ent, fin_pc)
      @code.emit(SM_DISP_STEP)
    else
      compile_bind(bind_pat, s.a.kind == :var_decl)
      compile_stmt(s.d, nil)
    @code.emit(SM_JMP, head_pc)
    end_pc = @code.len
    @code.patch_a(j_end, end_pc)
    lp.cont_patches.each ->(pi) @code.patch_a(pi, head_pc)
    lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
    @loops.pop
    @iter_depth -= 1
    @code.emit(SM_SCOPE_EXIT)
    @env_depth -= 1
    nil

  -> compile_for_await(s, labels)
    fs = s.x
    has_sc = fs.is_a?(JaScope)
    is_disp = s.a.kind == :var_decl && (s.a.str == "using" || s.a.str == "await using")
    is_async_disp = s.a.kind == :var_decl && s.a.str == "await using"
    @code.emit(SM_ENV_SAVE)
    @env_depth += 1
    @code.emit(SM_SCOPE_ENTER_NOSAVE, fs) if has_sc
    compile_expr(s.b)
    @code.emit(SM_FOR_AWAIT_INIT)
    @iter_depth += 1
    lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth - 1, @iter_depth, false, @fin_depth)
    @loops.push(lp)
    head_pc = @code.len
    j_end1 = @code.emit(SM_FOR_AWAIT_NEXT, 0)
    j_end2 = @code.emit(SM_FOR_AWAIT_STEP, 0)
    if has_sc
      @code.emit(SM_ENV_RESET)
      @code.emit(SM_SCOPE_ENTER_NOSAVE, fs)
    bind_pat = s.a.kind == :var_decl ? s.a.list[0].a : s.a
    if is_disp
      @code.has_try = true
      @code.emit(SM_TEMP_PUSH)
      push_pc = @code.emit(SM_DISP_PUSH, 0)
      @try_depth += 1
      @code.emit(SM_TEMP_GET, 0)
      @code.emit(SM_TEMP_POP)
      @code.emit(SM_DISP_ADD, is_async_disp)
      @code.emit(SM_ASSIGN_REF, bind_pat.x, true)
      @code.emit(SM_POP)
      compile_stmt(s.d, nil)
      @try_depth -= 1
      j_ent = @code.emit(SM_DISP_ENTER, 0)
      fin_pc = @code.len
      @code.patch_a(push_pc, fin_pc)
      @code.patch_a(j_ent, fin_pc)
      @code.emit(SM_DISP_STEP)
    else
      compile_bind(bind_pat, s.a.kind == :var_decl)
      compile_stmt(s.d, nil)
    @code.emit(SM_JMP, head_pc)
    end_pc = @code.len
    @code.patch_a(j_end1, end_pc)
    @code.patch_a(j_end2, end_pc)
    lp.cont_patches.each ->(pi) @code.patch_a(pi, head_pc)
    lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
    @loops.pop
    @iter_depth -= 1
    @code.emit(SM_SCOPE_EXIT)
    @env_depth -= 1
    nil

  -> compile_switch(s, labels)
    bs = s.x
    has_sc = bs.is_a?(JaScope)
    if has_sc
      @code.emit(SM_SCOPE_ENTER, bs)
      @env_depth += 1
    lp = JS:SmLoopInfo.new(labels, @try_depth, @env_depth, @iter_depth, @iter_depth, true, @fin_depth)
    @loops.push(lp)
    compile_expr(s.a)
    n = s.list.size
    all = []
    i = 0
    while i < n
      all = all + s.list[i].list
      i += 1
    @code.emit(SM_HOIST_FNS, all)
    case_jmps = []
    dflt_idx = -1
    i = 0
    while i < n
      c = s.list[i]
      if c.a == nil
        dflt_idx = i
        case_jmps.push(-1)
      else
        @code.emit(SM_DUP)
        compile_expr(c.a)
        @code.emit(SM_BINOP, "===")
        case_jmps.push(@code.emit(SM_JMP_TRUE, 0))
      i += 1
    @code.emit(SM_POP)
    j_dflt = @code.emit(SM_JMP, 0)
    body_pcs = []
    i = 0
    while i < n
      body_pcs.push(@code.len)
      @code.emit(SM_POP) if i != dflt_idx
      compile_stmts(s.list[i].list)
      i += 1
    end_pc = @code.len
    i = 0
    while i < n
      @code.patch_a(case_jmps[i], body_pcs[i]) if case_jmps[i] >= 0
      i += 1
    @code.patch_a(j_dflt, dflt_idx >= 0 ? body_pcs[dflt_idx] : end_pc)
    lp.break_patches.each ->(pi) @code.patch_a(pi, end_pc)
    @loops.pop
    if has_sc
      @code.emit(SM_SCOPE_EXIT)
      @env_depth -= 1
    nil

  -> sm_has_jump?(n)
    return false if n == nil || !n.is_a?(JsNode)
    k = n.kind
    return false if k == :function || k == :arrow || k == :function_decl || k == :class || k == :class_decl
    return true if k == :return || k == :break || k == :continue
    return true if sm_has_jump?(n.a) || sm_has_jump?(n.b) || sm_has_jump?(n.c) || sm_has_jump?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if sm_has_jump?(n.list[i])
        i += 1
    false

  -> sm_has_outer_jump?(n, labels)
    return true if @try_depth > 0 && sm_has_jump?(n)
    sm_has_return_or_labeled_jump?(n)

  -> sm_has_return_or_labeled_jump?(n)
    return false if n == nil || !n.is_a?(JsNode)
    k = n.kind
    return false if k == :function || k == :arrow || k == :function_decl || k == :class || k == :class_decl
    return true if k == :return
    return true if (k == :break || k == :continue) && n.str != nil
    return true if sm_has_return_or_labeled_jump?(n.a) || sm_has_return_or_labeled_jump?(n.b) || sm_has_return_or_labeled_jump?(n.c) || sm_has_return_or_labeled_jump?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if sm_has_return_or_labeled_jump?(n.list[i])
        i += 1
    false

  # ---- Suspending expression compiler ----

  -> compile_expr(e)
    if e == nil
      @code.emit(SM_PUSH_CONST, nil)
      return nil
    if !sm_has_suspend?(e)
      li = sm_local_idx(e, @jf)
      if li >= 0
        @code.emit(SM_LOCAL_GET, li)
        return nil
      @code.emit(SM_EXPR, e)
      return nil
    k = e.kind
    if k == :await
      # Peephole: `await Promise.resolve(local_var)` -> zero-Promise SM_AWAIT_RESOLVE_LOCAL!
      pm = sm_match_prom_resolve(e.a)
      if pm != nil && !sm_has_suspend?(pm[1])
        li = sm_local_idx(pm[1], @jf)
        if li >= 0
          @code.emit(SM_AWAIT_RESOLVE_LOCAL, li, pm[0], e.a)
          return nil
      compile_expr(e.a)
      @code.emit(SM_AWAIT)
      return nil
    if k == :yield
      if e.has?(F_DELEGATE)
        compile_expr(e.a)
        @code.emit(SM_YIELD_STAR_INIT)
        @code.emit(SM_YIELD_STAR_STEP)
        return nil
      if e.a == nil
        @code.emit(SM_PUSH_CONST, nil)
      else
        compile_expr(e.a)
      @code.emit(@code.is_async ? SM_ASYNC_YIELD : SM_YIELD)
      return nil
    if k == :binary
      if e.a.kind == :private_name
        compile_expr(e.b)
        @code.emit(SM_PRIV_IN, e.a.x)
        return nil
      compile_expr(e.a)
      compile_expr(e.b)
      @code.emit(SM_BINOP, e.str)
      return nil
    if k == :unary
      if e.str == "delete" && e.a.kind == :member
        compile_expr(e.a.a)
        if e.a.has?(F_COMPUTED)
          compile_expr(e.a.b)
          @code.emit(SM_DELETE_COMP, @jf.strict)
        else
          @code.emit(SM_DELETE_PROP, e.a.b.str, @jf.strict)
        return nil
      compile_expr(e.a)
      @code.emit(SM_UNARY, e.str)
      return nil
    if k == :logical
      compile_expr(e.a)
      if e.str == "&&"
        j = @code.emit(SM_JMP_FALSY_KEEP, 0)
      elsif e.str == "||"
        j = @code.emit(SM_JMP_TRUTHY_KEEP, 0)
      else
        j = @code.emit(SM_JMP_NOT_NULLISH_KEEP, 0)
      compile_expr(e.b)
      @code.patch_a(j, @code.len)
      return nil
    if k == :cond
      compile_expr(e.a)
      j_f = @code.emit(SM_JMP_FALSE, 0)
      compile_expr(e.b)
      j_e = @code.emit(SM_JMP, 0)
      @code.patch_a(j_f, @code.len)
      compile_expr(e.c)
      @code.patch_a(j_e, @code.len)
      return nil
    if k == :seq
      i = 0
      while i < e.list.size
        compile_expr(e.list[i])
        @code.emit(SM_POP) if i + 1 < e.list.size
        i += 1
      return nil
    if k == :assign
      op = e.str
      t = e.a
      if t.kind == :ident
        if op == "="
          compile_expr(e.b)
          @code.emit(SM_ASSIGN_REF, t.x, false)
        elsif op == "&&=" || op == "||=" || op == "??="
          @code.emit(SM_READ_REF, t.x)
          j_s = op == "&&=" ? @code.emit(SM_JMP_FALSY_KEEP, 0) : (op == "||=" ? @code.emit(SM_JMP_TRUTHY_KEEP, 0) : @code.emit(SM_JMP_NOT_NULLISH_KEEP, 0))
          compile_expr(e.b)
          @code.emit(SM_ASSIGN_REF, t.x, false)
          @code.patch_a(j_s, @code.len)
        else
          @code.emit(SM_READ_REF, t.x)
          compile_expr(e.b)
          @code.emit(SM_ASSIGN_OP_REF, t.x, op.slice(0, op.size - 1))
        return nil
      if t.kind == :member
        compile_expr(t.a)
        if t.b.kind == :private_name
          compile_expr(e.b)
          if op == "="
            @code.emit(SM_PRIV_SET, t.b.x)
          else
            @code.emit(SM_PRIV_ASSIGN_OP, t.b.x, op.slice(0, op.size - 1))
          return nil
        if t.has?(F_COMPUTED)
          compile_expr(t.b)
          compile_expr(e.b)
          if op == "="
            @code.emit(SM_SET_COMP, @jf.strict)
          else
            @code.emit(SM_ASSIGN_OP_COMP, op.slice(0, op.size - 1), @jf.strict)
        else
          compile_expr(e.b)
          if op == "="
            @code.emit(SM_SET_PROP, t.b.str, @jf.strict)
          else
            @code.emit(SM_ASSIGN_OP_PROP, t.b.str, op.slice(0, op.size - 1), @jf.strict)
        return nil
      # Destructuring pattern assignment
      compile_expr(e.b)
      @code.emit(SM_DUP)
      compile_bind(t, false)
      return nil
    if k == :member
      if e.a.kind == :super
        if e.has?(F_COMPUTED)
          compile_expr(e.b)
          @code.emit(SM_SUPER_GET, e, true)
        else
          @code.emit(SM_SUPER_GET, e, false)
        return nil
      compile_expr(e.a)
      if e.has?(F_COMPUTED)
        compile_expr(e.b)
        @code.emit(SM_GET_COMP)
      elsif e.b.kind == :private_name
        @code.emit(SM_PRIV_GET, e.b.x)
      else
        @code.emit(SM_GET_PROP, e.b.str)
      return nil
    if k == :chain
      sp = []
      compile_chain(e.a, sp)
      end_pc = @code.len
      sp.each ->(pi) @code.patch_a(pi, end_pc)
      return nil
    if k == :class
      compile_class(e, false)
      return nil
    if k == :import_call
      compile_expr(e.a)
      compile_expr(e.b) if e.b != nil
      @code.emit(SM_IMPORT_CALL, e.str, e.b != nil)
      return nil
    if k == :call
      c = e.a
      if c.kind == :member
        compile_expr(c.a)
        @code.emit(SM_DUP)
        if c.has?(F_COMPUTED)
          compile_expr(c.b)
          @code.emit(SM_GET_COMP)
        elsif c.b.kind == :private_name
          @code.emit(SM_PRIV_GET, c.b.x)
        else
          @code.emit(SM_GET_PROP, c.b.str)
        # Convention: SM_CALL expects [..., this, fn, a0..aN-1]!
        sp = compile_call_args(e.list)
        @code.emit(SM_CALL, e.list.size, sp)
        return nil
      @code.emit(SM_PUSH_CONST, nil)   # this = undefined
      compile_expr(c)                  # fn
      sp = compile_call_args(e.list)
      @code.emit(SM_CALL, e.list.size, sp)
      return nil
    if k == :new
      compile_expr(e.a)
      sp = compile_call_args(e.list)
      @code.emit(SM_NEW, e.list.size, sp)
      return nil
    if k == :array
      spreads = []
      i = 0
      while i < e.list.size
        el = e.list[i]
        if el == nil
          @code.emit(SM_PUSH_CONST, JS_HOLE)
          spreads.push(false)
        elsif el.kind == :spread
          compile_expr(el.a)
          spreads.push(true)
        else
          compile_expr(el)
          spreads.push(false)
        i += 1
      @code.emit(SM_ARRAY, e.list.size, spreads)
      return nil
    if k == :object
      specs = []
      i = 0
      while i < e.list.size
        p = e.list[i]
        if p.kind == :spread
          compile_expr(p.a)
          specs.push([:spread, nil])
        elsif p.has?(F_COMPUTED)
          compile_expr(p.a)
          compile_expr(p.b)
          specs.push([:comp, p.str])
        else
          compile_expr(p.b)
          specs.push([:prop, p.str, wk_prop_key(p.a)])
        i += 1
      @code.emit(SM_OBJECT, specs)
      return nil
    if k == :template
      quasis = []
      i = 0
      while i < e.list.size
        quasis.push(e.list[i].str)
        compile_expr(e.a[i]) if i < e.a.size
        i += 1
      @code.emit(SM_TEMPLATE, quasis)
      return nil
    @code.emit(SM_EXPR, e)
    nil

  # ---- Suspending optional chains, classes, and destructuring patterns ----

  -> compile_chain(e, sp)
    k = e.kind
    if k == :member
      if e.a.kind == :super
        if e.has?(F_COMPUTED)
          compile_expr(e.b)
          @code.emit(SM_SUPER_GET, e, true)
        else
          @code.emit(SM_SUPER_GET, e, false)
        return nil
      compile_chain(e.a, sp)
      sp.push(@code.emit(SM_JMP_NULLISH_SHORT, 0)) if e.has?(F_OPTIONAL)
      if e.has?(F_COMPUTED)
        compile_expr(e.b)
        @code.emit(SM_GET_COMP)
      elsif e.b.kind == :private_name
        @code.emit(SM_PRIV_GET, e.b.x)
      else
        @code.emit(SM_GET_PROP, e.b.str)
      return nil
    if k == :call
      c = e.a
      c = c.a if c.kind == :chain
      if c.kind == :member && c.a.kind != :super
        compile_chain(c.a, sp)
        sp.push(@code.emit(SM_JMP_NULLISH_SHORT, 0)) if c.has?(F_OPTIONAL)
        @code.emit(SM_DUP)
        if c.has?(F_COMPUTED)
          compile_expr(c.b)
          @code.emit(SM_GET_COMP)
        elsif c.b.kind == :private_name
          @code.emit(SM_PRIV_GET, c.b.x)
        else
          @code.emit(SM_GET_PROP, c.b.str)
        sp.push(@code.emit(SM_JMP_NULLISH_CALL_SHORT, 0)) if e.has?(F_OPTIONAL)
        cs = compile_call_args(e.list)
        @code.emit(SM_CALL, e.list.size, cs)
        return nil
      compile_chain(c, sp)
      sp.push(@code.emit(SM_JMP_NULLISH_SHORT, 0)) if e.has?(F_OPTIONAL)
      @code.emit(SM_PUSH_CONST, nil)
      @code.emit(SM_SWAP)
      cs = compile_call_args(e.list)
      @code.emit(SM_CALL, e.list.size, cs)
      return nil
    compile_expr(e)
    nil

  -> compile_call_args(list)
    has_sp = false
    i = 0
    while i < list.size
      if list[i].kind == :spread
        has_sp = true
        break
      i += 1
    if !has_sp
      i = 0
      while i < list.size
        compile_expr(list[i])
        i += 1
      return nil
    spreads = []
    i = 0
    while i < list.size
      el = list[i]
      if el.kind == :spread
        compile_expr(el.a)
        spreads.push(true)
      else
        compile_expr(el)
        spreads.push(false)
      i += 1
    spreads

  -> compile_class(n, is_decl)
    cs = n.x
    @code.emit(SM_SCOPE_ENTER, cs)
    @env_depth += 1
    @code.emit(SM_CLASS_INIT_PRIVS, cs)
    if n.a != nil
      compile_expr(n.a)
    @code.emit(SM_CLASS_HEAD, n, n.a != nil)
    i = 0
    while i < n.list.size
      m = n.list[i]
      if m.kind == :method_def && m.str != "constructor"
        if m.a.kind != :private_name && m.has?(F_COMPUTED)
          compile_expr(m.a)
          @code.emit(SM_TO_PROP_KEY)
          @code.emit(SM_CLASS_METHOD, m, true)
        else
          @code.emit(SM_CLASS_METHOD, m, false)
      elsif m.kind == :field_def
        if m.a.kind != :private_name && m.has?(F_COMPUTED)
          compile_expr(m.a)
          @code.emit(SM_TO_PROP_KEY)
          @code.emit(SM_CLASS_FIELD, m, true)
        else
          @code.emit(SM_CLASS_FIELD, m, false)
      elsif m.kind == :static_block
        @code.emit(SM_CLASS_STATIC_BLOCK, m)
      i += 1
    @code.emit(SM_CLASS_FINISH, n)
    @code.emit(SM_SCOPE_EXIT)
    @env_depth -= 1
    if is_decl
      @code.emit(SM_ASSIGN_REF, n.c, true)
      @code.emit(SM_POP)
    nil

  # Bind/assign top-of-stack value to pattern `pat` (consumes 1 value from vs).
  -> compile_bind(pat, decl)
    if !sm_has_suspend?(pat)
      @code.emit(SM_BIND_PAT, pat, decl)
      return nil
    k = pat.kind
    if k == :ident
      @code.emit(SM_ASSIGN_REF, pat.x, decl)
      @code.emit(SM_POP)
      return nil
    if k == :assign_pattern
      j_s = @code.emit(SM_JMP_NOT_UNDEF, 0)
      compile_expr(pat.b)
      @code.patch_a(j_s, @code.len)
      compile_bind(pat.a, decl)
      return nil
    if k == :member
      @code.emit(SM_TEMP_PUSH)
      compile_expr(pat.a)
      if pat.b.kind == :private_name
        @code.emit(SM_TEMP_GET, 0)
        @code.emit(SM_TEMP_POP)
        @code.emit(SM_PRIV_SET, pat.b.x)
        @code.emit(SM_POP)
      elsif pat.has?(F_COMPUTED)
        compile_expr(pat.b)
        @code.emit(SM_TEMP_GET, 0)
        @code.emit(SM_TEMP_POP)
        @code.emit(SM_SET_COMP, @jf.strict)
        @code.emit(SM_POP)
      else
        @code.emit(SM_TEMP_GET, 0)
        @code.emit(SM_TEMP_POP)
        @code.emit(SM_SET_PROP, pat.b.str, @jf.strict)
        @code.emit(SM_POP)
      return nil
    if k == :array_pattern
      compile_bind_array(pat, decl)
      return nil
    if k == :object_pattern
      compile_bind_object(pat, decl)
      return nil
    @code.emit(SM_BIND_PAT, pat, decl)
    nil

  -> compile_bind_array(pat, decl)
    @code.emit(SM_FOR_OF_INIT)
    @iter_depth += 1
    i = 0
    while i < pat.list.size
      e = pat.list[i]
      if e == nil
        @code.emit(SM_ITER_STEP_DSTR)
        @code.emit(SM_POP)
      else
        t = (e.kind == :rest || e.kind == :assign_pattern) ? e.a : e
        mem = !decl && t.kind == :member && t.a.kind != :super
        if mem
          compile_expr(t.a)
          if t.b.kind != :private_name && t.has?(F_COMPUTED)
            compile_expr(t.b)
          if e.kind == :rest
            @code.emit(SM_ITER_REST_DSTR)
          else
            @code.emit(SM_ITER_STEP_DSTR)
            if e.kind == :assign_pattern
              j_s = @code.emit(SM_JMP_NOT_UNDEF, 0)
              compile_expr(e.b)
              @code.patch_a(j_s, @code.len)
          if t.b.kind == :private_name
            @code.emit(SM_PRIV_SET, t.b.x)
          elsif t.has?(F_COMPUTED)
            @code.emit(SM_SET_COMP, @jf.strict)
          else
            @code.emit(SM_SET_PROP, t.b.str, @jf.strict)
          @code.emit(SM_POP)
        else
          if e.kind == :rest
            @code.emit(SM_ITER_REST_DSTR)
            compile_bind(e.a, decl)
          else
            @code.emit(SM_ITER_STEP_DSTR)
            compile_bind(e, decl)
      i += 1
    @code.emit(SM_FOR_OF_CLOSE)
    @iter_depth -= 1
    nil

  -> compile_bind_object(pat, decl)
    has_rest = pat.list.size > 0 && pat.list[pat.list.size - 1].kind == :rest
    @code.emit(SM_CHECK_OBJ_COERCIBLE)
    @code.emit(SM_TEMP_PUSH)
    @code.emit(SM_OBJ_REST_INIT) if has_rest
    v_off = has_rest ? 1 : 0
    i = 0
    while i < pat.list.size
      e = pat.list[i]
      if e.kind == :rest
        @code.emit(SM_OBJ_REST_BUILD)
        compile_bind(e.a, decl)
      else
        if e.has?(F_COMPUTED)
          compile_expr(e.a)
          @code.emit(SM_TO_PROP_KEY)
        else
          @code.emit(SM_PUSH_CONST, wk_prop_key(e.a))
        @code.emit(SM_OBJ_REST_EXCLUDE) if has_rest
        t = e.b.kind == :assign_pattern ? e.b.a : e.b
        if !decl && t.kind == :member && t.a.kind != :super
          @code.emit(SM_TEMP_PUSH)
          compile_expr(t.a)
          if t.b.kind != :private_name && t.has?(F_COMPUTED)
            compile_expr(t.b)
          @code.emit(SM_TEMP_GET, v_off + 1)
          @code.emit(SM_TEMP_GET, 0)
          @code.emit(SM_TEMP_POP)
          @code.emit(SM_GET_VALUE)
          if e.b.kind == :assign_pattern
            j_s = @code.emit(SM_JMP_NOT_UNDEF, 0)
            compile_expr(e.b.b)
            @code.patch_a(j_s, @code.len)
          if t.b.kind == :private_name
            @code.emit(SM_PRIV_SET, t.b.x)
          elsif t.has?(F_COMPUTED)
            @code.emit(SM_SET_COMP, @jf.strict)
          else
            @code.emit(SM_SET_PROP, t.b.str, @jf.strict)
          @code.emit(SM_POP)
        else
          @code.emit(SM_TEMP_GET, v_off)
          @code.emit(SM_SWAP)
          @code.emit(SM_GET_VALUE)
          compile_bind(e.b, decl)
      i += 1
    @code.emit(SM_TEMP_POP)
    nil

-> js_sm_compile(jf)
  c = wk_code(jf)
  sc = c.sm_code
  if sc == nil
    sc = JS:SmCompiler.new(jf).compile
    c.sm_code = sc
  sc

-> js_sm_compile_module(jf)
  comp = JS:SmCompiler.new(jf)
  comp.code.is_async = true
  comp.code.is_gen = false
  comp.compile(true)

# ---- Stackless Resumable Execution Frame ----

+ SmFrame
  rw :code, :act, :pc, :state, :vstack, :tries, :pendings, :env_stack, :iters, :temps, :disps, :disp_awaiting, :closing, :promise, :async_gen, :async_yield_phase, :ystar_rec, :ystar_phase, :result_kind, :result_val

  -> new(@code, @act)
    @pc = 0
    @state = :start
    @vstack = []
    @tries = []
    @pendings = []
    @env_stack = []
    @iters = []
    @temps = []
    @disps = []
    @disp_awaiting = false
    @closing = nil
    @promise = nil
    @async_gen = nil
    @async_yield_phase = 0   # 0=none, 1=awaiting yield val, 2=yielded, 3=awaiting return val
    @ystar_rec = nil
    @ystar_phase = 0         # async yield* phase: 0=call, 1=await next/throw, 2=await return, 3=await return(no-ret), 4=await close(no-throw), 5=yielded, 6=await return-resumption
    @result_kind = nil
    @result_val = nil

# Create an Async-from-Sync Iterator (§27.1.4) wrapping a sync IterRecord.
-> js_async_from_sync_cont(res, sync_rec, prom, close_on_rej = true)
  r = js_realm()
  q = r.jobs
  begin
    js_throw_type("Iterator result is not an object") if !js_object?(res)
    done = js_truthy(jget(res, "done"))
    val = jget(res, "value")
    pw = nil
    begin
      pw = js_promise_resolve_value(val)
    rescue ex2
      js_iter_close_quiet(sync_rec) if !done && close_on_rej
      raise ex2
    on_f = r.native("", 1, ->(this, args, nt) js_iter_result(js_arg(args, 0), done))
    on_r = nil
    if !done && close_on_rej
      on_r_fn = ->(this, args, nt)
        err = js_arg(args, 0)
        js_iter_close_quiet(sync_rec)
        js_throw(err)
      on_r = js_keep(r.native("", 1, on_r_fn), [sync_rec])
    cap = JS:Capability.new(prom, ->(x) js_promise_resolve_with(prom, x), ->(x) js_promise_reject_fast(prom, x, q))
    js_perform_then(pw, JS:Reaction.new(cap, :fulfill, on_f), JS:Reaction.new(cap, :reject, on_r))
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  prom

-> js_afs_next(sync_rec, args)
  r = js_realm()
  q = r.jobs
  prom = JS:Promise.new(r.promise_shape)
  begin
    res = js_call_arr(sync_rec.next_fn, sync_rec.iterator, args.size == 0 ? JS_NO_ARGS : [args[0]])
    js_async_from_sync_cont(res, sync_rec, prom, true)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  prom

-> js_afs_return(sync_rec, args)
  r = js_realm()
  q = r.jobs
  prom = JS:Promise.new(r.promise_shape)
  begin
    ret = js_get_method(sync_rec.iterator, "return")
    if ret == nil
      v = args.size == 0 ? nil : args[0]
      pw = js_promise_resolve_value(v)
      on_f = r.native("", 1, ->(t, a, n) js_iter_result(js_arg(a, 0), true))
      cap = JS:Capability.new(prom, ->(x) js_promise_resolve_with(prom, x), ->(x) js_promise_reject_fast(prom, x, q))
      js_perform_then(pw, JS:Reaction.new(cap, :fulfill, on_f), JS:Reaction.new(cap, :reject, nil))
      return prom
    res = js_call_arr(ret, sync_rec.iterator, args.size == 0 ? JS_NO_ARGS : [args[0]])
    js_async_from_sync_cont(res, sync_rec, prom, false)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  prom

-> js_afs_throw(sync_rec, args)
  r = js_realm()
  q = r.jobs
  prom = JS:Promise.new(r.promise_shape)
  begin
    th = js_get_method(sync_rec.iterator, "throw")
    if th == nil
      js_iter_close(sync_rec)
      js_promise_reject_fast(prom, js_make_error("TypeError", "The iterator does not provide a 'throw' method"), q)
      return prom
    res = js_call_arr(th, sync_rec.iterator, args.size == 0 ? JS_NO_ARGS : [args[0]])
    js_async_from_sync_cont(res, sync_rec, prom, true)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  prom

-> js_create_async_from_sync_iter(sync_rec)
  r = js_realm()
  o = js_new_object(r.object_proto)
  nf = r.method(o, "next", 1, ->(this, args, nt) js_afs_next(sync_rec, args))
  r.method(o, "return", 1, ->(this, args, nt) js_afs_return(sync_rec, args))
  r.method(o, "throw", 1, ->(this, args, nt) js_afs_throw(sync_rec, args))
  JS:IterRecord.new(o, nf)

# Run SmFrame until it suspends (:await, :yield, :yield_raw) or completes (:return, :throw).
# Sets frame.result_kind and frame.result_val.
# is_resumed: true ONLY when called from microtask drain (never on initial sync call, so first await ALWAYS suspends!).
-> js_sm_run(frame, resume_kind, resume_val, q, is_resumed = false)
  fr = nil
  if frame.act.fobj != nil && frame.act.fobj.is_a?(JS:Function)
    fr = frame.act.fobj.code.realm
  elsif frame.act.f != nil && frame.act.f.code != nil
    fr = frame.act.f.code.realm
  if fr != nil && fr != JS_REALM[0]
    prev = JS_REALM[0]
    JS_REALM[0] = fr
    begin
      js_sm_run_inner(frame, resume_kind, resume_val, q, is_resumed)
    rescue ex
      JS_REALM[0] = prev
      raise ex
    JS_REALM[0] = prev
    return nil
  js_sm_run_inner(frame, resume_kind, resume_val, q, is_resumed)

-> js_sm_run_inner(frame, resume_kind, resume_val, q, is_resumed = false)
  act = frame.act
  code = frame.code
  ops = code.ops
  ca = code.a
  cb = code.b
  cc = code.c
  cd = code.d
  locs = act.locals
  vs = frame.vstack
  act.caller = JS_CUR_ACT[0]
  JS_CUR_ACT[0] = act
  # Main bytecode execution loop (outer begin/rescue covers resume + bytecode -> ZERO per-op setjmp!)
  r_kind = resume_kind
  r_val = resume_val
  handled_resume = resume_kind == nil
  while true
    begin
      if !handled_resume
        handled_resume = true
        if frame.closing != nil
          cl = frame.closing
          frame.closing = nil
          ck = cl[0]
          if ck == :throw
            if !js_sm_unwind_throw(frame, cl[1])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = cl[1]
              return nil
          else
            js_throw(resume_val) if resume_kind == :throw
            js_throw_type("Iterator result " + js_to_display_short(resume_val) + " is not an object") if !js_object?(resume_val)
            if ck == :return
              if !js_sm_unwind_return(frame, cl[1])
                if frame.closing != nil
                  JS_CUR_ACT[0] = act.caller
                  return nil
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :return
                frame.result_val = cl[1]
                return nil
            elsif ck == :jump
              js_sm_unwind_jmp(frame, cl[1], cl[2], cl[3], cl[4])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
        elsif frame.disp_awaiting
          frame.disp_awaiting = false
          if resume_kind == :throw
            ds = frame.temps[frame.temps.size - 1]
            if ds[1]
              ds[2] = js_suppressed_error_new(resume_val, ds[2])
            else
              ds[1] = true
              ds[2] = resume_val
        elsif frame.ystar_rec != nil
          # Continuing SM_YIELD_STAR_STEP at frame.pc
          nil
        elsif frame.async_yield_phase == 1
          # Resumed from awaiting value inside async generator `yield v`
          frame.async_yield_phase = 0
          if resume_kind == :throw
            if !js_sm_unwind_throw(frame, resume_val)
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = resume_val
              return nil
          else
            frame.async_yield_phase = 2
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :yield
            frame.result_val = resume_val
            return nil
        elsif frame.async_yield_phase == 2
          # Resumed from yielding value inside async generator
          frame.async_yield_phase = 0
          if resume_kind == :next
            vs.push(resume_val)
          elsif resume_kind == :throw
            if !js_sm_unwind_throw(frame, resume_val)
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = resume_val
              return nil
          else
            # :return -> must await return value first (§27.6.3.4)
            frame.async_yield_phase = 3
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :await
            frame.result_val = resume_val
            return nil
        elsif frame.async_yield_phase == 3
          # Resumed from awaiting return value in async generator
          frame.async_yield_phase = 0
          if resume_kind == :throw
            if !js_sm_unwind_throw(frame, resume_val)
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = resume_val
              return nil
          else
            if !js_sm_unwind_return(frame, resume_val)
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :return
              frame.result_val = resume_val
              return nil
        elsif resume_kind == :next
          vs.push(resume_val)
        elsif resume_kind == :throw
          if !js_sm_unwind_throw(frame, resume_val)
            if frame.closing != nil
              JS_CUR_ACT[0] = act.caller
              return nil
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :throw
            frame.result_val = resume_val
            return nil
        else
          # :return (gen.return(v))
          if !js_sm_unwind_return(frame, resume_val)
            if frame.closing != nil
              JS_CUR_ACT[0] = act.caller
              return nil
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :return
            frame.result_val = resume_val
            return nil
      while true
        pc = frame.pc
        op = ops[pc]
        frame.pc = pc + 1
        # ---- Ultra-hot specialized local ops checked first! ----
        if op == SM_ADD_LOCAL_I32
          s_idx = ca[pc]
          v = vs.pop
          rv = wvalue_from_bits(sm_add_i32_bits(wvalue_bits(locs[s_idx]) ## i64, wvalue_bits(v) ## i64))
          if js_is_slow_bits(wvalue_bits(rv) ## i64) == 0
            locs[s_idx] = rv
          else
            locs[s_idx] = js_bitor(js_add(locs[s_idx], v), ~0.0)
        elsif op == SM_INC_LOCAL
          li = ca[pc]
          rv = wvalue_from_bits(sm_inc_f64_bits(wvalue_bits(locs[li]) ## i64))
          if js_is_slow_bits(wvalue_bits(rv) ## i64) == 0
            locs[li] = rv
          else
            locs[li] = js_inc(js_tonumeric(locs[li]), true)
        elsif op == SM_JGE_LOCAL
          i_idx = ca[pc]
          n_idx = cb[pc]
          end_pc = cc[pc]
          # Fast pure-LLVM inner loop when already resumed from empty microtask queue and Promise is pristine!
          if is_resumed && q != nil && q.head == q.tail && pc + 4 < code.len && ops[pc + 1] == SM_AWAIT_RESOLVE_LOCAL && ca[pc + 1] == i_idx && ops[pc + 2] == SM_ADD_LOCAL_I32 && ops[pc + 3] == SM_INC_LOCAL && ca[pc + 3] == i_idx && ops[pc + 4] == SM_JMP && ca[pc + 4] == pc
            r = js_realm()
            if js_promise_pristine?(r) && cb[pc + 1].value == r.promise_ctor
              if sm_run_acc_i32_loop(jit_arr_slots_ptr(wvalue_bits(locs) ## i64), i_idx ## i64, n_idx ## i64, ca[pc + 2] ## i64) != 0
                frame.pc = end_pc
                next
          cmp = sm_lt_f64_bits(wvalue_bits(locs[i_idx]) ## i64, wvalue_bits(locs[n_idx]) ## i64)
          if cmp == 0
            frame.pc = end_pc
          elsif cmp < 0
            frame.pc = end_pc if !js_lt(locs[i_idx], locs[n_idx])
        elsif op == SM_JMP
          frame.pc = ca[pc]
        elsif op == SM_AWAIT_RESOLVE_LOCAL
          # Fast zero-Promise `await Promise.resolve(local_var)`!
          r = js_realm()
          cell = cb[pc]
          if q != nil && js_promise_pristine?(r) && cell.value == r.promise_ctor
            v = locs[ca[pc]]
            if !js_object?(v)
              # If already resumed from microtask checkpoint AND queue is empty, continue directly!
              if is_resumed && q.head == q.tail
                vs.push(v)
                next
              JS_CUR_ACT[0] = act.caller
              frame.state = :suspended
              q.push_async(frame, v, 0)
              frame.result_kind = :enqueued
              return nil
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :await
            frame.result_val = js_promise_resolve_value(v)
            return nil
          # Slow fallback (Promise or Promise.resolve was monkey-patched!)
          v = wk_ev(cc[pc], act)
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :await
          frame.result_val = v
          return nil
        elsif op == SM_LOCAL_CONST
          locs[ca[pc]] = cb[pc]
        elsif op == SM_LOCAL_GET
          vs.push(locs[ca[pc]])
        elsif op == SM_LOCAL_SET
          locs[ca[pc]] = vs.pop
        elsif op == SM_RETURN_LOCAL
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :return
          frame.result_val = locs[ca[pc]]
          return nil
        # ---- General opcodes ----
        elsif op == SM_STMT
          wk_ex(ca[pc], act)
        elsif op == SM_EXPR
          vs.push(wk_ev(ca[pc], act))
        elsif op == SM_POP
          vs.pop
        elsif op == SM_DUP
          vs.push(vs[vs.size - 1])
        elsif op == SM_PUSH_CONST
          vs.push(ca[pc])
        elsif op == SM_JMP_FALSE
          frame.pc = ca[pc] if !js_truthy(vs.pop)
        elsif op == SM_JMP_TRUE
          frame.pc = ca[pc] if js_truthy(vs.pop)
        elsif op == SM_JMP_TRUTHY_KEEP
          if js_truthy(vs[vs.size - 1])
            frame.pc = ca[pc]
          else
            vs.pop
        elsif op == SM_JMP_FALSY_KEEP
          if !js_truthy(vs[vs.size - 1])
            frame.pc = ca[pc]
          else
            vs.pop
        elsif op == SM_JMP_NOT_NULLISH_KEEP
          if !js_nullish?(vs[vs.size - 1])
            frame.pc = ca[pc]
          else
            vs.pop
        elsif op == SM_AWAIT
          v = vs.pop
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :await
          frame.result_val = v
          return nil
        elsif op == SM_YIELD
          v = vs.pop
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :yield
          frame.result_val = v
          return nil
        elsif op == SM_ASYNC_YIELD
          v = vs.pop
          frame.async_yield_phase = 1
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :await
          frame.result_val = v
          return nil
        elsif op == SM_YIELD_STAR_INIT
          v = vs.pop
          if frame.async_gen != nil
            m = js_get_method(v, SYM_ASYNC_ITERATOR)
            if m != nil
              it = js_call_arr(m, v, JS_NO_ARGS)
              js_throw_type("Result of the Symbol.asyncIterator method is not an object") if !js_object?(it)
              rec = JS:IterRecord.new(it, jget(it, "next"))
            else
              rec = js_create_async_from_sync_iter(js_get_iterator(v, false))
            frame.ystar_rec = rec
            frame.ystar_phase = 0
          else
            rec = js_get_iterator(v)
            frame.ystar_rec = rec
            frame.ystar_phase = 0
          r_kind = :next
          r_val = nil
        elsif op == SM_YIELD_STAR_STEP
          rec = frame.ystar_rec
          if frame.async_gen != nil
            ph = frame.ystar_phase
            if ph == 0
              if r_kind == :next
                res = js_call_arr(rec.next_fn, rec.iterator, [r_val])
                frame.ystar_phase = 1
                frame.pc = pc
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :await
                frame.result_val = res
                return nil
              elsif r_kind == :throw
                th = js_get_method(rec.iterator, "throw")
                if th != nil
                  res = js_call_arr(th, rec.iterator, [r_val])
                  frame.ystar_phase = 1
                  frame.pc = pc
                  JS_CUR_ACT[0] = act.caller
                  frame.result_kind = :await
                  frame.result_val = res
                  return nil
                else
                  # AsyncIteratorClose(rec, NormalCompletion(unused)), then throw TypeError
                  rt = js_get_method(rec.iterator, "return")
                  if rt != nil
                    res = js_call_arr(rt, rec.iterator, JS_NO_ARGS)
                    frame.ystar_phase = 4
                    frame.pc = pc
                    JS_CUR_ACT[0] = act.caller
                    frame.result_kind = :await
                    frame.result_val = res
                    return nil
                  frame.ystar_rec = nil
                  frame.ystar_phase = 0
                  js_throw_type("The iterator does not provide a 'throw' method")
              else
                # r_kind == :return
                rt = js_get_method(rec.iterator, "return")
                if rt == nil
                  frame.ystar_phase = 3
                  frame.pc = pc
                  JS_CUR_ACT[0] = act.caller
                  frame.result_kind = :await
                  frame.result_val = r_val
                  return nil
                res = js_call_arr(rt, rec.iterator, [r_val])
                frame.ystar_phase = 2
                frame.pc = pc
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :await
                frame.result_val = res
                return nil
            elsif ph == 1
              frame.ystar_phase = 0
              if r_kind == :throw
                frame.ystar_rec = nil
                js_throw(r_val)
              js_throw_type("iterator result is not an object") if !js_object?(r_val)
              if js_truthy(jget(r_val, "done"))
                frame.ystar_rec = nil
                vs.push(jget(r_val, "value"))
              else
                yv = jget(r_val, "value")
                frame.ystar_phase = 5
                frame.pc = pc
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :yield
                frame.result_val = yv
                return nil
            elsif ph == 2
              frame.ystar_phase = 0
              if r_kind == :throw
                frame.ystar_rec = nil
                js_throw(r_val)
              js_throw_type("iterator result is not an object") if !js_object?(r_val)
              if js_truthy(jget(r_val, "done"))
                rv = jget(r_val, "value")
                frame.ystar_rec = nil
                if !js_sm_unwind_return(frame, rv)
                  if frame.closing != nil
                    JS_CUR_ACT[0] = act.caller
                    return nil
                  JS_CUR_ACT[0] = act.caller
                  frame.result_kind = :return
                  frame.result_val = rv
                  return nil
              else
                yv = jget(r_val, "value")
                frame.ystar_phase = 5
                frame.pc = pc
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :yield
                frame.result_val = yv
                return nil
            elsif ph == 3
              frame.ystar_phase = 0
              frame.ystar_rec = nil
              if r_kind == :throw
                js_throw(r_val)
              if !js_sm_unwind_return(frame, r_val)
                if frame.closing != nil
                  JS_CUR_ACT[0] = act.caller
                  return nil
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :return
                frame.result_val = r_val
                return nil
            elsif ph == 4
              frame.ystar_phase = 0
              frame.ystar_rec = nil
              if r_kind == :throw
                js_throw(r_val)
              js_throw_type("iterator result is not an object") if !js_object?(r_val)
              js_throw_type("The iterator does not provide a 'throw' method")
            elsif ph == 5
              # Resumed from AsyncGeneratorYield inside yield* (§27.6.3.7 AsyncGeneratorUnwrapYieldResumption)
              if r_kind == :return
                frame.ystar_phase = 6
                frame.pc = pc
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :await
                frame.result_val = r_val
                return nil
              frame.ystar_phase = 0
              frame.pc = pc
            else
              # ph == 6: awaited return resumption value in AsyncGeneratorUnwrapYieldResumption
              frame.ystar_phase = 0
              frame.pc = pc
              if r_kind != :throw
                r_kind = :return
            next
          res = nil
          if r_kind == :next
            res = js_call_arr(rec.next_fn, rec.iterator, [r_val])
          elsif r_kind == :throw
            th = js_get_method(rec.iterator, "throw")
            if th == nil
              frame.ystar_rec = nil
              js_iter_close(rec)
              js_throw_type("The iterator does not provide a 'throw' method")
            res = js_call_arr(th, rec.iterator, [r_val])
          else
            rt = js_get_method(rec.iterator, "return")
            if rt == nil
              frame.ystar_rec = nil
              if !js_sm_unwind_return(frame, r_val)
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :return
                frame.result_val = r_val
                return nil
              next
            res = js_call_arr(rt, rec.iterator, [r_val])
            js_throw_type("iterator result is not an object") if !js_object?(res)
            if js_truthy(jget(res, "done"))
              frame.ystar_rec = nil
              rv = jget(res, "value")
              if !js_sm_unwind_return(frame, rv)
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :return
                frame.result_val = rv
                return nil
              next
          js_throw_type("iterator result is not an object") if !js_object?(res)
          if js_truthy(jget(res, "done")) && r_kind != :return
            frame.ystar_rec = nil
            vs.push(jget(res, "value"))
          else
            # Keep PC at SM_YIELD_STAR_STEP so resume re-enters here!
            frame.pc = pc
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :yield_raw
            frame.result_val = res
            return nil
        elsif op == SM_RETURN
          v = vs.pop
          if !js_sm_unwind_return(frame, v)
            if frame.closing != nil
              JS_CUR_ACT[0] = act.caller
              return nil
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :return
            frame.result_val = v
            return nil
        elsif op == SM_THROW
          v = vs.pop
          if !js_sm_unwind_throw(frame, v)
            if frame.closing != nil
              JS_CUR_ACT[0] = act.caller
              return nil
            JS_CUR_ACT[0] = act.caller
            frame.result_kind = :throw
            frame.result_val = v
            return nil
        elsif op == SM_TRY_PUSH
          frame.tries.push([ca[pc], cb[pc], vs.size, act.env, cc[pc], cd[pc], frame.env_stack.size, frame.iters.size, frame.temps.size, frame.pendings.size])
        elsif op == SM_TRY_POP
          frame.tries.pop
        elsif op == SM_FINALLY_ENTER
          h = frame.tries.pop
          act.env = h[3]
          frame.pendings.push([:none, nil, 0, 0, 0])
          frame.pc = h[1]
        elsif op == SM_FINALLY_END
          pend = frame.pendings.pop
          pk = pend[0]
          if pk == :throw
            if !js_sm_unwind_throw(frame, pend[1])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = pend[1]
              return nil
          elsif pk == :return
            if !js_sm_unwind_return(frame, pend[1])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :return
              frame.result_val = pend[1]
              return nil
          elsif pk == :jump
            js_sm_unwind_jmp(frame, pend[1], pend[2], pend[3], pend[4])
            if frame.closing != nil
              JS_CUR_ACT[0] = act.caller
              return nil
        elsif op == SM_UNWIND_JMP
          js_sm_unwind_jmp(frame, ca[pc], cb[pc], cc[pc], cd[pc])
          if frame.closing != nil
            JS_CUR_ACT[0] = act.caller
            return nil
        elsif op == SM_SCOPE_ENTER
          frame.env_stack.push(act.env)
          wk_scope_enter(ca[pc], act)
        elsif op == SM_SCOPE_EXIT
          act.env = frame.env_stack.pop
        elsif op == SM_ENV_SAVE
          frame.env_stack.push(act.env)
        elsif op == SM_ENV_RESET
          act.env = frame.env_stack[frame.env_stack.size - 1]
        elsif op == SM_ENV_COPY
          act.env = js_env_copy(act.env)
        elsif op == SM_HOIST_FNS
          wk_hoist_functions(ca[pc], act)
        elsif op == SM_BINOP
          rhs = vs.pop
          lhs = vs.pop
          vs.push(wk_binop(ca[pc], lhs, rhs))
        elsif op == SM_PRIV_IN
          o = vs.pop
          js_throw_type("Cannot use 'in' operator to search for a private field in a non-object") if !js_object?(o)
          vs.push(o.is_a?(JS:Base) && o.priv_has?(wk_read_ref(ca[pc], act)))
        elsif op == SM_UNARY
          v = vs.pop
          uop = ca[pc]
          if uop == "!"
            vs.push(!js_truthy(v))
          elsif uop == "-"
            vs.push(js_neg(v))
          elsif uop == "+"
            vs.push(js_plus(v))
          elsif uop == "~"
            vs.push(js_bitnot(v))
          elsif uop == "typeof"
            vs.push(js_typeof(v))
          else
            vs.push(nil)
        elsif op == SM_READ_REF
          vs.push(wk_read_ref(ca[pc], act))
        elsif op == SM_ASSIGN_REF
          v = vs[vs.size - 1]
          wk_write_ref(ca[pc], v, act, cb[pc])
        elsif op == SM_ASSIGN_OP_REF
          rhs = vs.pop
          lhs = vs.pop
          nv = wk_binop(cb[pc], lhs, rhs)
          wk_write_ref(ca[pc], nv, act, false)
          vs.push(nv)
        elsif op == SM_BIND_PAT
          wk_bind(ca[pc], vs.pop, act, cb[pc])
        elsif op == SM_GET_PROP
          vs.push(jget(vs.pop, ca[pc]))
        elsif op == SM_GET_COMP
          k = vs.pop
          o = vs.pop
          vs.push(js_getv(o, k))
        elsif op == SM_SET_PROP
          v = vs.pop
          o = vs.pop
          js_setv(o, ca[pc], v, cb[pc])
          vs.push(v)
        elsif op == SM_SET_COMP
          v = vs.pop
          k = vs.pop
          o = vs.pop
          js_setv(o, k, v, ca[pc])
          vs.push(v)
        elsif op == SM_ASSIGN_OP_PROP
          rhs = vs.pop
          o = vs.pop
          nv = wk_binop(cb[pc], jget(o, ca[pc]), rhs)
          js_setv(o, ca[pc], nv, cc[pc])
          vs.push(nv)
        elsif op == SM_ASSIGN_OP_COMP
          rhs = vs.pop
          k = vs.pop
          o = vs.pop
          nv = wk_binop(ca[pc], js_getv(o, k), rhs)
          js_setv(o, k, nv, cb[pc])
          vs.push(nv)
        elsif op == SM_DELETE_PROP
          o = vs.pop
          vs.push(js_delete(o, ca[pc], cb[pc]))
        elsif op == SM_DELETE_COMP
          k = vs.pop
          o = vs.pop
          vs.push(js_delete(o, k, ca[pc]))
        elsif op == SM_CALL
          argc = ca[pc]
          sp = cb[pc]
          raw = Array.new(argc, nil)
          j = argc - 1
          while j >= 0
            raw[j] = vs.pop
            j -= 1
          fn = vs.pop
          this_v = vs.pop
          if sp != nil
            args = []
            j = 0
            while j < argc
              if sp[j]
                js_append_iterable(args, raw[j])
              else
                args.push(raw[j])
              j += 1
          else
            args = raw
          vs.push(js_call_arr(fn, this_v, args))
        elsif op == SM_NEW
          argc = ca[pc]
          sp = cb[pc]
          raw = Array.new(argc, nil)
          j = argc - 1
          while j >= 0
            raw[j] = vs.pop
            j -= 1
          fn = vs.pop
          if sp != nil
            args = []
            j = 0
            while j < argc
              if sp[j]
                js_append_iterable(args, raw[j])
              else
                args.push(raw[j])
              j += 1
          else
            args = raw
          vs.push(js_construct(fn, args, nil))
        elsif op == SM_ARRAY
          cnt = ca[pc]
          sp = cb[pc]
          raw = Array.new(cnt, nil)
          j = cnt - 1
          while j >= 0
            raw[j] = vs.pop
            j -= 1
          out = []
          j = 0
          while j < cnt
            if sp[j]
              js_append_iterable(out, raw[j])
            else
              out.push(raw[j])
            j += 1
          vs.push(js_mark_array(out))
        elsif op == SM_OBJECT
          specs = ca[pc]
          n = specs.size
          vals = Array.new(n, nil)
          keys = Array.new(n, nil)
          j = n - 1
          while j >= 0
            sp = specs[j]
            vals[j] = vs.pop
            keys[j] = vs.pop if sp[0] == :comp
            j -= 1
          obj = js_realm().new_object
          j = 0
          while j < n
            sp = specs[j]
            if sp[0] == :spread
              js_copy_data_properties(obj, vals[j], [])
            else
              pk = sp[0] == :comp ? js_to_property_key(keys[j]) : sp[2]
              if sp[1] == "get"
                obj.define_accessor(pk, vals[j], obj.setter_of(pk), ATTR_E + ATTR_C)
              elsif sp[1] == "set"
                obj.define_accessor(pk, obj.getter_of(pk), vals[j], ATTR_E + ATTR_C)
              else
                obj.define(pk, vals[j], ATTR_ALL)
            j += 1
          vs.push(obj)
        elsif op == SM_TEMPLATE
          qs = ca[pc]
          ne = qs.size - 1
          evs = Array.new(ne, nil)
          j = ne - 1
          while j >= 0
            evs[j] = vs.pop
            j -= 1
          sb = StringBuffer()
          j = 0
          while j < qs.size
            sb.append(qs[j])
            sb.append(js_template_string(evs[j])) if j < ne
            j += 1
          s_out = sb.to_s
          ccall("w_value_free_w", sb)
          vs.push(s_out)
        elsif op == SM_FOR_IN_INIT
          obj = vs.pop
          frame.iters.push([:in, obj, js_for_in_keys(obj), 0])
        elsif op == SM_FOR_IN_NEXT
          it = frame.iters[frame.iters.size - 1]
          obj = it[1]
          ks = it[2]
          idx = it[3]
          found = false
          while idx < ks.size
            k = ks[idx]
            idx += 1
            if !js_object?(obj) || jhas_property?(obj, k)
              it[3] = idx
              vs.push(k)
              found = true
              break
          if !found
            frame.iters.pop
            frame.pc = ca[pc]
        elsif op == SM_FOR_OF_INIT
          rec = js_get_iterator(vs.pop)
          frame.iters.push([:of, rec])
        elsif op == SM_FOR_OF_NEXT
          it = frame.iters[frame.iters.size - 1]
          rec = it[1]
          v = js_iter_step(rec)
          if v == JS_ITER_DONE
            frame.iters.pop
            frame.pc = ca[pc]
          else
            vs.push(v)
        elsif op == SM_FOR_OF_CLOSE
          it = frame.iters.pop
          if js_sm_close_iter(frame, it, false, [:close_direct])
            JS_CUR_ACT[0] = act.caller
            return nil
        elsif op == SM_FOR_AWAIT_INIT
          o = vs.pop
          m = js_get_method(o, SYM_ASYNC_ITERATOR)
          if m != nil
            it = js_call_arr(m, o, JS_NO_ARGS)
            js_throw_type("Result of the Symbol.asyncIterator method is not an object") if !js_object?(it)
            rec = JS:IterRecord.new(it, jget(it, "next"))
          else
            rec = js_create_async_from_sync_iter(js_get_iterator(o, false))
          frame.iters.push([:await, rec])
        elsif op == SM_FOR_AWAIT_NEXT
          it = frame.iters[frame.iters.size - 1]
          rec = it[1]
          rec.done = true
          r = js_call_arr(rec.next_fn, rec.iterator, JS_NO_ARGS)
          JS_CUR_ACT[0] = act.caller
          frame.result_kind = :await
          frame.result_val = r
          return nil
        elsif op == SM_FOR_AWAIT_STEP
          it = frame.iters[frame.iters.size - 1]
          rec = it[1]
          r = vs.pop
          js_throw_type("Iterator result " + js_to_display_short(r) + " is not an object") if !js_object?(r)
          if js_truthy(jget(r, "done"))
            rec.done = true
            frame.iters.pop
            frame.pc = ca[pc]
          else
            v = jget(r, "value")
            rec.done = false
            vs.push(v)
        elsif op == SM_PRIV_GET
          vs.push(js_priv_get(vs.pop, wk_read_ref(ca[pc], act)))
        elsif op == SM_PRIV_SET
          v = vs.pop
          o = vs.pop
          js_priv_set(o, wk_read_ref(ca[pc], act), v)
          vs.push(v)
        elsif op == SM_PRIV_ASSIGN_OP
          rhs = vs.pop
          o = vs.pop
          pn = wk_read_ref(ca[pc], act)
          nv = wk_binop(cb[pc], js_priv_get(o, pn), rhs)
          js_priv_set(o, pn, nv)
          vs.push(nv)
        elsif op == SM_WITH_ENTER
          o = js_to_object(vs.pop)
          frame.env_stack.push(act.env)
          act.env = JS:WithEnv.new(act.env, o)
        elsif op == SM_SCOPE_ENTER_NOSAVE
          wk_scope_enter(ca[pc], act)
        elsif op == SM_TO_PROP_KEY
          vs.push(js_to_property_key(vs.pop))
        elsif op == SM_JMP_NOT_UNDEF
          if vs[vs.size - 1] != nil
            frame.pc = ca[pc]
          else
            vs.pop
        elsif op == SM_TEMP_PUSH
          frame.temps.push(vs.pop)
        elsif op == SM_TEMP_GET
          vs.push(frame.temps[frame.temps.size - 1 - ca[pc]])
        elsif op == SM_TEMP_POP
          frame.temps.pop
        elsif op == SM_CHECK_OBJ_COERCIBLE
          v = vs[vs.size - 1]
          js_throw_type("Cannot destructure '" + js_to_display(v) + "' as it is " + (v == nil ? "undefined" : "null") + ".") if js_nullish?(v)
        elsif op == SM_OBJ_REST_INIT
          frame.temps.push([])
        elsif op == SM_OBJ_REST_EXCLUDE
          frame.temps[frame.temps.size - 1].push(vs[vs.size - 1])
        elsif op == SM_OBJ_REST_BUILD
          used = frame.temps.pop
          v = frame.temps[frame.temps.size - 1]
          o = js_new_object(js_realm().object_proto)
          src = js_object?(v) ? v : js_realm().wrap_primitive(v)
          ks = jown_keys(src)
          kj = 0
          while kj < ks.size
            kk = ks[kj]
            if !used.include?(kk) && jenumerable?(src, kk)
              o.define(kk, jget(src, kk, v), ATTR_DEFAULT)
            kj += 1
          vs.push(o)
        elsif op == SM_ITER_STEP_DSTR
          it = frame.iters[frame.iters.size - 1]
          rec = it[1]
          if rec.done
            vs.push(nil)
          else
            x = js_iter_step(rec)
            vs.push(x == JS_ITER_DONE ? nil : x)
        elsif op == SM_ITER_REST_DSTR
          it = frame.iters[frame.iters.size - 1]
          rec = it[1]
          rest = []
          while !rec.done
            y = js_iter_step(rec)
            rest.push(y) if y != JS_ITER_DONE
          vs.push(js_mark_array(rest))
        elsif op == SM_GET_VALUE
          k = vs.pop
          o = vs.pop
          vs.push(js_get_value(o, k))
        elsif op == SM_SWAP
          top = vs.pop
          sec = vs.pop
          vs.push(top)
          vs.push(sec)
        elsif op == SM_JMP_NULLISH_SHORT
          if js_nullish?(vs[vs.size - 1])
            vs.pop
            vs.push(nil)
            frame.pc = ca[pc]
        elsif op == SM_JMP_NULLISH_CALL_SHORT
          if js_nullish?(vs[vs.size - 1])
            vs.pop
            vs.pop
            vs.push(nil)
            frame.pc = ca[pc]
        elsif op == SM_CLASS_INIT_PRIVS
          cs = ca[pc]
          cs.order.each ->(b) wk_write(b, JS:PrivateName.new(b.name.slice(1, b.name.size - 1)), act) if b.kind == :private
        elsif op == SM_CLASS_HEAD
          n = ca[pc]
          r = js_realm()
          proto_parent = r.object_proto
          ctor_parent = r.function_proto
          if cb[pc]
            sup = vs.pop
            if sup == JS_NULL
              proto_parent = nil
            else
              js_throw_type("Class extends value " + js_to_display_short(sup) + " is not a constructor or null") if !js_is_constructor?(sup)
              pp = jget(sup, "prototype")
              js_throw_type("Class extends value does not have valid prototype property " + js_to_display_short(pp)) if !js_object?(pp) && pp != JS_NULL
              proto_parent = pp == JS_NULL ? nil : pp
              ctor_parent = sup
          proto = js_new_object(proto_parent)
          cjf = n.d.x
          f = js_method_closure(wk_code(cjf), wk_env_for(cjf, act), proto)
          f.set_prototype_of(ctor_parent) if ctor_parent != r.function_proto
          f.define("length", cjf.nparams.to_f, ATTR_C)
          f.define("name", cjf.name.to_s, ATTR_C)
          f.define("prototype", proto, 0)
          proto.define("constructor", f, ATTR_W + ATTR_C)
          frame.temps.push([f, proto, [], [], []])
        elsif op == SM_CLASS_METHOD
          m = ca[pc]
          has_comp = cb[pc]
          st = m.has?(F_STATIC)
          cst = frame.temps[frame.temps.size - 1]
          f = cst[0]
          proto = cst[1]
          privs = cst[3]
          target = st ? f : proto
          jf = m.b.x
          fo = js_method_closure(wk_code(jf), wk_env_for(jf, act), target)
          if m.a.kind == :private_name
            pn = wk_read_ref(m.a.x, act)
            if st
              if m.str == "method"
                f.priv_add_method(pn, fo)
              else
                f.priv_add_accessor(pn, m.str == "get" ? fo : nil, m.str == "set" ? fo : nil)
            else
              privs.push([pn, fo, m.str])
          else
            key = has_comp ? vs.pop : wk_prop_key(m.a)
            js_class_method(target, key, fo, m.str, has_comp)
        elsif op == SM_CLASS_FIELD
          m = ca[pc]
          has_comp = cb[pc]
          st = m.has?(F_STATIC)
          cst = frame.temps[frame.temps.size - 1]
          f = cst[0]
          proto = cst[1]
          fields = cst[2]
          privs = cst[3]
          statics = cst[4]
          is_priv = m.a.kind == :private_name
          key = is_priv ? wk_read_ref(m.a.x, act) : (has_comp ? vs.pop : wk_prop_key(m.a))
          init = m.x == nil ? nil : js_method_closure(wk_code(m.x), wk_env_for(m.x, act), st ? f : proto)
          if m.str == "accessor"
            dname = is_priv ? key.to_s : key
            storage_pn = JS:PrivateName.new(js_key_display(dname) + " (accessor storage)")
            get_fn = js_auto_accessor_get(storage_pn)
            set_fn = js_auto_accessor_set(storage_pn)
            js_set_fn_name(get_fn, dname, "get")
            js_set_fn_name(set_fn, dname, "set")
            if is_priv
              if st
                f.priv_add_accessor(key, get_fn, set_fn)
              else
                privs.push([key, get_fn, "get"])
                privs.push([key, set_fn, "set"])
            else
              js_class_method(st ? f : proto, key, get_fn, "get", has_comp)
              js_class_method(st ? f : proto, key, set_fn, "set", has_comp)
            if st
              statics.push([storage_pn, init, false])
            else
              fields.push([storage_pn, init])
          elsif st
            statics.push([key, init, false])
          else
            fields.push([key, init])
        elsif op == SM_CLASS_STATIC_BLOCK
          m = ca[pc]
          cst = frame.temps[frame.temps.size - 1]
          cst[4].push([nil, js_method_closure(wk_code(m.x), wk_env_for(m.x, act), cst[0]), true])
        elsif op == SM_CLASS_FINISH
          n = ca[pc]
          cst = frame.temps.pop
          f = cst[0]
          fields = cst[2]
          privs = cst[3]
          statics = cst[4]
          f.fields = fields if fields.size > 0
          f.privs = privs if privs.size > 0
          if n.str != nil
            wk_write(n.x.names[n.str], f, act)
          si = 0
          while si < statics.size
            se = statics[si]
            if se[2]
              js_call(se[1], f, 0, nil, nil, nil, nil, nil)
            else
              sv = se[1] == nil ? nil : js_call(se[1], f, 0, nil, nil, nil, nil, nil)
              if se[0].is_a?(JS:PrivateName)
                f.priv_add(se[0], sv)
              else
                jdefine_own_or_throw(f, se[0], sv)
            si += 1
          vs.push(f)
        elsif op == SM_SUPER_GET
          m = ca[pc]
          key = cb[pc] ? js_to_property_key(vs.pop) : m.b.str
          vs.push(wk_super_get_key(m, key, act))
        elsif op == SM_DISP_PUSH
          frame.disps.push(JS:DisposeCap.new)
          frame.tries.push([-1, ca[pc], vs.size, act.env, :dispose, nil, frame.env_stack.size, frame.iters.size, frame.temps.size, frame.pendings.size, frame.disps.size - 1])
        elsif op == SM_DISP_ADD
          js_add_disposable_resource(frame.disps[frame.disps.size - 1], vs[vs.size - 1], ca[pc] ? :async : :sync, false, nil)
        elsif op == SM_DISP_ENTER
          h = frame.tries.pop
          cap = frame.disps.pop
          act.env = h[3]
          frame.pendings.push([:none, nil, 0, 0, 0])
          frame.temps.push([cap, false, nil])
          frame.pc = ca[pc]
        elsif op == SM_DISP_STEP
          ds = frame.temps[frame.temps.size - 1]
          st = ds[0].stack
          suspended = false
          while st.size > 0
            res = st.pop
            call_res = nil
            threw = false
            threw_val = nil
            if res.method != nil
              begin
                call_res = js_call_arr(res.method, res.value, JS_NO_ARGS)
              rescue dex
                threw = true
                threw_val = js_error_value(dex)
            if threw
              if ds[1]
                ds[2] = js_suppressed_error_new(threw_val, ds[2])
              else
                ds[1] = true
                ds[2] = threw_val
              next
            if res.hint == :async
              frame.disp_awaiting = true
              frame.pc = pc
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :await
              frame.result_val = call_res
              suspended = true
              break
          return nil if suspended
          frame.temps.pop
          pend = frame.pendings.pop
          if ds[1]
            if !js_sm_unwind_throw(frame, ds[2])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
              JS_CUR_ACT[0] = act.caller
              frame.result_kind = :throw
              frame.result_val = ds[2]
              return nil
          else
            pk = pend[0]
            if pk == :throw
              if !js_sm_unwind_throw(frame, pend[1])
                if frame.closing != nil
                  JS_CUR_ACT[0] = act.caller
                  return nil
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :throw
                frame.result_val = pend[1]
                return nil
            elsif pk == :return
              if !js_sm_unwind_return(frame, pend[1])
                if frame.closing != nil
                  JS_CUR_ACT[0] = act.caller
                  return nil
                JS_CUR_ACT[0] = act.caller
                frame.result_kind = :return
                frame.result_val = pend[1]
                return nil
            elsif pk == :jump
              js_sm_unwind_jmp(frame, pend[1], pend[2], pend[3], pend[4])
              if frame.closing != nil
                JS_CUR_ACT[0] = act.caller
                return nil
        elsif op == SM_IMPORT_CALL
          opts_v = cb[pc] ? vs.pop : nil
          spec_v = vs.pop
          em = wk_enclosing_mod(act)
          ref_url = em != nil ? em.url : JS_CURRENT_URL[0]
          ph_s = ca[pc]
          phase = ph_s == "defer" ? :defer : (ph_s == "source" ? :source : :evaluation)
          vs.push(js_mod_dynamic_import(ref_url, spec_v, opts_v, phase))
        else
          js_throw(js_make_error("SyntaxError", "sm_coro: unknown op " + op.to_s))
    rescue ex
      JS_CUR_ACT[0] = act
      frame.ystar_rec = nil
      frame.ystar_phase = 0
      frame.async_yield_phase = 0
      frame.disp_awaiting = false
      frame.closing = nil
      ev = js_error_value(ex)
      if !js_sm_unwind_throw(frame, ev)
        if frame.closing != nil
          JS_CUR_ACT[0] = act.caller
          return nil
        JS_CUR_ACT[0] = act.caller
        frame.result_kind = :throw
        frame.result_val = ev
        return nil
  nil

# Close a popped iterator entry (`[:of, rec]` or `[:await, rec]`).
# Returns true if suspended awaiting AsyncIteratorClose (sets frame.closing, result_kind, result_val).
-> js_sm_close_iter(frame, it, is_throw, cont_action)
  kind = it[0]
  if kind == :of
    rec = it[1]
    if !rec.done
      if is_throw
        js_iter_close_quiet(rec)
      else
        js_iter_close(rec)
    return false
  if kind == :await
    rec = it[1]
    return false if rec.done
    rec.done = true
    if is_throw
      res = nil
      has_res = false
      begin
        rt = js_get_method(rec.iterator, "return")
        if rt != nil
          res = js_call_arr(rt, rec.iterator, JS_NO_ARGS)
          has_res = true
      rescue _ex
        has_res = false
      if has_res
        frame.closing = cont_action
        frame.result_kind = :await
        frame.result_val = res
        return true
      return false
    rt = js_get_method(rec.iterator, "return")
    return false if rt == nil
    res = js_call_arr(rt, rec.iterator, JS_NO_ARGS)
    frame.closing = cont_action
    frame.result_kind = :await
    frame.result_val = res
    return true
  false

# Unwind stackless handlers on throw(ev). Returns true if caught or entering finally, false if unhandled or async-closing.
-> js_sm_unwind_throw(frame, ev)
  act = frame.act
  vs = frame.vstack
  while frame.tries.size > 0
    h = frame.tries[frame.tries.size - 1]
    while frame.iters.size > h[7]
      it = frame.iters.pop
      return false if js_sm_close_iter(frame, it, true, [:throw, ev])
    frame.tries.pop
    catch_pc = h[0]
    fin_pc = h[1]
    while vs.size > h[2]
      vs.pop
    act.env = h[3]
    while frame.env_stack.size > h[6]
      frame.env_stack.pop
    while frame.temps.size > h[8]
      frame.temps.pop
    if catch_pc >= 0
      # If there's also a finally, keep a finally-only handler active during catch!
      if fin_pc >= 0
        frame.tries.push([-1, fin_pc, h[2], h[3], nil, nil, h[6], h[7], h[8], h[9]])
      while frame.pendings.size > h[9]
        frame.pendings.pop
      cs = h[4]
      if cs != nil
        frame.env_stack.push(act.env) if cs.has_env?
        wk_scope_enter(cs, act)
      pat = h[5]
      if pat != nil
        if pat.kind == :ident
          wk_write(cs.names[pat.str], ev, act)
        else
          wk_bind(pat, ev, act, true)
      frame.pc = catch_pc
      return true
    if fin_pc >= 0
      while frame.pendings.size > h[9]
        frame.pendings.pop
      if h[4] == :dispose
        cap = nil
        while frame.disps.size > h[10]
          cap = frame.disps.pop
        frame.pendings.push([:none, nil, 0, 0, 0])
        frame.temps.push([cap, true, ev])
        frame.pc = fin_pc
        return true
      frame.pendings.push([:throw, ev, 0, 0, 0])
      frame.pc = fin_pc
      return true
  # Close any remaining iterators before exiting with throw
  while frame.iters.size > 0
    it = frame.iters.pop
    return false if js_sm_close_iter(frame, it, true, [:throw, ev])
  false

# Unwind stackless handlers on return(rv). Returns true if entering a finally, false if ready to return or async-closing.
-> js_sm_unwind_return(frame, rv)
  act = frame.act
  vs = frame.vstack
  while frame.tries.size > 0
    h = frame.tries[frame.tries.size - 1]
    while frame.iters.size > h[7]
      it = frame.iters.pop
      return false if js_sm_close_iter(frame, it, false, [:return, rv])
    frame.tries.pop
    fin_pc = h[1]
    if fin_pc >= 0
      while vs.size > h[2]
        vs.pop
      act.env = h[3]
      while frame.env_stack.size > h[6]
        frame.env_stack.pop
      while frame.temps.size > h[8]
        frame.temps.pop
      while frame.pendings.size > h[9]
        frame.pendings.pop
      if h[4] == :dispose
        cap = nil
        while frame.disps.size > h[10]
          cap = frame.disps.pop
        frame.pendings.push([:return, rv, 0, 0, 0])
        frame.temps.push([cap, false, nil])
        frame.pc = fin_pc
        return true
      frame.pendings.push([:return, rv, 0, 0, 0])
      frame.pc = fin_pc
      return true
  while frame.iters.size > 0
    it = frame.iters.pop
    return false if js_sm_close_iter(frame, it, false, [:return, rv])
  false

# Unwind tries/finallys/envs/iters for break/continue across finally blocks.
-> js_sm_unwind_jmp(frame, target_pc, target_tdfd, target_ed, target_id)
  target_td = target_tdfd >> 16
  target_fd = target_tdfd & 65535
  act = frame.act
  vs = frame.vstack
  while frame.tries.size > target_td
    h = frame.tries[frame.tries.size - 1]
    while frame.iters.size > h[7]
      it = frame.iters.pop
      return nil if js_sm_close_iter(frame, it, false, [:jump, target_pc, target_tdfd, target_ed, target_id])
    frame.tries.pop
    if h[1] >= 0
      while vs.size > h[2]
        vs.pop
      act.env = h[3]
      while frame.env_stack.size > h[6]
        frame.env_stack.pop
      while frame.temps.size > h[8]
        frame.temps.pop
      while frame.pendings.size > h[9]
        frame.pendings.pop
      if h[4] == :dispose
        cap = nil
        while frame.disps.size > h[10]
          cap = frame.disps.pop
        frame.pendings.push([:jump, target_pc, target_tdfd, target_ed, target_id])
        frame.temps.push([cap, false, nil])
        frame.pc = h[1]
        return nil
      frame.pendings.push([:jump, target_pc, target_tdfd, target_ed, target_id])
      frame.pc = h[1]
      return nil
  while frame.pendings.size > target_fd
    frame.pendings.pop
  while frame.iters.size > target_id
    it = frame.iters.pop
    return nil if js_sm_close_iter(frame, it, false, [:jump, target_pc, target_tdfd, target_ed, target_id])
  while frame.env_stack.size > target_ed
    act.env = frame.env_stack.pop
  frame.pc = target_pc
  nil

# ---- Public Entry Points for Async Functions, Generators, and Async Generators ----

-> js_sm_call_suspendable(jf, f, this, argc, a0, a1, a2, a3, more)
  act = WkAct.new(jf, f, js_fenv(f), this, jf.nlocals)
  act.argc = argc
  act.args = more
  n = jf.node
  gen = n.has?(F_GENERATOR)
  asy = n.has?(F_ASYNC)
  sc = js_sm_compile(jf)
  if asy && !gen
    r = js_realm()
    prom = JS:Promise.new(r.promise_shape)
    frame = JS:SmFrame.new(sc, act)
    frame.promise = prom
    begin
      wk_prologue(jf, act, argc, a0, a1, a2, a3, more)
    rescue e
      js_promise_reject_fast(prom, js_error_value(e), r.jobs)
      return prom
    frame.state = :running
    js_sm_run(frame, nil, nil, r.jobs)
    js_sm_async_after(frame, r.jobs)
    return prom
  wk_prologue(jf, act, argc, a0, a1, a2, a3, more)
  frame = JS:SmFrame.new(sc, act)
  if gen && asy
    p = jget(f, "prototype")
    p = js_realm().intrinsic("%AsyncGeneratorPrototype%") if !js_object?(p)
    g = JS:AsyncGen.new(js_root_shape(p, SP_INLINE, SP_IBASE))
    g.frame = frame
    frame.async_gen = g
    return g
  p = jget(f, "prototype")
  p = js_realm().intrinsic("%GeneratorPrototype%") if !js_object?(p)
  g = JS:Generator.new(js_root_shape(p, SP_INLINE, SP_IBASE))
  g.frame = frame
  g

# After js_sm_run for an async function (or async generator!)
-> js_sm_async_after(frame, q)
  rk = frame.result_kind
  return nil if rk == :enqueued
  if frame.async_gen != nil
    js_sm_async_gen_after(frame.async_gen, frame, q)
    return nil
  if rk == :await
    frame.state = :suspended
    begin
      js_promise_attach_async(frame.result_val, frame, q)
    rescue ex
      frame.state = :running
      js_sm_run(frame, :throw, js_error_value(ex), q)
      js_sm_async_after(frame, q)
    return nil
  frame.state = :done
  prom = frame.promise
  frame.promise = nil
  if rk == :return
    rv = frame.result_val
    if !js_object?(rv)
      js_promise_fulfill_fast(prom, rv, q)
    else
      js_promise_resolve_with(prom, rv)
  else
    js_promise_reject_fast(prom, frame.result_val, q)
  nil

# Called directly from Realm#run_jobs for JOB_ASYNC (ZERO closures, ZERO setjmp!).
-> js_sm_async_resume(frame, val, is_throw, q)
  frame.state = :running
  js_sm_run(frame, is_throw != 0 ? :throw : :next, val, q, true)
  js_sm_async_after(frame, q)
  nil

-> js_sm_async_reject(frame, err)
  if frame.async_gen != nil
    g = frame.async_gen
    frame.state = :done
    if g.queue.size > 0
      req = g.queue.shift
      g.busy = false
      js_promise_reject(req[2], err)
      js_sm_async_gen_drain(g)
    return nil
  frame.state = :done
  prom = frame.promise
  frame.promise = nil
  js_promise_reject(prom, err) if prom != nil
  nil

# ---- Synchronous Generator resume ----

-> js_sm_gen_resume(g, kind, v)
  fr = g.frame
  st = fr.state
  js_throw_type("Generator is already running") if st == :running
  if st == :done
    js_throw(v) if kind == :throw
    return js_iter_result(kind == :return ? v : nil, true)
  if st == :start
    if kind == :return
      fr.state = :done
      return js_iter_result(v, true)
    if kind == :throw
      fr.state = :done
      js_throw(v)
    fr.state = :running
    js_sm_run(fr, nil, nil, nil)
  else
    fr.state = :running
    js_sm_run(fr, kind, v, nil)
  rk = fr.result_kind
  if rk == :yield
    fr.state = :suspended
    return js_iter_result(fr.result_val, false)
  if rk == :yield_raw
    fr.state = :suspended
    return fr.result_val
  fr.state = :done
  js_throw(fr.result_val) if rk == :throw
  js_iter_result(fr.result_val, true)

# ---- Async Generator queue ----

-> js_sm_async_gen_enqueue(g, kind, v)
  r = js_realm()
  prom = JS:Promise.new(r.promise_shape)
  if !g.is_a?(JS:AsyncGen)
    js_promise_reject_fast(prom, js_make_error("TypeError", "not an async generator"), r.jobs)
    return prom
  g.queue.push([kind, v, prom])
  js_sm_async_gen_drain(g) if !g.busy
  prom

-> js_sm_async_gen_drain(g)
  fr = g.frame
  q = js_realm().jobs
  while g.queue.size > 0 && !g.busy
    req = g.queue[0]
    kind = req[0]
    v = req[1]
    if fr.state == :done || (fr.state == :start && kind != :next)
      fr.state = :done
      if kind == :return
        # §27.6.3.6 AsyncGeneratorAwaitReturn: await v while busy before settling req[2]!
        g.busy = true
        pw = nil
        threw = false
        err = nil
        begin
          pw = js_promise_resolve_value(v)
        rescue ex
          threw = true
          err = js_error_value(ex)
        if threw
          g.queue.shift
          g.busy = false
          js_promise_reject_fast(req[2], err, q)
        else
          on_f = ->(av)
            g.queue.shift
            g.busy = false
            js_promise_fulfill_fast(req[2], js_iter_result(av, true), js_realm().jobs)
            js_sm_async_gen_drain(g)
          on_r = ->(ev)
            g.queue.shift
            g.busy = false
            js_promise_reject_fast(req[2], ev, js_realm().jobs)
            js_sm_async_gen_drain(g)
          rf = JS:Reaction.new(nil, :fulfill, on_f)
          rf.keep = g
          rr = JS:Reaction.new(nil, :reject, on_r)
          rr.keep = g
          js_perform_then(pw, rf, rr)
          return nil
      else
        g.queue.shift
        if kind == :throw
          js_promise_reject_fast(req[2], v, q)
        else
          js_promise_fulfill_fast(req[2], js_iter_result(nil, true), q)
    else
      g.busy = true
      first = fr.state == :start
      fr.state = :running
      js_sm_run(fr, first ? nil : kind, first ? nil : v, q)
      js_sm_async_gen_after(g, fr, q)
  nil

-> js_sm_async_gen_after(g, fr, q)
  rk = fr.result_kind
  if rk == :await
    fr.state = :suspended
    begin
      js_promise_attach_async(fr.result_val, fr, q)
    rescue ex
      fr.state = :running
      js_sm_run(fr, :throw, js_error_value(ex), q)
      js_sm_async_gen_after(g, fr, q)
    return nil
  req = g.queue.shift
  g.busy = false
  if rk == :yield
    fr.state = :suspended
    js_promise_fulfill_fast(req[2], js_iter_result(fr.result_val, false), q)
  elsif rk == :yield_raw
    fr.state = :suspended
    js_promise_fulfill_fast(req[2], fr.result_val, q)
  elsif rk == :return
    fr.state = :done
    js_promise_fulfill_fast(req[2], js_iter_result(fr.result_val, true), q)
  else
    fr.state = :done
    js_promise_reject_fast(req[2], fr.result_val, q)
  js_sm_async_gen_drain(g)
  nil
