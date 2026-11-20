# Pretty-printing of Satori terms in surface notation.

INFIX_TABLE = {
  "⇒" => ["→", 25, :right], "∨" => ["∨", 30, :right], "∧" => ["∧", 35, :right],
  "=" => ["=", 50, :none], "<" => ["<", 50, :none], "≤" => ["≤", 50, :none],
  "+" => ["+", 65, :left], "-" => ["-", 65, :left], "*" => ["*", 70, :left],
  "/" => ["/", 70, :left], "%" => ["%", 70, :left], "^" => ["^", 75, :right],
  "cons" => ["::", 67, :right], "append" => ["++", 66, :right],
  "mem" => ["∈", 50, :none], "dvd" => ["∣", 50, :none]
}

PP_BOUNDED_RELS = [["<", " < "], ["≤", " ≤ "], ["mem", " ∈ "]]

-> infix_table
  INFIX_TABLE

-> tm_show(t)
  tm_pp(t, [], 0)

-> show_lit(t)
  v = t.val
  if type(v) == "Array"
    if v[1] == 1
      v[0].to_s
    else
      v[0].to_s + "/" + v[1].to_s
  else
    v.to_s

-> paren_if(s, cond)
  if cond
    "(" + s + ")"
  else
    s

# names: binder names for bound indices (innermost last).
-> tm_pp(t, names, prec)
  case t.tag
  when :var
    t.name
  when :const
    case t.name
    when "⊤"
      "True"
    when "⊥"
      "False"
    when "nil"
      "\[\]"
    else
      t.name
  when :bnd
    i = names.size - 1 - t.idx
    if i >= 0
      names[i]
    else
      "#" + t.idx.to_s
  when :lit
    show_lit(t)
  when :lam
    nm = pp_fresh(t, names)
    binder = pp_cast_binder?(t) ? "(" + nm + " : " + ty_show(t.ty) + ")" : nm
    paren_if("fun " + binder + " => " + tm_pp(t.b, names + [nm], 0), prec > 0)
  else
    tm_pp_app(t, names, prec)

-> pp_fresh(lam, names)
  base = lam.name
  if base == nil || base == ""
    base = "x"
  nm = base
  k = 0
  while names.include?(nm) || tm_name_free?(nm, lam.b)
    k += 1
    nm = base + k.to_s
  nm

# An untyped binder in (n : ℝ) would infer n : ℝ and erase the cast on re-entry.
-> pp_cast_binder?(lam)
  lam.b.has_widening_cast? && [TY_NAT_SINGLETON, TY_INT_SINGLETON, TY_RAT_SINGLETON, TY_REAL_SINGLETON].include?(lam.ty)

-> tm_pp_app(t, names, prec)
  sp = strip_app(t)
  h = sp[0]
  args = sp[1]
  if h.tag == :const
    nm = h.name
    if h.op >= OP_INT_OF_NAT && h.op <= OP_REAL_OF_RAT && args.size == 1
      src = args[0]
      while src.tag == :app && src.a.op >= OP_INT_OF_NAT && src.a.op <= OP_REAL_OF_RAT
        src = src.b
      operand = tm_pp(src, names, 0)
      # Literals and overloaded operations need their original arithmetic
      # domain: ((1 / 2 : ℕ) : ℝ) must still denote natural division.
      if src.tag != :var && src.tag != :bnd
        operand = "(" + operand + " : " + ty_show(type_of(src)) + ")"
      return "(" + operand + " : " + ty_show(type_of(t)) + ")"
    if (nm == "∀" || nm == "∃") && args.size == 1 && args[0].tag == :lam
      typed = pp_cast_binder?(args[0])
      if !typed
        bq = pp_bounded(nm, args[0], names, prec)
        if bq != nil
          return bq
      # merge directly nested binders of the same kind:  ∀ x y, …
      bns = []
      cur = args[0]
      nms = names
      while true
        bn = pp_fresh(cur, nms)
        bns.push(bn)
        nms = nms + [bn]
        inner = cur.b
        isp = strip_app(inner)
        if isp[0].tag == :const && isp[0].name == nm && isp[1].size == 1 && isp[1][0].tag == :lam && typed == pp_cast_binder?(isp[1][0]) && (!typed || ty_eq(cur.ty, isp[1][0].ty))
          cur = isp[1][0]
        else
          break
      body = tm_pp(cur.b, nms, 0)
      binders = bns.join(" ")
      if typed
        binders = binders + " : " + ty_show(cur.ty)
      return paren_if(nm + " " + binders + ", " + body, prec > 0)
    if nm == "¬" && args.size == 1
      e = dest_binop(args[0], "=")
      if e != nil && type_of(e[0]).name != "bool"
        return paren_if(tm_pp(e[0], names, 51) + " ≠ " + tm_pp(e[1], names, 51), prec > 50)
      return paren_if("¬" + tm_pp(args[0], names, 90), prec > 90)
    if (nm == "sum_below" || nm == "prod_below" || nm == "sum_list" || nm == "prod_list") && args.size == 2 && args[1].tag == :lam
      op = "∑"
      if nm.starts_with?("prod")
        op = "∏"
      rel = " < "
      if nm.ends_with?("list")
        rel = " ∈ "
      lam = args[1]
      bn = pp_fresh(lam, names)
      s2 = op + " " + bn + rel + tm_pp(args[0], names, 66) + ", " + tm_pp(lam.b, names + [bn], 66)
      # the body extends to the right, so any operator context needs parentheses: (∑ i < n, f i) + f n
      return paren_if(s2, prec > 0)
    if nm == "pair" && args.size == 2
      return "(" + tm_pp(args[0], names, 0) + ", " + tm_pp(args[1], names, 0) + ")"
    if nm == "neg" && args.size == 1
      return paren_if("-" + tm_pp(args[0], names, 90), prec > 90)
    if nm == "ite" && args.size == 3
      s = "if " + tm_pp(args[0], names, 0) + " then " + tm_pp(args[1], names, 0) + " else " + tm_pp(args[2], names, 0)
      return paren_if(s, prec > 0)
    info = INFIX_TABLE[nm]
    if args.size == 2 && info != nil
      op = info[0]
      if nm == "=" && type_of(args[0]).name == "bool"
        op = "↔"
      p = info[1]
      lp = p + 1
      rp = p + 1
      if info[2] == :left
        lp = p
      if info[2] == :right
        rp = p
      s = tm_pp(args[0], names, lp) + " " + op + " " + tm_pp(args[1], names, rp)
      return paren_if(s, prec > p)
  parts = [tm_pp(h, names, 100)]
  args.each -> (a)
    parts.push(tm_pp(a, names, 100))
  paren_if(parts.join(" "), prec >= 100)

# ∀ x, x < t → P  ~>  ∀ x < t, P     ∃ x, x ∈ l ∧ P  ~>  ∃ x ∈ l, P
-> pp_bounded(q, lam, names, prec)
  conn = "⇒"
  if q == "∃"
    conn = "∧"
  if q != "∀" && q != "∃"
    return nil
  g = dest_binop(lam.b, conn)
  if g == nil
    return nil
  out = nil
  PP_BOUNDED_RELS.each -> (r)
    if out == nil
      d = dest_binop(g[0], r[0])
      if d != nil && d[0].tag == :bnd && d[0].idx == 0 && !lam_count_bound(d[1], 0)
        bn = pp_fresh(lam, names)
        bound = tm_pp(d[1], names + [bn], 66)
        out = paren_if(q + " " + bn + r[1] + bound + ", " + tm_pp(g[1], names + [bn], 0), prec > 0)
  out
