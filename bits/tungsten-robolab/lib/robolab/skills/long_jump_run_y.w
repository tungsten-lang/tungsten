# LongJumpRunY: the long jump on the run-up of the LABELLED BEYOND-HUMAN body's fall-reduced runner (playground/profiles/beyond.json,
# scratchpad/lj4/LOG.md). The approach is S5's chain F1 of RunGearYSkill (skills/run_geary.w: RunGearX plus the sprint-5 opt-in mechanisms,
# params/run_geary_v4_beyond_s5b.txt, frozen controller bin/challengers/run_geary-s5-final) and the jump is LongJumpRunSkill's.
#
# THIS FILE IS A COPY of skills/long_jump_run.w with ONE change: the class is `LongJumpRunYSkill < RunGearYSkill` instead of
# `LongJumpRunSkill < RunGearSkill` (the same construction as skills/long_jump_run_x.w, agent L3: a copy and not a subclass of
# LongJumpRunSkill, because subclassing a class with conditionally assigned ivars crashes the ideal take-off program in compiled
# Tungsten). long_jump_run.w, long_jump_run_x.w, run_gear.w, run_gearx.w and run_geary.w are untouched, so every existing champion replays
# unchanged. Everything below the class line is long_jump_run.w as it was built into bin/challengers/long_jump_run-c3 (md5 a40a3113),
# whose header follows.
#
# LongJumpRun: the long jump on the sprinter's run-up. The approach IS the
# runner: this skill is RunRISkill (skills/run_ri.w = RunSkill + opt-in
# reciprocal inhibition) with a take-off, a flight and a landing added, so it
# runs with whatever sprint params the runner has practised (the p95 top-speed
# champion's `params/run_ri_p95.txt`, the average body's `params/run_v3.txt`)
# and gets faster whenever the runner does. Every jump tunable is prefixed
# `j_` (search them with `--only 'j_*'`); the run's own tunables keep their
# names and meaning.
#
# One track drives every muscle. RunSkill's movement (stand -> lean -> l_push
# -> the six-chunk stride loop) gets these chunks appended, one set per
# take-off leg T (F = the free leg), so either foot can take off:
#
#   T_board   the plant: the take-off foot has landed on the board; a stiff,
#             pre-activated strut (knee near straight, high reflex gain,
#             knee and ankle extensors driven) while the COM vaults over the
#             foot and the free thigh swings through; latched on the COM
#             rising (vz > j_b_vz) or passing the foot (j_b_d), after j_b_min
#   T_takeoff the drive: full-power bursts on the take-off leg's extensors
#             (hip, vasti, soleus, gastrocnemius, hamstrings, toes) and the
#             free leg's hip flexors (with reciprocal inhibition, `ri`, the
#             antagonists stay quiet), the arms punch up; announces
#             `jump:takeoff`; latched on the take-off foot leaving the board
#   (T_hk1, T_hk2: with `j_hk 1` / `j_hk 2` the hitch-kick replaces the
#             hang and tuck: 1.5 / 2.5 running strides in the air, then reach)
#   hang      in the air: legs down and back, arms up (the hang), the arms
#             and legs servo trunk pitch against the forward rotation from
#             the board; latched on the sand being j_tk_tau s away
#   tuck      knees gathered (a short lever swings forward fast); latched on
#             the sand being j_rc_tau s away
#   reach     both legs forward for the landing, trunk folding over them
#   absorb    first sand contact: knees give, arms and trunk thrown forward
#             so the body pivots over the heels instead of sitting back
#   sit       the recovery (crouch or sit forward over the feet)
#
# Run-up planning (at every touchdown, `touchdown`): the plant step has its
# own length j_pl_step (the plant's reach changes it), so the ideal
# PENULTIMATE touchdown is j_pl_step short of the aim point (j_aim behind the
# foul line). The distance D from the touchdown toe to that point is split
# into the nearest whole number n of steps of the running average step
# length; while n + 1 <= j_st_n the next flight nudges its landing leg by
# j_st_w x (D / n - step) / leg length (capped at j_st_max m of step change)
# and scales the push (j_st_kdrv), so the last strides absorb the error (the
# visual regulation of the last 4-6 strides in real run-ups). A touchdown
# within j_win steps of that point is the PENULTIMATE: its knee sinks
# (j_pn_knee: the lowered penultimate step), its push is scaled (j_pn_drv),
# and the flight after it is the plant flight: the take-off leg reaches long
# and nearly straight for the aim (j_pl_hip, plus j_pl_w x the remaining
# error / leg length, capped at j_pl_max m; j_pl_knee), its vasti and soleus
# pre-activate (j_pl_pre), and the free leg swings through early
# (j_pl_free_*). The next touchdown of the take-off foot is the plant
# (committed). A touchdown within j_win steps of the aim that was not planned
# (the planner lost a step) takes off too.
#
# The final approach runs taller: over the last j_fin_d metres the torso
# target moves by j_fin_dlean (rad; negative = more upright) and the trunk
# servo's gains grow up to j_fin_kp times, and in the penultimate and plant
# phases the target moves by j_pn_dlean more.
#
# `j_ik 1` (a params-file switch plus the distilled ik_* knot table) replaces
# the plant flight, plant and drive with the ideal take-off program (see "the
# ideal take-off program" below). Opt-in refinements of that program, all off
# unless their params are present (defaults are bit-identical):
#   ik_from 1     the program starts at the PENULTIMATE touchdown (the task is
#                 told of the take-off at the plant touchdown, not before)
#   ik_fmin       the plant foot's contact force (body weights) that counts as
#                 its touchdown: 1.5 ignores a scuffing swing foot (< 1 BW)
#   ik_pr*, ik_kp_*, ik_kd_*, ik_fbclip, ik_fbmax
#                 rotation feedback: the torso pitch's error against the
#                 program's own average trajectory (a forward lean beyond it
#                 only, with ik_fbclip 1) times per-muscle gains
#   ik_fx*, ik_kf_*, ik_fxmax
#                 swing-foot lag feedback: the plant-side foot behind the COM
#                 by more than its average trajectory times per-muscle gains
#   ik_clz, ik_clt, ik_kc_*
#                 swing-foot clearance reflex: a toe or heel below ik_clz
#                 metres before the plant lifts the foot
# `j_il 1` adds the landing program (il_* knots on their own clock, latched on
# the first sand contact). With `il_tg` the clock before the sand is the
# BALLISTIC-TIME clock (tg minus the COM's time to fall to il_zl): the legs'
# tuck and reach are locked to the predicted landing, so a lower or shorter
# flight does not strike the sand with the legs still hanging; `il_ctau`,
# `il_clt`, `il_kc_*` add a time-to-strike reflex before the designed landing.
# Both tables are open-loop excitation programs (ORACLE-class), the residuals
# on them zero-initialised sensed feedback.
#
# `j_run 1` (a params-file switch) never takes off: the approach alone.
#
# The runner is RunGearSkill (skills/run_gear.w: RunKnot / RunRI with more gears), whose
# `gears N` params-file switch is the opt-in: without it (every params file before round 3) the
# run is RunRISkill's exactly, with `gears 2` and the g2_ twins (params/lj_runner_gear_v4_p95.txt:
# the sprint_top_speed_v4_p95 champion's runner) the stride is rebuilt from the twins above
# g2_v_on. A gear change replaces the stride's movement, so the jump's chunks go onto the new
# one (`switch_gear` below); the take-off, flight and landing are the same in every gear.

+ LongJumpRunYSkill < RunGearYSkill
  -> start(frame, ctl)
    @jump_ready = false
    @ik_rg_r = 0
    @ik_t_touch = ~0.0
    @pa_on = false
    @pa_de = []
    @pa_dc = []
    super(frame, ctl)
    @track = ctl.track("body")
    ik_tables if @ik
    il_tables if @il
    add_jump_chunks(@track.movement)
    @jump_ready = true
    @ik_on = false
    @ik_skip = false
    @pen_t = ~-1.0
    @stride = ~0.0
    @last_toe = ~-99.0
    @plan_n = 0
    @plan_step = ~0.0
    @pen = ""
    @plant = ""
    @to_side = ""
    @jumping = false
    @t_to = ~-1.0
    @nat_step = ~0.0
    self

  # The jump's chunks on a running movement: RunSkill's loop ends with l_push
  # (gait 0), which keeps looping to l_flight now that the jump's chunks follow it
  # in the list; then the take-off chunks for either foot, the ideal take-off and
  # landing programs, the flight and the landing.
  -> add_jump_chunks(mv)
    mv[mv.size - 1].followed_by("l_flight")
    takeoff_chunks(mv, "l_", "r_")
    takeoff_chunks(mv, "r_", "l_")
    if @ik
      ik_chunk(mv, "l_", "r_")
      ik_chunk(mv, "r_", "l_")
    if @il
      il_chunk(mv, "l_", "r_")
      il_chunk(mv, "r_", "l_")
    add_flight(mv)
    mv

  # A gear change (RunGearSkill#switch_gear) builds a fresh stride movement and swaps it under
  # the track: the jump's chunks go onto it before the track looks for its next chunk by name.
  # (A gear change inside the runner's own start, `gear0`, comes before the jump exists.)
  -> switch_gear(f, ctl, k)
    super(f, ctl, k)
    add_jump_chunks(@track.movement) if @jump_ready
    self

  -> read_params
    super
    @j_run = ~0.0
    @j_run = @params["j_run"] if @params.key?("j_run")
    # `j_debug 1`: emit the planner's decisions as dbg: commands (the task
    # prints them with ROBOLAB_LJ_DEBUG=1)
    @j_debug = @params.key?("j_debug")
    @board_shift = ~0.0
    @board_shift = @params["j_board_shift"] if @params.key?("j_board_shift")
    @j_ri = ~0.0
    @j_ri = @params["j_ri"] if @params.key?("j_ri")
    # planner
    @j_aim = param("j_aim", ~0.12, ~-0.8, ~0.6)
    @j_win = param("j_win", ~0.45, ~0.1, ~0.7)
    @st_n = param("j_st_n", ~5.0, ~1.0, ~10.0)
    @st_w = param("j_st_w", ~0.6, ~0.0, ~2.0)
    @st_max = param("j_st_max", ~0.2, ~0.0, ~0.5)
    @st_kdrv = param("j_st_kdrv", ~0.0, ~0.0, ~3.0)
    # round 3 (both off unless present): j_st_up caps the lengthening a nudge may ask for (m of step change,
    # the shortening keeps j_st_max), j_st_zk steers the step length through the hop height as well: the
    # gait's hop-height loop (k_z x (z_ref - pelvis height) on the stance extensors) gets its reference moved
    # by j_st_zk x the planned step change, so a longer planned step pushes harder and a shorter one softer
    @st_up = @st_max
    @st_up = param("j_st_up", @st_max, ~0.0, ~0.5) if @params.key?("j_st_up")
    @st_zk = ~0.0
    @st_zk = param("j_st_zk", ~0.0, ~0.0, ~4.0) if @params.key?("j_st_zk")
    # how the number of steps left to the penultimate touchdown is rounded (0.5 = to the nearest; toward 1.0 = up: the
    # plan shortens steps, which a nudge does, instead of lengthening them, which it does not: a forward reach makes the
    # foot touch down early and the step comes out shorter)
    @st_rnd = ~0.5
    @st_rnd = param("j_st_rnd", ~0.5, ~0.3, ~1.0) if @params.key?("j_st_rnd")
    @leg_len = param("j_leg_len", ~0.9, ~0.75, ~0.98)
    # final approach
    @fin_d = param("j_fin_d", ~6.0, ~0.5, ~20.0)
    @fin_dlean = param("j_fin_dlean", ~0.0, ~-1.3, ~0.3)
    @pn_dlean = param("j_pn_dlean", ~0.0, ~-0.6, ~0.3)
    # the trunk servo's gains grow by up to this factor over the final metres
    @fin_kp = param("j_fin_kp", ~1.0, ~1.0, ~4.0)
    @tkp0 = @torso_kp
    @tkd0 = @torso_kd
    # penultimate stance (lowered) and the plant flight
    @pn_knee = param("j_pn_knee", ~0.15, ~0.0, ~0.7)
    @pn_hip = param("j_pn_hip", ~0.0, ~-0.4, ~0.4)
    @pn_drv = param("j_pn_drv", ~1.0, ~0.3, ~1.5)
    @pl_hip = param("j_pl_hip", ~0.15, ~-0.3, ~0.7)
    @pl_step = param("j_pl_step", ~2.1, ~1.0, ~4.0)
    @plan2 = @params.key?("j_plan2") && @params["j_plan2"] > ~0.5
    @pl_extra = ~0.0
    @pl_extra = param("j_pl_extra", ~0.25, ~-0.6, ~1.0) if @plan2
    @pl_w = param("j_pl_w", ~0.5, ~0.0, ~2.0)
    @pl_max = param("j_pl_max", ~0.2, ~0.0, ~0.7)
    @pl_knee = param("j_pl_knee", ~0.2, ~0.0, ~0.8)
    @pl_ank = param("j_pl_ank", ~0.0, ~-0.4, ~0.4)
    @pl_pre = param("j_pl_pre", ~0.2, ~0.0, ~1.0)
    @pl_free_hip = param("j_pl_free_hip", ~0.2, ~0.0, ~1.2)
    @pl_free_knee = param("j_pl_free_knee", ~0.0, ~-0.5, ~1.0)
    # board (strut)
    @b_dur = param("j_b_dur", ~0.05, ~0.01, ~0.2)
    @b_min = param("j_b_min", ~0.03, ~0.0, ~0.12)
    @b_vz = param("j_b_vz", ~0.3, ~-0.5, ~1.5)
    @b_d = param("j_b_d", ~0.0, ~-0.3, ~0.4)
    @b_hip = param("j_b_hip", ~0.2, ~-0.4, ~0.8)
    @b_knee = param("j_b_knee", ~0.25, ~0.0, ~0.9)
    @b_ank = param("j_b_ank", ~0.1, ~-0.4, ~0.7)
    @b_free_hip = param("j_b_free_hip", ~1.0, ~0.0, ~2.0)
    @b_free_knee = param("j_b_free_knee", ~1.6, ~0.3, ~2.4)
    @b_drv = param("j_b_drv", ~0.4, ~0.0, ~1.0)
    @b_free_drv = param("j_b_free_drv", ~0.5, ~0.0, ~1.0)
    @g_b = param("j_g_b", ~1.5, ~0.3, ~3.0)
    # take-off drive
    @to_dur = param("j_to_dur", ~0.1, ~0.03, ~0.3)
    @to_min = param("j_to_min", ~0.03, ~0.0, ~0.12)
    @to_max = param("j_to_max", ~0.25, ~0.08, ~0.4)
    @to_hip = param("j_to_hip", ~-0.3, ~-0.8, ~0.4)
    @to_knee = param("j_to_knee", ~0.05, ~-0.02, ~0.6)
    @to_ank = param("j_to_ank", ~0.7, ~0.0, ~0.9)
    @to_toe = param("j_to_toe", ~0.0, ~-0.8, ~0.4)
    @to_free_hip = param("j_to_free_hip", ~1.6, ~0.6, ~2.2)
    @to_free_knee = param("j_to_free_knee", ~1.5, ~0.3, ~2.4)
    @to_arm_t = param("j_to_arm_t", ~2.2, ~-0.5, ~3.1)
    @to_arm_f = param("j_to_arm_f", ~0.3, ~-1.0, ~3.1)
    @to_spine = param("j_to_spine", ~0.0, ~-0.4, ~0.6)
    @to_drv = param("j_to_drv", ~1.0, ~0.0, ~1.0)
    @to_free_drv = param("j_to_free_drv", ~1.0, ~0.0, ~1.0)
    @to_arm_drv = param("j_to_arm_drv", ~0.5, ~0.0, ~1.0)
    # the other arm's drive (> 0 with j_to_arm_f high: a double-arm action)
    @to_arm2_drv = param("j_to_arm2_drv", ~0.0, ~0.0, ~1.0)
    @to_trunk = param("j_to_trunk", ~0.1, ~-0.3, ~0.6)
    @to_tkp = param("j_to_tkp", ~1.0, ~0.0, ~4.0)
    @to_tkd = param("j_to_tkd", ~0.2, ~0.0, ~0.6)
    @g_to = param("j_g_to", ~1.5, ~0.3, ~3.0)
    @g_free = param("j_g_free", ~1.0, ~0.2, ~2.0)
    @to_ease = ease_of(param("j_to_ease", ~2.0, ~0.0, ~4.49))
    # air and landing gains
    @g_air = param("j_g_air", ~0.8, ~0.2, ~2.0)
    # the ideal take-off program (`j_ik 1`: playground/long_jump_limits.py
    # distil writes it; see ik_tables)
    @ik = @params.key?("j_ik") && @params["j_ik"] > ~0.5
    @ik_g = ~0.0
    if @ik
      @ik_h = @params["ik_h"]
      @ik_n = (@params["ik_n"] + ~0.5).floor
      @ik_td = @params["ik_td"]
      @ik_g = param("j_ik_g", ~0.0, ~0.0, ~2.0)
      @ik_gap0 = ~0.0
      @ik_gap0 = @params["ik_gap0"] if @params.key?("ik_gap0")
      # program time at which the hang takes over (the program runs into the
      # early flight; default: 40 ms after the ideal touchdown, i.e. at the
      # foot's release)
      @ik_end = @ik_td + ~0.04
      @ik_end = @params["ik_end"] if @params.key?("ik_end")
      # where the program starts: the plant flight (ik_from 0) or the
      # penultimate touchdown (ik_from 1: the penultimate stance is the
      # program's too)
      @ik_at = "flight"
      @ik_at = "land" if @params.key?("ik_from") && @params["ik_from"] > ~0.5
      # the shortest penultimate stance the program starts after (s; 0 = any)
      @ik_pen_min = ~0.0
      @ik_pen_min = @params["ik_pen_min"] if @params.key?("ik_pen_min")
      @ik_kdc = param("j_ik_kdc", ~1.0, ~0.0, ~1.0)
      # the plant foot's contact force (body weights) that counts as its
      # touchdown (0.05: any touch; a swing foot's scuff stays under 1)
      @ik_fmin = ~0.05
      @ik_fmin = @params["ik_fmin"] if @params.key?("ik_fmin")
      # rotation feedback (ik_pr<k>, ik_kp_<role>, ik_kd_<role>) and the
      # swing-foot clearance reflex (ik_clz, ik_clt, ik_kc_<role>), see
      # ik_feedback; both zero / absent = the program alone
      @ik_fb = @params.key?("ik_pr0")
      # ik_fbclip 1: the pitch feedback acts on a forward lean beyond the
      # program's own average only (-1: on a backward one only; 0: both)
      @ik_fbclip = ~0.0
      @ik_fbclip = @params["ik_fbclip"] if @params.key?("ik_fbclip")
      # the pitch error is clipped to +- ik_fbmax rad (a residual, not a takeover)
      @ik_fbmax = ~9.0
      @ik_fbmax = @params["ik_fbmax"] if @params.key?("ik_fbmax")
      # swing-foot lag feedback (ik_fx<k> reference knots, ik_fxmax, ik_kf_<role>)
      @ik_fx = @params.key?("ik_fx0")
      if @ik_fx
        @ik_fxmax = ~0.3
        @ik_fxmax = @params["ik_fxmax"] if @params.key?("ik_fxmax")
      @ik_cl = @params.key?("ik_clz")
      if @ik_cl
        @ik_clz = @params["ik_clz"]
        @ik_clt = ~0.04
        @ik_clt = @params["ik_clt"] if @params.key?("ik_clt")
      # per-regime offsets after the plant touchdown (M3, agent L4; absent = the single program): ik_rg_t1 / ik_rg_t2 are touchdown-time
      # thresholds (s since the program's start; early below t1 = regime 1, late above t2 = regime 2), ik_rg_nd offset knots ik_rg_tau<k>
      # (s since the touchdown), tables ik1_de<k>_<role>, ik1_dc<k>_<role> (regime 1) and ik2_... (regime 2): see rg_offsets
      @ik_rg = @params.key?("ik_rg_t1")
      @ik_rg_t1 = ~0.0
      @ik_rg_t2 = ~9.0
      @ik_rg_nd = 0
      @ik_rg_tau = []
      if @ik_rg
        @ik_rg_t1 = @params["ik_rg_t1"]
        @ik_rg_t2 = @params["ik_rg_t2"]
        @ik_rg_nd = (@params["ik_rg_nd"] + ~0.5).floor
        @ik_rg_tau = (0...@ik_rg_nd).map ->(k) @params["ik_rg_tau" + k.to_s]
    # the landing program (`j_il 1`, playground/long_jump_limits.py landing):
    # after the take-off program, knots on its own clock latched on the sand
    @il = @ik && @params.key?("j_il") && @params["j_il"] > ~0.5
    if @il
      @il_h = @params["il_h"]
      @il_n = (@params["il_n"] + ~0.5).floor
      @il_ld = @params["il_ld"]
      @il_g = param("j_il_g", ~0.3, ~0.0, ~2.0)
      @il_lz = ~9.0
      @il_lz = @params["il_lz"] if @params.key?("il_lz")
      # the ballistic-time clock (il_tg > 0, see il_apply); il_zl: the COM height
      # the time is to (0 = j_land_z, the chunks' own)
      @il_tg = ~0.0
      @il_tg = @params["il_tg"] if @params.key?("il_tg")
      @il_zl = ~0.0
      @il_zl = @params["il_zl"] if @params.key?("il_zl")
      # the time-to-strike reflex (il_ctau, il_clt, il_kc_<role>; il_clearance)
      @il_cl = @params.key?("il_ctau")
      if @il_cl
        @il_ctau = @params["il_ctau"]
        @il_clt = ~0.10
        @il_clt = @params["il_clt"] if @params.key?("il_clt")
      @il_kdc = param("j_il_kdc", ~1.0, ~0.0, ~1.0)
    # hitch-kick (`j_hk` 1 or 2, a params-file switch; 0 = the hang); its
    # tunables are declared only when it is on
    @hk = ~0.0
    @hk = @params["j_hk"] if @params.key?("j_hk")
    @rc_tau = param("j_rc_tau", ~0.3, ~0.05, ~1.0)
    if @hk > ~0.5
      @hk_dur = param("j_hk_dur", ~0.22, ~0.08, ~0.45)
      @hk_b_hip = param("j_hk_b_hip", ~-0.3, ~-0.7, ~0.6)
      @hk_b_knee = param("j_hk_b_knee", ~0.2, ~0.0, ~1.2)
      @hk_f_hip = param("j_hk_f_hip", ~1.4, ~0.4, ~2.2)
      @hk_f_knee = param("j_hk_f_knee", ~1.9, ~0.5, ~2.5)
      @hk_ank = param("j_hk_ank", ~0.1, ~-0.5, ~0.8)
      @hk_arm_a = param("j_hk_arm_a", ~2.2, ~-1.0, ~3.1)
      @hk_arm_b = param("j_hk_arm_b", ~-0.5, ~-1.0, ~3.1)
      @hk_spine = param("j_hk_spine", ~0.1, ~-0.4, ~0.8)
      @hk_drv = param("j_hk_drv", ~0.5, ~0.0, ~1.0)
      @hk_ease = ease_of(param("j_hk_ease", ~0.0, ~0.0, ~4.49))
    # round 7 (agent L7; off unless `j_nat` 1): at toe-off the step of the flight that starts is predicted from the COM's velocity there,
    # j_nat_c0 + j_nat_cx x vx + j_nat_cz x vz (the natural step: 0.067 m of residual sd on 1410 flights of the runner H011 against 0.117 m
    # for the running average `stride`), and the planner's nudge corrects the plan against that prediction instead of against the average
    @nat_on = @params.key?("j_nat") && @params["j_nat"] > ~0.5
    @nat_c0 = ~-0.4314
    @nat_cx = ~0.2606
    @nat_cz = ~0.1702
    @nat_c0 = @params["j_nat_c0"] if @params.key?("j_nat_c0")
    @nat_cx = @params["j_nat_cx"] if @params.key?("j_nat_cx")
    @nat_cz = @params["j_nat_cz"] if @params.key?("j_nat_cz")
    self

  -> ease_of(v)
    return :min_jerk if v < ~0.5
    return :linear if v < ~1.5
    return :cubic_out if v < ~2.5
    return :sine_out if v < ~3.5
    :quint_out

  -> other(side)
    return "r_" if side == "l_"
    "l_"

  # ---- per tick ---------------------------------------------------------------

  -> before(frame, ctl)
    @last_ctl = ctl
    # the chunk this tick's track update will run (and whose drive it adds)
    @tick_chunk = @track.chunk if @track != nil
    super(frame, ctl)
    return self if !frame.has?("board")
    if !@jumping
      # the final approach runs taller (or leans more): torso target shift
      w = clamp(~1.0 - (frame.get("board") + @board_shift) / @fin_d, ~0.0, ~1.0)
      @torso_des = @torso_des + @fin_dlean * w
      @torso_kp = @tkp0 * (~1.0 + (@fin_kp - ~1.0) * w)
      @torso_kd = @tkd0 * (~1.0 + (@fin_kp - ~1.0) * w)
      @torso_des = @torso_des + @pn_dlean if @pen != ""
      route(frame, ctl)
    self

  # At the end of a flight chunk, when the landing foot touches down: the
  # planned plant (or an unplanned touchdown close enough to the aim) becomes
  # the take-off instead of a running stance.
  -> route(frame, ctl)
    return self if @j_run > ~0.5
    name = @track.chunk_name
    side = ""
    side = "r_" if name == "l_flight" && frame.get("r_foot_contact") > ~0.05
    side = "l_" if name == "r_flight" && frame.get("l_foot_contact") > ~0.05
    return self if side == ""
    return self if @track.elapsed(frame) < ~0.03
    due = side == @plant
    gap = board_x(frame) - @j_aim - toe_x(frame, side)
    due = true if @stride > ~0.0 && gap < @j_win * @stride
    if due
      @to_side = side
      @jumping = true
      @track.jump(ctl, frame, side + "board")
    self

  # Every running touchdown re-plans the steps to the board.
  -> enter(f, st, sw, phase)
    super(f, st, sw, phase)
    touchdown(f, st) if phase == :land && !@jumping
    nat_toe_off(f) if @nat_on && phase == :flight && !@jumping
    self

  # Toe-off (the flight chunk is entered): the natural step of this flight from the COM's velocity.
  -> nat_toe_off(f)
    @nat_step = @nat_c0 + @nat_cx * f.com_vx + @nat_cz * f.at("com_vel", 2)
    self

  # The step the planner's nudge corrects the plan against: the running average step, or with `j_nat` the natural step predicted at toe-off.
  -> step_ref
    return @nat_step if @nat_on && @nat_step > ~1.0
    @stride

  # The board the run-up plans against: the sensed foul line moved by the
  # check-mark shift j_board_shift (a params-file setting, m; default 0), so a
  # check mark can move (the start relative to the real board) while the
  # run-up, its planning and its final-approach blend stay exactly the same.
  -> board_x(f)
    f.at("board", 3) + @board_shift

  -> toe_x(f, side)
    return f.at("toes", 0) if side == "l_"
    f.at("toes", 2)

  -> touchdown(f, side)
    x = toe_x(f, side)
    s = x - @last_toe
    if s > ~0.5 && s < ~3.2
      @stride = s if @stride <= ~0.0
      @stride = @stride * ~0.6 + s * ~0.4
    @last_toe = x
    @plan_n = 0
    @pen = ""
    plan(f, side, x)
    if @j_debug && f.has?("board")
      d = board_x(f) - x
      @last_ctl.emit("dbg:td:[side]:t=[f.t]:gap=[d]:step=[s]:stride=[@stride]:n=[@plan_n]:plan=[@plan_step]:pen=[@pen]")
    self

  -> plan(f, side, x)
    return self if @stride <= ~0.0 || !f.has?("board") || @j_run > ~0.5
    # the plant step is its own length (j_pl_step, the reach changes it):
    # plan the running steps onto the ideal penultimate touchdown
    left = board_x(f) - @j_aim - x
    return self if left < @j_win * @stride
    to_pen = left - plant_step
    if to_pen < @j_win * @stride
      # this is the penultimate touchdown: the next one is the plant
      @plan_n = 1
      @plan_step = left
      @pen = side
      @pen_t = f.t
      @plant = other(side)
      return self
    n = (to_pen / @stride + @st_rnd).floor
    n = 1 if n < 1
    return self if n + 1 > @st_n
    @plan_n = n + 1
    @plan_step = to_pen / n
    self

  # The plant step's expected length: j_pl_step, or with `j_plan2` (a
  # params-file switch) the running average step plus j_pl_extra, so the
  # plan follows the run-up's own stride as it lengthens with speed.
  -> plant_step
    return @stride + @pl_extra if @plan2
    @pl_step

  # Gains: the jump's phases set their own, the run keeps RunSkill's.
  -> after(frame, ctl)
    return self if @phase == nil
    if @ik && !@ik_on && !@jumping && !@ik_skip && @plant != "" && @pen != "" && @track.chunk_name == @pen + @ik_at
      # a penultimate stance cut short (a bounce released the push latch
      # early; normal ones last 0.08-0.10 s) leaves the free foot at the
      # ground: the program is skipped and the gait's own take-off jumps
      if @ik_at == "flight" && frame.t - @pen_t < @ik_pen_min
        @ik_skip = true
      else
        ik_start(frame, ctl)
    if @ik_on
      if @track.chunk_name == @ik_side + "ik"
        ik_apply(frame, ctl)
        return self
      @ik_on = false
    if @phase == :il
      il_apply(frame, ctl)
      return self
    if @phase == :board || @phase == :takeoff
      g = @g_to
      g = @g_b if @phase == :board
      @leg_idx[@to_side].each -> ctl.set_gain(item, g)
      @leg_idx[other(@to_side)].each -> ctl.set_gain(item, @g_free)
      return self
    if @phase == :air
      @leg_idx["l_"].each -> ctl.set_gain(item, @g_air)
      @leg_idx["r_"].each -> ctl.set_gain(item, @g_air)
      return self
    if @phase == :landed
      return self
    super(frame, ctl)
    plant_preactivation(ctl) if @phase == :flight && @plant != "" && @sw == @plant
    self

  # The plant flight: the take-off leg's knee and ankle extensors
  # pre-activate so the leg meets the board stiff.
  -> plant_preactivation(ctl)
    return self if @pl_pre <= ~0.0
    [@plant + "knee_neg", @plant + "rf", @plant + "ankle_pos", @plant + "gas"].each ->(nm)
      ctl.add_drive(body.index(nm), @pl_pre) if body.has?(nm)
    self

  # RunSkill's corrections, plus the planner's nudges, the lowered
  # penultimate stance and the plant flight's reach.
  -> stride_correction(f, ctl, st, sw, phase)
    off = super(f, ctl, st, sw, phase)
    return off if @jumping || @plan_n == 0
    if phase == :flight
      if @plan_n == 1 && sw == @plant
        adj = clamp(@plan_step - plant_step, ~0.0 - @pl_max, @pl_max)
        joint_offset(off, sw + "hip_flex", @pl_hip + @pl_w * adj / @leg_len)
        joint_offset(off, sw + "knee", ~0.0 - @pl_knee)
        joint_offset(off, sw + "ankle", @pl_ank)
        joint_offset(off, st + "hip_flex", @pl_free_hip)
        joint_offset(off, st + "knee", @pl_free_knee)
      elsif @plan_n > 1
        adj = clamp(@plan_step - step_ref, ~0.0 - @st_max, @st_up)
        joint_offset(off, sw + "hip_flex", @st_w * adj / @leg_len)
      return off
    if st == @pen
      joint_offset(off, st + "knee", @pn_knee)
      joint_offset(off, st + "hip_flex", @pn_hip)
    off

  # RunSkill's drive scaling, then the planner's: a longer planned step
  # pushes harder, and the penultimate push by j_pn_drv.
  -> scale_drives(frame)
    if @st_zk != ~0.0 && !@jumping && @plan_n > 1 && @stride > ~0.5
      # (@z_err is recomputed every tick by RunSkill#before: the shift lasts one tick)
      @z_err = @z_err + @st_zk * clamp(@plan_step - @stride, ~0.0 - @st_max, @st_up)
    super(frame)
    return self if @jumping || @plan_n == 0 || @stride <= ~0.5
    k = ~1.0
    k = clamp(~1.0 + @st_kdrv * (@plan_step - @stride) / @stride, ~0.5, ~1.6) if @plan_n > 1
    k = @pn_drv if @pen != "" && @st == @pen
    return self if k == ~1.0
    @drives.each ->(e)
      d = e[0]
      d[e[1]] = clamp(d[e[1]] * k, ~0.0, ~1.0)
      d[e[2]] = clamp(d[e[2]] * k, ~0.0, ~1.0)
      d[e[3]] = clamp(d[e[3]] * k, ~0.0, ~1.0)
      d[e[4]] = clamp(d[e[4]] * k, ~0.0, ~1.0) if e[4] >= 0
      d[e[6]] = clamp(d[e[6]] * k, ~0.0, ~1.0) if e[6] >= 0
    self

  # ---- take-off -----------------------------------------------------------------

  -> takeoff_chunks(mv, t, fr)
    b = Pose.new
    leg(b, t, @b_hip + @phi_nom, @b_knee, @b_ank, @stiff_st)
    leg(b, fr, @b_free_hip + @phi_nom, @b_free_knee, ~-0.1, @stiff_sw)
    jump_arms(b, t, fr, @to_arm_t * ~0.5, @to_arm_f * ~0.5, @spine)
    rise = Latch.test("rising", ->(f, e, c) f.at("com_vel", 2) > @b_vz)
    past = Latch.test("past:" + t, ->(f, e, c) f.com_x - f.at(t + "foot_pos", 0) > @b_d)
    ch = mv.add(Chunk.new(t + "board", @b_dur).pose(b))
    ch.hold_until(Latch.any([rise, past]).after_min(@b_min), ~0.2)
    ch.drive(drive_vec([t + "knee_neg", @b_drv, t + "rf", @b_drv, t + "ankle_pos", @b_drv, t + "gas", @b_drv,
                        fr + "hip_flex_pos", @b_free_drv, fr + "rf", @b_free_drv]))
    ch.correct(->(f, c) takeoff_correction(f, c, t), @gait_spring)
    ch.on_enter(->(f, c) plant_entered(f, c, t, fr))
    p = Pose.new
    leg(p, t, @to_hip, @to_knee, @to_ank, @stiff_st)
    p.set(t + "toe", @to_toe, @stiff_st)
    leg(p, fr, @to_free_hip, @to_free_knee, ~0.0, @stiff_sw)
    jump_arms(p, t, fr, @to_arm_t, @to_arm_f, @to_spine)
    ch = mv.add(Chunk.new(t + "takeoff", @to_dur).pose(p).ease(@to_ease))
    ch.hold_until(Latch.release(t + "foot").after_min(@to_min), @to_max)
    ch.drive(drive_vec([t + "hip_flex_neg", @to_drv, t + "knee_neg", @to_drv, t + "ankle_pos", @to_drv, t + "gas", @to_drv,
                        t + "ham", @to_drv, t + "toe_pos", @to_drv * ~0.5,
                        fr + "hip_flex_pos", @to_free_drv, fr + "rf", @to_free_drv,
                        t + "shoulder_flex_pos", @to_arm_drv, fr + "shoulder_flex_pos", @to_arm2_drv]))
    ch.correct(->(f, c) takeoff_correction(f, c, t), @gait_spring)
    ch.on_enter(->(f, c) takeoff_entered(f, c, t, fr))
    if @hk > ~0.5
      ch.followed_by(t + "hk1")
      hitch_chunks(mv, t, fr)
    else
      ch.followed_by("hang")
    mv

  # The hitch-kick (`j_hk 1`: 1.5 strides in the air; `j_hk 2`: 2.5): the
  # legs keep running. hk1: the free leg (forward at take-off) sweeps down
  # and back nearly straight while the take-off leg folds and comes forward;
  # hk2 the other way round. Sweeping a straight leg back and recovering a
  # folded one forward stores the body's forward angular momentum in the
  # legs, so the trunk stays upright; the arms swing against the legs. Each
  # stride lasts j_hk_dur, and the reach begins as soon as the sand is
  # j_rc_tau s away.
  -> hitch_chunks(mv, t, fr)
    a = Pose.new
    leg(a, fr, @hk_b_hip, @hk_b_knee, @hk_ank, @stiff_sw)
    leg(a, t, @hk_f_hip, @hk_f_knee, @hk_ank, @stiff_sw)
    jump_arms(a, fr, t, @hk_arm_a, @hk_arm_b, @hk_spine)
    ch = mv.add(Chunk.new(t + "hk1", @hk_dur).pose(a).ease(@hk_ease))
    ch.hold_until(Latch.any([land_soon, sand_contact]), @hk_dur)
    ch.drive(drive_vec([fr + "hip_flex_neg", @hk_drv, fr + "ham", @hk_drv, t + "hip_flex_pos", @hk_drv, t + "rf", @hk_drv]))
    ch.correct(->(f, c) air_correction(f, c, :hitch), @gait_spring)
    ch.on_enter(->(f, c) enter(f, @to_side, other(@to_side), :air))
    ch.branch(->(f, c) hitch_next(f, t))
    b = Pose.new
    leg(b, t, @hk_b_hip, @hk_b_knee, @hk_ank, @stiff_sw)
    leg(b, fr, @hk_f_hip, @hk_f_knee, @hk_ank, @stiff_sw)
    jump_arms(b, t, fr, @hk_arm_a, @hk_arm_b, @hk_spine)
    ch = mv.add(Chunk.new(t + "hk2", @hk_dur).pose(b).ease(@hk_ease))
    ch.hold_until(Latch.any([land_soon, sand_contact]), @hk_dur)
    ch.drive(drive_vec([t + "hip_flex_neg", @hk_drv, t + "ham", @hk_drv, fr + "hip_flex_pos", @hk_drv, fr + "rf", @hk_drv]))
    ch.correct(->(f, c) air_correction(f, c, :hitch), @gait_spring)
    ch.followed_by("reach")
    mv

  # After the first air stride: a second one (j_hk 2) unless the sand is
  # already close; the reach otherwise.
  -> hitch_next(f, t)
    return t + "hk2" if @hk > ~1.5 && time_to_land(f) >= @rc_tau
    "reach"

  -> land_soon
    Latch.test("sand_in_tau", ->(f, e, c) time_to_land(f) < @rc_tau)

  -> sand_contact
    Latch.any([Latch.above("pit", 1, ~0.5), Latch.above("pit", 2, ~0.5).after_min(~0.15)])

  # The plant: from here on reciprocal inhibition runs at `j_ri` (a
  # params-file switch; 0/absent keeps the run's own setting), so the
  # take-off's full-power bursts are not fought by their antagonists even on
  # a runner practised without it.
  -> plant_entered(f, ctl, t, fr)
    setup_reciprocal(ctl, @j_ri) if @j_ri > ~0.0
    enter(f, t, fr, :board)

  -> takeoff_entered(f, ctl, t, fr)
    ctl.emit("jump:takeoff")
    @t_to = f.t
    enter(f, t, fr, :takeoff)

  # Arms at take-off: the take-off side's arm drives forward and up (it swings
  # with the free leg), the other arm as given; the spine as given.
  -> jump_arms(p, t, fr, arm_t, arm_f, spine)
    p.set(t + "shoulder_flex", arm_t, @stiff_up)
    p.set(fr + "shoulder_flex", arm_f, @stiff_up)
    p.set(t + "elbow", ~0.5, @stiff_up)
    p.set(fr + "elbow", @elbow, @stiff_up)
    p.set("spine_flex", spine, @stiff_up)
    p

  # On the board: the take-off hip holds the trunk near j_to_trunk.
  -> takeoff_correction(f, ctl, t)
    off = zeros
    err = f.torso_pitch - @to_trunk
    joint_offset(off, t + "hip_flex", ~0.0 - @to_tkp * err - @to_tkd * f.torso_pitch_rate)
    off

  # ---- the ideal take-off program (`j_ik 1`) --------------------------------------
  #
  # playground/long_jump_limits.py finds the take-off that ideal open-loop
  # control of all 32 muscles gets from this body's own approach state (from
  # the start of the plant flight to the take-off) and `distil` writes it as
  # knots on its own grid (every ik_h s, ik_n knots): per muscle ROLE (T_ =
  # the take-off leg's side, F_ = the free side, unsided muscles by name) the
  # contraction c, velocity v and acceleration a (quintic Hermite knots, the
  # contraction the controller senses along the ideal trajectory) and the
  # excitation e (drive knots, linear between knots), and the gap knots g: the
  # drive also gets gap_err x g(s), where gap_err is the penultimate toe's
  # distance to the foul line at the program's start minus ik_gap0 (the plant
  # step's feedback on the board). From the tick the plant
  # flight starts the program replaces the gait: every muscle's target is the
  # quintic c*(s), its drive e(s) plus j_ik_kdc x g x kd x v*(s) (so along the
  # ideal trajectory the reflex's velocity damping cancels and the activation
  # is exactly e), every reflex gain is j_ik_g (0: the ideal's open-loop
  # program exactly; > 0: feedback around it) and reciprocal inhibition is off.
  # The program clock s is latched to the plant: it waits at the ideal's
  # touchdown time ik_td until the take-off foot touches down, and is set to
  # ik_td when it touches down early. The chunk ends when that foot leaves the
  # ground (then the hang, or the hitch-kick).

  -> ik_tables
    @ik_tab = prog_tables("ik_", @ik_n, ["c", "v", "a", "e", "g"])
    if @ik_fb
      @ik_pr = (0...@ik_n).map ->(k) pget("ik_pr" + k.to_s)
      @ik_kp = role_gains("ik_kp_")
      @ik_kd = role_gains("ik_kd_")
    @ik_kc = role_gains("ik_kc_") if @ik_cl
    if @ik_fx
      @ik_fxr = (0...@ik_n).map ->(k) pget("ik_fx" + k.to_s)
      @ik_kf = role_gains("ik_kf_")
    if @ik_rg
      @ik_rgtab1 = prog_tables("ik1_", @ik_rg_nd, ["de", "dc"])
      @ik_rgtab2 = prog_tables("ik2_", @ik_rg_nd, ["de", "dc"])
    self

  # Per take-off side, a per-muscle gain vector from the params file
  # (<prefix><role>; missing entries are 0).
  -> role_gains(prefix)
    out = {}
    ["l_", "r_"].each ->(t)
      fr = other(t)
      out[t] = (0...body.size).map ->(m) pget(prefix + ik_role(body.muscle(m).name, t, fr))
    out

  -> il_tables
    @il_tab = prog_tables("il_", @il_n, ["c", "v", "a", "e"])
    # the landing's rotation feedback (a learned linear residual): a torso
    # pitch reference il_pr<k> (rad, linear between knots) and per-muscle
    # gains on the pitch error (il_kp_<role>) and the pitch rate (il_kd_<role>),
    # added to the drive; all zero = none
    @il_pr = (0...@il_n).map ->(k) pget("il_pr" + k.to_s)
    @il_kp = {}
    @il_kd = {}
    ["l_", "r_"].each ->(t)
      fr = other(t)
      @il_kp[t] = (0...body.size).map ->(m) pget("il_kp_" + ik_role(body.muscle(m).name, t, fr))
      @il_kd[t] = (0...body.size).map ->(m) pget("il_kd_" + ik_role(body.muscle(m).name, t, fr))
    @il_kc = role_gains("il_kc_") if @il_cl
    self

  -> pget(key)
    return @params[key] if @params.key?(key)
    ~0.0

  # Per take-off side, per quantity q, a knot-by-muscle table read from the
  # params file (<prefix><q><k>_<role>; missing entries are 0).
  -> prog_tables(prefix, n, qs)
    out = {}
    ["l_", "r_"].each ->(t)
      fr = other(t)
      rows = {}
      qs.each ->(q)
        rows[q] = (0...n).map ->(k) prog_row(prefix, q, k, t, fr)
      out[t] = rows
    out

  -> prog_row(prefix, q, k, t, fr)
    (0...body.size).map ->(m)
      key = prefix + q + k.to_s + "_" + ik_role(body.muscle(m).name, t, fr)
      v = ~0.0
      v = @params[key] if @params.key?(key)
      v

  -> ik_role(nm, t, fr)
    return "T_" + nm.slice(2, nm.size - 2) if nm.starts_with?(t)
    return "F_" + nm.slice(2, nm.size - 2) if nm.starts_with?(fr)
    nm

  -> ik_chunk(mv, t, fr)
    off = Latch.test("ik_off:" + t, ->(f, e, c) @ik_td_seen && ik_clock(f) > @ik_end && f.get(t + "foot_contact") <= ~0.02)
    ch = mv.add(Chunk.new(t + "ik", ~1.0))
    ch.hold_until(off, ~0.8)
    # no corrections, and a 1 ms spring: the gait's correction offsets are gone
    # by the program's second tick (the first runs without feedback)
    ch.correct(->(f, c) nil, ~0.001)
    ch.on_enter(->(f, c) ik_entered(f, c, t, fr))
    if @il
      ch.followed_by(t + "il")
    elsif @hk > ~0.5
      ch.followed_by(t + "hk1")
    else
      ch.followed_by("hang")
    mv

  # The take-off is announced (the task counts a jump that falls short of the
  # sand from here on) when the program starts at the plant flight, and only at
  # the plant's touchdown when it starts at the penultimate touchdown (ik_from
  # 1): announced earlier, the penultimate stance's own 0.17 s flight counted as
  # a take-off that landed short.
  -> ik_entered(f, ctl, t, fr)
    ctl.emit("jump:takeoff") if @ik_at == "flight"
    enter(f, t, fr, :ik)

  # The plant flight has just begun (this tick): cancel the drive the track
  # added this tick (the push chunk's: the flight chunk is entered at the end
  # of the update), hand the track to the program's hold chunk, and run it.
  -> ik_start(frame, ctl)
    drv = nil
    drv = @tick_chunk.drive_values if @tick_chunk != nil
    if drv != nil
      i = 0
      while i < body.size
        ctl.add_drive(i, ~0.0 - drv[i])
        i += 1
    setup_reciprocal(ctl, ~0.0)
    @ik_side = @plant
    @to_side = @plant
    @jumping = true
    @ik_on = true
    @ik_t0 = frame.t
    @ik_shift = ~0.0
    @ik_td_seen = false
    @ik_lifted = false
    @ik_first = true
    @ik_rg_r = 0
    @ik_t_touch = ~0.0
    # the plant step's feedback on the board: where the penultimate toe is
    # (board - toe) against the program's reference ik_gap0
    @ik_gap_err = frame.at("board", 3) - toe_x(frame, @pen) - @ik_gap0
    if @j_debug
      bx = frame.at("board", 3)
      tx = toe_x(frame, @pen)
      ctl.emit("dbg:ikgap:[@pen]:[bx]:[tx]:[@ik_gap0]:[@ik_gap_err]")
    @track.jump(ctl, frame, @plant + "ik")
    self

  -> ik_clock(f)
    f.t - @ik_t0 + @ik_shift

  -> ik_apply(frame, ctl)
    t = @ik_side
    s = ik_clock(frame)
    if !@ik_td_seen
      down = frame.get(t + "foot_contact") > @ik_fmin
      @ik_lifted = true if !down
      if down && @ik_lifted && s > ~0.03
        @ik_td_seen = true
        ctl.emit("jump:takeoff") if @ik_at == "land"
        if @ik_rg
          # the measured touchdown time (s since the program's start) picks the regime
          real = frame.t - @ik_t0
          @ik_rg_r = 1 if real < @ik_rg_t1
          @ik_rg_r = 2 if real > @ik_rg_t2
          @ik_t_touch = frame.t
        @ik_shift = @ik_shift + @ik_td - s
        s = @ik_td
      elsif s > @ik_td
        # late: hold the program at the ideal's touchdown until the plant
        @ik_shift = @ik_shift - (s - @ik_td)
        s = @ik_td
    g = @ik_g
    g = ~0.0 if @ik_first
    @ik_first = false
    @pa_on = false
    rg_offsets(frame, t) if @ik_rg_r > 0
    prog_apply(ctl, @ik_tab[t], @ik_h, @ik_n, s, g, @ik_kdc, @ik_gap_err, true)
    @pa_on = false
    ik_feedback(frame, ctl, t, s) if @ik_fb || @ik_cl || @ik_fx
    self

  # The regime's offsets at tau seconds after the plant touchdown, linear between the knots ik_rg_tau and held after the last one: a
  # per-muscle drive offset (@pa_de) and a per-muscle target-contraction offset (@pa_dc) that prog_apply adds when @pa_on.
  -> rg_offsets(frame, t)
    tab = @ik_rgtab1[t]
    tab = @ik_rgtab2[t] if @ik_rg_r == 2
    tau = frame.t - @ik_t_touch
    j = 0
    while j < @ik_rg_nd - 2 && tau > @ik_rg_tau[j + 1]
      j += 1
    u = clamp((tau - @ik_rg_tau[j]) / (@ik_rg_tau[j + 1] - @ik_rg_tau[j]), ~0.0, ~1.0)
    de0 = tab["de"][j]
    de1 = tab["de"][j + 1]
    dc0 = tab["dc"][j]
    dc1 = tab["dc"][j + 1]
    @pa_de = (0...body.size).map ->(m) de0[m] + (de1[m] - de0[m]) * u
    @pa_dc = (0...body.size).map ->(m) dc0[m] + (dc1[m] - dc0[m]) * u
    @pa_on = true
    self

  # Residuals on the take-off program, learned around it (zero = none).
  # Rotation: the torso pitch's error against the reference knots ik_pr<k> and
  # its rate, times per-muscle gains, added to the drive. Clearance: before the
  # plant (the program is still more than ik_clt s before its ideal
  # touchdown), the lower of the plant foot's toe and heel below ik_clz metres
  # adds per-muscle gain x (ik_clz - height) to the drive: a swing foot
  # dragging along the runway lifts (a scuff there tips the whole take-off).
  -> ik_feedback(frame, ctl, t, s)
    if @ik_fb
      j = (s / @ik_h).floor
      j = 0 if j < 0
      j = @ik_n - 2 if j > @ik_n - 2
      u = clamp((s - @ik_h * j) / @ik_h, ~0.0, ~1.0)
      err = frame.torso_pitch - (@ik_pr[j] + (@ik_pr[j + 1] - @ik_pr[j]) * u)
      err = ~0.0 if @ik_fbclip > ~0.5 && err < ~0.0
      err = ~0.0 if @ik_fbclip < ~-0.5 && err > ~0.0
      err = @ik_fbmax if err > @ik_fbmax
      err = ~0.0 - @ik_fbmax if err < ~0.0 - @ik_fbmax
      rate = frame.torso_pitch_rate
      kp = @ik_kp[t]
      kd = @ik_kd[t]
      m = 0
      while m < body.size
        ctl.add_drive(m, kp[m] * err + kd[m] * rate)
        m += 1
    if @ik_fx && !@ik_td_seen
      # swing-foot lag: the plant-side foot behind the COM by more than the
      # program's own average trajectory (ik_fx knots), per-muscle gain x the lag
      j = (s / @ik_h).floor
      j = 0 if j < 0
      j = @ik_n - 2 if j > @ik_n - 2
      u = clamp((s - @ik_h * j) / @ik_h, ~0.0, ~1.0)
      fxp = frame.at(t + "foot_pos", 0)
      lag = @ik_fxr[j] + (@ik_fxr[j + 1] - @ik_fxr[j]) * u - (fxp - frame.at("com_pos", 0))
      lag = ~0.0 if lag < ~0.0
      lag = @ik_fxmax if lag > @ik_fxmax
      if lag > ~0.0
        kf = @ik_kf[t]
        m = 0
        while m < body.size
          ctl.add_drive(m, kf[m] * lag)
          m += 1
    if @ik_cl && !@ik_td_seen && s < @ik_td - @ik_clt
      zi = 1
      zh = 5
      if t == "r_"
        zi = 3
        zh = 7
      z = frame.at("toes", zi)
      z = frame.at("toes", zh) if frame.at("toes", zh) < z
      if z < @ik_clz
        e = @ik_clz - z
        kc = @ik_kc[t]
        m = 0
        while m < body.size
          ctl.add_drive(m, kc[m] * e)
          m += 1
    self

  # The landing program: its clock starts at the handover, waits at il_ld
  # until the first sand contact (the task's pit contact flag) and is set to
  # il_ld when the sand comes early.
  -> il_chunk(mv, t, fr)
    ch = mv.add(Chunk.new(t + "il", ~1.0))
    ch.hold_until(Latch.after(~60.0))
    ch.correct(->(f, c) nil, ~0.001)
    ch.on_enter(->(f, c) il_entered(f, c, t, fr))
    mv

  -> il_entered(f, ctl, t, fr)
    @il_t0 = f.t
    @il_shift = ~0.0
    @il_landed = false
    @il_first = true
    @il_s_prev = ~-99.0
    @il_zf = ~-99.0
    enter(f, t, fr, :il)

  # With `il_tg` > 0 the program time before the sand is il_tg minus the
  # COM's ballistic time to fall to the landing height (a flight is ballistic
  # whatever the limbs do), not the time since the hand-over: the legs' tuck and
  # reach are then locked to the predicted landing, so a lower or shorter flight
  # (the same take-off program from a slightly different approach) brings them
  # up in time instead of touching the sand with the legs still hanging down
  # (which vaults the body over the feet). The clock never runs backward, holds
  # at il_ld until the sand, and runs in real time from il_ld after it.
  -> il_apply(frame, ctl)
    s = frame.t - @il_t0 + @il_shift
    if !@il_landed
      if @il_tg > ~0.0
        zl = @il_zl
        zl = @land_z if zl <= ~0.0
        s = @il_tg - time_to_z(frame, zl)
        s = @il_s_prev if s < @il_s_prev
        @il_s_prev = s
      # the landing: sand contact with the COM low (a foot grazing the sand
      # early in a low flight must not start the landing motion in the air)
      if frame.at("pit", 1) > ~0.5 && frame.at("com_pos", 2) < @il_lz
        @il_landed = true
        if @il_tg > ~0.0
          @il_shift = @il_ld - (frame.t - @il_t0)
        else
          @il_shift = @il_shift + @il_ld - s
        s = @il_ld
      elsif s > @il_ld
        @il_shift = @il_shift - (s - @il_ld) if @il_tg <= ~0.0
        s = @il_ld
    g = @il_g
    g = ~0.0 if @il_first
    @il_first = false
    prog_apply(ctl, @il_tab[@st], @il_h, @il_n, s, g, @il_kdc, ~0.0, false)
    # rotation feedback
    j = (s / @il_h).floor
    j = 0 if j < 0
    j = @il_n - 2 if j > @il_n - 2
    u = clamp((s - @il_h * j) / @il_h, ~0.0, ~1.0)
    err = frame.torso_pitch - (@il_pr[j] + (@il_pr[j + 1] - @il_pr[j]) * u)
    rate = frame.torso_pitch_rate
    kp = @il_kp[@st]
    kd = @il_kd[@st]
    m = 0
    while m < body.size
      ctl.add_drive(m, kp[m] * err + kd[m] * rate)
      m += 1
    il_clearance(frame, ctl, s) if @il_cl
    self

  # Time-to-strike reflex: before the designed landing (the program is more
  # than il_clt s from il_ld) a foot closing on the sand with less than il_ctau
  # s to go (the lowest of the four toe / heel points' height over its fall
  # speed, from the last tick's height) adds per-muscle gain x (il_ctau - time)
  # to the drive: in a short flight the feet come up instead of striking the
  # sand with the legs hanging down.
  -> il_clearance(frame, ctl, s)
    z = frame.at("toes", 1)
    z = frame.at("toes", 3) if frame.at("toes", 3) < z
    z = frame.at("toes", 5) if frame.at("toes", 5) < z
    z = frame.at("toes", 7) if frame.at("toes", 7) < z
    zp = z
    zp = @il_zf if @il_zf > ~-90.0
    @il_zf = z
    if !@il_landed && s < @il_ld - @il_clt
      vzf = (z - zp) / ctl.dt
      if vzf < ~-0.3
        zz = z
        zz = ~0.0 if zz < ~0.0
        tau = zz / (~0.0 - vzf)
        if tau < @il_ctau
          e = @il_ctau - tau
          kc = @il_kc[@st]
          m = 0
          while m < body.size
            ctl.add_drive(m, kc[m] * e)
            m += 1
    self

  # One tick of a knot program at program time s: every muscle's target is the
  # quintic through the (c, v, a) knots, its drive the linear drive knots (plus
  # gap x the gap knots) plus kdc x g x kd x v*(s), every reflex gain g.
  -> prog_apply(ctl, tab, h, n, s, g, kdc, ge, gapped)
    j = (s / h).floor
    j = 0 if j < 0
    j = n - 2 if j > n - 2
    u = clamp((s - h * j) / h, ~0.0, ~1.0)
    c0 = tab["c"][j]
    c1 = tab["c"][j + 1]
    v0 = tab["v"][j]
    v1 = tab["v"][j + 1]
    a0 = tab["a"][j]
    a1 = tab["a"][j + 1]
    e0 = tab["e"][j]
    e1 = tab["e"][j + 1]
    q0 = e0
    q1 = e1
    if gapped
      q0 = tab["g"][j]
      q1 = tab["g"][j + 1]
    b = Quintic.basis(u)
    u2 = u * u
    u3 = u2 * u
    u4 = u3 * u
    p = Easing.apply(:min_jerk, u)
    dp = ~30.0 * u2 - ~60.0 * u3 + ~30.0 * u4
    d1 = ~1.0 - ~18.0 * u2 + ~32.0 * u3 - ~15.0 * u4
    d2 = u - ~4.5 * u2 + ~6.0 * u3 - ~2.5 * u4
    d3 = ~1.5 * u2 - ~4.0 * u3 + ~2.5 * u4
    d4 = ~0.0 - ~12.0 * u2 + ~28.0 * u3 - ~15.0 * u4
    kd = ctl.reflex.kd
    cmd = ctl.command
    m = 0
    while m < body.size
      c = c0[m] + (c1[m] - c0[m]) * p + h * b[0] * v0[m] + h * h * b[1] * a0[m] + h * h * b[2] * a1[m] + h * b[3] * v1[m]
      v = ((c1[m] - c0[m]) * dp + h * d1 * v0[m] + h * h * d2 * a0[m] + h * h * d3 * a1[m] + h * d4 * v1[m]) / h
      e = e0[m] + (e1[m] - e0[m]) * u
      e = e + ge * (q0[m] + (q1[m] - q0[m]) * u) if gapped
      if @pa_on
        c = c + @pa_dc[m]
        e = e + @pa_de[m]
      ctl.add_drive(m, e + kdc * g * kd[m] * v)
      ctl.set_gain(m, g)
      ctl.add_offset(m, c - cmd[m])
      m += 1
    self

  # ---- flight and landing (after LongJumpSkill's, skills/long_jump.w) ---------------

  -> add_flight(mv)
    st = @stiff
    hang = sym_pose(param("j_hg_hip", ~0.1, ~-0.6, ~1.2), param("j_hg_knee", ~0.6, ~0.0, ~2.4),
                    param("j_hg_ank", ~0.2, ~-0.5, ~0.9), param("j_hg_spine", ~-0.1, ~-0.5, ~0.6),
                    param("j_hg_arm", ~2.6, ~-1.0, ~3.1), ~0.3, st)
    tuck = sym_pose(param("j_tk_hip", ~1.4, ~0.3, ~2.2), param("j_tk_knee", ~1.8, ~0.5, ~2.5),
                    param("j_tk_ank", ~0.2, ~-0.5, ~0.9), param("j_tk_spine", ~0.4, ~-0.3, ~1.2),
                    param("j_tk_arm", ~1.5, ~-1.0, ~3.1), ~0.3, st)
    reach = sym_pose(param("j_rc_hip", ~1.9, ~0.8, ~2.2), param("j_rc_knee", ~0.2, ~-0.02, ~1.0),
                     param("j_rc_ank", ~-0.1, ~-0.6, ~0.6), param("j_rc_spine", ~0.8, ~-0.3, ~1.2),
                     param("j_rc_arm", ~0.8, ~-1.0, ~3.1), ~0.2, st)
    absorb = sym_pose(param("j_ab_hip", ~1.9, ~0.8, ~2.2), param("j_ab_knee", ~1.6, ~0.3, ~2.5),
                      param("j_ab_ank", ~0.0, ~-0.6, ~0.9), param("j_ab_spine", ~1.0, ~-0.3, ~1.2),
                      param("j_ab_arm", ~2.0, ~-1.0, ~3.1), ~0.4, st)
    sit = sym_pose(param("j_rv_hip", ~1.6, ~0.2, ~2.2), param("j_rv_knee", ~1.2, ~0.2, ~2.5),
                   param("j_rv_ank", ~0.0, ~-0.6, ~0.9), param("j_rv_spine", ~0.6, ~-0.2, ~1.2),
                   param("j_rv_arm", ~1.0, ~-1.0, ~3.1), ~0.6, st)
    rv_gain = param("j_rv_gain", ~0.6, ~0.1, ~2.0)
    rc_tau = @rc_tau
    tk_tau = param("j_tk_tau", ~0.5, ~0.05, ~1.2)
    hg_min = param("j_hg_min", ~0.08, ~0.0, ~0.3)
    @air_pitch = param("j_air_pitch", ~0.2, ~-0.3, ~0.8)
    @k_air = param("j_k_air", ~0.5, ~0.0, ~3.0)
    @kd_air = param("j_kd_air", ~0.1, ~0.0, ~0.6)
    @k_air_arm = param("j_k_air_arm", ~0.5, ~0.0, ~3.0)
    @rc_comp = param("j_rc_comp", ~0.0, ~0.0, ~1.0)
    @land_z = param("j_land_z", ~0.55, ~0.3, ~0.9)
    @ab_k = param("j_ab_k", ~1.0, ~0.0, ~3.0)
    @ab_k2 = param("j_ab_k2", ~0.0, ~0.0, ~2.0)
    @ab_kd2 = param("j_ab_kd2", ~0.0, ~0.0, ~0.3)
    @cp_k = param("j_cp_k", ~0.0, ~0.0, ~2.0)
    @cp_margin = param("j_cp_margin", ~0.1, ~-0.3, ~0.6)
    @cp_leg = param("j_cp_leg", ~0.9, ~0.7, ~1.0)
    # sand contact (any body part), or the runway after a while (a jump that
    # falls short of the pit)
    sand = Latch.above("pit", 1, ~0.5)
    landed = Latch.any([sand, Latch.above("pit", 2, ~0.5).after_min(~0.15)])
    soon = Latch.test("sand_in_tau", ->(f, e, c) time_to_land(f) < rc_tau)
    gather = Latch.test("sand_in_tk_tau", ->(f, e, c) time_to_land(f) < tk_tau)
    air = ->(f, c) enter(f, @to_side, other(@to_side), :air)
    ch = mv.add(Chunk.new("hang", param("j_hg_dur", ~0.15, ~0.04, ~0.5)).pose(hang))
    ch.hold_until(Latch.any([gather, landed]).after_min(hg_min), ~0.9)
    ch.correct(->(f, c) air_correction(f, c, :hang), @gait_spring)
    ch.on_enter(air)
    ch = mv.add(Chunk.new("tuck", param("j_tk_dur", ~0.15, ~0.05, ~0.4)).pose(tuck))
    ch.hold_until(Latch.any([soon, landed]), ~0.9)
    ch.correct(->(f, c) air_correction(f, c, :reach), @gait_spring)
    ch.on_enter(air)
    ch = mv.add(Chunk.new("reach", param("j_rc_dur", ~0.2, ~0.05, ~0.6)).pose(reach))
    ch.hold_until(landed, ~1.5)
    ch.correct(->(f, c) air_correction(f, c, :reach), @gait_spring)
    ch.on_enter(air)
    ab_d = param("j_ab_drive", ~0.0, ~0.0, ~1.0)
    ch = mv.add(Chunk.new("absorb", param("j_ab_dur", ~0.3, ~0.1, ~0.8)).pose(absorb))
    ch.gain(param("j_ab_gain", ~0.5, ~0.1, ~2.0))
    ch.drive(sym_drive([["knee_pos", ab_d], ["hip_flex_pos", ab_d * ~0.5]]))
    ch.correct(->(f, c) landing_correction(f))
    ch.hold_until(Latch.after(~0.7))
    ch.on_enter(->(f, c) enter(f, @to_side, other(@to_side), :landed))
    ch = mv.add(Chunk.new("sit", param("j_rv_dur", ~0.8, ~0.2, ~2.0)).pose(sit).gain(rv_gain))
    ch.hold_until(Latch.after(~60.0))
    ch.correct(->(f, c) landing_correction(f))
    mv

  # In the air the whole body's angular momentum is fixed: legs sweeping back
  # and arms coming down rotate the trunk backward against the forward
  # rotation from the board (the hang). u grows with the trunk's excess
  # forward pitch and pitch rate. In the tuck and reach the legs are aimed
  # in world frame (j_rc_comp compensates the pelvis pitch).
  -> air_correction(f, ctl, phase)
    off = zeros
    capture_reach(f, ctl, off) if phase == :reach && @cp_k > ~0.0
    u = @k_air * (f.torso_pitch - @air_pitch) + @kd_air * f.torso_pitch_rate
    if phase == :hang
      joint_offset(off, "l_hip_flex", ~0.0 - u)
      joint_offset(off, "r_hip_flex", ~0.0 - u)
    elsif phase != :hitch
      joint_offset(off, "l_hip_flex", @rc_comp * pelvis_pitch(f))
      joint_offset(off, "r_hip_flex", @rc_comp * pelvis_pitch(f))
    joint_offset(off, "l_shoulder_flex", ~0.0 - @k_air_arm * u)
    joint_offset(off, "r_shoulder_flex", ~0.0 - @k_air_arm * u)
    off

  # Landing reach at the capture point (`j_cp_k` > 0): the legs reach as far
  # forward as the landing can carry. At the predicted sand contact (the COM
  # falling to j_land_z) the body pivots forward over its heels only if they
  # land behind its capture point x_com + vx sqrt(z / g) (the inverted
  # pendulum's point of no return; ahead of it the body sits back into the
  # sand and the mark moves back to the seat). So each hip is steered toward
  # the angle whose straight leg (j_cp_leg m) puts the heel j_cp_margin behind
  # that point, in world frame (the sensed pelvis pitch compensated).
  -> capture_reach(f, ctl, off)
    t = time_to_land(f)
    vx = f.com_vx
    cp = f.com_x + vx * t + vx * Math.sqrt(@land_z / ~9.81) - @cp_margin
    hip_x = f.at("pelvis_pos", 0) + vx * t
    d = clamp((cp - hip_x) / @cp_leg, ~-0.95, ~0.95)
    theta = Math.asin(d)
    ["l_", "r_"].each ->(side)
      want = theta + pelvis_pitch(f)
      cmd = pair_angle(ctl.command.values, side + "hip_flex")
      joint_offset(off, side + "hip_flex", @cp_k * (want - cmd))
    off

  # After touchdown: while the COM is still behind the heels, flex the trunk
  # and throw the arms forward (more the further behind), so the body pivots
  # over the feet instead of sitting back into the sand; once past them and
  # pitching forward fast, extend trunk and hips against a forward roll.
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

  # Seconds until the COM falls to its landing height on a ballistic arc.
  -> time_to_land(f)
    z = f.at("com_pos", 2) - @land_z
    vz = f.at("com_vel", 2)
    return ~0.0 if z <= ~0.0
    (vz + Math.sqrt(vz * vz + ~19.62 * z)) / ~9.81

  # ... to the height zl.
  -> time_to_z(f, zl)
    z = f.at("com_pos", 2) - zl
    vz = f.at("com_vel", 2)
    return ~0.0 if z <= ~0.0
    (vz + Math.sqrt(vz * vz + ~19.62 * z)) / ~9.81

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

  # Feed-forward activations on both sides: [[suffix, a], ...].
  -> sym_drive(pairs)
    out = zeros
    pairs.each ->(pair)
      ["l_", "r_"].each ->(side)
        nm = side + pair[0]
        out[body.index(nm)] = pair[1] if body.has?(nm)
    out
