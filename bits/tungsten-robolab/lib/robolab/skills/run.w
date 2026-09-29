# Run: a SIMBICON-style running gait (Yin, Loken & van de Panne 2007) with
# Raibert-style speed control, written as contraction chunks.
#
# Gaits sharing this skill and its corrections, chosen by the params file:
#
#   params/run.txt        baseline: the six-chunk stride below
#   params/run_lean.txt   forward-lean variant: same stride, with fall_lean /
#                         knee_lift / heel_tuck (see "Forward-lean variant")
#   params/run_bound.txt  `gait 1`: alternating mirrored bounds, four chunks
#                         per stride (see add_bounds)
#   params/run_v2.txt     the six-chunk stride on the v2 anatomy (toes and
#                         biarticular muscles), practised for speed
#   `gait 2`              one chunk per step, two per stride (see add_steps)
#
# One Track drives the whole body. Chunks and the latches that end them
# (`st` = the stance side, `sw` = the swing side):
#
#   start  stand ──(0.5 s)──> lean ──(COM d_go ahead of the ankles)──> l_push
#   loop   l_push ──(release l_foot)──> l_flight ──(contact r_foot)──> r_land
#          r_land ──(COM rising, or COM d_push past r_foot)──> r_push
#          r_push ──(release r_foot)──> r_flight ──(contact l_foot)──> l_land
#          l_land ──(COM rising, or COM d_push past l_foot)──> l_push ...
#
# so a stride is six chunk decisions, and each leg walks through six phases:
#
#   st_land    stance, early: soft knee and ankle yield like a spring
#   st_push    stance, late: the leg stiffens and extends with a drive burst
#   st_flight  follow-through: the leg that just pushed folds and recovers
#   sw_land    mid swing: thigh drives forward, heel tucked
#   sw_push    late swing: thigh high, knee opening
#   sw_flight  reach: thigh drops to the landing angle, knee extends
#
# Pose goals give every joint its nominal angle for the end of the chunk,
# eased min-jerk from wherever the command is (stance, swing and upper-body
# joints each with their own co-contraction). Spring-eased corrections close
# the loop every tick:
#
#   torso      in stance the stance hip is steered in world frame: its target
#              is the measured hip angle (plus a lead that cancels the
#              reflex's velocity damping and the spring lag) minus a PD on
#              torso pitch, minus the swing hip's servo error (SIMBICON's
#              tau_stance = -tau_torso - tau_swing), so the stance hip becomes
#              a pure torso servo. In flight nothing anchors the pelvis, so the
#              trailing leg serves as the reaction mass of the torso PD.
#   placement  the swing hip holds its thigh angle in world frame in stance
#              (pelvis pitch compensated; in flight partly, comp_fly, since
#              full compensation there is positive feedback) and, in late
#              swing and reach, the landing angle moves with speed: psi_v * v
#              (Raibert's neutral point) plus cv * (v - v_des). Past t_flight
#              the landing leg keeps retracting at `retract` rad/s (swing-leg
#              retraction, Seyfarth et al. 2003). Above v_cap a one-sided
#              brake moves the landing foot forward (k_brake) so the gait
#              cannot run away.
#   clearance  a withdrawal reflex on the swinging leg: when its ankle drops
#              below clear_h the knee flexes and the ankle dorsiflexes.
#
# Drives (feed-forward activation on top of the reflexes): push-off on the
# stance knee and ankle extensors and hip extensor, scaled with the speed
# plan and the speed deficit, plus hop-height feedback (Raibert's thrust
# loop: the knee and ankle push harder while the pelvis rides low); in flight, swing initiation on the trailing
# leg's hip and knee flexors and pre-landing activity in the landing knee.
# Gains: the reflex gain is set per leg and phase (see `after`): a soft
# landing knee and ankle, a firm stance hip and push, a loose swing leg.
#
# Forward-lean variant (params/run_lean.txt; every term is zero in the
# baseline, params/run.txt): a "caught fall" in the spirit of the Pose
# method. fall_lean tilts the torso target forward; with fall_place = 1 the
# whole body rotates as one piece (the pelvis pitch the corrections
# compensate against moves too, the pelvis-relative hip poses stay put, so
# every leg's world angle tilts back and the foot lands under the hips with
# the COM ahead of it), with fall_place = 0 only the trunk leans and the
# landing stays where it was relative to the hips. (At constant speed the
# mean ground force is vertical through the COM, so a permanent COM-ahead
# lean only works while accelerating; practice picks the blend.) fall_ankle
# dorsiflexes the
# landing ankle so the body can rotate forward over the foot. knee_lift adds
# swing-hip flexion in mid and late swing (thigh toward horizontal) and
# heel_tuck adds swing-knee flexion in follow-through and mid swing (a
# tighter heel recovery, more toe clearance).
#
# The desired speed v_des ramps from v0 to v_top at `accel`, and the torso
# leans further forward while v_des is still rising (sprinters'
# acceleration lean). All numbers are tunables (`param`), practised with
# CMA-ES; params/run.txt holds the practised set.

+ RunSkill < Skill
  -> start(frame, ctl)
    read_params
    @v_f = ~0.0
    @v_des = ~0.0
    @t_go = ~-1.0
    @z_err = ~0.0
    @torso_des = @lean
    @drives = []
    @phase = nil
    @t_phase = ~0.0
    @lifted = {}
    @lifted["l_"] = false
    @lifted["r_"] = false
    @st = "l_"
    @sw = "r_"
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    # v2 bodies: the biarticulars' stretch reflexes couple joints (a yielding
    # knee stretches the rectus femoris, whose reflex then flexes the hip), so
    # they get their own, usually lower, reflex gain; the monoarticulars servo
    # the posture and the biarticulars add tone and drive bursts
    biart = body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(biart, @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    # (v2 bodies: the biarticulars ride with the joint they mostly serve, rf
    # and ham with the hip, gas and the toe muscles with the ankle)
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle", side + "toe", side + "rf", side + "ham", side + "gas"])
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "gas", side + "toe"])

    mv = Movement.new("run")
    mv.add(stand_chunk)
    mv.add(lean_chunk)
    mv.add(push_chunk("l_", "r_", true))
    if @gait == 1
      add_bounds(mv)
    elsif @gait == 2
      add_steps(mv)
    else
      mv.add(flight_chunk("l_", "r_", nil))
      mv.add(land_chunk("r_", "l_"))
      mv.add(push_chunk("r_", "l_", false))
      mv.add(flight_chunk("r_", "l_", nil))
      mv.add(land_chunk("l_", "r_"))
      mv.add(push_chunk("l_", "r_", false))
    mv.loop_from(3)
    ctl.add_track(Track.new("body", mv, body.all))

  -> read_params
    # gait structure switch (a params-file setting, not a tunable): 0 = the
    # six-chunk stride, 1 = alternating bounds (see add_bounds)
    @gait = ~0.0
    @gait = @params["gait"] if @params.key?("gait")
    # easing of the bound's drive chunk (a params-file setting): 0 min_jerk,
    # 1 cubic_in, 2 quint_in, 3 expo_in. The "in" curves hold the stance leg
    # near its landing posture early (the load) and extend it late (the drive)
    @drive_ease = :min_jerk
    de = ~0.0
    de = @params["drive_ease"] if @params.key?("drive_ease")
    @drive_ease = :cubic_in if de > ~0.5
    @drive_ease = :quint_in if de > ~1.5
    @drive_ease = :expo_in if de > ~2.5
    # speed plan
    @v_top = param("v_top", ~3.8, ~2.5, ~10.0)
    @v0 = param("v0", ~1.0, ~0.0, ~2.5)
    @accel = param("accel", ~1.2, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.15, ~0.02, ~0.5)
    # torso
    @lean = param("lean", ~0.15, ~-0.1, ~0.4)
    @lean_acc = param("lean_acc", ~0.2, ~0.0, ~0.6)
    @spine = param("spine", ~0.15, ~-0.2, ~0.4)
    @torso_kp = param("torso_kp", ~1.5, ~0.3, ~3.0)
    @torso_kd = param("torso_kd", ~0.3, ~0.05, ~0.5)
    @hip_lead = param("hip_lead", ~0.02, ~0.0, ~0.12)
    @k_swc = param("k_swc", ~0.6, ~0.0, ~1.5)
    @k_fly = param("k_fly", ~0.8, ~0.0, ~1.5)
    @clear_h = param("clear_h", ~0.16, ~0.08, ~0.3)
    @k_clear = param("k_clear", ~0.0, ~0.0, ~12.0)
    @retract = param("retract", ~0.0, ~0.0, ~6.0)
    @comp_fly = param("comp_fly", ~0.7, ~0.0, ~1.0)
    @k_fly_d = param("k_fly_d", ~0.22, ~0.0, ~0.4)
    # forward-lean ("caught fall", Pose-method) variant; all zero = baseline
    @fall_lean = param("fall_lean", ~0.0, ~0.0, ~0.45)
    @fall_ankle = param("fall_ankle", ~0.0, ~0.0, ~0.4)
    @fall_place = param("fall_place", ~1.0, ~0.0, ~1.0)
    @knee_lift = param("knee_lift", ~0.0, ~0.0, ~0.7)
    @heel_tuck = param("heel_tuck", ~0.0, ~0.0, ~0.8)
    # nominal pelvis pitch the hip poses are written for, and the pitch the
    # corrections compensate against (the leaned body, see fall_lean)
    @phi_nom = @lean - @spine
    @phi_ref = @phi_nom + @fall_place * @fall_lean
    # stance leg
    @d_push = param("d_push", ~0.3, ~-0.2, ~0.4)
    @vz_push = param("vz_push", ~0.0, ~-0.4, ~0.4)
    @t_absorb = param("t_absorb", ~0.04, ~0.0, ~0.15)
    @k_land = param("k_land", ~0.5, ~0.2, ~0.9)
    @a_land = param("a_land", ~0.1, ~-0.3, ~0.5)
    @k_push = param("k_push", ~0.15, ~0.0, ~0.5)
    @a_push = param("a_push", ~0.6, ~0.2, ~0.9)
    @psi_ms = param("psi_ms", ~0.1, ~-0.3, ~0.5)
    @psi_to = param("psi_to", ~-0.4, ~-0.8, ~0.0)
    @drv_knee = param("drv_knee", ~0.4, ~0.0, ~1.0)
    @drv_ankle = param("drv_ankle", ~0.5, ~0.0, ~1.0)
    @drv_hip = param("drv_hip", ~0.1, ~0.0, ~0.8)
    @pre_knee = param("pre_knee", ~0.0, ~0.0, ~0.5)
    @drv_swh = param("drv_swh", ~0.0, ~0.0, ~0.8)
    @drv_swk = param("drv_swk", ~0.0, ~0.0, ~0.8)
    @drv_pre = param("drv_pre", ~0.0, ~0.0, ~0.6)
    @v_cap = param("v_cap", ~3.3, ~2.5, ~10.0)
    @k_brake = param("k_brake", ~0.0, ~0.0, ~1.5)
    @z_ref = param("z_ref", ~0.92, ~0.8, ~1.0)
    @k_z = param("k_z", ~0.0, ~0.0, ~12.0)
    @k_vd = param("k_vd", ~0.0, ~0.0, ~1.0)
    @drv_floor = param("drv_floor", ~0.3, ~0.0, ~1.0)
    # swing leg
    @psi_fo = param("psi_fo", ~0.3, ~-0.3, ~0.9)
    @k_fo = param("k_fo", ~1.6, ~0.6, ~2.4)
    @a_fo = param("a_fo", ~0.2, ~-0.3, ~0.8)
    @psi_mid = param("psi_mid", ~0.8, ~0.3, ~1.3)
    @k_mid = param("k_mid", ~1.9, ~0.8, ~2.4)
    @psi_late = param("psi_late", ~0.8, ~0.3, ~1.3)
    @k_late = param("k_late", ~1.3, ~0.3, ~2.2)
    @psi_reach = param("psi_reach", ~0.05, ~-0.3, ~0.6)
    @psi_v = param("psi_v", ~0.1, ~0.0, ~0.25)
    @cv = param("cv", ~0.1, ~0.0, ~0.4)
    @k_reach = param("k_reach", ~0.35, ~0.1, ~0.8)
    @a_reach = param("a_reach", ~0.2, ~-0.3, ~0.6)
    # arms
    @arm = param("arm", ~1.2, ~0.2, ~1.8)
    @elbow = param("elbow", ~1.2, ~0.3, ~2.2)
    # timing (easing durations of the chunks) and servo
    @t_land = param("t_land", ~0.06, ~0.01, ~0.25)
    @t_push = param("t_push", ~0.1, ~0.03, ~0.25)
    # push chunks end on the foot's release or at these timeouts (with toes,
    # a v2 foot keeps rolling on the ball long after the push is spent)
    @t_push_max = param("t_push_max", ~0.3, ~0.08, ~0.3)
    @t0_max = param("t0_max", ~0.6, ~0.2, ~0.6)
    @t_flight = param("t_flight", ~0.12, ~0.03, ~0.35)
    @stiff = param("stiff", ~0.05, ~0.0, ~0.3)
    @stiff_st = param("stiff_st", ~0.1, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.05, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.1, ~0.0, ~0.35)
    @g_st = param("g_st", ~1.0, ~0.4, ~2.0)
    @g_sw = param("g_sw", ~0.8, ~0.2, ~1.5)
    @g_kl = param("g_kl", ~0.5, ~0.1, ~1.5)
    @g_al = param("g_al", ~0.7, ~0.1, ~1.5)
    @leg_kp = param("leg_kp", ~6.0, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.3, ~0.05, ~0.6)
    # smoothing time of the spring that eases the gait corrections in and out.
    # Until the SDK retimed the track's spring per chunk, only the first
    # correcting chunk's time (the stand chunk's 0.08) ever applied, so the
    # practised gaits ran at 0.08 and their old `spring` lines are unused
    @gait_spring = param("gait_spring", ~0.08, ~0.01, ~0.2)
    # v2 anatomy (toes, biarticular muscles); no effect on the v1 body
    @toe_land = param("toe_land", ~0.0, ~-0.6, ~0.4)
    @toe_push = param("toe_push", ~0.0, ~-0.8, ~0.4)
    @toe_fly = param("toe_fly", ~0.0, ~-0.8, ~0.4)
    @bi_gain = param("bi_gain", ~1.0, ~0.0, ~1.5)
    @drv_gas = param("drv_gas", ~0.0, ~0.0, ~1.0)
    @drv_toe = param("drv_toe", ~0.0, ~0.0, ~1.0)
    @drv_ham = param("drv_ham", ~0.0, ~0.0, ~1.0)
    @drv_rf = param("drv_rf", ~0.0, ~0.0, ~1.0)
    @drv_hamb = param("drv_hamb", ~0.0, ~0.0, ~1.0)
    # bounds (gait 1)
    @psi_drive = param("psi_drive", ~0.9, ~0.3, ~1.6)
    @k_drive = param("k_drive", ~1.6, ~0.5, ~2.4)
    @t_drive = param("t_drive", ~0.18, ~0.05, ~0.35)
    @t_soft = param("t_soft", ~0.06, ~0.0, ~0.2)
    @t_stance = param("t_stance", ~0.12, ~0.04, ~0.25)
    # one chunk per step (gait 2)
    @t_swing = param("t_swing", ~0.25, ~0.08, ~0.5)
    @t_kext = param("t_kext", ~0.15, ~0.0, ~0.4)
    @t_kdur = param("t_kdur", ~0.1, ~0.03, ~0.3)
    @t_step_min = param("t_step_min", ~0.15, ~0.05, ~0.3)
    @k_syn = param("k_syn", ~0.8, ~0.0, ~2.5)
    @k_trail = param("k_trail", ~0.8, ~0.0, ~2.0)
    # standing start
    @d_go = param("d_go", ~0.15, ~0.0, ~0.3)
    @drv0_knee = param("drv0_knee", ~0.0, ~0.0, ~1.0)
    @drv0_ankle = param("drv0_ankle", ~0.5, ~0.0, ~1.0)
    @drv0_hip = param("drv0_hip", ~0.2, ~0.0, ~1.0)
    @psi0 = param("psi0", ~0.6, ~0.2, ~1.2)
    @k0 = param("k0", ~0.9, ~0.3, ~2.3)
    self

  # ---- per-tick state -------------------------------------------------------

  -> before(frame, ctl)
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    if @t_go >= ~0.0
      @v_des = @v0 + @accel * (frame.t - @t_go)
      @v_des = @v_top if @v_des > @v_top
    # sprinters lean into the acceleration and rise as they reach speed
    @torso_des = @lean + @fall_lean + @lean_acc * (~1.0 - @v_des / @v_top)
    @z_err = @z_ref - frame.pelvis_height
    @lifted["l_"] = true if !frame.contact?("l_foot")
    @lifted["r_"] = true if !frame.contact?("r_foot")
    scale_drives(frame)
    self

  -> mark_go(frame)
    @t_go = frame.t

  # Every stride chunk announces its roles on entry: which leg is loaded
  # (firm: stance, or the landing leg in flight) and which swings (loose).
  -> enter(f, st, sw, phase)
    @st = st
    @sw = sw
    @phase = phase
    @t_phase = f.t
    self

  -> start_stride(f, st, sw)
    mark_go(f)
    enter(f, st, sw, :push)

  # Per-leg reflex gains. Rigid tendons store no energy, so the stance leg's
  # compliance has to come from the reflexes: a near-straight knee servoed at
  # full gain makes a leg several times stiffer than a human's (leg stiffness
  # K_knee / (dL/dq)^2), which bounces and brakes on every landing. The
  # landing leg's knee and ankle therefore run at low gain (a soft spring the
  # load flexes) from late flight through the land chunk, the hip stays firm
  # for the torso servo, the push chunk stiffens the whole leg, and the swing
  # leg is loose.
  -> after(frame, ctl)
    return self if @phase == nil
    firm = @st
    loose = @sw
    soft = @phase == :land
    soft = frame.t - @t_phase < @t_soft if @phase == :drive || @phase == :step
    airborne = @phase == :flight
    airborne = !frame.contact?(@st + "foot") if @phase == :step
    if airborne
      firm = @sw
      loose = @st
      soft = true
    g_st = @g_st
    g_sw = @g_sw
    g_kl = @g_st
    g_al = @g_st
    if soft
      g_kl = @g_kl
      g_al = @g_al
    @hip_idx[firm].each -> ctl.set_gain(item, g_st)
    @knee_idx[firm].each -> ctl.set_gain(item, g_kl)
    @ankle_idx[firm].each -> ctl.set_gain(item, g_al)
    @leg_idx[loose].each -> ctl.set_gain(item, g_sw)
    self

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))

  # ---- chunks ---------------------------------------------------------------

  # Quiet stance while the reflexes settle; the ankles hold the COM just
  # ahead of the ankle joints (the stand skill's ankle strategy).
  -> stand_chunk
    p = Pose.new
    ["l_", "r_"].each ->
      s = item
      p.set(s + "hip_flex", ~0.05, @stiff)
      p.set(s + "knee", ~0.12, @stiff)
      p.set(s + "ankle", ~-0.05, @stiff)
      p.set(s + "shoulder_flex", ~0.0, @stiff)
      p.set(s + "elbow", @elbow, @stiff)
    p.set("spine_flex", @spine, @stiff)
    ch = Chunk.new("stand", ~0.3).pose(p).hold_until(Latch.after(~0.5))
    ch.correct(->(f, c) balance(f, ~0.05), ~0.08)
    ch

  # Tip the whole body forward: the ankle strategy's COM target moves out
  # toward the toes and the trunk leans, until the COM is ahead of the ankles
  # by d_go and the first push starts.
  -> lean_chunk
    p = Pose.new
    ["l_", "r_"].each ->
      s = item
      p.set(s + "hip_flex", ~0.1, @stiff)
      p.set(s + "knee", ~0.2, @stiff)
      p.set(s + "ankle", ~-0.2, @stiff)
    p.set("spine_flex", @spine + ~0.15, @stiff)
    p.set("l_shoulder_flex", ~-0.3, @stiff)
    p.set("r_shoulder_flex", ~0.3, @stiff)
    ahead = Latch.test("com_ahead", ->(f, e, c) com_ahead?(f))
    ch = Chunk.new("lean", ~0.4).pose(p).hold_until(ahead.after_min(~0.1), ~1.5)
    ch.correct(->(f, c) balance(f, @d_go + ~0.1), ~0.08)
    ch

  -> feet_x(f)
    (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5

  -> com_ahead?(f)
    f.com_x - feet_x(f) > @d_go

  # Ankle strategy: plantarflex when the COM is ahead of its target, dorsiflex
  # when behind.
  -> balance(f, target)
    dq = ~2.0 * (f.com_x - feet_x(f) - target) + ~0.4 * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    off

  # Stance, early: land on the forefoot and yield into the knee spring.
  -> land_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_ms + @phi_nom, @k_land, @a_land - @fall_ankle, @stiff_st)
    p.set(st + "toe", @toe_land, @stiff_st)
    leg(p, sw, @psi_mid + @knee_lift + @phi_nom, tuck(@k_mid), ~-0.1, @stiff_sw)
    upper(p, st, sw)
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("over:" + st, ->(f, e, c) over_foot?(f, st))
    ch = Chunk.new(st + "land", @t_land).pose(p)
    ch.hold_until(Latch.any([rising, over]).after_min(@t_absorb), ~0.3)
    ch.drive(drive_vec([st + "knee_neg", @pre_knee]))
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :land), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :land))
    ch

  -> over_foot?(f, st)
    f.com_x - f.at(st + "foot_pos", 0) > @d_push

  # Stance, late: push off (knee extensors and plantarflexors burst).
  -> push_chunk(st, sw, first)
    p = Pose.new
    leg(p, st, @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    p.set(st + "toe", @toe_push, @stiff_st)
    leg(p, sw, @psi_late + @knee_lift + @phi_nom, @k_late, ~0.0, @stiff_sw)
    upper(p, st, sw)
    off = Latch.release(st + "foot")
    ch = Chunk.new(st + "push", @t_push).pose(p)
    ch.hold_until(off.after_min(~0.03), @t_push_max)
    ch.drive(push_drive(st))
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :push), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :push))
    if first
      p.set(sw + "hip_flex", @psi0 + @phi_nom, @stiff_sw)
      p.set(sw + "knee", @k0, @stiff_sw)
      ch = Chunk.new(st + "push", ~0.25).pose(p)
      ch.hold_until(off.after_min(~0.15), @t0_max)
      ch.drive(drive_vec([st + "knee_neg", @drv0_knee, st + "ankle_pos", @drv0_ankle, st + "hip_flex_neg", @drv0_hip,
                          st + "gas", @drv_gas, st + "toe_pos", @drv_toe]))
      ch.correct(->(f, c) stride_correction(f, c, st, sw, :push), @gait_spring)
      ch.on_enter(->(f, c) start_stride(f, st, sw))
    ch

  # Flight after `st` pushed off: `st` folds and follows through, `sw` reaches
  # for its landing angle.
  -> flight_chunk(st, sw, pose)
    p = pose
    p = flight_pose(st, sw) if p == nil
    touch = Latch.contact(sw + "foot")
    ch = Chunk.new(st + "flight", @t_flight).pose(p)
    ch.hold_until(touch.after_min(~0.03), ~0.45)
    # swing initiation (hip and knee flexors of the leg that just left the
    # ground) and pre-landing extensor activity on the leg about to land
    ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, sw + "knee_neg", @drv_pre,
                        st + "rf", @drv_rf, sw + "ham", @drv_hamb]))
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :flight), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :flight))
    ch

  # Swing-knee flexion with the heel tuck added (capped short of the limit).
  -> tuck(k)
    k2 = k + @heel_tuck
    return ~2.45 if k2 > ~2.45
    k2

  -> flight_pose(st, sw)
    p = Pose.new
    leg(p, st, @psi_fo + @phi_nom, tuck(@k_fo), @a_fo, @stiff_sw)
    p.set(st + "toe", @toe_fly, @stiff_sw)
    leg(p, sw, @psi_reach + @phi_nom, @k_reach, @a_reach, @stiff_st)
    p.set(sw + "toe", @toe_land, @stiff_st)
    upper(p, st, sw)

  # ---- alternating bounds (gait 1) ------------------------------------------
  #
  # A stride as two mirrored compound movements, each a bound off one leg:
  #
  #   l_drive ──(release l_foot)──> l_fly ──(contact r_foot)──> r_drive
  #   r_drive ──(release r_foot)──> r_fly ──(contact l_foot)──> l_drive ...
  #
  # four chunk decisions per stride instead of six. X_drive runs from X's
  # contact to its release: one goal (X's drive-off posture, the swing knee
  # driven up and tucked) and the push-off burst; for t_soft after contact
  # (the load) the knee and ankle are soft and the burst is held back, after
  # it they are firm and driven. That timed onset replaces the six-chunk
  # stride's land -> push latch. X_fly is the
  # flight: the landing leg reaches, the leg that drove folds its heel up.
  # The right bound's poses are the left bound's mirrored (Pose.mirror), so
  # the two bounds are exact mirror images; the corrections are the stride
  # corrections (torso, placement, speed, clearance) and the drive carries
  # the speed and height loops. (A bound cannot be one chunk: a chunk eases
  # monotonically toward one goal, but within a bound the stance knee must
  # yield then extend and the swing knee fold then open.)
  -> add_bounds(mv)
    drive_l = drive_pose("l_", "r_")
    fly_l = flight_pose("l_", "r_")
    drive_r = drive_pose("l_", "r_").mirror
    fly_r = flight_pose("l_", "r_").mirror
    mv.add(flight_chunk("l_", "r_", fly_l))
    mv.add(drive_chunk("r_", "l_", drive_r))
    mv.add(flight_chunk("r_", "l_", fly_r))
    mv.add(drive_chunk("l_", "r_", drive_l))
    mv

  # ---- one chunk per step (gait 2) -----------------------------------------
  #
  # The stride as two chunk decisions, each step one chunk from a foot's
  # contact to the other foot's contact:
  #
  #   l_step ──(contact r_foot)──> r_step ──(contact l_foot)──> l_step ...
  #
  # One goal per chunk: the stance leg's drive-off posture and the swing
  # leg's landing posture. Chunk#stagger gives the muscle groups their own
  # timing: the stance knee, ankle and toe extensors start t_soft late (the
  # load window, during which the burst is also held back), the swing hip
  # heads for its landing angle over t_swing, and the swing knee's extension
  # to the landing angle starts t_kext late. A knee has to fold before it
  # extends, which one goal cannot say, so a swing synergy correction flexes
  # the swing knee in proportion to how far its hip still has to travel (the
  # leg folds as the thigh swings and opens as it arrives), and the trailing
  # leg folds once its foot is off the ground. Corrections and gains read the
  # stance foot's contact continuously (stance behaviour while it is down,
  # flight behaviour after) without a chunk decision.
  -> add_steps(mv)
    step_l = step_pose("l_", "r_")
    step_r = step_pose("l_", "r_").mirror
    mv.add(step_chunk("r_", "l_", step_r))
    mv.add(step_chunk("l_", "r_", step_l))
    mv

  -> step_pose(st, sw)
    p = Pose.new
    leg(p, st, @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    p.set(st + "toe", @toe_push, @stiff_st)
    leg(p, sw, @psi_reach + @knee_lift + @phi_nom, @k_reach, @a_reach, @stiff_sw)
    p.set(sw + "toe", @toe_land, @stiff_sw)
    upper(p, st, sw)

  -> step_chunk(st, sw, pose)
    # a touchdown: the swing foot loads after having been off the ground
    # during this chunk (it may still be on the ground when the chunk starts)
    touch = Latch.test("touchdown:" + sw, ->(f, e, c) f.contact?(sw + "foot", ~0.05) && @lifted[sw])
    ch = Chunk.new(st + "step", @t_swing).pose(pose)
    ch.hold_until(touch.after_min(@t_step_min), ~0.7)
    ch.stagger(body.mask([st + "knee", st + "ankle", st + "gas", st + "toe"]), @t_soft)
    ch.stagger(body.mask([sw + "knee"]), @t_kext, :min_jerk, @t_kdur)
    ch.drive(push_drive(st))
    ch.correct(->(f, c) step_correction(f, c, st, sw), @gait_spring)
    ch.on_enter(->(f, c) enter_step(f, st, sw))
    ch

  -> enter_step(f, st, sw)
    @lifted[sw] = false
    enter(f, st, sw, :step)

  # Stance corrections while the stance foot is down, flight corrections
  # after, plus the swing synergy and the trailing-leg fold.
  -> step_correction(f, ctl, st, sw)
    down = f.contact?(st + "foot")
    phase = :flight
    phase = :push if down
    off = stride_correction(f, ctl, st, sw, phase)
    left = pair_angle(ctl.command.values, sw + "hip_flex") - q_of(f, sw + "hip_flex")
    left = ~0.0 if left < ~0.0
    left = ~1.5 if left > ~1.5
    joint_offset(off, sw + "knee", @k_syn * left)
    joint_offset(off, st + "knee", @k_trail) if !down
    off

  -> drive_pose(st, sw)
    p = Pose.new
    leg(p, st, @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    leg(p, sw, @psi_drive + @knee_lift + @phi_nom, tuck(@k_drive), ~0.0, @stiff_sw)
    upper(p, st, sw)

  -> drive_chunk(st, sw, pose)
    off = Latch.release(st + "foot")
    ch = Chunk.new(st + "drive", @t_drive).pose(pose).ease(@drive_ease)
    # the release only counts after a minimum stance (a landing bounces)
    ch.hold_until(off.after_min(@t_stance), ~0.45)
    ch.drive(push_drive(st))
    # torso servo on the stance hip, the swing thigh held in world frame; the
    # Raibert placement acts in the flight chunk, where the landing is set
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :land), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :drive))
    ch

  -> leg(p, side, hip, knee, ankle, stiff)
    p.set(side + "hip_flex", hip, stiff)
    p.set(side + "knee", knee, stiff)
    p.set(side + "ankle", ankle, stiff)
    p

  # Arms swing against the legs: the stance-side arm comes forward while the
  # stance leg sweeps back.
  -> upper(p, st, sw)
    p.set(st + "shoulder_flex", @arm, @stiff_up)
    p.set(sw + "shoulder_flex", ~0.0 - @arm * ~0.7, @stiff_up)
    p.set(st + "elbow", @elbow, @stiff_up)
    p.set(sw + "elbow", @elbow, @stiff_up)
    p.set("spine_flex", @spine, @stiff_up)
    p

  # The push-off burst grows with the speed plan (a jog barely leaves the
  # ground, a run flies) and with the speed deficit (thrust feedback). The skill owns the drive arrays and rescales them
  # every tick (see `before`).
  -> push_drive(st)
    d = drive_vec([st + "knee_neg", @drv_knee, st + "ankle_pos", @drv_ankle, st + "hip_flex_neg", @drv_hip])
    @drives.push([d, body.index(st + "knee_neg"), body.index(st + "ankle_pos"), body.index(st + "hip_flex_neg"),
                  index_or(st + "gas"), index_or(st + "toe_pos"), index_or(st + "ham")])
    d

  -> index_or(name)
    return body.index(name) if body.has?(name)
    -1

  -> scale_drives(frame)
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @v_top, ~0.0, ~1.0)
    # thrust feedback: push harder while slower than the plan
    s = clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)
    # a bound's burst starts after its load window (see drive_chunk)
    s = ~0.0 if (@phase == :drive || @phase == :step) && frame.t - @t_phase < @t_soft
    # hop-height regulation (Raibert's thrust loop): extend harder while the
    # pelvis rides below its reference height, softer while above it
    h = @k_z * @z_err
    @drives.each ->(e)
      d = e[0]
      d[e[1]] = clamp(@drv_knee * s + h, ~0.0, ~1.0)
      d[e[2]] = clamp(@drv_ankle * s + h, ~0.0, ~1.0)
      d[e[3]] = @drv_hip * s
      d[e[4]] = clamp(@drv_gas * s + h, ~0.0, ~1.0) if e[4] >= 0
      d[e[5]] = @drv_toe * s if e[5] >= 0
      d[e[6]] = @drv_ham * s if e[6] >= 0
    self

  -> drive_vec(pairs)
    d = zeros
    i = 0
    while i < pairs.size
      d[body.index(pairs[i])] = pairs[i + 1] if body.has?(pairs[i])
      i += 2
    d

  # ---- corrections ----------------------------------------------------------

  # Offsets for one tick of a stride chunk (phase :land, :push or :flight).
  # In stance the stance hip servoes the torso and the swing hip holds its
  # thigh angle in world frame (pelvis pitch compensated). In flight nothing
  # anchors the pelvis, and compensating it would be positive feedback (a
  # backward-pitching pelvis would swing the legs back, pitching it further),
  # so the landing leg is placed in pelvis frame and the trailing leg, whose
  # angle matters least, becomes the reaction mass of a torso servo.
  -> stride_correction(f, ctl, st, sw, phase)
    off = zeros
    place = @psi_v * @v_f + @cv * (@v_f - @v_des)
    # speed brake: above v_cap the landing foot moves forward (Raibert's
    # regulation acting one-sided, so the gait cannot run away)
    place = place + @k_brake * (@v_f - @v_cap) if @v_f > @v_cap
    if phase == :flight
      fly = ~0.0 - @k_fly * (f.torso_pitch - @torso_des) - @k_fly_d * f.torso_pitch_rate
      joint_offset(off, st + "hip_flex", fly)
      # swing-leg retraction: once the reach pose is reached the landing leg
      # keeps sweeping back, so the foot meets the ground moving backward
      late = f.t - @t_phase - @t_flight
      late = ~0.0 if late < ~0.0
      ret = ~0.0 - @retract * late
      joint_offset(off, sw + "hip_flex", place + ret + @comp_fly * (pelvis_pitch(f) - @phi_ref))
      toe_clearance(f, off, st)
      return off
    comp = pelvis_pitch(f) - @phi_ref
    torso = torso_servo(f, ctl, st + "hip_flex") - @k_swc * servo_error(f, ctl, sw + "hip_flex")
    joint_offset(off, st + "hip_flex", torso)
    place = ~0.0 if phase == :land
    joint_offset(off, sw + "hip_flex", comp + place)
    toe_clearance(f, off, sw)
    off

  # Toe clearance, a withdrawal reflex on the swinging leg: when its ankle
  # drops below `clear_h` the knee flexes and the ankle dorsiflexes in
  # proportion, lifting the toe before it drags.
  -> toe_clearance(f, off, side)
    low = @clear_h - f.at(side + "foot_pos", 2)
    return off if low <= ~0.0
    joint_offset(off, side + "knee", @k_clear * low)
    joint_offset(off, side + "ankle", ~0.0 - @k_clear * low)
    off

  # Servo error of a joint (last commanded target angle minus measured angle),
  # proportional to the torque its muscles are producing. SIMBICON's stance
  # hip cancels the swing hip's reaction on the pelvis: tau_st = -tau_torso -
  # tau_swing; the same muscles on both hips make the ratio about one.
  -> servo_error(f, ctl, joint)
    pair_angle(ctl.target, joint) - q_of(f, joint)

  # Joint angles read through the joint's own antagonist pair (`<joint>_pos`
  # and `_neg`, looked up by name so a biarticular muscle naming the same
  # primary joint can never stand in for the pair), or on bodies with muscle
  # geometry from the q / qd sensors.
  -> pair_angle(values, joint)
    p = body.index(joint + "_pos")
    n = body.index(joint + "_neg")
    qa = body.muscle(p).angle_at(values[p])
    qb = body.muscle(n).angle_at(values[n])
    (qa + qb) * ~0.5

  -> q_of(f, joint)
    return f.q(body, joint) if body.geometry != nil
    p = body.index(joint + "_pos")
    body.muscle(p).angle_at(f.c(p))

  -> qd_of(f, joint)
    return f.qd(body, joint) if body.geometry != nil
    p = body.index(joint + "_pos")
    m = body.muscle(p)
    f.cdot(p) * (m.qmax - m.qmin)

  # World-frame stance hip: hold the measured angle (led by its velocity) and
  # add a PD on torso pitch, so the hip's torque answers only to the torso.
  -> torso_servo(f, ctl, joint)
    q = q_of(f, joint)
    qd = qd_of(f, joint)
    qc = pair_angle(ctl.command.values, joint)
    err = f.torso_pitch - @torso_des
    q + @hip_lead * qd - qc - @torso_kp * err - @torso_kd * f.torso_pitch_rate
