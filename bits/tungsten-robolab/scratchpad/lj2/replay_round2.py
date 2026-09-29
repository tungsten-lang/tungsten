"""Round 2's v4 champions (superseded in round 3): replay each frozen params file with its FROZEN binary and with the round-3 build
(c3) on every start of its trial and compare per seed.  usage: replay_round2.py <controller> <workers>"""
import json
import os
import sys

ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, ROOT + "/playground")
os.environ.setdefault("MUJOCO_GL", "cgl")

# (trial, history time of the promotion, frozen name)
ROUND2 = [
    ("long_jump_v4_p95", "2026-09-29 05:59:16", "long_jump_v4_p95-20260929-055916"),
    ("long_jump_v4_p95_robust", "2026-09-29 05:47:27", "long_jump_v4_p95_robust-20260929-054727"),
    ("long_jump_v4_p95_robust32", "2026-09-29 05:47:01", "long_jump_v4_p95_robust32-20260929-054701"),
    ("long_jump_v4_p95_robust96", "2026-09-29 09:00:39", "long_jump_v4_p95_robust96-20260929-090039"),
]


def main():
    import arena
    ctl = os.path.abspath(sys.argv[1])
    workers = int(sys.argv[2])
    trials = arena.load_json(arena.TRIALS, {})
    hist = [json.loads(line) for line in open(ROOT + "/playground/arena/history.jsonl") if line.strip()]
    for name, when, frozen in ROUND2:
        row = [h for h in hist if h["trial"] == name and h["time"] == when][0]
        params = arena.read_params(ROOT + "/playground/arena/params/" + frozen + ".txt")
        trial = dict(trials[name])
        old_bin = ROOT + "/bin/champions/" + frozen
        _, s_old = arena.evaluate(trial, params, old_bin, row["task"], workers)
        _, s_new = arena.evaluate(trial, params, ctl, row["task"], workers)
        ndiff = sum(1 for a, b in zip(s_old, s_new) if abs(a - b) > 1e-9)
        print("%-28s task %-18s frozen binary mean %8.4f | current build mean %8.4f | n=%3d differ %d" % (
            name, row["task"], sum(s_old) / len(s_old), sum(s_new) / len(s_new), len(s_new), ndiff), flush=True)


if __name__ == "__main__":
    main()
