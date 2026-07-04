# Slim::Node — AST node types for parsed Slim templates
#
# The parser produces a tree of these nodes. The compiler walks the tree
# to generate HTML output.

in Tungsten:Slim

# Base node — all nodes have children and a line number
+ Node
  ro :children
  ro :line

  -> new(line: 0)
    @children = []
    @line = line

  -> add_child(node)
    @children.push(node)
    self

  -> leaf?
    @children.empty?

# Root node — top of the document tree
+ Root < Node
  -> new
    super(line: 0)

# HTML element node: div.class#id(attr="val") "text"
+ Element < Node
  ro :tag
  ro :id
  ro :classes
  ro :attributes
  ro :text
  ro :inline_output

  -> new(tag:, id: nil, classes: [], attributes: {}, text: nil, inline_output: nil, line: 0)
    super(line: line)
    @tag = tag
    @id = id
    @classes = classes
    @attributes = attributes
    @text = text
    @inline_output = inline_output

  # Self-closing tags that don't need a closing tag
  VOID_TAGS = [:area, :base, :br, :col, :embed, :hr, :img,
               :input, :link, :meta, :param, :source, :track, :wbr]

  -> void?
    VOID_TAGS.include?(@tag.to_sym)

# Plain text node
+ Text < Node
  ro :value

  -> new(value:, line: 0)
    super(line: line)
    @value = value

# Code node — Tungsten code that does not produce output (- lines)
+ Code < Node
  ro :expression

  -> new(expression:, line: 0)
    super(line: line)
    @expression = expression

# Output node — Tungsten expression whose result is inserted (= lines)
+ Output < Node
  ro :expression
  ro :escape

  -> new(expression:, escape: true, line: 0)
    super(line: line)
    @expression = expression
    @escape = escape

# HTML comment node (/ lines)
+ Comment < Node
  ro :text

  -> new(text: nil, line: 0)
    super(line: line)
    @text = text

# Doctype node (doctype html, doctype xml, etc.)
+ Doctype < Node
  ro :type

  -> new(type: "html", line: 0)
    super(line: line)
    @type = type

  -> to_s
    case @type
      "html"          => "<!DOCTYPE html>"
      "xml"           => "<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
      "5"             => "<!DOCTYPE html>"
      "1.1"           => "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
      "strict"        => "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
      "transitional"  => "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">"
      =>                 "<!DOCTYPE html>"

# Table row node — represents a | cell1 | cell2 | row inside a table element
+ TableRow < Node
  ro :cells
  ro :header

  -> new(cells:, header: false, line: 0)
    super(line: line)
    @cells = cells
    @header = header
