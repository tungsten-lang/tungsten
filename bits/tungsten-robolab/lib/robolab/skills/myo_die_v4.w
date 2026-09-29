# MyoDieV4: die reorientation (MyoDieV3Skill: cup, greedy finger flips and
# palm tilts) with a closed-loop finish, opt-in by `wfin` (0: MyoDieV3Skill).
#
# The flips leave the die within 0.52 rad of its goal in 7% of episodes and
# within 0.26 rad in 2%, but the fine chunk only holds the cup, so the die
# drifts back (final angle 0.12 rad worse than the best on average) and the
# 15 deg window is never held. The finish treats the hand as the die's
# carrier: in the die task's palm frame the wrist and forearm joints turn
# about nearly orthogonal axes (measured on the model: flexion +x, pro_sup
# +y, deviation +z), so the remaining rotation vector (`rot_vec`, palm
# frame) maps straight onto them. While the fine chunk runs and the angle is
# under `w_on`, the wrist offsets integrate it,
#
#   d/dt [flexion, pro_sup, deviation] = [kw_x w_x, kw_y w_y, kw_z w_z]
#
# clamped to +-w_lim (pro_sup can only pronate: the palm-up posture sits at
# its supination limit), and reset whenever the fine chunk starts again.
# Integral, not proportional: as the die comes round the error vanishes but
# the wrist stays turned. The position error still acts through the base
# skill's kpos terms.
#
# The die must not roll on while the wrist carries it: traced, a flip that
# brings it to 0.14 rad overshoots and the loose cup lets it roll back out
# to 0.9 rad within 0.4 s. So the fine chunk also closes the hand on the die
# (`c_<group>`: joint-group offsets over the cup, a clamp), and a catch latch
# (`c_on` > 0) cuts any flip or tilt short and enters the fine chunk as soon
# as the die is within c_on of its goal.

+ MyoDieV4Skill < MyoDieV3Skill
  -> start(frame, ctl)
    @wfin = param("wfin", ~0.0, ~0.0, ~1.0) > ~0.5
    @kw = [param("kw_x", ~1.5, ~-8.0, ~8.0), param("kw_y", ~1.5, ~-8.0, ~8.0), param("kw_z", ~1.5, ~-8.0, ~8.0)]
    @w_lim = param("w_lim", ~0.4, ~0.05, ~0.8)
    @w_on = param("w_on", ~0.8, ~0.1, ~3.2)
    @wq = [~0.0, ~0.0, ~0.0]
    @w_last = ~-1.0
    gn = ["dev", "flex", "cabd", "cflex", "mp", "ip", "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]
    @camp = gn.map ->(n) param("c_" + n, ~0.0, ~-0.8, ~0.8)
    @c_on = param("c_on", ~0.0, ~0.0, ~1.2)
    @t_stop = param("t_stop", ~9.0, ~0.3, ~9.0)
    super(frame, ctl)

  -> choose(f)
    return super(f) if f.t < @t_stop
    @next = "fine"
    "fine"

  # Catch: a flip or tilt that has brought the die within c_on ends early.
  -> after(f, ctl)
    super(f, ctl)
    return nil if !@wfin || @c_on <= ~0.0
    name = ctl.track("hand").chunk_name
    return nil if !name.starts_with?("flip") && !name.starts_with?("tilt")
    w = f.vec("rot_vec")
    ctl.track("hand").jump(ctl, f, "fine") if Math.sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) < @c_on
    nil

  -> fine_offsets(f)
    off = super(f)
    return off if !@wfin
    # a new fine chunk (the previous call was not the last tick): restart
    if f.t - @w_last > ~1.5 * @dt
      @wq = [~0.0, ~0.0, ~0.0]
    @w_last = f.t
    w = f.vec("rot_vec")
    ang = Math.sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2])
    if ang < @w_on
      k = 0
      while k < 3
        @wq[k] = clamp(@wq[k] + @kw[k] * w[k] * @dt, ~0.0 - @w_lim, @w_lim)
        k += 1
      @wq[1] = ~-0.07 if @wq[1] < ~-0.07
    joint_offset(off, "flexion", @wq[0])
    joint_offset(off, "pro_sup", @wq[1])
    joint_offset(off, "deviation", @wq[2])
    add_groups(off, @camp)
    off

  # Joint offsets for a 14-group vector (the base skill's groups).
  -> add_groups(off, v)
    names = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion"]
    i = 0
    while i < 6
      joint_offset(off, names[i], v[i]) if v[i] != ~0.0
      i += 1
    k = 0
    while k < 4
      d = (k + 2).to_s
      joint_offset(off, "mcp" + d + "_flexion", v[6 + 2 * k]) if v[6 + 2 * k] != ~0.0
      if v[7 + 2 * k] != ~0.0
        joint_offset(off, "pm" + d + "_flexion", v[7 + 2 * k])
        joint_offset(off, "md" + d + "_flexion", v[7 + 2 * k] * ~0.7)
      k += 1
    off
