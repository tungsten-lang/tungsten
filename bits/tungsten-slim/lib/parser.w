# Slim::Parser — parses .slim source into a node tree
#
# Reads lines, tracks indentation depth, and produces an AST of Node objects.
# Handles tag shorthand (div.class#id), attributes, code, output, comments,
# doctype declarations, and literal text blocks.

in Tungsten:Slim

+ Parser
  # Regex patterns for line parsing
  TAG_PATTERN     = /^([a-zA-Z][a-zA-Z0-9]*)/
  ID_PATTERN      = /#([a-zA-Z_][a-zA-Z0-9_-]*)/
  CLASS_PATTERN   = /\.([a-zA-Z_][a-zA-Z0-9_-]*)/
  ATTR_PATTERN    = /\(([^)]*)\)/
  TEXT_PATTERN    = /\s+"(.*)"\s*$/
  OUTPUT_PATTERN  = /\s+=\s+(.+)$/

  -> new
    @line_number = 0

  # Parse a Slim template string into a Root node tree
  -> parse(source)
    @root = Root.new
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
      content.start_with?("doctype ") =>
        type = content.sub("doctype ", "").strip
        Doctype.new(type: type, line: @line_number)

      # HTML comment
      content.start_with?("/") =>
        text = content[1..].strip
        Comment.new(text: text.empty? ? nil : text, line: @line_number)

      # Code line (no output)
      content.start_with?("- ") =>
        expression = content[2..].strip
        Code.new(expression: expression, line: @line_number)

      # Output expression
      content.start_with?("= ") =>
        expression = content[2..].strip
        Output.new(expression: expression, line: @line_number)

      # Table row: | cell | cell | cell |
      content.match?(/^\|.*\|.*\|/) =>
        self.parse_table_row(content)

      # Literal text block
      content.start_with?("| ") =>
        text = content[2..]
        Text.new(value: text, line: @line_number)

      # Literal text (pipe with no space for empty lines)
      content == "|" =>
        Text.new(value: "", line: @line_number)

      # HTML element (starts with a letter, or with . or # for div shorthand)
      content.match?(/^[a-zA-Z]/) =>
        parse_element(content)

      # Shorthand div with class or id
      content.start_with?(".") || content.start_with?("#") =>
        parse_element("div" + content)

      # Anything else is plain text
      =>
        Text.new(value: content, line: @line_number)

  # Parse an element line: tag#id.class(attrs) "text" or tag = expr
  -> parse_element(content)
    remaining = content
    tag = nil
    id = nil
    classes = []
    attributes = {}
    text = nil
    inline_output = nil

    # Extract tag name
    if match = remaining.match(TAG_PATTERN)
      tag = match[1]
      remaining = remaining[match[0].size..]
    else
      tag = "div"

    # Extract ID shorthand (#id)
    while match = remaining.match(/^#([a-zA-Z_][a-zA-Z0-9_-]*)/)
      id = match[1]
      remaining = remaining[match[0].size..]

    # Extract class shorthands (.class)
    while match = remaining.match(/^\.([a-zA-Z_][a-zA-Z0-9_-]*)/)
      classes.push(match[1])
      remaining = remaining[match[0].size..]

    # Extract parenthesized attributes
    if match = remaining.match(/^\(([^)]*)\)/)
      attributes = parse_attributes(match[1])
      remaining = remaining[match[0].size..]

    # Check for inline output (tag = expression)
    if match = remaining.match(/^\s+=\s+(.+)$/)
      inline_output = match[1].strip

    # Check for inline text ("quoted text")
    elsif match = remaining.match(/^\s+"(.*)"\s*$/)
      text = match[1]

    # Check for unquoted inline text (after a space, not starting with special chars)
    elsif match = remaining.match(/^\s+([^"=\-\/|].*)$/)
      text = match[1].strip if match[1].strip.size > 0

    Element.new(
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
    remaining = attr_string.strip

    while remaining.size > 0
      # Match key="value" or key='value'
      if match = remaining.match(/^([a-zA-Z_][a-zA-Z0-9_-]*)\s*=\s*"([^"]*)"/)
        attrs[match[1]] = match[2]
        remaining = remaining[match[0].size..].strip

      elsif match = remaining.match(/^([a-zA-Z_][a-zA-Z0-9_-]*)\s*=\s*'([^']*)'/)
        attrs[match[1]] = match[2]
        remaining = remaining[match[0].size..].strip

      # Boolean attribute (no value)
      elsif match = remaining.match(/^([a-zA-Z_][a-zA-Z0-9_-]*)/)
        attrs[match[1]] = true
        remaining = remaining[match[0].size..].strip

      else
        break

    attrs

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
    is_header = parent.is_a?(Element) && parent.tag == "table" &&
                parent.children.none?(-> (c) c.is_a?(TableRow))

    TableRow.new(cells: cells, header: is_header, line: @line_number)

  # Measure leading whitespace of a line (number of spaces)
  -> measure_indent(line)
    count = 0
    line.each_char -> (ch)
      if ch == " "
        count = count + 1
      else
        << count
    count
