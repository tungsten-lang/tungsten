"""add_trial.py: append the arena trial `sprint_top_speed_v4_beyond_fresh512` (512 FRESH starts, seeds 50001-50512) to playground/arena/trials.json through the arena's own
load / save (under its lock), a NEW entry only: no existing trial is touched (checked: every other entry is byte-identical after the round trip). Main session, 3 Oct 2026.
The 128-seed trial `sprint_top_speed_v4_beyond_fresh128` has one start that S6's gear changes, so the arena's paired test cannot see an improvement there (p 0.51)."""
import copy, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import arena
name = "sprint_top_speed_v4_beyond_fresh512"
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    before = copy.deepcopy(trials)
    if name in trials:
        print(name, "already exists; nothing done"); sys.exit(0)
    entry = copy.deepcopy(trials["sprint_top_speed_v4_beyond_fresh128"])
    entry["about"] = ("FALL-FREE-NESS of the BEYOND-HUMAN LABELLED BODY VARIANT's sprinter (profiles/beyond.json: strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8 on the average skeleton; "
                      "an INVENTED stretch, not a human profile; NEVER compare with the average, P95, elite2 or sprinter trials). The rules of sprint_top_speed_v4_beyond_fresh128 (the fastest 1 s window, peak_speed_1s, "
                      "in a 30 s run from a perturbed standing start, guard NO FALL, task run_v4, ROBOLAB_CALIB=v4 + the beyond profile) on 512 FRESH starts, seeds 50001-50512, that no search ever used "
                      "(the main session's out-of-sample set for agent S6's rear-step gear): a fall scores -1e9, so the mean paired difference is dominated by the fall rate, and with 512 starts the "
                      "arena's paired test can see an improvement of a quarter of the falls (about 8 more recovered starts than new falls). Main session, 2026-10-03.")
    entry["seeds"] = list(range(50001, 50513))
    trials[name] = entry
    arena.save_json(arena.TRIALS, trials)
after = arena.load_json(arena.TRIALS, {})
changed = [k for k in before if before[k] != after.get(k)]
print("added", name, "with", len(after[name]["seeds"]), "seeds; existing entries changed:", changed, "; total trials", len(after))
