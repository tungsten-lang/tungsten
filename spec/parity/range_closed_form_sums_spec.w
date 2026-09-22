# Ranges: sums over ranges, including the closed-form (Σ polynomial) path
# that both engines implement separately (interpreter.w sigma_* vs
# lowering/poly_sum.w). Large bounds only finish quickly when the closed
# form is taken. Prefix Σ(expr, a..b) lowers as the same pipeline as
# (a..b)/Σ(expr).
#
# Cross-engine parity spec (scripts/parity.sh).

<< "sum [(1..100).sum]"
<< "sum.big [(1..1000000).sum]"
<< "sigma [(1..10)/Σ(x²)]"
<< "sigma.poly [(1..100)/Σ(5x² - 3x + 1)]"
<< "sigma.big [(1..1000000000)/Σ(x³)]"
<< "sigma.huge [(1..1000000000000)/Σ(x² + x)]"
-> via_var(n)
  r = (1..n)
  r/Σ(5x² - 3x + 1)
<< "sigma.var [via_var(100)] [via_var(10**9)]"
<< "sigma.prefix [Σ(2x⁷ + 3x², 1..10)]"
<< "sigma.prefix.poly [Σ(5x² - 3x + 1, 1..100)]"
<< "sigma.prefix.big [Σ(x³, 1..1000000000)]"
<< "sigma.prefix.excl [Σ(x, 1...5)]"
-> plain_sum(n)
  (1..n).sum
<< "sum.var [plain_sum(100)] [plain_sum(10**6)]"
<< "sum.mapped [((1..1000).map -> item * item).sum]"
<< "sum.map.sum [((1..10).map -> item * item).sum]"
