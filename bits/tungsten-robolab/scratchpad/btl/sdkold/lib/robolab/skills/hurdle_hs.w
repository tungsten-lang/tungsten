# HurdleHS: the high-school boys' 110 m hurdles (10 x 0.991 m, 9.14 m apart)
# on RunSkill's running gait, so any body RunSkill runs on (v1, v2, v3) can
# hurdle with that body's practised run (params/run_v3.txt for the v3 body).
#
# One track drives every muscle. The run is RunSkill's stride (land -> push
# -> flight per leg, with its torso, placement and speed corrections); this
# skill adds a stride planner, the take-off routing and one clearance per
# lead leg:
#
#   start      stand -> lean -> l_push (first) -> l_flight (the run loop)
#   run        l_flight -> r_land -> r_push -> r_flight -> l_land -> l_push ...
#   clearance  L_* (left leg leads, the right foot takes off) and R_*:
#                plant   the take-off foot lands (placed att_reach further
#                        ahead on a knee att_knee straighter by the planner's
#                        last flight) and loads on a firm knee while the lead
#                        knee drives forward folded; latched like a landing
#                attack  take-off: drive bursts on the take-off leg's
#                        extensors and the lead hip flexors (the knee drive),
#                        the trunk leans in, the opposite arm reaches; latched
#                        on the take-off foot releasing
#                lead    the lead leg extends heel-first over the bar, the
#                        trunk dips toward it, the trail knee folds behind (and,
#                        on a body with 3D hips, starts to abduct); latched on
#                        the lead foot passing the bar
#                trail   the lead leg comes down, the trail leg is pulled
#                        through high: thigh forward, knee folded, and with 3D
#                        hips abducted and turned out so the knee comes around
#                        the side; latched on the trail KNEE passing the bar
#                        (from the sensed hip angles: with the thigh back and
#                        the knee folded the foot is ahead of the knee) or the
#                        lead foot landing first
#                snap    the lead leg snaps down to land, the trail knee keeps
#                        driving forward as the next swing; latched on the lead
#                        foot's contact
#                land    stance on the lead leg (its own knee and ankle gains
#                        and an extensor drive: it comes down harder than a
#                        running step), trunk servoed back up, then straight
#                        into that leg's push (the run resumes)
#
# On the flight onto the take-off step the leg that will lead swings through
# early (h_pre_hip, h_pre_knee), so the knee drive is under way at the plant.
#
# Stride planner: at every touchdown within h_plan_n nominal steps of the
# take-off spot (bar - h_d_to), the distance to it is split into the nearest
# whole number n of nominal steps (h_step), so the next step should be
# distance / n long; in flight the landing hip is nudged by h_w_stride x (that
# step - the measured running average step) / leg length, capped at h_max_adj
# m (a longer step reaches further). So the step rhythm between hurdles
# follows from h_step and h_d_to (4 steps of ~1.5 m at 5 m/s, for example),
# and every step on the way absorbs a share of the error. The push-off
# drive is also scaled by the planned step against the average (h_k_sdrv).
# The take-off is the touchdown whose distance to the bar is within half a
# nominal step of h_d_to (whichever foot it is; the other leg leads).
#
# Over the bar every leg still short of it is lifted in proportion to how far
# its sole sits below bar height + h_want (the sensed bar height, so the
# corrections scale with the hurdle): the lead hip flexes and its knee
# extends (heel first), the trail knee folds, its hip flexes and abducts, its
# ankle dorsiflexes (foot flat). The
# arms servo trunk pitch in the air. The lead knee is opened by a heel aim
# (h_aim, see heel_aim) as the thigh rises. The air chunks end on the lead foot's
# ground contact (contact with the foot low), never on a brush of the bar.
#
# Air chunks carry drive bursts (the lead knee's kick and hip lift, the trail
# hip's pull-through, the snap-down) and a searched easing each (min-jerk, or
# a front-loaded linear / cubic-out / sine-out / quint-out).
#
# `h_via 1` (a params-file switch) makes the air keyframes (lead, trail)
# via-points: the command passes through them with velocity continuity
# (cubic Hermite, Catmull-Rom tangents) into the snap-down instead of easing
# to rest at each.

+ HurdleHSSkill < RunSkill
  -> start(frame, ctl)
    read_params
    @v_f = ~0.0
    @v_des = ~0.0
    @t_go = ~-1.0
    @z_err = ~0.0
    @torso_des = @lean + @fall_lean
    @drives = []
    @phase = nil
    @t_phase = ~0.0
    @lifted = {}
    @lifted["l_"] = false
    @lifted["r_"] = false
    @st = "l_"
    @sw = "r_"
    @has_target = false
    @target_x = ~0.0
    @plan_step = ~0.0
    @stride = ~0.0
    @last_foot = ~-99.0
    @bar_x = ~99.0
    @bar_h = ~0.0
    @steps_left = 0
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    biart = body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(biart, @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle", side + "toe", side + "rf", side + "ham", side + "gas"])
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "gas", side + "toe"])
    mv = Movement.new("hurdle_hs")
    mv.add(stand_chunk)
    mv.add(lean_chunk)
    first = mv.add(push_chunk("l_", "r_", true))
    first.followed_by("l_flight")
    clearance(mv, "l_", "r_")
    clearance(mv, "r_", "l_")
    cycle = mv.size
    mv.add(flight_chunk("l_", "r_", nil))
    mv.add(land_chunk("r_", "l_"))
    mv.add(push_chunk("r_", "l_", false))
    mv.add(flight_chunk("r_", "l_", nil))
    mv.add(land_chunk("l_", "r_"))
    mv.add(push_chunk("l_", "r_", false))
    mv.loop_from(cycle)
    @track = ctl.add_track(Track.new("body", mv, body.all))
    self

  -> read_params
    super
    # air keyframes as via-points (a params-file switch, not a tunable)
    @h_via = ~0.0
    @h_via = @params["h_via"] if @params.key?("h_via")
    # stride planner and take-off window
    @d_to = param("h_d_to", ~1.6, ~0.8, ~2.4)
    @h_step = param("h_step", ~1.6, ~1.1, ~2.1)
    @h_win = param("h_win", ~0.5, ~0.2, ~0.8)
    @d_min = param("h_d_min", ~0.7, ~0.4, ~1.2)
    # take-off guard (a params-file switch): also take off from a touchdown
    # whose next step would land closer than h_d_min (instead of running into
    # the hurdle when two touchdowns straddle the window)
    @to_guard = ~0.0
    @to_guard = @params["h_to_guard"] if @params.key?("h_to_guard")
    @w_stride = param("h_w_stride", ~0.5, ~0.0, ~1.5)
    @max_adj = param("h_max_adj", ~0.15, ~0.0, ~0.35)
    @plan_n = param("h_plan_n", ~6.0, ~1.0, ~12.0)
    # push-off drive scaled by the planned step against the running average
    # (a longer planned step pushes harder): 1 + h_k_sdrv (plan - avg) / avg
    @k_sdrv = param("h_k_sdrv", ~0.0, ~0.0, ~3.0)
    @step_min = param("h_step_min", ~1.0, ~0.7, ~1.6)
    @step_max = param("h_step_max", ~2.1, ~1.5, ~2.5)
    @leg_len = param("h_leg_len", ~0.9, ~0.75, ~0.98)
    @att_reach = param("h_att_reach", ~0.2, ~-0.3, ~0.6)
    @att_knee = param("h_att_knee", ~0.0, ~-0.3, ~0.5)
    # the flight onto the take-off step: the future lead leg (the one that
    # just pushed) swings through early, thigh forward and knee folded, so the
    # knee drive is already under way when the take-off foot lands
    @pre_hip = param("h_pre_hip", ~0.3, ~0.0, ~1.2)
    @pre_knee = param("h_pre_knee", ~0.3, ~0.0, ~1.2)
    # plant
    @pl_t = param("h_pl_t", ~0.05, ~0.02, ~0.2)
    @pl_absorb = param("h_pl_absorb", ~0.03, ~0.0, ~0.12)
    @pl_st_hip = param("h_pl_st_hip", ~0.0, ~-0.4, ~0.4)
    @pl_knee = param("h_pl_knee", ~0.3, ~0.05, ~1.0)
    @pl_ld_hip = param("h_pl_ld_hip", ~1.0, ~0.0, ~2.0)
    @pl_ld_knee = param("h_pl_ld_knee", ~2.0, ~0.8, ~2.5)
    @pl_spine = param("h_pl_spine", ~0.35, ~-0.2, ~0.9)
    @g_plant = param("h_g_plant", ~1.2, ~0.3, ~2.5)
    # attack (take-off)
    @at_t = param("h_at_t", ~0.12, ~0.04, ~0.3)
    @at_min = param("h_at_min", ~0.05, ~0.0, ~0.15)
    @at_max = param("h_at_max", ~0.25, ~0.1, ~0.5)
    @at_drive = param("h_at_drive", ~1.0, ~0.0, ~1.0)
    @at_hipd = param("h_at_hipd", ~0.5, ~0.0, ~1.0)
    @at_ld_drive = param("h_at_ld_drive", ~0.8, ~0.0, ~1.0)
    @at_st_hip = param("h_at_st_hip", ~-0.4, ~-0.7, ~0.4)
    @at_st_knee = param("h_at_st_knee", ~0.05, ~0.0, ~0.6)
    @at_st_ank = param("h_at_st_ank", ~0.6, ~0.0, ~0.9)
    @at_ld_hip = param("h_at_ld_hip", ~1.6, ~0.8, ~2.2)
    @at_ld_knee = param("h_at_ld_knee", ~2.0, ~0.6, ~2.5)
    @at_spine = param("h_at_spine", ~0.5, ~-0.2, ~1.0)
    @at_arm = param("h_at_arm", ~1.8, ~0.3, ~2.8)
    @arm_b = param("h_arm_b", ~-0.5, ~-1.0, ~0.3)
    @at_pitch = param("h_at_pitch", ~0.1, ~-0.2, ~0.6)
    @g_at = param("h_g_at", ~1.2, ~0.3, ~2.5)
    # lead
    @ld_t = param("h_ld_t", ~0.15, ~0.04, ~0.35)
    @ld_max = param("h_ld_max", ~0.4, ~0.1, ~0.6)
    @ld_clear = param("h_ld_clear", ~0.0, ~-0.3, ~0.5)
    @ld_hip = param("h_ld_hip", ~1.6, ~0.8, ~2.2)
    @ld_knee = param("h_ld_knee", ~0.2, ~0.0, ~1.2)
    @ld_ank = param("h_ld_ank", ~0.0, ~-0.5, ~0.7)
    @ld_tr_hip = param("h_ld_tr_hip", ~-0.4, ~-0.6, ~0.8)
    @ld_tr_knee = param("h_ld_tr_knee", ~2.0, ~0.5, ~2.5)
    @ld_tr_abd = param("h_ld_tr_abd", ~0.3, ~-0.2, ~0.8)
    @ld_tr_rot = param("h_ld_tr_rot", ~0.0, ~-0.6, ~0.6)
    @ld_tr_ank = param("h_ld_tr_ank", ~0.3, ~-0.6, ~0.9)
    @ld_spine = param("h_ld_spine", ~0.8, ~0.0, ~1.2)
    @ld_arm = param("h_ld_arm", ~2.0, ~0.3, ~2.8)
    # trail
    @tl_t = param("h_tl_t", ~0.12, ~0.04, ~0.35)
    @tl_max = param("h_tl_max", ~0.3, ~0.1, ~0.7)
    @tl_clear = param("h_tl_clear", ~0.0, ~-0.3, ~0.5)
    @tl_ld_hip = param("h_tl_ld_hip", ~0.6, ~-0.3, ~1.6)
    @tl_ld_knee = param("h_tl_ld_knee", ~0.05, ~0.0, ~1.0)
    @tl_tr_hip = param("h_tl_tr_hip", ~1.4, ~0.0, ~2.2)
    @tl_tr_knee = param("h_tl_tr_knee", ~2.3, ~1.0, ~2.5)
    @tl_tr_ank = param("h_tl_tr_ank", ~-0.3, ~-0.6, ~0.6)
    @tl_tr_abd = param("h_tl_tr_abd", ~0.6, ~-0.2, ~0.8)
    @tl_tr_rot = param("h_tl_tr_rot", ~-0.3, ~-0.6, ~0.6)
    @tl_spine = param("h_tl_spine", ~0.6, ~0.0, ~1.2)
    @tl_arm = param("h_tl_arm", ~0.5, ~-0.5, ~2.5)
    # snap-down
    @sn_t = param("h_sn_t", ~0.12, ~0.03, ~0.3)
    @sn_ld_hip = param("h_sn_ld_hip", ~0.0, ~-0.5, ~0.6)
    @sn_ld_knee = param("h_sn_ld_knee", ~0.15, ~0.0, ~1.0)
    @sn_ld_ank = param("h_sn_ld_ank", ~0.1, ~-0.3, ~0.7)
    @sn_tr_hip = param("h_sn_tr_hip", ~1.2, ~0.2, ~2.0)
    @sn_tr_knee = param("h_sn_tr_knee", ~2.0, ~0.5, ~2.5)
    @sn_tr_abd = param("h_sn_tr_abd", ~0.3, ~-0.2, ~0.8)
    # landing
    @hl_knee = param("h_hl_knee", ~0.4, ~0.1, ~1.3)
    @hl_tr_hip = param("h_hl_tr_hip", ~0.9, ~-0.2, ~1.6)
    @hl_pitch = param("h_hl_pitch", ~-0.1, ~-0.5, ~0.4)
    @hl_k = param("h_hl_k", ~1.5, ~0.5, ~3.0)
    # the landing off a hurdle comes down faster than a running step: its own
    # knee and ankle reflex gains and an extensor drive
    @g_hlk = param("h_g_hlk", ~1.0, ~0.1, ~2.5)
    @g_hla = param("h_g_hla", ~1.0, ~0.1, ~2.5)
    @hl_drive = param("h_hl_drive", ~0.3, ~0.0, ~1.0)
    @hl_adrive = param("h_hl_adrive", ~0.3, ~0.0, ~1.0)
    # the landing stance lasts at least h_hl_min and ends on the COM rising or
    # passing h_hl_dpush ahead of the foot (defaults: the run's own)
    @hl_min = param("h_hl_min", @t_absorb, ~0.0, ~0.25)
    @hl_dpush = param("h_hl_dpush", @d_push, ~-0.2, ~0.6)
    # knee extensors pre-activated for the touchdown in the snap-down
    @sn_kdrive = param("h_sn_kdrive", ~0.0, ~0.0, ~1.0)
    # air corrections and gains
    @want = param("h_want", ~0.1, ~0.0, ~0.3)
    @k_lead = param("h_k_lead", ~2.0, ~0.0, ~6.0)
    @k_lead_kn = param("h_k_lead_kn", ~0.0, ~0.0, ~6.0)
    @aim = param("h_aim", ~0.8, ~0.0, ~1.0)
    @aim_dx = param("h_aim_dx", ~1.2, ~0.3, ~2.0)
    @aim_thigh = param("h_aim_thigh", ~1.0, ~0.4, ~1.6)
    @aim_hip = param("h_aim_hip", ~0.0, ~0.0, ~1.0)
    @k_trail = param("h_k_trail", ~2.0, ~0.0, ~6.0)
    @k_trail_h = param("h_k_trail_h", ~1.0, ~0.0, ~6.0)
    @k_trail_a = param("h_k_trail_a", ~1.0, ~0.0, ~6.0)
    @k_trail_ank = param("h_k_trail_ank", ~0.0, ~0.0, ~6.0)
    @k_arm = param("h_k_arm", ~0.3, ~0.0, ~3.0)
    @g_air = param("h_g_air", ~0.8, ~0.3, ~2.0)
    @h_elbow = param("h_elbow", ~1.6, ~0.3, ~2.3)
    # drive bursts in the air: the lead knee's kick (vasti, rectus femoris) and
    # hip lift, the trail knee's fold; the trail hip's pull-through (flexors,
    # abductors on a 3D hip) and the lead hip's descent; the snap-down
    @ld_kick = param("h_ld_kick", ~0.5, ~0.0, ~1.0)
    @ld_hipd = param("h_ld_hipd", ~0.3, ~0.0, ~1.0)
    @ld_trd = param("h_ld_trd", ~0.3, ~0.0, ~1.0)
    @tl_drive = param("h_tl_drive", ~0.5, ~0.0, ~1.0)
    @tl_abdd = param("h_tl_abdd", ~0.3, ~0.0, ~1.0)
    @tl_ldd = param("h_tl_ldd", ~0.3, ~0.0, ~1.0)
    @sn_drive = param("h_sn_drive", ~0.3, ~0.0, ~1.0)
    @sn_trd = param("h_sn_trd", ~0.3, ~0.0, ~1.0)
    # easing per clearance chunk, a categorical searched as a number:
    # 0 min_jerk, 1 linear, 2 cubic_out, 3 sine_out, 4 quint_out (the "out"
    # curves front-load the move: a kick, a snap)
    @at_ease = ease_of(param("h_at_ease", ~0.0, ~0.0, ~4.49))
    @ld_ease = ease_of(param("h_ld_ease", ~0.0, ~0.0, ~4.49))
    @tl_ease = ease_of(param("h_tl_ease", ~0.0, ~0.0, ~4.49))
    @sn_ease = ease_of(param("h_sn_ease", ~0.0, ~0.0, ~4.49))
    self

  -> ease_of(v)
    return :min_jerk if v < ~0.5
    return :linear if v < ~1.5
    return :cubic_out if v < ~2.5
    return :sine_out if v < ~3.5
    :quint_out

  # ---- per-tick ---------------------------------------------------------------

  -> before(frame, ctl)
    super(frame, ctl)
    name = @track.chunk_name
    if name == "l_flight" && frame.get("r_foot_contact") > ~0.05 && takeoff_due(frame, "r_")
      @track.jump(ctl, frame, "L_plant")
    elsif name == "r_flight" && frame.get("l_foot_contact") > ~0.05 && takeoff_due(frame, "l_")
      @track.jump(ctl, frame, "R_plant")
    self

  # Every landing (a run touchdown or the landing off a hurdle) re-plans the
  # steps to the next take-off.
  -> enter(f, st, sw, phase)
    super(f, st, sw, phase)
    touchdown(f, st) if phase == :land
    self

  # Gains for the clearance phases; the run's phases keep RunSkill's.
  -> after(frame, ctl)
    return self if @phase == nil
    if @phase == :air
      @leg_idx["l_"].each -> ctl.set_gain(item, @g_air)
      @leg_idx["r_"].each -> ctl.set_gain(item, @g_air)
      return self
    if @phase == :hland
      @hip_idx[@st].each -> ctl.set_gain(item, @g_st)
      @knee_idx[@st].each -> ctl.set_gain(item, @g_hlk)
      @ankle_idx[@st].each -> ctl.set_gain(item, @g_hla)
      @leg_idx[@sw].each -> ctl.set_gain(item, @g_sw)
      return self
    if @phase == :plant || @phase == :attack
      g = @g_at
      g = @g_plant if @phase == :plant
      @leg_idx[@st].each -> ctl.set_gain(item, g)
      @leg_idx[@sw].each -> ctl.set_gain(item, @g_air)
      return self
    super(frame, ctl)

  -> other(side)
    return "r_" if side == "l_"
    "l_"

  -> hname(ld)
    return "L_" if ld == "l_"
    "R_"

  # ---- stride planning ----------------------------------------------------------

  -> takeoff_due(f, side)
    return false if f.at("hurdle", 1) <= ~0.0
    gap = f.com_x + f.get("hurdle") - f.at(side + "foot_pos", 0)
    return false if gap <= @d_min
    return true if gap < @d_to + @h_step * @h_win
    @to_guard > ~0.5 && @stride > ~0.0 && gap - @stride < @d_min && gap < @d_to + @h_step

  -> touchdown(f, side)
    x = f.at(side + "foot_pos", 0)
    note_step(x)
    @has_target = false
    @steps_left = 0
    return self if f.at("hurdle", 1) <= ~0.0
    left = f.com_x + f.get("hurdle") - @d_to - x
    return self if left < ~0.3
    n = (left / @h_step + ~0.5).floor
    n = 1 if n < 1
    return self if n > @plan_n
    @plan_step = clamp(left / n, @step_min, @step_max)
    @target_x = x + @plan_step
    @has_target = true
    @steps_left = n
    self

  # Running average of the step length (touchdown to touchdown).
  -> note_step(x)
    s = x - @last_foot
    if s > ~0.4 && s < ~2.8
      @stride = s if @stride <= ~0.0
      @stride = @stride * ~0.6 + s * ~0.4
    @last_foot = x
    self

  # Flight: RunSkill's placement plus the planner's nudge toward the planned
  # step, and on the take-off step (the last one planned) a plant further
  # ahead on a straighter knee.
  -> stride_correction(f, ctl, st, sw, phase)
    off = super(f, ctl, st, sw, phase)
    if phase == :flight && @has_target
      joint_offset(off, sw + "hip_flex", stride_nudge)
      if @steps_left == 1
        joint_offset(off, sw + "hip_flex", @att_reach)
        joint_offset(off, sw + "knee", ~0.0 - @att_knee)
        joint_offset(off, st + "hip_flex", @pre_hip)
        joint_offset(off, st + "knee", @pre_knee)
    off

  # RunSkill's drive scaling, then the planner's push scaling.
  -> scale_drives(frame)
    super(frame)
    return self if @k_sdrv <= ~0.0 || !@has_target || @stride <= ~0.5
    k = clamp(~1.0 + @k_sdrv * (@plan_step - @stride) / @stride, ~0.5, ~1.6)
    @drives.each ->(e)
      d = e[0]
      d[e[1]] = clamp(d[e[1]] * k, ~0.0, ~1.0)
      d[e[2]] = clamp(d[e[2]] * k, ~0.0, ~1.0)
      d[e[3]] = d[e[3]] * k
    self

  -> stride_nudge
    return ~0.0 if @stride <= ~0.0
    @w_stride * clamp(@plan_step - @stride, ~0.0 - @max_adj, @max_adj) / @leg_len

  # ---- clearance ----------------------------------------------------------------

  -> clearance(mv, ld, tr)
    p = hname(ld)
    rise = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over_tr = Latch.test("over:" + tr, ->(f, e, c) over_foot?(f, tr))
    ch = mv.add(Chunk.new(p + "plant", @pl_t).pose(plant_pose(ld, tr)))
    ch.hold_until(Latch.any([rise, over_tr]).after_min(@pl_absorb), ~0.3)
    ch.correct(->(f, c) attack_corr(f, c, ld, tr), @gait_spring)
    ch.on_enter(->(f, c) plant_enter(f, c, ld, tr))
    ch = mv.add(Chunk.new(p + "attack", @at_t).pose(attack_pose(ld, tr)).ease(@at_ease))
    ch.hold_until(Latch.release(tr + "foot").after_min(@at_min), @at_max)
    ch.drive(drive_vec([tr + "knee_neg", @at_drive, tr + "ankle_pos", @at_drive, tr + "hip_flex_neg", @at_drive * @at_hipd,
                        tr + "gas", @at_drive, tr + "toe_pos", @at_drive * ~0.5, ld + "hip_flex_pos", @at_ld_drive,
                        ld + "knee_pos", @at_ld_drive * ~0.5]))
    ch.correct(->(f, c) attack_corr(f, c, ld, tr), @gait_spring)
    ch.on_enter(->(f, c) enter(f, tr, ld, :attack))
    lead = Latch.test("lead_over", ->(f, e, c) past_bar(f, ld + "foot_pos", @ld_clear))
    ch = mv.add(Chunk.new(p + "lead", @ld_t).pose(lead_pose(ld, tr)).ease(@ld_ease))
    ch.hold_until(lead, @ld_max)
    ch.drive(drive_vec([ld + "knee_neg", @ld_kick, ld + "rf", @ld_kick, ld + "hip_flex_pos", @ld_hipd, tr + "knee_pos", @ld_trd]))
    ch.correct(->(f, c) air_corr(f, c, ld, tr), @gait_spring)
    ch.on_enter(->(f, c) enter(f, tr, ld, :air))
    ch.via if @h_via > ~0.5
    # (a low flight can land before the trail foot is past: the lead foot's
    # contact ends the trail too, and the snap hands straight to the landing)
    trail = Latch.test("trail_over", ->(f, e, c) knee_x(f, tr) > @bar_x + @tl_clear)
    ch = mv.add(Chunk.new(p + "trail", @tl_t).pose(trail_pose(ld, tr)).ease(@tl_ease))
    ch.hold_until(Latch.any([trail, ground(ld)]), @tl_max)
    ch.drive(drive_vec([tr + "hip_flex_pos", @tl_drive, tr + "knee_pos", @tl_drive * ~0.5, tr + "hip_abd_pos", @tl_abdd,
                        ld + "hip_flex_neg", @tl_ldd, ld + "ham", @tl_ldd]))
    ch.correct(->(f, c) air_corr(f, c, ld, tr), @gait_spring)
    ch.via if @h_via > ~0.5
    ch = mv.add(Chunk.new(p + "snap", @sn_t).pose(snap_pose(ld, tr)).ease(@sn_ease))
    ch.hold_until(ground(ld).after_min(~0.02), ~0.8)
    ch.drive(drive_vec([ld + "hip_flex_neg", @sn_drive, ld + "ham", @sn_drive, tr + "hip_flex_pos", @sn_trd,
                        ld + "knee_neg", @sn_kdrive]))
    ch.correct(->(f, c) snap_corr(f, c, ld, tr), @gait_spring)
    ch.on_enter(->(f, c) enter(f, tr, ld, :flight))
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("h_over:" + ld, ->(f, e, c) f.com_x - f.at(ld + "foot_pos", 0) > @hl_dpush)
    ch = mv.add(Chunk.new(p + "land", @t_land).pose(h_land_pose(ld, tr)))
    ch.hold_until(Latch.any([rising, over]).after_min(@hl_min), ~0.35)
    ch.drive(drive_vec([ld + "knee_neg", @hl_drive, ld + "rf", @hl_drive * ~0.5, ld + "ankle_pos", @hl_adrive, ld + "gas", @hl_adrive]))
    ch.correct(->(f, c) land_corr(f, c, ld, tr), @gait_spring)
    ch.on_enter(->(f, c) land_enter(f, ld, tr))
    ch.followed_by(ld + "push")
    mv

  # A foot's contact with the ground, not with a hurdle's top board: the
  # contact sensor feels both, and a lead foot brushing the bar must not end
  # the clearance as if it had landed.
  -> ground(side)
    Latch.test("ground:" + side, ->(f, e, c) f.get(side + "foot_contact") > ~0.05 && f.at(side + "foot_pos", 2) < ~0.25)

  -> land_enter(f, ld, tr)
    enter(f, ld, tr, :hland)
    touchdown(f, ld)

  -> plant_enter(f, c, ld, tr)
    enter(f, tr, ld, :plant)
    @bar_x = f.com_x + f.get("hurdle")
    @bar_h = f.at("hurdle", 1)
    @has_target = false
    @steps_left = 0
    self

  -> past_bar(f, sensor, margin)
    f.at(sensor, 0) > @bar_x + margin

  # Hip abduction and rotation (bodies with 3D hips; ignored otherwise).
  -> hip3(p, side, abd, rot)
    p.set(side + "hip_abd", abd, @stiff_sw)
    p.set(side + "hip_rot", rot, @stiff_sw)
    p

  # Hurdle upper body: `fwd`'s arm reaches forward (the arm opposite the lead
  # leg), the other is held back; spine as given.
  -> h_upper(p, fwd, spine, arm_f)
    p.set(fwd + "shoulder_flex", arm_f, @stiff_up)
    p.set(other(fwd) + "shoulder_flex", @arm_b, @stiff_up)
    p.set("l_elbow", @h_elbow, @stiff_up)
    p.set("r_elbow", @h_elbow, @stiff_up)
    p.set("spine_flex", spine, @stiff_up)
    p

  -> plant_pose(ld, tr)
    p = Pose.new
    leg(p, tr, @psi_ms + @phi_nom + @pl_st_hip, @pl_knee, @a_land, @stiff_st)
    leg(p, ld, @pl_ld_hip, @pl_ld_knee, ~-0.1, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, ~0.0, ~0.0)
    h_upper(p, tr, @pl_spine, @at_arm * ~0.5)

  -> attack_pose(ld, tr)
    p = Pose.new
    leg(p, tr, @at_st_hip, @at_st_knee, @at_st_ank, @stiff_st)
    p.set(tr + "toe", @toe_push, @stiff_st)
    leg(p, ld, @at_ld_hip, @at_ld_knee, ~-0.2, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, ~0.0, ~0.0)
    h_upper(p, tr, @at_spine, @at_arm)

  -> lead_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @ld_hip, @ld_knee, @ld_ank, @stiff_sw)
    leg(p, tr, @ld_tr_hip, @ld_tr_knee, @ld_tr_ank, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, @ld_tr_abd, @ld_tr_rot)
    h_upper(p, tr, @ld_spine, @ld_arm)

  -> trail_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @tl_ld_hip, @tl_ld_knee, ~0.2, @stiff_sw)
    leg(p, tr, @tl_tr_hip, @tl_tr_knee, @tl_tr_ank, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, @tl_tr_abd, @tl_tr_rot)
    h_upper(p, tr, @tl_spine, @tl_arm)

  -> snap_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @psi_reach + @phi_nom + @sn_ld_hip, @sn_ld_knee, @sn_ld_ank, @stiff_st)
    leg(p, tr, @sn_tr_hip, @sn_tr_knee, ~-0.2, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, @sn_tr_abd, ~0.0)
    upper(p, ld, tr)

  -> h_land_pose(ld, tr)
    p = Pose.new
    leg(p, ld, @psi_ms + @phi_nom, @hl_knee, @a_land, @stiff_st)
    leg(p, tr, @hl_tr_hip, @k_mid, ~-0.1, @stiff_sw)
    hip3(p, ld, ~0.0, ~0.0)
    hip3(p, tr, ~0.0, ~0.0)
    upper(p, ld, tr)

  # ---- corrections ----------------------------------------------------------------

  # Torso pitch wanted now: the run's lean, plus `extra`, plus whatever the
  # chunk's spine command adds to the nominal spine (the dip over the bar),
  # so the servo never fights the pose.
  -> torso_target(ctl, extra)
    @torso_des + extra + pair_angle(ctl.command.values, "spine_flex") - @spine

  -> h_torso_servo(f, ctl, joint, extra, k)
    q = q_of(f, joint)
    qd = qd_of(f, joint)
    qc = pair_angle(ctl.command.values, joint)
    err = f.torso_pitch - torso_target(ctl, extra)
    q + @hip_lead * qd - qc - k * (@torso_kp * err + @torso_kd * f.torso_pitch_rate)

  # Take-off stance: the take-off hip servoes the torso toward a steeper lean
  # (h_at_pitch), the lead thigh keeps its world angle and the lead heel aims
  # over the bar.
  -> attack_corr(f, ctl, ld, tr)
    off = zeros
    torso = h_torso_servo(f, ctl, tr + "hip_flex", @at_pitch, ~1.0) - @k_swc * servo_error(f, ctl, ld + "hip_flex")
    joint_offset(off, tr + "hip_flex", torso)
    joint_offset(off, ld + "hip_flex", pelvis_pitch(f) - @phi_ref)
    heel_aim(off, f, ctl, ld)

  # Lead heel aim (a kinematic model of the leg: thigh and shin 0.43 m, the
  # sole 0.08 m under the ankle). From the sensed hip height and the lead
  # thigh's world angle, the most-flexed knee that keeps the lead heel above
  # bar + h_want is kappa = theta - acos((knee height - wanted ankle height) /
  # 0.43); while the lead foot is within h_aim_dx of the bar (short of it)
  # and the thigh is at least h_aim_thigh forward, a knee commanded more
  # flexed than that is opened toward it (h_aim of the difference): the leg
  # unfolds as fast as the thigh rises, heel first over the bar. The thigh
  # aim (h_aim_hip) raises the lead hip to the angle the straight leg needs.
  -> heel_aim(off, f, ctl, ld)
    dx = @bar_x - f.at(ld + "foot_pos", 0)
    return off if @aim <= ~0.0 || dx < ~0.0 || dx > @aim_dx
    theta = q_of(f, ld + "hip_flex") - pelvis_pitch(f)
    return off if theta < @aim_thigh
    knee_z = f.at("pelvis_pos", 2) - ~0.43 * Math.cos(theta)
    c = (knee_z - (@bar_h + @want + ~0.08)) / ~0.43
    # c >= 1: the heel clears at any knee angle; c <= -1: no knee angle
    # clears from this thigh angle (the thigh must rise first)
    return off if c >= ~1.0 || c <= ~-1.0
    target = theta - Math.acos(c)
    target = ~0.0 if target < ~0.0
    cmd = pair_angle(ctl.command.values, ld + "knee")
    joint_offset(off, ld + "knee", @aim * (target - cmd)) if target < cmd
    thigh_aim(off, f, ctl, ld)

  # Lead thigh aim: the world thigh angle at which the straight lead leg's
  # heel is at bar + h_want from the sensed hip height (leg 0.86 m, sole 0.08
  # m), turned into a hip angle through the sensed pelvis pitch; a lead hip
  # commanded lower than that is raised toward it (h_aim_hip of the gap).
  -> thigh_aim(off, f, ctl, ld)
    return off if @aim_hip <= ~0.0
    c = (f.at("pelvis_pos", 2) - (@bar_h + @want + ~0.08)) / ~0.86
    return off if c >= ~1.0
    theta = ~1.5708
    theta = Math.acos(c) if c > ~0.0
    need = theta + pelvis_pitch(f)
    cmd = pair_angle(ctl.command.values, ld + "hip_flex")
    joint_offset(off, ld + "hip_flex", @aim_hip * (need - cmd)) if need > cmd
    off

  # Over the bar: the arms steer trunk pitch; each leg short of the bar is
  # lifted by how far its sole sits below bar height + h_want.
  -> air_corr(f, ctl, ld, tr)
    off = zeros
    dq = @k_arm * (f.torso_pitch - torso_target(ctl, ~0.0))
    joint_offset(off, "l_shoulder_flex", dq)
    joint_offset(off, "r_shoulder_flex", dq)
    lift = clearance_short(f, ld, @bar_h + @want)
    joint_offset(off, ld + "hip_flex", @k_lead * lift)
    joint_offset(off, ld + "knee", ~0.0 - @k_lead_kn * lift)
    heel_aim(off, f, ctl, ld)
    trail_lift(off, f, tr)

  # The trail leg's tuck, kept up until it is past the bar: the knee folds
  # and the hip flexes by how far the sole sits below bar height + h_want,
  # and (3D hips) the hip abducts by how far the knee does.
  -> trail_lift(off, f, tr)
    lift = clearance_short(f, tr, @bar_h + @want)
    joint_offset(off, tr + "knee", @k_trail * lift)
    joint_offset(off, tr + "hip_flex", @k_trail_h * lift)
    joint_offset(off, tr + "hip_abd", @k_trail_a * knee_short(f, tr, @bar_h + @want))
    joint_offset(off, tr + "ankle", ~0.0 - @k_trail_ank * lift)
    off

  # The knee from the sensed hip angles (thigh 0.43 m; the abduction takes
  # its share out of the sagittal plane): x (m) and height (m).
  -> thigh_r(f, side)
    return ~0.43 if !body.has_joint?(side + "hip_abd")
    ~0.43 * Math.cos(q_of(f, side + "hip_abd"))

  -> knee_x(f, side)
    f.at("pelvis_pos", 0) + thigh_r(f, side) * Math.sin(q_of(f, side + "hip_flex") - pelvis_pitch(f))

  -> knee_z(f, side)
    f.at("pelvis_pos", 2) - thigh_r(f, side) * Math.cos(q_of(f, side + "hip_flex") - pelvis_pitch(f))

  # How far (m) the knee is below `want` while it is short of the bar.
  -> knee_short(f, side, want)
    return ~0.0 if knee_x(f, side) > @bar_x + ~0.1
    clamp(want - (knee_z(f, side) - ~0.05), ~0.0, ~0.4)

  -> snap_corr(f, ctl, ld, tr)
    trail_lift(stride_correction(f, ctl, tr, ld, :flight), f, tr)

  -> land_corr(f, ctl, ld, tr)
    off = zeros
    torso = h_torso_servo(f, ctl, ld + "hip_flex", @hl_pitch, @hl_k) - @k_swc * servo_error(f, ctl, tr + "hip_flex")
    joint_offset(off, ld + "hip_flex", torso)
    joint_offset(off, tr + "hip_flex", pelvis_pitch(f) - @phi_ref)
    toe_clearance(f, off, tr)
    trail_lift(off, f, tr)

  # How far (m) the sole is below `want` while the foot is short of (or over)
  # the bar; 0 once it is past.
  -> clearance_short(f, side, want)
    return ~0.0 if f.at(side + "foot_pos", 0) > @bar_x + ~0.15
    clamp(want - (f.at(side + "foot_pos", 2) - ~0.08), ~0.0, ~0.4)
