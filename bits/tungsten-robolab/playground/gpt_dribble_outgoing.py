"""Round 10: matched outgoing-stroke refinement with inherited heads fixed."""
import argparse,hashlib,json,multiprocessing as mp,os,shutil,time
from pathlib import Path
import gpt_competitor as base
import numpy as np
from search import BoxRep,Problem,Search,describe,read_params,jsonable
from gpt_dribble_catch import score,compact
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round10';PARAMS=ROOT/'params/competitor_dribble_round10'
TRAIN=list(range(290101,290117));VALID=list(range(291101,291165));SECONDS=15.;BUDGET=2048
NAMES=['x_dx','x_y','x_kv','x_t','x_tmax','x_steer','x_dxl','x_dyl','x_roll','z_low','pitch_low','t_push']
GROUPS=['pure','pure_previous','pure_bias','pure_zero','tcn','tcn_previous','tcn_bias','tcn_zero']
def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def controller(v):return str(ROOT/f'bin/challengers/gpt-dribble-outgoing-{v}')
def initial(v):return read_params(OUT/f'reference/{v}.txt')
def fixed_match(p,v):
    original=initial(v)
    return all(p.get(k)==value for k,value in original.items() if k not in NAMES) and not (set(p)-set(original)-set(NAMES))
def run(job):
    label,v,p,seed,seconds,trace=job
    base.OUT=OUT;base.ctl_path=lambda problem,mode:controller(mode)
    _,m,wall=base.run(('dribble',v,p,seed,seconds,{'trace':trace} if trace else {}))
    return (-1e9 if 'error' in m else score(m)),m,wall
class OutgoingProblem(Problem):
    def __init__(self,v,rep):super().__init__('dribble',rep,TRAIN,SECONDS,risk=.5);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.v,self.rep.decode(x),s,SECONDS,None) for s in (seeds or self.seeds)]
def check_manifest():
    for p,h in read(OUT/'manifest.json').items():assert sha(ROOT/p)==h,p

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['check','train','freeze','validate','long']);ap.add_argument('variant',choices=['pure','tcn'],nargs='?');a=ap.parse_args();check_manifest()
    if a.action=='check':
        checks={};reps={}
        assert not (OUT/'preflight.json').exists(),'Preserve completed preflight'
        for v in ['pure','tcn']:
            p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            rep=BoxRep.from_tunables(describe('dribble',p),only=NAMES,init=p)
            checks[v+'_twelve_dimensions']=rep.n==12 and set(rep.names)==set(NAMES)
            checks[v+'_initialization_exact']=all(abs(rep.decode(rep.x0)[k]-val)<1e-12 for k,val in p.items())
            checks[v+'_copied_binary_matches_parent']=sha(controller(v))==sha(ROOT/f'bin/challengers/gpt-dribble-catch-{v}')
            checks[v+'_fixed_heads_and_catch']=fixed_match(rep.decode(rep.x0),v)
            reps[v]={'names':rep.names,'lo':rep.lo.tolist(),'hi':rep.hi.tolist(),'initial':rep.decode(rep.x0)}
            write(f'{v}_representation.json',reps[v])
        checks['same_dimensions_and_ranges']=all(reps['pure'][k]==reps['tcn'][k] for k in ['names','lo','hi'])
        checks['r9_audit_passes']=read(ROOT/'out/competitor_dribble_round9/audit.json')['passed']
        checks['new_train_and_validation_disjoint']=not(set(TRAIN)&set(VALID)) and min(TRAIN)>289132
        report={'passed':all(checks.values()),'checks':checks,'scope':'No dynamics or controller source changes. Exact frozen binary copies and parent parameters preserve the already-audited R9 integration. New training starts are not used in this check.'}
        write('preflight.json',report);print(json.dumps(report,indent=2));assert report['passed'];return
    if a.action=='freeze':
        assert not (OUT/'candidates.json').exists()
        reg=[]
        for v in ['pure','tcn']:
            result=read(OUT/f'{v}.json');assert result['used']==BUDGET
            p=read_params(PARAMS/f'{v}.txt');assert p==result['params'] and fixed_match(p,v)
            dest=PARAMS/f'{v}_frozen.txt';shutil.copy2(PARAMS/f'{v}.txt',dest)
            reg.append({'label':v,'variant':v,'params':p,'params_file':str(dest),'params_sha256':sha(dest),'controller':controller(v),'controller_sha256':sha(controller(v))})
        write('candidates.json',reg);return
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            assert a.variant and read(OUT/'preflight.json')['passed'];v=a.variant
            assert not (OUT/f'{v}.jsonl').exists(),'Never restart a training search'
            p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            rep=BoxRep.from_tunables(describe('dribble',p),only=NAMES,init=p)
            assert rep.n==12 and fixed_match(rep.decode(rep.x0),v)
            search=Search(OutgoingProblem(v,rep),'oneplusone',BUDGET,280934,.015,out=str(PARAMS/f'{v}.txt'),log=str(OUT/f'{v}.jsonl'),archive=str(OUT/f'{v}.npz'),label='gpt: outgoing crossover '+v)
            print('BEGIN',v,rep.n,BUDGET,flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
                search.consume(results)
                if search.gen%8==0 or search.gen==1 or search.done:print(v,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
            result=search.summary();assert result['used']==BUDGET and fixed_match(result['params'],v)
            write(f'{v}.json',result);print('FINAL',v,json.dumps(compact([{'metrics':m} for m in result['metrics']])),flush=True)
        else:
            name='validation' if a.action=='validate' else 'endurance30';assert not (OUT/(name+'.json')).exists()
            reg=read(OUT/'candidates.json');groups=[]
            for r in reg:
                assert sha(r['params_file'])==r['params_sha256'] and sha(r['controller'])==r['controller_sha256']
                v=r['variant'];p=r['params'];assert fixed_match(p,v)
                groups.extend([(v,v,p),(v+'_previous',v,initial(v))])
                if a.action=='validate':
                    groups.append((v+'_bias',v,{**p,**{f'gpt_w{i}':0. for i in range(20) if i%5}}))
                    groups.append((v+'_zero',v,{**p,**{f'gpt_w{i}':0. for i in range(20)}}))
            if a.action=='validate':assert [g[0] for g in groups]==GROUPS
            else:assert (OUT/'validation.json').exists()
            seeds=VALID if a.action=='validate' else VALID[:8];seconds=SECONDS if a.action=='validate' else 30.
            jobs=[(label,v,p,s,seconds,f'{name}_{label}.npz' if s==seeds[0] else None) for label,v,p in groups for s in seeds]
            rows=[]
            for idx,(j,r) in enumerate(zip(jobs,pool.imap(run,jobs,chunksize=1)),1):
                assert 'error' not in r[1],r
                rows.append({'label':j[0],'seed':j[3],'score':r[0],'metrics':r[1]})
                if idx%32==0 or idx==len(jobs):print(name,idx,'/',len(jobs),flush=True)
            write(name+'.json',rows)
            summary={label:compact([r for r in rows if r['label']==label]) for label,_,_ in groups}
            write(name+'_summary.json',summary);print(json.dumps(summary),flush=True)
    check_manifest()
if __name__=='__main__':main()
