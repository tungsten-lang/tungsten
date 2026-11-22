# `go`, `fn` and `on` are contextual keywords: keywords only in their own
# forms (`go -> body`, `fn name(...)`, `on TARGET` + indented body) and
# ordinary identifiers everywhere else. The keyword forms must keep working
# beside locals, parameters and methods with those names.
# contextual_keyword_lexer_spec.w pins the token types, and
# spec/parity/{go_identifier,contextual_keywords}_spec.w the identifier uses
# on every engine.

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# `go ->` spawns as a statement and as an expression, beside a local named go
# that the spawned bodies read.
-> spawn_with_local_named_go
  ch = Channel.new(2)
  go = 20
  go ->
    ch.send(go + 1)
  task = go -> ch.send(go + 2)
  a = ch.recv()
  b = ch.recv()
  a + b

expect("go -> spawns beside a local named go", spawn_with_local_named_go() == 43)

-> go(x)
  x * 2

ch = Channel.new(1)
go -> ch.send(go(5) + go(go(1)))
expect("spawned body calls a function named go", ch.recv() == 14)

h = {go: 3}
ch2 = Channel.new(1)
go -> ch2.send(h[:go] * go(2))
expect("spawned body reads a go hash key", ch2.recv() == 12)

# `fn name` still defines a function next to a local named fn.
fn = 5
fn contextual_triple(x)
  x * 3
expect("fn definition beside a local named fn", contextual_triple(fn) == 15)

# `on TARGET` + body still guards, next to a local named on.
on = 0
on macos || linux || windows || wasm
  on = 1
on !(macos || linux || windows || wasm)
  on = 2
expect("on guard beside a local named on", on == 1)

+ ContextualLamp
  rw :on
  -> new(@on)
  -> fn(x)
    x + 1
  -> go(x)
    x + 2
lamp = ContextualLamp.new(false)
lamp.on = true
expect("attribute named on", lamp.on == true)
expect("methods named fn and go", lamp.fn(1) + lamp.go(1) == 5)
