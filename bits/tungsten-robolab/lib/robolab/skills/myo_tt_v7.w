# MyoTTV7: round-6 options for the table-tennis skill (MyoTTSkill), each
# opt-in by params; with every switch at 0 it is MyoTTSkill.
#
# Round-5 traces of the backhand: the arm crosses the body at up to 6 m/s
# toward a posture it cannot reach (the plane of elevation commanded -1.2,
# reached 0.3; the shoulder's elevation commanded 0.64, sagging to 0.1 by
# contact), every forearm muscle saturated by the co-contraction (stiff 0.11
# with the arm's reflex gain asks ~1.4 activation of each), so the face is
# still turning at contact; and the paddle turns in the fingers (66 deg in
# the first 0.13 s as the grip closes, a further 20-40 deg from 0.25 s to
# contact): the finger flexors close past their thresholds, their stretch
# reflex goes negative and cancels the grip's tonic drive (mean flexor
# activation 0.9 at 0.15 s, 0.35 at contact).
#
#   gsq      grip squeeze (1 backhand, 2 both sides): from gsq_lead s before
#            the predicted contact until gsq_hold s after it, the finger and
#            thumb flexors get gsq_drv of drive and their thresholds gsq_c
#            shorter (so the reflex adds to the drive however far they have
#            closed), the intrinsics gsq_int of drive, and the finger
#            extensors' thresholds gsq_ext longer (relaxed); gsq_t0 > 0
#            starts it at that absolute time instead
#   b7_ff    the internal-model gravity feed-forward on the arm (gain), for
#            the backhand only: a low-co-contraction arm holds its posture
#            without the reflexes waiting for gravity to open an error
#   b7_tb    the backhand's transfer burst (triphasic): for b7_tb s after the
#            side is chosen, the arm muscles the backhand posture shortens
#            get up to b7_ta of drive (full at a contraction change of
#            b7_tsc), then for b7_tbrk s the ones it lengthens get up to
#            b7_tba (the brake), the arm's reflex gain times b7_tg meanwhile
#            (the antagonists' stretch reflex would fight the burst)
#   b7_sff   the backhand's static drive: the activations b7_a0..b7_a31 (the
#            arm muscles, MyoTTKin order) that hold its posture against
#            gravity and the passive pull of stretched muscles (solved
#            offline: the posture's static torques met by the nonnegative
#            minimum-norm activations), times b7_sff, eased in over b7_sr
#            from b7_st s after the side is chosen. The equilibrium-point
#            reflexes alone hold a posture only once its error has grown
#            enough to recruit that much (a sag), and the backhand's
#            passive loads are large (shoulder rotation ~10 N m, elbow ~10)
#   gcp      the grip follows the arm (1 backhand, 2 both sides): every hand
#            muscle's threshold moves by the change of its contraction that
#            the arm's joints (shoulder to wrist) make from the start posture
#            with the fingers held (the geometry's length tables); the finger
#            muscles cross the wrist, so without it a wrist flexing from
#            -0.75 to +0.4 slackens the grip (flexor activation 0.9 -> 0.35)
#            and the paddle turns in the hand. glk_w 1: the grip lock
#            follows the arm the same way from its lock posture
#   bh_vpe   the backhand's aim law expects a moving pad: (bh_vpx, bh_vpy,
#            bh_vpz) m/s plus bh_kvpm of the measured pad velocity
#   pw       power strokes (the stroke families, the flick and the scoop): a
#            burst on the prime movers timed from the stroke's firing
#            (pw_t0, pw_t, pw_a, pw_sc), the antagonists inhibited (pw_inh)
#            and their reflex gain lowered (pw_g) meanwhile, then an
#            optional brake (pw_brk, pw_ba)
#   sc_fwd   the corrected low scoop: the pad up and forward (sc_a) across
#            the back of the ball; sc_phi >= 0 closes its face that far
#   bh_tk    the backhand's posture per serve: the practised posture plus
#            bh_tq_* per second of predicted contact time after bh_tc0 and
#            bh_zq_* per metre of crossing height above bh_zc0 (bh_tk 2: the
#            time term only for contacts earlier than bh_tc0)
#   bh_tmin  the backhand's contact no earlier than bh_tmin s: the pad plane
#            moves back (up to bh_tx beyond its range) until the ball
#            reaches it then
#   fc_open  the angle sweeps: the face fixed fc_open rad open (- closed),
#            its yaw the aim law's (any stroke); fh_open / bh_open the same
#            for one side's single stroke (the block); ch_open / fl_open / sc_open
#            the same for the chop, the flick and the scoop alone (the sweeps'
#            best angles as opt-in stroke settings); ap_on 1: the ball met
#            ap_dz m below its bounce's apex (the height matching's target)
#   glk      grip lock (1 backhand, 2 both sides): from glk_t s the hand holds
#            the finger posture it has then (every hand muscle's threshold at
#            its measured contraction, plus glk_s co-contraction), the grip
#            chunk's drive replaced by a tonic glk_d, the hand's reflex gain
#            times glk_g. A harder squeeze turns the paddle further (the
#            curling fingers roll the handle: gsq 1 from 0.02 s, slip 19 ->
#            34 deg): the grip must hold still, not close

+ MyoTTV7Skill < MyoTTSkill
  -> read_params
    super
    @gsq = param("gsq", ~0.0, ~0.0, ~2.0)
    @gsq_lead = param("gsq_lead", ~0.1, ~0.0, ~1.5)
    @gsq_hold = param("gsq_hold", ~0.1, ~0.0, ~0.5)
    @gsq_t0 = param("gsq_t0", ~0.0, ~0.0, ~1.0)
    @gsq_drv = param("gsq_drv", ~1.0, ~0.0, ~1.0)
    @gsq_c = param("gsq_c", ~0.3, ~0.0, ~1.0)
    @gsq_int = param("gsq_int", ~0.0, ~0.0, ~1.0)
    @gsq_ext = param("gsq_ext", ~0.0, ~0.0, ~0.5)
    @b7_ff = param("b7_ff", ~0.0, ~0.0, ~1.5)
    @b7_tb = param("b7_tb", ~0.0, ~0.0, ~0.3)
    @b7_ta = param("b7_ta", ~0.5, ~0.0, ~1.0)
    @b7_tbrk = param("b7_tbrk", ~0.0, ~0.0, ~0.3)
    @b7_tba = param("b7_tba", ~0.3, ~0.0, ~1.0)
    @b7_tg = param("b7_tg", ~1.0, ~0.0, ~2.0)
    @b7_tsc = param("b7_tsc", ~0.1, ~0.01, ~0.5)
    @glk = param("glk", ~0.0, ~0.0, ~2.0)
    @glk_t = param("glk_t", ~0.2, ~0.0, ~1.0)
    @glk_s = param("glk_s", ~0.1, ~0.0, ~0.6)
    @glk_d = param("glk_d", ~0.0, ~0.0, ~1.0)
    @glk_g = param("glk_g", ~1.0, ~0.2, ~5.0)
    @b7_sff = param("b7_sff", ~0.0, ~0.0, ~1.5)
    @b7_st = param("b7_st", ~0.0, ~0.0, ~0.8)
    @b7_sr = param("b7_sr", ~0.1, ~0.01, ~0.5)
    @b7_a = (0...32).map ->(i) param("b7_a[i]", ~0.0, ~0.0, ~1.0)
    @gcp = param("gcp", ~0.0, ~0.0, ~2.0)
    @bh_vpe = param("bh_vpe", ~0.0, ~0.0, ~1.0)
    @bh_vpx = param("bh_vpx", ~0.0, ~-2.0, ~2.0)
    @bh_vpy = param("bh_vpy", ~0.0, ~-2.0, ~2.0)
    @bh_vpz = param("bh_vpz", ~0.0, ~-2.0, ~2.0)
    @bh_kvpm = param("bh_kvpm", ~0.0, ~0.0, ~1.5)
    @pw = param("pw", ~0.0, ~0.0, ~1.0)
    @pw_a = param("pw_a", ~1.0, ~0.0, ~1.0)
    @pw_sc = param("pw_sc", ~0.03, ~0.005, ~0.2)
    @pw_t0 = param("pw_t0", ~0.0, ~-0.1, ~0.2)
    @pw_t = param("pw_t", ~0.12, ~0.02, ~0.4)
    @pw_inh = param("pw_inh", ~0.5, ~0.0, ~1.0)
    @pw_g = param("pw_g", ~0.3, ~0.0, ~2.0)
    @pw_brk = param("pw_brk", ~0.0, ~0.0, ~0.3)
    @pw_ba = param("pw_ba", ~0.5, ~0.0, ~1.0)
    @pw_all = param("pw_all", ~0.0, ~0.0, ~1.0)
    @fc_open = param("fc_open", ~-9.0, ~-9.0, ~1.5)
    @fh_open = param("fh_open", ~-9.0, ~-9.0, ~1.5)
    @bh_open = param("bh_open", ~-9.0, ~-9.0, ~1.5)
    @ap_on = param("ap_on", ~0.0, ~0.0, ~1.0)
    @ap_dz = param("ap_dz", ~0.0, ~-0.2, ~0.6)
    @sc_fwd = param("sc_fwd", ~0.0, ~0.0, ~1.0)
    @sc_a = param("sc_a", ~0.8, ~0.0, ~1.5)
    @sc_phi = param("sc_phi", ~-1.0, ~-1.0, ~1.5)
    @glk_w = param("glk_w", ~0.0, ~0.0, ~1.0)
    @bh_tk = param("bh_tk", ~0.0, ~0.0, ~2.0)
    @bh_tc0 = param("bh_tc0", ~0.53, ~0.3, ~0.8)
    @bh_tq = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex", "trunk"].map ->(nm) param("bh_tq_" + nm, ~0.0, ~-8.0, ~8.0)
    @bh_zq = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex", "trunk"].map ->(nm) param("bh_zq_" + nm, ~0.0, ~-8.0, ~8.0)
    @bh_zc0 = param("bh_zc0", ~1.2, ~0.9, ~1.5)
    @bh_tmin = param("bh_tmin", ~0.0, ~0.0, ~0.8)
    @bh_tx = param("bh_tx", ~0.0, ~0.0, ~0.5)
    # st_best 1: the round-6 angle sweeps' best settings as the strokes'
    # defaults (each still overridable): the chop's face 60 deg open as
    # commanded (reached: backhand -4, forehand +43) on a path 40 deg down;
    # the flick's face vertical on a path 20 deg up; the scoop up and forward
    # at 70 deg with its face 15 deg closed (its topspin variant)
    @st_best = param("st_best", ~0.0, ~0.0, ~1.0)
    sb = @st_best > ~0.5
    d_ch = ~-9.0
    d_fl = ~-9.0
    d_sc = ~-9.0
    if sb
      d_ch = ~1.047
      d_fl = ~0.0
      d_sc = ~-0.262
      @chop_down = ~0.698 if !params.key?("chop_down")
      @fl_a = ~0.349 if !params.key?("fl_a")
      @sc_a = ~1.222 if !params.key?("sc_a")
      @sc_fwd = ~1.0 if !params.key?("sc_fwd")
    @ch_open = param("ch_open", d_ch, ~-9.0, ~1.5)
    @fl_open = param("fl_open", d_fl, ~-9.0, ~1.5)
    @sc_open = param("sc_open", d_sc, ~-9.0, ~1.5)

  -> start(frame, ctl)
    super(frame, ctl)
    @t_cpred = ~-1.0
    @t_hit_at = ~-1.0
    @sq_flex = names_mask(["FDS5", "FDS4", "FDS3", "FDS2", "FDP5", "FDP4", "FDP3", "FDP2", "FPL", "OP"])
    @sq_int = names_mask(["RI2", "LU_RB2", "UI_UB2", "RI3", "LU_RB3", "UI_UB3", "RI4", "LU_RB4", "UI_UB4", "RI5", "LU_RB5", "UI_UB5"])
    @sq_ext = names_mask(["EDC5", "EDC4", "EDC3", "EDC2", "EDM", "EIP"])
    @tr_d = nil
    @c_lock = nil
    @q_lock = nil
    @vp7 = [~0.0, ~0.0, ~0.0]
    @pw_off = nil
    @pw_fire = ~0.0
    g = body.geometry
    @arm_j = MyoTTKin.arm_joints.map ->(nm) g.joint(nm)
    @q_gc = frame.vec("q").map -> item
    @c_gc = @hand_mask.map ->(m) g.contraction(m, @q_gc)

  -> set_side(side)
    super(side)
    serve_posture if side == 2 && @bh_tk > ~0.5 && @plan != nil
    if side == 2
      @ctl.enable_feedforward(@arm_mask, @b7_ff) if @b7_ff > ~0.0
      transfer_plan if @b7_tb > ~0.0
    nil

  -> before(f, ctl)
    super(f, ctl)
    @t_cpred = f.t + @plan[0] if @plan != nil
    if @bh_kvpm > ~0.0
      vw = paddle_velocity(f)
      i = 0
      while i < 3
        @vp7[i] = @vp7[i] + (vw[i] - @vp7[i]) * ~0.3
        i += 1
    @t_hit_at = f.t if @hit && @t_hit_at < ~0.0
    nil

  # (the parent's before() sets the height-matching goal @gx, then drives the
  # pelvis: the late-contact adjustment goes in between)
  -> drive_pelvis(f)
    apex_contact(f) if @ap_on > ~0.5 && !@locked && @plan != nil && @g_hx > ~0.0
    late_contact(f) if @bh_tmin > ~0.0 && @side == 2 && !@locked && @plan != nil && @g_hx > ~0.0
    super(f)

  # ap_on 1: the height matching meets the ball ap_dz m below the apex of
  # its bounce (on the rise; ap_dz 0: at the apex) instead of at z_hit.
  -> apex_contact(f)
    p = [f.at("env_ball_pos", 0), f.at("env_ball_pos", 1), f.at("env_ball_pos", 2)]
    v = [f.at("env_ball_vel", 0), f.at("env_ball_vel", 1), f.at("env_ball_vel", 2)]
    vz = v[2]
    if !@bounced
      c = p[2] - ~0.805
      disc = v[2] * v[2] + ~2.0 * ~9.81 * c
      return nil if disc < ~0.0
      tb = (v[2] + Math.sqrt(disc)) / ~9.81
      vz = ~0.0 - (v[2] - ~9.81 * tb) * ~0.99
      apex = ~0.805 + vz * vz / (~2.0 * ~9.81)
    else
      apex = p[2] + clamp(vz, ~0.0, ~50.0) * clamp(vz, ~0.0, ~50.0) / (~2.0 * ~9.81)
    zt = apex - @ap_dz
    xh = MyoTTBall.at_height(p, v, zt, @bounced)
    return nil if xh == nil
    xhi = @x_hi
    xhi = @x_hi + @bh_dx_hi if @side == 2
    xw = clamp(xh, @x_lo, xhi)
    pel_x = f.at("env_pelvis_pos", 0)
    want_x = pel_x + (xw - @xp)
    @gx = @gx0 + @g_hx * (~1.6 - want_x - @gx0)
    nil

  # ---- the backhand meets the ball no earlier than bh_tmin -------------------------

  # bh_tmin > 0: the backhand's pad plane (the fore-aft height matching's
  # choice) moves back, up to bh_tx beyond x_hi (+ bh_dx_hi), until the ball
  # reaches it no earlier than bh_tmin s: on the trial's backhands, contacts
  # at 0.55-0.62 s solve 20 of 34, at 0.44-0.52 s 5 of 36 (fast serves met
  # low while the swing still turns the face and moves the pad).
  -> late_contact(f)
    p = [f.at("env_ball_pos", 0), f.at("env_ball_pos", 1), f.at("env_ball_pos", 2)]
    v = [f.at("env_ball_vel", 0), f.at("env_ball_vel", 1), f.at("env_ball_vel", 2)]
    tt = @bh_tmin - f.t
    return nil if tt <= ~0.0
    x = p[0] + v[0] * tt
    if !@bounced
      c = p[2] - ~0.805
      disc = v[2] * v[2] + ~2.0 * ~9.81 * c
      if disc >= ~0.0
        tb = (v[2] + Math.sqrt(disc)) / ~9.81
        x = p[0] + v[0] * tb + ~0.996 * v[0] * (tt - tb) if tt > tb
    zt = @z_hit + @hx_pad * (pad_center(f)[2] - @z_hit) + @bh_dz_hit
    xhi = @x_hi + @bh_dx_hi
    xh = MyoTTBall.at_height(p, v, zt, @bounced)
    return nil if xh == nil
    xw = clamp(xh, @x_lo, xhi)
    return nil if x <= xw
    xw = clamp(x, @x_lo, xhi + @bh_tx)
    pel_x = f.at("env_pelvis_pos", 0)
    want_x = pel_x + (xw - @xp)
    @gx = @gx0 + @g_hx * (~1.6 - want_x - @gx0)
    nil

  -> after(f, ctl)
    super(f, ctl)
    grip_squeeze(f, ctl) if @gsq > ~0.5 && @side != 0 && (@side == 2 || @gsq > ~1.5)
    transfer_burst(f, ctl) if @tr_d != nil
    grip_lock(f, ctl) if @glk > ~0.5 && @side != 0 && (@side == 2 || @glk > ~1.5)
    static_drive(f, ctl) if @b7_sff > ~0.0 && @side == 2
    grip_follow(f, ctl) if @gcp > ~0.5 && @side != 0 && (@side == 2 || @gcp > ~1.5)
    power_burst(f, ctl) if @pw_off != nil
    nil

  # ---- power strokes -----------------------------------------------------------------

  # The stroke family's joint change (as fam_stroke sets it: the pad along
  # the family's direction, the normal held), kept as each arm muscle's
  # contraction change for the power burst.
  -> fam_stroke(f)
    r = super(f)
    if @pw > ~0.5
      dir = @fam_dir
      pv = push_vector_dir(f, dir[0], dir[2])
      pv = push_vector_wrist(f, dir[0], dir[2]) if @fam == 5
      off = zeros
      names = MyoTTKin.arm_joints
      i = 0
      while i < 7
        joint_move(off, names[i], pv[i] * @fam_d)
        i += 1
      @pw_off = off
      @pw_fire = f.t
    r

  # pw 1: the stroke is struck with power, timed to the contact: from pw_t0 s
  # after it fires, for pw_t s, the muscles its joint change shortens get up
  # to pw_a of drive (full at a contraction change of pw_sc) and the ones it
  # lengthens are inhibited (pw_inh) with their reflex gain set to pw_g (their
  # stretch reflex would brake the swing; the rest of the arm keeps its
  # reflexes, which hold it up against gravity; pw_all 1: the whole arm's
  # gain drops, the wrist-only flick's choice); then for pw_brk s
  # the lengthened ones brake (pw_ba) the follow-through.
  -> power_burst(f, ctl)
    e = f.t - @pw_fire - @pw_t0
    return nil if e < ~0.0 || e > @pw_t + @pw_brk
    off = @pw_off
    brake = e > @pw_t
    @arm_mask.each ->(m)
      x = off[m] / @pw_sc
      if brake
        ctl.add_drive(m, @pw_ba * clamp(~0.0 - x, ~0.0, ~1.0)) if x < ~0.0
      else
        if x > ~0.0
          ctl.add_drive(m, @pw_a * clamp(x, ~0.0, ~1.0))
        elsif x < ~0.0
          ctl.add_drive(m, ~0.0 - @pw_inh * clamp(~0.0 - x, ~0.0, ~1.0))
        ctl.set_gain(m, @pw_g) if x < ~0.0 || @pw_all > ~0.5
    nil

  # ---- the scoop, corrected ------------------------------------------------------------

  # sc_fwd 1: the low scoop's pad moves up and forward (sc_a above the
  # horizontal, toward the opponent) across the back of the ball instead of
  # up and back: the round-5 scoop (the pad moving back toward the player at
  # under 1 m/s, face open) let the incoming ball's own speed along the face
  # drag its underside toward the player: backspin.
  -> set_family(k)
    super(k)
    if k == 6 && @sc_fwd > ~0.5
      dir = [~0.0 - Math.cos(@sc_a), ~0.0, Math.sin(@sc_a)]
      @fam_dir = dir
      sp = @k_ach * @fam_d / (@t_hit + @t_fol)
      @fam_vp = [sp * dir[0] + @vp[0], sp * dir[1] + @vp[1], sp * dir[2] + @vp[2]]
    nil

  # sc_phi >= 0: the scoop's face is closed sc_phi rad (its normal toward
  # the ball pointing that far below the horizontal: the pad meets the upper
  # back of the ball), its yaw the aim law's. fc_open > -8 (any stroke; the
  # angle sweeps): the face fixed fc_open rad open (+: the normal toward the
  # ball tilted up; -: closed) instead of the aim law's pitch. The skill's
  # normals point toward the player (x > 0), so an open face has n_z < 0.
  -> aim_normal(plan)
    n = super(plan)
    op = @fc_open
    op = @fh_open if @side == 1 && @fam == 0 && @fh_open > ~-8.0
    op = @bh_open if @side == 2 && @fam == 0 && @bh_open > ~-8.0
    op = @ch_open if @fam == 3 && @ch_open > ~-8.0
    op = @fl_open if @fam == 5 && @fl_open > ~-8.0
    op = @sc_open if @fam == 6 && @sc_open > ~-8.0
    op = ~0.0 - @sc_phi if @fam == 6 && @sc_phi >= ~0.0 && op < ~-8.0
    return n if op < ~-8.0
    h = Math.sqrt(n[0] * n[0] + n[1] * n[1])
    c = Math.cos(op)
    [c * n[0] / h, c * n[1] / h, ~0.0 - Math.sin(op)]

  # ---- the grip follows the wrist ----------------------------------------------------

  # The finger muscles cross the wrist and elbow: as the arm moves, their
  # contraction changes with the finger posture unchanged (a wrist flexed
  # from -0.75 to +0.4 shortens the finger flexors past their grip
  # thresholds, their reflex drops out and the paddle turns). How much each
  # hand muscle's contraction changes when the arm joints move from q0 to
  # the measured posture, the finger joints held (the geometry's length
  # tables).
  -> arm_shift(f, q0, c0)
    g = body.geometry
    qn = f.vec("q")
    qa = q0.map -> item
    @arm_j.each ->(j) qa[j] = qn[j]
    out = zeros
    i = 0
    while i < @hand_mask.size
      m = @hand_mask[i]
      out[m] = g.contraction(m, qa) - c0[i]
      i += 1
    out

  # gcp: the grip's thresholds move with the arm (from the start posture),
  # so the practised grip keeps its hold whatever the wrist does.
  -> grip_follow(f, ctl)
    return nil if @glk > ~0.5 && @c_lock != nil
    d = arm_shift(f, @q_gc, @c_gc)
    @hand_mask.each ->(m) ctl.add_offset(m, d[m])
    nil

  # ---- the backhand's static drive -----------------------------------------------------

  # The activations that hold the backhand's posture still against gravity
  # and the stretched muscles' passive pull (b7_a0..b7_a31, the arm muscles
  # in MyoTTKin order; solved offline for the posture), times b7_sff,
  # eased in over b7_sr from b7_st s after the side is chosen.
  -> static_drive(f, ctl)
    w = clamp((f.t - @t_side - @b7_st) / @b7_sr, ~0.0, ~1.0)
    return nil if w <= ~0.0
    i = 0
    while i < @arm_mask.size
      ctl.add_drive(@arm_mask[i], @b7_sff * w * @b7_a[i])
      i += 1
    nil

  # ---- the grip lock ---------------------------------------------------------------

  -> grip_lock(f, ctl)
    return nil if f.t < @glk_t
    if @c_lock == nil
      @c_lock = (0...body.size).map ->(m) f.c(m)
      @q_lock = f.vec("q").map -> item
      g = body.geometry
      @c_lock_g = @hand_mask.map ->(m) g.contraction(m, @q_lock)
    dv = ctl.track("hand").chunk.drive_values
    cmd = ctl.command
    cl = @c_lock
    sh = zeros
    sh = arm_shift(f, @q_lock, @c_lock_g) if @glk_w > ~0.5
    @hand_mask.each ->(m)
      d = @glk_d
      d = d - dv[m] if dv != nil
      ctl.add_drive(m, d)
      ctl.add_offset(m, cl[m] + sh[m] + @glk_s * ~0.5 - cmd[m])
      ctl.set_gain(m, @glk_g)
    nil

  # ---- the backhand's posture per serve ----------------------------------------------

  # bh_tk 1: the backhand's commanded posture (its ready movement and the
  # stroke from it) is set per serve when the side is chosen: the practised
  # posture plus bh_tq_* rad per second the predicted contact comes after
  # bh_tc0, and bh_zq_* per metre the ball crosses above bh_zc0. The swing
  # toward the backhand is still turning the face at contact, so a fixed
  # posture meets early balls (fast serves, contact at 0.44-0.52 s) with the
  # pad still swinging and the face too open (3 of 36 hit and solved on the
  # trial), late ones (0.55-0.62 s) 0.2 more closed (20 of 34).
  -> serve_posture
    dt = @plan[0] + @t_side - @bh_tc0
    # bh_tk 2: only contacts earlier than bh_tc0 are shifted (a hinge)
    dt = ~0.0 if @bh_tk > ~1.5 && dt > ~0.0
    dz = @plan[2] - @bh_zc0
    q = []
    i = 0
    while i < 7
      q.push(@q_bh[i] + @bh_tq[i] * dt + @bh_zq[i] * dz)
      i += 1
    tr = [@trunk_bh[0], @trunk_bh[1], @trunk_bh[2] + @bh_tq[7] * dt + @bh_zq[7] * dz]
    @q_set = q
    @trunk_bh = tr
    @bh_ready_c.pose(posture(tr, q, @bs))
    if @bh_tq[7] != ~0.0 || @bh_zq[7] != ~0.0
      pt = posture(tr, q, @stiff)
      @ctl.track("trunk").movement.chunks.each ->(c)
        c.pose(pt) if c.name == "bh_brace" || c.name == "bh_hold"
    nil

  # ---- the backhand's expected pad velocity ------------------------------------------

  # bh_vpe 1: the aim law expects the backhand's pad to carry (bh_vpx, bh_vpy,
  # bh_vpz) m/s into the contact plus bh_kvpm of its measured (smoothed)
  # velocity: the backhand meets the ball still swinging (median (-0.37,
  # -0.66, 0.23) m/s at contact, 0.36 m/s into the ball along the face
  # normal) where the aim law assumes a still pad, so it returns long.
  -> pad_vel_expected
    return super if @bh_vpe < ~0.5 || @side != 2 || (fam_side_on && @fam > 0) || @fam >= 5
    v = super
    [v[0] + @bh_vpx + @bh_kvpm * @vp7[0], v[1] + @bh_vpy + @bh_kvpm * @vp7[1], v[2] + @bh_vpz + @bh_kvpm * @vp7[2]]

  # ---- the grip squeeze ----------------------------------------------------------

  -> squeeze_on(f)
    return false if @t_hit_at >= ~0.0 && f.t > @t_hit_at + @gsq_hold
    return f.t >= @gsq_t0 if @gsq_t0 > ~0.0
    return false if @t_cpred < ~0.0
    f.t >= @t_cpred - @gsq_lead

  -> grip_squeeze(f, ctl)
    return nil if !squeeze_on(f)
    @sq_flex.each ->(m)
      ctl.add_drive(m, @gsq_drv)
      ctl.add_offset(m, @gsq_c)
    if @gsq_int > ~0.0
      @sq_int.each ->(m) ctl.add_drive(m, @gsq_int)
    if @gsq_ext > ~0.0
      @sq_ext.each ->(m) ctl.add_offset(m, ~0.0 - @gsq_ext)
    nil

  # ---- the backhand's transfer burst ------------------------------------------------

  # The contraction change the backhand's ready posture asks of each arm
  # muscle from the command as it stands when the side is chosen.
  -> transfer_plan
    start = @ctl.command
    goal = posture(@trunk_bh, @q_bh, @bs).apply(body, start)
    d = zeros
    @arm_mask.each ->(m) d[m] = goal[m] - start[m]
    @tr_d = d
    @tr_t0 = @t_side
    nil

  -> transfer_burst(f, ctl)
    e = f.t - @tr_t0
    return nil if e < ~0.0 || e > @b7_tb + @b7_tbrk
    d = @tr_d
    brake = e > @b7_tb
    g = @bh_gain * @b7_tg
    @arm_mask.each ->(m)
      x = d[m] / @b7_tsc
      if brake
        ctl.add_drive(m, @b7_tba * clamp(~0.0 - x, ~0.0, ~1.0)) if x < ~0.0
      else
        ctl.add_drive(m, @b7_ta * clamp(x, ~0.0, ~1.0)) if x > ~0.0
      ctl.set_gain(m, g)
    nil
