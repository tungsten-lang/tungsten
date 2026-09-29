# MyoHold: bring-up skill for MyoSuite bodies. Commands the body's reference
# posture (every joint the muscles cross) with a little co-contraction and
# holds it through the reflexes, with an ankle balance correction.

+ MyoHoldSkill < Skill
  -> start(frame, ctl)
    g = body.geometry
    stiff = param("stiff", ~0.04, ~0.0, ~0.3)
    kp = param("kp", ~6.0, ~1.0, ~20.0)
    kd = param("kd", ~0.25, ~0.0, ~2.0)
    ctl.reflex.set_gains(body.all, kp, kd)
    ff = param("ff", ~0.0, ~0.0, ~1.5)
    ctl.enable_feedforward(body.all, ff) if ff > ~0.0
    pose = Pose.new
    g.joint_names.each ->(name)
      j = g.joint(name)
      pose.set(name, g.qref(j), stiff)
    mv = Movement.new("hold")
    mv.add(Chunk.new("settle", ~0.3).pose(pose).hold_until(Latch.after(~100.0)))
    ctl.add_track(Track.new("body", mv, body.all))
