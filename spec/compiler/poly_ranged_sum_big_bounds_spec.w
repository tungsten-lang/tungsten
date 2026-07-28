# Closed-form ranged sum (lowering/pipeline_fusion.w + poly_sum.w): the
# Faulhaber fold of `range/Σ(P(x))` must be EXACT for range bounds past
# 2^48, and must fire whether the range sits literally at the pipeline base
# or comes from a variable bound to one.
#
# Two regressions live here:
#
#   1. Both bounds were unboxed with the 48-bit `nanunbox_int` shortcut, so a
#      bound above 2^48 (a boxed bigint WValue) was silently TRUNCATED and the
#      fold returned a wrapped answer. Every bound under 2^48 looked correct,
#      which is what let it hide. Fixed by routing the bounds through
#      w_range_bound_i64, as the sibling `:count` closed form already did.
#
#   2. `r = (lo..hi)` materialized the range as a real array (an O(N) push
#      loop) even when every use of `r` folded to closed form, so the compiled
#      program was O(N) despite emitting the O(1) fold. Fixed by eliding the
#      materialization when every use is an elidable position. At the bounds
#      used here the old push loop could not finish at all, so these cases
#      completing IS the coverage.
#
# Expected values are exact integers computed out-of-band with Python's
# arbitrary-precision ints via Newton's forward-difference identity
#   sum_{x=1..m} P(x) = sum_j C(m, j+1) * (Delta^j P)(1)
# cross-checked against a brute-force sum at m=100. They are compared as
# DECIMAL STRINGS on purpose: an in-Tungsten reference computation would
# itself run through the >2^48 integer paths under test here, and a literal
# of this width is not a reliable spec input either.

failures = 0

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got=" + got + " want=" + want
    return 1
  << "PASS " + name
  0

# --- 1. Literal range base, bounds past 2^48 (2^48 = 281474976710656) -----

big_hi = 1000000000000000            # 10^15, ~3.6x 2^48

failures = failures + check("deg2 @10^15 literal range",
  ((1..big_hi)/Σ(5x² - 3x + 1)).to_s(),
  "1666666666666667666666666666667000000000000000")

failures = failures + check("deg20 @10^15 literal range",
  ((1..big_hi)/Σ(x²⁰ + 17x¹³ - 4x⁵ + 2x + 9)).to_s(),
  "47619047619048119047619047620714285714285714285714285714276214285714285714285714285714347238095238095239309523809523495023809523809542226190476191748614718614718574201948051944509202020202020288841630591637051630591630591508374963924957050663924963925054341630591634073138528138528111892424242423723300000000000000")

# Straddle the truncation edge: 2^48 - 1 and 2^48 + 1.
failures = failures + check("deg2 @2^48-1",
  ((1..281474976710655)/Σ(5x² - 3x + 1)).to_s(),
  "37167908664217388323242806731335144923201535")

failures = failures + check("deg2 @2^48+1",
  ((1..281474976710657)/Σ(5x² - 3x + 1)).to_s(),
  "37167908664218180604867949375836980269547523")

# --- 2. Range bound to a variable (materialization elision) ---------------
# Inside a function body, since the elision gate skips main's top level.

-> via_var(n)
  r = (1..n)
  r/Σ(5x² - 3x + 1)

failures = failures + check("deg2 @10^15 via range var",
  via_var(big_hi).to_s(),
  "1666666666666667666666666666667000000000000000")

# Two pipelines over ONE binding — the polysum.w shape.
-> two_uses(n)
  r = (1..n)
  a = r/Σ(5x² - 3x + 1)
  b = r/Σ(5x² - 3x + 1)
  a + b

failures = failures + check("deg2 @10^15 two uses of one var",
  two_uses(big_hi).to_s(),
  "3333333333333335333333333333334000000000000000")

# Rep-shifted bounds, both from variables.
-> shifted(lo, hi)
  r = (lo..hi)
  r/Σ(5x² - 3x + 1)

failures = failures + check("deg2 shifted range @10^15",
  shifted(5, big_hi + 4).to_s(),
  "1666666666666687666666666666755000000000000000")

# --- 3. A non-elidable use keeps the range materialized ------------------
# `.size` is not a position the range-binding substitution rewrites, so the
# materialization must survive and `r` must still behave as a real range.
# Sum(2x+3, x=1..100) = 10400, plus size 100.

-> also_sized(n)
  r = (1..n)
  r/Σ(2x + 3) + r.size

failures = failures + check("elision refused when .size is used", also_sized(100).to_s(), "10500")

# --- 4. Pipelines inside a block body capture their free variables ---------
# find_vars_in_node is a per-kind table whose `else` leaf captured NOTHING,
# and it had no :map / :calc / :range case. A pipeline inside a block never
# captured the names its range bounds or its base referred to, so the
# reference loaded nil: the inline-range form folded over a nil bound and the
# captured-range form segfaulted. Both must now equal 2 * sum(x, 1..100).

-> block_inline_range(n)
  t = 0
  2 -> (k)
    t += (1..n)/Σ(x)
  t

failures = failures + check("inline range in block body captures n", block_inline_range(100).to_s(), "10100")

-> block_captured_range(n)
  r = (1..n)
  t = 0
  2 -> (k)
    t += r/Σ(x)
  t

failures = failures + check("captured range as pipeline base in block", block_captured_range(100).to_s(), "10100")

# --- 5. Compound assignment whose RHS materializes bindings ---------------
# `t += <pipeline>` picked its write-back target (binding vs var_slot) BEFORE
# lowering the RHS, but lowering a :map / :calc calls materialize_bindings,
# which spills bindings to slots and clears them. The result went to a dead
# binding while the slot every later read uses kept the old value — so the
# `+=` vanished AND the variable stayed desynchronized for the rest of the
# body (a following `t += 1` was lost too).

-> single_compound(n)
  r = (1..n)
  t = 0
  t += r/Σ(x)
  t

failures = failures + check("single += over a pipeline", single_compound(100).to_s(), "5050")

-> repeated_compound(n)
  r = (1..n)
  t = 0
  t += r/Σ(x)
  t += r/Σ(x)
  t

failures = failures + check("repeated += over one range binding", repeated_compound(100).to_s(), "10100")

-> compound_then_int(n)
  r = (1..n)
  t = 0
  t += r/Σ(x)
  t += 1
  t

failures = failures + check("+= pipeline then += int stays in sync", compound_then_int(100).to_s(), "5051")

if failures == 0
  << "poly_ranged_sum_big_bounds_spec: all checks passed"
else
  << "poly_ranged_sum_big_bounds_spec: " + failures.to_s() + " FAILED"
  exit(1)
