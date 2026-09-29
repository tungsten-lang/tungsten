# RunGear: the RunKnot / RunRI sprint with more GEARS.
#
# One parameter set has to both accelerate a standing body and cruise at top speed, and the two want
# different strides: searched from a standing start, the cruising gait is held back by what the
# start can survive (the same gait tuned from flying starts at top speed runs 0.5 m/s faster and
# falls when started from rest). With `gears N` (N >= 2; a params-file switch; without it this is
# RunKnotSkill exactly) every tunable X has gear twins g2_X ... gN_X (default: the previous gear's
# value), and the first time the filtered speed reaches `g<k>_v_on` the stride is rebuilt from
# gear k's values at the next flight: RunSkill's chunks, poses, corrections, reflex gains and
# reciprocal inhibition (g<k>_ri) all come from gear k, the movement swaps under the running track
# (Track#set_movement) and the stride carries on at the landing. Gear 1 is the start and the
# acceleration; each later gear is searched at the speed range it takes over (from flying starts
# recorded on the gear before it). The switch is one way. `knots` must be off (the knot chunks
# are gear 1's).

+ RunGearSkill < RunKnotSkill
  -> start(frame, ctl)
    @gear = 1
    super(frame, ctl)
    return self if @gears < 2
    tr = ctl.track("body")
    attach_gear_branches(tr.movement, ctl)
    # gear0 K (practice: a flying start, fly_entry 2) starts in gear K's stride instead of gear 1's
    g0 = ~1.0
    g0 = @params["gear0"] if @params.key?("gear0")
    if g0 >= ~1.5 && g0.to_i <= @gears
      switch_gear(frame, ctl, g0.to_i)
      tr.jump(ctl, frame, "r_land") if @fly_entry2 && frame.com_vx > ~1.0
    self

  -> attach_gear_branches(mv, ctl)
    mv.chunks.each ->(ch)
      if ch.name == "l_flight"
        ch.branch(->(f, c) gear_next(f, c, ctl, "r_land"))
      elsif ch.name == "r_flight"
        ch.branch(->(f, c) gear_next(f, c, ctl, "l_land"))
    self

  # The value gear `gear` uses for `name`: the nearest gear at or below it that names the
  # twin g<k>_name in the params file, else gear 1's value v.
  -> gear_value(name, v, gear)
    k = gear
    while k >= 2
      key = "g" + k.to_s + "_" + name
      return @params[key] if @params.key?(key)
      k -= 1
    v

  -> gear_name?(name)
    return false if name.size < 3
    return false if name.slice(0, 1) != "g"
    d = name.slice(1, 1)
    return false if d < "2" || d > "9"
    name.slice(2, 1) == "_"

  # Every tunable gets a twin per gear; in gear k the twin's value (else the previous gear's) is used.
  -> param(name, default, lo, hi)
    v = super(name, default, lo, hi)
    n = ~0.0
    n = @params["gears"] if @params.key?("gears")
    return v if n < ~1.5 || gear_name?(name)
    return gear_value(name, v, @gear) if @gear >= 2
    k = 2
    while k <= n.to_i
      key = "g" + k.to_s + "_" + name
      dv = gear_value(name, v, k - 1)
      @declared.push("TUNABLE [key] [dv] [lo] [hi]")
      k += 1
    v

  -> read_params
    super
    n = ~0.0
    n = @params["gears"] if @params.key?("gears")
    @gears = n.to_i
    @gears = 1 if @gears < 2
    self

  # A flight chunk's branch: at the first flight after the speed reaches the next gear's g<k>_v_on,
  # change gear and land in the new movement; otherwise the movement's own order (nil).
  -> gear_next(f, c, ctl, land)
    return nil if @gear >= @gears
    von = ~99.0
    key = "g" + (@gear + 1).to_s + "_v_on"
    von = @params[key] if @params.key?(key)
    return nil if @v_f < von
    switch_gear(f, ctl, @gear + 1)
    land

  -> switch_gear(f, ctl, k)
    @gear = k
    read_params
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    biart = body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(biart, @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    ri = ~0.0
    ri = @params["ri"] if @params.key?("ri")
    ri = gear_value("ri", ri, k)
    setup_reciprocal(ctl, ri) if ri > ~0.0
    @drives = []
    mv = Movement.new("run")
    mv.add(stand_chunk)
    mv.add(lean_chunk)
    mv.add(push_chunk("l_", "r_", true))
    mv.add(flight_chunk("l_", "r_", nil))
    mv.add(land_chunk("r_", "l_"))
    mv.add(push_chunk("r_", "l_", false))
    mv.add(flight_chunk("r_", "l_", nil))
    mv.add(land_chunk("l_", "r_"))
    mv.add(push_chunk("l_", "r_", false))
    mv.loop_from(3)
    attach_gear_branches(mv, ctl) if k < @gears
    ctl.track("body").set_movement(mv)
    # the speed plan is ramped: the cruising gait runs at full drive
    @v0 = @v_top
    @t_go = f.t
    @v_des = @v_top
    self
