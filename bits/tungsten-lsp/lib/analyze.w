# Source analysis for Tungsten LSP
#
# AST-based analysis using the Tungsten lexer and parser.
# Provides: symbols, hover, definition, references, signature help,
# completion, and cross-file resolution via use-path following.

# LSP SymbolKind constants
SK_METHOD   = 6
SK_CLASS    = 5
SK_MODULE   = 2
SK_FUNCTION = 12
SK_TRAIT    = 11

# -- Project index & single-entry parse/lines caches --
# Maps file paths to their parsed AST and extracted definitions.

project_index = {}
parse_cache = {}

-> text_lines(text)
  if parse_cache[:lines_text] == text && parse_cache[:lines] != nil
    return parse_cache[:lines]
  lines = text.split("\n")
  parse_cache[:lines_text] = text
  parse_cache[:lines] = lines
  lines

-> index_file(path, text)
  ast = parse_source(text, path)
  return nil if ast == nil

  defs = []
  collect_defs(ast, defs)
  project_index[path] = {ast: ast, defs: defs, text: text}
  defs

-> index_from_uri(uri, text)
  path = uri_to_path(uri)
  return nil if path == nil
  index_file(path, text)

-> ensure_indexed(uri, text)
  path = uri_to_path(uri)
  return nil if path == nil
  if project_index[path] == nil
    index_file(path, text)
  project_index[path]

# -- Use-path resolution --

-> resolve_use_path(use_path, from_file)
  base = dirname(from_file)
  candidate = base + "/" + use_path + ".w"
  return candidate if file?(candidate)

  # Try lib/ from project root
  root = __project_root
  if root != nil
    lib_path = root + "/lib/" + use_path + ".w"
    return lib_path if file?(lib_path)
  nil

-> dirname(path)
  idx = path.size - 1
  while idx >= 0
    if path.byte_at(idx) == 47
      return path.slice(0, idx)
    idx -= 1
  "."

-> index_dependencies(text, from_file)
  # Scan for use statements and index those files
  lines = text_lines(text)
  i = 0
  n = lines.size
  while i < n
    stripped = lines[i].strip
    if stripped.starts_with?("use ")
      use_path = stripped.slice(4, stripped.size - 4).strip
      resolved = resolve_use_path(use_path, from_file)
      if resolved != nil && project_index[resolved] == nil && file?(resolved)
        dep_text = read_file(resolved)
        index_file(resolved, dep_text)
        index_dependencies(dep_text, resolved)
    i += 1

# -- Parse source safely --

-> parse_source(text, filename = "buffer.w")
  # Current lexer/parser API: packed tokens + a 7-arg Parser (mirrors how the
  # compiler itself lexes/parses — see compiler/lib/loader.w). NON-RAISING:
  # returns nil on a lex/parse error so indexing/hover/definition degrade
  # gracefully on a malformed buffer instead of crashing the server (callers
  # already guard `if ast == nil`). diagnose() does its own raising parse to
  # capture the error. (The old single-arg `Parser(tokens)` left every ivar nil
  # and crashed in sync_current.)
  if parse_cache[:text] == text && parse_cache[:file] == filename && parse_cache[:ast] != nil
    return parse_cache[:ast]
  entry = project_index[filename]
  if entry != nil && entry[:text] == text && entry[:ast] != nil
    parse_cache[:text] = text
    parse_cache[:file] = filename
    parse_cache[:ast] = entry[:ast]
    return entry[:ast]
  result = nil
  begin
    lexer = Lexer.new(text, filename)
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, text, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    result = parser.parse().expressions
    parse_cache[:text] = text
    parse_cache[:file] = filename
    parse_cache[:ast] = result
  rescue err
    result = nil
  result

# -- Definition collection --

-> collect_defs(nodes, defs)
  return nil if type(nodes) != "Array"
  i = 0
  n = nodes.size
  while i < n
    collect_def(nodes[i], defs)
    i += 1

-> collect_def(node, defs)
  return nil if !is_ast_node?(node)

  n = ast_kind(node)

  if n == :method_def || n == :fn_def
    defs.push(node)
  elsif n == :class_def || n == :module_def
    defs.push(node)
    body = ast_get(node, :body)
    collect_defs(body, defs) if body != nil

# -- Symbol extraction (LSP documentSymbol) --

-> extract_symbols(text)
  ast = parse_source(text)
  return [] if ast == nil

  symbols = []
  collect_symbols(ast, symbols)
  symbols

-> collect_symbols(nodes, symbols)
  return nil if type(nodes) != "Array"
  i = 0
  n = nodes.size
  while i < n
    collect_symbol(nodes[i], symbols)
    i += 1

-> collect_symbol(node, symbols)
  return nil if !is_ast_node?(node)

  n = ast_kind(node)

  if n == :method_def
    name = ast_get(node, :name)
    line = node_line(node)
    symbols.push(lsp_symbol(name, SK_METHOD, line, 0, name.size))
    body = ast_get(node, :body)
    collect_symbols(body, symbols) if body != nil

  elsif n == :fn_def
    name = ast_get(node, :name)
    line = node_line(node)
    symbols.push(lsp_symbol(name, SK_FUNCTION, line, 0, name.size))

  elsif n == :class_def
    name = ast_get(node, :name)
    line = node_line(node)
    symbols.push(lsp_symbol(name, SK_CLASS, line, 0, name.size))
    body = ast_get(node, :body)
    collect_symbols(body, symbols) if body != nil

  elsif n == :module_def
    name = ast_get(node, :name)
    line = node_line(node)
    symbols.push(lsp_symbol(name, SK_MODULE, line, 0, name.size))
    body = ast_get(node, :body)
    collect_symbols(body, symbols) if body != nil

# -- Workspace symbols (LSP workspace/symbol) --

-> workspace_symbols(query)
  results = []
  paths = project_index.keys
  pi = 0
  pn = paths.size
  while pi < pn
    path = paths[pi]
    entry = project_index[path]
    if entry != nil && entry[:defs] != nil
      defs = entry[:defs]
      di = 0
      dn = defs.size
      while di < dn
        defn = defs[di]
        name = ast_get(defn, :name)
        if query == "" || name.include?(query)
          line = node_line(defn)
          kind = def_kind(defn)
          results.push(lsp_workspace_symbol(name, kind, path, line))
        di += 1
    pi += 1
  results

-> def_kind(node)
  n = ast_kind(node)
  return SK_METHOD if n == :method_def
  return SK_FUNCTION if n == :fn_def
  return SK_CLASS if n == :class_def
  return SK_MODULE if n == :module_def
  SK_METHOD

-> lsp_workspace_symbol(name, kind, path, line)
  {
    "name": name,
    "kind": kind,
    "location": {
      "uri": "file://" + path,
      "range": {
        "start": {"line": line, "character": 0},
        "end": {"line": line, "character": name.size}
      }
    }
  }

# -- Hover (LSP textDocument/hover) --

-> hover_info(text, line, col, uri)
  word = word_at_line(text, line, col)
  return nil if word == nil

  defn = find_def_anywhere(word, uri, text)
  return nil if defn == nil

  format_signature(defn)

# -- Go to definition (LSP textDocument/definition) --
# Searches current file first, then indexed dependencies.

-> find_definition(text, line, col, uri)
  word = word_at_line(text, line, col)
  return nil if word == nil

  # Search current file
  ast = parse_source(text)
  if ast != nil
    defn = find_def_node(ast, word)
    if defn != nil
      def_line = node_line(defn)
      return {"uri": uri, "line": def_line, "col": 0, "end_col": word.size}

  # Search dependencies
  path = uri_to_path(uri)
  if path != nil
    paths = project_index.keys
    pi = 0
    pn = paths.size
    while pi < pn
      dep_path = paths[pi]
      if dep_path != path
        entry = project_index[dep_path]
        if entry != nil && entry[:defs] != nil
          defs = entry[:defs]
          di = 0
          dn = defs.size
          while di < dn
            defn = defs[di]
            if ast_get(defn, :name) == word
              def_line = node_line(defn)
              return {"uri": "file://" + dep_path, "line": def_line, "col": 0, "end_col": word.size}
            di += 1
      pi += 1
  nil

# -- Find references (LSP textDocument/references) --

-> find_references(text, line, col, uri)
  word = word_at_line(text, line, col)
  return [] if word == nil

  refs = []
  wlen = word.size

  # Search current file line by line
  lines = text_lines(text)
  li = 0
  ln_count = lines.size
  while li < ln_count
    ln = lines[li]
    ln_size = ln.size
    ci = 0
    while ci < ln_size
      idx = ln.index(word, ci)
      if idx == nil
        ci = ln_size
      else
        # Check it's a word boundary
        before_ok = idx == 0 || !is_word_byte?(ln.byte_at(idx - 1))
        after_idx = idx + wlen
        after_ok = after_idx >= ln_size || !is_word_byte?(ln.byte_at(after_idx))
        if before_ok && after_ok
          refs.push({"uri": uri, "line": li, "col": idx, "end_col": after_idx})
        ci = after_idx
    li += 1
  refs

# -- Signature help (LSP textDocument/signatureHelp) --

-> signature_help(text, line, col, uri)
  # Walk backwards from cursor to find the function name before (
  ln = text_lines(text)
  return nil if line >= ln.size

  the_line = ln[line]
  return nil if col == 0

  # Find the opening ( before cursor
  paren_pos = col - 1
  paren_pos = the_line.size - 1 if paren_pos >= the_line.size
  depth = 0
  while paren_pos >= 0
    b = the_line.byte_at(paren_pos)
    if b == 41
      depth += 1
    elsif b == 40
      if depth == 0
        name_end = paren_pos
        name_start = name_end - 1
        while name_start >= 0 && is_word_byte?(the_line.byte_at(name_start))
          name_start -= 1
        name_start += 1
        if name_start < name_end
          fname = the_line.slice(name_start, name_end - name_start)
          defn = find_def_anywhere(fname, uri, text)
          if defn != nil
            return format_signature_help(defn)
        return nil
      else
        depth -= 1
    paren_pos -= 1
  nil

-> format_signature_help(node)
  label = "-> " + ast_get(node, :name)
  param_labels = []
  param_objs = []
  params = ast_get(node, :params)
  if params != nil && params.size > 0
    label = label + "("
    pi = 0
    pn = params.size
    while pi < pn
      p = params[pi]
      pname = nil
      if is_ast_node?(p)
        pname = ast_get(p, :name).to_s
      else
        pname = p.to_s
      param_labels.push(pname)
      param_objs.push({"label": pname})
      pi += 1
    label = label + param_labels.join(", ") + ")"

  {
    "signatures": [{
      "label": label,
      "parameters": param_objs
    }],
    "activeSignature": 0,
    "activeParameter": 0
  }

# -- Completion (LSP textDocument/completion) --

-> complete(text, line, col, uri)
  # Collect all known symbols from current file and dependencies
  items = []
  seen = {}

  ast = parse_source(text)
  if ast != nil
    add_completions(ast, items, seen)

  # Add from indexed dependencies
  paths = project_index.keys
  pi = 0
  pn = paths.size
  while pi < pn
    path = paths[pi]
    entry = project_index[path]
    if entry != nil && entry[:defs] != nil
      defs = entry[:defs]
      di = 0
      dn = defs.size
      while di < dn
        defn = defs[di]
        name = ast_get(defn, :name)
        if seen[name] == nil
          seen[name] = true
          kind = completion_kind(defn)
          items.push({"label": name, "kind": kind})
        di += 1
    pi += 1
  items

-> add_completions(nodes, items, seen)
  return nil if type(nodes) != "Array"
  i = 0
  cnt = nodes.size
  while i < cnt
    node = nodes[i]
    if is_ast_node?(node)
      n = ast_kind(node)
      if n == :method_def || n == :fn_def
        name = ast_get(node, :name)
        if seen[name] == nil
          seen[name] = true
          kind = completion_kind(node)
          items.push({"label": name, "kind": kind, "detail": signature_detail(node)})
      if n == :class_def || n == :module_def
        name = ast_get(node, :name)
        if seen[name] == nil
          seen[name] = true
          items.push({"label": name, "kind": 7})  # 7 = Class
        body = ast_get(node, :body)
        add_completions(body, items, seen) if body != nil
    i += 1

-> completion_kind(node)
  n = ast_kind(node)
  return 3 if n == :fn_def       # Function
  return 2 if n == :method_def   # Method
  return 7 if n == :class_def    # Class
  return 9 if n == :module_def   # Module
  2

-> signature_detail(node)
  params = ast_get(node, :params)
  return nil if params == nil || params.size == 0
  names = []
  pi = 0
  pn = params.size
  while pi < pn
    p = params[pi]
    if is_ast_node?(p)
      names.push(ast_get(p, :name).to_s)
    else
      names.push(p.to_s)
    pi += 1
  "(" + names.join(", ") + ")"

# -- Diagnostics (LSP textDocument/publishDiagnostics) --

-> diagnose(text, uri)
  # Parse the buffer; the lexer/parser raise a structured compile-error hash
  # ({rt: :compile_error, row:, col:, message:, span_length:}) on the first
  # error. Convert it to an LSP diagnostic. Bare rescue keeps a malformed
  # buffer from ever crashing the long-lived server. An empty result clears
  # any previously-published diagnostics once the buffer parses cleanly.
  diagnostics = []
  begin
    lexer = Lexer.new(text, "buffer.w")
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, text, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    parser.parse()
  rescue err
    d = diagnostic_from_error(err, text, uri)
    diagnostics.push(d) if d != nil
  diagnostics

-> diagnostic_from_error(err, text = nil, uri = nil)
  # Compiler rows/cols are 1-based; LSP positions are 0-based.
  line0 = 0
  char0 = 0
  span = 1
  msg = "syntax error"
  if type(err) == "Hash"
    line0 = err[:row] - 1 if err[:row] != nil
    char0 = err[:col] - 1 if err[:col] != nil
    span = err[:span_length] if err[:span_length] != nil
    msg = err[:message].to_s if err[:message] != nil
  else
    msg = err.to_s
  line0 = 0 if line0 < 0
  char0 = 0 if char0 < 0
  span = 1 if span < 1

  out = {
    "range": {
      "start": {"line": line0, "character": char0},
      "end": {"line": line0, "character": char0 + span}
    },
    "severity": 1,
    "source": "tungsten",
    "message": msg
  }
  if type(err) == "Hash" && err[:code] != nil
    out["code"] = err[:code].to_s

  # Build human-centric code frame and agent-centric payload if text is available
  if text != nil
    lines = text_lines(text)
    if line0 < lines.size
      src_line = lines[line0]
      caret_pad = ""
      k = 0
      while k < char0 && k < src_line.size
        caret_pad += (src_line.byte_at(k) == 9 ? "\t" : " ")
        k += 1
      caret_len = span
      caret_len = src_line.size - char0 if char0 + caret_len > src_line.size
      caret_len = 1 if caret_len < 1
      carets = "^" * caret_len

      line_num_str = (line0 + 1).to_s
      code_frame = line_num_str + " | " + src_line + "\n" + (" " * line_num_str.size) + " | " + caret_pad + carets
      out["code_frame"] = code_frame
      out["agent_payload"] = {
        "uri": uri,
        "line": line0 + 1,
        "column": char0 + 1,
        "span": span,
        "message": msg,
        "frame": code_frame,
        "code": type(err) == "Hash" && err[:code] != nil ? err[:code].to_s : "E_SYNTAX"
      }

  out

# -- Cross-file helpers --

-> find_def_anywhere(name, uri, text)
  # Current file first
  ast = parse_source(text)
  if ast != nil
    defn = find_def_node(ast, name)
    return defn if defn != nil

  # Then dependencies
  paths = project_index.keys
  pi = 0
  pn = paths.size
  while pi < pn
    path = paths[pi]
    entry = project_index[path]
    if entry != nil && entry[:defs] != nil
      defs = entry[:defs]
      di = 0
      dn = defs.size
      while di < dn
        defn = defs[di]
        return defn if ast_get(defn, :name) == name
        di += 1
    pi += 1
  nil

-> find_def_node(nodes, name)
  return nil if type(nodes) != "Array"
  i = 0
  cnt = nodes.size
  while i < cnt
    node = nodes[i]
    if is_ast_node?(node)
      n = ast_kind(node)
      if (n == :method_def || n == :fn_def) && ast_get(node, :name) == name
        return node
      if n == :class_def || n == :module_def
        body = ast_get(node, :body)
        if body != nil
          result = find_def_node(body, name)
          return result if result != nil
    i += 1
  nil

-> format_signature(node)
  out = StringBuffer(0)
  out << "```tungsten\n-> " + ast_get(node, :name)
  params = ast_get(node, :params)

  if params != nil && params.size > 0
    out << "("
    pi = 0
    pn = params.size
    while pi < pn
      p = params[pi]
      out << ", " if pi > 0
      if is_ast_node?(p)
        out << ast_get(p, :name).to_s
      else
        out << p.to_s
      pi += 1
    out << ")"
  out + "\n```"

# -- Shared helpers --

-> node_line(node)
  # Slab AST nodes carry source position in a packed :loc slot; `.line` unboxes
  # it (1-based, or nil if the kind has no :loc). LSP lines are 0-based.
  return 0 if !is_ast_node?(node)
  l = node.line
  return l - 1 if l != nil
  0

-> lsp_symbol(name, kind, line, start_col, end_col)
  {
    "name": name,
    "kind": kind,
    "range": {
      "start": {"line": line, "character": start_col},
      "end": {"line": line, "character": end_col}
    },
    "selectionRange": {
      "start": {"line": line, "character": start_col},
      "end": {"line": line, "character": end_col}
    }
  }

-> uri_to_path(uri)
  return uri.slice(7, uri.size - 7) if uri.starts_with?("file://")
  nil

-> word_at_line(text, line, col)
  lines = text_lines(text)
  return nil if line >= lines.size
  word_at(lines[line], col)

-> word_at(line, col)
  len = line.size
  return nil if col >= len
  left = col

  while left > 0 && is_word_byte?(line.byte_at(left - 1))
    left -= 1

  right = col

  while right < len && is_word_byte?(line.byte_at(right))
    right += 1

  return nil if left == right

  line.slice(left, right - left)

-> is_word_byte?(b)
  return true if b >= 97 && b <= 122
  return true if b >= 65 && b <= 90
  return true if b >= 48 && b <= 57
  b == 95 || b == 63 || b == 33

-> is_word_char?(ch)
  return true if ch >= "a" && ch <= "z"
  return true if ch >= "A" && ch <= "Z"
  return true if ch >= "0" && ch <= "9"

  ch == "_" || ch == "?" || ch == "!"
