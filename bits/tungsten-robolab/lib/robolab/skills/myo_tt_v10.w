# MyoTTV10: round-9 options for the table-tennis skill (MyoTTV9Skill), each
# opt-in by params; with every switch at 0 it is MyoTTV9Skill (and so the
# round-5 champions).
#
# Round 8 found the arm far from what it is told: at the forehand's contact
# the plane of elevation is 0.96 against 0.36 commanded, the forearm's
# rotation 0.44 against 1.20. Part of it is the posture-to-contraction map:
# the controller's length model is additive (each joint swept alone from the
# reset posture), and on the shoulder, where the three axes and the
# shoulder girdle move together, it is off by up to 0.36 of a muscle's range
# at the forehand's commanded posture (BIClong) and 0.86 at the backhand's
# (BIClong; SUPSP 0.64, SUBSC 0.46): thresholds that no posture satisfies,
# muscles that saturate against each other.
#
#   lt       live tracking (1 both sides, 2 backhand only, 3 forehand only): the arm's muscle
#            thresholds come from the muscles' measured contractions and live
#            moment arms (the task's arm_mom block, sent when lt_arms is 1):
#            c*_m = c_m - sum_j arm_mj / range_m (q*_j - q_j) + stiff / 2,
#            q* the arm chunk's joint-space goal (the side's posture, its
#            stroke's goal) eased from the posture measured when the chunk
#            began, plus the servo's joint corrections; the servo's own
#            offsets on the arm (reference slopes) are dropped. Families and
#            flicks keep the old map.
#   lt_ff    with lt: the gravity feed-forward's gain on the arm (the
#            controller's internal model), the arm's muscles only
#   rd       a learned residual on the reflex law's drive term (1 on): per
#            side, a 9-12-3 tanh network (weights rdw0..rdw317, side s from
#            159 s; the same inputs as rn) gives three signed drives, each
#            bounded by rd_lim: pronation (+: PT, PQ; -: SUP), wrist flexion
#            (+: FCR, FCU, PL; -: ECRL, ECRB, ECU) and ulnar deviation (+: FCU,
#            ECU; -: ECRL, FCR), added as feed-forward activation (a negative
#            drive inhibits: under the saturating co-contraction a contraction
#            offset changes nothing, a drive below zero does) from rn_t0 s to
#            contact; trained by evolution strategies on training serves

+ MyoTTV10Skill < MyoTTV9Skill
  -> read_params
    super
    @lt = param("lt", ~0.0, ~0.0, ~3.0)
    @lt_arms = param("lt_arms", ~0.0, ~0.0, ~1.0)
    @lt_ff = param("lt_ff", ~0.0, ~0.0, ~1.5)
    @lt_ch = ""
    @lt_ok = false
    @lt_qs = nil
    @lt_qg = nil
    @lt_qstroke = nil
    @rd = param("rd", ~0.0, ~0.0, ~1.0)
    @rd_lim = param("rd_lim", ~0.6, ~0.0, ~1.0)
    @rdw = (0...318).map ->(i) param("rdw[i]", ~0.0, ~-10.0, ~10.0)
    @rd_o = [~0.0, ~0.0, ~0.0]

  -> start(frame, ctl)
    super(frame, ctl)
    g = body.geometry
    @lt_range = (0...body.size).map ->(m) ~1.0
    @arm_mask.each ->(m)
      r = g.range(m)
      @lt_range[m] = r[1] - r[0]
    ctl.enable_feedforward(@arm_mask, @lt_ff) if @lt > ~0.5 && @lt_ff > ~0.0
    @rd_m = [names_mask(["PT", "PQ"]), names_mask(["SUP"]), names_mask(["FCR", "FCU", "PL"]), names_mask(["ECRL", "ECRB", "ECU"]), names_mask(["FCU", "ECU"]), names_mask(["ECRL", "FCR"])]
    nil

  -> lt_side_on
    return false if @lt < ~0.5 || @side == 0
    return @side == 1 if @lt > ~2.5
    return @side == 2 if @lt > ~1.5
    true

  -> q_now(f)
    MyoTTKin.servo_joints.map ->(nm) f.q(body, nm)

  # The joint-space goal of the arm chunk that is running (nil: not tracked).
  -> lt_goal(name)
    fh = [@q_ready[0], @q_ready[1], @q_ready[2], @q_ready[3], @q_ready[4], @q_ready[5], @q_ready[6], @trunk_q[2]]
    if name == "ready"
      return fh
    if name == "stroke" || name == "follow" || name == "hold"
      return @lt_qstroke if @lt_qstroke != nil
      return fh
    bq = @q_bh
    bq = @q_set if name == "bh_set"
    bh = [bq[0], bq[1], bq[2], bq[3], bq[4], bq[5], bq[6], @trunk_bh[2]]
    return bh if name == "bh_ready" || name == "bh_set"
    if name == "bh_stroke" || name == "bh_follow" || name == "bh_hold"
      return @lt_qstroke if @lt_qstroke != nil
      return bh
    nil

  # The single stroke's joint goal (the side's posture plus the push along
  # the push vector, as stroke_due sets the chunk's pose), for live tracking.
  -> stroke_due(f)
    r = super(f)
    if r && @lt > ~0.5 && !((fam_side_on && @fam > 0) || @fam >= 5)
      side_q = @q_ready
      tr = @trunk_q[2]
      dpush = @d_push
      if @side == 2
        side_q = @q_set
        tr = @trunk_bh[2]
        dpush = @d_push + @bh_dd_push
      pv = push_vector(f)
      q = (0...7).map ->(i) side_q[i] + pv[i] * dpush
      q.push(tr)
      @lt_qstroke = q
    r

  -> servo_offsets(f)
    off = super(f)
    if lt_side_on && @lt_ok
      @arm_mask.each ->(m) off[m] = ~0.0
    off

  -> after(f, ctl)
    super(f, ctl)
    live_track(f, ctl) if lt_side_on && f.has?("arm_mom")
    drive_residual(f, ctl) if @rd > ~0.5
    nil

  -> drive_residual(f, ctl)
    s = @side
    return nil if s == 0 || @plan == nil || @hit || f.t < @rn_t0
    n = pad_normal(f)
    a = aim_normal(@plan)
    pc = pad_center(f)
    x = [a[1] - n[1], a[2] - n[2], @plan[2] + @z_bias - pc[2], @plan[0] - ~0.1, n[1], n[2], a[1], a[2], ~1.0]
    b = 159 * (s - 1)
    h = []
    j = 0
    while j < 12
      acc = @rdw[b + 108 + j]
      i = 0
      while i < 9
        acc = acc + @rdw[b + 9 * j + i] * x[i]
        i += 1
      h.push(Math.tanh(acc))
      j += 1
    k = 0
    while k < 3
      acc = @rdw[b + 156 + k]
      j = 0
      while j < 12
        acc = acc + @rdw[b + 120 + 12 * k + j] * h[j]
        j += 1
      o = @rd_lim * Math.tanh(acc)
      @rd_o[k] = o
      pos = @rd_m[2 * k]
      neg = @rd_m[2 * k + 1]
      if o > ~0.0
        pos.each ->(m) ctl.add_drive(m, o)
        neg.each ->(m) ctl.add_drive(m, ~0.0 - o)
      else
        neg.each ->(m) ctl.add_drive(m, ~0.0 - o)
        pos.each ->(m) ctl.add_drive(m, o)
      k += 1
    nil

  -> live_track(f, ctl)
    tr = ctl.track("arm")
    ch = tr.chunk
    return nil if ch == nil
    name = ch.name
    if name != @lt_ch
      @lt_ch = name
      @lt_t0 = f.t
      @lt_qs = q_now(f)
      @lt_qg = lt_goal(name)
      @lt_dur = ch.duration
      @lt_ez = ch.easing
    @lt_ok = @lt_qg != nil
    return nil if !@lt_ok
    p = ~1.0
    p = Easing.apply(@lt_ez, (f.t - @lt_t0) / @lt_dur) if @lt_dur > ~0.0 && f.t - @lt_t0 < @lt_dur
    qn = q_now(f)
    dq = (0...8).map ->(j) @lt_qs[j] + (@lt_qg[j] - @lt_qs[j]) * p + @q_corr[j] - qn[j]
    st = @stiff
    st = @fh_stiff if @side == 1 && @fh_stiff >= ~0.0
    st = @bs if @side == 2
    cmd = ctl.command
    i = 0
    while i < @arm_mask.size
      m = @arm_mask[i]
      acc = f.c(m) + st * ~0.5
      j = 0
      while j < 8
        acc = acc - f.at("arm_mom", 8 * i + j) / @lt_range[m] * dq[j]
        j += 1
      ctl.add_offset(m, acc - cmd[m])
      i += 1
    nil
