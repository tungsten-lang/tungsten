# Slim::Parser — parses .slim source into a node tree
#
# Reads lines, tracks indentation depth, and produces an AST of Node objects.
# Handles tag shorthand (div.class#id), attributes, code, output, comments,
# doctype declarations, and literal text blocks.

in Tungsten:Slim

+ Parser
  ro :line_number
  ro :root
  ro :stack

  -> new
    @line_number = 0
    @root = nil
    @stack = nil

  # Parse a Slim template string into a Root node tree
  -> parse(source)
    @root = Tungsten:Slim:Root.new
    @stack = [{node: @root, indent: -1}]
    @line_number = 0

    lines = source.split("\n")
    nlines = lines.size
    index = 0

    while index < nlines
      line = lines[index]
      @line_number = index + 1
      content = line.strip

      # Skip completely blank lines
      if content.empty?
        index = index + 1
        next

      indent = measure_indent(line)

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
    b0 = content.byte_at(0)

    # Fast path for HTML elements (starts with a letter) and doctype
    if (b0 >= 97 && b0 <= 122) || (b0 >= 65 && b0 <= 90)
      if b0 == 100 && content.starts_with?("doctype ")
        type = content.slice(8, content.size - 8).strip
        return Tungsten:Slim:Doctype.new(type: type, line: @line_number)
      return parse_element(content)

    # Shorthand div with class or id
    if b0 == 46 || b0 == 35
      return parse_element("div" + content)

    case
      # HTML comment
      b0 == 47 =>
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

      # Literal text / table row starting with |
      b0 == 124 =>
        if content == "|"
          Tungsten:Slim:Text.new(value: "", line: @line_number)
        elsif content.index("|", 1) != nil && content.split("|").size > 3
          self.parse_table_row(content)
        elsif content.starts_with?("| ")
          text = content.slice(2, content.size - 2)
          Tungsten:Slim:Text.new(value: text, line: @line_number)
        else
          Tungsten:Slim:Text.new(value: content, line: @line_number)

      # Anything else is plain text
      =>
        Tungsten:Slim:Text.new(value: content, line: @line_number)

  # Parse an element line: tag#id.class(attrs) "text" or tag = expr
  -> parse_element(content)
    remaining = content
    n = remaining.size
    tag = nil
    id = nil
    classes = []
    attributes = {}
    text = nil
    inline_output = nil

    pos = 0
    if n > 0 && element_start_byte?(remaining.byte_at(0))
      pos = 1
      while pos < n && identifier_byte?(remaining.byte_at(pos))
        pos = pos + 1
      tag = remaining.slice(0, pos)
    else
      tag = "div"

    while pos < n
      mb = remaining.byte_at(pos)
      break if mb != 35 && mb != 46
      pos = pos + 1
      start = pos
      while pos < n && identifier_byte?(remaining.byte_at(pos))
        pos = pos + 1
      value = remaining.slice(start, pos - start)
      if mb == 35
        id = value
      else
        classes.push(value)

    if pos < n && remaining.byte_at(pos) == 40
      close = remaining.index(")")
      if close
        attributes = parse_attributes(remaining.slice(pos + 1, close - pos - 1))
        pos = close + 1

    if pos < n
      tail = remaining.slice(pos, n - pos).strip
      tsize = tail.size
      if tsize > 0
        if tail.starts_with?("= ")
          inline_output = tail.slice(2, tsize - 2).strip
        elsif tsize >= 2 && tail.byte_at(0) == 34 && tail.byte_at(tsize - 1) == 34
          text = tail.slice(1, tsize - 2)
        else
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
    parts = attr_string.split(" ")
    n = parts.size
    i = 0
    while i < n
      part = parts[i]
      if part.size > 0
        eq = part.index("=")
        if eq
          name = part.slice(0, eq)
          value = part.slice(eq + 1, part.size - eq - 1)
          vsize = value.size
          if vsize >= 2
            q0 = value.byte_at(0)
            if (q0 == 34 || q0 == 39) && value.byte_at(vsize - 1) == q0
              value = value.slice(1, vsize - 2)
          attrs[name] = value
        else
          attrs[part] = true
      i = i + 1

    attrs

  -> element_start_byte?(b)
    (b >= 97 && b <= 122) || (b >= 65 && b <= 90)

  -> identifier_byte?(b)
    (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 95 || b == 45

  -> element_start?(text)
    return false if text.size == 0
    element_start_byte?(text.byte_at(0))

  -> identifier_char?(ch)
    return false if ch.size == 0
    identifier_byte?(ch.byte_at(0))

  # Parse a table row: | cell1 | cell2 | cell3 |
  # First row under a `table` element becomes a header row
  -> parse_table_row(content)
    # Split on | and strip whitespace from each cell
    parts = content.split("|")
    # Remove empty first/last from leading/trailing |
    cells = []
    i = 0
    while i < parts.size
      s = parts[i].strip
      if s.size > 0
        cells.push(s)
      i = i + 1

    # Determine if this is a header row:
    # First | row under a table parent is treated as <thead>
    parent = @stack.last[:node]
    is_header = (parent.is_a?(Tungsten:Slim:Element) && parent.tag == "table" &&
      parent.children.none?(-> (c) c.is_a?(Tungsten:Slim:TableRow)))

    Tungsten:Slim:TableRow.new(cells: cells, header: is_header, line: @line_number)

  # Measure leading whitespace of a line (number of spaces)
  -> measure_indent(line)
    count = 0
    n = line.size
    while count < n && line.byte_at(count) == 32
      count = count + 1
    count
