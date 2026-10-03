"""Add a LABELLED BEYOND-HUMAN BODY long-jump trial to playground/arena/trials.json under the arena lock (L3). Existing trials are never
touched; an existing name is left alone.
usage: add_trial.py <name> <task> <seeds: comma list / a-b ranges> "<what this trial is>" """
import copy
import json
import sys

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena


def seeds_of(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if "-" in tok[1:]:
            a, b = tok.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(tok))
    return out


def main():
    name, task, seeds, what = sys.argv[1:5]
    with arena.locked():
        trials = arena.load_json(arena.TRIALS, {})
        if name in trials:
            print(name, "already there: nothing changed")
            return
        base = copy.deepcopy(trials["long_jump_v4_p95"])
        base["task"] = task
        base["seeds"] = seeds_of(seeds)
        base["env"] = {"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
        base["about"] = (
            f"{name}: LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP. {what} The body is playground/profiles/beyond.json (strength x2.4, muscle speed x2.0, "
            "tendon stiffness x1.5, activation time constants x0.8 on the average 1.75 m / 67.5 kg skeleton, the v4 anatomy): an INVENTED stretch, not a human "
            "profile. NEVER compare its scores with the human-body long-jump trials (long_jump_v4_p95* and the others): the body, the run-up (a check mark of about "
            "151 m instead of 44 m) and the 14 m sand pit are different. Rules, scene and metric as long_jump_v4_p95: official_m is the legal distance from the foul "
            "line to the nearest break in the sand made by any part of the body (World Athletics TR 29-30 as encoded in tasks/long_jump_run.py: a foul, a landing "
            "short of the sand, a torso past 120 deg after the take-off or a runway touch after the landing score 0). The runner is S4's chain D of RunGearXSkill "
            "(sprint_top_speed_v4_beyond), run by LongJumpRunXSkill (bin/challengers/long_jump_run_x-l3b).")
        trials[name] = base
        arena.save_json(arena.TRIALS, trials)
        print("added", name, "task", task, "seeds", base["seeds"][:4], "..." if len(base["seeds"]) > 4 else "", len(base["seeds"]), "starts")


if __name__ == "__main__":
    main()
