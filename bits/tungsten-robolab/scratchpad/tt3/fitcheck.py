import sys, numpy as np, glob, json
np.set_printoptions(precision=3, suppress=True, linewidth=220)
params = {l.split()[0]: float(l.split()[1]) for l in open("params/myo_tt_p2_r10_c3.txt") if l.strip() and not l.startswith("#")}
FH = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex"]
BH = ["bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_elbow", "bh_pro_sup", "bh_dev", "bh_wflex"]
d = sys.argv[1] if len(sys.argv) > 1 else "out/tt3/logs_rec_test"
for f in sorted(glob.glob(d + "/*.npz")):
    z = np.load(f)
    t, qfit, res, q, side, s = z["t"][:, 0], z["qfit"], z["res"][:, 0], z["q"], z["side"][:, 0], z["s"][:, 0]
    sd = int(side[-1])
    ask = np.array([params[k] for k in (BH if sd == 2 else FH)])
    i27 = int(np.argmin(np.abs(t - 0.27)))
    i45 = int(np.argmin(np.abs(t - 0.45)))
    print(f.split("/")[-1], "side", sd, "fit res median %.4f max %.4f" % (np.median(res), res.max()))
    print("   params ", ask)
    print("   qfit .27", qfit[i27], "s %.3f" % s[i27], " qfit .45", qfit[i45])
    print("   qmeas.27", q[i27], "   qmeas.45", q[i45])
