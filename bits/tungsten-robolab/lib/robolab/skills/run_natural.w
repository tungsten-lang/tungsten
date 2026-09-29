# RunNatural: a running gait authored as human keyframes.
#
# The stride is six contraction vectors at the gait events of human running,
# taken from published sagittal kinematics at ~3-4 m/s, eased from one to the
# next and latched on the real gait events. Right stance is authored; the left
# step's goals are Pose#mirror of the right step's:
#
#   r_load   right touchdown (TD) -> mid-stance (MS)   ends: COM over the foot
#   r_drive  MS -> right toe-off (TO)                  ends: right foot releases
#   r_flight TO -> left TD (mirrored TD)               ends: left foot contact
#   l_load, l_drive, l_flight                          the mirror images
#
# Keyframes (right stance; degrees, model convention: hip + = flexion of the
# thigh relative to the pelvis, knee + = flexion, ankle + = PLANTARflexion,
# toe - = toes extended, shoulder + = flexion (arm forward), elbow + = flexion).
# Approximate values after Novacheck 1998 (Gait & Posture 7:77, running
# ~3.2 m/s), Hamner & Delp 2013 (J Biomech 46:780, 2-5 m/s), Fukuchi et al.
# 2017 (PeerJ 5:e3298, 3.5 m/s) and Pontzer et al. 2009 (J Exp Biol 212:523,
# arm swing), re-zeroed on quiet standing (model hip = thigh relative to the
# pelvis, so a lab hip curve loses the standing pelvic-tilt offset):
#
#   event  stance leg (hip knee ankle toe)   swing leg (hip knee ankle)   arms (st shoulder, sw shoulder)
#   TD      30  18    0    0                  -8   55   12                 -18.5   28.5
#   MS      12  40  -20    0                  20  110   -5                  24.3  -14.3
#   TO     -12  15   25  -30                  55   90   -2                  44.9  -34.9
#
# TO is the "final motion of each stride": the power leg nearly fully extended
# behind, the alternate knee driven up, the arm on the power-leg side swung
# forward and the other arm back. Elbows 80-90 (elbow = 85 + 5 (shoulder - 5)
# / 40), trunk 7 deg forward of vertical with the pelvis 3 deg (spine 4 deg).
# `speed` (the gait's design speed, default 3.5 m/s) shifts the swing
# amplitudes along the human speed trends (Novacheck, Hamner & Delp: the swing
# hip and knee flex further and the arms swing wider as speed rises), so the
# same keyframes serve a jog and a fast run.
#
# Erik's keyframes (opt-in): a params-file value ref_<td|ms|to>_<key>
# (degrees, right stance, the Keyframe Bench's "Copy params" keys: st_hip
# st_knee st_ankle st_toe sw_hip sw_knee sw_ankle sw_toe st_shoulder st_elbow
# sw_shoulder sw_elbow spine pelvis) replaces the literature value of that
# joint at that keyframe (no speed trend on an overridden value); the elbows
# and the spine are then explicit per keyframe, and the torso servo's trunk
# and pelvis targets become the keyframes' means (trunk = pelvis + spine).
# Without ref_* params every target is the literature's, as before.
#
# Ordered keyframes (opt-in): ref_<id>_phase <pct> places keyframe <id> at a
# phase of the stride (0 = right touchdown; td / ms / to default to 0 / 18 /
# 36). Any extra keyframe (the Bench's hr "heel rise" 30 %, kl "max knee
# height" 38 %, or an id Erik adds) splits the step into more chunks, each
# easing to the next keyframe in phase order (the extras are via points):
#   td -> ms (load) -> hr (via) -> to (drive) -> kl (via) -> next td (flight)
# A chunk ends on its keyframe's event: ms the COM over the stance foot, hr
# the stance heel leaving the ground (heel contact from the task), to the
# stance foot's release, kl the swing thigh's elevation rate crossing zero
# (or the landing foot's contact), td the landing foot's contact; any other
# keyframe at its phase share of its phase (load TD-MS, drive MS-TO, flight
# TO-TD, timed on a running estimate of each phase's duration). An extra
# keyframe gets its own command offsets d_<id>_<st|sw>_<joint>, starting
# between its neighbours'. With only td / ms / to the stride is the six
# chunks above, exactly as before.
#
# The commanded keyframe is the reference plus a searched offset per leg
# joint and keyframe (d_<kf>_<st|sw>_<joint>, degrees): the reflex servo sags
# under load, so the command that ACHIEVES a reference posture is not the
# reference itself; practice scores the achieved kinematics against the
# reference, not the command.
#
# Timing (`timing`, a params-file switch):
#   0  per-chunk durations t_load / t_drive / t_fly, each chunk's easing
#      searched (ease_load / ease_drive / ease_fly, a categorical), or all
#      chunks `via` (via 1): the command passes through each keyframe with
#      the Catmull-Rom velocity toward the next (cubic Hermite), so a stride
#      is one velocity-continuous motion instead of stop-and-go segments
#   1  "start -> end contraction at a speed": every chunk lasts (largest
#      joint travel between its keyframes) / omega, one joint speed for the
#      whole stride
#
# Keyframe representation (`keys`, a params-file switch): 0 (default) the
# goal is the keyframe posture, turned into one contraction per muscle by
# Pose through the body's geometry; 1 the goal is the full contraction vector
# of that posture plus searched per-muscle offsets (c_<kf>_<st|sw>_<muscle>,
# the leg muscles, mirrored by role), reached with Chunk#to.
#
# Corrections are spring-eased offsets on the keyframes, each PD term clamped
# to +-corr_lim rad so the look stays the keyframes':
#   torso      the stance hip carries the trunk: w_hip blends its keyframe
#              (0) with SIMBICON's world-frame torso servo (1: hold the
#              measured angle, led by hip_lead x its rate), plus a clamped PD
#              on trunk pitch and the swing hip's reaction (k_swc); on this
#              body a pure keyframe hip cannot hold an upright trunk (the
#              extensors saturate), so practice settles in between. The
#              trunk target is the reference lean plus a searched bias (lean):
#              the ACHIEVED lean is what the task scores. In flight the
#              trailing leg is the reaction mass of the torso PD
#   pitch      the swing hip holds its thigh angle in world frame against
#              pelvis pitch error (comp)
#   placement  the landing hip moves with the speed error, cv (v - v_des)
#              (Raibert), and past t_fly keeps retracting at `retract` rad/s
#              (Seyfarth et al. 2003), so speed settles at v_des
# Drives (feed-forward bursts on top of the reflexes): push-off on the stance
# extensors in `drive` (scaled with the speed plan and deficit, k_vd, and
# Raibert's hop-height loop, k_z (z_ref - pelvis height); below z_ref the
# stance knee is also commanded straighter, k_zk), knee and ankle
# pre-tension through `load`, swing initiation on the trailing leg in
# `flight`. The arms read the reference shoulder sinusoid arm_lead % ahead
# (the servo lags a fast swing).
#
# Standing start (the default): stand -> lean (ankle and hip strategies, gain
# g0, co-contraction stiff0) -> a first push push0_amp of the way into the
# left TO keyframe, then the stride loop; v_des ramps from v0 to `speed` at
# `accel`. A body that starts already running (com_vx > 1 m/s at t = 0) goes
# straight into the loop.

+ RunNaturalSkill < Skill
  -> start(frame, ctl)
    read_params
    # the task builds its human reference at the gait's design speed
    ctl.emit("ref_speed:" + @speed.to_s)
    @v_f = frame.com_vx
    @flying = frame.com_vx > ~1.0
    @v_des = @v0
    @v_des = @speed if @flying
    @t_go = ~-1.0
    @t_go = frame.t if @flying
    @phase = nil
    @t_phase = frame.t
    @st = "r_"
    @sw = "l_"
    @drives = []
    setup_reflexes(ctl)
    read_contraction_offsets
    td = keyframe("td")
    ms = keyframe("ms")
    to = keyframe("to")
    mv = Movement.new("run_natural")
    if !@flying
      mv.add(stand_chunk)
      mv.add(lean_chunk)
      mv.add(first_push(to.mirror))
    first = mv.size
    if @plan.size > 3
      build_stride(mv)
      mv.loop_from(first)
      ctl.add_track(Track.new("body", mv, body.all))
      return self
    mv.add(flight_chunk("l_", "r_", td, to.mirror))
    mv.add(load_chunk("r_", "l_", ms, td))
    mv.add(drive_chunk("r_", "l_", to, ms))
    mv.add(flight_chunk("r_", "l_", td.mirror, to))
    mv.add(load_chunk("l_", "r_", ms.mirror, td.mirror))
    mv.add(drive_chunk("l_", "r_", to.mirror, ms.mirror))
    mv.loop_from(first)
    ctl.add_track(Track.new("body", mv, body.all))

  -> read_params
    # structure switches (params-file settings, not tunables)
    @timing = ~0.0
    @timing = @params["timing"] if @params.key?("timing")
    @via = true
    @via = @params["via"] > ~0.5 if @params.key?("via")
    # the flight chunk ends at touchdown, where the knee reverses (it extends
    # into the landing and yields after it), so a Catmull-Rom tangent there
    # would still be extending at contact: by default it arrives on its easing
    @via_fly = false
    @via_fly = @params["via_fly"] > ~0.5 if @params.key?("via_fly")
    # the gait's design speed (m/s): v_des settles here, and the keyframes'
    # swing amplitudes follow it (see ref_deg)
    @speed = ~3.5
    @speed = @params["speed"] if @params.key?("speed")
    # keyframe representation: 0 joint-space postures, 1 full contraction
    # vectors with per-muscle offsets (see aim)
    @keys = ~0.0
    @keys = @params["keys"] if @params.key?("keys")
    @eases = [:min_jerk, :linear, :sine_in_out, :cubic_in, :cubic_out, :quint_in_out, :cubic_in_out, :expo_out]
    # speed plan
    @v0 = param("v0", ~1.0, ~0.0, ~2.5)
    @accel = param("accel", ~1.5, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.15, ~0.02, ~0.5)
    # keyframe command offsets (degrees): command = reference + offset
    @off = {}
    ["td", "ms", "to"].each ->(kf)
      ["st", "sw"].each ->(role)
        ["hip", "knee", "ankle"].each ->(j)
          nm = "d_" + kf + "_" + role + "_" + j
          @off[nm] = param(nm, default_offset(nm), ~0.0 - offset_limit(kf, role, j), offset_limit(kf, role, j))
    # the step's keyframes in phase order (td, ms, to plus any extras) and
    # the extras' own offsets
    @plan = step_keyframes
    read_extra_offsets
    @dur_load = ~0.1
    @dur_drive = ~0.1
    @dur_fly = ~0.13
    @d_spine = param("d_spine", ~0.0, ~-15.0, ~20.0)
    @arm_amp = param("arm_amp", ~1.0, ~0.5, ~1.6)
    # the arms' keyframe targets are read this far ahead on the reference's
    # shoulder sinusoid (% of the cycle): the servo lags a fast swing
    @arm_lead = param("arm_lead", ~0.0, ~-5.0, ~25.0)
    @stiff_st = param("stiff_st", ~0.2, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.08, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.1, ~0.0, ~0.35)
    # timing: per-chunk durations (timing 0) or one joint speed (timing 1)
    @t_load = ~0.08
    @t_drive = ~0.12
    @t_fly = ~0.09
    @omega = ~8.0
    if @timing > ~0.5
      @omega = param("omega", ~8.0, ~3.0, ~20.0)
    else
      @t_load = param("t_load", ~0.08, ~0.03, ~0.3)
      @t_drive = param("t_drive", ~0.12, ~0.03, ~0.3)
      @t_fly = param("t_fly", ~0.09, ~0.03, ~0.35)
    # (a via chunk runs a cubic Hermite, so its easing is only searched when
    # the chunk is not via)
    @ease_load = :min_jerk
    @ease_drive = :min_jerk
    @ease_fly = :min_jerk
    @ease_load = easing("ease_load") if !@via
    @ease_drive = easing("ease_drive") if !@via
    @ease_fly = easing("ease_fly") if !@via_fly
    # latches: mid-stance is the COM passing d_ms ahead of the stance ankle
    # (bounded so the mid-stance latch stays a real mid-stance: the COM over
    # the foot, after at least 40 ms of loading)
    @d_ms = param("d_ms", ~0.02, ~-0.02, ~0.15)
    @t_ms_min = param("t_ms_min", ~0.06, ~0.04, ~0.14)
    @t_ms_max = param("t_ms_max", ~0.18, ~0.06, ~0.3)
    @t_drive_max = param("t_drive_max", ~0.25, ~0.08, ~0.35)
    # reflexes and per-phase gains
    @leg_kp = param("leg_kp", ~6.0, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.37, ~0.05, ~0.6)
    @bi_gain = param("bi_gain", ~1.3, ~0.0, ~1.5)
    @up_kp = param("up_kp", ~6.0, ~2.0, ~12.0)
    @up_kd = param("up_kd", ~0.25, ~0.05, ~0.6)
    @g_st = param("g_st", ~0.75, ~0.4, ~2.0)
    @g_sw = param("g_sw", ~0.65, ~0.2, ~1.5)
    @g_kl = param("g_kl", ~0.8, ~0.2, ~1.8)
    @g_al = param("g_al", ~0.95, ~0.2, ~1.8)
    # the swing knee's own reflex gain (default: the swing leg's, g_sw)
    @g_swk = param("g_swk", @g_sw, ~0.2, ~1.5)
    # drives
    @drv_knee = param("drv_knee", ~0.7, ~0.0, ~1.0)
    @drv_ankle = param("drv_ankle", ~0.3, ~0.0, ~1.0)
    @drv_gas = param("drv_gas", ~0.9, ~0.0, ~1.0)
    @drv_hip = param("drv_hip", ~0.33, ~0.0, ~1.0)
    @drv_ham = param("drv_ham", ~0.5, ~0.0, ~1.0)
    @pre_knee = param("pre_knee", ~0.3, ~0.0, ~0.8)
    @pre_ankle = param("pre_ankle", ~0.1, ~0.0, ~0.8)
    @drv_swh = param("drv_swh", ~0.2, ~0.0, ~0.8)
    @drv_swk = param("drv_swk", ~0.5, ~0.0, ~0.8)
    @drv_rf = param("drv_rf", ~0.7, ~0.0, ~1.0)
    @drv_pre = param("drv_pre", ~0.05, ~0.0, ~0.6)
    @drv_floor = param("drv_floor", ~0.15, ~0.0, ~1.0)
    # swing-leg bursts (0 = off, round 1's gait): the heel tuck (knee flexor
    # on the swing leg while the other leg loads), the knee drive (hip flexor
    # on the swing leg while the other leg pushes: "the alternate knee up"),
    # and pre-landing plantarflexor tone on the landing leg in flight (a
    # forefoot-leaning, stiffer ankle at contact)
    @drv_tuck = param("drv_tuck", ~0.0, ~0.0, ~0.8)
    @drv_lift = param("drv_lift", ~0.0, ~0.0, ~0.8)
    @drv_pre_ank = param("drv_pre_ank", ~0.0, ~0.0, ~0.6)
    @k_vd = param("k_vd", ~0.4, ~0.0, ~1.0)
    # hop-height regulation (Raibert's thrust loop): the knee and ankle
    # extensors push harder while the pelvis rides below z_ref
    @z_ref = param("z_ref", ~0.9, ~0.8, ~1.0)
    @k_z = param("k_z", ~0.0, ~0.0, ~12.0)
    # ... and the stance knee is commanded straighter (rad per m below z_ref),
    # so a low landing does not sink the leg into a deep crouch
    @k_zk = param("k_zk", ~0.0, ~0.0, ~6.0)
    @z_err = ~0.0
    # corrections (each clamped to +-corr_lim rad)
    # stance hip: w_hip blends the keyframe (0) with SIMBICON's world-frame
    # torso servo (1: hold the measured angle, led by hip_lead x its rate, so
    # the hip's torque answers only to the PD on trunk pitch and cancels the
    # swing hip's reaction, k_swc)
    @w_hip = param("w_hip", ~1.0, ~0.0, ~1.0)
    @hip_lead = param("hip_lead", ~0.12, ~0.0, ~0.2)
    @torso_kp = param("torso_kp", ~0.3, ~0.0, ~3.0)
    @torso_kd = param("torso_kd", ~0.45, ~0.0, ~0.8)
    @k_swc = param("k_swc", ~0.5, ~0.0, ~1.5)
    @fly_kp = param("fly_kp", ~0.75, ~0.0, ~2.0)
    @fly_kd = param("fly_kd", ~0.25, ~0.0, ~0.5)
    @comp = param("comp", ~0.8, ~0.0, ~1.0)
    @cv = param("cv", ~0.1, ~0.0, ~0.4)
    @retract = param("retract", ~2.0, ~0.0, ~6.0)
    @corr_lim = param("corr_lim", ~0.25, ~0.05, ~0.5)
    @spring = param("spring", ~0.06, ~0.01, ~0.2)
    @lean_acc = param("lean_acc", ~0.15, ~0.0, ~0.5)
    # bias of the torso servo's target (degrees): the trunk settles where the
    # servo balances the stride's pitching moments, not at its target, so the
    # target is searched and the ACHIEVED lean is scored against the reference
    @lean = param("lean", ~0.0, ~-8.0, ~20.0)
    # standing start
    @d_go = param("d_go", ~0.12, ~0.0, ~0.3)
    @k_bal = param("k_bal", ~1.0, ~0.0, ~3.0)
    @stiff0 = param("stiff0", ~0.1, ~0.0, ~0.3)
    @g0 = param("g0", ~0.7, ~0.3, ~1.5)
    @push0_amp = param("push0_amp", ~0.6, ~0.2, ~1.0)
    @drv0_knee = param("drv0_knee", ~0.2, ~0.0, ~1.0)
    @drv0_ankle = param("drv0_ankle", ~0.6, ~0.0, ~1.0)
    @drv0_hip = param("drv0_hip", ~0.4, ~0.0, ~1.0)
    @t0_max = param("t0_max", ~0.45, ~0.2, ~0.7)
    # reference trunk and pelvis pitch (rad, world frame)
    @trunk_ref = ~0.1222 + ~0.0035 * (@speed - ~3.5)
    @pelvis_ref = ~0.0524
    trunk_targets_from_keyframes if keyframe_trunk?
    @trunk_des = @trunk_ref + @lean * ~0.017453292519943295
    self

  # The search box of a command offset (+-degrees): 60 for hips, 40 for knees
  # and ankles, or a params-file setting lim_<kf>_<st|sw>_<joint> (e.g. a
  # forefoot touchdown far from the literature pose: lim_td_st_ankle 80).
  -> offset_limit(kf, role, j)
    key = "lim_" + kf + "_" + role + "_" + j
    return @params[key] if @params.key?(key)
    return ~60.0 if j == "hip"
    ~40.0

  # Starting guesses for the command offsets (degrees): the loaded stance
  # knee and ankle sag past their command, so they are commanded straighter.
  -> default_offset(nm)
    return ~-10.0 if nm == "d_ms_st_knee"
    return ~8.0 if nm == "d_ms_st_ankle"
    return ~-5.0 if nm == "d_td_st_knee"
    ~0.0

  -> easing(nm)
    k = param(nm, ~0.5, ~0.0, ~7.999).floor
    k = 0 if k < 0
    k = 7 if k > 7
    @eases[k]

  -> setup_reflexes(ctl)
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    ctl.reflex.set_gains(body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"]), @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    ctl.reflex.set_gains(body.mask(["spine", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @up_kp, @up_kd)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle", side + "toe", side + "rf", side + "ham", side + "gas"])
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "gas", side + "toe"])
    self

  # ---- keyframes --------------------------------------------------------------

  # Human reference for a right-stance keyframe (degrees): stance hip, knee,
  # ankle, toe, swing hip, knee, ankle, toe, stance-side shoulder, swing-side
  # shoulder. See the table at the top; `speed` moves the swing amplitudes
  # along the human trends (per m/s above 3.5: TD stance hip +2, MS swing
  # knee +8, TO swing hip +6 and knee +5, arm swing +12 %).
  -> ref_deg(kf)
    lit = ref_lit(lit_id(kf))
    keys = ["st_hip", "st_knee", "st_ankle", "st_toe", "sw_hip", "sw_knee", "sw_ankle", "sw_toe", "st_shoulder", "sw_shoulder"]
    out = []
    i = 0
    while i < keys.size
      out.push(ov(kf, keys[i], lit[i]))
      i += 1
    out

  # The literature values (see the table at the top), with the speed trends.
  -> ref_lit(kf)
    dv = @speed - ~3.5
    if kf == "td"
      return [~30.0 + ~2.0 * dv, ~18.0, ~0.0, ~0.0, ~-8.0, ~55.0, ~12.0, ~0.0, shoulder_deg(~0.0, ~85.0), shoulder_deg(~0.0, ~35.0)]
    if kf == "ms"
      return [~12.0, ~40.0, ~-20.0, ~0.0, ~20.0, ~110.0 + ~8.0 * dv, ~-5.0, ~0.0, shoulder_deg(~18.0, ~85.0), shoulder_deg(~18.0, ~35.0)]
    return [~-12.0, ~15.0, ~25.0, ~-30.0, ~55.0 + ~6.0 * dv, ~90.0 + ~5.0 * dv, ~-2.0, ~0.0, shoulder_deg(~36.0, ~85.0), shoulder_deg(~36.0, ~35.0)]

  # The reference shoulder angle (degrees) at a cycle phase (%): each arm
  # swings with the contralateral thigh, 5 - A cos(2 pi (phase - back) / 100)
  # with the arm furthest back at `back` % (the stance-side arm at 85 %, the
  # other at 35 %), A = 40 deg at 3.5 m/s (+12 % per m/s). The command reads
  # it arm_lead % ahead.
  -> shoulder_deg(phase, back)
    amp = ~40.0 * (~1.0 + ~0.12 * (@speed - ~3.5))
    ~5.0 - amp * Math.cos(~6.283185307179586 * (phase + @arm_lead - back) / ~100.0)

  # Elbow flexion that goes with a shoulder angle (degrees): 80 with the arm
  # back, 90 with it forward.
  -> elbow_deg(shoulder)
    ~85.0 + ~5.0 * (shoulder - ~5.0) / ~40.0

  # The commanded right-stance keyframe: reference plus the searched offsets.
  -> keyframe(kf)
    r = ref_deg(kf)
    rad = ~0.017453292519943295
    k = RunNaturalKeyframe.new(kf)
    pre = "d_" + kf + "_"
    k.set("r_hip_flex", (r[0] + @off[pre + "st_hip"]) * rad, @stiff_st)
    k.set("r_knee", (r[1] + @off[pre + "st_knee"]) * rad, @stiff_st)
    k.set("r_ankle", (r[2] + @off[pre + "st_ankle"]) * rad, @stiff_st)
    k.set("r_toe", r[3] * rad, @stiff_st)
    k.set("l_hip_flex", (r[4] + @off[pre + "sw_hip"]) * rad, @stiff_sw)
    k.set("l_knee", (r[5] + @off[pre + "sw_knee"]) * rad, @stiff_sw)
    k.set("l_ankle", (r[6] + @off[pre + "sw_ankle"]) * rad, @stiff_sw)
    k.set("l_toe", r[7] * rad, @stiff_sw)
    k.set("r_shoulder_flex", (~5.0 + (r[8] - ~5.0) * @arm_amp) * rad, @stiff_up)
    k.set("l_shoulder_flex", (~5.0 + (r[9] - ~5.0) * @arm_amp) * rad, @stiff_up)
    k.set("r_elbow", ov(kf, "st_elbow", elbow_deg(r[8])) * rad, @stiff_up)
    k.set("l_elbow", ov(kf, "sw_elbow", elbow_deg(r[9])) * rad, @stiff_up)
    k.set("spine_flex", (ov(kf, "spine", ~4.0) + @d_spine) * rad, @stiff_up)
    k

  # Erik's keyframe value ref_<kf>_<key> (degrees) if the params carry it,
  # else the literature value `lit`.
  -> ov(kf, key, lit)
    nm = "ref_" + kf + "_" + key
    return @params[nm] if @params.key?(nm)
    lit

  # Do the params set any keyframe's spine or pelvis?
  -> keyframe_trunk?
    kfs = @plan
    i = 0
    while i < kfs.size
      return true if @params.key?("ref_" + kfs[i] + "_spine") || @params.key?("ref_" + kfs[i] + "_pelvis")
      i += 1
    false

  # Torso-servo targets from the keyframes: trunk pitch = mean of pelvis +
  # spine, pelvis pitch = mean pelvis (literature 3 + 4 where not given).
  -> trunk_targets_from_keyframes
    rad = ~0.017453292519943295
    tr = ~0.0
    pv = ~0.0
    n = ~0.0
    kfs = @plan
    i = 0
    while i < kfs.size
      p = ov(kfs[i], "pelvis", ~3.0)
      tr = tr + p + ov(kfs[i], "spine", ~4.0)
      pv = pv + p
      n = n + ~1.0
      i += 1
    @trunk_ref = tr / n * rad
    @pelvis_ref = pv / n * rad
    self

  # ---- ordered keyframes ---------------------------------------------------------

  # A keyframe's phase (% of the stride): ref_<id>_phase, else the default
  # (td 0, ms 18, hr 30, to 36, kl 38), else -1 (not placed).
  -> kf_phase(id)
    nm = "ref_" + id + "_phase"
    return @params[nm] if @params.key?(nm)
    return ~0.0 if id == "td"
    return ~18.0 if id == "ms"
    return ~36.0 if id == "to"
    return ~30.0 if id == "hr"
    return ~38.0 if id == "kl"
    ~-1.0

  # The right step's keyframe ids sorted by phase: td, ms, to and every id
  # with a ref_<id>_phase line whose phase lies inside the step (< td + 50).
  -> step_keyframes
    ids = ["td", "ms", "to"]
    @params.keys.each ->(k)
      if k.starts_with?("ref_") && k.ends_with?("_phase") && k.size > 10
        id = k.slice(4, k.size - 10)
        ids.push(id) if !listed?(ids, id)
    top = kf_phase("td") + ~50.0
    keep = []
    i = 0
    while i < ids.size
      p = kf_phase(ids[i])
      keep.push(ids[i]) if p >= ~0.0 && p < top
      i += 1
    # insertion sort by phase
    i = 1
    while i < keep.size
      j = i
      while j > 0 && kf_phase(keep[j - 1]) > kf_phase(keep[j])
        t = keep[j - 1]
        keep[j - 1] = keep[j]
        keep[j] = t
        j -= 1
      i += 1
    keep

  -> listed?(list, s)
    i = 0
    while i < list.size
      return true if list[i] == s
      i += 1
    false

  # The main keyframe whose literature values an extra keyframe falls back on
  # (the Bench always writes all 14 values, so this is only a safety net).
  -> lit_id(id)
    return id if id == "td" || id == "ms" || id == "to"
    p = kf_phase(id)
    return "td" if p < kf_phase("ms")
    return "ms" if p < kf_phase("to")
    "to"

  # The phase the keyframe falls in: :load (TD-MS], :drive (MS-TO], :flight
  # (TO-next TD].
  -> kind_of(p)
    return :load if p <= kf_phase("ms")
    return :drive if p <= kf_phase("to")
    :flight

  # Where a phase lies inside its kind's span, 0 at the kind's first event and
  # 1 at its last (next TD = td + 50).
  -> share_of(p, kind)
    a = kf_phase("td")
    b = kf_phase("ms")
    if kind == :drive
      a = kf_phase("ms")
      b = kf_phase("to")
    if kind == :flight
      a = kf_phase("to")
      b = kf_phase("td") + ~50.0
    return ~1.0 if b <= a
    (p - a) / (b - a)

  # Command offsets of the extra keyframes, d_<id>_<st|sw>_<joint> (degrees),
  # starting between the neighbouring main keyframes' offsets (in flight the
  # next touchdown's roles are swapped: the swing leg lands).
  -> read_extra_offsets
    i = 0
    while i < @plan.size
      id = @plan[i]
      if id != "td" && id != "ms" && id != "to"
        p = kf_phase(id)
        k = kind_of(p)
        w = share_of(p, k)
        ["st", "sw"].each ->(role)
          ["hip", "knee", "ankle"].each ->(j)
            nm = "d_" + id + "_" + role + "_" + j
            lim = offset_limit(id, role, j)
            a = "td"
            b = "ms"
            rb = role
            if k == :drive
              a = "ms"
              b = "to"
            if k == :flight
              a = "to"
              b = "td"
              rb = "sw"
              rb = "st" if role == "sw"
            d0 = @off["d_" + a + "_" + role + "_" + j] * (~1.0 - w) + @off["d_" + b + "_" + rb + "_" + j] * w
            @off[nm] = param(nm, clamp(d0, ~0.0 - lim, lim), ~0.0 - lim, lim)
      i += 1
    self

  # The stride from the ordered keyframes: the left step's flight chunks (the
  # standing start's first push is the left toe-off), the right step, then the
  # left step's stance chunks; the loop repeats from the first.
  -> build_stride(mv)
    kfs = []
    i = 0
    while i < @plan.size
      kfs.push(keyframe(@plan[i]))
      i += 1
    add_step(mv, "l_", "r_", kfs, [:flight])
    add_step(mv, "r_", "l_", kfs, [:load, :drive, :flight])
    add_step(mv, "l_", "r_", kfs, [:load, :drive])
    self

  # One step's chunks of the given kinds: from each keyframe to the next in
  # phase order, the last to the other leg's touchdown (td mirrored).
  -> add_step(mv, st, sw, kfs, kinds)
    n = kfs.size
    i = 1
    while i <= n
      prev = kfs[i - 1]
      goal = kfs[0].mirror
      p = kf_phase("td") + ~50.0
      if i < n
        goal = kfs[i]
        p = kf_phase(@plan[i])
      p0 = kf_phase(@plan[i - 1])
      if st == "l_"
        prev = prev.mirror
        goal = kfs[0]
        goal = kfs[i].mirror if i < n
      k = kind_of(p)
      if listed_kind?(kinds, k)
        first = kind_of(p0) != k || @plan[i - 1] == "td"
        mv.add(step_chunk(st, sw, goal, prev, i == n, k, share_of(p0, k), share_of(p, k), first))
      i += 1
    self

  -> listed_kind?(kinds, k)
    i = 0
    while i < kinds.size
      return true if kinds[i] == k
      i += 1
    false

  # One chunk of the ordered stride: to `goal` (a keyframe of kind `k`,
  # spanning shares s0 -> s1 of that kind's phase), `last` = the next
  # touchdown. Load, drive and flight chunks keep their round-1 names (st +
  # load / drive / flight) when they end at ms / to / td; the others are
  # named after their keyframe (r_hr, r_kl, ...).
  -> step_chunk(st, sw, goal, from, last, k, s0, s1, first)
    id = goal.name
    base = @t_load
    base = @t_drive if k == :drive
    base = @t_fly if k == :flight
    nm = st + id
    nm = st + "load" if id == "ms"
    nm = st + "drive" if id == "to"
    nm = st + "flight" if last
    ch = aim(Chunk.new(nm, chunk_time(base * (s1 - s0), goal, from)), goal)
    ease = @ease_load
    ease = @ease_drive if k == :drive
    ease = @ease_fly if k == :flight
    via = @via
    via = true if k == :flight
    via = @via_fly if last
    styled(ch, ease, via)
    ch.hold_until(step_latch(st, sw, id, last, k, s1), step_timeout(id, last, k))
    if k == :load
      ch.drive(drive_vec([st + "knee_neg", @pre_knee, st + "ankle_pos", @pre_ankle, sw + "knee_pos", @drv_tuck]))
    elsif k == :drive
      ch.drive(push_drive(st, sw))
    else
      ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, st + "rf", @drv_rf, sw + "knee_neg", @drv_pre,
                          sw + "ankle_pos", @drv_pre_ank, sw + "gas", @drv_pre_ank]))
    mode = :stance
    mode = :flight if k == :flight
    ch.correct(->(f, c) correction(f, c, st, sw, mode), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, k)) if first
    ch

  # The event that ends a chunk of the ordered stride.
  -> step_latch(st, sw, id, last, k, s1)
    if last
      return Latch.contact(sw + "foot").after_min(~0.03)
    if id == "ms"
      mid = Latch.test("mid:" + st, ->(f, e, c) f.com_x - f.at(st + "foot_pos", 0) > @d_ms)
      return mid.after_min(@t_ms_min)
    if id == "to"
      return Latch.release(st + "foot").after_min(~0.03)
    if id == "hr"
      return Latch.release(st + "heel").after_min(~0.02)
    if id == "kl"
      apex = Latch.test("apex:" + sw, ->(f, e, c) thigh_rate(f, sw) <= ~0.0)
      return Latch.any([apex, Latch.contact(sw + "foot")]).after_min(~0.02)
    Latch.test("share:" + st + id, ->(f, e, c) f.t - @t_phase >= s1 * dur_of(k))

  -> step_timeout(id, last, k)
    return ~0.45 if last || k == :flight
    return @t_ms_max if id == "ms"
    @t_drive_max

  # The swing thigh's elevation rate in world frame (rad/s): hip flexion rate
  # plus the pelvis's pitch rate (the torso's less the spine's).
  -> thigh_rate(f, side)
    qd_of(f, side + "hip_flex") + f.torso_pitch_rate - qd_of(f, "spine_flex")

  -> dur_of(k)
    return @dur_load if k == :load
    return @dur_drive if k == :drive
    @dur_fly

  # ---- chunk goals -----------------------------------------------------------

  # keys 0: the chunk's goal is the keyframe posture (Pose, turned into one
  # contraction per muscle through the body's geometry at chunk entry).
  # keys 1: the goal is the keyframe's full contraction vector plus a
  # searched per-muscle offset, c_<kf>_<st|sw>_<muscle> (leg muscles; the
  # mirrored step reads the same offsets with the roles swapped).
  -> aim(ch, kf)
    return ch.pose(kf.pose) if @keys < ~0.5
    ch.to(contraction_of(kf))

  -> contraction_of(kf)
    c = kf.pose.apply(body, Contraction.fill(body.size, ~0.5))
    @leg_names.each ->(nm)
      role = "sw_"
      role = "st_" if nm.starts_with?(kf.stance)
      key = "c_" + kf.name + "_" + role + nm.slice(2, nm.size - 2)
      m = body.index(nm)
      c[m] = c[m] + @coff[key]
    c

  -> read_contraction_offsets
    @leg_names = []
    @coff = {}
    return self if @keys < ~0.5
    body.muscles.each ->(mu)
      nm = mu.name
      if nm.starts_with?("l_") || nm.starts_with?("r_")
        rest = nm.slice(2, nm.size - 2)
        leg = rest.starts_with?("hip") || rest.starts_with?("knee") || rest.starts_with?("ankle") || rest.starts_with?("toe")
        leg = leg || rest == "rf" || rest == "ham" || rest == "gas"
        @leg_names.push(nm) if leg
    ["td", "ms", "to"].each ->(kf)
      @leg_names.each ->(nm)
        if nm.starts_with?("r_")
          rest = nm.slice(2, nm.size - 2)
          ["st_", "sw_"].each ->(role)
            key = "c_" + kf + "_" + role + rest
            @coff[key] = param(key, ~0.0, ~-0.15, ~0.15)
    self

  # ---- chunks -----------------------------------------------------------------

  # Chunk duration: the stated time (timing 0), or the largest joint travel
  # from the previous keyframe at the stride's joint speed (timing 1).
  -> chunk_time(t, goal, from)
    return t if @timing < ~0.5
    d = goal.travel(from) / @omega
    return ~0.03 if d < ~0.03
    d

  -> styled(ch, ease, via)
    ch.ease(ease)
    ch.via if via
    ch

  # Touchdown -> mid-stance: the landing leg yields into the knee spring while
  # the swing heel tucks; ends when the COM passes over the stance foot.
  -> load_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "load", chunk_time(@t_load, goal, from)), goal)
    styled(ch, @ease_load, @via)
    mid = Latch.test("mid:" + st, ->(f, e, c) f.com_x - f.at(st + "foot_pos", 0) > @d_ms)
    ch.hold_until(mid.after_min(@t_ms_min), @t_ms_max)
    ch.drive(drive_vec([st + "knee_neg", @pre_knee, st + "ankle_pos", @pre_ankle, sw + "knee_pos", @drv_tuck]))
    ch.correct(->(f, c) correction(f, c, st, sw, :stance), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :load))
    ch

  # Mid-stance -> toe-off: the power leg extends behind with the push-off
  # burst, the alternate knee drives up; ends when the foot leaves the ground.
  -> drive_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "drive", chunk_time(@t_drive, goal, from)), goal)
    styled(ch, @ease_drive, @via)
    off = Latch.release(st + "foot")
    ch.hold_until(off.after_min(~0.03), @t_drive_max)
    ch.drive(push_drive(st, sw))
    ch.correct(->(f, c) correction(f, c, st, sw, :stance), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :drive))
    ch

  # Toe-off -> the other leg's touchdown: `st` just pushed and folds, `sw`
  # reaches for its landing; ends on `sw`'s foot contact.
  -> flight_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "flight", chunk_time(@t_fly, goal, from)), goal)
    styled(ch, @ease_fly, @via_fly)
    touch = Latch.contact(sw + "foot")
    ch.hold_until(touch.after_min(~0.03), ~0.45)
    ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, st + "rf", @drv_rf, sw + "knee_neg", @drv_pre,
                        sw + "ankle_pos", @drv_pre_ank, sw + "gas", @drv_pre_ank]))
    ch.correct(->(f, c) correction(f, c, st, sw, :flight), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :flight))
    ch

  # ---- standing start ----------------------------------------------------------

  # (quiet stance has its own co-contraction, stiff0: the running stance's
  # stiff_st locks the knees of a standing body)
  -> stand_pose(p)
    rad = ~0.017453292519943295
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", ~0.05, @stiff0)
      p.set(s + "knee", ~0.12, @stiff0)
      p.set(s + "ankle", ~-0.05, @stiff0)
      p.set(s + "shoulder_flex", ~0.0, @stiff_up)
      p.set(s + "elbow", ~85.0 * rad, @stiff_up)
    p.set("spine_flex", (~4.0 + @d_spine) * rad, @stiff_up)
    p

  # Quiet stance while the reflexes settle (ankle strategy holds the COM just
  # ahead of the ankles).
  -> stand_chunk
    ch = Chunk.new("stand", ~0.3).pose(stand_pose(Pose.new)).hold_until(Latch.after(~0.5))
    ch.correct(->(f, c) balance(f, ~0.05), ~0.08)
    ch.gain(@g0)
    ch

  # Tip forward: the ankle strategy's COM target moves toward the toes until
  # the COM is d_go ahead of the ankles.
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

  # First push: the left leg drives the body push0_amp of the way from
  # standing to the left toe-off keyframe (from rest, the full knee drive
  # throws the trunk back).
  -> first_push(goal)
    off = Latch.release("l_foot")
    ch = aim(Chunk.new("l_push0", ~0.25), blend_from_stand(goal, @push0_amp))
    ch.hold_until(off.after_min(~0.15), @t0_max)
    ch.drive(drive_vec(["l_knee_neg", @drv0_knee, "l_ankle_pos", @drv0_ankle, "l_hip_flex_neg", @drv0_hip, "l_gas", @drv0_ankle]))
    ch.correct(->(f, c) correction(f, c, "l_", "r_", :stance), @spring)
    ch.on_enter(->(f, c) start_stride(f))
    ch

  # A keyframe `amp` of the way from the standing posture to `kf`.
  -> blend_from_stand(kf, amp)
    rad = ~0.017453292519943295
    out = RunNaturalKeyframe.new(kf.name)
    out.set_stance(kf.stance)
    i = 0
    while i < kf.joints.size
      j = kf.joints[i]
      q0 = ~0.0
      q0 = ~0.05 if j.ends_with?("hip_flex")
      q0 = ~0.12 if j.ends_with?("knee")
      q0 = ~-0.05 if j.ends_with?("ankle")
      q0 = ~85.0 * rad if j.ends_with?("elbow")
      q0 = (~4.0 + @d_spine) * rad if j == "spine_flex"
      out.set(j, q0 + amp * (kf.angles[i] - q0), kf.stiff[i])
      i += 1
    out

  -> start_stride(f)
    @t_go = f.t
    enter(f, "l_", "r_", :drive)

  -> feet_x(f)
    (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5

  # Ankle strategy (plantarflex when the COM is ahead of its target) plus a
  # hip strategy holding the trunk at its reference lean.
  -> balance(f, target)
    dq = ~2.0 * (f.com_x - feet_x(f) - target) + ~0.4 * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    hip = ~0.0 - @k_bal * (f.torso_pitch - @trunk_ref) - ~0.2 * f.torso_pitch_rate
    joint_offset(off, "l_hip_flex", hip)
    joint_offset(off, "r_hip_flex", hip)
    off

  # ---- per-tick state -----------------------------------------------------------

  -> enter(f, st, sw, phase)
    note_duration(f.t - @t_phase) if @phase != nil && @phase != phase
    @st = st
    @sw = sw
    @phase = phase
    @t_phase = f.t
    self

  # Running estimate of each phase's duration (the ordered stride times the
  # keyframes that have no event of their own by it).
  -> note_duration(d)
    return self if d < ~0.02 || d > ~0.6
    @dur_load = ~0.5 * (@dur_load + d) if @phase == :load
    @dur_drive = ~0.5 * (@dur_drive + d) if @phase == :drive
    @dur_fly = ~0.5 * (@dur_fly + d) if @phase == :flight
    self

  -> before(frame, ctl)
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    if @t_go >= ~0.0
      @v_des = @v0 + @accel * (frame.t - @t_go)
      @v_des = @speed if @v_des > @speed
    # lean into the acceleration, rise to the reference trunk at speed
    @trunk_des = @trunk_ref + @lean * ~0.017453292519943295 + @lean_acc * (~1.0 - @v_des / @speed)
    @z_err = @z_ref - frame.pelvis_height
    scale_drives
    self

  # Per-leg reflex gains: the stance hip firm (it carries the torso), the
  # loading knee and ankle at their own (softer) gains, the swing leg loose;
  # in flight the landing leg is the firm one.
  -> after(frame, ctl)
    return self if @phase == nil
    firm = @st
    loose = @sw
    soft = @phase == :load
    if @phase == :flight
      firm = @sw
      loose = @st
      soft = true
    g_kl = @g_st
    g_al = @g_st
    if soft
      g_kl = @g_kl
      g_al = @g_al
    gs = @g_st
    gw = @g_sw
    @hip_idx[firm].each ->(m) ctl.set_gain(m, gs)
    @knee_idx[firm].each ->(m) ctl.set_gain(m, g_kl)
    @ankle_idx[firm].each ->(m) ctl.set_gain(m, g_al)
    @leg_idx[loose].each ->(m) ctl.set_gain(m, gw)
    gk = @g_swk
    @knee_idx[loose].each ->(m) ctl.set_gain(m, gk)
    self

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))

  # ---- drives --------------------------------------------------------------------

  -> push_drive(st, sw)
    d = drive_vec([sw + "hip_flex_pos", @drv_lift])
    @drives.push([d, index_or(st + "knee_neg"), index_or(st + "ankle_pos"), index_or(st + "gas"),
                  index_or(st + "hip_flex_neg"), index_or(st + "ham")])
    d

  -> index_or(name)
    return body.index(name) if body.has?(name)
    -1

  # The push-off burst grows with the speed plan and with the speed deficit,
  # and the knee and ankle extensors add the hop-height term.
  -> scale_drives
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @speed, ~0.0, ~1.0)
    s = clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)
    h = @k_z * @z_err
    vals = [@drv_knee * s + h, @drv_ankle * s + h, @drv_gas * s + h, @drv_hip * s, @drv_ham * s]
    @drives.each ->(e)
      d = e[0]
      k = 0
      while k < 5
        d[e[k + 1]] = clamp(vals[k], ~0.0, ~1.0) if e[k + 1] >= 0
        k += 1
    self

  -> drive_vec(pairs)
    d = zeros
    i = 0
    while i < pairs.size
      d[body.index(pairs[i])] = pairs[i + 1] if body.has?(pairs[i])
      i += 2
    d

  # ---- corrections ------------------------------------------------------------------

  # Spring-eased offsets around the keyframes (radians), each clamped to
  # +-corr_lim. In stance the stance hip carries the torso (see w_hip) and the
  # swing hip holds its thigh angle in world frame (pelvis pitch compensated).
  # In flight nothing anchors the pelvis, so the trailing leg is the reaction
  # mass of the torso PD, and the landing hip is placed: Raibert's speed
  # term, pelvis-pitch compensation, and past t_fly swing-leg retraction
  # (Seyfarth et al. 2003) so the foot meets the ground moving backward.
  -> correction(f, ctl, st, sw, phase)
    off = zeros
    lim = @corr_lim
    nlim = ~0.0 - lim
    err = f.torso_pitch - @trunk_des
    tilt = pelvis_pitch(f) - @pelvis_ref
    if phase == :flight
      fly = clamp(~0.0 - @fly_kp * err - @fly_kd * f.torso_pitch_rate, nlim, lim)
      joint_offset(off, st + "hip_flex", fly)
      late = f.t - @t_phase - @t_fly
      late = ~0.0 if late < ~0.0
      place = @cv * (@v_f - @v_des) + @comp * tilt - @retract * late
      joint_offset(off, sw + "hip_flex", clamp(place, nlim, lim))
      return off
    joint_offset(off, st + "hip_flex", torso_servo(f, ctl, st, sw))
    joint_offset(off, sw + "hip_flex", clamp(@comp * tilt, nlim, lim))
    low = @z_err
    low = ~0.0 if low < ~0.0
    joint_offset(off, st + "knee", clamp(~0.0 - @k_zk * low, nlim, ~0.0))
    off

  # Stance hip: w_hip x (measured angle led by its rate, minus the command)
  # hands the hip from the keyframe to the torso PD; the swing hip's servo
  # error is cancelled (SIMBICON: tau_stance = -tau_torso - tau_swing).
  -> torso_servo(f, ctl, st, sw)
    j = st + "hip_flex"
    free = q_of(f, j) + @hip_lead * qd_of(f, j) - pair_angle(ctl.command.values, j)
    err = f.torso_pitch - @trunk_des
    pd = ~0.0 - @torso_kp * err - @torso_kd * f.torso_pitch_rate - @k_swc * servo_error(f, ctl, sw + "hip_flex")
    @w_hip * free + clamp(pd, ~0.0 - @corr_lim, @corr_lim)

  -> servo_error(f, ctl, joint)
    pair_angle(ctl.target, joint) - q_of(f, joint)

  # A joint's angle as its own antagonist pair commands it.
  -> pair_angle(values, joint)
    p = body.index(joint + "_pos")
    n = body.index(joint + "_neg")
    (body.muscle(p).angle_at(values[p]) + body.muscle(n).angle_at(values[n])) * ~0.5

  -> q_of(f, joint)
    f.q(body, joint)

  -> qd_of(f, joint)
    f.qd(body, joint)

# A keyframe posture: joint angles (radians) with per-joint co-contraction.
+ RunNaturalKeyframe
  ro :name
  ro :joints
  ro :angles
  ro :stiff
  -> new(@name)
    @joints = []
    @angles = []
    @stiff = []
    @stance = "r_"
    @source = nil

  # "r_" for an authored (right-stance) keyframe, "l_" for its mirror.
  -> stance
    @stance

  -> set_stance(side)
    @stance = side
    self

  -> set(joint, q, s)
    @joints.push(joint)
    @angles.push(q)
    @stiff.push(s)
    self

  -> angle(joint)
    i = 0
    while i < @joints.size
      return @angles[i] if @joints[i] == joint
      i += 1
    ~0.0

  # Left/right swapped (the other step). The angles are kept for travel(); the
  # goal posture is the authored keyframe's Pose#mirror (see pose).
  -> mirror
    out = RunNaturalKeyframe.new(@name)
    out.set_stance("l_") if @stance == "r_"
    out.set_source(self)
    i = 0
    while i < @joints.size
      j = @joints[i]
      if j.starts_with?("l_")
        j = "r_" + j.slice(2, j.size - 2)
      elsif j.starts_with?("r_")
        j = "l_" + j.slice(2, j.size - 2)
      out.set(j, @angles[i], @stiff[i])
      i += 1
    out

  -> set_source(kf)
    @source = kf
    self

  -> pose
    return @source.pose.mirror if @source != nil
    p = Pose.new
    i = 0
    while i < @joints.size
      p.set(@joints[i], @angles[i], @stiff[i])
      i += 1
    p

  # Largest joint travel (radians) from `other` to this keyframe.
  -> travel(other)
    m = ~0.0
    i = 0
    while i < @joints.size
      d = (@angles[i] - other.angle(@joints[i])).abs
      m = d if d > m
      i += 1
    m
