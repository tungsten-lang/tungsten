# Skill: a named motor program. Subclasses declare tunable parameters with
# `param` (so an optimizer can practise them), build their movements as
# tracks in `start`, and may add task logic in `before` / `after`.

+ Skill
  ro :body
  ro :params
  -> new(@body, @params)
    @declared = []

  # A tunable number: the override from the optimizer if present, else the
  # default. lo/hi bound the search.
  -> param(name, default, lo, hi)
    @declared.push("TUNABLE [name] [default] [lo] [hi]")
    return @params[name] if @params.key?(name)
    default

  -> describe
    @declared

  -> start(frame, ctl)

  -> before(frame, ctl)

  -> after(frame, ctl)

  # Helpers shared by skills.

  -> clamp(x, lo, hi)
    return lo if x < lo
    return hi if x > hi
    x

  # Offsets vector (length n, zeros) with joint `joint` shifted by dq radians:
  # the pos muscle's contraction rises and the neg muscle's falls by the same
  # fraction of the joint range.
  -> joint_offset(off, joint, dq)
    return off if !@body.has_joint?(joint)
    g = @body.geometry
    if g != nil
      j = g.joint(joint)
      return off if j == nil
      g.crossing(j).each ->(m) off[m] = off[m] + g.contraction_slope(m, j) * dq
      return off
    p = @body.pos_index(joint)
    n = @body.neg_index(joint)
    m = @body.muscle(p)
    d = dq / (m.qmax - m.qmin)
    off[p] = off[p] + d
    off[n] = off[n] - d
    off

  -> zeros
    (0...@body.size).map -> ~0.0
