# MyoBaodingV4: the palm-tilt baoding skill (MyoBaodingTiltSkill) with a
# finger gait latched on the balls, opt-in by `pg` (0: MyoBaodingTiltSkill).
#
# The round-2 gait states (a0..a3 counter-clockwise, b0..b3 clockwise) ran
# in a fixed timed loop, blind to where the balls were, and the search set
# them all back to the cup: the champion turns the pair by the tilt alone
# and the pair sits in its trough (-0.09 turns on every task, HOLD 0.07).
# A push that moves the pair on when it lies along the palm pushes it back
# when it lies across, so here the gait alternates push and relax and picks
# each push by the pair's measured angle:
#
#   push   a0 / a2 (b0 / b2 clockwise): a goal posture over the 14 joint
#          groups, a0 for a pair lying within 45 deg of the axis `pg_axis`
#          (either way round: the pair is symmetric under swapping the
#          balls), a2 for one lying across it
#   relax  a1 / a3 (b1 / b3): the posture the hand returns to after that
#          push (defaults: the cup), after which the next push is chosen
#          again from the balls
#
# Pacing is the base skill's: a pair running `lead` ahead of its targets
# goes to `hold` and resumes at a relax state; HOLD targets stop once within
# `hold_tol`. The tilt, posture map and synergy stay on as corrections.

+ MyoBaodingV4Skill < MyoBaodingTiltSkill
  -> start(frame, ctl)
    @pg = param("pg", ~0.0, ~0.0, ~1.0) > ~0.5
    @pg_axis = param("pg_axis", ~1.5, ~-3.2, ~3.2)
    @pg_spin_lead = param("pg_spin_lead", ~0.5, ~0.0, ~1.5)
    @pg_chase = param("pg_chase", ~0.0, ~0.0, ~1.5)
    @raw_goal = false
    super(frame, ctl)

  -> begin_gait(f)
    r = super(f)
    return r if !@pg
    @resume = @gait + "1"
    @resume

  -> pace_step(f, name, nxt)
    return super(f, name, nxt) if !@pg
    side = name.slice(0, 1)
    k = name.slice(1, 1).to_i
    if ahead(f) > @th_in
      @resume = side + "1"
      @resume = side + "3" if k >= 2
      return "hold"
    # a push is followed by its relax
    return side + (k + 1).to_s if k == 0 || k == 2
    # after a relax: the push for the pair's sector
    return side + "0" if Math.cos(~2.0 * (phi(f) - @pg_axis)) > ~0.0
    side + "2"

  # The targets' direction is read from their own motion (the base skill's
  # `before`), never from the led target below.
  -> before(f, ctl)
    @raw_goal = true
    r = super(f, ctl)
    @raw_goal = false
    r

  # Spin benchmark (`spin` = +-1) with the gait on: the targets the tilt and
  # synergy steer toward run `pg_spin_lead` ahead of the pair in the spin
  # direction, so they push the way the gait turns instead of toward the
  # env's own (random-direction) targets.
  #
  # `pg_chase` > 0 (the task itself): the same led target. Turning targets
  # circle faster than the balls can follow, so the tilt swirls a fixed
  # pg_chase ahead of the pair in the targets' direction (the spin search's
  # turning); a HOLD target is approached the shorter way and never passed:
  # phi + clamp(phi* - phi, +-pg_chase).
  -> phi_goal(f)
    return super(f) if !@pg || @raw_goal
    p = phi(f)
    return wrap(p + @spin * @pg_spin_lead) if @spin != 0
    return super(f) if @pg_chase <= ~0.0
    return wrap(p + @dir * @pg_chase) if @dir != 0
    wrap(p + clamp(wrap(super(f) - p), ~0.0 - @pg_chase, @pg_chase))
