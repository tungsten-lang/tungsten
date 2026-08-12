# AST source formatter. This is the self-hosted counterpart of
# implementations/ruby/lib/tungsten/formatter.rb. It deliberately rejects an
# unsupported node instead of writing an object inspection into source.

use lexer
use parser

# Comments are not AST nodes yet. For comments at statement boundaries, mask
# them as uniquely named zero-argument calls, format the real AST, then restore
# the comment in the marker's formatted position. This keeps indentation tied
# to the surrounding AST instead of making every documented file bypass the
# formatter. Grouped-expression comments and comments swallowed by a `##` hint
# remain on the lossless fallback until their exact attachment point is modeled.
-> formatter_group_depth_at(tokens, token_count, offset)
  depth = 0
  i = 0
  while i < token_count
    token = tokens[i]
    if parser_tok_off(token) >= offset
      break
    kind = parser_tok_type(token)
    if kind in (T_LPAREN T_LBRACKET T_LBRACE)
      depth += 1
    elsif kind in (T_RPAREN T_RBRACKET T_RBRACE)
      depth -= 1
    i += 1
  depth

-> formatter_line_indent(line)
  chars = line.chars()
  out = StringBuffer(chars.size())
  i = 0
  while i < chars.size()
    if chars[i] != " " && chars[i] != "\t"
      break
    out << chars[i]
    i += 1
  out.to_s()

-> formatter_line_slice(line, from, count)
  chars = line.chars()
  out = StringBuffer(count)
  i = from
  finish = from + count
  if finish > chars.size()
    finish = chars.size()
  while i < finish
    out << chars[i]
    i += 1
  out.to_s()

-> formatter_next_content_indent(lines, index)
  i = index + 1
  while i < lines.size()
    stripped = lines[i].strip()
    if stripped != "" && !stripped.starts_with?("#")
      return formatter_line_indent(lines[i])
    i += 1
  ""

-> formatter_mask_comments(source, file)
  if source.include?("__tungsten_fmt_comment_")
    return nil
  probe = Lexer.new(source, file)
  token_count = probe.tokenize()
  # Polyglot bash headers are rewritten in-place by Lexer. Keep their exact
  # two-line trampoline on the lossless path until header attachment is a
  # first-class formatter concept.
  if probe.source() != source
    return nil
  tokens = probe.packed_tokens()
  chars = probe.chars()
  covered = {}
  ti = 0
  while ti < token_count
    token = tokens[ti]
    off = parser_tok_off(token)
    size = parser_tok_len(token)
    kind = parser_tok_type(token)
    next_off = nil
    if ti + 1 < token_count
      next_off = parser_tok_off(tokens[ti + 1])
    else
      next_off = chars.size()
    # Packed token lengths wrap at 4096. A hash inside a long string-like
    # token would otherwise look uncovered and be mistaken for a comment.
    # Conservatively keep that rare source on the lossless path.
    if next_off - off >= 4096 && kind in (T_STRING T_STRING_INTERP T_REGEX T_REGEX_CAPTURE T_BYTE_ARRAY T_BYTE_ARRAY_INTERP T_WORD_ARRAY T_SYMBOL_ARRAY T_TYPE_HINT)
      return nil
    j = 0
    while j < size
      covered[off + j] = kind
      j += 1
    ti += 1

  line_at = probe.line_at()
  col_at = probe.col_at()
  columns = {}
  i = 0
  while i < chars.size()
    if chars[i] != "#"
      i += 1
      next
    if i + 1 < chars.size() && chars[i + 1] == "#"
      i += 2
      next
    # Key tokens store their packed span after the `#[` introducer, so the
    # leading hash is not covered even though it is not a comment.
    if i + 1 < chars.size() && chars[i + 1] == "\["
      i += 2
      next
    token_kind = covered[i]
    if token_kind != nil && token_kind != T_TYPE_HINT
      i += 1
      next
    # A trailing comment is part of the packed TYPE_HINT token even though
    # Parser later strips it. Replacing it with a statement would sever the
    # pending hint from its definition, so retain the lossless fallback.
    if token_kind == T_TYPE_HINT
      return nil
    if formatter_group_depth_at(tokens, token_count, i) > 0
      return nil
    line = line_at[i]
    if columns[line] == nil
      columns[line] = col_at[i]
    while i < chars.size() && chars[i] != "\n"
      i += 1

  if columns.empty?()
    return {source: source, comments: {}}

  lines = source.split("\n")
  comments = {}
  out = StringBuffer(source.size() + columns.size() * 48)
  li = 0
  serial = 0
  while li < lines.size()
    column = columns[li + 1]
    if column == nil
      out << lines[li]
    else
      line = lines[li]
      before = formatter_line_slice(line, 0, column - 1).rtrim()
      comment = formatter_line_slice(line, column - 1, line.chars().size() - column + 1).rtrim()
      marker = "__tungsten_fmt_comment_" + serial.to_s() + "__()"
      if before.strip() == ""
        indent = formatter_line_indent(line)
        out << indent << marker
        comments[marker] = {text: comment, inline: false}
      else
        indent = formatter_line_indent(line)
        next_indent = formatter_next_content_indent(lines, li)
        if next_indent.size() > indent.size()
          indent = next_indent
        out << before << "\n" << indent << marker
        comments[marker] = {text: comment, inline: true}
      serial += 1
    if li + 1 < lines.size()
      out << "\n"
    li += 1
  {source: out.to_s(), comments: comments}

-> formatter_restore_comments(formatted, comments)
  if comments == nil || comments.empty?()
    return formatted
  lines = formatted.split("\n")
  restored = []
  i = 0
  while i < lines.size()
    line = lines[i]
    marker = line.strip()
    attached = comments[marker]
    if attached == nil
      restored.push(line)
    elsif attached[:inline]
      if restored.empty?()
        restored.push(attached[:text])
      else
        previous = restored.pop()
        restored.push(previous + "  " + attached[:text])
    else
      indent = formatter_line_indent(line)
      restored.push(indent + attached[:text])
    i += 1
  restored.join("\n").rtrim() + "\n"

# Retain exact placement and apply only lossless whitespace cleanup when a
# comment shape cannot yet be attached without changing program structure.
-> formatter_lossless_whitespace(source)
  lines = source.split("\n")
  out = StringBuffer(source.size + 16)
  finish = lines.size
  while finish > 0 && lines[finish - 1].strip() == ""
    finish -= 1
  i = 0
  while i < finish
    line = lines[i]
    while line.size > 0
      last = line.slice(line.size - 1, 1)
      if last == " " || last == "\t"
        line = line.slice(0, line.size - 1)
      else
        break
    out << line << "\n"
    i += 1
  out.to_s()

-> formatter_indent(depth)
  "  " * depth

-> formatter_quote(text)
  out = StringBuffer(text.size + 8)
  out << "\""
  chars = text.chars()
  i = 0
  while i < chars.size
    ch = chars[i]
    case ch
    when "\\"
      out << "\\\\"
    when "\""
      out << "\\\""
    when "\n"
      out << "\\n"
    when "\r"
      out << "\\r"
    when "\t"
      out << "\\t"
    else
      out << ch
    i += 1
  out << "\""
  out.to_s()

-> formatter_operator(op)
  case op
  when :PLUS
    "+"
  when :MINUS
    "-"
  when :STAR
    "*"
  when :SLASH
    "/"
  when :PERCENT
    "%"
  when :POW
    "**"
  when :EQ
    "=="
  when :CASE_EQ
    "==="
  when :NEQ
    "!="
  when :LT
    "<"
  when :LTE
    "<="
  when :GT
    ">"
  when :GTE
    ">="
  when :MATCH
    "=~"
  when :SPACESHIP
    "<=>"
  when :AND
    "&&"
  when :OR
    "||"
  when :AMPERSAND
    "&"
  when :PIPE
    "|"
  when :CARET
    "^"
  when :LSHIFT
    "<<"
  when :RSHIFT
    ">>"
  when :DOT_PRODUCT
    "·"
  when :CROSS_PRODUCT
    "×"
  when :HADAMARD
    "⊙"
  when :KRONECKER
    "⊗"
  when :DOT_PLUS
    ".+"
  when :DOT_MINUS
    ".-"
  when :DOT_STAR
    ".*"
  when :DOT_SLASH
    "./"
  when :DOT_PIPE
    ".|"
  when :DOT_AMP
    ".&"
  when :DOT_CARET
    ".^"
  when :DOT_LSHIFT
    ".<<"
  when :DOT_RSHIFT
    ".>>"
  when :APPROX
    "≈"
  when :PIPE_FWD
    "|>"
  else
    op.to_s()

-> formatter_join_nodes(nodes, separator, depth = 0)
  parts = []
  i = 0
  while i < nodes.size
    parts.push(formatter_expr(nodes[i], depth))
    i += 1
  parts.join(separator)

-> formatter_param(node, depth)
  if type(node) == "String"
    return node
  name = node.name.to_s()
  if node.ivar_assign
    name = "@" + name unless name.starts_with?("@")
  if node.splat
    name = "*" + name
  if node.block_param
    name = "&" + name
  if node.keyword
    name = name + ":"
  if node.default != nil
    name += " = " + formatter_expr(node.default, depth)
  name

-> formatter_params(params, depth)
  parts = []
  i = 0
  while i < params.size
    parts.push(formatter_param(params[i], depth))
    i += 1
  parts.join(", ")

-> formatter_type_args(values)
  if values == nil || values.empty?()
    return ""
  rendered = []
  i = 0
  while i < values.size
    rendered.push(values[i].to_s())
    i += 1
  "<" + rendered.join(", ") + ">"

# Platform predicates use their own small grammar. The precedence values here
# mirror parser.w: `!` binds tighter than `&&`, which binds tighter than `||`.
-> formatter_target(node, parent_precedence = 0)
  kind = ast_kind(node)
  precedence = 4
  if kind == :target_or
    precedence = 1
  elsif kind == :target_and
    precedence = 2
  elsif kind == :target_not
    precedence = 3

  if kind == :target_designator
    out = node.name.to_s()
  elsif kind == :target_not
    out = "!" + formatter_target(node.expression, precedence)
  elsif kind == :target_and
    out = formatter_target(node.left, precedence) + " && " + formatter_target(node.right, precedence)
  elsif kind == :target_or
    out = formatter_target(node.left, precedence) + " || " + formatter_target(node.right, precedence)
  else
    raise "tungsten fmt: unsupported target node :" + kind.to_s()

  if precedence < parent_precedence
    return "(" + out + ")"
  out

-> formatter_block(node, depth)
  params = formatter_params(node.params, depth)
  header = "->"
  if params != ""
    header += " (" + params + ")"
  body = formatter_sequence(node.body, depth + 1)
  if body == ""
    return header
  header + "\n" + body

-> formatter_call(node, depth, safe = false)
  receiver = node.receiver
  name = node.name.to_s()
  out = ""
  if receiver != nil
    out = formatter_expr(receiver, depth)
    if ast_kind(receiver) == :range || ast_kind(receiver) == :quantity
      out = "(" + out + ")"
    out += formatter_type_args(node.type_args)
    if name == "\[\]"
      out += "\[" + formatter_join_nodes(node.args, ", ", depth) + "\]"
    elsif name == "\[\]="
      indices = []
      i = 0
      while i + 1 < node.args.size
        indices.push(formatter_expr(node.args[i], depth))
        i += 1
      out += "\[" + indices.join(", ") + "\] = " + formatter_expr(node.args[node.args.size - 1], depth)
    else
      out += safe ? "&." : "."
      out += name
  else
    out = name + formatter_type_args(node.type_args)
  if name != "\[\]" && name != "\[\]=" && node.args != nil && !node.args.empty?()
    out += "(" + formatter_join_nodes(node.args, ", ", depth) + ")"
  elsif receiver == nil && node.args != nil && node.args.empty?()
    out += "()"
  if node.block != nil
    out += " " + formatter_block(node.block, depth)
  out

-> formatter_hash_key(node, depth)
  if ast_kind(node) == :symbol
    return node.value.to_s()
  formatter_expr(node, depth)

-> formatter_expr(node, depth = 0)
  if node == nil
    return "nil"
  kind = ast_kind(node)
  case kind
  when :int
    if node.raw != nil
      return node.raw.to_s()
    node.value.to_s()
  when :wvalue
    node.raw.to_s()
  when :float
    "~" + node.value.to_s()
  when :decimal
    node.value.to_s()
  when :quantity
    unit = node.unit.to_s()
    separator = unit == "%" ? "" : " "
    node.number_str.to_s() + separator + unit
  when :currency
    prefix = node.prefix == nil ? "" : node.prefix.to_s()
    suffix = node.suffix == nil ? "" : node.suffix.to_s()
    prefix + node.amount.to_s() + suffix
  when :date, :datetime, :time, :month, :ip4, :cidr4, :ip6, :cidr6, :rational
    node.value.to_s()
  when :duration
    node.raw.to_s()
  when :codepoint
    hex = node.value.to_s(16).upcase()
    while hex.size < 4
      hex = "0" + hex
    "U+" + hex
  when :color
    hex = node.rgba.to_s(16).upcase()
    while hex.size < 8
      hex = "0" + hex
    "#" + hex
  when :bool
    node.value ? "true" : "false"
  when :nil_lit
    "nil"
  when :string
    formatter_quote(node.value.to_s())
  when :string_interp
    out = StringBuffer(32)
    out << "\""
    i = 0
    while i < node.parts.size
      part = node.parts[i]
      if part[0] == :str
        literal = formatter_quote(part[1].to_s())
        out << literal.slice(1, literal.size - 2)
      else
        out << "\[" << formatter_expr(part[1], depth) << "\]"
      i += 1
    out << "\""
    out.to_s()
  when :symbol
    ":" + node.value.to_s()
  when :array
    "\[" + formatter_join_nodes(node.elements, ", ", depth) + "\]"
  when :typed_array, :typed_array_new
    node.element_type.to_s() + "\[" + formatter_expr(node.size, depth) + "\]"
  when :hash_literal
    entries = []
    i = 0
    while i < node.entries.size
      entry = node.entries[i]
      entries.push(formatter_hash_key(entry[0], depth) + ": " + formatter_expr(entry[1], depth))
      i += 1
    "{" + entries.join(", ") + "}"
  when :byte_array
    bytes = []
    i = 0
    while i < node.values.size
      bytes.push(node.values[i].to_s(16).rjust(2, "0"))
      i += 1
    bytes.empty?() ? "« »" : "« " + bytes.join(" ") + " »"
  when :byte_array_interp
    parts = []
    i = 0
    while i < node.parts.size
      part = node.parts[i]
      if part[0] == :bytes
        values = []
        j = 0
        while j < part[1].size
          values.push(part[1][j].to_s(16).rjust(2, "0"))
          j += 1
        parts.push(values.join(" "))
      else
        parts.push("\[" + formatter_expr(part[1], depth) + "\]")
      i += 1
    "« " + parts.join(" ") + " »"
  when :var, :ivar, :cvar, :gvar
    node.name.to_s()
  when :parg
    "@" + node.index.to_s()
  when :class_ref
    node.name.to_s() + formatter_type_args(node.type_args)
  when :magic_constant
    "__" + node.name.to_s() + "__"
  when :self_ref
    "self"
  when :binary_op
    "(" + formatter_expr(node.left, depth) + " " + formatter_operator(node.op) + " " + formatter_expr(node.right, depth) + ")"
  when :unary_op
    "(" + formatter_operator(node.op) + formatter_expr(node.operand, depth) + ")"
  when :not
    "(!" + formatter_expr(node.operand, depth) + ")"
  when :and
    "(" + formatter_expr(node.left, depth) + " && " + formatter_expr(node.right, depth) + ")"
  when :or
    "(" + formatter_expr(node.left, depth) + " || " + formatter_expr(node.right, depth) + ")"
  when :assign
    value = formatter_expr(node.value, depth)
    if node.type_hint != nil
      value += " ## " + node.type_hint.to_s()
    "(" + formatter_expr(node.target, depth) + " = " + value + ")"
  when :compound_assign
    "(" + formatter_expr(node.target, depth) + " " + formatter_operator(node.op) + "= " + formatter_expr(node.value, depth) + ")"
  when :call
    formatter_call(node, depth)
  when :safe_nav
    formatter_call(node, depth, true)
  when :range
    right = node.to == nil ? "" : formatter_expr(node.to, depth)
    formatter_expr(node.from, depth) + (node.exclusive ? "..." : "..") + right
  when :splat
    "*" + formatter_expr(node.expression, depth)
  when :super
    node.args.empty?() ? "super" : "super(" + formatter_join_nodes(node.args, ", ", depth) + ")"
  when :block
    formatter_block(node, depth)
  when :passthrough
    formatter_expr(node.expression, depth) + "; " + formatter_expr(node.value, depth)
  when :rescue_expr
    "(" + formatter_expr(node.body, depth) + " rescue " + formatter_expr(node.fallback, depth) + ")"
  when :type_ascription
    formatter_expr(node.expression, depth) + " ## " + node.type_hint.to_s()
  else
    raise "tungsten fmt: unsupported expression node :" + kind.to_s()

-> formatter_sequence(nodes, depth)
  return "" if nodes == nil || nodes.empty?()
  out = StringBuffer(nodes.size * 32)
  i = 0
  while i < nodes.size
    out << formatter_statement(nodes[i], depth)
    out << "\n" if i + 1 < nodes.size
    i += 1
  out.to_s()

-> formatter_definition(node, depth, keyword)
  prefix = formatter_indent(depth)
  header = prefix + keyword + " "
  if ast_kind(node) == :method_def && node.is_class_method
    header += "."
  header += node.name.to_s()
  if node.params != nil && !node.params.empty?()
    header += "(" + formatter_params(node.params, depth) + ")"
  hints = node.type_hints
  if hints != nil && !hints.empty?()
    names = hints.keys()
    hint_lines = StringBuffer(names.size * 24)
    i = 0
    while i < names.size
      name = names[i]
      hint_lines << prefix << "## " << hints[name].to_s() << ": " << name.to_s() << "\n"
      i += 1
    header = hint_lines.to_s() + header
  body = formatter_sequence(node.body, depth + 1)
  body == "" ? header : header + "\n" + body

-> formatter_gpu_definition(node, depth)
  prefix = formatter_indent(depth)
  header = prefix + "@" + node.attribute.to_s() + " fn " + node.name.to_s()
  if node.params != nil && !node.params.empty?()
    header += "(" + formatter_params(node.params, depth) + ")"
  hints = node.type_hints
  if hints != nil && !hints.empty?()
    names = hints.keys()
    hint_lines = StringBuffer(names.size * 24)
    i = 0
    while i < names.size
      name = names[i]
      hint_lines << prefix << "## " << hints[name].to_s() << ": " << name.to_s() << "\n"
      i += 1
    header = hint_lines.to_s() + header
  body = formatter_sequence(node.body, depth + 1)
  body == "" ? header : header + "\n" + body

-> formatter_if(node, depth)
  out = formatter_indent(depth) + "if " + formatter_expr(node.condition, depth) + "\n"
  out += formatter_sequence(node.then_body, depth + 1)
  i = 0
  while i < node.elsif_clauses.size
    clause = node.elsif_clauses[i]
    out += "\n" + formatter_indent(depth) + "elsif " + formatter_expr(clause[0], depth) + "\n"
    out += formatter_sequence(clause[1], depth + 1)
    i += 1
  if node.else_body != nil && !node.else_body.empty?()
    out += "\n" + formatter_indent(depth) + "else\n"
    out += formatter_sequence(node.else_body, depth + 1)
  out

-> formatter_case_value(node, depth)
  out = formatter_indent(depth) + "case " + formatter_expr(node.subject, depth)
  i = 0
  while i < node.arms.size
    arm = node.arms[i]
    out += "\n" + formatter_indent(depth) + "when " + formatter_expr(arm.pattern, depth)
    if arm.guard != nil
      out += " if " + formatter_expr(arm.guard, depth)
    out += "\n" + formatter_sequence(arm.body, depth + 1)
    i += 1
  if node.else_body != nil && !node.else_body.empty?()
    out += "\n" + formatter_indent(depth) + "else\n"
    out += formatter_sequence(node.else_body, depth + 1)
  out

-> formatter_case(node, depth)
  out = formatter_indent(depth) + "case"
  i = 0
  while i < node.whens.size
    branch = node.whens[i]
    out += "\n" + formatter_indent(depth) + "when " + formatter_join_nodes(branch.conditions, ", ", depth) + "\n"
    out += formatter_sequence(branch.body, depth + 1)
    i += 1
  if node.else_body != nil && !node.else_body.empty?()
    out += "\n" + formatter_indent(depth) + "else\n"
    out += formatter_sequence(node.else_body, depth + 1)
  out

-> formatter_generic_body(node, depth)
  out = StringBuffer(64)
  constraints = node.type_constraints
  skip_nils = 0
  wrote = false
  if constraints != nil
    i = 0
    while i < constraints.size
      constraint = constraints[i]
      out << formatter_indent(depth) << "with " << constraint[0].to_s() << " in (" << constraint[1].join(" ") << ")"
      wrote = true
      skip_nils += 1
      i += 1
      if i < constraints.size
        out << "\n"
  i = 0
  while i < node.body.size
    child = node.body[i]
    if skip_nils > 0 && ast_kind(child) == :nil_lit
      skip_nils -= 1
    else
      if wrote
        out << "\n"
      out << formatter_statement(child, depth)
      wrote = true
    i += 1
  out.to_s()

-> formatter_statement(node, depth = 0)
  kind = ast_kind(node)
  prefix = formatter_indent(depth)
  case kind
  when :assign
    value = formatter_expr(node.value, depth)
    if node.type_hint != nil
      value += " ## " + node.type_hint.to_s()
    prefix + formatter_expr(node.target, depth) + " = " + value
  when :multi_assign
    prefix + formatter_join_nodes(node.targets, ", ", depth) + " = " + formatter_expr(node.value, depth)
  when :compound_assign
    prefix + formatter_expr(node.target, depth) + " " + formatter_operator(node.op) + "= " + formatter_expr(node.value, depth)
  when :puts
    prefix + "<< " + formatter_join_nodes(node.value, ", ", depth)
  when :print
    prefix + "<- " + formatter_expr(node.value, depth)
  when :use
    prefix + "use " + node.path.to_s()
  when :method_def
    formatter_definition(node, depth, "->")
  when :fn_def
    formatter_definition(node, depth, "fn")
  when :gpu_kernel_def
    formatter_gpu_definition(node, depth)
  when :class_def
    header = prefix + "+ " + node.name.to_s() + formatter_type_args(node.type_params)
    if node.class_role != nil
      header += " \[" + node.class_role.to_s() + "\]"
    if node.superclass != nil
      header += " < " + node.superclass.to_s() + formatter_type_args(node.parent_type_args)
    body = formatter_generic_body(node, depth + 1)
    body == "" ? header : header + "\n" + body
  when :module_def
    body = formatter_sequence(node.body, depth + 1)
    prefix + "module " + node.name.to_s() + (body == "" ? "" : "\n" + body)
  when :trait_def
    body = formatter_generic_body(node, depth + 1)
    prefix + "trait " + node.name.to_s() + formatter_type_args(node.type_params) + (body == "" ? "" : "\n" + body)
  when :trait_include
    prefix + "is " + node.name.to_s() + formatter_type_args(node.trait_type_args)
  when :namespace_decl
    prefix + "in " + node.namespace.to_s()
  when :if
    formatter_if(node, depth)
  when :while
    prefix + "while " + formatter_expr(node.condition, depth) + "\n" + formatter_sequence(node.body, depth + 1)
  when :on_guard
    header = prefix + "on " + formatter_target(node.predicate)
    i = 0
    while i < node.capabilities.size
      header += " with " + node.capabilities[i].to_s()
      i += 1
    body = formatter_sequence(node.body, depth + 1)
    body == "" ? header : header + "\n" + body
  when :with
    bindings = []
    i = 0
    while i < node.bindings.size
      binding = node.bindings[i]
      bindings.push(formatter_expr(binding[0], depth) + " in " + formatter_expr(binding[1], depth))
      i += 1
    prefix + "with " + bindings.join(", ") + "\n" + formatter_sequence(node.body, depth + 1)
  when :case_value
    formatter_case_value(node, depth)
  when :case
    formatter_case(node, depth)
  when :begin
    out = prefix + "begin\n" + formatter_sequence(node.body, depth + 1)
    if node.rescue_body != nil && !node.rescue_body.empty?()
      out += "\n" + prefix + "rescue"
      if node.rescue_var != nil
        if type(node.rescue_var) == "String"
          out += " " + node.rescue_var
        else
          out += " " + formatter_expr(node.rescue_var, depth)
      out += "\n" + formatter_sequence(node.rescue_body, depth + 1)
    if node.ensure_body != nil && !node.ensure_body.empty?()
      out += "\n" + prefix + "ensure\n" + formatter_sequence(node.ensure_body, depth + 1)
    out
  when :return, :return_nil
    node.value == nil ? prefix + "return" : prefix + "return " + formatter_expr(node.value, depth)
  when :break
    prefix + "break"
  when :next
    prefix + "next"
  when :yield
    node.args.empty?() ? prefix + "yield" : prefix + "yield " + formatter_join_nodes(node.args, ", ", depth)
  when :go
    prefix + "go ->\n" + formatter_sequence(node.body, depth + 1)
  when :raise
    prefix + "raise " + formatter_expr(node.value, depth)
  else
    prefix + formatter_expr(node, depth)

-> format_tungsten_source(source, file = "(fmt)")
  masked = formatter_mask_comments(source, file)
  if masked == nil
    return formatter_lossless_whitespace(source)
  formatter_source = masked[:source]
  lexer = Lexer.new(formatter_source, file)
  token_count = lexer.tokenize()
  parser = Parser.new(token_count, lexer.packed_tokens, formatter_source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
  ast = parser.parse()
  formatted = formatter_sequence(ast.expressions, 0).rtrim() + "\n"
  formatter_restore_comments(formatted, masked[:comments])
