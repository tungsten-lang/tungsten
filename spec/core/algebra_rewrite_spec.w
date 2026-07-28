# Focused algebra surface-grammar regressions.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_rewrite_spec.w
#   bin/tungsten compile spec/core/algebra_rewrite_spec.w --out /tmp/algebra-rewrite-spec

use algebra

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

# ASCII powers, superscript projective dimension, rational coefficients, and
# two declarations in one source exercise the declaration-local temp names.
C1 ⊂ ℙ²_ℚ (X, Y, Z) : 1/2X^2 + Y² - Z² = 0
C2 ⊂ ℙ²_ℚ (U, V) : U^2 + (3/2)V² - 1 = 0

check("projective equation degree", C1.degree, 2)
check("projective rational coefficient",
      C1.equation.coeff([2, 0, 0]), Rational.new(1, 2))
check("projective point membership", C1.contains?(C1.space[0:1:1]), true)

check("affine equation homogenized", C2.equation.homogeneous?, true)
check("affine equation degree", C2.degree, 2)
check("affine point membership", C2.contains?(C2.space[1:0:1]), true)

P3 = ProjectiveSpace<ℚ, 3>.new(:W, :X, :Y, :Z)
check("generic projective dimension", P3.dimension, 3)
check("generic projective names", P3.coordinate_names.join(","), "W,X,Y,Z")
check("four-coordinate point rewrite", P3[2:0:0:0].to_s, "\[1:0:0:0\]")

p3_ascii = ℙ^3_ℚ
check("ASCII global projective dimension", p3_ascii.dimension, 3)
check("ASCII global projective arity", p3_ascii.coordinate_count, 4)

p0 = ℙ⁰_ℚ
check("zero-dimensional projective dimension", p0.dimension, 0)
check("zero-dimensional projective arity", p0.coordinate_count, 1)
check("zero-dimensional projective point", p0.point([12]).to_s, "\[1\]")

p4 = ℙ⁴_ℚ
check("Unicode global projective dimension", p4.dimension, 4)
check("Unicode global default names", p4.coordinate_names.join(","), "X0,X1,X2,X3,X4")
check("arbitrary point arity", p4[2:0:0:0:0].to_s, "\[1:0:0:0:0\]")

t = Poly<ℚ>.new(:t).generator
check("Poly field injection", t.ring.field.class_name, "RationalField")
check("Poly identity", (t**3 - t).discriminant, 4)

unsupported_raised = false
begin
  Algebra.field("𝔽_5")
rescue error
  unsupported_raised = "[error]".include?("unsupported coefficient field")
check("unsupported field is loud", unsupported_raised, true)

source = "use algebra\nA ⊂ ℙ²_ℚ (X, Y, Z) : X² + Y² - Z² = 0\nB ⊂ ℙ²_ℚ (U, V, W) : U² + V² - W² = 0"
rewritten = ccall("w_algebra_rewrite_source", source)
check("rewrite first space temp", rewritten.include?("__algebra_space_0"), true)
check("rewrite second space temp", rewritten.include?("__algebra_space_1"), true)
check("rewrite first coords temp", rewritten.include?("__algebra_coords_0"), true)
check("rewrite second coords temp", rewritten.include?("__algebra_coords_1"), true)
check("rewrite is idempotent",
      ccall("w_algebra_rewrite_source", rewritten) == rewritten, true)

# The surface grammar is opt-in: a source without `use algebra` (or the
# orchestrator's `use core/algebra/...` form) must come back byte-identical,
# however algebra-shaped its contents look.
plain = "A ⊂ ℙ²_ℚ (X, Y, Z) : X² + Y² - Z² = 0"
check("rewrite requires use algebra opt-in",
      ccall("w_algebra_rewrite_source", plain) == plain, true)

commented = "# use algebra\nP2[1:0:0]"
check("comment cannot enable algebra rewrite",
      ccall("w_algebra_rewrite_source", commented) == commented, true)
quoted = "label = \"use algebra\"\nP2[1:0:0]"
check("string cannot enable algebra rewrite",
      ccall("w_algebra_rewrite_source", quoted) == quoted, true)

<< "algebra_rewrite_spec: all checks passed"
