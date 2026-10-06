"""add_record_trial.py: append the arena trial `long_jump_v4_beyond_record480` to playground/arena/trials.json through the arena's own
load / save (under its lock), a NEW entry only: no existing trial is touched (checked: every other entry is byte-identical after the round trip).
Main session, 4 Oct 2026, after agent L6's best-of-six result (scratchpad/lj6/LOG.md).

The trial scores the PER-ATTEMPT event behind the competition numbers: `record_beaten` = 1.0 for a LEGAL jump past the human record 8.95 m
(a metric the task `long_jump_v4_beyond_a` gained for this: playground/tasks/long_jump_v4_beyond_a.py). With attempts that are independent
starts, P(best of six legal marks > 8.95 m) = 1 - (1 - p)^6 for the per-attempt rate p, so the mean of this metric over the 480 seeds IS the
number the competition statistics are made of (scratchpad/lj6/bo6.py computes them from the same rollouts)."""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import arena  # noqa: E402

name = "long_jump_v4_beyond_record480"
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    before = copy.deepcopy(trials)
    if name in trials:
        print(name, "already exists; nothing done")
        sys.exit(0)
    entry = copy.deepcopy(trials["long_jump_v4_beyond_robust96"])
    entry["about"] = (
        "long_jump_v4_beyond_record480: the HUMAN RECORD in a six-attempt competition, on the LABELLED BEYOND-HUMAN BODY with an UNLIMITED RUN-UP. "
        "Metric `record_beaten` = 1.0 for a LEGAL jump past 8.95 m (the men's world record), else 0.0: the per-attempt event behind the best-of-six "
        "numbers (athletics counts the best legal mark of six attempts; for independent attempts P(best of six > 8.95 m) = 1 - (1 - p)^6, so p = 0.11 "
        "is the median competition beating the record). 480 FRESH perturbed standing starts, seeds 41001-41480 (the main session's out-of-sample set "
        "for agent L6's best-of-six program: no search, practice, fit or selection used them), check mark 151.025 m, task long_jump_v4_beyond_a, the body "
        "of playground/profiles/beyond.json (strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8 on the average 1.75 m / 67.5 kg skeleton: an "
        "INVENTED stretch, not a human profile). NEVER compare with the human-body long-jump trials or with the mean-mark trial "
        "long_jump_v4_beyond_robust96: a program that wins HERE trades legality and mean mark for the upper tail (L6's K3: mean mark 6.0 m against 6.7-7.0 m "
        "for L4's C7, legal 74% against 89%). Seeded with L4's C7 (the program trained for the mean mark). Main session, 2026-10-04.")
    entry["metric"] = "record_beaten"
    entry["seeds"] = list(range(41001, 41481))
    entry["report"] = ["official_m", "effective_m", "board_offset_m", "foul", "failed", "speed_5m", "takeoff_vx", "takeoff_vz", "flight_s"]
    trials[name] = entry
    arena.save_json(arena.TRIALS, trials)
after = arena.load_json(arena.TRIALS, {})
changed = [k for k in before if before[k] != after.get(k)]
print("added", name, "with", len(after[name]["seeds"]), "seeds, metric", after[name]["metric"], "; existing entries changed:", changed, "; total trials", len(after))
