"""Round 11: common zero-head fingered-body policies, matched robust search."""
import argparse,hashlib,json,multiprocessing as mp,os,shutil,time
from pathlib import Path
import gpt_competitor as base
import numpy as np
from search import BoxRep,Problem,Search,describe,read_params,jsonable
from gpt_dribble_catch import compact
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round11';PARAMS=ROOT/'params/competitor_dribble_round11'
TRAIN=list(range(292101,292133));VALID=list(range(293101,293165));SECONDS=15.;BUDGET=4096;OPTSEED=280935
BACKBONE=['hand_fb','hand_vfb','reach','carry_track','c_kv','c_tmax','x_lead','x_kv','x_t','x_steer','f_open','f_flick']
NAMES=BACKBONE+[f'gpt_w{i}' for i in range(20)]
GROUPS=['pure','pure_bias','pure_zero','tcn','tcn_bias','tcn_zero','common_zero']
def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def controller(v):return str(ROOT/f'bin/challengers/gpt-dribble-fingers-{v}')
def initial(v):return {**read_params(OUT/'reference/v3-params.txt'),**{f'gpt_w{i}':0. for i in range(20)},'gpt_temporal':float(v=='tcn')}
def score(m):
    impact=.01*max(m['peak_grf_bw']-4,0)**2+.0002*max(m['peak_loading_bw_s']-100,0)
    miss=m.get('moves',{}).get('X',{}).get('catch_miss') or 0.
    return 2*m.get('x_ok',0)+m.get('controlled_s',0)-2*m.get('moves_failed',0)-3*miss-2*m.get('body_hits',0)-2*m.get('drift_mean',0)-3*m.get('apex_std',0)-impact-10*max(m.get('trunk_share_upper',0)-.06,0)-10*bool(m.get('fell'))
def fixed_match(p,v):return all(p.get(k)==value for k,value in initial(v).items() if k not in NAMES) and not(set(p)-set(initial(v))-set(NAMES))
def run(job):
    label,v,p,seed,seconds,trace=job
    base.OUT=OUT;base.CONFIG={**base.CONFIG,'dribble':('dribble_v3','dribble_crossover_25',SECONDS,[])}
    base.ctl_path=lambda problem,mode:controller(mode)
    _,m,wall=base.run(('dribble',v,p,seed,seconds,{'trace':trace} if trace else {}))
    return (-1e9 if 'error' in m else score(m)),m,wall
class FingerProblem(Problem):
    def __init__(self,v,rep):super().__init__('dribble_v3',rep,TRAIN,SECONDS,risk=.5);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.v,self.rep.decode(x),s,SECONDS,None) for s in (seeds or self.seeds)]
def check_manifest():
    for p,h in read(OUT/'manifest.json').items():assert sha(ROOT/p)==h,p

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['check','train','freeze','validate','long']);ap.add_argument('variant',choices=['pure','tcn'],nargs='?');a=ap.parse_args();check_manifest()
    if a.action=='check':
        assert not (OUT/'preflight.json').exists();checks={};reps={};proto=ROOT/'out/competitor_dribble_fingers_prototype'
        checks['all_fifteen_integration_checks_pass']=read(proto/'preflight.json')['passed'] and len(read(proto/'preflight.json')['checks'])==15 and all(read(proto/'preflight.json')['checks'].values())
        checks['prototype_inputs_pinned']=all(sha(ROOT/p)==h for p,h in read(proto/'build_manifest.json').items())
        for v in ['pure','tcn']:
            p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            rep=BoxRep.from_tunables(describe('dribble_v3',p),only=NAMES,init=p)
            checks[v+'_thirty_two_dimensions']=rep.n==32 and set(rep.names)==set(NAMES)
            checks[v+'_initialization_exact']=all(rep.decode(rep.x0)[k]==val for k,val in p.items())
            checks[v+'_zero_head']=all(p[f'gpt_w{i}']==0 for i in range(20))
            checks[v+'_copy_matches_checked_prototype']=sha(controller(v))==sha(ROOT/'bin/challengers/gpt-dribble-fingers-prototype')
            checks[v+'_only_declared_dimensions']=fixed_match(rep.decode(rep.x0),v)
            reps[v]={'names':rep.names,'lo':rep.lo.tolist(),'hi':rep.hi.tolist(),'initial':rep.decode(rep.x0)};write(v+'_representation.json',reps[v])
        checks['matched_boxes']=all(reps['pure'][k]==reps['tcn'][k] for k in ['names','lo','hi'])
        checks['common_backbone']=all(v==initial('tcn')[k] for k,v in initial('pure').items() if k!='gpt_temporal')
        checks['previous_round_audit_passes']=read(ROOT/'out/competitor_dribble_round10/audit.json')['passed']
        old=set()
        for f in (ROOT/'out').glob('competitor*/**/*protocol.json'):
            if f==OUT/'protocol.json':continue
            for k,v in read(f).items():
                if k in ['training_seeds','validation_seeds','training','validation','pilot_seeds','parity_seeds','endurance_seeds'] and isinstance(v,list):old.update(x for x in v if isinstance(x,int))
        old.update(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds']);old.update([289101,289102])
        checks['new_training_and_validation_disjoint']=not(set(TRAIN)&set(VALID)) and not((set(TRAIN)|set(VALID))&old)
        report={'passed':all(checks.values()),'checks':checks,'scope':'Uses the completed fifteen-check full-motion prototype integration test; no training or validation starts consumed. Both copied binaries use the same fingered body and baseline. Existing quiet-trunk code and all unsearched parameters stay fixed.'}
        write('preflight.json',report);print(json.dumps(report,indent=2));assert report['passed'];return
    if a.action=='freeze':
        assert not (OUT/'candidates.json').exists();reg=[]
        for v in ['pure','tcn']:
            result=read(OUT/f'{v}.json');assert result['used']==BUDGET
            p=read_params(PARAMS/f'{v}.txt');assert p==result['params'] and fixed_match(p,v)
            dest=PARAMS/f'{v}_frozen.txt';shutil.copy2(PARAMS/f'{v}.txt',dest)
            reg.append({'label':v,'variant':v,'task':'dribble_v3','params':p,'params_file':str(dest),'params_sha256':sha(dest),'controller':controller(v),'controller_sha256':sha(controller(v))})
        write('candidates.json',reg);return
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            assert a.variant and read(OUT/'preflight.json')['passed'];v=a.variant;assert not (OUT/f'{v}.jsonl').exists(),'Never restart a training search'
            p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            rep=BoxRep.from_tunables(describe('dribble_v3',p),only=NAMES,init=p);assert rep.n==32 and fixed_match(rep.decode(rep.x0),v)
            search=Search(FingerProblem(v,rep),'oneplusone',BUDGET,OPTSEED,.02,out=str(PARAMS/f'{v}.txt'),log=str(OUT/f'{v}.jsonl'),archive=str(OUT/f'{v}.npz'),label='gpt: fingered crossover '+v)
            print('BEGIN',v,rep.n,BUDGET,flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
                search.consume(results)
                if search.gen%4==0 or search.gen==1 or search.done:print(v,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
            result=search.summary();assert result['used']==BUDGET and fixed_match(result['params'],v)
            write(f'{v}.json',result);print('FINAL',v,json.dumps(compact([{'metrics':m} for m in result['metrics']])),flush=True)
        else:
            name='validation' if a.action=='validate' else 'endurance30';assert not (OUT/(name+'.json')).exists();reg=read(OUT/'candidates.json');groups=[]
            for r in reg:
                assert sha(r['params_file'])==r['params_sha256'] and sha(r['controller'])==r['controller_sha256']
                v=r['variant'];p=r['params'];assert fixed_match(p,v);groups.append((v,v,p))
                if a.action=='validate':
                    groups.append((v+'_bias',v,{**p,**{f'gpt_w{i}':0. for i in range(20) if i%5}}))
                    groups.append((v+'_zero',v,{**p,**{f'gpt_w{i}':0. for i in range(20)}}))
            groups.append(('common_zero','pure',initial('pure')))
            if a.action=='validate':assert [g[0] for g in groups]==GROUPS
            else:assert (OUT/'validation.json').exists()
            seeds=VALID if a.action=='validate' else VALID[:8];seconds=SECONDS if a.action=='validate' else 30.
            jobs=[(label,v,p,s,seconds,f'{name}_{label}.npz' if s==seeds[0] else None) for label,v,p in groups for s in seeds];rows=[]
            for idx,(j,r) in enumerate(zip(jobs,pool.imap(run,jobs,chunksize=1)),1):
                assert 'error' not in r[1],r;rows.append({'label':j[0],'seed':j[3],'score':r[0],'metrics':r[1]})
                if idx%32==0 or idx==len(jobs):print(name,idx,'/',len(jobs),flush=True)
            write(name+'.json',rows);summary={label:compact([r for r in rows if r['label']==label]) for label,_,_ in groups};write(name+'_summary.json',summary);print(json.dumps(summary),flush=True)
    check_manifest()
if __name__=='__main__':main()
