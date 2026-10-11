# Satori session: runs commands, keeps the environment of theorems, simp
# rules, equation lemmas and induction principles, and reports results.

+ Session
  ro :k, :d, :elab, :theorems, :simp_rules, :messages, :stats, :root
  rw :prelude_mode, :quiet, :only

  -> new(@root)
    @k = KKernel.new
    kernel_bootstrap(@k)
    @d = Derived.new(@k)
    @elab = Elab.new(@k)
    @theorems = {}
    @order = []
    @simp_rules = []
    @eqns = {}
    @induction = {}
    @loaded = {}
    @messages = []
    @prelude_mode = false
    @quiet = false
    @stats = {"theorems" => 0, "defs" => 0, "axioms" => 0, "lines" => 0}
    @failures = 0
    @current_dir = "."
    @only = nil
    @thm_index = 0

  -> failures
    @failures

  -> solver_path
    @root + "/bits/tungsten-wassat/bin/wassat"

  -> cache_dir
    @root + "/bits/tungsten-satori/.satori-cache"

  -> prelude_dir
    @root + "/bits/tungsten-satori/prelude"

  -> say(s)
    @messages.push(s)
    if !@quiet
      << s

  -> theorem(name)
    if @theorems.has_key?(name)
      return @theorems[name]
    if @k.axioms.has_key?(name)
      return @k.axioms[name]
    if @k.defs.has_key?(name)
      return @k.defs[name]
    nil

  -> add_theorem(name, th)
    @theorems[name] = th
    @order.push(name)

  # Monomorphic lemma lookup: "name.int", "name.nat", ... or polymorphic "name".
  -> lemma_at(base, ty)
    nm = base + "." + ty.name
    if @theorems.has_key?(nm)
      return @theorems[nm]
    if @theorems.has_key?(base)
      th = @theorems[base]
      return th
    nil

  -> induction_thm(ty)
    if ty.tag != :c
      return nil
    if @induction.has_key?(ty.name)
      return @induction[ty.name]
    if ty.name == "nat"
      return @k.axiom("nat_induct")
    if @k.axioms.has_key?(ty.name + "_induct")
      return @k.axioms[ty.name + "_induct"]
    nil

  -> eqns_of(name)
    if @eqns.has_key?(name)
      return @eqns[name]
    []

  # ---- files ---------------------------------------------------------------------------

  -> load_prelude
    old = @prelude_mode
    @prelude_mode = true
    run_import("prelude")
    @prelude_mode = old

  -> run_file(path)
    src = File.read(path)
    old_dir = @current_dir
    @current_dir = path_dirname(path)
    run_source(src)
    @current_dir = old_dir

  -> run_import(name)
    if @loaded.has_key?(name)
      return
    @loaded[name] = true
    cand = [prelude_dir + "/" + name.gsub(".", "/") + ".sat", @current_dir + "/" + name + ".sat"]
    found = nil
    cand.each -> (c)
      if found == nil && File.exist?(c)
        found = c
    if found == nil
      raise "import: cannot find " + name
    inprel = found.starts_with?(prelude_dir)
    old = @prelude_mode
    oldq = @quiet
    if inprel
      @prelude_mode = true
      @quiet = true
    run_file(found)
    @prelude_mode = old
    @quiet = oldq

  -> run_source(src)
    cmds = parse_program(src)
    @stats["lines"] = @stats["lines"] + src.split("\n").size
    cmds.each -> (c)
      target = false
      if @only != nil && !@prelude_mode
        if c.kind == :theorem || (c.kind == :attr && c.body != nil && c.body.kind == :theorem)
          target = @thm_index + 1 == @only
      if target
        << "⟦" + @only.to_s + "⟧"
      begin
        exec(c)
      rescue e
        @failures += 1
        << ("✗ line " + c.line.to_s + " (" + c.kind.to_s + " " + c.name.to_s + "): " + e.to_s)
      if target
        << "⟦/" + @only.to_s + "⟧"

  # ---- commands ------------------------------------------------------------------------

  -> exec(c)
    case c.kind
    when :import
      run_import(c.name)
    when :inductive
      exec_inductive(c)
    when :structure
      exec_structure(c)
    when :def
      exec_def(c)
    when :axiom
      exec_axiom(c)
    when :opaque
      @elab.reset
      ty = @elab.elab_type(c.ty)
      @k.declare_const(c.name, ty)
      say("✓ opaque " + c.name + " : " + ty_show(ty))
    when :theorem
      exec_theorem(c)
    when :hash
      exec_hash(c)
    when :attr
      exec(c.body)
    when :parse_error
      raise c.text
    else
      raise "unknown command"

  -> exec_inductive(c)
    @elab.reset
    params = c.params
    self_ty = ty_con(c.name, params.map ->(p) ty_var(p))
    @elab.set_pending(c.name, params)
    ctors = []
    c.ctors.each -> (ct)
      args = []
      ct[1].each -> (a)
        args.push(@elab.elab_type(a[1]))
      ctors.push([ct[0], args])
    @elab.set_pending(nil, [])
    @k.inductive(c.name, params, ctors)
    @stats["defs"] = @stats["defs"] + 1
    # distinctness facts are good simp rules
    @k.axioms.keys.each -> (nm)
      if nm.starts_with?(c.name + "_distinct_")
        @simp_rules.push(make_rule(@d, @k.axioms[nm], nm))
    say("✓ inductive " + c.name)

  -> exec_structure(c)
    exec_inductive(c)
    ct = c.ctors[0]
    fields = []
    ct[1].each -> (f)
      fields.push(f[0])
    info = @k.inductives[c.name]
    self_ty = ty_con(c.name, c.params.map ->(p) ty_var(p))
    arg_tys = info.ctors[0][1]
    i = 0
    while i < fields.size
      # proj = λ p. T_rec (λ f1 .. fn. fi) p
      vs = []
      j = 0
      while j < arg_tys.size
        vs.push(mk_var("f" + j.to_s, arg_tys[j]))
        j += 1
      case_f = mk_lams(vs, vs[i])
      rt = arg_tys[i]
      rec = mk_const_raw(info.rec_name, ty_funs([type_of(case_f), self_ty], rt))
      pv = mk_var("p", self_ty)
      body = mk_lam(pv, mk_apps(rec, [case_f, pv]))
      pname = c.name + "." + fields[i]
      @k.define(pname, body)
      # projection equation: T.f (T.mk x1 .. xn) = xi
      xs = []
      j = 0
      while j < arg_tys.size
        xs.push(mk_var(fields[j], arg_tys[j]))
        j += 1
      lhs = mk_app(mk_const_raw(pname, ty_fun(self_ty, rt)), mk_apps(mk_const_raw(ct[0], ty_funs(arg_tys, self_ty)), xs))
      eq = eq_by_compute(lhs, xs[i])
      th = @d.gen_all(xs, eq)
      add_theorem(pname + ".mk", th)
      @simp_rules.push(make_rule(@d, th, pname))
      i += 1
    @elab.register_fields(c.name, ct[0], fields)

  # ⊢ lhs = rhs when both sides evaluate to the same normal form.
  -> eq_by_compute(lhs, rhs)
    a = @k.compute(lhs, true)
    b = @k.compute(rhs, true)
    va = dest_binop(a.concl, "=")[1]
    vb = dest_binop(b.concl, "=")[1]
    if !tm_eq(va, vb)
      raise "equation does not hold by computation: " + tm_show(va) + " vs " + tm_show(vb)
    @k.trans(a, @k.sym(b))

  -> exec_def(c)
    if c.eqns.size > 0
      return exec_pattern_def(c)
    # fun binders => body, with the declared result type
    lam = c.body
    if c.binders.size > 0
      lam = ast(:lam, "", [c.body])
      lam.binders = c.binders
    @elab.reset
    @elab.type_params_from(c)
    t = @elab.elab(lam)
    if c.ty != nil
      rt = @elab.elab_type(c.ty)
      ft = rt
      i = c.binders.size - 1
      while i >= 0
        b = c.binders[i]
        bt = nil
        if b.ty != nil
          bt = @elab.elab_type(b.ty)
        else
          bt = @elab.fresh_meta
        ft = ty_fun(bt, ft)
        i -= 1
      @elab.unify(@elab.tyof(t), ft)
    body = @elab.finalize(t, true)
    @elab.check(body)
    th = @k.define(c.name, body)
    # equation lemma: ∀ xs, name xs = body
    vars = []
    cur = body
    nm_avoid = [body]
    while cur.tag == :lam
      p = dest_lam_fresh(cur, nm_avoid)
      vars.push(p[0])
      nm_avoid.push(p[0])
      cur = p[1]
    if vars.size > 0
      ct = mk_const_raw(c.name, type_of(body))
      lhs = mk_apps(ct, vars)
      eq = @d.ap_thm_all(th, vars)
      eq = @k.trans(eq, @d.beta_norm_conv(dest_binop(eq.concl, "=")[1]))
      eqg = @d.gen_all(vars, eq)
      @eqns[c.name] = [eqg]
      add_theorem(c.name + ".def", eqg)
    else
      @eqns[c.name] = [th]
    @stats["defs"] = @stats["defs"] + 1
    say("✓ def " + c.name + " : " + ty_show(type_of(body)))

  -> exec_pattern_def(c)
    pd = PatternDef.new(self, c)
    pd.compile
    @stats["defs"] = @stats["defs"] + 1
    say("✓ def " + c.name + " : " + ty_show(@k.const_type(c.name)))

  -> exec_axiom(c)
    r = @elab.elab_prop(c.ty, c.binders, true)
    th = @k.new_axiom(c.name, r[0], @prelude_mode)
    add_theorem(c.name, th)
    if c.text == "simp"
      @simp_rules.push(make_rule(@d, th, c.name))
    @stats["axioms"] = @stats["axioms"] + 1
    if !@prelude_mode
      say("⚠ axiom " + c.name + " : " + tm_show(r[0]))

  -> exec_theorem(c)
    r = @elab.elab_prop(c.ty, c.binders, true)
    stmt = r[0]
    names = r[1]
    th = nil
    if @only != nil && !@prelude_mode
      @thm_index += 1
      if @thm_index != @only
        # split mode: another process checks this theorem
        th = @k.admit_split(stmt, c.name)
        add_theorem(c.name, th)
        if c.text == "simp"
          @simp_rules.push(make_rule(@d, th, c.name))
        @stats["theorems"] = @stats["theorems"] + 1
        say("⋯ split " + c.name)
        return
    if c.tactics != nil
      th = prove_with_tactics(stmt, names, c.tactics)
    elsif c.body != nil
      p = Prover.new(self)
      g = Goal.new([], [], stmt)
      th = p.fit(GoalRef.new(g, nil, 0), p.proof_ast(g, c.body, stmt))
    else
      raise "theorem without proof"
    if th.hyps.size > 0
      raise "proof leaves assumptions: " + tm_show(th.hyps[0])
    if !tm_eq(th.concl, stmt)
      raise "proved statement differs from the claim"
    add_theorem(c.name, th)
    if c.text == "simp"
      @simp_rules.push(make_rule(@d, th, c.name))
    @stats["theorems"] = @stats["theorems"] + 1
    trust = ""
    if th.tags.size > 0
      trust = "   \[" + th.tags.join(", ") + "\]"
    if c.name != "_example" || true
      say("✓ " + c.name + " : " + tm_show(stmt) + trust)

  -> prove_with_tactics(stmt, names, tactics)
    p = Prover.new(self)
    root = GoalRef.new(Goal.new([], [], stmt), nil, 0)
    p.goals = [root]
    cur = root
    names.each -> (nm)
      cur = p.intro1(cur, nm)
    p.run_block(tactics)
    if p.goals.size > 0
      raise "unsolved goals:\n" + p.goals[0].goal.show(@k)
    root.thm

  -> exec_hash(c)
    case c.name
    when "check"
      t = @elab.elab_term(parse_expr_toks(c.body))
      say(tm_show(t) + " : " + ty_show(type_of(t)))
    when "eval"
      t = @elab.elab_term(parse_expr_toks(c.body))
      th = @k.compute(t)
      say(tm_show(dest_binop(th.concl, "=")[1]))
    when "print"
      nm = c.body[0].text
      th = theorem(nm)
      if th == nil
        say(nm + " : " + ty_show(@k.const_type(nm)))
      else
        say(nm + " : " + tm_show(th.concl))
    when "axioms"
      nm = c.body[0].text
      th = theorem(nm)
      if th.tags.size == 0
        say(nm + " depends only on the foundational kernel")
      else
        say(nm + " depends on: " + th.tags.join(", "))
    when "stats"
      say(stats_line)
    else
      raise "unknown command #" + c.name

  -> stats_line
    @stats["theorems"].to_s + " theorems, " + @stats["defs"].to_s + " definitions, " + @stats["axioms"].to_s + " axioms"

# Derived helper used by definitions.
+ Derived
  -> ap_thm_all(th, xs)
    t = th
    xs.each -> (x)
      t = ap_thm(t, x)
    t

+ Elab
  -> set_pending(name, params)
    @pending = name
    @pending_params = params

  -> type_params_from(c)
    @type_params = []

-> path_dirname(path)
  i = path.size - 1
  cs = path.chars
  i = cs.size - 1
  while i >= 0 && cs[i] != "/"
    i -= 1
  if i < 0
    return "."
  if i == 0
    return "/"
  arr_sub(cs, 0, i).join("")
