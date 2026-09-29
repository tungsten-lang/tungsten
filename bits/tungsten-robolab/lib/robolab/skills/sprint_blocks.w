# SprintBlocks: a sprint from starting blocks, keyframed on Usain Bolt.
#
# The stride machinery of run_natural (load / drive / flight chunks latched on
# the gait events, via-chained keyframes, the stance-hip trunk servo, the
# push-off drives and the hop-height loop; copied from RunNaturalSkill as of
# 2026-09-27 so this skill does not change when that one does) with Bolt's keyframes
# (SprintRef, generated from playground/refs/bolt/bolt_keyframes.json by
# `playground/tasks/sprint_blocks.py refw`) and a block start in front:
#
#   set         hold the set position (Bolt's `set` keyframe) until the gun
#               sensor has read `react` seconds (World Athletics: a reaction
#               under 0.100 s is a false start)
#   rear_push   both legs drive, the rear leg extends and leaves its pad;
#               eased toward Bolt's `rear_exit` keyframe; ends when the rear
#               pad's force drops (the `blocks` sensor)
#   front_push  the front leg drives to full extension while the rear thigh
#               swings through; toward `block_exit`; ends on the front pad's
#               force dropping
#   s0_fly      flight to the first touchdown (the rear leg lands)
#   steps 1..N  (n_acc, even) acceleration steps: load -> drive -> flight per
#               step, each keyframe blended by step index between Bolt's
#               anchors: steps 1-3 (s1..s3), the drive phase (step k_drive)
#               and the max-velocity cycle (step N + 1); the torso target,
#               the hop-height reference and the command offsets blend with
#               the same index
#   max velocity  run_natural's six-chunk loop on Bolt's maxv keyframes
#
# The front leg is the left (the task's pads), so step 1 is a right stance
# and the loop starts after the left toe-off of step N. Every keyframe is
# the reference plus a searched offset per leg joint (the servo sags under
# load, so the command that ACHIEVES a posture is not the posture); the
# arms, elbows, toes and spine come from the reference. A params-file entry
# ref_<event>_<key> (degrees, SprintRef's keys) replaces one reference value,
# so postures edited in the keyframe editor can be fed back.

+ SprintBlocksSkill < Skill
  -> start(frame, ctl)
    mv = Movement.new("sprint_blocks")
    build_start(frame, ctl, mv, -1)
    add_loop(mv)
    ctl.add_track(Track.new("body", mv, body.all))

  # The set, the block pushes, the flight to step 1 and the acceleration steps,
  # appended to `mv`: n steps (at least 2 and even, so the last toe-off is the
  # left's), or the params' n_acc when n < 0. Reuse from another skill (e.g.
  # a hurdler's first 13.72 m): hold a SprintBlocksSkill.new(body, params),
  # call its build_start(frame, ctl, mv, n) in your start, append your own
  # chunks (the first is the flight after the left toe-off, the right leg
  # landing), and call its before / after each tick until your first chunk
  # is entered. Its tunables are declared with the same names as here.
  -> build_start(frame, ctl, mv, n)
    read_params
    read_sprint_params
    @n_acc = n if n >= 0
    @v_f = frame.com_vx
    @v_des = @speed
    @t_go = ~-1.0
    @t_now = frame.t
    @phase = nil
    @t_phase = frame.t
    @st = "r_"
    @sw = "l_"
    @drives = []
    @step = 0
    setup_reflexes(ctl)
    set_reflexes(ctl)
    @ref = SprintRef.new
    set_step_targets(0)
    # a params-file switch for testing the stride alone: `flying 1` skips the
    # blocks and the acceleration steps (the task's SPRINT_START=flying
    # starts the body in flight at speed)
    # (`flying 2`: from the flight after the block exit, through the
    # acceleration steps; the task's SPRINT_FLY_KF=block_exit poses it)
    flying = @params.key?("flying") && @params["flying"] > ~0.5
    exit_fly = flying && @params["flying"] > ~1.5
    if flying
      setup_reflexes(ctl)
      ctl.reflex.set_integral(body.all, ~0.0, ~0.0)
      @t_go = frame.t
    if flying && !exit_fly
      @n_acc = 0
    else
      if !flying
        mv.add(set_chunk)
        mv.add(rear_push_chunk)
        mv.add(front_push_chunk)
      # flight to the first touchdown (right stance)
      step_durations(~0.0)
      td1 = accel_kf(1, "td", "r_")
      fly0 = flight_chunk("l_", "r_", td1, block_kf("block_exit"))
      fly0.on_enter(->(f, c) enter_step(f, c, "l_", "r_", :flight, 0, "s1_td", "r_"))
      mv.add(fly0)
    k = 1
    while k <= @n_acc
      st = "r_"
      st = "l_" if k % 2 == 0
      sw = "l_"
      sw = "r_" if st == "l_"
      td = accel_kf(k, "td", st)
      ms = accel_kf(k, "ms", st)
      to = accel_kf(k, "to", st)
      add_step(mv, k, st, sw, td, ms, to)
      k += 1
    self

  # The acceleration step being run (0 in the blocks and the first flight):
  # a host skill that built the start with build_start calls this skill's
  # before / after each tick until its own first chunk (entered after the
  # last acceleration step's toe-off) begins.
  -> step
    @step

  # the max-velocity cycle: run_natural's six chunks on Bolt's maxv keyframes
  -> add_loop(mv)
    step_durations(~1.0)
    td_r = maxv_kf("td", "r_")
    ms_r = maxv_kf("ms", "r_")
    to_r = maxv_kf("to", "r_")
    td_l = maxv_kf("td", "l_")
    ms_l = maxv_kf("ms", "l_")
    to_l = maxv_kf("to", "l_")
    last = @n_acc + 1
    first = mv.size
    tag(mv.add(flight_chunk("l_", "r_", td_r, to_l)), "l_", "r_", :flight, last, "maxv_td", "r_")
    tag(mv.add(load_chunk("r_", "l_", ms_r, td_r)), "r_", "l_", :load, last, "maxv_ms", "r_")
    tag(mv.add(drive_chunk("r_", "l_", to_r, ms_r)), "r_", "l_", :drive, last, "maxv_to", "r_")
    tag(mv.add(flight_chunk("r_", "l_", td_l, to_r)), "r_", "l_", :flight, last, "maxv_td", "l_")
    tag(mv.add(load_chunk("l_", "r_", ms_l, td_l)), "l_", "r_", :load, last, "maxv_ms", "l_")
    tag(mv.add(drive_chunk("l_", "r_", to_l, ms_l)), "l_", "r_", :drive, last, "maxv_to", "l_")
    mv.loop_from(first)
    self

  # Acceleration step k: load (toward mid-stance), drive (toward toe-off) and,
  # before the last one, the flight to the next step's touchdown.
  -> add_step(mv, k, st, sw, td, ms, to)
    ev = anchor_event(k)
    step_durations(blend(k))
    ld = tag(mv.add(load_chunk(st, sw, ms, td)), st, sw, :load, k, ev + "_td", st)
    # early steps: the stance extensors are driven through the loading too
    # (drv_acc, fading with the step blend), so a low body does not sink
    a = @drv_acc * (~1.0 - blend(k))
    ld.drive(drive_vec([st + "knee_neg", @pre_knee + a, st + "ankle_pos", @pre_ankle + a, st + "gas", a,
                        st + "hip_flex_neg", a, sw + "knee_pos", @drv_tuck,
                        sw + "hip_flex_pos", @drv_swload, sw + "rf", @drv_swload * @drv_swrf]))
    tag(mv.add(drive_chunk(st, sw, to, ms)), st, sw, :drive, k, ev + "_to", st)
    return self if k >= @n_acc
    nxt = accel_kf(k + 1, "td", sw)
    tag(mv.add(flight_chunk(st, sw, nxt, to)), st, sw, :flight, k + 1, anchor_event(k + 1) + "_td", sw)
    self

  # Chunk durations of a step `b` of the way from step 1's to the loop's
  # (read when the chunks are built).
  -> step_durations(b)
    @t_load = @t_load_a + (@t_load_m - @t_load_a) * b
    @t_drive = @t_drive_a + (@t_drive_m - @t_drive_a) * b
    @t_fly = @t_fly_a + (@t_fly_m - @t_fly_a) * b
    self

  -> tag(ch, st, sw, phase, k, ev, side)
    ch.on_enter(->(f, c) enter_step(f, c, st, sw, phase, k, ev, side))
    ch

  # The reference event shown for step k (the nearest anchor).
  -> anchor_event(k)
    return "s1" if k <= 1
    return "s2" if k == 2
    return "s3" if k == 3
    return "drive" if k < (@k_drive + @n_acc + 1) / 2
    "maxv"

  -> read_sprint_params
    # structure (params-file settings): acceleration steps (even) and the
    # step at which Bolt's drive-phase keyframes are reached
    @n_acc = 12
    @n_acc = @params["n_acc"].to_i if @params.key?("n_acc")
    @n_acc = @n_acc + 1 if @n_acc % 2 == 1
    @n_acc = 2 if @n_acc < 2
    @k_drive = 6
    @k_drive = @params["k_drive"].to_i if @params.key?("k_drive")
    @k_drive = 4 if @k_drive < 4
    @k_drive = @n_acc if @k_drive > @n_acc
    # set and reaction (s after the gun sensor)
    @react = param("react", ~0.12, ~0.05, ~0.3)
    @stiff_set = param("stiff_set", ~0.1, ~0.0, ~0.35)
    @g_set = param("g_set", ~1.0, ~0.4, ~2.0)
    # postural tone in the set: an integral of every muscle's error (Reflex
    # set_integral) removes the servo's sag, switched off at the gun
    @ki_set = param("ki_set", ~20.0, ~0.0, ~60.0)
    @ki_lim = param("ki_lim", ~0.02, ~0.0, ~0.05)
    # stiffer servos in the set (x the running gains): the arms prop the trunk
    @kp_set_up = param("kp_set_up", ~3.0, ~1.0, ~6.0)
    @kp_set_leg = param("kp_set_leg", ~1.5, ~1.0, ~4.0)
    # ... of the set's own base gains (not the running ones, so re-practising
    # the stride does not disturb the set)
    @set_leg_kp = param("set_leg_kp", ~7.8187, ~3.0, ~12.0)
    @set_leg_kd = param("set_leg_kd", ~0.251, ~0.05, ~0.6)
    @set_up_kp = param("set_up_kp", ~5.231, ~2.0, ~12.0)
    @set_up_kd = param("set_up_kd", ~0.1244, ~0.05, ~0.6)
    # holding still: the pads push the body forward (their faces lean back),
    # so the COM's drift from where the set began flexes the shoulders (the
    # hands push the track forward, the body back): rad per m and per m/s
    @k_hold = param("k_hold", ~8.0, ~0.0, ~30.0)
    @k_hold_v = param("k_hold_v", ~2.0, ~0.0, ~8.0)
    # ... plus an integral (rad per m s) once the settling is over (t_hold s
    # into the set; before that the reference follows the pelvis)
    @k_hold_i = param("k_hold_i", ~0.0, ~0.0, ~150.0)
    @t_hold = param("t_hold", ~0.0, ~0.0, ~0.6)
    @x_set = nil
    @hold_i = ~0.0
    # both feet pressed into their pads in the set (extensor tone)
    @drv_set_r = param("drv_set_r", ~0.1, ~0.0, ~0.5)
    @drv_set_f = param("drv_set_f", ~0.05, ~0.0, ~0.5)
    # the hands push the chest up as the legs drive (shoulder extensors)
    @drv_rx_sh = param("drv_rx_sh", ~0.3, ~0.0, ~1.0)
    # the back extensors raise the chest out of the blocks: a drive on
    # spine_flex_neg in both pushes, and a spine offset (deg) on the
    # rear-exit and block-exit keyframes
    @drv_spine = param("drv_spine", ~0.0, ~0.0, ~1.0)
    # reflex gain of the pushing extensors in the block phase: the eased
    # command lags an explosive push, and the stretch reflex would then brake
    # it (inhibit the agonist, recruit the antagonist), so the push is mostly
    # feed-forward drive
    @g_push = param("g_push", ~1.0, ~0.0, ~1.5)
    # the hands stay on the track this long into the rear push (the arms
    # carry the upper body while the legs load), then swing
    @arm_delay = param("arm_delay", ~0.0, ~0.0, ~0.3)
    # ... and while they are planted the shoulder flexors push the chest up
    # and back off them (a hand push-off)
    @drv_rx_shf = param("drv_rx_shf", ~0.0, ~0.0, ~1.0)
    @blk = nil
    @push_rear = extensors("r_") + extensors("l_")
    @push_front = extensors("l_")
    @swing_ext = extensors("r_")
    @d_bx_spine = param("d_bx_spine", ~0.0, ~-40.0, ~20.0)
    # block phase: durations, reflex gain, drives
    @t_rx = param("t_rx", ~0.15, ~0.05, ~0.4)
    @t_bx = param("t_bx", ~0.2, ~0.05, ~0.5)
    @g_blk = param("g_blk", ~1.0, ~0.3, ~2.0)
    @stiff_blk = param("stiff_blk", ~0.1, ~0.0, ~0.35)
    @drv_rx_knee = param("drv_rx_knee", ~0.8, ~0.0, ~1.0)
    @drv_rx_ankle = param("drv_rx_ankle", ~0.8, ~0.0, ~1.0)
    @drv_rx_hip = param("drv_rx_hip", ~0.6, ~0.0, ~1.0)
    @drv_fx_knee = param("drv_fx_knee", ~0.5, ~0.0, ~1.0)
    @drv_fx_ankle = param("drv_fx_ankle", ~0.5, ~0.0, ~1.0)
    @drv_fx_hip = param("drv_fx_hip", ~0.5, ~0.0, ~1.0)
    @drv_bx_knee = param("drv_bx_knee", ~0.9, ~0.0, ~1.0)
    @drv_bx_ankle = param("drv_bx_ankle", ~0.9, ~0.0, ~1.0)
    @drv_bx_hip = param("drv_bx_hip", ~0.7, ~0.0, ~1.0)
    # the biarticulars apart: the hamstrings extend the hip but flex the knee,
    # the rectus femoris extends the knee but flexes the hip
    @drv_rx_ham = param("drv_rx_ham", @drv_rx_hip, ~0.0, ~1.0)
    @drv_fx_ham = param("drv_fx_ham", @drv_fx_hip, ~0.0, ~1.0)
    @drv_bx_ham = param("drv_bx_ham", @drv_bx_hip, ~0.0, ~1.0)
    @drv_rx_rf = param("drv_rx_rf", ~0.0, ~0.0, ~1.0)
    @drv_fx_rf = param("drv_fx_rf", ~0.0, ~0.0, ~1.0)
    @drv_bx_st_rf = param("drv_bx_st_rf", ~0.0, ~0.0, ~1.0)
    @drv_bx_swh = param("drv_bx_swh", ~0.6, ~0.0, ~1.0)
    # the rear leg swinging through in the front push: its knee flexor (heel
    # up, less inertia) and the reflex gain of its (stretched) extensors
    @drv_bx_swk = param("drv_bx_swk", ~0.0, ~0.0, ~1.0)
    @g_swext = param("g_swext", ~1.0, ~0.0, ~1.5)
    @drv_bx_rf = param("drv_bx_rf", ~0.4, ~0.0, ~1.0)
    @rx_off = param("rx_off", ~0.3, ~0.02, ~0.8)
    # the rear push ends at the latest t_rx_max after it began (the rear leg
    # then swings through whether or not its pad has unloaded)
    @t_rx_max = param("t_rx_max", ~0.45, ~0.08, ~0.45)
    @bx_off = param("bx_off", ~0.3, ~0.02, ~0.8)
    # placement: 1 = the pitch compensation refers to each step's keyframe
    # pelvis (run_natural's is a fixed 3 deg)
    # early steps: extensor drive in the loading (see add_step), and how much
    # of the max-velocity cycle's mid-stance yield (the knee bending, the ankle
    # dorsiflexing past the TD-TO midpoint) the early anchors' mid-stance takes
    @drv_acc = param("drv_acc", ~0.0, ~0.0, ~1.0)
    @arm_acc = param("arm_acc", ~1.0, ~0.2, ~1.0)
    @elbow_acc = param("elbow_acc", ~0.0, ~0.0, ~40.0)
    # ... and the swing leg's hip flexors driven through the other leg's
    # loading too (run_natural drives them only in its push and in flight),
    # the rectus femoris at drv_swrf of that
    @drv_swload = param("drv_swload", ~0.0, ~0.0, ~1.0)
    @drv_swrf = param("drv_swrf", ~0.5, ~0.0, ~1.0)
    @ms_bump = param("ms_bump", ~1.0, ~0.0, ~1.0)
    # the arms keep their keyframe's world angle when the torso pitches away
    # from its target (k_arm of the torso error comes off both shoulders)
    @k_arm = param("k_arm", ~1.0, ~0.0, ~1.5)
    # foot placement in task space (SIMBICON's balance feedback, as a servo):
    # in flight the landing hip flexes k_cp rad per m that the landing foot is
    # behind x_des = cp_gain * vx * sqrt(z_com / g) + cp_x (ahead of the COM),
    # clamped to +-corr_lim; 0 = off (run_natural's placement only)
    @k_cp = param("k_cp", ~0.0, ~0.0, ~6.0)
    @cp_gain = param("cp_gain", ~0.5, ~0.0, ~1.5)
    @cp_x = param("cp_x", ~0.0, ~-0.4, ~0.4)
    # world-frame swing thigh: the keyframes' hips are relative to the pelvis
    # at Bolt's pitch, so a body pitched further forward would swing its
    # thigh short; the swinging leg's hip takes up k_swcomp of the pelvis's
    # pitch beyond the keyframe's (clamped to +-swcomp_lim rad), in the
    # front push and in every flight and stance (use with comp 0: run_natural's
    # own term is the same, clamped to corr_lim)
    @k_swcomp = param("k_swcomp", ~0.0, ~0.0, ~1.2)
    @swcomp_lim = param("swcomp_lim", ~1.0, ~0.2, ~1.5)
    @servo_pelvis = true
    @servo_pelvis = @params["servo_pelvis"] > ~0.5 if @params.key?("servo_pelvis")
    @pelvis_des = ~0.6
    @pelvis_follow = true
    @pelvis_follow = @params["pelvis_follow"] > ~0.5 if @params.key?("pelvis_follow")
    # torso: the target is the keyframes' torso pitch x lean_scale + lean
    @lean_scale = param("lean_scale", ~1.0, ~0.2, ~1.3)
    @bx_kp = param("bx_kp", ~0.5, ~0.0, ~3.0)
    # hop height: z_ref0 at step 1 rising to z_ref at the max-velocity cycle
    @z_ref0 = param("z_ref0", ~0.82, ~0.65, ~1.0)
    # acceleration-step durations (blend to t_load / t_drive / t_fly)
    @t_load_a = param("t_load_a", ~0.08, ~0.03, ~0.3)
    @t_drive_a = param("t_drive_a", ~0.16, ~0.03, ~0.35)
    @t_fly_a = param("t_fly_a", ~0.08, ~0.03, ~0.35)
    @t_load_m = @t_load
    @t_drive_m = @t_drive
    @t_fly_m = @t_fly
    # command offsets (deg) of the block keyframes and of step 1 (blending to
    # run_natural's max-velocity offsets d_<td|ms|to>_<st|sw>_<joint>)
    ["set", "rx", "bx", "acc_td", "acc_ms", "acc_to"].each ->(kf)
      ["st", "sw"].each ->(role)
        ["hip", "knee", "ankle"].each ->(j)
          nm = "d_" + kf + "_" + role + "_" + j
          lim = ~40.0
          lim = ~60.0 if j == "hip"
          @off[nm] = param(nm, ~0.0, ~0.0 - lim, lim)
    self

  # ---- the reference -----------------------------------------------------------------

  # Bolt's model keyframe (degrees, SprintRef keys) with ref_<event>_<key>
  # params over it.
  -> bolt_deg(ev)
    base = @ref.deg(ev)
    keys = @ref.keys
    out = []
    i = 0
    while i < keys.size
      nm = "ref_" + ev + "_" + keys[i]
      v = base[i]
      v = @params[nm] if @params.key?(nm)
      out.push(v)
      i += 1
    out

  -> lerp_vals(a, b, t)
    out = []
    i = 0
    while i < a.size
      out.push(a[i] + (b[i] - a[i]) * t)
      i += 1
    out

  # An anchor's keyframe of a kind: measured TD / TO, and a mid-stance that is
  # the TD-TO midpoint plus the max-velocity cycle's mid-stance bump (the
  # stance knee's yield), which the video does not give for the early steps.
  -> anchor_deg(prefix, kind)
    return bolt_deg(prefix + "_" + kind) if prefix == "maxv" || kind != "ms"
    mid = lerp_vals(bolt_deg(prefix + "_td"), bolt_deg(prefix + "_to"), ~0.5)
    mmid = lerp_vals(bolt_deg("maxv_td"), bolt_deg("maxv_to"), ~0.5)
    bump = bolt_deg("maxv_ms")
    out = []
    i = 0
    while i < mid.size
      out.push(mid[i] + @ms_bump * (bump[i] - mmid[i]))
      i += 1
    out

  # Step k's reference keyframe: linear in the step index between the anchors
  # (1: s1, 2: s2, 3: s3, k_drive: drive, n_acc + 1: maxv).
  -> step_deg(k, kind)
    steps = [1, 2, 3, @k_drive, @n_acc + 1]
    names = ["s1", "s2", "s3", "drive", "maxv"]
    return anchor_deg("s1", kind) if k <= 1
    return anchor_deg("maxv", kind) if k >= @n_acc + 1
    i = 0
    while i < 4
      a = steps[i]
      b = steps[i + 1]
      if k >= a && k <= b
        t = (k - a) * ~1.0 / ((b - a) * ~1.0)
        return lerp_vals(anchor_deg(names[i], kind), anchor_deg(names[i + 1], kind), t)
      i += 1
    anchor_deg("maxv", kind)

  # Blend of step k toward the max-velocity cycle (0 at step 1, 1 at the loop).
  -> blend(k)
    return ~1.0 if @n_acc < 1
    b = (k - 1) * ~1.0 / (@n_acc * ~1.0)
    clamp(b, ~0.0, ~1.0)

  # A keyframe posture from reference degrees (SprintRef order), st the stance
  # (or front) side, leg offsets offs = [st hip, knee, ankle, sw hip, knee, ankle].
  -> kf_from(name, vals, st, offs, stiff_st, stiff_sw, spine_off = ~-999.0, stiff_arm = ~-1.0)
    rad = ~0.017453292519943295
    spine_off = @d_spine if spine_off < ~-900.0
    stiff_arm = @stiff_up if stiff_arm < ~0.0
    sw = "l_"
    sw = "r_" if st == "l_"
    k = SprintKeyframe.new(name)
    k.set_stance(st)
    k.set(st + "hip_flex", (vals[0] + offs[0]) * rad, stiff_st)
    k.set(st + "knee", (vals[1] + offs[1]) * rad, stiff_st)
    k.set(st + "ankle", (vals[2] + offs[2]) * rad, stiff_st)
    k.set(st + "toe", vals[3] * rad, stiff_st)
    k.set(sw + "hip_flex", (vals[4] + offs[3]) * rad, stiff_sw)
    k.set(sw + "knee", (vals[5] + offs[4]) * rad, stiff_sw)
    k.set(sw + "ankle", (vals[6] + offs[5]) * rad, stiff_sw)
    k.set(sw + "toe", vals[7] * rad, stiff_sw)
    k.set(st + "shoulder_flex", vals[8] * rad, stiff_arm)
    k.set(st + "elbow", vals[9] * rad, stiff_arm)
    k.set(sw + "shoulder_flex", vals[10] * rad, stiff_arm)
    k.set(sw + "elbow", vals[11] * rad, stiff_arm)
    k.set("spine_flex", (vals[12] + spine_off) * rad, stiff_arm)
    k

  -> offsets(prefix)
    out = []
    ["st", "sw"].each ->(role)
      ["hip", "knee", "ankle"].each ->(j)
        out.push(@off["d_" + prefix + "_" + role + "_" + j])
    out

  -> block_kf(ev)
    pre = "bx"
    pre = "set" if ev == "set"
    pre = "rx" if ev == "rear_exit"
    vals = bolt_deg(ev)
    # the set holds the task's posture exactly (no running spine offset, its
    # own co-contraction on the arms): gait params must not move a still body
    return kf_from(ev, vals, "l_", offsets(pre), @stiff_blk, @stiff_blk, ~0.0, @stiff_set) if ev == "set"
    vals[12] = vals[12] + @d_bx_spine
    kf_from(ev, vals, "l_", offsets(pre), @stiff_blk, @stiff_blk)

  -> accel_kf(k, kind, st)
    b = blend(k)
    offs = lerp_vals(offsets("acc_" + kind), offsets(kind), b)
    vals = step_deg(k, kind)
    # early steps: a narrower arm swing (arm_acc of the keyframe's shoulder
    # angles) and more bent elbows (+elbow_acc deg) keep the hands off the
    # track while the trunk is still low; both fade with the step blend
    a = ~1.0 - (~1.0 - @arm_acc) * (~1.0 - b)
    e = @elbow_acc * (~1.0 - b)
    vals[8] = vals[8] * a
    vals[10] = vals[10] * a
    vals[9] = vals[9] + e
    vals[11] = vals[11] + e
    kf_from("s" + k.to_s + "_" + kind, vals, st, offs, @stiff_st, @stiff_sw)

  -> maxv_kf(kind, st)
    kf_from("maxv_" + kind, bolt_deg("maxv_" + kind), st, offsets(kind), @stiff_st, @stiff_sw)

  # Torso pitch (rad) of step k: the mean of its TD and TO keyframes'
  # pelvis + spine, scaled by lean_scale, plus the lean bias.
  -> torso_target(k)
    rad = ~0.017453292519943295
    a = step_deg(k, "td")
    b = step_deg(k, "to")
    deg = (a[12] + a[13] + b[12] + b[13]) * ~0.5
    (deg * @lean_scale + @lean) * rad

  # The pelvis pitch (rad) step k's keyframes assume (mean of its TD and TO):
  # the placement corrections (run_natural's `comp`) hold the limbs' world
  # angles against the pelvis pitching away from it.
  -> pelvis_target(k)
    a = step_deg(k, "td")
    b = step_deg(k, "to")
    (a[13] + b[13]) * ~0.5 * ~0.017453292519943295

  -> set_step_targets(k)
    kk = k
    kk = 1 if kk < 1
    @trunk_des = torso_target(kk)
    @pelvis_ref = pelvis_target(kk) if @pelvis_follow
    @pelvis_des = pelvis_target(kk) * @lean_scale + @lean * ~0.017453292519943295
    @z_step = @z_ref0 + (@z_ref - @z_ref0) * blend(kk)
    self

  -> enter_step(f, ctl, st, sw, phase, k, ev, side)
    @blk = nil
    enter(f, st, sw, phase)
    @step = k
    set_step_targets(k)
    ctl.emit("kf:" + ev + ":" + side.slice(0, 1))
    self

  # ---- the block phase ---------------------------------------------------------------

  -> set_chunk
    ch = Chunk.new("set", ~0.3).pose(block_kf("set").pose)
    ch.hold_until(Latch.above("gun", 0, @react))
    ch.gain(@g_set)
    ch.drive(drive_vec(["r_knee_neg", @drv_set_r, "r_ankle_pos", @drv_set_r, "r_gas", @drv_set_r, "r_hip_flex_neg", @drv_set_r,
                        "l_knee_neg", @drv_set_f, "l_ankle_pos", @drv_set_f, "l_gas", @drv_set_f, "l_hip_flex_neg", @drv_set_f]))
    ch.correct(->(f, c) set_hold(f, c), ~0.02)
    ch.on_enter(->(f, c) c.emit("kf:set:l"))
    ch

  -> rear_push_chunk
    ch = aim(Chunk.new("rear_push", @t_rx), block_kf("rear_exit"))
    ch.via if @via && @arm_delay <= ~0.0
    ch.stagger(body.mask(["l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @arm_delay) if @arm_delay > ~0.0
    off = Latch.below("blocks", 1, @rx_off * ~0.1)
    ch.hold_until(off.after_min(~0.04), @t_rx_max)
    ch.drive(drive_vec(["r_knee_neg", @drv_rx_knee, "r_ankle_pos", @drv_rx_ankle, "r_gas", @drv_rx_ankle,
                        "r_hip_flex_neg", @drv_rx_hip, "r_ham", @drv_rx_ham, "r_rf", @drv_rx_rf,
                        "l_knee_neg", @drv_fx_knee, "l_ankle_pos", @drv_fx_ankle, "l_gas", @drv_fx_ankle,
                        "l_hip_flex_neg", @drv_fx_hip, "l_ham", @drv_fx_ham, "l_rf", @drv_fx_rf,
                        "l_shoulder_flex_neg", @drv_rx_sh, "r_shoulder_flex_neg", @drv_rx_sh, "spine_flex_neg", @drv_spine,
                        "l_shoulder_flex_pos", @drv_rx_shf, "r_shoulder_flex_pos", @drv_rx_shf]))
    ch.gain(@g_blk)
    ch.on_enter(->(f, c) block_enter(c, "rear_exit"))
    ch

  -> front_push_chunk
    ch = aim(Chunk.new("front_push", @t_bx), block_kf("block_exit"))
    ch.via if @via
    off = Latch.below("blocks", 0, @bx_off * ~0.1)
    ch.hold_until(off.after_min(~0.04), ~0.6)
    ch.drive(drive_vec(["l_knee_neg", @drv_bx_knee, "l_ankle_pos", @drv_bx_ankle, "l_gas", @drv_bx_ankle,
                        "l_hip_flex_neg", @drv_bx_hip, "l_ham", @drv_bx_ham, "l_rf", @drv_bx_st_rf,
                        "r_hip_flex_pos", @drv_bx_swh, "r_rf", @drv_bx_rf, "spine_flex_neg", @drv_spine,
                        "r_knee_pos", @drv_bx_swk]))
    ch.gain(@g_blk)
    ch.correct(->(f, c) block_torso(f, c), @spring)
    ch.on_enter(->(f, c) block_enter(c, "block_exit"))
    ch

  # The set's servos: the running gains x kp_set_up (spine, shoulders,
  # elbows) and x kp_set_leg (legs), plus the postural integral.
  -> set_reflexes(ctl)
    up = body.mask(["spine", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow"])
    ctl.reflex.set_gains(up, @set_up_kp * @kp_set_up, @set_up_kd * @kp_set_up)
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe"])
    ctl.reflex.set_gains(legs, @set_leg_kp * @kp_set_leg, @set_leg_kd * @kp_set_leg)
    ctl.reflex.set_integral(body.all, @ki_set, @ki_lim) if @ki_set > ~0.0
    self

  -> set_hold(f, ctl)
    x = f.com_x
    @x_set = x if @x_set == nil || f.t < @t_hold
    dx = x - @x_set
    @hold_i = clamp(@hold_i + dx * ctl.dt, ~-0.01, ~0.01) if f.t >= @t_hold
    off = zeros
    a = clamp(@k_hold * dx + @k_hold_v * f.com_vx + @k_hold_i * @hold_i, ~-0.4, ~0.4)
    joint_offset(off, "l_shoulder_flex", a)
    joint_offset(off, "r_shoulder_flex", a)
    off

  -> extensors(side)
    out = []
    ["knee_neg", "ankle_pos", "gas", "hip_flex_neg", "ham"].each ->(m)
      out.push(body.index(side + m)) if body.has?(side + m)
    out

  -> block_enter(ctl, ev)
    @blk = ev
    @bx_pelvis = bolt_deg("block_exit")[13] * ~0.017453292519943295
    @pelvis_des = (bolt_deg(ev)[13] * @lean_scale + @lean) * ~0.017453292519943295
    @t_go = @t_now if ev == "rear_exit"
    if ev == "rear_exit"
      setup_reflexes(ctl)
      ctl.reflex.set_integral(body.all, ~0.0, ~0.0)
      ctl.reflex.reset_integral
    @trunk_des = torso_of(bolt_deg(ev))
    ctl.emit("kf:" + ev + ":l")
    self

  -> torso_of(vals)
    (((vals[12] + vals[13]) * @lean_scale) + @lean) * ~0.017453292519943295

  # Front-leg push: the front hip servos the trunk toward the block-exit lean
  # (a clamped PD, bx_kp), the knee and ankle follow the keyframe.
  -> block_torso(f, ctl)
    off = zeros
    err = trunk_err(f)
    pd = ~0.0 - @bx_kp * err - @torso_kd * f.torso_pitch_rate
    joint_offset(off, "l_hip_flex", clamp(pd, ~0.0 - @corr_lim, @corr_lim))
    swing_comp(off, f, "r_", @bx_pelvis)
    arms(off, f)

  # Both shoulders take up k_arm of the torso's pitch error (radians,
  # clamped to +-1): an arm's world angle is its shoulder flexion minus the
  # torso pitch, so a torso pitched further forward than planned flexes the
  # shoulders by as much and the hands keep their keyframe's world direction
  # instead of swinging into the track.
  -> arms(off, f)
    a = clamp(@k_arm * (f.torso_pitch - @trunk_des), ~-1.0, ~1.0)
    joint_offset(off, "l_shoulder_flex", a)
    joint_offset(off, "r_shoulder_flex", a)
    off

  -> swing_comp(off, f, leg, ref)
    return off if @k_swcomp <= ~0.0
    tilt = pelvis_pitch(f) - ref
    joint_offset(off, leg + "hip_flex", clamp(@k_swcomp * tilt, ~0.0 - @swcomp_lim, @swcomp_lim))
    off

  # The trunk error the servos correct (rad): with servo_pelvis (the
  # default) the PELVIS pitch against the keyframes' pelvis (x lean_scale,
  # + lean): a torso servo is fooled by the lumbar spine extending while the
  # pelvis stays pitched forward (the body folded at the hips); 0 = run_natural's
  # torso pitch against trunk_des.
  -> trunk_err(f)
    return f.torso_pitch - @trunk_des if !@servo_pelvis
    pelvis_pitch(f) - @pelvis_des

  # run_natural's correction with trunk_err in place of the torso error, the
  # world-frame swing compensation and the arms.
  -> correction(f, ctl, st, sw, phase)
    off = zeros
    lim = @corr_lim
    nlim = ~0.0 - lim
    err = trunk_err(f)
    tilt = pelvis_pitch(f) - @pelvis_ref
    if phase == :flight
      fly = clamp(~0.0 - @fly_kp * err - @fly_kd * f.torso_pitch_rate, nlim, lim)
      joint_offset(off, st + "hip_flex", fly)
      late = f.t - @t_phase - @t_fly
      late = ~0.0 if late < ~0.0
      place = @cv * (@v_f - @v_des) + @comp * tilt - @retract * late
      joint_offset(off, sw + "hip_flex", clamp(place, nlim, lim))
      placement(off, f, sw)
    else
      joint_offset(off, st + "hip_flex", torso_servo(f, ctl, st, sw))
      joint_offset(off, sw + "hip_flex", clamp(@comp * tilt, nlim, lim))
      low = @z_err
      low = ~0.0 if low < ~0.0
      joint_offset(off, st + "knee", clamp(~0.0 - @k_zk * low, nlim, ~0.0))
    swing_comp(off, f, sw, @pelvis_ref)
    arms(off, f)

  -> torso_servo(f, ctl, st, sw)
    j = st + "hip_flex"
    free = q_of(f, j) + @hip_lead * qd_of(f, j) - pair_angle(ctl.command.values, j)
    pd = ~0.0 - @torso_kp * trunk_err(f) - @torso_kd * f.torso_pitch_rate - @k_swc * servo_error(f, ctl, st_swing(sw))
    @w_hip * free + clamp(pd, ~0.0 - @corr_lim, @corr_lim)

  -> st_swing(sw)
    sw + "hip_flex"

  # Task-space placement of the landing foot (flight): x_des ahead of the COM.
  -> placement(off, f, sw)
    return off if @k_cp <= ~0.0
    z = f.at("com_pos", 2)
    z = ~0.3 if z < ~0.3
    x_des = @cp_gain * f.com_vx * Math.sqrt(z / ~9.81) + @cp_x
    behind = x_des - (f.at(sw + "foot_pos", 0) - f.com_x)
    joint_offset(off, sw + "hip_flex", clamp(@k_cp * behind, ~0.0 - @corr_lim, @corr_lim))
    off

  # ---- per tick -------------------------------------------------------------------------

  -> after(frame, ctl)
    if @blk != nil
      idx = @push_front
      idx = @push_rear if @blk == "rear_exit"
      g = @g_push
      idx.each ->(m) ctl.set_gain(m, g)
      if @blk == "block_exit"
        gs = @g_swext
        @swing_ext.each ->(m) ctl.set_gain(m, gs)
      return self
    gait_gains(frame, ctl)

  # The speed plan ramps from v0 at the rear push at `accel` m/s^2 to `speed`
  # (run_natural's): the Raibert placement term cv (v - v_des) does not throw
  # the early feet far behind a body that cannot yet accelerate like Bolt.
  -> before(frame, ctl)
    @t_now = frame.t
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    @v_des = @v0
    @v_des = @v0 + @accel * (frame.t - @t_go) if @t_go >= ~0.0
    @v_des = @speed if @v_des > @speed
    @z_err = @z_step - frame.pelvis_height
    scale_drives
    self

  # ---- the stride machinery (copied from RunNaturalSkill, run_natural.w) -------------------

  -> read_params
    @via = true
    @via = @params["via"] > ~0.5 if @params.key?("via")
    @via_fly = false
    @via_fly = @params["via_fly"] > ~0.5 if @params.key?("via_fly")
    # the speed plan's top speed (m/s; a params-file setting)
    @speed = ~5.5
    @speed = @params["speed"] if @params.key?("speed")
    @eases = [:min_jerk, :linear, :sine_in_out, :cubic_in, :cubic_out, :quint_in_out, :cubic_in_out, :expo_out]
    @v0 = param("v0", ~1.0, ~0.0, ~2.5)
    @accel = param("accel", ~1.5, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.15, ~0.02, ~0.5)
    # max-velocity keyframe command offsets (deg): command = reference + offset
    @off = {}
    ["td", "ms", "to"].each ->(kf)
      ["st", "sw"].each ->(role)
        ["hip", "knee", "ankle"].each ->(j)
          nm = "d_" + kf + "_" + role + "_" + j
          lim = ~40.0
          lim = ~60.0 if j == "hip"
          @off[nm] = param(nm, ~0.0, ~0.0 - lim, lim)
    @d_spine = param("d_spine", ~0.0, ~-15.0, ~20.0)
    @stiff_st = param("stiff_st", ~0.2, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.08, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.1, ~0.0, ~0.35)
    @t_load = param("t_load", ~0.08, ~0.03, ~0.3)
    @t_drive = param("t_drive", ~0.12, ~0.03, ~0.3)
    @t_fly = param("t_fly", ~0.09, ~0.03, ~0.35)
    @ease_load = :min_jerk
    @ease_drive = :min_jerk
    @ease_fly = :min_jerk
    @ease_load = easing("ease_load") if !@via
    @ease_drive = easing("ease_drive") if !@via
    @ease_fly = easing("ease_fly") if !@via_fly
    @d_ms = param("d_ms", ~0.02, ~-0.02, ~0.15)
    @t_ms_min = param("t_ms_min", ~0.06, ~0.04, ~0.14)
    @t_ms_max = param("t_ms_max", ~0.18, ~0.06, ~0.3)
    @t_drive_max = param("t_drive_max", ~0.25, ~0.08, ~0.35)
    @leg_kp = param("leg_kp", ~6.0, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.37, ~0.05, ~0.6)
    @bi_gain = param("bi_gain", ~1.3, ~0.0, ~1.5)
    @up_kp = param("up_kp", ~6.0, ~2.0, ~12.0)
    @up_kd = param("up_kd", ~0.25, ~0.05, ~0.6)
    @g_st = param("g_st", ~0.75, ~0.4, ~2.0)
    @g_sw = param("g_sw", ~0.65, ~0.2, ~1.5)
    @g_kl = param("g_kl", ~0.8, ~0.2, ~1.8)
    @g_al = param("g_al", ~0.95, ~0.2, ~1.8)
    @g_swk = param("g_swk", @g_sw, ~0.2, ~1.5)
    @drv_knee = param("drv_knee", ~0.7, ~0.0, ~1.0)
    @drv_ankle = param("drv_ankle", ~0.3, ~0.0, ~1.0)
    @drv_gas = param("drv_gas", ~0.9, ~0.0, ~1.0)
    @drv_hip = param("drv_hip", ~0.33, ~0.0, ~1.0)
    @drv_ham = param("drv_ham", ~0.5, ~0.0, ~1.0)
    @pre_knee = param("pre_knee", ~0.3, ~0.0, ~0.8)
    @pre_ankle = param("pre_ankle", ~0.1, ~0.0, ~0.8)
    @drv_swh = param("drv_swh", ~0.2, ~0.0, ~0.8)
    @drv_swk = param("drv_swk", ~0.5, ~0.0, ~0.8)
    @drv_rf = param("drv_rf", ~0.7, ~0.0, ~1.0)
    @drv_pre = param("drv_pre", ~0.05, ~0.0, ~0.6)
    @drv_floor = param("drv_floor", ~0.15, ~0.0, ~1.0)
    @drv_tuck = param("drv_tuck", ~0.0, ~0.0, ~0.8)
    @drv_lift = param("drv_lift", ~0.0, ~0.0, ~0.8)
    @drv_pre_ank = param("drv_pre_ank", ~0.0, ~0.0, ~0.6)
    @k_vd = param("k_vd", ~0.4, ~0.0, ~1.0)
    @z_ref = param("z_ref", ~0.9, ~0.8, ~1.0)
    @k_z = param("k_z", ~0.0, ~0.0, ~12.0)
    @k_zk = param("k_zk", ~0.0, ~0.0, ~6.0)
    @z_err = ~0.0
    @w_hip = param("w_hip", ~1.0, ~0.0, ~1.0)
    @hip_lead = param("hip_lead", ~0.12, ~0.0, ~0.2)
    @torso_kp = param("torso_kp", ~0.3, ~0.0, ~3.0)
    @torso_kd = param("torso_kd", ~0.45, ~0.0, ~0.8)
    @k_swc = param("k_swc", ~0.5, ~0.0, ~1.5)
    @fly_kp = param("fly_kp", ~0.75, ~0.0, ~2.0)
    @fly_kd = param("fly_kd", ~0.25, ~0.0, ~0.5)
    @comp = param("comp", ~0.8, ~0.0, ~1.0)
    @cv = param("cv", ~0.1, ~0.0, ~0.4)
    @retract = param("retract", ~2.0, ~0.0, ~6.0)
    @corr_lim = param("corr_lim", ~0.25, ~0.05, ~0.5)
    @spring = param("spring", ~0.06, ~0.01, ~0.2)
    @lean = param("lean", ~0.0, ~-8.0, ~20.0)
    @pelvis_ref = ~0.0524
    @trunk_des = ~0.12
    self

  -> easing(nm)
    k = param(nm, ~0.5, ~0.0, ~7.999).floor
    k = 0 if k < 0
    k = 7 if k > 7
    @eases[k]

  -> setup_reflexes(ctl)
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    ctl.reflex.set_gains(body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"]), @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    ctl.reflex.set_gains(body.mask(["spine", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @up_kp, @up_kd)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle", side + "toe", side + "rf", side + "ham", side + "gas"])
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "gas", side + "toe"])
    self

  -> aim(ch, kf)
    ch.pose(kf.pose)

  -> styled(ch, ease, via)
    ch.ease(ease)
    ch.via if via
    ch

  # Touchdown -> mid-stance: the landing leg yields while the swing heel
  # tucks; ends when the COM passes d_ms ahead of the stance foot.
  -> load_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "load", @t_load), goal)
    styled(ch, @ease_load, @via)
    mid = Latch.test("mid:" + st, ->(f, e, c) f.com_x - f.at(st + "foot_pos", 0) > @d_ms)
    ch.hold_until(mid.after_min(@t_ms_min), @t_ms_max)
    ch.drive(drive_vec([st + "knee_neg", @pre_knee, st + "ankle_pos", @pre_ankle, sw + "knee_pos", @drv_tuck]))
    ch.correct(->(f, c) correction(f, c, st, sw, :stance), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :load))
    ch

  # Mid-stance -> toe-off: the push-off burst, the alternate knee drives up;
  # ends when the stance foot leaves the ground.
  -> drive_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "drive", @t_drive), goal)
    styled(ch, @ease_drive, @via)
    off = Latch.release(st + "foot")
    ch.hold_until(off.after_min(~0.03), @t_drive_max)
    ch.drive(push_drive(st, sw))
    ch.correct(->(f, c) correction(f, c, st, sw, :stance), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :drive))
    ch

  # Toe-off -> the other leg's touchdown: `st` folds, `sw` reaches for its
  # landing; ends on `sw`'s foot contact.
  -> flight_chunk(st, sw, goal, from)
    ch = aim(Chunk.new(st + "flight", @t_fly), goal)
    styled(ch, @ease_fly, @via_fly)
    touch = Latch.contact(sw + "foot")
    ch.hold_until(touch.after_min(~0.03), ~0.45)
    ch.drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, st + "rf", @drv_rf, sw + "knee_neg", @drv_pre,
                        sw + "ankle_pos", @drv_pre_ank, sw + "gas", @drv_pre_ank]))
    ch.correct(->(f, c) correction(f, c, st, sw, :flight), @spring)
    ch.on_enter(->(f, c) enter(f, st, sw, :flight))
    ch

  -> enter(f, st, sw, phase)
    @st = st
    @sw = sw
    @phase = phase
    @t_phase = f.t
    self

  # Per-leg reflex gains: the stance hip firm, the loading knee and ankle
  # softer, the swing leg loose; in flight the landing leg is the firm one.
  -> gait_gains(frame, ctl)
    return self if @phase == nil
    firm = @st
    loose = @sw
    soft = @phase == :load
    if @phase == :flight
      firm = @sw
      loose = @st
      soft = true
    g_kl = @g_st
    g_al = @g_st
    if soft
      g_kl = @g_kl
      g_al = @g_al
    gs = @g_st
    gw = @g_sw
    @hip_idx[firm].each ->(m) ctl.set_gain(m, gs)
    @knee_idx[firm].each ->(m) ctl.set_gain(m, g_kl)
    @ankle_idx[firm].each ->(m) ctl.set_gain(m, g_al)
    @leg_idx[loose].each ->(m) ctl.set_gain(m, gw)
    gk = @g_swk
    @knee_idx[loose].each ->(m) ctl.set_gain(m, gk)
    self

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))

  -> push_drive(st, sw)
    d = drive_vec([sw + "hip_flex_pos", @drv_lift])
    @drives.push([d, index_or(st + "knee_neg"), index_or(st + "ankle_pos"), index_or(st + "gas"),
                  index_or(st + "hip_flex_neg"), index_or(st + "ham")])
    d

  -> index_or(name)
    return body.index(name) if body.has?(name)
    -1

  # The push-off burst grows with the speed plan and the speed deficit; the
  # knee and ankle extensors add the hop-height term.
  -> scale_drives
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @speed, ~0.0, ~1.0)
    s = clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)
    h = @k_z * @z_err
    vals = [@drv_knee * s + h, @drv_ankle * s + h, @drv_gas * s + h, @drv_hip * s, @drv_ham * s]
    @drives.each ->(e)
      d = e[0]
      k = 0
      while k < 5
        d[e[k + 1]] = clamp(vals[k], ~0.0, ~1.0) if e[k + 1] >= 0
        k += 1
    self

  -> drive_vec(pairs)
    d = zeros
    i = 0
    while i < pairs.size
      d[body.index(pairs[i])] = pairs[i + 1] if body.has?(pairs[i])
      i += 2
    d

  -> servo_error(f, ctl, joint)
    pair_angle(ctl.target, joint) - q_of(f, joint)

  -> pair_angle(values, joint)
    p = body.index(joint + "_pos")
    n = body.index(joint + "_neg")
    (body.muscle(p).angle_at(values[p]) + body.muscle(n).angle_at(values[n])) * ~0.5

  -> q_of(f, joint)
    f.q(body, joint)

  -> qd_of(f, joint)
    f.qd(body, joint)

# A keyframe posture: joint angles (radians) with per-joint co-contraction
# (RunNaturalKeyframe's authored-keyframe half).
+ SprintKeyframe
  ro :name
  ro :joints
  ro :angles
  ro :stiff
  -> new(@name)
    @joints = []
    @angles = []
    @stiff = []
    @stance = "r_"

  -> stance
    @stance

  -> set_stance(side)
    @stance = side
    self

  -> set(joint, q, s)
    @joints.push(joint)
    @angles.push(q)
    @stiff.push(s)
    self

  -> pose
    p = Pose.new
    i = 0
    while i < @joints.size
      p.set(@joints[i], @angles[i], @stiff[i])
      i += 1
    p
