# Dogfood for floating-point math modes (strict / precise / fast) and the
# `@strictmath` / `@fastmath` scoped block overrides.
#
# The load-bearing invariant is the FMA-contraction CARVE-OUT in precise mode
# (the default): a *direct* `a*b + c` / `a*b - c` (addend not itself a product)
# contracts to a single `llvm.fmuladd.f64`, but `a*b - c*d` — where the addend
# IS a product — does NOT. That keeps a 2x2 determinant / cross product exactly
# zero when its two cross terms are equal, instead of the ~1e-16 residual that
# C's bare `-ffp-contract=on` produces by contracting one product into the FMA.
#
# How the numeric checks discriminate:
#   * direct `a*b+c` over exact inputs → value is mode-independent, so we just
#     confirm correctness (a wrong fmuladd field-mapping would dangle and the
#     program wouldn't compile at all — see compiler/lib/wire.w apply_subst).
#   * `x1*y2 - x2*y1` with x1==x2, y1==y2 over INEXACT inputs (1.7, 3.3) → the
#     residual is 0 iff contraction was correctly suppressed. This is the
#     regression guard: drop the `both_products` guard in lowering/ops.w and
#     this flips to nonzero and FAILs.
#
# Run: `bin/tungsten -o /tmp/fpm spec/numeric/fp_math_mode_spec.w && /tmp/fpm`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Precise mode (default): direct a*b±scalar contracts; value stays correct --
a = ~2.0
b = ~3.0
c = ~1.0
check("precise.fma_add", a * b + c == ~7.0, true)
check("precise.fma_sub", a * b - c == ~5.0, true)
check("precise.mul_only", a * b == ~6.0, true)
# Commuted add `c + a*b` also contracts (addend `c` is a scalar).
check("precise.fma_add_commuted", c + a * b == ~7.0, true)

# -- The carve-out: a*b - c*d (both sides products) must NOT contract. --
# x1*y2 and x2*y1 are the same real value over equal inputs, so a non-contracted
# subtraction is bit-exactly zero. A wrongly-contracted FMA leaves ~1.19e-16.
x1 = ~1.7
y1 = ~3.3
x2 = ~1.7
y2 = ~3.3
det = x1 * y2 - x2 * y1
check("precise.cross_product_exact_zero", det == ~0.0, true)
# The `+` form of two products (a*b + c*d) likewise stays unfused; here it is
# just a plain sum, checked for correctness.
sum2 = x1 * y2 + x2 * y1
check("precise.two_products_add", sum2 == (x1 * y2) + (x2 * y1), true)

# -- @strictmath block: NO contraction at all (FMA only via explicit fma()). --
# Even the direct a*b+c stays as separate fmul+fadd, and the cross product is 0.
@strictmath ->
  s1 = ~1.7
  t1 = ~3.3
  s2 = ~1.7
  t2 = ~3.3
  sdet = s1 * t2 - s2 * t1
  check("strict.cross_product_zero", sdet == ~0.0, true)
  check("strict.fma_add_value", ~2.0 * ~3.0 + ~1.0 == ~7.0, true)

# -- Explicit fma(a,b,c): a fused multiply-add. --
# Compiled, this is llvm.fma.f64 (single rounding), so fma(x,y,-(x*y)) isolates
# the nonzero rounding error of x*y — the opt-in precision precise mode refuses
# to apply implicitly to a*b - c*d. That single-rounding residual is a
# compiled-codegen property (the tree-walking interpreter double-rounds), so it
# is NOT asserted here to keep this spec passing under both `-o` and `run`;
# it was verified live: `fma(~1.7,~3.3, ~0.0 - ~1.7*~3.3)` == 1.199e-16 compiled.
check("fma.basic", fma(~2.0, ~3.0, ~1.0) == ~7.0, true)

# -- @fastmath block: fast-math flags on; ordinary arithmetic stays correct. --
# Use exactly-representable inputs (2*3+1 == 7) so the assertion holds whether
# or not fast-math contracts/reassociates — we are testing that the block still
# computes correctly, not the last-ULP rounding that fast mode is allowed to
# perturb.
@fastmath ->
  f1 = ~2.0
  g1 = ~3.0
  check("fast.mul_add_value", f1 * g1 + ~1.0 == ~7.0, true)

# -- Blocks inside method bodies. Exercises the expression-position dispatch
# (a method whose tail is the block) and ivar collection through the block. --
+ Geo
  -> det(@a, @b, @c, @d)
    @strictmath ->
      @a * @d - @b * @c          # block is the method body's value

  -> scaled(@x, @y)
    @fastmath ->
      @acc = @x * @y + ~1.0      # ivar assigned inside the block
      @acc

g = Geo.new
check("method.strict_det_zero", g.det(~1.7, ~3.3, ~1.7, ~3.3) == ~0.0, true)
check("method.fast_ivar_acc", g.scaled(~2.0, ~3.0) == ~7.0, true)
