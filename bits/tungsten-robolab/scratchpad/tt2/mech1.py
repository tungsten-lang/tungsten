"""When does the paddle leave the palm, and how does the arm sit, on the beyond arm vs the official arm (agent T2; diagnostic)."""
import numpy as np, sys, os, json
np.set_printoptions(precision=3, suppress=True, linewidth=200)
rungs = [int(x) for x in sys.argv[1].split(",")]
seeds = [int(x) for x in sys.argv[2].split(",")]
for s in seeds:
    print("== seed", s)
    for r in rungs:
        f = f"out/tt2/logs_r{r}/{s}.npz"
        if not os.path.exists(f): print("  rung", r, "no log"); continue
        z = np.load(f); L, X = z["L"], z["X"]; k = int(z["contact"])
        t = L[:, 0]; pe = np.linalg.norm(L[:, 25:28], axis=1); eff = L[:, 28]
        idx = [i for i in (5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 100) if i < len(t)]
        print(f"  rung {r}: contact row {k}, n rows {len(t)}, palm_err(t) at rows {idx}:", pe[idx])
        print(f"           first row with palm_err > 0.05: {np.argmax(pe > 0.05) if (pe > 0.05).any() else None}, > 0.5: {np.argmax(pe > 0.5) if (pe > 0.5).any() else None}; effort_act mean sq at rows:", eff[idx])
        print(f"           joints q(t) (elv,sh_elv,sh_rot,elbow,pro_sup,dev,flex) at rows 5,20,35:", X[[i for i in (5, 20, 35) if i < len(X)], :7].round(2).tolist())
        print(f"           pelvis x,y at rows 20, 35, 50:", L[[i for i in (20, 35, 50) if i < len(t)], 16:19].round(2).tolist())
