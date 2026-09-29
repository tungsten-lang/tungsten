# RunKnots: the natural run as a periodic quintic knot train, fitted to a
# human reference by least squares and closed on the body by iterative
# learning control (P7 in playground/SEARCH.md; driver playground/runknots.py).
#
# Two ways to run the train. `knots 1` replaces RunNaturalSkill's stride
# chunks by knot chunks (below). `knot_residual 1` (the one P7's runners use)
# keeps RunNaturalSkill's posture-keyframe stride and adds the knot train to
# its command as a residual, zero by default: at zero vectors the controller
# is RunNaturalSkill bit for bit, and the least-squares fit and the ILC move
# the residual knots from there. (The full train, fitted to the champion's
# own mean command, falls where the keyframes do not: their front-loaded
# chunks reach each goal posture early and hold it, so a phase that ends
# early still ends at its goal, while a smooth segment is cut short.)
#
# With `knots 1`: a RunNaturalSkill whose stride chunks are Chunk#knot keyframes. Each gait
# event of the right step (td, ms, to, plus any ordered extra keyframe such as
# hr / kl) is a knot: a full contraction vector (one entry per muscle), a
# contraction-velocity vector and a contraction-acceleration vector. The left
# step's knots are their mirror images (l_ and r_ muscles swapped). Between two
# knots the command is the quintic Hermite segment (min-jerk position basis,
# Quintic.basis for the derivatives), so the whole stride is a linear
# function of the knot vectors: a periodic knot train through a transposed
# convolution whose kernels are the Hermite basis functions, stretched to
# each segment's duration. The train runs in gait phase, not clock time: a
# knot chunk lasts its share of the running estimate of its phase's duration
# (load, drive, flight; RunNaturalSkill#dur_of, updated at every phase change),
# so the segments stretch with the slow first strides of a standing start and
# each knot is reached about when its event's latch fires (`knot_clock 0`:
# fixed durations kt_load / kt_drive / kt_fly instead). Everything else is
# RunNaturalSkill's: the latches that end each
# chunk on its gait event, the reflex gains per phase, the drives (push-off
# scaled by the speed plan and Raibert's hop-height loop), the spring-eased
# corrections (the stance hip's torso servo, the swing hip's pitch
# compensation and placement, the stance knee's hop-height term) and the
# standing start.
#
# Params-file settings (not tunables; the driver sets them):
#
#   knots 1                  the stride chunks become knot chunks (0 or absent:
#                            RunNaturalSkill exactly)
#   kc_<id>_<muscle>         the knot's contraction (right stance; id = td, ms,
#   kv_<id>_<muscle>         to or an extra keyframe; muscle = a body muscle
#   ka_<id>_<muscle>         name). Missing: kc the keyframe posture's
#                            contraction (RunNaturalSkill's goal), kv / ka zero
#   knot_from t              run RunNaturalSkill's posture keyframes (the
#                            standing start and the first strides) until t
#                            seconds, then switch to the knot train at the
#                            next stride (default 0: knots from the start)
#   knot_clock 0             fixed knot-chunk durations kt_load / kt_drive /
#                            kt_fly (s; times each chunk's share of its phase)
#                            instead of the running phase estimates
#   knot_tscale s            scale the phase-timed durations (default 1)
#   knot_trace 1             emit the tracks' command each tick (a `kcmd:`
#                            token, 32 comma-separated values): the decoder's
#                            output, before corrections and the reflexes
#   knot_residual 1          the knot train as a RESIDUAL on RunNaturalSkill's
#                            own posture-keyframe stride (knots off): per stride
#                            knot rc_<id>_<muscle> / rv_ / ra_ (contraction
#                            offset, its velocity and acceleration; right
#                            stance, the left step mirrored), a quintic segment
#                            per stride chunk (event to event, timed as the
#                            knot chunks are) added to the command as an
#                            offset. Zero vectors: RunNaturalSkill exactly
#   res_from t, res_ramp r   (with knot_residual) fade the residual in from t
#                            seconds over r seconds (default: on from the
#                            first stride chunk)
#   knot_mid 1               (with knot_residual) a knot between every two
#                            events too: each stride chunk's residual runs to
#                            its mid knot h<id> (id = the chunk's own knot)
#                            over the first half of its timed duration, then
#                            on to the chunk's knot
#   two_knot 1               (with knots 1) the stride as TWO knots per step,
#                            touchdown and toe-off: a stance chunk (knot to,
#                            ends on the foot's release) and a flight chunk
#                            (knot td, ends on the other foot's contact); the
#                            mid-stance switch of gains and drives stays, as an
#                            event inside the stance chunk (see start_two);
#                            kt_stance: the stance segment's fixed duration
#                            (knot_clock 0; else load + drive estimates). With
#                            knot_residual 1 instead: the RESIDUAL's knots are
#                            touchdown and toe-off, its stance segment spanning
#                            the posture stride's load and drive chunks
#   k_vlean k, vlean_max l   a speed loop through the trunk: the torso servo's
#                            target + k (v_des - v), clamped to +-l rad
#   tcn 1                    a residual causal TCN (ConvPolicy, tcn.w) on
#                            proprioception adds a joint-angle offset (rad) to
#                            each leg joint and the spine every tick, spread
#                            over the muscles crossing the joint through the
#                            body's geometry (Skill#joint_offset); weights
#                            tcn_w<k> (the head starts at zero); `tcn_trace 1`
#                            emits its outputs as a `tcn:` token

+ RunKnotsSkill < RunNaturalSkill
  -> read_params
    super
    @knots = switch_on("knots")
    @knot_clock = true
    @knot_clock = @params["knot_clock"] > ~0.5 if @params.key?("knot_clock")
    @knot_tscale = ~1.0
    @knot_tscale = @params["knot_tscale"] if @params.key?("knot_tscale")
    @kt_load = ~0.08
    @kt_load = @params["kt_load"] if @params.key?("kt_load")
    @kt_drive = ~0.11
    @kt_drive = @params["kt_drive"] if @params.key?("kt_drive")
    @kt_fly = ~0.16
    @kt_fly = @params["kt_fly"] if @params.key?("kt_fly")
    @knot_trace = switch_on("knot_trace")
    # knot_from t: the standing start and the stride loop run the posture
    # keyframes until t seconds, then the knot train takes over (see start)
    @knot_from = ~0.0
    @knot_from = @params["knot_from"] if @params.key?("knot_from")
    @knot_later = @knots && @knot_from > ~0.0
    @knots = false if @knot_later
    @mirror = []
    body.muscles.each ->(mu) @mirror.push(mirror_name(mu.name))
    @tcn = nil
    @tcn_trace = switch_on("tcn_trace")
    @tcn_joints = ["l_hip_flex", "l_knee", "l_ankle", "r_hip_flex", "r_knee", "r_ankle", "spine_flex"]
    @tcn = ConvPolicy.new(body, @params, @tcn_joints) if switch_on("tcn")
    @k_vlean = ~0.0
    @k_vlean = @params["k_vlean"] if @params.key?("k_vlean")
    @vlean_max = ~0.1
    @vlean_max = @params["vlean_max"] if @params.key?("vlean_max")
    @res_on = switch_on("knot_residual")
    @two_res = false
    @kt_stance = ~0.2
    @kt_stance = @params["kt_stance"] if @params.key?("kt_stance")
    read_residual if @res_on
    @two = @knots && switch_on("two_knot")
    self

  -> switch_on(name)
    return false if !@params.key?(name)
    @params[name] > ~0.5

  -> start(frame, ctl)
    if @params.key?("two_knot") && @params["two_knot"] > ~0.5 && switch_on("knots")
      return start_two(frame, ctl)
    super(frame, ctl)
    add_knot_loop(ctl) if @knot_later
    @track = ctl.track("body")
    self

  # ---- two knots per step (two_knot 1, with knots 1) -------------------------

  # The stride as touchdown and toe-off knots only: per step a stance chunk
  # (touchdown -> toe-off: knot `to`, ends on the stance foot's release) and a
  # flight chunk (toe-off -> the other foot's touchdown: knot `td`, ends on its
  # contact), each one quintic segment; no mid-stance or heel-rise keyframe.
  # Everything else is RunNaturalSkill's: the standing start, the latches, the
  # drives (push-off scaled by the speed plan and the hop-height loop), the
  # corrections and the per-phase reflex gains, whose load -> drive switch
  # (softer knee and ankle while the leg loads) still happens at the
  # mid-stance event (the COM passing d_ms ahead of the stance foot) inside
  # the stance chunk, together with the switch from the loading pre-tension
  # to the push-off drive. (RunNaturalSkill#start, repeated for this stride.)
  -> start_two(frame, ctl)
    read_params
    ctl.emit("ref_speed:" + @speed.to_s)
    @v_f = frame.com_vx
    @flying = frame.com_vx > ~1.0
    @v_des = @v0
    @v_des = @speed if @flying
    @t_go = ~-1.0
    @t_go = frame.t if @flying
    @phase = nil
    @t_phase = frame.t
    @st = "r_"
    @sw = "l_"
    @drives = []
    setup_reflexes(ctl)
    read_contraction_offsets
    @load_drive = {}
    @push_vec = {}
    @stance_drive = {}
    td = keyframe("td")
    to = keyframe("to")
    mv = Movement.new("run_natural")
    if !@flying
      mv.add(stand_chunk)
      mv.add(lean_chunk)
      mv.add(first_push(to.mirror))
    first = mv.size
    mv.add(two_flight("l_", "r_", td))
    mv.add(two_stance("r_", "l_", to))
    mv.add(two_flight("r_", "l_", td.mirror))
    mv.add(two_stance("l_", "r_", to.mirror))
    mv.loop_from(first)
    @track = ctl.add_track(Track.new("body", mv, body.all))
    self

  -> two_flight(st, sw, goal)
    ch = aim(Chunk.new(st + "flight", @t_fly), goal)
    styled(ch, @ease_fly, false)
    ch.hold_until(Latch.contact(sw + "foot").after_min(~0.03), ~0.45)
    ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, st + "rf", @drv_rf, sw + "knee_neg", @drv_pre,
                        sw + "ankle_pos", @drv_pre_ank, sw + "gas", @drv_pre_ank]))
    ch.correct(->(f, c) correction(f, c, st, sw, :flight), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :flight))
    ch

  -> two_stance(st, sw, goal)
    ch = aim(Chunk.new(st + "stance", @t_load + @t_drive), goal)
    styled(ch, @ease_drive, false)
    ch.hold_until(Latch.release(st + "foot").after_min(@t_ms_min + ~0.03), @t_ms_max + @t_drive_max)
    @load_drive[st] = drive_vec([st + "knee_neg", @pre_knee, st + "ankle_pos", @pre_ankle, sw + "knee_pos", @drv_tuck])
    @push_vec[st] = push_drive(st, sw)
    d = zeros
    @stance_drive[st] = d
    ch.drive(d)
    ch.correct(->(f, c) correction(f, c, st, sw, :stance), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :load))
    ch

  # Inside the stance chunk: the mid-stance switch (load -> drive gains and
  # drives), and the stance chunk's drive vector for the current phase (the
  # push-off vector is rescaled every tick by scale_drives).
  -> two_phase(f)
    return self if @phase == nil
    st = @st
    if @phase == :load
      e = f.t - @t_phase
      mid = f.com_x - f.at(st + "foot_pos", 0) > @d_ms
      enter(f, st, @sw, :drive) if (e >= @t_ms_min && mid) || e >= @t_ms_max
    d = @stance_drive[st]
    return self if d == nil
    src = @load_drive[st]
    src = @push_vec[st] if @phase == :drive
    i = 0
    while i < d.size
      d[i] = src[i]
      i += 1
    self

  # knot_from: RunNaturalSkill's movement (standing start, posture-keyframe
  # stride loop) gets the knot train's stride loop appended; the posture
  # loop's last chunk goes back to its first until knot_from seconds, then on
  # into the knot loop, which loops from then on. (Chunk names repeat, so a
  # jump by name finds the posture loop's.)
  -> add_knot_loop(ctl)
    mv = ctl.track("body").movement
    name0 = mv[mv.loop_start].name
    last = mv[mv.size - 1]
    @knots = true
    first = mv.size
    if @plan.size > 3
      build_stride(mv)
    else
      td = keyframe("td")
      ms = keyframe("ms")
      to = keyframe("to")
      mv.add(flight_chunk("l_", "r_", td, to.mirror))
      mv.add(load_chunk("r_", "l_", ms, td))
      mv.add(drive_chunk("r_", "l_", to, ms))
      mv.add(flight_chunk("r_", "l_", td.mirror, to))
      mv.add(load_chunk("l_", "r_", ms.mirror, td.mirror))
      mv.add(drive_chunk("l_", "r_", to.mirror, ms.mirror))
    mv.loop_from(first)
    last.branch(->(f, c) keep_posture(f, name0))
    self

  -> keep_posture(f, name)
    return name if f.t < @knot_from
    nil

  # The other side's muscle (l_ and r_ swapped; unsided muscles map to
  # themselves).
  -> mirror_name(nm)
    return "r_" + nm.slice(2, nm.size - 2) if nm.starts_with?("l_")
    return "l_" + nm.slice(2, nm.size - 2) if nm.starts_with?("r_")
    nm

  # ---- the knot train -------------------------------------------------------

  # A stride chunk's goal: the knot of its keyframe (mirrored on the left
  # step), reached along the quintic Hermite segment.
  -> aim(ch, kf)
    if !@knots
      return super(ch, kf)
    k = PhaseChunk.new(ch.name, ch.duration)
    tm = knot_timing(kf.name)
    k.timed_by(self, tm[0], tm[1])
    k.to(knot_c(kf)).knot(knot_vec("kv_", kf), knot_vec("ka_", kf))

  # The gait phase a knot chunk belongs to (the kind of its goal keyframe) and
  # its share of that phase: from the previous keyframe of the step to its own
  # (RunNaturalSkill#step_chunk's shares; 1 for td / ms / to alone).
  -> knot_timing(id)
    if @two || @two_res
      return [:flight, ~1.0] if id == "td"
      return [:stance, ~1.0]
    p = kf_phase(id)
    p = kf_phase("td") + ~50.0 if id == "td"
    k = kind_of(p)
    i = 0
    while i < @plan.size && @plan[i] != id
      i += 1
    j = i - 1
    j = @plan.size - 1 if j < 0
    [k, share_of(p, k) - share_of(kf_phase(@plan[j]), k)]

  # A knot chunk's duration: its share of the phase's duration, the running
  # estimate (knot_clock 1) or the fixed kt_load / kt_drive / kt_fly.
  -> knot_time(kind, share)
    if kind == :stance
      return (dur_of(:load) + dur_of(:drive)) * share * @knot_tscale if @knot_clock
      return @kt_stance * share * @knot_tscale
    return dur_of(kind) * share * @knot_tscale if @knot_clock
    return @kt_load * share * @knot_tscale if kind == :load
    return @kt_drive * share * @knot_tscale if kind == :drive
    @kt_fly * share * @knot_tscale

  # Knot chunks run the exact quintic: min-jerk position basis, no via
  # tangents (the knot's own velocity replaces them).
  -> styled(ch, ease, via)
    if !@knots
      return super(ch, ease, via)
    ch.ease(:min_jerk)

  # The standing start's first push stays a posture chunk (the loop's first
  # knot segment starts from it at rest).
  -> first_push(goal)
    was = @knots
    @knots = false
    ch = super(goal)
    @knots = was
    ch

  # The params-file name of muscle m's entry in a keyframe's knot: the
  # right-stance knot's own muscle, or on the left step its mirror.
  -> knot_key(prefix, kf, m)
    nm = body.muscle(m).name
    nm = @mirror[m] if kf.stance == "l_"
    prefix + kf.name + "_" + nm

  -> knot_c(kf)
    c = contraction_of(kf)
    m = 0
    while m < body.size
      key = knot_key("kc_", kf, m)
      c[m] = @params[key] if @params.key?(key)
      m += 1
    c

  -> knot_vec(prefix, kf)
    out = zeros
    m = 0
    while m < body.size
      key = knot_key(prefix, kf, m)
      out[m] = @params[key] if @params.key?(key)
      m += 1
    out

  # ---- per tick ---------------------------------------------------------------

  # k_vlean (rad per m/s, opt-in): the torso servo's target leans forward
  # while the body runs below v_des (and back above it), clamped to
  # +-vlean_max rad: a speed loop through the trunk, the stride's strongest
  # speed lever (RunNaturalSkill's own speed terms are the push-off scaling
  # and Raibert's placement).
  -> before(frame, ctl)
    super(frame, ctl)
    two_phase(frame) if @two
    if @k_vlean > ~0.0
      @trunk_des = @trunk_des + clamp(@k_vlean * (@v_des - @v_f), ~0.0 - @vlean_max, @vlean_max)
    self

  -> after(frame, ctl)
    super(frame, ctl)
    apply_residual(frame, ctl) if @res_on
    apply_tcn(frame, ctl) if @tcn != nil
    ctl.emit("kcmd:" + ctl.command.values.join(",")) if @knot_trace
    ctl.emit("kres:" + @res_last.join(",")) if @knot_trace && @res_on
    self

  # ---- the residual knot train (knot_residual 1) -------------------------------

  # The residual's knot vectors per stride knot ("<id>:r_" / "<id>:l_": c, v,
  # a over the muscles, the left step's read from the mirror muscles) and the
  # knot each stride chunk ends on (its goal keyframe; a flight ends on the
  # other side's touchdown).
  -> read_residual
    @res = {}
    @res_goal = {}
    @two_res = switch_on("two_knot")
    return read_two_residual if @two_res
    ["r_", "l_"].each ->(st)
      other = "l_"
      other = "r_" if st == "l_"
      @plan.each ->(id)
        nm = st + id
        g = st
        if id == "td"
          nm = st + "flight"
          g = other
        nm = st + "load" if id == "ms"
        nm = st + "drive" if id == "to"
        @res_goal[nm] = id + ":" + g
    @res_mid = switch_on("knot_mid")
    @res_from = ~0.0
    @res_from = @params["res_from"] if @params.key?("res_from")
    @res_ramp = ~0.0
    @res_ramp = @params["res_ramp"] if @params.key?("res_ramp")
    @track_t = ~0.0
    @plan.each ->(id)
      ["r_", "l_"].each ->(side)
        @res[id + ":" + side] = [res_vec("rc_", id, side), res_vec("rv_", id, side), res_vec("ra_", id, side)]
        h = "h" + id
        @res[h + ":" + side] = [res_vec("rc_", h, side), res_vec("rv_", h, side), res_vec("ra_", h, side)] if @res_mid
    @res_name = ""
    @res_cur = nil
    @res_t = ~0.1
    @res_last = zeros
    @res_p0 = zeros
    @res_v0 = zeros
    @res_a0 = zeros
    self

  # two_knot with knot_residual: the residual's knots are touchdown and
  # toe-off only; its stance segment runs from touchdown through the
  # posture stride's load and drive chunks to toe-off (one quintic over
  # kt_stance, or the load + drive estimates), its flight segment through the
  # flight chunk to the next touchdown.
  -> read_two_residual
    ["r_", "l_"].each ->(st)
      other = "l_"
      other = "r_" if st == "l_"
      @res_goal[st + "load"] = "to:" + st
      @res_goal[st + "drive"] = "to:" + st
      @res_goal[st + "flight"] = "td:" + other
      ["td", "to"].each ->(id)
        @res[id + ":" + st] = [res_vec("rc_", id, st), res_vec("rv_", id, st), res_vec("ra_", id, st)]
    @res_mid = false
    @res_from = ~0.0
    @res_from = @params["res_from"] if @params.key?("res_from")
    @res_ramp = ~0.0
    @res_ramp = @params["res_ramp"] if @params.key?("res_ramp")
    @track_t = ~0.0
    @res_name = ""
    @res_cur = nil
    @res_t = ~0.1
    @res_t0 = ~0.0
    @res_last = zeros
    @res_p0 = zeros
    @res_v0 = zeros
    @res_a0 = zeros
    self

  -> res_vec(prefix, id, side)
    out = zeros
    m = 0
    while m < body.size
      nm = body.muscle(m).name
      nm = @mirror[m] if side == "l_"
      key = prefix + id + "_" + nm
      out[m] = @params[key] if @params.key?(key)
      m += 1
    out

  # The residual this tick: the quintic segment of the current stride chunk
  # (from where the residual was when the chunk began, leaving with the
  # velocity and acceleration of the knot the previous chunk ended on, to
  # this chunk's knot over its timed duration, held there if the chunk runs
  # longer), added to the command as an offset. Zero outside the stride.
  -> apply_residual(frame, ctl)
    @track_t = frame.t
    ch = @track.chunk
    return self if ch == nil
    enter_residual(ch.name) if ch.name != @res_name && !@two_res
    enter_two_residual(ch.name, frame) if ch.name != @res_name && @two_res
    return self if @res_cur == nil
    e = @track.elapsed(frame)
    e = frame.t - @res_t0 if @two_res
    k = @res[@res_cur]
    t = @res_t
    p0 = @res_p0
    v0 = @res_v0
    a0 = @res_a0
    if @res_mid
      # two segments per chunk: to the mid knot over the first half of the
      # timed duration, then from it to the chunk's knot
      t = @res_t * ~0.5
      h = @res["h" + @res_cur]
      if e < t
        k = h
      else
        p0 = h[0]
        v0 = h[1]
        a0 = h[2]
        e = e - t
    residual_segment(ctl, p0, v0, a0, k, t, e)
    self

  -> residual_segment(ctl, p0, v0, a0, k, t, e)
    s = Easing.clamp01(e / t)
    p = Easing.min_jerk(s)
    b = Quintic.basis(s)
    c1 = k[0]
    v1 = k[1]
    a1 = k[2]
    ta = t * t
    g = residual_gain(ctl)
    m = 0
    while m < body.size
      r = p0[m] + (c1[m] - p0[m]) * p + t * (b[0] * v0[m] + b[3] * v1[m]) + ta * (b[1] * a0[m] + b[2] * a1[m])
      @res_last[m] = r
      ctl.add_offset(m, r * g)
      m += 1
    self

  # res_from / res_ramp: the residual fades in linearly from res_from seconds
  # over res_ramp seconds (default: full from the first stride chunk), so the
  # standing start and the first strides stay RunNaturalSkill's own.
  -> residual_gain(ctl)
    return ~1.0 if @res_ramp <= ~0.0 && @res_from <= ~0.0
    t = @track_t - @res_from
    return ~0.0 if t <= ~0.0
    return ~1.0 if t >= @res_ramp
    t / @res_ramp

  -> enter_residual(name)
    prev = @res_cur
    @res_name = name
    @res_cur = nil
    @res_cur = @res_goal[name] if @res_goal.key?(name)
    @res_p0 = @res_last.map -> item
    @res_v0 = zeros
    @res_a0 = zeros
    if prev != nil
      @res_v0 = @res[prev][1]
      @res_a0 = @res[prev][2]
    if @res_cur != nil
      tm = knot_timing(@res_cur.slice(0, @res_cur.size - 3))
      @res_t = knot_time(tm[0], tm[1])
    self

  # A two-knot residual segment starts only when the stance chunk's goal
  # changes (load -> drive continues the stance segment), timed from the
  # chunk's own start.
  -> enter_two_residual(name, frame)
    @res_name = name
    g = nil
    g = @res_goal[name] if @res_goal.key?(name)
    return self if g != nil && g == @res_cur
    prev = @res_cur
    @res_cur = g
    @res_t0 = frame.t - @track.elapsed(frame)
    @res_p0 = @res_last.map -> item
    @res_v0 = zeros
    @res_a0 = zeros
    if prev != nil
      @res_v0 = @res[prev][1]
      @res_a0 = @res[prev][2]
    if g != nil
      tm = knot_timing(g.slice(0, g.size - 3))
      @res_t = knot_time(tm[0], tm[1])
    self

  # The TCN's joint offsets (rad, clamped to +-tcn_max) as contraction
  # offsets on every muscle crossing each joint.
  -> apply_tcn(frame, ctl)
    y = @tcn.step(@tcn.features(frame))
    off = zeros
    i = 0
    while i < @tcn_joints.size
      joint_offset(off, @tcn_joints[i], y[i])
      i += 1
    m = 0
    while m < off.size
      ctl.add_offset(m, off[m])
      m += 1
    ctl.emit("tcn:" + y.join(",")) if @tcn_trace
    self

# A knot chunk timed in gait phase: its duration is its share of the skill's
# running estimate of its phase's duration (RunKnotsSkill#knot_time), read
# every tick. The estimate only changes when its own phase ends, so it is
# constant while the chunk runs.
+ PhaseChunk < Chunk
  -> timed_by(@clock, @kind, @share)
    self

  -> duration
    @clock.knot_time(@kind, @share)
