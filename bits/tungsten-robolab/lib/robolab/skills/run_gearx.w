# RunGearX: RunGear (the gears of the P95 sprint) with opt-in TRUNK mechanisms, for the extended-stance gear of
# scratchpad/sprint2/LOG.md. Every mechanism is a tunable that defaults to 0; with all of them 0 this is RunGearSkill
# exactly (checked on the P95 champion's arena starts), and each has gear twins g2_X .. gN_X like every tunable.
#
# No ideal actuator: a body's trunk can only be pushed on by the stance hip, the swing hip and the arms (the spine is
# internal to the trunk), so the mechanisms use those.
#
#   k_arm_p, k_arm_d   arm counter-rotation: both shoulders' pose is offset by -(k_arm_p x pitch error + k_arm_d x pitch
#                      rate); arms swinging back are a forward-pitching torque's opposite on the trunk (reaction torque
#                      of the shoulder muscles on the torso), so a trunk that pitches forward is answered by arm extension
#   k_swh              swing-hip synergy in the stance phases: the swing hip's command is offset by -k_swh x pitch error
#                      (the swing thigh's hip-extension torque reacts on the pelvis as a backward-pitching torque)
#   lean_v, lean_v0    a forward-lean set point that grows with the filtered speed: torso_des += lean_v x clamp(v - lean_v0, 0, 3)

+ RunGearXSkill < RunGearSkill
  -> read_params
    super
    @k_arm_p = param("k_arm_p", ~0.0, ~0.0, ~8.0)
    @k_arm_d = param("k_arm_d", ~0.0, ~0.0, ~1.0)
    @k_swh = param("k_swh", ~0.0, ~0.0, ~3.0)
    @lean_v = param("lean_v", ~0.0, ~0.0, ~0.3)
    @lean_v0 = param("lean_v0", ~7.5, ~5.0, ~9.0)
    self

  -> before(frame, ctl)
    super(frame, ctl)
    return self if @lean_v <= ~0.0
    @torso_des = @torso_des + @lean_v * clamp(@v_f - @lean_v0, ~0.0, ~3.0)
    self

  -> stride_correction(f, ctl, st, sw, phase)
    off = super(f, ctl, st, sw, phase)
    return off if @k_arm_p <= ~0.0 && @k_arm_d <= ~0.0 && @k_swh <= ~0.0
    err = f.torso_pitch - @torso_des
    if @k_arm_p > ~0.0 || @k_arm_d > ~0.0
      dq = ~0.0 - @k_arm_p * err - @k_arm_d * f.torso_pitch_rate
      joint_offset(off, "l_shoulder_flex", dq)
      joint_offset(off, "r_shoulder_flex", dq)
    joint_offset(off, sw + "hip_flex", ~0.0 - @k_swh * err) if @k_swh > ~0.0 && phase != :flight
    off
