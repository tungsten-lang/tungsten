import numpy as np, glob, json
np.set_printoptions(precision=2,suppress=True,linewidth=200)
rows={json.loads(l)["seed"]:json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")}
n=0
for side in (1,2):
    print("=== side",side)
    cnt=0
    for f in sorted(glob.glob("out/tt_r10/champ_logs/*.npz")):
        seed=int(f.split("/")[-1].split(".")[0]); r=rows[seed]
        if r.get("side")!=side or not r.get("hit"): continue
        z=np.load(f); L=z["L"]; k=int(z["contact"]); t=L[:,0]; pel=L[:,16:19]
        vx=np.diff(pel[:,0])/np.diff(t)
        idx=np.arange(max(k-45,1),k,5)
        print("seed",seed,"contact row",k,"t_c",r["t_contact"],"solved",r["solved"],"ball speed in %.2f"%np.linalg.norm(r["ball_in_exact"]),"| pelvis x (rows k-45..k step 5):",pel[idx,0]," vx:",vx[idx-1])
        cnt+=1
        if cnt>=6: break
