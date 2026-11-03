"""Future diagnostic only. Run after R9 is audited and all rollout pools exit."""
import json,multiprocessing as mp
from pathlib import Path
import gpt_competitor as base
import numpy as np
from search import read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_bat_prepare_prototype';SEEDS=[271001,271002]
CONTROLLER=ROOT/'bin/challengers/gpt-bat-prepare-prototype'

def run(job):
    label,v,p,seed,old=job
    base.OUT=OUT;base.ctl_path=lambda task,mode:str(ROOT/f'bin/challengers/gpt-bat-{mode}') if old else str(CONTROLLER)
    return base.run(('bat',v,p,seed,7.8,{'trace':f'{label}_{v}_{seed}.npz'}))

def main():
    import hashlib
    sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
    r9=ROOT/'out/competitor_dribble_round9/audit.json'
    assert r9.exists() and json.loads(r9.read_text())['passed'],'Finish and audit R9 before opening another rollout pool'
    assert not (OUT/'preflight.json').exists(),'Preserve prior preflight results; do not overwrite'
    for p,h in json.loads((OUT/'build_manifest.json').read_text()).items():assert sha(ROOT/p)==h,p
    jobs=[]
    for v in ['pure','tcn']:
        p=read_params(ROOT/f'params/competitor_20260927/bat_{v}.txt');p['gpt_temporal']=float(v=='tcn')
        zero={**p,**{f'gpt_w{i}':0. for i in range(20)}}
        for seed in SEEDS:
            for label,params,old in [('old',p,True),('off',{**p,'gpt_prepare':0.},False),('on',{**p,'gpt_prepare':1.},False),('old_zero',zero,True),('on_zero',{**zero,'gpt_prepare':1.},False)]:jobs.append((label,v,params,seed,old))
    rows=[]
    with mp.get_context('spawn').Pool(3) as pool:
        for job,result in zip(jobs,pool.imap(run,jobs,chunksize=1)):
            assert 'error' not in result[1],result
            rows.append({'label':job[0],'variant':job[1],'seed':job[3],'score':result[0],'metrics':result[1]})
    (OUT/'rollouts.json').write_text(json.dumps(jsonable(rows),indent=2)+'\n')
    checks={};details={}
    for v in ['pure','tcn']:
        for seed in SEEDS:
            traces={k:np.load(OUT/f'{k}_{v}_{seed}.npz') for k in ['old','off','on','old_zero','on_zero']}
            for left,right in [('old','off'),('old_zero','on_zero')]:
                exact={k:bool(np.array_equal(traces[left][k],traces[right][k])) for k in ['command','measured','activation','labels','q']}
                checks[f'{v}_{seed}_{left}_{right}_exact']=all(exact.values());details[f'{v}_{seed}_{left}_{right}']=exact
            release=next(r['metrics']['pitches'][0]['t_release'] for r in rows if r['label']=='old' and r['variant']==v and r['seed']==seed)
            on=traces['on'];off=traces['off'];prefix=np.arange(len(on['labels']))*.005<release-1e-9
            effects={k:float(np.max(np.abs(on[k][prefix]-off[k][prefix]))) for k in ['command','measured','activation']}
            effects['q']=float(np.max(np.abs(on['q'][on['t']<release-1e-9]-off['q'][off['t']<release-1e-9])))
            checks[f'{v}_{seed}_changes_pre_aim_measured_motion']=all(x>1e-8 for x in effects.values());details[f'{v}_{seed}_pre_release_effects']=effects
            different=np.flatnonzero(np.any(on['command']!=off['command'],axis=1))
            details[f'{v}_{seed}_first_difference']={'control_index':int(different[0]) if len(different) else None,'time':float(different[0]*.005) if len(different) else None,'label':str(off['labels'][different[0]]) if len(different) else None}
    ms=[r['metrics'] for r in rows]
    checks['full_visible_rollouts']=all(7.8<=m['time']<7.82 for m in ms)
    checks['bounded_residual_requests']=all(all(x<=b+1e-9 for x,b in zip(m['residual_peak_rad'],[.16,.16,.20,.20])) for m in ms)
    checks['consumed_starts_only']={r['seed'] for r in rows}==set(SEEDS)
    result={'passed':all(checks.values()),'checks':checks,'details':details,'scope':'Diagnostic only on two consumed R1 starts. No training or fresh validation. Passing establishes integration/parity, not smoother technique or an arena win.'}
    (OUT/'preflight.json').write_text(json.dumps(jsonable(result),indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed'],checks
if __name__=='__main__':main()
