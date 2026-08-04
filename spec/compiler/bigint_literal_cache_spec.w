# Compiled loop-local source literals wider than i64 publish one immutable
# BigInt template per emitted literal site.  Normal copied results may be
# returned concurrently and must still obey value semantics under compound
# assignment and explicit alias-visible bang methods.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> cached_literal
  value = 0 ## big
  i = 0 ## i64
  while i < 1
    value = 0x10000000000000000000000000000000000000000000000000000000000000000
    i += 1
  value

want = 1 << 256
check("literal.value", cached_literal(), want)
check("literal.repeated", cached_literal(), cached_literal())
check("literal.one_limb_value", 9223372036854775808, 1 << 63)

# Compound assignment may consume the binding, but never the immutable
# module literal or another binding that aliases it.
x = cached_literal()
alias_value = x
x += 1
check("literal.alias_unchanged", alias_value, want)
check("literal.compound_result", x, want + 1)
check("literal.cache_unchanged", cached_literal(), want)

y = cached_literal()
y *= 3
check("literal.mul_compound_result", y, want * 3)
check("literal.cache_after_mul", cached_literal(), want)

# BigInt bang methods intentionally mutate every alias of the receiver.  A
# cached source literal must therefore return an ordinary value copied from
# its pinned template, never the template itself.
z = cached_literal()
z_alias = z
z.neg!
check("literal.bang_alias_visible", z_alias, 0 - want)
check("literal.cache_after_bang", cached_literal(), want)

# Decimal, negative, binary, and octal over-u64 spellings all lower through
# the same cached-decimal representation and retain exact values.
check("literal.decimal", 340282366920938463463374607431768211456, 1 << 128)
check("literal.negative", -340282366920938463463374607431768211456, -(1 << 128))
check("literal.binary", 0b1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000, 1 << 192)
check("literal.octal", 0o10000000000000000000000000000000000000000000000000000000000000000, 1 << 192)

# Race the first-use publication for one literal site.  Every worker must see
# the same exact value; Thread.join also exercises cross-thread lifetime.
count = 8 ## i64
seen = i64[count]
workers = []
i = 0 ## i64
while i < count
  slot = i ## i64
  worker = Thread.new ->
    j = 0 ## i64
    value = 0 ## big
    while j < 1000
      value = cached_literal()
      j += 1
    seen[slot] = value % 1000000007
  workers.push(worker)
  i += 1

expected = want % 1000000007
i = 0
while i < count
  workers[i].join
  check("literal.thread_" + i.to_s(), seen[i], expected)
  i += 1

<< "bigint_literal_cache_spec: all checks passed"
