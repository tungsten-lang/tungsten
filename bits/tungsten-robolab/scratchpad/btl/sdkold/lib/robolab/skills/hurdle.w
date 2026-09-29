# Hurdle: run a flight of hurdles on the planar (sagittal) muscle body.
#
# One track drives every muscle through one movement of contraction chunks:
# pose goals eased min-jerk (all muscles moving at once), transitions latched
# on sensation, and spring-eased real-time corrections on top. The running
# gait between hurdles is the SIMBICON / Raibert chunk gait of RunSkill
# (lib/robolab/skills/run.w), whose ideas and practised numbers are copied
# here; the hurdle skill adds the clearance chunks, the distance-latched
# take-off and the stride planner.
#
#   start      set (quiet stance) -> lean (COM d_go ahead of the ankles) ->
#              gun (first push off the left foot) -> l_flight
#   run        l_flight -> r_land -> r_push -> r_flight -> l_land -> l_push,
#              looping. land: soft knee and ankle yield (latched on the COM
#              rising or passing the foot); push: the stance leg stiffens and
#              extends with a drive burst (latched on the foot releasing);
#              flight: the landing leg reaches (latched on its contact)
#   clearance  L_plant, L_attack, L_lead, L_trail, L_snap, L_land (left leg
#              leads, the right foot takes off) and the mirror R_* (right leg
#              leads):
#                plant   the take-off foot lands (planted further ahead on a
#                        straighter knee, see `att_reach`) and loads while the
#                        lead knee swings forward folded (latched like land)
#                attack  take-off push: a drive burst on the take-off leg's
#                        extensors and the lead hip flexors (the knee drive),
#                        trunk leaning in (latched on the take-off foot
#                        releasing)
#                lead    the lead leg extends over the bar, the trunk dips,
#                        the trail knee folds (latched on the lead foot
#                        passing the bar)
#                trail   the trail leg tucks and is pulled through while the
#                        lead leg comes down (latched on the pelvis passing
#                        the bar)
#                snap    the lead leg snaps down to land, trail knee high
#                        (latched on the lead foot's contact)
#                land    stance on the lead leg with a firmer trunk servo,
#                        then back into the run at that leg's push
#
# The body is planar: the trail leg cannot abduct around the hurdle as a
# real hurdler's does. It tucks in the sagittal plane instead (hip flexed to
# bring the thigh level, knee folded heel to buttock) and passes over the bar
# under the pelvis.
#
# Latches: foot contact / release, COM vertical velocity and position, and the
# task's `hurdle` sensor (distance to and height of the next bar). The
# take-off is latched on that distance: the first touchdown inside the
# take-off window (closer than d_to + half a stride) becomes the attack step,
# whichever foot it is, and the other leg leads.
#
# Corrections (contraction offsets recomputed every tick, eased in by the
# track's critically damped spring):
#   torso      in stance the stance hip is a torso-pitch servo (its target is
#              the measured angle plus a PD on torso pitch, minus the swing
#              hip's reaction, SIMBICON's tau_st = -tau_torso - tau_swing);
#              in flight the trailing leg is the servo's reaction mass
#   placement  the landing hip reaches with speed (Raibert's neutral point
#              psi_v v plus cv (v - v*)), retracts late in flight, and brakes
#              above v_cap
#   stride     at every touchdown the planner splits the distance left to
#              the take-off spot (bar - d_to) into the nearest whole number
#              of steps n and aims the next landing at foot + d / n; in
#              flight the landing hip is nudged (w_stride, capped at
#              max_adj m) toward that target, and when n = 1 (the attack
#              step) the landing hip reaches att_reach further on a knee
#              att_knee straighter
#   over bar   each leg still short of the bar is lifted in proportion to
#              how far its sole sits below bar height + clear_want (sensed
#              foot height against sensed bar height): the lead hip flexes,
#              the trail knee folds and its hip flexes (kept up through the
#              snap-down and landing until the trail foot is past); the arms
#              servo pitch
#   toes       a withdrawal reflex lifts a swinging foot that drops too low
#
# Reflex gains are set per leg and phase each tick (soft landing knee and
# ankle, firm stance hip and push, loose swing leg; g_air for both legs over
# the bar).

+ HurdleSkill < Skill
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
    @st = "l_"
    @sw = "r_"
    @stride = @step0
    @last_foot = ~-99.0
    @has_target = false
    @target_x = ~0.0
    @bar_x = ~99.0
    @bar_h = ~0.0
    @steps_left = 0
    @r_from = []
    @r_latch = []
    @r_to = []
    @r_max = []
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle"])
      @hip_idx[side] = body.mask([side + "hip"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle"])
    routed = Latch.test("routed", ->(f, e, c) false)

    mv = Movement.new("hurdle")
    mv.add(stand_chunk)
    mv.add(lean_chunk)
    mv.add(gun_chunk(routed))
    # clearances (right leg leading, then left); each lands into the run
    # through the router
    hurdle_chunks(mv, "r_", "l_", routed)
    hurdle_chunks(mv, "l_", "r_", routed)
    cycle = mv.size
    mv.add(flight_chunk("l_", "r_"))
    mv.add(land_chunk("r_", "l_"))
    mv.add(push_chunk("r_", "l_"))
    mv.add(flight_chunk("r_", "l_"))
    mv.add(land_chunk("l_", "r_"))
    mv.add(push_chunk("l_", "r_"))
    mv.loop_from(cycle)
    @track = ctl.add_track(Track.new("body", mv, body.all))
    self

  -> read_params
    # ---- the run (RunSkill's gait; defaults are the practised params/hurdle.txt) ----
    # speed plan
    @v_top = param("v_top", ~4.406905592775882, ~2.5, ~7.0)
    @v0 = param("v0", ~2.37655887235429, ~0.0, ~2.5)
    @accel = param("accel", ~3.3591981074872392, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.02, ~0.02, ~0.5)
    # torso
    @lean = param("lean", ~0.007543181880472691, ~-0.1, ~0.4)
    @lean_acc = param("lean_acc", ~0.04379166411121158, ~0.0, ~0.6)
    @spine = param("spine", ~0.23767365174209099, ~-0.2, ~0.4)
    @torso_kp = param("torso_kp", ~2.682851574427365, ~0.3, ~3.0)
    @torso_kd = param("torso_kd", ~0.49167838251100643, ~0.05, ~0.5)
    @hip_lead = param("hip_lead", ~0.04798649327930726, ~0.0, ~0.12)
    @k_swc = param("k_swc", ~0.18921218965125802, ~0.0, ~1.5)
    @k_fly = param("k_fly", ~1.016492892499366, ~0.0, ~1.5)
    @clear_h = param("clear_h", ~0.12165027310736891, ~0.08, ~0.3)
    @k_clear = param("k_clear", ~7.020488300047592, ~0.0, ~12.0)
    @retract = param("retract", ~0.202105695529492, ~0.0, ~6.0)
    @comp_fly = param("comp_fly", ~0.032924462796281084, ~0.0, ~1.0)
    @k_fly_d = param("k_fly_d", ~0.10185867764682964, ~0.0, ~0.4)
    @phi_nom = @lean - @spine
    # stance leg
    @d_push = param("d_push", ~-0.08974623364463248, ~-0.2, ~0.4)
    @vz_push = param("vz_push", ~-0.25950207144645787, ~-0.4, ~0.4)
    @t_absorb = param("t_absorb", ~0.0886916727847189, ~0.0, ~0.15)
    @k_land = param("k_land", ~0.532884809649035, ~0.2, ~0.9)
    @a_land = param("a_land", ~0.5, ~-0.3, ~0.5)
    @k_push = param("k_push", ~0.1567752285678842, ~0.0, ~0.5)
    @a_push = param("a_push", ~0.5360854851265571, ~0.2, ~0.9)
    @psi_ms = param("psi_ms", ~0.1620140588580511, ~-0.3, ~0.5)
    @psi_to = param("psi_to", ~-0.09057643365951695, ~-0.8, ~0.0)
    @drv_knee = param("drv_knee", ~0.18585239244410512, ~0.0, ~1.0)
    @drv_ankle = param("drv_ankle", ~0.26320989720107457, ~0.0, ~1.0)
    @drv_hip = param("drv_hip", ~0.771169542387818, ~0.0, ~0.8)
    @pre_knee = param("pre_knee", ~0.17053929590806316, ~0.0, ~0.5)
    @drv_swh = param("drv_swh", ~0.1295117883657517, ~0.0, ~0.8)
    @drv_swk = param("drv_swk", ~0.2737183673378649, ~0.0, ~0.8)
    @drv_pre = param("drv_pre", ~0.25961345871320174, ~0.0, ~0.6)
    @v_cap = param("v_cap", ~4.285467241301644, ~2.5, ~7.0)
    @k_brake = param("k_brake", ~0.06337767813566131, ~0.0, ~1.5)
    @z_ref = param("z_ref", ~0.8786273863664321, ~0.8, ~1.0)
    @k_z = param("k_z", ~1.190034329719078, ~0.0, ~12.0)
    @k_vd = param("k_vd", ~0.182876536984735, ~0.0, ~1.0)
    @drv_floor = param("drv_floor", ~0.1287978977869921, ~0.0, ~1.0)
    # swing leg
    @psi_fo = param("psi_fo", ~0.4182375067742195, ~-0.3, ~0.9)
    @k_fo = param("k_fo", ~0.6080083830712405, ~0.6, ~2.4)
    @a_fo = param("a_fo", ~0.4899994630269859, ~-0.3, ~0.8)
    @psi_mid = param("psi_mid", ~0.6433328103549981, ~0.3, ~1.3)
    @k_mid = param("k_mid", ~1.5662455376666164, ~0.8, ~2.4)
    @psi_late = param("psi_late", ~0.4390469609154369, ~0.3, ~1.3)
    @k_late = param("k_late", ~0.3932342596947297, ~0.3, ~2.2)
    @psi_reach = param("psi_reach", ~0.5525466100995138, ~-0.3, ~0.6)
    @psi_v = param("psi_v", ~0.02596274103392418, ~0.0, ~0.25)
    @cv = param("cv", ~0.24468201571697132, ~0.0, ~0.4)
    @k_reach = param("k_reach", ~0.12568141209801847, ~0.1, ~0.8)
    @a_reach = param("a_reach", ~0.5829553888506562, ~-0.3, ~0.6)
    # arms
    @arm = param("arm", ~1.283409650900181, ~0.2, ~1.8)
    @elbow = param("elbow", ~1.8812103504408335, ~0.3, ~2.2)
    # timing (easing durations of the chunks) and servo
    @t_land = param("t_land", ~0.03649885922095192, ~0.01, ~0.25)
    @t_push = param("t_push", ~0.19282864100147534, ~0.03, ~0.25)
    @t_flight = param("t_flight", ~0.2984074354125491, ~0.03, ~0.35)
    @stiff = param("stiff", ~0.20166499687639322, ~0.0, ~0.3)
    @stiff_st = param("stiff_st", ~0.2553522472046452, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.20460912249559152, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.32424543224444213, ~0.0, ~0.35)
    @g_st = param("g_st", ~0.5390001921658657, ~0.4, ~2.0)
    @g_sw = param("g_sw", ~0.9806270599391884, ~0.2, ~1.5)
    @g_kl = param("g_kl", ~1.2737501722211964, ~0.1, ~1.5)
    @g_al = param("g_al", ~0.2160298574893581, ~0.1, ~1.5)
    @leg_kp = param("leg_kp", ~5.464832623255166, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.16225756487000187, ~0.05, ~0.6)
    # Correction spring for the run and clearance chunks. Until the SDK honoured
    # per-chunk spring times, every chunk ran with the first correcting chunk's
    # 0.08 s (the old `spring` param was never applied), so 0.08 is the value
    # this skill was practised with.
    @spring = param("gait_spring", ~0.08, ~0.01, ~0.2)
    # standing start
    @d_go = param("d_go", ~0.19609729528034694, ~0.0, ~0.3)
    @drv0_knee = param("drv0_knee", ~0.08305777776194063, ~0.0, ~1.0)
    @drv0_ankle = param("drv0_ankle", ~0.8912526677265549, ~0.0, ~1.0)
    @drv0_hip = param("drv0_hip", ~0.893547396148237, ~0.0, ~1.0)
    @psi0 = param("psi0", ~0.7921332494551663, ~0.2, ~1.2)
    @k0 = param("k0", ~1.8304416585033976, ~0.3, ~2.3)
    # ---- hurdling ----
    # stride planning toward each take-off
    @step0 = param("step0", ~1.327405601748393, ~0.5, ~1.6)
    @d_to = param("d_to", ~0.8631958683821171, ~0.5, ~2.2)
    @w_stride = param("w_stride", ~0.0, ~0.0, ~1.0)
    @max_adj = param("max_adj", ~0.11797714637839934, ~0.0, ~0.3)
    @step_min = param("step_min", ~0.7003575082675699, ~0.4, ~1.2)
    @step_max = param("step_max", ~1.5391753079428343, ~0.9, ~2.2)
    @leg_len = param("leg_len", ~0.9, ~0.75, ~0.98)
    # plant + attack: take-off stance on the trail leg, lead knee driven up
    @pl_ld_hip = param("pl_ld_hip", ~1.6, ~0.0, ~1.6)
    @att_reach = param("att_reach", ~0.5018880468878735, ~-0.2, ~0.6)
    @att_knee = param("att_knee", ~-0.1296535530856082, ~-0.3, ~0.5)
    @g_plant = param("g_plant", ~0.9977052767397727, ~0.3, ~2.5)
    @pl_ld_knee = param("pl_ld_knee", ~2.5, ~0.8, ~2.5)
    @att_t = param("att_t", ~0.1832876966025657, ~0.04, ~0.3)
    @att_min = param("att_min", ~0.12341481315122525, ~0.0, ~0.15)
    @att_max = param("att_max", ~0.17498851842746216, ~0.1, ~0.6)
    @att_drive = param("att_drive", ~1.0, ~0.0, ~1.0)
    @att_ld_drive = param("att_ld_drive", ~0.9796911192639185, ~0.0, ~1.0)
    @att_pitch = param("att_pitch", ~0.09606786237574844, ~-0.2, ~0.5)
    @att_st_hip = param("att_st_hip", ~-0.4569880182987694, ~-0.6, ~0.4)
    @att_st_knee = param("att_st_knee", ~0.0, ~0.0, ~0.6)
    @att_st_ank = param("att_st_ank", ~0.42916495909164026, ~0.0, ~0.9)
    @att_ld_hip = param("att_ld_hip", ~1.1786393266760338, ~0.8, ~2.2)
    @att_ld_knee = param("att_ld_knee", ~2.4, ~0.6, ~2.4)
    @att_arm = param("att_arm", ~2.4681298414416455, ~0.3, ~2.5)
    @h_arm_b = param("h_arm_b", ~-0.5465999163847852, ~-1.0, ~0.3)
    @att_lean = param("att_lean", ~0.260442205507987, ~0.0, ~0.9)
    # lead: lead leg extends over the bar, trunk dips, trail knee folds
    @lead_t = param("lead_t", ~0.2963382749105744, ~0.04, ~0.3)
    @lead_max = param("lead_max", ~0.4964916754491778, ~0.1, ~0.6)
    @lead_clear = param("lead_clear", ~-0.06866336124038519, ~-0.2, ~0.5)
    @lead_hip = param("lead_hip", ~1.5005234139689732, ~0.8, ~2.2)
    @lead_knee = param("lead_knee", ~0.33899475921353733, ~0.0, ~1.2)
    @lead_tr_hip = param("lead_tr_hip", ~-0.5489336902175692, ~-0.6, ~0.6)
    @lead_tr_knee = param("lead_tr_knee", ~2.2093397086187374, ~1.0, ~2.5)
    @dip = param("dip", ~0.07891812135084511, ~0.0, ~1.0)
    # trail: trail leg tucked and pulled through, lead leg down
    @trail_t = param("trail_t", ~0.08814765482686053, ~0.04, ~0.35)
    @trail_max = param("trail_max", ~0.21144493981754167, ~0.1, ~0.7)
    @trail_clear = param("trail_clear", ~-0.3, ~-0.3, ~0.5)
    @trail_hip = param("trail_hip", ~1.2399535930002443, ~0.6, ~2.2)
    @trail_knee = param("trail_knee", ~2.453673098944126, ~1.5, ~2.5)
    @trail_ld_hip = param("trail_ld_hip", ~0.1438348834701062, ~-0.2, ~1.4)
    @trail_lean = param("trail_lean", ~0.0, ~0.0, ~1.0)
    # snap-down landing on the lead leg
    @snap_t = param("snap_t", ~0.12162188659934757, ~0.03, ~0.3)
    @snap_ld_ank = param("snap_ld_ank", ~-0.09632432895816437, ~-0.3, ~0.7)
    @snap_ld_hip = param("snap_ld_hip", ~0.05029200070149842, ~-0.5, ~0.4)
    @snap_ld_knee = param("snap_ld_knee", ~0.1825409600893316, ~0.0, ~1.0)
    @snap_tr_hip = param("snap_tr_hip", ~1.3966035355724977, ~0.4, ~1.8)
    @snap_tr_knee = param("snap_tr_knee", ~2.3691961535423918, ~0.6, ~2.4)
    # landing stance on the lead leg
    @hl_knee = param("hl_knee", ~0.3737325937616084, ~0.1, ~1.3)
    @hl_tr_hip = param("hl_tr_hip", ~0.9411400393339779, ~-0.2, ~1.4)
    @hl_pitch = param("hl_pitch", ~-0.24252863943215175, ~-0.5, ~0.3)
    @hl_k = param("hl_k", ~2.00889694867999, ~0.5, ~3.0)
    # sensed clearance corrections over the bar, arm pitch servo, air gains
    @clear_want = param("clear_want", ~0.2950179429201439, ~0.0, ~0.3)
    @k_lead = param("k_lead", ~2.198722138012803, ~0.0, ~6.0)
    @k_trail = param("k_trail", ~3.398068712880076, ~0.0, ~6.0)
    @k_trail_h = param("k_trail_h", ~0.0, ~0.0, ~6.0)
    @k_arm = param("k_arm", ~0.31608889606331736, ~0.0, ~3.0)
    @k_arm_d = param("k_arm_d", ~0.0, ~0.0, ~0.5)
    @g_air = param("g_air", ~0.5703704008609813, ~0.3, ~2.0)
    self

  # ---- per-tick state -------------------------------------------------------

  -> before(frame, ctl)
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    if @t_go >= ~0.0
      @v_des = @v0 + @accel * (frame.t - @t_go)
      @v_des = @v_top if @v_des > @v_top
    # sprinters lean into the acceleration and rise as they reach speed
    @torso_des = @lean + @lean_acc * (~1.0 - @v_des / @v_top)
    @z_err = @z_ref - frame.pelvis_height
    scale_drives
    route_events(frame, ctl)

  # Chunk ends the skill decides (see `route`), then the take-off: the foot
  # that has just landed is inside the take-off window.
  -> route_events(frame, ctl)
    tr = @track
    name = tr.chunk_name
    i = 0
    while i < @r_from.size
      if @r_from[i] == name
        e = tr.elapsed(frame)
        if e > @r_max[i] || @r_latch[i].fired?(frame, e, ctl)
          tr.jump(ctl, frame, @r_to[i])
          return self
      i += 1
    if name == "l_flight" && frame.get("r_foot_contact") > ~0.05 && takeoff_due(frame, "r_")
      tr.jump(ctl, frame, "L_plant")
    elsif name == "r_flight" && frame.get("l_foot_contact") > ~0.05 && takeoff_due(frame, "l_")
      tr.jump(ctl, frame, "R_plant")
    self

  # When `latch` fires in chunk `from` (or after `timeout` s), jump to chunk
  # `to` instead of advancing to the next chunk in the list.
  -> route(from, latch, to, timeout)
    @r_from.push(from)
    @r_latch.push(latch)
    @r_to.push(to)
    @r_max.push(timeout)
    self

  -> mark_go(frame)
    @t_go = frame.t

  # Every chunk announces its roles on entry: which leg is loaded (firm:
  # stance, or the landing leg in flight) and which swings (loose).
  -> enter(f, st, sw, phase)
    @st = st
    @sw = sw
    @phase = phase
    @t_phase = f.t
    self

  -> start_stride(f, st, sw)
    mark_go(f)
    enter(f, st, sw, :push)

  -> land_enter(f, c, st, sw)
    enter(f, st, sw, :land)
    touchdown(f, c, st)

  # Per-leg reflex gains (RunSkill): a soft landing knee and ankle, a firm
  # stance hip and push, a loose swing leg; over the bar both legs run at
  # g_air.
  -> after(frame, ctl)
    return self if @phase == nil
    if @phase == :air
      @leg_idx["l_"].each -> ctl.set_gain(item, @g_air)
      @leg_idx["r_"].each -> ctl.set_gain(item, @g_air)
      return self
    if @phase == :attack
      # take-off leg firm, lead leg driven hard
      @leg_idx[@st].each -> ctl.set_gain(item, @g_plant)
      @leg_idx[@sw].each -> ctl.set_gain(item, @g_air)
      return self
    firm = @st
    loose = @sw
    soft = @phase == :land
    if @phase == :flight
      firm = @sw
      loose = @st
      soft = true
    g_kl = @g_st
    g_al = @g_st
    if soft
      g_kl = @g_kl
      g_al = @g_al
    g_st = @g_st
    @hip_idx[firm].each -> ctl.set_gain(item, g_st)
    @knee_idx[firm].each -> ctl.set_gain(item, g_kl)
    @ankle_idx[firm].each -> ctl.set_gain(item, g_al)
    @leg_idx[loose].each -> ctl.set_gain(item, @g_sw)
    self

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))

  # ---- start ------------------------------------------------------------------

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
    Chunk.new("set", ~0.3).pose(p).hold_until(Latch.after(~0.5)).correct(->(f, c) balance(f, ~0.05), ~0.08)

  # Tip the whole body forward until the COM is d_go ahead of the ankles.
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
    Chunk.new("lean", ~0.4).pose(p).hold_until(ahead.after_min(~0.1), ~1.5).correct(->(f, c) balance(f, @d_go + ~0.1), ~0.08)

  # The first push off the left foot (the right leg swings through); routed
  # to l_flight when the left foot releases.
  -> gun_chunk(routed)
    p = Pose.new
    leg(p, "l_", @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    leg(p, "r_", @psi0 + @phi_nom, @k0, ~0.0, @stiff_sw)
    upper(p, "l_", "r_")
    route("gun", Latch.release("l_foot").after_min(~0.15), "l_flight", ~0.6)
    Chunk.new("gun", ~0.25).pose(p).hold_until(routed).drive(drive_vec(["l_knee_neg", @drv0_knee, "l_ankle_pos", @drv0_ankle, "l_hip_flex_neg", @drv0_hip])).correct(->(f, c) stride_correction(f, c, "l_", "r_", :push), @spring).on_enter(->(f, c) start_stride(f, "l_", "r_"))

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

  # ---- the run (RunSkill's stride chunks) -----------------------------------

  # Stance, early: land on the forefoot and yield into the knee spring.
  -> land_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_ms + @phi_nom, @k_land, @a_land, @stiff_st)
    leg(p, sw, @psi_mid + @phi_nom, @k_mid, ~-0.1, @stiff_sw)
    upper(p, st, sw)
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("over:" + st, ->(f, e, c) over_foot?(f, st))
    Chunk.new(st + "land", @t_land).pose(p).hold_until(Latch.any([rising, over]).after_min(@t_absorb), ~0.3).drive(drive_vec([st + "knee_neg", @pre_knee])).correct(->(f, c) stride_correction(f, c, st, sw, :land), @spring).on_enter(->(f, c) land_enter(f, c, st, sw))

  -> over_foot?(f, st)
    f.com_x - f.at(st + "foot_pos", 0) > @d_push

  # Stance, late: push off (knee extensors and plantarflexors burst).
  -> push_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    leg(p, sw, @psi_late + @phi_nom, @k_late, ~0.0, @stiff_sw)
    upper(p, st, sw)
    off = Latch.release(st + "foot")
    Chunk.new(st + "push", @t_push).pose(p).hold_until(off.after_min(~0.03), ~0.3).drive(push_drive(st)).correct(->(f, c) stride_correction(f, c, st, sw, :push), @spring).on_enter(->(f, c) enter(f, st, sw, :push))

  # Flight after `st` pushed off: `st` folds and follows through, `sw` reaches
  # for its landing angle.
  -> flight_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_fo + @phi_nom, @k_fo, @a_fo, @stiff_sw)
    leg(p, sw, @psi_reach + @phi_nom, @k_reach, @a_reach, @stiff_st)
    upper(p, st, sw)
    touch = Latch.contact(sw + "foot")
    Chunk.new(st + "flight", @t_flight).pose(p).hold_until(touch.after_min(~0.03), ~0.45).drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, sw + "knee_neg", @drv_pre])).correct(->(f, c) stride_correction(f, c, st, sw, :flight), @spring).on_enter(->(f, c) enter(f, st, sw, :flight))

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

  # The push-off burst grows with the speed plan and the speed deficit; the
  # skill owns the drive arrays and rescales them every tick.
  -> push_drive(st)
    d = drive_vec([st + "knee_neg", @drv_knee, st + "ankle_pos", @drv_ankle, st + "hip_flex_neg", @drv_hip])
    @drives.push([d, body.index(st + "knee_neg"), body.index(st + "ankle_pos"), body.index(st + "hip_flex_neg")])
    d

  -> scale_drives
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @v_top, ~0.0, ~1.0)
    # thrust feedback: push harder while slower than the plan
    s = clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)
    # hop-height regulation (Raibert's thrust loop)
    h = @k_z * @z_err
    @drives.each ->(e)
      d = e[0]
      d[e[1]] = clamp(@drv_knee * s + h, ~0.0, ~1.0)
      d[e[2]] = clamp(@drv_ankle * s + h, ~0.0, ~1.0)
      d[e[3]] = @drv_hip * s
    self

  -> drive_vec(pairs)
    d = zeros
    i = 0
    while i < pairs.size
      d[body.index(pairs[i])] = pairs[i + 1]
      i += 2
    d

  -> other(side)
    return "r_" if side == "l_"
    "l_"

  # ---- clearance ----------------------------------------------------------------

  # One clearance with `ld` leading and `tr` (the take-off foot) trailing;
  # the landing chunk hands over to ld's push through the router.
  -> hurdle_chunks(mv, ld, tr, routed)
    p = hname(ld)
    # plant: the take-off foot lands and loads like any stance (the knee
    # yields) while the lead knee is already driving forward
    rise = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over_tr = Latch.test("over:" + tr, ->(f, e, c) over_foot?(f, tr))
    mv.add(Chunk.new(p + "plant", @t_land).pose(plant_pose(ld, tr)).hold_until(Latch.any([rise, over_tr]).after_min(@t_absorb), ~0.3).correct(->(f, c) attack_corr(f, c, ld, tr), @spring).on_enter(->(f, c) attack_enter(f, c, ld, tr)))
    attack = Latch.release(tr + "foot").after_min(@att_min)
    push = drive_vec([tr + "knee_neg", @att_drive, tr + "ankle_pos", @att_drive, tr + "hip_flex_neg", @att_drive * ~0.5, ld + "hip_flex_pos", @att_ld_drive])
    mv.add(Chunk.new(p + "attack", @att_t).pose(attack_pose(ld, tr)).drive(push).hold_until(attack, @att_max).correct(->(f, c) attack_corr(f, c, ld, tr), @spring))
    lead = Latch.test("lead_over", ->(f, e, c) past_bar(f, ld + "foot_pos", @lead_clear))
    mv.add(Chunk.new(p + "lead", @lead_t).pose(lead_pose(ld, tr)).hold_until(lead, @lead_max).correct(->(f, c) air_corr(f, c, ld, tr), @spring).on_enter(->(f, c) enter(f, tr, ld, :air)))
    trail = Latch.test("trail_over", ->(f, e, c) past_bar(f, "pelvis_pos", @trail_clear))
    mv.add(Chunk.new(p + "trail", @trail_t).pose(trail_pose(ld, tr)).hold_until(trail, @trail_max).correct(->(f, c) air_corr(f, c, ld, tr), @spring))
    mv.add(Chunk.new(p + "snap", @snap_t).pose(snap_pose(ld, tr)).hold_until(Latch.contact(ld + "foot"), ~0.8).correct(->(f, c) snap_corr(f, c, ld, tr), @spring).on_enter(->(f, c) enter(f, tr, ld, :flight)))
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("over:" + ld, ->(f, e, c) over_foot?(f, ld))
    route(p + "land", Latch.any([rising, over]).after_min(@t_absorb), ld + "push", ~0.35)
    mv.add(Chunk.new(p + "land", @t_land).pose(h_land_pose(ld, tr)).hold_until(routed).correct(->(f, c) land_corr(f, c, ld, tr), @spring).on_enter(->(f, c) land_enter(f, c, ld, tr)))
    mv

  -> hname(ld)
    return "L_" if ld == "l_"
    "R_"

  # Hurdle upper body: `fwd` side's arm reaches forward, spine as given.
  -> h_upper(p, fwd, spine, arm_f)
    p.set(fwd + "shoulder_flex", arm_f, @stiff_up)
    p.set(other(fwd) + "shoulder_flex", @h_arm_b, @stiff_up)
    p.set("l_elbow", @elbow, @stiff_up)
    p.set("r_elbow", @elbow, @stiff_up)
    p.set("spine_flex", spine, @stiff_up)
    p

  -> plant_pose(ld, tr)
    p = Pose.new
    leg(p, tr, @psi_ms + @phi_nom, @k_land, @a_land, @stiff_st)
    leg(p, ld, @pl_ld_hip, @pl_ld_knee, ~-0.1, @stiff_sw)
    h_upper(p, tr, @att_lean, @att_arm)

  -> attack_pose(ld, tr)
    p = Pose.new
    leg(p, tr, @att_st_hip, @att_st_knee, @att_st_ank, @stiff_st)
    leg(p, ld, @att_ld_hip, @att_ld_knee, ~-0.2, @stiff_sw)
    h_upper(p, tr, @att_lean, @att_arm)

  -> lead_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @lead_hip, @lead_knee, ~-0.2, @stiff_sw)
    leg(p, tr, @lead_tr_hip, @lead_tr_knee, ~0.3, @stiff_sw)
    h_upper(p, tr, @dip, @att_arm)

  -> trail_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @trail_ld_hip, ~0.05, ~0.2, @stiff_sw)
    leg(p, tr, @trail_hip, @trail_knee, ~-0.4, @stiff_sw)
    h_upper(p, tr, @trail_lean, @arm)

  -> snap_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @psi_reach + @phi_nom + @snap_ld_hip, @snap_ld_knee, @snap_ld_ank, @stiff_st)
    leg(p, tr, @snap_tr_hip, @snap_tr_knee, ~-0.2, @stiff_sw)
    upper(p, ld, tr)

  -> h_land_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @psi_ms + @phi_nom, @hl_knee, @a_land, @stiff_st)
    leg(p, tr, @hl_tr_hip, @k_mid, ~-0.1, @stiff_sw)
    upper(p, ld, tr)

  # ---- events ---------------------------------------------------------------

  # Take off from `side`'s touchdown when the next step would land closer
  # to the bar than d_to - half a stride (but never from right under it).
  -> takeoff_due(f, side)
    return false if f.at("hurdle", 1) <= ~0.0
    gap = f.com_x + f.get("hurdle") - f.at(side + "foot_pos", 0)
    gap < @d_to + @stride * ~0.5 && gap > ~0.3

  -> attack_enter(f, c, ld, tr)
    enter(f, tr, ld, :attack)
    @bar_x = f.com_x + f.get("hurdle")
    @bar_h = f.at("hurdle", 1)
    @has_target = false
    x = f.at(tr + "foot_pos", 0)
    note_step(x)
    gap = @bar_x - x
    c.emit("takeoff:[gap]")
    self

  -> past_bar(f, sensor, margin)
    f.at(sensor, 0) > @bar_x + margin

  -> note_step(x)
    s = x - @last_foot
    @stride = @stride * ~0.6 + s * ~0.4 if s > ~0.4 && s < ~2.6
    @last_foot = x
    self

  # Touchdown of `side`: update the stride estimate and plan the steps to
  # the next take-off spot (either foot may take off).
  -> touchdown(f, c, side)
    x = f.at(side + "foot_pos", 0)
    note_step(x)
    @has_target = false
    @steps_left = 0
    return self if f.at("hurdle", 1) <= ~0.0
    left = f.com_x + f.get("hurdle") - @d_to - x
    return self if left < ~0.2
    n = (left / clamp(@stride, @step_min, @step_max) + ~0.5).floor
    n = 1 if n < 1
    s = clamp(left / n, @step_min, @step_max)
    @target_x = x + s
    @has_target = true
    @steps_left = n
    c.emit("plan:[n]:[s]")
    self

  # ---- corrections ----------------------------------------------------------

  # Offsets for one tick of a stride chunk (phase :land, :push or :flight).
  # In stance the stance hip servoes the torso and the swing hip holds its
  # thigh angle in world frame (pelvis pitch compensated). In flight the
  # landing leg is placed (partly pelvis-compensated, comp_fly: full
  # compensation there is positive feedback), nudged toward the stride
  # planner's landing target, and the trailing leg is the reaction mass of
  # a torso servo.
  -> stride_correction(f, ctl, st, sw, phase)
    off = zeros
    place = @psi_v * @v_f + @cv * (@v_f - @v_des)
    # speed brake: above v_cap the landing foot moves forward
    place = place + @k_brake * (@v_f - @v_cap) if @v_f > @v_cap
    if phase == :flight
      fly = ~0.0 - @k_fly * (f.torso_pitch - @torso_des) - @k_fly_d * f.torso_pitch_rate
      joint_offset(off, st + "hip_flex", fly)
      # swing-leg retraction late in flight
      late = f.t - @t_phase - @t_flight
      late = ~0.0 if late < ~0.0
      ret = ~0.0 - @retract * late
      joint_offset(off, sw + "hip_flex", place + ret + @comp_fly * (pelvis_pitch(f) - @phi_nom) + stride_nudge(f, ctl, sw))
      # the attack step: when the next landing is the take-off, plant that
      # foot further ahead on a straighter knee (a pole-vault plant turns
      # run-up speed into lift)
      if @steps_left == 1
        joint_offset(off, sw + "hip_flex", @att_reach)
        joint_offset(off, sw + "knee", ~0.0 - @att_knee)
      toe_clearance(f, off, st)
      return off
    comp = pelvis_pitch(f) - @phi_nom
    torso = torso_servo(f, ctl, st + "hip_flex", ~0.0, ~1.0) - @k_swc * servo_error(f, ctl, sw + "hip_flex")
    joint_offset(off, st + "hip_flex", torso)
    place = ~0.0 if phase == :land
    joint_offset(off, sw + "hip_flex", comp + place)
    toe_clearance(f, off, sw)
    off

  # Stride planner in flight: predict where the landing foot will come down
  # (the hip's ballistic path plus the commanded thigh angle) and turn the
  # miss against the planned landing into a hip angle (w_stride of it,
  # capped at max_adj metres).
  -> stride_nudge(f, ctl, sw)
    return ~0.0 if !@has_target
    t = time_to_land(f)
    hip_x = f.at("pelvis_pos", 0) + f.at("pelvis_vel", 0) * t
    thigh = ctl.command.joint_angle(body, sw + "hip_flex") - pelvis_pitch(f)
    miss = @target_x - (hip_x + @leg_len * Math.sin(thigh))
    @w_stride * clamp(miss, ~0.0 - @max_adj, @max_adj) / @leg_len

  # Ballistic time until the hip drops to landing height.
  -> time_to_land(f)
    z = f.at("pelvis_pos", 2)
    vz = f.at("pelvis_vel", 2)
    h = @leg_len * ~0.95
    return ~0.0 if z <= h
    (vz + Math.sqrt(vz * vz + ~19.62 * (z - h))) / ~9.81

  # Take-off stance: the take-off hip servoes the torso toward a steeper
  # lean (att_pitch), the lead thigh keeps its world angle.
  -> attack_corr(f, ctl, ld, tr)
    off = zeros
    torso = torso_servo(f, ctl, tr + "hip_flex", @att_pitch, ~1.0) - @k_swc * servo_error(f, ctl, ld + "hip_flex")
    joint_offset(off, tr + "hip_flex", torso)
    joint_offset(off, ld + "hip_flex", pelvis_pitch(f) - @phi_nom)
    off

  # Landing on the lead leg: a firmer torso servo (hl_k) to stand the trunk
  # back up after the dip.
  -> land_corr(f, ctl, ld, tr)
    off = zeros
    torso = torso_servo(f, ctl, ld + "hip_flex", @hl_pitch, @hl_k) - @k_swc * servo_error(f, ctl, tr + "hip_flex")
    joint_offset(off, ld + "hip_flex", torso)
    joint_offset(off, tr + "hip_flex", pelvis_pitch(f) - @phi_nom)
    toe_clearance(f, off, tr)
    trail_lift(off, f, tr)

  # Over the hurdle: the arms steer trunk pitch (both legs are busy), and
  # each leg that has not yet passed the bar is lifted in proportion to how
  # far its sole sits below the wanted clearance (sensed foot height against
  # the sensed bar height): the lead hip flexes, the trail knee folds and its
  # hip flexes.
  -> air_corr(f, ctl, ld, tr)
    off = zeros
    dq = @k_arm * (f.torso_pitch - torso_target(ctl, ~0.0)) + @k_arm_d * f.torso_pitch_rate
    joint_offset(off, "l_shoulder_flex", dq)
    joint_offset(off, "r_shoulder_flex", dq)
    lift = clearance_short(f, ld, @bar_h + @clear_want)
    joint_offset(off, ld + "hip_flex", @k_lead * lift)
    trail_lift(off, f, tr)

  # The trail leg's tuck, kept up until its foot is past the bar (through
  # the snap-down and the landing too): the knee folds and the hip flexes in
  # proportion to how far the sole sits below bar height + clear_want.
  -> trail_lift(off, f, tr)
    lift = clearance_short(f, tr, @bar_h + @clear_want)
    joint_offset(off, tr + "knee", @k_trail * lift)
    joint_offset(off, tr + "hip_flex", @k_trail_h * lift)
    off

  -> snap_corr(f, ctl, ld, tr)
    trail_lift(stride_correction(f, ctl, tr, ld, :flight), f, tr)

  # How far (m) the foot's sole is below `want` while the foot is still
  # short of (or over) the bar; 0 once it is past.
  -> clearance_short(f, side, want)
    return ~0.0 if f.at(side + "foot_pos", 0) > @bar_x + ~0.15
    clamp(want - (f.at(side + "foot_pos", 2) - ~0.08), ~0.0, ~0.4)

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
  # proportional to the torque its muscles are producing.
  -> servo_error(f, ctl, joint)
    tg = ctl.target
    p = body.pos_index(joint)
    n = body.neg_index(joint)
    qa = body.muscle(p).angle_at(tg[p])
    qb = body.muscle(n).angle_at(tg[n])
    (qa + qb) * ~0.5 - f.joint_angle(body, joint)

  # Torso pitch wanted now: the run's lean, plus `extra`, plus whatever the
  # chunk's spine command adds to the nominal spine (the hurdle dip), so the
  # servo never fights the pose.
  -> torso_target(ctl, extra)
    @torso_des + extra + ctl.command.joint_angle(body, "spine_flex") - @spine

  # World-frame stance hip: hold the measured angle (led by its velocity) and
  # add a PD on torso pitch (gains scaled by k), so the hip's torque answers
  # only to the torso.
  -> torso_servo(f, ctl, joint, extra, k)
    q = f.joint_angle(body, joint)
    qd = f.joint_rate(body, joint)
    qc = ctl.command.joint_angle(body, joint)
    err = f.torso_pitch - torso_target(ctl, extra)
    q + @hip_lead * qd - qc - k * (@torso_kp * err + @torso_kd * f.torso_pitch_rate)
