# MyoKickSkill: round 10, the closed-loop penalty kick (agent P, 9/29).
#
# MyoSoccerV4Skill (unchanged) plus, behind the master switch `kc` (default off: every older params file replays V4 exactly, checked bit for
# bit on the noisy phase-1 dumps), closed-loop terms that act on the kick's swing and snap from the sensed positions of the toe and the ball.
#
# Why a new layer. Measured on the phase-1 kick (scratchpad/kick/LOG.md): (1) the swing's aim servo (k_ky) adds to the hip's adduction OFFSET,
# but the kicking hip's adduction sits on its 0.5236 rad limit for the whole swing, and the hip's rotation offsets go through the geometry's
# reference slopes, which in the swing posture give a torque of the wrong sign (rot_k +0.3 moved the achieved rotation by -0.07 rad); a
# joint-offset servo has no authority there. (2) The kicking leg's thigh and shank hit the plant leg's during the swing (1.4-2.6 kN in every
# kick, fast or slow). The terms below therefore work in TORQUE space: a requested torque about a joint is spread over the muscles that
# cross it, using the live moment arms (`sense_arms 1`, blocks arm_<joint>) and peak forces, exactly as Controller#split_torque does with the
# geometry's arms, and added as feed-forward drive. The parent's offsets keep the reference slopes (`@live` is switched off after the
# parent read it), so the open-loop kick is untouched.
#
# kc terms (swing and snap phases; w(gap) = a window on the toe's distance to the ball, gap = ball x - toe x):
#   lateral: e = toe y - (ball y + kc_y0 + aim kc_ya); torque about the kicking hip's rotation and adduction = kc_rk e + kc_rv v_y (and the
#            adduction likewise), clipped at +-kc_lim; v_y the toe's lateral velocity
#   heading: torque about the plant hip's rotation = kc_yk (yaw - kc_yaw0) + kc_ykd yaw rate (the pelvis turns about the plant foot)
#   vertical / speed: torque about the kicking knee and hip flexion = kc_zk (toe z - kc_z0) ... (see kc_law)

+ MyoKickSkill < MyoSoccerV4Skill
  -> read_params
    super
    @kc = switch_on("kc")
    # kr 1: after the touch (follow, land) the kicker balances on the plant foot with the single-leg routine's stance terms (cp4 on the sensed
    # centre of pressure, the twist-limited heading hold tlh; their parameters come from the hold's params file), instead of the phase-1
    # kick's open-loop follow-through: the falls after good kicks (19 % of the noisy kicks at +-0.001 rad) happen in the landing
    @kr = switch_on("kr")
    # the parent's hip offsets keep the reference slopes even with sense_arms on (the sensors are only for the kc terms; kr turns the live
    # arms on for the phases where the routine's terms run)
    @kc_arms = @live
    @live = false if @kc || @kr
    kc_params if @kc
    kr_params if @kr
    # kp 1: capture-point placement of the plant step. The phase-1 reach lands the plant foot on a fixed spot relative to the ball (IK from the measured hip);
    # the body, however, is FALLING onto that foot (COM 0.13-0.16 m outboard of the plant heel at the touch-down, 1 m/s forward), and the kick tolerates only +-2 cm
    # of lateral start offset. The landing spot is moved by the COM's velocity (seconds of travel) as the reach runs: kp_cpx forward, kp_cpy sideways.
    @kp = switch_on("kp")
    if @kp
      @kp_cpx = param("kp_cpx", ~0.0, ~-0.3, ~0.3)
      @kp_cpy = param("kp_cpy", ~0.0, ~-0.3, ~0.3)
      @kp_vy = ~0.0
    # kw 1 (with k4): the standing kick's wind-up and swing carry their own hip adduction and rotation targets for the kicking leg (the
    # routine's one-leg posture tucks the swing leg under the body: with the wind-up the kicking foot ends 0.35 m left of the ball's line)
    @kw = @k4 && switch_on("kw")
    kw_params if @kw
    # kt 1 (with kw): the kicking leg is torque-servoed through the wind-up, swing and snap (see kt_law)
    @kt = @kw && switch_on("kt")
    kt_params if @kt
    self

  -> start(frame, ctl)
    super(frame, ctl)
    @plant_x0 = @plant_x
    self

  -> plant_y
    return super + @kp_cpy * @kp_vy if @kp
    super

  -> kc_params
    # the window: on when the toe is closer than kc_gon to the ball, off inside kc_goff
    @kc_gon = param("kc_gon", ~0.7, ~0.3, ~1.0)
    @kc_gfull = param("kc_gfull", ~0.4, ~0.15, ~0.8)
    @kc_goff = param("kc_goff", ~0.15, ~0.05, ~0.3)
    @kc_lim = param("kc_lim", ~60.0, ~0.0, ~120.0)
    # the lateral target of the toe relative to the ball (and per aim side), and its gains
    @kc_y0 = param("kc_y0", ~-0.02, ~-0.1, ~0.1)
    @kc_ya = param("kc_ya", ~0.0, ~-0.1, ~0.1)
    @kc_rk = param("kc_rk", ~0.0, ~-800.0, ~800.0)
    @kc_rv = param("kc_rv", ~0.0, ~-120.0, ~120.0)
    @kc_ak = param("kc_ak", ~0.0, ~-800.0, ~800.0)
    @kc_av = param("kc_av", ~0.0, ~-120.0, ~120.0)
    # heading: the plant hip's rotation on the pelvis yaw
    @kc_yaw0 = param("kc_yaw0", ~0.7, ~0.3, ~1.1)
    @kc_yk = param("kc_yk", ~0.0, ~-200.0, ~200.0)
    @kc_ykd = param("kc_ykd", ~0.0, ~-40.0, ~40.0)
    # the toe's height above the ball's centre line and the vertical / forward speed channels (knee, hip flexion)
    @kc_z0 = param("kc_z0", ~-0.04, ~-0.1, ~0.05)
    @kc_zk = param("kc_zk", ~0.0, ~-800.0, ~800.0)
    @kc_zv = param("kc_zv", ~0.0, ~-120.0, ~120.0)
    # the speed channel: the toe's forward speed against the practised swing's (about 10.4 m/s per metre of travel: 8.75 m/s at 0.15 m from the
    # ball after starting 0.95 m behind it), scaled by kc_vs; the shortfall drives the hip's flexion and the knee's extension
    @kc_vs = param("kc_vs", ~1.0, ~0.5, ~1.5)
    @kc_fk = param("kc_fk", ~0.0, ~-100.0, ~100.0)
    @kc_kk = param("kc_kk", ~0.0, ~-100.0, ~100.0)
    # a steady torque about the plant hip's adduction while the toe is in the window (positive adducts): the kicking leg passes the plant leg with
    # 1.3-2.6 kN between the thighs and shanks in every phase-1 kick, and the slow kicks are the ones that stay in contact longest
    @kc_pa = param("kc_pa", ~0.0, ~-80.0, ~80.0)
    self

  # ---- the follow-through, landing (kr) ----------------------------------------------------

  # The plant leg's posture after the touch (the parent keeps the kick's: the leg 0.796 m hip to ankle, i.e. straight, with the drive that
  # carries the follow-through, which in the noisy kicks launches the body: both feet leave the ground 0.2 s after the touch and it lands
  # rotated and falls). The defaults are the parent's values.
  -> kr_params
    @kr_dx = param("kr_dx", @ks_dx, ~-0.2, ~0.3)
    @kr_dz = param("kr_dz", @ks_dz, ~0.5, ~0.8)
    @kr_pitch = param("kr_pitch", @ks_pitch, ~-0.4, ~0.4)
    @kr_add = param("kr_add", @add_pl, ~-0.5, ~0.3)
    @kr_fe = param("kr_fe", @fe_step, ~-0.8, ~0.0)
    # the follow-through braked in torque space: the kicking hip's flexion velocity and the knee's extension velocity are opposed (N m per rad/s),
    # from the touch until the right foot has landed, at most kr_blim N m
    @kr_bk = param("kr_bk", ~0.0, ~0.0, ~40.0)
    @kr_bkk = param("kr_bkk", ~0.0, ~0.0, ~40.0)
    @kr_blim = param("kr_blim", ~80.0, ~10.0, ~200.0)
    self

  -> kr_brake(f, ctl)
    return self if !f.has?("arm_hip_flexion_r")
    lim = @kr_blim
    vh = f.qd(body, "hip_flexion_r")
    kc_torque(ctl, f, "hip_flexion_r", clamp(~0.0 - @kr_bk * vh, ~0.0 - lim, lim)) if vh > ~0.0
    vk = f.qd(body, "knee_angle_r")
    kt_geo_torque(ctl, f, f.vec("q"), "knee_angle_r", clamp(~0.0 - @kr_bkk * vk, ~0.0 - lim, lim)) if vk < ~0.0
    self

  -> kr_plant(p)
    tleg(p, "l", @kr_dx, @kr_dz, @kr_pitch, @tilt_step)
    p.set("flex_extension", @kr_fe)
    p.set("hip_adduction_l", @kr_add)
    p

  -> add_after_touch(mv)
    return super(mv) if !@kr
    p = kr_plant(kick_stance(base_posture))
    wleg(p, "r", @th_fol, @knee_fol, @ankle_land)
    ch = chunk("follow", @t_follow, p, :follow, :l, :l).hold_until(Latch.after(@t_follow))
    ch.drive(drive_on(@kick_anta, @drv_brake))
    mv.add(ch)
    p = kr_plant(kick_stance(base_posture))
    wleg(p, "r", @th_land, @knee_land, @ankle_land)
    land = Latch.contact("r_foot", ~0.1)
    mv.add(chunk("land", ~0.2, p, :land, :l, :l).hold_until(land.after_min(~0.05), ~0.8))
    p = base_posture
    tleg(p, "l", @rec_ldx, @rec_dz, ~0.0, @tilt_step)
    tleg(p, "r", @rec_rdx, @rec_dz, ~0.0, @tilt_step)
    p.set("flex_extension", @fe_rec)
    mv.add(chunk("recover", @t_rec, p, :recover, :both, :mid).hold_until(Latch.after(~100.0)))
    mv

  -> kw_params
    @kw_add = param("kw_add", ~-0.1, ~-0.6, ~0.4)
    @kw_rot = param("kw_rot", ~0.0, ~-0.6, ~0.6)
    @kw_sadd = param("kw_sadd", ~-0.1, ~-0.6, ~0.4)
    @kw_srot = param("kw_srot", ~0.0, ~-0.6, ~0.6)
    self

  -> kt_params
    # the reflex gain left on the kicking leg's muscles while the servo drives it
    @kt_g = param("kt_g", ~0.25, ~0.0, ~1.0)
    # joint targets (rad): wind-up (c), swing (s), snap (n): hip flexion, adduction, rotation, knee, ankle
    @kt_c_hf = param("kt_c_hf", ~-0.3, ~-0.5, ~0.5)
    @kt_c_ha = param("kt_c_ha", ~-0.1, ~-0.6, ~0.4)
    @kt_c_hr = param("kt_c_hr", ~0.0, ~-0.6, ~0.6)
    @kt_c_kn = param("kt_c_kn", ~1.7, ~0.8, ~2.0)
    @kt_c_an = param("kt_c_an", ~-0.3, ~-0.6, ~0.4)
    @kt_s_hf = param("kt_s_hf", ~0.7, ~-0.2, ~1.5)
    @kt_s_ha = param("kt_s_ha", ~-0.1, ~-0.6, ~0.4)
    @kt_s_hr = param("kt_s_hr", ~0.0, ~-0.6, ~0.6)
    @kt_s_kn = param("kt_s_kn", ~1.5, ~0.5, ~2.0)
    @kt_s_an = param("kt_s_an", ~-0.3, ~-0.6, ~0.4)
    @kt_n_hf = param("kt_n_hf", ~0.8, ~-0.2, ~1.5)
    @kt_n_kn = param("kt_n_kn", ~0.1, ~0.0, ~1.0)
    # joint servo gains (N m per rad, N m s per rad): hip, knee, ankle
    @kt_kp_h = param("kt_kp_h", ~120.0, ~0.0, ~400.0)
    @kt_kd_h = param("kt_kd_h", ~8.0, ~0.0, ~40.0)
    @kt_kp_k = param("kt_kp_k", ~80.0, ~0.0, ~300.0)
    @kt_kd_k = param("kt_kd_k", ~5.0, ~0.0, ~30.0)
    @kt_kp_a = param("kt_kp_a", ~30.0, ~0.0, ~150.0)
    @kt_kd_a = param("kt_kd_a", ~2.0, ~0.0, ~15.0)
    # feed-forward torque bursts: hip flexion in the swing, knee extension in the snap (N m)
    @kt_ff_hf = param("kt_ff_hf", ~60.0, ~0.0, ~200.0)
    @kt_ff_kn = param("kt_ff_kn", ~60.0, ~0.0, ~250.0)
    @kt_lim = param("kt_lim", ~150.0, ~20.0, ~300.0)
    # the aim: hip adduction and rotation per metre of the toe's lateral error to the ball's line (+ kt_y0), through the swing and the snap
    @kt_y0 = param("kt_y0", ~0.0, ~-0.1, ~0.1)
    @kt_ka = param("kt_ka", ~0.0, ~-3.0, ~3.0)
    @kt_kr = param("kt_kr", ~0.0, ~-3.0, ~3.0)
    # the pelvis heading on the plant foot: torque about the plant hip's rotation (N m per rad and per rad/s of the pelvis yaw), limited by the
    # foot's torsional grip (about 60 N m at one body weight); it holds through the wind-up, swing and snap
    @kt_yaw0 = param("kt_yaw0", ~0.0, ~-0.6, ~0.6)
    @kt_yk = param("kt_yk", ~120.0, ~0.0, ~400.0)
    @kt_ykd = param("kt_ykd", ~20.0, ~0.0, ~80.0)
    @kt_ylim = param("kt_ylim", ~50.0, ~0.0, ~120.0)
    self

  # ---- the joint-space torque servo of the kicking leg (kt) -------------------------------
  #
  # The posture chunks turn joint targets into contraction targets with the geometry's additive length tables, which in the wound-back
  # and swing postures give hip adduction and rotation targets that do not hold (measured: the wound-back foot sat 0.34 m left of the
  # ball whatever kw_add was). Here the wound-back, swing and snap are servoed as torques: PD on each joint of the kicking leg toward
  # its target, plus feed-forward bursts, spread over the muscles by their live moment arms at the hip (arm_<joint> blocks) and the
  # geometry's arms at the knee and ankle (single-axis joints); the leg's reflex gain is turned down so the posture does not fight it.

  -> kt_phase
    return :cock if @phase == :b_lift
    return :swing if @phase == :swing
    return :snap if @phase == :snap
    :none

  -> kt_geo_torque(ctl, f, q, joint, tau)
    return self if tau > ~-0.01 && tau < ~0.01
    j = @g.joint(joint)
    return self if j == nil
    denom = ~0.0
    ms = @g.crossing(j)
    i = 0
    while i < ms.size
      m = ms[i]
      t = ~0.0 - @g.moment_arm(m, j, q) * @g.force(m)
      denom = denom + t * t if t * tau > ~0.0
      i += 1
    return self if denom <= ~0.0
    i = 0
    while i < ms.size
      m = ms[i]
      t = ~0.0 - @g.moment_arm(m, j, q) * @g.force(m)
      ctl.add_drive(m, tau * t / denom) if t * tau > ~0.0
      i += 1
    self

  -> kt_law(f, ctl)
    ph = kt_phase
    return self if ph == :none
    return self if !f.has?("arm_hip_rotation_r")
    hf = @kt_c_hf
    ha = @kt_c_ha
    hr = @kt_c_hr
    kn = @kt_c_kn
    an = @kt_c_an
    ffh = ~0.0
    ffk = ~0.0
    if ph == :swing
      hf = @kt_s_hf
      ha = @kt_s_ha
      hr = @kt_s_hr
      kn = @kt_s_kn
      an = @kt_s_an
      ffh = @kt_ff_hf
    if ph == :snap
      hf = @kt_n_hf
      ha = @kt_s_ha
      hr = @kt_s_hr
      kn = @kt_n_kn
      an = @kt_s_an
      ffk = ~0.0 - @kt_ff_kn
    if ph != :cock
      ey = f.at("r_toe_pos", 1) - (f.at("env_ball_pos", 1) + @kt_y0)
      ha = ha + @kt_ka * ey
      hr = hr + @kt_kr * ey
    lim = @kt_lim
    q = f.vec("q")
    th = f.q(body, "hip_flexion_r")
    kc_torque(ctl, f, "hip_flexion_r", clamp(@kt_kp_h * (hf - th) - @kt_kd_h * f.qd(body, "hip_flexion_r") + ffh, ~0.0 - lim, lim))
    kc_torque(ctl, f, "hip_adduction_r", clamp(@kt_kp_h * (ha - f.q(body, "hip_adduction_r")) - @kt_kd_h * f.qd(body, "hip_adduction_r"), ~0.0 - lim, lim))
    kc_torque(ctl, f, "hip_rotation_r", clamp(@kt_kp_h * (hr - f.q(body, "hip_rotation_r")) - @kt_kd_h * f.qd(body, "hip_rotation_r"), ~0.0 - lim, lim))
    kt_geo_torque(ctl, f, q, "knee_angle_r", clamp(@kt_kp_k * (kn - f.q(body, "knee_angle_r")) - @kt_kd_k * f.qd(body, "knee_angle_r") + ffk, ~0.0 - lim, lim))
    kt_geo_torque(ctl, f, q, "ankle_angle_r", clamp(@kt_kp_a * (an - f.q(body, "ankle_angle_r")) - @kt_kd_a * f.qd(body, "ankle_angle_r"), ~0.0 - lim, lim))
    yl = @kt_ylim
    kc_torque(ctl, f, "hip_rotation_l", clamp(~0.0 - (@kt_yk * (@yaw - @kt_yaw0) + @kt_ykd * f.at("pelvis_angvel", 2)), ~0.0 - yl, yl))
    g = @kt_g
    @leg_r.each ->(i) ctl.set_gain(i, g)
    self

  # ---- the standing kick (kw) ------------------------------------------------------------

  -> add_standing_kick(mv)
    return super(mv) if !@kw
    p = stance
    p.set("hip_adduction_l", p.get("hip_adduction_l") + @b_shift_add)
    p.set("hip_adduction_r", p.get("hip_adduction_r") - @b_shift_add)
    unl = Latch.test("k4_unl", ->(f, e, c) foot_load("r") < @b_unload && captured?(f, "l"))
    mv.add(chunk("k4_shift", @b_t_shift, p, :b_shift, :both, :l).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + @k4_tmax))
    p = one_leg_posture("l")
    wleg(p, "r", @th_back, @knee_back, @ankle_back)
    p.set("hip_adduction_r", @kw_add)
    p.set("hip_rotation_r", @kw_rot)
    mv.add(chunk("k4_cock", @k4_t_cock, p, :b_lift, :l, :l).hold_until(Latch.after(@k4_t_cock)))
    add_kick(mv)

  -> add_kick(mv)
    return super(mv) if !@kw || @side > ~0.5
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k1, @knee_k1, @ankle_k)
    p.set("hip_adduction_r", @kw_sadd)
    p.set("hip_rotation_r", @kw_srot)
    if @sd
      thigh = Latch.test("thigh", ->(f, e, c) f.q(body, "hip_flexion_r") > @hip_snap && f.at("env_ball_pos", 0) - f.at("r_toe_pos", 0) < @sn_d)
    else
      thigh = Latch.test("thigh", ->(f, e, c) f.q(body, "hip_flexion_r") > @hip_snap)
    ch = chunk("swing", @t_swing, p, :swing, :l, :l).hold_until(thigh, @t_swing * ~2.5)
    ch.drive(drive_on(@hip_flexors_r, @drv_hip))
    mv.add(ch)
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k2, @knee_k2, @ankle_k)
    p.set("hip_adduction_r", @kw_sadd)
    p.set("hip_rotation_r", @kw_srot)
    hit = Latch.test("touch", ->(f, e, c) f.get("ball_touch") > ~0.5)
    ch = chunk("snap", @t_snap, p, :snap, :l, :l).hold_until(hit, @t_snap * ~2.5)
    d = drive_on(@knee_ext_r, @drv_knee)
    @hip_flexors_r.each ->(i) d[i] = @drv_hip
    ch.drive(d)
    mv.add(ch)
    add_after_touch(mv)

  # ---- the torque channel -----------------------------------------------------------

  # Torque tau (N m) about `joint` as drive on the muscles crossing it: each muscle's torque per unit activation is -arm * peak force (the
  # live moment arm, dL/dq at the measured posture); the drive is the minimum-norm activation over the muscles whose torque has the sign of
  # tau (Controller#split_torque with live arms).
  -> kc_torque(ctl, f, joint, tau)
    return self if tau > ~-0.01 && tau < ~0.01
    nm = "arm_" + joint
    return self if !f.has?(nm)
    sc = f.schema
    o = sc.offset(nm)
    oi = sc.offset(nm + "_ids")
    w = sc.width(nm)
    v = f.values
    denom = ~0.0
    i = 0
    while i < w
      m = v[oi + i].to_i
      t = ~0.0 - v[o + i] * @g.force(m)
      denom = denom + t * t if t * tau > ~0.0
      i += 1
    return self if denom <= ~0.0
    i = 0
    while i < w
      m = v[oi + i].to_i
      t = ~0.0 - v[o + i] * @g.force(m)
      ctl.add_drive(m, tau * t / denom) if t * tau > ~0.0
      i += 1
    self

  # ---- the swing's closed loop --------------------------------------------------------

  # 0 -> 1 as the toe closes from kc_gon to kc_gfull behind the ball, back to 0 by kc_goff
  -> kc_window(gap)
    up = clamp((@kc_gon - gap) / (@kc_gon - @kc_gfull), ~0.0, ~1.0)
    dn = clamp((gap - @kc_goff) / ~0.1, ~0.0, ~1.0)
    up * dn

  -> kc_law(f, ctl)
    return self if !f.has?("arm_hip_rotation_r")
    gap = f.at("env_ball_pos", 0) - f.at("r_toe_pos", 0)
    w = kc_window(gap)
    return self if w <= ~0.0
    ey = f.at("r_toe_pos", 1) - (f.at("env_ball_pos", 1) + @kc_y0 + @aim * @kc_ya)
    vy = f.at("r_toe_vel", 1)
    lim = @kc_lim
    kc_torque(ctl, f, "hip_rotation_r", w * clamp(@kc_rk * ey + @kc_rv * vy, ~0.0 - lim, lim))
    kc_torque(ctl, f, "hip_adduction_r", w * clamp(@kc_ak * ey + @kc_av * vy, ~0.0 - lim, lim))
    yr = f.at("pelvis_angvel", 2)
    kc_torque(ctl, f, "hip_rotation_l", w * clamp(@kc_yk * (@yaw - @kc_yaw0) + @kc_ykd * yr, ~0.0 - lim, lim))
    ez = f.at("r_toe_pos", 2) - @kc_z0
    vz = f.at("r_toe_vel", 2)
    dv = @kc_vs * ~10.4 * (~0.95 - gap) - f.at("r_toe_vel", 0)
    tz = w * clamp(@kc_zk * ez + @kc_zv * vz + @kc_kk * dv, ~0.0 - lim, lim)
    kc_torque(ctl, f, "knee_angle_r", tz)
    kc_torque(ctl, f, "hip_flexion_r", w * clamp(@kc_fk * dv, ~0.0 - lim, lim))
    kc_torque(ctl, f, "hip_adduction_l", w * @kc_pa)
    self

  -> v4_phase?
    return true if @kr && (@phase == :follow || @phase == :land)
    super

  -> before(frame, ctl)
    super(frame, ctl)
    @live = @kc_arms && (@phase == :follow || @phase == :land) if @kr
    if @kp
      @kp_vy = frame.at("com_vel", 1)
      @plant_x = @plant_x0 + @kp_cpx * frame.at("com_vel", 0)
    self

  -> after(frame, ctl)
    super(frame, ctl)
    kc_law(frame, ctl) if @kc && (@phase == :swing || @phase == :snap)
    kt_law(frame, ctl) if @kt
    kr_brake(frame, ctl) if @kr && (@phase == :follow || @phase == :land) && (@kr_bk > ~0.0 || @kr_bkk > ~0.0)
    self
