# Closure arity safety, 3-/4-arg yield & local closure calls, and sibling
# loop/block parameter scope isolation.

-> check(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> run_no_arg(&)
  yield

-> run_one_arg(v, &)
  yield v

-> run_three_args(a, b, c, &)
  yield a, b, c

-> run_four_args(a, b, c, d, &)
  yield a, b, c, d

# 1. Implicit free-var block called with 0 args must raise cleanly, not segfault
undef_raised = false
begin
  run_no_arg() ->
    x = "[ab]*"
    x
rescue err
  undef_raised = true
check("implicit undef free var raises cleanly", undef_raised)

# 2. Explicit params called with fewer args pad missing params with nil
r1 = run_no_arg() -> (a)
  a == nil
check("explicit 1-param block called with 0 args pads nil", r1)

r2 = run_one_arg(7) -> (a, b, c)
  a == 7 && b == nil && c == nil
check("explicit 3-param block called with 1 arg pads nil", r2)

# 3. 3-arg and 4-arg yield and local closure calls
s3 = run_three_args(10, 20, 30) -> (a, b, c)
  a + b + c
check("3-arg yield", s3 == 60)

s4 = run_four_args(1, 2, 3, 4) -> (a, b, c, d)
  a * 1000 + b * 100 + c * 10 + d
check("4-arg yield", s4 == 1234)

add3 = -> (a, b, c) a + b + c
add4 = -> (a, b, c, d) a + b + c + d
check("3-arg local closure call", add3(4, 5, 6) == 15)
check("4-arg local closure call", add4(4, 5, 6, 7) == 22)

# 4. Closure#arity preserves 0 for implicit blocks and N for explicit blocks
-> capture_block(&blk)
  blk
imp = capture_block() ->
  x + 1
check("implicit block arity is 0", imp.arity == 0)
check("implicit block call with 1 arg works", imp.call(41) == 42)
check("explicit 3-param block arity is 3", add3.arity == 3)

# 5. Sibling range.each / with-loop does not leak param type into subsequent array.each
-> test_sibling_loops
  modes = [nil]
  (6...9).each -> (mode)
    modes.push(mode)
  out = []
  modes.each -> (mode)
    out.push([1].select(-> (x) x == 1).size)
  out.size

check("sibling range.each then array.each with inner lambda", test_sibling_loops() == 4)

-> test_sibling_with_then_array_each
  modes = [nil]
  with mode in 6...9
    modes.push(mode)
  nil_count = 0
  modes.each -> (mode)
    if mode == nil
      nil_count += 1
  nil_count

check("sibling with-loop then array.each sees nil", test_sibling_with_then_array_each() == 1)

# 6. Dynamic Array#each destructuring with multi-param block
-> dynamic_each_pairs(items)
  total = 0
  items.each -> (k, v)
    total += k * 10 + v
  total

check("dynamic array.each destructuring", dynamic_each_pairs([[1, 2], [3, 4]]) == 46)
