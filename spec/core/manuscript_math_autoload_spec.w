# Public autoloads for the manuscript-derived math models.  Deliberately no
# feature-level `use`: each class must resolve through core/tungsten.w.

-> manuscript_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

manuscript_check("autoload.shell",
                 DiagonalShellPolytope.new(3).shell_count(2) == 19)
manuscript_check("autoload.centered_simplex",
                 CenteredEhrhartSimplex.new(2).normalized_volume == 9)
manuscript_check("autoload.lattice_polygon",
                 LatticePolygon.new([[0, 0], [3, 0], [0, 4]])
                   .interior_lattice_point_count == 3)
manuscript_check("autoload.laurent_jets",
                 LaurentJetFiltration.new([[0], [1]]).jet_rank(1) == 1)
manuscript_check("autoload.newton_polytope",
                 LatticePolytope.new([[0], [1]]).gorenstein_index == 2)
manuscript_check("autoload.homogenized_cone",
                 HomogenizedCone.new(LatticePolytope.new([[0], [1]]))
                   .slice_lattice_point_count(2) == 3)
period_ring = PolynomialRing.new([:x], RationalField.new)
period_x = period_ring.generators[0]
manuscript_check("autoload.toric_period",
                 ToricHypersurfacePeriod.new(
                   period_ring.one + period_x + period_x*period_x)
                   .coefficient(3) == 7)
manuscript_check("autoload.parity_lift",
                 ParityLiftLattice.new([[1, 1]], [1]).certified?)
manuscript_check("autoload.divided_square",
                 DividedSquareSpace.new(4).divided_dimension == 10)
manuscript_check("autoload.binary_carry",
                 BinaryCarryGroup.new(2).order(
                   BinaryCarryGroup.new(2).element([1, 0])) == 4)
manuscript_check("autoload.measure",
                 EuclideanMeasure.unit_ball_volume(2) == Expression.pi)
manuscript_check("autoload.warped_cone",
                 WarpedConeSurface.exponential(1, 1).ideal_apex?)
manuscript_check("autoload.mellin",
                 Math.abs(
                   RadialMellinTransform.critical_multiplier(3, ~1.0).abs -
                   ~1.0) < ~1.0e-11)

<< "manuscript_math_autoload_spec: all checks passed"
