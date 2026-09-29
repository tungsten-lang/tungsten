# SearchBalance: quiet standing and push recovery on a MyoSuite body (the
# chase-tag myoLeg: 80 muscles, 14 leg joints), the benchmark skill for
# robolab's search methods (problem P2 in playground/SEARCH.md; task
# playground/tasks/search_balance.py).
#
# One chunk eases the commanded contraction vector from the measured one to
# the standing midpoint in 0.3 s and holds it; the reflexes (lambda model)
# make it an equilibrium, and spring-eased corrections close the balance
# loops every tick. The midpoint composes three layers, so each
# representation the search compares is a subset of the tunables (the rest
# stay at their defaults, zero offsets):
#
#   (a) hand-designed posture: hip, knee and ankle flexion, hip adduction
#       (stance width) and subtalar angle, the same on both legs
#   (b) joint space: dq_<joint>, a per-joint offset on each of the 14 joints
#       (7 per leg), the posture turned into contractions through Geometry
#   (c) contraction space: dc_<muscle>, a per-muscle offset added to the
#       contraction vector the posture gives (80 numbers)
#
# (a synergy basis, the fourth representation, lives on the Python side:
# playground/search.py maps a few synergy coefficients to the dc_ offsets.)
#
# Balance corrections (joint offsets through Geometry, eased by a
# critically damped spring of smooth time `spring`), in the heading frame
# (forward = the pelvis's forward axis, level; left = up x forward):
#
#   ankle strategy  COM ahead of its target d_ap in front of the heels, or
#                   moving forward: both ankles plantarflex (k_ap, k_apv)
#   hip strategy    trunk pitched forward or pitching: both hips extend
#                   (k_hp, k_hpv)
#   lateral         COM left of the heels' midpoint, or moving left: the left
#                   hip abducts and the right adducts, pushing the pelvis back
#                   right (k_ml, k_mlv)
#
# Stiffness: `stiff` co-contraction on every posed joint, reflex gains kp and
# kd on every muscle.

+ SearchBalanceSkill < Skill
  -> start(frame, ctl)
    g = body.geometry
    @stiff = param("stiff", ~0.06, ~0.0, ~0.3)
    kp = param("kp", ~8.0, ~2.0, ~20.0)
    kd = param("kd", ~0.3, ~0.0, ~1.5)
    ctl.reflex.set_gains(body.all, kp, kd)
    @k_ap = param("k_ap", ~2.0, ~0.0, ~8.0)
    @k_apv = param("k_apv", ~0.5, ~0.0, ~3.0)
    @d_ap = param("d_ap", ~0.1, ~0.0, ~0.2)
    @k_hp = param("k_hp", ~0.5, ~0.0, ~1.2)
    @k_hpv = param("k_hpv", ~0.1, ~0.0, ~0.5)
    @k_ml = param("k_ml", ~1.0, ~0.0, ~8.0)
    @k_mlv = param("k_mlv", ~0.3, ~0.0, ~3.0)
    spring = param("spring", ~0.06, ~0.02, ~0.2)

    # (a) the symmetric posture, defaults at the reference (start) posture
    hip = param("hip", ref("hip_flexion"), ~-0.2, ~0.8)
    knee = param("knee", ref("knee_angle"), ~0.0, ~1.2)
    ankle = param("ankle", ref("ankle_angle"), ~-0.3, ~0.5)
    add = param("add", ref("hip_adduction"), ~-0.3, ~0.2)
    sub = param("sub", ref("subtalar_angle"), ~-0.25, ~0.25)
    base = {}
    base["hip_flexion"] = hip
    base["hip_adduction"] = add
    base["hip_rotation"] = ref("hip_rotation")
    base["knee_angle"] = knee
    base["ankle_angle"] = ankle
    base["subtalar_angle"] = sub
    base["mtp_angle"] = ref("mtp_angle")
    # (b) per-joint offsets
    pose = Pose.new
    ["_r", "_l"].each ->(side)
      ["hip_flexion", "hip_adduction", "hip_rotation", "knee_angle", "ankle_angle", "subtalar_angle", "mtp_angle"].each ->(j)
        name = j + side
        q = base[j] + param("dq_" + name, ~0.0, ~-0.35, ~0.35)
        k = g.joint(name)
        q = clamp(q, g.qmin(k), g.qmax(k)) if k != nil
        pose.set(name, q, @stiff)
    goal = pose.apply(body, ctl.command)
    # (c) per-muscle offsets
    i = 0
    while i < body.size
      goal[i] = goal[i] + param("dc_" + body.muscle(i).name, ~0.0, ~-0.2, ~0.2)
      i += 1

    mv = Movement.new("balance")
    ch = Chunk.new("stand", ~0.3).to(goal).hold_until(Latch.after(~1000.0))
    ch.correct(->(f, c) balance(f), spring)
    mv.add(ch)
    ctl.add_track(Track.new("body", mv, body.all))

  # Reference angle of a joint (the right side's; the model is symmetric).
  -> ref(j)
    g = body.geometry
    g.qref(g.joint(j + "_r"))

  -> balance(f)
    fx = f.at("pelvis_fwd", 0)
    fy = f.at("pelvis_fwd", 1)
    norm = Math.sqrt(fx * fx + fy * fy)
    fx = fx / norm
    fy = fy / norm
    lx = ~0.0 - fy
    ly = fx
    hx = (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5
    hy = (f.at("l_foot_pos", 1) + f.at("r_foot_pos", 1)) * ~0.5
    dx = f.at("com_pos", 0) - hx
    dy = f.at("com_pos", 1) - hy
    vx = f.at("com_vel", 0)
    vy = f.at("com_vel", 1)
    e_ap = dx * fx + dy * fy - @d_ap
    e_ml = dx * lx + dy * ly
    v_ap = vx * fx + vy * fy
    v_ml = vx * lx + vy * ly
    ux = f.at("pelvis_up", 0)
    uy = f.at("pelvis_up", 1)
    uz = f.at("pelvis_up", 2)
    pitch = Math.atan2(ux * fx + uy * fy, uz)
    pitch_rate = f.at("torso_angvel", 0) * lx + f.at("torso_angvel", 1) * ly
    ank = ~0.0 - (@k_ap * e_ap + @k_apv * v_ap)
    hp = ~0.0 - (@k_hp * pitch + @k_hpv * pitch_rate)
    ml = @k_ml * e_ml + @k_mlv * v_ml
    off = zeros
    joint_offset(off, "ankle_angle_r", ank)
    joint_offset(off, "ankle_angle_l", ank)
    joint_offset(off, "hip_flexion_r", hp)
    joint_offset(off, "hip_flexion_l", hp)
    joint_offset(off, "hip_adduction_r", ml)
    joint_offset(off, "hip_adduction_l", ~0.0 - ml)
    off
