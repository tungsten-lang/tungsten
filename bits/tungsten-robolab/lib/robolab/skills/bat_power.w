# BatPowerSkill (v6, 2026-09-27): the v5 swing (skills/bat.w, unchanged)
# plus opt-in features for bat speed. Measured on v5 (playground/
# bat_power_diag.py): every arm and wrist joint stays at 15-60 % of its
# unloaded speed limit, the arm and wrist prime movers spend under 8 % of
# their power phase at activation >= 0.9 (co-contraction index 0.19-0.28),
# the arms peak 130-160 ms before contact and the bottom wrist uncocks early
# (casting). Each feature is off at its default, so a params file without
# them replays the v5 swing exactly.
#
#   ri        reciprocal inhibition (Controller#set_reciprocal) on every
#             upper-body joint pair (pelvis yaw, spine, shoulders, elbows,
#             wrists): while a muscle carries feed-forward drive its
#             antagonist's activation is scaled by 1 - ri * drive. Drive
#             only exists in the swing's chunks, so it is phase-gated.
#   pw_*      phase-gated drive along the plan: while a track is in its power
#             phase (hips: swing, torso: swing, arms: swing -> drive) and the
#             bat has not met the ball, the muscle each joint's command is
#             shortening gets pw * clamp(command speed / pw_v, 0, 1) of extra
#             drive, i.e. full drive on the prime movers of the planned motion
#             (pw_hips on pelvis yaw, pw_torso on the spine, pw_arms on the
#             shoulders and elbows, pw_wrist on the wrists)
#   lag       wrist lag and release: until the release the wrists are held a
#             fraction `lag` of the way from their planned angle back to the
#             slot's cocked angles (the bat lags the hands), then released
#             (the offset springs out on the swing's spring) with rel_drv of
#             drive on the uncocking muscles for rel_t s. The release latches
#             on SENSED trunk speed: the torso's yaw rate has peaked and fallen
#             below rel_pk of its peak (the trunk braking, as in a kinetic
#             chain), at the latest when the pitch is rel_tau s from the plate.
#   off_*     per-phase joint offsets on the aim correction (after the Codex
#             bat_power search, whose gain came from them): spine rotation
#             (off_rot*), spine flexion (off_flx*), both elbows (off_elb*) and
#             both wrists' flexion (off_wfx*), radians, for phase 0 (stride
#             and plant), 1 (load and the arms' swing into the slot) and 2
#             (whip, release, drive)

+ BatPowerSkill < BatSkill
  -> read_params
    super
    @ri = param("ri", ~0.0, ~0.0, ~1.0)
    @pw_hips = param("pw_hips", ~0.0, ~0.0, ~1.0)
    @pw_torso = param("pw_torso", ~0.0, ~0.0, ~1.0)
    @pw_arms = param("pw_arms", ~0.0, ~0.0, ~1.0)
    @pw_wrist = param("pw_wrist", ~0.0, ~0.0, ~1.0)
    @pw_v = param("pw_v", ~1.0, ~0.1, ~4.0)
    @lag = param("lag", ~0.0, ~0.0, ~1.0)
    @rel_pk = param("rel_pk", ~0.9, ~0.5, ~1.3)
    @rel_tau = param("rel_tau", ~0.06, ~-0.05, ~0.25)
    @rel_drv = param("rel_drv", ~0.0, ~0.0, ~1.0)
    @rel_t = param("rel_t", ~0.06, ~0.02, ~0.2)
    @offs = []
    [0, 1, 2].each ->(ph)
      @offs.push([param("off_rot[ph]", ~0.0, ~-0.2, ~0.2), param("off_flx[ph]", ~0.0, ~-0.2, ~0.2),
                  param("off_elb[ph]", ~0.0, ~-0.3, ~0.3), param("off_wfx[ph]", ~0.0, ~-0.3, ~0.3)])
    @offs_on = false
    @offs.each ->(o)
      o.each ->(v)
        @offs_on = true if v != ~0.0
    # prog: the ideal-control swing program (skills/bat_program.w)
    @prog = param("prog", ~0.0, ~0.0, ~1.5)
    @prog_track = param("prog_track", ~1.0, ~0.0, ~1.0)
    @prog_shift = param("prog_shift", ~0.0, ~-0.05, ~0.05)
    @prog_loc = param("prog_loc", ~1.0, ~0.0, ~1.0)
    @prog_end = param("prog_end", ~0.0, ~-0.05, ~0.05)
    # the reflex gain (chunk gain multiplier) of the program's muscles while
    # it drives; < 0 leaves the chunks' own
    @prog_gain = param("prog_gain", ~-1.0, ~-1.0, ~2.0)
    # the programs' blend: metres of crossing distance per m/s of pitch speed
    # (< 0: the library's own speed_scale) and the inverse-distance power
    @prog_vscale = param("prog_vscale", ~-1.0, ~-1.0, ~0.1)
    @prog_pow = param("prog_pow", ~2.0, ~1.0, ~8.0)
    # every track's swing fires when the pitch is prog_trig s from the plate
    # (the program sequences the segments itself); default: the program's
    # contact time after the hips fire, plus 15 ms (contact is in front of
    # the plate)
    @prog_trig = param("prog_trig", BatProgram.t_contact[0] - BatProgram.lead + ~0.015, ~0.1, ~0.4)
    # train: the program distilled into quintic contraction knots (see below)
    @train = param("train", ~0.0, ~0.0, ~1.0) > ~0.5
    @train_n = param("train_n", ~7.0, ~3.0, ~12.0).to_i
    @train_gain = param("train_gain", ~1.0, ~0.0, ~3.0)
    @train_drv = param("train_drv", ~1.0, ~0.0, ~1.5)
    @train_end = param("train_end", ~0.005, ~-0.03, ~0.03)
    @train_legs = param("train_legs", ~1.2, ~0.6, ~2.0)
    # train_first: the first knot segment lasts this many times the others (the command's velocity step at the swing's
    # start, from the load's velocity to the program's, spreads over a longer segment); 1 = evenly spaced knots
    @train_first = param("train_first", ~1.0, ~0.5, ~4.0)
    # train_legs_ease: the legs' swing easing is (1 - e) x the v5 hips swing's cubic_out (fastest at the swing's start, a
    # velocity step from the plant's stillness) + e x a smoothstep (starts at rest); 0 = cubic_out
    @train_legs_ease = param("train_legs_ease", ~0.0, ~0.0, ~1.0)
    # train_ext: see train_disp (s; 0 = the program's table as it is)
    @train_ext = param("train_ext", ~0.0, ~0.0, ~0.08)
    @train_tc = ~0.0
    # dshape (batting round 2): a time profile on the feed-forward drive per joint group (pelvis yaw, spine, shoulders, elbows,
    # wrists): the drive of a knot segment is scaled by 1 + dshape_b * clip(sum_k dw[6 g + k] g_k(t), -1, 1) with g_k the same 6 gaussian
    # bumps (30, 70, .. 230 ms after the fire, width 30 ms) as tres; all weights 0 = the drive as it is
    @dshape_b = param("dshape_b", ~0.5, ~0.0, ~1.0)
    @dshape_w = []
    ti = 0
    while ti < 30
      @dshape_w.push(param("dw[ti]", ~0.0, ~-1.0, ~1.0))
      ti += 1
    @dshape_on = false
    ti = 0
    while ti < 30
      @dshape_on = true if @dshape_w[ti] != ~0.0
      ti += 1
    @dshape_group = nil
    # train_lead / train_dlead (s): the reflex targets (angle, rate, acceleration) / the feed-forward drive are read from the
    # program this much later than the keyframe's time (positive: the targets lead the drive, or the drive the targets)
    @train_lead = param("train_lead", ~0.0, ~-0.03, ~0.05)
    @train_dlead = param("train_dlead", ~0.0, ~-0.03, ~0.05)
    # taim (batting round 2): the first-order aim correction of the blended program (see aim_correction)
    @taim_z = param("taim_z", ~0.0, ~-4.0, ~4.0)
    @taim_x = param("taim_x", ~0.0, ~-4.0, ~4.0)
    @taim_z0 = param("taim_z0", ~0.0, ~-0.1, ~0.1)
    @taim_x0 = param("taim_x0", ~0.0, ~-0.1, ~0.1)
    @taim_ramp = param("taim_ramp", ~0.8, ~0.2, ~1.2)
    @taim_on = @taim_z != ~0.0 || @taim_x != ~0.0 || @taim_z0 != ~0.0 || @taim_x0 != ~0.0
    @taim_c = nil
    @taim_idx = nil
    # tres (batting round 2): a zero-initialised temporal residual on the reflex target (see temporal_residual)
    @tres_b = param("tres_b", ~0.1, ~0.0, ~0.3)
    @tres_w = []
    @tres_v = []
    ti = 0
    while ti < 24
      @tres_w.push(param("tw[ti]", ~0.0, ~-1.0, ~1.0))
      ti += 1
    ti = 0
    while ti < 16
      @tres_v.push(param("tv[ti]", ~0.0, ~-1.0, ~1.0))
      ti += 1
    # tres_conv: also the five fixed convolutional features of the Codex residual (bat_residual.w) through the readout tc0-tc19
    @tres_conv = param("tres_conv", ~0.0, ~0.0, ~1.0) > ~0.5
    @tres_c = []
    ti = 0
    while ti < 20
      @tres_c.push(param("tc[ti]", ~0.0, ~-1.0, ~1.0))
      ti += 1
    @tres_on = false
    ti = 0
    while ti < 24
      @tres_on = true if @tres_w[ti] != ~0.0
      ti += 1
    ti = 0
    while ti < 16
      @tres_on = true if @tres_v[ti] != ~0.0
      ti += 1
    ti = 0
    while ti < 20
      @tres_on = true if @tres_conv && @tres_c[ti] != ~0.0
      ti += 1
    @tres_t0 = ~-1.0
    @tres_fade = ~1.0
    @tres_pf = nil
    @tres_lp = [~0.0, ~0.0, ~0.0, ~0.0]
    @conv = nil
    @trains = []
    @train_holds = {}
    @train_tick = 0
    @pj = nil
    self

  -> start(frame, ctl)
    super(frame, ctl)
    @prev_cmd = nil
    @released = false
    @rel_at = ~-1.0
    @contacted = false
    @frame = frame
    setup_reciprocal(ctl) if @ri > ~0.0
    @prog_t0 = ~-1.0
    @tres_t0 = ~-1.0
    @tres_fade = ~1.0
    load_program if @prog > ~0.0 && @pj == nil
    self

  -> setup_reciprocal(ctl)
    pairs = []
    BatPostures.joints.each ->(j)
      pairs.push([body.pos_index(j), body.neg_index(j)])
    ctl.set_reciprocal(pairs, @ri)
    self

  -> wrist_joints
    ["l_wrist_flex", "l_wrist_dev", "r_wrist_flex", "r_wrist_dev"]

  -> trigger(lag, which)
    return super(lag, which) if @prog <= ~0.0 && !@train
    @prog_trig

  # ---- per tick ---------------------------------------------------------------

  -> before(f, ctl)
    @frame = f
    super(f, ctl)
    arms = ctl.track("arms").chunk_name
    if arms == "set" || arms == "ready" || arms == "recover" || arms == "regrip" || arms == "close"
      @released = false
      @contacted = false
    @contacted = true if f.at("bat_contact", 0) > ~0.0
    update_release(f, ctl) if @lag > ~0.0 || @rel_drv > ~0.0
    update_train(f) if @train
    nil

  -> after(f, ctl)
    cmd = ctl.command
    if @prev_cmd != nil && !@contacted
      power_drive(ctl, "hips", body.mask(["pelvis_yaw"]), @pw_hips) if @pw_hips > ~0.0
      power_drive(ctl, "torso", body.mask(["spine_"]), @pw_torso) if @pw_torso > ~0.0
      power_drive(ctl, "arms", body.mask(["l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @pw_arms) if @pw_arms > ~0.0
      if @pw_wrist > ~0.0 && (@lag <= ~0.0 || @released)
        power_drive(ctl, "arms", body.mask(["l_wrist", "r_wrist"]), @pw_wrist)
      release_drive(f, ctl) if @rel_drv > ~0.0 && @released
    # (the hips' swing chunk, entered during this tick's track update, set
    # @hips_fired: the program starts on the same tick)
    start_program(f, ctl) if @prog > ~0.0
    run_program(f, ctl) if @prog > ~0.0 && @prog_t0 >= ~0.0
    temporal_residual(f, ctl) if @tres_on
    @prev_cmd = cmd.copy
    nil

  # tres (batting round 2): the Codex recipe's zero-initialised readout on fixed features, on the knots swing. Four
  # joint-group offsets (spine rotation, spine flexion, both elbows, both wrists' flexion), each
  #   bound * clip(sum_k tw[6 o + k] g_k(tau) + sum_p tv[4 o + p] x_p, -1, 1)   radians on the reflex target,
  # g_k the 6 gaussian bumps (centres 30, 70, ..., 230 ms after the hips fire, width 30 ms: the temporal basis)
  # and x = [1, height, crossing, speed] of the pitch (predicted when the hips fire, scaled to about +-1). All weights 0
  # = the knots swing exactly. The offsets start through a 40 ms smoothstep window and stop at contact through a 30 ms
  # fade (no step in the command).
  -> temporal_residual(f, ctl)
    if !@hips_fired
      @tres_t0 = ~-1.0
      @tres_fade = ~1.0
      return nil
    @tres_fade = @tres_fade - ctl.dt / ~0.03 if @contacted
    return nil if @tres_fade <= ~0.0
    p = predict(f)
    if @tres_t0 < ~0.0
      @tres_t0 = f.t
      @tres_pf = [~1.0, clamp((p[2] - ~0.81) / ~0.19, ~-1.5, ~1.5), clamp((p[1] - @plate_x) / ~0.15, ~-1.5, ~1.5), clamp((plate_speed(f) - ~33.0) / ~3.3, ~-1.5, ~1.5)]
      @tres_lp = [~0.0, ~0.0, ~0.0, ~0.0]
      if @tres_conv
        @conv = BatConvResidual.new if @conv == nil
        @conv.reset
    tau = f.t - @tres_t0
    # (a 40 ms smoothstep window from the fire: a constant term does not step the command)
    win = clamp(tau / ~0.04, ~0.0, ~1.0)
    win = win * win * (~3.0 - ~2.0 * win)
    cf = nil
    if @tres_conv
      @conv.update(f, [p[0] / ~0.25, (p[1] - @plate_x) / ~0.15, (p[2] - ~0.81) / ~0.19, f.torso_pitch, f.torso_pitch_rate / ~5.0, tau / ~0.25])
      cf = @conv.feats
    lp = ctl.dt / (~0.03 + ctl.dt)
    out = [~0.0, ~0.0, ~0.0, ~0.0]
    o = 0
    while o < 4
      acc = ~0.0
      k = 0
      while k < 6
        dd = (tau - (~0.03 + ~0.04 * k)) / ~0.03
        acc = acc + @tres_w[o * 6 + k] * Math.exp(~-0.5 * dd * dd)
        k += 1
      k = 0
      while k < 4
        acc = acc + @tres_v[o * 4 + k] * @tres_pf[k]
        k += 1
      if cf != nil
        k = 0
        while k < 5
          acc = acc + @tres_c[o * 5 + k] * cf[k]
          k += 1
      @tres_lp[o] = @tres_lp[o] + (@tres_b * win * clamp(acc, ~-1.0, ~1.0) - @tres_lp[o]) * lp
      out[o] = @tres_fade * @tres_lp[o]
      o += 1
    off = zeros
    joint_offset(off, "spine_rot", out[0])
    joint_offset(off, "spine_flex", out[1])
    joint_offset(off, "l_elbow", out[2])
    joint_offset(off, "r_elbow", out[2])
    joint_offset(off, "l_wrist_flex", out[3])
    joint_offset(off, "r_wrist_flex", out[3])
    i = 0
    while i < off.size
      ctl.add_offset(i, off[i]) if off[i] != ~0.0
      i += 1
    nil

  # A track's power phase: from its swing to the drive (the arms) or the end
  # of its swing (hips, torso).
  -> powering?(ctl, track)
    name = ctl.track(track).chunk_name
    return name == "swing" if track != "arms"
    name == "swing" || name == "whip" || name == "release" || name == "drive"

  # Drive along the plan (see the header): the muscle each joint's command is
  # shortening gets level * clamp(command speed / pw_v, 0, 1).
  -> power_drive(ctl, track, mask, level)
    return nil if !powering?(ctl, track)
    cmd = ctl.command
    pc = @prev_cmd
    dt = ctl.dt
    mask.each ->(i)
      v = (cmd[i] - pc[i]) / dt
      ctl.add_drive(i, level * clamp(v / @pw_v, ~0.0, ~1.0)) if v > ~0.0
    nil

  # ---- wrist lag and release -------------------------------------------------

  -> update_release(f, ctl)
    return nil if @released || !powering?(ctl, "arms")
    tr = ~0.0 - f.at("torso_angvel", 2)
    braking = @t_max > ~3.0 && tr < @rel_pk * @t_max
    p = predict(f)
    late = p[0] < ~8.0 && p[0] <= @rel_tau
    if braking || late
      @released = true
      @rel_at = f.t
    nil

  # The uncocking muscles (the way each wrist joint moves from the slot to
  # contact) driven for rel_t s after the release.
  -> release_drive(f, ctl)
    return nil if f.t - @rel_at > @rel_t
    a = BatPostures.q_slot
    b = BatPostures.q_contact_u
    names = BatPostures.joints
    i = 0
    while i < names.size
      if names[i].include?("wrist")
        k = body.pos_index(names[i])
        k = body.neg_index(names[i]) if b[i] < a[i]
        ctl.add_drive(k, @rel_drv)
      i += 1
    nil

  # ---- offsets on the aim correction -------------------------------------------

  -> arm_phase
    name = @ctl.track("arms").chunk_name
    return 1 if name == "load" || name == "swing"
    return 2 if name == "whip" || name == "release" || name == "drive"
    return 0 if name == "stride" || name == "plant" || name == "leglift"
    -1

  -> aim_offsets(wp)
    off = super(wp)
    return off if off == nil
    ph = arm_phase
    if @offs_on && ph >= 0
      o = @offs[ph]
      joint_offset(off, "spine_rot", o[0])
      joint_offset(off, "spine_flex", o[1])
      joint_offset(off, "l_elbow", o[2])
      joint_offset(off, "r_elbow", o[2])
      joint_offset(off, "l_wrist_flex", o[3])
      joint_offset(off, "r_wrist_flex", o[3])
    lag_offsets(off) if @lag > ~0.0 && !@released && (ph == 1 || ph == 2)
    off

  # Hold the wrists `lag` of the way from their planned angle back to the
  # slot's cocked angles.
  -> lag_offsets(off)
    a = BatPostures.q_slot
    names = BatPostures.joints
    cmd = @ctl.command
    i = 0
    while i < names.size
      if names[i].include?("wrist")
        p = body.pos_index(names[i])
        m = body.muscle(p)
        q = m.qmin + cmd[p] * (m.qmax - m.qmin)
        joint_offset(off, names[i], @lag * (a[i] - q))
      i += 1
    off

  # ---- prog: the ideal-control swing program -------------------------------------
  #
  # skills/bat_program.w holds open-loop swings found by playground/
  # bat_ceiling.py (CMA-ES over the upper body's excitations from the moment
  # the practised swing's hips fire, fastest sweet spot through the ball),
  # exported by playground/bat_program_export.py. With `prog` > 0 the program
  # starts when the hips fire: each program joint gets prog * u(t) as drive
  # (u > 0 the pos muscle, u < 0 the neg muscle), and, scaled by prog_track,
  # the reflex target follows the program's joint displacement from where the
  # command was when it started (so the stretch reflexes do not fight it). The
  # programs (one per pitch location) are blended by inverse squared distance
  # to the pitch's predicted crossing when the hips fire. Drive stops at contact (or prog_end s after the
  # program's own contact time for a miss); the tracking offset then holds its
  # contact value and fades out over prog_fade s through the follow-through.

  -> load_program
    @pj = BatProgram.joints
    @pknots = BatProgram.knots
    @pn = BatProgram.count
    @pu = BatProgram.u
    @pq = BatProgram.q
    @plocs = BatProgram.locs
    @ptcs = BatProgram.t_contact
    @pqs = BatProgram.q_start
    @ptick = BatProgram.tick
    @pnk = @pknots.size
    @pns = @pq.size / (@pn * @pj.size)
    @plead = BatProgram.lead
    @ppos = @pj.map ->(j) body.pos_index(j)
    @pneg = @pj.map ->(j) body.neg_index(j)
    @prog_fade = ~0.35
    @poff = @pj.map ->(j) ~0.0
    @pw = (0...@pn).map ->(i) ~0.0
    @pw[0] = ~1.0
    @taim_idx = @pj.map ->(j) taim_index(j)
    @taim_c = @pj.map ->(j) ~0.0
    @dshape_group = @pj.map ->(j) dshape_group_of(j)
    self

  # dshape's joint groups: 0 pelvis yaw, 1 spine, 2 shoulders, 3 elbows, 4 wrists
  -> dshape_group_of(name)
    return 0 if name == "pelvis_yaw"
    return 1 if name.starts_with?("spine")
    return 3 if name.include?("elbow")
    return 4 if name.include?("wrist")
    2

  # The drive's scale for program joint jj over a segment centred at train time tm (see dshape).
  -> drive_factor(jj, tm)
    g = @dshape_group[jj]
    acc = ~0.0
    k = 0
    while k < 6
      dd = (tm - (~0.03 + ~0.04 * k)) / ~0.03
      acc = acc + @dshape_w[g * 6 + k] * Math.exp(~-0.5 * dd * dd)
      k += 1
    ~1.0 + @dshape_b * clamp(acc, ~-1.0, ~1.0)

  # A program joint's place in the aim sensitivity vectors (BatPostures.k_joints), -1 if it has none.
  -> taim_index(name)
    names = BatPostures.k_joints
    i = 0
    while i < names.size
      return i if names[i] == name
      i += 1
    -1

  # The command's joint angle (from the pos muscle's contraction).
  -> cmd_angle(ctl, k)
    p = @ppos[k]
    m = body.muscle(p)
    m.qmin + ctl.command[p] * (m.qmax - m.qmin)

  -> start_program(f, ctl)
    if !@hips_fired
      @prog_t0 = ~-1.0
      return nil
    return nil if @prog_t0 >= ~0.0
    @prog_t0 = f.t
    p = predict(f)
    if p[0] < ~8.0
      program_weights(p[1] - @plate_x, p[2], plate_speed(f))
    @ptc = ~0.0
    i = 0
    while i < @pn
      @ptc = @ptc + @pw[i] * @ptcs[i]
      i += 1
    @ptau_s = @plead + @prog_shift
    @pq0 = (0...@pj.size).map ->(k) cmd_angle(ctl, k)
    @pd0 = (0...@pj.size).map ->(k) prog_disp(k, @ptau_s)
    @pt_contact = ~-1.0
    nil

  # The pitch's speed at the front of the plate, predicted from the ball's
  # state (predict's quadratic drag along the remaining path).
  -> plate_speed(f)
    vx = f.at("ball_vel", 0)
    vy = f.at("ball_vel", 1)
    vz = f.at("ball_vel", 2)
    return ~0.0 if vy < ~1.0
    sp = Math.sqrt(vx * vx + vy * vy + vz * vz)
    dy = @plate_y - f.at("ball_pos", 1)
    sp * Math.exp(~0.0 - ~0.0062 * dy * sp / vy)

  # Inverse squared distance weights of the programs' pitches to the
  # predicted one (crossing x from the plate centre, z, and speed_scale x the
  # speed at the plate); prog_loc < 1 pulls the crossing toward the first
  # program's.
  -> program_weights(x, z, v)
    x0 = @plocs[0]
    z0 = @plocs[1]
    x = x0 + @prog_loc * (x - x0)
    z = z0 + @prog_loc * (z - z0)
    ks = BatProgram.speed_scale
    ks = @prog_vscale if @prog_vscale >= ~0.0
    total = ~0.0
    i = 0
    while i < @pn
      dx = x - @plocs[3 * i]
      dz = z - @plocs[3 * i + 1]
      dv = ks * (v - @plocs[3 * i + 2])
      w = ~1.0 / (Math.pow(dx * dx + dz * dz + dv * dv, @prog_pow * ~0.5) + ~0.00000001)
      @pw[i] = w
      total = total + w
      i += 1
    i = 0
    while i < @pn
      @pw[i] = @pw[i] / total
      i += 1
    nil

  # Entry i of joint k's row of a program table (programs x joints x n),
  # blended over the programs by their weights.
  -> blend(tab, k, i)
    n = tab.size / (@pn * @pj.size)
    out = ~0.0
    j = 0
    while j < @pn
      w = @pw[j]
      out = out + w * tab[(j * @pj.size + k) * n + i] if w > ~0.0001
      j += 1
    out

  -> prog_u(k, tau)
    return ~0.0 if tau < @pknots[0]
    last = @pnk - 1
    return blend(@pu, k, last) if tau >= @pknots[last]
    i = 0
    while i < last - 1 && tau >= @pknots[i + 1]
      i += 1
    s = (tau - @pknots[i]) / (@pknots[i + 1] - @pknots[i])
    a = blend(@pu, k, i)
    a + (blend(@pu, k, i + 1) - a) * s

  -> prog_disp(k, tau)
    x = tau / @ptick
    x = ~0.0 if x < ~0.0
    last = @pns - 1
    return blend(@pq, k, last) if x >= last * ~1.0
    i = x.to_i
    s = x - i * ~1.0
    a = blend(@pq, k, i)
    a + (blend(@pq, k, i + 1) - a) * s

  -> run_program(f, ctl)
    tau = f.t - @prog_t0 + @ptau_s
    @pt_contact = tau if @contacted && @pt_contact < ~0.0
    driving = !@contacted && tau <= @ptc + @prog_end + ~0.03
    k = 0
    while k < @pj.size
      if driving
        if @prog_gain >= ~0.0
          ctl.set_gain(@ppos[k], @prog_gain)
          ctl.set_gain(@pneg[k], @prog_gain)
        u = clamp(prog_u(k, tau), ~-1.0, ~1.0) * @prog
        ctl.add_drive(@ppos[k], u) if u > ~0.0
        ctl.add_drive(@pneg[k], ~0.0 - u) if u < ~0.0
      if @prog_track > ~0.0
        track_program(ctl, k, tau)
      k += 1
    nil

  # The reflex target follows the program's displacement; after the
  # program's drive ends the offset holds and fades out over prog_fade.
  -> track_program(ctl, k, tau)
    t_end = @ptc + @prog_end + ~0.03
    t_end = @pt_contact if @pt_contact >= ~0.0
    w = ~1.0
    if tau <= t_end
      want = @pq0[k] + prog_disp(k, tau) - @pd0[k]
      @poff[k] = @prog_track * (want - cmd_angle(ctl, k))
    else
      w = clamp(~1.0 - (tau - t_end) / @prog_fade, ~0.0, ~1.0)
      w = w * w * (~3.0 - ~2.0 * w)
    return nil if w <= ~0.0
    p = @ppos[k]
    m = body.muscle(p)
    d = w * @poff[k] / (m.qmax - m.qmin)
    ctl.add_offset(p, d)
    ctl.add_offset(@pneg[k], ~0.0 - d)
    nil

  # ---- train: the program distilled into robolab's representation ---------------
  #
  # `train 1` swings with ordinary robolab chunks instead of playing the
  # excitation program: each track's swing is a train of `train_n` quintic
  # contraction knots (Chunk#knot + via, TimedChunk durations), keyframes
  # evenly spaced from the hips firing to `train_end` s before the program's
  # contact. A knot's goal, velocity and acceleration are the program's own
  # (location-blended) joint trajectory at that time, as contractions; the
  # hips track's legs go from the landed stance to the swing stance on the v5
  # hips swing's easing (cubic_out over train_legs x the train, at its gain). Each knot chunk drives the muscles the program excited
  # over its segment (train_drv * the segment's mean excitation: phase-gated
  # full drive on the prime movers), with the reflexes ON (the swing's reflex
  # gains times train_gain) and, with `ri`, reciprocal inhibition. The
  # keyframes are set from the predicted crossing every 20 ms while the pitch
  # is in flight, until the hips fire; each train holds its load's correction
  # (the aim, the torso's separation) as it was then, and its keyframes
  # subtract it, so the target is the program's own trajectory. The v5
  # follow-through (the arc) starts from the last knot's velocity.

  -> swing_train(which, mv, mask, legs_load, legs_swing)
    return nil if !@train
    load_program if @pj == nil
    chunks = []
    k = 0
    # (the hips track: its legs at the v5 swing's gain)
    g = @train_gain
    g = @swing_gain if which == :hips
    while k < @train_n
      name = "train"
      name = "swing" if k == 0
      ch = TimedChunk.new(name, ~0.03).to(zeros).knot(zeros, zeros).via.drive(zeros).gain(g)
      ch.correct(->(f, c) train_hold(which))
      mv.add(ch)
      chunks.push(ch)
      k += 1
    inside = {}
    mask.each ->(m) inside[m] = true
    @trains.push([which, inside, chunks, leg_contractions(legs_load), leg_contractions(legs_swing)])
    chunks[0]

  # The correction a track's train holds: its load's correction (the aim,
  # and the torso's hip-shoulder separation) as it was when the keyframes
  # were last set, so the spring stays where the load left it; the keyframes
  # subtract it (the target is the program's own trajectory).
  -> train_hold(which)
    return nil if !@train_holds.key?(which)
    @train_holds[which]

  -> load_correction(which, f)
    off = nil
    off = separation(f, @ctl) if which == :torso
    off = aim_offsets(:release) if which != :torso
    off = zeros if off == nil
    off

  -> leg_contractions(legs)
    out = zeros
    names = BatPostures.leg_joints
    i = 0
    while i < names.size
      p = body.pos_index(names[i])
      n = body.neg_index(names[i])
      out[p] = body.muscle(p).contraction_at(legs[i])
      out[n] = body.muscle(n).contraction_at(legs[i])
      i += 1
    out

  # The blended program joint k's angle, rate and acceleration at program
  # time t (central differences over +-h of its displacement).
  -> train_state(k, t)
    h = ~0.01
    q0 = ~0.0
    i = 0
    while i < @pn
      q0 = q0 + @pw[i] * @pqs[i * @pj.size + k]
      i += 1
    a = train_disp(k, t - h)
    b = train_disp(k, t)
    c = train_disp(k, t + h)
    [q0 + b, (c - a) / (~2.0 * h), (c - ~2.0 * b + a) / (h * h)]

  # train_ext (batting round 2): the program's table after its own contact time is the CMA rollout WITH the ball's
  # impact in it (the wrists' rates collapse within 10 ms), which a swing that meets the ball a little later than the
  # program did would take as its target and brake against. With train_ext > 0 the plan past the program's contact
  # is instead the pre-contact motion carried on at its contact velocity, slowing linearly to rest over train_ext s.
  -> train_disp(k, t)
    return prog_disp(k, t) if @train_ext <= ~0.0 || t <= @train_tc
    tc = @train_tc
    vc = (prog_disp(k, tc) - prog_disp(k, tc - ~0.01)) / ~0.01
    d = t - tc
    d = @train_ext if d > @train_ext
    prog_disp(k, tc) + vc * d - ~0.5 * vc * d * d / @train_ext

  # The program's mean excitation of joint k over (ta, tb]: [pos, neg].
  # TODO: the bounds were t0/t1; a compiled local named `t<N>` collides with
  # the compiler's own %t<N> temporaries in the emitted LLVM IR ("multiple
  # definition of local value named 't0'"); the lowering should prefix user
  # locals as it does for the `v<N>` slots. Renamed until that is fixed.
  -> train_drive(k, ta, tb)
    sp = ~0.0
    sn = ~0.0
    m = 0
    t = ta + ~0.0025
    while t < tb
      u = clamp(prog_u(k, t), ~-1.0, ~1.0)
      sp = sp + u if u > ~0.0
      sn = sn - u if u < ~0.0
      m += 1
      t = t + ~0.005
    return [~0.0, ~0.0] if m == 0
    [sp / m, sn / m]

  # taim (batting round 2): the first-order aim correction of the blended program. The programs
  # are blended by inverse squared distance to the predicted crossing (program_weights), which is exact at a
  # program's own pitch but has no slope there: between programs the blend's swing meets the pitch's location
  # only as well as sum_i w_i loc_i does, and the miss (perpendicular to the swing plane at contact) is
  # linear in that location mismatch (measured: bat_rep aim_n = -3.2 + 152 dz + 35 dx cm, R2 0.88 on 144 fresh
  # pitches, dz, dx in m). The correction is the v5 aim law's own machinery, applied to the mismatch:
  #   joint offset_j = taim_z * k_z_u[j] * (z_pred - z_blend + taim_z0) + taim_x * k_x_u[j] * (x_pred - x_blend + taim_x0)
  # (k_z_u, k_x_u: the joint change that moves the sweet spot 1 m up / out with the top hand on the handle,
  # BatPostures), ramped in over taim_ramp of the train by a quintic smoothstep and added to every keyframe's
  # angle, rate and acceleration. At a program's own pitch the mismatch is 0, so the program is unchanged there.
  -> aim_correction(p)
    xe = ~0.0
    ze = ~0.0
    i = 0
    while i < @pn
      xe = xe + @pw[i] * @plocs[3 * i]
      ze = ze + @pw[i] * @plocs[3 * i + 1]
      i += 1
    dz = p[2] - ze + @taim_z0
    dx = (p[1] - @plate_x) - xe + @taim_x0
    kz = BatPostures.k_z_u
    kx = BatPostures.k_x_u
    j = 0
    while j < @pj.size
      idx = @taim_idx[j]
      @taim_c[j] = ~0.0
      @taim_c[j] = @taim_z * kz[idx] * dz + @taim_x * kx[idx] * dx if idx >= 0
      j += 1
    nil

  # The correction's ramp at train time t: [w, dw/dt, d2w/dt2] (quintic smoothstep over taim_ramp x the train).
  -> aim_ramp(t, big_t)
    tr = @taim_ramp * big_t
    s = t / tr
    return [~1.0, ~0.0, ~0.0] if s >= ~1.0
    return [~0.0, ~0.0, ~0.0] if s <= ~0.0
    s2 = s * s
    om = ~1.0 - s
    [s2 * s * (~10.0 - ~15.0 * s + ~6.0 * s2), ~30.0 * s2 * om * om / tr, ~60.0 * s * om * (~1.0 - ~2.0 * s) / (tr * tr)]

  -> corrected_state(jj, st, ramp, mu)
    c = @taim_c[jj]
    return st if c == ~0.0
    q = clamp(st[0] + ramp[0] * c, mu.qmin + ~0.02, mu.qmax - ~0.02)
    [q, st[1] + ramp[1] * c, st[2] + ramp[2] * c]

  -> update_train(f)
    return nil if @hips_fired
    p = predict(f)
    return nil if p[0] > ~8.0
    @train_tick += 1
    return nil if @train_tick % 4 != 1
    program_weights(p[1] - @plate_x, p[2], plate_speed(f))
    tc = ~0.0
    i = 0
    while i < @pn
      tc = tc + @pw[i] * @ptcs[i]
      i += 1
    big_t = tc - @train_end
    @train_tc = tc
    n = @train_n
    dk = big_t / n
    tf = dk
    dr = dk
    if @train_first != ~1.0 && n > 1
      tf = dk * @train_first
      dr = (big_t - tf) / (n - 1)
    aim_correction(p) if @taim_on
    @trains.each ->(tr)
      inside = tr[1]
      chunks = tr[2]
      la = tr[3]
      lb = tr[4]
      hold = load_correction(tr[0], f)
      @train_holds[tr[0]] = hold
      k = 1
      while k <= n
        t = dk * k
        t_prev = t - dk
        dur = dk
        if @train_first != ~1.0 && n > 1
          t = tf + dr * (k - 1)
          t_prev = ~0.0
          t_prev = t - dr if k > 1
          dur = t - t_prev
        goal = zeros
        vel = zeros
        acc = zeros
        drv = zeros
        ramp = aim_ramp(t, big_t)
        jj = 0
        while jj < @pj.size
          pp = @ppos[jj]
          if inside.key?(pp)
            nn = @pneg[jj]
            st = train_state(jj, t + @train_lead)
            mu = body.muscle(pp)
            st = corrected_state(jj, st, ramp, mu) if @taim_on
            r = mu.qmax - mu.qmin
            goal[pp] = mu.contraction_at(st[0]) - hold[pp]
            goal[nn] = body.muscle(nn).contraction_at(st[0]) - hold[nn]
            vel[pp] = st[1] / r
            vel[nn] = ~0.0 - st[1] / r
            acc[pp] = st[2] / r
            acc[nn] = ~0.0 - st[2] / r
            d = train_drive(jj, t_prev + @train_dlead, t + @train_dlead)
            dg = ~1.0
            dg = drive_factor(jj, ~0.5 * (t_prev + t)) if @dshape_on
            drv[pp] = @train_drv * d[0] * dg
            drv[nn] = @train_drv * d[1] * dg
          jj += 1
        # the legs on the v5 hips swing's easing (cubic_out), stretched over
        # the whole train (train_legs x its length) so they are still moving
        # into the follow-through
        dl = big_t * @train_legs
        sl = clamp(t / dl, ~0.0, ~1.0)
        om = ~1.0 - sl
        e0 = ~1.0 - om * om * om
        e1 = ~3.0 * om * om / dl
        e2 = ~-6.0 * om / (dl * dl)
        if @train_legs_ease > ~0.0
          le = @train_legs_ease
          e0 = (~1.0 - le) * e0 + le * sl * sl * (~3.0 - ~2.0 * sl)
          e1 = (~1.0 - le) * e1 + le * ~6.0 * sl * om / dl
          sm2 = ~0.0
          sm2 = (~6.0 - ~12.0 * sl) / (dl * dl) if sl < ~1.0
          e2 = (~1.0 - le) * e2 + le * sm2
        BatPostures.leg_joints.each ->(j)
          [body.pos_index(j), body.neg_index(j)].each ->(m)
            if inside.key?(m)
              goal[m] = la[m] + (lb[m] - la[m]) * e0
              vel[m] = (lb[m] - la[m]) * e1
              acc[m] = (lb[m] - la[m]) * e2
        ch = chunks[k - 1]
        ch.retime(dur)
        ch.to(goal)
        ch.knot(vel, acc)
        ch.drive(drv)
        k += 1
    nil
