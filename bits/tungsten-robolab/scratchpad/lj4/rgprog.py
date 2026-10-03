"""RegimeIK (agent L4): long_jump_limits.IKProgram plus per-REGIME post-touchdown offsets, the harness twin of the M3 scheme.

LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP. The take-off program is the single robust program (e / c knots, gap knots, reflex gain). At the plant's TOUCHDOWN the measured touchdown
time T (seconds since the program's start = the penultimate touchdown) picks a regime: early (T < t1), late (T > t2), else normal (0). For the regimes 1 and 2, from the touchdown on,
every muscle's drive gets an offset de_r(tau) and its target contraction an offset dc_r(tau), tau = the time since the touchdown, linear between the knots tau_k (hold after the last):

    e(s)  += de_r(tau)          cs(s) += dc_r(tau)

(the base program is untouched for the normal regime and before the touchdown, so the pre-touchdown trajectory is the base program's). Genes: x in [0,1]: de = (x - 0.5) DE_SCALE, dc = (x - 0.5) DC_SCALE.
"""
import os
import sys
import numpy as np

os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import long_jump_limits as L  # noqa: E402

DE_SCALE = 0.5
DC_SCALE = 0.3
TAU_KNOTS = (0.0, 0.03, 0.06, 0.09)


def interp_rows(tab_rows, tau, knots):
    """Linear interpolation of a (nd, n) offset table at time tau after touchdown (hold before the first / after the last knot)."""
    if tau <= knots[0]:
        return tab_rows[0]
    if tau >= knots[-1]:
        return tab_rows[-1]
    j = 0
    while j + 1 < len(knots) and tau > knots[j + 1]:
        j += 1
    u = (tau - knots[j]) / (knots[j + 1] - knots[j])
    return tab_rows[j] + (tab_rows[j + 1] - tab_rows[j]) * u


class RegimeIK(L.IKProgram):
    def __init__(self, tab, h, td, g, kdc, kp, kd, gap0, end, rg=None):
        super().__init__(tab, h, td, g, kdc, kp, kd, gap0, end)
        self.rg = rg   # None, or {"t1","t2","knots","de":{r: (nd,n)},"dc":{r: (nd,n)}} in THIS program's muscle order

    def start(self, body, cap):
        super().start(body, cap)
        self.regime = 0
        self.t_touch = None

    def pick(self, t):
        if self.rg is None:
            return 0
        if t < self.rg["t1"]:
            return 1
        if t > self.rg["t2"]:
            return 2
        return 0

    def __call__(self, body, t, k):
        d = body.d
        s = t + self.shift
        if not self.td_seen:
            down = self.foot_force(body) > self.fmin
            if not down:
                self.lifted = True
            if down and self.lifted and s > 0.03:
                self.td_seen = True
                self.t_touch = t
                self.regime = self.pick(t)
                self.shift += self.td - s
                s = self.td
            elif s > self.td:
                self.shift -= s - self.td
                s = self.td
        self.s = s
        ids = body.act_ids
        c = (self.hi - d.actuator_length[ids]) / self.span
        cd = -d.actuator_velocity[ids] / self.span
        cs, vs, e, e1 = L.quintic_eval(self.tab, s, self.h, self.nk)
        if self.td_seen and self.regime and self.rg is not None and self.regime in self.rg["de"]:
            tau = t - self.t_touch
            e = e + interp_rows(self.rg["de"][self.regime], tau, self.rg["knots"])
            cs = cs + interp_rows(self.rg["dc"][self.regime], tau, self.rg["knots"])
        g = self.g if k > 0 else 0.0
        out = e + self.gap_err * e1 + self.kdc * g * self.kd * vs + g * (self.kp * (cs - c) - self.kd * cd)
        tab = self.tab
        if "pr" in tab:
            raise NotImplementedError("rotation feedback is not part of the robust program")
        if "ckc" in tab and not self.td_seen and s < self.td - tab["clt"]:
            z = min(float(d.site_xpos[self.site_toe][2]), float(d.site_xpos[self.site_heel][2]))
            if z < tab["clz"]:
                out = out + tab["ckc"] * (tab["clz"] - z)
        return out
