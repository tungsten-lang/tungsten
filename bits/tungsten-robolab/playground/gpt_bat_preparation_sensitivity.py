"""Threshold and duplicate-prefix checks on consumed preparation traces."""
import hashlib,json
from pathlib import Path
import gpt_competitor as base
import numpy as np
import mujoco
from tasks.bat import TASK
from gpt_motion_report import longest
ROOT=base.ROOT;OUT=ROOT/'out/competitor_bat_prepare_prototype'
def main():
    sim=base.Sim(TASK());inds=[int(sim.m.jnt_qposadr[j]) for j in range(sim.m.njnt) if (mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_JOINT,j) or '').startswith(('l_shoulder','r_shoulder','l_elbow','r_elbow','l_wrist','r_wrist'))];thresholds=[.05,.075,.1,.125,.15,.2];sources={};rows=[];identity={}
    for v in ['pure','tcn']:
        for label in ['off','on']:
            traces=[]
            for seed in [271001,271002]:
                p=OUT/f'{label}_{v}_{seed}.npz';sources[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest();traces.append(np.load(p))
            a,b=traces;qwin=a['t']<2.9;control_count=580
            identity[v+'_'+label]={k:bool(np.array_equal(a[k][:control_count],b[k][:control_count])) for k in ['command','measured','activation','labels']}
            identity[v+'_'+label]['q_before_release']=bool(np.array_equal(a['q'][qwin],b['q'][b['t']<2.9]));identity[v+'_'+label]['sample_times_before_release']=bool(np.array_equal(a['t'][qwin],b['t'][b['t']<2.9]))
            t=a['t'];q=a['q'][:,inds];velocity=np.gradient(q,t,axis=0);speed=np.sqrt(np.mean(velocity**2,axis=1));w=(t>=2.56)&(t<2.9);acc=np.gradient(velocity,t,axis=0)
            sampled=q[w];rows.append({'variant':v,'label':label,'representative_seed':271001,'window_s':[2.56,2.9],'threshold_quiet_ms':{str(th):longest(speed[w]<th,t[w]) for th in thresholds},'mean_rms_speed_rad_s':float(np.mean(speed[w])),'mean_joint_travel_rad':float(np.mean(np.sum(np.abs(np.diff(sampled,axis=0)),axis=0))),'mean_absolute_net_joint_change_rad':float(np.mean(np.abs(sampled[-1]-sampled[0]))),'rms_joint_acceleration_rad_s2':float(np.sqrt(np.mean(acc[w]**2)))})
    sources['playground/gpt_bat_preparation_sensitivity.py']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    result={'scope':'Post-hoc sensitivity analysis of consumed traces only. Both pitch seeds share preparation before release if the prefix checks pass; they are not independent perturbed preparation starts. Speed thresholds are diagnostics, not perceptual smoothness or an arena score. Approximately10ms q sampling limits derivatives and durations.','sources_sha256':sources,'pre_release_prefix_identity_between_pitch_seeds':identity,'all_preparation_prefixes_identical':all(all(x.values()) for x in identity.values()),'rows':rows}
    with (OUT/'preparation_sensitivity.json').open('x') as f:json.dump(result,f,indent=2)
    print(json.dumps({k:v for k,v in result.items() if k!='sources_sha256'},indent=2))
if __name__=='__main__':main()
