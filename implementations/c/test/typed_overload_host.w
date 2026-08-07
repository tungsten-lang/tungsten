# Typed-overload dispatch in the C bytecode VM (stage-0 host).
#
# Same-name/same-arity methods that differ only in the declared param
# type must select by argument value at call time:
#   - named-param form:  -> combine(other)(BigInt) vs (Number)
#   - arity-suffix form: -> pick/1(BigInt) vs (Number)
# "BigInt" matches an integer that does not fit the inline i48 payload
# (heap-boxed in this VM); "Number" matches any numeric value. The BigInt
# arm must win on a >i48 value because BigInt is the more specific type —
# `order` declares the Number arm FIRST to prove specificity beats
# declaration order. `relay` exercises the implicit-self dispatch site
# (bare sibling call, method IC) with alternating argument types.
#
# Run:
#   TUNGSTEN_LEX64_TABLE=languages/tungsten/tungsten.lex64 \
#     implementations/c/build/tungsten-c implementations/c/test/typed_overload_host.w
# Expected output:
#   number-arm
#   bigint-arm
#   num
#   big
#   num
#   big
#   num
#   general-first
#   specific-wins
+ TypedHost
  -> new
    nil

  -> combine(other)(BigInt)
    "bigint-arm"

  -> combine(other)(Number)
    "number-arm"

  -> pick/1(BigInt)
    "big"

  -> pick/1(Number)
    "num"

  -> order(other)(Number)
    "general-first"

  -> order(other)(BigInt)
    "specific-wins"

  -> relay(x)
    pick(x)

host = TypedHost.new
small = 5
big = 1 << 50

puts host.combine(small)
puts host.combine(big)
puts host.pick(small)
puts host.pick(big)
puts host.relay(small)
puts host.relay(big)
puts host.relay(small)
puts host.order(small)
puts host.order(big)
