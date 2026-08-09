# Symbolic differential geometry plus exact/discrete computational foundations.
#
# `use geometry` loads a small exact/numeric spine plus discrete foundations:
#
#   Chart -> TensorField -> Metric -> LeviCivitaConnection
#                                -> RiemannCurvature
#                                -> GeodesicSystem
#
#   exact affine predicates -> validated TriangleMesh topology
#
# Algebraic projective geometry remains under `use algebra`; these classes are
# for smooth coordinate metrics and computational geometry, and do not change
# that dependency boundary.  Mesh fields/operators remain with Tensor/Sparse;
# mesh rendering remains with Plot/Plot3D.

use core/calculus
use core/solve
use core/geometry/support
use core/geometry/lattice_symmetry
use core/geometry/digital
use core/geometry/polygon
use core/geometry/lattice_metric
use core/geometry/conway_criterion
use core/geometry/crystallography
use core/geometry/plane_symmetry
use core/geometry/wallpaper_group
use core/geometry/polyomino
use core/geometry/polyomino_packing
use core/geometry/tiling
use core/geometry/predicates
use core/geometry/mesh
use core/geometry/measure
use core/geometry/flat_torus
use core/geometry/chart
use core/geometry/tensor_field
use core/geometry/metric
use core/geometry/connection
use core/geometry/curvature
use core/geometry/geodesic
use core/geometry/warped_cone
use core/geometry/perturbation
use core/geometry/spacetime
use core/geometry/brane

+ Geometry
  -> .chart(names, domains = nil)
    Chart.new(names, domains)

  -> .metric(chart, components, signature = nil)
    Metric.new(chart, components, signature)

  -> .tensor_field(chart, components, indices)
    TensorField.new(chart, components, indices)
