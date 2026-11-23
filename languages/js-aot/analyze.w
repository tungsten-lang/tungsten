# analyze — scope analysis for compiled JavaScript: the one owner of binding layout.
#
#   a = JaAnalysis.new(program_node, strict)
#   a.run                        # a.funcs: every function (and the script) in pre-order
#
# For each binding it decides where the value lives (PLAN.md 3.4):
#   local     a Tungsten local of the function that declares it
#   env       slot `slot` of its scope's JS:Env (captured by a nested function)
#   global    a JS:GlobalCell (script-level var/function, unresolved names)
#   lexical   a JS:GlobalCell in the realm's script-lexical table (top-level let/const)
#
# and for each function value which form tier 1 can use (PLAN.md 3.9):
#   fclass :call_only   no function object: every use is the callee of a plain call
#   fclass :escaping    a lean JS:Function object
#   single              the one captured binding, stored by value in the object's @env
#                       (it is never reassigned after its initializer), or nil
#
# Functions that use a construct the slice cannot compile yet carry `unsupported`
# (the reason); a function using direct eval or `with` is `dynamic` and stays in tier 0.

use frontend/parser

+ JaBinding
  rw :name, :kind, :scope, :slot, :local, :captured, :writes, :reads, :value_uses, :callee_uses, :fnode, :tdz, :decl_pos, :early_read, :init_before_fns, :id

  -> new(@name, @kind, @scope)
    @slot = -1
    @local = nil
    @captured = false
    @writes = 0
    @reads = 0
    @value_uses = 0
    @callee_uses = 0
    @fnode = nil
    @tdz = false
    @decl_pos = 0
    @early_read = false
    @init_before_fns = true
    @id = 0

  -> global?
    @kind == :global || @kind == :lexical

  -> in_env?
    @slot >= 0

+ JaScope
  rw :kind, :parent, :func, :names, :env_count, :id, :node, :per_iter, :order

  -> new(@kind, @parent, @func, @node)
    @names = {}
    @order = []
    @env_count = 0
    @id = 0
    @per_iter = false

  -> declare(a, name, kind)
    b = @names[name]
    return b if b != nil
    b = JaBinding.new(name, kind, self)
    a.bind_count += 1
    b.id = a.bind_count
    @names[name] = b
    @order.push(b)
    b

  -> has_env?
    @env_count > 0

+ JaFunc
  rw :node, :parent, :index, :scope, :strict, :arrow, :uses_this, :uses_args, :dynamic, :free, :fclass, :single, :inner, :binding, :self_binding, :unsupported, :name, :def_scope, :nparams, :params, :this_binding, :body_scope, :script

  -> new(@node, @parent, @index)
    @scope = nil
    @strict = false
    @arrow = false
    @uses_this = false
    @uses_args = false
    @dynamic = false
    @free = {}
    @fclass = :escaping
    @single = nil
    @inner = []
    @binding = nil
    @self_binding = nil
    @unsupported = nil
    @name = ""
    @def_scope = nil
    @nparams = 0
    @params = []
    @this_binding = nil
    @body_scope = nil
    @script = false

  -> fail(why)
    @unsupported = why if @unsupported == nil
    nil

+ JaAnalysis
  rw :program, :funcs, :strict, :bind_count, :scope_count, :unsupported_counts

  -> new(@program, @strict)
    @funcs = []
    @bind_count = 0
    @scope_count = 0
    @unsupported_counts = {}
    @fnmap = {}
    @scopemap = {}

  -> new_scope(kind, parent, func, node)
    s = JaScope.new(kind, parent, func, node)
    @scope_count += 1
    s.id = @scope_count
    s

  -> run
    f = JaFunc.new(@program, nil, 0)
    f.script = true
    f.strict = @strict || @program.has?(F_STRICT)
    @funcs.push(f)
    sc = new_scope(:script, nil, f, @program)
    f.scope = sc
    f.body_scope = sc
    hoist_body(f, sc, @program.list, true)
    walk_stmts(@program.list, sc)
    finish()
    self

  # ---- declarations (hoisting) ----

  -> bound_names(p, out)
    return out if p == nil
    k = p.kind
    if k == :ident
      out.push(p.str)
    elsif k == :array_pattern
      i = 0
      while i < p.list.size
        bound_names(p.list[i], out) if p.list[i] != nil
        i += 1
    elsif k == :object_pattern
      i = 0
      while i < p.list.size
        e = p.list[i]
        bound_names(e.kind == :rest ? e.a : e.b, out)
        i += 1
    elsif k == :assign_pattern || k == :rest
      bound_names(p.a, out)
    out

  # var-declared names of a statement list, not entering functions; sloppy-mode
  # function declarations in nested blocks are var-scoped too (Annex B).
  -> var_names(stmts, out, strict, top)
    i = 0
    while i < stmts.size
      var_names_stmt(stmts[i], out, strict, top)
      i += 1
    out

  -> var_names_stmt(s, out, strict, top)
    return nil if s == nil
    k = s.kind
    if k == :var_decl
      if s.str == "var"
        i = 0
        while i < s.list.size
          bound_names(s.list[i].a, out)
          i += 1
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
      i = 0
      while i < s.list.size
        var_names(s.list[i].list, out, strict, false)
        i += 1
    elsif k == :labeled
      var_names_stmt(s.a, out, strict, false)
    elsif k == :with
      var_names_stmt(s.b, out, strict, false)
    nil

  # Declare the hoisted names of a function or script body in sc. (Annex B names that a
  # top-level let, const or class of the body already declares are not vars.)
  -> hoist_body(f, sc, stmts, top)
    vn = var_names(stmts, [], f.strict, true)
    lex = lexical_names(stmts)
    i = 0
    while i < vn.size
      kind = sc.kind == :script ? :global : :var
      b = sc.declare(self, vn[i], kind) if !lex.include?(vn[i])
      i += 1
    hoist_block(sc, stmts, top)

  -> lexical_names(stmts)
    out = []
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :var_decl && s.str != "var"
        j = 0
        while j < s.list.size
          bound_names(s.list[j].a, out)
          j += 1
      elsif s.kind == :class_decl && s.str != nil
        out.push(s.str)
      i += 1
    out

  # Lexical declarations and function declarations directly in a statement list.
  -> hoist_block(sc, stmts, top)
    script = sc.kind == :script
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :var_decl && s.str != "var"
        j = 0
        while j < s.list.size
          names = bound_names(s.list[j].a, [])
          q = 0
          while q < names.size
            b = sc.declare(self, names[q], script ? :lexical : (s.str == "const" ? :const : :let))
            b.decl_pos = s.fin
            q += 1
          j += 1
      elsif s.kind == :class_decl && s.str != nil
        b = sc.declare(self, s.str, script ? :lexical : :class)
        b.decl_pos = s.fin
      elsif s.kind == :function_decl && s.str != nil
        b = sc.declare(self, s.str, script ? :global : :function)
        b.writes += 1
      i += 1
    nil

  # ---- the walk: scopes, references, function values ----

  -> walk_stmts(stmts, sc)
    i = 0
    while i < stmts.size
      walk_stmt(stmts[i], sc)
      i += 1
    nil

  -> walk_stmt(s, sc)
    return nil if s == nil
    f = sc.func
    k = s.kind
    if k == :expr_stmt
      walk_expr(s.a, sc)
    elsif k == :var_decl
      i = 0
      while i < s.list.size
        d = s.list[i]
        if d.a.kind != :ident
          f.fail("destructuring")
        else
          b = resolve(d.a.str, sc)
          if d.b != nil
            note_fn_value(d.b, b)
            walk_expr(d.b, sc)
            note_write(b, sc, d.a.pos)
          elsif s.str != "var"
            note_write(b, sc, d.a.pos)
        i += 1
    elsif k == :function_decl
      walk_function(s, sc, resolve(s.str, sc))
    elsif k == :class_decl
      f.fail("class")
    elsif k == :block
      bs = block_scope(sc, s, s.list)
      walk_stmts(s.list, bs)
    elsif k == :empty || k == :debugger
      nil
    elsif k == :if
      walk_expr(s.a, sc)
      walk_stmt(s.b, sc)
      walk_stmt(s.c, sc)
    elsif k == :for
      fs = sc
      if s.a != nil && s.a.kind == :var_decl && s.a.str != "var"
        fs = map_scope(s, new_scope(:for, sc, f, s))
        hoist_block(fs, [s.a], false)
        fs.per_iter = true
      if s.a != nil
        if s.a.kind == :var_decl
          walk_stmt(s.a, fs)
        else
          walk_expr(s.a, fs)
      walk_expr(s.b, fs) if s.b != nil
      walk_expr(s.c, fs) if s.c != nil
      walk_stmt(s.d, fs)
    elsif k == :while
      walk_expr(s.a, sc)
      walk_stmt(s.b, sc)
    elsif k == :do_while
      walk_stmt(s.a, sc)
      walk_expr(s.b, sc)
    elsif k == :return
      walk_expr(s.a, sc) if s.a != nil
    elsif k == :break || k == :continue
      nil
    elsif k == :throw
      walk_expr(s.a, sc)
    elsif k == :try
      walk_stmt(s.a, sc)
      if s.c != nil
        cs = map_scope(s, new_scope(:catch, sc, f, s))
        if s.b != nil
          if s.b.kind != :ident
            f.fail("destructuring")
          else
            cs.declare(self, s.b.str, :catch)
        bs = block_scope(cs, s.c, s.c.list)
        walk_stmts(s.c.list, bs)
      f.fail("finally") if s.d != nil
    elsif k == :switch
      walk_expr(s.a, sc)
      all = []
      i = 0
      while i < s.list.size
        all = all + s.list[i].list
        i += 1
      bs = block_scope(sc, s, all)
      i = 0
      while i < s.list.size
        c = s.list[i]
        walk_expr(c.a, bs) if c.a != nil
        walk_stmts(c.list, bs)
        i += 1
    elsif k == :labeled
      walk_stmt(s.a, sc)
    elsif k == :with
      f.dynamic = true
      f.fail("with")
      walk_expr(s.a, sc)
      walk_stmt(s.b, sc)
    elsif k == :for_in || k == :for_of
      f.fail(k.to_s)
    else
      f.fail(k.to_s)
    nil

  # A block's own scope, when it declares lexical bindings (else the enclosing one).
  # Function declarations in blocks are block-scoped in strict code, and in sloppy code
  # when no var of the same name was hoisted (Annex B did not apply).
  -> block_scope(sc, node, stmts)
    has = false
    i = 0
    while i < stmts.size
      s = stmts[i]
      has = true if (s.kind == :var_decl && s.str != "var") || s.kind == :class_decl || (s.kind == :function_decl && block_function?(s, sc))
      i += 1
    return sc if !has
    bs = map_scope(node, new_scope(:block, sc, sc.func, node))
    hoist_block(bs, stmts, false)
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :function_decl && s.str != nil && block_function?(s, sc)
        b = bs.declare(self, s.str, :function)
        b.writes += 1
      i += 1
    bs

  -> block_function?(s, sc)
    return false if s.str == nil
    return true if sc.func.strict
    b = sc.func.scope.names[s.str]
    b == nil || (b.kind != :var && b.kind != :global)

  -> walk_exprs(list, sc)
    i = 0
    while i < list.size
      walk_expr(list[i], sc) if list[i] != nil
      i += 1
    nil

  -> walk_expr(e, sc)
    return nil if e == nil
    f = sc.func
    k = e.kind
    if k == :ident
      note_read(resolve(e.str, sc), sc, e.pos, false)
    elsif k == :num || k == :string || k == :null || k == :true || k == :false
      nil
    elsif k == :this
      note_this(sc)
    elsif k == :function || k == :arrow
      walk_function(e, sc, nil)
    elsif k == :call
      c = e.a
      f.fail("optional call") if e.has?(F_OPTIONAL)
      if c.kind == :ident
        if c.str == "eval"
          f.dynamic = true
          f.fail("eval")
        note_read(resolve(c.str, sc), sc, c.pos, true)
      elsif (c.kind == :function || c.kind == :arrow) && !c.has?(F_ASYNC) && !c.has?(F_GENERATOR)
        walk_function(c, sc, nil)
        jf = fn_of(c)
        jf.fclass = :iife if jf != nil
      else
        walk_expr(c, sc)
      walk_args(e.list, sc)
    elsif k == :new
      walk_expr(e.a, sc)
      walk_args(e.list, sc)
    elsif k == :member
      f.fail("optional chain") if e.has?(F_OPTIONAL)
      walk_expr(e.a, sc)
      if e.has?(F_COMPUTED)
        walk_expr(e.b, sc)
      elsif e.b.kind == :private_name
        f.fail("private name")
    elsif k == :chain
      f.fail("optional chain")
      walk_expr(e.a, sc)
    elsif k == :unary
      if e.str == "typeof" && e.a.kind == :ident
        note_read(resolve(e.a.str, sc), sc, e.a.pos, false)
      elsif e.str == "delete" && e.a.kind == :ident
        f.fail("delete of a binding")
      else
        walk_expr(e.a, sc)
    elsif k == :update
      walk_target(e.a, sc)
    elsif k == :binary || k == :logical
      walk_expr(e.a, sc)
      walk_expr(e.b, sc)
    elsif k == :assign
      if e.a.kind == :ident
        b = resolve(e.a.str, sc)
        note_read(b, sc, e.a.pos, false) if e.str != "="
        note_fn_value(e.b, nil)
        walk_expr(e.b, sc)
        note_write(b, sc, e.a.pos)
      elsif e.a.kind == :member
        walk_expr(e.a, sc)
        walk_expr(e.b, sc)
      else
        f.fail("destructuring assignment")
    elsif k == :cond
      walk_expr(e.a, sc)
      walk_expr(e.b, sc)
      walk_expr(e.c, sc)
    elsif k == :seq
      walk_exprs(e.list, sc)
    elsif k == :array
      i = 0
      while i < e.list.size
        x = e.list[i]
        if x != nil
          f.fail("spread") if x.kind == :spread
          walk_expr(x, sc)
        i += 1
    elsif k == :object
      i = 0
      while i < e.list.size
        p = e.list[i]
        if p.kind != :prop || p.str != "init" || p.has?(F_COMPUTED) || p.has?(F_METHOD)
          f.fail("object literal " + (p.kind == :prop ? p.str : p.kind.to_s))
          walk_expr(p.a, sc) if p.kind == :prop && p.has?(F_COMPUTED)
        walk_expr(p.kind == :prop ? p.b : p.a, sc)
        i += 1
    elsif k == :template
      f.fail("template")
      walk_exprs(e.a, sc)
    else
      f.fail(k.to_s)
      walk_expr(e.a, sc) if e.a.is_a?(JsNode)
      walk_expr(e.b, sc) if e.b.is_a?(JsNode)
    nil

  -> walk_args(list, sc)
    i = 0
    while i < list.size
      a = list[i]
      sc.func.fail("spread") if a.kind == :spread
      walk_expr(a, sc)
      i += 1
    nil

  -> walk_target(t, sc)
    if t.kind == :ident
      b = resolve(t.str, sc)
      note_read(b, sc, t.pos, false)
      note_write(b, sc, t.pos)
    else
      walk_expr(t, sc)
    nil

  # ---- functions ----

  -> fn_of(node)
    @fnmap[node_key(node)]

  -> node_key(node)
    node.kind.to_s + ":" + node.pos.to_s + ":" + node.fin.to_s

  # The scope the analysis made for a block, for, catch or switch node (else sc).
  -> scope_for(node, sc)
    s = @scopemap[node_key(node)]
    s == nil ? sc : s

  -> map_scope(node, s)
    @scopemap[node_key(node)] = s
    s

  -> walk_function(n, sc, binding)
    pf = sc.func
    jf = JaFunc.new(n, pf, @funcs.size)
    @funcs.push(jf)
    @fnmap[node_key(n)] = jf
    pf.inner.push(jf)
    jf.def_scope = sc
    jf.binding = binding
    jf.binding.fnode = jf if binding != nil
    jf.arrow = n.kind == :arrow
    jf.strict = pf.strict || n.has?(F_STRICT)
    jf.name = n.str == nil ? "" : n.str
    jf.fail("async") if n.has?(F_ASYNC)
    jf.fail("generator") if n.has?(F_GENERATOR)
    fs = new_scope(:function, sc, jf, n)
    jf.scope = fs
    if n.kind == :function && n.str != nil && binding == nil
      jf.self_binding = fs.declare(self, n.str, :self)
    i = 0
    while i < n.list.size
      p = n.list[i]
      if p.kind == :ident
        b = fs.declare(self, p.str, :param)
        jf.params.push(b)
      else
        jf.fail("parameter " + p.kind.to_s)
      i += 1
    jf.nparams = jf.params.size
    if !jf.arrow && (n.has?(F_USES_ARGS) || n.has?(F_HAS_EVAL))
      jf.uses_args = true
      jf.fail("arguments")
    jf.dynamic = true if n.has?(F_HAS_EVAL)
    if jf.arrow && n.has?(F_EXPR_BODY)
      jf.body_scope = fs
      walk_expr(n.b, fs)
    else
      body = n.b
      if body == nil
        jf.fail("lazy body")
        return nil
      hoist_body(jf, fs, body, true)
      jf.body_scope = fs
      walk_stmts(body, fs)
    nil

  # A function expression assigned to a binding: remember it (call-only candidates).
  -> note_fn_value(e, b)
    nil

  # ---- references ----

  # The binding name refers to from sc (declaring an implicit global when unresolved).
  -> resolve(name, sc)
    s = sc
    while s != nil
      b = s.names[name]
      return b if b != nil
      s = s.parent
    gs = @funcs[0].scope
    b = gs.names[name]
    if b == nil
      b = gs.declare(self, name, :global)
    b

  -> note_read(b, sc, pos, callee)
    if b.kind == :self && (!callee || sc.func != b.scope.func)
      sc.func.fail("named function expression used as a value")
    b.reads += 1
    if callee
      b.callee_uses += 1
    else
      b.value_uses += 1
    note_capture(b, sc)
    if (b.kind == :let || b.kind == :const || b.kind == :class) && pos < b.decl_pos && b.scope.func == sc.func
      b.early_read = true
    nil

  -> note_write(b, sc, pos)
    b.writes += 1
    note_capture(b, sc)
    nil

  -> note_capture(b, sc)
    return nil if b.global?
    f = sc.func
    df = b.scope.func
    if f != df
      b.captured = true
      g = f
      while g != nil && g != df
        g.free[b.id] = b
        g = g.parent
    nil

  # `this` inside an arrow is the enclosing function's: a captured binding.
  -> note_this(sc)
    f = sc.func
    g = f
    while g.arrow
      g = g.parent
    if g.script
      f.uses_this = true
      return nil
    g.uses_this = true
    if g.this_binding == nil
      g.this_binding = g.scope.declare(self, "this", :this)
      g.this_binding.writes = 1
    if f != g
      note_read(g.this_binding, sc, 0, false)
    nil

  # ---- layout ----

  -> finish
    # function value classes
    i = 1
    while i < @funcs.size
      f = @funcs[i]
      if f.fclass != :iife
        b = f.binding
        if b != nil && !b.global? && b.writes == 1 && b.value_uses == 0 && b.kind == :function
          f.fclass = :call_only
        else
          f.fclass = :escaping
      if f.self_binding != nil && f.self_binding.value_uses > 0
        f.fclass = :escaping if f.fclass == :call_only
      # one captured binding that never changes after its initializer: stored by value
      if f.free.size == 1 && !inner_captures?(f)
        fb = f.free.values[0]
        if single_ok?(fb)
          f.single = fb
      i += 1
    # environment slots: captured bindings that some non-single function needs
    i = 1
    while i < @funcs.size
      f = @funcs[i]
      if f.single == nil
        f.free.values.each ->(b)
          if b.slot < 0
            b.slot = b.scope.env_count
            b.scope.env_count = b.scope.env_count + 1
      i += 1
    nil

  -> inner_captures?(f)
    i = 0
    while i < f.inner.size
      return true if f.inner[i].free.size > 0
      i += 1
    false

  -> single_ok?(b)
    return true if b.kind == :param && b.writes == 0
    return true if b.kind == :this
    if b.kind == :const || b.kind == :let || b.kind == :var
      return b.writes == 1 && !b.early_read && b.kind != :var
    false

  # Statistics for the corpus tool: functions per class and scopes without environments.
  -> stats
    st = {funcs: @funcs.size - 1, call_only: 0, iife: 0, escaping: 0, no_captures: 0, single: 0, unsupported: 0, dynamic: 0}
    i = 1
    while i < @funcs.size
      f = @funcs[i]
      st[f.fclass] = st[f.fclass] + 1
      st[:no_captures] = st[:no_captures] + 1 if f.free.size == 0
      st[:single] = st[:single] + 1 if f.single != nil
      st[:unsupported] = st[:unsupported] + 1 if f.unsupported != nil
      st[:dynamic] = st[:dynamic] + 1 if f.dynamic
      i += 1
    st
