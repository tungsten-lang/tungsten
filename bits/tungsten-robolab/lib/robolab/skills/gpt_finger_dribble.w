# Untrained private prototype on the established fingered body.
# Four bounded corrections: elbow, wrist, finger MCP and finger PIP.
# Zero readout preserves the explicit DribbleV3 contraction backbone.
+ GptFingerDribbleSkill < DribbleV3Skill
  -> start(f, ctl)
    @gpt = GptTemporalResidual.new(self, [~0.18, ~0.15, ~0.20, ~0.20])
    super(f, ctl)

  -> before(f, ctl)
    name = ctl.track(@active.name).chunk_name
    phase = 0
    phase = 1 if name == "recover" || name == "wait" || name == "x_recover" || name == "x_wait" || name == "b_recover" || name == "b_wait"
    phase = 2 if name == "swing" || name == "x_swing" || name == "p_swing" || name == "b_swing"
    phase = 3 if name == "carry" || name == "x_carry" || name == "p_carry" || name == "b_carry"
    side_sign = ~1.0
    side_sign = ~-1.0 if @active.side == "l"
    @gpt.update(f, ctl, [f.at("ball_pos", 0) - @active.home[0], f.at("ball_pos", 1) * side_sign, f.at("ball_pos", 2), f.at("ball_vel", 0) / ~4.0, f.at("ball_vel", 1) * side_sign / ~4.0, f.at("ball_vel", 2) / ~5.0], phase)
    super(f, ctl)

  -> hand_fix(f, ctl, hand, mode)
    off = super(f, ctl, hand, mode)
    return off if off == nil
    r = @gpt.output
    joint_offset(off, hand.side + "_elbow", r[0])
    joint_offset(off, hand.side + "_wrist_flex", r[1])
    if @fingers
      joint_offset(off, hand.side + "_finger_mcp", r[2])
      joint_offset(off, hand.side + "_finger_pip", r[3])
    off
