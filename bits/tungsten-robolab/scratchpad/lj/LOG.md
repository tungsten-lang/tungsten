# scratchpad/lj (long jump workstream, 29 Sep 2026)

The running log is `out/long_jump_run/LOG.md` (decisions, numbers, traps). This directory holds scratch scripts and backups:

- `assemble.sh <take-off file> <landing file> <out> [tg] [delta]`: a full params file (overlay last: il_tg, il_zl, check-mark shift).
- `one.py`, `trace.py`, `plant_contacts.py`, `swing_clear.py`, `speedprofile.py`, `v4run.py`: single-rollout probes (planner debug lines, per-tick traces, plant contact events, swing-foot heights, speed vs distance, the v4 runner).
- `fbprobe*.py`, `ttsprobe.py`, `latchforce.py`, `evalfb.py`: hand-set feedback / reflex probes on captured starts (harness).
- `capture_mine*.sh`, `capture_e2.sh`, `scan_tg.sh`, `seed_trials.sh`, `e2_*.sh`, `v4_ideal.sh`: the batch jobs that were run.
- `backup/`: copies of `long_jump_limits.py` and `long_jump_run.w` before the larger edits.
- `cand_*.txt`: assembled candidate params (C0 = pn1, C1 = pn2), `fbg*_*.txt` greedy outputs, `land_*_g*.txt` landing snapshots.
- `README_round2*.md`: drafts of the README section (the final text is in README.md).
