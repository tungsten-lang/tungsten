# Tiling theory on the polyform grids: coronas and Heesch numbers, the
# boundary-word tiling criteria, periodic tilings, and CNF encodings of
# corona questions for an external SAT solver.
#
#   TilingGrid / Polyform    the square, hexagonal and iamond grids and
#                            shapes on them, in heesch-sat's conventions
#   Corona / HeeschNumber    coronas by exact cover, Heesch numbers, witness
#                            verification
#   BoundaryWord /           Beauquier–Nivat and Conway factorizations on
#   TilingCriteria           all three grids (sufficient, never necessary)
#   PeriodicTiling           constructive periodic tilings on a torus
#   CoronaCnf                DIMACS encodings for wassat / wrat
#
# `use geometry` loads all of it; `use core/geometry/tiling` loads only this.

use core/combinatorics/exact_cover
use core/geometry/tiling/grid
use core/geometry/tiling/polyform
use core/geometry/tiling/corona
use core/geometry/tiling/criteria
use core/geometry/tiling/periodic
use core/geometry/tiling/cnf
