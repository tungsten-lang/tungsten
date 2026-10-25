# Satori terms and types.
#
# Types are simple polymorphic types: variables ('a) and constructors applied
# to arguments (bool, nat, fun(a, b), list(a), ...). Terms are locally
# nameless: free variables carry a name and a type, bound variables are de
# Bruijn indices that also carry their type, so `type_of` never needs a
# context and alpha-equivalent terms are structurally identical.
#
# Every node carries a structural hash so equality tests reject quickly.

HASH_MOD = 1000000007

-> str_hash(s)
  h = 7
  n = s.size
  i = 0
  while i < n
    h = (h * 31 + s.byte_at(i)) % HASH_MOD
    i += 1
  h

+ KTy
  ro :tag, :name, :args, :key, :h

  -> new(@tag, @name, @args)
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
        parts = []
        i = 0
        while i < n
          parts.push(@args[i].key)
          i += 1
        @key = @name + "(" + parts.join(",") + ")"
    @h = str_hash(@key)

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

-> ty_eq(a, b)
  a == b || (a.h == b.h && a.key == b.key)

-> ty_var(n)
  KTy.new(:v, n, [])

-> ty_con(n, args)
  KTy.new(:c, n, args)

-> ty_fun(a, b)
  KTy.new(:c, "fun", [a, b])

-> ty_funs(args, res)
  t = res
  i = args.size - 1
  while i >= 0
    t = ty_fun(args[i], t)
    i -= 1
  t

TY_BOOL_SINGLETON = KTy.new(:c, "bool", [])
TY_NAT_SINGLETON = KTy.new(:c, "nat", [])
TY_INT_SINGLETON = KTy.new(:c, "int", [])
TY_RAT_SINGLETON = KTy.new(:c, "rat", [])
TY_REAL_SINGLETON = KTy.new(:c, "real", [])

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
  if t.tag == :v
    if m.has_key?(t.name)
      return m[t.name]
    return t
  if t.args.size == 0
    return t
  changed = false
  out = []
  t.args.each -> (a)
    b = ty_subst(a, m)
    if !(b.h == a.h && b.key == a.key)
      changed = true
    out.push(b)
  if changed
    ty_con(t.name, out)
  else
    t

-> ty_vars_into(t, acc)
  if t.tag == :v
    if !acc.include?(t.name)
      acc.push(t.name)
  else
    t.args.each -> (a)
      ty_vars_into(a, acc)
  acc

-> ty_vars(t)
  ty_vars_into(t, [])

-> ty_occurs(name, t)
  if t.tag == :v
    return t.name == name
  t.args.each -> (a)
    if ty_occurs(name, a)
      return true
  false

# One-way matching: extends m so that ty_subst(pat, m) == t. Returns false on failure.
-> ty_match(pat, t, m)
  if pat.tag == :v
    if m.has_key?(pat.name)
      return ty_eq(m[pat.name], t)
    m[pat.name] = t
    return true
  if t.tag == :v
    return false
  if pat.name != t.name || pat.args.size != t.args.size
    return false
  i = 0
  while i < pat.args.size
    if !ty_match(pat.args[i], t.args[i], m)
      return false
    i += 1
  true


# ---------------------------------------------------------------------------
# Terms

+ KTm
  ro :tag, :name, :ty, :a, :b, :idx, :val, :h, :cl, :mx

  # tag :var(name, ty)  :const(name, ty)  :app(a = fn, b = arg)
  #     :lam(name = hint, ty = binder type, b = body)  :bnd(idx, ty)
  #     :lit(val, ty)   val is an Int for nat/int, [num, den] for rat/real
  -> new(@tag, @name, @ty, @a, @b, @idx, @val)
    @cl = true
    # mx: 1 + the largest loose de Bruijn index (0 when locally closed)
    @mx = 0
    case @tag
    when :var
      @cl = false
      @h = (str_hash(@name) * 31 + @ty.h + 1) % HASH_MOD
    when :const
      @h = (str_hash(@name) * 37 + @ty.h + 2) % HASH_MOD
    when :app
      @cl = @a.cl && @b.cl
      @mx = @a.mx
      if @b.mx > @mx
        @mx = @b.mx
      @h = (@a.h * 41 + @b.h * 7 + 3) % HASH_MOD
    when :lam
      @cl = @b.cl
      if @b.mx > 1
        @mx = @b.mx - 1
      @h = (@ty.h * 43 + @b.h * 11 + 4) % HASH_MOD
    when :bnd
      @mx = @idx + 1
      @h = (@idx * 47 + 5) % HASH_MOD
    else
      @h = (str_hash(lit_key(@val)) * 53 + @ty.h + 6) % HASH_MOD

  -> to_s
    tm_show(self)

-> lit_key(v)
  if v.class_name == "Array"
    v[0].to_s + "/" + v[1].to_s
  else
    v.to_s

-> mk_var(n, ty)
  KTm.new(:var, n, ty, nil, nil, 0, nil)

-> mk_const_raw(n, ty)
  KTm.new(:const, n, ty, nil, nil, 0, nil)

-> mk_bnd(i, ty)
  KTm.new(:bnd, nil, ty, nil, nil, i, nil)

# Small ℕ/ℤ literals are shared (Tungsten has no tracing GC; evaluation would
# otherwise allocate a fresh node for every intermediate number).
LIT_CACHE = {}

-> mk_lit(v, ty)
  if v.class_name == "Int" && v > -2048 && v < 65536 && ty.tag == :c && (ty.name == "nat" || ty.name == "int")
    key = v * 2
    if ty.name == "int"
      key = key + 1
    c = LIT_CACHE[key]
    if c != nil
      return c
    c = KTm.new(:lit, nil, ty, nil, nil, 0, v)
    LIT_CACHE[key] = c
    return c
  KTm.new(:lit, nil, ty, nil, nil, 0, v)

-> mk_nat(n)
  mk_lit(n, ty_nat)

-> mk_app_raw(f, x)
  KTm.new(:app, nil, nil, f, x, 0, nil)

-> mk_lam_raw(hint, ty, body)
  KTm.new(:lam, hint, ty, nil, body, 0, nil)

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
    a.idx == b.idx
  else
    ty_eq(a.ty, b.ty) && lit_val_eq(a.val, b.val)

-> lit_val_eq(va, vb)
  if va.class_name == "Array"
    return vb.class_name == "Array" && va[0] == vb[0] && va[1] == vb[1]
  vb.class_name != "Array" && va == vb

-> type_of(t)
  case t.tag
  when :var
    t.ty
  when :const
    t.ty
  when :bnd
    t.ty
  when :lit
    t.ty
  when :lam
    ty_fun(t.ty, type_of(t.b))
  else
    ft = type_of(t.a)
    if !ft.fun?
      raise "type_of: applying a non-function: " + tm_show(t)
    ft.cod

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
  if t.cl
    return t
  case t.tag
  when :var
    if t.name == v.name && ty_eq(t.ty, v.ty)
      return mk_bnd(depth, t.ty)
    t
  when :app
    a = tm_abstract(t.a, v, depth)
    b = tm_abstract(t.b, v, depth)
    if a == t.a && b == t.b
      return t
    mk_app_raw(a, b)
  when :lam
    b = tm_abstract(t.b, v, depth + 1)
    if b == t.b
      return t
    mk_lam_raw(t.name, t.ty, b)
  else
    t

# Replace bound index `depth` by the (locally closed) term u.
-> tm_instantiate(t, u, depth)
  if t.mx <= depth
    return t
  case t.tag
  when :bnd
    if t.idx == depth
      return u
    t
  when :app
    a = tm_instantiate(t.a, u, depth)
    b = tm_instantiate(t.b, u, depth)
    if a == t.a && b == t.b
      return t
    mk_app_raw(a, b)
  when :lam
    b = tm_instantiate(t.b, u, depth + 1)
    if b == t.b
      return t
    mk_lam_raw(t.name, t.ty, b)
  else
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

-> tm_frees_into(t, acc, seen)
  if t.cl
    return acc
  case t.tag
  when :var
    k = t.name + ":" + t.ty.key
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
  tm_frees_into(t, [], {})

-> tm_tyvars_into(t, acc)
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
  tm_tyvars_into(t, [])

# A name not free in any of the given terms, based on `base`.
-> fresh_name(base, terms)
  name = base
  k = 0
  n = terms.size
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

# Simultaneous substitution of free variables. m: key "name:tykey" -> term.
-> tm_subst(t, m)
  if t.cl
    return t
  case t.tag
  when :var
    k = t.name + ":" + t.ty.key
    if m.has_key?(k)
      return m[k]
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
  v.name + ":" + v.ty.key

-> tm_inst_types(t, m)
  case t.tag
  when :var
    mk_var(t.name, ty_subst(t.ty, m))
  when :const
    mk_const_raw(t.name, ty_subst(t.ty, m))
  when :bnd
    mk_bnd(t.idx, ty_subst(t.ty, m))
  when :lit
    nt = ty_subst(t.ty, m)
    if nt.tag == :c && (nt.name == "rat" || nt.name == "real") && t.val.class_name != "Array"
      return mk_lit([t.val, 1], nt)
    mk_lit(t.val, nt)
  when :app
    mk_app_raw(tm_inst_types(t.a, m), tm_inst_types(t.b, m))
  else
    mk_lam_raw(t.name, ty_subst(t.ty, m), tm_inst_types(t.b, m))

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
  args = []
  while t.tag == :app
    args.push(t.b)
    t = t.a
  lo = 0
  hi = args.size - 1
  while lo < hi
    tmp = args[lo]
    args[lo] = args[hi]
    args[hi] = tmp
    lo += 1
    hi -= 1
  [t, args]

-> head_const?(t, name)
  while t.tag == :app
    t = t.a
  t.tag == :const && t.name == name

-> is_const?(t, name)
  t.tag == :const && t.name == name

# For a binary operator application `op l r`, return [l, r] or nil.
-> dest_binop(t, name)
  if t.tag == :app && t.a.tag == :app && t.a.a.tag == :const && t.a.a.name == name
    [t.a.b, t.b]
  else
    nil

-> dest_unop(t, name)
  if t.tag == :app && t.a.tag == :const && t.a.name == name
    t.b
  else
    nil

-> lam_count_bound(t, depth)
  t.mx > depth

# True when t has no loose bound variables.
-> tm_closed_bound?(t)
  t.mx == 0

# ---------------------------------------------------------------------------
# Rationals over arbitrary-precision Int: [num, den], den > 0, reduced.

-> int_gcd(a, b)
  if a < 0
    a = 0 - a
  if b < 0
    b = 0 - b
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> q_make(n, d)
  if d == 0
    raise "rational with zero denominator"
  if d < 0
    n = 0 - n
    d = 0 - d
  g = int_gcd(n, d)
  if g > 1
    n = n / g
    d = d / g
  [n, d]

-> q_add(x, y)
  q_make(zadd(x[0] * y[1], y[0] * x[1]), x[1] * y[1])

-> q_sub(x, y)
  q_make(zsub(x[0] * y[1], y[0] * x[1]), x[1] * y[1])

-> q_mul(x, y)
  q_make(x[0] * y[0], x[1] * y[1])

-> q_div(x, y)
  q_make(x[0] * y[1], x[1] * y[0])

-> q_neg(x)
  [0 - x[0], x[1]]

-> q_cmp(x, y)
  l = x[0] * y[1]
  r = y[0] * x[1]
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
  zsub(a, b * int_fdiv(a, b))

-> int_pow(a, e)
  r = 1
  while e > 0
    r = r * a
    e -= 1
  r

# ---------------------------------------------------------------------------
# Overflow-safe integer addition. TODO(tungsten compiler): compiled Int + Int
# and Int - Int wrap on i64 overflow instead of promoting to BigInt
# (multiplication promotes correctly). Until that is fixed, kernel arithmetic
# routes large operands through multiplication, which promotes: 4a and 4b
# exceed i64, so the sum is formed in BigInt and the exact division by 4
# keeps it there.
BIG_GUARD = 2305843009213693952

-> zadd(a, b)
  if a.class_name == "Int" && b.class_name == "Int" && (a >= BIG_GUARD || a <= 0 - BIG_GUARD || b >= BIG_GUARD || b <= 0 - BIG_GUARD)
    return (a * 4 + b * 4) / 4
  a + b

-> zsub(a, b)
  if a.class_name == "Int" && b.class_name == "Int" && (a >= BIG_GUARD || a <= 0 - BIG_GUARD || b >= BIG_GUARD || b <= 0 - BIG_GUARD)
    return (a * 4 - b * 4) / 4
  a - b

# Copy of a[start, start+len). Array#slice creates a registered view and the
# runtime never prunes its view table (slicing a view scans every registered
# view), which made long evaluations quadratic: see
# ~/math/openai/TUNGSTEN_ISSUES.md #5. TODO(tungsten runtime): drop when fixed.
-> arr_sub(a, start, len)
  out = []
  i = start
  stop = start + len
  if stop > a.size
    stop = a.size
  while i < stop
    out.push(a[i])
    i += 1
  out
