# Easing curves and springs: the time-shaping half of the control plane.
#
# Easing maps normalised chunk time t in [0, 1] to progress e(t) with
# e(0) = 0 and e(1) = 1. The set mirrors pmndrs/math's time/easing module,
# plus `min_jerk`, the quintic 10t^3 - 15t^4 + 6t^5 that Flash & Hogan (1985)
# showed matches human point-to-point movement: it minimises integrated
# squared jerk, so velocity rises and falls as a smooth bell with zero
# velocity and acceleration at both ends.

+ Easing
  -> .clamp01(t)
    return ~0.0 if t < ~0.0
    return ~1.0 if t > ~1.0
    t

  -> .min_jerk(t)
    t * t * t * (t * (t * ~6.0 - ~15.0) + ~10.0)

  # d/dt of min_jerk: 30 t^2 (1 - t)^2, peaking at 1.875 when t = 0.5.
  -> .min_jerk_rate(t)
    u = ~1.0 - t
    ~30.0 * t * t * u * u

  -> .sine_in(t)
    ~1.0 - Math.cos(t * ~1.5707963267948966)

  -> .sine_out(t)
    Math.sin(t * ~1.5707963267948966)

  -> .sine_in_out(t)
    ~0.5 - ~0.5 * Math.cos(t * ~3.141592653589793)

  -> .cubic_in(t)
    t * t * t

  -> .cubic_out(t)
    u = ~1.0 - t
    ~1.0 - u * u * u

  -> .cubic_in_out(t)
    return ~4.0 * t * t * t if t < ~0.5
    u = ~2.0 - ~2.0 * t
    ~1.0 - u * u * u * ~0.5

  -> .quint_in(t)
    t * t * t * t * t

  -> .quint_out(t)
    u = ~1.0 - t
    ~1.0 - u * u * u * u * u

  -> .quint_in_out(t)
    return ~16.0 * t * t * t * t * t if t < ~0.5
    u = ~2.0 - ~2.0 * t
    ~1.0 - u * u * u * u * u * ~0.5

  -> .expo_in(t)
    return ~0.0 if t <= ~0.0
    Math.pow(~2.0, ~10.0 * t - ~10.0)

  -> .expo_out(t)
    return ~1.0 if t >= ~1.0
    ~1.0 - Math.pow(~2.0, ~-10.0 * t)

  -> .circ_out(t)
    u = t - ~1.0
    Math.sqrt(~1.0 - u * u)

  # Named lookup so chunks can carry their easing as a symbol.
  -> .apply(name, t)
    t = clamp01(t)
    case name
      when :linear then return t
      when :min_jerk then return min_jerk(t)
      when :sine_in then return sine_in(t)
      when :sine_out then return sine_out(t)
      when :sine_in_out then return sine_in_out(t)
      when :cubic_in then return cubic_in(t)
      when :cubic_out then return cubic_out(t)
      when :cubic_in_out then return cubic_in_out(t)
      when :quint_in then return quint_in(t)
      when :quint_out then return quint_out(t)
      when :quint_in_out then return quint_in_out(t)
      when :expo_in then return expo_in(t)
      when :expo_out then return expo_out(t)
      when :circ_out then return circ_out(t)
      when :step then return ~1.0
    raise "unknown easing [name]"

# Quintic Hermite basis: the C2 keyframe spline. A segment of T seconds from
# the state (p0, v0, a0) to (p1, v1, a1), position, velocity and acceleration
# at each end, is, at s = elapsed / T in [0, 1],
#
#   p(s) = p0 + (p1 - p0) h5(s) + T (v0 h1(s) + v1 h4(s)) + T^2 (a0 h2(s) + a1 h3(s))
#
# h5 is min_jerk, so a segment whose end velocities and accelerations are
# zero is exactly the min-jerk profile. Each of h1..h4 is zero at both ends
# with a unit first (h1, h4) or second (h2, h3) derivative at its own end and
# zero derivatives elsewhere. `basis(s)` is [h1, h2, h3, h4].
+ Quintic
  -> .basis(s)
    s2 = s * s
    s3 = s2 * s
    s4 = s3 * s
    s5 = s4 * s
    h1 = s - ~6.0 * s3 + ~8.0 * s4 - ~3.0 * s5
    h2 = ~0.5 * s2 - ~1.5 * s3 + ~1.5 * s4 - ~0.5 * s5
    h3 = ~0.5 * s3 - s4 + ~0.5 * s5
    h4 = ~0.0 - ~4.0 * s3 + ~7.0 * s4 - ~3.0 * s5
    [h1, h2, h3, h4]

# A damped spring integrated with the exact analytic solution (stable at any
# step), after pmndrs/math's time/spring: `smooth_time` is roughly how long it
# takes to reach the target (omega = 2 / smooth_time) and `ratio` is the
# damping ratio (1 = critical, no overshoot; below 1 overshoots, and ratios
# above 1 are treated as critical). SpringVector runs one spring per
# component over a plain Array of floats; robolab uses it to ease real-time
# corrections so a re-aimed swing bends smoothly instead of jumping.
+ SpringVector
  ro :value
  ro :velocity
  -> new(n, @smooth_time, @ratio)
    @ratio = ~1.0 if @ratio > ~1.0
    @value = (0...n).map -> ~0.0
    @velocity = (0...n).map -> ~0.0

  # Change the smoothing time (a chunk that states its own spring time).
  -> retime(smooth_time)
    @smooth_time = smooth_time
    self

  -> smooth_time
    @smooth_time

  -> reset(values)
    i = 0
    while i < @value.size
      @value[i] = values[i]
      @velocity[i] = ~0.0
      i += 1
    self

  -> step(target, dt)
    omega = ~2.0 / (@smooth_time < ~0.0001 ? ~0.0001 : @smooth_time)
    pp = ~1.0
    pv = ~0.0
    vp = ~0.0
    vv = ~1.0
    if (@ratio - ~1.0).abs < ~0.0001
      e = Math.exp(~0.0 - omega * dt)
      pp = e * (~1.0 + omega * dt)
      pv = e * dt
      vp = ~0.0 - e * omega * omega * dt
      vv = e * (~1.0 - omega * dt)
    else
      za = ~0.0 - omega * @ratio
      wd = omega * Math.sqrt((~1.0 - @ratio * @ratio).abs)
      e = Math.exp(za * dt)
      c = Math.cos(wd * dt)
      s = Math.sin(wd * dt)
      pp = e * (c - za * s / wd)
      pv = e * s / wd
      vp = ~0.0 - e * omega * omega * s / wd
      vv = e * (c + za * s / wd)
    i = 0
    while i < @value.size
      d = @value[i] - target[i]
      v = @velocity[i]
      @value[i] = target[i] + pp * d + pv * v
      @velocity[i] = vp * d + vv * v
      i += 1
    @value
