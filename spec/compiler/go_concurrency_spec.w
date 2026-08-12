# go -> body concurrency spec.
# Tests that `go -> body` parses and compiles as a goroutine task launch.

ch = Channel.new(1)

go ->
  ch.send(42)

res = ch.recv()

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("go.goroutine_launch", res == 42)
