# Exact flat-torus orbit and Lonely Runner objective regressions.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_flat_torus_spec.w
#   bin/tungsten compile spec/core/geometry_flat_torus_spec.w \
#     --out /tmp/geometry-flat-torus-spec

use geometry

-> flat_torus_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

pair = FlatTorusOrbit.new([1, 2])
pair_extremum = pair.maximum_loneliness
flat_torus_check("pair.dimension", pair.dimension == 2)
flat_torus_check("pair.primitive", pair.primitive?)
flat_torus_check("pair.loneliness", pair_extremum.value == Rational.new(1, 3))
flat_torus_check("pair.witness", pair_extremum.times.include?(Rational.new(1, 3)))
pair_active = pair.active_coordinate_indices(Rational.new(1, 3))
flat_torus_check("pair.active_coordinates",
                 pair_active.size == 2 &&
                 pair_active[0] == 0 && pair_active[1] == 1)
flat_torus_check("pair.distance_to_half",
                 pair.linfinity_distance_to_half == Rational.new(1, 6))
pair_bad_measures = pair.bad_multiplicity_measures(Rational.new(1, 3))
flat_torus_check("pair.bad_measure.partition",
                 pair_bad_measures[0] + pair_bad_measures[1] +
                   pair_bad_measures[2] == Rational.new(1))
flat_torus_check("pair.bad_measure.intersection",
                 pair.bad_intersection_measure([0, 1], Rational.new(1, 3)) ==
                   Rational.new(1, 3))
flat_torus_check("pair.bad_measure.full_not_cover",
                 pair.bad_union_measure(Rational.new(1, 3)) == Rational.new(1) &&
                 !pair.bad_sets_cover?(Rational.new(1, 3)))
flat_torus_check("pair.bad_measure.zero_lonely_time",
                 pair.lonely_time_measure(Rational.new(1, 3)) == Rational.new(0))
flat_torus_check("pair.bad_measure.ambient_target",
                 pair.ambient_lonely_region_measure(Rational.new(1, 3)) ==
                   Rational.new(1, 9))
flat_torus_check("pair.bad_measure.above_covers",
                 pair.bad_sets_cover?(Rational.new(7, 20)))
flat_torus_check("pair.bad_measure.below_has_gap",
                 pair.bad_union_measure(Rational.new(3, 10)) < Rational.new(1))

consecutive = FlatTorusOrbit.new([1, 2, 3, 4])
flat_torus_check("consecutive.tight",
                 consecutive.maximum_loneliness.value == Rational.new(1, 5))
flat_torus_check("consecutive.threshold",
                 consecutive.witness_at_least?(Rational.new(1, 5)))
flat_torus_check("consecutive.above_threshold",
                 !consecutive.witness_at_least?(Rational.new(1, 4)))
flat_torus_check("consecutive.ambient_threshold_volume",
                 consecutive.ambient_lonely_region_measure(Rational.new(1, 5)) ==
                   Rational.new(81, 625))

odd_pair = FlatTorusOrbit.new([1, 3])
flat_torus_check("odd_pair.antipode",
                 odd_pair.maximum_loneliness.value == Rational.new(1, 2))

scaled = FlatTorusOrbit.new([-2, 4, 6])
flat_torus_check("scaled.normalized",
                 scaled.generators.size == 3 &&
                 scaled.generators[0] == 1 &&
                 scaled.generators[1] == 2 &&
                 scaled.generators[2] == 3)
flat_torus_check("scaled.loneliness",
                 scaled.maximum_loneliness.value == Rational.new(1, 4))
flat_torus_check("negative_time.symmetry",
                 scaled.minimum_coordinate_distance(Rational.new(-1, 4)) ==
                   scaled.minimum_coordinate_distance(Rational.new(1, 4)))

straightening = FlatTorusOrbit.new([1, 5, 6]).unimodular_straightening
flat_torus_check("straightening.primitive", straightening.primitive?)
flat_torus_check("straightening.image",
                 straightening.vectors_equal?(straightening.image, [1, 0, 0]))
flat_torus_check("straightening.inverse_first_column",
                 straightening.vectors_equal?(
                   straightening.unstraighten([1, 0, 0]), [1, 5, 6]))
flat_torus_check("straightening.certified", straightening.certified?)

nonprimitive_straightening = FlatTorusOrbitStraightening.new([6, -10, 14])
flat_torus_check("straightening.nonprimitive",
                 !nonprimitive_straightening.primitive? &&
                 nonprimitive_straightening.divisor == 2 &&
                 nonprimitive_straightening.vectors_equal?(
                   nonprimitive_straightening.image, [2, 0, 0]) &&
                 nonprimitive_straightening.certified?)

invalid_raised = false
begin
  FlatTorusOrbit.new([1, 0])
rescue error
  invalid_raised = error.to_s.include?("nonzero integers")
flat_torus_check("zero.rejected", invalid_raised)

<< "geometry_flat_torus_spec: all checks passed"
