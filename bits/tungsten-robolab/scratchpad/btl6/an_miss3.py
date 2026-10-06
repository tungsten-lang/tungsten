"""Stage-3 no-touch anatomy: features of the starts whose stage-3 stroke never touches the ball (chain from stage 3, G tables)."""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
act = pickle.load(open("out/btl6/val_verdicts_G.pkl", "rb"))
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
rows = []
for sd in range(84001, 84841):
    r = act.get(sd)
    if r is None or len(r["ok"]) < 2 or not (r["ok"][0] and r["ok"][1]): continue
    fl = r["fl"]
    if not (fl.get(2) and fl[2]["touch"] and fl[2]["bounced"] and fl[2]["gate"] and fl[2]["bfl"] == 0): continue
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    st = ch.prep(rec, 3)
    if st is None: continue
    run = ch.run(st, upto=3)
    if run is None: continue
    ss = run["stage"][3]
    oc = Ob.eval_stage(run, 3)
    if oc is None: continue
    J, sm, pre, bfl = oc
    touch = bool(sm.get("touch"))
    pos, cf, palm = run["out"]["pos"], run["out"]["cf"], run["out"]["palm"]
    t0 = ss["t0"]
    dmin = float(np.min(np.linalg.norm(palm[t0:, 0] - pos[t0:], axis=1)))
    rows.append((sd, touch, ss["u"], ss["cr"], dmin, J))
n = len(rows); miss = [r for r in rows if not r[1]]; hit = [r for r in rows if r[1]]
print("starts", n, "no touch", len(miss))
U = lambda rs: np.array([r[2] for r in rs])
print("u (x, y, wrist flex, shoulder abd, elbow) mean touch:", U(hit).mean(0).round(2), " no touch:", U(miss).mean(0).round(2))
print("fraction clamped (|u| = 2.5) per feature: touch", (np.abs(U(hit)) > 2.499).mean(0).round(2), " no touch", (np.abs(U(miss)) > 2.499).mean(0).round(2))
CR = lambda rs: np.array([[r[3][1], r[3][2], r[3][0], r[3][3]] for r in rs])
print("crossing x, y, t, vz mean touch:", CR(hit).mean(0).round(3), "sd", CR(hit).std(0).round(3), " no touch:", CR(miss).mean(0).round(3), "sd", CR(miss).std(0).round(3))
print("closest approach (m) of the palm for no-touch starts: quantiles", np.quantile([r[4] for r in miss], [0.1, 0.25, 0.5, 0.75, 0.9]).round(3))
# by number of clamped features
for k in range(0, 6):
    sel = [r for r in rows if int((np.abs(r[2]) > 2.499).sum()) == k]
    if sel: print(f"  {k} clamped features: n {len(sel)}, no touch {sum(1 for r in sel if not r[1])} ({100*sum(1 for r in sel if not r[1])/len(sel):.0f} %)")
print("---- no-touch starts by reachability of the incoming ball (crossing y < 0.45 and x > -0.30 and vz > 0.5 = in reach)")
inreach = [r for r in miss if r[3][2] < 0.45 and r[3][1] > -0.30 and r[3][3] > 0.5]
weak = [r for r in miss if r[3][3] <= 0.5]
far = [r for r in miss if r[3][3] > 0.5 and not (r[3][2] < 0.45 and r[3][1] > -0.30)]
print("no touch:", len(miss), " of which weak (vz at the crossing <= 0.5):", len(weak), " out of reach with vz > 0.5:", len(far), " in reach but missed:", len(inreach))
allweak = [r for r in rows if r[3][3] <= 0.5]
print("all starts with a weak incoming ball (vz <= 0.5):", len(allweak), "of", n, "-> touched", sum(1 for r in allweak if r[1]))
