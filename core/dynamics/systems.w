# Classic dynamical systems — the standard research benchmarks, each a
# Flow or MapSystem with analytic Jacobians where cheap. `.classic`
# factories carry the canonical chaotic parameter sets.

+ Lorenz < Flow
  -> new(sigma, rho, beta)
    @sigma = sigma
    @rho = rho
    @beta = beta
    self

  -> .classic
    Lorenz.new(~10.0, ~28.0, ~8.0 / ~3.0)

  -> dim
    3

  -> f(t, x)
    [@sigma * (x[1] - x[0]), x[0] * (@rho - x[2]) - x[1], x[0] * x[1] - @beta * x[2]]

  -> jac(t, x)
    [[~0.0 - @sigma, @sigma, ~0.0], [@rho - x[2], ~0.0 - ~1.0, ~0.0 - x[0]], [x[1], x[0], ~0.0 - @beta]]

+ Rossler < Flow
  -> new(a, b, c)
    @a = a
    @b = b
    @c = c
    self

  -> .classic
    Rossler.new(~0.2, ~0.2, ~5.7)

  -> dim
    3

  -> f(t, x)
    [~0.0 - x[1] - x[2], x[0] + @a * x[1], @b + x[2] * (x[0] - @c)]

  -> jac(t, x)
    [[~0.0, ~0.0 - ~1.0, ~0.0 - ~1.0], [~1.0, @a, ~0.0], [x[2], ~0.0, x[0] - @c]]

+ VanDerPol < Flow
  -> new(mu)
    @mu = mu
    self

  -> .classic
    VanDerPol.new(~1.0)

  -> dim
    2

  -> f(t, x)
    [x[1], @mu * (~1.0 - x[0] * x[0]) * x[1] - x[0]]

  -> jac(t, x)
    [[~0.0, ~1.0], [~0.0 - ~2.0 * @mu * x[0] * x[1] - ~1.0, @mu * (~1.0 - x[0] * x[0])]]

# Duffing oscillator x'' = γ·cos(ωt) − δ·x' − α·x − β·x³ (non-autonomous).
+ Duffing < Flow
  -> new(delta, alpha, beta, gamma, omega)
    @delta = delta
    @alpha = alpha
    @beta = beta
    @gamma = gamma
    @omega = omega
    self

  -> .classic
    Duffing.new(~0.3, ~0.0 - ~1.0, ~1.0, ~0.5, ~1.2)

  -> dim
    2

  -> f(t, x)
    [x[1], @gamma * Math.cos(@omega * t) - @delta * x[1] - @alpha * x[0] - @beta * x[0] * x[0] * x[0]]

  -> jac(t, x)
    [[~0.0, ~1.0], [~0.0 - @alpha - ~3.0 * @beta * x[0] * x[0], ~0.0 - @delta]]

# Planar double pendulum, state [θ1, θ2, ω1, ω2]; numeric Jacobian.
+ DoublePendulum < Flow
  -> new(m1, m2, l1, l2, g)
    @m1 = m1
    @m2 = m2
    @l1 = l1
    @l2 = l2
    @g = g
    self

  -> .classic
    DoublePendulum.new(~1.0, ~1.0, ~1.0, ~1.0, ~9.81)

  -> dim
    4

  -> f(t, x)
    th1 = x[0]
    th2 = x[1]
    w1 = x[2]
    w2 = x[3]
    d = th1 - th2
    cd = Math.cos(d)
    sd = Math.sin(d)
    mt = @m1 + @m2
    den = mt - @m2 * cd * cd
    a1 = (~0.0 - @m2 * @l1 * w1 * w1 * sd * cd + @m2 * @g * Math.sin(th2) * cd - @m2 * @l2 * w2 * w2 * sd - mt * @g * Math.sin(th1)) / (@l1 * den)
    a2 = (@m2 * @l2 * w2 * w2 * sd * cd + mt * (@g * Math.sin(th1) * cd + @l1 * w1 * w1 * sd - @g * Math.sin(th2))) / (@l2 * den)
    [w1, w2, a1, a2]

# Harmonic oscillator as the minimal Hamiltonian example:
# H = p²/2 + ω²·q²/2, accel(q) = −ω²·q.
+ HarmonicOscillator < HamiltonianSystem
  -> new(omega)
    @omega = omega
    self

  -> .classic
    HarmonicOscillator.new(~1.0)

  -> dim
    2

  -> accel(q)
    [~0.0 - @omega * @omega * q[0]]

  -> potential(q)
    ~0.5 * @omega * @omega * q[0] * q[0]

# -- discrete maps --

+ LogisticMap < MapSystem
  -> new(r)
    @r = r
    self

  -> .classic
    LogisticMap.new(~4.0)

  -> dim
    1

  -> step(x)
    [@r * x[0] * (~1.0 - x[0])]

  -> jac(x)
    [[@r * (~1.0 - ~2.0 * x[0])]]

+ Henon < MapSystem
  -> new(a, b)
    @a = a
    @b = b
    self

  -> .classic
    Henon.new(~1.4, ~0.3)

  -> dim
    2

  -> step(x)
    [~1.0 - @a * x[0] * x[0] + x[1], @b * x[0]]

  -> jac(x)
    [[~0.0 - ~2.0 * @a * x[0], ~1.0], [@b, ~0.0]]

# Chirikov standard map, state [θ, p], both wrapped into [0, 2π).
+ StandardMap < MapSystem
  -> new(k)
    @k = k
    self

  -> .classic
    StandardMap.new(~0.971635)

  -> dim
    2

  -> step(x)
    p = Dynamics.wrap2pi(x[1] + @k * Math.sin(x[0]))
    [Dynamics.wrap2pi(x[0] + p), p]

  -> jac(x)
    kc = @k * Math.cos(x[0])
    [[~1.0 + kc, ~1.0], [kc, ~1.0]]
