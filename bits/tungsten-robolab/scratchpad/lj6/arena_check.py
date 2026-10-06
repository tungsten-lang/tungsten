"""arena_check (agent L6): a READ-ONLY check of the final candidate against the arena's champion of `long_jump_v4_beyond_robust96` (L4's C7, stored per-seed scores) by the arena's own paired test
(arena.evaluate + arena.compare on the trial's metric = the mean official mark on seeds 10001-10096). It writes NOTHING (no history, no champions.json / trials.json). LABELLED beyond-human body, unlimited run-up."""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, ROOT + "/playground")
import arena

def main():
    trials = arena.load_json(arena.TRIALS, {})
    champs = arena.load_json(arena.CHAMPS, {})
    name = "long_jump_v4_beyond_robust96"
    trial = trials[name]
    champ = champs[name]
    params = arena.read_params(ROOT + "/scratchpad/lj6/params/long_jump_beyond_bo6a.txt")
    ctl = ROOT + "/bin/challengers/long_jump_run_y-l6a"
    rows, scores = arena.evaluate(trial, params, ctl, "long_jump_v4_beyond_a", 6)
    s = arena.summary(scores)
    cmp = arena.compare(trial, champ["scores"], scores)
    print("trial %s (%d seeds %d-%d): champion (C7) mean %.4f; challenger K3 mean %.4f +- %.4f; paired mean diff %+.4f, p %s, WINS (arena rule): %s" % (
        name, len(trial["seeds"]), trial["seeds"][0], trial["seeds"][-1], champ["summary"]["mean"], s["mean"], s["ci95"], cmp["mean_diff"], cmp["p"], cmp["wins"]))
    hi = sum(1 for x in scores if x > 8.95)
    print("K3 on these 96 seeds: legal %d, marks above 8.95 m: %d (the champion: %d)" % (sum(1 for x in scores if x > 0), hi, sum(1 for x in champ["scores"] if x > 8.95)))

if __name__ == "__main__":
    main()
