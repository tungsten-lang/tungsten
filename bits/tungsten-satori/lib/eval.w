# The Satori evaluator — part of the trusted kernel.
#
# KEval.eval(t) returns a term v with ⊢ t = v. It applies only:
#   beta reduction; unfolding of definitions made by KKernel.define;
#   literal arithmetic on nat/int/rat/real (semantics fixed by the prelude
#   axioms: truncated nat subtraction, floor division, x / 0 = 0, x % 0 = x);
#   n + k = succ^k n on ℕ; recursor (iota) reduction on constructor
#   applications and nat literals; equality of literals, booleans and
#   constructor terms (injectivity and distinctness); the connectives and
#   `ite` on ⊤/⊥; finite expansion of quantifiers bounded by a literal range,
#   a literal list (via the kernel's `mem`), Prop, or an enumeration type.
# Anything else is left as a neutral term.
#
# Implementation: normalization by evaluation. Terms are evaluated in an
# environment of values (de Bruijn index i = i-th enclosing binding); a lambda
# evaluates to a closure, so instantiating a binder never copies a term.
# Values are KTm (literals, booleans, constructor data, neutral terms) or
# KClo (closures); `reify` turns a value back into a term. Tungsten has no
# tracing GC, so avoiding term copies is what keeps memory bounded.
# The previous substitution-based evaluator is kept as KEvalRef (eval_ref.w)
# for differential testing.

+ KClo
  ro :lam, :env
  -> new(@lam, @env)
  -> clo?
    true

+ KTm
  -> clo?
    false

+ KEnv
  ro :v, :up
  -> new(@v, @up)

-> env_get(env, i)
  e = env
  while i > 0
    e = e.up
    i -= 1
  e.v

# Does the loose bound index d (relative to depth 0 of t) occur in t?
-> occurs_bnd(t, d)
  if t.mx <= d
    return false
  case t.tag
  when :bnd
    t.idx == d
  when :app
    occurs_bnd(t.a, d) || occurs_bnd(t.b, d)
  when :lam
    occurs_bnd(t.b, d + 1)
  else
    false

+ KEval
  -> new(@k, deep = false, symbolic = false)
    @fuel = 200000000
    @deep = deep
    @symbolic = symbolic
    @fresh = 0
    @memo = {}
    @defcache = {}

  -> tick
    @fuel -= 1
    if @fuel < 0
      raise "compute: evaluation budget exhausted"

  -> tt
    if @tt == nil
      @tt = mk_const_raw("⊤", ty_bool)
    @tt

  -> ff
    if @ff == nil
      @ff = mk_const_raw("⊥", ty_bool)
    @ff

  -> bool_val(b)
    if b
      tt
    else
      ff

  -> true?(v)
    !v.clo? && v.tag == :const && v.name == "⊤"

  -> false?(v)
    !v.clo? && v.tag == :const && v.name == "⊥"

  # public entry: evaluate a (locally closed) term to a term
  -> eval(t)
    reify(ev(t, nil))

  # ---- values and reification -------------------------------------------------

  -> reify(v)
    if !v.clo?
      return v
    lam = v.lam
    if @deep
      @fresh += 1
      x = mk_var("§e" + @fresh.to_s, lam.ty)
      body = reify(ev(lam.b, KEnv.new(x, v.env)))
      return mk_lam(x, body)
    subst_env(lam, v.env, 0)

  # replace loose indices ≥ depth by the reified environment values
  -> subst_env(t, env, depth)
    if t.mx <= depth
      return t
    case t.tag
    when :bnd
      reify(env_get(env, t.idx - depth))
    when :app
      mk_app_raw(subst_env(t.a, env, depth), subst_env(t.b, env, depth))
    when :lam
      mk_lam_raw(t.name, t.ty, subst_env(t.b, env, depth + 1))
    else
      t

  # ---- evaluation --------------------------------------------------------------

  -> ev(t, env)
    tick
    case t.tag
    when :bnd
      env_get(env, t.idx)
    when :lit
      t
    when :var
      t
    when :lam
      KClo.new(t, env)
    when :const
      eval_const(t)
    else
      if t.cl && t.mx == 0
        return memo_app(t)
      ev_app(t, env)

  -> memo_app(t)
    bucket = @memo[t.h]
    if bucket != nil
      bucket.each -> (pr)
        if tm_eq(pr[0], t)
          return pr[1]
    else
      bucket = []
      @memo[t.h] = bucket
    v = ev_app(t, nil)
    bucket.push([t, v])
    v

  -> eval_const(t)
    if @k.defs.has_key?(t.name)
      return ev(def_body(t), nil)
    t

  # Definition body at the constant's type (cached per name and type).
  -> def_body(t)
    key = t.name + "@" + t.ty.key
    if @defcache.has_key?(key)
      return @defcache[key]
    d = @k.defs[t.name]
    e = dest_binop(d.concl, "=")
    rhs = e[1]
    m = {}
    ty_match(e[0].ty, t.ty, m)
    nontrivial = false
    m.keys.each -> (vn)
      if !(m[vn].tag == :v && m[vn].name == vn)
        nontrivial = true
    if nontrivial
      rhs = tm_inst_types(rhs, m)
    @defcache[key] = rhs
    rhs

  -> ev_app(t, env)
    sp = strip_app(t)
    h = sp[0]
    args = sp[1]
    if h.tag == :const
      return ev_const_app(h, args, env)
    f = ev(h, env)
    args.each -> (a)
      f = apply1(f, ev(a, env))
    f

  -> apply_vals(f, vals, from)
    i = from
    while i < vals.size
      f = apply1(f, vals[i])
      i += 1
    f

  -> apply1(f, x)
    tick
    if f.clo?
      return ev(f.lam.b, KEnv.new(x, f.env))
    if f.tag == :lam
      # a reified (locally closed) lambda is the closure with an empty env
      return ev(f.b, KEnv.new(x, nil))
    # f is a term: a constant (possibly partially applied) or a neutral term.
    # Re-dispatch only while the constant still lacks the arguments its
    # reduction rule needs; a stuck application just grows.
    sp = strip_app(f)
    if sp[0].tag == :const && sp[1].size < reduction_arity(sp[0].name)
      vals = []
      sp[1].each -> (a)
        vals.push(a)
      vals.push(x)
      return ev_const_vals(sp[0], vals)
    mk_app_raw(f, reify(x))

  # Constant applied to argument terms in env (lazy forms handled here).
  -> ev_const_app(h, args, env)
    name = h.name
    n = args.size
    if name == "ite" && n >= 3
      c = ev(args[0], env)
      if true?(c)
        return apply_terms(ev(args[1], env), args, 3, env)
      if false?(c)
        return apply_terms(ev(args[2], env), args, 3, env)
      vals = [c, ev(args[1], env), ev(args[2], env)]
      i = 3
      while i < n
        vals.push(ev(args[i], env))
        i += 1
      return neutral(h, vals)
    if name == "∧" && n == 2
      l = ev(args[0], env)
      if false?(l)
        return ff
      r = ev(args[1], env)
      return conn_and(h, l, r)
    if name == "∨" && n == 2
      l = ev(args[0], env)
      if true?(l)
        return tt
      r = ev(args[1], env)
      return conn_or(h, l, r)
    if name == "⇒" && n == 2
      l = ev(args[0], env)
      if false?(l)
        return tt
      r = ev(args[1], env)
      return conn_imp(h, l, r)
    if (name == "∀" || name == "∃") && n == 1 && args[0].tag == :lam
      r = ev_bounded(name, args[0], env)
      if r != nil
        return r
      return neutral(h, [ev(args[0], env)])
    if @k.defs.has_key?(name)
      f = eval_const(h)
      args.each -> (a)
        f = apply1(f, ev(a, env))
      return f
    vals = []
    args.each -> (a)
      vals.push(ev(a, env))
    ev_const_vals(h, vals)

  -> apply_terms(f, args, from, env)
    i = from
    while i < args.size
      f = apply1(f, ev(args[i], env))
      i += 1
    f

  -> neutral(h, vals)
    t = h
    vals.each -> (v)
      t = mk_app_raw(t, reify(v))
    t

  -> conn_and(h, l, r)
    if false?(r)
      return ff
    if true?(l)
      return r
    if true?(r)
      return l
    neutral(h, [l, r])

  -> conn_or(h, l, r)
    if true?(r)
      return tt
    if false?(l)
      return r
    if false?(r)
      return l
    neutral(h, [l, r])

  -> conn_imp(h, l, r)
    if true?(l)
      return r
    if true?(r)
      return tt
    neutral(h, [l, r])

  # Constant applied to evaluated values.
  -> ev_const_vals(h, vals)
    name = h.name
    n = vals.size
    if @k.defs.has_key?(name)
      return apply_vals(eval_const(h), vals, 0)
    if name == "ite" && n >= 3
      if true?(vals[0])
        return apply_vals(vals[1], vals, 3)
      if false?(vals[0])
        return apply_vals(vals[2], vals, 3)
      return neutral(h, vals)
    if name == "∧" && n == 2
      if false?(vals[0])
        return ff
      return conn_and(h, vals[0], vals[1])
    if name == "∨" && n == 2
      if true?(vals[0])
        return tt
      return conn_or(h, vals[0], vals[1])
    if name == "⇒" && n == 2
      if false?(vals[0])
        return tt
      return conn_imp(h, vals[0], vals[1])
    if name == "¬" && n == 1
      if true?(vals[0])
        return ff
      if false?(vals[0])
        return tt
      return neutral(h, vals)
    if (name == "∀" || name == "∃") && n == 1 && vals[0].clo?
      r = ev_bounded(name, vals[0].lam, vals[0].env)
      if r != nil
        return r
      return neutral(h, vals)
    if name == "nat_rec" && n >= 3
      r = nat_rec_val(h, vals[0], vals[1], vals[2])
      return apply_vals(r, vals, 3)
    if name == "=" && n == 2
      a = reify(vals[0])
      b = reify(vals[1])
      d = decide_eq(a, b)
      if d != nil
        return d
      return mk_app_raw(mk_app_raw(h, a), b)
    if n == 1 && !vals[0].clo? && vals[0].tag == :lit
      r = lit_unary(name, h.ty, vals[0])
      if r != nil
        return r
    if n == 2 && !vals[0].clo? && !vals[1].clo? && vals[0].tag == :lit && vals[1].tag == :lit
      r = lit_binary(name, h.ty, vals[0], vals[1])
      if r != nil
        return r
    # n + k  =  succ^k n  on ℕ (add_succ), exposing constructors to nat_rec
    if name == "+" && n == 2 && !vals[1].clo? && vals[1].tag == :lit && vals[1].ty.name == "nat" && (vals[0].clo? || vals[0].tag != :lit) && vals[1].val <= 64
      s = mk_const_raw("succ", ty_fun(ty_nat, ty_nat))
      r = reify(vals[0])
      i = 0
      while i < vals[1].val
        r = mk_app_raw(s, r)
        i += 1
      return r
    if @k.inductives.has_key?(rec_owner(name))
      r = iota(h, vals)
      if r != nil
        return r
    neutral(h, vals)

  -> reduction_arity(name)
    case name
    when "ite", "nat_rec"
      3
    when "∧", "∨", "⇒", "=", "+", "-", "*", "/", "%", "^", "<", "≤"
      2
    when "¬", "∀", "∃", "succ", "neg", "abs", "int_of_nat", "rat_of_int", "real_of_rat", "nat_of_int", "floor"
      1
    else
      if @k.inductives.has_key?(rec_owner(name))
        return @k.inductives[rec_owner(name)].ctors.size + 1
      if @k.defs.has_key?(name)
        return 1000000
      0

  -> nat_rec_val(h, z, s, nv)
    if !nv.clo? && nv.tag == :lit
      acc = z
      i = 0
      while i < nv.val
        acc = apply1(apply1(s, mk_nat(i)), acc)
        i += 1
      return acc
    if !nv.clo? && nv.tag == :app && nv.a.tag == :const && nv.a.name == "succ"
      m = nv.b
      return apply1(apply1(s, m), nat_rec_val(h, z, s, m))
    neutral(h, [z, s, nv])

  -> rec_owner(name)
    if name.ends_with?("_rec")
      name.slice(0, name.size - 4)
    else
      ""

  -> iota(h, vals)
    info = @k.inductives[rec_owner(h.name)]
    k = info.ctors.size
    if vals.size < k + 1
      return nil
    target = reify(vals[k])
    sp = strip_app(target)
    ch = sp[0]
    if ch.tag != :const || !@k.ctor_of.has_key?(ch.name) || @k.ctor_of[ch.name] != info.name
      return nil
    ci = 0
    while ci < k && info.ctors[ci][0] != ch.name
      ci += 1
    cargs = sp[1]
    f = vals[ci]
    cargs.each -> (a)
      f = apply1(f, a)
    j = 0
    while j < cargs.size
      at = type_of(cargs[j])
      if at.tag == :c && at.name == info.name
        rv = []
        q = 0
        while q < k
          rv.push(vals[q])
          q += 1
        rv.push(cargs[j])
        f = apply1(f, iota_or_neutral(h, rv))
      j += 1
    apply_vals(f, vals, k + 1)

  -> iota_or_neutral(h, vals)
    r = iota(h, vals)
    if r != nil
      return r
    neutral(h, vals)

  # ---- bounded quantifiers ---------------------------------------------------------

  # Finite expansion of ∀/∃ over a literal range/list/finite type. lam is the
  # quantifier's lambda term, evaluated in env. Returns a value or nil.
  -> ev_bounded(q, lam, env)
    ty = lam.ty
    body = lam.b
    conn = "⇒"
    if q == "∃"
      conn = "∧"
    dom = nil
    rest = nil
    g = dest_binop(body, conn)
    if g != nil
      guard = g[0]
      d = dest_binop(guard, "<")
      if d != nil && d[0].tag == :bnd && d[0].idx == 0 && !occurs_bnd(d[1], 0) && ty.name == "nat"
        nv = reify(ev(d[1], KEnv.new(tt, env)))
        if nv.tag == :lit
          dom = range_lits(0, nv.val)
          rest = g[1]
      d = dest_binop(guard, "≤")
      if dom == nil && d != nil && d[0].tag == :bnd && d[0].idx == 0 && !occurs_bnd(d[1], 0) && ty.name == "nat"
        nv = reify(ev(d[1], KEnv.new(tt, env)))
        if nv.tag == :lit
          dom = range_lits(0, nv.val + 1)
          rest = g[1]
      d = dest_binop(guard, "mem")
      if dom == nil && d != nil && d[0].tag == :bnd && d[0].idx == 0 && !occurs_bnd(d[1], 0)
        lst = reify(ev(d[1], KEnv.new(tt, env)))
        items = list_literal_items(lst)
        if items != nil
          dom = items
          rest = g[1]
    if dom == nil
      if ty.tag == :c && ty.name == "bool"
        dom = [tt, ff]
        rest = body
      elsif ty.tag == :c && @k.inductives.has_key?(ty.name)
        info = @k.inductives[ty.name]
        enum = info.params.size == 0
        info.ctors.each -> (c)
          if c[1].size > 0
            enum = false
        if enum
          dom = []
          info.ctors.each -> (c)
            dom.push(mk_const_raw(c[0], ty))
          rest = body
    if dom == nil
      return nil
    residue = []
    dom.each -> (x)
      v = reify(ev(rest, KEnv.new(x, env)))
      if q == "∀"
        if false?(v)
          return ff
        if !true?(v)
          if !@symbolic
            return nil
          residue.push(v)
      else
        if true?(v)
          return tt
        if !false?(v)
          if !@symbolic
            return nil
          residue.push(v)
    if residue.size > 0
      cn = "∧"
      if q == "∃"
        cn = "∨"
      c = mk_const_raw(cn, ty_funs([ty_bool, ty_bool], ty_bool))
      acc = residue[residue.size - 1]
      i = residue.size - 2
      while i >= 0
        acc = mk_app_raw(mk_app_raw(c, residue[i]), acc)
        i -= 1
      return acc
    if q == "∀"
      tt
    else
      ff

  -> range_lits(lo, hi)
    out = []
    i = lo
    while i < hi
      out.push(mk_nat(i))
      i += 1
    out

  # ---- primitive decisions on terms -------------------------------------------------

  -> ctor_app?(t)
    sp = strip_app(t)
    sp[0].tag == :const && @k.ctor_of.has_key?(sp[0].name)

  -> decide_eq(a, b)
    if a.tag == :lit && b.tag == :lit
      return bool_val(lit_key(a.val) == lit_key(b.val))
    if (true?(a) || false?(a)) && (true?(b) || false?(b))
      return bool_val(a.name == b.name)
    if ctor_app?(a) && ctor_app?(b)
      sa = strip_app(a)
      sb = strip_app(b)
      if sa[0].name != sb[0].name
        return ff
      i = sa[1].size - 1
      while i >= 0
        e = decide_eq(sa[1][i], sb[1][i])
        if e == nil
          return nil
        if false?(e)
          return ff
        i -= 1
      return tt
    if tm_eq(a, b)
      return tt
    nil

  -> lit_unary(name, ty, x)
    rt = ty.cod
    v = x.val
    case name
    when "succ"
      mk_lit(zadd(v, 1), ty_nat)
    when "neg"
      if rt.name == "int"
        mk_lit(0 - v, rt)
      elsif rt.name == "rat" || rt.name == "real"
        mk_lit(q_neg(v), rt)
      else
        nil
    when "abs"
      if rt.name == "int" || rt.name == "nat"
        if v < 0
          mk_lit(0 - v, rt)
        else
          x
      elsif rt.name == "rat" || rt.name == "real"
        if v[0] < 0
          mk_lit(q_neg(v), rt)
        else
          x
      else
        nil
    when "int_of_nat"
      mk_lit(v, ty_int)
    when "rat_of_int"
      mk_lit([v, 1], ty_rat)
    when "real_of_rat"
      mk_lit(v, ty_real)
    when "nat_of_int"
      if v < 0
        mk_nat(0)
      else
        mk_nat(v)
    when "floor"
      mk_lit(int_fdiv(v[0], v[1]), ty_int)
    else
      nil

  -> lit_binary(name, ty, x, y)
    at = ty.dom
    kind = at.name
    a = x.val
    b = y.val
    if kind == "nat" || kind == "int"
      case name
      when "+"
        return mk_lit(zadd(a, b), at)
      when "*"
        return mk_lit(a * b, at)
      when "-"
        r = zsub(a, b)
        if kind == "nat" && r < 0
          r = 0
        return mk_lit(r, at)
      when "/"
        return mk_lit(int_fdiv(a, b), at)
      when "%"
        return mk_lit(int_fmod(a, b), at)
      when "^"
        return mk_lit(int_pow_fast(a, b), at)
      when "<"
        return bool_val(a < b)
      when "≤"
        return bool_val(a <= b)
      else
        return nil
    if kind == "rat" || kind == "real"
      case name
      when "+"
        return mk_lit(q_add(a, b), at)
      when "-"
        return mk_lit(q_sub(a, b), at)
      when "*"
        return mk_lit(q_mul(a, b), at)
      when "/"
        if b[0] == 0
          return mk_lit([0, 1], at)
        return mk_lit(q_div(a, b), at)
      when "^"
        return mk_lit(q_make(int_pow_fast(a[0], b), int_pow_fast(a[1], b)), at)
      when "<"
        return bool_val(q_cmp(a, b) < 0)
      when "≤"
        return bool_val(q_cmp(a, b) <= 0)
      else
        return nil
    nil

-> int_pow_fast(a, e)
  r = 1
  base = a
  while e > 0
    if e % 2 == 1
      r = r * base
    base = base * base
    e = e / 2
  r
