"""Add the round-2 dribble trials to playground/arena/trials.json (a new entry only, under the arena lock)."""
import fcntl, json, os, sys
sys.path.insert(0, "playground")
import arena
NEW = {}
base = json.load(open(arena.TRIALS))["dribble_btl_streak_25"]
e = dict(base)
e["about"] = ("longest run of consecutive good through-the-legs passes in 15 s on 32 FRESH starts (seeds 1101-1132, never used in any tuning): "
              "the same rules and metric as dribble_btl_streak_25 (tasks/dribble_btl.py: between the legs below the crotch, one bounce, caught legally by the other hand, "
              "nothing else hit, the dribble goes on); guards: no fall, no carry. v3 challengers run with --task dribble_btl_v3")
e["seeds"] = list(range(1101, 1133))
NEW["dribble_btl_streak_fresh32"] = e
with open(os.path.join(arena.DIR, ".lock"), "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    trials = json.load(open(arena.TRIALS))
    for k, v in NEW.items():
        assert k not in trials, k + " exists"
        trials[k] = v
    arena.save_json(arena.TRIALS, trials)
    fcntl.flock(f, fcntl.LOCK_UN)
print("added", list(NEW))
