# Satori parser: logical lines -> command ASTs; token slices -> expression ASTs.

+ Ast
  rw :kind, :s, :kids, :binders, :ty, :line
  -> new(@kind, @s, @kids)
    @binders = []
    @ty = nil
    @line = 0

-> ast(kind, s, kids)
  Ast.new(kind, s, kids)

# A binder: name, type AST (or nil), optional relation and bound for ∀ x ∈ S.
+ Binder
  ro :name, :ty, :rel, :bound
  -> new(@name, @ty, @rel, @bound)

+ TacNode
  ro :toks, :block, :line
  -> new(@toks, @block, @line)

+ Cmd
  rw :kind, :name, :binders, :ty, :body, :tactics, :eqns, :ctors, :params, :line, :text
  -> new(@kind)
    @binders = []
    @tactics = nil
    @eqns = []
    @ctors = []
    @params = []

# ---------------------------------------------------------------------------
# Expression parser over a token array.

+ EParser
  ro :pos
  -> new(@toks, start = 0)
    @pos = start

  -> peek
    if @pos < @toks.size
      @toks[@pos]
    else
      nil

  -> peek_at(k)
    if @pos + k < @toks.size
      @toks[@pos + k]
    else
      nil

  -> at_end?
    @pos >= @toks.size

  -> next_tok
    t = peek
    @pos += 1
    t

  -> is?(text)
    t = peek
    t != nil && (t.kind == :sym || t.kind == :kw) && t.text == text

  -> accept(text)
    if is?(text)
      @pos += 1
      return true
    false

  -> expect(text)
    if !accept(text)
      t = peek
      got = "end of line"
      if t != nil
        got = "'" + t.text + "' (line " + t.line.to_s + ")"
      raise "parse error: expected '" + text + "' but found " + got
    true

  -> error(msg)
    t = peek
    where = " at end of line"
    if t != nil
      where = " at '" + t.text + "' (line " + t.line.to_s + ", col " + t.col.to_s + ")"
    raise "parse error: " + msg + where

  # Binder types in commands may be propositions (hypotheses) or types.
  -> parse_expr_or_type
    save = @pos
    ok = false
    e = nil
    begin
      e = parse_expr
      t = peek
      # a binder type must end at the closing bracket; `ℕ × ℕ` parses as a
      # partial expression, so fall back to the type grammar
      ok = t == nil || (t.kind == :sym && (t.text == ")" || t.text == "}" || t.text == ":=" || t.text == ","))
    rescue err
      ok = false
    if ok
      return ast(:either, "", [e])
    @pos = save
    parse_type

  # ---- types ----------------------------------------------------------------

  -> parse_type
    t = parse_type_prod
    if accept("→")
      r = parse_type
      return ast(:tarrow, "→", [t, r])
    t

  -> parse_type_prod
    t = parse_type_app
    if accept("×")
      r = parse_type_prod
      return ast(:tprod, "×", [t, r])
    t

  -> parse_type_app
    h = parse_type_atom
    args = []
    while type_atom_start?
      args.push(parse_type_atom)
    if args.size == 0
      return h
    n = ast(:tapp, h.s, args)
    n

  -> type_atom_start?
    t = peek
    if t == nil
      return false
    if t.kind == :id
      return true
    t.kind == :sym && t.text == "("

  -> parse_type_atom
    t = peek
    if t == nil
      error("expected a type")
    if accept("(")
      ty = parse_type
      expect(")")
      return ty
    if t.kind == :id
      next_tok
      return ast(:tid, t.text, [])
    error("expected a type")

  # ---- expressions -------------------------------------------------------------

  -> parse_expr
    parse_iff

  -> parse_iff
    l = parse_imp
    while accept("↔")
      r = parse_imp
      l = ast(:binop, "↔", [l, r])
    l

  -> parse_imp
    l = parse_or
    if accept("→")
      r = parse_imp
      return ast(:binop, "→", [l, r])
    l

  -> parse_or
    l = parse_and
    if accept("∨")
      r = parse_or
      return ast(:binop, "∨", [l, r])
    l

  -> parse_and
    l = parse_not
    if accept("∧")
      r = parse_and
      return ast(:binop, "∧", [l, r])
    l

  -> parse_not
    if accept("¬")
      return ast(:unop, "¬", [parse_not])
    parse_rel

  -> rel_op?
    t = peek
    t != nil && t.kind == :sym && ["=", "≠", "<", ">", "≤", "≥", "∈", "∉", "⊆", "∣"].include?(t.text)

  -> parse_rel
    l = parse_cons
    if rel_op?
      op = next_tok.text
      r = parse_cons
      res = ast(:binop, op, [l, r])
      # chains a < b < c  ==> a < b ∧ b < c
      while rel_op?
        op2 = next_tok.text
        r2 = parse_cons
        res = ast(:binop, "∧", [res, ast(:binop, op2, [r, r2])])
        r = r2
      return res
    l

  -> parse_cons
    l = parse_add
    if accept("::")
      r = parse_cons
      return ast(:binop, "::", [l, r])
    if accept("++")
      r = parse_cons
      return ast(:binop, "++", [l, r])
    l

  -> parse_add
    l = parse_mul
    while is?("+") || is?("-") || is?("∪")
      op = next_tok.text
      r = parse_mul
      l = ast(:binop, op, [l, r])
    l

  -> parse_mul
    l = parse_unary
    while is?("*") || is?("/") || is?("%") || is?("∘") || is?("∩")
      op = next_tok.text
      r = parse_unary
      l = ast(:binop, op, [l, r])
    l

  -> parse_unary
    if accept("-")
      return ast(:unop, "neg", [parse_unary])
    if accept("√")
      return ast(:app, "", [ast(:id, "sqrt", []), parse_unary])
    parse_pow

  -> parse_pow
    b = parse_app
    if accept("^")
      e = parse_unary
      return ast(:binop, "^", [b, e])
    if accept("⁻¹")
      return ast(:unop, "inv", [b])
    b

  -> atom_start?
    t = peek
    if t == nil
      return false
    if t.kind == :id || t.kind == :num || t.kind == :dec || t.kind == :str
      return true
    if t.kind == :sym
      return ["(", "\[", "⟨", "{", "_", "|"].include?(t.text) && !(t.text == "|" && @in_abs)
    false

  -> parse_app
    if is?("∑") || is?("∏")
      return parse_bigop(next_tok.text)
    if is?("∀") || is?("∃") || (peek != nil && peek.kind == :kw && (peek.text == "fun" || peek.text == "if" || peek.text == "let"))
      return parse_binder_expr
    f = parse_postfix(parse_atom)
    while atom_start?
      x = parse_postfix(parse_atom)
      f = ast(:app, "", [f, x])
    # trailing binder expression as last argument: f fun x => ...
    if is?("∀") || is?("∃") || (peek != nil && peek.kind == :kw && peek.text == "fun")
      x = parse_binder_expr
      f = ast(:app, "", [f, x])
    f

  -> parse_binder_expr
    if accept("∀")
      return parse_quant("∀")
    if accept("∃")
      q = "∃"
      if accept("!")
        q = "∃!"
      return parse_quant(q)
    t = next_tok
    if t.text == "fun"
      bs = parse_binders_until("=>")
      expect("=>")
      body = parse_expr
      n = ast(:lam, "", [body])
      n.binders = bs
      return n
    if t.text == "if"
      c = parse_expr
      expect("then")
      a = parse_expr
      expect("else")
      b = parse_expr
      return ast(:ite, "", [c, a, b])
    if t.text == "let"
      nm = next_tok.text
      ty = nil
      if accept(":")
        ty = parse_type
      expect(":=")
      v = parse_expr
      if !accept(";")
        expect("in")
      body = parse_expr
      n = ast(:let, nm, [v, body])
      n.ty = ty
      return n
    error("unexpected keyword")

  # ∀ x y : τ, P   ∀ (x : τ) (y : σ), P   ∀ x ∈ S, P   ∀ i < n, P
  -> parse_quant(q)
    bs = []
    if is?("(")
      while accept("(")
        names = []
        while peek != nil && peek.kind == :id
          names.push(next_tok.text)
        expect(":")
        ty = parse_type
        expect(")")
        names.each -> (nm)
          bs.push(Binder.new(nm, ty, nil, nil))
    else
      names = []
      while peek != nil && (peek.kind == :id || (peek.kind == :sym && peek.text == "_"))
        names.push(next_tok.text)
      ty = nil
      rel = nil
      bound = nil
      if accept(":")
        ty = parse_type
      elsif is?("∈") || is?("<") || is?("≤") || is?(">") || is?("≥") || is?("∉") || is?("⊆")
        rel = next_tok.text
        bound = parse_cons
      names.each -> (nm)
        bs.push(Binder.new(nm, ty, rel, bound))
    expect(",")
    body = parse_expr
    n = ast(:quant, q, [body])
    n.binders = bs
    n

  -> parse_binders_until(stop)
    bs = []
    while !is?(stop)
      if accept("(")
        names = []
        while peek != nil && peek.kind == :id
          names.push(next_tok.text)
        ty = nil
        if accept(":")
          ty = parse_type
        expect(")")
        names.each -> (nm)
          bs.push(Binder.new(nm, ty, nil, nil))
      elsif peek != nil && (peek.kind == :id || peek.text == "_")
        bs.push(Binder.new(next_tok.text, nil, nil, nil))
      else
        error("expected a binder")
    bs

  -> parse_atom
    t = next_tok
    if t == nil
      error("unexpected end of expression")
    if t.kind == :id
      a = ast(:id, t.text, [])
      a.line = t.line
      return a
    if t.kind == :num
      return ast(:num, t.text, [])
    if t.kind == :dec
      return ast(:dec, t.text, [])
    if t.kind == :str
      return ast(:str, t.text, [])
    if t.text == "_"
      return ast(:hole, "_", [])
    if t.kind == :kw && t.text == "by"
      # tactic block inside a term: collect tokens up to the enclosing bracket
      start = @pos
      depth = 0
      while @pos < @toks.size && !(depth == 0 && (@toks[@pos].text == ")" || @toks[@pos].text == "\]" || @toks[@pos].text == "⟩" || @toks[@pos].text == ","))
        tx = @toks[@pos].text
        if tx == "(" || tx == "\[" || tx == "⟨" || tx == "{"
          depth += 1
        if tx == ")" || tx == "\]" || tx == "⟩" || tx == "}"
          depth -= 1
        @pos += 1
      n = ast(:by, "", [])
      n.binders = arr_sub(@toks, start, @pos - start)
      return n
    if t.text == "("
      if accept(")")
        return ast(:id, "unit_val", [])
      e = parse_expr
      if accept(":")
        ty = parse_type
        expect(")")
        n = ast(:ascribe, "", [e])
        n.ty = ty
        return n
      if is?(",")
        items = [e]
        while accept(",")
          items.push(parse_expr)
        expect(")")
        return ast(:tuple, "", items)
      expect(")")
      return e
    if t.text == "\["
      items = []
      if !accept("\]")
        items.push(parse_expr)
        if accept("..")
          hi = parse_expr
          expect("\]")
          return ast(:range, "", [items[0], hi])
        while accept(",")
          items.push(parse_expr)
        expect("\]")
      return ast(:list, "", items)
    if t.text == "⟨"
      items = []
      if !accept("⟩")
        items.push(parse_expr)
        while accept(",")
          items.push(parse_expr)
        expect("⟩")
      return ast(:anon, "", items)
    if t.text == "{"
      if peek != nil && peek.kind == :id && peek_at(1) != nil && (peek_at(1).text == "|" || peek_at(1).text == ":")
        nm = next_tok.text
        ty = nil
        if accept(":")
          ty = parse_type
        expect("|")
        body = parse_expr
        expect("}")
        n = ast(:setof, nm, [body])
        n.ty = ty
        return n
      items = []
      if !accept("}")
        items.push(parse_expr)
        while accept(",")
          items.push(parse_expr)
        expect("}")
      return ast(:setlit, "", items)
    if t.text == "|"
      old = @in_abs
      @in_abs = true
      e = parse_expr
      @in_abs = old
      expect("|")
      return ast(:app, "", [ast(:id, "abs", []), e])
    @pos -= 1
    error("unexpected token")

# ---------------------------------------------------------------------------
# Commands

-> parse_expr_toks(toks)
  p = EParser.new(toks, 0)
  e = p.parse_expr
  if !p.at_end?
    p.error("trailing tokens")
  e

-> parse_type_toks(toks)
  p = EParser.new(toks, 0)
  e = p.parse_type
  if !p.at_end?
    p.error("trailing tokens in type")
  e

# Splits tokens on top-level occurrences of a symbol.
-> split_top(toks, sym)
  out = []
  cur = []
  depth = 0
  toks.each -> (t)
    if t.kind == :sym && (t.text == "(" || t.text == "\[" || t.text == "{" || t.text == "⟨")
      depth += 1
    if t.kind == :sym && (t.text == ")" || t.text == "\]" || t.text == "}" || t.text == "⟩")
      depth -= 1
    if depth == 0 && (t.kind == :sym || t.kind == :kw) && t.text == sym
      out.push(cur)
      cur = []
    else
      cur.push(t)
  out.push(cur)
  out

-> find_top(toks, sym, start)
  depth = 0
  i = start
  while i < toks.size
    t = toks[i]
    if t.kind == :sym && (t.text == "(" || t.text == "\[" || t.text == "{" || t.text == "⟨")
      depth += 1
    if t.kind == :sym && (t.text == ")" || t.text == "\]" || t.text == "}" || t.text == "⟩")
      depth -= 1
    if depth == 0 && (t.kind == :sym || t.kind == :kw) && t.text == sym
      return i
    i += 1
  -1

# Groups logical lines into a tree by indentation: returns array of TacNode.
-> build_blocks(lines, from, to, base_indent)
  out = []
  i = from
  while i < to
    ln = lines[i]
    j = i + 1
    while j < to && lines[j].indent > ln.indent
      j += 1
    out.push(TacNode.new(ln.toks, build_blocks(lines, i + 1, j, ln.indent), ln.line))
    i = j
  out

# Parses (x y : τ) {z : σ} binder groups starting at p.pos; stops at other tokens.
-> parse_cmd_binders(p)
  bs = []
  while p.is?("(") || p.is?("{")
    close = ")"
    if p.is?("{")
      close = "}"
    p.next_tok
    names = []
    while p.peek != nil && p.peek.kind == :id
      names.push(p.next_tok.text)
    p.expect(":")
    ty = p.parse_expr_or_type
    p.expect(close)
    names.each -> (nm)
      bs.push(Binder.new(nm, ty, nil, nil))
  bs

-> parse_program(src)
  lines = lex_source(src)
  cmds = []
  i = 0
  while i < lines.size
    ln = lines[i]
    j = i + 1
    while j < lines.size && lines[j].indent > ln.indent
      j += 1
    begin
      cmds.push(parse_command(ln, build_blocks(lines, i + 1, j, ln.indent), lines, i + 1, j))
    rescue err
      # a parse error fails this command only; the rest of the file still runs
      bad = Cmd.new(:parse_error)
      bad.line = ln.line
      bad.name = ""
      bad.text = err.to_s
      cmds.push(bad)
    i = j
  cmds

-> parse_command(ln, block, lines, from, to)
  toks = ln.toks
  toks.each -> (t)
    if t.kind == :lexerr
      raise t.text
  head = toks[0]
  c = nil
  if head.kind == :sym && head.text == "@"
    j = 0
    while j < toks.size && toks[j].text != "\]"
      j += 1
    attr = toks[2].text
    inner = parse_command(LLine.new(ln.indent, arr_sub(toks, j + 1, toks.size - j - 1), ln.line), block, lines, from, to)
    inner.text = attr
    return inner
  # Tungsten-style shorthands:  + name : stmt  (theorem)   -> name ... (def)
  if head.kind == :sym && (head.text == "+" || head.text == "→")
    kw = "theorem"
    if head.text == "→"
      kw = "def"
    t2 = [Tok.new(:kw, kw, head.line, head.col)] + arr_sub(toks, 1, toks.size - 1)
    return parse_command(LLine.new(ln.indent, t2, ln.line), block, lines, from, to)
  if head.kind == :kw && head.text == "import"
    c = Cmd.new(:import)
    c.name = toks[1].text
  elsif head.kind == :kw && (head.text == "theorem" || head.text == "lemma" || head.text == "example" || head.text == "axiom")
    c = parse_theorem_cmd(toks, block)
  elsif head.kind == :kw && head.text == "def"
    c = parse_def_cmd(toks, block)
  elsif head.kind == :kw && head.text == "opaque"
    c = Cmd.new(:opaque)
    c.name = toks[1].text
    c.ty = parse_type_toks(arr_sub(toks, 3, toks.size - 3))
  elsif head.kind == :kw && head.text == "inductive"
    c = parse_inductive_cmd(toks, block)
  elsif head.kind == :kw && head.text == "structure"
    c = parse_structure_cmd(toks, block)
  elsif head.kind == :sym && head.text == "#"
    c = Cmd.new(:hash)
    c.name = toks[1].text
    c.body = arr_sub(toks, 2, toks.size - 2)
  else
    raise "line " + ln.line.to_s + ": unknown command '" + head.text + "'"
  c.line = ln.line
  c

-> parse_theorem_cmd(toks, block)
  kind = toks[0].text
  c = Cmd.new(:theorem)
  if kind == "axiom"
    c.kind = :axiom
  i = 1
  if kind != "example"
    c.name = toks[1].text
    i = 2
  else
    c.name = "_example"
  p = EParser.new(toks, i)
  c.binders = parse_cmd_binders(p)
  p.expect(":")
  rest = arr_sub(toks, p.pos, toks.size - p.pos)
  k = find_top(rest, ":=", 0)
  if k < 0
    c.ty = parse_expr_toks(rest)
    c.tactics = block
  else
    c.ty = parse_expr_toks(arr_sub(rest, 0, k))
    after = arr_sub(rest, k + 1, rest.size - k - 1)
    if after.size > 0 && after[0].kind == :kw && after[0].text == "by"
      inline = arr_sub(after, 1, after.size - 1)
      tacs = []
      if inline.size > 0
        split_top(inline, ";").each -> (part)
          if part.size > 0
            tacs.push(TacNode.new(part, [], toks[0].line))
      block.each -> (b)
        tacs.push(b)
      c.tactics = tacs
    else
      c.body = parse_expr_toks(after)
  c

-> parse_def_cmd(toks, block)
  c = Cmd.new(:def)
  c.name = toks[1].text
  p = EParser.new(toks, 2)
  c.binders = parse_cmd_binders(p)
  if p.accept(":")
    k = find_top(toks, ":=", p.pos)
    if k < 0
      c.ty = parse_type_toks(arr_sub(toks, p.pos, toks.size - p.pos))
      p = EParser.new(toks, toks.size)
    else
      c.ty = parse_type_toks(arr_sub(toks, p.pos, k - p.pos))
      p = EParser.new(toks, k)
  if p.accept(":=")
    # the body may continue on more-indented lines below the definition
    btoks = arr_sub(toks, p.pos, toks.size - p.pos)
    flatten_block(block, btoks)
    c.body = parse_expr_toks(btoks)
  else
    # pattern equations:  | pats => rhs
    block.each -> (b)
      bt = b.toks
      if bt[0].text != "|"
        raise "line " + b.line.to_s + ": expected '| pattern => value'"
      k = find_top(bt, "=>", 1)
      lhs = split_top(arr_sub(bt, 1, k - 1), ",")
      pats = []
      lhs.each -> (pt)
        pats.push(parse_expr_toks(pt))
      rhs = parse_expr_toks(arr_sub(bt, k + 1, bt.size - k - 1))
      c.eqns.push([pats, rhs])
  c

# inductive name (α β) | c1 (x : τ) ... | c2 ...
-> parse_inductive_cmd(toks, block)
  c = Cmd.new(:inductive)
  c.name = toks[1].text
  i = 2
  while i < toks.size && toks[i].text != "|" && toks[i].text != "where"
    if toks[i].kind == :id
      c.params.push(toks[i].text)
    i += 1
  alts = []
  if i < toks.size
    split_top(arr_sub(toks, i, toks.size - i), "|").each -> (part)
      if part.size > 0 && !(part.size == 1 && part[0].text == "where")
        alts.push(part)
  block.each -> (b)
    split_top(b.toks, "|").each -> (part)
      if part.size > 0
        alts.push(part)
  alts.each -> (part)
    nm = part[0].text
    p = EParser.new(part, 1)
    args = []
    while !p.at_end?
      if p.accept("(")
        names = []
        while p.peek != nil && p.peek.kind == :id
          names.push(p.next_tok.text)
        p.expect(":")
        ty = p.parse_type
        p.expect(")")
        names.each -> (an)
          args.push([an, ty])
      else
        ty = p.parse_type_atom
        args.push(["_", ty])
    c.ctors.push([nm, args])
  c

# structure name (α) := (f : τ) (g : σ)   -- one constructor `mk`
-> parse_structure_cmd(toks, block)
  c = Cmd.new(:structure)
  c.name = toks[1].text
  i = 2
  while i < toks.size && toks[i].text != ":="
    if toks[i].kind == :id
      c.params.push(toks[i].text)
    i += 1
  p = EParser.new(toks, i + 1)
  fields = []
  while !p.at_end?
    p.expect("(")
    names = []
    while p.peek != nil && p.peek.kind == :id
      names.push(p.next_tok.text)
    p.expect(":")
    ty = p.parse_type
    p.expect(")")
    names.each -> (fname)
      fields.push([fname, ty])
  c.ctors = [[c.name + ".mk", fields]]
  c

+ EParser
  # a.1  a.2  (h x).mp  — projections after an atom
  -> parse_postfix(a)
    while is?(".") && peek_at(1) != nil && (peek_at(1).kind == :num || peek_at(1).kind == :id)
      next_tok
      f = next_tok.text
      a = ast(:proj, f, [a])
    a

+ EParser
  # ∑ i < n, body   ∑ x ∈ l, body   (and ∏) — sum_below n (fun i => body) / sum_list l (fun x => body)
  -> parse_bigop(op)
    name = next_tok.text
    kind = "sum"
    if op == "∏"
      kind = "prod"
    if accept("<")
      bound = parse_cons
      expect(",")
      body = parse_add
      lam = ast(:lam, "", [body])
      lam.binders = [Binder.new(name, nil, nil, nil)]
      return ast(:app, "", [ast(:app, "", [ast(:id, kind + "_below", []), bound]), lam])
    expect("∈")
    l = parse_cons
    expect(",")
    body = parse_add
    lam = ast(:lam, "", [body])
    lam.binders = [Binder.new(name, nil, nil, nil)]
    ast(:app, "", [ast(:app, "", [ast(:id, kind + "_list", []), l]), lam])

-> flatten_block(nodes, out)
  nodes.each -> (n)
    n.toks.each -> (t)
      out.push(t)
    flatten_block(n.block, out)
  out
