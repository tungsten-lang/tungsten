"""Saved fingered-body geometry only; no dynamics or controller invocation."""
import hashlib,json
from pathlib import Path
import gpt_competitor as base
import mujoco
import numpy as np
from tasks.dribble_v3 import TASK
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_fingers_prototype'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    rows=json.loads((OUT/'rollouts.json').read_text());task=TASK();xml=task.xml(task.builder());m=mujoco.MjModel.from_xml_string(xml);d=mujoco.MjData(m)
    ball=m.geom('ball').id;hands={s:[m.geom(s+g).id for g in ['_hand','_fingers1','_fingers2']] for s in 'rl'};out=[]
    for row in rows:
        if row['label'].startswith('zero'):continue
        path=OUT/f"{row['label']}_{row['seed']}.npz";a=np.load(path);t=a['t'];q=a['q'];labels=a['labels'];metrics=row['metrics'];dt=.005
        release=next(i*dt for i,l in enumerate(labels) if 'right:let_go' in l);end=release+metrics['controlled_s']
        b=[];gaps={s:[] for s in 'rl'};centers={s:[] for s in 'rl'}
        for ti,qi in zip(t,q):
            d.time=ti;d.qpos[:]=qi;mujoco.mj_forward(m,d);b.append(d.geom_xpos[ball].copy())
            for s,geoms in hands.items():
                gaps[s].append([float(mujoco.mj_geomDistance(m,d,ball,g,10.,None)) for g in geoms]);centers[s].append(d.site(s+'_palm').xpos.copy())
        b=np.array(b);gaps={s:np.array(v) for s,v in gaps.items()};centers={s:np.array(v) for s,v in centers.items()}
        floors=[]
        for i in range(1,len(t)-1):
            if t[i]>end+.05:break
            if t[i]>=release and b[i,2]<.14 and b[i,2]<=b[i-1,2] and b[i,2]<=b[i+1,2] and (not floors or t[i]-t[floors[-1]]>.3):floors.append(i)
        cycles=[]
        for left,right in zip(floors,floors[1:]):
            phase=str(labels[min(round(t[left]/dt),len(labels)-1)]);receiver='l' if any('left:'+x in phase for x in ['recover','wait','swing','carry','x_recover','x_wait','x_swing','x_carry','b_recover','b_wait','b_swing','b_carry']) else 'r'
            seg=slice(left,right+1);dist=np.min(gaps[receiver],axis=1);nearest=left+int(np.argmin(dist[seg]));apex=left+int(np.argmax(b[seg,2]))
            cycles.append({'bounce_start':float(t[left]),'bounce_end':float(t[right]),'receiver_inferred':receiver,'phase_at_bounce':phase,'apex_z':float(b[apex,2]),'minimum_ball_hand_gap_m':float(dist[nearest]),'closest_time':float(t[nearest]),'closest_geom':['palm','proximal_finger','distal_finger'][int(np.argmin(gaps[receiver][nearest]))],'phase_at_closest':str(labels[min(round(t[nearest]/dt),len(labels)-1)]),'ball_at_closest':b[nearest].tolist(),'palm_at_closest':centers[receiver][nearest].tolist()})
        active=(t>=release)&(t<=end);exc={}
        for name in ['spine_flex','spine_bend','spine_twist']+[s+'_'+j for s in 'rl' for j in ['shoulder_flex','shoulder_abd','elbow','wrist_flex','finger_mcp','finger_pip']]:
            jid=mujoco.mj_name2id(m,mujoco.mjtObj.mjOBJ_JOINT,name)
            if jid>=0:exc[name]=float(np.ptp(q[active,m.jnt_qposadr[jid]]))
        out.append({'label':row['label'],'seed':row['seed'],'source':str(path),'source_sha256':sha(path),'release':release,'estimated_loss':end,'metrics':{k:metrics[k] for k in ['x_ok','controlled_s','lost','fell','body_hits']},'measured_control_window_joint_excursion_rad':exc,'cycles':cycles})
    result={'scope':'Forward kinematics of six already-consumed full-motion traces. No dynamics or new rollout. Signed geometric separation at about100Hz is not force-threshold contact; receiving hand is inferred from controller labels and loss time uses rounded control duration. No architecture or technique-improvement claim.','model_xml_sha256':hashlib.sha256(xml.encode()).hexdigest(),'sources_sha256':{'playground/gpt_finger_geometry.py':sha(__file__),'out/competitor_dribble_fingers_prototype/rollouts.json':sha(OUT/'rollouts.json')},'rows':out}
    (OUT/'geometry_diagnosis.json').write_text(json.dumps(result,indent=2)+'\n')
    for r in out:print(json.dumps({k:r[k] for k in ['label','seed','metrics']}|{'last_cycle':r['cycles'][-1] if r['cycles'] else None}))
if __name__=='__main__':main()
