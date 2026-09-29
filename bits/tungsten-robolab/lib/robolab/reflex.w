# Reflex: the spinal layer that turns commanded contractions into
# activations, after Feldman's equilibrium-point (lambda) model.
#
# A commanded contraction c* sets the muscle's threshold length. When the
# muscle is longer than that (measured c below c*) the stretch reflex
# recruits it in proportion to the error, and a velocity term damps
# lengthening. The descending command therefore never names forces: it
# shifts thresholds, and the body's own reflexes and mechanics find the
# forces. Antagonist pairs make this a position-and-stiffness servo;
# co-contraction raises stiffness without moving the equilibrium.
#
#   a_i = clamp(drive_i + g * (kp_i * (c*_i - c_i) - kd_i * cdot_i) + ki_i * I_i, 0, 1)
#
# The optional integral I_i accumulates (c*_i - c_i) dt, clamped to +-limit
# (anti-windup), so a held posture loses its steady-state sag under gravity,
# the way postural tone slowly adapts. It is zero unless set_integral is used.
#
# Optional velocity-referenced damping (set_velocity_reference, off by
# default): muscle i damps its contraction velocity about w_i times the
# commanded one, kd_i * (cdot_i - w_i * cdot*_i), so a movement that commands
# a velocity (a quintic knot, a fast stroke) is tracked instead of braked:
# the plain term brakes every fast movement, the agonist's shortening and the
# antagonist's stretch alike. The controller passes cdot*, the rate of the
# muscle's target (command plus correction), clamped to +-VREF_MAX per
# second. With w_i = 0 (the default) the activation is exactly the plain
# one above.

+ Reflex
  ro :kp
  ro :kd
  -> new(n, kp, kd)
    @kp = (0...n).map -> kp
    @kd = (0...n).map -> kd
    @ki = (0...n).map -> ~0.0
    @limit = (0...n).map -> ~0.0
    @acc = (0...n).map -> ~0.0
    @integrating = false
    @vref = (0...n).map -> ~0.0
    @referencing = false

  # Velocity-referenced damping (see the header) for these muscles, weight w
  # (1: damp about the commanded velocity; 0: the plain damping).
  -> set_velocity_reference(indices, w)
    indices.each -> @vref[item] = w
    @referencing = true
    self

  -> referencing?
    @referencing

  -> .vref_max
    ~10.0

  -> set_integral(indices, ki, limit)
    indices.each ->(m)
      @ki[m] = ki
      @limit[m] = limit
    @integrating = true
    self

  -> integrating?
    @integrating

  # Advance muscle i's error integral by dt and return ki * integral.
  -> integral(i, target, c, dt)
    return ~0.0 if @ki[i] == ~0.0
    a = @acc[i] + (target - c) * dt
    a = @limit[i] if a > @limit[i]
    a = ~0.0 - @limit[i] if a < ~0.0 - @limit[i]
    @acc[i] = a
    @ki[i] * a

  -> reset_integral
    i = 0
    while i < @acc.size
      @acc[i] = ~0.0
      i += 1
    self

  -> set_gains(indices, kp, kd)
    indices.each ->
      @kp[item] = kp
      @kd[item] = kd
    self

  # tdot: the target's contraction rate (1/s), used only by muscles with a
  # velocity reference.
  -> activation(i, target, c, cdot, drive, gain, tdot = ~0.0)
    a = ~0.0
    if @vref[i] == ~0.0
      a = drive + gain * (@kp[i] * (target - c) - @kd[i] * cdot)
    else
      a = drive + gain * (@kp[i] * (target - c) - @kd[i] * (cdot - @vref[i] * tdot))
    return ~0.0 if a < ~0.0
    return ~1.0 if a > ~1.0
    a
