"""ljx_feat: a state-conditioned take-off program by regression of per-state programs on the penultimate-touchdown features (agent L3).

Per-state programs (ljx_robust.py on ONE capture, only the excitation knots free, from the one-start program) reach ~10 m on nearly every start of the LABELLED
BEYOND-HUMAN body; one fixed program (gap knots only) reaches 7.5-9 m. Here the per-state excitation tables, by muscle ROLE (T_ = plant leg, F_ = free leg),
are regressed on standardised features of the state the program starts from:

    E(s; z) = X0 + B0 + sum_m z_m B_m       (knots every 30 ms, clipped to [0, 1]; g = 0; contraction tables from the base program)

    ljx_feat.py fit  --states a,b,c --tag pf [--init params/long_jump_beyond_nom1.txt] [--lam 1.0] --out prog.npz
    ljx_feat.py eval --prog prog.npz --states a,b,c [--intercept-only]     (harness, latched IKProgram, board-mode score)

Features (at the start of the program, the state the skill sees at its first tick, kinematics of the start of the last physics step as the bridge reads them):
    gap          line - penultimate toe (as the skill's gap_err + ik_gap0)
    swing_ahead  plant-side foot body x - COM x
    pen_ahead    penultimate-side foot body x - COM x
    torso        torso pitch (rad)
    com_z        COM height
"""

import argparse
import json
import math
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

import long_jump_limits as L  # noqa: E402
import ljx  # noqa: E402
import ljx_robust  # noqa: E402

FEATURES = ["gap", "swing_ahead", "pen_ahead", "torso", "com_z"]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "out", "lj3")


def roles_of(mus):
    return sorted(set(L.role_of(n, "l") for n in mus))


def prog_by_role(path, body, plant, nk, roles):
    """The excitation table of a program file as (roles, knots)."""
    _, tab = L.read_ik(path, body.muscles, plant, nk=nk)
    idx = {r: i for i, r in enumerate(roles)}
    out = np.zeros((len(roles), nk))
    for i, nm in enumerate(body.muscles):
        out[idx[L.role_of(nm, plant)]] = tab["e"][:, i]
    return out


def raw_features(body, cap):
    """The features of a captured state (see the module doc)."""
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, cap["state"], L.SPEC)
    mujoco.mj_forward(m, d)
    q = d.qpos.copy()
    prev = q.copy()
    mujoco.mj_integratePos(m, prev, d.qvel, -m.opt.timestep)
    d.qpos[:] = prev
    mujoco.mj_kinematics(m, d)
    mujoco.mj_comPos(m, d)
    plant = cap["plant"]
    pen = "l" if plant == "r" else "r"
    com_x = float(d.subtree_com[body.pelvis][0])
    com_z = float(d.subtree_com[body.pelvis][2])
    sw = float(d.xpos[m.body(f"{plant}_foot").id][0]) - com_x
    pa = float(d.xpos[m.body(f"{pen}_foot").id][0]) - com_x
    up = d.xmat[body.torso].reshape(3, 3)[:, 2]
    torso = math.atan2(up[0], up[2])
    gap = cap["board_x"] - float(d.site(f"{pen}_toe").xpos[0])
    d.qpos[:] = q
    mujoco.mj_forward(m, d)
    return np.array([gap, sw, pa, torso, com_z])


def load_states(names):
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    return caps, body


def fit(a):
    names = [n for n in a.states.split(",") if n]
    caps, body = load_states(names)
    nk = 24
    roles = roles_of(body.muscles)
    from search import read_params
    X0 = prog_by_role(a.init, body, caps[0]["plant"], nk, roles)
    F = np.array([raw_features(body, c) for c in caps])
    mu, sd = F.mean(axis=0), F.std(axis=0) + 1e-9
    Z = (F - mu) / sd
    Y = []
    for n, c in zip(names, caps):
        Xi = prog_by_role(os.path.join(OUT, f"ps_{n}_{a.tag}.txt"), body, c["plant"], nk, roles)
        Y.append((Xi - X0).ravel())
    Y = np.array(Y)
    A = np.hstack([np.ones((len(Z), 1)), Z])
    pen = a.lam * np.eye(A.shape[1])
    pen[0, 0] = 0.0
    B = np.linalg.solve(A.T @ A + pen, A.T @ Y)
    res = Y - A @ B
    tot = ((Y - Y.mean(axis=0)) ** 2).sum()
    print(f"fit: {len(names)} states, features {FEATURES}, lam {a.lam}; per-state shift from the init: rms {np.sqrt((Y ** 2).mean()):.4f}, "
          f"rms of the intercept {np.sqrt((B[0] ** 2).mean()):.4f}, slopes per sd: {[round(float(np.sqrt((B[i + 1] ** 2).mean())), 4) for i in range(Z.shape[1])]}; "
          f"variance of the shifts explained by the features: {1 - (res ** 2).sum() / tot:.2f}")
    np.savez(a.out, roles=json.dumps(roles), X0=X0, B=B, mu=mu, sd=sd, feats=json.dumps(FEATURES), init=a.init, lam=a.lam)
    print("wrote", a.out)


def predict(P, f, intercept_only=False):
    z = (f - P["mu"]) / P["sd"]
    if intercept_only:
        z = np.zeros_like(z)
    A = np.concatenate([[1.0], z])
    Y = A @ P["B"]
    return np.clip(P["X0"] + Y.reshape(P["X0"].shape), 0.0, 1.0)


def evaluate(a):
    from search import read_params
    P = dict(np.load(a.prog, allow_pickle=False))
    roles = json.loads(str(P["roles"]))
    names = [n for n in a.states.split(",") if n]
    caps, body = load_states(names)
    nk = 24
    kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    pf = read_params(str(P["init"]))
    base_path = a.base
    cfg = {"board": True, "margin": 0.03, "lmax": -1.5, "lmin": -15.0, "grfcap": 20.0, "grfw": 0.3, "td": 0.0, "tdw": 20.0}
    idx = {r: i for i, r in enumerate(roles)}
    rows = []
    for n, c in zip(names, caps):
        f = raw_features(body, c)
        Xr = predict(P, f, a.intercept_only)
        _, tab = L.read_ik(base_path, body.muscles, c["plant"], nk=nk)
        e = np.zeros((nk, len(body.muscles)))
        for i, nm in enumerate(body.muscles):
            e[:, i] = Xr[idx[L.role_of(nm, c["plant"])]]
        tab["e"] = e
        tab["e1"] = np.zeros_like(e)
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], 0.0, 1.0, kp, kd, pf["ik_gap0"], pf["ik_end"])
        r = ljx_robust.simulate_prog2(body, c, prog)
        s = ljx.score2(r, c, cfg)
        rows.append((n, r, s, f))
        if not a.quiet:
            if r["valid"]:
                print("%-12s gap %.3f score %6.2f D_board %.3f off %+.3f vx %.2f vz %.2f L %6.1f contact %.3f grf12 %.1f" % (
                    n, f[0], s, r["D"] - (c["board_x"] - r["toe_max"]), r["toe_max"] - c["board_x"], r["vx"], r["vz"], r["L"], r["contact_s"], r["grf12_bw"]))
            else:
                print("%-12s gap %.3f INVALID %s" % (n, f[0], r.get("why")))
    sc = np.array([x[2] for x in rows])
    legal = sc[sc > 0]
    nval = sum(1 for x in rows if x[1]["valid"])
    db = np.array([x[1]["D"] - (caps[i]["board_x"] - x[1]["toe_max"]) for i, x in enumerate(rows) if x[1]["valid"] and x[2] > 0])
    print("SUMMARY %s%s: %d states, valid %d, legal(score>0) %d, score mean %.3f (all) / %.3f (legal), D_board of the legal: mean %.3f median %.3f min %.3f" % (
        os.path.basename(a.prog), " (intercept only)" if a.intercept_only else "", len(rows), nval, len(legal), sc.mean(), legal.mean() if len(legal) else 0.0,
        db.mean() if len(db) else 0.0, np.median(db) if len(db) else 0.0, db.min() if len(db) else 0.0))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fit")
    f.add_argument("--states", required=True)
    f.add_argument("--tag", default="pf")
    f.add_argument("--init", default="/Users/erik/tungsten/bits/tungsten-robolab/params/long_jump_beyond_nom1.txt")
    f.add_argument("--lam", type=float, default=1.0)
    f.add_argument("--out", required=True)
    e = sub.add_parser("eval")
    e.add_argument("--prog", required=True)
    e.add_argument("--states", required=True)
    e.add_argument("--base", default="/Users/erik/tungsten/bits/tungsten-robolab/out/lj3/ik_bs45_b20.txt")
    e.add_argument("--intercept-only", dest="intercept_only", action="store_true")
    e.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    fit(a) if a.cmd == "fit" else evaluate(a)


if __name__ == "__main__":
    main()
