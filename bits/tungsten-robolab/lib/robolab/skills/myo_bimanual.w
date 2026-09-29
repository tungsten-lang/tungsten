# MyoBimanual: MyoChallenge 2024 bimanual handover. The myoArm (63 muscles)
# picks the gelatin box off the start pillar and holds it out; the MPL
# prosthetic arm (17 position servos) takes it and sets it on the goal pillar.
#
# The myoArm runs the relocate skill's machinery (MyoRelocateSkill: the
# pinch servo on a table of midpoint postures and contraction vectors, touch
# re-aiming, regrasp on a slip), with its own table (MyoBimanualPostures) and
# chunks:
#
#   reach     pinch point above the box
#   descend   pinch around the box, just above the pillar; LATCHED on touch
#   close     pinch closes; LATCHED on a grip
#   lift      the palm rises; LATCHED on the box clearing the pillar
#   carry     the palm eases to the handover point (hx, hy, hz)
#   handover  holds the box there; LATCHED on the prosthesis having held it
#             for `n_pros` frames (the touching_body sensor)
#   release   the hand opens and the palm backs away
#
# The prosthesis is scripted in `after` as a state machine over the same
# sensations, each state easing the MPL palm (min-jerk) to a target through
# its posture table (MyoBimanualProsthesis) plus searchable joint offsets:
#
#   wait      holds its start pose until the myoArm lifts the box
#   approach  palm above the box's free end, hand open
#   grip      palm down onto that end, then the fingers close; stays until
#             the myo hand has let go
#   carry     palm (with the box) above the goal pillar
#   place     lowers until the goal pillar touches the box
#   release   fingers open; then `retreat` lifts the palm away

+ MyoBimanualSkill < MyoRelocateSkill
  -> postures_joints
    MyoBimanualPostures.joints

  -> postures_muscles
    MyoBimanualPostures.muscles

  -> postures_table
    MyoBimanualPostures.table

  -> postures_contractions
    MyoBimanualPostures.contractions

  -> postures_at(tab, width, x, y, z)
    MyoBimanualPostures.at(tab, width, x, y, z)

  -> z_floor
    @bz_floor

  -> gripping_phase?(name)
    name == "close" || name == "lift" || name == "carry" || name == "handover"

  -> movement(p_open, p_grip, p_drop, squeeze, servo)
    # myo side: goals for the box on the pillar and the handover point
    @bz_floor = param("b_floor", ~1.14, ~1.1, ~1.2)
    @bz_above = param("b_above", ~1.2, ~1.13, ~1.3)
    @bz_grasp = param("b_grasp", ~1.105, ~1.09, ~1.15)
    @bz_lift = param("b_lift", ~1.3, ~1.18, ~1.42)
    @bz_clear = param("b_clear", ~1.16, ~1.12, ~1.25)
    @box = [param("b_ox", ~-0.02, ~-0.06, ~0.06), param("b_oy", ~0.0, ~-0.06, ~0.06)]
    @hand_pt = [param("hx", ~-0.12, ~-0.35, ~0.05), param("hy", ~-0.32, ~-0.45, ~-0.15), param("hz", ~1.28, ~1.15, ~1.42)]
    @retreat = [param("rx", ~-0.1, ~-0.25, ~0.05), param("ry", ~0.05, ~-0.1, ~0.15), param("rz", ~0.05, ~-0.05, ~0.15)]
    @n_pros = param("n_pros", ~20.0, ~2.0, ~80.0)
    t_hand = param("t_hand", ~0.5, ~0.2, ~1.2)
    t_rel = param("t_rel", ~0.4, ~0.1, ~1.0)
    @pros_frames = 0
    @myo_free = 0
    mpl_setup
    arrived = Latch.test("arrived", ->(f, e, c) palm_error(f) < @r_reach)
    touched = Latch.test("touched", ->(f, e, c) touch_total(f) > @touch_th)
    gripped = Latch.test("gripped", ->(f, e, c) gripped?(f))
    cleared = Latch.test("cleared", ->(f, e, c) f.at("env_obj_pos", 2) > @bz_clear)
    ready = Latch.test("ready", ->(f, e, c) pinch_ready?(f))
    taken = Latch.test("taken", ->(f, e, c) handed_over?(f))
    mv = Movement.new("bimanual")
    mv.add(Chunk.new("reach", @t_reach).pose(p_open).hold_until(arrived.after_min(@t_reach * ~0.7), @to_reach).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "reach", @t_reach)))
    mv.add(Chunk.new("descend", @t_desc).pose(p_open).hold_until(Latch.any([touched, ready.after_min(@t_desc)]), @to_desc).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "descend", @t_desc)))
    mv.add(Chunk.new("close", @t_close).pose(p_grip).drive(squeeze).hold_until(gripped.after_min(@t_close * ~0.5), @to_close).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "close", @t_close)))
    mv.add(Chunk.new("lift", @t_lift).pose(p_grip).drive(squeeze).hold_until(cleared, @to_lift).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "lift", @t_lift)))
    # the carry to the handover point is 30-45 cm; `t_bcarry` (> 0) replaces
    # the relocate carry's short duration with a slow one (the episode is 10 s)
    t_bc = param("t_bcarry", ~0.0, ~0.0, ~2.5)
    tc = @t_carry
    tc = t_bc if t_bc > ~0.0
    mv.add(Chunk.new("carry", tc).pose(p_grip).drive(squeeze).hold_until(Latch.after(tc)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "carry", tc)))
    mv.add(Chunk.new("handover", t_hand).pose(p_grip).drive(squeeze).hold_until(taken, ~6.0).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "handover", t_hand)))
    mv.add(Chunk.new("release", t_rel).pose(p_drop).hold_until(Latch.after(~100.0)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "release", t_rel)))
    mv

  # The handover chunk's latch: the prosthesis has held the box for n_pros
  # frames (skills built on this one may ask for more).
  -> handed_over?(f)
    @pros_frames >= @n_pros

  # Palm goals for the bimanual chunks (the pinch point while reaching).
  -> phase_goal(f)
    ph = @phase
    ox = f.at("env_obj_pos", 0) + @box[0]
    oy = f.at("env_obj_pos", 1) + @box[1]
    return [ox, oy, @bz_above] if ph == "reach"
    return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], @bz_grasp] if ph == "descend"
    return [@hold[0], @hold[1], @hold[2]] if ph == "close"
    return [@hold[0], @hold[1], @bz_lift] if ph == "lift"
    return [@hand_pt[0], @hand_pt[1], @hand_pt[2]] if ph == "carry" || ph == "handover"
    [@hand_pt[0] + @retreat[0], @hand_pt[1] + @retreat[1], @hand_pt[2] + @retreat[2]]

  -> before(f, ctl)
    # prosthesis and myo contact counts (touching_body: myo, prosth, start, goal, env)
    @pros_frames = @pros_frames + 1 if f.at("env_touching_body", 1) > ~0.5
    @myo_free = 0 if f.at("env_touching_body", 0) > ~0.5
    @myo_free = @myo_free + 1 if f.at("env_touching_body", 0) < ~0.5
    return nil if @phase != "descend" && @phase != "close"
    return nil if touch_total(f) < @touch_th
    k = 0
    while k < 2
      off = f.at("touch_pos", k) - f.at("env_obj_pos", k)
      @felt[k] = @felt[k] + (off - @felt[k]) / (@felt_n + 1)
      k += 1
    @felt_n = @felt_n + 1 if @felt_n < 20
    nil

  -> after(f, ctl)
    feed_forward(ctl) if @kv > ~0.0
    if (@phase == "lift" || @phase == "carry") && lost?(f)
      @felt_n = 0
      @felt = [~0.0, ~0.0]
      ctl.track("arm").jump(ctl, f, "reach")
    mpl_update(f, ctl)
    nil

  # ---- prosthesis ------------------------------------------------------------

  -> mpl_setup
    @mpl_joints = MyoBimanualProsthesis.joints
    @mpl_servos = MyoBimanualProsthesis.servos
    @mpl_ranges = MyoBimanualProsthesis.ranges
    @mpl_state = "wait"
    @mpl_t0 = ~0.0
    @mpl_from = nil
    @mpl_to = [~0.0, ~0.0, ~0.0]
    @mpl_hand0 = nil
    @mpl_close = 0
    @mpl_off = @mpl_joints.map ->(n) param("m_off_" + n.slice(11, n.size - 11), ~0.0, ~-0.5, ~0.5)
    # fraction of each hand servo's range when closed on the box
    @mpl_shut = (7...17).map ->(k) param("m_shut_" + k.to_s, ~0.7, ~0.0, ~1.0)
    @mpl_grip = [param("m_gx", ~0.05, ~-0.05, ~0.15), param("m_gy", ~0.0, ~-0.08, ~0.08), param("m_gz", ~0.03, ~-0.02, ~0.1)]
    @mpl_pre = param("m_pre", ~0.08, ~0.02, ~0.2)
    @mpl_goal = [param("m_px", ~0.0, ~-0.08, ~0.08), param("m_py", ~0.0, ~-0.08, ~0.08)]
    @mpl_h_carry = param("m_hcarry", ~0.15, ~0.05, ~0.3)
    @mpl_h_place = param("m_hplace", ~0.035, ~0.0, ~0.1)
    @mpl_t_move = param("m_tmove", ~0.5, ~0.2, ~1.2)
    @mpl_t_close = param("m_tclose", ~0.3, ~0.1, ~0.8)
    @mpl_hold_off = [~0.0, ~0.0, ~0.0]
    # `m_late` = 1: the prosthesis waits for the myo hand to arrive and hold
    # still at the handover point (its `handover` chunk, plus m_settle s)
    # before it reaches in; reaching in during the carry knocks the box out
    # of the myo hand
    @mpl_late = param("m_late", ~0.0, ~0.0, ~1.0) > ~0.5
    @mpl_settle = param("m_settle", ~0.2, ~0.0, ~1.0)
    @hand_t0 = ~-1.0
    nil

  -> mpl_go(f, state, to)
    @mpl_state = state
    @mpl_t0 = f.t
    @mpl_from = [f.at("env_Rpalm_pos", 0), f.at("env_Rpalm_pos", 1), f.at("env_Rpalm_pos", 2)]
    @mpl_to = to
    nil

  -> mpl_update(f, ctl)
    if @mpl_hand0 == nil
      @mpl_hand0 = (7...17).map ->(k) f.at("pros_q", k)
      @mpl_arm0 = (0...7).map ->(k) f.at("pros_q", k)
    st = @mpl_state
    e = f.t - @mpl_t0
    box = [f.at("env_obj_pos", 0), f.at("env_obj_pos", 1), f.at("env_obj_pos", 2)]
    goal = [f.at("env_goal_pos", 0) + @mpl_goal[0], f.at("env_goal_pos", 1) + @mpl_goal[1], ~1.09]
    @hand_t0 = f.t if @phase == "handover" && @hand_t0 < ~0.0
    reach_in = @phase == "carry" || @phase == "handover"
    reach_in = @phase == "handover" && f.t - @hand_t0 >= @mpl_settle if @mpl_late
    if st == "wait" && reach_in
      mpl_go(f, "approach", [box[0] + @mpl_grip[0], box[1] + @mpl_grip[1], box[2] + @mpl_grip[2] + @mpl_pre])
    elsif st == "approach"
      @mpl_to = [box[0] + @mpl_grip[0], box[1] + @mpl_grip[1], box[2] + @mpl_grip[2] + @mpl_pre]
      mpl_go(f, "grip", [box[0] + @mpl_grip[0], box[1] + @mpl_grip[1], box[2] + @mpl_grip[2]]) if e > @mpl_t_move && @phase == "handover"
    elsif st == "grip"
      @mpl_close = 1 if e > @mpl_t_move * ~0.5
      if @phase == "release" && @myo_free > 10
        k = 0
        while k < 3
          @mpl_hold_off[k] = f.at("env_Rpalm_pos", k) - box[k]
          k += 1
        mpl_go(f, "carry", [goal[0] + @mpl_hold_off[0], goal[1] + @mpl_hold_off[1], goal[2] + @mpl_h_carry + @mpl_hold_off[2]])
    elsif st == "carry" && e > @mpl_t_move
      mpl_go(f, "place", [goal[0] + @mpl_hold_off[0], goal[1] + @mpl_hold_off[1], goal[2] + @mpl_h_place + @mpl_hold_off[2]])
    elsif st == "place" && (f.at("env_touching_body", 3) > ~0.5 || e > @mpl_t_move * ~1.5)
      @mpl_close = 0
      mpl_go(f, "release", @mpl_to)
    elsif st == "release" && e > @mpl_t_close
      mpl_go(f, "retreat", [@mpl_to[0], @mpl_to[1] + ~0.05, @mpl_to[2] + ~0.12])
    mpl_command(f, ctl)
    nil

  # Ease the palm target (min-jerk), look the arm posture up, add the joint
  # offsets, and send every servo its normalised action.
  -> mpl_command(f, ctl)
    if @mpl_from == nil
      # waiting: hold the start pose (an unset servo would go to mid-range)
      k = 0
      while k < 7
        mpl_servo(ctl, k, @mpl_arm0[k])
        k += 1
      k = 7
      while k < 17
        mpl_servo(ctl, k, @mpl_hand0[k - 7])
        k += 1
      return nil
    s = Easing.min_jerk(clamp((f.t - @mpl_t0) / @mpl_t_move, ~0.0, ~1.0))
    x = @mpl_from[0] + (@mpl_to[0] - @mpl_from[0]) * s
    y = @mpl_from[1] + (@mpl_to[1] - @mpl_from[1]) * s
    z = @mpl_from[2] + (@mpl_to[2] - @mpl_from[2]) * s
    q = MyoBimanualProsthesis.at(x, y, z)
    k = 0
    while k < 7
      mpl_servo(ctl, k, q[k] + @mpl_off[k])
      k += 1
    k = 7
    while k < 17
      lo = @mpl_ranges[2 * k]
      hi = @mpl_ranges[2 * k + 1]
      v = @mpl_hand0[k - 7]
      v = lo + (hi - lo) * @mpl_shut[k - 7] if @mpl_close == 1
      mpl_servo(ctl, k, v)
      k += 1
    nil

  -> mpl_servo(ctl, k, q)
    lo = @mpl_ranges[2 * k]
    hi = @mpl_ranges[2 * k + 1]
    a = clamp((q - (lo + hi) * ~0.5) / ((hi - lo) * ~0.5), ~-1.0, ~1.0)
    ctl.motor(@mpl_servos[k], a)
