# translate — JavaScript (a JsNode AST, analysed by analyze.w) to Tungsten AST.
#
#   t = JsTranslator.new(analysis)
#   nodes = t.program()          # top-level Tungsten AST nodes for the compiled program
#   t.ic_words                   # size of the JS_IC table the program must declare
#
# Every JS function becomes `jsd_N(fe, this, argc, a0, a1, a2, a3, more)`: fe is its
# captured environment (a JS:Env, the single captured value, or nil). A function with
# an object also gets the generic entry `jsf_N(f, …)`, which reads f's @env and calls
# jsd_N; js_dispatch maps a JS:Code's index to it. Call-only functions and IIFEs are
# called through jsd_N directly and never get an object (PLAN.md 3.9).
#
# Control flow: one Tungsten `while` per JS loop, switch or labelled block. A break or
# continue that must leave more than one of them sets a flag local and breaks; each
# enclosing while checks the flag on the way out.

use build
use ../analyze

JT_OPS = {"+" => "js_add", "-" => "js_sub", "*" => "js_mul", "/" => "js_div", "%" => "js_mod", "**" => "js_pow", "<" => "js_lt", ">" => "js_gt", "<=" => "js_le", ">=" => "js_ge", "==" => "js_eq", "===" => "js_seq", "|" => "js_bitor", "&" => "js_bitand", "^" => "js_bitxor", "<<" => "js_shl", ">>" => "js_sar", ">>>" => "js_shr", "instanceof" => "js_instanceof", "in" => "js_in"}

+ JtFrame
  rw :kind, :labels, :id, :flag, :escapes, :continue_used, :first
  -> new(@kind, @labels, @id)
    @flag = nil
    @escapes = []
    @continue_used = false
    @first = nil

+ JsTranslator
  rw :an, :ic_words, :errors, :globals, :lexicals, :codes, :lit_shapes, :fn_count

  -> new(@an)
    @ic_words = 8
    @errors = []
    @globals = {}
    @glist = []
    @lexicals = {}
    @llist = []
    @codes = []
    @lit_shapes = []
    @f = nil
    @tmp = 0
    @frames = []
    @frame_ids = 0
    @fn_count = 0
    @defs = []
    @next_labels = []
    @var_names = nil
    @translated = 0
    @hoisted = {}

  # ---- program ----

  # The program's top-level nodes (after the runtime): realm, cells, codes, functions,
  # the dispatcher and the run of the script.
  # partial: functions the slice cannot compile (or past limit) become stubs that would
  # run in tier 0, instead of failing the program (the scale check; units later).
  -> program(partial = false, limit = -1)
    fs = @an.funcs
    i = 0
    while i < fs.size
      f = fs[i]
      if f.unsupported != nil
        @errors.push([f.index, f.unsupported])
      i += 1
    return nil if @errors.size > 0 && !partial
    @translated = 0
    i = 0
    while i < fs.size
      f = fs[i]
      if partial && (f.unsupported != nil || (limit >= 0 && @translated >= limit && !f.script))
        @defs.push(stub(f))
      else
        nerr = @errors.size
        nd = @defs.size
        tr_function(f)
        if partial && @errors.size > nerr
          while @defs.size > nd
            @defs.pop
          @defs.push(stub(f))
        else
          @translated += 1
      i += 1
    out = []
    out.push(ta_set("JSR", ta_call("js_new_realm", [])))
    i = 0
    while i < @glist.size
      out.push(ta_set("JSG_" + i.to_s, ta_call("js_gcell", [ta_str(@glist[i])])))
      i += 1
    i = 0
    while i < @llist.size
      out.push(ta_set("JSL_" + i.to_s, ta_call("js_lcell", [ta_str(@llist[i])])))
      i += 1
    i = 0
    while i < fs.size
      f = fs[i]
      flags = (f.strict ? 1 : 0) + (f.arrow ? 2 : 0) + ((f.arrow || f.script) ? 0 : 8)
      out.push(ta_set("JSC_" + i.to_s, ta_send(ta_var("JS:Code"), "new", [ta_str(f.name), ta_int(f.nparams), ta_int(i), ta_int(flags)])))
      i += 1
    i = 0
    while i < @lit_shapes.size
      ks = []
      @lit_shapes[i].each ->(k) ks.push(ta_str(k))
      out.push(ta_set("JSS_" + i.to_s, ta_call("js_lit_shape", [ta_array(ks)])))
      i += 1
    out.push(dispatcher())
    @defs.each ->(d) out.push(d)
    run = ta_call("jsd_0", [ta_nil, ta_nil, ta_int(0), ta_nil, ta_nil, ta_nil, ta_nil, ta_nil])
    out.push(ta_begin([run], "uncaught", [ta_call("js_report_uncaught", [ta_var("uncaught")])]))
    out.push(ta_call("js_finish", []))
    out

  -> translated
    @translated

  # A function left to tier 0: entries that exist but do not run compiled code.
  -> stub(f)
    body = [ta_call("js_tier0_only", [ta_int(f.index)])]
    if !f.script && f.fclass == :escaping
      @defs.push(ta_def("jsf_" + f.index.to_s, ["f", "this", "argc", "a0", "a1", "a2", "a3", "more"], body))
    ta_def("jsd_" + f.index.to_s, ["fe", "this", "argc", "a0", "a1", "a2", "a3", "more"], body)

  -> dispatcher
    arms = []
    fs = @an.funcs
    i = 0
    while i < fs.size
      if fs[i].fclass == :escaping && !fs[i].script
        arms.push([ta_int(i), [ta_call("jsf_" + i.to_s, entry_args("f"))]])
      i += 1
    body = arms.size == 0 ? [ta_nil] : [ta_case(ta_var("i"), arms, [ta_nil])]
    ta_def("js_dispatch", ["i", "f", "this", "argc", "a0", "a1", "a2", "a3", "more"], body)

  -> entry_args(first)
    [ta_var(first), ta_var("this"), ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")]

  # ---- names ----

  -> gcell(name)
    i = @globals[name]
    if i == nil
      i = @glist.size
      @globals[name] = i
      @glist.push(name)
    ta_var("JSG_" + i.to_s)

  -> lcell(name)
    i = @lexicals[name]
    if i == nil
      i = @llist.size
      @lexicals[name] = i
      @llist.push(name)
    ta_var("JSL_" + i.to_s)

  -> cell_of(b)
    b.kind == :lexical ? lcell(b.name) : gcell(b.name)

  -> local_name(b)
    "l" + b.id.to_s

  -> env_name(sc)
    "e" + sc.id.to_s

  -> tmp
    @tmp += 1
    "t" + @tmp.to_s

  # n inline-cache sites (4 words each) at once; returns the first word's index.
  -> site(n)
    k = @ic_words
    @ic_words += 4 * n
    k

  # ---- functions ----

  -> tr_function(f)
    @f = f
    @tmp = 0
    @frames = []
    n = f.node
    body = []
    sc = f.scope
    if f.script
      body = body + script_prologue(f)
    else
      if f.uses_this && !f.strict && !f.arrow
        body.push(ta_set("this", ta_call("js_sloppy_this", [ta_var("this")])))
      body = body + scope_entry(sc)
      i = 0
      while i < f.params.size
        p = f.params[i]
        v = i < 4 ? ta_var("a" + i.to_s) : ta_if(ta_send(ta_var("argc"), ">", [ta_int(i)]), [ta_send(ta_var("more"), "\[]", [ta_int(i)])], [ta_nil])
        body.push(write_binding(p, v, sc))
        i += 1
      if f.this_binding != nil && f.this_binding.in_env?
        body.push(write_binding(f.this_binding, ta_var("this"), sc))
      body = body + hoist_vars(sc)
    if f.arrow && n.has?(F_EXPR_BODY)
      body.push(ta_return(tr_expr(n.b, sc)))
    else
      stmts = f.script ? n.list : n.b
      body = body + hoist_functions(stmts, f.body_scope)
      body = body + tr_stmts(stmts, f.body_scope)
      body.push(ta_return(ta_nil))
    @defs.push(ta_def("jsd_" + f.index.to_s, ["fe", "this", "argc", "a0", "a1", "a2", "a3", "more"], body))
    if !f.script && f.fclass == :escaping
      @defs.push(ta_def("jsf_" + f.index.to_s, ["f", "this", "argc", "a0", "a1", "a2", "a3", "more"], [ta_call("jsd_" + f.index.to_s, [ta_call("js_fenv", [ta_var("f")]), ta_var("this"), ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")])]))
    nil

  # Script top level: its var names become properties of the global object.
  -> script_prologue(f)
    out = []
    vn = @an.var_names(@an.program.list, [], f.strict, true)
    i = 0
    while i < vn.size
      out.push(ta_call("js_gdeclare", [gcell(vn[i]), ta_nil, ta_bool(false)]))
      i += 1
    out

  # Entering a scope: its environment record, when a closure captures any of its
  # bindings.
  -> scope_entry(sc)
    return [] if !sc.has_env?
    up = current_env(sc.parent, sc.func)
    up = ta_var("fe") if sc.kind == :function && @f.single == nil
    ctor = sc.env_count > 7 ? ta_send(ta_var("JS:EnvN"), "new", [up, ta_int(sc.env_count)]) : ta_send(ta_var("JS:Env"), "new", [up])
    [ta_set(env_name(sc), ctor)]

  # Hoisted var bindings of a function start undefined.
  -> hoist_vars(sc)
    out = []
    i = 0
    while i < sc.order.size
      b = sc.order[i]
      if (b.kind == :var || b.kind == :let || b.kind == :const) && !b.in_env?
        out.push(ta_set(local_name(b), ta_nil))
      i += 1
    out

  # Function declarations directly in a statement list are created on entry. (Sloppy-mode
  # functions in nested blocks are var-scoped, Annex B: they are assigned on block entry.)
  -> hoist_functions(stmts, sc)
    out = []
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :function_decl && s.str != nil
        @hoisted[@an.node_key(s)] = true
        jf = @an.fn_of(s)
        b = jf.binding
        if b != nil && b.global?
          out.push(ta_call("js_gdeclare", [cell_of(b), closure(jf, sc), ta_bool(true)]))
        elsif jf.fclass != :call_only
          out.push(write_binding(b, closure(jf, sc), sc))
      i += 1
    out

  # The function object for jf, created in scope sc.
  -> closure(jf, sc)
    ta_call("js_closure", [ta_var("JSC_" + jf.index.to_s), env_for(jf, sc)])

  # What jf's fe is when created (or called directly) at scope sc: the innermost
  # environment around its definition, reached from sc.
  -> env_for(jf, sc)
    return read_binding(jf.single, sc) if jf.single != nil
    return ta_nil if jf.free.size == 0
    t = jf.def_scope
    while t != nil && !t.has_env?
      t = t.parent
    return ta_nil if t == nil
    env_of(t, sc)

  # The innermost environment at scope sc of function f.
  -> current_env(sc, f)
    s = sc
    while s != nil && s.func == f
      return ta_var(env_name(s)) if s.has_env?
      s = s.parent
    return ta_nil if f.single != nil || f.script
    ta_var("fe")

  # The environment record of scope target, seen from scope sc.
  -> env_of(target, sc)
    f = sc.func
    s = sc
    while s != nil && s.func == f
      return ta_var(env_name(s)) if s == target
      s = s.parent
    # outside f: walk up from fe, counting environment-bearing scopes
    e = ta_var("fe")
    s = f.def_scope
    while s != nil
      if s.has_env?
        return e if s == target
        e = ta_call("js_env_up", [e])
      s = s.parent
    @errors.push([f.index, "environment of " + target.id.to_s + " not found"])
    ta_nil

  # ---- bindings ----

  -> read_binding(b, sc)
    return ta_call("js_gget", [cell_of(b)]) if b.global?
    if b.scope.func != sc.func
      return ta_var("fe") if sc.func.single == b
      return ta_call("js_env_get", [env_of(b.scope, sc), ta_int(b.slot)])
    return ta_call("js_env_get", [env_of(b.scope, sc), ta_int(b.slot)]) if b.in_env?
    return ta_var("this") if b.kind == :this
    ta_var(local_name(b))

  -> write_binding(b, v, sc)
    return ta_call("js_gset", [cell_of(b), v, ta_bool(@f.strict)]) if b.global?
    if b.in_env?
      return ta_call("js_env_set", [env_of(b.scope, sc), ta_int(b.slot), v])
    ta_set(local_name(b), v)

  -> binding_of(name, sc)
    @an.resolve(name, sc)

  # ---- statements ----

  -> tr_stmts(stmts, sc)
    out = []
    i = 0
    while i < stmts.size
      r = tr_stmt(stmts[i], sc)
      out = out + r if r != nil
      i += 1
    out

  -> tr_stmt(s, sc)
    k = s.kind
    if k == :expr_stmt
      return [tr_void(s.a, sc)]
    if k == :var_decl
      out = []
      i = 0
      while i < s.list.size
        d = s.list[i]
        b = binding_of(d.a.str, sc)
        if d.b != nil
          out.push(write_binding(b, tr_expr_named(d.b, sc, d.a.str), sc))
        elsif s.str != "var"
          out.push(write_binding(b, ta_nil, sc))
        i += 1
      return out
    if k == :function_decl
      return [] if @hoisted[@an.node_key(s)] == true
      # a declaration as the body of an if (sloppy mode): assigned when reached
      jf = @an.fn_of(s)
      return [write_binding(jf.binding, closure(jf, sc), sc)]
    if k == :empty || k == :debugger
      return []
    if k == :block
      bs = block_scope_of(s, sc)
      out = []
      out = out + scope_entry(bs) if bs != sc
      out = out + hoist_functions(s.list, bs)
      return out + tr_stmts(s.list, bs)
    if k == :if
      return [ta_if(tr_cond(s.a, sc), tr_stmt(s.b, sc), s.c == nil ? nil : tr_stmt(s.c, sc))]
    if k == :return
      return [ta_return(s.a == nil ? ta_nil : tr_expr(s.a, sc))]
    if k == :throw
      return [ta_call("js_throw", [tr_expr(s.a, sc)])]
    if k == :while
      fr = push_frame(:loop, s)
      body = tr_stmt(s.b, sc)
      pop_frame()
      return loop_out(fr, ta_while(tr_cond(s.a, sc), body))
    if k == :do_while
      fr = push_frame(:loop, s)
      body = tr_stmt(s.a, sc)
      pop_frame()
      first = tmp()
      body = [ta_set(first, ta_bool(false))] + body
      return [ta_set(first, ta_bool(true))] + loop_out(fr, ta_while(ta_or(ta_var(first), tr_cond(s.b, sc)), body))
    if k == :for
      return tr_for(s, sc)
    if k == :break || k == :continue
      return tr_jump(s)
    if k == :labeled
      return tr_labeled(s, sc, [s.str])
    if k == :try
      return tr_try(s, sc)
    if k == :switch
      return tr_switch(s, sc, [])
    @errors.push([@f.index, "statement " + k.to_s])
    []

  -> block_scope_of(node, sc)
    @an.scope_for(node, sc)

  # for (init; test; update) body
  -> tr_for(s, sc, labels = [])
    fs = @an.scope_for(s, sc)
    out = []
    out = out + scope_entry(fs) if fs != sc
    if s.a != nil
      if s.a.kind == :var_decl
        out = out + tr_stmt(s.a, fs)
      else
        out.push(tr_expr(s.a, fs))
    @next_labels = labels
    fr = push_frame(:loop, s)
    body = tr_stmt(s.d, fs)
    pop_frame()
    # per-iteration bindings captured by closures: a fresh copy of the environment
    # before the first iteration and before each update (CreatePerIterationEnvironment)
    copy = []
    if fs != sc && fs.has_env?
      copy.push(ta_set(env_name(fs), ta_call("js_env_copy", [ta_var(env_name(fs))])))
      out = out + copy
    test = s.b == nil ? ta_bool(true) : tr_cond(s.b, fs)
    upd = s.c == nil ? [] : [tr_void(s.c, fs)]
    if fr.continue_used && (upd.size > 0 || copy.size > 0)
      first = tmp()
      head = ta_if(ta_var(first), [ta_set(first, ta_bool(false))], copy + upd)
      brk = ta_if(ta_not(test), [ta_break], nil)
      out.push(ta_set(first, ta_bool(true)))
      return out + loop_out(fr, ta_while(ta_bool(true), [head, brk] + body))
    out + loop_out(fr, ta_while(test, body + copy + upd))

  -> tr_labeled(s, sc, labels)
    a = s.a
    return tr_labeled(a, sc, labels + [a.str]) if a.kind == :labeled
    if a.kind == :for
      return tr_for(a, sc, labels)
    if a.kind == :while || a.kind == :do_while
      @next_labels = labels
      return tr_stmt(a, sc)
    if a.kind == :switch
      return tr_switch(a, sc, labels)
    # a labelled statement: a one-pass loop that `break label` leaves
    @next_labels = labels
    fr = push_frame(:block, s)
    body = tr_stmt(a, sc)
    pop_frame()
    loop_out(fr, ta_while(ta_bool(true), body + [ta_break]))

  -> push_frame(kind, node)
    @frame_ids += 1
    fr = JtFrame.new(kind, @next_labels, @frame_ids)
    @next_labels = []
    @frames.push(fr)
    fr

  -> pop_frame
    @frames.pop
    nil

  # The while node for frame fr, followed by the checks for jumps that left it.
  -> loop_out(fr, w)
    out = [w]
    i = 0
    while i < fr.escapes.size
      t = fr.escapes[i]
      out.push(escape_check(t))
      i += 1
    out

  # After an inner loop: a pending jump to frame t (one of the enclosing frames).
  -> escape_check(t)
    cur = @frames.size > 0 ? @frames[@frames.size - 1] : nil
    flag = ta_var(t.flag)
    if cur == t
      return ta_if(ta_eq(flag, ta_int(1)), [ta_set(t.flag, ta_int(0)), ta_break], [ta_if(ta_eq(flag, ta_int(2)), [ta_set(t.flag, ta_int(0)), ta_next], nil)])
    cur.escapes.push(t) if cur != nil && !cur.escapes.include?(t)
    ta_if(ta_ne(flag, ta_int(0)), [ta_break], nil)

  -> tr_jump(s)
    cont = s.kind == :continue
    ti = @frames.size - 1
    found = -1
    while ti >= 0 && found < 0
      fr = @frames[ti]
      if s.str == nil
        found = ti if fr.kind == :loop || (!cont && fr.kind == :switch)
      elsif fr.labels.include?(s.str)
        found = ti
      ti -= 1
    if found < 0
      @errors.push([@f.index, "jump target"])
      return []
    t = @frames[found]
    t.continue_used = true if cont
    if found == @frames.size - 1
      return [cont ? ta_next : ta_break]
    t.flag = tmp() if t.flag == nil
    inner = @frames[@frames.size - 1]
    inner.escapes.push(t) if !inner.escapes.include?(t)
    [ta_set(t.flag, ta_int(cont ? 2 : 1)), ta_break]

  -> tr_try(s, sc)
    body = tr_stmt(s.a, sc)
    ev = tmp()
    cs = @an.scope_for(s, sc)
    rescue_body = []
    rescue_body = rescue_body + scope_entry(cs) if cs != sc
    if s.b != nil
      b = cs.names[s.b.str]
      rescue_body.push(write_binding(b, ta_call("js_error_value", [ta_var(ev)]), cs))
    bs = @an.scope_for(s.c, cs)
    rescue_body = rescue_body + scope_entry(bs) if bs != cs
    rescue_body = rescue_body + hoist_functions(s.c.list, bs)
    rescue_body = rescue_body + tr_stmts(s.c.list, bs)
    [ta_begin(body, ev, rescue_body)]

  # switch: the matching clause's index, then the clauses in a one-pass loop where
  # each runs when its index is at least the match (fall-through).
  -> tr_switch(s, sc, labels)
    bs = @an.scope_for(s, sc)
    out = []
    out = out + scope_entry(bs) if bs != sc
    d = tmp()
    ix = tmp()
    out.push(ta_set(d, tr_expr(s.a, sc)))
    n = s.list.size
    dflt = n
    i = n - 1
    chain = nil
    while i >= 0
      c = s.list[i]
      if c.a == nil
        dflt = i
      i -= 1
    out.push(ta_set(ix, ta_int(dflt)))
    i = n - 1
    tests = []
    while i >= 0
      c = s.list[i]
      if c.a != nil
        chain = ta_if(ta_call("js_seq", [ta_var(d), tr_expr(c.a, bs)]), [ta_set(ix, ta_int(i))], chain == nil ? nil : [chain])
      i -= 1
    out.push(chain) if chain != nil
    @next_labels = labels
    fr = push_frame(:switch, s)
    body = []
    i = 0
    all = []
    while i < n
      all = all + s.list[i].list
      i += 1
    body = body + hoist_functions(all, bs)
    i = 0
    while i < n
      c = s.list[i]
      body.push(ta_if(Tungsten:AST:BinaryOp.new(ta_var(ix), "<=", ta_int(i)), tr_stmts(c.list, bs), nil))
      i += 1
    body.push(ta_break)
    pop_frame()
    out + loop_out(fr, ta_while(ta_bool(true), body))

  # ---- expressions ----

  # An expression whose value is unused: x++ needs no copy of the old value.
  -> tr_void(e, sc)
    if e.kind == :update && !e.has?(F_PREFIX)
      return tr_update(e, sc, true)
    if e.kind == :seq
      parts = []
      i = 0
      while i < e.list.size
        parts.push(tr_void(e.list[i], sc))
        i += 1
      return ta_seq(parts)
    tr_expr(e, sc)

  # An expression in a test position: a Tungsten boolean.
  -> tr_cond(e, sc)
    k = e.kind
    if k == :logical && e.str == "&&"
      return ta_and(tr_cond(e.a, sc), tr_cond(e.b, sc))
    if k == :logical && e.str == "||"
      return ta_or(tr_cond(e.a, sc), tr_cond(e.b, sc))
    if k == :unary && e.str == "!"
      return ta_not(tr_cond(e.a, sc))
    if k == :binary && bool_op?(e.str)
      return tr_expr(e, sc)
    if k == :true
      return ta_bool(true)
    if k == :false
      return ta_bool(false)
    ta_call("js_truthy", [tr_expr(e, sc)])

  -> bool_op?(op)
    op == "<" || op == ">" || op == "<=" || op == ">=" || op == "===" || op == "!==" || op == "==" || op == "!=" || op == "instanceof" || op == "in"

  # A function expression gets the binding's name (`var f = function(){}`).
  -> tr_expr_named(e, sc, name)
    tr_expr(e, sc)

  -> tr_expr(e, sc)
    k = e.kind
    if k == :num
      return ta_num(e.a)
    if k == :string
      return ta_str(e.str)
    if k == :true
      return ta_bool(true)
    if k == :false
      return ta_bool(false)
    if k == :null
      return ta_var("JS_NULL")
    if k == :ident
      return tr_ident(e, sc)
    if k == :this
      return tr_this(sc)
    if k == :binary
      return tr_binary(e, sc)
    if k == :logical
      t = tmp()
      a = ta_set(t, tr_expr(e.a, sc))
      b = tr_expr(e.b, sc)
      if e.str == "&&"
        return ta_if(ta_call("js_truthy", [a]), [b], [ta_var(t)])
      if e.str == "||"
        return ta_if(ta_call("js_truthy", [a]), [ta_var(t)], [b])
      return ta_if(ta_call("js_nullish?", [a]), [b], [ta_var(t)])
    if k == :unary
      return tr_unary(e, sc)
    if k == :update
      return tr_update(e, sc)
    if k == :assign
      return tr_assign(e, sc)
    if k == :cond
      return ta_if(tr_cond(e.a, sc), [tr_expr(e.b, sc)], [tr_expr(e.c, sc)])
    if k == :seq
      parts = []
      i = 0
      while i < e.list.size
        parts.push(tr_expr(e.list[i], sc))
        i += 1
      return ta_seq(parts)
    if k == :call
      return tr_call(e, sc)
    if k == :new
      args = call_args(e.list, sc)
      return with_temps(args, ta_call("js_new", [tr_expr(e.a, sc), ta_int(site(2))] + args[1]))
    if k == :member
      return tr_member_get(e, sc)
    if k == :function || k == :arrow
      jf = @an.fn_of(e)
      return closure(jf, sc)
    if k == :array
      return tr_array(e, sc)
    if k == :object
      return tr_object(e, sc)
    @errors.push([@f.index, "expression " + k.to_s])
    ta_nil

  -> tr_ident(e, sc)
    b = binding_of(e.str, sc)
    if b.kind == :global && @an.funcs[0].scope.names[e.str] == b && b.writes == 0
      return ta_nil if e.str == "undefined"
      return ta_num(js_nan()) if e.str == "NaN"
      return ta_num(~1.0 / ~0.0) if e.str == "Infinity"
    read_binding(b, sc)

  -> tr_this(sc)
    f = sc.func
    g = f
    while g.arrow
      g = g.parent
    return ta_var("this") if g == f || g.script
    read_binding(g.this_binding, sc)


  -> tr_binary(e, sc)
    op = e.str
    a = tr_expr(e.a, sc)
    b = tr_expr(e.b, sc)
    return ta_not(ta_call("js_seq", [a, b])) if op == "!=="
    return ta_call("js_int32", [a]) if op == "|" && e.b.kind == :num && e.b.a == ~0.0
    return ta_not(ta_call("js_eq", [a, b])) if op == "!="
    fn = JT_OPS[op]
    if fn == nil
      @errors.push([@f.index, "operator " + op])
      return ta_nil
    ta_call(fn, [a, b])

  -> tr_unary(e, sc)
    op = e.str
    if op == "typeof"
      if e.a.kind == :ident
        b = binding_of(e.a.str, sc)
        return ta_call("js_gtypeof", [cell_of(b)]) if b.global?
      return ta_call("js_typeof", [tr_expr(e.a, sc)])
    if op == "delete"
      a = e.a
      if a.kind == :member
        key = a.has?(F_COMPUTED) ? tr_expr(a.b, sc) : ta_str(a.b.str)
        return ta_call("js_delete", [tr_expr(a.a, sc), key, ta_bool(@f.strict)])
      return ta_seq([tr_expr(a, sc), ta_bool(true)])
    v = tr_expr(e.a, sc)
    return ta_not(tr_cond(e.a, sc)) if op == "!"
    return ta_call("js_neg", [v]) if op == "-"
    return ta_call("js_plus", [v]) if op == "+"
    return ta_call("js_bitnot", [v]) if op == "~"
    return ta_seq([v, ta_nil]) if op == "void"
    @errors.push([@f.index, "unary " + op])
    ta_nil

  # ++x, x++, --x, x-- (void: the value is unused, so x++ is ++x)
  -> tr_update(e, sc, void = false)
    fn = e.str == "++" ? "js_add" : "js_sub"
    one = ta_num(~1.0)
    t = e.a
    old = tmp()
    pre = e.has?(F_PREFIX) || void
    if t.kind == :ident
      b = binding_of(t.str, sc)
      if pre
        return write_binding(b, ta_call(fn, [ta_call("js_tonumeric", [read_binding(b, sc)]), one]), sc)
      get = ta_set(old, ta_call("js_tonumeric", [read_binding(b, sc)]))
      return ta_seq([write_binding(b, ta_call(fn, [get, one]), sc), ta_var(old)])
    if t.kind == :member
      o = tmp()
      if t.has?(F_COMPUTED)
        kk = tmp()
        pre_nodes = [ta_set(o, tr_expr(t.a, sc)), ta_set(kk, ta_call("js_to_property_key", [tr_expr(t.b, sc)]))]
        get = ta_set(old, ta_call("js_tonumeric", [ta_call("js_getv", [ta_var(o), ta_var(kk)])]))
        set = ta_call("js_setv", [ta_var(o), ta_var(kk), ta_call(fn, [get, one]), ta_bool(@f.strict)])
      else
        pre_nodes = [ta_set(o, tr_expr(t.a, sc))]
        get = ta_set(old, ta_call("js_tonumeric", [ta_call("js_getp", [ta_var(o), ta_str(t.b.str), ta_int(site(1))])]))
        set = ta_call("js_setp", [ta_var(o), ta_str(t.b.str), ta_call(fn, [get, one]), ta_int(site(1))])
      return ta_seq(pre_nodes + [set]) if pre
      return ta_seq(pre_nodes + [set, ta_var(old)])
    @errors.push([@f.index, "update target"])
    ta_nil

  -> tr_assign(e, sc)
    op = e.str
    t = e.a
    if t.kind == :ident
      b = binding_of(t.str, sc)
      v = nil
      if op == "="
        v = tr_expr_named(e.b, sc, t.str)
      elsif op == "&&=" || op == "||=" || op == "??="
        return tr_logical_assign(e, sc, b)
      else
        v = ta_call(JT_OPS[op.slice(0, op.size - 1)], [read_binding(b, sc), tr_expr(e.b, sc)])
      if b.kind == :const
        return ta_seq([v, ta_call("js_throw_type", [ta_str("Assignment to constant variable.")])])
      return write_binding(b, v, sc)
    if t.kind == :member
      if op == "&&=" || op == "||=" || op == "??="
        @errors.push([@f.index, "logical assignment to a member"])
        return ta_nil
      o = tr_expr(t.a, sc)
      if t.has?(F_COMPUTED)
        if op == "="
          return ta_call("js_setv", [o, tr_expr(t.b, sc), tr_expr(e.b, sc), ta_bool(@f.strict)])
        ot = tmp()
        kt = tmp()
        pre = [ta_set(ot, o), ta_set(kt, ta_call("js_to_property_key", [tr_expr(t.b, sc)]))]
        v = ta_call(JT_OPS[op.slice(0, op.size - 1)], [ta_call("js_getv", [ta_var(ot), ta_var(kt)]), tr_expr(e.b, sc)])
        return ta_seq(pre + [ta_call("js_setv", [ta_var(ot), ta_var(kt), v, ta_bool(@f.strict)])])
      key = ta_str(t.b.str)
      if op == "="
        return ta_call("js_setp", [o, key, tr_expr(e.b, sc), ta_int(site(1))])
      ot = tmp()
      v = ta_call(JT_OPS[op.slice(0, op.size - 1)], [ta_call("js_getp", [ta_var(ot), key, ta_int(site(1))]), tr_expr(e.b, sc)])
      return ta_seq([ta_set(ot, o), ta_call("js_setp", [ta_var(ot), key, v, ta_int(site(1))])])
    @errors.push([@f.index, "assignment target"])
    ta_nil

  -> tr_logical_assign(e, sc, b)
    t = tmp()
    cur = ta_set(t, read_binding(b, sc))
    set = write_binding(b, tr_expr(e.b, sc), sc)
    if e.str == "&&="
      return ta_if(ta_call("js_truthy", [cur]), [set], [ta_var(t)])
    if e.str == "||="
      return ta_if(ta_call("js_truthy", [cur]), [ta_var(t)], [set])
    ta_if(ta_call("js_nullish?", [cur]), [set], [ta_var(t)])

  -> tr_member_get(e, sc)
    o = tr_expr(e.a, sc)
    if e.has?(F_COMPUTED)
      return ta_call("js_getv", [o, tr_expr(e.b, sc)])
    ta_call("js_getp", [o, ta_str(e.b.str), ta_int(site(1))])

  # Arguments in generic-entry form: [setup nodes, [argc, a0, a1, a2, a3, more]].
  # More than four arguments are evaluated once into temporaries.
  -> call_args(list, sc)
    n = list.size
    if n <= 4
      a = [ta_int(n)]
      i = 0
      while i < 4
        a.push(i < n ? tr_expr(list[i], sc) : ta_nil)
        i += 1
      a.push(ta_nil)
      return [[], a]
    pre = []
    vars = []
    i = 0
    while i < n
      t = tmp()
      pre.push(ta_set(t, tr_expr(list[i], sc)))
      vars.push(ta_var(t))
      i += 1
    arr = tmp()
    pre.push(ta_set(arr, ta_array(vars)))
    [pre, [ta_int(n), vars[0], vars[1], vars[2], vars[3], ta_var(arr)]]

  -> with_temps(args, call)
    return call if args[0].size == 0
    ta_seq(args[0] + [call])

  -> tr_call(e, sc)
    c = e.a
    args = call_args(e.list, sc)
    if c.kind == :ident
      b = binding_of(c.str, sc)
      jf = b.fnode
      if jf != nil && jf.fclass == :call_only && !b.global?
        return with_temps(args, ta_call("jsd_" + jf.index.to_s, [env_for(jf, sc), ta_nil] + args[1]))
      if b.kind == :self
        # recursion through a function expression's own name (from its own body)
        return with_temps(args, ta_call("jsd_" + b.scope.func.index.to_s, [ta_var("fe"), ta_nil] + args[1]))
      if jf != nil && jf.fclass == :escaping && jf.single == nil && jf.free.size == 0
        # a guess at the callee (the function this name is declared as), checked by code
        return guarded_call(tr_ident(c, sc), jf, args)
      return with_temps(args, ta_call("js_call", [tr_ident(c, sc), ta_nil] + args[1]))
    if (c.kind == :function || c.kind == :arrow)
      jf = @an.fn_of(c)
      if jf != nil && jf.fclass == :iife
        return with_temps(args, ta_call("jsd_" + jf.index.to_s, [env_for(jf, sc), ta_nil] + args[1]))
    if c.kind == :member
      if c.has?(F_COMPUTED)
        return with_temps(args, ta_call("js_call_computed", [tr_expr(c.a, sc), tr_expr(c.b, sc)] + args[1]))
      return with_temps(args, ta_call("js_call_method", [tr_expr(c.a, sc), ta_str(c.b.str), ta_int(site(1))] + args[1]))
    with_temps(args, ta_call("js_call", [tr_expr(c, sc), ta_nil] + args[1]))

  # f(args) where f is expected to be jf's object: a direct call when its code matches,
  # else the generic call. Arguments are evaluated once, into temporaries.
  -> guarded_call(fexpr, jf, args)
    ft = tmp()
    pre = args[0] + [ta_set(ft, fexpr)]
    a = args[1]
    vals = []
    i = 0
    while i < a.size
      x = a[i]
      if i >= 1 && i <= 4 && !simple_arg?(x)
        t = tmp()
        pre.push(ta_set(t, x))
        vals.push(ta_var(t))
      else
        vals.push(x)
      i += 1
    direct = ta_call("jsd_" + jf.index.to_s, [ta_nil, ta_nil] + vals)
    generic = ta_call("js_call", [ta_var(ft), ta_nil] + vals)
    ta_seq(pre + [ta_if(ta_call("js_code_is?", [ta_var(ft), ta_var("JSC_" + jf.index.to_s)]), [direct], [generic])])

  -> simple_arg?(x)
    k = ast_kind(x)
    k == :var || k == :nil_lit || k == :int || k == :float || k == :string || k == :bool

  -> tr_array(e, sc)
    elems = []
    holes = false
    i = 0
    while i < e.list.size
      x = e.list[i]
      if x == nil
        holes = true
        elems.push(ta_var("JS_HOLE"))
      else
        elems.push(tr_expr(x, sc))
      i += 1
    ta_call(holes ? "js_mark_holey" : "js_mark_array", [ta_array(elems)])

  # An object literal with distinct static keys: one allocation with the site's final
  # shape (computed once at start) and the values stored straight into slots.
  -> tr_object(e, sc)
    keys = []
    vals = []
    plain = true
    i = 0
    while i < e.list.size
      p = e.list[i]
      key = prop_key(p.a)
      plain = false if key == nil || key == "__proto__" || keys.include?(key)
      keys.push(key)
      vals.push(tr_expr_named(p.b, sc, key))
      i += 1
    if plain
      si = @lit_shapes.size
      @lit_shapes.push(keys)
      if vals.size <= 6
        while vals.size < 6
          vals.push(ta_nil)
        return ta_call("js_lit", [ta_var("JSS_" + si.to_s)] + vals)
      return ta_call("js_lit_n", [ta_var("JSS_" + si.to_s), ta_array(vals)])
    o = tmp()
    out = [ta_set(o, ta_call("js_new_object", [ta_send(ta_var("JSR"), "object_proto", [])]))]
    i = 0
    while i < keys.size
      out.push(ta_call("js_define_literal", [ta_var(o), ta_str(keys[i]), vals[i]]))
      i += 1
    out.push(ta_var(o))
    ta_seq(out)

  -> prop_key(a)
    return a.str if a.kind == :ident || a.kind == :string
    if a.kind == :num
      x = a.a
      return x.to_i.to_s if x == Math.floor(x) && x >= ~0.0 && x < ~9007199254740992.0
    nil
