use ./lexer

# Ruby parser for Spinel's line-oriented AST contract.
#
# Output format:
#   ROOT <id>
#   N <id> <NodeType>
#   S/I/F/R/A <id> <field> <value>

-> ruby_token(type, value, line)
  [type, value, line]

-> ruby_packed_type(tok)
  (tok >> 40) & 0x3F

-> ruby_packed_offset(tok)
  (tok >> 4) & 0xFFFFFF

-> ruby_packed_length(tok)
  (tok >> 28) & 0xFFF

-> ruby_slice_chars(chars, off, len)
  out = StringBuffer(len)
  i = 0
  while i < len && off + i < chars.size()
    out << chars[off + i]
    i += 1
  out.to_s()

-> ruby_keyword_type(s)
  case s
  when "class"
    :class
  when "module"
    :module
  when "def"
    :def
  when "end"
    :end
  when "if"
    :if
  when "elsif"
    :elsif
  when "else"
    :else
  when "case"
    :case
  when "when"
    :when
  when "then"
    :then
  when "unless"
    :unless
  when "while"
    :while
  when "until"
    :until
  when "for"
    :for
  when "in"
    :in
  when "begin"
    :begin
  when "rescue"
    :rescue
  when "ensure"
    :ensure
  when "retry"
    :retry
  when "do"
    :do
  when "return"
    :return
  when "next"
    :next
  when "break"
    :break
  when "yield"
    :yield
  when "super"
    :super
  when "nil"
    :nil
  when "true"
    :true
  when "false"
    :false
  when "self"
    :self
  when "and"
    :and
  when "or"
    :or
  else
    nil

-> ruby_is_operator_label?(raw)
  raw in ("==" "!=" "<=" ">=" "&&" "||" "<<" ">>" "**" "+=" "-=" "*=" "/=" "%=" "=>" "=~" ".." "..." "===" "<=>" ":" "+" "-" "*" "/" "%" "<" ">" "&" "|" "^" "?" "!")

-> ruby_operator_token(raw, line)
  case raw
  when "::"
    ruby_token(:colon2, raw, line)
  when "&."
    ruby_token(:safe_dot, raw, line)
  when "("
    ruby_token(:lparen, raw, line)
  when ")"
    ruby_token(:rparen, raw, line)
  when "\["
    ruby_token(:lbrack, raw, line)
  when "\]"
    ruby_token(:rbrack, raw, line)
  when "{"
    ruby_token(:lbrace, raw, line)
  when "}"
    ruby_token(:rbrace, raw, line)
  when ","
    ruby_token(:comma, raw, line)
  when "."
    ruby_token(:dot, raw, line)
  when "="
    ruby_token(:eq, raw, line)
  when ";"
    ruby_token(:nl, "\n", line)
  when "|"
    ruby_token(:pipe, raw, line)
  else
    ruby_token(:op, raw, line)

-> ruby_delimiter_token_type(ch)
  case ch
  when "("
    :lparen
  when ")"
    :rparen
  when "\["
    :lbrack
  when "\]"
    :rbrack
  when "{"
    :lbrace
  when "}"
    :rbrace
  when ","
    :comma
  when "."
    :dot
  when ";"
    :nl
  else
    nil

-> ruby_split_delimiter_run?(raw)
  if raw.size() <= 1 || raw == ".." || raw == "..."
    return false
  has_bracket = false
  i = 0
  while i < raw.size()
    ch = raw[i]
    if ruby_delimiter_token_type(ch) == nil
      return false
    if ch in ("(" ")" "\[" "\]" "{" "}" ";")
      has_bracket = true
    i += 1
  has_bracket

-> ruby_push_operator_token(tokens, raw, line)
  if ruby_split_delimiter_run?(raw)
    i = 0
    while i < raw.size()
      ch = raw[i]
      tokens.push(ruby_token(ruby_delimiter_token_type(ch), ch, line))
      i += 1
    return nil

  case raw
  when "\[]"
    tokens.push(ruby_token(:lbrack, "\[", line))
    tokens.push(ruby_token(:rbrack, "\]", line))
  when "\[\["
    tokens.push(ruby_token(:lbrack, "\[", line))
    tokens.push(ruby_token(:lbrack, "\[", line))
  when "\]\]"
    tokens.push(ruby_token(:rbrack, "\]", line))
    tokens.push(ruby_token(:rbrack, "\]", line))
  when "(-"
    tokens.push(ruby_token(:lparen, "(", line))
    tokens.push(ruby_token(:op, "-", line))
  when "(*"
    tokens.push(ruby_token(:lparen, "(", line))
    tokens.push(ruby_token(:op, "*", line))
  when "<("
    tokens.push(ruby_token(:op, "<", line))
    tokens.push(ruby_token(:lparen, "(", line))
  when ">("
    tokens.push(ruby_token(:op, ">", line))
    tokens.push(ruby_token(:lparen, "(", line))
  when ")/"
    tokens.push(ruby_token(:rparen, ")", line))
    tokens.push(ruby_token(:op, "/", line))
  when "\[-"
    tokens.push(ruby_token(:lbrack, "\[", line))
    tokens.push(ruby_token(:op, "-", line))
  when "(:"
    tokens.push(ruby_token(:lparen, "(", line))
    tokens.push(ruby_token(:op, ":", line))
  when "\[:"
    tokens.push(ruby_token(:lbrack, "\[", line))
    tokens.push(ruby_token(:op, ":", line))
  when "<=>("
    tokens.push(ruby_token(:op, "<=>", line))
    tokens.push(ruby_token(:lparen, "(", line))
  when "==("
    tokens.push(ruby_token(:op, "==", line))
    tokens.push(ruby_token(:lparen, "(", line))
  when "\]."
    tokens.push(ruby_token(:rbrack, "\]", line))
    tokens.push(ruby_token(:dot, ".", line))
  when "\])"
    tokens.push(ruby_token(:rbrack, "\]", line))
    tokens.push(ruby_token(:rparen, ")", line))
  when ":,"
    tokens.push(ruby_token(:op, ":", line))
    tokens.push(ruby_token(:comma, ",", line))
  when ":)"
    tokens.push(ruby_token(:op, ":", line))
    tokens.push(ruby_token(:rparen, ")", line))
  when "))"
    tokens.push(ruby_token(:rparen, ")", line))
    tokens.push(ruby_token(:rparen, ")", line))
  when "{}"
    tokens.push(ruby_token(:lbrace, "{", line))
    tokens.push(ruby_token(:rbrace, "}", line))
  else
    tokens.push(ruby_operator_token(raw, line))

-> ruby_unquote(raw)
  if raw.size() < 2
    return raw
  out = StringBuffer(raw.size())
  i = 1
  last = raw.size() - 1
  while i < last
    ch = raw[i]
    if ch == "\\" && i + 1 < last
      i += 1
      esc = raw[i]
      if esc == "n"
        out << "\n"
      elsif esc == "t"
        out << "\t"
      elsif esc == "r"
        out << "\r"
      else
        out << esc
    else
      out << ch
    i += 1
  out.to_s()

-> ruby_identifier_token(raw, line)
  kw = ruby_keyword_type(raw)
  if kw != nil
    return ruby_token(kw, raw, line)
  first = raw[0]
  if first >= "A" && first <= "Z"
    ruby_token(:const, raw, line)
  else
    ruby_token(:id, raw, line)

-> ruby_regex_start_context?(tokens)
  i = tokens.size() - 1
  while i >= 0
    t = tokens[i]
    if t[0] != :nl
      tt = t[0]
      return tt in (:op :eq :lparen :comma :lbrack :if :unless :when :in :return)
    i -= 1
  true

-> ruby_materialize_tokens(source)
  chars = source.chars()
  line_at = []
  line = 1
  ci = 0
  while ci < chars.size()
    line_at.push(line)
    if chars[ci] == "\n"
      line += 1
    ci += 1
  line_at.push(line)

  lc = source.lchs("ruby")
  packed = i64[lc.size() + 16]
  count = ruby_tokenize_fast64(lc, lc.size(), packed)
  tokens = []

  i = 0
  while i < count
    tok = packed[i]
    type_id = ruby_packed_type(tok)
    off = ruby_packed_offset(tok)
    len = ruby_packed_length(tok)
    raw = ruby_slice_chars(chars, off, len)
    tline = line_at[off]

    case type_id
    when 1
      tokens.push(ruby_identifier_token(raw, tline))
    when 2
      tokens.push(ruby_token(:const, raw, tline))
    when 3
      tokens.push(ruby_token(:int, raw, tline))
    when 4
      tokens.push(ruby_token(:float, raw, tline))
    when 5
      if raw.size() > 0 && raw[0] == "`"
        tokens.push(ruby_token(:xstring, ruby_unquote(raw), tline))
      else
        tokens.push(ruby_token(:string, ruby_unquote(raw), tline))
    when 6
      tokens.push(ruby_token(:symbol, raw.slice(1, raw.size() - 1), tline))
    when 7
      if raw.size() > 1 && raw[0] == "(" && raw[1] == "/"
        tokens.push(ruby_token(:lparen, "(", tline))
        out = StringBuffer()
        scan_pos = off + 2
        while scan_pos < chars.size()
          ch = chars[scan_pos]
          if ch == "/"
            break
          if ch == "\\" && scan_pos + 1 < chars.size()
            out << ch
            scan_pos += 1
            out << chars[scan_pos]
          else
            out << ch
          scan_pos += 1
        close_off = scan_pos
        has_close_paren = false
        if close_off + 1 < chars.size() && chars[close_off + 1] == ")"
          has_close_paren = true
          close_off += 1
        while i + 1 < count && ruby_packed_offset(packed[i + 1]) <= close_off
          i += 1
        tokens.push(ruby_token(:regex, out.to_s(), tline))
        if has_close_paren
          tokens.push(ruby_token(:rparen, ")", tline))
      elsif raw.size() > 0 && raw[0] == "/" && ruby_regex_start_context?(tokens)
        out = StringBuffer()
        scan_pos = off + 1
        while scan_pos < chars.size()
          ch = chars[scan_pos]
          if ch == "/"
            break
          if ch == "\\" && scan_pos + 1 < chars.size()
            out << ch
            scan_pos += 1
            out << chars[scan_pos]
          else
            out << ch
          scan_pos += 1
        close_off = scan_pos
        while i + 1 < count && ruby_packed_offset(packed[i + 1]) <= close_off
          i += 1
        tokens.push(ruby_token(:regex, out.to_s(), tline))
      else
        ruby_push_operator_token(tokens, raw, tline)
    when 8
      # comments are intentionally skipped
      nil
    when 9
      tokens.push(ruby_token(:nl, "\n", tline))
    when 10
      tokens.push(ruby_token(:ivar, raw, tline))
    when 11
      tokens.push(ruby_token(:ivar, raw, tline))
    when 12
      tokens.push(ruby_token(:gvar, raw, tline))
    else
      ruby_push_operator_token(tokens, raw, tline)

    i += 1

  tokens.push(ruby_token(:eof, "", line))
  tokens

-> ruby_ast_escape(value)
  if value == nil
    return ""
  value.to_s().replace("%", "%25").replace("\n", "%0A").replace("\r", "%0D").replace("\t", "%09").replace(" ", "%20")

-> ruby_join_ids(ids)
  out = StringBuffer()
  i = 0
  while i < ids.size()
    if i > 0
      out << ","
    out << ids[i].to_s()
    i += 1
  out.to_s()

+ RubyAstOut
  -> new
    @next_id = 0
    @lines = []
    @root = -1

  -> node(type)
    id = @next_id
    @next_id += 1
    @lines.push("N " + id.to_s() + " " + type)
    id

  -> set_root(id)
    @root = id

  -> s(id, field, val)
    @lines.push("S " + id.to_s() + " " + field + " " + ruby_ast_escape(val))

  -> i(id, field, val)
    @lines.push("I " + id.to_s() + " " + field + " " + val.to_s())

  -> f(id, field, val)
    @lines.push("F " + id.to_s() + " " + field + " " + val.to_s())

  -> r(id, field, ref)
    if ref == nil
      ref = -1
    @lines.push("R " + id.to_s() + " " + field + " " + ref.to_s())

  -> a(id, field, refs)
    @lines.push("A " + id.to_s() + " " + field + " " + ruby_join_ids(refs))

  -> dump
    "ROOT " + @root.to_s() + "\n" + @lines.join("\n") + "\n"

-> ruby_precedence(op)
  case op
  when ".."
    0
  when "..."
    0
  when "||"
    1
  when "or"
    1
  when "&&"
    2
  when "and"
    2
  when "=="
    3
  when "!="
    3
  when "==="
    3
  when "=~"
    3
  when "<=>"
    3
  when "<"
    3
  when ">"
    3
  when "<="
    3
  when ">="
    3
  when "|"
    4
  when "^"
    4
  when "&"
    4
  when "<<"
    4
  when ">>"
    4
  when "+"
    5
  when "-"
    5
  when "*"
    6
  when "/"
    6
  when "%"
    6
  when "**"
    7
  else
    -1

-> ruby_array_copy(arr)
  out = []
  i = 0
  while i < arr.size()
    out.push(arr[i])
    i += 1
  out

+ RubyParser
  -> new(@tokens)
    @i = 0
    @out = RubyAstOut.new()
    @locals = []
    @assigned_names = collect_assigned_names(@tokens)
    @node_types = {}
    @node_names = {}
    @node_receivers = {}
    @node_args = {}

  -> collect_assigned_names(tokens)
    names = {}
    i = 0
    while i + 1 < tokens.size()
      if tokens[i][0] == :id
        nt = tokens[i + 1]
        receiver_name = false
        if i > 0
          pt = tokens[i - 1]
          receiver_name = pt[0] in (:dot :safe_dot :colon2)
        if !receiver_name && (nt[0] == :eq || (nt[0] == :op && nt[1] in ("+=" "-=" "*=" "/=" "%=")))
          names[tokens[i][1]] = true
      i += 1
    names

  -> parse
    program = @out.node("ProgramNode")
    stmts = parse_statements([:eof])
    @out.r(program, "statements", stmts)
    @out.set_root(program)
    @out.dump()

  -> parse_statements(stoppers)
    skip_nl()
    ids = []
    while !stoppers.include?(peek()[0])
      ids.push(parse_statement())
      skip_nl()
    id = @out.node("StatementsNode")
    @out.a(id, "body", ids)
    id

  -> parse_statement
    case peek()[0]
    when :class
      parse_class()
    when :module
      parse_module()
    when :def
      parse_def()
    when :if
      parse_if()
    when :unless
      parse_unless()
    when :case
      parse_case()
    when :begin
      parse_begin()
    when :while
      parse_while()
    when :for
      parse_for()
    when :return
      parse_return()
    when :yield
      parse_yield()
    when :next
      advance()
      parse_modifier(@out.node("NextNode"))
    when :break
      advance()
      parse_modifier(@out.node("BreakNode"))
    when :retry
      advance()
      parse_modifier(@out.node("RetryNode"))
    else
      expr = nil
      if multi_write_start?()
        expr = parse_multi_write()
      elsif command_call_start?()
        expr = parse_command_call()
      else
        expr = parse_expression()
      parse_modifier(expr)

  -> command_call_start?
    if peek()[0] != :id
      return false
    if @locals.include?(peek()[1])
      return false
    nt = @tokens[@i + 1]
    if nt == nil
      return false
    if nt[0] == :lparen && peek()[1] in ("puts" "p" "print" "warn" "raise")
      return true
    if nt[0] == :op && nt[1] in ("+" "-" "*" "/" "%" "==" "!=" "<" ">" "<=" ">=" "<=>" "&&" "||")
      return false
    if nt[0] in (:nl :eof :eq :dot :lparen)
      return false
    expression_start?(nt[0])

  -> multi_write_start?
    if !(peek()[0] in (:id :ivar))
      return false
    j = @i + 1
    seen_comma = false
    while j < @tokens.size()
      if @tokens[j][0] == :comma
        seen_comma = true
        j += 1
        if !(@tokens[j][0] in (:id :ivar))
          return false
      elsif @tokens[j][0] == :eq
        return seen_comma
      else
        return false
      j += 1
    false

  -> parse_multi_write
    targets = []
    loop
      tok = advance()
      target = nil
      if tok[0] == :ivar
        target = @out.node("InstanceVariableTargetNode")
        @out.s(target, "name", tok[1])
      else
        if !@locals.include?(tok[1])
          @locals.push(tok[1])
        target = @out.node("LocalVariableTargetNode")
        @out.s(target, "name", tok[1])
      targets.push(target)
      if !accept(:comma)
        break
    expect(:eq)
    values = []
    values.push(parse_expression())
    while accept(:comma)
      values.push(parse_expression())
    value = nil
    if values.size() == 1
      value = values[0]
    else
      value = @out.node("ArrayNode")
      @out.a(value, "elements", values)
    id = @out.node("MultiWriteNode")
    @out.a(id, "lefts", targets)
    @out.r(id, "value", value)
    id

  -> expression_start?(type)
    type in (:id :const :ivar :gvar :int :float :string :symbol :nil :true :false :self :lparen :lbrack :op)

  -> command_arg_start?(type)
    type in (:id :const :ivar :gvar :int :float :string :symbol :nil :true :false :self :lparen)

  -> parse_command_call
    name = expect(:id)[1]
    args = []
    while !(peek()[0] in (:nl :eof :end :else :elsif :if :unless :rescue :ensure))
      args.push(parse_expression())
      if !accept(:comma)
        break
    call_node(-1, name, args, -1)

  -> parse_modifier(expr)
    if accept(:if)
      pred = parse_expression()
      return if_node(pred, [expr], -1)
    if accept(:unless)
      pred = parse_expression()
      return if_node(pred, [], else_node([expr]))
    expr

  -> parse_class
    expect(:class)
    const = parse_const_path()
    superclass = -1
    if peek()[0] == :op && peek()[1] == "<"
      advance()
      superclass = parse_expression()
    body = parse_statements([:rescue, :ensure, :end])
    if peek()[0] in (:rescue :ensure)
      rescue_clause = -1
      ensure_clause = -1
      if peek()[0] == :rescue
        rescue_clause = parse_rescue_chain()
      if accept(:ensure)
        skip_nl()
        estmts = parse_statements([:end])
        ensure_clause = @out.node("EnsureNode")
        @out.r(ensure_clause, "statements", estmts)
      bid = @out.node("BeginNode")
      @out.r(bid, "statements", body)
      @out.r(bid, "rescue_clause", rescue_clause)
      @out.r(bid, "ensure_clause", ensure_clause)
      body = bid
    expect(:end)
    id = @out.node("ClassNode")
    @out.r(id, "constant_path", const)
    @out.r(id, "superclass", superclass)
    @out.r(id, "body", body)
    id

  -> parse_module
    expect(:module)
    const = parse_const_path()
    body = parse_statements([:end])
    expect(:end)
    id = @out.node("ModuleNode")
    @out.r(id, "constant_path", const)
    @out.r(id, "body", body)
    id

  -> parse_def
    expect(:def)
    old_locals = ruby_array_copy(@locals)
    receiver = -1
    if peek()[0] == :self
      receiver = parse_primary()
      expect(:dot)
    name_tok = advance()
    name = name_tok[1]
    params = parse_parameters()
    body = parse_statements([:rescue, :ensure, :end])
    if peek()[0] in (:rescue :ensure)
      rescue_clause = -1
      ensure_clause = -1
      if peek()[0] == :rescue
        rescue_clause = parse_rescue_chain()
      if accept(:ensure)
        skip_nl()
        estmts = parse_statements([:end])
        ensure_clause = @out.node("EnsureNode")
        @out.r(ensure_clause, "statements", estmts)
      bid = @out.node("BeginNode")
      @out.r(bid, "statements", body)
      @out.r(bid, "rescue_clause", rescue_clause)
      @out.r(bid, "ensure_clause", ensure_clause)
      body = bid
    expect(:end)
    @locals = old_locals
    id = @out.node("DefNode")
    @out.s(id, "name", name)
    @out.r(id, "parameters", params)
    @out.r(id, "body", body)
    @out.r(id, "receiver", receiver)
    id

  -> parse_parameters
    if !accept(:lparen)
      return -1
    requireds = []
    optionals = []
    keywords = []
    rest = -1
    block_param = -1
    while peek()[0] != :rparen && peek()[0] != :eof
      is_rest = false
      tok = nil
      if peek()[0] == :op && peek()[1] == "&"
        advance()
        tok = expect(:id)
        @locals.push(tok[1])
        block_param = @out.node("BlockParameterNode")
        @out.s(block_param, "name", tok[1])
        accept(:comma)
        next
      elsif peek()[0] == :op && peek()[1] == "*"
        advance()
        tok = expect(:id)
        @locals.push(tok[1])
        rest = @out.node("RestParameterNode")
        @out.s(rest, "name", tok[1])
        is_rest = true
      else
        tok = expect(:id)
        @locals.push(tok[1])
      if !is_rest
        if peek()[0] == :op && peek()[1] == ":"
          advance()
          if peek()[0] in (:comma :rparen)
            kid = @out.node("RequiredKeywordParameterNode")
            @out.s(kid, "name", tok[1])
            keywords.push(kid)
          else
            kid = @out.node("OptionalKeywordParameterNode")
            @out.s(kid, "name", tok[1])
            @out.r(kid, "value", parse_expression())
            keywords.push(kid)
        elsif accept(:eq)
          oid = @out.node("OptionalParameterNode")
          @out.s(oid, "name", tok[1])
          @out.r(oid, "value", parse_expression())
          optionals.push(oid)
        else
          rid = @out.node("RequiredParameterNode")
          @out.s(rid, "name", tok[1])
          requireds.push(rid)
      accept(:comma)
    expect(:rparen)
    id = @out.node("ParametersNode")
    @out.a(id, "requireds", requireds)
    @out.a(id, "optionals", optionals)
    @out.a(id, "keywords", keywords)
    if rest >= 0
      @out.r(id, "rest", rest)
    if block_param >= 0
      @out.r(id, "block", block_param)
    id

  -> parse_if
    expect(:if)
    parse_if_body()

  -> parse_if_body
    pred = parse_expression()
    skip_nl()
    stmts = parse_statements([:else, :elsif, :end])
    subsequent = -1
    if accept(:else)
      estmts = parse_statements([:end])
      subsequent = @out.node("ElseNode")
      @out.r(subsequent, "statements", estmts)
    elsif accept(:elsif)
      subsequent = parse_if_body()
      return if_node_from_parts(pred, stmts, subsequent)
    expect(:end)
    if_node_from_parts(pred, stmts, subsequent)

  -> if_node_from_parts(pred, stmts, subsequent)
    id = @out.node("IfNode")
    @out.r(id, "predicate", pred)
    @out.r(id, "statements", stmts)
    @out.r(id, "subsequent", subsequent)
    id

  -> parse_unless
    expect(:unless)
    pred = parse_expression()
    skip_nl()
    stmts = parse_statements([:end])
    expect(:end)
    empty = @out.node("StatementsNode")
    @out.a(empty, "body", [])
    else_id = @out.node("ElseNode")
    @out.r(else_id, "statements", stmts)
    id = @out.node("IfNode")
    @out.r(id, "predicate", pred)
    @out.r(id, "statements", empty)
    @out.r(id, "subsequent", else_id)
    id

  -> parse_case
    expect(:case)
    pred = -1
    if !(peek()[0] in (:nl :when :in))
      pred = parse_expression()
    skip_nl()
    if peek()[0] == :in
      return parse_case_match(pred)
    whens = []
    while accept(:when)
      conds = []
      conds.push(parse_expression())
      while accept(:comma)
        conds.push(parse_expression())
      accept(:then)
      skip_nl()
      body = parse_statements([:when, :else, :end])
      wid = @out.node("WhenNode")
      @out.a(wid, "conditions", conds)
      @out.r(wid, "statements", body)
      whens.push(wid)
      skip_nl()
    else_id = -1
    if accept(:else)
      skip_nl()
      estmts = parse_statements([:end])
      else_id = @out.node("ElseNode")
      @out.r(else_id, "statements", estmts)
    expect(:end)
    id = @out.node("CaseNode")
    @out.r(id, "predicate", pred)
    @out.a(id, "conditions", whens)
    @out.r(id, "else_clause", else_id)
    id

  -> parse_case_match(pred)
    ins = []
    while accept(:in)
      pat = parse_pattern()
      accept(:then)
      skip_nl()
      body = parse_statements([:in, :else, :end])
      iid = @out.node("InNode")
      @out.r(iid, "pattern", pat)
      @out.r(iid, "statements", body)
      ins.push(iid)
      skip_nl()
    else_id = -1
    if accept(:else)
      skip_nl()
      estmts = parse_statements([:end])
      else_id = @out.node("ElseNode")
      @out.r(else_id, "statements", estmts)
    expect(:end)
    id = @out.node("CaseMatchNode")
    @out.r(id, "predicate", pred)
    @out.a(id, "conditions", ins)
    @out.r(id, "else_clause", else_id)
    id

  -> parse_pattern
    left = parse_pattern_atom()
    while (peek()[0] == :op && peek()[1] == "|") || peek()[0] == :pipe
      advance()
      right = parse_pattern_atom()
      id = @out.node("AlternationPatternNode")
      @out.r(id, "left", left)
      @out.r(id, "right", right)
      left = id
    left

  -> parse_pattern_atom
    parse_primary()

  -> parse_begin
    expect(:begin)
    skip_nl()
    stmts = parse_statements([:rescue, :ensure, :end])
    rescue_clause = -1
    ensure_clause = -1
    if peek()[0] == :rescue
      rescue_clause = parse_rescue_chain()
    if accept(:ensure)
      skip_nl()
      estmts = parse_statements([:end])
      ensure_clause = @out.node("EnsureNode")
      @out.r(ensure_clause, "statements", estmts)
    expect(:end)
    id = @out.node("BeginNode")
    @out.r(id, "statements", stmts)
    @out.r(id, "rescue_clause", rescue_clause)
    @out.r(id, "ensure_clause", ensure_clause)
    id

  -> parse_rescue_chain
    first = -1
    prev = -1
    while accept(:rescue)
      exceptions = []
      reference = -1
      bare_line = peek()[0] == :nl
      skip_nl()
      if !bare_line && !(peek()[0] in (:nl :then :ensure :end))
        if !(peek()[0] == :op && peek()[1] == "=>")
          exceptions.push(parse_expression())
          while accept(:comma)
            exceptions.push(parse_expression())
        if peek()[0] == :op && peek()[1] == "=>"
          advance()
          tok = expect(:id)
          if !@locals.include?(tok[1])
            @locals.push(tok[1])
          reference = @out.node("LocalVariableTargetNode")
          @out.s(reference, "name", tok[1])
      accept(:then)
      skip_nl()
      body = parse_statements([:rescue, :ensure, :end])
      rid = @out.node("RescueNode")
      @out.a(rid, "exceptions", exceptions)
      @out.r(rid, "reference", reference)
      @out.r(rid, "statements", body)
      if first < 0
        first = rid
      if prev >= 0
        @out.r(prev, "subsequent", rid)
      prev = rid
      skip_nl()
    first

  -> parse_while
    expect(:while)
    pred = parse_expression()
    skip_nl()
    stmts = parse_statements([:end])
    expect(:end)
    id = @out.node("WhileNode")
    @out.r(id, "predicate", pred)
    @out.r(id, "statements", stmts)
    id

  -> parse_for
    expect(:for)
    name = expect(:id)[1]
    if !@locals.include?(name)
      @locals.push(name)
    target = @out.node("LocalVariableTargetNode")
    @out.s(target, "name", name)
    expect(:in)
    collection = parse_expression()
    skip_nl()
    stmts = parse_statements([:end])
    expect(:end)
    id = @out.node("ForNode")
    @out.r(id, "index", target)
    @out.r(id, "collection", collection)
    @out.r(id, "statements", stmts)
    id

  -> parse_yield
    expect(:yield)
    args = []
    if !(peek()[0] in (:nl :end :else :elsif :eof))
      args.push(parse_expression())
      while accept(:comma)
        args.push(parse_expression())
    aid = -1
    if args.size() > 0
      aid = @out.node("ArgumentsNode")
      @out.a(aid, "arguments", args)
    id = @out.node("YieldNode")
    @out.r(id, "arguments", aid)
    id

  -> parse_return
    expect(:return)
    args = []
    if !(peek()[0] in (:nl :end :eof))
      args.push(parse_expression())
      while accept(:comma)
        args.push(parse_expression())
    aid = @out.node("ArgumentsNode")
    @out.a(aid, "arguments", args)
    id = @out.node("ReturnNode")
    @out.r(id, "arguments", aid)
    id

  -> parse_expression(min_prec = 0)
    left = parse_assignment()
    loop
      tok = peek()
      op = tok[1]
      if tok[0] == :and
        op = "and"
      if tok[0] == :or
        op = "or"
      prec = ruby_precedence(op)
      if prec < min_prec
        break
      advance()
      skip_nl()
      right = parse_expression(prec + 1)
      if op == ".." || op == "..."
        nid = @out.node("RangeNode")
        @out.r(nid, "left", left)
        @out.r(nid, "right", right)
        left = nid
      elsif op == "&&" || op == "and"
        nid = @out.node("AndNode")
        @out.r(nid, "left", left)
        @out.r(nid, "right", right)
        left = nid
      elsif op == "||" || op == "or"
        nid = @out.node("OrNode")
        @out.r(nid, "left", left)
        @out.r(nid, "right", right)
        left = nid
      else
        left = call_node(left, op, [right], -1)
    if min_prec == 0 && peek()[0] == :op && peek()[1] == "?"
      advance()
      truthy = parse_expression()
      expect_op(":")
      falsey = parse_expression()
      left = if_node(left, [truthy], else_node([falsey]))
    if min_prec == 0 && accept(:rescue)
      fallback = parse_expression()
      rid = @out.node("RescueModifierNode")
      @out.r(rid, "expression", left)
      @out.r(rid, "rescue_expression", fallback)
      left = rid
    left

  -> parse_assignment
    left = parse_postfix(parse_primary())
    if accept(:eq)
      value = parse_expression()
      return write_node(left, value)
    if peek()[0] == :op && peek()[1] in ("+=" "-=" "*=" "/=" "%=")
      op = advance()[1]
      op = op.slice(0, op.size() - 1)
      value = parse_expression()
      return operator_write_node(left, op, value)
    left

  -> parse_primary
    tok = advance()
    case tok[0]
    when :id
      if tok[1] == "__LINE__"
        id = @out.node("SourceLineNode")
        @out.i(id, "start_line", tok[2])
        return id
      if tok[1] == "defined?"
        return parse_defined()
      if @locals.include?(tok[1]) || @assigned_names[tok[1]]
        id = @out.node("LocalVariableReadNode")
        @out.s(id, "name", tok[1])
        remember(id, "LocalVariableReadNode", tok[1])
        return id
      call_node(-1, tok[1], parse_call_args_if_present(), -1)
    when :const
      id = @out.node("ConstantReadNode")
      @out.s(id, "name", tok[1])
      remember(id, "ConstantReadNode", tok[1])
    when :ivar
      id = @out.node("InstanceVariableReadNode")
      @out.s(id, "name", tok[1])
      remember(id, "InstanceVariableReadNode", tok[1])
    when :gvar
      if tok[1].size() > 1 && tok[1][1] >= "0" && tok[1][1] <= "9"
        id = @out.node("NumberedReferenceReadNode")
        @out.i(id, "number", tok[1].slice(1, tok[1].size() - 1).to_i())
        id
      else
        id = @out.node("GlobalVariableReadNode")
        @out.s(id, "name", tok[1])
        remember(id, "GlobalVariableReadNode", tok[1])
    when :int
      id = @out.node("IntegerNode")
      @out.i(id, "value", tok[1].replace("_", ""))
      id
    when :float
      id = @out.node("FloatNode")
      @out.f(id, "value", tok[1].replace("_", ""))
      id
    when :string
      if tok[1].index("#{") != nil
        interpolated_string_node(tok[1])
      else
        id = @out.node("StringNode")
        @out.s(id, "content", tok[1])
        id
    when :xstring
      id = @out.node("XStringNode")
      @out.s(id, "content", tok[1])
      id
    when :symbol
      id = @out.node("SymbolNode")
      @out.s(id, "value", tok[1])
      id
    when :regex
      id = @out.node("RegularExpressionNode")
      @out.s(id, "unescaped", tok[1])
      id
    when :nil
      @out.node("NilNode")
    when :true
      @out.node("TrueNode")
    when :false
      @out.node("FalseNode")
    when :self
      @out.node("SelfNode")
    when :case
      @i -= 1
      parse_case()
    when :begin
      @i -= 1
      parse_begin()
    when :super
      args = parse_call_args_if_present()
      id = @out.node("SuperNode")
      if args.size() > 0
        aid = @out.node("ArgumentsNode")
        @out.a(aid, "arguments", args)
        @out.r(id, "arguments", aid)
      id
    when :lparen
      inner = parse_expression()
      expect(:rparen)
      id = @out.node("ParenthesesNode")
      @out.r(id, "body", inner)
      id
    when :lbrack
      parse_array()
    when :lbrace
      parse_hash()
    when :op
      if tok[1] == "-"
        if peek()[0] == :int
          nt = advance()
          id = @out.node("IntegerNode")
          @out.i(id, "value", "-" + nt[1].replace("_", ""))
          return id
        if peek()[0] == :float
          nt = advance()
          id = @out.node("FloatNode")
          @out.f(id, "value", "-" + nt[1].replace("_", ""))
          return id
        return call_node(parse_primary(), "-@", [], -1)
      if tok[1] == ":" && peek()[0] in (:id :const)
        nt = advance()
        return symbol_node(nt[1])
      raise "unexpected token " + tok[0].to_s() + " " + tok[1].to_s() + " near " + near_tokens()
    else
      raise "unexpected token " + tok[0].to_s() + " " + tok[1].to_s() + " near " + near_tokens()

  -> parse_defined
    value = nil
    if accept(:lparen)
      value = parse_expression()
      expect(:rparen)
    else
      value = parse_expression()
    id = @out.node("DefinedNode")
    @out.r(id, "value", value)
    id

  -> interpolated_string_node(value)
    parts = []
    rest = value
    idx = rest.index("#{")
    while idx != nil
      text = rest.slice(0, idx)
      if text.size() > 0
        sid = @out.node("StringNode")
        @out.s(sid, "content", text)
        parts.push(sid)
      close = rest.index("}")
      if close == nil
        break
      expr_src = rest.slice(idx + 2, close - idx - 2).strip()
      expr = nil
      if @locals.include?(expr_src) || @assigned_names[expr_src]
        expr = @out.node("LocalVariableReadNode")
        @out.s(expr, "name", expr_src)
      else
        expr = call_node(-1, expr_src, [], -1)
      stmts = @out.node("StatementsNode")
      @out.a(stmts, "body", [expr])
      emb = @out.node("EmbeddedStatementsNode")
      @out.r(emb, "statements", stmts)
      parts.push(emb)
      rest = rest.slice(close + 1, rest.size() - close - 1)
      idx = rest.index("#{")
    if rest.size() > 0
      sid = @out.node("StringNode")
      @out.s(sid, "content", rest)
      parts.push(sid)
    id = @out.node("InterpolatedStringNode")
    @out.a(id, "parts", parts)
    id

  -> parse_postfix(left)
    loop
      if accept(:dot)
        name = advance()[1]
        args = parse_call_args_if_present()
        if args.size() == 0 && command_arg_start?(peek()[0])
          args.push(parse_expression())
          while accept(:comma)
            args.push(parse_expression())
        left = call_node(left, name, args, -1)
      elsif accept(:safe_dot)
        name = advance()[1]
        args = parse_call_args_if_present()
        left = call_node(left, name, args, -1)
        @out.s(left, "call_operator", "&.")
      elsif accept(:colon2)
        name = expect(:const)[1]
        cid = @out.node("ConstantPathNode")
        @out.r(cid, "parent", left)
        @out.s(cid, "name", name)
        left = cid
      elsif accept(:lbrack)
        recv = left
        args = []
        if peek()[0] != :rbrack
          args.push(parse_expression())
          while accept(:comma)
            args.push(parse_expression())
        expect(:rbrack)
        left = call_node(recv, "[]", args, -1)
      elsif peek()[0] == :lparen
        args = parse_call_args_if_present()
        left = call_node(left, "call", args, -1)
      elsif peek()[0] == :lbrace
        block = parse_block()
        @out.r(left, "block", block)
      elsif peek()[0] == :do
        block = parse_do_block()
        @out.r(left, "block", block)
      else
        break
    left

  -> parse_call_args_if_present
    if !accept(:lparen)
      return []
    args = []
    skip_nl()
    while peek()[0] != :rparen && peek()[0] != :eof
      if label_start?()
        args.push(parse_keyword_hash())
        skip_nl()
        break
      args.push(parse_expression())
      accept(:comma)
      skip_nl()
    expect(:rparen)
    args

  -> parse_array
    elems = []
    skip_nl()
    while peek()[0] != :rbrack && peek()[0] != :eof
      elems.push(parse_expression())
      accept(:comma)
      skip_nl()
    expect(:rbrack)
    id = @out.node("ArrayNode")
    @out.a(id, "elements", elems)
    id

  -> parse_hash
    elems = []
    skip_nl()
    while peek()[0] != :rbrace && peek()[0] != :eof
      key = nil
      value = nil
      if label_start?()
        key_name = advance()[1]
        expect_op(":")
        key = symbol_node(key_name)
        value = parse_expression()
      else
        key = parse_expression()
        expect_op("=>")
        value = parse_expression()
      assoc = @out.node("AssocNode")
      @out.r(assoc, "key", key)
      @out.r(assoc, "value", value)
      elems.push(assoc)
      accept(:comma)
      skip_nl()
    expect(:rbrace)
    id = @out.node("HashNode")
    @out.a(id, "elements", elems)
    id

  -> parse_keyword_hash
    elems = []
    while label_start?()
      key_name = advance()[1]
      expect_op(":")
      key = symbol_node(key_name)
      value = parse_expression()
      assoc = @out.node("AssocNode")
      @out.r(assoc, "key", key)
      @out.r(assoc, "value", value)
      elems.push(assoc)
      if !accept(:comma)
        break
      skip_nl()
    id = @out.node("KeywordHashNode")
    @out.a(id, "elements", elems)
    id

  -> label_start?
    if peek()[0] != :id
      return false
    nt = @tokens[@i + 1]
    nt != nil && nt[0] == :op && nt[1] == ":"

  -> symbol_node(name)
    id = @out.node("SymbolNode")
    @out.s(id, "value", name)
    id

  -> parse_block
    expect(:lbrace)
    parse_block_body(:rbrace)

  -> parse_do_block
    expect(:do)
    parse_block_body(:end)

  -> parse_block_body(terminator)
    param_ids = []
    old_locals = ruby_array_copy(@locals)
    if accept(:pipe)
      while peek()[0] != :pipe && peek()[0] != :eof
        tok = expect(:id)
        @locals.push(tok[1])
        rid = @out.node("RequiredParameterNode")
        @out.s(rid, "name", tok[1])
        param_ids.push(rid)
        accept(:comma)
      expect(:pipe)
    body = parse_statements([terminator])
    expect(terminator)
    params = -1
    if param_ids.size() > 0
      inner = @out.node("ParametersNode")
      @out.a(inner, "requireds", param_ids)
      @out.a(inner, "optionals", [])
      @out.a(inner, "keywords", [])
      params = @out.node("BlockParametersNode")
      @out.r(params, "parameters", inner)
    id = @out.node("BlockNode")
    @out.r(id, "parameters", params)
    @out.r(id, "body", body)
    @locals = old_locals
    id

  -> parse_const_path
    id = parse_primary()
    while accept(:colon2)
      name = expect(:const)[1]
      cid = @out.node("ConstantPathNode")
      @out.r(cid, "parent", id)
      @out.s(cid, "name", name)
      id = cid
    id

  -> write_node(left, value)
    type = node_type(left)
    name = node_name(left)
    id = nil
    if type == "LocalVariableReadNode"
      if !@locals.include?(name)
        @locals.push(name)
      id = @out.node("LocalVariableWriteNode")
    elsif type == "InstanceVariableReadNode"
      id = @out.node("InstanceVariableWriteNode")
    elsif type == "GlobalVariableReadNode"
      id = @out.node("GlobalVariableWriteNode")
    elsif type == "ConstantReadNode"
      id = @out.node("ConstantWriteNode")
    elsif type == "CallNode" && name == "[]"
      args = @node_args[left]
      if args == nil
        args = []
      args.push(value)
      return call_node(@node_receivers[left], "[]=", args, -1)
    elsif type == "CallNode" && @node_receivers[left] != nil && @node_receivers[left] >= 0
      return call_node(@node_receivers[left], name + "=", [value], -1)
    else
      return call_node(left, "=", [value], -1)
    @out.s(id, "name", name)
    @out.r(id, "value", value)
    id

  -> operator_write_node(left, op, value)
    type = node_type(left)
    name = node_name(left)
    id = nil
    if type == "LocalVariableReadNode"
      id = @out.node("LocalVariableOperatorWriteNode")
    elsif type == "InstanceVariableReadNode"
      id = @out.node("InstanceVariableOperatorWriteNode")
    else
      return call_node(left, op, [value], -1)
    @out.s(id, "name", name)
    @out.s(id, "binary_operator", op)
    @out.r(id, "value", value)
    id

  -> node_type(id)
    if @node_types[id] == nil
      return ""
    @node_types[id]

  -> node_name(id)
    if @node_names[id] == nil
      return ""
    @node_names[id]

  -> remember(id, type, name)
    @node_types[id] = type
    @node_names[id] = name
    id

  -> call_node(receiver, name, args, block)
    aid = -1
    if args != nil && args.size() > 0
      aid = @out.node("ArgumentsNode")
      @out.a(aid, "arguments", args)
    id = @out.node("CallNode")
    @out.s(id, "name", name)
    @out.r(id, "receiver", receiver)
    @out.r(id, "arguments", aid)
    @out.r(id, "block", block)
    remember(id, "CallNode", name)
    @node_receivers[id] = receiver
    if args == nil
      args = []
    @node_args[id] = args
    id

  -> if_node(predicate, truthy_ids, subsequent)
    stmts = @out.node("StatementsNode")
    @out.a(stmts, "body", truthy_ids)
    id = @out.node("IfNode")
    @out.r(id, "predicate", predicate)
    @out.r(id, "statements", stmts)
    @out.r(id, "subsequent", subsequent)
    id

  -> else_node(ids)
    stmts = @out.node("StatementsNode")
    @out.a(stmts, "body", ids)
    id = @out.node("ElseNode")
    @out.r(id, "statements", stmts)
    id

  -> peek
    @tokens[@i]

  -> advance
    tok = @tokens[@i]
    @i += 1
    tok

  -> accept(type)
    if peek()[0] != type
      return false
    @i += 1
    true

  -> expect(type)
    tok = advance()
    if tok[0] != type
      raise "expected " + type.to_s() + ", got " + tok[0].to_s() + " " + tok[1].to_s() + " near " + near_tokens()
    tok

  -> expect_op(value)
    tok = advance()
    if tok[0] != :op || tok[1] != value
      raise "expected op " + value + ", got " + tok[0].to_s() + " " + tok[1].to_s() + " near " + near_tokens()
    tok

  -> near_tokens
    start = @i - 4
    if start < 0
      start = 0
    stop = @i + 5
    if stop > @tokens.size()
      stop = @tokens.size()
    out = StringBuffer()
    out << @i.to_s()
    out << ": "
    j = start
    while j < stop
      t = @tokens[j]
      out << t[0].to_s()
      out << ":"
      out << t[1].to_s()
      out << " "
      j += 1
    out.to_s()

  -> skip_nl
    while peek()[0] == :nl
      @i += 1

-> ruby_parse(source)
  tokens = ruby_materialize_tokens(source)
  RubyParser.new(tokens).parse()

args = argv()
if args.size() == 0
  << "usage: ruby_parser <input.rb> output.ast"
  exit(1)

source_file = args[0]
out_file = nil
if args.size() > 1
  out_file = args[1]

source = read_file(source_file)
if source == nil
  << "ruby_parser: cannot read " + source_file
  exit(1)

ast = ruby_parse(source)
if out_file == nil
  <- ast
else
  write_file(out_file, ast)
