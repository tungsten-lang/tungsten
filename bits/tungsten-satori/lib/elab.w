# Satori elaborator: surface ASTs -> kernel terms.
#
# Hindley-Milner inference over kernel types. Type metavariables are type
# variables whose names start with "?". Numerals get numeric metas that default
# to ℕ (or ℚ for decimals). Unknown lowercase identifiers in theorem statements
# become universally quantified variables ("auto-bound").

+ Elab
  ro :k, :autobound
  rw :allow_auto

  -> new(@k)
    @counter = 0
    @subst = {}
    @numeric = {}
    @fractional = {}
    @locals = []
    @autobound = []
    @allow_auto = false
    @type_params = []
    @aliases = {"True" => "⊤", "False" => "⊥"}
    @fields = {}
    @ctor_names = {}

  -> reset
    @subst = {}
    @numeric = {}
    @fractional = {}
    @locals = []
    @autobound = []
    @type_params = []

  -> register_fields(tyname, ctor, fields)
    @fields[tyname] = [ctor, fields]

  -> fresh_meta
    @counter += 1
    ty_var("?" + @counter.to_s)

  -> meta?(t)
    t.tag == :v && t.name.starts_with?("?")

  # ---- types -------------------------------------------------------------------

  -> resolve(t)
    if t.tag == :v
      if @subst.has_key?(t.name)
        r = resolve(@subst[t.name])
        @subst[t.name] = r
        return r
      return t
    if t.args.size == 0
      return t
    args = []
    t.args.each -> (a)
      args.push(resolve(a))
    ty_con(t.name, args)

  -> unify(a, b)
    a = resolve(a)
    b = resolve(b)
    if ty_eq(a, b)
      return true
    if meta?(a)
      bind_meta(a, b)
      return true
    if meta?(b)
      bind_meta(b, a)
      return true
    if a.tag == :v || b.tag == :v
      raise "type mismatch: " + ty_show(a) + " vs " + ty_show(b)
    if a.name != b.name || a.args.size != b.args.size
      raise "type mismatch: " + ty_show(a) + " vs " + ty_show(b)
    i = 0
    while i < a.args.size
      unify(a.args[i], b.args[i])
      i += 1
    true

  -> bind_meta(m, t)
    if ty_occurs(m.name, t)
      raise "type error: infinite type"
    if @numeric.has_key?(m.name)
      if meta?(t)
        @numeric[t.name] = true
        if @fractional.has_key?(m.name)
          @fractional[t.name] = true
      elsif t.tag == :c && !["nat", "int", "rat", "real"].include?(t.name)
        if !@k.inductives.has_key?(t.name)
          raise "type error: expected a number type, got " + ty_show(t)
    @subst[m.name] = t

  -> mark_numeric(t, fractional = false)
    t = resolve(t)
    if meta?(t)
      @numeric[t.name] = true
      if fractional
        @fractional[t.name] = true

  -> elab_type(a)
    case a.kind
    when :either
      return elab_type_expr(a.kids[0])
    when :tid
      return named_type(a.s, [])
    when :tapp
      args = []
      a.kids.each -> (x)
        args.push(elab_type(x))
      return named_type(a.s, args)
    when :tarrow
      return ty_fun(elab_type(a.kids[0]), elab_type(a.kids[1]))
    when :tprod
      return ty_con("prod", [elab_type(a.kids[0]), elab_type(a.kids[1])])
    else
      elab_type_expr(a)

  # Interprets an expression AST as a type.
  -> elab_type_expr(e)
    case e.kind
    when :id
      named_type(e.s, [])
    when :app
      sp = ast_spine(e)
      if sp[0].kind != :id
        raise "not a type"
      args = []
      sp[1].each -> (x)
        args.push(elab_type_expr(x))
      named_type(sp[0].s, args)
    when :binop
      if e.s == "→"
        ty_fun(elab_type_expr(e.kids[0]), elab_type_expr(e.kids[1]))
      else
        raise "not a type"
    when :tid, :tapp, :tarrow, :tprod, :either
      elab_type(e)
    else
      raise "not a type"

  -> type_expr?(e)
    begin
      elab_type_expr(e)
      return true
    rescue err
      return false

  -> named_type(n, args)
    case n
    when "ℕ", "nat", "Nat"
      return ty_nat
    when "ℤ", "int", "Int"
      return ty_int
    when "ℚ", "rat", "Rat"
      return ty_rat
    when "ℝ", "real", "Real"
      return ty_real
    when "Prop", "bool", "Bool"
      return ty_bool
    when "set", "Set"
      if args.size != 1
        raise "set takes one type argument"
      return ty_fun(args[0], ty_bool)
    if type_var_name?(n)
      return ty_var(n)
    if @pending != nil && n == @pending
      return ty_con(n, args)
    if !@k.types.has_key?(n)
      raise "unknown type " + n
    if @k.types[n] != args.size
      raise "type " + n + " expects " + @k.types[n].to_s + " arguments"
    ty_con(n, args)

  -> type_var_name?(n)
    if @type_params.include?(n)
      return true
    cs = n.chars
    if cs.size == 1
      o = cs[0].ord
      return o >= 945 && o <= 969 && n != "λ"
    n.starts_with?("'")

  # ---- terms -------------------------------------------------------------------

  -> ast_spine(e)
    args = []
    while e.kind == :app
      args.unshift(e.kids[1])
      e = e.kids[0]
    [e, args]

  -> lookup_local(n)
    i = @locals.size - 1
    while i >= 0
      if @locals[i][0] == n
        return @locals[i][1]
      i -= 1
    nil

  -> push_local(n, v)
    @locals.push([n, v])

  -> pop_local
    @locals.pop

  -> const_inst(name)
    g = @k.const_type(name)
    m = {}
    ty_vars(g).each -> (v)
      m[v] = fresh_meta
    mk_const_raw(name, ty_subst(g, m))

  -> tyof(t)
    resolve(type_of_meta(t))

  -> type_of_meta(t)
    case t.tag
    when :lam
      ty_fun(t.ty, type_of_meta(t.b))
    when :app
      ft = resolve(type_of_meta(t.a))
      if ft.fun?
        ft.cod
      else
        r = fresh_meta
        unify(ft, ty_fun(type_of_meta(t.b), r))
        r
    else
      t.ty

  -> app(f, x)
    ft = resolve(type_of_meta(f))
    xt = type_of_meta(x)
    if ft.fun?
      unify(ft.dom, xt)
    else
      r = fresh_meta
      unify(ft, ty_fun(xt, r))
    mk_app_raw(f, x)

  -> app2(name, a, b)
    app(app(const_inst(name), a), b)

  -> mk_not(p)
    app(const_inst("¬"), p)

  -> elab(e)
    case e.kind
    when :num
      t = mk_lit(e.s.to_i, fresh_meta)
      mark_numeric(t.ty)
      t
    when :dec
      parts = e.s.split(".")
      den = int_pow_fast(10, parts[1].size)
      t = mk_lit(q_make(parts[0].to_i * den + parts[1].to_i, den), fresh_meta)
      mark_numeric(t.ty, true)
      t
    when :id
      elab_id(e.s)
    when :app
      sp = ast_spine(e)
      f = elab(sp[0])
      sp[1].each -> (x)
        ft = resolve(type_of_meta(f))
        if x.kind == :lam && ft.fun?
          f = app(f, elab_lam_expected(x.binders, x.kids[0], 0, ft.dom))
        else
          f = app(f, elab(x))
      f
    when :binop
      elab_binop(e.s, e.kids[0], e.kids[1])
    when :unop
      elab_unop(e.s, e.kids[0])
    when :lam
      elab_lam(e.binders, e.kids[0], 0)
    when :quant
      elab_quant(e.s, e.binders, e.kids[0], 0)
    when :ite
      c = elab(e.kids[0])
      unify(tyof(c), ty_bool)
      a = elab(e.kids[1])
      b = elab(e.kids[2])
      ite = const_inst("ite")
      app(app(app(ite, c), a), b)
    when :ascribe
      elab_ascribe(e.kids[0], elab_type(e.ty))
    when :tuple
      t = elab(e.kids[e.kids.size - 1])
      i = e.kids.size - 2
      while i >= 0
        t = app2("pair", elab(e.kids[i]), t)
        i -= 1
      t
    when :list
      elab_list(e.kids)
    when :setof
      v = mk_var(e.s, fresh_meta)
      if e.ty != nil
        v = mk_var(e.s, elab_type(e.ty))
      push_local(e.s, v)
      body = elab(e.kids[0])
      pop_local
      unify(tyof(body), ty_bool)
      mk_lam(v, body)
    when :setlit
      v = mk_var("x", fresh_meta)
      body = nil
      e.kids.each -> (x)
        eq = app2("=", v, elab(x))
        if body == nil
          body = eq
        else
          body = app2("∨", body, eq)
      if body == nil
        body = const_inst("⊥")
      mk_lam(v, body)
    when :let
      v = elab(e.kids[0])
      if e.ty != nil
        unify(tyof(v), elab_type(e.ty))
      push_local(e.s, v)
      b = elab(e.kids[1])
      pop_local
      b
    when :proj
      project(elab(e.kids[0]), e.s)
    when :anon
      raise "anonymous constructor ⟨...⟩ needs a known structure type; use an ascription"
    when :hole
      raise "unexpected placeholder _"
    else
      raise "cannot elaborate " + e.kind.to_s

  -> elab_list(items)
    t = const_inst("nil")
    i = items.size - 1
    while i >= 0
      t = app2("cons", elab(items[i]), t)
      i -= 1
    t

  -> elab_id(n)
    v = lookup_local(n)
    if v != nil
      return v
    if @aliases.has_key?(n)
      return const_inst(@aliases[n])
    if @k.has_const?(n)
      return const_inst(n)
    # p.x : field projection or namespaced constant
    if n.include?(".")
      parts = n.split(".")
      base = lookup_local(parts[0])
      if base != nil
        t = base
        i = 1
        while i < parts.size
          t = project(t, parts[i])
          i += 1
        return t
    if @allow_auto && auto_name?(n)
      @autobound.each -> (p)
        if p[0] == n
          return p[1]
      v = mk_var(n, fresh_meta)
      @autobound.push([n, v])
      return v
    raise "unknown identifier '" + n + "'"

  -> auto_name?(n)
    if @auto_names != nil && @auto_names.has_key?(n)
      return true
    c = n.chars[0]
    o = c.ord
    (o >= 97 && o <= 122) || (o >= 945 && o <= 969)

  # pattern-variable names that may be auto-bound whatever their case
  -> set_auto_names(names)
    @auto_names = {}
    names.each -> (n)
      @auto_names[n] = true

  -> clear_auto_names
    @auto_names = nil

  -> project(t, field)
    ty = tyof(t)
    if (field == "1" || field == "2") && ty.tag == :c && ty.name == "prod"
      if field == "1"
        return app(const_inst("fst"), t)
      return app(const_inst("snd"), t)
    if ty.tag == :c && @fields.has_key?(ty.name)
      fname = ty.name + "." + field
      if @k.has_const?(fname)
        return app(const_inst(fname), t)
    if @k.has_const?(field)
      return app(const_inst(field), t)
    raise "no field " + field + " for type " + ty_show(ty)

  -> elab_ascribe(e, ty)
    t = elab(e)
    tt = tyof(t)
    if meta?(tt) || ty_eq(tt, ty)
      unify(tt, ty)
      return t
    c = coercion(tt, ty)
    if c != nil
      return app(const_inst(c[0]), t) if c.size == 1
      r = t
      c.each -> (nm)
        r = app(const_inst(nm), r)
      return r
    unify(tt, ty)
    t

  -> coercion(from, to)
    if from.tag != :c || to.tag != :c
      return nil
    f = from.name
    g = to.name
    if f == "nat" && g == "int"
      return ["int_of_nat"]
    if f == "int" && g == "rat"
      return ["rat_of_int"]
    if f == "rat" && g == "real"
      return ["real_of_rat"]
    if f == "nat" && g == "rat"
      return ["int_of_nat", "rat_of_int"]
    if f == "int" && g == "real"
      return ["rat_of_int", "real_of_rat"]
    if f == "nat" && g == "real"
      return ["int_of_nat", "rat_of_int", "real_of_rat"]
    nil

  -> elab_unop(op, x)
    case op
    when "¬"
      p = elab(x)
      unify(tyof(p), ty_bool)
      mk_not(p)
    when "neg"
      t = elab(x)
      if t.tag == :lit
        mark_numeric(t.ty)
      app(const_inst("neg"), t)
    when "inv"
      t = elab(x)
      one = mk_lit(1, fresh_meta)
      mark_numeric(one.ty, true)
      app2("/", one, t)
    else
      raise "unknown prefix operator " + op

  -> arith(name, l, r)
    a = elab(l)
    b = elab(r)
    t = app2(name, a, b)
    mark_numeric(tyof(a))
    t

  -> elab_binop(op, l, r)
    case op
    when "+", "-", "*", "/", "%"
      arith(op, l, r)
    when "^"
      a = elab(l)
      b = elab(r)
      unify(tyof(b), ty_nat)
      app2("^", a, b)
    when "<", "≤"
      arith(op, l, r)
    when ">"
      arith("<", r, l)
    when "≥"
      arith("≤", r, l)
    when "="
      app2("=", elab(l), elab(r))
    when "≠"
      mk_not(app2("=", elab(l), elab(r)))
    when "∧", "∨"
      app2(op, elab(l), elab(r))
    when "→"
      app2("⇒", elab(l), elab(r))
    when "↔"
      a = elab(l)
      unify(tyof(a), ty_bool)
      app2("=", a, elab(r))
    when "::"
      app2("cons", elab(l), elab(r))
    when "++"
      app2("append", elab(l), elab(r))
    when "∈"
      elab_mem(l, r)
    when "∉"
      mk_not(elab_mem(l, r))
    when "⊆"
      app2("subset", elab(l), elab(r))
    when "∣"
      app2("dvd", elab(l), elab(r))
    when "∪"
      app2("union", elab(l), elab(r))
    when "∩"
      app2("inter", elab(l), elab(r))
    when "∘"
      app2("comp", elab(l), elab(r))
    else
      raise "unknown operator " + op

  -> elab_mem(l, r)
    s = elab(r)
    x = elab(l)
    st = tyof(s)
    if st.tag == :c && st.name == "list"
      return app2("mem", x, s)
    if st.tag == :c && st.name == "finset"
      return app2("fmem", x, s)
    if st.tag == :c && st.name == "fun"
      return app(s, x)
    if meta?(st)
      unify(st, ty_fun(tyof(x), ty_bool))
      return app(s, x)
    raise "∈: right side is not a set or list: " + ty_show(st)

  -> binder_var(b)
    ty = nil
    if b.ty != nil
      ty = elab_type(b.ty)
    else
      ty = fresh_meta
    mk_var(b.name, ty)

  -> elab_lam(bs, body, i)
    if i >= bs.size
      return elab(body)
    v = binder_var(bs[i])
    push_local(bs[i].name, v)
    b = elab_lam(bs, body, i + 1)
    pop_local
    mk_lam(v, b)

  -> quant_of(q, v, body)
    lam = mk_lam(v, body)
    c = const_inst(q)
    app(c, lam)

  -> elab_quant(q, bs, body, i)
    if i >= bs.size
      p = elab(body)
      unify(tyof(p), ty_bool)
      return p
    b = bs[i]
    v = binder_var(b)
    guard = nil
    if b.rel != nil
      guard = elab_guard(v, b.rel, b.bound)
      # ∀ a < 5, …  with a literal bound: the binder defaults to ℕ (as decide expects), so a
      # later ascription (a : ℤ) inserts a coercion instead of retyping the binder
      if b.ty == nil && (b.rel == "<" || b.rel == "≤") && meta?(v.ty)
        unify(v.ty, ty_nat)
    push_local(b.name, v)
    inner = elab_quant(q, bs, body, i + 1)
    pop_local
    if q == "∃!"
      # ∃ x, P x ∧ ∀ y, P y → y = x
      px = inner
      if guard != nil
        px = app2("∧", guard, inner)
      y = mk_var(b.name + "'", v.ty)
      py = tm_instantiate(tm_abstract(px, v, 0), y, 0)
      uniq = quant_of("∀", y, app2("⇒", py, app2("=", y, v)))
      return quant_of("∃", v, app2("∧", px, uniq))
    if guard != nil
      if q == "∀"
        inner = app2("⇒", guard, inner)
      else
        inner = app2("∧", guard, inner)
    quant_of(q, v, inner)

  -> elab_guard(v, rel, bound_ast)
    push_local(v.name, v)
    bt = elab(bound_ast)
    pop_local
    case rel
    when "∈"
      st = tyof(bt)
      if st.tag == :c && st.name == "list"
        return app2("mem", v, bt)
      if st.tag == :c && st.name == "finset"
        return app2("fmem", v, bt)
      unify(st, ty_fun(v.ty, ty_bool))
      return app(bt, v)
    when "∉"
      return mk_not(app(bt, v))
    when "<"
      mark_numeric(v.ty)
      return app2("<", v, bt)
    when "≤"
      mark_numeric(v.ty)
      return app2("≤", v, bt)
    when ">"
      return app2("<", bt, v)
    when "≥"
      return app2("≤", bt, v)
    when "⊆"
      return app2("subset", v, bt)
    raise "unsupported bounded quantifier " + rel

  # ---- finalization ----------------------------------------------------------------

  # Applies the substitution, defaults numeric metas, and generalizes (or rejects)
  # remaining metas. Returns the closed-type term.
  -> finalize(t, generalize = true)
    @numeric.keys.each -> (m)
      r = resolve(ty_var(m))
      if meta?(r)
        if @fractional.has_key?(m) || @fractional.has_key?(r.name)
          @subst[r.name] = ty_rat
        else
          @subst[r.name] = ty_nat
    m = {}
    tm_tyvars(t).each -> (x)
      m[x] = resolve(ty_var(x))
    t2 = tm_inst_types(t, m)
    rest = {}
    gi = 0
    tm_tyvars(t2).each -> (x)
      if x.starts_with?("?")
        if !generalize
          raise "could not infer a type (ambiguous)"
        nm = "t" + gi.to_s
        while @type_params.include?(nm)
          gi += 1
          nm = "t" + gi.to_s
        rest[x] = ty_var(nm)
        gi += 1
    if rest.size > 0
      t2 = tm_inst_types(t2, rest)
    fix_lits(t2)

  -> final_type(ty)
    r = resolve(ty)
    m = {}
    ty_vars(r).each -> (x)
      if x.starts_with?("?")
        if @numeric.has_key?(x)
          m[x] = ty_nat
    ty_subst(r, m)

  -> fix_lits(t)
    case t.tag
    when :lit
      if (t.ty.name == "rat" || t.ty.name == "real") && t.val.class_name != "Array"
        return mk_lit([t.val, 1], t.ty)
      if (t.ty.name == "nat" || t.ty.name == "int") && t.val.class_name == "Array"
        raise "fractional literal used at an integer type"
      t
    when :app
      mk_app_raw(fix_lits(t.a), fix_lits(t.b))
    when :lam
      mk_lam_raw(t.name, t.ty, fix_lits(t.b))
    else
      t

  # Fully type-checks a finalized term (raises on error).
  -> check(t)
    case t.tag
    when :app
      check(t.a)
      check(t.b)
      mk_app(t.a, t.b)
    when :lam
      check(t.b)
    when :const
      @k.mk_const(t.name, t.ty)
    t

  # ---- top-level helpers ------------------------------------------------------------

  # Elaborates a proposition; with auto-binding, unknown names become ∀-variables.
  -> elab_prop(e, binders, auto)
    reset
    @allow_auto = auto
    vars = []
    hyps = []
    binders.each -> (b)
      if b.ty != nil && b.ty.kind == :either && !type_expr?(b.ty.kids[0])
        hyps.push(b)
      else
        v = binder_var(b)
        push_local(b.name, v)
        vars.push([b.name, v, :var])
    hyp_terms = []
    hyps.each -> (b)
      p = elab(b.ty.kids[0])
      unify(tyof(p), ty_bool)
      hyp_terms.push([b.name, p])
    body = elab(e)
    unify(tyof(body), ty_bool)
    @allow_auto = false
    # statement = ∀ autobound, ∀ vars, hyps → body
    stmt = body
    i = hyp_terms.size - 1
    while i >= 0
      stmt = app2("⇒", hyp_terms[i][1], stmt)
      i -= 1
    i = vars.size - 1
    while i >= 0
      stmt = quant_of("∀", vars[i][1], stmt)
      i -= 1
    i = @autobound.size - 1
    while i >= 0
      stmt = quant_of("∀", @autobound[i][1], stmt)
      i -= 1
    intro_names = []
    @autobound.each -> (p)
      intro_names.push(p[0])
    vars.each -> (p)
      intro_names.push(p[0])
    hyp_terms.each -> (p)
      intro_names.push(p[0])
    final = finalize(stmt, true)
    check(final)
    [final, intro_names]

  -> elab_term(e, expected = nil)
    reset
    t = elab(e)
    if expected != nil
      unify(tyof(t), expected)
    f = finalize(t, true)
    check(f)
    f

  # Elaborates an expression inside a proof, with fixed local variables in scope.
  -> elab_in(e, locals, expected = nil)
    reset
    locals.each -> (p)
      push_local(p[0], p[1])
    t = elab(e)
    if expected != nil
      unify(tyof(t), expected)
    f = finalize(t, false)
    check(f)
    f

+ Elab
  # λ with binder types taken from the expected function type when not given.
  -> elab_lam_expected(bs, body, i, exp)
    if i >= bs.size
      return elab(body)
    e = resolve(exp)
    v = nil
    if bs[i].ty == nil && e.fun?
      v = mk_var(bs[i].name, e.dom)
    else
      v = binder_var(bs[i])
    push_local(bs[i].name, v)
    nexp = fresh_meta
    if e.fun?
      nexp = e.cod
    b = elab_lam_expected(bs, body, i + 1, nexp)
    pop_local
    mk_lam(v, b)
