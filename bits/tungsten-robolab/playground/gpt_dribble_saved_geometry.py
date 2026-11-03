"""Read-only 100 Hz geometry replay; no dynamics or controller is run."""
import json,hashlib
from pathlib import Path
import gpt_competitor as base
import mujoco
import numpy as np
from tasks.dribble import TASK
from search import jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round9'

def replay(path,metrics):
    task=TASK();xml=task.xml(task.builder());m=mujoco.MjModel.from_xml_string(xml);d=mujoco.MjData(m)
    a=np.load(path);t=a['t'];q=a['q'];assert q.shape[1]==m.nq
    ball=m.geom('ball').id;radius=float(m.geom_size[ball,0]);geoms={s:m.geom(s+'_hand').id for s in 'rl'}
    positions=[];palms={s:[] for s in 'rl'};gap={s:[] for s in 'rl'}
    for time,state in zip(t,q):
        d.qpos[:]=state;d.time=time;mujoco.mj_forward(m,d)
        center=d.geom_xpos[ball].copy();positions.append(center)
        for s,g in geoms.items():
            local=d.geom_xmat[g].reshape(3,3).T@(center-d.geom_xpos[g])
            outside=np.maximum(np.abs(local)-m.geom_size[g],0)
            gap[s].append(float(np.linalg.norm(outside)-radius));palms[s].append(d.site(s+'_palm').xpos.copy())
    positions=np.array(positions);palms={s:np.array(v) for s,v in palms.items()};gap={s:np.array(v) for s,v in gap.items()}
    # Control labels are sampled every 5 ms; q is independently sampled ~10 ms.
    labels=a['labels'];dt=.005
    released=next(i*dt for i,l in enumerate(labels) if 'right:let_go' in l)
    end=released+metrics['controlled_s']
    floors=[]
    for i in range(1,len(t)-1):
        if t[i]>end+.03:break
        if t[i]<released or positions[i,2]>=.14:continue
        if positions[i,2]<=positions[i-1,2] and positions[i,2]<=positions[i+1,2] and (not floors or t[i]-t[floors[-1]]>.3):floors.append(i)
    np.savez_compressed(OUT/(path.stem+'_geometry.npz'),t=t,ball=positions,r_palm=palms['r'],l_palm=palms['l'],r_gap=gap['r'],l_gap=gap['l'])
    cycles=[]
    for left,right in zip(floors,floors[1:]):
        apex=left+int(np.argmax(positions[left:right+1,2]));segment=slice(left,right+1)
        phase=str(labels[min(round(t[left]/dt),len(labels)-1)])
        receiving='l' if any('left:'+x in phase for x in ['recover','wait','x_swing','x_carry']) else 'r'
        nearest=left+int(np.argmin(gap[receiving][segment]));rising=left+int(np.argmin(gap[receiving][left:apex+1]))
        joints={}
        for name in [receiving+'_shoulder_flex',receiving+'_shoulder_abd',receiving+'_elbow',receiving+'_wrist_flex']:
            j=m.joint(name).id;adr=m.jnt_qposadr[j];joints[name]=float(np.ptp(q[segment,adr]))
        cycles.append({'bounce_start':float(t[left]),'bounce_end':float(t[right]),'receiving_hand_inferred_from_phase':receiving,'phase_at_bounce':phase,'apex_time':float(t[apex]),'apex_z':float(positions[apex,2]),'closest_surface_gap_m':float(gap[receiving][nearest]),'closest_time':float(t[nearest]),'rising_surface_gap_m':float(gap[receiving][rising]),'rising_closest_time':float(t[rising]),'phase_at_closest':str(labels[min(round(t[nearest]/dt),len(labels)-1)]),'ball_at_closest':positions[nearest].tolist(),'palm_at_closest':palms[receiving][nearest].tolist(),'measured_joint_range_rad':joints})
    return {'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'model_xml_sha256':hashlib.sha256(xml.encode()).hexdigest(),'q_sample_interval':float(np.median(np.diff(t))),'release_time_from_label':released,'estimated_loss_time':end,'metrics':{k:metrics.get(k) for k in ['x_ok','controlled_s','lost','fell']},'cycles':cycles}

def main():
    rows=json.loads((OUT/'preflight_rollouts.json').read_text());result=[]
    for seed in [288001,288002]:
        for label in ['old_tcn','old_zero']:
            row=next(r for r in rows if r['seed']==seed and r['label']==label)
            data=replay(OUT/f'preflight_{label}_{seed}.npz',row['metrics']);data.update({'label':label,'seed':seed});result.append(data)
    report={'scope':'Read-only forward kinematics from already-consumed preflight q traces. No dynamics, no controller, no new rollout. Approximate 100 Hz surface separation is not official force-threshold hand contact. Phase selects an inferred receiving hand; loss time uses let_go label plus rounded controlled_s. No current training or selection changes.','rows':result}
    (OUT/'saved_geometry_diagnosis.json').write_text(json.dumps(jsonable(report),indent=2)+'\n')
    for r in result:print(json.dumps({k:r[k] for k in ['label','seed','estimated_loss_time','metrics']}|{'last_two_cycles':r['cycles'][-2:]}))
if __name__=='__main__':main()
