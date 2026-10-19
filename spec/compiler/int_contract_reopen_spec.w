# spec: compiled -- exercises the integer-release gate in compiler/lib/lowering/analysis.w
# Integer releases (compiler/lib/ownership.w) assume core Integer semantics: an
# arithmetic result is fresh or a shared-marked operand.  A program that
# reopens BigInt#* to hand back a value it keeps elsewhere breaks that, so
# integer_contract_reopened? turns the releases off for the whole module.  If
# it did not, every `x * x` below would release the cached BigInt.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

cache_box = [2037035976334486086268445688409378161051468393665936250636140449354381299763336706183397377]

+ BigInt
  -> *(other)(BigInt)
    cache_box[0]

-> run(n, x)
  acc = 0
  y = 0
  i = 0
  while i < n
    acc += 1 if x * x + 1 > 0
    y = x * x
    i += 1
  [acc, y]

r = run(1000, 2037035976334486086268445688409378161051468393665936250636140449354381299763336706183397377)
check("the loop ran with the reopened operator", r[0] == 1000)
check("the cached BigInt is intact", cache_box[0].to_s() == "2037035976334486086268445688409378161051468393665936250636140449354381299763336706183397377")
check("and so is the value the loop kept", r[1].to_s() == cache_box[0].to_s())
<< "int_contract_reopen_spec: all checks passed"
