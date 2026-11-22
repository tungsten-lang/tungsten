# Algebra classes autoload by name (no `use algebra`) and work compiled and
# interpreted. Small on purpose, so it runs on the interpreter too, unlike
# the exhaustive compiled-only algebra_autoload_spec.w. (The Ruby
# implementation cannot load core/integer.w yet: it reads the comment
# `## Parity / divisibility.` as a type hint.)
#
# Regression: a lexer change made a trailing `>` continue the line, so
# `+ Poly<K>` in core/algebra/polynomial.w swallowed its class body and the
# file stopped parsing. The autoloader skipped failed core loads silently,
# so every algebra class (Polynomial, Curve, ...) quietly failed to load. A
# core file that fails to load is now an error.
#
# Run:
#   bin/tungsten spec/core/algebra_autoload_engines_spec.w
#   bin/tungsten run --interpret spec/core/algebra_autoload_engines_spec.w

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
    exit 1
  << "PASS " + name

field = FiniteField.new(7)
ring = PolynomialRing.new([:x, :y], field, :grevlex)
x = ring.generator(0)
y = ring.generator(1)
f = x * x + y * 3
check("polynomial.class", f.class_name, "Polynomial")
check("polynomial.to_s", f.to_s, "x^2 + 3y")
check("polynomial.specialize", f.specialize(:y, 2).to_s, "x^2 + 6")

space = ProjectiveSpace<FiniteField, 2>.new(Algebra.field(field), 2, [:X, :Y, :Z])
cx = space.coords[0]
cy = space.coords[1]
cz = space.coords[2]
curve = Curve.new(space, cy * cy * cz - cx * cx * cx - cx * cz * cz)
check("curve.degree", curve.degree, 3)
check("curve.genus", curve.genus, 1)
check("curve.nonsingular", curve.nonsingular?, true)
check("curve.contains_point_at_infinity", curve.contains?(space.point([0, 1, 0])), true)
check("curve.excludes_point", curve.contains?(space.point([1, 1, 1])), false)
