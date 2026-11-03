"""Round 7: matched mean-score launch/support refinement with frozen heads."""
import argparse,hashlib,json,multiprocessing as mp,os,shutil,time
from pathlib import Path
import gpt_competitor as base
from gpt_jump_adaptive import CaptureSim
from gpt_jump_recover import legal
from gpt_jump_support_validate import compact
from search import BoxRep,Problem,Search,describe,read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_jump_round7';PARAMS=ROOT/'params/competitor_jump_round7'
TRAIN=list(range(284101,284133));VALID=list(range(285101,285165));SECONDS=8.;BUDGET=2048
NAMES=['crouch_t','extend_t','to_z','drv_hip','drv_arm','stand_t','stand_hip_flex','stand_knee','stand_ankle','gpt_support_time','gpt_support_height','gpt_support_gain']
def read(p):return json.loads(Path(p).read_text())
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def controller(v):return str(ROOT/f'bin/challengers/gpt-jump-mean-refine-{v}')
def initial(v):return read_params(OUT/f'reference/{v}.txt')
def run(job):
    label,v,p,seed,seconds,trace,reference=job
    base.OUT=OUT;base.Sim=CaptureSim;base.ctl_path=lambda task,mode:str(ROOT/'out/competitor_jump_round4/reference/p6-controller') if reference else controller(mode)
    _,m,wall=base.run(('jump',v,p,seed,seconds,{'trace':trace} if trace else {}))
    if 'error' in m:return -1e9,m,wall
    e=m['three_second'];ok3=legal(e);ok8=legal(m)
    penalty=.01*max(m['peak_grf_bw']-4,0)**2+.0002*max(m['peak_loading_bw_s']-100,0)
    score=100*ok3+20*max(e.get('mark',0),0)*ok3+2*ok8+.5*max(m.get('mark',0),0)*ok8-penalty
    return score,m,wall
class RefineProblem(Problem):
    def __init__(self,v,rep):super().__init__('search_jump_v3',rep,TRAIN,SECONDS,risk=0.);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.v,self.rep.decode(x),s,SECONDS,None,False) for s in (seeds or self.seeds)]
def check_manifest():
    for p,h in read(OUT/'manifest.json').items():assert sha(ROOT/p)==h,p

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['train','freeze','validate','long']);ap.add_argument('variant',choices=['pure','tcn'],nargs='?');a=ap.parse_args();check_manifest()
    if a.action=='freeze':
        registry=[]
        for v in ['pure','tcn']:
            result=read(OUT/f'{v}.json');p=read_params(PARAMS/f'{v}.txt');assert p==result['params'];dest=PARAMS/f'{v}_frozen.txt';shutil.copy2(PARAMS/f'{v}.txt',dest)
            assert all(p.get(f'gpt_w{i}',0)==initial(v).get(f'gpt_w{i}',0) for i in range(20))
            registry.append({'label':v,'variant':v,'params':p,'params_file':str(dest),'params_sha256':sha(dest),'controller':controller(v),'controller_sha256':sha(controller(v))})
        write('candidates.json',registry);return
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            assert a.variant;v=a.variant;p=initial(v);os.environ['ROBOLAB_CONTROLLER']=controller(v)
            tun=describe('search_jump_v3',p);rep=BoxRep.from_tunables(tun,only=NAMES,init=p);assert rep.n==12,rep.names
            search=Search(RefineProblem(v,rep),'oneplusone',BUDGET,280931,.008,out=str(PARAMS/f'{v}.txt'),log=str(OUT/f'{v}.jsonl'),archive=str(OUT/f'{v}.npz'),label='gpt: mean-score launch support '+v)
            write(f'{v}_representation.json',{'names':rep.names,'lo':rep.lo.tolist(),'hi':rep.hi.tolist(),'initial':rep.decode(rep.x0)})
            print('BEGIN',v,rep.n,BUDGET,flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
                search.consume(results)
                if search.gen%8==0 or search.done or search.gen==1:print(v,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
            result=search.summary();write(f'{v}.json',result)
            assert all(result['params'].get(f'gpt_w{i}',0)==p.get(f'gpt_w{i}',0) for i in range(20))
            print('FINAL',v,json.dumps(compact([{'metrics':m} for m in result['metrics']])),flush=True)
        else:
            registry=read(OUT/'candidates.json');jobs=[]
            for r in registry:assert sha(r['params_file'])==r['params_sha256'] and sha(r['controller'])==r['controller_sha256']
            if a.action=='validate':
                groups=[]
                for r in registry:
                    v=r['variant'];p=r['params'];groups.extend([(v,v,p,False),(v+'_previous',v,initial(v),False)])
                    groups.append((v+'_static',v,{**p,'gpt_support':0.,'stand_after':p['gpt_support_time'],'stand_gain':p['gpt_support_gain']},False))
                    if v=='tcn':
                        groups.append(('tcn_bias','tcn',{**p,**{f'gpt_w{i}':0. for i in range(20) if i%5}},False))
                        groups.append(('tcn_zero','tcn',{**p,**{f'gpt_w{i}':0. for i in range(20)}},False))
                groups.append(('p6_reference','pure',read_params(ROOT/'out/competitor_jump_round4/reference/p6-params.txt'),True))
                for label,v,p,ref in groups:
                    for seed in VALID:jobs.append((label,v,p,seed,8.,f'validation_{label}.npz' if seed==VALID[0] else None,ref))
            else:
                assert (OUT/'validation.json').exists()
                for r in registry:
                    for seed in VALID[:8]:jobs.append((r['label'],r['variant'],r['params'],seed,20.,f'endurance_{r["label"]}.npz' if seed==VALID[0] else None,False))
            results=[]
            for idx,(job,result) in enumerate(zip(jobs,pool.imap(run,jobs,chunksize=1)),1):
                assert 'error' not in result[1]
                results.append({'label':job[0],'seed':job[3],'score':result[0],'metrics':result[1]})
                if idx%64==0 or idx==len(jobs):print(a.action,idx,'/',len(jobs),flush=True)
            write('validation.json' if a.action=='validate' else 'endurance20.json',results)
            summary={k:compact([r for r in results if r['label']==k],8 if a.action=='validate' else 20) for k in dict.fromkeys(r['label'] for r in results)}
            write('validation_summary.json' if a.action=='validate' else 'endurance_summary.json',summary);print(json.dumps(summary),flush=True)
    check_manifest()
if __name__=='__main__':main()
