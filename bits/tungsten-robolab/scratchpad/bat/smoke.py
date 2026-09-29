"""Smoke test of the round-2 features: default replay against a reference binary on a few pitches, then each feature once."""
import os, sys, json
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import bat_rep
P = bat_rep.read_params(sys.argv[1])
ref, new = sys.argv[2], sys.argv[3]
seeds = [int(s) for s in sys.argv[4].split(",")]
def run(ctl, params):
    return [bat_rep.rollout(bat_rep.job(params, ctl, s, 4.3)) for s in seeds]
a = run(ref, P); b = run(new, P)
same = all(x["rec"].get("bat_speed") == y["rec"].get("bat_speed") and x["flow"] == y["flow"] and x["hit"] == y["hit"] for x, y in zip(a, b))
print("default replay identical:", same, [(x["rec"].get("bat_speed"), y["rec"].get("bat_speed")) for x, y in zip(a, b)])
for name, over in (("train_first=2", {"train_first": 2.0}), ("train_legs_ease=0.5", {"train_legs_ease": 0.5}), ("train_ext=0.03", {"train_ext": 0.03}),
                   ("tres tw3=0.5 tv0=0.3", {"tw3": 0.5, "tv0": 0.3})):
    r = run(new, {**P, **over})
    print(name, [(x["hit"], x["rec"].get("bat_speed"), round(x["flow"], 3) if x["flow"] else None, x.get("error")) for x in r])
