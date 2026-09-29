import json, numpy as np, collections
import sys
sys.path.insert(0,"playground")
sys.path.insert(0,"playground/tasks")
from tasks.myo_tt import failure_class
rows=[json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")]
rows=[r for r in rows if "error" not in r]
def intercept(p,v,xh=1.75):
    px,py,pz=p; vx,vy,vz=v
    c=pz-0.805; disc=vz*vz+2*9.81*c
    tb=(vz+np.sqrt(disc))/9.81
    px=px+vx*tb; py=py+vy*tb; vz=-(vz-9.81*tb)*0.99; vx*=0.996; vy*=0.996; pz=0.805
    th=(xh-px)/vx
    return np.array([tb+th, py+vy*th, pz+vz*th-4.905*th*th])
Y=np.array([intercept(r["serve"][0:3],r["serve"][3:6])[1] for r in rows])
Zc=np.array([intercept(r["serve"][0:3],r["serve"][3:6])[2] for r in rows])
cls=[failure_class(r) for r in rows]
side=np.array([r["side"] for r in rows])
print("crossing y (at x=1.75) by bins: n, solved%, no-hit%, lateral-miss%, below-ball%")
edges=[-0.9,-0.5,-0.3,-0.1,0.1,0.3,0.5,0.9]
for lo,hi in zip(edges[:-1],edges[1:]):
    m=(Y>=lo)&(Y<hi)
    if m.sum()==0: continue
    c=collections.Counter(np.array(cls)[m])
    print("  y %.1f..%.1f n %3d side1 %3d side2 %3d | solved %.0f%% | lateral %.0f%% below %.0f%% above %.0f%% rim/timing %.0f%%"%(lo,hi,m.sum(),(side[m]==1).sum(),(side[m]==2).sum(),100*c["solved"]/m.sum(),100*c["miss: lateral (out of reach)"]/m.sum(),100*c["miss: pad below the ball"]/m.sum(),100*c["miss: pad above the ball"]/m.sum(),100*c["miss: within 10 cm (rim/timing)"]/m.sum()))
print("crossing z bins (below-ball misses):")
qs=np.quantile(Zc,[0,.2,.4,.6,.8,1.0])
for lo,hi in zip(qs[:-1],qs[1:]):
    m=(Zc>=lo)&(Zc<=hi); c=collections.Counter(np.array(cls)[m])
    print("  z %.2f..%.2f n %3d solved %.0f%% below-ball %.0f%% above %.0f%%"%(lo,hi,m.sum(),100*c["solved"]/m.sum(),100*c["miss: pad below the ball"]/m.sum(),100*c["miss: pad above the ball"]/m.sum()))
