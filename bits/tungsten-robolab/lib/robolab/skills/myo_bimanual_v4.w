# MyoBimanualV4: round-4 handover (MyoBimanualV3Skill plus a closed-loop
# prosthesis), opt-in by params; with `m_v4` = 0 (and `myo_idle` = 0) it is
# MyoBimanualV3Skill.
#
# Round 3's prosthesis almost never touched the box (0.6 contact frames per
# episode). Its palm went open loop through the posture table, whose far
# (x < 0) end the MPL arm cannot reach (12 cm short at x = -0.2, 4 cm at
# -0.1), and it closed its fingers on a clock. Here:
#
#   m_v4     1: the MPL palm is servoed: the table is looked up at the eased
#            target plus a clamped integral of the measured palm error
#            (`env_Rpalm_pos`; gains m_ki, m_ilim), and every state change
#            is latched on the palm having arrived:
#              rise      (m_rise > 0) straight up from where it waits to
#                        m_rise above the approach point, so the way in
#                        comes down over the box instead of up into it
#              approach  palm `m_pre` above the grip point (box + m_g*),
#                        and `m_apx`, `m_apy` beside it (a side approach
#                        clear of the myo hand; box frame with m_bframe),
#                        tracking the box; LATCHED on arriving within m_rapp
#              descend   palm down to the grip point; LATCHED on arriving
#                        within m_rclose (or 2 m_tmove)
#              grip      fingers close, the palm holds where it closed;
#                        LATCHED on the myo hand having let go (or, with
#                        m_now, after m_thold)
#              carry / place / release / retreat as before (to the goal
#              pillar, down until the pillar touches the box, open, lift off)
#            and the myo hand lets go (its handover chunk's latch) only once
#            the prosthesis has closed on the box for m_hand seconds and
#            touched it for n_pros frames.
#   m_bframe 1: the grip offset (m_gx, m_gy) turns with the box's yaw (the
#            `box_up` sensor) from its resting yaw on the pillar, so the
#            prosthesis grips the same end of the box however the myo hand
#            has turned it
#   m_now    1: the prosthesis starts at once (development: with the box
#            started within its reach, see tasks/myo_bimanual_pdev.py)
#   myo_idle 1: the myo arm holds still at its start posture (development)
#   b_patience  the myo reach and descend timeouts are multiplied by it
#            (default 1): the carry-to-handover episode is 10 s long, so the
#            pinch can wait to arrive over the box before coming down
#   h_kd_*   joint-space damping while the myo arm holds the box out (the
#            handover chunk; with h_carry also the carry): offsets
#            -h_kd_j qd_j (clamped to +-h_lim) on elv_angle, shoulder_elv,
#            shoulder_rot, elbow and pro_sup. Held out at the handover point
#            the arm otherwise swings in a 0.7 s limit cycle (palm +-6 cm,
#            pro_sup +-0.3 rad), which no prosthesis grip can catch; applied
#            over the whole episode the same damping spoils the grasp.
#   h_cc     co-contraction (drive on every arm muscle) while holding out
#   m_vstill (> 0) the prosthesis sets off, and comes down onto the box, only
#            while the box moves slower than this (m/s, low-passed)
#   h_freeze 1: while holding out, the servo's arm offsets are frozen at their
#            first value (the palm servo off; the reflexes and the static
#            feed-forward hold that posture): the servo's own loop through the
#            posture table is what swings the arm, the reflexes alone do not

+ MyoBimanualV4Skill < MyoBimanualV3Skill
  -> start(frame, ctl)
    @m_v4 = param("m_v4", ~0.0, ~0.0, ~1.0) > ~0.5
    @m_now = param("m_now", ~0.0, ~0.0, ~1.0) > ~0.5
    @myo_idle = param("myo_idle", ~0.0, ~0.0, ~1.0) > ~0.5
    @m_ki = param("m_ki", ~6.0, ~0.0, ~40.0)
    @m_ilim = param("m_ilim", ~0.04, ~0.0, ~0.12)
    @m_rapp = param("m_rapp", ~0.02, ~0.005, ~0.08)
    @m_rclose = param("m_rclose", ~0.012, ~0.003, ~0.05)
    @m_thold = param("m_thold", ~0.4, ~0.0, ~2.0)
    @m_hand = param("m_hand", ~0.3, ~0.0, ~1.5)
    @m_free = param("m_free", ~10.0, ~1.0, ~60.0)
    @m_bframe = param("m_bframe", ~0.0, ~0.0, ~1.0) > ~0.5
    @m_ap = [param("m_apx", ~0.0, ~-0.1, ~0.15), param("m_apy", ~0.0, ~-0.1, ~0.1)]
    @m_rise = param("m_rise", ~0.0, ~0.0, ~0.2)
    @m_vstill = param("m_vstill", ~0.0, ~0.0, ~0.5)
    @m_prev = nil
    @m_speed = ~0.0
    @m_int = [~0.0, ~0.0, ~0.0]
    @m_closed_t = ~-1.0
    @h_kd = [param("h_kd_elv", ~0.0, ~0.0, ~0.6), param("h_kd_sh", ~0.0, ~0.0, ~0.6), param("h_kd_rot", ~0.0, ~0.0, ~0.6), param("h_kd_elb", ~0.0, ~0.0, ~0.6), param("h_kd_ps", ~0.0, ~0.0, ~0.6)]
    @h_lim = param("h_lim", ~0.3, ~0.02, ~1.0)
    @h_carry = param("h_carry", ~0.0, ~0.0, ~1.0) > ~0.5
    @h_cc = param("h_cc", ~0.0, ~0.0, ~0.3)
    @h_freeze = param("h_freeze", ~0.0, ~0.0, ~1.0) > ~0.5
    @h_off = nil
    @h_on = @h_cc > ~0.0
    k = 0
    while k < 5
      @h_on = true if @h_kd[k] > ~0.0
      k += 1
    super(frame, ctl)

  # Holding the box out: the handover chunk (and with h_carry the carry).
  -> holding_out?
    @phase == "handover" || (@h_carry && @phase == "carry")

  -> servo_step(f, ctl)
    frozen = @h_freeze && holding_out?
    off = nil
    if frozen && @h_off != nil
      add_static_drive(ctl) if @ff_id > ~0.0 && @cmd_p != nil && @ff_m.size > 0
      off = @h_off.map ->(v) v
    else
      off = super(f, ctl)
      @h_off = off.map(->(v) v) if frozen
    return off if !@h_on || !holding_out?
    k = 0
    while k < 5
      if @h_kd[k] > ~0.0
        dq = clamp(~0.0 - @h_kd[k] * f.at("qd", @arm_j[k]), ~0.0 - @h_lim, @h_lim)
        joint_offset(off, @jpd_names[k], dq)
      k += 1
    if @h_cc > ~0.0
      @am.each ->(m) ctl.add_drive(m, @h_cc)
    off

  -> movement(p_open, p_grip, p_drop, squeeze, servo)
    # patience: the episode is 10 s, so the reach and descend may wait for
    # the pinch to arrive (their timeouts x b_patience) instead of coming
    # down on the box while the arm still lags
    pat = param("b_patience", ~1.0, ~1.0, ~6.0)
    @to_reach = @to_reach * pat
    @to_desc = @to_desc * pat
    mv = super(p_open, p_grip, p_drop, squeeze, servo)
    return mv if !@myo_idle
    idle = Movement.new("idle")
    idle.add(Chunk.new("idle", ~0.2).pose(p_open).hold_until(Latch.after(~100.0)))
    idle

  -> handed_over?(f)
    return super(f) if !@m_v4
    return false if @m_closed_t < ~0.0
    f.t - @m_closed_t >= @m_hand && @pros_frames >= @n_pros

  # Distance from the MPL palm to its (uneased) target.
  -> mpl_err(f)
    dx = @mpl_to[0] - f.at("env_Rpalm_pos", 0)
    dy = @mpl_to[1] - f.at("env_Rpalm_pos", 1)
    dz = @mpl_to[2] - f.at("env_Rpalm_pos", 2)
    Math.sqrt(dx * dx + dy * dy + dz * dz)

  -> mpl_update(f, ctl)
    return super(f, ctl) if !@m_v4
    if @mpl_hand0 == nil
      @mpl_hand0 = (7...17).map ->(k) f.at("pros_q", k)
      @mpl_arm0 = (0...7).map ->(k) f.at("pros_q", k)
    st = @mpl_state
    e = f.t - @mpl_t0
    box = [f.at("env_obj_pos", 0), f.at("env_obj_pos", 1), f.at("env_obj_pos", 2)]
    if @m_prev != nil
      dx = box[0] - @m_prev[0]
      dy = box[1] - @m_prev[1]
      dz = box[2] - @m_prev[2]
      # low-passed box speed (m/s)
      @m_speed = @m_speed + (Math.sqrt(dx * dx + dy * dy + dz * dz) / @dt - @m_speed) * ~0.2
    @m_prev = box
    still = @m_vstill <= ~0.0 || @m_speed < @m_vstill
    c = ~1.0
    sn = ~0.0
    if @m_bframe
      # resting yaw on the pillar: pi (the box's x axis along world -x)
      dy = f.at("box_up", 3) - ~3.141592653589793
      c = Math.cos(dy)
      sn = Math.sin(dy)
    grip = [box[0] + c * @mpl_grip[0] - sn * @mpl_grip[1], box[1] + sn * @mpl_grip[0] + c * @mpl_grip[1], box[2] + @mpl_grip[2]]
    above = [grip[0] + c * @m_ap[0] - sn * @m_ap[1], grip[1] + sn * @m_ap[0] + c * @m_ap[1], grip[2] + @mpl_pre]
    goal = [f.at("env_goal_pos", 0) + @mpl_goal[0], f.at("env_goal_pos", 1) + @mpl_goal[1], ~1.09]
    @hand_t0 = f.t if @phase == "handover" && @hand_t0 < ~0.0
    reach_in = @m_now || (@phase == "handover" && f.t - @hand_t0 >= @mpl_settle && still)
    if st == "wait" && reach_in && @m_rise > ~0.0
      mpl_go(f, "rise", [f.at("env_Rpalm_pos", 0), f.at("env_Rpalm_pos", 1), above[2] + @m_rise])
    elsif st == "wait"
      mpl_go(f, "approach", above) if reach_in
    elsif st == "rise"
      mpl_go(f, "approach", above) if e > @mpl_t_move && mpl_err(f) < ~2.0 * @m_rapp || e > ~2.0 * @mpl_t_move
    elsif st == "approach"
      @mpl_to = above
      mpl_go(f, "descend", grip) if e > @mpl_t_move && mpl_err(f) < @m_rapp && still
    elsif st == "descend"
      @mpl_to = grip
      if (e > @mpl_t_move && mpl_err(f) < @m_rclose) || e > ~2.0 * @mpl_t_move
        @mpl_close = 1
        @m_closed_t = f.t
        mpl_go(f, "grip", grip)
    elsif st == "grip"
      let_go = @myo_free > @m_free
      let_go = e > @m_thold if @m_now
      if e > @mpl_t_close && let_go
        k = 0
        while k < 3
          @mpl_hold_off[k] = f.at("env_Rpalm_pos", k) - box[k]
          k += 1
        mpl_go(f, "carry", [goal[0] + @mpl_hold_off[0], goal[1] + @mpl_hold_off[1], goal[2] + @mpl_h_carry + @mpl_hold_off[2]])
    elsif st == "carry" && e > @mpl_t_move && mpl_err(f) < @m_rapp * ~2.0
      mpl_go(f, "place", [goal[0] + @mpl_hold_off[0], goal[1] + @mpl_hold_off[1], goal[2] + @mpl_h_place + @mpl_hold_off[2]])
    elsif st == "place" && (f.at("env_touching_body", 3) > ~0.5 || e > @mpl_t_move * ~1.5)
      @mpl_close = 0
      mpl_go(f, "release", @mpl_to)
    elsif st == "release" && e > @mpl_t_close
      mpl_go(f, "retreat", [@mpl_to[0], @mpl_to[1] + ~0.05, @mpl_to[2] + ~0.12])
    mpl_command(f, ctl)
    ctl.emit("dbg:" + @mpl_state + " err " + (mpl_err(f) * ~1000.0).round.to_s + " int " + @m_int.map(->(v) (v * ~1000.0).round.to_s).join(",")) if @debug
    nil

  # The base command with the palm error's clamped integral added to the
  # table lookup point (m_v4).
  -> mpl_command(f, ctl)
    return super(f, ctl) if !@m_v4 || @mpl_from == nil
    s = Easing.min_jerk(clamp((f.t - @mpl_t0) / @mpl_t_move, ~0.0, ~1.0))
    x = [~0.0, ~0.0, ~0.0]
    k = 0
    while k < 3
      x[k] = @mpl_from[k] + (@mpl_to[k] - @mpl_from[k]) * s
      err = x[k] - f.at("env_Rpalm_pos", k)
      @m_int[k] = clamp(@m_int[k] + @m_ki * err * @dt, ~0.0 - @m_ilim, @m_ilim)
      k += 1
    q = MyoBimanualProsthesis.at(x[0] + @m_int[0], x[1] + @m_int[1], x[2] + @m_int[2])
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
