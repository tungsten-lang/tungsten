# Controller: runs movements on the body, one tick per sensor frame.
#
# The commanded contraction vector is the control plane's state. Tracks
# (parallel movements on disjoint muscle masks, e.g. legs running while an
# arm dribbles) write their chunk's eased trajectory into it; real-time
# corrections are added on top through springs; the reflex layer turns the
# result into activations. A skill object gets `before`/`after` hooks each
# tick for task-level logic such as predicting a ball's flight.

+ Track
  ro :name
  ro :movement
  ro :mask
  -> new(@name, @movement, @mask)
    @index = -1
    @t0 = ~0.0
    @start = nil
    @goal = nil
    @finished = false
    @spring = nil
    @corr = nil
    @hermite = false
    @v0 = nil
    @v1 = nil
    @prev_cmd = nil
    @cmd_vel = nil
    @quintic = false
    @kv0 = nil
    @ka0 = nil

  -> chunk
    return nil if @index < 0
    @movement[@index]

  # Swap the movement the track runs (opt-in: RunGearSkill's gear change hands the stride over to a
  # movement built from another parameter set; the track's index and clock carry on, and the caller
  # jumps to a chunk of the new movement).
  -> set_movement(mv)
    @movement = mv
    self

  -> chunk_name
    return "-" if @index < 0
    @movement[@index].name

  -> finished?
    @finished

  -> elapsed(frame)
    frame.t - @t0

  -> enter_chunk(ctl, frame, i)
    came_via = @index >= 0 && @movement[@index].via?
    prev = nil
    prev = @movement[@index] if @index >= 0
    @index = i
    @t0 = frame.t
    @start = ctl.command.copy
    ch = @movement[i]
    @goal = ch.goal_from(ctl.body, @start, @mask)
    plan_hermite(ctl, ch, came_via)
    plan_quintic(ch, prev)
    # A chunk that states its own spring time retimes the correction spring
    # (the spring itself, and its state, carry over so nothing steps).
    @spring.retime(ch.spring_time) if @spring != nil && ch.correction != nil && ch.spring_time_stated?
    callback = ch.enter_fn
    callback.call(frame, ctl) if callback != nil
    self

  # Velocity-continuous chaining: a chunk entered from a via chunk starts with
  # the command's current velocity; a via chunk ends with the Catmull-Rom
  # tangent toward the next chunk's goal. Otherwise the chunk's easing runs.
  -> plan_hermite(ctl, ch, came_via)
    n = ctl.body.size
    @hermite = false
    @v0 = nil
    @v1 = nil
    return self if ch.staggered? || ch.duration <= ~0.0 || ch.knot?
    if came_via && @cmd_vel != nil
      cv = @cmd_vel
      v0 = []
      i = 0
      while i < n
        v0.push(cv[i])
        i += 1
      @v0 = v0
      @hermite = true
    if ch.via?
      nxt = next_index(ch)
      v1 = []
      i = 0
      while i < n
        v1.push(~0.0)
        i += 1
      @v1 = v1
      if nxt >= 0
        nc = @movement[nxt]
        p2 = nc.goal_from(ctl.body, @goal, @mask)
        t2 = nc.duration
        t2 = ch.duration if t2 <= ~0.0
        span = ch.duration + t2
        st = @start
        msk = @mask
        nm = msk.size
        k = 0
        while k < nm
          m = msk[k]
          v1[m] = (p2[m] - st[m]) / span
          k += 1
      @hermite = true
    self

  # Quintic keyframes (Chunk#knot): a knot chunk starts from the previous
  # chunk's knot (its end velocity and acceleration) when that chunk was a
  # knot chunk too, with the command's velocity (and zero acceleration) when
  # it was a via chunk (as any chunk entered from a via chunk does: a run of
  # via keyframes can end on a knot of prescribed velocity), else at rest,
  # and ends at its own knot.
  -> plan_quintic(ch, prev)
    @quintic = ch.knot? && !ch.staggered? && ch.duration > ~0.0
    @kv0 = nil
    @ka0 = nil
    if @quintic && prev != nil && prev.knot?
      @kv0 = prev.knot_vel
      @ka0 = prev.knot_acc
    elsif @quintic && prev != nil && prev.via? && @cmd_vel != nil
      cv = @cmd_vel
      n = cv.size
      kv0 = []
      i = 0
      while i < n
        kv0.push(cv[i])
        i += 1
      @kv0 = kv0
    self

  -> next_index(ch)
    name = ch.static_successor
    if name != nil
      i = 0
      while i < @movement.size
        return i if @movement[i].name == name
        i += 1
      return -1
    nxt = @index + 1
    if nxt >= @movement.size
      return -1 if !@movement.looping
      nxt = @movement.loop_start
    nxt

  -> advance(ctl, frame)
    name = @movement[@index].successor(frame, ctl)
    return jump(ctl, frame, name) if name != nil
    nxt = @index + 1
    if nxt >= @movement.size
      if @movement.looping
        nxt = @movement.loop_start
      else
        @finished = true
        return self
    enter_chunk(ctl, frame, nxt)

  # Jump to a named chunk (skills use this to react to events).
  -> jump(ctl, frame, name)
    i = 0
    while i < @movement.size
      if @movement[i].name == name
        @finished = false
        return enter_chunk(ctl, frame, i)
      i += 1
    raise "no chunk [name] in [@movement.name]"

  # A via chunk whose keyframe (the end of its duration) fell inside the last
  # tick hands over at the keyframe, not at this tick: the next chunk's clock
  # starts at the keyframe time, from the keyframe, with the via tangent. Its
  # durations need not be multiples of the control tick (a truncated last
  # tick would otherwise slow the command and hand that slower velocity on).
  # A knot chunk that is also a via chunk (Chunk#knot plus #via) hands over
  # at its keyframe the same way, with its knot velocity; a knot chunk
  # without via keeps ending on the tick.
  -> pass_keyframes(ctl, frame)
    ch = @movement[@index]
    while !@finished && (@hermite || @quintic) && ch.via? && frame.t - @t0 > ch.duration && ends_on_time?(ch)
      t_key = @t0 + ch.duration
      v = @v1
      v = ch.knot_vel if @quintic
      cmd = ctl.command
      gl = @goal
      msk = @mask
      nm = msk.size
      k = 0
      while k < nm
        m = msk[k]
        cmd[m] = gl[m]
        k += 1
      advance(ctl, frame)
      return self if @finished
      @t0 = t_key
      @v0 = v if @hermite && @v0 != nil
      # (a knot chunk entered from this via chunk: its exact tangent)
      @kv0 = v if @quintic && @kv0 != nil
      ch = @movement[@index]
    self

  # The chunk ends when its duration runs out (no latch, or a timeout at the
  # duration), rather than on a latch.
  -> ends_on_time?(ch)
    return true if ch.latch == nil
    ch.timeout > ~0.0 && ch.timeout <= ch.duration

  -> update(ctl, frame)
    enter_chunk(ctl, frame, 0) if @index < 0
    pass_keyframes(ctl, frame)
    ch = @movement[@index]
    e = frame.t - @t0
    cmd = ctl.command
    st = @start
    gl = @goal
    msk = @mask
    nm = msk.size
    if ch.staggered?
      k = 0
      while k < nm
        m = msk[k]
        cmd[m] = st[m] + (gl[m] - st[m]) * ch.progress(m, e)
        k += 1
    elsif @hermite
      hermite_step(cmd, st, gl, e, ch.duration)
    elsif @quintic
      quintic_step(cmd, st, gl, e, ch)
    else
      p = ~1.0
      p = Easing.apply(ch.easing, e / ch.duration) if ch.duration > ~0.0
      k = 0
      while k < nm
        m = msk[k]
        cmd[m] = st[m] + (gl[m] - st[m]) * p
        k += 1
    track_velocity(cmd, ctl.dt)
    drv = ch.drive_values
    if drv != nil
      k = 0
      while k < nm
        m = msk[k]
        ctl.add_drive(m, drv[m])
        k += 1
    g = ch.gain_value
    k = 0
    while k < nm
      ctl.set_gain(msk[k], g)
      k += 1
    apply_correction(ctl, frame, ch)
    return self if @finished
    fired = false
    if ch.latch != nil
      fired = ch.latch.fired?(frame, e, ctl)
      fired = true if ch.timeout > ~0.0 && e >= ch.timeout
    else
      fired = e >= ch.span
    advance(ctl, frame) if fired
    self

  # Cubic Hermite from start (velocity v0) to goal (velocity v1) over T.
  -> hermite_step(cmd, st, gl, e, big_t)
    s = e / big_t
    s = ~1.0 if s > ~1.0
    s2 = s * s
    s3 = s2 * s
    h00 = ~2.0 * s3 - ~3.0 * s2 + ~1.0
    h10 = s3 - ~2.0 * s2 + s
    h01 = ~3.0 * s2 - ~2.0 * s3
    h11 = s3 - s2
    v0 = @v0
    v1 = @v1
    msk = @mask
    nm = msk.size
    k = 0
    while k < nm
      m = msk[k]
      a = ~0.0
      a = v0[m] if v0 != nil
      b = ~0.0
      b = v1[m] if v1 != nil
      cmd[m] = h00 * st[m] + h10 * big_t * a + h01 * gl[m] + h11 * big_t * b
      k += 1
    self

  # Quintic Hermite from start (the previous knot's velocity and
  # acceleration) to goal (this chunk's knot) over the chunk's duration. The
  # position term is the easing path's own expression, so zero knots add
  # exactly nothing to it.
  -> quintic_step(cmd, st, gl, e, ch)
    big_t = ch.duration
    p = Easing.apply(ch.easing, e / big_t)
    b = Quintic.basis(Easing.clamp01(e / big_t))
    tv = big_t
    ta = big_t * big_t
    tb0 = tv * b[0]
    tb1 = ta * b[1]
    tb2 = ta * b[2]
    tb3 = tv * b[3]
    v0 = @kv0
    a0 = @ka0
    v1 = ch.knot_vel
    a1 = ch.knot_acc
    msk = @mask
    nm = msk.size
    k = 0
    while k < nm
      m = msk[k]
      d = ~0.0
      d = d + tb0 * v0[m] if v0 != nil
      d = d + tb1 * a0[m] if a0 != nil
      d = d + tb2 * a1[m] if a1 != nil
      d = d + tb3 * v1[m] if v1 != nil
      cmd[m] = st[m] + (gl[m] - st[m]) * p + d
      k += 1
    self

  # Command velocity per muscle (feeds the next chunk's starting velocity).
  -> track_velocity(cmd, dt)
    if @prev_cmd == nil
      n = cmd.size
      pc = []
      cv = []
      i = 0
      while i < n
        pc.push(cmd[i])
        cv.push(~0.0)
        i += 1
      @prev_cmd = pc
      @cmd_vel = cv
      return self
    pc = @prev_cmd
    cv = @cmd_vel
    msk = @mask
    nm = msk.size
    k = 0
    while k < nm
      m = msk[k]
      cv[m] = (cmd[m] - pc[m]) / dt
      pc[m] = cmd[m]
      k += 1
    self

  # Spring-smoothed corrections: the chunk's correction function proposes
  # contraction offsets; the spring eases toward them (and back to zero when
  # the chunk has none), so corrections never step.
  -> apply_correction(ctl, frame, ch)
    callback = ch.correction
    if @spring == nil && callback == nil
      return self
    n = ctl.body.size
    if @spring == nil
      @spring = SpringVector.new(n, ch.spring_time, ~1.0)
      corr = []
      i = 0
      while i < n
        corr.push(~0.0)
        i += 1
      @corr = corr
    tgt = @corr
    i = 0
    while i < n
      tgt[i] = ~0.0
      i += 1
    msk = @mask
    nm = msk.size
    if callback != nil
      off = callback.call(frame, ctl)
      if off != nil
        k = 0
        while k < nm
          m = msk[k]
          tgt[m] = off[m]
          k += 1
    v = @spring.step(tgt, ctl.dt)
    k = 0
    while k < nm
      m = msk[k]
      ctl.add_offset(m, v[m])
      k += 1
    self

+ Controller
  ro :body
  ro :dt
  ro :command
  ro :reflex
  ro :skill
  -> new(@body, @dt, @skill)
    n = @body.size
    @command = Contraction.fill(n, ~0.5)
    @tracks = []
    @reflex = Reflex.new(n, ~6.0, ~0.25)
    @emits = []
    @drive = (0...n).map -> ~0.0
    @gain = (0...n).map -> ~1.0
    @offset = (0...n).map -> ~0.0
    @target = (0...n).map -> ~0.0
    @target_known = false
    @started = false
    @memory = {}
    @ff_gain = ~0.0
    @ff_on = []
    @ff_tau = nil
    @ff_groups = nil
    @recip = nil

  -> add_track(track)
    @tracks.push(track)
    track

  # Internal-model feed-forward (opt-in; bodies that send muscle geometry,
  # peak forces and the `bias` sensor, i.e. MyoSuite bodies). Each tick the
  # gravity + Coriolis torque at every joint is split over the selected
  # muscles able to supply it (minimum-norm over their torque per unit
  # activation) and added to their drive, so the reflexes only correct the
  # residual instead of waiting for gravity to open an error first.
  -> enable_feedforward(muscles, gain)
    @ff_gain = gain
    n = @body.size
    @ff_on = (0...n).map -> false
    muscles.each ->(m) @ff_on[m] = true
    self

  -> apply_feedforward(frame)
    g = @body.geometry
    return self if g == nil || @ff_gain == ~0.0 || !frame.has?("bias")
    q = frame.vec("q")
    j = 0
    while j < g.joint_count
      tau = frame.at("bias", j)
      split_torque(g, j, q, tau, @ff_gain) if tau > ~0.001 || tau < ~-0.001
      j += 1
    self

  # An extra feed-forward torque per geometry joint for this tick (nil =
  # none), split over the enable_feedforward muscles exactly as the bias is:
  # e.g. the inverse-dynamics term M[j, d] qacc_d of a joint d whose
  # acceleration loads the others (the bridge's `mcol_<joint>` blocks).
  # Independent of the bias gain, so it can run with the bias share off.
  -> set_feedforward_torque(tau)
    @ff_tau = tau
    self

  -> apply_torque_feedforward(frame)
    g = @body.geometry
    return self if g == nil
    q = frame.vec("q")
    return allocate_groups(g, q) if @ff_groups != nil
    j = 0
    while j < g.joint_count
      tau = @ff_tau[j]
      split_torque(g, j, q, tau, ~1.0) if tau > ~0.001 || tau < ~-0.001
      j += 1
    self

  # Joint allocation for the torque feed-forward (opt-in; without it every
  # joint's torque is split on its own). `groups` lists independent geometry
  # joints solved together (e.g. a shoulder's three axes), `couplings` the
  # equality-slaved joints as [dependent, independent, c] (q_dep = c q_ind).
  # A slaved joint's torque is folded onto its master (times c), and the
  # group's torques are met by the nonnegative minimum-norm activations of
  # the enabled muscles crossing it, each muscle's torque per unit
  # activation taken over the coupled motion (its arm about the master
  # plus c times its arms about the slaved joints); a muscle whose share
  # comes out negative is dropped and the rest re-solved. Muscles spanning
  # several axes then add up to the torque asked for instead of each axis
  # recruiting its own muscles blind to what they do about the others.
  -> set_feedforward_allocation(groups, couplings)
    @ff_groups = groups
    @ff_slaves = {}
    couplings.each ->(c)
      @ff_slaves[c[1]] = [] if !@ff_slaves.key?(c[1])
      @ff_slaves[c[1]].push([c[0], c[2]])
    @ff_members = nil
    self

  # The enabled muscles each group can load (built on first use, after
  # enable_feedforward has chosen them).
  -> group_members(g)
    return @ff_members if @ff_members != nil
    @ff_members = []
    @ff_groups.each ->(grp)
      seen = {}
      out = []
      grp.each ->(j)
        js = [j]
        slaves(j).each ->(sl) js.push(sl[0])
        js.each ->(k)
          g.crossing(k).each ->(m)
            if @ff_on[m] && !seen.key?(m)
              seen[m] = true
              out.push(m)
      @ff_members.push(out)
    @ff_members

  -> slaves(j)
    return @ff_slaves[j] if @ff_slaves.key?(j)
    []

  -> allocate_groups(g, q)
    members = group_members(g)
    gi = 0
    while gi < @ff_groups.size
      allocate_group(g, q, @ff_groups[gi], members[gi])
      gi += 1
    self

  -> allocate_group(g, q, grp, ms)
    k = grp.size
    nm = ms.size
    return self if nm == 0
    # the group's torques, slaved joints folded onto their masters, and
    # each muscle's torque per unit activation over the coupled motion
    tau = []
    rows = []
    big = false
    r = 0
    while r < k
      j = grp[r]
      sl = slaves(j)
      t = @ff_tau[j]
      s = 0
      while s < sl.size
        t = t + sl[s][1] * @ff_tau[sl[s][0]]
        s += 1
      tau.push(t)
      big = true if t > ~0.001 || t < ~-0.001
      row = []
      i = 0
      while i < nm
        m = ms[i]
        arm = g.moment_arm(m, j, q)
        s = 0
        while s < sl.size
          arm = arm + sl[s][1] * g.moment_arm(m, sl[s][0], q)
          s += 1
        row.push(~0.0 - arm * g.force(m))
        i += 1
      rows.push(row)
      r += 1
    return self if !big
    act = []
    a = []
    i = 0
    while i < nm
      act.push(true)
      a.push(~0.0)
      i += 1
    it = 0
    done = false
    while it < 8 && !done
      mat = []
      r = 0
      while r < k
        c = 0
        while c < k
          acc = ~0.0
          i = 0
          while i < nm
            acc = acc + rows[r][i] * rows[c][i] if act[i]
            i += 1
          mat.push(acc)
          c += 1
        r += 1
      lam = ~0.0
      r = 0
      while r < k
        lam = lam + mat[k * r + r]
        r += 1
      lam = lam * ~0.000001 / k + ~0.000000001
      rhs = []
      r = 0
      while r < k
        mat[k * r + r] = mat[k * r + r] + lam
        rhs.push(tau[r])
        r += 1
      y = solve_small(mat, rhs, k)
      done = true
      i = 0
      while i < nm
        if act[i]
          v = ~0.0
          r = 0
          while r < k
            v = v + rows[r][i] * y[r]
            r += 1
          a[i] = v
          if v < ~0.0
            act[i] = false
            done = false
        i += 1
      it += 1
    i = 0
    while i < nm
      @drive[ms[i]] = @drive[ms[i]] + a[i] if act[i] && a[i] > ~0.0
      i += 1
    self

  # Solve a x = b (n x n, flat row-major) by Gaussian elimination with
  # partial pivoting. Clobbers a and b.
  -> solve_small(a, b, n)
    i = 0
    while i < n
      p = i
      k = i + 1
      while k < n
        p = k if a[n * k + i].abs > a[n * p + i].abs
        k += 1
      if p != i
        c = 0
        while c < n
          sw = a[n * i + c]
          a[n * i + c] = a[n * p + c]
          a[n * p + c] = sw
          c += 1
        sw = b[i]
        b[i] = b[p]
        b[p] = sw
      d = a[n * i + i]
      d = ~0.000000000001 if d == ~0.0
      k = i + 1
      while k < n
        f = a[n * k + i] / d
        c = i
        while c < n
          a[n * k + c] = a[n * k + c] - f * a[n * i + c]
          c += 1
        b[k] = b[k] - f * b[i]
        k += 1
      i += 1
    x = []
    i = 0
    while i < n
      x.push(~0.0)
      i += 1
    i = n - 1
    while i >= 0
      acc = b[i]
      c = i + 1
      while c < n
        acc = acc - a[n * i + c] * x[c]
        c += 1
      d = a[n * i + i]
      d = ~0.000000000001 if d == ~0.0
      x[i] = acc / d
      i -= 1
    x

  # scale * tau at joint j as drive on the selected muscles able to supply
  # it: the minimum-norm activations over their torque per unit activation
  # (moment arm times peak force).
  -> split_torque(g, j, q, tau, scale)
    denom = ~0.0
    cr = g.crossing(j)
    nc = cr.size
    i = 0
    while i < nc
      m = cr[i]
      if @ff_on[m]
        arm = ~0.0 - g.moment_arm(m, j, q) * g.force(m)
        denom += arm * arm if arm * tau > ~0.0
      i += 1
    if denom > ~0.0
      factor = scale * tau / denom
      i = 0
      while i < nc
        m = cr[i]
        if @ff_on[m]
          arm = ~0.0 - g.moment_arm(m, j, q) * g.force(m)
          @drive[m] = @drive[m] + factor * arm if arm * tau > ~0.0
        i += 1
    self

  # Reciprocal inhibition (opt-in; off unless set): while a muscle is driven
  # (its feed-forward drive this tick: chunk bursts plus any feed-forward),
  # its antagonist's activation is scaled by max(0, 1 - k drive), and the
  # other way round, so a burst on a prime mover is not fought by its
  # antagonist's stretch reflex or tone (Sherrington's reciprocal
  # innervation; Ia reciprocal inhibition). `pairs` lists [a, b] muscle
  # indices; each pair inhibits both ways.
  -> set_reciprocal(pairs, k)
    @recip = pairs
    @recip_k = k
    self

  -> apply_reciprocal(acts)
    k = @recip_k
    drv = @drive
    rc = @recip
    nr = rc.size
    i = 0
    while i < nr
      pr = rc[i]
      a = pr[0]
      b = pr[1]
      sa = ~1.0 - k * drv[b]
      sb = ~1.0 - k * drv[a]
      sa = ~0.0 if sa < ~0.0
      sb = ~0.0 if sb < ~0.0
      acts[a] = acts[a] * sa if sa < ~1.0
      acts[b] = acts[b] * sb if sb < ~1.0
      i += 1
    acts

  -> track(name)
    ts = @tracks
    nt = ts.size
    i = 0
    while i < nt
      tr = ts[i]
      return tr if tr.name == name
      i += 1
    raise "no track [name]"

  -> emit(cmd)
    @emits.push(cmd)
    self

  # Set a non-muscle actuator (env action units); the body holds the value.
  -> motor(name, value)
    @emits.push("motor:" + name + ":" + value.to_s)
    self

  -> add_drive(i, a)
    @drive[i] = @drive[i] + a

  -> set_gain(i, g)
    @gain[i] = g

  -> add_offset(i, v)
    @offset[i] = @offset[i] + v

  # Skill scratch storage that persists across ticks.
  -> remember(key, value)
    @memory[key] = value

  -> recall(key, default = nil)
    return @memory[key] if @memory.key?(key)
    default

  -> target
    @target

  -> label
    ts = @tracks
    nt = ts.size
    if nt == 1
      tr = ts[0]
      return tr.name + ":" + tr.chunk_name
    parts = []
    i = 0
    while i < nt
      tr = ts[i]
      parts.push(tr.name + ":" + tr.chunk_name)
      i += 1
    parts.join("|")

  -> tick(frame)
    n = @body.size
    if !@started
      i = 0
      while i < n
        @command[i] = frame.c(i)
        i += 1
      @skill.start(frame, self)
      @started = true
    i = 0
    while i < n
      @drive[i] = ~0.0
      @gain[i] = ~1.0
      @offset[i] = ~0.0
      i += 1
    @skill.before(frame, self)
    ts = @tracks
    nt = ts.size
    ti = 0
    while ti < nt
      ts[ti].update(self, frame)
      ti += 1
    @skill.after(frame, self)
    apply_feedforward(frame) if @ff_gain != ~0.0
    apply_torque_feedforward(frame) if @ff_tau != nil
    acts = []
    ref = @reflex.referencing?
    integ = @reflex.integrating?
    vmax = Reflex.vref_max
    i = 0
    while i < n
      tg = @command[i] + @offset[i]
      tdot = ~0.0
      if ref && @target_known
        # the target's rate for velocity-referenced damping (opt-in)
        tdot = (tg - @target[i]) / @dt
        tdot = vmax if tdot > vmax
        tdot = ~0.0 - vmax if tdot < ~0.0 - vmax
      @target[i] = tg
      drv = @drive[i]
      fc = frame.c(i)
      drv = drv + @reflex.integral(i, tg, fc, @dt) if integ
      acts.push(@reflex.activation(i, tg, fc, frame.cdot(i), drv, @gain[i], tdot))
      i += 1
    @target_known = true
    apply_reciprocal(acts) if @recip != nil
    acts

  -> take_emits
    out = @emits
    @emits = []
    out
