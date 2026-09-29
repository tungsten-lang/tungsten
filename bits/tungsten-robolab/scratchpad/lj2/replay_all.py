"""Replay every long-jump champion's frozen params with ONE controller (the current build) and compare per seed with the stored
champion scores: exactness check that older params still replay bit-identically on the rebuilt skill.
usage: replay_all.py <controller> <workers> [trial ...]"""
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
os.environ.setdefault("MUJOCO_GL", "cgl")


def main():
    import arena
    ctl = os.path.abspath(sys.argv[1])
    workers = int(sys.argv[2])
    only = sys.argv[3:]
    trials = arena.load_json(arena.TRIALS, {})
    champs = arena.load_json(arena.CHAMPS, {})
    for name in sorted(champs):
        if "long_jump" not in name or (only and name not in only):
            continue
        ch = champs[name]
        trial = dict(trials[name])
        params = arena.read_params(ch.get("frozen_params") or ch["params"])
        rows, scores = arena.evaluate(trial, params, ctl, ch["task"], workers)
        stored = ch.get("scores") or []
        ndiff = sum(1 for a, b in zip(scores, stored) if abs(a - b) > 1e-9) + abs(len(scores) - len(stored))
        good = [x for x in scores if abs(x) < 1e8]
        sgood = [x for x in stored if abs(x) < 1e8]
        print("%-28s %-58s mean %8.4f n=%3d stored %8.4f  differ %d" % (
            name, ch.get("frozen_params") or ch["params"], sum(good) / max(1, len(good)), len(scores),
            sum(sgood) / max(1, len(sgood)), ndiff), flush=True)


if __name__ == "__main__":
    main()
