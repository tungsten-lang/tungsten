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
    @output = StringIO.new

    root.children.each -> (node)
      compile_node(node)

    @output.string

  # Dispatch to the appropriate compile method for each node type
  -> compile_node(node)
    case node
      Doctype  => compile_doctype(node)
      Element  => compile_element(node)
      Text     => compile_text(node)
      Code     => compile_code(node)
      Output   => compile_output(node)
      Comment  => compile_comment(node)
      TableRow => compile_table_row(node)
      =>          <! CompileError, "Unknown node type at line [node.line]"

  # Compile a doctype declaration
  -> compile_doctype(node)
    write_line(node.to_s)

  # Compile an HTML element with its attributes, text, and children
  -> compile_element(node)
    # Build opening tag
    tag = node.tag
    attr_str = Helpers.element_attributes(node)
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
      escaped = Helpers.escape_html(value.to_s)
      write_line("[opening][escaped]</[tag]>")

    elsif node.leaf?
      # Empty element: <tag></tag>
      write_line("[opening]</[tag]>")

    elsif tag == "table" && node.children.any?(-> (c) c.is_a?(TableRow))
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
      expr.start_with?("if ") || expr.start_with?("unless ") =>
        evaluate_conditional(node)

      expr.match?(/\.each\s/) =>
        evaluate_iteration(node)

      =>
        evaluate(expr)

  # Compile an output node — evaluate and insert result
  -> compile_output(node)
    value = evaluate(node.expression)
    text = if node.escape
      Helpers.escape_html(value.to_s)
    else
      value.to_s
    write_line(text)

  # Compile a table element with automatic thead/tbody wrapping
  -> compile_table_element(node, opening, tag, attr_str)
    write_line(opening)
    @indent_level = @indent_level + 1

    header_rows = node.children.select(-> (c) c.is_a?(TableRow) && c.header)
    body_rows   = node.children.select(-> (c) c.is_a?(TableRow) && !c.header)
    other       = node.children.reject(-> (c) c.is_a?(TableRow))

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
    cells_html = node.cells.map(-> (cell)
      interpolated = interpolate(cell)
      "<[cell_tag]>[interpolated]</[cell_tag]>"
    ).join("")
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
    condition = expr.sub(/^(if|unless)\s+/, "")
    negate = expr.start_with?("unless ")

    result = evaluate(condition)
    result = !result if negate

    if result
      node.children.each -> (child)
        # Skip 'else' code nodes — they're the alternative branch
        if child.is_a?(Code) && child.expression == "else"
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
    param_match = expr.match(/-> \((\w+)\)/)
    param_name = param_match ? param_match[1] : "item"

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
      @output.write(Helpers.indent(@indent_level))
      @output.write(text)
      @output.write("\n")
    else
      @output.write(text)

  # Interpolate [expression] references in text strings
  -> interpolate(text)
    text.gsub(/\[([^\]]+)\]/) -> (match, expr)
      value = evaluate(expr)
      value.to_s

  # Evaluate a Tungsten expression in the current locals context
  -> evaluate(expression)
    Evaluator.eval(expression, @locals)
