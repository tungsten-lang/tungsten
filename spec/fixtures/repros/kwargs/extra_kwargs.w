# Leftover labels: labels that do not name a declared keyword param form a
# residual hash placed at the first free non-keyword slot (exactly as if a
# trailing hash had been passed); when every slot is taken they are dropped.
fn show(v)
  v == nil ? "~" : v.to_s()

# No keyword params at all: whole group -> first free slot.
fn plain(a, b)
  << "plain a=" + show(a) + " b=" + show(b)

plain(a: 1, b: 2)

# Keyword param consumed, stray label -> residual into the free positional slot.
+ Box
  -> new
    @x = 0
  -> fill(slot, depth: 1)
    << "fill slot=" + show(slot) + " depth=" + show(depth)

b = Box.new
b.fill(stray: 9, depth: 3)
b.fill("s1", depth: 2, stray: 7)
