# Bounded target corrections ride the existing aiming spring and preserve
# every keyframe, velocity-continuous chunk and feed-forward drive.
+ GptBatSkill < BatSkill
  -> start(f, ctl)
    @gpt = GptTemporalResidual.new(self, [~0.16, ~0.16, ~0.20, ~0.20])
    super(f, ctl)

  -> before(f, ctl)
    name = ctl.track("arms").chunk_name
    phase = 0
    phase = 1 if name == "load" || name == "swing"
    phase = 2 if name == "whip" || name == "release" || name == "drive"
    phase = 3 if name == "follow" || name == "let_go" || name == "finish"
    p = predict(f)
    @gpt.update(f, ctl, [p[0], p[1], p[2], f.torso_pitch, f.torso_pitch_rate / ~5.0, phase / ~3.0], phase)
    super(f, ctl)

  -> aim_offsets(wp)
    off = super(wp)
    return off if off == nil
    r = @gpt.output
    joint_offset(off, "spine_rot", r[0])
    joint_offset(off, "spine_flex", r[1])
    ["l_", "r_"].each ->(side)
      joint_offset(off, side + "elbow", r[2])
      joint_offset(off, side + "wrist_flex", r[3])
    off
