# MyoTTV8: round-7 options for the table-tennis skill (MyoTTV7Skill), each
# opt-in by params; with every switch at 0 it is MyoTTV7Skill (and so the
# round-5 champions).
#
# Always (a report only, no effect on the play): at the servo's lock the
# skill emits "l8:" with the side, the aim law's landing target, the plan
# (time to the pad's plane, crossing y and z, the ball's velocity there),
# the pad plane's x, the pad's measured normal and the aim law's normal, and
# the learned model's seven outputs (lm below), so practice can fit what the
# aim law gets wrong.

#
#   lm       a learned contact model's corrections (1 on): per side, seven
#            linear maps of the serve's features phi = [1, contact time - 0.53,
#            crossing y, crossing z - 1.2, vx - 5, vy, vz, pad plane x - 1.8]
#            (the plan's crossing, from what is seen), weights lm0..lm111
#            (side s, output k, feature i at 56 s + 8 k + i): outputs 0-1
#            shift the aim law's landing target (x, y, m), 2-4 the pad
#            velocity the aim law expects at contact (m/s), 5-6 trim the aim
#            law's normal (y, z components). Fitted from training rollouts:
#            the pad's velocity at contact, the face it reached against the
#            aim, and where the return came down against the target.
#   lc       the contact point's learned centring (see lc_update)
#   sd       side choice by a learned classifier (1 on): backhand when
#            sd0 + sd1..sd7 . phi[1..7] > 0 (the same features), instead of
#            the crossing's side of y_switch
#   gp       the backhand's grasp (1 on): pinch emphasis (the thumb's FPL and
#            OP thresholds gp_th shorter, the index's gp_ix, the other
#            fingers' gp_rest), and the wrist's extensors (gp_we) and
#            flexors (gp_wf) driven from gp_w0 s before the predicted contact
#            to gp_w1 s after it (co-activation that keeps the grip's pull
#            from flexing the wrist then)

+ MyoTTV8Skill < MyoTTV7Skill
  -> read_params
    super
    @lm = param("lm", ~0.0, ~0.0, ~1.0)
    @lm_g = param("lm_g", ~1.0, ~0.0, ~1.5)
    @lmw = (0...112).map ->(i) param("lm[i]", ~0.0, ~-5.0, ~5.0)
    @sd = param("sd", ~0.0, ~0.0, ~1.0)
    @sdw = (0...8).map ->(i) param("sd[i]", ~0.0, ~-20.0, ~20.0)
    @gp = param("gp", ~0.0, ~0.0, ~1.0)
    @gp_th = param("gp_th", ~0.0, ~-0.3, ~0.5)
    @gp_ix = param("gp_ix", ~0.0, ~-0.3, ~0.5)
    @gp_rest = param("gp_rest", ~0.0, ~-0.5, ~0.3)
    @gp_we = param("gp_we", ~0.0, ~0.0, ~1.0)
    @gp_wf = param("gp_wf", ~0.0, ~0.0, ~1.0)
    @gp_w0 = param("gp_w0", ~0.1, ~0.0, ~0.6)
    @gp_w1 = param("gp_w1", ~0.05, ~0.0, ~0.3)
    @lm_out = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    @lc = param("lc", ~0.0, ~0.0, ~1.0)
    @lcw = (0...32).map ->(i) param("lc[i]", ~0.0, ~-5.0, ~5.0)
    @lc_out = [~0.0, ~0.0]
    @z_bias0 = @z_bias
    @y_trim0 = @y_trim
    @bh_y_trim0 = @bh_y_trim

  -> start(frame, ctl)
    super(frame, ctl)
    @gp_th_m = names_mask(["FPL", "OP"])
    @gp_ix_m = names_mask(["FDS2", "FDP2", "RI2", "LU_RB2", "UI_UB2"])
    @gp_rest_m = names_mask(["FDS3", "FDP3", "RI3", "LU_RB3", "UI_UB3", "FDS4", "FDP4", "RI4", "LU_RB4", "UI_UB4", "FDS5", "FDP5", "RI5", "LU_RB5", "UI_UB5"])
    @gp_we_m = names_mask(["ECRL", "ECRB", "ECU"])
    @gp_wf_m = names_mask(["FCR", "FCU", "PL"])

  # ---- the serve's features -----------------------------------------------------------

  -> serve_phi(f, plan)
    [~1.0, f.t + plan[0] - ~0.53, plan[1], plan[2] - ~1.2, plan[3] - ~5.0, plan[4], plan[5], @xp - ~1.8]

  # ---- the learned contact model ---------------------------------------------------------

  -> before(f, ctl)
    lm_update(f) if @lm > ~0.5 && @plan != nil && !@locked
    lc_update(f) if @lc > ~0.5 && @plan != nil && !@locked
    super(f, ctl)
    nil

  # lc 1: the contact point's learned centring: per side, the pad's height
  # target (z_bias) and the slide's lateral trim move by linear maps of phi
  # (weights lc0..lc31: side s, output k (0 height, 1 lateral), feature i at
  # 16 s + 8 k + i), fitted from where the ball met the pad in training
  # rollouts (hits within 3 cm of the pad's centre solve 67% on the
  # forehand, 6-9 cm off 31%, and every hit 9 cm or more off is a rim hit)
  -> lc_update(f)
    s = @side
    return nil if s == 0
    phi = serve_phi(f, @plan)
    base = 16 * (s - 1)
    k = 0
    while k < 2
      acc = ~0.0
      i = 0
      while i < 8
        acc = acc + @lcw[base + 8 * k + i] * phi[i]
        i += 1
      @lc_out[k] = acc
      k += 1
    @z_bias = @z_bias0 + @lc_out[0]
    @y_trim = @y_trim0 + @lc_out[1]
    @bh_y_trim = @bh_y_trim0 + @lc_out[1]
    nil

  -> lm_update(f)
    s = @side
    return nil if s == 0
    phi = serve_phi(f, @plan)
    base = 56 * (s - 1)
    k = 0
    while k < 7
      acc = ~0.0
      i = 0
      while i < 8
        acc = acc + @lmw[base + 8 * k + i] * phi[i]
        i += 1
      @lm_out[k] = @lm_g * acc
      k += 1
    nil

  -> choose_target(plan, n)
    super(plan, n)
    if @lm > ~0.5 && @side != 0
      @tx = @tx + @lm_out[0]
      @ty = @ty + @lm_out[1]
    nil

  -> pad_vel_expected
    v = super
    return v if @lm < ~0.5 || @side == 0 || (fam_side_on && @fam > 0) || @fam >= 5
    [v[0] + @lm_out[2], v[1] + @lm_out[3], v[2] + @lm_out[4]]

  -> aim_normal(plan)
    n = super(plan)
    return n if @lm < ~0.5 || @side == 0
    m = [n[0], n[1] + @lm_out[5], n[2] + @lm_out[6]]
    r = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
    [m[0] / r, m[1] / r, m[2] / r]

  # ---- side choice ------------------------------------------------------------------------

  -> choose_side(f)
    return super(f) if @sd < ~0.5
    return @side if @side != 0
    return 0 if @plan == nil
    @t_side = f.t
    phi = serve_phi(f, @plan)
    acc = ~0.0
    i = 0
    while i < 8
      acc = acc + @sdw[i] * phi[i]
      i += 1
    side = 1
    side = 2 if acc > ~0.0
    set_side(side)
    @side

  # ---- the backhand's grasp ------------------------------------------------------------------

  -> after(f, ctl)
    super(f, ctl)
    grasp_shape(f, ctl) if @gp > ~0.5 && @side == 2
    nil

  -> grasp_shape(f, ctl)
    @gp_th_m.each ->(m) ctl.add_offset(m, @gp_th)
    @gp_ix_m.each ->(m) ctl.add_offset(m, @gp_ix)
    @gp_rest_m.each ->(m) ctl.add_offset(m, @gp_rest)
    return nil if @t_cpred < ~0.0 || f.t < @t_cpred - @gp_w0
    return nil if @t_hit_at >= ~0.0 && f.t > @t_hit_at + @gp_w1
    @gp_we_m.each ->(m) ctl.add_drive(m, @gp_we)
    @gp_wf_m.each ->(m) ctl.add_drive(m, @gp_wf)
    nil
  -> lock_now(ctl)
    super(ctl)
    emit_lock(ctl) if @plan != nil
    nil

  -> emit_lock(ctl)
    p = @plan
    n = @n_last
    n = [~0.0, ~0.0, ~0.0] if n == nil
    a = @a_last
    a = [~0.0, ~0.0, ~0.0] if a == nil
    o = @lm_out
    vals = [@side.to_f, @tx, @ty, p[0], p[1], p[2], p[3], p[4], p[5], @xp, n[0], n[1], n[2], a[0], a[1], a[2], o[0], o[1], o[2], o[3], o[4], o[5], o[6], @lc_out[0], @lc_out[1]]
    ctl.emit("l8:" + vals.map(->(x) x.to_s).join(":"))
    nil

  # the pad's normal and the aim law's, as the servo last saw them
  -> servo(f, pc, plan, ey)
    super(f, pc, plan, ey)
    @n_last = pad_normal(f)
    @a_last = aim_normal(plan)
    nil
