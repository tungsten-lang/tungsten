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
  ro :k, :fuel, :deep, :symbolic, :fresh, :memo, :defcache

  -> new(@k, deep = false, symbolic = false)
    @fuel = 200000000
    @deep = deep
    @symbolic = symbolic
    @fresh = 0
    @memo = {}
    @memo_count = 0
    @defcache = @k.defcache
    @tt = @k.truth_tm
    @ff = @k.false_tm
    @succ_c = mk_const_raw("succ", ty_fun(TY_NAT_SINGLETON, TY_NAT_SINGLETON))

  -> tick
    @fuel -= 1
    if @fuel < 0
      raise "compute: evaluation budget exhausted"

  -> tt
    @tt

  -> ff
    @ff

  -> bool_val(b)
    if b
      @tt
    else
      @ff

  -> true?(v)
    !v.clo? && v.op == OP_TRUE

  -> false?(v)
    !v.clo? && v.op == OP_FALSE

  # public entry: evaluate a (locally closed) term to a term
  -> eval(t)
    res = reify(ev(t, nil))
    @memo = {}
    @memo_count = 0
    res

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
      a = subst_env(t.a, env, depth)
      b = subst_env(t.b, env, depth)
      if a == t.a && b == t.b
        return t
      mk_app_raw(a, b)
    when :lam
      b = subst_env(t.b, env, depth + 1)
      if b == t.b
        return t
      mk_lam_raw(t.name, t.ty, b)
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
      nb = bucket.size
      bi = 0
      while bi < nb
        pr = bucket[bi]
        if tm_eq(pr[0], t)
          return pr[1]
        bi += 1
    v = ev_app(t, nil)
    if @memo_count < 32768
      if bucket == nil
        bucket = []
        @memo[t.h] = bucket
      bucket.push([t, v])
      @memo_count += 1
    v

  -> eval_const(t)
    if t.op == OP_NONE && @k.defs.has_key?(t.name)
      return ev(def_body(t), nil)
    t

  # Definition body at the constant's type (cached per name and type id).
  -> def_body(t)
    key = t.name + "#" + t.ty.id.to_s
    cached = @defcache[key]
    if cached != nil
      return cached
    d = @k.defs[t.name]
    e = dest_binop(d.concl, "=")
    rhs = e[1]
    if d.concl.tv
      m = {}
      ty_match(e[0].ty, t.ty, m)
      rhs = tm_inst_types(rhs, m)
    @defcache[key] = rhs
    rhs

  -> spine_head(t)
    while t.tag == :app
      t = t.a
    t

  -> ev_app(t, env)
    # Memoize closed curried prefixes of user definitions (e.g. `iter_collatz 120 (n + 1)`).
    if t.a.tag == :app && t.a.cl && t.a.mx == 0
      hd = spine_head(t.a)
      if hd.tag != :const || (hd.op == OP_NONE && @k.defs.has_key?(hd.name))
        return apply1(memo_app(t.a), ev(t.b, env))
    sp = strip_app(t)
    h = sp[0]
    args = sp[1]
    if h.tag == :const
      return ev_const_app(h, args, env)
    f = ev(h, env)
    n = args.size
    i = 0
    while i < n
      f = apply1(f, ev(args[i], env))
      i += 1
    f

  -> apply_vals(f, vals, from)
    i = from
    n = vals.size
    while i < n
      f = apply1(f, vals[i])
      i += 1
    f

  -> apply1(f, x)
    tick
    if f.clo?
      return ev(f.lam.b, KEnv.new(x, f.env))
    if f.tag == :lam
      return ev(f.b, KEnv.new(x, nil))
    hd = spine_head(f)
    if hd.tag == :const
      arity = reduction_arity_const(hd)
      if arity > 0
        sp = strip_app(f)
        sp1 = sp[1]
        nsp = sp1.size
        if nsp < arity
          vals = Array.new(nsp + 1)
          i = 0
          while i < nsp
            vals[i] = sp1[i]
            i += 1
          vals[nsp] = x
          return ev_const_vals(hd, vals)
    mk_app_raw(f, reify(x))

  # Constant applied to argument terms in env (lazy forms handled here).
  -> ev_const_app(h, args, env)
    op = h.op
    n = args.size
    if op != OP_NONE
      if op == OP_ITE && n >= 3
        c = ev(args[0], env)
        if true?(c)
          return apply_terms(ev(args[1], env), args, 3, env)
        if false?(c)
          return apply_terms(ev(args[2], env), args, 3, env)
        vals = Array.new(n)
        vals[0] = c
        vals[1] = ev(args[1], env)
        vals[2] = ev(args[2], env)
        i = 3
        while i < n
          vals[i] = ev(args[i], env)
          i += 1
        return neutral(h, vals)
      if op == OP_AND && n == 2
        l = ev(args[0], env)
        if false?(l)
          return @ff
        return conn_and(h, l, ev(args[1], env))
      if op == OP_OR && n == 2
        l = ev(args[0], env)
        if true?(l)
          return @tt
        return conn_or(h, l, ev(args[1], env))
      if op == OP_IMP && n == 2
        l = ev(args[0], env)
        if false?(l)
          return @tt
        return conn_imp(h, l, ev(args[1], env))
      if (op == OP_ALL || op == OP_EX) && n == 1 && args[0].tag == :lam
        r = ev_bounded(op, args[0], env)
        if r != nil
          return r
        return neutral(h, [ev(args[0], env)])
      vals = Array.new(n)
      i = 0
      while i < n
        vals[i] = ev(args[i], env)
        i += 1
      return ev_const_vals_op(h, op, vals)
    name = h.name
    if @k.defs.has_key?(name)
      f = eval_const(h)
      i = 0
      while i < n
        f = apply1(f, ev(args[i], env))
        i += 1
      return f
    vals = Array.new(n)
    i = 0
    while i < n
      vals[i] = ev(args[i], env)
      i += 1
    info = @k.rec_of[name]
    if info != nil
      r = iota_info(h, info, vals)
      if r != nil
        return r
    neutral(h, vals)

  -> apply_terms(f, args, from, env)
    i = from
    n = args.size
    while i < n
      f = apply1(f, ev(args[i], env))
      i += 1
    f

  -> neutral(h, vals)
    t = h
    n = vals.size
    i = 0
    while i < n
      t = mk_app_raw(t, reify(vals[i]))
      i += 1
    t

  -> conn_and(h, l, r)
    if false?(r)
      return @ff
    if true?(l)
      return r
    if true?(r)
      return l
    neutral(h, [l, r])

  -> conn_or(h, l, r)
    if true?(r)
      return @tt
    if false?(l)
      return r
    if false?(r)
      return l
    neutral(h, [l, r])

  -> conn_imp(h, l, r)
    if true?(l)
      return r
    if true?(r)
      return @tt
    neutral(h, [l, r])

  # Constant applied to evaluated values.
  -> ev_const_vals(h, vals)
    op = h.op
    if op != OP_NONE
      return ev_const_vals_op(h, op, vals)
    name = h.name
    if @k.defs.has_key?(name)
      return apply_vals(eval_const(h), vals, 0)
    info = @k.rec_of[name]
    if info != nil
      r = iota_info(h, info, vals)
      if r != nil
        return r
    neutral(h, vals)

  -> ev_const_vals_op(h, op, vals)
    n = vals.size
    if n == 2
      v0 = vals[0]
      v1 = vals[1]
      if op >= OP_ADD && op <= OP_LE
        if !v0.clo? && !v1.clo? && v0.tag == :lit && v1.tag == :lit
          r = lit_binary_op(op, h.ty, v0, v1)
          if r != nil
            return r
        if op == OP_ADD && !v1.clo? && v1.tag == :lit && v1.ty == TY_NAT_SINGLETON && (v0.clo? || v0.tag != :lit) && v1.val <= 64
          r = reify(v0)
          i = 0
          kv = v1.val
          while i < kv
            r = mk_app_raw(@succ_c, r)
            i += 1
          return r
        return neutral(h, vals)
      if op == OP_EQ
        a = reify(v0)
        b = reify(v1)
        d = decide_eq(a, b)
        if d != nil
          return d
        return mk_app_raw(mk_app_raw(h, a), b)
      if op == OP_AND
        if false?(v0)
          return @ff
        return conn_and(h, v0, v1)
      if op == OP_OR
        if true?(v0)
          return @tt
        return conn_or(h, v0, v1)
      if op == OP_IMP
        if false?(v0)
          return @tt
        return conn_imp(h, v0, v1)
    if n == 1
      v0 = vals[0]
      if op >= OP_SUCC && op <= OP_FLOOR
        if !v0.clo? && v0.tag == :lit
          r = lit_unary_op(op, h.ty, v0)
          if r != nil
            return r
        return neutral(h, vals)
      if op == OP_NOT
        if true?(v0)
          return @ff
        if false?(v0)
          return @tt
        return neutral(h, vals)
      if (op == OP_ALL || op == OP_EX) && v0.clo?
        r = ev_bounded(op, v0.lam, v0.env)
        if r != nil
          return r
        return neutral(h, vals)
    if op == OP_ITE && n >= 3
      if true?(vals[0])
        return apply_vals(vals[1], vals, 3)
      if false?(vals[0])
        return apply_vals(vals[2], vals, 3)
      return neutral(h, vals)
    if op == OP_NAT_REC && n >= 3
      r = nat_rec_val(h, vals[0], vals[1], vals[2])
      return apply_vals(r, vals, 3)
    neutral(h, vals)

  -> reduction_arity_const(h)
    op = h.op
    if op != OP_NONE
      if op == OP_ITE || op == OP_NAT_REC
        return 3
      if (op >= OP_AND && op <= OP_IMP) || (op >= OP_EQ && op <= OP_LE)
        return 2
      if op == OP_NOT || op == OP_ALL || op == OP_EX || (op >= OP_SUCC && op <= OP_FLOOR)
        return 1
      return 0
    name = h.name
    info = @k.rec_of[name]
    if info != nil
      return info.ctors.size + 1
    if @k.defs.has_key?(name)
      return 1000000
    0

  -> nat_rec_val(h, z, s, nv)
    if !nv.clo? && nv.tag == :lit
      nval = nv.val
      if nval > 0
        # Fast static check before evaluating step function when s is a 2-arg closure `λ k ih. body`.
        if s.clo? && s.lam.b.tag == :lam
          if !occurs_bnd(s.lam.b.b, 0)
            return apply1(apply1(s, mk_nat(nval - 1)), z)
        else
          f1 = apply1(s, mk_nat(nval - 1))
          if ignores_arg?(f1)
            return apply1(f1, z)
      acc = z
      i = 0
      while i < nval
        acc = apply1(apply1(s, mk_nat(i)), acc)
        i += 1
      return acc
    if !nv.clo? && nv.tag == :app && nv.a.tag == :const && nv.a.op == OP_SUCC
      m = nv.b
      f1 = apply1(s, m)
      if ignores_arg?(f1)
        return apply1(f1, z)
      return apply1(f1, nat_rec_val(h, z, s, m))
    neutral(h, [z, s, nv])

  -> iota(h, vals)
    info = @k.rec_of[h.name]
    if info == nil
      return nil
    iota_info(h, info, vals)

  -> iota_info(h, info, vals)
    k = info.ctors.size
    if vals.size < k + 1
      return nil
    target = reify(vals[k])
    sp = strip_app(target)
    ch = sp[0]
    if ch.tag != :const || @k.ctor_of[ch.name] != info.name
      return nil
    ci = 0
    while ci < k && info.ctors[ci][0] != ch.name
      ci += 1
    cargs = sp[1]
    nc = cargs.size
    f = vals[ci]
    j = 0
    while j < nc
      f = apply1(f, cargs[j])
      j += 1
    rpos = info.rec_pos[ci]
    nrp = rpos.size
    ri = 0
    while ri < nrp
      rj = rpos[ri]
      if ignores_arg?(f)
        f = apply1(f, cargs[rj])
      else
        rv = Array.new(k + 1)
        q = 0
        while q < k
          rv[q] = vals[q]
          q += 1
        rv[k] = cargs[rj]
        f = apply1(f, iota_or_neutral(h, info, rv))
      ri += 1
    apply_vals(f, vals, k + 1)

  -> ignores_arg?(f)
    if f.clo?
      return !occurs_bnd(f.lam.b, 0)
    if f.tag == :lam
      return !occurs_bnd(f.b, 0)
    false

  -> iota_or_neutral(h, info, vals)
    r = iota_info(h, info, vals)
    if r != nil
      return r
    neutral(h, vals)

  # ---- bounded quantifiers ---------------------------------------------------------

  # Finite expansion of ∀/∃ over a literal range/list/finite type.
  -> ev_bounded(q_op, lam, env)
    ty = lam.ty
    body = lam.b
    conn_op = q_op == OP_EX ? OP_AND : OP_IMP
    dom = nil
    range_end = nil
    rest = nil
    if body.tag == :app && body.a.tag == :app && body.a.a.tag == :const && body.a.a.op == conn_op
      guard = body.a.b
      rest_cand = body.b
      if guard.tag == :app && guard.a.tag == :app && guard.a.a.tag == :const
        ghead = guard.a.a
        glhs = guard.a.b
        grhs = guard.b
        if glhs.tag == :bnd && glhs.idx == 0 && !occurs_bnd(grhs, 0)
          if ghead.op == OP_LT && ty == TY_NAT_SINGLETON
            nv = reify(ev(grhs, KEnv.new(@tt, env)))
            if nv.tag == :lit
              range_end = nv.val
              rest = rest_cand
          elsif ghead.op == OP_LE && ty == TY_NAT_SINGLETON
            nv = reify(ev(grhs, KEnv.new(@tt, env)))
            if nv.tag == :lit
              range_end = zadd(nv.val, 1)
              rest = rest_cand
          elsif ghead.name == "mem"
            lst = reify(ev(grhs, KEnv.new(@tt, env)))
            items = list_literal_items(lst)
            if items != nil
              dom = items
              rest = rest_cand
    if dom == nil && range_end == nil
      if ty == TY_BOOL_SINGLETON
        dom = [@tt, @ff]
        rest = body
      elsif ty.tag == :c
        info = @k.inductives[ty.name]
        if info != nil && info.is_enum
          nc = info.ctors.size
          dom = Array.new(nc)
          ci = 0
          while ci < nc
            dom[ci] = mk_const_raw(info.ctors[ci][0], ty)
            ci += 1
          rest = body
    if dom == nil && range_end == nil
      return nil
    residue = []
    nd = range_end == nil ? dom.size : range_end
    di = 0
    while di < nd
      x = range_end == nil ? dom[di] : mk_nat(di)
      v = reify(ev(rest, KEnv.new(x, env)))
      if q_op == OP_ALL
        if false?(v)
          return @ff
        if !true?(v)
          if !@symbolic
            return nil
          residue.push(v)
      else
        if true?(v)
          return @tt
        if !false?(v)
          if !@symbolic
            return nil
          residue.push(v)
      di += 1
    if residue.size > 0
      cn = q_op == OP_EX ? "∨" : "∧"
      c = mk_const_raw(cn, ty_fun(TY_BOOL_SINGLETON, ty_fun(TY_BOOL_SINGLETON, TY_BOOL_SINGLETON)))
      acc = residue[residue.size - 1]
      i = residue.size - 2
      while i >= 0
        acc = mk_app_raw(mk_app_raw(c, residue[i]), acc)
        i -= 1
      return acc
    if q_op == OP_ALL
      @tt
    else
      @ff

  # ---- primitive decisions on terms -------------------------------------------------

  -> ctor_app?(t)
    hd = spine_head(t)
    hd.tag == :const && @k.ctor_of.has_key?(hd.name)

  -> decide_eq(a, b)
    if a.tag == :lit && b.tag == :lit
      return bool_val(lit_val_eq(a.val, b.val))
    if (true?(a) || false?(a)) && (true?(b) || false?(b))
      return bool_val(a.op == b.op)
    if ctor_app?(a) && ctor_app?(b)
      sa = strip_app(a)
      sb = strip_app(b)
      if sa[0].name != sb[0].name
        return @ff
      i = sa[1].size - 1
      while i >= 0
        e = decide_eq(sa[1][i], sb[1][i])
        if e == nil
          return nil
        if false?(e)
          return @ff
        i -= 1
      return @tt
    if tm_eq(a, b)
      return @tt
    nil

  -> lit_unary_op(op, ty, x)
    rt = ty.cod
    v = x.val
    case op
    when OP_SUCC
      mk_lit(zadd(v, 1), TY_NAT_SINGLETON)
    when OP_NEG
      if rt == TY_INT_SINGLETON
        mk_lit(zsub(0, v), rt)
      elsif rt == TY_RAT_SINGLETON || rt == TY_REAL_SINGLETON
        mk_lit(q_neg(v), rt)
      else
        nil
    when OP_ABS
      if rt == TY_INT_SINGLETON || rt == TY_NAT_SINGLETON
        if v < 0
          mk_lit(zsub(0, v), rt)
        else
          x
      elsif rt == TY_RAT_SINGLETON || rt == TY_REAL_SINGLETON
        if v[0] < 0
          mk_lit(q_neg(v), rt)
        else
          x
      else
        nil
    when OP_INT_OF_NAT
      mk_lit(v, TY_INT_SINGLETON)
    when OP_RAT_OF_INT
      mk_lit([v, 1], TY_RAT_SINGLETON)
    when OP_REAL_OF_RAT
      mk_lit(v, TY_REAL_SINGLETON)
    when OP_NAT_OF_INT
      if v < 0
        mk_nat(0)
      else
        mk_nat(v)
    when OP_FLOOR
      mk_lit(int_fdiv(v[0], v[1]), TY_INT_SINGLETON)
    else
      nil

  -> lit_binary_op(op, ty, x, y)
    at = ty.dom
    a = x.val
    b = y.val
    if at == TY_NAT_SINGLETON || at == TY_INT_SINGLETON
      case op
      when OP_ADD
        return mk_lit(zadd(a, b), at)
      when OP_MUL
        return mk_lit(zmul(a, b), at)
      when OP_SUB
        r = zsub(a, b)
        if at == TY_NAT_SINGLETON && r < 0
          r = 0
        return mk_lit(r, at)
      when OP_DIV
        return mk_lit(int_fdiv(a, b), at)
      when OP_MOD
        return mk_lit(int_fmod(a, b), at)
      when OP_POW
        return mk_lit(int_pow_fast(a, b), at)
      when OP_LT
        return bool_val(a < b)
      when OP_LE
        return bool_val(a <= b)
      else
        return nil
    if at == TY_RAT_SINGLETON || at == TY_REAL_SINGLETON
      case op
      when OP_ADD
        return mk_lit(q_add(a, b), at)
      when OP_SUB
        return mk_lit(q_sub(a, b), at)
      when OP_MUL
        return mk_lit(q_mul(a, b), at)
      when OP_DIV
        if b[0] == 0
          return mk_lit(Q_ZERO, at)
        return mk_lit(q_div(a, b), at)
      when OP_POW
        return mk_lit(q_make(int_pow_fast(a[0], b), int_pow_fast(a[1], b)), at)
      when OP_LT
        return bool_val(q_cmp(a, b) < 0)
      when OP_LE
        return bool_val(q_cmp(a, b) <= 0)
      else
        return nil
    nil

-> int_pow_fast(a, e)
  if e <= 0
    return 1
  r = 1
  base = a
  while e > 0
    if (e & 1) == 1
      r = zmul(r, base)
    e = e >> 1
    if e > 0
      base = zmul(base, base)
  r
