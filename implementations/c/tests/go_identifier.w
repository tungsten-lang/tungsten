# `go` is a keyword only where it starts a spawn (`go -> body`); everywhere
# else it is an ordinary identifier. No spawn here: the bootstrap VM runs
# this fixture too, and spec/parity/go_identifier_spec.w reuses it.

# A top-level function named go.
-> go(x)
  x + 100
<< go(5)
<< go(go(1))

# Locals, compound assignment and expressions, in a scope of their own.
-> locals
  go = 1
  << go
  go += 2
  << go * 10 + go
  << (go > 2 ? "big" : "small")
  [go, go + 1].size + go
<< locals()

# A parameter.
-> twice(go)
  go * 2
<< twice(21)

# A method named go, an attribute named go, and `obj.go` calls.
+ Pump
  rw :go
  -> new(@go)
  -> go_twice
    self.go + @go
  -> spin(n)
    self.go = n
    self.go
p = Pump.new(5)
<< p.go
<< p.go_twice
<< p.spin(8)

+ Engine
  -> go(n)
    n * 3
<< Engine.new.go(4)

# A hash key, symbol and string.
h = {go: 7, stop: 8}
<< h[:go]
<< :go
<< "go"
