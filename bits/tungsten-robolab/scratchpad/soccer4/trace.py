"""Per-step trace of the soccer body's twist budget.
usage: trace.py <params> <seed> [controller] [seconds]  (env from MYO_SOCCER_ENV)"""
import math, os, sys, json
import numpy as np, mujoco
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask

params = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 2 and not line.startswith("#"):
        params[p[0]] = float(p[1])
for kv in os.environ.get("TRACE_SET", "").split(","):
    if "=" in kv:
        k, v = kv.split("="); params[k] = float(v)
seed = int(sys.argv[2])
ctl = sys.argv[3] if len(sys.argv) > 3 else None
secs = float(sys.argv[4]) if len(sys.argv) > 4 else None
every = int(os.environ.get("TRACE_EVERY", "5"))

rows = []
dbg = []
class T(MyoSoccerTask):
    def on_command(self, sim, cmd):
        if cmd.startswith("dbg:"):
            dbg.append((round(float(sim.d.time), 3), cmd[4:]))
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        m, d = sim.m, sim.d
        n = len(rows)
        self._k = getattr(self, "_k", 0) + 1
        if self._k % every:
            return
        pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
        yaw = math.atan2(pel[1, 0], pel[0, 0])
        out = {"t": round(float(d.time), 3), "lab": sim.label, "yaw": round(yaw, 3)}
        com = d.subtree_com[m.body("root").id]
        fcl = 0.5 * (d.xpos[m.body("calcn_l").id] + d.xpos[m.body("toes_l").id])
        out["comy_l"] = round(float(com[1] - fcl[1]), 3)
        out["comx_l"] = round(float(com[0] - fcl[0]), 3)
        tor = d.xmat[m.body("torso").id].reshape(3, 3)
        out["tpitch"] = round(math.atan2(tor[0, 1], tor[2, 1]), 3)
        out["ppitch"] = round(math.atan2(pel[0, 1], pel[2, 1]), 3)
        out["fe"] = round(float(d.qpos[m.jnt_qposadr[m.joint("flex_extension").id]]), 3)
        out["pz_h"] = round(float(d.xpos[m.body("pelvis").id][2]), 3)
        out["proll"] = round(math.atan2(-pel[2, 2], pel[1, 2]) if False else float(pel[2, 2]), 3)
        ct = sim.foot_contacts()
        for sd in "lr":
            cid = m.body("calcn_" + sd).id
            R = d.xmat[cid].reshape(3, 3)
            fy = math.atan2(R[1, 0], R[0, 0])
            v = np.zeros(6)
            mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, cid, v, 0)
            jr = m.joint("hip_rotation_" + sd)
            dof = m.jnt_dofadr[jr.id]
            # ground contacts of this foot: vertical torque about the COP, and capacity
            bodies = {cid, m.body("toes_" + sd).id}
            pts, fs = [], []
            f6 = np.zeros(6)
            for k in range(d.ncon):
                c = d.contact[k]
                b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
                if (b1 in bodies and b2 == 0) or (b2 in bodies and b1 == 0):
                    mujoco.mj_contactForce(m, d, k, f6)
                    fr = np.array(c.frame).reshape(3, 3)
                    fw = fr.T @ f6[:3]
                    if b1 in bodies:  # force on geom2 from geom1... make it force ON the foot
                        fw = -fw
                    pts.append(np.array(c.pos)); fs.append(fw)
            tz = cap = N = 0.0
            copl = 0.0
            if pts:
                P = np.array(pts); F = np.array(fs)
                N = float(np.sum(np.abs(F[:, 2])))
                cop = (np.abs(F[:, 2]) @ P) / max(N, 1e-9)
                r = P - cop
                tz = float(np.sum(r[:, 0] * F[:, 1] - r[:, 1] * F[:, 0]))
                cap = float(np.sum(np.abs(F[:, 2]) * np.hypot(r[:, 0], r[:, 1])))
                fc_ = 0.5 * (d.xpos[cid] + d.xpos[m.body("toes_" + sd).id])
                copl = float((cop - fc_) @ R[:, 2])  # along calcn z (body's right)
            out[sd] = {"load": round(ct[sd], 2), "fyaw": round(fy, 3), "fyawd": round(float(v[2]), 2),
                       "hrot": round(float(d.qpos[m.jnt_qposadr[jr.id]]), 3),
                       "hflex": round(float(d.qpos[m.jnt_qposadr[m.joint("hip_flexion_" + sd).id]]), 3),
                       "hadd": round(float(d.qpos[m.jnt_qposadr[m.joint("hip_adduction_" + sd).id]]), 3),
                       "hrot_tq": round(float(d.qfrc_actuator[dof] + d.qfrc_passive[dof]), 1),
                       "tz": round(tz, 1), "cap": round(cap, 1), "N": round(N, 0), "nc": len(pts),
                       "cop": round(copl, 3),
                       "sub": round(float(d.qpos[m.jnt_qposadr[m.joint("subtalar_angle_" + sd).id]]), 3)}
        rows.append(out)

task = T()
sim = MyoSim(task, params=params, controller=ctl, seed=seed, verbose=os.environ.get("TRACE_VERBOSE") == "1")
res = sim.run(secs)
keys = ["time", "plant_err", "t_plant", "plant_heel", "yaw_plant_deg", "ball_speed", "com_x_max", "bal1_s", "bal_l_tot", "bal_r_tot", "bal_l", "bal_r", "bal_s", "stand_time", "fallen", "goal", "t_touch", "strike_zone", "strike_medial_m", "yaw_touch_deg", "rmed_touch_deg", "n_steps", "ap_best_stand", "ap_start"]
print(json.dumps({k: res.get(k) for k in keys}))
outp = os.environ.get("TRACE_OUT")
if outp:
    json.dump({"res": {k: v for k, v in res.items() if k != "events"}, "events": res.get("events"), "rows": rows}, open(outp, "w"))
for t_, c_ in dbg[:: int(os.environ.get("DBG_STRIDE", "10"))]:
    print("DBG", t_, c_)
if os.environ.get("TRACE_PRINT", "1") == "1":
    for r in rows[:: int(os.environ.get("TRACE_STRIDE", "4"))]:
        l, rr = r["l"], r["r"]
        print(f'{r["t"]:6.2f} {r["lab"][:10]:10s} yaw {r["yaw"]:+.2f} cy {r["comy_l"]:+.3f} cx {r["comx_l"]:+.3f} pz {r["proll"]:+.2f} | L ld {l["load"]:.2f} fy {l["fyaw"]:+.2f} hf {l["hflex"]:+.2f} ha {l["hadd"]:+.2f} hr {l["hrot"]:+.2f} cop {l["cop"]:+.3f} sub {l["sub"]:+.2f} tq {l["hrot_tq"]:+6.1f} tz {l["tz"]:+6.1f}/{l["cap"]:5.1f} | R ld {rr["load"]:.2f} fy {rr["fyaw"]:+.2f} hr {rr["hrot"]:+.2f} tq {rr["hrot_tq"]:+6.1f} tz {rr["tz"]:+6.1f}/{rr["cap"]:5.1f}')
