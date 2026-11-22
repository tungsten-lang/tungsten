# `go` is a contextual keyword: reserved only where it starts a spawn,
# `go -> body`, and an ordinary identifier everywhere else. The spawn form
# must keep working beside locals and functions named go.
# go_contextual_keyword_lexer_spec.w pins the token types, and
# spec/parity/go_identifier_spec.w the identifier uses on every engine.

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
