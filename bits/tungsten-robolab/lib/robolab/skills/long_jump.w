# Long jump: approach run, penultimate-step lowering, take-off on the board,
# flight (hang, tuck, reach), landing with the legs forward in the sand, then
# recovery to a crouch or a sit.
#
# One track of chunks drives every muscle (st = stance side, sw = swing):
#
#   stand ──(0.5 s)──> lean ──(COM ahead of the ankles)──> l_push (first)
#   approach loop (a SIMBICON-style run, three chunks per step):
#     l_push ──(release l_foot)──> l_flight ──(contact r_foot)──> r_land
#     r_land ──(COM rising, or past r_foot)──> r_push ──(release)──> r_flight
#     r_flight ──(contact l_foot)──> l_land ──> l_push ...
#   take-off ("pop", use_penult 0, the practised mode): the right touchdown
#   from which the next left step lands less than pn_gap_max behind the foul
#   line marks the penultimate stride, which is run with the gait's own
#   chunks plus corrections (the right knee sinks, the left leg reaches long
#   and straight for the board); the left stance that lands within
#   to_window of the foul line is the take-off:
#       l_land (board contact, soft knee) ──(COM rising or past the foot)──>
#       takeoff (the push becomes a drive of the left hip, knee and ankle
#       extensors; free knee and opposite arm punch up; trunk held upright)
#   (use_penult 1 runs dedicated penult / penult_push / plant / to_land
#   chunks instead: a lowered penultimate stance and a long plant)
#       ──(left toe and heel off the ground)──> hang (legs hang, arms up)
#       ──(sand within tk_tau s on the ballistic arc)──> tuck (knees gathered)
#       ──(sand within rc_tau s)──> reach (legs forward)
#       ──(sand contact)──> absorb (deep crouch, soft) ──> sit
#
# Real-time corrections (spring-eased every tick):
#   torso      in stance the stance hip is a world-frame torso servo (its
#              target is the measured hip angle, led by its velocity, minus a
#              PD on trunk pitch, minus the swing hip's servo error: SIMBICON's
#              tau_st = -tau_torso - tau_swing); in flight the trailing leg is
#              the reaction mass of the same servo. The last stride and the
#              take-off hold the trunk at their own upright targets.
#   placement  the swing thigh is held in world frame in stance and lands at
#              psi_v * v (Raibert's neutral point) + cv * (v - v_des), where
#              v_des ramps v0 -> v_top; the leg keeps retracting after reach.
#   board      the penultimate decision reads the distance-to-board sensor and
#              predicts the next step from the last step of the same foot;
#              optional steering (steer_k) stretches or shortens earlier
#              strides toward a parity-correct count, and the plant step can
#              stretch toward the aim (pl_steer). The practised run uses its
#              natural stride and a measured run-up instead (a check mark).
#   clearance  a withdrawal reflex lifts a swinging toe that drops too low.
#   air        the whole body's angular momentum is fixed in flight: legs
#              sweeping back and arms coming down rotate the trunk backward
#              against the forward rotation from the board (the hang); the
#              reach aims the legs in world frame.
#   landing    while the COM is behind the heels the trunk flexes and the
#              arms reach forward; once past them, trunk and hips resist a
#              forward somersault.
# Reflex gains are set per leg and phase: soft landing knee and ankle, firm
# stance hip and push, loose swing leg, a stiff take-off leg.
#
# The approach gait follows RunSkill (lib/robolab/skills/run.w: SIMBICON
# chunks, Raibert placement, speed plan, per-phase gains, retraction, toe
# clearance), copied here so the two skills evolve independently; its
# practised parameters seeded this skill's practice.
#
# On the v2 anatomy (biarticular rectus femoris, hamstrings, gastrocnemius and
# toe joints; playground/tasks/long_jump_v2.py) the same chunks also drive the
# biarticulars and the toe flexors (toe-off) at push and take-off, the
# biarticulars get their own reflex gain, and the board contact can be made a
# strut (pop_board_knee, pop_land_k). With pop_commit the left touchdown after
# a penultimate stride is always the take-off. The take-off chunk announces
# itself to the task (`jump:takeoff`), so a jump that falls short of the sand
# is measured rather than mistaken for a running stride. Every v2-only feature
# defaults to off, so the v1 practised set reproduces unchanged.
#
# A start within a metre of the board runs the standing long jump instead
# (countermovement, arm swing, rock forward, drive, then the same flight);
# that program is an early milestone and is not practised for the final body.

+ LongJumpSkill < Skill
  -> start(frame, ctl)
    read_params
    @v_f = ~0.0
    @v_des = ~0.0
    @t_go = ~-1.0
    @torso_des = @lean
    @tkp = @torso_kp
    @tkd = @torso_kd
    @drives = []
    @phase = nil
    @t_phase = ~0.0
    @st = "l_"
    @sw = "r_"
    @prev_chunk = ""
    @touch = []
    @touch_t = []
    @debug = params.key?("debug")
    # (the v2 anatomy adds toe joints and the biarticular rf, ham and gas; on
    # the base body these prefixes match nothing)
    legs = body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe",
                      "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(legs, @leg_kp, @leg_kd)
    # v2 bodies: the biarticulars' stretch reflexes couple joints (a yielding
    # knee stretches the rectus femoris, whose reflex then flexes the hip), so
    # they get their own reflex gain (idea from run.w)
    biart = body.mask(["l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"])
    ctl.reflex.set_gains(biart, @leg_kp * @bi_gain, @leg_kd * @bi_gain)
    @leg_idx = {}
    @hip_idx = {}
    @knee_idx = {}
    @ankle_idx = {}
    ["l_", "r_"].each ->(side)
      @leg_idx[side] = body.mask([side + "hip", side + "knee", side + "ankle", side + "toe", side + "rf", side + "ham", side + "gas"])
      @hip_idx[side] = body.mask([side + "hip", side + "rf", side + "ham"])
      @knee_idx[side] = body.mask([side + "knee"])
      @ankle_idx[side] = body.mask([side + "ankle", side + "toe", side + "gas"])
    standing = standing_program
    running = running_program
    mv = running
    mv = standing if frame.has?("board") && frame.get("board") < ~1.0
    ctl.add_track(Track.new("body", mv, body.all))

  -> read_params
    # speed plan
    @v_top = param("v_top", ~3.8, ~2.5, ~7.0)
    @v0 = param("v0", ~1.0, ~0.0, ~2.5)
    @accel = param("accel", ~1.2, ~0.4, ~4.0)
    @v_tau = param("v_tau", ~0.15, ~0.02, ~0.5)
    # torso
    @lean = param("lean", ~0.15, ~-0.1, ~0.4)
    @lean_acc = param("lean_acc", ~0.2, ~0.0, ~0.6)
    @spine = param("spine", ~0.15, ~-0.2, ~0.4)
    @torso_kp = param("torso_kp", ~1.5, ~0.3, ~3.0)
    @torso_kd = param("torso_kd", ~0.3, ~0.05, ~0.5)
    @hip_lead = param("hip_lead", ~0.02, ~0.0, ~0.12)
    @k_swc = param("k_swc", ~0.6, ~0.0, ~1.5)
    @k_fly = param("k_fly", ~0.8, ~0.0, ~1.5)
    @clear_h = param("clear_h", ~0.16, ~0.08, ~0.3)
    @k_clear = param("k_clear", ~0.0, ~0.0, ~12.0)
    @retract = param("retract", ~0.0, ~0.0, ~6.0)
    @comp_fly = param("comp_fly", ~0.7, ~0.0, ~1.0)
    @k_fly_d = param("k_fly_d", ~0.22, ~0.0, ~0.4)
    @phi_nom = @lean - @spine
    # stance leg
    @d_push = param("d_push", ~0.3, ~-0.2, ~0.4)
    @vz_push = param("vz_push", ~0.0, ~-0.4, ~0.4)
    @t_absorb = param("t_absorb", ~0.04, ~0.0, ~0.15)
    @k_land = param("k_land", ~0.5, ~0.2, ~0.9)
    @a_land = param("a_land", ~0.1, ~-0.3, ~0.5)
    @k_push = param("k_push", ~0.15, ~0.0, ~0.5)
    @a_push = param("a_push", ~0.6, ~0.2, ~0.9)
    @psi_ms = param("psi_ms", ~0.1, ~-0.3, ~0.5)
    @psi_to = param("psi_to", ~-0.4, ~-0.8, ~0.0)
    @drv_knee = param("drv_knee", ~0.4, ~0.0, ~1.0)
    @drv_ankle = param("drv_ankle", ~0.5, ~0.0, ~1.0)
    @drv_hip = param("drv_hip", ~0.1, ~0.0, ~0.8)
    @pre_knee = param("pre_knee", ~0.0, ~0.0, ~0.5)
    @drv_swh = param("drv_swh", ~0.0, ~0.0, ~0.8)
    @drv_swk = param("drv_swk", ~0.0, ~0.0, ~0.8)
    @drv_pre = param("drv_pre", ~0.0, ~0.0, ~0.6)
    @k_vd = param("k_vd", ~0.0, ~0.0, ~1.0)
    @drv_floor = param("drv_floor", ~0.3, ~0.0, ~1.0)
    # v2 anatomy only: push drives on the biarticulars and the toe flexors
    @drv_gas = param("drv_gas", ~0.0, ~0.0, ~1.0)
    @drv_ham = param("drv_ham", ~0.0, ~0.0, ~1.0)
    @drv_toe = param("drv_toe", ~0.0, ~0.0, ~1.0)
    @toe_push = param("toe_push", ~0.0, ~-0.8, ~0.4)
    @bi_gain = param("bi_gain", ~1.0, ~0.1, ~1.5)
    # swing leg
    @psi_fo = param("psi_fo", ~0.3, ~-0.3, ~0.9)
    @k_fo = param("k_fo", ~1.6, ~0.6, ~2.4)
    @a_fo = param("a_fo", ~0.2, ~-0.3, ~0.8)
    @psi_mid = param("psi_mid", ~0.8, ~0.3, ~1.3)
    @k_mid = param("k_mid", ~1.9, ~0.8, ~2.4)
    @psi_late = param("psi_late", ~0.8, ~0.3, ~1.3)
    @k_late = param("k_late", ~1.3, ~0.3, ~2.2)
    @psi_reach = param("psi_reach", ~0.05, ~-0.3, ~0.6)
    @psi_v = param("psi_v", ~0.1, ~0.0, ~0.25)
    @cv = param("cv", ~0.1, ~0.0, ~0.4)
    @k_reach = param("k_reach", ~0.35, ~0.1, ~0.8)
    @a_reach = param("a_reach", ~0.2, ~-0.3, ~0.6)
    # arms
    @arm = param("arm", ~1.2, ~0.2, ~1.8)
    @elbow = param("elbow", ~1.2, ~0.3, ~2.2)
    # timing (easing durations of the chunks) and servo
    @t_land = param("t_land", ~0.06, ~0.01, ~0.25)
    @t_push = param("t_push", ~0.1, ~0.03, ~0.25)
    @t_flight = param("t_flight", ~0.12, ~0.03, ~0.35)
    @stiff = param("stiff", ~0.05, ~0.0, ~0.3)
    @stiff_st = param("stiff_st", ~0.1, ~0.0, ~0.35)
    @stiff_sw = param("stiff_sw", ~0.05, ~0.0, ~0.35)
    @stiff_up = param("stiff_up", ~0.1, ~0.0, ~0.35)
    @g_st = param("g_st", ~1.0, ~0.4, ~2.0)
    @g_sw = param("g_sw", ~0.8, ~0.2, ~1.5)
    @g_kl = param("g_kl", ~0.5, ~0.1, ~1.5)
    @g_al = param("g_al", ~0.7, ~0.1, ~1.5)
    @leg_kp = param("leg_kp", ~6.0, ~3.0, ~12.0)
    @leg_kd = param("leg_kd", ~0.3, ~0.05, ~0.6)
    # correction spring time for the stride and take-off chunks (the stand
    # chunk states 0.08; before the SDK began retiming springs per chunk,
    # 0.08 was in force throughout, which is what the practised set assumes)
    @spring = param("gait_spring", ~0.08, ~0.01, ~0.15)
    # standing start
    @d_go = param("d_go", ~0.15, ~0.0, ~0.3)
    @drv0_knee = param("drv0_knee", ~0.0, ~0.0, ~1.0)
    @drv0_ankle = param("drv0_ankle", ~0.5, ~0.0, ~1.0)
    @drv0_hip = param("drv0_hip", ~0.2, ~0.0, ~1.0)
    @psi0 = param("psi0", ~0.6, ~0.2, ~1.2)
    @k0 = param("k0", ~0.9, ~0.3, ~2.3)
    # final approach and take-off posture
    @fin_d = param("fin_d", ~1.0, ~0.3, ~8.0)
    @fin_lean = param("fin_lean", ~0.1, ~-0.1, ~0.6)
    @pn_lean = param("pn_lean", ~0.05, ~-0.2, ~0.5)
    @pn_tkp = param("pn_tkp", ~1.5, ~0.0, ~4.0)
    @pn_tkd = param("pn_tkd", ~0.3, ~0.0, ~0.6)
    @to_trunk = param("to_trunk", ~0.0, ~-0.3, ~0.4)
    @to_stiff = param("to_stiff", ~1.3, ~0.5, ~3.0)
    @tl_d = param("tl_d", ~0.0, ~-0.3, ~0.4)
    @tl_vz = param("tl_vz", ~0.0, ~-0.6, ~0.6)
    # steering onto the board
    @steer_k = param("steer_k", ~0.5, ~0.0, ~1.5)
    @pn_gap_max = param("pn_gap_max", ~0.7, ~0.2, ~1.5)
    @pl_steer = param("pl_steer", ~0.3, ~0.0, ~1.0)
    @pl_margin = param("pl_margin", ~-0.4, ~-0.8, ~0.3)
    # take-off mode: 1 = penultimate lowering + plant chunks; 0 = "pop" (the
    # run continues onto the board and the board stance's push is replaced)
    @use_penult = param("use_penult", ~1.0, ~0.0, ~1.0)
    @jump = param("jump", ~1.0, ~0.0, ~1.0)
    @to_window = param("to_window", ~0.9, ~0.3, ~1.6)
    @pop_step = false
    @pop_next = false
    @pop_lower = param("pop_lower", ~0.0, ~0.0, ~0.6)
    @pop_reach = param("pop_reach", ~0.0, ~0.0, ~0.6)
    @pop_knee = param("pop_knee", ~0.0, ~0.0, ~0.8)
    @pop_steer = param("pop_steer", ~0.0, ~0.0, ~1.0)
    @pop_land_k = param("pop_land_k", ~1.0, ~0.3, ~4.0)
    @pop_board_knee = param("pop_board_knee", ~0.0, ~0.0, ~1.2)
    @pop_swing_knee = param("pop_swing_knee", ~0.0, ~0.0, ~1.5)
    @pop_sw_k = param("pop_sw_k", ~-1.0, ~-1.0, ~1.2)
    @pop_pre = param("pop_pre", ~0.0, ~0.0, ~1.0)
    @pop_commit = param("pop_commit", ~0.0, ~0.0, ~1.0)
    @plant_gap = ~0.0
    @board_aim = param("board_aim", ~0.08, ~0.0, ~0.3)
    self

  # ---- per-tick state ----------------------------------------------------------

  -> before(frame, ctl)
    k = ctl.dt / (@v_tau + ctl.dt)
    @v_f = @v_f + (frame.com_vx - @v_f) * k
    if @t_go >= ~0.0
      @v_des = @v0 + @accel * (frame.t - @t_go)
      @v_des = @v_top if @v_des > @v_top
    # sprinters lean into the acceleration and rise as they reach speed
    @torso_des = @lean + @lean_acc * (~1.0 - @v_des / @v_top)
    @tkp = @torso_kp
    @tkd = @torso_kd
    # the final approach runs tall: lean and trunk servo blend toward the
    # take-off posture over the last fin_d metres
    if @t_go >= ~0.0 && frame.has?("board")
      w = clamp(~1.0 - frame.get("board") / @fin_d, ~0.0, ~1.0)
      @torso_des = @torso_des + (@fin_lean - @torso_des) * w
      @tkp = @torso_kp + (@pn_tkp - @torso_kp) * w
      @tkd = @torso_kd + (@pn_tkd - @torso_kd) * w
    if @phase == :pland || @phase == :penult || @phase == :plant || @phase == :to_land || @pop_next
      @torso_des = @pn_lean
      @tkp = @pn_tkp
      @tkd = @pn_tkd
    scale_drives
    self

  -> mark_go(frame)
    @t_go = frame.t

  # Every stride chunk announces its roles on entry: which leg is loaded
  # (firm: stance, or the landing leg in flight) and which swings (loose).
  -> enter(f, st, sw, phase)
    @st = st
    @sw = sw
    @phase = phase
    @t_phase = f.t
    self

  # The take-off chunk announces itself to the task (`jump:takeoff`), which
  # uses it to tell a jump that falls short of the sand from a running stride.
  -> takeoff_entered(f, ctl)
    ctl.emit("jump:takeoff")
    enter(f, "l_", "r_", :takeoff)

  -> start_stride(f, st, sw)
    mark_go(f)
    enter(f, st, sw, :push)

  -> after(frame, ctl)
    route(frame, ctl)
    leg_gains(ctl)
    pop_drive(ctl) if @pop_next && @pop_pre > ~0.0
    self

  # Pop mode, the flight onto the board: knee extensors of the take-off leg
  # pre-activate so the knee meets the board straight and stiff.
  -> pop_drive(ctl)
    return self if @phase != :flight || @sw != "l_"
    ["l_knee_neg", "l_rf"].each ->(nm)
      ctl.add_drive(body.index(nm), @pop_pre) if body.has?(nm)
    self

  # Per-leg reflex gains. Rigid tendons store no energy, so the stance leg's
  # compliance has to come from the reflexes: the landing leg's knee and ankle
  # run at low gain (a soft spring the load flexes) from late flight through
  # the land chunk, the hip stays firm for the torso servo, the push stiffens
  # the whole leg, the swing leg is loose, and the take-off leg is stiffest.
  -> leg_gains(ctl)
    return self if @phase == nil || @phase == :air
    firm = @st
    loose = @sw
    soft = @phase == :land || @phase == :pland || @phase == :to_land
    if @phase == :flight || @phase == :plant
      firm = @sw
      loose = @st
      soft = true
    g_hip = @g_st
    g_kl = @g_st
    g_al = @g_st
    if soft
      g_kl = @g_kl
      g_al = @g_al
    if @phase == :takeoff
      g_hip = @g_st * @to_stiff
      g_kl = g_hip
      g_al = g_hip
    if @pop_step && @phase == :land
      # pop mode: the board contact itself (the take-off leg's landing)
      g_kl = g_kl * @pop_land_k
      g_al = g_al * @pop_land_k
    @hip_idx[firm].each -> ctl.set_gain(item, g_hip)
    @knee_idx[firm].each -> ctl.set_gain(item, g_kl)
    @ankle_idx[firm].each -> ctl.set_gain(item, g_al)
    @leg_idx[loose].each -> ctl.set_gain(item, @g_sw)
    self

  # ---- chunk routing -------------------------------------------------------------

  # The stride loop is l_flight .. l_push; l_push falls through to penult in
  # the chunk list, so route it back to l_flight. A left flight ends on a
  # right touchdown: that stance becomes the penultimate one when one more
  # step reaches the board with the left foot.
  -> route(frame, ctl)
    tr = ctl.track("body")
    name = tr.chunk_name
    return self if name == @prev_chunk
    if name == "l_land" || name == "r_land" || name == "takeoff"
      @touch.push(lead_toe_x(frame))
      @touch_t.push(frame.t)
    if name == "r_land" && @prev_chunk == "l_flight" && @debug
      dr = frame.at("board", 2)
      lt = lead_toe_x(frame)
      nt = @touch_t.size
      ns = next_step_estimate
      ctl.emit("dbg:r_land:t=[frame.t]:d=[dr]:s=[stride_estimate]:next=[ns]:toe=[lt]:n=[nt]")
    if name == "penult" && @prev_chunk == "l_push" && !@pop_step
      tr.jump(ctl, frame, "l_flight")
    elsif @jump < ~0.5
      # run-through (practice of the approach alone): never take off
      @pop_step = false
    elsif name == "r_land" && @prev_chunk == "l_flight" && @use_penult > ~0.5 && penult_now?(frame)
      tr.jump(ctl, frame, "penult")
    elsif name == "r_land" && @prev_chunk == "l_flight" && @use_penult <= ~0.5
      # pop mode: this right stance is the penultimate one when the next left
      # step reaches the board; it is lowered and the left leg plants long
      # (spring-eased corrections on the gait's own chunks, see stride_correction)
      @pop_next = penult_now?(frame)
    elsif name == "l_land" && @use_penult <= ~0.5 && !@pop_step && (lead_toe_x(frame) > frame.at("board", 3) - @to_window || (@pop_next && @pop_commit > ~0.5))
      # "pop" take-off: this left stance, landed within to_window of the
      # foul line (or, with pop_commit, the one after a penultimate stride:
      # the athlete is committed), is the take-off step; its push becomes
      # the take-off
      @pop_step = true
      @pop_next = false
    elsif name == "l_push" && @pop_step
      tr.jump(ctl, frame, "takeoff")
    @prev_chunk = tr.chunk_name
    self

  # This right touchdown is the penultimate one when one natural step would
  # put the left toe less than pn_gap_max behind the foul line (a legal,
  # close take-off; a foul is far worse than a few centimetres lost). The
  # gap is remembered: the plant step stretches or shortens toward the aim.
  -> penult_now?(frame)
    gap = frame.at("board", 3) - lead_toe_x(frame) - next_step_estimate
    @plant_gap = gap
    gap < @pn_gap_max

  # Mean step length: half the last stride (touchdown to touchdown of the
  # same foot), or speed times a nominal step time before there is one.
  -> stride_estimate
    n = @touch.size
    return clamp(@v_f * ~0.3, ~0.5, ~2.2) if n < 3
    clamp((@touch[n - 1] - @touch[n - 3]) * ~0.5, ~0.5, ~2.2)

  # Length of the step about to be taken from the current touchdown: the
  # previous step of the same kind (from this foot to the other), since a
  # gait's left and right steps need not be equal.
  -> next_step_estimate
    n = @touch.size
    return stride_estimate if n < 3
    clamp(@touch[n - 2] - @touch[n - 3], ~0.5, ~2.4)

  # ---- the running long jump ------------------------------------------------------

  -> running_program
    mv = Movement.new("long_jump")
    mv.add(stand_chunk)
    mv.add(lean_chunk)
    mv.add(push_chunk("l_", "r_", true))
    mv.add(flight_chunk("l_", "r_"))
    mv.add(land_chunk("r_", "l_"))
    mv.add(push_chunk("r_", "l_", false))
    mv.add(flight_chunk("r_", "l_"))
    mv.add(land_chunk("l_", "r_"))
    mv.add(push_chunk("l_", "r_", false))
    add_takeoff(mv)
    add_flight(mv)
    mv

  # Quiet stance while the reflexes settle; the ankles hold the COM just
  # ahead of the ankle joints (the stand skill's ankle strategy).
  -> stand_chunk
    p = Pose.new
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", ~0.05, @stiff)
      p.set(s + "knee", ~0.12, @stiff)
      p.set(s + "ankle", ~-0.05, @stiff)
      p.set(s + "shoulder_flex", ~0.0, @stiff)
      p.set(s + "elbow", @elbow, @stiff)
    p.set("spine_flex", @spine, @stiff)
    Chunk.new("stand", ~0.3).pose(p).hold_until(Latch.after(~0.5))
      .correct(->(f, c) balance(f, ~0.05), ~0.08)

  # Tip the whole body forward: the ankle strategy's COM target moves out
  # toward the toes and the trunk leans, until the COM is ahead of the ankles
  # by d_go and the first push starts.
  -> lean_chunk
    p = Pose.new
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", ~0.1, @stiff)
      p.set(s + "knee", ~0.2, @stiff)
      p.set(s + "ankle", ~-0.2, @stiff)
    p.set("spine_flex", @spine + ~0.15, @stiff)
    p.set("l_shoulder_flex", ~-0.3, @stiff)
    p.set("r_shoulder_flex", ~0.3, @stiff)
    ahead = Latch.test("com_ahead", ->(f, e, c) f.com_x - feet_x(f) > @d_go)
    Chunk.new("lean", ~0.4).pose(p).hold_until(ahead.after_min(~0.1), ~1.5)
      .correct(->(f, c) balance(f, @d_go + ~0.1), ~0.08)

  # Stance, early: land on the forefoot and yield into the knee spring.
  -> land_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_ms + @phi_nom, @k_land, @a_land, @stiff_st)
    leg(p, sw, @psi_mid + @phi_nom, @k_mid, ~-0.1, @stiff_sw)
    upper(p, st, sw)
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("over:" + st, ->(f, e, c) f.com_x - f.at(st + "foot_pos", 0) > @d_push)
    Chunk.new(st + "land", @t_land).pose(p)
      .hold_until(Latch.any([rising, over]).after_min(@t_absorb), ~0.3)
      .drive(drive_vec([st + "knee_neg", @pre_knee]))
      .correct(->(f, c) stride_correction(f, c, st, sw, :land), @spring)
      .on_enter(->(f, c) enter(f, st, sw, :land))

  # Stance, late: push off (knee extensors and plantarflexors burst).
  -> push_chunk(st, sw, first)
    p = Pose.new
    leg(p, st, @psi_to + @phi_nom, @k_push, @a_push, @stiff_st)
    p.set(st + "toe", @toe_push, @stiff_st)
    leg(p, sw, @psi_late + @phi_nom, @k_late, ~0.0, @stiff_sw)
    upper(p, st, sw)
    off = Latch.release(st + "foot")
    if first
      p.set(sw + "hip_flex", @psi0 + @phi_nom, @stiff_sw)
      p.set(sw + "knee", @k0, @stiff_sw)
      # TODO: bound to a local first: the parser attaches a leading-dot
      # continuation after `return X` to the return statement, not to X.
      ch = Chunk.new(st + "push", ~0.25).pose(p)
        .hold_until(off.after_min(~0.15), ~0.6)
        .drive(drive_vec([st + "knee_neg", @drv0_knee, st + "ankle_pos", @drv0_ankle, st + "hip_flex_neg", @drv0_hip]))
        .correct(->(f, c) stride_correction(f, c, st, sw, :push), @spring)
        .on_enter(->(f, c) start_stride(f, st, sw))
      return ch
    Chunk.new(st + "push", @t_push).pose(p)
      .hold_until(off.after_min(~0.03), ~0.3)
      .drive(push_drive(st))
      .correct(->(f, c) stride_correction(f, c, st, sw, :push), @spring)
      .on_enter(->(f, c) enter(f, st, sw, :push))

  # Flight after `st` pushed off: `st` folds and follows through, `sw` reaches
  # for its landing angle.
  -> flight_chunk(st, sw)
    p = Pose.new
    leg(p, st, @psi_fo + @phi_nom, @k_fo, @a_fo, @stiff_sw)
    leg(p, sw, @psi_reach + @phi_nom, @k_reach, @a_reach, @stiff_st)
    upper(p, st, sw)
    # swing initiation (hip and knee flexors of the leg that just left the
    # ground) and pre-landing extensor activity on the leg about to land
    Chunk.new(st + "flight", @t_flight).pose(p)
      .hold_until(Latch.contact(sw + "foot").after_min(~0.03), ~0.45)
      .drive(drive_vec([st + "hip_flex_pos", @drv_swh, st + "knee_pos", @drv_swk, sw + "knee_neg", @drv_pre]))
      .correct(->(f, c) stride_correction(f, c, st, sw, :flight), @spring)
      .on_enter(->(f, c) enter(f, st, sw, :flight))

  -> leg(p, side, hip, knee, ankle, stiff)
    p.set(side + "hip_flex", hip, stiff)
    p.set(side + "knee", knee, stiff)
    p.set(side + "ankle", ankle, stiff)
    p

  # Arms swing against the legs: the stance-side arm comes forward while the
  # stance leg sweeps back.
  -> upper(p, st, sw)
    p.set(st + "shoulder_flex", @arm, @stiff_up)
    p.set(sw + "shoulder_flex", ~0.0 - @arm * ~0.7, @stiff_up)
    p.set(st + "elbow", @elbow, @stiff_up)
    p.set(sw + "elbow", @elbow, @stiff_up)
    p.set("spine_flex", @spine, @stiff_up)
    p

  # The push-off burst grows with the speed plan and with the speed deficit
  # (thrust feedback); the skill owns the drive arrays and rescales them every
  # tick (see `before`).
  # On the v2 anatomy the push also drives the biarticular gastrocnemius and
  # hamstrings and the toe flexors (toe-off); the base body has none of them.
  -> push_drive(st)
    pairs = [st + "knee_neg", @drv_knee, st + "ankle_pos", @drv_ankle, st + "hip_flex_neg", @drv_hip,
             st + "gas", @drv_gas, st + "ham", @drv_ham, st + "toe_pos", @drv_toe]
    d = drive_vec(pairs)
    @drives.push([d, pairs])
    d

  -> scale_drives
    s = @drv_floor + (~1.0 - @drv_floor) * clamp(@v_des / @v_top, ~0.0, ~1.0)
    s = clamp(s + @k_vd * (@v_des - @v_f), ~0.0, ~1.6)
    @drives.each ->(e)
      d = e[0]
      pairs = e[1]
      i = 0
      while i < pairs.size
        d[body.index(pairs[i])] = pairs[i + 1] * s if body.has?(pairs[i])
        i += 2
    self

  # ---- penultimate step and take-off -------------------------------------------------

  -> add_takeoff(mv)
    # penultimate stride: the gait's own right land/push chunks, lowered (a
    # deeper knee in stance), flatter (a gentler push) and with the trunk
    # rising; the left leg swings through high to reach long for the board
    p = Pose.new
    leg(p, "r_", @psi_ms + @phi_nom, param("pn_knee", ~0.65, ~0.2, ~1.3), @a_land, @stiff_st)
    leg(p, "l_", @psi_mid + @phi_nom, @k_mid, ~-0.1, @stiff_sw)
    upper(p, "r_", "l_")
    rising = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @vz_push)
    over = Latch.test("over:r_", ->(f, e, c) f.com_x - f.at("r_foot_pos", 0) > @d_push)
    mv.add(Chunk.new("penult", @t_land).pose(p)
      .hold_until(Latch.any([rising, over]).after_min(@t_absorb), ~0.3)
      .correct(->(f, c) stride_correction(f, c, "r_", "l_", :land), @spring)
      .on_enter(->(f, c) enter(f, "r_", "l_", :pland)))
    q = Pose.new
    leg(q, "r_", param("pn_hip", ~-0.4, ~-0.8, ~0.2) + @phi_nom, @k_push, param("pn_ank", ~0.5, ~-0.2, ~0.9), @stiff_st)
    leg(q, "l_", param("pn_sw_hip", ~0.95, ~0.3, ~1.6) + @phi_nom, param("pn_sw_knee", ~1.0, ~0.2, ~2.2), ~0.0, @stiff_sw)
    upper(q, "r_", "l_")
    pn_d = param("pn_drive", ~0.7, ~0.0, ~1.5)
    mv.add(Chunk.new("penult_push", param("pn_dur", ~0.1, ~0.03, ~0.3)).pose(q)
      .hold_until(foot_lifted("r_").after_min(~0.03), ~0.35)
      .drive(drive_vec(["r_knee_neg", @drv_knee * pn_d, "r_ankle_pos", @drv_ankle * pn_d, "r_hip_flex_neg", @drv_hip * pn_d]))
      .correct(->(f, c) stride_correction(f, c, "r_", "l_", :push), @spring)
      .on_enter(->(f, c) enter(f, "r_", "l_", :penult)))
    # plant: the left leg reaches long and nearly straight for the board
    r = Pose.new
    leg(r, "l_", param("pl_hip", ~0.45, ~-0.2, ~1.2) + @phi_nom, param("pl_knee", ~0.12, ~-0.02, ~0.6),
        param("pl_ank", ~0.05, ~-0.4, ~0.5), @stiff_st)
    leg(r, "r_", @psi_fo + @phi_nom, @k_fo, @a_fo, @stiff_sw)
    upper(r, "r_", "l_")
    mv.add(Chunk.new("plant", param("pl_dur", ~0.1, ~0.03, ~0.3)).pose(r)
      .hold_until(planted("l_").after_min(~0.03), ~0.45)
      .correct(->(f, c) stride_correction(f, c, "r_", "l_", :plant), @spring)
      .on_enter(->(f, c) enter(f, "r_", "l_", :plant)))
    # board contact, early: the left leg lands and yields like a running
    # stance (soft knee and ankle) while the trunk is held upright; ends when
    # the COM rises or passes the foot, then the take-off push begins
    b = Pose.new
    leg(b, "l_", @psi_ms + @phi_nom, param("tl_knee", ~0.4, ~0.05, ~1.0), param("tl_ank", ~0.1, ~-0.3, ~0.6), @stiff_st)
    leg(b, "r_", param("tl_free_hip", ~0.9, ~0.0, ~1.8) + @phi_nom, @k_mid, ~-0.1, @stiff_sw)
    upper(b, "l_", "r_")
    rise = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @tl_vz)
    past = Latch.test("over:l_", ->(f, e, c) f.com_x - f.at("l_foot_pos", 0) > @tl_d)
    mv.add(Chunk.new("to_land", param("tl_dur", ~0.05, ~0.01, ~0.2)).pose(b)
      .hold_until(Latch.any([rise, past]).after_min(param("tl_min", ~0.02, ~0.0, ~0.12)), ~0.25)
      .correct(->(f, c) takeoff_correction(f, c), @spring)
      .on_enter(->(f, c) enter(f, "l_", "r_", :to_land)))
    # take-off: vault over the planted leg and drive it straight; the free
    # (right) knee and the opposite arm punch up
    t = Pose.new
    leg(t, "l_", param("to_hip", ~-0.25, ~-0.6, ~0.4), param("to_knee", ~0.05, ~-0.02, ~0.7),
        param("to_ank", ~0.7, ~0.0, ~0.9), @stiff_st)
    leg(t, "r_", param("to_free_hip", ~1.6, ~0.6, ~2.2), param("to_free_knee", ~1.4, ~0.3, ~2.4), ~0.0, @stiff_sw)
    t.set("l_shoulder_flex", param("to_arm_l", ~2.3, ~0.0, ~3.1), @stiff_up)
    t.set("r_shoulder_flex", param("to_arm_r", ~0.3, ~-1.0, ~3.1), @stiff_up)
    t.set("l_elbow", ~0.4, @stiff_up)
    t.set("r_elbow", ~0.8, @stiff_up)
    t.set("spine_flex", param("to_spine", ~-0.05, ~-0.4, ~0.5), @stiff_up)
    to_d = param("to_drive", ~0.6, ~0.0, ~1.0)
    fr_d = param("to_free_drive", ~0.5, ~0.0, ~1.0)
    # v2 anatomy: toe-off (toe flexors press as the heel rises), take-off
    # drive on gastrocnemius and hamstrings, rectus femoris on the free leg
    t.set("l_toe", param("to_toe_q", ~0.0, ~-0.8, ~0.4), @stiff_st)
    to_gas = param("to_gas", ~0.0, ~0.0, ~1.0)
    to_ham = param("to_ham", ~0.0, ~0.0, ~1.0)
    to_toe = param("to_toe", ~0.0, ~0.0, ~1.0)
    to_rf = param("to_free_rf", ~0.0, ~0.0, ~1.0)
    mv.add(Chunk.new("takeoff", param("to_dur", ~0.12, ~0.04, ~0.3)).pose(t).ease(:cubic_out)
      .drive(drive_vec(["l_hip_flex_neg", to_d, "l_ankle_pos", to_d, "l_knee_neg", to_d, "r_hip_flex_pos", fr_d,
                        "l_gas", to_gas, "l_ham", to_ham, "l_toe_pos", to_toe, "r_rf", to_rf]))
      .hold_until(foot_lifted("l_").after_min(~0.05), ~0.35)
      .correct(->(f, c) takeoff_correction(f, c), @spring)
      .on_enter(->(f, c) takeoff_entered(f, c)))
    mv

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

  # ---- the standing long jump (start at the board) --------------------------------

  -> standing_program
    st = @stiff
    mv = Movement.new("standing_long_jump")
    ready = sym_pose(~0.05, ~0.12, ~-0.05, ~0.08, ~0.1, ~0.4, st)
    wind = sym_pose(param("sw_hip", ~1.0, ~0.4, ~2.0), param("sw_knee", ~1.0, ~0.5, ~2.2),
                    param("sw_ankle", ~-0.35, ~-0.6, ~0.2), param("sw_spine", ~0.5, ~0.0, ~1.0),
                    param("sw_sh", ~-0.9, ~-1.0, ~0.5), ~0.3, st)
    rock = sym_pose(param("sk_hip", ~1.2, ~0.4, ~2.0), param("sk_knee", ~1.2, ~0.5, ~2.2),
                    param("sk_ankle", ~-0.55, ~-0.6, ~0.2), param("sk_spine", ~0.6, ~0.0, ~1.0),
                    param("sk_sh", ~-0.3, ~-1.0, ~1.5), ~0.3, st)
    drive = sym_pose(param("sd_hip", ~-0.2, ~-0.5, ~0.6), param("sd_knee", ~0.0, ~-0.02, ~0.6),
                     param("sd_ankle", ~0.85, ~0.0, ~0.9), param("sd_spine", ~0.1, ~-0.3, ~0.8),
                     param("sd_sh", ~2.6, ~0.5, ~3.1), ~0.2, st)
    d_act = param("sd_act", ~0.6, ~0.0, ~1.0)
    d_arm = param("sd_arm", ~0.6, ~0.0, ~1.0)
    push = sym_drive([["hip_flex_neg", d_act], ["knee_neg", d_act], ["ankle_pos", d_act], ["shoulder_flex_pos", d_arm]])
    mv.add(Chunk.new("ready", ~0.3).pose(ready).hold_until(Latch.after(~0.5)))
    mv.add(Chunk.new("wind", param("sw_dur", ~0.45, ~0.2, ~1.0)).pose(wind))
    mv.add(Chunk.new("rock", param("sk_dur", ~0.3, ~0.1, ~0.8)).pose(rock)
      .hold_until(com_ahead_of_toes(param("sk_lean", ~0.0, ~-0.15, ~0.25)), ~0.8))
    mv.add(Chunk.new("drive", param("sd_dur", ~0.2, ~0.08, ~0.5)).pose(drive).drive(push).ease(:cubic_out)
      .gain(param("sd_gain", ~1.0, ~0.2, ~3.0))
      .hold_until(airborne.after_min(~0.08), ~0.6)
      .on_enter(->(f, c) c.emit("jump:takeoff")))
    add_flight(mv)
    mv

  # ---- corrections ----------------------------------------------------------------------

  # Offsets for one tick of a stride chunk (phase :land, :push, :flight or
  # :plant). In stance the stance hip servoes the torso and the swing hip
  # holds its thigh angle in world frame (pelvis pitch compensated). In flight
  # nothing anchors the pelvis, and compensating it would be positive feedback
  # (a backward-pitching pelvis would swing the legs back, pitching it
  # further), so the landing leg is placed partly in pelvis frame (comp_fly)
  # and the trailing leg becomes the reaction mass of a torso servo.
  -> stride_correction(f, ctl, st, sw, phase)
    off = zeros
    place = @psi_v * @v_f + @cv * (@v_f - @v_des)
    if phase == :flight || phase == :plant
      fly = ~0.0 - @k_fly * (f.torso_pitch - @torso_des) - @k_fly_d * f.torso_pitch_rate
      joint_offset(off, st + "hip_flex", fly)
      ret = ~0.0
      if phase == :flight
        # swing-leg retraction: once the reach pose is reached the landing leg
        # keeps sweeping back, so the foot meets the ground moving backward
        late = f.t - @t_phase - @t_flight
        late = ~0.0 if late < ~0.0
        ret = ~0.0 - @retract * late
        place = place + steer(f, st)
      else
        place = @psi_v * @v_f + @pl_steer * clamp(@plant_gap - @board_aim, ~-0.5, ~0.8)
      joint_offset(off, sw + "hip_flex", place + ret + @comp_fly * (pelvis_pitch(f) - @phi_nom))
      toe_clearance(f, off, st)
      if @pop_next && sw == "l_" && @pop_sw_k >= ~0.0
        joint_offset(off, "l_knee", @pop_sw_k - @k_reach)
      if @pop_next && sw == "l_"
        # the flight onto the board: the take-off leg reaches long and straight,
        # stretched or shortened toward the aim (the gap the penultimate
        # decision measured: + = the natural step would land short of it)
        aim = @pop_steer * clamp(@plant_gap - @board_aim, ~-0.5, ~0.8)
        joint_offset(off, "l_hip_flex", @pop_reach + aim)
        joint_offset(off, "l_knee", ~0.0 - @pop_knee)
      return off
    comp = pelvis_pitch(f) - @phi_nom
    torso = torso_servo(f, ctl, st + "hip_flex") - @k_swc * servo_error(f, ctl, sw + "hip_flex")
    joint_offset(off, st + "hip_flex", torso)
    place = ~0.0 if phase == :land
    joint_offset(off, sw + "hip_flex", comp + place)
    toe_clearance(f, off, sw)
    # the penultimate stance (pop mode) sinks: extra knee flexion lowers the hips
    joint_offset(off, st + "knee", @pop_lower) if @pop_next && st == "r_"
    if @pop_next && sw == "l_"
      # meanwhile the take-off leg opens its knee early (a knee needs time to
      # extend), so it can reach the board nearly straight (the flight chunk
      # then drives it to pop_sw_k)
      joint_offset(off, "l_knee", ~0.0 - @pop_swing_knee)
    # the board contact (pop mode) is a strut, not a running stance: a
    # straighter knee target (with pop_land_k's stiffer reflexes) makes the
    # body vault over the planted foot, turning run-up speed upward
    joint_offset(off, st + "knee", ~0.0 - @pop_board_knee) if @pop_step && st == "l_" && phase == :land
    off

  # Toe clearance, a withdrawal reflex on the swinging leg: when its ankle
  # drops below `clear_h` the knee flexes and the ankle dorsiflexes in
  # proportion, lifting the toe before it drags.
  -> toe_clearance(f, off, side)
    low = @clear_h - f.at(side + "foot_pos", 2)
    return off if low <= ~0.0
    joint_offset(off, side + "knee", @k_clear * low)
    joint_offset(off, side + "ankle", ~0.0 - @k_clear * low)
    off

  # Servo error of a joint (last commanded target angle minus measured angle),
  # proportional to the torque its muscles are producing.
  -> servo_error(f, ctl, joint)
    tg = ctl.target
    p = body.pos_index(joint)
    n = body.neg_index(joint)
    qa = body.muscle(p).angle_at(tg[p])
    qb = body.muscle(n).angle_at(tg[n])
    (qa + qb) * ~0.5 - f.joint_angle(body, joint)

  # World-frame stance hip: hold the measured angle (led by its velocity) and
  # add a PD on torso pitch, so the hip's torque answers only to the torso.
  -> torso_servo(f, ctl, joint)
    q = f.joint_angle(body, joint)
    qd = f.joint_rate(body, joint)
    qc = ctl.command.joint_angle(body, joint)
    err = f.torso_pitch - @torso_des
    q + @hip_lead * qd - qc - @tkp * err - @tkd * f.torso_pitch_rate

  # Take-off: keep the trunk near to_trunk over the vaulting leg.
  -> takeoff_correction(f, ctl)
    off = zeros
    err = f.torso_pitch - @to_trunk
    joint_offset(off, "l_hip_flex", ~0.0 - @pn_tkp * err - @pn_tkd * f.torso_pitch_rate)
    off

  # In the air the whole body's angular momentum is fixed, so the trunk's
  # forward rotation (from the vault over the board) is managed by moving the
  # limbs: sweeping the legs back and bringing the arms down from overhead
  # both rotate the trunk backward (the hang). u grows with the trunk's excess
  # forward pitch and pitch rate. In the reach the legs are left to swing
  # forward, aimed in world frame (rc_comp compensates the pelvis pitch).
  -> air_correction(f, phase)
    off = zeros
    u = @k_air * (f.torso_pitch - @air_pitch) + @kd_air * f.torso_pitch_rate
    if phase == :hang
      joint_offset(off, "l_hip_flex", ~0.0 - u)
      joint_offset(off, "r_hip_flex", ~0.0 - u)
    else
      joint_offset(off, "l_hip_flex", @rc_comp * pelvis_pitch(f))
      joint_offset(off, "r_hip_flex", @rc_comp * pelvis_pitch(f))
    joint_offset(off, "l_shoulder_flex", ~0.0 - @k_air_arm * u)
    joint_offset(off, "r_shoulder_flex", ~0.0 - @k_air_arm * u)
    off

  # After touchdown: while the COM is still behind the heels, flex the trunk
  # and throw the arms forward (more the further behind), so the body pivots
  # over the feet instead of sitting back into the sand; once it has passed
  # them and the trunk pitches forward fast, extend trunk and hips against
  # the rotation so the landing ends kneeling or sitting, not somersaulting.
  -> landing_correction(f)
    heel = f.at("toes", 4)
    heel = f.at("toes", 6) if f.at("toes", 6) < heel
    behind = clamp(heel - f.com_x, ~0.0, ~0.6)
    tip = @ab_k2 * clamp(f.torso_pitch - ~0.6, ~0.0, ~1.0) + @ab_kd2 * clamp(f.torso_pitch_rate, ~0.0, ~6.0)
    off = zeros
    joint_offset(off, "spine_flex", @ab_k * behind - tip)
    joint_offset(off, "l_hip_flex", ~0.0 - tip)
    joint_offset(off, "r_hip_flex", ~0.0 - tip)
    joint_offset(off, "l_shoulder_flex", ~2.0 * @ab_k * behind)
    joint_offset(off, "r_shoulder_flex", ~2.0 * @ab_k * behind)
    off

  # Stride-length adjustment toward the board, as a swing-hip angle (0 far
  # away). `st` is the side of the last touchdown: the left toe must land on
  # the aim point after an even number of steps from a left touchdown and an
  # odd number from a right one; the remaining steps share the distance.
  -> steer(f, st)
    return ~0.0 if @steer_k <= ~0.0 || @touch.size < 2
    dist = f.at("board", 3) - @board_aim - @touch[@touch.size - 1]
    s = stride_estimate
    return ~0.0 if dist > ~7.0 || dist < ~0.3
    k = steps_to_board(dist, s, st)
    clamp(@steer_k * (dist / k - s), ~-0.25, ~0.25)

  -> steps_to_board(dist, s, st)
    k = (dist / s).round
    k = 1 if k < 1
    even = st == "l_"
    if even && k % 2 == 1
      k = k + 1
      k = k - 2 if k > 2 && (dist / (k - 2) - s).abs < (dist / k - s).abs
    if !even && k % 2 == 0
      k = k + 1
      k = k - 2 if k > 1 && (dist / (k - 2) - s).abs < (dist / k - s).abs
    k

  # Seconds until the COM falls to its landing height on a ballistic arc.
  -> time_to_land(f)
    z = f.at("com_pos", 2) - @land_z
    vz = f.at("com_vel", 2)
    return ~0.0 if z <= ~0.0
    (vz + Math.sqrt(vz * vz + ~19.62 * z)) / ~9.81

  # Ankle strategy: plantarflex when the COM is ahead of its target, dorsiflex
  # when behind.
  -> balance(f, target)
    dq = ~2.0 * (f.com_x - feet_x(f) - target) + ~0.4 * f.com_vx
    off = zeros
    joint_offset(off, "l_ankle", dq)
    joint_offset(off, "r_ankle", dq)
    off

  # ---- latches ----------------------------------------------------------------------------

  # Both feet off the ground: every toe and heel above the runway surface.
  # (Contact force alone chatters to zero for single ticks mid-push.)
  -> airborne
    Latch.test("airborne", ->(f, e, c) lowest_foot_point(f) > ~0.02)

  # A foot contact near or ahead of the centre of mass (toe no more than
  # -pl_margin behind it): the plant on the board, not a swinging toe
  # scuffing the runway far behind the body.
  -> planted(side)
    k = 0
    k = 2 if side == "r_"
    Latch.test(side + "planted", ->(f, e, c) f.get(side + "foot_contact") > ~0.05 && f.at("toes", k) > f.com_x + @pl_margin)

  -> foot_lifted(side)
    Latch.test(side + "lifted", ->(f, e, c) foot_height(f, side) > ~0.015)

  # The centre of mass has rocked forward past the leading toe by `margin`.
  -> com_ahead_of_toes(margin)
    Latch.test("com>toes", ->(f, e, c) f.com_x - lead_toe_x(f) > margin)

  # ---- sensing helpers --------------------------------------------------------------------

  -> feet_x(f)
    (f.at("l_foot_pos", 0) + f.at("r_foot_pos", 0)) * ~0.5

  -> foot_height(f, side)
    k = 0
    k = 2 if side == "r_"
    z = f.at("toes", k + 1)
    z = f.at("toes", k + 5) if f.at("toes", k + 5) < z
    z

  -> lowest_foot_point(f)
    z = foot_height(f, "l_")
    zr = foot_height(f, "r_")
    z = zr if zr < z
    z

  -> lead_toe_x(f)
    x = f.at("toes", 0)
    x = f.at("toes", 2) if f.at("toes", 2) > x
    x

  -> pelvis_pitch(f)
    Math.atan2(f.at("pelvis_up", 0), f.at("pelvis_up", 2))

  # ---- posture and drive helpers ------------------------------------------------------------

  # A left/right symmetric full-body posture.
  -> sym_pose(hip, knee, ankle, spine, sh, el, stiff)
    p = Pose.new
    ["l_", "r_"].each ->(s)
      p.set(s + "hip_flex", hip, stiff)
      p.set(s + "knee", knee, stiff)
      p.set(s + "ankle", ankle, stiff)
      p.set(s + "shoulder_flex", sh, stiff)
      p.set(s + "elbow", el, stiff)
    p.set("spine_flex", spine, stiff)
    p

  # Feed-forward activations from a flat [muscle, a, muscle, a, ...] list
  # (muscles the body does not have are skipped).
  -> drive_vec(pairs)
    d = zeros
    i = 0
    while i < pairs.size
      d[body.index(pairs[i])] = pairs[i + 1] if body.has?(pairs[i])
      i += 2
    d

  # Feed-forward activations on both sides: [[suffix, a], ...] (e.g.
  # "knee_neg" drives l_knee_neg and r_knee_neg).
  # TODO: named block params work around the compiler's nested implicit-item
  # capture bug (inside a method the inner `item` is the outer element).
  -> sym_drive(pairs)
    out = zeros
    pairs.each ->(pair)
      ["l_", "r_"].each ->(side)
        nm = side + pair[0]
        out[body.index(nm)] = pair[1] if body.has?(nm)
    out
