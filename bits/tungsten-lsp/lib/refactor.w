# Refactoring uses the compiler's tokens and binding structure. Interned Var
# nodes deliberately have no occurrence locations, so token ranges are admitted
# only when their count agrees with AST variable occurrences in one lexical
# function scope. Ambiguous/capturing syntax is refused, never text-replaced.

-> refactor_range(line, first, last)
  {"start": {"line": line, "character": first}, "end": {"line": line, "character": last}}

-> refactor_tokens(text)
  lexer = Lexer.new(text, "refactor.w")
  count = lexer.tokenize()
  chars = lexer.chars
  columns = []
  column = 0
  ci = 0
  while ci < chars.size()
    columns.push(column)
    ch = chars[ci]
    if ch == "\n"
      column = 0
    else
      column += ch.ord() > 65535 ? 2 : 1
    ci += 1
  columns.push(column)
  rows = []
  i = 0
  while i < count
    packed = lexer.packed_tokens[i]
    kind = parser_tok_type(packed)
    off = parser_tok_off(packed)
    length = parser_tok_len(packed)
    if !(kind in (T_SP T_NEWLINE T_INDENT T_DEDENT T_EOF))
      rows.push({kind: kind, value: lexer.values[i], off: off, length: length,
        line: lexer.line_at[off] - 1, col: columns[off], end_col: columns[off + length]})
    i += 1
  rows

-> refactor_scope_facts(value, old_name, new_name, facts)
  if value == nil
    return nil
  if type(value) == "Array"
    i = 0
    while i < value.size()
      refactor_scope_facts(value[i], old_name, new_name, facts)
      i += 1
    return nil
  if !is_ast_node?(value)
    return nil
  kind = ast_kind(value)
  if kind in (:block :go :fn_def :method_def :class_def :module_def :trait_def :string_interp :byte_array_interp :hash_literal :parallel_with)
    facts[:safe] = false
  if kind == :var
    name = ast_get(value, :name)
    if name == old_name
      facts[:references] = facts[:references] + 1
    if new_name != nil && name == new_name
      facts[:safe] = false
  if kind == :call && ast_get(value, :receiver) == nil && new_name != nil && ast_get(value, :name) == new_name
    facts[:safe] = false
  children = ast_children(value)
  i = 0
  while i < children.size()
    refactor_scope_facts(children[i], old_name, new_name, facts)
    i += 1
  nil

-> refactor_parameter_plan(text, line, col, new_name = nil)
  ast = parse_source(text)
  if ast == nil || line < 0 || col < 0
    return {error: "Rename requires a valid source buffer and position"}
  tokens = refactor_tokens(text)
  selected = nil
  ti = 0
  while ti < tokens.size()
    token = tokens[ti]
    if token[:kind] == T_ID && token[:line] == line && token[:col] <= col && col < token[:end_col]
      selected = token
    ti += 1
  if selected == nil
    return {error: "Select an explicit positional parameter or one of its references"}
  old_name = selected[:value]
  if new_name != nil
    proposed = refactor_tokens(new_name)
    if proposed.size() != 1 || proposed[0][:kind] != T_ID || proposed[0][:value] != new_name || new_name == ""
      return {error: "The new name must be one valid Tungsten identifier"}
  defs = []
  collect_defs(ast, defs)
  di = 0
  while di < defs.size()
    defn = defs[di]
    if ast_kind(defn) in (:fn_def :method_def)
      start_line = node_line(defn)
      start_col = defn.col - 1
      end_line = text.split("\n").size()
      ti = 0
      while ti < tokens.size()
        token = tokens[ti]
        if token[:line] > start_line && token[:col] <= start_col
          end_line = token[:line]
          break
        ti += 1
      if start_line <= line && line < end_line
        params = ast_get(defn, :params)
        parameter = nil
        pi = 0
        while params != nil && pi < params.size()
          param = params[pi]
          if ast_get(param, :name) == old_name
            parameter = param
          elsif new_name != nil && ast_get(param, :name) == new_name
            return {error: "The new name would collide with another parameter"}
          pi += 1
        if parameter != nil
          hints = ast_get(defn, :type_hints)
          if hints != nil && hints.has_key?(old_name)
            return {error: "Name-bound type hints must be updated together with their parameter"}
          if ast_get(parameter, :keyword) == true || ast_get(parameter, :ivar_assign) == true || ast_get(parameter, :splat) == true || ast_get(parameter, :block_param) == true || ast_get(parameter, :default) != nil
            return {error: "This parameter changes a public name or has a non-local binding contract"}
          facts = {safe: true, references: 0}
          refactor_scope_facts(ast_get(defn, :body), old_name, new_name, facts)
          edits = []
          signature_open = false
          previous = nil
          ti = 0
          while ti < tokens.size()
            token = tokens[ti]
            if token[:line] >= start_line && token[:line] < end_line
              if token[:line] == start_line && token[:kind] == T_LPAREN
                signature_open = true
              if token[:kind] == T_TYPE_HINT && token[:value] != nil && token[:value].to_s().include?(old_name)
                facts[:safe] = false
              if token[:kind] == T_STRING_INTERP || (token[:kind] == T_STRING && token[:value] != nil && token[:value].to_s().include?("\["))
                facts[:safe] = false
              if token[:kind] == T_ID && token[:value] == old_name && (token[:line] > start_line || signature_open)
                if previous == nil || !(previous[:kind] in (T_DOT T_COLON))
                  edits.push({"range": refactor_range(token[:line], token[:col], token[:end_col]), "newText": new_name})
              previous = token
            ti += 1
          if !facts[:safe] || edits.size() != facts[:references] + 1
            return {error: "Rename is ambiguous in this scope (capture, interpolation, shorthand, or name collision)"}
          selected_range = refactor_range(selected[:line], selected[:col], selected[:end_col])
          # A same-spelled property must not select the parameter's binding.
          selected_edit = false
          ei = 0
          while ei < edits.size()
            range = edits[ei]["range"]
            if range["start"]["line"] == line && range["start"]["character"] <= col && col < range["end"]["character"]
              selected_edit = true
            ei += 1
          if selected_edit
            return {name: old_name, range: selected_range, edits: edits}
    di += 1
  {error: "Rename currently supports explicit positional parameters within one unambiguous function scope"}

-> refactor_duplicate_imports(text, uri, version, first_line, last_line)
  ast = parse_source(text)
  if ast == nil
    return []
  imports = {}
  i = 0
  while i < ast.size()
    node = ast[i]
    if ast_kind(node) == :use
      imports[ast_get(node, :path)] = true
    i += 1
  seen = {}
  actions = []
  lines = text.split("\n")
  i = 0
  while i < lines.size()
    line = lines[i]
    if line.starts_with?("use ")
      path = line.slice(4, line.size() - 4).strip()
      if imports[path] == true
        if seen[path] == true && first_line <= i && i <= last_line
          end_pos = i + 1 < lines.size() ? {"line": i + 1, "character": 0} : {"line": i, "character": line.size()}
          edit = {"range": {"start": {"line": i, "character": 0}, "end": end_pos}, "newText": ""}
          actions.push({"title": "Remove duplicate import " + path, "kind": "quickfix",
            "edit": {"documentChanges": [{"textDocument": {"uri": uri, "version": version}, "edits": [edit]}]}})
        seen[path] = true
    i += 1
  actions
