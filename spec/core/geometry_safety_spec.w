# Operational values, ownership, and finite-domain guards in both engines.
use geometry

-> safety_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

wide = 281474976710656
safety_check("integer.values", Integer.value?(0) && Integer.value?(-1) &&
             Integer.value?(wide) && Integer.value?(-wide))
# Instant occupies the old BigInt tag. Construct its zero-ms tagged payload
# directly because the Instant constructor surface is still a scaffold.
instant = wvalue_from_bits((-2251799813685248) ## i64)
safety_check("integer.reject_instant_tag", ((instant$value >> 48) & 0xFFFF) == 0xFFF8 && !Integer.value?(instant))
[Integer.new, Int.new, BigInt.new, ~1.0, 1.0, Rational.new(1), instant, nil, true].each -> (bad)
  safety_check("integer.reject_scaffold_or_noninteger", !Integer.value?(bad))
  rejected = false
  begin
    EuclideanMeasure.validate_dimension(bad)
  rescue error
    rejected = error.to_s.include?("integer")
  safety_check("measure.reject", rejected)
  rejected = false
  begin
    FlatTorusOrbit.new([bad])
  rescue error
    rejected = error.to_s.include?("integers")
  safety_check("orbit.reject", rejected)
  rejected = false
  begin
    FlatTorusOrbitStraightening.new([bad])
  rescue error
    rejected = error.to_s.include?("integer")
  safety_check("straightening.reject", rejected)
  rejected = false
  begin
    FlatTorusOrbit.new([1, 2]).coordinate_distance(bad, Rational.new(0))
  rescue error
    rejected = error.to_s.include?("index")
  safety_check("orbit.index_reject", rejected)
safety_check("measure.bigint", EuclideanMeasure.validate_dimension(wide) == wide)
large_orbit = FlatTorusOrbit.new([wide, 2*wide])
safety_check("orbit.bigint_normalized", large_orbit.generators == [1, 2])

orbit = FlatTorusOrbit.new([1, 2])
orbit.generators[0] = 100
safety_check("orbit.array_owned", orbit.maximum_loneliness.value == Rational.new(1, 3))
owned_wide = 281474976710657
orbit = FlatTorusOrbit.new([1, owned_wide])
owned_wide.neg!
safety_check("orbit.bigint_source_owned", orbit.generators[1] > 0)
exposed = orbit.generators[1]
exposed.neg!
safety_check("orbit.bigint_getter_owned", orbit.generators[1] > 0)

source = [1, 281474976710657]
straight = FlatTorusOrbitStraightening.new(source)
source[1].neg!
straight.source[0] = 99
straight.matrix[0][0] = 99
straight.inverse[0][0] = 99
straight.image[0] = 99
safety_check("straightening.arrays_owned", straight.certified?)
exposed = straight.source[1]
exposed.neg!
exposed = straight.unstraighten([1, 0])[1]
exposed.neg!
safety_check("straightening.values_owned", straight.certified? && straight.source[1] > 0)

numerator = 281474976710657
denominator = 281474976710659
fraction = Rational.new(numerator, denominator)
extremum = FlatTorusOrbitExtremum.new(fraction, [fraction])
fraction.numerator.neg!
extremum.times.push(Rational.new(99))
exposed = extremum.value
exposed.denominator.neg!
exposed = extremum.witness_time
exposed.numerator.neg!
safety_check("extremum.owned", extremum.value > 0 && extremum.times.size == 1 &&
             extremum.witness_time > 0)

[Math.sqrt(~-1.0), Math.exp(~10000.0), -Math.exp(~10000.0), Float.new, Int.new, "1"].each -> (bad)
  rejected = false
  begin
    WarpedConeSurface.exponential(bad, 1)
  rescue error
    rejected = error.to_s.include?("finite")
  safety_check("cone.radius_finite", rejected)
  rejected = false
  begin
    WarpedConeSurface.exponential(1, bad)
  rescue error
    rejected = error.to_s.include?("finite")
  safety_check("cone.rate_finite", rejected)
  rejected = false
  begin
    WarpedConeSurface.power(1, 1, bad)
  rescue error
    rejected = error.to_s.include?("finite")
  safety_check("cone.exponent_finite", rejected)
  rejected = false
  begin
    WarpedConeSurface.exponential.radius(bad)
  rescue error
    rejected = error.to_s.include?("finite")
  safety_check("cone.height_finite", rejected)
  rejected = false
  begin
    WarpedConeSurface.exponential.normalized_separation(bad, 0)
  rescue error
    rejected = error.to_s.include?("finite")
  safety_check("cone.angle_finite", rejected)
safety_check("cone.fractional_apex", WarpedConeSurface.linear(3, 2).finite_apex_height == Rational.new(3, 2))
cone = WarpedConeSurface.exponential
pi = Math.acos(~-1.0)
tau = ~2.0*pi
gap = cone.normalized_separation(~-5.0, ~5.0)
expected = tau - (10 % tau)
safety_check("cone.opposite_sign_angles", Math.abs(gap - expected) < ~0.000000000001)
safety_check("cone.angle_symmetry", cone.normalized_separation(~5.0, ~-5.0) == gap)
safety_check("cone.angle_periodicity", Math.abs(
  cone.normalized_separation(~-5.0 - ~4.0*tau, ~5.0 + ~3.0*tau) - gap) < ~0.000000000001)
huge_angle = ~1.0e308
gap = cone.normalized_separation(huge_angle, -huge_angle)
safety_check("cone.angle_subtraction_overflow", !gap.nan? && !gap.infinite? && gap >= ~0.0 && gap <= pi)
<< "geometry_safety_spec: all checks passed"
