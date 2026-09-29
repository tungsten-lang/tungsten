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

  -> activation(i, target, c, cdot, drive, gain)
    a = drive + gain * (@kp[i] * (target - c) - @kd[i] * cdot)
    return ~0.0 if a < ~0.0
    return ~1.0 if a > ~1.0
    a
