# MyoDie: MyoChallenge 2022 die reorientation (phase 2) on the myoHand, 39
# muscles. Turn the die in the upturned palm to a random goal orientation
# (each Euler angle uniform in +-180 deg) within 1.5 s.
#
# The rotation still to do arrives as a rotation vector in the palm frame
# (`rot_vec`: axis times angle). The chunks:
#
#   cup      the fingers curl into a cradle that centres the die
#
# Every chunk ends by branching on the rotation error: to the flip for the
# axis and sign with the largest component, if that component exceeds
# `flip_min`, else to `fine`.
#   flip_*   six coarse moves, a 90 deg roll the fingers or thumb can
#            give: +-x (tip across the palm), +-y (roll about the finger
#            axis), +-z (spin about the palm normal). Each is the cup plus
#            an amplitude vector over the 14 joint groups; LATCHED on the
#            die having turned `flip_done` about that axis (or a timeout)
#   fine     the cup plus a proportional correction: the rotation vector
#            through a 3 x 14 gain matrix to joint offsets, and the position
#            error through the wrist, eased in by the correction spring;
#            LATCHED on the error growing past `flip_min` again
#
# Joint groups: [deviation, flexion, cmc_abd, cmc_flex, mp, ip, mcp2, pip2,
# mcp3, pip3, mcp4, pip4, mcp5, pip5].

+ MyoDieSkill < Skill
  -> start(frame, ctl)
    @g = body.geometry
    @dt = ctl.dt
    ctl.reflex.set_gains(body.all, param("kp", ~8.0, ~1.0, ~40.0), param("kd", ~0.2, ~0.0, ~2.0))
    stiff = param("stiff", ~0.06, ~0.0, ~0.3)
    @names = ["dev", "flex", "cabd", "cflex", "mp", "ip", "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]
    cup = [param("cup_dev", ~0.1, ~-0.17, ~0.43), param("cup_flex", ~0.1, ~-0.78, ~0.78), param("cup_cabd", ~0.3, ~-0.5, ~0.78), param("cup_cflex", ~0.2, ~-0.78, ~0.7), param("cup_mp", ~0.2, ~-0.78, ~0.7), param("cup_ip", ~0.1, ~-1.3, ~0.43), param("cup_f2", ~0.4, ~0.0, ~1.5), param("cup_p2", ~0.4, ~0.0, ~1.5), param("cup_f3", ~0.4, ~0.0, ~1.5), param("cup_p3", ~0.4, ~0.0, ~1.5), param("cup_f4", ~0.4, ~0.0, ~1.5), param("cup_p4", ~0.4, ~0.0, ~1.5), param("cup_f5", ~0.5, ~0.0, ~1.5), param("cup_p5", ~0.5, ~0.0, ~1.5)]
    @cup = cup
    @stiff = stiff
    p_cup = posture(cup, stiff)
    @flip_min = param("flip_min", ~1.2, ~0.3, ~3.2)
    @flip_done = param("flip_done", ~1.2, ~0.3, ~1.6)
    t_flip = param("t_flip", ~0.15, ~0.05, ~0.5)
    to_flip = param("to_flip", ~0.35, ~0.1, ~0.8)
    t_cup = param("t_cup", ~0.15, ~0.02, ~0.5)
    # fine-correction gains: rotation vector component (x, y, z) -> joint group
    @gain = ["x", "y", "z"].map ->(ax) @names.map ->(n) param("k" + ax + "_" + n, ~0.0, ~-1.0, ~1.0)
    @kpos = [param("kpos_dev", ~0.0, ~-8.0, ~8.0), param("kpos_flex", ~0.0, ~-8.0, ~8.0)]
    @next = "fine"
    @axis = 0
    @sign = 1
    @turned = ~0.0
    @prev = nil
    mv = Movement.new("die")
    route = ->(f, c) choose(f)
    mv.add(Chunk.new("cup", t_cup).pose(p_cup).hold_until(Latch.after(t_cup)).branch(route))
    [["x", 0], ["y", 1], ["z", 2]].each ->(ax)
      [["p", 1], ["n", -1]].each ->(sg)
        name = "flip_" + ax[0] + sg[0]
        amp = @names.map ->(n) param(name + "_" + n, ~0.0, ~-0.8, ~0.8)
        state = (0...cup.size).map ->(i) cup[i] + amp[i]
        done = Latch.test("flipped", ->(f, e, c) @turned > @flip_done)
        mv.add(Chunk.new(name, t_flip).pose(posture(state, stiff)).hold_until(done.after_min(t_flip * ~0.5), to_flip).on_enter(->(f, c) start_flip(f)).branch(route))
    extra_primitives(mv, route, cup, stiff, t_flip, to_flip)
    big = Latch.test("big_error", ->(f, e, c) largest(f) > @flip_min)
    mv.add(Chunk.new("fine", ~0.1).pose(p_cup).hold_until(big.after_min(~0.1)).correct(->(f, c) fine_offsets(f), param("spring", ~0.05, ~0.01, ~0.3)).branch(route))
    ctl.add_track(Track.new("hand", mv, body.all))

  # Skills built on this one add primitive chunks here (routed by `route`).
  -> extra_primitives(mv, route, cup, stiff, t_flip, to_flip)
    nil

  # Hand posture from the 14 joint-group values; palm up.
  -> posture(v, stiff)
    p = Pose.new
    p.set("pro_sup", ~-1.5, stiff)
    p.set("deviation", clamp(v[0], ~-0.17, ~0.43), stiff)
    p.set("flexion", clamp(v[1], ~-0.78, ~0.78), stiff)
    p.set("cmc_abduction", clamp(v[2], ~-0.5, ~0.78), stiff)
    p.set("cmc_flexion", clamp(v[3], ~-0.78, ~0.7), stiff)
    p.set("mp_flexion", clamp(v[4], ~-0.78, ~0.7), stiff)
    p.set("ip_flexion", clamp(v[5], ~-1.3, ~0.43), stiff)
    k = 0
    while k < 4
      d = (k + 2).to_s
      p.set("mcp" + d + "_flexion", clamp(v[6 + 2 * k], ~0.0, ~1.57), stiff)
      p.set("pm" + d + "_flexion", clamp(v[7 + 2 * k], ~0.0, ~1.57), stiff)
      p.set("md" + d + "_flexion", clamp(v[7 + 2 * k] * ~0.7, ~0.0, ~1.57), stiff)
      k += 1
    p

  # Largest rotation-vector component (absolute), its axis and sign.
  -> largest(f)
    best = ~0.0
    k = 0
    while k < 3
      v = f.at("rot_vec", k)
      v = ~0.0 - v if v < ~0.0
      best = v if v > best
      k += 1
    best

  -> choose(f)
    best = ~0.0
    k = 0
    while k < 3
      v = f.at("rot_vec", k)
      a = v
      a = ~0.0 - v if v < ~0.0
      if a > best
        best = a
        @axis = k
        @sign = 1
        @sign = -1 if v < ~0.0
      k += 1
    @next = "fine"
    if best > @flip_min
      suffix = "p"
      suffix = "n" if @sign < 0
      @next = "flip_" + ["x", "y", "z"][@axis] + suffix
    @next

  -> start_flip(f)
    @turned = ~0.0
    @prev = f.vec("die_axes")
    nil

  # Track how far the die has turned about the flip axis since the flip
  # began (angle of the die's frame change, projected on the axis).
  -> before(f, ctl)
    return nil if @prev == nil
    cur = f.vec("die_axes")
    # small rotation between frames: w = 0.5 * sum_i (a_i x b_i)
    w = [~0.0, ~0.0, ~0.0]
    i = 0
    while i < 3
      ax = @prev[3 * i]
      ay = @prev[3 * i + 1]
      az = @prev[3 * i + 2]
      bx = cur[3 * i]
      by = cur[3 * i + 1]
      bz = cur[3 * i + 2]
      w[0] += ~0.5 * (ay * bz - az * by)
      w[1] += ~0.5 * (az * bx - ax * bz)
      w[2] += ~0.5 * (ax * by - ay * bx)
      i += 1
    @turned = @turned + w[@axis] * @sign
    @prev = cur
    nil

  # Fine correction: rotation vector and position error -> joint offsets,
  # as contraction offsets through the muscle geometry.
  -> fine_offsets(f)
    q = @g.reference_posture
    names = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion"]
    dq = (0...14).map ->(i) ~0.0
    ax = 0
    while ax < 3
      v = f.at("rot_vec", ax)
      i = 0
      while i < 14
        dq[i] = dq[i] + @gain[ax][i] * v
        i += 1
      ax += 1
    dq[0] = dq[0] + @kpos[0] * f.at("pos_loc", 0)
    dq[1] = dq[1] + @kpos[1] * f.at("pos_loc", 1)
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, names[i], dq[i])
      i += 1
    k = 0
    while k < 4
      d = (k + 2).to_s
      joint_offset(off, "mcp" + d + "_flexion", dq[6 + 2 * k])
      joint_offset(off, "pm" + d + "_flexion", dq[7 + 2 * k])
      joint_offset(off, "md" + d + "_flexion", dq[7 + 2 * k] * ~0.7)
      k += 1
    off
