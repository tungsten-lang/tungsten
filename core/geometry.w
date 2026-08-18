# Differential geometry over symbolic coordinate fields.
#
# `use geometry` loads a small exact/numeric spine:
#
#   Chart -> TensorField -> Metric -> LeviCivitaConnection
#                                -> RiemannCurvature
#                                -> GeodesicSystem
#
# Algebraic projective geometry remains under `use algebra`; these classes are
# for smooth coordinate metrics and do not change that dependency boundary.

use core/calculus
use core/solve
use core/geometry/support
use core/geometry/lattice_symmetry
use core/geometry/digital
use core/geometry/plane_symmetry
use core/geometry/wallpaper_group
use core/geometry/polyomino
use core/geometry/polyomino_packing
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
