use spec
use slim

describe Slim:Parser
  let(:parser) { Parser.new }

  describe "#parse"
    it "parses a doctype declaration"
      root = parser.parse("doctype html")
      expect(root.children.size).to eq(1)
      expect(root.children[0]).to be_a(Slim:Doctype)
      expect(root.children[0].type).to eq("html")

    it "parses a simple element"
      root = parser.parse("div")
      expect(root.children.size).to eq(1)
      expect(root.children[0]).to be_a(Slim:Element)
      expect(root.children[0].tag).to eq("div")

    it "parses an element with inline text"
      root = parser.parse("h1 \"Hello, world\"")
      node = root.children[0]
      expect(node.tag).to eq("h1")
      expect(node.text).to eq("Hello, world")

    it "parses ID shorthand"
      root = parser.parse("div#main")
      node = root.children[0]
      expect(node.tag).to eq("div")
      expect(node.id).to eq("main")

    it "parses class shorthand"
      root = parser.parse("div.container.wide")
      node = root.children[0]
      expect(node.tag).to eq("div")
      expect(node.classes).to eq(["container", "wide"])

    it "parses combined ID and classes"
      root = parser.parse("section#content.main.wide")
      node = root.children[0]
      expect(node.tag).to eq("section")
      expect(node.id).to eq("content")
      expect(node.classes).to eq(["main", "wide"])

    it "parses parenthesized attributes"
      root = parser.parse("a(href=\"/bits\" class=\"nav-link\")")
      node = root.children[0]
      expect(node.tag).to eq("a")
      expect(node.attributes["href"]).to eq("/bits")
      expect(node.attributes["class"]).to eq("nav-link")

    it "parses boolean attributes"
      root = parser.parse("input(type=\"email\" required)")
      node = root.children[0]
      expect(node.attributes["type"]).to eq("email")
      expect(node.attributes["required"]).to eq(true)

    it "parses code lines"
      root = parser.parse("- if @signed_in?")
      node = root.children[0]
      expect(node).to be_a(Slim:Code)
      expect(node.expression).to eq("if @signed_in?")

    it "parses output expressions"
      root = parser.parse("= @bit.name")
      node = root.children[0]
      expect(node).to be_a(Slim:Output)
      expect(node.expression).to eq("@bit.name")

    it "parses HTML comments"
      root = parser.parse("/ This is a comment")
      node = root.children[0]
      expect(node).to be_a(Slim:Comment)
      expect(node.text).to eq("This is a comment")

    it "parses literal text blocks"
      root = parser.parse("| This is literal text")
      node = root.children[0]
      expect(node).to be_a(Slim:Text)
      expect(node.value).to eq("This is literal text")

    it "parses shorthand div with class"
      root = parser.parse(".container")
      node = root.children[0]
      expect(node.tag).to eq("div")
      expect(node.classes).to eq(["container"])

    it "parses shorthand div with id"
      root = parser.parse("#header")
      node = root.children[0]
      expect(node.tag).to eq("div")
      expect(node.id).to eq("header")

    it "parses inline output on elements"
      root = parser.parse("h1 = @title")
      node = root.children[0]
      expect(node.tag).to eq("h1")
      expect(node.inline_output).to eq("@title")

  describe "nesting"
    it "parses nested elements by indentation"
      source = "div\n  h1 \"Title\"\n  p \"Body\""
      root = parser.parse(source)
      div = root.children[0]
      expect(div.tag).to eq("div")
      expect(div.children.size).to eq(2)
      expect(div.children[0].tag).to eq("h1")
      expect(div.children[1].tag).to eq("p")

    it "parses deeply nested structures"
      source = "html\n  head\n    title \"Test\"\n  body\n    div \"Content\""
      root = parser.parse(source)
      html = root.children[0]
      expect(html.children.size).to eq(2)

      head = html.children[0]
      expect(head.tag).to eq("head")
      expect(head.children[0].tag).to eq("title")

      body = html.children[1]
      expect(body.tag).to eq("body")
      expect(body.children[0].tag).to eq("div")

    it "skips blank lines"
      source = "div\n\n  p \"Text\""
      root = parser.parse(source)
      div = root.children[0]
      expect(div.children.size).to eq(1)
      expect(div.children[0].tag).to eq("p")

  describe "void elements"
    it "recognizes void tags"
      root = parser.parse("br")
      node = root.children[0]
      expect(node.void?).to eq(true)

    it "recognizes non-void tags"
      root = parser.parse("div")
      node = root.children[0]
      expect(node.void?).to eq(false)
