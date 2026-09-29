# MyoWalk: 3D standing balance and walking on the MyoSuite myoLeg (80
# muscles on wrapped tendons, free root, ChaseTag body), written as robolab
# contraction chunks.
#
# Every posture below is an equilibrium point: a Pose of the 7 joints of a
# leg (hip flexion / adduction / rotation, knee, ankle, subtalar, mtp) that
# the body's Geometry turns into one contraction per muscle, eased by the
# chunk and held by the lambda-model reflexes. Feedback is spring-eased
# corrections (joint offsets) added on top every tick. In this model the
# torso is rigid on the pelvis, so "trunk" below means the pelvis.
#
# Modes (the task's `walk_goal` sensor block, [mode, v_des, heading_des],
# or the `mode` param when there is none):
#
#   0 stand   one track, one chunk (`stand`) held forever, with
#             sagittal  an ankle strategy on the COM-over-feet error
#                       (plantarflex when the COM drifts ahead) and a hip
#                       strategy that servoes pelvis pitch
#             lateral   both hips shift the pelvis over the feet (one leg
#                       adducts while the other abducts)
#             yaw       the hip rotators hold the heading
#
#   1 walk    two tracks, one per leg (disjoint muscle masks), each looping
#             four chunks latched on that leg's own sensations:
#
#     X_stance ──(COM d_push ahead of the X foot, other leg not pushing)──> X_push
#     X_push   ──(X foot released: toe-off; or push_max)─────────────────> X_lift
#     X_lift   ──(thigh swung past psi_go, world frame; or t_lift)───────> X_reach
#     X_reach  ──(X heel contact; or reach_max)──────────────────────────> X_stance
#
#             The legs coordinate through the body, as in Song & Geyer's
#             reflex walker: a leg pushes off once the COM has passed over
#             it (never while the other leg is pushing: walking has no
#             flight), and it lifts when its foot has unloaded. The poses
#             follow a human gait cycle (MyoSuite's sample_gait_cycle.csv):
#             loading knee flexion, push-off plantarflexion, a tucked swing
#             knee, a landing thigh angle. Lift eases cubic-out and reach
#             too (the equilibrium point jumps ahead: a ballistic swing);
#             stance and push ease min-jerk.
#
#             Frames. Balance lives in a travel frame psi_f: the smoothed
#             COM-velocity direction led toward the desired heading by at
#             most lead_max (rate-limited). Lateral foot placement then
#             bends the path at a bounded rate (Raibert-style steering), and
#             the frame never runs away from the motion. The pelvis is
#             servoed toward psi_f separately; a yawing pelvis (this model
#             has no arm swing, so each swinging leg's yaw momentum lands on
#             the trunk) no longer looks like a sideways fall.
#
#             Corrections (per leg, from its phase and load):
#             stance  the loaded hip is a world-frame trunk servo in torque
#                     units: the hip first stops pulling toward its commanded
#                     posture (target = measured angle), then a PD on pelvis
#                     pitch, roll and heading error (N m per rad) is applied
#                     through MyoWalkHip, a decoupled muscle map (the servo
#                     is not axis-pure: see MyoWalkHip). The trunk torque is
#                     shared by the legs in proportion to the load each
#                     carries (roll twice: in double support the hips cannot
#                     level the pelvis and shift it at once). The ankle keeps
#                     the foot flat (it follows the shank's world
#                     inclination), so the whole sole grips in yaw.
#             swing   the thigh is held in world frame (pelvis pitch and
#                     roll compensated); its landing direction is placed in
#                     the travel frame by the COM (Raibert / SIMBICON:
#                     forward cv (v - v_des) + cd d, outward
#                     ab_land + cv_lat v_lat + cd_lat d_lat) and rotated into
#                     the pelvis frame; the foot yaws toward psi_f; a
#                     withdrawal reflex lifts a dragging toe
#
#             From quiet standing (both feet down, COM still) walking starts
#             with a weight shift onto the left foot and a forward lean: the
#             right foot unloads, so its stance latch fires.
#
#   2 reflex  Song & Geyer's (2015) spinal reflex walker as ported to the
#             80-muscle myoLeg by Seungmoon Song and Chun Kwang Tan in MyoSuite
#             (agents/baseline_Reflex/reflexCtr.py, credit to them), written
#             as robolab chunks: each leg loops X_sg_stance ──(foot
#             released)──> X_sg_swing ──(foot contact)──> X_sg_stance, and the
#             spinal laws (positive force feedback on SOL, GAS, VAS, RF in
#             stance; trunk PD through HFL / GLU / HAM and HAB / HAD scaled
#             by load; leg-angle placement alpha_tgt = c0 - cv v - theta in
#             swing with knee flex / hold / stop / hold sub-phases latched on
#             knee angle, leg angle and leg retraction) are drives on the
#             eleven muscle groups. The lambda servo is relaxed (gain g_sg,
#             default 0) so the drives are the activations; placement uses the
#             travel frame (steering), and an optional stance-hip yaw torque
#             (MyoWalkHip, sg_yaw) holds the heading, which the original lacks.
#
#   3 one-leg stance (a balance test: shift onto the left foot, lift the right)
#
# Round-2 options (params flags; absent = the round-1 gait, bit for bit):
#   turn_gait = 1   a second leg loop (X_tstance / X_tpush / X_tlift / X_treach)
#                   that every chunk boundary branches into (Chunk#branch)
#                   while the goal heading is far off the motion: see turn_params
#   stride = 1      the trailing leg may push off during double support (a
#                   latch on the leading foot's load), for longer steps
#   lift_via = 1    the lift posture is a via point (Chunk#via): one smooth swing
#
# Drives (feed-forward activation on top of the reflexes): plantarflexor
# push-off in X_push, hip-flexor swing initiation early in X_lift, tonic
# abductor and vasti support in stance scaled by the leg's load share.
# Reflex gains are set per leg and phase in `after` (stance, push, swing,
# and a separate stance-ankle gain).
#
# All numbers are tunables (`param`), practised with CMA-ES over the
# official P1 reset (params/myo_walk.txt, params/myo_stand.txt).

# Joint-angle view of one leg's commanded posture: the Track eases the chunk
# poses in contraction space; this mirrors the easing in joint space so a
# correction can be written against the commanded angle (a world-frame
# servo needs "target angle minus commanded angle").
+ MyoWalkPlan
  -> new(names, init)
    @names = names
    @index = {}
    i = 0
    while i < names.size
      @index[names[i]] = i
      i += 1
    @q0 = init.map -> item
    @q1 = init.map -> item
    @t0 = ~0.0
    @dur = ~0.0
    @easing = :min_jerk

  -> angle(k, t)
    return @q1[k] if @dur <= ~0.0
    p = Easing.apply(@easing, (t - @t0) / @dur)
    @q0[k] + (@q1[k] - @q0[k]) * p

  -> cmd(name, t)
    angle(@index[name], t)

  # A chunk starts at time t, easing over dur toward goals, a flat array
  # [joint, angle, joint, angle, ...]; unnamed joints hold where they are.
  -> enter(t, dur, goals, easing)
    k = 0
    while k < @names.size
      a = angle(k, t)
      @q0[k] = a
      @q1[k] = a
      k += 1
    i = 0
    while i < goals.size
      @q1[@index[goals[i]]] = goals[i + 1]
      i += 2
    @t0 = t
    @dur = dur
    @easing = easing
    self

# Decoupled hip torque through the reflex layer. The lambda servo is not
# axis-pure: a kinematic joint offset (every crossing muscle shifted by its
# contraction slope) recruits muscles in proportion to their slopes, and the
# resulting hip torque leaks across axes through the muscles' other moment
# arms. On the myoLeg hip a 0.1 rad offset gives 72 Nm on adduction and 34 Nm
# on flexion but only 4 Nm on rotation, while flexion and adduction offsets
# leak 2-18 Nm into rotation: yaw is barely controlled and mostly disturbed.
# With each muscle's peak force F and length range L (sent by the task as
# the constant sensor blocks muscle_fmax / muscle_range) the linearised
# servo torque of an offset dq is tau = kp g K dq with
#
#   K = sum_i (F_i / L_i) r_i r_i^T,   r_i = moment arms = slope_i * L_i
#
# so the offset dq = K^-1 tau / (kp g) produces the torque tau on the three
# hip axes and nothing else (in the linear, co-contracted regime).
+ MyoWalkHip
  ro :muscles
  -> new(geom, frame, side)
    @joints = [geom.joint("hip_flexion_" + side), geom.joint("hip_adduction_" + side), geom.joint("hip_rotation_" + side)]
    @muscles = []
    seen = {}
    @joints.each ->(j)
      geom.crossing(j).each ->(m)
        if !seen.key?(m)
          seen[m] = true
          @muscles.push(m)
    @slopes = []
    k = (0...9).map -> ~0.0
    @muscles.each ->(m)
      sl = @joints.map ->(j) geom.contraction_slope(m, j)
      @slopes.push(sl)
      fmax = frame.at("muscle_fmax", m)
      rng = frame.at("muscle_range", m)
      w = fmax * rng
      a = 0
      while a < 3
        b = 0
        while b < 3
          k[a * 3 + b] = k[a * 3 + b] + w * sl[a] * sl[b]
          b += 1
        a += 1
    @kinv = invert3(k)

  -> invert3(k)
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

  # Add to `off` the contraction offsets that make the hip produce torques
  # (flexion, adduction, rotation) in N m under reflex gain kp * g.
  -> torque(off, tf, ta, tr, gain)
    ki = @kinv
    s = ~1.0 / gain
    d0 = (ki[0] * tf + ki[1] * ta + ki[2] * tr) * s
    d1 = (ki[3] * tf + ki[4] * ta + ki[5] * tr) * s
    d2 = (ki[6] * tf + ki[7] * ta + ki[8] * tr) * s
    u = 0
    while u < @muscles.size
      m = @muscles[u]
      sl = @slopes[u]
      off[m] = off[m] + sl[0] * d0 + sl[1] * d1 + sl[2] * d2
      u += 1
    off

+ MyoWalkSkill < Skill
  -> start(frame, ctl)
    @joints = ["hip_flexion", "hip_adduction", "hip_rotation", "knee_angle", "ankle_angle", "subtalar_angle", "mtp_angle"]
    read_params
    @mode = ~1.0
    @mode = @params["mode"] if @params.key?("mode")
    @v_des = @v_walk
    @have_goal = frame.has?("walk_goal")
    fwd0 = frame.vec("pelvis_fwd")
    @psi_f = Math.atan2(fwd0[1], fwd0[0])
    cvx = frame.at("com_vel", 0)
    cvy = frame.at("com_vel", 1)
    @psi_f = Math.atan2(cvy, cvx) if cvx * cvx + cvy * cvy > ~0.04
    @vxs = cvx
    @vys = cvy
    @psi_y = @psi_f
    @psi_m = @psi_f
    @load_l = frame.get("l_foot_contact")
    @load_r = frame.get("r_foot_contact")
    sense(frame)
    @psi_des = @psi
    @psi_hold = @psi
    read_goal(frame)
    @psi_goal = @psi_des
    @turning = false
    @tmode = {}
    @tmode["l"] = false
    @tmode["r"] = false
    bd = body
    @plan = {}
    @side_idx = {}
    @plantar = {}
    @abd = {}
    @ankle = {}
    @vas = {}
    @hipflex = {}
    @phase = {}
    @t_phase = {}
    @foot_x0 = {}
    @foot_y0 = {}
    @steps = 0
    @starting = false
    ["l", "r"].each ->(s)
      names = @joints.map ->(j) j + "_" + s
      init = names.map ->(nm) frame.q(bd, nm)
      @plan[s] = MyoWalkPlan.new(names, init)
      @side_idx[s] = side_mask("_" + s)
      @plantar[s] = names_mask(["soleus_", "gasmed_", "gaslat_"], s)
      @abd[s] = names_mask(["glmed1_", "glmed2_", "glmed3_", "glmin1_", "glmin2_", "glmin3_"], s)
      @vas[s] = names_mask(["vasint_", "vaslat_", "vasmed_"], s)
      @ankle[s] = body.geometry.crossing(body.geometry.joint("ankle_angle_" + s))
      @hipflex[s] = names_mask(["iliacus_", "psoas_", "recfem_", "sart_"], s)
      @phase[s] = :stance
      @t_phase[s] = frame.t
      @foot_x0[s] = foot_x(frame, s)
      @foot_y0[s] = foot_y(frame, s)
    ctl.reflex.set_gains(body.all, @kp, @kd)
    # ff_gain > 0 (a params flag, default off): the controller's internal-model
    # gravity + Coriolis feed-forward on every muscle (Controller#enable_feedforward)
    ff = ~0.0
    ff = @params["ff_gain"] if @params.key?("ff_gain")
    ctl.enable_feedforward(body.all, ff) if ff > ~0.0
    @hips = nil
    if frame.has?("muscle_fmax") && frame.has?("muscle_range")
      @hips = {}
      g = body.geometry
      @hips["l"] = MyoWalkHip.new(g, frame, "l")
      @hips["r"] = MyoWalkHip.new(g, frame, "r")
    if @mode < ~0.5
      @phase["l"] = :stand
      @phase["r"] = :stand
      mv = Movement.new("stand")
      mv.add(stand_chunk)
      ctl.add_track(Track.new("body", mv, body.all))
      return self
    if @mode > ~1.5 && @mode < ~2.5
      sg_setup(frame, ctl)
      return self
    if @mode > ~2.5
      # one-leg stance (a balance test): shift onto the left foot, lift the
      # right leg and hold both
      @starting = true
      lm = Movement.new("hold_l")
      lm.add(stance_chunk("l").hold_until(Latch.after(~1000.0)))
      rm = Movement.new("lift_r")
      rm.add(stance_chunk("r"))
      rm.add(lift_chunk("r").hold_until(Latch.after(~1000.0)))
      ctl.add_track(Track.new("l", lm, @side_idx["l"]))
      ctl.add_track(Track.new("r", rm, @side_idx["r"]))
      return self
    # walking: a leg whose heel is h_air above the other starts in swing; from quiet standing
    # the gait starts with a weight shift onto the left foot
    speed = Math.sqrt(@vf * @vf + @vl * @vl)
    @starting = speed < @v_still
    ["l", "r"].each ->(s)
      rise = frame.at(s + "_foot_pos", 2) - frame.at(other(s) + "_foot_pos", 2)
      up = rise > @h_air && !@starting
      ctl.add_track(Track.new(s, leg_movement(s, up), @side_idx[s]))
    self

  # One leg's gait loop, entered in swing (lift) when the foot is up.
  -> leg_movement(s, up)
    return turn_movement(s, up) if @turn_gait > ~0.5
    mv = Movement.new("walk_" + s)
    if up
      mv.add(lift_chunk(s))
      mv.add(reach_chunk(s))
      mv.add(stance_chunk(s))
      mv.add(push_chunk(s))
    else
      mv.add(stance_chunk(s))
      mv.add(push_chunk(s))
      mv.add(lift_chunk(s))
      mv.add(reach_chunk(s))
    mv.loop_from(0)
    mv

  # Both loops in one movement; every chunk names its successor at run time
  # (Chunk#branch), in the walking or the turning loop as @turning says.
  -> turn_movement(s, up)
    mv = Movement.new("walk_" + s)
    walk = [stance_chunk(s), push_chunk(s), lift_chunk(s), reach_chunk(s)]
    turn = [tstance_chunk(s), tpush_chunk(s), tlift_chunk(s), treach_chunk(s)]
    order = [0, 1, 2, 3]
    order = [2, 3, 0, 1] if up
    nexts = ["push", "lift", "reach", "stance"]
    order.each ->(k) mv.add(walk[k])
    turn.each ->(ch) mv.add(ch)
    k = 0
    while k < 4
      link_branch(walk[k], s, nexts[k])
      link_branch(turn[k], s, nexts[k])
      k += 1
    mv.loop_from(0)
    mv

  -> link_branch(ch, s, base)
    ch.branch(->(f, c) pick(s, base))

  -> pick(s, base)
    return s + "_t" + base if @turning
    s + "_" + base

  -> read_params
    # reflexes (lambda model): a = g (kp (c* - c) - kd cdot) + drive
    @kp = param("kp", ~6.0, ~2.0, ~16.0)
    @kd = param("kd", ~0.2, ~0.02, ~1.0)
    @spring = param("spring", ~0.04, ~0.01, ~0.12)
    # quiet stance
    @s_hip = param("s_hip", ~0.08, ~-0.1, ~0.4)
    @s_knee = param("s_knee", ~0.12, ~0.0, ~0.6)
    @s_ankle = param("s_ankle", ~0.05, ~-0.2, ~0.3)
    @s_add = param("s_add", ~0.0, ~-0.15, ~0.15)
    @s_stiff = param("s_stiff", ~0.04, ~0.0, ~0.3)
    @s_com = param("s_com", ~0.06, ~-0.04, ~0.12)
    @k_ank = param("k_ank", ~1.5, ~0.0, ~6.0)
    @d_ank = param("d_ank", ~0.4, ~0.0, ~2.0)
    @k_lat = param("k_lat", ~1.0, ~0.0, ~6.0)
    @d_lat = param("d_lat", ~0.3, ~0.0, ~2.0)
    # trunk (pelvis) servo
    @pitch_des = param("pitch_des", ~0.05, ~-0.15, ~0.3)
    @lean_v = param("lean_v", ~0.0, ~0.0, ~0.2)
    @t_kp = param("t_kp", ~1.5, ~0.0, ~5.0)
    @t_kd = param("t_kd", ~0.3, ~0.0, ~1.5)
    @r_kp = param("r_kp", ~2.0, ~0.0, ~6.0)
    @r_kd = param("r_kd", ~0.3, ~0.0, ~1.5)
    @y_kp = param("y_kp", ~2.0, ~0.0, ~5.0)
    @y_kd = param("y_kd", ~0.5, ~0.0, ~2.0)
    # the walking trunk servo as stance-hip torques (N m per rad, per rad/s)
    @tq_kp = param("tq_kp", ~400.0, ~0.0, ~1200.0)
    @tq_kd = param("tq_kd", ~50.0, ~0.0, ~200.0)
    @rq_kp = param("rq_kp", ~400.0, ~0.0, ~1200.0)
    @rq_kd = param("rq_kd", ~50.0, ~0.0, ~200.0)
    @yq_kp = param("yq_kp", ~120.0, ~0.0, ~500.0)
    @yq_kd = param("yq_kd", ~15.0, ~0.0, ~80.0)
    @hip_lead = param("hip_lead", ~0.03, ~0.0, ~0.15)
    @lead_add = param("lead_add", ~0.0, ~0.0, ~0.15)
    @lead_rot = param("lead_rot", ~0.0, ~0.0, ~0.15)
    @load_tau = param("load_tau", ~0.02, ~0.0, ~0.1)
    @grip = param("grip", ~0.2, ~0.02, ~0.6)
    # walking speed and steering
    @v_walk = param("v_walk", ~1.3, ~0.3, ~3.0)
    @turn_max = param("turn_max", ~0.35, ~0.05, ~0.8)
    @turn_rate_max = param("turn_rate_max", ~1.0, ~0.1, ~3.0)
    @lead_max = param("lead_max", ~0.3, ~0.0, ~0.8)
    @v_tau = param("v_tau", ~0.1, ~0.01, ~0.4)
    @yaw_tau = param("yaw_tau", ~0.4, ~0.01, ~2.0)
    @k_turn = param("k_turn", ~0.0, ~0.0, ~0.5)
    @k_slow = param("k_slow", ~0.0, ~0.0, ~1.0)
    @v_min = param("v_min", ~0.8, ~0.3, ~1.5)
    @rot_cancel = param("rot_cancel", ~1.0, ~0.0, ~1.0)
    @yaw_foot = param("yaw_foot", ~0.5, ~0.0, ~1.0)
    @v_still = param("v_still", ~0.25, ~0.05, ~0.6)
    @h_air = param("h_air", ~0.1, ~0.03, ~0.3)
    # stance leg (loading response to mid stance)
    @t_st = param("t_st", ~0.15, ~0.03, ~0.4)
    @k_st = param("k_st", ~0.2, ~0.0, ~0.6)
    @a_st = param("a_st", ~0.0, ~-0.3, ~0.35)
    @stiff_st = param("stiff_st", ~0.06, ~0.0, ~0.3)
    @g_st = param("g_st", ~1.0, ~0.4, ~2.0)
    @k_sta = param("k_sta", ~0.0, ~0.0, ~4.0)
    @flat = param("flat", ~1.0, ~0.0, ~1.0)
    @g_ank = param("g_ank", ~0.6, ~0.1, ~2.0)
    @sta_com = param("sta_com", ~0.05, ~-0.1, ~0.2)
    @k_stl = param("k_stl", ~0.0, ~-3.0, ~3.0)
    @d_push = param("d_push", ~0.08, ~-0.1, ~0.3)
    @unload = param("unload", ~0.15, ~0.02, ~0.5)
    # push-off (terminal stance / pre-swing)
    @t_push = param("t_push", ~0.12, ~0.03, ~0.3)
    @h_push = param("h_push", ~-0.2, ~-0.5, ~0.3)
    @k_push = param("k_push", ~0.25, ~0.0, ~1.2)
    @a_push = param("a_push", ~-0.35, ~-0.6, ~0.1)
    @drv_push = param("drv_push", ~0.3, ~0.0, ~1.0)
    @k_vpush = param("k_vpush", ~0.0, ~0.0, ~3.0)
    @g_push = param("g_push", ~1.0, ~0.3, ~2.0)
    @push_max = param("push_max", ~0.35, ~0.1, ~0.8)
    # tonic stance drives (gravity support), scaled by the leg's load share
    @drv_abd = param("drv_abd", ~0.1, ~0.0, ~0.6)
    @drv_vas = param("drv_vas", ~0.05, ~0.0, ~0.6)
    @ffb_vas = param("ffb_vas", ~0.0, ~0.0, ~1.5)
    @ffb_sol = param("ffb_sol", ~0.0, ~0.0, ~1.5)
    # swing
    @t_lift = param("t_lift", ~0.25, ~0.08, ~0.45)
    @psi_lift = param("psi_lift", ~0.6, ~0.0, ~1.2)
    @psi_go = param("psi_go", ~0.3, ~-0.2, ~0.7)
    @k_go = param("k_go", ~2.2, ~0.4, ~2.2)
    @k_lift = param("k_lift", ~1.05, ~0.3, ~1.8)
    @a_lift = param("a_lift", ~0.1, ~-0.3, ~0.4)
    @drv_lift = param("drv_lift", ~0.3, ~0.0, ~0.8)
    @t_drv_lift = param("t_drv_lift", ~0.12, ~0.0, ~0.3)
    @t_reach = param("t_reach", ~0.12, ~0.04, ~0.4)
    @psi_land = param("psi_land", ~0.45, ~0.0, ~0.9)
    @k_reach = param("k_reach", ~0.05, ~0.0, ~0.5)
    @a_reach = param("a_reach", ~0.1, ~-0.2, ~0.3)
    @reach_max = param("reach_max", ~0.5, ~0.2, ~1.2)
    @stiff_sw = param("stiff_sw", ~0.03, ~0.0, ~0.3)
    @g_sw = param("g_sw", ~0.8, ~0.2, ~1.5)
    @cv = param("cv", ~0.3, ~0.0, ~1.0)
    @cd = param("cd", ~0.0, ~-1.0, ~1.5)
    @ab_land = param("ab_land", ~0.03, ~-0.1, ~0.2)
    @cv_lat = param("cv_lat", ~0.3, ~0.0, ~1.2)
    @cd_lat = param("cd_lat", ~0.0, ~-1.0, ~2.0)
    @clear_h = param("clear_h", ~0.05, ~0.0, ~0.15)
    @k_clear = param("k_clear", ~4.0, ~0.0, ~15.0)
    # gait initiation from quiet standing
    @shift = param("shift", ~0.06, ~0.0, ~0.12)
    @k_shift = param("k_shift", ~2.0, ~0.0, ~6.0)
    @k_lean = param("k_lean", ~1.5, ~0.0, ~6.0)
    @d_lean = param("d_lean", ~0.08, ~0.0, ~0.2)
    # the reflex gait's tunables are declared in every mode (so practice sees them)
    sg_params
    turn_params
    stride_params
    self

  # Turning gait (turn_gait = 1; 0 keeps the original single loop): a second
  # loop of leg chunks (X_tstance -> X_tpush -> X_tlift -> X_treach) that every
  # chunk boundary can switch to through Chunk#branch while the goal heading is
  # more than th_on off the direction of motion (back below th_off: the
  # walking loop). It brakes (v_t), leads the travel frame hard toward the
  # goal (lead_max_t), servoes the pelvis at the goal heading itself through
  # the stance hip (yq_kp_t, torque capped at tr_max_t so the sole does not
  # spin), and lands each swing foot pre-rotated toward it (yaw_foot_t): a
  # step turn of short quick steps instead of a wide arc at speed.
  -> stride_params
    @stride = ~0.0
    @stride = @params["stride"] if @params.key?("stride")
    @lift_via = ~0.0
    @lift_via = @params["lift_via"] if @params.key?("lift_via")
    @d_trail = param("d_trail", ~-0.05, ~-0.3, ~0.3)
    @ds_min = param("ds_min", ~0.03, ~0.0, ~0.2)
    self

  -> turn_params
    @turn_gait = ~0.0
    @turn_gait = @params["turn_gait"] if @params.key?("turn_gait")
    @th_on = param("th_on", ~1.0, ~0.3, ~2.5)
    @th_off = param("th_off", ~0.4, ~0.1, ~1.5)
    @v_t = param("v_t", ~0.6, ~0.0, ~1.4)
    @lead_max_t = param("lead_max_t", ~0.5, ~0.0, ~1.6)
    @turn_rate_max_t = param("turn_rate_max_t", ~2.0, ~0.2, ~5.0)
    @turn_max_t = param("turn_max_t", ~0.6, ~0.1, ~1.2)
    @yq_kp_t = param("yq_kp_t", ~80.0, ~0.0, ~400.0)
    @yq_kd_t = param("yq_kd_t", ~10.0, ~0.0, ~80.0)
    @tr_max_t = param("tr_max_t", ~40.0, ~5.0, ~100.0)
    @hr_lim_t = param("hr_lim_t", ~0.4, ~0.1, ~0.65)
    @rot_cancel_t = param("rot_cancel_t", ~0.8, ~0.0, ~1.0)
    @yaw_foot_t = param("yaw_foot_t", ~0.5, ~0.0, ~1.2)
    @k_turn_t = param("k_turn_t", ~0.2, ~0.0, ~0.8)
    @cv_t = param("cv_t", ~0.3, ~0.0, ~1.2)
    @psi_land_t = param("psi_land_t", ~0.15, ~-0.1, ~0.7)
    @psi_lift_t = param("psi_lift_t", ~0.5, ~0.0, ~1.2)
    @k_st_t = param("k_st_t", ~0.33, ~0.0, ~0.7)
    @t_st_t = param("t_st_t", ~0.14, ~0.03, ~0.4)
    @st_max_t = param("st_max_t", ~0.35, ~0.1, ~1.0)
    @d_push_t = param("d_push_t", ~0.1, ~-0.15, ~0.3)
    @t_push_t = param("t_push_t", ~0.2, ~0.03, ~0.4)
    @drv_push_t = param("drv_push_t", ~0.2, ~0.0, ~1.0)
    @t_lift_t = param("t_lift_t", ~0.15, ~0.05, ~0.45)
    @t_reach_t = param("t_reach_t", ~0.15, ~0.04, ~0.4)
    self

  # ---- sensing ---------------------------------------------------------------

  # Heading frame: psi is the pelvis yaw, f the forward and l the leftward
  # unit vector on the floor. Pitch is + forward, roll + toward the left,
  # rates in the same senses.
  -> sense(f)
    fx = f.at("pelvis_fwd", 0)
    fy = f.at("pelvis_fwd", 1)
    @psi = Math.atan2(fy, fx)
    @fx = Math.cos(@psi)
    @fy = Math.sin(@psi)
    @lx = ~0.0 - @fy
    @ly = @fx
    ux = f.at("pelvis_up", 0)
    uy = f.at("pelvis_up", 1)
    uz = f.at("pelvis_up", 2)
    @pitch = Math.atan2(ux * @fx + uy * @fy, uz)
    @roll = Math.atan2(ux * @lx + uy * @ly, uz)
    wx = f.at("torso_angvel", 0)
    wy = f.at("torso_angvel", 1)
    @pitch_rate = wx * @lx + wy * @ly
    @roll_rate = ~0.0 - (wx * @fx + wy * @fy)
    @yaw_rate = f.at("torso_angvel", 2)
    # balance quantities live in the travel frame (heading psi_f, which
    # follows the desired heading at a limited turn rate), not the pelvis
    # frame: a pelvis that yaws must not make forward speed look sideways
    @tx = Math.cos(@psi_f)
    @ty = Math.sin(@psi_f)
    vx = f.at("com_vel", 0)
    vy = f.at("com_vel", 1)
    @vf = vx * @tx + vy * @ty
    @vl = vy * @tx - vx * @ty
    # foot loads (body weights), low-passed (contacts flicker)
    k = ~0.01 / (@load_tau + ~0.01)
    @load_l = @load_l + (f.get("l_foot_contact") - @load_l) * k
    @load_r = @load_r + (f.get("r_foot_contact") - @load_r) * k
    self

  # 1 when foot s carries at least `grip` body weights, 0 when it is off the ground.
  -> grounded(s)
    clamp(load(s) / @grip, ~0.0, ~1.0)

  # Share of the body's weight on leg s (0 when its foot is off the ground).
  -> share(s)
    lo = load(other(s))
    ls = load(s)
    clamp(ls / (ls + lo + ~0.05), ~0.0, ~1.0)

  -> load(s)
    return @load_l if s == "l"
    @load_r

  -> other(s)
    return "r" if s == "l"
    "l"

  # Foot centre (the calcn origin sits at the heel; the sole's centre of
  # pressure is about 8 cm ahead of it along the heading).
  -> foot_x(f, s)
    f.at(s + "_foot_pos", 0) + ~0.08 * @fx

  -> foot_y(f, s)
    f.at(s + "_foot_pos", 1) + ~0.08 * @fy

  # COM relative to a point, in the heading frame (forward, leftward).
  -> rel_f(f, x, y)
    (f.at("com_pos", 0) - x) * @tx + (f.at("com_pos", 1) - y) * @ty

  -> rel_l(f, x, y)
    (f.at("com_pos", 1) - y) * @tx - (f.at("com_pos", 0) - x) * @ty

  # +1 for the left side, -1 for the right: lateral quantities toward side s.
  -> sgn(s)
    return ~1.0 if s == "l"
    ~-1.0

  -> wrap(a)
    while a > ~3.141592653589793
      a = a - ~6.283185307179586
    while a < ~-3.141592653589793
      a = a + ~6.283185307179586
    a

  # Thigh angle forward of vertical in world frame (hip flexion minus pelvis pitch).
  -> thigh(f, s)
    f.q(body, jn("hip_flexion", s)) - @pitch

  # The task's goal: walk_goal = [mode, v_des, heading_des]. Skills that
  # steer by themselves (MyoChaseSkill) override `goal`.
  -> read_goal(f)
    return self if !@have_goal
    @mode = f.at("walk_goal", 0)
    @v_des = f.at("walk_goal", 1)
    @psi_des = f.at("walk_goal", 2)
    @psi_goal = @psi_des
    self

  -> goal(f)
    read_goal(f)

  -> before(frame, ctl)
    sense(frame)
    goal(frame)
    # slow down while the desired heading is far off the motion (tighter turns)
    if @k_slow > ~0.0
      off = wrap(@psi_des - @psi_m).abs / ~3.141592653589793
      @v_des = clamp(@v_des * (~1.0 - @k_slow * off), @v_min, @v_des)
    if @mode > ~0.5
      # the travel frame leads the direction of motion (the smoothed COM
      # velocity, or the pelvis heading when nearly still) toward the desired
      # heading by at most lead_max: lateral placement then bends the path at
      # a bounded rate, and the frame can never run away from the motion
      k = ctl.dt / (@v_tau + ctl.dt)
      @vxs = @vxs + (frame.at("com_vel", 0) - @vxs) * k
      @vys = @vys + (frame.at("com_vel", 1) - @vys) * k
      ref = @psi
      ref = Math.atan2(@vys, @vxs) if @vxs * @vxs + @vys * @vys > ~0.09
      @psi_m = ref
      lead = @lead_max
      rate = @turn_rate_max
      aim = @psi_des
      if @turn_gait > ~0.5 && @mode < ~1.5
        # the turning loop while the goal is far off the motion (hysteresis)
        err = wrap(@psi_goal - ref).abs
        @turning = true if err > @th_on
        @turning = false if err < @th_off
        if @turning
          lead = @lead_max_t
          rate = @turn_rate_max_t
          aim = @psi_goal
          @v_des = @v_t if @v_t < @v_des
      goal = wrap(ref + clamp(wrap(aim - ref), ~0.0 - lead, lead))
      step = rate * ctl.dt
      @psi_f = wrap(@psi_f + clamp(wrap(goal - @psi_f), ~0.0 - step, step))
      # the pelvis heading target: the travel frame filtered over yaw_tau, so
      # the yaw servo does not chase the step-to-step sway of the COM velocity
      ky = ctl.dt / (@yaw_tau + ctl.dt)
      @psi_y = wrap(@psi_y + wrap(@psi_f - @psi_y) * ky)
    sg_update(frame) if @mode > ~1.5 && @mode < ~2.5
    self

  # ---- muscle groups ---------------------------------------------------------

  -> side_mask(suffix)
    out = []
    n = body.size
    i = 0
    while i < n
      out.push(i) if body.muscle(i).name.ends_with?(suffix)
      i += 1
    out

  -> names_mask(prefixes, s)
    out = []
    bd = body
    prefixes.each ->(p)
      nm = p + s
      out.push(bd.index(nm)) if bd.has?(nm)
    out

  -> jn(base, s)
    base + "_" + s

  # ---- poses and chunks ------------------------------------------------------

  # Goals for one leg: a flat [joint, angle, ...] list the plan and the Pose share.
  -> leg_goals(s, hip, add, rot, knee, ankle)
    out = []
    out.push(jn("hip_flexion", s))
    out.push(hip)
    out.push(jn("hip_adduction", s))
    out.push(add)
    out.push(jn("hip_rotation", s))
    out.push(rot)
    out.push(jn("knee_angle", s))
    out.push(knee)
    out.push(jn("ankle_angle", s))
    out.push(ankle)
    out.push(jn("subtalar_angle", s))
    out.push(~0.0)
    out.push(jn("mtp_angle", s))
    out.push(~0.0)
    out

  -> pose_of(goals, stiff)
    p = Pose.new
    i = 0
    while i < goals.size
      p.set(goals[i], goals[i + 1], stiff)
      i += 2
    p

  # A leg chunk whose goal is `goals`; on entry the leg's plan and phase update.
  -> leg_chunk(s, name, dur, goals, stiff, phase, easing)
    ch = Chunk.new(s + "_" + name, dur).pose(pose_of(goals, stiff)).ease(easing)
    ch.on_enter(->(f, c) enter(f, s, ch, goals, phase))
    ch.correct(->(f, c) leg_correction(f, c, s), @spring)
    ch

  -> enter(f, s, ch, goals, phase)
    @plan[s].enter(f.t, ch.duration, goals, ch.easing)
    @tmode[s] = ch.name.starts_with?(s + "_t")
    @steps += 1 if phase == :stance && @phase[s] == :reach
    @starting = false if phase == :lift
    @phase[s] = phase
    @t_phase[s] = f.t
    @foot_x0[other(s)] = foot_x(f, other(s))
    @foot_y0[other(s)] = foot_y(f, other(s))
    self

  # Stance (loading response to mid stance): soft knee, ankle near neutral;
  # the hip is the trunk servo (its pose goal is irrelevant: the correction
  # replaces it with the measured angle plus the servo).
  -> stance_chunk(s)
    g = leg_goals(s, ~0.0, ~0.0, ~0.0, @k_st, @a_st)
    ch = leg_chunk(s, "stance", @t_st, g, @stiff_st, :stance, :min_jerk)
    ahead = Latch.test("ahead:" + s, ->(f, e, c) com_ahead?(f, s))
    free = Latch.test("unloaded:" + s, ->(f, e, c) unloaded?(s))
    if @stride > ~0.5
      trail = Latch.test("trail:" + s, ->(f, e, c) trailing?(f, s))
      ch.hold_until(Latch.any([ahead, free, trail]).after_min(~0.08))
      return ch
    ch.hold_until(Latch.any([ahead, free]).after_min(~0.08))
    ch

  # Push-off starts once the COM is d_push ahead of this foot, and never
  # while the other leg is itself pushing off (walking has no flight).
  -> com_ahead?(f, s)
    return false if @starting || @phase[other(s)] == :push
    rel_f(f, foot_x(f, s), foot_y(f, s)) > @d_push

  # Long strides (stride = 1): the trailing leg also pushes off once the
  # leading foot has landed and carries weight (ds_min s into its stance) with
  # the COM at least d_trail ahead of this foot: the push-off of human walking
  # spans double support, and a long step that brakes the COM short of d_push
  # must not leave both legs standing (the gait stalls and topples back).
  -> trailing?(f, s)
    o = other(s)
    return false if @starting || @phase[o] != :stance
    return false if f.t - @t_phase[o] < @ds_min || load(o) < @grip
    rel_f(f, foot_x(f, s), foot_y(f, s)) > @d_trail

  # Gait initiation only: the weight shift has taken the right foot's load
  # (the left foot unloads briefly first, as the centre of pressure moves
  # toward the right foot to push the COM left: it must not take a step).
  -> unloaded?(s)
    @starting && s == "r" && load(s) < @unload && load(other(s)) > ~0.5

  # Push-off: plantarflex (with a drive burst) and start folding the knee.
  -> push_chunk(s)
    g = leg_goals(s, @h_push + @pitch_des, ~0.0, ~0.0, @k_push, @a_push)
    ch = leg_chunk(s, "push", @t_push, g, @stiff_st, :push, :min_jerk)
    ch.hold_until(Latch.release(s + "_foot", ~0.03).after_min(~0.03), @push_max)
    ch

  # Early swing: the thigh drives forward (cubic-out: the equilibrium point
  # jumps ahead, a ballistic start), heel tucked, toe up.
  -> lift_chunk(s)
    g = leg_goals(s, @psi_lift + @pitch_des, ~0.0, ~0.0, @k_lift, @a_lift)
    ch = leg_chunk(s, "lift", @t_lift, g, @stiff_sw, :lift, :cubic_out)
    # lift_via = 1: the lift posture is a via point, so the swing flows into
    # the reach (knee extending, thigh still flexing) without stopping
    ch.via if @lift_via > ~0.5
    fwd = Latch.test("thigh:" + s, ->(f, e, c) thigh(f, s) > @psi_go)
    tuck = Latch.test("knee:" + s, ->(f, e, c) f.q(body, jn("knee_angle", s)) > @k_go)
    ch.hold_until(Latch.any([fwd, tuck, Latch.after(@t_lift)]).after_min(~0.03))
    ch

  # Late swing: the thigh sweeps to its landing angle (placed by the
  # corrections), the knee opens.
  -> reach_chunk(s)
    g = leg_goals(s, @psi_land + @pitch_des, ~0.0, ~0.0, @k_reach, @a_reach)
    ch = leg_chunk(s, "reach", @t_reach, g, @stiff_sw, :reach, :cubic_out)
    ch.hold_until(Latch.contact(s + "_foot", ~0.1).after_min(~0.05), @reach_max)
    ch

  # ---- the turning loop (turn_gait = 1) ---------------------------------------
  # The same phases with their own poses and timing. Stance also ends after
  # st_max_t once the other foot carries weight: at low speed the COM may
  # never get d_push_t ahead of the foot, and a turn in place still needs steps.
  -> tstance_chunk(s)
    g = leg_goals(s, ~0.0, ~0.0, ~0.0, @k_st_t, @a_st)
    ch = leg_chunk(s, "tstance", @t_st_t, g, @stiff_st, :stance, :min_jerk)
    ahead = Latch.test("ahead_t:" + s, ->(f, e, c) com_ahead_t?(f, s))
    late = Latch.test("late_t:" + s, ->(f, e, c) stance_late?(s, e))
    ch.hold_until(Latch.any([ahead, late]).after_min(~0.08))
    ch

  -> com_ahead_t?(f, s)
    return false if @phase[other(s)] == :push
    rel_f(f, foot_x(f, s), foot_y(f, s)) > @d_push_t

  -> stance_late?(s, e)
    return false if @phase[other(s)] == :push || e < @st_max_t
    load(other(s)) > @grip

  -> tpush_chunk(s)
    g = leg_goals(s, @h_push + @pitch_des, ~0.0, ~0.0, @k_push, @a_push)
    ch = leg_chunk(s, "tpush", @t_push_t, g, @stiff_st, :push, :min_jerk)
    ch.hold_until(Latch.release(s + "_foot", ~0.03).after_min(~0.03), @push_max)
    ch

  -> tlift_chunk(s)
    g = leg_goals(s, @psi_lift_t + @pitch_des, ~0.0, ~0.0, @k_lift, @a_lift)
    ch = leg_chunk(s, "tlift", @t_lift_t, g, @stiff_sw, :lift, :cubic_out)
    fwd = Latch.test("thigh_t:" + s, ->(f, e, c) thigh(f, s) > @psi_go)
    tuck = Latch.test("knee_t:" + s, ->(f, e, c) f.q(body, jn("knee_angle", s)) > @k_go)
    ch.hold_until(Latch.any([fwd, tuck, Latch.after(@t_lift_t)]).after_min(~0.03))
    ch

  -> treach_chunk(s)
    g = leg_goals(s, @psi_land_t + @pitch_des, ~0.0, ~0.0, @k_reach, @a_reach)
    ch = leg_chunk(s, "treach", @t_reach_t, g, @stiff_sw, :reach, :cubic_out)
    ch.hold_until(Latch.contact(s + "_foot", ~0.1).after_min(~0.05), @reach_max)
    ch

  -> stand_goals
    g = leg_goals("l", @s_hip, @s_add, ~0.0, @s_knee, @s_ankle)
    leg_goals("r", @s_hip, @s_add, ~0.0, @s_knee, @s_ankle).each ->(x) g.push(x)
    g

  -> stand_chunk
    goals = stand_goals
    ch = Chunk.new("stand", ~0.6).pose(pose_of(goals, @s_stiff))
    ch.hold_until(Latch.after(~1000.0))
    ch.correct(->(f, c) stand_correction(f), @spring)
    ch

  # ---- gains and drives ------------------------------------------------------

  -> after(frame, ctl)
    return self if @mode < ~0.5
    return sg_stim(frame, ctl) if @mode > ~1.5 && @mode < ~2.5
    ["l", "r"].each ->(s)
      ph = @phase[s]
      e = frame.t - @t_phase[s]
      g = @g_sw
      g = @g_st if ph == :stance
      g = @g_push if ph == :push
      @side_idx[s].each ->(i) ctl.set_gain(i, g)
      if ph == :stance
        @ankle[s].each ->(i) ctl.set_gain(i, @g_ank)
      if ph == :stance || ph == :push
        w = share(s)
        @abd[s].each ->(i) ctl.add_drive(i, w * @drv_abd)
        @vas[s].each ->(i) ctl.add_drive(i, w * @drv_vas) if ph == :stance
        # positive force feedback (Geyer's stance reflex): the loaded
        # extensors excite themselves in proportion to their own force, so
        # the stance leg is a load-adaptive spring
        fr = frame
        if ph == :stance && @ffb_vas > ~0.0
          @vas[s].each ->(i) ctl.add_drive(i, @ffb_vas * fr.force(i))
        if @ffb_sol > ~0.0
          @plantar[s].each ->(i) ctl.add_drive(i, @ffb_sol * fr.force(i))
      if ph == :push
        # push harder when slower than v_des, softer when faster (speed loop)
        sp = clamp(~1.0 + @k_vpush * (@v_des - @vf), ~0.0, ~2.0)
        dp = @drv_push
        dp = @drv_push_t if @tmode[s]
        @plantar[s].each ->(i) ctl.add_drive(i, dp * sp)
      if ph == :lift && e < @t_drv_lift
        @hipflex[s].each ->(i) ctl.add_drive(i, @drv_lift)
    self

  # ---- Song & Geyer reflex gait (mode 2) -------------------------------------

  -> sgp(name, scale, offset, lo, hi)
    param("sg_" + name, ~1.0, lo, hi) * scale + offset

  -> sg_params
    d = ~0.017453292519943295
    @sg = {}
    @sg["theta_tgt"] = sgp("theta_tgt", ~10.0 * d, ~0.0, ~-1.0, ~3.0)
    @sg["c0"] = sgp("c0", ~20.0 * d, ~55.0 * d, ~-1.0, ~3.0)
    @sg["cv"] = sgp("cv", ~2.0 * d, ~0.0, ~0.0, ~20.0)
    @sg["alpha_delta"] = sgp("alpha_delta", ~5.0 * d, ~0.0, ~-1.0, ~3.0)
    @sg["knee_sw_tgt"] = sgp("knee_sw_tgt", ~20.0 * d, ~120.0 * d, ~-1.0, ~2.0)
    @sg["knee_tgt"] = sgp("knee_tgt", ~15.0 * d, ~160.0 * d, ~-1.0, ~1.3)
    @sg["knee_off_st"] = sgp("knee_off_st", ~10.0 * d, ~165.0 * d, ~-1.0, ~1.5)
    @sg["ankle_tgt"] = sgp("ankle_tgt", ~20.0 * d, ~60.0 * d, ~-1.0, ~2.0)
    @sg["HFL_3_PG"] = sgp("hfl_3_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["HFL_3_DG"] = sgp("hfl_3_dg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["HFL_6_PG"] = sgp("hfl_6_pg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["HFL_6_DG"] = sgp("hfl_6_dg", ~0.1, ~0.0, ~0.0, ~3.0)
    @sg["HFL_10_PG"] = sgp("hfl_10_pg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["GLU_3_PG"] = sgp("glu_3_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["GLU_3_DG"] = sgp("glu_3_dg", ~0.5, ~0.0, ~0.0, ~3.0)
    @sg["GLU_6_PG"] = sgp("glu_6_pg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["GLU_6_DG"] = sgp("glu_6_dg", ~0.1, ~0.0, ~0.0, ~3.0)
    @sg["GLU_10_PG"] = sgp("glu_10_pg", ~0.5, ~0.0, ~0.0, ~3.0)
    @sg["HAM_3_GLU"] = sgp("ham_3_glu", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["HAM_9_PG"] = sgp("ham_9_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["RF_1_FG"] = sgp("rf_1_fg", ~0.3, ~0.0, ~0.0, ~3.0)
    @sg["RF_8_DG_knee"] = sgp("rf_8_dg_knee", ~0.1, ~0.0, ~0.0, ~3.0)
    @sg["VAS_1_FG"] = sgp("vas_1_fg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["VAS_2_PG"] = sgp("vas_2_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["VAS_10_PG"] = sgp("vas_10_pg", ~0.3, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_2_PG"] = sgp("bfsh_2_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_7_DG_alpha"] = sgp("bfsh_7_dg_alpha", ~0.2, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_7_PG"] = sgp("bfsh_7_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_8_DG"] = sgp("bfsh_8_dg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_8_PG"] = sgp("bfsh_8_pg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_9_G_HAM"] = sgp("bfsh_9_g_ham", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_9_HAM0"] = sgp("bfsh_9_ham0", ~0.3, ~0.0, ~0.0, ~3.0)
    @sg["BFSH_10_PG"] = sgp("bfsh_10_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["GAS_2_FG"] = sgp("gas_2_fg", ~1.2, ~0.0, ~0.0, ~3.0)
    @sg["SOL_1_FG"] = sgp("sol_1_fg", ~1.2, ~0.0, ~0.0, ~3.0)
    @sg["TA_5_PG"] = sgp("ta_5_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["TA_5_G_SOL"] = sgp("ta_5_g_sol", ~0.5, ~0.0, ~0.0, ~3.0)
    @sg["theta_tgt_f"] = sgp("theta_tgt_f", ~5.0 * d, ~0.0, ~-2.0, ~2.0)
    @sg["c0_f"] = sgp("c0_f", ~20.0 * d, ~60.0 * d, ~-1.0, ~2.0)
    @sg["cv_f"] = sgp("cv_f", ~10.0 * d, ~0.0, ~0.0, ~10.0)
    @sg["HAB_3_PG"] = sgp("hab_3_pg", ~10.0, ~0.0, ~0.0, ~3.0)
    @sg["HAB_3_DG"] = sgp("hab_3_dg", ~1.0, ~0.0, ~0.0, ~3.0)
    @sg["HAB_6_PG"] = sgp("hab_6_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["HAD_3_PG"] = sgp("had_3_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @sg["HAD_3_DG"] = sgp("had_3_dg", ~0.3, ~0.0, ~0.0, ~3.0)
    @sg["HAD_6_PG"] = sgp("had_6_pg", ~2.0, ~0.0, ~0.0, ~3.0)
    @g_sg = param("g_sg", ~0.0, ~0.0, ~1.0)
    @sg_yaw = param("sg_yaw", ~0.0, ~0.0, ~2.0)
    @sg_contact = param("sg_contact", ~0.1, ~0.02, ~0.4)
    self

  # Muscle groups of the MyoSuite reflex interface; muscles in no group get
  # the resting 0.01.
  -> sg_groups(s)
    g = {}
    g["HAB"] = names_mask(["piri_", "sart_", "glmed1_", "glmed2_", "glmin1_", "glmin2_", "glmin3_"], s)
    g["HAD"] = names_mask(["addbrev_", "addlong_", "addmagDist_", "addmagIsch_", "addmagMid_", "addmagProx_", "grac_"], s)
    g["HFL"] = names_mask(["psoas_", "iliacus_"], s)
    g["GLU"] = names_mask(["glmax1_", "glmax2_", "glmax3_", "glmed3_"], s)
    g["HAM"] = names_mask(["semimem_", "semiten_", "bflh_"], s)
    g["RF"] = names_mask(["recfem_"], s)
    g["VAS"] = names_mask(["vasint_", "vaslat_", "vasmed_"], s)
    g["BFSH"] = names_mask(["bfsh_"], s)
    g["GAS"] = names_mask(["gaslat_", "gasmed_"], s)
    g["SOL"] = names_mask(["soleus_", "perbrev_", "perlong_", "tibpost_"], s)
    g["TA"] = names_mask(["tibant_"], s)
    g

  -> sg_setup(frame, ctl)
    @grp = {}
    @st = {}
    @csw = {}
    @sw0 = {}
    @stst = {}
    @swf = {}
    @flex_k = {}
    @hold_k = {}
    @stop_l = {}
    @hold_l = {}
    @swing_init = {}
    @sgs = {}
    ["l", "r"].each ->(s)
      @grp[s] = sg_groups(s)
      rise = frame.at(s + "_foot_pos", 2) - frame.at(other(s) + "_foot_pos", 2)
      up = rise > @h_air
      @st[s] = ~1.0
      @swf[s] = ~0.0
      if up
        @st[s] = ~0.0
        @swf[s] = ~1.0
      @flex_k[s] = @swf[s]
      @hold_k[s] = ~0.0
      @stop_l[s] = ~0.0
      @hold_l[s] = ~0.0
      @csw[s] = ~0.0
      @sw0[s] = ~0.0
      @stst[s] = ~0.0
      @swing_init[s] = ~0.0
      @phase[s] = :stance
      @phase[s] = :swing if up
      mv = Movement.new("sg_" + s)
      if up
        mv.add(sg_swing_chunk(s))
        mv.add(sg_stance_chunk(s))
      else
        mv.add(sg_stance_chunk(s))
        mv.add(sg_swing_chunk(s))
      mv.loop_from(0)
      ctl.add_track(Track.new(s, mv, @side_idx[s]))
    sg_update(frame)
    self

  -> sg_stance_chunk(s)
    ch = Chunk.new(s + "_sg_stance", ~0.05)
    ch.hold_until(Latch.release(s + "_foot", @sg_contact).after_min(~0.03))
    ch.on_enter(->(f, c) sg_enter(f, s, :stance))
    ch

  -> sg_swing_chunk(s)
    ch = Chunk.new(s + "_sg_swing", ~0.05)
    ch.hold_until(Latch.contact(s + "_foot", @sg_contact).after_min(~0.05))
    ch.on_enter(->(f, c) sg_enter(f, s, :swing))
    ch

  # Touchdown starts stance control; liftoff starts swing control with the
  # knee flexing.
  -> sg_enter(f, s, phase)
    @steps += 1 if phase == :stance && @phase[s] == :swing
    @phase[s] = phase
    @t_phase[s] = f.t
    if phase == :stance
      @st[s] = ~1.0
      @swf[s] = ~0.0
      @flex_k[s] = ~0.0
      @hold_k[s] = ~0.0
      @stop_l[s] = ~0.0
      @hold_l[s] = ~0.0
    else
      @st[s] = ~0.0
      @csw[s] = ~0.0
      @sw0[s] = ~0.0
      @stst[s] = ~0.0
      @swf[s] = ~1.0
      @flex_k[s] = ~1.0
    self

  # Sensor values in Song's convention and the "brain" targets.
  -> sg_update(f)
    hp = ~1.5707963267948966
    ["l", "r"].each ->(s)
      e = {}
      hip = f.q(body, jn("hip_flexion", s))
      knee = f.q(body, jn("knee_angle", s))
      e["phi_hip"] = ~3.141592653589793 - hip
      e["phi_knee"] = ~3.141592653589793 - knee
      e["phi_ankle"] = hp - f.q(body, jn("ankle_angle", s))
      e["dphi_knee"] = ~0.0 - f.qd(body, jn("knee_angle", s))
      e["alpha"] = hp - hip + ~0.5 * knee
      e["dalpha"] = ~0.0 - f.qd(body, jn("hip_flexion", s)) + ~0.5 * f.qd(body, jn("knee_angle", s))
      e["alpha_f"] = hp + f.q(body, jn("hip_adduction", s))
      sg = sgn(s)
      e["theta_f"] = sg * @roll
      e["dtheta_f"] = sg * @roll_rate
      e["alpha_tgt"] = @sg["c0"] - @sg["cv"] * @vf - @pitch
      e["alpha_tgt_f"] = @sg["c0_f"] - sg * @sg["cv_f"] * @vl - e["theta_f"]
      e["hip_tgt"] = e["alpha_tgt"] + ~0.5 * @sg["knee_tgt"]
      e["load"] = load(s)
      e["load_c"] = load(other(s))
      e["contact_c"] = ~0.0
      e["contact_c"] = ~1.0 if load(other(s)) > @sg_contact
      @sgs[s] = e
    # swing initiation: with both feet down, the leg further behind its target swings
    @swing_init["l"] = ~0.0
    @swing_init["r"] = ~0.0
    if load("l") > @sg_contact && load("r") > @sg_contact
      dl = @sgs["l"]["alpha"] - @sgs["l"]["alpha_tgt"]
      dr = @sgs["r"]["alpha"] - @sgs["r"]["alpha_tgt"]
      if dr > dl
        @swing_init["r"] = ~1.0
      else
        @swing_init["l"] = ~1.0
    ["l", "r"].each ->(s)
      e = @sgs[s]
      if @st[s] > ~0.5
        @csw[s] = ~1.0 - e["contact_c"]
        @sw0[s] = @swing_init[s]
        @stst[s] = ~1.0 - @sw0[s]
      if @swf[s] > ~0.5
        if @flex_k[s] > ~0.5
          if e["phi_knee"] < @sg["knee_sw_tgt"]
            @flex_k[s] = ~0.0
            @hold_k[s] = ~1.0
        else
          @hold_k[s] = ~0.0 if @hold_k[s] > ~0.5 && e["alpha"] < e["alpha_tgt"]
          @stop_l[s] = ~1.0 if e["alpha"] < e["alpha_tgt"] + @sg["alpha_delta"]
          @hold_l[s] = ~1.0 if @stop_l[s] > ~0.5 && e["dalpha"] > ~0.0
    self

  -> relu(x)
    return ~0.0 if x < ~0.0
    x

  -> group_force(s, name)
    idx = @grp[s][name]
    return ~0.0 if idx.size == 0
    tot = ~0.0
    fr = @frame
    idx.each ->(i) tot = tot + fr.force(i)
    tot / idx.size

  # The spinal laws of LocoCtrl.spinal_control_leg, one leg at a time.
  -> sg_stim(frame, ctl)
    @frame = frame
    ["l", "r"].each ->(s)
      e = @sgs[s]
      c = @sg
      st = @st[s]
      sw = @swf[s]
      sw0 = @sw0[s]
      stst = @stst[s]
      ld = e["load"]
      lc = e["load_c"]
      th = @pitch
      dth = @pitch_rate
      thf = e["theta_f"]
      dthf = e["dtheta_f"]
      a = e["alpha"]
      at = e["alpha_tgt"]
      da = e["dalpha"]
      pk = e["phi_knee"]
      pre = ~0.01
      stim = {}
      hab3 = st * ld * relu(~0.0 - c["HAB_3_PG"] * (thf - c["theta_tgt_f"]) - c["HAB_3_DG"] * dthf)
      hab6 = (sw0 * lc + sw) * relu(c["HAB_6_PG"] * (e["alpha_f"] - e["alpha_tgt_f"]))
      stim["HAB"] = pre + hab3 + hab6
      had3 = st * ld * relu(c["HAD_3_PG"] * (thf - c["theta_tgt_f"]) + c["HAD_3_DG"] * dthf)
      had6 = (sw0 * lc + sw) * relu(~0.0 - c["HAD_6_PG"] * (e["alpha_f"] - e["alpha_tgt_f"]))
      stim["HAD"] = pre + had3 + had6
      hfl3 = st * ld * relu(~0.0 - c["HFL_3_PG"] * (th - c["theta_tgt"]) - c["HFL_3_DG"] * dth)
      hfl6 = (sw0 * lc + sw) * relu(c["HFL_6_PG"] * (a - at) + c["HFL_6_DG"] * da)
      hfl10 = @hold_l[s] * relu(c["HFL_10_PG"] * (e["phi_hip"] - e["hip_tgt"]))
      stim["HFL"] = pre + hfl3 + hfl6 + hfl10
      glu3 = st * ld * relu(c["GLU_3_PG"] * (th - c["theta_tgt"]) + c["GLU_3_DG"] * dth)
      glu6 = (sw0 * lc + sw) * relu(~0.0 - c["GLU_6_PG"] * (a - at) - c["GLU_6_DG"] * da)
      glu10 = @hold_l[s] * relu(~0.0 - c["GLU_10_PG"] * (e["phi_hip"] - e["hip_tgt"]))
      stim["GLU"] = pre + glu3 + glu6 + glu10
      ham9 = @stop_l[s] * relu(~0.0 - c["HAM_9_PG"] * (a - (at + c["alpha_delta"])))
      stim["HAM"] = pre + c["HAM_3_GLU"] * glu3 + ham9
      supp = stst + sw0 * (~1.0 - lc)
      rf1 = supp * relu(c["RF_1_FG"] * group_force(s, "RF"))
      rf8 = @hold_k[s] * relu(~0.0 - c["RF_8_DG_knee"] * e["dphi_knee"])
      stim["RF"] = pre + rf1 + rf8
      vas1 = supp * relu(c["VAS_1_FG"] * group_force(s, "VAS"))
      vas2 = ~0.0 - supp * relu(c["VAS_2_PG"] * (pk - c["knee_off_st"]))
      vas10 = @hold_l[s] * relu(~0.0 - c["VAS_10_PG"] * (pk - c["knee_tgt"]))
      stim["VAS"] = pre + vas1 + vas2 + vas10
      bf2 = supp * relu(c["BFSH_2_PG"] * (pk - c["knee_off_st"]))
      bf7 = (sw0 * lc + @flex_k[s]) * relu(~0.0 - c["BFSH_7_DG_alpha"] * da + c["BFSH_7_PG"] * (pk - c["knee_sw_tgt"]))
      bf8 = @hold_k[s] * relu(c["BFSH_8_DG"] * e["dphi_knee"] * c["BFSH_8_PG"] * (a - at))
      bf9 = relu(c["BFSH_9_G_HAM"] * (ham9 - c["BFSH_9_HAM0"]))
      bf10 = @hold_l[s] * relu(c["BFSH_10_PG"] * (pk - c["knee_tgt"]))
      stim["BFSH"] = pre + bf2 + bf7 + bf8 + bf9 + bf10
      stim["GAS"] = pre + st * relu(c["GAS_2_FG"] * group_force(s, "GAS"))
      sol1 = st * relu(c["SOL_1_FG"] * group_force(s, "SOL"))
      stim["SOL"] = pre + sol1
      ta5 = relu(c["TA_5_PG"] * (e["phi_ankle"] - c["ankle_tgt"]))
      stim["TA"] = pre + ta5 - st * relu(c["TA_5_G_SOL"] * sol1)
      g = @g_sg
      @side_idx[s].each ->(i)
        ctl.set_gain(i, g)
        ctl.add_drive(i, pre)
      ["HAB", "HAD", "HFL", "GLU", "HAM", "RF", "VAS", "BFSH", "GAS", "SOL", "TA"].each ->(name)
        vv = clamp(stim[name], ~0.01, ~1.0) - pre
        @grp[s][name].each ->(i) ctl.add_drive(i, vv)
      sg_yaw_drive(frame, ctl, s) if @sg_yaw > ~0.0 && @hips != nil && st > ~0.5
    self

  # Heading hold the original lacks: the stance hip's rotation torque
  # (yq_kp / yq_kd on the travel-frame heading error, scaled by sg_yaw and
  # the load share) mapped to muscle drives through MyoWalkHip.
  -> sg_yaw_drive(frame, ctl, s)
    heading = clamp(wrap(@psi_y - @psi), ~0.0 - @turn_max, @turn_max)
    tr = sgn(s) * (@yq_kp * heading - @yq_kd * @yaw_rate) * @sg_yaw * share(s)
    off = zeros
    @hips[s].torque(off, ~0.0, ~0.0, tr, ~1.0)
    @hips[s].muscles.each ->(i) ctl.add_drive(i, relu(off[i]))
    self

  # ---- corrections -----------------------------------------------------------

  -> leg_correction(f, ctl, s)
    off = zeros
    ph = @phase[s]
    sg = sgn(s)
    tm = @tmode[s]
    heading = clamp(wrap(@psi_y - @psi), ~0.0 - @turn_max, @turn_max)
    # turning loop: the pelvis and the swing foot aim at the goal heading itself
    heading = clamp(wrap(@psi_goal - @psi), ~0.0 - @turn_max_t, @turn_max_t) if tm
    # a loaded leg (stance or push) servoes the trunk in proportion to the
    # weight it carries; the rest of its hip holds the thigh in world frame
    w = ~0.0
    w = share(s) if ph == :stance || ph == :push
    if w > ~0.0
      trunk_servo(f, off, s, w, heading)
    # a foot off the ground holds its thigh in world frame (a planted one
    # must not: rotating it with the pelvis would push the wrong way)
    air = ~1.0
    air = ~1.0 - grounded(s) if ph == :stance || ph == :push
    joint_offset(off, jn("hip_flexion", s), air * (@pitch - @pitch_des))
    if ph == :stance
      return stance_extras(f, off, s, air)
    if ph == :push
      joint_offset(off, jn("hip_adduction", s), ~0.0 - air * sg * @roll)
      return off
    # swing: the landing angle is placed by the COM (relative to the stance
    # foot where it was when this leg lifted off)
    o = other(s)
    d_f = rel_f(f, @foot_x0[o], @foot_y0[o])
    d_l = sg * rel_l(f, @foot_x0[o], @foot_y0[o])
    v_l = sg * @vl
    cv = @cv
    cv = @cv_t if tm
    place = cv * (@vf - @v_des) + @cd * d_f
    place = place * ~0.5 if ph == :lift
    ab = @ab_land + @cv_lat * v_l + @cd_lat * d_l
    # turning: the foot lands toward the outside of the desired turn (the
    # centripetal push), in proportion to how far the motion must still turn
    if tm
      ab = ab - sg * @k_turn_t * clamp(wrap(@psi_goal - @psi_m), ~0.0 - @turn_max_t, @turn_max_t)
    else
      ab = ab - sg * @k_turn * clamp(wrap(@psi_des - @psi_m), ~0.0 - @turn_max, @turn_max)
    # the thigh's direction is placed in the travel frame (forward angle
    # base + place, outward angle ab) and rotated into the pelvis frame by the
    # heading error h, so a yawed pelvis still puts the foot where the COM needs it
    base = @psi_land
    base = @psi_lift if ph == :lift
    if tm
      base = @psi_land_t
      base = @psi_lift_t if ph == :lift
    h = wrap(@psi_f - @psi)
    ch = Math.cos(h)
    sh = Math.sin(h)
    af = base + place
    al = sg * ab
    pf = af * ch - al * sh
    pl = af * sh + al * ch
    joint_offset(off, jn("hip_flexion", s), pf - base)
    # world adduction = -sg * (leftward angle); joint adduction = world - sg * roll
    joint_offset(off, jn("hip_adduction", s), ~0.0 - sg * pl - sg * @roll)
    # foot yaw toward the desired heading (internal rotation turns the foot medially)
    yf = @yaw_foot
    yf = @yaw_foot_t if tm
    joint_offset(off, jn("hip_rotation", s), ~0.0 - sg * yf * heading)
    toe_clearance(f, off, s)
    off

  # The trunk servo of a loaded hip, weighted by w (its share of the load):
  # on each axis the target is the measured angle, led by its velocity to
  # cancel the reflex damping, minus a PD on the trunk error, so the hip
  # answers only to the trunk. Roll is weighted by w twice: in double
  # support the hips cannot level the pelvis and shift it at once.
  -> trunk_servo(f, off, s, w, heading)
    return trunk_torque(f, off, s, w, heading) if @hips != nil
    sg = sgn(s)
    pitch_des = @pitch_des + @lean_v * @v_des
    hf = jn("hip_flexion", s)
    ha = jn("hip_adduction", s)
    hr = jn("hip_rotation", s)
    t = f.t
    pl = @plan[s]
    tq = f.q(body, hf) + @hip_lead * f.qd(body, hf) - @t_kp * (@pitch - pitch_des) - @t_kd * @pitch_rate
    joint_offset(off, hf, w * (tq - pl.cmd(hf, t)))
    rq = f.q(body, ha) + @lead_add * f.qd(body, ha) + w * sg * (@r_kp * @roll + @r_kd * @roll_rate)
    joint_offset(off, ha, w * (rq - pl.cmd(ha, t)))
    yq = f.q(body, hr) + @lead_rot * f.qd(body, hr) + sg * (@y_kp * heading - @y_kd * @yaw_rate)
    joint_offset(off, hr, w * (yq - pl.cmd(hr, t)))
    off

  # The trunk servo in torque form: the hip first stops pulling toward its
  # commanded posture (target = measured angle, velocity-led), then the
  # trunk PD is applied as hip torques through the decoupled muscle map.
  -> trunk_torque(f, off, s, w, heading)
    sg = sgn(s)
    pitch_des = @pitch_des + @lean_v * @v_des
    t = f.t
    pl = @plan[s]
    hf = jn("hip_flexion", s)
    ha = jn("hip_adduction", s)
    hr = jn("hip_rotation", s)
    joint_offset(off, hf, w * (f.q(body, hf) + @hip_lead * f.qd(body, hf) - pl.cmd(hf, t)))
    joint_offset(off, ha, w * (f.q(body, ha) + @lead_add * f.qd(body, ha) - pl.cmd(ha, t)))
    tm = @tmode[s]
    rc = @rot_cancel
    rc = @rot_cancel_t if tm
    joint_offset(off, hr, w * rc * (f.q(body, hr) + @lead_rot * f.qd(body, hr) - pl.cmd(hr, t)))
    tf = ~0.0 - (@tq_kp * (@pitch - pitch_des) + @tq_kd * @pitch_rate)
    ta = w * sg * (@rq_kp * @roll + @rq_kd * @roll_rate)
    tr = sg * (@yq_kp * heading - @yq_kd * @yaw_rate)
    # turning loop: the stance hip turns the pelvis toward the goal heading
    # over the planted foot, but only within +-hr_lim_t of hip rotation (the
    # joint stops at 40 deg: a pelvis carried into the stop spins the sole
    # instead), torque capped below the sole's grip
    if tm
      hq = f.q(body, hr)
      tgt = clamp(hq + sg * heading, ~0.0 - @hr_lim_t, @hr_lim_t)
      tr = clamp(@yq_kp_t * (tgt - hq) - sg * @yq_kd_t * @yaw_rate, ~0.0 - @tr_max_t, @tr_max_t)
    g = @kp * @g_st
    g = @kp * @g_push if @phase[s] == :push
    @hips[s].torque(off, w * tf, w * ta, w * tr, g)
    off

  # Stance extras: the unloaded part of the hip keeps the thigh level in the
  # frontal plane; the ankle adds sagittal and lateral strategies about this
  # foot; from quiet standing the hips shift the COM onto the left foot.
  -> stance_extras(f, off, s, air)
    sg = sgn(s)
    ha = jn("hip_adduction", s)
    joint_offset(off, ha, ~0.0 - air * sg * @roll)
    fwd = rel_f(f, foot_x(f, s), foot_y(f, s))
    lat = rel_l(f, foot_x(f, s), foot_y(f, s))
    # flat foot: the ankle follows the shank's world inclination, so the
    # whole sole stays loaded and grips in yaw. The shank leans back from
    # the ankle by (thigh angle - knee); a flat foot then needs the ankle at
    # knee - thigh (dorsiflexed when the knee is ahead of the ankle)
    an = jn("ankle_angle", s)
    flat = f.q(body, jn("knee_angle", s)) - (f.q(body, jn("hip_flexion", s)) - @pitch)
    joint_offset(off, an, @flat * (flat + @a_st - @plan[s].cmd(an, f.t)))
    joint_offset(off, an, ~0.0 - @k_sta * (fwd - @sta_com))
    # the COM toward the stance foot's medial edge everts it (subtalar -)
    joint_offset(off, jn("subtalar_angle", s), sg * @k_stl * lat)
    # gait initiation: shift the COM over the left foot, unloading the right,
    # and lean forward over the feet (ankle strategy toward d_lean)
    if @starting
      joint_offset(off, an, ~0.0 - @k_lean * (fwd - @d_lean))
      cx = (foot_x(f, "l") + foot_x(f, "r")) * ~0.5
      cy = (foot_y(f, "l") + foot_y(f, "r")) * ~0.5
      e = rel_l(f, cx, cy) - @shift
      # the pelvis moves left when the left hip adducts and the right abducts
      joint_offset(off, ha, ~0.0 - sg * @k_shift * e)
    off

  # Withdrawal reflex: a toe below clear_h in swing flexes the knee and
  # dorsiflexes the ankle.
  -> toe_clearance(f, off, s)
    low = @clear_h - f.at(s + "_foot_pos", 2)
    return off if low <= ~0.0
    joint_offset(off, jn("knee_angle", s), @k_clear * low)
    joint_offset(off, jn("ankle_angle", s), @k_clear * low * ~0.5)
    off

  # Quiet stance: ankle strategy (sagittal), hip strategy (pitch), lateral
  # pelvis shift over the feet, heading hold.
  -> stand_correction(f)
    off = zeros
    cx = (foot_x(f, "l") + foot_x(f, "r")) * ~0.5
    cy = (foot_y(f, "l") + foot_y(f, "r")) * ~0.5
    fwd = rel_f(f, cx, cy) - @s_com
    lat = rel_l(f, cx, cy)
    ank = ~0.0 - (@k_ank * fwd + @d_ank * @vf)
    joint_offset(off, "ankle_angle_l", ank)
    joint_offset(off, "ankle_angle_r", ank)
    hip = ~0.0 - (@t_kp * (@pitch - @pitch_des) + @t_kd * @pitch_rate)
    joint_offset(off, "hip_flexion_l", hip)
    joint_offset(off, "hip_flexion_r", hip)
    # shift the pelvis right (COM too far left): right hip adducts, left abducts
    sh = @k_lat * lat + @d_lat * @vl
    joint_offset(off, "hip_adduction_r", sh)
    joint_offset(off, "hip_adduction_l", ~0.0 - sh)
    yaw = @y_kp * wrap(@psi - @psi_hold) + @y_kd * @yaw_rate
    joint_offset(off, "hip_rotation_r", yaw)
    joint_offset(off, "hip_rotation_l", ~0.0 - yaw)
    off
