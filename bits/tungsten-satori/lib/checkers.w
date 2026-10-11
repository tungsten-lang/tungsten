# Trusted checkers used by the kernel: commutative-ring normal forms,
# literal CNF extraction and an LRAT (RUP) refutation checker.
#
# These are deliberately simple and heuristic-free. The LRAT checker shares
# no code with any SAT solver: it replays each hinted unit-propagation chain.

# ---------------------------------------------------------------------------
# Canonical structural key of a term (used to identify ring atoms).

-> tm_key(t)
  case t.tag
  when :var
    "v:" + t.name + ":" + t.ty.key
  when :const
    "c:" + t.name + ":" + t.ty.key
  when :bnd
    "b" + t.idx.to_s
  when :lit
    "l:" + lit_key(t.val) + ":" + t.ty.key
  when :lam
    "(λ" + t.ty.key + "." + tm_key(t.b) + ")"
  else
    "(" + tm_key(t.a) + " " + tm_key(t.b) + ")"

# ---------------------------------------------------------------------------
# Polynomials: Hash monomial-key -> rational [num, den]; a monomial key is a
# sorted "atom^exp" list joined by "*" ("" is the constant monomial).

+ RingCtx
  ro :atoms
  -> new(@kind)
    @atoms = {}

  -> atom(t)
    k = tm_key(t)
    if !@atoms.has_key?(k)
      @atoms[k] = "a" + (1000000 + @atoms.size).to_s
    @atoms[k]

-> poly_const(q)
  p = {}
  if q[0] != 0
    p[""] = q
  p

-> poly_add(p, r)
  out = {}
  p.keys.each -> (k)
    out[k] = p[k]
  r.keys.each -> (k)
    if out.has_key?(k)
      s = q_add(out[k], r[k])
      if s[0] == 0
        out.delete(k)
      else
        out[k] = s
    else
      out[k] = r[k]
  out

-> poly_scale(p, q)
  out = {}
  if q[0] == 0
    return out
  p.keys.each -> (k)
    out[k] = q_mul(p[k], q)
  out

-> mono_mul(a, b)
  if a == ""
    return b
  if b == ""
    return a
  exps = {}
  (a.split("*") + b.split("*")).each -> (f)
    parts = f.split("^")
    e = parts[1].to_i
    if exps.has_key?(parts[0])
      exps[parts[0]] = exps[parts[0]] + e
    else
      exps[parts[0]] = e
  names = exps.keys.sort
  out = []
  names.each -> (nm)
    out.push(nm + "^" + exps[nm].to_s)
  out.join("*")

-> poly_mul(p, r)
  out = {}
  p.keys.each -> (a)
    r.keys.each -> (b)
      m = mono_mul(a, b)
      c = q_mul(p[a], r[b])
      if out.has_key?(m)
        s = q_add(out[m], c)
        if s[0] == 0
          out.delete(m)
        else
          out[m] = s
      else
        out[m] = c
  out

-> poly_key(p)
  ks = p.keys.sort
  parts = []
  ks.each -> (k)
    parts.push(k + "=" + lit_key(p[k]))
  parts.join(";")

# Normal form of an expression of the given numeric kind, or nil.
-> ring_normal(t, kind)
  ring_norm(t, kind, RingCtx.new(kind))

-> ring_lit_q(t, kind)
  if kind == "rat" || kind == "real"
    t.val
  else
    [t.val, 1]

-> ring_norm(t, kind, ctx)
  if t.tag == :lit
    return poly_const(ring_lit_q(t, kind))
  b = dest_binop(t, "+")
  if b != nil
    return poly_add(ring_norm(b[0], kind, ctx), ring_norm(b[1], kind, ctx))
  b = dest_binop(t, "*")
  if b != nil
    return poly_mul(ring_norm(b[0], kind, ctx), ring_norm(b[1], kind, ctx))
  if kind != "nat"
    b = dest_binop(t, "-")
    if b != nil
      return poly_add(ring_norm(b[0], kind, ctx), poly_scale(ring_norm(b[1], kind, ctx), [-1, 1]))
    u = dest_unop(t, "neg")
    if u != nil
      return poly_scale(ring_norm(u, kind, ctx), [-1, 1])
  b = dest_binop(t, "^")
  if b != nil && b[1].tag == :lit
    base = ring_norm(b[0], kind, ctx)
    r = poly_const([1, 1])
    i = 0
    while i < b[1].val
      r = poly_mul(r, base)
      i += 1
    return r
  if kind == "rat" || kind == "real"
    b = dest_binop(t, "/")
    if b != nil && b[1].tag == :lit && b[1].val[0] != 0
      return poly_scale(ring_norm(b[0], kind, ctx), q_div([1, 1], b[1].val))
  p = {}
  p[ctx.atom(t) + "^1"] = [1, 1]
  p

# ---------------------------------------------------------------------------
# Literal CNF: a closed term of type list (list int) built from cons/nil and
# int literals. Returns an array of clauses (arrays of nonzero Ints) or nil.

-> list_literal_items(t)
  out = []
  while true
    sp = strip_app(t)
    h = sp[0]
    if h.tag != :const
      return nil
    if h.name == "nil" && sp[1].size == 0
      return out
    if h.name != "cons" || sp[1].size != 2
      return nil
    out.push(sp[1][0])
    t = sp[1][1]

-> cnf_literal_value(t)
  cls = list_literal_items(t)
  if cls == nil
    return nil
  out = []
  cls.each -> (c)
    lits = list_literal_items(c)
    if lits == nil
      return nil
    row = []
    lits.each -> (l)
      if l.tag != :lit || l.ty.name != "int" || l.val == 0
        return nil
      row.push(l.val)
    out.push(row)
  out

# ---------------------------------------------------------------------------
# LRAT checking (RUP steps with hints). Clause ids 1..m are the input clauses.

-> lrat_check(clauses, text)
  db = {}
  i = 0
  while i < clauses.size
    db[i + 1] = clauses[i]
    i += 1
  lines = text.split("\n")
  derived_empty = false
  lines.each -> (line)
    if !derived_empty
      toks = []
      line.split(" ").each -> (w)
        if w != ""
          toks.push(w)
      if toks.size > 0 && toks[0] != "c"
        id = toks[0].to_i
        if toks.size > 1 && toks[1] == "d"
          j = 2
          while j < toks.size && toks[j] != "0"
            db.delete(toks[j].to_i)
            j += 1
        else
          lits = []
          j = 1
          while j < toks.size && toks[j] != "0"
            lits.push(toks[j].to_i)
            j += 1
          j += 1
          hints = []
          while j < toks.size && toks[j] != "0"
            hints.push(toks[j].to_i)
            j += 1
          if !lrat_rup(db, lits, hints)
            return false
          db[id] = lits
          if lits.size == 0
            derived_empty = true
  derived_empty

# Assign the negation of `lits`, then each hint must be unit or conflicting.
-> lrat_rup(db, lits, hints)
  val = {}
  lits.each -> (l)
    val[0 - l] = true
  hints.each -> (hid)
    if hid <= 0 || !db.has_key?(hid)
      return false
    cl = db[hid]
    unassigned = 0
    unit = 0
    sat = false
    cl.each -> (l)
      if val.has_key?(l)
        sat = true
      elsif !val.has_key?(0 - l)
        unassigned += 1
        unit = l
    if sat
      return false
    if unassigned == 0
      return true
    if unassigned > 1
      return false
    val[unit] = true
  false

# ---------------------------------------------------------------------------
# Tseitin encoding of a propositional formula over opaque atoms.
# Atoms are maximal subterms that are not ⊤ ⊥ ¬ ∧ ∨ ⇒, = on Prop, or
# Prop-valued ite; equal atoms (structurally) share a variable. Returns
# [clauses, root_literal, atom_count]. Equisatisfiable with the formula.

+ Tseitin
  ro :clauses, :nvars
  -> new
    @clauses = []
    @atoms = {}
    @nvars = 0
    @true_var = 0
    @memo = {}

  -> fresh
    @nvars += 1
    @nvars

  -> truth_lit
    if @true_var == 0
      @true_var = fresh
      @clauses.push([@true_var])
    @true_var

  -> enc(t)
    if t.tag == :const && t.name == "⊤"
      return truth_lit
    if t.tag == :const && t.name == "⊥"
      return 0 - truth_lit
    u = dest_unop(t, "¬")
    if u != nil
      return 0 - enc(u)
    bucket = @memo[t.h]
    if bucket != nil
      bucket.each -> (pr)
        if tm_eq(pr[0], t)
          return pr[1]
    else
      bucket = []
      @memo[t.h] = bucket
    lit = enc_gate(t)
    bucket.push([t, lit])
    lit

  -> enc_gate(t)
    b = dest_binop(t, "∧")
    if b != nil
      x = enc(b[0])
      y = enc(b[1])
      v = fresh
      @clauses.push([0 - v, x])
      @clauses.push([0 - v, y])
      @clauses.push([v, 0 - x, 0 - y])
      return v
    b = dest_binop(t, "∨")
    if b != nil
      x = enc(b[0])
      y = enc(b[1])
      v = fresh
      @clauses.push([0 - v, x, y])
      @clauses.push([v, 0 - x])
      @clauses.push([v, 0 - y])
      return v
    b = dest_binop(t, "⇒")
    if b != nil
      x = enc(b[0])
      y = enc(b[1])
      v = fresh
      @clauses.push([0 - v, 0 - x, y])
      @clauses.push([v, x])
      @clauses.push([v, 0 - y])
      return v
    b = dest_binop(t, "=")
    if b != nil && type_of(b[0]).tag == :c && type_of(b[0]).name == "bool"
      x = enc(b[0])
      y = enc(b[1])
      v = fresh
      @clauses.push([0 - v, 0 - x, y])
      @clauses.push([0 - v, x, 0 - y])
      @clauses.push([v, x, y])
      @clauses.push([v, 0 - x, 0 - y])
      return v
    sp = strip_app(t)
    if sp[0].tag == :const && sp[0].name == "ite" && sp[1].size == 3 && ty_eq(type_of(t), ty_bool)
      c = enc(sp[1][0])
      x = enc(sp[1][1])
      y = enc(sp[1][2])
      v = fresh
      @clauses.push([0 - v, 0 - c, x])
      @clauses.push([0 - v, c, y])
      @clauses.push([v, 0 - c, 0 - x])
      @clauses.push([v, c, 0 - y])
      return v
    # atom
    fresh

-> tseitin_refutation_cnf(phi)
  ts = Tseitin.new
  root = ts.enc(phi)
  cls = []
  ts.clauses.each -> (c)
    cls.push(c)
  cls.push([root])
  cls
