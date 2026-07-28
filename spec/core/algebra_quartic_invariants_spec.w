# Exact Macaulay-resultant and ternary-quartic discriminant regressions.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_quartic_invariants_spec.w
#   bin/tungsten compile spec/core/algebra_quartic_invariants_spec.w \
#     --out /tmp/tungsten-algebra-quartic-invariants-spec

use algebra

-> invariant_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
coordinates = P2.coords
x = coordinates[0]
y = coordinates[1]
z = coordinates[2]

# The Macaulay resultant is normalized by
# Res(a X^3, b Y^3, c Z^3) = a^9 b^9 c^9.
fermat = x**4 + y**4 + z**4
raw = MacaulayResultant.ternary(
  [fermat.derivative(0), fermat.derivative(1), fermat.derivative(2)],
  [3, 3, 3])
invariant_check("macaulay.fermat_raw", raw, Rational.new(4 ** 27))

# Live Magma V2.29 normalization checks:
#   DixmierOhnoInvariants(X^4+Y^4+Z^4)[13] = -1
#   DiscriminantOfTernaryQuartic(...)       = -2^40
invariant_check("fermat.i27", fermat.dixmier_ohno.last, Rational.new(-1))
invariant_check("fermat.integral_discriminant",
                fermat.ternary_quartic_discriminant,
                Rational.new(0 - (2 ** 40)))
invariant_check("partial.complete", fermat.dixmier_ohno.complete?, false)
invariant_check("partial.weights", fermat.dixmier_ohno.weights.join(","), "27")
invariant_check("partial.index", fermat.dixmier_ohno[0], Rational.new(-1))

unsupported_invariant_raised = false
begin
  fermat.dixmier_ohno.invariant(:I3)
rescue error
  unsupported_invariant_raised = "[error]".include?("only the Dixmier-Ohno invariant I27")
invariant_check("partial.unsupported_is_loud", unsupported_invariant_raised, true)

# Diagonal scaling checks degree 27 without relying on the motivating form.
# Magma gives I27(2X^4+3Y^4+5Z^4) = -(2*3*5)^9.
diagonal = (x**4) * 2 + (y**4) * 3 + (z**4) * 5
invariant_check("diagonal.i27",
                diagonal.dixmier_ohno.last,
                Rational.new(0 - (30 ** 9)))
invariant_check("diagonal.integral_discriminant",
                diagonal.ternary_quartic_discriminant,
                Rational.new(0 - (2 ** 40) * (30 ** 9)))

# The shell-width quartic is sparse enough that the canonical Macaulay
# extraneous minor specializes to zero.  The exact chart search must still
# recover Magma's I27 rather than returning 0/0 or recognizing the fixture.
shell = (x**3 * z) * 16 + (x * y**2 * z) * 48 - (y**4) * 3 + (y**3 * z) * 8 + (y**2 * z**2) * 162 + (z**4) * 729
# Magma's Factorization prints the three positive prime powers but omits this
# negative unit; the actual default I27 value is negative.
shell_i27 = Rational.new(
  0 - (2 ** 40) * (3 ** 42) * (13 ** 2))
invariant_check("shell.i27", shell.dixmier_ohno.last, shell_i27)
invariant_check("shell.factor_integer",
                shell.dixmier_ohno.last.to_i,
                0 - (2 ** 40) * (3 ** 42) * (13 ** 2))
invariant_check("curve.delegate",
                Curve.new(P2, shell).dixmier_ohno.last,
                shell_i27)

# A singular quartic must have zero discriminant.  Its third partial is zero,
# exercising the declared-degree Macaulay path rather than degree inference.
singular = x**4 + y**4
invariant_check("singular.discriminant",
                singular.ternary_quartic_discriminant,
                Rational.new(0))
invariant_check("singular.i27", singular.dixmier_ohno.last, Rational.new(0))

nonquartic_raised = false
begin
  (x**3 + y**3 + z**3).dixmier_ohno
rescue error
  nonquartic_raised = "[error]".include?("nonzero homogeneous quartic")
invariant_check("nonquartic_is_loud", nonquartic_raised, true)

<< "algebra_quartic_invariants_spec: all checks passed"
