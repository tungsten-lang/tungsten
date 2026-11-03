"""Freeze both predeclared support-pilot selections, then validate untouched starts."""
import argparse,hashlib,json,multiprocessing as mp,shutil,statistics
from pathlib import Path
import numpy as np
import gpt_competitor as base
import gpt_jump_support as study
from gpt_jump_adaptive import CaptureSim
from search import read_params,jsonable
ROOT=study.ROOT;OUT=study.OUT;VALID=study.VALID

def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def compact(rows,seconds=8):
    metrics=[r['metrics'] for r in rows];early=[m['three_second'] for m in metrics]
    good3=[m for m in early if study.legal(m)];good=[m for m in metrics if study.legal(m)]
    return {'n':len(rows),'horizon':seconds,'legal3':len(good3),'mean3':statistics.mean(m['mark'] for m in good3) if good3 else None,'legal_final':len(good),'mean_final':statistics.mean(m['mark'] for m in good) if good else None,'capture_count':sum(bool(m['capture_events']) for m in metrics),'peak_bw':statistics.mean(m['peak_grf_bw'] for m in metrics),'loading':statistics.mean(m['peak_loading_bw_s'] for m in metrics)}

def check_manifests():
    for name in ['../manifest.json','manifest.json']:
        for path,digest in read(OUT/name).items():assert sha(ROOT/path)==digest,path

def freeze():
    check_manifests();summary=read(OUT/'pilot_summary.json');dest=study.PARAMS/'frozen';dest.mkdir(exist_ok=True)
    registry=[]
    for v in ['pure','tcn']:
        rows=read(OUT/f'{v}_pilot.json');assert len(rows)==46 and summary[v]['used']==368
        assert all(len(r['rows'])==8 and {x['seed'] for x in r['rows']}==set(study.PILOT) for r in rows)
        best=max(rows,key=lambda r:r['score']);assert summary[v]['selected']==best['index']
        choices=[('recovery',best)]
        eligible=[r for r in rows if r['summary']['legal3']==8 and r['summary']['legal8']>=6]
        if eligible:
            distance=max(eligible,key=lambda r:(r['summary']['mark3'],r['score']))
            assert summary[v]['distance_alternative']['selected']==distance['index']
            if distance['params']!=best['params']:choices.append(('distance',distance))
        for choice,row in choices:
            path=study.PARAMS/(v+('_distance' if choice=='distance' else '')+'.txt')
            params=read_params(path);assert params==row['params']
            assert all(params.get(k)==value for k,value in study.initial(v).items()),'Non-gate parameter changed'
            label=v+'_'+choice;frozen=dest/(label+'.txt');shutil.copy2(path,frozen)
            registry.append({'label':label,'variant':v,'choice':choice,'pilot_index':row['index'],'training':row['summary'],'controller':study.controller(v),'params_file':str(frozen),'params':params,'params_sha256':sha(frozen),'controller_sha256':sha(study.controller(v))})
    write('candidates.json',registry)
    protocol={'validation_seeds':VALID,'seconds':8,'workers':3,'previous':'Pinned round-2 policy with support gate disabled.','groups':'Each unique selected candidate, its static timing/gain counterpart, and temporal bias-only/zero-head ablations; shared previous controls and pinned P6 reference.','endurance_seeds':VALID[:8],'endurance_seconds':20,'duplicates':'Identical recovery and distance parameter selections are evaluated once.','selection':'Both recovery and distance rules were frozen in support/protocol.json before the pilot and before validation.'}
    write('validation_protocol.json',protocol)
    write('validation_manifest.json',{'files':{str(Path(__file__).resolve().relative_to(ROOT)):sha(__file__),str((OUT/'candidates.json').relative_to(ROOT)):sha(OUT/'candidates.json'),str((OUT/'validation_protocol.json').relative_to(ROOT)):sha(OUT/'validation_protocol.json')},'candidate_files':{r['params_file']:r['params_sha256'] for r in registry}})
    print('FROZEN',json.dumps([{k:r[k] for k in ['label','pilot_index','training']} for r in registry]),flush=True)

def run(job):
    label,variant,params,seed,seconds,trace,reference=job
    if reference:
        base.OUT=OUT;base.Sim=CaptureSim;base.ctl_path=lambda task,mode:str(ROOT/'out/competitor_jump_round4/reference/p6-controller')
        result=base.run(('jump','pure',params,seed,seconds,{'trace':trace} if trace else {}))
        score=None
    else:
        result=study.run((variant,params,seed,seconds,False,trace));score=result[0]
    assert 'error' not in result[1],result[1]
    return {'label':label,'variant':variant,'seed':seed,'score':score,'metrics':result[1]}

def check_frozen():
    check_manifests();m=read(OUT/'validation_manifest.json')
    for path,digest in m['files'].items():assert sha(ROOT/path)==digest,path
    for path,digest in m['candidate_files'].items():assert sha(path)==digest,path
    registry=read(OUT/'candidates.json')
    for r in registry:assert sha(r['controller'])==r['controller_sha256']
    ref=ROOT/'out/competitor_jump_round4';m=read(ref/'reference/manifest.json')
    for path,digest in m['files'].items():assert sha(ref/path)==digest,path
    return registry

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['freeze','validate','long']);a=ap.parse_args()
    if a.action=='freeze':freeze();return
    registry=check_frozen();jobs=[]
    if a.action=='validate':
        groups=[]
        for v in ['pure','tcn']:groups.append((v+'_previous',v,{**study.initial(v),'gpt_support':0.},False))
        for r in registry:
            p=r['params'];label=r['label'];v=r['variant'];groups.append((label,v,p,False))
            static={**p,'gpt_support':0.,'stand_after':p.get('gpt_support_time',p['stand_after']),'stand_gain':p.get('gpt_support_gain',p['stand_gain'])}
            groups.append((label+'_static',v,static,False))
            if v=='tcn':
                groups.append((label+'_bias','tcn',{**p,**{f'gpt_w{i}':0. for i in range(20) if i%5}},False))
                groups.append((label+'_zero','tcn',{**p,**{f'gpt_w{i}':0. for i in range(20)}},False))
        groups.append(('p6_reference','pure',read_params(ROOT/'out/competitor_jump_round4/reference/p6-params.txt'),True))
        for label,v,p,ref in groups:
            for seed in VALID:jobs.append((label,v,p,seed,8.,f'validation_{label}.npz' if seed==VALID[0] else None,ref))
    else:
        assert (OUT/'validation.json').exists()
        for r in registry:
            for seed in VALID[:8]:jobs.append((r['label'],r['variant'],r['params'],seed,20.,f'endurance_{r["label"]}.npz' if seed==VALID[0] else None,False))
    results=[]
    with mp.get_context('spawn').Pool(3) as pool:
        for index,row in enumerate(pool.imap(run,jobs,chunksize=1),1):
            results.append(row)
            if index%64==0 or index==len(jobs):print(a.action,index,'/',len(jobs),flush=True)
    filename='validation.json' if a.action=='validate' else 'endurance20.json';write(filename,results)
    summaries={label:compact([r for r in results if r['label']==label],8 if a.action=='validate' else 20) for label in dict.fromkeys(r['label'] for r in results)}
    write('validation_summary.json' if a.action=='validate' else 'endurance_summary.json',summaries)
    for label,s in summaries.items():print(label,json.dumps(s),flush=True)
if __name__=='__main__':main()
