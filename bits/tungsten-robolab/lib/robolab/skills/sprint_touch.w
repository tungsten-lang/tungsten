# SprintTouch: a sprint keyframed ONLY at toe-touch, powered by phase bursts.
#
# Erik's test: "model the toe touches with everything in between eased ...
# toe-touch followed by max power on the muscles that give a sprint its
# speed." One keyframe, the right touchdown (TD) posture; the left touchdown
# is its Pose#mirror. The stride is two chunks, one per step, each from one
# foot's touchdown to the other's:
#
#   r_step   right TD -> left TD   goal: the left touchdown (TD mirrored)
#   l_step   left TD -> right TD   goal: the right touchdown
#
# Each chunk is a `via` keyframe chunk (cubic Hermite), so the command runs
# touch -> touch as one velocity-continuous spline; there is no mid-stance,
# toe-off or knee-lift target. Consecutive goals alternate, so the Catmull-Rom
# tangent at every touch is zero and the command dwells at each touch; the
# touch velocities below (the keyframe's joint velocities at the touch, as a
# quintic Chunk#knot) are what make the stride run. Each chunk ends on the
# swing foot's touchdown: loading > 0.05 body weights after >= 60 ms in the
# air, ahead of the stance foot (a trailing toe scuffing behind is no step),
# after the stance foot's own touchdown; with a 0.6 s timeout.
#
# Keyframe (right stance landing, left trailing; degrees, model convention:
# hip + = flexion of the thigh on the pelvis, knee + = flexion, ankle + =
# PLANTARflexion, toe - = extension, shoulder + = forward):
#
#   td_st_hip td_st_knee td_st_ankle td_st_toe   landing leg (literature ~5
#     m/s: 33 15 5 0; Bolt at max velocity 28 4 30, bolt_keyframes.json)
#   td_sw_hip td_sw_knee td_sw_ankle td_sw_toe   trailing leg (~5 m/s: -2 75
#     10 0; Bolt: 18 140 36, the heel tucked)
#   arm (the landing-side arm back, the other forward: 5 -+ 28 arm deg),
#   elbow, d_spine (spine 4 + d_spine)
#
# Everything between two touches comes from the reflexes holding the eased
# command plus feed-forward BURSTS on the muscles that make sprint speed
# (Dorn, Schache & Pandy 2012, J Exp Biol 215:1944: the plantarflexors,
# soleus and gastrocnemius, give the vertical support that buys stride length
# up to ~7 m/s, the hip muscles, iliopsoas, gluteus maximus, rectus femoris
# and hamstrings, the faster swing that buys stride frequency beyond it;
# Morin et al. 2015, Front Physiol 6:404: the hamstrings' end-of-swing
# activity and eccentric strength drive horizontal force). Each leg runs its
# own schedule, timed on its own sensed touchdown (TD) and toe-off (TO):
#
#   stance (from TD, latched off at TO):
#     push     o_ext .. o_ext + d_ext   hip extensors (hip_flex_neg: gluteus
#              maximus, b_glut; ham: biarticular hamstrings, b_ham) and
#              plantarflexors (ankle_pos: soleus, b_sol; gas:
#              gastrocnemius, b_gas)
#     support  o_vas .. o_vas + d_vas   knee extensors (knee_neg: vasti,
#              b_vas), a brief pulse at landing
#     pre-swing from o_pre after TD      the swing's hip-flexor burst (b_ilio,
#              b_rf) starts in late stance, reversing the thigh before
#              toe-off (o_pre at its 0.4 s bound: off)
#   swing (from TO, latched off at TD):
#     drive    o_sw .. o_sw + d_sw      hip flexors (hip_flex_pos: iliopsoas,
#              b_ilio; rf: rectus femoris, b_rf), the knee drive; heel tuck
#              o_sw .. o_sw + d_tuck (knee_pos, b_tuck)
#     claw     late swing, timed on the OTHER leg's toe-off (the flight that
#              ends in this leg's touchdown): o_claw .. o_claw + d_claw after
#              it (and >= 0.1 s into this leg's swing), hamstrings (b_claw)
#              and gluteus (b_claw_g) brake the shank and pull the foot back
#              into the next touch; pre-landing vasti and plantarflexor tone
#              (b_pre_vas, b_pre_sol)
#
# The bursts are the chunk's drive vector (Chunk#drive, added to the reflex
# layer's activation, a = clamp(drive + g (kp (c* - c) - kd cdot))),
# rewritten every tick from the schedule. Stance bursts scale with `power`
# (drv_floor .. 1 along the speed plan, plus k_vd times the speed deficit;
# drv_floor 1 = full power from the first step).
#
# Feedback (run_natural's, spring-eased and clamped to +-corr_lim rad):
#   hop height  Raibert's thrust loop: k_z (z_ref - pelvis height) added to
#               the stance vasti, soleus and gastrocnemius; below z_ref the
#               stance knee is commanded straighter (k_zk rad per m)
#   torso       the stance hip blends the eased command (w_hip 0) with
#               SIMBICON's world-frame torso servo (1), PD on trunk pitch
#               (torso_kp, torso_kd) and the swing hip's reaction (k_swc); in
#               flight the trailing leg is the torso PD's reaction mass
#               (fly_kp, fly_kd)
#   placement   in flight the landing hip moves with speed: Raibert's
#               feedback cv (v - v_des) plus the neutral-point shift psi_v (v -
#               v_top) (the keyframe's landing angle is for v_top), and, t_ret
#               after the stance leg's toe-off, retracts at `retract` rad/s
#               (Seyfarth et al. 2003); the swing thigh is held in world frame
#               against pelvis pitch (comp in stance, comp_fly in flight)
# Reflex gains per leg and phase: stance hip g_st, knee g_stk, ankle g_sta;
# swing leg g_sw (knee g_swk); from the claw onset on, the landing leg g_land.
# Reciprocal inhibition (opt-in, `ri` k > 0; Controller#set_reciprocal):
# while a burst drives a prime mover its antagonist's activation is scaled by
# 1 - k drive, per leg for hip flexors / extensors, knee flexors / vasti,
# soleus / dorsiflexors, rectus femoris / hamstrings and gastrocnemius /
# dorsiflexors, so the bursts are not fought by co-contraction.
#
# Touch velocities (opt-in; every practised params file uses them): the
# keyframe may also carry each leg joint's
# angular velocity at the touch (rad/s; w_st_<joint> for the landing leg,
# w_sw_<joint> for the trailing leg, hip / knee / ankle). With any of them
# nonzero every step chunk is a quintic knot (Chunk#knot) arriving at the
# touch with those joint velocities (turned into contraction velocities
# through the body's geometry), and the next step starts from them, so the
# single touch -> touch segment bends between the touches: a landing hip
# that arrives retracting sweeps on back through stance, a landing knee
# still extending pushes before it folds, a trailing hip that leaves the
# touch swinging forward overshoots into the knee drive and comes back into
# the next touch. Still no mid-stance, toe-off or knee-lift target. (t_hold is
# ignored then: a staggered chunk runs no knot.) w_speed (0..1) scales the
# touch velocities with the speed plan, by 1 - w_speed (1 - v_des / v_top),
# so a standing start's slow first steps are not driven at sprint rates.
# `w_sym 1` ties the trailing hip's touch velocity to minus w_sym_k times the
# landing hip's (the legs scissor through the touch).
#
# Opt-in: t_hold > 0 delays the stance leg's knee and ankle command (Chunk#
# stagger) by t_hold, so the stance leg keeps its touchdown shape under load
# before easing toward the trailing posture (the chunk then eases min-jerk,
# still at rest at each touch, so velocity-continuous).
#
# Standing start (as run_natural): stand -> lean (ankle strategy until the COM
# is d_go ahead of the feet) -> l_push0 (the left leg pushes with its own
# drives drv0_*, its knee and ankle command held t0_hold, while the right
# leg lifts, drv0_lift / drv0_tuck, its knee folding to k0; ends at the left
# toe-off) -> l_step (the right leg reaches its first touchdown) -> the
# r_step / l_step loop; v_des ramps from v0 to v_top at `accel`. `s0 1`
# gives the push its own posture instead (the start only: the right thigh
# driven to s0_hip, the pushing leg extended behind, s0_push_*). A body that
# starts running (com_vx > 1 m/s: tasks/sprint_touch.py's flying starts,
# just before a right touchdown) goes straight into the loop, its command on
# the touchdown keyframe and its speed plan continued from the speed it has.
#
# Sensed events: a leg's touchdown (above) and toe-off (unloaded <= 0.02 body
# weights for 12 ms after >= 30 ms of stance; the foot box rocking heel to toe
# unloads for a tick or two mid-stance).

+ SprintTouchSkill < Skill
  -> start(frame, ctl)
    read_params
    @v_f = frame.com_vx
    @flying = frame.com_vx > ~1.0
    @v_des = @v0
    @t_go = ~-1.0
    # a flying start continues the speed plan from the speed it has
    @t_go = frame.t - clamp(frame.com_vx - @v0, ~0.0, ~20.0) / @accel if @flying
    @st = "r_"
    @sw = "l_"
    @z_err = ~0.0
    @running = @flying
    @starting = false
    init_events(frame)
    setup_reflexes(ctl)
    setup_reciprocal(ctl) if @ri > ~0.0
    @dv = zeros
    td = keyframe
    # running already (a flying start just before a right touchdown): the
    # command starts where the stride has it at that instant, on the
    # touchdown keyframe, not on the sensed posture
    seed_command(ctl, td) if @flying
    mv = Movement.new("sprint_touch")
    if @flying
      mv.add(step_chunk("l_", "r_", td))
    else
      mv.add(stand_chunk)
      mv.add(lean_chunk)
      mv.add(start_chunk)
      mv.add(step_chunk("l_", "r_", td))
    first = mv.size
    mv.add(step_chunk("r_", "l_", td.mirror))
    mv.add(step_chunk("l_", "r_", td))
    mv.loop_from(first)
    ctl.add_track(Track.new("body", mv, body.all))

  -> seed_command(ctl, pose)
    c = pose.apply(body, ctl.command)
    cmd = ctl.command
    i = 0
    while i < body.size
      cmd[i] = c[i]
      i += 1
    self

  -> read_params
    rad = ~0.017453292519943295
    # the touchdown keyframe (degrees)
    @td_st_hip = param("td_st_hip", ~29.0, ~-10.0, ~60.0)
    @td_st_knee = param("td_st_knee", ~35.0, ~0.0, ~60.0)
    @td_st_ankle = param("td_st_ankle", ~2.0, ~-25.0, ~45.0)
    @td_st_toe = param("td_st_toe", ~-6.0, ~-40.0, ~20.0)
    @td_sw_hip = param("td_sw_hip", ~15.0, ~-35.0, ~85.0)
    @td_sw_knee = param("td_sw_knee", ~70.0, ~10.0, ~145.0)
    @td_sw_ankle = param("td_sw_ankle", ~27.0, ~-25.0, ~45.0)
    @td_sw_toe = param("td_sw_toe", ~-14.0, ~-40.0, ~20.0)
    @arm = param("arm", ~0.5, ~0.3, ~2.0)
    @elbow = param("elbow", ~110.0, ~40.0, ~120.0)
    @d_spine = param("d_spine", ~13.0, ~-15.0, ~20.0)
    @stiff_st = param("stiff_st", ~0.3, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.02, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.18, ~0.0, ~0.35)
    # reciprocal inhibition gain (a params-file switch; 0 = off)
    @ri = ~0.0
    @ri = @params["ri"] if @params.key?("ri")
    # touch velocities (rad/s), see the header
    @w_st_hip = param("w_st_hip", ~0.0, ~-25.0, ~25.0)
    @w_st_knee = param("w_st_knee", ~0.0, ~-35.0, ~35.0)
    @w_st_ankle = param("w_st_ankle", ~0.0, ~-30.0, ~30.0)
    @w_sw_hip = param("w_sw_hip", ~0.0, ~-25.0, ~25.0)
    @w_sw_knee = param("w_sw_knee", ~0.0, ~-40.0, ~40.0)
    @w_sw_ankle = param("w_sw_ankle", ~0.0, ~-30.0, ~30.0)
    @w_speed = param("w_speed", ~0.0, ~0.0, ~1.0)
    # `w_sym 1` (a params-file switch): the trailing hip's touch velocity is
    # the negative of the landing hip's, scaled by w_sym_k (the legs scissor:
    # role-indexed, signed agonist / antagonist velocity vectors)
    if @params.key?("w_sym") && @params["w_sym"] > ~0.5
      k = param("w_sym_k", ~1.0, ~0.3, ~2.5)
      @w_sw_hip = ~0.0 - k * @w_st_hip
    @w_scale = ~1.0
    @knot_vels = []
    ws = [@w_st_hip, @w_st_knee, @w_st_ankle, @w_sw_hip, @w_sw_knee, @w_sw_ankle]
    @knots = ws.any? ->(w) w > ~0.000001 || w < ~-0.000001
    # step timing: the spline's touch -> touch time, and the opt-in stance
    # knee / ankle hold
    @t_step = param("t_step", ~0.33, ~0.15, ~0.45)
    @t_hold = param("t_hold", ~0.0, ~0.0, ~0.3)
    # reflexes and per-phase gains
    @leg_kp = param("leg_kp", ~8.0, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.35, ~0.05, ~0.6)
    @bi_gain = param("bi_gain", ~1.0, ~0.0, ~1.5)
    @up_kp = param("up_kp", ~5.0, ~2.0, ~12.0)
    @up_kd = param("up_kd", ~0.15, ~0.05, ~0.6)
    @g_st = param("g_st", ~0.62, ~0.3, ~2.0)
    @g_stk = param("g_stk", ~1.2, ~0.1, ~2.0)
    @g_sta = param("g_sta", ~1.0, ~0.1, ~2.0)
    @g_sw = param("g_sw", ~1.0, ~0.1, ~1.5)
    @g_swk = param("g_swk", ~1.0, ~0.1, ~1.5)
    @g_land = param("g_land", ~1.0, ~0.2, ~1.8)
    # stance bursts (seconds after touchdown; latched off at toe-off)
    @o_ext = param("o_ext", ~0.0, ~0.0, ~0.08)
    @d_ext = param("d_ext", ~0.18, ~0.03, ~0.3)
    @b_glut = param("b_glut", ~0.65, ~0.0, ~1.0)
    @b_ham = param("b_ham", ~0.6, ~0.0, ~1.0)
    @b_sol = param("b_sol", ~0.6, ~0.0, ~1.0)
    @b_gas = param("b_gas", ~0.7, ~0.0, ~1.0)
    @o_vas = param("o_vas", ~0.0, ~0.0, ~0.06)
    @d_vas = param("d_vas", ~0.15, ~0.01, ~0.2)
    @b_vas = param("b_vas", ~0.6, ~0.0, ~1.0)
    @o_pre = param("o_pre", ~0.4, ~0.05, ~0.4)
    # swing bursts (seconds after toe-off; latched off at touchdown)
    @o_sw = param("o_sw", ~0.0, ~0.0, ~0.08)
    @d_sw = param("d_sw", ~0.3, ~0.02, ~0.4)
    @b_ilio = param("b_ilio", ~1.0, ~0.0, ~1.0)
    @b_rf = param("b_rf", ~0.3, ~0.0, ~1.0)
    @b_tuck = param("b_tuck", ~0.9, ~0.0, ~1.0)
    @d_tuck = param("d_tuck", ~0.2, ~0.02, ~0.4)
    @o_claw = param("o_claw", ~0.0, ~-0.1, ~0.15)
    @d_claw = param("d_claw", ~0.2, ~0.02, ~0.3)
    @b_claw = param("b_claw", ~0.55, ~0.0, ~1.0)
    @b_claw_g = param("b_claw_g", ~0.7, ~0.0, ~1.0)
    @b_pre_vas = param("b_pre_vas", ~0.35, ~0.0, ~0.8)
    @b_pre_sol = param("b_pre_sol", ~0.05, ~0.0, ~0.8)
    # stance power along the speed plan
    @drv_floor = param("drv_floor", ~1.0, ~0.0, ~1.0)
    @k_vd = param("k_vd", ~0.0, ~0.0, ~1.0)
    # hop height
    @z_ref = param("z_ref", ~0.85, ~0.8, ~1.0)
    @k_z = param("k_z", ~0.0, ~0.0, ~12.0)
    @k_zk = param("k_zk", ~0.0, ~0.0, ~6.0)
    # torso
    @w_hip = param("w_hip", ~1.0, ~0.0, ~1.0)
    @hip_lead = param("hip_lead", ~0.1, ~0.0, ~0.2)
    @torso_kp = param("torso_kp", ~0.5, ~0.0, ~3.0)
    @torso_kd = param("torso_kd", ~0.5, ~0.0, ~0.8)
    @k_swc = param("k_swc", ~0.0, ~0.0, ~1.5)
    @fly_kp = param("fly_kp", ~1.0, ~0.0, ~2.0)
    @fly_kd = param("fly_kd", ~0.23, ~0.0, ~0.5)
    @lean = param("lean", ~17.0, ~-8.0, ~20.0)
    @lean_acc = param("lean_acc", ~0.3, ~0.0, ~0.6)
    # placement
    @comp = param("comp", ~1.0, ~0.0, ~1.0)
    @comp_fly = param("comp_fly", ~0.73, ~0.0, ~1.0)
    @cv = param("cv", ~0.05, ~0.0, ~0.4)
    @psi_v = param("psi_v", ~0.08, ~0.0, ~0.2)
    @retract = param("retract", ~3.3, ~0.0, ~6.0)
    @t_ret = param("t_ret", ~0.15, ~0.0, ~0.4)
    @corr_lim = param("corr_lim", ~0.4, ~0.05, ~0.6)
    @spring = param("spring", ~0.02, ~0.01, ~0.2)
    # speed plan
    @v_top = param("v_top", ~5.0, ~3.0, ~12.0)
    @v0 = param("v0", ~1.1, ~0.0, ~2.5)
    @accel = param("accel", ~2.8, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.14, ~0.02, ~0.5)
    # standing start
    @d_go = param("d_go", ~0.21, ~0.0, ~0.3)
    @k_bal = param("k_bal", ~0.3, ~0.0, ~3.0)
    @stiff0 = param("stiff0", ~0.05, ~0.0, ~0.3)
    @g0 = param("g0", ~0.5, ~0.3, ~1.5)
    @t0 = param("t0", ~0.3, ~0.15, ~0.5)
    @t0_hold = param("t0_hold", ~0.2, ~0.0, ~0.4)
    @t0_max = param("t0_max", ~0.55, ~0.2, ~0.8)
    @k0 = param("k0", ~80.0, ~10.0, ~130.0)
    # the first push's own posture (degrees; the start only, the stride stays
    # touch-only): the lifting right thigh's knee drive s0_hip, the pushing
    # left leg extended behind (s0_push_hip / knee / ankle); s0 0 keeps the
    # touchdown keyframe with only the right knee at k0
    @s0 = param("s0", ~0.0, ~0.0, ~1.0)
    @s0_hip = param("s0_hip", ~50.0, ~0.0, ~90.0)
    @s0_push_hip = param("s0_push_hip", ~-15.0, ~-40.0, ~20.0)
    @s0_push_knee = param("s0_push_knee", ~15.0, ~0.0, ~60.0)
    @s0_push_ankle = param("s0_push_ankle", ~25.0, ~-10.0, ~45.0)
    @drv0_knee = param("drv0_knee", ~0.06, ~0.0, ~1.0)
    @drv0_ankle = param("drv0_ankle", ~1.0, ~0.0, ~1.0)
    @drv0_hip = param("drv0_hip", ~0.48, ~0.0, ~1.0)
    @drv0_lift = param("drv0_lift", ~0.5, ~0.0, ~1.0)
    @drv0_tuck = param("drv0_tuck", ~0.4, ~0.0, ~1.0)
    # reference trunk and pelvis pitch (rad, world frame)
    @trunk_ref = ~0.13
    @trunk_des = @trunk_ref + @lean * rad
    # the pelvis pitch the corrections compensate against: the trunk's
    # target less the keyframe's spine flexion
    @pelvis_ref = @trunk_des - (~4.0 + @d_spine) * rad
    self

  -> setup_reflexes(ctl)
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    ctl.reflex.set_gains(body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"]), @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    ctl.reflex.set_gains(body.mask(["spine", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @up_kp, @up_kd)
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    @mu = {}
    ["l_", "r_"].each ->(side)
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "gas", side + "toe"])
      ["hip_flex_pos", "hip_flex_neg", "knee_pos", "knee_neg", "ankle_pos", "rf", "ham", "gas"].each ->(m)
        @mu[side + m] = index_or(side + m)
    self

  -> index_or(name)
    return body.index(name) if body.has?(name)
    -1

  -> setup_reciprocal(ctl)
    pairs = []
    ["l_", "r_"].each ->(side)
      [["hip_flex_pos", "hip_flex_neg"], ["knee_pos", "knee_neg"], ["ankle_pos", "ankle_neg"], ["rf", "ham"],
       ["gas", "ankle_neg"]].each ->(pr)
        a = index_or(side + pr[0])
        b = index_or(side + pr[1])
        pairs.push([a, b]) if a >= 0 && b >= 0
    ctl.set_reciprocal(pairs, @ri)
    self

  # ---- the keyframe -------------------------------------------------------------

  # The right touchdown: right leg landing, left leg trailing, the right arm
  # back and the left forward.
  -> keyframe
    rad = ~0.017453292519943295
    p = Pose.new
    p.set("r_hip_flex", @td_st_hip * rad, @stiff_st)
    p.set("r_knee", @td_st_knee * rad, @stiff_st)
    p.set("r_ankle", @td_st_ankle * rad, @stiff_st)
    p.set("r_toe", @td_st_toe * rad, @stiff_st)
    p.set("l_hip_flex", @td_sw_hip * rad, @stiff_sw)
    p.set("l_knee", @td_sw_knee * rad, @stiff_sw)
    p.set("l_ankle", @td_sw_ankle * rad, @stiff_sw)
    p.set("l_toe", @td_sw_toe * rad, @stiff_sw)
    p.set("r_shoulder_flex", (~5.0 - ~28.0 * @arm) * rad, @stiff_up)
    p.set("l_shoulder_flex", (~5.0 + ~28.0 * @arm) * rad, @stiff_up)
    p.set("r_elbow", @elbow * rad, @stiff_up)
    p.set("l_elbow", @elbow * rad, @stiff_up)
    p.set("spine_flex", (~4.0 + @d_spine) * rad, @stiff_up)
    p

  # The keyframe's contraction velocities at a touchdown of `land` (the
  # trailing leg `trail`): each joint's touch velocity through the geometry.
  -> touch_velocity(land, trail)
    v = zeros
    joint_offset(v, land + "hip_flex", @w_st_hip)
    joint_offset(v, land + "knee", @w_st_knee)
    joint_offset(v, land + "ankle", @w_st_ankle)
    joint_offset(v, trail + "hip_flex", @w_sw_hip)
    joint_offset(v, trail + "knee", @w_sw_knee)
    joint_offset(v, trail + "ankle", @w_sw_ankle)
    v

  # ---- chunks ----------------------------------------------------------------------

  # One step: `st` just touched down, `sw` swings to its touchdown `goal`.
  -> step_chunk(st, sw, goal)
    ch = Chunk.new(st + "step", @t_step).pose(goal)
    if @knots
      v = touch_velocity(sw, st)
      @knot_vels.push([v, v.map ->(x) x])
      ch.knot(v, nil)
    else
      ch.via
      ch.stagger(body.mask([st + "knee", st + "ankle", st + "gas", st + "toe"]), @t_hold) if @t_hold > ~0.005
    touch = Latch.test("td:" + sw, ->(f, e, c) touched?(sw, st))
    ch.hold_until(touch.after_min(~0.05), ~0.6)
    ch.drive(@dv)
    ch.correct(->(f, c) correction(f, c, st, sw), @spring)
    ch.on_enter(->(f, c) enter(st, sw))
    ch

  # Has the swing foot touched down after the stance foot did? (Not "since
  # the chunk began": the first step's touchdown may come before the push-off
  # chunk hands over.)
  -> touched?(sw, st)
    @down[sw] && @td_t[sw] > @td_t[st]

  -> enter(st, sw)
    @st = st
    @sw = sw
    @running = true
    @starting = false
    self

  # Quiet stance while the reflexes settle.
  -> stand_pose(p)
    rad = ~0.017453292519943295
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", ~0.05, @stiff0)
      p.set(s + "knee", ~0.12, @stiff0)
      p.set(s + "ankle", ~-0.05, @stiff0)
      p.set(s + "shoulder_flex", ~0.0, @stiff_up)
      p.set(s + "elbow", @elbow * rad, @stiff_up)
    p.set("spine_flex", (~4.0 + @d_spine) * rad, @stiff_up)
    p

  -> stand_chunk
    ch = Chunk.new("stand", ~0.3).pose(stand_pose(Pose.new)).hold_until(Latch.after(~0.5))
    ch.correct(->(f, c) balance(f, ~0.05), ~0.08)
    ch.gain(@g0)
    ch

  # Tip forward until the COM is d_go ahead of the feet.
  -> lean_chunk
    p = stand_pose(Pose.new)
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", ~0.1, @stiff0)
      p.set(s + "knee", ~0.2, @stiff0)
      p.set(s + "ankle", ~-0.2, @stiff0)
    p.set("l_shoulder_flex", ~0.3, @stiff_up)
    p.set("r_shoulder_flex", ~-0.3, @stiff_up)
    ahead = Latch.test("com_ahead", ->(f, e, c) f.com_x - feet_x(f) > @d_go)
    ch = Chunk.new("lean", ~0.4).pose(p).hold_until(ahead.after_min(~0.1), ~1.5)
    ch.correct(->(f, c) balance(f, @d_go + ~0.1), ~0.08)
    ch.gain(@g0)
    ch

  # The first push: the left leg drives (its knee and ankle command held
  # t0_hold) while the right leg lifts (its knee folding to k0 degrees) and
  # swings toward the right touchdown; ends at the left toe-off, and an
  # l_step carries the right leg on into its first touchdown.
  -> start_chunk
    rad = ~0.017453292519943295
    goal = keyframe
    goal.set("r_knee", @k0 * rad, @stiff_sw)
    if @s0 > ~0.5
      goal.set("r_hip_flex", @s0_hip * rad, @stiff_sw)
      goal.set("l_hip_flex", @s0_push_hip * rad, @stiff_st)
      goal.set("l_knee", @s0_push_knee * rad, @stiff_st)
      goal.set("l_ankle", @s0_push_ankle * rad, @stiff_st)
    ch = Chunk.new("l_push0", @t0).pose(goal)
    ch.stagger(body.mask(["l_knee", "l_ankle", "l_gas", "l_toe"]), @t0_hold) if @t0_hold > ~0.005
    off = Latch.test("to:l_", ->(f, e, c) !@down["l_"])
    ch.hold_until(off.after_min(~0.15), @t0_max)
    ch.drive(@dv)
    ch.correct(->(f, c) correction(f, c, "l_", "r_"), @spring)
    ch.on_enter(->(f, c) start_stride(f))
    ch

  -> start_stride(f)
    enter("l_", "r_")
    @starting = true
    @t_go = f.t
    @td_t["l_"] = f.t
    self

  -> feet_x(f)
    (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5

  # Ankle strategy plus a hip strategy on the trunk's lean.
  -> balance(f, target)
    dq = ~2.0 * (f.com_x - feet_x(f) - target) + ~0.4 * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    hip = ~0.0 - @k_bal * (f.torso_pitch - @trunk_ref) - ~0.2 * f.torso_pitch_rate
    joint_offset(off, "l_hip_flex", hip)
    joint_offset(off, "r_hip_flex", hip)
    off

  # ---- sensed gait events -------------------------------------------------------------

  -> init_events(f)
    @down = {}
    @td_t = {}
    @to_t = {}
    @off_t = {}
    ["l_", "r_"].each ->(s)
      @down[s] = !@flying
      @off_t[s] = ~-1.0
      @td_t[s] = f.t - ~0.4
      @to_t[s] = f.t - ~0.4
    if @flying
      # a flying start (tasks/sprint_touch.py: just before a right touchdown;
      # run_natural's: just after a left toe-off): the left leg in early
      # swing, the right leg landing
      @to_t["l_"] = f.t - ~0.12
      @to_t["r_"] = f.t - ~0.25
    self

  # A foot touches down when it loads (> 0.05 body weights) after >= 60 ms in
  # the air, landing ahead of the other foot if that one is down (a trailing
  # toe scuffing the ground behind is not a step), and toes off when it has
  # stayed unloaded (<= 0.02) for 12 ms after >= 30 ms of stance (a foot
  # rocking heel to toe unloads for a tick or two mid-stance); the toe-off
  # time is when it unloaded.
  -> update_events(f)
    ["l_", "r_"].each ->(s)
      o = "l_"
      o = "r_" if s == "l_"
      ahead = !@down[o] || f.at(s + "foot_pos", 0) > f.at(o + "foot_pos", 0)
      c = f.get(s + "foot_contact")
      if @down[s]
        if c > ~0.02
          @off_t[s] = ~-1.0
        elsif f.t - @td_t[s] >= ~0.03
          @off_t[s] = f.t if @off_t[s] < ~0.0
          if f.t - @off_t[s] >= ~0.012
            @down[s] = false
            @to_t[s] = @off_t[s]
            @off_t[s] = ~-1.0
      elsif c > ~0.05 && f.t - @to_t[s] >= ~0.06 && ahead
        @down[s] = true
        @td_t[s] = f.t
    self

  # ---- per tick -------------------------------------------------------------------------

  -> before(frame, ctl)
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    if @t_go >= ~0.0
      @v_des = @v0 + @accel * (frame.t - @t_go)
      @v_des = @v_top if @v_des > @v_top
    @trunk_des = @trunk_ref + @lean * ~0.017453292519943295 + @lean_acc * (~1.0 - @v_des / @v_top)
    @z_err = @z_ref - frame.pelvis_height
    scale_knots
    update_events(frame)
    fill_bursts(frame)
    self

  # Per-leg reflex gains from each leg's own state.
  -> after(frame, ctl)
    return self if !@running
    ["l_", "r_"].each ->(s)
      if @down[s]
        gh = @g_st
        gk = @g_stk
        ga = @g_sta
      elsif late_swing?(frame, s)
        gh = @g_land
        gk = @g_land
        ga = @g_land
      else
        gh = @g_sw
        gk = @g_swk
        ga = @g_sw
      @hip_idx[s].each ->(m) ctl.set_gain(m, gh)
      @knee_idx[s].each ->(m) ctl.set_gain(m, gk)
      @ankle_idx[s].each ->(m) ctl.set_gain(m, ga)
    self

  # Touch velocities along the speed plan (w_speed; each chunk's knot array
  # is rescaled in place from its full-speed copy).
  -> scale_knots
    return self if @w_speed < ~0.000001
    k = ~1.0 - @w_speed * (~1.0 - clamp(@v_des / @v_top, ~0.0, ~1.0))
    return self if k == @w_scale
    @w_scale = k
    @knot_vels.each ->(pair)
      v = pair[0]
      full = pair[1]
      i = 0
      while i < v.size
        v[i] = full[i] * k
        i += 1
    self

  # ---- bursts ------------------------------------------------------------------------------

  # Stance power: drv_floor .. 1 along the speed plan, plus k_vd x the deficit.
  -> power
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @v_top, ~0.0, ~1.0)
    clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)

  -> fill_bursts(f)
    d = @dv
    i = 0
    while i < d.size
      d[i] = ~0.0
      i += 1
    return self if !@running
    s = power
    h = @k_z * @z_err
    ["l_", "r_"].each ->(side)
      if @starting
        start_bursts(d, side, f.t)
      elsif @down[side]
        stance_bursts(d, side, f.t - @td_t[side], s, h)
      else
        swing_bursts(d, side, f.t - @to_t[side], claw_age(f, side))
    i = 0
    while i < d.size
      d[i] = clamp(d[i], ~0.0, ~1.0)
      i += 1
    self

  -> within?(e, onset, dur)
    e >= onset && e < onset + dur

  # Late swing of `side`: from o_claw after the other leg's toe-off (the
  # flight before this leg lands), once this leg has swung >= 0.1 s. Returns
  # the time since late swing began, or -1.
  -> claw_age(f, side)
    o = "l_"
    o = "r_" if side == "l_"
    return ~-1.0 if @down[o] || @down[side]
    t0 = @to_t[o] + @o_claw
    t0 = @to_t[side] + ~0.1 if @to_t[side] + ~0.1 > t0
    return ~-1.0 if f.t < t0
    f.t - t0

  -> late_swing?(f, side)
    claw_age(f, side) >= ~0.0

  -> add(d, key, v)
    m = @mu[key]
    d[m] = d[m] + v if m >= 0
    self

  -> stance_bursts(d, side, e, s, h)
    if within?(e, @o_ext, @d_ext)
      add(d, side + "hip_flex_neg", @b_glut * s)
      add(d, side + "ham", @b_ham * s)
      add(d, side + "ankle_pos", @b_sol * s)
      add(d, side + "gas", @b_gas * s)
    add(d, side + "knee_neg", @b_vas * s) if within?(e, @o_vas, @d_vas)
    if e >= @o_pre && @o_pre < ~0.395
      add(d, side + "hip_flex_pos", @b_ilio)
      add(d, side + "rf", @b_rf)
    add(d, side + "knee_neg", h)
    add(d, side + "ankle_pos", h)
    add(d, side + "gas", h)
    self

  -> swing_bursts(d, side, e, ca)
    if within?(e, @o_sw, @d_sw) && ca < ~0.0
      add(d, side + "hip_flex_pos", @b_ilio)
      add(d, side + "rf", @b_rf)
    add(d, side + "knee_pos", @b_tuck) if within?(e, @o_sw, @d_tuck) && ca < ~0.0
    if ca >= ~0.0 && ca < @d_claw
      add(d, side + "ham", @b_claw)
      add(d, side + "hip_flex_neg", @b_claw_g)
      add(d, side + "knee_neg", @b_pre_vas)
      add(d, side + "ankle_pos", @b_pre_sol)
      add(d, side + "gas", @b_pre_sol)
    self

  # The first push: the left leg's own drives while it is down; the right
  # leg lifts (hip flexors, knee flexors) until it leaves the ground, then
  # swings with the regular knee-drive burst.
  -> start_bursts(d, side, t)
    if side == "l_"
      if @down["l_"]
        add(d, "l_knee_neg", @drv0_knee)
        add(d, "l_ankle_pos", @drv0_ankle)
        add(d, "l_gas", @drv0_ankle)
        add(d, "l_hip_flex_neg", @drv0_hip)
      return self
    if @down["r_"]
      add(d, "r_hip_flex_pos", @drv0_lift)
      add(d, "r_knee_pos", @drv0_tuck)
      return self
    swing_bursts(d, "r_", t - @to_t["r_"], ~-1.0)
    self

  # ---- corrections -------------------------------------------------------------------------

  -> correction(f, ctl, st, sw)
    off = zeros
    lim = @corr_lim
    nlim = ~0.0 - lim
    tilt = pelvis_pitch(f) - @pelvis_ref
    place = @cv * (@v_f - @v_des) + @psi_v * (@v_f - @v_top)
    if @down[st]
      joint_offset(off, st + "hip_flex", torso_servo(f, ctl, st, sw))
      joint_offset(off, sw + "hip_flex", clamp(@comp * tilt, nlim, lim))
      low = @z_err
      low = ~0.0 if low < ~0.0
      joint_offset(off, st + "knee", clamp(~0.0 - @k_zk * low, nlim, ~0.0))
      return off
    err = f.torso_pitch - @trunk_des
    fly = clamp(~0.0 - @fly_kp * err - @fly_kd * f.torso_pitch_rate, nlim, lim)
    joint_offset(off, st + "hip_flex", fly)
    late = f.t - @to_t[st] - @t_ret
    late = ~0.0 if late < ~0.0
    joint_offset(off, sw + "hip_flex", clamp(place + @comp_fly * tilt - @retract * late, nlim, lim))
    off

  # Stance hip: w_hip x (measured angle led by its rate, minus the command)
  # hands the hip from the eased command to the torso PD; the swing hip's
  # servo error is cancelled (SIMBICON: tau_stance = -tau_torso - tau_swing).
  -> torso_servo(f, ctl, st, sw)
    j = st + "hip_flex"
    free = f.q(body, j) + @hip_lead * f.qd(body, j) - pair_angle(ctl.command.values, j)
    err = f.torso_pitch - @trunk_des
    pd = ~0.0 - @torso_kp * err - @torso_kd * f.torso_pitch_rate - @k_swc * servo_error(f, ctl, sw + "hip_flex")
    @w_hip * free + clamp(pd, ~0.0 - @corr_lim, @corr_lim)

  -> servo_error(f, ctl, joint)
    pair_angle(ctl.target, joint) - f.q(body, joint)

  # A joint's angle as its own antagonist pair commands it.
  -> pair_angle(values, joint)
    p = body.index(joint + "_pos")
    n = body.index(joint + "_neg")
    (body.muscle(p).angle_at(values[p]) + body.muscle(n).angle_at(values[n])) * ~0.5

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))
