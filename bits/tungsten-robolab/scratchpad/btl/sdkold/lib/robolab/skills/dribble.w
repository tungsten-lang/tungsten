# Dribble: a stationary basketball dribble on the pivot body, with both hands:
# single-hand dribbles, crossovers (hand to hand in front of the body, also on
# every bounce) and between-the-legs passes, run from a scripted sequence of
# moves (`mode` 0 keeps the original right-hand-only dribble).
#
# Four tracks run in parallel on disjoint muscle masks:
#
#   stance  legs, pelvis yaw, spine bend/twist: an athletic crouch, and the
#           staggered, widened stances a between-the-legs pass needs (the
#           lead foot steps forward, then the back foot back, each step a
#           lift chunk and a place chunk; a lead change steps the back foot
#           forward and the front foot back)
#   right   the right shoulder, elbow and wrist
#   left    the left arm, the mirror image (same chunks, same tuning)
#   trunk   spine flexion: the trunk pump that rides along with each push,
#           started by the active hand's chunks
#
# Each hand runs the same dribble chunks; joins latch on sensation:
#
#   start  hold ──(t_hold)──> lift ──(t_lift: ball raised, hand cocked)──>
#          throw ──(palm below z_rel)──> let_go (grip:r:0 on entry: the
#          fingers open mid-stroke) ──(t_push)──> recover   (right hand)
#   loop   recover ──(t_rec)──> wait ──(the rising ball will reach the strike
#          height within t_lead)──> swing ──(palm feels the ball)──> carry
#          ──(palm contact released)──> idle
#   moves  a crossover or a pass enters its own stroke instead of swing /
#          carry: x_swing, x_carry ──> idle_x and p_swing, p_carry ──> idle_p
#          (same latches; the low pose, drive burst and correction law are
#          the move's)
#   catch  b_recover, b_wait, b_swing, b_carry: the same cycle from a cocked
#          pose low beside the front hip, trunk straightened (a palm-down
#          catch there is out of reach with the dribbling lean), where a
#          between-the-legs pass comes up ──(released)──> idle_b
#
#   recover  the hand eases back up to the cocked pose above its home spot
#   wait     it hovers there while the correction steers the palm over the
#            ball's predicted apex, until the rising ball is t_lead seconds
#            from the strike height (a predictive visual latch)
#   swing    elbow, shoulder and wrist swing the hand down with a
#            feed-forward drive burst per joint group (the synergy that
#            shapes the hand's path; the antagonists let go), the trunk pumps
#   carry    the palm, now on the ball, keeps driving it down until the hand
#            brakes and the ball leaves it
#   idle     entered at every release: the move sequencer picks the next
#            move; a dribble jumps this hand straight back to recover, a
#            crossover or between-the-legs pass leaves this hand resting
#            (cocked over its home, out of the ball's way) and jumps the
#            other hand from its rest into recover (or b_recover)
#
# Moves (one script token per push): D dribble again with the same hand, X
# cross over to the other hand, B pass between the legs to the other hand.
# A move sets the push's target: D the hand's home spot (or, when a
# crossover or a pass comes next, the spot it starts from: in the crossover
# lane, or beside the back knee), X the other side of the crossover lane, B
# the spot beside the other side's front hip, past the gap between the feet.
# A hand's first push after it receives the ball has a catch law of its own
# (it must also stop the ball's sideways run).
#
# Why the hand meets the ball on its downswing instead of riding the rising
# ball up and pushing from rest: every floor bounce of a FIBA ball
# (restitution 0.77) takes ~40% of its energy, so a waist-high dribble needs
# ~3.4 m/s at release, and these muscles are slow (MuJoCo's Hill
# force-velocity curve with vmax = 1.5 optimal lengths per second, on damped
# joints). A reflex-servoed push from a hand resting on the ball accelerated
# at only ~1.3 g, so the ball simply fell away from the palm. The swing gets
# the hand moving before it touches the ball, the way a low "pound" dribble
# does; contact then lasts ~40-60 ms of carry.
#
# Every chunk after the launch carries the same spring-eased real-time
# correction, computed in hand space: the chunk's commanded arm angles give
# a palm position and normal through the arm's kinematic model (DribbleArm);
# the correction moves the palm over the ball's predicted apex while waiting
# (aiming past the measured miss, since the arm lags its command), lowers
# the whole stroke when the ball will not rise to the strike height, keeps
# the aim through the stroke (blended toward chasing the ball by
# carry_track), and tilts the palm normal toward the horizontal velocity
# that would carry the ball to the move's target in the move's flight time
# (plus, for dribbles, a slow integral on the drift); crossovers and passes
# also sweep the palm along that velocity (steer). A few Gauss-Newton steps
# of inverse kinematics turn that into joint offsets, then contraction
# offsets.

# 3x3 rotations as flat row-major arrays of 9 floats and 3-vectors as arrays
# of 3: just enough linear algebra for the arm's kinematic model.
+ DribbleMath
  -> .rx(t)
    c = Math.cos(t)
    s = Math.sin(t)
    [~1.0, ~0.0, ~0.0, ~0.0, c, ~0.0 - s, ~0.0, s, c]

  -> .ry(t)
    c = Math.cos(t)
    s = Math.sin(t)
    [c, ~0.0, s, ~0.0, ~1.0, ~0.0, ~0.0 - s, ~0.0, c]

  -> .rz(t)
    c = Math.cos(t)
    s = Math.sin(t)
    [c, ~0.0 - s, ~0.0, s, c, ~0.0, ~0.0, ~0.0, ~1.0]

  -> .mul(a, b)
    out = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    i = 0
    while i < 3
      j = 0
      while j < 3
        out[3 * i + j] = a[3 * i] * b[j] + a[3 * i + 1] * b[3 + j] + a[3 * i + 2] * b[6 + j]
        j += 1
      i += 1
    out

  # p + r * (x, y, z)
  -> .move(p, r, x, y, z)
    [p[0] + r[0] * x + r[1] * y + r[2] * z, p[1] + r[3] * x + r[4] * y + r[5] * z, p[2] + r[6] * x + r[7] * y + r[8] * z]

  -> .unit(x, y, z)
    n = Math.sqrt(x * x + y * y + z * z)
    return [~0.0, ~0.0, ~-1.0] if n < ~0.000001
    [x / n, y / n, z / n]

  -> .clamp(x, lo, hi)
    return lo if x < lo
    return hi if x > hi
    x

  # Solve a x = b for a symmetric positive definite n x n matrix (flat,
  # row-major); Gaussian elimination without pivoting. Clobbers a and b.
  -> .solve_spd(a, b, n)
    i = 0
    while i < n
      d = a[n * i + i]
      k = i + 1
      while k < n
        f = a[n * k + i] / d
        j = i
        while j < n
          a[n * k + j] = a[n * k + j] - f * a[n * i + j]
          j += 1
        b[k] = b[k] - f * b[i]
        k += 1
      i += 1
    x = (0...n).map -> ~0.0
    i = n - 1
    while i >= 0
      s = b[i]
      j = i + 1
      while j < n
        s = s - a[n * i + j] * x[j]
        j += 1
      x[i] = s / a[n * i + i]
      i -= 1
    x

# The controller's model of one arm (its body schema): segment offsets and
# joint axes mirror playground/body.py (shoulder 0.19 m lateral and 0.42 m up
# the torso, upper arm 0.30 m, forearm 0.26 m, palm face 0.018 m in front of
# the hand's axis; the ball meets the finger pads, 0.12 m down the spread
# hand the dribble task gives it, clear of the wrist). The base is the pelvis
# position, the pelvis yaw and the three spine angles; the arm has six
# joints: shoulder flex / abd / rot, elbow, wrist flex / dev. `fk` returns
# the palm's contact point and its outward normal; `solve` is the inverse.
+ DribbleArm
  ro :side
  ro :joints
  -> new(@body, @side)
    s = @side
    b = @body
    @joints = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev"].map -> s + "_" + item
    @ls = s == "r" ? ~-1.0 : ~1.0
    @lo = @joints.map -> b.muscle(b.pos_index(item)).qmin + ~0.02
    @hi = @joints.map -> b.muscle(b.pos_index(item)).qmax - ~0.02
    @w_normal = ~0.5
    @lambda = ~0.002

  -> fk(base, q)
    r = DribbleMath.rz(base[3])
    p = DribbleMath.move([base[0], base[1], base[2]], r, ~0.0, ~0.0, ~0.10)
    r = DribbleMath.mul(r, DribbleMath.ry(base[4]))
    r = DribbleMath.mul(r, DribbleMath.rx(base[5]))
    r = DribbleMath.mul(r, DribbleMath.rz(base[6]))
    p = DribbleMath.move(p, r, ~0.0, ~0.19 * @ls, ~0.42)
    r = DribbleMath.mul(r, DribbleMath.ry(~0.0 - q[0]))
    r = DribbleMath.mul(r, DribbleMath.rx(@ls * q[1]))
    r = DribbleMath.mul(r, DribbleMath.rz(~0.0 - @ls * q[2]))
    p = DribbleMath.move(p, r, ~0.0, ~0.0, ~-0.30)
    r = DribbleMath.mul(r, DribbleMath.ry(~0.0 - q[3]))
    p = DribbleMath.move(p, r, ~0.0, ~0.0, ~-0.26)
    r = DribbleMath.mul(r, DribbleMath.ry(q[4]))
    r = DribbleMath.mul(r, DribbleMath.rx(@ls * q[5]))
    p = DribbleMath.move(p, r, ~-0.018, ~0.0, ~-0.12)
    [p[0], p[1], p[2], ~0.0 - r[0], ~0.0 - r[3], ~0.0 - r[6]]

  -> residual(base, q, target, normal)
    h = fk(base, q)
    w = @w_normal
    [h[0] - target[0], h[1] - target[1], h[2] - target[2], w * (h[3] - normal[0]), w * (h[4] - normal[1]), w * (h[5] - normal[2])]

  # Arm angles near q0 that put the palm contact point at `target` with the
  # palm normal `normal`: damped Gauss-Newton on a numeric Jacobian,
  # regularised toward q0 so the answer stays close to the current posture
  # (six joints, five constraints: the spare degree of freedom goes to q0).
  -> solve(base, q0, target, normal, iters)
    q = q0.map -> item
    eps = ~0.0001
    k = 0
    while k < iters
      r = residual(base, q, target, normal)
      jac = (0...36).map -> ~0.0
      c = 0
      while c < 6
        q2 = q.map -> item
        q2[c] = q2[c] + eps
        r2 = residual(base, q2, target, normal)
        m = 0
        while m < 6
          jac[6 * m + c] = (r2[m] - r[m]) / eps
          m += 1
        c += 1
      a = (0...36).map -> ~0.0
      g = (0...6).map -> ~0.0
      i = 0
      while i < 6
        j = 0
        while j < 6
          s = ~0.0
          m = 0
          while m < 6
            s = s + jac[6 * m + i] * jac[6 * m + j]
            m += 1
          a[6 * i + j] = s
          j += 1
        a[7 * i] = a[7 * i] + @lambda
        s = ~0.0
        m = 0
        while m < 6
          s = s + jac[6 * m + i] * r[m]
          m += 1
        g[i] = ~0.0 - s - @lambda * (q[i] - q0[i])
        i += 1
      dq = DribbleMath.solve_spd(a, g, 6)
      i = 0
      while i < 6
        q[i] = DribbleMath.clamp(q[i] + dq[i], @lo[i], @hi[i])
        i += 1
      k += 1
    q

# One hand's state: its arm model, home spot and the correction's memory.
+ DribbleHand
  ro :side
  ro :name
  ro :arm
  ro :home
  ro :touch_k
  rw :aim
  rw :dz
  rw :zh
  rw :ix
  rw :iy
  rw :palm_prev
  rw :fresh
  -> new(body, @side, @home)
    @name = @side == "r" ? "right" : "left"
    @touch_k = @side == "r" ? 0 : 1
    @arm = DribbleArm.new(body, @side)
    @aim = nil
    @dz = ~0.0
    @zh = ~1.0
    @ix = ~0.0
    @iy = ~0.0
    @palm_prev = nil
    @fresh = false

  # This side's copy of a lateral coordinate authored for the right hand
  # (negative y): the body and the moves are mirror-symmetric.
  -> ys(y)
    return y if @side == "r"
    ~0.0 - y

  -> label
    @side == "r" ? "R" : "L"

+ DribbleSkill < Skill
  -> start(frame, ctl)
    read_params
    @radius = ~0.12
    @g = ~9.81
    @pelvis = [frame.at("pelvis_pos", 0), frame.at("pelvis_pos", 1), frame.at("pelvis_pos", 2)]
    home = [frame.at("ball_home", 0), frame.at("ball_home", 1)]
    @right = DribbleHand.new(body, "r", home)
    @left = DribbleHand.new(body, "l", [home[0], ~0.0 - home[1]])
    @script = script_for(@mode).split(" ")
    @step = 0
    @active = @right
    @move = "D"
    @target = home
    @stance = "a"
    @stance_pending = ""
    @hold_stance = false
    @setup = false
    arms_r = body.mask(["r_shoulder", "r_elbow", "r_wrist"])
    arms_l = body.mask(["l_shoulder", "l_elbow", "l_wrist"])
    trunk = body.mask(["spine_flex"])
    ctl.reflex.set_gains(arms_r, @arm_kp, @arm_kd)
    ctl.reflex.set_gains(arms_l, @arm_kp, @arm_kd) if @mode > ~0.5
    ctl.reflex.set_gains(body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]), @leg_kp, @leg_kd) if @mode > ~0.5
    used = []
    arms_r.each -> used.push(item)
    arms_l.each -> used.push(item)
    trunk.each -> used.push(item)
    # the trunk updates before the hands, so a pump a hand's chunk starts
    # takes effect from the next tick, as if the spine were in that chunk
    ctl.add_track(Track.new("stance", stance_movement, rest_of(used)))
    ctl.add_track(Track.new("trunk", trunk_movement, trunk))
    ctl.add_track(Track.new("right", hand_movement(@right), arms_r))
    ctl.add_track(Track.new("left", hand_movement(@left), arms_l))
    choose(frame, ctl, @right)

  -> read_params
    # what to play: 0 right hand only, 1 the showcase choreography, 2
    # crossovers on every bounce, 3 between-the-legs passes both ways, 4
    # crossovers, single and in a stretch on every bounce
    @mode = param("mode", ~0.0, ~0.0, ~4.0)
    # stance
    @spine = param("spine", ~0.45, ~0.2, ~0.7)
    @pump = param("pump", ~0.16, ~0.0, ~0.4)
    @stiff = param("stiff", ~0.06, ~0.0, ~0.3)
    @t_step = param("t_step", ~0.18, ~0.1, ~0.35)
    @leg_kp = param("leg_kp", ~12.0, ~4.0, ~20.0)
    @leg_kd = param("leg_kd", ~0.4, ~0.1, ~1.0)
    # arm servo
    @arm_kp = param("arm_kp", ~8.0, ~3.0, ~16.0)
    @arm_kd = param("arm_kd", ~0.3, ~0.05, ~1.0)
    @arm_stiff = param("arm_stiff", ~0.08, ~0.0, ~0.4)
    # stroke geometry in hand space: the cocked palm (height, fore-aft offset
    # from home, normal pitch; + pitch tilts the normal forward), the palm
    # height where it should meet the ball, and the end of the stroke
    @z_cock = param("z_cock", ~1.12, ~0.95, ~1.3)
    @dx_cock = param("dx_cock", ~0.03, ~-0.15, ~0.15)
    @pitch_cock = param("pitch_cock", ~0.3, ~-0.4, ~0.8)
    @z_hit = param("z_hit", ~0.97, ~0.85, ~1.1)
    @z_low = param("z_low", ~0.8, ~0.65, ~0.95)
    @dx_low = param("dx_low", ~-0.06, ~-0.2, ~0.15)
    @pitch_low = param("pitch_low", ~-0.2, ~-0.8, ~0.6)
    @dz_max = param("dz_max", ~0.15, ~0.0, ~0.4)
    @z_rel = param("z_rel", ~0.97, ~0.8, ~1.1)
    # timing: the stroke eases to the low pose over t_push (with the easing
    # push_ease picks: 0 min_jerk, 1 cubic_out, 2 expo_out, 3 step)
    @t_hold = param("t_hold", ~0.4, ~0.2, ~1.0)
    @t_lift = param("t_lift", ~0.4, ~0.2, ~0.8)
    @t_push = param("t_push", ~0.08, ~0.02, ~0.2)
    @push_ease = param("push_ease", ~1.5, ~0.0, ~3.99)
    @push_min = param("push_min", ~0.02, ~0.0, ~0.1)
    @push_max = param("push_max", ~0.2, ~0.08, ~0.35)
    @t_rec = param("t_rec", ~0.2, ~0.08, ~0.4)
    @t_lead = param("t_lead", ~0.07, ~0.0, ~0.2)
    # push burst (feed-forward activation on the muscles the stroke shortens,
    # per joint group, scaled by how far each joint travels), the stroke's
    # co-contraction (0: the antagonists let go, reciprocal inhibition) and
    # reflex gain scaling
    @drive_el = param("drive_el", ~1.0, ~0.0, ~1.0)
    @drive_sh = param("drive_sh", ~0.6, ~0.0, ~1.0)
    @drive_wr = param("drive_wr", ~0.6, ~0.0, ~1.0)
    @drive_sp = param("drive_sp", ~0.8, ~0.0, ~1.0)
    @push_stiff = param("push_stiff", ~0.0, ~0.0, ~0.3)
    @push_gain = param("push_gain", ~1.5, ~0.5, ~3.0)
    # sensing thresholds (ball weights)
    @touch_thr = param("touch_thr", ~0.3, ~0.05, ~2.0)
    @release_thr = param("release_thr", ~0.2, ~0.02, ~2.0)
    # corrections (dribble): palm tilt toward the velocity that brings the
    # ball home in t_home, the aim, and the slow drift integral
    @spring = param("spring", ~0.04, ~0.01, ~0.15)
    @tilt_kv = param("tilt_kv", ~0.35, ~0.0, ~0.8)
    @t_home = param("t_home", ~0.5, ~0.2, ~2.0)
    @carry_track = param("carry_track", ~0.5, ~0.0, ~1.0)
    @tilt_max = param("tilt_max", ~0.25, ~0.0, ~0.5)
    @reach = param("reach", ~0.15, ~0.0, ~0.3)
    @hand_fb = param("hand_fb", ~0.5, ~0.0, ~1.5)
    @hand_vfb = param("hand_vfb", ~0.02, ~0.0, ~0.1)
    @tilt_ki = param("tilt_ki", ~0.3, ~0.0, ~2.0)
    # crossover: the catch spot on the other side (x offset from its home, y
    # authored for the right side like every spot here, negative), and the
    # push's tilt gain, flight time, tilt limit and palm sweep
    @x_dx = param("x_dx", ~0.0, ~-0.15, ~0.15)
    @x_y = param("x_y", ~-0.25, ~-0.4, ~-0.12)
    @x_kv = param("x_kv", ~0.3, ~0.0, ~0.8)
    @x_t = param("x_t", ~0.5, ~0.25, ~1.0)
    @x_tmax = param("x_tmax", ~0.4, ~0.0, ~0.7)
    @x_steer = param("x_steer", ~0.05, ~0.0, ~0.2)
    # the catch: a hand's first push after it receives a crossover or a pass
    # has to stop the ball's sideways run as well as send it home
    @c_kv = param("c_kv", ~0.5, ~0.0, ~0.8)
    @c_tmax = param("c_tmax", ~0.5, ~0.0, ~0.7)
    # the crossover stroke: its low pose sits inward of the dribble's (x_dyl
    # toward the midline, x_dxl fore-aft) with the palm rolled x_roll toward
    # the midline, so the hand pushes the ball across as it comes down
    @x_dxl = param("x_dxl", ~0.0, ~-0.2, ~0.2)
    @x_dyl = param("x_dyl", ~0.22, ~0.0, ~0.4)
    @x_roll = param("x_roll", ~0.3, ~0.0, ~0.7)
    # between the legs: the setup spot beside the knee the pass starts from,
    # the catch spot behind the other side's front leg (and the cocked, strike
    # and low palm heights of the catching stroke), and the push's law
    @s_x = param("s_x", ~0.3, ~0.2, ~0.45)
    @s_y = param("s_y", ~-0.16, ~-0.35, ~-0.08)
    @b_x = param("b_x", ~0.0, ~-0.1, ~0.2)
    @b_y = param("b_y", ~-0.38, ~-0.48, ~-0.28)
    @b_zc = param("b_zc", ~0.95, ~0.8, ~1.1)
    @b_zh = param("b_zh", ~0.84, ~0.7, ~1.0)
    @b_zl = param("b_zl", ~0.72, ~0.6, ~0.9)
    @b_dxl = param("b_dxl", ~0.1, ~-0.1, ~0.25)
    @b_spine = param("b_spine", ~0.1, ~0.0, ~0.4)
    @b_kv = param("b_kv", ~0.8, ~0.0, ~1.0)
    @b_t = param("b_t", ~0.4, ~0.2, ~1.0)
    @b_tmax = param("b_tmax", ~0.7, ~0.0, ~0.8)
    @b_steer = param("b_steer", ~0.0, ~0.0, ~0.2)
    # the setup dribbles before a pass walk the ball to the setup spot
    @s_kv = param("s_kv", ~0.5, ~0.0, ~0.8)
    @s_tmax = param("s_tmax", ~0.4, ~0.0, ~0.6)
    # strike timing for transfers: the rising ball is met t_lead earlier for
    # a crossover (x_lead) or a pass (p_lead), so the push also reverses more
    # of its rise and has more authority sideways
    @x_lead = param("x_lead", ~0.07, ~0.0, ~0.2)
    @p_lead = param("p_lead", ~0.07, ~0.0, ~0.2)
    # the pass stroke: the dribble's stroke with its low pose moved back
    # (p_dxl), inward (p_dyl) and down (p_dzl), palm rolled inward p_roll
    @p_dxl = param("p_dxl", ~0.0, ~-0.3, ~0.1)
    @p_dyl = param("p_dyl", ~0.0, ~0.0, ~0.3)
    @p_dzl = param("p_dzl", ~0.0, ~-0.15, ~0.1)
    @p_roll = param("p_roll", ~0.0, ~0.0, ~0.6)

  # The scripts, one token per push. A between-the-legs pass needs its
  # stance: the feet step from the athletic crouch into the stagger during
  # the two setup dribbles before it (the timing the pass was practised
  # with), so a return pass waits six dribbles for the feet to come back to
  # the crouch first, and a dribble follows each pass catch before any
  # crossover.
  -> script_for(mode)
    return "D" if mode < ~0.5
    return "D D D B D D D D X D D D D X X X D D D D D D B D D D D X X X X X X D D D D" if mode < ~1.5
    return "X" if mode < ~2.5
    return "D D D B D D D D D D B D D D" if mode < ~3.5
    "D D D X D D D X D D X X X X D D"

  -> token(k)
    @script[k % @script.size]

  -> other_of(hand)
    return @left if hand.side == "r"
    @right

  -> active?(hand)
    hand.side == @active.side

  # Muscles not in `mask`.
  -> rest_of(mask)
    taken = {}
    mask.each -> taken[item] = true
    out = []
    body.all.each -> out.push(item) if !taken.key?(item)
    out

  # ---- the move sequencer ---------------------------------------------------

  # Pick `hand`'s next move from the script and aim its push; step the feet
  # into the stagger a between-the-legs pass within the next three pushes
  # needs (lead foot on the receiving side), or back out of it (the timing
  # the pass was practised with: the back leg steps back as the setup
  # dribbles walk the ball beside the back knee).
  -> choose(f, ctl, hand)
    @move = token(@step)
    @step += 1
    @setup = false
    t1 = token(@step)
    t2 = token(@step + 1)
    other = other_of(hand)
    if @move == "X"
      @target = [other.home[0] + @x_dx, other.ys(@x_y)]
    elsif @move == "B"
      @target = [@b_x, other.ys(@b_y)]
    elsif t1 == "B" || (t1 == "D" && t2 == "B")
      @target = [@s_x, hand.ys(@s_y)]
      @setup = true
    elsif t1 == "X"
      @target = [hand.home[0] + @x_dx, hand.ys(@x_y)]
    else
      @target = hand.home
    ctl.emit("plan:" + @move + ":" + hand.label)
    if @hold_stance
      @hold_stance = false
      return nil
    want = "a"
    h = hand
    k = 0
    while k < 3
      m = @move
      m = token(@step + k - 1) if k > 0
      if m == "B"
        want = other_of(h).side
        k = 5
      else
        h = other_of(h) if m != "D"
        k += 1
    set_stance(f, ctl, want)
    nil

  # Entered at every release (idle / idle_b of the active hand).
  -> released(f, ctl, hand)
    return nil if !active?(hand)
    hand.fresh = false
    done = @move
    if done == "D"
      choose(f, ctl, hand)
      ctl.track(hand.name).jump(ctl, f, "recover")
      return nil
    other = other_of(hand)
    @active = other
    other.ix = ~0.0
    other.iy = ~0.0
    other.aim = nil
    other.fresh = true
    @hold_stance = done == "B"
    choose(f, ctl, other)
    ctl.track(other.name).jump(ctl, f, done == "B" ? "b_recover" : "recover")
    nil

  -> trunk_to(f, ctl, hand, name)
    ctl.track("trunk").jump(ctl, f, name) if active?(hand)
    nil

  -> entering(f, ctl, hand, zh)
    hand.zh = zh
    trunk_to(f, ctl, hand, zh == @b_zh ? "b_up" : "up")

  # Entering a swing: the dribble's swing hands a crossover or a pass over to
  # that move's own stroke; every stroke announces the move and pumps.
  -> striking(f, ctl, hand, redirect)
    if redirect && active?(hand) && @move == "X"
      ctl.track(hand.name).jump(ctl, f, "x_swing")
      return nil
    if redirect && active?(hand) && @move == "B"
      ctl.track(hand.name).jump(ctl, f, "p_swing")
      return nil
    ctl.emit("move:" + @move + ":" + hand.label) if active?(hand)
    trunk_to(f, ctl, hand, "pump")

  -> b_striking(f, ctl, hand)
    ctl.emit("move:" + @move + ":" + hand.label) if active?(hand)
    trunk_to(f, ctl, hand, "b_pump")

  -> let_go(f, ctl, hand)
    ctl.emit("grip:r:0")
    trunk_to(f, ctl, hand, "pump")

  -> before(frame, ctl)
    return nil if @stance_pending == ""
    name = ctl.track("stance").chunk_name
    set_stance(frame, ctl, @stance_pending) if name == "athletic_l" || name == "athletic_r"
    nil

  # ---- stance -----------------------------------------------------------

  -> set_stance(f, ctl, want)
    return nil if want == @stance
    st = ctl.track("stance")
    if @stance == "a"
      st.jump(ctl, f, want + "_lift")
    elsif want == "a"
      st.jump(ctl, f, "a" + @stance + "_lift")
    else
      # switch the lead directly: the back foot steps forward, then the front
      # foot steps back
      st.jump(ctl, f, @stance + "2" + want + "_lift")
    @stance = want
    @stance_pending = ""
    nil

  # Leg joint angles (hip flex, abd, rot, knee, ankle): the athletic crouch
  # (feet under the hips, 0.3 m apart), a front leg (foot 0.34 m forward,
  # 0.20 m out) and a back leg (foot 0.18 m back, 0.28 m out, heel up),
  # solved offline for flat feet on the floor with the pelvis at 0.80 m. The
  # stagger was searched together with the pass lane: a ball released beside
  # the back knee at 1.9 m/s bounces between the feet and rises beside the
  # front hip clearing both legs by ~2 cm (a real between-the-legs lane).
  -> leg(kind, lifted)
    q = [~0.57, ~0.1, ~0.0, ~1.14, ~-0.57]
    q = [~0.778, ~0.109, ~0.084, ~0.679, ~0.087] if kind == "front"
    q = [~0.223, ~0.235, ~0.064, ~0.904, ~-0.59] if kind == "back"
    if lifted
      q[0] = q[0] + ~0.3
      q[3] = q[3] + ~0.6
    q

  -> stance_pose(lq, rq)
    p = Pose.new
    names = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"]
    i = 0
    while i < 5
      p.set("l_" + names[i], lq[i], @stiff)
      p.set("r_" + names[i], rq[i], @stiff)
      i += 1
    p.set("pelvis_yaw", ~0.0, @stiff)
    p.set("spine_lat", ~0.0, @stiff)
    p.set("spine_rot", ~0.0, @stiff)
    p

  -> lead_pose(lead, lead_kind, lead_lift, back_kind, back_lift)
    a = leg(lead_kind, lead_lift)
    b = leg(back_kind, back_lift)
    return stance_pose(a, b) if lead == "l"
    stance_pose(b, a)

  -> stance_movement
    never = Latch.test("never", ->(f, e, c) false)
    mv = Movement.new("stance")
    mv.add(Chunk.new("athletic", ~0.4).pose(lead_pose("l", "a", false, "a", false)).hold_until(never))
    ["l", "r"].each ->
      s = item
      mv.add(Chunk.new(s + "_lift", @t_step).pose(lead_pose(s, "front", true, "a", false)))
      mv.add(Chunk.new(s + "_place", @t_step).pose(lead_pose(s, "front", false, "a", false)))
      mv.add(Chunk.new(s + "_lift2", @t_step).pose(lead_pose(s, "front", false, "back", true)))
      mv.add(Chunk.new(s + "_lead", @t_step).pose(lead_pose(s, "front", false, "back", false)).hold_until(never))
      mv.add(Chunk.new("a" + s + "_lift", @t_step).pose(lead_pose(s, "a", true, "back", false)))
      mv.add(Chunk.new("a" + s + "_place", @t_step).pose(lead_pose(s, "a", false, "back", false)))
      mv.add(Chunk.new("a" + s + "_lift2", @t_step).pose(lead_pose(s, "a", false, "a", true)))
      mv.add(Chunk.new("athletic_" + s, @t_step).pose(lead_pose(s, "a", false, "a", false)).hold_until(never))
    ["l", "r"].each ->
      s = item
      o = s == "l" ? "r" : "l"
      # from lead s to lead o: s's back foot comes forward (it becomes o's
      # front foot), then s's front foot goes back
      mv.add(Chunk.new(s + "2" + o + "_lift", @t_step).pose(lead_pose(o, "front", true, "front", false)))
      mv.add(Chunk.new(s + "2" + o + "_place", @t_step).pose(lead_pose(o, "front", false, "front", false)))
      mv.add(Chunk.new(s + "2" + o + "_lift2", @t_step).pose(lead_pose(o, "front", false, "back", true)))
      mv.add(Chunk.new(s + "2" + o + "_lead", @t_step).pose(lead_pose(o, "front", false, "back", false)).hold_until(never))
    mv

  # ---- the trunk ------------------------------------------------------------

  -> spine_pose(q)
    p = Pose.new
    p.set("spine_flex", q, @stiff)
    p

  -> trunk_movement
    up = @spine - @pump * ~0.5
    down = @spine + @pump * ~0.5
    drv = zeros
    drv[body.pos_index("spine_flex")] = @drive_sp * DribbleMath.clamp(@pump / ~0.2, ~0.0, ~1.0)
    never = Latch.test("never", ->(f, e, c) false)
    mv = Movement.new("trunk")
    mv.add(Chunk.new("hold", ~0.3).pose(spine_pose(@spine)).hold_until(never))
    mv.add(Chunk.new("lift", @t_lift).pose(spine_pose(up)).hold_until(never))
    mv.add(Chunk.new("pump", @t_push).pose(spine_pose(down)).ease(ease_for(@push_ease)).drive(drv).gain(@push_gain).hold_until(never))
    mv.add(Chunk.new("up", @t_rec).pose(spine_pose(up)).hold_until(never))
    mv.add(Chunk.new("b_up", @t_rec).pose(spine_pose(@b_spine)).hold_until(never))
    mv.add(Chunk.new("b_pump", @t_push).pose(spine_pose(@b_spine + @pump)).ease(ease_for(@push_ease)).drive(drv).gain(@push_gain).hold_until(never))
    mv

  # ---- a hand ---------------------------------------------------------------

  # Arm angles with the palm at (x, y, z) and its normal pitched by `pitch`
  # (radians, + tilts it forward) while the trunk leans `spine`, solved from
  # a posture near the top of the dribble (the same seed serves both sides:
  # the left arm's joint axes are the mirror of the right's).
  -> arm_angles(hand, x, y, z, pitch, spine)
    arm_rolled(hand, x, y, z, pitch, ~0.0, spine)

  # ...with the normal also rolled by `roll` toward the midline.
  -> arm_rolled(hand, x, y, z, pitch, roll, spine)
    seed = [~0.55, ~0.05, ~-0.5, ~1.4, ~-0.05, ~0.1]
    base = [@pelvis[0], @pelvis[1], @pelvis[2], ~0.0, spine, ~0.0, ~0.0]
    normal = DribbleMath.unit(Math.sin(pitch), hand.ys(~0.0 - Math.sin(roll)), ~0.0 - Math.cos(pitch) * Math.cos(roll))
    hand.arm.solve(base, seed, [x, y, z], normal, 40)

  -> hand_pose(hand, q, stiff)
    p = Pose.new
    i = 0
    while i < 6
      p.set(hand.arm.joints[i], q[i], stiff)
      i += 1
    p

  # The left arm's guard in front of the body (right-hand-only mode).
  -> guard_pose
    p = Pose.new
    p.set("l_shoulder_flex", ~0.6, @stiff)
    p.set("l_shoulder_abd", ~0.25, @stiff)
    p.set("l_shoulder_rot", ~0.0, @stiff)
    p.set("l_elbow", ~1.3, @stiff)
    p.set("l_wrist_flex", ~0.0, @stiff)
    p.set("l_wrist_dev", ~0.0, @stiff)
    p

  # Feed-forward burst for a stroke from arm angles qa to qb: the muscle each
  # joint shortens gets that joint group's drive level (shoulder, elbow,
  # wrist: the synergy that shapes the hand's path), scaled down for joints
  # that barely move.
  -> burst(hand, qa, qb)
    levels = [@drive_sh, @drive_sh, @drive_sh, @drive_el, @drive_wr, @drive_wr]
    drv = zeros
    i = 0
    while i < 6
      dq = qb[i] - qa[i]
      j = hand.arm.joints[i]
      k = body.pos_index(j)
      k = body.neg_index(j) if dq < ~0.0
      drv[k] = levels[i] * DribbleMath.clamp(dq.abs / ~0.4, ~0.0, ~1.0)
      i += 1
    drv

  -> ease_for(x)
    return :min_jerk if x < ~1.0
    return :cubic_out if x < ~2.0
    return :expo_out if x < ~3.0
    :step

  -> hand_movement(hand)
    hx = hand.home[0]
    hy = hand.home[1]
    up = @spine - @pump * ~0.5
    down = @spine + @pump * ~0.5
    q_cock = arm_angles(hand, hx + @dx_cock, hy, @z_cock, @pitch_cock, up)
    q_low = arm_angles(hand, hx + @dx_low, hy, @z_low, @pitch_low, down)
    by = hand.ys(@b_y)
    q_bcock = arm_angles(hand, @b_x, by, @b_zc, @pitch_cock, @b_spine)
    q_blow = arm_angles(hand, @b_x + @b_dxl, by, @b_zl, @pitch_low, @b_spine + @pump)
    q_xlow = arm_rolled(hand, hx + @dx_low + @x_dxl, hy + hand.ys(~0.0 - @x_dyl), @z_low, @pitch_low, @x_roll, down)
    q_plow = arm_rolled(hand, hx + @dx_low + @p_dxl, hy + hand.ys(~0.0 - @p_dyl), @z_low + @p_dzl, @pitch_low, @p_roll, down)
    cock = hand_pose(hand, q_cock, @arm_stiff)
    low = hand_pose(hand, q_low, @push_stiff)
    bcock = hand_pose(hand, q_bcock, @arm_stiff)
    blow = hand_pose(hand, q_blow, @push_stiff)
    xlow = hand_pose(hand, q_xlow, @push_stiff)
    plow = hand_pose(hand, q_plow, @push_stiff)
    rest = cock
    rest = guard_pose if @mode < ~0.5 && hand.side == "l"
    drv = burst(hand, q_cock, q_low)
    bdrv = burst(hand, q_bcock, q_blow)
    xdrv = burst(hand, q_cock, q_xlow)
    pdrv = burst(hand, q_cock, q_plow)
    ease = ease_for(@push_ease)
    meet = ->(f, c) hand_fix(f, c, hand, :meet)
    carry = ->(f, c) hand_fix(f, c, hand, :carry)
    idle = ->(f, c) nil
    k = hand.touch_k
    touch = Latch.above("ball_touch", k, @touch_thr)
    released = Latch.below("ball_touch", k, @release_thr).after_min(@push_min)
    arrive = Latch.test("arrive", ->(f, e, c) arrival(f, hand) < lead(hand))
    never = Latch.test("never", ->(f, e, c) false)
    zh = @z_hit
    bzh = @b_zh

    mv = Movement.new(hand.name)
    if hand.side == "r"
      q_hold = arm_angles(hand, hx, hy, ~0.99, ~0.0, @spine)
      hold = hand_pose(hand, q_hold, @arm_stiff)
      mv.add(Chunk.new("hold", ~0.3).pose(hold).hold_until(Latch.after(@t_hold)).correct(idle, @spring).on_enter(->(f, c) trunk_to(f, c, hand, "hold")))
      mv.add(Chunk.new("lift", @t_lift).pose(cock).on_enter(->(f, c) trunk_to(f, c, hand, "lift")))
      mv.add(Chunk.new("throw", @t_push).pose(low).ease(ease).drive(drv).gain(@push_gain).hold_until(Latch.below("r_hand_pos", 2, @z_rel), @push_max).on_enter(->(f, c) trunk_to(f, c, hand, "pump")))
      mv.add(Chunk.new("let_go", @t_push).pose(low).ease(ease).drive(drv).gain(@push_gain).on_enter(->(f, c) let_go(f, c, hand)))
    else
      mv.add(Chunk.new("rest", ~0.3).pose(rest).hold_until(never).correct(idle, @spring))
    mv.add(Chunk.new("recover", @t_rec).pose(cock).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, zh)))
    mv.add(Chunk.new("wait", ~0.05).pose(cock).hold_until(arrive, ~1.5).correct(meet, @spring))
    mv.add(Chunk.new("swing", @t_push).pose(low).ease(ease).drive(drv).gain(@push_gain).hold_until(touch, @push_max).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, true)))
    mv.add(Chunk.new("carry", @t_push).pose(low).ease(ease).drive(drv).gain(@push_gain).hold_until(released, @push_max).correct(carry, @spring).on_enter(->(f, c) trunk_to(f, c, hand, "pump")))
    mv.add(Chunk.new("idle", @t_rec).pose(rest).hold_until(never).on_enter(->(f, c) released(f, c, hand)))
    mv.add(Chunk.new("x_swing", @t_push).pose(xlow).ease(ease).drive(xdrv).gain(@push_gain).hold_until(touch, @push_max).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false)))
    mv.add(Chunk.new("x_carry", @t_push).pose(xlow).ease(ease).drive(xdrv).gain(@push_gain).hold_until(released, @push_max).correct(carry, @spring).on_enter(->(f, c) trunk_to(f, c, hand, "pump")))
    mv.add(Chunk.new("idle_x", @t_rec).pose(rest).hold_until(never).on_enter(->(f, c) released(f, c, hand)))
    mv.add(Chunk.new("p_swing", @t_push).pose(plow).ease(ease).drive(pdrv).gain(@push_gain).hold_until(touch, @push_max).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false)))
    mv.add(Chunk.new("p_carry", @t_push).pose(plow).ease(ease).drive(pdrv).gain(@push_gain).hold_until(released, @push_max).correct(carry, @spring).on_enter(->(f, c) trunk_to(f, c, hand, "pump")))
    mv.add(Chunk.new("idle_p", @t_rec).pose(rest).hold_until(never).on_enter(->(f, c) released(f, c, hand)))
    mv.add(Chunk.new("b_recover", @t_rec).pose(bcock).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, bzh)))
    mv.add(Chunk.new("b_wait", ~0.05).pose(bcock).hold_until(arrive, ~1.5).correct(meet, @spring))
    mv.add(Chunk.new("b_swing", @t_push).pose(blow).ease(ease).drive(bdrv).gain(@push_gain).hold_until(touch, @push_max).correct(carry, @spring).on_enter(->(f, c) b_striking(f, c, hand)))
    mv.add(Chunk.new("b_carry", @t_push).pose(blow).ease(ease).drive(bdrv).gain(@push_gain).hold_until(released, @push_max).correct(carry, @spring).on_enter(->(f, c) trunk_to(f, c, hand, "b_pump")))
    mv.add(Chunk.new("idle_b", @t_rec).pose(rest).hold_until(never).on_enter(->(f, c) released(f, c, hand)))
    mv

  # The push's law for `hand`: [target x, target y, tilt gain, flight time,
  # tilt limit, palm sweep, drift integral on/off, limit on the tilt's
  # length]. A resting hand keeps its home dribble law.
  # tilt limit applied to the tilt vector's length (1) or per axis (0; the
  # dribble law, as it was tuned).
  -> move_law(hand)
    if active?(hand) && @move == "X"
      return [@target[0], @target[1], @x_kv, @x_t, @x_tmax, @x_steer, ~0.0, ~1.0]
    if active?(hand) && @move == "B"
      return [@target[0], @target[1], @b_kv, @b_t, @b_tmax, @b_steer, ~0.0, ~1.0]
    t = hand.home
    t = @target if active?(hand)
    return [t[0], t[1], @c_kv, @t_home, @c_tmax, ~0.0, ~0.0, ~1.0] if active?(hand) && hand.fresh
    return [t[0], t[1], @s_kv, @t_home, @s_tmax, ~0.0, ~0.0, ~1.0] if active?(hand) && @setup
    [t[0], t[1], @tilt_kv, @t_home, @tilt_max, ~0.0, ~1.0, ~0.0]

  # Palm tilt (added to the stroke's own palm normal) toward the horizontal
  # velocity that carries the ball to the law's target in its flight time,
  # less the velocity it has, plus (for dribbles) a slow integral on drift.
  -> palm_tilt(f, hand, law)
    bx = f.at("ball_pos", 0)
    by = f.at("ball_pos", 1)
    if f.at("ball_vel", 2) < ~0.0
      bx = f.at("ball_apex", 0)
      by = f.at("ball_apex", 1)
    vx = (law[0] - bx) / law[3] - f.at("ball_vel", 0)
    vy = (law[1] - by) / law[3] - f.at("ball_vel", 1)
    tilt_x = law[2] * vx - @tilt_ki * hand.ix * law[6]
    tilt_y = law[2] * vy - @tilt_ki * hand.iy * law[6]
    if law[7] > ~0.5
      len = Math.sqrt(tilt_x * tilt_x + tilt_y * tilt_y)
      if len > law[4]
        tilt_x = tilt_x * law[4] / len
        tilt_y = tilt_y * law[4] / len
      return [tilt_x, tilt_y]
    [DribbleMath.clamp(tilt_x, ~0.0 - law[4], law[4]), DribbleMath.clamp(tilt_y, ~0.0 - law[4], law[4])]

  -> lead(hand)
    return @x_lead if active?(hand) && @move == "X"
    return @p_lead if active?(hand) && @move == "B"
    @t_lead

  # Seconds until the rising ball's centre reaches the height where this
  # hand's palm meets it (its apex, if it will not rise that far); a long
  # time while the ball is still falling toward the floor, none when a slow
  # ball is already up there.
  -> arrival(f, hand)
    z = f.at("ball_pos", 2)
    vz = f.at("ball_vel", 2)
    zh = hand.zh - @radius + hand.dz
    if vz <= ~0.0
      return ~0.0 if z > zh && vz > ~-1.0
      return ~9.0
    disc = vz * vz - ~2.0 * @g * (zh - z)
    return vz / @g if disc < ~0.0
    (vz - Math.sqrt(disc)) / @g

  -> base_now(f)
    [f.at("pelvis_pos", 0), f.at("pelvis_pos", 1), f.at("pelvis_pos", 2), f.joint_angle(body, "pelvis_yaw"), f.joint_angle(body, "spine_flex"), f.joint_angle(body, "spine_lat"), f.joint_angle(body, "spine_rot")]

  -> arm_measured(f, hand)
    b = body
    hand.arm.joints.map -> f.joint_angle(b, item)

  -> arm_command(ctl, hand)
    cmd = ctl.command
    b = body
    hand.arm.joints.map -> cmd.joint_angle(b, item)

  # Hand-space correction. :meet (recover, wait) moves the palm over the
  # ball's predicted apex and, when that apex is below the strike height,
  # lowers the whole stroke to match (remembered in hand.dz for the stroke);
  # :carry (swing, carry) keeps that aim (blended toward chasing the ball by
  # carry_track) and sweeps the palm along the move's demanded velocity. The
  # palm contact point sits where the tilted palm touches the ball.
  -> hand_fix(f, ctl, hand, mode)
    return nil if f.get("ball_held") > ~0.5
    base = base_now(f)
    q = arm_command(ctl, hand)
    h = hand.arm.fk(base, q)
    bx = f.at("ball_pos", 0)
    by = f.at("ball_pos", 1)
    if mode == :meet
      bx = f.at("ball_apex", 0)
      by = f.at("ball_apex", 1)
      hand.dz = DribbleMath.clamp(f.at("ball_apex", 2) + @radius - hand.zh, ~0.0 - @dz_max, ~0.0)
    law = move_law(hand)
    hand.ix = hand.ix + (f.at("ball_pos", 0) - law[0]) * ctl.dt
    hand.iy = hand.iy + (f.at("ball_pos", 1) - law[1]) * ctl.dt
    tilt = palm_tilt(f, hand, law)
    n = DribbleMath.unit(h[3] + tilt[0], h[4] + tilt[1], h[5])
    # where the palm really is (the arm lags and droops behind its command):
    # aim past the target by hand_fb times the miss and, on the stroke, by
    # hand_vfb seconds of the palm's horizontal slip against the ball, so it
    # comes down over the ball instead of dragging it sideways
    m = hand.arm.fk(base, arm_measured(f, hand))
    vx = ~0.0
    vy = ~0.0
    if hand.palm_prev != nil
      vx = (m[0] - hand.palm_prev[0]) / ctl.dt
      vy = (m[1] - hand.palm_prev[1]) / ctl.dt
    hand.palm_prev = m
    tx = bx - @radius * n[0]
    ty = by - @radius * n[1]
    tx = tx + @hand_fb * (tx - m[0])
    ty = ty + @hand_fb * (ty - m[1])
    if mode == :carry
      tx = tx + @hand_vfb * (f.at("ball_vel", 0) - vx)
      ty = ty + @hand_vfb * (f.at("ball_vel", 1) - vy)
    tx = DribbleMath.clamp(tx, h[0] - @reach, h[0] + @reach)
    ty = DribbleMath.clamp(ty, h[1] - @reach, h[1] + @reach)
    # the aim taken while waiting is kept through the stroke, blended toward
    # chasing the ball by carry_track (0: come straight down on the aim)
    if mode == :meet
      hand.aim = [tx, ty]
    elsif hand.aim != nil
      tx = hand.aim[0] + @carry_track * (tx - hand.aim[0])
      ty = hand.aim[1] + @carry_track * (ty - hand.aim[1])
    if mode == :carry
      tx = tx + law[5] * ((law[0] - f.at("ball_pos", 0)) / law[3] - f.at("ball_vel", 0))
      ty = ty + law[5] * ((law[1] - f.at("ball_pos", 1)) / law[3] - f.at("ball_vel", 1))
    qd = hand.arm.solve(base, q, [tx, ty, h[2] + hand.dz], n, 2)
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], qd[i] - q[i])
      i += 1
    off
