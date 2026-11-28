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

use parser
use analyze

WK_NONE = 0
WK_BREAK = 1
WK_CONTINUE = 2
WK_RETURN = 3

+ WkAct
  rw :f, :fobj, :fe, :this, :locals, :env, :argc, :args, :nt, :sig, :label, :rv, :env_at_entry, :coro, :pos, :caller, :a0, :a1, :a2, :a3, :disp

  -> new(@f, @fobj, @fe, @this, n)
    @pos = 0
    @caller = nil
    @locals = Array.new(n, nil)
    @env = @fe
    @argc = 0
    @args = nil
    @a0 = nil
    @a1 = nil
    @a2 = nil
    @a3 = nil
    @nt = nil
    @sig = 0
    @label = nil
    @rv = nil
    @env_at_entry = nil
    @coro = nil
    @disp = nil

  -> reset(f, fobj, fe, this, n)
    @f = f
    @fobj = fobj
    @fe = fe
    @this = this
    @env = fe
    @argc = 0
    @args = nil
    @a0 = nil
    @a1 = nil
    @a2 = nil
    @a3 = nil
    @nt = nil
    @sig = 0
    @label = nil
    @rv = nil
    @env_at_entry = nil
    @coro = nil
    @disp = nil
    @pos = 0
    @caller = nil
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
    gen = jf.node.has?(F_GENERATOR)
    asy = jf.node.has?(F_ASYNC)
    ctor = !jf.arrow && !jf.script && (jf.method_kind == nil || jf.class_ctor) && !jf.field_init && !gen && !asy
    flags = (jf.strict ? CODE_STRICT : 0) + (jf.arrow ? CODE_ARROW : 0) + (jf.method_kind != nil || jf.node.has?(F_METHOD) ? CODE_METHOD : 0) + (ctor ? CODE_CTOR : 0) + (jf.class_ctor ? CODE_CLASS : 0) + (jf.class_ctor && jf.derived ? CODE_DERIVED : 0) + (gen ? CODE_GEN : 0) + (asy ? CODE_ASYNC : 0)
    c = JS:Code.new(jf.name, jf.nparams, -1, flags)
    c.node = jf
    c.realm = js_realm()
    jf.code = c
  c

# ---- running scripts ----

# ->(analysis) called before a script (not eval code) runs, with its analysis.
WK_PRE_RUN = [nil]

# Optional host hook for pre-parsed JS AST + JaAnalysis caching (used by blade/frameworks):
#   WK_PARSE_CACHE_HOOK[0] = ->(src, url) returns [prog, an] or nil
#   WK_PARSE_CACHE_HOOK[1] = ->(src, url, pair, parse_ms) stores [prog, an]
WK_PARSE_CACHE_HOOK = [nil, nil]

# Run a script (mode nil), indirect eval code (:eval) or the source new Function builds.
# Returns the completion value of the last expression statement.
-> wk_run(src, url, mode = nil)
  prog = nil
  an = nil
  if mode == nil && WK_PARSE_CACHE_HOOK[0] != nil
    hit = WK_PARSE_CACHE_HOOK[0].call(src, url)
    if hit != nil && hit[1] != nil && hit[1].funcs != nil && hit[1].funcs.size > 0 && hit[1].funcs[0] != nil
      prog = hit[0]
      an = hit[1]
  if an == nil
    t_parse0 = WK_PARSE_CACHE_HOOK[1] != nil && mode == nil ? clock() : ~0.0
    # Large script AST + semantic analysis allocates almost 100% live nodes until done;
    # pause Tungsten GC during parse+analyze to avoid stop-the-world cycles walking live ASTs.
    pause_gc = src.size >= 65536 && GC.enabled?
    GC.disable if pause_gc
    begin
      p = JsParser.new(src, false)
      begin
        prog = p.parse_program()
      rescue e
        p.release_simd_lex
        js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.msg + " (line " + p.error.line.to_s + ", column " + p.error.col.to_s + ")"))
      p.release_simd_lex
      an = JaAnalysis.new(prog, false)
      an.src = src
      an.url = url
      an.eval_mode = mode != nil
      an.run
    ensure
      GC.enable if pause_gc
    if mode == nil && WK_PARSE_CACHE_HOOK[1] != nil
      WK_PARSE_CACHE_HOOK[1].call(src, url, [prog, an], (clock() - t_parse0) * ~1000.0)
  r0 = JS_REALM[0]
  r0.analyses.push(an) if !JS_GC_ON[0] && r0 != nil && r0.analyses != nil
  # (the host may load the script's compiled unit here: runtime/units.w)
  WK_PRE_RUN[0].call(an) if WK_PRE_RUN[0] != nil && mode == nil
  f = an.funcs[0]
  an.funcs.each ->(g)
    js_throw(js_make_error("SyntaxError", g.unsupported0.to_s)) if g.unsupported0 != nil
  c = f.code
  if c != nil && c.entry != 0
    # a loaded unit compiled the script itself
    return ccall("w_closure_call_8", c.entry, nil, js_realm().global, 0, nil, nil, nil, nil, nil)
  act = wk_act(f, nil, nil, js_realm().global, f.nlocals)
  act.caller = JS_CUR_ACT[0]
  JS_CUR_ACT[0] = act
  rv = nil
  begin
    wk_hoist_script(f, act)
    wk_scope_enter(f.scope, act)
    wk_hoist_functions(prog.list, act)
    wk_stmts(prog.list, act)
    rv = act.rv
  ensure
    JS_CUR_ACT[0] = act.caller
    if JS_GC_ON[0]
      has_inner = an.funcs != nil && an.funcs.size > 1
      an.program = nil
      f.node = nil
      an.funcs = nil
      an.src = nil if !has_inner
    wk_release(act)
  rv

# The JS stack as JavaScriptCore prints it (Blade presents as Safari): one
# "name@url:line:col" per frame, innermost first, scripts as "global code@...".
-> wk_stack_lines
  out = []
  a = JS_CUR_ACT[0]
  while a != nil && a.f != nil && out.size < 100
    jf = a.f
    an = jf.analysis
    loc = js_src_location(an.src, an.url, a.pos)
    if jf.script
      out.push((an.eval_mode ? "eval code@" : "global code@") + loc)
    else
      out.push(jf.name.to_s + "@" + loc)
    a = a.caller
  out.join("\n")

# [url, line, column] of the innermost frame.
-> wk_top_location
  a = JS_CUR_ACT[0]
  return ["", 1, 1] if a == nil || a.f == nil
  an = a.f.analysis
  lc = js_src_linecol(an.src, a.pos)
  [an.url == nil ? "" : an.url, lc[0], lc[1]]

JS_STACK_HOOK[0] = ->() wk_stack_lines()
JS_LOCATION_HOOK[0] = ->() wk_top_location()

-> wk_can_declare_global_fn?(g, nm)
  ep = g.get_own_property(nm)
  return g.is_extensible? if ep == nil
  return true if ep.configurable
  !ep.accessor? && ep.writable && ep.enumerable

-> wk_can_declare_global_var?(g, nm)
  ep = g.get_own_property(nm)
  return true if ep != nil
  g.is_extensible?

-> wk_hoist_script(f, act)
  ev = f.analysis.eval_mode
  return nil if ev && f.strict
  return nil if !f.script
  g = js_realm().global
  lm = js_lexical_map()
  gv = js_global_vars()
  stmts = f.node.list
  ta = JaAnalysis.new(nil, false)
  lex = ta.lexical_names(stmts)
  vn = ta.var_names(stmts, [], f.strict, true)
  fn_names = []
  stmts.each ->(st)
    fs2 = wk_unwrap_labeled_fn(st)
    fn_names.push(fs2.str) if fs2 != nil && !fn_names.include?(fs2.str)
  # §16.1.7 GlobalDeclarationInstantiation validation (before creating any bindings!)
  if !ev
    lex.each ->(nm)
      js_throw(js_make_error("SyntaxError", "Identifier '" + nm + "' has already been declared")) if lm.has_key?(nm) || gv.has_key?(nm)
      ep = g.get_own_property(nm)
      js_throw(js_make_error("SyntaxError", "Identifier '" + nm + "' has already been declared")) if ep != nil && !ep.configurable
  vn.each ->(nm)
    js_throw(js_make_error("SyntaxError", "Identifier '" + nm + "' has already been declared")) if lm.has_key?(nm)
  fn_names.each ->(nm)
    js_throw(js_make_error("SyntaxError", "Identifier '" + nm + "' has already been declared")) if lm.has_key?(nm)
  # Check CanDeclareGlobalFunction for top-level function declarations
  fn_names.each ->(nm)
    js_throw_type("Cannot declare global function '" + nm + "'") if !wk_can_declare_global_fn?(g, nm)
  # Check CanDeclareGlobalVar for var declarations not shadowed by a top-level function declaration
  vn.each ->(nm)
    if !fn_names.include?(nm)
      js_throw_type("Cannot declare global var '" + nm + "'") if !wk_can_declare_global_var?(g, nm)
  # Pre-create global lexical cells in TDZ (for non-eval scripts)
  if !ev
    lex.each ->(nm) js_lcell(nm)
  # Annex B.3.3.2 / B.3.3.3: block-scoped function declarations in sloppy mode
  ab_add = []
  if !f.strict
    ab = ta.annexb_names(stmts, lex, [], true)
    ab.each ->(nm)
      if !vn.include?(nm) && !fn_names.include?(nm) && !lm.has_key?(nm)
        if wk_can_declare_global_var?(g, nm)
          ab_add.push(nm)
  attrs = ev ? ATTR_W + ATTR_E + ATTR_C : ATTR_W + ATTR_E
  i = 0
  while i < vn.size
    nm = vn[i]
    if !fn_names.include?(nm)
      js_gdeclare(js_gcell(nm), nil, false, attrs)
      gv[nm] = true if !ev
    i += 1
  i = 0
  while i < ab_add.size
    nm = ab_add[i]
    js_gdeclare(js_gcell(nm), nil, false, attrs)
    gv[nm] = true if !ev
    i += 1
  if !ev
    fn_names.each ->(nm) gv[nm] = true
  nil

# Source text of a function tier 0 runs (Function.prototype.toString).
-> wk_fn_source(f)
  return f.code.src_text if f.code != nil && f.code.src_text != nil
  jf = f.code.node
  return nil if !jf.is_a?(JaFunc)
  s = jf.analysis.src
  return nil if s == nil
  n = jf.class_ctor && jf.class_node != nil ? jf.class_node : jf.node
  s.slice(n.pos, n.fin - n.pos)

-> wk_check_fn_parts(prefix, pstr, body)
  p1 = JsParser.new(prefix + " f(" + pstr + "\n) {}", false)
  begin
    prog1 = p1.parse_program()
  rescue e
    p1.release_simd_lex
    js_throw(js_make_error("SyntaxError", p1.error == nil ? e.to_s : p1.error.msg))
  p1.release_simd_lex
  js_throw(js_make_error("SyntaxError", "Invalid parameter list")) if prog1 == nil || prog1.list == nil || prog1.list.size != 1 || prog1.list[0].kind != :function_decl
  p2 = JsParser.new(prefix + " f() {\n" + body + "\n}", false)
  begin
    prog2 = p2.parse_program()
  rescue e
    p2.release_simd_lex
    js_throw(js_make_error("SyntaxError", p2.error == nil ? e.to_s : p2.error.msg))
  p2.release_simd_lex
  js_throw(js_make_error("SyntaxError", "Invalid function body")) if prog2 == nil || prog2.list == nil || prog2.list.size != 1 || prog2.list[0].kind != :function_decl
  nil

JS_EVAL_HOOK[0] = ->(src) wk_run(src, "eval", :eval)
JS_FUNCTION_HOOK[0] = ->(src) wk_run(src, "Function", :function)
JS_FUNCTION_CHECK_HOOK[0] = ->(prefix, pstr, body) wk_check_fn_parts(prefix, pstr, body)
JS_FN_SOURCE_HOOK[0] = ->(f) wk_fn_source(f)

# ---- calls into tier 0 ----

# The entry js_dispatch uses for a function with no native code.
WK_JIT_FN_THRESH = 4
WK_JIT_OSR_THRESH = 16

-> wk_call(f, this, argc, a0, a1, a2, a3, more)
  c = f.code
  if (c.flags & CODE_CLASS) != 0 && JS_NEW_TARGET[0] == nil
    js_throw_type("Class constructor " + c.name.to_s + " cannot be invoked without 'new'")
  if JS_DEADLINE_SEC[0] > ~0.0
    js_check_deadline()
    return wk_call_tier0(f, this, argc, a0, a1, a2, a3, more)
  if c.jit_fp != 0
    return jit_enter_fn(c, f, this, argc, a0, a1, a2, a3, more)
  if c.jit_state == 0
    if JS_ARENA_STATE[2] == 0
      if this.is_a?(JS:Object) && !this.shape.dict && this.shape.count == 0 && this.shape.inline == OBJ_INLINE && this.shape.ibase == OBJ_IBASE
        prev_rsh = c.ctor_rsh
        if prev_rsh == nil
          c.ctor_rsh = this.shape
        elsif prev_rsh != this.shape
          c.ctor_rsh = false
      else
        c.ctor_rsh = false
    c.warm_args = [a0, a1, a2, a3] if c.warm_args == nil && argc > 0 && JS_ARENA_STATE[2] == 0
    h = c.jit_hits + 1
    c.jit_hits = h
    if h >= WK_JIT_FN_THRESH
      wargs = argc > 0 && JS_ARENA_STATE[2] == 0 ? [a0, a1, a2, a3] : c.warm_args
      ok_jit = jit_compile_and_install(c, wargs)
      c.warm_args = nil
      c.ctor_rsh = nil
      if ok_jit
        return jit_enter_fn(c, f, this, argc, a0, a1, a2, a3, more)
  wk_call_tier0(f, this, argc, a0, a1, a2, a3, more)

JS_CALL_DEPTH = [0]

# Sentinel + scratch slot for O(1)-stack Proper Tail Calls (§15.10).
+ WkTail
  -> new
    nil
WK_TAIL = WkTail.new
WK_TC = [nil, nil, 0, nil, nil, nil, nil, nil]

-> wk_tail_set(f, this, argc, a0, a1, a2, a3, more)
  WK_TC[0] = f
  WK_TC[1] = this
  WK_TC[2] = argc
  WK_TC[3] = a0
  WK_TC[4] = a1
  WK_TC[5] = a2
  WK_TC[6] = a3
  WK_TC[7] = more
  WK_TAIL

-> wk_tail_arr(f, this, args)
  n = args.size
  if n > 4
    return wk_tail_set(f, this, n, args[0], args[1], args[2], args[3], args)
  a0 = n > 0 ? args[0] : nil
  a1 = n > 1 ? args[1] : nil
  a2 = n > 2 ? args[2] : nil
  a3 = n > 3 ? args[3] : nil
  wk_tail_set(f, this, n, a0, a1, a2, a3, nil)

-> wk_exec_pending_tail
  f = WK_TC[0]
  this = WK_TC[1]
  argc = WK_TC[2]
  a0 = WK_TC[3]
  a1 = WK_TC[4]
  a2 = WK_TC[5]
  a3 = WK_TC[6]
  more = WK_TC[7]
  WK_TC[0] = nil
  WK_TC[1] = nil
  WK_TC[3] = nil
  WK_TC[4] = nil
  WK_TC[5] = nil
  WK_TC[6] = nil
  WK_TC[7] = nil
  js_call(f, this, argc, a0, a1, a2, a3, more)

-> wk_call_tier0(f, this, argc, a0, a1, a2, a3, more)
  nt = JS_NEW_TARGET[0]
  JS_NEW_TARGET[0] = nil
  saved_realm = JS_REALM[0]
  d = JS_CALL_DEPTH[0] + 1
  js_throw_range("Maximum call stack size exceeded") if d > 1200
  JS_CALL_DEPTH[0] = d
  while true
    jf = f.code.node
    if jf.unsupported0 != nil
      JS_CALL_DEPTH[0] = d - 1
      JS_REALM[0] = saved_realm
      js_throw(js_make_error("SyntaxError", "tier 0 cannot run this yet: " + jf.unsupported0.to_s))
    if jf.class_ctor && nt == nil
      JS_CALL_DEPTH[0] = d - 1
      JS_REALM[0] = saved_realm
      js_throw_type("Class constructor " + jf.name + " cannot be invoked without 'new'")
    n = jf.node
    if n.has?(F_GENERATOR) || n.has?(F_ASYNC)
      JS_CALL_DEPTH[0] = d - 1
      r = nil
      begin
        r = wk_call_suspendable(jf, f, this, argc, a0, a1, a2, a3, more)
      rescue ex
        JS_REALM[0] = saved_realm
        raise ex
      JS_REALM[0] = saved_realm
      return r
    act = wk_act(jf, f, js_fenv(f), this, jf.nlocals)
    act.argc = argc
    act.args = more
    act.a0 = a0
    act.a1 = a1
    act.a2 = a2
    act.a3 = a3
    act.nt = nt
    act.caller = JS_CUR_ACT[0]
    JS_CUR_ACT[0] = act
    r = nil
    begin
      if jf.class_ctor
        r = wk_construct_body(jf, act, argc, a0, a1, a2, a3, more)
      else
        r = wk_enter(jf, act, argc, a0, a1, a2, a3, more)
    rescue ex
      JS_CALL_DEPTH[0] = d - 1
      JS_CUR_ACT[0] = act.caller
      JS_REALM[0] = saved_realm
      wk_release(act)
      raise ex
    JS_CUR_ACT[0] = act.caller
    wk_release(act)
    if r != WK_TAIL
      if JS_GC_ON[0] && jf.one_shot
        jf.one_shot = false
        jf.node = nil
        if jf.scopes != nil
          si = 0
          while si < jf.scopes.size
            sc = jf.scopes[si]
            if sc != nil
              sc.order = nil
              sc.names = nil
              sc.tdz_bindings = nil
            si += 1
          jf.scopes = nil
        jf.param_nodes = nil
        jf.param_copies = nil
        jf.params = nil
        jf.free = nil
        if f.code != nil
          f.code.warm_args = nil
          f.code.ctor_rsh = nil
      JS_CALL_DEPTH[0] = d - 1
      JS_REALM[0] = saved_realm
      return r
    # Proper Tail Call trampoline: previous frame is destroyed; execute next call in O(1) stack.
    f = WK_TC[0]
    this = WK_TC[1]
    argc = WK_TC[2]
    a0 = WK_TC[3]
    a1 = WK_TC[4]
    a2 = WK_TC[5]
    a3 = WK_TC[6]
    more = WK_TC[7]
    WK_TC[0] = nil
    WK_TC[1] = nil
    WK_TC[3] = nil
    WK_TC[4] = nil
    WK_TC[5] = nil
    WK_TC[6] = nil
    WK_TC[7] = nil
    nt = nil
    while (jsr_kind(wvalue_bits(f) ## i64) & 15) == KIND_BOUND
      ba = f.args + js_args_array(argc, a0, a1, a2, a3, more)
      this = f.bthis
      f = f.target
      argc = ba.size
      if argc > 4
        a0 = ba[0]
        a1 = ba[1]
        a2 = ba[2]
        a3 = ba[3]
        more = ba
      else
        a0 = argc > 0 ? ba[0] : nil
        a1 = argc > 1 ? ba[1] : nil
        a2 = argc > 2 ? ba[2] : nil
        a3 = argc > 3 ? ba[3] : nil
        more = nil
    k = jsr_kind(wvalue_bits(f) ## i64) & 15
    if k == KIND_FUNCTION
      c = f.code
      if (c.flags & CODE_CLASS) != 0
        JS_CALL_DEPTH[0] = d - 1
        begin
          js_throw_type("Class constructor " + c.name.to_s + " cannot be invoked without 'new'")
        rescue ex
          JS_REALM[0] = saved_realm
          raise ex
      if JS_DEADLINE_SEC[0] > ~0.0
        begin
          js_check_deadline()
        rescue ex
          JS_CALL_DEPTH[0] = d - 1
          JS_REALM[0] = saved_realm
          raise ex
      if c.node.is_a?(JaFunc) && c.entry == 0 && (c.flags & (CODE_GEN | CODE_ASYNC)) == 0
        JS_REALM[0] = c.realm if c.realm != nil
        next
    JS_CALL_DEPTH[0] = d - 1
    begin
      r = js_call(f, this, argc, a0, a1, a2, a3, more)
    rescue ex
      JS_REALM[0] = saved_realm
      raise ex
    JS_REALM[0] = saved_realm
    return r
  nil

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
  if jf.derived
    act.this = JS_TDZ
  else
    js_init_fields(act.this, act.fobj)
  r = wk_enter(jf, act, argc, a0, a1, a2, a3, more)
  r = wk_exec_pending_tail() if r == WK_TAIL
  return r if js_object?(r)
  if jf.derived && r != nil
    JS_REALM[0] = JS_CONSTRUCT_REALM[0] if JS_CONSTRUCT_REALM[0] != nil
    js_throw_type("Derived constructors may only return object or undefined")
  t = wk_this_value(jf, act)
  if t == JS_TDZ || t == nil
    JS_REALM[0] = JS_CONSTRUCT_REALM[0] if jf.derived && JS_CONSTRUCT_REALM[0] != nil
    js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")
  t

# The current this of a function's activation (its environment slot when arrows use it).
-> wk_this_value(jf, act)
  b = jf.this_binding
  return js_env_get(act.env_at_entry, b.slot) if b != nil && b.slot >= 0
  act.this

# A generator, async function or async generator: executed by the stackless state machine (sm_coro.w).
-> wk_call_suspendable(jf, f, this, argc, a0, a1, a2, a3, more)
  js_sm_call_suspendable(jf, f, this, argc, a0, a1, a2, a3, more)

# Suspend at yield or await (handled directly by sm_coro.w; unreachable from sync walk.w).
-> wk_suspend(act, k, v)
  js_throw(js_make_error("SyntaxError", "unexpected suspend outside coroutine"))

-> wk_whole(jf, act, argc, a0, a1, a2, a3, more)
  wk_prologue(jf, act, argc, a0, a1, a2, a3, more)
  wk_body(jf, act)

-> wk_enter(jf, act, argc, a0, a1, a2, a3, more)
  wk_prologue(jf, act, argc, a0, a1, a2, a3, more)
  wk_body(jf, act)

-> wk_body(jf, act)
  n = jf.node
  if jf.arrow && n.has?(F_EXPR_BODY)
    return wk_ev(n.b, act)
  if jf.body_scope != nil && jf.body_scope.has_dispose
    prev_disp = act.disp
    my_cap = JS:DisposeCap.new
    act.disp = my_cap
    begin
      wk_hoist_functions(n.b, act)
      wk_stmts(n.b, act)
    rescue ex
      act.disp = prev_disp
      js_dispose_resources_sync(my_cap, true, js_error_value(ex))
    act.disp = prev_disp
    js_dispose_resources_sync(my_cap, false, nil)
    return act.sig == WK_RETURN ? act.rv : nil
  wk_hoist_functions(n.b, act)
  wk_stmts(n.b, act)
  act.sig == WK_RETURN ? act.rv : nil

-> wk_prologue(jf, act, argc, a0, a1, a2, a3, more)
  if (jf.uses_this || jf.dynamic) && !jf.strict && !jf.arrow
    act.this = js_sloppy_this(act.this)
  # a named function expression sees itself under its name in its own outer scope
  if jf.self_scope != nil
    wk_scope_enter(jf.self_scope, act)
    wk_write(jf.self_binding, act.fobj, act)
  elsif jf.self_binding != nil
    wk_write(jf.self_binding, act.fobj, act)
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
  return nil if jf.arrow && n.has?(F_EXPR_BODY)
  bs = jf.body_scope
  if bs != sc
    wk_scope_enter(bs, act)
    jf.param_copies.each ->(pc) wk_write(pc[1], wk_read_binding_from(pc[0], bs, act), act)
  nil

# A non-simple parameter list: defaults, patterns and a rest element, in order.
-> wk_bind_params(jf, act, argc, a0, a1, a2, a3, more)
  # All parameters start in TDZ until initialized left-to-right (§10.2.11)
  jf.scope.order.each ->(b)
    if b.kind == :param
      if b.slot >= 0
        js_env_set(act.env, b.slot, JS_TDZ)
      elsif b.lidx >= 0
        act.locals[b.lidx] = JS_TDZ
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
    if p.a.kind == :super
      this = wk_this_for(p.a, act)
      raw_key = p.has?(F_COMPUTED) ? wk_ev(p.b, act) : p.b.str
      fo = wk_special(p.a, act, :fo)
      bv = jget_prototype_of(fo.home)
      js_throw_type("Cannot set properties of null") if bv == JS_NULL
      key = p.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
      ok = jset(bv, key, v, js_enc_recv(this))
      js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && act.f.strict
    else
      o = wk_ev(p.a, act)
      if p.b.kind == :private_name
        js_priv_set(o, wk_read_ref(p.b.x, act), v)
      else
        key = p.has?(F_COMPUTED) ? wk_ev(p.b, act) : p.b.str
        js_setv(o, key, v, act.f.strict)
  elsif k == :array_pattern
    wk_bind_array(p, v, act, decl)
  elsif k == :object_pattern
    wk_bind_object(p, v, act, decl)
  elsif k == :call
    wk_ev(p, act)
    js_throw_reference("Invalid left-hand side in assignment")
  else
    js_throw(js_make_error("SyntaxError", "tier 0: pattern " + k.to_s))
  nil

-> wk_bind_array(p, v, act, decl)
  rec = js_get_iterator(v)
  begin
    i = 0
    while i < p.list.size
      e = p.list[i]
      # a member target's object and key are evaluated before the value (§13.15.5.5)
      t = e == nil ? nil : (e.kind == :rest || e.kind == :assign_pattern ? e.a : e)
      mem = !decl && t != nil && t.kind == :member
      sup_mem = mem && t.a.kind == :super
      mo = nil
      mk = nil
      sthis = nil
      if sup_mem
        sthis = wk_this_for(t.a, act)
        mk = t.has?(F_COMPUTED) ? js_to_property_key(wk_ev(t.b, act)) : t.b.str
        fo = wk_special(t.a, act, :fo)
        mo = jget_prototype_of(fo.home)
      elsif mem
        mo = wk_ev(t.a, act)
        mk = t.b.kind == :private_name ? wk_read_ref(t.b.x, act) : (t.has?(F_COMPUTED) ? wk_ev(t.b, act) : t.b.str)
      x = nil
      if e != nil && e.kind == :rest
        rest = []
        while !rec.done
          y = js_iter_step(rec)
          rest.push(y) if y != JS_ITER_DONE
        x = js_mark_array(rest)
      else
        x = rec.done ? JS_ITER_DONE : js_iter_step(rec)
        x = nil if x == JS_ITER_DONE
      if sup_mem
        x = wk_ev(e.b, act) if e.kind == :assign_pattern && x == nil
        js_throw_type("Cannot set properties of null") if mo == JS_NULL
        ok = jset(mo, mk, x, js_enc_recv(sthis))
        js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(mk)) + "' of object") if !ok && act.f.strict
      elsif mem
        x = wk_ev(e.b, act) if e.kind == :assign_pattern && x == nil
        if t.b.kind == :private_name
          js_priv_set(mo, mk, x)
        else
          js_setv(mo, mk, x, act.f.strict)
      elsif e != nil
        wk_bind(e.kind == :rest ? e.a : e, x, act, decl)
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
      t = e.b.kind == :assign_pattern ? e.b.a : e.b
      if !decl && t.kind == :member && t.a.kind == :super
        sthis = wk_this_for(t.a, act)
        mk = t.has?(F_COMPUTED) ? js_to_property_key(wk_ev(t.b, act)) : t.b.str
        fo = wk_special(t.a, act, :fo)
        mo = jget_prototype_of(fo.home)
        x = js_get_value(v, key)
        x = wk_ev(e.b.b, act) if e.b.kind == :assign_pattern && x == nil
        js_throw_type("Cannot set properties of null") if mo == JS_NULL
        ok = jset(mo, mk, x, js_enc_recv(sthis))
        js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(mk)) + "' of object") if !ok && act.f.strict
      elsif !decl && t.kind == :member
        # the target's object and key first, then the value (§13.15.5.6)
        mo = wk_ev(t.a, act)
        mk = t.b.kind == :private_name ? wk_read_ref(t.b.x, act) : (t.has?(F_COMPUTED) ? wk_ev(t.b, act) : t.b.str)
        x = js_get_value(v, key)
        x = wk_ev(e.b.b, act) if e.b.kind == :assign_pattern && x == nil
        if t.b.kind == :private_name
          js_priv_set(mo, mk, x)
        else
          js_setv(mo, mk, x, act.f.strict)
      elsif !decl && t.kind == :ident && (act.f.dynamic || t.x.binding.kind == :dyn_eval)
        # ResolveBinding BEFORE GetV(v, key) (§13.15.5.6)
        dyn = wk_dyn_find(t.str, t.x, act)
        x = js_get_value(v, key)
        x = wk_ev(e.b.b, act) if e.b.kind == :assign_pattern && x == nil
        if dyn != nil
          if dyn[0] == :with
            wk_with_set(dyn[1], t.str, x, act.f.strict)
          else
            dyn[1][t.str] = x
        else
          wk_write_ref_static(t.x, x, act, false)
      else
        wk_bind(e.b, js_get_value(v, key), act, decl)
    i += 1
  nil

# A property key written in the source (identifier, string or number).
-> wk_prop_key(a)
  return js_number_to_s(a.a) if a.kind == :num
  return a.str if a.kind == :ident || a.kind == :string
  return js_bigint_literal(a.str).v.to_s if a.kind == :bigint
  js_throw(js_make_error("SyntaxError", "tier 0: key " + a.kind.to_s))

# Entering a scope with an environment record (or TDZ lexical bindings).
-> wk_scope_enter(sc, act)
  if sc.has_env?
    if sc.env_count > 7 || sc.has_dyn
      e = JS:EnvN.new(act.env, sc.env_count)
      e.dyn = {} if sc.has_dyn
    else
      e = JS:Env.new(act.env)
    js_gc_reg(e) if JS_GC_ON[0]
    act.env = e
  tb = sc.tdz_bindings
  if tb != nil
    i = 0
    while i < tb.size
      b = tb[i]
      if b.slot >= 0
        js_env_set(act.env, b.slot, JS_TDZ)
      elsif b.lidx >= 0
        act.locals[b.lidx] = JS_TDZ
      i += 1
  nil

# HasBinding on a `with` object (§9.1.1.2.1): checks `in` plus `@@unscopables`.
-> wk_with_has?(o, name)
  return false if !jhas_property?(o, name)
  u = jget(o, SYM_UNSCOPABLES)
  return true if !js_object?(u)
  !js_truthy(jget(u, name))

-> wk_with_get(o, name, strict)
  if !jhas_property?(o, name)
    js_throw_reference(name + " is not defined") if strict
    return nil
  jget(o, name)

-> wk_with_set(o, name, v, strict)
  still = jhas_property?(o, name)
  js_throw_reference(name + " is not defined") if !still && strict
  js_setv(o, name, v, strict)

# Walk dynamic (`with` / sloppy direct `eval`) environments between `ref.scope` and `ref.binding.scope`.
# Returns `[:with, obj]` or `[:dyn, hash]` if a dynamic binding shadows the static binding, else `nil`.
-> wk_dyn_find(name, ref, act)
  b = ref.binding
  is_dyn_b = b.kind == :dyn_eval
  stop_sc = (b.global? || is_dyn_b) ? nil : b.scope
  s = ref.scope
  e = act.env
  while s != nil && e != nil
    break if s == stop_sc
    if s.has_env?
      if s.is_with && e.is_a?(JS:WithEnv)
        return [:with, e.obj] if wk_with_has?(e.obj, name)
      elsif s.has_dyn && e.is_a?(JS:EnvN) && e.dyn != nil
        return [:dyn, e.dyn] if e.dyn.has_key?(name)
      e = js_env_up(e)
    if s.parent != nil && s.parent.func == s.func
      s = s.parent
    else
      s = s.func.def_scope
  nil

# ---- bindings ----

-> wk_env_at(act, hops)
  e = act.env
  while hops > 0
    js_throw_type("tier 0: no environment " + hops.to_s + " above, in " + act.f.name.to_s + " (" + (act.f.analysis.url == nil ? "" : act.f.analysis.url) + ":" + act.f.node.pos.to_s + ")") if e == nil
    e = js_env_up(e)
    hops -= 1
  js_throw_type("tier 0: missing environment in " + act.f.name.to_s + " (" + (act.f.analysis.url == nil ? "" : act.f.analysis.url) + ":" + act.f.node.pos.to_s + ")") if e == nil
  e

-> wk_hops(ref)
  h = ref.hops
  if h == nil
    h = ref.scope.func.analysis.env_hops(ref.scope, ref.binding.scope)
    ref.hops = h
  h

-> wk_const?(b)
  b.decl_const == true

-> wk_cell(b)
  if b.kind != :lexical
    lm = js_lexical_map()
    if lm.size > 0
      lc = lm[b.name]
      return lc if lc != nil
  c = b.cell
  if c == nil
    c = b.kind == :lexical ? js_lcell(b.name) : js_gcell(b.name)
    b.cell = c
  c

-> wk_check_tdz(b, v)
  if v == JS_TDZ
    if b.kind == :this
      js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")
    js_throw_reference("Cannot access '" + b.name + "' before initialization")
  v

-> wk_enclosing_mod(act)
  f = act.f
  while f != nil
    return f.mod_rec if f.mod_rec != nil
    f = f.parent
  nil

-> wk_read_ref_static(ref, act)
  b = ref.binding
  return js_mod_read_import(b.scope.func.mod_rec, b.name) if b.kind == :import
  return js_gget(js_gcell(b.name)) if b.kind == :dyn_eval
  if b.global?
    c = wk_cell(b)
    if c.value == JS_HOLE && (b.kind == :lexical || js_lexical_map().has_key?(b.name))
      js_throw_reference("Cannot access '" + b.name + "' before initialization")
    return js_gget(c)
  if b.scope.func != act.f
    v = act.f.single == b ? act.fe : js_env_get(wk_env_at(act, wk_hops(ref)), b.slot)
    return wk_check_tdz(b, v)
  return wk_check_tdz(b, js_env_get(wk_env_at(act, wk_hops(ref)), b.slot)) if b.slot >= 0
  return wk_check_tdz(b, act.this) if b.kind == :this
  wk_check_tdz(b, act.locals[b.lidx])

-> wk_write_ref_static(ref, v, act, init = false)
  b = ref.binding
  js_throw_type("Assignment to constant variable.") if b.kind == :import
  return js_gset(js_gcell(b.name), v, act.f.strict) if b.kind == :dyn_eval
  if b.global?
    if b.kind == :lexical
      return init ? js_linit(wk_cell(b), v, wk_const?(b)) : js_lset(wk_cell(b), v)
    lm = js_lexical_map()
    if lm.size > 0
      lc = lm[b.name]
      return js_lset(lc, v) if lc != nil
    return js_gset(wk_cell(b), v, act.f.strict)
  if b.kind == :self
    js_throw_type("Assignment to constant variable.") if act.f.strict
    return v
  if !init && (b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :class_inner || b.kind == :param)
    cur = b.slot >= 0 ? js_env_get(wk_env_at(act, wk_hops(ref)), b.slot) : act.locals[b.lidx]
    js_throw_reference("Cannot access '" + b.name + "' before initialization") if cur == JS_TDZ
  js_throw_type("Assignment to constant variable.") if !init && (b.kind == :const || b.kind == :class_inner)
  if b.slot >= 0
    js_env_set(wk_env_at(act, wk_hops(ref)), b.slot, v)
    return v
  act.locals[b.lidx] = v
  v

-> wk_read_ref(ref, act)
  b = ref.binding
  return js_mod_read_import(b.scope.func.mod_rec, b.name) if b.kind == :import
  if act.f.dynamic || b.kind == :dyn_eval
    dyn = wk_dyn_find(b.name, ref, act)
    if dyn != nil
      return dyn[0] == :with ? wk_with_get(dyn[1], b.name, act.f.strict) : dyn[1][b.name]
  return js_gget(js_gcell(b.name)) if b.kind == :dyn_eval
  if b.global?
    c = wk_cell(b)
    if c.value == JS_HOLE && (b.kind == :lexical || js_lexical_map().has_key?(b.name))
      js_throw_reference("Cannot access '" + b.name + "' before initialization")
    return js_gget(c)
  if b.scope.func != act.f
    v = act.f.single == b ? act.fe : js_env_get(wk_env_at(act, wk_hops(ref)), b.slot)
    return wk_check_tdz(b, v)
  return wk_check_tdz(b, js_env_get(wk_env_at(act, wk_hops(ref)), b.slot)) if b.slot >= 0
  return wk_check_tdz(b, act.this) if b.kind == :this
  wk_check_tdz(b, act.locals[b.lidx])

-> wk_write_ref(ref, v, act, init = false)
  b = ref.binding
  if !init && (act.f.dynamic || b.kind == :dyn_eval)
    dyn = wk_dyn_find(b.name, ref, act)
    if dyn != nil
      if dyn[0] == :with
        wk_with_set(dyn[1], b.name, v, act.f.strict)
      else
        dyn[1][b.name] = v
      return v
  return js_gset(js_gcell(b.name), v, act.f.strict) if b.kind == :dyn_eval
  if b.global?
    if b.kind == :lexical
      return init ? js_linit(wk_cell(b), v, wk_const?(b)) : js_lset(wk_cell(b), v)
    lm = js_lexical_map()
    if lm.size > 0
      lc = lm[b.name]
      return js_lset(lc, v) if lc != nil
    return js_gset(wk_cell(b), v, act.f.strict)
  if b.kind == :self
    # a named function expression's own name is immutable: ignored in sloppy code
    js_throw_type("Assignment to constant variable.") if act.f.strict
    return v
  if !init && (b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :class_inner || b.kind == :param)
    cur = b.slot >= 0 ? js_env_get(wk_env_at(act, wk_hops(ref)), b.slot) : act.locals[b.lidx]
    js_throw_reference("Cannot access '" + b.name + "' before initialization") if cur == JS_TDZ
  js_throw_type("Assignment to constant variable.") if !init && (b.kind == :const || b.kind == :class_inner)
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

-> wk_unwrap_labeled_fn(s)
  cur = s
  while cur != nil && cur.kind == :labeled
    cur = cur.a
  (cur != nil && cur.kind == :function_decl && cur.str != nil) ? cur : nil

-> wk_dyn_var_find(name, ref, act)
  b = ref.binding
  is_dyn_b = b.kind == :dyn_eval
  stop_sc = (b.global? || is_dyn_b) ? nil : b.scope
  s = ref.scope
  e = act.env
  while s != nil && e != nil
    break if s == stop_sc
    if s.has_env?
      if s.has_dyn && e.is_a?(JS:EnvN) && e.dyn != nil
        return [:dyn, e.dyn] if e.dyn.has_key?(name)
      e = js_env_up(e)
    if s.parent != nil && s.parent.func == s.func
      s = s.parent
    else
      s = s.func.def_scope
  nil

-> wk_hoist_functions(stmts, act)
  any = false
  i = 0
  while i < stmts.size
    s = wk_unwrap_labeled_fn(stmts[i])
    if s != nil
      any = true
      jf = s.x
      b = jf.binding
      fo = js_closure(wk_code(jf), wk_env_for(jf, act))
      if b.global?
        js_gdeclare(wk_cell(b), fo, true, act.f.analysis.eval_mode ? ATTR_W + ATTR_E + ATTR_C : ATTR_W + ATTR_E)
      else
        wk_write_decl(jf, fo, act)
    i += 1
  any

# A function declaration's binding gets its object (seen from where it is declared).
-> wk_write_decl(jf, v, act)
  b = jf.binding
  if b.kind == :dyn_eval
    dyn = wk_dyn_find(b.name, JaRef.new(b, jf.def_scope), act)
    if dyn != nil && dyn[0] == :dyn
      dyn[1][b.name] = v
      return v
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
  return nil if jf.free.size == 0 && !jf.dynamic
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
    # the completion value (eval); a function's return value replaces it on return
    act.rv = wk_ev(s.a, act)
  elsif k == :var_decl
    is_using = s.str == "using"
    i = 0
    while i < s.list.size
      d = s.list[i]
      if is_using
        v = wk_ev(d.b, act)
        js_add_disposable_resource(act.disp, v, :sync, false, nil)
        wk_write_ref(d.a.x, v, act, true)
      elsif d.a.kind != :ident
        wk_bind(d.a, wk_ev(d.b, act), act, s.str != "var")
      elsif d.b != nil
        if s.str == "var" && (act.f.dynamic || d.a.x.binding.kind == :dyn_eval)
          # ResolveBinding BEFORE evaluating Initializer (§14.3.2.1)
          dyn = wk_dyn_find(d.a.str, d.a.x, act)
          v = wk_ev(d.b, act)
          if dyn != nil
            if dyn[0] == :with
              wk_with_set(dyn[1], d.a.str, v, act.f.strict)
            else
              dyn[1][d.a.str] = v
          else
            wk_write_ref_static(d.a.x, v, act, false)
        else
          wk_write_ref(d.a.x, wk_ev(d.b, act), act, s.str != "var")
      elsif s.str != "var"
        wk_write_ref(d.a.x, nil, act, true)
      i += 1
  elsif k == :if
    # if, loops, try and switch complete with undefined when nothing inside produced a
    # value (UpdateEmpty: the completion value eval and scripts report)
    act.rv = nil
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
    act.rv = nil
    wk_for(s, act, nil)
  elsif k == :while
    act.rv = nil
    wk_while(s, act, nil)
  elsif k == :do_while
    act.rv = nil
    wk_do_while(s, act, nil)
  elsif k == :break
    act.sig = WK_BREAK
    act.label = s.str
  elsif k == :continue
    act.sig = WK_CONTINUE
    act.label = s.str
  elsif k == :throw
    v = wk_ev(s.a, act)
    act.pos = s.pos
    js_throw(v)
  elsif k == :try
    act.rv = nil
    wk_try(s, act)
  elsif k == :function_decl
    jf = s.x
    if jf.in_if && jf.binding != nil
      wk_write_decl(jf, js_closure(wk_code(jf), wk_env_for(jf, act)), act)
    elsif jf.annexb != nil
      # Annex B: evaluating the declaration copies the block's binding into the nearest VariableEnvironment (skipping with objects!)
      v = wk_read_binding_from(jf.binding, jf.def_scope, act)
      aref = JaRef.new(jf.annexb, jf.def_scope)
      if jf.annexb.kind == :dyn_eval
        dyn = wk_dyn_var_find(jf.annexb.name, aref, act)
        if dyn != nil
          dyn[1][jf.annexb.name] = v
        else
          js_gset(js_gcell(jf.annexb.name), v, act.f.strict)
      else
        wk_write_ref_static(aref, v, act)
  elsif k == :switch
    act.rv = nil
    wk_switch(s, act, nil)
  elsif k == :class_decl
    wk_write_ref(s.c, wk_class(s, act), act, true)
  elsif k == :for_in
    act.rv = nil
    wk_for_in(s, act, nil)
  elsif k == :for_of
    act.rv = nil
    wk_for_of(s, act, nil)
  elsif k == :labeled
    wk_labeled(s, act, [s.str])
  elsif k == :with
    o = js_to_object(wk_ev(s.a, act))
    saved = act.env
    act.env = JS:WithEnv.new(saved, o)
    act.rv = nil
    begin
      wk_ex(s.b, act)
    rescue ex
      act.env = saved
      raise ex
    act.env = saved
  elsif k == :empty || k == :debugger || k == :import_decl || k == :export_all
    nil
  elsif k == :export_named
    wk_ex(s.a, act) if s.a != nil
  elsif k == :export_default
    d = s.a
    if d.kind == :function_decl
      nil
    elsif d.kind == :class_decl
      wk_ex(d, act)
    else
      v = wk_ev(d, act)
      js_set_fn_name(v, "default", nil) if wk_anonymous_fn?(d) && !(d.kind == :class && wk_class_has_static_name?(d))
      wk_write_ref(s.c, v, act, true)
  else
    js_throw(js_make_error("SyntaxError", "tier 0: statement " + k.to_s))
  nil

-> wk_block(node, list, act)
  sc = node.x
  saved = act.env
  if sc.is_a?(JaScope) && sc.has_dispose
    prev_disp = act.disp
    my_cap = JS:DisposeCap.new
    act.disp = my_cap
    begin
      wk_scope_enter(sc, act)
      wk_hoist_functions(list, act)
      wk_stmts(list, act)
    rescue ex
      act.disp = prev_disp
      act.env = saved
      js_dispose_resources_sync(my_cap, true, js_error_value(ex))
    act.disp = prev_disp
    act.env = saved
    js_dispose_resources_sync(my_cap, false, nil)
    return nil
  if sc.is_a?(JaScope)
    wk_scope_enter(sc, act)
  if node.d != false
    node.d = false if !wk_hoist_functions(list, act)
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

# Does loop statement `s` contain an inner loop or call (so 2 iterations warm all ICs and
# OSR should kick in immediately instead of spending 16 outer iterations in tier 0)?
-> wk_loop_heavy?(n)
  return false if !n.is_a?(JsNode)
  k = n.kind
  return true if k == :for || k == :while || k == :do_while || k == :call
  return true if wk_loop_heavy?(n.a) || wk_loop_heavy?(n.b) || wk_loop_heavy?(n.c) || wk_loop_heavy?(n.d)
  if n.list.is_a?(Array)
    i = 0
    while i < n.list.size
      return true if wk_loop_heavy?(n.list[i])
      i += 1
  false

-> wk_while(s, act, labels)
  ofp = s.osr_fp
  if ofp > 0 && labels == nil && JS_DEADLINE_SEC[0] <= ~0.0 && JS_UI_PUMP_HOOK[0] == nil && !(JS_GC_ON[0] && JS_GC_HEAP.size >= JS_GC_NEXT[0])
    rc = jit_run_osr_fp(ofp, act)
    return nil if rc == 0 || rc == 2
  it = 0
  thr = ofp > 0 ? 0 : (wk_loop_heavy?(s.b) ? 2 : WK_JIT_OSR_THRESH)
  while true
    js_check_deadline() if JS_DEADLINE_SEC[0] > ~0.0
    js_ui_pump_maybe() if JS_UI_PUMP_HOOK[0] != nil
    js_gc_backedge(act) if JS_GC_ON[0] && JS_GC_HEAP.size >= JS_GC_NEXT[0]
    if ofp >= 0 && it == thr && labels == nil && JS_DEADLINE_SEC[0] <= ~0.0
      rc = jit_try_osr(s, act)
      ofp = s.osr_fp
      break if rc == 0
      return nil if rc == 2
    break if !js_truthy(wk_ev(s.a, act))
    it += 1
    wk_ex(s.b, act)
    r = wk_loop_signal(act, labels)
    return nil if r == WK_RETURN
    break if r == WK_BREAK
  nil

-> wk_do_while(s, act, labels)
  while true
    js_check_deadline() if JS_DEADLINE_SEC[0] > ~0.0
    js_ui_pump_maybe() if JS_UI_PUMP_HOOK[0] != nil
    js_gc_backedge(act) if JS_GC_ON[0] && JS_GC_HEAP.size >= JS_GC_NEXT[0]
    wk_ex(s.a, act)
    r = wk_loop_signal(act, labels)
    return nil if r == WK_RETURN
    break if r == WK_BREAK
    break if !js_truthy(wk_ev(s.b, act))
  nil

-> wk_for(s, act, labels)
  fs = s.x
  saved = act.env
  has_disp = fs.is_a?(JaScope) && fs.has_dispose
  per = fs.is_a?(JaScope) && fs.has_env?
  prev_disp = act.disp
  my_cap = has_disp ? JS:DisposeCap.new : nil
  act.disp = my_cap if has_disp
  begin
    wk_scope_enter(fs, act) if fs.is_a?(JaScope)
    if s.a != nil
      if s.a.kind == :var_decl
        wk_ex(s.a, act)
      else
        wk_ev(s.a, act)
    act.env = js_env_copy(act.env) if per
    ofp = s.osr_fp
    if ofp > 0 && !has_disp && !per && labels == nil && JS_DEADLINE_SEC[0] <= ~0.0 && JS_UI_PUMP_HOOK[0] == nil && !(JS_GC_ON[0] && JS_GC_HEAP.size >= JS_GC_NEXT[0])
      rc = jit_run_osr_fp(ofp, act)
      if rc == 0 || rc == 2
        act.env = saved
        return nil
    it = 0
    thr = ofp > 0 ? 0 : (wk_loop_heavy?(s.d) ? 2 : WK_JIT_OSR_THRESH)
    while true
      js_check_deadline() if JS_DEADLINE_SEC[0] > ~0.0
      js_ui_pump_maybe() if JS_UI_PUMP_HOOK[0] != nil
      js_gc_backedge(act) if JS_GC_ON[0] && JS_GC_HEAP.size >= JS_GC_NEXT[0]
      if ofp >= 0 && !has_disp && it == thr && !per && labels == nil && JS_DEADLINE_SEC[0] <= ~0.0
        rc = jit_try_osr(s, act)
        ofp = s.osr_fp
        break if rc == 0
        if rc == 2
          act.env = saved
          return nil
      break if s.b != nil && !js_truthy(wk_ev(s.b, act))
      it += 1
      wk_ex(s.d, act)
      r = wk_loop_signal(act, labels)
      if r == WK_RETURN
        break
      break if r == WK_BREAK
      act.env = js_env_copy(act.env) if per
      wk_ev(s.c, act) if s.c != nil
  rescue ex
    if has_disp
      act.disp = prev_disp
      act.env = saved
      js_dispose_resources_sync(my_cap, true, js_error_value(ex))
    act.env = saved
    raise ex
  act.env = saved
  if has_disp
    act.disp = prev_disp
    js_dispose_resources_sync(my_cap, false, nil)
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
    d0 = s.a.list[0]
    iv = wk_ev(d0.b, act)
    if d0.a.kind == :ident && wk_anonymous_fn?(d0.b) && !(d0.b.kind == :class && wk_class_has_static_name?(d0.b))
      js_set_fn_name(iv, d0.a.str, nil)
    wk_bind(d0.a, iv, act, false)
  wk_scope_enter(fs, act) if fs.is_a?(JaScope)
  obj = wk_ev(s.b, act)
  ks = js_for_in_keys(obj)
  sh0 = obj.is_a?(JS:Object) && !obj.shape.dict ? obj.shape : nil
  i = 0
  while i < ks.size
    k = ks[i]
    i += 1
    # a key deleted before it is reached is not visited (skip lookup if shape is unchanged!)
    if !(sh0 != nil && obj.shape == sh0) && js_object?(obj) && !jhas_property?(obj, k)
      next
    if fs.is_a?(JaScope)
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

# for await (x of o) is compiled & executed by sm_coro.w (never reached in sync walk.w).
-> wk_for_await(s, act, labels)
  js_throw(js_make_error("SyntaxError", "for await outside async function"))

-> wk_for_of(s, act, labels)
  return wk_for_await(s, act, labels) if s.has?(F_AWAIT)
  fs = s.x
  saved = act.env
  per = fs.is_a?(JaScope) && fs.has_env?
  is_using = s.a.kind == :var_decl && s.a.str == "using"
  # the right side is evaluated in the head's scope (its let bindings' dead zone), as the
  # analysis resolved it
  wk_scope_enter(fs, act) if fs.is_a?(JaScope)
  rec = js_get_iterator(wk_ev(s.b, act))
  begin
    while true
      v = js_iter_step(rec)
      break if v == JS_ITER_DONE
      if fs.is_a?(JaScope)
        act.env = saved
        wk_scope_enter(fs, act)
      if is_using
        prev_disp = act.disp
        iter_cap = JS:DisposeCap.new
        act.disp = iter_cap
        begin
          js_add_disposable_resource(iter_cap, v, :sync, false, nil)
          wk_for_head(s, v, act)
          wk_ex(s.d, act)
        rescue ex2
          act.disp = prev_disp
          js_dispose_resources_sync(iter_cap, true, js_error_value(ex2))
        act.disp = prev_disp
        js_dispose_resources_sync(iter_cap, false, nil)
      else
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
    raise ex if ex.is_a?(JS:TimeoutError)
    JS_CUR_ACT[0] = act
    pending = ex
  act.env = saved
  sg = act.sig
  lb = act.label
  rv = act.rv
  act.sig = 0
  act.label = nil
  act.rv = nil
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
    raise ex if ex.is_a?(JS:TimeoutError)
    JS_CUR_ACT[0] = act
    act.env = saved
    act.rv = nil
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

# Build/fetch cached switch dispatch metadata on s.d:
#   [has_fn_decls (bool), lit_map (Hash or nil), dflt_idx (int)]
# Eliminates per-execution function-declaration rescans and gives O(1) dispatch for dense switches.
-> wk_switch_meta(s)
  m = s.d
  return m if m != nil
  n = s.list.size
  has_fn = false
  all_lit = n >= 4
  dflt = n
  lmap = nil
  i = 0
  while i < n
    c = s.list[i]
    if c.a == nil
      dflt = i
    elsif all_lit
      ck = c.a.kind
      if ck != :num && ck != :string
        all_lit = false
    if !has_fn
      j = 0
      while j < c.list.size
        if wk_unwrap_labeled_fn(c.list[j]) != nil
          has_fn = true
          break
        j += 1
    i += 1
  if all_lit
    lmap = {}
    i = 0
    while i < n
      c = s.list[i]
      if c.a != nil
        kv = c.a.kind == :num ? c.a.a : c.a.str
        # Preserve first matching clause (JS evaluates case expressions in order)
        lmap[kv] = i if !lmap.has_key?(kv)
      i += 1
  m = [has_fn, lmap, dflt]
  s.d = m
  m

-> wk_switch(s, act, labels)
  saved = act.env
  bs = s.x
  d = wk_ev(s.a, act)
  wk_scope_enter(bs, act) if bs.is_a?(JaScope)
  n = s.list.size
  meta = wk_switch_meta(s)
  if meta[0]
    hi = 0
    while hi < n
      wk_hoist_functions(s.list[hi].list, act)
      hi += 1
  lmap = meta[1]
  ix = -1
  if lmap != nil && (js_number?(d) || js_string?(d))
    # O(1) dense literal switch lookup (NaN never matches any case via ===)
    if js_string?(d) || d == d
      k = js_number?(d) && d == ~0.0 ? ~0.0 : d
      hit = lmap[k]
      ix = hit != nil ? hit : meta[2]
    else
      ix = meta[2]
  else
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
    if e.has?(F_COMPUTED)
      idx = wk_ev(e.b, act)
      if js_array?(o) && (js_array_flags(o) & 15) == JS_AF_ARRAY && js_number?(idx)
        ii = jsr_i32(wvalue_bits(idx) ## i64)
        if ii >= 0 && ii < o.size && ii.to_f == idx
          return o[ii]
      return js_getv(o, idx)
    return js_priv_get(o, wk_read_ref(e.b.x, act)) if e.b.kind == :private_name
    return js_getp_ic(o, e.b.str, wk_ic(e))
  if k == :call
    act.pos = e.pos
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
    act.pos = e.pos
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
  if k == :yield
    v = e.a == nil ? nil : wk_ev(e.a, act)
    act.pos = e.pos
    return wk_suspend(act, 1, v) if e.has?(F_DELEGATE)
    return wk_suspend(act, 2, v) if act.f.node.has?(F_ASYNC)
    return wk_suspend(act, 0, v)
  if k == :await
    v = wk_ev(e.a, act)
    act.pos = e.pos
    return wk_suspend(act, 3, v)
  if k == :class
    return wk_class(e, act)
  if k == :meta_property
    return js_mod_get_meta(wk_enclosing_mod(act)) if e.str == "import.meta"
    return wk_special(e, act, :nt)
  if k == :import_call
    spec_v = wk_ev(e.a, act)
    opts_v = e.b == nil ? nil : wk_ev(e.b, act)
    em = wk_enclosing_mod(act)
    ref_url = em != nil ? em.url : JS_CURRENT_URL[0]
    phase = e.str == "defer" ? :defer : (e.str == "source" ? :source : :evaluation)
    return js_mod_dynamic_import(ref_url, spec_v, opts_v, phase)
  if k == :template
    sb = StringBuffer()
    i = 0
    while i < e.list.size
      sb.append(e.list[i].str)
      sb.append(js_template_string(wk_ev(e.a[i], act))) if i < e.a.size
      i += 1
    r = sb.to_s
    ccall("w_value_free_w", sb)
    return r
  if k == :tagged_template
    return wk_tagged(e, act)
  if k == :chain
    v = wk_chain(e.a, act)
    return v == WK_SHORT ? nil : v
  if k == :regex
    return js_regexp_create(e.str, e.a)
  if k == :bigint
    bv = e.x
    if bv == nil
      bv = js_bigint_literal(e.str)
      e.x = bv
      jit_keep(bv)
    return bv
  js_throw(js_make_error("SyntaxError", "tier 0: expression " + k.to_s))


-> wk_tagged(e, act)
  t = e.b
  tc = js_realm().template_cache
  tobj = tc[t]
  if tobj == nil
    cooked = []
    raw = []
    t.list.each ->(q)
      cooked.push(q.str)
      raw.push(q.a)
    tobj = js_template_object(cooked, raw)
    tc[t] = tobj
  c = e.a
  this = nil
  f = nil
  if c.kind == :member && c.a.kind == :super
    # super.tag`…`: the home object's prototype has the tag, this is the method's this
    f = wk_super_get(c, act)
    this = wk_this_for(c.a, act)
  elsif c.kind == :member
    this = wk_ev(c.a, act)
    f = c.has?(F_COMPUTED) ? js_getv(this, wk_ev(c.b, act)) : js_getp_ic(this, c.b.str, wk_ic(c))
  else
    f = wk_ev(c, act)
  args = [tobj]
  t.a.each ->(x) args.push(wk_ev(x, act))
  e.has?(F_TAIL) ? wk_tail_arr(f, this, args) : js_call_arr(f, this, args)

# Optional chains: WK_SHORT travels out of the chain when a ?. link meets null/undefined.
+ WkShort
  -> new
    nil
WK_SHORT = WkShort.new

-> wk_chain(e, act)
  k = e.kind
  if k == :member
    return wk_super_get(e, act) if e.a.kind == :super
    o = wk_chain(e.a, act)
    return WK_SHORT if o == WK_SHORT
    return WK_SHORT if e.has?(F_OPTIONAL) && js_nullish?(o)
    return js_getv(o, wk_ev(e.b, act)) if e.has?(F_COMPUTED)
    return js_priv_get(o, wk_read_ref(e.b.x, act)) if e.b.kind == :private_name
    return js_getp_ic(o, e.b.str, wk_ic(e))
  if k == :call
    c = e.a
    return wk_super_call(e, act) if c.kind == :super
    c = c.a if c.kind == :chain
    this = nil
    f = nil
    if c.kind == :member
      if c.a.kind == :super
        f = wk_super_get(c, act)
        this = wk_this_for(c.a, act)
      else
        this = wk_chain(c.a, act)
        return WK_SHORT if this == WK_SHORT
        return WK_SHORT if c.has?(F_OPTIONAL) && js_nullish?(this)
        if c.b.kind == :private_name
          f = js_priv_get(this, wk_read_ref(c.b.x, act))
        else
          f = c.has?(F_COMPUTED) ? js_getv(this, wk_ev(c.b, act)) : js_getp_ic(this, c.b.str, wk_ic(c))
    else
      f = wk_chain(c, act)
      return WK_SHORT if f == WK_SHORT
    return WK_SHORT if e.has?(F_OPTIONAL) && js_nullish?(f)
    return wk_call_args(f, this, e.list, act, e.has?(F_TAIL))
  wk_ev(e, act)

-> wk_read_ident(e, act)
  ref = e.x
  b = ref.binding
  if b.kind == :global && b.writes == 0 && !act.f.dynamic
    nm = e.str
    return nil if nm == "undefined"
  wk_read_ref(ref, act)

-> wk_this(e, act)
  f = act.f
  if !f.arrow || f.script || f.mod_rec != nil
    v = (!f.script && f.mod_rec == nil && f.this_binding != nil && f.this_binding.slot >= 0) ? js_env_get(act.env_at_entry, f.this_binding.slot) : act.this
    js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor") if v == JS_TDZ
    return v
  g = f
  while g.arrow
    g = g.parent
  return js_realm().global if g.script
  return nil if g.mod_rec != nil
  wk_read_binding_from(g.this_binding, e.x.scope, act)

WK_OPS = {"+" => 1, "-" => 2, "*" => 3, "/" => 4, "%" => 5, "<" => 6, ">" => 7, "<=" => 8, ">=" => 9, "===" => 10, "!==" => 11, "==" => 12, "!=" => 13, "|" => 14, "&" => 15, "^" => 16, "<<" => 17, ">>" => 18, ">>>" => 19, "**" => 20, "instanceof" => 21, "in" => 22}
WK_AOPS = {"+=" => 1, "-=" => 2, "*=" => 3, "/=" => 4, "%=" => 5, "|=" => 14, "&=" => 15, "^=" => 16, "<<=" => 17, ">>=" => 18, ">>>=" => 19, "**=" => 20}

-> wk_binop_code(c, a, b, op = "")
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

-> wk_binop(op, a, b)
  wk_binop_code(WK_OPS[op], a, b, op)

-> wk_assign_op(e, cur, rhs)
  c = e.d
  if c == nil
    c = WK_AOPS[e.str]
    e.d = c
  wk_binop_code(c, cur, rhs, e.str)

-> wk_binary(e, act)
  if e.a.kind == :private_name
    o = wk_ev(e.b, act)
    js_throw_type("Cannot use 'in' operator to search for a private field in a non-object") if !js_object?(o)
    return o.is_a?(JS:Base) && o.priv_has?(wk_read_ref(e.a.x, act))
  a = wk_ev(e.a, act)
  b = wk_ev(e.b, act)
  c = e.d
  if c == nil
    c = WK_OPS[e.str]
    e.d = c
  if js_number?(a) && js_number?(b)
    return a + b if c == 1
    return a - b if c == 2
    return a * b if c == 3
    return a < b if c == 6
    return a > b if c == 7
    return a <= b if c == 8
    return a >= b if c == 9
    return a == b if c == 10
    return a != b if c == 11
  wk_binop_code(c, a, b, e.str)

-> wk_unary(e, act)
  op = e.str
  if op == "typeof"
    a = e.a
    if a.kind == :ident
      return js_typeof(js_mod_read_import(a.x.binding.scope.func.mod_rec, a.x.binding.name)) if a.x.binding.kind == :import
      if act.f.dynamic || a.x.binding.kind == :dyn_eval
        dyn = wk_dyn_find(a.str, a.x, act)
        if dyn != nil
          return js_typeof(dyn[0] == :with ? wk_with_get(dyn[1], a.str, act.f.strict) : dyn[1][a.str])
      if a.x.binding.global?
        c = wk_cell(a.x.binding)
        if c.value == JS_HOLE && (a.x.binding.kind == :lexical || js_lexical_map().has_key?(a.str))
          js_throw_reference("Cannot access '" + a.str + "' before initialization")
        return js_gtypeof(c)
    return js_typeof(wk_ev(a, act))
  if op == "delete"
    a = e.a
    if a.kind == :chain
      ce = a.a
      if ce.kind == :member
        o = wk_chain(ce.a, act)
        return true if o == WK_SHORT
        return true if ce.has?(F_OPTIONAL) && js_nullish?(o)
        key = ce.has?(F_COMPUTED) ? wk_ev(ce.b, act) : ce.b.str
        return js_delete(o, key, act.f.strict)
      wk_chain(ce, act)
      return true
    if a.kind == :member
      if a.a.kind == :super
        wk_this_for(a.a, act)
        wk_ev(a.b, act) if a.has?(F_COMPUTED)
        js_throw_reference("Unsupported reference to 'super'")
      o = wk_ev(a.a, act)
      key = a.has?(F_COMPUTED) ? wk_ev(a.b, act) : a.b.str
      return js_delete(o, key, act.f.strict)
    if a.kind == :ident
      if act.f.dynamic || a.x.binding.kind == :dyn_eval
        dyn = wk_dyn_find(a.str, a.x, act)
        if dyn != nil
          return js_delete(dyn[1], a.str, false) if dyn[0] == :with
          dyn[1].delete(a.str)
          return true
      b = a.x.binding
      return js_delete(js_realm().global, a.str, false) if b.kind == :dyn_eval
      if b.global?
        return false if b.kind == :lexical
        return js_delete(js_realm().global, a.str, false)
      return false
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
  if t.kind == :call
    wk_ev(t, act)
    js_throw_reference("Invalid left-hand side expression in update")
  if t.kind == :ident
    if act.f.dynamic || t.x.binding.kind == :dyn_eval
      dyn = wk_dyn_find(t.str, t.x, act)
      if dyn != nil
        old = js_tonumeric(dyn[0] == :with ? wk_with_get(dyn[1], t.str, act.f.strict) : dyn[1][t.str])
        nv = js_inc(old, inc)
        if dyn[0] == :with
          wk_with_set(dyn[1], t.str, nv, act.f.strict)
        else
          dyn[1][t.str] = nv
        return e.has?(F_PREFIX) ? nv : old
    old = js_tonumeric(wk_read_ref_static(t.x, act))
    nv = js_inc(old, inc)
    wk_write_ref_static(t.x, nv, act)
    return e.has?(F_PREFIX) ? nv : old
  if t.a.kind == :super
    this = wk_this_for(t.a, act)
    raw_key = t.has?(F_COMPUTED) ? wk_ev(t.b, act) : t.b.str
    fo = wk_special(t.a, act, :fo)
    bv = jget_prototype_of(fo.home)
    js_throw_type("Cannot read properties of null") if bv == JS_NULL
    key = t.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
    old = js_tonumeric(jget(bv, key, js_enc_recv(this)))
    nv = js_inc(old, inc)
    ok = jset(bv, key, nv, js_enc_recv(this))
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && act.f.strict
    return e.has?(F_PREFIX) ? nv : old
  o = wk_ev(t.a, act)
  if t.b.kind == :private_name
    pn = wk_read_ref(t.b.x, act)
    old = js_tonumeric(js_priv_get(o, pn))
    nv = js_inc(old, inc)
    js_priv_set(o, pn, nv)
    return e.has?(F_PREFIX) ? nv : old
  if !t.has?(F_COMPUTED)
    key = t.b.str
    js_throw_type("Cannot read properties of " + js_to_display(o)) if js_nullish?(o)
    old = js_tonumeric(js_getp_ic(o, key, wk_ic(e)))
    nv = js_inc(old, inc)
    js_setp_ic(o, key, nv, wk_ic(t), act.f.strict)
    return e.has?(F_PREFIX) ? nv : old
  raw_key = wk_ev(t.b, act)
  js_throw_type("Cannot read properties of " + js_to_display(o)) if js_nullish?(o)
  key = js_to_property_key(raw_key)
  old = js_tonumeric(js_getv(o, key))
  nv = js_inc(old, inc)
  js_setv(o, key, nv, act.f.strict)
  e.has?(F_PREFIX) ? nv : old

-> wk_assign(e, act)
  op = e.str
  t = e.a
  if t.kind == :call
    wk_ev(t, act)
    js_throw_reference("Invalid left-hand side in assignment")
  if t.kind == :ident
    ref = t.x
    if act.f.dynamic || ref.binding.kind == :dyn_eval
      dyn = wk_dyn_find(t.str, ref, act)
      if dyn != nil
        if op == "="
          v = wk_ev(e.b, act)
        elsif op == "&&=" || op == "||=" || op == "??="
          cur = dyn[0] == :with ? wk_with_get(dyn[1], t.str, act.f.strict) : dyn[1][t.str]
          return cur if op == "&&=" && !js_truthy(cur)
          return cur if op == "||=" && js_truthy(cur)
          return cur if op == "??=" && !js_nullish?(cur)
          v = wk_ev(e.b, act)
        else
          cur = dyn[0] == :with ? wk_with_get(dyn[1], t.str, act.f.strict) : dyn[1][t.str]
          v = wk_assign_op(e, cur, wk_ev(e.b, act))
        if dyn[0] == :with
          wk_with_set(dyn[1], t.str, v, act.f.strict)
        else
          dyn[1][t.str] = v
        return v
    strict_unres = act.f.strict && op == "=" && ref.binding.kind == :global && wk_cell(ref.binding).value == JS_HOLE && !js_lexical_map().has_key?(ref.binding.name)
    if op == "="
      v = wk_ev(e.b, act)
      js_throw_reference(ref.binding.name + " is not defined") if strict_unres
    elsif op == "&&=" || op == "||=" || op == "??="
      cur = wk_read_ref_static(ref, act)
      return cur if op == "&&=" && !js_truthy(cur)
      return cur if op == "||=" && js_truthy(cur)
      return cur if op == "??=" && !js_nullish?(cur)
      v = wk_ev(e.b, act)
    else
      v = wk_assign_op(e, wk_read_ref_static(ref, act), wk_ev(e.b, act))
    wk_write_ref_static(ref, v, act)
    return v
  if t.kind == :object_pattern || t.kind == :array_pattern
    v = wk_ev(e.b, act)
    wk_bind(t, v, act, false)
    return v
  if t.a.kind == :super
    this = wk_this_for(t.a, act)
    raw_key = t.has?(F_COMPUTED) ? wk_ev(t.b, act) : t.b.str
    fo = wk_special(t.a, act, :fo)
    bv = jget_prototype_of(fo.home)
    if op == "="
      v = wk_ev(e.b, act)
      js_throw_type("Cannot set properties of null") if bv == JS_NULL
      key = t.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
      ok = jset(bv, key, v, js_enc_recv(this))
      js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && act.f.strict
      return v
    js_throw_type("Cannot read properties of null") if bv == JS_NULL
    key = t.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
    cur = jget(bv, key, js_enc_recv(this))
    if op == "&&=" || op == "||=" || op == "??="
      return cur if (op == "&&=" && !js_truthy(cur)) || (op == "||=" && js_truthy(cur)) || (op == "??=" && !js_nullish?(cur))
      v = wk_ev(e.b, act)
    else
      v = wk_binop(op.slice(0, op.size - 1), cur, wk_ev(e.b, act))
    ok = jset(bv, key, v, js_enc_recv(this))
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && act.f.strict
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
    raw_key = t.has?(F_COMPUTED) ? wk_ev(t.b, act) : t.b.str
    js_throw_type("Cannot read properties of " + js_to_display(o)) if js_nullish?(o)
    key = t.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
    cur = js_getv(o, key)
    return cur if (op == "&&=" && !js_truthy(cur)) || (op == "||=" && js_truthy(cur)) || (op == "??=" && !js_nullish?(cur))
    v = wk_ev(e.b, act)
    js_setv(o, key, v, act.f.strict)
    return v
  if !t.has?(F_COMPUTED)
    key = t.b.str
    v = op == "=" ? wk_ev(e.b, act) : wk_assign_op(e, js_getp_ic(o, key, wk_ic(e)), wk_ev(e.b, act))
    js_setp_ic(o, key, v, wk_ic(t), act.f.strict)
    return v
  raw_key = wk_ev(t.b, act)
  if op == "="
    v = wk_ev(e.b, act)
    if js_array?(o) && (js_array_flags(o) & 15) == JS_AF_ARRAY && js_number?(raw_key)
      ii = jsr_i32(wvalue_bits(raw_key) ## i64)
      if ii >= 0 && ii < o.size && ii.to_f == raw_key
        o[ii] = v
        return v
    js_setv(o, raw_key, v, act.f.strict)
    return v
  js_throw_type("Cannot read properties of " + js_to_display(o)) if js_nullish?(o)
  key = js_to_property_key(raw_key)
  v = wk_assign_op(e, js_getv(o, key), wk_ev(e.b, act))
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



# Record up to 4 (shape, fn) pairs on a method call node for JIT polymorphic inlining.
WK_POLY_COUNTS = {}
WK_POLY_JIT_CNTS = {}

-> wk_record_poly_site(e, sh, fn)
  p = e.x
  if p == nil
    e.x = [sh, fn]
    WK_POLY_COUNTS[e] = [1]
    jit_keep(fn)
    return nil
  return nil if !p.is_a?(Array)
  cnts = WK_POLY_COUNTS[e]
  i = 0
  while i < p.size
    if p[i] == sh
      if cnts != nil
        idx = i / 2
        cnts[idx] = cnts[idx] + 1 if idx < cnts.size
      return nil
    i += 2
  return nil if p.size >= 8
  p.push(sh)
  p.push(fn)
  if cnts != nil
    cnts.push(1)
  jit_keep(fn)
  nil

-> wk_sort_poly_prof(e, prof)
  return prof if prof == nil || prof.size < 4
  cnts = WK_POLY_COUNTS[e]
  jrec = WK_POLY_JIT_CNTS[e]
  return prof if cnts == nil && jrec == nil
  np = prof.size / 2
  eff = []
  i = 0
  while i < np
    c = (cnts != nil && i < cnts.size) ? cnts[i] : 0
    if jrec != nil
      shb = wvalue_bits(prof[i * 2]) ## i64
      jshs = jrec[0]
      jarr = jrec[1]
      ji = 0
      while ji < jshs.size
        if jshs[ji] == shb
          c = c + jarr[ji]
          break
        ji += 1
    eff.push(c)
    i += 1
  order = []
  i = 0
  while i < np
    order.push(i)
    i += 1
  # Insertion sort descending by combined Tier-0 + Tier-1 PGO hit count (np <= 4)
  i = 1
  while i < np
    k = order[i]
    kc = eff[k]
    j = i - 1
    while j >= 0 && eff[order[j]] < kc
      order[j + 1] = order[j]
      j -= 1
    order[j + 1] = k
    i += 1
  out = []
  i = 0
  while i < np
    oi = order[i]
    out.push(prof[oi * 2])
    out.push(prof[oi * 2 + 1])
    i += 1
  out

-> wk_call_expr(e, act)
  c = e.a
  tail = e.has?(F_TAIL)
  return wk_super_call(e, act) if c.kind == :super
  if c.kind == :chain && c.a.kind == :member
    m = c.a
    if m.a.kind == :super
      f = wk_super_get(m, act)
      return wk_call_args(f, wk_this_for(m.a, act), e.list, act, tail)
    o = wk_chain(m.a, act)
    if o == WK_SHORT || (m.has?(F_OPTIONAL) && js_nullish?(o))
      return wk_call_args(nil, nil, e.list, act, tail)
    if m.b.kind == :private_name
      f = js_priv_get(o, wk_read_ref(m.b.x, act))
    else
      f = m.has?(F_COMPUTED) ? js_getv(o, wk_ev(m.b, act)) : js_getp_ic(o, m.b.str, wk_ic(m))
    return wk_call_args(f, o, e.list, act, tail)
  if c.kind == :member
    if c.a.kind == :super
      return wk_call_args(wk_super_get(c, act), wk_this_for(c.a, act), e.list, act, tail)
    o = wk_ev(c.a, act)
    if c.b.kind == :private_name
      f = js_priv_get(o, wk_read_ref(c.b.x, act))
    else
      f = c.has?(F_COMPUTED) ? js_getv(o, wk_ev(c.b, act)) : js_getp_ic(o, c.b.str, wk_ic(c))
      if !c.has?(F_COMPUTED) && o.is_a?(JS:Base) && f.is_a?(JS:Function)
        wk_record_poly_site(e, o.shape, f)
    return wk_call_args(f, o, e.list, act, tail)
  if c.kind == :ident && (act.f.dynamic || c.x.binding.kind == :dyn_eval)
    dyn = wk_dyn_find(c.str, c.x, act)
    if dyn != nil
      if dyn[0] == :with
        f = wk_with_get(dyn[1], c.str, act.f.strict)
        if e.d.is_a?(JaScope) && f == js_realm().intrinsics["eval"]
          args = wk_args(e.list, act)
          return args.size == 0 ? nil : wk_direct_eval(args[0], act, e.d)
        return wk_call_args(f, dyn[1], e.list, act, tail)
      f = dyn[1][c.str]
      if e.d.is_a?(JaScope) && f == js_realm().intrinsics["eval"]
        args = wk_args(e.list, act)
        return args.size == 0 ? nil : wk_direct_eval(args[0], act, e.d)
      return wk_call_args(f, nil, e.list, act, tail)
    f = wk_read_ref_static(c.x, act)
    if e.d.is_a?(JaScope) && f == js_realm().intrinsics["eval"]
      args = wk_args(e.list, act)
      return args.size == 0 ? nil : wk_direct_eval(args[0], act, e.d)
    return wk_call_args(f, nil, e.list, act, tail)
  f = wk_ev(c, act)
  if e.d.is_a?(JaScope) && f == js_realm().intrinsics["eval"]
    # a direct eval (§19.2.1.1 PerformEval with direct = true)
    args = wk_args(e.list, act)
    return args.size == 0 ? nil : wk_direct_eval(args[0], act, e.d)
  wk_call_args(f, nil, e.list, act, tail)

# Direct eval: the code is analysed below the call's scope and runs as an arrow there,
# on the caller's environment and this; its completion value is the result.
-> wk_direct_eval(src, act, sc)
  return src if !js_string?(src)
  p = JsParser.new(src, false)
  p.ctx = p.ctx | C_STRICT if act.f.strict
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    p.release_simd_lex
    js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.msg + " (line " + p.error.line.to_s + ", column " + p.error.col.to_s + ")"))
  p.release_simd_lex
  an = JaAnalysis.new(prog, act.f.strict)
  an.src = src
  an.url = act.f.analysis.url
  an.eval_mode = true
  f = an.run_direct(sc)
  r0 = JS_REALM[0]
  r0.analyses.push(an) if !JS_GC_ON[0] && r0 != nil && r0.analyses != nil
  bad = nil
  an.funcs.each ->(g) bad = g.unsupported0 if bad == nil && g.unsupported0 != nil
  if bad != nil
    js_throw(js_make_error("SyntaxError", bad.slice(13, bad.size - 13))) if bad.starts_with?("SyntaxError: ")
    js_throw(js_make_error("SyntaxError", "tier 0 cannot run this yet: " + bad.to_s))
  # (a script's vars/annexB fns a sloppy eval declares become global properties;
  #  a function's sloppy eval vars/functions attach to the caller's variable scope EnvN.dyn!)
  if f.strict == false
    vs = sc
    while vs.parent != nil && vs.kind != :function && vs.kind != :body && vs.kind != :script
      vs = vs.parent
    tmp_an = JaAnalysis.new(nil, false)
    vn = tmp_an.var_names(prog.list, [], false, true)
    fn_names = []
    prog.list.each ->(st)
      fs2 = wk_unwrap_labeled_fn(st)
      fn_names.push(fs2.str) if fs2 != nil && !fn_names.include?(fs2.str)
    ab = tmp_an.annexb_names(prog.list, tmp_an.lexical_names(prog.list), [], true)
    if vs.kind == :script
      g = js_realm().global
      lm = js_lexical_map()
      # §19.2.1.3 EvalDeclarationInstantiation validation BEFORE defining any global bindings!
      fn_names.each ->(nm)
        js_throw_type("Cannot declare global function '" + nm + "'") if !wk_can_declare_global_fn?(g, nm)
      vn.each ->(nm)
        if !fn_names.include?(nm)
          js_throw_type("Cannot declare global var '" + nm + "'") if !wk_can_declare_global_var?(g, nm)
      vn.each ->(nm)
        js_gdeclare(js_gcell(nm), nil, false, ATTR_W + ATTR_E + ATTR_C) if !fn_names.include?(nm)
      ab.each ->(nm)
        if !vn.include?(nm) && !fn_names.include?(nm) && !lm.has_key?(nm) && wk_can_declare_global_var?(g, nm)
          js_gdeclare(js_gcell(nm), nil, false, ATTR_W + ATTR_E + ATTR_C)
    else
      has_de = f.eval_dyn_vars != nil && f.eval_dyn_vars.size > 0
      f.scope.order.each ->(b) has_de = true if b.kind == :dyn_eval
      if has_de
        h = act.f.analysis.env_hops(sc, vs)
        if h >= 0
          ve = wk_env_at(act, h)
          if ve.is_a?(JS:EnvN)
            ve.dyn = {} if ve.dyn == nil
            f.scope.order.each ->(b)
              if b.kind == :dyn_eval && !ve.dyn.has_key?(b.name)
                ve.dyn[b.name] = nil
            if f.eval_dyn_vars != nil
              f.eval_dyn_vars.each ->(nm)
                ve.dyn[nm] = nil if !ve.dyn.has_key?(nm)
  ea = WkAct.new(f, nil, act.env, act.this, f.nlocals)
  ea.caller = JS_CUR_ACT[0]
  JS_CUR_ACT[0] = ea
  begin
    wk_prologue(f, ea, 0, nil, nil, nil, nil, nil)
    wk_hoist_functions(prog.list, ea)
    wk_stmts(prog.list, ea)
  rescue ex
    JS_CUR_ACT[0] = ea.caller
    raise ex
  JS_CUR_ACT[0] = ea.caller
  ea.rv

-> wk_call_args(f, this, list, act, tail = false)
  n = list.size
  if wk_has_spread?(list)
    args = wk_args(list, act)
    return tail ? wk_tail_arr(f, this, args) : js_call_arr(f, this, args)
  if n <= 4
    a0 = n > 0 ? wk_ev(list[0], act) : nil
    a1 = n > 1 ? wk_ev(list[1], act) : nil
    a2 = n > 2 ? wk_ev(list[2], act) : nil
    a3 = n > 3 ? wk_ev(list[3], act) : nil
    return tail ? wk_tail_set(f, this, n, a0, a1, a2, a3, nil) : js_call(f, this, n, a0, a1, a2, a3, nil)
  args = wk_args(list, act)
  tail ? wk_tail_set(f, this, n, args[0], args[1], args[2], args[3], args) : js_call(f, this, n, args[0], args[1], args[2], args[3], args)

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
        jf = p.b.x
        f = js_method_closure(wk_code(jf), wk_env_for(jf, act), o)
        js_gc_reg(f) if JS_GC_ON[0]
        js_set_fn_name(f, key, kind)
        cur = o.get_own_property(key)
        g = kind == "get" ? f : (cur != nil && cur.accessor? ? cur.getter : nil)
        st = kind == "set" ? f : (cur != nil && cur.accessor? ? cur.setter : nil)
        o.define_accessor(key, g, st, ATTR_E + ATTR_C)
      elsif key == "__proto__" && !p.has?(F_COMPUTED) && !p.has?(F_SHORTHAND) && !p.has?(F_METHOD)
        v = wk_ev(p.b, act)
        o.set_prototype_of(v) if js_object?(v) || v == JS_NULL
      else
        if p.has?(F_METHOD) && p.b.kind == :function && p.b.x.is_a?(JaFunc)
          jf = p.b.x
          v = js_method_closure(wk_code(jf), wk_env_for(jf, act), o)
          js_gc_reg(v) if JS_GC_ON[0]
          js_set_fn_name(v, key, nil)
        else
          v = wk_ev(p.b, act)
          js_set_fn_name(v, key, nil) if wk_anonymous_fn?(p.b) && !(p.b.kind == :class && wk_class_has_static_name?(p.b))
        o.define(key, v, ATTR_DEFAULT)
    i += 1
  o

-> wk_class_has_static_name?(n)
  i = 0
  while i < n.list.size
    m = n.list[i]
    if m.has?(F_STATIC) && !m.has?(F_COMPUTED) && (m.kind == :method_def || m.kind == :field_def) && m.a != nil && m.a.kind != :private_name && (m.a.kind == :ident || m.a.kind == :string) && m.a.str == "name"
      return true
    i += 1
  false

-> wk_anonymous_fn?(n)
  (n.kind == :function || n.kind == :arrow || n.kind == :class) && n.str == nil



# Parse and analyse a script without running it (test262 parse-phase negatives): raises
# the SyntaxError a run would.
-> wk_check(src)
  p = JsParser.new(src, false)
  begin
    prog = p.parse_program()
  rescue e
    p.release_simd_lex
    js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.msg + " (line " + p.error.line.to_s + ", column " + p.error.col.to_s + ")"))
  p.release_simd_lex
  an = JaAnalysis.new(prog, false).run
  an.funcs.each ->(g)
    js_throw(js_make_error("SyntaxError", g.unsupported0.to_s)) if g.unsupported0 != nil
  nil


# ---- classes & Stage 3 decorators (§15.7.14 ClassDefinitionEvaluation) ----

-> wk_eval_decorators(list, act)
  return nil if !list.is_a?(Array) || list.size == 0
  out = []
  i = 0
  while i < list.size
    d = wk_ev(list[i], act)
    js_throw_type("Decorator is not a function") if !js_callable?(d)
    out.push(d)
    i += 1
  out

-> wk_make_dec_ctx(kind, name, is_static, is_priv, access, extra_inits, metadata, active)
  ctx = js_new_object(js_realm().object_proto)
  ctx.define("kind", kind, ATTR_DEFAULT)
  ctx.define("name", name, ATTR_DEFAULT)
  if kind != "class"
    ctx.define("static", is_static, ATTR_DEFAULT)
    ctx.define("private", is_priv, ATTR_DEFAULT)
    ctx.define("access", access, ATTR_DEFAULT) if access != nil
  add_fn = ->(this, args, nt)
    js_throw_type("addInitializer cannot be called after decorator execution") if !active[0]
    fn = args.size > 0 ? args[0] : nil
    js_throw_type("Initializer must be a function") if !js_callable?(fn)
    extra_inits.push(fn)
    nil
  ctx.define("addInitializer", js_native("addInitializer", 1, add_fn), ATTR_DEFAULT)
  ctx.define("metadata", metadata, ATTR_DEFAULT)
  ctx

-> wk_make_dec_access(kind, key, is_priv, get_fn, set_fn)
  acc = js_new_object(js_realm().object_proto)
  if is_priv
    pn = key
    has_fn = ->(this, args, nt)
      o = args.size > 0 ? args[0] : nil
      js_throw_type("Cannot check private field on non-object") if !js_object?(o)
      o.is_a?(JS:Base) && o.priv_has?(pn)
    acc.define("has", js_native("has", 1, has_fn), ATTR_DEFAULT)
    if kind == "method" || kind == "getter" || kind == "field" || kind == "accessor"
      g_fn = ->(this, args, nt)
        o = args.size > 0 ? args[0] : nil
        js_priv_get(o, pn)
      acc.define("get", js_native("get", 1, g_fn), ATTR_DEFAULT)
    if kind == "setter" || kind == "field" || kind == "accessor"
      s_fn = ->(this, args, nt)
        o = args.size > 0 ? args[0] : nil
        v = args.size > 1 ? args[1] : nil
        js_priv_set(o, pn, v)
        nil
      acc.define("set", js_native("set", 2, s_fn), ATTR_DEFAULT)
  else
    pk = key
    has_fn = ->(this, args, nt)
      o = args.size > 0 ? args[0] : nil
      js_throw_type("Cannot use 'in' operator on non-object") if !js_object?(o)
      jhas_property?(o, pk)
    acc.define("has", js_native("has", 1, has_fn), ATTR_DEFAULT)
    if kind != "setter"
      g_fn = ->(this, args, nt)
        o = args.size > 0 ? args[0] : nil
        js_getv(o, pk)
      acc.define("get", js_native("get", 1, g_fn), ATTR_DEFAULT)
    if kind == "setter" || kind == "field" || kind == "accessor"
      s_fn = ->(this, args, nt)
        o = args.size > 0 ? args[0] : nil
        v = args.size > 1 ? args[1] : nil
        js_setv(o, pk, v, true)
        nil
      acc.define("set", js_native("set", 2, s_fn), ATTR_DEFAULT)
  acc

-> wk_class(n, act)
  cs = n.x
  saved = act.env
  saved_strict = act.f.strict
  # Class decorators are evaluated BEFORE entering strict class scope (§15.7.14)
  class_decs = wk_eval_decorators(n.b, act)
  act.f.strict = true
  begin
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
    f.define("length", cjf.nparams.to_f, ATTR_C)
    f.define("name", cjf.name.to_s, ATTR_C)
    f.define("prototype", proto, 0)
    proto.define("constructor", f, ATTR_W + ATTR_C)
    metadata = js_new_object(nil)
    fields = []
    privs = []
    statics = []
    inst_extra_inits = []
    stat_extra_inits = []
    class_extra_inits = []
    i = 0
    while i < n.list.size
      m = n.list[i]
      st = m.has?(F_STATIC)
      if m.kind == :method_def && m.str != "constructor"
        edecs = wk_eval_decorators(m.c, act)
        target = st ? f : proto
        jf = m.b.x
        fo = js_method_closure(wk_code(jf), wk_env_for(jf, act), target)
        is_priv = m.a.kind == :private_name
        key = is_priv ? wk_read_ref(m.a.x, act) : (m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.a, act)) : wk_prop_key(m.a))
        if edecs != nil
          dkind = m.str == "get" ? "getter" : (m.str == "set" ? "setter" : "method")
          dname = is_priv ? key.to_s : key
          js_set_fn_name(fo, dname, m.str == "method" ? nil : m.str) if !is_priv
          acc = wk_make_dec_access(dkind, key, is_priv, fo, fo)
          einits = st ? stat_extra_inits : inst_extra_inits
          di = edecs.size - 1
          while di >= 0
            active = [true]
            ctx = wk_make_dec_ctx(dkind, dname, st, is_priv, acc, einits, metadata, active)
            nv = js_call(edecs[di], nil, 2, fo, ctx, nil, nil, nil)
            active[0] = false
            if nv != nil
              js_throw_type("Decorator must return a function or undefined") if !js_callable?(nv)
              fo = nv
            di -= 1
        if is_priv
          if st
            if m.str == "method"
              f.priv_add_method(key, fo)
            else
              f.priv_add_accessor(key, m.str == "get" ? fo : nil, m.str == "set" ? fo : nil)
          else
            privs.push([key, fo, m.str])
        else
          js_class_method(target, key, fo, m.str, m.has?(F_COMPUTED))
      elsif m.kind == :field_def && m.str == "accessor"
        edecs = wk_eval_decorators(m.c, act)
        target = st ? f : proto
        is_priv = m.a.kind == :private_name
        key = is_priv ? wk_read_ref(m.a.x, act) : (m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.a, act)) : wk_prop_key(m.a))
        dname = is_priv ? key.to_s : key
        storage_pn = JS:PrivateName.new(js_key_display(dname) + " (accessor storage)")
        get_fn = js_auto_accessor_get(storage_pn)
        set_fn = js_auto_accessor_set(storage_pn)
        js_set_fn_name(get_fn, dname, "get")
        js_set_fn_name(set_fn, dname, "set")
        init = m.x == nil ? nil : js_method_closure(wk_code(m.x), wk_env_for(m.x, act), target)
        nf = m.b != nil && wk_anonymous_fn?(m.b) && !(m.b.kind == :class && wk_class_has_static_name?(m.b))
        finits = nil
        if edecs != nil
          acc = wk_make_dec_access("accessor", key, is_priv, get_fn, set_fn)
          einits = st ? stat_extra_inits : inst_extra_inits
          di = edecs.size - 1
          while di >= 0
            val_obj = js_new_object(r.object_proto)
            val_obj.define("get", get_fn, ATTR_DEFAULT)
            val_obj.define("set", set_fn, ATTR_DEFAULT)
            active = [true]
            ctx = wk_make_dec_ctx("accessor", dname, st, is_priv, acc, einits, metadata, active)
            nv = js_call(edecs[di], nil, 2, val_obj, ctx, nil, nil, nil)
            active[0] = false
            if nv != nil
              js_throw_type("Accessor decorator must return an object or undefined") if !js_object?(nv)
              ng = jget(nv, "get")
              if ng != nil
                js_throw_type("Accessor decorator get must be a function") if !js_callable?(ng)
                get_fn = ng
              ns = jget(nv, "set")
              if ns != nil
                js_throw_type("Accessor decorator set must be a function") if !js_callable?(ns)
                set_fn = ns
              ni = jget(nv, "init")
              if ni != nil
                js_throw_type("Accessor decorator init must be a function") if !js_callable?(ni)
                finits = [] if finits == nil
                finits.push(ni)
            di -= 1
        if is_priv
          if st
            f.priv_add_accessor(key, get_fn, set_fn)
          else
            privs.push([key, get_fn, "get"])
            privs.push([key, set_fn, "set"])
        else
          js_class_method(target, key, get_fn, "get", m.has?(F_COMPUTED))
          js_class_method(target, key, set_fn, "set", m.has?(F_COMPUTED))
        if st
          statics.push([storage_pn, init, false, nf, dname, finits])
        else
          fields.push([storage_pn, init, nf, dname, finits])
      elsif m.kind == :field_def
        edecs = wk_eval_decorators(m.c, act)
        is_priv = m.a.kind == :private_name
        key = is_priv ? wk_read_ref(m.a.x, act) : (m.has?(F_COMPUTED) ? js_to_property_key(wk_ev(m.a, act)) : wk_prop_key(m.a))
        init = m.x == nil ? nil : js_method_closure(wk_code(m.x), wk_env_for(m.x, act), st ? f : proto)
        nf = m.b != nil && wk_anonymous_fn?(m.b) && !(m.b.kind == :class && wk_class_has_static_name?(m.b))
        finits = nil
        if edecs != nil
          dname = is_priv ? key.to_s : key
          acc = wk_make_dec_access("field", key, is_priv, nil, nil)
          einits = st ? stat_extra_inits : inst_extra_inits
          di = edecs.size - 1
          while di >= 0
            active = [true]
            ctx = wk_make_dec_ctx("field", dname, st, is_priv, acc, einits, metadata, active)
            nv = js_call(edecs[di], nil, 2, nil, ctx, nil, nil, nil)
            active[0] = false
            if nv != nil
              js_throw_type("Field decorator must return a function or undefined") if !js_callable?(nv)
              finits = [] if finits == nil
              finits.push(nv)
            di -= 1
        if st
          statics.push([key, init, false, nf, nil, finits])
        else
          fields.push([key, init, nf, nil, finits])
      elsif m.kind == :static_block
        statics.push([nil, js_method_closure(wk_code(m.x), wk_env_for(m.x, act), f), true, false, nil, nil])
      i += 1
    f.fields = fields if fields.size > 0
    f.privs = privs if privs.size > 0
    f.inits = inst_extra_inits if inst_extra_inits.size > 0
    if class_decs != nil
      di = class_decs.size - 1
      while di >= 0
        active = [true]
        ctx = wk_make_dec_ctx("class", n.str, false, false, nil, class_extra_inits, metadata, active)
        nv = js_call(class_decs[di], nil, 2, f, ctx, nil, nil, nil)
        active[0] = false
        if nv != nil
          js_throw_type("Class decorator must return a constructor or undefined") if !js_is_constructor?(nv)
          f = nv
        di -= 1
    if n.str != nil
      wk_write(cs.names[n.str], f, act)
    # static extra initializers from element decorators
    i = 0
    while i < stat_extra_inits.size
      js_call(stat_extra_inits[i], f, 0, nil, nil, nil, nil, nil)
      i += 1
    # static fields and blocks, in order, with this = the constructor
    i = 0
    while i < statics.size
      se = statics[i]
      if se[2]
        js_call(se[1], f, 0, nil, nil, nil, nil, nil)
      else
        v = se[1] == nil ? nil : js_call(se[1], f, 0, nil, nil, nil, nil, nil)
        if se[3]
          dk = se[4] != nil ? se[4] : se[0]
          js_set_fn_name(v, dk.is_a?(JS:PrivateName) ? dk.to_s : dk, nil)
        if se[5] != nil
          cbs = se[5]
          ci = 0
          while ci < cbs.size
            v = js_call(cbs[ci], f, 1, v, nil, nil, nil, nil)
            ci += 1
        if se[0].is_a?(JS:PrivateName)
          f.priv_add(se[0], v)
        else
          jdefine_own_or_throw(f, se[0], v)
      i += 1
    # class decorator extra initializers
    i = 0
    while i < class_extra_inits.size
      js_call(class_extra_inits[i], f, 0, nil, nil, nil, nil, nil)
      i += 1
  rescue ex
    act.f.strict = saved_strict
    act.env = saved
    raise ex
  act.f.strict = saved_strict
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
  if !f.arrow
    v = (!f.script && f.this_binding != nil && f.this_binding.slot >= 0) ? js_env_get(act.env_at_entry, f.this_binding.slot) : act.this
    js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor") if v == JS_TDZ
    return v
  g = f
  while g.arrow
    g = g.parent
  wk_read_binding_from(g.this_binding, e.x.scope, act)

# super.x and super[x]: from the home object's prototype, with this as the receiver.
-> wk_super_get_key(m, key, act)
  fo = wk_special(m.a, act, :fo)
  this = wk_this_for(m.a, act)
  home = fo.home
  p = jget_prototype_of(home)
  js_throw_type("Cannot read properties of null") if p == JS_NULL
  jget(p, key, js_enc_recv(this))

-> wk_super_get(m, act)
  this = wk_this_for(m.a, act)
  raw_key = m.has?(F_COMPUTED) ? wk_ev(m.b, act) : m.b.str
  fo = wk_special(m.a, act, :fo)
  home = fo.home
  p = jget_prototype_of(home)
  js_throw_type("Cannot read properties of null") if p == JS_NULL
  key = m.has?(F_COMPUTED) ? js_to_property_key(raw_key) : raw_key
  jget(p, key, js_enc_recv(this))

-> wk_super_set(m, key, v, act)
  fo = wk_special(m.a, act, :fo)
  this = wk_this_for(m.a, act)
  p = jget_prototype_of(fo.home)
  js_throw_type("Cannot set properties of null") if p == JS_NULL
  ok = jset(p, key, v, js_enc_recv(this))
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
    js_throw_reference("Super constructor may only be called once") if act.this != JS_TDZ
    act.this = obj
    return nil
  hops = act.f.analysis.env_hops(e.a.x.scope, b.scope)
  env = wk_env_at(act, hops)
  cur = js_env_get(env, b.slot)
  js_throw_reference("Super constructor may only be called once") if cur != JS_TDZ
  js_env_set(env, b.slot, obj)
  act.this = obj if !f.arrow
  nil



