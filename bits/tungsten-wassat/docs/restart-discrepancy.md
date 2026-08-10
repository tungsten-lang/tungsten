# Phase 0: the "unexplained 4x" on bmc-ibm-12 — resolved

2026-07-22. Question under investigation: `bmc-ibm-12` (SATISFIABLE, 39,598
vars) was reported to take 11,224 conflicts on the shipped adaptive-restart
build but 2,609 on a "pure rare-restart build", even though the 16,384-conflict
restart floor means neither run should ever restart. The working theory was
that "something in the adaptive bookkeeping changes the search". If real, an
invisible 4x in the baseline would poison every measurement Phases 1–3 are
judged by.

## Verdict: the bookkeeping is exonerated, bit-for-bit

A pure rare-restart build — the shipped core with the LBD trigger deleted, so
`want_restart` is simply `since_restart >= 16384` — produces **exactly**
11,224 conflicts and 45,910 decisions on `bmc-ibm-12`: identical to the
shipped adaptive build, decision for decision.

This is the expected result, and it is provable from the code rather than
merely observed. Below the restart floor the adaptive state is *write-only*:

- The LBD and trail moving-average windows are written on every conflict but
  read only inside the `want_restart` evaluation, which is gated behind
  `@since_restart >= WASSAT_MIN_RESTART_INTERVAL` (16,384). A run of 11,224
  conflicts never reaches that gate.
- `reduce_db` sits inside the restart branch, so it is equally unreachable;
  the shipped run performs zero restarts and zero reductions
  (`c stats restarts=0 reduces=0`).
- Nothing else in the conflict-side bookkeeping touches assignment, activity,
  phase, or the heap.

So the two restart policies cannot diverge on this instance, and they don't.

## Where the 2,609 must have come from

The figure is not reproducible from any restart-policy change on the current
core, and no surviving backup of the previous session's experiments
(`/tmp/solver_backup.w`, `solver_v1.w`, `solver_pre_la.w`, `solver_bmc_base.w`,
`solver_pre_best.w`, `solver_pre_probe.w`) contains a build that produces it.
What the backups do confirm:

- `solver_bmc_base.w` (the old sawtooth `100 * (1 + n % 8)` schedule, same
  core otherwise) reproduces the historical benchmark number exactly:
  21,399 conflicts, 85,580 decisions.
- Every earlier backup differs from the shipped core in more than restart
  policy (old linear-scan VSIDS with periodic decay vs. the native EVSIDS
  heap, no LBD tracking, different reduce cadence constants), so any number
  measured on them is a cross-core comparison, not a restart-policy
  measurement.

The 2,609/601 ms "marathon" figure therefore came from a differently
configured experimental build whose exact configuration did not survive.
Candidates tested and excluded on the shipped core: initial phase polarity
+1 (12,543 conflicts), scheduled bare restarts every ~1,500 conflicts
(9,340), scheduled restart+reduce (21,119 — reduction *hurts* here),
`--lookahead 4` (>600 s, nowhere near 601 ms).

## What this means for later phases

1. **Single-instance conflict counts are chaotic.** Sound, equally-reasonable
   perturbations of the search (phase init, restart cadence, reduce cadence)
   swing `bmc-ibm-12` between 2.6k and 21k conflicts. A 4x difference between
   two builds on one satisfiable instance is trajectory noise, not signal.
2. **Gates must be family-level.** Phase 1–3 success criteria are measured
   over instance families with medians of repetitions (as the plan already
   specifies), never on a single instance.
3. **The stats contract makes this visible.** `c stats restarts=… reduces=…`
   is emitted on every run, so "the adaptive machinery never acted" is now an
   observable fact of a run rather than an inference from code reading.
4. **Reduce cadence is a real, separate question.** Scheduled reduction made
   this satisfiable BMC instance *worse* (21,119 vs 11,224), consistent with
   the reduce-on-restart coupling being harmless here. Revisit only with
   family-level evidence, ideally after Phase 1 preprocessing changes clause
   counts materially.

Experiment logs: variants built from the shipped source in the session
scratchpad (`v2-reduce-decoupled`, `v3-restart-only`, `v5-pure-rare`,
`v6-sawtooth`, `v7-phase-pos`), all run on
`/tmp/satlib/structclean/bmc/bmc-ibm-12.cnf` with the same compiler.
