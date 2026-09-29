import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
exec(open("scratchpad/tt/an11.py").read().split("res={}")[0].split("rows=[json")[0])  # imports only
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("paddle_vel") and r.get("pad_normal") and r.get("ball_in_exact")]
E,ALPHA,MU=0.95,0.9,0.012
rng=np.random.default_rng(1); NS=64
Z=rng.standard_normal((NS,5))
PHA=np.arange(-30,51,3.0); YWA=np.arange(-20,21,4.0); DEL=np.arange(-0.25,1.51,0.25)
def design_P(vin,pos,sig_p,sig_y,sig_v):
    out=np.zeros((len(DEL),len(PHA),len(YWA))); ret=np.array([1.0,0.0,0.0])
    for a,d in enumerate(DEL):
        vp=(d*ret)[None,:]+sig_v*Z[:,2:5]
        P=np.radians(PHA[:,None,None]+sig_p*Z[None,None,:,0]); Y=np.radians(YWA[None,:,None]+sig_y*Z[None,None,:,1])
        n=np.stack([np.cos(P)*np.cos(Y),np.cos(P)*np.sin(Y),np.sin(P)+0*Y],axis=-1); n/=np.linalg.norm(n,axis=-1,keepdims=True)
        v=ti.impact(vin,ALPHA*vp[None,None,:,:],n,E,MU); out[a]=ti.landing_ok(pos,v).mean(axis=-1)
    return out
sub=hits[::6]
print("serve | ball speed in, elev, azim | best delta, aim pitch, aim yaw, P | nominal exit speed/elev/azim | champion actual: solved, pad pitch, delta(meas)")
for r in sub[:40]:
    vin=np.array(r["ball_in_exact"]); pos=np.array(r["ball_pos_out"]); vp=np.array(r["paddle_vel"]); nt=np.array(r["pad_normal"])
    P=design_P(vin,pos,10,2.5,0.5); a,b,c=np.unravel_index(np.argmax(P),P.shape)
    d,phi,psi=DEL[a],PHA[b],YWA[c]
    n=ti.normal_from_angles(np.radians(phi),np.radians(psi)); vo=ti.impact(vin,ALPHA*d*np.array([1,0,0]),n,E,MU)
    sp_in=np.linalg.norm(vin); el_in=np.degrees(np.arcsin(vin[2]/sp_in)); az_in=np.degrees(np.arctan2(vin[1],vin[0]))
    sp=np.linalg.norm(vo); el=np.degrees(np.arcsin(vo[2]/sp)); az=np.degrees(np.arctan2(vo[1],-vo[0]))
    nto=nt*np.sign(nt[0]); pt=np.degrees(np.arcsin(nto[2])); 
    print("%d s%d | %.2f %+5.1f %+5.1f | d %.2f phi %+3.0f psi %+3.0f P %.2f | %.2f %+5.1f %+5.1f | sol %d padpitch %+5.1f"%(r["seed"],r["side"],sp_in,el_in,az_in,d,phi,psi,P.max(),sp,el,az,r["solved"]>0,pt))
