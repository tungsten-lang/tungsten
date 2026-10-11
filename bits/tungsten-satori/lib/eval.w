# The Satori evaluator — part of the trusted kernel.
#
# KEval.eval(t) returns a term v with ⊢ t = v. It applies only:
#   beta reduction; unfolding of definitions made by KKernel.define;
#   literal arithmetic on nat/int/rat/real (semantics fixed by the prelude
#   axioms: truncated nat subtraction, floor division, x / 0 = 0, x % 0 = x);
#   recursor (iota) reduction on constructor applications and nat literals;
#   equality of literals, booleans and constructor terms (by injectivity and
#   distinctness); the connectives and `ite` on ⊤/⊥.
# Anything else is left as a neutral term.

+ KEval
  -> new(@k, deep = false, symbolic = false)
    @fuel = 200000000
    @deep = deep
    @symbolic = symbolic
    @fresh = 0
    @memo = {}

  -> tick
    @fuel -= 1
    if @fuel < 0
      raise "compute: evaluation budget exhausted"

  -> tt
    mk_const_raw("⊤", ty_bool)

  -> ff
    mk_const_raw("⊥", ty_bool)

  -> bool_val(b)
    if b
      tt
    else
      ff

  -> true?(t)
    t.tag == :const && t.name == "⊤"

  -> false?(t)
    t.tag == :const && t.name == "⊥"

  -> eval(t)
    tick
    case t.tag
    when :lit
      t
    when :var
      t
    when :bnd
      t
    when :lam
      if @deep
        @fresh += 1
        v = mk_var("§e" + @fresh.to_s, t.ty)
        return mk_lam(v, eval(tm_instantiate(t.b, v, 0)))
      t
    when :const
      eval_const(t)
    else
      memo_eval_app(t)

  -> eval_const(t)
    if @k.defs.has_key?(t.name)
      return eval(def_body(t))
    t

  # Definition body at the constant's type (cached per name and type).
  -> def_body(t)
    key = t.name + "@" + t.ty.key
    if @defcache == nil
      @defcache = {}
    if @defcache.has_key?(key)
      return @defcache[key]
    d = @k.defs[t.name]
    e = dest_binop(d.concl, "=")
    rhs = e[1]
    m = {}
    ty_match(e[0].ty, t.ty, m)
    nontrivial = false
    m.keys.each -> (v)
      if !(m[v].tag == :v && m[v].name == v)
        nontrivial = true
    if nontrivial
      rhs = tm_inst_types(rhs, m)
    @defcache[key] = rhs
    rhs

  -> apply_all(f, args)
    r = f
    args.each -> (a)
      r = mk_app_raw(r, a)
    r

  -> eval_app(t)
    sp = strip_app(t)
    h = sp[0]
    args = sp[1]
    if h.tag == :lam
      body = tm_instantiate(h.b, args[0], 0)
      rest = arr_sub(args, 1, args.size - 1)
      return eval(apply_all(body, rest))
    if h.tag != :const
      hv = eval(h)
      if hv.tag == :lam || (hv.tag == :const && !tm_eq(hv, h))
        return eval(apply_all(hv, args))
      ev = []
      args.each -> (a)
        ev.push(eval(a))
      return apply_all(hv, ev)
    name = h.name
    # lazy forms
    if name == "ite" && args.size >= 3
      c = eval(args[0])
      rest = arr_sub(args, 3, args.size - 3)
      if true?(c)
        return eval(apply_all(args[1], rest))
      if false?(c)
        return eval(apply_all(args[2], rest))
      return apply_all(h, [c, eval(args[1]), eval(args[2])] + rest)
    if name == "∧" && args.size == 2
      l = eval(args[0])
      if false?(l)
        return ff
      r = eval(args[1])
      if true?(l)
        return r
      if false?(r)
        return ff
      if true?(r)
        return l
      return apply_all(h, [l, r])
    if name == "∨" && args.size == 2
      l = eval(args[0])
      if true?(l)
        return tt
      r = eval(args[1])
      if false?(l)
        return r
      if true?(r)
        return tt
      if false?(r)
        return l
      return apply_all(h, [l, r])
    if name == "⇒" && args.size == 2
      l = eval(args[0])
      if false?(l)
        return tt
      r = eval(args[1])
      if true?(l)
        return r
      if true?(r)
        return tt
      return apply_all(h, [l, r])
    if name == "¬" && args.size == 1
      l = eval(args[0])
      if true?(l)
        return ff
      if false?(l)
        return tt
      return apply_all(h, [l])
    if name == "nat_rec" && args.size >= 3
      n = eval(args[2])
      if n.tag == :lit
        acc = eval(args[0])
        s = args[1]
        i = 0
        while i < n.val
          acc = eval(mk_app_raw(mk_app_raw(s, mk_nat(i)), acc))
          i += 1
        rest = arr_sub(args, 3, args.size - 3)
        return eval(apply_all(acc, rest))
      if n.tag == :app && n.a.tag == :const && n.a.name == "succ"
        m = n.b
        rest = arr_sub(args, 3, args.size - 3)
        inner = apply_all(h, [args[0], args[1], m])
        return eval(apply_all(mk_app_raw(mk_app_raw(args[1], m), inner), rest))
      ev = [eval(args[0]), eval(args[1]), n] + eval_list(arr_sub(args, 3, args.size - 3))
      return apply_all(h, ev)
    if (name == "∀" || name == "∃") && args.size == 1 && args[0].tag == :lam
      r = eval_bounded(name, args[0])
      if r != nil
        return r
    if @k.defs.has_key?(name)
      f = eval_const(h)
      return eval(apply_all(f, args))
    ev = eval_list(args)
    r = delta(h, ev)
    if r != nil
      return r
    apply_all(h, ev)

  -> eval_list(xs)
    out = []
    xs.each -> (a)
      out.push(eval(a))
    out

  # Primitive reductions on evaluated arguments; nil when none applies.
  -> delta(h, ev)
    name = h.name
    n = ev.size
    if name == "=" && n == 2
      return decide_eq(ev[0], ev[1])
    if n == 1 && ev[0].tag == :lit
      return lit_unary(name, h.ty, ev[0])
    if n == 2 && ev[0].tag == :lit && ev[1].tag == :lit
      return lit_binary(name, h.ty, ev[0], ev[1])
    # n + k  =  succ^k n  on ℕ (add_succ), exposing constructors to nat_rec
    if name == "+" && n == 2 && ev[1].tag == :lit && ev[1].ty.name == "nat" && ev[0].tag != :lit && ev[1].val <= 64
      s = mk_const_raw("succ", ty_fun(ty_nat, ty_nat))
      r = ev[0]
      i = 0
      while i < ev[1].val
        r = mk_app_raw(s, r)
        i += 1
      return r
    if @k.inductives.has_key?(rec_owner(name))
      return iota(h, ev)
    nil

  -> rec_owner(name)
    if name.ends_with?("_rec")
      name.slice(0, name.size - 4)
    else
      ""

  -> iota(h, ev)
    info = @k.inductives[rec_owner(h.name)]
    k = info.ctors.size
    if ev.size < k + 1
      return nil
    target = ev[k]
    sp = strip_app(target)
    ch = sp[0]
    if ch.tag != :const || !@k.ctor_of.has_key?(ch.name) || @k.ctor_of[ch.name] != info.name
      return nil
    ci = 0
    while ci < k && info.ctors[ci][0] != ch.name
      ci += 1
    cargs = sp[1]
    recf = apply_all(h, arr_sub(ev, 0, k))
    callargs = []
    cargs.each -> (a)
      callargs.push(a)
    j = 0
    while j < cargs.size
      at = type_of(cargs[j])
      if at.tag == :c && at.name == info.name
        callargs.push(mk_app_raw(recf, cargs[j]))
      j += 1
    rest = arr_sub(ev, k + 1, ev.size - k - 1)
    eval(apply_all(apply_all(ev[ci], callargs), rest))

  -> ctor_app?(t)
    sp = strip_app(t)
    sp[0].tag == :const && @k.ctor_of.has_key?(sp[0].name)

  -> value?(t)
    if t.tag == :lit
      return true
    if true?(t) || false?(t)
      return true
    if ctor_app?(t)
      sp = strip_app(t)
      sp[1].each -> (a)
        if !value?(a)
          return false
      return true
    false

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
      acc = tt
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

+ KEval
  # Finite expansion of quantifiers over a literal range/list/finite type.
  # Returns ⊤/⊥ or nil when the quantifier is not finitely bounded.
  -> eval_bounded(q, lam)
    ty = lam.ty
    body = lam.b
    dom = nil
    rest = nil
    conn = "⇒"
    if q == "∃"
      conn = "∧"
    g = dest_binop(body, conn)
    if g != nil
      guard = g[0]
      d = dest_binop(guard, "<")
      if d != nil && d[0].tag == :bnd && d[0].idx == 0 && tm_closed_bound?(d[1]) && ty.name == "nat"
        n = eval(d[1])
        if n.tag == :lit
          dom = []
          i = 0
          while i < n.val
            dom.push(mk_nat(i))
            i += 1
          rest = g[1]
      d = dest_binop(guard, "≤")
      if dom == nil && d != nil && d[0].tag == :bnd && d[0].idx == 0 && tm_closed_bound?(d[1]) && ty.name == "nat"
        n = eval(d[1])
        if n.tag == :lit
          dom = []
          i = 0
          while i <= n.val
            dom.push(mk_nat(i))
            i += 1
          rest = g[1]
      d = dest_binop(guard, "mem")
      if dom == nil && d != nil && d[0].tag == :bnd && d[0].idx == 0 && tm_closed_bound?(d[1])
        lst = eval(d[1])
        items = list_literal_items(lst)
        if items != nil
          dom = items
          rest = g[1]
    if dom == nil
      # whole finite types: Prop and enumeration inductives
      if ty.name == "bool" && ty.tag == :c
        dom = [tt, ff]
        rest = body
        conn = nil
      elsif ty.tag == :c && @k.inductives.has_key?(ty.name)
        info = @k.inductives[ty.name]
        enum = true
        info.ctors.each -> (c)
          if c[1].size > 0
            enum = false
        if enum && info.params.size == 0
          dom = []
          info.ctors.each -> (c)
            dom.push(mk_const_raw(c[0], ty))
          rest = body
          conn = nil
    if dom == nil
      return nil
    residue = []
    dom.each -> (x)
      v = eval(tm_instantiate(rest, x, 0))
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
      conn2 = "∧"
      if q == "∃"
        conn2 = "∨"
      c = mk_const_raw(conn2, ty_funs([ty_bool, ty_bool], ty_bool))
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

+ KEval
  # Applications without free variables are memoized (evaluation is a function).
  -> memo_eval_app(t)
    if !closed_term?(t)
      return eval_app(t)
    bucket = @memo[t.h]
    if bucket != nil
      bucket.each -> (pr)
        if tm_eq(pr[0], t)
          return pr[1]
    else
      bucket = []
      @memo[t.h] = bucket
    v = eval_app(t)
    bucket.push([t, v])
    v

-> closed_term?(t)
  t.cl
