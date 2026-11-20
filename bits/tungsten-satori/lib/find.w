# Keep parameter renamings one-to-one in both the conclusion and its guards.
-> find_bind?(params, name, replacement)
  if params[name] != nil
    return params[name] == replacement
  if params.values.include?(replacement)
    return false
  params[name] = replacement
  true

# Abstract an expression at a declaration parameter applied to distinct local
# binders, such as F i j. Replay the same expression at every later occurrence
# with the corresponding arguments, including under a different binder order.
-> find_function_match(decl, query, params, left, right)
  sp = decl.spine
  if sp[0].kind != :id || !params.has_key?(sp[0].s) || left.include?(sp[0].s)
    return nil
  formals = []
  visible = right.map -> (name) "#unavailable"
  sp[1].each -> (arg)
    if arg.kind != :id
      return nil
    i = left.size - 1
    while i >= 0 && left[i] != arg.s
      i -= 1
    if i < 0 || formals.include?(right[i])
      return nil
    formals.push(right[i])
    visible[i] = right[i]
  name = sp[0].s
  known = params[name]
  if known != nil
    if known.is_a?(Array)
      return known[1].size == formals.size && find_expr_matches?(query, query, {}, right, visible) && find_expr_matches?(known[0], query, {}, known[1], formals)
    return nil
  # Keep a bare function name available for any explicit type filter.
  actual = query.spine
  if actual[0].kind == :id && actual[1].size == formals.size
    plain = true
    i = 0
    while i < formals.size
      if actual[1][i].kind != :id || actual[1][i].s != formals[i]
        plain = false
      i += 1
    if plain
      return nil
  if !find_expr_matches?(query, query, {}, right, visible)
    return false
  params["#general"] = true
  params[name] = [query, formals]
  true

# Match the written conclusion of a library declaration without importing it.
# A parameter may be renamed. A local binder must refer to the same binder
# in both expressions, even when the names are shadowed or the sums transpose.
-> find_expr_matches?(decl, query, params, left = [], right = [])
  if query == nil || decl == nil
    return query == decl
  if query.kind == :hole || (query.kind == :id && query.s == "_")
    return true
  if decl.kind == :id && params.has_key?(decl.s) && !left.include?(decl.s) && (query.kind == :num || query.kind == :dec)
    key = "#" + query.kind.to_s + query.s
    if params[decl.s] == nil
      params["#general"] = true
      params[decl.s] = key
    return params[decl.s] == key
  if decl.kind == :app && !left.empty?() && !params.empty?()
    matched = find_function_match(decl, query, params, left, right)
    if matched != nil
      return matched
  if query.kind != decl.kind || query.kids.size != decl.kids.size || query.binders.size != decl.binders.size
    return false
  if decl.kind == :id
    i = left.size - 1
    while i >= 0
      if left[i] == decl.s || right[i] == query.s
        return left[i] == decl.s && right[i] == query.s
      i -= 1
    if params.has_key?(decl.s)
      return find_bind?(params, decl.s, query.s)
  if decl.kind == :by
    return false
  if decl.kind != :setof && decl.kind != :let && decl.s != query.s
    return false
  if query.ty != nil && !find_expr_matches?(decl.ty, query.ty, params, left, right)
    return false
  i = 0
  while i < decl.binders.size
    a = decl.binders[i]
    b = query.binders[i]
    if a.rel != b.rel || !find_expr_matches?(a.bound, b.bound, params, left, right)
      return false
    if b.ty != nil && !find_expr_matches?(a.ty, b.ty, params, left, right)
      return false
    left = left + [a.name]
    right = right + [b.name]
    i += 1
  i = 0
  while i < decl.kids.size
    if decl.kind == :setof || (decl.kind == :let && i == 1)
      left = left + [decl.s]
      right = right + [query.s]
    if !find_expr_matches?(decl.kids[i], query.kids[i], params, left, right)
      return false
    i += 1
  true

# Command parameters and explicit quantifiers use different type ASTs.
# Put their annotations in the same surface grammar for structural matching.
-> find_annotation(t)
  if t == nil
    return nil
  case t.kind
  when :either
    return t.kids[0]
  when :tid
    return ast(:id, t.s, [])
  when :tapp
    head = ast(:id, t.s, [])
    t.kids.each -> (arg) head = ast(:app, "", [head, find_annotation(arg)])
    return head
  when :tarrow, :tprod
    return ast(:binop, t.s, [find_annotation(t.kids[0]), find_annotation(t.kids[1])])
  t

# A search header may specify any subset of the declaration's binders.
# Match the conclusion first: it normally determines all term parameters.
# A supplied hypothesis can then distinguish rules with the same result.
-> find_binders_match?(decl, wanted, params, i = 0)
  if i == wanted.size
    return true
  b = wanted[i]
  if wanted.size > decl.size
    return false
  decl.each -> (a)
    trial = params.dup
    if !find_bind?(trial, a.name, b.name)
      next
    if find_expr_matches?(find_annotation(a.ty), find_annotation(b.ty), trial) && find_binders_match?(decl, wanted, trial, i + 1)
      return true
  false

# Also expose binders and conditions written after the colon. Always try the
# full result first, so an explicitly quantified or conditional query works.
-> find_declaration_rank(decl, query, wanted)
  term = decl.ty
  binders = decl.binders.dup
  loop
    if term.kind == query.kind || query.kind == :hole || (query.kind == :id && query.s == "_")
      params = {}
      binders.each -> (b) params[b.name] = nil
      if find_expr_matches?(term, query, params) && find_binders_match?(binders, wanted, params)
        return params.has_key?("#general") ? 1 : 0
    if term.kind == :quant && term.s == "∀"
      term.binders.each -> (b)
        # A shadowed outer name cannot become a free parameter at this point.
        if binders.any?(-> (old) old.name == b.name)
          return nil
        binders.push(b)
        if b.rel != nil
          guard = ast(:binop, b.rel, [ast(:id, b.name, []), b.bound])
          binders.push(Binder.new("#" + binders.size.to_s, guard, nil, nil))
      term = term.kids[0]
    elsif term.kind == :binop && term.s == "→"
      binders.push(Binder.new("#" + binders.size.to_s, term.kids[0], nil, nil))
      term = term.kids[1]
    else
      return nil

# Use the original header, including every hypothesis. Token columns count
# Unicode characters, whereas Tungsten string slices take byte offsets.
-> find_signature(lines, first, last, proof)
  parts = []
  i = first.line
  while i <= last.line
    s = lines[i - 1]
    if proof != nil && i == proof.line
      col = 0
      off = 0
      while col < proof.col && off < s.size
        off += utf8_len(s.byte_at(off))
        col += 1
      s = s.slice(0, off)
    parts.push(s.strip)
    i += 1
  parts.join(" ")

-> find_module_statements(path, query, binders, results, mod, limit)
  src = File.read(path)
  lines = nil
  count = 0
  lex_source(src).each -> (ln)
    if ln.indent != 0
      next
    ts = ln.toks
    start = 0
    while start < ts.size && ts[start].text == "@"
      while start < ts.size && ts[start].text != "\]"
        start += 1
      start += 1
    if start >= ts.size || !["+", "theorem", "lemma", "axiom"].include?(ts[start].text)
      next
    # Parse only the declaration. Proof bodies do not participate in lookup.
    end_at = find_top(ts, ":=", start)
    proof = nil
    if end_at >= 0
      proof = ts[end_at]
      ts = arr_sub(ts, 0, end_at)
    header = LLine.new(0, ts, ln.line)
    begin
      decl = parse_command(header, [], [], 0, 0)
    rescue err
      raise path + ":" + ln.line.to_s + ": " + err.to_s
    rank = find_declaration_rank(decl, query, binders)
    if rank != nil
      count += 1
      if limit == nil || results[rank].size < limit
        if lines == nil
          lines = src.split("\n")
        results[rank].push("import " + mod + "  ·  " + find_signature(lines, ts[0], ts.last, proof))
  count

-> satori_find(root, args)
  all = args.size == 3 && args[1] == "--all"
  if args.size != 2 && !all
    << "usage: satori find \[--all\] 'CONCLUSION'"
    return 1
  begin
    src = args.last
    toks = []
    lex_source(src).each -> (ln)
      ln.toks.each -> (token) toks.push(token)
    binders = []
    if toks.size > 0 && (toks[0].text == "(" || toks[0].text == "{") && find_top(toks, ":", 0) >= 0
      parser = EParser.new(toks)
      binders = parse_cmd_binders(parser)
      parser.expect(":")
      toks = arr_sub(toks, parser.pos, toks.size - parser.pos)
    query = parse_expr_toks(toks)
    dir = root + "/bits/tungsten-satori/prelude/"
    if !File.exist?(dir + "prelude.sat")
      raise "cannot find Satori prelude at " + dir
    count = 0
    results = [[], []]
    limit = all ? nil : 12
    paths = []
    collect = -> (path)
      if path.ends_with?(".sat")
        paths.push(path)
    File.walk(dir, collect)
    paths.sort.each -> (path)
      mod = path.slice(dir.size, path.size - dir.size - 4).gsub("/", ".")
      count += find_module_statements(path, query, binders, results, mod, limit)
    shown = results[0] + results[1]
    if limit != nil && shown.size > limit
      shown = arr_sub(shown, 0, limit)
    shown.each -> (line) << line
    if count > shown.size
      << (count - shown.size).to_s + " more matches (use --all)"
    if count == 0
      << "no matching library declaration"
    0
  rescue err
    << "find: " + err.to_s
    1
