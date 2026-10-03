# RunGearY: RunGearX (RunGear with the opt-in trunk mechanisms k_arm_p, k_arm_d, k_swh, lean_v) plus opt-in mechanisms of sprint 5
# (agent S5, scratchpad/sprint5/LOG.md: the fall-free labelled beyond-human sprinter). Every mechanism is a tunable that defaults to 0; with
# all of them 0 this is RunGearXSkill exactly (checked on chain D's starts), and each has gear twins g2_X .. gN_X like every tunable.
# run_gear.w and run_gearx.w are untouched, so every existing champion replays bit for bit.
#
#   k_pp, k_pr   pitch-feedback foot placement: in flight the landing (swing) hip's command is offset by +(k_pp x pitch error + k_pr x pitch
#                rate), the sign being free (boxes are symmetric): a trunk pitching forward lands the foot further ahead (a braking
#                reaction at the foot behind the COM turns the trunk back), the stride-by-stride, deadbeat-like trunk correction of a
#                runner's foot placement, where RunGearX's mechanisms act on the pelvis through the hips and arms only
#   p_pp, k_pp3  refinements of the placement law: the error is measured from a reference lean p_pp (the steady running lean error, so that the
#                feedback acts on the stride-to-stride fluctuation and does not add a constant braking offset), and a cubic term k_pp3 x e^3
#                concentrates the correction on large excursions: offset = k_pp x e + k_pp3 x e^3 + k_pr x pitch rate, e = pitch - torso_des - p_pp
#   k_cat, p_cat catch step: only when the trunk pitch passes +-p_cat (absolute, rad) the landing hip is offset by k_cat x the excess (forward lean
#                lands the foot further ahead, backward lean less far): zero in ordinary running (the pitch there stays inside +-0.4) and a
#                strong reach in the 0.3 s before the runs that fall pitch past 0.5 rad
#   k_sps, k_spds  the spine servo of RunRI (k_sp, k_spd) with either sign (RunRI's guard `<= 0` switches a negative value off): the spine
#                offset -k_sps x (torso pitch - torso_des) - k_spds x pitch rate, in every phase; S5 measured that a positive k_sp destabilises
#                the sprint (0.6: 44 % falls, 0.264: 15 %, 0: 5 % at the top gear), so the opposite sign is worth a scan
#   k_swhs, k_arm_ps, k_arm_ds  RunGearX's swing-hip synergy (k_swh) and arm counter-rotation (k_arm_p, k_arm_d) with either sign (RunGearX
#                guards them with `> 0`, so a negative value is off there); added on top of RunGearX's own terms with the same formulas
#   t_blend      trunk set point blend at a gear switch: the set point steps when the gear changes (lean 0.06 -> -0.11 at the handover of
#                S4's chains), which kicks the trunk servo; with t_blend > 0 the old set point is kept as an offset that decays with the
#                time constant t_blend (the NEW gear's value) after the switch; 0 = the step, RunGearX exactly
#   sw_r, sw_wait  gated gear switch: the switch to the next gear (at the first flight after the speed reaches g<k>_v_on) is postponed while the
#                trunk pitch RATE is larger than sw_r (rad/s, absolute; this gear's value; 99 = off, RunGear exactly), for at most sw_wait
#                seconds: the runs that fall right after the 1->2 switch had three times the pitch rate of the others at the crossing
#   k_bal        gain of the ankle strategy of the stand and lean chunks (RunSkill's `balance`: ankle offset = 2.0 x COM error + 0.4 x COM speed, in rad)
#                as a multiplier, 1 = RunSkill exactly: the 1-2 % of starts that collapse backward in the first 2 s are the ones whose COM starts
#                0.06 m behind the feet and stays there under the stock gain
#   t_blendk     blend of the per-tick GAINS at a gear switch: torso_kp, torso_kd, k_fly, k_fly_d, k_swc, hip_lead, comp_fly, k_swh, k_arm_p, k_arm_d
#                keep their old gear's value as a decaying offset (time constant t_blendk, the NEW gear's value; 0 = the step, RunGearX exactly).
#                S5 measured that the handover falls follow the size of the parameter step at the switch (the swing-hip synergy k_swh alone
#                steps 0.29 -> 1.87 at the 1-2 switch, a swing-hip kick of ~0.3 rad at the pitch error of a stride)
#   k_bals       COM feedback of the stand / lean chunks on the SPINE (added to the ankle strategy): spine offset = -k_bals x (COM error), so a COM
#                behind its target flexes the trunk forward (rad per m; 0 = RunSkill exactly). The starts that collapse backward in the first
#                2 s begin with the COM 4 cm behind the feet (13076: -0.042 m against +0.052 m for a normal start) and their ankles sit at the
#                dorsiflexion limit (-37 deg) without moving the COM: the ankle strategy runs out of authority, the trunk has some left
#   lean_vn      the speed-dependent trunk set point of the README with either sign: torso_des += lean_vn x clamp(v - lean_v0, 0, 3)
#                (RunGearX's lean_v ignores values below 0, and its box starts at 0)
#   k_pi, p_tau  integral trim of the trunk set point: the torso pitch low-passed at p_tau seconds is compared with the set point and the
#                difference integrated at k_pi per second (the set point moves against a persistent lean error), clamped at +-0.4 rad;
#                it removes a slow drift of the mean lean that the proportional servo leaves

+ RunGearYSkill < RunGearXSkill
  -> read_params
    super
    @k_pp = param("k_pp", ~0.0, ~-1.5, ~1.5)
    @k_pr = param("k_pr", ~0.0, ~-0.5, ~0.5)
    @p_pp = param("p_pp", ~0.0, ~-0.3, ~0.6)
    @k_pp3 = param("k_pp3", ~0.0, ~-20.0, ~20.0)
    @k_cat = param("k_cat", ~0.0, ~-4.0, ~4.0)
    @k_sps = param("k_sps", ~0.0, ~-3.0, ~3.0)
    @t_blend = param("t_blend", ~0.0, ~0.0, ~4.0)
    @t_blendk = param("t_blendk", ~0.0, ~0.0, ~4.0)
    @k_bal = param("k_bal", ~1.0, ~0.3, ~8.0)
    @k_bals = param("k_bals", ~0.0, ~0.0, ~8.0)
    @sw_r = param("sw_r", ~99.0, ~0.0, ~100.0)
    @sw_wait = param("sw_wait", ~1.0, ~0.0, ~3.0)
    @k_swhs = param("k_swhs", ~0.0, ~-3.0, ~3.0)
    @k_arm_ps = param("k_arm_ps", ~0.0, ~-8.0, ~8.0)
    @k_arm_ds = param("k_arm_ds", ~0.0, ~-1.0, ~1.0)
    @k_spds = param("k_spds", ~0.0, ~-1.0, ~1.0)
    @p_cat = param("p_cat", ~0.4, ~0.15, ~0.8)
    @lean_vn = param("lean_vn", ~0.0, ~-0.3, ~0.3)
    @k_pi = param("k_pi", ~0.0, ~-1.0, ~1.0)
    @p_tau = param("p_tau", ~0.5, ~0.1, ~3.0)
    self

  -> start(frame, ctl)
    @p_lp = ~0.0
    @trim = ~0.0
    @blend0 = ~0.0
    @old_des = ~0.0
    @sw_pending = false
    @t_ready = ~-1.0
    @bw = ~0.0
    @kb_pending = false
    super(frame, ctl)

  -> gear_next(f, c, ctl, land)
    return nil if @gear >= @gears
    von = ~99.0
    key = "g" + (@gear + 1).to_s + "_v_on"
    von = @params[key] if @params.key?(key)
    return nil if @v_f < von
    if @sw_r < ~90.0
      @t_ready = f.t if @t_ready < ~0.0
      rate = f.torso_pitch_rate
      rate = ~0.0 - rate if rate < ~0.0
      return nil if rate > @sw_r && f.t - @t_ready < @sw_wait
    @t_ready = ~-1.0
    switch_gear(f, ctl, @gear + 1)
    land

  -> balance(f, target)
    return super(f, target) if @k_bal == ~1.0 && @k_bals == ~0.0
    e = f.com_x - feet_x(f) - target
    dq = @k_bal * (~2.0 * e + ~0.4 * f.com_vx)
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    joint_offset(off, "spine_flex", ~0.0 - @k_bals * e) if @k_bals != ~0.0
    off

  -> switch_gear(f, ctl, k)
    @old_des = @torso_des
    @sw_pending = true
    o_kp = @torso_kp
    o_kd = @torso_kd
    o_kf = @k_fly
    o_kfd = @k_fly_d
    o_swc = @k_swc
    o_hl = @hip_lead
    o_cf = @comp_fly
    o_swh = @k_swh
    o_arp = @k_arm_p
    o_ard = @k_arm_d
    super(f, ctl, k)
    if @t_blendk > ~0.0
      @bo_kp = o_kp
      @bo_kd = o_kd
      @bo_kf = o_kf
      @bo_kfd = o_kfd
      @bo_swc = o_swc
      @bo_hl = o_hl
      @bo_cf = o_cf
      @bo_swh = o_swh
      @bo_arp = o_arp
      @bo_ard = o_ard
      @bn_kp = @torso_kp
      @bn_kd = @torso_kd
      @bn_kf = @k_fly
      @bn_kfd = @k_fly_d
      @bn_swc = @k_swc
      @bn_hl = @hip_lead
      @bn_cf = @comp_fly
      @bn_swh = @k_swh
      @bn_arp = @k_arm_p
      @bn_ard = @k_arm_d
      @bw = ~1.0

  -> before(frame, ctl)
    super(frame, ctl)
    if @sw_pending
      @sw_pending = false
      @blend0 = @old_des - @torso_des if @t_blend > ~0.0
    if @bw > ~0.001
      @bw = @bw - @bw * (ctl.dt / (@t_blendk + ctl.dt))
      @torso_kp = @bn_kp + (@bo_kp - @bn_kp) * @bw
      @torso_kd = @bn_kd + (@bo_kd - @bn_kd) * @bw
      @k_fly = @bn_kf + (@bo_kf - @bn_kf) * @bw
      @k_fly_d = @bn_kfd + (@bo_kfd - @bn_kfd) * @bw
      @k_swc = @bn_swc + (@bo_swc - @bn_swc) * @bw
      @hip_lead = @bn_hl + (@bo_hl - @bn_hl) * @bw
      @comp_fly = @bn_cf + (@bo_cf - @bn_cf) * @bw
      @k_swh = @bn_swh + (@bo_swh - @bn_swh) * @bw
      @k_arm_p = @bn_arp + (@bo_arp - @bn_arp) * @bw
      @k_arm_d = @bn_ard + (@bo_ard - @bn_ard) * @bw
    if @blend0 != ~0.0
      @blend0 = @blend0 - @blend0 * (ctl.dt / (@t_blend + ctl.dt))
      @blend0 = ~0.0 if @blend0 < ~0.001 && @blend0 > ~-0.001
      @torso_des = @torso_des + @blend0
    return self if @lean_vn == ~0.0 && @k_pi == ~0.0
    @torso_des = @torso_des + @lean_vn * clamp(@v_f - @lean_v0, ~0.0, ~3.0) if @lean_vn != ~0.0
    if @k_pi != ~0.0
      k = ctl.dt / (@p_tau + ctl.dt)
      @p_lp = @p_lp + (frame.torso_pitch - @p_lp) * k
      @trim = clamp(@trim + @k_pi * (@p_lp - @torso_des) * ctl.dt, ~-0.4, ~0.4)
      @torso_des = @torso_des - @trim
    self

  -> stride_correction(f, ctl, st, sw, phase)
    off = super(f, ctl, st, sw, phase)
    if @k_sps != ~0.0 || @k_spds != ~0.0
      joint_offset(off, "spine_flex", ~0.0 - @k_sps * (f.torso_pitch - @torso_des) - @k_spds * f.torso_pitch_rate)
    if @k_swhs != ~0.0 || @k_arm_ps != ~0.0 || @k_arm_ds != ~0.0
      e2 = f.torso_pitch - @torso_des
      if @k_arm_ps != ~0.0 || @k_arm_ds != ~0.0
        dq = ~0.0 - @k_arm_ps * e2 - @k_arm_ds * f.torso_pitch_rate
        joint_offset(off, "l_shoulder_flex", dq)
        joint_offset(off, "r_shoulder_flex", dq)
      joint_offset(off, sw + "hip_flex", ~0.0 - @k_swhs * e2) if @k_swhs != ~0.0 && phase != :flight
    return off if phase != :flight || (@k_pp == ~0.0 && @k_pr == ~0.0 && @k_pp3 == ~0.0 && @k_cat == ~0.0)
    err = f.torso_pitch - @torso_des - @p_pp
    d = @k_pp * err + @k_pp3 * err * err * err + @k_pr * f.torso_pitch_rate
    if @k_cat != ~0.0
      pitch = f.torso_pitch
      d = d + @k_cat * (clamp(pitch - @p_cat, ~0.0, ~2.0) - clamp(~0.0 - pitch - @p_cat, ~0.0, ~2.0))
    joint_offset(off, sw + "hip_flex", d)
    off
