import sys, numpy as np
def table(fn, wins=((0.0, 0.03), (0.03, 0.06), (0.06, 0.10), (0.10, 0.15))):
    z = np.load(fn); A = z["A"]; cols = list(z["cols"]); c = lambda n: A[:, cols.index(n)]
    since = c("since_lift"); res = {}
    for lo, hi in wins:
        sel = (since >= lo) & (since < hi) & (since < 0.5)
        if not sel.any(): continue
        res[(lo, hi)] = dict(n=int(sel.sum()), knee=np.degrees(c("knee")[sel].mean()), kv=c("knee_v")[sel].mean(), hip_a=c("hip_a")[sel].mean(), coupling=c("tau_coupling")[sel].mean(),
                             musc=c("tau_mus")[sel].mean(), rf=-0.8 * c("r_rf_see.spring_force")[sel].mean(), vasti=-c("r_knee_neg_see.spring_force")[sel].mean(), passive=c("tau_joint_passive")[sel].mean())
    return res
for fn in sys.argv[1:]:
    print(fn)
    for (lo, hi), v in table(fn).items():
        print(f"  {lo*1000:3.0f}-{hi*1000:3.0f} ms (n={v['n']:3d}): knee {v['knee']:5.1f} deg v {v['kv']:5.2f} rad/s | hip acc {v['hip_a']:6.1f} | whip coupling {v['coupling']:6.1f} | flexors etc (fibre-side muscles) {v['musc']:6.1f} | rf chain {v['rf']:7.1f} | vasti chain {v['vasti']:7.1f} | joint passive {v['passive']:6.1f}")
