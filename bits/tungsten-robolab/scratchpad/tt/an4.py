import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
vin=np.array([r["ball_in_exact"] for r in hits]); vp=np.array([r["paddle_vel"] for r in hits]); n=np.array([r["pad_normal"] for r in hits]); vout=np.array([r["ball_out_exact"] for r in hits])
side=np.array([r["side"] for r in hits]); sol=np.array([r["solved"]>0 for r in hits])
# orient normal against incoming ball (pointing to -x, toward the ball)
sg=np.sign(np.sum(vin*n,axis=1)); nn=n*(-sg)[:,None]     # nn . vin < 0
vpn=np.sum(vp*nn,axis=1)      # pad velocity along the outward normal (positive = moving toward the ball = closing)
vinn=-np.sum(vin*nn,axis=1)   # ball approach speed along the normal (positive)
sp_in=np.linalg.norm(vin,axis=1); sp_out=np.linalg.norm(vout,axis=1)
np.set_printoptions(precision=3,suppress=True,linewidth=150)
print("n hits",len(hits))
print("ball speed in: mean %.2f std %.2f; range %.2f..%.2f"%(sp_in.mean(),sp_in.std(),sp_in.min(),sp_in.max()))
print("pad velocity along its normal (+ toward the ball): mean %.2f std %.2f"%(vpn.mean(),vpn.std()))
print("  by side: fh mean %.2f std %.2f ; bh mean %.2f std %.2f"%(vpn[side==1].mean(),vpn[side==1].std(),vpn[side==2].mean(),vpn[side==2].std()))
print("pad velocity components: x %.2f+-%.2f y %.2f+-%.2f z %.2f+-%.2f"%(vp[:,0].mean(),vp[:,0].std(),vp[:,1].mean(),vp[:,1].std(),vp[:,2].mean(),vp[:,2].std()))
# regress exit speed on approach speed and pad normal velocity
A=np.c_[np.ones(len(hits)),vinn,vpn]
c,res,_,_=np.linalg.lstsq(A,sp_out,rcond=None)
print("exit speed ~ %.2f + %.2f * vin_n + %.2f * vp_n ; resid std %.2f ; exit speed std %.2f"%(c[0],c[1],c[2],np.std(sp_out-A@c),sp_out.std()))
for lo,hi in [(-2,-0.5),(-0.5,-0.2),(-0.2,0.0),(0,0.2),(0.2,0.5),(0.5,2)]:
    m=(vpn>=lo)&(vpn<hi)
    if m.sum(): print("vp_n %.1f..%.1f: n %d mean exit speed %.2f solved %d (%.0f%%)"%(lo,hi,m.sum(),sp_out[m].mean(),sol[m].sum(),100*sol[m].mean()))
# incoming speed groups
for lo,hi in [(0,5.2),(5.2,5.6),(5.6,6.0),(6.0,6.5),(6.5,9)]:
    m=(sp_in>=lo)&(sp_in<hi)
    if m.sum(): print("ball speed in %.1f..%.1f: n %d exit %.2f+-%.2f vp_n %.2f solved %d (%.0f%%)"%(lo,hi,m.sum(),sp_out[m].mean(),sp_out[m].std(),vpn[m].mean(),sol[m].sum(),100*sol[m].mean()))
# how much of exit speed variation is serve vs pad
print("corr(exit, ball speed in)=%.2f corr(exit, vp_n)=%.2f corr(vp_n, ball speed)=%.2f"%(np.corrcoef(sp_out,sp_in)[0,1],np.corrcoef(sp_out,vpn)[0,1],np.corrcoef(vpn,sp_in)[0,1]))
