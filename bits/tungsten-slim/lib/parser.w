# Slim::Parser — parses .slim source into a node tree
#
# Reads lines, tracks indentation depth, and produces an AST of Node objects.
# Handles tag shorthand (div.class#id), attributes, code, output, comments,
# doctype declarations, and literal text blocks.

in Tungsten:Slim

+ Parser
  -> new
    @line_number = 0

  # Parse a Slim template string into a Root node tree
  -> parse(source)
    @root = Tungsten:Slim:Root.new
    @stack = [{node: @root, indent: -1}]
    @line_number = 0

    lines = source.split("\n")
    index = 0

    while index < lines.size
      line = lines[index]
      @line_number = index + 1

      # Skip completely blank lines
      if line.strip.empty?
        index = index + 1
        next

      indent = measure_indent(line)
      content = line.strip

      # Parse the line into a node
      node = parse_line(content)

      if node
        # Pop stack back to the correct parent depth
        while @stack.size > 1 && @stack.last[:indent] >= indent
          @stack.pop

        # Add node as child of current parent
        @stack.last[:node].add_child(node)

        # Push this node onto the stack as a potential parent
        @stack.push({node: node, indent: indent})

      index = index + 1

    @root

  # Parse a single line of Slim content into the appropriate node type
  -> parse_line(content)
    case
      # Doctype declaration
      content.starts_with?("doctype ") =>
        type = content.slice(8, content.size - 8).strip
        Tungsten:Slim:Doctype.new(type: type, line: @line_number)

      # HTML comment
      content.starts_with?("/") =>
        text = content.slice(1, content.size - 1).strip
        Tungsten:Slim:Comment.new(text: text.empty? ? nil : text, line: @line_number)

      # Code line (no output)
      content.starts_with?("- ") =>
        expression = content.slice(2, content.size - 2).strip
        Tungsten:Slim:Code.new(expression: expression, line: @line_number)

      # Output expression
      content.starts_with?("= ") =>
        expression = content.slice(2, content.size - 2).strip
        Tungsten:Slim:Output.new(expression: expression, line: @line_number)

      # Table row: | cell | cell | cell |
      content.starts_with?("|") && content.split("|").size > 3 =>
        self.parse_table_row(content)

      # Literal text block
      content.starts_with?("| ") =>
        text = content.slice(2, content.size - 2)
        Tungsten:Slim:Text.new(value: text, line: @line_number)

      # Literal text (pipe with no space for empty lines)
      content == "|" =>
        Tungsten:Slim:Text.new(value: "", line: @line_number)

      # HTML element (starts with a letter, or with . or # for div shorthand)
      element_start?(content) =>
        parse_element(content)

      # Shorthand div with class or id
      content.starts_with?(".") || content.starts_with?("#") =>
        parse_element("div" + content)

      # Anything else is plain text
      =>
        Tungsten:Slim:Text.new(value: content, line: @line_number)

  # Parse an element line: tag#id.class(attrs) "text" or tag = expr
  -> parse_element(content)
    remaining = content
    tag = nil
    id = nil
    classes = []
    attributes = {}
    text = nil
    inline_output = nil

    pos = 0
    if element_start?(remaining)
      while pos < remaining.size && identifier_char?(remaining.slice(pos, 1))
        pos = pos + 1
      tag = remaining.slice(0, pos)
    else
      tag = "div"

    while pos < remaining.size && (remaining.slice(pos, 1) == "#" || remaining.slice(pos, 1) == ".")
      marker = remaining.slice(pos, 1)
      pos = pos + 1
      start = pos
      while pos < remaining.size && identifier_char?(remaining.slice(pos, 1))
        pos = pos + 1
      value = remaining.slice(start, pos - start)
      if marker == "#"
        id = value
      else
        classes.push(value)

    if pos < remaining.size && remaining.slice(pos, 1) == "("
      close = remaining.index(")")
      if close
        attributes = parse_attributes(remaining.slice(pos + 1, close - pos - 1))
        pos = close + 1

    tail = remaining.slice(pos, remaining.size - pos).strip
    if tail.starts_with?("= ")
      inline_output = tail.slice(2, tail.size - 2).strip
    elsif tail.size >= 2 && tail.slice(0, 1) == "\"" && tail.slice(tail.size - 1, 1) == "\""
      text = tail.slice(1, tail.size - 2)
    elsif tail.size > 0
      text = tail

    Tungsten:Slim:Element.new(
      tag: tag,
      id: id,
      classes: classes,
      attributes: attributes,
      text: text,
      inline_output: inline_output,
      line: @line_number
    )

  # Parse attribute string: key="value" key="value" ...
  -> parse_attributes(attr_string)
    attrs = {}
    attr_string.split(" ").each -> (part)
      eq = part.index("=")
      if eq
        name = part.slice(0, eq)
        value = part.slice(eq + 1, part.size - eq - 1)
        if value.size >= 2
          quote = value.slice(0, 1)
          if (quote == "\"" || quote == "'") && value.slice(value.size - 1, 1) == quote
            value = value.slice(1, value.size - 2)
        attrs[name] = value
      else
        attrs[part] = true

    attrs

  -> element_start?(text)
    return false if text.size == 0
    ch = text.slice(0, 1)
    (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z")

  -> identifier_char?(ch)
    element_start?(ch) || (ch >= "0" && ch <= "9") || ch == "_" || ch == "-"

  # Parse a table row: | cell1 | cell2 | cell3 |
  # First row under a `table` element becomes a header row
  -> parse_table_row(content)
    # Split on | and strip whitespace from each cell
    parts = content.split("|")
    # Remove empty first/last from leading/trailing |
    cells = parts.select(-> (p) p.strip.size > 0).map(-> (p) p.strip)

    # Determine if this is a header row:
    # First | row under a table parent is treated as <thead>
    parent = @stack.last[:node]
    is_header = (parent.is_a?(Tungsten:Slim:Element) && parent.tag == "table" &&
      parent.children.none?(-> (c) c.is_a?(Tungsten:Slim:TableRow)))

    Tungsten:Slim:TableRow.new(cells: cells, header: is_header, line: @line_number)

  # Measure leading whitespace of a line (number of spaces)
  -> measure_indent(line)
    count = 0
    line.chars.each -> (ch)
      if ch == " "
        count = count + 1
      else
        return count
    count
