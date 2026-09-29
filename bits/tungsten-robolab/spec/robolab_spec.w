# robolab SDK spec: easing, springs, contraction/pose mapping, reflexes,
# latches, and chunk sequencing driven by synthetic sensor frames.
#
#   bin/tungsten --release -o /tmp/robolab_spec bits/tungsten-robolab/spec/robolab_spec.w
#   /tmp/robolab_spec

use robolab/easing
use robolab/body
use robolab/contraction
use robolab/sensors
use robolab/latch
use robolab/chunk
use robolab/reflex
use robolab/controller
use robolab/link
use robolab/skill

+ Check
  -> new
    @passed = 0
    @failed = 0

  -> ok(label, cond)
    if cond
      @passed += 1
    else
      @failed += 1
      << "FAIL: [label]"

  -> near(label, actual, expected, tol = ~0.000001)
    ok(label + " (got [actual], want [expected])", (actual - expected).abs <= tol)

  -> finish
    << "[@passed] passed, [@failed] failed"
    exit(1) if @failed > 0

# One hinge (knee-like, range 0..2) driven by a pos/neg pair.
-> test_body
  b = Body.new
  b.add(Muscle.new(0, "knee_pos", "knee", 1, ~0.0, ~2.0, "knee"))
  b.add(Muscle.new(1, "knee_neg", "knee", -1, ~0.0, ~2.0, "knee"))
  b

+ ProbeSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("probe")
    bend = Pose.new
    bend.set("knee", ~1.5, ~0.0)
    straight = Pose.new
    straight.set("knee", ~0.5, ~0.0)
    mv.add(Chunk.new("bend", ~1.0).pose(bend))
    mv.add(Chunk.new("hold", ~0.2).pose(bend).hold_until(Latch.above("probe", 0, ~0.5)))
    mv.add(Chunk.new("straighten", ~0.5).pose(straight))
    ctl.add_track(Track.new("leg", mv, body.all))

check = Check.new

# Easing endpoints and the min-jerk profile.
check.near("min_jerk(0)", Easing.min_jerk(~0.0), ~0.0)
check.near("min_jerk(1)", Easing.min_jerk(~1.0), ~1.0)
check.near("min_jerk(0.5)", Easing.min_jerk(~0.5), ~0.5)
check.near("min_jerk_rate peak", Easing.min_jerk_rate(~0.5), ~1.875)
check.near("apply clamps", Easing.apply(:min_jerk, ~1.7), ~1.0)
check.near("cubic_in_out(0.25)", Easing.cubic_in_out(~0.25), ~0.0625)
check.near("sine_in_out(0.5)", Easing.sine_in_out(~0.5), ~0.5)

# A critically damped spring approaches without overshoot.
sp = SpringVector.new(1, ~0.2, ~1.0)
over = false
i = 0
while i < 400
  v = sp.step([~1.0], ~0.005)
  over = true if v[0] > ~1.0000001
  i += 1
check.ok("spring converges", (sp.value[0] - ~1.0).abs < ~0.001)
check.ok("critical spring never overshoots", !over)

# Contraction <-> angle for an antagonist pair.
b = test_body
check.near("pos contraction at q=0.5", b.muscle(0).contraction_at(~0.5), ~0.25)
check.near("neg contraction at q=0.5", b.muscle(1).contraction_at(~0.5), ~0.75)
check.near("angle from pos contraction", b.muscle(0).angle_at(~0.25), ~0.5)
pose = Pose.new
pose.set("knee", ~1.0, ~0.2)
c = pose.apply(b, Contraction.fill(2, ~0.0))
check.near("pose pos with co-contraction", c[0], ~0.6)
check.near("pose neg with co-contraction", c[1], ~0.6)
check.near("pose commands its angle", c.joint_angle(b, "knee"), ~1.0)
check.near("rate over time", Rate.new([~0.5, ~-0.5]).over(~0.4)[1], ~-0.2)

# Reflex: stretched muscle recruits, antagonist stays quiet, clamps at 1.
r = Reflex.new(2, ~6.0, ~0.25)
check.near("stretch reflex", r.activation(0, ~0.6, ~0.5, ~0.0, ~0.0, ~1.0), ~0.6)
check.near("shortened muscle silent", r.activation(1, ~0.4, ~0.5, ~0.0, ~0.0, ~1.0), ~0.0)
check.near("activation clamps", r.activation(0, ~1.0, ~0.0, ~0.0, ~0.0, ~1.0), ~1.0)
check.near("drive adds", r.activation(1, ~0.5, ~0.5, ~0.0, ~0.3, ~1.0), ~0.3)

# Controller: chunks ease, hold on a latch, then continue.
schema = Schema.new(2)
schema.add("probe", 1)
skill = ProbeSkill.new(b, {})
ctl = Controller.new(b, ~0.005, skill)
ctl.tick(Frame.new(schema, [~0.0, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.ok("starts in bend", ctl.label == "leg:bend")
ctl.tick(Frame.new(schema, [~0.5, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.near("halfway through bend (min-jerk 0.5)", ctl.command.joint_angle(b, "knee"), ~1.0, ~0.0001)
ctl.tick(Frame.new(schema, [~1.0, ~0.75, ~0.25, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.ok("bend done, now holding", ctl.label == "leg:hold")
ctl.tick(Frame.new(schema, [~1.5, ~0.75, ~0.25, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.ok("hold waits for its latch", ctl.label == "leg:hold")
ctl.tick(Frame.new(schema, [~1.6, ~0.75, ~0.25, ~0.0, ~0.0, ~0.0, ~0.0, ~0.9]))
check.ok("latch releases the hold", ctl.label == "leg:straighten")
acts = ctl.tick(Frame.new(schema, [~1.7, ~0.75, ~0.25, ~0.0, ~0.0, ~0.0, ~0.0, ~0.9]))
check.ok("straightening recruits the knee_neg muscle", acts[1] > acts[0])

# Geometry: a biarticular muscle whose length falls linearly with joint a
# (0.1 per rad) and rises with joint b (0.2 per rad); samples at 3 points.
gb = Body.new
gb.add(Muscle.new(0, "bi", "a", 1, ~0.0, ~1.0, "bi"))
geo = Geometry.new
geo.add_joint(0, "a", ~0.0, ~1.0, ~0.0, 3)
geo.add_joint(1, "b", ~0.0, ~2.0, ~0.0, 3)
geo.set_range(0, ~0.4, ~0.9, ~0.6)
geo.add_length(0, 0, [~0.6, ~0.55, ~0.5])
geo.add_length(0, 1, [~0.6, ~0.8, ~1.0])
gb.set_geometry(geo)
check.near("geometry length at reference", geo.length(0, [~0.0, ~0.0]), ~0.6)
check.near("geometry length is additive", geo.length(0, [~1.0, ~0.5]), ~0.6)
check.near("geometry contraction", geo.contraction(0, [~1.0, ~0.0]), ~0.8)
check.near("contraction slope on a", geo.contraction_slope(0, 0), ~0.2)
check.near("contraction slope on b", geo.contraction_slope(0, 1), ~-0.4)
gpose = Pose.new
gpose.set("a", ~1.0, ~0.1)
gc = gpose.apply(gb, Contraction.fill(1, ~0.0))
check.near("pose through geometry (b at reference) + stiffness", gc[0], ~0.85)
check.ok("geometry body has joint b", gb.has_joint?("b"))

# Branching and staggered timing.
+ BranchSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("branchy")
    bend = Pose.new
    bend.set("knee", ~1.5, ~0.0)
    mv.add(Chunk.new("a", ~0.1).pose(bend).branch(->(f, c) f.get("probe") > ~0.5 ? "c" : nil))
    mv.add(Chunk.new("b", ~0.1).pose(bend).followed_by("a"))
    straight = Pose.new
    straight.set("knee", ~0.5, ~0.0)
    mv.add(Chunk.new("c", ~1.0).pose(straight).stagger([0], ~0.5, :linear, ~0.5))
    ctl.add_track(Track.new("leg", mv, body.all))

bctl = Controller.new(b, ~0.005, BranchSkill.new(b, {}))
bctl.tick(Frame.new(schema, [~0.0, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
bctl.tick(Frame.new(schema, [~0.2, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.ok("no branch: falls through to b", bctl.label == "leg:b")
bctl.tick(Frame.new(schema, [~0.4, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
check.ok("followed_by returns to a", bctl.label == "leg:a")
bctl.tick(Frame.new(schema, [~0.6, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.9]))
check.ok("branch picks c", bctl.label == "leg:c")
start_pos = bctl.command[0]
bctl.tick(Frame.new(schema, [~0.9, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.9]))
check.near("staggered muscle waits for its delay", bctl.command[0], start_pos)
check.ok("unstaggered muscle already moving", bctl.command[1] > ~0.3)
bctl.tick(Frame.new(schema, [~1.35, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.9]))
check.near("staggered muscle halfway (linear)", bctl.command[0], start_pos + (~0.25 - start_pos) * ~0.5, ~0.001)
check.ok("staggered muscle had real distance to cover", start_pos > ~0.6)

# v2 registration order: the monoarticular pair is registered before the
# biarticulars that name the same primary joint, and stays the joint's pair.
vb = Body.new
vb.add(Muscle.new(0, "l_hip_flex_pos", "l_hip_flex", 1, ~-0.6, ~2.2, "hip"))
vb.add(Muscle.new(1, "l_hip_flex_neg", "l_hip_flex", -1, ~-0.6, ~2.2, "hip"))
vb.add(Muscle.new(2, "l_rf", "l_hip_flex", 1, ~-0.6, ~2.2, "rf"))
vb.add(Muscle.new(3, "l_ham", "l_hip_flex", -1, ~-0.6, ~2.2, "ham"))
check.ok("pair pos survives a biarticular", vb.pos_index("l_hip_flex") == 0)
check.ok("pair neg survives a biarticular", vb.neg_index("l_hip_flex") == 1)
check.ok("joint listed once", vb.joints.size == 1)

# Pair residual: a 2 x 2 grid over joints a and b (bilinear), zero at the
# reference corner, so the correction is the grid value itself.
geo.add_pair(0, 0, 1, 2, [~0.0, ~0.0, ~0.0, ~0.08])
check.near("pair residual at the far corner", geo.length(0, [~1.0, ~2.0]), ~0.6 - ~0.1 + ~0.4 + ~0.08)
check.near("pair residual bilinear midpoint", geo.length(0, [~0.5, ~1.0]), ~0.6 - ~0.05 + ~0.2 + ~0.02)
check.near("pair residual vanishes at reference", geo.length(0, [~0.0, ~0.0]), ~0.6)

# Reflex integral: accumulates the error, clamps, and is off by default.
ri = Reflex.new(2, ~6.0, ~0.25)
check.ok("integral off by default", !ri.integrating?)
check.near("no integral term without set_integral", ri.integral(0, ~0.6, ~0.5, ~0.01), ~0.0)
ri.set_integral([0], ~10.0, ~0.05)
check.near("integral after one step", ri.integral(0, ~0.6, ~0.5, ~0.1), ~0.1)
i = 0
while i < 20
  ri.integral(0, ~0.6, ~0.5, ~0.1)
  i += 1
check.near("integral clamps at the limit", ri.integral(0, ~0.6, ~0.5, ~0.1), ~0.5)

# Via-point chaining: a via chunk passes its goal with the Catmull-Rom
# velocity toward the next goal, and the next chunk starts with that velocity.
+ ViaSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("via")
    a = Pose.new
    a.set("knee", ~1.0, ~0.0)
    b2 = Pose.new
    b2.set("knee", ~1.8, ~0.0)
    mv.add(Chunk.new("up1", ~0.5).pose(a).via)
    mv.add(Chunk.new("up2", ~0.5).pose(b2))
    ctl.add_track(Track.new("leg", mv, body.all))

vctl = Controller.new(b, ~0.01, ViaSkill.new(b, {}))
vt = ~0.0
vprev = ~0.0
vmid = ~-1.0
vend = ~0.0
while vt < ~0.995
  vctl.tick(Frame.new(schema, [vt, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
  vcur = vctl.command.joint_angle(b, "knee")
  vmid = (vcur - vprev) / ~0.01 if vt > ~0.495 && vt < ~0.505
  vprev = vcur
  vt += ~0.01
check.ok("via chunk still moving at its keyframe (no stop)", vmid > ~0.5)
check.near("via chain arrives at the final goal", vctl.command.joint_angle(b, "knee"), ~1.8, ~0.02)

# The same with a keyframe off the control tick (0.503 s at 10 ms ticks): the
# handover happens at the keyframe, so no tick is truncated and the next chunk
# inherits the full velocity.
+ ViaOddSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("via_odd")
    a = Pose.new
    a.set("knee", ~1.0, ~0.0)
    b2 = Pose.new
    b2.set("knee", ~1.8, ~0.0)
    mv.add(Chunk.new("up1", ~0.503).pose(a).via)
    mv.add(Chunk.new("up2", ~0.5).pose(b2))
    ctl.add_track(Track.new("leg", mv, body.all))

octl = Controller.new(b, ~0.01, ViaOddSkill.new(b, {}))
ot = ~0.0
oprev = ~0.0
ovel = []
while ot < ~0.6
  octl.tick(Frame.new(schema, [ot, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
  ocur = octl.command.joint_angle(b, "knee")
  ovel.push((ocur - oprev) / ~0.01) if ot > ~0.455 && ot < ~0.555
  oprev = ocur
  ot += ~0.01
ojump = ~0.0
k = 1
while k < ovel.size
  dv = (ovel[k] - ovel[k - 1]).abs
  ojump = dv if dv > ojump
  k += 1
check.ok("via handover off the control tick keeps the velocity (max step [ojump])", ojump < ~0.15)

# Torque feed-forward (Controller#set_feedforward_torque): a flexor ("fl",
# length falling 0.1 per rad on joint a, peak force 100 N) and an extensor
# ("ex", rising 0.1 per rad); joint b is slaved to a (q_b = 0.5 q_a) and the
# flexor also shortens 0.1 per rad over b.
+ IdleSkill < Skill
  -> start(frame, ctl)

tb = Body.new
tb.add(Muscle.new(0, "fl", "a", 1, ~0.0, ~1.0, "a"))
tb.add(Muscle.new(1, "ex", "a", -1, ~0.0, ~1.0, "a"))
tgeo = Geometry.new
tgeo.add_joint(0, "a", ~0.0, ~1.0, ~0.0, 3)
tgeo.add_joint(1, "b", ~0.0, ~2.0, ~0.0, 3)
tgeo.set_range(0, ~0.3, ~0.9, ~0.6)
tgeo.set_range(1, ~0.3, ~0.9, ~0.6)
tgeo.add_length(0, 0, [~0.6, ~0.55, ~0.5])
tgeo.add_length(1, 0, [~0.6, ~0.65, ~0.7])
tgeo.add_length(0, 1, [~0.6, ~0.5, ~0.4])
tgeo.set_force(0, ~100.0)
tgeo.set_force(1, ~100.0)
tb.set_geometry(tgeo)
tschema = Schema.new(2)
tschema.add("q", 2)
tframe = Frame.new(tschema, [~0.0, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0, ~0.5, ~0.25])
tctl = Controller.new(tb, ~0.01, IdleSkill.new(tb, {}))
tctl.enable_feedforward([0, 1], ~0.0)
tctl.set_feedforward_torque([~5.0, ~0.0])
tacts = tctl.tick(tframe)
check.near("torque feed-forward drives the muscle that supplies it", tacts[0], ~0.5)
check.near("torque feed-forward leaves the antagonist", tacts[1], ~0.0)
tctl.set_feedforward_allocation([[0]], [[1, 0, ~0.5]])
tctl.set_feedforward_torque([~4.0, ~2.0])
tacts = tctl.tick(tframe)
check.near("allocation folds the slaved torque and uses the coupled arm", tacts[0], ~1.0 / ~3.0, ~0.0001)
check.near("allocation drops a muscle whose share is negative", tacts[1], ~0.0)

# Quintic keyframes (Chunk#knot). The basis: each h is zero at both ends,
# with a unit first (h1 at 0, h4 at 1) or second (h2 at 0, h3 at 1)
# derivative at its own end.
qe = ~0.0001
q0 = Quintic.basis(~0.0)
q1 = Quintic.basis(~1.0)
check.ok("quintic basis vanishes at both ends", q0.all? -> item == ~0.0)
check.ok("quintic basis vanishes at s = 1", q1.all? -> item.abs < ~0.000000000001)
check.near("h1'(0) = 1", Quintic.basis(qe)[0] / qe, ~1.0, ~0.001)
check.near("h4'(1) = 1", (~0.0 - Quintic.basis(~1.0 - qe)[3]) / qe, ~1.0, ~0.001)
check.near("h2''(0) = 1", ~2.0 * Quintic.basis(qe)[1] / (qe * qe), ~1.0, ~0.001)
check.near("h3''(1) = 1", ~2.0 * Quintic.basis(~1.0 - qe)[2] / (qe * qe), ~1.0, ~0.001)

# Two keyframe chunks: mode 0 plain min-jerk, mode 1 knots of zero vectors,
# mode 2 a knot of velocity 0.8 / s and acceleration 2 / s^2 at the first
# keyframe (knee_pos; the knee_neg muscle mirrors it).
+ KnotSkill < Skill
  -> start(frame, ctl)
    mode = @params["mode"]
    mv = Movement.new("knots")
    k1 = Chunk.new("k1", ~0.5).to([~0.6, ~0.4])
    k2 = Chunk.new("k2", ~0.5).to([~0.8, ~0.2])
    if mode > ~0.5 && mode < ~1.5
      k1.knot([~0.0, ~0.0], [~0.0, ~0.0])
      k2.knot([~0.0, ~0.0], [~0.0, ~0.0])
    if mode > ~1.5
      k1.knot([~0.8, ~-0.8], [~2.0, ~-2.0])
      k2.knot(nil)
    mv.add(k1)
    mv.add(k2)
    ctl.add_track(Track.new("leg", mv, body.all))

# Run a KnotSkill for 1 s at 1/64 s ticks (the keyframe falls on a tick);
# returns the knee_pos command at every tick.
-> knot_run(b, schema, mode)
  ps = {}
  ps["mode"] = mode
  kc = Controller.new(b, ~0.015625, KnotSkill.new(b, ps))
  out = []
  k = 0
  while k <= 64
    kc.tick(Frame.new(schema, [k * ~0.015625, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
    out.push(kc.command[0])
    k += 1
  out

kplain = knot_run(b, schema, ~0.0)
kzero = knot_run(b, schema, ~1.0)
kvel = knot_run(b, schema, ~2.0)
same = true
k = 0
while k < kplain.size
  same = false if kplain[k] != kzero[k]
  k += 1
check.ok("zero knots reproduce the min-jerk command exactly", same)
kdt = ~0.015625
check.near("knot chunk reaches its keyframe", kvel[32], ~0.6, ~0.000000001)
check.near("arrives at the knot velocity", (kvel[32] - kvel[31]) / kdt, ~0.8, ~0.05)
check.near("next segment leaves with it", (kvel[33] - kvel[32]) / kdt, ~0.8, ~0.05)
check.near("and with the knot acceleration", (kvel[33] - ~2.0 * kvel[32] + kvel[31]) / (kdt * kdt), ~2.0, ~0.3)
check.near("first knot chunk starts at rest", (kvel[1] - kvel[0]) / kdt, ~0.0, ~0.01)
check.near("the chain ends at the last goal", kvel[64], ~0.8, ~0.000000001)

# A run of via keyframes ending on a knot of prescribed velocity (a swing
# whose contact is planned): the knot chunk starts with the via chunk's
# velocity (the Catmull-Rom tangent, 0.3 / s here) instead of at rest,
# arrives at its knot velocity, and the next knot leaves with it.
+ ViaKnotSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("via_knot")
    mv.add(Chunk.new("v1", ~0.5).to([~0.6, ~0.4]).via)
    mv.add(Chunk.new("k1", ~0.5).to([~0.8, ~0.2]).knot([~1.2, ~-1.2]))
    mv.add(Chunk.new("k2", ~0.5).to([~0.9, ~0.1]).knot(nil))
    ctl.add_track(Track.new("leg", mv, body.all))

vkc = Controller.new(b, ~0.015625, ViaKnotSkill.new(b, {}))
vk = []
k = 0
while k <= 96
  vkc.tick(Frame.new(schema, [k * ~0.015625, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
  vk.push(vkc.command[0])
  k += 1
check.near("via -> knot: the knot chunk leaves with the via tangent", (vk[33] - vk[32]) / kdt, ~0.3, ~0.03)
check.near("via -> knot: no velocity step at the handover", (vk[33] - vk[32]) / kdt, (vk[32] - vk[31]) / kdt, ~0.03)
check.near("via -> knot: arrives at the knot", vk[64], ~0.8, ~0.000000001)
check.near("via -> knot: with the knot velocity", (vk[64] - vk[63]) / kdt, ~1.2, ~0.08)
check.near("via -> knot: the next knot leaves with it", (vk[65] - vk[64]) / kdt, ~1.2, ~0.08)
check.near("via -> knot: the chain ends at the last goal", vk[96], ~0.9, ~0.000000001)

# A knot that is also a via chunk, its keyframe off the control tick (0.503
# s at 10 ms ticks), hands over at the keyframe (as a via chunk does), so the
# knot velocity is not cut by a truncated tick; the next chunk, entered from
# a via chunk, is a plain Hermite that leaves with that velocity.
+ KnotOddSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("knot_odd")
    a = Pose.new
    a.set("knee", ~1.0, ~0.0)
    b2 = Pose.new
    b2.set("knee", ~1.8, ~0.0)
    mv.add(Chunk.new("k1", ~0.503).pose(a).knot([~1.5, ~-1.5]).via)
    mv.add(Chunk.new("up2", ~0.5).pose(b2))
    ctl.add_track(Track.new("leg", mv, body.all))

kctl = Controller.new(b, ~0.01, KnotOddSkill.new(b, {}))
kt = ~0.0
kprev = ~0.0
kvl = []
while kt < ~0.6
  kctl.tick(Frame.new(schema, [kt, ~0.25, ~0.75, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
  kcur = kctl.command.joint_angle(b, "knee")
  kvl.push((kcur - kprev) / ~0.01) if kt > ~0.455 && kt < ~0.555
  kprev = kcur
  kt += ~0.01
kjump = ~0.0
k = 1
while k < kvl.size
  dv = (kvl[k] - kvl[k - 1]).abs
  kjump = dv if dv > kjump
  k += 1
check.ok("knot + via off the control tick keeps its velocity (max step [kjump])", kjump < ~0.15)
check.ok("knot + via still moving through the keyframe", kvl.all? -> item > ~1.0)

# Reciprocal inhibition (opt-in, Controller#set_reciprocal): a driven muscle
# scales its antagonist's activation by 1 - k drive; off by default.
+ RecipSkill < Skill
  -> start(frame, ctl)

  -> before(frame, ctl)
    ctl.add_drive(0, ~0.6)
    ctl.add_offset(1, ~0.1)

rschema = Schema.new(2)
rctl = Controller.new(b, ~0.005, RecipSkill.new(b, {}))
ra = rctl.tick(Frame.new(rschema, [~0.0, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0]))
check.near("no reciprocal inhibition by default: antagonist's stretch reflex", ra[1], ~0.6)
rctl.set_reciprocal([[0, 1]], ~1.0)
ra = rctl.tick(Frame.new(rschema, [~0.005, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0]))
check.near("reciprocal inhibition scales the antagonist by 1 - k drive", ra[1], ~0.24)
check.near("reciprocal inhibition leaves the driven agonist", ra[0], ~0.6)

# Velocity-referenced damping (opt-in, Reflex#set_velocity_reference): a
# muscle damps its contraction velocity about w times its target's rate;
# off by default, where the target rate is ignored.
rv = Reflex.new(2, ~6.0, ~0.25)
check.ok("velocity reference off by default", !rv.referencing?)
check.near("plain damping ignores the target rate", rv.activation(0, ~0.6, ~0.5, ~0.4, ~0.0, ~1.0, ~0.4), ~0.5)
rv.set_velocity_reference([0], ~1.0)
check.ok("velocity reference on", rv.referencing?)
check.near("no damping at the commanded rate", rv.activation(0, ~0.6, ~0.5, ~0.4, ~0.0, ~1.0, ~0.4), ~0.6)
check.near("damping about the commanded rate", rv.activation(0, ~0.6, ~0.5, ~0.8, ~0.0, ~1.0, ~0.4), ~0.5)
check.near("muscles without a reference keep the plain damping", rv.activation(1, ~0.6, ~0.5, ~0.4, ~0.0, ~1.0, ~0.4), ~0.5)

# The controller passes each target's rate: a target rising 0.02 per 5 ms
# tick (4 /s), followed at that rate 0.1 behind, is not braked with the
# reference, and is braked to zero without it.
+ VrefSkill < Skill
  -> start(frame, ctl)
    @k = 0

  -> before(frame, ctl)
    @k += 1
    ctl.add_offset(0, ~0.02 * @k)

vschema = Schema.new(2)
plain = Controller.new(b, ~0.005, VrefSkill.new(b, {}))
refd = Controller.new(b, ~0.005, VrefSkill.new(b, {}))
refd.reflex.set_velocity_reference([0], ~1.0)
plain.tick(Frame.new(vschema, [~0.0, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0]))
refd.tick(Frame.new(vschema, [~0.0, ~0.5, ~0.5, ~0.0, ~0.0, ~0.0, ~0.0]))
pa = plain.tick(Frame.new(vschema, [~0.005, ~0.44, ~0.5, ~4.0, ~0.0, ~0.0, ~0.0]))
va = refd.tick(Frame.new(vschema, [~0.005, ~0.44, ~0.5, ~4.0, ~0.0, ~0.0, ~0.0]))
check.near("plain damping brakes a target moving at 4 /s", pa[0], ~0.0)
check.near("velocity reference tracks it (stretch term only)", va[0], ~0.6)
check.near("the unreferenced antagonist is unchanged", va[1], pa[1])

check.finish
