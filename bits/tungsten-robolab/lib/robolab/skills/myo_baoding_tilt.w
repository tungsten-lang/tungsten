# MyoBaodingTilt: the baoding skill (MyoBaodingSkill: cup, posture map,
# rotation synergy, pacing) with the palm itself as an actuator. Tilting the
# upturned palm makes both balls roll downhill against the cupped fingers, so
# the pair lines up along the low wall; turning the tilt direction turns the
# pair with it (the way a bowl is gyrated to swirl two balls round each
# other).
#
# In the palm frame (the `balls` sensor's x, y), the wrist can lower the
# palm toward +y (flexion), toward -y (extension) and toward -x (pronation
# away from the fully supinated limit); +x is out of reach (the forearm is at
# its supination limit palm up), where the thumb has to act as the wall.
# The commanded roll direction is
#
#   theta = phi* + tilt_d + clamp(tilt_k * (phi* - phi), +-tilt_lim)
#
# (phi*: the targets' pair angle, phi: the balls'), eased in through the
# chunks' correction spring, and turned into joint offsets
#
#   flexion  += tilt_f * sin(theta)
#   pro_sup  += tilt_p * max(0, -cos(theta)) + tilt_px * max(0, cos(theta))
#
# on top of the cup's own tilt (ps0: the cup's pro_sup, flex bias). With
# every tilt gain at 0 the skill is the base skill with pro_sup at ps0.

+ MyoBaodingTiltSkill < MyoBaodingSkill
  -> start(frame, ctl)
    @ps0 = param("ps0", ~-1.5, ~-1.57, ~-0.9)
    @tilt_f = param("tilt_f", ~0.0, ~0.0, ~0.78)
    @tilt_p = param("tilt_p", ~0.0, ~0.0, ~0.6)
    @tilt_px = param("tilt_px", ~0.0, ~-0.3, ~0.3)
    @tilt_d = param("tilt_d", ~0.0, ~-3.2, ~3.2)
    @tilt_k = param("tilt_k", ~0.0, ~0.0, ~4.0)
    @tilt_lim = param("tilt_lim", ~0.8, ~0.0, ~1.6)
    # HOLD targets: the tilt fades to tilt_hold x its amplitude once the pair
    # is within hold_tol of its target (a level palm lets the cup hold them)
    @tilt_hold = param("tilt_hold", ~1.0, ~0.0, ~1.0)
    @theta = ~0.0
    super(frame, ctl)

  -> posture(v, stiff)
    p = super(v, stiff)
    p.set("pro_sup", @ps0, stiff)
    p

  # The base skill's posture map and synergy, plus the tilt.
  -> synergy_offsets(f)
    off = super(f)
    return off if off == nil
    pg = phi_goal(f)
    e = wrap(pg - phi(f))
    u = clamp(@tilt_k * e, ~0.0 - @tilt_lim, @tilt_lim)
    th = pg + @tilt_d + u
    @theta = th
    amp = ~1.0
    if @dir == 0
      ae = e
      ae = ~0.0 - e if e < ~0.0
      amp = @tilt_hold if ae < @hold_tol
    c = Math.cos(th)
    s = Math.sin(th)
    joint_offset(off, "flexion", amp * @tilt_f * s)
    dps = ~0.0
    dps = @tilt_p * (~0.0 - c) if c < ~0.0
    dps = @tilt_px * c if c > ~0.0
    joint_offset(off, "pro_sup", amp * dps)
    off
