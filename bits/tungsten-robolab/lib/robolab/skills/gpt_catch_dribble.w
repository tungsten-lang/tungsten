# Private round-nine comparison; inherited trunk choreography remains.
# Phase follows the active hand when explicitly enabled. No SDK changes.
+ GptCatchDribbleSkill < DribbleSkill
  -> start(f, ctl)
    @gpt = GptTemporalResidual.new(self, [~0.18, ~0.18, ~0.25, ~0.18])
    @active_phase = param("gpt_active_phase", ~0.0, ~0.0, ~1.0)
    super(f, ctl)

  -> before(f, ctl)
    track_name = "right"
    track_name = @active.name if @active_phase > ~0.5
    name = ctl.track(track_name).chunk_name
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
