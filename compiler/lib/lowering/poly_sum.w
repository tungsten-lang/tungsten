# Lowering / poly_sum — polynomial normal form for closed-form ranged sums.
#
# Folds a map-chain over a range whose element function is polynomial into a
# linear combination of power sums (one `w_range_pow_sum` per term), so
# `range / map… : sum` collapses to O(degree²) regardless of range length.
# Extracted from calls.w; consumed by lower_pipeline there.
#
# Depends on the emit helpers from earlier workers (emit_instruction,
# next_temp, typed_value, ast_kind, …). This file deliberately has no `use`
# directives — see pass_registry.w.

# === Polynomial normal form (closed-form ranged sums) ===================
#
# A polynomial in the loop element is a dense array of integer
# coefficients indexed by power: `poly[k]` is the coefficient of xᵏ
# (degree = size−1). The empty array is the zero polynomial. This is a
# LOWERING-INTERNAL normal form, not an AST kind — the recognizer below
# folds an arbitrary map chain into one of these by analyzing each map
# function's *body AST* (resolving named methods like `sq`/`cube` to
# their definitions), then composing. Σ over a range of a polynomial is
# a linear combination of power sums (one `w_range_pow_sum` call per
# term), so the whole `range / map… : sum` collapses to O(degree²),
# independent of the range length.

# Drop trailing zero coefficients so equal polynomials have one shape.
-> poly_trim(p)
  n = p.size()
  while n > 0 && p[n - 1] == 0
    n = n - 1
  if n == p.size()
    return p
  r = []
  i = 0
  while i < n
    r.push(p[i])
    i = i + 1
  r

-> poly_const(c)
  if c == 0
    return []
  [c]

-> poly_var()
  [0, 1]

-> poly_add(a, b)
  n = a.size()
  if b.size() > n
    n = b.size()
  r = []
  i = 0
  while i < n
    av = 0
    if i < a.size()
      av = a[i]
    bv = 0
    if i < b.size()
      bv = b[i]
    r.push(av + bv)
    i = i + 1
  poly_trim(r)

-> poly_scale(a, c)
  if c == 0
    return []
  r = []
  i = 0
  while i < a.size()
    r.push(a[i] * c)
    i = i + 1
  r

-> poly_sub(a, b)
  poly_add(a, poly_scale(b, 0 - 1))

-> poly_mul(a, b)
  if a.size() == 0 || b.size() == 0
    return []
  r = []
  outn = a.size() + b.size() - 1
  z = 0
  while z < outn
    r.push(0)
    z = z + 1
  i = 0
  while i < a.size()
    j = 0
    while j < b.size()
      r[i + j] = r[i + j] + a[i] * b[j]
      j = j + 1
    i = i + 1
  poly_trim(r)

-> poly_pow(a, k)
  r = [1]
  i = 0
  while i < k
    r = poly_mul(r, a)
    i = i + 1
  r

# q(p(x)) = Σ_k q[k]·p(x)ᵏ — substitute one polynomial into another.
-> poly_compose(q, p)
  r = []
  k = 0
  while k < q.size()
    if q[k] != 0
      r = poly_add(r, poly_scale(poly_pow(p, k), q[k]))
    k = k + 1
  r

# P(x) mod 2 depends only on x mod 2: it equals the constant-term parity
# when x is even, and the coefficient-sum parity when x is odd. These two
# helpers expose that, so a parity filter over ANY polynomial resolves to
# a clean x-parity (or keep-all / keep-none) — see the recognizer.
-> poly_const_parity(p)
  c0 = 0
  if p.size() > 0
    c0 = p[0]
  v = c0 % 2
  if v < 0
    v = 0 - v
  v

-> poly_sum_parity(p)
  s = 0
  i = 0
  while i < p.size()
    s = s + p[i]
    i = i + 1
  v = s % 2
  if v < 0
    v = 0 - v
  v

# Emittable iff non-zero, degree ≤ 64 (the Faulhaber cap), and every
# coefficient fits an i64 immediate (huge composed coefficients fall back).
-> poly_emittable(p)
  if p.size() == 0
    return false
  if p.size() - 1 > 64
    return false
  i = 0
  while i < p.size()
    c = p[i]
    if c > 9000000000000000000 || c < 0 - 9000000000000000000
      return false
    i = i + 1
  true

# Resolve a no-arg "pure" method (single-expression body) to its return
# expression, trying the numeric-tower classes in a fixed order so the
# lookup is deterministic (byte-identity). Core methods (`sq`, `cube`, …)
# resolve here too: a range literal autoloads Number (see loader.w), so
# number.w's class def is registered before the pipeline lowers.
-> resolve_pure_method_body(ctx, mname)
  cands = ["Number", "Integer", "Real", "Int", "Float", "Numeric"]
  i = 0
  while i < cands.size()
    node = ctx[:mod][:class_method_asts][cands[i] + "." + mname]
    if node != nil
      stmts = ast_get(node, :body)
      if stmts != nil && stmts.size() == 1
        return stmts[0]
    i = i + 1
  nil

# Extract the polynomial computed by `expr` as a function of the element.
# `var_name` is the element's identifier for a lambda body (nil when the
# element is `self`, as in a resolved method body). Returns nil when
# `expr` is not a polynomial in the element (→ caller falls back to a
# loop). Recursive: a method call resolves the callee's body and composes.
-> poly_of_expr(ctx, expr, var_name, depth)
  if depth > 24
    return nil
  if !is_ast_node?(expr)
    return nil
  k = ast_kind(expr)
  if k == :int
    return poly_const(ast_get(expr, :value))
  if k == :self_ref
    return poly_var()
  if k == :var
    nm = "" + ast_get(expr, :name)
    if var_name != nil && nm == var_name
      return poly_var()
    body = resolve_pure_method_body(ctx, nm)
    if body == nil
      return nil
    return poly_of_expr(ctx, body, nil, depth + 1)
  if k == :binary_op
    bop = ast_get(expr, :op)
    if bop == :POW
      rt = ast_get(expr, :right)
      if !is_ast_node?(rt) || ast_kind(rt) != :int
        return nil
      pbase = poly_of_expr(ctx, ast_get(expr, :left), var_name, depth + 1)
      if pbase == nil
        return nil
      e = ast_get(rt, :value)
      if e < 0 || e > 64
        return nil
      return poly_pow(pbase, e)
    lp = poly_of_expr(ctx, ast_get(expr, :left), var_name, depth + 1)
    if lp == nil
      return nil
    rp = poly_of_expr(ctx, ast_get(expr, :right), var_name, depth + 1)
    if rp == nil
      return nil
    if bop == :PLUS
      return poly_add(lp, rp)
    if bop == :MINUS
      return poly_sub(lp, rp)
    if bop == :STAR
      return poly_mul(lp, rp)
    return nil
  if k == :call
    args = ast_get(expr, :args)
    if args != nil && args.size() > 0
      return nil
    body = resolve_pure_method_body(ctx, "" + ast_get(expr, :name))
    if body == nil
      return nil
    inner = poly_of_expr(ctx, body, nil, depth + 1)
    if inner == nil
      return nil
    recv = ast_get(expr, :receiver)
    if recv == nil
      return inner
    rp = poly_of_expr(ctx, recv, var_name, depth + 1)
    if rp == nil
      return nil
    return poly_compose(inner, rp)
  if k == :block
    params = ast_get(expr, :params)
    body = ast_get(expr, :body)
    if params == nil || params.size() != 1 || body == nil || body.size() != 1
      return nil
    # Block params are bare name strings (parse_lambda pushes identifiers).
    return poly_of_expr(ctx, body[0], "" + params[0], depth + 1)
  nil

# Emit Σ_k cₖ·(Σ_{x∈range, parity} xᵏ) = the closed-form ranged sum of a
# polynomial, as a chain of boxed (BigInt-promoting) w_range_pow_sum /
# w_mul / w_add calls. The result matches the elementwise loop exactly.
-> emit_poly_ranged_sum(wfn, p, lo_cf, hi_cf, parity)
  acc = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: acc, name: "w_int", args: ["0"]})
  k = 0
  while k < p.size()
    c = p[k]
    if c != 0
      pk = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: pk, name: "w_range_pow_sum", args: [lo_cf, hi_cf, k.to_s(), parity.to_s()]})
      term = pk
      if c != 1
        cbox = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: cbox, name: "w_int", args: [c.to_s()]})
        scaled = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: scaled, name: "w_mul", args: [cbox, term]})
        term = scaled
      acc2 = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: acc2, name: "w_add", args: [acc, term]})
      acc = acc2
    k = k + 1
  typed_value(:i64, acc)
