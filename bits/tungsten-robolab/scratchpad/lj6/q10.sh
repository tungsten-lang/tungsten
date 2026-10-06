#!/bin/sh
# Q10 (LABELLED beyond-human body, unlimited run-up): (1) K3 = H011 runner + TO1 (average of Rk2 g40 and Rk3 g10 / g20 / g30) + land_C2 + joint shift 0.10 on SELECTION; (2) landing retrain L1 on TO1's hand-overs
# (80 strong + 15 other pool states, record seed 34006, init land_C2, tail-q 0.1).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/q10.done
scratchpad/lj6/cand6.sh K3 out/lj6/TO1.txt scratchpad/lj4/progs/land_C2.txt 0.10 31001-31480
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
nice -n 10 .venv/bin/python scratchpad/lj6/ljx_risk.py --eval out/lj6/TO1.txt --captures "$(cat out/lj6/zh_all.txt)" --fmin 1.5 --workers 6 --lmax -1.0 --lw 1.0 --pw 3.5 --quiet --shift 0.10 --json out/lj6/zh_TO1.json > out/lj6/zh_TO1.txt 2>&1
nice -n 10 .venv/bin/python - <<'PY'
import json, numpy as np
rows=json.load(open("out/lj6/zh_TO1.json"))
ok=[r for r in rows if r["valid"] and not r["foul"] and r["s"]>0]
strong=sorted([r for r in ok if r["s"]>=7.3],key=lambda r:r["gap"]); rest=[r for r in ok if r["s"]<7.3]
rng=np.random.default_rng(11)
pick=[r["name"] for r in strong[::3]]
extra=[rest[i]["name"] for i in rng.choice(len(rest),15,replace=False)]
open("out/lj6/zh_ho.txt","w").write(",".join(pick+extra))
print("hand-over states:",len(pick),"strong +",len(extra),"others (legal %d, strong %d)"%(len(ok),len(strong)))
PY
INIT=out/lj4/land_C2.txt scratchpad/lj6/land6.sh L1 out/lj6/TO1.txt out/lj6/zh_ho.txt 34006 100000 0 --tail-q 0.1
echo done > out/lj6/q10.done
