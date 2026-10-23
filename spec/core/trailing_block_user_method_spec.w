# A trailing block on a call of a block-taking user method reaches that
# method on both engines. The tree-walker only passed trailing blocks to a
# fixed list of iterator names (each, map, times, ...); any other name was
# treated as taking no block, so `Runner.run(5) -> (q)` ran `run` without a
# block ("no block given") and then iterated its result, and
# `Tempfile.create(...) -> (t)` / `File.open(...) -> (f)` yielded the
# handle's ivar names instead of the handle (2026-10-21). It now records the
# names of methods that declare `&` or use `yield` / `block?`, as lowering
# does, and passes the block to those.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

+ Runner
  -> .run(v)
    begin
      result = yield v
    ensure
      nil
    result

  -> twice(&block)
    block.call(1) + block.call(2)

  -> probe
    block? ? "block" : "none"

  -> listing
    [1, 2, 3]

-> with_scaled(v)
  yield v * 10

r = Runner.run(5) -> (q)
  q * 2
check("class method with yield", r, 10)

t = Runner.new.twice -> (k)
  k * 100
check("instance method with &block", t, 300)

p = Runner.new.probe -> (x)
  x
check("block? sees the block", p, "block")

s = with_scaled(4) -> (v)
  v + 1
check("top-level fn with yield", s, 41)

# A name no definition gives a block still iterates its result.
seen = []
Runner.new.listing -> (x)
  seen.push(x * 2)
check("blockless method iterates its result", seen, [2, 4, 6])

# Core methods that yield: Tempfile.create and File.open.
kept = nil
Tempfile.create("tungsten-trailing-block") -> (tmp)
  kept = tmp.path
  tmp.write("abc")
check("Tempfile.create yields the tempfile", kept != nil && !File.exist?(kept), true)
