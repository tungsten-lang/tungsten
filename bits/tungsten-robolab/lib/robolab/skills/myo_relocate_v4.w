# MyoRelocateV4: round-4 placement for the relocate skill (MyoRelocateV3Skill
# with the resolved-rate servo), opt-in by params; with `drop_in` at 0 it is
# MyoRelocateV3Skill.
#
# Round-3 placements failed after good lifts in two ways (100 dev seeds of the
# round-4 champion: 30 lifted above the rim, not placed). The carry's servo
# lags the goal by 6-10 cm, so the carry chunk times out short of the box;
# the lower chunk then comes down wherever the hand is, onto or outside the
# wall, or the release comes too late to count 5 solved steps in 1.5 s.
#
#   drop_in  1: the hand opens on a latch, not a clock: in lift, carry or
#            lower, as soon as the held object is above `z_rel` and its
#            landing point lies within `r_in` of the receptacle's centre.
#            The released hand rises `rel_up` from where it let go instead
#            of following the object in.
#   hold_hi  1: lower keeps the carry height (it never comes down outside
#            the box; only the latch lets go); 0: lower eases down to z_low
#            as before and the latch only lets go earlier.
#   lead     how far the landing point leads the object: 0 tests where the
#            object is (a drop from over the opening); 1 the ballistic
#            landing point from its measured velocity (`obj_vel`), falling
#            to `z_land`, so a moving object is let go early and flies in
#            (a toss that saves the time the carry would take to stop).
#   y_far    far-side grasp: objects starting beyond y_far (the far edge of
#            the table, y < -0.3: 30% of episodes, lifted in 23% against 65%
#            elsewhere; the arm reaches them nearly straight and the servo
#            oscillates) get their own grasp settings, the `<name>_f`
#            twins of z_above, z_grasp, ox, oy, k_touch, r_reach, r_xy,
#            touch_th, servo_p, servo_i, rr_kp and rr_ki (defaults: the
#            near values). y_far defaults to -1 (no episode is far).
#   rr_kd    task-space damping in the resolved-rate correction: traced
#            failed grasps show the pinch point swinging +-9 cm at ~2.5 Hz
#            about its target while the posture-table command barely moves
#            (the reflexes and the resolved-rate term chase each other), so
#            the correction's task-space command becomes
#            rr_kp e + rr_ki int(e) + rr_kd (v* - v), v the palm velocity
#            from the Jacobian and the joint velocities, v* the eased
#            target's own velocity (0: the base correction). Grasp chunks
#            only (reach, descend, close): damping the loaded carry slows the
#            lift more than it steadies it.

+ MyoRelocateV4Skill < MyoRelocateV3Skill
  -> start(frame, ctl)
    @drop_in = param("drop_in", ~0.0, ~0.0, ~1.0) > ~0.5
    @z_rel = param("z_rel", ~1.12, ~1.0, ~1.3)
    @r_in = param("r_in", ~0.04, ~0.005, ~0.09)
    @lead = param("lead", ~0.0, ~0.0, ~1.2)
    @z_land = param("z_land", ~0.95, ~0.88, ~1.1)
    @rel_up = param("rel_up", ~0.03, ~-0.05, ~0.12)
    @hold_hi = param("hold_hi", ~0.0, ~0.0, ~1.0) > ~0.5
    @rel_p = [~0.0, ~0.0, ~0.0]
    @rr_kd = param("rr_kd", ~0.0, ~0.0, ~10.0)
    @xs_prev = nil
    super(frame, ctl)
    far_grasp(frame)

  # The base resolved-rate correction with the rr_kd damping term.
  -> add_resolved_rate(f, off)
    return super(f, off) if @rr_kd <= ~0.0 || (@phase != "reach" && @phase != "descend" && @phase != "close")
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
      e[k] = @rr_kp * e[k] + @rr_ki * @rr_int[k] + @rr_kd * (vs[k] - v[k])
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

  # The far-side grasp settings (declared on every episode, so a search sees
  # them; applied when the object starts beyond y_far).
  -> far_grasp(frame)
    y_far = param("y_far", ~-1.0, ~-1.0, ~-0.1)
    v = [param("z_above_f", @z_above, ~0.94, ~1.12), param("z_grasp_f", @z_grasp, ~0.9, ~0.98), param("ox_f", @ox, ~-0.05, ~0.05), param("oy_f", @oy, ~-0.05, ~0.05), param("k_touch_f", @k_touch, ~0.0, ~1.0), param("r_reach_f", @r_reach, ~0.005, ~0.08), param("r_xy_f", @r_xy, ~0.003, ~0.05), param("touch_th_f", @touch_th, ~0.05, ~5.0), param("servo_p_f", @kp_s, ~0.0, ~1.5), param("servo_i_f", @ki_s, ~0.0, ~30.0), param("rr_kp_f", @rr_kp, ~0.0, ~20.0), param("rr_ki_f", @rr_ki, ~0.0, ~60.0)]
    return nil if !frame.has?("env_obj_pos") || frame.at("env_obj_pos", 1) >= y_far
    @z_above = v[0]
    @z_grasp = v[1]
    @ox = v[2]
    @oy = v[3]
    @k_touch = v[4]
    @r_reach = v[5]
    @r_xy = v[6]
    @touch_th = v[7]
    @kp_s = v[8]
    @ki_s = v[9]
    @rr_kp = v[10]
    @rr_ki = v[11]
    nil

  -> enter_phase(f, name, duration)
    super(f, name, duration)
    if name == "release"
      k = 0
      while k < 3
        @rel_p[k] = f.at("env_palm_pos", k)
        k += 1
    nil

  -> after(f, ctl)
    super(f, ctl)
    return nil if !@drop_in
    return nil if @phase != "lift" && @phase != "carry" && @phase != "lower"
    ctl.track("arm").jump(ctl, f, "release") if drop_ready?(f)
    nil

  # The held object is above z_rel and lands within r_in of the centre.
  -> drop_ready?(f)
    z = f.at("env_obj_pos", 2)
    return false if z < @z_rel
    t = ~0.0
    if @lead > ~0.0
      vz = f.at("obj_vel", 2)
      h = z - @z_land
      h = ~0.0 if h < ~0.0
      t = (vz + Math.sqrt(vz * vz + ~19.62 * h)) / ~9.81
    dx = f.at("env_obj_pos", 0) + @lead * t * f.at("obj_vel", 0) - f.at("env_goal_pos", 0)
    dy = f.at("env_obj_pos", 1) + @lead * t * f.at("obj_vel", 1) - f.at("env_goal_pos", 1)
    Math.sqrt(dx * dx + dy * dy) < @r_in

  -> phase_goal(f)
    return super(f) if !@drop_in
    ph = @phase
    if ph == "lower" && @hold_hi
      return [f.at("env_goal_pos", 0) + @cx, f.at("env_goal_pos", 1) + @cy, @z_carry]
    if ph == "release"
      return [@rel_p[0], @rel_p[1], @rel_p[2] + @rel_up]
    super(f)
