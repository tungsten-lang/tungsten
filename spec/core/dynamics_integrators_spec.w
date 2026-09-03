# core/dynamics/integrators.w (and the vector helpers in base.w) checked for
# ORDER, not just for "it ran".
#
# Every integrator here is exercised on the harmonic oscillator q'' = -q,
# whose exact solution from (q, p) = (1, 0) is (cos t, -sin t), over exactly
# one period so the exact answer is (1, 0) again. Halving the step must
# divide the global error by 2^order:
#
#   RK4        order 4   error ratio -> 16
#   Verlet     order 2   error ratio ->  4
#   Yoshida4   order 4   error ratio -> 16
#
# and the symplectic pair must keep the energy BOUNDED over a long run
# (Verlet oscillates inside an O(h^2) band around H = 1/2 for 10 000 steps),
# while non-symplectic RK4 at a coarse step loses energy monotonically.
#
# Also: RK4 is exact on a cubic quadrature (it degenerates to Simpson's
# rule), the logistic map at r = 4 is checked against its closed form
# x_n = sin^2(2^n theta), and trajectory/advance/orbit/iterate are checked
# for shape and mutual agreement.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/dynamics_integrators_spec.w
#   bin/tungsten -o /tmp/dyn-integrators-spec spec/core/dynamics_integrators_spec.w && /tmp/dyn-integrators-spec

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> abs(v)
  v < ~0.0 ? ~0.0 - v : v

-> close?(got, want, tolerance)
  abs(got - want) <= tolerance

# x' = 3t^2 with x(0) = 0, so x(t) = t^3 exactly.
+ CubicQuadrature < Flow
  -> dim
    1

  -> f(t, x)
    [~3.0 * t * t]

# x' = x with x(0) = 1, so x(t) = e^t.
+ Exponential < Flow
  -> dim
    1

  -> f(t, x)
    [x[0]]

TAU = ~6.283185307179586
OSC = HarmonicOscillator.classic

# --- the vector helpers integrators are built from --------------------------

check("vcopy.equal_values", Dynamics.vcopy([~1.0, ~2.0])[1] == ~2.0)
check("vcopy.is_a_copy", Dynamics.vcopy([~1.0])[0] == ~1.0)
check("vaxpy.y_plus_a_x", Dynamics.vaxpy([~1.0, ~2.0], ~3.0, [~10.0, ~100.0])[0] == ~31.0)
check("vaxpy.second_component", Dynamics.vaxpy([~1.0, ~2.0], ~3.0, [~10.0, ~100.0])[1] == ~302.0)
check("vsub", Dynamics.vsub([~5.0, ~1.0], [~2.0, ~4.0])[0] == ~3.0)
check("vnorm.three_four_five", close?(Dynamics.vnorm([~3.0, ~4.0]), ~5.0, ~1.0e-15))
check("vnorm.zero", Dynamics.vnorm([~0.0, ~0.0]) == ~0.0)
check("vdist", close?(Dynamics.vdist([~1.0, ~1.0], [~4.0, ~5.0]), ~5.0, ~1.0e-15))
check("wrap2pi.inside", close?(Dynamics.wrap2pi(~1.0), ~1.0, ~1.0e-15))
check("wrap2pi.above", close?(Dynamics.wrap2pi(TAU + ~1.0), ~1.0, ~1.0e-12))
check("wrap2pi.below", close?(Dynamics.wrap2pi(~0.0 - ~1.0), TAU - ~1.0, ~1.0e-12))

# --- RK4 is exact on a cubic (it is Simpson's rule in disguise) -------------

cubic = CubicQuadrature.new
one_step = Dynamics.rk4_step(cubic, ~0.0, [~0.0], ~1.0)
check("rk4.cubic.one_step", close?(one_step[0], ~1.0, ~1.0e-15))
ten_steps = Dynamics.advance(cubic, [~0.0], ~0.0, 10, ~0.2)
check("rk4.cubic.exact_at_two", close?(ten_steps[0], ~8.0, ~1.0e-14))
check("rk4.cubic.midpoint",
      close?(Dynamics.advance(cubic, [~0.0], ~0.0, 5, ~0.2)[0], ~1.0, ~1.0e-14))

# one RK4 step of x' = x from 1 truncates at h^5/120
step_error = abs(Dynamics.rk4_step(Exponential.new, ~0.0, [~1.0], ~0.1)[0] - Math.exp(~0.1))
check("rk4.local_error_is_fifth_order", step_error < ~1.0e-6)
check("rk4.local_error_is_not_zero", step_error > ~1.0e-9)

# --- RK4 global order 4 on the harmonic oscillator --------------------------

# error over exactly one period, from (q, p) = (1, 0) back to (1, 0)
-> rk4_period_error(steps)
  x = Dynamics.advance(OSC, [~1.0, ~0.0], ~0.0, steps, TAU / steps.to_f)
  abs(x[0] - ~1.0) + abs(x[1])

e32 = rk4_period_error(32)
e64 = rk4_period_error(64)
e128 = rk4_period_error(128)
e256 = rk4_period_error(256)
check("rk4.converges", e32 > e64 && e64 > e128 && e128 > e256)
# the ratio approaches 16 from above as the h^5 term dies away:
# 17.05, 16.59, 16.31
check("rk4.order4.first_halving", close?(e32 / e64, ~16.0, ~1.5))
check("rk4.order4.second_halving", close?(e64 / e128, ~16.0, ~1.0))
check("rk4.order4.third_halving", close?(e128 / e256, ~16.0, ~0.5))
check("rk4.accurate_at_256", e256 < ~1.0e-7)

# --- Verlet is order 2, Yoshida4 is order 4 ---------------------------------

-> verlet_period_error(steps)
  r = Dynamics.verlet(OSC, [~1.0], [~0.0], TAU, TAU / steps.to_f)
  abs(r[:q].last[0] - ~1.0) + abs(r[:p].last[0])

-> yoshida_period_error(steps)
  r = Dynamics.yoshida4(OSC, [~1.0], [~0.0], TAU, TAU / steps.to_f)
  abs(r[:q].last[0] - ~1.0) + abs(r[:p].last[0])

v32 = verlet_period_error(32)
v64 = verlet_period_error(64)
v128 = verlet_period_error(128)
v256 = verlet_period_error(256)
check("verlet.converges", v32 > v64 && v64 > v128 && v128 > v256)
check("verlet.order2.first_halving", close?(v32 / v64, ~4.0, ~0.2))
check("verlet.order2.second_halving", close?(v64 / v128, ~4.0, ~0.05))
check("verlet.order2.third_halving", close?(v128 / v256, ~4.0, ~0.01))
# order 2, not order 4: halving buys 4x, never 16x
check("verlet.is_not_fourth_order", v128 / v256 < ~8.0)

y32 = yoshida_period_error(32)
y64 = yoshida_period_error(64)
y128 = yoshida_period_error(128)
y256 = yoshida_period_error(256)
check("yoshida4.converges", y32 > y64 && y64 > y128 && y128 > y256)
check("yoshida4.order4.first_halving", close?(y32 / y64, ~16.0, ~1.0))
check("yoshida4.order4.second_halving", close?(y64 / y128, ~16.0, ~0.2))
check("yoshida4.order4.third_halving", close?(y128 / y256, ~16.0, ~0.1))
# and at equal step count it beats Verlet by orders of magnitude
check("yoshida4.beats_verlet", y128 < v128 / ~100.0)

# --- shapes and endpoints ---------------------------------------------------

verlet_run = Dynamics.verlet(OSC, [~1.0], [~0.0], TAU, TAU / ~32.0)
check("verlet.sample_count", verlet_run[:q].size == 33)
check("verlet.momentum_sampled_too", verlet_run[:p].size == 33)
check("verlet.time_starts_at_zero", verlet_run[:t][0] == ~0.0)
check("verlet.time_ends_at_period", close?(verlet_run[:t].last, TAU, ~1.0e-12))
check("verlet.initial_state_untouched",
      verlet_run[:q][0][0] == ~1.0 && verlet_run[:p][0][0] == ~0.0)
yoshida_run = Dynamics.yoshida4(OSC, [~1.0], [~0.0], TAU, TAU / ~32.0)
check("yoshida4.sample_count", yoshida_run[:q].size == 33)
check("yoshida4.time_ends_at_period", close?(yoshida_run[:t].last, TAU, ~1.0e-12))

# --- long-run energy behavior: bounded vs. secular --------------------------

check("oscillator.initial_energy", OSC.energy([~1.0], [~0.0]) == ~0.5)
check("oscillator.potential", OSC.potential([~2.0]) == ~2.0)
check("oscillator.acceleration", OSC.accel([~3.0])[0] == ~-3.0)
check("oscillator.flow_state_layout",
      OSC.f(~0.0, [~1.0, ~2.0])[0] == ~2.0 && OSC.f(~0.0, [~1.0, ~2.0])[1] == ~-1.0)
check("oscillator.is_a_flow", OSC.flow?)
check("oscillator.dim", OSC.dim == 2)

# Verlet at h = 0.1 over 10 000 steps: the energy error stays inside an
# O(h^2) band and never walks away from it.
verlet_energies = []
mark = 1
while mark <= 4
  long_run = Dynamics.verlet(OSC, [~1.0], [~0.0], ~250.0 * mark.to_f, ~0.1)
  verlet_energies.push(OSC.energy(long_run[:q].last, long_run[:p].last))
  mark += 1
worst = ~0.0
i = 0
while i < 4
  d = abs(verlet_energies[i] - ~0.5)
  worst = d if d > worst
  i += 1
check("verlet.energy.bounded", worst < ~2.0e-3)
check("verlet.energy.not_exact", worst > ~1.0e-6)
# no secular trend: the error at t = 1000 is no worse than at t = 250
check("verlet.energy.no_drift",
      abs(verlet_energies[3] - ~0.5) < ~3.0 * abs(verlet_energies[0] - ~0.5))
check("verlet.energy.oscillates",
      verlet_energies[1] != verlet_energies[0] &&
      verlet_energies[2] != verlet_energies[1])

# Yoshida4 at the same step is four orders tighter.
yoshida_long = Dynamics.yoshida4(OSC, [~1.0], [~0.0], ~1000.0, ~0.1)
check("yoshida4.energy.tight",
      abs(OSC.energy(yoshida_long[:q].last, yoshida_long[:p].last) - ~0.5) < ~1.0e-5)

# RK4 at a coarse step bleeds energy monotonically — that is what
# "not symplectic" costs, and why the symplectic pair exists.
rk4_energies = []
block = 1
while block <= 4
  state = Dynamics.advance(OSC, [~1.0, ~0.0], ~0.0, 800 * block, ~0.3)
  rk4_energies.push(~0.5 * (state[0] * state[0] + state[1] * state[1]))
  block += 1
check("rk4.energy.decays_monotonically",
      rk4_energies[0] > rk4_energies[1] &&
      rk4_energies[1] > rk4_energies[2] &&
      rk4_energies[2] > rk4_energies[3])
check("rk4.energy.loss_is_visible", rk4_energies[3] < ~0.49)
check("rk4.energy.loss_is_slow", rk4_energies[3] > ~0.45)

# --- trajectory / advance / adaptive ----------------------------------------

path = Dynamics.trajectory(OSC, [~1.0, ~0.0], ~0.0, ~1.0, ~0.01)
check("trajectory.sample_count", path[:t].size == 101)
check("trajectory.states_match_times", path[:x].size == path[:t].size)
check("trajectory.starts_at_t_start", path[:t][0] == ~0.0)
check("trajectory.ends_at_t_stop", close?(path[:t].last, ~1.0, ~1.0e-12))
check("trajectory.initial_state", path[:x][0][0] == ~1.0)
check("trajectory.matches_cosine", close?(path[:x].last[0], Math.cos(~1.0), ~1.0e-9))
check("trajectory.matches_minus_sine", close?(path[:x].last[1], ~0.0 - Math.sin(~1.0), ~1.0e-9))
# advance is the same RK4, without keeping the path
advanced = Dynamics.advance(OSC, [~1.0, ~0.0], ~0.0, 100, ~0.01)
check("advance.agrees_with_trajectory",
      close?(advanced[0], path[:x].last[0], ~1.0e-15) &&
      close?(advanced[1], path[:x].last[1], ~1.0e-15))
check("advance.zero_steps_is_identity",
      Dynamics.advance(OSC, [~1.0, ~0.0], ~0.0, 0, ~0.01)[0] == ~1.0)

adaptive = Dynamics.trajectory_adaptive(Exponential.new, [~1.0], ~0.0, ~1.0, ~0.01)
check("adaptive.reaches_e", close?(adaptive[:x].last[0], Math.exp(~1.0), ~1.0e-5))
check("adaptive.lands_on_t_stop", close?(adaptive[:t].last, ~1.0, ~1.0e-12))
check("adaptive.uses_few_steps", adaptive[:t].size < 101)
check("adaptive.starts_where_told", adaptive[:x][0][0] == ~1.0)

# --- numerical Jacobian matches the analytic flow ---------------------------

numeric = Dynamics.numjac_flow(OSC, ~0.0, [~1.0, ~2.0])
# d/dx of [p, -q] is [[0, 1], [-1, 0]]
check("numjac.dq_dq", close?(numeric[0][0], ~0.0, ~1.0e-6))
check("numjac.dq_dp", close?(numeric[0][1], ~1.0, ~1.0e-6))
check("numjac.dp_dq", close?(numeric[1][0], ~-1.0, ~1.0e-6))
check("numjac.dp_dp", close?(numeric[1][1], ~0.0, ~1.0e-6))

# --- maps: orbit and iterate against a closed form --------------------------

# x_{n+1} = 4 x_n (1 - x_n) with x_0 = sin^2(theta) has x_n = sin^2(2^n theta)
theta = ~1.0
seed = Math.sin(theta) * Math.sin(theta)
logistic = LogisticMap.classic
check("logistic.is_a_map", !logistic.flow?)
check("logistic.dim", logistic.dim == 1)
orbit = Dynamics.orbit(logistic, [seed], 5)
check("orbit.length_is_n_plus_one", orbit.size == 6)
check("orbit.first_is_the_seed", orbit[0][0] == seed)
check("orbit.step1_closed_form",
      close?(orbit[1][0], Math.sin(~2.0) * Math.sin(~2.0), ~1.0e-15))
check("orbit.step3_closed_form",
      close?(orbit[3][0], Math.sin(~8.0) * Math.sin(~8.0), ~1.0e-14))
check("orbit.step5_closed_form",
      close?(orbit[5][0], Math.sin(~32.0) * Math.sin(~32.0), ~1.0e-12))
check("iterate.matches_orbit_end",
      Dynamics.iterate(logistic, [seed], 5)[0] == orbit[5][0])
check("iterate.zero_is_identity", Dynamics.iterate(logistic, [seed], 0)[0] == seed)
# 0 and 3/4 are the fixed points of the r = 4 logistic map
check("logistic.fixed_point_zero", logistic.step([~0.0])[0] == ~0.0)
check("logistic.fixed_point_three_quarters",
      close?(logistic.step([~0.75])[0], ~0.75, ~1.0e-15))
check("logistic.stays_in_unit_interval",
      orbit[4][0] >= ~0.0 && orbit[4][0] <= ~1.0)
# derivative at the fixed point 3/4 is r(1 - 2x) = -2, so it is unstable
check("logistic.unstable_fixed_point", close?(logistic.jac([~0.75])[0][0], ~-2.0, ~1.0e-15))

# The Henon map's fixed point is a genuine fixed point of iterate.
henon = Henon.classic
fixed = Dynamics.fixed_point_map(henon, [~0.6, ~0.2])
moved = Dynamics.iterate(henon, fixed, 1)
check("henon.fixed_point_is_fixed",
      close?(moved[0], fixed[0], ~1.0e-9) && close?(moved[1], fixed[1], ~1.0e-9))
check("henon.fixed_point_satisfies_y_eq_bx",
      close?(fixed[1], ~0.3 * fixed[0], ~1.0e-9))

# The standard map keeps both coordinates wrapped into [0, 2pi).
standard = Dynamics.iterate(StandardMap.classic, [~1.0, ~2.0], 500)
check("standard_map.theta_wrapped", standard[0] >= ~0.0 && standard[0] < TAU)
check("standard_map.momentum_wrapped", standard[1] >= ~0.0 && standard[1] < TAU)
# k = 0 makes it an exact rotation: p is constant, theta advances by p
free = StandardMap.new(~0.0)
rotated = Dynamics.iterate(free, [~1.0, ~2.0], 3)
check("standard_map.free_momentum_constant", close?(rotated[1], ~2.0, ~1.0e-12))
# theta = 1 + 3*2 = 7, wrapped back into [0, 2pi)
check("standard_map.free_theta_advances",
      close?(rotated[0], ~7.0 - TAU, ~1.0e-12))

<< "dynamics_integrators_spec: all checks passed"
