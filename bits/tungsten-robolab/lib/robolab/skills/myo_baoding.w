# MyoBaoding: MyoChallenge 2022 Baoding balls (phase 2) on the myoHand, 39
# muscles of the forearm and hand. Two balls in the upturned palm follow two
# targets circling an ellipse: still (HOLD), clockwise or counter-clockwise.
#
# What the task asks for is the pair's orientation: phi, the angle of the
# line from ball 2 to ball 1 in the palm frame (the `balls` sensor), must
# follow the targets' phi* (the `goals` sensor) while the pair stays centred.
# The skill turns the pair with a finger gait:
#
#   cup      fingers curl into a cup that holds both balls; the skill reads
#            the targets' direction from their motion (they start moving on
#            the second step)
#   a0..a3   the counter-clockwise gait: four contraction states, each held
#            for its duration (or LATCHED early on the pair running ahead),
#            looping
#   b0..b3   the clockwise gait
#   hold     entered whenever the pair runs `lead` ahead of phi* (and for
#            HOLD once the pair has caught up): the cup posture, LATCHED on
#            phi* coming back within `lead` / 2, then the gait resumes
#
# Routing is by chunk branches: cup branches to the direction's first gait
# state, every gait state's latch also fires when the pair runs ahead (its
# branch then picks `hold`), the last state loops, and hold branches back to
# the state it interrupted.
#
# Every chunk also carries a spring-eased correction: a posture map indexed
# by the targets' pair angle phi* (per joint group, a second-order Fourier
# series in phi* over the cup: for each target angle, the posture whose
# resting pair angle is closest to it), plus, from the target error, the
# rotation synergy: a signed vector over the joint groups (flexing the
# middle and ring fingers turns the pair one way, the little finger and ulnar
# deviation the other; a static probe of each group measured up to +-30 deg),
# scaled by the pair's angle error phi* - phi through a saturating gain. The
# cup posture fixes an equilibrium pair angle; the synergy moves that
# equilibrium toward the targets, so the pair follows them within the reach
# of the hand, and HOLD targets near the reach are held.
#
# Each gait state is a goal posture over 14 joint groups (wrist deviation
# and flexion, the four thumb joints, each finger's knuckle and middle
# joints; defaults: the cup), a duration and an easing, with a `stagger`:
# the fingers' onsets delayed one after another (a travelling wave inside
# the chunk) and the thumb's by its own lag. The gait states are timed; the
# rotation synergy and the pacing sit on top. Search (BO / (1+1)-ES, per the
# search study) finds the states.

+ MyoBaodingSkill < Skill
  -> start(frame, ctl)
    @g = body.geometry
    @dt = ctl.dt
    @dir = 0
    @phi_goal0 = nil
    @goal_seen = 0
    @resume = "a0"
    @gait = ""
    ctl.reflex.set_gains(body.all, param("kp", ~8.0, ~1.0, ~40.0), param("kd", ~0.2, ~0.0, ~2.0))
    wrist = body.mask(["ECRL", "ECRB", "ECU", "FCR", "FCU", "PL", "PT", "PQ"])
    ctl.reflex.set_gains(wrist, param("kp_wrist", ~10.0, ~1.0, ~40.0), param("kd_wrist", ~0.3, ~0.0, ~2.0))
    stiff = param("stiff", ~0.06, ~0.0, ~0.3)
    # joint groups: [deviation, flexion, cmc_abd, cmc_flex, mp, ip,
    #   mcp2, pip2, mcp3, pip3, mcp4, pip4, mcp5, pip5]
    @groups = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion", "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]
    cup = [param("cup_dev", ~0.1, ~-0.17, ~0.43), param("cup_flex", ~0.1, ~-0.78, ~0.78), param("cup_cabd", ~0.3, ~-0.5, ~0.78), param("cup_cflex", ~0.2, ~-0.78, ~0.7), param("cup_mp", ~0.2, ~-0.78, ~0.7), param("cup_ip", ~0.1, ~-1.3, ~0.43), param("cup_f2", ~0.5, ~0.0, ~1.5), param("cup_p2", ~0.4, ~0.0, ~1.5), param("cup_f3", ~0.5, ~0.0, ~1.5), param("cup_p3", ~0.4, ~0.0, ~1.5), param("cup_f4", ~0.5, ~0.0, ~1.5), param("cup_p4", ~0.4, ~0.0, ~1.5), param("cup_f5", ~0.6, ~0.0, ~1.5), param("cup_p5", ~0.5, ~0.0, ~1.5)]
    @cup = cup
    p_cup = posture(cup, stiff)
    t_cup = param("t_cup", ~0.3, ~0.1, ~1.0)
    # rotation synergy (joint-group offsets per unit of saturated angle error)
    # (turning the pair either way uses different fingers, so one vector per
    # sign of the error; defaults from the static probe for the + side)
    @syn_p = @groups.map ->(n) param("synp_" + n, probe_default(n), ~-0.8, ~0.8)
    @syn_n = @groups.map ->(n) param("synn_" + n, ~0.0, ~-0.8, ~0.8)
    @k_rot = param("k_rot", ~2.0, ~0.0, ~10.0)
    # posture map: per joint group, offsets a cos(phi*) + b sin(phi*) +
    # c cos(2 phi*) + d sin(2 phi*) over the cup, phi* the targets' pair angle
    @fmap = []
    @groups.each ->(n)
      ["c1", "s1", "c2", "s2"].each ->(h) @fmap.push(param("fm_" + n + "_" + h, ~0.0, ~-0.6, ~0.6))
    # postural tone for the hand (off by default)
    ki_h = param("ki_hand", ~0.0, ~0.0, ~60.0)
    ctl.reflex.set_integral(body.all, ki_h, param("ilim_hand", ~0.02, ~0.001, ~0.1)) if ki_h > ~0.0
    @rot_lim = param("rot_lim", ~1.0, ~0.0, ~1.5)
    syn_cb = ->(f, c) synergy_offsets(f)
    syn_spring = param("syn_spring", ~0.08, ~0.02, ~0.4)
    @lead = param("lead", ~0.35, ~0.05, ~1.0)
    @hold_tol = param("hold_tol", ~0.15, ~0.02, ~0.6)
    @th_in = ~10.0
    @th_out = ~0.0
    @turn = 1
    # spin benchmark (param `spin` = 1 or -1): turn that way without pacing
    @spin = 0
    @spin = params["spin"].to_i if params.key?("spin")
    t_step = param("t_step", ~0.25, ~0.05, ~0.8)
    mv = Movement.new("baoding")
    mv.add(Chunk.new("cup", t_cup).pose(p_cup).hold_until(Latch.after(t_cup)).correct(syn_cb, syn_spring).branch(->(f, c) begin_gait(f)))
    # the finger groups a gait state may stagger (a travelling wave inside
    # one chunk): index, middle, ring, little, thumb
    digits = [body.mask(["FDS2", "FDP2", "EDC2", "EIP", "RI2", "LU_RB2", "UI_UB2"]), body.mask(["FDS3", "FDP3", "EDC3", "RI3", "LU_RB3", "UI_UB3"]), body.mask(["FDS4", "FDP4", "EDC4", "RI4", "LU_RB4", "UI_UB4"]), body.mask(["FDS5", "FDP5", "EDC5", "EDM", "RI5", "LU_RB5", "UI_UB5"]), body.mask(["EPL", "EPB", "FPL", "APL", "OP"])]
    easings = [:linear, :min_jerk, :sine_in_out, :cubic_in, :cubic_out]
    ["a", "b"].each ->(side)
      k = 0
      while k < 4
        name = side + k.to_s
        nxt = side + ((k + 1) % 4).to_s
        # the state as a goal posture (defaults: the cup), a duration and an
        # easing; `wave` delays each finger's onset by wave x its place in
        # index -> little (negative: little -> index), `lag_th` the thumb's
        state = (0...@groups.size).map ->(i) param(name + "_" + @groups[i], cup[i], group_lo(i), group_hi(i))
        dur = param(name + "_t", t_step, ~0.05, ~0.8)
        ez = easings[clamp((param(name + "_e", ~0.3, ~0.0, ~0.99) * ~5.0).floor, 0, 4)]
        wave = param(name + "_wave", ~0.0, ~-0.08, ~0.08)
        lag_th = param(name + "_lagth", ~0.0, ~0.0, ~0.15)
        early = Latch.test("ahead", ->(f, e, c) ahead(f) > @th_in)
        ch = Chunk.new(name, dur).pose(posture(state, stiff)).ease(ez).hold_until(Latch.any([Latch.after(dur), early]))
        d = 0
        while d < 4
          delay = wave * d
          delay = (~0.0 - wave) * (3 - d) if wave < ~0.0
          ch.stagger(digits[d], delay) if delay > ~0.0
          d += 1
        ch.stagger(digits[4], lag_th) if lag_th > ~0.0
        ch.correct(syn_cb, syn_spring)
        ch.branch(pace(name, nxt))
        mv.add(ch)
        k += 1
    back = Latch.test("caught_up", ->(f, e, c) caught_up?(f))
    mv.add(Chunk.new("hold", ~0.15).pose(p_cup).hold_until(back).correct(syn_cb, syn_spring).branch(->(f, c) @resume))
    ctl.add_track(Track.new("hand", mv, body.all))

  # Search range of joint group i (rad).
  -> group_lo(i)
    los = [~-0.17, ~-0.78, ~-0.5, ~-0.78, ~-0.78, ~-1.3, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    los[i]

  -> group_hi(i)
    his = [~0.43, ~0.78, ~0.78, ~0.7, ~0.7, ~0.43, ~1.5, ~1.5, ~1.5, ~1.5, ~1.5, ~1.5, ~1.5, ~1.5]
    his[i]

  # Hand posture from the 14 joint-group values (palm up: pro_sup at its
  # limit, which the forearm's weight holds).
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

  # ---- pair angles --------------------------------------------------------

  -> phi(f)
    Math.atan2(f.at("balls", 1) - f.at("balls", 3), f.at("balls", 0) - f.at("balls", 2))

  -> phi_goal(f)
    Math.atan2(f.at("goals", 1) - f.at("goals", 3), f.at("goals", 0) - f.at("goals", 2))

  # a - b wrapped to (-pi, pi]
  -> wrap(a)
    while a > ~3.141592653589793
      a = a - ~6.283185307179586
    while a <= ~-3.141592653589793
      a = a + ~6.283185307179586
    a

  # How far the pair is ahead of its targets in the direction of travel.
  -> ahead(f)
    d = wrap(phi(f) - phi_goal(f))
    return ~0.0 - d if @turn < 0
    d

  # Pacing thresholds on ahead(f): enter `hold` above @th_in, leave it
  # below @th_out. Turning targets: hold `lead` ahead, resume at lead / 2.
  # HOLD targets: stop once within `hold_tol` of the target, turn again only
  # if the pair falls 2 hold_tol behind.
  -> caught_up?(f)
    ahead(f) < @th_out

  # ---- direction and pacing --------------------------------------------------

  # The targets' direction from their motion; the gait's turning direction
  # (for HOLD, the shorter way round to the start phase).
  -> before(f, ctl)
    return nil if !f.has?("goals")
    pg = phi_goal(f)
    if f.at("goals", 0) != ~0.0 || f.at("goals", 1) != ~0.0
      @goal_seen = @goal_seen + 1
      if @goal_seen == 2
        @phi_goal0 = pg
      if @goal_seen == 4
        d = wrap(pg - @phi_goal0)
        @dir = 0
        @dir = 1 if d > ~0.01
        @dir = -1 if d < ~-0.01
    nil

  # Cup's branch: once the targets' direction is known, the gait that turns
  # the pair toward (or with) them; HOLD targets stop once reached.
  -> begin_gait(f)
    @turn = @dir
    @turn = 1 if @dir == 0 && wrap(phi_goal(f) - phi(f)) > ~0.0
    @turn = -1 if @dir == 0 && wrap(phi_goal(f) - phi(f)) <= ~0.0
    @th_in = @lead
    @th_out = @lead * ~0.5
    if @dir == 0
      @th_in = ~0.0 - @hold_tol
      @th_out = ~-2.0 * @hold_tol
    if @spin != 0
      @turn = @spin
      @th_in = ~10.0
    @gait = "a"
    @gait = "b" if @turn < 0
    @resume = @gait + "0"
    @resume

  # A gait state's branch: hold if the pair has run ahead, else the next state.
  -> pace(name, nxt)
    ->(f, c) pace_step(f, name, nxt)

  -> pace_step(f, name, nxt)
    if ahead(f) > @th_in
      @resume = nxt
      return "hold"
    nxt

  # Rotation synergy: joint offsets = syn_p (or syn_n when the pair must turn
  # the other way) * |clamp(k_rot * (phi* - phi))|,
  # through the muscle geometry. Off until the targets have been seen.
  -> synergy_offsets(f)
    return nil if @goal_seen < 2
    # joint-group offsets: the posture map at the target angle phi*, plus the
    # error synergy
    dq = (0...14).map ->(i) ~0.0
    pg = phi_goal(f)
    feats = [Math.cos(pg), Math.sin(pg), Math.cos(~2.0 * pg), Math.sin(~2.0 * pg)]
    i = 0
    while i < 14
      k = 0
      while k < 4
        dq[i] = dq[i] + @fmap[4 * i + k] * feats[k]
        k += 1
      i += 1
    if @k_rot != ~0.0
      u = clamp(@k_rot * wrap(pg - phi(f)), ~0.0 - @rot_lim, @rot_lim)
      syn = @syn_p
      if u < ~0.0
        syn = @syn_n
        u = ~0.0 - u
      i = 0
      while i < 14
        dq[i] = dq[i] + syn[i] * u
        i += 1
    off = zeros
    names = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion"]
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

  # The + side's starting synergy, from the static probe: flexing index,
  # middle and ring turned the pair counter-clockwise, the little finger the
  # other way.
  -> probe_default(n)
    names = ["f2", "f3", "p3", "f4", "p4", "f5"]
    vals = [~0.3, ~0.4, ~0.4, ~0.4, ~0.4, ~-0.2]
    i = 0
    while i < names.size
      return vals[i] if names[i] == n
      i += 1
    ~0.0
