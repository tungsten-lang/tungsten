import hashlib,json,sys
from pathlib import Path
ROOT=Path('/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab')
sys.path.insert(0,str(ROOT/'playground'))
import gpt_competitor as base
import numpy as np
import mujoco
from tasks.bat import TASK
from gpt_motion_report import longest
OUT=ROOT/'out/competitor_bat_prepare_prototype'
def main():
 sim=base.Sim(TASK())
 names={mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_JOINT,j):int(sim.m.jnt_qposadr[j]) for j in range(sim.m.njnt)}
 groups={'arms':[a for n,a in names.items() if n.startswith(('l_shoulder','r_shoulder','l_elbow','r_elbow','l_wrist','r_wrist'))], 'trunk':[a for n,a in names.items() if n.startswith(('spine','pelvis_yaw'))], 'front_hip':[names['r_hip_flex']], 'front_knee':[names['r_knee']]}
 rows=[];sources={}
 for r in json.loads((OUT/'rollouts.json').read_text()):
  if r['label'] not in ['on','off']:continue
  p=OUT/f"{r['label']}_{r['variant']}_{r['seed']}.npz";sources[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
  d=np.load(p);t=d['t'];q=d['q'];labels=d['labels'];m=r['metrics'];pitch=m['pitches'][0]
  def first(label,default):
   ii=np.flatnonzero(np.char.find(labels,label)>=0)
   return float((ii[0]+1)*.005) if len(ii) else default
  start=first('arms:leglift',0);finish=first('arms:finish',float(t[-1]));stride=first('hips:stride',finish);release=pitch['t_release']
  row={'label':r['label'],'variant':r['variant'],'seed':r['seed'],'motion_interval':[start,finish],'release':release,'threshold_rad_s':.1,'groups':{},'full_visible_interval':[float(t[0]),float(t[-1])],'metrics':{k:m[k] for k in ['power','quality','hitch','hitch_full','peak_grf_bw','peak_loading_bw_s','fell']}}
  for k,inds in groups.items():
   speeds=np.sqrt(np.mean(np.gradient(q[:,inds],t,axis=0)**2,axis=1));win=(t>=start)&(t<=(stride if k.startswith('front_') else finish));pre=(t>=stride)&(t<release)
   row['groups'][k]={'quiet_ms_measured':longest(speeds[win]<.1,t[win]),'pre_release_stride_quiet_ms':longest(speeds[pre]<.1,t[pre]),'full_visible_peak_rms_joint_speed_rad_s':float(speeds.max()),'full_visible_mean_joint_travel_rad':float(np.mean(np.sum(np.abs(np.diff(q[:,inds],axis=0)),axis=0)))}
  rows.append(row)
 result={'scope':'Consumed-start integration diagnostic, not fresh validation or an arena judgment. Whole q trajectory is inspected; quiet intervals use the previously reported 0.1 rad/s RMS threshold. A quiet interval is not a perceptual hitch measurement.','sources_sha256':sources,'rows':rows}
 (OUT/'measured_motion.json').write_text(json.dumps(result,indent=2)+'\n')
 for r in rows:print(r['variant'],r['seed'],r['label'],r['metrics'],{k:g['quiet_ms_measured'] for k,g in r['groups'].items()})
if __name__=='__main__':main()
