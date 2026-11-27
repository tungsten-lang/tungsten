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

use parser

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
  rw :kind, :parent, :func, :names, :env_count, :id, :node, :per_iter, :order, :is_with, :has_dyn, :tdz_bindings, :has_dispose

  -> new(@kind, @parent, @func, @node)
    @names = {}
    @order = []
    @env_count = 0
    @id = 0
    @per_iter = false
    @is_with = false
    @has_dyn = false
    @tdz_bindings = nil
    @has_dispose = false

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
    @env_count > 0 || @is_with || @has_dyn

+ JaFunc
  rw :node, :parent, :index, :scope, :strict, :arrow, :uses_this, :uses_args, :dynamic, :free, :fclass, :single, :inner, :binding, :self_binding, :self_scope, :unsupported, :name, :def_scope, :nparams, :params, :this_binding, :body_scope, :script, :nlocals, :code, :scopes, :analysis, :in_if, :single_ref, :annexb, :unsupported0, :simple, :args_binding, :mapped_args, :param_nodes, :param_copies, :method_kind, :is_static, :home, :class_ctor, :derived, :default_ctor, :field_init, :class_node, :nt_binding, :fo_binding, :eval_dyn_vars, :has_tail, :has_dispose, :mod_rec

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
    @self_scope = nil
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
    @eval_dyn_vars = nil
    @has_tail = false
    @has_dispose = false
    @mod_rec = nil

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
      in_param_sc = vs.kind == :function && vs.func != nil && vs.func.body_scope != nil && vs.func.body_scope != vs
      names = var_names(list, [], false, true)
      list.each ->(s)
        fs2 = unwrap_labeled_fn(s)
        names.push(fs2.str) if fs2 != nil && !names.include?(fs2.str)
      names.each ->(nm)
        s = outer
        found = nil
        in_catch = false
        while s != nil && found == nil
          if simple_catch_scope?(s)
            in_catch = true if s.names[nm] != nil
          else
            cand = s.names[nm]
            cand = nil if cand != nil && cand.kind == :global && s.kind != :script
            found = cand
          if found == nil
            break if s == vs
            s = s.parent
        if found != nil && (found.kind == :let || found.kind == :const || found.kind == :class || found.kind == :lexical || (in_param_sc && (found.kind == :param || found.kind == :arguments)))
          f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
        elsif found == nil
          if vs.kind == :script
            if js_lexical_map().has_key?(nm)
              f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
            if in_catch
              f.eval_dyn_vars = [] if f.eval_dyn_vars == nil
              f.eval_dyn_vars.push(nm)
            else
              sc.declare(self, nm, :global)
          else
            vs.has_dyn = true
            if in_catch
              f.eval_dyn_vars = [] if f.eval_dyn_vars == nil
              f.eval_dyn_vars.push(nm)
            else
              sc.declare(self, nm, :dyn_eval)
      # Annex B.3.3.3: sloppy block-scoped function declarations hoist if they don't clash with enclosing lexicals/params!
      ab = annexb_names(list, lexical_names(list), [], true)
      ab.each ->(nm)
        if !names.include?(nm)
          s = outer
          found = nil
          clash = false
          while s != nil && found == nil
            if !simple_catch_scope?(s)
              cand = s.names[nm]
              cand = nil if cand != nil && cand.kind == :global && s.kind != :script
              found = cand
              if found != nil
                clash = true if found.kind == :let || found.kind == :const || found.kind == :class || found.kind == :lexical || (in_param_sc && (found.kind == :param || found.kind == :arguments))
                break
            break if s == vs
            s = s.parent
          if !clash && found == nil
            if vs.kind == :script
              sc.declare(self, nm, :global) if !js_lexical_map().has_key?(nm)
            else
              vs.has_dyn = true
              sc.declare(self, nm, :dyn_eval)
      f.dynamic = true
      hoist_block(sc, list.select(->(s) unwrap_labeled_fn(s) == nil), true)
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

  -> run_module(mod_rec)
    f = JaFunc.new(@program, nil, 0)
    f.analysis = self
    f.script = false
    f.strict = true
    f.mod_rec = mod_rec
    @funcs.push(f)
    sc = new_scope(:module, nil, f, @program)
    f.scope = sc
    f.body_scope = sc
    hoist_module(f, sc, @program.list)
    walk_stmts(@program.list, sc)
    finish()
    self

  -> hoist_module(f, sc, stmts)
    lex_seen = {}
    var_seen = {}
    # 1. Declare all top-level var names (including inside blocks and export var)
    vn = var_names(stmts, [], true, true)
    vn.each ->(nm)
      var_seen[nm] = true
      sc.declare(self, nm, :var)
    # 2. Declare imports, top-level let/const/using/await using/class/function, and export declarations
    i = 0
    while i < stmts.size
      s = stmts[i]
      k = s.kind
      if k == :import_decl
        phase = s.a
        s.list.each ->(sp)
          nm = sp.str
          if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          lex_seen[nm] = true
          if sp.a == :namespace || phase == "source"
            b = sc.declare(self, nm, :const)
            b.decl_const = true
          else
            b = sc.declare(self, nm, :import)
            b.decl_const = true
      elsif k == :export_default
        d = s.a
        if d.kind == :function_decl
          nm = d.str != nil ? d.str : "*default*"
          if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          lex_seen[nm] = true
          b = sc.declare(self, nm, :function)
          b.writes += 1
        elsif d.kind == :class_decl
          nm = d.str != nil ? d.str : "*default*"
          if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          lex_seen[nm] = true
          b = sc.declare(self, nm, :class)
          b.decl_pos = d.fin
        else
          b = sc.declare(self, "*default*", :let)
          b.decl_pos = s.fin
      elsif k == :export_named && s.a != nil
        hoist_mod_decl(f, sc, s.a, lex_seen, var_seen)
      elsif k == :var_decl || k == :function_decl || k == :class_decl
        hoist_mod_decl(f, sc, s, lex_seen, var_seen)
      i += 1
    nil

  -> hoist_mod_decl(f, sc, s, lex_seen, var_seen)
    k = s.kind
    if k == :var_decl && s.str != "var"
      is_const = s.str == "const" || s.str == "using" || s.str == "await using"
      if s.str == "using" || s.str == "await using"
        sc.has_dispose = true
        f.has_dispose = true
      s.list.each ->(dec)
        names = bound_names(dec.a, [])
        names.each ->(nm)
          if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          lex_seen[nm] = true
          b = sc.declare(self, nm, is_const ? :const : :let)
          b.decl_pos = dec.fin
          b.decl_const = is_const
    elsif k == :class_decl && s.str != nil
      nm = s.str
      if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
        f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
      lex_seen[nm] = true
      b = sc.declare(self, nm, :class)
      b.decl_pos = s.fin
    elsif k == :function_decl && s.str != nil
      nm = s.str
      if lex_seen.has_key?(nm) || var_seen.has_key?(nm)
        f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
      lex_seen[nm] = true
      b = sc.declare(self, nm, :function)
      b.writes += 1
    nil

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
    elsif k == :export_named && s.a != nil
      var_names_stmt(s.a, out, strict, false)
    nil

  # Declare the hoisted names of a function or script body in sc. (Annex B names that a
  # top-level let, const or class of the body already declares are not vars.)
  -> hoist_body(f, sc, stmts, top)
    vn = var_names(stmts, [], f.strict, true)
    # Check top-level var/function vs lexical clashes & param vs lexical clashes
    lex = lexical_names(stmts)
    if lex.size > 0
      lset = {}
      lex.each ->(nm) lset[nm] = true
      vn.each ->(nm) f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if lset.has_key?(nm)
      if !f.script
        f.scope.order.each ->(b)
          f.fail0("SyntaxError: Identifier '" + b.name + "' has already been declared") if b.kind == :param && lset.has_key?(b.name)
    # strict eval code keeps its vars and functions to itself
    gvars = sc.kind == :script && !(@eval_mode && f.strict)
    i = 0
    while i < vn.size
      sc.declare(self, vn[i], gvars ? :global : :var)
      i += 1
    if !f.strict
      pnames = []
      f.scope.order.each ->(b) pnames.push(b.name) if b.kind == :param || b.kind == :arguments
      an = annexb_names(stmts, lex + pnames, [], true)
      i = 0
      while i < an.size
        b = sc.names[an[i]]
        if b == nil && !(gvars && js_lexical_map().has_key?(an[i]))
          sc.declare(self, an[i], gvars ? :global : :var)
        i += 1
    hoist_block(sc, stmts, top)

  -> unwrap_labeled_fn(s)
    cur = s
    while cur != nil && cur.kind == :labeled
      cur = cur.a
    (cur != nil && cur.kind == :function_decl && cur.str != nil) ? cur : nil

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
        s = unwrap_labeled_fn(stmts[j])
        if s != nil && !s.has?(F_ASYNC) && !s.has?(F_GENERATOR) && !lex.include?(s.str)
          out.push(s.str) if !out.include?(s.str)
        j += 1
      # this block's own functions are lexical in it: they shadow for nested blocks
      j = 0
      while j < stmts.size
        fs2 = unwrap_labeled_fn(stmts[j])
        inner.push(fs2.str) if fs2 != nil
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
    elsif k == :with
      annexb_body(s.b, lex, out)
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
    f = sc.func
    lex_seen = {}
    fn_seen = {}
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :var_decl && s.str != "var"
        is_const = s.str == "const" || s.str == "using" || s.str == "await using"
        if s.str == "using" || s.str == "await using"
          sc.has_dispose = true
          f.has_dispose = true
        j = 0
        while j < s.list.size
          names = bound_names(s.list[j].a, [])
          q = 0
          while q < names.size
            nm = names[q]
            if lex_seen.has_key?(nm) || fn_seen.has_key?(nm)
              f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
            lex_seen[nm] = true
            b = sc.declare(self, nm, script ? :lexical : (is_const ? :const : :let))
            b.decl_pos = s.list[j].fin
            b.decl_const = is_const
            q += 1
          j += 1
      elsif s.kind == :class_decl && s.str != nil
        nm = s.str
        if lex_seen.has_key?(nm) || fn_seen.has_key?(nm)
          f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
        lex_seen[nm] = true
        b = sc.declare(self, nm, script ? :lexical : :class)
        b.decl_pos = s.fin
      else
        fs2 = unwrap_labeled_fn(s)
        if fs2 != nil
          nm = fs2.str
          if lex_seen.has_key?(nm)
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          if !top && fn_seen.has_key?(nm)
            # In strict mode (or if either is async/generator), duplicate block functions are a SyntaxError
            prev_s = fn_seen[nm]
            if f.strict || fs2.has?(F_ASYNC) || fs2.has?(F_GENERATOR) || prev_s.has?(F_ASYNC) || prev_s.has?(F_GENERATOR)
              f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared")
          fn_seen[nm] = fs2
          b = sc.declare(self, nm, gfuns ? :global : :function)
          b.writes += 1
      i += 1
    # Check nested var declarations inside this non-top lexical scope against its lexicals and block functions!
    if !top && (lex_seen.size > 0 || fn_seen.size > 0)
      inner_vars = var_names(stmts, [], f.strict, false)
      inner_vars.each ->(nm)
        f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if lex_seen.has_key?(nm) || fn_seen.has_key?(nm)
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
            note_write(b, sc, b.decl_pos)
          elsif s.str != "var"
            note_write(b, sc, b.decl_pos)
        i += 1
    elsif k == :function_decl
      b = resolve(s.str, sc)
      walk_function(s, sc, b)
      top_sc = sc.func.body_scope != nil ? sc.func.body_scope : sc.func.scope
      if b.kind == :function && b.scope != top_sc && !s.has?(F_ASYNC) && !s.has?(F_GENERATOR)
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
        bv = var_names_stmt(s.d, [], f.strict, false)
        if bv != nil
          nil
        body_vars = []
        var_names_stmt(s.d, body_vars, f.strict, false)
        body_vars.each ->(nm)
          f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if fs.names.has_key?(nm)
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
        cnames = {}
        if s.b != nil
          names = bound_names(s.b, [])
          q = 0
          while q < names.size
            nm = names[q]
            f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if cnames.has_key?(nm)
            cnames[nm] = true
            cs.declare(self, nm, :catch)
            q += 1
          if s.b.kind == :ident
            ref(s.b, cs)
          else
            walk_pattern(s.b, cs, true)
          # Catch parameter clashes with lexical declarations in catch block (and with var if destructuring!)
          clex = lexical_names(s.c.list)
          clex.each ->(nm) f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if cnames.has_key?(nm)
          s.c.list.each ->(st)
            if st.kind == :function_decl && st.str != nil && cnames.has_key?(st.str)
              f.fail0("SyntaxError: Identifier '" + st.str + "' has already been declared")
          if s.b.kind != :ident
            cvars = var_names(s.c.list, [], f.strict, false)
            cvars.each ->(nm) f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if cnames.has_key?(nm)
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
      if f.strict
        f.fail0("SyntaxError: Strict mode code may not include a with statement")
      f.fail("with")
      g = f
      while g != nil
        g.dynamic = true
        g = g.parent
      ws = map_scope(s, new_scope(:with, sc, f, s))
      ws.is_with = true
      walk_expr(s.a, sc)
      walk_stmt(s.b, ws)
    elsif k == :for_in || k == :for_of
      f.fail("for await") if s.has?(F_AWAIT)
      fs = sc
      a = s.a
      if a.kind == :var_decl && a.str != "var"
        fs = map_scope(s, new_scope(:for, sc, f, s))
        hoist_block(fs, [a], false)
        fs.order.each ->(fb) fb.decl_pos = s.b.fin
        fs.per_iter = true
        body_vars = []
        var_names_stmt(s.d, body_vars, f.strict, false)
        body_vars.each ->(nm)
          f.fail0("SyntaxError: Identifier '" + nm + "' has already been declared") if fs.names.has_key?(nm)
      # the right side sees the head's let bindings in their dead zone (spec: TDZ scope)
      walk_expr(s.b, fs)
      if a.kind == :var_decl
        walk_pattern(a.list[0].a, fs, true)
        walk_expr(a.list[0].b, fs) if a.list[0].b != nil
      else
        walk_pattern(a, fs, false)
      walk_stmt(s.d, fs)
    elsif k == :import_decl || k == :export_all
      nil
    elsif k == :export_named
      walk_stmt(s.a, sc) if s.a != nil
    elsif k == :export_default
      d = s.a
      if d.kind == :function_decl
        nm = d.str != nil ? d.str : "*default*"
        b = resolve(nm, sc)
        walk_function(d, sc, b)
        d.x.name = "default" if d.str == nil
      elsif d.kind == :class_decl
        nm = d.str != nil ? d.str : "*default*"
        cb = resolve(nm, sc)
        d.c = JaRef.new(cb, sc)
        walk_class(d, sc, cb)
        name_fn(d, "default") if d.str == nil
      else
        walk_expr(d, sc)
        name_fn(d, "default")
        b = resolve("*default*", sc)
        s.c = JaRef.new(b, sc)
        note_write(b, sc, s.pos)
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
      fs2 = unwrap_labeled_fn(s)
      has = true if (s.kind == :var_decl && s.str != "var") || s.kind == :class_decl || (fs2 != nil && block_function?(fs2, sc))
      i += 1
    return sc if !has
    bs = map_scope(node, new_scope(:block, sc, sc.func, node))
    hoist_block(bs, stmts, false)
    bs

  -> simple_catch_scope?(s)
    s.kind == :catch && s.node != nil && s.node.b != nil && s.node.b.kind == :ident

  # The var binding an Annex B function declaration in block scope bs copies into.
  -> annexb_var(name, bs)
    return nil if bs.func.strict
    fs = bs.func.body_scope != nil ? bs.func.body_scope : bs.func.scope
    # Annex B.3.3.1: skip if name is an explicit parameter or implicit arguments binding (ES §10.2.11 step 22.f)
    if !bs.func.script && !bs.func.arrow && !bs.func.analysis.eval_mode
      pb = bs.func.scope.names[name]
      return nil if pb != nil && (pb.kind == :param || pb.kind == :arguments)
    v = fs.names[name]
    if v != nil && (v.kind == :var || v.kind == :global || v.kind == :dyn_eval || v.kind == :function)
      return nil if v.kind == :global && js_lexical_map().has_key?(name)
      # a lexical declaration between the block and the function shadows: no copy (simple catch does not block!)
      s = bs.parent
      while s != nil && s != fs
        if !simple_catch_scope?(s)
          b = s.names[name]
          return nil if b != nil
        s = s.parent
      return v
    # Sloppy direct eval: may copy into an existing var/param/global/function binding of the caller's variable scope!
    if bs.func.analysis.eval_mode && bs.func.def_scope != nil
      s = bs.parent
      while s != nil && s != fs
        return nil if !simple_catch_scope?(s) && s.names[name] != nil
        s = s.parent
      s = bs.func.def_scope
      while s != nil
        if !simple_catch_scope?(s)
          b = s.names[name]
          if b != nil
            return nil if b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :lexical
            return b if b.kind == :var || b.kind == :global || b.kind == :param || b.kind == :dyn_eval || b.kind == :function
            return nil
        break if s.kind == :function || s.kind == :body || s.kind == :script
        s = s.parent
    nil

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

  -> enclosing_non_arrow(f)
    g = f
    while g != nil && g.arrow
      g = g.parent
    g

  -> check_no_arguments(nm, sc)
    if nm == "arguments"
      g = enclosing_non_arrow(sc.func)
      sc.func.fail0("SyntaxError: 'arguments' is not allowed in class field initializer or static initialization block") if g != nil && g.field_init
    nil

  -> walk_expr(e, sc)
    return nil if e == nil
    f = sc.func
    k = e.kind
    if k == :ident
      check_no_arguments(e.str, sc)
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
      if c.kind == :super
        g = enclosing_non_arrow(f)
        f.fail0("SyntaxError: 'super' keyword unexpected here") if g == nil || !g.class_ctor || !g.derived
        note_special(sc, :nt)
      if c.kind == :ident
        cb = ref(c, sc)
        if c.str == "arguments"
          g = enclosing_non_arrow(f)
          f.fail0("SyntaxError: 'arguments' is not allowed in class field initializer or static initialization block") if g != nil && g.field_init
        if c.str == "eval"
          # a direct eval (when eval is still %eval% at run time): its code sees every
          # binding in scope, so this function and those around it keep all of theirs in
          # environments (finish), and tier 0 analyses the code below sc (run_direct)
          f.fail("eval")
          e.d = sc
          g = f
          while g != nil
            g.dynamic = true
            g = g.parent
          vs = sc
          while vs.parent != nil && vs.kind != :function && vs.kind != :body && vs.kind != :script
            vs = vs.parent
          vs.has_dyn = true if vs.kind != :script
          g = f
          while g.arrow
            g = g.parent
          if !g.script
            if g.this_binding == nil
              g.this_binding = g.scope.declare(self, "this", :this)
              g.this_binding.writes = 1
            if g.fo_binding == nil
              g.fo_binding = g.scope.declare(self, "%home", :fnobj)
              g.fo_binding.writes = 1
            if g.nt_binding == nil
              g.nt_binding = g.scope.declare(self, "new.target", :newtarget)
              g.nt_binding.writes = 1
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
      if e.a.kind == :super
        g = enclosing_non_arrow(f)
        f.fail0("SyntaxError: 'super' keyword unexpected here") if g == nil || !(g.home || g.class_ctor || g.field_init || g.method_kind != nil)
      walk_expr(e.a, sc)
      if e.has?(F_COMPUTED)
        walk_expr(e.b, sc)
      elsif e.b.kind == :private_name
        priv_ref(e.b, sc)
    elsif k == :chain
      walk_expr(e.a, sc)
    elsif k == :unary
      if e.str == "typeof" && e.a.kind == :ident
        check_no_arguments(e.a.str, sc)
        note_read(ref(e.a, sc), sc, e.a.pos, false)
      elsif e.str == "delete" && e.a.kind == :ident
        check_no_arguments(e.a.str, sc)
        b = ref(e.a, sc)
        note_read(b, sc, e.a.pos, false)
        f.fail0("SyntaxError: Delete of an unqualified identifier in strict mode") if f.strict
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
        check_no_arguments(e.a.str, sc)
        b = ref(e.a, sc)
        note_read(b, sc, e.a.pos, false) if e.str != "="
        note_fn_value(e.b, nil)
        walk_expr(e.b, sc)
        name_fn(e.b, e.a.str) if !e.a.has?(F_PAREN) && (e.str == "=" || e.str == "&&=" || e.str == "||=" || e.str == "??=")
        note_write(b, sc, e.a.pos)
      elsif e.a.kind == :member
        walk_expr(e.a, sc)
        walk_expr(e.b, sc)
      elsif e.a.kind == :call
        f.fail("web-compat lhs")
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
      has_proto = false
      i = 0
      while i < e.list.size
        p = e.list[i]
        if p.kind == :prop && p.b != nil && p.b.kind == :assign_pattern
          f.fail0("SyntaxError: Invalid shorthand property initializer")
        if p.kind == :prop && p.str == "init" && !p.has?(F_COMPUTED) && !p.has?(F_SHORTHAND) && !p.has?(F_METHOD) && (p.a.kind == :ident || p.a.kind == :string) && p.a.str == "__proto__"
          f.fail0("SyntaxError: Duplicate __proto__ fields are not allowed in object literals") if has_proto
          has_proto = true
        if p.kind != :prop || p.str != "init" || p.has?(F_COMPUTED) || p.has?(F_METHOD)
          walk_expr(p.a, sc) if p.kind == :prop && p.has?(F_COMPUTED)
        walk_expr(p.kind == :prop ? p.b : p.a, sc)
        # methods and accessors of a literal are not constructors
        if p.kind == :prop && (p.has?(F_METHOD) || p.str == "get" || p.str == "set") && p.b.x.is_a?(JaFunc)
          p.b.x.method_kind = p.has?(F_METHOD) ? "method" : p.str
          if !p.has?(F_COMPUTED) && (p.str == "get" || p.str == "set")
            kn = p.a.kind == :num ? js_number_to_s(p.a.a) : p.a.str
            p.b.x.name = p.str + " " + kn.to_s if kn != nil
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
      begin
        js_rx_compile(e.str, e.a)
      rescue ex
        f.fail0("Invalid regular expression: /" + e.str.to_s + "/")
    elsif k == :meta_property
      if e.str == "new.target"
        g = enclosing_non_arrow(f)
        f.fail0("SyntaxError: new.target expression is not allowed here") if g == nil || g.script || g.mod_rec != nil
        e.x = JaRef.new(nil, sc)
        note_special(sc, :nt)
      elsif e.str == "import.meta"
        e.x = JaRef.new(nil, sc)
      else
        f.fail0(e.str)
    elsif k == :import_call
      walk_expr(e.a, sc)
      walk_expr(e.b, sc) if e.b != nil
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
      check_no_arguments(t.str, sc)
      b = ref(t, sc)
      note_read(b, sc, t.pos, false)
      note_write(b, sc, t.pos)
    else
      sc.func.fail("web-compat lhs") if t.kind == :call
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

  -> has_dyn_ancestor?(sc)
    s = sc
    while s != nil
      return true if s.is_with || s.has_dyn
      s = s.parent
    false

  -> walk_function(n, sc, binding, is_ctor = false, is_derived = false, is_field_init = false)
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
    jf.home = true if n.has?(F_METHOD)
    jf.class_ctor = is_ctor
    jf.derived = is_derived
    jf.field_init = is_field_init
    jf.fail("async") if n.has?(F_ASYNC)
    jf.fail("generator") if n.has?(F_GENERATOR)
    fparent = sc
    if n.kind == :function && n.str != nil && binding == nil
      self_sc = new_scope(:self, sc, jf, n)
      jf.self_scope = self_sc
      jf.self_binding = self_sc.declare(self, n.str, :self)
      fparent = self_sc
    fs = new_scope(:function, fparent, jf, n)
    jf.scope = fs
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
    if n.has?(F_HAS_EVAL) || has_dyn_ancestor?(sc)
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
          jf.param_copies.push([pb, b]) if pb != nil && (pb.kind == :param || pb.kind == :arguments) && b.kind == :var
      jf.body_scope = bs
      walk_stmts(body, bs)
    if jf.strict && !jf.field_init && !n.has?(F_ASYNC) && !n.has?(F_GENERATOR) && !(jf.body_scope != nil && jf.body_scope.has_dispose)
      if jf.arrow && n.has?(F_EXPR_BODY)
        mark_tail_expr(n.b, jf)
      else
        mark_tail_stmts(n.b, jf)
    nil

  # ECMA-262 §15.10.2 HasCallInTailPosition: mark :call and :tagged_template nodes
  # that are in strict tail position of jf.
  -> mark_tail_stmts(list, jf)
    return nil if list == nil
    i = 0
    while i < list.size
      mark_tail_stmt(list[i], jf)
      i += 1
    nil

  -> mark_tail_stmt(s, jf)
    return nil if s == nil
    k = s.kind
    if k == :return
      mark_tail_expr(s.a, jf) if s.a != nil
    elsif k == :block
      mark_tail_stmts(s.list, jf) if !(s.x.is_a?(JaScope) && s.x.has_dispose)
    elsif k == :if
      mark_tail_stmt(s.b, jf)
      mark_tail_stmt(s.c, jf)
    elsif k == :while
      mark_tail_stmt(s.b, jf)
    elsif k == :do_while
      mark_tail_stmt(s.a, jf)
    elsif k == :for || k == :for_in
      mark_tail_stmt(s.d, jf) if !(s.x.is_a?(JaScope) && s.x.has_dispose)
    elsif k == :labeled
      mark_tail_stmt(s.a, jf)
    elsif k == :with
      mark_tail_stmt(s.b, jf)
    elsif k == :switch
      i = 0
      while i < s.list.size
        mark_tail_stmts(s.list[i].list, jf)
        i += 1
    elsif k == :try
      # try body is NEVER in tail position; catch body only when there is no finally; finally body IS.
      mark_tail_stmts(s.c.list, jf) if s.c != nil && s.d == nil
      mark_tail_stmts(s.d.list, jf) if s.d != nil
    nil

  -> mark_tail_expr(e, jf)
    return nil if e == nil
    k = e.kind
    if k == :cond
      mark_tail_expr(e.b, jf)
      mark_tail_expr(e.c, jf)
    elsif k == :logical
      mark_tail_expr(e.b, jf)
    elsif k == :seq
      mark_tail_expr(e.list[e.list.size - 1], jf) if e.list.size > 0
    elsif k == :chain
      mark_tail_expr(e.a, jf)
    elsif k == :call
      if e.a.kind != :super
        e.flags = e.flags | F_TAIL
        jf.has_tail = true
    elsif k == :tagged_template
      e.flags = e.flags | F_TAIL
      jf.has_tail = true
    nil

  # A binding or assignment pattern: annotate its identifiers, walk its defaults and
  # computed keys. decl: the identifiers are declarations (already declared in sc).
  -> walk_pattern(p, sc, decl)
    return nil if p == nil
    k = p.kind
    if k == :ident
      check_no_arguments(p.str, sc)
      b = ref(p, sc)
      note_write(b, sc, p.pos)
    elsif k == :assign_pattern
      walk_pattern(p.a, sc, decl)
      walk_expr(p.b, sc)
      name_fn(p.b, p.a.str) if p.a.kind == :ident && !p.a.has?(F_PAREN)
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

  # NamedEvaluation (§8.4.5): an anonymous function, arrow, or class takes the name it is bound to.
  -> name_fn(e, name)
    return nil if e == nil || name == nil
    k = e.kind
    if (k == :function || k == :arrow) && e.str == nil && e.x.is_a?(JaFunc)
      e.x.name = name
    elsif (k == :class || k == :class_decl) && e.str == nil && e.d != nil && e.d.x.is_a?(JaFunc)
      has_static_name = false
      i = 0
      while i < e.list.size
        m = e.list[i]
        if m.has?(F_STATIC) && !m.has?(F_COMPUTED) && (m.kind == :method_def || m.kind == :field_def) && m.a != nil && m.a.kind != :private_name && (m.a.kind == :ident || m.a.kind == :string) && m.a.str == "name"
          has_static_name = true
        i += 1
      e.d.x.name = name if !has_static_name
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
    if (b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :class_inner) && (pos < b.decl_pos || b.scope.func != sc.func)
      b.early_read = true
    nil

  -> note_write(b, sc, pos)
    b.writes += 1
    note_capture(b, sc)
    if (b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :class_inner) && (pos < b.decl_pos || b.scope.func != sc.func)
      b.early_read = true
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
    if g.script || g.mod_rec != nil
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
    # Class decorators are evaluated in the outer scope BEFORE the class scope / PrivateEnvironment
    walk_exprs(n.b, sc) if n.b.is_a?(Array)
    cs = map_scope(n, new_scope(:class, sc, f, n))
    if n.str != nil
      inner = cs.declare(self, n.str, :class_inner)
      inner.writes = 1
    # ClassHeritage is evaluated BEFORE the class's PrivateEnvironment is created (§15.7.14)
    walk_expr(n.a, cs) if n.a != nil
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
    ctor = nil
    i = 0
    while i < n.list.size
      m = n.list[i]
      if m.kind == :method_def
        walk_exprs(m.c, cs) if m.c.is_a?(Array)
        walk_expr(m.a, cs) if m.has?(F_COMPUTED)
        walk_function(m.b, cs, nil, m.str == "constructor", m.str == "constructor" && n.a != nil, false)
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
        walk_exprs(m.c, cs) if m.c.is_a?(Array)
        walk_expr(m.a, cs) if m.has?(F_COMPUTED)
        if m.b != nil
          body = [JsNode.new(:return, m.b.pos, m.b.fin, nil, m.b, nil, nil, nil, 0)]
          fn = JsNode.new(:function, m.pos, m.fin, nil, nil, body, nil, [], F_STRICT | F_METHOD)
          walk_function(fn, cs, nil, false, false, true)
          fn.x.field_init = true
          fn.x.home = true
          fn.x.is_static = m.has?(F_STATIC)
          m.x = fn.x
          name_fn(m.b, m.a.kind == :private_name ? "#" + m.a.str : m.a.str) if !m.has?(F_COMPUTED) && m.a.kind != :num
      elsif m.kind == :static_block
        fn = JsNode.new(:function, m.pos, m.fin, nil, nil, m.list, nil, [], F_STRICT | F_METHOD)
        walk_function(fn, cs, nil, false, false, true)
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
    # Propagate dynamic=true down to inner functions walked before eval/with appeared in their enclosing scope!
    i = 1
    while i < @funcs.size
      f = @funcs[i]
      if !f.dynamic && ((f.parent.dynamic && !f.parent.script) || has_dyn_ancestor?(f.def_scope))
        f.dynamic = true
      i += 1
    # a function's own name, if escaping, keeps its object
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
        if single_ok?(fb) && single_init_ok?(f, fb)
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
    # Module top-level scope: every own module binding lives in mod.env (slot >= 0) for live exports!
    if @funcs.size > 0 && @funcs[0].scope.kind == :module
      ms = @funcs[0].scope
      ms.order.each ->(b)
        if !b.global? && b.kind != :import && b.slot < 0
          b.slot = ms.env_count
          ms.env_count = ms.env_count + 1
    # a function containing a direct eval (or one around it): every binding in an
    # environment, where the eval'd code can reach it (including script-level class/block scopes!)
    i = 0
    while i < @funcs.size
      f = @funcs[i]
      if f.dynamic
        f.scopes.each ->(s)
          if !f.script || s.kind != :script
            s.order.each ->(b)
              if !b.global? && b.kind != :dyn_eval && b.slot < 0
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
          if !b.global? && b.kind != :dyn_eval && b.slot < 0 && b.kind != :this
            b.lidx = n
            n += 1
          q += 1
        j += 1
      f.nlocals = n
      j = 0
      while j < f.scopes.size
        sc = f.scopes[j]
        tb = nil
        q = 0
        while q < sc.order.size
          b = sc.order[q]
          if b.kind == :let || b.kind == :const || b.kind == :class || b.kind == :class_inner
            tb = [] if tb == nil
            tb.push(b)
          q += 1
        sc.tdz_bindings = tb
        j += 1
      i += 1
    ccall("w_value_free_w", @fnmap) if @fnmap != nil
    @fnmap = {}
    ccall("w_value_free_w", @scopemap) if @scopemap != nil
    @scopemap = {}
    nil

  # Release AST nodes and scope/function analysis tables when a Realm/Page is closed.
  -> free_once(seen, x)
    return nil if x == nil
    k = (wvalue_bits(x) ## i64) & 140737488355312
    return nil if k == 0 || seen.has_key?(k)
    seen[k] = true
    ccall("w_value_free_w", x)
    nil

  -> release
    if JS_GC_ON[0]
      @src = nil
      return nil
    seen = {}
    seen[(wvalue_bits(JS_EMPTY_BLOCK) ## i64) & 140737488355312] = true
    seen[(wvalue_bits(JS_EMPTY_BLOCK.list) ## i64) & 140737488355312] = true
    if @program != nil
      stack = [@program]
      while stack.size > 0
        n = stack.pop
        next if n == nil || !n.is_a?(JsNode) || n == JS_EMPTY_BLOCK
        nk = (wvalue_bits(n) ## i64) & 140737488355312
        next if seen.has_key?(nk)
        seen[nk] = true
        stack.push(n.a) if n.a.is_a?(JsNode)
        stack.push(n.b) if n.b.is_a?(JsNode)
        if n.b.is_a?(Array)
          bi = 0
          while bi < n.b.size
            stack.push(n.b[bi]) if n.b[bi].is_a?(JsNode)
            bi += 1
          free_once(seen, n.b)
        stack.push(n.c) if n.c.is_a?(JsNode)
        stack.push(n.d) if n.d.is_a?(JsNode)
        if n.list.is_a?(Array)
          li = 0
          while li < n.list.size
            stack.push(n.list[li]) if n.list[li].is_a?(JsNode)
            li += 1
          free_once(seen, n.list)
        free_once(seen, n.x) if n.x.is_a?(JaRef)
        ccall("w_value_free_w", n)
      ccall("w_value_free_w", stack)
      @program = nil
    fi = 0
    while fi < @funcs.size
      f = @funcs[fi]
      fi += 1
      next if f == nil
      si = 0
      while si < f.scopes.size
        sc = f.scopes[si]
        si += 1
        next if sc == nil
        oi = 0
        while oi < sc.order.size
          free_once(seen, sc.order[oi])
          oi += 1
        free_once(seen, sc.names)
        free_once(seen, sc.order)
        free_once(seen, sc.tdz_bindings)
        free_once(seen, sc)
      free_once(seen, f.free)
      free_once(seen, f.inner)
      free_once(seen, f.params)
      free_once(seen, f.scopes)
      free_once(seen, f.param_nodes)
      free_once(seen, f.param_copies)
      free_once(seen, f)
    free_once(seen, @funcs)
    free_once(seen, @unsupported_counts)
    free_once(seen, @fnmap)
    free_once(seen, @scopemap)
    ccall("w_value_free_w", seen)
    @funcs = []
    @src = nil
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

  # A let, const or class binding is stored by value only in a function made after the
  # binding was initialized: not a hoisted declaration (made at its scope's entry), and
  # one that starts after the declaration ends.
  -> single_init_ok?(f, b)
    return true if !(b.kind == :let || b.kind == :const || b.kind == :class)
    return false if f.node.kind == :function_decl
    return false if b.scope.node != nil && b.scope.node.kind == :switch
    f.node.pos > b.decl_pos

  -> single_ok?(b)
    return false if b.kind == :import || b.scope.kind == :module
    return false if b.kind == :param && (b.scope.func.mapped_args || !b.scope.func.simple)
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
