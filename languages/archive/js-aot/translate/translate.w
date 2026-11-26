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
# called through jsd_N directly and never get an object (PLAN.md 3.9). A function that
# must see its own object (a class constructor, a method using super, a named function
# expression whose name is used as a value) receives the object in fe instead: its
# jsd_N starts with `fobj = fe; fe = js_fenv(fobj)`.
#
# Control flow: one Tungsten `while` per JS loop, switch or labelled block. A break or
# continue that must leave more than one of them sets a flag local and breaks; each
# enclosing while checks the flag on the way out.
#
# try/finally (PLAN.md 3.6): the try (and catch) run inside a one-pass `while` around a
# `begin`; a throw is caught into a pending-completion record (kind, value), and a
# return, break or continue that leaves the try records itself there and breaks out.
# The finally block follows the loop, then the record is replayed (re-raise, return, or
# the jump re-issued from outside). A finally that completes abruptly simply never
# reaches the replay. for-of closes its iterator the same way: the iterator is closed
# after its loop, which every exit but a return passes through; a return closes the
# iterators it leaves itself.

use build
use unit
use ../analyze

JT_OPS = {"+" => "js_add", "-" => "js_sub", "*" => "js_mul", "/" => "js_div", "%" => "js_mod", "**" => "js_pow", "<" => "js_lt", ">" => "js_gt", "<=" => "js_le", ">=" => "js_ge", "==" => "js_eq", "===" => "js_seq", "|" => "js_bitor", "&" => "js_bitand", "^" => "js_bitxor", "<<" => "js_shl", ">>" => "js_sar", ">>>" => "js_shr", "instanceof" => "js_instanceof", "in" => "js_in"}

# A JS loop, switch, labelled block, or try/finally being translated. kind :finally
# frames hold the pending-completion locals (pk: 0 normal, 1 throw, 2 return, 3 + i the
# i-th recorded jump; pv: the thrown or returned value). close: a for-of's iterator
# local, closed by a return that leaves it.
+ JtFrame
  rw :kind, :labels, :id, :flag, :escapes, :continue_used, :first, :pk, :pv, :jumps, :has_return, :close
  -> new(@kind, @labels, @id)
    @flag = nil
    @escapes = []
    @continue_used = false
    @first = nil
    @pk = nil
    @pv = nil
    @jumps = []
    @has_return = false
    @close = nil

+ JsTranslator
  rw :an, :ic_words, :errors, :globals, :lexicals, :codes, :lit_shapes, :fn_count, :source, :glist, :llist, :templates, :omit

  -> new(@an)
    @ic_words = 8
    @errors = []
    @globals = {}
    @glist = []
    @lexicals = {}
    @llist = []
    @codes = []
    @lit_shapes = []
    @templates = []
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
    @partial = false
    @omit = {}
    @source = nil

  # ---- program ----

  # The program's top-level nodes (after the runtime): realm, cells, codes, functions,
  # the dispatcher and the run of the script.
  # partial: functions the slice cannot compile (or before skip, past limit, or larger
  # than maxsize bytes of source) become
  # stubs that would run in tier 0, instead of failing the program (the scale check;
  # units later).
  -> program(partial = false, limit = -1, skip = 0, maxsize = -1)
    fs = @an.funcs
    i = 0
    while i < fs.size
      f = fs[i]
      if f.unsupported != nil
        @errors.push([f.index, f.unsupported])
      i += 1
    return nil if @errors.size > 0 && !partial
    @translated = 0
    @partial = partial
    # which functions this program compiles (partial: the supported ones, up to limit;
    # the rest would stay in tier 0 and are reached only through code descriptors)
    @omit = {}
    i = 0
    n = 0
    sk = 0
    while i < fs.size
      f = fs[i]
      big = partial && !f.script && maxsize >= 0 && f.node.fin - f.node.pos > maxsize
      if big
        @omit[f.index] = true
      elsif partial && !f.script && f.unsupported == nil && sk < skip
        @omit[f.index] = true
        sk += 1
      elsif partial && (f.unsupported != nil || (limit >= 0 && n >= limit && !f.script))
        @omit[f.index] = true
      else
        n += 1
      i += 1
    i = 0
    while i < fs.size
      f = fs[i]
      if @omit[f.index] != true
        nerr = @errors.size
        nd = @defs.size
        tr_function(f)
        if partial && @errors.size > nerr
          while @defs.size > nd
            @defs.pop
          @defs.push(stub(f))
        else
          @translated += 1
          u = JT_UNIT[0]
          u.entries.push(f.index) if u != nil && (f.script || f.fclass == :escaping)
      i += 1
    u = JT_UNIT[0]
    if u != nil
      # a unit: the functions and jsu_init (the host makes the realm, cells and codes)
      out = []
      @defs.each ->(d) out.push(d)
      u.init_defs.each ->(d) out.push(d)
      return out
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
    # the script's text, for Function.prototype.toString over each code's span
    out.push(ta_call("js_set_source", [ta_str(@source)])) if @source != nil
    i = 0
    while i < fs.size
      f = fs[i]
      if @omit[i] != true
        c = ta_send(ta_var("JS:Code"), "new", [ta_str(f.name), ta_int(f.nparams), ta_int(i), ta_int(code_flags(f))])
        if @source != nil && !f.script
          sn = f.class_ctor && f.class_node != nil ? f.class_node : f.node
          c = ta_call("js_code_span", [c, ta_int(sn.pos), ta_int(sn.fin)])
        out.push(ta_set("JSC_" + i.to_s, c))
      i += 1
    i = 0
    while i < @lit_shapes.size
      ks = []
      @lit_shapes[i].each ->(k) ks.push(ta_str(k))
      out.push(ta_set("JSS_" + i.to_s, ta_call("js_lit_shape", [ta_array(ks)])))
      i += 1
    # the template objects of tagged templates: one per site, made once
    i = 0
    while i < @templates.size
      cooked = []
      raw = []
      @templates[i].list.each ->(q)
        cooked.push(q.str == nil ? ta_nil : ta_str(q.str))
        raw.push(ta_str(q.a))
      out.push(ta_set("JSTO_" + i.to_s, ta_call("js_template_object", [ta_array(cooked), ta_array(raw)])))
      i += 1
    out.push(dispatcher())
    @defs.each ->(d) out.push(d)
    run = ta_call("jsd_0", [ta_nil, ta_nil, ta_int(0), ta_nil, ta_nil, ta_nil, ta_nil, ta_nil])
    out.push(ta_begin([run], "uncaught", [ta_call("js_report_uncaught", [ta_var("uncaught")])]))
    out.push(ta_call("js_finish", []))
    out

  -> translated
    @translated

  # JS:Code flags (runtime/function.w), as tier 0 computes them, plus CODE_NONT for code
  # that never reads new.target.
  -> code_flags(f)
    n = f.node
    gen = n.has?(F_GENERATOR)
    asy = n.has?(F_ASYNC)
    ctor = !f.arrow && !f.script && (f.method_kind == nil || f.class_ctor) && !f.field_init && !gen && !asy
    fl = (f.strict ? 1 : 0) + (f.arrow ? 2 : 0) + (ctor ? 8 : 0) + (f.class_ctor ? 16 : 0) + (f.class_ctor && f.derived ? 32 : 0) + (gen ? 64 : 0) + (asy ? 128 : 0)
    fl += 256 if !reads_nt?(f)
    fl

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
      if fs[i].fclass == :escaping && !fs[i].script && @omit[i] != true
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

  # Does f's jsd_N receive its own object (in fe)?
  -> needs_fobj?(f)
    f.class_ctor || f.fo_binding != nil || self_needed?(f)

  # A named function expression whose name is read as a value (or from a nested function).
  -> self_needed?(f)
    sb = f.self_binding
    sb != nil && (sb.value_uses > 0 || sb.captured)

  -> reads_nt?(f)
    f.class_ctor || f.nt_binding != nil

  # The value of argument i in the generic entry.
  -> arg_value(i)
    return ta_var("a" + i.to_s) if i < 4
    ta_if(ta_gt(ta_var("argc"), ta_int(i)), [ta_send(ta_var("more"), "\[]", [ta_int(i)])], [ta_nil])

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
      if needs_fobj?(f)
        body.push(ta_set("fobj", ta_var("fe")))
        body.push(ta_set("fe", ta_call("js_fenv", [ta_var("fobj")])))
      body.push(ta_set("ntv", ta_call("js_take_nt", []))) if reads_nt?(f)
      if f.class_ctor
        body.push(ta_if(ta_eq(ta_var("ntv"), ta_nil), [ta_call("js_throw_type", [ta_str("Class constructor " + f.name + " cannot be invoked without 'new'")])], nil))
        if f.default_ctor
          body.push(ta_return(ta_call("js_default_ctor", [ta_var("fobj"), ta_var("this"), ta_var("ntv"), ta_bool(f.derived), ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")])))
          emit_function(f, body)
          return nil
        # a base class initializes its fields before its parameters (§10.2.2)
        body.push(ta_call("js_init_fields", [ta_var("this"), ta_var("fobj")])) if !f.derived
      if f.uses_this && !f.strict && !f.arrow
        body.push(ta_set("this", ta_call("js_sloppy_this", [ta_var("this")])))
      body = body + scope_entry(sc)
      if f.this_binding != nil && f.this_binding.in_env?
        body.push(write_binding(f.this_binding, ta_var("this"), sc))
      body.push(write_binding(f.nt_binding, ta_var("ntv"), sc)) if f.nt_binding != nil && f.nt_binding.in_env?
      body.push(write_binding(f.fo_binding, ta_var("fobj"), sc)) if f.fo_binding != nil && f.fo_binding.in_env?
      body.push(write_binding(f.self_binding, ta_var("fobj"), sc)) if self_needed?(f)
      if f.args_binding != nil
        body.push(write_binding(f.args_binding, ta_call("js_args_object", [ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")]), sc))
      if f.simple
        i = 0
        while i < f.params.size
          body.push(write_binding(f.params[i], arg_value(i), sc))
          i += 1
      else
        body = body + tr_params(f, sc)
      body = body + hoist_vars(sc)
      bs = f.body_scope
      if bs != sc
        # a non-simple parameter list: the body's own scope, where a var named like a
        # parameter starts with its value
        body = body + scope_entry(bs) + hoist_vars(bs)
        f.param_copies.each ->(pc) body.push(write_binding(pc[1], read_binding(pc[0], bs), bs))
    if f.arrow && n.has?(F_EXPR_BODY)
      body.push(ta_return(tr_expr(n.b, sc)))
    else
      stmts = f.script ? n.list : n.b
      body = body + hoist_functions(stmts, f.body_scope)
      body = body + tr_stmts(stmts, f.body_scope)
      # a script answers its completion value (eval, a host's script runner)
      body.push(emit_return(f.script ? ta_var("jscv") : ta_nil))
    emit_function(f, body)
    nil

  -> emit_function(f, body)
    @defs.push(ta_def("jsd_" + f.index.to_s, ["fe", "this", "argc", "a0", "a1", "a2", "a3", "more"], body))
    if !f.script && f.fclass == :escaping
      first = needs_fobj?(f) ? ta_var("f") : ta_call("js_fenv", [ta_var("f")])
      @defs.push(ta_def("jsf_" + f.index.to_s, ["f", "this", "argc", "a0", "a1", "a2", "a3", "more"], [ta_call("jsd_" + f.index.to_s, [first, ta_var("this"), ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")])]))
    nil

  # Defaults, patterns and a rest element, bound in order in the parameter scope.
  -> tr_params(f, sc)
    out = []
    ps = f.param_nodes
    i = 0
    while i < ps.size
      p = ps[i]
      if p.kind == :rest
        out = out + tr_bind(p.a, ta_call("js_rest_args", [ta_int(i), ta_var("argc"), ta_var("a0"), ta_var("a1"), ta_var("a2"), ta_var("a3"), ta_var("more")]), sc, true)
      else
        out = out + tr_bind(p, arg_value(i), sc, true)
      i += 1
    out

  # Script top level: its var names become properties of the global object.
  -> script_prologue(f)
    out = [ta_set("jscv", ta_nil)]
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
    ctor = sc.env_count > 7 ? ta_new("JS:EnvN", [up, ta_int(sc.env_count)]) : ta_new("JS:Env", [up])
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
    ta_call("js_closure", [code_ref(jf), env_for(jf, sc)])

  # The JS:Code of jf: a global of this program, or (for a function it does not compile)
  # the descriptor the host keeps.
  -> code_ref(jf)
    # (a unit gets every descriptor from the host, compiled here or not)
    return ta_call("js_code_at", [ta_int(jf.index)]) if @omit[jf.index] == true && JT_UNIT[0] == nil
    ta_var("JSC_" + jf.index.to_s)

  -> compiled?(jf)
    @omit[jf.index] != true

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

  # A write that is not a declaration's initialization (script-level let/const/class
  # cells check their dead zone and constness).
  -> write_binding(b, v, sc)
    return ta_call("js_lset", [lcell(b.name), v]) if b.kind == :lexical
    return ta_call("js_gset", [cell_of(b), v, ta_bool(@f.strict)]) if b.global?
    if b.in_env?
      return ta_call("js_env_set", [env_of(b.scope, sc), ta_int(b.slot), v])
    ta_set(local_name(b), v)

  # A declaration's initialization (let/const/class, parameters, patterns in declarations).
  -> init_binding(b, v, sc)
    return ta_call("js_linit", [lcell(b.name), v, ta_bool(b.decl_const)]) if b.kind == :lexical
    write_binding(b, v, sc)

  # An assignment: a TypeError for a const, an inner class name, or (strict) a function
  # expression's own name, which sloppy code silently leaves alone.
  -> assign_binding(b, v, sc)
    if b.kind == :const || b.kind == :class_inner || (b.kind == :self && @f.strict)
      return ta_seq([v, ta_call("js_throw_type", [ta_str("Assignment to constant variable.")])])
    return v if b.kind == :self
    write_binding(b, v, sc)

  -> binding_of(name, sc)
    @an.resolve(name, sc)

  # ---- patterns (destructuring; tier 0's wk_bind) ----

  # Statements binding (decl) or assigning value v (a node, evaluated once) to pattern p.
  -> tr_bind(p, v, sc, decl)
    k = p.kind
    if k == :ident
      b = binding_of(p.str, sc)
      return [decl ? init_binding(b, v, sc) : assign_binding(b, v, sc)]
    if k == :assign_pattern
      t = tmp()
      return [ta_set(t, v), ta_if(ta_eq(ta_var(t), ta_nil), [ta_set(t, tr_expr(p.b, sc))], nil)] + tr_bind(p.a, ta_var(t), sc, decl)
    if k == :member
      return [tr_member_set(p, v, sc)]
    if k == :array_pattern
      return tr_bind_array(p, v, sc, decl)
    if k == :object_pattern
      return tr_bind_object(p, v, sc, decl)
    @errors.push([@f.index, "pattern " + k.to_s])
    []

  # Assign v to a member target (object first evaluated after v, as tier 0 does).
  -> tr_member_set(p, v, sc)
    if p.a.kind == :super
      th = tmp()
      vt = tmp()
      return ta_seq([ta_set(vt, v), ta_set(th, tr_this(sc)), ta_call("js_super_set", [fo_value(sc), tr_super_key(p, sc), ta_var(vt), ta_var(th), ta_bool(@f.strict)])])
    if p.b.kind == :private_name && !p.has?(F_COMPUTED)
      vt = tmp()
      return ta_seq([ta_set(vt, v), ta_call("js_priv_set", [tr_expr(p.a, sc), read_binding(p.b.x.binding, sc), ta_var(vt)])])
    vt = tmp()
    ot = tmp()
    key = p.has?(F_COMPUTED) ? ta_call("js_to_property_key", [tr_expr(p.b, sc)]) : ta_str(p.b.str)
    ta_seq([ta_set(vt, v), ta_set(ot, tr_expr(p.a, sc)), ta_call("js_setv", [ta_var(ot), key, ta_var(vt), ta_bool(@f.strict)])])

  # [a, b = d, , ...r] = v: arrays whose iterator is the intrinsic one are read by index,
  # anything else through its iterator (closed when the pattern ends early or throws).
  -> tr_bind_array(p, v, sc, decl)
    it = tmp()
    out = [ta_set(it, ta_call("js_pat_iter", [v]))]
    steps = []
    i = 0
    while i < p.list.size
      e = p.list[i]
      t = e == nil ? nil : (e.kind == :rest || e.kind == :assign_pattern ? e.a : e)
      if e == nil
        steps.push(ta_call("js_pat_skip", [ta_var(it)]))
      elsif member_target?(t, decl)
        x = e.kind == :rest ? ta_call("js_pat_rest", [ta_var(it), ta_int(i)]) : ta_call("js_pat_step", [ta_var(it), ta_int(i)])
        steps = steps + tr_bind_member(t, e.kind == :assign_pattern ? e.b : nil, x, sc)
      elsif e.kind == :rest
        steps = steps + tr_bind(e.a, ta_call("js_pat_rest", [ta_var(it), ta_int(i)]), sc, decl)
      else
        steps = steps + tr_bind(e, ta_call("js_pat_step", [ta_var(it), ta_int(i)]), sc, decl)
      i += 1
    if pattern_safe?(p, sc)
      out = out + steps
    else
      ex = tmp()
      out.push(ta_begin(steps, ex, [ta_call("js_pat_close_quiet", [ta_var(it)]), ta_raise(ta_var(ex))]))
    out.push(ta_call("js_pat_close", [ta_var(it)]))
    out

  # Can binding the elements of array pattern p throw (so that the iterator must be
  # closed)? Plain names of function bindings without defaults cannot.
  -> pattern_safe?(p, sc)
    i = 0
    while i < p.list.size
      e = p.list[i]
      e = e.a if e != nil && e.kind == :rest
      if e != nil
        return false if e.kind != :ident
        b = binding_of(e.str, sc)
        return false if b.global? || b.kind == :const || b.kind == :class_inner || b.kind == :self
      i += 1
    true

  -> tr_bind_object(p, v, sc, decl)
    t = tmp()
    out = [ta_set(t, ta_call("js_req_coercible", [v]))]
    used = []
    has_rest = false
    i = 0
    while i < p.list.size
      has_rest = true if p.list[i].kind == :rest
      i += 1
    i = 0
    while i < p.list.size
      e = p.list[i]
      if e.kind == :rest
        keys = []
        used.each ->(u) keys.push(u[0] ? ta_var(u[1]) : ta_str(u[1]))
        out = out + tr_bind(e.a, ta_call("js_object_rest", [ta_var(t), ta_array(keys)]), sc, decl)
      elsif e.has?(F_COMPUTED)
        kt = tmp()
        out.push(ta_set(kt, ta_call("js_to_property_key", [tr_expr(e.a, sc)])))
        used.push([true, kt]) if has_rest
        out = out + tr_bind_prop(e.b, ta_call("js_get_value", [ta_var(t), ta_var(kt)]), sc, decl)
      else
        ks = prop_key(e.a)
        if ks != nil
          used.push([false, ks]) if has_rest
          out = out + tr_bind_prop(e.b, ta_call("js_getp", [ta_var(t), ta_str(ks), ta_int(site(1))]), sc, decl)
        else
          kt = tmp()
          out.push(ta_set(kt, static_key(e.a)))
          used.push([true, kt]) if has_rest
          out = out + tr_bind_prop(e.b, ta_call("js_get_value", [ta_var(t), ta_var(kt)]), sc, decl)
      i += 1
    out

  # The value pattern of an object pattern property.
  -> tr_bind_prop(b, v, sc, decl)
    t = b.kind == :assign_pattern ? b.a : b
    return tr_bind_member(t, b.kind == :assign_pattern ? b.b : nil, v, sc) if member_target?(t, decl)
    tr_bind(b, v, sc, decl)

  # An assignment pattern's member target: its object and key are evaluated before the
  # value (§13.15.5.5, .6).
  -> member_target?(t, decl)
    !decl && t != nil && t.kind == :member && t.a.kind != :super

  # Member target t gets value v (or dflt when v is undefined).
  -> tr_bind_member(t, dflt, v, sc)
    ot = tmp()
    xt = tmp()
    out = [ta_set(ot, tr_expr(t.a, sc))]
    kt = nil
    if t.has?(F_COMPUTED)
      kt = tmp()
      out.push(ta_set(kt, ta_call("js_to_property_key", [tr_expr(t.b, sc)])))
    out.push(ta_set(xt, v))
    out.push(ta_if(ta_eq(ta_var(xt), ta_nil), [ta_set(xt, tr_expr(dflt, sc))], nil)) if dflt != nil
    if t.b.kind == :private_name && !t.has?(F_COMPUTED)
      out.push(ta_call("js_priv_set", [ta_var(ot), read_binding(t.b.x.binding, sc), ta_var(xt)]))
    else
      out.push(ta_call("js_setv", [ta_var(ot), kt == nil ? ta_str(t.b.str) : ta_var(kt), ta_var(xt), ta_bool(@f.strict)]))
    out

  # A property key written in the source, as a node (tier 0's wk_prop_key).
  -> static_key(a)
    k = prop_key(a)
    return ta_str(k) if k != nil
    return ta_call("js_number_to_s", [ta_num(a.a)]) if a.kind == :num
    ta_str(a.str)

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
      return [ta_set("jscv", tr_expr(s.a, sc))] if @f.script
      return [tr_void(s.a, sc)]
    if @f.script && (k == :if || k == :for || k == :while || k == :do_while || k == :try || k == :switch || k == :for_in || k == :for_of)
      # these complete with undefined when nothing inside produced a value (UpdateEmpty)
      return [ta_set("jscv", ta_nil)] + tr_stmt_inner(s, sc)
    tr_stmt_inner(s, sc)

  -> tr_stmt_inner(s, sc)
    k = s.kind
    if k == :expr_stmt
      return [tr_void(s.a, sc)]
    if k == :var_decl
      out = []
      lex = s.str != "var"
      i = 0
      while i < s.list.size
        d = s.list[i]
        if d.a.kind != :ident
          out = out + tr_bind(d.a, tr_expr(d.b, sc), sc, true)
        else
          b = binding_of(d.a.str, sc)
          if d.b != nil
            v = tr_expr_named(d.b, sc, d.a.str)
            out.push(lex ? init_binding(b, v, sc) : write_binding(b, v, sc))
          elsif lex
            out.push(init_binding(b, ta_nil, sc))
        i += 1
      return out
    if k == :function_decl
      if @hoisted[@an.node_key(s)] == true
        jf = @an.fn_of(s)
        # Annex B: evaluating the declaration copies the block's binding into the var
        return [write_binding(jf.annexb, read_binding(jf.binding, sc), sc)] if jf.annexb != nil
        return []
      # a declaration as the body of an if (sloppy mode): assigned when reached
      jf = @an.fn_of(s)
      return [write_binding(jf.binding, closure(jf, sc), sc)]
    if k == :class_decl
      return [init_binding(binding_of(s.str, sc), tr_class(s, sc), sc)]
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
      return return_value(s.a == nil ? ta_nil : tr_expr(s.a, sc))
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
    if k == :for_in
      return tr_for_in(s, sc)
    if k == :for_of
      return tr_for_of(s, sc)
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
      copy = [ta_set(env_name(fs), ta_call("js_env_copy", [ta_var(env_name(fs))]))]
    test = s.b == nil ? ta_bool(true) : tr_cond(s.b, fs)
    upd = s.c == nil ? [] : [tr_void(s.c, fs)]
    if fr.continue_used && (upd.size > 0 || copy.size > 0)
      first = tmp()
      head = ta_if(ta_var(first), [ta_set(first, ta_bool(false))], copy + upd)
      brk = ta_if(ta_not(test), [ta_break], nil)
      out.push(ta_set(first, ta_bool(true)))
      return out + loop_out(fr, ta_while(ta_bool(true), [head, brk] + body))
    out + loop_out(fr, ta_while(test, body + copy + upd))

  # The head of a for-in/of: declare-and-bind, or assign, each value.
  -> tr_for_head(s, v, fs)
    a = s.a
    return tr_bind(a.list[0].a, v, fs, true) if a.kind == :var_decl
    tr_bind(a, v, fs, false)

  # for (head in o) body: the keys are listed once; a key deleted before its turn is
  # skipped. A captured let/const head gets a fresh environment per iteration.
  -> tr_for_in(s, sc, labels = [])
    fs = @an.scope_for(s, sc)
    per = fs != sc && fs.has_env?
    out = []
    a = s.a
    if a.kind == :var_decl && a.list[0].b != nil
      # for (var x = init in o): the initializer runs first (Annex B.3.5)
      out = out + tr_bind(a.list[0].a, tr_expr(a.list[0].b, sc), sc, true)
    out = out + scope_entry(fs) if per
    obj = tmp()
    ks = tmp()
    ix = tmp()
    k = tmp()
    out.push(ta_set(obj, tr_expr(s.b, fs)))
    out.push(ta_set(ks, ta_call("js_for_in_keys", [ta_var(obj)])))
    out.push(ta_set(ix, ta_int(0)))
    @next_labels = labels
    fr = push_frame(:loop, s)
    head = tr_for_head(s, ta_var(k), fs)
    body = tr_stmt(s.d, fs)
    pop_frame()
    lb = [ta_set(k, ta_send(ta_var(ks), "\[]", [ta_var(ix)])), ta_set(ix, ta_add(ta_var(ix), ta_int(1)))]
    lb.push(ta_if(ta_not(ta_call("js_for_in_has?", [ta_var(obj), ta_var(k)])), [ta_next], nil))
    lb = lb + scope_entry(fs) if per
    w = ta_while(ta_lt(ta_var(ix), ta_send(ta_var(ks), "size", [])), lb + head + body)
    out + loop_out(fr, w)

  # for (head of v) body. Arrays whose iterator is the intrinsic one are read by index
  # (that iterator has no return method to call); anything else goes through its
  # iterator, closed when the loop is left early or throws.
  -> tr_for_of(s, sc, labels = [])
    fs = @an.scope_for(s, sc)
    per = fs != sc && fs.has_env?
    out = []
    out = out + scope_entry(fs) if per
    v = tmp()
    rec = tmp()
    ix = tmp()
    x = tmp()
    out.push(ta_set(v, tr_expr(s.b, fs)))
    out.push(ta_set(rec, ta_call("js_for_of_iter", [ta_var(v)])))
    out.push(ta_set(ix, ta_int(0)))
    @next_labels = labels
    fr = push_frame(:loop, s)
    fr.close = rec
    head = tr_for_head(s, ta_var(x), fs)
    body = tr_stmt(s.d, fs)
    pop_frame()
    lb = [ta_set(x, ta_call("js_for_of_step", [ta_var(v), ta_var(rec), ta_var(ix)]))]
    lb.push(ta_if(ta_eq(ta_var(x), ta_var("JS_ITER_DONE")), [ta_break], nil))
    lb.push(ta_set(ix, ta_add(ta_var(ix), ta_int(1))))
    lb = lb + scope_entry(fs) if per
    w = ta_while(ta_bool(true), lb + head + body)
    ex = tmp()
    out.push(ta_set(fr.flag, ta_int(0))) if fr.flag != nil
    out.push(ta_begin([w, ta_call("js_for_of_close", [ta_var(rec)])], ex, [ta_call("js_for_of_close_quiet", [ta_var(rec)]), ta_raise(ta_var(ex))]))
    out + loop_checks(fr)

  -> tr_labeled(s, sc, labels)
    a = s.a
    return tr_labeled(a, sc, labels + [a.str]) if a.kind == :labeled
    if a.kind == :for
      return tr_for(a, sc, labels)
    if a.kind == :for_in
      return tr_for_in(a, sc, labels)
    if a.kind == :for_of
      return tr_for_of(a, sc, labels)
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

  # The while node for frame fr (its jump flag cleared first), followed by the checks
  # for jumps that left it.
  -> loop_out(fr, w)
    out = []
    out.push(ta_set(fr.flag, ta_int(0))) if fr.flag != nil
    out.push(w)
    out + loop_checks(fr)

  -> loop_checks(fr)
    out = []
    i = 0
    while i < fr.escapes.size
      out.push(escape_check(fr.escapes[i]))
      i += 1
    out

  # After an inner loop: a pending jump to frame t (one of the enclosing frames).
  -> escape_check(t)
    cur = @frames.size > 0 ? @frames[@frames.size - 1] : nil
    flag = ta_var(t.flag)
    if cur == t
      return ta_if(ta_eq(flag, ta_int(1)), [ta_set(t.flag, ta_int(0)), ta_break], [ta_if(ta_eq(ta_var(t.flag), ta_int(2)), [ta_set(t.flag, ta_int(0)), ta_next], nil)])
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
    # a finally between here and the target runs first: it records the jump, and
    # re-issues it after the finally block
    fi = @frames.size - 1
    while fi > found
      fr = @frames[fi]
      if fr.kind == :finally
        return [ta_set(fr.pk, ta_int(3 + jump_index(fr, s)))] + jump_out(fi)
      fi -= 1
    t = @frames[found]
    t.continue_used = true if cont
    if found == @frames.size - 1
      return [cont ? ta_next : ta_break]
    t.flag = tmp() if t.flag == nil
    inner = @frames[@frames.size - 1]
    inner.escapes.push(t) if !inner.escapes.include?(t)
    [ta_set(t.flag, ta_int(cont ? 2 : 1)), ta_break]

  # Leave frame i's while (from the innermost frame).
  -> jump_out(i)
    return [ta_break] if i == @frames.size - 1
    t = @frames[i]
    t.flag = tmp() if t.flag == nil
    inner = @frames[@frames.size - 1]
    inner.escapes.push(t) if !inner.escapes.include?(t)
    [ta_set(t.flag, ta_int(1)), ta_break]

  # The index of jump statement s among those finally frame fr replays.
  -> jump_index(fr, s)
    i = 0
    while i < fr.jumps.size
      j = fr.jumps[i]
      return i if j.kind == s.kind && j.str == s.str
      i += 1
    fr.jumps.push(s)
    fr.jumps.size - 1

  # Return v (a node) from here: closing the for-of iterators it leaves, or through the
  # innermost finally (whose loop exits close the iterators on the way).
  -> return_value(v)
    closes = []
    i = @frames.size - 1
    while i >= 0
      fr = @frames[i]
      if fr.kind == :finally
        fr.has_return = true
        return [ta_set(fr.pv, v), ta_set(fr.pk, ta_int(2))] + jump_out(i)
      closes.push(ta_call("js_for_of_close", [ta_var(fr.close)])) if fr.close != nil
      i -= 1
    return [emit_return(v)] if closes.size == 0
    t = tmp()
    [ta_set(t, v)] + closes + [emit_return(ta_var(t))]

  # The Tungsten return of a value: a class constructor returns its [[Construct]] result.
  -> emit_return(v)
    return ta_return(v) if !@f.class_ctor
    ta_return(ta_call("js_ctor_result", [v, ctor_this(), ta_bool(@f.derived)]))

  -> ctor_this
    b = @f.this_binding
    return read_binding(b, @f.scope) if b != nil && b.in_env?
    ta_var("this")

  -> tr_try(s, sc)
    return tr_try_catch(s, sc) if s.d == nil
    fr = push_frame(:finally, s)
    fr.pk = tmp()
    fr.pv = tmp()
    inner = s.c != nil ? tr_try_catch(s, sc) : tr_stmt(s.a, sc)
    pop_frame()
    ex = tmp()
    out = [ta_set(fr.pk, ta_int(0)), ta_set(fr.pv, ta_nil)]
    w = ta_while(ta_bool(true), [ta_begin(inner, ex, [ta_set(fr.pk, ta_int(1)), ta_set(fr.pv, ta_var(ex))]), ta_break])
    out = out + loop_out(fr, w)
    out = out + tr_stmt(s.d, sc)
    # replay the pending completion (from outside the finally's frame)
    chain = nil
    j = fr.jumps.size - 1
    while j >= 0
      chain = [ta_if(ta_eq(ta_var(fr.pk), ta_int(3 + j)), tr_jump(fr.jumps[j]), chain)]
      j -= 1
    if fr.has_return
      chain = [ta_if(ta_eq(ta_var(fr.pk), ta_int(2)), return_value(ta_var(fr.pv)), chain)]
    out.push(ta_if(ta_eq(ta_var(fr.pk), ta_int(1)), [ta_raise(ta_var(fr.pv))], chain))
    out

  -> tr_try_catch(s, sc)
    body = tr_stmt(s.a, sc)
    ev = tmp()
    cs = @an.scope_for(s, sc)
    rescue_body = []
    rescue_body = rescue_body + scope_entry(cs) if cs != sc
    if s.b != nil
      if s.b.kind == :ident
        b = cs.names[s.b.str]
        rescue_body.push(write_binding(b, ta_call("js_error_value", [ta_var(ev)]), cs))
      else
        rescue_body = rescue_body + tr_bind(s.b, ta_call("js_error_value", [ta_var(ev)]), cs, true)
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
      body.push(ta_if(ta_le(ta_var(ix), ta_int(i)), tr_stmts(c.list, bs), nil))
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
      return tr_new(e, sc)
    if k == :member
      return tr_member_get(e, sc)
    if k == :function || k == :arrow
      jf = @an.fn_of(e)
      return closure(jf, sc)
    if k == :array
      return tr_array(e, sc)
    if k == :object
      return tr_object(e, sc)
    if k == :template
      return tr_template(e, sc)
    if k == :tagged_template
      return tr_tagged(e, sc)
    if k == :chain
      return tr_chain(e.a, sc)
    if k == :regex
      return ta_call("js_regexp_create", [ta_str(e.str), ta_str(e.a)])
    if k == :bigint
      return ta_call("js_bigint_literal", [ta_str(e.str)])
    if k == :class
      return tr_class(e, sc)
    if k == :meta_property && e.str == "new.target"
      return nt_value(sc)
    @errors.push([@f.index, "expression " + k.to_s])
    ta_nil

  -> tr_ident(e, sc)
    b = binding_of(e.str, sc)
    if b.kind == :global && @an.funcs[0].scope.names[e.str] == b && b.writes == 0
      return ta_nil if e.str == "undefined"
      return ta_num(~0.0 / ~0.0) if e.str == "NaN"
      return ta_num(~1.0 / ~0.0) if e.str == "Infinity"
    read_binding(b, sc)

  -> tr_this(sc)
    f = sc.func
    g = f
    while g.arrow
      g = g.parent
    if g == f || g.script
      # a derived constructor's this lives in its environment when arrows (which may
      # call super()) share it
      b = f.this_binding
      return read_binding(b, sc) if g == f && f.class_ctor && f.derived && b != nil && b.in_env?
      return ta_var("this")
    read_binding(g.this_binding, sc)

  # The running method's own object (for super), where scope sc is.
  -> fo_value(sc)
    f = sc.func
    return ta_var("fobj") if !f.arrow
    g = f
    while g.arrow
      g = g.parent
    return ta_nil if g.script || g.fo_binding == nil
    read_binding(g.fo_binding, sc)

  # new.target where scope sc is.
  -> nt_value(sc)
    f = sc.func
    return ta_var("ntv") if !f.arrow && !f.script
    g = f
    while g.arrow
      g = g.parent
    return ta_nil if g.script || g.nt_binding == nil
    read_binding(g.nt_binding, sc)

  -> tr_binary(e, sc)
    op = e.str
    if e.a.kind == :private_name
      # #x in o
      return ta_call("js_priv_in", [tr_expr(e.b, sc), read_binding(e.a.x.binding, sc)])
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
        if a.a.kind == :super
          return ta_call("js_throw_reference", [ta_str("Unsupported reference to 'super'")])
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
        return assign_binding(b, ta_call(fn, [ta_call("js_tonumeric", [read_binding(b, sc)]), one]), sc)
      get = ta_set(old, ta_call("js_tonumeric", [read_binding(b, sc)]))
      return ta_seq([assign_binding(b, ta_call(fn, [get, one]), sc), ta_var(old)])
    if t.kind == :member
      o = tmp()
      if t.a.kind == :super
        kk = tmp()
        pre_nodes = [ta_set(o, tr_this(sc)), ta_set(kk, tr_super_key(t, sc))]
        get = ta_set(old, ta_call("js_tonumeric", [ta_call("js_super_get", [fo_value(sc), ta_var(kk), ta_var(o)])]))
        set = ta_call("js_super_set", [fo_value(sc), ta_var(kk), ta_call(fn, [get, one]), ta_var(o), ta_bool(@f.strict)])
      elsif t.b.kind == :private_name && !t.has?(F_COMPUTED)
        pre_nodes = [ta_set(o, tr_expr(t.a, sc))]
        get = ta_set(old, ta_call("js_tonumeric", [ta_call("js_priv_get", [ta_var(o), read_binding(t.b.x.binding, sc)])]))
        set = ta_call("js_priv_set", [ta_var(o), read_binding(t.b.x.binding, sc), ta_call(fn, [get, one])])
      elsif t.has?(F_COMPUTED)
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

  -> logical_op?(op)
    op == "&&=" || op == "||=" || op == "??="

  # cur (an assignment node of the current value) && / || / ?? set (the write).
  -> logical_pick(op, cur, t, set)
    if op == "&&="
      return ta_if(ta_call("js_truthy", [cur]), [set], [ta_var(t)])
    if op == "||="
      return ta_if(ta_call("js_truthy", [cur]), [ta_var(t)], [set])
    ta_if(ta_call("js_nullish?", [cur]), [set], [ta_var(t)])

  -> tr_assign(e, sc)
    op = e.str
    t = e.a
    if t.kind == :ident
      b = binding_of(t.str, sc)
      v = nil
      if op == "="
        v = tr_expr_named(e.b, sc, t.str)
      elsif logical_op?(op)
        return tr_logical_assign(e, sc, b)
      else
        v = ta_call(JT_OPS[op.slice(0, op.size - 1)], [read_binding(b, sc), tr_expr(e.b, sc)])
      return assign_binding(b, v, sc)
    if t.kind == :object_pattern || t.kind == :array_pattern
      vt = tmp()
      return ta_seq([ta_set(vt, tr_expr(e.b, sc))] + tr_bind(t, ta_var(vt), sc, false) + [ta_var(vt)])
    if t.kind == :member
      if t.a.kind == :super
        th = tmp()
        kk = tmp()
        pre = [ta_set(th, tr_this(sc)), ta_set(kk, tr_super_key(t, sc))]
        if logical_op?(op)
          cur = tmp()
          get = ta_set(cur, ta_call("js_super_get", [fo_value(sc), ta_var(kk), ta_var(th)]))
          set = ta_call("js_super_set", [fo_value(sc), ta_var(kk), tr_expr(e.b, sc), ta_var(th), ta_bool(@f.strict)])
          return ta_seq(pre + [logical_pick(op, get, cur, set)])
        v = op == "=" ? tr_expr(e.b, sc) : ta_call(JT_OPS[op.slice(0, op.size - 1)], [ta_call("js_super_get", [fo_value(sc), ta_var(kk), ta_var(th)]), tr_expr(e.b, sc)])
        return ta_seq(pre + [ta_call("js_super_set", [fo_value(sc), ta_var(kk), v, ta_var(th), ta_bool(@f.strict)])])
      if t.b.kind == :private_name && !t.has?(F_COMPUTED)
        ot = tmp()
        pre = [ta_set(ot, tr_expr(t.a, sc))]
        if logical_op?(op)
          cur = tmp()
          get = ta_set(cur, ta_call("js_priv_get", [ta_var(ot), read_binding(t.b.x.binding, sc)]))
          set = ta_call("js_priv_set", [ta_var(ot), read_binding(t.b.x.binding, sc), tr_expr(e.b, sc)])
          return ta_seq(pre + [logical_pick(op, get, cur, set)])
        v = op == "=" ? tr_expr(e.b, sc) : ta_call(JT_OPS[op.slice(0, op.size - 1)], [ta_call("js_priv_get", [ta_var(ot), read_binding(t.b.x.binding, sc)]), tr_expr(e.b, sc)])
        return ta_seq(pre + [ta_call("js_priv_set", [ta_var(ot), read_binding(t.b.x.binding, sc), v])])
      if logical_op?(op)
        ot = tmp()
        cur = tmp()
        pre = [ta_set(ot, tr_expr(t.a, sc))]
        if t.has?(F_COMPUTED)
          kt = tmp()
          pre.push(ta_set(kt, ta_call("js_to_property_key", [tr_expr(t.b, sc)])))
          get = ta_set(cur, ta_call("js_getv", [ta_var(ot), ta_var(kt)]))
          set = ta_call("js_setv", [ta_var(ot), ta_var(kt), tr_expr(e.b, sc), ta_bool(@f.strict)])
        else
          get = ta_set(cur, ta_call("js_getv", [ta_var(ot), ta_str(t.b.str)]))
          set = ta_call("js_setv", [ta_var(ot), ta_str(t.b.str), tr_expr(e.b, sc), ta_bool(@f.strict)])
        return ta_seq(pre + [logical_pick(op, get, cur, set)])
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
      return ta_seq([ta_set(ot, o), ta_call("js_setp", [ta_var(ot), ta_str(t.b.str), v, ta_int(site(1))])])
    @errors.push([@f.index, "assignment target"])
    ta_nil

  -> tr_logical_assign(e, sc, b)
    t = tmp()
    cur = ta_set(t, read_binding(b, sc))
    logical_pick(e.str, cur, t, assign_binding(b, tr_expr_named(e.b, sc, e.a.str), sc))

  -> tr_member_get(e, sc)
    if e.a.kind == :super
      return ta_call("js_super_get", [fo_value(sc), tr_super_key(e, sc), tr_this(sc)])
    o = tr_expr(e.a, sc)
    if e.has?(F_COMPUTED)
      return ta_call("js_getv", [o, tr_expr(e.b, sc)])
    if e.b.kind == :private_name
      return ta_call("js_priv_get", [o, read_binding(e.b.x.binding, sc)])
    ta_call("js_getp", [o, ta_str(e.b.str), ta_int(site(1))])

  # The key of super.x / super[x].
  -> tr_super_key(m, sc)
    return ta_call("js_to_property_key", [tr_expr(m.b, sc)]) if m.has?(F_COMPUTED)
    ta_str(m.b.str)

  # Arguments in generic-entry form: [setup nodes, [argc, a0, a1, a2, a3, more]].
  # More than four arguments are evaluated once into temporaries.
  -> call_args(list, sc)
    vals = []
    i = 0
    while i < list.size
      vals.push(tr_expr(list[i], sc))
      i += 1
    call_args_ta(vals)

  # The same for argument nodes already translated.
  -> call_args_ta(vals)
    n = vals.size
    if n <= 4
      a = [ta_int(n)]
      i = 0
      while i < 4
        a.push(i < n ? vals[i] : ta_nil)
        i += 1
      a.push(ta_nil)
      return [[], a]
    pre = []
    names = []
    i = 0
    while i < n
      t = tmp()
      pre.push(ta_set(t, vals[i]))
      names.push(t)
      i += 1
    arr = tmp()
    elems = []
    names.each ->(nm) elems.push(ta_var(nm))
    pre.push(ta_set(arr, ta_array(elems)))
    [pre, [ta_int(n), ta_var(names[0]), ta_var(names[1]), ta_var(names[2]), ta_var(names[3]), ta_var(arr)]]

  -> with_temps(args, call)
    return call if args[0].size == 0
    ta_seq(args[0] + [call])

  -> has_spread?(list)
    i = 0
    while i < list.size
      return true if list[i] != nil && list[i].kind == :spread
      i += 1
    false

  # An argument list with spread elements: [setup nodes, the name of the Array local].
  -> spread_args(list, sc)
    a = tmp()
    pre = [ta_set(a, ta_array([]))]
    i = 0
    while i < list.size
      x = list[i]
      if x.kind == :spread
        pre.push(ta_call("js_append_iterable", [ta_var(a), tr_expr(x.a, sc)]))
      else
        pre.push(ta_send(ta_var(a), "push", [tr_expr(x, sc)]))
      i += 1
    [pre, a]

  # jsd_N called with the arguments in Array local a.
  -> direct_arr_call(jf, first, a)
    ta_call("jsd_" + jf.index.to_s, [first, ta_nil, ta_send(ta_var(a), "size", []), ta_call("js_arg", [ta_var(a), ta_int(0)]), ta_call("js_arg", [ta_var(a), ta_int(1)]), ta_call("js_arg", [ta_var(a), ta_int(2)]), ta_call("js_arg", [ta_var(a), ta_int(3)]), ta_var(a)])

  # What a direct call of the running function from its own body passes as fe.
  -> self_first(jf)
    ta_var(needs_fobj?(jf) ? "fobj" : "fe")

  -> tr_call(e, sc)
    c = e.a
    return tr_super_call(e, sc) if c.kind == :super
    return tr_call_spread(e, sc) if has_spread?(e.list)
    if c.kind == :ident
      args = call_args(e.list, sc)
      b = binding_of(c.str, sc)
      jf = b.fnode
      if jf != nil && jf.fclass == :call_only && !b.global?
        return with_temps(args, ta_call("js_call", [closure(jf, sc), ta_nil] + args[1])) if !compiled?(jf)
        return with_temps(args, ta_call("jsd_" + jf.index.to_s, [env_for(jf, sc), ta_nil] + args[1]))
      if b.kind == :self && b.scope.func == sc.func
        # recursion through a function expression's own name (from its own body)
        return with_temps(args, ta_call("jsd_" + b.scope.func.index.to_s, [self_first(b.scope.func), ta_nil] + args[1]))
      if jf != nil && jf.fclass == :escaping && jf.single == nil && jf.free.size == 0
        # a guess at the callee (the function this name is declared as), checked by code
        return guarded_call(tr_ident(c, sc), jf, args)
      return with_temps(args, ta_call("js_call", [tr_ident(c, sc), ta_nil] + args[1]))
    if (c.kind == :function || c.kind == :arrow)
      jf = @an.fn_of(c)
      if jf != nil && jf.fclass == :iife
        args = call_args(e.list, sc)
        return with_temps(args, ta_call("js_call", [closure(jf, sc), ta_nil] + args[1])) if !compiled?(jf)
        return with_temps(args, ta_call("jsd_" + jf.index.to_s, [env_for(jf, sc), ta_nil] + args[1]))
    if c.kind == :member
      if c.a.kind == :super
        th = tmp()
        ft = tmp()
        pre = [ta_set(th, tr_this(sc)), ta_set(ft, ta_call("js_super_get", [fo_value(sc), tr_super_key(c, sc), ta_var(th)]))]
        args = call_args(e.list, sc)
        return ta_seq(pre + args[0] + [ta_call("js_call", [ta_var(ft), ta_var(th)] + args[1])])
      if c.b.kind == :private_name && !c.has?(F_COMPUTED)
        ot = tmp()
        ft = tmp()
        pre = [ta_set(ot, tr_expr(c.a, sc)), ta_set(ft, ta_call("js_priv_get", [ta_var(ot), read_binding(c.b.x.binding, sc)]))]
        args = call_args(e.list, sc)
        return ta_seq(pre + args[0] + [ta_call("js_call", [ta_var(ft), ta_var(ot)] + args[1])])
      # the callee is read before the arguments are evaluated
      args = call_args(e.list, sc)
      simple = args[0].size == 0 && args[1].all?(->(x) simple_arg?(x))
      if c.has?(F_COMPUTED)
        return with_temps(args, ta_call("js_call_computed", [tr_expr(c.a, sc), tr_expr(c.b, sc)] + args[1])) if simple
        ot = tmp()
        ft = tmp()
        pre = [ta_set(ot, tr_expr(c.a, sc)), ta_set(ft, ta_call("js_getv", [ta_var(ot), tr_expr(c.b, sc)]))]
        return ta_seq(pre + args[0] + [ta_call("js_call", [ta_var(ft), ta_var(ot)] + args[1])])
      return with_temps(args, ta_call("js_call_method", [tr_expr(c.a, sc), ta_str(c.b.str), ta_int(site(1))] + args[1])) if simple
      ot = tmp()
      ft = tmp()
      pre = [ta_set(ot, tr_expr(c.a, sc)), ta_set(ft, ta_call("js_getp", [ta_var(ot), ta_str(c.b.str), ta_int(site(1))]))]
      return ta_seq(pre + args[0] + [ta_call("js_call", [ta_var(ft), ta_var(ot)] + args[1])])
    ft = tmp()
    fx = ta_set(ft, tr_expr(c, sc))
    args = call_args(e.list, sc)
    ta_seq([fx] + args[0] + [ta_call("js_call", [ta_var(ft), ta_nil] + args[1])])

  # f(...args), o.m(...args): the arguments gathered into an Array first.
  -> tr_call_spread(e, sc)
    c = e.a
    if c.kind == :member
      ot = tmp()
      ft = tmp()
      pre = []
      if c.a.kind == :super
        pre.push(ta_set(ot, tr_this(sc)))
        pre.push(ta_set(ft, ta_call("js_super_get", [fo_value(sc), tr_super_key(c, sc), ta_var(ot)])))
      elsif c.b.kind == :private_name && !c.has?(F_COMPUTED)
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_priv_get", [ta_var(ot), read_binding(c.b.x.binding, sc)])))
      elsif c.has?(F_COMPUTED)
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_getv", [ta_var(ot), tr_expr(c.b, sc)])))
      else
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_getp", [ta_var(ot), ta_str(c.b.str), ta_int(site(1))])))
      args = spread_args(e.list, sc)
      return ta_seq(pre + args[0] + [ta_call("js_call_arr", [ta_var(ft), ta_var(ot), ta_var(args[1])])])
    if c.kind == :ident
      b = binding_of(c.str, sc)
      jf = b.fnode
      if jf != nil && jf.fclass == :call_only && !b.global? && compiled?(jf)
        args = spread_args(e.list, sc)
        return ta_seq(args[0] + [direct_arr_call(jf, env_for(jf, sc), args[1])])
      if b.kind == :self && b.scope.func == sc.func
        args = spread_args(e.list, sc)
        return ta_seq(args[0] + [direct_arr_call(b.scope.func, self_first(b.scope.func), args[1])])
    if c.kind == :function || c.kind == :arrow
      jf = @an.fn_of(c)
      if jf != nil && jf.fclass == :iife && compiled?(jf)
        args = spread_args(e.list, sc)
        return ta_seq(args[0] + [direct_arr_call(jf, env_for(jf, sc), args[1])])
    ft = tmp()
    fv = nil
    if c.kind == :ident
      b = binding_of(c.str, sc)
      jf = b.fnode
      fv = (jf != nil && jf.fclass == :call_only && !b.global?) ? closure(jf, sc) : tr_ident(c, sc)
    else
      fv = tr_expr(c, sc)
    args = spread_args(e.list, sc)
    ta_seq([ta_set(ft, fv)] + args[0] + [ta_call("js_call_arr", [ta_var(ft), ta_nil, ta_var(args[1])])])

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
        vals.push(t)
      else
        vals.push(x)
      i += 1
    dvals = []
    gvals = []
    vals.each ->(v)
      if v.is_a?(String)
        dvals.push(ta_var(v))
        gvals.push(ta_var(v))
      else
        dvals.push(v)
        gvals.push(v)
    first = needs_fobj?(jf) ? ta_var(ft) : ta_nil
    direct = ta_call("jsd_" + jf.index.to_s, [first, ta_nil] + dvals)
    generic = ta_call("js_call", [ta_var(ft), ta_nil] + gvals)
    return ta_seq(pre + [generic]) if !compiled?(jf)
    ta_seq(pre + [ta_if(ta_call("js_code_is?", [ta_var(ft), ta_var("JSC_" + jf.index.to_s)]), [direct], [generic])])

  -> simple_arg?(x)
    k = ast_kind(x)
    k == :var || k == :nil_lit || k == :int || k == :float || k == :string || k == :bool

  -> tr_new(e, sc)
    if has_spread?(e.list)
      ft = tmp()
      pre = [ta_set(ft, tr_expr(e.a, sc))]
      args = spread_args(e.list, sc)
      return ta_seq(pre + args[0] + [ta_call("js_new_arr", [ta_var(ft), ta_var(args[1])])])
    args = call_args(e.list, sc)
    with_temps(args, ta_call("js_new", [tr_expr(e.a, sc), ta_int(site(2))] + args[1]))

  # super(args) in a derived constructor (or an arrow in one): the parent constructs the
  # object, this is bound once, then the fields are initialized.
  -> tr_super_call(e, sc)
    pre = []
    av = nil
    if has_spread?(e.list)
      args = spread_args(e.list, sc)
      pre = args[0]
      av = ta_var(args[1])
    else
      vals = []
      e.list.each ->(x) vals.push(tr_expr(x, sc))
      av = ta_array(vals)
    obj = tmp()
    out = pre + [ta_set(obj, ta_call("js_super_construct", [fo_value(sc), nt_value(sc), av]))]
    f = sc.func
    g = f
    while g.arrow
      g = g.parent
    b = g.this_binding
    if !f.arrow && (b == nil || !b.in_env?)
      out.push(ta_call("js_super_bound", [ta_var("this")]))
      out.push(ta_set("this", ta_var(obj)))
    else
      out.push(ta_call("js_super_bound", [read_binding(b, sc)]))
      out.push(write_binding(b, ta_var(obj), sc))
      out.push(ta_set("this", ta_var(obj))) if !f.arrow
    out.push(ta_call("js_init_fields", [ta_var(obj), fo_value(sc)]))
    out.push(ta_var(obj))
    ta_seq(out)

  -> tr_array(e, sc)
    if has_spread?(e.list)
      a = tmp()
      out = [ta_set(a, ta_array([]))]
      holes = false
      i = 0
      while i < e.list.size
        x = e.list[i]
        if x == nil
          holes = true
          out.push(ta_send(ta_var(a), "push", [ta_var("JS_HOLE")]))
        elsif x.kind == :spread
          out.push(ta_call("js_append_iterable", [ta_var(a), tr_expr(x.a, sc)]))
        else
          out.push(ta_send(ta_var(a), "push", [tr_expr(x, sc)]))
        i += 1
      out.push(ta_call(holes ? "js_mark_holey" : "js_mark_array", [ta_var(a)]))
      return ta_seq(out)
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

  # An object literal with distinct static keys and plain values (or methods): one
  # allocation with the site's final shape (computed once at start) and the values
  # stored straight into slots. Anything else is built property by property.
  -> tr_object(e, sc)
    keys = []
    plain = true
    i = 0
    while i < e.list.size
      p = e.list[i]
      if p.kind != :prop || p.str != "init" || p.has?(F_COMPUTED)
        plain = false
      else
        key = prop_key(p.a)
        plain = false if key == nil || key == "__proto__" || keys.include?(key)
        keys.push(key)
      i += 1
    return tr_object_general(e, sc) if !plain
    vals = []
    i = 0
    while i < e.list.size
      vals.push(tr_expr_named(e.list[i].b, sc, keys[i]))
      i += 1
    si = @lit_shapes.size
    @lit_shapes.push(keys)
    if vals.size <= 6
      while vals.size < 6
        vals.push(ta_nil)
      return ta_call("js_lit", [ta_var("JSS_" + si.to_s)] + vals)
    ta_call("js_lit_n", [ta_var("JSS_" + si.to_s), ta_array(vals)])

  # tier 0's wk_object: spread, accessors, computed keys, __proto__.
  -> tr_object_general(e, sc)
    o = tmp()
    out = [ta_set(o, ta_call("js_new_object", [ta_object_proto()]))]
    i = 0
    while i < e.list.size
      p = e.list[i]
      if p.kind == :spread
        out.push(ta_call("js_copy_data_properties", [ta_var(o), tr_expr(p.a, sc), ta_var("JS_NO_ARGS")]))
      else
        comp = p.has?(F_COMPUTED)
        kt = nil
        if comp
          kt = tmp()
          out.push(ta_set(kt, ta_call("js_to_property_key", [tr_expr(p.a, sc)])))
        kind = p.str
        if kind == "get" || kind == "set"
          ft = tmp()
          out.push(ta_set(ft, tr_expr(p.b, sc)))
          out.push(ta_call("js_set_fn_name", [ta_var(ft), ta_var(kt), ta_str(kind)])) if comp
          out.push(ta_call("js_lit_accessor", [ta_var(o), comp ? ta_var(kt) : static_key(p.a), ta_var(ft), ta_bool(kind == "get")]))
        elsif !comp && !p.has?(F_SHORTHAND) && !p.has?(F_METHOD) && prop_key(p.a) == "__proto__"
          out.push(ta_call("js_lit_proto", [ta_var(o), tr_expr(p.b, sc)]))
        elsif comp && (p.b.kind == :function || p.b.kind == :arrow) && p.b.str == nil
          vt = tmp()
          out.push(ta_set(vt, tr_expr(p.b, sc)))
          out.push(ta_call("js_set_fn_name", [ta_var(vt), ta_var(kt), ta_nil]))
          out.push(ta_call("js_define_literal", [ta_var(o), ta_var(kt), ta_var(vt)]))
        else
          out.push(ta_call("js_define_literal", [ta_var(o), comp ? ta_var(kt) : static_key(p.a), tr_expr(p.b, sc)]))
      i += 1
    out.push(ta_var(o))
    ta_seq(out)

  -> prop_key(a)
    return a.str if a.kind == :ident || a.kind == :string
    if a.kind == :num
      x = a.a
      return x.to_i.to_s if x == Math.floor(x) && x >= ~0.0 && x < ~9007199254740992.0
    nil

  # `a${x}b`: the cooked strings and ToString of each substitution, concatenated.
  -> tr_template(e, sc)
    parts = []
    i = 0
    while i < e.list.size
      q = e.list[i].str
      parts.push(ta_str(q)) if q != nil && q != ""
      parts.push(ta_call("js_template_string", [tr_expr(e.a[i], sc)])) if i < e.a.size
      i += 1
    return ta_str("") if parts.size == 0
    r = parts[0]
    i = 1
    while i < parts.size
      r = ta_call("js_str_cat", [r, parts[i]])
      i += 1
    r

  # tag`a${x}b`: tag(template object, x), with this = the object for a member tag.
  -> tr_tagged(e, sc)
    t = e.b
    ti = @templates.size
    @templates.push(t)
    c = e.a
    pre = []
    ft = tmp()
    this = nil
    if c.kind == :member
      ot = tmp()
      if c.a.kind == :super
        pre.push(ta_set(ot, tr_this(sc)))
        pre.push(ta_set(ft, ta_call("js_super_get", [fo_value(sc), tr_super_key(c, sc), ta_var(ot)])))
      elsif c.b.kind == :private_name && !c.has?(F_COMPUTED)
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_priv_get", [ta_var(ot), read_binding(c.b.x.binding, sc)])))
      elsif c.has?(F_COMPUTED)
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_getv", [ta_var(ot), tr_expr(c.b, sc)])))
      else
        pre.push(ta_set(ot, tr_expr(c.a, sc)))
        pre.push(ta_set(ft, ta_call("js_getp", [ta_var(ot), ta_str(c.b.str), ta_int(site(1))])))
      this = ot
    else
      pre.push(ta_set(ft, tr_expr(c, sc)))
    vals = [ta_var("JSTO_" + ti.to_s)]
    t.a.each ->(x) vals.push(tr_expr(x, sc))
    args = call_args_ta(vals)
    ta_seq(pre + args[0] + [ta_call("js_call", [ta_var(ft), this == nil ? ta_nil : ta_var(this)] + args[1])])

  # An optional chain (the expression inside a :chain): the links from the base outward,
  # each into a temporary; a ?. link whose left side is null or undefined makes the rest
  # of the chain undefined.
  -> tr_chain(e, sc)
    links = []
    x = e
    going = true
    while going
      if x.kind == :member && x.a.kind != :super
        links.push(x)
        x = x.a
      elsif x.kind == :call && x.a.kind != :super && (x.has?(F_OPTIONAL) || x.a.kind != :ident)
        links.push(x)
        x = x.a
      else
        going = false
    base = x
    links = links.reverse
    n = links.size
    temps = []
    i = 0
    while i <= n
      temps.push(tmp())
      i += 1
    inner = [ta_var(temps[n])]
    i = n
    while i >= 1
      l = links[i - 1]
      prev = temps[i - 1]
      v = nil
      if l.kind == :member
        if l.has?(F_COMPUTED)
          v = ta_call("js_getv", [ta_var(prev), tr_expr(l.b, sc)])
        elsif l.b.kind == :private_name
          v = ta_call("js_priv_get", [ta_var(prev), read_binding(l.b.x.binding, sc)])
        else
          v = ta_call("js_getp", [ta_var(prev), ta_str(l.b.str), ta_int(site(1))])
      else
        this = ta_nil
        if i >= 2 && links[i - 2].kind == :member
          this = ta_var(temps[i - 2])
        elsif i == 1 && base.kind == :member && base.a.kind == :super
          this = tr_this(sc)
        if has_spread?(l.list)
          args = spread_args(l.list, sc)
          v = ta_seq(args[0] + [ta_call("js_call_arr", [ta_var(prev), this, ta_var(args[1])])])
        else
          args = call_args(l.list, sc)
          v = with_temps(args, ta_call("js_call", [ta_var(prev), this] + args[1]))
      st = ta_set(temps[i], v)
      if l.has?(F_OPTIONAL)
        inner = [ta_if(ta_call("js_nullish?", [ta_var(prev)]), [ta_nil], [st] + inner)]
      else
        inner = [st] + inner
      i -= 1
    ta_seq([ta_set(temps[0], tr_expr(base, sc))] + inner)

  # A class (tier 0's wk_class): its scope's private names, the constructor and
  # prototype, the elements in order, the inner name, then the static fields and blocks.
  -> tr_class(n, sc)
    cs = @an.scope_for(n, sc)
    out = []
    out = out + scope_entry(cs) if cs != sc
    i = 0
    while i < cs.order.size
      b = cs.order[i]
      if b.kind == :private
        out.push(write_binding(b, ta_new("JS:PrivateName", [ta_str(b.name.slice(1, b.name.size - 1))]), cs))
      i += 1
    sup = nil
    if n.a != nil
      sup = tmp()
      out.push(ta_set(sup, tr_expr(n.a, cs)))
    cjf = n.d.x
    f = tmp()
    proto = tmp()
    out.push(ta_set(f, ta_call("js_class_create", [code_ref(cjf), env_for(cjf, cs), ta_bool(n.a != nil), sup == nil ? ta_nil : ta_var(sup)])))
    out.push(ta_set(proto, ta_call("js_home", [ta_var(f)])))
    statics = []
    i = 0
    while i < n.list.size
      m = n.list[i]
      st = m.has?(F_STATIC)
      tgt = st ? f : proto
      if m.kind == :method_def && m.str != "constructor"
        jf = m.b.x
        fo = ta_call("js_method_closure", [code_ref(jf), env_for(jf, cs), ta_var(tgt)])
        if m.a.kind == :private_name
          out.push(ta_call("js_class_priv_method", [ta_var(f), ta_bool(st), read_binding(m.a.x.binding, cs), fo, ta_str(m.str)]))
        else
          fv = tmp()
          out.push(ta_set(fv, fo))
          key = m.has?(F_COMPUTED) ? ta_call("js_to_property_key", [tr_expr(m.a, cs)]) : static_key(m.a)
          out.push(ta_call("js_class_method", [ta_var(tgt), key, ta_var(fv), ta_str(m.str), ta_bool(m.has?(F_COMPUTED))]))
      elsif m.kind == :field_def
        kt = tmp()
        if m.a.kind == :private_name
          out.push(ta_set(kt, read_binding(m.a.x.binding, cs)))
        elsif m.has?(F_COMPUTED)
          out.push(ta_set(kt, ta_call("js_to_property_key", [tr_expr(m.a, cs)])))
        else
          out.push(ta_set(kt, static_key(m.a)))
        init = m.x == nil ? ta_nil : ta_call("js_method_closure", [code_ref(m.x), env_for(m.x, cs), ta_var(tgt)])
        if st
          it = tmp()
          out.push(ta_set(it, init))
          statics.push([kt, it, false])
        else
          out.push(ta_call("js_class_add_field", [ta_var(f), ta_var(kt), init]))
      elsif m.kind == :static_block
        it = tmp()
        out.push(ta_set(it, ta_call("js_method_closure", [code_ref(m.x), env_for(m.x, cs), ta_var(f)])))
        statics.push([nil, it, true])
      i += 1
    out.push(write_binding(cs.names[n.str], ta_var(f), cs)) if n.str != nil
    i = 0
    while i < statics.size
      se = statics[i]
      if se[2]
        out.push(ta_call("js_call", [ta_var(se[1]), ta_var(f), ta_int(0), ta_nil, ta_nil, ta_nil, ta_nil, ta_nil]))
      else
        out.push(ta_call("js_class_static_field", [ta_var(f), ta_var(se[0]), ta_var(se[1])]))
      i += 1
    out.push(ta_var(f))
    ta_seq(out)
