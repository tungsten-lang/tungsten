# Z[i] as a Euclidean domain, and its unit group as the square lattice's
# rotation group.
#   bin/tungsten run spec/core/gaussian_integer_spec.w

use algebra
use geometry

-> gaussian_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

one = GaussianInteger.one
i = GaussianInteger.i
z = GaussianInteger.new(3, 2)
w = GaussianInteger.new(1, 0 - 4)

gaussian_check("norm", z.norm == 13)
gaussian_check("conjugate", z.conjugate == GaussianInteger.new(3, 0 - 2))
gaussian_check("norm.of_conjugate", z.conjugate.norm == z.norm)
# The norm is multiplicative — the property that makes Z[i] Euclidean.
gaussian_check("norm.multiplicative", (z * w).norm == z.norm * w.norm)
gaussian_check("add", z + w == GaussianInteger.new(4, 0 - 2))
gaussian_check("sub", z - z == GaussianInteger.zero)
gaussian_check("mul", z * w == GaussianInteger.new(11, 0 - 10))
gaussian_check("negate", z.negate == GaussianInteger.new(0 - 3, 0 - 2))

# Units: the four fourth-roots of unity, and nothing else of norm 1.
units = GaussianInteger.units
gaussian_check("units.count", units.size == 4)
all_unit = true
units.each ->(u)
  all_unit = false if !u.unit? || u.norm != 1
gaussian_check("units.norm_one", all_unit)
gaussian_check("units.i_order4", i * i * i * i == one)
gaussian_check("units.i_squared", i * i == GaussianInteger.new(0 - 1, 0))
gaussian_check("unit.not_prime", !one.prime?)

# Euclidean division: the remainder is strictly smaller in norm.
pair = z.divmod(w)
gaussian_check("divmod.identity", pair[0] * w + pair[1] == z)
gaussian_check("divmod.remainder_smaller", pair[1].norm < w.norm)
gaussian_check("divmod.by_unit_exact", z.divmod(i)[1].zero?)

# 5 splits as (2 + i)(2 - i), so 2 + i divides 5 and is a common divisor.
five = GaussianInteger.new(5, 0)
split = GaussianInteger.new(2, 1)
gaussian_check("split.product", split * split.conjugate == five)
gaussian_check("divides", split.divides?(five))
gaussian_check("gcd.norm", z.gcd(z).norm == z.norm)
gaussian_check("gcd.split", five.gcd(split).norm == 5)
gaussian_check("associates.count", z.associates.size == 4)

# Rational primes behave by their residue mod 4: 3 stays inert, 2 and 5 split.
gaussian_check("prime.inert_3", GaussianInteger.new(3, 0).prime?)
gaussian_check("prime.split_5", !five.prime?)
gaussian_check("prime.ramified_2", !GaussianInteger.new(2, 0).prime?)
gaussian_check("prime.1_plus_i", GaussianInteger.new(1, 1).prime?)
gaussian_check("prime.2_plus_i", split.prime?)
gaussian_check("prime.zero", !GaussianInteger.zero.prime?)

# ---- the lattice bridge ----------------------------------------------
#
# Multiplying by -i is the quarter turn clockwise that the packing
# convention uses, and -conj(z) is its reflection across the y-axis. So the
# eight images of a shape under D4 computed in Z[i] must be exactly the
# orbit the geometry module reports.

point = GaussianInteger.new(2, 5)
gaussian_check("rotate.cw_matches_lattice", point.rotated_cw(1) == GaussianInteger.new(5, 0 - 2))
gaussian_check("rotate.ccw_inverse", point.rotated_cw(1).rotated_ccw(1) == point)
gaussian_check("rotate.order4", point.rotated_cw(4) == point)
gaussian_check("reflect.across_y", point.d4_image(6) == GaussianInteger.new(0 - 2, 5))

shape = Polyomino.new([[0, 0], [1, 0], [2, 0], [0, 1]])
lattice_keys = {}
k = 0
while k < 8
  cells = []
  shape.cells.each ->(cell)
    image = GaussianInteger.new(cell[0], cell[1]).d4_image(k)
    cells.push([image.re, image.im])
  lattice_keys[Polyomino.new(cells).key] = true
  k += 1
orbit_keys = {}
shape.orientations.each ->(image)
  orbit_keys[image.key] = true
matched = orbit_keys.size == lattice_keys.size
shape.orientations.each ->(image)
  matched = false if !lattice_keys.key?(image.key)
gaussian_check("d4.orbit_matches_geometry", matched)

<< "gaussian integer spec complete"
