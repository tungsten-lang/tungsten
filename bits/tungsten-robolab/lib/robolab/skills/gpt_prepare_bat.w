# Private prototype: permit the existing bounded residual during the
# inherited preparatory correction callbacks, before pitch aiming starts.
# Defaults off; disabled behavior delegates exactly to frozen GptBatSkill.
# No raw activations, keyframe replacement, new sensors or SDK changes.
+ GptPrepareBatSkill < GptBatSkill
  -> start(f, ctl)
    @gpt_prepare = param("gpt_prepare", ~0.0, ~0.0, ~1.0)
    super(f, ctl)

  -> aim_offsets(wp)
    off = super(wp)
    return off if off != nil || @gpt_prepare < ~0.5
    off = zeros
    r = @gpt.output
    joint_offset(off, "spine_rot", r[0])
    joint_offset(off, "spine_flex", r[1])
    ["l_", "r_"].each ->(side)
      joint_offset(off, side + "elbow", r[2])
      joint_offset(off, side + "wrist_flex", r[3])
    off
