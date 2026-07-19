# Kwargs plus a trailing block: the closure the caller appends after the
# kwargs group must still land in the block slot (the entry remap
# right-aligns post-group args), and the keyword params bind by name.
+ Runner
  -> new
    @n = 0
  -> run(x, scale: 10)
    yield(x * scale)
    "ran"

# NOTE: `r.run(2) -> (v) …` (block + defaulted param, NO kwargs) is a
# PRE-EXISTING compiled gap unrelated to kwargs: the caller-appended closure
# lands in the defaulted slot (probed with a plain `scale = 10` too). The
# kwargs entry remap right-aligns the closure correctly, so the kwargs+block
# shape below works on both engines.
r = Runner.new
r.run(3, scale: 100) -> (v)
  << "block saw " + v.to_s()
r.run(4, scale: 2) -> (v)
  << "block saw " + v.to_s()
<< "done"
