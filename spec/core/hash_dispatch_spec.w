# Public `hash` on builtin value receivers through a cached call site.
#
# The first `hash` call on a String, Symbol, Int or Float at a call site
# publishes a universal inline-cache row (runtime w_method_call_slow); later
# calls from that site take the cached handler instead of re-walking the
# dispatch cascade. The cached path must return exactly what the first
# (cascade) call returned, stay equal for equal values, and keep a user
# class's own `hash` method winning.
#
# Run:
#   bin/tungsten spec/core/hash_dispatch_spec.w
#   bin/tungsten run --interpret spec/core/hash_dispatch_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# One call site, called repeatedly: the first call populates the cache.
-> hash_of(v)
  v.hash

-> stable(v)
  a = hash_of(v)
  ok = true
  i = 0
  while i < 50
    ok = false if hash_of(v) != a
    i += 1
  ok

+ Keyed
  -> new(@k)
  -> hash
    42

check("string hash stable through the cache", stable("font-weight-xyz"))
check("short string hash stable", stable("abc"))
check("empty string hash stable", stable(""))
check("symbol hash stable", stable(:some_symbol))
check("int hash stable", stable(123456789))
check("float hash stable", stable(~14.5))
check("equal strings hash equal", hash_of("ab" + "cd") == hash_of("abcd"))
check("different strings differ", hash_of("abcd") != hash_of("abce"))
check("float equal values hash equal", hash_of(~1.5 + ~1.0) == hash_of(~2.5))
check("mixed receivers at one site", hash_of("x1y2z3") == "x1y2z3".hash && hash_of(~3.25) == (~3.25).hash && hash_of(7) == 7.hash)
check("user hash wins at a warmed site", hash_of(Keyed.new(1)) == 42)
check("public hash fits the inline Int tier", hash_of("a long string to hash") < 140737488355328)

<< "ALL PASS hash_dispatch_spec ([passed.load()] checks)"
