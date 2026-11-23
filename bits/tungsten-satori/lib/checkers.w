# Trusted checkers used by the kernel: commutative-ring normal forms,
# literal CNF extraction and an LRAT (RUP) refutation checker.
#
# These are deliberately simple and heuristic-free. The LRAT checker shares
# no code with any SAT solver: it replays each hinted unit-propagation chain.

# ---------------------------------------------------------------------------
# Canonical structural key of a term (kept for diagnostic/external callers).

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
# Polynomials: Hash(Int mono_id -> rational [num, den]).
# mono_id == 0 is the constant monomial `1`.
# Every non-constant monomial is interned inside RingCtx as a flat sorted array
# [atom_id_0, exp_0, atom_id_1, exp_1, ...] with integer hash-consing and
# pair-multiplication caching, avoiding all string formatting and splitting.

+ RingCtx
  ro :atoms, :monos
  -> new(@kind)
    @atoms = {}
    @atom_count = 0
    # monos[0] = [] (constant 1); monos[id] = [aid0, exp0, ...]
    @monos = [[]]
    @mono_buckets = {}
    @mul_cache = {}
    @atom_monos = [0]

  -> atom(t)
    bucket = @atoms[t.h]
    if bucket != nil
      nb = bucket.size
      i = 0
      while i < nb
        pr = bucket[i]
        if tm_eq(pr[0], t)
          return pr[1]
        i += 1
    else
      bucket = []
      @atoms[t.h] = bucket
    @atom_count += 1
    aid = @atom_count
    bucket.push([t, aid])
    mid = intern_mono([aid, 1])
    @atom_monos.push(mid)
    aid

  -> atom_mono(t)
    aid = atom(t)
    @atom_monos[aid]

  -> intern_mono(vec)
    n = vec.size
    if n == 0
      return 0
    h = 17
    i = 0
    while i < n
      h = (h * 131 + vec[i]) % HASH_MOD
      i += 1
    bucket = @mono_buckets[h]
    if bucket != nil
      nb = bucket.size
      bi = 0
      while bi < nb
        mid = bucket[bi]
        cand = @monos[mid]
        if cand.size == n
          same = true
          k = 0
          while k < n
            if cand[k] != vec[k]
              same = false
              break
            k += 1
          if same
            return mid
        bi += 1
    else
      bucket = []
      @mono_buckets[h] = bucket
    mid = @monos.size
    @monos.push(vec)
    bucket.push(mid)
    mid

  -> mono_mul(a, b)
    if a == 0
      return b
    if b == 0
      return a
    lo = a
    hi = b
    if lo > hi
      lo = b
      hi = a
    ck = (lo << 20) + hi
    cached = @mul_cache[ck]
    if cached != nil
      return cached
    va = @monos[a]
    vb = @monos[b]
    na = va.size
    nb = vb.size
    ia = 0
    ib = 0
    merged = []
    while ia < na && ib < nb
      ka = va[ia]
      kb = vb[ib]
      if ka < kb
        merged.push(ka)
        merged.push(va[ia + 1])
        ia += 2
      elsif kb < ka
        merged.push(kb)
        merged.push(vb[ib + 1])
        ib += 2
      else
        merged.push(ka)
        merged.push(va[ia + 1] + vb[ib + 1])
        ia += 2
        ib += 2
    while ia < na
      merged.push(va[ia])
      merged.push(va[ia + 1])
      ia += 2
    while ib < nb
      merged.push(vb[ib])
      merged.push(vb[ib + 1])
      ib += 2
    res = intern_mono(merged)
    if @mul_cache.size < 65536
      @mul_cache[ck] = res
    res

-> poly_const(q)
  p = {}
  if q[0] != 0
    p[0] = q
  p

-> poly_add(p, r)
  if p.size == 0
    return r
  if r.size == 0
    return p
  out = {}
  p.each -> (k, v)
    out[k] = v
  r.each -> (k, v)
    prev = out[k]
    if prev != nil
      s = q_add(prev, v)
      if s[0] == 0
        out.delete(k)
      else
        out[k] = s
    else
      out[k] = v
  out

-> poly_add_scaled!(acc, p, q)
  if q[0] == 0 || p.size == 0
    return acc
  q_is_one = q[0] == 1 && q[1] == 1
  q_is_neg1 = q[0] == -1 && q[1] == 1
  p.each -> (k, v)
    sv = q_is_one ? v : (q_is_neg1 ? q_neg(v) : q_mul(v, q))
    prev = acc[k]
    if prev != nil
      s = q_add(prev, sv)
      if s[0] == 0
        acc.delete(k)
      else
        acc[k] = s
    else
      acc[k] = sv
  acc

-> poly_scale(p, q)
  out = {}
  if q[0] == 0 || p.size == 0
    return out
  if q[0] == 1 && q[1] == 1
    return p
  if q[0] == -1 && q[1] == 1
    p.each -> (k, v)
      out[k] = q_neg(v)
    return out
  p.each -> (k, v)
    out[k] = q_mul(v, q)
  out

-> poly_mul(p, r, ctx)
  out = {}
  if p.size == 0 || r.size == 0
    return out
  p.each -> (a, pa)
    r.each -> (b, rb)
      m = ctx.mono_mul(a, b)
      c = q_mul(pa, rb)
      prev = out[m]
      if prev != nil
        s = q_add(prev, c)
        if s[0] == 0
          out.delete(m)
        else
          out[m] = s
      else
        out[m] = c
  out

-> poly_eq?(a, b)
  if a.size != b.size
    return false
  ok = true
  a.each -> (k, qa)
    if ok
      qb = b[k]
      if qb == nil || qa[0] != qb[0] || qa[1] != qb[1]
        ok = false
  ok

-> poly_key(p)
  ks = p.keys.sort
  parts = []
  ks.each -> (k)
    parts.push(k.to_s + "=" + lit_key(p[k]))
  parts.join(";")

# Normal form of an expression of the given numeric kind, or nil.
-> ring_normal(t, kind)
  ring_norm(t, kind, RingCtx.new(kind))

-> ring_lit_q(t, kind)
  if kind == "rat" || kind == "real"
    t.val
  else
    [t.val, 1]

-> ring_ground_const_q(t)
  if t.tag == :lit
    if type(t.val) == "Array"
      return t.val
    return [t.val, 1]
  if t.tag == :app && t.a.tag == :const
    uop = t.a.op
    if uop == OP_INT_OF_NAT || uop == OP_RAT_OF_INT || uop == OP_REAL_OF_RAT
      return ring_ground_const_q(t.b)
  nil

-> ring_wrap_casts(u, casts)
  nc = casts.size
  if nc == 0
    return u
  at = u
  i = nc - 1
  while i >= 0
    at = mk_app_raw(casts[i], at)
    i -= 1
  at

-> ring_norm(t, kind, ctx)
  ring_norm_cast(t, kind, [], ctx)

# Homomorphic polynomial normalizer across ℕ → ℤ → ℚ → ℝ widening casts.
# Widening casts preserve literals, +, *, literal-exponent ^, and succ (on ℕ);
# rat_of_int / real_of_rat additionally preserve - and neg (never on ℕ, where
# subtraction is truncated); real_of_rat additionally preserves / by a nonzero
# constant polynomial (never on ℕ or ℤ, where division is Euclidean).
-> ring_norm_cast(t, cur_kind, casts, ctx)
  if t.tag == :lit
    return poly_const(ring_lit_q(t, cur_kind))
  if t.tag == :app
    ta = t.a
    if ta.tag == :app && ta.a.tag == :const
      op = ta.a.op
      lhs = ta.b
      rhs = t.b
      if op == OP_ADD
        return poly_add(ring_norm_cast(lhs, cur_kind, casts, ctx), ring_norm_cast(rhs, cur_kind, casts, ctx))
      if op == OP_MUL
        return poly_mul(ring_norm_cast(lhs, cur_kind, casts, ctx), ring_norm_cast(rhs, cur_kind, casts, ctx), ctx)
      if op == OP_SUB && cur_kind != "nat"
        return poly_add(ring_norm_cast(lhs, cur_kind, casts, ctx), poly_scale(ring_norm_cast(rhs, cur_kind, casts, ctx), Q_NEG_ONE))
      if op == OP_POW && rhs.tag == :lit
        exp = rhs.val
        if exp == 0
          return poly_const(Q_ONE)
        base = ring_norm_cast(lhs, cur_kind, casts, ctx)
        if exp == 1
          return base
        if exp == 2
          return poly_mul(base, base, ctx)
        res = poly_const(Q_ONE)
        cur = base
        e = exp
        while e > 0
          if (e & 1) == 1
            res = poly_mul(res, cur, ctx)
          e = e >> 1
          if e > 0
            cur = poly_mul(cur, cur, ctx)
        return res
      if op == OP_DIV && (cur_kind == "rat" || cur_kind == "real")
        pr = ring_norm_cast(rhs, cur_kind, casts, ctx)
        if pr.size == 1 && pr.has_key?(0) && pr[0][0] != 0
          return poly_scale(ring_norm_cast(lhs, cur_kind, casts, ctx), q_div(Q_ONE, pr[0]))
    elsif ta.tag == :const
      uop = ta.op
      if uop == OP_NEG && cur_kind != "nat"
        return poly_scale(ring_norm_cast(t.b, cur_kind, casts, ctx), Q_NEG_ONE)
      if uop == OP_SUCC && cur_kind == "nat"
        return poly_add(ring_norm_cast(t.b, cur_kind, casts, ctx), poly_const(Q_ONE))
      if uop == OP_REAL_OF_RAT && cur_kind == "real"
        return ring_norm_cast(t.b, "rat", casts + [ta], ctx)
      if uop == OP_RAT_OF_INT && cur_kind == "rat"
        return ring_norm_cast(t.b, "int", casts + [ta], ctx)
      if uop == OP_INT_OF_NAT && cur_kind == "int"
        return ring_norm_cast(t.b, "nat", casts + [ta], ctx)
  p = {}
  p[ctx.atom_mono(ring_wrap_casts(t, casts))] = Q_ONE
  p

# ---------------------------------------------------------------------------
# Literal CNF: a closed term of type list (list int) built from cons/nil and
# int literals. Returns an array of clauses (arrays of nonzero Ints) or nil.

-> list_literal_items(t)
  out = []
  while true
    if t.tag == :const && t.name == "nil"
      return out
    if t.tag == :app && t.a.tag == :app && t.a.a.tag == :const && t.a.a.name == "cons"
      out.push(t.a.b)
      t = t.b
    else
      return nil

-> cnf_literal_value(t)
  raw_clauses = list_literal_items(t)
  if raw_clauses == nil
    return nil
  clauses = []
  raw_clauses.each -> (rc)
    items = list_literal_items(rc)
    if items == nil
      return nil
    cl = []
    items.each -> (it)
      if it.tag != :lit || it.val == 0
        return nil
      cl.push(it.val)
    clauses.push(cl)
  clauses

# ---------------------------------------------------------------------------
# LRAT checking (RUP steps with hints). Clause ids 1..m are the input clauses.
# Single-pass byte scanner + flat clause array + generation-stamped assignment
# array (zero String#split or per-clause Hash allocations).

-> lrat_lit_idx(l)
  if l > 0
    l * 2
  else
    (0 - l) * 2 + 1

-> lrat_ensure_stamp(stamp, idx)
  while stamp.size <= idx
    stamp.push(0)

-> lrat_ensure_db(db, id)
  while db.size <= id
    db.push(nil)

-> lrat_rup_fast(db, lits, hints, stamp, gen)
  nl = lits.size
  i = 0
  while i < nl
    nl_idx = lrat_lit_idx(0 - lits[i])
    if nl_idx >= stamp.size
      lrat_ensure_stamp(stamp, nl_idx + 64)
    stamp[nl_idx] = gen
    i += 1
  db_len = db.size
  nh = hints.size
  hi = 0
  while hi < nh
    hid = hints[hi]
    if hid <= 0 || hid >= db_len
      return false
    cl = db[hid]
    if cl == nil
      return false
    unassigned = 0
    unit = 0
    ncl = cl.size
    ci = 0
    while ci < ncl
      l = cl[ci]
      pidx = l > 0 ? l * 2 : (0 - l) * 2 + 1
      nidx = l > 0 ? l * 2 + 1 : (0 - l) * 2
      if pidx >= stamp.size || nidx >= stamp.size
        mx = pidx > nidx ? pidx : nidx
        lrat_ensure_stamp(stamp, mx + 64)
      if stamp[pidx] == gen
        return false
      if stamp[nidx] != gen
        unassigned += 1
        if unassigned > 1
          return false
        unit = l
      ci += 1
    if unassigned == 0
      return true
    u_idx = unit > 0 ? unit * 2 : (0 - unit) * 2 + 1
    stamp[u_idx] = gen
    hi += 1
  false

-> lrat_check(clauses, text)
  m = clauses.size
  max_v = 16
  i = 0
  while i < m
    cl = clauses[i]
    nc = cl.size
    j = 0
    while j < nc
      v = cl[j]
      if v < 0
        v = 0 - v
      if v > max_v
        max_v = v
      j += 1
    i += 1
  db = Array.new(m + 256)
  i = 0
  while i < m
    db[i + 1] = clauses[i]
    i += 1
  stamp = Array.new(max_v * 2 + 64, 0)
  hints = []
  gen = 0
  n = text.size
  pos = 0
  while pos < n
    # skip leading horizontal whitespace / blank lines
    while pos < n
      b = text.byte_at(pos)
      if b == 32 || b == 9 || b == 13 || b == 10
        pos += 1
      else
        break
    if pos >= n
      break
    b = text.byte_at(pos)
    if b == 99
      # comment line 'c ...'
      while pos < n && text.byte_at(pos) != 10
        pos += 1
    else
      # parse step id
      neg = false
      if b == 45
        neg = true
        pos += 1
      id = 0
      has_dig = false
      while pos < n
        bd = text.byte_at(pos)
        if bd >= 48 && bd <= 57
          id = id * 10 + (bd - 48)
          has_dig = true
          pos += 1
        else
          break
      if !has_dig
        while pos < n && text.byte_at(pos) != 10
          pos += 1
      else
        if neg
          id = 0 - id
        while pos < n
          bs = text.byte_at(pos)
          if bs == 32 || bs == 9
            pos += 1
          else
            break
        if pos < n && text.byte_at(pos) == 100
          # deletion line: `<id> d <cid...> 0`
          pos += 1
          while pos < n
            while pos < n && (text.byte_at(pos) == 32 || text.byte_at(pos) == 9 || text.byte_at(pos) == 13)
              pos += 1
            if pos >= n || text.byte_at(pos) == 10
              break
            dneg = false
            if text.byte_at(pos) == 45
              dneg = true
              pos += 1
            did = 0
            dh = false
            while pos < n
              bd = text.byte_at(pos)
              if bd >= 48 && bd <= 57
                did = did * 10 + (bd - 48)
                dh = true
                pos += 1
              else
                break
            if !dh
              break
            if dneg
              did = 0 - did
            if did == 0
              while pos < n && text.byte_at(pos) != 10
                pos += 1
              break
            if did > 0 && did < db.size
              db[did] = nil
        else
          # RUP addition line: `<id> <lits...> 0 <hints...> 0`
          lits = []
          while pos < n
            while pos < n && (text.byte_at(pos) == 32 || text.byte_at(pos) == 9 || text.byte_at(pos) == 13)
              pos += 1
            if pos >= n || text.byte_at(pos) == 10
              break
            lneg = false
            if text.byte_at(pos) == 45
              lneg = true
              pos += 1
            lv = 0
            lh = false
            while pos < n
              bd = text.byte_at(pos)
              if bd >= 48 && bd <= 57
                lv = lv * 10 + (bd - 48)
                lh = true
                pos += 1
              else
                break
            if !lh
              break
            if lneg
              lv = 0 - lv
            if lv == 0
              break
            lits.push(lv)
          hints.clear
          while pos < n
            while pos < n && (text.byte_at(pos) == 32 || text.byte_at(pos) == 9 || text.byte_at(pos) == 13)
              pos += 1
            if pos >= n || text.byte_at(pos) == 10
              break
            hneg = false
            if text.byte_at(pos) == 45
              hneg = true
              pos += 1
            hv = 0
            hh = false
            while pos < n
              bd = text.byte_at(pos)
              if bd >= 48 && bd <= 57
                hv = hv * 10 + (bd - 48)
                hh = true
                pos += 1
              else
                break
            if !hh
              break
            if hneg
              hv = 0 - hv
            if hv == 0
              while pos < n && text.byte_at(pos) != 10
                pos += 1
              break
            hints.push(hv)
          gen += 1
          if !lrat_rup_fast(db, lits, hints, stamp, gen)
            return false
          if lits.size == 0
            return true
          if id >= db.size
            lrat_ensure_db(db, id + 256)
          db[id] = lits
  false

# ---------------------------------------------------------------------------
# Tseitin encoding of a propositional formula over opaque atoms.

+ Tseitin
  ro :clauses, :nvars
  -> new
    @clauses = []
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
    if t.tag == :const
      if t.op == OP_TRUE
        return truth_lit
      if t.op == OP_FALSE
        return 0 - truth_lit
    if t.tag == :app && t.a.tag == :const && t.a.op == OP_NOT
      return 0 - enc(t.b)
    bucket = @memo[t.h]
    if bucket != nil
      nb = bucket.size
      bi = 0
      while bi < nb
        pr = bucket[bi]
        if tm_eq(pr[0], t)
          return pr[1]
        bi += 1
    else
      bucket = []
      @memo[t.h] = bucket
    lit = enc_gate(t)
    bucket.push([t, lit])
    lit

  -> enc_gate(t)
    if t.tag == :app
      ta = t.a
      if ta.tag == :app && ta.a.tag == :const
        op = ta.a.op
        lhs = ta.b
        rhs = t.b
        if op == OP_AND
          x = enc(lhs)
          y = enc(rhs)
          v = fresh
          @clauses.push([0 - v, x])
          @clauses.push([0 - v, y])
          @clauses.push([v, 0 - x, 0 - y])
          return v
        if op == OP_OR
          x = enc(lhs)
          y = enc(rhs)
          v = fresh
          @clauses.push([0 - v, x, y])
          @clauses.push([v, 0 - x])
          @clauses.push([v, 0 - y])
          return v
        if op == OP_IMP
          x = enc(lhs)
          y = enc(rhs)
          v = fresh
          @clauses.push([0 - v, 0 - x, y])
          @clauses.push([v, x])
          @clauses.push([v, 0 - y])
          return v
        if op == OP_EQ && ty_eq(type_of(lhs), TY_BOOL_SINGLETON)
          x = enc(lhs)
          y = enc(rhs)
          v = fresh
          @clauses.push([0 - v, 0 - x, y])
          @clauses.push([0 - v, x, 0 - y])
          @clauses.push([v, x, y])
          @clauses.push([v, 0 - x, 0 - y])
          return v
      if ta.tag == :app && ta.a.tag == :app && ta.a.a.tag == :const && ta.a.a.op == OP_ITE && ty_eq(type_of(t), TY_BOOL_SINGLETON)
        c = enc(ta.a.b)
        x = enc(ta.b)
        y = enc(t.b)
        v = fresh
        @clauses.push([0 - v, 0 - c, x])
        @clauses.push([0 - v, c, y])
        @clauses.push([v, 0 - c, 0 - x])
        @clauses.push([v, c, 0 - y])
        return v
    fresh

-> tseitin_refutation_cnf(phi)
  ts = Tseitin.new
  root = ts.enc(phi)
  cls = ts.clauses
  cls.push([root])
  cls
