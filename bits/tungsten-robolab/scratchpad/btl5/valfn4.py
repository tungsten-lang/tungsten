"""A value function for stage 4: the probability that the A4 left reflex takes the stage-4 stroke's ball (pass 5 ok) given the delivered ball's features
(replay summary of a CLEAN stroke: rise apex, arrival x, y, horizontal speed, velocity), logistic regression with a ridge penalty on the standardized
features [apex, ax, ay, vh, ax^2, ay^2, ax*ay, apex*vh]; trained on closed-loop records (the replay of the recorded stroke reproduces the closed loop).

    scratchpad/btl5/py scratchpad/btl5/valfn4.py data.pkl out.npz [ridge] [stage 3|4]
"""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F


def feats(apex, ax, ay, vh):
    return np.array([apex, ax, ay, vh, ax * ax, ay * ay, ax * ay, apex * vh])


def fit_logistic(X, y, ridge):
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    Z1 = np.hstack([np.ones((len(Z), 1)), Z])
    w = np.zeros(Z1.shape[1])
    R = ridge * np.eye(len(w)); R[0, 0] = 0
    for _ in range(100):
        p = 1 / (1 + np.exp(-Z1 @ w))
        g = Z1.T @ (p - y) + R @ w
        H = Z1.T @ (Z1 * (p * (1 - p))[:, None]) + R
        w = w - np.linalg.solve(H, g)
    return w, mu, sd


def main():
    D = pickle.load(open(sys.argv[1], "rb"))
    out = sys.argv[2]
    ridge = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
    stage = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    class A: pass
    a = A()
    if stage == 4:
        a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 4, 3, 0.1, 0.7, -0.55, 0.0, -0.1
    elif stage == 2:
        a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 2, 1, 0.2, 0.6, -0.5, -0.05, 0.3
    else:   # stage 3
        a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 3, 2, -0.40, 0.10, 0.15, 0.55, 0.30
    lab = stage      # the pass whose success the next stage decides: pass index `stage` (0-based): stage 3 -> pass 4, stage 4 -> pass 5; stage 2: passes 3 and 4 both
    act = [r for r in F.active_set(D, a) if len(r["pass_ok"]) > max(lab, 3)]
    ok_of = (lambda r: bool(r["pass_ok"][2] and r["pass_ok"][3])) if stage == 2 else (lambda r: bool(r["pass_ok"][lab]))
    for r in act:
        r["u"] = np.zeros(5)
    data = {r["seed"]: r for r in act}
    cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
           "arr": {"pos_dz": 0.04, "vel_dz": 0.2, "target": [0.0, 0.38] if stage == 4 else ([-0.09, 0.30] if stage == 2 else [0.44, -0.26]), "vt": [-0.1, 1.5] if stage == 4 else ([-1.58, 1.58] if stage == 2 else [1.5, -1.5]), "pre": True, "w_pos": 4.0, "w_vel": 1.0, "apex_min": 0.5, "w_apex": 5.0}}
    F.init_worker(data, cfg)
    X, y = [], []
    for r in act:
        J, sm = F.eval_one((None, r["seed"], np.zeros(5)))
        if not (sm.get("touch") and sm.get("bounced")) or sm.get("gate", 0) == 0 or sm.get("body", 0) > 0:
            continue
        X.append(feats(sm["apex"], sm["arrive"][0], sm["arrive"][1], float(np.hypot(*sm["va"][:2]))))
        y.append(1.0 if ok_of(r) else 0.0)
    X, y = np.array(X), np.array(y)
    n = len(y)
    idx = np.arange(n); rng = np.random.default_rng(0); rng.shuffle(idx)
    tr, te = idx[: int(0.7 * n)], idx[int(0.7 * n):]
    w, mu, sd = fit_logistic(X[tr], y[tr], ridge)
    p = 1 / (1 + np.exp(-(np.hstack([np.ones((len(te), 1)), (X[te] - mu) / sd]) @ w)))
    # AUC on the held-out part
    pos, neg = p[y[te] == 1], p[y[te] == 0]
    auc = float(np.mean([(a_ > b_) + 0.5 * (a_ == b_) for a_ in pos for b_ in neg])) if len(pos) and len(neg) else float("nan")
    print(f"clean strokes {n}, positives {int(y.sum())}; held-out AUC {auc:.3f} (n {len(te)}, positives {int(y[te].sum())})")
    w, mu, sd = fit_logistic(X, y, ridge)
    np.savez(out, w=w, mu=mu, sd=sd)
    names = ["1", "apex", "ax", "ay", "vh", "ax2", "ay2", "axay", "apex*vh"]
    print("weights", dict(zip(names, np.round(w, 2))))
    # a few probes
    for (apex, ax, ay, vh) in [(0.55, -0.1, 0.38, 1.6), (0.70, -0.1, 0.30, 1.8), (0.70, -0.1, 0.45, 2.0), (0.45, 0.0, 0.40, 1.5), (0.75, -0.05, 0.32, 2.0)]:
        z = (feats(apex, ax, ay, vh) - mu) / sd
        print(f"  apex {apex} arrival ({ax}, {ay}) vh {vh}: p = {1 / (1 + np.exp(-(w[0] + w[1:] @ z))):.2f}")


if __name__ == "__main__":
    main()
