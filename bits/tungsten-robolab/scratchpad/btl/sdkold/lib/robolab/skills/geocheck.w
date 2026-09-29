# GeoCheck: test skill for the Geometry model. Commands the reference posture
# with joint k offset by param "d<k>" radians and no co-contraction; the
# first tick's commanded contractions are the model's prediction, which the
# harness compares with exact MuJoCo muscle lengths.

+ GeoCheckSkill < Skill
  -> start(frame, ctl)
    g = body.geometry
    pose = Pose.new
    k = 0
    while k < g.joint_count
      pose.set(g.joint_names[k], g.qref(k) + param("d" + k.to_s, ~0.0, ~-3.0, ~3.0), ~0.0)
      k += 1
    mv = Movement.new("check")
    mv.add(Chunk.new("pose", ~0.0).pose(pose).hold_until(Latch.after(~100.0)))
    ctl.add_track(Track.new("all", mv, body.all))
