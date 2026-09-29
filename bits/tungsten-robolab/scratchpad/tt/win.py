import numpy as np, sys
sys.path.insert(0,"playground")
import tt_impact as ti
def feasible(v, z0=1.27, x0=1.72, y0=0.0, az=0.0):
    ok=[]
    for th in np.arange(-20,89.5,0.5):
        t=np.radians(th); a=np.radians(az)
        vel=np.array([-v*np.cos(t)*np.cos(a), v*np.cos(t)*np.sin(a), v*np.sin(t)])
        l,x,y,_=ti.flight([x0,y0,z0],vel)
        if l=="opp": ok.append(th)
    return ok
def intervals(ok):
    if not ok: return []
    out=[]; s=ok[0]; p=ok[0]
    for a in ok[1:]:
        if a-p>0.51: out.append((s,p)); s=a
        p=a
    out.append((s,p)); return out
for v in [3.5,4.0,4.5,5.0,5.5,6.0,6.5,7.0,8.0]:
    print("speed",v,"elevation windows (deg):",intervals(feasible(v)))
print("with z0=1.27 x0=1.72 azimuth 0; azimuth window at 5 m/s, elevation 40:")
for az in [-30,-20,-10,0,10,20,30,40]:
    ok=feasible(5.0,az=az)
    print(" az",az,intervals(ok))
