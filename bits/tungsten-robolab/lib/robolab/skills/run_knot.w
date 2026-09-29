# RunKnot: the RunRI sprint with its stance distilled from the ideal-control
# analysis (playground/sprint_limits.py) into quintic contraction knots.
#
# sprint_limits.py finds, at each speed, the stance an ideal controller would
# run: open-loop excitations of the stance leg's 11 muscles with the pelvis
# pitch and the other leg driven for free. Replayed and recorded
# (scratchpad/sprint_knot/ideal_trace.py; P95 at 7.5 m/s), it lands with the
# thigh 0.46 rad ahead and the knee nearly straight (0.29 rad) while the hip
# retracts at ~12 rad/s, yields the knee only to ~0.6 rad, and leaves with the
# thigh 0.72 rad behind, the knee straight and the ankle plantarflexing at ~28
# rad/s; vasti near full from touchdown, soleus and gastrocnemius from ~40 ms,
# gluteus and hamstrings early. The run_v2-line champions land 0.2 rad
# further ahead with the knee at 0.56, collapse it to ~1.0 and leave at -0.2.
#
# This skill does NOT replay those excitations. With `knots 1` (a params-file
# switch; without it this is RunRISkill exactly) it distils them into
# RunSkill's own representation, every value a tunable seeded from the ideal:
#
#   landing   the flight chunk's goal for the landing leg is the touchdown
#             keyframe (kn_td_thigh world thigh angle, kn_td_knee, kn_td_ankle)
#             and the chunk is a quintic knot (Chunk#knot) arriving there with
#             the joints' touchdown velocities (kn_td_w*: the hip retracting)
#   stance    the land and push chunks become two knot chunks: touchdown ->
#             mid-stance keyframe (kn_ms_*, reached kn_t_ms after touchdown)
#             -> lift-off keyframe (kn_lo_*: thigh behind, knee straight,
#             ankle plantarflexed, with lift-off velocities kn_lo_w*), the
#             second latched on the foot's release. Joint velocities become
#             contraction velocities through the body's geometry, so the
#             command is a C1 path through the ideal's (c, v) at each knot.
#   drive     phase-gated FULL drive (kn_level, default 1.0) on the stance
#             prime movers, each in its own window after the sensed
#             touchdown: gluteus [kd_glut_on, kd_glut_off], hamstrings,
#             vasti, soleus, gastrocnemius (the last three to lift-off), with
#             the hop-height term on vasti / soleus / gastrocnemius; RunRI's
#             reciprocal inhibition (`ri`) acts on top. RunSkill's own
#             push-chunk drives are not used in the stride (they still drive
#             the standing start).
#
# The reflexes, the hop-height loop, the stance-hip trunk servo (which
# replaces the stance hip's command, as in RunSkill), the Raibert placement
# and swing retraction all stay on top.
#
# Speed scheduling: the knot chunks (X_kflight -> Y_kland -> Y_kpush ->
# Y_kflight ...) are extra chunks beside RunSkill's own, entered by a branch
# from any flight chunk once the filtered speed reaches kn_v_on (a sprint
# stance is wrong at a jog); below it RunSkill's land / push / flight chunks
# run as before, so the standing start is RunSkill's. A body that starts
# moving (com_vx > 1 m/s: tasks/sprint_touch.py's flying starts, just before
# a right touchdown) enters the loop at the left flight with its speed plan
# fully ramped (v_des = v_top), as in steady running.

+ RunKnotSkill < RunRISkill
  -> start(frame, ctl)
    super(frame, ctl)
    return self if !@knots && !@fly_entry
    tr = ctl.track("body")
    mv = tr.movement
    if @knots
      # RunSkill's loop wraps at the end of the movement: its last chunk now
      # names the loop start, since the knot chunks are appended after it
      mv[mv.size - 1].followed_by(mv[mv.loop_start].name)
      ["l_", "r_"].each ->(st)
        sw = "r_"
        sw = "l_" if st == "r_"
        mv.add(kland_chunk(st, sw))
        mv.add(kpush_chunk(st, sw))
        mv.add(kflight_chunk(st, sw))
      mv.chunks.each ->(ch)
        if ch.name == "l_flight" || ch.name == "l_kflight"
          ch.branch(->(f, c) knot_next("r_"))
        elsif ch.name == "r_flight" || ch.name == "r_kflight"
          ch.branch(->(f, c) knot_next("l_"))
    if frame.com_vx > ~1.0
      # (the speed plan fully ramped, as a steadily running controller's is:
      # the acceleration lean and the push drives follow v_des / v_top)
      # (RunSkill ramps v_des only while t_go >= 0: the ramp starts at v_top)
      @v_f = frame.com_vx
      @v0 = @v_top
      @t_go = frame.t
      @v_des = @v_top
      nm = "l_flight"
      knot_td = @knots && frame.com_vx >= @kn_v_on
      nm = "l_kflight" if knot_td
      # fly_entry 2: enter the right stance chunk itself (the snapshot is a few ms before the right
      # touchdown, and the flight chunk holds >= 30 ms before it hands over to the landing)
      nm = "r_land" if @fly_entry2 && !knot_td
      nm = "r_kland" if @fly_entry2 && knot_td
      # the command starts on the flight's pose (as a running controller's
      # would be), not on the sensed posture: a command equal to the sensed
      # contraction leaves the stretch reflexes no tone at the landing
      p = flight_pose("l_", "r_")
      knot_leg(p, "r_", @kn_td_thigh, @kn_td_knee, @kn_td_ankle) if knot_td
      c = p.apply(body, ctl.command)
      cmd = ctl.command
      i = 0
      while i < body.size
        cmd[i] = c[i]
        i += 1
      tr.jump(ctl, frame, nm)
    self

  # The stance after a flight: the knot stance once running at kn_v_on, else
  # RunSkill's (nil = the movement's own order: X_flight is followed by
  # Y_land; a knot flight names Y_land explicitly).
  -> knot_next(land)
    return land + "kland" if @v_f >= @kn_v_on
    land + "land"

  -> read_params
    super
    # fly_entry 1 (a params-file switch): a body that starts already running (a
    # flying start: tasks/sprint_touch.py fly_touch 2) enters RunSkill's stride
    # loop at the left flight with the speed plan ramped, as `knots 1` does;
    # without knots the stride is RunRISkill's exactly
    @fly_entry = @params.key?("fly_entry") && @params["fly_entry"] > ~0.5
    @fly_entry2 = @params.key?("fly_entry") && @params["fly_entry"] > ~1.5
    @knots = @params.key?("knots") && @params["knots"] > ~0.5
    @knot_stance = false
    return self if !@knots
    @kn_v_on = param("kn_v_on", ~3.0, ~1.0, ~9.0)
    # touchdown keyframe of the landing leg (rad; thigh = world angle, + ahead)
    @kn_td_thigh = param("kn_td_thigh", ~0.46, ~0.0, ~0.9)
    @kn_td_knee = param("kn_td_knee", ~0.29, ~0.0, ~0.9)
    @kn_td_ankle = param("kn_td_ankle", ~-0.23, ~-0.6, ~0.5)
    @kn_td_whip = param("kn_td_whip", ~-8.0, ~-16.0, ~4.0)
    @kn_td_wknee = param("kn_td_wknee", ~0.0, ~-15.0, ~15.0)
    @kn_td_wankle = param("kn_td_wankle", ~-3.0, ~-20.0, ~20.0)
    # mid-stance keyframe and its time after touchdown
    @kn_t_ms = param("kn_t_ms", ~0.055, ~0.02, ~0.12)
    @kn_ms_thigh = param("kn_ms_thigh", ~0.16, ~-0.4, ~0.7)
    @kn_ms_knee = param("kn_ms_knee", ~0.59, ~0.1, ~1.2)
    @kn_ms_ankle = param("kn_ms_ankle", ~-0.45, ~-0.6, ~0.5)
    @kn_ms_whip = param("kn_ms_whip", ~-5.0, ~-16.0, ~4.0)
    @kn_ms_wknee = param("kn_ms_wknee", ~0.0, ~-20.0, ~20.0)
    @kn_ms_wankle = param("kn_ms_wankle", ~-10.0, ~-30.0, ~30.0)
    # lift-off keyframe, reached kn_t_lo after mid-stance
    @kn_t_lo = param("kn_t_lo", ~0.065, ~0.02, ~0.15)
    @kn_lo_thigh = param("kn_lo_thigh", ~-0.72, ~-1.0, ~0.2)
    @kn_lo_knee = param("kn_lo_knee", ~0.0, ~-0.02, ~0.8)
    @kn_lo_ankle = param("kn_lo_ankle", ~0.4, ~-0.3, ~0.9)
    @kn_lo_whip = param("kn_lo_whip", ~-14.0, ~-20.0, ~4.0)
    @kn_lo_wknee = param("kn_lo_wknee", ~-19.0, ~-30.0, ~10.0)
    @kn_lo_wankle = param("kn_lo_wankle", ~28.0, ~-10.0, ~35.0)
    # phase-gated drive windows (s after touchdown; an off of kd_open means
    # "until lift-off")
    @kn_level = param("kn_level", ~1.0, ~0.0, ~1.0)
    @kd_glut_on = param("kd_glut_on", ~0.0, ~0.0, ~0.1)
    @kd_glut_off = param("kd_glut_off", ~0.11, ~0.0, ~0.25)
    @kd_ham_on = param("kd_ham_on", ~0.0, ~0.0, ~0.1)
    @kd_ham_off = param("kd_ham_off", ~0.075, ~0.0, ~0.25)
    @kd_vas_on = param("kd_vas_on", ~0.005, ~0.0, ~0.1)
    @kd_sol_on = param("kd_sol_on", ~0.035, ~0.0, ~0.12)
    @kd_gas_on = param("kd_gas_on", ~0.045, ~0.0, ~0.12)
    @t_td = ~-1.0
    self

  # ---- keyframes ---------------------------------------------------------------

  # The stance / landing leg's keyframe posture on `p` (hip commanded as the
  # world thigh angle plus the nominal pelvis pitch, as RunSkill's poses are).
  -> knot_leg(p, side, thigh, knee, ankle)
    p.set(side + "hip_flex", thigh + @phi_nom, @stiff_st)
    p.set(side + "knee", knee, @stiff_st)
    p.set(side + "ankle", ankle, @stiff_st)
    p

  # Contraction velocities of `side`'s leg muscles for joint velocities (rad/s).
  -> knot_vel(side, whip, wknee, wankle)
    v = zeros
    joint_offset(v, side + "hip_flex", whip)
    joint_offset(v, side + "knee", wknee)
    joint_offset(v, side + "ankle", wankle)
    v

  # ---- chunks ----------------------------------------------------------------------

  # Flight after a knot stance: RunSkill's flight pose with the landing leg on
  # the touchdown keyframe, arriving with its touchdown velocities.
  # (RunSkill's flight_chunk with the landing keyframe and its knot.)
  -> kflight_chunk(st, sw)
    p = flight_pose(st, sw)
    knot_leg(p, sw, @kn_td_thigh, @kn_td_knee, @kn_td_ankle)
    touch = Latch.contact(sw + "foot")
    ch = Chunk.new(st + "kflight", @t_flight).pose(p)
    ch.knot(knot_vel(sw, @kn_td_whip, @kn_td_wknee, @kn_td_wankle), nil)
    ch.hold_until(touch.after_min(~0.03), ~0.45)
    ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, sw + "knee_neg", @drv_pre,
                        st + "rf", @drv_rf, sw + "ham", @drv_hamb]))
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :flight), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :flight))
    ch

  # Touchdown -> mid-stance: a timed knot chunk (no latch; a foot that leaves
  # early is caught by the lift-off chunk's release latch at once).
  -> kland_chunk(st, sw)
    p = Pose.new
    knot_leg(p, st, @kn_ms_thigh, @kn_ms_knee, @kn_ms_ankle)
    p.set(st + "toe", @toe_land, @stiff_st)
    leg(p, sw, @psi_mid + @knee_lift + @phi_nom, tuck(@k_mid), ~-0.1, @stiff_sw)
    upper(p, st, sw)
    ch = Chunk.new(st + "kland", @kn_t_ms).pose(p)
    ch.knot(knot_vel(st, @kn_ms_whip, @kn_ms_wknee, @kn_ms_wankle), nil)
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :land), @gait_spring)
    ch.on_enter(->(f, c) knot_enter(f, st, sw))
    ch.followed_by(st + "kpush")
    ch

  -> knot_enter(f, st, sw)
    enter(f, st, sw, :land)
    @knot_stance = true
    @t_td = f.t
    self

  # Mid-stance -> lift-off: a knot chunk latched on the foot's release.
  -> kpush_chunk(st, sw)
    p = Pose.new
    knot_leg(p, st, @kn_lo_thigh, @kn_lo_knee, @kn_lo_ankle)
    p.set(st + "toe", @toe_push, @stiff_st)
    leg(p, sw, @psi_late + @knee_lift + @phi_nom, @k_late, ~0.0, @stiff_sw)
    upper(p, st, sw)
    ch = Chunk.new(st + "kpush", @kn_t_lo).pose(p)
    ch.knot(knot_vel(st, @kn_lo_whip, @kn_lo_wknee, @kn_lo_wankle), nil)
    ch.hold_until(Latch.release(st + "foot").after_min(~0.01), @t_gate_max)
    ch.correct(->(f, c) stride_correction(f, c, st, sw, :push), @gait_spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :push))
    ch.followed_by(st + "kflight")
    ch

  -> enter(f, st, sw, phase)
    @knot_stance = false if phase == :land
    super(f, st, sw, phase)

  # ---- phase-gated drive -------------------------------------------------------------

  -> after(frame, ctl)
    super(frame, ctl)
    return self if !@knots || !@knot_stance
    return self if @phase != :land && @phase != :push
    e = frame.t - @t_td
    h = @k_z * @z_err
    st = @st
    gate(ctl, st + "hip_flex_neg", e, @kd_glut_on, @kd_glut_off, ~0.0)
    gate(ctl, st + "ham", e, @kd_ham_on, @kd_ham_off, ~0.0)
    gate(ctl, st + "knee_neg", e, @kd_vas_on, ~9.0, h)
    gate(ctl, st + "ankle_pos", e, @kd_sol_on, ~9.0, h)
    gate(ctl, st + "gas", e, @kd_gas_on, ~9.0, h)
    self

  -> gate(ctl, name, e, t_on, t_off, h)
    return self if !body.has?(name) || e < t_on || e >= t_off
    v = clamp(@kn_level + h, ~0.0, ~1.0)
    ctl.add_drive(body.index(name), v)
    self
