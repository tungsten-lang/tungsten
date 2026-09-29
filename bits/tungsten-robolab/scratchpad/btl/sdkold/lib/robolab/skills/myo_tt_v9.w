# MyoTTV9: round-8 options for the table-tennis skill (MyoTTV8Skill), each
# opt-in by params; with every switch at 0 it is MyoTTV8Skill (and so the
# round-5 champions).
#
#   ft_amp   the face-follow probe (a measurement, not a player): the aim
#            law's normal gets a pitch trim of ft_amp times a pseudo-random
#            number in [-1, 1] fixed per serve (from the ball's first seen
#            position), and ft_yaw times another in yaw; the trims are
#            reported in the l8 line's learned-output slots 5 and 6, so the
#            reached face's change per aimed change (the follow ratio) is a
#            regression slope on serves the trims do not otherwise predict

#   fh_stiff >= 0: the forehand arm's own co-contraction (the shared stiff,
#            0.11, with the arm's reflex gain asks ~1.4 activation of every
#            forearm muscle: the servo's offsets change nothing until an error
#            beats the saturation); the ready, stroke, follow and hold chunks
#            of the arm track are posed with it (the trunk keeps stiff)
#   fh_gain  the forehand arm chunks' reflex gain multiplier (1: as before)
#   rn       a learned residual on the forearm and wrist (1 on): per side, a
#            small network (9 inputs, 12 tanh units, 3 outputs, weights
#            rw0..rw317, side s from 159 s) maps what the skill sees each tick
#            (the aim law's normal less the pad's, y and z; the pad's height
#            error to the crossing; the time to contact; the pad's and the
#            aim's normals, y and z; 1) to joint offsets on the forearm's
#            rotation, the wrist's deviation and flexion (tanh times rn_lim
#            rad), added to the servo's corrections from rn_t0 s to contact;
#            trained by evolution strategies across training serves

+ MyoTTV9Skill < MyoTTV8Skill
  -> read_params
    super
    @fh_stiff = param("fh_stiff", ~-1.0, ~-1.0, ~0.3)
    @fh_gain = param("fh_gain", ~1.0, ~0.2, ~3.0)
    @rn = param("rn", ~0.0, ~0.0, ~1.0)
    @rn_lim = param("rn_lim", ~0.3, ~0.0, ~1.0)
    @rn_t0 = param("rn_t0", ~0.2, ~0.0, ~0.6)
    @rw = (0...318).map ->(i) param("rw[i]", ~0.0, ~-10.0, ~10.0)
    @rn_q = [~0.0, ~0.0, ~0.0]
    @ft_amp = param("ft_amp", ~0.0, ~0.0, ~0.4)
    @ft_yaw = param("ft_yaw", ~0.0, ~0.0, ~0.4)
    @ft_u = nil

  -> start(frame, ctl)
    super(frame, ctl)
    if @fh_stiff >= ~0.0 || @fh_gain != ~1.0
      st = @stiff
      st = @fh_stiff if @fh_stiff >= ~0.0
      p = posture(@trunk_q, @q_ready, st)
      ctl.track("arm").movement.chunks.each ->(c)
        if c.name == "ready" || c.name == "stroke" || c.name == "follow" || c.name == "hold"
          c.pose(p)
          c.gain(@fh_gain)
    nil

  # the stroke's goal is posed with the forehand's own co-contraction too
  -> stroke_due(f)
    return super(f) if @fh_stiff < ~0.0 || @side == 2
    keep = @stiff
    @stiff = @fh_stiff
    r = super(f)
    @stiff = keep
    r

  -> before(f, ctl)
    if (@ft_amp > ~0.0 || @ft_yaw > ~0.0) && @ft_u == nil
      x = f.at("env_ball_pos", 0) * ~7919.0 + f.at("env_ball_pos", 1) * ~104729.0 + f.at("env_ball_vel", 2) * ~1299.7
      u1 = x - x.floor
      y = u1 * ~9973.0 + ~0.61803
      u2 = y - y.floor
      @ft_u = [~2.0 * u1 - ~1.0, ~2.0 * u2 - ~1.0]
      @lm_out[5] = @ft_yaw * @ft_u[1]
      @lm_out[6] = @ft_amp * @ft_u[0]
    super(f, ctl)
    rn_update(f) if @rn > ~0.5
    nil

  # ---- the learned forearm and wrist residual (rn) ------------------------------------

  -> after(f, ctl)
    super(f, ctl)
    nil

  -> rn_update(f)
    s = @side
    return nil if s == 0 || @plan == nil || @hit || f.t < @rn_t0
    n = pad_normal(f)
    a = aim_normal(@plan)
    pc = pad_center(f)
    x = [a[1] - n[1], a[2] - n[2], @plan[2] + @z_bias - pc[2], @plan[0] - ~0.1, n[1], n[2], a[1], a[2], ~1.0]
    b = 159 * (s - 1)
    h = []
    j = 0
    while j < 12
      acc = @rw[b + 108 + j]
      i = 0
      while i < 9
        acc = acc + @rw[b + 9 * j + i] * x[i]
        i += 1
      h.push(Math.tanh(acc))
      j += 1
    k = 0
    while k < 3
      acc = @rw[b + 156 + k]
      j = 0
      while j < 12
        acc = acc + @rw[b + 120 + 12 * k + j] * h[j]
        j += 1
      @rn_q[k] = @rn_lim * Math.tanh(acc)
      k += 1
    nil

  -> servo_offsets(f)
    return super(f) if @rn < ~0.5 || @off_tick == f.t
    off = super(f)
    joint_move(off, "pro_sup", @rn_q[0])
    joint_move(off, "deviation", @rn_q[1])
    joint_move(off, "flexion", @rn_q[2])
    off

  -> aim_normal(plan)
    n = super(plan)
    return n if @ft_u == nil || @lm > ~0.5
    m = [n[0], n[1] + @lm_out[5], n[2] + @lm_out[6]]
    r = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
    [m[0] / r, m[1] / r, m[2] / r]
