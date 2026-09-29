# MyoRelocateV5: round-5 grasp and transport options for the relocate skill
# (MyoRelocateV4Skill), each opt-in by params; with every switch at 0 it is
# MyoRelocateV4Skill.
#
# Round-4 traces (200 dev seeds of the relocate_p2 champion): the hand closes
# while its palm still moves at ~1 m/s (median; the descend aims below the
# object and a touch closes the hand), and aim errors over 4 cm (20% of
# episodes) lift almost nothing. After the grasp the lift and carry swing the
# held object at 2.5-3 m/s (the posture table's elbow and plane of elevation
# change fast with height near the table), so 37 of 65 objects lifted above
# the rim but not placed left the hand before the release.
#
#   settle   1: the descend stops `h_hov` above the grasp point, and a
#            `settle` chunk brings the pinch down onto it; the hand closes
#            only on a latched "still" test: the pinch within r_still (xy)
#            of the grasp point, no more than z_still above it (the grasp
#            point may lie below what the table lets the pinch reach), and
#            slower than v_still for
#            n_still consecutive ticks (or a touch while slower than
#            v_touch; or the timeout to_set). st_kd: task-space damping of
#            the resolved-rate correction while settling.
#   see      1: aim at the object as seen (the `obj_see` sensor: the
#            centroid of the object's three primitives, which can sit 2-3 cm
#            from the site the official observation reports), blended by
#            k_see; the reach hovers h_above over the seen top, the pinch
#            closes dz_see from the seen centroid's height.
#   tab5     1: the round-5 posture table and its static feed-forward
#            (MyoRelocatePosturesV5 / MyoRelocateFFV5: elbow-flexed and
#            smooth across the workspace). tab5_y: use it only for objects
#            starting beyond this y (the far side), else the base table.
#   tab3_y   with tab3 1 (round 3's pronation-capped table, pro_sup <= 0.5,
#            the palm turned down by the shoulder): only for objects
#            starting beyond this y. Far-side reaches roll the forearm from
#            pro_sup 1.3 to 0 (the biceps out-pulls pronators that sit short
#            past ~1 rad), and the pinch turns away from the object.
#   carry5   1: transport: the servo's integrals restart at the lift (no
#            wound-up push from the grasp; ir_close 1: also at the close),
#            the lift and carry run their own resolved-rate and servo
#            integral gains (rr_kp_c, rr_ki_c, servo_i_c), lf_kd damps the
#            resolved-rate correction during lift and carry, the lift heads
#            lift_to of the way toward the receptacle as it rises, and the
#            carry hands over to the lower only once the object is over the
#            receptacle's interior (within r_drop of its centre, above z_in,
#            moving slower than v_in horizontally).
#   y_far5   far-side arm control: for objects starting beyond y_far5 every
#            param named in far5_name? (arm servo, pronation tone, joint-space
#            loop, wrist offsets, reach and close timing) takes its `_f` twin
#            (declared whenever y_far5 > -1, default the near value). Far
#            reaches roll the forearm (pro_sup 1.3 -> 0.1 in the median far
#            episode) and lift in 7% of them against ~40% elsewhere.
#   t_blend  the table's arm command eases in from the start posture over
#            the first t_blend s (see postures_at).
#   squeeze_c  the grip's squeeze drive during lift, carry and lower
#            (default: the close's `squeeze`).
#   lead_g / lead_c   time lead of the eased servo target in the grasp
#            chunks / the transport chunks (s): the target runs ahead of
#            its min-jerk plan by this much, against the servo's lag.

+ MyoRelocateV5Skill < MyoRelocateV4Skill
  -> start(frame, ctl)
    # far-side arm control (y_far5): decided first, every later param reads it
    @far5_on = false
    yf = param("y_far5", ~-1.0, ~-1.0, ~-0.1)
    @far5 = yf > ~-1.0 && frame.has?("env_obj_pos") && frame.at("env_obj_pos", 1) < yf
    @far5_on = yf > ~-1.0
    @settle = param("settle", ~0.0, ~0.0, ~1.0) > ~0.5
    @see = param("see", ~0.0, ~0.0, ~1.0) > ~0.5 && frame.has?("obj_see")
    @carry5 = param("carry5", ~0.0, ~0.0, ~1.0) > ~0.5
    tab = param("tab5", ~0.0, ~0.0, ~1.0) > ~0.5
    y5 = param("tab5_y", ~0.0, ~-0.5, ~0.0)
    @tab5 = tab
    @tab5 = false if tab && frame.has?("env_obj_pos") && frame.at("env_obj_pos", 1) >= y5 && y5 < ~0.0
    # tab3_y: the round-3 pronation-capped table (tab3) only for objects
    # starting beyond this y; nearer ones keep the base table
    y3 = param("tab3_y", ~0.0, ~-0.5, ~0.0)
    @t3_skip = y3 < ~0.0 && frame.has?("env_obj_pos") && frame.at("env_obj_pos", 1) >= y3
    @t_blend = param("t_blend", ~0.0, ~0.0, ~0.5)
    @w_blend = ~1.0
    @w_blend = ~0.0 if @t_blend > ~0.0
    sq0 = ~0.15
    sq0 = params["squeeze"] if params.key?("squeeze")
    @sq_c = param("squeeze_c", sq0, ~0.0, ~0.8)
    @lead_g = param("lead_g", ~0.0, ~0.0, ~0.15)
    @lead_c = param("lead_c", ~0.0, ~0.0, ~0.15)
    @h_hov = ~0.0
    @st_kd = ~0.0
    @lf_kd = ~0.0
    @still_n = ~0.0
    @spd = ~0.0
    @p_prev = nil
    if @settle
      @h_hov = param("h_hov", ~0.03, ~0.0, ~0.08)
      @t_set = param("t_set", ~0.08, ~0.02, ~0.3)
      @to_set = param("to_set", ~0.2, ~0.03, ~0.5)
      @r_still = param("r_still", ~0.012, ~0.003, ~0.04)
      @z_still = param("z_still", ~0.015, ~0.003, ~0.05)
      @v_still = param("v_still", ~0.15, ~0.02, ~0.8)
      @n_still = param("n_still", ~3.0, ~1.0, ~10.0)
      @v_touch = param("v_touch", ~0.3, ~0.0, ~2.0)
      @st_kd = param("st_kd", ~0.0, ~0.0, ~10.0)
      @a_spd = param("a_spd", ~0.5, ~0.1, ~1.0)
    if @see
      @k_see = param("k_see", ~1.0, ~0.0, ~1.0)
      @h_above = param("h_above", ~0.06, ~0.0, ~0.14)
      @dz_see = param("dz_see", ~-0.02, ~-0.07, ~0.03)
    if @carry5
      @lf_kd = param("lf_kd", ~0.0, ~0.0, ~10.0)
      @z_in = param("z_in", ~1.12, ~1.05, ~1.3)
      @v_in = param("v_in", ~0.4, ~0.05, ~2.0)
      @ir_close = param("ir_close", ~0.0, ~0.0, ~1.0) > ~0.5
      @lift_to = param("lift_to", ~0.0, ~0.0, ~0.8)
    super(frame, ctl)
    # transport gains (carry5; defaults: the grasp's, after the far-side
    # settings are applied)
    # the arm's start posture (the geometry's reference) for the blend
    q_ref = @g.reference_posture
    @q_start = @arm_j.map ->(j) q_ref[j]
    @g_grasp = [@rr_kp, @rr_ki, @ki_s]
    @g_carry = @g_grasp
    if @carry5
      @g_carry = [param("rr_kp_c", @rr_kp, ~0.0, ~20.0), param("rr_ki_c", @rr_ki, ~0.0, ~60.0), param("servo_i_c", @ki_s, ~0.0, ~30.0)]

  # Far-side twins (y_far5): each arm-servo, pronation, joint-loop, wrist and
  # reach-timing param in FAR5 is also declared as <name>_f (default: its
  # near value) and, for objects starting beyond y_far5, used instead.
  -> param(name, default, lo, hi)
    v = super(name, default, lo, hi)
    return v if !@far5_on || !far5_name?(name)
    vf = super(name + "_f", v, lo, hi)
    return vf if @far5
    v

  -> far5_name?(name)
    ["pron_i", "pron_lim", "kp_pron", "kd_pron", "kq_elv", "kq_sh", "kq_rot", "kq_elb", "kq_ps", "kqd_elv", "kqd_sh", "kqd_rot", "kqd_elb", "kqd_ps", "jpd_lim", "dps", "ddev", "dflex", "stiff_sh", "spring", "kv", "ff_id", "servo_lim", "servo_leak", "rr_lim", "rr_lam", "t_reach", "to_reach", "t_desc", "to_desc", "t_close", "to_close", "squeeze"].include?(name)

  # ---- chunks ----------------------------------------------------------------

  -> movement(p_open, p_grip, p_drop, squeeze, servo)
    # the transport's squeeze: the close's, or squeeze_c on the same muscles
    carry_sq = zeros
    sq_same = true
    i = 0
    while i < squeeze.size
      carry_sq[i] = squeeze[i]
      if squeeze[i] > ~0.0
        carry_sq[i] = @sq_c
        sq_same = false if @sq_c != squeeze[i]
      i += 1
    return super(p_open, p_grip, p_drop, squeeze, servo) if !@settle && sq_same
    arrived = Latch.test("arrived", ->(f, e, c) palm_error(f) < @r_reach)
    touched = Latch.test("touched", ->(f, e, c) touch_total(f) > @touch_th)
    gripped = Latch.test("gripped", ->(f, e, c) gripped?(f))
    cleared = Latch.test("cleared", ->(f, e, c) f.at("env_obj_pos", 2) > @z_clear)
    over = Latch.test("over", ->(f, e, c) over_box?(f))
    still = Latch.test("still", ->(f, e, c) @still_n >= @n_still)
    soft = Latch.test("soft", ->(f, e, c) touch_total(f) > @touch_th && @spd < @v_touch)
    ready = Latch.test("ready", ->(f, e, c) pinch_ready?(f))
    mv = Movement.new("relocate")
    mv.add(Chunk.new("reach", @t_reach).pose(p_open).hold_until(arrived.after_min(@t_reach * ~0.7), @to_reach).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "reach", @t_reach)))
    if @settle
      mv.add(Chunk.new("descend", @t_desc).pose(p_open).hold_until(Latch.any([touched, arrived.after_min(@t_desc * ~0.7)]), @to_desc).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "descend", @t_desc)))
      mv.add(Chunk.new("settle", @t_set).pose(p_open).hold_until(Latch.any([still, soft]), @to_set).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "settle", @t_set)))
    if !@settle
      mv.add(Chunk.new("descend", @t_desc).pose(p_open).hold_until(Latch.any([touched, ready.after_min(@t_desc)]), @to_desc).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "descend", @t_desc)))
    mv.add(Chunk.new("close", @t_close).pose(p_grip).drive(squeeze).hold_until(gripped.after_min(@t_close * ~0.5), @to_close).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "close", @t_close)))
    mv.add(Chunk.new("lift", @t_lift).pose(p_grip).drive(carry_sq).hold_until(cleared, @to_lift).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "lift", @t_lift)))
    mv.add(Chunk.new("carry", @t_carry).pose(p_grip).drive(carry_sq).hold_until(over.after_min(@t_carry * ~0.5), @to_carry).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "carry", @t_carry)))
    mv.add(Chunk.new("lower", @t_low).pose(p_grip).drive(carry_sq).hold_until(Latch.after(@t_low + @t_hold)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "lower", @t_low)))
    mv.add(Chunk.new("release", ~0.1).pose(p_drop).hold_until(Latch.after(~100.0)).correct(servo, @spring).on_enter(->(f, c) enter_phase(f, "release", ~0.1)))
    mv

  # ---- per-tick state --------------------------------------------------------

  # The pinch's speed (smoothed) and the still counter, before the chunk's
  # latches are tested.
  -> before(f, ctl)
    super(f, ctl)
    @w_blend = Easing.min_jerk(clamp(f.t / @t_blend, ~0.0, ~1.0)) if @t_blend > ~0.0
    return nil if !@settle
    feel(f) if @phase == "settle" && touch_total(f) >= @touch_th
    p = [~0.0, ~0.0, ~0.0]
    k = 0
    while k < 3
      p[k] = (f.at("tips", k) + (f.at("tips", 3 + k) + f.at("tips", 6 + k)) * ~0.5) * ~0.5
      k += 1
    if @p_prev != nil
      dx = p[0] - @p_prev[0]
      dy = p[1] - @p_prev[1]
      dz = p[2] - @p_prev[2]
      v = Math.sqrt(dx * dx + dy * dy + dz * dz) / @dt
      @spd = @spd + @a_spd * (v - @spd)
    @p_prev = p
    if @phase != "settle"
      @still_n = ~0.0
      return nil
    goal = phase_goal(f)
    ex = goal[0] - p[0]
    ey = goal[1] - p[1]
    ez = goal[2] - p[2]
    ok = Math.sqrt(ex * ex + ey * ey) < @r_still && ez > ~0.0 - @z_still && @spd < @v_still
    @still_n = ~0.0 if !ok
    @still_n = @still_n + ~1.0 if ok
    nil

  # Where the hand feels the object while settling (as the base skill does
  # in descend and close).
  -> feel(f)
    k = 0
    while k < 2
      off = f.at("touch_pos", k) - f.at("env_obj_pos", k)
      @felt[k] = @felt[k] + (off - @felt[k]) / (@felt_n + 1)
      k += 1
    @felt_n = @felt_n + 1 if @felt_n < 20
    nil

  -> enter_phase(f, name, duration)
    super(f, name, duration)
    if @carry5 && (name == "lift" || (@ir_close && name == "close"))
      k = 0
      while k < 3
        @integ[k] = ~0.0
        @rr_int[k] = ~0.0
        k += 1
    if @carry5
      g = @g_grasp
      g = @g_carry if name == "lift" || name == "carry" || name == "lower" || name == "release"
      @rr_kp = g[0]
      @rr_ki = g[1]
      @ki_s = g[2]
    lead = @lead_g
    lead = @lead_c if name == "lift" || name == "carry" || name == "lower"
    @t0 = @t0 - lead if lead > ~0.0
    nil

  # ---- goals -----------------------------------------------------------------

  # The object point the grasp aims at: the site, or (see) the seen centroid.
  -> obj_at(f, k)
    return f.at("env_obj_pos", k) if !@see
    s = f.at("env_obj_pos", k)
    s + @k_see * (f.at("obj_see", k) - s)

  -> phase_goal(f)
    ph = @phase
    if @see && (ph == "reach" || ph == "descend" || ph == "settle")
      ox = obj_at(f, 0) + @ox
      oy = obj_at(f, 1) + @oy
      zg = f.at("obj_see", 2) + @dz_see
      return [ox, oy, f.at("obj_see", 6) + @h_above] if ph == "reach"
      return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], zg + @h_hov] if ph == "descend"
      return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], zg]
    if @carry5 && ph == "lift" && @lift_to > ~0.0
      gx = f.at("env_goal_pos", 0) + @cx
      gy = f.at("env_goal_pos", 1) + @cy
      return [@hold[0] + @lift_to * (gx - @hold[0]), @hold[1] + @lift_to * (gy - @hold[1]), @z_lift]
    if @settle && (ph == "descend" || ph == "settle")
      ox = f.at("env_obj_pos", 0) + @ox
      oy = f.at("env_obj_pos", 1) + @oy
      return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], @z_grasp + @h_hov] if ph == "descend"
      return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], @z_grasp]
    super(f)

  -> control_point(f, k)
    if @phase == "settle"
      fingers = (f.at("tips", 3 + k) + f.at("tips", 6 + k)) * ~0.5
      return (f.at("tips", k) + fingers) * ~0.5
    super(f, k)

  # Over the interior (carry5: also above z_in and slow horizontally).
  -> over_box?(f)
    return super(f) if !@carry5
    dx = f.at("env_obj_pos", 0) - f.at("env_goal_pos", 0)
    dy = f.at("env_obj_pos", 1) - f.at("env_goal_pos", 1)
    return false if Math.sqrt(dx * dx + dy * dy) >= @r_drop
    return false if f.at("env_obj_pos", 2) < @z_in
    vx = f.at("obj_vel", 0)
    vy = f.at("obj_vel", 1)
    Math.sqrt(vx * vx + vy * vy) < @v_in

  # ---- tables ------------------------------------------------------------------

  -> postures_table
    return MyoRelocatePosturesV5.table if @tab5
    return MyoRelocatePostures.table if @t3_skip
    super

  -> postures_contractions
    return MyoRelocatePosturesV5.contractions if @tab5
    return MyoRelocatePostures.contractions if @t3_skip
    super

  -> ff_table
    return MyoRelocateFFV5.acts if @tab5
    return MyoRelocateFF.acts if @t3_skip
    super

  # Start blend (t_blend): the table's arm command eases in from the start
  # posture over the first t_blend seconds instead of stepping to the
  # table's own posture for the start palm (0.4-0.5 rad away in the
  # shoulder's elevation and rotation): the joint command and the arm
  # muscles' contraction offsets are w * table + (1 - w) * start, w the
  # min-jerk of t / t_blend.
  -> postures_at(tab, width, x, y, z)
    v = super(tab, width, x, y, z)
    return v if @w_blend >= ~1.0
    w = @w_blend
    if width == 7
      qs = @q_start
      return (0...7).map ->(k) qs[k] + w * (v[k] - qs[k])
    if width == @am.size
      cr = @cref
      return (0...width).map ->(i) cr[i] + w * (v[i] - cr[i])
    v

  # ---- resolved rate with phase damping ---------------------------------------

  # Task-space damping per phase: st_kd while settling, lf_kd while lifting
  # and carrying (carry5), rr_kd in reach / descend / close (round 4).
  -> damping_for(ph)
    return @st_kd if ph == "settle"
    return @lf_kd if ph == "lift" || ph == "carry"
    return @rr_kd if ph == "reach" || ph == "descend" || ph == "close"
    ~0.0

  -> add_resolved_rate(f, off)
    kd = damping_for(@phase)
    return super(f, off) if kd <= ~0.0 || (@phase != "settle" && @phase != "lift" && @phase != "carry")
    e = [~0.0, ~0.0, ~0.0]
    v = [~0.0, ~0.0, ~0.0]
    j = 0
    while j < 7
      qd = f.at("qd", @arm_j[j])
      v[0] += f.at("palm_jac", 3 * j) * qd
      v[1] += f.at("palm_jac", 3 * j + 1) * qd
      v[2] += f.at("palm_jac", 3 * j + 2) * qd
      j += 1
    vs = [~0.0, ~0.0, ~0.0]
    if @xs_prev != nil
      k = 0
      while k < 3
        vs[k] = (@xs[k] - @xs_prev[k]) / @dt
        k += 1
    @xs_prev = @xs.map ->(x) x
    k = 0
    while k < 3
      e[k] = @xs[k] - control_point(f, k)
      @rr_int[k] = clamp(@rr_int[k] + e[k] * @dt, ~-0.05, ~0.05)
      e[k] = @rr_kp * e[k] + @rr_ki * @rr_int[k] + kd * (vs[k] - v[k])
      k += 1
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
