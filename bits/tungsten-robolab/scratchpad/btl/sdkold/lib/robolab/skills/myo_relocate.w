# MyoRelocate: MyoChallenge 2023 Relocate (phase 2) on the myoArm, 63
# muscles. Pick the object off the table and put it in the receptacle, all
# inside the 1.5 s episode.
#
# One track drives every muscle (the extrinsic finger muscles cross the
# wrist, so arm and hand postures are authored together). The chunks:
#
#   reach    the hand opens into a wide pinch and the palm eases to a point
#            above the object; LATCHED on the palm arriving (or a timeout)
#   descend  the palm eases down until the pinch straddles the object;
#            LATCHED on touch or on arriving
#   close    thumb and fingers close the pinch with a feed-forward squeeze;
#            LATCHED on a grip (thumb and a finger both pressing)
#   lift     the palm rises straight up; LATCHED on the object clearing the
#            receptacle's wall
#   carry    the palm eases over the receptacle; LATCHED on the object being
#            over the opening
#   lower    the palm eases down into the receptacle (the object counts as
#            placed once it is within 10 cm of the receptacle's centre, so a
#            held object below the rim already scores); LATCHED on time
#   release  the pinch opens and the object drops the rest of the way (or,
#            with `toss_x`, as soon as the lifted object has crossed that x:
#            a toss into the receptacle)
#
# The hand postures were designed offline by forward kinematics on the
# model (a pinch whose thumb and index/middle tips close 4 cm below the palm
# site; open 10 cm apart, closed 1.3 cm apart so contact squeezes) and are
# tunables, as are every palm goal, duration, gain and threshold.
#
# Arm movement is a spring-eased correction on every chunk, in hand space.
# Each chunk names a palm goal (relative to the object or to the receptacle,
# from the env_obj_pos / env_goal_pos sensors); the servo target eases from
# the previous chunk's target to that goal along the min-jerk profile over the
# chunk's duration. A table of midpoint postures (MyoRelocatePostures, solved
# offline by inverse kinematics on the model, hand held in the pinch
# orientation) turns the commanded palm position into the seven arm and wrist
# angles, and the body's muscle geometry turns those into one contraction per
# muscle. The commanded palm position is the target plus an integral of the
# measured palm error (clamped, so it cannot wind up), which carries the palm
# the rest of the way against gravity sag and the reflexes' compliance.

+ MyoRelocateSkill < Skill
  -> start(frame, ctl)
    @g = body.geometry
    @dt = ctl.dt
    @arm = postures_joints
    @tab = postures_table
    @ctab = postures_contractions
    @arm_j = @arm.map ->(n) @g.joint(n)
    # arm muscles: true contractions from the table; their reference values
    # (the chunk poses hold the arm at the reference, where the body's
    # additive length model is exact)
    @am = postures_muscles.map ->(n) body.index(n)
    q_ref = @g.reference_posture
    @cref = @am.map ->(m) @g.contraction(m, q_ref)
    is_arm = {}
    @am.each ->(m) is_arm[m] = true
    # finger muscles that also cross the wrist: the additive model
    crossing = {}
    @arm_j.each ->(j) @g.crossing(j).each ->(m) crossing[m] = true if !is_arm.key?(m)
    @fm = crossing.keys
    @integ = [~0.0, ~0.0, ~0.0]
    @qcmd = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    @ps_cmd = ~0.0
    @kp_s = param("servo_p", ~0.3, ~0.0, ~1.5)
    @ki_s = param("servo_i", ~6.0, ~0.0, ~30.0)
    @ilim = param("servo_lim", ~0.08, ~0.0, ~0.2)
    @leak = param("servo_leak", ~0.5, ~0.0, ~5.0)
    @spring = param("spring", ~0.04, ~0.01, ~0.2)
    # pronator tone: the biceps (a strong supinator) turns the palm up as it
    # works, so an integral on the pronation error raises the pronators'
    # (PT, PQ) commanded contraction
    @pron = body.mask(["PT", "PQ"])
    @ps_j = @g.joint("pro_sup")
    @ps_int = ~0.0
    @ki_ps = param("pron_i", ~3.0, ~0.0, ~20.0)
    @ps_lim = param("pron_lim", ~0.15, ~0.0, ~0.4)
    @debug = params.key?("debug")
    # velocity feed-forward: the reflex damps every motion (-kd * cdot), the
    # commanded ones too; a drive of kv times the commanded contraction rate
    # (from the target history) makes it track the plan instead
    @kv = param("kv", ~0.0, ~0.0, ~2.0)
    # shoulder stiffness without the biceps: co-contraction added to the
    # shoulder-only muscles (uniform co-contraction recruits the biceps,
    # which supinates the forearm); the plane of elevation is otherwise
    # barely constrained while the upper arm hangs
    @sh_m = body.mask(["DELT", "SUPSP", "INFSP", "SUBSC", "TMIN", "TMAJ", "PECM", "LAT", "CORB"])
    @st_sh = param("stiff_sh", ~0.0, ~0.0, ~0.3)
    @tprev = nil
    @tprev2 = nil
    @phase = ""
    @x0 = [~0.0, ~0.0, ~0.0]
    @xs = [~0.0, ~0.0, ~0.0]
    @hold = [~0.0, ~0.0, ~0.0]
    @started = false
    @t0 = ~0.0
    @tp = ~0.3
    # palm goals (m): offsets from the object (the grasp point sits about
    # (0.02, -0.01, -0.042) from the palm site), then absolute heights
    @ox = param("ox", ~0.0, ~-0.05, ~0.05)
    @oy = param("oy", ~0.0, ~-0.05, ~0.05)
    @z_above = param("z_above", ~1.0, ~0.94, ~1.12)
    @z_grasp = param("z_grasp", ~0.925, ~0.9, ~0.98)
    # touch re-aims the pinch: object estimate = site + k_touch * (felt - site)
    @k_touch = param("k_touch", ~0.7, ~0.0, ~1.0)
    @felt = [~0.0, ~0.0]
    @felt_n = 0
    @z_lift = param("z_lift", ~1.22, ~1.1, ~1.35)
    @z_clear = param("z_clear", ~1.15, ~1.08, ~1.25)
    @cx = param("cx", ~-0.02, ~-0.08, ~0.08)
    @cy = param("cy", ~0.01, ~-0.08, ~0.08)
    @z_carry = param("z_carry", ~1.22, ~1.1, ~1.35)
    @z_low = param("z_low", ~1.04, ~0.95, ~1.25)
    @r_reach = param("r_reach", ~0.025, ~0.005, ~0.08)
    @r_xy = param("r_xy", ~0.015, ~0.003, ~0.05)
    @r_drop = param("r_drop", ~0.04, ~0.005, ~0.12)
    @touch_th = param("touch_th", ~0.5, ~0.05, ~5.0)
    @t_retry = param("t_retry", ~0.8, ~0.0, ~1.2)
    # toss: open the hand once the lifted object has crossed toss_x on its
    # way to the receptacle (0.5 = never; the carry then goes all the way)
    @toss_x = param("toss_x", ~0.5, ~-0.25, ~0.5)
    @d_lost = param("d_lost", ~0.1, ~0.05, ~0.25)
    @grip_th = param("grip_th", ~1.0, ~0.1, ~10.0)
    # chunk durations and timeouts (s)
    @t_reach = param("t_reach", ~0.25, ~0.08, ~0.6)
    @t_desc = param("t_desc", ~0.12, ~0.04, ~0.4)
    @t_close = param("t_close", ~0.1, ~0.03, ~0.3)
    @t_lift = param("t_lift", ~0.25, ~0.15, ~0.5)
    @t_carry = param("t_carry", ~0.3, ~0.15, ~0.5)
    @t_low = param("t_low", ~0.12, ~0.03, ~0.4)
    @to_reach = param("to_reach", ~0.5, ~0.1, ~0.8)
    @to_desc = param("to_desc", ~0.35, ~0.05, ~0.6)
    @to_close = param("to_close", ~0.15, ~0.04, ~0.5)
    @to_lift = param("to_lift", ~0.3, ~0.08, ~0.6)
    @to_carry = param("to_carry", ~0.35, ~0.08, ~0.7)
    @t_hold = param("t_hold", ~0.1, ~0.0, ~0.5)
    # reflexes: arm and hand
    hand = body.mask(["FDS", "FDP", "EDC", "EDM", "EIP", "EPL", "EPB", "FPL", "APL", "OP", "RI", "LU_", "UI_"])
    arm = body.all.select ->(i) !hand.include?(i)
    ctl.reflex.set_gains(arm, param("kp_arm", ~10.0, ~1.0, ~40.0), param("kd_arm", ~0.3, ~0.0, ~2.0))
    ctl.reflex.set_gains(hand, param("kp_hand", ~8.0, ~1.0, ~40.0), param("kd_hand", ~0.2, ~0.0, ~2.0))
    # the pronators hold the palm down against the biceps' supination
    ctl.reflex.set_gains(body.mask(["PT", "PQ"]), param("kp_pron", ~15.0, ~1.0, ~40.0), param("kd_pron", ~0.3, ~0.0, ~2.0))
    # postural tone: a clamped integral of each muscle's length error, so a
    # held posture loses its gravity sag (arm) and a closed grip keeps
    # squeezing harder while the fingers are held open by the object (hand).
    # Off (0) by default.
    ki_arm = param("ki_arm", ~0.0, ~0.0, ~60.0)
    ki_hand = param("ki_hand", ~0.0, ~0.0, ~60.0)
    ctl.reflex.set_integral(arm, ki_arm, param("ilim_arm", ~0.02, ~0.001, ~0.1)) if ki_arm > ~0.0
    ctl.reflex.set_integral(hand, ki_hand, param("ilim_hand", ~0.02, ~0.001, ~0.1)) if ki_hand > ~0.0
    # internal-model feed-forward: the arm's gravity + Coriolis torque as
    # drive on the arm muscles, so the reflexes correct only the residual
    ff = param("ff_gain", ~0.0, ~0.0, ~1.5)
    ctl.enable_feedforward(arm, ff) if ff > ~0.0
    st_arm = param("stiff_arm", ~0.04, ~0.0, ~0.3)
    st_open = param("stiff_open", ~0.02, ~0.0, ~0.3)
    st_grip = param("stiff_grip", ~0.1, ~0.0, ~0.4)
    # hand = [mcp flex, pip, dip, mcp abduction, thumb cmc abd, cmc flex, mp, ip] (rad)
    open = open_hand
    shut = shut_hand
    # wrist offsets on the posture table's wrist: [pro_sup, deviation, flexion]
    @wrist = [param("dps", ~0.0, ~-0.6, ~0.6), param("ddev", ~0.0, ~-0.3, ~0.3), param("dflex", ~0.0, ~-0.6, ~0.6)]
    @wrist_c = [param("dps_carry", ~0.0, ~-0.6, ~0.6), param("ddev_carry", ~0.0, ~-0.3, ~0.3), param("dflex_carry", ~0.0, ~-0.6, ~0.6)]
    @open = open
    @shut = shut
    @hand = open
    @wr = @wrist
    p_open = posture(open, st_arm, st_open)
    p_grip = posture(shut, st_arm, st_grip)
    p_drop = posture(open, st_arm, st_open)
    squeeze = zeros
    level = param("squeeze", ~0.15, ~0.0, ~0.6)
    body.mask(["FDS", "FDP", "FPL", "OP"]).each ->(i) squeeze[i] = level
    # internal model and joint-space loop (opt-in; see servo_step / servo_offsets)
    @ff_id = param("ff_id", ~0.0, ~0.0, ~1.5)
    @ff_m = ff_muscle_names.map ->(n) body.index(n)
    @cmd_p = nil
    @jpd_names = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup"]
    @jpd_kq = [param("kq_elv", ~0.0, ~0.0, ~3.0), param("kq_sh", ~0.0, ~0.0, ~3.0), param("kq_rot", ~0.0, ~0.0, ~3.0), param("kq_elb", ~0.0, ~0.0, ~3.0), param("kq_ps", ~0.0, ~0.0, ~3.0)]
    @jpd_kd = [param("kqd_elv", ~0.0, ~0.0, ~0.6), param("kqd_sh", ~0.0, ~0.0, ~0.6), param("kqd_rot", ~0.0, ~0.0, ~0.6), param("kqd_elb", ~0.0, ~0.0, ~0.6), param("kqd_ps", ~0.0, ~0.0, ~0.6)]
    @jpd_lim = param("jpd_lim", ~0.5, ~0.05, ~1.5)
    @jpd_on = false
    k = 0
    while k < 5
      @jpd_on = true if @jpd_kq[k] > ~0.0 || @jpd_kd[k] > ~0.0
      k += 1
    # resolved-rate correction through the palm Jacobian (opt-in, rr_kp / rr_ki)
    @rr_kp = param("rr_kp", ~0.0, ~0.0, ~20.0)
    @rr_ki = param("rr_ki", ~0.0, ~0.0, ~60.0)
    @rr_lim = param("rr_lim", ~0.3, ~0.02, ~1.0)
    @rr_lam = param("rr_lam", ~0.002, ~0.0001, ~0.05)
    @rr_int = [~0.0, ~0.0, ~0.0]
    servo = ->(f, c) servo_step(f, c)
    if params.key?("bench")
      ctl.add_track(Track.new("arm", bench_movement(p_open, servo), body.all))
      return nil
    ctl.add_track(Track.new("arm", movement(p_open, p_grip, p_drop, squeeze, servo), body.all))

  # The relocate chunks (see the header); subclasses build their own.
  -> movement(p_open, p_grip, p_drop, squeeze, servo)
    arrived = Latch.test("arrived", ->(f, e, c) palm_error(f) < @r_reach)
    touched = Latch.test("touched", ->(f, e, c) touch_total(f) > @touch_th)
    gripped = Latch.test("gripped", ->(f, e, c) gripped?(f))
    cleared = Latch.test("cleared", ->(f, e, c) f.at("env_obj_pos", 2) > @z_clear)
    over = Latch.test("over", ->(f, e, c) over_box?(f))
    mv = Movement.new("relocate")
    mv.add(Chunk.new("reach", @t_reach).pose(p_open).hold_until(arrived.after_min(@t_reach * ~0.7), @to_reach).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "reach", @t_reach)))
    ready = Latch.test("ready", ->(f, e, c) pinch_ready?(f))
    mv.add(Chunk.new("descend", @t_desc).pose(p_open).hold_until(Latch.any([touched, ready.after_min(@t_desc)]), @to_desc).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "descend", @t_desc)))
    mv.add(Chunk.new("close", @t_close).pose(p_grip).drive(squeeze).hold_until(gripped.after_min(@t_close * ~0.5), @to_close).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "close", @t_close)))
    mv.add(Chunk.new("lift", @t_lift).pose(p_grip).drive(squeeze).hold_until(cleared, @to_lift).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "lift", @t_lift)))
    mv.add(Chunk.new("carry", @t_carry).pose(p_grip).drive(squeeze).hold_until(over.after_min(@t_carry * ~0.5), @to_carry).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "carry", @t_carry)))
    mv.add(Chunk.new("lower", @t_low).pose(p_grip).drive(squeeze).hold_until(Latch.after(@t_low + @t_hold)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "lower", @t_low)))
    mv.add(Chunk.new("release", ~0.1).pose(p_drop).hold_until(Latch.after(~100.0)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "release", ~0.1)))
    mv

  # Where the hand feels the object, as an offset from the object's site
  # (latched from the first touches of the grasp and kept while the object
  # is lost again; the site moves with the object, the offset rides along).
  -> before(f, ctl)
    return nil if @phase != "descend" && @phase != "close"
    return nil if touch_total(f) < @touch_th
    k = 0
    while k < 2
      off = f.at("touch_pos", k) - f.at("env_obj_pos", k)
      @felt[k] = @felt[k] + (off - @felt[k]) / (@felt_n + 1)
      k += 1
    @felt_n = @felt_n + 1 if @felt_n < 20
    nil

  # Drive = kv x the commanded contraction rate, from the last two ticks'
  # targets (one tick late), on every muscle.
  -> feed_forward(ctl)
    tg = ctl.target
    if @tprev != nil
      n = tg.size
      inv = @kv / @dt
      i = 0
      while i < n
        ctl.add_drive(i, (@tprev[i] - @tprev2[i]) * inv) if @tprev2 != nil
        i += 1
    @tprev2 = @tprev
    @tprev = tg.map ->(x) x
    nil

  # Toss point: the held object is above the rim and past toss_x.
  -> tossed?(f)
    f.at("env_obj_pos", 0) > @toss_x && f.at("env_obj_pos", 2) > @z_clear

  # Regrasp: the object is still on the table while the palm has risen
  # well above it (the grip slipped), and there is time for another try.
  -> lost?(f)
    return false if f.t > @t_retry
    f.at("env_obj_pos", 2) < z_floor && f.at("env_palm_pos", 2) - f.at("env_obj_pos", 2) > @d_lost

  -> after(f, ctl)
    feed_forward(ctl) if @kv > ~0.0
    if (@phase == "lift" || @phase == "carry") && tossed?(f)
      ctl.track("arm").jump(ctl, f, "release")
      return nil
    if (@phase == "lift" || @phase == "carry") && lost?(f)
      @felt_n = 0
      @felt = [~0.0, ~0.0]
      ctl.track("arm").jump(ctl, f, "reach")
    if @phase.starts_with?("benchb")
      ctl.emit("tgt:" + @xs.map(->(x) (x * ~10000.0).round.to_s).join(",") + "," + (@ps_cmd * ~10000.0).round.to_s)
    return nil if !@debug
    e = @xs.map ->(x) x
    k = 0
    while k < 3
      e[k] = @xs[k] - f.at("env_palm_pos", k)
      k += 1
    qa = @arm_j.map ->(j) (f.at("q", j) * ~100.0).round.to_s
    qc = @qcmd.map ->(x) (x * ~100.0).round.to_s
    ctl.emit("dbg:" + @integ.map(->(x) (x * ~1000.0).round.to_s).join(",") + "/" + e.map(->(x) (x * ~1000.0).round.to_s).join(",") + "/q:" + qa.join(",") + "/cmd:" + qc.join(","))
    nil

  # Reaching benchmark (param `bench`): the palm tours fixed targets over the
  # workspace (above the objects, down to grasp height, up over the rim, over
  # the receptacle and into it), no object handling; the skill emits its
  # target (`tgt:x,y,z`) so the task can score the palm's tracking.
  -> bench_movement(pose, servo)
    @bench = [[~-0.2, ~-0.25, ~1.0], [~-0.2, ~-0.25, ~0.96], [~-0.2, ~-0.25, ~1.2], [~0.0, ~-0.25, ~1.2], [~0.0, ~-0.25, ~1.03], [~-0.3, ~-0.2, ~1.0], [~-0.3, ~-0.2, ~0.96], [~-0.12, ~-0.33, ~0.97]]
    dur = param("t_bench", ~0.3, ~0.1, ~0.6)
    mv = Movement.new("bench")
    i = 0
    while i < @bench.size
      name = "b" + i.to_s
      mv.add(Chunk.new(name, dur).pose(pose).hold_until(Latch.after(dur)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "bench" + c.track("arm").chunk_name, dur)))
      i += 1
    mv

  # Full posture: arm and wrist at the reference (the correction moves them),
  # then the hand: [mcp flex, pip, dip, mcp abduction, thumb cmc abd, cmc
  # flex, mp, ip].
  -> posture(hand, st_arm, st_hand)
    g = @g
    p = Pose.new
    @arm.each ->(name) p.set(name, g.qref(g.joint(name)), st_arm)
    hand_joints(hand).each ->(pair) p.set(pair[0], pair[1], st_hand)
    p

  -> hand_joints(hand)
    out = []
    ["2", "3", "4", "5"].each ->(k)
      out.push(["mcp" + k + "_flexion", hand[0]])
      out.push(["pm" + k + "_flexion", hand[1]])
      out.push(["md" + k + "_flexion", hand[2]])
    out.push(["mcp2_abduction", hand[3]])
    out.push(["mcp4_abduction", ~0.0 - hand[3]])
    out.push(["mcp5_abduction", ~0.0 - hand[3]])
    out.push(["cmc_abduction", hand[4]])
    out.push(["cmc_flexion", hand[5]])
    out.push(["mp_flexion", hand[6]])
    out.push(["ip_flexion", hand[7]])
    out

  # ---- latches ---------------------------------------------------------------

  # Distance from the servo's control point (pinch or palm) to the goal.
  -> palm_error(f)
    goal = phase_goal(f)
    dx = goal[0] - control_point(f, 0)
    dy = goal[1] - control_point(f, 1)
    dz = goal[2] - control_point(f, 2)
    Math.sqrt(dx * dx + dy * dy + dz * dz)

  # The pinch has come down around the object: centred within r_xy and
  # within 1 cm of the grasp height.
  -> pinch_ready?(f)
    goal = phase_goal(f)
    dx = goal[0] - control_point(f, 0)
    dy = goal[1] - control_point(f, 1)
    dz = goal[2] - control_point(f, 2)
    Math.sqrt(dx * dx + dy * dy) < @r_xy && dz > ~-0.01 && dz < ~0.01

  -> touch_total(f)
    s = ~0.0
    k = 0
    while k < 6
      s += f.at("touch", k)
      k += 1
    s

  -> gripped?(f)
    fingers = f.at("touch", 1) + f.at("touch", 2) + f.at("touch", 3) + f.at("touch", 4)
    f.at("touch", 0) > @grip_th && fingers > @grip_th

  -> over_box?(f)
    dx = f.at("env_obj_pos", 0) - f.at("env_goal_pos", 0)
    dy = f.at("env_obj_pos", 1) - f.at("env_goal_pos", 1)
    Math.sqrt(dx * dx + dy * dy) < @r_drop

  # ---- hand-space servo ------------------------------------------------------

  -> enter_phase(f, name, duration)
    @phase = name
    @t0 = f.t
    @tp = duration
    switch = !@started || name == "lift" || name == "reach"
    k = 0
    while k < 3
      @xs[k] = control_point(f, k) if switch
      @x0[k] = @xs[k]
      k += 1
    @started = true
    # close holds the pinch where it was aimed; lift starts from the palm
    if name == "close" || name == "lift"
      k = 0
      while k < 3
        @hold[k] = @xs[k]
        k += 1
    @hand = @open
    @hand = @shut if gripping_phase?(name)
    @wr = @wrist
    @wr = @wrist_c if name == "carry" || name == "lower" || name == "release"
    nil

  # The chunk's palm goal.
  -> phase_goal(f)
    ph = @phase
    ox = f.at("env_obj_pos", 0) + @ox
    oy = f.at("env_obj_pos", 1) + @oy
    oz = f.at("env_obj_pos", 2)
    gx = f.at("env_goal_pos", 0) + @cx
    gy = f.at("env_goal_pos", 1) + @cy
    if ph.starts_with?("benchb")
      b = @bench[ph.slice(6, ph.size - 6).to_i]
      return [b[0], b[1], b[2]]
    return [ox, oy, @z_above] if ph == "reach"
    return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], @z_grasp] if ph == "descend"
    return [@hold[0], @hold[1], @hold[2]] if ph == "close"
    return [@hold[0], @hold[1], @z_lift] if ph == "lift"
    return [gx, gy, @z_carry] if ph == "carry"
    [gx, gy, @z_low]

  # The point the servo steers: the pinch (thumb tip halfway to the index
  # and middle tips) while reaching for the object, the palm once it holds it.
  -> control_point(f, k)
    ph = @phase
    if ph == "reach" || ph == "descend" || ph == "close"
      fingers = (f.at("tips", 3 + k) + f.at("tips", 6 + k)) * ~0.5
      return (f.at("tips", k) + fingers) * ~0.5
    f.at("env_palm_pos", k)

  # Arm offsets for the palm command: the posture table's arm and wrist
  # angles (plus the chunk's wrist offsets) against the reference, through the
  # muscle geometry at the chunk's finger posture.
  -> servo_offsets(f)
    off = zeros
    return off if @phase == ""
    goal = phase_goal(f)
    s = Easing.min_jerk(clamp((f.t - @t0) / @tp, ~0.0, ~1.0))
    cmd = [~0.0, ~0.0, ~0.0]
    k = 0
    while k < 3
      x = @x0[k] + (goal[k] - @x0[k]) * s
      @xs[k] = x
      cp = control_point(f, k)
      e = x - cp
      @integ[k] = clamp(@integ[k] + (@ki_s * e - @leak * @integ[k]) * @dt, ~0.0 - @ilim, @ilim)
      # palm command = the target carried over by the palm's offset from the
      # control point, plus the integral and a proportional push
      cmd[k] = x + (f.at("env_palm_pos", k) - cp) + @integ[k] + @kp_s * e
      k += 1
    @cmd_p = cmd
    arm = postures_at(@tab, 7, cmd[0], cmd[1], cmd[2])
    ctab = postures_at(@ctab, @am.size, cmd[0], cmd[1], cmd[2])
    q = @g.reference_posture
    hand_joints(@hand).each ->(pair) q[@g.joint(pair[0])] = pair[1]
    base = @fm.map ->(m) @g.contraction(m, q)
    k = 0
    while k < 7
      j = @arm_j[k]
      q[j] = clamp(arm[k], @g.qmin(j), @g.qmax(j))
      @qcmd[k] = q[j]
      k += 1
    qo = q.map ->(v) v
    turned = false
    k = 0
    while k < 3
      if @wr[k] != ~0.0
        j = @arm_j[4 + k]
        qo[j] = clamp(q[j] + @wr[k], @g.qmin(j), @g.qmax(j))
        turned = true
      k += 1
    i = 0
    while i < @am.size
      m = @am[i]
      v = ctab[i] - @cref[i]
      v = v + @g.contraction(m, qo) - @g.contraction(m, q) if turned
      off[m] = v
      i += 1
    i = 0
    while i < @fm.size
      m = @fm[i]
      off[m] = @g.contraction(m, qo) - base[i]
      i += 1
    # pronation the table asks for (the wrist offsets are commands, not goals)
    @ps_cmd = q[@ps_j]
    @ps_int = clamp(@ps_int + @ki_ps * @dt * (@ps_cmd - f.at("q", @ps_j)), ~0.0, @ps_lim)
    @pron.each ->(m) off[m] = off[m] + @ps_int
    if @st_sh > ~0.0
      half = @st_sh * ~0.5
      @sh_m.each ->(m) off[m] = off[m] + half
    add_joint_pd(f, off) if @jpd_on
    add_resolved_rate(f, off) if (@rr_kp > ~0.0 || @rr_ki > ~0.0) && f.has?("palm_jac")
    off

  # Resolved-rate correction (opt-in; rr_kp, rr_ki default 0). The posture
  # table is an open-loop map from palm target to posture, right only while
  # the arm sits near the table's own postures; when the forearm has rolled
  # or the shoulder swung, its offsets point the wrong way. This term steers
  # the control point from the arm's *measured* configuration instead: the
  # palm Jacobian (the `palm_jac` sensor, 3 x 7 over the arm joints) turns
  # the servo error e = x_target - x into joint offsets by damped least
  # squares, dq = J^T (J J^T + lam I)^-1 (rr_kp e + rr_ki int e), clamped to
  # +-rr_lim per joint, and the muscle geometry turns those into contraction
  # offsets.
  -> add_resolved_rate(f, off)
    e = [~0.0, ~0.0, ~0.0]
    k = 0
    while k < 3
      e[k] = @xs[k] - control_point(f, k)
      @rr_int[k] = clamp(@rr_int[k] + e[k] * @dt, ~-0.05, ~0.05)
      e[k] = @rr_kp * e[k] + @rr_ki * @rr_int[k]
      k += 1
    # A = J J^T + lam I (3 x 3, symmetric)
    a = [@rr_lam, ~0.0, ~0.0, ~0.0, @rr_lam, ~0.0, ~0.0, ~0.0, @rr_lam]
    j = 0
    while j < 7
      x = f.at("palm_jac", 3 * j)
      y = f.at("palm_jac", 3 * j + 1)
      z = f.at("palm_jac", 3 * j + 2)
      a[0] += x * x
      a[1] += x * y
      a[2] += x * z
      a[4] += y * y
      a[5] += y * z
      a[8] += z * z
      j += 1
    a[3] = a[1]
    a[6] = a[2]
    a[7] = a[5]
    # y = A^-1 e by Cramer's rule
    det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
    return off if det < ~0.0000000001 && det > ~-0.0000000001
    i00 = (a[4] * a[8] - a[5] * a[7]) / det
    i01 = (a[2] * a[7] - a[1] * a[8]) / det
    i02 = (a[1] * a[5] - a[2] * a[4]) / det
    i11 = (a[0] * a[8] - a[2] * a[6]) / det
    i12 = (a[2] * a[3] - a[0] * a[5]) / det
    i22 = (a[0] * a[4] - a[1] * a[3]) / det
    y0 = i00 * e[0] + i01 * e[1] + i02 * e[2]
    y1 = i01 * e[0] + i11 * e[1] + i12 * e[2]
    y2 = i02 * e[0] + i12 * e[1] + i22 * e[2]
    j = 0
    while j < 7
      dq = f.at("palm_jac", 3 * j) * y0 + f.at("palm_jac", 3 * j + 1) * y1 + f.at("palm_jac", 3 * j + 2) * y2
      joint_offset(off, @arm[j], clamp(dq, ~0.0 - @rr_lim, @rr_lim))
      j += 1
    off

  # Joint-space outer loop (opt-in; gains default 0). The lambda servo's
  # stiffness about a joint scales with the squared moment arms of the
  # muscles crossing it; about the plane of elevation and the humeral
  # rotation they are short while the upper arm hangs, and on the reaching
  # benchmark elv_angle swings +-0.7 rad about its command with a ~1.2 s
  # period. For the proximal joints the offsets get
  #   dq_j = kq_j (q_cmd_j - q_j) - kqd_j qd_j   (clamped to +-jpd_lim)
  # (q_cmd: the posture just looked up; q, qd: the joint sensors) through
  # the muscle geometry.
  -> add_joint_pd(f, off)
    k = 0
    while k < 5
      j = @arm_j[k]
      dq = @jpd_kq[k] * (@qcmd[k] - f.at("q", j)) - @jpd_kd[k] * f.at("qd", j)
      joint_offset(off, @jpd_names[k], clamp(dq, ~0.0 - @jpd_lim, @jpd_lim))
      k += 1
    off

  # The chunks' correction: the servo's offsets, plus (opt-in, `ff_id`) the
  # internal model's static drive at the palm command: the arm-muscle
  # activations that hold the commanded posture still against gravity and
  # passive muscle forces (ff_table, see playground/tasks/myo_relocate_ff.py),
  # so the reflexes need no standing error to carry the arm.
  -> servo_step(f, ctl)
    off = servo_offsets(f)
    add_static_drive(ctl) if @ff_id > ~0.0 && @cmd_p != nil && @ff_m.size > 0
    off

  -> add_static_drive(ctl)
    p = @cmd_p
    acts = postures_at(ff_table, @ff_m.size, p[0], p[1], p[2])
    i = 0
    while i < @ff_m.size
      ctl.add_drive(@ff_m[i], @ff_id * acts[i])
      i += 1
    nil

  # ---- hooks for skills built on this one --------------------------------

  # Static feed-forward table (activations per posture-table node) and its
  # muscles; none by default (skills with a table override both).
  -> ff_muscle_names
    []

  -> ff_table
    []

  # The hand's open and closed postures: [mcp flex, pip, dip, mcp abduction,
  # thumb cmc abd, cmc flex, mp, ip] (rad); the pinch by default.
  -> open_hand
    [param("f_open", ~0.8, ~0.0, ~1.4), param("pip_open", ~0.09, ~0.0, ~1.0), param("dip_open", ~0.0, ~0.0, ~1.0), param("abd_open", ~0.0, ~-0.26, ~0.26), param("thabd_open", ~-0.5, ~-0.5, ~0.78), param("thflex_open", ~0.7, ~-0.78, ~0.7), param("thmp_open", ~0.59, ~-0.78, ~0.7), param("thip_open", ~0.02, ~-1.3, ~0.43)]

  -> shut_hand
    [param("f_close", ~1.31, ~0.5, ~1.57), param("pip_close", ~0.07, ~0.0, ~1.57), param("dip_close", ~0.19, ~0.0, ~1.57), param("abd_close", ~0.0, ~-0.26, ~0.26), param("thabd_close", ~-0.32, ~-0.5, ~0.78), param("thflex_close", ~0.35, ~-0.78, ~0.7), param("thmp_close", ~0.0, ~-0.78, ~0.7), param("thip_close", ~0.02, ~-1.3, ~0.43)]

  -> postures_joints
    MyoRelocatePostures.joints

  -> postures_muscles
    MyoRelocatePostures.muscles

  -> postures_table
    MyoRelocatePostures.table

  -> postures_contractions
    MyoRelocatePostures.contractions

  -> postures_at(tab, width, x, y, z)
    MyoRelocatePostures.at(tab, width, x, y, z)

  # Below this height the object is still on its support (the table).
  -> z_floor
    ~0.95

  # Chunks during which the hand holds the object closed.
  -> gripping_phase?(name)
    name == "close" || name == "lift" || name == "carry" || name == "lower"
