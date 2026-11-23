# tier0/walk — tier 0: a tree-walking interpreter over the analysed JsNode AST.
#
# It shares everything with tier 1 but the control flow: the analysis (analyze.w) owns the
# binding layout — locals live in the activation's array at their binding's lidx, captured
# bindings in JS:Env slots, globals in cells — and every operation calls the same runtime
# functions compiled code calls. So a function object made here can be called by compiled
# code and the reverse, over the same environments. Nothing is allocated per node.
#
#   wk_run(src, url)             # parse, analyse and run a classic script
#
# Completion: a statement leaves act.sig set to WK_BREAK / WK_CONTINUE / WK_RETURN (with
# act.label, act.rv); throw is a Tungsten raise of JS:Throw.

use ../frontend/parser
use ../analyze

WK_NONE = 0
WK_BREAK = 1
WK_CONTINUE = 2
WK_RETURN = 3

+ WkAct
  rw :f, :fobj, :fe, :this, :locals, :env, :argc, :args, :nt, :sig, :label, :rv, :env_at_entry

  -> new(@f, @fobj, @fe, @this, n)
    @locals = Array.new(n, nil)
    @env = @fe
    @argc = 0
    @args = nil
    @nt = nil
    @sig = 0
    @label = nil
    @rv = nil
    @env_at_entry = nil

  -> reset(f, fobj, fe, this, n)
    @f = f
    @fobj = fobj
    @fe = fe
    @this = this
    @env = fe
    @argc = 0
    @args = nil
    @nt = nil
    @sig = 0
    @label = nil
    @rv = nil
    @env_at_entry = nil
    l = @locals
    while l.size > n
      l.pop
    i = 0
    while i < l.size
      l[i] = nil
      i += 1
    while l.size < n
      l.push(nil)
    self

# Activations are reused: a call takes one from the pool and returns it when it returns
# normally (an exception leaves it to be dropped). Nothing else ever holds an activation.
# TODO(js-aot): per thread once workers run tier 0.
WK_POOL = []

-> wk_act(f, fobj, fe, this, n)
  return WK_POOL.pop.reset(f, fobj, fe, this, n) if WK_POOL.size > 0
  WkAct.new(f, fobj, fe, this, n)

-> wk_release(act)
  if WK_POOL.size < 256
    act.reset(nil, nil, nil, nil, 0)
    WK_POOL.push(act)
  nil

# The JS:Code of an analysed function (one per function per script; index -1: tier 0).
-> wk_code(jf)
  c = jf.code
  if c == nil
    ctor = !jf.arrow && !jf.script && (jf.method_kind == nil || jf.class_ctor) && !jf.field_init
    flags = (jf.strict ? CODE_STRICT : 0) + (jf.arrow ? CODE_ARROW : 0) + (ctor ? CODE_CTOR : 0) + (jf.class_ctor ? CODE_CLASS : 0) + (jf.class_ctor && jf.derived ? CODE_DERIVED : 0)
    c = JS:Code.new(jf.name, jf.nparams, -1, flags)
    c.node = jf
    jf.code = c
  c

# ---- running scripts ----

-> wk_run(src, url)
  p = JsParser.new(src, false)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.to_s))
  an = JaAnalysis.new(prog, false).run
  bad = []
  an.funcs.each ->(f) bad.push(f.unsupported0) if f.unsupported0 != nil
  js_throw(js_make_error("SyntaxError", "tier 0 cannot run this yet: " + bad[0].to_s)) if bad.size > 0
  f = an.funcs[0]
  act = wk_act(f, nil, nil, nil, f.nlocals)
  wk_hoist_script(f, act)
  wk_hoist_functions(prog.list, act)
  wk_stmts(prog.list, act)
  act.rv

-> wk_hoist_script(f, act)
  vn = f.script ? JaAnalysis.new(nil, false).var_names(f.node.list, [], f.strict, true) : []
  i = 0
  while i < vn.size
    js_gdeclare(js_gcell(vn[i]), nil, false)
    i += 1
  nil

# ---- calls into tier 0 ----

# The entry js_dispatch uses for a function with no native code.
-> wk_call(f, this, argc, a0, a1, a2, a3, more)
  jf = f.code.node
  nt = JS_NEW_TARGET[0]
  JS_NEW_TARGET[0] = nil
  js_throw_type("Class constructor " + jf.name + " cannot be invoked without 'new'") if jf.class_ctor && nt == nil
  act = wk_act(jf, f, js_fenv(f), this, jf.nlocals)
  act.argc = argc
  act.args = more
  act.nt = nt
  if jf.class_ctor
    r = wk_construct_body(jf, act, argc, a0, a1, a2, a3, more)
  else
    r = wk_enter(jf, act, argc, a0, a1, a2, a3, more)
  wk_release(act)
  r

# A class constructor's body under [[Construct]] (§10.2.2): a base class initializes its
# fields on the new object first; a derived one gets `this` from super(). The result is
# the returned object, else this.
-> wk_construct_body(jf, act, argc, a0, a1, a2, a3, more)
  if jf.default_ctor
    if jf.derived
      parent = act.fobj.get_prototype_of
      js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
      obj = js_construct(parent, js_args_array(argc, a0, a1, a2, a3, more).dup, act.nt)
      js_init_fields(obj, act.fobj)
      return obj
    js_init_fields(act.this, act.fobj)
    return act.this
  js_init_fields(act.this, act.fobj) if !jf.derived
  r = wk_enter(jf, act, argc, a0, a1, a2, a3, more)
  return r if js_object?(r)
  js_throw_type("Derived constructors may only return object or undefined") if jf.derived && r != nil
  t = wk_this_value(jf, act)
  js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor") if t == nil
  t

# The current this of a function's activation (its environment slot when arrows use it).
-> wk_this_value(jf, act)
  b = jf.this_binding
  return js_env_get(act.env_at_entry, b.slot) if b != nil && b.slot >= 0
  act.this

-> wk_enter(jf, act, argc, a0, a1, a2, a3, more)
  if jf.uses_this && !jf.strict && !jf.arrow
    act.this = js_sloppy_this(act.this)
  sc = jf.scope
  wk_scope_enter(sc, act)
  act.env_at_entry = act.env
  if jf.this_binding != nil && jf.this_binding.in_env?
    wk_write(jf.this_binding, act.this, act)
  wk_write(jf.nt_binding, act.nt, act) if jf.nt_binding != nil
  wk_write(jf.fo_binding, act.fobj, act) if jf.fo_binding != nil
  if jf.args_binding != nil
    args = js_args_array(argc, a0, a1, a2, a3, more)
    slots = []
    jf.params.each ->(b) slots.push(b.slot)
    wk_write(jf.args_binding, js_arguments(args.dup, act.fobj, jf.mapped_args, act.env, slots), act)
  if jf.simple
    i = 0
    while i < jf.params.size
      v = i == 0 ? a0 : (i == 1 ? a1 : (i == 2 ? a2 : (i == 3 ? a3 : (argc > i ? more[i] : nil))))
      v = nil if i >= argc
      wk_write(jf.params[i], v, act)
      i += 1
  else
    wk_bind_params(jf, act, argc, a0, a1, a2, a3, more)
  n = jf.node
  if jf.arrow && n.has?(F_EXPR_BODY)
    return wk_ev(n.b, act)
  bs = jf.body_scope
  if bs != sc
    wk_scope_enter(bs, act)
    jf.param_copies.each ->(pc) wk_write(pc[1], wk_read_binding_from(pc[0], bs, act), act)
  wk_hoist_functions(n.b, act)
  wk_stmts(n.b, act)
  act.sig == WK_RETURN ? act.rv : nil

# A non-simple parameter list: defaults, patterns and a rest element, in order.
-> wk_bind_params(jf, act, argc, a0, a1, a2, a3, more)
  ps = jf.param_nodes
  i = 0
  while i < ps.size
    p = ps[i]
    if p.kind == :rest
      rest = []
      j = i
      while j < argc
        rest.push(j == 0 ? a0 : (j == 1 ? a1 : (j == 2 ? a2 : (j == 3 ? a3 : more[j]))))
        j += 1
      wk_bind(p.a, js_mark_array(rest), act, true)
    else
      v = i >= argc ? nil : (i == 0 ? a0 : (i == 1 ? a1 : (i == 2 ? a2 : (i == 3 ? a3 : more[i]))))
      wk_bind(p, v, act, true)
    i += 1
  nil

# ---- patterns ----

# Bind or assign value v to pattern p. decl: p's identifiers are declarations being
# initialized (else assignment targets, which may also be members).
-> wk_bind(p, v, act, decl)
  k = p.kind
  if k == :ident
    wk_write_ref(p.x, v, act, decl)
  elsif k == :assign_pattern
    v = wk_ev(p.b, act) if v == nil
    wk_bind(p.a, v, act, decl)
  elsif k == :member
    o = wk_ev(p.a, act)
    key = p.has?(F_COMPUTED) ? js_to_property_key(wk_ev(p.b, act)) : p.b.str
    js_setv(o, key, v, act.f.strict)
  elsif k == :array_pattern
    wk_bind_array(p, v, act, decl)
  elsif k == :object_pattern
    wk_bind_object(p, v, act, decl)
  else
    js_throw(js_make_error("SyntaxError", "tier 0: pattern " + k.to_s))
  nil

-> wk_bind_array(p, v, act, decl)
  rec = js_get_iterator(v)
  begin
    i = 0
    while i < p.list.size
      e = p.list[i]
      if e != nil && e.kind == :rest
        rest = []
        while !rec.done
          x = js_iter_step(rec)
          rest.push(x) if x != JS_ITER_DONE
        wk_bind(e.a, js_mark_array(rest), act, decl)
      else
        x = rec.done ? JS_ITER_DONE : js_iter_step(rec)
        x = nil if x == JS_ITER_DONE
        wk_bind(e, x, act, decl) if e != nil
      i += 1
  rescue ex
    js_iter_close_quiet(rec)
    raise ex
  js_iter_close(rec) if !rec.done
  nil

-> wk_bind_object(p, v, act, decl)
  js_throw_type("Cannot destructure '" + js_to_display(v) + "' as it is " + (v == nil ? "undefined" : "null") + ".") if js_nullish?(v)
  used = []
  i = 0
  while i < p.list.size
    e = p.list[i]
    if e.kind == :rest
      o = js_new_object(js_realm().object_proto)
      src = js_object?(v) ? v : js_realm().wrap_primitive(v)
      ks = jown_keys(src)
      j = 0
      while j < ks.size
        kk = ks[j]
        if !used.include?(kk) && jenumerable?(src, kk)
          o.define(kk, jget(src, kk, v), ATTR_DEFAULT)
        j += 1
      wk_bind(e.a, o, act, decl)
    else
      key = e.has?(F_COMPUTED) ? js_to_property_key(wk_ev(e.a, act)) : wk_prop_key(e.a)
      used.push(key)
      wk_bind(e.b, js_get_value(v, key), act, decl)
    i += 1
  nil

# A property key written in the source (identifier, string or number).
-> wk_prop_key(a)
  return js_number_to_s(a.a) if a.kind == :num
  return a.str if a.kind == :ident || a.kind == :string
  return a.str if a.kind == :bigint
  js_throw(js_make_error("SyntaxError", "tier 0: key " + a.kind.to_s))

# Entering a scope with an environment record.
-> wk_scope_enter(sc, act)
  return nil if !sc.has_env?
  e = sc.env_count > 7 ? JS:EnvN.new(act.env, sc.env_count) : JS:Env.new(act.env)
  act.env = e
  nil

# ---- bindings ----

-> wk_env_at(act, hops)
  e = act.env
  while hops > 0
    e = js_env_up(e)
    hops -= 1
  e

-> wk_hops(ref)
  h = ref.hops
  if h == nil
    h = ref.scope.func.analysis.env_hops(ref.scope, ref.binding.scope)
    ref.hops = h
  h

-> wk_const?(b)
  b.writes <= 1 && b.decl_const == true

-> wk_cell(b)
  c = b.cell
  if c == nil
    c = b.kind == :lexical ? js_lcell(b.name) : js_gcell(b.name)
    b.cell = c
  c

-> wk_read_ref(ref, act)
  b = ref.binding
  return js_gget(wk_cell(b)) if b.global?
  if b.scope.func != act.f
    return act.fe if act.f.single == b
    return js_env_get(wk_env_at(act, wk_hops(ref)), b.slot)
  return js_env_get(wk_env_at(act, wk_hops(ref)), b.slot) if b.slot >= 0
  return act.this if b.kind == :this
  act.locals[b.lidx]

-> wk_write_ref(ref, v, act, init = false)
  b = ref.binding
  if b.kind == :lexical
    return init ? js_linit(wk_cell(b), v, wk_const?(b)) : js_lset(wk_cell(b), v)
  return js_gset(wk_cell(b), v, act.f.strict) if b.global?
  if b.slot >= 0
    js_env_set(wk_env_at(act, wk_hops(ref)), b.slot, v)
    return v
  act.locals[b.lidx] = v
  v

# A write to a binding declared in the current function at the current point (params,
# hoisted functions): its scope's environment is the innermost one.
-> wk_write(b, v, act)
  return js_gset(wk_cell(b), v, act.f.strict) if b.global?
  if b.slot >= 0
    js_env_set(act.env, b.slot, v)
    return v
  act.locals[b.lidx] = v
  v

# ---- hoisting ----

-> wk_hoist_functions(stmts, act)
  i = 0
  while i < stmts.size
    s = stmts[i]
    if s.kind == :function_decl && s.str != nil
      jf = s.x
      b = jf.binding
      fo = js_closure(wk_code(jf), wk_env_for(jf, act))
      if b.global?
        js_gdeclare(wk_cell(b), fo, true)
      else
        wk_write_decl(jf, fo, act)
    i += 1
  nil

# A function declaration's binding gets its object (seen from where it is declared).
-> wk_write_decl(jf, v, act)
  b = jf.binding
  return js_gset(wk_cell(b), v, act.f.strict) if b.global?
  if b.slot >= 0
    js_env_set(wk_env_at(act, act.f.analysis.env_hops(jf.def_scope, b.scope)), b.slot, v)
    return v
  act.locals[b.lidx] = v
  v

# What jf's fe is when created now (tier 0 makes every function an object).
-> wk_env_for(jf, act)
  if jf.single != nil
    return wk_read_single(jf, act)
  return nil if jf.free.size == 0
  t = jf.def_scope
  while t != nil && !t.has_env?
    t = t.parent
  return nil if t == nil
  wk_env_at(act, act.f.analysis.env_hops(jf.def_scope, t))

-> wk_read_binding_from(b, sc, act)
  wk_read_ref(JaRef.new(b, sc), act)

# The value of jf's single captured binding, read where jf is created (its JaRef is made
# once and kept on the function).
-> wk_read_single(jf, act)
  r = jf.single_ref
  if r == nil
    r = JaRef.new(jf.single, jf.def_scope)
    jf.single_ref = r
  wk_read_ref(r, act)

# ---- statements ----

-> wk_stmts(list, act)
  i = 0
  n = list.size
  while i < n
    wk_ex(list[i], act)
    return nil if act.sig != 0
    i += 1
  nil

-> wk_ex(s, act)
  k = s.kind
  if k == :expr_stmt
    wk_ev(s.a, act)
  elsif k == :var_decl
    i = 0
    while i < s.list.size
      d = s.list[i]
      if d.a.kind != :ident
        wk_bind(d.a, wk_ev(d.b, act), act, s.str != "var")
      elsif d.b != nil
        wk_write_ref(d.a.x, wk_ev(d.b, act), act, s.str != "var")
      elsif s.str != "var"
        wk_write_ref(d.a.x, nil, act, true)
      i += 1
  elsif k == :if
    if js_truthy(wk_ev(s.a, act))
      wk_ex(s.b, act)
    elsif s.c != nil
      wk_ex(s.c, act)
  elsif k == :block
    wk_block(s, s.list, act)
  elsif k == :return
    act.rv = s.a == nil ? nil : wk_ev(s.a, act)
    act.sig = WK_RETURN
  elsif k == :for
    wk_for(s, act, nil)
  elsif k == :while
    wk_while(s, act, nil)
  elsif k == :do_while
    wk_do_while(s, act, nil)
  elsif k == :break
    act.sig = WK_BREAK
    act.label = s.str
  elsif k == :continue
    act.sig = WK_CONTINUE
    act.label = s.str
  elsif k == :throw
    js_throw(wk_ev(s.a, act))
  elsif k == :try
    wk_try(s, act)
  elsif k == :function_decl
    jf = s.x
    if jf.in_if && jf.binding != nil
      wk_write_decl(jf, js_closure(wk_code(jf), wk_env_for(jf, act)), act)
    elsif jf.annexb != nil
      # Annex B: evaluating the declaration copies the block's binding into the var
      v = wk_read_binding_from(jf.binding, jf.def_scope, act)
      wk_write_ref(JaRef.new(jf.annexb, jf.def_scope), v, act)
  elsif k == :switch
    wk_switch(s, act, nil)
  elsif k == :class_decl
    wk_write_ref(s.c, wk_class(s, act), act, true)
  elsif k == :for_in
    wk_for_in(s, act, nil)
  elsif k == :for_of
    wk_for_of(s, act, nil)
  elsif k == :labeled
    wk_labeled(s, act, [s.str])
  elsif k == :empty || k == :debugger
    nil
  else
    js_throw(js_make_error("SyntaxError", "tier 0: statement " + k.to_s))
  nil

-> wk_block(node, list, act)
  sc = node.x
  saved = act.env
  if sc.is_a?(JaScope)
    wk_scope_enter(sc, act)
  wk_hoist_functions(list, act)
  wk_stmts(list, act)
  act.env = saved
  nil

# Did a break/continue (act.sig) end at this loop? Clears it when so.
-> wk_loop_signal(act, labels)
  sg = act.sig
  return 0 if sg == 0
  if sg == WK_BREAK || sg == WK_CONTINUE
    if act.label == nil || (labels != nil && labels.include?(act.label))
      act.sig = 0
      act.label = nil
      return sg
  WK_RETURN

-> wk_while(s, act, labels)
  while js_truthy(wk_ev(s.a, act))
    wk_ex(s.b, act)
    r = wk_loop_signal(act, labels)
    return nil if r == WK_RETURN
    break if r == WK_BREAK
  nil

-> wk_do_while(s, act, labels)
  while true
    wk_ex(s.a, act)
    r = wk_loop_signal(act, labels)
    return nil if r == WK_RETURN
    break if r == WK_BREAK
    break if !js_truthy(wk_ev(s.b, act))
  nil

-> wk_for(s, act, labels)
  fs = s.x
  saved = act.env
  per = fs.is_a?(JaScope) && fs.has_env?
  wk_scope_enter(fs, act) if fs.is_a?(JaScope)
  if s.a != nil
    if s.a.kind == :var_decl
      wk_ex(s.a, act)
    else
      wk_ev(s.a, act)
  act.env = js_env_copy(act.env) if per
  while s.b == nil || js_truthy(wk_ev(s.b, act))
    wk_ex(s.d, act)
    r = wk_loop_signal(act, labels)
    if r == WK_RETURN
      act.env = saved
      return nil
    break if r == WK_BREAK
    act.env = js_env_copy(act.env) if per
    wk_ev(s.c, act) if s.c != nil
  act.env = saved
  nil

# The head of a for-in/of: declare-and-bind, or assign, each value.
-> wk_for_head(s, v, act)
  a = s.a
  if a.kind == :var_decl
    wk_bind(a.list[0].a, v, act, true)
  else
    wk_bind(a, v, act, false)
  nil

-> wk_for_in(s, act, labels)
  fs = s.x
  saved = act.env
  per = fs.is_a?(JaScope) && fs.has_env?
  if s.a.kind == :var_decl && s.a.list[0].b != nil
    # for (var x = init in o): the initializer runs first (Annex B.3.5)
    wk_bind(s.a.list[0].a, wk_ev(s.a.list[0].b, act), act, true)
  obj = wk_ev(s.b, act)
  ks = js_for_in_keys(obj)
  i = 0
  while i < ks.size
    k = ks[i]
    i += 1
    # a key deleted before it is reached is not visited
    if js_object?(obj) && !jhas_property?(obj, k)
      next
    if per
      act.env = saved
      wk_scope_enter(fs, act)
    wk_for_head(s, k, act)
    wk_ex(s.d, act)
    r = wk_loop_signal(act, labels)
    if r == WK_RETURN
      act.env = saved
      return nil
    break if r == WK_BREAK
  act.env = saved
  nil

-> wk_for_of(s, act, labels)
  fs = s.x
  saved = act.env
  per = fs.is_a?(JaScope) && fs.has_env?
  rec = js_get_iterator(wk_ev(s.b, act))
  begin
    while true
      v = js_iter_step(rec)
      break if v == JS_ITER_DONE
      if per
        act.env = saved
        wk_scope_enter(fs, act)
      wk_for_head(s, v, act)
      wk_ex(s.d, act)
      r = wk_loop_signal(act, labels)
      if r != 0 && r != WK_CONTINUE
        js_iter_close(rec)
        break
  rescue ex
    js_iter_close_quiet(rec)
    act.env = saved
    raise ex
  act.env = saved
  nil

-> wk_labeled(s, act, labels)
  a = s.a
  k = a.kind
  return wk_labeled(a, act, labels + [a.str]) if k == :labeled
  return wk_for(a, act, labels) if k == :for
  return wk_while(a, act, labels) if k == :while
  return wk_do_while(a, act, labels) if k == :do_while
  return wk_switch(a, act, labels) if k == :switch
  return wk_for_in(a, act, labels) if k == :for_in
  return wk_for_of(a, act, labels) if k == :for_of
  wk_ex(a, act)
  if act.sig == WK_BREAK && act.label != nil && labels.include?(act.label)
    act.sig = 0
    act.label = nil
  nil

-> wk_try(s, act)
  return wk_try_catch(s, act) if s.d == nil
  # try/finally: the finally block runs after the try (and catch) completes however it
  # completes; its own abrupt completion replaces the pending one
  saved = act.env
  pending = nil
  begin
    if s.c != nil
      wk_try_catch(s, act)
    else
      wk_ex(s.a, act)
  rescue ex
    pending = ex
  act.env = saved
  sg = act.sig
  lb = act.label
  rv = act.rv
  act.sig = 0
  act.label = nil
  wk_block(s.d, s.d.list, act)
  if act.sig == 0
    raise pending if pending != nil
    act.sig = sg
    act.label = lb
    act.rv = rv
  nil

-> wk_try_catch(s, act)
  saved = act.env
  begin
    wk_ex(s.a, act)
  rescue ex
    act.env = saved
    cs = s.x
    cs = nil if !cs.is_a?(JaScope)
    wk_scope_enter(cs, act) if cs != nil
    if s.b != nil
      v = js_error_value(ex)
      if s.b.kind == :ident
        wk_write(cs.names[s.b.str], v, act)
      else
        wk_bind(s.b, v, act, true)
    wk_block(s.c, s.c.list, act)
    act.env = saved
  nil

-> wk_switch(s, act, labels)
  saved = act.env
  bs = s.x
  wk_scope_enter(bs, act) if bs.is_a?(JaScope)
  d = wk_ev(s.a, act)
  n = s.list.size
  ix = -1
  dflt = n
  i = 0
  while i < n && ix < 0
    c = s.list[i]
    if c.a == nil
      dflt = i
    elsif js_seq(d, wk_ev(c.a, act))
      ix = i
    i += 1
  if ix < 0
    while i < n
      dflt = i if s.list[i].a == nil
      i += 1
    ix = dflt
  all = []
  i = 0
  while i < n
    all = all + s.list[i].list
    i += 1
  wk_hoist_functions(all, act)
  i = ix
  while i < n
    wk_stmts(s.list[i].list, act)
    break if act.sig != 0
    i += 1
  if act.sig == WK_BREAK && (act.label == nil || (labels != nil && labels.include?(act.label)))
    act.sig = 0
    act.label = nil
  act.env = saved
  nil

# ---- expressions ----

-> wk_ev(e, act)
  k = e.kind
  if k == :ident
    return wk_read_ident(e, act)
  if k == :num
    return e.a
  if k == :string
    return e.str
  if k == :member
    return wk_super_get(e, act) if e.a.kind == :super
    o = wk_ev(e.a, act)
    return js_getv(o, wk_ev(e.b, act)) if e.has?(F_COMPUTED)
    return js_priv_get(o, wk_read_ref(e.b.x, act)) if e.b.kind == :private_name
    return js_getp_ic(o, e.b.str, wk_ic(e))
  if k == :call
    return wk_call_expr(e, act)
  if k == :binary
    return wk_binary(e, act)
  if k == :assign
    return wk_assign(e, act)
  if k == :logical
    a = wk_ev(e.a, act)
    if e.str == "&&"
      return js_truthy(a) ? wk_ev(e.b, act) : a
    if e.str == "||"
      return js_truthy(a) ? a : wk_ev(e.b, act)
    return js_nullish?(a) ? wk_ev(e.b, act) : a
  if k == :this
    return wk_this(e, act)
  if k == :true
    return true
  if k == :false
    return false
  if k == :null
    return JS_NULL
  if k == :unary
    return wk_unary(e, act)
  if k == :update
    return wk_update(e, act)
  if k == :cond
    return js_truthy(wk_ev(e.a, act)) ? wk_ev(e.b, act) : wk_ev(e.c, act)
  if k == :function || k == :arrow
    jf = e.x
    return js_closure(wk_code(jf), wk_env_for(jf, act))
  if k == :new
    return wk_new(e, act)
  if k == :array
    return wk_array(e, act)
  if k == :object
    return wk_object(e, act)
  if k == :seq
    v = nil
    i = 0
    while i < e.list.size
      v = wk_ev(e.list[i], act)
      i += 1
    return v
  if k == :class
    return wk_class(e, act)
  if k == :meta_property
    return wk_special(e, act, :nt)
  if k == :template
    sb = StringBuffer()
    i = 0
    while i < e.list.size
      sb.append(e.list[i].str)
      sb.append(js_template_string(wk_ev(e.a[i], act))) if i < e.a.size
      i += 1
    return sb.to_s
  if k == :tagged_template
    return wk_tagged(e, act)
  if k == :chain
    v = wk_chain(e.a, act)
    return v == WK_SHORT ? nil : v
  if k == :regex
    return js_regexp_create(e.str, e.a)
  if k == :bigint
    return js_bigint_literal(e.str)
  js_throw(js_make_error("SyntaxError", "tier 0: expression " + k.to_s))

# A substitution in a template literal: ToString, which a Symbol refuses.
-> js_template_string(v)
  return v if js_string?(v)
  js_to_string(v)

-> wk_tagged(e, act)
  t = e.b
  tobj = t.x
  if tobj == nil
    cooked = []
    raw = []
    t.list.each ->(q)
      cooked.push(q.str)
      raw.push(q.a)
    tobj = js_template_object(cooked, raw)
    t.x = tobj
  c = e.a
  this = nil
  f = nil
  if c.kind == :member
    this = wk_ev(c.a, act)
    f = c.has?(F_COMPUTED) ? js_getv(this, wk_ev(c.b, act)) : js_getp_ic(this, c.b.str, wk_ic(c))
  else
    f = wk_ev(c, act)
  args = [tobj]
  t.a.each ->(x) args.push(wk_ev(x, act))
  js_call_arr(f, this, args)

# Optional chains: WK_SHORT travels out of the chain when a ?. link meets null/undefined.
+ WkShort
  -> new
    nil
WK_SHORT = WkShort.new

-> wk_chain(e, act)
  k = e.kind
  if k == :member
    o = wk_chain(e.a, act)
    return WK_SHORT if o == WK_SHORT
    return WK_SHORT if e.has?(F_OPTIONAL) && js_nullish?(o)
    return js_getv(o, wk_ev(e.b, act)) if e.has?(F_COMPUTED)
    return js_getp_ic(o, e.b.str, wk_ic(e))
  if k == :call
    c = e.a
    this = nil
    f = nil
    if c.kind == :member
      this = wk_chain(c.a, act)
      return WK_SHORT if this == WK_SHORT
      return WK_SHORT if c.has?(F_OPTIONAL) && js_nullish?(this)
      f = c.has?(F_COMPUTED) ? js_getv(this, wk_ev(c.b, act)) : js_getp_ic(this, c.b.str, wk_ic(c))
    else
      f = wk_chain(c, act)
      return WK_SHORT if f == WK_SHORT
    return WK_SHORT if e.has?(F_OPTIONAL) && js_nullish?(f)
    return wk_call_args(f, this, e.list, act)
  wk_ev(e, act)

-> wk_read_ident(e, act)
  ref = e.x
  b = ref.binding
  if b.kind == :global && b.writes == 0
    nm = e.str
    return nil if nm == "undefined"
  wk_read_ref(ref, act)

-> wk_this(e, act)
  f = act.f
  return act.this if !f.arrow || f.script
  g = f
  while g.arrow
    g = g.parent
  return act.this if g.script
  wk_read_binding_from(g.this_binding, e.x.scope, act)

WK_OPS = {"+" => 1, "-" => 2, "*" => 3, "/" => 4, "%" => 5, "<" => 6, ">" => 7, "<=" => 8, ">=" => 9, "===" => 10, "!==" => 11, "==" => 12, "!=" => 13, "|" => 14, "&" => 15, "^" => 16, "<<" => 17, ">>" => 18, ">>>" => 19, "**" => 20, "instanceof" => 21, "in" => 22}

-> wk_binop(op, a, b)
  c = WK_OPS[op]
  return js_add(a, b) if c == 1
  return js_sub(a, b) if c == 2
  return js_mul(a, b) if c == 3
  return js_div(a, b) if c == 4
  return js_mod(a, b) if c == 5
  return js_lt(a, b) if c == 6
  return js_gt(a, b) if c == 7
  return js_le(a, b) if c == 8
  return js_ge(a, b) if c == 9
  return js_seq(a, b) if c == 10
  return !js_seq(a, b) if c == 11
  return js_eq(a, b) if c == 12
  return !js_eq(a, b) if c == 13
  return js_bitor(a, b) if c == 14
  return js_bitand(a, b) if c == 15
  return js_bitxor(a, b) if c == 16
  return js_shl(a, b) if c == 17
  return js_sar(a, b) if c == 18
  return js_shr(a, b) if c == 19
  return js_pow(a, b) if c == 20
  return js_instanceof(a, b) if c == 21
  return js_in(a, b) if c == 22
  js_throw(js_make_error("SyntaxError", "tier 0: operator " + op))

-> wk_binary(e, act)
  if e.a.kind == :private_name
    o = wk_ev(e.b, act)
    js_throw_type("Cannot use 'in' operator to search for a private field in a non-object") if !js_object?(o)
    return o.is_a?(JS:Base) && o.priv_has?(wk_read_ref(e.a.x, act))
  a = wk_ev(e.a, act)
  b = wk_ev(e.b, act)
  wk_binop(e.str, a, b)

-> wk_unary(e, act)
  op = e.str
  if op == "typeof"
    a = e.a
    if a.kind == :ident && a.x.binding.global?
      return js_gtypeof(wk_cell(a.x.binding))
    return js_typeof(wk_ev(a, act))
  if op == "delete"
    a = e.a
    if a.kind == :member
      key = a.has?(F_COMPUTED) ? wk_ev(a.b, act) : a.b.str
      return js_delete(wk_ev(a.a, act), key, act.f.strict)
    wk_ev(a, act)
    return true
  v = wk_ev(e.a, act)
  return !js_truthy(v) if op == "!"
  return js_neg(v) if op == "-"
  return js_plus(v) if op == "+"
  return js_bitnot(v) if op == "~"
  return nil if op == "void"
  js_throw(js_make_error("SyntaxError", "tier 0: unary " + op))

-> wk_update(e, act)
  t = e.a
  inc = e.str == "++"
  if t.kind == :ident
    old = js_tonumeric(wk_read_ref(t.x, act))
    nv = inc ? js_add(old, ~1.0) : js_sub(old, ~1.0)
    wk_write_ref(t.x, nv, act)
    return e.has?(F_PREFIX) ? nv : old
  o = wk_ev(t.a, act)
  key = t.has?(F_COMPUTED) ? js_to_property_key(wk_ev(t.b, act)) : t.b.str
  old = js_tonumeric(js_getv(o, key))
  nv = inc ? js_add(old, ~1.0) : js_sub(old, ~1.0)
  js_setv(o, key, nv, act.f.strict)
  e.has?(F_PREFIX) ? nv : old

-> wk_assign(e, act)
  op = e.str
  t = e.a
  if t.kind == :ident
    ref = t.x
    if op == "="
      v = wk_ev(e.b, act)
    elsif op == "&&=" || op == "||=" || op == "??="
      cur = wk_read_ref(ref, act)
      return cur if op == "&&=" && !js_truthy(cur)
      return cur if op == "||=" && js_truthy(cur)
      return cur if op == "??=" && !js_nullish?(cur)
      v = wk_ev(e.b, act)
    else
      v = wk_binop(op.slice(0, op.size - 1), wk_read_ref(ref, act), wk_ev(e.b, act))
    js_throw_type("Assignment to constant variable.") if ref.binding.kind == :const
    wk_write_ref(ref, v, act)
    return v
  if t.kind == :object_pattern || t.kind == :array_pattern
    v = wk_ev(e.b, act)
    wk_bind(t, v, act, false)
    return v
  if t.a.kind == :super
    key = t.has?(F_COMPUTED) ? js_to_property_key(wk_ev(t.b, act)) : t.b.str
    v = op == "=" ? wk_ev(e.b, act) : wk_binop(op.slice(0, op.size - 1), wk_super_get(t, act), wk_ev(e.b, act))
    wk_super_set(t, key, v, act)
    return v
  o = wk_ev(t.a, act)
  if t.b.kind == :private_name
    pn = wk_read_ref(t.b.x, act)
    if op == "&&=" || op == "||=" || op == "??="
      cur = js_priv_get(o, pn)
      return cur if (op == "&&=" && !js_truthy(cur)) || (op == "||=" && js_truthy(cur)) || (op == "??=" && !js_nullish?(cur))
      v = wk_ev(e.b, act)
    else
      v = op == "=" ? wk_ev(e.b, act) : wk_binop(op.slice(0, op.size - 1), js_priv_get(o, pn), wk_ev(e.b, act))
    js_priv_set(o, pn, v)
    return v
  if op == "&&=" || op == "||=" || op == "??="
    key = t.has?(F_COMPUTED) ? js_to_property_key(wk_ev(t.b, act)) : t.b.str
    cur = js_getv(o, key)
    return cur if (op == "&&=" && !js_truthy(cur)) || (op == "||=" && js_truthy(cur)) || (op == "??=" && !js_nullish?(cur))
    v = wk_ev(e.b, act)
    js_setv(o, key, v, act.f.strict)
    return v
  if !t.has?(F_COMPUTED)
    key = t.b.str
    v = op == "=" ? wk_ev(e.b, act) : wk_binop(op.slice(0, op.size - 1), js_getv(o, key), wk_ev(e.b, act))
    js_setp_ic(o, key, v, wk_ic(t), act.f.strict)
    return v
  key = js_to_property_key(wk_ev(t.b, act))
  if op == "="
    v = wk_ev(e.b, act)
  else
    v = wk_binop(op.slice(0, op.size - 1), js_getv(o, key), wk_ev(e.b, act))
  js_setv(o, key, v, act.f.strict)
  v

# The inline cache of a property node (made on first use; kept in the node's x).
-> wk_ic(e)
  ic = e.x
  if ic == nil
    ic = i64[4]
    e.x = ic
  ic

-> wk_args(list, act)
  out = []
  i = 0
  while i < list.size
    x = list[i]
    if x.kind == :spread
      js_append_iterable(out, wk_ev(x.a, act))
    else
      out.push(wk_ev(x, act))
    i += 1
  out

-> wk_has_spread?(list)
  i = 0
  while i < list.size
    return true if list[i] != nil && list[i].kind == :spread
    i += 1
  false



-> wk_call_expr(e, act)
  c = e.a
  return wk_super_call(e, act) if c.kind == :super
  if c.kind == :member
    if c.a.kind == :super
      return wk_call_args(wk_super_get(c, act), wk_this_for(c.a, act), e.list, act)
    o = wk_ev(c.a, act)
    if c.b.kind == :private_name
      f = js_priv_get(o, wk_read_ref(c.b.x, act))
    else
      f = c.has?(F_COMPUTED) ? js_getv(o, wk_ev(c.b, act)) : js_getp_ic(o, c.b.str, wk_ic(c))
    return wk_call_args(f, o, e.list, act)
  f = wk_ev(c, act)
  wk_call_args(f, nil, e.list, act)

-> wk_call_args(f, this, list, act)
  n = list.size
  return js_call_arr(f, this, wk_args(list, act)) if wk_has_spread?(list)
  if n <= 4
    a0 = n > 0 ? wk_ev(list[0], act) : nil
    a1 = n > 1 ? wk_ev(list[1], act) : nil
    a2 = n > 2 ? wk_ev(list[2], act) : nil
    a3 = n > 3 ? wk_ev(list[3], act) : nil
    return js_call(f, this, n, a0, a1, a2, a3, nil)
  args = wk_args(list, act)
  js_call(f, this, n, args[0], args[1], args[2], args[3], args)

-> wk_new(e, act)
  f = wk_ev(e.a, act)
  list = e.list
  n = list.size
  return js_new_arr(f, wk_args(list, act)) if wk_has_spread?(list)
  if n <= 4
    a0 = n > 0 ? wk_ev(list[0], act) : nil
    a1 = n > 1 ? wk_ev(list[1], act) : nil
    a2 = n > 2 ? wk_ev(list[2], act) : nil
    a3 = n > 3 ? wk_ev(list[3], act) : nil
    return js_new(f, JS_IC_SCRATCH, n, a0, a1, a2, a3, nil)
  args = wk_args(list, act)
  js_new(f, JS_IC_SCRATCH, n, args[0], args[1], args[2], args[3], args)

-> wk_array(e, act)
  out = []
  holes = false
  i = 0
  while i < e.list.size
    x = e.list[i]
    if x == nil
      out.push(JS_HOLE)
      holes = true
    elsif x.kind == :spread
      js_append_iterable(out, wk_ev(x.a, act))
    else
      out.push(wk_ev(x, act))
    i += 1
  holes ? js_mark_holey(out) : js_mark_array(out)

-> wk_object(e, act)
  o = js_new_object(js_realm().object_proto)
  i = 0
  while i < e.list.size
    p = e.list[i]
    if p.kind == :spread
      js_copy_data_properties(o, wk_ev(p.a, act), [])
    else
      key = p.has?(F_COMPUTED) ? js_to_property_key(wk_ev(p.a, act)) : wk_prop_key(p.a)
      kind = p.str
      if kind == "get" || kind == "set"
        f = wk_ev(p.b, act)
        js_set_fn_name(f, key, kind) if p.has?(F_COMPUTED)
        cur = o.get_own_property(key)
        g = kind == "get" ? f : (cur != nil && cur.accessor? ? cur.getter : nil)
        st = kind == "set" ? f : (cur != nil && cur.accessor? ? cur.setter : nil)
        o.define_accessor(key, g, st, ATTR_E + ATTR_C)
      elsif key == "__proto__" && !p.has?(F_COMPUTED) && !p.has?(F_SHORTHAND) && !p.has?(F_METHOD)
        v = wk_ev(p.b, act)
        o.set_prototype_of(v) if js_object?(v) || v == JS_NULL
      else
        v = wk_ev(p.b, act)
        js_set_fn_name(v, key, nil) if p.has?(F_COMPUTED) && wk_anonymous_fn?(p.b)
        o.define(key, v, ATTR_DEFAULT)
    i += 1
  o

-> wk_anonymous_fn?(n)
  (n.kind == :function || n.kind == :arrow) && n.str == nil

# CopyDataProperties (spread in object literals and rest patterns).
-> js_copy_data_properties(o, src, excluded)
  return o if js_nullish?(src)
  from = js_object?(src) ? src : js_realm().wrap_primitive(src)
  ks = jown_keys(from)
  j = 0
  while j < ks.size
    kk = ks[j]
    if !excluded.include?(kk) && jenumerable?(from, kk)
      o.define(kk, jget(from, kk, src), ATTR_DEFAULT)
    j += 1
  o

# SetFunctionName for a computed key (the static ones are named by the analysis).
-> js_set_fn_name(f, key, prefix)
  return nil if !f.is_a?(JS:Function)
  nm = key.is_a?(JS:Symbol) ? (key.description == nil ? "" : "\[" + key.description + "]") : js_to_string(key)
  nm = prefix + " " + nm if prefix != nil
  f.define("name", nm, ATTR_C)
  nil

# Parse and analyse a script without running it (test262 parse-phase negatives): raises
# the SyntaxError a run would.
-> wk_check(src)
  p = JsParser.new(src, false)
  begin
    prog = p.parse_program()
  rescue e
    js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.to_s))
  JaAnalysis.new(prog, false).run
  nil


# ---- classes (§15.7.14 ClassDefinitionEvaluation) ----

-> wk_class(n, act)
  cs = n.x
  saved = act.env
  wk_scope_enter(cs, act)
  # a fresh private name per #x
  cs.order.each ->(b) wk_write(b, JS:PrivateName.new(b.name.slice(1, b.name.size - 1)), act) if b.kind == :private
  r = js_realm()
  proto_parent = r.object_proto
  ctor_parent = r.function_proto
  if n.a != nil
    sup = wk_ev(n.a, act)
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
  f.define("prototype", proto, 0)
  proto.define("constructor", f, ATTR_W + ATTR_C)
  fields = []
  privs = []
  statics = []
  i = 0
  while i < n.list.size
    m = n.list[i]
    st = m.has?(F_STATIC)
    if m.kind == :method_def && m.str != "constructor"
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
        key = m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.a, act)) : wk_prop_key(m.a)
        js_set_fn_name(fo, key, m.str == "method" ? nil : m.str) if m.has?(F_COMPUTED)
        if m.str == "method"
          target.define(key, fo, ATTR_W + ATTR_C)
        else
          cur = target.get_own_property(key)
          g = m.str == "get" ? fo : (cur != nil && cur.accessor? ? cur.getter : nil)
          sx = m.str == "set" ? fo : (cur != nil && cur.accessor? ? cur.setter : nil)
          target.define_accessor(key, g, sx, ATTR_C)
    elsif m.kind == :field_def
      key = m.a.kind == :private_name ? wk_read_ref(m.a.x, act) : (m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.a, act)) : wk_prop_key(m.a))
      init = m.x == nil ? nil : js_method_closure(wk_code(m.x), wk_env_for(m.x, act), st ? f : proto)
      if st
        statics.push([key, init, false])
      else
        fields.push([key, init])
    elsif m.kind == :static_block
      statics.push([nil, js_method_closure(wk_code(m.x), wk_env_for(m.x, act), f), true])
    i += 1
  f.fields = fields if fields.size > 0
  f.privs = privs if privs.size > 0
  if n.str != nil
    wk_write(cs.names[n.str], f, act)
  # static fields and blocks, in order, with this = the constructor
  i = 0
  while i < statics.size
    se = statics[i]
    if se[2]
      js_call(se[1], f, 0, nil, nil, nil, nil, nil)
    else
      v = se[1] == nil ? nil : js_call(se[1], f, 0, nil, nil, nil, nil, nil)
      if se[0].is_a?(JS:PrivateName)
        f.priv_add(se[0], v)
      else
        jdefine_own_or_throw(f, se[0], v)
    i += 1
  act.env = saved
  f

# new.target (:nt) or the running method's object (:fo) where node e is: the activation's
# own in a non-arrow function, else the enclosing function's binding.
-> wk_special(e, act, which)
  f = act.f
  if !f.arrow
    return which == :nt ? act.nt : act.fobj
  g = f
  while g.arrow
    g = g.parent
  return nil if g.script
  b = which == :nt ? g.nt_binding : g.fo_binding
  wk_read_binding_from(b, e.x.scope, act)

-> wk_this_for(e, act)
  f = act.f
  return act.this if !f.arrow
  g = f
  while g.arrow
    g = g.parent
  wk_read_binding_from(g.this_binding, e.x.scope, act)

# super.x and super[x]: from the home object's prototype, with this as the receiver.
-> wk_super_get(m, act)
  fo = wk_special(m.a, act, :fo)
  key = m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.b, act)) : m.b.str
  this = wk_this_for(m.a, act)
  home = fo.home
  p = jget_prototype_of(home)
  return nil if p == JS_NULL
  jget(p, key, this)

-> wk_super_set(m, key, v, act)
  fo = wk_special(m.a, act, :fo)
  this = wk_this_for(m.a, act)
  p = jget_prototype_of(fo.home)
  ok = p == JS_NULL ? false : jset(p, key, v, this)
  js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && act.f.strict
  v

# super(...args) in a derived constructor (or an arrow inside one).
-> wk_super_call(e, act)
  fo = wk_special(e.a, act, :fo)
  nt = wk_special(e.a, act, :nt)
  parent = fo.get_prototype_of
  args = wk_args(e.list, act)
  js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
  obj = js_construct(parent, args, nt)
  wk_bind_this(e, obj, act)
  js_init_fields(obj, fo)
  obj

# Initialize the constructor's this once (a second super() is a ReferenceError).
-> wk_bind_this(e, obj, act)
  f = act.f
  g = f
  while g.arrow
    g = g.parent
  b = g.this_binding
  if !f.arrow && (b == nil || b.slot < 0)
    js_throw_reference("Super constructor may only be called once") if act.this != nil
    act.this = obj
    return nil
  cur = wk_read_binding_from(b, e.a.x.scope, act)
  js_throw_reference("Super constructor may only be called once") if cur != nil
  wk_write_ref(JaRef.new(b, e.a.x.scope), obj, act)
  act.this = obj if !f.arrow
  nil

-> js_priv_get(o, pn)
  js_throw_type("Cannot read private member " + pn.to_s + " from an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_get(pn)

-> js_priv_set(o, pn, v)
  js_throw_type("Cannot write private member " + pn.to_s + " to an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_set(pn, v)

-> js_bigint_literal(s)
  t = s
  base = 10
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    base = b == 120 ? 16 : (b == 111 ? 8 : (b == 98 ? 2 : 10))
    t = t.slice(2, t.size - 2) if base != 10
  v = 0
  i = 0
  while i < t.size
    v = v * base + js_digit(t.byte_at(i))
    i += 1
  JS:BigIntValue.new(v)
