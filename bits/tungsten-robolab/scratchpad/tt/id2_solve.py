import numpy as np, sys
from scipy.optimize import lsq_linear
np.set_printoptions(precision=3,suppress=True)
names=["elv","sh_elv","sh_rot","elbow","pro_sup","dev","trunk_ar"]
# per +0.1 rad (pitch deg, yaw deg, pad z m) from id2_* (wflex -0.25, qa=3)
J=np.array([[-2.481, 0.380, 0.003],
            [ 2.002, 0.857,-0.012],
            [-0.827,-0.667, 0.002],
            [-3.116, 0.986, 0.029],
            [ 0.591, 0.075,-0.003],
            [-2.269, 1.288, 0.009],
            [float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3])]])/0.1
cur=np.array([-3.232,28.275,1.114])
base=np.array([0.345,0.104,-1.294,1.075,1.124,-0.128,0.0])
lo=np.array([-0.5,0.0,-1.5,0.0,-1.5,-0.17,-0.75])-base; hi=np.array([1.5,2.0,1.5,2.2,1.5,0.43,0.75])-base
for wy in (0.05,0.15,0.3):
    for tgt in [(-4.0,12.0,1.205)]:
        W=np.diag([1.0,wy,20.0]); lam=1.0
        A=np.vstack([W@J.T,np.sqrt(lam)*np.eye(7)]); b=np.concatenate([W@(np.array(tgt)-cur),np.zeros(7)])
        r=lsq_linear(A,b,bounds=(lo,hi)); dq=r.x; pred=cur+J.T@dq
        print("yaw weight %.2f: new %s | predicted pitch %.1f yaw %.1f z %.3f"%(wy,dict(zip(names,(base+dq).round(3))),*pred))
