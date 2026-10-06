"""CHAINED replay (round 6, agent D5): the right return (stage 2), the left hand's second stroke (stage 3) and the right hand's second stroke (stage 4)
replayed as ONE physics rollout from the trigger tick of a stage of a recorded closed-loop start (scratchpad/btl6/rec6.py records).

What is replayed and what is emulated (every emulated rule is the skill's own, lib/robolab/skills/dribble_btl.w pg_trigger / pg_step / handoff_prog):

  * the physics: MuJoCo from the physics snapshot at the first stage's trigger tick (the top of the tick), the recorded activations of every muscle
    as the BASE, five substeps per 5 ms control tick, contact forces per substep as oracle_lib.Replay.run;
  * the tables: a programmed stage's stroking arm (16 muscles) is overridden by the stage's table (T0 + sum_i u_i clip(T_i, +-gmax) at the 17 knots, bounded to
    [0, 1], linear in time, clock shifted by lead - acd - (predicted time to the crossing)), with the schedule features u computed ONLINE at the stage's
    trigger tick from the replayed state exactly as the skill reads its sensor frame (bridge conventions: the state as the last mj_step left it, values
    rounded to 6 significant digits as the S lines of the bridge are printed);
  * the triggers: stage s + 1 fires at the first tick after stage s's release at which the ball is off the floor (z >= 0.14), rises (predicted post-bounce
    vertical speed > 0.5) and its predicted rising crossing of z 0.62 is within the stage's lead (receive_state);
  * the releases: stage s's hand has touched (ball_touch >= touch_thr) and the touch force falls below release_thr after push_min s (pg_step);
  * the events a release starts (the receiving arm's x_recover chunk, the lead leg's clearance window) are not re-computed: the recorded activations of the
    receiving arm and of the legs are replayed TIME-SHIFTED by the difference between the replayed and the recorded release tick (integer ticks);
  * stage 2 has the servo of round 3 around its table: the recorded activation of the right arm already contains it, so the stage-2 table of the replay is the
    recorded activation plus (new table - old table): `act = clip(rec - T_old + T_new)` (exact at T_new = T_old); stages 3 and 4 have no servo (pg_fbs 0): act = T.

    import chainrep as C
    ch = C.Chain(params_file, rec0)           # one per process (builds the MuJoCo model)
    st = ch.prep(rec, s0)                     # per-start data for a chain that starts at stage s0 (2, 3 or 4)
    run = ch.run(st, over={2: B2})            # replay; over = replacement tables per stage (6, 16, 17) arrays
"""
import math
import sys

import numpy as np

for _p in ("scratchpad/btl6", "scratchpad/btl5", "scratchpad/btl2", "playground", "playground/tasks"):
    if _p not in sys.path:
        sys.path.insert(0, _p)
import mujoco  # noqa: E402

import fit3 as F  # noqa: E402
import oracle_lib as O  # noqa: E402
import oracle_search as S  # noqa: E402
from common import load  # noqa: E402

TICK, SUB, DT = 0.005, 5, 0.001
G = 9.81
RH = 0.62
ZJ = [4, 1, 3]
HAND = {2: "r", 3: "l", 4: "r"}
NK, DK = F.NK, F.DK


def r6(x):
    """a number as the bridge prints it (6 significant digits) and the controller reads it"""
    return float("%.6g" % x)


class Chain:
    def __init__(self, pfile, rec0, gmax=None):
        self.P = load(pfile)
        self.rp = O.Replay(rec0)
        self.names = rec0["names"]
        self.ids = np.array(rec0["act_ids"])
        n = len(self.names)
        self.idx = {s: np.array(F.arm_indices(self.names, s)) for s in "lr"}
        arm = set(self.idx["l"].tolist()) | set(self.idx["r"].tolist())
        self.legs = np.array([i for i, nm in enumerate(self.names) if i not in arm and (nm[:2] in ("l_", "r_"))])
        self.tab = {}
        for s in (2, 3, 4):
            B, nom, sc = F.parse_stage(pfile, s)
            # the energy-hinge block pgv<s> (skill key pg_vn 1): u_v = clip((knee - vz at the crossing) / scale, 0, 2.5), a 7th block, zero if the params have none
            P_ = self.P
            Bv = np.zeros((1, 16, NK))
            if P_.get("pg_vn", 0.0) > 0.5:
                for m_ in range(16):
                    for k_ in range(NK):
                        Bv[0, m_, k_] = P_.get(f"pgv{s}_{m_}_{k_}", 0.0)
            Bw = np.zeros((1, 16, NK))
            if P_.get("pg_vn", 0.0) > 0.5:
                for m_ in range(16):
                    for k_ in range(NK):
                        Bw[0, m_, k_] = P_.get(f"pgw{s}_{m_}_{k_}", 0.0)
            self.tab[s] = (np.concatenate([B, Bv, Bw], axis=0), nom, sc)
        self.vk = {s: self.P.get(f"pgvk{s}", 1.5) for s in (2, 3, 4)}
        self.vs = {s: self.P.get(f"pgvs{s}", 0.2) for s in (2, 3, 4)}
        self.vsel = {s: int(self.P.get(f"pg_vsel{s}", 0.0)) for s in (2, 3, 4)}
        self.kap = {s: self.P.get(f"pg_vts{s}", 0.0) for s in (2, 3, 4)}
        self.wk = {s: self.P.get(f"pgwk{s}", 0.7) for s in (2, 3, 4)}
        self.ws = {s: self.P.get(f"pgws{s}", 0.05) for s in (2, 3, 4)}
        P = self.P
        self.gmax = P.get("pg_gmax", 1000.0) if gmax is None else gmax
        self.lead = {s: P.get(f"pg_lead{s}", P.get("pg_lead", 0.165)) for s in (2, 3, 4)}
        self.acd = {s: P.get(f"pg_acd{s}", P.get("pg_acd", 0.0025)) for s in (2, 3, 4)}
        self.touch_thr = P.get("touch_thr", 0.353)
        self.release_thr = P.get("release_thr", 0.376)
        self.push_min = P.get("push_min", 0.02)
        self.t, self.m, self.d = self.rp.t, self.rp.m, self.rp.d
        self.mid = {nm: i for i, nm in enumerate(self.names)}
        # contraction index pairs of the posture joints per side
        self.zidx = {s: [(self.names.index(f"{s}_{F.JOINTS[j]}_pos"), self.names.index(f"{s}_{F.JOINTS[j]}_neg")) for j in ZJ] for s in "lr"}
        self.ball_dof = self.rp.ball_dof
        self.track_body = False
        self.ball_id = self.rp.ball_id

    def reexpress(self, s, mult):
        """the stage's table in `mult` times wider feature units: the function inside the old +-2.5 range is unchanged (gains scale with the spread), beyond it the
        table extrapolates its gains linearly up to +-2.5 new spreads (the nominal and T0 stay)"""
        B, nom, sc = self.tab[s]
        B2 = B.copy()
        B2[1:6] = B[1:6] * mult
        self.tab[s] = (B2, nom, sc * mult)

    def reexpress_feat(self, s, i, mult):
        """feature i (0 x, 1 y, 2 wrist flexion, 3 shoulder abduction, 4 elbow) of the stage's table in `mult` times wider units (gains scale with the spread)"""
        B, nom, sc = self.tab[s]
        B2 = B.copy()
        sc2 = sc.copy()
        B2[1 + i] = B[1 + i] * mult
        sc2[i] = sc[i] * mult
        self.tab[s] = (B2, nom, sc2)

    # ---- per-start data -------------------------------------------------------------------------

    def prep(self, rec, s0):
        """Per-start data of a chain that starts at stage s0: None if the record lacks the stage (or its hand is the wrong one)."""
        if s0 not in rec["ks"]:
            return None
        kb = rec["k_base"]
        ks0 = rec["ks"][s0]
        i0 = ks0 - kb
        if i0 < 1:
            return None
        ev = {}
        for t, lst in rec["ev"].items():
            for kind, h in lst:
                ev.setdefault((kind, h), []).append(t - i0)
        hand0 = "right" if HAND[s0] == "r" else "left"
        if 0 not in ev.get(("g", hand0), []):
            return None
        st = {"seed": rec["seed"], "s0": s0, "snap": rec["snaps"][s0], "acts": rec["acts"][i0:].copy(), "ball_prev": rec["ball"][i0 - 1].copy(),
              "pass_log": rec["pass_log"], "streak": rec["streak"], "ev": ev, "ks": {s: v - ks0 for s, v in rec["ks"].items()},
              "ball_rec": rec["ball"][i0:].copy()}
        # recorded release ticks (the receiving hand's x_recover onset after the stage's trigger), relative to the chain's first tick
        x_l = sorted(t for t in ev.get(("x", "left"), []) if t > 0)
        x_r = sorted(t for t in ev.get(("x", "right"), []) if t > 0)
        if s0 == 2:
            rr2 = x_l[0] if x_l else None
            rr3 = next((t for t in x_r if rr2 is not None and t > rr2), None)
            rr4 = next((t for t in x_l if rr3 is not None and t > rr3), None)
        elif s0 == 3:
            rr2 = None
            rr3 = x_r[0] if x_r else None
            rr4 = next((t for t in x_l if rr3 is not None and t > rr3), None)
        else:
            rr2, rr3, rr4 = None, None, (x_l[0] if x_l else None)
        st["rec_rel"] = {2: rr2, 3: rr3, 4: rr4}
        return st

    # ---- the frame as the controller reads it -------------------------------------------------------

    def sensors(self):
        """ball_rise (7), ball_pos z, ball_touch (r, l) and the muscles' contractions, from the state the last mj_step left (as Sim.tick builds the frame)."""
        d, m, t = self.d, self.m, self.t
        ex = {nm: vals for nm, vals in t.extra_sensors(m, d)}
        rise = [r6(x) for x in ex["ball_rise"]]
        bz = r6(float(ex["ball_pos"][2]))
        touch = [r6(x) for x in ex["ball_touch"]]
        c, cd, _ = self.rp.sim.contraction()
        return rise, bz, touch, c

    def sensors_loaded(self, ball_prev):
        """the frame of the trigger tick from a snapshot just loaded (mj_forward recomputed the kinematics: the position is the recorded stale one, the
        contraction is moved back by one step of its rate, as scratchpad/btl5/prep.py does)"""
        d, rp = self.d, self.rp
        v = d.qvel[self.ball_dof:self.ball_dof + 3].copy()
        spin = d.body("ball").xmat.reshape(3, 3) @ d.qvel[self.ball_dof + 3:self.ball_dof + 6]
        rise = [r6(x) for x in self.t.predict_rise(np.array(ball_prev, float), v, spin)]
        c, cd, _ = rp.sim.contraction()
        return rise, r6(float(ball_prev[2])), None, c - cd * DT

    @staticmethod
    def crossing(rise):
        """receive_state: (time to the crossing, x, y, vertical speed there) or None"""
        vz = rise[5]
        if vz <= 0.5:
            return None
        disc = vz * vz - 2.0 * G * (RH - rise[2])
        s = vz / G
        if disc > 0.0:
            s = (vz - math.sqrt(disc)) / G
        return rise[6] + s, rise[0] + rise[3] * s, rise[1] + rise[4] * s, math.sqrt(max(disc, 0.0)), rise[2] + vz * vz / (2.0 * G)

    def features(self, s, cr, c, knobs=None):
        """the stage's schedule features u (5, clipped to +-2.5) from the crossing and the stroking arm's contractions (the frame's)"""
        B, nom, sc = self.tab[s]
        if knobs and s in knobs and knobs[s].get("dnom") is not None:
            nom = nom + knobs[s]["dnom"]
        side = HAND[s]
        zq = [r6(float(c[a])) - r6(float(c[b])) for a, b in self.zidx[side]]
        feat = np.array([cr[1], cr[2]] + zq)
        u = np.clip((feat - nom) / sc, -2.5, 2.5)
        k = knobs.get(s, {}) if knobs else {}
        uw = float(np.clip((cr[4] - (self.wk[s] + k.get("dwk", 0.0))) / max(self.ws[s] + k.get("dws", 0.0), 0.01), 0.0, 2.5))
        return np.append(np.append(u, self.uv_of(s, cr, knobs)), uw)

    def uv_of(self, s, cr, knobs=None):
        k = knobs.get(s, {}) if knobs else {}
        fv = cr[4] if self.vsel[s] else cr[3]          # the hinge's argument: the incoming ball's apex (pg_vsel 1, 2) or its vertical speed at the crossing
        knee = self.vk[s] + k.get("dvk", 0.0)
        if self.vsel[s] == 2:                          # turned over: a block for the strong balls
            return float(np.clip((fv - knee) / max(self.vs[s] + k.get("dvs", 0.0), 0.02), 0.0, 2.5))
        return float(np.clip((knee - fv) / max(self.vs[s] + k.get("dvs", 0.0), 0.02), 0.0, 2.5))

    def shift_of(self, s, cr, knobs=None, first=False):
        """the table clock's shift: lead - acd - (predicted time to the crossing), with the knobs' offsets (the first stage's trigger is fixed by the record);
        `dkap` shifts the clock by dkap seconds per unit of the energy feature (a weak ball's crossing time is the time to its apex)"""
        k = knobs.get(s, {}) if knobs else {}
        lead = self.lead[s] + (0.0 if first else k.get("dlead", 0.0))
        sh = lead - (self.acd[s] + k.get("dacd", 0.0)) - cr[0]
        kap = self.kap[s] + k.get("dkap", 0.0)
        if kap:
            sh += kap * self.uv_of(s, cr, knobs)
        return sh

    def stage_table(self, s, u, shift, over, n=120):
        B = over[s] if (over and s in over) else self.tab[s][0]
        X = F.table_knots(B, u, self.gmax)
        return F.knot_acts(X, shift, n)

    def vzc0(self, st, s=None):
        """the energy feature's argument (the vertical speed at the crossing, or the apex with pg_vsel) at the chain's first trigger tick"""
        self.load(st["snap"])
        rise, bz, _, c = self.sensors_loaded(st["ball_prev"])
        cr = self.crossing(rise)
        if cr is None:
            return None
        return cr[4] if self.vsel[st["s0"] if s is None else s] else cr[3]

    def apex0(self, st):
        """the incoming ball's predicted apex at the chain's first trigger tick"""
        self.load(st["snap"])
        rise, bz, _, c = self.sensors_loaded(st["ball_prev"])
        cr = self.crossing(rise)
        return None if cr is None else cr[4]

    # ---- the rollout --------------------------------------------------------------------------------

    def load(self, snap):
        q, v, a, c, tm, ws, eq = snap
        d = self.d
        d.qpos[:] = q
        d.qvel[:] = v
        d.act[:] = a
        d.ctrl[:] = c
        d.time = tm
        d.qacc_warmstart[:] = ws
        d.eq_active[:] = eq
        mujoco.mj_forward(self.m, d)

    def run(self, st, over=None, n_max=470, upto=4, trace=True, knobs=None):
        """Replay the chain of start data `st` (prep) with the stages' tables (G's, or `over[s]`); returns the trace and the stage events."""
        rp, m, d = self.rp, self.m, self.d
        s0 = st["s0"]
        acts = st["acts"]
        na = len(acts)
        self.load(st["snap"])
        n_ball = self.ball_id
        rec_rel = st["rec_rel"]
        idxL, idxR = self.idx["l"], self.idx["r"]
        legs = self.legs
        pos = np.zeros((n_max, 3))
        vel = np.zeros((n_max, 3))
        cf = np.zeros((n_max, 4))
        lg = np.zeros((n_max, 2, 3, 3))
        palm = np.zeros((n_max, 2, 3))
        prehit = np.zeros((n_max, 2))          # [left, right]: a body contact preceded that hand's contact within the tick
        stage = {}                      # s -> dict(t0, A, live, u, shift, touched, released, rel, T_old)
        rel_tick = {}                   # s -> replayed release tick
        trig_tick = {s0: 0}
        armed = {}
        # the first stage: features from the loaded snapshot
        rise, bz, _, c = self.sensors_loaded(st["ball_prev"])
        cr = self.crossing(rise)
        if cr is None:
            return None
        u = self.features(s0, cr, c, knobs)
        shift = self.shift_of(s0, cr, knobs, first=True)
        A, live = self.stage_table(s0, u, shift, over)
        if s0 == 2:
            u_old = self.features(s0, cr, c, None)
            shift_old = self.shift_of(s0, cr, None, first=True)
            A_old, _ = self.stage_table(s0, u_old, shift_old, None)
        else:
            A_old = None
        stage[s0] = {"t0": 0, "A": A, "live": live, "A_old": A_old, "u": u, "shift": shift, "touched": False, "released": False, "cr": cr}
        end_tick = None
        last_rel = None
        body_hits = []
        for i in range(n_max):
            if i > 0:
                rise, bz, touch, c = self.sensors()
                # (1) the trigger of the next stage: pg_trigger runs before pg_step
                nxt = None
                for s in (3, 4):
                    if s > s0 and s not in stage and armed.get(s) is not None and armed[s] <= i and s <= upto:
                        nxt = s
                        break
                if nxt is not None and bz >= 0.14:
                    cr = self.crossing(rise)
                    if cr is not None and cr[0] <= self.lead[nxt] + (knobs[nxt].get("dlead", 0.0) if knobs and nxt in knobs else 0.0):
                        u = self.features(nxt, cr, c, knobs)
                        shift = self.shift_of(nxt, cr, knobs)
                        A, live = self.stage_table(nxt, u, shift, over)
                        stage[nxt] = {"t0": i, "A": A, "live": live, "A_old": None, "u": u, "shift": shift, "touched": False, "released": False, "cr": cr}
                        trig_tick[nxt] = i
                # (2) pg_step: the release of every running stage
                for s, ss in stage.items():
                    if ss["released"]:
                        continue
                    k = 0 if HAND[s] == "r" else 1
                    fk = touch[k]
                    tt = (i - ss["t0"]) * TICK
                    if fk >= self.touch_thr:
                        ss["touched"] = True
                    if ss["touched"] and fk < self.release_thr and tt > self.push_min:
                        ss["released"] = True
                        rel_tick[s] = i
                        armed[s + 1] = i + 1
                        last_rel = i
            # the base activations: recorded, time-shifted per group by the release shifts
            def jidx(group, i=i):
                if group == "t":
                    return min(i, na - 1)
                if group == "L":
                    r2 = rel_tick.get(2)
                    rr2 = rec_rel[2]
                    if rr2 is None:
                        return min(i, na - 1)
                    if r2 is None:
                        return min(i, rr2 - 1)
                    return min(max(i - (r2 - rr2), 0), na - 1)
                if group == "R":
                    r3 = rel_tick.get(3)
                    rr3 = rec_rel[3]
                    if rr3 is None:
                        return min(i, na - 1)
                    if r3 is None:
                        return min(i, rr3 - 1)
                    return min(max(i - (r3 - rr3), 0), na - 1)
                if group == "G":      # legs: lift 1 aligned to the release of stage 2, lift 2 to the release of stage 3
                    r2, r3 = rel_tick.get(2), rel_tick.get(3)
                    rr2, rr3 = rec_rel[2], rec_rel[3]
                    if r3 is not None and rr3 is not None:
                        return min(max(i - (r3 - rr3), 0), na - 1)
                    cap = (rr3 - 1) if rr3 is not None else na - 1
                    if r2 is not None and rr2 is not None:
                        return min(max(i - (r2 - rr2), 0), cap, na - 1)
                    if rr2 is not None:
                        return min(i, rr2 - 1)
                    return min(i, cap, na - 1)
                return min(i, na - 1)
            a = acts[jidx("t")].copy()
            a[idxL] = acts[jidx("L")][idxL]
            a[idxR] = acts[jidx("R")][idxR]
            a[legs] = acts[jidx("G")][legs]
            # the tables
            for s, ss in stage.items():
                j = i - ss["t0"]
                if j < 0 or j >= len(ss["live"]) or not ss["live"][j]:
                    continue
                arm = idxR if HAND[s] == "r" else idxL
                if ss["A_old"] is not None:
                    a[arm] = np.clip(a[arm] - ss["A_old"][:, j] + ss["A"][:, j], 0.0, 1.0)
                else:
                    a[arm] = ss["A"][:, j]
            d.ctrl[self.ids] = a
            fm = [0.0, 0.0, 0.0, 0.0]
            sb = -1
            sh = [-1, -1]
            for sub in range(SUB):
                mujoco.mj_step(m, d)
                f = rp.contacts()
                for jj, key in enumerate(("l", "r", "floor", "body")):
                    if f[key] > fm[jj]:
                        fm[jj] = f[key]
                if f["body"] > 0.3 and sb < 0:
                    sb = sub
                if f["body"] > 0.3 and self.track_body:
                    for ci in range(d.ncon):
                        g1, g2 = d.contact.geom1[ci], d.contact.geom2[ci]
                        if rp.ball_geom in (g1, g2):
                            og = g2 if g1 == rp.ball_geom else g1
                            if og != rp.floor_geom and og not in rp.hand_geoms:
                                nm = mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_BODY, int(m.geom_bodyid[og]))
                                if not body_hits or body_hits[-1][1] != nm or i - body_hits[-1][0] > 2:
                                    body_hits.append((i, nm))
                for hh in (0, 1):
                    if sh[hh] < 0 and f["lr"[hh]] > 0.3:
                        sh[hh] = sub
            pos[i] = d.xpos[n_ball]
            vel[i] = d.qvel[self.ball_dof:self.ball_dof + 3]
            cf[i] = fm
            for hh in (0, 1):
                prehit[i, hh] = 1.0 if (sb >= 0 and sh[hh] >= 0 and sb < sh[hh]) else 0.0
            for si in range(2):
                for ji in range(3):
                    lg[i, si, ji] = d.xpos[rp.leg_ids[si][ji]]
                palm[i, si] = d.site_xpos[rp.palm_ids[si]]
            # the end of the evaluation: after the last stage's release and its bounce, the ball rises through z 0.60 (or the other hand touches it), or time
            lastst = max(stage)
            if lastst == upto and (upto in rel_tick):
                r = rel_tick[upto]
                if i > r + 8:
                    fl = np.nonzero(cf[r:i + 1, 2] > 0.2)[0]
                    other = 0 if HAND[upto] == "r" else 1
                    if len(fl) and ((vel[i, 2] > 0 and pos[i, 2] >= 0.60) or cf[i, other] > 0.3 or i > r + 120):
                        end_tick = i
                        break
            # chain broke: the next stage never fires
            if last_rel is not None and lastst < upto and i > last_rel + 150:
                end_tick = i
                break
        n = (end_tick + 1) if end_tick is not None else n_max
        out = {"pos": pos[:n], "vel": vel[:n], "cf": cf[:n], "legs": lg[:n], "palm": palm[:n], "prehit": prehit[:n], "t0": st["snap"][4]}
        return {"out": out, "stage": stage, "rel": rel_tick, "trig": trig_tick, "n": n, "body_hits": body_hits}
