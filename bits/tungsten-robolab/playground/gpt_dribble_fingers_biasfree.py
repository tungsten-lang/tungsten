"""Round 12: retrain fingered policies with global residual offsets fixed at zero."""
import argparse,hashlib,json,multiprocessing as mp,os,shutil,time
from datetime import datetime,timezone
from pathlib import Path
import gpt_competitor as base
import numpy as np
from search import BoxRep,Problem,Search,describe,read_params,jsonable
from gpt_dribble_catch import compact
import gpt_dribble_fingers as r11

ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round12';PARAMS=ROOT/'params/competitor_dribble_round12'
REFERENCE=ROOT/'out/competitor_dribble_round11/reference'
TRAIN=list(range(294101,294133));VALID=list(range(295101,295165));SECONDS=15.;BUDGET=4096;OPTSEED=281935
BACKBONE=['hand_fb','hand_vfb','reach','carry_track','c_kv','c_tmax','x_lead','x_kv','x_t','x_steer','f_open','f_flick']
FIXED_READOUT=[0,5,10,15]
NAMES=BACKBONE+[f'gpt_w{i}' for i in range(20) if i not in FIXED_READOUT]
GROUPS=['pure_biasfree','tcn_biasfree','common_zero']
TRIALS=['dribble_crossover_25','dribble_crossover','dribble_arms_only']
MAIN=Path('/Users/erik/tungsten/bits/tungsten-robolab')

def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def source_controller(v):return str(ROOT/f'bin/challengers/gpt-dribble-fingers-{v}')
def controller(v):return str(ROOT/f'bin/challengers/gpt-dribble-fingers-round12-{v}')
def initial(v):return {**read_params(OUT/'reference/v3-params.txt'),**{f'gpt_w{i}':0. for i in range(20)},'gpt_temporal':float(v=='tcn')}
def fixed_match(p,v):return all(p.get(k)==value for k,value in initial(v).items() if k not in NAMES) and not(set(p)-set(initial(v))-set(NAMES))
def manifest_paths():
    return [
        'playground/gpt_dribble_fingers_biasfree.py','playground/gpt_dribble_fingers.py',
        'playground/gpt_competitor.py','playground/search.py','playground/gpt_dribble_catch.py',
        'lib/entry/gpt_dribble_fingers.w','lib/robolab/skills/gpt_finger_dribble.w',
        'lib/robolab/skills/gpt_temporal.w','out/competitor_dribble_round12/reference/v3-params.txt',
        'out/competitor_dribble_round12/reference/v3-controller','out/competitor_dribble_round12/protocol.json',
        'out/competitor_dribble_round12/trials_before.json',
        'bin/challengers/gpt-dribble-fingers-pure','bin/challengers/gpt-dribble-fingers-tcn',
        'bin/challengers/gpt-dribble-fingers-round12-pure','bin/challengers/gpt-dribble-fingers-round12-tcn',
        'out/competitor_dribble_round11/audit.json','out/competitor_dribble_round11/summary.json',
        'playground/arena/trials.json','playground/arena/champions.json',
        'playground/arena.py','playground/gpt_arena_entry.py','playground/tasks/dribble_v3.py'
    ]
def check_manifest():
    for path,digest in read(OUT/'manifest.json').items():assert sha(ROOT/path)==digest,path
    for path,digest in read(OUT/'judge_manifest.json').items():assert sha(ROOT/path)==digest,path

def prepare():
    OUT.mkdir(parents=True,exist_ok=True);PARAMS.mkdir(parents=True,exist_ok=True)
    if (OUT/'protocol.json').exists():raise AssertionError('Never replace a frozen Round 12 protocol')
    source_paths=['playground/gpt_dribble_fingers_biasfree.py','playground/gpt_dribble_fingers.py','playground/gpt_competitor.py','playground/search.py','playground/gpt_dribble_catch.py','lib/entry/gpt_dribble_fingers.w','lib/robolab/skills/gpt_finger_dribble.w','lib/robolab/skills/gpt_temporal.w','out/competitor_dribble_round11/audit.json','out/competitor_dribble_round11/summary.json','out/competitor_dribble_round11/reference/v3-params.txt','out/competitor_dribble_round11/reference/v3-controller','bin/challengers/gpt-dribble-fingers-pure','bin/challengers/gpt-dribble-fingers-tcn','playground/arena/trials.json','playground/arena/champions.json','playground/arena.py','playground/gpt_arena_entry.py','playground/tasks/dribble_v3.py']
    missing=[p for p in source_paths if not (ROOT/p).is_file()]
    if missing:raise FileNotFoundError(missing)
    if any((OUT/name).exists() for name in ['pure.jsonl','tcn.jsonl','candidates.json','validation.json','endurance30.json','arena_summary.json']):
        raise AssertionError('Round 12 already has candidate or run artifacts; inspect before continuing')
    (OUT/'reference').mkdir(exist_ok=True)
    shutil.copy2(REFERENCE/'v3-params.txt',OUT/'reference/v3-params.txt')
    shutil.copy2(REFERENCE/'v3-controller',OUT/'reference/v3-controller')
    trials=read(ROOT/'playground/arena/trials.json')
    if set(TRIALS)-set(trials):raise AssertionError('A frozen Round 12 trial is missing')
    (OUT/'trials_before.json').write_bytes((ROOT/'playground/arena/trials.json').read_bytes())
    for v in ['pure','tcn']:
        shutil.copy2(source_controller(v),controller(v))
    protocol={
        'round':12,'problem':'Sustained crossover control with fingered hands and quiet trunk',
        'intervention':'Retrain both residual families with four constant output offsets fixed at zero; rebound handling is unchanged.',
        'task':'dribble_v3','trials':TRIALS,'training_seeds':TRAIN,'validation_seeds':VALID,
        'endurance_seeds':VALID[:8],'training_rollouts_per_family':BUDGET,'seconds':SECONDS,
        'optimizer':'oneplusone','optimizer_seed':OPTSEED,'sigma':0.02,'risk':0.5,'workers':3,
        'train_order':['pure','tcn'],'backbone_parameters':BACKBONE,
        'optimized_readout_parameters':[f'gpt_w{i}' for i in range(20) if i not in FIXED_READOUT],
        'fixed_readout_offsets':[f'gpt_w{i}' for i in FIXED_READOUT],
        'tunable_dimensions':len(NAMES),'validation_groups':GROUPS,
        'promotion_gate':'Arena is sole judge; complete all six candidate entries before promotion; candidate must beat both local and current main frontiers.'
    }
    write('protocol.json',protocol)
    pinned=manifest_paths();missing=[p for p in pinned if not (ROOT/p).is_file()]
    if missing:raise FileNotFoundError(missing)
    write('manifest.json',{p:sha(ROOT/p) for p in pinned})
    judge_paths=['playground/arena/trials.json','playground/arena.py','playground/gpt_arena_entry.py',
        'playground/tasks/dribble_v3.py','lib/entry/gpt_dribble_fingers.w',
        'lib/robolab/skills/gpt_finger_dribble.w','lib/robolab/skills/gpt_temporal.w',
        'out/competitor_dribble_round12/trials_before.json',
        'bin/challengers/gpt-dribble-fingers-round12-pure','bin/challengers/gpt-dribble-fingers-round12-tcn']
    write('judge_manifest.json',{p:sha(ROOT/p) for p in judge_paths})
    write('pipeline_state.json',{'state':'prepared','at':datetime.now(timezone.utc).isoformat()})
    print(json.dumps({'protocol':str(OUT/'protocol.json'),'manifest_files':len(pinned),'judge_files':len(judge_paths)},indent=2))

def score(m):return r11.score(m)
def run(job):
    label,v,p,seed,seconds,trace=job
    base.OUT=OUT;base.CONFIG={**base.CONFIG,'dribble':('dribble_v3','dribble_crossover_25',SECONDS,[])}
    base.ctl_path=lambda problem,mode:controller(mode)
    _,m,wall=base.run(('dribble',v,p,seed,seconds,{'trace':trace} if trace else {}))
    return (-1e9 if 'error' in m else score(m)),m,wall
class BiasFreeProblem(Problem):
    def __init__(self,v,rep):super().__init__('dribble_v3',rep,TRAIN,SECONDS,risk=0.5);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.v,self.rep.decode(x),s,SECONDS,None) for s in (seeds or self.seeds)]

def preflight():
    checks={};representations={};r11audit=read(ROOT/'out/competitor_dribble_round11/audit.json')
    checks['round11_audit_passes']=r11audit.get('passed') is True and len(r11audit.get('checks',{}))==44
    checks['round11_did_not_promote']=read(ROOT/'out/competitor_dribble_round11/promotions.json')==[]
    frozen=read(ROOT/'out/competitor_dribble_round11/candidates.json')
    checks['controller_hashes_match_round11']=all(sha(controller(v))==next(c['controller_sha256'] for c in frozen if c['variant']==v) for v in ['pure','tcn'])
    checks['trial_snapshot_unchanged']=(ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    main_trials=read(MAIN/'playground/arena/trials.json');local_trials=read(OUT/'trials_before.json')
    checks['main_trials_match_local']=all(local_trials.get(t)==main_trials.get(t) for t in TRIALS)
    checks['protocol_dimensions_are_28']=len(NAMES)==28 and len(set(NAMES))==28
    for v in ['pure','tcn']:
        p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
        rep=BoxRep.from_tunables(describe('dribble_v3',p),only=NAMES,init=p);decoded=rep.decode(rep.x0)
        checks[v+'_exactly_28_tunables']=rep.n==28 and set(rep.names)==set(NAMES)
        checks[v+'_four_offsets_fixed_zero']=all(decoded[f'gpt_w{i}']==0.0 for i in FIXED_READOUT)
        checks[v+'_initialization_exact']=all(decoded[k]==val for k,val in p.items())
        checks[v+'_undeclared_parameters_fixed']=fixed_match(decoded,v)
        representations[v]={'names':rep.names,'lo':rep.lo.tolist(),'hi':rep.hi.tolist(),'initial':decoded}
        write(v+'_representation.json',representations[v])
    checks['matched_boxes']=all(representations['pure'][k]==representations['tcn'][k] for k in ['names','lo','hi'])
    checks['common_start_backbone']=all(v==initial('tcn')[k] for k,v in initial('pure').items() if k!='gpt_temporal')
    checks['round11_validation_protocol_precedent']=read(ROOT/'out/competitor_dribble_round11/protocol.json')['validation_groups']==['pure','pure_bias','pure_zero','tcn','tcn_bias','tcn_zero','common_zero']
    old=set();old_optimizer=set()
    for f in (ROOT/'out').glob('competitor*/**/*protocol.json'):
        if f==OUT/'protocol.json':continue
        d=read(f)
        if isinstance(d.get('optimizer_seed'),int):old_optimizer.add(d['optimizer_seed'])
        for k,v in d.items():
            if k in ['training_seeds','validation_seeds','training','validation','pilot_seeds','parity_seeds','endurance_seeds'] and isinstance(v,list):old.update(x for x in v if isinstance(x,int))
    old.update(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds'])
    checks['new_train_and_validation_seeds_disjoint']=not(set(TRAIN)&set(VALID)) and not((set(TRAIN)|set(VALID))&old)
    checks['new_optimizer_seed']=OPTSEED not in old_optimizer
    checks['three_trial_definitions_present']=set(TRIALS)<=set(read(ROOT/'playground/arena/trials.json'))
    report={'passed':all(checks.values()),'checks':checks,'scope':'Static protocol and parameter-description checks only; no rollout, training or validation was started.'}
    write('preflight.json',report);print(json.dumps(report,indent=2));assert report['passed']

def train(v):
    assert read(OUT/'preflight.json')['passed'];assert v in ['pure','tcn']
    assert not (OUT/f'{v}.jsonl').exists(),'Never restart a search from a partial log'
    assert not (PARAMS/f'{v}_biasfree.txt').exists(),'Never overwrite a frozen parameter search'
    p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
    rep=BoxRep.from_tunables(describe('dribble_v3',p),only=NAMES,init=p)
    assert rep.n==28 and fixed_match(rep.decode(rep.x0),v)
    search=Search(BiasFreeProblem(v,rep),'oneplusone',BUDGET,OPTSEED,.02,out=str(PARAMS/f'{v}_biasfree.txt'),log=str(OUT/f'{v}.jsonl'),archive=str(OUT/f'{v}.npz'),label='gpt: bias-free fingered crossover '+v)
    print('BEGIN',v,rep.n,BUDGET,flush=True)
    with mp.get_context('spawn').Pool(3) as pool:
        while not search.done:
            jobs=search.next_jobs()
            if not jobs:break
            results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
            search.consume(results)
            if search.gen%4==0 or search.gen==1 or search.done:print(v,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
    result=search.summary();assert result['used']==BUDGET and fixed_match(result['params'],v)
    write(f'{v}.json',result);write('pipeline_state.json',{'state':'training_complete','variant':v,'used':result['used']})
    print('FINAL',v,json.dumps(compact([{'metrics':m} for m in result['metrics']])),flush=True)

def freeze():
    assert not (OUT/'candidates.json').exists()
    registry=[]
    for v in ['pure','tcn']:
        result=read(OUT/f'{v}.json');assert result['used']==BUDGET and fixed_match(result['params'],v)
        p=read_params(PARAMS/f'{v}_biasfree.txt');assert p==result['params']
        dest=PARAMS/f'{v}_biasfree_frozen.txt';shutil.copy2(PARAMS/f'{v}_biasfree.txt',dest)
        registry.append({'label':v+'_biasfree','variant':v,'task':'dribble_v3','fixed_readout_offsets':[f'gpt_w{i}' for i in FIXED_READOUT],
            'params':p,'params_file':str(dest),'params_sha256':sha(dest),'controller':controller(v),'controller_sha256':sha(controller(v))})
    write('candidates.json',registry);write('pipeline_state.json',{'state':'candidates_frozen'})

def evaluate_groups(action):
    assert not (OUT/('validation.json' if action=='validate' else 'endurance30.json')).exists()
    registry=read(OUT/'candidates.json');groups=[]
    for c in registry:
        assert sha(c['params_file'])==c['params_sha256'] and sha(c['controller'])==c['controller_sha256']
        assert fixed_match(c['params'],c['variant'])
        groups.append((c['label'],c['variant'],c['params']))
    groups.append(('common_zero','pure',initial('pure')))
    if action=='validate':assert [g[0] for g in groups]==GROUPS
    else:assert (OUT/'validation.json').exists()
    seeds=VALID if action=='validate' else VALID[:8];seconds=SECONDS if action=='validate' else 30.
    name='validation' if action=='validate' else 'endurance30'
    jobs=[(label,v,p,seed,seconds,str(OUT/f'{name}_{label}.npz') if seed==seeds[0] else None) for label,v,p in groups for seed in seeds]
    rows=[]
    with mp.get_context('spawn').Pool(3) as pool:
        for idx,(job,result) in enumerate(zip(jobs,pool.imap(run,jobs,chunksize=1)),1):
            assert 'error' not in result[1],result
            rows.append({'label':job[0],'seed':job[3],'score':result[0],'metrics':result[1]})
            if idx%32==0 or idx==len(jobs):print(name,idx,'/',len(jobs),flush=True)
    write(name+'.json',rows);summary={label:compact([r for r in rows if r['label']==label]) for label,_,_ in groups}
    write(name+'_summary.json',summary);write('pipeline_state.json',{'state':name+'_complete','rows':len(rows)})
    print(json.dumps(summary),flush=True)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['prepare','check','train','freeze','validate','long']);ap.add_argument('variant',choices=['pure','tcn'],nargs='?');a=ap.parse_args()
    if a.action=='prepare':prepare();return
    check_manifest()
    if a.action=='check':preflight();return
    if a.action=='freeze':freeze();return
    if a.action=='train':assert a.variant;train(a.variant);return
    if a.action in ['validate','long']:evaluate_groups(a.action);return
    raise AssertionError(a.action)
if __name__=='__main__':main()
