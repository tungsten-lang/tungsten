"""Sensitivity of the contact to tiny state perturbations at the swing start (open-loop replay): joint-angle noise of size eps."""
import sys, glob
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P
CK = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/"
p = P.Probe()
m = p.sim.m
names = ["hip_flexion_r","hip_adduction_r","hip_rotation_r","knee_angle_r","ankle_angle_r","hip_flexion_l","hip_adduction_l","hip_rotation_l","knee_angle_l","ankle_angle_l","flex_extension","lat_bending","axial_rotation","subtalar_angle_r","subtalar_angle_l"]
adr = [m.jnt_qposadr[m.joint(n).id] for n in names]
def first(tr, lab): return next(i for i, r in enumerate(tr) if r["lab"] == lab)
rng = np.random.default_rng(3)
files = [CK + "p1base_n0_dx+0_dy+0_s5000.pkl.gz", CK + "p1base_n0_dx+0_dy+0_s5002.pkl.gz", CK + "p1base_n0.05_dx+0_dy+0_s5000.pkl.gz", CK + "p1base_n0.05_dx+0_dy+0_s5001.pkl.gz", CK + "p1base_n0.05_dx+0_dy+0_s5009.pkl.gz", CK + "p1base_n0.05_dx+0_dy+0_s5010.pkl.gz"]
print("eps = size of the joint-angle noise (uniform +-eps on 15 joints) at the swing start; 6 draws each; contact toe y / z (cm), ball speed, launch: mean (std) of the change from the unperturbed replay")
for f in files:
    pack = P.load(f)
    k0 = first(pack["trace"], "swing")
    r0 = P.contact_summary(p.run(pack, k0))
    print(f.split("/")[-1][:36], "base y %+.1f z %+.1f v %.2f launch %+.1f" % (100*r0["toe"][1], 100*r0["toe"][2], r0["ball_speed"], r0["launch"]))
    for eps in (0.0005, 0.002, 0.005, 0.01, 0.02):
        dy, dz, dv, dl = [], [], [], []
        for k in range(6):
            pk = dict(pack)
            st = [dict(s) for s in pack["state"]]
            q = st[k0]["qpos"].copy()
            for a in adr:
                q[a] += rng.uniform(-eps, eps)
            st[k0]["qpos"] = q
            pk["state"] = st
            r = p.run(pk, k0)
            c = P.contact_summary(r)
            if c.get("toe") is None:
                dy.append(np.nan); dz.append(np.nan); dv.append(np.nan); dl.append(np.nan); continue
            dy.append(100*(c["toe"][1]-r0["toe"][1])); dz.append(100*(c["toe"][2]-r0["toe"][2])); dv.append(c["ball_speed"]-r0["ball_speed"]); dl.append((c["launch"] or 0)-r0["launch"])
        f2 = lambda a: f"{np.nanmean(a):+6.1f} ({np.nanstd(a):4.1f})"
        print(f"    eps {eps:.4f}: dy cm {f2(dy)} dz cm {f2(dz)} dv {f2(dv)} dlaunch {f2(dl)}", flush=True)
