import numpy as np
names=["elv","sh_elv","sh_rot","elbow","pro_sup","dev","wflex"]
# per +0.1 rad (from id_an): pitch(deg), yaw(deg), pad_z(m)
J=np.array([[-2.529,  0.447,  0.005],
            [ 2.612,  1.086, -0.011],
            [-0.731, -0.484,  0.000],
            [-4.912,  1.825,  0.026],
            [-0.063, -0.251, -0.001],
            [-4.860,  2.289,  0.006],
            [ 1.873,  4.846, -0.013]])/0.1     # per rad, rows = joints
cur=np.array([-7.83,12.2,1.177])
def solve(target,w=(1.0,0.3,20.0),lam=2.0,free=(1,1,1,1,1,1,1)):
    # minimise |W (J^T dq - (target-cur))|^2 + lam |dq|^2
    W=np.diag(w)
    A=(W@J.T)[:,list(np.nonzero(free)[0])]
    b=W@(np.array(target)-cur)
    x=np.linalg.solve(A.T@A+lam*np.eye(A.shape[1]),A.T@b)
    dq=np.zeros(7); dq[list(np.nonzero(free)[0])]=x
    return dq
for target in [(-3.0,12.2,1.22),(-3.0,12.2,1.26),(-6.0,12.2,1.24),(-8.0,12.2,1.24)]:
    dq=solve(target)
    pred=cur+J.T@dq
    print("target pitch %.0f z %.2f -> dq %s | predicted pitch %.1f yaw %.1f z %.3f"%(target[0],target[2],dict(zip(names,dq.round(3))),*pred))

from scipy.optimize import lsq_linear
base=np.array([0.345,0.104,-1.294,1.075,1.124,-0.128,-0.651])   # elv, sh_elv, sh_rot, elbow, pro_sup, dev, wflex (b0)
lo=np.array([-0.5,0.0,-1.5,0.0,-1.5,-0.17,-0.78])-base; hi=np.array([1.5,2.0,1.5,2.2,1.5,0.43,0.78])-base
def solve_box(target,w=(1.0,0.3,20.0),lam=2.0):
    W=np.diag(w); A=np.vstack([W@J.T, np.sqrt(lam)*np.eye(7)]); b=np.concatenate([W@(np.array(target)-cur),np.zeros(7)])
    r=lsq_linear(A,b,bounds=(lo,hi)); return r.x
print("--- with the joint boxes (dev >= -0.17)")
for target in [(-3.0,12.2,1.22),(-3.0,12.2,1.26),(-6.0,12.2,1.24),(-8.0,12.2,1.24)]:
    dq=solve_box(target); pred=cur+J.T@dq
    print("target pitch %.0f z %.2f -> new params %s | predicted pitch %.1f yaw %.1f z %.3f"%(target[0],target[2],dict(zip(names,(base+dq).round(3))),*pred))

print("--- wflex fixed")
def solve_fixed(target,wf,w=(1.0,0.3,20.0),lam=2.0):
    W=np.diag(w); dqw=wf-base[6]
    A=np.vstack([(W@J.T)[:,:6], np.sqrt(lam)*np.eye(6)]); b=np.concatenate([W@(np.array(target)-cur-J[6]*dqw), np.zeros(6)])
    r=lsq_linear(A,b,bounds=(lo[:6],hi[:6])); dq=np.concatenate([r.x,[dqw]]); return dq
for wf in (-0.5,-0.4,-0.3):
    for target in [(-4.0,12.2,1.24)]:
        for wy in (0.3,1.0):
            dq=solve_fixed(target,wf,w=(1.0,wy,20.0)); pred=cur+J.T@dq
            print("wflex %.2f yaw weight %.1f target pitch %.0f z %.2f -> %s | predicted pitch %.1f yaw %.1f z %.3f"%(wf,wy,target[0],target[2],dict(zip(names,(base+dq).round(3))),*pred))
