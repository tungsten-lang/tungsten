# MyoRelocateV6: round-6 options for the relocate skill (MyoRelocateV5Skill),
# for the phase-2 evaluation environment (myoChallengeRelocateP2eval-v0:
# objects over x -0.4..-0.05, y -0.4..-0.1, up to 7 cm across, 50-300 g).
# Each option is opt-in by params; with every switch off it is
# MyoRelocateV5Skill, episode for episode.
#
# What 1200 dev episodes of the round-5 champion on the eval env showed
# (playground/tasks/myo_relocate_v6.py has the diagnostics):
#
# - Where the object starts decides most of it. The round-5 skill was tuned
#   on P2's range; on the eval env 29% of objects start beyond y = -0.3 (far,
#   8% official success), 26% left of x = -0.3 (10%) and 15% close to the
#   body, y > -0.16 (24%), against 34% in the P2-like core. Left and near
#   reaches run into the reach timeout (the palm arrives in 0.58 s instead of
#   0.3 s); beyond y ~ -0.35 the palm-down pinch is out of reach.
# - The physics steps a receptacle the observation does not show (MyoSuite
#   2.12.2 keeps two MjData; see the task module): an invisible 20 cm box at
#   a random pose over the workspace. The arm starts inside it in a third of
#   the eval episodes and runs into it in another fifth.
# - Mass and size barely change the grasp; heavy lifted objects fall out
#   more (0.2-0.3 kg: 32% of lifts placed, against 55% at 0.1-0.2 kg), and
#   they leave the hand suddenly rather than by slow slip.
#
#   x_left6 / y_near6   position-indexed settings: objects starting left of
#            x_left6 (and not beyond y_far5) take the `_l` twin of every
#            param in REG6 (arm servo, pronation, joint loop, wrist, reach
#            and grasp targets and timing, transport); objects starting
#            nearer than y_near6 (and in neither the far nor the left region)
#            the `_n` twin. Twins default to the near value and are declared
#            whenever their region is on (x_left6 > -1, y_near6 < 0), so a
#            search sees them; far objects keep round 5's `_f` twins.
#   grip6    1: reactive grip. During lift, carry and lower, once the held
#            object sinks in the hand (palm-object gap grown by slip_th) or
#            falls away from it (relative downward speed over v_slip), the
#            flexors (FDS, FDP, FPL, OP) get sq_boost more squeeze drive for
#            the rest of the transport; w_load adds squeeze in proportion to
#            the load the lift feels (the palm's vertical lag behind its
#            target over the first t_weigh s of the lift, a mass proxy).
#   stall6   1: stalled-reach escape. When the reach, st_late s after it
#            started, has not brought the pinch st_eps closer to its goal
#            for st_win s while still farther than r_reach, the hand rises
#            to z_esc over t_esc s and then reaches again, travelling at
#            z_trav (at least z_above) before the descend (once per
#            episode): an arm caught on an obstacle it cannot see goes over
#            it. esc0 1 (diagnostic): escape at the first tick, whatever
#            happens.
#   zrel6    1: grasp heights follow the object. An object resting above
#            z_rest6 (on the invisible receptacle's base or against its
#            wall, 6% of eval episodes, 4% success) moves the reach, descend
#            and settle goals up by its height over z_rest6 (the grasp
#            heights are absolute, for objects on the table).

+ MyoRelocateV6Skill < MyoRelocateV5Skill
  -> start(frame, ctl)
    # regions first: every later param reads them
    @reg6 = ""
    @left6_on = false
    @near6_on = false
    xl = param("x_left6", ~-1.0, ~-1.0, ~0.0)
    yn = param("y_near6", ~0.0, ~-0.3, ~0.0)
    @left6_on = xl > ~-1.0
    @near6_on = yn < ~0.0
    if frame.has?("env_obj_pos")
      ox = frame.at("env_obj_pos", 0)
      oy = frame.at("env_obj_pos", 1)
      yf = param("y_far5", ~-1.0, ~-1.0, ~-0.1)
      far = yf > ~-1.0 && oy < yf
      @reg6 = "_l" if !far && @left6_on && ox < xl
      @reg6 = "_n" if !far && @reg6 == "" && @near6_on && oy > yn
    @grip6 = param("grip6", ~0.0, ~0.0, ~1.0) > ~0.5
    @stall6 = param("stall6", ~0.0, ~0.0, ~1.0) > ~0.5
    @boost = false
    @gap0 = nil
    @pz_prev = nil
    @load = ~0.0
    @load_n = ~0.0
    @lift_t0 = ~-1.0
    if @grip6
      @slip_th = param("slip_th", ~0.008, ~0.002, ~0.03)
      @v_slip = param("v_slip", ~0.3, ~0.05, ~2.0)
      @sq_boost = param("sq_boost", ~0.2, ~0.0, ~0.6)
      @w_load = param("w_load", ~0.0, ~0.0, ~20.0)
      @t_weigh = param("t_weigh", ~0.05, ~0.02, ~0.15)
    @esc = false
    @esc_done = false
    @esc_t0 = ~0.0
    @best_err = ~9.0
    @best_t = ~0.0
    @zrel6 = param("zrel6", ~0.0, ~0.0, ~1.0) > ~0.5
    @z_rest6 = ~0.94
    @z_rest6 = param("z_rest6", ~0.94, ~0.9, ~1.05) if @zrel6
    @reach_t0 = ~-1.0
    @esc0 = false
    if @stall6
      @st_eps = param("st_eps", ~0.01, ~0.002, ~0.04)
      @st_win = param("st_win", ~0.1, ~0.03, ~0.3)
      @st_late = param("st_late", ~0.35, ~0.0, ~0.6)
      @z_esc = param("z_esc", ~1.28, ~1.1, ~1.4)
      @t_esc = param("t_esc", ~0.15, ~0.05, ~0.4)
      @z_trav = param("z_trav", ~1.0, ~0.94, ~1.35)
      @esc0 = param("esc0", ~0.0, ~0.0, ~1.0) > ~0.5
    super(frame, ctl)
    @sq_m = body.mask(["FDS", "FDP", "FPL", "OP"])

  # Region twins: a REG6 param named p takes p_l (left) or p_n (near) for
  # an object in that region. Both twins are declared while their region is
  # on, so the describe handshake lists them in every episode.
  -> param(name, default, lo, hi)
    v = super(name, default, lo, hi)
    return v if (!@left6_on && !@near6_on) || !reg6_name?(name)
    vl = v
    vn = v
    vl = super(name + "_l", v, lo, hi) if @left6_on
    vn = super(name + "_n", v, lo, hi) if @near6_on
    return vl if @reg6 == "_l"
    return vn if @reg6 == "_n"
    v

  -> reg6_name?(name)
    far5_name?(name) || ["z_above", "z_grasp", "ox", "oy", "k_touch", "r_reach", "r_xy", "touch_th", "servo_p", "servo_i", "rr_kp", "rr_ki", "lift_to", "t_lift", "to_lift", "t_carry", "to_carry", "z_lift", "z_clear", "z_carry", "cx", "cy", "rr_kp_c", "rr_ki_c", "servo_i_c", "lf_kd", "squeeze_c"].include?(name)

  # ---- per tick ----------------------------------------------------------------

  -> before(f, ctl)
    super(f, ctl)
    grip_watch(f) if @grip6
    nil

  -> after(f, ctl)
    super(f, ctl)
    stall_watch(f, ctl) if @stall6
    nil

  # Reactive grip: latch the boost on a sink or a fall-away of the held
  # object; meanwhile average the palm's vertical lag over the first t_weigh
  # s of the lift (the load).
  -> grip_watch(f)
    ph = @phase
    pz = f.at("env_palm_pos", 2)
    vpz = ~0.0
    vpz = (pz - @pz_prev) / @dt if @pz_prev != nil
    @pz_prev = pz
    return nil if ph != "lift" && ph != "carry" && ph != "lower"
    @lift_t0 = f.t if @lift_t0 < ~0.0
    if f.t - @lift_t0 < @t_weigh
      @load = @load + (@xs[2] - pz)
      @load_n = @load_n + ~1.0
    return nil if touch_total(f) < @touch_th
    gap = pz - f.at("env_obj_pos", 2)
    @gap0 = gap if @gap0 == nil
    fall = vpz - f.at("obj_vel", 2)
    @boost = true if gap - @gap0 > @slip_th || fall > @v_slip
    nil

  # Stalled reach: the best distance to the goal so far and when it last
  # improved by st_eps; a stall restarts the reach chunk (and its timeout)
  # as the escape, which eases the hand up to z_esc; after t_esc the reach
  # restarts from there (once per episode).
  -> stall_watch(f, ctl)
    if @esc
      return nil if f.t - @esc_t0 < @t_esc
      @esc = false
      @esc_done = true
      ctl.track("arm").jump(ctl, f, "reach")
      return nil
    return nil if @phase != "reach" || @esc_done
    @reach_t0 = f.t if @reach_t0 < ~0.0
    err = palm_error(f)
    if err < @best_err - @st_eps
      @best_err = err
      @best_t = f.t
    stalled = f.t - @best_t >= @st_win && err >= @r_reach && f.t - @reach_t0 >= @st_late
    return nil if !stalled && !@esc0
    ctl.track("arm").jump(ctl, f, "reach")
    @esc = true
    @esc_t0 = f.t
    @tp = @t_esc
    nil

  # No arrival while escaping.
  -> palm_error(f)
    return ~1.0 if @esc
    super(f)

  # The squeeze boost (grip6) on top of the chunk's own drive.
  -> servo_step(f, ctl)
    off = super(f, ctl)
    return off if !@grip6
    ph = @phase
    return off if ph != "lift" && ph != "carry" && ph != "lower"
    extra = ~0.0
    extra = @sq_boost if @boost
    extra = extra + @w_load * @load / @load_n if @load_n > ~0.0 && @w_load > ~0.0
    return off if extra <= ~0.0
    e = clamp(extra, ~0.0, ~0.8)
    @sq_m.each ->(m) ctl.add_drive(m, e)
    off

  # ---- goals -------------------------------------------------------------------

  # While escaping, the pinch heads straight up to z_esc; the reach after
  # an escape travels at z_trav (or z_above if higher).
  -> phase_goal(f)
    if @esc
      return [@x0[0], @x0[1], @z_esc]
    g = super(f)
    g[2] = @z_trav if @esc_done && @phase == "reach" && @z_trav > g[2]
    if @zrel6 && (@phase == "reach" || @phase == "descend" || @phase == "settle")
      dz = f.at("env_obj_pos", 2) - @z_rest6
      g[2] = g[2] + dz if dz > ~0.0
    g
