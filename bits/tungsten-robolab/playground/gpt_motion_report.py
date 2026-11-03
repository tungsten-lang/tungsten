"""Measured joint-motion diagnostics from complete saved batter traces.
These are observations, not an alternative arena judge or perceptual hitch metric.
"""
import json,sys
import numpy as np
from gpt_competitor import OUT,CONFIG,Sim
from tasks.bat import TASK
import mujoco

def longest(mask,times):
    if len(mask)<2:return 0.
    delta=float(np.median(np.diff(times)));best=cur=0
    for yes in mask:
        cur=cur+1 if yes else 0;best=max(best,cur)
    return round(1000*best*delta,1)

def main():
    task=TASK();sim=Sim(task)
    names={mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_JOINT,j):int(sim.m.jnt_qposadr[j]) for j in range(sim.m.njnt)}
    groups={'arms':[a for n,a in names.items() if n.startswith(('l_shoulder','r_shoulder','l_elbow','r_elbow','l_wrist','r_wrist'))], 'trunk':[a for n,a in names.items() if n.startswith(('spine','pelvis_yaw'))], 'front_hip':[names['r_hip_flex']], 'front_knee':[names['r_knee']]}
    result=[]
    for variant,kind in [('pure','baseline'),('pure','candidate'),('tcn','candidate'),('tcn','bias_only'),('tcn','zero_head')]:
        path=OUT/f'bat_{variant}_{kind}_validation.npz'
        if '--partial' in sys.argv and not path.exists():continue
        trace=np.load(path);t=trace['t'];q=trace['q'];labels=trace['labels']
        if kind=='zero_head':rows=json.loads((OUT/'bat_tcn_zero_head.json').read_text());metrics=rows[0]['metrics']
        else:
            rows=json.loads((OUT/f'bat_{variant}_validate.json').read_text());metrics=next(r['metrics'] for r in rows if r['kind']==kind)
        control_t=(np.arange(len(labels))+1)*task.control_dt
        def first(label,default):
            where=np.flatnonzero(np.char.find(labels,label)>=0)
            return float(control_t[where[0]]) if len(where) else default
        start=first('arms:leglift',0.);finish=first('arms:finish',float(t[-1]));stride=first('hips:stride',finish)
        row={'controller':variant+'_'+kind,'seed':271001,'motion_interval':[start,finish],'threshold_rad_s':0.1,'groups':{},'full_visible_interval':[float(t[0]),float(t[-1])]}
        for group,indices in groups.items():
            speeds=np.sqrt(np.mean(np.gradient(q[:,indices],t,axis=0)**2,axis=1))
            window=(t>=start)&(t<=(stride if group.startswith('front_') else finish))
            quiet=speeds<.1
            boundaries=np.flatnonzero(np.diff(np.r_[False,quiet,False]))
            spans=[]
            for begin,end in zip(boundaries[::2],boundaries[1::2]):
                end=min(end,len(t)-1)
                i=min(len(labels)-1,max(0,int(t[begin]/task.control_dt)))
                spans.append({'start_s':float(t[begin]),'end_s':float(t[end]),'duration_s':float(t[end]-t[begin]),'label_at_start':str(labels[i])})
            row['groups'][group]={'quiet_ms_measured':longest(speeds[window]<.1,t[window]),'peak_rms_joint_speed_rad_s':float(np.max(speeds[window])), 'full_visible_peak_rms_joint_speed_rad_s':float(np.max(speeds)), 'full_visible_mean_joint_travel_rad':float(np.mean(np.sum(np.abs(np.diff(q[:,indices],axis=0)),axis=0))), 'full_visible_longest_quiet_spans':sorted(spans,key=lambda x:x['duration_s'],reverse=True)[:5]}
        pitch=metrics['pitches'][0]
        row['plant_to_swing_ms']=1000*(pitch['t_swing']-pitch['t_plant']) if pitch.get('t_swing') is not None and pitch.get('t_plant') is not None else None
        result.append(row)
    (OUT/'bat_measured_motion.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
