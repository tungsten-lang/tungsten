# Specialization into smaller rings, re-embedding, and divisibility.

use algebra

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = FiniteField.new(101)
ring = PolynomialRing.new([:x, :y, :z], field, :grevlex)
gens = ring.generators
x = gens[0]
y = gens[1]
z = gens[2]

f = y * y * z - x * z * z + x * y * 3 + ring.constant(5)
fz = f.specialize(:z, 3)
check("specialize drops the variable", fz.ring.arity, 2)
check("specialize ring names", fz.ring.names.to_s, [:x, :y].to_s)
xy_ring = fz.ring
gx = xy_ring.generator(0)
gy = xy_ring.generator(1)
check("specialize value", fz, gy * gy * 3 - gx * 9 + gx * gy * 3 + xy_ring.constant(5))

fxz = f.specialize(:y, 2).specialize(:x, 7)
check("double specialization is univariate", fxz.ring.arity, 1)
check("univariate coefficients available", fxz.coefficients.size, 3)

back = fz.in_ring(ring)
check("in_ring re-embeds", back, f.substitute(:z, 3))

raised = false
begin
  (x + y).in_ring(PolynomialRing.new([:x], field))
rescue error
  raised = true
check("in_ring rejects missing variables", raised, true)

g = x * y + z
h = g * (x - z) * (y + ring.constant(2))
check("divides? true", g.divides?(h), true)
check("divides? false", (g + ring.constant(1)).divides?(h), false)
check("divides? zero", ring.zero.divides?(ring.zero), true)

# The UFD cancellation used in the 6400 discriminant argument: if D_1^2 | s^2
# then D_1 | s, checked computationally after a specialization.
d1 = x * y + ring.constant(1)
s = d1 * (x + y * y)
square = s * s
d1z = d1.specialize(:z, 5)
sz = s.specialize(:z, 5)
check("square divisibility after specialization", (d1z * d1z).divides?(square.specialize(:z, 5)), true)
check("cancellation D1 | s", d1z.divides?(sz), true)

<< "all checks passed"
