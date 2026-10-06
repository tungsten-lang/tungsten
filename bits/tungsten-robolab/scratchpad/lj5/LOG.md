# L5: the labelled beyond-human long jump on S6a's runner (main session, 3 Oct 2026)

Why: Erik's goal "use the best runner for long jump and then exceed human ability" and his 2 Oct decision that labelled beyond-human bodies count. S6 (scratchpad/sprint6/LOG.md) produced
the best runner so far (S6a, the rear step for starts whose COM begins over the heel: falls 7.4 % -> 5.6 % over 2280 seeds, falls before 20 s 6.2 % -> 4.4 %); L4's long jump (rob2) still ran F1.

What was done (no agent; a mechanical port with an identity gate):
- (removed again, see RESULT) `lib/robolab/skills/long_jump_run_z.w` (`LongJumpRunZSkill < RunGearZSkill`) = a COPY of `long_jump_run_y.w` with only the class line changed (the reason for a copy and not a subclass is in long_jump_run_x.w);
  entry `lib/entry/long_jump_run_z.w`; frozen controller `bin/challengers/long_jump_run_z-l5` (built by `./build.sh long_jump_run_z`).
- params `params/long_jump_beyond_rob2z.txt` = L4's `long_jump_beyond_rob2.txt` + S6a's 7 `rk_` lines (the only lines S6a adds to F1; L4's file contains every F1 key unchanged).
- IDENTITY (gate): the new controller with L4's params (no rk_ lines) reproduces L4's official marks on 12 of 12 starts (10001-10012), 0 differ (a throw-away script over `arena.evaluate` with the champion record's own task and trial env, removed with the other artifacts below).
- FRESH CHECK: L5 against L4 on 256 starts nobody has used (51001-51256), same task (the champion record's own, `long_jump_v4_beyond_a`) and trial env; result below.

## RESULT (3 Oct 2026): NULL, and why. S6a's gear does not apply to the long-jump task's starts; L5 = L4; nothing kept but this record

- FRESH CHECK (256 starts nobody had used, 51001-51256, the champion record's own task `long_jump_v4_beyond_a`, the trial's env; labelled beyond-human body, unlimited run-up): L4 (F1 runner, rob2) mean 7.022 m, legal 232/256 (90.6 %), 5 starts above 8.95 m;
  L5 (S6a runner, rob2 + the 7 rk_ lines) mean 7.022 m, legal 232/256, 5 above 8.95 m; **starts whose mark differs: 0 of 256.** (The same 12-start identity gate had passed with L4's params and no rk_ lines: 0 of 12 differ.)
- WHY: the rear step is taken by starts whose COM - ankles at the first tick is below rk_thr = -0.05 m. `scratchpad/lj5/com0_lj.py` over the same 256 seeds: the long-jump task's starts have COM - ankles between -0.018 and +0.014 m, **0 of 256 below -0.05 m**,
  while task `run_v4` (the sprint trials) has -0.075 to +0.082 m on the same seeds, 4 of 256 below -0.05 m. The jump task perturbs its starts far less than the sprint task, so the deep class that S6a fixes does not occur there; the 2-5 % of runs that fall before the line in
  the jump task are the acceleration / handover / top-gear falls, which S6a does not touch.
- THE RK_ LINES ARE LIVE (so the null is the threshold, not a wiring fault): with rk_thr raised to +0.5 m (every start at risk) the marks of 12 starts all change (for example 51011 0.0 -> 7.84 m, 51005 7.29 -> 0.0 m, 51003 7.26 -> 6.00 m): the step perturbs normal starts, as designed it should not be applied to them.
- So the labelled long jump already runs on the best runner for ITS starts: `long_jump_run_y-l4b` (F1) = what S6a would give. The files built for this check (`long_jump_run_z.w`, its entry, `params/long_jump_beyond_rob2z.txt`, the binaries) were REMOVED after the check
  (no dead code); to redo it: copy `lib/robolab/skills/long_jump_run_y.w` to `long_jump_run_z.w` changing only the class line to `+ LongJumpRunZSkill < RunGearZSkill`, copy the entry with `use robolab/skills/run_gearz` and `LongJumpRunZSkill.new`,
  `./build.sh long_jump_run_z`, and append S6a's 7 rk_ lines (`params/run_gearz_v4_beyond_s6a.txt`) to `params/long_jump_beyond_rob2.txt` (L4's file contains every F1 key unchanged).
- WHAT WOULD HELP THE JUMP (from L4's FINAL STATE; L4's own M3, the plant-touchdown-time regimes, was RUN and gave NO gain in official rollouts: +0.007 on 480 starts, harness gain vanished after Rb1-Rb3; a program set chosen at the plant from measured features is uncorrelated, a perfect selector would add only +0.22): a take-off with feedback instead of tables (foot-lag gains +0.04 official), a runner that arrives at 10 m/s with F1's fall rate (about +0.2 m), a landing that does not fall back (up to +0.39 m), more captured states per take-off update, a risk-seeking objective if the count of jumps above 8.95 m is the goal; a runner with fewer falls is worth about 0.1 m (2-5 % falls before the line at about 7 m each) but S6a is not that runner for this task.
