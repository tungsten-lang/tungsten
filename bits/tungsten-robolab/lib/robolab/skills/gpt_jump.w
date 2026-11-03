# Search baseline: phase-specific contraction synergies; learned challenger:
# the same bounded synergies driven by a causal temporal-convolution head.
+ GptJumpSkill < SearchJumpSkill
  -> start(f, ctl)
    @gpt = GptTemporalResidual.new(self, [~0.6, ~0.6, ~0.4, ~0.6])
    super(f, ctl)

  -> before(f, ctl)
    name = ctl.track("body").chunk_name
    phase = 0
    phase = 1 if name == "extend"
    phase = 2 if name == "flight"
    phase = 3 if name == "land" || name == "stand"
    @gpt.update(f, ctl, [f.at("com_pos", 2), f.com_vx / ~3.0, f.at("com_vel", 2) / ~3.0, f.torso_pitch, f.torso_pitch_rate / ~5.0, phase / ~3.0], phase)

  -> gpt_offset(off)
    r = @gpt.output
    ["l_", "r_"].each ->(side)
      joint_offset(off, side + "hip_flex", r[0])
      joint_offset(off, side + "knee", r[1])
      joint_offset(off, side + "shoulder_flex", r[3])
    joint_offset(off, "spine_flex", r[2])
    off

  -> balance(f)
    gpt_offset(super(f))

  -> flight_correction(f)
    gpt_offset(super(f))

  -> land_correction(f)
    gpt_offset(super(f))
