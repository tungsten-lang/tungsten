# The Satori kernel — the trusted base.
#
# Classical higher-order logic (simple types with polymorphism) presented as
# natural deduction. A theorem is a sequent `hyps ⊢ concl` plus a sorted list
# of trust tags naming every non-foundational axiom and oracle it depends on.
# Only the methods of KKernel construct theorems; tactics, the elaborator and
# all automation live outside this file and can only call these rules.
#
# Trusted components, all in this file:
#   * the inference rules below;
#   * definitional extension (closed definitions, inductive datatypes with
#     primitive recursion), which is conservative;
#   * the evaluator `compute`, which only applies beta, literal arithmetic,
#     unfolding of computational definitions, recursor (iota) reduction,
#     constructor (in)equality and the boolean connectives;
#   * three checkers (tags): `sat` (LRAT refutation check of a literal CNF),
#     `ring` (commutative-ring normal form), `arith` (Farkas certificates).

+ KThm
  ro :hyps, :concl, :tags

  -> new(@hyps, @concl, @tags)

  -> to_s
    s = ""
    if @hyps.size > 0
      parts = []
      @hyps.each -> (h)
        parts.push(tm_show(h))
      s = parts.join(", ") + " "
    s + "⊢ " + tm_show(@concl)

-> hyps_union(a, b)
  out = []
  a.each -> (t)
    out.push(t)
  b.each -> (t)
    if !hyps_has?(out, t)
      out.push(t)
  out

-> hyps_has?(hs, t)
  hs.each -> (u)
    if tm_eq(u, t)
      return true
  false

-> hyps_remove(hs, t)
  out = []
  hs.each -> (u)
    if !tm_eq(u, t)
      out.push(u)
  out

-> tags_union(a, b)
  if b.size == 0
    return a
  if a.size == 0
    return b
  out = []
  a.each -> (x)
    out.push(x)
  b.each -> (x)
    if !out.include?(x)
      out.push(x)
  out.sort

+ KInductive
  ro :name, :params, :ctors, :rec_name
  # ctors: array of [name, arg_types (with the type itself as ty_con(name, params))]
  -> new(@name, @params, @ctors, @rec_name)

+ KKernel
  ro :consts, :types, :axioms, :defs, :inductives, :foundational, :ctor_of

  -> new
    @types = {}
    @consts = {}
    @axioms = {}
    @foundational = {}
    @defs = {}
    @inductives = {}
    @ctor_of = {}
    @types["bool"] = 0
    @types["fun"] = 2
    @types["nat"] = 0
    @types["int"] = 0
    @types["rat"] = 0
    @types["real"] = 0
    a = ty_var("a")
    b = ty_bool
    @consts["="] = ty_funs([a, a], b)
    @consts["⇒"] = ty_funs([b, b], b)
    @consts["∧"] = ty_funs([b, b], b)
    @consts["∨"] = ty_funs([b, b], b)
    @consts["¬"] = ty_fun(b, b)
    @consts["⊤"] = b
    @consts["⊥"] = b
    @consts["∀"] = ty_fun(ty_fun(a, b), b)
    @consts["∃"] = ty_fun(ty_fun(a, b), b)
    @consts["ε"] = ty_fun(ty_fun(a, b), a)
    @consts["ite"] = ty_funs([b, a, a], a)
    n = ty_nat
    @consts["succ"] = ty_fun(n, n)
    @consts["nat_rec"] = ty_funs([a, ty_funs([n, a], a), n], a)
    # overloaded arithmetic: instances at nat/int/rat/real are axiomatized
    @consts["+"] = ty_funs([a, a], a)
    @consts["-"] = ty_funs([a, a], a)
    @consts["*"] = ty_funs([a, a], a)
    @consts["/"] = ty_funs([a, a], a)
    @consts["%"] = ty_funs([a, a], a)
    @consts["^"] = ty_funs([a, ty_nat], a)
    @consts["neg"] = ty_fun(a, a)
    @consts["abs"] = ty_fun(a, a)
    @consts["<"] = ty_funs([a, a], b)
    @consts["≤"] = ty_funs([a, a], b)
    @consts["int_of_nat"] = ty_fun(ty_nat, ty_int)
    @consts["rat_of_int"] = ty_fun(ty_int, ty_rat)
    @consts["real_of_rat"] = ty_fun(ty_rat, ty_real)
    @consts["nat_of_int"] = ty_fun(ty_int, ty_nat)
    @consts["floor"] = ty_fun(ty_rat, ty_int)
    @numeric = ["nat", "int", "rat", "real"]

  # ---- signature ---------------------------------------------------------

  -> const_type(name)
    if !@consts.has_key?(name)
      raise "unknown constant " + name
    @consts[name]

  -> has_const?(name)
    @consts.has_key?(name)

  # Instance of a constant at a type; checks it is an instance of the generic type.
  -> mk_const(name, ty)
    g = const_type(name)
    m = {}
    if !ty_match(g, ty, m)
      raise "constant " + name + " : " + ty_show(g) + " cannot have type " + ty_show(ty)
    mk_const_raw(name, ty)

  -> declare_type(name, arity)
    if @types.has_key?(name)
      raise "type " + name + " already declared"
    @types[name] = arity

  -> declare_const(name, ty)
    if @consts.has_key?(name)
      raise "constant " + name + " already declared"
    @consts[name] = ty

  # ---- helpers -------------------------------------------------------------

  -> eq_tm(l, r)
    t = type_of(l)
    mk_app_raw(mk_app_raw(mk_const_raw("=", ty_funs([t, t], ty_bool)), l), r)

  -> bin(name, l, r)
    mk_app_raw(mk_app_raw(mk_const_raw(name, ty_funs([ty_bool, ty_bool], ty_bool)), l), r)

  -> neg_tm(p)
    mk_app_raw(mk_const_raw("¬", ty_fun(ty_bool, ty_bool)), p)

  -> truth_tm
    mk_const_raw("⊤", ty_bool)

  -> false_tm
    mk_const_raw("⊥", ty_bool)

  -> quant(name, v, body)
    lam = mk_lam(v, body)
    mk_app_raw(mk_const_raw(name, ty_fun(ty_fun(v.ty, ty_bool), ty_bool)), lam)

  -> dest_eq(t)
    dest_binop(t, "=")

  -> need_bool(t, who)
    if !ty_eq(type_of(t), ty_bool)
      raise who + ": not a proposition: " + tm_show(t)

  -> thm(hyps, concl, tags)
    KThm.new(hyps, concl, tags)

  # ---- primitive rules ------------------------------------------------------

  -> assume(p)
    need_bool(p, "assume")
    if !tm_closed_bound?(p)
      raise "assume: term has loose bound variables"
    thm([p], p, [])

  -> refl(t)
    thm([], eq_tm(t, t), [])

  -> trans(th1, th2)
    e1 = dest_eq(th1.concl)
    e2 = dest_eq(th2.concl)
    if e1 == nil || e2 == nil
      raise "trans: not equations"
    if !tm_eq(e1[1], e2[0])
      raise "trans: middle terms differ: " + tm_show(e1[1]) + " vs " + tm_show(e2[0])
    thm(hyps_union(th1.hyps, th2.hyps), eq_tm(e1[0], e2[1]), tags_union(th1.tags, th2.tags))

  -> sym(th)
    e = dest_eq(th.concl)
    if e == nil
      raise "sym: not an equation"
    thm(th.hyps, eq_tm(e[1], e[0]), th.tags)

  -> mk_comb(th1, th2)
    e1 = dest_eq(th1.concl)
    e2 = dest_eq(th2.concl)
    if e1 == nil || e2 == nil
      raise "mk_comb: not equations"
    l = mk_app(e1[0], e2[0])
    r = mk_app(e1[1], e2[1])
    thm(hyps_union(th1.hyps, th2.hyps), eq_tm(l, r), tags_union(th1.tags, th2.tags))

  -> abs_rule(v, th)
    if v.tag != :var
      raise "abs: binder must be a variable"
    e = dest_eq(th.concl)
    if e == nil
      raise "abs: not an equation"
    th.hyps.each -> (h)
      if tm_free_in?(v, h)
        raise "abs: variable " + v.name + " is free in a hypothesis"
    thm(th.hyps, eq_tm(mk_lam(v, e[0]), mk_lam(v, e[1])), th.tags)

  -> beta(t)
    if t.tag != :app || t.a.tag != :lam
      raise "beta: not a redex: " + tm_show(t)
    if !ty_eq(t.a.ty, type_of(t.b))
      raise "beta: ill-typed redex"
    thm([], eq_tm(t, beta_head(t)), [])

  -> eta(t)
    if t.tag != :lam || t.b.tag != :app || t.b.b.tag != :bnd || t.b.b.idx != 0
      raise "eta: not an eta redex"
    f = t.b.a
    if lam_count_bound(f, 0)
      raise "eta: bound variable occurs in function"
    thm([], eq_tm(t, f), [])

  -> eq_mp(th1, th2)
    e = dest_eq(th1.concl)
    if e == nil || !ty_eq(type_of(e[0]), ty_bool)
      raise "eq_mp: not a propositional equation"
    if !tm_eq(e[0], th2.concl)
      raise "eq_mp: mismatch: " + tm_show(e[0]) + " vs " + tm_show(th2.concl)
    thm(hyps_union(th1.hyps, th2.hyps), e[1], tags_union(th1.tags, th2.tags))

  -> deduct_antisym(th1, th2)
    h = hyps_union(hyps_remove(th1.hyps, th2.concl), hyps_remove(th2.hyps, th1.concl))
    thm(h, eq_tm(th1.concl, th2.concl), tags_union(th1.tags, th2.tags))

  # m: array of [var, term]
  -> inst(th, pairs)
    if pairs.size == 0
      return th
    m = {}
    pairs.each -> (p)
      v = p[0]
      t = p[1]
      if v.tag != :var
        raise "inst: can only instantiate variables"
      if !ty_eq(v.ty, type_of(t))
        raise "inst: type mismatch for " + v.name
      m[var_key(v)] = t
    hs = []
    th.hyps.each -> (h)
      hs.push(tm_subst(h, m))
    thm(hs, tm_subst(th.concl, m), th.tags)

  # m: Hash tyvar name -> KTy
  -> inst_type(th, m)
    hs = []
    th.hyps.each -> (h)
      hs.push(tm_inst_types(h, m))
    thm(hs, tm_inst_types(th.concl, m), th.tags)

  -> disch(p, th)
    need_bool(p, "disch")
    thm(hyps_remove(th.hyps, p), bin("⇒", p, th.concl), th.tags)

  -> mp(th1, th2)
    pq = dest_binop(th1.concl, "⇒")
    if pq == nil
      raise "mp: not an implication: " + tm_show(th1.concl)
    if !tm_eq(pq[0], th2.concl)
      raise "mp: antecedent mismatch: " + tm_show(pq[0]) + " vs " + tm_show(th2.concl)
    thm(hyps_union(th1.hyps, th2.hyps), pq[1], tags_union(th1.tags, th2.tags))

  -> gen(v, th)
    if v.tag != :var
      raise "gen: not a variable"
    th.hyps.each -> (h)
      if tm_free_in?(v, h)
        raise "gen: " + v.name + " is free in hypothesis " + tm_show(h)
    thm(th.hyps, quant("∀", v, th.concl), th.tags)

  -> spec(t, th)
    q = dest_unop(th.concl, "∀")
    if q == nil || q.tag != :lam
      raise "spec: not a universal: " + tm_show(th.concl)
    if !ty_eq(q.ty, type_of(t))
      raise "spec: type mismatch instantiating " + tm_show(th.concl) + " with " + tm_show(t)
    thm(th.hyps, tm_instantiate(q.b, t, 0), th.tags)

  # goal: ∃-term `ex` (∃ applied to λ); witness t; th ⊢ body[t]
  -> exists_intro(ex, t, th)
    q = dest_unop(ex, "∃")
    if q == nil || q.tag != :lam
      raise "exists_intro: not an existential"
    if !ty_eq(q.ty, type_of(t))
      raise "exists_intro: witness has wrong type"
    if !tm_eq(tm_instantiate(q.b, t, 0), th.concl)
      raise "exists_intro: theorem does not match instantiated body"
    thm(th.hyps, ex, th.tags)

  # th_ex ⊢ ∃x. P x ; th has hypothesis P v ; v fresh.
  -> choose(v, th_ex, th)
    q = dest_unop(th_ex.concl, "∃")
    if q == nil || q.tag != :lam
      raise "choose: not an existential"
    if v.tag != :var || !ty_eq(v.ty, q.ty)
      raise "choose: bad witness variable"
    pv = tm_instantiate(q.b, v, 0)
    if tm_free_in?(v, th.concl) || tm_free_in?(v, th_ex.concl)
      raise "choose: witness variable escapes"
    rest = hyps_remove(th.hyps, pv)
    rest.each -> (h)
      if tm_free_in?(v, h)
        raise "choose: witness variable free in another hypothesis"
    th_ex.hyps.each -> (h)
      if tm_free_in?(v, h)
        raise "choose: witness variable free in existential's hypotheses"
    thm(hyps_union(th_ex.hyps, rest), th.concl, tags_union(th_ex.tags, th.tags))

  -> conj(th1, th2)
    thm(hyps_union(th1.hyps, th2.hyps), bin("∧", th1.concl, th2.concl), tags_union(th1.tags, th2.tags))

  -> conj1(th)
    pq = dest_binop(th.concl, "∧")
    if pq == nil
      raise "conj1: not a conjunction"
    thm(th.hyps, pq[0], th.tags)

  -> conj2(th)
    pq = dest_binop(th.concl, "∧")
    if pq == nil
      raise "conj2: not a conjunction"
    thm(th.hyps, pq[1], th.tags)

  -> disj1(th, q)
    need_bool(q, "disj1")
    thm(th.hyps, bin("∨", th.concl, q), th.tags)

  -> disj2(p, th)
    need_bool(p, "disj2")
    thm(th.hyps, bin("∨", p, th.concl), th.tags)

  -> disj_cases(th, th1, th2)
    pq = dest_binop(th.concl, "∨")
    if pq == nil
      raise "disj_cases: not a disjunction"
    if !tm_eq(th1.concl, th2.concl)
      raise "disj_cases: branch conclusions differ"
    h = hyps_union(th.hyps, hyps_union(hyps_remove(th1.hyps, pq[0]), hyps_remove(th2.hyps, pq[1])))
    thm(h, th1.concl, tags_union(th.tags, tags_union(th1.tags, th2.tags)))

  # th: Γ ⊢ ⊥  ->  Γ - {p} ⊢ ¬p
  -> not_intro(p, th)
    if !is_const?(th.concl, "⊥")
      raise "not_intro: conclusion is not ⊥"
    thm(hyps_remove(th.hyps, p), neg_tm(p), th.tags)

  -> not_elim(th1, th2)
    p = dest_unop(th1.concl, "¬")
    if p == nil
      raise "not_elim: not a negation"
    if !tm_eq(p, th2.concl)
      raise "not_elim: mismatch"
    thm(hyps_union(th1.hyps, th2.hyps), false_tm, tags_union(th1.tags, th2.tags))

  -> false_elim(th, p)
    if !is_const?(th.concl, "⊥")
      raise "false_elim: conclusion is not ⊥"
    need_bool(p, "false_elim")
    thm(th.hyps, p, th.tags)

  -> truth
    thm([], truth_tm, [])

  -> excluded_middle(p)
    need_bool(p, "excluded_middle")
    thm([], bin("∨", p, neg_tm(p)), [])

  # pl = λx. body ; th ⊢ body[x0]  ->  ⊢ body[ε pl]
  -> select_rule(pl, x0, th)
    if pl.tag != :lam || !ty_eq(type_of(pl), ty_fun(pl.ty, ty_bool))
      raise "select: predicate must be a lambda"
    if !tm_eq(tm_instantiate(pl.b, x0, 0), th.concl)
      raise "select: theorem does not match predicate"
    e = mk_app_raw(mk_const_raw("ε", ty_fun(ty_fun(pl.ty, ty_bool), pl.ty)), pl)
    thm(th.hyps, tm_instantiate(pl.b, e, 0), th.tags)

  # ---- definitions and axioms ---------------------------------------------

  -> define(name, rhs)
    if @consts.has_key?(name)
      raise "constant " + name + " already exists"
    if tm_frees(rhs).size > 0
      raise "definition of " + name + " has free variables"
    if !tm_closed_bound?(rhs)
      raise "definition of " + name + " has loose bound variables"
    ty = type_of(rhs)
    tv = ty_vars(ty)
    tm_tyvars(rhs).each -> (x)
      if !tv.include?(x)
        raise "definition of " + name + " has a type variable not in its type"
    @consts[name] = ty
    c = mk_const_raw(name, ty)
    th = thm([], eq_tm(c, rhs), [])
    @defs[name] = th
    th

  -> new_axiom(name, p, foundational = false)
    need_bool(p, "axiom")
    if tm_frees(p).size > 0
      raise "axiom " + name + " has free variables"
    tags = []
    if foundational
      @foundational[name] = true
    else
      tags = ["axiom:" + name]
    th = thm([], p, tags)
    @axioms[name] = th
    th

  -> axiom(name)
    if !@axioms.has_key?(name)
      raise "no axiom " + name
    @axioms[name]

  # Inductive datatype. params: tyvar names; ctors: array of [cname, [arg types]]
  # where recursive arguments are exactly ty_con(name, params). Returns the
  # KInductive record; constructors, recursor and the axioms
  #   <name>_rec_<ctor>, <name>_inj_<ctor>, <name>_distinct_<i>_<j>, <name>_induct
  # are registered.
  -> inductive(name, params, ctors)
    pvars = []
    params.each -> (p)
      pvars.push(ty_var(p))
    self_ty = ty_con(name, pvars)
    @types[name] = params.size
    ctors.each -> (c)
      c[1].each -> (at)
        if !ty_eq(at, self_ty) && ty_mentions_con(at, name)
          raise "inductive " + name + ": non-strictly-positive or nested occurrence in " + c[0]
      ty_vars(ty_funs(c[1], self_ty)).each -> (v)
        if !params.include?(v)
          raise "inductive " + name + ": constructor " + c[0] + " mentions unbound type variable"
    if ctors.size == 0
      raise "inductive " + name + " has no constructors"
    has_base = false
    ctors.each -> (c)
      rec = false
      c[1].each -> (at)
        if ty_eq(at, self_ty)
          rec = true
      if !rec
        has_base = true
    if !has_base
      raise "inductive " + name + " has no non-recursive constructor (empty type)"
    ctors.each -> (c)
      @consts[c[0]] = ty_funs(c[1], self_ty)
      @ctor_of[c[0]] = name
    # recursor: rec : (case_1) → ... → (case_k) → T → R
    rname = "r"
    rr = 0
    while params.include?(rname)
      rr += 1
      rname = "r" + rr.to_s
    r = ty_var(rname)
    case_tys = []
    ctors.each -> (c)
      args = []
      c[1].each -> (at)
        args.push(at)
      c[1].each -> (at)
        if ty_eq(at, self_ty)
          args.push(r)
      case_tys.push(ty_funs(args, r))
    rec_name = name + "_rec"
    @consts[rec_name] = ty_funs(case_tys + [self_ty], r)
    info = KInductive.new(name, params, ctors, rec_name)
    @inductives[name] = info
    kernel_inductive_axioms(self, info, self_ty, r, case_tys)
    info

  -> inductive_of_type(ty)
    if ty.tag == :c && @inductives.has_key?(ty.name)
      @inductives[ty.name]
    else
      nil

  # ---- trusted checkers ------------------------------------------------------

  # ⊢ t = v by evaluation.
  -> compute(t, deep = false)
    v = KEval.new(self, deep).eval(t)
    thm([], eq_tm(t, v), [])

  -> tagged(th, tag)
    thm(th.hyps, th.concl, tags_union(th.tags, [tag]))

  # An admitted goal; the `sorry` tag propagates to every dependent theorem.
  -> sorry_thm(p)
    need_bool(p, "sorry")
    thm([], p, ["sorry"])

  # ⊢ lhs = rhs when both sides have the same commutative-ring normal form.
  -> ring_eq(lhs, rhs)
    ty = type_of(lhs)
    if !["int", "rat", "real", "nat"].include?(ty.name)
      raise "ring: unsupported type " + ty_show(ty)
    a = ring_normal(lhs, ty.name)
    b = ring_normal(rhs, ty.name)
    if a == nil || b == nil || poly_key(a) != poly_key(b)
      raise "ring: sides are not equal as polynomials"
    thm([], eq_tm(lhs, rhs), ["oracle:ring"])

  # Unsatisfiability of a literal CNF, given an LRAT refutation text.
  -> sat_unsat(cnf_tm, lrat)
    clauses = cnf_literal_value(cnf_tm)
    if clauses == nil
      raise "sat: CNF term is not a literal list of clauses"
    if !lrat_check(clauses, lrat)
      raise "sat: LRAT refutation rejected"
    unsat = mk_const("cnf_unsat", ty_fun(type_of(cnf_tm), ty_bool))
    thm([], mk_app(unsat, cnf_tm), ["oracle:sat"])

  # Farkas certificate: theorems `a_i R_i b_i` (R ∈ <, ≤, =) at one ordered
  # numeric type and rational coefficients q_i (q_i ≥ 0 unless R_i is =) with
  # Σ q_i (b_i - a_i) a constant c where c < 0, or c = 0 and some strict
  # inequality has q_i > 0. Concludes ⊥ from the union of hypotheses.
  -> farkas(thms, coeffs)
    if thms.size == 0 || thms.size != coeffs.size
      raise "farkas: bad certificate shape"
    kind = nil
    total = {}
    strict_used = false
    hs = []
    tags = ["oracle:arith"]
    ctx = RingCtx.new("rat")
    i = 0
    while i < thms.size
      th = thms[i]
      q = coeffs[i]
      rel = nil
      ab = nil
      ["<", "≤", "="].each -> (r)
        if rel == nil
          d = dest_binop(th.concl, r)
          if d != nil
            rel = r
            ab = d
      if rel == nil
        raise "farkas: not a comparison: " + tm_show(th.concl)
      ty = type_of(ab[0])
      if !["nat", "int", "rat", "real"].include?(ty.name)
        raise "farkas: not an ordered numeric type"
      if kind == nil
        kind = ty.name
      if kind != ty.name
        raise "farkas: mixed numeric types"
      if rel != "=" && q[0] < 0
        raise "farkas: negative coefficient on an inequality"
      if rel == "<" && q[0] > 0
        strict_used = true
      pa = ring_norm(ab[0], kind, ctx)
      pb = ring_norm(ab[1], kind, ctx)
      diff = poly_add(pb, poly_scale(pa, [-1, 1]))
      total = poly_add(total, poly_scale(diff, q))
      hs = hyps_union(hs, th.hyps)
      tags = tags_union(tags, th.tags)
      i += 1
    c = [0, 1]
    total.keys.each -> (m)
      if m != ""
        raise "farkas: combination is not constant"
      c = total[m]
    if !(c[0] < 0 || (c[0] == 0 && strict_used))
      raise "farkas: combination is not contradictory"
    thm(hs, false_tm, tags)


-> ty_mentions_con(t, name)
  if t.tag == :v
    return false
  if t.name == name
    return true
  t.args.each -> (a)
    if ty_mentions_con(a, name)
      return true
  false

# Generates and registers the axioms of an inductive type.
-> kernel_inductive_axioms(k, info, self_ty, r, case_tys)
  name = info.name
  ctors = info.ctors
  rec_c = mk_const_raw(info.rec_name, k.const_type(info.rec_name))
  fs = []
  i = 0
  while i < case_tys.size
    fs.push(mk_var("f" + i.to_s, case_tys[i]))
    i += 1
  rec_applied = mk_apps(rec_c, fs)
  # recursion equations
  ci = 0
  while ci < ctors.size
    c = ctors[ci]
    xs = []
    j = 0
    while j < c[1].size
      xs.push(mk_var("x" + j.to_s, c[1][j]))
      j += 1
    ct = mk_apps(mk_const_raw(c[0], ty_funs(c[1], self_ty)), xs)
    rhs_args = []
    xs.each -> (x)
      rhs_args.push(x)
    xs.each -> (x)
      if ty_eq(x.ty, self_ty)
        rhs_args.push(mk_app(rec_applied, x))
    lhs = mk_app(rec_applied, ct)
    rhs = mk_apps(fs[ci], rhs_args)
    eqn = k.eq_tm(lhs, rhs)
    allv = fs + xs
    p = eqn
    vi = allv.size - 1
    while vi >= 0
      p = k.quant("∀", allv[vi], p)
      vi -= 1
    k.new_axiom(name + "_rec_" + c[0], p, true)
    ci += 1
  # injectivity
  ctors.each -> (c)
    if c[1].size > 0
      xs = []
      ys = []
      j = 0
      while j < c[1].size
        xs.push(mk_var("x" + j.to_s, c[1][j]))
        ys.push(mk_var("y" + j.to_s, c[1][j]))
        j += 1
      cc = mk_const_raw(c[0], ty_funs(c[1], self_ty))
      lhs = k.eq_tm(mk_apps(cc, xs), mk_apps(cc, ys))
      conc = nil
      j = c[1].size - 1
      while j >= 0
        e = k.eq_tm(xs[j], ys[j])
        if conc == nil
          conc = e
        else
          conc = k.bin("∧", e, conc)
        j -= 1
      p = k.bin("⇒", lhs, conc)
      allv = xs + ys
      vi = allv.size - 1
      while vi >= 0
        p = k.quant("∀", allv[vi], p)
        vi -= 1
      k.new_axiom(name + "_inj_" + c[0], p, true)
  # distinctness
  a = 0
  while a < ctors.size
    b = a + 1
    while b < ctors.size
      ca = ctors[a]
      cb = ctors[b]
      xs = []
      j = 0
      while j < ca[1].size
        xs.push(mk_var("x" + j.to_s, ca[1][j]))
        j += 1
      ys = []
      j = 0
      while j < cb[1].size
        ys.push(mk_var("y" + j.to_s, cb[1][j]))
        j += 1
      ta = mk_apps(mk_const_raw(ca[0], ty_funs(ca[1], self_ty)), xs)
      tb = mk_apps(mk_const_raw(cb[0], ty_funs(cb[1], self_ty)), ys)
      p = k.neg_tm(k.eq_tm(ta, tb))
      allv = xs + ys
      vi = allv.size - 1
      while vi >= 0
        p = k.quant("∀", allv[vi], p)
        vi -= 1
      k.new_axiom(name + "_distinct_" + ca[0] + "_" + cb[0], p, true)
      b += 1
    a += 1
  # induction: ∀P. (case premises) ⇒ ∀t. P t
  pv = mk_var("P", ty_fun(self_ty, ty_bool))
  prem = []
  ctors.each -> (c)
    xs = []
    j = 0
    while j < c[1].size
      xs.push(mk_var("x" + j.to_s, c[1][j]))
      j += 1
    ct = mk_apps(mk_const_raw(c[0], ty_funs(c[1], self_ty)), xs)
    body = mk_app(pv, ct)
    ihs = []
    xs.each -> (x)
      if ty_eq(x.ty, self_ty)
        ihs.push(mk_app(pv, x))
    hi = ihs.size - 1
    while hi >= 0
      body = k.bin("⇒", ihs[hi], body)
      hi -= 1
    vi = xs.size - 1
    while vi >= 0
      body = k.quant("∀", xs[vi], body)
      vi -= 1
    prem.push(body)
  tv = mk_var("t", self_ty)
  concl = k.quant("∀", tv, mk_app(pv, tv))
  pi = prem.size - 1
  while pi >= 0
    concl = k.bin("⇒", prem[pi], concl)
    pi -= 1
  k.new_axiom(name + "_induct", k.quant("∀", pv, concl), true)
  0

# ---------------------------------------------------------------------------
# Bootstrap: Peano axioms for ℕ, lists, and the canonical CNF semantics that
# the `sat` checker certifies. Installed by the kernel itself so no user
# definition can change what `cnf_unsat` means.

-> kernel_bootstrap(k)
  n = ty_nat
  b = ty_bool
  a = ty_var("a")
  zero = mk_nat(0)
  succ = mk_const_raw("succ", ty_fun(n, n))
  mv = mk_var("m", n)
  nv = mk_var("n", n)
  pv = mk_var("P", ty_fun(n, b))
  # induction
  step = k.quant("∀", nv, k.bin("⇒", mk_app(pv, nv), mk_app(pv, mk_app(succ, nv))))
  ind = k.bin("⇒", mk_app(pv, zero), k.bin("⇒", step, k.quant("∀", nv, mk_app(pv, nv))))
  k.new_axiom("nat_induct", k.quant("∀", pv, ind), true)
  k.new_axiom("succ_inj", k.quant("∀", mv, k.quant("∀", nv, k.bin("⇒", k.eq_tm(mk_app(succ, mv), mk_app(succ, nv)), k.eq_tm(mv, nv)))), true)
  k.new_axiom("succ_ne_zero", k.quant("∀", nv, k.neg_tm(k.eq_tm(mk_app(succ, nv), zero))), true)
  rec_c = mk_const_raw("nat_rec", ty_funs([a, ty_funs([n, a], a), n], a))
  zv = mk_var("z", a)
  sv = mk_var("s", ty_funs([n, a], a))
  r0 = k.eq_tm(mk_apps(rec_c, [zv, sv, zero]), zv)
  k.new_axiom("nat_rec_zero", k.quant("∀", zv, k.quant("∀", sv, r0)), true)
  rs = k.eq_tm(mk_apps(rec_c, [zv, sv, mk_app(succ, nv)]), mk_apps(sv, [nv, mk_apps(rec_c, [zv, sv, nv])]))
  k.new_axiom("nat_rec_succ", k.quant("∀", zv, k.quant("∀", sv, k.quant("∀", nv, rs))), true)
  # lists
  la = ty_con("list", [a])
  k.inductive("list", ["a"], [["nil", []], ["cons", [a, la]]])
  # list_any p = list_rec ⊥ (λ x xs r. p x ∨ r)
  p = mk_var("p", ty_fun(a, b))
  x = mk_var("x", a)
  xs = mk_var("xs", la)
  r = mk_var("r", b)
  lrec = mk_const_raw("list_rec", ty_funs([b, ty_funs([a, la, b], b), la], b))
  cons_case = mk_lams([x, xs, r], k.bin("∨", mk_app(p, x), r))
  any_body = mk_lam(p, mk_apps(lrec, [k.false_tm, cons_case]))
  k.define("list_any", any_body)
  # mem x l = list_any (λ y. x = y) l   (the evaluator expands ∀ x, mem x l → …)
  y = mk_var("y", a)
  anya = mk_const_raw("list_any", ty_funs([ty_fun(a, b), la], b))
  lv = mk_var("l", la)
  k.define("mem", mk_lams([x, lv], mk_apps(anya, [mk_lam(y, k.eq_tm(x, y)), lv])))
  # lit_true a l = if 0 < l then a (nat_of_int l) else ¬ a (nat_of_int (neg l))
  i = ty_int
  asg = mk_var("a", ty_fun(n, b))
  l = mk_var("l", i)
  lt = mk_const_raw("<", ty_funs([i, i], b))
  noi = mk_const_raw("nat_of_int", ty_fun(i, n))
  negc = mk_const_raw("neg", ty_fun(i, i))
  ite = mk_const_raw("ite", ty_funs([b, b, b], b))
  cond = mk_apps(lt, [mk_lit(0, i), l])
  pos = mk_app(asg, mk_app(noi, l))
  negl = k.neg_tm(mk_app(asg, mk_app(noi, mk_app(negc, l))))
  k.define("lit_true", mk_lams([asg, l], mk_apps(ite, [cond, pos, negl])))
  li = ty_con("list", [i])
  anyi = mk_const_raw("list_any", ty_funs([ty_fun(i, b), li], b))
  c = mk_var("c", li)
  litt = mk_const_raw("lit_true", ty_funs([ty_fun(n, b), i], b))
  k.define("clause_true", mk_lams([asg, c], mk_apps(anyi, [mk_app(litt, asg), c])))
  lli = ty_con("list", [li])
  f = mk_var("f", lli)
  anyl = mk_const_raw("list_any", ty_funs([ty_fun(li, b), lli], b))
  ct = mk_const_raw("clause_true", ty_funs([ty_fun(n, b), li], b))
  falsified = mk_lam(c, k.neg_tm(mk_apps(ct, [asg, c])))
  k.define("cnf_unsat", mk_lam(f, k.quant("∀", asg, mk_apps(anyl, [falsified, f]))))
  k
