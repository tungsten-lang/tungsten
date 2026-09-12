# `Tungsten.noinline!` as the first statement of a fn or method body keeps
# that function out of line in emitted code (its own LLVM attribute group
# carries `noinline`) and is a no-op for the tree walker. The statement has
# no value and takes part in nothing else: the bodies below compute exactly
# as they would without it, on both engines.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

fn add_pair(a, b) (i64 i64) i64
  Tungsten.noinline!
  a + b

-> describe(n)
  Tungsten.noinline!
  if n > 3
    return "big"
  "small"

+ Counter
  -> new(@count)

  -> bump(by)
    Tungsten.noinline!
    @count += by
    @count

check("raw fn", add_pair(40, 2), 42)
check("raw fn twice", add_pair(add_pair(1, 2), 3), 6)
check("plain fn", describe(5), "big")
check("plain fn small", describe(1), "small")
counter = Counter.new(10)
check("method", counter.bump(5), 15)
check("method again", counter.bump(1), 16)

<< "noinline_directive_spec: all checks passed"
