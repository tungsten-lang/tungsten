# Body plan: the muscles the controller can contract.
#
# Every joint is driven by an antagonist pair: `<joint>_pos` pulls the joint
# angle toward its positive limit, `<joint>_neg` toward the negative limit.
# A muscle's contraction c is the fraction of its length range it has
# shortened through: 0 = fully lengthened, 1 = fully contracted. Across one
# joint the pair is kinematically coupled, c_pos + c_neg = 1, which is what
# makes a contraction vector a complete description of posture AND stiffness:
# commanding a pair whose contractions sum above 1 asks both muscles to be
# shorter than the joint allows, so both pull, and the joint stiffens
# (co-contraction) around the midpoint of the two commands.

+ Muscle
  ro :index
  ro :name
  ro :joint
  ro :sign
  ro :qmin
  ro :qmax
  ro :group
  -> new(@index, @name, @joint, @sign, @qmin, @qmax, @group)

  # Contraction this muscle has when its joint sits at angle q.
  -> contraction_at(q)
    span = @qmax - @qmin
    return (q - @qmin) / span if @sign > 0
    (@qmax - q) / span

  # Joint angle implied by this muscle's contraction c.
  -> angle_at(c)
    span = @qmax - @qmin
    return @qmin + c * span if @sign > 0
    @qmax - c * span

+ Body
  ro :muscles
  -> new
    @muscles = []
    @index = {}
    @pos = {}
    @neg = {}
    @joints = []
    @geometry = nil
    @motors = []

  # The first muscle registered for a joint direction is the joint's pair
  # muscle (bodies list monoarticular pairs before multi-joint muscles).
  -> add(muscle)
    @muscles.push(muscle)
    @index[muscle.name] = muscle.index
    if muscle.sign > 0
      if !@pos.key?(muscle.joint)
        @pos[muscle.joint] = muscle.index
        @joints.push(muscle.joint)
    else
      @neg[muscle.joint] = muscle.index if !@neg.key?(muscle.joint)
    self

  -> size
    @muscles.size

  -> joints
    @joints

  -> has?(name)
    @index.key?(name)

  -> has_joint?(joint)
    return true if @pos.key?(joint)
    @geometry != nil && @geometry.has_joint?(joint)

  # Multi-joint muscle geometry (MyoSuite bodies); nil for pair-per-joint bodies.
  -> geometry
    @geometry

  -> set_geometry(g)
    @geometry = g
    self

  # Non-muscle actuators (e.g. a prosthesis motor), set via Controller#motor.
  -> motors
    @motors

  -> add_motor(name)
    @motors.push(name)
    self

  -> index(name)
    raise "no muscle named [name]" if !@index.key?(name)
    @index[name]

  -> pos_index(joint)
    @pos[joint]

  -> neg_index(joint)
    @neg[joint]

  -> muscle(i)
    @muscles[i]

  # Indices of every muscle whose name starts with one of the prefixes, e.g.
  # mask(["l_", "r_hip"]). A prefix of "" selects everything.
  -> mask(prefixes)
    out = []
    nm = @muscles.size
    np = prefixes.size
    i = 0
    while i < nm
      m = @muscles[i]
      mname = m.name
      hit = false
      j = 0
      while j < np && !hit
        if mname.starts_with?(prefixes[j])
          hit = true
        j += 1
      if hit
        out.push(m.index)
      i += 1
    out

  -> all
    out = []
    n = @muscles.size
    i = 0
    while i < n
      out.push(i)
      i += 1
    out

# Geometry: muscle length as a function of posture, for bodies whose muscles
# wrap across several joints (the MyoSuite models: 80-290 muscles, many of
# them biarticular). The body sends, per muscle and per joint it crosses, the
# muscle's length sampled across that joint's range with every other joint at
# a reference posture. Length is treated as additive over joints:
#
#   L_i(q) = Lref_i + sum_j (f_ij(q_j) - f_ij(qref_j))
#
# which is exact for a muscle crossing one joint and close for wrapped
# multi-joint muscles. A posture (an equilibrium point) therefore maps to one
# contraction per muscle, c_i = (Lmax_i - L_i(q)) / (Lmax_i - Lmin_i), and the
# reflex layer holds it.

+ Geometry
  ro :joint_names
  -> new
    @joint_names = []
    @joint_index = {}
    @qmin = []
    @qmax = []
    @qref = []
    @samples = []
    @crossing = []
    @lmin = []
    @lmax = []
    @lref = []
    @spans = []
    @tables = []
    @pairs = []
    @force = []

  -> add_joint(k, name, lo, hi, qref, samples)
    @joint_names.push(name)
    @joint_index[name] = k
    @qmin.push(lo)
    @qmax.push(hi)
    @qref.push(qref)
    @samples.push(samples)
    @crossing.push([])
    self

  -> ensure_muscle(i)
    while @lmin.size <= i
      @lmin.push(~0.0)
      @lmax.push(~1.0)
      @lref.push(~0.5)
      @spans.push([])
      @tables.push([])
      @pairs.push([])
      @force.push(~0.0)
    self

  -> set_force(i, f)
    ensure_muscle(i)
    @force[i] = f
    self

  -> force(i)
    @force[i]

  # d(length_i)/d(q_j) at the posture q (the muscle's moment arm about joint j,
  # from the slope of its length table; pair corrections are ignored here).
  -> moment_arm(i, j, q)
    slot = 0
    while slot < @spans[i].size
      if @spans[i][slot] == j
        row = @tables[i][slot]
        k = row.size
        h = (@qmax[j] - @qmin[j]) / (k - 1)
        qa = q[j] + h * ~0.5
        qa = @qmax[j] if qa > @qmax[j]
        qb = q[j] - h * ~0.5
        qb = @qmin[j] if qb < @qmin[j]
        return (table_length(i, slot, qa) - table_length(i, slot, qb)) / (qa - qb)
      slot += 1
    ~0.0
  # Second-order correction for coupled joints a and b: muscle i's length
  # residual over an s x s grid spanning both joints' ranges (row-major).
  -> add_pair(i, a, b, s, values)
    ensure_muscle(i)
    @pairs[i].push([a, b, s, values])
    self

  -> pair_residual(entry, qa, qb)
    a = entry[0]
    b = entry[1]
    s = entry[2]
    grid = entry[3]
    ua = (qa - @qmin[a]) / (@qmax[a] - @qmin[a]) * (s - 1)
    ub = (qb - @qmin[b]) / (@qmax[b] - @qmin[b]) * (s - 1)
    ua = ~0.0 if ua < ~0.0
    ub = ~0.0 if ub < ~0.0
    ua = s - 1 if ua > s - 1
    ub = s - 1 if ub > s - 1
    ia = ua.to_i
    ia = s - 2 if ia > s - 2
    ia = 0 if ia < 0
    ib = ub.to_i
    ib = s - 2 if ib > s - 2
    ib = 0 if ib < 0
    ta = ua - ia
    tb = ub - ib
    v00 = grid[ia * s + ib]
    v10 = grid[(ia + 1) * s + ib]
    v01 = grid[ia * s + ib + 1]
    v11 = grid[(ia + 1) * s + ib + 1]
    (~1.0 - ta) * (~1.0 - tb) * v00 + ta * (~1.0 - tb) * v10 + (~1.0 - ta) * tb * v01 + ta * tb * v11

  -> set_range(i, lmin, lmax, lref)
    ensure_muscle(i)
    @lmin[i] = lmin
    @lmax[i] = lmax
    @lref[i] = lref
    self

  -> add_length(i, j, values)
    ensure_muscle(i)
    @spans[i].push(j)
    @tables[i].push(values)
    @crossing[j].push(i)
    self

  -> joint_count
    @joint_names.size

  -> joint(name)
    return nil if !@joint_index.key?(name)
    @joint_index[name]

  -> has_joint?(name)
    @joint_index.key?(name)

  -> qmin(j)
    @qmin[j]

  -> qmax(j)
    @qmax[j]

  -> qref(j)
    @qref[j]

  -> reference_posture
    out = []
    n = @qref.size
    i = 0
    while i < n
      out.push(@qref[i])
      i += 1
    out

  -> crossing(j)
    @crossing[j]

  -> spans(i)
    @spans[i]

  # Piecewise-linear lookup of muscle i's length table for its slot-th joint.
  -> table_length(i, slot, q)
    j = @spans[i][slot]
    row = @tables[i][slot]
    k = row.size
    lo = @qmin[j]
    hi = @qmax[j]
    u = (q - lo) / (hi - lo) * (k - 1)
    return row[0] if u <= ~0.0
    return row[k - 1] if u >= k - 1
    a = u.to_i
    a = k - 2 if a > k - 2
    t = u - a
    row[a] + (row[a + 1] - row[a]) * t

  -> length(i, q)
    total = @lref[i]
    spans_i = @spans[i]
    ns = spans_i.size
    slot = 0
    while slot < ns
      j = spans_i[slot]
      qj = q[j]
      qr = @qref[j]
      if qj != qr
        total += table_length(i, slot, qj) - table_length(i, slot, qr)
      slot += 1
    pairs_i = @pairs[i]
    np = pairs_i.size
    pi = 0
    while pi < np
      e = pairs_i[pi]
      e0 = e[0]
      e1 = e[1]
      if q[e0] != @qref[e0] || q[e1] != @qref[e1]
        total += pair_residual(e, q[e0], q[e1]) - pair_residual(e, @qref[e0], @qref[e1])
      pi += 1
    total

  -> contraction(i, q)
    (@lmax[i] - length(i, q)) / (@lmax[i] - @lmin[i])

  # Muscle i's length range [Lmin, Lmax] and its length at the reference.
  -> range(i)
    [@lmin[i], @lmax[i]]

  -> reference_length(i)
    @lref[i]

  # d(contraction_i)/d(q_j) at the reference posture: how far muscle i
  # shortens (as a fraction of its range) per radian of joint j.
  -> contraction_slope(i, j)
    slot = 0
    while slot < @spans[i].size
      if @spans[i][slot] == j
        h = (@qmax[j] - @qmin[j]) * ~0.02
        qa = @qref[j] + h
        qa = @qmax[j] if qa > @qmax[j]
        qb = @qref[j] - h
        qb = @qmin[j] if qb < @qmin[j]
        up = table_length(i, slot, qa)
        dn = table_length(i, slot, qb)
        return (dn - up) / (qa - qb) / (@lmax[i] - @lmin[i])
      slot += 1
    ~0.0
