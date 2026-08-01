# Exact homogeneous-map identities and certified canonical-height tails.

use algebra

-> height_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

line = ProjectiveSpace<ℚ, 1>.new(:X, :Y)
x = line.coords[0]
y = line.coords[1]
zero = line.ring.zero
one = line.ring.one

# Coordinatewise squaring has zero height defect.
power_map = ProjectiveHomogeneousMap.new(line, [x**2, y**2])
power_defect = ProjectiveHeightDefectBound.new(
  power_map, 1, 2, [[one, zero], [zero, one]])
height_check("projective_height.power_map", power_map.certified?)
height_check("projective_height.power_defect", power_defect.certified?)
height_check(
  "projective_height.power_defect_zero",
  power_defect.defect_coefficient_bound == 1)

tolerance = Rational.new(1, 10**18)
power_height = ProjectiveCanonicalHeightEnclosure.new(
  power_map, power_defect, line.point(2, 1), 4, tolerance)
log_two = Calculus.certified_log(2, tolerance)
height_check("projective_height.power_enclosure", power_height.certified?)
height_check(
  "projective_height.power_contains_log_two",
  power_height.lower_bound <= log_two.upper_bound &&
  power_height.upper_bound >= log_two.lower_bound)
height_check(
  "projective_height.power_tail_tight",
  power_height.width <= tolerance)

# F=[X^2+Y^2:X^2-Y^2] has the exact identities
# 2X^2=F0+F1 and 2Y^2=F0-F1.  Both coefficient bounds are 2.
sum_map = ProjectiveHomogeneousMap.new(
  line, [x**2 + y**2, x**2 - y**2])
sum_defect = ProjectiveHeightDefectBound.new(
  sum_map, 2, 2, [[one, one], [one, one*(-1)]])
height_check("projective_height.sum_map", sum_map.certified?)
height_check("projective_height.sum_defect", sum_defect.certified?)
height_check(
  "projective_height.sum_bound",
  sum_defect.forward_coefficient_bound == 2 &&
  sum_defect.reverse_coefficient_bound == 2 &&
  sum_defect.defect_coefficient_bound == 2)

sum_height = ProjectiveCanonicalHeightEnclosure.new(
  sum_map, sum_defect, line.point(1, 1), 5, tolerance)
height_check("projective_height.sum_enclosure", sum_height.certified?)
height_check("projective_height.sum_contains_zero", sum_height.interval.contains?(0))
height_check(
  "projective_height.sum_tail_shrinks",
  sum_height.upper_bound <= log_two.upper_bound / 32)

tamper_rejected = false
begin
  ProjectiveHeightDefectBound.new(
    sum_map, 2, 2, [[one, zero], [one, one*(-1)]])
rescue error
  tamper_rejected = true
height_check("projective_height.tamper_rejected", tamper_rejected)
