"""Two-stage replay: the left hand's return (stage 0) and the right hand's return (stage 1) in one physics trace.

    rp = O.Replay(rec)                      # rec: a closed-loop record (snapshots from before stage 0's trigger)
    out = run_pair(rp, ks, xL, uL, xR, cfg) # both programs (gain-scheduled tables) applied as the skill applies them

The replay reproduces the skill's chain logic: stage 0 starts at tick ks (its trigger tick); the left hand's release
(sensor force below release_thr after a touch) hands over to the right hand, whose program starts at the first tick with the
ball off the floor whose PREDICTED rising crossing of z 0.62 is within `lead` s (the live prediction, as `receive_state`);
every other muscle replays the recording. The right arm's hover before its program is the recorded one, so the recording
should have been made with programs close to the ones being searched.
"""
import sys

import mujoco
import numpy as np

sys.path.insert(0, "scratchpad/btl2")
import oracle_lib as O  # noqa: E402

DT_TICK = 0.005


def live_pred(rp, height=0.62):
    """(tau, x, y) from the live state, as the skill's receive_state: None if the ball will not rise."""
    d, m = rp.d, rp.m
    g = 9.81
    p = d.body("ball").xpos.copy()
    adr = m.jnt_dofadr[m.joint("ball").id]
    v = d.qvel[adr:adr + 3].copy()
    spin = d.body("ball").xmat.reshape(3, 3) @ d.qvel[adr + 3:adr + 6]
    r = rp.t.predict_rise(p, v, spin)
    vz = r[5]
    if vz <= 0.5:
        return None
    disc = vz * vz - 2.0 * g * (height - r[2])
    s = vz / g
    if disc > 0.0:
        s = (vz - np.sqrt(disc)) / g
    return (r[6] + s, r[0] + r[3] * s, r[1] + r[4] * s)


def table_at(T, u, nprog, kt, G):
    """Per-tick activation program from a gain-scheduled table set T (3, nm, K)."""
    X = np.clip(T[0] + u[0] * np.clip(T[1], -G, G) + u[1] * np.clip(T[2], -G, G), 0.0, 1.0)
    out = np.zeros((nprog + 1, X.shape[0]))
    for r in range(X.shape[0]):
        out[:, r] = np.interp(np.arange(nprog + 1), kt, X[r])
    return out


def run_pair(rp, ks, cfg, TL, uL, TR, feat_R, jitR=(0.0, 0.0), n=300, stop=True):
    """cfg: idxL, idxR (muscle indices, program order), kt, nprog, G, lead, touch_thr, release_thr, push_min, nomR, scR.
    feat_R(pred_xy) -> u for the right stage (nominal/scale of that stage)."""
    rec = rp.rec
    base = rec["acts"]
    m, d = rp.m, rp.d
    ids = rp.act_ids
    rp.load(ks)
    progL = table_at(TL, uL, cfg["nprog"], cfg["kt"], cfg["G"])
    nprog = cfg["nprog"]
    idxL, idxR = cfg["idxL"], cfg["idxR"]
    pos = np.zeros((n, 3)); vel = np.zeros((n, 3)); cf = np.zeros((n, 4)); legs = np.zeros((n, 2, 3, 3)); palm = np.zeros((n, 2, 3)); prehit = np.zeros(n)
    cf_last = np.zeros((n, 2))
    touched = False
    released_tick = None
    handoff_i = None
    startR = None
    progR = None
    n_used = n
    for i in range(n):
        a = base[ks + i].copy()
        # the right hand's trigger (after the left's handoff, at a tick strictly later than the handoff tick)
        if startR is None and handoff_i is not None and handoff_i < i:
            zb = d.body("ball").xpos[2]
            if zb >= 0.14:
                pr = live_pred(rp)
                if pr is not None and pr[0] <= cfg["lead"]:
                    startR = i
                    u = feat_R(np.array(pr[1:3])) + np.array(jitR)
                    progR = table_at(TR, u, nprog, cfg["kt"], cfg["G"])
        if startR is not None and i - startR <= nprog:
            a[idxR] = progR[i - startR]
        if i <= nprog:
            a[idxL] = progL[i]
        # the left hand's release detection (the skill's pg_step: the sensor is the previous tick's last-substep force)
        if i > 0 and released_tick is None:
            fk = cf_last[i - 1, 0]
            if fk >= cfg["touch_thr"]:
                touched = True
            if touched and fk < cfg["release_thr"] and i * DT_TICK > cfg["push_min"]:
                released_tick = i
                handoff_i = i
        d.ctrl[ids] = a
        fm = [0.0, 0.0, 0.0, 0.0]
        sb = sh = -1
        f = None
        for sub in range(O.SUBSTEPS):
            mujoco.mj_step(m, d)
            f = rp.contacts()
            for j, key in enumerate(("l", "r", "floor", "body")):
                if f[key] > fm[j]:
                    fm[j] = f[key]
            if f["body"] > 0.3 and sb < 0:
                sb = sub
            # the passer whose stroke is being timed: both hands are passers in a chain
            if (f["l"] > 0.3 or f["r"] > 0.3) and sh < 0:
                sh = sub
        pos[i] = d.xpos[rp.ball_id]
        vel[i] = d.qvel[rp.ball_dof:rp.ball_dof + 3]
        cf[i] = fm
        cf_last[i] = (f["l"], f["r"])
        prehit[i] = 1.0 if (sb >= 0 and sh >= 0 and sb < sh) else 0.0
        for si in range(2):
            for ji in range(3):
                legs[i, si, ji] = d.xpos[rp.leg_ids[si][ji]]
            palm[i, si] = d.site_xpos[rp.palm_ids[si]]
        if stop and startR is not None and i > startR + 20 and vel[i, 2] > 0 and pos[i, 2] >= 0.60:
            if np.any(cf[startR:i + 1, 1] > 0.3) and np.any(cf[startR:i + 1, 2] > 0.2):
                n_used = i + 1
                break
    sl = slice(0, n_used)
    return {"pos": pos[sl], "vel": vel[sl], "cf": cf[sl], "legs": legs[sl], "palm": palm[sl], "prehit": prehit[sl],
            "t0": rp.rec["snaps"][ks][4], "release_tick": released_tick, "startR": startR}


def run_chain(rp, ks, cfg, tabs, u0, feats, nstages, jit=None, n=420, stop=True):
    """A chain of `nstages` programmed strokes alternating left (stage 0), right, left, ... on one trace.
    tabs[s % len(tabs)] is the (3, nm, K) table set of stage s; feats[s % len(feats)](pred_xy) its arrival feature (stage 0 uses u0);
    the hands' muscle sets are cfg["idxL"] / cfg["idxR"]. Returns the trace and the release tick of every stage."""
    rec = rp.rec
    base = rec["acts"]
    m, d = rp.m, rp.d
    ids = rp.act_ids
    rp.load(ks)
    nprog = cfg["nprog"]
    idx = [cfg["idxL"] if s % 2 == 0 else cfg["idxR"] for s in range(nstages)]
    col = [0 if s % 2 == 0 else 1 for s in range(nstages)]
    start = [None] * nstages
    prog = [None] * nstages
    touched = [False] * nstages
    handoff = [None] * nstages
    start[0] = 0
    prog[0] = table_at(tabs[0], u0, nprog, cfg["kt"], cfg["G"])
    pos = np.zeros((n, 3)); vel = np.zeros((n, 3)); cf = np.zeros((n, 4)); legs = np.zeros((n, 2, 3, 3)); palm = np.zeros((n, 2, 3)); prehit = np.zeros(n)
    cf_last = np.zeros((n, 2))
    n_used = n
    cur = 0   # the stage whose release is awaited / the last started stage
    for i in range(n):
        a = base[ks + i].copy()
        # trigger of the next stage after the current stage's handoff
        nxt = cur + 1
        if nxt < nstages and start[nxt] is None and handoff[cur] is not None and handoff[cur] < i:
            if d.body("ball").xpos[2] >= 0.14:
                pr = live_pred(rp)
                if pr is not None and pr[0] <= cfg["lead"]:
                    u = feats[nxt % len(feats)](np.array(pr[1:3]))
                    if jit is not None:
                        u = u + np.array(jit[nxt])
                    start[nxt] = i
                    prog[nxt] = table_at(tabs[nxt % len(tabs)], u, nprog, cfg["kt"], cfg["G"])
                    cur = nxt
        for s in range(nstages):
            if start[s] is not None and 0 <= i - start[s] <= nprog:
                a[idx[s]] = prog[s][i - start[s]]
        # release detection of the latest started stage (as the skill's pg_step for the hand that owns the ball)
        s = cur
        if start[s] is not None and handoff[s] is None and i > 0:
            fk = cf_last[i - 1, col[s]]
            if fk >= cfg["touch_thr"]:
                touched[s] = True
            if touched[s] and fk < cfg["release_thr"] and (i - start[s]) * DT_TICK > cfg["push_min"]:
                handoff[s] = i
        d.ctrl[ids] = a
        fm = [0.0, 0.0, 0.0, 0.0]
        sb = sh = -1
        f = None
        for sub in range(O.SUBSTEPS):
            mujoco.mj_step(m, d)
            f = rp.contacts()
            for j, key in enumerate(("l", "r", "floor", "body")):
                if f[key] > fm[j]:
                    fm[j] = f[key]
            if f["body"] > 0.3 and sb < 0:
                sb = sub
            if (f["l"] > 0.3 or f["r"] > 0.3) and sh < 0:
                sh = sub
        pos[i] = d.xpos[rp.ball_id]
        vel[i] = d.qvel[rp.ball_dof:rp.ball_dof + 3]
        cf[i] = fm
        cf_last[i] = (f["l"], f["r"])
        prehit[i] = 1.0 if (sb >= 0 and sh >= 0 and sb < sh) else 0.0
        for si in range(2):
            for ji in range(3):
                legs[i, si, ji] = d.xpos[rp.leg_ids[si][ji]]
            palm[i, si] = d.site_xpos[rp.palm_ids[si]]
        last = nstages - 1
        if stop and start[last] is not None and i > start[last] + 20 and vel[i, 2] > 0 and pos[i, 2] >= 0.60:
            if np.any(cf[start[last]:i + 1, col[last]] > 0.3) and np.any(cf[start[last]:i + 1, 2] > 0.2):
                n_used = i + 1
                break
    sl = slice(0, n_used)
    return {"pos": pos[sl], "vel": vel[sl], "cf": cf[sl], "legs": legs[sl], "palm": palm[sl], "prehit": prehit[sl],
            "t0": rp.rec["snaps"][ks][4], "handoff": handoff, "start": start}
