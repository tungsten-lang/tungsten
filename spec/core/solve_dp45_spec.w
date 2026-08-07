# Solve.rk45 — true Dormand-Prince 5(4) with FSAL and embedded error
# control. Checks: accuracy within the requested tolerance, order-5
# adaptivity (few steps on smooth problems), tolerance scaling, and
# agreement with a fine fixed-step reference on a chaotic flow.
#
# Run compiled:    bin/tungsten -o /tmp/dp45 spec/core/solve_dp45_spec.w && /tmp/dp45
# Run interpreted: bin/tungsten spec/core/solve_dp45_spec.w

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# y' = y over [0,1] at default tolerance (rtol 1e-6)
r = Solve.rk45(-> (t, y) [y[0]], ~0.0, ~1.0, [~1.0], ~0.01)
d = r[:y].last[0] - Math.exp(~1.0)
if d < ~0.0
  d = ~0.0 - d
check("exp.within_tolerance", d < ~3.0e-6, true)
check("exp.adaptive_steps", r[:t].size < 20, true)

# Tolerance scaling: 1e-10 rtol buys ~1e-10 accuracy for ~4x the steps
tight = Solve.rk45(-> (t, y) [y[0]], ~0.0, ~1.0, [~1.0], ~0.01, ~1.0e-10, ~1.0e-12)
dt2 = tight[:y].last[0] - Math.exp(~1.0)
if dt2 < ~0.0
  dt2 = ~0.0 - dt2
check("exp.tight_tolerance", dt2 < ~1.0e-9, true)
check("exp.tight_steps", tight[:t].size < 60, true)

# Harmonic oscillator over 10π: back to (1, 0)
sho = Solve.rk45(-> (t, y) [y[1], ~0.0 - y[0]], ~0.0, ~31.41592653589793, [~1.0, ~0.0], ~0.01)
e2 = sho[:y].last[0] - ~1.0
if e2 < ~0.0
  e2 = ~0.0 - e2
check("sho.10pi", e2 < ~1.0e-4, true)
check("sho.step_efficiency", sho[:t].size < 400, true)

# Dense output: the free order-4 interpolant samples anywhere in range
sol = Solve.rk45_dense(-> (t, y) [y[0]], ~0.0, ~1.0, [~1.0], ~0.01)
de = sol.at(~1.0)[0] - Math.exp(~1.0)
if de < ~0.0
  de = ~0.0 - de
check("dense.endpoint_consistent", de < ~3.0e-6, true)
dm = sol.at(~0.5)[0] - Math.exp(~0.5)
if dm < ~0.0
  dm = ~0.0 - dm
check("dense.midpoint", dm < ~1.0e-6, true)
shod = Solve.rk45_dense(-> (t, y) [y[1], ~0.0 - y[0]], ~0.0, ~10.0, [~1.0, ~0.0], ~0.01)
qp = shod.at(~1.5707963267948966)
qc = qp[0]
if qc < ~0.0
  qc = ~0.0 - qc
check("dense.sho_quarter_cos", qc < ~1.0e-5, true)
check("dense.sho_quarter_sin", qp[1] > ~0.0 - ~1.00001 && qp[1] < ~0.0 - ~0.99999, true)
dr = false
begin
  shod.at(~11.0)
rescue derr
  dr = true
check("dense.out_of_range_raises", dr, true)

# Dynamics wrapper agrees with a 20x-finer fixed-step reference on Lorenz
lz = Lorenz.classic
ta = Dynamics.trajectory_adaptive(lz, [~1.0, ~1.0, ~1.0], ~0.0, ~2.0, ~0.01)
tf = Dynamics.trajectory(lz, [~1.0, ~1.0, ~1.0], ~0.0, ~2.0, ~0.001)
check("lorenz.matches_fixed_reference", Dynamics.vdist(ta[:x].last, tf[:x].last) < ~0.01, true)
check("lorenz.fewer_steps", ta[:t].size < 300, true)

<< "solve_dp45_spec: all green"
