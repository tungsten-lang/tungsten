# Satori terms and types.
#
# Types are simple polymorphic types: variables ('a) and constructors applied
# to arguments (bool, nat, fun(a, b), list(a), ...). Terms are locally
# nameless: free variables carry a name and a type, bound variables are de
# Bruijn indices that also carry their type, so `type_of` never needs a
# context and alpha-equivalent terms are structurally identical.
#
# Every KTy is hash-consed (canonical pointer identity + integer id), and
# every KTm carries a structural hash, closedness flags, type-variable flag,
# cached application result type, and built-in constant opcode.

HASH_MOD = 1000000007
STR_HASH_CACHE = {}

-> str_hash(s)
  c = STR_HASH_CACHE[s]
  if c != nil
    return c
  h = 7
  n = s.size
  i = 0
  while i < n
    h = (h * 31 + s.byte_at(i)) % HASH_MOD
    i += 1
  if STR_HASH_CACHE.size < 32768
    STR_HASH_CACHE[s] = h
  h

# Built-in constant opcodes for fast O(1) dispatch in KEval / checkers.
OP_NONE = 0
OP_ITE = 1
OP_AND = 2
OP_OR = 3
OP_IMP = 4
OP_NOT = 5
OP_ALL = 6
OP_EX = 7
OP_NAT_REC = 8
OP_EQ = 9
OP_ADD = 10
OP_SUB = 11
OP_MUL = 12
OP_DIV = 13
OP_MOD = 14
OP_POW = 15
OP_LT = 16
OP_LE = 17
OP_SUCC = 18
OP_NEG = 19
OP_ABS = 20
OP_INT_OF_NAT = 21
OP_RAT_OF_INT = 22
OP_REAL_OF_RAT = 23
OP_NAT_OF_INT = 24
OP_FLOOR = 25
OP_TRUE = 26
OP_FALSE = 27

CONST_OP_TABLE = {
  "ite" => OP_ITE, "∧" => OP_AND, "∨" => OP_OR, "⇒" => OP_IMP,
  "¬" => OP_NOT, "∀" => OP_ALL, "∃" => OP_EX, "nat_rec" => OP_NAT_REC,
  "=" => OP_EQ, "+" => OP_ADD, "-" => OP_SUB, "*" => OP_MUL,
  "/" => OP_DIV, "%" => OP_MOD, "^" => OP_POW, "<" => OP_LT, "≤" => OP_LE,
  "succ" => OP_SUCC, "neg" => OP_NEG, "abs" => OP_ABS,
  "int_of_nat" => OP_INT_OF_NAT, "rat_of_int" => OP_RAT_OF_INT,
  "real_of_rat" => OP_REAL_OF_RAT, "nat_of_int" => OP_NAT_OF_INT,
  "floor" => OP_FLOOR, "⊤" => OP_TRUE, "⊥" => OP_FALSE
}

-> const_opcode(name)
  op = CONST_OP_TABLE[name]
  if op == nil
    return OP_NONE
  op

+ KTy
  ro :tag, :name, :args, :h, :id, :has_var

  -> new(@tag, @name, @args, @id, @has_var, @h)
    @key = nil

  -> key
    if @key != nil
      return @key
    if @tag == :v
      @key = "'" + @name
    else
      n = @args.size
      if n == 0
        @key = @name
      elsif n == 1
        @key = @name + "(" + @args[0].key + ")"
      elsif n == 2
        @key = @name + "(" + @args[0].key + "," + @args[1].key + ")"
      else
        parts = Array.new(n)
        i = 0
        while i < n
          parts[i] = @args[i].key
          i += 1
        @key = @name + "(" + parts.join(",") + ")"
    @key

  -> var?
    @tag == :v

  -> fun?
    @tag == :c && @name == "fun"

  -> dom
    @args[0]

  -> cod
    @args[1]

  -> to_s
    ty_show(self)

TY_STATE = [0]
TY_VAR_CACHE = {}
TY_CON0_CACHE = {}
TY_FUN_CACHE = {}
TY_CON_CACHE = {}

-> ty_var(n)
  c = TY_VAR_CACHE[n]
  if c != nil
    return c
  id = TY_STATE[0]
  TY_STATE[0] = id + 1
  h = (str_hash(n) * 37 + 1) % HASH_MOD
  c = KTy.new(:v, n, [], id, true, h)
  TY_VAR_CACHE[n] = c
  c

-> intern_ty_con0(n)
  c = TY_CON0_CACHE[n]
  if c != nil
    return c
  id = TY_STATE[0]
  TY_STATE[0] = id + 1
  h = (str_hash(n) * 41 + 2) % HASH_MOD
  c = KTy.new(:c, n, [], id, false, h)
  TY_CON0_CACHE[n] = c
  c

-> ty_fun(a, b)
  k = (a.id << 22) + b.id
  c = TY_FUN_CACHE[k]
  if c != nil
    return c
  id = TY_STATE[0]
  TY_STATE[0] = id + 1
  h = (a.h * 59 + b.h * 13 + 3) % HASH_MOD
  c = KTy.new(:c, "fun", [a, b], id, a.has_var || b.has_var, h)
  TY_FUN_CACHE[k] = c
  c

-> ty_con(n, args)
  na = args.size
  if na == 0
    return intern_ty_con0(n)
  if na == 2 && n == "fun"
    return ty_fun(args[0], args[1])
  h = (str_hash(n) * 43 + na) % HASH_MOD
  hv = false
  i = 0
  while i < na
    ai = args[i]
    h = (h * 61 + ai.h + 7) % HASH_MOD
    if ai.has_var
      hv = true
    i += 1
  bucket = TY_CON_CACHE[h]
  if bucket != nil
    nb = bucket.size
    bi = 0
    while bi < nb
      cand = bucket[bi]
      if cand.name == n && cand.args.size == na
        same = true
        j = 0
        while j < na
          if cand.args[j] != args[j]
            same = false
            break
          j += 1
        if same
          return cand
      bi += 1
  else
    bucket = []
    TY_CON_CACHE[h] = bucket
  id = TY_STATE[0]
  TY_STATE[0] = id + 1
  c = KTy.new(:c, n, args, id, hv, h)
  bucket.push(c)
  c

-> ty_eq(a, b)
  a == b || (a.h == b.h && a.key == b.key)

-> ty_funs(args, res)
  t = res
  i = args.size - 1
  while i >= 0
    t = ty_fun(args[i], t)
    i -= 1
  t

TY_BOOL_SINGLETON = intern_ty_con0("bool")
TY_NAT_SINGLETON = intern_ty_con0("nat")
TY_INT_SINGLETON = intern_ty_con0("int")
TY_RAT_SINGLETON = intern_ty_con0("rat")
TY_REAL_SINGLETON = intern_ty_con0("real")

-> ty_bool
  TY_BOOL_SINGLETON

-> ty_nat
  TY_NAT_SINGLETON

-> ty_int
  TY_INT_SINGLETON

-> ty_rat
  TY_RAT_SINGLETON

-> ty_real
  TY_REAL_SINGLETON

-> ty_show(t)
  if t.tag == :v
    return "'" + t.name
  case t.name
  when "fun"
    a = t.args[0]
    l = ty_show(a)
    if a.fun?
      l = "(" + l + ")"
    l + " → " + ty_show(t.args[1])
  when "bool"
    "Prop"
  when "nat"
    "ℕ"
  when "int"
    "ℤ"
  when "rat"
    "ℚ"
  when "real"
    "ℝ"
  when "prod"
    l = ty_show(t.args[0])
    r = ty_show(t.args[1])
    if t.args[0].fun? || (t.args[0].tag == :c && t.args[0].name == "prod")
      l = "(" + l + ")"
    if t.args[1].fun?
      r = "(" + r + ")"
    l + " × " + r
  else
    if t.args.size == 0
      t.name
    else
      parts = [t.name]
      t.args.each -> (a)
        s = ty_show(a)
        if a.args.size > 0 && a.tag == :c
          s = "(" + s + ")"
        parts.push(s)
      parts.join(" ")

-> ty_subst(t, m)
  if !t.has_var || m.size == 0
    return t
  if t.tag == :v
    r = m[t.name]
    if r != nil
      return r
    return t
  na = t.args.size
  if na == 2 && t.name == "fun"
    a0 = ty_subst(t.args[0], m)
    a1 = ty_subst(t.args[1], m)
    if a0 == t.args[0] && a1 == t.args[1]
      return t
    return ty_fun(a0, a1)
  changed = false
  out = Array.new(na)
  i = 0
  while i < na
    a = t.args[i]
    b = ty_subst(a, m)
    if b != a
      changed = true
    out[i] = b
    i += 1
  if changed
    ty_con(t.name, out)
  else
    t

-> ty_vars_into(t, acc)
  if !t.has_var
    return acc
  if t.tag == :v
    if !acc.include?(t.name)
      acc.push(t.name)
  else
    na = t.args.size
    i = 0
    while i < na
      ty_vars_into(t.args[i], acc)
      i += 1
  acc

-> ty_vars(t)
  if !t.has_var
    return []
  ty_vars_into(t, [])

-> ty_occurs(name, t)
  if !t.has_var
    return false
  if t.tag == :v
    return t.name == name
  na = t.args.size
  i = 0
  while i < na
    if ty_occurs(name, t.args[i])
      return true
    i += 1
  false

# One-way matching: extends m so that ty_subst(pat, m) == t. Returns false on failure.
-> ty_match(pat, t, m)
  if !pat.has_var
    return ty_eq(pat, t)
  if pat.tag == :v
    prev = m[pat.name]
    if prev != nil
      return ty_eq(prev, t)
    m[pat.name] = t
    return true
  if t.tag == :v
    return false
  if pat.name != t.name || pat.args.size != t.args.size
    return false
  i = 0
  n = pat.args.size
  while i < n
    if !ty_match(pat.args[i], t.args[i], m)
      return false
    i += 1
  true


# ---------------------------------------------------------------------------
# Terms

# Presence flags let tactics skip traversals of subterms that cannot contribute.
TERM_MINMAX = 1
TERM_DIVMOD = 2
TERM_SQUARE_PRODUCT = 4
TERM_LAMBDA = 8
TERM_WIDEN = 16
TERM_POWER = 32
TERM_BETA_REDEX = 64
TERM_ETA_CANDIDATE = 128
TERM_FINITE_SUM = 256

# Packed bitfield layout in KTm#@bits (fits KTm into 8 ivar slots total):
#   bit  0     : cl (closed w.r.t. free vars)
#   bit  1     : tv (mentions type variables)
#   bits 2..6  : op (5-bit built-in constant opcode 0..31)
#   bits 7..15 : search_ops (9-bit presence flags)
#   bits 16+   : mx (max loose de Bruijn index + 1)
TM_BIT_CL = 1
TM_BIT_TV = 2
TM_SOPS_SHIFT = 7
TM_SOPS_MASK = 65408          # 511 << 7
TM_BIT_SQ_PROD = 512          # TERM_SQUARE_PRODUCT << 7
TM_BIT_LAMBDA = 1024          # TERM_LAMBDA << 7
TM_BIT_WIDEN = 2048           # TERM_WIDEN << 7
TM_BIT_BETA = 8192            # TERM_BETA_REDEX << 7
TM_BIT_ETA = 16384            # TERM_ETA_CANDIDATE << 7

+ KTm
  ro :tag, :bits, :h, :ty, :a, :b, :name, :val

  # 8-slot compact layout:
  #   :var   -> name, ty, b = vkey
  #   :const -> name, ty
  #   :app   -> a = fn, b = arg, ty = cached codomain (when known)
  #   :lam   -> name = hint, ty = binder type, b = body
  #   :bnd   -> ty, val = de Bruijn index
  #   :lit   -> ty, val = Int or [num, den]
  -> new(@tag, @bits, @h, @ty, @a, @b, @name, @val)

  -> cl
    (@bits & 1) != 0

  -> tv
    (@bits & 2) != 0

  -> op
    (@bits >> 2) & 31

  -> search_ops
    (@bits >> 7) & 511

  -> mx
    @bits >> 16

  -> idx
    @val

  -> vkey
    @b

  -> has_widening_cast?
    (@bits & TM_BIT_WIDEN) != 0

  -> to_s
    tm_show(self)

-> lit_key(v)
  if type(v) == "Array"
    v[0].to_s + "/" + v[1].to_s
  else
    v.to_s

# Reuse immutable nodes built repeatedly by substitution and proof search.
# Each slot holds one candidate. A hash collision evicts it; only an exact
# match of all constructor arguments (including binder hints) can reuse it.
VAR_TM_SLOTS = Array.new(16384)
VAR_TM_MASK = 16383

-> mk_var(n, ty)
  nh = str_hash(n)
  slot = (nh + ty.id * 31) & VAR_TM_MASK
  h = (nh * 31 + ty.h + 1) % HASH_MOD
  t = VAR_TM_SLOTS[slot]
  if t != nil && t.h == h && t.name == n && t.ty == ty
    return t
  bits = ty.has_var ? TM_BIT_TV : 0
  vkey = n + "#" + ty.id.to_s
  t = KTm.new(:var, bits, h, ty, nil, vkey, n, nil)
  VAR_TM_SLOTS[slot] = t
  t

CONST_TM_CACHE = {}

-> mk_const_raw(n, ty)
  by_ty = CONST_TM_CACHE[n]
  if by_ty != nil
    c = by_ty[ty.id]
    if c != nil
      return c
  else
    by_ty = {}
    CONST_TM_CACHE[n] = by_ty
  op = const_opcode(n)
  sops = 0
  if n == "min" || n == "max"
    sops = TERM_MINMAX
  elsif n == "sum_below" || n == "sum_list"
    sops = TERM_FINITE_SUM
  elsif op == OP_DIV || op == OP_MOD
    sops = TERM_DIVMOD
  elsif op == OP_POW
    sops = TERM_POWER
  elsif op >= OP_INT_OF_NAT && op <= OP_REAL_OF_RAT
    sops = TERM_WIDEN
  bits = TM_BIT_CL | (ty.has_var ? TM_BIT_TV : 0) | (op << 2) | (sops << TM_SOPS_SHIFT)
  h = (str_hash(n) * 37 + ty.h + 2) % HASH_MOD
  c = KTm.new(:const, bits, h, ty, nil, nil, n, nil)
  if by_ty.size < 256
    by_ty[ty.id] = c
  c

BND_CACHE = {}

-> mk_bnd(i, ty)
  if i >= 0 && i < 32
    k = (ty.id << 5) + i
    c = BND_CACHE[k]
    if c != nil
      return c
    bits = TM_BIT_CL | (ty.has_var ? TM_BIT_TV : 0) | ((i + 1) << 16)
    h = (i * 47 + ty.h * 59 + 5) % HASH_MOD
    c = KTm.new(:bnd, bits, h, ty, nil, nil, nil, i)
    if BND_CACHE.size < 16384
      BND_CACHE[k] = c
    return c
  bits = TM_BIT_CL | (ty.has_var ? TM_BIT_TV : 0) | ((i + 1) << 16)
  h = (i * 47 + ty.h * 59 + 5) % HASH_MOD
  KTm.new(:bnd, bits, h, ty, nil, nil, nil, i)

# Small ℕ/ℤ/ℚ/ℝ integer literals are shared across the session.
LIT_CACHE = {}

-> make_lit_tm(v, ty)
  lh = 0
  if type(v) == "Array"
    lh = ((v[0] % HASH_MOD) * 97 + (v[1] % HASH_MOD) + HASH_MOD * 2) % HASH_MOD
  else
    lh = ((v % HASH_MOD) + HASH_MOD) % HASH_MOD
  bits = TM_BIT_CL | (ty.has_var ? TM_BIT_TV : 0)
  h = (lh * 53 + ty.h + 6) % HASH_MOD
  KTm.new(:lit, bits, h, ty, nil, nil, nil, v)

-> mk_lit(v, ty)
  if ty.tag == :c
    if v.is_a?(Integer) && v > -2048 && v < 65536
      if ty == TY_NAT_SINGLETON
        key = v * 4
        c = LIT_CACHE[key]
        if c != nil
          return c
        c = make_lit_tm(v, ty)
        LIT_CACHE[key] = c
        return c
      if ty == TY_INT_SINGLETON
        key = v * 4 + 1
        c = LIT_CACHE[key]
        if c != nil
          return c
        c = make_lit_tm(v, ty)
        LIT_CACHE[key] = c
        return c
    elsif type(v) == "Array" && v[1] == 1 && v[0].is_a?(Integer) && v[0] > -2048 && v[0] < 65536
      if ty == TY_RAT_SINGLETON
        key = v[0] * 4 + 2
        c = LIT_CACHE[key]
        if c != nil
          return c
        c = make_lit_tm(v, ty)
        LIT_CACHE[key] = c
        return c
      if ty == TY_REAL_SINGLETON
        key = v[0] * 4 + 3
        c = LIT_CACHE[key]
        if c != nil
          return c
        c = make_lit_tm(v, ty)
        LIT_CACHE[key] = c
        return c
  make_lit_tm(v, ty)

-> mk_nat(n)
  mk_lit(n, TY_NAT_SINGLETON)

APP_TM_SLOTS = Array.new(65536)
APP_TM_MASK = 65535

-> mk_app_raw(f, x)
  fh = f.h
  xh = x.h
  raw_h = fh * 41 + xh * 7
  slot = raw_h & APP_TM_MASK
  h = (raw_h + 3) % HASH_MOD
  t = APP_TM_SLOTS[slot]
  if t != nil && t.h == h && t.a == f && t.b == x
    return t
  fb = f.bits
  xb = x.bits
  ftag = f.tag
  cl_tv_sops = (fb & xb & TM_BIT_CL) | ((fb | xb) & (TM_BIT_TV | TM_SOPS_MASK))
  ty = nil
  if ftag == :lam
    cl_tv_sops = cl_tv_sops | TM_BIT_BETA
  else
    if ftag == :app && ((f.a.bits >> 2) & 31) == OP_MUL && f.b.h == xh
      cl_tv_sops = cl_tv_sops | TM_BIT_SQ_PROD
    fty = f.ty
    if fty != nil && fty.fun?
      ty = fty.cod
  fmx = fb >> 16
  xmx = xb >> 16
  mx = fmx > xmx ? fmx : xmx
  bits = cl_tv_sops | (mx << 16)
  t = KTm.new(:app, bits, h, ty, f, x, nil, nil)
  APP_TM_SLOTS[slot] = t
  t

LAM_TM_SLOTS = Array.new(8192)
LAM_TM_MASK = 8191

-> mk_lam_raw(hint, ty, body)
  tyh = ty.h
  bh = body.h
  raw_h = tyh * 43 + bh * 11
  slot = raw_h & LAM_TM_MASK
  h = (raw_h + 4) % HASH_MOD
  t = LAM_TM_SLOTS[slot]
  if t != nil && t.h == h && t.b == body && t.ty == ty && t.name == hint
    return t
  bb = body.bits
  cl_tv_sops = (bb & (TM_BIT_CL | TM_BIT_TV | TM_SOPS_MASK)) | TM_BIT_LAMBDA
  if ty.has_var
    cl_tv_sops = cl_tv_sops | TM_BIT_TV
  if body.tag == :app
    b_arg = body.b
    if b_arg.tag == :bnd && b_arg.val == 0
      cl_tv_sops = cl_tv_sops | TM_BIT_ETA
  bmx = bb >> 16
  mx = bmx > 1 ? bmx - 1 : 0
  bits = cl_tv_sops | (mx << 16)
  t = KTm.new(:lam, bits, h, ty, nil, body, hint, nil)
  LAM_TM_SLOTS[slot] = t
  t

-> tm_eq(a, b)
  if a == b
    return true
  if a.h != b.h || a.tag != b.tag
    return false
  case a.tag
  when :var
    a.name == b.name && ty_eq(a.ty, b.ty)
  when :const
    a.name == b.name && ty_eq(a.ty, b.ty)
  when :app
    tm_eq(a.a, b.a) && tm_eq(a.b, b.b)
  when :lam
    ty_eq(a.ty, b.ty) && tm_eq(a.b, b.b)
  when :bnd
    a.idx == b.idx && ty_eq(a.ty, b.ty)
  else
    ty_eq(a.ty, b.ty) && lit_val_eq(a.val, b.val)

-> tm_contains?(t, subterm)
  if tm_eq(t, subterm)
    return true
  if t.tag == :app
    return tm_contains?(t.a, subterm) || tm_contains?(t.b, subterm)
  t.tag == :lam && tm_contains?(t.b, subterm)

-> lit_val_eq(va, vb)
  if type(va) == "Array"
    return type(vb) == "Array" && va[0] == vb[0] && va[1] == vb[1]
  type(vb) != "Array" && va == vb

# Structural term-set helper (avoids allocating tm_key strings).
-> tm_set_add?(seen, t)
  bucket = seen[t.h]
  if bucket != nil
    nb = bucket.size
    i = 0
    while i < nb
      if tm_eq(bucket[i], t)
        return false
      i += 1
    bucket.push(t)
    return true
  seen[t.h] = [t]
  true

-> tm_set_has?(seen, t)
  bucket = seen[t.h]
  if bucket == nil
    return false
  nb = bucket.size
  i = 0
  while i < nb
    if tm_eq(bucket[i], t)
      return true
    i += 1
  false

-> type_of(t)
  case t.tag
  when :app
    if t.ty != nil
      return t.ty
    ft = type_of(t.a)
    if !ft.fun?
      raise "type_of: applying a non-function: " + tm_show(t)
    ft.cod
  when :lam
    ty_fun(t.ty, type_of(t.b))
  else
    t.ty

# Checked application.
-> mk_app(f, x)
  ft = type_of(f)
  if !ft.fun?
    raise "mk_app: not a function: " + tm_show(f) + " : " + ty_show(ft)
  if !ty_eq(ft.dom, type_of(x))
    raise "mk_app: type mismatch applying " + tm_show(f) + " : " + ty_show(ft) + " to " + tm_show(x) + " : " + ty_show(type_of(x))
  mk_app_raw(f, x)

-> mk_apps(f, xs)
  t = f
  n = xs.size
  i = 0
  while i < n
    t = mk_app(t, xs[i])
    i += 1
  t

# Replace free variable v (name + type) by bound index `depth` throughout t.
-> tm_abstract(t, v, depth)
  if (t.bits & 1) != 0
    return t
  tag = t.tag
  if tag == :app
    ta = t.a
    tb = t.b
    a = tm_abstract(ta, v, depth)
    b = tm_abstract(tb, v, depth)
    if a.h == ta.h && b.h == tb.h && a == ta && b == tb
      return t
    return mk_app_raw(a, b)
  if tag == :var
    if t.name == v.name && ty_eq(t.ty, v.ty)
      return mk_bnd(depth, t.ty)
    return t
  if tag == :lam
    tb = t.b
    b = tm_abstract(tb, v, depth + 1)
    if b.h == tb.h && b == tb
      return t
    return mk_lam_raw(t.name, t.ty, b)
  t

# Replace bound index `depth` by the (locally closed) term u.
-> tm_instantiate(t, u, depth)
  if (t.bits >> 16) <= depth
    return t
  tag = t.tag
  if tag == :app
    ta = t.a
    tb = t.b
    a = tm_instantiate(ta, u, depth)
    b = tm_instantiate(tb, u, depth)
    if a.h == ta.h && b.h == tb.h && a == ta && b == tb
      return t
    return mk_app_raw(a, b)
  if tag == :bnd
    if t.val == depth
      return u
    return t
  if tag == :lam
    tb = t.b
    b = tm_instantiate(tb, u, depth + 1)
    if b.h == tb.h && b == tb
      return t
    return mk_lam_raw(t.name, t.ty, b)
  t

-> mk_lam(v, body)
  if v.tag != :var
    raise "mk_lam: binder is not a variable"
  mk_lam_raw(v.name, v.ty, tm_abstract(body, v, 0))

-> mk_lams(vs, body)
  t = body
  i = vs.size - 1
  while i >= 0
    t = mk_lam(vs[i], t)
    i -= 1
  t

# Head beta step: (λx. b) a  ~>  b[a/x]
-> beta_head(t)
  tm_instantiate(t.a.b, t.b, 0)

-> tm_free_in?(v, t)
  if t.cl
    return false
  case t.tag
  when :var
    t.name == v.name && ty_eq(t.ty, v.ty)
  when :app
    tm_free_in?(v, t.a) || tm_free_in?(v, t.b)
  when :lam
    tm_free_in?(v, t.b)
  else
    false

-> tm_name_free?(name, t)
  if t.cl
    return false
  case t.tag
  when :var
    t.name == name
  when :app
    tm_name_free?(name, t.a) || tm_name_free?(name, t.b)
  when :lam
    tm_name_free?(name, t.b)
  else
    false

-> tm_free_names_into(t, set)
  if t.cl
    return set
  case t.tag
  when :var
    set[t.name] = true
  when :app
    tm_free_names_into(t.a, set)
    tm_free_names_into(t.b, set)
  when :lam
    tm_free_names_into(t.b, set)
  set

-> fresh_name_from_set(base, set)
  name = base
  k = 0
  while set.has_key?(name)
    k += 1
    name = base + k.to_s
  set[name] = true
  name

-> tm_frees_into(t, acc, seen)
  if t.cl
    return acc
  case t.tag
  when :var
    k = t.vkey
    if !seen.has_key?(k)
      seen[k] = true
      acc.push(t)
  when :app
    tm_frees_into(t.a, acc, seen)
    tm_frees_into(t.b, acc, seen)
  when :lam
    tm_frees_into(t.b, acc, seen)
  acc

-> tm_frees(t)
  if t.cl
    return []
  tm_frees_into(t, [], {})

-> tm_tyvars_into(t, acc)
  if !t.tv
    return acc
  case t.tag
  when :app
    tm_tyvars_into(t.a, acc)
    tm_tyvars_into(t.b, acc)
  when :lam
    ty_vars_into(t.ty, acc)
    tm_tyvars_into(t.b, acc)
  else
    ty_vars_into(t.ty, acc)
  acc

-> tm_tyvars(t)
  if !t.tv
    return []
  tm_tyvars_into(t, [])

# A name not free in any of the given terms, based on `base`.
-> fresh_name(base, terms)
  n = terms.size
  if n > 2
    set = {}
    i = 0
    while i < n
      tm_free_names_into(terms[i], set)
      i += 1
    return fresh_name_from_set(base, set)
  name = base
  k = 0
  while true
    clash = false
    i = 0
    while i < n
      if tm_name_free?(name, terms[i])
        clash = true
        break
      i += 1
    if !clash
      return name
    k += 1
    name = base + k.to_s

# Open a lambda with a fresh variable: returns [var, body].
-> dest_lam_fresh(t, avoid)
  hint = t.name
  if hint == nil || hint == ""
    hint = "x"
  n = fresh_name(hint, avoid + [t])
  v = mk_var(n, t.ty)
  [v, tm_instantiate(t.b, v, 0)]

# Simultaneous substitution of free variables. m: var_key -> term.
-> tm_subst(t, m)
  if t.cl || m.size == 0
    return t
  case t.tag
  when :var
    r = m[t.vkey]
    if r != nil
      return r
    t
  when :app
    a = tm_subst(t.a, m)
    b = tm_subst(t.b, m)
    if a == t.a && b == t.b
      return t
    mk_app_raw(a, b)
  when :lam
    b = tm_subst(t.b, m)
    if b == t.b
      return t
    mk_lam_raw(t.name, t.ty, b)
  else
    t

-> var_key(v)
  v.vkey

-> tm_inst_types(t, m)
  if !t.tv || m.size == 0
    return t
  case t.tag
  when :var
    nt = ty_subst(t.ty, m)
    if nt == t.ty
      return t
    mk_var(t.name, nt)
  when :const
    nt = ty_subst(t.ty, m)
    if nt == t.ty
      return t
    mk_const_raw(t.name, nt)
  when :bnd
    nt = ty_subst(t.ty, m)
    if nt == t.ty
      return t
    mk_bnd(t.idx, nt)
  when :lit
    nt = ty_subst(t.ty, m)
    if nt.tag == :c && (nt.name == "rat" || nt.name == "real") && type(t.val) != "Array"
      return mk_lit([t.val, 1], nt)
    if nt == t.ty
      return t
    mk_lit(t.val, nt)
  when :app
    a = tm_inst_types(t.a, m)
    b = tm_inst_types(t.b, m)
    if a == t.a && b == t.b
      return t
    mk_app_raw(a, b)
  else
    nt = ty_subst(t.ty, m)
    nb = tm_inst_types(t.b, m)
    if nt == t.ty && nb == t.b
      return t
    mk_lam_raw(t.name, nt, nb)

# Strip an application spine: f a1 ... an -> [f, [a1..an]]
-> strip_app(t)
  if t.tag != :app
    return [t, []]
  t1 = t.a
  if t1.tag != :app
    return [t1, [t.b]]
  t2 = t1.a
  if t2.tag != :app
    return [t2, [t1.b, t.b]]
  t3 = t2.a
  if t3.tag != :app
    return [t3, [t2.b, t1.b, t.b]]
  cnt = 0
  cur = t
  while cur.tag == :app
    cnt += 1
    cur = cur.a
  args = Array.new(cnt)
  idx = cnt - 1
  cur = t
  while cur.tag == :app
    args[idx] = cur.b
    idx -= 1
    cur = cur.a
  [cur, args]

-> head_const?(t, name)
  while t.tag == :app
    t = t.a
  t.tag == :const && t.name == name

-> is_const?(t, name)
  t.tag == :const && t.name == name

# For a binary operator application `op l r`, return [l, r] or nil.
-> dest_binop(t, name)
  if t.tag == :app
    ta = t.a
    if ta.tag == :app
      taa = ta.a
      if taa.tag == :const && taa.name == name
        return [ta.b, t.b]
  nil

-> dest_binop_op(t, op)
  if t.tag == :app
    ta = t.a
    if ta.tag == :app
      taa = ta.a
      if taa.tag == :const && ((taa.bits >> 2) & 31) == op
        return [ta.b, t.b]
  nil

-> dest_unop(t, name)
  if t.tag == :app
    ta = t.a
    if ta.tag == :const && ta.name == name
      return t.b
  nil

-> dest_unop_op(t, op)
  if t.tag == :app
    ta = t.a
    if ta.tag == :const && ((ta.bits >> 2) & 31) == op
      return t.b
  nil

-> lam_count_bound(t, depth)
  t.mx > depth

# True when t has no loose bound variables.
-> tm_closed_bound?(t)
  t.mx == 0

# ---------------------------------------------------------------------------
# Rationals over arbitrary-precision Int: [num, den], den > 0, reduced.

Q_ZERO = [0, 1]
Q_ONE = [1, 1]
Q_NEG_ONE = [-1, 1]

# The mathematical integers promote at every width. Use the boxed arithmetic
# operations even when both operands happen to fit a machine register.
-> zadd(a, b)
  (a ## int) + b

-> zsub(a, b)
  (a ## int) - b

-> zmul(a, b)
  (a ## int) * b

-> int_gcd(a, b)
  if a < 0
    a = zsub(0, a)
  if b < 0
    b = zsub(0, b)
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> q_make(n, d)
  if d == 0
    raise "rational with zero denominator"
  if n == 0
    return Q_ZERO
  if d < 0
    n = zsub(0, n)
    d = zsub(0, d)
  if d == 1
    if n == 1
      return Q_ONE
    if n == -1
      return Q_NEG_ONE
    return [n, 1]
  g = int_gcd(n, d)
  if g > 1
    n = n / g
    d = d / g
  [n, d]

-> q_add(x, y)
  yn = y[0]
  if yn == 0
    return x
  xn = x[0]
  if xn == 0
    return y
  xd = x[1]
  yd = y[1]
  if xd == 1 && yd == 1
    s = zadd(xn, yn)
    if s == 0
      return Q_ZERO
    if s == 1
      return Q_ONE
    if s == -1
      return Q_NEG_ONE
    return [s, 1]
  if xd == yd
    return q_make(zadd(xn, yn), xd)
  q_make(zadd(zmul(xn, yd), zmul(yn, xd)), zmul(xd, yd))

-> q_sub(x, y)
  yn = y[0]
  if yn == 0
    return x
  xn = x[0]
  if xn == 0
    return [zsub(0, yn), y[1]]
  xd = x[1]
  yd = y[1]
  if xd == 1 && yd == 1
    s = zsub(xn, yn)
    if s == 0
      return Q_ZERO
    if s == 1
      return Q_ONE
    if s == -1
      return Q_NEG_ONE
    return [s, 1]
  if xd == yd
    return q_make(zsub(xn, yn), xd)
  q_make(zsub(zmul(xn, yd), zmul(yn, xd)), zmul(xd, yd))

-> q_mul(x, y)
  xn = x[0]
  if xn == 0
    return Q_ZERO
  yn = y[0]
  if yn == 0
    return Q_ZERO
  xd = x[1]
  yd = y[1]
  if xd == 1
    if xn == 1
      return y
    if xn == -1
      return [zsub(0, yn), yd]
  if yd == 1
    if yn == 1
      return x
    if yn == -1
      return [zsub(0, xn), xd]
  if xd == 1 && yd == 1
    return [zmul(xn, yn), 1]
  g1 = (yd == 1 || xn == 1 || xn == -1) ? 1 : int_gcd(xn, yd)
  g2 = (xd == 1 || yn == 1 || yn == -1) ? 1 : int_gcd(yn, xd)
  n1 = g1 > 1 ? xn / g1 : xn
  d2 = g1 > 1 ? yd / g1 : yd
  n2 = g2 > 1 ? yn / g2 : yn
  d1 = g2 > 1 ? xd / g2 : xd
  n = zmul(n1, n2)
  d = zmul(d1, d2)
  if d == 1
    if n == 1
      return Q_ONE
    if n == -1
      return Q_NEG_ONE
    return [n, 1]
  [n, d]

-> q_div(x, y)
  if y[0] == 0
    raise "rational with zero denominator"
  if x[0] == 0
    return Q_ZERO
  if y[0] < 0
    return q_mul(x, [zsub(0, y[1]), zsub(0, y[0])])
  q_mul(x, [y[1], y[0]])

-> q_neg(x)
  if x[0] == 0
    return Q_ZERO
  [zsub(0, x[0]), x[1]]

-> q_cmp(x, y)
  if x[1] == y[1]
    if x[0] < y[0]
      return -1
    if x[0] > y[0]
      return 1
    return 0
  l = zmul(x[0], y[1])
  r = zmul(y[0], x[1])
  if l < r
    -1
  elsif l > r
    1
  else
    0

-> q_zero?(x)
  x[0] == 0

# Floor division and modulus on Int (sign of the divisor), division by 0 gives 0.
-> int_fdiv(a, b)
  if b == 0
    return 0
  q = a / b
  if (a % b != 0) && ((a < 0) != (b < 0))
    q = zsub(q, 1)
  q

-> int_fmod(a, b)
  if b == 0
    return a
  zsub(a, zmul(b, int_fdiv(a, b)))

-> int_pow(a, e)
  if e <= 0
    return 1
  r = 1
  base = a
  exp = e
  while exp > 0
    if (exp & 1) == 1
      r = zmul(r, base)
    exp = exp >> 1
    if exp > 0
      base = zmul(base, base)
  r

# Preallocated slice copy (avoids Array#slice view-table retention and push reallocs).
-> arr_sub(a, start, len)
  stop = start + len
  if stop > a.size
    stop = a.size
  cnt = stop - start
  if cnt <= 0
    return []
  out = Array.new(cnt)
  i = 0
  while i < cnt
    out[i] = a[start + i]
    i += 1
  out
