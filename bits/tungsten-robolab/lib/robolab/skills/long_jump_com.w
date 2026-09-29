# LongJumpComSkill: LongJumpSkill (lib/robolab/skills/long_jump.w, unchanged)
# with two opt-in latches on the centre-of-mass state, after the standing-jump
# finding in search_jump.w (fb_takeoff / fb_touch):
#
#   com_to 1   the take-off chunk also ends when the COM has risen above to_z
#              while still moving up, whichever comes first, so a toe that
#              lingers or chatters on the board does not delay the flight
#              chunks (hang, tuck, reach)
#   com_td 1   the landing latch (sand contact, or the runway after 0.15 s)
#              also needs the COM below td_z and falling: a foot scuffing the
#              sand early no longer starts the landing posture in mid-air
#
# Both are params-file switches, off by default; each declares its tunable
# only when on (after every tunable of the parent), so every params file
# without them replays as LongJumpSkill. add_flight below is the parent's,
# verbatim except for the com_td gate on `landed`.

+ LongJumpComSkill < LongJumpSkill
  -> read_params
    super
    @com_to = switch_on("com_to")
    @com_td = switch_on("com_td")
    @to_z = param("to_z", ~1.1, ~0.9, ~1.25) if @com_to
    @td_z = param("td_z", ~0.8, ~0.5, ~1.05) if @com_td
    self

  -> switch_on(name)
    return false if !@params.key?(name)
    @params[name] > ~0.5

  # The take-off chunk's latch (foot_lifted("l_")), or the COM launched.
  -> foot_lifted(side)
    base = super(side)
    return base if !@com_to || side != "l_"
    launched = Latch.test("launched", ->(f, e, c) f.at("com_pos", 2) > @to_z && f.at("com_vel", 2) > ~0.0)
    Latch.any([base, launched])

  # Flight, landing and recovery chunks shared by both programs.
  -> add_flight(mv)
    st = @stiff
    hang = sym_pose(param("hg_hip", ~0.1, ~-0.5, ~1.2), param("hg_knee", ~1.0, ~0.0, ~2.4),
                    param("hg_ank", ~0.2, ~-0.5, ~0.9), param("hg_spine", ~-0.15, ~-0.5, ~0.6),
                    param("hg_arm", ~2.8, ~0.0, ~3.1), ~0.3, st)
    tuck = sym_pose(param("tk_hip", ~1.5, ~0.3, ~2.2), param("tk_knee", ~1.9, ~0.5, ~2.5),
                    param("tk_ank", ~0.2, ~-0.5, ~0.9), param("tk_spine", ~0.4, ~-0.3, ~1.2),
                    param("tk_arm", ~1.5, ~-1.0, ~3.1), ~0.3, st)
    reach = sym_pose(param("rc_hip", ~2.0, ~0.8, ~2.2), param("rc_knee", ~0.15, ~-0.02, ~1.0),
                     param("rc_ank", ~-0.1, ~-0.6, ~0.6), param("rc_spine", ~0.8, ~-0.3, ~1.2),
                     param("rc_arm", ~0.6, ~-1.0, ~3.1), ~0.2, st)
    absorb = sym_pose(param("ab_hip", ~1.9, ~0.8, ~2.2), param("ab_knee", ~1.6, ~0.3, ~2.5),
                      param("ab_ank", ~0.0, ~-0.6, ~0.9), param("ab_spine", ~1.0, ~-0.3, ~1.2),
                      param("ab_arm", ~2.0, ~-1.0, ~3.1), ~0.4, st)
    # recovery: settle from the landing crouch (forward over the feet, as
    # jumpers leave the pit through the front) into a sit or a squat
    sit = sym_pose(param("rv_hip", ~1.6, ~0.2, ~2.2), param("rv_knee", ~1.2, ~0.2, ~2.5),
                   param("rv_ank", ~0.0, ~-0.6, ~0.9), param("rv_spine", ~0.6, ~-0.2, ~1.2),
                   param("rv_arm", ~1.0, ~-1.0, ~3.1), ~0.6, st)
    rv_gain = param("rv_gain", ~0.6, ~0.1, ~2.0)
    rc_tau = param("rc_tau", ~0.3, ~0.05, ~1.0)
    hg_min = param("hg_min", ~0.08, ~0.0, ~0.2)
    @air_pitch = param("air_pitch", ~0.2, ~-0.3, ~0.8)
    @k_air = param("k_air", ~0.0, ~0.0, ~3.0)
    @kd_air = param("kd_air", ~0.0, ~0.0, ~0.6)
    @k_air_arm = param("k_air_arm", ~0.0, ~0.0, ~3.0)
    @rc_comp = param("rc_comp", ~0.0, ~0.0, ~1.0)
    @land_z = param("land_z", ~0.55, ~0.3, ~0.9)
    @ab_k = param("ab_k", ~1.0, ~0.0, ~3.0)
    @ab_k2 = param("ab_k2", ~0.0, ~0.0, ~2.0)
    @ab_kd2 = param("ab_kd2", ~0.0, ~0.0, ~0.3)
    # sand contact (any body part), or the runway after a while (a jump that
    # falls short of the pit); a lingering take-off contact must not count
    sand = Latch.above("pit", 1, ~0.5)
    landed = Latch.any([sand, Latch.above("pit", 2, ~0.5).after_min(~0.15)])
    if @com_td
      low = Latch.test("low", ->(f, e, c) f.at("com_pos", 2) < @td_z && f.at("com_vel", 2) < ~0.0)
      landed = Latch.all([landed, low])
    # the legs swing forward when the sand is rc_tau seconds away (ballistic
    # time-to-contact of the COM down to its landing height)
    soon = Latch.test("sand_in_tau", ->(f, e, c) time_to_land(f) < rc_tau)
    tk_tau = param("tk_tau", ~0.45, ~0.05, ~1.2)
    gather = Latch.test("sand_in_tk_tau", ->(f, e, c) time_to_land(f) < tk_tau)
    air = ->(f, c) enter(f, "l_", "r_", :air)
    mv.add(Chunk.new("hang", param("hg_dur", ~0.2, ~0.05, ~0.5)).pose(hang)
      .hold_until(Latch.any([gather, landed]).after_min(hg_min), ~0.9)
      .correct(->(f, c) air_correction(f, :hang), @spring)
      .on_enter(air))
    # tuck: both legs gather forward with the knees bent (a short lever
    # swings fast), then the reach extends them for the landing
    mv.add(Chunk.new("tuck", param("tk_dur", ~0.15, ~0.05, ~0.4)).pose(tuck)
      .hold_until(Latch.any([soon, landed]), ~0.9)
      .correct(->(f, c) air_correction(f, :reach), @spring)
      .on_enter(air))
    mv.add(Chunk.new("reach", param("rc_dur", ~0.25, ~0.08, ~0.6)).pose(reach).hold_until(landed, ~1.5)
      .correct(->(f, c) air_correction(f, :reach), @spring)
      .on_enter(air))
    # landing co-activation: a flexor burst holds the crouch against the
    # stretched extensors' passive force (which would otherwise spring the
    # body back out of a deep landing)
    ab_d = param("ab_drive", ~0.0, ~0.0, ~1.0)
    mv.add(Chunk.new("absorb", param("ab_dur", ~0.3, ~0.1, ~0.8)).pose(absorb).gain(param("ab_gain", ~0.5, ~0.1, ~2.0))
      .drive(sym_drive([["knee_pos", ab_d], ["hip_flex_pos", ab_d * ~0.5]]))
      .correct(->(f, c) landing_correction(f))
      .hold_until(Latch.after(~0.7)).on_enter(air))
    mv.add(Chunk.new("sit", param("rv_dur", ~0.8, ~0.2, ~2.0)).pose(sit).gain(rv_gain).hold_until(Latch.after(~60.0))
      .correct(->(f, c) landing_correction(f)).on_enter(air))
    mv
