# `fn` and `on` (like `go`, see go_identifier.w) are keywords only in their
# own forms, `fn name(...)` and `on TARGET` + indented body; everywhere
# else they are ordinary identifiers. spec/parity/contextual_keywords_spec.w
# reuses this fixture on the other engines.

# Locals.
on = 1
fn = 6
<< on + fn
on += 1
<< on * fn

# Parameters.
-> pause(on)
  on ? "paused" : "running"
<< pause(true)
-> scale(fn, on)
  fn * on
<< scale(3, 4)

# An attribute named on, methods named fn and on.
+ Switch
  rw :on
  -> new(@on)
  -> fn(x)
    x + 1
  -> flip
    self.on = !self.on
    self.on
sw = Switch.new(false)
sw.on = true
<< sw.on
<< sw.flip
<< sw.fn(1)

# Hash keys and symbols.
h = {on: 1, fn: 2}
<< h[:on] + h[:fn]
<< :on
<< :fn

# The keyword forms still work beside them.
fn twice(x)
  x * 2
<< twice(fn)
guarded = "no"
on macos || linux || windows || wasm
  guarded = "yes"
<< guarded
