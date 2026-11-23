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
  rw :name, :kind, :scope, :slot, :local, :captured, :writes, :reads, :value_uses, :callee_uses, :fnode, :tdz, :decl_pos, :early_read, :init_before_fns, :id, :lidx, :cell, :decl_const

  -> new(@name, @kind, @scope)
    @slot = -1
    @lidx = -1
    @cell = nil
    @decl_const = false
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

# A resolved identifier occurrence: the binding and the scope it is written in.
+ JaRef
  rw :binding, :scope, :hops
  -> new(@binding, @scope)
    @hops = nil

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
  rw :node, :parent, :index, :scope, :strict, :arrow, :uses_this, :uses_args, :dynamic, :free, :fclass, :single, :inner, :binding, :self_binding, :unsupported, :name, :def_scope, :nparams, :params, :this_binding, :body_scope, :script, :nlocals, :code, :scopes, :analysis, :in_if, :single_ref, :annexb, :unsupported0, :simple, :args_binding, :mapped_args, :param_nodes, :param_copies, :method_kind, :is_static, :home, :class_ctor, :derived, :default_ctor, :field_init, :class_node, :nt_binding, :fo_binding

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
    @nlocals = 0
    @code = nil
    @scopes = []
    @analysis = nil
    @in_if = false
    @single_ref = nil
    @annexb = nil
    @unsupported0 = nil
    @simple = true
    @args_binding = nil
    @mapped_args = false
    @param_nodes = []
    @param_copies = []
    @method_kind = nil
    @is_static = false
    @home = false
    @class_ctor = false
    @derived = false
    @default_ctor = false
    @field_init = false
    @class_node = nil
    @nt_binding = nil
    @fo_binding = nil

  # What tier 1 cannot compile yet (the function stays in tier 0).
  -> fail(why)
    @unsupported = why if @unsupported == nil
    nil

  # What neither tier can run yet.
  -> fail0(why)
    @unsupported0 = why if @unsupported0 == nil
    fail(why)

+ JaAnalysis
  rw :program, :funcs, :strict, :bind_count, :scope_count, :unsupported_counts, :src, :eval_mode, :url

  -> new(@program, @strict)
    @src = nil
    @url = nil
    @eval_mode = false
    @funcs = []
    @bind_count = 0
    @scope_count = 0
    @unsupported_counts = {}
    @fnmap = {}
    @scopemap = {}

  # Direct eval code (tier 0): the program as an arrow-like function defined at the
  # caller's scope outer (another analysis, already finished), so the code reads and
  # writes the caller's bindings and its this. Its own var and function declarations stay
  # its own (a sloppy direct eval would add them to the caller's variables).
  -> run_direct(outer)
    f = JaFunc.new(@program, outer.func, 0)
    f.analysis = self
    f.arrow = true
    f.strict = @strict || @program.has?(F_STRICT)
    f.def_scope = outer
    @funcs.push(f)
    sc = new_scope(:function, outer, f, @program)
    f.scope = sc
    f.body_scope = sc
    list = @program.list
    if f.strict
      hoist_body(f, sc, list, true)
    else
      # sloppy: a var or function the caller's variable scope already has is that binding;
      # one the global scope gets is a global; a lexical one in between is an error
      vs = outer
      while vs.parent != nil && vs.kind != :function && vs.kind != :body && vs.kind != :script
        vs = vs.parent
      names = var_names(list, [], false, true)
      list.each ->(s) names.push(s.str) if s.kind == :function_decl && s.str != nil && !names.include?(s.str)
      names.each ->(nm)
        s = outer
        found = nil
        while s != nil && found == nil
          found = s.names[nm]
          if found == nil
            break if s == vs
            s = s.parent
        if found != nil && (found.kind == :let || found.kind == :const || found.kind == :class)
          f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
        elsif found == nil
          sc.declare(self, nm, vs.kind == :script ? :global : :var)
      hoist_block(sc, list.select(->(s) s.kind != :function_decl), true)
    walk_stmts(list, sc)
    finish()
    f

  -> new_scope(kind, parent, func, node)
    s = JaScope.new(kind, parent, func, node)
    @scope_count += 1
    s.id = @scope_count
    func.scopes.push(s)
    s

  -> run
    f = JaFunc.new(@program, nil, 0)
    f.analysis = self
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

  # var-declared names of a statement list, not entering functions. (Sloppy-mode
  # function declarations in nested blocks are added by annexb_names.)
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
    # strict eval code keeps its vars and functions to itself
    gvars = sc.kind == :script && !(@eval_mode && f.strict)
    i = 0
    while i < vn.size
      sc.declare(self, vn[i], gvars ? :global : :var)
      i += 1
    if !f.strict
      pnames = []
      f.scope.order.each ->(b) pnames.push(b.name) if b.kind == :param
      an = annexb_names(stmts, lexical_names(stmts) + pnames, [], true)
      i = 0
      while i < an.size
        b = sc.names[an[i]]
        sc.declare(self, an[i], gvars ? :global : :var) if b == nil
        i += 1
    hoist_block(sc, stmts, top)

  # Annex B.3.3: a sloppy-mode function declaration in a nested block also gets a var
  # binding in the function, unless a var there would clash with a lexical declaration
  # of an enclosing block (or the function body) or name a parameter. lex holds those
  # names on the way down.
  -> annexb_names(stmts, lex, out, top)
    i = 0
    inner = lex + lexical_names(stmts)
    if !top
      j = 0
      while j < stmts.size
        s = stmts[j]
        if s.kind == :function_decl && s.str != nil && !lex.include?(s.str)
          out.push(s.str) if !out.include?(s.str)
        j += 1
      # this block's own functions are lexical in it: they shadow for nested blocks
      j = 0
      while j < stmts.size
        inner.push(stmts[j].str) if stmts[j].kind == :function_decl && stmts[j].str != nil
        j += 1
    while i < stmts.size
      annexb_stmt(stmts[i], inner, out)
      i += 1
    out

  -> annexb_stmt(s, lex, out)
    return nil if s == nil
    k = s.kind
    if k == :block
      annexb_names(s.list, lex, out, false)
    elsif k == :if
      annexb_body(s.b, lex, out)
      annexb_body(s.c, lex, out)
    elsif k == :for || k == :for_in || k == :for_of
      l2 = lex
      if s.a != nil && s.a.kind == :var_decl && s.a.str != "var"
        l2 = lex + lexical_names([s.a])
      annexb_body(s.d, l2, out)
    elsif k == :while
      annexb_body(s.b, lex, out)
    elsif k == :do_while
      annexb_body(s.a, lex, out)
    elsif k == :try
      annexb_stmt(s.a, lex, out)
      if s.c != nil
        l2 = lex
        l2 = lex + bound_names(s.b, []) if s.b != nil && s.b.kind != :ident
        annexb_stmt(s.c, l2, out)
      annexb_stmt(s.d, lex, out)
    elsif k == :switch
      all = []
      s.list.each ->(c) all = all + c.list
      annexb_names(all, lex, out, false)
    elsif k == :labeled
      annexb_body(s.a, lex, out)
    nil

  # A statement in a body position (if branch, loop body): a function declaration there
  # behaves as if wrapped in a block.
  -> annexb_body(s, lex, out)
    return nil if s == nil
    if s.kind == :function_decl
      annexb_names([s], lex, out, false)
    else
      annexb_stmt(s, lex, out)
    nil

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
    # eval code's top-level let, const and class are its own (a fresh declarative scope)
    script = sc.kind == :script && !@eval_mode
    gfuns = sc.kind == :script && !(@eval_mode && sc.func.strict)
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
            b.decl_const = s.str == "const"
            q += 1
          j += 1
      elsif s.kind == :class_decl && s.str != nil
        b = sc.declare(self, s.str, script ? :lexical : :class)
        b.decl_pos = s.fin
      elsif s.kind == :function_decl && s.str != nil
        b = sc.declare(self, s.str, gfuns ? :global : :function)
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
          walk_expr(d.b, sc) if d.b != nil
          walk_pattern(d.a, sc, true)
        else
          b = ref(d.a, sc)
          if d.b != nil
            note_fn_value(d.b, b)
            walk_expr(d.b, sc)
            name_fn(d.b, d.a.str)
            note_write(b, sc, d.a.pos)
          elsif s.str != "var"
            note_write(b, sc, d.a.pos)
        i += 1
    elsif k == :function_decl
      b = resolve(s.str, sc)
      walk_function(s, sc, b)
      if b.kind == :function && b.scope != sc.func.scope
        av = annexb_var(s.str, b.scope)
        if av != nil
          s.x.annexb = av
          note_write(av, sc, s.pos)
          b.value_uses += 1
    elsif k == :class_decl
      cb = resolve(s.str, sc)
      s.c = JaRef.new(cb, sc)
      walk_class(s, sc, cb)
    elsif k == :block
      bs = block_scope(sc, s, s.list)
      walk_stmts(s.list, bs)
    elsif k == :empty || k == :debugger
      nil
    elsif k == :if
      walk_expr(s.a, sc)
      walk_stmt(s.b, sc)
      walk_stmt(s.c, sc)
      s.b.x.in_if = true if s.b.kind == :function_decl && s.b.x.is_a?(JaFunc)
      s.c.x.in_if = true if s.c != nil && s.c.kind == :function_decl && s.c.x.is_a?(JaFunc)
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
          names = bound_names(s.b, [])
          q = 0
          while q < names.size
            cs.declare(self, names[q], :catch)
            q += 1
          if s.b.kind == :ident
            ref(s.b, cs)
          else
            walk_pattern(s.b, cs, true)
        bs = block_scope(cs, s.c, s.c.list)
        walk_stmts(s.c.list, bs)
      if s.d != nil
        bd = block_scope(sc, s.d, s.d.list)
        walk_stmts(s.d.list, bd)
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
      f.fail0("with")
      walk_expr(s.a, sc)
      walk_stmt(s.b, sc)
    elsif k == :for_in || k == :for_of
      f.fail("for await") if s.has?(F_AWAIT)
      fs = sc
      a = s.a
      if a.kind == :var_decl && a.str != "var"
        fs = map_scope(s, new_scope(:for, sc, f, s))
        hoist_block(fs, [a], false)
        fs.per_iter = true
      # the right side sees the head's let bindings in their dead zone (spec: TDZ scope)
      walk_expr(s.b, fs)
      if a.kind == :var_decl
        walk_pattern(a.list[0].a, fs, true)
        walk_expr(a.list[0].b, fs) if a.list[0].b != nil
      else
        walk_pattern(a, fs, false)
      walk_stmt(s.d, fs)
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

  # The var binding an Annex B function declaration in block scope bs copies into.
  -> annexb_var(name, bs)
    return nil if bs.func.strict
    fs = bs.func.scope
    v = fs.names[name]
    return nil if v == nil || (v.kind != :var && v.kind != :global)
    # a lexical declaration between the block and the function shadows: no copy
    s = bs.parent
    while s != nil && s != fs
      b = s.names[name]
      return nil if b != nil
      s = s.parent
    v

  # Function declarations in blocks are block-scoped (strict and sloppy alike); a sloppy
  # one whose name Annex B also made a var gets copied into it when evaluated.
  -> block_function?(s, sc)
    s.str != nil

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
      note_read(ref(e, sc), sc, e.pos, false)
    elsif k == :num || k == :string || k == :null || k == :true || k == :false || k == :bigint
      nil
    elsif k == :this
      e.x = JaRef.new(nil, sc)
      note_this(sc)
    elsif k == :function || k == :arrow
      walk_function(e, sc, nil)
    elsif k == :call
      c = e.a
      # super(...) passes new.target on (an arrow reads it from the constructor)
      note_special(sc, :nt) if c.kind == :super
      if c.kind == :ident
        cb = ref(c, sc)
        if c.str == "eval" && cb.global?
          # a direct eval (when eval is still %eval% at run time): its code sees every
          # binding in scope, so this function and those around it keep all of theirs in
          # environments (finish), and tier 0 analyses the code below sc (run_direct)
          f.fail("eval")
          e.d = sc
          g = f
          while g != nil
            g.dynamic = true
            g = g.parent
          g = f
          while g.arrow
            g = g.parent
          if !g.script && g.this_binding == nil
            g.this_binding = g.scope.declare(self, "this", :this)
            g.this_binding.writes = 1
        note_read(cb, sc, c.pos, !e.has?(F_OPTIONAL))
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
      walk_expr(e.a, sc)
      if e.has?(F_COMPUTED)
        walk_expr(e.b, sc)
      elsif e.b.kind == :private_name
        priv_ref(e.b, sc)
    elsif k == :chain
      walk_expr(e.a, sc)
    elsif k == :unary
      if e.str == "typeof" && e.a.kind == :ident
        note_read(ref(e.a, sc), sc, e.a.pos, false)
      elsif e.str == "delete" && e.a.kind == :ident
        f.fail("delete of a binding")
      else
        walk_expr(e.a, sc)
    elsif k == :update
      walk_target(e.a, sc)
    elsif k == :binary || k == :logical
      if e.a.kind == :private_name
        priv_ref(e.a, sc)
      else
        walk_expr(e.a, sc)
      walk_expr(e.b, sc)
    elsif k == :assign
      if e.a.kind == :ident
        b = ref(e.a, sc)
        note_read(b, sc, e.a.pos, false) if e.str != "="
        note_fn_value(e.b, nil)
        walk_expr(e.b, sc)
        name_fn(e.b, e.a.str) if e.str == "=" || e.str == "&&=" || e.str == "||=" || e.str == "??="
        note_write(b, sc, e.a.pos)
      elsif e.a.kind == :member
        walk_expr(e.a, sc)
        walk_expr(e.b, sc)
      else
        walk_expr(e.b, sc)
        walk_pattern(e.a, sc, false)
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
          if x.kind == :spread
            walk_expr(x.a, sc)
          else
            walk_expr(x, sc)
        i += 1
    elsif k == :object
      i = 0
      while i < e.list.size
        p = e.list[i]
        if p.kind != :prop || p.str != "init" || p.has?(F_COMPUTED) || p.has?(F_METHOD)
          walk_expr(p.a, sc) if p.kind == :prop && p.has?(F_COMPUTED)
        walk_expr(p.kind == :prop ? p.b : p.a, sc)
        # methods and accessors of a literal are not constructors
        if p.kind == :prop && (p.has?(F_METHOD) || p.str == "get" || p.str == "set") && p.b.x.is_a?(JaFunc)
          p.b.x.method_kind = p.has?(F_METHOD) ? "method" : p.str
        if p.kind == :prop && !p.has?(F_COMPUTED) && p.str == "init"
          kn = p.a.kind == :num ? nil : p.a.str
          name_fn(p.b, kn) if kn != nil && kn != "__proto__"
        i += 1
    elsif k == :template
      walk_exprs(e.a, sc)
    elsif k == :class
      walk_class(e, sc, nil)
    elsif k == :super
      # super.x / super.m() / super(...): the home object and this of the enclosing method
      e.x = JaRef.new(nil, sc)
      note_special(sc, :fo)
      note_this(sc)
    elsif k == :tagged_template
      walk_expr(e.a, sc)
      walk_exprs(e.b.a, sc)
    elsif k == :spread
      walk_expr(e.a, sc)
    elsif k == :yield || k == :await
      walk_expr(e.a, sc) if e.a != nil
    elsif k == :regex
      nil
    elsif k == :meta_property
      if e.str == "new.target"
        e.x = JaRef.new(nil, sc)
        note_special(sc, :nt)
      else
        f.fail0(e.str)
    else
      f.fail(k.to_s)
      walk_expr(e.a, sc) if e.a.is_a?(JsNode)
      walk_expr(e.b, sc) if e.b.is_a?(JsNode)
    nil

  -> walk_args(list, sc)
    i = 0
    while i < list.size
      a = list[i]
      if a.kind == :spread
        walk_expr(a.a, sc)
      else
        walk_expr(a, sc)
      i += 1
    nil

  -> walk_target(t, sc)
    if t.kind == :ident
      b = ref(t, sc)
      note_read(b, sc, t.pos, false)
      note_write(b, sc, t.pos)
    else
      walk_expr(t, sc)
    nil

  # ---- functions ----

  -> fn_of(node)
    node.x

  -> node_key(node)
    node.kind.to_s + ":" + node.pos.to_s + ":" + node.fin.to_s

  # The scope the analysis made for a block, for, catch or switch node (else sc).
  -> scope_for(node, sc)
    s = node.x
    s.is_a?(JaScope) ? s : sc

  -> map_scope(node, s)
    node.x = s
    s

  -> walk_function(n, sc, binding)
    pf = sc.func
    jf = JaFunc.new(n, pf, @funcs.size)
    jf.analysis = self
    @funcs.push(jf)
    n.x = jf
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
    # parameters: plain names, or patterns with defaults and a rest element (non-simple)
    jf.param_nodes = n.list
    nlen = -1
    i = 0
    while i < n.list.size
      p = n.list[i]
      if p.kind == :ident
        b = fs.declare(self, p.str, :param)
        jf.params.push(b)
        p.x = JaRef.new(b, fs)
      else
        jf.simple = false
        nlen = i if nlen < 0 && (p.kind == :assign_pattern || p.kind == :rest)
        names = bound_names(p, [])
        q = 0
        while q < names.size
          fs.declare(self, names[q], :param)
          q += 1
      i += 1
    jf.nparams = nlen < 0 ? n.list.size : nlen
    if !jf.arrow && (n.has?(F_USES_ARGS) || n.has?(F_HAS_EVAL))
      jf.uses_args = true
      if fs.names["arguments"] == nil
        jf.args_binding = fs.declare(self, "arguments", :arguments)
        jf.args_binding.writes = 1
        jf.mapped_args = !jf.strict && jf.simple
      jf.fail("mapped arguments") if jf.mapped_args
    if n.has?(F_HAS_EVAL)
      jf.dynamic = true
    # defaults and patterns are evaluated in the parameter scope
    i = 0
    while i < n.list.size
      walk_pattern(n.list[i], fs, true) if n.list[i].kind != :ident
      i += 1
    if jf.arrow && n.has?(F_EXPR_BODY)
      jf.body_scope = fs
      walk_expr(n.b, fs)
    else
      body = n.b
      if body == nil
        jf.fail0("lazy body")
        return nil
      # a non-simple parameter list gives the body's declarations their own scope, where a
      # var named like a parameter starts with its value (FunctionDeclarationInstantiation)
      bs = fs
      if !jf.simple
        bs = new_scope(:body, fs, jf, n)
      hoist_body(jf, bs, body, true)
      if bs != fs
        bs.order.each ->(b)
          pb = fs.names[b.name]
          jf.param_copies.push([pb, b]) if pb != nil && pb.kind == :param && b.kind == :var
      jf.body_scope = bs
      walk_stmts(body, bs)
    nil

  # A binding or assignment pattern: annotate its identifiers, walk its defaults and
  # computed keys. decl: the identifiers are declarations (already declared in sc).
  -> walk_pattern(p, sc, decl)
    return nil if p == nil
    k = p.kind
    if k == :ident
      b = ref(p, sc)
      note_write(b, sc, p.pos)
    elsif k == :assign_pattern
      walk_pattern(p.a, sc, decl)
      walk_expr(p.b, sc)
      name_fn(p.b, p.a.str) if p.a.kind == :ident
    elsif k == :rest
      walk_pattern(p.a, sc, decl)
    elsif k == :array_pattern
      i = 0
      while i < p.list.size
        walk_pattern(p.list[i], sc, decl) if p.list[i] != nil
        i += 1
    elsif k == :object_pattern
      i = 0
      while i < p.list.size
        e = p.list[i]
        if e.kind == :rest
          walk_pattern(e.a, sc, decl)
        else
          walk_expr(e.a, sc) if e.has?(F_COMPUTED)
          walk_pattern(e.b, sc, decl)
        i += 1
    elsif k == :member
      walk_expr(p, sc)
    else
      walk_expr(p, sc)
    nil

  # NamedEvaluation (§8.4.5): an anonymous function or arrow takes the name it is bound to.
  -> name_fn(e, name)
    return nil if e == nil || name == nil
    k = e.kind
    if (k == :function || k == :arrow) && e.str == nil && e.x.is_a?(JaFunc)
      e.x.name = name
    nil

  # A function expression assigned to a binding.
  -> note_fn_value(e, b)
    nil

  # ---- references ----

  # Resolve an identifier node and annotate it with its JaRef.
  -> ref(node, sc)
    b = resolve(node.str, sc)
    node.x = JaRef.new(b, sc)
    b

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

  # ---- classes ----

  # A class: its scope holds the inner name binding and one binding per private name
  # ("#x", a fresh JS:PrivateName per evaluation). Methods are functions defined in that
  # scope; field initializers and static blocks become synthetic methods too, so `this`
  # and closures work as in any function.
  -> walk_class(n, sc, outer)
    f = sc.func
    cs = map_scope(n, new_scope(:class, sc, f, n))
    if n.str != nil
      inner = cs.declare(self, n.str, :class_inner)
      inner.writes = 1
    i = 0
    while i < n.list.size
      m = n.list[i]
      if (m.kind == :method_def || m.kind == :field_def) && m.a != nil && m.a.kind == :private_name
        pb = cs.names["#" + m.a.str]
        if pb == nil
          pb = cs.declare(self, "#" + m.a.str, :private)
          pb.writes = 1
        m.a.x = JaRef.new(pb, cs)
      i += 1
    walk_expr(n.a, cs) if n.a != nil
    ctor = nil
    i = 0
    while i < n.list.size
      m = n.list[i]
      if m.kind == :method_def
        walk_expr(m.a, cs) if m.has?(F_COMPUTED)
        walk_function(m.b, cs, nil)
        jf = m.b.x
        jf.method_kind = m.str
        jf.is_static = m.has?(F_STATIC)
        jf.home = true
        jf.class_node = n
        if m.str == "constructor"
          jf.class_ctor = true
          jf.derived = n.a != nil
          jf.name = n.str == nil ? "" : n.str
          ctor = jf
        elsif !m.has?(F_COMPUTED)
          kn = m.a.kind == :private_name ? "#" + m.a.str : (m.a.kind == :num ? nil : m.a.str)
          jf.name = (m.str == "get" || m.str == "set") ? m.str + " " + kn.to_s : kn.to_s if kn != nil
      elsif m.kind == :field_def
        walk_expr(m.a, cs) if m.has?(F_COMPUTED)
        if m.b != nil
          body = [JsNode.new(:return, m.b.pos, m.b.fin, nil, m.b, nil, nil, nil, 0)]
          fn = JsNode.new(:function, m.pos, m.fin, nil, nil, body, nil, [], F_STRICT | F_METHOD)
          walk_function(fn, cs, nil)
          fn.x.field_init = true
          fn.x.home = true
          fn.x.is_static = m.has?(F_STATIC)
          m.x = fn.x
          name_fn(m.b, m.a.kind == :private_name ? "#" + m.a.str : m.a.str) if !m.has?(F_COMPUTED) && m.a.kind != :num
      elsif m.kind == :static_block
        fn = JsNode.new(:function, m.pos, m.fin, nil, nil, m.list, nil, [], F_STRICT | F_METHOD)
        walk_function(fn, cs, nil)
        fn.x.field_init = true
        fn.x.home = true
        fn.x.is_static = true
        m.x = fn.x
      i += 1
    if ctor == nil
      # the default constructor (§15.7.14 step 10)
      fn = JsNode.new(:function, n.pos, n.fin, nil, nil, [], nil, [], F_STRICT | F_METHOD)
      walk_function(fn, cs, nil)
      ctor = fn.x
      ctor.class_ctor = true
      ctor.default_ctor = true
      ctor.derived = n.a != nil
      ctor.home = true
      ctor.name = n.str == nil ? "" : n.str
    ctor.class_node = n
    n.d = ctor.node
    note_write(outer, sc, n.pos) if outer != nil
    nil

  # A private name reference (#x): annotate it with its binding in the class scope.
  -> priv_ref(node, sc)
    b = resolve("#" + node.str, sc)
    sc.func.fail0("undeclared private name #" + node.str) if b.kind != :private
    node.x = JaRef.new(b, sc)
    note_read(b, sc, node.pos, false)
    b

  # new.target (:nt) or the running method's own object (:fo, for super) seen from an
  # arrow: a binding of the enclosing function, like `this`.
  -> note_special(sc, which)
    f = sc.func
    g = f
    while g.arrow
      g = g.parent
    return nil if g.script
    if which == :nt
      if g.nt_binding == nil
        g.nt_binding = g.scope.declare(self, "new.target", :newtarget)
        g.nt_binding.writes = 1
      note_read(g.nt_binding, sc, 0, false) if f != g
    else
      if g.fo_binding == nil
        g.fo_binding = g.scope.declare(self, "%home", :fnobj)
        g.fo_binding.writes = 1
      note_read(g.fo_binding, sc, 0, false) if f != g
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
      # a named function expression that reads its own name as a value (or from a nested
      # function) needs its object, even as an IIFE
      sb = f.self_binding
      if sb != nil && (sb.value_uses > 0 || sb.captured)
        f.fclass = :escaping if f.fclass == :call_only || f.fclass == :iife
      # one captured binding that never changes after its initializer: stored by value
      if f.free.size == 1 && !inner_captures?(f) && !f.dynamic
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
    # a function containing a direct eval (or one around it): every binding in an
    # environment, where the eval'd code can reach it
    i = 0
    while i < @funcs.size
      f = @funcs[i]
      if f.dynamic && !f.script
        f.scopes.each ->(s)
          s.order.each ->(b)
            if !b.global? && b.slot < 0
              b.slot = s.env_count
              s.env_count = s.env_count + 1
      i += 1
    # a sloppy function with a mapped arguments object aliases its parameters through it:
    # they live in the environment so the object stays valid after the call returns
    i = 1
    while i < @funcs.size
      f = @funcs[i]
      if f.mapped_args
        f.params.each ->(b)
          if b.slot < 0
            b.slot = b.scope.env_count
            b.scope.env_count = b.scope.env_count + 1
      i += 1
    # local slots (tier 0's activation array): every binding not in an environment
    i = 0
    while i < @funcs.size
      f = @funcs[i]
      n = 0
      j = 0
      while j < f.scopes.size
        sc = f.scopes[j]
        q = 0
        while q < sc.order.size
          b = sc.order[q]
          if !b.global? && b.slot < 0 && b.kind != :this
            b.lidx = n
            n += 1
          q += 1
        j += 1
      f.nlocals = n
      i += 1
    nil

  # Environment hops from scope sc to the environment of scope target (an ancestor
  # with an environment), as tier 0 walks them: through the environment-bearing scopes
  # of sc's function, then from the function's fe along its definition scopes.
  -> env_hops(sc, target)
    h = 0
    s = sc
    f = sc.func
    while s != nil && s.func == f
      return h if s == target
      h += 1 if s.has_env?
      s = s.parent
    s = f.def_scope
    while s != nil
      if s.has_env?
        return h if s == target
        h += 1
      s = s.parent
    -1

  -> inner_captures?(f)
    i = 0
    while i < f.inner.size
      return true if f.inner[i].free.size > 0
      i += 1
    false

  -> single_ok?(b)
    return false if b.kind == :param && b.scope.func.mapped_args
    return true if b.kind == :param && b.writes == 0
    # a derived constructor's this changes when super() returns
    return !b.scope.func.derived if b.kind == :this
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
