# MyoSoccerWalkSkill: the chase-tag walker (MyoWalkSkill, lib/robolab/skills/
# myo_walk.w) on the soccer body, for the phase-2 approach.
#
# The soccer body is the chase-tag myoLeg (the same 80 leg muscles, by name)
# with a lumbar spine and 210 trunk muscles instead of a torso rigid on the
# pelvis. So:
#
#   legs   the walker's two leg tracks, masked to the 80 leg muscles (a
#          muscle is a leg muscle when it crosses a leg joint and no lumbar
#          joint: the psoas slips Ps_* are trunk)
#   trunk  a third track on the trunk muscles holding the lumbar spine at
#          w_fe (a joint servo on the measured flexion and side bend: the
#          upper body nearly rigid on the pelvis, as on the chase-tag body)
#          and a feed-forward drive on the lumbar extensors (postural tone,
#          integrating the flexion's error), with per-muscle reflex gains
#          proportional to each muscle's length range.
#
#          Why extended (measured, playground/.. scratchpad trunk map): the
#          rectus abdominis's passive pull on the lumbar (~207 N m upright,
#          -108 at 0.3 rad of flexion) plus the upper body's weight needs, to
#          hold still, 84-123 % of all the extensors' capacity (145-200 N m)
#          whenever the thorax is upright, for any pelvis tilt; the soccer
#          stance runs there with the extensors' tone saturated. With the
#          lumbar extended 0.2-0.3 rad and the thorax leaning back 0.4-0.6
#          rad the abdominal pull and the weight nearly cancel: 50-65 %. So
#          the walker walks with the trunk leaning back, the pelvis within
#          0.2 rad of upright (the hips keep their extension range)
#   tilt   the walker's pelvis pitch target tipped back by w_tilt (the
#          soccer stance's reason: an upright pelvis stretches the rectus
#          abdominis, whose passive force folds the trunk forward)
#   rates  the walker's trunk rates are the pelvis's (pelvis_angvel; the
#          walker's torso is its pelvis); w_thor 1 balances the thorax instead
#   goal   the walking heading points at the approach spot (ap_dx, ap_dy from
#          the ball) and the speed tapers near it (see goal)
#
# The walker's hip torque map (MyoWalkHip) needs the muscle_fmax /
# muscle_range blocks, which the soccer task sends with `walk_consts 1`.

+ MyoSoccerWalkSkill < MyoWalkSkill
  -> start(frame, ctl)
    @g = body.geometry
    @nm = body.size
    @fe0 = frame.q(body, "flex_extension")
    @fe_tgt = @fe0
    @fe_t0 = ~0.0
    @w_prog = ~0.0
    classify_legs
    super(frame, ctl)
    setup_trunk(frame, ctl)
    self

  -> read_params
    super
    # trunk (the soccer skill's values)
    @w_ktr = param("w_ktr", ~107.7, ~20.0, ~300.0)
    @w_kdr = param("w_kdr", ~0.03, ~0.0, ~0.1)
    # the lumbar held extended (see the header: the trunk map)
    @w_fe = param("w_fe", ~0.25, ~-0.6, ~0.6)
    @w_poff = param("w_poff", ~0.4, ~0.0, ~0.8)
    @w_lmode = ~0.0
    @w_lmode = @params["w_lmode"] if @params.key?("w_lmode")
    @w_tp = param("w_tp", ~0.1, ~-0.4, ~0.5)
    @w_thor = ~0.0
    @w_thor = @params["w_thor"] if @params.key?("w_thor")
    @w_kth = param("w_kth", ~1.8, ~0.0, ~5.0)
    @w_kthd = param("w_kthd", ~0.44, ~0.0, ~1.5)
    @w_klb = param("w_klb", ~1.2, ~-3.0, ~3.0)
    @w_tone0 = param("w_tone0", ~1.0, ~0.0, ~1.0)
    @w_ktone = param("w_ktone", ~1.33, ~0.0, ~5.0)
    @w_stiff = param("w_stiff", ~0.04, ~0.0, ~0.2)
    # the pelvis tipped back (added to the walker's pitch_des, which every
    # leg goal is written against): at an upright pelvis the rectus
    # abdominis is stretched and its passive force (~207 N m) folds the trunk
    # forward, more than the back extensors can hold; the soccer stance
    # tilts the pelvis back and flexes the lumbar spine to slacken it
    @w_tilt = param("w_tilt", ~-0.15, ~-0.6, ~0.2)
    @pitch_des = @pitch_des + @w_tilt
    # the way in: from the reset (lumbar ~0, thorax upright: the extensors
    # are already short of the ~112 % that posture needs) the pelvis first
    # tips back to w_pd0 (the thorax with it, off the weight), the lumbar
    # extends to w_fe over w_t0, then the pelvis comes forward to its walking
    # tilt over w_t1
    @pitch_walk = @pitch_des
    @w_pd0 = param("w_pd0", ~-0.4, ~-0.6, ~0.0)
    @w_t0 = param("w_t0", ~0.8, ~0.1, ~3.0)
    @w_t1 = param("w_t1", ~0.8, ~0.1, ~3.0)
    @w_tstart = param("w_tstart", ~1.5, ~0.0, ~4.0)
    @w_tset = param("w_tset", ~0.0, ~0.0, ~3.0)
    @w_shp = param("w_shp", ~-0.4, ~-0.5, ~0.2)
    @w_skn = param("w_skn", ~0.41, ~0.0, ~1.0)
    @w_sank = param("w_sank", ~0.34, ~-0.2, ~0.5)
    @w_scom = param("w_scom", ~0.03, ~-0.1, ~0.15)
    @w_tset1 = param("w_tset1", ~0.0, ~0.0, ~3.0)
    @w_kpp = param("w_kpp", ~1.5, ~0.0, ~6.0)
    @w_kppd = param("w_kppd", ~0.3, ~0.0, ~2.0)
    @w_sk_ank = param("w_sk_ank", ~5.0, ~0.0, ~12.0)
    @w_sd_ank = param("w_sd_ank", ~0.9, ~0.0, ~3.0)
    @w_sk_hp = param("w_sk_hp", ~0.4, ~0.0, ~3.0)
    @w_sd_hp = param("w_sd_hp", ~0.1, ~0.0, ~1.0)
    @t_now = ~0.0
    @pitch_des = @pitch_walk + @w_pd0
    # the approach: the spot (pelvis) relative to the ball, the distance
    # below which the speed tapers (to w_vmin of v_walk), and the arrival
    # radius
    @ap_dx = param("ap_dx", ~-1.0, ~-1.6, ~-0.3)
    @ap_dy = param("ap_dy", ~0.0, ~-0.4, ~0.4)
    @ap_slow = param("ap_slow", ~0.6, ~0.1, ~2.0)
    @ap_vmin = param("ap_vmin", ~0.3, ~0.0, ~1.0)
    @approach_on = @params.key?("approach_on") && @params["approach_on"] > ~0.5
    self

  # ---- muscles ----------------------------------------------------------------

  -> classify_legs
    g = @g
    lumbar = {}
    legj = {}
    g.joint_names.each ->(nm)
      j = g.joint(nm)
      lumbar[j] = true if nm == "flex_extension" || nm == "lat_bending" || nm == "axial_rotation"
      legj[j] = true if nm.starts_with?("hip_") || nm.starts_with?("knee_") || nm.starts_with?("ankle_") || nm.starts_with?("subtalar_") || nm.starts_with?("mtp_")
    crosses_leg = (0...@nm).map -> false
    crosses_lumbar = (0...@nm).map -> false
    legj.keys.each ->(j)
      g.crossing(j).each ->(m) crosses_leg[m] = true
    lumbar.keys.each ->(j)
      g.crossing(j).each ->(m) crosses_lumbar[m] = true
    @is_leg = (0...@nm).map ->(i) crosses_leg[i] && !crosses_lumbar[i]
    @trunk = []
    i = 0
    while i < @nm
      @trunk.push(i) if !@is_leg[i]
      i += 1
    self

  # The walker's per-side masks, leg muscles only.
  -> side_mask(suffix)
    out = []
    n = body.size
    i = 0
    while i < n
      out.push(i) if @is_leg[i] && body.muscle(i).name.ends_with?(suffix)
      i += 1
    out

  -> lumbar_mode
    [["flex_extension", ~1.0], ["Abs_r3", ~0.6429], ["L4_L5_FE", ~0.185], ["L3_L4_FE", ~0.204], ["L2_L3_FE", ~0.231], ["L1_L2_FE", ~0.255]]

  # The trunk track: the soccer stance's lumbar posture held by the trunk
  # muscles' reflexes (gains proportional to their length ranges), the
  # lumbar servo as its correction, and the extensors for postural tone.
  -> setup_trunk(frame, ctl)
    g = @g
    @extensors = []
    @trunk.each ->(i)
      rg = g.range(i)
      kp = @w_ktr * (rg[1] - rg[0])
      ctl.reflex.set_gains([i], kp, kp * @w_kdr)
      s = ~0.0
      lumbar_mode.each ->(pair)
        jj = g.joint(pair[0])
        s = s + pair[1] * g.contraction_slope(i, jj) if jj != nil
      @extensors.push(i) if s > ~0.02
    # trunk muscles that also cross a hip (the psoas slips): their targets
    # follow the measured hip angles, so the legs' motion does not stretch
    # them into flexing the spine
    @thip = []
    ["l", "r"].each ->(sd)
      ["hip_flexion_", "hip_adduction_", "hip_rotation_"].each ->(jn)
        j = g.joint(jn + sd)
        ms = []
        g.crossing(j).each ->(m) ms.push(m) if !@is_leg[m]
        @thip.push([jn + sd, j, ms]) if ms.size > 0
    p = MyoSoccerPosture.new(g, false)
    p.set("flex_extension", @w_fe)
    p.stiffen("flex", @w_stiff)
    mv = Movement.new("trunk")
    ch = Chunk.new("trunk", ~0.3).pose(p.pose).hold_until(Latch.after(~100000.0))
    ch.correct(->(f, c) trunk_correction(f), @spring)
    mv.add(ch)
    ctl.add_track(Track.new("trunk", mv, @trunk))
    @tone = @w_tone0
    @tpitch = ~0.0
    @troll = ~0.0
    nth = 0
    @thip.each ->(row) nth = nth + row[2].size
    ctl.emit("dbg:walk:legs:" + (@nm - @trunk.size).to_s + ":trunk:" + @trunk.size.to_s + ":ext:" + @extensors.size.to_s + ":thip:" + nth.to_s)
    self

  # ---- sensing ----------------------------------------------------------------

  # The walker's heading frame and trunk angles, with the rates taken from the
  # pelvis (the walker's torso is the pelvis); the thorax's pitch and roll in
  # the same frame for the trunk track.
  -> sense(f)
    super(f)
    # the way in (see read_params)
    t = f.t
    u0 = clamp((t - @fe_t0) / @w_t0, ~0.0, ~1.0)
    @fe_tgt = @fe0 + (@w_fe - @fe0) * Easing.apply(:min_jerk, u0) if @fe0 != nil
    # the pelvis comes forward only as far as the lumbar has extended (at
    # most at the rate 1 / w_t1)
    if @fe0 != nil
      prog = clamp((f.q(body, "flex_extension") - @fe0) / (@w_fe - @fe0 + ~0.001), ~0.0, ~1.0)
      prog = ~0.0 if t < @w_t0 * ~0.5
      @w_prog = clamp(prog, @w_prog - ~0.01 / @w_t1, @w_prog + ~0.01 / @w_t1)
      @pitch_des = @pitch_walk + @w_pd0 * (~1.0 - @w_prog)
    wx = f.at("pelvis_angvel", 0)
    wy = f.at("pelvis_angvel", 1)
    @pitch_rate = wx * @lx + wy * @ly
    @roll_rate = ~0.0 - (wx * @fx + wy * @fy)
    @yaw_rate = f.at("pelvis_angvel", 2)
    ux = f.at("thorax_up", 0)
    uy = f.at("thorax_up", 1)
    uz = f.at("thorax_up", 2)
    @tpitch = Math.atan2(ux * @fx + uy * @fy, uz)
    @troll = Math.atan2(ux * @lx + uy * @ly, uz)
    # w_thor 1: the walker balances the thorax (less w_poff) instead of the
    # pelvis
    if @w_thor > ~0.5
      tx = f.at("torso_angvel", 0)
      ty = f.at("torso_angvel", 1)
      @pitch = @tpitch - @w_poff
      @pitch_rate = tx * @lx + ty * @ly
      @roll = @troll
      @roll_rate = ~0.0 - (tx * @fx + ty * @fy)
    self

  # The walking heading: at the approach spot (ap_dx, ap_dy from the ball)
  # while approach_on, the speed tapering within ap_slow of it.
  -> goal(f)
    return self if !@approach_on
    tx = f.at("env_ball_pos", 0) + @ap_dx
    ty = f.at("env_ball_pos", 1) + @ap_dy
    dx = tx - f.at("pelvis_pos", 0)
    dy = ty - f.at("pelvis_pos", 1)
    d = Math.sqrt(dx * dx + dy * dy)
    @psi_des = Math.atan2(dy, dx) if d > ~0.05
    @psi_goal = @psi_des
    @v_des = @v_walk * clamp(d / @ap_slow, @ap_vmin, ~1.0)
    self

  # ---- the gait's start, after the trunk's way in ------------------------------

  # Each leg first holds the soccer stance's leg posture (hip w_shp, knee
  # w_skn, ankle w_sank: the pelvis tips back on the reflexes, as the soccer
  # set does, fast enough for the thorax to come along) for w_tset, with no
  # walker correction; then the walker's loop.
  -> leg_movement(s, up)
    mv = super(s, up)
    return mv if @w_tset <= ~0.0
    out = Movement.new("walk_" + s)
    g = leg_goals(s, @w_shp, ~0.0, ~0.0, @w_skn, @w_sank)
    ch = leg_chunk(s, "wset", ~0.3, g, @stiff_st, :wset, :min_jerk)
    ch.hold_until(Latch.after(@w_tset))
    out.add(ch)
    i = 0
    while i < mv.size
      out.add(mv[i])
      i += 1
    out.loop_from(1)
    out

  -> leg_correction(f, ctl, s)
    return set_correction(f) if @phase[s] == :wset
    super(f, ctl, s)

  # The set's balance (both legs; each leg track keeps its own side): the
  # ankle strategy on the COM's fore-aft offset from the feet (w_scom ahead),
  # the hips shifting the pelvis over the feet laterally, and a hip strategy
  # on the thorax's pitch.
  -> set_correction(f)
    off = zeros
    cx = (foot_x(f, "l") + foot_x(f, "r")) * ~0.5
    cy = (foot_y(f, "l") + foot_y(f, "r")) * ~0.5
    fwd = rel_f(f, cx, cy) - @w_scom
    lat = rel_l(f, cx, cy)
    ank = ~0.0 - (@w_sk_ank * fwd + @w_sd_ank * @vf)
    joint_offset(off, "ankle_angle_l", ank)
    joint_offset(off, "ankle_angle_r", ank)
    wx = f.at("torso_angvel", 0)
    wy = f.at("torso_angvel", 1)
    hip = ~0.0 - (@w_sk_hp * (@tpitch - @w_tp) + @w_sd_hp * (wx * @lx + wy * @ly))
    if @w_tset1 > ~0.0 && f.t > @w_tset1
      # (the second part of the set) the hips bring the pelvis to its walking
      # tilt, eased from where it was, while the lumbar extends (see
      # trunk_correction): the thorax ends leaning back over a pelvis the hips
      # can walk under
      @pp_from = @pitch if @pp_from == nil
      u = Easing.apply(:min_jerk, clamp((f.t - @w_tset1) / (@w_tset - @w_tset1), ~0.0, ~1.0))
      tgt = @pp_from + (@pitch_walk - @pp_from) * u
      hip = hip + @w_kpp * (tgt - @pitch) - @w_kppd * @pitch_rate
    joint_offset(off, "hip_flexion_l", hip)
    joint_offset(off, "hip_flexion_r", hip)
    sh = @k_lat * lat + @d_lat * @vl
    joint_offset(off, "hip_adduction_r", sh)
    joint_offset(off, "hip_adduction_l", ~0.0 - sh)
    off

  # Before w_tstart the legs stand (no weight shift, no step): the trunk's
  # way in runs first.
  -> stance_extras(f, off, s, air)
    return super(f, off, s, air) if f.t >= @w_tstart || !@starting
    @starting = false
    super(f, off, s, air)
    @starting = true
    off

  -> unloaded?(s)
    return false if @t_now < @w_tstart
    super(s)

  -> before(frame, ctl)
    @t_now = frame.t
    super(frame, ctl)

  # ---- trunk ------------------------------------------------------------------

  # The lumbar on the thorax's pitch (w_lmode 1; w_lmode 2 until the set's
  # second part, then on its own flexion toward w_fe, ramped from there).
  -> thorax_mode?(f)
    return true if @w_lmode > ~0.5 && @w_lmode < ~1.5
    return false if @w_lmode < ~0.5
    if f.t <= @w_tset1
      @fe0 = f.q(body, "flex_extension")
      @fe_t0 = f.t
      return true
    false

  -> lumbar_offset(off, dq)
    lumbar_mode.each ->(pair) joint_offset(off, pair[0], pair[1] * dq)
    off

  -> trunk_correction(f)
    off = zeros
    wx = f.at("torso_angvel", 0)
    wy = f.at("torso_angvel", 1)
    tr = wx * @lx + wy * @ly
    # the lumbar held at its posture (the trunk nearly rigid on the pelvis,
    # as on the chase-tag body): a joint servo on the measured flexion
    q = f.q(body, "flex_extension")
    if thorax_mode?(f)
      # (w_lmode 1, and 2 before w_tset1) the soccer skill's trunk: the lumbar
      # extends on the thorax's pitch error from w_tp and its pitch rate
      lumbar_offset(off, @w_kth * (@tpitch - @w_tp) + @w_kthd * tr)
    else
      lumbar_offset(off, @w_kth * (@fe_tgt - q) - @w_kthd * f.qd(body, "flex_extension"))
    joint_offset(off, "lat_bending", ~0.0 - @w_klb * f.q(body, "lat_bending"))
    g = @g
    @thip.each ->(row)
      dq = f.q(body, row[0]) - g.qref(row[1])
      j = row[1]
      row[2].each ->(m) off[m] = off[m] + g.contraction_slope(m, j) * dq
    off

  -> after(frame, ctl)
    super(frame, ctl)
    err = @fe_tgt - frame.q(body, "flex_extension")
    err = @tpitch - @w_tp if thorax_mode?(frame)
    @tone = clamp(@tone + @w_ktone * err * ctl.dt, ~0.0, ~1.0)
    tone = @tone
    @extensors.each ->(i) ctl.add_drive(i, tone)
    self
