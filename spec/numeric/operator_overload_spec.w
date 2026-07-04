# Dogfood for typed operator-overload dispatch — the feature that lets a class
# declare several same-name/same-arity operators that differ only by parameter
# type and have each call routed to the right body at runtime:
#
#   Vec3 * Vec3   → */1(Vector)  Hadamard (componentwise)
#   Vec3 * scalar → */1(Number)  componentwise scale
#   Mat3 * Vec3   → */1(Vec3)    matrix·vector
#   Mat3 * Mat3   → */1(Mat3)    matrix·matrix
#
# Before this landed, `(Vec3)`-style param types never parsed (a class name
# lexes as T_NAME, not T_TYPE), so the second overload silently clobbered the
# first. The lowering synthesizes a per-class dispatcher that branches on
# `@1.is_a?("Type")`; the hierarchy-base overload (Number) is the else, and a
# group with no base (Mat3's Vec3/Mat3) falls to `super`.
#
# Run: `bin/tungsten -o /tmp/od spec/numeric/operator_overload_spec.w && /tmp/od`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Vector * dispatch: Hadamard vs scalar (overloads on Vector, base=Number) --
v = Vec3<f64>.new([1.0, 2.0, 3.0] ## f64[3])
w = Vec3<f64>.new([4.0, 5.0, 6.0] ## f64[3])
h = v * w
check("vec3.hadamard.x", h.x == (4.0 ## f64), true)
check("vec3.hadamard.y", h.y == (10.0 ## f64), true)
check("vec3.hadamard.z", h.z == (18.0 ## f64), true)
s = v * (2.0 ## f64)
check("vec3.scale.x", s.x == (2.0 ## f64), true)
check("vec3.scale.z", s.z == (6.0 ## f64), true)

# -- Explicit Hadamard alias `⊙` routes to the same worker. --
od = v ⊙ w
check("vec3.odot.x", od.x == (4.0 ## f64), true)

# -- Vector / dispatch: Hadamard division vs scalar division. --
a = Vec3<f64>.new([8.0, 12.0, 18.0] ## f64[3])
b = Vec3<f64>.new([2.0, 3.0, 6.0] ## f64[3])
hd = a / b
check("vec3.haddiv.x", hd.x == (4.0 ## f64), true)
check("vec3.haddiv.z", hd.z == (3.0 ## f64), true)
sd = a / (2.0 ## f64)
check("vec3.scaldiv.x", sd.x == (4.0 ## f64), true)

# -- Mat3 * dispatch: matrix·vector vs matrix·matrix (no base → super). --
id = Mat3<f64>.identity
vf = Vec3<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
mv = id * vf
check("mat3.matvec.x", mv.x == ~1.0, true)
check("mat3.matvec.z", mv.z == ~3.0, true)
mm = id * id
# Value-compare via to_s: identity's elements stay integer-typed (a separate
# `## T`-substitution gap), so `== (1.0 ## f64)` would mismatch on type even
# though the matmul dispatch routed correctly and the value is right.
check("mat3.matmul.diag", mm.at(0, 0).to_s(), "1")
check("mat3.matmul.offdiag", mm.at(0, 1).to_s(), "0")

# -- is_a? (the primitive the dispatcher is built on) --
check("isa.vec3.vector", v.is_a?("Vector"), true)
check("isa.vec3.vec3", v.is_a?("Vec3"), true)
check("isa.vec3.not_mat3", v.is_a?("Mat3"), false)
check("isa.scalar.not_vector", (2.0 ## f64).is_a?("Vector"), false)
