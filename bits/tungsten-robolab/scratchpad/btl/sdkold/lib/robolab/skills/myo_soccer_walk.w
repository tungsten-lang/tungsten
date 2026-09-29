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
#   trunk  a third track on the trunk muscles holding the soccer stance's
#          lumbar flexion (fe; the rectus abdominis is slack there), a joint
#          servo holding the lumbar flexion and side bend there, and the
#          soccer skill's postural tone (a feed-forward drive on the lumbar
#          extensors integrating the lumbar flexion's error), with per-muscle
#          gains proportional to each muscle's length range
#   tilt   the walker's pelvis pitch target tipped back by w_tilt (the
#          soccer stance's reason: an upright pelvis stretches the rectus
#          abdominis, whose passive force folds the trunk forward)
#   trunk  the walker's trunk pitch and roll (and their rates) are the
#          thorax's (less w_poff, its lead over the pelvis in the stance): the
#          heavy upper body is what the stance hips balance
#   goal   the walking heading points at the approach spot (ap_dx, ap_dy from
#          the ball) and the speed tapers near it (see goal)
#
# The walker's hip torque map (MyoWalkHip) needs the muscle_fmax /
# muscle_range blocks, which the soccer task sends with `walk_consts 1`.

+ MyoSoccerWalkSkill < MyoWalkSkill
  -> start(frame, ctl)
    @g = body.geometry
    @nm = body.size
    classify_legs
    super(frame, ctl)
    setup_trunk(frame, ctl)
    self

  -> read_params
    super
    # trunk (the soccer skill's values)
    @w_ktr = param("w_ktr", ~107.7, ~20.0, ~300.0)
    @w_kdr = param("w_kdr", ~0.03, ~0.0, ~0.1)
    @w_fe = param("w_fe", ~-0.365, ~-0.8, ~0.0)
    @w_poff = param("w_poff", ~0.4, ~0.0, ~0.8)
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
    @w_tilt = param("w_tilt", ~-0.35, ~-0.6, ~0.1)
    @pitch_des = @pitch_des + @w_tilt
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
    # the walker balances the upper body, not the light pelvis: its trunk
    # pitch is the thorax's less w_poff (the thorax's lead over the pelvis in
    # the stance), its rates the thorax's
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

  # ---- trunk ------------------------------------------------------------------

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
    lumbar_offset(off, @w_kth * (@w_fe - q) - @w_kthd * f.qd(body, "flex_extension"))
    joint_offset(off, "lat_bending", ~0.0 - @w_klb * f.q(body, "lat_bending"))
    g = @g
    @thip.each ->(row)
      dq = f.q(body, row[0]) - g.qref(row[1])
      j = row[1]
      row[2].each ->(m) off[m] = off[m] + g.contraction_slope(m, j) * dq
    off

  -> after(frame, ctl)
    super(frame, ctl)
    @tone = clamp(@tone + @w_ktone * (@w_fe - frame.q(body, "flex_extension")) * ctl.dt, ~0.0, ~1.0)
    tone = @tone
    @extensors.each ->(i) ctl.add_drive(i, tone)
    self
