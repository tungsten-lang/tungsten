# MyoSoccer: a penalty kick on the MyoChallenge 2025 soccer body (myoLeg +
# myoTorso: 290 muscles, 80 in the legs, 210 in the lumbar spine and
# abdominal wall), written as robolab contraction chunks.
#
# One Track drives all 290 muscles. Chunks (whole-body equilibrium postures,
# eased min-jerk in contraction space) and the latches that end them:
#
#   set     settle into the stance: pelvis tipped back, lumbar flexed, back
#           extensor tone on                          -- after t_set
#   shift   lean: the ankle strategy's COM target moves forward (shift_x)
#           and over the right foot                   -- LATCH left foot
#           unloaded, or the COM d_go ahead of the feet (a caught fall)
#   lift    left knee and hip fold (toe clearance)    -- LATCH left heel
#           clear of the ground (lift_h)
#   reach   the left leg swings to the plant spot beside the ball; a live
#           two-link IK correction steers the ankle onto the spot from the
#           measured hip position and pelvis pitch/roll -- LATCH left foot
#           loaded at least min_step ahead of where it started
#   swing   (direct kick) the right hip drives the thigh through with a
#           hip-flexor burst, knee folded; antagonists silenced (reciprocal
#           inhibition), kicking-leg reflexes loose     -- LATCH right hip
#           flexion past hip_snap
#   snap    knee-extensor burst on top: the shank whips open through the
#           ball                                      -- LATCH ball touch
#   follow  hip-extensor brake on the kicking leg      -- after t_follow
#   land    the kicking foot comes down ahead          -- LATCH right foot
#           contact
#   recover both feet down, sinking into a low crouch (the pelvis only has
#           to stay above 0.2 m until the ball arrives)
#
# Leg postures are written as foot targets (ankle relative to hip, metres)
# turned into joint angles by two-link IK at a nominal pelvis tilt. Spring-
# eased corrections every tick (balance): lumbar servo on thorax pitch and a
# hip strategy on the stance hip(s); ankle strategy on the COM's fore-aft
# error; hip ab/adduction and subtalar on its lateral error plus a pelvis-
# roll servo on the stance hip (the gluteus medius against Trendelenburg);
# the swing thigh held in world frame; the IK placement in reach; and in
# swing/snap the aim: the kicking hip's adduction and rotation steer the
# foot's lateral path relative to the ball. Aim: the keeper's observed y
# picks the near-post (right) or far-post (left) variant of the kick, the one
# whose crossing point is farther from the keeper (switch at aim_split),
# re-evaluated every tick until the swing commits.
#
# The trunk. At the model's upright neutral posture the rectus abdominis sits
# at the long end of its length range and its passive force alone flexes the
# lumbar spine with ~207 N m, more than all 156 back extensors can return at
# full activation (~196 N m, measured on the model). No reflex holds that
# posture. The stance therefore tilts the pelvis back (hip extension) and
# flexes the lumbar spine (which slackens the abdominals), keeping the thorax
# near vertical, and gives the extensors a tonic drive (feed-forward
# activation) that an integrator on thorax pitch can trim: postural tone.
#
# Reflex gains are per muscle, proportional to the muscle's length range, so
# the stretch reflex answers to length error in metres: the spine's many
# short muscles (ranges of 1-5 cm) would otherwise saturate on millimetre
# errors.
#
# Every number is a tunable (`param`), practised with CMA-ES in stages
# (stance, one-leg stance, step, kick power, recovery, far-post aim) on full
# official-environment rollouts; params/myo_soccer.txt holds the result.
# The earlier lunge-then-plant variant (lunge, plant chunks) is kept behind
# the `direct` setting (0).
#
# Phase 2 (random start, joint noise, moving keeper). All opt-in, so the
# phase-1 params reproduce exactly:
#   approach   quasi-static steps (branching on the measured feet: either
#              foot, clipped steps, min-jerk weight shift, IK placement with
#              pelvis-yaw compensation, apex / abort latches, own trunk and
#              balance gains) until both feet are on the practised stance
#              spots, then the kick
#   kv2        the plant step as an approach step aimed beside the ball, then
#              the lunge / wind-back / kick (direct 0) or the swing (direct 1)
#   kf_ref     postures anchored to the model's key frame (phase-2 resets
#              are noisy; the bridge's reference posture is that reset)
#   hq         single-support stance hip as a decoupled torque servo on the
#              pelvis (MyoSoccerHip)
#   ff_trunk   internal-model feed-forward on the trunk muscles
#   side       side-foot variant of the swing (hip turned out, ankle locked
#              in dorsiflexion, pelvis-yaw servo)
# None of these reached a phase-2 goal yet (0 / 100): see README.md.

# Joint couplings of the model (MuJoCo joint equality constraints): a
# follower joint is a quartic polynomial of its leader. Postures are written
# on the leaders; the followers are filled in so the multi-joint Geometry
# sees a consistent pose (the knee's translations and patella, the lumbar
# vertebrae).
+ MyoSoccerCoupling
  -> .table
    [
      ["flex_extension", "Abs_r3", [~0.0, ~0.6429, ~0.0, ~0.0, ~0.0]],
      ["flex_extension", "L4_L5_FE", [~0.0, ~0.185, ~0.0, ~0.0, ~0.0]],
      ["flex_extension", "L3_L4_FE", [~0.0, ~0.204, ~0.0, ~0.0, ~0.0]],
      ["flex_extension", "L2_L3_FE", [~0.0, ~0.231, ~0.0, ~0.0, ~0.0]],
      ["flex_extension", "L1_L2_FE", [~0.0, ~0.255, ~0.0, ~0.0, ~0.0]],
      ["axial_rotation", "L4_L5_AR", [~0.0, ~0.0378, ~0.0, ~0.0, ~0.0]],
      ["axial_rotation", "L3_L4_AR", [~0.0, ~0.0378, ~0.0, ~0.0, ~0.0]],
      ["axial_rotation", "L2_L3_AR", [~0.0, ~0.0311, ~0.0, ~0.0, ~0.0]],
      ["axial_rotation", "L1_L2_AR", [~0.0, ~0.0289, ~0.0, ~0.0, ~0.0]],
      ["lat_bending", "L4_L5_LB", [~0.0, ~0.1811, ~0.0, ~0.0, ~0.0]],
      ["lat_bending", "L3_L4_LB", [~0.0, ~0.2453, ~0.0, ~0.0, ~0.0]],
      ["lat_bending", "L2_L3_LB", [~0.0, ~0.2501, ~0.0, ~0.0, ~0.0]],
      ["lat_bending", "L1_L2_LB", [~0.0, ~0.188, ~0.0, ~0.0, ~0.0]],
      ["knee_angle_r", "knee_angle_r_translation2", [~0.0, ~0.00588, ~-0.001256, ~-0.000003, ~0.000001]],
      ["knee_angle_r", "knee_angle_r_translation1", [~0.0, ~0.003129, ~-0.002308, ~0.000562, ~0.000001]],
      ["knee_angle_r", "knee_angle_r_rotation2", [~0.0, ~0.0791, ~-0.0328, ~-0.0252, ~0.0108]],
      ["knee_angle_r", "knee_angle_r_rotation3", [~0.0, ~0.3695, ~-0.1695, ~0.0252, ~0.0]],
      ["knee_angle_r", "knee_angle_r_beta_translation2", [~-0.0108, ~-0.0488, ~0.0093, ~0.0132, ~-0.0035]],
      ["knee_angle_r", "knee_angle_r_beta_translation1", [~0.0524, ~-0.015, ~-0.0341, ~0.0133, ~-0.0009]],
      ["knee_angle_r", "knee_angle_r_beta_rotation1", [~0.0105, ~0.0248, ~-1.3165, ~0.7163, ~-0.1383]],
      ["knee_angle_l", "knee_angle_l_translation2", [~0.0, ~-0.00588, ~0.001256, ~0.000003, ~-0.000001]],
      ["knee_angle_l", "knee_angle_l_translation1", [~0.0, ~0.003129, ~-0.002308, ~0.000562, ~0.000001]],
      ["knee_angle_l", "knee_angle_l_rotation2", [~0.0, ~0.0791, ~-0.0328, ~-0.0252, ~0.0108]],
      ["knee_angle_l", "knee_angle_l_rotation3", [~0.0, ~-0.3695, ~0.1695, ~-0.0252, ~0.0]],
      ["knee_angle_l", "knee_angle_l_beta_translation2", [~-0.0108, ~-0.0488, ~0.0093, ~0.0132, ~-0.0035]],
      ["knee_angle_l", "knee_angle_l_beta_translation1", [~0.0524, ~-0.015, ~-0.0341, ~0.0133, ~-0.0009]],
      ["knee_angle_l", "knee_angle_l_beta_rotation1", [~0.0105, ~0.0248, ~-1.3165, ~0.7163, ~-0.1383]]
    ]

  -> .poly(c, q)
    c[0] + q * (c[1] + q * (c[2] + q * (c[3] + q * c[4])))

  # d(follower)/d(leader) at q.
  -> .dpoly(c, q)
    c[1] + q * (~2.0 * c[2] + q * (~3.0 * c[3] + q * ~4.0 * c[4]))

# The model's key frame (key_qpos[0], the phase-1 reset) for the leader joints
# the stance never sets explicitly; every other joint is 0 there. Phase 2
# resets add +-0.02 rad of noise to every joint, and the bridge's reference
# posture is that noisy reset, so postures built on it would carry the noise
# as a permanent target offset (kf_ref = 1 anchors them to the key frame).
+ MyoSoccerKeyframe
  -> .table
    {"hip_flexion_r" => ~0.161153, "hip_adduction_r" => ~-0.0279385, "hip_rotation_r" => ~-0.041886,
     "knee_angle_r" => ~0.461137, "ankle_angle_r" => ~0.334, "subtalar_angle_r" => ~-0.00117055,
     "mtp_angle_r" => ~-0.000125295, "hip_flexion_l" => ~0.161153, "hip_adduction_l" => ~-0.0279385,
     "hip_rotation_l" => ~-0.041886, "knee_angle_l" => ~0.461137, "ankle_angle_l" => ~0.334,
     "subtalar_angle_l" => ~-0.00117055, "mtp_angle_l" => ~-0.000125295}

  -> .value(name)
    t = MyoSoccerKeyframe.table
    return t[name] if t.key?(name)
    ~0.0

# A whole-body posture: every joint the muscles cross, starting from the
# model's reference (the key-frame stance); leaders are set by name and the
# coupled followers derived. `pose` turns it into a Pose (every joint set, so
# no muscle falls back to a reference angle for a joint it crosses).
+ MyoSoccerPosture
  -> new(@geometry, kf = false)
    @q = {}
    g = @geometry
    g.joint_names.each ->(name) @q[name] = g.qref(g.joint(name))
    g.joint_names.each ->(name) @q[name] = MyoSoccerKeyframe.value(name) if kf
    @kf = kf
    @stiff = {}

  -> set(joint, value)
    @q[joint] = value if @q.key?(joint)
    self

  -> get(joint)
    @q[joint]

  -> copy
    out = MyoSoccerPosture.new(@geometry, @kf)
    @q.keys.each ->(k) out.set(k, @q[k])
    out

  # Stiffness (co-contraction) of the joints whose name starts with prefix.
  -> stiffen(prefix, s)
    @stiff[prefix] = s
    self

  -> couple
    MyoSoccerCoupling.table.each ->(row)
      @q[row[1]] = MyoSoccerCoupling.poly(row[2], @q[row[0]]) if @q.key?(row[0]) && @q.key?(row[1])
    self

  -> stiffness_of(name)
    s = ~0.0
    @stiff.keys.each ->(prefix)
      s = @stiff[prefix] if name.starts_with?(prefix) && @stiff[prefix] > s
    s

  -> pose
    couple
    p = Pose.new
    @geometry.joint_names.each ->(name) p.set(name, @q[name], stiffness_of(name))
    p

# Two-link leg inverse kinematics in the sagittal plane (thigh 0.403 m,
# shank 0.400 m hip-to-ankle, measured on the model): the ankle dx ahead of
# the hip and dz below it -> [thigh world angle (knee ahead of the hip +),
# knee flexion].
+ MyoSoccerLeg
  -> .ik(dx, dz)
    l1 = ~0.403
    l2 = ~0.400
    d = Math.sqrt(dx * dx + dz * dz)
    d = ~0.25 if d < ~0.25
    d = ~0.795 if d > ~0.795
    ck = (l1 * l1 + l2 * l2 - d * d) / (~2.0 * l1 * l2)
    knee = ~3.141592653589793 - Math.acos(ck)
    cg = (l1 * l1 + d * d - l2 * l2) / (~2.0 * l1 * d)
    cg = ~1.0 if cg > ~1.0
    [Math.atan2(dx, dz) + Math.acos(cg), knee]

# Decoupled hip torque map (the idea of MyoWalkHip in myo_walk.w, credit to
# the locomotion work), built from this body's geometry and the skill's own
# per-muscle reflex gains. A joint offset dq on the three hip joints changes
# muscle i's contraction command by sl_i . dq (sl = contraction slopes), its
# activation by kp_i sl_i . dq and so the hip torque by
#
#   tau = K dq,   K = sum_i F_i L_i kp_i sl_i sl_i^T
#
# (F peak force, L length range: the moment arm is sl L). dq = K^-1 tau then
# produces the torque (flexion, adduction, rotation) and nothing else, where
# plain joint offsets leak between the axes (a roll servo also yaws).
+ MyoSoccerHip
  -> new(geom, side, kp)
    @joints = [geom.joint("hip_flexion_" + side), geom.joint("hip_adduction_" + side), geom.joint("hip_rotation_" + side)]
    k = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    seen = {}
    @joints.each ->(j)
      geom.crossing(j).each ->(m)
        if !seen.key?(m)
          seen[m] = true
          sl = @joints.map ->(jj) geom.contraction_slope(m, jj)
          rg = geom.range(m)
          w = geom.force(m) * (rg[1] - rg[0]) * kp[m]
          a = 0
          while a < 3
            b = 0
            while b < 3
              k[a * 3 + b] = k[a * 3 + b] + w * sl[a] * sl[b]
              b += 1
            a += 1
    @kinv = MyoSoccerHip.invert3(k)

  -> .invert3(k)
    a = k[0]
    b = k[1]
    c = k[2]
    d = k[3]
    e = k[4]
    f = k[5]
    g = k[6]
    h = k[7]
    i = k[8]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    inv = ~1.0 / det
    [(e * i - f * h) * inv, (c * h - b * i) * inv, (b * f - c * e) * inv,
     (f * g - d * i) * inv, (a * i - c * g) * inv, (c * d - a * f) * inv,
     (d * h - e * g) * inv, (b * g - a * h) * inv, (a * e - b * d) * inv]

  # The joint offsets (flexion, adduction, rotation) giving hip torques
  # (tf, ta, tr) in N m.
  -> offsets(tf, ta, tr)
    ki = @kinv
    [ki[0] * tf + ki[1] * ta + ki[2] * tr, ki[3] * tf + ki[4] * ta + ki[5] * tr, ki[6] * tf + ki[7] * ta + ki[8] * tr]

+ MyoSoccerSkill < Skill
  -> start(frame, ctl)
    read_params
    @n = body.size
    @g = body.geometry
    classify
    set_gains(ctl)
    # opt-in internal-model feed-forward (gravity + Coriolis torque split over
    # the trunk muscles): the torso hangs on the lumbar joints, so their bias
    # torque is the one the trunk muscles must supply
    if @ff_trunk > ~0.0
      trunk = []
      i = 0
      while i < @n
        trunk.push(i) if !@is_leg[i]
        i += 1
      ctl.enable_feedforward(trunk, @ff_trunk)
    @tone = @tone0
    @support = :both
    @lat_to = :mid
    @phase = :set
    @t_phase = ~0.0
    @pitch = ~0.0
    @tilt = @tilt0
    @roll = ~0.0
    @proll = ~0.0
    @cl_f = ~0.5
    @cr_f = ~0.5
    @aim = choose_aim(frame)
    @heel0 = frame.at("l_foot_pos", 0)
    @plant_x = frame.at("env_ball_pos", 0) + @plant_dx
    @plant_y = frame.at("env_ball_pos", 1) + @plant_dy
    # the practised stance's foot centres relative to the ball (phase 1's
    # key-frame start): where the approach brings the feet
    bx = frame.at("env_ball_pos", 0)
    by = frame.at("env_ball_pos", 1)
    @goal_l = [bx - ~1.077 + @ap_goal_dx, by + ~0.0895]
    @goal_r = [bx - ~1.0775 + @ap_goal_dx, by - ~0.0925]
    @step_side = "l"
    @step_to = [~0.0, ~0.0]
    @last_side = ""
    @yaw = ~0.0
    @steps = 0
    @ap_postures = {}
    @ap_lift_postures = {}
    l = foot_center(frame, "l")
    r = foot_center(frame, "r")
    el = Math.sqrt((@goal_l[0] - l[0]) * (@goal_l[0] - l[0]) + (@goal_l[1] - l[1]) * (@goal_l[1] - l[1]))
    er = Math.sqrt((@goal_r[0] - r[0]) * (@goal_r[0] - r[0]) + (@goal_r[1] - r[1]) * (@goal_r[1] - r[1]))
    @start_err = el
    @start_err = er if er > el
    @hips = {}
    if @hq > ~0.5
      @hips["l"] = MyoSoccerHip.new(@g, "l", @kp_arr)
      @hips["r"] = MyoSoccerHip.new(@g, "r", @kp_arr)
    @cur_post = stance
    ctl.add_track(Track.new("body", movement, body.all))

  -> read_params
    @stage = ~2.0
    @stage = @params["stage"] if @params.key?("stage")
    # stance (the midpoint posture, practised in quiet standing)
    @fe = param("fe", ~-0.49, ~-0.8, ~0.0)
    @hip = param("hip", ~-0.4, ~-0.5, ~0.4)
    @knee = param("knee", ~0.41, ~0.1, ~1.0)
    @ankle = param("ankle", ~0.34, ~0.0, ~0.5)
    @stiff_t = param("stiff_t", ~0.0, ~0.0, ~0.2)
    @stiff_l = param("stiff_l", ~0.02, ~0.0, ~0.2)
    # the pelvis pitch (forward +) the stance settles at: leg postures below
    # give thigh angles in the world frame, hip flexion = thigh - tilt0
    @tilt0 = param("tilt0", ~-0.45, ~-0.8, ~-0.1)
    # reflexes: kp per metre of length error
    @k_trunk = param("k_trunk", ~46.0, ~5.0, ~120.0)
    @k_leg = param("k_leg", ~74.0, ~30.0, ~400.0)
    @kd_ratio = param("kd_ratio", ~0.02, ~0.0, ~0.1)
    @g_psoas = param("g_psoas", ~1.0, ~0.0, ~1.5)
    @kd_leg = param("kd_leg", ~0.02, ~0.0, ~0.3)
    @ki_leg = param("ki_leg", ~0.0, ~0.0, ~20.0)
    @ki_lim = param("ki_lim", ~0.3, ~0.0, ~0.6)
    @ff_trunk = param("ff_trunk", ~0.0, ~0.0, ~1.5)
    # hq (1): in single support the stance hip is a torque servo on the
    # pelvis (MyoSoccerHip): its posture pull released by hq_rel (target =
    # measured angle + hq_lead x velocity), then PD torques (N m per rad) on
    # pelvis tilt (to hq_tilt), roll (level) and yaw (to 0), replacing the
    # joint-offset hip strategies on that hip
    @hq = ~0.0
    @hq = @params["hq"] if @params.key?("hq")
    @hq_rel = param("hq_rel", ~0.8, ~0.0, ~1.0)
    @hq_lead = param("hq_lead", ~0.03, ~0.0, ~0.2)
    @hq_tilt = param("hq_tilt", ~-0.3, ~-0.6, ~0.2)
    @hq_tkp = param("hq_tkp", ~300.0, ~0.0, ~1000.0)
    @hq_tkd = param("hq_tkd", ~20.0, ~0.0, ~150.0)
    @hq_rkp = param("hq_rkp", ~400.0, ~0.0, ~1200.0)
    @hq_rkd = param("hq_rkd", ~60.0, ~0.0, ~300.0)
    @hq_ykp = param("hq_ykp", ~40.0, ~0.0, ~200.0)
    @hq_ykd = param("hq_ykd", ~5.0, ~0.0, ~60.0)
    @kf_ref = ~0.0
    @kf_ref = @params["kf_ref"] if @params.key?("kf_ref")
    # postural tone of the back extensors, trimmed by thorax pitch
    @tone0 = param("tone0", ~0.51, ~0.0, ~1.0)
    @k_tone = param("k_tone", ~0.73, ~0.0, ~5.0)
    @pitch_des = param("pitch_des", ~0.25, ~-0.3, ~0.5)
    # trunk servo on the lumbar spine; hip strategy on the stance hip(s)
    @k_th = param("k_th", ~1.5, ~0.3, ~4.0)
    @k_thd = param("k_thd", ~0.31, ~0.0, ~0.8)
    @k_hp = param("k_hp", ~0.5, ~0.0, ~3.0)
    @k_hpd = param("k_hpd", ~0.1, ~0.0, ~0.8)
    # swing thigh held in the world frame against pelvis pitch
    @k_comp = param("k_comp", ~0.5, ~0.0, ~1.2)
    # ankle strategy (sagittal) and hip strategy (frontal)
    @k_ax = param("k_ax", ~3.6, ~0.0, ~8.0)
    @k_axv = param("k_axv", ~0.5, ~0.0, ~2.0)
    @x_des = param("x_des", ~0.045, ~-0.05, ~0.15)
    @k_ay = param("k_ay", ~3.1, ~0.0, ~8.0)
    @k_ayv = param("k_ayv", ~0.29, ~0.0, ~2.0)
    @k_ay1 = param("k_ay1", ~1.0, ~-4.0, ~4.0)
    @k_st1 = param("k_st1", ~0.0, ~-4.0, ~4.0)
    # frontal-plane trunk servo: thorax roll on the stance hip(s) and the
    # lumbar lateral bend
    @k_roll = param("k_roll", ~0.0, ~-3.0, ~3.0)
    @k_rolld = param("k_rolld", ~0.0, ~-0.6, ~0.6)
    @k_lb = param("k_lb", ~0.0, ~-3.0, ~3.0)
    @k_pr = param("k_pr", ~1.5, ~0.0, ~4.0)
    @k_prd = param("k_prd", ~0.1, ~0.0, ~0.6)
    @spring = param("spring", ~0.03, ~0.005, ~0.15)
    # weight shift onto the right foot and forward lean
    @t_set = param("t_set", ~0.3, ~0.05, ~1.0)
    @t_shift = param("t_shift", ~0.3, ~0.1, ~0.8)
    @shift_y = param("shift_y", ~0.0, ~-0.08, ~0.08)
    @shift_x = param("shift_x", ~0.08, ~-0.05, ~0.2)
    @unload = param("unload", ~0.15, ~0.0, ~0.6)
    @shift_add = param("shift_add", ~0.05, ~-0.2, ~0.2)
    @d_go = param("d_go", ~0.0, ~0.0, ~0.3)
    @shift_st = param("shift_st", ~0.0, ~-0.3, ~0.3)
    @k_st2 = param("k_st2", ~0.0, ~-3.0, ~3.0)
    # step: lift and reach with the left leg, push with the right
    @k_ax_st = param("k_ax_st", ~3.0, ~0.0, ~6.0)
    @x_step = param("x_step", ~0.05, ~-0.05, ~0.4)
    @t_lift = param("t_lift", ~0.15, ~0.05, ~0.4)
    @th_lift = param("th_lift", ~0.7, ~-0.2, ~1.2)
    @knee_lift = param("knee_lift", ~1.2, ~0.2, ~1.8)
    @lift_h = param("lift_h", ~0.08, ~0.03, ~0.2)
    # foot targets (ankle relative to hip, metres) for the step and lunge
    @lift_dx = param("lift_dx", ~0.1, ~-0.2, ~0.4)
    @lift_dz = param("lift_dz", ~0.6, ~0.4, ~0.78)
    @lift_pitch = param("lift_pitch", ~0.2, ~-0.4, ~0.5)
    @reach_dx = param("reach_dx", ~0.32, ~0.0, ~0.6)
    @reach_dz = param("reach_dz", ~0.77, ~0.55, ~0.8)
    @reach_pitch = param("reach_pitch", ~0.05, ~-0.4, ~0.5)
    @push_dx = param("push_dx", ~-0.12, ~-0.4, ~0.1)
    @push_dz = param("push_dz", ~0.76, ~0.55, ~0.8)
    @push_pitch = param("push_pitch", ~0.0, ~-0.6, ~0.3)
    @k_ik = param("k_ik", ~0.7, ~0.0, ~1.0)
    @reach_lat = param("reach_lat", ~0.3, ~0.0, ~1.0)
    @tilt_step = param("tilt_step", ~-0.3, ~-0.6, ~0.1)
    @fe_step = param("fe_step", ~-0.35, ~-0.8, ~0.0)
    @lg_dx = param("lg_dx", ~0.18, ~-0.1, ~0.5)
    @lg_dz = param("lg_dz", ~0.74, ~0.55, ~0.8)
    @lg_pitch = param("lg_pitch", ~0.0, ~-0.4, ~0.4)
    @lr_dx = param("lr_dx", ~-0.38, ~-0.6, ~0.0)
    @lr_dz = param("lr_dz", ~0.68, ~0.5, ~0.8)
    @lr_pitch = param("lr_pitch", ~-0.5, ~-0.9, ~0.2)
    @ks_dx = param("ks_dx", ~0.02, ~-0.2, ~0.3)
    @ks_dz = param("ks_dz", ~0.75, ~0.55, ~0.8)
    @ks_pitch = param("ks_pitch", ~0.0, ~-0.4, ~0.4)
    @ankle_lift = param("ankle_lift", ~0.2, ~-0.4, ~0.5)
    @t_reach = param("t_reach", ~0.2, ~0.05, ~0.5)
    @th_reach = param("th_reach", ~0.55, ~-0.2, ~1.2)
    @knee_reach = param("knee_reach", ~0.2, ~0.0, ~1.2)
    @ankle_reach = param("ankle_reach", ~0.1, ~-0.4, ~0.5)
    @add_reach = param("add_reach", ~-0.15, ~-0.5, ~0.3)
    @th_push = param("th_push", ~0.05, ~-0.8, ~0.3)
    @knee_push = param("knee_push", ~0.45, ~0.0, ~1.2)
    @ankle_push = param("ankle_push", ~0.3, ~-0.6, ~0.5)
    @drv_push = param("drv_push", ~0.0, ~0.0, ~1.0)
    @min_step = param("min_step", ~0.35, ~0.1, ~0.8)
    @direct = ~0.0
    @direct = @params["direct"] if @params.key?("direct")
    @plant_load = param("plant_load", ~0.1, ~0.02, ~0.6)
    @lean_step = param("lean_step", ~0.0, ~-0.3, ~0.5)
    # plant: left leg loads, right leg winds back
    @t_plant = param("t_plant", ~0.2, ~0.05, ~0.6)
    # plant spot (left ankle) relative to the ball, and the swing placement
    # correction that steers the ankle onto it
    @plant_dx = param("plant_dx", ~-0.42, ~-0.8, ~-0.2)
    @plant_dy = param("plant_dy", ~0.14, ~0.0, ~0.35)
    @k_py = param("k_py", ~0.7, ~0.0, ~1.0)
    # lunge: double support, COM target relative to the left foot centre
    @t_lunge = param("t_lunge", ~0.6, ~0.1, ~1.2)
    @t_lunge_max = param("t_lunge_max", ~1.0, ~0.05, ~1.5)
    @x_lunge = param("x_lunge", ~0.0, ~-0.2, ~0.15)
    @y_lunge = param("y_lunge", ~-0.02, ~-0.1, ~0.1)
    @unload_r = param("unload_r", ~0.1, ~0.0, ~0.5)
    @th_rb = param("th_rb", ~-0.35, ~-0.8, ~0.2)
    @knee_rb = param("knee_rb", ~0.3, ~0.0, ~1.2)
    @ankle_rb = param("ankle_rb", ~0.1, ~-0.5, ~0.5)
    @x_plant = param("x_plant", ~0.05, ~-0.2, ~0.3)
    @th_pl = param("th_pl", ~0.05, ~-0.5, ~0.8)
    @knee_pl = param("knee_pl", ~0.4, ~0.0, ~1.2)
    @ankle_pl = param("ankle_pl", ~0.2, ~-0.4, ~0.5)
    @add_pl = param("add_pl", ~-0.1, ~-0.5, ~0.3)
    @th_back = param("th_back", ~-0.15, ~-0.6, ~0.4)
    @knee_back = param("knee_back", ~1.6, ~0.4, ~2.1)
    @ankle_back = param("ankle_back", ~-0.4, ~-0.7, ~0.4)
    # kick: hip leads (swing), knee snaps (snap); aim on the kicking hip
    @t_swing = param("t_swing", ~0.12, ~0.03, ~0.3)
    @hip_snap = param("hip_snap", ~0.3, ~-0.4, ~1.2)
    @th_k1 = param("th_k1", ~0.4, ~-0.2, ~1.4)
    @knee_k1 = param("knee_k1", ~1.3, ~0.6, ~1.8)
    @t_snap = param("t_snap", ~0.1, ~0.03, ~0.3)
    @th_k2 = param("th_k2", ~0.6, ~-0.2, ~1.6)
    @knee_k2 = param("knee_k2", ~0.1, ~0.0, ~1.2)
    @ankle_k = param("ankle_k", ~-0.5, ~-0.7, ~0.4)
    @drv_hip = param("drv_hip", ~0.7, ~0.0, ~1.0)
    @drv_knee = param("drv_knee", ~0.7, ~0.0, ~1.0)
    @g_kick = param("g_kick", ~0.4, ~0.0, ~1.5)
    @g_anta = param("g_anta", ~0.0, ~0.0, ~1.0)
    @g_st = param("g_st", ~1.0, ~0.5, ~3.0)
    @drv_st = param("drv_st", ~0.0, ~0.0, ~0.6)
    @drv_post = param("drv_post", ~0.0, ~0.0, ~0.8)
    @aim_add = param("aim_add", ~0.1, ~-0.5, ~0.5)
    @aim_rot = param("aim_rot", ~0.0, ~-0.6, ~0.6)
    @add_k = param("add_k", ~0.0, ~-0.4, ~0.4)
    @rot_k = param("rot_k", ~0.0, ~-0.6, ~0.6)
    @corner = param("corner", ~2.2, ~0.5, ~3.2)
    @kick_dy = param("kick_dy", ~0.0, ~-0.15, ~0.15)
    @aim_dy = param("aim_dy", ~-0.04, ~-0.12, ~0.12)
    @k_ky = param("k_ky", ~2.0, ~0.0, ~6.0)
    @left_dy = param("left_dy", ~0.0, ~-0.2, ~0.2)
    @left_add = param("left_add", ~0.0, ~-0.5, ~0.5)
    @left_rot = param("left_rot", ~0.0, ~-0.6, ~0.6)
    @left_pdy = param("left_pdy", ~0.0, ~-0.15, ~0.15)
    # side-foot (inside of the foot) strike, `side` 1: the kicking hip turned
    # out (external rotation s_rot; the model's range ends at -0.7 rad, more
    # turn-out comes from the pelvis opening over the plant hip, s_open), the
    # ankle locked in dorsiflexion (s_ankle, stiffened by s_stiff and a
    # co-contraction drive s_drv_ank), the knee only slightly flexed at
    # contact (s_knee2); the swing comes from the hip (flexor burst drv_hip,
    # adductor burst s_drv_add), the plant foot turned toward the target
    # before it lands (s_plant_rot)
    @side = ~0.0
    @side = @params["side"] if @params.key?("side")
    @s_rot = param("s_rot", ~-0.6, ~-0.7, ~-0.3)
    @s_open = param("s_open", ~-0.3, ~-0.7, ~0.0)
    @s_ankle = param("s_ankle", ~0.25, ~-0.2, ~0.52)
    @s_stiff = param("s_stiff", ~0.1, ~0.0, ~0.4)
    @s_drv_ank = param("s_drv_ank", ~0.2, ~0.0, ~0.8)
    @s_knee1 = param("s_knee1", ~0.8, ~0.1, ~1.6)
    @s_knee2 = param("s_knee2", ~0.3, ~0.0, ~1.2)
    @s_drv_add = param("s_drv_add", ~0.0, ~0.0, ~1.0)
    @s_drv_knee = param("s_drv_knee", ~0.2, ~0.0, ~1.0)
    @s_plant_rot = param("s_plant_rot", ~0.0, ~-0.6, ~0.6)
    @s_add = param("s_add", ~0.1, ~-0.1, ~0.5)
    @s_dy = param("s_dy", ~0.0, ~-0.2, ~0.2)
    @s_aim_add = param("s_aim_add", ~0.1, ~-0.5, ~0.5)
    @s_aim_rot = param("s_aim_rot", ~0.0, ~-0.15, ~0.15)
    @s_aim_dy = param("s_aim_dy", ~0.0, ~-0.12, ~0.12)
    @s_t_cock = param("s_t_cock", ~0.12, ~0.0, ~0.4)
    # joint servo (rad of offset per rad of error) holding the kicking
    # ankle's dorsiflexion and the hip's turn-out through cock/swing/snap
    # against the swing's inertia and the push-off's plantarflexion
    @s_servo = param("s_servo", ~1.0, ~0.0, ~4.0)
    # reflex gain of the kicking ankle's muscles in cock/swing/snap (the rest
    # of the kicking leg is loose, g_kick): a locked ankle
    @s_g_ank = param("s_g_ank", ~1.5, ~0.0, ~4.0)
    @s_g_rot = param("s_g_rot", ~1.5, ~0.0, ~4.0)
    # pelvis yaw servo on the plant hip (the pelvis stays open, yaw at
    # s_yaw_des, so the turned-out kicking foot's medial side faces the ball)
    @s_kyaw = param("s_kyaw", ~1.0, ~0.0, ~4.0)
    @s_yaw_des = param("s_yaw_des", ~-0.2, ~-1.0, ~0.4)
    # ... and through the run-up (set, shift, lift, reach) on the stance hip(s)
    @s_kyaw_run = param("s_kyaw_run", ~1.0, ~0.0, ~4.0)
    @s_yaw_run = param("s_yaw_run", ~-0.2, ~-1.0, ~0.4)
    @s_th_cock = param("s_th_cock", ~-0.3, ~-0.8, ~0.4)
    @s_knee_cock = param("s_knee_cock", ~1.0, ~0.2, ~1.8)
    # keeper y at which the kick switches from the near-post (right, -y)
    # variant to the far-post (left, +y) one: the midpoint of the two
    # variants' crossing points, so the ball goes to whichever is farther
    # from the keeper
    @aim_split = param("aim_split", ~0.0, ~-3.3, ~3.3)
    # approach (phase 2 starts): quasi-static steps, either foot, until both
    # feet stand on the practised stance spots behind the ball
    @approach = ~1.0
    @approach = @params["approach"] if @params.key?("approach")
    @ap_tol = param("ap_tol", ~0.06, ~0.02, ~0.15)
    @ap_max_x = param("ap_max_x", ~0.3, ~0.1, ~0.5)
    @ap_max_y = param("ap_max_y", ~0.2, ~0.05, ~0.4)
    @ap_min_sep = param("ap_min_sep", ~0.14, ~0.08, ~0.3)
    @ap_max_split = param("ap_max_split", ~0.35, ~0.15, ~0.6)
    @ap_t_hold = param("ap_t_hold", ~0.3, ~0.05, ~1.0)
    @ap_t_shift = param("ap_t_shift", ~0.35, ~0.1, ~0.8)
    @ap_unload = param("ap_unload", ~0.15, ~0.0, ~0.5)
    @ap_apex = ~0.0
    @ap_apex = @params["ap_apex"] if @params.key?("ap_apex")
    @ap_vapex = param("ap_vapex", ~0.02, ~-0.1, ~0.15)
    @ap_apex_load = param("ap_apex_load", ~0.35, ~0.05, ~0.7)
    @ap_apex_tol = param("ap_apex_tol", ~0.03, ~0.005, ~0.1)
    # a swing whose COM drifts ap_abort outward of the stance foot (away from
    # the swing foot) is put down at once; ap_reach_max caps the swing
    @ap_abort = param("ap_abort", ~0.05, ~0.0, ~0.15)
    @ap_reach_max = param("ap_reach_max", ~0.8, ~0.2, ~1.2)
    @ap_t_ease = param("ap_t_ease", ~0.25, ~0.1, ~1.0)
    # capture-point placement: the swing foot lands offset by the COM's
    # velocity (seconds of travel), catching the sway it is falling into
    @ap_cp = param("ap_cp", ~0.0, ~0.0, ~0.5)
    # kv2 (1): the plant step is an approach-style step (eased weight shift
    # onto the right foot, lift, IK-placed reach to the plant spot kp_dx,
    # kp_dy from the ball, leaning kp_fwd / kp_lat of the way onto it), taken
    # when the approach is done, and the kick follows its landing; the
    # approach's stance spots move ap_goal_dx toward the ball
    @ap_yawc = param("ap_yawc", ~0.0, ~0.0, ~1.0)
    @ap_yawr = param("ap_yawr", ~0.0, ~0.0, ~1.0)
    @kv2 = ~0.0
    @kv2 = @params["kv2"] if @params.key?("kv2")
    @ap_goal_dx = param("ap_goal_dx", ~0.0, ~-0.1, ~0.6)
    @kp_dx = param("kp_dx", ~-0.3, ~-0.6, ~0.1)
    @kp_dy = param("kp_dy", ~0.05, ~-0.1, ~0.35)
    @kp_fwd = param("kp_fwd", ~0.5, ~0.0, ~1.2)
    @kp_x = param("kp_x", ~0.1, ~-0.05, ~0.3)
    @kp_shift_y = param("kp_shift_y", ~0.0, ~-0.1, ~0.1)
    @kp_lat = param("kp_lat", ~0.5, ~0.0, ~1.2)
    @plant_step = false
    @ap_cpx = param("ap_cpx", ~0.0, ~0.0, ~0.5)
    @ap_shift_y = param("ap_shift_y", ~-0.01, ~-0.12, ~0.1)
    @ap_x = param("ap_x", ~0.02, ~-0.1, ~0.15)
    @ap_t_lift = param("ap_t_lift", ~0.12, ~0.05, ~0.4)
    @ap_lift_h = param("ap_lift_h", ~0.05, ~0.02, ~0.15)
    @ap_lift_dx = param("ap_lift_dx", @lift_dx, ~-0.2, ~0.4)
    @ap_lift_dz = param("ap_lift_dz", @lift_dz, ~0.5, ~0.78)
    @ap_lift_pitch = param("ap_lift_pitch", ~0.15, ~-0.3, ~0.5)
    @ap_t_reach = param("ap_t_reach", ~0.25, ~0.05, ~0.6)
    @ap_reach_dz = param("ap_reach_dz", ~0.77, ~0.6, ~0.8)
    @ap_reach_pitch = param("ap_reach_pitch", ~0.0, ~-0.3, ~0.3)
    @ap_k_ik = param("ap_k_ik", ~0.8, ~0.0, ~1.0)
    @ap_k_py = param("ap_k_py", ~0.8, ~0.0, ~1.0)
    @ap_lat = param("ap_lat", ~0.3, ~0.0, ~1.0)
    @ap_load = param("ap_load", ~0.2, ~0.02, ~0.6)
    @ap_t_settle = param("ap_t_settle", ~0.25, ~0.05, ~0.8)
    @ap_drv_st = param("ap_drv_st", ~0.0, ~0.0, ~0.5)
    # the stance leg in single support: the stance posture plus offsets
    @ap_st_hip = param("ap_st_hip", ~0.0, ~-0.4, ~0.4)
    @ap_st_knee = param("ap_st_knee", ~0.0, ~-0.3, ~0.5)
    @ap_st_ankle = param("ap_st_ankle", ~0.0, ~-0.3, ~0.3)
    # the approach's own trunk and balance gains (the kick keeps its own)
    @ap_k_th = param("ap_k_th", @k_th, ~0.3, ~4.0)
    @ap_k_thd = param("ap_k_thd", @k_thd, ~0.0, ~0.8)
    @ap_pitch_des = param("ap_pitch_des", @pitch_des, ~-0.4, ~0.5)
    @ap_k_hp = param("ap_k_hp", @k_hp, ~0.0, ~3.0)
    @ap_k_hpd = param("ap_k_hpd", @k_hpd, ~0.0, ~0.8)
    @ap_k_pr = param("ap_k_pr", @k_pr, ~0.0, ~4.0)
    @ap_k_ay = param("ap_k_ay", @k_ay, ~0.0, ~8.0)
    @ap_k_st1 = param("ap_k_st1", @k_st1, ~-4.0, ~4.0)
    @ap_tilt = param("ap_tilt", @tilt0, ~-0.6, ~0.1)
    @ap_fe = param("ap_fe", @fe, ~-0.8, ~0.0)
    @ap_k_ay1 = param("ap_k_ay1", @k_ay1, ~-4.0, ~4.0)
    @ap_k_ayv = param("ap_k_ayv", @k_ayv, ~0.0, ~2.0)
    @ap_k_ax = param("ap_k_ax", @k_ax, ~0.0, ~8.0)
    @ap_k_axv = param("ap_k_axv", @k_axv, ~0.0, ~2.0)
    @ap_k_lb = param("ap_k_lb", @k_lb, ~-3.0, ~3.0)
    @ap_k_roll = param("ap_k_roll", @k_roll, ~-3.0, ~3.0)
    @ap_k_st2 = param("ap_k_st2", @k_st2, ~-3.0, ~3.0)
    # the COM target moves along a min-jerk path (a weight shift, not a
    # step change of the target); the balance offsets are clamped
    @ap_clamp = param("ap_clamp", ~0.3, ~0.05, ~0.8)
    @ap_fwd = param("ap_fwd", ~0.3, ~0.0, ~1.0)
    @ap_t_back = param("ap_t_back", ~0.3, ~0.05, ~0.8)
    # single support: the stance hip stops pulling toward its posture (the
    # target follows the measured angle, velocity-led) by ap_rel, so the
    # trunk servo terms act as a pure PD on the trunk (as in myo_walk)
    @ap_rel = param("ap_rel", ~0.0, ~0.0, ~1.0)
    # double support in the approach (hold, shift, settle): each leg's
    # posture re-solved by IK to where its foot actually is, from a pelvis
    # over the COM target at hip height ap_hz (ap_fit = blend, 0 = off)
    @ap_fit = param("ap_fit", ~0.0, ~0.0, ~1.0)
    @ap_hz = param("ap_hz", ~0.84, ~0.7, ~0.9)
    @ap_lead = param("ap_lead", ~0.05, ~0.0, ~0.3)
    @k_yaw = param("k_yaw", ~0.5, ~-2.0, ~2.0)
    @k_yawd = param("k_yawd", ~0.05, ~-0.5, ~0.5)
    # follow-through, landing and recovery
    @t_follow = param("t_follow", ~0.15, ~0.03, ~0.5)
    @th_fol = param("th_fol", ~0.5, ~-0.2, ~1.2)
    @knee_fol = param("knee_fol", ~0.4, ~0.0, ~1.5)
    @drv_brake = param("drv_brake", ~0.3, ~0.0, ~1.0)
    @th_land = param("th_land", ~0.3, ~-0.4, ~1.0)
    @knee_land = param("knee_land", ~0.3, ~0.0, ~1.2)
    @ankle_land = param("ankle_land", ~0.1, ~-0.4, ~0.5)
    @x_rec = param("x_rec", ~0.0, ~-0.2, ~0.2)
    @knee_rec = param("knee_rec", ~0.5, ~0.0, ~1.2)
    @rec_ldx = param("rec_ldx", ~0.0, ~-0.4, ~0.4)
    @rec_rdx = param("rec_rdx", ~0.1, ~-0.4, ~0.5)
    @rec_dz = param("rec_dz", ~0.6, ~0.3, ~0.79)
    @fe_rec = param("fe_rec", ~-0.4, ~-1.2, ~0.0)
    @t_rec = param("t_rec", ~0.3, ~0.05, ~1.0)
    self

  # ---- muscles ----------------------------------------------------------------

  -> leg_joint?(name)
    ["hip", "knee", "ankle", "subtalar", "mtp"].any? ->(k) name.include?(k)

  # Per muscle: length range (metres, from the geometry's length and
  # contraction at two postures), leg or trunk, side, and whether it extends
  # the lumbar spine (its contraction rises as the lumbar mode extends).
  -> classify
    g = @g
    @range = []
    @is_leg = []
    @extensors = []
    @leg_r = []
    @leg_l = []
    q0 = g.reference_posture
    mode = lumbar_mode
    i = 0
    while i < @n
      mu = body.muscle(i)
      leg = leg_joint?(mu.joint)
      @is_leg.push(leg)
      @leg_r.push(i) if leg && mu.name.ends_with?("_r")
      @leg_l.push(i) if leg && mu.name.ends_with?("_l")
      j = g.spans(i)[0]
      q1 = q0.map ->(v) v
      q1[j] = q1[j] + (g.qmax(j) - g.qmin(j)) * ~0.1
      dc = g.contraction(i, q0) - g.contraction(i, q1)
      dl = g.length(i, q1) - g.length(i, q0)
      r = ~0.1
      r = dl / dc if dc.abs > ~0.000001
      r = ~0.005 if r < ~0.005
      @range.push(r)
      s = ~0.0
      mode.each ->(pair)
        jj = g.joint(pair[0])
        s = s + pair[1] * g.contraction_slope(i, jj) if jj != nil
      @extensors.push(i) if s > ~0.02 && !leg
      i += 1
    @hip_flexors_r = agonists("hip_flexion_r", ~1.0, ~0.1)
    @kick_anta = agonists("hip_flexion_r", ~-1.0, ~0.1)
    agonists("knee_angle_r", ~1.0, ~0.1).each ->(i) @kick_anta.push(i) if !@kick_anta.include?(i)
    @knee_ext_r = agonists("knee_angle_r", ~-1.0, ~0.1)
    @hip_add_r = agonists("hip_adduction_r", ~1.0, ~0.1)
    @hip_rot_r = agonists("hip_rotation_r", ~1.0, ~0.2)
    agonists("hip_rotation_r", ~-1.0, ~0.2).each ->(i) @hip_rot_r.push(i) if !@hip_rot_r.include?(i)
    @ankle_r = agonists("ankle_angle_r", ~1.0, ~0.1)
    agonists("ankle_angle_r", ~-1.0, ~0.1).each ->(i) @ankle_r.push(i) if !@ankle_r.include?(i)
    @plantar_r = agonists("ankle_angle_r", ~-1.0, ~0.1)
    @plantar_l = agonists("ankle_angle_l", ~-1.0, ~0.1)
    # the support leg's antigravity muscles: knee extensors, plantarflexors,
    # hip extensors of the left leg
    @support_l = agonists("knee_angle_l", ~-1.0, ~0.1)
    @plantar_l.each ->(i) @support_l.push(i) if !@support_l.include?(i)
    agonists("hip_flexion_l", ~-1.0, ~0.15).each ->(i) @support_l.push(i) if !@support_l.include?(i) && @is_leg[i]
    @support_r = agonists("knee_angle_r", ~-1.0, ~0.1)
    @plantar_r.each ->(i) @support_r.push(i) if !@support_r.include?(i)
    agonists("hip_flexion_r", ~-1.0, ~0.15).each ->(i) @support_r.push(i) if !@support_r.include?(i) && @is_leg[i]
    self

  # Muscles that shorten as `joint` moves in direction `sign` (contraction
  # slope above thr): the agonists of that movement.
  -> agonists(joint, sign, thr)
    j = @g.joint(joint)
    out = []
    i = 0
    while i < @n
      out.push(i) if sign * @g.contraction_slope(i, j) > thr
      i += 1
    out

  # The lumbar flexion mode: flex_extension with its coupled vertebrae (with
  # a coupled geometry only flex_extension is a joint; the rest are skipped).
  -> lumbar_mode
    [["flex_extension", ~1.0], ["Abs_r3", ~0.6429], ["L4_L5_FE", ~0.185], ["L3_L4_FE", ~0.204], ["L2_L3_FE", ~0.231], ["L1_L2_FE", ~0.255]]

  -> set_gains(ctl)
    ctl.reflex.set_integral(@leg_l, @ki_leg, @ki_lim) if @ki_leg > ~0.0
    @kp_arr = []
    i = 0
    while i < @n
      k = @k_trunk
      k = @k_leg if @is_leg[i]
      k = k * @g_psoas if psoas?(i)
      kp = k * @range[i]
      kd = kp * @kd_ratio
      kd = kp * @kd_leg if @is_leg[i]
      ctl.reflex.set_gains([i], kp, kd)
      @kp_arr.push(kp)
      i += 1
    self

  # The psoas slips run from the lumbar vertebrae to the femur: the only hip
  # flexors that also flex the spine.
  -> psoas?(i)
    nm = body.muscle(i).name
    nm.starts_with?("Ps_") || nm.starts_with?("psoas")

  -> drive_on(list, level)
    d = zeros
    list.each ->(i) d[i] = level
    d

  # ---- postures -----------------------------------------------------------------

  -> base_posture
    p = MyoSoccerPosture.new(@g, @kf_ref > ~0.5)
    p.set("flex_extension", @fe)
    p.stiffen("hip", @stiff_l)
    p.stiffen("knee", @stiff_l)
    p.stiffen("ankle", @stiff_l)
    p.stiffen("subtalar", @stiff_l)
    p.stiffen("flex", @stiff_t)
    p

  -> leg(p, side, hip, knee, ankle)
    p.set("hip_flexion_" + side, hip)
    p.set("knee_angle_" + side, knee)
    p.set("ankle_angle_" + side, ankle)
    p

  # A leg given its thigh's world angle (knee ahead of the hip +) at the
  # nominal pelvis tilt: hip flexion = thigh angle + pelvis tilt (anterior +;
  # a pelvis tipped back extends the hip over a vertical femur).
  -> wleg(p, side, thigh, knee, ankle)
    leg(p, side, thigh + @tilt_step, knee, ankle)

  # A leg given where its ankle should be relative to its hip (world frame,
  # dx ahead, dz below, at the nominal pelvis tilt) and the foot's pitch
  # (0 flat, + toes up): two-link IK, hip flexion = thigh angle + tilt.
  -> fleg(p, side, dx, dz, pitch)
    tleg(p, side, dx, dz, pitch, @tilt0)

  # The same at pelvis tilt `tilt` (stepping postures let the pelvis come
  # forward to tilt_step so the stance hip is not pinned at its extension
  # limit).
  -> tleg(p, side, dx, dz, pitch, tilt)
    a = MyoSoccerLeg.ik(dx, dz)
    leg(p, side, a[0] + tilt, a[1], a[1] - a[0] + pitch)

  -> stance
    p = base_posture
    leg(p, "l", @hip, @knee, @ankle)
    leg(p, "r", @hip, @knee, @ankle)
    p

  # ---- aim ------------------------------------------------------------------------

  # The plant spot's y: beside the ball, shifted for the far-post variant.
  -> plant_y
    return @plant_y + @left_pdy if @aim > ~0.0
    @plant_y

  # Aim at the side of the goal away from the goalkeeper: +1 = left (+y),
  # -1 = right (the switch point is aim_split, see read_params). The
  # keeper's y is observed (env_goalkeeper_pos) every tick until the swing
  # commits to it. (The environment's first observation after a reset still
  # holds the keeper's pre-reset position, so the choice is never made from
  # the t = 0 frame alone.)
  -> choose_aim(f)
    ky = f.at("env_goalkeeper_pos", 1)
    return ~-1.0 if ky > @aim_split
    ~1.0

  -> track_aim(f)
    return self if @phase == :swing || @phase == :snap || @phase == :follow || @phase == :land || @phase == :recover
    @aim = choose_aim(f) if f.t > ~0.0
    self

  # ---- movement -----------------------------------------------------------------

  -> enter(f, phase, support, lat)
    @phase = phase
    @t_phase = f.t
    @heel0 = f.at("l_foot_pos", 0) if phase == :set
    @com0x = f.at("com_pos", 0)
    @com0y = f.at("com_pos", 1)
    @support = support
    @lat_to = lat
    self

  -> chunk(name, duration, posture, phase, support, lat)
    ch = Chunk.new(name, duration).pose(posture.pose)
    ch.correct(->(f, c) balance(f, c), @spring)
    ch.on_enter(->(f, c) enter_post(f, phase, support, lat, posture))
    ch

  -> enter_post(f, phase, support, lat, posture)
    @cur_post = posture
    enter(f, phase, support, lat)

  -> kick_stance(p)
    tleg(p, "l", @ks_dx, @ks_dz, @ks_pitch, @tilt_step)
    p.set("flex_extension", @fe_step)
    p.set("hip_adduction_l", @add_pl)
    p

  -> movement
    mv = Movement.new("kick")
    if @kv2 > ~0.5
      # approach (its hold decides at once when the start is already on the
      # spots), plant step, kick
      add_approach(mv)
      add_plant_step(mv)
      add_lunge_plant(mv) if @direct < ~0.5
      if @stage < ~1.5
        # practice stage: stand on the plant foot, kicking leg wound back
        p = kick_stance(base_posture)
        wleg(p, "r", @th_back, @knee_back, @ankle_back)
        mv.add(chunk("hold", ~0.3, p, :hold, :l, :l).hold_until(Latch.after(~100.0)))
        return mv
      add_kick(mv)
      return mv
    # the approach only runs when the start is not already the stance (P1's
    # reset is the key-frame stance itself)
    add_approach(mv) if @approach > ~0.5 && @start_err > @ap_tol
    # set: settle into the stance (pelvis back, lumbar flexed, tone on)
    t_set = @t_set
    t_set = ~100.0 if @stage < ~0.3
    mv.add(chunk("set", ~0.25, stance, :set, :both, :mid).hold_until(Latch.after(t_set)))
    # shift: move the COM over the right foot until the left one unloads
    p = stance
    p.set("hip_adduction_r", p.get("hip_adduction_r") + @shift_add)
    p.set("hip_adduction_l", p.get("hip_adduction_l") - @shift_add)
    p.set("subtalar_angle_r", p.get("subtalar_angle_r") + @shift_st)
    p.set("subtalar_angle_l", p.get("subtalar_angle_l") - @shift_st)
    # the step starts when the left foot is unloaded or, leaning, when the
    # COM has fallen d_go ahead of the feet (gait initiation as a caught fall)
    unloaded = Latch.test("unloaded", ->(f, e, c) @cl_f < @unload || (@d_go > ~0.0 && f.at("com_pos", 0) - support_point(f, :both)[0] > @d_go))
    mv.add(chunk("shift", @t_shift, p, :shift, :both, :r).hold_until(unloaded.after_min(@t_shift * ~0.5), ~2.0))
    # lift: left knee and hip flex (toe clearance), right leg starts the push
    p = base_posture
    p.set("flex_extension", @fe - @lean_step)
    fleg(p, "l", @lift_dx, @lift_dz, @lift_pitch)
    leg(p, "r", @hip, @knee, @ankle)
    # the swing starts once the heel is clear of the ground
    clear = Latch.test("clear", ->(f, e, c) f.at("l_foot_pos", 2) > @lift_h)
    mv.add(chunk("lift", @t_lift, p, :lift, :r, :r).hold_until(clear.after_min(@t_lift * ~0.5), ~0.5))
    if @stage < ~0.75
      # practice stage: stand on the right leg with the left one lifted
      mv.add(chunk("stork", ~0.3, p, :stork, :r, :r).hold_until(Latch.after(~100.0)))
      return mv
    # reach: the left leg swings to the plant spot (a placement correction
    # steers the ankle onto it), the right leg holds the body back over its
    # foot
    p = base_posture
    p.set("flex_extension", @fe - @lean_step)
    fleg(p, "l", @reach_dx, @reach_dz, @reach_pitch)
    p.set("hip_adduction_l", @add_reach)
    tleg(p, "r", @push_dx, @push_dz, @push_pitch, @tilt_step)
    p.set("flex_extension", @fe_step)
    @reach_posture = p
    # the step counts once the left foot is down at least min_step ahead of
    # where it started (a toe scuffing the ground at lift-off is not a step)
    touch = Latch.test("plant", ->(f, e, c) @cl_f > @plant_load && f.at("l_foot_pos", 0) > @heel0 + @min_step)
    ch = chunk("reach", @t_reach, p, :reach, :r, :r).hold_until(touch.after_min(~0.05), ~1.2)
    ch.drive(drive_on(@plantar_r, @drv_push))
    mv.add(ch)
    # direct: the kick starts the moment the plant foot lands (a running
    # kick: the trailing leg's push-off is the start of the swing);
    # otherwise a lunge carries the weight onto the plant foot first
    if @direct > ~0.5
      add_kick(mv)
      return mv
    add_lunge_plant(mv)
    if @stage < ~1.5
      mv.add(chunk("hold", ~0.3, p, :hold, :l, :l).hold_until(Latch.after(~100.0)))
      return mv
    add_kick(mv)
    mv

  # lunge: both feet down, the COM travels forward onto the left foot; plant:
  # the left leg takes the weight, the right leg winds back
  -> add_lunge_plant(mv)
    p = base_posture
    tleg(p, "l", @lg_dx, @lg_dz, @lg_pitch, @tilt_step)
    p.set("hip_adduction_l", @add_pl)
    tleg(p, "r", @lr_dx, @lr_dz, @lr_pitch, @tilt_step)
    p.set("flex_extension", @fe_step)
    over = Latch.test("over", ->(f, e, c) @cr_f < @unload_r)
    mv.add(chunk("lunge", @t_lunge, p, :lunge, :lunge, :lunge).hold_until(over.after_min(@t_lunge * ~0.5), @t_lunge_max))
    p = kick_stance(base_posture)
    wleg(p, "r", @th_back, @knee_back, @ankle_back)
    mv.add(chunk("plant", @t_plant, p, :plant, :l, :l).hold_until(Latch.after(@t_plant)))
    mv

  # ---- approach (phase 2) ---------------------------------------------------------
  #
  # From a random start behind the ball the feet walk, one quasi-static step
  # at a time, onto the practised stance spots (goal_l, goal_r):
  #
  #   ap_hold ──(t)──> branch: next step or `set`
  #   X_shift ──(X foot unloaded)──> X_lift ──(X heel up)──> X_reach
  #   X_reach ──(X foot loaded)──> X_settle ──(t)──> branch: next step or `set`
  #
  # The branch (Chunk#branch) chooses the foot and the step at run time from
  # the measured foot positions: each foot's error to its spot, clipped to a
  # step (ap_max_x, ap_max_y), keeping the feet from crossing (ap_min_sep)
  # or splitting too far (ap_max_split); the foot whose clipped step makes
  # more progress goes (ties: the one that did not just step). In the reach a
  # live two-link IK correction steers the swing ankle onto the chosen spot.
  -> add_approach(mv)
    ch = chunk("ap_hold", @ap_t_ease, stance, :ap_hold, :both, :mid).hold_until(Latch.after(@ap_t_hold))
    ch.branch(->(f, c) next_step(f))
    mv.add(ch)
    postures = @ap_postures
    ["l", "r"].each ->(sd)
      o = "r"
      o = "l" if sd == "r"
      ssym = :l
      ssym = :r if sd == "r"
      osym = :r
      osym = :l if sd == "r"
      # shift: the COM over the stance foot until the swing foot unloads
      # (or, with ap_apex on, at the apex of the lateral shift: the COM's
      # velocity toward the stance foot has died away while the swing foot
      # is below ap_apex_load, so the short single support falls toward the
      # landing foot rather than out over the stance foot)
      unl = Latch.test(sd + "_unl", ->(f, e, c) foot_load(sd) < @ap_unload || apex?(f, sd))
      mv.add(chunk(sd + "_shift", @ap_t_shift, stance, :ap_shift, :both, osym).hold_until(unl.after_min(@ap_t_shift * ~0.5), ~1.5))
      # lift: the swing foot clears the ground
      p = base_posture
      tleg(p, sd, @ap_lift_dx, @ap_lift_dz, @ap_lift_pitch, @ap_tilt)
      ap_stance_leg(p, o)
      p.set("flex_extension", @ap_fe)
      @ap_lift_postures[sd] = p
      up = Latch.test(sd + "_up", ->(f, e, c) f.at(sd + "_foot_pos", 2) > @ap_lift_h)
      # (practice stage 0.1: hold the lift, a one-leg stance test)
      tmax = ~0.5
      if @stage < ~0.15
        up = Latch.after(~100.0)
        tmax = ~100.0
      mv.add(chunk(sd + "_lift", @ap_t_lift, p, :ap_lift, osym, osym).hold_until(up.after_min(@ap_t_lift * ~0.5), tmax))
      # reach: the swing ankle is steered onto its spot; lands on load
      p = base_posture
      tleg(p, sd, @ap_lift_dx, @ap_reach_dz, @ap_reach_pitch, @ap_tilt)
      ap_stance_leg(p, o)
      p.set("flex_extension", @ap_fe)
      postures[sd] = p
      down = Latch.test(sd + "_down", ->(f, e, c) foot_load(sd) > @ap_load || abort?(f, sd))
      mv.add(chunk(sd + "_reach", @ap_t_reach, p, :ap_reach, osym, osym).hold_until(down.after_min(@ap_t_reach * ~0.5), @ap_reach_max))
      # settle: both feet down, the COM back between them
      ch = chunk(sd + "_settle", ~0.2, stance, :ap_settle, :both, :mid).hold_until(Latch.after(@ap_t_settle))
      ch.branch(->(f, c) next_step(f))
      mv.add(ch)
    mv

  -> ap_stance_leg(p, side)
    leg(p, side, @hip + @ap_st_hip, @knee + @ap_st_knee, @ankle + @ap_st_ankle)

  # The approach is done: the kick sequence (kv2: the plant step toward the
  # plant spot beside the ball, then the kick; else the practised `set`).
  -> done_step(f)
    return "set" if @kv2 < ~0.5
    @step_side = "l"
    @step_to = [f.at("env_ball_pos", 0) + @kp_dx, f.at("env_ball_pos", 1) + @kp_dy]
    @plant_step = true
    "k_shift"

  # kv2 plant step: the left step of the approach aimed at the plant spot.
  -> add_plant_step(mv)
    unl = Latch.test("k_unl", ->(f, e, c) foot_load("l") < @ap_unload || apex?(f, "l"))
    mv.add(chunk("k_shift", @ap_t_shift, stance, :ap_shift, :both, :r).hold_until(unl.after_min(@ap_t_shift * ~0.5), ~1.5))
    up = Latch.test("k_up", ->(f, e, c) f.at("l_foot_pos", 2) > @ap_lift_h)
    tmax = ~0.5
    # (practice stage 0.1: hold the lift, a one-leg stance on the right foot)
    if @stage < ~0.15
      up = Latch.after(~100.0)
      tmax = ~100.0
    mv.add(chunk("k_lift", @ap_t_lift, @ap_lift_postures["l"], :ap_lift, :r, :r).hold_until(up.after_min(@ap_t_lift * ~0.5), tmax))
    down = Latch.test("k_down", ->(f, e, c) foot_load("l") > @ap_load || abort?(f, "l"))
    mv.add(chunk("k_reach", @ap_t_reach, @ap_postures["l"], :ap_reach, :r, :r).hold_until(down.after_min(@ap_t_reach * ~0.5), @ap_reach_max))
    mv

  -> apex?(f, sd)
    return false if @ap_apex < ~0.5
    # the swing side's outward direction: +y for the left foot
    out = ~1.0
    out = ~-1.0 if sd == "r"
    # COM velocity toward the stance foot (away from the swing side)
    vin = ~0.0 - out * f.at("com_vel", 1)
    tg = ap_target(f)
    vin < @ap_vapex && foot_load(sd) < @ap_apex_load && (f.at("com_pos", 1) - tg[1]).abs < @ap_apex_tol

  # The COM more than ap_abort outward of the stance foot (away from the
  # swing foot): the swing cannot catch that fall.
  -> abort?(f, sd)
    st = "r"
    st = "l" if sd == "r"
    c = foot_center(f, st)
    out = ~1.0
    out = ~-1.0 if st == "r"
    out * (f.at("com_pos", 1) - c[1]) > @ap_abort

  -> foot_load(side)
    return @cl_f if side == "l"
    @cr_f

  -> clip(v, lim)
    return lim if v > lim
    return ~0.0 - lim if v < ~0.0 - lim
    v

  # The next chunk after a hold or a settled step: a step of the foot that
  # makes the most progress toward its spot, or the kick sequence when both
  # feet are within ap_tol.
  -> next_step(f)
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    el = [@goal_l[0] - l[0], @goal_l[1] - l[1]]
    er = [@goal_r[0] - r[0], @goal_r[1] - r[1]]
    nl = Math.sqrt(el[0] * el[0] + el[1] * el[1])
    nr = Math.sqrt(er[0] * er[0] + er[1] * er[1])
    return done_step(f) if (nl < @ap_tol && nr < @ap_tol) || @steps >= 12
    # candidate steps, clipped and kept from crossing or splitting
    dlx = clip(el[0], @ap_max_x)
    dly = clip(el[1], @ap_max_y)
    dly = r[1] + @ap_min_sep - l[1] if l[1] + dly < r[1] + @ap_min_sep
    dlx = clip(l[0] + dlx - r[0], @ap_max_split) + r[0] - l[0]
    drx = clip(er[0], @ap_max_x)
    dry = clip(er[1], @ap_max_y)
    dry = l[1] - @ap_min_sep - r[1] if r[1] + dry > l[1] - @ap_min_sep
    drx = clip(r[0] + drx - l[0], @ap_max_split) + l[0] - r[0]
    gl = nl - Math.sqrt((el[0] - dlx) * (el[0] - dlx) + (el[1] - dly) * (el[1] - dly))
    gr = nr - Math.sqrt((er[0] - drx) * (er[0] - drx) + (er[1] - dry) * (er[1] - dry))
    if @last_side == "l"
      gl = gl * ~0.5
    if @last_side == "r"
      gr = gr * ~0.5
    @steps += 1
    if gl >= gr
      @step_side = "l"
      @step_to = [l[0] + dlx, l[1] + dly]
      @last_side = "l"
      return "l_shift"
    @step_side = "r"
    @step_to = [r[0] + drx, r[1] + dry]
    @last_side = "r"
    "r_shift"

  # Double support: both legs re-solved by two-link IK from a pelvis whose
  # hips sit over the COM target (ap_target) at height ap_hz to the measured
  # ankles; the difference from the stance posture, scaled by ap_fit.
  -> fit_legs(f, off)
    tg = ap_target(f)
    p = stance
    rho = ~0.0 - Math.atan2(f.at("pelvis_upv", 1), f.at("pelvis_upv", 2))
    hxm = (f.at("l_hip_pos", 0) + f.at("r_hip_pos", 0)) * ~0.5
    hym = (f.at("l_hip_pos", 1) + f.at("r_hip_pos", 1)) * ~0.5
    ["l", "r"].each ->(sd)
      ax = f.at(sd + "_ankle_pos", 0)
      ay = f.at(sd + "_ankle_pos", 1)
      az = f.at(sd + "_ankle_pos", 2)
      hx = tg[0] + f.at(sd + "_hip_pos", 0) - hxm
      hy = tg[1] + f.at(sd + "_hip_pos", 1) - hym
      dz = @ap_hz - az
      a = MyoSoccerLeg.ik(ax - hx, dz)
      hip = a[0] + @tilt
      knee = a[1]
      ankle = a[1] - a[0]
      joint_offset(off, "hip_flexion_" + sd, @ap_fit * (hip - p.get("hip_flexion_" + sd)))
      joint_offset(off, "knee_angle_" + sd, @ap_fit * (knee - p.get("knee_angle_" + sd)))
      joint_offset(off, "ankle_angle_" + sd, @ap_fit * (ankle - p.get("ankle_angle_" + sd)))
      phi = Math.atan2(ay - hy, dz)
      add = rho - phi
      add = phi - rho if sd == "r"
      joint_offset(off, "hip_adduction_" + sd, @ap_fit * (add - p.get("hip_adduction_" + sd)))
    off

  # Single support (hq on): the stance hip as a torque servo on the pelvis.
  -> hip_servo(f, off)
    sd = "r"
    sd = "l" if @support == :l
    sg = ~-1.0
    sg = ~1.0 if @support == :l
    p = @cur_post
    ["hip_flexion_", "hip_adduction_", "hip_rotation_"].each ->(jn)
      j = jn + sd
      joint_offset(off, j, @hq_rel * (f.q(body, j) + @hq_lead * f.qd(body, j) - p.get(j)))
    tf = ~0.0 - (@hq_tkp * (@tilt - @hq_tilt) + @hq_tkd * f.at("pelvis_angvel", 1))
    ta = ~0.0 - sg * (@hq_rkp * @proll + @hq_rkd * f.at("pelvis_angvel", 0))
    tr = ~0.0 - sg * (@hq_ykp * @yaw + @hq_ykd * f.at("pelvis_angvel", 2))
    d = @hips[sd].offsets(tf, ta, tr)
    joint_offset(off, "hip_flexion_" + sd, d[0])
    joint_offset(off, "hip_adduction_" + sd, d[1])
    joint_offset(off, "hip_rotation_" + sd, d[2])
    off

  # Single support: the stance hip's posture pull is cancelled by ap_rel
  # (its target follows the measured angle, led by ap_lead x velocity).
  -> release_stance(f, off)
    sw = @step_side
    st = "r"
    st = "l" if sw == "r"
    p = @ap_postures[sw]
    p = @ap_lift_postures[sw] if @phase == :ap_lift
    ["hip_flexion_", "hip_adduction_", "hip_rotation_"].each ->(jn)
      j = jn + st
      joint_offset(off, j, @ap_rel * (f.q(body, j) + @ap_lead * f.qd(body, j) - p.get(j)))
    off

  # Approach placement: live two-link IK from the swing hip to the chosen spot
  # (foot centre -> ankle: 4 cm back), as `place` does for the plant.
  -> place_step(f, off)
    sd = @step_side
    hx = f.at(sd + "_hip_pos", 0)
    hy = f.at(sd + "_hip_pos", 1)
    hz = f.at(sd + "_hip_pos", 2)
    # foot centre -> ankle: 4 cm back, 1.5 cm medial (measured at the stance)
    tx = @step_to[0] - ~0.04 + @ap_cpx * f.at("com_vel", 0)
    ty = @step_to[1] - ~0.015 + @ap_cp * f.at("com_vel", 1)
    ty = @step_to[1] + ~0.015 + @ap_cp * f.at("com_vel", 1) if sd == "r"
    # the offset in the pelvis's heading frame (a yawed pelvis turns the
    # hip's flexion plane; ap_yawc = 1 compensates fully), and the swing
    # hip rotated so the foot lands pointing along x (ap_yawr)
    c = Math.cos(@yaw * @ap_yawc)
    s = Math.sin(@yaw * @ap_yawc)
    ddx = tx - hx
    ddy = ty - hy
    fx = ddx * c + ddy * s
    fy = ddy * c - ddx * s
    tx = hx + fx
    ty = hy + fy
    a = MyoSoccerLeg.ik(tx - hx, hz - ~0.07)
    hip = a[0] + @tilt
    knee = a[1]
    ankle = a[1] - a[0] + @ap_reach_pitch
    p = @ap_postures[sd]
    # (hip_rotation + turns the right foot's toes left and the left foot's
    # toes right, measured on the model)
    rot = ~0.0 - @ap_yawr * @yaw
    rot = @ap_yawr * @yaw if sd == "l"
    joint_offset(off, "hip_rotation_" + sd, rot)
    joint_offset(off, "hip_flexion_" + sd, @ap_k_ik * (hip - p.get("hip_flexion_" + sd)))
    joint_offset(off, "knee_angle_" + sd, @ap_k_ik * (knee - p.get("knee_angle_" + sd)))
    joint_offset(off, "ankle_angle_" + sd, @ap_k_ik * (ankle - p.get("ankle_angle_" + sd)))
    rho = ~0.0 - Math.atan2(f.at("pelvis_upv", 1), f.at("pelvis_upv", 2))
    phi = Math.atan2(ty - hy, hz - ~0.07)
    add = rho - phi
    add = phi - rho if sd == "r"
    joint_offset(off, "hip_adduction_" + sd, @ap_k_py * (add - p.get("hip_adduction_" + sd)))
    off

  # The kick, latched on the plant: swing (the hip drives the thigh through,
  # knee folded), snap (the knee whips open through the ball, latched on the
  # thigh passing hip_snap), follow-through, landing and recovery.
  -> add_kick(mv)
    return add_side_kick(mv) if @side > ~0.5
    # swing: the hip drives the thigh through, the knee stays folded
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k1, @knee_k1, @ankle_k)
    thigh = Latch.test("thigh", ->(f, e, c) f.q(body, "hip_flexion_r") > @hip_snap)
    ch = chunk("swing", @t_swing, p, :swing, :l, :l).hold_until(thigh, @t_swing * ~2.5)
    ch.drive(drive_on(@hip_flexors_r, @drv_hip))
    mv.add(ch)
    # snap: the knee whips open through the ball
    p = kick_stance(base_posture)
    wleg(p, "r", @th_k2, @knee_k2, @ankle_k)
    hit = Latch.test("touch", ->(f, e, c) f.get("ball_touch") > ~0.5)
    ch = chunk("snap", @t_snap, p, :snap, :l, :l).hold_until(hit, @t_snap * ~2.5)
    d = drive_on(@knee_ext_r, @drv_knee)
    @hip_flexors_r.each ->(i) d[i] = @drv_hip
    ch.drive(d)
    mv.add(ch)
    add_after_touch(mv)

  -> add_after_touch(mv)
    # follow-through: the kicking leg is braked (hip extensor burst) and
    # brought down in front, so its momentum does not tip the body over
    p = kick_stance(base_posture)
    wleg(p, "r", @th_fol, @knee_fol, @ankle_land)
    ch = chunk("follow", @t_follow, p, :follow, :l, :l).hold_until(Latch.after(@t_follow))
    ch.drive(drive_on(@kick_anta, @drv_brake))
    mv.add(ch)
    p = kick_stance(base_posture)
    wleg(p, "r", @th_land, @knee_land, @ankle_land)
    land = Latch.contact("r_foot", ~0.1)
    mv.add(chunk("land", ~0.2, p, :land, :l, :l).hold_until(land.after_min(~0.05), ~0.8))
    # recover: both feet down, sinking into a low, wide crouch (the pelvis
    # only has to stay above 0.2 m until the ball arrives), trunk as low as
    # it likes over the thighs
    p = base_posture
    tleg(p, "l", @rec_ldx, @rec_dz, ~0.0, @tilt_step)
    tleg(p, "r", @rec_rdx, @rec_dz, ~0.0, @tilt_step)
    p.set("flex_extension", @fe_rec)
    mv.add(chunk("recover", @t_rec, p, :recover, :both, :mid).hold_until(Latch.after(~100.0)))
    mv

  # The kicking leg for the side-foot strike: thigh (world angle), knee, the
  # ankle locked in dorsiflexion and the hip turned out.
  -> side_leg(p, thigh, knee)
    wleg(p, "r", thigh, knee, @s_ankle)
    p.set("hip_rotation_r", @s_rot)
    p.set("hip_adduction_r", p.get("hip_adduction_r") + @s_add)
    p.stiffen("ankle_angle_r", @s_stiff)
    p.stiffen("subtalar_angle_r", @s_stiff)
    p

  -> side_drive(knee_drive)
    d = drive_on(@hip_flexors_r, @drv_hip)
    @hip_add_r.each ->(i) d[i] = d[i] + @s_drv_add
    @ankle_r.each ->(i) d[i] = d[i] + @s_drv_ank
    @knee_ext_r.each ->(i) d[i] = d[i] + knee_drive
    d

  # Side-foot kick: swing (hip flexors and adductors drive the turned-out
  # leg along the target line, knee bent s_knee1) and strike (the knee opens
  # only to s_knee2, the medial arch meets the ball), then the same
  # follow-through, landing and recovery as the instep kick.
  -> add_side_kick(mv)
    # cock (backswing): the push-off foot leaves the ground, the hip turns
    # out and the ankle locks in dorsiflexion before the swing starts
    if @s_t_cock > ~0.0
      p = side_leg(kick_stance(base_posture), @s_th_cock, @s_knee_cock)
      ch = chunk("cock", @s_t_cock, p, :cock, :l, :l).hold_until(Latch.after(@s_t_cock))
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

  # ---- balance ------------------------------------------------------------------

  -> thorax_pitch(f)
    Math.atan2(f.at("thorax_up", 0), f.at("thorax_up", 2))

  # Thorax roll (+ = leaning toward +y, the body's left).
  -> thorax_roll(f)
    Math.atan2(f.at("thorax_up", 1), f.at("thorax_up", 2))

  -> pelvis_tilt(f)
    Math.atan2(f.at("pelvis_upv", 0), f.at("pelvis_upv", 2))

  -> foot_center(f, side)
    x = (f.at(side + "_foot_pos", 0) + f.at(side + "_toe_pos", 0)) * ~0.5
    y = (f.at(side + "_foot_pos", 1) + f.at(side + "_toe_pos", 1)) * ~0.5
    [x, y]

  # Balance target (x, y): the loaded foot's centre, or between the feet.
  -> support_point(f, which)
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    return l if which == :l
    return r if which == :r
    return lunge_point(f, l) if which == :lunge
    [(l[0] + r[0]) * ~0.5, (l[1] + r[1]) * ~0.5]

  # Lunge target: from where the COM was when both feet came down to over
  # the left foot (plus x_lunge, y_lunge), eased min-jerk over t_lunge, so
  # the weight travels onto the front foot instead of being yanked there.
  -> lunge_point(f, l)
    u = Easing.apply(:min_jerk, (f.t - @t_phase) / @t_lunge)
    tx = l[0] + @x_lunge
    ty = l[1] + @y_lunge
    [@com0x + (tx - @com0x) * u, @com0y + (ty - @com0y) * u]

  -> lumbar_offset(off, dq)
    lumbar_mode.each ->(pair) joint_offset(off, pair[0], pair[1] * dq)
    off

  # Where the COM should sit ahead of the support point in this phase.
  -> approach?
    @phase == :ap_hold || @phase == :ap_shift || @phase == :ap_lift || @phase == :ap_reach || @phase == :ap_settle

  # The approach's COM target (x, y). Weight shift: from where the COM was
  # when the phase began to over the stance foot (ap_x ahead, ap_shift_y
  # toward its outside), min-jerk over ap_t_shift. Swing: over the stance
  # foot, leaning ap_fwd / ap_lat of the way toward the landing spot.
  # Settle: back between the feet over ap_t_back.
  -> ap_target(f)
    l = foot_center(f, "l")
    r = foot_center(f, "r")
    mid = [(l[0] + r[0]) * ~0.5 + @ap_x, (l[1] + r[1]) * ~0.5]
    return mid if @phase == :ap_hold
    return eased(f, mid, @ap_t_back) if @phase == :ap_settle
    st = l
    st = r if @lat_to == :r
    out = ~1.0
    out = ~-1.0 if @lat_to == :r
    tx = st[0] + @ap_x
    # the plant step leans forward first (a caught fall onto the plant foot)
    tx = st[0] + @kp_x if @plant_step
    ty = st[1] + out * @ap_shift_y
    ty = st[1] + out * @kp_shift_y if @plant_step
    return eased(f, [tx, ty], @ap_t_shift) if @phase == :ap_shift
    return [tx, ty] if @phase == :ap_lift
    fw = @ap_fwd
    fw = @kp_fwd if @plant_step
    lt = @ap_lat
    lt = @kp_lat if @plant_step
    [tx + fw * (@step_to[0] - tx), ty + lt * (@step_to[1] - ty)]

  -> eased(f, target, dur)
    u = Easing.apply(:min_jerk, clamp((f.t - @t_phase) / dur, ~0.0, ~1.0))
    [@com0x + (target[0] - @com0x) * u, @com0y + (target[1] - @com0y) * u]

  -> x_target
    return @ap_x if approach?
    return @shift_x if @phase == :shift
    return @x_step if @phase == :lift || @phase == :reach
    return @x_plant if @support == :l
    return ~0.0 if @support == :lunge
    @x_des

  -> k_ankle
    return @k_ax_st if @phase == :lift || @phase == :reach
    @k_ax

  # Offsets for one tick:
  #   trunk      lumbar servo on thorax pitch (PD), plus a hip strategy on
  #              the stance hip(s)
  #   sagittal   ankle strategy on the COM's fore-aft error (stance ankles)
  #   lateral    hip ab/adduction (and subtalar) on the COM's lateral error
  #   swing leg  thigh held in world frame (pelvis pitch compensated)
  #   aim        the kicking hip's adduction and rotation
  -> balance(f, ctl)
    off = zeros
    rate = f.at("torso_angvel", 1)
    ap = approach?
    kth = @k_th
    kthd = @k_thd
    pdes = @pitch_des
    khp = @k_hp
    khpd = @k_hpd
    kpr = @k_pr
    kay = @k_ay
    kst1 = @k_st1
    if ap
      kth = @ap_k_th
      kthd = @ap_k_thd
      pdes = @ap_pitch_des
      khp = @ap_k_hp
      khpd = @ap_k_hpd
      kpr = @ap_k_pr
      kay = @ap_k_ay
      kst1 = @ap_k_st1
    perr = @pitch - pdes
    lumbar_offset(off, kth * perr + kthd * rate)
    roll = @roll
    rrate = f.at("torso_angvel", 0)
    klb = @k_lb
    klb = @ap_k_lb if ap
    joint_offset(off, "lat_bending", klb * roll)
    hr = @k_roll * roll + @k_rolld * rrate
    # pelvis roll (+ = left side up): a stance hip abducts against the pelvis
    # dropping on the swing side (Trendelenburg), as the gluteus medius does
    pr = kpr * @proll + @k_prd * f.at("pelvis_angvel", 0)
    hs = ~0.0 - (khp * perr + khpd * rate)
    comp = @k_comp * (@tilt - @tilt0)
    if ap
      tg = ap_target(f)
      ex = f.at("com_pos", 0) - tg[0]
      ey = f.at("com_pos", 1) - tg[1]
      da = clamp(~0.0 - @ap_k_ax * (ex + @ap_k_axv * f.at("com_vel", 0)), ~0.0 - @ap_clamp, @ap_clamp)
      dy = clamp(~0.0 - (kay * ey + @ap_k_ayv * f.at("com_vel", 1)), ~0.0 - @ap_clamp, @ap_clamp)
      hr = @ap_k_roll * roll + @k_rolld * rrate
    else
      spx = support_point(f, @support)
      spy = support_point(f, @lat_to)
      ex = f.at("com_pos", 0) - spx[0] - x_target
      da = ~0.0 - k_ankle * (ex + @k_axv * f.at("com_vel", 0))
      ey = f.at("com_pos", 1) - spy[1]
      # in the swing the lateral target leans toward the landing spot, so the
      # COM is already falling onto the new foot when it lands
      ey = ey - @reach_lat * (plant_y - spy[1]) if @phase == :reach
      ey = ey - @shift_y if @lat_to == :r
      dy = ~0.0 - (kay * ey + @k_ayv * f.at("com_vel", 1))
    k1 = @k_ay1
    k1 = @ap_k_ay1 if ap
    kst2 = @k_st2
    kst2 = @ap_k_st2 if ap
    # heading: the stance hips' rotators hold the pelvis facing the goal
    yr = @k_yaw * @yaw + @k_yawd * f.at("pelvis_angvel", 2)
    if @support == :both || @support == :lunge
      joint_offset(off, "ankle_angle_l", da)
      joint_offset(off, "ankle_angle_r", da)
      joint_offset(off, "hip_adduction_l", dy + hr)
      joint_offset(off, "hip_adduction_r", ~0.0 - dy - hr)
      joint_offset(off, "subtalar_angle_l", kst2 * dy)
      joint_offset(off, "subtalar_angle_r", ~0.0 - kst2 * dy)
      joint_offset(off, "hip_flexion_l", hs)
      joint_offset(off, "hip_flexion_r", hs)
    hqon = @hq > ~0.5
    if @support == :l
      joint_offset(off, "ankle_angle_l", da)
      joint_offset(off, "hip_adduction_l", k1 * dy + hr - pr) if !hqon
      joint_offset(off, "subtalar_angle_l", kst1 * dy)
      joint_offset(off, "hip_flexion_l", hs) if !hqon
      joint_offset(off, "hip_flexion_r", comp)
    if @support == :r
      joint_offset(off, "ankle_angle_r", da)
      joint_offset(off, "hip_adduction_r", ~0.0 - k1 * dy - hr + pr) if !hqon
      joint_offset(off, "subtalar_angle_r", ~0.0 - kst1 * dy)
      joint_offset(off, "hip_flexion_r", hs) if !hqon
      joint_offset(off, "hip_flexion_l", comp)
    hip_servo(f, off) if hqon && (@support == :l || @support == :r)
    if @phase == :reach
      place(f, off)
      # side-foot: the plant foot turned toward the target before it lands
      joint_offset(off, "hip_rotation_l", @s_plant_rot) if @side > ~0.5
    if @phase == :ap_reach
      place_step(f, off)
    release_stance(f, off) if (@phase == :ap_lift || @phase == :ap_reach) && @ap_rel > ~0.0
    fit_legs(f, off) if (@phase == :ap_hold || @phase == :ap_shift || @phase == :ap_settle) && @ap_fit > ~0.0
    if approach? && !(hqon && (@support == :l || @support == :r))
      joint_offset(off, "hip_rotation_l", ~0.0 - yr) if @support != :r
      joint_offset(off, "hip_rotation_r", yr) if @support != :l
    if @side > ~0.5 && (@phase == :set || @phase == :shift || @phase == :lift || @phase == :reach)
      # side-foot: the run-up keeps the pelvis from twisting toward the plant side
      ys = @s_kyaw_run * (@yaw - @s_yaw_run)
      joint_offset(off, "hip_rotation_l", ~0.0 - ys) if @support != :r
      joint_offset(off, "hip_rotation_r", ys) if @support != :l
    if @phase == :swing || @phase == :snap || @phase == :cock
      # aim: the kicking foot's lateral path is steered onto the ball (a
      # contact off the ball's centre line sends it the other way), offset
      # toward the side that sends the ball away from the keeper; the hip's
      # rotation turns the foot's face with it
      ty = f.at("env_ball_pos", 1) + @kick_dy + @aim * @aim_dy
      add = @add_k + @aim_add * @aim
      rot = @rot_k + @aim_rot * @aim
      if @aim > ~0.0
        # the far-post (left, +y) variant of the kick has its own offsets
        ty = ty + @left_dy
        add = add + @left_add
        rot = rot + @left_rot
      if @side > ~0.5
        # side-foot: the turn-out is in the posture (s_rot); the aim moves
        # the foot's path (s_dy, s_aim_dy) and face (s_aim_add, s_aim_rot);
        # the pelvis opens over the plant hip (s_open)
        ty = f.at("env_ball_pos", 1) + @s_dy + @aim * @s_aim_dy
        add = @s_aim_add * @aim
        rot = @s_aim_rot * @aim + @s_servo * (@s_rot - f.q(body, "hip_rotation_r"))
        joint_offset(off, "hip_rotation_l", @s_open - @s_kyaw * (@yaw - @s_yaw_des))
        joint_offset(off, "ankle_angle_r", @s_servo * (@s_ankle - f.q(body, "ankle_angle_r")))
      joint_offset(off, "hip_adduction_r", add + @k_ky * (ty - f.at("r_ankle_pos", 1)))
      joint_offset(off, "hip_rotation_r", rot)
    off

  # Swing placement (reach): the ankle target is the plant spot beside the
  # ball; live two-link IK from the measured hip position and pelvis pitch
  # and roll gives the leg angles that put the ankle there, and the
  # difference from the reach posture is the correction (scaled by k_ik).
  -> place(f, off)
    hx = f.at("l_hip_pos", 0)
    hy = f.at("l_hip_pos", 1)
    hz = f.at("l_hip_pos", 2)
    a = MyoSoccerLeg.ik(@plant_x - hx, hz - ~0.07)
    hip = a[0] + @tilt
    knee = a[1]
    ankle = a[1] - a[0] + @reach_pitch
    p = @reach_posture
    joint_offset(off, "hip_flexion_l", @k_ik * (hip - p.get("hip_flexion_l")))
    joint_offset(off, "knee_angle_l", @k_ik * (knee - p.get("knee_angle_l")))
    joint_offset(off, "ankle_angle_l", @k_ik * (ankle - p.get("ankle_angle_l")))
    rho = ~0.0 - Math.atan2(f.at("pelvis_upv", 1), f.at("pelvis_upv", 2))
    add = rho - Math.atan2(plant_y - hy, hz - ~0.07)
    joint_offset(off, "hip_adduction_l", @k_py * (add - p.get("hip_adduction_l")))
    off

  -> before(frame, ctl)
    track_aim(frame)
    k = ctl.dt / (~0.05 + ctl.dt)
    @cl_f = @cl_f + (frame.get("l_foot_contact") - @cl_f) * k
    @cr_f = @cr_f + (frame.get("r_foot_contact") - @cr_f) * k
    @pitch = thorax_pitch(frame)
    @tilt = pelvis_tilt(frame)
    @roll = thorax_roll(frame)
    @proll = ~0.0 - Math.atan2(frame.at("pelvis_upv", 1), frame.at("pelvis_upv", 2))
    @yaw = Math.atan2(frame.at("pelvis_fwd", 1), frame.at("pelvis_fwd", 0))
    self

  # Postural tone (the back extensors' drive, integrating thorax pitch error)
  # and the loose kicking leg (a ballistic swing: reflexes turned down).
  -> after(frame, ctl)
    pdes = @pitch_des
    pdes = @ap_pitch_des if approach?
    @tone = clamp(@tone + @k_tone * (@pitch - pdes) * ctl.dt, ~0.0, ~1.0)
    tone = @tone
    @extensors.each ->(i) ctl.add_drive(i, tone)
    # the support leg on its own after the plant: firmer reflexes and an
    # antigravity drive so it does not buckle under the lunge and the kick
    if @support == :l && !approach?
      gs = @g_st
      ds = @drv_st
      # after the touch the plant leg carries the follow-through
      ds = @drv_post if @phase == :follow || @phase == :land
      @leg_l.each ->(i) ctl.set_gain(i, gs)
      @support_l.each ->(i) ctl.add_drive(i, ds)
    if approach? && @support == :r
      da = @ap_drv_st
      @support_r.each ->(i) ctl.add_drive(i, da)
    if approach? && @support == :l
      da = @ap_drv_st
      @support_l.each ->(i) ctl.add_drive(i, da)
    if @phase == :swing || @phase == :snap
      g = @g_kick
      @leg_r.each ->(i) ctl.set_gain(i, g)
      # reciprocal inhibition: the kick's antagonists (hip extensors, knee
      # flexors) are silenced so their stretch reflexes do not brake the
      # swing
      ga = @g_anta
      @kick_anta.each ->(i) ctl.set_gain(i, ga)
    if @side > ~0.5 && (@phase == :swing || @phase == :snap || @phase == :cock)
      ge = @s_g_ank
      @ankle_r.each ->(i) ctl.set_gain(i, ge)
      gr = @s_g_rot
      @hip_rot_r.each ->(i) ctl.set_gain(i, gr)
    self
