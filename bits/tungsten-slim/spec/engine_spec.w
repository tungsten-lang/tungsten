use spec
use slim

describe Slim:Engine
  let(:engine) { Engine.new }

  describe "#render"
    it "renders a doctype"
      result = engine.render("doctype html")
      expect(result.strip).to eq("<!DOCTYPE html>")

    it "renders a simple element"
      result = engine.render("div")
      expect(result.strip).to eq("<div></div>")

    it "renders an element with inline text"
      result = engine.render("h1 \"Hello\"")
      expect(result.strip).to eq("<h1>Hello</h1>")

    it "renders nested elements"
      source = "div\n  p \"Hello\""
      result = engine.render(source)
      expect(result).to include("<div>")
      expect(result).to include("<p>Hello</p>")
      expect(result).to include("</div>")

    it "renders element with ID"
      result = engine.render("div#main")
      expect(result.strip).to eq("<div id=\"main\"></div>")

    it "renders element with classes"
      result = engine.render("div.container.wide")
      expect(result.strip).to eq("<div class=\"container wide\"></div>")

    it "renders element with attributes"
      result = engine.render("a(href=\"/bits\" target=\"_blank\") \"Browse\"")
      expect(result.strip).to eq("<a href=\"/bits\" target=\"_blank\">Browse</a>")

    it "renders void elements without closing tag"
      result = engine.render("br")
      expect(result.strip).to eq("<br>")

    it "renders void elements with attributes"
      result = engine.render("meta(charset=\"UTF-8\")")
      expect(result.strip).to eq("<meta charset=\"UTF-8\">")

    it "renders HTML comments"
      result = engine.render("/ TODO: fix this")
      expect(result.strip).to eq("<!-- TODO: fix this -->")

    it "renders literal text"
      result = engine.render("| Just some text")
      expect(result.strip).to eq("Just some text")

    it "renders output expressions"
      result = engine.render("= @name", {name: "Tungsten"})
      expect(result.strip).to eq("Tungsten")

    it "renders inline output on elements"
      result = engine.render("h1 = @title", {title: "Hello"})
      expect(result.strip).to eq("<h1>Hello</h1>")

    it "escapes HTML in output expressions"
      result = engine.render("= @content", {content: "<script>alert('xss')</script>"})
      expect(result.strip).to eq("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")

    it "renders boolean attributes"
      result = engine.render("input(type=\"email\" required)")
      expect(result.strip).to eq("<input type=\"email\" required>")

  describe "interpolation"
    it "interpolates variables in text"
      result = engine.render("p \"Hello, [name]\"", {name: "world"})
      expect(result.strip).to eq("<p>Hello, world</p>")

    it "interpolates expressions in text"
      result = engine.render("title \"[page] — Tungsten\"", {page: "Bits"})
      expect(result.strip).to eq("<title>Bits — Tungsten</title>")

  describe "full template"
    it "renders a complete HTML document"
      source = "doctype html\nhtml\n  head\n    title \"Test\"\n  body\n    h1 \"Hello\""
      result = engine.render(source)
      expect(result).to include("<!DOCTYPE html>")
      expect(result).to include("<html>")
      expect(result).to include("<title>Test</title>")
      expect(result).to include("<h1>Hello</h1>")
      expect(result).to include("</html>")

    it "renders a navbar structure"
      source = "nav.navbar\n  a.brand(href=\"/\") \"Home\"\n  ul.nav-links\n    li\n      a(href=\"/bits\") \"Browse\""
      result = engine.render(source)
      expect(result).to include("<nav class=\"navbar\">")
      expect(result).to include("<a class=\"brand\" href=\"/\">Home</a>")
      expect(result).to include("<ul class=\"nav-links\">")
      expect(result).to include("<a href=\"/bits\">Browse</a>")
