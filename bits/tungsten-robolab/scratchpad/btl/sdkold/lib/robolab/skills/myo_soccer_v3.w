# MyoSoccerV3Skill: round-3 soccer. MyoSoccerSkill (lib/robolab/skills/
# myo_soccer.w, unchanged) plus, each behind a params-file switch whose
# tunables are only declared when it is on (so every older params file
# replays as MyoSoccerSkill):
#
#   bal 1     the single-leg balance routine of the soccer_single_leg trial:
#             settle, shift the weight over the left foot, lift the right foot
#             and stand on the left leg for b_hold seconds, put it down, shift
#             back, then the same on the right leg
#
#             b_set ──(t)──> b_shift ──(swing foot unloaded)──> b_lift ──(t)──>
#             b_hold ──(t)──> b_down ──(swing foot loaded)──> b_mid ──(t)──> ...
#
#   ap3 1     the phase-2 approach as quasi-static steps built from the same
#             chunks (see ap3_movement), then the parent's kick
#   inside 1  the inside-of-the-foot kick (see inside_movement); with ap3 the
#             approach walks to its own spots and heading first
#   sb_ap 1   the parent's approach steps balance on the controller below
#   dec 1     hip offsets through the hip's stiffness (MyoSoccerHip3.pure);
#             dec_nf 1 keeps the flexion term plain
#   sbf 1     single support measures the COM in the joints' own frames
#
# Single support (`sb_*`) is its own controller, written per stance side
# with sigma = +1 on the left leg and -1 on the right, so both legs share
# one set of gains. With ey the COM's outward offset from the stance foot's
# centre (toward the stance side) and vo its outward velocity:
#
#   ankle      stance ankle flexion on the COM's fore-aft error (ankle strategy)
#   subtalar   stance inversion on ey + tau vo (the COP rolls to the outer
#              edge and the shank tilts back in: frontal ankle strategy)
#   hip        stance hip adduction on ey + tau vo (the pelvis and trunk tilt
#              toward the swing side; a negative tau turns the velocity term
#              into the fast hip strategy, the trunk thrown into the fall)
#              and on the swing side's pelvis drop (the gluteus medius
#              against Trendelenburg), plus an optional integral
#   swing leg  its hip abducts as a counterweight while the COM is outward
#   trunk      lumbar lateral bend holding the thorax at sb_lean over the
#              stance leg; lumbar pitch servo and postural tone as in the kick
#   yaw        the stance hip's rotators hold the pelvis heading (sb_kyaw
#              through `dec`, sb_kyp as a plain rotation offset)
#   tone       an antigravity drive on the stance leg, a feed-forward drive on
#              its abductors, co-contraction of its ankle (and optionally of
#              its hip rotators, sb_rot_cc), with the stance leg's reflex
#              gain sb_g
#
# Single or double support is decided by the loads (the swing foot below
# sb_ds_load), not by the phase: a weight shift that unloads the swing foot
# early is already single support, and the double-support hip terms (which
# push the pelvis toward the loaded foot) never act on one leg, where they
# feed a fall outward.
#
# Measured on this model and built around: the feet spin easily (their
# ground contacts sit within a few cm and have no torsional friction, so a
# hip rotation torque turns a lightly loaded foot, not the pelvis); the hip's
# internal rotators give ~54 N m, the external ~120 N m; stepping with the
# left leg (the plant) twists the pelvis ~0.6 rad toward it.
#
# Signs, measured on the model: subtalar + is inversion, hip adduction +
# adducts and hip rotation + turns the toes in on both legs, lat_bending +
# bends the trunk to the right.

# The hip's stiffness under the reflexes, K = sum_i F_i L_i kp_i sl_i sl_i^T
# over (flexion, adduction, rotation) as in MyoSoccerHip, kept whole so a
# servo can ask for each axis's own torque without the cross-axis leak.
+ MyoSoccerHip3
  -> new(geom, side, kp)
    js = [geom.joint("hip_flexion_" + side), geom.joint("hip_adduction_" + side), geom.joint("hip_rotation_" + side)]
    k = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    seen = {}
    js.each ->(j)
      geom.crossing(j).each ->(m)
        if !seen.key?(m)
          seen[m] = true
          sl = js.map ->(jj) geom.contraction_slope(m, jj)
          rg = geom.range(m)
          w = geom.force(m) * (rg[1] - rg[0]) * kp[m]
          a = 0
          while a < 3
            b = 0
            while b < 3
              k[a * 3 + b] = k[a * 3 + b] + w * sl[a] * sl[b]
              b += 1
            a += 1
    @k = k
    @kinv = MyoSoccerHip.invert3(k)

  # Offsets (flexion, adduction, rotation) whose torques are the ones plain
  # offsets (df, da, dr) would produce through the diagonal stiffness alone.
  -> pure(df, da, dr)
    k = @k
    ki = @kinv
    tf = k[0] * df
    ta = k[4] * da
    tr = k[8] * dr
    [ki[0] * tf + ki[1] * ta + ki[2] * tr, ki[3] * tf + ki[4] * ta + ki[5] * tr, ki[6] * tf + ki[7] * ta + ki[8] * tr]

+ MyoSoccerV3Skill < MyoSoccerSkill
  -> start(frame, ctl)
    super(frame, ctl)
    @abd_l = abductors("l")
    @abd_r = abductors("r")
    @ank_l = ankle_muscles("l")
    @ank_r = ankle_muscles("r")
    @rot_l = rotators("l")
    @rot_r = rotators("r")
    if @ap3
      bx = frame.at("env_ball_pos", 0)
      by = frame.at("env_ball_pos", 1)
      @g3_l = [bx - ~1.077 + @s3_goal_dx, by + ~0.0895]
      @g3_r = [bx - ~1.0775 + @s3_goal_dx, by - ~0.0925]
      if @inside
        @g3_l = [bx + @in_pdx, by + @in_pdy]
        @g3_r = [bx + @in_rdx, by + @in_rdy]
    if @inside
      @plant_x = frame.at("env_ball_pos", 0) + @in_pdx
      @plant_y = frame.at("env_ball_pos", 1) + @in_pdy
    @hip3 = {}
    if @dec
      @hip3["l"] = MyoSoccerHip3.new(@g, "l", @kp_arr)
      @hip3["r"] = MyoSoccerHip3.new(@g, "r", @kp_arr)
    self

  -> switch_on(name)
    return false if !@params.key?(name)
    @params[name] > ~0.5

  -> read_params
    super
    @bal = switch_on("bal")
    @dec = switch_on("dec")
    # dec_nf 1: the flexion term stays a plain offset (measured: the hip's
    # rotation stiffness is ~13x below its flexion stiffness and 0.42
    # coupled to it, so a decoupled flexion offset carries ~1.5x its size in
    # external rotation, which turns the pelvis to the rotation limit)
    @dec_nf = switch_on("dec_nf")
    # sbf 1: single support measures the COM's offsets in the frames the
    # joints act in instead of the world's: fore-aft along the stance foot
    # (ankle), lateral across it (subtalar), lateral across the pelvis (hip
    # ab/adduction, the swing leg's counterweight); the target (sb_x, sb_y)
    # is in the foot's frame. With the pelvis free to yaw 0.5-0.8 rad on one
    # leg, world-x/y errors drive the wrong joints.
    @sbf = switch_on("sbf")
    @inside = switch_on("inside")
    # in_direct 1: the swing starts the moment the plant foot lands (the
    # parent's running kick), the pelvis turned during the swing itself
    @in_direct = switch_on("in_direct")
    # sb_ap 1: the approach's single-support phases (ap_lift, ap_reach: the
    # phase-2 approach steps and the kv2 plant step) balance with the
    # single-support controller below instead of the kick's terms
    @sb_ap = switch_on("sb_ap")
    # ap3 1: the phase-2 approach as quasi-static steps built from the
    # single-leg routine's chunks (shift, lift, then an IK-placed reach until
    # the foot takes weight, then the COM back between the feet), then the
    # kick from the stance spots
    @ap3 = switch_on("ap3")
    bal_params if @bal || @ap3
    ds_params if @bal || @inside || @ap3
    sb_params if @bal || @inside || @sb_ap || @ap3
    ap3_params if @ap3
    in_params if @inside
    self

  # The single-leg routine's timing and postures.
  -> bal_params
    @b_t_set = param("b_t_set", ~0.4, ~0.1, ~1.5)
    @b_t_shift = param("b_t_shift", ~0.6, ~0.2, ~1.2)
    @b_unload = param("b_unload", ~0.1, ~0.02, ~0.4)
    @b_t_lift = param("b_t_lift", ~0.25, ~0.1, ~0.6)
    @b_hold = param("b_hold", ~2.9, ~2.0, ~4.0)
    @b_t_down = param("b_t_down", ~0.3, ~0.1, ~0.8)
    @b_load = param("b_load", ~0.2, ~0.05, ~0.5)
    @b_t_mid = param("b_t_mid", ~0.5, ~0.2, ~1.2)
    @b_shift_add = param("b_shift_add", ~0.1, ~-0.1, ~0.3)
    # the lift waits for the COM's capture point (position + velocity x
    # sqrt(h / g)) to be within b_cp_tol of the stance foot's target
    @b_cp_tol = param("b_cp_tol", ~0.03, ~0.005, ~0.1)
    # the one-leg posture: stance leg offsets from the stance, its hip
    # adducted b_add (pelvis over the foot); swing thigh, knee, ankle and
    # adduction
    @b_st_hip = param("b_st_hip", ~0.0, ~-0.4, ~0.4)
    @b_st_knee = param("b_st_knee", ~0.0, ~-0.3, ~0.5)
    @b_st_ankle = param("b_st_ankle", ~0.0, ~-0.3, ~0.3)
    @b_add = param("b_add", ~0.08, ~-0.2, ~0.3)
    @b_sw_th = param("b_sw_th", ~0.2, ~-0.3, ~0.9)
    @b_sw_knee = param("b_sw_knee", ~1.0, ~0.3, ~1.8)
    @b_sw_ankle = param("b_sw_ankle", ~0.1, ~-0.4, ~0.4)
    @b_sw_add = param("b_sw_add", ~0.0, ~-0.3, ~0.3)
    self

  # Double-support balance while the weight moves (the routine's set, shift
  # and mid; the inside kick's plant until the kicking foot is off).
  -> ds_params
    @b_x = param("b_x", @x_des, ~-0.05, ~0.15)
    @b_kax = param("b_kax", @k_ax, ~0.0, ~8.0)
    @b_kaxv = param("b_kaxv", @k_axv, ~0.0, ~2.0)
    @b_kay = param("b_kay", @k_ay, ~0.0, ~10.0)
    @b_kayv = param("b_kayv", @k_ayv, ~0.0, ~2.0)
    @b_kst2 = param("b_kst2", @k_st2, ~-4.0, ~4.0)
    @b_kyaw = param("b_kyaw", @k_yaw, ~-1.0, ~3.0)
    @b_kyawd = param("b_kyawd", @k_yawd, ~-0.3, ~0.5)
    self

  # The quasi-static approach (see ap3_movement).
  -> ap3_params
    @s3_max_x = param("s3_max_x", ~0.25, ~0.1, ~0.4)
    @s3_max_y = param("s3_max_y", ~0.15, ~0.05, ~0.3)
    @s3_min_sep = param("s3_min_sep", ~0.14, ~0.08, ~0.3)
    @s3_max_split = param("s3_max_split", ~0.3, ~0.15, ~0.5)
    @s3_tol = param("s3_tol", ~0.06, ~0.02, ~0.15)
    @s3_goal_dx = param("s3_goal_dx", ~0.0, ~-0.1, ~0.6)
    @s3_reach_dx = param("s3_reach_dx", ~0.15, ~-0.1, ~0.4)
    @s3_reach_dz = param("s3_reach_dz", ~0.77, ~0.6, ~0.8)
    @s3_t_reach = param("s3_t_reach", ~0.4, ~0.1, ~1.0)
    @s3_reach_max = param("s3_reach_max", ~1.0, ~0.3, ~2.0)
    @s3_load = param("s3_load", ~0.2, ~0.05, ~0.5)
    @s3_t_mid = param("s3_t_mid", ~0.4, ~0.1, ~1.0)
    @s3_t_hold = param("s3_t_hold", ~0.3, ~0.05, ~1.0)
    # the heading the approach walks to (the stance hips hold it, each swing
    # foot lands pointing along it: swing hip rotation s3_yawr x the pelvis's
    # error from it), so the body can arrive turned
    @s3_head = param("s3_head", ~0.0, ~-1.0, ~0.5)
    @s3_yawr = param("s3_yawr", ~0.6, ~0.0, ~1.5)
    # the swing foot's path: the ankle target rides s3_clr above the ground
    # until the foot is within s3_near of its spot, and the step lands (the
    # foot takes weight) only there
    @s3_clr = param("s3_clr", ~0.06, ~0.0, ~0.15)
    @s3_near = param("s3_near", ~0.08, ~0.03, ~0.2)
    @s3_k_ik = param("s3_k_ik", ~0.8, ~0.0, ~1.2)
    @s3_k_py = param("s3_k_py", ~0.8, ~0.0, ~1.2)
    # foot placement as balance: the target moves by s3_cp (lateral) and
    # s3_cpx (fore-aft) seconds of the COM's velocity, and the foot is put
    # down wherever it is once the COM's capture point has left the stance
    # foot by s3_fall toward the swing side
    @s3_cp = param("s3_cp", ~0.2, ~0.0, ~0.6)
    @s3_cpx = param("s3_cpx", ~0.0, ~0.0, ~0.6)
    @s3_fall = param("s3_fall", ~0.04, ~0.0, ~0.15)
    self

  # The inside-of-the-foot kick (see add_inside_kick).
  -> in_params
    # the plant: left ankle target relative to the ball, the pelvis heading
    # held through the run-up (right stance hip), the plant foot turned by
    # the left hip's rotation as it lands (+ toes in, to the right)
    @in_pdx = param("in_pdx", ~-0.25, ~-0.9, ~0.1)
    @in_pdy = param("in_pdy", ~0.3, ~0.0, ~0.55)
    # with ap3: the approach ends with the plant foot's centre at in_pdx,
    # in_pdy from the ball and the kicking foot's at in_rdx, in_rdy
    @in_rdx = param("in_rdx", ~-0.5, ~-1.0, ~-0.1)
    @in_rdy = param("in_rdy", ~-0.1, ~-0.5, ~0.2)
    # pre-turn, in double support: the weight toward the left foot while
    # the right hip turns the lightly loaded right foot out to in_rfoot (the
    # feet spin easily when unloaded), then the weight back toward it while
    # both hips turn the pelvis to in_yaw0: the turned-out right foot then
    # caps how far the plant step can twist the pelvis back (hip range)
    @in_piv_t = param("in_piv_t", ~0.0, ~0.0, ~1.5)
    @in_piv_dy = param("in_piv_dy", ~0.06, ~0.0, ~0.12)
    @in_rfoot = param("in_rfoot", ~-0.6, ~-1.0, ~0.0)
    @in_kpiv = param("in_kpiv", ~1.5, ~0.0, ~4.0)
    # the right ankle pulled up in the pivot (toes off the ground: the foot
    # turns on its heel)
    @in_piv_ank = param("in_piv_ank", ~0.3, ~0.0, ~0.6)
    @in_yaw0 = param("in_yaw0", ~-0.3, ~-0.8, ~0.2)
    @in_t_turn = param("in_t_turn", ~0.0, ~0.0, ~1.5)
    @in_turn_dy = param("in_turn_dy", ~0.03, ~-0.05, ~0.1)
    @in_yaw_run = param("in_yaw_run", ~0.0, ~-0.8, ~0.3)
    @in_kyaw_run = param("in_kyaw_run", ~1.0, ~0.0, ~5.0)
    @in_plant_rot = param("in_plant_rot", ~0.7, ~-0.5, ~1.0)
    # the strike's pelvis heading (turned toward the kicking side so the
    # turned-out foot's inside faces the goal), held by the plant hip
    @in_yaw = param("in_yaw", ~-0.6, ~-1.0, ~0.2)
    @in_kyaw = param("in_kyaw", ~2.0, ~-3.0, ~5.0)
    @in_kyawd = param("in_kyawd", ~0.1, ~-0.2, ~0.6)
    @in_yaw_load = param("in_yaw_load", ~0.4, ~0.05, ~1.0)
    # the turn: once the kicking foot is off, the plant hip turns the
    # pelvis; the swing starts when the heading is within in_yaw_tol (or
    # after in_t_cock)
    @in_yaw_tol = param("in_yaw_tol", ~0.1, ~0.02, ~0.4)
    @in_t_cock = param("in_t_cock", ~0.6, ~0.1, ~1.5)
    @in_t_plant = param("in_t_plant", ~0.6, ~0.1, ~1.5)
    # the plant: both feet down, the COM eased to in_plant_w of the way from
    # the right foot to the left, both hips turning the pelvis (the right
    # hip's share in_kyaw_r: its internal rotators are weak)
    @in_plant_w = param("in_plant_w", ~0.7, ~0.3, ~1.1)
    @in_kyaw_r = param("in_kyaw_r", ~0.5, ~0.0, ~2.0)
    # backswing and strike postures of the kicking leg (joint angles: hip
    # flexion, adduction, rotation (- = turned out), knee, ankle (+ up))
    @in_hf_b = param("in_hf_b", ~-0.2, ~-0.5, ~0.6)
    @in_add_b = param("in_add_b", ~-0.5, ~-0.85, ~0.2)
    @in_rot_b = param("in_rot_b", ~-0.66, ~-0.7, ~0.2)
    @in_knee_b = param("in_knee_b", ~1.0, ~0.2, ~1.8)
    @in_ank_b = param("in_ank_b", ~0.3, ~-0.3, ~0.52)
    @in_hf_k = param("in_hf_k", ~0.6, ~-0.2, ~1.4)
    @in_add_k = param("in_add_k", ~-0.1, ~-0.6, ~0.5)
    @in_rot_k = param("in_rot_k", ~-0.66, ~-0.7, ~0.2)
    @in_knee_k = param("in_knee_k", ~0.7, ~0.0, ~1.5)
    @in_ank_k = param("in_ank_k", ~0.35, ~-0.3, ~0.52)
    @in_sub_k = param("in_sub_k", ~-0.15, ~-0.35, ~0.35)
    @in_t_swing = param("in_t_swing", ~0.15, ~0.05, ~0.4)
    # the swing: hip flexor and adductor bursts, the ankle co-contracted;
    # reflex gains of the kicking leg (loose), its ankle and its rotators
    # (firm), and a joint servo holding the ankle and the turn-out
    @in_drv_flex = param("in_drv_flex", ~0.6, ~0.0, ~1.0)
    @in_drv_add = param("in_drv_add", ~0.6, ~0.0, ~1.0)
    @in_drv_ank = param("in_drv_ank", ~0.2, ~0.0, ~0.6)
    @in_g_kick = param("in_g_kick", ~0.5, ~0.0, ~1.5)
    @in_g_ank = param("in_g_ank", ~1.5, ~0.0, ~4.0)
    @in_g_rot = param("in_g_rot", ~1.5, ~0.0, ~4.0)
    @in_servo = param("in_servo", ~1.0, ~0.0, ~3.0)
    self

  # Single-support controller gains (see the header).
  -> sb_params
    @sb_x = param("sb_x", ~0.03, ~-0.08, ~0.12)
    @sb_y = param("sb_y", ~0.0, ~-0.06, ~0.06)
    @sb_kax = param("sb_kax", @k_ax, ~0.0, ~8.0)
    @sb_kaxv = param("sb_kaxv", @k_axv, ~0.0, ~2.0)
    @sb_kst = param("sb_kst", ~3.0, ~-4.0, ~8.0)
    @sb_kstv = param("sb_kstv", ~0.3, ~-0.5, ~1.5)
    @sb_kha = param("sb_kha", ~0.0, ~-4.0, ~4.0)
    @sb_khav = param("sb_khav", ~0.3, ~-1.5, ~1.5)
    @sb_kpr = param("sb_kpr", ~1.0, ~-1.0, ~4.0)
    @sb_kprd = param("sb_kprd", ~0.1, ~-0.3, ~0.6)
    @sb_pr_des = param("sb_pr_des", ~0.0, ~-0.15, ~0.15)
    @sb_ksw = param("sb_ksw", ~1.0, ~-3.0, ~5.0)
    @sb_kswv = param("sb_kswv", ~0.3, ~-1.5, ~1.5)
    @sb_klb = param("sb_klb", ~0.5, ~-2.0, ~3.0)
    @sb_lean = param("sb_lean", ~0.0, ~-0.2, ~0.3)
    @sb_kyaw = param("sb_kyaw", ~1.0, ~-1.0, ~4.0)
    @sb_kyawd = param("sb_kyawd", ~0.1, ~-0.3, ~0.6)
    @sb_khp = param("sb_khp", @k_hp, ~0.0, ~3.0)
    @sb_khpd = param("sb_khpd", @k_hpd, ~0.0, ~0.8)
    @sb_g = param("sb_g", ~1.0, ~0.5, ~3.0)
    @sb_drv = param("sb_drv", ~0.0, ~0.0, ~0.5)
    @sb_drv_abd = param("sb_drv_abd", ~0.05, ~0.0, ~0.5)
    @sb_cc = param("sb_cc", ~0.0, ~0.0, ~0.4)
    @sb_ds_load = param("sb_ds_load", ~0.1, ~0.02, ~0.4)
    # heading servo as plain rotation offsets on the stance hip (sb_kyp,
    # sb_kypd; b_kyp, b_kypd in double support), beside the decoupled one
    # (measured: with dec on, the decoupled rotation offsets turn the
    # pelvis the wrong way), and an integral of the COM's outward offset on
    # the stance hip's adduction (slow drift)
    @sb_kyp = param("sb_kyp", ~0.0, ~-1.0, ~4.0)
    @sb_kypd = param("sb_kypd", ~0.0, ~-0.3, ~0.6)
    @b_kyp = param("b_kyp", ~0.0, ~-1.0, ~4.0)
    @b_kypd = param("b_kypd", ~0.0, ~-0.3, ~0.6)
    @sb_ki = param("sb_ki", ~0.0, ~-10.0, ~20.0)
    @sb_ki_lim = param("sb_ki_lim", ~0.1, ~0.0, ~0.3)
    # co-contraction of the stance hip's rotators (both directions): the
    # rotation axis is ~13x softer than flexion, and the pelvis yaws to its
    # limit on one leg
    @sb_rot_cc = param("sb_rot_cc", ~0.0, ~0.0, ~0.5)
    @sb_int = ~0.0
    self

  # ---- muscles ------------------------------------------------------------------

  # The hip's abductors on one side (their contraction rises as the hip
  # abducts).
  -> abductors(side)
    out = []
    agonists("hip_adduction_" + side, ~-1.0, ~0.1).each ->(i) out.push(i) if @is_leg[i]
    out

  # The hip's rotators on one side, both directions.
  -> rotators(side)
    out = []
    [~1.0, ~-1.0].each ->(sg)
      agonists("hip_rotation_" + side, sg, ~0.2).each ->(i) out.push(i) if !out.include?(i) && @is_leg[i]
    out

  # Every muscle that moves the ankle or the subtalar joint of one side.
  -> ankle_muscles(side)
    out = []
    ["ankle_angle_", "subtalar_angle_"].each ->(jn)
      [~1.0, ~-1.0].each ->(sg)
        agonists(jn + side, sg, ~0.1).each ->(i) out.push(i) if !out.include?(i)
    out

  # ---- phases -------------------------------------------------------------------

  -> v3_phase?
    return true if kick_phase? || turn_phase? || @phase == :s3_reach
    @phase == :b_set || @phase == :b_shift || @phase == :b_lift || @phase == :b_hold || @phase == :b_down || @phase == :b_mid

  # The inside kick's run-up: the parent's set, shift, lift and reach.
  -> run_up?
    @phase == :set || @phase == :shift || @phase == :lift || @phase == :reach

  # The inside kick's pre-turn (double support).
  -> turn_phase?
    @phase == :in_piv || @phase == :in_turn

  -> kick_phase?
    @phase == :in_plant || @phase == :in_cock || @phase == :in_swing

  -> single?
    @support == :l || @support == :r

  -> other_side(sd)
    return "l" if sd == "r"
    "r"

  # The leg the routine is putting the weight on (shift) or standing on
  # (lift, hold, down; the inside kick's plant and swing); "" in
  # double-support phases.
  -> b_stance_side
    return "l" if @phase == :in_cock || @phase == :in_swing
    return "l" if sb_ap_phase? && @support == :l
    return "r" if sb_ap_phase? && @support == :r
    return "l" if @phase == :in_plant && foot_load("r") < @sb_ds_load
    return "l" if @phase == :b_shift && @lat_to == :l
    return "r" if @phase == :b_shift && @lat_to == :r
    return "l" if @support == :l
    return "r" if @support == :r
    ""

  # The pelvis heading the stance hips hold: the inside kick's strike heading
  # in its plant and swing, else straight at the goal.
  -> yaw_ref
    return @in_yaw if kick_phase?
    return @s3_head if @ap3 && s3_phase?
    ~0.0

  # The ap3 approach's chunks (they reuse the routine's phases).
  -> s3_phase?
    @phase == :b_set || @phase == :b_shift || @phase == :b_lift || @phase == :s3_reach || @phase == :b_mid

  # A new chunk: the parent's bookkeeping, and the single-support integral
  # starts from zero on each leg.
  -> enter(f, phase, support, lat)
    super(f, phase, support, lat)
    @sb_int = ~0.0 if phase == :b_shift || phase == :in_plant
    self

  # ---- movement -----------------------------------------------------------------

  -> movement
    return bal_movement if @bal
    return ap3_movement if @ap3
    return inside_movement if @inside
    super

  # ---- quasi-static approach (ap3) -----------------------------------------------
  #
  #   s3_hold ──(t)──> branch: a step, or the kick when both feet are on
  #   their spots (the phase-1 key-frame feet relative to the ball, moved
  #   s3_goal_dx toward it)
  #   X_s3shift ──(X foot unloaded, capture point over the stance foot)──>
  #   X_s3lift ──(t)──> X_s3reach ──(X foot loaded)──> X_s3mid ──(t)──> branch
  #
  # Shift, lift and the one-leg posture are the single-leg routine's (bal
  # params), the reach places the foot with the parent's IK (place_step) while
  # the single-support controller keeps the COM over the stance foot.
  -> ap3_movement
    mv = Movement.new("ap3")
    ch = chunk("s3_hold", ~0.3, stance, :b_set, :both, :mid).hold_until(Latch.after(@s3_t_hold))
    ch.branch(->(f, c) next3(f))
    mv.add(ch)
    add_step3(mv, "l")
    add_step3(mv, "r")
    if @inside
      add_inside_kick(mv)
      return mv
    add_run_up(mv)
    add_kick(mv)
    mv

  -> add_step3(mv, sd)
    st = other_side(sd)
    ss = :l
    ss = :r if st == "r"
    p = stance
    p.set("hip_adduction_" + st, p.get("hip_adduction_" + st) + @b_shift_add)
    p.set("hip_adduction_" + sd, p.get("hip_adduction_" + sd) - @b_shift_add)
    unl = Latch.test(sd + "_s3unl", ->(f, e, c) foot_load(sd) < @b_unload && captured?(f, st))
    mv.add(chunk(sd + "_s3shift", @b_t_shift, p, :b_shift, :both, ss).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + ~1.0))
    p = one_leg_posture(st)
    mv.add(chunk(sd + "_s3lift", @b_t_lift, p, :b_lift, ss, ss).hold_until(Latch.after(@b_t_lift)))
    p = one_leg_posture(st)
    tleg(p, sd, @s3_reach_dx, @s3_reach_dz, @ap_reach_pitch, @tilt0)
    @ap_postures[sd] = p
    down = Latch.test(sd + "_s3down", ->(f, e, c) foot_load(sd) > @s3_load && (s3_dist(f) < @s3_near * ~1.5 || s3_falling?(f, st)))
    mv.add(chunk(sd + "_s3reach", @s3_t_reach, p, :s3_reach, ss, ss).hold_until(down.after_min(@s3_t_reach * ~0.5), @s3_reach_max))
    ch = chunk(sd + "_s3mid", ~0.3, stance, :b_mid, :both, :mid).hold_until(Latch.after(@s3_t_mid))
    ch.branch(->(f, c) next3(f))
    mv.add(ch)
    mv

  # The next step (the foot whose clipped step makes more progress toward
  # its spot, as the parent's next_step), or the kick.
  -> next3(f)
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    el = [@g3_l[0] - l[0], @g3_l[1] - l[1]]
    er = [@g3_r[0] - r[0], @g3_r[1] - r[1]]
    nl = Math.sqrt(el[0] * el[0] + el[1] * el[1])
    nr = Math.sqrt(er[0] * er[0] + er[1] * er[1])
    if (nl < @s3_tol && nr < @s3_tol) || @steps >= 12
      return "in_plant" if @inside
      return "set"
    dlx = clip(el[0], @s3_max_x)
    dly = clip(el[1], @s3_max_y)
    dly = r[1] + @s3_min_sep - l[1] if l[1] + dly < r[1] + @s3_min_sep
    dlx = clip(l[0] + dlx - r[0], @s3_max_split) + r[0] - l[0]
    drx = clip(er[0], @s3_max_x)
    dry = clip(er[1], @s3_max_y)
    dry = l[1] - @s3_min_sep - r[1] if r[1] + dry > l[1] - @s3_min_sep
    drx = clip(r[0] + drx - l[0], @s3_max_split) + l[0] - r[0]
    gl = nl - Math.sqrt((el[0] - dlx) * (el[0] - dlx) + (el[1] - dly) * (el[1] - dly))
    gr = nr - Math.sqrt((er[0] - drx) * (er[0] - drx) + (er[1] - dry) * (er[1] - dry))
    gl = gl * ~0.5 if @last_side == "l"
    gr = gr * ~0.5 if @last_side == "r"
    @steps += 1
    if gl >= gr
      @step_side = "l"
      @step_to = [l[0] + dlx, l[1] + dly]
      @last_side = "l"
      return "l_s3shift"
    @step_side = "r"
    @step_to = [r[0] + drx, r[1] + dry]
    @last_side = "r"
    "r_s3shift"

  # The soccer_single_leg routine: the left leg, then the right, then stand.
  -> bal_movement
    mv = Movement.new("bal")
    mv.add(chunk("b_set", ~0.3, stance, :b_set, :both, :mid).hold_until(Latch.after(@b_t_set)))
    add_one_leg(mv, "l")
    add_one_leg(mv, "r")
    mv.add(chunk("b_end", ~0.3, stance, :b_mid, :both, :mid).hold_until(Latch.after(~100.0)))
    mv

  -> add_one_leg(mv, st)
    sw = "r"
    sw = "l" if st == "r"
    ss = :l
    ss = :r if st == "r"
    # shift: the COM eased over the stance foot until the swing foot unloads
    p = stance
    p.set("hip_adduction_" + st, p.get("hip_adduction_" + st) + @b_shift_add)
    p.set("hip_adduction_" + sw, p.get("hip_adduction_" + sw) - @b_shift_add)
    unl = Latch.test(st + "_bunl", ->(f, e, c) foot_load(sw) < @b_unload && captured?(f, st))
    mv.add(chunk("b_shift_" + st, @b_t_shift, p, :b_shift, :both, ss).hold_until(unl.after_min(@b_t_shift * ~0.5), @b_t_shift + ~1.0))
    # lift, then hold on one leg
    p = one_leg_posture(st)
    mv.add(chunk("b_lift_" + st, @b_t_lift, p, :b_lift, ss, ss).hold_until(Latch.after(@b_t_lift)))
    mv.add(chunk("b_hold_" + st, ~0.2, p, :b_hold, ss, ss).hold_until(Latch.after(@b_hold)))
    # down: the swing foot back on the ground, then the COM back between the feet
    down = Latch.test(st + "_bdown", ->(f, e, c) foot_load(sw) > @b_load)
    mv.add(chunk("b_down_" + st, @b_t_down, stance, :b_down, ss, ss).hold_until(down.after_min(@b_t_down * ~0.5), ~1.0))
    mv.add(chunk("b_mid_" + st, ~0.3, stance, :b_mid, :both, :mid).hold_until(Latch.after(@b_t_mid)))
    mv

  # The COM's lateral capture point (y + vy sqrt(h / g), h ~ 0.95 m) within
  # b_cp_tol of the single-support target over the `st` foot.
  -> captured?(f, st)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    fc = foot_center(f, st)
    cp = f.at("com_pos", 1) + f.at("com_vel", 1) * ~0.311
    (cp - fc[1] - sg * @sb_y).abs < @b_cp_tol

  # Standing on `st`: the stance leg (stance posture plus offsets, hip
  # adducted b_add so the pelvis sits over the foot) and the swing leg folded
  # (thigh at world angle b_sw_th, knee b_sw_knee).
  -> one_leg_posture(st)
    sw = "r"
    sw = "l" if st == "r"
    p = base_posture
    leg(p, st, @hip + @b_st_hip, @knee + @b_st_knee, @ankle + @b_st_ankle)
    p.set("hip_adduction_" + st, p.get("hip_adduction_" + st) + @b_add)
    wleg(p, sw, @b_sw_th, @b_sw_knee, @b_sw_ankle)
    p.set("hip_adduction_" + sw, p.get("hip_adduction_" + sw) + @b_sw_add)
    p

  # The inside-of-the-foot kick (P1 start). The model's hip turns out only
  # 0.7 rad and its knee does not rotate, so the foot's inside faces the goal
  # (measured on the model: within ~15 deg) only with the pelvis turned
  # 0.5-0.7 rad toward the kicking side, the hip turned out to its limit and
  # abducted, knee bent ~0.6-1.0, ankle up; the foot then travels at the ball
  # inside first when the hip flexes and adducts (the swing across the body).
  #
  #   set, shift, lift, reach   the parent's run-up, verbatim (reach: the left
  #                             foot IK-placed at the plant spot in_pdx, in_pdy
  #                             from the ball), the pelvis heading held at
  #                             in_yaw_run by the stance hip, the plant foot
  #                             turned by in_plant_rot as it lands
  #   in_plant                  the weight onto the left foot, the pelvis turned
  #                             to in_yaw by the plant hip; the right leg winds
  #                             back turned out, abducted, knee bent, ankle up
  #   in_swing                  hip flexor and adductor bursts sweep the foot
  #                             across the body, inside first -- LATCH touch
  #   follow, land, recover     the parent's
  -> inside_movement
    mv = Movement.new("inside")
    if @kv2 > ~0.5
      # the quasi-static route: the approach (phase 2; in phase 1 its hold
      # decides at once) and the kv2 plant step beside the ball (kp_dx,
      # kp_dy), then the plant turn, cock and swing
      add_approach(mv)
      add_plant_step(mv)
      add_inside_kick(mv)
      return mv
    mv.add(chunk("set", ~0.25, stance, :set, :both, :mid).hold_until(Latch.after(@t_set)))
    add_pre_turn(mv)
    add_run_up_steps(mv)
    add_inside_kick(mv)
    mv

  # The parent's kick run-up, verbatim: set, shift onto the right foot,
  # lift and reach with the left (IK-placed at the plant spot).
  -> add_run_up(mv)
    mv.add(chunk("set", ~0.25, stance, :set, :both, :mid).hold_until(Latch.after(@t_set)))
    add_run_up_steps(mv)

  -> add_pre_turn(mv)
    # (the pre-turn chunks only when given a duration)
    mv.add(chunk("in_piv", ~0.3, stance, :in_piv, :both, :l).hold_until(Latch.after(@in_piv_t))) if @in_piv_t > ~0.1
    mv.add(chunk("in_turn", ~0.3, stance, :in_turn, :both, :r).hold_until(Latch.after(@in_t_turn))) if @in_t_turn > ~0.1
    mv

  -> add_run_up_steps(mv)
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
    clear = Latch.test("clear", ->(f, e, c) f.at("l_foot_pos", 2) > @lift_h)
    mv.add(chunk("lift", @t_lift, p, :lift, :r, :r).hold_until(clear.after_min(@t_lift * ~0.5), ~0.5))
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
    mv

  -> add_inside_kick(mv)
    return add_inside_swing(mv) if @in_direct
    # plant: both feet down in the parent's lunge posture (split stance),
    # the COM travels forward between them and the pelvis turns
    p = base_posture
    tleg(p, "l", @lg_dx, @lg_dz, @lg_pitch, @tilt_step)
    p.set("hip_adduction_l", @add_pl)
    tleg(p, "r", @lr_dx, @lr_dz, @lr_pitch, @tilt_step)
    p.set("flex_extension", @fe_step)
    mv.add(chunk("in_plant", @in_t_plant, p, :in_plant, :both, :l).hold_until(Latch.after(@in_t_plant)))
    # cock: the right foot off, the leg wound back; the turn finishes
    p = kick_stance(base_posture)
    in_leg(p, @in_hf_b, @in_add_b, @in_rot_b, @in_knee_b, @in_ank_b)
    turned = Latch.test("turned", ->(f, e, c) (@yaw - @in_yaw).abs < @in_yaw_tol)
    mv.add(chunk("in_cock", ~0.1, p, :in_cock, :l, :l).hold_until(turned, @in_t_cock))
    add_inside_swing(mv)

  # The inside swing: hip flexor and adductor bursts sweep the turned-out
  # foot across the body, inside first -- LATCH touch; then the parent's
  # follow-through, landing and recovery.
  -> add_inside_swing(mv)
    p = kick_stance(base_posture)
    in_leg(p, @in_hf_k, @in_add_k, @in_rot_k, @in_knee_k, @in_ank_k)
    p.set("subtalar_angle_r", @in_sub_k)
    hit = Latch.test("touch", ->(f, e, c) f.get("ball_touch") > ~0.5)
    ch = chunk("in_swing", @in_t_swing, p, :in_swing, :l, :l).hold_until(hit, @in_t_swing * ~2.5)
    d = drive_on(@hip_flexors_r, @in_drv_flex)
    @hip_add_r.each ->(i) d[i] = d[i] + @in_drv_add
    @ankle_r.each ->(i) d[i] = d[i] + @in_drv_ank
    ch.drive(d)
    mv.add(ch)
    add_after_touch(mv)

  # The kicking leg as joint angles (hip flexion, adduction, rotation, knee,
  # ankle).
  -> in_leg(p, hf, add, rot, knee, ank)
    p.set("hip_flexion_r", hf)
    p.set("hip_adduction_r", add)
    p.set("hip_rotation_r", rot)
    p.set("knee_angle_r", knee)
    p.set("ankle_angle_r", ank)
    p

  -> plant_y
    return @plant_y if @inside
    super

  # ---- balance ------------------------------------------------------------------

  # The COM target of the routine: between the feet (set, mid: eased back
  # there), or over the stance foot (shift: eased there from where the COM
  # was when the shift began; the inside kick's plant: eased over the left
  # foot).
  -> b_target(f)
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    if turn_phase?
      dy = @in_piv_dy
      dy = ~0.0 - @in_turn_dy if @phase == :in_turn
      tm = [(l[0] + r[0]) * ~0.5 + @b_x, (l[1] + r[1]) * ~0.5 + dy]
      return eased(f, tm, ~0.4)
    if kick_phase?
      if @phase == :in_plant
        w = @in_plant_w
        tp = [r[0] + w * (l[0] - r[0]) + @sb_x, r[1] + w * (l[1] - r[1])]
        return eased(f, tp, @in_t_plant)
      return [l[0] + @sb_x, l[1] + @sb_y]
    mid = [(l[0] + r[0]) * ~0.5 + @b_x, (l[1] + r[1]) * ~0.5]
    return mid if @phase == :b_set
    return eased(f, mid, @b_t_mid) if @phase == :b_mid
    st = l
    sg = ~1.0
    if @lat_to == :r
      st = r
      sg = ~-1.0
    tg = [st[0] + @sb_x, st[1] + sg * @sb_y]
    return eased(f, tg, @b_t_shift) if @phase == :b_shift
    tg

  -> balance(f, ctl)
    if @inside && run_up?
      off = super(f, ctl)
      return run_up_yaw(f, off)
    return ap_single(f) if sb_ap_phase?
    return super(f, ctl) if !v3_phase?
    off = zeros
    rate = f.at("torso_angvel", 1)
    perr = @pitch - @pitch_des
    lumbar_offset(off, @k_th * perr + @k_thd * rate)
    if kick_phase?
      kick_servo(f, off) if @phase != :in_plant
      kick_yaw(f, off)
    # single support by the loads, not the phase: until the swing foot is
    # off the ground (and once it is down again) both legs balance
    st = b_stance_side
    if st != "" && foot_load(other_side(st)) < @sb_ds_load
      sb_single(f, off, perr, rate, st)
      place3(f, off) if @phase == :s3_reach
      return off
    joint_offset(off, "lat_bending", @k_lb * @roll)
    tg = b_target(f)
    ex = f.at("com_pos", 0) - tg[0]
    ey = f.at("com_pos", 1) - tg[1]
    da = ~0.0 - @b_kax * (ex + @b_kaxv * f.at("com_vel", 0))
    dy = ~0.0 - (@b_kay * ey + @b_kayv * f.at("com_vel", 1))
    hs = ~0.0 - (@k_hp * perr + @k_hpd * rate)
    yk = @b_kyaw
    ykd = @b_kyawd
    if kick_phase? || turn_phase?
      yk = ~0.0
      ykd = ~0.0
    turn_yaw(f, off) if turn_phase?
    y = yk * (@yaw - yaw_ref) + ykd * f.at("pelvis_angvel", 2)
    yp = ~0.0
    yp = @b_kyp * (@yaw - yaw_ref) + @b_kypd * f.at("pelvis_angvel", 2) if !kick_phase? && !turn_phase?
    ["l", "r"].each ->(sd)
      sg = ~1.0
      sg = ~-1.0 if sd == "r"
      joint_offset(off, "ankle_angle_" + sd, da)
      joint_offset(off, "subtalar_angle_" + sd, sg * @b_kst2 * dy)
      hip_off(off, sd, hs, sg * dy, ~0.0 - sg * y)
      joint_offset(off, "hip_rotation_" + sd, ~0.0 - sg * yp)
    off

  # sb_ap: an approach step's single support (lift, reach) on the
  # single-support controller, plus the parent's IK placement of the swing
  # foot in the reach.
  -> ap_single(f)
    off = zeros
    rate = f.at("torso_angvel", 1)
    perr = @pitch - @pitch_des
    lumbar_offset(off, @k_th * perr + @k_thd * rate)
    st = "l"
    st = "r" if @support == :r
    sb_single(f, off, perr, rate, st)
    place_step(f, off) if @phase == :ap_reach
    off

  # The swing ankle's distance to its target (the step's foot-centre spot,
  # 4 cm back, 1.5 cm medial).
  -> s3_ankle_target
    sd = @step_side
    ty = @step_to[1] - ~0.015
    ty = @step_to[1] + ~0.015 if sd == "r"
    [@step_to[0] - ~0.04, ty]

  # The live placement target: the spot, moved by the COM's velocity.
  -> s3_place_target(f)
    t = s3_ankle_target
    [t[0] + @s3_cpx * f.at("com_vel", 0), t[1] + @s3_cp * f.at("com_vel", 1)]

  # The capture point (COM + velocity x sqrt(h / g)) past the stance foot's
  # centre by s3_fall toward the swing side: the step must land now.
  -> s3_falling?(f, st)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    fc = foot_center(f, st)
    cp = f.at("com_pos", 1) + f.at("com_vel", 1) * ~0.311
    ~0.0 - sg * (cp - fc[1]) > @s3_fall

  -> s3_dist(f)
    t = s3_ankle_target
    dx = t[0] - f.at(@step_side + "_ankle_pos", 0)
    dy = t[1] - f.at(@step_side + "_ankle_pos", 1)
    Math.sqrt(dx * dx + dy * dy)

  # ap3 placement: live two-link IK from the swing hip to the ankle target
  # (as the parent's place_step, yaw-compensated by ap_yawc), the target
  # riding s3_clr above the ground until the foot is near its spot, and the
  # swing foot turned to land along the approach heading s3_head.
  -> place3(f, off)
    sd = @step_side
    hx = f.at(sd + "_hip_pos", 0)
    hy = f.at(sd + "_hip_pos", 1)
    hz = f.at(sd + "_hip_pos", 2)
    t = s3_place_target(f)
    zt = ~0.07 + @s3_clr * clamp(s3_dist(f) / @s3_near, ~0.0, ~1.0)
    c = Math.cos(@yaw * @ap_yawc)
    sn = Math.sin(@yaw * @ap_yawc)
    ddx = t[0] - hx
    ddy = t[1] - hy
    fx = ddx * c + ddy * sn
    fy = ddy * c - ddx * sn
    a = MyoSoccerLeg.ik(fx, hz - zt)
    p = @ap_postures[sd]
    joint_offset(off, "hip_flexion_" + sd, @s3_k_ik * (a[0] + @tilt - p.get("hip_flexion_" + sd)))
    joint_offset(off, "knee_angle_" + sd, @s3_k_ik * (a[1] - p.get("knee_angle_" + sd)))
    joint_offset(off, "ankle_angle_" + sd, @s3_k_ik * (a[1] - a[0] + @ap_reach_pitch - p.get("ankle_angle_" + sd)))
    rho = ~0.0 - Math.atan2(f.at("pelvis_upv", 1), f.at("pelvis_upv", 2))
    phi = Math.atan2(fy, hz - zt)
    add = rho - phi
    add = phi - rho if sd == "r"
    joint_offset(off, "hip_adduction_" + sd, @s3_k_py * (add - p.get("hip_adduction_" + sd)))
    e = s3_yawr_err
    joint_offset(off, "hip_rotation_" + @step_side, e) if @step_side == "r"
    joint_offset(off, "hip_rotation_" + @step_side, ~0.0 - e) if @step_side == "l"
    off

  # (+ turns the right toes left: the right hip's internal rotation to bring
  # its foot from the pelvis heading to s3_head; the left hip mirrors it)
  -> s3_yawr_err
    @s3_yawr * (@s3_head - @yaw)

  -> sb_ap_phase?
    @sb_ap && (@phase == :ap_lift || @phase == :ap_reach)

  # The inside kick's run-up: in the set the hips turn the pelvis to in_yaw0,
  # then the stance hip(s) hold it at in_yaw_run; the plant foot is turned by
  # in_plant_rot as it reaches. (Plain joint offsets: measured on the model,
  # MyoSoccerHip3's decoupled rotation turns the pelvis the wrong way.)
  -> run_up_yaw(f, off)
    tgt = @in_yaw_run
    tgt = ~0.0 if @phase == :set
    y = @in_kyaw_run * (@yaw - tgt + ~0.1 * f.at("pelvis_angvel", 2))
    joint_offset(off, "hip_rotation_r", y) if @support != :l
    joint_offset(off, "hip_rotation_l", ~0.0 - y) if @support == :both
    joint_offset(off, "hip_rotation_l", @in_plant_rot) if @phase == :reach
    off

  # The inside kick's pre-turn. Pivot: the right hip turns the right foot
  # (toes heading from the calcaneus to the toes) out to in_rfoot while the
  # left hip holds the pelvis heading; turn: both hips turn the pelvis to
  # in_yaw0 (right hip internal, left external).
  -> turn_yaw(f, off)
    yv = f.at("pelvis_angvel", 2)
    if @phase == :in_piv
      fy = Math.atan2(f.at("r_toe_pos", 1) - f.at("r_foot_pos", 1), f.at("r_toe_pos", 0) - f.at("r_foot_pos", 0))
      joint_offset(off, "hip_rotation_r", @in_kpiv * (@in_rfoot - fy))
      joint_offset(off, "ankle_angle_r", @in_piv_ank)
      joint_offset(off, "hip_rotation_l", ~0.0 - @in_kyaw_run * (@yaw + ~0.1 * yv))
      return off
    y = @in_kyaw_run * (@yaw - @in_yaw0 + ~0.1 * yv)
    joint_offset(off, "hip_rotation_r", y)
    joint_offset(off, "hip_rotation_l", ~0.0 - y)
    off

  # The inside kick's plant, cock and swing: the plant hip's rotators turn
  # the pelvis to in_yaw, eased in as the plant foot takes the weight and the
  # kicking foot leaves the ground (a foot that is not loaded would only
  # spin, and a planted kicking foot would pin the pelvis).
  -> kick_yaw(f, off)
    wl = clamp(foot_load("l") / @in_yaw_load, ~0.0, ~1.0)
    y = @in_kyaw * (@yaw - @in_yaw) + @in_kyawd * f.at("pelvis_angvel", 2)
    if @phase == :in_plant
      # both feet planted: the left hip turns out, the right hip in
      wr = clamp(foot_load("r") / @in_yaw_load, ~0.0, ~1.0)
      joint_offset(off, "hip_rotation_l", ~0.0 - wl * y)
      joint_offset(off, "hip_rotation_r", @in_kyaw_r * wr * y)
      return off
    wr = clamp(~1.0 - foot_load("r") / @in_yaw_load, ~0.0, ~1.0)
    joint_offset(off, "hip_rotation_l", ~0.0 - wl * wr * y)
    off

  # The kicking leg's ankle and turn-out held at the chunk's posture by a
  # joint servo on the measured angles (against the swing's inertia).
  -> kick_servo(f, off)
    p = @cur_post
    ["ankle_angle_r", "hip_rotation_r"].each ->(j)
      joint_offset(off, j, @in_servo * (p.get(j) - f.q(body, j)))
    off

  # Hip offsets (flexion, adduction, rotation) on one side; with `dec` on,
  # turned into the offsets giving each axis the torque the plain offset
  # would give it through its own stiffness alone (MyoSoccerHip3.pure): no
  # adduction servo that also twists the pelvis.
  -> hip_off(off, sd, df, da, dr)
    d = [df, da, dr]
    if @dec && @dec_nf
      d = @hip3[sd].pure(~0.0, da, dr)
      d[0] = d[0] + df
    elsif @dec
      d = @hip3[sd].pure(df, da, dr)
    joint_offset(off, "hip_flexion_" + sd, d[0])
    joint_offset(off, "hip_adduction_" + sd, d[1])
    joint_offset(off, "hip_rotation_" + sd, d[2])
    off

  # Single support on `st` (see the header). In the inside kick the free leg
  # is the kicking leg: no counterweight term on it.
  -> sb_single(f, off, perr, rate, st)
    sw = other_side(st)
    sg = ~1.0
    sg = ~-1.0 if st == "r"
    fc = foot_center(f, st)
    ex = f.at("com_pos", 0) - fc[0] - @sb_x
    ey = sg * (f.at("com_pos", 1) - fc[1]) - @sb_y
    vx = f.at("com_vel", 0)
    vo = sg * f.at("com_vel", 1)
    eh = ey
    vh = vo
    if @sbf
      # stance foot heading (heel to toes) and pelvis heading
      ph = Math.atan2(f.at(st + "_toe_pos", 1) - f.at(st + "_foot_pos", 1), f.at(st + "_toe_pos", 0) - f.at(st + "_foot_pos", 0))
      dx = f.at("com_pos", 0) - fc[0]
      dy = f.at("com_pos", 1) - fc[1]
      cf = Math.cos(ph)
      sf = Math.sin(ph)
      cvx = f.at("com_vel", 0)
      cvy = f.at("com_vel", 1)
      # foot frame: forward, and lateral (outward = +y for the left foot)
      ex = dx * cf + dy * sf - @sb_x
      ey = sg * (dy * cf - dx * sf) - @sb_y
      vx = cvx * cf + cvy * sf
      vo = sg * (cvy * cf - cvx * sf)
      # pelvis frame lateral
      cp = Math.cos(@yaw)
      sp = Math.sin(@yaw)
      eh = sg * (dy * cp - dx * sp) - @sb_y
      vh = sg * (cvy * cp - cvx * sp)
    joint_offset(off, "ankle_angle_" + st, ~0.0 - @sb_kax * (ex + @sb_kaxv * vx))
    joint_offset(off, "subtalar_angle_" + st, @sb_kst * (ey + @sb_kstv * vo))
    # stance hip: adduction on the COM's outward offset and on the swing
    # side's pelvis drop (+), rotation on the heading, flexion on the thorax
    # pitch
    drop = sg * @proll
    dropv = sg * f.at("pelvis_angvel", 0)
    add = @sb_kha * (eh + @sb_khav * vh) - @sb_kpr * (drop - @sb_pr_des) - @sb_kprd * dropv
    yk = @sb_kyaw
    ykd = @sb_kyawd
    if kick_phase?
      yk = ~0.0
      ykd = ~0.0
    y = yk * (@yaw - yaw_ref) + ykd * f.at("pelvis_angvel", 2)
    # (the integral runs only in single support; kept between ticks)
    @sb_int = clamp(@sb_int + @sb_ki * eh * ~0.01, ~0.0 - @sb_ki_lim, @sb_ki_lim)
    hip_off(off, st, ~0.0 - (@sb_khp * perr + @sb_khpd * rate), add + @sb_int, ~0.0 - sg * y)
    yp = @sb_kyp * (@yaw - yaw_ref) + @sb_kypd * f.at("pelvis_angvel", 2)
    joint_offset(off, "hip_rotation_" + st, ~0.0 - sg * yp) if !kick_phase?
    joint_offset(off, "hip_adduction_" + sw, ~0.0 - @sb_ksw * (eh + @sb_kswv * vh)) if !kick_phase? && @phase != :ap_reach && @phase != :s3_reach
    # thorax roll (+ leaning left) held at sb_lean toward the stance side
    joint_offset(off, "lat_bending", @sb_klb * (@roll - sg * @sb_lean))
    off

  # Postural tone as in the kick, the inside kick's leg gains, and the
  # stance leg's gain and drives.
  -> after(frame, ctl)
    return super(frame, ctl) if !v3_phase? && !sb_ap_phase?
    @tone = clamp(@tone + @k_tone * (@pitch - @pitch_des) * ctl.dt, ~0.0, ~1.0)
    tone = @tone
    @extensors.each ->(i) ctl.add_drive(i, tone)
    if @phase == :in_swing
      gk = @in_g_kick
      @leg_r.each ->(i) ctl.set_gain(i, gk)
      ga = @in_g_ank
      @ankle_r.each ->(i) ctl.set_gain(i, ga)
      gr = @in_g_rot
      @hip_rot_r.each ->(i) ctl.set_gain(i, gr)
    st = b_stance_side
    return self if st == "" || foot_load(other_side(st)) >= @sb_ds_load
    legs = @leg_l
    sup = @support_l
    abd = @abd_l
    ank = @ank_l
    if st == "r"
      legs = @leg_r
      sup = @support_r
      abd = @abd_r
      ank = @ank_r
    g = @sb_g
    legs.each ->(i) ctl.set_gain(i, g)
    d1 = @sb_drv
    sup.each ->(i) ctl.add_drive(i, d1)
    d2 = @sb_drv_abd
    abd.each ->(i) ctl.add_drive(i, d2)
    d3 = @sb_cc
    ank.each ->(i) ctl.add_drive(i, d3)
    rot = @rot_l
    rot = @rot_r if st == "r"
    d4 = @sb_rot_cc
    rot.each ->(i) ctl.add_drive(i, d4) if d4 > ~0.0
    self
