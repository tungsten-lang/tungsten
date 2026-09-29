# MyoSoccerV4Skill: round-4 soccer. Turn by stepping, never by pivoting on a
# planted foot. MyoSoccerV3Skill (lib/robolab/skills/myo_soccer_v3.w,
# unchanged) plus, each behind a params-file switch whose tunables are only
# declared when it is on (so every older params file replays as V3):
#
#   tlh 1     twist-limited heading hold: the loaded feet's hips hold the
#             pelvis heading as a torque servo whose twist never exceeds what
#             each foot's grip can take; the rest goes to the trunk's
#             counter-rotation and the swing leg (see tlh)
#   fyaw 1    every swing foot is turned in the air to its landing heading
#             (the hip's rotation servoing the foot's measured yaw), so it
#             lands already along the heading the body is turning to
#   hg 1      the stance hip kept off its extension limit (a flexion offset
#             below hg_min)
#   ap4 1     (with ap3 1) the approach as a turning gait: each step's foot
#             lands turned by at most s4_turn from the stance foot toward the
#             walking heading (toward the kick spots while far, the final
#             heading s4_hf near them) and placed in that heading's frame, so
#             the body turns a little each step (see next3)
#   bcatch 1  (with bal; bsettle / bplace refine it) the single-leg routine
#             catches its falls by stepping: a hold ends early when the capture point leaves the
#             stance foot toward the swing side (bc_in), the swing foot is put
#             down and the routine goes on with the other leg, alternating
#             until each leg has stood bc_cap seconds (the trial counts the
#             seconds on each leg while the kicker stays up)
#   cp4 1     (with sense_arms) single support balances on the sensed centre
#             of pressure: the capture point (COM + velocity / omega) in the
#             stance foot's frame sets a COP target (cp + cp_k (cp - ref),
#             clipped to the sole), the subtalar and ankle servo the measured
#             COP to it, what the sole cannot take goes to the stance hip's
#             ab/adduction (the hip strategy), and the reference drifts
#             (cp_ki) so the COP stays centred; replaces the round-3 ankle,
#             subtalar and hip-adduction terms (see cp4)
#   rk4 1     the round-4 terms (tlh, fyaw) in the parent's running kick
#             (set, shift, lift, reach, cock, swing, snap; the side-foot
#             variant too): the run-up holds the heading rk_head, the plant
#             foot lands turned to rk_plant, the plant hip holds rk_kick
#             through the swing; the parent's open-loop heading terms
#             (s_kyaw_run, s_kyaw, s_plant_rot) are off
#   in4 1     (with ap4 and inside) the angled approach and a standing inside-of-the-foot
#             kick: the approach walks to spots in the in4_head frame (the
#             plant foot beside the ball, the kicking foot behind), then the
#             weight onto the plant foot, the kicking leg wound back turned
#             out, and V3's inside swing (see add_inside4)
#   sense_arms 1  (read by the task too) every hip offset goes through the
#             muscles' live moment arms instead of the geometry's reference
#             slopes (see joint_offset); live_axes 1 / 2 keeps the reference
#             slopes for adduction and flexion / adduction only
#
# The feet's grip against twisting, measured on the model (condim-3 contacts:
# two capsules along the sole 4 cm apart, an ellipsoid, two toe capsules;
# friction 1, no torsional friction): the ground's torque about the centre of
# pressure is at most sum_i mu N_i |r_i| ~ 60-68 N m at one body weight
# (805 N, an effective radius of ~8 cm), proportionally less on a lightly
# loaded foot, and a few N m on the toes alone. A hip twist above that spins
# the foot. In the round-3 single-leg champion the stance foot does NOT spin:
# the stance hip's rotation is so compliant (~25 N m / rad under the
# reflexes) that the pelvis swings to the hip's rotation limit (0.7 rad) at
# 1-15 N m. So the heading hold can be several times stiffer, as long as its
# twist stays inside the grip.
#
# Why the pelvis yaws on one leg (measured): the stance hip sits at its
# extension limit (-0.53 rad), where the gluteus medius's posterior fibres
# (the abductors single support needs) rotate the hip externally with 15-40
# N m per unit activation and the anterior fibres, the internal rotators of a
# flexed hip, turn external too (glmed1: -29 to +37 N m over the stance range,
# glmax1/2 -58 to +23). The controller's geometry is additive (every joint
# swept alone at the reference posture), so its rotation offsets activate
# muscles that, at this posture, rotate the other way: in the round-3 hold a
# commanded internal rotation drove glmed1, glmin1 and TFL to 0.9 activation
# and produced -9 N m (external). Only iliacus and adductor longus keep their
# (internal) sign everywhere, ~12 N m together.
#
# Signs (measured on the model): hip rotation + turns the toes in on both
# legs; a hip rotation torque tau_j on the left hip turns the pelvis with
# +tau_j about +z (CCW from above), on the right hip with -tau_j.

+ MyoSoccerV4Skill < MyoSoccerV3Skill
  -> start(frame, ctl)
    super(frame, ctl)
    @fy_prev = {"l" => foot_yaw(frame, "l"), "r" => foot_yaw(frame, "r")}
    @fy_rate = {"l" => ~0.0, "r" => ~0.0}
    # each foot's natural toe-out relative to the pelvis (the reset posture)
    y0 = Math.atan2(frame.at("pelvis_fwd", 1), frame.at("pelvis_fwd", 0))
    @toe0 = {"l" => wrap(foot_yaw(frame, "l") - y0), "r" => wrap(foot_yaw(frame, "r") - y0)}
    @k_rot = {"l" => rot_stiffness("l"), "r" => rot_stiffness("r")}
    @inv_range = (0...@n).map ->(i) ~1.0 / (@g.range(i)[1] - @g.range(i)[0])
    @tl_excess = ~0.0
    @tl_torque = ~0.0
    @dbg = ~0.0
    @dbg = @params["dbg"] if @params.key?("dbg")
    if @k4
      bx = frame.at("env_ball_pos", 0)
      by = frame.at("env_ball_pos", 1)
      @g3_l = [bx + @k4_pdx, by + @k4_pdy]
      @g3_r = [bx + @k4_rdx, by + @k4_rdy]
    if @in4
      bx = frame.at("env_ball_pos", 0)
      by = frame.at("env_ball_pos", 1)
      c = Math.cos(@in4_head)
      sn = Math.sin(@in4_head)
      @g3_l = [bx + @in4_pdx * c - @in4_pdy * sn, by + @in4_pdx * sn + @in4_pdy * c]
      @g3_r = [bx + @in4_rdx * c - @in4_rdy * sn, by + @in4_rdx * sn + @in4_rdy * c]
      @s4_hf = @in4_head
      @s4_ref = @in4_head
    ctl.emit("dbg:k_rot:" + @k_rot["l"].to_s + ":" + @k_rot["r"].to_s + ":toe0:" + @toe0["l"].to_s + ":" + @toe0["r"].to_s) if @dbg > ~0.5
    self

  -> read_params
    super
    @tlh = switch_on("tlh")
    @live = switch_on("sense_arms")
    # which hip axes go through the live arms: 1 rotation, 2 + flexion (the
    # axes whose gluteal arms flip over the stance range), 3 + adduction
    @live_axes = ~3.0
    @live_axes = param("live_axes", ~3.0, ~1.0, ~3.0) if @live
    @fyaw = switch_on("fyaw")
    @hg = switch_on("hg")
    @ap4 = @ap3 && switch_on("ap4")
    @in4 = @ap4 && @inside && switch_on("in4")
    tlh_params if @tlh
    fyaw_params if @fyaw
    hg_params if @hg
    ap4_params if @ap4
    in4_params if @in4
    @rk4 = switch_on("rk4")
    rk4_params if @rk4
    # sd 1: the kick's snap (the knee whip) waits until the kicking foot's toes
    # are sn_d metres or less behind the ball: under joint noise the swing's
    # timing moves by 0.1 s (measured: the plant lands 30 ms later, the hip
    # takes 0.12 s longer to reach hip_snap, the ball is struck 0.18 s later
    # and leaves at 4 m/s instead of 12), and a whip fired by the clock then
    # meets the ball at the wrong phase; fired by the geometry it meets it
    # where it was practised
    @sd = switch_on("sd")
    @sn_d = ~0.0
    @sn_d = param("sn_d", ~0.35, ~0.0, ~0.9) if @sd
    # k6 1 (with bal-style params: bcatch, cp4, tlh, sense_arms): the kick's
    # run-up from the routine's robust right-leg stance. The phase-1 run-up's
    # own shift and lift are open loop and amplify the reset's joint noise
    # (measured: +-0.001 rad halves the goals); the routine's set, shift onto
    # the right foot, lift and hold converge to the same one-leg state whatever
    # the noise (the hold is an attractor), and the parent's reach, plant and
    # swing then start from a repeatable state (see k6_movement)
    @k6 = switch_on("k6")
    @k6_t_hold = ~0.3
    @k6_t_hold = param("k6_t_hold", ~0.3, ~0.05, ~2.0) if @k6
    # k7 1 (with k6): a lean between the hold and the reach. The phase-1 run-up
    # reaches with the COM already 0.24 m ahead of the stance foot and falling
    # (1 m/s forward, 0.86 m/s down at the plant): a controlled fall, initiated
    # in double support by the COM leaning ahead of the feet. From the centred
    # hold the reach cannot land the foot 0.75 m ahead. The lean moves cp4's
    # fore-aft capture-point reference forward to k7_lean metres beyond the
    # stance foot's centre over k7_t_lean seconds (past the toes the body falls
    # forward: the sole cannot take it), and the reach starts when the COM is
    # k7_go ahead of the foot or after k7_t_max
    @k7 = @k6 && switch_on("k7")
    @k7_ref = ~0.0
    if @k7
      @k7_lean = param("k7_lean", ~0.15, ~0.0, ~0.45)
      @k7_t_lean = param("k7_t_lean", ~0.3, ~0.05, ~1.0)
      @k7_go = param("k7_go", ~0.15, ~0.0, ~0.4)
      @k7_t_max = param("k7_t_max", ~0.8, ~0.2, ~2.0)
    # k4 1 (with ap4, not in4): the approach walks the plant (left) foot to
    # k4_pdx, k4_pdy from the ball and the kicking foot to k4_rdx, k4_rdy,
    # then a standing kick: the weight onto the plant foot, the kicking leg
    # wound back on the one-leg posture (cp4 balances it), and the parent's
    # swing and snap from there (see add_standing_kick)
    @k4 = @ap4 && !@in4 && switch_on("k4")
    # k4_cp 1 (with k4): the standing kick's swing, snap, follow-through and
    # landing keep the routine's stance terms (tlh, fyaw, cp4, live arms) on
    # the plant leg: the parent's own single-support balance (tuned for the
    # run-up's lunge) lets the standing body fall at the swing
    @k4_cp = @k4 && switch_on("k4_cp")
    if @k4
      @k4_pdx = param("k4_pdx", ~-0.2, ~-0.6, ~0.1)
      @k4_pdy = param("k4_pdy", ~0.17, ~0.05, ~0.35)
      @k4_rdx = param("k4_rdx", ~-0.45, ~-0.9, ~-0.15)
      @k4_rdy = param("k4_rdy", ~-0.05, ~-0.25, ~0.1)
      @k4_tmax = param("k4_tmax", ~1.0, ~0.2, ~3.0)
      @k4_t_cock = param("k4_t_cock", ~0.4, ~0.1, ~1.2)
    @bcatch = @bal && switch_on("bcatch")
    bcatch_params if @bcatch
    # ks5 1 (with ap3 for the routine's gains): the kick from a settled
    # stance: the routine's set until the stance is still and square
    # (bsettle's latch), then the parent's run-up (shift, lift, the plant
    # step IK-placed beside the ball) and kick
    @ks5 = @ap3 && switch_on("ks5")
    bs_params if @ks5 || @k6
    @cp4 = @live && switch_on("cp4")
    if @cp4
      cp4_params
      @sb_kax = ~0.0
      @sb_kst = ~0.0
      @sb_kha = ~0.0
      @sb_ki = ~0.0
    # (the support threshold, when no round-3 single-support block declared it)
    @sb_ds_load = param("sb_ds_load", ~0.1, ~0.02, ~0.4) if @sb_ds_load == nil && (@tlh || @fyaw)
    # the swing foot's heading is fyaw's (the round-3 open-loop term off)
    @s3_yawr = ~0.0 if @ap3 && @fyaw
    # the kick's heading is the hold's (the round-3 plant-hip servo off)
    if @tlh && @in4
      @in_kyaw = ~0.0
      @in_kyawd = ~0.0
    if @tlh
      # the hold replaces the round-3 heading servos (single and double
      # support)
      @sb_kyaw = ~0.0
      @sb_kyawd = ~0.0
      @sb_kyp = ~0.0
      @sb_kypd = ~0.0
      @b_kyaw = ~0.0
      @b_kyawd = ~0.0
      @b_kyp = ~0.0
      @b_kypd = ~0.0
    self

  -> tlh_params
    # the heading PD as a pelvis torque (N m per rad, per rad/s)
    @tl_kp = param("tl_kp", ~60.0, ~0.0, ~250.0)
    @tl_kd = param("tl_kd", ~12.0, ~0.0, ~60.0)
    # the grip: twist limit per body weight of load on a foot (N m), cut
    # back while the foot is spinning (to zero at tl_spin rad/s)
    @tl_cap = param("tl_cap", ~40.0, ~5.0, ~70.0)
    @tl_spin = param("tl_spin", ~1.5, ~0.2, ~6.0)
    @tl_cfrac = param("tl_cfrac", ~0.7, ~0.2, ~1.0)
    # the hip's own position stiffness cancelled (1: the stance hip's rotation
    # is a pure torque source, its twist bounded by the grip)
    @tl_cancel = param("tl_cancel", ~1.0, ~0.0, ~1.0)
    # scales the model-derived rotation stiffness used to turn torque into
    # an equilibrium shift
    @tl_kscale = param("tl_kscale", ~1.0, ~0.3, ~3.0)
    # the reference: world heading (0), or the pelvis square to the loaded
    # feet (1: the stance foot's heading less its natural toe-out)
    @tl_wfoot = param("tl_wfoot", ~1.0, ~0.0, ~1.0)
    # the torque the grip cannot take: the trunk's counter-rotation (lumbar
    # axial rotation, rad per N m) and the swing hip's rotation
    @tl_ktr = param("tl_ktr", ~0.0, ~-0.02, ~0.02)
    @tl_ksw = param("tl_ksw", ~0.0, ~-0.02, ~0.02)
    @tl_max = param("tl_max", ~0.6, ~0.1, ~1.5)
    @tl_cfull = ~0.0
    @tl_cfull = param("tl_cfull", ~1.0, ~0.0, ~1.0) if switch_on("tl_cf")
    # tl_latch 1: in single support the reference is the heading the pelvis
    # had when the swing foot left the ground (a long stance holds where it
    # is instead of creeping toward the foot's heading)
    @tl_latch = switch_on("tl_latch")
    @tl_yaw0 = nil
    self

  -> ap4_params
    # the final heading (0: facing the goal), the turn per step relative to
    # the stance foot, the walking heading's limit from the final one, and
    # the distances (spots' midpoint) over which it blends from the walking
    # heading (far) to the final one (near)
    @s4_hf = param("s4_hf", ~0.0, ~-0.8, ~0.8)
    @s4_turn = param("s4_turn", ~0.3, ~0.05, ~0.6)
    @s4_hmax = param("s4_hmax", ~0.5, ~0.0, ~1.2)
    @s4_far = param("s4_far", ~0.6, ~0.2, ~1.5)
    @s4_near = param("s4_near", ~0.2, ~0.0, ~0.6)
    @s4_htol = param("s4_htol", ~0.15, ~0.03, ~0.5)
    @s4_max = param("s4_max", ~14.0, ~2.0, ~24.0)
    # the step in the new heading's frame, from the stance foot: at most
    # s4_ahead ahead, s4_back behind
    @s4_ahead = param("s4_ahead", ~0.22, ~0.05, ~0.45)
    @s4_back = param("s4_back", ~0.1, ~0.0, ~0.3)
    @s4_ref = @s4_hf
    @step_head = @s4_hf
    # s4set 1: the steps wait for a still double stance (both feet above
    # s4_load, the COM slower than s4_v; at most s4_tmax beyond the step's
    # own times) before the next shift
    @s4set = switch_on("s4set")
    if @s4set
      @s4_load = param("s4_load", ~0.3, ~0.1, ~0.5)
      @s4_v = param("s4_v", ~0.06, ~0.01, ~0.2)
      @s4_tmax = param("s4_tmax", ~1.0, ~0.2, ~3.0)
      @s4_knee = param("s4_knee", ~0.0, ~-0.2, ~0.8)
      @s4_tmove = param("s4_tmove", ~0.0, ~0.0, ~2.0)
      @s4_hip = param("s4_hip", ~0.0, ~-0.3, ~0.5)
    self

  -> bcatch_params
    @bc_in = param("bc_in", ~0.04, ~0.0, ~0.12)
    @bc_cap = param("bc_cap", ~3.05, ~1.0, ~3.5)
    # the weight shift's time limit beyond b_t_shift (the lift waits for the
    # capture point over the stance foot and the swing foot unloaded)
    @bc_tmax = param("bc_tmax", ~1.0, ~0.2, ~6.0)
    # (and when it leaves the foot outward by bc_out: the swing foot put down
    # anyway, a double stance the hips can pull the COM back over; off by
    # default)
    @blv = switch_on("blv")
    @b_vlat = param("b_vlat", ~0.03, ~0.005, ~0.2) if @blv
    @bc_out = ~1.0
    @bc_out = param("bc_out", ~0.05, ~0.01, ~0.2) if switch_on("bcout")
    # bramp 1: the set's ramp from the reset posture to the stance takes
    # b_t_ramp seconds instead of 0.3 (the reset's posture is hip flexed +0.15,
    # the stance extends it to -0.26: at 0.3 s that is a 1.4 rad/s lurch that
    # rocks the body from foot to foot and spins the feet in the first second;
    # the set's minimum time is extended by the same amount)
    @b_t_ramp = ~0.3
    @b_t_ramp = param("b_t_ramp", ~0.3, ~0.15, ~1.5) if switch_on("bramp")
    # bgset 1: the set chunk's reflex gain multiplier (b_g_set; stiffer legs
    # while the reset's posture becomes the stance)
    @b_g_set = ~1.0
    @b_g_set = param("b_g_set", ~1.0, ~0.5, ~3.0) if switch_on("bgset")
    # dsx 1: double support's sagittal hip strategy: what the ankles cannot
    # take of the COM's fore-aft capture-point error (beyond dsx_lim) goes to
    # both hips' flexion (dsx_k rad per m: a COM behind the target flexes the
    # hips, the trunk leans forward). Measured: in the failing shifts the COM
    # drifts 0.1-0.6 m behind the feet over ~2 s while both ankles sit at their
    # dorsiflexion limit (+0.524), where the ankle strategy has no authority
    # bwide 1: the routine's stance (set, shifts, mids) has both hips abducted
    # by b_wide rad. Measured on 120 fresh starts: the starts that fail in the
    # hold whatever the hold's gains have a narrower stance at the lift (feet
    # 16.4 cm apart against 20.4 cm, z -8) and lift with the capture point
    # outboard of the stance foot (+0.8 cm against -1.2 cm)
    @b_wide = ~0.0
    @b_wide = param("b_wide", ~0.05, ~-0.1, ~0.3) if switch_on("bwide")
    # swabd 1: a feed-forward drive of sw_drv_abd on the SWING leg's hip
    # abductors while the other foot carries the body. Measured: in every
    # hold the swing shank rests on the stance thigh with 190-230 N (the soft
    # swing leg sags inward: kinematically 0.1 rad more abduction clears it by
    # 3.6 cm), an outward force on the stance femur that the stance hip's
    # adductors must resist and that ends one hold in 30 in a MuJoCo
    # instability
    @sw_drv_abd = ~0.0
    @sw_drv_abd = param("sw_drv_abd", ~0.15, ~0.0, ~0.6) if switch_on("swabd")
    @dsx = switch_on("dsx")
    @dsx_k = ~0.0
    @dsx_lim = ~0.05
    if @dsx
      @dsx_k = param("dsx_k", ~3.0, ~0.0, ~20.0)
      @dsx_lim = param("dsx_lim", ~0.05, ~0.0, ~0.12)
    # dsi 1: the weight shift's lateral integral: while the swing foot has not
    # unloaded, the COM's lateral error from the shift's target is integrated
    # (dsi_k rad per m s, at most dsi_lim rad) into the hips' adduction
    # (stance +, swing -) like the routine's feed-forward b_shift_add. Measured:
    # in the stuck shifts the loads stall at 0.7 / 0.3 with the COM 5-12 cm
    # from the stance foot for seconds while the body drifts back
    @dsi = switch_on("dsi")
    @dsi_k = ~0.0
    @dsi_lim = ~0.0
    @dsi_int = ~0.0
    if @dsi
      @dsi_k = param("dsi_k", ~1.0, ~0.0, ~6.0)
      @dsi_lim = param("dsi_lim", ~0.15, ~0.0, ~0.35)
    # bfore 1: the lift also waits for the COM's fore-aft capture point to be
    # within b_fx_tol of the stance foot's target (sb_x): the lateral latch
    # alone let a slow fore-aft drift (the COM 0.19 m behind the stance foot)
    # into the lift
    @bfore = switch_on("bfore")
    @b_fx_tol = ~1.0
    @b_fx_tol = param("b_fx_tol", ~0.06, ~0.02, ~0.2) if @bfore
    # bcpo 1: the lift also waits (at most bc_tmax more seconds) for the COM's
    # lateral capture point to be inboard of b_cpo_max from the stance foot's
    # centre (outward +). Measured on 240 starts (ramp base, left leg, lift-time
    # state): no hold failed when the lift came with the capture point at or
    # inboard of the foot's centre (0 of 212); 11 of the 28 lifts outboard of it
    # fell within 4 s, 10 of the 14 beyond +0.5 cm
    @bcpo = switch_on("bcpo")
    @b_cpo_max = ~1000000.0
    @b_cpo_max = param("b_cpo_max", ~0.0, ~-0.03, ~0.03) if @bcpo
    # (bcpo, measured: waiting is fatal. 36 starts, 20 s: 0 fixed, 13 of the
    # 17 lifts that had survived now fall in the shift 2.2-3 s in, the cp
    # outboard and the swing foot lightly on the ground; the lift itself is
    # what recovers them)
    # bshc 1: the shift's capture-point brake. While the swing foot has not
    # unloaded, the stance foot's lateral capture point beyond bsh_ref
    # (outward) trims the shift's push (the stance hip's adduction down, the
    # swing hip's up) by bsh_k rad per m of excess, at most bsh_lim: the
    # feed-forward b_shift_add pushes the COM the same way whatever the stance
    # width (r = -0.75 between the width and the cp at the lift), and a narrow
    # stance over-shifts
    @bshc = switch_on("bshc")
    @bsh_ref = ~1000000.0
    @bsh_k = ~0.0
    @bsh_lim = ~0.0
    if @bshc
      @bsh_ref = param("bsh_ref", ~-0.005, ~-0.03, ~0.03)
      @bsh_k = param("bsh_k", ~2.0, ~0.0, ~10.0)
      @bsh_lim = param("bsh_lim", ~0.08, ~0.0, ~0.25)
    # bretry 1: a hold that the fall catch ends within bc_short seconds is
    # retried on the same leg (at most bc_retry times) instead of switching to
    # the other one: the strict five-minute trial needs one 300 s stretch on
    # either leg, and a caught early fall leaves time for another attempt.
    # With bcout the outward excess (bc_out) is caught only during the first
    # bc_arm seconds of a hold: a hold that has lasted longer is trusted
    @bretry = switch_on("bretry")
    @bc_retry = ~0.0
    @bc_short = ~0.0
    @bc_arm = ~1000000.0
    if @bretry
      @bc_retry = param("bc_retry", ~2.0, ~0.0, ~4.0)
      @bc_short = param("bc_short", ~20.0, ~5.0, ~60.0)
      @bc_arm = param("bc_arm", ~12.0, ~2.0, ~40.0)
    # broll 1 (with bretry): the early hold is also ended (the swing foot put
    # down, then the next attempt) when the pelvis rolls outward past bc_roll
    # (rad, the pelvis's up axis tilted toward the stance side). Healthy holds
    # stay within +-0.06 rad; the outward runaway that the capture point
    # catches too late (cpo > 3 cm) shows as a growing roll oscillation of
    # +-0.1..0.25 rad from 0.5 s after the lift
    @bc_roll = ~1000.0
    @bc_roll = param("bc_roll", ~0.12, ~0.05, ~0.4) if switch_on("broll")
    @bc_tries = ~0.0
    @att_acc = ~0.0
    @bal_acc = {"l" => ~0.0, "r" => ~0.0}
    @bal_last = ""
    # (bc_first 1: the right leg first)
    @bal_last = "l" if @params.key?("bc_first") && @params["bc_first"] > ~0.5
    # bsettle 1: the set and each mid-stance wait (after their minimum time,
    # at most bs_tmax more) until both feet carry bs_load, the COM moves
    # slower than bs_v and the pelvis turns slower than bs_w: a shift starts
    # from a still, square double stance
    @bsettle = switch_on("bsettle")
    bs_params if @bsettle
    # bplace 1: the catch step is placed: in the put-down the swing hip steers
    # the foot (adduction across, flexion along the pelvis) toward the
    # capture point, bp_out beyond it toward the swing side
    # bdown 1: in the mid-stance, while the put-down foot carries less than
    # sb_ds_load, single support runs on the loaded foot (the double-support
    # hip terms on one leg feed a fall outward: measured, the COM drifted
    # 0.9 m outward over the stance foot while the put-down foot bounced),
    # and the COM is let fall bd_in toward the foot being put down
    @bdown = switch_on("bdown")
    @bd_in = ~0.0
    @bd_in = param("bd_in", ~0.02, ~0.0, ~0.08) if @bdown
    @bplace = switch_on("bplace")
    if @bplace
      @bp_k = param("bp_k", ~2.0, ~0.0, ~8.0)
      @bp_kf = param("bp_kf", ~1.0, ~0.0, ~6.0)
      @bp_out = param("bp_out", ~0.03, ~-0.1, ~0.15)
    self

  -> cp4_params
    @cp_k = param("cp_k", ~1.0, ~0.0, ~4.0)
    @cp_lim = param("cp_lim", ~0.025, ~0.005, ~0.04)
    @cp_limf = param("cp_limf", ~0.05, ~0.01, ~0.09)
    @cp_x = param("cp_x", ~0.02, ~-0.05, ~0.08)
    @cp_y = param("cp_y", ~0.0, ~-0.03, ~0.03)
    @cp_ks = param("cp_ks", ~6.0, ~0.0, ~30.0)
    @cp_ksf = param("cp_ksf", ~3.0, ~0.0, ~40.0)
    @cp_ka = param("cp_ka", ~4.0, ~0.0, ~30.0)
    @cp_kaf = param("cp_kaf", ~2.0, ~0.0, ~20.0)
    @cp_kh = param("cp_kh", ~-10.0, ~-60.0, ~15.0)
    @cp_ki = param("cp_ki", ~0.0, ~-3.0, ~3.0)
    @cp_h = param("cp_h", ~0.95, ~0.7, ~1.1)
    @cp_khf = param("cp_khf", ~0.0, ~-10.0, ~10.0)
    # cp_more 1: what the sole cannot take also goes to the swing hip (its
    # abduction, cp_ksw per metre: the leg as a counterweight) and to the
    # trunk's lateral bend toward the swing side (cp_klb per metre): the
    # stance hip's own strategy (cp_kh) throws the trunk into the fall, which
    # is right for a fast excess but positive feedback for a slow outward
    # drift (measured: pelvis roll 0.1 -> 0.9 while the hip abducts to -0.9)
    # cp_wash 1: the hip strategy with a washout: the fast part of the excess
    # goes through cp_kh (throw the trunk into the fall), the part that
    # persists (the excess low-passed with time constant cp_tau) through cp_khs
    # instead (positive: the stance hip adducts, the trunk leans back over the
    # foot), so a slow outward drift is fought by the static effect of the
    # lean, not fed by it
    @cp_wash = switch_on("cp_wash")
    @cp_khs = ~0.0
    @cp_tau = ~1.0
    @cp_slow = ~0.0
    if @cp_wash
      @cp_khs = param("cp_khs", ~4.0, ~-30.0, ~30.0)
      @cp_tau = param("cp_tau", ~0.6, ~0.1, ~3.0)
    @cp_ksw = ~0.0
    @cp_klb = ~0.0
    if switch_on("cp_more")
      @cp_ksw = param("cp_ksw", ~0.0, ~-8.0, ~8.0)
      @cp_klb = param("cp_klb", ~0.0, ~-8.0, ~8.0)
    @cp_rf = ~0.0
    @cp_ro = ~0.0
    self

  -> bs_params
    return self if @bs_load != nil
    @bs_load = param("bs_load", ~0.3, ~0.1, ~0.5)
    @bs_v = param("bs_v", ~0.05, ~0.01, ~0.2)
    @bs_w = param("bs_w", ~0.3, ~0.05, ~1.5)
    @bs_tmax = param("bs_tmax", ~1.5, ~0.2, ~4.0)
    self

  -> rk4_params
    # the run-up's pelvis heading, the plant foot's landing heading (less its
    # toe-out) and the kick's pelvis heading
    @rk_head = param("rk_head", ~0.0, ~-0.8, ~0.4)
    @rk_plant = param("rk_plant", ~-0.3, ~-1.0, ~0.4)
    @rk_kick = param("rk_kick", ~-0.4, ~-1.0, ~0.4)
    # the plant step's IK target turned into the pelvis's heading (rk_yawc of
    # its yaw): the parent's placement works in world x / y, and a pelvis
    # yawed in the run-up then puts the plant foot across the ball's line
    @rk_yawc = param("rk_yawc", ~1.0, ~0.0, ~1.0)
    # rk_wait 1: the side-foot kick's cock waits on the plant foot until the
    # plant hip has turned the pelvis within rk_tol of rk_kick (at most
    # rk_t_turn beyond s_t_cock)
    @rk_wait = switch_on("rk_wait")
    @rk_tol = param("rk_tol", ~0.15, ~0.03, ~0.6) if @rk_wait
    @rk_t_turn = param("rk_t_turn", ~0.4, ~0.05, ~1.2) if @rk_wait
    @s_kyaw_run = ~0.0
    @s_kyaw = ~0.0
    @s_plant_rot = ~0.0
    self

  -> in4_params
    # the angled approach's frame (in4_head: the pelvis heading of the strike,
    # negative = turned toward the kicking side) and its spots relative to
    # the ball in that frame (x along it, y to its left): the plant (left)
    # foot's centre and the kicking foot's
    @in4_head = param("in4_head", ~-0.6, ~-1.0, ~0.0)
    @in4_pdx = param("in4_pdx", ~-0.12, ~-0.5, ~0.15)
    @in4_pdy = param("in4_pdy", ~0.24, ~0.1, ~0.45)
    @in4_rdx = param("in4_rdx", ~-0.45, ~-0.9, ~-0.15)
    @in4_rdy = param("in4_rdy", ~0.06, ~-0.2, ~0.3)
    # the kick's heading offset from in4_head, and the wind-back: at least
    # in4_t_cock, until the heading is within in_yaw_tol
    @in4_dh = param("in4_dh", ~0.0, ~-0.4, ~0.4)
    @in4_t_cock = param("in4_t_cock", ~0.4, ~0.1, ~1.5)
    self

  -> hg_params
    @hg_min = param("hg_min", ~-0.35, ~-0.52, ~0.2)
    @hg_k = param("hg_k", ~1.0, ~0.0, ~4.0)
    # single support leans the thorax hg_pitch further forward (a hip hinge:
    # the stance hip flexes instead of the pelvis tipping back), eased in as
    # the swing foot unloads
    @hg_pitch = param("hg_pitch", ~0.0, ~-0.2, ~0.5)
    @pitch_des0 = @pitch_des
    self

  -> fyaw_params
    # the swing foot's yaw servo (hip rotation rad per rad of the foot's
    # heading error), its limit, and the foot's toe-out at landing
    @fy_k = param("fy_k", ~1.0, ~0.0, ~3.0)
    @fy_lim = param("fy_lim", ~0.6, ~0.1, ~1.2)
    @fy_splay = param("fy_splay", ~0.0, ~-0.3, ~0.3)
    self

  # ---- geometry -------------------------------------------------------------

  -> wrap(a)
    Math.atan2(Math.sin(a), Math.cos(a))

  # A foot's heading: heel (calcn origin) to toes.
  -> foot_yaw(f, sd)
    Math.atan2(f.at(sd + "_toe_pos", 1) - f.at(sd + "_foot_pos", 1), f.at(sd + "_toe_pos", 0) - f.at(sd + "_foot_pos", 0))

  # The hip's rotation stiffness under the reflexes (N m / rad), as in
  # MyoSoccerHip3: sum over the muscles crossing it of F (Lmax - Lmin) kp sl^2.
  -> rot_stiffness(sd)
    j = @g.joint("hip_rotation_" + sd)
    k = ~0.0
    @g.crossing(j).each ->(m)
      sl = @g.contraction_slope(m, j)
      rg = @g.range(m)
      k = k + @g.force(m) * (rg[1] - rg[0]) * @kp_arr[m] * sl * sl
    k

  # The same from the live moment arms (sense_arms): sum F kp arm^2 / range.
  -> live_rot_stiffness(f, sd)
    nm = "arm_hip_rotation_" + sd
    return @k_rot[sd] if !f.has?(nm)
    k = ~0.0
    w = f.schema.width(nm)
    i = 0
    while i < w
      m = f.at(nm + "_ids", i).to_i
      a = f.at(nm, i)
      rg = @g.range(m)
      k = k + @g.force(m) * @kp_arr[m] * a * a / (rg[1] - rg[0])
      i += 1
    k

  # With sense_arms on, every hip offset (the round-3 balance terms and the
  # round-4 ones) goes through the muscles' live moment arms, the task's
  # arm_<joint> blocks: contraction slope -arm / (Lmax - Lmin) at the measured
  # posture, instead of the geometry's reference slopes.
  -> joint_offset(off, joint, dq)
    return super(off, joint, dq) if !@live || @frame == nil
    nm = "arm_" + joint
    return super(off, joint, dq) if !@frame.has?(nm)
    return super(off, joint, dq) if @live_axes < ~1.5 && !joint.starts_with?("hip_rotation")
    return super(off, joint, dq) if @live_axes < ~2.5 && joint.starts_with?("hip_adduction")
    sc = @frame.schema
    o = sc.offset(nm)
    oi = sc.offset(nm + "_ids")
    w = sc.width(nm)
    v = @frame.values
    i = 0
    while i < w
      m = v[oi + i].to_i
      off[m] = off[m] - v[o + i] * @inv_range[m] * dq
      i += 1
    off

  # (swabd) the swing leg's hip abductors driven while one foot is unloaded.
  -> after(frame, ctl)
    super(frame, ctl)
    if @sw_drv_abd != nil && @sw_drv_abd > ~0.0 && v4_phase?
      sw = swing_side
      if sw != ""
        abd = @abd_l
        abd = @abd_r if sw == "r"
        d6 = @sw_drv_abd
        abd.each ->(i) ctl.add_drive(i, d6)
    self

  -> before(frame, ctl)
    super(frame, ctl)
    @frame = frame
    if @k7
      @k7_ref = ~0.0
      @k7_ref = @k7_lean * clamp((frame.t - @t_phase) / @k7_t_lean, ~0.0, ~1.0) if @phase == :k7_lean
    if @emit_q != nil
      ctl.emit(@emit_q)
      @emit_q = nil
    if @bcatch && @phase != nil
      @bal_acc["l"] = @bal_acc["l"] + ctl.dt if foot_load("r") < ~0.05 && foot_load("l") > ~0.3
      @bal_acc["r"] = @bal_acc["r"] + ctl.dt if foot_load("l") < ~0.05 && foot_load("r") > ~0.3
    if @hg && @phase != nil
      w = ~0.0
      w = clamp(~1.0 - (foot_load("l") < foot_load("r") ? foot_load("l") : foot_load("r")) / ~0.2, ~0.0, ~1.0) if v4_phase?
      @pitch_des = @pitch_des0 + @hg_pitch * w
    if @fy_prev != nil
      ["l", "r"].each ->(sd)
        fy = foot_yaw(frame, sd)
        @fy_rate[sd] = @fy_rate[sd] + (wrap(fy - @fy_prev[sd]) / ctl.dt - @fy_rate[sd]) * ~0.3
        @fy_prev[sd] = fy
    self

  # ---- balance --------------------------------------------------------------

  -> balance(f, ctl)
    off = super(f, ctl)
    kp = kick_phase? || (@rk4 && rk_kick_phase?)
    dsx_hip(f, off) if @dsx && v4_phase?
    dsi_hip(f, off, ctl) if @dsi && @phase == :b_shift
    shc_hip(f, off) if @bshc && @phase == :b_shift
    return off if !v4_phase? && !(@in4 && kick_phase?) && !(@rk4 && rk_phase?)
    tlh(f, off, ctl) if @tlh
    swing_yaw(f, off) if @fyaw && !kp
    hip_guard(f, off) if @hg
    cp4(f, off, ctl) if @cp4
    catch_place(f, off) if @bplace && @phase == :b_down
    off

  # The routine's stance with both hips abducted b_wide (bwide).
  -> stance
    p = super
    if @b_wide != nil && @b_wide != ~0.0
      p.set("hip_adduction_l", p.get("hip_adduction_l") - @b_wide)
      p.set("hip_adduction_r", p.get("hip_adduction_r") - @b_wide)
    p

  # (dsx) In double support (no foot unloaded below sb_ds_load) the COM's
  # fore-aft capture point beyond dsx_lim of the routine's target flexes both
  # hips.
  -> dsx_hip(f, off)
    st = b_stance_side
    return off if st != "" && foot_load(other_side(st)) < @sb_ds_load
    return off if @phase != :b_set && @phase != :b_shift && @phase != :b_mid && @phase != :b_down
    tg = b_target(f)
    e = f.at("com_pos", 0) + f.at("com_vel", 0) * ~0.311 - tg[0]
    ex = ~0.0
    ex = e - @dsx_lim if e > @dsx_lim
    ex = e + @dsx_lim if e < ~0.0 - @dsx_lim
    joint_offset(off, "hip_flexion_l", ~0.0 - @dsx_k * ex)
    joint_offset(off, "hip_flexion_r", ~0.0 - @dsx_k * ex)
    off

  # (dsi) the shift's lateral integral (see read_params).
  -> dsi_hip(f, off, ctl)
    tg = b_target(f)
    ey = f.at("com_pos", 1) - tg[1]
    @dsi_int = clamp(@dsi_int - @dsi_k * ey * ctl.dt, ~0.0 - @dsi_lim, @dsi_lim)
    joint_offset(off, "hip_adduction_l", @dsi_int)
    joint_offset(off, "hip_adduction_r", ~0.0 - @dsi_int)
    off

  # (bshc) the shift's capture-point brake (see read_params).
  -> shc_hip(f, off)
    st = b_stance_side
    return off if st == ""
    ex = cp_lateral(f, st) - @bsh_ref
    return off if ex <= ~0.0
    brake = clamp(@bsh_k * ex, ~0.0, @bsh_lim)
    joint_offset(off, "hip_adduction_" + st, ~0.0 - brake)
    joint_offset(off, "hip_adduction_" + other_side(st), brake)
    off

  # The stance hip kept off its extension limit: a flexion offset hg_k per
  # radian below hg_min (in single support).
  -> hip_guard(f, off)
    sw = swing_side
    return off if sw == ""
    st = other_side(sw)
    hf = f.q(body, "hip_flexion_" + st)
    @hg_dbg = hf
    joint_offset(off, "hip_flexion_" + st, @hg_k * (@hg_min - hf)) if hf < @hg_min
    off

  # The parent's running kick (rk4).
  -> rk_phase?
    @phase == :set || @phase == :shift || @phase == :lift || @phase == :reach || @phase == :lunge || @phase == :plant || @phase == :hold || rk_kick_phase?

  -> rk_kick_phase?
    @phase == :cock || @phase == :swing || @phase == :snap || @phase == :plant || @phase == :hold

  # Where the round-4 terms act: the single-leg routine and the ap3 approach.
  -> v4_phase?
    return false if kick_phase? || turn_phase?
    return true if @k4_cp && (@phase == :swing || @phase == :snap || @phase == :follow || @phase == :land)
    @phase == :b_set || @phase == :b_shift || @phase == :b_lift || @phase == :b_hold || @phase == :b_down || @phase == :b_mid || @phase == :s3_reach || @phase == :k7_lean

  # A foot's twist budget (N m): with the task's grip_cap sensor (the
  # ground's torsional limit under the foot, sum mu N |r - cop|, zero on a
  # single contact point) tl_cfrac of it, else tl_cap per body weight of
  # load; cut back while the foot spins.
  -> grip(sd)
    cap = @tl_cap * foot_load(sd)
    if @frame != nil && @frame.has?("grip_cap")
      cap = @tl_cfrac * @frame.at("grip_cap", 0)
      cap = @tl_cfrac * @frame.at("grip_cap", 1) if sd == "r"
    cap * clamp(~1.0 - @fy_rate[sd].abs / @tl_spin, ~0.0, ~1.0)

  # The heading the pelvis holds: the world reference blended (tl_wfoot)
  # toward the loaded feet's headings less their natural toe-out.
  -> tl_ref(f)
    wl = foot_load("l")
    wr = foot_load("r")
    ref = yaw_ref
    return ref if wl + wr < ~0.05
    hl = wrap(foot_yaw(f, "l") - @toe0["l"])
    hr = wrap(foot_yaw(f, "r") - @toe0["r"])
    # the load-weighted mean heading, taken relative to hl
    fh = hl + wr * wrap(hr - hl) / (wl + wr)
    ref + @tl_wfoot * wrap(fh - ref)

  # The twist-limited heading hold. The desired pelvis torque (PD on the
  # heading) is clipped to the loaded feet's summed grip and shared between
  # them by grip; each hip's equilibrium is shifted by its share over the
  # hip's rotation stiffness (plus, tl_cancel, its measured deviation from
  # the posture, so the share is the hip's whole twist). What the grip cannot
  # take goes to the trunk (lumbar axial rotation) and the swing leg.
  -> tlh(f, off, ctl)
    ref = tl_ref(f)
    if @tl_latch
      if swing_side == ""
        @tl_yaw0 = nil
      else
        @tl_yaw0 = @yaw if @tl_yaw0 == nil
        ref = @tl_yaw0
    e = wrap(@yaw - ref)
    tp = ~0.0 - (@tl_kp * e + @tl_kd * f.at("pelvis_angvel", 2))
    cl = grip("l")
    cr = grip("r")
    tot = cl + cr
    t = clamp(tp, ~0.0 - tot, tot)
    @tl_torque = t
    @tl_excess = tp - t
    ctl.emit("dbg:hg:" + @hg_dbg.to_s + ":" + @phase.to_s + ":" + swing_side) if @dbg > ~2.5 && @hg_dbg != nil
    ctl.emit("dbg:tlh:" + e.to_s + ":" + tp.to_s + ":" + cl.to_s + ":" + cr.to_s + ":kl:" + live_rot_stiffness(f, "l").to_s) if @dbg > ~1.5
    ["l", "r"].each ->(sd)
      c = cl
      c = cr if sd == "r"
      # (a foot below 20 % of body weight is eased out of the hold)
      w = clamp(foot_load(sd) / ~0.2, ~0.0, ~1.0)
      # (tl_cfull: a lightly loaded or landing foot's hip also stops pulling
      # toward the posture's rotation, so it does not twist the foot it
      # stands on; only a foot in the air keeps its posture, or fyaw's servo)
      wc = w
      wc = clamp(w + @tl_cfull, ~0.0, ~1.0) if foot_load(sd) > ~0.01
      if wc > ~0.0
        sg = ~1.0
        sg = ~-1.0 if sd == "r"
        jn = "hip_rotation_" + sd
        dq = ~0.0
        dq = sg * t * c / tot / (live_rot_stiffness(f, sd) * @tl_kscale) if tot > ~0.5 && w > ~0.0
        dq = dq + @tl_cancel * wc * (f.q(body, jn) - @cur_post.get(jn))
        joint_offset(off, jn, clamp(dq, ~0.0 - @tl_max, @tl_max))
    ex = @tl_excess
    joint_offset(off, "axial_rotation", clamp(@tl_ktr * ex, ~-0.5, ~0.5)) if @tl_ktr != ~0.0
    if @tl_ksw != ~0.0
      sw = swing_side
      if sw != ""
        sg = ~1.0
        sg = ~-1.0 if sw == "r"
        joint_offset(off, "hip_rotation_" + sw, clamp(sg * @tl_ksw * ex, ~-0.4, ~0.4))
    off

  # The unloaded foot while the other carries the body ("" in double
  # support).
  -> swing_side
    return "r" if foot_load("r") < @sb_ds_load && foot_load("l") > @sb_ds_load
    return "l" if foot_load("l") < @sb_ds_load && foot_load("r") > @sb_ds_load
    ""

  # The heading a swing foot lands along (the pelvis's reference heading,
  # plus the foot's natural toe-out and fy_splay).
  -> land_yaw(f, sw)
    sg = ~1.0
    sg = ~-1.0 if sw == "r"
    h = yaw_ref
    h = tl_ref(f) if @tlh
    h = @step_head if @ap4 && s3_phase?
    h = @rk_plant if @rk4 && @phase == :reach
    h + @toe0[sw] + sg * @fy_splay

  # The swing foot turned in the air: its hip's rotation servos the foot's
  # measured heading to land_yaw (hip rotation + turns the left toes CW and
  # the right toes CCW).
  -> swing_yaw(f, off)
    sw = swing_side
    return off if sw == ""
    sg = ~1.0
    sg = ~-1.0 if sw == "r"
    e = wrap(land_yaw(f, sw) - foot_yaw(f, sw))
    joint_offset(off, "hip_rotation_" + sw, clamp(~0.0 - sg * @fy_k * e, ~0.0 - @fy_lim, @fy_lim))
    @emit_q = "dbg:fyaw:" + sw + ":land:" + land_yaw(f, sw).to_s + ":fy:" + foot_yaw(f, sw).to_s + ":e:" + e.to_s if @dbg > ~3.5
    off

  # ---- the turning approach (ap4) --------------------------------------------

  -> yaw_ref
    return @in4_head + @in4_dh if @in4 && kick_phase?
    return @rk_kick if @rk4 && rk_kick_phase?
    return @rk_head if @rk4 && rk_phase?
    return @s4_ref if @ap4 && s3_phase?
    super

  # A foot's heading less its natural toe-out: the heading it gives the
  # body.
  -> foot_heading(f, sd)
    wrap(foot_yaw(f, sd) - @toe0[sd])

  # The next step, or the kick. The walking heading points at the spots'
  # midpoint (within s4_hmax of the final heading s4_hf) while they are
  # farther than s4_far and blends to s4_hf by s4_near; the feet alternate
  # (the first step: the foot farther from its spot). The stepping foot's new
  # heading is the stance foot's turned by at most s4_turn toward the walking
  # heading; its spot, expressed in that heading's frame from the stance
  # foot, is clipped to s4_ahead ahead, s4_back behind, and s3_min_sep to
  # s3_min_sep + s3_max_y out to its own side.
  -> next3(f)
    return super(f) if !@ap4
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    nl = Math.sqrt((@g3_l[0] - l[0]) * (@g3_l[0] - l[0]) + (@g3_l[1] - l[1]) * (@g3_l[1] - l[1]))
    nr = Math.sqrt((@g3_r[0] - r[0]) * (@g3_r[0] - r[0]) + (@g3_r[1] - r[1]) * (@g3_r[1] - r[1]))
    hb = wrap(foot_heading(f, "l") + wrap(foot_heading(f, "r") - foot_heading(f, "l")) * ~0.5)
    done = nl < @s3_tol && nr < @s3_tol && wrap(hb - @s4_hf).abs < @s4_htol
    if done || @steps >= @s4_max
      @s4_ref = @s4_hf
      return "in4_shift" if @in4
      return "k4_shift" if @k4
      return "k5_set" if @ks5
      return "set"
    dx = (@g3_l[0] + @g3_r[0] - l[0] - r[0]) * ~0.5
    dy = (@g3_l[1] + @g3_r[1] - l[1] - r[1]) * ~0.5
    dist = Math.sqrt(dx * dx + dy * dy)
    w = clamp((dist - @s4_near) / (@s4_far - @s4_near + ~0.001), ~0.0, ~1.0)
    ht = @s4_hf + clip(wrap(Math.atan2(dy, dx) - @s4_hf), @s4_hmax)
    h = wrap(@s4_hf + w * wrap(ht - @s4_hf))
    sd = "l"
    sd = "r" if @last_side == "l"
    if @last_side == ""
      sd = "r" if nr > nl
    st = other_side(sd)
    ps = foot_center(f, st)
    hs = foot_heading(f, st)
    hn = wrap(hs + clip(wrap(h - hs), @s4_turn))
    g = @g3_l
    g = @g3_r if sd == "r"
    sg = ~1.0
    sg = ~-1.0 if sd == "r"
    c = Math.cos(hn)
    sn = Math.sin(hn)
    rx = g[0] - ps[0]
    ry = g[1] - ps[1]
    fw = clamp(rx * c + ry * sn, ~0.0 - @s4_back, @s4_ahead)
    lt = sg * clamp(sg * (ry * c - rx * sn), @s3_min_sep, @s3_min_sep + @s3_max_y)
    @step_to = [ps[0] + fw * c - lt * sn, ps[1] + fw * sn + lt * c]
    @step_head = hn
    @s4_ref = wrap(hs + wrap(hn - hs) * ~0.5)
    @steps += 1
    @step_side = sd
    @last_side = sd
    @emit_q = "dbg:step:" + sd + ":" + @step_to[0].to_s + ":" + @step_to[1].to_s + ":" + hn.to_s + ":dist:" + dist.to_s if @dbg > ~0.5
    sd + "_s3shift"

  # The swing ankle's target: the step's foot-centre spot, 4 cm back along
  # the new heading and 1.5 cm medial.
  -> s3_ankle_target
    return super if !@ap4
    c = Math.cos(@step_head)
    sn = Math.sin(@step_head)
    m = ~0.015
    m = ~-0.015 if @step_side == "r"
    [@step_to[0] - ~0.04 * c + m * sn, @step_to[1] - ~0.04 * sn - m * c]

  # The COM's capture point across the stance foot (in its own frame) within
  # b_cp_tol of the single-support target.
  -> captured?(f, st)
    return super(f, st) if !@ap4
    (cp_lateral(f, st) - @sb_y).abs < @b_cp_tol

  -> s3_falling?(f, st)
    return super(f, st) if !@ap4
    ~0.0 - cp_lateral(f, st) > @s3_fall

  # The capture point's outward offset from the stance foot's centre, across
  # the foot (+ toward the stance side).
  -> cp_lateral(f, st)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    fc = foot_center(f, st)
    h = foot_yaw(f, st)
    cx = f.at("com_pos", 0) + f.at("com_vel", 0) * ~0.311 - fc[0]
    cy = f.at("com_pos", 1) + f.at("com_vel", 1) * ~0.311 - fc[1]
    sg * (cy * Math.cos(h) - cx * Math.sin(h))

  # ---- the angled inside kick (in4) -------------------------------------------

  -> ap3_movement
    return super if !@in4 && !@s4set
    mv = Movement.new("ap4")
    ch = chunk("s3_hold", ~0.3, stance, :b_set, :both, :mid).hold_until(Latch.after(@s3_t_hold))
    ch = chunk("s3_hold", ~0.3, stance, :b_set, :both, :mid).hold_until(s4_settled.after_min(@s3_t_hold), @s3_t_hold + @s4_tmax) if @s4set
    ch.branch(->(f, c) next3(f))
    mv.add(ch)
    add_step3(mv, "l")
    add_step3(mv, "r")
    if @k4
      add_standing_kick(mv)
      return mv
    if !@in4
      add_run_up(mv)
      add_kick(mv)
      return mv
    add_inside4(mv)
    mv

  -> ap3_movement_in4
    mv = Movement.new("ap4")
    ch = chunk("s3_hold", ~0.3, stance, :b_set, :both, :mid).hold_until(Latch.after(@s3_t_hold))
    ch.branch(->(f, c) next3(f))
    mv.add(ch)
    add_step3(mv, "l")
    add_step3(mv, "r")
    add_inside4(mv)
    mv

  # From the approach's spots: the weight onto the plant (left) foot until
  # the kicking foot unloads with the capture point over the plant foot; the
  # kicking leg wound back (V3's in_*_b posture: hip extended, abducted,
  # turned out, knee bent, ankle up) on the plant leg's one-leg posture, for
  # at least in4_t_cock and until the heading holds; then V3's inside swing.
  -> add_inside4(mv)
    p = stance
    p.set("hip_adduction_l", p.get("hip_adduction_l") + @b_shift_add)
    p.set("hip_adduction_r", p.get("hip_adduction_r") - @b_shift_add)
    unl = Latch.test("in4_unl", ->(f, e, c) foot_load("r") < @b_unload && captured?(f, "l"))
    mv.add(chunk("in4_shift", @b_t_shift, p, :b_shift, :both, :l).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + ~1.0))
    p = one_leg_posture("l")
    in_leg(p, @in_hf_b, @in_add_b, @in_rot_b, @in_knee_b, @in_ank_b)
    turned = Latch.test("in4_turned", ->(f, e, c) wrap(@yaw - yaw_ref).abs < @in_yaw_tol)
    mv.add(chunk("in_cock", @in4_t_cock, p, :in_cock, :l, :l).hold_until(turned.after_min(@in4_t_cock), @in4_t_cock + @in_t_cock))
    add_inside_swing(mv)

  # ---- the single-leg routine with caught falls (bcatch) ---------------------

  -> bal_movement
    return super if !@bcatch
    mv = Movement.new("bal")
    ramp_extra = @b_t_ramp - ~0.3
    ch = chunk("b_set", @b_t_ramp, stance, :b_set, :both, :mid).hold_until(Latch.after(@b_t_set + ramp_extra)).gain(@b_g_set)
    ch = chunk("b_set", @b_t_ramp, stance, :b_set, :both, :mid).hold_until(settled.after_min(@b_t_set + ramp_extra), @b_t_set + ramp_extra + @bs_tmax).gain(@b_g_set) if @bsettle
    ch.branch(->(f, c) next_leg(f))
    mv.add(ch)
    add_catch_leg(mv, "l")
    add_catch_leg(mv, "r")
    mv.add(chunk("b_end", ~0.3, stance, :b_mid, :both, :mid).hold_until(Latch.after(~100.0)))
    mv

  # The next leg to stand on (alternating, skipping a leg that has its
  # bc_cap seconds), or the end.
  -> next_leg(f)
    l = @bal_acc["l"] >= @bc_cap
    r = @bal_acc["r"] >= @bc_cap
    return "b_end" if l && r
    st = "l"
    st = "r" if @bal_last == "l"
    st = "r" if l
    st = "l" if r
    # (bretry: a short hold is retried on the same leg)
    if @bretry && @bal_last != ""
      held = @bal_acc[@bal_last] - @att_acc
      if held < @bc_short && @bc_tries < @bc_retry && @bal_acc[@bal_last] < @bc_cap
        st = @bal_last
        @bc_tries = @bc_tries + ~1.0
    @att_acc = @bal_acc[st]
    @bal_last = st
    "b_shift_" + st

  # V3's add_one_leg, the hold ending early on a coming fall (or the leg's
  # seconds reached), the mid-stance branching to the next leg.
  -> add_catch_leg(mv, st)
    sw = other_side(st)
    ss = :l
    ss = :r if st == "r"
    p = stance
    p.set("hip_adduction_" + st, p.get("hip_adduction_" + st) + @b_shift_add)
    p.set("hip_adduction_" + sw, p.get("hip_adduction_" + sw) - @b_shift_add)
    unl = Latch.test(st + "_bunl", ->(f, e, c) foot_load(sw) < @b_unload && captured?(f, st) && lat_still?(f, st) && fore_ok?(f, st) && cpo_ok?(f, st))
    mv.add(chunk("b_shift_" + st, @b_t_shift, p, :b_shift, :both, ss).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + @bc_tmax))
    p = one_leg_posture(st)
    mv.add(chunk("b_lift_" + st, @b_t_lift, p, :b_lift, ss, ss).hold_until(Latch.after(@b_t_lift)))
    stop = Latch.test(st + "_bfall", ->(f, e, c) @bal_acc[st] >= @bc_cap || ~0.0 - cp_lateral(f, st) > @bc_in || (cp_lateral(f, st) > @bc_out && e < @bc_arm) || (roll_out(f, st) > @bc_roll && e < @bc_arm))
    mv.add(chunk("b_hold_" + st, ~0.2, p, :b_hold, ss, ss).hold_until(Latch.any([Latch.after(@b_hold), stop]), @b_hold))
    down = Latch.test(st + "_bdown", ->(f, e, c) foot_load(sw) > @b_load)
    mv.add(chunk("b_down_" + st, @b_t_down, stance, :b_down, ss, ss).hold_until(down.after_min(@b_t_down * ~0.5), ~1.0))
    ch = chunk("b_mid_" + st, ~0.3, stance, :b_mid, :both, :mid).hold_until(Latch.after(@b_t_mid))
    ch = chunk("b_mid_" + st, ~0.3, stance, :b_mid, :both, :mid).hold_until(settled.after_min(@b_t_mid), @b_t_mid + @bs_tmax) if @bsettle
    ch.branch(->(f, c) next_leg(f))
    mv.add(ch)
    mv

  # The pelvis's outward tilt (toward the stance side), rad.
  -> roll_out(f, st)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    # the z component of the pelvis's lateral axis (its forward axis crossed
    # with its up axis): sin of the roll, whatever the pelvis's yaw and pitch
    sg * (f.at("pelvis_fwd", 0) * f.at("pelvis_upv", 1) - f.at("pelvis_fwd", 1) * f.at("pelvis_upv", 0))

  # (blv) the COM's velocity across the stance foot below b_vlat: the lift
  # waits for the weight shift to have stopped, not only arrived.
  -> lat_still?(f, st)
    return true if !@blv
    h = foot_yaw(f, st)
    (f.at("com_vel", 1) * Math.cos(h) - f.at("com_vel", 0) * Math.sin(h)).abs < @b_vlat

  # (bfore) the COM's fore-aft capture point (COM + velocity x sqrt(h / g)
  # along the stance foot's heading) within b_fx_tol of the foot's target
  # sb_x ahead of its centre.
  -> fore_ok?(f, st)
    return true if !@bfore
    fc = foot_center(f, st)
    h = foot_yaw(f, st)
    dx = f.at("com_pos", 0) + f.at("com_vel", 0) * ~0.311 - fc[0]
    dy = f.at("com_pos", 1) + f.at("com_vel", 1) * ~0.311 - fc[1]
    (dx * Math.cos(h) + dy * Math.sin(h) - @sb_x).abs < @b_fx_tol

  # (bcpo) the lateral capture point inboard of b_cpo_max from the stance
  # foot's centre.
  -> cpo_ok?(f, st)
    return true if !@bcpo
    cp_lateral(f, st) < @b_cpo_max

  # Still, square double stance (bsettle).
  -> settled
    Latch.test("settled", ->(f, e, c) foot_load("l") > @bs_load && foot_load("r") > @bs_load && Math.sqrt(f.at("com_vel", 0) * f.at("com_vel", 0) + f.at("com_vel", 1) * f.at("com_vel", 1)) < @bs_v && f.at("pelvis_angvel", 2).abs < @bs_w)

  # The placed catch step (bplace): in the put-down the swing hip steers the
  # foot toward the capture point (+ bp_out outward), in the pelvis's frame.
  -> catch_place(f, off)
    st = "l"
    st = "r" if @support == :r
    sw = other_side(st)
    sg = ~1.0
    sg = ~-1.0 if sw == "r"
    c = Math.cos(@yaw)
    sn = Math.sin(@yaw)
    tx = f.at("com_pos", 0) + f.at("com_vel", 0) * ~0.311 - sg * @bp_out * sn
    ty = f.at("com_pos", 1) + f.at("com_vel", 1) * ~0.311 + sg * @bp_out * c
    ex = tx - f.at(sw + "_ankle_pos", 0)
    ey = ty - f.at(sw + "_ankle_pos", 1)
    el = ey * c - ex * sn
    ef = ex * c + ey * sn
    joint_offset(off, "hip_adduction_" + sw, clamp(~0.0 - sg * @bp_k * el, ~-0.5, ~0.5))
    joint_offset(off, "hip_flexion_" + sw, clamp(@bp_kf * ef, ~-0.5, ~0.5))
    off

  # ---- the kick's snap fired by the foot-ball distance (sd) -------------------

  -> add_kick(mv)
    return super(mv) if !@sd || @side > ~0.5
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k1, @knee_k1, @ankle_k)
    thigh = Latch.test("thigh", ->(f, e, c) f.q(body, "hip_flexion_r") > @hip_snap && f.at("env_ball_pos", 0) - f.at("r_toe_pos", 0) < @sn_d)
    ch = chunk("swing", @t_swing, p, :swing, :l, :l).hold_until(thigh, @t_swing * ~2.5)
    ch.drive(drive_on(@hip_flexors_r, @drv_hip))
    mv.add(ch)
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k2, @knee_k2, @ankle_k)
    hit = Latch.test("touch", ->(f, e, c) f.get("ball_touch") > ~0.5)
    ch = chunk("snap", @t_snap, p, :snap, :l, :l).hold_until(hit, @t_snap * ~2.5)
    d = drive_on(@knee_ext_r, @drv_knee)
    @hip_flexors_r.each ->(i) d[i] = @drv_hip
    ch.drive(d)
    mv.add(ch)
    add_after_touch(mv)

  # ---- the side-foot kick waiting for the turn (rk4 + rk_wait) ---------------

  -> add_side_kick(mv)
    return super(mv) if !@rk4 || !@rk_wait
    p = side_leg(kick_stance(base_posture), @s_th_cock, @s_knee_cock)
    turned = Latch.test("rk_turned", ->(f, e, c) wrap(@yaw - @rk_kick).abs < @rk_tol)
    ch = chunk("cock", @s_t_cock + ~0.05, p, :cock, :l, :l).hold_until(turned.after_min(@s_t_cock), @s_t_cock + @rk_t_turn)
    d = zeros
    @ankle_r.each ->(i) d[i] = @s_drv_ank
    ch.drive(d)
    mv.add(ch)
    p = side_leg(kick_stance(base_posture), @th_k1, @s_knee1)
    thigh = Latch.test("thigh", ->(f, e, c) f.q(body, "hip_flexion_r") > @hip_snap)
    ch = chunk("swing", @t_swing, p, :swing, :l, :l).hold_until(thigh, @t_swing * ~2.5)
    ch.drive(side_drive(~0.0))
    mv.add(ch)
    p = side_leg(kick_stance(base_posture), @th_k2, @s_knee2)
    hit = Latch.test("touch", ->(f, e, c) f.get("ball_touch") > ~0.5)
    ch = chunk("snap", @t_snap, p, :snap, :l, :l).hold_until(hit, @t_snap * ~2.5)
    ch.drive(side_drive(@s_drv_knee))
    mv.add(ch)
    add_after_touch(mv)

  # ---- single support on the sensed centre of pressure (cp4) ------------------

  # (each leg's stance starts from an uncorrected reference)
  -> enter(f, phase, support, lat)
    super(f, phase, support, lat)
    if phase == :s3_reach && @s4set
      @s4_from = [f.at(@step_side + "_ankle_pos", 0), f.at(@step_side + "_ankle_pos", 1)]
      @s4_t0 = f.t
    @dsi_int = ~0.0 if phase == :b_shift
    if @cp4 && phase == :b_shift
      @cp_ro = ~0.0
      @cp_rf = ~0.0
      @cp_slow = ~0.0
    self

  # The stance foot's capture point in its own frame [forward, outward] from
  # the foot centre, and the COP target (clipped to the sole) with what the
  # sole cannot take; the subtalar (inversion moves the COP outward) and the
  # ankle (plantarflexion moves it forward) servo the measured COP, the stance
  # hip adducts on the lateral excess.
  -> cp4(f, off, ctl)
    sw = swing_side
    return off if sw == ""
    st = other_side(sw)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    fc = foot_center(f, st)
    h = foot_yaw(f, st)
    c = Math.cos(h)
    sn = Math.sin(h)
    w = ~1.0 / Math.sqrt(~9.81 / @cp_h)
    dx = f.at("com_pos", 0) + f.at("com_vel", 0) * w - fc[0]
    dy = f.at("com_pos", 1) + f.at("com_vel", 1) * w - fc[1]
    cpf = dx * c + dy * sn
    cpo = sg * (dy * c - dx * sn)
    k = 0
    k = 2 if st == "r"
    copf = f.at("foot_cop", k)
    copo = f.at("foot_cop", k + 1)
    rf = @cp_x + @cp_rf + @k7_ref
    ro = @cp_y + @cp_ro
    # (bdown: putting the foot down, and until it carries weight, the COM is
    # let fall bd_in toward it)
    ro = ro - @bd_in if @bdown && (@phase == :b_down || @phase == :b_mid)
    wo = cpo + @cp_k * (cpo - ro)
    wf = cpf + @cp_k * (cpf - rf)
    dso = clamp(wo, ~0.0 - @cp_lim, @cp_lim)
    dsf = clamp(wf, ~0.0 - @cp_limf, @cp_limf)
    joint_offset(off, "subtalar_angle_" + st, @cp_ks * (dso - copo) + @cp_ksf * dso)
    joint_offset(off, "ankle_angle_" + st, ~0.0 - (@cp_ka * (dsf - copf) + @cp_kaf * dsf))
    hipoff = @cp_kh * (wo - dso)
    if @cp_wash
      @cp_slow = @cp_slow + ((wo - dso) - @cp_slow) * ctl.dt / @cp_tau
      hipoff = @cp_kh * ((wo - dso) - @cp_slow) + @cp_khs * @cp_slow
    joint_offset(off, "hip_adduction_" + st, hipoff)
    # (cp_more: the swing leg abducted and the trunk bent toward the swing
    # side by the same excess, whatever its sign)
    joint_offset(off, "hip_adduction_" + sw, ~0.0 - @cp_ksw * (wo - dso)) if @cp_ksw != ~0.0
    joint_offset(off, "lat_bending", sg * @cp_klb * (wo - dso)) if @cp_klb != ~0.0
    # (and the fore-aft excess to the stance hip's flexion: the sagittal hip
    # strategy, sign and size by practice)
    joint_offset(off, "hip_flexion_" + st, @cp_khf * (wf - dsf)) if @cp_khf != ~0.0
    # the reference drifts so the sole's COP stays centred
    @cp_ro = clamp(@cp_ro - @cp_ki * copo * ctl.dt, ~-0.03, ~0.03)
    ctl.emit("dbg:cp4:" + st + ":cpo:" + cpo.to_s + ":dso:" + dso.to_s + ":copo:" + copo.to_s + ":cpf:" + cpf.to_s + ":dsf:" + dsf.to_s + ":copf:" + copf.to_s) if @dbg > ~2.5
    off

  # (bdown) the mid-stance's support by the loads: single support on the
  # loaded foot while the other carries less than sb_ds_load.
  -> b_stance_side
    sd = super
    return sd if sd != "" || !@bdown || @phase != :b_mid
    return "l" if foot_load("r") < @sb_ds_load && foot_load("l") > @sb_ds_load
    return "r" if foot_load("l") < @sb_ds_load && foot_load("r") > @sb_ds_load
    ""

  # ---- the approach's steps with the routine's transitions (ap4 + s4set) ------

  # V3's quasi-static step (shift, lift, IK-placed reach, mid-stance), its
  # mid-stance (and the approach's first hold) waiting for a still, square
  # double stance like the single-leg routine's (bsettle's latch), and the
  # step's shift waiting for the swing foot unloaded with the capture point
  # over the stance foot.
  -> add_step3(mv, sd)
    return super(mv, sd) if !@s4set
    st = other_side(sd)
    ss = :l
    ss = :r if st == "r"
    p = stance
    p.set("hip_adduction_" + st, p.get("hip_adduction_" + st) + @b_shift_add)
    p.set("hip_adduction_" + sd, p.get("hip_adduction_" + sd) - @b_shift_add)
    unl = Latch.test(sd + "_s3unl", ->(f, e, c) foot_load(sd) < @b_unload && captured?(f, st))
    mv.add(chunk(sd + "_s3shift", @b_t_shift, p, :b_shift, :both, ss).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + @s4_tmax))
    p = step_stance(st)
    mv.add(chunk(sd + "_s3lift", @b_t_lift, p, :b_lift, ss, ss).hold_until(Latch.after(@b_t_lift)))
    p = step_stance(st)
    tleg(p, sd, @s3_reach_dx, @s3_reach_dz, @ap_reach_pitch, @tilt0)
    @ap_postures[sd] = p
    down = Latch.test(sd + "_s3down", ->(f, e, c) foot_load(sd) > @s3_load && (s3_dist(f) < @s3_near * ~1.5 || s3_falling?(f, st)))
    mv.add(chunk(sd + "_s3reach", @s3_t_reach, p, :s3_reach, ss, ss).hold_until(down.after_min(@s3_t_reach * ~0.5), @s3_reach_max))
    ch = chunk(sd + "_s3mid", ~0.3, stance, :b_mid, :both, :mid).hold_until(s4_settled.after_min(@s3_t_mid), @s3_t_mid + @s4_tmax)
    ch.branch(->(f, c) next3(f))
    mv.add(ch)
    mv

  # The step's one-leg posture: the routine's, with the stance leg crouched
  # by s4_knee (knee flexion, the hip and ankle following so the foot stays
  # under the hip: the thigh leans forward, the stance hip leaves the
  # extension corner where its rotators lose the heading) plus s4_hip.
  -> step_stance(st)
    p = one_leg_posture(st)
    k = @s4_knee
    p.set("knee_angle_" + st, p.get("knee_angle_" + st) + k)
    p.set("hip_flexion_" + st, p.get("hip_flexion_" + st) + k * ~0.5 + @s4_hip)
    p.set("ankle_angle_" + st, p.get("ankle_angle_" + st) + k * ~0.5)
    p

  # (s4_tmove > 0) the step's placement target travels from where the swing
  # ankle was at the reach's start to the spot, min-jerk over s4_tmove: a
  # slow, smooth swing (a fast one's reaction yaws the pelvis over a stance
  # hip that has no internal rotation left at its extension corner)
  -> s3_place_target(f)
    t = super(f)
    return t if !@s4set || @s4_tmove <= ~0.0 || @s4_from == nil
    u = Easing.apply(:min_jerk, clamp((f.t - @s4_t0) / @s4_tmove, ~0.0, ~1.0))
    [@s4_from[0] + (t[0] - @s4_from[0]) * u, @s4_from[1] + (t[1] - @s4_from[1]) * u]

  -> s4_settled
    Latch.test("s4_settled", ->(f, e, c) foot_load("l") > @s4_load && foot_load("r") > @s4_load && Math.sqrt(f.at("com_vel", 0) * f.at("com_vel", 0) + f.at("com_vel", 1) * f.at("com_vel", 1)) < @s4_v)

  # ---- the standing kick after the approach (k4) ------------------------------

  # The weight onto the plant (left) foot until the kicking foot unloads with
  # the capture point over the plant foot; the kicking leg wound back (the
  # parent's th_back, knee_back, ankle_back) on the plant leg's one-leg
  # posture for k4_t_cock (single support on the sensed COP); then the
  # parent's swing, snap, follow-through, landing and recovery.
  -> add_standing_kick(mv)
    p = stance
    p.set("hip_adduction_l", p.get("hip_adduction_l") + @b_shift_add)
    p.set("hip_adduction_r", p.get("hip_adduction_r") - @b_shift_add)
    unl = Latch.test("k4_unl", ->(f, e, c) foot_load("r") < @b_unload && captured?(f, "l"))
    mv.add(chunk("k4_shift", @b_t_shift, p, :b_shift, :both, :l).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + @k4_tmax))
    p = one_leg_posture("l")
    wleg(p, "r", @th_back, @knee_back, @ankle_back)
    mv.add(chunk("k4_cock", @k4_t_cock, p, :b_lift, :l, :l).hold_until(Latch.after(@k4_t_cock)))
    add_kick(mv)

  # ---- the kick from a settled stance (ks5) ------------------------------------

  # The run-up's shift and lift (V3's add_run_up_steps' first two chunks),
  # then standing on the right leg with the left one lifted.
  -> add_k5_stork(mv)
    p = stance
    p.set("hip_adduction_r", p.get("hip_adduction_r") + @shift_add)
    p.set("hip_adduction_l", p.get("hip_adduction_l") - @shift_add)
    p.set("subtalar_angle_r", p.get("subtalar_angle_r") + @shift_st)
    p.set("subtalar_angle_l", p.get("subtalar_angle_l") - @shift_st)
    unloaded = Latch.test("unloaded", ->(f, e, c) @cl_f < @unload || (@d_go > ~0.0 && f.at("com_pos", 0) - support_point(f, :both)[0] > @d_go))
    mv.add(chunk("shift", @t_shift, p, :shift, :both, :r).hold_until(unloaded.after_min(@t_shift * ~0.5), ~2.0))
    p = base_posture
    p.set("flex_extension", @fe - @lean_step)
    fleg(p, "l", @lift_dx, @lift_dz, @lift_pitch)
    leg(p, "r", @hip, @knee, @ankle)
    mv.add(chunk("lift", @t_lift, p, :lift, :r, :r).hold_until(Latch.after(@t_lift)))
    mv.add(chunk("stork", ~0.3, p, :stork, :r, :r).hold_until(Latch.after(~100.0)))
    mv

  -> movement
    return k6_movement if @k6
    return ks5_movement if @ks5
    super

  # The routine's set, shift onto the right foot, lift and hold, then the
  # parent's reach (the left foot IK-placed at the plant spot beside the ball
  # while the right leg pushes), plant and kick.
  -> k6_movement
    mv = Movement.new("k6")
    ramp_extra = @b_t_ramp - ~0.3
    ch = chunk("b_set", @b_t_ramp, stance, :b_set, :both, :mid).hold_until(settled.after_min(@b_t_set + ramp_extra), @b_t_set + ramp_extra + @bs_tmax).gain(@b_g_set)
    mv.add(ch)
    p = stance
    p.set("hip_adduction_r", p.get("hip_adduction_r") + @b_shift_add)
    p.set("hip_adduction_l", p.get("hip_adduction_l") - @b_shift_add)
    unl = Latch.test("r_bunl", ->(f, e, c) foot_load("l") < @b_unload && captured?(f, "r") && lat_still?(f, "r") && fore_ok?(f, "r"))
    mv.add(chunk("b_shift_r", @b_t_shift, p, :b_shift, :both, :r).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + @bc_tmax))
    p = one_leg_posture("r")
    mv.add(chunk("b_lift_r", @b_t_lift, p, :b_lift, :r, :r).hold_until(Latch.after(@b_t_lift)))
    mv.add(chunk("b_hold_r", ~0.2, p, :b_hold, :r, :r).hold_until(Latch.after(@k6_t_hold)))
    if @k7
      ahead = Latch.test("k7_ahead", ->(f, e, c) f.at("com_pos", 0) - foot_center(f, "r")[0] > @k7_go)
      mv.add(chunk("k7_lean", @k7_t_lean, p, :k7_lean, :r, :r).hold_until(ahead.after_min(@k7_t_lean * ~0.5), @k7_t_max))
    p = base_posture
    p.set("flex_extension", @fe - @lean_step)
    fleg(p, "l", @reach_dx, @reach_dz, @reach_pitch)
    p.set("hip_adduction_l", @add_reach)
    tleg(p, "r", @push_dx, @push_dz, @push_pitch, @tilt_step)
    p.set("flex_extension", @fe_step)
    @reach_posture = p
    touch = Latch.test("plant", ->(f, e, c) @cl_f > @plant_load && f.at("l_foot_pos", 0) > @heel0 + @min_step)
    ch = chunk("reach", @t_reach, p, :reach, :r, :r).hold_until(touch.after_min(~0.05), ~1.2)
    ch.drive(drive_on(@plantar_r, @drv_push))
    mv.add(ch)
    if @direct > ~0.5
      add_kick(mv)
      return mv
    add_lunge_plant(mv)
    add_kick(mv)
    mv

  # (with ap4 and s4set: the approach's steps to the kick spots first, each
  # from a settled stance, then the settle and the kick)
  -> ks5_movement
    mv = Movement.new("ks5")
    if @ap4 && @s4set
      ch = chunk("s3_hold", ~0.3, stance, :b_set, :both, :mid).hold_until(s4_settled.after_min(@s3_t_hold), @s3_t_hold + @s4_tmax)
      ch.branch(->(f, c) next3(f))
      mv.add(ch)
      add_step3(mv, "l")
      add_step3(mv, "r")
    mv.add(chunk("k5_set", ~0.3, stance, :b_set, :both, :mid).hold_until(settled.after_min(@b_t_set), @b_t_set + @bs_tmax))
    # the curriculum's stages (stage, as the parent's): < 0.75 stand on the
    # right leg with the left one lifted (stork); < 1.5 with direct 1: land
    # the plant step and stand on the plant foot, the kicking leg wound back
    return add_k5_stork(mv) if @stage < ~0.75
    add_run_up_steps(mv)
    if @stage < ~1.5 && @direct > ~0.5
      p = kick_stance(base_posture)
      wleg(p, "r", @th_back, @knee_back, @ankle_back)
      mv.add(chunk("hold", ~0.3, p, :hold, :l, :l).hold_until(Latch.after(~100.0)))
      return mv
    # (direct 0: the parent's lunge carries the weight onto the plant foot and
    # the kicking leg winds back before the kick; stage < 1.5 stops there, on
    # the plant foot, for practice)
    if @direct < ~0.5
      add_lunge_plant(mv)
      if @stage < ~1.5
        p = kick_stance(base_posture)
        wleg(p, "r", @th_back, @knee_back, @ankle_back)
        mv.add(chunk("hold", ~0.3, p, :hold, :l, :l).hold_until(Latch.after(~100.0)))
        return mv
    add_kick(mv)
    mv

  # (rk4) the plant step's placement, yaw-compensated (see rk_yawc).
  -> place(f, off)
    return super(f, off) if !@rk4
    hx = f.at("l_hip_pos", 0)
    hy = f.at("l_hip_pos", 1)
    hz = f.at("l_hip_pos", 2)
    c = Math.cos(@yaw * @rk_yawc)
    sn = Math.sin(@yaw * @rk_yawc)
    dx = @plant_x - hx
    dy = plant_y - hy
    fx = dx * c + dy * sn
    fy = dy * c - dx * sn
    a = MyoSoccerLeg.ik(fx, hz - ~0.07)
    p = @reach_posture
    joint_offset(off, "hip_flexion_l", @k_ik * (a[0] + @tilt - p.get("hip_flexion_l")))
    joint_offset(off, "knee_angle_l", @k_ik * (a[1] - p.get("knee_angle_l")))
    joint_offset(off, "ankle_angle_l", @k_ik * (a[1] - a[0] + @reach_pitch - p.get("ankle_angle_l")))
    rho = ~0.0 - Math.atan2(f.at("pelvis_upv", 1), f.at("pelvis_upv", 2))
    add = rho - Math.atan2(fy, hz - ~0.07)
    joint_offset(off, "hip_adduction_l", @k_py * (add - p.get("hip_adduction_l")))
    off
