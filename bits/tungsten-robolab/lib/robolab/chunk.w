# Chunk: one piece of a compound movement.
#
# A chunk moves the commanded contraction vector from wherever it is when
# the chunk starts to a goal, with every selected muscle moving at once
# along an easing profile. The goal can be given three ways:
#
#   rate(v)   a contraction-rate vector: goal = start + v * duration
#   to(c)     an absolute contraction state
#   pose(p)   a joint-angle posture, converted to contractions
#
# so the average rate over the chunk is the rate vector and the easing
# shapes it (min-jerk by default, the human bell-shaped velocity profile).
# After `duration` the chunk holds its goal until its latch fires; a latch
# that fires early cuts the chunk short. Chunks may also carry:
#
#   drive(a)      feed-forward activation added on top of the reflexes
#                 (ballistic bursts: push-off, a swing's first 100 ms)
#   gain(g)       reflex gain multiplier (loose vs firm limbs)
#   correct(callback)   a real-time correction callback(frame, controller) -> Array of
#                 contraction offsets (length n, or nil), eased through a
#                 critically damped spring so re-aiming stays smooth
#   on_enter(callback)  callback(frame, controller) called once, e.g. to emit a command
#   followed_by(name)   the chunk to go to when this one ends (default: the next
#                 in the movement); branch(callback) chooses it at run time,
#                 callback(frame, controller) -> chunk name or nil
#   via           make the goal a via-point: the command passes through it
#                 with a velocity aimed at the next chunk's goal (Catmull-Rom
#                 tangent) instead of stopping, and the next chunk starts
#                 with that velocity; a run of via chunks is one smooth,
#                 velocity-continuous motion through keyframes (cubic Hermite)
#   stagger(muscles, delay, easing, duration)  per-muscle-group timing inside
#                 one chunk: those muscles start `delay` s late (and may use
#                 their own easing and duration), so a single rate vector
#                 can still carry limbs that move at different times
#   knot(vel, acc)  make the goal a quintic Hermite keyframe: the command
#                 arrives at the goal with contraction velocity `vel` (1/s)
#                 and acceleration `acc` (1/s^2), per-muscle arrays (nil =
#                 zero), and a following knot chunk starts from that state
#                 (see Quintic in easing.w). A run of knot chunks that hand
#                 over at their keyframes is C2 continuous (position,
#                 velocity, acceleration); the first knot chunk after a via
#                 chunk starts with the via's velocity, after any other
#                 chunk at rest. A latch that cuts a knot chunk
#                 short or holds it at its goal keeps the command continuous
#                 and still starts the next segment from the knot's velocity
#                 and acceleration: knots are the segments' boundary
#                 conditions, so the command is a linear function of the knot
#                 vectors. The position basis is the chunk's easing, the exact
#                 quintic with min_jerk (the default), and a knot of zero
#                 vectors reproduces the easing's command exactly. Ignored on
#                 staggered chunks and chunks of zero duration; takes
#                 precedence over `via`.

+ Chunk
  ro :name
  ro :duration
  ro :easing
  ro :latch
  ro :timeout
  ro :knot_vel
  ro :knot_acc
  -> new(@name, @duration)
    @easing = :min_jerk
    @latch = nil
    @timeout = ~0.0
    @goal_kind = :hold
    @goal = nil
    @drive = nil
    @gain = ~1.0
    @correction = nil
    @enter = nil
    @spring_time = ~-1.0
    @successor = nil
    @brancher = nil
    @via = false
    @delays = nil
    @eases = nil
    @durs = nil
    @knot = false
    @knot_vel = nil
    @knot_acc = nil

  -> ease(name)
    @easing = name
    self

  -> rate(r)
    @goal_kind = :rate
    @goal = r
    self

  -> to(c)
    @goal_kind = :to
    @goal = c
    self

  -> pose(p)
    @goal_kind = :pose
    @goal = p
    self

  -> hold_until(latch, timeout = ~0.0)
    @latch = latch
    @timeout = timeout
    self

  -> drive(values)
    @drive = values
    self

  -> gain(g)
    @gain = g
    self

  # spring_time < 0 means "not stated": the track keeps its spring as is
  # (0.08 s when the track creates it).
  -> correct(callback, spring_time = ~-1.0)
    @correction = callback
    @spring_time = spring_time
    self

  -> spring_time_stated?
    @spring_time >= ~0.0

  -> on_enter(callback)
    @enter = callback
    self

  -> followed_by(name)
    @successor = name
    self

  -> via
    @via = true
    self

  -> via?
    @via

  -> knot(vel, acc = nil)
    @knot = true
    @knot_vel = vel
    @knot_acc = acc
    self

  -> knot?
    @knot

  # The statically known successor's name (nil = the movement's own order);
  # run-time branches are not known in advance.
  -> static_successor
    @successor

  -> branch(callback)
    @brancher = callback
    self

  # Name of the chunk to run next, or nil for the movement's own order.
  -> successor(frame, ctl)
    if @brancher != nil
      chosen = @brancher.call(frame, ctl)
      return chosen if chosen != nil
    @successor

  -> stagger(muscles, delay, easing = nil, duration = ~-1.0)
    @delays = {} if @delays == nil
    @eases = {} if @eases == nil
    @durs = {} if @durs == nil
    muscles.each ->(m)
      @delays[m] = delay
      @eases[m] = easing if easing != nil
      @durs[m] = duration if duration >= ~0.0
    self

  -> staggered?
    @delays != nil

  # Progress of muscle m at elapsed time e (staggered chunks).
  -> progress(m, e)
    d = ~0.0
    d = @delays[m] if @delays.key?(m)
    dur = @duration
    dur = @durs[m] if @durs.key?(m)
    ez = @easing
    ez = @eases[m] if @eases.key?(m)
    return ~0.0 if e < d
    return ~1.0 if dur <= ~0.0
    Easing.apply(ez, (e - d) / dur)

  # Time until every muscle has arrived (ends a latch-less chunk).
  -> span
    return @duration if @delays == nil
    out = @duration
    @delays.keys.each ->(m)
      dur = @duration
      dur = @durs[m] if @durs.key?(m)
      out = @delays[m] + dur if @delays[m] + dur > out
    out

  -> drive_values
    @drive

  -> gain_value
    @gain

  -> correction
    @correction

  -> spring_time
    return ~0.08 if @spring_time < ~0.0
    @spring_time

  -> enter_fn
    @enter

  # Goal contraction for a chunk starting from `start`, restricted to the
  # track's muscles (others keep their start value).
  -> goal_from(body, start, mask)
    goal = start.copy
    nm = mask.size
    if @goal_kind == :rate
      d = @goal.over(@duration)
      i = 0
      while i < nm
        m = mask[i]
        goal[m] = start[m] + d[m]
        i += 1
    elsif @goal_kind == :to
      g = @goal
      i = 0
      while i < nm
        m = mask[i]
        goal[m] = g[m]
        i += 1
    elsif @goal_kind == :pose
      posed = @goal.apply(body, start)
      i = 0
      while i < nm
        m = mask[i]
        goal[m] = posed[m]
        i += 1
    goal

# Movement: an ordered list of chunks, optionally looping (a gait cycle).
+ Movement
  ro :name
  ro :chunks
  ro :looping
  -> new(@name)
    @chunks = []
    @looping = false
    @loop_from = 0

  -> add(chunk)
    @chunks.push(chunk)
    chunk

  -> loop_from(index)
    @looping = true
    @loop_from = index
    self

  -> loop_start
    @loop_from

  -> size
    @chunks.size

  -> [](i)
    @chunks[i]
