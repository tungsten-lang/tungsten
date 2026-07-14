# Dogfood for the square fixed-size matrix family (Mat2 / Mat3 / Mat4).
#
# These autoload-but-never-exercised classes shipped green under the
# byte-identity build yet were broken at runtime: a parser bug in per-element
# typed-literal arrays (`[1 ## T, 0 ## T, …]`) made mat2/mat3/mat4 fail to
# autoload (so `Mat3<f64>` resolved to nil), and `class.new` inside a class
# method (`.identity` / `.zero`) returned the class instead of an instance.
# Both are fixed; this spec instantiates the family and checks identity,
# zero, determinant, trace, transpose, and an inverse round-trip so the rot
# can't return silently.
#
# Run: `bin/tungsten -o /tmp/md spec/numeric/matrix_spec.w && /tmp/md`.
#
# Known gap (tracked separately, NOT exercised here):
#   - `.identity` / `.zero` elements stay integer (generic `## T` literal
#     coercion is not applied during monomorphization), so identity-derived
#     scalars are int-typed — checked with integer compares below.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Class methods build real instances (parser + class.new fixes). --
# Identity elements are integer (see gap note), so these compare to ints.
check("mat2.identity.det", Mat2<f64>.identity.determinant, 1)
check("mat3.identity.det", Mat3<f64>.identity.determinant, 1)
check("mat4.identity.det", Mat4<f64>.identity.determinant, 1)
check("mat3.identity.trace", Mat3<f64>.identity.trace, 3)
check("mat4.identity.trace", Mat4<f64>.identity.trace, 4)
check("mat3.zero.trace", Mat3<f64>.zero.trace, 0)

# -- determinant / trace on explicit float matrices (column-major). --
# 2·I3 → det = 8, trace = 6.
two = Mat3<f64>.new([
  2.0 ## f64, 0.0 ## f64, 0.0 ## f64,
  0.0 ## f64, 2.0 ## f64, 0.0 ## f64,
  0.0 ## f64, 0.0 ## f64, 2.0 ## f64
] ## f64[9])
check("mat3.2I.det", two.determinant == (8.0 ## f64), true)
check("mat3.2I.trace", two.trace == (6.0 ## f64), true)

# Mat2 determinant of [[1,2],[3,4]] (column-major [1,3,2,4]) = 1·4 − 2·3 = −2.
m2 = Mat2<f64>.new([1.0 ## f64, 3.0 ## f64, 2.0 ## f64, 4.0 ## f64] ## f64[4])
check("mat2.det", m2.determinant == (-2.0 ## f64), true)

# -- transpose: trace is transpose-invariant. --
tp = Mat3<f64>.new([
  1.0 ## f64, 2.0 ## f64, 3.0 ## f64,
  4.0 ## f64, 5.0 ## f64, 6.0 ## f64,
  7.0 ## f64, 8.0 ## f64, 9.0 ## f64
] ## f64[9]).transpose
check("mat3.transpose.trace", tp.trace == (15.0 ## f64), true)

# -- Inverse: (2I)⁻¹ = 0.5·I → det 1/8 = 0.125, trace 1.5. --
inv = two.inverse
check("mat3.inverse.det", inv.determinant == (0.125 ## f64), true)
check("mat3.inverse.trace", inv.trace == (1.5 ## f64), true)

# -- General Mat4 determinant regression. The old first-column expansion
# returned -384 for this matrix; the correct determinant is 72. --
m4 = Mat4<f64>.new([
  1.0, 2.0, 3.0, 4.0,
  5.0, 6.0, 7.0, 8.0,
  2.0, 6.0, 4.0, 8.0,
  3.0, 1.0, 1.0, 2.0
] ## f64[16])
check("mat4.general.det", m4.determinant == (72.0 ## f64), true)

# One entry from the exact inverse is -1/6. This also catches an inverse
# accidentally scaled by the old, incorrect determinant.
m4inv = m4.inverse
check("mat4.general.inverse", m4inv.at(0, 0) == ((-1.0 ## f64) / (6.0 ## f64)), true)
