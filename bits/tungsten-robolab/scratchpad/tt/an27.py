import json, numpy as np
np.set_printoptions(precision=3,suppress=True,linewidth=160)
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r and r.get("q_corr")]
names=["elv_angle","shoulder_elv","shoulder_rot","elbow","pro_sup","deviation","flexion","ax_rot"]
for side in (1,2):
    Q=np.array([r["q_corr"] for r in rows if r["side"]==side]); S=np.array([r["q_servo"] for r in rows if r["side"]==side])
    print("side",side,"n",len(Q))
    print("  q_corr mean",Q.mean(0),"\n  q_corr sd  ",Q.std(0))
    print("  q_servo mean",S.mean(0),"\n  q_servo sd  ",S.std(0))
    print("  fraction of serves with |q_corr| at the clamp 0.588 per joint:",(np.abs(Q)>=0.585).mean(0))
