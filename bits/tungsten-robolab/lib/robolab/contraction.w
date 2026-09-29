# Contraction: the state vector of the control plane, one entry per muscle,
# each a contraction fraction (0 = fully lengthened, 1 = fully contracted;
# see Body). Rate: a contraction-per-second vector, the velocity of a piece
# of movement. Chunks integrate rates into contraction states.
#
# Posture authoring helpers build contraction vectors from joint angles, so a
# skill can say "hip 0.9 rad, knee 0.3 rad, stiff 0.2" and get the pair of
# muscle contractions (with co-contraction) that holds that posture.

+ Contraction
  ro :values
  -> new(@values)

  -> .zeros(n)
    Contraction.new((0...n).map -> ~0.0)

  -> .fill(n, v)
    Contraction.new((0...n).map -> v)

  # Relaxed posture: every pair at its joint's current angle with no
  # co-contraction is not known without sensors, so rest is the midpoint.
  -> .rest(body)
    Contraction.fill(body.size, ~0.5)

  # Measured contraction from a sensor frame.
  -> .measured(frame)
    n = frame.muscle_count
    Contraction.new((0...n).map -> frame.c(item))

  -> size
    @values.size

  -> [](i)
    @values[i]

  -> []=(i, v)
    @values[i] = v

  -> copy
    Contraction.new(@values.map -> item)

  -> +(other)
    o = other.values
    Contraction.new((0...@values.size).map -> @values[item] + o[item])

  -> -(other)
    o = other.values
    Contraction.new((0...@values.size).map -> @values[item] - o[item])

  -> scale(s)
    Contraction.new(@values.map -> item * s)

  # Componentwise a + (b - a) * t.
  -> lerp(other, t)
    o = other.values
    Contraction.new((0...@values.size).map -> @values[item] + (o[item] - @values[item]) * t)

  # Set joint `joint` to angle q with co-contraction `stiff` (0 = none; 0.2
  # means each muscle is commanded 0.1 shorter than the posture needs).
  -> set_joint(body, joint, q, stiff = ~0.0)
    p = body.pos_index(joint)
    n = body.neg_index(joint)
    raise "no joint [joint]" if p == nil
    @values[p] = body.muscle(p).contraction_at(q) + stiff * ~0.5
    @values[n] = body.muscle(n).contraction_at(q) + stiff * ~0.5
    self

  # Joint angle this contraction vector commands at `joint` (the midpoint of
  # the pair's two commands, which is where the reflexes balance).
  -> joint_angle(body, joint)
    p = body.pos_index(joint)
    n = body.neg_index(joint)
    qa = body.muscle(p).angle_at(@values[p])
    qb = body.muscle(n).angle_at(@values[n])
    (qa + qb) * ~0.5

  -> set(body, name, v)
    @values[body.index(name)] = v
    self

  -> to_s
    @values.join(" ")

# Contraction velocity: d(contraction)/dt per muscle, in 1/s.
+ Rate
  ro :values
  -> new(@values)

  -> .zeros(n)
    Rate.new((0...n).map -> ~0.0)

  -> .between(from, to, seconds)
    f = from.values
    t = to.values
    inv = ~1.0 / seconds
    Rate.new((0...f.size).map -> inv * (t[item] - f[item]))

  -> [](i)
    @values[i]

  # Displacement after `seconds` at this rate.
  -> over(seconds)
    Contraction.new(@values.map -> item * seconds)

# A posture: joint angles plus stiffness, turned into a Contraction on demand.
# Only joints named here are written; the rest of the base vector is kept.
+ Pose
  -> new
    @joints = []
    @angles = []
    @stiff = []

  -> set(joint, q, stiff = ~0.0)
    @joints.push(joint)
    @angles.push(q)
    @stiff.push(stiff)
    self

  -> joints
    @joints

  # Mirror left/right: swaps l_ and r_ joint names.
  -> mirror
    out = Pose.new
    i = 0
    while i < @joints.size
      j = @joints[i]
      if j.starts_with?("l_")
        j = "r_" + j.slice(2, j.size - 2)
      elsif j.starts_with?("r_")
        j = "l_" + j.slice(2, j.size - 2)
      out.set(j, @angles[i], @stiff[i])
      i += 1
    out

  -> apply(body, base)
    g = body.geometry
    return apply_geometry(body, g, base) if g != nil
    c = base.copy
    i = 0
    while i < @joints.size
      c.set_joint(body, @joints[i], @angles[i], @stiff[i]) if body.has_joint?(@joints[i])
      i += 1
    c

  # Multi-joint bodies: every muscle crossing a posed joint gets the
  # contraction it has at the posture (unposed joints at the reference
  # posture), plus half the largest stiffness among its posed joints.
  -> apply_geometry(body, g, base)
    c = base.copy
    q = g.reference_posture
    n = body.size
    touched = (0...n).map -> false
    stiff = (0...n).map -> ~0.0
    i = 0
    while i < @joints.size
      j = g.joint(@joints[i])
      if j != nil
        q[j] = @angles[i]
        s = @stiff[i]
        g.crossing(j).each ->(m)
          touched[m] = true
          stiff[m] = s if s > stiff[m]
      i += 1
    m = 0
    while m < n
      c[m] = g.contraction(m, q) + stiff[m] * ~0.5 if touched[m]
      m += 1
    c

  # Indices of the muscles this pose writes.
  -> muscles(body)
    out = []
    @joints.each ->
      if body.has_joint?(item)
        out.push(body.pos_index(item))
        out.push(body.neg_index(item))
    out
