"""Add the long_jump_v4_p95_robust96 trial (96 fresh starts 9033-9128, the v3 robust96 seeds, on the v4 P95 body) to
playground/arena/trials.json under the arena lock. Existing trials are never touched. Run once."""
import copy
import json
import os
import sys

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena


def main():
    with arena.locked():
        trials = arena.load_json(arena.TRIALS, {})
        if "long_jump_v4_p95_robust96" in trials:
            print("already there")
            return
        base = copy.deepcopy(trials["long_jump_v4_p95_robust32"])
        base["seeds"] = list(range(9033, 9129))
        base["about"] = (
            "long_jump_v4_p95_robust96: long_jump_v4_p95_robust32's scene, rules, body and metric on 96 perturbed standing starts (seeds "
            "9033-9128, the seeds of long_jump_p95_robust96) that no search or practice used and that are disjoint from long_jump_v4_p95_robust's 16 and "
            "long_jump_v4_p95_robust32's 32: with a 3-10 percent failure rate per start (a stumble in the run-up, a somersault after a weak take-off, "
            "a foul) a 32-start trial cannot separate two programs that differ by a few rescued starts. Original description: "
            + trials["long_jump_v4_p95_robust32"]["about"])
        trials["long_jump_v4_p95_robust96"] = base
        arena.save_json(arena.TRIALS, trials)
        print("added long_jump_v4_p95_robust96,", len(base["seeds"]), "seeds")


if __name__ == "__main__":
    main()
