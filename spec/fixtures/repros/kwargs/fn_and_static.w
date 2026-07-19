# Keyword binding is identical across the compiled call paths: top-level fn
# (direct known-fn call), class method (direct static path), and dynamic
# method dispatch — and across both engines.
fn show(v)
  v == nil ? "~" : v.to_s()

fn greet(name, greeting: "hello", punct: "!")
  << "fn " + greeting + " " + name + punct

greet("wren")
greet("wren", punct: "?")
greet("wren", greeting: "yo", punct: ".")

+ Maker
  -> .build(kind, size: "M", color: "none")
    << "static " + kind + " size=" + show(size) + " color=" + show(color)
  -> new
    @k = 0
  -> tag(label, prefix: ">")
    << "dyn " + prefix + label

Maker.build("chair")
Maker.build("chair", color: "red")
Maker.build("chair", color: "red", size: "XL")
mk = Maker.new
mk.tag("a")
mk.tag("b", prefix: "#")
