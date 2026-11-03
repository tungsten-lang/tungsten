# Arm-only residual contraction synergies. The base crossover choreography
# is retained; the residual never moves the legs or adds a trunk pump.
+ GptDribbleSkill < DribbleSkill
  -> start(f, ctl)
    @gpt = GptTemporalResidual.new(self, [~0.18, ~0.18, ~0.25, ~0.18])
    super(f, ctl)

  -> before(f, ctl)
    name = ctl.track("right").chunk_name
    phase = 0
    phase = 1 if name == "wait" || name == "recover"
    phase = 2 if name == "x_swing" || name == "x_carry"
    phase = 3 if name == "swing" || name == "carry"
    @gpt.update(f, ctl, [f.at("ball_pos", 0), f.at("ball_pos", 1), f.at("ball_pos", 2), f.at("ball_vel", 0) / ~4.0, f.at("ball_vel", 1) / ~4.0, f.at("ball_vel", 2) / ~5.0], phase)
    super(f, ctl)

  -> hand_fix(f, ctl, hand, mode)
    off = super(f, ctl, hand, mode)
    return off if off == nil
    r = @gpt.output
    joint_offset(off, hand.side + "_shoulder_flex", r[0])
    joint_offset(off, hand.side + "_shoulder_abd", r[1])
    joint_offset(off, hand.side + "_elbow", r[2])
    joint_offset(off, hand.side + "_wrist_flex", r[3])
    off
