# Dogfood for the Vec2/Vec3/Vec4 family — exercises the autoload-but-never-
# instantiated vector classes: float dot product (C3), parallel? (Cauchy-
# Schwarz over dot), componentwise arithmetic, cross product, and swizzles.
#
# `dot` is the accumulator-shorthand `-> dot/1 0` summing an each_with_index
# closure. On a float component type the accumulator must NOT be promoted to
# a raw machine int, or the float `+=` coerces through w_to_i64 and dies —
# the C3 bug. Fixed by making escape analysis (mark_subtree_escape) work on
# slab-AST nodes again.
#
# Run: `bin/tungsten -o /tmp/vd spec/numeric/vector_spec.w && /tmp/vd`.
#
# Not exercised (separate, unrelated gaps): `length` needs `sqrt` on a
# machine `## f64` (unimplemented, like `.to_i`); `.sum` on a plain float
# array mis-sums via the fused-pipeline path. Use `length_squared` / `dot`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Float dot product (C3): [1,2,3]·[1,2,3] = 14. --
v = Vec3<f64>.new([1.0, 2.0, 3.0] ## f64[3])
check("vec3.dot.f64", v.dot(v) == (14.0 ## f64), true)
v2 = Vec2<f64>.new([3.0, 4.0] ## f64[2])
check("vec2.dot.f64", v2.dot(v2) == (25.0 ## f64), true)
v4 = Vec4<f64>.new([1.0, 1.0, 1.0, 1.0] ## f64[4])
check("vec4.dot.f64", v4.dot(v4) == (4.0 ## f64), true)

# Integer vectors keep integer dot.
vi = Vec3<i64>.new([1, 2, 3] ## i64[3])
check("vec3.dot.i64", vi.dot(vi), 14)

# -- length_squared = dot(self): 3²+4² = 25; length = √25 = 5 (sqrt). --
check("vec2.length_squared", v2.length_squared == (25.0 ## f64), true)
check("vec2.length", v2.length == (5.0 ## f64), true)

# -- float / int array .sum (boxed-array sum must accumulate via w_add). --
check("array.sum.float", [1.0, 2.0, 3.0].sum == (6.0 ## f64), true)
check("array.sum.int", [1, 2, 3, 4].sum, 10)

# -- to_i / floor on float-ish scalars. --
check("scalar.to_i", (16.0).sqrt.to_i, 4)
check("scalar.floor", (3.7).floor, 3)

# -- parallel? (Cauchy-Schwarz over the float dot). --
w = Vec3<f64>.new([2.0, 4.0, 6.0] ## f64[3])      # collinear with v
u = Vec3<f64>.new([1.0, 0.0, 0.0] ## f64[3])      # not collinear
check("vec3.parallel.true", v.parallel?(w), true)
check("vec3.parallel.false", v.parallel?(u), false)

# -- Componentwise add / subtract. --
check("vec3.add.x", (v + w).x == (3.0 ## f64), true)
check("vec3.sub.x", (w - v).x == (1.0 ## f64), true)
check("vec3.negate.z", (-v).z == (-3.0 ## f64), true)
check("vec3.lerp.y", v.lerp(w, 0.5 ## f64).y == (3.0 ## f64), true)

# -- Vec3 cross product: x̂ × ŷ = ẑ. --
e1 = Vec3<f64>.new([1.0, 0.0, 0.0] ## f64[3])
e2 = Vec3<f64>.new([0.0, 1.0, 0.0] ## f64[3])
check("vec3.cross.z", e1.cross(e2).z == (1.0 ## f64), true)

# -- Swizzles + dimension. --
check("vec3.zyx.x", v.zyx.x == (3.0 ## f64), true)
check("vec3.dimension", v.dimension, 3)
