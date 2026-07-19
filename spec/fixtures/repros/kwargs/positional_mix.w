# Positional args and keyword args mix: positionals fill left-to-right —
# including into keyword slots (positional fill wins) — and the labels bind
# whatever keyword slots remain.
fn show(v)
  v == nil ? "~" : v.to_s()

+ Mixer
  -> new
    @x = 0
  -> mix(a, b, c: "C", d: "D")
    << "mix " + show(a) + "," + show(b) + "," + show(c) + "," + show(d)

m = Mixer.new
m.mix(1, 2, c: "x", d: "y")
m.mix(1, 2, d: "y")
m.mix(1, 2, "px", d: "y")
m.mix(1, 2)
m.mix(1, 2, "px", "pd")

# Only keywords, positionals missing entirely: slots stay nil-defaulted.
fn lone(a, b: 9)
  << "lone a=" + show(a) + " b=" + show(b)

lone(b: 2)
