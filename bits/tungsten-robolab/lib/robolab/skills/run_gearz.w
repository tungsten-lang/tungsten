# RunGearZ: RunGearY (the sprint-5 chain's skill: RunGearX plus the opt-in mechanisms of sprint 5) plus the AT-RISK START GEAR of sprint 6
# (agent S6, scratchpad/sprint6/LOG.md: the labelled beyond-human sprinter, from 8 % falls to under 5 %). With the file switch rk_thr at its default
# (-9) this is RunGearYSkill exactly (checked: chain F1's params through this skill reproduce the arena's recorded per-seed scores of the champion of
# sprint_top_speed_v4_beyond_fresh128 on all 128 seeds); run_gear.w, run_gearx.w and run_geary.w are untouched, so every existing champion replays bit
# for bit.
#
# RESULT (labelled beyond-human body, 30 s perturbed standing starts of run_v4): chain S6a = F1 + rk_thr -0.05 + the rear-step profile of
# params/run_gearz_v4_beyond_s6a.txt falls on 51 of the 1000 selection seeds against F1's 73 (22 recovered, 0 new: every start outside the at-risk
# class is bit-identical to F1) and on 3 / 128 and 5 / 128 of the TEST A / B seeds (F1: 5 and 5), survivors' mean peak 10.11 m/s.
#
# THE PROBLEM. 59 % of F1's falls (S6, 1000 selection seeds) belong to standing starts whose COM begins behind the ankles: the early backward
# collapse at 1.3-2.3 s, the stalled lean that ends in a backward fall at 3-5 s, and most acceleration falls of the first strides (S6 LOG). The
# foot box ends 0.063 m behind the ankle: a start with COM - ankles about -0.063 m begins with its COM over the heel point, and the stock stand
# chunk's ankle strategy (a dorsiflexion offset of 2 rad per m of COM error) is satisfied by rotating the light foot toes-up about the heel
# instead of leaning the shank, which swings the whole body backward over the heel; the lean chunk's kick then puts the foot on its joint stop and
# the body balances on the heel point with nothing to hold it. No ankle clamp, slew limit, hip / knee / spine posture shift or trunk pulse helped
# (every posture shift is answered by the legs rotating back about the ankle; the heel carries at most 42 N m): the COM needs SUPPORT BEHIND IT,
# as a person steps back. The fix is the REAR STEP below, with two timing levers (an earlier end of the stand chunk and a shorter lean timeout) that
# make it work; the step is harmful for starts above rk_thr -0.05 (COM at least 1.3 cm ahead of the heel), which the stock sequence handles.
#
# THE AT-RISK GEAR. A start whose COM - ankles at the first tick is below the file switch rk_thr (m; -9 = never) runs gear 1 with the twins
# rk_<name> of every gear-1 tunable (the value of rk_<name> if the params file names it, else the plain value: with no rk_ line this is F1 exactly)
# and with these structure tunables, all neutral at their defaults and used only by at-risk starts:
#   stand chunk   rk_st_hip, rk_st_knee, rk_st_ankle, rk_st_spine, rk_st_sh, rk_st_elbow  offsets (rad) of the stand pose (hips 0.05, knees 0.12,
#                 ankles -0.05, spine @spine, shoulders 0, elbows @elbow); rk_st_dur  the pose's easing time (0.3 s), rk_st_hold  when the stand
#                 chunk ends (0.5 s), rk_st_tgt  offset of its ankle strategy's COM target (0.05 m)
#   lean chunk    rk_ln_hip, rk_ln_knee, rk_ln_ankle, rk_ln_spine, rk_ln_sh  offsets of the lean pose (hips 0.1, knees 0.2, ankles -0.2, spine
#                 @spine + 0.15, shoulders -+0.3), rk_ln_dur  easing time (0.4 s), rk_ln_to  the chunk's timeout (1.5 s), rk_ln_tgt  offset of the
#                 ankle strategy's COM target (d_go + 0.1)
#   ankle strategy  rk_cap_st / rk_cap_ln  clamp of its offset (rad; 99 = none) and rk_rate_st / rk_rate_ln  clamp of its rate of change (rad/s;
#                 99 = none) in the stand / lean chunk
#   rear step     rk_sr_hip, rk_sr_knee, rk_sr_ankle, rk_sr_t0, rk_sr_dur  a STEP of the right leg backward in the stand chunk (a start whose COM is over
#                 the heel needs a support behind it): from rk_sr_t0 s the right hip is extended by rk_sr_hip rad (negative = leg back; persistent
#                 until the first push), the right knee flexed by a bump of height rk_sr_knee rad that returns to zero (the foot clears the floor
#                 while it swings back and comes down behind the left foot), the right ankle offset by rk_sr_ankle, all over rk_sr_dur s
#   rk_k_bal (via the plain tunable k_bal's twin), the push-off of the first stride (psi0, k0, drv0_*, t0_max, ... twins) and everything else of gear 1.

# DYNAMIC REAR STEP (dy_*, off by default: dy_thr -9; implemented for the starts whose COM drifts behind the heel during the stand chunk, NEVER
# EVALUATED in sprint 6 and not used by S6a). For a start that is not in the at-risk class by its COM at t = 0 but whose COM - ankles
# falls below dy_thr (m) at any tick of the stand / lean chunks between dy_ta and dy_tb seconds (the COM drifts back over the heel while the stand
# chunk runs), the same rear step of the right leg starts at that moment: dy_hip, dy_knee, dy_ankle, dy_dur as the rk_sr_* of the at-risk gear.
# A start that never triggers is bit-identical to RunGearY's.

+ RunGearZSkill < RunGearYSkill
  -> start(frame, ctl)
    thr = ~-9.0
    thr = @params["rk_thr"] if @params.key?("rk_thr")
    @rk = f_com_behind(frame) < thr
    @u_ank = ~0.0
    @dy_on = false
    @dy_t0 = ~0.0
    super(frame, ctl)

  -> f_com_behind(f)
    f.com_x - feet_x(f)

  # at-risk starts read rk_<name> where the params file names it; every tunable declares its twin
  -> param(name, default, lo, hi)
    if name.size > 3 && name.slice(0, 3) == "rk_"
      @declared.push("TUNABLE [name] [default] [lo] [hi]")
      return @params[name] if @params.key?(name)
      return default
    v = super(name, default, lo, hi)
    return v if @gear >= 2 || gear_name?(name)
    @declared.push("TUNABLE rk_[name] [v] [lo] [hi]")
    return v if !@rk
    key = "rk_" + name
    return @params[key] if @params.key?(key)
    v

  -> read_params
    super
    @rk_st_hip = param("rk_st_hip", ~0.0, ~-0.6, ~0.8)
    @rk_st_knee = param("rk_st_knee", ~0.0, ~-0.12, ~0.8)
    @rk_st_ankle = param("rk_st_ankle", ~0.0, ~-0.4, ~0.4)
    @rk_st_spine = param("rk_st_spine", ~0.0, ~-0.6, ~0.8)
    @rk_st_sh = param("rk_st_sh", ~0.0, ~-0.8, ~1.6)
    @rk_st_elbow = param("rk_st_elbow", ~0.0, ~-1.0, ~1.0)
    @rk_st_dur = param("rk_st_dur", ~0.3, ~0.1, ~2.5)
    @rk_st_hold = param("rk_st_hold", ~0.5, ~0.3, ~3.0)
    @rk_st_tgt = param("rk_st_tgt", ~0.0, ~-0.3, ~0.3)
    @rk_ln_hip = param("rk_ln_hip", ~0.0, ~-0.6, ~0.8)
    @rk_ln_knee = param("rk_ln_knee", ~0.0, ~-0.2, ~0.8)
    @rk_ln_ankle = param("rk_ln_ankle", ~0.0, ~-0.4, ~0.4)
    @rk_ln_spine = param("rk_ln_spine", ~0.0, ~-0.6, ~0.8)
    @rk_ln_sh = param("rk_ln_sh", ~0.0, ~-0.8, ~1.2)
    @rk_ln_dur = param("rk_ln_dur", ~0.4, ~0.1, ~2.5)
    @rk_ln_to = param("rk_ln_to", ~1.5, ~0.3, ~4.0)
    @rk_ln_tgt = param("rk_ln_tgt", ~0.0, ~-0.4, ~0.4)
    @rk_cap_st = param("rk_cap_st", ~99.0, ~0.0, ~99.0)
    @rk_cap_ln = param("rk_cap_ln", ~99.0, ~0.0, ~99.0)
    @rk_rate_st = param("rk_rate_st", ~99.0, ~0.02, ~99.0)
    @rk_rate_ln = param("rk_rate_ln", ~99.0, ~0.02, ~99.0)
    @rk_sr_hip = param("rk_sr_hip", ~0.0, ~-0.8, ~0.4)
    @rk_sr_knee = param("rk_sr_knee", ~0.0, ~-0.2, ~1.6)
    @rk_sr_ankle = param("rk_sr_ankle", ~0.0, ~-0.6, ~0.6)
    @rk_sr_t0 = param("rk_sr_t0", ~0.05, ~0.0, ~1.5)
    @rk_sr_dur = param("rk_sr_dur", ~0.3, ~0.1, ~1.5)
    @dy_thr = param("dy_thr", ~-9.0, ~-9.0, ~0.2)
    @dy_ta = param("dy_ta", ~0.3, ~0.0, ~1.5)
    @dy_tb = param("dy_tb", ~0.9, ~0.1, ~3.0)
    @dy_hip = param("dy_hip", ~0.0, ~-0.8, ~0.4)
    @dy_knee = param("dy_knee", ~0.0, ~-0.2, ~1.6)
    @dy_ankle = param("dy_ankle", ~0.0, ~-0.6, ~0.6)
    @dy_dur = param("dy_dur", ~0.3, ~0.1, ~1.5)
    self

  -> stand_chunk
    if !@rk
      ch0 = super
      ch0.correct(->(f, ctl) dy_balance(f, ctl, ~0.05), ~0.08) if @dy_thr > ~-8.0
      return ch0
    p = Pose.new
    ["l_", "r_"].each ->
      s = item
      p.set(s + "hip_flex", ~0.05 + @rk_st_hip, @stiff)
      p.set(s + "knee", ~0.12 + @rk_st_knee, @stiff)
      p.set(s + "ankle", ~-0.05 + @rk_st_ankle, @stiff)
      p.set(s + "shoulder_flex", @rk_st_sh, @stiff)
      p.set(s + "elbow", @elbow + @rk_st_elbow, @stiff)
    p.set("spine_flex", @spine + @rk_st_spine, @stiff)
    ch = Chunk.new("stand", @rk_st_dur).pose(p).hold_until(Latch.after(@rk_st_hold))
    ch.correct(->(f, ctl) rk_balance(f, ctl, ~0.05 + @rk_st_tgt, @rk_cap_st, @rk_rate_st), ~0.08)
    ch

  -> lean_chunk
    if !@rk
      ch0 = super
      ch0.correct(->(f, ctl) dy_balance(f, ctl, @d_go + ~0.1), ~0.08) if @dy_thr > ~-8.0
      return ch0
    p = Pose.new
    ["l_", "r_"].each ->
      s = item
      p.set(s + "hip_flex", ~0.1 + @rk_ln_hip, @stiff)
      p.set(s + "knee", ~0.2 + @rk_ln_knee, @stiff)
      p.set(s + "ankle", ~-0.2 + @rk_ln_ankle, @stiff)
    p.set("spine_flex", @spine + ~0.15 + @rk_ln_spine, @stiff)
    p.set("l_shoulder_flex", ~-0.3 - @rk_ln_sh, @stiff)
    p.set("r_shoulder_flex", ~0.3 + @rk_ln_sh, @stiff)
    ahead = Latch.test("com_ahead", ->(f, e, c) com_ahead?(f))
    ch = Chunk.new("lean", @rk_ln_dur).pose(p).hold_until(ahead.after_min(~0.1), @rk_ln_to)
    ch.correct(->(f, ctl) rk_balance(f, ctl, @d_go + ~0.1 + @rk_ln_tgt, @rk_cap_ln, @rk_rate_ln), ~0.08)
    ch

  # the ankle strategy of the stand and lean chunks (RunSkill#balance, with RunGearY's k_bal / k_bals) with its offset clamped at +-cap rad and its
  # rate of change at +-rate rad/s; cap and rate >= 90 mean no clamp, which is RunGearY's balance exactly
  -> rk_balance(f, ctl, target, cap, rate)
    c = f.com_x - feet_x(f)
    e = c - target
    dq = @k_bal * (~2.0 * e + ~0.4 * f.com_vx)
    dq = clamp(dq, ~0.0 - cap, cap) if cap < ~90.0
    if rate < ~90.0
      step = rate * ctl.dt
      dq = clamp(dq, @u_ank - step, @u_ank + step)
    @u_ank = dq
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    joint_offset(off, "spine_flex", ~0.0 - @k_bals * e) if @k_bals != ~0.0
    rk_step_offsets(off, f)

  # the right leg's rear step (rk_sr_*): hip and ankle offsets follow a smoothstep over rk_sr_dur from rk_sr_t0 and stay, the knee offset is a sine bump
  -> rk_step_offsets(off, f)
    return off if @rk_sr_hip == ~0.0 && @rk_sr_knee == ~0.0 && @rk_sr_ankle == ~0.0
    u = clamp((f.t - @rk_sr_t0) / @rk_sr_dur, ~0.0, ~1.0)
    sm = u * u * (~3.0 - ~2.0 * u)
    joint_offset(off, "r_hip_flex", @rk_sr_hip * sm) if @rk_sr_hip != ~0.0
    joint_offset(off, "r_knee", @rk_sr_knee * Math.sin(~3.14159265 * u)) if @rk_sr_knee != ~0.0
    joint_offset(off, "r_ankle", @rk_sr_ankle * sm) if @rk_sr_ankle != ~0.0
    off

  # the stock ankle strategy plus, once triggered, the dynamic rear step (dy_*)
  -> dy_balance(f, ctl, target)
    off = balance(f, target)
    if !@dy_on && f.t >= @dy_ta && f.t <= @dy_tb && f.com_x - feet_x(f) < @dy_thr
      @dy_on = true
      @dy_t0 = f.t
    return off if !@dy_on
    u = clamp((f.t - @dy_t0) / @dy_dur, ~0.0, ~1.0)
    sm = u * u * (~3.0 - ~2.0 * u)
    joint_offset(off, "r_hip_flex", @dy_hip * sm) if @dy_hip != ~0.0
    joint_offset(off, "r_knee", @dy_knee * Math.sin(~3.14159265 * u)) if @dy_knee != ~0.0
    joint_offset(off, "r_ankle", @dy_ankle * sm) if @dy_ankle != ~0.0
    off
