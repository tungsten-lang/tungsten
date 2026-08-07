# core/dynamics — quantitative regressions against known results:
# LinAlg eigen machinery, RK4/symplectic integration, fixed points and
# stability classification, Lyapunov exponents (logistic ln 2, Hénon
# spectrum summing to ln b, Lorenz trace identity), Kaplan-Yorke,
# bifurcation/periods, Poincaré sections, Takens embedding, and the
# Grassberger-Procaccia correlation dimension.
#
# Run compiled:    bin/tungsten -o /tmp/dynspec spec/core/dynamics_spec.w && /tmp/dynspec
# Run interpreted: bin/tungsten spec/core/dynamics_spec.w   (sized to stay ~1-2 min)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> approx(name, got, lo, hi)
  if got >= lo && got <= hi
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " not in " + lo.to_s() + ".." + hi.to_s()
    exit 1

# -- LinAlg: eigenvalues, QR --
e1 = LinAlg.eigenvalues([[~2.0, ~0.0], [~0.0, ~3.0]])
s1 = e1[0][0] + e1[1][0]
approx("eig.diag.sum", s1, ~4.999999, ~5.000001)
e2 = LinAlg.eigenvalues([[~0.0, ~0.0 - ~1.0], [~1.0, ~0.0]])
check("eig.rotation.real", e2[0][0] * e2[0][0] < ~1.0e-20, true)
approx("eig.rotation.imag", e2[0][1] * e2[0][1], ~0.999999, ~1.000001)
qr = LinAlg.qr([[~1.0, ~1.0], [~0.0, ~1.0], [~1.0, ~0.0]])
qtq = LinAlg.matmul(LinAlg.transpose(qr[0]), qr[0])
approx("qr.orthonormal", qtq[0][0] + qtq[1][1], ~1.999999, ~2.000001)
approx("qr.offdiag", qtq[0][1] * qtq[0][1], ~0.0 - ~1.0e-20, ~1.0e-20)

# -- Integration --
lz = Lorenz.classic
tr = Dynamics.trajectory(lz, [~1.0, ~1.0, ~1.0], ~0.0, ~1.0, ~0.01)
check("traj.count", tr[:t].size, 101)

# Analytic vs finite-difference Jacobians agree
ja = lz.jac(~0.0, [~1.0, ~2.0, ~3.0])
jn = Dynamics.numjac_flow(lz, ~0.0, [~1.0, ~2.0, ~3.0])
maxd = ~0.0
r = 0
while r < 3
  c = 0
  while c < 3
    d = ja[r][c] - jn[r][c]
    if d < ~0.0
      d = ~0.0 - d
    if d > maxd
      maxd = d
    c = c + 1
  r = r + 1
approx("jacobian.numeric_matches_analytic", maxd, ~0.0 - ~1.0e-20, ~1.0e-4)

# Symplectic energy behavior on the harmonic oscillator
ho = HarmonicOscillator.classic
vr = Dynamics.verlet(ho, [~1.0], [~0.0], ~50.0, ~0.05)
ev = ho.energy(vr[:q].last, vr[:p].last)
approx("verlet.energy", ev, ~0.4995, ~0.5005)
y4 = Dynamics.yoshida4(ho, [~1.0], [~0.0], ~50.0, ~0.05)
ey = ho.energy(y4[:q].last, y4[:p].last)
approx("yoshida4.energy", ey, ~0.4999999, ~0.5000001)

# -- Fixed points + stability --
fp = Dynamics.fixed_point_flow(lz, [~0.1, ~0.1, ~0.1])
approx("lorenz.origin", Dynamics.vnorm(fp), ~0.0 - ~1.0e-20, ~1.0e-9)
check("lorenz.origin.class", Dynamics.classify_flow(lz, fp).to_s(), "saddle")
cp = Dynamics.fixed_point_flow(lz, [~8.0, ~8.0, ~27.0])
approx("lorenz.cplus.x", cp[0], ~8.485281, ~8.485282)
approx("lorenz.cplus.z", cp[2], ~26.999999, ~27.000001)
low = Lorenz.new(~10.0, ~0.5, ~8.0 / ~3.0)
lfp = Dynamics.fixed_point_flow(low, [~0.1, ~0.1, ~0.1])
check("lorenz.subcritical.class", Dynamics.classify_flow(low, lfp).to_s(), "sink")

lm28 = LogisticMap.new(~2.8)
mfp = Dynamics.fixed_point_map(lm28, [~0.5])
approx("logistic.fixed_point", mfp[0], ~0.642857, ~0.642858)
check("logistic.fp.class", Dynamics.classify_map(lm28, mfp).to_s(), "sink")
hn = Henon.classic
hfp = Dynamics.fixed_point_map(hn, [~0.6, ~0.2])
check("henon.fp.class", Dynamics.classify_map(hn, hfp).to_s(), "saddle")

# -- Lyapunov exponents --
lm4 = LogisticMap.classic
lam = Dynamics.lyapunov_max_map(lm4, [~0.3], 100, 2000)
approx("logistic.r4.ln2", lam, ~0.673, ~0.713)

hlam = Dynamics.lyapunov_max_map(hn, [~0.1, ~0.1], 200, 3000)
approx("henon.lambda1", hlam, ~0.38, ~0.46)
hsp = Dynamics.lyapunov_spectrum_map(hn, [~0.1, ~0.1], 200, 1500)
hsum = hsp[0] + hsp[1]
approx("henon.spectrum.sum_ln_b", hsum, ~0.0 - ~1.2039729, ~0.0 - ~1.2039727)
approx("henon.kaplan_yorke", Dynamics.kaplan_yorke(hsp), ~1.22, ~1.30)

blam = Dynamics.lyapunov_max(lz, [~1.0, ~1.0, ~1.0], ~5.0, ~30.0, ~0.01)
approx("lorenz.benettin", blam, ~0.6, ~1.15)
lsp = Dynamics.lyapunov_spectrum(lz, [~1.0, ~1.0, ~1.0], ~3.0, 400, 5, ~0.01)
tracesum = lsp[0] + lsp[1] + lsp[2]
approx("lorenz.spectrum.trace", tracesum, ~0.0 - ~13.97, ~0.0 - ~13.37)
approx("lorenz.spectrum.lambda1", lsp[0], ~0.6, ~1.2)
approx("lorenz.kaplan_yorke", Dynamics.kaplan_yorke(lsp), ~1.85, ~2.2)

# -- Bifurcation + periods --
check("period.r2_8", Dynamics.period(LogisticMap.new(~2.8), [~0.3], 500, 16, ~1.0e-6), 1)
check("period.r3_2", Dynamics.period(LogisticMap.new(~3.2), [~0.3], 500, 16, ~1.0e-6), 2)
check("period.r3_5", Dynamics.period(LogisticMap.new(~3.5), [~0.3], 2000, 16, ~1.0e-5), 4)
bf = Dynamics.bifurcation(-> (r) LogisticMap.new(r), ~2.8, ~3.6, 5, [~0.3], 300, 8)
check("bifurcation.count", bf[:r].size, 40)

# -- Poincaré section on the Lorenz attractor (upward through z = 27) --
pc = Dynamics.poincare(lz, [~1.0, ~1.0, ~1.0], [~0.0, ~0.0, ~1.0], ~27.0, ~5.0, ~20.0, ~0.01)
check("poincare.nonempty", pc[:points].size >= 10, true)
zerr = pc[:points][0][2] - ~27.0
if zerr < ~0.0
  zerr = ~0.0 - zerr
approx("poincare.on_plane", zerr, ~0.0 - ~1.0e-20, ~0.2)

# -- Standard map stays wrapped --
sm = StandardMap.classic
sx = Dynamics.iterate(sm, [~1.0, ~2.0], 500)
tau2 = ~6.2831854
check("standard_map.wrapped", sx[0] >= ~0.0 && sx[0] < tau2 && sx[1] >= ~0.0 && sx[1] < tau2, true)

# -- Other classic flows stay finite / on their attractors --
vdp = VanDerPol.classic
vtr = Dynamics.trajectory(vdp, [~0.1, ~0.0], ~0.0, ~30.0, ~0.01)
vlast = vtr[:x].last
approx("vanderpol.limit_cycle", Dynamics.vnorm(vlast), ~0.1, ~3.5)
rs = Rossler.classic
rlast = Dynamics.advance(rs, [~1.0, ~1.0, ~1.0], ~0.0, 2000, ~0.01)
check("rossler.finite", Dynamics.vnorm(rlast) < ~100.0, true)
dp = DoublePendulum.classic
dlast = Dynamics.advance(dp, [~1.5, ~1.5, ~0.0, ~0.0], ~0.0, 1000, ~0.005)
check("double_pendulum.finite", Dynamics.vnorm(dlast) < ~100.0, true)
df = Duffing.classic
flast = Dynamics.advance(df, [~0.1, ~0.1], ~0.0, 2000, ~0.01)
check("duffing.finite", Dynamics.vnorm(flast) < ~10.0, true)

# -- Embedding + correlation dimension --
sr = [~1.0, ~2.0, ~1.0, ~2.0, ~1.0, ~2.0, ~1.0, ~2.0]
check("embed.count", Dynamics.embed(sr, 2, 1).size, 7)
check("embed.tau", Dynamics.suggest_tau(sr, 4), 1)
horb = Dynamics.orbit(hn, [~0.1, ~0.1], 550)
hpts = horb.drop(200)
cdim = Dynamics.correlation_dimension(hpts, ~0.02, ~0.5, 6)
approx("henon.correlation_dim", cdim, ~0.9, ~1.5)

<< "dynamics_spec: all green"
