# GeodesicSystem / GeodesicTrajectory (core/geometry/geodesic.w), checked
# against the one case everybody already knows the answer to: on a sphere
# the geodesics are exactly the GREAT CIRCLES.
#
# Rather than compare against a closed-form parameterization, the great-circle
# property is verified through its three defining invariants, sampled along a
# tilted geodesic launched from the equator:
#
#   unit speed   g_ij v^i v^j == 1 everywhere (affine parameterization);
#   Clairaut     sin^2(theta) * v^phi is constant (the phi-Killing momentum);
#   planarity    embedding the curve in R^3 as (sin t cos p, sin t sin p,
#                cos t), every point stays in the plane through the origin
#                spanned by the initial position and velocity — which IS
#                the definition of a great circle;
#
# plus the two exact special cases (a meridian and the equator, which the
# solver must reproduce to round-off) and the fact that the affine parameter
# of a unit-speed geodesic equals the great-circle central angle it sweeps.
#
# The same machinery on flat R^2 in POLAR coordinates — nonzero Christoffels,
# zero curvature — must still trace a straight line: starting at cartesian
# (1, 0) moving in +y, at s = 1 the curve is at r = sqrt(2), theta = pi/4.
#
# Closing section: the curvature the connection carries. A radius-R sphere has
# scalar curvature 2/R^2 and Kretschmann 4/R^4; a cylinder and a flat torus
# have none at all.
#
# COMPILED-ONLY lane (like spec/core/geometry_spec.w, whose header likewise
# names no --interpret command):
#
#   bin/tungsten -o /tmp/geom-geodesic-spec spec/core/geometry_geodesic_spec.w && /tmp/geom-geodesic-spec
#
# BUG: the native interpreter SIGSEGVs (exit 139, no output, no diagnostic)
# on any use of the symbolic Expression/Chart layer this module is built on.
# Minimal repro — compiled prints "0", `bin/tungsten run --interpret` dies:
#   << Expression.constant(0).to_s
# `bin/tungsten run` swallows the signal and reports success when its output
# is piped, so the crash is easy to mistake for an empty run.

use geometry

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> abs(v)
  v < ~0.0 ? ~0.0 - v : v

-> close?(got, want, tolerance = ~1.0e-9)
  abs(got - want) <= tolerance

# (theta, phi) -> the point on the unit sphere in R^3
-> embed(theta, phi)
  [Math.sin(theta) * Math.cos(phi),
   Math.sin(theta) * Math.sin(phi),
   Math.cos(theta)]

# d/ds of embed along (v_theta, v_phi)
-> embed_velocity(theta, phi, vt, vp)
  [Math.cos(theta) * Math.cos(phi) * vt - Math.sin(theta) * Math.sin(phi) * vp,
   Math.cos(theta) * Math.sin(phi) * vt + Math.sin(theta) * Math.cos(phi) * vp,
   ~0.0 - Math.sin(theta) * vt]

-> cross(a, b)
  [a[1] * b[2] - a[2] * b[1],
   a[2] * b[0] - a[0] * b[2],
   a[0] * b[1] - a[1] * b[0]]

-> dot3(a, b)
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

ZERO = Expression.constant(0)
ONE = Expression.constant(1)
FOUR = Expression.constant(4)
HALF_PI = ~1.5707963267948966
QUARTER_PI = ~0.7853981633974483

sphere_chart = Chart.new([:theta, :phi])
theta_coordinate = sphere_chart.coordinate(0)
unit_sphere = Metric.new(
  sphere_chart, [[ONE, ZERO], [ZERO, theta_coordinate.sin**2]], [1, 1])
sphere_geodesics = unit_sphere.geodesic_system

# --- the system itself ------------------------------------------------------

check("system.dimension", sphere_geodesics.dimension == 2)
check("system.metric_readback", sphere_geodesics.metric == unit_sphere)
check("system.to_s", sphere_geodesics.to_s == "GeodesicSystem(dim=2)")

# rhs: the first half of the output is the velocity, verbatim
rhs = sphere_geodesics.rhs(~0.0, [HALF_PI, ~0.0, ~0.3, ~0.7])
check("rhs.position_derivative_is_velocity", rhs[0] == ~0.3 && rhs[1] == ~0.7)
# at the equator sin(theta)cos(theta) = 0 and cot(theta) = 0, so a geodesic
# through the equator has zero coordinate acceleration
check("rhs.equator_theta_acceleration", close?(rhs[2], ~0.0, ~1.0e-15))
check("rhs.equator_phi_acceleration", close?(rhs[3], ~0.0, ~1.0e-15))
# off the equator, Gamma^theta_phiphi = -sin(theta)cos(theta) bends it
off = sphere_geodesics.rhs(~0.0, [~1.0, ~0.0, ~0.0, ~1.0])
check("rhs.off_equator_bends",
      close?(off[2], Math.sin(~1.0) * Math.cos(~1.0), ~1.0e-12))
check("rhs.off_equator_phi_free", close?(off[3], ~0.0, ~1.0e-15))
# Gamma^phi_thetaphi = cot(theta): moving in theta twists phi
twist = sphere_geodesics.rhs(~0.0, [~1.0, ~0.0, ~1.0, ~1.0])
check("rhs.cotangent_coupling",
      close?(twist[3], ~-2.0 * Math.cos(~1.0) / Math.sin(~1.0), ~1.0e-12))

# --- exact case 1: a meridian (phi constant) --------------------------------

meridian = sphere_geodesics.trajectory([HALF_PI, ~0.3], [~1.0, ~0.0], ~0.0, ~0.5, ~0.01)
check("meridian.theta_advances_linearly",
      close?(meridian.final_position[0], HALF_PI + ~0.5, ~1.0e-12))
check("meridian.phi_never_moves", close?(meridian.final_position[1], ~0.3, ~1.0e-15))
check("meridian.speed_preserved", close?(meridian.final_velocity[0], ~1.0, ~1.0e-12))
check("meridian.no_phi_velocity", close?(meridian.final_velocity[1], ~0.0, ~1.0e-15))

# --- exact case 2: the equator ----------------------------------------------

equator = sphere_geodesics.trajectory([HALF_PI, ~0.0], [~0.0, ~1.0], ~0.0, ~1.0, ~0.01)
check("equator.stays_on_the_equator",
      close?(equator.final_position[0], HALF_PI, ~1.0e-12))
check("equator.phi_advances_at_unit_rate",
      close?(equator.final_position[1], ~1.0, ~1.0e-12))
check("equator.velocity_preserved", close?(equator.final_velocity[1], ~1.0, ~1.0e-12))
check("equator.no_theta_velocity", close?(equator.final_velocity[0], ~0.0, ~1.0e-12))

# --- trajectory accessors ---------------------------------------------------

check("trajectory.sample_count", equator.parameters.size == 101)
check("trajectory.states_match_parameters", equator.states.size == 101)
check("trajectory.state_layout", equator.states[0].size == 4)
check("trajectory.positions_are_halved", equator.positions[0].size == 2)
check("trajectory.velocities_are_halved", equator.velocities[0].size == 2)
check("trajectory.first_parameter", equator.parameters[0] == ~0.0)
check("trajectory.last_parameter", close?(equator.parameters.last, ~1.0, ~1.0e-12))
check("trajectory.initial_position", equator.positions[0][0] == HALF_PI)
check("trajectory.initial_velocity", equator.velocities[0][1] == ~1.0)
check("trajectory.final_state_is_the_last_state",
      equator.final_state[0] == equator.states.last[0])
check("trajectory.final_position_agrees",
      equator.final_position[1] == equator.positions.last[1])
check("trajectory.system_readback", equator.system == sphere_geodesics)
check("trajectory.chart_readback", equator.chart == sphere_chart)
check("trajectory.to_s", equator.to_s == "GeodesicTrajectory(points=101)")

# --- the general case: a tilted great circle --------------------------------

launch_angle = ~0.6
tilted = sphere_geodesics.trajectory(
  [HALF_PI, ~0.0],
  [Math.cos(launch_angle), Math.sin(launch_angle)],
  ~0.0, ~1.2, ~0.005)
positions = tilted.positions
velocities = tilted.velocities
check("tilted.sample_count", positions.size >= 241)
check("tilted.velocities_match_positions", velocities.size == positions.size)
# it really does leave the equator (otherwise the invariants would be trivial)
check("tilted.leaves_the_equator", abs(positions.last[0] - HALF_PI) > ~0.5)

start = embed(positions[0][0], positions[0][1])
start_velocity = embed_velocity(
  positions[0][0], positions[0][1], velocities[0][0], velocities[0][1])
normal = cross(start, start_velocity)
clairaut0 = Math.sin(positions[0][0]) * Math.sin(positions[0][0]) * velocities[0][1]

worst_speed = ~0.0
worst_clairaut = ~0.0
worst_plane = ~0.0
worst_radius = ~0.0
sample = 0
while sample < positions.size
  polar = positions[sample][0]
  azimuth = positions[sample][1]
  sine = Math.sin(polar)
  # g_ij v^i v^j
  radial_part = velocities[sample][0] * velocities[sample][0]
  angular_part = sine * sine * velocities[sample][1] * velocities[sample][1]
  speed = radial_part + angular_part
  worst_speed = abs(speed - ~1.0) if abs(speed - ~1.0) > worst_speed
  # Clairaut's relation
  momentum = sine * sine * velocities[sample][1]
  worst_clairaut = abs(momentum - clairaut0) if abs(momentum - clairaut0) > worst_clairaut
  # planarity through the origin
  point = embed(polar, azimuth)
  offset = abs(dot3(normal, point))
  worst_plane = offset if offset > worst_plane
  # and it stays on the unit sphere
  radius = abs(dot3(point, point) - ~1.0)
  worst_radius = radius if radius > worst_radius
  sample += 1

check("great_circle.unit_speed", worst_speed < ~1.0e-9)
check("great_circle.clairaut_conserved", worst_clairaut < ~1.0e-9)
check("great_circle.lies_in_a_plane_through_the_origin", worst_plane < ~1.0e-9)
check("great_circle.stays_on_the_sphere", worst_radius < ~1.0e-15)
# the normal is a real normal, not a degenerate zero vector
check("great_circle.plane_is_nondegenerate", dot3(normal, normal) > ~0.5)

# affine parameter == central angle swept (both are arc length at unit speed)
finish = embed(positions.last[0], positions.last[1])
check("great_circle.parameter_is_arc_length",
      close?(Math.acos(dot3(start, finish)), ~1.2, ~1.0e-8))
# and at every intermediate sample too: the swept angle is the parameter
worst_arc = ~0.0
sample = 0
while sample < positions.size
  here = embed(positions[sample][0], positions[sample][1])
  swept = Math.acos(dot3(start, here))
  gap = abs(swept - tilted.parameters[sample])
  worst_arc = gap if gap > worst_arc
  sample += 1
check("great_circle.arc_length_matches_everywhere", worst_arc < ~1.0e-8)

# a purely azimuthal launch off the equator is NOT a geodesic circle of
# latitude: it must bend back toward the equator
latitude = sphere_geodesics.trajectory([~1.0, ~0.0], [~0.0, ~1.0], ~0.0, ~0.8, ~0.005)
check("latitude_circle.is_not_a_geodesic", latitude.final_position[0] > ~1.05)
check("latitude_circle.bends_toward_the_equator",
      latitude.final_position[0] > latitude.positions[0][0])

# --- flat R^2 in polar coordinates: still a straight line -------------------

polar_chart = Chart.new([:r, :theta])
radius_coordinate = polar_chart.coordinate(0)
polar_metric = Metric.new(
  polar_chart, [[ONE, ZERO], [ZERO, radius_coordinate**2]], [1, 1])
# the Christoffels are genuinely nonzero here
check("polar.gamma_r_theta_theta",
      polar_metric.connection.component(0, 1, 1) == -radius_coordinate)
check("polar.is_flat",
      close?(polar_metric.curvature.scalar_curvature.evaluate({r: ~2.0, theta: ~0.4}),
             ~0.0, ~1.0e-12))
# cartesian (1, 0) moving in +y is (r, theta) = (1, 0) with (r', theta') = (0, 1)
straight = polar_metric.geodesic_system.trajectory(
  [~1.0, ~0.0], [~0.0, ~1.0], ~0.0, ~1.0, ~0.005)
check("polar.straight_line_radius",
      close?(straight.final_position[0], Math.sqrt(~2.0), ~1.0e-8))
check("polar.straight_line_angle",
      close?(straight.final_position[1], QUARTER_PI, ~1.0e-8))
# and a purely radial ray is exact
ray = polar_metric.geodesic_system.trajectory(
  [~1.0, ~0.7], [~1.0, ~0.0], ~0.0, ~2.0, ~0.01)
check("polar.radial_ray_radius", close?(ray.final_position[0], ~3.0, ~1.0e-12))
check("polar.radial_ray_angle", close?(ray.final_position[1], ~0.7, ~1.0e-15))

# --- cartesian geodesics: constant velocity ---------------------------------

cartesian = Chart.new([:x, :y])
flat = Metric.new(cartesian, [[ONE, ZERO], [ZERO, ONE]], [1, 1])
flat_geodesics = flat.geodesic_system
free = flat_geodesics.trajectory([~1.0, ~2.0], [~3.0, ~-1.0], ~0.0, ~2.0, ~0.05)
check("flat.position_is_linear",
      close?(free.final_position[0], ~7.0, ~1.0e-12) &&
      close?(free.final_position[1], ~0.0, ~1.0e-12))
check("flat.velocity_is_constant",
      free.final_velocity[0] == ~3.0 && free.final_velocity[1] == ~-1.0)
check("flat.rhs_has_no_acceleration",
      flat_geodesics.rhs(~0.0, [~1.0, ~2.0, ~3.0, ~-1.0])[2] == ~0.0)

# --- loud failures ----------------------------------------------------------

raised = false
begin
  sphere_geodesics.rhs(~0.0, [~1.0, ~2.0, ~3.0])
rescue e
  raised = true
check("error.short_state", raised)

raised = false
begin
  sphere_geodesics.trajectory([~1.0], [~0.0, ~1.0], ~0.0, ~1.0)
rescue e
  raised = true
check("error.short_initial_position", raised)

raised = false
begin
  sphere_geodesics.trajectory([HALF_PI, ~0.0], [~1.0], ~0.0, ~1.0)
rescue e
  raised = true
check("error.short_initial_velocity", raised)

raised = false
begin
  GeodesicSystem.new(sphere_chart)
rescue e
  raised = true
check("error.needs_a_metric", raised)

# --- the curvature the connection carries -----------------------------------

# radius-2 sphere: R^2 (dtheta^2 + sin^2(theta) dphi^2)
big_sphere = Metric.new(
  sphere_chart,
  [[FOUR, ZERO], [ZERO, FOUR * theta_coordinate.sin**2]], [1, 1])
point = {theta: ~1.0, phi: ~0.4}
big_curvature = big_sphere.curvature
# Gaussian curvature 1/R^2 = 1/4, so scalar = 2K = 1/2
check("sphere_r2.scalar_curvature",
      close?(big_curvature.scalar_curvature.evaluate(point), ~0.5, ~1.0e-12))
# Kretschmann = 4/R^4 = 1/4
check("sphere_r2.kretschmann",
      close?(big_curvature.kretschmann_scalar.evaluate(point), ~0.25, ~1.0e-12))
# Ricci = K g, so Ricci_thetatheta = (1/4)(4) = 1
check("sphere_r2.ricci",
      close?(big_curvature.ricci_tensor.evaluate(point)[0][0], ~1.0, ~1.0e-12))
# every 2-surface is Einstein-flat: G = Ric - (R/2) g == 0
check("sphere_r2.einstein_vanishes",
      close?(big_curvature.einstein_tensor.evaluate(point)[0][0], ~0.0, ~1.0e-12))
# and the unit sphere is the R = 1 case: scalar 2, Kretschmann 4
check("sphere_r1.scalar_curvature",
      close?(unit_sphere.curvature.scalar_curvature.evaluate(point), ~2.0, ~1.0e-12))
check("sphere_r1.kretschmann",
      close?(unit_sphere.curvature.kretschmann_scalar.evaluate(point), ~4.0, ~1.0e-12))
# scalar curvature scales as 1/R^2: quadrupling the metric quarters it
check("sphere.scales_inversely_with_area",
      close?(unit_sphere.curvature.scalar_curvature.evaluate(point),
             ~4.0 * big_curvature.scalar_curvature.evaluate(point), ~1.0e-12))

# a cylinder is intrinsically flat, even though it looks curved in R^3
cylinder_chart = Chart.new([:z, :phi])
cylinder = Metric.new(cylinder_chart, [[ONE, ZERO], [ZERO, FOUR]], [1, 1])
check("cylinder.no_christoffels", cylinder.connection.component(0, 1, 1) == ZERO)
check("cylinder.no_riemann",
      cylinder.curvature.riemann_tensor.component(0, 1, 0, 1) == ZERO)
check("cylinder.no_scalar_curvature", cylinder.curvature.scalar_curvature == ZERO)

# so is the flat torus: the identity metric on periodic coordinates
torus_chart = Chart.new([:u, :v])
flat_torus = Metric.new(torus_chart, [[ONE, ZERO], [ZERO, ONE]], [1, 1])
check("flat_torus.no_scalar_curvature",
      flat_torus.curvature.scalar_curvature == ZERO)
check("flat_torus.no_kretschmann",
      flat_torus.curvature.kretschmann_scalar == ZERO)
check("flat_torus.no_ricci",
      flat_torus.curvature.ricci_tensor.component(0, 0) == ZERO)
check("flat_torus.no_einstein",
      flat_torus.curvature.einstein_tensor.component(1, 1) == ZERO)
check("flat_torus.geodesics_are_straight",
      close?(flat_torus.geodesic_system.trajectory(
               [~0.1, ~0.2], [~1.0, ~2.0], ~0.0, ~1.0, ~0.05).final_position[1],
             ~2.2, ~1.0e-12))

<< "geometry_geodesic_spec: all checks passed"
