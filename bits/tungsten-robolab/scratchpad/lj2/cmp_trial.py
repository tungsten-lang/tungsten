"""Compare a controller+params on a trial's seeds with the stored champion per-seed scores (exactness check of a rebuilt controller).
usage: cmp_trial.py <trial> <params> <controller> <task> [workers]"""
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
os.environ.setdefault("MUJOCO_GL", "cgl")


def main():
    import arena
    trial_name, params_path, ctl, task = sys.argv[1:5]
    workers = int(sys.argv[5]) if len(sys.argv) > 5 else 2
    trials = arena.load_json(arena.TRIALS, {})
    champs = arena.load_json(arena.CHAMPS, {})
    trial = dict(trials[trial_name])
    params = arena.read_params(params_path)
    rows, scores = arena.evaluate(trial, params, os.path.abspath(ctl), task, workers)
    stored = champs[trial_name].get("scores")
    n_bad = 0
    for s, sc, st in zip(trial["seeds"], scores, stored or [None] * len(scores)):
        same = st is not None and abs(sc - st) < 1e-9
        if not same:
            n_bad += 1
        print("seed %-5s new %8.4f stored %s %s" % (s, sc, ("%8.4f" % st) if st is not None else "-", "" if same else "DIFF"))
    good = [x for x in scores if abs(x) < 1e8]
    print("trial %s: mean %.4f over %d, %d differ from the stored champion scores" % (trial_name, sum(good) / len(good), len(good), n_bad))


if __name__ == "__main__":
    main()
