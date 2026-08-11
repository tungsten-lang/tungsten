# Slim::Compiler — compiles a node tree into HTML output
#
# Walks the AST produced by the Parser and generates HTML strings.
# Handles indentation, attribute rendering, interpolation, and
# code evaluation via the provided binding context.

in Tungsten:Slim

+ Compiler
  -> new(pretty: true)
    @pretty = pretty
    @indent_level = 0

  # Compile a Root node tree into an HTML string
  -> compile(root, locals = {})
    @locals = locals
    @output = StringBuffer()

    root.children.each -> (node)
      compile_node(node)

    @output.to_s

  # Dispatch to the appropriate compile method for each node type
  -> compile_node(node)
    if node.is_a?(Tungsten:Slim:Doctype)
      compile_doctype(node)
    elsif node.is_a?(Tungsten:Slim:Element)
      compile_element(node)
    elsif node.is_a?(Tungsten:Slim:Text)
      compile_text(node)
    elsif node.is_a?(Tungsten:Slim:Code)
      compile_code(node)
    elsif node.is_a?(Tungsten:Slim:Output)
      compile_output(node)
    elsif node.is_a?(Tungsten:Slim:Comment)
      compile_comment(node)
    elsif node.is_a?(Tungsten:Slim:TableRow)
      compile_table_row(node)
    else
      raise "Unknown Slim node type at line " + node.line.to_s

  # Compile a doctype declaration
  -> compile_doctype(node)
    write_line(node.to_s)

  # Compile an HTML element with its attributes, text, and children
  -> compile_element(node)
    # Build opening tag
    tag = node.tag
    attr_str = Tungsten:Slim:Helpers.element_attributes(node)
    opening = if attr_str.empty?
      "<[tag]>"
    else
      "<[tag] [attr_str]>"

    if node.void?
      # Self-closing tags
      void_tag = if attr_str.empty?
        "<[tag]>"
      else
        "<[tag] [attr_str]>"
      write_line(void_tag)

    elsif node.text
      # Inline text: <tag>text</tag> on one line
      text = interpolate(node.text)
      write_line("[opening][text]</[tag]>")

    elsif node.inline_output
      # Inline output: <tag>#{expression}</tag>
      value = evaluate(node.inline_output)
      escaped = Tungsten:Slim:Helpers.escape_html(value.to_s)
      write_line("[opening][escaped]</[tag]>")

    elsif node.leaf?
      # Empty element: <tag></tag>
      write_line("[opening]</[tag]>")

    elsif tag == "table" && node.children.any?(-> (c) c.is_a?(Tungsten:Slim:TableRow))
      # Table with table row children — auto-wrap in thead/tbody
      self.compile_table_element(node, opening, tag, attr_str)

    else
      # Element with children — indent and recurse
      write_line(opening)
      @indent_level = @indent_level + 1
      node.children.each -> (child)
        compile_node(child)
      @indent_level = @indent_level - 1
      write_line("</[tag]>")

  # Compile a plain text node
  -> compile_text(node)
    text = interpolate(node.value)
    write_line(text)

  # Compile a code node (control flow — no output)
  -> compile_code(node)
    expr = node.expression

    # Handle control structures that have children
    case
      expr.starts_with?("if ") || expr.starts_with?("unless ") =>
        evaluate_conditional(node)

      expr.include?(".each ") =>
        evaluate_iteration(node)

      =>
        evaluate(expr)

  # Compile an output node — evaluate and insert result
  -> compile_output(node)
    value = evaluate(node.expression)
    text = if node.escape
      Tungsten:Slim:Helpers.escape_html(value.to_s)
    else
      value.to_s
    write_line(text)

  # Compile a table element with automatic thead/tbody wrapping
  -> compile_table_element(node, opening, tag, attr_str)
    write_line(opening)
    @indent_level = @indent_level + 1

    header_rows = node.children.select(-> (c) c.is_a?(Tungsten:Slim:TableRow) && c.header)
    body_rows   = node.children.select(-> (c) c.is_a?(Tungsten:Slim:TableRow) && !c.header)
    other       = node.children.reject(-> (c) c.is_a?(Tungsten:Slim:TableRow))

    # Compile non-table-row children first
    other.each -> (child)
      compile_node(child)

    # Thead
    if header_rows.any?
      write_line("<thead>")
      @indent_level = @indent_level + 1
      header_rows.each -> (row)
        compile_table_row(row)
      @indent_level = @indent_level - 1
      write_line("</thead>")

    # Tbody
    if body_rows.any?
      write_line("<tbody>")
      @indent_level = @indent_level + 1
      body_rows.each -> (row)
        compile_table_row(row)
      @indent_level = @indent_level - 1
      write_line("</tbody>")

    @indent_level = @indent_level - 1
    write_line("</[tag]>")

  # Compile a table row node into <tr><th>...</th></tr> or <tr><td>...</td></tr>
  -> compile_table_row(node)
    cell_tag = if node.header then "th" else "td"
    cells_html = node.cells.map(-> (cell) "<[cell_tag]>[interpolate(cell)]</[cell_tag]>").join("")
    write_line("<tr>[cells_html]</tr>")

  # Compile an HTML comment
  -> compile_comment(node)
    if node.text
      write_line("<!-- [node.text] -->")
    elsif node.children.any?
      write_line("<!--")
      @indent_level = @indent_level + 1
      node.children.each -> (child)
        compile_node(child)
      @indent_level = @indent_level - 1
      write_line("-->")
    else
      write_line("<!-- -->")

  # --- Control flow helpers ---

  # Evaluate an if/unless/else conditional block
  -> evaluate_conditional(node)
    expr = node.expression
    condition = if expr.starts_with?("if ")
      expr.slice(3, expr.size - 3)
    else
      expr.slice(7, expr.size - 7)
    negate = expr.starts_with?("unless ")

    result = evaluate(condition)
    result = !result if negate

    if result
      node.children.each -> (child)
        # Skip 'else' code nodes — they're the alternative branch
        if child.is_a?(Tungsten:Slim:Code) && child.expression == "else"
          << nil
        compile_node(child)

  # Evaluate an .each iteration block
  -> evaluate_iteration(node)
    # Parse: collection.each -> (item)
    expr = node.expression
    parts = expr.split(".each")
    collection_expr = parts[0].strip
    collection = evaluate(collection_expr)

    # Extract the block parameter name
    param_name = "item"
    marker = expr.index("-> (")
    if marker != nil
      tail = expr.slice(marker + 4, expr.size - marker - 4)
      close = tail.index(")")
      param_name = tail.slice(0, close) if close != nil

    collection.each -> (item)
      prev = @locals[param_name.to_sym]
      @locals[param_name.to_sym] = item
      node.children.each -> (child)
        compile_node(child)
      @locals[param_name.to_sym] = prev

  # --- Output helpers ---

  # Write a line to the output buffer with current indentation
  -> write_line(text)
    if @pretty
      @output << Tungsten:Slim:Helpers.indent(@indent_level)
      @output << text
      @output << "\n"
    else
      @output << text

  # Interpolate [expression] references in text strings
  -> interpolate(text)
    out = ""
    rest = text
    start = rest.index("\[")
    while start != nil
      out = out + rest.slice(0, start)
      tail = rest.slice(start + 1, rest.size - start - 1)
      close = tail.index("\]")
      if close == nil
        return out + rest.slice(start, rest.size - start)
      expr = tail.slice(0, close)
      out = out + evaluate(expr).to_s
      rest = tail.slice(close + 1, tail.size - close - 1)
      start = rest.index("\[")
    out + rest

  # Evaluate a Tungsten expression in the current locals context
  -> evaluate(expression)
    expr = expression.strip
    key = expr
    key = expr.slice(1, expr.size - 1) if expr.starts_with?("@")
    symbol_key = key.to_sym
    if @locals.key?(symbol_key)
      return @locals[symbol_key]
    if @locals.key?(key)
      return @locals[key]
    return true if expr == "true"
    return false if expr == "false"
    return nil if expr == "nil"
    raise "Unknown Slim local: " + expression
