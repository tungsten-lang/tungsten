# MyoDieV3: die reorientation (MyoDieSkill: cup, six finger flips, fine
# correction) with two round-3 additions, each opt-in by params (all off:
# MyoDieSkill):
#
#   tilt primitives  four palm rolls: the cup plus an amplitude vector over
#            the 14 joint groups and a forearm rotation (`tilt_*_ps`: the
#            upturned palm pronates away from its supination limit, which
#            the fingers alone cannot do), so the die rolls over an edge of
#            the palm instead of being flicked by a finger. Named by the palm
#            axis they nominally roll about (tilt_xp: +x, ...); enabled by
#            `tilts` = 1.
#   greedy   the primitive is chosen by the rotation it is measured to cause,
#            not by the largest component of the rotation still to do: each
#            primitive k carries its mean effect e_k (a rotation vector in
#            the palm frame, tunables `e_<name>_x/y/z`, filled in by a
#            calibration run with `force` = k), and the controller picks
#            the k minimising the angle of R_rem R(e_k)^T (the rotation left
#            after it), or the fine correction when none beats staying by
#            `g_margin`.
#   force    calibration: after the cup, run primitive `force` (0-5 flips
#            xp xn yp yn zp zn, 6-9 tilts xp xn yp yn) once, then hold the
#            cup; the task measures the die's rotation over the chunk.

+ MyoDieV3Skill < MyoDieSkill
  -> start(frame, ctl)
    @prims = ["flip_xp", "flip_xn", "flip_yp", "flip_yn", "flip_zp", "flip_zn", "tilt_xp", "tilt_xn", "tilt_yp", "tilt_yn"]
    @tilts = param("tilts", ~0.0, ~0.0, ~1.0) > ~0.5
    @greedy = param("greedy", ~0.0, ~0.0, ~1.0) > ~0.5
    @force = param("force", ~-1.0, ~-1.0, ~9.0).round
    @forced = 0
    @g_margin = param("g_margin", ~0.1, ~0.0, ~0.8)
    nominal = [[~1.2, ~0.0, ~0.0], [~-1.2, ~0.0, ~0.0], [~0.0, ~1.2, ~0.0], [~0.0, ~-1.2, ~0.0], [~0.0, ~0.0, ~1.2], [~0.0, ~0.0, ~-1.2], [~1.2, ~0.0, ~0.0], [~-1.2, ~0.0, ~0.0], [~0.0, ~1.2, ~0.0], [~0.0, ~-1.2, ~0.0]]
    @eff = []
    k = 0
    while k < 10
      nk = nominal[k]
      pre = "e_" + @prims[k] + "_"
      @eff.push([param(pre + "x", nk[0], ~-3.2, ~3.2), param(pre + "y", nk[1], ~-3.2, ~3.2), param(pre + "z", nk[2], ~-3.2, ~3.2)])
      k += 1
    @axes = [0, 0, 1, 1, 2, 2, 0, 0, 1, 1]
    @ps_off = ~0.0
    super(frame, ctl)

  # The palm rolls (see the header); nominal defaults: pronate to roll the
  # die toward the ulnar side (about y), flex / extend the wrist (about x).
  -> extra_primitives(mv, route, cup, stiff, t_flip, to_flip)
    return nil if !@tilts && @force < 6
    t_tilt = param("t_tilt", ~0.25, ~0.05, ~0.6)
    to_tilt = param("to_tilt", ~0.5, ~0.1, ~0.9)
    # nominal defaults [pro_sup, wrist flexion]
    defaults = [[~0.0, ~0.4], [~0.0, ~-0.4], [~0.5, ~0.0], [~0.0, ~0.0]]
    k = 0
    while k < 4
      name = @prims[6 + k]
      d = defaults[k]
      amp = @names.map ->(n) ~0.0
      i = 0
      while i < @names.size
        dflt = ~0.0
        dflt = d[1] if i == 1
        amp[i] = param(name + "_" + @names[i], dflt, ~-0.8, ~0.8)
        i += 1
      ps = param(name + "_ps", d[0], ~0.0, ~1.4)
      state = (0...cup.size).map ->(i) cup[i] + amp[i]
      done = Latch.test("flipped", ->(f, e, c) @turned > @flip_done)
      mv.add(Chunk.new(name, t_tilt).pose(posture_ps(state, stiff, ps)).hold_until(done.after_min(t_tilt * ~0.5), to_tilt).on_enter(->(f, c) start_flip(f)).branch(route))
      k += 1
    nil

  # Posture with the forearm pronated `ps` from the palm-up default.
  -> posture_ps(v, stiff, ps)
    p = posture(v, stiff)
    p.set("pro_sup", ~-1.5 + ps, stiff)
    p

  -> choose(f)
    if @force >= 0
      return "fine" if @forced > 0
      @forced = 1
      set_axis(@force)
      return @prims[@force]
    return super(f) if !@greedy
    rv = f.vec("rot_vec")
    rem = rodrigues(rv[0], rv[1], rv[2])
    best = angle_of(rem) - @g_margin
    pick = -1
    n = 6
    n = 10 if @tilts
    k = 0
    while k < n
      e = @eff[k]
      a = angle_of(mul_t(rem, rodrigues(e[0], e[1], e[2])))
      if a < best
        best = a
        pick = k
      k += 1
    @next = "fine"
    return "fine" if pick < 0 || largest(f) < @flip_min
    set_axis(pick)
    @next = @prims[pick]
    @next

  # The turned-latch's axis and sign: the primitive's nominal axis.
  -> set_axis(k)
    @axis = @axes[k]
    @sign = 1
    @sign = -1 if k % 2 == 1
    nil

  # ---- 3 x 3 rotations (row-major flat arrays) ------------------------------

  -> rodrigues(x, y, z)
    th = Math.sqrt(x * x + y * y + z * z)
    return [~1.0, ~0.0, ~0.0, ~0.0, ~1.0, ~0.0, ~0.0, ~0.0, ~1.0] if th < ~0.000001
    kx = x / th
    ky = y / th
    kz = z / th
    s = Math.sin(th)
    c = ~1.0 - Math.cos(th)
    r = [~1.0 + c * (kx * kx - ~1.0), c * kx * ky - s * kz, c * kx * kz + s * ky]
    r.push(c * kx * ky + s * kz)
    r.push(~1.0 + c * (ky * ky - ~1.0))
    r.push(c * ky * kz - s * kx)
    r.push(c * kx * kz - s * ky)
    r.push(c * ky * kz + s * kx)
    r.push(~1.0 + c * (kz * kz - ~1.0))
    r

  # a * b^T
  -> mul_t(a, b)
    out = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    i = 0
    while i < 3
      j = 0
      while j < 3
        out[3 * i + j] = a[3 * i] * b[3 * j] + a[3 * i + 1] * b[3 * j + 1] + a[3 * i + 2] * b[3 * j + 2]
        j += 1
      i += 1
    out

  -> angle_of(r)
    Math.acos(clamp((r[0] + r[4] + r[8] - ~1.0) * ~0.5, ~-1.0, ~1.0))
