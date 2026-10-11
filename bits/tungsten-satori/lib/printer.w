# Pretty-printing of Satori terms in surface notation.

-> infix_table
  {
    "⇒" => ["→", 25, :right], "∨" => ["∨", 30, :right], "∧" => ["∧", 35, :right],
    "=" => ["=", 50, :none], "<" => ["<", 50, :none], "≤" => ["≤", 50, :none],
    "+" => ["+", 65, :left], "-" => ["-", 65, :left], "*" => ["*", 70, :left],
    "/" => ["/", 70, :left], "%" => ["%", 70, :left], "^" => ["^", 75, :right],
    "cons" => ["::", 67, :right], "append" => ["++", 66, :right],
    "mem" => ["∈", 50, :none], "dvd" => ["∣", 50, :none], "pair" => [",", 10, :right]
  }

-> tm_show(t)
  tm_pp(t, [], 0)

-> show_lit(t)
  v = t.val
  if v.class_name == "Array"
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
    nm = pp_fresh(t.name, names)
    paren_if("fun " + nm + " => " + tm_pp(t.b, names + [nm], 0), prec > 0)
  else
    tm_pp_app(t, names, prec)

-> pp_fresh(hint, names)
  base = hint
  if base == nil || base == ""
    base = "x"
  nm = base
  k = 0
  while names.include?(nm)
    k += 1
    nm = base + k.to_s
  nm

-> tm_pp_app(t, names, prec)
  sp = strip_app(t)
  h = sp[0]
  args = sp[1]
  if h.tag == :const
    nm = h.name
    if (nm == "∀" || nm == "∃" || nm == "ε") && args.size == 1 && args[0].tag == :lam
      lam = args[0]
      bn = pp_fresh(lam.name, names)
      body = tm_pp(lam.b, names + [bn], 0)
      return paren_if(nm + " " + bn + ", " + body, prec > 0)
    if nm == "¬" && args.size == 1
      return paren_if("¬" + tm_pp(args[0], names, 90), prec > 90)
    if nm == "neg" && args.size == 1
      return paren_if("-" + tm_pp(args[0], names, 90), prec > 90)
    if nm == "ite" && args.size == 3
      s = "if " + tm_pp(args[0], names, 0) + " then " + tm_pp(args[1], names, 0) + " else " + tm_pp(args[2], names, 0)
      return paren_if(s, prec > 0)
    tbl = infix_table
    if args.size == 2 && tbl.has_key?(nm)
      info = tbl[nm]
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
