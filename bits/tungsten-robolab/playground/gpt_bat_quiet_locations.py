"""Locate quiet intervals in consumed batting traces; no new rollout."""
import hashlib,json
from pathlib import Path
import gpt_competitor as base
import numpy as np
import mujoco
from tasks.bat import TASK
ROOT=base.ROOT;OUT=ROOT/'out/competitor_bat_prepare_prototype'
def main():
    sim=base.Sim(TASK());step=round(sim.task.control_dt/sim.m.opt.timestep)*sim.m.opt.timestep
    names={mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_JOINT,j):int(sim.m.jnt_qposadr[j]) for j in range(sim.m.njnt)}
    groups={'arms':[a for n,a in names.items() if n.startswith(('l_shoulder','r_shoulder','l_elbow','r_elbow','l_wrist','r_wrist'))],'trunk':[a for n,a in names.items() if n.startswith(('spine','pelvis_yaw'))],'front_hip':[names['r_hip_flex']],'front_knee':[names['r_knee']]}
    rows=[];sources={}
    for row in json.loads((OUT/'rollouts.json').read_text()):
        if row['label'] not in ['on','off']:continue
        p=OUT/f"{row['label']}_{row['variant']}_{row['seed']}.npz";sources[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest();a=np.load(p);t=a['t'];q=a['q'];labels=a['labels']
        def first(label):return next(i*step for i,l in enumerate(labels) if label in l)
        start=first('arms:leglift');end=first('arms:finish');stride=first('hips:stride');result={}
        for group,inds in groups.items():
            speed=np.sqrt(np.mean(np.gradient(q[:,inds],t,axis=0)**2,axis=1));stop=stride if group.startswith('front_') else end
            quiet=(t>=start)&(t<=stop)&(speed<.1);edges=np.diff(np.r_[False,quiet,False].astype(int));segments=[]
            for lo,hi in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)):
                phases=list(dict.fromkeys(str(labels[min(int(np.floor(ti/step+1e-7)),len(labels)-1)]) for ti in t[lo:hi]));dt=float(np.median(np.diff(t[max(0,lo-1):min(len(t),hi+1)])))
                segments.append({'start_s':float(t[lo]),'end_s':float(t[hi-1]),'sample_support_ms':float((t[hi-1]-t[lo]+dt)*1000),'q_samples':int(hi-lo),'phases':phases,'maximum_rms_speed_rad_s':float(speed[lo:hi].max())})
            result[group]=sorted(segments,key=lambda x:x['sample_support_ms'],reverse=True)[:3]
        rows.append({'label':row['label'],'variant':row['variant'],'seed':row['seed'],'leglift_start':start,'stride_start':stride,'arms_finish_start':end,'quiet_intervals':result})
    sources['playground/gpt_bat_quiet_locations.py']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    evidence={'scope':'Offline consumed-trace diagnosis only, no dynamics or new performance claim. Quiet means RMS joint speed below0.1rad/s, not a perceptual hitch judgment. Intervals cover leglift-to-finish (frontleg stops atstride) and have approximately10ms sample precision. Labels map through the verified physics/control interval.','control_interval_s':step,'sources_sha256':sources,'rows':rows}
    path=OUT/'quiet_locations.json'
    with path.open('x') as f:json.dump(evidence,f,indent=2)
    for r in rows:print(json.dumps({k:r[k] for k in ['label','variant','seed','leglift_start','stride_start']}|{'longest_arm_interval':r['quiet_intervals']['arms'][:1],'longest_front_knee_interval':r['quiet_intervals']['front_knee'][:1]}))
if __name__=='__main__':main()
