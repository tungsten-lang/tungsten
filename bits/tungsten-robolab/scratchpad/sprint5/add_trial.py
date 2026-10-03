"""add_trial.py NAME: append the fall-free-ness arena trial `sprint_top_speed_v4_beyond_fresh128` to playground/arena/trials.json through the arena's own
load / save (under its lock), a NEW entry only: no existing trial is touched (checked: every other entry is byte-identical after the round trip)."""
import copy, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import arena
name = sys.argv[1] if len(sys.argv) > 1 else "sprint_top_speed_v4_beyond_fresh128"
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    before = copy.deepcopy(trials)
    if name in trials:
        print(name, "already exists; nothing done"); sys.exit(0)
    base = trials["sprint_top_speed_v4_beyond"]
    entry = copy.deepcopy(base)
    entry["about"] = ("FALL-FREE-NESS of the BEYOND-HUMAN LABELLED BODY VARIANT's sprinter (profiles/beyond.json: strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8 on the average skeleton; "
                      "an INVENTED stretch, not a human profile; NEVER compare with the average, P95, elite2 or sprinter trials). The rules of sprint_top_speed_v4_beyond (the fastest 1 s window, peak_speed_1s, m/s, "
                      "in a 30 s run from a perturbed standing start, guard NO FALL, task run_v4, ROBOLAB_CALIB=v4 + the beyond profile) on 128 FRESH starts, seeds 12001-12128, that no search ever used: "
                      "a fall scores -1e9, so the mean paired difference is dominated by the fall rate. Agent S5, 2026-09-30.")
    entry["seeds"] = list(range(12001, 12129))
    trials[name] = entry
    arena.save_json(arena.TRIALS, trials)
after = arena.load_json(arena.TRIALS, {})
changed = [k for k in before if before[k] != after.get(k)]
print("added", name, "with", len(after[name]["seeds"]), "seeds; existing entries changed:", changed, "; total trials", len(after))
