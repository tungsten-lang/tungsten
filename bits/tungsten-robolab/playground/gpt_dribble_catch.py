"""Round 9: common-backbone, matched-budget sustained crossover catching."""
import argparse,hashlib,json,multiprocessing as mp,os,shutil,time
from pathlib import Path
import gpt_competitor as base
import numpy as np
from search import BoxRep,Problem,Search,describe,read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round9';PARAMS=ROOT/'params/competitor_dribble_round9'
TRAIN=list(range(288101,288109));VALID=list(range(289101,289133));PREFLIGHT=[288001,288002]
SECONDS=15.;BUDGET=1024
NAMES=['hand_fb','hand_vfb','reach','carry_track','spring','dz_max','c_tmax','x_lead']+[f'gpt_w{i}' for i in range(20)]
def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def controller(v):return str(ROOT/f'bin/challengers/gpt-dribble-catch-{v}')
def initial(v):return {**read_params(OUT/'reference/previous-params.txt'),**{f'gpt_w{i}':0. for i in range(20)},'gpt_temporal':float(v=='tcn'),'gpt_active_phase':1.}
def score(m):
    impact=.01*max(m['peak_grf_bw']-4,0)**2+.0002*max(m['peak_loading_bw_s']-100,0)
    miss=m.get('moves',{}).get('X',{}).get('catch_miss') or 0.
    return 2*m.get('x_ok',0)+m.get('controlled_s',0)-2*m.get('moves_failed',0)-3*miss-.5*m.get('body_hits',0)-2*m.get('drift_mean',0)-3*m.get('apex_std',0)-impact

def run(job):
    label,v,p,seed,trace,old=job
    base.OUT=OUT;base.ctl_path=lambda problem,mode:str(OUT/'reference/previous-controller') if old else controller(mode)
    _,m,wall=base.run(('dribble',v,p,seed,SECONDS,{'trace':trace} if trace else {}))
    return (-1e9 if 'error' in m else score(m)),m,wall

def compact(rows):
    ms=[r['metrics'] for r in rows];out={'n':len(ms),'errors':sum('error' in m for m in ms)}
    for k in ['x_ok','dribbles','controlled_s','moves_failed','body_hits','drift_mean','apex_std','trunk_share_upper','trunk_share_if_dribbling','peak_grf_bw','peak_loading_bw_s']:
        out[k]=float(np.mean([m[k] for m in ms]))
    out['at_least_ten_dribbles']=sum(m['dribbles']>=10 for m in ms)
    out['lost']=sum(bool(m.get('lost')) for m in ms)
    out['catch_miss']=float(np.mean([m['moves']['X']['catch_miss'] for m in ms if m['moves']['X']['catch_miss'] is not None]))
    return out
class CatchProblem(Problem):
    def __init__(self,v,rep):super().__init__('dribble',rep,TRAIN,SECONDS,risk=.5);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.v,self.rep.decode(x),s,None,False) for s in (seeds or self.seeds)]
def check_manifest():
    for p,h in read(OUT/'manifest.json').items():assert sha(ROOT/p)==h,p

def preflight(pool):
    jobs=[]
    for seed in PREFLIGHT:
        zero=initial('pure');probe={**zero,**{f'gpt_w{i}':([.05,.2,-.2,.1,-.1][i%5]) for i in range(20)}}
        previous=read_params(OUT/'reference/previous-params.txt')
        groups=[('old_zero','pure',zero,True),('zero_pure','pure',zero,False),('zero_tcn','tcn',{**zero,'gpt_temporal':1.},False),('old_pure','pure',probe,True),('off_pure','pure',{**probe,'gpt_active_phase':0.},False),('active_pure','pure',probe,False),('old_tcn','tcn',previous,True),('off_tcn','tcn',{**previous,'gpt_active_phase':0.},False),('active_tcn','tcn',{**previous,'gpt_active_phase':1.},False)]
        for label,v,p,old in groups:jobs.append((label,v,p,seed,f'preflight_{label}_{seed}.npz',old))
    rows=[]
    for j,r in zip(jobs,pool.imap(run,jobs,chunksize=1)):
        assert 'error' not in r[1],r
        rows.append({'label':j[0],'seed':j[3],'score':r[0],'metrics':r[1]})
    write('preflight_rollouts.json',rows)
    checks={};detail={}
    for seed in PREFLIGHT:
        data={label:np.load(OUT/f'preflight_{label}_{seed}.npz') for label in {r['label'] for r in rows}}
        for a,b in [('old_zero','zero_pure'),('old_zero','zero_tcn'),('old_pure','off_pure'),('old_tcn','off_tcn'),('old_tcn','active_tcn')]:
            exact={k:bool(np.array_equal(data[a][k],data[b][k])) for k in ['command','measured','activation','q','labels']}
            checks[f'{seed}_{a}_{b}_exact']=all(exact.values());detail[f'{seed}_{a}_{b}']=exact
        effects={}
        for a,b in [('active_pure','off_pure'),('active_pure','zero_pure'),('active_tcn','zero_tcn')]:
            effects[a+'_'+b]={k:float(np.max(np.abs(data[a][k]-data[b][k]))) for k in ['command','measured','activation','q']}
            checks[f'{seed}_{a}_{b}_changes_motion']=all(x>1e-8 for x in effects[a+'_'+b].values())
        detail[f'{seed}_effects']=effects
        # Pure trajectories coincide until active-hand phase can affect a correction.
        a=data['active_pure'];b=data['off_pure'];idx=np.flatnonzero(np.any(a['command']!=b['command'],axis=1))
        detail[f'{seed}_first_phase_difference']={'control_index':int(idx[0]),'active_labels':a['labels'][max(0,idx[0]-2):idx[0]+3].tolist(),'old_labels':b['labels'][max(0,idx[0]-2):idx[0]+3].tolist()}
    report={'passed':all(checks.values()),'checks':checks,'details':detail};write('preflight.json',report);assert report['passed'],checks
    print('PREFLIGHT',len(checks),'checks pass',flush=True)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['preflight','train','freeze','validate']);ap.add_argument('variant',choices=['pure','tcn'],nargs='?');a=ap.parse_args();check_manifest()
    if a.action=='freeze':
        assert not (OUT/'candidates.json').exists()
        reg=[]
        for v in ['pure','tcn']:
            result=read(OUT/f'{v}.json');assert result['used']==BUDGET
            p=read_params(PARAMS/f'{v}.txt');assert p==result['params'];dest=PARAMS/f'{v}_frozen.txt';shutil.copy2(PARAMS/f'{v}.txt',dest)
            reg.append({'label':v,'variant':v,'params':p,'params_file':str(dest),'params_sha256':sha(dest),'controller':controller(v),'controller_sha256':sha(controller(v))})
        write('candidates.json',reg);return
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='preflight':preflight(pool)
        elif a.action=='train':
            assert a.variant;assert read(OUT/'preflight.json')['passed'];v=a.variant;assert not (OUT/f'{v}.jsonl').exists()
            p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            rep=BoxRep.from_tunables(describe('dribble',p),only=NAMES,init=p)
            assert rep.n==28 and set(rep.names)==set(NAMES),rep.names
            search=Search(CatchProblem(v,rep),'oneplusone',BUDGET,280933,.025,out=str(PARAMS/f'{v}.txt'),log=str(OUT/f'{v}.jsonl'),archive=str(OUT/f'{v}.npz'),label='gpt: sustained crossover '+v)
            write(f'{v}_representation.json',{'names':rep.names,'lo':rep.lo.tolist(),'hi':rep.hi.tolist(),'initial':rep.decode(rep.x0)})
            print('BEGIN',v,rep.n,BUDGET,flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
                search.consume(results)
                if search.gen%8==0 or search.gen==1 or search.done:print(v,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
            result=search.summary();write(f'{v}.json',result);print('FINAL',v,json.dumps(compact([{'metrics':m} for m in result['metrics']])),flush=True)
        else:
            assert not (OUT/'validation.json').exists()
            reg=read(OUT/'candidates.json');groups=[]
            for r in reg:
                assert sha(r['params_file'])==r['params_sha256'] and sha(r['controller'])==r['controller_sha256']
                v=r['variant'];p=r['params'];groups.append((v,v,p,False))
                groups.append((v+'_bias',v,{**p,**{f'gpt_w{i}':0. for i in range(20) if i%5}},False))
                if v=='pure':groups.append(('pure_right_phase',v,{**p,'gpt_active_phase':0.},False))
                else:groups.append(('tcn_zero',v,{**p,**{f'gpt_w{i}':0. for i in range(20)}},False))
            groups.extend([('previous','tcn',read_params(OUT/'reference/previous-params.txt'),True),('common_zero','pure',initial('pure'),False)])
            assert {g[0] for g in groups}==set(read(OUT/'protocol.json')['validation_groups'])
            jobs=[(label,v,p,s,f'validation_{label}.npz' if s==VALID[0] else None,old) for label,v,p,old in groups for s in VALID]
            rows=[]
            for idx,(j,r) in enumerate(zip(jobs,pool.imap(run,jobs,chunksize=1)),1):
                assert 'error' not in r[1],r
                rows.append({'label':j[0],'seed':j[3],'score':r[0],'metrics':r[1]})
                if idx%32==0 or idx==len(jobs):print('validate',idx,'/',len(jobs),flush=True)
            write('validation.json',rows)
            summary={label:compact([r for r in rows if r['label']==label]) for label,_,_,_ in groups};write('validation_summary.json',summary);print(json.dumps(summary),flush=True)
    check_manifest()
if __name__=='__main__':main()
