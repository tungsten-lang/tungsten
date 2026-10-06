"""ffeval (L7): harness evaluation of a take-off program whose gap error input is FED FORWARD with the penultimate-touchdown state (vx, vz, torso pitch, gap): the toe offset of legal
harness states is 80-90 % predictable from those (R2 0.8 with vx, vz, torso pitch), and the program's own authority over the plant toe through its gap input is +0.69 m per m of
gap error (TO1, pool A), so the effective gap error  gap_err + kappa x (cg (gap - gm) + cv (vx - vm) + cz (vz - zm) + ct (torso - tm))  can cancel the predictable part.
The coefficients come from the environment (FF_KAPPA, FF_CG, FF_CV, FF_CZ, FF_CT, FF_GM, FF_VM, FF_ZM, FF_TM). Everything else is scratchpad/lj6/ljx_risk.py --eval.
usage: ffeval.py <program.txt> <captures comma list file> --shift 0.15 [--json rows.json] [--workers N] [--quiet]"""
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, HERE + "/playground")
sys.path.insert(0, HERE + "/scratchpad/lj6")
os.environ.setdefault("MUJOCO_GL", "cgl")
import long_jump_limits as L  # noqa: E402
import long_jump_mine as M  # noqa: E402


class FFProgram(L.IKProgram):
    def start(self, body, cap):
        super().start(body, cap)
        e = os.environ
        kappa = float(e.get("FF_KAPPA", "0"))
        if kappa != 0.0:
            f = M.features(body, cap)          # sets the captured state again (the program starts from it)
            if e.get("FF_MODE", "full") == "edge":
                # one-sided: pull the plant toe back only when the predicted toe offset (harness units, toe_max - board) is above FF_THR
                off_pred = float(e["FF_B0"]) + float(e["FF_BG"]) * f["gap"] + float(e["FF_BV"]) * f["vx"] + float(e["FF_BZ"]) * f["vz"] + float(e["FF_BT"]) * f["torso"]
                over = max(0.0, off_pred - float(e["FF_THR"]))
                self.gap_err += -kappa * over / float(e.get("FF_AUTH", "0.69"))
            else:
                delta = (float(e["FF_CG"]) * (f["gap"] - float(e["FF_GM"])) + float(e["FF_CV"]) * (f["vx"] - float(e["FF_VM"]))
                         + float(e["FF_CZ"]) * (f["vz"] - float(e["FF_ZM"])) + float(e["FF_CT"]) * (f["torso"] - float(e["FF_TM"])))
                lim = float(e.get("FF_LIM", "9"))
                self.gap_err += kappa * max(-lim, min(lim, delta))


L.IKProgram = FFProgram

import ljx_risk  # noqa: E402  (its _eworker builds L.IKProgram at call time: the subclass)

if __name__ == "__main__":
    # ljx_risk.main with the arguments as given
    ljx_risk.main()
