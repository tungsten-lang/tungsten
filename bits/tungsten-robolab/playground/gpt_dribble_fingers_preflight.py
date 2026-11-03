"""Untrained fingered-body integration check; never overlap the R10 pipeline."""
import hashlib,json,multiprocessing as mp
from pathlib import Path
import gpt_competitor as base
import numpy as np
import mujoco
from search import read_params,jsonable
from tasks.dribble_v3 import TASK
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_fingers_prototype';SEEDS=[289101,289102]
CONTROLLER=ROOT/'bin/challengers/gpt-dribble-fingers-prototype'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(job):
    label,v,p,seed,old=job
    base.OUT=OUT;base.CONFIG={**base.CONFIG,'dribble':('dribble_v3','dribble_crossover_25',15.,[])}
    base.ctl_path=lambda problem,mode:str(OUT/'reference/v3-controller') if old else str(CONTROLLER)
    return base.run(('dribble',v,p,seed,15.,{'trace':f'{label}_{seed}.npz'}))
def main():
    r10=ROOT/'out/competitor_dribble_round10/audit.json'
    assert r10.exists() and json.loads(r10.read_text())['passed'],'Finish and audit R10, and confirm all its rollout pools exited, before this diagnostic'
    assert not (OUT/'preflight.json').exists(),'Never overwrite prior diagnostic evidence'
    for p,h in json.loads((OUT/'build_manifest.json').read_text()).items():assert sha(ROOT/p)==h,p
    p=read_params(OUT/'reference/v3-params.txt');zero={**p,**{f'gpt_w{i}':0. for i in range(20)}}
    probe={**p,**{f'gpt_w{i}':[.05,.1,-.1,.08,-.08][i%5] for i in range(20)}}
    jobs=[]
    for seed in SEEDS:
        jobs += [('baseline','pure',p,seed,True),('zero_pure','pure',{**zero,'gpt_temporal':0.},seed,False),('zero_tcn','tcn',{**zero,'gpt_temporal':1.},seed,False),('probe_pure','pure',{**probe,'gpt_temporal':0.},seed,False),('probe_tcn','tcn',{**probe,'gpt_temporal':1.},seed,False)]
    rows=[]
    with mp.get_context('spawn').Pool(3) as pool:
        for job,result in zip(jobs,pool.imap(run,jobs,chunksize=1)):
            assert 'error' not in result[1],result
            rows.append({'label':job[0],'variant':job[1],'seed':job[3],'score':result[0],'metrics':result[1]})
    (OUT/'rollouts.json').write_text(json.dumps(jsonable(rows),indent=2)+'\n')
    task=TASK();m=mujoco.MjModel.from_xml_string(task.xml(task.builder()))
    joints={name:int(m.joint(name).qposadr[0]) for side in ['r','l'] for name in [side+'_elbow',side+'_wrist_flex',side+'_finger_mcp',side+'_finger_pip']}
    checks={'fingered_body_present':len(joints)==8};detail={}
    for seed in SEEDS:
        traces={label:np.load(OUT/f'{label}_{seed}.npz') for label in ['baseline','zero_pure','zero_tcn','probe_pure','probe_tcn']}
        for label in ['zero_pure','zero_tcn']:
            equal={k:bool(np.array_equal(traces['baseline'][k],traces[label][k])) for k in ['command','measured','activation','labels','q']}
            checks[f'{label}_{seed}_exact_baseline']=all(equal.values());detail[f'{label}_{seed}_exact']=equal
        for label in ['probe_pure','probe_tcn']:
            d=traces[label];z=traces['baseline'];effects={k:float(np.max(np.abs(d[k]-z[k]))) for k in ['command','measured','activation','q']}
            joint_effects={name:float(np.max(np.abs(d['q'][:,adr]-z['q'][:,adr]))) for name,adr in joints.items()}
            checks[f'{label}_{seed}_changes_measured_motion']=all(x>1e-8 for x in effects.values())
            checks[f'{label}_{seed}_changes_both_fingers']=all(joint_effects[name]>1e-8 for name in joints if 'finger' in name)
            detail[f'{label}_{seed}_effects']={'full_trajectory':effects,'joint_q_radians':joint_effects}
    ms=[r['metrics'] for r in rows]
    checks['whole_fifteen_second_runs']=all(15<=m['time']<15.02 for m in ms)
    checks['bounded_requests']=all(all(0<=x<=b+1e-9 for x,b in zip(m['residual_peak_rad'],[.18,.15,.2,.2])) for m in ms)
    report={'passed':all(checks.values()),'checks':checks,'details':detail,'scope':'Untrained integration diagnostic on the existing fingered v3 body. Seeds reuse R9 identifiers but these are new body-specific diagnostics, not fresh validation. No arena or technique-improvement claim. Model and task differ from the paddle-hand R9/R10 controllers, so scores are not direct architecture comparisons.'}
    (OUT/'preflight.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));assert report['passed'],checks
if __name__=='__main__':main()
