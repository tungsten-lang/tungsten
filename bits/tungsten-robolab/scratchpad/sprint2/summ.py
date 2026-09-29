import re, sys
import numpy as np
cols=["tc","flight","step","th_td","th_lo","kn_td","kn_max","fz_mean","fz_peak","pitch_td","pitch_lo","pitch_rock","vz_lo"]
for fn in sys.argv[1:]:
    rows=[l.split() for l in open(fn) if re.match(r'\s*\d+\s+(ok|FALL)', l)]
    ok=[r for r in rows if r[1]=='ok']
    print(f"== {fn}: {len(ok)}/{len(rows)} survive; falls", [r[0]+"@"+r[2] for r in rows if r[1]!='ok'])
    if not ok: continue
    pk=[float(r[3]) for r in ok]; sd=[float(r[4]) for r in ok]
    print(f"   peak mean {np.mean(pk):.3f} min {np.min(pk):.3f} max {np.max(pk):.3f}  steady mean {np.mean(sd):.3f} min {np.min(sd):.3f}")
    print("   " + " ".join(f"{c}={np.mean([float(r[6+i]) for r in ok]):.3f}" for i,c in enumerate(cols)))
