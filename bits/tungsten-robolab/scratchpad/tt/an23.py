import numpy as np, sys, json
sys.path.insert(0,"playground")
np.set_printoptions(precision=3,suppress=True,linewidth=220)
def at_height(p,v,zt,bounced):
    px,pz,vx,vz=p[0],p[2],v[0],v[2]
    if not bounced:
        c=pz-0.805; disc=vz*vz+2*9.81*c
        if disc<0: return None
        tb=(vz+np.sqrt(disc))/9.81
        px=px+vx*tb; vz=-(vz-9.81*tb)*0.99; vx=vx*0.996; pz=0.805
    if vx<0.5: return None
    d=vz*vz-2*9.81*(zt-pz); t=vz/9.81
    if d>0: t=(vz-np.sqrt(d))/9.81
    t=max(t,0.0)
    return px+vx*t
for seed in [int(x) for x in sys.argv[1:]]:
    z=np.load("out/tt_r10/champ_logs/%d.npz"%seed); L=z["L"]; k=int(z["contact"]); t=L[:,0]
    ball=L[:,1:4]; bv=L[:,4:7]; pad=L[:,7:10]; pel=L[:,16:19]; touch=L[:,19:25]
    bounced=np.maximum.accumulate(touch[:,1]>0)
    print("seed",seed,"contact row",k)
    rows=np.arange(5,k,4)
    xh=[at_height(ball[i],bv[i],1.273,bool(bounced[i])) for i in rows]
    print(" t         :",t[rows])
    print(" ball x    :",ball[rows,0])
    print(" xh (z 1.273):",np.array([np.nan if x is None else x for x in xh]))
    print(" pel x     :",pel[rows,0])
    print(" pad x     :",pad[rows,0]," pad-pel:",pad[rows,0]-pel[rows,0])
    print(" pad z     :",pad[rows,2])
