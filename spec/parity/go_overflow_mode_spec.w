## parity xfail the compiled engine cannot compile a statement-level `Math.wrap ->` block (compiler error "undefined method 'name' for Object (object/hash ...)", pre-existing); the interpreter wraps the goroutine's add
# `go` under `Math.wrap ->`: the lexical overflow mode reaches the
# goroutine's body, which runs after the block has been left (the
# interpreter captures the mode at the spawn, see interpreter/runtime.w
# spawn_goroutine; the compiled engine lowers the body inside the block).
# Split from go_concurrency_spec.w so that spec's channel transcript stays a
# live gate while statement-level Math.* blocks do not compile.
#
# Cross-engine parity spec (scripts/parity.sh).

wr = Channel.new(0)
Math.wrap ->
  go ->
    big = 9223372036854775807
    wr.send(big + 1)
<< "wrap in goroutine [wr.receive]"
