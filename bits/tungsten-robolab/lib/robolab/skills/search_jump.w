# SearchJump: a standing broad jump on the planar muscle humanoid, the
# benchmark skill for robolab's search methods (problem P1 in
# playground/SEARCH.md; task playground/tasks/search_jump.py).
#
# Five chunks, every leg, arm and spine muscle moving at once:
#
#   set ──(0.4 s)──> crouch ──(duration)──> extend ──(both feet off)──>
#       flight ──(a foot touches)──> land (held)
#
#   crouch   the countermovement: hips, knees and ankles fold, arms swing back
#            (set and crouch carry an ankle-strategy balance correction)
#   extend   push-off: the legs extend under a feed-forward drive on the hip,
#            knee and ankle extensors while the arms swing forward and up
#   flight   tuck: the thighs come up and the shins forward for the landing
#   land     absorb: soft reflexes, hips and knees fold, the trunk leans in
#
# The motion of each chunk (six joints: hip, knee, ankle, spine, shoulder,
# elbow; left and right move together) is parametrised one of four ways,
# picked by the params-file setting `rep` (not a tunable):
#
#   rep 0  goal + duration: the chunk's end posture as joint angles
#   rep 1  joint rate + duration (the default): one rate per joint (rad/s);
#          the chunk's goal posture is the previous chunk's goal plus
#          rate * duration
#   rep 2  muscle rate + duration: a contraction rate per muscle (1/s), the
#          pos and neg muscle of a joint independent (so co-contraction can
#          change from chunk to chunk); the goal contraction vector is the
#          previous goal plus rate * duration
#   rep 3  per-group timing: rep 1's joint rates, but hips, knees, ankles
#          and the upper body (spine, shoulders, elbows) each run on their own
#          track, and each group's push-off has its own onset delay after the
#          crouch (extend_delay_<group>) and its own duration (extend_t_<group>),
#          so the extension can sequence proximal to distal. (A chunk has one
#          easing and one clock for all its muscles; tracks give each group
#          its own.)
#   rep 4  keyframes: each chunk's goal is a full per-muscle contraction
#          vector (<chunk>_c_<muscle>, all 22 muscles, left and right free),
#          eased from the previous keyframe over the chunk's duration
#   rep 5  keyframes at a speed: rep 4's contraction vectors, but each segment
#          has a speed (<chunk>_v, contraction per second) instead of a
#          duration: the segment lasts (largest contraction change from the
#          previous planned keyframe) / speed
#
# The rates integrate from the previous chunk's planned goal rather than the
# live command (which is what Chunk#rate does): the two agree whenever the
# previous chunk ran its full duration, and this way a latch that cuts a
# chunk short (the take-off, the touchdown) does not shift every later goal.
# So the representations differ only as parametrisations: the rate defaults
# are the goal defaults' average velocities, the delays default to zero, and
# all four start from the same jump. The goal boxes are the joint ranges; the
# rate boxes let a chunk of default duration sweep a joint's whole range (a
# muscle's whole contraction range).
#
# `loop` 1 (params-file) repeats crouch -> extend -> flight -> land after
# each landing (held land_hold s) as a gait of consecutive jumps; in rep 5 a
# looped crouch keeps the first crouch's duration.
#
# `ease` (params-file) picks one easing for every chunk (an index into
# @eases, 0 = min_jerk); `ease_search` 1 makes each chunk's easing a tunable
# instead (a categorical: the floor of a real in [0, 8)).
#
# Feedback (params-file switches, all off by default; each declares its own
# tunables only when on, so every run without them replays exactly):
#
#   fb_push 1   take-off latched on sensed state: the push-off starts when the
#               COM has sunk below push_z (the depth of the countermovement)
#               once push_min of the crouch has passed, or push_late s after
#               the crouch's duration at the latest, instead of on the clock
#   fb_takeoff 1  take-off latched on the COM as well as the feet: the flight
#               (tuck) starts when both feet are off or, whichever is first,
#               when the COM has risen above to_z still moving up, so a toe
#               that lingers or chatters on the floor does not delay the tuck
#   fb_touch 1  the landing latch needs the COM low (below td_z) and falling:
#               a foot scuffing the floor early in the flight no longer
#               starts the landing posture in mid-air
#   fb_flight 1 flight correction: hips (leg reach) and shoulders servo the
#               trunk pitch toward fl_pitch (and its rate toward zero), the
#               legs reach further for a faster take-off (k_fv per m/s over
#               fl_vx)
#   fb_land 1   landing correction (a critically damped spring, land_spring
#               s): from the capture point (COM + vx / omega) relative to the
#               feet's centre (d_land ahead of the ankles) the ankles, hips,
#               knees and arms bring the COM over the feet, the way a person
#               reaches the arms forward and pitches the trunk to not sit
#               back; the hips also servo the trunk pitch toward p_land; the
#               leg pairs co-contract by land_cc (a stiffer landing)
#   fb_stand 1  after stand_after s of landing, rise to a balanced crouch
#               (stand_* posture, reflex gain stand_gain) with the landing
#               correction still on; needs fb_land
#
# Convolutional keyframe policy (P6 in SEARCH.md; params-file switches, off
# by default, declared after every other tunable):
#
#   kf_knots 1  (rep 4) quintic Hermite keyframes: the crouch, extend and
#               flight keyframes also carry an end velocity
#               (<chunk>_v_<muscle>, contraction per second) and acceleration
#               (<chunk>_a_<muscle>, per second squared), which the next
#               keyframe chunk starts from (Chunk#knot); zero knots are the
#               min-jerk keyframes exactly
#   tcn 1       a residual causal TCN (ConvPolicy, lib/robolab/tcn.w) reads
#               a ~0.2 s window of proprioception and adds a correction to
#               every muscle's command each tick, under the latches and over
#               the reflexes; its weights are the params file's tcn_* lines,
#               and a zero last layer adds exactly nothing

+ SearchJumpSkill < Skill
  -> start(frame, ctl)
    @rep = ~1.0
    @rep = @params["rep"] if @params.key?("rep")
    @ease0 = ~0.0
    @ease0 = @params["ease"] if @params.key?("ease")
    @ease_search = false
    @ease_search = @params["ease_search"] > ~0.5 if @params.key?("ease_search")
    @loop = false
    @loop = @params["loop"] > ~0.5 if @params.key?("loop")
    @fb_push = switch("fb_push")
    @fb_takeoff = switch("fb_takeoff")
    @fb_touch = switch("fb_touch")
    @fb_flight = switch("fb_flight")
    @fb_land = switch("fb_land")
    @fb_stand = @fb_land && !@loop && switch("fb_stand")
    @kf_knots = @rep > ~3.5 && @rep < ~4.5 && switch("kf_knots")
    @eases = [:min_jerk, :linear, :sine_in_out, :cubic_in, :cubic_out, :quint_in, :expo_in, :step]
    @joints = ["hip_flex", "knee", "ankle", "spine_flex", "shoulder_flex", "elbow"]
    @stiff = param("stiff", ~0.08, ~0.0, ~0.3)
    kp = param("kp", ~6.0, ~2.0, ~14.0)
    kd = param("kd", ~0.25, ~0.05, ~0.8)
    ctl.reflex.set_gains(body.all, kp, kd)
    @g_ext = param("g_ext", ~1.0, ~0.3, ~2.0)
    @g_land = param("g_land", ~0.6, ~0.2, ~1.5)
    drv_hip = param("drv_hip", ~0.6, ~0.0, ~1.0)
    drv_knee = param("drv_knee", ~0.5, ~0.0, ~1.0)
    drv_ankle = param("drv_ankle", ~0.5, ~0.0, ~1.0)
    drv_arm = param("drv_arm", ~0.3, ~0.0, ~1.0)
    @drive = drive_vec(drv_hip, drv_knee, drv_ankle, drv_arm)
    @k_bal = param("k_bal", ~2.0, ~0.0, ~6.0)
    @kd_bal = param("kd_bal", ~0.4, ~0.0, ~2.0)
    @d_bal = param("d_bal", ~0.14, ~-0.05, ~0.25)

    stand = [~0.05, ~0.12, ~-0.05, ~0.08, ~0.1, ~0.4]
    crouch = [~1.1, ~1.5, ~-0.45, ~0.45, ~-0.8, ~0.2]
    extend = [~0.7, ~0.0, ~0.8, ~0.4, ~2.2, ~0.2]
    flight = [~1.5, ~1.7, ~0.0, ~0.5, ~1.2, ~0.4]
    land = [~1.3, ~1.5, ~-0.35, ~0.7, ~1.4, ~0.4]

    # joint groups: one track for every muscle, or (rep 3) one per group
    @groups = [["hip_flex", "knee", "ankle", "spine_flex", "shoulder_flex", "elbow"]]
    @group_names = ["body"]
    if @rep > ~2.5 && @rep < ~3.5
      @groups = [["hip_flex"], ["knee"], ["ankle"], ["spine_flex", "shoulder_flex", "elbow"]]
      @group_names = ["hip", "knee", "ankle", "upper"]
    t_crouch = ~0.5
    t_flight = ~0.3
    t_land = ~0.15
    t_ext = []
    delay = []
    g_crouch = nil
    g_extend = nil
    g_flight = nil
    g_land = nil
    if @rep > ~3.5
      kf = keyframes(stand, [crouch, extend, flight, land], ["crouch", "extend", "flight", "land"])
      gs = kf[0]
      ts = kf[1]
      t_crouch = ts[0]
      t_ext.push(ts[1])
      delay.push(~0.0)
      t_flight = ts[2]
      t_land = ts[3]
      g_crouch = gs[0]
      g_extend = gs[1]
      g_flight = gs[2]
      g_land = gs[3]
    else
      t_crouch = param("crouch_t", ~0.5, ~0.2, ~1.0)
      t_flight = param("flight_t", ~0.3, ~0.1, ~0.6)
      t_land = param("land_t", ~0.15, ~0.05, ~0.4)
      tj_ext = @joints.map -> ~0.22
      gi = 0
      while gi < @groups.size
        if @rep > ~2.5
          te = param("extend_t_" + @group_names[gi], ~0.22, ~0.08, ~0.5)
          delay.push(param("extend_delay_" + @group_names[gi], ~0.0, ~0.0, ~0.2))
        else
          te = param("extend_t", ~0.22, ~0.08, ~0.5)
          delay.push(~0.0)
        t_ext.push(te)
        ji = 0
        while ji < @joints.size
          tj_ext[ji] = te if @groups[gi].include?(@joints[ji])
          ji += 1
        gi += 1

      # the planned goal of the previous chunk (angles for rep 0/1/3, a
      # contraction vector for rep 2), which the rate representations integrate
      @plan_q = stand
      @plan_c = posture(stand).apply(body, Contraction.fill(body.size, ~0.5))
      g_crouch = plan("crouch", crouch, stand, ~0.5, same(t_crouch))
      g_extend = plan("extend", extend, crouch, ~0.22, tj_ext)
      g_flight = plan("flight", flight, extend, ~0.3, same(t_flight))
      g_land = plan("land", land, flight, ~0.15, same(t_land))
    hold = ~100.0
    hold = t_land + param("land_hold", ~0.3, ~0.05, ~1.0) if @loop
    feedback_tunables
    hold = @stand_after if @fb_stand
    knot_tunables if @kf_knots
    @tcn = nil
    @tcn = ConvPolicy.new(body, @params, body.all) if switch("tcn")

    gi = 0
    while gi < @groups.size
      mv = Movement.new(@group_names[gi])
      bal = ->(f, c) balance(f)
      mv.add(Chunk.new("set", ~0.3).pose(posture(stand)).hold_until(Latch.after(~0.4)).correct(bal))
      c1 = motion("crouch", g_crouch, t_crouch)
      c1.knot(@knot_v[0], @knot_a[0]) if @kf_knots
      cue = Latch.after(t_crouch + delay[gi])
      cue = push_latch(t_crouch + delay[gi]) if @fb_push
      mv.add(c1.hold_until(cue).correct(bal))
      c2 = motion("extend", g_extend, t_ext[gi])
      c2.knot(@knot_v[1], @knot_a[1]) if @kf_knots
      off = Latch.all([Latch.release("l_foot"), Latch.release("r_foot")])
      off = Latch.any([off, Latch.test("launched", ->(f, e, c) launched?(f))]) if @fb_takeoff
      c2.hold_until(off.after_min(~0.05), ~0.8)
      mv.add(c2.drive(@drive).gain(@g_ext))
      c3 = motion("flight", g_flight, t_flight)
      c3.knot(@knot_v[2], @knot_a[2]) if @kf_knots
      touch = Latch.any([Latch.contact("l_foot"), Latch.contact("r_foot")])
      touch = Latch.all([touch, Latch.test("low", ->(f, e, c) falling_low?(f))]) if @fb_touch
      c3.correct(->(f, c) flight_correction(f)) if @fb_flight
      mv.add(c3.hold_until(touch.after_min(~0.08), ~1.2))
      c4 = motion("land", g_land, t_land)
      c4.knot(nil) if @kf_knots
      c4.correct(->(f, c) land_correction(f), @land_spring) if @fb_land
      mv.add(c4.gain(@g_land).hold_until(Latch.after(hold)))
      if @fb_stand
        c5 = Chunk.new("stand", @stand_t).pose(posture(@stand_q)).gain(@stand_gain)
        mv.add(c5.hold_until(Latch.after(~100.0)).correct(->(f, c) land_correction(f), @land_spring))
      mv.loop_from(1) if @loop
      ctl.add_track(Track.new(@group_names[gi], mv, group_mask(gi)))
      gi += 1

  # The convolutional policy's correction (tcn 1), after the tracks.
  -> after(frame, ctl)
    @tcn.apply(frame, ctl) if @tcn != nil

  -> same(t)
    @joints.map -> t

  # Names of the body joints a jump joint drives (the spine is unpaired).
  -> sided(j)
    return [j] if j == "spine_flex"
    ["l_" + j, "r_" + j]

  -> group_mask(gi)
    return body.all if @groups.size == 1
    prefixes = []
    @groups[gi].each ->(j)
      sided(j).each ->(name) prefixes.push(name)
    body.mask(prefixes)

  -> span(j)
    m = body.muscle(body.pos_index(sided(j)[0]))
    m.qmax - m.qmin

  -> qlo(j)
    body.muscle(body.pos_index(sided(j)[0])).qmin

  -> qhi(j)
    body.muscle(body.pos_index(sided(j)[0])).qmax

  -> posture(q)
    p = Pose.new
    i = 0
    while i < @joints.size
      sided(@joints[i]).each ->(name) p.set(name, q[i], @stiff)
      i += 1
    p

  # The goal of chunk `nm`, whose default is to move from the posture `prev`
  # to the posture `goal` in `dur` seconds, in the representation `rep`
  # picks: joint angles (rep 0, 1, 3) or a contraction vector (rep 2). `tj`
  # holds each joint's actual duration (the rates integrate over it). Updates
  # the planned goal the next chunk integrates from.
  -> plan(nm, goal, prev, dur, tj)
    if @rep > ~1.5 && @rep < ~2.5
      c = @plan_c.copy
      i = 0
      while i < @joints.size
        j = @joints[i]
        w = (goal[i] - prev[i]) / dur / span(j)
        rp = param(nm + "_r_" + j + "_pos", w, ~-1.0 / dur, ~1.0 / dur)
        rn = param(nm + "_r_" + j + "_neg", ~0.0 - w, ~-1.0 / dur, ~1.0 / dur)
        t = tj[i]
        sided(j).each ->(name)
          c[body.pos_index(name)] = c[body.pos_index(name)] + rp * t
          c[body.neg_index(name)] = c[body.neg_index(name)] + rn * t
        i += 1
      @plan_c = c
      return c
    q = []
    i = 0
    while i < @joints.size
      j = @joints[i]
      if @rep < ~0.5
        q.push(param(nm + "_" + j, goal[i], qlo(j), qhi(j)))
      else
        s = span(j)
        w = param(nm + "_w_" + j, (goal[i] - prev[i]) / dur, ~0.0 - s / dur, s / dur)
        q.push(@plan_q[i] + w * tj[i])
      i += 1
    @plan_q = q
    q

  -> motion(nm, g, t)
    ch = Chunk.new(nm, t)
    ch.ease(easing(nm))
    return ch.to(g) if @rep > ~1.5 && @rep < ~2.5
    return ch.to(g) if @rep > ~3.5
    ch.pose(posture(g))

  # Keyframes (rep 4, 5): each chunk's goal is a full per-muscle contraction
  # vector, defaulting to the contraction the default posture gives; rep 4
  # gives each segment a duration, rep 5 a speed. Returns [goals, durations].
  -> keyframes(stand, goals, names)
    durs = [~0.5, ~0.22, ~0.3, ~0.15]
    dlo = [~0.2, ~0.08, ~0.1, ~0.05]
    dhi = [~1.0, ~0.5, ~0.6, ~0.4]
    base = Contraction.fill(body.size, ~0.5)
    prev0 = posture(stand).apply(body, base)
    prev = prev0.copy
    cs = []
    ts = []
    k = 0
    while k < goals.size
      nm = names[k]
      c0 = posture(goals[k]).apply(body, base)
      c = c0.copy
      i = 0
      while i < body.size
        c[i] = param(nm + "_c_" + body.muscle(i).name, c0[i], ~-0.05, ~1.15)
        i += 1
      t = durs[k]
      if @rep < ~4.5
        t = param(nm + "_t", durs[k], dlo[k], dhi[k])
      else
        v = param(nm + "_v", excursion(c0, prev0) / durs[k], ~0.3, ~12.0)
        t = clamp(excursion(c, prev) / v, ~0.03, ~1.5)
      cs.push(c)
      ts.push(t)
      prev0 = c0
      prev = c
      k += 1
    [cs, ts]

  # Largest per-muscle contraction change between two vectors.
  -> excursion(a, b)
    m = ~0.0
    i = 0
    while i < a.size
      d = (a[i] - b[i]).abs
      m = d if d > m
      i += 1
    m

  -> easing(nm)
    v = @ease0
    v = param(nm + "_ease", @ease0 + ~0.5, ~0.0, ~7.999) if @ease_search
    k = v.floor
    k = 0 if k < 0
    k = 7 if k > 7
    @eases[k]

  # Ankle strategy while standing and crouching (as in StandSkill): the
  # ankles plantarflex when the COM drifts ahead of its target d_bal in front
  # of the ankles and dorsiflex when it falls behind.
  -> balance(f)
    feet = (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5 + @d_bal
    dq = @k_bal * (f.com_x - feet) + @kd_bal * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    off

  # Push-off burst: hip extensors (hip_flex_neg), knee extensors (knee_neg),
  # plantarflexors (ankle_pos) and the arm swing (shoulder_flex_pos).
  -> drive_vec(hip, knee, ankle, arm)
    d = zeros
    ["l_", "r_"].each ->(s)
      d[body.index(s + "hip_flex_neg")] = hip
      d[body.index(s + "knee_neg")] = knee
      d[body.index(s + "ankle_pos")] = ankle
      d[body.index(s + "shoulder_flex_pos")] = arm
    d

  # ---- feedback (opt-in; see the header) ------------------------------------

  -> switch(name)
    return false if !@params.key?(name)
    @params[name] > ~0.5

  # Tunables of the switched-on feedback, declared after every other tunable
  # (a run without feedback declares exactly the tunables it always did).
  -> feedback_tunables
    if @fb_push
      @push_z = param("push_z", ~0.7, ~0.45, ~0.95)
      @push_min = param("push_min", ~0.6, ~0.0, ~1.0)
      @push_late = param("push_late", ~0.1, ~0.0, ~0.4)
    if @fb_takeoff
      @to_z = param("to_z", ~0.93, ~0.7, ~1.1)
    if @fb_touch
      @td_z = param("td_z", ~0.8, ~0.45, ~1.05)
    if @fb_flight
      @fl_pitch = param("fl_pitch", ~0.8, ~-0.5, ~2.0)
      @k_fp = param("k_fp", ~0.0, ~-2.0, ~2.0)
      @kd_fp = param("kd_fp", ~0.0, ~-0.5, ~0.5)
      @k_farm = param("k_farm", ~0.0, ~-2.0, ~2.0)
      @fl_vx = param("fl_vx", ~1.9, ~0.5, ~3.0)
      @k_fv = param("k_fv", ~0.0, ~-1.5, ~1.5)
    if @fb_land
      @land_spring = param("land_spring", ~0.08, ~0.02, ~0.3)
      @d_land = param("d_land", ~0.06, ~-0.1, ~0.25)
      @k_la = param("k_la", ~1.5, ~-1.0, ~5.0)
      @k_lh = param("k_lh", ~1.5, ~-1.0, ~5.0)
      @k_lk = param("k_lk", ~0.0, ~-3.0, ~3.0)
      @k_ls = param("k_ls", ~0.0, ~-2.0, ~3.0)
      @k_larm = param("k_larm", ~2.0, ~-1.0, ~5.0)
      @p_land = param("p_land", ~1.0, ~0.0, ~2.0)
      @k_lp = param("k_lp", ~0.0, ~-1.0, ~2.0)
      @kd_lp = param("kd_lp", ~0.0, ~-0.3, ~0.5)
      @land_cc = param("land_cc", ~0.0, ~0.0, ~0.3)
    if @fb_stand
      @stand_after = param("stand_after", ~0.5, ~0.1, ~1.5)
      @stand_t = param("stand_t", ~0.6, ~0.2, ~1.5)
      @stand_gain = param("stand_gain", ~0.8, ~0.2, ~2.0)
      sq = [~1.0, ~1.2, ~-0.4, ~0.5, ~1.2, ~0.4]
      @stand_q = []
      i = 0
      while i < @joints.size
        j = @joints[i]
        @stand_q.push(param("stand_" + j, sq[i], qlo(j), qhi(j)))
        i += 1

  # Quintic knots (kf_knots): the end velocity and acceleration of the
  # crouch, extend and flight keyframes, per muscle. The land keyframe, held
  # to the end, keeps a zero knot (it starts from the flight's).
  -> knot_tunables
    @knot_v = []
    @knot_a = []
    ["crouch", "extend", "flight"].each ->(nm)
      v = zeros
      a = zeros
      i = 0
      while i < body.size
        v[i] = param(nm + "_v_" + body.muscle(i).name, ~0.0, ~-10.0, ~10.0)
        i += 1
      i = 0
      while i < body.size
        a[i] = param(nm + "_a_" + body.muscle(i).name, ~0.0, ~-400.0, ~400.0)
        i += 1
      @knot_v.push(v)
      @knot_a.push(a)
    self

  # Take-off latch: push off at the bottom of the countermovement as sensed
  # (the COM below push_z), not after a fixed time; `t` is the crouch's
  # clock time, which still bounds it (push_late s later at the latest).
  -> push_latch(t)
    deep = Latch.test("deep", ->(f, e, c) f.at("com_pos", 2) < @push_z)
    Latch.any([Latch.after(t + @push_late), deep.after_min(t * @push_min)])

  -> launched?(f)
    f.at("com_pos", 2) > @to_z && f.at("com_vel", 2) > ~0.0

  -> falling_low?(f)
    f.at("com_pos", 2) < @td_z && f.at("com_vel", 2) < ~0.0

  # Flight: angular momentum is fixed once airborne, so the trunk's pitch is
  # steered by moving the legs and arms against it (hip extension and a
  # backward arm swing pitch the trunk back); a faster take-off reaches the
  # feet further forward.
  -> flight_correction(f)
    u = @k_fp * (f.torso_pitch - @fl_pitch) + @kd_fp * f.torso_pitch_rate
    reach = clamp(@k_fv * (f.com_vx - @fl_vx), ~-0.6, ~0.6)
    hip = clamp(reach - u, ~-1.0, ~1.0)
    knee = ~0.0 - reach
    arm = clamp(~0.0 - @k_farm * u, ~-1.5, ~1.5)
    off = zeros
    ["l_", "r_"].each ->(s)
      joint_offset(off, s + "hip_flex", hip)
      joint_offset(off, s + "knee", knee)
      joint_offset(off, s + "shoulder_flex", arm)
    off

  # Landing: the capture point (COM + vx / omega, omega = sqrt(g / z)) against
  # the feet's centre. Behind the feet: dorsiflex the ankles, flex the hips
  # and spine (trunk forward) and throw the arms forward; ahead: the reverse,
  # except the arms (swung back from a crouch they reach the floor). The hips
  # also hold the trunk pitch near p_land.
  -> land_correction(f)
    z = f.at("com_pos", 2)
    z = ~0.3 if z < ~0.3
    feet = (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5 + @d_land
    e = f.com_x - feet + f.com_vx * Math.sqrt(z / ~9.81)
    tip = f.torso_pitch - @p_land
    ank = clamp(@k_la * e, ~-0.6, ~0.6)
    hip = clamp(~0.0 - @k_lh * e - @k_lp * tip - @kd_lp * f.torso_pitch_rate, ~-1.0, ~1.0)
    knee = clamp(@k_lk * e, ~-0.8, ~0.8)
    arm = clamp(~0.0 - @k_larm * e, ~0.0, ~1.5)
    spine = clamp(~0.0 - @k_ls * e, ~-0.6, ~0.6)
    off = zeros
    ["l_", "r_"].each ->(s)
      joint_offset(off, s + "ankle", ank)
      joint_offset(off, s + "hip_flex", hip)
      joint_offset(off, s + "knee", knee)
      joint_offset(off, s + "shoulder_flex", arm)
    joint_offset(off, "spine_flex", spine)
    cocontract(off, @land_cc) if @land_cc > ~0.0
    off

  # Co-contraction: both muscles of every leg joint shorten by cc (stiffness
  # without moving the equilibrium).
  -> cocontract(off, cc)
    ["l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle"].each ->(j)
      off[body.pos_index(j)] = off[body.pos_index(j)] + cc
      off[body.neg_index(j)] = off[body.neg_index(j)] + cc
    off
