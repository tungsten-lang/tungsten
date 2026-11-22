# blade/js/interp — tier 0: compile a JsNode AST into Tungsten closures once, then run them.
#
# Every expression becomes ->(env) value and every statement ->(env) completion (nil for
# normal completion, a JsCompletion for break/continue/return; throw is a Tungsten raise).
# Variables are resolved here, at compile time, to (frame hops, slot index), so running code
# never looks a local up by name. A block gets its own frame only when a closure inside it
# could capture its bindings; otherwise its bindings live in the enclosing frame.
#
# Tungsten notes for whoever edits this file: a `return` inside a stored lambda is a
# non-local return from the method that created it (an error once that method has
# returned), so compiled lambdas are expressions or delegate to helper methods; and
# lambdas capture variables by reference, so every lambda is made inside a method whose
# locals belong to it alone.

# Scratch node flags (above the parser's): closure containment cache.
F_CL_DONE = 1048576
F_CL_YES = 2097152

+ JsBinding
  rw :name, :kind, :frame, :index, :tdz, :global, :cell, :is_const
  -> new(@name, @kind, @frame, @index)
    @tdz = false
    @global = false
    @cell = nil
    @is_const = false

+ JsScope
  rw :kind, :parent, :names, :owner, :size, :frame, :fnc, :strict, :with_index, :lex, :funcs, :derived, :is_async, :is_gen, :cls_priv

  -> new(@kind, @parent, @owner)
    @names = {}
    @lex = []
    @funcs = []
    @with_index = -1
    @derived = false
    @is_async = false
    @is_gen = false
    @cls_priv = nil
    if @owner
      @frame = self
      @size = (@kind == :function || @kind == :arrow || @kind == :script || @kind == :eval || @kind == :module || @kind == :field) ? FS_FIRST : 1
    else
      @frame = @parent.frame
      @size = 0
    if @kind == :function || @kind == :arrow || @kind == :script || @kind == :eval || @kind == :module || @kind == :field
      @fnc = self
    else
      @fnc = @parent.fnc
    @strict = @parent == nil ? false : @parent.strict

  -> alloc
    f = @frame
    i = f.size
    f.size = i + 1
    i

  -> declare(name, kind)
    b = @names[name]
    if b != nil
      if b.kind == :self
        b = JsBinding.new(name, kind, @frame, alloc())
        @names[name] = b
      return b
    b = JsBinding.new(name, kind, @frame, alloc())
    b.tdz = kind == :let || kind == :const || kind == :class
    b.is_const = kind == :const
    @names[name] = b
    @lex.push(b.index) if b.tdz
    b

  # Is this scope a function boundary for `this` (arrows and eval code see through)?
  -> this_scope?
    @kind == :function || @kind == :script || @kind == :module || @kind == :field

  -> fun_scope?
    @kind == :function || @kind == :arrow || @kind == :field

# A resolved identifier.
+ JsRef
  rw :kind, :hops, :index, :binding, :name, :withs
  -> new(@kind)
    @hops = 0
    @index = 0
    @binding = nil
    @name = nil
    @withs = nil


+ JsCompiler
  rw :src, :completion_slot, :url, :builtin, :lazy, :unit

  -> new(@src)
    @url = ""
    @builtin = false
    @completion_slot = -1
    @fn_depth = 0
    @lazy = false
    @unit = nil
    @aot_map = nil
    @cur_block_node = nil

  # ---- scope helpers ----

  -> hops_between(from_frame, to_frame)
    f = from_frame
    h = 0
    while f != to_frame
      f = f.parent.frame
      h += 1
    h

  -> resolve(name, sc)
    s = sc
    withs = nil
    while s != nil
      if s.kind == :with
        withs = [] if withs == nil
        withs.push([hops_between(sc.frame, s.frame), s.with_index])
      b = s.names[name]
      if b != nil
        r = JsRef.new(b.global ? :global : (b.cell != nil ? :cell : :slot))
        r.binding = b
        r.name = name
        r.withs = withs
        if r.kind == :slot
          r.hops = hops_between(sc.frame, b.frame)
          r.index = b.index
        return r
      s = s.parent
    r = JsRef.new(:global)
    r.name = name
    r.withs = withs
    r

  # Nearest non-arrow function (or script) scope, and the hops to its frame.
  -> this_scope(sc)
    s = sc
    while s != nil && !s.this_scope?
      s = s.parent
    s

  -> fun_scope(sc)
    s = sc
    while s != nil && !s.fun_scope?
      s = s.parent
    s

  # ---- closure containment (decides which blocks need their own frame) ----

  -> has_closure?(n)
    return false if n == nil
    return (n.flags & F_CL_YES) != 0 if (n.flags & F_CL_DONE) != 0
    k = n.kind
    yes = false
    if k == :function || k == :arrow || k == :class || k == :function_decl || k == :class_decl
      yes = true
    elsif k == :call && n.a != nil && n.a.kind == :ident && n.a.str == "eval"
      yes = true
    else
      yes = any_closure?(n.a) || any_closure?(n.b) || any_closure?(n.c) || any_closure?(n.d) || any_closure?(n.list)
    n.flags = n.flags | F_CL_DONE | (yes ? F_CL_YES : 0)
    yes

  -> any_closure?(x)
    return false if x == nil
    return has_closure?(x) if x.is_a?(JsNode)
    if x.is_a?(Array)
      i = 0
      while i < x.size
        y = x[i]
        return true if y != nil && y.is_a?(JsNode) && has_closure?(y)
        i += 1
    false

  # ---- declarations ----

  -> bound_names(p, out)
    return out if p == nil
    k = p.kind
    if k == :ident
      out.push(p.str)
    elsif k == :array_pattern
      p.list.each ->(e)
        bound_names(e, out) if e != nil
    elsif k == :object_pattern
      p.list.each ->(e)
        if e.kind == :rest
          bound_names(e.a, out)
        else
          bound_names(e.b, out)
    elsif k == :assign_pattern || k == :rest
      bound_names(p.a, out)
    out

  # VarDeclaredNames of a statement list (not entering functions). Sloppy-mode
  # function declarations in nested blocks are var-scoped too (Annex B).
  -> var_names(stmts, out, strict, top)
    stmts.each ->(s)
      var_names_stmt(s, out, strict, top)
    out

  -> var_names_stmt(s, out, strict, top)
    return nil if s == nil
    k = s.kind
    if k == :var_decl
      if s.str == "var"
        s.list.each ->(d) bound_names(d.a, out)
    elsif k == :function_decl
      out.push(s.str) if !top && !strict && s.str != nil
    elsif k == :block
      var_names(s.list, out, strict, false)
    elsif k == :if
      var_names_stmt(s.b, out, strict, false)
      var_names_stmt(s.c, out, strict, false)
    elsif k == :for
      var_names_stmt(s.a, out, strict, false) if s.a != nil && s.a.kind == :var_decl
      var_names_stmt(s.d, out, strict, false)
    elsif k == :for_in || k == :for_of
      var_names_stmt(s.a, out, strict, false) if s.a.kind == :var_decl
      var_names_stmt(s.d, out, strict, false)
    elsif k == :while
      var_names_stmt(s.b, out, strict, false)
    elsif k == :do_while
      var_names_stmt(s.a, out, strict, false)
    elsif k == :try
      var_names_stmt(s.a, out, strict, false)
      var_names_stmt(s.c, out, strict, false)
      var_names_stmt(s.d, out, strict, false)
    elsif k == :switch
      s.list.each ->(c) var_names(c.list, out, strict, false)
    elsif k == :labeled
      var_names_stmt(s.a, out, strict, false)
    elsif k == :with
      var_names_stmt(s.b, out, strict, false)
    elsif k == :export_named && s.a != nil
      var_names_stmt(s.a, out, strict, top)
    nil

  # Lexical declarations directly in a statement list: [name, kind] pairs.
  -> lex_decls(stmts, strict)
    out = []
    stmts.each ->(s0)
      s = s0
      s = s.a if s.kind == :export_named && s.a != nil
      s = s.a if s.kind == :export_default && s.a != nil && (s.a.kind == :class_decl || s.a.kind == :function_decl)
      if s.kind == :var_decl && s.str != "var"
        s.list.each ->(d)
          bound_names(d.a, []).each ->(nm) out.push([nm, s.str == "const" ? :const : :let])
      elsif s.kind == :class_decl && s.str != nil
        out.push([s.str, :class])
    out

  # ---- early errors (static semantics) ----

  -> early_dup(nm)
    raise JsThrow.new(js_syntax_error("Identifier '" + nm + "' has already been declared"))

  # A statement list's LexicallyDeclaredNames must be unique and must not occur in its
  # VarDeclaredNames (or in extra, e.g. parameters). top: function/script body, where
  # function declarations are var-scoped; in a block they are lexical (sloppy duplicates
  # of functions are allowed, Annex B.3.2.4).
  -> early_check(stmts, strict, top, extra = nil)
    seen = {}
    fn_only = {}
    stmts.each ->(s0)
      s = s0
      s = s.a if s.kind == :export_named && s.a != nil
      s = s.a if s.kind == :export_default && s.a != nil && (s.a.kind == :class_decl || s.a.kind == :function_decl)
      names = []
      is_fn = false
      if s.kind == :var_decl && s.str != "var"
        s.list.each ->(d) bound_names(d.a, names)
      elsif s.kind == :class_decl && s.str != nil
        names.push(s.str)
      elsif s.kind == :function_decl && !top && s.str != nil
        names.push(s.str)
        is_fn = !strict && !s.has?(F_ASYNC) && !s.has?(F_GENERATOR)
      names.each ->(nm)
        if seen[nm]
          early_dup(nm) if !(is_fn && fn_only[nm])
        seen[nm] = true
        fn_only[nm] = is_fn && (fn_only[nm] == nil || fn_only[nm])
    return nil if seen.size == 0
    vars = var_names(stmts, [], true, top)
    if top
      stmts.each ->(s) vars.push(s.str) if s.kind == :function_decl && s.str != nil
    vars.each ->(nm) early_dup(nm) if seen[nm]
    extra.each(->(nm) early_dup(nm) if seen[nm]) if extra != nil
    nil

  # Block-level instantiation for a list (block, switch body, catch body): declares
  # let/const/class and (strict) functions in sc; returns the function decls to hoist.
  -> declare_block(stmts, sc)
    early_check(stmts, sc.strict, false)
    lex_decls(stmts, sc.strict).each ->(d)
      sc.declare(d[0], d[1])
    fns = []
    stmts.each ->(s)
      if s.kind == :function_decl
        # block-local in both modes; sloppy code also copies it to the var at the
        # declaration (Annex B.3.3, compile_annexb_fn)
        sc.declare(s.str, :let_fn)
        fns.push(s)
    fns

  # ---- entry points ----

  # A whole script: var/function at top level go on the global object.
  -> compile_script(prog)
    sc = JsScope.new(:script, nil, true)
    sc.strict = prog.has?(F_STRICT)
    r = JS_REALM[0]
    early_check(prog.list, sc.strict, true)
    vn = var_names(prog.list, [], sc.strict, true)
    ln0 = lex_decls(prog.list, sc.strict).map(->(d) d[0])
    vn = vn.select(->(nm) !ln0.include?(nm)) if ln0.size > 0
    vn.each ->(nm)
      b = JsBinding.new(nm, :var, sc, -1)
      b.global = true
      sc.names[nm] = b
    fns = []
    prog.list.each ->(s)
      if s.kind == :function_decl
        b = JsBinding.new(s.str, :var, sc, -1)
        b.global = true
        sc.names[s.str] = b
        fns.push(s)
    lex_decls(prog.list, sc.strict).each ->(d)
      b = JsBinding.new(d[0], d[1], sc, -1)
      b.cell = r.glex_cell(d[0], d[1] == :const)
      b.is_const = d[1] == :const
      b.tdz = true
      sc.names[d[0]] = b
    @completion_slot = sc.alloc()
    cslot = @completion_slot
    body = compile_list(prog.list, sc)
    hoist = fns.map(->(f) [f.str, compile_function(f, sc, f.str)])
    lexes = sc.names.values.select(->(b) b.cell != nil).map(->(b) b.cell)
    gvars = vn
    run = ->(this_v)
      js_script_run(sc, body, hoist, lexes, gvars, cslot, this_v)
    run

  # Direct eval: compiled against the caller's static scope; runs in a frame below env.
  -> compile_eval(prog, parent_sc, strict)
    sc = JsScope.new(:eval, parent_sc, true)
    sc.strict = strict || prog.has?(F_STRICT)
    global_vars = !sc.strict && parent_sc.fnc.kind == :script
    vn = var_names(prog.list, [], sc.strict, true)
    fns = []
    prog.list.each ->(s)
      fns.push(s) if s.kind == :function_decl
    vn.each ->(nm)
      if global_vars
        b = JsBinding.new(nm, :var, sc, -1)
        b.global = true
        sc.names[nm] = b
      elsif sc.strict || !eval_var_outer?(nm, parent_sc)
        sc.declare(nm, :var)
    fns.each ->(f)
      if global_vars
        b = JsBinding.new(f.str, :var, sc, -1)
        b.global = true
        sc.names[f.str] = b
      elsif sc.strict || !eval_var_outer?(f.str, parent_sc)
        sc.declare(f.str, :var)
    lex_decls(prog.list, sc.strict).each ->(d) sc.declare(d[0], d[1])
    @completion_slot = sc.alloc()
    cslot = @completion_slot
    body = compile_list(prog.list, sc)
    hoist = fns.map(->(f) [resolve(f.str, sc), compile_function(f, sc, f.str)])
    lex = sc.lex
    run = ->(env)
      js_eval_run(sc, body, hoist, lex, cslot, env)
    run

  # Sloppy direct eval: a var/function name the caller's function already declares binds to
  # that variable (EvalDeclarationInstantiation uses the caller's variable environment). A
  # lexical binding of the name in between is a SyntaxError. Names new to the caller stay
  # local to the eval (TODO: add them to the caller's environment dynamically).
  -> eval_var_outer?(nm, parent_sc)
    sc = parent_sc
    while sc != nil
      b = sc.names[nm]
      if b != nil
        return true if b.kind == :var || b.kind == :param || b.kind == :let_fn
        early_dup(nm) if b.kind == :let || b.kind == :const || b.kind == :class
        return false
      break if sc == sc.fnc
      sc = sc.parent
    false

  # ---- statements ----

  -> compile_list(stmts, sc)
    fs = []
    stmts.each ->(s)
      c = cs(s, sc, nil)
      fs.push(c) if c != nil
    n = fs.size
    if n == 0
      return ->(env) nil
    if n == 1
      return fs[0]
    if n == 2
      a = fs[0]
      b = fs[1]
      two = ->(env)
        r = a.call(env)
        r == nil ? b.call(env) : r
      return two
    ->(env) js_run_list(fs, env)

  # Compile one statement; labels is the label set of an enclosing labeled statement.
  # Completion values (eval / script result): if/loops/switch/try/with produce undefined
  # unless their body produces a value (UpdateEmpty(C, undefined)).
  -> cs(n, sc, labels)
    st = cs_raw(n, sc, labels)
    k = n.kind
    if @completion_slot >= 0 && @fn_depth == 0 && (k == :if || k == :while || k == :do_while || k == :for || k == :for_in || k == :for_of || k == :switch || k == :try || k == :with)
      h = hops_between(sc.frame, completion_frame(sc))
      slot = @completion_slot
      inner = js_nop_stmt(st)
      return ->(env) js_cpl_reset(env, h, slot, inner)
    st

  -> cs_raw(n, sc, labels)
    k = n.kind
    case k
    when :expr_stmt
      compile_expr_stmt(n, sc)
    when :var_decl
      compile_var_decl(n, sc)
    when :function_decl
      compile_annexb_fn(n, sc)
    when :class_decl
      compile_class_decl(n, sc)
    when :block
      @cur_block_node = n
      compile_block(n.list, sc)
    when :empty, :debugger
      nil
    when :if
      compile_if(n, sc)
    when :for
      compile_for(n, sc, labels)
    when :for_in
      compile_for_in(n, sc, labels)
    when :for_of
      compile_for_of(n, sc, labels)
    when :while
      compile_while(n, sc, labels)
    when :do_while
      compile_do_while(n, sc, labels)
    when :return
      compile_return(n, sc)
    when :break
      c = n.str == nil ? BREAK_PLAIN : JsCompletion.new(C_BREAK, n.str, nil)
      ->(env) c
    when :continue
      c = n.str == nil ? CONTINUE_PLAIN : JsCompletion.new(C_CONTINUE, n.str, nil)
      ->(env) c
    when :throw
      e = cx(n.a, sc)
      ->(env) js_throw_value(e.call(env))
    when :try
      compile_try(n, sc)
    when :switch
      compile_switch(n, sc, labels)
    when :labeled
      compile_labeled(n, sc, labels)
    when :with
      compile_with(n, sc)
    when :import_decl
      compile_import(n, sc)
    when :export_named
      compile_export_named(n, sc)
    when :export_default
      compile_export_default(n, sc)
    when :export_all
      nil
    else
      raise JsThrow.new(js_syntax_error("Unsupported statement " + k.to_s))

  -> compile_expr_stmt(n, sc)
    e = cx(n.a, sc)
    if @completion_slot >= 0 && @fn_depth == 0
      h = hops_between(sc.frame, completion_frame(sc))
      slot = @completion_slot
      cv = ->(env)
        js_up(env, h)[slot] = e.call(env)
        nil
      return cv
    st = ->(env)
      e.call(env)
      nil
    st

  -> completion_frame(sc)
    s = sc
    while s.kind != :script && s.kind != :eval && s.kind != :module
      s = s.parent
    s.frame

  -> compile_var_decl(n, sc)
    fs = []
    n.list.each ->(d)
      if d.b != nil
        nm = d.a.kind == :ident ? d.a.str : nil
        v = cx_named(d.b, sc, nm)
        t = compile_pattern(d.a, sc, :init)
        fs.push(js_bind_init(t, v))
      elsif n.str != "var"
        t = compile_pattern(d.a, sc, :init)
        fs.push(js_bind_undef(t))
    return nil if fs.size == 0
    return fs[0] if fs.size == 1
    ->(env) js_run_list(fs, env)

  -> js_bind_init(t, v)
    ->(env)
      t.call(env, v.call(env))
      nil

  -> js_bind_undef(t)
    ->(env)
      t.call(env, nil)
      nil

  # A block: its own scope; a frame only if a closure might capture its bindings.
  -> compile_block(stmts, sc)
    bnode = @cur_block_node
    @cur_block_node = nil
    needs_scope = false
    stmts.each ->(s)
      needs_scope = true if (s.kind == :var_decl && s.str != "var") || s.kind == :class_decl || s.kind == :function_decl
    return compile_list(stmts, sc) if !needs_scope
    owner = any_closure?(stmts)
    bs = JsScope.new(:block, sc, owner)
    @aot_map[bnode] = bs if @aot_map != nil && bnode != nil
    fns = declare_block(stmts, bs)
    body = compile_list(stmts, bs)
    enter = compile_hoist(fns, bs)
    lex = bs.lex
    if owner
      size_of = bs
      ob = ->(env)
        e = Array.new(size_of.size, nil)
        e[0] = env
        js_tdz_fill(e, lex)
        enter.call(e) if enter != nil
        body.call(e)
      return ob
    nb = ->(env)
      js_tdz_fill(env, lex)
      enter.call(env) if enter != nil
      body.call(env)
    nb

  # Function declarations to create at scope entry: ->(env) or nil.
  -> compile_hoist(fns, sc)
    return nil if fns.size == 0
    items = fns.map(->(f) [resolve(f.str, sc), compile_function(f, sc, f.str)])
    ->(env) js_hoist(items, env)

  # A Statement position (if/loop/with/label bodies) cannot hold a declaration; sloppy
  # if-bodies may hold a plain function declaration (Annex B.3.4).
  -> check_sub(s, sc, if_body)
    return nil if s == nil
    k = s.kind
    bad = false
    if k == :var_decl && s.str != "var"
      bad = true
    elsif k == :class_decl
      bad = true
    elsif k == :function_decl
      bad = !(if_body && !sc.strict && !s.has?(F_ASYNC) && !s.has?(F_GENERATOR))
    elsif k == :labeled
      b = s.a
      b = b.a while b != nil && b.kind == :labeled
      bad = b != nil && (b.kind == :function_decl || (b.kind == :var_decl && b.str != "var") || b.kind == :class_decl)
    raise JsThrow.new(js_syntax_error("Lexical declaration cannot appear in a single-statement context")) if bad
    nil

  # Annex B.3.3: evaluating a sloppy block-level function declaration copies the block
  # binding to the function's var of the same name, unless a lexical declaration of the
  # name in an enclosing block would make that var statement an error.
  -> compile_annexb_fn(n, sc)
    return nil if sc.strict || n.has?(F_ASYNC) || n.has?(F_GENERATOR) || sc == sc.fnc
    nm = n.str
    s2 = sc.parent
    while s2 != nil && s2 != sc.fnc
      b2 = s2.names[nm]
      return nil if b2 != nil && (b2.kind == :let || b2.kind == :const || b2.kind == :class)
      s2 = s2.parent
    vb = sc.fnc.names[nm]
    return nil if vb == nil || !(vb.kind == :var || vb.kind == :param)
    g = compile_ident_get(nm, sc)
    if vb.global || vb.index < 0
      return ->(env) js_annexb_global(nm, g.call(env))
    h = hops_between(sc.frame, vb.frame)
    i = vb.index
    ->(env) js_annexb_set(js_up(env, h), i, g.call(env))

  -> compile_if(n, sc)
    check_sub(n.b, sc, true)
    check_sub(n.c, sc, true)
    t = cx_bool(n.a, sc)
    # if (x) function f() {} behaves as if (x) { function f() {} } (Annex B.3.4)
    return compile_if_wrapped(n, sc, t) if (n.b != nil && n.b.kind == :function_decl) || (n.c != nil && n.c.kind == :function_decl)
    c = cs(n.b, sc, nil)
    c = js_nop_stmt(c)
    if n.c == nil
      return ->(env) t.call(env) ? c.call(env) : nil
    a = cs(n.c, sc, nil)
    a = js_nop_stmt(a)
    ->(env) t.call(env) ? c.call(env) : a.call(env)

  -> compile_if_wrapped(n, sc, t)
    c = js_nop_stmt(n.b.kind == :function_decl ? compile_block([n.b], sc) : cs(n.b, sc, nil))
    if n.c == nil
      return ->(env) t.call(env) ? c.call(env) : nil
    a = js_nop_stmt(n.c.kind == :function_decl ? compile_block([n.c], sc) : cs(n.c, sc, nil))
    ->(env) t.call(env) ? c.call(env) : a.call(env)

  -> compile_while(n, sc, labels)
    check_sub(n.b, sc, false)
    t = cx_bool(n.a, sc)
    b = cs(n.b, sc, nil)
    b = js_nop_stmt(b)
    ->(env) js_run_while(t, b, labels, env)

  -> compile_do_while(n, sc, labels)
    check_sub(n.a, sc, false)
    b = cs(n.a, sc, nil)
    b = js_nop_stmt(b)
    t = cx_bool(n.b, sc)
    ->(env) js_run_do_while(t, b, labels, env)

  # for (let/const …): bound names unique, not "let", not var-declared in the body.
  -> for_bound_check(bound, body)
    seen = {}
    bound.each ->(nm)
      raise JsThrow.new(js_syntax_error("let is disallowed as a lexically bound name")) if nm == "let"
      early_dup(nm) if seen[nm]
      seen[nm] = true
    vs = []
    var_names_stmt(body, vs, true, false)
    vs.each ->(nm) early_dup(nm) if seen[nm]
    nil

  -> compile_for(n, sc, labels)
    check_sub(n.d, sc, false)
    init = n.a
    lexical = init != nil && init.kind == :var_decl && init.str != "var"
    ls = sc
    owner = false
    if lexical
      owner = has_closure?(n)
      ls = JsScope.new(:block, sc, owner)
      @aot_map[n] = ls if @aot_map != nil
      bound = []
      init.list.each ->(d) bound_names(d.a, bound)
      for_bound_check(bound, n.d)
      bound.each ->(nm) ls.declare(nm, init.str == "const" ? :const : :let)
    ic = nil
    if init != nil
      if init.kind == :var_decl
        ic = compile_var_decl(init, ls)
      else
        e = cx(init, ls)
        ic0 = ->(env)
          e.call(env)
          nil
        ic = ic0
    t = n.b == nil ? nil : cx_bool(n.b, ls)
    u = n.c == nil ? nil : cx(n.c, ls)
    b = cs(n.d, ls, nil)
    b = js_nop_stmt(b)
    # only the loop's own let/const bindings start uninitialized (not the enclosing block's)
    lex = lexical ? ls.lex : []
    if owner
      size_of = ls
      per_iter = ->(env) js_run_for_owner(size_of, lex, ic, t, u, b, labels, env)
      return per_iter
    ->(env) js_run_for(lex, ic, t, u, b, labels, env)

  -> compile_for_in(n, sc, labels)
    check_sub(n.d, sc, false)
    ls, target, owner = for_head(n, sc)
    rhs = cx(n.b, sc)
    b = cs(n.d, ls, nil)
    b = js_nop_stmt(b)
    lex = ls == sc ? [] : ls.lex
    size_of = ls
    if n.a.kind == :var_decl && n.a.str == "var" && n.a.list[0].b != nil
      # Annex B.3.5: for (var x = init in obj) assigns init before the object is evaluated
      ivc = cx(n.a.list[0].b, sc)
      return ->(env) js_run_for_in_init(target, ivc, rhs, b, labels, owner, size_of, lex, env)
    ->(env) js_run_for_in(rhs.call(env), target, b, labels, owner, size_of, lex, env)

  -> compile_for_of(n, sc, labels)
    check_sub(n.d, sc, false)
    ls, target, owner = for_head(n, sc)
    rhs = cx(n.b, sc)
    b = cs(n.d, ls, nil)
    b = js_nop_stmt(b)
    lex = ls == sc ? [] : ls.lex
    size_of = ls
    if n.has?(F_AWAIT)
      gs = fun_scope(sc)
      h = hops_between(sc.frame, gs.frame)
      return ->(env) js_run_for_await(js_up(env, h)[FS_GEN], rhs.call(env), target, b, labels, owner, size_of, lex, env)
    ->(env) js_run_for_of(rhs.call(env), target, b, labels, owner, size_of, lex, env)

  # [loop scope, target setter ->(env, v), owner?] for for-in / for-of.
  -> for_head(n, sc)
    left = n.a
    if left.kind == :var_decl && left.str != "var"
      owner = has_closure?(n.d) || any_closure?(left.list)
      ls = JsScope.new(:block, sc, owner)
      fb = bound_names(left.list[0].a, [])
      for_bound_check(fb, n.d)
      fb.each ->(nm) ls.declare(nm, left.str == "const" ? :const : :let)
      return [ls, compile_pattern(left.list[0].a, ls, :init), owner]
    if left.kind == :var_decl
      d = left.list[0]
      t = compile_pattern(d.a, sc, :init)
      if d.b != nil
        # for (var x = init in o): Annex B initializer
        iv = cx(d.b, sc)
        return [sc, t, false]
      return [sc, t, false]
    [sc, compile_pattern(left, sc, :assign), false]

  -> compile_return(n, sc)
    if n.a == nil
      c = JsCompletion.new(C_RETURN, nil, nil)
      return ->(env) c
    e = cx(n.a, sc)
    fs = fun_scope(sc)
    if fs != nil && fs.is_async && fs.is_gen
      h = hops_between(sc.frame, fs.frame)
      return ->(env) JsCompletion.new(C_RETURN, nil, js_await(js_up(env, h)[FS_GEN], e.call(env)))
    ->(env) js_ret(e.call(env))

  -> compile_try(n, sc)
    block = compile_block(n.a.list, sc)
    handler = nil
    if n.c != nil
      param = n.b
      if param == nil
        hb = compile_block(n.c.list, sc)
        h0 = ->(env, v) hb.call(env)
        handler = h0
      else
        owner = has_closure?(n.c) || has_closure?(param)
        cs2 = JsScope.new(:catch, sc, owner)
        cp = bound_names(param, [])
        cseen = {}
        cp.each ->(nm)
          early_dup(nm) if cseen[nm]
          cseen[nm] = true
        if n.c != nil && n.c.kind == :block
          lex_decls(n.c.list, sc.strict).each ->(d) early_dup(d[0]) if cseen[d[0]]
          n.c.list.each ->(st) early_dup(st.str) if st.kind == :function_decl && cseen[st.str]
        cp.each ->(nm) cs2.declare(nm, :let_catch)
        bind = compile_pattern(param, cs2, :init)
        hb = compile_block(n.c.list, cs2)
        size_of = cs2
        # (TODO(tungsten): assigning a lambda literal straight to an existing local inside an
        # if body is dropped by the compiled engine, so each goes through a fresh local)
        if owner
          h1 = ->(env, v) js_catch_owner(size_of, bind, hb, env, v)
          handler = h1
        else
          h2 = ->(env, v) js_catch_inline(bind, hb, env, v)
          handler = h2
    if handler != nil && @completion_slot >= 0 && @fn_depth == 0
      # the catch clause's completion replaces the try's (UpdateEmpty(C, undefined))
      ch = hops_between(sc.frame, completion_frame(sc))
      cslot2 = @completion_slot
      hh = handler
      handler = ->(env, v) js_cpl_catch(env, ch, cslot2, hh, v)
    fin = n.d == nil ? nil : compile_block(n.d.list, sc)
    if fin != nil && @completion_slot >= 0 && @fn_depth == 0
      # a finally block that completes normally does not change the completion value
      fh = hops_between(sc.frame, completion_frame(sc))
      fslot = @completion_slot
      fin0 = js_nop_stmt(fin)
      fin = ->(env) js_cpl_keep(env, fh, fslot, fin0)
    if fin == nil
      return ->(env) js_run_try_catch(block, handler, env)
    if handler == nil
      return ->(env) js_run_try_finally(block, fin, env)
    ->(env) js_run_try_catch_finally(block, handler, fin, env)

  -> compile_switch(n, sc, labels)
    d = cx(n.a, sc)
    all = []
    n.list.each ->(c) c.list.each ->(s) all.push(s)
    raise JsThrow.new(js_syntax_error("More than one default clause in switch statement")) if n.list.select(->(c) c.a == nil).size > 1
    early_check(all, sc.strict, false)
    owner = any_closure?(all)
    needs = false
    all.each ->(s)
      needs = true if (s.kind == :var_decl && s.str != "var") || s.kind == :class_decl || s.kind == :function_decl
    ss = needs ? JsScope.new(:block, sc, owner) : sc
    owner = owner && needs
    fns = needs ? declare_block(all, ss) : []
    tests = n.list.map(->(c) c.a == nil ? nil : cx(c.a, ss))
    bodies = n.list.map(->(c) compile_list(c.list, ss))
    enter = compile_hoist(fns, ss)
    # only the switch's own scope starts in TDZ (ss is the enclosing scope when it declares nothing)
    lex = needs ? ss.lex : []
    size_of = ss
    ->(env) js_run_switch(d.call(env), tests, bodies, labels, owner, size_of, lex, enter, env)

  -> compile_labeled(n, sc, labels)
    ls = labels == nil ? [n.str] : labels + [n.str]
    body = n.a
    raise JsThrow.new(js_syntax_error("In strict mode code, functions can only be declared at top level or inside a block.")) if body.kind == :function_decl && (sc.strict || body.has?(F_ASYNC) || body.has?(F_GENERATOR))
    raise JsThrow.new(js_syntax_error("Lexical declaration cannot appear in a single-statement context")) if (body.kind == :var_decl && body.str != "var") || body.kind == :class_decl
    k = body.kind
    if k == :for || k == :for_in || k == :for_of || k == :while || k == :do_while || k == :labeled || k == :switch
      return cs(body, sc, ls)
    b = cs(body, sc, nil)
    return nil if b == nil
    # every label of a chain (outer: inner: { … }) is a target of this statement
    ->(env) js_run_labeled(b, ls, env)

  -> compile_with(n, sc)
    check_sub(n.b, sc, false)
    o = cx(n.a, sc)
    ws = JsScope.new(:with, sc, false)
    ws.with_index = sc.alloc()
    b = cs(n.b, ws, nil)
    b = js_nop_stmt(b)
    idx = ws.with_index
    ->(env) js_run_with(o.call(env), idx, b, env)

  -> compile_class_decl(n, sc)
    c = compile_class(n, sc, n.str)
    t = compile_ident_set(n.str, sc, :init)
    ->(env)
      t.call(env, c.call(env))
      nil

  # Modules are compiled by JsModule (module.w); these run inside a module scope.
  -> compile_import(n, sc)
    nil

  -> compile_export_named(n, sc)
    return nil if n.a == nil
    cs(n.a, sc, nil)

  -> compile_export_default(n, sc)
    a = n.a
    if a.kind == :function_decl
      return nil
    if a.kind == :class_decl
      return compile_class_decl(a, sc) if a.str != nil
      c = compile_class(a, sc, "default")
      t = compile_ident_set("*default*", sc, :init)
      return ->(env) t.call(env, c.call(env))
    e = cx_named(a, sc, "default")
    t = compile_ident_set("*default*", sc, :init)
    ->(env)
      t.call(env, e.call(env))
      nil

  # ---- expressions ----

  # An expression for a boolean context.
  -> cx_bool(n, sc)
    k = n.kind
    if k == :binary
      op = n.str
      if op == "<" || op == ">" || op == "<=" || op == ">=" || op == "===" || op == "!==" || op == "==" || op == "!=" || op == "instanceof" || op == "in"
        return cx(n, sc)
    if k == :unary && n.str == "!"
      return cx(n, sc)
    e = cx(n, sc)
    ->(env) js_truthy(e.call(env))

  # Compile with a name for anonymous functions and classes (NamedEvaluation).
  -> cx_named(n, sc, name)
    if name != nil
      k = n.kind
      if (k == :function || k == :arrow) && n.str == nil
        code = compile_function(n, sc, name)
        return ->(env) js_make_closure(code, env)
      if k == :class && n.str == nil
        return compile_class(n, sc, name)
    cx(n, sc)

  -> cx(n, sc)
    k = n.kind
    case k
    when :num
      v = n.a
      ->(env) v
    when :string
      v = n.str
      ->(env) v
    when :true
      ->(env) true
    when :false
      ->(env) false
    when :null
      ->(env) JS_NULL
    when :ident
      compile_ident_get(n.str, sc)
    when :this
      compile_this(sc)
    when :template
      compile_template(n, sc)
    when :tagged_template
      compile_tagged(n, sc)
    when :regex
      pat = n.str
      fl = n.a
      ->(env) js_regexp_create(pat, fl)
    when :bigint
      v = js_parse_bigint_literal(n.str)
      ->(env) v
    when :array
      compile_array(n, sc)
    when :object
      compile_object(n, sc)
    when :function
      code = compile_function(n, sc, n.str)
      ->(env) js_make_closure(code, env)
    when :arrow
      code = compile_function(n, sc, nil)
      ->(env) js_make_closure(code, env)
    when :class
      compile_class(n, sc, n.str)
    when :unary
      compile_unary(n, sc)
    when :update
      compile_update(n, sc)
    when :binary
      compile_binary(n, sc)
    when :logical
      compile_logical(n, sc)
    when :assign
      compile_assign(n, sc)
    when :cond
      t = cx_bool(n.a, sc)
      a = cx(n.b, sc)
      b = cx(n.c, sc)
      ->(env) t.call(env) ? a.call(env) : b.call(env)
    when :call
      compile_call(n, sc)
    when :new
      compile_new(n, sc)
    when :member
      compile_member(n, sc)
    when :chain
      e = cx(n.a, sc)
      ->(env) js_unshort(e.call(env))
    when :seq
      fs = n.list.map(->(x) cx(x, sc))
      ->(env) js_run_seq(fs, env)
    when :yield
      compile_yield(n, sc)
    when :await
      compile_await(n, sc)
    when :meta_property
      compile_meta(n, sc)
    when :import_call
      s = cx(n.a, sc)
      base = @src
      ->(env) js_dynamic_import(s.call(env))
    when :spread
      raise JsThrow.new(js_syntax_error("Unexpected spread"))
    else
      raise JsThrow.new(js_syntax_error("Unsupported expression " + k.to_s))

  # ---- identifiers ----

  -> compile_ident_get(name, sc)
    r = resolve(name, sc)
    g = ident_get_ref(r)
    return g if r.withs == nil
    wrap_with_get(r.withs, name, g)

  -> ident_get_ref(r)
    if r.kind == :slot
      b = r.binding
      i = r.index
      h = r.hops
      nm = r.name
      if b.tdz
        if h == 0
          return ->(env) js_tdz_check(env[i], nm)
        if h == 1
          return ->(env) js_tdz_check(env[0][i], nm)
        return ->(env) js_tdz_check(js_up(env, h)[i], nm)
      if h == 0
        return ->(env) env[i]
      if h == 1
        return ->(env) env[0][i]
      if h == 2
        return ->(env) env[0][0][i]
      return ->(env) js_up(env, h)[i]
    if r.kind == :cell
      c = r.binding.cell
      nm = r.name
      return ->(env) js_tdz_check(c.v, nm)
    nm = r.name
    if nm == "undefined"
      return ->(env) js_gget_undefined()
    ->(env) js_gget(nm)

  # withs[0] is the innermost with; it is consulted first.
  -> wrap_with_get(withs, name, g)
    w = withs[0]
    inner = withs.size > 1 ? wrap_with_get(withs.slice(1, withs.size - 1), name, g) : g
    h = w[0]
    i = w[1]
    ->(env) js_with_get(js_up(env, h)[i], name, inner, env)

  # A setter ->(env, v) for an identifier. mode :init initializes (declarations),
  # :assign is a plain assignment (TDZ and const checks).
  -> compile_ident_set(name, sc, mode)
    r = resolve(name, sc)
    s = ident_set_ref(r, mode, sc.strict)
    return s if r.withs == nil || mode == :init
    wrap_with_set(r.withs, name, s, sc.strict)

  -> ident_set_ref(r, mode, strict)
    nm = r.name
    if r.kind == :slot
      b = r.binding
      i = r.index
      h = r.hops
      if mode == :assign && b.is_const
        return ->(env, v) js_const_assign(js_up(env, h)[i], nm)
      if mode == :assign && b.kind == :self
        if strict
          return ->(env, v) js_const_error(nm)
        return ->(env, v) v
      if mode == :assign && b.tdz
        return ->(env, v) js_set_checked(js_up(env, h), i, v, nm)
      if h == 0
        return ->(env, v) env[i] = v
      if h == 1
        return ->(env, v) env[0][i] = v
      return ->(env, v) js_up(env, h)[i] = v
    if r.kind == :cell
      c = r.binding.cell
      if mode == :init
        return ->(env, v) c.v = v
      return ->(env, v) js_cell_assign(c, v)
    if mode == :init && r.binding != nil && r.binding.global
      return ->(env, v) js_global_define_var(nm, v)
    ->(env, v) js_gset(nm, v, strict)

  -> wrap_with_set(withs, name, s, strict)
    w = withs[0]
    inner = withs.size > 1 ? wrap_with_set(withs.slice(1, withs.size - 1), name, s, strict) : s
    h = w[0]
    i = w[1]
    ->(env, v) js_with_set(js_up(env, h)[i], name, inner, env, v, strict)

  -> compile_this(sc)
    ts = this_scope(sc)
    h = hops_between(sc.frame, ts.frame)
    if ts.derived
      return ->(env) js_this_check(js_up(env, h)[FS_THIS])
    if h == 0
      return ->(env) env[FS_THIS]
    if h == 1
      return ->(env) env[0][FS_THIS]
    ->(env) js_up(env, h)[FS_THIS]

  # ---- literals ----

  -> compile_template(n, sc)
    quasis = n.list.map(->(q) q.str)
    exprs = n.a.map(->(e) cx(e, sc))
    if exprs.size == 0
      s = quasis[0]
      return ->(env) s
    ->(env) js_run_template(quasis, exprs, env)

  -> compile_tagged(n, sc)
    t = n.b
    site = js_template_site(t)
    exprs = t.a.map(->(e) cx(e, sc))
    tag = n.a
    if tag.kind == :member && tag.a.kind != :super
      o = cx(tag.a, sc)
      kf = member_key(tag, sc)
      return ->(env) js_tagged_method(o.call(env), kf.call(env), site, exprs, env)
    f = cx(tag, sc)
    ->(env) js_tagged_call(f.call(env), nil, site, exprs, env)

  -> js_template_site(t)
    cooked = t.list.map(->(q) q.str)
    raw = t.list.map(->(q) q.a)
    [cooked, raw, nil]

  -> compile_array(n, sc)
    items = n.list
    has_spread = false
    items.each ->(x)
      has_spread = true if x != nil && x.kind == :spread
    if !has_spread
      fs = items.map(->(x) x == nil ? nil : cx(x, sc))
      return ->(env) js_array_lit(fs, env)
    parts = items.map(->(x) x == nil ? nil : (x.kind == :spread ? [cx(x.a, sc)] : cx(x, sc)))
    ->(env) js_array_lit_spread(parts, env)

  -> compile_object(n, sc)
    ops = []
    n.list.each ->(p)
      ops.push(compile_obj_member(p, sc))
    ->(env) js_object_lit(ops, env)

  # One object-literal member: ->(env, obj).
  -> compile_obj_member(p, sc)
    if p.kind == :spread
      e = cx(p.a, sc)
      return ->(env, o) js_copy_data_props(o, e.call(env), nil)
    kf = prop_key(p.a, p.has?(F_COMPUTED), sc)
    static_name = p.has?(F_COMPUTED) ? nil : js_static_key(p.a)
    kind = p.str
    if p.has?(F_METHOD)
      code = compile_function(p.b, sc, static_name, true)
      if kind == "get"
        return ->(env, o) js_def_getter(o, kf.call(env), code, env, o)
      if kind == "set"
        return ->(env, o) js_def_setter(o, kf.call(env), code, env, o)
      return ->(env, o) js_def_method(o, kf.call(env), code, env, o, true)
    if p.has?(F_SHORTHAND)
      v = cx(p.b.kind == :assign_pattern ? p.b.a : p.b, sc)
      key = p.a.str
      return ->(env, o) js_lit_put(o, key, v.call(env))
    if static_name == "__proto__" && !p.has?(F_COMPUTED)
      v = cx(p.b, sc)
      return ->(env, o) js_lit_proto(o, v.call(env))
    if static_name != nil
      v = cx_named(p.b, sc, static_name)
      return ->(env, o) js_lit_put(o, static_name, v.call(env))
    v = cx(p.b, sc)
    if js_anon_fn?(p.b)
      code = p.b.kind == :class ? nil : compile_function(p.b, sc, nil)
      if code != nil
        return ->(env, o) js_lit_put_named_fn(o, kf.call(env), code, env)
    ->(env, o) js_lit_put(o, kf.call(env), v.call(env))

  -> js_anon_fn?(n)
    (n.kind == :function || n.kind == :arrow) && n.str == nil

  # A property key: ->(env) key (String or JsSymbol).
  -> prop_key(k, computed, sc)
    if computed
      e = cx(k, sc)
      return ->(env) js_to_property_key(e.call(env))
    s = js_static_key(k)
    ->(env) s

  -> js_static_key(k)
    return k.str if k.kind == :ident || k.kind == :string
    return js_number_to_s(k.a) if k.kind == :num
    return js_parse_bigint_literal(k.str).v.to_s if k.kind == :bigint
    nil

  # ---- operators ----

  -> compile_unary(n, sc)
    op = n.str
    a = n.a
    if op == "typeof" && a.kind == :ident
      r = resolve(a.str, sc)
      if r.kind == :global && r.withs == nil
        nm = a.str
        return ->(env) js_gtypeof(nm)
      g = compile_ident_get(a.str, sc)
      return ->(env) js_typeof_v(g.call(env))
    if op == "delete"
      return compile_delete(a, sc)
    e = cx(a, sc)
    case op
    when "!"
      ->(env) !js_truthy(e.call(env))
    when "-"
      ->(env) js_neg(e.call(env))
    when "+"
      ->(env) js_to_number(e.call(env))
    when "~"
      ->(env) js_bitnot(e.call(env))
    when "typeof"
      ->(env) js_typeof_v(e.call(env))
    when "void"
      ->(env) js_void(e.call(env))
    else
      raise JsThrow.new(js_syntax_error("bad unary " + op))

  -> compile_delete(a, sc)
    strict = sc.strict
    if a.kind == :chain
      inner = a.a
      if inner.kind == :member
        o = cx(inner.a, sc)
        kf = member_key(inner, sc)
        opt = inner.has?(F_OPTIONAL)
        return ->(env) js_delete_opt(o.call(env), kf, env, strict)
    if a.kind == :member
      if a.a.kind == :super
        return ->(env) js_throw_ref("Unsupported reference to 'super'")
      o = cx(a.a, sc)
      kf = member_key(a, sc)
      return ->(env) js_delete(o.call(env), kf.call(env), strict)
    if a.kind == :ident
      r = resolve(a.str, sc)
      if r.kind == :global
        nm = a.str
        return ->(env) js_delete_global(nm)
      return ->(env) false
    e = cx(a, sc)
    ->(env) js_eval_true(e.call(env))

  # The key of a :member node: ->(env) key.
  -> member_key(m, sc)
    if m.has?(F_COMPUTED)
      e = cx(m.b, sc)
      return ->(env) js_to_property_key(e.call(env))
    s = m.b.str
    ->(env) s

  -> compile_binary(n, sc)
    op = n.str
    if op == "in" && n.a.kind == :private_name
      pr = private_ref(n.a.str, sc)
      o = cx(n.b, sc)
      return ->(env) js_priv_in(pr.call(env), o.call(env))
    a = cx(n.a, sc)
    b = cx(n.b, sc)
    case op
    when "+"
      ->(env) js_add(a.call(env), b.call(env))
    when "-"
      ->(env) js_sub2(a.call(env), b.call(env))
    when "*"
      ->(env) js_mul2(a.call(env), b.call(env))
    when "/"
      ->(env) js_div2(a.call(env), b.call(env))
    when "%"
      ->(env) js_arith(:mod, a.call(env), b.call(env))
    when "**"
      ->(env) js_arith(:pow, a.call(env), b.call(env))
    when "<<"
      ->(env) js_arith(:shl, a.call(env), b.call(env))
    when ">>"
      ->(env) js_arith(:sar, a.call(env), b.call(env))
    when ">>>"
      ->(env) js_arith(:shr, a.call(env), b.call(env))
    when "&"
      ->(env) js_band2(a.call(env), b.call(env))
    when "|"
      ->(env) js_bor2(a.call(env), b.call(env))
    when "^"
      ->(env) js_arith(:bxor, a.call(env), b.call(env))
    when "<"
      ->(env) js_lt(a.call(env), b.call(env))
    when ">"
      ->(env) js_gt(a.call(env), b.call(env))
    when "<="
      ->(env) js_le(a.call(env), b.call(env))
    when ">="
      ->(env) js_ge(a.call(env), b.call(env))
    when "==="
      ->(env) js_strict_eq(a.call(env), b.call(env))
    when "!=="
      ->(env) !js_strict_eq(a.call(env), b.call(env))
    when "=="
      ->(env) js_loose_eq(a.call(env), b.call(env))
    when "!="
      ->(env) !js_loose_eq(a.call(env), b.call(env))
    when "instanceof"
      ->(env) js_instanceof(a.call(env), b.call(env))
    when "in"
      ->(env) js_in(a.call(env), b.call(env))
    else
      raise JsThrow.new(js_syntax_error("bad operator " + op))

  -> compile_logical(n, sc)
    a = cx(n.a, sc)
    b = cx(n.b, sc)
    op = n.str
    if op == "&&"
      return ->(env) js_and(a.call(env), b, env)
    if op == "||"
      return ->(env) js_or(a.call(env), b, env)
    ->(env) js_nullish_or(a.call(env), b, env)

  # ---- assignment ----

  -> compile_assign(n, sc)
    op = n.str
    t = n.a
    strict = sc.strict
    if op == "="
      if t.kind == :ident
        v = cx_named(n.b, sc, t.str)
        s = compile_ident_set(t.str, sc, :assign)
        return ->(env) js_assign_ret(s, env, v.call(env))
      if t.kind == :member
        return compile_member_assign(t, cx(n.b, sc), sc)
      p = compile_pattern(t, sc, :assign)
      v = cx(n.b, sc)
      return ->(env) js_assign_ret(p, env, v.call(env))
    # logical assignment
    if op == "&&=" || op == "||=" || op == "??="
      return compile_logical_assign(n, sc)
    bop = op.slice(0, op.size - 1)
    v = cx(n.b, sc)
    if t.kind == :ident
      g = compile_ident_get(t.str, sc)
      s = compile_ident_set(t.str, sc, :assign)
      f = binop_fn(bop)
      return ->(env) js_assign_ret(s, env, f.call(g.call(env), v.call(env)))
    if t.kind == :member
      f = binop_fn(bop)
      if t.a.kind == :super
        kf = member_key(t, sc)
        sr = super_base(sc)
        th = compile_this(sc)
        return ->(env) js_super_compound(sr.call(env), th.call(env), kf.call(env), f, v, env, strict)
      o = cx(t.a, sc)
      if t.b.kind == :private_name
        pr = private_ref(t.b.str, sc)
        return ->(env) js_priv_compound(o.call(env), pr.call(env), f, v, env)
      if t.has?(F_COMPUTED)
        ke = cx(t.b, sc)
        return ->(env) js_compound_idx(o.call(env), ke.call(env), f, v, env, strict)
      key = t.b.str
      return ->(env) js_compound_member(o.call(env), key, f, v, env, strict)
    raise JsThrow.new(js_syntax_error("Invalid left-hand side in assignment"))

  -> binop_fn(op)
    case op
    when "+"
      ->(a, b) js_add(a, b)
    when "-"
      ->(a, b) js_sub2(a, b)
    when "*"
      ->(a, b) js_mul2(a, b)
    when "/"
      ->(a, b) js_div2(a, b)
    when "%"
      ->(a, b) js_arith(:mod, a, b)
    when "**"
      ->(a, b) js_arith(:pow, a, b)
    when "<<"
      ->(a, b) js_arith(:shl, a, b)
    when ">>"
      ->(a, b) js_arith(:sar, a, b)
    when ">>>"
      ->(a, b) js_arith(:shr, a, b)
    when "&"
      ->(a, b) js_band2(a, b)
    when "|"
      ->(a, b) js_bor2(a, b)
    when "^"
      ->(a, b) js_arith(:bxor, a, b)
    else
      raise JsThrow.new(js_syntax_error("bad compound operator " + op))

  -> compile_logical_assign(n, sc)
    op = n.str
    t = n.a
    strict = sc.strict
    kind = op == "&&=" ? 1 : (op == "||=" ? 2 : 3)
    if t.kind == :ident
      g = compile_ident_get(t.str, sc)
      s = compile_ident_set(t.str, sc, :assign)
      v = cx_named(n.b, sc, t.str)
      return ->(env) js_logical_assign_var(kind, g, s, v, env)
    if t.kind == :member && t.a.kind != :super && t.b.kind == :private_name
      # this.#x ||= v reads and writes the private element, not a public property
      o = cx(t.a, sc)
      pr = private_ref(t.b.str, sc)
      v = cx(n.b, sc)
      return ->(env) js_logical_assign_priv(kind, o.call(env), pr.call(env), v, env)
    if t.kind == :member && t.a.kind != :super
      o = cx(t.a, sc)
      kf = member_key(t, sc)
      v = cx(n.b, sc)
      return ->(env) js_logical_assign_member(kind, o.call(env), kf.call(env), v, env, strict)
    if t.kind == :member && t.a.kind == :super
      sr = super_base(sc)
      th = compile_this(sc)
      kf = member_key(t, sc)
      v = cx(n.b, sc)
      return ->(env) js_logical_assign_super(kind, sr.call(env), th.call(env), kf.call(env), v, env, strict)
    raise JsThrow.new(js_syntax_error("Invalid left-hand side in assignment"))

  -> compile_member_assign(t, v, sc)
    strict = sc.strict
    if t.a.kind == :super
      kf = member_key(t, sc)
      sr = super_base(sc)
      th = compile_this(sc)
      return ->(env) js_super_set(sr.call(env), kf.call(env), v.call(env), th.call(env), strict)
    o = cx(t.a, sc)
    if t.b.kind == :private_name
      pr = private_ref(t.b.str, sc)
      return ->(env) js_priv_set(o.call(env), pr.call(env), v.call(env))
    if t.has?(F_COMPUTED)
      ke = cx(t.b, sc)
      return ->(env) js_assign_idx(o.call(env), ke.call(env), v, env, strict)
    key = t.b.str
    ->(env) js_assign_member(o.call(env), key, v, env, strict)

  -> compile_update(n, sc)
    t = n.a
    prefix = n.has?(F_PREFIX)
    d = n.str == "++" ? ~1.0 : ~-1.0
    strict = sc.strict
    if t.kind == :ident
      r = resolve(t.str, sc)
      if r.kind == :slot && r.withs == nil && !r.binding.tdz && !r.binding.is_const && r.binding.kind != :self
        i = r.index
        h = r.hops
        if h == 0
          return ->(env) js_update_slot(env, i, d, prefix)
        return ->(env) js_update_slot(js_up(env, h), i, d, prefix)
      g = compile_ident_get(t.str, sc)
      s = compile_ident_set(t.str, sc, :assign)
      return ->(env) js_update_ref(g, s, d, prefix, env)
    if t.kind == :member
      if t.a.kind == :super
        kf = member_key(t, sc)
        sr = super_base(sc)
        th = compile_this(sc)
        return ->(env) js_super_update(sr.call(env), th.call(env), kf.call(env), d, prefix, strict)
      o = cx(t.a, sc)
      if t.b.kind == :private_name
        pr = private_ref(t.b.str, sc)
        return ->(env) js_priv_update(o.call(env), pr.call(env), d, prefix)
      kf = member_key(t, sc)
      return ->(env) js_update_member(o.call(env), kf.call(env), d, prefix, strict)
    raise JsThrow.new(js_syntax_error("Invalid left-hand side expression in postfix operation"))

  # ---- member access and calls ----

  -> compile_member(n, sc)
    if n.a.kind == :super
      kf = member_key(n, sc)
      sr = super_base(sc)
      th = compile_this(sc)
      return ->(env) js_super_get(sr.call(env), kf.call(env), th.call(env))
    o = cx(n.a, sc)
    opt = n.has?(F_OPTIONAL)
    if n.b.kind == :private_name
      pr = private_ref(n.b.str, sc)
      if opt
        return ->(env) js_opt_priv_get(o.call(env), pr.call(env))
      return ->(env) js_priv_get(o.call(env), pr.call(env))
    if n.has?(F_COMPUTED)
      ke = cx(n.b, sc)
      if opt
        return ->(env) js_opt_getidx(o.call(env), ke, env)
      return ->(env) js_getidx_s(o.call(env), ke.call(env))
    key = n.b.str
    if opt
      return ->(env) js_opt_getv(o.call(env), key)
    if key == "length"
      return ->(env) js_get_length(o.call(env))
    ->(env) js_getv_s(o.call(env), key)

  -> compile_args(list, sc)
    has_spread = false
    list.each ->(x) has_spread = true if x.kind == :spread
    if has_spread
      parts = list.map(->(x) x.kind == :spread ? [cx(x.a, sc)] : cx(x, sc))
      return ->(env) js_array_lit_spread_raw(parts, env)
    fs = list.map(->(x) cx(x, sc))
    n = fs.size
    if n == 0
      # one shared empty list (argument arrays are never mutated)
      return ->(env) JS_NO_ARGS
    if n == 1
      a0 = fs[0]
      return ->(env) [a0.call(env)]
    if n == 2
      a0 = fs[0]
      a1 = fs[1]
      return ->(env) [a0.call(env), a1.call(env)]
    if n == 3
      a0 = fs[0]
      a1 = fs[1]
      a2 = fs[2]
      return ->(env) [a0.call(env), a1.call(env), a2.call(env)]
    ->(env) js_eval_args(fs, env)

  -> compile_call(n, sc)
    callee = n.a
    args = compile_args(n.list, sc)
    opt = n.has?(F_OPTIONAL)
    if callee.kind == :super
      fs = this_scope(sc)
      h = hops_between(sc.frame, fs.frame)
      return ->(env) js_super_call_l(js_up(env, h), args, env)
    if callee.kind == :member && callee.a.kind != :super
      o = cx(callee.a, sc)
      oopt = callee.has?(F_OPTIONAL)
      if callee.b.kind == :private_name
        pr = private_ref(callee.b.str, sc)
        return ->(env) js_call_priv(o.call(env), pr.call(env), args, env)
      if callee.has?(F_COMPUTED)
        ke = cx(callee.b, sc)
        return ->(env) js_call_method_idx(o.call(env), ke, args, env, oopt, opt)
      key = callee.b.str
      if oopt || opt
        return ->(env) js_call_method_opt(o.call(env), key, args, env, oopt, opt)
      cp = n.pos
      # the callee is fetched before the arguments are evaluated (§13.3.6.1)
      return ->(env) js_call_dotted(o.call(env), key, args, env, cp)
    if callee.kind == :member
      # super.m(...)
      kf = member_key(callee, sc)
      sr = super_base(sc)
      th = compile_this(sc)
      # GetThisBinding, then the key, then the method, then the arguments (§13.3.7)
      return ->(env) js_super_method_call_l(sr.call(env), th.call(env), kf, args, env)
    if callee.kind == :ident && callee.str == "eval"
      r = resolve("eval", sc)
      if r.kind == :global
        strict = sc.strict
        f = compile_ident_get("eval", sc)
        csc = sc
        return ->(env) js_direct_eval(f.call(env), args.call(env), csc, env, strict)
    if callee.kind == :ident && !opt
      rw = resolve(callee.str, sc)
      if rw.withs != nil
        # f() inside with: the object that has f is the call's this (§9.1.1.2.6 WithBaseObject)
        ws = rw.withs.map(->(w) [w[0], w[1]])
        g0 = ident_get_ref(rw)
        nm0 = callee.str
        cp0 = n.pos
        return ->(env) js_with_call(env, ws, nm0, g0, args, cp0)
    f = cx(callee, sc)
    what = callee.kind == :ident ? callee.str : "expression"
    if opt
      return ->(env) js_call_opt(f.call(env), args, env)
    if callee.kind == :chain
      # (a?.b)() keeps a?.b's this
      return ->(env) js_call_named(f.call(env), nil, args.call(env), what)
    cp = n.pos
    ->(env) js_call_ident_site(f, args, env, cp, what)

  -> compile_new(n, sc)
    f = cx(n.a, sc)
    args = compile_args(n.list, sc)
    what = n.a.kind == :ident ? n.a.str : (n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.a.b.kind == :ident ? n.a.b.str : "expression")
    cp = n.pos
    ->(env)
      fv = f.call(env)
      av = args.call(env)
      JS_POS[JS_DEPTH[0]] = cp
      js_construct_named(fv, av, what)

  # ---- super ----

  # ->(env) the home object of the enclosing method.
  -> super_base(sc)
    ts = this_scope(sc)
    h = hops_between(sc.frame, ts.frame)
    ->(env) js_up(env, h)[FS_HOME]

  -> compile_meta(n, sc)
    if n.str == "new.target"
      ts = this_scope(sc)
      h = hops_between(sc.frame, ts.frame)
      return ->(env) js_up(env, h)[FS_NT]
    ->(env) js_import_meta()

  -> compile_yield(n, sc)
    gs = fun_scope(sc)
    h = hops_between(sc.frame, gs.frame)
    e = n.a == nil ? nil : cx(n.a, sc)
    if n.has?(F_DELEGATE)
      return ->(env) js_yield_star(js_up(env, h)[FS_GEN], e.call(env))
    if gs.is_async
      return ->(env) js_async_yield(js_up(env, h)[FS_GEN], e == nil ? nil : e.call(env))
    ->(env) js_yield(js_up(env, h)[FS_GEN], e == nil ? nil : e.call(env))

  -> compile_await(n, sc)
    gs = fun_scope(sc)
    e = cx(n.a, sc)
    if gs == nil
      # top-level await in a module: the module body runs as an async function
      ms = sc
      while ms.kind != :module && ms.parent != nil
        ms = ms.parent
      h = hops_between(sc.frame, ms.frame)
      return ->(env) js_await(js_up(env, h)[FS_GEN], e.call(env))
    h = hops_between(sc.frame, gs.frame)
    ->(env) js_await(js_up(env, h)[FS_GEN], e.call(env))

  # ---- private names ----

  # ->(env) the JsPrivateName for #name in the innermost class declaring it.
  -> private_ref(name, sc)
    r = resolve("#" + name, sc)
    raise JsThrow.new(js_syntax_error("Private field '#" + name + "' must be declared in an enclosing class")) if r.kind != :slot
    i = r.index
    h = r.hops
    ->(env) js_up(env, h)[i]

  # ---- patterns (destructuring) ----

  # A setter ->(env, v) for a binding or assignment pattern.
  -> compile_pattern(p, sc, mode)
    k = p.kind
    if k == :ident
      return compile_ident_set(p.str, sc, mode)
    if k == :member
      strict = sc.strict
      if p.a.kind == :super
        kf = member_key(p, sc)
        sr = super_base(sc)
        th = compile_this(sc)
        return ->(env, v) js_super_set(sr.call(env), kf.call(env), v, th.call(env), strict)
      o = cx(p.a, sc)
      if p.b.kind == :private_name
        pr = private_ref(p.b.str, sc)
        return ->(env, v) js_priv_set(o.call(env), pr.call(env), v)
      kf = member_key(p, sc)
      return ->(env, v) js_setv_k(o.call(env), kf.call(env), v, strict)
    if k == :assign_pattern
      nm = p.a.kind == :ident ? p.a.str : nil
      d = cx_named(p.b, sc, nm)
      t = compile_pattern(p.a, sc, mode)
      return ->(env, v) t.call(env, v == nil ? d.call(env) : v)
    if k == :array_pattern
      items = p.list.map(->(e) compile_array_item(e, sc, mode))
      return ->(env, v) js_destructure_array(env, v, items)
    if k == :object_pattern
      items = p.list.map(->(e) compile_object_item(e, sc, mode))
      return ->(env, v) js_destructure_object(env, v, items)
    if k == :chain || k == :call
      return ->(env, v) js_throw_ref("Invalid left-hand side in assignment")
    raise JsThrow.new(js_syntax_error("Invalid destructuring target " + k.to_s))

  # A member target (o.k, o[k], optionally with a default) as [prep, set_ref]: prep(env)
  # evaluates the reference before the value is read (§13.15.5.3-5); set_ref(env, ref, v)
  # stores into it. nil for other targets.
  -> compile_target_ref(p, sc)
    if p.kind == :assign_pattern && p.a.kind == :member
      inner = compile_target_ref(p.a, sc)
      return nil if inner == nil
      d = cx(p.b, sc)
      st = inner[1]
      return [inner[0], ->(env, ref, v) st.call(env, ref, v == nil ? d.call(env) : v)]
    return nil if p.kind != :member || p.a.kind == :super || p.b.kind == :private_name
    strict = sc.strict
    o = cx(p.a, sc)
    kf = member_key(p, sc)
    [->(env) [o.call(env), kf.call(env)], ->(env, ref, v) js_setv_k(ref[0], ref[1], v, strict)]

  # [kind, setter, prep, set_ref]: kind 0 element, 1 hole, 2 rest.
  -> compile_array_item(e, sc, mode)
    return [1, nil, nil, nil] if e == nil
    t = e.kind == :rest ? e.a : e
    ref = mode == :assign ? compile_target_ref(t, sc) : nil
    [e.kind == :rest ? 2 : 0, compile_pattern(t, sc, mode), ref == nil ? nil : ref[0], ref == nil ? nil : ref[1]]

  # [key fn or nil for rest, setter, static key, prep, set_ref]
  -> compile_object_item(e, sc, mode)
    t = e.kind == :rest ? e.a : e.b
    ref = mode == :assign ? compile_target_ref(t, sc) : nil
    prep = ref == nil ? nil : ref[0]
    sref = ref == nil ? nil : ref[1]
    if e.kind == :rest
      return [nil, compile_pattern(e.a, sc, mode), nil, prep, sref]
    kf = prop_key(e.a, e.has?(F_COMPUTED), sc)
    [kf, compile_pattern(e.b, sc, mode), nil, prep, sref]

  # ---- functions ----

  # Compile a function or arrow node into a JsCode (once; closures share it).
  -> compile_function(n, sc, name, is_method = false, derived = false)
    arrow = n.kind == :arrow
    async = n.has?(F_ASYNC)
    gen = n.has?(F_GENERATOR)
    code = JsCode.new(name == nil ? "" : name)
    code.src = @src
    code.url = @url
    code.builtin = @builtin
    code.pos = n.pos
    code.fin = n.fin
    code.method = is_method || n.has?(F_METHOD)
    if arrow
      code.kind = async ? :async_arrow : :arrow
    elsif async && gen
      code.kind = :async_gen
      code.lazy_kind = 3
    elsif gen
      code.kind = :generator
      code.lazy_kind = 2
    elsif async
      code.kind = :async
    elsif code.method
      code.kind = :method
    else
      code.kind = :normal
      code.lazy_kind = 1
    len = 0
    seen_default = false
    n.list.each ->(p)
      if p.kind == :assign_pattern || p.kind == :rest
        seen_default = true
      len += 1 if !seen_default
    code.length = len
    if @unit != nil
      # tier 1 (aot.w) translates this function again from its node and scope when hot
      code.unit = @unit
      code.aot_src = JsPending.new(n, sc, derived, @src, @url, @builtin)
      @aot_map[n] = code if @aot_map != nil
    if @lazy
      # Lazy compilation: the body becomes closures on the first call (js_code_ready).
      code.pending = JsPending.new(n, sc, derived, @src, @url, @builtin)
      JS_LAZY_STATS[0] += 1
      return code
    compile_function_body(code, n, sc, derived)
    code

  # The scope, binder and body closures of a function (eagerly, or on its first call).
  -> compile_function_body(code, n, sc, derived)
    arrow = n.kind == :arrow
    async = n.has?(F_ASYNC)
    gen = n.has?(F_GENERATOR)
    js_lazy_parse_body(n, @src) if n.b == nil && n.c != nil
    fsc = JsScope.new(arrow ? :arrow : :function, sc, true)
    if @unit != nil
      # tier 1 reuses these scopes (and the inner functions' codes) to keep frame layouts
      @aot_map = {} if @aot_map == nil
      @aot_map[n] = fsc
      code.aot_map = @aot_map
    fsc.strict = sc.strict || n.has?(F_STRICT)
    fsc.is_async = async
    fsc.is_gen = gen
    fsc.derived = derived
    code.strict = fsc.strict
    # a named function expression sees its own name
    if n.kind == :function && n.str != nil
      b = JsBinding.new(n.str, :self, fsc, FS_FUNC)
      fsc.names[n.str] = b
    params = n.list
    simple = true
    params.each ->(p)
      if p.kind != :ident
        simple = false
    pnames = []
    params.each ->(p) bound_names(p, pnames)
    pnames.each ->(nm) fsc.declare(nm, :param)
    if !arrow && (n.has?(F_USES_ARGS) || n.has?(F_HAS_EVAL)) && !pnames.include?("arguments")
      ab = fsc.declare("arguments", :var)
      code.args_slot = ab.index
    body = n.b
    @fn_depth += 1
    if arrow && n.has?(F_EXPR_BODY)
      code.binder = compile_binder(params, simple, fsc, code)
      e = cx(body, fsc)
      code.body = e
      code.expr_body = true
      if async
        code.expr_body = false
        code.body = ->(env) JsCompletion.new(C_RETURN, nil, e.call(env))
    else
      early_check(body, fsc.strict, true, pnames)
      vn = var_names(body, [], fsc.strict, true)
      # Annex B names that a top-level let/const/class already declares are not vars
      ln = lex_decls(body, fsc.strict).map(->(d) d[0])
      vn = vn.select(->(nm) !ln.include?(nm)) if ln.size > 0
      # With a non-simple parameter list the body's declarations get their own scope (same
      # frame, distinct slots); a var named like a parameter starts with its value
      # (FunctionDeclarationInstantiation step 28).
      bsc = simple ? fsc : JsScope.new(:block, fsc, false)
      copies = []
      vn.each ->(nm)
        if !simple && pnames.include?(nm)
          copies.push([fsc.names[nm].index, bsc.declare(nm, :var).index])
        else
          bsc.declare(nm, :var)
      fns = []
      body.each ->(s)
        if s.kind == :function_decl
          bsc.declare(s.str, :var)
          fns.push(s)
      lex_decls(body, fsc.strict).each ->(d) bsc.declare(d[0], d[1])
      code.binder = compile_binder(params, simple, fsc, code)
      hoist = compile_hoist(fns, bsc)
      if copies.size > 0
        h0 = hoist
        hoist = ->(env) js_param_var_copy(env, copies, h0)
      stmts = compile_list(body, bsc)
      lex = simple ? fsc.lex : fsc.lex + bsc.lex
      code.aot_lex = lex
      code.aot_hoist = hoist
      if hoist == nil && lex.size == 0
        code.body = stmts
      else
        code.body = ->(env) js_fn_prologue(env, lex, hoist, stmts)
    @fn_depth -= 1
    code.nslots = fsc.size
    # the frame can be released when the call returns if nothing can capture it
    code.frame_free = !async && !gen && !derived && !n.has?(F_HAS_EVAL) && (code.args_slot < 0 || code.strict) && !any_closure?(params) && !any_closure?(n.b)
    code

  # The parameter binder ->(env, args).
  -> compile_binder(params, simple, fsc, code)
    aslot = code.args_slot
    strict = code.strict
    if simple
      idx = params.map(->(p) fsc.names[p.str].index)
      n = idx.size
      if aslot >= 0
        return ->(env, args) js_bind_simple_args(env, args, idx, aslot, strict)
      if n == 0
        return ->(env, args) nil
      if n == 1
        i0 = idx[0]
        return ->(env, args) env[i0] = args.size > 0 ? args[0] : nil
      if n == 2
        i0 = idx[0]
        i1 = idx[1]
        return ->(env, args) js_bind2(env, args, i0, i1)
      return ->(env, args) js_bind_simple(env, args, idx)
    items = params.map(->(p) p.kind == :rest ? [2, compile_pattern(p.a, fsc, :init)] : [0, compile_pattern(p, fsc, :init)])
    ->(env, args) js_bind_params(env, args, items, aslot, strict)

  # ---- classes ----

  -> compile_class(n, sc, name)
    csc = JsScope.new(:class, sc, true)
    csc.strict = true
    if n.str != nil
      csc.declare(n.str, :const)
    # private names
    privs = []
    n.list.each ->(m)
      if (m.kind == :method_def || m.kind == :field_def) && m.a != nil && m.a.kind == :private_name
        pn = "#" + m.a.str
        if csc.names[pn] == nil
          b = csc.declare(pn, :priv)
          privs.push([m.a.str, b.index, m.kind == :method_def])
    sup = n.a == nil ? nil : cx(n.a, csc)
    derived = n.a != nil
    ctor_node = nil
    n.list.each ->(m)
      ctor_node = m if m.kind == :method_def && m.str == "constructor"
    ccode = nil
    if ctor_node != nil
      ccode = compile_ctor(ctor_node.b, csc, name, derived)
    else
      ccode = JsCode.new(name == nil ? "" : name)
      ccode.url = @url
      ccode.builtin = @builtin
      ccode.kind = derived ? :default_derived : :default_base
      ccode.strict = true
      ccode.src = @src
      ccode.pos = n.pos
      ccode.fin = n.fin
    ccode.is_class = true
    ccode.src = @src
    ccode.pos = n.pos
    ccode.fin = n.fin
    # members: [kind, static, key fn, payload, private name slot or -1]
    members = []
    fsc = JsScope.new(:field, csc, true)
    fsc.strict = true
    @fn_depth += 1
    n.list.each ->(m)
      if m.kind == :method_def && m.str != "constructor"
        members.push(compile_class_method(m, csc))
      elsif m.kind == :field_def
        members.push(compile_class_field(m, csc, fsc))
      elsif m.kind == :static_block
        members.push(compile_static_block(m, csc))
    @fn_depth -= 1
    self_slot = n.str == nil ? -1 : csc.names[n.str].index
    size_of = csc
    fsize = fsc
    cname = name
    ->(env) js_class_create(env, size_of, fsize, privs, sup, derived, ccode, members, self_slot, cname)

  -> compile_ctor(fnode, csc, name, derived)
    code = compile_function(fnode, csc, name, true, derived)
    code.kind = :normal
    code.lazy_kind = 0
    code

  # Mark compiled this-checks for derived constructors: done by scope flag before compile.
  -> compile_class_method(m, csc)
    static = m.has?(F_STATIC)
    priv_slot = -1
    kf = nil
    nm = nil
    if m.a.kind == :private_name
      priv_slot = csc.names["#" + m.a.str].index
      nm = "#" + m.a.str
    else
      kf = prop_key(m.a, m.has?(F_COMPUTED), csc)
      nm = m.has?(F_COMPUTED) ? nil : js_static_key(m.a)
    code = compile_function(m.b, csc, nm, true)
    kind = m.str == "get" ? :getter : (m.str == "set" ? :setter : :method)
    [kind, static, kf, code, priv_slot]

  -> compile_class_field(m, csc, fsc)
    static = m.has?(F_STATIC)
    priv_slot = -1
    kf = nil
    nm = nil
    if m.a.kind == :private_name
      priv_slot = csc.names["#" + m.a.str].index
      nm = "#" + m.a.str
    else
      kf = prop_key(m.a, m.has?(F_COMPUTED), csc)
      nm = m.has?(F_COMPUTED) ? nil : js_static_key(m.a)
    init = m.b == nil ? nil : cx_named(m.b, fsc, nm)
    [:field, static, kf, init, priv_slot]

  -> compile_static_block(m, csc)
    bs = JsScope.new(:field, csc, true)
    bs.strict = true
    vn = var_names(m.list, [], true, true)
    vn.each ->(nm) bs.declare(nm, :var)
    fns = []
    m.list.each ->(s)
      if s.kind == :function_decl
        bs.declare(s.str, :var)
        fns.push(s)
    lex_decls(m.list, true).each ->(d) bs.declare(d[0], d[1])
    hoist = compile_hoist(fns, bs)
    body = compile_list(m.list, bs)
    lex = bs.lex
    size_of = bs
    run = ->(env, f) js_static_block_run(env, size_of, lex, hoist, body, f)
    [:block, true, nil, run, -1]


# ---- lazy compilation ----
#
# A function's body is compiled to closures on its first call: what compile_function
# needs from its static context (the scope chain, which stays alive through JsScope
# parents) is kept in a JsPending. Most functions on a heavy page are never called.

JS_LAZY_STATS = [0, 0, 0, 0]
# Seconds spent compiling bodies on first call (parse included) and parsing them.
JS_LAZY_T = [~0.0, ~0.0]
JS_LAZY_DEBUG = [Env.get("BLADE_JS_LAZY_DEBUG", "") == "1"]
# Scripts at least this long compile lazily (BLADE_JS_LAZY=0 turns it off, =all forces it).
JS_LAZY_MIN = [Env.get("BLADE_JS_LAZY", "") == "0" ? 1000000000000 : (Env.get("BLADE_JS_LAZY", "") == "all" ? 0 : 4096)]

+ JsPending
  rw :node, :sc, :derived, :src, :url, :builtin
  -> new(@node, @sc, @derived, @src, @url, @builtin)

-> js_code_ready(code)
  p = code.pending
  return code if p == nil
  code.pending = nil
  comp = JsCompiler.new(p.src)
  comp.url = p.url
  comp.builtin = p.builtin
  comp.lazy = true
  comp.unit = code.unit
  t0 = clock()
  begin
    comp.compile_function_body(code, p.node, p.sc, p.derived)
  rescue e
    code.pending = p
    raise e
  JS_LAZY_STATS[1] += 1
  JS_LAZY_T[0] = JS_LAZY_T[0] + (clock() - t0)
  js_aot_from_cache(code) if code.unit != nil
  code

# ---- run-time helpers for the compiled closures ----

-> js_run_list(fs, env)
  i = 0
  n = fs.size
  while i < n
    r = fs[i].call(env)
    return r if r != nil
    i += 1
  nil

-> js_run_seq(fs, env)
  v = nil
  i = 0
  while i < fs.size
    v = fs[i].call(env)
    i += 1
  v

-> js_truthy(v)
  return v if v == true || v == false
  js_to_boolean(v)

-> js_void(v)
  nil

-> js_eval_true(v)
  true

-> js_throw_value(v)
  raise JsThrow.new(v)

-> js_throw_ref(msg)
  raise JsThrow.new(js_reference_error(msg))

-> js_tdz_check(v, name)
  js_tdz_error(name) if v.is_a?(JsTdz)
  v

-> js_tdz_fill(env, lex)
  i = 0
  while i < lex.size
    env[lex[i]] = JS_TDZ
    i += 1
  nil

-> js_const_assign(cur, name)
  js_tdz_error(name) if cur.is_a?(JsTdz)
  js_const_error(name)

-> js_set_checked(frame, i, v, name)
  js_tdz_error(name) if frame[i].is_a?(JsTdz)
  frame[i] = v

-> js_cell_assign(c, v)
  js_tdz_error(c.name) if c.v.is_a?(JsTdz)
  js_const_error(c.name) if c.is_const
  c.v = v

-> js_gget_undefined
  r = JS_REALM[0]
  c = r.glex["undefined"]
  return c.v if c != nil
  nil

-> js_global_define_var(name, v)
  g = JS_REALM[0].global
  g.set(name, v, g)
  v

-> js_this_check(v)
  raise JsThrow.new(js_reference_error("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")) if v.is_a?(JsTdz)
  v

-> js_assign_ret(s, env, v)
  s.call(env, v)
  v

-> js_hoist(items, env)
  items.each ->(it)
    r = it[0]
    f = js_make_closure(it[1], env)
    if r.kind == :slot
      js_up(env, r.hops)[r.index] = f
    elsif r.kind == :cell
      r.binding.cell.v = f
    else
      g = JS_REALM[0].global
      js_define_global_function(g, r.name, f)
  nil

-> js_define_global_function(g, name, f)
  d = g.get_own_property(name)
  if d == nil || d.configurable == true
    g.define(name, f, ATTR_W + ATTR_E)
  else
    g.set(name, f, g)

-> js_param_var_copy(env, copies, hoist)
  copies.each ->(c) env[c[1]] = env[c[0]]
  hoist.call(env) if hoist != nil
  nil

-> js_fn_prologue(env, lex, hoist, stmts)
  js_tdz_fill(env, lex) if lex.size > 0
  hoist.call(env) if hoist != nil
  stmts.call(env)

# A script: hoist, then run with this = the global object; returns the completion value.
-> js_script_run(sc, body, hoist, lexes, gvars, cslot, this_v)
  r = JS_REALM[0]
  g = r.global
  gvars.each ->(nm)
    if !g.has_own?(nm)
      g.define(nm, nil, ATTR_W + ATTR_E)
  env = Array.new(sc.size, nil)
  env[FS_THIS] = this_v == nil ? g : this_v
  hoist.each ->(h)
    f = js_make_closure(h[1], env)
    js_define_global_function(g, h[0], f)
  js_tdz_fill(env, sc.lex)
  JS_DEPTH[0] = 0 if JS_DEPTH[0] < 0
  c = body.call(env)
  raise JsThrow.new(js_syntax_error("Illegal return statement")) if c != nil && c.kind == C_RETURN
  env[cslot]

-> js_eval_run(sc, body, hoist, lex, cslot, env)
  e = Array.new(sc.size, nil)
  e[0] = env
  js_tdz_fill(e, lex)
  js_hoist(hoist, e)
  c = body.call(e)
  e[cslot]

-> js_run_template(quasis, exprs, env)
  out = quasis[0]
  i = 0
  while i < exprs.size
    v = exprs[i].call(env)
    js_throw_type("Cannot convert a Symbol value to a string") if v.is_a?(JsSymbol)
    out = js_str_cat(js_str_cat(out, v.is_a?(String) ? v : js_to_string(v)), quasis[i + 1])
    i += 1
  out

# The frozen template object for a tagged template site (cached per site).
-> js_template_object(site)
  return site[2] if site[2] != nil
  r = JS_REALM[0]
  cooked = r.new_array(site[0].map(->(s) s))
  raw = r.new_array(site[1].map(->(s) s))
  js_freeze(raw)
  cooked.define("raw", raw, 0)
  js_freeze(cooked)
  site[2] = cooked
  cooked

-> js_tagged_call(f, this, site, exprs, env)
  args = [js_template_object(site)]
  exprs.each ->(e) args.push(e.call(env))
  js_call_named(f, this, args, "tag")

-> js_tagged_method(o, k, site, exprs, env)
  f = js_getv(o, k)
  js_tagged_call(f, o, site, exprs, env)

-> js_array_lit(fs, env)
  out = Array.new(fs.size, nil)
  i = 0
  while i < fs.size
    f = fs[i]
    out[i] = f == nil ? JS_HOLE : f.call(env)
    i += 1
  JsArray.new(JS_REALM[0].array_proto, out)

-> js_array_lit_spread_raw(parts, env)
  out = []
  parts.each ->(p)
    if p == nil
      out.push(nil)
    elsif p.is_a?(Array)
      js_spread_into(out, p[0].call(env))
    else
      out.push(p.call(env))
  out

-> js_array_lit_spread(parts, env)
  out = []
  parts.each ->(p)
    if p == nil
      out.push(JS_HOLE)
    elsif p.is_a?(Array)
      js_spread_into(out, p[0].call(env))
    else
      out.push(p.call(env))
  JsArray.new(JS_REALM[0].array_proto, out)

-> js_eval_args(fs, env)
  out = Array.new(fs.size, nil)
  i = 0
  while i < fs.size
    out[i] = fs[i].call(env)
    i += 1
  out

-> js_object_lit(ops, env)
  o = JsObject.new(JS_REALM[0].object_proto, "Object")
  i = 0
  while i < ops.size
    ops[i].call(env, o)
    i += 1
  o

-> js_lit_put(o, k, v)
  if o.attrs == nil && o.getters == nil
    o.props[k] = v
  else
    o.define(k, v, ATTR_ALL)
  nil

-> js_lit_put_named_fn(o, k, code, env)
  f = js_make_closure(code, env)
  f.define("name", k.is_a?(JsSymbol) ? "\[" + k.description.to_s + "]" : k, ATTR_C)
  o.define(k, f, ATTR_ALL)
  nil

-> js_lit_proto(o, v)
  o.proto = v if v.is_a?(JsObject) || v == JS_NULL
  nil

-> js_fn_name_for_key(k, prefix)
  base = k.is_a?(JsSymbol) ? (k.description == nil ? "" : "\[" + k.description + "]") : k
  prefix == nil ? base : prefix + " " + base

-> js_def_method(o, k, code, env, home, enumerable)
  f = js_make_closure(code, env)
  f.home = home
  f.define("name", js_fn_name_for_key(k, nil), ATTR_C) if code.name == "" || code.name == nil
  o.define(k, f, enumerable ? ATTR_ALL : ATTR_W + ATTR_C)
  f

-> js_def_getter(o, k, code, env, home)
  f = js_make_closure(code, env)
  f.home = home
  f.define("name", js_fn_name_for_key(k, "get"), ATTR_C)
  d = o.get_own_property(k)
  s = (d != nil && d.accessor?) ? d.setter : nil
  o.define_accessor(k, f, s, ATTR_E + ATTR_C)
  nil

-> js_def_setter(o, k, code, env, home)
  f = js_make_closure(code, env)
  f.home = home
  f.define("name", js_fn_name_for_key(k, "set"), ATTR_C)
  d = o.get_own_property(k)
  g = (d != nil && d.accessor?) ? d.getter : nil
  o.define_accessor(k, g, f, ATTR_E + ATTR_C)
  nil

# Copy own enumerable properties of src onto o (object spread, Object.assign-like without setters).
-> js_copy_data_props(o, src, excluded)
  return nil if js_nullish?(src)
  if src.is_a?(String)
    u = js_len(src)
    i = 0
    while i < u
      js_create_data(o, i.to_s, js_char_at(src, i))
      i += 1
    return nil
  return nil if !src.is_a?(JsObject)
  src.own_keys.each ->(k)
    if excluded == nil || !excluded.include?(k)
      d = src.get_own_property(k)
      if d != nil && d.enumerable == true
        js_create_data(o, k, src.get(k, src))
  nil

-> js_and(a, b, env)
  js_truthy(a) ? b.call(env) : a

-> js_or(a, b, env)
  js_truthy(a) ? a : b.call(env)

-> js_nullish_or(a, b, env)
  (a == nil || a == JS_NULL) ? b.call(env) : a

-> js_sub2(a, b)
  return a - b if a.is_a?(Float) && b.is_a?(Float)
  js_arith(:sub, a, b)

-> js_mul2(a, b)
  return a * b if a.is_a?(Float) && b.is_a?(Float)
  js_arith(:mul, a, b)

-> js_div2(a, b)
  return a / b if a.is_a?(Float) && b.is_a?(Float)
  js_arith(:div, a, b)

-> js_band2(a, b)
  return js_f(js_i32(a) & js_i32(b)) if a.is_a?(Float) && b.is_a?(Float)
  js_arith(:band, a, b)

-> js_bor2(a, b)
  return js_f(js_i32(a) | js_i32(b)) if a.is_a?(Float) && b.is_a?(Float)
  js_arith(:bor, a, b)

-> js_update_slot(frame, i, d, prefix)
  old = frame[i]
  if old.is_a?(Float)
    nv = old + d
    frame[i] = nv
    return prefix ? nv : old
  o = js_numeric_value(old)
  nv = js_inc(o, d)
  frame[i] = nv
  prefix ? nv : o

-> js_update_ref(g, s, d, prefix, env)
  o = js_numeric_value(g.call(env))
  nv = js_inc(o, d)
  s.call(env, nv)
  prefix ? nv : o

-> js_update_member(o, k, d, prefix, strict)
  old = js_numeric_value(js_getv(o, k))
  nv = js_inc(old, d)
  js_setv(o, k, nv, strict)
  prefix ? nv : old

-> js_assign_member(o, key, v, env, strict)
  js_nullish_set_check(o, key)
  val = v.call(env)
  js_setv(o, key, val, strict)
  val

-> js_assign_idx(o, k, v, env, strict)
  js_nullish_set_check(o, k)
  key = (k.is_a?(Float) || k.is_a?(String) || k.is_a?(JsSymbol)) ? k : js_to_property_key(k)
  val = v.call(env)
  js_setidx(o, key, val, strict)
  val

-> js_nullish_set_check(o, k)
  if o == nil || o == JS_NULL
    raise JsThrow.new(js_type_error("Cannot set properties of " + js_to_display(o) + " (setting '" + js_key_display(k.is_a?(Float) ? js_number_to_s(k) : k).to_s + "')"))
  nil

-> js_setv_k(o, k, v, strict)
  js_setv(o, k, v, strict)

-> js_compound_member(o, key, f, v, env, strict)
  old = js_getv(o, key)
  nv = f.call(old, v.call(env))
  js_setv(o, key, nv, strict)
  nv

-> js_compound_idx(o, k, f, v, env, strict)
  key = js_to_property_key(k)
  old = js_getv(o, key)
  nv = f.call(old, v.call(env))
  js_setv(o, key, nv, strict)
  nv

-> js_logical_assign_var(kind, g, s, v, env)
  cur = g.call(env)
  if kind == 1
    return cur if !js_truthy(cur)
  elsif kind == 2
    return cur if js_truthy(cur)
  else
    return cur if !js_nullish?(cur)
  nv = v.call(env)
  s.call(env, nv)
  nv

-> js_logical_assign_member(kind, o, k, v, env, strict)
  cur = js_getv(o, k)
  if kind == 1
    return cur if !js_truthy(cur)
  elsif kind == 2
    return cur if js_truthy(cur)
  else
    return cur if !js_nullish?(cur)
  nv = v.call(env)
  js_setv(o, k, nv, strict)
  nv

-> js_logical_assign_priv(kind, o, pn, v, env)
  cur = js_priv_get(o, pn)
  if kind == 1
    return cur if !js_truthy(cur)
  elsif kind == 2
    return cur if js_truthy(cur)
  else
    return cur if !js_nullish?(cur)
  nv = v.call(env)
  js_priv_set(o, pn, nv)
  nv

-> js_logical_assign_super(kind, home, this, k, v, env, strict)
  cur = js_super_get(home, k, this)
  if kind == 1
    return cur if !js_truthy(cur)
  elsif kind == 2
    return cur if js_truthy(cur)
  else
    return cur if !js_nullish?(cur)
  nv = v.call(env)
  js_super_set(home, k, nv, this, strict)
  nv

# ---- member reads (string-keyed fast paths) ----

-> js_getv_s(o, k)
  if o.is_a?(JsObject)
    v = o.get(k, o)
    js_trace_miss(o, k) if v == nil && JS_TRACE_MISS[0]
    return v
  js_getv(o, k)

JS_TRACE_MISS = [false]

# Debugging aid (BLADE_JS_TRACE=miss): report reads of absent properties on host objects.
-> js_trace_miss(o, k)
  c = o.cls
  if c == "Window" || c == "Navigator" || c == "HTMLDocument" || c == "Screen" || c == "Performance" || c == "Location" || c == "History" || c == "Element" || c == "Event" || c == "global"
    ccall("w_eputs", "\[js miss] " + c + "." + js_key_display(k).to_s)
  nil

-> js_get_length(o)
  return JS_SHORT if o == JS_SHORT
  if o.is_a?(JsArray)
    return o.elems.size + ~0.0 if o.slen == nil
    return o.length + ~0.0
  return js_len(o) + ~0.0 if o.is_a?(String)
  js_getv(o, "length")

-> js_getidx_s(o, k)
  return o.get(k, o) if k.is_a?(String) && o.is_a?(JsObject) && (k.size == 0 || k.byte_at(0) > 57)
  return JS_SHORT if o == JS_SHORT
  js_getidx(o, k)

-> js_unshort(v)
  v == JS_SHORT ? nil : v

-> js_opt_getv(o, k)
  return JS_SHORT if o == JS_SHORT
  return JS_SHORT if o == nil || o == JS_NULL
  js_getv(o, k)

-> js_opt_getidx(o, ke, env)
  return JS_SHORT if o == JS_SHORT
  return JS_SHORT if o == nil || o == JS_NULL
  js_getidx(o, ke.call(env))

-> js_delete_opt(o, kf, env, strict)
  return true if o == nil || o == JS_NULL
  js_delete(o, kf.call(env), strict)

-> js_delete_global(name)
  g = JS_REALM[0].global
  return true if !g.has_own?(name)
  g.delete_own(name)

# ---- calls ----

-> js_call_method(o, key, args)
  if o.is_a?(JsObject)
    f = o.get(key, o)
  else
    return JS_SHORT if o == JS_SHORT
    f = js_getv(o, key)
  if f.is_a?(JsFunction)
    return f.native.call(o, args, nil) if f.native != nil
    return js_call_code(f, o, args)
  js_call_named(f, o, args, js_callee_desc(o, key))

-> js_call_dotted(o, key, args, env, cp)
  return JS_SHORT if o == JS_SHORT
  f = o.is_a?(JsObject) ? o.get(key, o) : js_getv(o, key)
  av = args.call(env)
  JS_POS[JS_DEPTH[0]] = cp
  if f.is_a?(JsFunction)
    return f.native.call(o, av, nil) if f.native != nil
    r = js_call_code(f, o, av)
    js_args_done(f, av)
    return r
  js_call_named(f, o, av, js_callee_desc(o, key))

JS_NO_ARGS = []

# A call site's argument array once an interpreted callee has bound it: parameters, rest
# arrays and strict arguments objects all copy out of it, so it can be released. (Not for
# natives, which may keep views of it, nor for the empty literal, which may be shared.)
-> js_args_done(f, av)
  c = f.code
  return nil if c == nil || av.size == 0 || c.native != nil || (c.args_slot >= 0 && !c.strict)
  ccall("w_value_free_w", av)
  nil

-> js_call_ident_site(f, args, env, cp, what)
  fv = f.call(env)
  av = args.call(env)
  JS_POS[JS_DEPTH[0]] = cp
  if fv.is_a?(JsFunction) && fv.native == nil && fv.code != nil
    r = js_call_code(fv, nil, av)
    js_args_done(fv, av)
    return r
  js_call_named(fv, nil, av, what)

-> js_callee_desc(o, key)
  base = o.is_a?(JsFunction) ? o.fname.to_s : (o.is_a?(JsObject) ? (o.cls == "Object" ? "object" : o.cls) : js_typeof(o))
  base + "." + js_key_display(key).to_s

-> js_call_method_idx(o, ke, args, env, oopt, opt)
  return JS_SHORT if o == JS_SHORT
  return JS_SHORT if oopt && (o == nil || o == JS_NULL)
  k = js_to_property_key(ke.call(env))
  f = js_getv(o, k)
  return JS_SHORT if opt && (f == nil || f == JS_NULL)
  js_call_named(f, o, args.call(env), js_callee_desc(o, k))

-> js_call_method_opt(o, key, args, env, oopt, opt)
  return JS_SHORT if o == JS_SHORT
  return JS_SHORT if oopt && (o == nil || o == JS_NULL)
  f = js_getv(o, key)
  return JS_SHORT if opt && (f == nil || f == JS_NULL)
  js_call_named(f, o, args.call(env), js_callee_desc(o, key))

-> js_call_opt(f, args, env)
  return JS_SHORT if f == JS_SHORT
  return JS_SHORT if f == nil || f == JS_NULL
  js_call_named(f, nil, args.call(env), "expression")

-> js_bind2(env, args, i0, i1)
  n = args.size
  env[i0] = n > 0 ? args[0] : nil
  env[i1] = n > 1 ? args[1] : nil
  nil

-> js_bind_simple(env, args, idx)
  i = 0
  n = idx.size
  m = args.size
  while i < n
    env[idx[i]] = i < m ? args[i] : nil
    i += 1
  nil

-> js_bind_simple_args(env, args, idx, aslot, strict)
  js_bind_simple(env, args, idx)
  env[aslot] = strict ? js_arguments(args, env[FS_FUNC], strict) : js_mapped_arguments(args, env[FS_FUNC], env, idx)
  nil

-> js_bind_params(env, args, items, aslot, strict)
  env[aslot] = js_arguments(args, env[FS_FUNC], strict) if aslot >= 0
  i = 0
  while i < items.size
    it = items[i]
    if it[0] == 2
      rest = i < args.size ? args.slice(i, args.size - i) : []
      it[1].call(env, JS_REALM[0].new_array(rest))
    else
      it[1].call(env, i < args.size ? args[i] : nil)
    i += 1
  nil

# ---- destructuring ----

-> js_destructure_array(env, v, items)
  if v.is_a?(JsArray) && js_array_iter_pristine?(v)
    i = 0
    while i < items.size
      it = items[i]
      ref = it[2] == nil ? nil : it[2].call(env)
      if it[0] == 2
        rest = []
        j = i
        while j < v.length
          rest.push(js_arr_elem(v, j))
          j += 1
        js_destr_store(env, it[1], it[3], ref, JS_REALM[0].new_array(rest))
      elsif it[0] == 0
        js_destr_store(env, it[1], it[3], ref, i < v.length ? js_arr_elem(v, i) : nil)
      i += 1
    return nil
  js_throw_type(js_to_display(v) + " is not iterable") if js_nullish?(v)
  rec = js_get_iterator(v)
  begin
    items.each ->(it)
      ref = it[2] == nil ? nil : it[2].call(env)
      if it[0] == 2
        rest = []
        while !rec.done
          x = js_iter_step(rec)
          rest.push(x) if x != JS_ITER_DONE
        js_destr_store(env, it[1], it[3], ref, JS_REALM[0].new_array(rest))
      else
        x = rec.done ? nil : js_iter_step(rec)
        x = nil if x == JS_ITER_DONE
        js_destr_store(env, it[1], it[3], ref, x) if it[0] == 0
  rescue e
    js_iter_close_quiet(rec) if !rec.done
    raise e
  js_iter_close(rec) if !rec.done
  nil

-> js_iter_close_quiet(rec)
  begin
    js_iter_close(rec)
  rescue e2
    nil
  nil

-> js_destructure_object(env, v, items)
  if js_nullish?(v)
    raise JsThrow.new(js_type_error("Cannot destructure '" + js_to_display(v) + "' as it is " + (v == nil ? "undefined" : "null") + "."))
  used = nil
  items.each ->(it)
    if it[0] == nil
      ref = it[3] == nil ? nil : it[3].call(env)
      r = JsObject.new(JS_REALM[0].object_proto, "Object")
      js_copy_data_props(r, v, used == nil ? [] : used)
      js_destr_store(env, it[1], it[4], ref, r)
    else
      k = it[0].call(env)
      used = [] if used == nil
      used.push(k)
      ref = it[3] == nil ? nil : it[3].call(env)
      js_destr_store(env, it[1], it[4], ref, js_getv(v, k))
  nil

# Store a destructured value: into a reference prepared before the read, or via the setter.
-> js_destr_store(env, setter, set_ref, ref, v)
  if set_ref != nil
    set_ref.call(env, ref, v)
  else
    setter.call(env, v)
  nil

# ---- loops ----

-> js_loop_ctl(r, labels)
  # 0: continue looping, 1: break out normally, 2: propagate r
  if r.kind == C_BREAK
    return 1 if r.label == nil || (labels != nil && labels.include?(r.label))
    return 2
  if r.kind == C_CONTINUE
    return 0 if r.label == nil || (labels != nil && labels.include?(r.label))
    return 2
  2

-> js_run_while(t, b, labels, env)
  while t.call(env)
    js_watchdog() if ((JS_TICKS[0] += 1) & 65535) == 0
    r = b.call(env)
    if r != nil
      c = js_loop_ctl(r, labels)
      return nil if c == 1
      return r if c == 2
  nil

-> js_run_do_while(t, b, labels, env)
  while true
    r = b.call(env)
    if r != nil
      c = js_loop_ctl(r, labels)
      return nil if c == 1
      return r if c == 2
    break if !t.call(env)
  nil

-> js_run_for(lex, ic, t, u, b, labels, env)
  js_tdz_fill(env, lex) if lex.size > 0
  ic.call(env) if ic != nil
  while t == nil || t.call(env)
    js_watchdog() if ((JS_TICKS[0] += 1) & 65535) == 0
    r = b.call(env)
    if r != nil
      c = js_loop_ctl(r, labels)
      return nil if c == 1
      return r if c == 2
    u.call(env) if u != nil
  nil

# for (let ...) whose body has closures: a fresh copy of the loop frame each iteration.
-> js_run_for_owner(size_of, lex, ic, t, u, b, labels, env)
  e = Array.new(size_of.size, nil)
  e[0] = env
  js_tdz_fill(e, lex)
  ic.call(e) if ic != nil
  # CreatePerIterationEnvironment also runs before the first test (§14.7.4.4)
  e = e.dup
  while t == nil || t.call(e)
    r = b.call(e)
    if r != nil
      c = js_loop_ctl(r, labels)
      return nil if c == 1
      return r if c == 2
    e = e.dup
    u.call(e) if u != nil
  nil

-> js_run_for_in_init(target, ivc, rhs, b, labels, owner, size_of, lex, env)
  target.call(env, ivc.call(env))
  js_run_for_in(rhs.call(env), target, b, labels, owner, size_of, lex, env)

-> js_iter_frame(owner, size_of, lex, env)
  return env if !owner
  e = Array.new(size_of.size, nil)
  e[0] = env
  js_tdz_fill(e, lex)
  e

-> js_run_for_in(obj, target, b, labels, owner, size_of, lex, env)
  keys = js_for_in_keys(obj)
  return nil if keys.size == 0
  o = js_to_object(obj)
  keys.each ->(k)
    if js_still_has?(o, k)
      e = js_iter_frame(owner, size_of, lex, env)
      target.call(e, k)
      r = b.call(e)
      if r != nil
        c = js_loop_ctl(r, labels)
        return nil if c == 1
        return r if c == 2
  nil

-> js_still_has?(o, k)
  o.has_property?(k)

-> js_run_for_of(v, target, b, labels, owner, size_of, lex, env)
  if v.is_a?(JsArray) && js_array_iter_pristine?(v)
    i = 0
    while i < v.length
      x = js_arr_elem(v, i)
      e = js_iter_frame(owner, size_of, lex, env)
      target.call(e, x)
      r = b.call(e)
      if r != nil
        c = js_loop_ctl(r, labels)
        return nil if c == 1
        return r if c == 2
      i += 1
    return nil
  rec = js_get_iterator(v)
  while true
    x = js_iter_step(rec)
    break if x == JS_ITER_DONE
    r = js_for_of_body(rec, target, b, owner, size_of, lex, env, x)
    if r != nil
      c = js_loop_ctl(r, labels)
      if c != 0
        js_iter_close(rec)
        return nil if c == 1
        return r
  nil

# One for-of iteration; closes the iterator if the body throws.
-> js_for_of_body(rec, target, b, owner, size_of, lex, env, x)
  begin
    e = js_iter_frame(owner, size_of, lex, env)
    target.call(e, x)
    return b.call(e)
  rescue err
    js_iter_close_quiet(rec)
    raise err
  nil

-> js_run_for_await(c, v, target, b, labels, owner, size_of, lex, env)
  m = js_get_method(v, SYM_ASYNC_ITERATOR)
  rec = nil
  if m == nil
    rec = js_get_iterator(v)
    rec = js_async_from_sync(rec)
  else
    it = js_call(m, v, [])
    rec = JsIterRecord.new(it, it.get("next"))
  while true
    res = js_await(c, js_call(rec.next_fn, rec.iterator, []))
    js_throw_type("iterator result is not an object") if !res.is_a?(JsObject)
    break if js_to_boolean(res.get("done"))
    x = res.get("value")
    e = js_iter_frame(owner, size_of, lex, env)
    target.call(e, x)
    r = b.call(e)
    if r != nil
      cc = js_loop_ctl(r, labels)
      if cc != 0
        ret = js_get_method(rec.iterator, "return")
        js_await(c, js_call(ret, rec.iterator, [])) if ret != nil
        return nil if cc == 1
        return r
  nil

# A sync iterator record adapted for for-await (values are awaited by the loop).
-> js_async_from_sync(rec)
  r = JS_REALM[0]
  o = r.new_object
  nx = r.native("next", 0, ->(this, args, nt) js_async_from_sync_next(rec))
  o.define("next", nx, BUILTIN_ATTRS)
  ret = js_get_method(rec.iterator, "return")
  o.define("return", ret, BUILTIN_ATTRS) if ret != nil
  JsIterRecord.new(o, nx)

-> js_async_from_sync_next(rec)
  res = js_call(rec.next_fn, rec.iterator, [])
  js_throw_type("iterator result is not an object") if !res.is_a?(JsObject)
  done = js_to_boolean(res.get("done"))
  p = js_promise_resolve_value(res.get("value"))
  on_ok = ->(x) js_iter_result(x, done)
  js_promise_then_value(p, on_ok)

-> js_run_switch(d, tests, bodies, labels, owner, size_of, lex, enter, env)
  e = env
  if owner
    e = Array.new(size_of.size, nil)
    e[0] = env
  js_tdz_fill(e, lex) if lex.size > 0
  enter.call(e) if enter != nil
  start = -1
  dflt = -1
  i = 0
  while i < tests.size
    t = tests[i]
    if t == nil
      dflt = i
    elsif js_strict_eq(d, t.call(e))
      start = i
      break
    i += 1
  start = dflt if start < 0
  return nil if start < 0
  j = start
  while j < bodies.size
    r = bodies[j].call(e)
    if r != nil
      return nil if r.kind == C_BREAK && (r.label == nil || (labels != nil && labels.include?(r.label)))
      return r
    j += 1
  nil

-> js_run_labeled(b, labels, env)
  r = b.call(env)
  return nil if r != nil && r.kind == C_BREAK && r.label != nil && labels.include?(r.label)
  r

-> js_run_with(o, idx, b, env)
  env[idx] = js_to_object(o)
  b.call(env)

-> js_with_has?(o, name)
  return false if !o.has_property?(name)
  u = o.get(SYM_UNSCOPABLES, o)
  return true if !u.is_a?(JsObject)
  !js_to_boolean(u.get(name, u))

-> js_with_call(env, ws, name, g0, args, cp)
  base = nil
  f = nil
  found = false
  ws.each ->(w)
    if !found
      o = js_up(env, w[0])[w[1]]
      if js_with_has?(o, name)
        found = true
        base = o
        f = o.get(name, o)
  f = g0.call(env) if !found
  av = args.call(env)
  JS_POS[JS_DEPTH[0]] = cp
  js_call_named(f, base, av, name)

-> js_with_get(o, name, inner, env)
  return o.get(name, o) if js_with_has?(o, name)
  inner.call(env)

-> js_with_set(o, name, inner, env, v, strict)
  if js_with_has?(o, name)
    js_setv(o, name, v, strict)
    return v
  inner.call(env, v)

# ---- try ----

-> js_run_try_catch(block, handler, env)
  d = JS_DEPTH[0]
  begin
    return block.call(env)
  rescue e
    raise e if e.is_a?(JsGenReturn)
    JS_DEPTH[0] = d
    v = js_error_value(e)
    js_trace_catch(v) if JS_TRACE_CATCH[0]
    return handler.call(env, v)
  nil

-> js_cpl_reset(env, h, slot, inner)
  js_up(env, h)[slot] = nil
  inner.call(env)

-> js_cpl_catch(env, h, slot, handler, v)
  js_up(env, h)[slot] = nil
  handler.call(env, v)

-> js_cpl_keep(env, h, slot, fin)
  fr = js_up(env, h)
  saved = fr[slot]
  rv = JS_RETVAL[0]
  r = fin.call(env)
  JS_RETVAL[0] = rv if r == nil
  fr[slot] = saved if r == nil
  r

-> js_annexb_set(fr, i, v)
  fr[i] = v
  nil

-> js_annexb_global(nm, v)
  js_gset(nm, v, false)
  nil

-> js_run_try_finally(block, fin, env)
  d = JS_DEPTH[0]
  r = nil
  err = nil
  begin
    r = block.call(env)
  rescue e
    err = e
  JS_DEPTH[0] = d if err != nil
  rv = r == JS_RET_MARK ? JS_RETVAL[0] : nil
  f = fin.call(env)
  return f if f != nil
  raise err if err != nil
  JS_RETVAL[0] = rv if r == JS_RET_MARK
  r

-> js_run_try_catch_finally(block, handler, fin, env)
  d = JS_DEPTH[0]
  r = nil
  err = nil
  begin
    r = block.call(env)
  rescue e
    err = e
  if err != nil && !err.is_a?(JsGenReturn)
    JS_DEPTH[0] = d
    v = js_error_value(err)
    js_trace_catch(v) if JS_TRACE_CATCH[0]
    err = nil
    begin
      r = handler.call(env, v)
    rescue e2
      err = e2
  JS_DEPTH[0] = d if err != nil
  rv = r == JS_RET_MARK ? JS_RETVAL[0] : nil
  f = fin.call(env)
  return f if f != nil
  raise err if err != nil
  JS_RETVAL[0] = rv if r == JS_RET_MARK
  r

-> js_catch_owner(size_of, bind, hb, env, v)
  e = Array.new(size_of.size, nil)
  e[0] = env
  bind.call(e, v)
  hb.call(e)

-> js_catch_inline(bind, hb, env, v)
  bind.call(env, v)
  hb.call(env)

# ---- super ----

-> js_super_get(home, k, this)
  js_throw_ref("'super' keyword unexpected here") if home == nil
  p = home.get_prototype_of
  return nil if p == nil || p == JS_NULL
  p.get(k, this)

-> js_super_set(home, k, v, this, strict)
  p = home.get_prototype_of
  ok = p.set(k, v, this)
  js_set_failed(this, k) if !ok && strict
  v

-> js_super_compound(home, this, k, f, v, env, strict)
  old = js_super_get(home, k, this)
  nv = f.call(old, v.call(env))
  js_super_set(home, k, nv, this, strict)
  nv

-> js_super_update(home, this, k, d, prefix, strict)
  old = js_numeric_value(js_super_get(home, k, this))
  nv = js_inc(old, d)
  js_super_set(home, k, nv, this, strict)
  prefix ? nv : old

-> js_super_method_call(home, k, this, args)
  f = js_super_get(home, k, this)
  js_call_named(f, this, args, "(intermediate value)." + js_key_display(k).to_s)

-> js_super_method_call_l(home, this, kf, args, env)
  k = kf.call(env)
  f = js_super_get(home, k, this)
  js_call_named(f, this, args.call(env), "(intermediate value)." + js_key_display(k).to_s)

# super(...) with GetSuperConstructor before the arguments are evaluated (§13.3.7.1).
-> js_super_call_l(frame, args, env)
  f = frame[FS_FUNC]
  parent = f.get_prototype_of
  av = args.call(env)
  # IsConstructor is checked after ArgumentListEvaluation (§13.3.7.1 steps 3-5)
  js_throw_type("Super constructor " + js_to_display(parent) + " of anonymous class is not a constructor") if !(parent.is_a?(JsObject) && js_is_constructor?(parent))
  js_super_call_with(frame, f, parent, av)

-> js_super_call_with(frame, f, parent, args)
  obj = js_construct(parent, args, frame[FS_NT])
  raise JsThrow.new(js_reference_error("Super constructor may only be called once")) if !frame[FS_THIS].is_a?(JsTdz)
  frame[FS_THIS] = obj
  js_init_fields(f, obj)
  obj

# super(...args) in a derived constructor; frame is the constructor's frame.
-> js_super_call(frame, args)
  f = frame[FS_FUNC]
  parent = f.get_prototype_of
  js_throw_type("Super constructor " + js_to_display(parent) + " of anonymous class is not a constructor") if !(parent.is_a?(JsObject) && js_is_constructor?(parent))
  obj = js_construct(parent, args, frame[FS_NT])
  raise JsThrow.new(js_reference_error("Super constructor may only be called once")) if !frame[FS_THIS].is_a?(JsTdz)
  frame[FS_THIS] = obj
  js_init_fields(f, obj)
  obj

# ---- private members ----

-> js_priv_get(o, pn)
  js_throw_type("Cannot read private member #" + pn.description + " from an object whose class did not declare it") if !o.is_a?(JsObject)
  o.priv_get(pn)

-> js_opt_priv_get(o, pn)
  return JS_SHORT if o == JS_SHORT || o == nil || o == JS_NULL
  js_priv_get(o, pn)

-> js_priv_set(o, pn, v)
  js_throw_type("Cannot write private member #" + pn.description + " to an object whose class did not declare it") if !o.is_a?(JsObject)
  o.priv_set(pn, v)
  v

-> js_priv_compound(o, pn, f, v, env)
  old = js_priv_get(o, pn)
  nv = f.call(old, v.call(env))
  js_priv_set(o, pn, nv)

-> js_priv_update(o, pn, d, prefix)
  old = js_numeric_value(js_priv_get(o, pn))
  nv = js_inc(old, d)
  js_priv_set(o, pn, nv)
  prefix ? nv : old

-> js_priv_in(pn, o)
  js_throw_type("Cannot use 'in' operator to search for '#" + pn.description + "' in " + js_to_display(o)) if !o.is_a?(JsObject)
  o.priv_has?(pn)

-> js_call_priv(o, pn, args, env)
  f = js_priv_get(o, pn)
  js_call_named(f, o, args.call(env), "#" + pn.description)

# ---- classes ----

-> js_class_create(env, size_of, fsize, privs, sup, derived, ccode, members, self_slot, cname)
  r = JS_REALM[0]
  ce = Array.new(size_of.size, nil)
  ce[0] = env
  privs.each ->(p)
    pn = JsPrivateName.new(p[0])
    pn.is_method = p[2]
    ce[p[1]] = pn
  ce[self_slot] = JS_TDZ if self_slot >= 0
  proto_parent = r.object_proto
  ctor_parent = r.function_proto
  if derived
    sv = sup.call(ce)
    if sv == JS_NULL
      proto_parent = JS_NULL
    elsif !(sv.is_a?(JsObject) && js_is_constructor?(sv))
      js_throw_type("Class extends value " + js_to_display(sv) + " is not a constructor or null")
    else
      pp = sv.get("prototype")
      js_throw_type("Class extends value does not have valid prototype property") if !(pp.is_a?(JsObject) || pp == JS_NULL)
      proto_parent = pp
      ctor_parent = sv
  proto = JsObject.new(proto_parent, "Object")
  f = JsFunction.new(ctor_parent, nil, cname == nil ? "" : cname, ccode.length, true)
  f.code = ccode
  f.scope = ce
  f.home = proto
  f.cls_kind = derived ? :derived : :base
  f.define("prototype", proto, 0)
  proto.define("constructor", f, ATTR_W + ATTR_C)
  fi = JsFieldInit.new(ce, fsize.size)
  statics = []
  members.each ->(m)
    kind = m[0]
    static = m[1]
    target = static ? f : proto
    if kind == :field
      key = m[4] >= 0 ? ce[m[4]] : m[2].call(ce)
      if static
        statics.push([:field, key, m[3], m[4] >= 0])
      else
        fi.items.push([key, m[3], m[4] >= 0])
    elsif kind == :block
      statics.push([:block, m[3]])
    elsif m[4] >= 0
      pn = ce[m[4]]
      fnc = js_make_closure(m[3], ce)
      fnc.home = target
      if static
        js_class_priv_member(f, pn, kind, fnc)
      else
        js_class_priv_proto(fi, pn, kind, fnc)
    else
      key = m[2].call(ce)
      if kind == :getter
        js_def_getter_cls(target, key, m[3], ce, target)
      elsif kind == :setter
        js_def_setter_cls(target, key, m[3], ce, target)
      else
        js_def_method(target, key, m[3], ce, target, false)
  if fi.items.size > 0 || fi.privs.size > 0
    f.fields = fi
  elsif derived && sup != nil
    f.fields = nil
  ce[self_slot] = f if self_slot >= 0
  # static fields and blocks, in order, with this = the class
  senv = Array.new(fsize.size, nil)
  senv[0] = ce
  senv[FS_THIS] = f
  senv[FS_FUNC] = f
  senv[FS_HOME] = f
  statics.each ->(s)
    if s[0] == :field
      v = s[2] == nil ? nil : s[2].call(senv)
      if s[3]
        f.priv_add(s[1], v)
      else
        js_create_data(f, s[1], v)
    else
      s[1].call(ce, f)
  f

-> js_class_priv_member(o, pn, kind, fnc)
  if kind == :method
    o.priv_add(pn, fnc)
    return nil
  o.priv = {} if o.priv == nil
  e = o.priv[pn]
  e = JsPrivAccessor.new(nil, nil) if e == nil
  e.getter = fnc if kind == :getter
  e.setter = fnc if kind == :setter
  o.priv[pn] = e
  nil

-> js_class_priv_proto(fi, pn, kind, fnc)
  if kind == :method
    fi.privs.push([pn, fnc])
    return nil
  found = nil
  fi.privs.each ->(p)
    found = p if p[0] == pn
  if found == nil
    found = [pn, JsPrivAccessor.new(nil, nil)]
    fi.privs.push(found)
  found[1].getter = fnc if kind == :getter
  found[1].setter = fnc if kind == :setter
  nil

-> js_def_getter_cls(o, k, code, env, home)
  f = js_make_closure(code, env)
  f.home = home
  f.define("name", js_fn_name_for_key(k, "get"), ATTR_C)
  d = o.get_own_property(k)
  s = (d != nil && d.accessor?) ? d.setter : nil
  o.define_accessor(k, f, s, ATTR_C)
  nil

-> js_def_setter_cls(o, k, code, env, home)
  f = js_make_closure(code, env)
  f.home = home
  f.define("name", js_fn_name_for_key(k, "set"), ATTR_C)
  d = o.get_own_property(k)
  g = (d != nil && d.accessor?) ? d.getter : nil
  o.define_accessor(k, g, f, ATTR_C)
  nil

-> js_static_block_run(ce, size_of, lex, hoist, body, f)
  e = Array.new(size_of.size, nil)
  e[0] = ce
  e[FS_THIS] = f
  e[FS_FUNC] = f
  e[FS_HOME] = f
  js_tdz_fill(e, lex)
  hoist.call(e) if hoist != nil
  body.call(e)
  nil

# ---- eval ----

-> js_direct_eval(f, args, sc, env, strict)
  r = JS_REALM[0]
  if f != r.intrinsic("eval")
    return js_call_named(f, nil, args, "eval")
  src = args.size > 0 ? js_eval_source(args[0]) : nil
  return src if !src.is_a?(String)
  prog = js_parse_or_throw(src, false)
  comp = JsCompiler.new(src)
  comp.lazy = src.size >= JS_LAZY_MIN[0]
  run = comp.compile_eval(prog, sc, strict)
  run.call(env)

-> js_parse_or_throw(src, mod)
  if src.size >= JS_LAZY_MIN[0]
    # lazy parsing: function bodies are skipped now and parsed on their first call; on
    # any error parse again eagerly, so errors (and any skipper mistake) match eager mode
    lp = JsParser.new(src, mod)
    lp.lazy = true
    begin
      return lp.parse_program()
    rescue e
      JS_LAZY_STATS[3] += 1
      ccall("w_eputs", "\[js lazy] eager reparse: " + (lp.error == nil ? e.message.to_s : lp.error.to_s)) if JS_LAZY_DEBUG[0]
  p = JsParser.new(src, mod)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    err = p.error
    msg = err == nil ? e.message.to_s : err.msg
    raise JsThrow.new(js_syntax_error(msg))
  prog

-> js_parse_bigint_literal(s)
  t = s
  radix = 10
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    if b == 120
      radix = 16
    elsif b == 111
      radix = 8
    elsif b == 98
      radix = 2
    t = t.slice(2, t.size - 2) if radix != 10
  v = 0 ## int
  i = 0
  while i < t.size
    c = t.byte_at(i)
    if c != 95
      v = v * radix + js_digit(c)
    i += 1
  JsBigInt.new(v)

JS_NOP = [nil]
JS_TRACE_CATCH = [false]

# Debugging aid (BLADE_JS_TRACE=1): print every exception a script's own catch swallows.
-> js_trace_catch(v)
  m = v.is_a?(JsObject) ? js_inspect(v, 2, []) : js_to_display(v)
  ccall("w_eputs", "\[js caught] " + m.slice(0, 1500))
  nil

# A statement lambda that does nothing, for an omitted body.
-> js_nop_stmt(c)
  return c if c != nil
  if JS_NOP[0] == nil
    JS_NOP[0] = ->(env) nil
  JS_NOP[0]

# Parse a lazily-skipped function body (see JsLazyBody in the parser).
-> js_lazy_parse_body(n, src)
  lz = n.c
  t0 = clock()
  p = JsParser.new(src, lz.module)
  p.lazy = true
  body = nil
  begin
    body = p.parse_lazy_body(lz)
  rescue e
    err = p.error
    raise JsThrow.new(js_syntax_error(err == nil ? e.message.to_s : err.msg))
  n.b = body
  n.c = nil
  n.flags = n.flags | p.lazy_flags
  JS_LAZY_STATS[2] += 1
  JS_LAZY_T[1] = JS_LAZY_T[1] + (clock() - t0)
  nil
