# Stand: bring-up skill. Holds a standing posture with an ankle balance
# strategy, then loops a squat and an arm raise to exercise every chunk
# feature: pose goals, min-jerk easing, time latches, and a spring-eased
# real-time correction.

+ StandSkill < Skill
  -> start(frame, ctl)
    stiff = param("stiff", ~0.04, ~0.0, ~0.3)
    k_pos = param("balance_kp", ~2.0, ~0.0, ~6.0)
    k_vel = param("balance_kd", ~0.4, ~0.0, ~2.0)
    stand = stance_pose(~0.05, ~0.12, ~-0.05, stiff)
    squat = stance_pose(~0.9, ~1.2, ~-0.5, stiff)
    reach = stance_pose(~0.05, ~0.12, ~-0.05, stiff)
    reach.set("l_shoulder_flex", ~2.9, stiff)
    reach.set("r_shoulder_flex", ~2.9, stiff)
    squat.set("spine_flex", ~0.5, stiff)
    squat.set("l_shoulder_flex", ~1.6, stiff)
    squat.set("r_shoulder_flex", ~1.6, stiff)

    mv = Movement.new("stand")
    balance = ->(f, c) balance_offsets(f, k_pos, k_vel)
    mv.add(Chunk.new("settle", ~0.4).pose(stand).hold_until(Latch.after(~1.2)).correct(balance))
    mv.add(Chunk.new("squat_down", ~1.1).pose(squat).hold_until(Latch.after(~1.6)).correct(balance))
    mv.add(Chunk.new("squat_up", ~1.0).pose(stand).hold_until(Latch.after(~1.4)).correct(balance))
    mv.add(Chunk.new("reach_up", ~0.8).pose(reach).hold_until(Latch.after(~1.2)).correct(balance))
    mv.add(Chunk.new("arms_down", ~0.8).pose(stand).hold_until(Latch.after(~1.2)).correct(balance))
    mv.loop_from(1)
    ctl.add_track(Track.new("body", mv, body.all))

  -> stance_pose(hip, knee, ankle, stiff)
    p = Pose.new
    ["l_", "r_"].each ->
      s = item
      p.set(s + "hip_flex", hip, stiff)
      p.set(s + "knee", knee, stiff)
      p.set(s + "ankle", ankle, stiff)
      p.set(s + "shoulder_flex", ~0.1, stiff)
      p.set(s + "elbow", ~0.4, stiff)
    p.set("spine_flex", ~0.08, stiff)
    p

  # Ankle strategy: plantarflex when the centre of mass drifts ahead of the
  # feet, dorsiflex when it drifts behind.
  -> balance_offsets(f, k_pos, k_vel)
    feet = (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5 + ~0.05
    err = f.com_x - feet
    dq = k_pos * err + k_vel * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    off
