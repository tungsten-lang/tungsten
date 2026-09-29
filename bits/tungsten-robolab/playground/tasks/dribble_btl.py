"""Between-the-legs dribble: the dribble task (tasks/dribble.py: same scene,
ball, bodies and sensors) judged on through-the-legs passes.

A between-the-legs pass (BTL) succeeds when, between the push that releases
the ball and the next hand touch:

  1. the ball passes BETWEEN THE LEGS BELOW THE CROTCH: its centre crosses the
     leg gate, the segment joining the two legs' axes (hip -> knee -> ankle)
     at the ball's own height, strictly between the legs (0 < u < 1 along the
     gate), with the ball moving across it (not a leg sweeping past a still
     ball), and the ball's top below the crotch (hip height less the thigh's
     radius);
  2. it bounces on the floor exactly once;
  3. the first hand to touch it is the OTHER hand, and that touch is legal
     (no carry, below);
  4. it touches no other body part on the way, from the release to the
     catch (a pass that clips a leg is a failed pass; the pushing arm
     brushing the ball while it pushes is part of the push);
  5. the dribble goes on: the receiving hand's own push lands a legal bounce
     (or time runs out first).

Rules the rollout must keep (arena guards):

  carried  the palm carried the ball (dribbling rules forbid the hand under
           the ball): a hand pushed the ball UP from below its equator for
           more than CARRY_S seconds in one touch, one touch lasted longer
           than HOLD_S (holding), or both hands were on the ball at once for
           more than BOTH_S (a two-hand hold). Before the launch the ball
           sits in the hand by the grip weld; that is not dribbling and does
           not count.
  fell     from the bridge (the pivot body cannot fall; kept so a free-root
           body can be scored by the same trial).

Metrics (flat, for the arena):

  btl_rate       successful BTLs / max(BTL attempts, BTL_MIN). Every pass
                 from one hand to the other is judged as a BTL attempt; a ball
                 lost without a failed pass to charge it to (the launch, a
                 plain dribble, a swing that never reaches the ball) is one
                 more failed attempt; and a 15 s rollout is expected to make
                 BTL_MIN attempts (a pass at least every other push once the
                 feet are set), so a run that loses the ball early, or that
                 dribbles instead of passing, cannot score a high rate on a
                 few passes. Plain dribbles between passes are allowed and
                 neither count nor break a streak.
  pass_streak    the longest run of consecutive legal passes (every rule
                 above but the gate); first_btl_ok, whether a run's first
                 pass was a good BTL.
  btl_ok, btl_attempts, btl_opportunities (the denominator), btl_move_rate
  (ok / (attempts + the uncharged loss)),
  btl_streak (longest run of consecutive successful BTLs), btl_consecutive
  (successful BTLs from the first push until the first failure), gate_passes
  (all ball crossings of the gate below the crotch), btl_fail_* (why the
  failed passes failed: no_gate, bounces, wrong_hand, body, carry, lost_after).

Bodies: `body_kind` from DRIBBLE_BODY (v1 default, as tasks/dribble.py:
the base humanoid, run by bin/robolab_dribble, the round-1 skill whose mode 3
was the earlier between-the-legs attempt) or v3 (tasks/dribble_btl_v3.py:
the fingered v2 body, run by bin/robolab_dribble_btl, skills/dribble_btl.w).

    python playground/tasks/dribble_btl.py --trials 8 --params p.txt [--body v3] [--controller bin/x]
    python playground/tasks/dribble_btl.py --render out/dribble_btl --params p.txt --seed 3 --body v3
"""

import math
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dribble import BALL_R, DribbleTask, ROOT  # noqa: E402

CARRY_S = 0.05      # s of upward push from below the ball's equator in one touch
CARRY_FORCE = 0.5   # ... counted while the hand's upward force exceeds this (ball weights)
CARRY_DZ = -0.3     # ... and its contact point lies this far below the centre (ball radii)
HOLD_S = 0.35       # s: a single touch longer than this is holding the ball
BOTH_S = 0.03       # s: both hands on the ball together longer than this
THIGH_R = 0.06
ARRIVE_Z = 0.62     # pass log: where a pass's ball rises through this centre height after its bounce
BTL_MIN = 10        # BTL attempts a 15 s rollout is expected to make (the rate's least denominator)
# The lunge the body starts in (left lead: the lead foot's ankle at LEAD_FOOT,
# the back foot's at BACK_FOOT, x forward, y left, from the pelvis) and the
# pelvis height it is held at: a through-the-legs lunge is lower than the
# dribble task's athletic crouch. The skill may step into a lunge of its own.
PELVIS_BTL = float(os.environ.get("DRIBBLE_BTL_PELVIS", "0.72"))
LEAD_FOOT = tuple(float(v) for v in os.environ.get("DRIBBLE_BTL_LEAD", "0.40,0.28").split(","))
BACK_FOOT = tuple(float(v) for v in os.environ.get("DRIBBLE_BTL_BACK", "-0.55,-0.15").split(","))
ANKLE_Z = 0.078
LEG = ("hip_flex", "hip_abd", "hip_rot", "knee", "ankle")


class DribbleBtlTask(DribbleTask):
    name = "dribble_btl"
    body_kind = os.environ.get("DRIBBLE_BODY", "v1")
    pelvis_height = PELVIS_BTL

    @property
    def controller(self):
        if self.body_kind == "v1":
            return None  # bin/robolab_dribble_btl would be the default; the arena passes --controller
        return os.path.join(ROOT, "bin", "robolab_dribble_btl")

    def xml_extras(self):
        # the dribble task's home disk marks the one-hand dribble's spot, not
        # this drill's: keep the site (sensors), hide it
        out = super().xml_extras()
        out["extra_world"] = out["extra_world"].replace('rgba="0.2 0.3 0.8 0.15"', 'rgba="0.2 0.3 0.8 0"')
        return out

    # ---- episode ---------------------------------------------------------

    def stance_qpos(self, m, d):
        """The dribble task's start (trunk lean, guard, ball held over home),
        with the legs in the lunge: each ankle placed by damped least squares
        on MuJoCo's own kinematics, the foot flat on the floor."""
        super().stance_qpos(m, d)
        for side, (x, y) in (("l", LEAD_FOOT), ("r", BACK_FOOT)):
            self.place_foot(m, d, side, x, y)
        self.solve_hold(m, d, np.array([self.home[0], self.home[1], self.hold_z()]))

    def hold_z(self):
        return 0.99 - (0.80 - self.pelvis_height)

    def place_foot(self, m, d, side, x, y):
        adr = [m.jnt_qposadr[m.joint(f"{side}_{j}").id] for j in LEG]
        rng = [m.jnt_range[m.joint(f"{side}_{j}").id] for j in LEG]

        def res(q):
            d.qpos[adr] = q
            mujoco.mj_kinematics(m, d)
            a = d.body(f"{side}_foot").xpos
            R = d.body(f"{side}_foot").xmat.reshape(3, 3)
            return np.array([a[0] - x, a[1] - y, a[2] - ANKLE_Z, 0.3 * R[0, 2], 0.3 * R[1, 2]])
        q = np.array([0.5, 0.1, 0.0, 0.8, -0.3])
        r = res(q)
        lam = 1e-3
        for _ in range(150):
            J = np.zeros((5, 5))
            for k in range(5):
                dq = np.zeros(5)
                dq[k] = 1e-5
                J[:, k] = (res(q + dq) - r) / 1e-5
            qn = q + np.linalg.solve(J.T @ J + lam * np.eye(5), -J.T @ r)
            qn = np.array([np.clip(v, lo + 0.01, hi - 0.01) for v, (lo, hi) in zip(qn, rng)])
            rn = res(qn)
            if rn @ rn < r @ r:
                q, r, lam = qn, rn, lam / 3
            else:
                lam *= 4
        d.qpos[adr] = q

    def reset(self, m, d):
        super().reset(m, d)
        self.legs = {s: [m.body(f"{s}_thigh").id, m.body(f"{s}_shin").id, m.body(f"{s}_foot").id] for s in "lr"}
        self.gate_prev = None
        self.gate_passes = []      # (t, u, z, move index or -1)
        self.gate_xyz = {}
        self.touch_t0 = {"r": None, "l": None}
        self.up_time = {"r": 0.0, "l": 0.0}
        self.both_t = 0.0
        self.carried = False
        self.carry_why = ""
        self.max_touch_s = 0.0
        self.max_up_s = 0.0
        self.max_both_s = 0.0
        self.n_floor = 0
        self.ktouch = []
        self.ball_vel_prev = None

    def on_command(self, m, d, cmd):
        if cmd.startswith("ktouch:"):
            # the controller's own report of a planned contact: hand, lateness, palm miss (x y z)
            self.ktouch.append((round(d.time, 3), *cmd.split(":")[1:]))
            return
        n = len(self.moves) if hasattr(self, "moves") else 0
        super().on_command(m, d, cmd)
        if hasattr(self, "moves") and len(self.moves) > n:
            mv = self.moves[-1]
            mv.update({"gate": None, "recv_t": None, "continued": None, "recv_carry": False, "touch0": False})

    # ---- geometry: the leg gate ----------------------------------------------

    def leg_chain(self, d, side):
        return [d.xpos[i] for i in self.legs[side]]

    @staticmethod
    def leg_point(chain, z):
        """xy of a leg's axis (hip -> knee -> ankle) at height z; the hip above it, the ankle below."""
        for a, b in zip(chain[:-1], chain[1:]):
            lo, hi = (a[2], b[2]) if a[2] < b[2] else (b[2], a[2])
            if lo <= z <= hi and hi - lo > 1e-9:
                f = (z - a[2]) / (b[2] - a[2])
                return (a + f * (b - a))[:2]
        if z >= max(c[2] for c in chain):
            return np.array(chain[0][:2])
        return np.array(chain[-1][:2])

    def gate_check(self, m, d, p, v):
        """Record a crossing of the leg gate by the ball centre (see the docstring)."""
        cl, cr = self.leg_chain(d, "l"), self.leg_chain(d, "r")
        z = float(p[2])
        pl, pr = self.leg_point(cl, z), self.leg_point(cr, z)
        g = pr - pl
        rel = np.array(p[:2]) - pl
        s = g[0] * rel[1] - g[1] * rel[0]
        prev = self.gate_prev
        self.gate_prev = s
        if prev is None or (s > 0) == (prev > 0):
            return
        gg = float(g @ g)
        if gg < 1e-6:
            return
        u = float(rel @ g) / gg
        crotch = min(cl[0][2], cr[0][2]) - THIGH_R
        normal = np.array([-g[1], g[0]]) / math.sqrt(gg)
        across = float(np.dot(v[:2], normal)) * (1.0 if s > 0 else -1.0)
        if not (0.0 < u < 1.0 and z + BALL_R < crotch and across > 0.3):
            return
        idx = -1
        for k, mv in enumerate(self.moves):
            if mv["released"] and mv["outcome"] is None:
                idx = k
                if mv.get("gate") is None:
                    mv["gate"] = (round(d.time, 3), round(u, 3), round(z, 3))
                break
        self.gate_passes.append((round(d.time, 3), round(u, 3), round(z, 3), idx))
        self.gate_xyz[round(d.time, 3)] = (float(p[0]), float(p[1]), z)

    def floor_gate_distance(self, d, x, y):
        """Distance (m) of a floor point from the segment joining the ankles."""
        a = np.array(d.xpos[self.legs["l"][2]][:2])
        b = np.array(d.xpos[self.legs["r"][2]][:2])
        p = np.array([x, y])
        t = float(np.clip((p - a) @ (b - a) / max(float((b - a) @ (b - a)), 1e-9), 0.0, 1.0))
        return float(np.linalg.norm(p - (a + t * (b - a))))

    # ---- the hand's contacts: carry, hold, two hands -----------------------------

    def hand_contacts(self, m, d, p):
        """Per hand: (normal force in ball weights, upward force on the ball in
        ball weights from contacts below CARRY_DZ radii under the centre)."""
        out = {"r": [0.0, 0.0], "l": [0.0, 0.0]}
        f6 = np.zeros(6)
        for i in range(d.ncon):
            con = d.contact[i]
            if con.geom1 == self.ball_geom:
                other, sgn = con.geom2, -1.0
            elif con.geom2 == self.ball_geom:
                other, sgn = con.geom1, 1.0
            else:
                continue
            side = self.hand_bodies.get(m.geom_bodyid[other])
            if side is None:
                continue
            mujoco.mj_contactForce(m, d, i, f6)
            fn = abs(f6[0])
            out[side][0] += fn / self.ball_w
            n = con.frame[:3]
            fz = sgn * fn * n[2]  # the normal force's vertical component on the ball
            if (con.pos[2] - p[2]) < CARRY_DZ * BALL_R and fz > 0.0:
                out[side][1] += fz / self.ball_w
        return out

    def carry_check(self, m, d, p):
        dt = m.opt.timestep
        hc = self.hand_contacts(m, d, p)
        on = {}
        for side in "rl":
            touch = hc[side][0] > 0.3
            on[side] = touch
            if touch:
                if self.touch_t0[side] is None:
                    self.touch_t0[side] = d.time
                    self.up_time[side] = 0.0
                dur = d.time - self.touch_t0[side]
                self.max_touch_s = max(self.max_touch_s, dur)
                if hc[side][1] > CARRY_FORCE:
                    self.up_time[side] += dt
                    self.max_up_s = max(self.max_up_s, self.up_time[side])
                if self.up_time[side] > CARRY_S:
                    self.flag_carry(d, f"{side} hand under the ball (carry)")
                if dur > HOLD_S:
                    self.flag_carry(d, f"{side} hand held the ball {dur:.2f} s")
            else:
                self.touch_t0[side] = None
        if on["r"] and on["l"]:
            self.both_t += dt
            self.max_both_s = max(self.max_both_s, self.both_t)
            if self.both_t > BOTH_S:
                self.flag_carry(d, "both hands on the ball")
        else:
            self.both_t = 0.0

    def flag_carry(self, d, why):
        if not self.carried:
            self.carried = True
            self.carry_why = f"{why} at t={d.time:.2f}"
        for mv in self.moves:
            if mv.get("recv_t") is not None and mv.get("continued") is None:
                mv["recv_carry"] = True

    # ---- per step -------------------------------------------------------------

    def before_step(self, m, d):
        if not hasattr(self, "ball_geom"):
            return
        self.now = d.time  # the parent's move_touch (called below) has no time argument
        n_events = len(self.events)
        super().before_step(m, d)
        if self.released_t is None or self.lost_t is not None:
            return
        p = d.xpos[self.ball_id]
        v = d.qvel[self.ball_dof:self.ball_dof + 3]
        self.gate_check(m, d, p, v)
        self.carry_check(m, d, p)
        if v[2] > 0.0 and p[2] >= ARRIVE_Z:
            for mv in self.moves:
                if mv["released"] and mv["bounces"] >= 1 and mv.get("arrive_xy") is None and mv["outcome"] is None:
                    mv["arrive_xy"] = (round(float(p[0]), 3), round(float(p[1]), 3))
        # catchability of a pass in flight after its bounce: the highest the
        # ball rises, and its horizontal speed (the last value is the speed
        # at the receiving touch, which settles the move)
        for mv in self.moves:
            if mv["released"] and mv["bounces"] >= 1 and mv["outcome"] is None:
                mv["rise_apex"] = max(mv.get("rise_apex", 0.0), float(p[2]))
                mv["recv_vh"] = float(math.hypot(v[0], v[1]))
        for e in self.events[n_events:]:
            if e[1] == "body":
                # a pass fails on a body contact in flight: after the pushing
                # hand released it (an arm brushing the ball during the push
                # is part of the push)
                for mv in self.moves:
                    if mv["released"] and mv["outcome"] is None:
                        mv["body_flight"] = mv.get("body_flight", 0) + 1
                        break
            if e[1] == "floor":
                for mv in self.moves:
                    if mv["released"] and mv["bounces"] == 1 and mv.get("bounce_gd") is None:
                        mv["bounce_gd"] = self.floor_gate_distance(d, e[2], e[3])
                        mv["bounce_xy"] = (round(e[2], 3), round(e[3], 3))
            if e[1] == "floor" and self.lost_t is None:
                # a legal bounce: every received pass whose dribble had to go on has
                for mv in self.moves:
                    if mv.get("recv_t") is not None and mv.get("continued") is None and e[0] > mv["recv_t"]:
                        mv["continued"] = True

    def move_touch(self, hand):
        # a released pass touched by the other hand before any bounce: a
        # failure (the parent only settles a move at its first touch after a
        # bounce). The pushing hand touching it again before the bounce is
        # the same push (its contact chatters as the ball leaves the palm).
        for mv in self.moves:
            if mv["released"] and mv["outcome"] is None and mv["bounces"] == 0 and hand != mv["hand"]:
                mv["outcome"] = "fail"
                mv["touch0"] = True
        before = [mv["outcome"] for mv in self.moves]
        super().move_touch(hand)
        for mv, was in zip(self.moves, before):
            if was is None and mv["outcome"] == "ok":
                mv["recv_t"] = self.now
        return None

    def lose(self, t, why):
        first = self.lost_t is None
        super().lose(t, why)
        if first:
            for mv in self.moves:
                if mv.get("recv_t") is not None and mv.get("continued") is None:
                    mv["continued"] = False

    # ---- metrics ------------------------------------------------------------

    def btl_verdict(self, mv):
        """(success, reason) for one settled move."""
        if mv["type"] == "D" or mv["recv"] == mv["hand"]:
            return False, "dribble"
        if mv.get("touch0"):
            return False, "touched_before_bounce"
        if mv["outcome"] != "ok":
            return False, "bounces_or_wrong_hand"
        if mv.get("gate") is None:
            return False, "no_gate"
        if mv.get("body_flight", 0) > 0:
            return False, "body"
        if mv.get("recv_carry"):
            return False, "carry"
        if mv.get("continued") is False:
            return False, "lost_after"
        return True, "ok"

    @staticmethod
    def legal_pass(mv):
        """A pass to the other hand that keeps every rule of a BTL except the gate."""
        return (mv["outcome"] == "ok" and not mv.get("touch0") and mv.get("body_flight", 0) == 0
                and not mv.get("recv_carry") and mv.get("continued") is not False)

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        settled = [mv for mv in self.moves if mv["outcome"] is not None]
        verdicts = [self.btl_verdict(mv) for mv in settled]
        ok = sum(1 for v in verdicts if v[0])
        passes = [mv for mv in settled if mv["recv"] != mv["hand"]]
        failed_pass = any(mv["outcome"] == "fail" for mv in passes)
        lost_extra = 1 if (self.lost_t is not None and not failed_pass) else 0
        tried = len(passes) + lost_extra
        opp = max(tried, BTL_MIN)
        pv = [v for mv, v in zip(settled, verdicts) if mv["recv"] != mv["hand"]]
        streak = best = 0
        for v in pv:
            streak = streak + 1 if v[0] else 0
            best = max(best, streak)
        run = 0
        for v in pv:
            if not v[0]:
                break
            run += 1
        out["btl_ok"] = ok
        out["btl_attempts"] = len(passes)
        out["btl_opportunities"] = opp
        out["btl_tried"] = tried
        out["btl_rate"] = round(ok / opp, 4) if opp else 0.0
        out["btl_move_rate"] = round(ok / tried, 4) if tried else 0.0
        out["btl_streak"] = best
        out["btl_consecutive"] = run
        # legal passes (every BTL rule but the gate: one bounce, the other
        # hand next and legally, nothing else hit, the dribble goes on) and
        # the longest run of them; whether the first pass was a good BTL
        legal = [self.legal_pass(mv) for mv in settled if mv["recv"] != mv["hand"]]
        run_l = best_l = 0
        for v in legal:
            run_l = run_l + 1 if v else 0
            best_l = max(best_l, run_l)
        out["pass_streak"] = best_l
        out["first_btl_ok"] = bool(pv and pv[0][0])
        out["gate_passes"] = len(self.gate_passes)
        gds = [mv["bounce_gd"] for mv in self.moves if mv["recv"] != mv["hand"] and mv.get("bounce_gd") is not None]
        out["bounce_gate_dist"] = round(float(np.mean(gds)), 3) if gds else 1.0
        reasons = {}
        for mv, v in zip(settled, verdicts):
            if not v[0] and v[1] != "dribble":
                reasons[v[1]] = reasons.get(v[1], 0) + 1
        for k, n in reasons.items():
            out["btl_fail_" + k] = n
        out["ball_lost"] = self.lost_t is not None
        out["carried"] = bool(self.carried)
        out["carry_why"] = self.carry_why or None
        out["max_touch_s"] = round(self.max_touch_s, 3)
        out["max_up_s"] = round(self.max_up_s, 3)
        out["max_both_s"] = round(self.max_both_s, 3)
        out["pass_log"] = [{"k": mv["type"] + mv["hand"], "t": mv["t"], "released": mv["released"],
                             "outcome": mv["outcome"], "gate": mv.get("gate") is not None, "body": mv.get("body_flight", 0),
                             "bounce_xy": mv.get("bounce_xy"), "bounce_gd": mv.get("bounce_gd"),
                             "arrive_xy": mv.get("arrive_xy"), "miss": mv.get("miss"),
                             "rise_apex": mv.get("rise_apex"), "recv_vh": mv.get("recv_vh"),
                             "ok": mv["outcome"] is not None and self.btl_verdict(mv)[0]}
                            for mv in self.moves if mv["recv"] != mv["hand"]]
        out["move_log"] = [{"k": mv["type"] + mv["hand"], "t": mv["t"], "released": mv["released"],
                             "outcome": mv["outcome"], "arrive_xy": mv.get("arrive_xy"), "pass": mv["recv"] != mv["hand"],
                             "rise_apex": mv.get("rise_apex")}
                            for mv in self.moves]
        out["btl_log"] = [{"t": mv["t"], "k": mv["type"] + mv["hand"], "ok": v[0], "why": v[1], "gate": mv.get("gate")}
                          for mv, v in zip(settled, verdicts)]
        return out

    def score(self, metrics):
        """Practice objective (not the trial's metric): the rate and the good
        BTLs, with dense shaping for passes that nearly work: gate crossings,
        passes the other hand received after one bounce, the rising ball's miss
        of the receiving palm, time in control; ball-body hits cost."""
        mv = metrics.get("moves", {})
        s = 10.0 * metrics.get("btl_rate", 0.0) + 1.0 * metrics.get("btl_ok", 0)
        s += 0.5 * min(metrics.get("gate_passes", 0), 20)
        s += 0.5 * sum(mv.get(k, {}).get("ok", 0) for k in "XB")
        for k in "XB":
            if mv.get(k, {}).get("catch_miss") is not None:
                s -= 2.0 * mv[k]["catch_miss"]
        s -= 0.3 * min(metrics.get("body_hits", 0), 10)
        s -= 1.0 * metrics.get("bounce_gate_dist", 1.0)
        s += 0.2 * metrics.get("controlled_s", 0.0)
        if metrics.get("carried"):
            s -= 20.0
        return s

    # ---- presentation ------------------------------------------------------------

    def camera(self, m, d, cam):
        # three-quarter front view from the right, low: the gap between the
        # feet and the front thigh the ball passes under are in view
        cam.lookat[:] = [0.12, 0.0, 0.42]
        cam.distance = 2.4
        cam.azimuth = 150
        cam.elevation = -10

    def title(self):
        return "robolab: between-the-legs dribble (pivot muscle humanoid)"


TASK = DribbleBtlTask


# ---- trials and render ---------------------------------------------------------

def _trial(job):
    seed, params, seconds, body, controller = job
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from bridge import Sim
    task = DribbleBtlTask()
    task.seed = seed
    if body:
        task.body_kind = body
    sim = Sim(task, params=params, controller=controller)
    res = sim.run(seconds)
    res["seed"] = seed
    return res


def trials(params, seeds, seconds=15.0, workers=3, body=None, controller=None):
    from multiprocessing import Pool
    with Pool(workers) as pool:
        runs = pool.map(_trial, [(s, params, seconds, body, controller) for s in seeds])
    ok = sum(r["btl_ok"] for r in runs)
    opp = sum(r["btl_opportunities"] for r in runs)
    att = sum(r["btl_tried"] for r in runs)
    reasons = {}
    for r in runs:
        for k, v in r.items():
            if k.startswith("btl_fail_"):
                reasons[k[9:]] = reasons.get(k[9:], 0) + v
    return {
        "seeds": list(seeds), "seconds": seconds,
        "btl_ok": ok, "btl_opportunities": opp, "btl_attempts": att,
        "pooled_rate": round(ok / opp, 4) if opp else 0.0,
        "pooled_move_rate": round(ok / att, 4) if att else 0.0,
        "mean_rate": round(float(np.mean([r["btl_rate"] for r in runs])), 4),
        "streak_max": max(r["btl_streak"] for r in runs),
        "streak_median": float(np.median([r["btl_streak"] for r in runs])),
        "carried": sum(1 for r in runs if r["carried"]),
        "fail_reasons": reasons,
        "runs": [{k: r.get(k) for k in ("seed", "btl_rate", "btl_ok", "btl_opportunities", "btl_streak", "lost",
                                        "carry_why", "gate_passes", "body_hits")} for r in runs],
    }


def render(params, seed, seconds, prefix, body=None, controller=None, gif_mb=6.0, sheet_times=None, camera=None,
           slow=None):
    """One seeded run rendered from the three-quarter front camera, 960 x 720:
    the ball's last 0.8 s as a fading trail (blue while a pass is in flight),
    a green marker where it crossed between the legs, the move in progress in
    large type with the tally. Writes <prefix>.mp4, <prefix>.gif (shrunk until
    it fits gif_mb) and <prefix>_sheet.png (the first two consecutive good
    BTLs, push to catch; or frames at `sheet_times`). `slow` = (t0, t1, k)
    appends a k-times slow-motion replay of t0..t1 to the video and gif."""
    from collections import deque
    from PIL import Image, ImageDraw, ImageFont
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from bridge import Sim
    from render import Recorder
    try:
        big = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 32)
        small = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 18)
    except OSError:
        big = small = ImageFont.load_default()
    task = DribbleBtlTask()
    task.seed = seed
    if body:
        task.body_kind = body
    if camera:
        task.camera = camera
    sim = Sim(task, params=params, controller=controller)
    colors = {"D": (0.95, 0.95, 0.95), "X": (1.0, 0.55, 0.1), "B": (0.3, 0.6, 1.0)}

    def label_of(mv):
        if mv["type"] == "D":
            return f"dribble {mv['hand']}"
        return f"between the legs {mv['hand']} -> {mv['recv']}"

    class TrailRecorder(Recorder):
        def __init__(self, sim):
            super().__init__(sim, width=960, height=720)
            self.trail = deque()
            base = self.renderer.update_scene

            def update_scene(data, camera, scene_option=None):
                if scene_option is None:
                    base(data, camera)
                else:
                    base(data, camera, scene_option=scene_option)
                self.add_marks()
            self.renderer.update_scene = update_scene

        def maybe_capture(self, sim):
            if getattr(task, "released_t", None) is not None:
                self.trail.append((sim.d.time, sim.d.body("ball").xpos.copy(), task.open_move_type()))
            while self.trail and sim.d.time - self.trail[0][0] > 0.8:
                self.trail.popleft()
            super().maybe_capture(sim)

        def add_marks(self):
            scn = self.renderer.scene
            now = self.sim.d.time
            for t, p, kind in list(self.trail)[::3]:
                if scn.ngeom >= scn.maxgeom:
                    break
                a = max(0.0, 1.0 - (now - t) / 0.8)
                rgba = np.array([*colors.get(kind, colors["D"]), 0.15 + 0.6 * a], dtype=np.float32)
                mujoco.mjv_initGeom(scn.geoms[scn.ngeom], mujoco.mjtGeom.mjGEOM_SPHERE, np.array([0.022, 0, 0]),
                                    p.astype(np.float64), np.eye(3).flatten(), rgba)
                scn.ngeom += 1
            for t, u, z, idx in getattr(task, "gate_passes", []):
                if now - t > 1.2 or scn.ngeom >= scn.maxgeom:
                    continue
                pos = np.array(task.gate_xyz.get(t, (0, 0, z)), dtype=np.float64)
                a = max(0.0, 1.0 - (now - t) / 1.2)
                mujoco.mjv_initGeom(scn.geoms[scn.ngeom], mujoco.mjtGeom.mjGEOM_SPHERE, np.array([0.05, 0, 0]),
                                    pos, np.eye(3).flatten(), np.array([0.2, 0.9, 0.3, 0.6 * a], dtype=np.float32))
                scn.ngeom += 1

        def capture(self, sim):
            super().capture(sim)
            moves = task.moves
            label = label_of(moves[-1]) if moves else "set in the lunge"
            kind = moves[-1]["type"] if moves else "D"
            done = [mv for mv in moves if mv["outcome"] is not None]
            good = sum(1 for mv in done if task.btl_verdict(mv)[0])
            run = best = 0
            for mv in done:
                run = run + 1 if task.btl_verdict(mv)[0] else 0
                best = max(best, run)
            tally = f"through the legs {good}/{len(done)}   in a row {run} (best {best})"
            if getattr(task, "lost_t", None) is not None:
                tally += "   ball lost"
            im = Image.fromarray(self.frames[-1])
            dr = ImageDraw.Draw(im, "RGBA")
            col = tuple(int(255 * c) for c in colors.get(kind, colors["D"]))
            dr.rectangle([8, 96, 640, 176], fill=(15, 18, 24, 150))
            dr.text((20, 100), label.upper(), font=big, fill=col + (255,))
            dr.text((20, 146), tally, font=small, fill=(225, 230, 238, 255))
            self.frames[-1] = np.asarray(im)

    rec = TrailRecorder(sim)
    # (frames are captured on control ticks, 1 / control_dt per second: a
    # replay slower than that over 60 fps would skip frames)
    k = min(int(slow[2]), int(1.0 / task.control_dt / 60.0)) if slow else 1
    rec.fps = 60 * k  # capture rate (sim time); written at 60 fps
    res = sim.run(seconds, recorder=rec)
    rec.fps = 60
    frames = rec.frames
    if slow:
        real = frames[::k]
        replay = []
        for i in range(int(slow[0] * 60 * k), min(len(frames), int(slow[1] * 60 * k))):
            im = Image.fromarray(frames[i])
            ImageDraw.Draw(im, "RGBA").text((rec.width - 330, 20), f"replay {k}x slower", font=big, fill=(255, 220, 80, 255))
            replay.append(np.asarray(im))
        rec.frames = real + [real[-1]] * 20 + replay
    rec.write_mp4(prefix + ".mp4")
    for scale, every in ((0.5, 2), (0.42, 3), (0.36, 3), (0.32, 4), (0.28, 4), (0.25, 5)):
        rec.write_gif(prefix + ".gif", scale=scale, every=every)
        if os.path.getsize(prefix + ".gif") <= gif_mb * 1e6:
            break
    rec.frames = frames[::k] if slow else frames
    shots = []
    if sheet_times:
        shots = [(t, f"t={t:.2f}s") for t in sheet_times]
    else:
        ms = [mv for mv in task.moves if mv["outcome"] is not None]
        pick = next((i for i in range(len(ms) - 1) if task.btl_verdict(ms[i])[0] and task.btl_verdict(ms[i + 1])[0]), None)
        if pick is not None:
            for j in (pick, pick + 1):
                t0 = ms[j]["t"] - 0.04
                t1 = ms[j + 1]["t"] if j + 1 < len(ms) else ms[j]["t"] + 0.5
                for k in range(6):
                    t = t0 + (t1 - t0) * k / 5
                    shots.append((t, f"{label_of(ms[j])}  t={t:.2f}s"))
    if shots:
        w, h = int(rec.width * 0.4), int(rec.height * 0.4)
        cols = 6
        rows = (len(shots) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * h), (255, 255, 255))
        for k, (t, label) in enumerate(shots):
            i = min(len(rec.frames) - 1, int(round(t * rec.fps)))
            im = Image.fromarray(rec.frames[i]).resize((w, h))
            ImageDraw.Draw(im).text((8, h - 30), label, font=small, fill=(20, 20, 20))
            sheet.paste(im, ((k % cols) * w, (k // cols) * h))
        sheet.save(prefix + "_sheet.png")
    return res


def pass_score(pl, spot):
    """Dense quality of one logged pass: gate crossing, reception, leg hits,
    the bounce's distance from the ankle-to-ankle segment and how far from
    the receiving hand's spot the ball rises through ARRIVE_Z."""
    if pl is None or not pl["released"]:
        return -4.0
    s = 2.0 * pl["gate"] + 2.0 * (pl["outcome"] == "ok") - 0.5 * min(pl["body"], 4)
    s -= 2.0 * (pl["bounce_gd"] if pl["bounce_gd"] is not None else 1.0)
    if pl["arrive_xy"] is None:
        s -= 3.0
    else:
        s -= 3.0 * math.hypot(pl["arrive_xy"][0] - spot[0], pl["arrive_xy"][1] - spot[1])
    return s


CATCH_APEX = 0.72   # catchability: a pass should rise at least this high after its bounce (centre, m)
CATCH_VH = 1.3      # ... and reach the receiving hand no faster than this horizontally (m/s)


def catchability(pl):
    """How catchable a pass is: its rise after the bounce against CATCH_APEX
    and its horizontal speed at the receiving touch against CATCH_VH."""
    if pl is None or not pl["released"] or pl.get("rise_apex") is None:
        return -2.0
    s = -4.0 * max(0.0, CATCH_APEX - pl["rise_apex"])
    if pl.get("recv_vh") is not None:
        s -= 1.5 * max(0.0, pl["recv_vh"] - CATCH_VH)
    return s


def spots_of(params):
    """(lead hand's spot, back leg hand's spot) from the params (skills/dribble_btl.w defaults)."""
    ly = -1.0 if params.get("st_lead", 0.0) > 0.5 else 1.0
    lead = (params.get("bt_bx", -0.15), ly * params.get("bt_by", 0.44))
    back = (params.get("bt_fx", 0.35), ly * params.get("bt_fy", -0.4))
    return lead, back


def catch_score(ml, spot):
    """A catch dribble (the move after a pass, by the receiving hand): it
    must bounce once and come back to the same hand, rising through ARRIVE_Z
    near the hand's spot."""
    if ml is None or not ml["released"]:
        return -4.0
    s = 2.0 * (ml["outcome"] == "ok")
    if ml["arrive_xy"] is None:
        return s - 3.0
    return s - 3.0 * math.hypot(ml["arrive_xy"][0] - spot[0], ml["arrive_xy"][1] - spot[1])


def cycle_score(r, params):
    """Mode 7 (pass, catch dribble, pass back): half the first pass, the
    catch after it and the return pass."""
    lead, back = spots_of(params)
    ml = r["move_log"]
    passes = [m for m in ml if m["pass"]]
    s = 0.5 * pass_score(r["pass_log"][0] if r["pass_log"] else None, lead)
    i = ml.index(passes[0]) if passes else None
    catch = ml[i + 1] if i is not None and i + 1 < len(ml) and not ml[i + 1]["pass"] else None
    s += catch_score(catch, lead)
    s += pass_score(r["pass_log"][1] if len(r["pass_log"]) > 1 else None, back)
    return s


def chain_score(r, params, n=3, catch=0.0):
    """The first n passes in sequence (right, left, right, ...): each pass's
    dense score plus 3 for a complete BTL; the later passes weigh 1.5.
    catch > 0 adds each pass's catchability at that weight."""
    lead, back = spots_of(params)
    pls = r["pass_log"]
    s = 0.0
    for k in range(n):
        pl = pls[k] if len(pls) > k else None
        spot = lead if k % 2 == 0 else back
        s += (1.0 if k == 0 else 1.5) * (pass_score(pl, spot) + 3.0 * bool(pl and pl["ok"]) + catch * catchability(pl))
    return s


def _scored(job):
    seed, params, seconds, body, controller, objective = job
    r = _trial(job[:5])
    if objective == "chain":
        return chain_score(r, params), r
    if objective == "chain4":
        return chain_score(r, params, 4), r
    if objective == "catch4":
        return chain_score(r, params, 4, catch=1.0), r
    if objective == "cycle":
        return cycle_score(r, params), r
    if objective == "btl1":
        # the first pass, complete: through the legs, caught, the dribble goes on
        lead, back = spots_of(params)
        pl = r["pass_log"][0] if r["pass_log"] else None
        return pass_score(pl, lead) + 3.0 * bool(pl and pl["ok"]), r
    if objective in ("pass1", "pass2"):
        k = 0 if objective == "pass1" else 1
        pl = r["pass_log"][k] if len(r["pass_log"]) > k else None
        lead, back = spots_of(params)
        return pass_score(pl, lead if k == 0 else back) + (pass_score(r["pass_log"][0], lead) if k == 1 and r["pass_log"] else -4.0) * (k == 1) * 0.5, r
    return DribbleBtlTask().score(r), r


def practice(a, params):
    """CMA-ES (practice.py's) over the tunables named by --only, each candidate
    scored as the mean practice score over --seeds (a multi-seed score, so the
    search cannot win by fitting one trajectory). Writes the best candidate to
    --out, in the params-file format, whenever it improves."""
    import time
    from multiprocessing import get_context
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import practice as pr
    seeds = [int(x) for x in a.seeds.split(",")]
    body = a.body or "v3"
    ctl = a.controller
    tun = {t[0]: t for t in pr.describe("dribble_btl_v3" if body == "v3" else "dribble_btl", params)}
    names = a.only.split(",")
    lo = np.array([tun[n][2] for n in names])
    hi = np.array([tun[n][3] for n in names])
    x0 = np.array([(params.get(n, tun[n][1]) - tun[n][2]) / (tun[n][3] - tun[n][2]) for n in names]).clip(0, 1)

    def to_params(x):
        p = dict(params)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    def score_all(pool, xs):
        jobs = [(sd, to_params(x), a.seconds, body, ctl, a.objective) for x in xs for sd in seeds]
        res = pool.map(_scored, jobs)
        k = len(seeds)
        out = []
        for i in range(len(xs)):
            rows = res[i * k:(i + 1) * k]
            ok = sum(r[1]["btl_ok"] for r in rows)
            tried = sum(r[1]["btl_tried"] for r in rows)
            out.append((float(np.mean([r[0] for r in rows])), f"{ok}/{tried}", [r[1]["btl_streak"] for r in rows]))
        return out

    es = pr.CMA(x0, a.sigma, a.popsize or None, seed=a.cma_seed)
    t0 = time.time()
    with get_context("spawn").Pool(a.workers) as pool:
        base = score_all(pool, [x0])[0]
        best = (base[0], x0.copy(), base[1], base[2])
        print(f"gen 0 score {base[0]:.3f} btl {base[1]} streaks {base[2]}", flush=True)
        for g in range(a.gens):
            xs = es.ask()
            res = score_all(pool, xs)
            scores = [r[0] for r in res]
            es.tell(xs, [sc - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for sc, x in zip(scores, xs)])
            k = int(np.argmax(scores))
            if scores[k] > best[0]:
                best = (scores[k], np.clip(xs[k], 0, 1), res[k][1], res[k][2])
                write_params(a.out, to_params(best[1]), f"practice score {best[0]:.3f}, btl {best[2]} on seeds {seeds}")
            print(f"gen {g + 1} best {best[0]:.3f} {best[2]} gen-best {scores[k]:.3f} {res[k][1]} {res[k][2]} "
                  f"sigma {es.sigma:.3f} ({time.time() - t0:.0f}s)", flush=True)


def write_params(path, params, note):
    with open(path, "w") as f:
        f.write(f"# robolab dribble_btl practice: {note}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def main():
    import argparse
    import json
    ap = argparse.ArgumentParser(description="between-the-legs dribble trials")
    ap.add_argument("--trials", type=int, default=0)
    ap.add_argument("--seeds", default="")
    ap.add_argument("--params")
    ap.add_argument("--set", default="")
    ap.add_argument("--seconds", type=float, default=15.0)
    ap.add_argument("--body")
    ap.add_argument("--controller")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--out")
    ap.add_argument("--render", help="render one run (--seed) to <prefix>.mp4/.gif/_sheet.png")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--sheet-times", default="", help="comma-separated times for the sheet")
    ap.add_argument("--slow", default="", help="t0,t1,k: append a k-times slow-motion replay of t0..t1")
    ap.add_argument("--practice", action="store_true", help="multi-seed CMA-ES over --only (see practice())")
    ap.add_argument("--only", default="")
    ap.add_argument("--gens", type=int, default=30)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--popsize", type=int, default=0)
    ap.add_argument("--cma-seed", type=int, default=7)
    ap.add_argument("--objective", default="full", help="practice objective: full (the shaped score), pass1, pass2, cycle, btl1, chain, chain4, catch4 (chain4 plus catchability)")
    a = ap.parse_args()
    params = {}
    if a.params:
        for line in open(a.params):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    if a.practice:
        return practice(a, params)
    if a.render:
        times = [float(t) for t in a.sheet_times.split(",")] if a.sheet_times else None
        slow = tuple(float(v) for v in a.slow.split(",")) if a.slow else None
        res = render(params, a.seed, a.seconds, a.render, a.body, a.controller, sheet_times=times, slow=slow)
        print({k: res.get(k) for k in ("btl_rate", "btl_ok", "btl_opportunities", "btl_streak", "lost", "carry_why")})
        print(res.get("btl_log"))
        return
    seeds = [int(s) for s in a.seeds.split(",")] if a.seeds else list(range(1, (a.trials or 8) + 1))
    res = trials(params, seeds, a.seconds, a.workers, a.body, a.controller)
    text = json.dumps(res, indent=1)
    print(text)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
