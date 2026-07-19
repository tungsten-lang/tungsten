# Carbide::Template specs — mustache-style compile-once/render-many
# view templates: {{name}} (escaped), {{{name}}} (raw), {{#if}}/{{#each}}
# blocks with {{this}}/{{this.field}}, nil on malformed source.
# Run: bin/tungsten bits/tungsten-carbide/spec/template_spec.w

use spec
use carbide

describe "Template" ->
  describe "interpolation" ->
    it "substitutes params values" ->
      t = Template.compile("Hello {{name}}!")
      expect(t.render({name: "World"})).to eq("Hello World!")

    it "renders a compiled template many times with different params" ->
      t = Template.compile("Hello {{name}}!")
      expect(t.render({name: "Ada"})).to eq("Hello Ada!")
      expect(t.render({name: "Grace"})).to eq("Hello Grace!")
      expect(t.render({})).to eq("Hello !")

    it "renders a missing value as empty" ->
      t = Template.compile("v={{v}}!")
      expect(t.render({})).to eq("v=!")
      expect(t.render({v: nil})).to eq("v=!")

    it "stringifies non-string values" ->
      t = Template.compile("n={{n}} b={{b}}")
      expect(t.render({n: 42, b: true})).to eq("n=42 b=true")

    it "ignores whitespace inside the tag" ->
      expect(Template.compile("{{ name }}").render({name: "x"})).to eq("x")

    it "passes literal text and lone braces through verbatim" ->
      expect(Template.compile("a { b } c").render({})).to eq("a { b } c")

  describe "escaping" ->
    it "HTML-escapes interpolated values by default" ->
      t = Template.compile("{{v}}")
      expect(t.render({v: "a<b>&\"c'"})).to eq("a&lt;b&gt;&amp;&quot;c&#39;")

    it "leaves triple-brace values raw" ->
      t = Template.compile("{{{v}}}")
      expect(t.render({v: "<b>hi</b>"})).to eq("<b>hi</b>")

    it "does not escape literal template text" ->
      t = Template.compile("<ul>{{v}}</ul>")
      expect(t.render({v: "x"})).to eq("<ul>x</ul>")

  describe "if blocks" ->
    it "renders the body when the value is true" ->
      t = Template.compile("A{{#if flag}}B{{/if}}C")
      expect(t.render({flag: true})).to eq("ABC")

    it "skips the body when the value is false" ->
      t = Template.compile("A{{#if flag}}B{{/if}}C")
      expect(t.render({flag: false})).to eq("AC")

    it "treats a missing value as falsy" ->
      t = Template.compile("A{{#if flag}}B{{/if}}C")
      expect(t.render({})).to eq("AC")

    it "treats any non-nil non-false value as truthy" ->
      t = Template.compile("A{{#if flag}}B{{/if}}C")
      expect(t.render({flag: "yes"})).to eq("ABC")
      expect(t.render({flag: 0})).to eq("ABC")

  describe "each blocks" ->
    it "renders the body once per element with {{this}}" ->
      t = Template.compile("{{#each xs}}<{{this}}>{{/each}}")
      expect(t.render({xs: ["a", "b"]})).to eq("<a><b>")

    it "reads hash element fields with {{this.field}}" ->
      t = Template.compile("{{#each xs}}{{this.name}};{{/each}}")
      expect(t.render({xs: [{name: "a"}, {name: "b"}]})).to eq("a;b;")

    it "renders nothing for an empty or missing array" ->
      t = Template.compile("A{{#each xs}}x{{/each}}B")
      expect(t.render({xs: []})).to eq("AB")
      expect(t.render({})).to eq("AB")

    it "escapes interpolated element values" ->
      t = Template.compile("{{#each xs}}{{this}}{{/each}}")
      expect(t.render({xs: ["a&b"]})).to eq("a&amp;b")

  describe "nesting" ->
    it "renders an if inside an each against element fields" ->
      t = Template.compile("{{#each xs}}{{#if this.hot}}{{this.name}}!{{/if}}{{/each}}")
      xs = [{name: "a", hot: true}, {name: "b", hot: false}, {name: "c", hot: true}]
      expect(t.render({xs: xs})).to eq("a!c!")

    it "still resolves outer params names inside an each" ->
      t = Template.compile("{{#each xs}}{{label}}{{this}} {{/each}}")
      expect(t.render({xs: ["1", "2"], label: "#"})).to eq("#1 #2 ")

  describe "malformed templates" ->
    # Contract: Template.compile returns NIL for a malformed source (no
    # exceptions — same both-engines convention as Model.find).
    it "returns nil for an unclosed block" ->
      expect(Template.compile("{{#if x}}oops")).to be_nil
      expect(Template.compile("{{#each xs}}oops")).to be_nil

    it "returns nil for an unterminated tag" ->
      expect(Template.compile("hi {{name")).to be_nil

    it "returns nil for a stray or mismatched close tag" ->
      expect(Template.compile("x{{/if}}")).to be_nil
      expect(Template.compile("{{#if x}}{{/each}}")).to be_nil

    it "returns nil for an empty or unknown tag" ->
      expect(Template.compile("a{{}}b")).to be_nil
      expect(Template.compile("{{#with x}}y{{/with}}")).to be_nil

spec_summary
