import numpy as np
def run(q0,qg,vf,T0,dt=0.01,amax=200.0,tmin=0.06):
    r=q0; v=0.0; a=0.0; t=0.0; out=[]
    while t<T0-1e-9:
        tx=T0-t
        if tx>tmin:
            j=60*(qg-r)/tx**3-(36*v+24*vf)/tx**2-9*a/tx
            a=np.clip(a+j*dt,-amax,amax)
        else:
            a=0.0
        v+=a*dt; r+=v*dt; t+=dt
        out.append((t,r,v,a))
    return np.array(out)
for (q0,qg,u) in [(-0.42,-0.205,0.4),(-0.42,-0.205,0.0),(-0.42,-0.6,0.4),(-0.42,-0.42,0.4),(-0.42,-0.42,1.0),(-0.42,-0.8,0.8)]:
    o=run(q0,qg,-u,0.5)
    print("q0 %.2f goal %.3f  retreat u=%.1f: peak |v| %.2f m/s, peak |a| %.1f m/s^2, end v %.2f, end q %.3f, q range [%.3f, %.3f]"%(q0,qg,u,np.abs(o[:,2]).max(),np.abs(o[:,3]).max(),o[-1,2],o[-1,1],o[:,1].min(),o[:,1].max()))
print("--- coast threshold sweep: end velocity error")
for tmin in (0.06,0.04,0.03,0.02,0.01):
    errs=[]
    for (q0,qg,u) in [(-0.42,-0.205,0.4),(-0.42,-0.205,0.0),(-0.42,-0.6,0.4),(-0.42,-0.42,0.4),(-0.42,-0.42,1.0),(-0.42,-0.8,0.8),(-0.42,-0.1,0.6),(-0.42,-0.3,1.0)]:
        o=run(q0,qg,-u,0.5,tmin=tmin)
        errs.append((o[-1,2]-(-u),o[-1,1]-qg))
    e=np.array(errs)
    print("tmin %.2f: end velocity error rms %.3f max %.3f ; position error rms %.3f max %.3f ; peak |a| ~"%(tmin,np.sqrt((e[:,0]**2).mean()),np.abs(e[:,0]).max(),np.sqrt((e[:,1]**2).mean()),np.abs(e[:,1]).max()))
