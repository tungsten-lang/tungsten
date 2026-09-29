# MyoChase: chase and tag the opponent in myoChallengeChaseTagP1-v0 (and
# P2) with the MyoWalk gait. The walking skill does all the body work; this
# skill only decides where to go, every tick, from the official
# observations (env_opponent_pose [x, y, angle] and env_opponent_vel
# [linear, angular], the same the challenge policy sees):
#
#   intercept   the opponent's motion is extrapolated with its own
#               kinematics (it moves backward along its local y axis at the
#               linear speed and turns at the angular speed, clipped to the
#               +-5.5 m field); the target is the first predicted point the
#               walker can reach, allowing for the time it needs to turn
#   heading     the walking skill steers toward it (stance-hip yaw servo,
#               swing-foot yaw); a target behind the walker gives the full
#               turn_max heading error, a tight turn
#   speed       v_chase, reduced in the last metre (v_close) so the final
#               steps stay balanced (the walking skill also slows, k_slow,
#               while the target is far off the heading: tighter turns)
#   walls       a target within `margin` of the out-of-bounds line (6.5 m)
#               is pulled inside it, and when the pelvis carried on by its
#               velocity for t_look seconds would cross that line the walker
#               heads for the arena centre instead
#   evade       in P2's EVADE episodes (env_task = 1) the target is a point 2 m
#               straight away from the chaser, kept 1 m inside the margin
#   settle      for the first t_settle seconds the initial heading is held
#               (the reset is mid-stride at 1.5 m/s; steering waits for the gait)
#   Dubins      a target inside the walker's turning circle (radius r_turn)
#               on its side cannot be reached by turning: walk on until it
#               is outside, then turn (no orbiting a close target)
#   turning     the commanded heading rotates toward the target bearing at
#               rate_cmd rad/s rather than jumping (the walking skill was
#               practised on rotating targets); the unlimited target bearing
#               goes to the walking skill as psi_goal, which its turning loop
#               (turn_gait = 1) aims at directly
#   evade_v2    (flag) EVADE picks, among 16 headings, the one that keeps the
#               chaser farthest after t_ev seconds, less wall and turn penalties

+ MyoChaseSkill < MyoWalkSkill
  -> read_params
    super
    @v_chase = param("v_chase", ~1.4, ~0.5, ~3.0)
    @v_close = param("v_close", ~1.0, ~0.3, ~3.0)
    @turn_rate = param("turn_rate", ~1.0, ~0.2, ~3.0)
    @margin = param("margin", ~0.6, ~0.0, ~1.5)
    @lead = param("lead", ~1.0, ~0.0, ~1.5)
    @t_settle = param("t_settle", ~0.6, ~0.0, ~2.0)
    @rate_cmd = param("rate_cmd", ~1.0, ~0.0, ~4.0)
    @r_turn = param("r_turn", ~0.0, ~0.0, ~5.0)
    @psi_cmd = nil
    @t_cmd = ~0.0
    @t_look = param("t_look", ~1.2, ~0.0, ~3.0)
    @psi0 = nil
    # EVADE planner (evade_v2 = 1; 0 keeps the point-2-m-away rule)
    @evade_v2 = ~0.0
    @evade_v2 = @params["evade_v2"] if @params.key?("evade_v2")
    @t_ev = param("t_ev", ~2.0, ~0.5, ~5.0)
    @w_wall = param("w_wall", ~3.0, ~0.0, ~10.0)
    @w_turn = param("w_turn", ~0.5, ~0.0, ~3.0)
    self

  # EVADE (evade_v2): among 16 headings, the one that leaves the chaser
  # farthest after t_ev seconds (the walker at v_chase along it, the chaser
  # closing at 1 m/s), less a penalty for ending past the margin and for
  # turning away from the current motion (turns are slow and risky here).
  -> evade_heading(px, py, ox, oy)
    best = @psi_m
    best_s = ~-1000000.0
    lim = ~6.5 - @margin
    k = 0
    while k < 16
      a = wrap(k * ~0.39269908169872414)
      qx = px + @v_chase * @t_ev * Math.cos(a)
      qy = py + @v_chase * @t_ev * Math.sin(a)
      dx = qx - ox
      dy = qy - oy
      d = Math.sqrt(dx * dx + dy * dy) - @t_ev
      wall = relu(qx.abs - lim) + relu(qy.abs - lim)
      sc = d - @w_wall * wall - @w_turn * wrap(a - @psi_m).abs
      if sc > best_s
        best_s = sc
        best = a
      k += 1
    best

  -> goal(f)
    px = f.at("pelvis_pos", 0)
    py = f.at("pelvis_pos", 1)
    ox = f.at("env_opponent_pose", 0)
    oy = f.at("env_opponent_pose", 1)
    th = f.at("env_opponent_pose", 2)
    lin = f.at("env_opponent_vel", 0).abs
    rot = f.at("env_opponent_vel", 1)
    v = @v_chase
    tx = ox
    ty = oy
    # EVADE (P2: the official task observation says so): run from the chaser
    evade = f.has?("env_task") && f.at("env_task", 0) > ~0.5
    # march the opponent forward in time until the walker can get there
    dt = ~0.05
    t = ~0.0
    found = evade
    while t < ~6.0 && !found
      dx = ox - px
      dy = oy - py
      d = Math.sqrt(dx * dx + dy * dy)
      turn = wrap(Math.atan2(dy, dx) - @psi).abs / @turn_rate
      reach = v * (t - turn)
      if reach >= d - ~0.3
        found = true
      else
        th = th + rot * dt
        ox = clamp(ox + lin * Math.sin(th) * dt, ~-5.5, ~5.5)
        oy = clamp(oy - lin * Math.cos(th) * dt, ~-5.5, ~5.5)
        t = t + dt
    # blend between the opponent now and the predicted meeting point
    tx = tx + (ox - tx) * @lead
    ty = ty + (oy - ty) * @lead
    lim = ~6.5 - @margin
    if evade
      # a point 2 m straight away from the chaser, kept inside the arena
      ax = px - ox
      ay = py - oy
      an = Math.sqrt(ax * ax + ay * ay) + ~0.001
      tx = clamp(px + ~2.0 * ax / an, ~1.0 - lim, lim - ~1.0)
      ty = clamp(py + ~2.0 * ay / an, ~1.0 - lim, lim - ~1.0)
    tx = clamp(tx, ~0.0 - lim, lim)
    ty = clamp(ty, ~0.0 - lim, lim)
    @psi_des = Math.atan2(ty - py, tx - px)
    return evade_goal(f, px, py) if evade && @evade_v2 > ~0.5
    # Dubins: a target inside the turning circle (radius r_turn) on its side
    # cannot be reached by turning toward it; walk on until it is outside
    if @r_turn > ~0.0
      hx = Math.cos(@psi_m)
      hy = Math.sin(@psi_m)
      side = ~1.0
      side = ~-1.0 if hx * (ty - py) - hy * (tx - px) < ~0.0
      cx = px - side * @r_turn * hy
      cy = py + side * @r_turn * hx
      @psi_des = @psi_m if (tx - cx) * (tx - cx) + (ty - cy) * (ty - cy) < @r_turn * @r_turn
    # walls: if the pelvis, carried on by its velocity for t_look seconds,
    # would cross the margin, head for the arena centre instead
    qx = px + f.at("com_vel", 0) * @t_look
    qy = py + f.at("com_vel", 1) * @t_look
    @psi_des = Math.atan2(~0.0 - py, ~0.0 - px) if qx.abs > lim || qy.abs > lim
    # the reset is mid-stride: hold the initial heading until the gait settles
    @psi0 = @psi if @psi0 == nil
    @psi_des = @psi0 if f.t < @t_settle
    # the target direction itself (the walking skill's turning loop, when
    # enabled, compares it with the direction of motion and aims at it)
    @psi_goal = @psi_des
    # the commanded heading turns toward the target at rate_cmd (rad/s; 0 = at
    # once), the way the walking skill was practised (rotating targets)
    if @rate_cmd > ~0.0
      @psi_cmd = @psi0 if @psi_cmd == nil
      step = @rate_cmd * (f.t - @t_cmd)
      @psi_cmd = wrap(@psi_cmd + clamp(wrap(@psi_des - @psi_cmd), ~0.0 - step, step))
      @psi_des = @psi_cmd
    @t_cmd = f.t
    dx = f.at("env_opponent_pose", 0) - px
    dy = f.at("env_opponent_pose", 1) - py
    @v_des = v
    @v_des = @v_close if dx * dx + dy * dy < ~1.0
    self

  -> evade_goal(f, px, py)
    @psi_des = evade_heading(px, py, f.at("env_opponent_pose", 0), f.at("env_opponent_pose", 1))
    @psi0 = @psi if @psi0 == nil
    @psi_des = @psi0 if f.t < @t_settle
    @psi_goal = @psi_des
    if @rate_cmd > ~0.0
      @psi_cmd = @psi0 if @psi_cmd == nil
      step = @rate_cmd * (f.t - @t_cmd)
      @psi_cmd = wrap(@psi_cmd + clamp(wrap(@psi_des - @psi_cmd), ~0.0 - step, step))
      @psi_des = @psi_cmd
    @t_cmd = f.t
    @v_des = @v_chase
    self
